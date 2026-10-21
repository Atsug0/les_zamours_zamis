-- =============================================================
-- 0005 — Les manches : consigner, révéler, voter, clore
--
-- Deux invariants tenus par le serveur, pas par le client :
--   * le temps (fenêtres de vote, chronos) est validé côté base ;
--   * la réponse enregistrée n'est écrite dans le tour qu'AU MOMENT
--     de la révélation, donc le serveur ne divulgue jamais rien
--     qui ne soit déjà public pour toute la salle.
-- =============================================================

create or replace function normaliser(t text)
returns text language sql immutable
set search_path = public, pg_temp as $$
  select regexp_replace(lower(btrim(coalesce(t,''))), '\s+', ' ', 'g');
$$;

create or replace function points_manche(p_manche text)
returns int language sql immutable
set search_path = public, pg_temp as $$
  select case p_manche when 'qcm' then 5 when 'libre' then 15 when 'bonus' then 30 else 0 end;
$$;

-- Les votants d'un tour : tout le monde sauf les deux du binôme
-- concerné et sauf le présentateur, qui arbitre (règles §6.1).
create or replace function votants(p_tour uuid)
returns setof uuid language sql security definer stable
set search_path = public, pg_temp as $$
  select j.id from tours t
  join joueurs j on j.partie_id = t.partie_id
  join parties p on p.id = t.partie_id
  where t.id = p_tour
    and j.binome_id is distinct from t.binome_id
    and j.binome_id is not null
    and j.id is distinct from p.presentateur_id;
$$;

-- Attribue les points et passe le tour en 'juge'.
create or replace function juger_tour(p_tour uuid, p_verdict boolean)
returns void language plpgsql security definer
set search_path = public, pg_temp as $$
declare t tours; v_pts int;
begin
  select * into t from tours where id = p_tour;
  v_pts := case when p_verdict then points_manche(t.manche) else 0 end;
  update tours set verdict = p_verdict, points = v_pts, statut = 'juge',
                   vote_fin_at = null, vote_restant_ms = null
  where id = p_tour;
  update binomes set score = score + v_pts where id = t.binome_id;
end $$;

-- -------------------------------------------------------------
-- Consigner la réponse donnée à voix haute (§4.1c)
--   QCM   : le joueur lui-même tape son choix -> jugé immédiatement
--   libre : le questionneur consigne 2-3 mots -> puis il révèle
-- -------------------------------------------------------------
create or replace function rpc_consigner(p_tour uuid, p_valeur text)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare t tours; p parties; v_attendue text; v_verdict boolean;
begin
  select * into t from tours where id = p_tour;
  if t.id is null then raise exception 'tour introuvable'; end if;
  select * into p from parties where id = t.partie_id;
  if not est_membre(t.partie_id) then raise exception 'tu n''es pas dans cette partie'; end if;
  if p.en_pause then raise exception 'la partie est en pause'; end if;
  if t.statut <> 'attente' then raise exception 'ce tour est déjà consigné'; end if;
  if t.manche = 'bonus' then raise exception 'le bonus n''a rien à consigner'; end if;
  if length(btrim(coalesce(p_valeur,''))) = 0 then raise exception 'réponse vide'; end if;

  if t.manche = 'qcm' then
    if auth.uid() <> t.repondant_id then
      raise exception 'en QCM, c''est le joueur lui-même qui tape son choix';
    end if;
  else
    if auth.uid() <> t.questionneur_id then
      raise exception 'seul le questionneur du tour consigne';
    end if;
  end if;

  select valeur into v_attendue from reponses_prepa
  where joueur_id = (select id from joueurs
                     where binome_id = t.binome_id and id <> t.repondant_id)
    and question_id = t.question_id;

  update tours set reponse_donnee = btrim(p_valeur), statut = 'consigne' where id = p_tour;

  -- QCM : validation automatique, pas de vote, pas de débat (règles §5)
  if t.manche = 'qcm' then
    update tours set reponse_revelee = v_attendue where id = p_tour;
    v_verdict := normaliser(p_valeur) = normaliser(v_attendue);
    perform juger_tour(p_tour, v_verdict);
    return jsonb_build_object('statut','juge','verdict',v_verdict,
                              'reponse_revelee', v_attendue);
  end if;

  return jsonb_build_object('statut','consigne');
end $$;

-- -------------------------------------------------------------
-- Révéler : c'est ICI que la réponse enregistrée devient publique.
-- -------------------------------------------------------------
create or replace function rpc_reveler(p_tour uuid)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  t tours; p parties; v_attendue text; v_donnee text; v_fenetre int;
  v_a uuid; v_b uuid;
begin
  select * into t from tours where id = p_tour;
  if t.id is null then raise exception 'tour introuvable'; end if;
  select * into p from parties where id = t.partie_id;
  if p.en_pause then raise exception 'la partie est en pause'; end if;
  if auth.uid() <> t.questionneur_id and not peut_orchestrer(t.partie_id) then
    raise exception 'seul le questionneur révèle';
  end if;

  if t.manche = 'bonus' then
    if t.statut <> 'attente' then raise exception 'bonus déjà révélé'; end if;
    -- les DEUX membres ont répondu au même énoncé pendant la prépa :
    -- on dévoile les deux réponses en même temps (règles §7)
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

-- -------------------------------------------------------------
-- Voter. Secret : rien n'est lisible avant le verdict (§6).
-- -------------------------------------------------------------
create or replace function rpc_voter(p_tour uuid, p_pour boolean)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare t tours; p parties;
begin
  select * into t from tours where id = p_tour;
  if t.id is null then raise exception 'tour introuvable'; end if;
  select * into p from parties where id = t.partie_id;
  if p.en_pause then raise exception 'la partie est en pause'; end if;
  if t.statut <> 'vote' then raise exception 'le vote n''est pas ouvert'; end if;
  if t.vote_fin_at is null or now() >= t.vote_fin_at then
    raise exception 'la fenêtre de vote est fermée';
  end if;
  if auth.uid() not in (select votants(p_tour)) then
    raise exception 'tu ne votes pas sur ce tour';
  end if;

  insert into votes (tour_id, joueur_id, pour) values (p_tour, auth.uid(), p_pour)
  on conflict (tour_id, joueur_id) do nothing;

  return jsonb_build_object('vote_enregistre', true,
    'tous_ont_vote', (select count(*) from votes where tour_id = p_tour)
                     >= (select count(*) from votants(p_tour)));
end $$;

-- -------------------------------------------------------------
-- Clore le vote. Refuse avant l'heure, sauf si tout le monde a voté.
-- -------------------------------------------------------------
create or replace function rpc_clore_vote(p_tour uuid)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  t tours; p parties; v_pour int; v_contre int; v_total int; v_verdict boolean;
begin
  select * into t from tours where id = p_tour;
  if t.id is null then raise exception 'tour introuvable'; end if;
  select * into p from parties where id = t.partie_id;
  if t.statut = 'juge' then
    return jsonb_build_object('statut','juge','verdict',t.verdict,'deja',true);
  end if;
  if t.statut <> 'vote' then raise exception 'aucun vote en cours'; end if;
  if not peut_orchestrer(t.partie_id) then
    raise exception 'seuls le plateau, l''hôte et le présentateur closent le vote';
  end if;

  select count(*) filter (where pour), count(*) filter (where not pour)
    into v_pour, v_contre from votes where tour_id = p_tour;
  select count(*) into v_total from votants(p_tour);

  -- avant l'heure, on ne clôt que si tout le monde s'est prononcé
  if now() < t.vote_fin_at and (v_pour + v_contre) < v_total then
    raise exception 'la fenêtre de vote court encore';
  end if;

  if v_pour > v_contre then
    v_verdict := true;
  elsif v_contre > v_pour then
    v_verdict := false;
  elsif p.presentateur_id is not null then
    -- égalité : le présentateur tranche (§6.1). Le tour reste ouvert.
    return jsonb_build_object('statut','vote','egalite',true,
                              'pour',v_pour,'contre',v_contre,'arbitrage_requis',true);
  else
    v_verdict := true;   -- sans présentateur, le doute profite au binôme
  end if;

  perform juger_tour(p_tour, v_verdict);
  return jsonb_build_object('statut','juge','verdict',v_verdict,
                            'pour',v_pour,'contre',v_contre);
end $$;

-- Arbitrage du présentateur, uniquement sur égalité des voix.
create or replace function rpc_arbitrer(p_tour uuid, p_pour boolean)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare t tours; p parties; v_pour int; v_contre int;
begin
  select * into t from tours where id = p_tour;
  select * into p from parties where id = t.partie_id;
  if p.presentateur_id is null or auth.uid() <> p.presentateur_id then
    raise exception 'seul le présentateur arbitre';
  end if;
  if t.statut <> 'vote' then raise exception 'rien à arbitrer'; end if;
  select count(*) filter (where pour), count(*) filter (where not pour)
    into v_pour, v_contre from votes where tour_id = t.id;
  if v_pour <> v_contre then
    raise exception 'les voix ne sont pas à égalité : % contre %', v_pour, v_contre;
  end if;
  perform juger_tour(t.id, p_pour);
  return jsonb_build_object('statut','juge','verdict',p_pour,'arbitre',true);
end $$;

-- Sauter un tour : 0 point, la partie continue (§4.2).
create or replace function rpc_sauter_tour(p_tour uuid)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare t tours;
begin
  select * into t from tours where id = p_tour;
  if t.id is null then raise exception 'tour introuvable'; end if;
  if not peut_orchestrer(t.partie_id) then
    raise exception 'seuls l''hôte et le présentateur sautent un tour';
  end if;
  if t.statut = 'juge' then raise exception 'ce tour est déjà joué'; end if;
  perform juger_tour(p_tour, false);
  return jsonb_build_object('statut','juge','saute',true);
end $$;

-- =============================================================
-- Présence et gel des chronos (§10.c)
-- =============================================================

create or replace function rpc_pouls()
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_partie uuid;
begin
  update joueurs set vu_le = now() where id = auth.uid()
  returning partie_id into v_partie;
  if v_partie is null then
    select id into v_partie from parties where plateau_id = auth.uid();
  end if;
  return jsonb_build_object('partie_id', v_partie, 'at', now());
end $$;

-- Gèle la partie : les chronos s'arrêtent et gardent leur reste.
create or replace function rpc_geler(p_motif text default 'absence')
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_partie uuid;
begin
  select partie_id into v_partie from joueurs where id = auth.uid();
  if v_partie is null then select id into v_partie from parties where plateau_id = auth.uid(); end if;
  if not peut_orchestrer(v_partie) then raise exception 'non autorisé'; end if;
  if (select en_pause from parties where id = v_partie) then
    return jsonb_build_object('en_pause', true, 'deja', true);
  end if;

  update tours set
    vote_restant_ms = greatest(0, (extract(epoch from (vote_fin_at - now())) * 1000)::int),
    vote_fin_at = null
  where partie_id = v_partie and statut = 'vote' and vote_fin_at is not null;

  update passages_finale set
    chrono_restant_ms = greatest(0, (extract(epoch from (chrono_fin_at - now())) * 1000)::int),
    chrono_fin_at = null
  where partie_id = v_partie and chrono_fin_at is not null and seuil_atteint is null;

  update parties set en_pause = true, pause_motif = p_motif, pause_depuis = now()
  where id = v_partie;
  return jsonb_build_object('en_pause', true, 'motif', p_motif);
end $$;

-- Dégèle : chaque chrono repart exactement là où il s'était arrêté.
create or replace function rpc_degeler()
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_partie uuid;
begin
  select partie_id into v_partie from joueurs where id = auth.uid();
  if v_partie is null then select id into v_partie from parties where plateau_id = auth.uid(); end if;
  if not peut_orchestrer(v_partie) then raise exception 'non autorisé'; end if;

  update tours set
    vote_fin_at = now() + (vote_restant_ms || ' milliseconds')::interval,
    vote_restant_ms = null
  where partie_id = v_partie and statut = 'vote' and vote_restant_ms is not null;

  update passages_finale set
    chrono_fin_at = now() + (chrono_restant_ms || ' milliseconds')::interval,
    chrono_restant_ms = null
  where partie_id = v_partie and chrono_restant_ms is not null and seuil_atteint is null;

  update parties set en_pause = false, pause_motif = null, pause_depuis = null
  where id = v_partie;
  return jsonb_build_object('en_pause', false);
end $$;

-- Appelée par le plateau en boucle : gèle si le joueur ATTENDU est
-- absent, dégèle quand il revient. Un simple votant absent ne gèle
-- rien — c'est une abstention (règles §4.2).
create or replace function rpc_verifier_presence()
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  p parties; v_partie uuid; v_absents text[]; v_seuil timestamptz;
begin
  select id into v_partie from parties where plateau_id = auth.uid();
  if v_partie is null then select partie_id into v_partie from joueurs where id = auth.uid(); end if;
  if not peut_orchestrer(v_partie) then raise exception 'non autorisé'; end if;
  select * into p from parties where id = v_partie;
  v_seuil := now() - interval '30 seconds';

  select array_agg(distinct j.prenom) into v_absents
  from joueurs j
  where j.partie_id = v_partie and j.vu_le < v_seuil and (
        j.id in (select unnest(array[t.repondant_id, t.questionneur_id])
                 from tours t where t.partie_id = v_partie
                   and t.statut in ('attente','consigne'))
     or j.id in (select unnest(array[f.joueur_id, f.questionneur_id])
                 from passages_finale f where f.partie_id = v_partie
                   and f.seuil_atteint is null and f.serie_id is not null));

  if v_absents is not null and not p.en_pause then
    perform rpc_geler('absence');
    return jsonb_build_object('en_pause', true, 'attend', to_jsonb(v_absents));
  elsif v_absents is null and p.en_pause and p.pause_motif = 'absence' then
    perform rpc_degeler();
    return jsonb_build_object('en_pause', false, 'reprise', true);
  end if;
  return jsonb_build_object('en_pause', p.en_pause,
                            'attend', coalesce(to_jsonb(v_absents), '[]'::jsonb));
end $$;

-- =============================================================
-- Machine à états : avancer l'émission
-- =============================================================
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
    -- plus aucun tour de manche : la finale, puis le palmarès
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

do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p
           join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like 'rpc_%'
  loop
    execute format('revoke execute on function %s from public, anon', f.sig);
    execute format('grant  execute on function %s to authenticated', f.sig);
  end loop;
end $$;
