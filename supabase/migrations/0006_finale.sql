-- =============================================================
-- 0006 — La finale et le palmarès
--
-- Barème (règles §8.2) : 12 points par bonne réponse, prime de 40
-- au seuil. La finale pèse donc autant que toutes les manches
-- réunies — un binôme largué peut revenir.
--
-- C'est le seul endroit où quelqu'un voit la réponse attendue avant
-- la salle : le questionneur, et seulement une fois le chrono lancé.
-- =============================================================

create or replace function preparer_finale(p_partie uuid)
returns int language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  p parties; b record; v_ordre int := 0; v_binomes uuid[]; v_nb int; v_q uuid;
begin
  select * into p from parties where id = p_partie;
  delete from passages_finale where partie_id = p_partie;

  -- Ordre de passage : du DERNIER au PREMIER au classement. Le leader
  -- finit sous pression (règles §8).
  select array_agg(id order by score asc, couleur) into v_binomes
  from binomes where partie_id = p_partie;
  v_nb := array_length(v_binomes, 1);

  for b in select bi.*, row_number() over (order by bi.score asc, bi.couleur) as rang
           from binomes bi where bi.partie_id = p_partie
           order by bi.score asc, bi.couleur loop
    v_ordre := v_ordre + 1;
    -- questionneur : le présentateur, sinon un joueur d'un AUTRE binôme
    v_q := coalesce(p.presentateur_id, (
      select id from joueurs
      where binome_id = v_binomes[1 + (v_ordre % v_nb)]
      order by role limit 1));
    insert into passages_finale (partie_id, binome_id, ordre, questionneur_id, serie_id)
    values (p_partie, b.id, v_ordre, v_q, p.tirage -> b.mode ->> 'finale');
  end loop;
  return v_ordre;
end $$;

-- Le binôme désigne lequel des deux joue.
create or replace function rpc_designer_finaliste(p_passage uuid, p_joueur uuid)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare f passages_finale; j joueurs;
begin
  select * into f from passages_finale where id = p_passage;
  if f.id is null then raise exception 'passage introuvable'; end if;
  if f.chrono_fin_at is not null or f.seuil_atteint is not null then
    raise exception 'ce passage a déjà commencé';
  end if;
  select * into j from joueurs where id = p_joueur;
  if j.binome_id is distinct from f.binome_id then
    raise exception 'ce joueur n''est pas de ce binôme';
  end if;
  if (select binome_id from joueurs where id = auth.uid()) is distinct from f.binome_id
     and not peut_orchestrer(f.partie_id) then
    raise exception 'c''est au binôme de désigner qui joue';
  end if;
  update passages_finale set joueur_id = p_joueur where id = p_passage;
  return jsonb_build_object('joueur_id', p_joueur);
end $$;

-- Démarrer le passage : lance le chrono et donne les réponses
-- attendues AU SEUL QUESTIONNEUR.
create or replace function rpc_demarrer_passage(p_passage uuid)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  f passages_finale; p parties; v_n int; v_fin timestamptz; v_rep jsonb;
begin
  select * into f from passages_finale where id = p_passage;
  if f.id is null then raise exception 'passage introuvable'; end if;
  select * into p from parties where id = f.partie_id;
  if p.en_pause then raise exception 'la partie est en pause'; end if;
  if auth.uid() <> f.questionneur_id then
    raise exception 'seul le questionneur mène le passage';
  end if;
  if f.joueur_id is null then raise exception 'le binôme doit désigner qui joue'; end if;
  if f.chrono_fin_at is not null or f.chrono_restant_ms is not null then
    raise exception 'passage déjà lancé';
  end if;
  if f.seuil_atteint is not null then raise exception 'passage déjà terminé'; end if;

  v_n := (p.reglages->>'questionsFinale')::int;
  v_fin := now() + ((p.reglages->>'chronoFinaleMs')::int || ' milliseconds')::interval;

  -- les réponses du PARTENAIRE du finaliste : c'est lui qu'on doit deviner
  select jsonb_agg(jsonb_build_object('question_id', q, 'attendue', r.valeur, 'passee', r.passee)
                   order by ord)
  into v_rep
  from generate_series(1, v_n) ord
  cross join lateral (select f.serie_id || '.' || ord as q) qq
  left join reponses_prepa r
         on r.question_id = qq.q
        and r.joueur_id = (select id from joueurs
                           where binome_id = f.binome_id and id <> f.joueur_id);

  update passages_finale
  set chrono_fin_at = v_fin,
      jugements = array_fill('attente'::text, array[v_n])
  where id = p_passage;

  return jsonb_build_object('chrono_fin_at', v_fin, 'questions', v_rep,
                            'serie_id', f.serie_id);
end $$;

-- Trancher une question au vol : juste, faux, ou passer.
create or replace function rpc_juger(p_passage uuid, p_index int, p_jugement text)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare f passages_finale; p parties; v_js text[];
begin
  select * into f from passages_finale where id = p_passage;
  if f.id is null then raise exception 'passage introuvable'; end if;
  select * into p from parties where id = f.partie_id;
  if p.en_pause then raise exception 'la partie est en pause'; end if;
  if auth.uid() <> f.questionneur_id then raise exception 'seul le questionneur tranche'; end if;
  if p_jugement not in ('juste','faux','passee') then raise exception 'jugement inconnu'; end if;
  if f.chrono_fin_at is null then raise exception 'le passage n''est pas lancé'; end if;
  if now() >= f.chrono_fin_at then raise exception 'le chrono est écoulé'; end if;
  if p_index < 1 or p_index > array_length(f.jugements,1) then
    raise exception 'index hors de la série';
  end if;

  v_js := f.jugements;
  v_js[p_index] := p_jugement;
  update passages_finale set jugements = v_js where id = p_passage;

  return jsonb_build_object('jugements', to_jsonb(v_js),
    'restantes', (select count(*) from unnest(v_js) x where x in ('attente','passee')),
    'justes', (select count(*) from unnest(v_js) x where x = 'juste'));
end $$;

-- Clore le passage : compte les points, applique la prime au seuil.
create or replace function rpc_clore_passage(p_passage uuid)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  f passages_finale; p parties; v_justes int; v_seuil int;
  v_prime int := 40; v_pts int; v_atteint boolean; v_reste int;
begin
  select * into f from passages_finale where id = p_passage;
  if f.id is null then raise exception 'passage introuvable'; end if;
  if f.seuil_atteint is not null then
    return jsonb_build_object('deja', true, 'points', f.points,
                              'seuil_atteint', f.seuil_atteint);
  end if;
  select * into p from parties where id = f.partie_id;
  if not peut_orchestrer(f.partie_id) and auth.uid() <> f.questionneur_id then
    raise exception 'non autorisé';
  end if;
  if f.chrono_fin_at is null then raise exception 'le passage n''a pas été lancé'; end if;

  select count(*) into v_reste from unnest(f.jugements) x where x in ('attente','passee');
  if now() < f.chrono_fin_at and v_reste > 0 then
    raise exception 'le chrono court encore et % question(s) ne sont pas tranchées', v_reste;
  end if;

  select count(*) into v_justes from unnest(f.jugements) x where x = 'juste';
  v_seuil   := (p.reglages->>'seuilFinale')::int;
  v_atteint := v_justes >= v_seuil;
  v_pts     := v_justes * 12 + case when v_atteint then v_prime else 0 end;

  update passages_finale set points = v_pts, seuil_atteint = v_atteint,
                             chrono_fin_at = null, chrono_restant_ms = null
  where id = p_passage;
  update binomes set score = score + v_pts where id = f.binome_id;

  return jsonb_build_object('justes', v_justes, 'seuil', v_seuil,
                            'seuil_atteint', v_atteint, 'prime', case when v_atteint then v_prime else 0 end,
                            'points', v_pts);
end $$;

-- =============================================================
-- Palmarès
-- =============================================================
create view v_palmares as
  select b.partie_id, b.id as binome_id, b.couleur, b.mode, b.score,
         rank() over (partition by b.partie_id order by b.score desc) as rang,
         (select array_agg(j.prenom order by j.role) from joueurs j where j.binome_id = b.id) as prenoms,
         (select f.points from passages_finale f where f.binome_id = b.id) as points_finale,
         (select f.seuil_atteint from passages_finale f where f.binome_id = b.id) as seuil_atteint
  from binomes b
  where est_membre(b.partie_id);

-- Le récap de fin de soirée : c'est à ça que servent les 2-3 mots
-- consignés par le questionneur (règles §9).
create view v_recap as
  select t.partie_id, t.ordre, t.manche, t.binome_id, t.question_id,
         t.reponse_donnee, t.reponse_revelee, t.verdict, t.points,
         (select prenom from joueurs j where j.id = t.repondant_id) as repondant
  from tours t
  where t.statut = 'juge' and est_membre(t.partie_id)
  order by t.ordre;

grant select on v_palmares, v_recap to anon, authenticated;

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
