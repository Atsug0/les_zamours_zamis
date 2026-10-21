-- =============================================================
-- 0016 — Mode « qui connaît le mieux X »
--
-- Une inversion du jeu, pas une variante. Une personne — LE SUJET —
-- est celle qu'on doit devenir ; tous les autres s'affrontent
-- individuellement. Le sujet est aussi le présentateur : c'est lui
-- qui sait, donc lui qui valide.
--
-- DÉCISION DE CONCEPTION : pas de phase de préparation.
-- Le sujet répond EN SECRET juste avant les autres, question par
-- question. Trois raisons :
--   * zéro temps mort — une prépa de 12 questions pour une seule
--     personne, c'est six minutes où sept joueurs regardent le mur ;
--   * c'est exactement comme on jouerait à table ;
--   * sa réponse est verrouillée avant que quiconque réponde, donc
--     l'équité est la même qu'avec une prépa.
--
-- Plus de binômes au sens du jeu principal, mais chaque challenger
-- reçoit un « binôme » d'une personne : scores, couleurs et palmarès
-- fonctionnent alors sans y toucher.
-- =============================================================

alter table parties
  add column mode_jeu text not null default 'binomes'
      check (mode_jeu in ('binomes','sujet')),
  add column sujet_id uuid references joueurs on delete set null on update cascade;

-- un tour du mode sujet n'appartient à aucun binôme : tout le monde joue
alter table tours alter column binome_id drop not null;

-- -------------------------------------------------------------
-- Les réponses des challengers. Secrètes jusqu'à la révélation,
-- comme tout le reste : aucun droit de lecture directe.
-- -------------------------------------------------------------
create table reponses_manche (
  tour_id   uuid not null references tours on delete cascade,
  joueur_id uuid not null references joueurs on delete cascade on update cascade,
  valeur    text not null,
  juste     boolean,
  ecrit_le  timestamptz not null default now(),
  primary key (tour_id, joueur_id)
);
alter table reponses_manche enable row level security;
revoke all on table reponses_manche from anon, authenticated;

-- Vue : qui a répondu, et le contenu seulement après la révélation.
create view v_reponses_manche as
  select r.tour_id, r.joueur_id, j.prenom,
         case when t.statut in ('revele','juge') then r.valeur end as valeur,
         case when t.statut in ('revele','juge') then r.juste end as juste,
         (r.joueur_id = auth.uid()) as c_est_moi
  from reponses_manche r
  join tours t   on t.id = r.tour_id
  join joueurs j on j.id = r.joueur_id
  where est_membre(t.partie_id);

grant select on v_reponses_manche to anon, authenticated;

-- -------------------------------------------------------------
-- Lobby : devenir le sujet
-- -------------------------------------------------------------
create or replace function rpc_devenir_sujet()
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare moi joueurs; p parties;
begin
  select * into moi from joueurs where id = auth.uid();
  if moi.id is null then raise exception 'rejoins la partie d''abord'; end if;
  select * into p from parties where id = moi.partie_id;
  if p.etat <> 'lobby' then raise exception 'trop tard'; end if;
  if p.sujet_id is not null and p.sujet_id <> moi.id then
    raise exception '% est déjà le sujet',
      (select prenom from joueurs where id = p.sujet_id);
  end if;
  if exists (select 1 from binomes where partie_id = p.id) then
    raise exception 'des binômes sont déjà formés : ce mode se joue sans binôme';
  end if;

  update parties set mode_jeu = 'sujet', sujet_id = moi.id, presentateur_id = moi.id
  where id = p.id;
  return jsonb_build_object('sujet_id', moi.id, 'mode_jeu', 'sujet');
end $$;

-- -------------------------------------------------------------
-- Lancement. Le sujet ne prépare rien : il répondra en direct.
-- -------------------------------------------------------------
create or replace function rpc_lancer_sujet(p_format text default 'court')
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  p parties; v_partie uuid; j record; m text;
  n_ouvertes int; n_qcm int; v_tirage jsonb;
  couleurs text[] := array['rouge','jaune','bleu','vert','orange','violet'];
  i int := 0; v_bid uuid;
begin
  select pa.* into p from parties pa
  where pa.id = (select partie_id from joueurs where id = auth.uid())
     or pa.plateau_id = auth.uid()
  limit 1;
  if p.id is null then raise exception 'partie introuvable'; end if;
  v_partie := p.id;
  if not peut_orchestrer(v_partie) then raise exception 'non autorisé'; end if;
  if p.etat <> 'lobby' then raise exception 'la partie est déjà lancée'; end if;
  if p.sujet_id is null then raise exception 'personne ne s''est désigné comme sujet'; end if;
  if p_format not in ('court','long') then raise exception 'format inconnu'; end if;

  if (select count(*) from joueurs where partie_id = v_partie
        and id <> p.sujet_id) < 2 then
    raise exception 'il faut au moins deux challengers : sinon il n''y a rien à départager';
  end if;

  -- Le mode du sujet décide du pool. Par défaut Zamis : ce mode se joue
  -- entre amis ou en famille, autour d'une personne.
  m := coalesce((select mode_choisi from joueurs where id = p.sujet_id), 'zamis');

  -- Pas de partenaire, donc on prend LES DEUX slots de chaque paire.
  n_ouvertes := case p_format when 'court' then 4 else 6 end;   -- -> 8 ou 12 questions
  n_qcm      := case p_format when 'court' then 2 else 3 end;   -- -> 4 ou 6 questions

  v_tirage := jsonb_build_object(m, jsonb_build_object(
    'ouvertes', to_jsonb(tirer_paires(m,'ouverte','{}', false, n_ouvertes)),
    'qcm',      to_jsonb(tirer_paires(m,'qcm','{}',     false, n_qcm)),
    'bonus',    null,                                  -- le bonus parle d'un duo
    'finale',   tirer_un(m,'serie_finale','{}', false),
    'citez3',   '[]'::jsonb,
    'sensibles', false, 'occasions', '[]'::jsonb
  ));

  -- Chaque challenger reçoit une « équipe » d'une personne : scores,
  -- couleurs et palmarès fonctionnent alors sans modification.
  for j in select * from joueurs where partie_id = v_partie and id <> p.sujet_id
           order by prenom loop
    i := i + 1;
    if i > 6 then raise exception 'six challengers au maximum'; end if;
    insert into binomes (partie_id, mode, couleur, verrouille)
    values (v_partie, m, couleurs[i], true) returning id into v_bid;
    update joueurs set binome_id = v_bid, role = 'A' where id = j.id;
  end loop;

  update parties set format = p_format, tirage = v_tirage, etat = 'qcm' where id = v_partie;
  perform fabriquer_tours_sujet(v_partie);
  update parties set tour_courant = (select id from tours where partie_id = v_partie
                                     order by ordre limit 1)
  where id = v_partie;

  return jsonb_build_object('etat','qcm','mode_jeu','sujet',
                            'tours',(select count(*) from tours where partie_id = v_partie));
end $$;

-- -------------------------------------------------------------
-- Les tours : une question = un tour, tout le monde y joue.
-- QCM d'abord, puis les ouvertes. Pas de bonus (il parle d'un duo).
-- -------------------------------------------------------------
create or replace function fabriquer_tours_sujet(p_partie uuid)
returns int language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  p parties; m text; v_ordre int := 0; v_manche text; v_cle text;
  v_paire text; v_slot text;
begin
  select * into p from parties where id = p_partie;
  delete from tours where partie_id = p_partie;
  select mode into m from binomes where partie_id = p_partie limit 1;

  foreach v_manche in array array['qcm','libre'] loop
    v_cle := case v_manche when 'qcm' then 'qcm' else 'ouvertes' end;
    for v_paire in select x.value from jsonb_array_elements_text(p.tirage->m->v_cle) x loop
      foreach v_slot in array array['a','b'] loop
        v_ordre := v_ordre + 1;
        insert into tours (partie_id, ordre, manche, binome_id, question_id,
                           repondant_id, questionneur_id)
        values (p_partie, v_ordre, v_manche, null, v_paire || '.' || v_slot,
                null, p.sujet_id);
      end loop;
    end loop;
  end loop;
  return v_ordre;
end $$;

-- -------------------------------------------------------------
-- 1. Le sujet répond en secret.
-- -------------------------------------------------------------
create or replace function rpc_sujet_repond(p_tour uuid, p_valeur text)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare t tours; p parties;
begin
  select * into t from tours where id = p_tour;
  if t.id is null then raise exception 'tour introuvable'; end if;
  select * into p from parties where id = t.partie_id;
  if p.mode_jeu <> 'sujet' then raise exception 'mauvais mode de jeu'; end if;
  if p.en_pause then raise exception 'la partie est en pause'; end if;
  if auth.uid() <> p.sujet_id then raise exception 'seul le sujet répond ici'; end if;
  if t.statut <> 'attente' then raise exception 'tu as déjà répondu à cette question'; end if;
  if length(btrim(coalesce(p_valeur,''))) = 0 then raise exception 'réponse vide'; end if;

  -- écrite dans reponse_revelee, que la vue masque tant que le tour
  -- n'est pas révélé : personne ne peut la lire d'ici là
  update tours set reponse_revelee = btrim(p_valeur), statut = 'consigne' where id = p_tour;
  return jsonb_build_object('statut','consigne');
end $$;

-- -------------------------------------------------------------
-- 2. Les challengers répondent, chacun de son côté.
-- -------------------------------------------------------------
create or replace function rpc_defier(p_tour uuid, p_valeur text)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare t tours; p parties; v_total int; v_faits int; v_motif text;
begin
  select * into t from tours where id = p_tour;
  if t.id is null then raise exception 'tour introuvable'; end if;
  select * into p from parties where id = t.partie_id;
  if p.en_pause then raise exception 'la partie est en pause'; end if;
  if auth.uid() = p.sujet_id then raise exception 'le sujet ne se devine pas lui-même'; end if;
  if not exists (select 1 from joueurs where id = auth.uid() and partie_id = t.partie_id) then
    raise exception 'tu n''es pas dans cette partie';
  end if;
  if t.statut <> 'consigne' then
    -- RAISE n'accepte pas une expression CASE : on la calcule d'abord.
    v_motif := case t.statut when 'attente' then 'le sujet n''a pas encore répondu'
                             else 'la réponse est déjà révélée' end;
    raise exception '%', v_motif;
  end if;
  if length(btrim(coalesce(p_valeur,''))) = 0 then raise exception 'réponse vide'; end if;

  insert into reponses_manche (tour_id, joueur_id, valeur)
  values (p_tour, auth.uid(), btrim(p_valeur))
  on conflict (tour_id, joueur_id) do update set valeur = excluded.valeur, ecrit_le = now();

  select count(*) into v_total from joueurs
  where partie_id = t.partie_id and id <> p.sujet_id;
  select count(*) into v_faits from reponses_manche where tour_id = p_tour;
  return jsonb_build_object('faits', v_faits, 'total', v_total,
                            'tous_ont_repondu', v_faits >= v_total);
end $$;

-- -------------------------------------------------------------
-- 3. Révélation. On pré-remplit le jugement par comparaison exacte :
--    le sujet n'a plus qu'à corriger les cas limites.
-- -------------------------------------------------------------
create or replace function rpc_reveler_defis(p_tour uuid)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare t tours; p parties;
begin
  select * into t from tours where id = p_tour;
  if t.id is null then raise exception 'tour introuvable'; end if;
  select * into p from parties where id = t.partie_id;
  if auth.uid() <> p.sujet_id and not peut_orchestrer(t.partie_id) then
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

-- 4. Le sujet corrige un jugement (même idée, autres mots).
create or replace function rpc_juger_defi(p_tour uuid, p_joueur uuid, p_juste boolean)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare t tours; p parties;
begin
  select * into t from tours where id = p_tour;
  select * into p from parties where id = t.partie_id;
  if auth.uid() <> p.sujet_id then raise exception 'seul le sujet juge'; end if;
  if t.statut <> 'revele' then raise exception 'ce tour n''est pas en jugement'; end if;
  update reponses_manche set juste = p_juste where tour_id = p_tour and joueur_id = p_joueur;
  return jsonb_build_object('joueur_id', p_joueur, 'juste', p_juste);
end $$;

-- 5. Clôture : chaque bonne réponse rapporte à son auteur.
create or replace function rpc_clore_defis(p_tour uuid)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare t tours; p parties; v_pts int; v_justes int;
begin
  select * into t from tours where id = p_tour;
  if t.id is null then raise exception 'tour introuvable'; end if;
  select * into p from parties where id = t.partie_id;
  if auth.uid() <> p.sujet_id and not peut_orchestrer(t.partie_id) then
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
  for f in select p.oid::regprocedure as sig from pg_proc p
           join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'fabriquer_tours_sujet'
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;

-- -------------------------------------------------------------
-- La machine à états : le mode sujet n'a pas de finale.
--
-- La finale fait deviner les réponses d'un PARTENAIRE, et dans ce
-- mode il n'y en a pas : le sujet n'a rien préparé, il répond en
-- direct. On va donc des manches droit au palmarès.
-- -------------------------------------------------------------
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

  select * into t from tours
  where partie_id = v_partie and statut <> 'juge'
  order by ordre limit 1;

  if t.id is null then
    if p.mode_jeu = 'sujet' then
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
                            'questionneur_id', t.questionneur_id);
end $$;

revoke all on function rpc_suivant() from public, anon;
grant execute on function rpc_suivant() to authenticated;
