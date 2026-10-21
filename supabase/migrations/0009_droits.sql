-- =============================================================
-- 0009 — Droits sur les fonctions : la source unique de vérité
--
-- PostgREST expose COMME ENDPOINT REST toute fonction du schéma
-- public exécutable par anon ou authenticated. Les migrations
-- précédentes ne révoquaient que les fonctions rpc_*, laissant les
-- helpers internes ouverts — dont juger_tour(tour, verdict), qui
-- écrit des points sans aucune validation.
--
-- Règle désormais appliquée globalement :
--   * rpc_*  -> authenticated seulement (chaque fonction vérifie
--              elle-même l'appelant, la phase et les délais) ;
--   * ping() -> anon, pour le cron anti-pause ;
--   * une LISTE BLANCHE étroite -> authenticated, par nécessité
--     technique (voir le tableau `requis` plus bas) ;
--   * tout le reste -> PERSONNE. Les helpers sont appelés depuis
--     l'intérieur de fonctions SECURITY DEFINER, qui tournent avec
--     les droits de leur propriétaire : ils n'ont besoin d'aucun
--     droit public.
--
-- Les fonctions fournies par une extension (pgcrypto…) sont laissées
-- telles quelles : elles ne nous appartiennent pas.
-- =============================================================

-- Deux fonctions doivent rester joignables, et c'est subtil :
--
--   est_membre        appelée dans les politiques RLS. Une politique
--                     s'évalue avec les droits du rôle APPELANT : la
--                     révoquer casse toute lecture.
--   nb_questions_prepa appelée dans la vue v_progression. Dans une vue
--                     non-security_invoker, Postgres vérifie l'accès aux
--                     TABLES avec les droits du propriétaire, mais
--                     l'exécution des FONCTIONS avec ceux de l'appelant.
--
-- Les deux sont inoffensives : la première ne répond que sur auth.uid(),
-- la seconde rend un simple compte de questions. Toute fonction ajoutée
-- à une politique ou à une vue devra rejoindre cette liste — et
-- 05_droits.sql échouera si on l'oublie, ou si on y met autre chose.
do $$
declare
  f record;
  requis text[] := array['est_membre', 'nb_questions_prepa'];
begin
  for f in
    select p.oid::regprocedure as sig, p.proname
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      -- ne pas toucher à ce qui vient d'une extension
      and not exists (
        select 1 from pg_depend d
        where d.objid = p.oid and d.deptype = 'e'
      )
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);

    if f.proname like 'rpc\_%' or f.proname = any(requis) then
      execute format('grant execute on function %s to authenticated', f.sig);
    elsif f.proname = 'ping' then
      execute format('grant execute on function %s to anon, authenticated', f.sig);
    end if;
  end loop;
end $$;

-- Interdit à PostgREST de deviner un endpoint dans un autre schéma.
revoke all on schema public from anon, authenticated;
grant usage on schema public to anon, authenticated;
