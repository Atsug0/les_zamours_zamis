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

\echo '--- droits sur les tables et les vues ---'
-- Le trou historique : Supabase accorde ALL par defaut, et les VUES
-- echappaient aux revoke nommes. Une vue tourne avec les droits de son
-- proprietaire : y ecrire contourne les RLS.
select assert_vrai((
  select count(*) = 0 from information_schema.role_table_grants
  where grantee in ('anon','authenticated') and table_schema = 'public'
    and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES')
), 'aucune relation du schema public n est modifiable depuis le navigateur');

select assert_vrai((
  select array_agg(distinct table_name::text order by table_name::text) = array[
    'binomes','joueurs','parties','v_joueurs','v_palmares',
    'v_passages_finale','v_progression','v_recap','v_tours']
  from information_schema.role_table_grants
  where grantee = 'authenticated' and table_schema = 'public' and privilege_type = 'SELECT'
), 'exactement 3 tables et 6 vues sont lisibles, pas une de plus');

-- l exploit concret, teste a travers la vue
set role authenticated;
select assert_erreur('update v_recap set points = 9999 where ordre = -1',
                     'falsifier les scores a travers v_recap');
select assert_erreur('update v_joueurs set binome_id = gen_random_uuid() where prenom = ''__x__''',
                     'changer de binome a travers v_joueurs');
select assert_erreur('update v_tours set verdict = true where ordre = -1',
                     'se valider soi-meme a travers v_tours');
select assert_erreur('select count(*) from questions_index',
                     'lire l index des questions (le client a deja les textes)');
reset role;

\echo '=== DROITS : OK ==='
