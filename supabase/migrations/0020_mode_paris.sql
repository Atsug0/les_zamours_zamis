-- =============================================================
-- 0020 — « Tous contre le binôme » : le public parie
--
-- Le jeu à binômes, mais à chaque question le reste de la salle
-- PARIE sur la concordance, avant la révélation. Deux façons de
-- marquer sur un seul tableau : bien se connaître, et bien lire les
-- autres. Et surtout, le public a enfin quelque chose à faire à
-- CHAQUE tour — aujourd'hui il ne vote que sur les questions libres.
--
-- CONFLIT D'INTÉRÊTS, ET SA RÉSOLUTION.
-- On ne peut pas à la fois parier sur un résultat et le juger : qui a
-- parié « ça ne concordera pas » a tout intérêt à refuser la réponse.
-- Dans ce mode, le jugement est donc MÉCANIQUE — comparaison
-- normalisée — et seul le présentateur ou l'hôte peut le corriger,
-- lui qui ne parie pas. Le pari porte ainsi sur un fait, pas sur une
-- opinion, ce qui est de toute façon plus satisfaisant à parier.
-- =============================================================

alter table parties drop constraint parties_mode_jeu_check;
alter table parties add constraint parties_mode_jeu_check
  check (mode_jeu in ('binomes','sujet','duel','tournoi','paris'));

-- Le mode se choisit au lobby, avant de lancer.
create or replace function rpc_choisir_mode_jeu(p_mode text)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_partie uuid;
begin
  if p_mode not in ('binomes','paris') then
    raise exception 'ce mode ne se choisit pas ici';
  end if;
  select partie_id into v_partie from joueurs where id = auth.uid();
  if v_partie is null then select id into v_partie from parties where plateau_id = auth.uid(); end if;
  if not peut_orchestrer(v_partie) then raise exception 'non autorisé'; end if;
  if (select etat from parties where id = v_partie) <> 'lobby' then
    raise exception 'trop tard';
  end if;
  update parties set mode_jeu = p_mode where id = v_partie;
  return jsonb_build_object('mode_jeu', p_mode);
end $$;

-- rpc_lancer conserve le mode « paris » choisi au lobby.
create or replace function rpc_lancer(p_format text default 'court',
                                      p_citez3 boolean default false)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  p parties; v_partie uuid; n_ouvertes int; n_qcm int;
  v_tirage jsonb := '{}'::jsonb; m record;
  v_occ text[]; v_sens boolean; v_nb int; v_joueurs int; v_duel boolean; v_mode text;
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
  v_duel := (v_nb = 1 and v_joueurs = 2);
  if v_nb < 2 and not v_duel then
    raise exception 'il faut au moins deux binômes, ou alors être exactement deux pour un duel';
  end if;
  if p.mode_jeu = 'paris' and v_duel then
    raise exception 'les paris demandent un public : il faut au moins deux binômes';
  end if;

  v_mode := case when v_duel then 'duel'
                 when p.mode_jeu = 'paris' then 'paris'
                 else 'binomes' end;

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
                     mode_jeu = v_mode, etat = 'prep'
  where id = v_partie;

  perform fabriquer_tours(v_partie);
  return jsonb_build_object('etat','prep','mode_jeu',v_mode,
                            'tours',(select count(*) from tours where partie_id = v_partie));
end $$;

-- -------------------------------------------------------------
-- En mode paris, la consignation N'ÉMET PAS de jugement : elle
-- ouvre les paris. Même en QCM — c'est là que c'est le plus drôle,
-- parce que tout le monde croit connaître la réponse.
-- -------------------------------------------------------------
create or replace function rpc_consigner(p_tour uuid, p_valeur text)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  t tours; p parties; v_attendue text; v_verdict boolean;
  v_duel boolean; v_paris boolean; v_motif text;
begin
  select * into t from tours where id = p_tour;
  if t.id is null then raise exception 'tour introuvable'; end if;
  select * into p from parties where id = t.partie_id;
  if not est_membre(t.partie_id) then raise exception 'tu n''es pas dans cette partie'; end if;
  if p.en_pause then raise exception 'la partie est en pause'; end if;
  if t.statut <> 'attente' then raise exception 'ce tour est déjà consigné'; end if;
  if t.manche = 'bonus' then raise exception 'le bonus n''a rien à consigner'; end if;
  if length(btrim(coalesce(p_valeur,''))) = 0 then raise exception 'réponse vide'; end if;
  v_duel  := p.mode_jeu = 'duel';
  v_paris := p.mode_jeu = 'paris';

  if t.manche = 'qcm' or v_duel then
    if auth.uid() <> t.repondant_id then
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

  -- mode paris : on s'arrête là, le public doit pouvoir parier
  if v_paris then
    return jsonb_build_object('statut','consigne','paris_ouverts',true);
  end if;

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

-- -------------------------------------------------------------
-- Parier. Tout le monde sauf le binôme en jeu — le présentateur ne
-- parie pas : c'est lui qui peut corriger le verdict.
-- -------------------------------------------------------------
create or replace function parieurs(p_tour uuid)
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
revoke all on function parieurs(uuid) from public, anon, authenticated;

create or replace function rpc_parier(p_tour uuid, p_concorde boolean)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare t tours; p parties; v_faits int; v_total int;
begin
  select * into t from tours where id = p_tour;
  if t.id is null then raise exception 'tour introuvable'; end if;
  select * into p from parties where id = t.partie_id;
  if p.mode_jeu <> 'paris' then raise exception 'on ne parie que dans ce mode'; end if;
  if p.en_pause then raise exception 'la partie est en pause'; end if;
  if t.statut <> 'consigne' then
    raise exception 'les paris ne sont pas ouverts';
  end if;
  if auth.uid() not in (select parieurs(p_tour)) then
    raise exception 'tu ne paries pas sur ce tour';
  end if;

  insert into reponses_manche (tour_id, joueur_id, valeur)
  values (p_tour, auth.uid(), case when p_concorde then 'oui' else 'non' end)
  on conflict (tour_id, joueur_id) do update set valeur = excluded.valeur, ecrit_le = now();

  select count(*) into v_faits from reponses_manche where tour_id = p_tour;
  select count(*) into v_total from parieurs(p_tour);
  update tours set reponses_recues = v_faits where id = p_tour;

  return jsonb_build_object('paris', v_faits, 'total', v_total,
                            'tous_ont_parie', v_faits >= v_total);
end $$;

-- -------------------------------------------------------------
-- Clôture : le binôme marque sa manche, et chaque parieur qui a
-- lu juste marque 5 points pour son propre binôme.
-- -------------------------------------------------------------
create or replace function rpc_clore_paris(p_tour uuid, p_verdict boolean default null)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  t tours; p parties; v_attendue text; v_verdict boolean;
  v_bons int; v_pts int;
begin
  select * into t from tours where id = p_tour;
  if t.id is null then raise exception 'tour introuvable'; end if;
  select * into p from parties where id = t.partie_id;
  if p.mode_jeu <> 'paris' then raise exception 'mauvais mode de jeu'; end if;
  if t.statut = 'juge' then return jsonb_build_object('deja', true); end if;
  if t.statut not in ('consigne','revele') then raise exception 'rien à clore'; end if;
  if auth.uid() <> t.questionneur_id and not peut_orchestrer(t.partie_id) then
    raise exception 'seuls le questionneur, l''hôte et le présentateur closent';
  end if;
  -- corriger le verdict est réservé à qui ne parie pas
  if p_verdict is not null and not peut_orchestrer(t.partie_id) then
    raise exception 'seuls l''hôte et le présentateur corrigent un verdict : ils ne parient pas';
  end if;

  if t.manche = 'bonus' then
    select valeur into v_attendue from reponses_prepa
    where joueur_id = (select id from joueurs where binome_id = t.binome_id and role = 'B')
      and question_id = t.question_id;
    update tours set reponse_donnee = coalesce(t.reponse_donnee, (
      select valeur from reponses_prepa
      where joueur_id = (select id from joueurs where binome_id = t.binome_id and role = 'A')
        and question_id = t.question_id))
    where id = p_tour;
    select * into t from tours where id = p_tour;
  else
    select valeur into v_attendue from reponses_prepa
    where joueur_id = (select id from joueurs where binome_id = t.binome_id
                         and id <> t.repondant_id)
      and question_id = t.question_id;
  end if;

  v_verdict := coalesce(p_verdict, normaliser(t.reponse_donnee) = normaliser(v_attendue));
  update tours set reponse_revelee = v_attendue where id = p_tour;

  -- les paris justes
  update reponses_manche r set juste = ((r.valeur = 'oui') = v_verdict)
  where r.tour_id = p_tour;
  select count(*) into v_bons from reponses_manche where tour_id = p_tour and juste;

  -- 5 points par parieur qui a lu juste, à son propre binôme
  update binomes b set score = b.score + 5 * (
    select count(*) from reponses_manche r
    join joueurs j on j.id = r.joueur_id
    where r.tour_id = p_tour and r.juste and j.binome_id = b.id)
  where b.partie_id = t.partie_id;

  -- et le binôme en jeu marque sa manche
  v_pts := case when v_verdict then points_manche(t.manche) else 0 end;
  update tours set verdict = v_verdict, points = v_pts, statut = 'juge' where id = p_tour;
  update binomes set score = score + v_pts where id = t.binome_id;

  return jsonb_build_object('statut','juge','verdict',v_verdict,
                            'reponse_revelee', v_attendue,
                            'paris_justes', v_bons,
                            'points_binome', v_pts);
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
