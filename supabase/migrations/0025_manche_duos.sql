-- =============================================================
-- 0025 — La manche des « qui de vous deux »
--
-- Le format le plus drôle du jeu n'existait qu'en UNE question
-- bonus. Les deux membres répondent au même énoncé, on révèle en
-- même temps, et le désaccord EST la blague. Il en faut plusieurs.
--
-- Le tirage passe donc d'un identifiant unique à un TABLEAU de
-- trois, et chaque question vaut 10 points au lieu de 30 — le total
-- d'une partie reste à 100 (10 en QCM + 60 en libre + 30 ici).
--
-- Les lecteurs acceptent les deux formes : une partie en cours au
-- moment de la migration a encore une chaîne dans son tirage, et
-- doit pouvoir finir.
-- =============================================================

create or replace function duos_du_tirage(p_tirage jsonb, p_mode text)
returns text[] language sql immutable
set search_path = public, pg_temp as $$
  select case jsonb_typeof(p_tirage -> p_mode -> 'bonus')
           when 'array'  then array(select jsonb_array_elements_text(p_tirage->p_mode->'bonus'))
           when 'string' then array[p_tirage->p_mode->>'bonus']
           else '{}'::text[]
         end;
$$;
revoke all on function duos_du_tirage(jsonb, text) from public, anon, authenticated;

create or replace function points_manche(p_manche text)
returns int language sql immutable
set search_path = public, pg_temp as $$
  select case p_manche
           when 'qcm'    then 5
           when 'libre'  then 15
           when 'citez3' then 5     -- par réponse commune
           when 'bonus'  then 10    -- 3 duos -> 30 points, total inchangé
           else 0 end;
$$;

-- Le tirage rend trois duos.
create or replace function tirer_duos(p_mode text, p_occasions text[],
                                      p_sensibles boolean, p_n int default 3)
returns text[] language plpgsql security definer
set search_path = public, pg_temp as $$
declare res text[];
begin
  select array_agg(id) into res from (
    select id from questions_index
    where kind = 'bonus' and p_mode = any(modes)
      and (occasion is null or occasion = any(p_occasions))
      and (not sensible or p_sensibles)
    order by random() limit p_n
  ) x;
  if coalesce(array_length(res,1),0) < p_n then
    raise exception 'pas assez de questions « qui de vous deux » pour le mode %', p_mode;
  end if;
  return res;
end $$;
revoke all on function tirer_duos(text, text[], boolean, int) from public, anon, authenticated;

-- La préparation en compte trois.
create or replace function nb_questions_prepa(p_partie uuid)
returns int language sql security definer stable
set search_path = public, pg_temp as $$
  select case format when 'court' then 2 else 3 end       -- ouvertes
       + case format when 'court' then 1 else 2 end       -- qcm
       + 3                                                -- les duos
       + (reglages->>'questionsFinale')::int              -- série de finale
       + case when avec_citez3 then 3 else 0 end
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
  -- les duos : le MÊME énoncé pour les deux membres, c'est le principe
  ids := ids || duos_du_tirage(p.tirage, b.mode);

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

-- Un tour par duo et par binôme, juste avant la finale.
create or replace function fabriquer_tours(p_partie uuid)
returns int language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  p parties;
  v_binomes uuid[]; v_nb int; v_ordre int := 0;
  v_manche text; v_cle text; v_n int;
  k int; bi int; v_slot text;
  v_bid uuid; v_mode text; v_paire text;
  v_repondant uuid; v_questionneur uuid; v_duos text[];
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

  -- la manche des duos : on alterne les binômes à chaque question
  for k in 1..3 loop
    for bi in 1..v_nb loop
      v_bid := v_binomes[bi];
      select mode into v_mode from binomes where id = v_bid;
      v_duos := duos_du_tirage(p.tirage, v_mode);
      exit when k > coalesce(array_length(v_duos,1),0);
      v_questionneur := coalesce(p.presentateur_id, (
        select id from joueurs where binome_id = v_binomes[1 + (bi % v_nb)]
        order by role limit 1));
      v_ordre := v_ordre + 1;
      insert into tours (partie_id, ordre, manche, binome_id, question_id,
                         repondant_id, questionneur_id)
      values (p_partie, v_ordre, 'bonus', v_bid, v_duos[k], null, v_questionneur);
    end loop;
  end loop;

  return v_ordre;
end $$;

-- Le tirage produit trois duos.
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
                 when p.mode_jeu = 'paris' then 'paris' else 'binomes' end;

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
      'bonus',    to_jsonb(tirer_duos(m.mode, v_occ, v_sens, 3)),
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

-- remplir_prepa suit les trois duos
create or replace function remplir_prepa(p_joueur uuid)
returns int language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  j joueurs; p parties; b binomes; v_slot text; v_serie text; v_c3 text;
  i int; n int := 0; q text; v_duo text; v_val text;
begin
  select * into j from joueurs where id = p_joueur;
  if j.binome_id is null then return 0; end if;
  select * into p from parties where id = j.partie_id;
  select * into b from binomes where id = j.binome_id;
  v_slot := lower(j.role);

  for q in select x.value || '.' || v_slot
           from jsonb_array_elements_text(p.tirage->b.mode->'ouvertes') x
           union all
           select x.value || '.' || v_slot
           from jsonb_array_elements_text(p.tirage->b.mode->'qcm') x loop
    insert into reponses_prepa (joueur_id, question_id, valeur) values (p_joueur, q, 'rep-' || q)
    on conflict do nothing;
    n := n + 1;
  end loop;

  -- un duo se joue sur la concordance : une fois sur deux, on s'aligne
  foreach v_duo in array duos_du_tirage(p.tirage, b.mode) loop
    v_val := coalesce(
      (select r.valeur from reponses_prepa r join joueurs o on o.id = r.joueur_id
       where o.binome_id = j.binome_id and r.question_id = v_duo and random() < 0.6 limit 1),
      'duo-' || substr(md5(random()::text), 1, 5));
    insert into reponses_prepa (joueur_id, question_id, valeur) values (p_joueur, v_duo, v_val)
    on conflict do nothing;
    n := n + 1;
  end loop;

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
    (select count(*) from reponses_prepa r where r.joueur_id = p_joueur) where id = p_joueur;
  return n;
end $$;
revoke all on function remplir_prepa(uuid) from public, anon, authenticated;

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
