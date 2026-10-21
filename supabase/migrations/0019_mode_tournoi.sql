-- =============================================================
-- 0019 — Le tournoi : chacun est le sujet à son tour
--
-- Extension naturelle du mode sujet. Là-bas, une seule personne est
-- devinée et ne marque jamais ; ici le sujet TOURNE, chacun passe
-- sur le gril pour quelques questions, et marque des points comme
-- challenger le reste du temps. Un seul classement à la fin :
-- qui connaît le mieux le groupe.
--
-- Presque aucun code nouveau : le sujet devient une propriété DU
-- TOUR et non de la partie, et toute la mécanique du mode sujet
-- s'applique telle quelle.
-- =============================================================

alter table parties drop constraint parties_mode_jeu_check;
alter table parties add constraint parties_mode_jeu_check
  check (mode_jeu in ('binomes','sujet','duel','tournoi'));

-- Le sujet du tour. Null = on retombe sur le sujet de la partie.
alter table tours add column sujet_id uuid references joueurs on delete set null on update cascade;

create or replace function sujet_du_tour(p_tour uuid)
returns uuid language sql security definer stable
set search_path = public, pg_temp as $$
  select coalesce(t.sujet_id, p.sujet_id)
  from tours t join parties p on p.id = t.partie_id
  where t.id = p_tour;
$$;
revoke all on function sujet_du_tour(uuid) from public, anon, authenticated;

-- -------------------------------------------------------------
-- Lancement
-- -------------------------------------------------------------
create or replace function rpc_lancer_tournoi(p_format text default 'court')
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  p parties; v_partie uuid; j record; m text;
  n_par_sujet int; n_paires int; v_joueurs int;
  v_tirage jsonb; v_bid uuid;
  couleurs text[] := array['rouge','jaune','bleu','vert','orange','violet'];
  i int := 0;
begin
  select pa.* into p from parties pa
  where pa.id = (select partie_id from joueurs where id = auth.uid())
     or pa.plateau_id = auth.uid()
  limit 1;
  if p.id is null then raise exception 'partie introuvable'; end if;
  v_partie := p.id;
  if not peut_orchestrer(v_partie) then raise exception 'non autorisé'; end if;
  if p.etat <> 'lobby' then raise exception 'la partie est déjà lancée'; end if;
  if p_format not in ('court','long') then raise exception 'format inconnu'; end if;
  if exists (select 1 from binomes where partie_id = v_partie) then
    raise exception 'ce mode se joue sans binôme';
  end if;

  select count(*) into v_joueurs from joueurs where partie_id = v_partie;
  if v_joueurs < 3 then
    raise exception 'il faut au moins trois joueurs : avec deux, c''est un duel';
  end if;
  if v_joueurs > 6 then
    raise exception 'six joueurs au maximum : au-delà, chacun attend trop longtemps son tour';
  end if;

  m := coalesce((select mode_choisi from joueurs where partie_id = v_partie
                 and mode_choisi is not null limit 1), 'zamis');

  -- Chaque sujet a SES questions : les mêmes pour tous seraient
  -- répétitives au bout du troisième passage.
  n_par_sujet := case p_format when 'court' then 2 else 3 end;   -- en paires
  n_paires := n_par_sujet * v_joueurs;

  v_tirage := jsonb_build_object(m, jsonb_build_object(
    'ouvertes', to_jsonb(tirer_paires(m,'ouverte','{}', false, n_paires)),
    'qcm', '[]'::jsonb, 'bonus', null,
    'finale', tirer_un(m,'serie_finale','{}', false),
    'citez3', '[]'::jsonb, 'sensibles', false, 'occasions', '[]'::jsonb
  ));

  -- Tout le monde marque, donc tout le monde a son « équipe » d'une personne.
  for j in select * from joueurs where partie_id = v_partie order by prenom loop
    i := i + 1;
    insert into binomes (partie_id, mode, couleur, verrouille)
    values (v_partie, m, couleurs[i], true) returning id into v_bid;
    update joueurs set binome_id = v_bid, role = 'A' where id = j.id;
  end loop;

  update parties set format = p_format, tirage = v_tirage, mode_jeu = 'tournoi',
                     sujet_id = null, etat = 'libre'
  where id = v_partie;

  perform fabriquer_tours_tournoi(v_partie, n_par_sujet);
  update parties set tour_courant = (select id from tours where partie_id = v_partie
                                     order by ordre limit 1)
  where id = v_partie;

  return jsonb_build_object('etat','libre','mode_jeu','tournoi',
                            'tours',(select count(*) from tours where partie_id = v_partie));
end $$;

-- -------------------------------------------------------------
-- Les tours : chaque joueur est sujet pour n paires d'affilée.
-- On enchaîne par sujet et non par question : « c'est au tour de
-- Camille » est plus lisible qu'une rotation à chaque question.
-- -------------------------------------------------------------
create or replace function fabriquer_tours_tournoi(p_partie uuid, p_par_sujet int)
returns int language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  p parties; m text; v_ordre int := 0; j record; k int; v_slot text; v_paire text;
  v_curseur int := 0; v_paires text[];
begin
  select * into p from parties where id = p_partie;
  delete from tours where partie_id = p_partie;
  select mode into m from binomes where partie_id = p_partie limit 1;
  select array(select x.value from jsonb_array_elements_text(p.tirage->m->'ouvertes') x)
  into v_paires;

  for j in select * from joueurs where partie_id = p_partie order by prenom loop
    for k in 1..p_par_sujet loop
      v_curseur := v_curseur + 1;
      v_paire := v_paires[v_curseur];
      foreach v_slot in array array['a','b'] loop
        v_ordre := v_ordre + 1;
        insert into tours (partie_id, ordre, manche, binome_id, question_id,
                           repondant_id, questionneur_id, sujet_id)
        values (p_partie, v_ordre, 'libre', null, v_paire || '.' || v_slot,
                null, j.id, j.id);
      end loop;
    end loop;
  end loop;
  return v_ordre;
end $$;
revoke all on function fabriquer_tours_tournoi(uuid, int) from public, anon, authenticated;

-- -------------------------------------------------------------
-- Les cinq fonctions du mode sujet passent au sujet DU TOUR.
-- -------------------------------------------------------------
create or replace function rpc_sujet_repond(p_tour uuid, p_valeur text)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare t tours; p parties; v_sujet uuid;
begin
  select * into t from tours where id = p_tour;
  if t.id is null then raise exception 'tour introuvable'; end if;
  select * into p from parties where id = t.partie_id;
  if p.mode_jeu not in ('sujet','tournoi') then raise exception 'mauvais mode de jeu'; end if;
  if p.en_pause then raise exception 'la partie est en pause'; end if;
  v_sujet := sujet_du_tour(p_tour);
  if auth.uid() <> v_sujet then raise exception 'ce n''est pas ton tour d''être le sujet'; end if;
  if t.statut <> 'attente' then raise exception 'tu as déjà répondu à cette question'; end if;
  if length(btrim(coalesce(p_valeur,''))) = 0 then raise exception 'réponse vide'; end if;

  update tours set reponse_revelee = btrim(p_valeur), statut = 'consigne' where id = p_tour;
  return jsonb_build_object('statut','consigne');
end $$;

create or replace function rpc_defier(p_tour uuid, p_valeur text)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare t tours; p parties; v_total int; v_faits int; v_motif text; v_sujet uuid;
begin
  select * into t from tours where id = p_tour;
  if t.id is null then raise exception 'tour introuvable'; end if;
  select * into p from parties where id = t.partie_id;
  if p.en_pause then raise exception 'la partie est en pause'; end if;
  v_sujet := sujet_du_tour(p_tour);
  if auth.uid() = v_sujet then raise exception 'le sujet ne se devine pas lui-même'; end if;
  if not exists (select 1 from joueurs where id = auth.uid() and partie_id = t.partie_id) then
    raise exception 'tu n''es pas dans cette partie';
  end if;
  if t.statut <> 'consigne' then
    v_motif := case t.statut when 'attente' then 'le sujet n''a pas encore répondu'
                             else 'la réponse est déjà révélée' end;
    raise exception '%', v_motif;
  end if;
  if length(btrim(coalesce(p_valeur,''))) = 0 then raise exception 'réponse vide'; end if;

  insert into reponses_manche (tour_id, joueur_id, valeur)
  values (p_tour, auth.uid(), btrim(p_valeur))
  on conflict (tour_id, joueur_id) do update set valeur = excluded.valeur, ecrit_le = now();

  select count(*) into v_total from joueurs
  where partie_id = t.partie_id and id <> v_sujet;
  select count(*) into v_faits from reponses_manche where tour_id = p_tour;
  update tours set reponses_recues = v_faits where id = p_tour;

  return jsonb_build_object('faits', v_faits, 'total', v_total,
                            'tous_ont_repondu', v_faits >= v_total);
end $$;

create or replace function rpc_reveler_defis(p_tour uuid)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare t tours; v_sujet uuid;
begin
  select * into t from tours where id = p_tour;
  if t.id is null then raise exception 'tour introuvable'; end if;
  v_sujet := sujet_du_tour(p_tour);
  if auth.uid() <> v_sujet and not peut_orchestrer(t.partie_id) then
    raise exception 'seul le sujet révèle';
  end if;
  if t.statut <> 'consigne' then raise exception 'rien à révéler'; end if;

  update reponses_manche r set juste = (normaliser(r.valeur) = normaliser(t.reponse_revelee))
  where r.tour_id = p_tour;
  update tours set statut = 'revele' where id = p_tour;

  return jsonb_build_object('statut','revele','reponse', t.reponse_revelee,
                            'reponses', (select jsonb_agg(jsonb_build_object(
                                           'joueur_id', r.joueur_id, 'valeur', r.valeur,
                                           'juste', r.juste))
                                         from reponses_manche r where r.tour_id = p_tour));
end $$;

create or replace function rpc_juger_defi(p_tour uuid, p_joueur uuid, p_juste boolean)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare t tours;
begin
  select * into t from tours where id = p_tour;
  if auth.uid() <> sujet_du_tour(p_tour) then raise exception 'seul le sujet juge'; end if;
  if t.statut <> 'revele' then raise exception 'ce tour n''est pas en jugement'; end if;
  update reponses_manche set juste = p_juste where tour_id = p_tour and joueur_id = p_joueur;
  update tours set revision = revision + 1 where id = p_tour;
  return jsonb_build_object('joueur_id', p_joueur, 'juste', p_juste);
end $$;

create or replace function rpc_clore_defis(p_tour uuid)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare t tours; v_pts int; v_justes int;
begin
  select * into t from tours where id = p_tour;
  if t.id is null then raise exception 'tour introuvable'; end if;
  if auth.uid() <> sujet_du_tour(p_tour) and not peut_orchestrer(t.partie_id) then
    raise exception 'non autorisé';
  end if;
  if t.statut = 'juge' then return jsonb_build_object('deja', true); end if;
  if t.statut <> 'revele' then raise exception 'révèle d''abord'; end if;

  v_pts := points_manche(t.manche);
  update binomes b set score = b.score + v_pts
  where b.partie_id = t.partie_id
    and exists (select 1 from reponses_manche r
                join joueurs j on j.id = r.joueur_id
                where r.tour_id = p_tour and r.juste and j.binome_id = b.id);

  select count(*) into v_justes from reponses_manche where tour_id = p_tour and juste;
  update tours set statut = 'juge', verdict = v_justes > 0, points = v_pts * v_justes
  where id = p_tour;
  return jsonb_build_object('statut','juge','justes',v_justes,'points_chacun',v_pts);
end $$;

-- Le tournoi n'a pas de finale : il n'y a pas de partenaire à deviner,
-- et le classement se fait sur l'ensemble des passages.
create or replace function rpc_suivant()
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_partie uuid; p parties; t tours; v_restants int;
begin
  select partie_id into v_partie from joueurs where id = auth.uid();
  if v_partie is null then select id into v_partie from parties where plateau_id = auth.uid(); end if;
  if not peut_orchestrer(v_partie) then
    raise exception 'seuls le plateau, l''hôte et le présentateur font avancer l''émission';
  end if;
  select * into p from parties where id = v_partie;
  if p.en_pause then raise exception 'la partie est en pause'; end if;

  if p.etat = 'prep' then
    select count(*) into v_restants from joueurs j
    where j.partie_id = v_partie and j.binome_id is not null
      and (select count(*) from reponses_prepa r where r.joueur_id = j.id)
          < nb_questions_prepa(v_partie);
    if v_restants > 0 then
      raise exception '% joueur(s) n''ont pas fini de préparer', v_restants;
    end if;
  elsif p.etat = 'palmares' then
    return jsonb_build_object('etat','palmares','fin',true);
  end if;

  select * into t from tours where partie_id = v_partie and statut <> 'juge'
  order by ordre limit 1;

  if t.id is null then
    if p.mode_jeu in ('sujet','tournoi') then
      update parties set etat = 'palmares', tour_courant = null where id = v_partie;
      return jsonb_build_object('etat','palmares','fin',true);
    end if;
    if p.etat not in ('finale','palmares') then
      perform preparer_finale(v_partie);
      update parties set etat = 'finale', tour_courant = null where id = v_partie;
      return jsonb_build_object('etat','finale',
        'passages', (select count(*) from passages_finale where partie_id = v_partie));
    end if;
    if not exists (select 1 from passages_finale
                   where partie_id = v_partie and seuil_atteint is null) then
      update parties set etat = 'palmares' where id = v_partie;
      return jsonb_build_object('etat','palmares','fin',true);
    end if;
    return jsonb_build_object('etat','finale',
      'passage_courant', (select id from passages_finale
                          where partie_id = v_partie and seuil_atteint is null
                          order by ordre limit 1));
  end if;

  update parties set etat = t.manche, tour_courant = t.id where id = v_partie;
  return jsonb_build_object('etat', t.manche, 'tour_id', t.id, 'ordre', t.ordre,
                            'manche', t.manche, 'binome_id', t.binome_id,
                            'question_id', t.question_id, 'repondant_id', t.repondant_id,
                            'questionneur_id', t.questionneur_id, 'sujet_id', t.sujet_id);
end $$;

-- v_tours expose le sujet du tour
drop view if exists v_tours;
create view v_tours as
  select t.id, t.partie_id, t.ordre, t.manche, t.binome_id,
         t.question_id, t.repondant_id, t.questionneur_id, t.sujet_id,
         t.statut, t.vote_fin_at, t.verdict, t.points, t.contestee,
         t.reponse_donnee, t.reponses_recues, t.revision,
         case when t.statut in ('revele','vote','juge')
              then t.reponse_revelee end as reponse_revelee,
         case when t.statut = 'juge'
              then (select count(*) from votes v where v.tour_id = t.id and v.pour) end as voix_pour,
         case when t.statut = 'juge'
              then (select count(*) from votes v where v.tour_id = t.id and not v.pour) end as voix_contre,
         exists (select 1 from votes v where v.tour_id = t.id and v.joueur_id = auth.uid()) as j_ai_vote,
         exists (select 1 from reponses_manche r
                 where r.tour_id = t.id and r.joueur_id = auth.uid()) as j_ai_repondu
  from tours t
  where est_membre(t.partie_id);
grant select on v_tours to anon, authenticated;

do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p
           join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like 'rpc\_%'
  loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
