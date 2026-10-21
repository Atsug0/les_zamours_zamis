-- =============================================================
-- 0018 — Le duel : deux personnes, qui connaît le mieux l'autre
--
-- Un seul binôme, donc PLUS AUCUN VOTANT : les questions libres
-- sont normalement jugées par les autres binômes, et il n'y en a
-- pas. Laisser le mécanisme en place validerait tout (0 voix pour,
-- 0 contre = égalité = le doute profite au binôme).
--
-- Trois options étaient possibles :
--   a) l'adversaire juge      -> il est juge et partie ;
--   b) tout en QCM            -> on perd l'intérêt du jeu ;
--   c) auto-jugement + contestation.
--
-- On retient (c). La concordance est calculée mécaniquement, donc
-- personne ne peut tricher sur la consignation. Celui qui n'est pas
-- d'accord conteste UNE fois, et l'autre tranche : c'est un duel,
-- la pression sociale suffit, et un refus de mauvaise foi se voit.
--
-- Le mode s'active tout seul : deux joueurs, un binôme, on lance.
-- Aucune case à cocher.
-- =============================================================

alter table parties drop constraint parties_mode_jeu_check;
alter table parties add constraint parties_mode_jeu_check
  check (mode_jeu in ('binomes','sujet','duel'));

alter table tours add column contestee boolean not null default false;

create or replace function mode_duel(p_partie uuid)
returns boolean language sql security definer stable
set search_path = public, pg_temp as $$
  select mode_jeu = 'duel' from parties where id = p_partie;
$$;
revoke all on function mode_duel(uuid) from public, anon, authenticated;

-- -------------------------------------------------------------
-- Lancement : un seul binôme est accepté s'il n'y a que deux joueurs.
-- -------------------------------------------------------------
create or replace function rpc_lancer(p_format text default 'court',
                                      p_citez3 boolean default false)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  p parties; v_partie uuid; n_ouvertes int; n_qcm int;
  v_tirage jsonb := '{}'::jsonb; m record;
  v_occ text[]; v_sens boolean; v_nb int; v_joueurs int; v_duel boolean;
begin
  select pa.* into p from parties pa
  where pa.id = (select partie_id from joueurs where id = auth.uid())
     or pa.plateau_id = auth.uid()
  limit 1;
  if p.id is null then raise exception 'partie introuvable'; end if;
  v_partie := p.id;

  if not peut_orchestrer(v_partie) then
    raise exception 'seuls le plateau, l''hôte et le présentateur lancent la partie';
  end if;
  if p.etat <> 'lobby' then raise exception 'la partie est déjà lancée'; end if;
  if p_format not in ('court','long') then raise exception 'format inconnu'; end if;
  if exists (select 1 from binomes where partie_id = v_partie and not verrouille) then
    raise exception 'tous les binômes doivent avoir choisi leur mode';
  end if;
  if exists (select 1 from joueurs where partie_id = v_partie and binome_id is null
               and id is distinct from p.presentateur_id) then
    raise exception 'un joueur n''est ni en binôme ni présentateur';
  end if;

  select count(*) into v_nb from binomes where partie_id = v_partie;
  select count(*) into v_joueurs from joueurs where partie_id = v_partie;

  -- Le duel s'active de lui-même : deux joueurs, un binôme.
  v_duel := (v_nb = 1 and v_joueurs = 2);
  if v_nb < 2 and not v_duel then
    raise exception 'il faut au moins deux binômes, ou alors être exactement deux pour un duel';
  end if;

  n_ouvertes := case p_format when 'court' then 2 else 3 end;
  n_qcm      := case p_format when 'court' then 1 else 2 end;

  for m in select mode from binomes where partie_id = v_partie group by mode loop
    select bool_and(sensibles) into v_sens
      from binomes where partie_id = v_partie and mode = m.mode;
    select coalesce((select array_agg(o) from (
             select unnest(occasions) as o from binomes
             where partie_id = v_partie and mode = m.mode
             group by o having count(*) = (select count(*) from binomes
                                           where partie_id = v_partie and mode = m.mode)
           ) z), '{}') into v_occ;

    v_tirage := v_tirage || jsonb_build_object(m.mode, jsonb_build_object(
      'ouvertes', to_jsonb(tirer_paires(m.mode,'ouverte', v_occ, v_sens, n_ouvertes)),
      'qcm',      to_jsonb(tirer_paires(m.mode,'qcm',     v_occ, v_sens, n_qcm)),
      'bonus',    tirer_un(m.mode,'bonus',        v_occ, v_sens),
      'finale',   tirer_un(m.mode,'serie_finale', v_occ, v_sens),
      'citez3',   case when coalesce(p_citez3,false)
                       then to_jsonb(tirer_citez3(m.mode, v_occ, v_sens))
                       else '[]'::jsonb end,
      'sensibles', v_sens, 'occasions', to_jsonb(v_occ)
    ));
  end loop;

  update parties set format = p_format, tirage = v_tirage,
                     avec_citez3 = coalesce(p_citez3,false),
                     mode_jeu = case when v_duel then 'duel' else 'binomes' end,
                     etat = 'prep'
  where id = v_partie;

  perform fabriquer_tours(v_partie);
  return jsonb_build_object('etat','prep','mode_jeu', case when v_duel then 'duel' else 'binomes' end,
                            'tours',(select count(*) from tours where partie_id = v_partie));
end $$;

-- -------------------------------------------------------------
-- En duel, c'est le répondant qui consigne sa propre réponse, et la
-- concordance est calculée mécaniquement : il n'y a personne pour
-- arbitrer, donc personne ne doit pouvoir tricher sur la saisie.
-- -------------------------------------------------------------
create or replace function rpc_consigner(p_tour uuid, p_valeur text)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare t tours; p parties; v_attendue text; v_verdict boolean; v_duel boolean; v_motif text;
begin
  select * into t from tours where id = p_tour;
  if t.id is null then raise exception 'tour introuvable'; end if;
  select * into p from parties where id = t.partie_id;
  if not est_membre(t.partie_id) then raise exception 'tu n''es pas dans cette partie'; end if;
  if p.en_pause then raise exception 'la partie est en pause'; end if;
  if t.statut <> 'attente' then raise exception 'ce tour est déjà consigné'; end if;
  if t.manche = 'bonus' then raise exception 'le bonus n''a rien à consigner'; end if;
  if length(btrim(coalesce(p_valeur,''))) = 0 then raise exception 'réponse vide'; end if;
  v_duel := p.mode_jeu = 'duel';

  if t.manche = 'qcm' or v_duel then
    if auth.uid() <> t.repondant_id then
      -- RAISE n'accepte pas d'expression CASE : on la calcule d'abord.
      v_motif := case when v_duel then 'en duel, chacun saisit sa propre réponse'
                      else 'en QCM, c''est le joueur lui-même qui tape son choix' end;
      raise exception '%', v_motif;
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

  -- QCM et duel : jugement mécanique, pas de vote
  if t.manche = 'qcm' or v_duel then
    update tours set reponse_revelee = v_attendue where id = p_tour;
    v_verdict := normaliser(p_valeur) = normaliser(v_attendue);
    perform juger_tour(p_tour, v_verdict);
    return jsonb_build_object('statut','juge','verdict',v_verdict,
                              'reponse_revelee', v_attendue,
                              'contestable', v_duel and not v_verdict);
  end if;

  return jsonb_build_object('statut','consigne');
end $$;

-- Le bonus en duel : les deux ont préparé la même question, on compare.
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

  -- en duel, aucun votant : on juge mécaniquement
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

-- -------------------------------------------------------------
-- Contester une fois, et l'adversaire tranche.
-- -------------------------------------------------------------
create or replace function rpc_contester(p_tour uuid)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare t tours; p parties; moi joueurs;
begin
  select * into t from tours where id = p_tour;
  if t.id is null then raise exception 'tour introuvable'; end if;
  select * into p from parties where id = t.partie_id;
  if p.mode_jeu <> 'duel' then
    raise exception 'la contestation n''existe qu''en duel : ailleurs, c''est la salle qui vote';
  end if;
  select * into moi from joueurs where id = auth.uid();
  if moi.binome_id is distinct from t.binome_id then
    raise exception 'ce n''est pas ton tour';
  end if;
  if t.statut <> 'juge' then raise exception 'rien à contester'; end if;
  if t.verdict then raise exception 'cette réponse a déjà été comptée'; end if;
  if t.contestee then raise exception 'on ne conteste qu''une fois par tour'; end if;

  -- on retire les points éventuels et on rouvre
  update binomes set score = score - t.points where id = t.binome_id;
  update tours set contestee = true, statut = 'revele', points = 0, verdict = null
  where id = p_tour;
  return jsonb_build_object('statut','revele','contestee',true,
    'arbitre', (select id from joueurs where binome_id = t.binome_id and id <> auth.uid()));
end $$;

create or replace function rpc_trancher_contestation(p_tour uuid, p_accepte boolean)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare t tours; p parties; moi joueurs;
begin
  select * into t from tours where id = p_tour;
  if t.id is null then raise exception 'tour introuvable'; end if;
  select * into p from parties where id = t.partie_id;
  if not t.contestee or t.statut <> 'revele' then raise exception 'aucune contestation en cours'; end if;
  select * into moi from joueurs where id = auth.uid();
  if moi.binome_id is distinct from t.binome_id then raise exception 'ce n''est pas ton tour'; end if;
  if auth.uid() = t.repondant_id then
    raise exception 'c''est à l''autre de trancher : on ne s''accorde pas ses propres points';
  end if;
  perform juger_tour(p_tour, p_accepte);
  return jsonb_build_object('statut','juge','verdict',p_accepte);
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
