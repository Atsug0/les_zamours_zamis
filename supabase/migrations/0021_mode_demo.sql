-- =============================================================
-- 0021 — Parties de démonstration, avec des bots
--
-- Pour dérouler une partie entière tout seul : on crée une partie
-- peuplée de bots, on la rejoint normalement, et les bots jouent
-- leur part pendant qu'on joue la sienne.
--
-- SÛRETÉ. Les bots agissent via une fonction qui ne lit pas
-- auth.uid() — c'est tout l'intérêt, ils n'ont pas de session. Deux
-- verrous pour que ça ne devienne pas une porte dérobée :
--   * la partie doit être marquée `demo`, et seule rpc_creer_demo
--     peut la marquer ainsi ;
--   * la fonction n'agit QUE pour des joueurs marqués `bot`.
-- Une partie normale ne peut donc jamais être pilotée par là.
-- =============================================================

alter table parties add column demo boolean not null default false;
alter table joueurs add column bot boolean not null default false;

-- -------------------------------------------------------------
-- Créer la partie de démonstration. L'appelant y entre comme joueur.
-- -------------------------------------------------------------
create or replace function rpc_creer_demo(p_mode_jeu text default 'binomes',
                                          p_bots int default 3,
                                          p_mode text default 'zamis')
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  p parties; v_moi uuid; v_bid uuid; v_bot uuid; i int; v_nb int;
  noms text[] := array['Bot Ana','Bot Bruno','Bot Chloé','Bot Diego','Bot Elsa','Bot Fred','Bot Gaby'];
  couleurs text[] := array['rouge','jaune','bleu','vert','orange','violet'];
  v_libre uuid; v_couleur int := 0;
begin
  v_moi := auth.uid();
  if v_moi is null then raise exception 'session requise'; end if;
  if p_mode_jeu not in ('binomes','paris','sujet','tournoi','duel') then
    raise exception 'mode de jeu inconnu';
  end if;
  if p_mode not in ('zamours','zamis') then raise exception 'mode inconnu'; end if;

  v_nb := greatest(1, least(p_bots, 6));

  insert into parties (code, plateau_id, demo) values (tirer_code(), v_moi, true)
  returning * into p;

  -- l'humain entre comme joueur : il joue et regarde en même temps
  insert into joueurs (id, partie_id, prenom) values (v_moi, p.id, 'Toi');
  insert into sieges (joueur_id, pin) values (v_moi, tirer_pin());
  update parties set hote_id = v_moi where id = p.id;

  for i in 1..v_nb loop
    v_bot := gen_random_uuid();
    insert into joueurs (id, partie_id, prenom, bot) values (v_bot, p.id, noms[i], true);
    insert into sieges (joueur_id, pin) values (v_bot, tirer_pin());
  end loop;

  if p_mode_jeu in ('binomes','paris','duel') then
    -- l'humain avec le premier bot, puis les bots deux par deux
    v_couleur := 1;
    select id into v_bot from joueurs where partie_id = p.id and bot order by prenom limit 1;
    insert into binomes (partie_id, mode, couleur, verrouille)
    values (p.id, p_mode, couleurs[v_couleur], true) returning id into v_bid;
    update joueurs set binome_id = v_bid, role = 'A', mode_choisi = p_mode where id = v_moi;
    update joueurs set binome_id = v_bid, role = 'B', mode_choisi = p_mode where id = v_bot;

    loop
      select id into v_libre from joueurs
      where partie_id = p.id and bot and binome_id is null order by prenom limit 1;
      exit when v_libre is null;
      select id into v_bot from joueurs
      where partie_id = p.id and bot and binome_id is null and id <> v_libre
      order by prenom limit 1;
      if v_bot is null then
        -- bot en trop : il présente
        update parties set presentateur_id = v_libre where id = p.id;
        exit;
      end if;
      v_couleur := v_couleur + 1;
      insert into binomes (partie_id, mode, couleur, verrouille)
      values (p.id, p_mode, couleurs[v_couleur], true) returning id into v_bid;
      update joueurs set binome_id = v_bid, role = 'A', mode_choisi = p_mode where id = v_libre;
      update joueurs set binome_id = v_bid, role = 'B', mode_choisi = p_mode where id = v_bot;
    end loop;

    if p_mode_jeu = 'paris' then
      update parties set mode_jeu = 'paris' where id = p.id;
    end if;

  elsif p_mode_jeu = 'sujet' then
    -- un bot est le sujet : il répondra tout seul, l'humain devine
    select id into v_bot from joueurs where partie_id = p.id and bot order by prenom limit 1;
    update parties set mode_jeu = 'sujet', sujet_id = v_bot, presentateur_id = v_bot
    where id = p.id;
    update joueurs set mode_choisi = p_mode where partie_id = p.id;
  else
    update joueurs set mode_choisi = p_mode where partie_id = p.id;
  end if;

  return jsonb_build_object('partie_id', p.id, 'code', p.code,
                            'mode_jeu', p_mode_jeu, 'bots', v_nb);
end $$;

-- -------------------------------------------------------------
-- Remplir la préparation : les bots, et l'humain s'il le demande.
-- La prépa est la partie ennuyeuse d'un déroulé en solo.
-- -------------------------------------------------------------
create or replace function remplir_prepa(p_joueur uuid)
returns int language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  j joueurs; p parties; b binomes; v_slot text; v_serie text; v_c3 text;
  i int; n int := 0; q text; v_val text; v_bonus text;
begin
  select * into j from joueurs where id = p_joueur;
  if j.binome_id is null then return 0; end if;
  select * into p from parties where id = j.partie_id;
  select * into b from binomes where id = j.binome_id;
  v_slot := lower(j.role);

  -- le bonus : une chance sur deux que le binôme concorde
  v_bonus := case when (select count(*) from reponses_prepa r
                        join joueurs o on o.id = r.joueur_id
                        where o.binome_id = j.binome_id
                          and r.question_id = p.tirage->b.mode->>'bonus') > 0
                       and random() < 0.6
                  then (select r.valeur from reponses_prepa r
                        join joueurs o on o.id = r.joueur_id
                        where o.binome_id = j.binome_id
                          and r.question_id = p.tirage->b.mode->>'bonus' limit 1)
                  else 'bonus-' || substr(md5(random()::text), 1, 5) end;

  for q in select x.value || '.' || v_slot
           from jsonb_array_elements_text(p.tirage->b.mode->'ouvertes') x
           union all
           select x.value || '.' || v_slot
           from jsonb_array_elements_text(p.tirage->b.mode->'qcm') x loop
    v_val := 'rep-' || q;
    insert into reponses_prepa (joueur_id, question_id, valeur) values (p_joueur, q, v_val)
    on conflict do nothing;
    n := n + 1;
  end loop;

  insert into reponses_prepa (joueur_id, question_id, valeur)
  values (p_joueur, p.tirage->b.mode->>'bonus', v_bonus) on conflict do nothing;
  n := n + 1;

  if p.avec_citez3 then
    v_c3 := p.tirage->b.mode->'citez3'->>(case j.role when 'A' then 0 else 1 end);
    for i in 1..3 loop
      insert into reponses_prepa (joueur_id, question_id, valeur)
      values (p_joueur, v_c3 || '.' || i, 'trois-' || i) on conflict do nothing;
      n := n + 1;
    end loop;
  end if;

  v_serie := p.tirage->b.mode->>'finale';
  for i in 1..(p.reglages->>'questionsFinale')::int loop
    insert into reponses_prepa (joueur_id, question_id, valeur)
    values (p_joueur, v_serie || '.' || i, 'fin-' || i) on conflict do nothing;
    n := n + 1;
  end loop;

  update joueurs set prepa_faites =
    (select count(*) from reponses_prepa r where r.joueur_id = p_joueur)
  where id = p_joueur;
  return n;
end $$;
revoke all on function remplir_prepa(uuid) from public, anon, authenticated;

/** Remplir SA propre préparation au hasard — réservé aux parties de démo. */
create or replace function rpc_remplir_ma_prepa()
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare j joueurs;
begin
  select * into j from joueurs where id = auth.uid();
  if j.id is null then raise exception 'rejoins la partie d''abord'; end if;
  if not (select demo from parties where id = j.partie_id) then
    raise exception 'réservé aux parties de démonstration';
  end if;
  return jsonb_build_object('remplies', remplir_prepa(j.id));
end $$;

-- =============================================================
-- Les bots jouent.
--
-- Plutôt que de recopier la logique de chaque rpc_ (qui divergerait
-- au premier changement), un bot ENDOSSE son identité le temps de
-- l'action : auth.uid() lit `request.jwt.claim.sub`, qu'on pose en
-- local de transaction. Les bots empruntent donc exactement le même
-- chemin que des humains — validations comprises. Une partie de démo
-- est ainsi un test d'intégration qui se joue tout seul.
-- =============================================================

create or replace function agir_comme(p_joueur uuid)
returns void language sql security definer
set search_path = public, pg_temp as $$
  select set_config('request.jwt.claim.sub', coalesce(p_joueur::text, ''), true);
$$;
revoke all on function agir_comme(uuid) from public, anon, authenticated;

/** Réponse d'un bot : juste la plupart du temps, pour que ça bouge. */
create or replace function reponse_bot(p_attendue text, p_chance real default 0.55)
returns text language sql
set search_path = public, pg_temp as $$
  select case when p_attendue is not null and random() < p_chance
              then p_attendue
              else 'à côté ' || substr(md5(random()::text), 1, 4) end;
$$;
revoke all on function reponse_bot(text, real) from public, anon, authenticated;

create or replace function rpc_bots_agir(p_partie uuid default null)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  p parties; v_partie uuid; v_humain uuid := auth.uid();
  t tours; j record; v_sujet uuid; v_acteur uuid; v_attendue text;
  f passages_finale; v_actions text[] := '{}'; v_tour uuid;
begin
  v_partie := coalesce(p_partie, (select partie_id from joueurs where id = v_humain),
                       (select id from parties where plateau_id = v_humain));
  select * into p from parties where id = v_partie;
  if p.id is null then raise exception 'partie introuvable'; end if;
  if not p.demo then raise exception 'réservé aux parties de démonstration'; end if;
  if not est_membre(v_partie) then raise exception 'tu n''es pas dans cette partie'; end if;
  if p.en_pause then return jsonb_build_object('actions', '[]'::jsonb, 'en_pause', true); end if;

  -- ---- préparation : les bots remplissent la leur ----
  if p.etat = 'prep' then
    for j in select jo.* from joueurs jo
             where jo.partie_id = v_partie and jo.bot and jo.binome_id is not null
               and jo.prepa_faites < nb_questions_prepa(v_partie) loop
      perform remplir_prepa(j.id);
      v_actions := array_append(v_actions, j.prenom || ' a préparé');
    end loop;
    perform agir_comme(v_humain);
    return jsonb_build_object('actions', to_jsonb(v_actions), 'etat', p.etat);
  end if;

  -- ---- finale ----
  if p.etat = 'finale' then
    select * into f from passages_finale
    where partie_id = v_partie and seuil_atteint is null order by ordre limit 1;
    if f.id is not null then
      if f.joueur_id is null then
        select id into v_acteur from joueurs where binome_id = f.binome_id and bot limit 1;
        if v_acteur is not null then
          perform agir_comme(v_acteur);
          perform rpc_designer_finaliste(f.id, v_acteur);
          v_actions := array_append(v_actions, 'un bot se désigne pour la finale');
        end if;
      elsif f.chrono_fin_at is null and f.chrono_restant_ms is null then
        if (select bot from joueurs where id = f.questionneur_id) then
          perform agir_comme(f.questionneur_id);
          perform rpc_demarrer_passage(f.id);
          v_actions := array_append(v_actions, 'le chrono de finale est lancé');
        end if;
      elsif (select bot from joueurs where id = f.questionneur_id) then
        perform agir_comme(f.questionneur_id);
        for i in 1..array_length(f.jugements,1) loop
          if f.jugements[i] = 'attente' then
            perform rpc_juger(f.id, i, case when random() < 0.5 then 'juste' else 'faux' end);
          end if;
        end loop;
        perform rpc_clore_passage(f.id);
        v_actions := array_append(v_actions, 'le passage de finale est jugé');
      end if;
    end if;
    perform agir_comme(v_humain);
    return jsonb_build_object('actions', to_jsonb(v_actions), 'etat', p.etat);
  end if;

  -- ---- les manches ----
  select * into t from tours where partie_id = v_partie and statut <> 'juge'
  order by ordre limit 1;
  if t.id is null then
    perform agir_comme(v_humain);
    return jsonb_build_object('actions', '[]'::jsonb, 'etat', p.etat);
  end if;
  v_tour := t.id;

  if p.mode_jeu in ('sujet','tournoi') then
    v_sujet := sujet_du_tour(v_tour);
    if t.statut = 'attente' and (select bot from joueurs where id = v_sujet) then
      perform agir_comme(v_sujet);
      perform rpc_sujet_repond(v_tour, 'rep-' || t.ordre);
      v_actions := array_append(v_actions, 'le sujet a répondu en secret');
    end if;
    select * into t from tours where id = v_tour;

    if t.statut = 'consigne' then
      for j in select jo.* from joueurs jo
               where jo.partie_id = v_partie and jo.bot and jo.id <> v_sujet
                 and not exists (select 1 from reponses_manche r
                                 where r.tour_id = v_tour and r.joueur_id = jo.id) loop
        perform agir_comme(j.id);
        perform rpc_defier(v_tour, reponse_bot('rep-' || t.ordre));
        v_actions := array_append(v_actions, j.prenom || ' a répondu');
      end loop;
      select * into t from tours where id = v_tour;
      if (select count(*) from joueurs where partie_id = v_partie and id <> v_sujet)
         = t.reponses_recues
         and (select bot from joueurs where id = v_sujet) then
        perform agir_comme(v_sujet);
        perform rpc_reveler_defis(v_tour);
        v_actions := array_append(v_actions, 'révélation');
      end if;
    end if;
    select * into t from tours where id = v_tour;
    if t.statut = 'revele' and (select bot from joueurs where id = v_sujet) then
      perform agir_comme(v_sujet);
      perform rpc_clore_defis(v_tour);
      v_actions := array_append(v_actions, 'points comptés');
    end if;

  else
    -- binômes, duel, paris
    if t.statut = 'attente' then
      if t.manche = 'bonus' then
        v_acteur := t.questionneur_id;
      elsif t.manche = 'qcm' or p.mode_jeu = 'duel' then
        v_acteur := t.repondant_id;
      else
        v_acteur := t.questionneur_id;
      end if;
      if (select bot from joueurs where id = v_acteur) then
        perform agir_comme(v_acteur);
        if t.manche = 'bonus' then
          perform rpc_reveler(v_tour);
          v_actions := array_append(v_actions, 'le bonus est révélé');
        else
          select valeur into v_attendue from reponses_prepa
          where joueur_id = (select id from joueurs
                             where binome_id = t.binome_id and id <> t.repondant_id)
            and question_id = t.question_id;
          perform rpc_consigner(v_tour, reponse_bot(v_attendue));
          v_actions := array_append(v_actions, 'une réponse est consignée');
        end if;
      end if;
    end if;
    select * into t from tours where id = v_tour;

    if t.statut = 'consigne' then
      if p.mode_jeu = 'paris' then
        for j in select jo.* from joueurs jo
                 where jo.partie_id = v_partie and jo.bot
                   and jo.id in (select parieurs(v_tour))
                   and not exists (select 1 from reponses_manche r
                                   where r.tour_id = v_tour and r.joueur_id = jo.id) loop
          perform agir_comme(j.id);
          perform rpc_parier(v_tour, random() < 0.5);
          v_actions := array_append(v_actions, j.prenom || ' a parié');
        end loop;
        if (select count(*) from parieurs(v_tour)) =
           (select reponses_recues from tours where id = v_tour)
           and (select bot from joueurs where id = t.questionneur_id) then
          perform agir_comme(t.questionneur_id);
          perform rpc_clore_paris(v_tour);
          v_actions := array_append(v_actions, 'paris comptés');
        end if;
      elsif (select bot from joueurs where id = t.questionneur_id) then
        perform agir_comme(t.questionneur_id);
        perform rpc_reveler(v_tour);
        v_actions := array_append(v_actions, 'révélation');
      end if;
    end if;
    select * into t from tours where id = v_tour;

    if t.statut = 'vote' then
      for j in select jo.* from joueurs jo
               where jo.partie_id = v_partie and jo.bot
                 and jo.id in (select votants(v_tour))
                 and not exists (select 1 from votes v
                                 where v.tour_id = v_tour and v.joueur_id = jo.id) loop
        perform agir_comme(j.id);
        perform rpc_voter(v_tour, random() < 0.7);
        v_actions := array_append(v_actions, j.prenom || ' a voté');
      end loop;
    end if;

    -- duel : un bot qui s'est trompé conteste parfois, l'autre tranche
    select * into t from tours where id = v_tour;
    if p.mode_jeu = 'duel' and t.statut = 'revele' and t.contestee then
      select id into v_acteur from joueurs
      where binome_id = t.binome_id and id <> t.repondant_id and bot;
      if v_acteur is not null then
        perform agir_comme(v_acteur);
        perform rpc_trancher_contestation(v_tour, random() < 0.6);
        v_actions := array_append(v_actions, 'contestation tranchée');
      end if;
    end if;
  end if;

  perform agir_comme(v_humain);
  return jsonb_build_object('actions', to_jsonb(v_actions), 'etat', p.etat, 'tour', v_tour);
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
end $$;

-- v_joueurs expose le drapeau bot, et considère les bots toujours
-- présents : sans ça, le plateau gèlerait la partie en les croyant
-- déconnectés — ils n'envoient aucun pouls.
drop view if exists v_joueurs;
create view v_joueurs as
  select j.id, j.partie_id, j.prenom, j.binome_id, j.role, j.vu_le,
         ((j.vu_le > now() - interval '30 seconds') or j.bot) as present,
         (j.mode_choisi is not null) as a_choisi_mode, j.prepa_faites, j.bot,
         j.mode_choisi, j.sensibles_choisi, j.occasions_choisies
  from joueurs j
  where est_membre(j.partie_id);

grant select on v_joueurs to anon, authenticated;
