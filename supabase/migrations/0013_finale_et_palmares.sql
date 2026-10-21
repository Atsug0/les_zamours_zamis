-- =============================================================
-- 0013 — Deux manques de la finale et du palmarès
--
-- 1. rpc_demarrer_passage refusait un second appel. Or le
--    questionneur est le SEUL à détenir les réponses attendues, et
--    elles ne vivent que dans la mémoire de son navigateur : un
--    téléphone qui se verrouille ou se recharge tuait le passage.
--    La fonction devient idempotente — elle rend les mêmes réponses
--    sans toucher au chrono.
--
-- 2. La mort subite en cas d'égalité au sommet (règles §8.4) était
--    promise et n'existait pas. Elle se joue à l'oral, comme le
--    reste du jeu : le présentateur pose une question commune, et
--    déclare le binôme qui a concordé le premier.
-- =============================================================

create or replace function rpc_demarrer_passage(p_passage uuid)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  f passages_finale; p parties; v_n int; v_fin timestamptz; v_rep jsonb;
begin
  select * into f from passages_finale where id = p_passage;
  if f.id is null then raise exception 'passage introuvable'; end if;
  select * into p from parties where id = f.partie_id;
  if auth.uid() <> f.questionneur_id then
    raise exception 'seul le questionneur mène le passage';
  end if;
  if f.joueur_id is null then raise exception 'le binôme doit désigner qui joue'; end if;
  if f.seuil_atteint is not null then raise exception 'passage déjà terminé'; end if;

  v_n := (p.reglages->>'questionsFinale')::int;

  -- les réponses du PARTENAIRE du finaliste : c'est lui qu'on devine
  select jsonb_agg(jsonb_build_object('question_id', qq.q, 'attendue', r.valeur,
                                      'passee', r.passee) order by ord)
  into v_rep
  from generate_series(1, v_n) ord
  cross join lateral (select f.serie_id || '.' || ord as q) qq
  left join reponses_prepa r
         on r.question_id = qq.q
        and r.joueur_id = (select id from joueurs
                           where binome_id = f.binome_id and id <> f.joueur_id);

  -- Déjà lancé : on rend les mêmes réponses, sans relancer le chrono.
  -- C'est le chemin d'un téléphone qui se recharge en pleine finale.
  if f.chrono_fin_at is not null or f.chrono_restant_ms is not null then
    return jsonb_build_object('chrono_fin_at', f.chrono_fin_at,
                              'chrono_restant_ms', f.chrono_restant_ms,
                              'questions', v_rep, 'serie_id', f.serie_id,
                              'jugements', to_jsonb(f.jugements), 'reprise', true);
  end if;

  if p.en_pause then raise exception 'la partie est en pause'; end if;
  v_fin := now() + ((p.reglages->>'chronoFinaleMs')::int || ' milliseconds')::interval;
  update passages_finale
  set chrono_fin_at = v_fin, jugements = array_fill('attente'::text, array[v_n])
  where id = p_passage;

  return jsonb_build_object('chrono_fin_at', v_fin, 'questions', v_rep,
                            'serie_id', f.serie_id, 'reprise', false);
end $$;

-- -------------------------------------------------------------
-- Mort subite : départage à égalité au sommet (règles §8.4).
-- Le jeu étant oral, le départage l'est aussi — le présentateur pose
-- une question commune et déclare qui a concordé le premier. La base
-- vérifie seulement qu'il y a bien égalité, et sur qui.
-- -------------------------------------------------------------
create or replace function rpc_mort_subite(p_binome uuid)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  v_partie uuid; v_max int; v_exaequo int;
begin
  select partie_id into v_partie from binomes where id = p_binome;
  if v_partie is null then raise exception 'binôme introuvable'; end if;
  if not peut_orchestrer(v_partie) then
    raise exception 'seuls l''hôte et le présentateur départagent';
  end if;
  if (select etat from parties where id = v_partie) <> 'palmares' then
    raise exception 'la mort subite ne se joue qu''au palmarès';
  end if;

  select max(score) into v_max from binomes where partie_id = v_partie;
  select count(*) into v_exaequo from binomes where partie_id = v_partie and score = v_max;
  if v_exaequo < 2 then raise exception 'il n''y a pas d''égalité à départager'; end if;
  if (select score from binomes where id = p_binome) <> v_max then
    raise exception 'ce binôme n''est pas à égalité au sommet';
  end if;

  -- un point suffit : il ne compte pas, il tranche
  update binomes set score = score + 1 where id = p_binome;
  return jsonb_build_object('vainqueur', p_binome, 'score', v_max + 1);
end $$;

do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p
           join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public'
             and p.proname in ('rpc_demarrer_passage','rpc_mort_subite')
  loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
