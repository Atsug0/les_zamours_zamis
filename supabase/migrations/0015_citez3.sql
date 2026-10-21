-- =============================================================
-- 0015 — La manche « cite 3 » (variante, règles §9.3)
--
-- Reprise des questions finales du questionnaire d'origine. Chaque
-- joueur cite, EN PRÉPARATION, trois choses sur son partenaire ;
-- pendant la manche, le partenaire doit retrouver les trois.
--
-- Deux passages par binôme, un par sens : c'est ce qui la rend
-- symétrique avec toutes les autres manches et permet de réutiliser
-- les paires, les sets croisés et la fabrication des tours.
-- 5 points par réponse commune, 15 par passage, 30 par binôme.
--
-- Jugée par le QUESTIONNEUR, pas par un vote : trois réponses à
-- faire voter une par une casserait le rythme. Il annonce combien
-- ont concordé, la salle voit les deux triplets côte à côte.
-- =============================================================

alter table parties add column avec_citez3 boolean not null default false;
alter table tours drop constraint tours_manche_check;
alter table tours add constraint tours_manche_check
  check (manche in ('qcm','libre','citez3','bonus'));

-- -------------------------------------------------------------
-- Le tirage gagne deux énoncés « cite 3 », un par slot.
-- -------------------------------------------------------------
create or replace function tirer_citez3(p_mode text, p_occasions text[], p_sensibles boolean)
returns text[] language plpgsql security definer
set search_path = public, pg_temp as $$
declare res text[];
begin
  select array_agg(id) into res from (
    select id from questions_index
    where kind = 'citez3' and p_mode = any(modes)
      and (occasion is null or occasion = any(p_occasions))
      and (not sensible or p_sensibles)
    order by random() limit 2
  ) x;
  if coalesce(array_length(res,1),0) < 2 then
    raise exception 'il faut au moins deux énoncés « cite 3 » pour le mode %', p_mode;
  end if;
  return res;
end $$;

create or replace function nb_questions_prepa(p_partie uuid)
returns int language sql security definer stable
set search_path = public, pg_temp as $$
  select case format when 'court' then 2 else 3 end       -- ouvertes
       + case format when 'court' then 1 else 2 end       -- qcm
       + 1                                                -- bonus
       + (reglages->>'questionsFinale')::int              -- série de finale
       + case when avec_citez3 then 3 else 0 end          -- les trois réponses
  from parties where id = p_partie;
$$;

create or replace function rpc_mes_questions()
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  j joueurs; p parties; b binomes; v_slot text; ids text[] := '{}';
  v_serie text; v_c3 text; i int;
begin
  select * into j from joueurs where id = auth.uid();
  if j.id is null then raise exception 'rejoins la partie d''abord'; end if;
  if j.binome_id is null then raise exception 'le présentateur ne prépare rien'; end if;
  select * into p from parties where id = j.partie_id;
  select * into b from binomes where id = j.binome_id;
  v_slot := lower(j.role);

  select array_agg(x || '.' || v_slot order by o) into ids
  from (select x, o from jsonb_array_elements_text(p.tirage->b.mode->'ouvertes')
        with ordinality t(x,o)) z;

  ids := ids || array(select x || '.' || v_slot
                      from jsonb_array_elements_text(p.tirage->b.mode->'qcm') x);
  ids := ids || array[p.tirage->b.mode->>'bonus'];

  -- « cite 3 » : trois sous-réponses au même énoncé, propre à son slot
  if p.avec_citez3 then
    v_c3 := p.tirage->b.mode->'citez3'->>(case j.role when 'A' then 0 else 1 end);
    for i in 1..3 loop ids := ids || array[v_c3 || '.' || i]; end loop;
  end if;

  v_serie := p.tirage->b.mode->>'finale';
  for i in 1..(p.reglages->>'questionsFinale')::int loop
    ids := ids || array[v_serie || '.' || i];
  end loop;

  return jsonb_build_object('role', j.role, 'mode', b.mode,
                            'questions', to_jsonb(ids),
                            'citez3', p.tirage->b.mode->'citez3'->(case j.role when 'A' then 0 else 1 end),
                            'total', array_length(ids,1));
end $$;

-- -------------------------------------------------------------
-- Fabrication des tours : la manche s'insère juste avant le bonus.
-- -------------------------------------------------------------
create or replace function fabriquer_tours(p_partie uuid)
returns int language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  p parties;
  v_binomes uuid[]; v_nb int; v_ordre int := 0;
  v_manche text; v_cle text; v_n int;
  k int; bi int; v_slot text;
  v_bid uuid; v_mode text; v_paire text;
  v_repondant uuid; v_questionneur uuid;
begin
  select * into p from parties where id = p_partie;
  delete from tours where partie_id = p_partie;

  select array_agg(id order by couleur) into v_binomes from binomes where partie_id = p_partie;
  v_nb := array_length(v_binomes, 1);

  foreach v_manche in array array['qcm','libre'] loop
    v_cle := case v_manche when 'qcm' then 'qcm' else 'ouvertes' end;
    v_n   := case v_manche
               when 'qcm'  then case p.format when 'court' then 1 else 2 end
               else             case p.format when 'court' then 2 else 3 end end;

    for k in 1..v_n loop
      foreach v_slot in array array['a','b'] loop
        for bi in 1..v_nb loop
          v_bid  := v_binomes[bi];
          select mode into v_mode from binomes where id = v_bid;
          v_paire := p.tirage -> v_mode -> v_cle ->> (k - 1);
          select id into v_repondant from joueurs
          where binome_id = v_bid and role = case v_slot when 'a' then 'B' else 'A' end;
          v_questionneur := coalesce(p.presentateur_id, (
            select id from joueurs where binome_id = v_binomes[1 + (bi % v_nb)]
            order by case when (k + bi) % 2 = 0 then role end nulls last, role limit 1));
          v_ordre := v_ordre + 1;
          insert into tours (partie_id, ordre, manche, binome_id, question_id,
                             repondant_id, questionneur_id)
          values (p_partie, v_ordre, v_manche, v_bid, v_paire || '.' || v_slot,
                  v_repondant, v_questionneur);
        end loop;
      end loop;
    end loop;
  end loop;

  -- La manche « cite 3 », si elle est activée : deux passages par
  -- binôme, un par sens, juste avant le bonus.
  if p.avec_citez3 then
    for k in 0..1 loop
      for bi in 1..v_nb loop
        v_bid := v_binomes[bi];
        select mode into v_mode from binomes where id = v_bid;
        select id into v_repondant from joueurs
        where binome_id = v_bid and role = case k when 0 then 'B' else 'A' end;
        v_questionneur := coalesce(p.presentateur_id, (
          select id from joueurs where binome_id = v_binomes[1 + (bi % v_nb)]
          order by role limit 1));
        v_ordre := v_ordre + 1;
        insert into tours (partie_id, ordre, manche, binome_id, question_id,
                           repondant_id, questionneur_id)
        values (p_partie, v_ordre, 'citez3', v_bid,
                p.tirage -> v_mode -> 'citez3' ->> k, v_repondant, v_questionneur);
      end loop;
    end loop;
  end if;

  for bi in 1..v_nb loop
    v_bid := v_binomes[bi];
    select mode into v_mode from binomes where id = v_bid;
    v_questionneur := coalesce(p.presentateur_id, (
      select id from joueurs where binome_id = v_binomes[1 + (bi % v_nb)]
      order by role limit 1));
    v_ordre := v_ordre + 1;
    insert into tours (partie_id, ordre, manche, binome_id, question_id,
                       repondant_id, questionneur_id)
    values (p_partie, v_ordre, 'bonus', v_bid, p.tirage -> v_mode ->> 'bonus',
            null, v_questionneur);
  end loop;

  return v_ordre;
end $$;

-- -------------------------------------------------------------
-- Juger un « cite 3 » : le questionneur consigne les trois réponses
-- données et annonce combien ont concordé.
-- -------------------------------------------------------------
create or replace function rpc_juger_citez3(p_tour uuid, p_valeurs text[], p_concordes int)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare t tours; p parties; v_attendues text; v_pts int;
begin
  select * into t from tours where id = p_tour;
  if t.id is null then raise exception 'tour introuvable'; end if;
  if t.manche <> 'citez3' then raise exception 'ce tour n''est pas un « cite 3 »'; end if;
  select * into p from parties where id = t.partie_id;
  if p.en_pause then raise exception 'la partie est en pause'; end if;
  if auth.uid() <> t.questionneur_id then
    raise exception 'seul le questionneur juge ce tour';
  end if;
  if t.statut = 'juge' then raise exception 'ce tour est déjà jugé'; end if;
  if p_concordes < 0 or p_concordes > 3 then raise exception 'entre 0 et 3 réponses communes'; end if;

  select string_agg(r.valeur, ' · ' order by r.question_id) into v_attendues
  from reponses_prepa r
  where r.joueur_id = (select id from joueurs
                       where binome_id = t.binome_id and id <> t.repondant_id)
    and r.question_id like t.question_id || '.%';

  v_pts := p_concordes * 5;
  update tours set
    reponse_donnee  = array_to_string(p_valeurs, ' · '),
    reponse_revelee = v_attendues,
    verdict = p_concordes > 0,
    points = v_pts,
    statut = 'juge'
  where id = p_tour;
  update binomes set score = score + v_pts where id = t.binome_id;

  return jsonb_build_object('concordes', p_concordes, 'points', v_pts,
                            'reponse_revelee', v_attendues);
end $$;

-- rpc_lancer prend l'option. On SUPPRIME l'ancienne signature : un
-- « create or replace » avec une liste d'arguments différente crée une
-- SURCHARGE, et l'appel devient ambigu — pour psql comme pour PostgREST.
drop function if exists rpc_lancer(text);
create or replace function rpc_lancer(p_format text default 'court',
                                      p_citez3 boolean default false)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  p parties; v_partie uuid; n_ouvertes int; n_qcm int;
  v_tirage jsonb := '{}'::jsonb; m record;
  v_occ text[]; v_sens boolean; v_binomes uuid[]; v_nb int;
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
  if v_nb < 2 then
    raise exception 'il faut au moins deux binômes : sans adversaire, personne ne peut voter';
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
      'sensibles', v_sens,
      'occasions', to_jsonb(v_occ)
    ));
  end loop;

  update parties set format = p_format, tirage = v_tirage,
                     avec_citez3 = coalesce(p_citez3,false), etat = 'prep'
  where id = v_partie;

  select array_agg(id order by couleur) into v_binomes from binomes where partie_id = v_partie;
  perform fabriquer_tours(v_partie);

  return jsonb_build_object('etat','prep','tirage',v_tirage,
                            'tours',(select count(*) from tours where partie_id = v_partie));
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
  -- les helpers restent fermés (0009)
  for f in select p.oid::regprocedure as sig from pg_proc p
           join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public'
             and p.proname in ('tirer_citez3','fabriquer_tours','nb_questions_prepa')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;

-- rpc_suivant écrit « etat = manche » : la contrainte sur parties.etat
-- doit donc connaître la nouvelle manche, sinon la partie plante en
-- arrivant dessus. Attrapé par le typage du front, pas par les tests
-- SQL — d'où l'assertion ajoutée dans 40_citez3.sql.
alter table parties drop constraint parties_etat_check;
alter table parties add constraint parties_etat_check
  check (etat in ('lobby','prep','qcm','libre','citez3','bonus','finale','palmares'));
