\set ON_ERROR_STOP on
\echo '=== LOBBY ==='
reset role;
select remise_a_zero();

\set tv '''11111111-1111-1111-1111-111111111111'''
\set p1 '''aaaaaaaa-0000-0000-0000-000000000001'''
\set p2 '''aaaaaaaa-0000-0000-0000-000000000002'''
\set p3 '''aaaaaaaa-0000-0000-0000-000000000003'''
\set p4 '''aaaaaaaa-0000-0000-0000-000000000004'''
\set p5 '''aaaaaaaa-0000-0000-0000-000000000005'''
\set intrus '''bbbbbbbb-0000-0000-0000-000000000009'''

-- la télé crée la partie
select devenir(:tv::uuid); set role authenticated;
select set_config('zz.code', (rpc_creer_partie()->>'code'), false);
select assert_vrai(length(current_setting('zz.code')) = 4, 'la télé obtient un code à 4 lettres');
select assert_vrai(current_setting('zz.code') !~ '[IO01]', 'le code évite I, O, 0 et 1');

-- cinq joueurs rejoignent
reset role; select devenir(:p1::uuid); set role authenticated;
do $$ begin perform rpc_rejoindre(current_setting('zz.code'), 'Sam'); end $$;
reset role; select devenir(:p2::uuid); set role authenticated;
do $$ begin perform rpc_rejoindre(current_setting('zz.code'), 'Alex'); end $$;
reset role; select devenir(:p3::uuid); set role authenticated;
do $$ begin perform rpc_rejoindre(current_setting('zz.code'), 'Camille'); end $$;
reset role; select devenir(:p4::uuid); set role authenticated;
do $$ begin perform rpc_rejoindre(current_setting('zz.code'), 'Noe'); end $$;
reset role; select devenir(:p5::uuid); set role authenticated;
do $$ begin perform rpc_rejoindre(current_setting('zz.code'), 'Lou'); end $$;

reset role;
select assert_vrai((select count(*) from joueurs) = 5, 'cinq joueurs dans la partie');
select assert_vrai((select hote_id from parties) = :p1::uuid, 'le premier arrive devient hote');

-- prenom deja pris : depuis une session qui n a pas encore de siege
reset role; select devenir('cccccccc-0000-0000-0000-00000000000f'::uuid); set role authenticated;
select assert_erreur(format('select rpc_rejoindre(%L, %L)', current_setting('zz.code'), 'sam'),
                     'prenom deja pris, a la casse pres');
select assert_erreur('select rpc_rejoindre(''ZZZZ'', ''Bob'')', 'code inexistant');

-- une session qui a deja un siege le retrouve : c est le chemin de reconnexion
reset role; select devenir(:p1::uuid); set role authenticated;
select assert_vrai((rpc_rejoindre(current_setting('zz.code'), 'Sam')->>'reprise')::boolean,
                   'rappeler rpc_rejoindre rend le meme siege');

-- appariements
reset role; select devenir(:p1::uuid); set role authenticated;
select rpc_apparier(:p2::uuid) \g /dev/null
reset role; select devenir(:p3::uuid); set role authenticated;
select rpc_apparier(:p4::uuid) \g /dev/null
reset role;
select assert_vrai((select count(*) from binomes) = 2, 'deux binomes formes');
select assert_vrai((select array_agg(couleur order by couleur) from binomes) = array['jaune','rouge'],
                   'couleurs dans l ordre du plateau : rouge puis jaune');
select assert_vrai((select count(distinct role) from joueurs where binome_id is not null) = 2,
                   'les roles A et B sont distribues');

-- on ne vole pas un joueur deja apparie
set role authenticated;
select assert_erreur(format('select rpc_apparier(%L)', :p2), 'apparier un joueur deja en binome');

-- le cinquieme presente
reset role; select devenir(:p5::uuid); set role authenticated;
do $$ begin perform rpc_devenir_presentateur(); end $$;
reset role;
select assert_vrai((select presentateur_id from parties) = :p5::uuid, 'le joueur en trop devient presentateur');

-- choix des modes
reset role; select devenir(:p1::uuid); set role authenticated;
select assert_vrai((rpc_choisir_mode('zamours')->>'accord')::boolean is false,
                   'un seul choix ne verrouille pas le binome');
reset role; select devenir(:p2::uuid); set role authenticated;
select assert_vrai((rpc_choisir_mode('zamours')->>'accord')::boolean,
                   'les deux d accord : binome verrouille');

reset role; select devenir(:p3::uuid); set role authenticated;
do $$ begin perform rpc_choisir_mode('zamis'); end $$;
reset role; select devenir(:p4::uuid); set role authenticated;
select assert_vrai((rpc_choisir_mode('zamours')->>'accord')::boolean is false,
                   'modes divergents : pas d accord');
do $$ begin perform rpc_choisir_mode('zamis'); end $$;
reset role;
select assert_vrai((select count(*) from binomes where verrouille) = 2, 'les deux binomes verrouilles');
select assert_vrai((select count(*) from binomes where mode = 'zamis') = 1, 'un binome Zamis, un Zamours');

\echo '--- RLS ---'
select devenir(:p1::uuid); set role authenticated;
select assert_vrai((select count(*) from joueurs) = 1, 'un joueur ne lit que sa propre ligne joueurs (pin inclus)');
select assert_vrai((select count(*) from v_joueurs) = 5, 'la vue publique montre les 5 joueurs');
select assert_erreur('select count(*) from reponses_prepa', 'reponses_prepa : aucun droit de lecture');
select assert_erreur('select count(*) from votes', 'votes : aucun droit de lecture');
select assert_vrai((select count(*) from parties) = 1, 'un membre lit sa partie');
select assert_erreur('insert into binomes (partie_id, couleur) select id, ''vert'' from parties',
                     'ecriture directe dans binomes');
select assert_erreur('update binomes set score = 999', 'tricher sur le score en direct');

reset role; select devenir(:intrus::uuid); set role authenticated;
select assert_vrai((select count(*) from parties) = 0, 'un non-membre ne voit aucune partie');
select assert_vrai((select count(*) from v_joueurs) = 0, 'un non-membre ne voit aucun joueur');

reset role;
\echo '=== LOBBY : OK ==='
