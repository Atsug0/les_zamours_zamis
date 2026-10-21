-- =============================================================
-- 0022 — Chaque mode ne répond qu'à ses propres fonctions
--
-- Trouvé en déroulant une partie de démonstration : appelée dans un
-- mode sujet ou tournoi, rpc_reveler (le chemin des binômes) passait
-- sans broncher et laissait le tour en statut « vote » — un état qui
-- n'existe pas dans ces modes. La partie se bloquait, sans erreur.
--
-- Les fonctions d'un mode doivent refuser les autres modes. C'est le
-- pendant de ce qu'on fait déjà partout ailleurs : valider la phase
-- avant d'agir.
-- =============================================================

create or replace function garde_mode(p_partie uuid, p_attendus text[])
returns void language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_mode text;
begin
  select mode_jeu into v_mode from parties where id = p_partie;
  if not (v_mode = any(p_attendus)) then
    raise exception 'cette action n''existe pas dans le mode « % »', v_mode;
  end if;
end $$;
revoke all on function garde_mode(uuid, text[]) from public, anon, authenticated;

-- rpc_reveler et rpc_consigner : réservées aux modes à binômes.
create or replace function rpc_reveler(p_tour uuid)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  t tours; p parties; v_attendue text; v_donnee text; v_fenetre int;
  v_a uuid; v_b uuid;
begin
  select * into t from tours where id = p_tour;
  if t.id is null then raise exception 'tour introuvable'; end if;
  perform garde_mode(t.partie_id, array['binomes','duel','paris']);
  select * into p from parties where id = t.partie_id;
  if p.en_pause then raise exception 'la partie est en pause'; end if;
  if auth.uid() <> t.questionneur_id and not peut_orchestrer(t.partie_id)
     and not (p.mode_jeu = 'duel' and est_membre(t.partie_id)) then
    raise exception 'seul le questionneur révèle';
  end if;

  if t.manche = 'bonus' then
    if t.statut <> 'attente' then raise exception 'bonus déjà révélé'; end if;
    select id into v_a from joueurs where binome_id = t.binome_id and role = 'A';
    select id into v_b from joueurs where binome_id = t.binome_id and role = 'B';
    select valeur into v_donnee   from reponses_prepa where joueur_id = v_a and question_id = t.question_id;
    select valeur into v_attendue from reponses_prepa where joueur_id = v_b and question_id = t.question_id;
    v_fenetre := (p.reglages->>'fenetreBonusMs')::int;
  else
    if t.statut <> 'consigne' then raise exception 'consigne la réponse d''abord'; end if;
    v_donnee := t.reponse_donnee;
    select valeur into v_attendue from reponses_prepa
    where joueur_id = (select id from joueurs where binome_id = t.binome_id and id <> t.repondant_id)
      and question_id = t.question_id;
    v_fenetre := (p.reglages->>'fenetreVoteMs')::int;
  end if;

  if p.mode_jeu = 'duel' then
    update tours set reponse_donnee = coalesce(reponse_donnee, v_donnee),
                     reponse_revelee = v_attendue
    where id = p_tour;
    perform juger_tour(p_tour, normaliser(v_donnee) = normaliser(v_attendue));
    return jsonb_build_object('statut','juge',
      'reponse_donnee', v_donnee, 'reponse_revelee', v_attendue,
      'verdict', normaliser(v_donnee) = normaliser(v_attendue),
      'contestable', normaliser(v_donnee) <> normaliser(v_attendue));
  end if;

  update tours set reponse_donnee  = coalesce(reponse_donnee, v_donnee),
                   reponse_revelee = v_attendue,
                   statut = 'vote',
                   vote_fin_at = now() + (v_fenetre || ' milliseconds')::interval
  where id = p_tour;

  return jsonb_build_object('statut','vote',
    'reponse_donnee', coalesce(t.reponse_donnee, v_donnee),
    'reponse_revelee', v_attendue,
    'vote_fin_at', now() + (v_fenetre || ' milliseconds')::interval,
    'votants', (select count(*) from votants(p_tour)));
end $$;

-- Les fonctions du mode sujet refusent les modes à binômes.
create or replace function rpc_defier(p_tour uuid, p_valeur text)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare t tours; p parties; v_total int; v_faits int; v_motif text; v_sujet uuid;
begin
  select * into t from tours where id = p_tour;
  if t.id is null then raise exception 'tour introuvable'; end if;
  perform garde_mode(t.partie_id, array['sujet','tournoi']);
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
  perform garde_mode(t.partie_id, array['sujet','tournoi']);
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
