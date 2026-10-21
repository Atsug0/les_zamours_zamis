\set ON_ERROR_STOP on
\echo '=== DROITS SUR LES FONCTIONS ==='
reset role;

-- PostgREST publie toute fonction executable par anon/authenticated.
-- Ce test est la pour qu un helper ajoute plus tard ne devienne pas
-- un endpoint REST par accident.
select assert_vrai((
  select count(*) = 0 from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
    and p.proname not like 'rpc\_%'
    -- les seules exceptions, justifiees une par une dans 0009_droits.sql
    and p.proname not in ('ping','est_membre','nb_questions_prepa')
    and p.proname not in ('assert_vrai','assert_erreur','remise_a_zero','devenir')
    and (has_function_privilege('anon', p.oid, 'execute')
      or has_function_privilege('authenticated', p.oid, 'execute'))
), 'aucun helper interne n est joignable depuis l API');

select assert_vrai((
  select count(*) > 15 from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname like 'rpc\_%'
    and has_function_privilege('authenticated', p.oid, 'execute')
), 'les fonctions rpc_ restent joignables par un joueur connecte');

select assert_vrai((
  select count(*) = 0 from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname like 'rpc\_%'
    and has_function_privilege('anon', p.oid, 'execute')
), 'aucune fonction de jeu n est joignable sans session');

select assert_vrai(has_function_privilege('anon', 'ping()', 'execute'),
                   'ping reste ouvert pour le cron anti-pause');

-- l exploit concret que ce verrou ferme
set role authenticated;
select assert_erreur('select juger_tour(gen_random_uuid(), true)',
                     'juger_tour : attribuer des points sans validation');
select assert_erreur('select fabriquer_tours(gen_random_uuid())',
                     'fabriquer_tours : regenerer les tours d une partie');
select assert_erreur('select tirer_pin()', 'tirer_pin : fabriquer un code de reprise');
-- est_membre reste joignable : les politiques RLS en ont besoin. Elle ne
-- repond que sur soi-meme, donc elle ne divulgue rien.
-- est_membre et nb_questions_prepa restent joignables : les politiques RLS
-- et la vue v_progression en ont besoin. Elles ne divulguent rien.
select assert_vrai(est_membre(gen_random_uuid()) is false,
                   'est_membre reste appelable mais ne repond que sur soi-meme');
select assert_vrai(nb_questions_prepa(gen_random_uuid()) is null,
                   'nb_questions_prepa reste appelable et ne rend qu un compte');
reset role;
\echo '=== DROITS : OK ==='
