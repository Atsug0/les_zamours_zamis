-- =============================================================
-- 0004 — Lancement, tirage serveur, préparation
--
-- Le tirage est fait ICI, par le serveur, et jamais par un client :
-- c'est ce qui garantit qu'il est identique pour tous les binômes
-- d'un même mode, donc que le vote des autres porte sur une base
-- comparable (règles §3.1).
-- =============================================================

-- Tire n paires d'un type donné, en imposant des THÈMES DISTINCTS.
-- C'est ce qui tient la promesse des règles §3.1 : un binôme ne
-- tombe jamais deux fois sur le même thème.
create or replace function tirer_paires(p_mode text, p_kind text, p_occasions text[],
                                        p_sensibles boolean, p_n int)
returns text[] language plpgsql security definer
set search_path = public, pg_temp as $$
declare res text[];
begin
  select array_agg(paire) into res from (
    select paire from (
      -- une seule paire par thème, tirée au hasard dans le thème
      select distinct on (theme) theme, paire from (
        select paire, min(theme) as theme
        from questions_index
        where kind = p_kind
          and p_mode = any(modes)
          and (occasion is null or occasion = any(p_occasions))
          and (not sensible or p_sensibles)
        group by paire
        having count(*) = 2              -- les deux slots doivent passer les filtres
      ) c
      order by theme, random()
    ) t
    order by random()
    limit p_n
  ) x;

  if coalesce(array_length(res,1),0) < p_n then
    raise exception 'banque insuffisante : % paires % pour le mode % (il en faut %)',
      coalesce(array_length(res,1),0), p_kind, p_mode, p_n;
  end if;
  return res;
end $$;

create or replace function tirer_un(p_mode text, p_kind text, p_occasions text[],
                                    p_sensibles boolean)
returns text language plpgsql security definer
set search_path = public, pg_temp as $$
declare res text;
begin
  select id into res from questions_index
  where kind = p_kind
    and p_mode = any(modes)
    and (occasion is null or occasion = any(p_occasions))
    and (not sensible or p_sensibles)
  order by random() limit 1;
  if res is null then
    raise exception 'aucune question % disponible pour le mode %', p_kind, p_mode;
  end if;
  return res;
end $$;

-- -------------------------------------------------------------
-- rpc_lancer : vérifie, tire, fabrique TOUS les tours, passe en prep.
-- -------------------------------------------------------------
create or replace function rpc_lancer(p_format text default 'court')
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  p parties;
  v_partie uuid;
  n_ouvertes int; n_qcm int;
  v_tirage jsonb := '{}'::jsonb;
  m record;
  v_occ text[]; v_sens boolean;
  v_binomes uuid[]; v_nb int;
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
  if exists (select 1 from joueurs
             where partie_id = v_partie and binome_id is null
               and id is distinct from p.presentateur_id) then
    raise exception 'un joueur n''est ni en binôme ni présentateur';
  end if;
  select count(*) into v_nb from binomes where partie_id = v_partie;
  if v_nb < 2 then
    raise exception 'il faut au moins deux binômes : sans adversaire, personne ne peut voter';
  end if;

  n_ouvertes := case p_format when 'court' then 2 else 3 end;
  n_qcm      := case p_format when 'court' then 1 else 2 end;

  -- Un tirage par mode présent. Les catégories sensibles et les blocs
  -- d'occasion ne sont retenus que si TOUS les binômes du mode les ont
  -- activés : le tirage doit rester identique pour tout le monde, donc
  -- on prend l'intersection des consentements.
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
      'sensibles', v_sens,
      'occasions', to_jsonb(v_occ)
    ));
  end loop;

  update parties set format = p_format, tirage = v_tirage, etat = 'prep' where id = v_partie;

  -- Ordre de passage des binômes, stable sur toute la partie.
  select array_agg(id order by couleur) into v_binomes
  from binomes where partie_id = v_partie;
  v_nb := array_length(v_binomes, 1);

  perform fabriquer_tours(v_partie);

  return jsonb_build_object('etat','prep','tirage',v_tirage,
                            'tours',(select count(*) from tours where partie_id = v_partie));
end $$;

-- -------------------------------------------------------------
-- Fabrique tous les tours des manches, dans l'ordre de jeu.
--
-- On alterne les binômes À CHAQUE QUESTION (règles §5) : personne
-- n'enchaîne quatre tours pendant que les autres regardent.
-- Ordre : manche → paire → slot → binôme.
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

          -- le slot 'a' a été préparé par le joueur de rôle A :
          -- c'est donc B qui doit le deviner, et réciproquement.
          select id into v_repondant from joueurs
          where binome_id = v_bid and role = case v_slot when 'a' then 'B' else 'A' end;

          -- questionneur : le présentateur s'il y en a un, sinon un
          -- joueur d'un AUTRE binôme, par rotation.
          v_questionneur := coalesce(p.presentateur_id, (
            select id from joueurs
            where binome_id = v_binomes[1 + (bi % v_nb)]
            order by case when (k + bi) % 2 = 0 then role end nulls last, role
            limit 1));

          v_ordre := v_ordre + 1;
          insert into tours (partie_id, ordre, manche, binome_id, question_id,
                             repondant_id, questionneur_id)
          values (p_partie, v_ordre, v_manche, v_bid, v_paire || '.' || v_slot,
                  v_repondant, v_questionneur);
        end loop;
      end loop;
    end loop;
  end loop;

  -- La question bonus : un tour par binôme, les deux membres répondent,
  -- donc pas de répondant désigné.
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

-- =============================================================
-- Préparation
-- =============================================================

-- Combien de questions chaque joueur doit remplir.
create or replace function nb_questions_prepa(p_partie uuid)
returns int language sql security definer stable
set search_path = public, pg_temp as $$
  select case format when 'court' then 2 else 3 end       -- ouvertes
       + case format when 'court' then 1 else 2 end       -- qcm
       + 1                                                -- bonus
       + (reglages->>'questionsFinale')::int              -- série de finale
  from parties where id = p_partie;
$$;

-- La liste exacte des questions du joueur, dans l'ordre de saisie.
-- Le client récupère les textes dans questions.json avec ces ids.
create or replace function rpc_mes_questions()
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  j joueurs; p parties; b binomes; v_slot text; ids text[] := '{}';
  v_serie text; i int;
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

  v_serie := p.tirage->b.mode->>'finale';
  for i in 1..(p.reglages->>'questionsFinale')::int loop
    ids := ids || array[v_serie || '.' || i];
  end loop;

  return jsonb_build_object('role', j.role, 'mode', b.mode,
                            'questions', to_jsonb(ids),
                            'total', array_length(ids,1));
end $$;

-- Relire ses propres réponses : le seul chemin de lecture de
-- reponses_prepa, et il ne rend que les siennes.
create or replace function rpc_mes_reponses()
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare res jsonb;
begin
  if auth.uid() is null then raise exception 'session requise'; end if;
  select coalesce(jsonb_object_agg(question_id,
           jsonb_build_object('valeur', valeur, 'passee', passee)), '{}'::jsonb)
  into res from reponses_prepa where joueur_id = auth.uid();
  return res;
end $$;

-- Écrire une réponse. Enregistrée question par question : fermer la
-- page au milieu de la prépa ne perd rien (§10.d).
create or replace function rpc_repondre_prepa(p_question text, p_valeur text,
                                              p_passee boolean default false)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  j joueurs; p parties; attendues jsonb; faites int;
begin
  select * into j from joueurs where id = auth.uid();
  if j.id is null then raise exception 'rejoins la partie d''abord'; end if;
  select * into p from parties where id = j.partie_id;
  if p.etat <> 'prep' then raise exception 'ce n''est plus la phase de préparation'; end if;

  attendues := (rpc_mes_questions())->'questions';
  if not (attendues ? p_question) then
    raise exception 'cette question n''est pas dans ton set';
  end if;
  if not coalesce(p_passee,false) and length(btrim(coalesce(p_valeur,''))) = 0 then
    raise exception 'réponse vide : utilise « passer »';
  end if;

  insert into reponses_prepa (joueur_id, question_id, valeur, passee)
  values (j.id, p_question, btrim(coalesce(p_valeur,'')), coalesce(p_passee,false))
  on conflict (joueur_id, question_id)
    do update set valeur = excluded.valeur, passee = excluded.passee, ecrit_le = now();

  select count(*) into faites from reponses_prepa where joueur_id = j.id;
  return jsonb_build_object('faites', faites, 'total', nb_questions_prepa(p.id),
                            'termine', faites >= nb_questions_prepa(p.id));
end $$;

-- Progression de la prépa pour l'écran TV : des nombres, aucun contenu.
create view v_progression as
  select j.partie_id,
         count(*) filter (where r.n >= nb_questions_prepa(j.partie_id)) as termines,
         count(*) as total
  from joueurs j
  left join (select joueur_id, count(*) n from reponses_prepa group by joueur_id) r
         on r.joueur_id = j.id
  where j.binome_id is not null and est_membre(j.partie_id)
  group by j.partie_id;

grant select on v_progression to anon, authenticated;

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
