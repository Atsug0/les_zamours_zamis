-- =============================================================
-- 0017 — Faire remonter l'état du mode sujet
--
-- Même piège que pour la préparation (0012) : `reponses_manche`
-- n'est pas diffusée, et ne doit pas l'être — les réponses des
-- challengers sont secrètes jusqu'à la révélation.
--
-- Mais le plateau doit afficher « 3 réponses sur 5 », et les écrans
-- doivent se rafraîchir quand le sujet corrige un jugement. Deux
-- compteurs sur `tours`, table déjà diffusée :
--   reponses_recues : combien ont répondu — un nombre, aucun contenu ;
--   revision        : incrémentée à chaque jugement, pour que les
--                     clients sachent qu'il faut relire les réponses.
-- =============================================================

alter table tours
  add column reponses_recues int not null default 0,
  add column revision int not null default 0;

create or replace function rpc_defier(p_tour uuid, p_valeur text)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare t tours; p parties; v_total int; v_faits int; v_motif text;
begin
  select * into t from tours where id = p_tour;
  if t.id is null then raise exception 'tour introuvable'; end if;
  select * into p from parties where id = t.partie_id;
  if p.en_pause then raise exception 'la partie est en pause'; end if;
  if auth.uid() = p.sujet_id then raise exception 'le sujet ne se devine pas lui-même'; end if;
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
  where partie_id = t.partie_id and id <> p.sujet_id;
  select count(*) into v_faits from reponses_manche where tour_id = p_tour;

  -- le compteur passe par tours, donc il est diffusé
  update tours set reponses_recues = v_faits where id = p_tour;

  return jsonb_build_object('faits', v_faits, 'total', v_total,
                            'tous_ont_repondu', v_faits >= v_total);
end $$;

create or replace function rpc_juger_defi(p_tour uuid, p_joueur uuid, p_juste boolean)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare t tours; p parties;
begin
  select * into t from tours where id = p_tour;
  select * into p from parties where id = t.partie_id;
  if auth.uid() <> p.sujet_id then raise exception 'seul le sujet juge'; end if;
  if t.statut <> 'revele' then raise exception 'ce tour n''est pas en jugement'; end if;
  update reponses_manche set juste = p_juste where tour_id = p_tour and joueur_id = p_joueur;
  -- rien ne serait diffusé sans ça : reponses_manche est muette par
  -- conception, donc on signale le changement sur tours.
  update tours set revision = revision + 1 where id = p_tour;
  return jsonb_build_object('joueur_id', p_joueur, 'juste', p_juste);
end $$;

-- v_tours expose les deux compteurs
drop view if exists v_tours;
create view v_tours as
  select t.id, t.partie_id, t.ordre, t.manche, t.binome_id,
         t.question_id, t.repondant_id, t.questionneur_id,
         t.statut, t.vote_fin_at, t.verdict, t.points,
         t.reponse_donnee,
         t.reponses_recues, t.revision,
         case when t.statut in ('revele','vote','juge')
              then t.reponse_revelee end as reponse_revelee,
         case when t.statut = 'juge'
              then (select count(*) from votes v where v.tour_id = t.id and v.pour) end as voix_pour,
         case when t.statut = 'juge'
              then (select count(*) from votes v where v.tour_id = t.id and not v.pour) end as voix_contre,
         exists (select 1 from votes v where v.tour_id = t.id and v.joueur_id = auth.uid()) as j_ai_vote,
         exists (select 1 from reponses_manche r
                 where r.tour_id = t.id and r.joueur_id = auth.uid()) as j_ai_repondu
  from tours t
  where est_membre(t.partie_id);

grant select on v_tours to anon, authenticated;

do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p
           join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('rpc_defier','rpc_juger_defi')
  loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
