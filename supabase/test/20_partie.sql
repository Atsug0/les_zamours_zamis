\set ON_ERROR_STOP on
\echo '=== TIRAGE ET PREPARATION ==='
reset role;
select remise_a_zero();

\set tv '''11111111-1111-1111-1111-111111111111'''
\set p1 '''aaaaaaaa-0000-0000-0000-000000000001'''
\set p2 '''aaaaaaaa-0000-0000-0000-000000000002'''
\set p3 '''aaaaaaaa-0000-0000-0000-000000000003'''
\set p4 '''aaaaaaaa-0000-0000-0000-000000000004'''

-- quatre joueurs, deux binomes, pas de presentateur, les deux en Zamours
select devenir(:tv::uuid); set role authenticated;
select set_config('zz.code', (rpc_creer_partie()->>'code'), false);
reset role; select devenir(:p1::uuid); set role authenticated;
do $$ begin perform rpc_rejoindre(current_setting('zz.code'), 'Sam'); end $$;
reset role; select devenir(:p2::uuid); set role authenticated;
do $$ begin perform rpc_rejoindre(current_setting('zz.code'), 'Alex'); end $$;
reset role; select devenir(:p3::uuid); set role authenticated;
do $$ begin perform rpc_rejoindre(current_setting('zz.code'), 'Camille'); end $$;
reset role; select devenir(:p4::uuid); set role authenticated;
do $$ begin perform rpc_rejoindre(current_setting('zz.code'), 'Lou'); end $$;
reset role; select devenir(:p1::uuid); set role authenticated;
select rpc_apparier(:p2::uuid) \g /dev/null
reset role; select devenir(:p3::uuid); set role authenticated;
select rpc_apparier(:p4::uuid) \g /dev/null
reset role; select devenir(:p1::uuid); set role authenticated;
do $$ begin perform rpc_choisir_mode('zamours'); end $$;
reset role; select devenir(:p2::uuid); set role authenticated;
do $$ begin perform rpc_choisir_mode('zamours'); end $$;
reset role; select devenir(:p3::uuid); set role authenticated;
do $$ begin perform rpc_choisir_mode('zamours'); end $$;
reset role; select devenir(:p4::uuid); set role authenticated;
do $$ begin perform rpc_choisir_mode('zamours'); end $$;

-- un joueur lambda ne lance pas la partie
select assert_erreur('select rpc_lancer(''court'')', 'un joueur sans role ne lance pas la partie');

reset role; select devenir(:tv::uuid); set role authenticated;
do $$ begin perform rpc_lancer('court'); end $$;
reset role;
select assert_vrai((select etat from parties) = 'prep', 'la partie passe en preparation');
select assert_erreur('select rpc_lancer(''court'')', 'relancer une partie deja lancee');

\echo '--- le tirage ---'
select assert_vrai(jsonb_array_length((select tirage->'zamours'->'ouvertes' from parties)) = 2,
                   'format court : 2 paires ouvertes');
select assert_vrai(jsonb_array_length((select tirage->'zamours'->'qcm' from parties)) = 1,
                   'format court : 1 paire QCM');
select assert_vrai((select tirage->'zamours'->>'bonus' from parties) is not null, 'un bonus tire');
select assert_vrai((select tirage->'zamours'->>'finale' from parties) is not null, 'une serie de finale tiree');
select assert_vrai((select count(*) from parties where tirage ? 'zamis') = 0,
                   'aucun tirage Zamis : aucun binome ne joue ce mode');

-- themes distincts dans le tirage (regles 3.1)
select assert_vrai((
  select count(distinct qi.theme) = count(*)
  from parties p, jsonb_array_elements_text(p.tirage->'zamours'->'ouvertes') x
  join questions_index qi on qi.paire = x.value and qi.slot = 'a'
), 'aucun theme repete dans les paires ouvertes');

-- les categories sensibles ne sont pas tirees sans consentement
select assert_vrai((
  select not bool_or(qi.sensible)
  from parties p, jsonb_array_elements_text(p.tirage->'zamours'->'ouvertes') x
  join questions_index qi on qi.paire = x.value
), 'aucune question sensible sans activation');

\echo '--- les tours ---'
-- court, 2 binomes : (1 paire QCM + 2 paires libres) x 2 slots x 2 binomes + 1 bonus x 2
-- court, 2 binomes : 4 QCM + 8 libres + 6 duos
select assert_vrai((select count(*) from tours) = 18, '18 tours fabriques');
select assert_vrai((select count(*) from tours where manche = 'qcm')   = 4, '4 tours QCM');
select assert_vrai((select count(*) from tours where manche = 'libre') = 8, '8 tours libres');
select assert_vrai((select count(*) from tours where manche = 'bonus') = 6,
                   '3 duos par binome : le format le plus drole merite une manche');
select assert_vrai((select count(distinct ordre) from tours) = 18, 'les ordres sont uniques');
select assert_vrai((select min(ordre) from tours where manche = 'libre')
                 > (select max(ordre) from tours where manche = 'qcm'),
                   'la manche QCM passe avant la manche libre');
select assert_vrai((select min(ordre) from tours where manche = 'bonus')
                 > (select max(ordre) from tours where manche = 'libre'),
                   'le bonus passe en dernier');

-- alternance : deux tours consecutifs d une meme manche ne sont jamais au meme binome
select assert_vrai((
  select count(*) = 0 from (
    select binome_id, manche, lag(binome_id) over (partition by manche order by ordre) prec
    from tours where manche in ('qcm','libre')
  ) t where binome_id = prec
), 'les binomes alternent a chaque question');

-- le questionneur n est jamais du binome interroge
select assert_vrai((
  select count(*) = 0 from tours t join joueurs j on j.id = t.questionneur_id
  where j.binome_id = t.binome_id
), 'le questionneur n est jamais du binome interroge');

-- c est bien le partenaire qui devine
select assert_vrai((
  select count(*) = 0 from tours t join joueurs j on j.id = t.repondant_id
  where t.manche <> 'bonus'
    and (j.binome_id <> t.binome_id
         or lower(j.role) = right(t.question_id, 1))
), 'le repondant est le partenaire de celui qui a prepare');
select assert_vrai((select count(*) from tours where manche = 'bonus' and repondant_id is not null) = 0,
                   'le bonus n a pas de repondant designe : les deux repondent');

-- comparabilite : les deux binomes Zamours jouent exactement les memes questions
select assert_vrai((
  select count(distinct liste) = 1 from (
    select binome_id, array_agg(question_id order by question_id) liste
    from tours where manche in ('qcm','libre') group by binome_id
  ) z
), 'les deux binomes du meme mode jouent les memes questions');

\echo '--- la preparation ---'
reset role; select devenir(:p1::uuid); set role authenticated;
select assert_vrai((rpc_mes_questions()->>'total')::int = 11,
                   'chaque joueur a 11 questions : 2 ouvertes + 1 QCM + 3 duos + 5 finale');
select set_config('zz.q1', (rpc_mes_questions()->'questions'->>0), false);
select assert_vrai(right(current_setting('zz.q1'),1) = lower((rpc_mes_questions()->>'role')),
                   'les paires servies correspondent au slot du joueur');

-- sets croises : aucune question commune entre les deux membres
reset role; select devenir(:p2::uuid); set role authenticated;
select set_config('zz.qp2', (rpc_mes_questions()->'questions')::text, false);
reset role; select devenir(:p1::uuid); set role authenticated;
-- les paires (suffixe .a / .b) doivent etre disjointes ;
-- le bonus et la serie de finale, eux, sont communs par construction.
select assert_vrai((
  select count(*) = 0 from (
    select x.value from jsonb_array_elements_text(rpc_mes_questions()->'questions') x
    intersect
    select y.value from jsonb_array_elements_text(current_setting('zz.qp2')::jsonb) y
  ) z where z.value ~ '\.[ab]$'
), 'sets croises : aucune paire commune entre les deux membres');
select assert_vrai((
  select count(*) = 8 from (
    select x.value from jsonb_array_elements_text(rpc_mes_questions()->'questions') x
    intersect
    select y.value from jsonb_array_elements_text(current_setting('zz.qp2')::jsonb) y
  ) z
), 'exactement 8 questions communes : les 3 duos et les 5 de la finale');

select assert_erreur('select rpc_repondre_prepa(''quo-99.a'', ''test'')',
                     'repondre a une question hors de son set');
select assert_erreur(format('select rpc_repondre_prepa(%L, '''')', current_setting('zz.q1')),
                     'reponse vide sans passer');
select assert_vrai((rpc_repondre_prepa(current_setting('zz.q1'), 'Le repassage')->>'faites')::int = 1,
                   'une reponse enregistree');
select assert_vrai((rpc_repondre_prepa(current_setting('zz.q1'), 'Etendre le linge')->>'faites')::int = 1,
                   'reecrire la meme question ne cree pas de doublon');
select assert_vrai((rpc_mes_reponses()->current_setting('zz.q1')->>'valeur') = 'Etendre le linge',
                   'on relit sa propre reponse, corrigee');

-- repondre a tout, pour verifier le drapeau de fin
do $$
declare q text;
begin
  for q in select x.value from jsonb_array_elements_text(rpc_mes_questions()->'questions') x loop
    perform rpc_repondre_prepa(q, 'reponse de ' || q);
  end loop;
end $$;
select assert_vrai((rpc_repondre_prepa(current_setting('zz.q1'), 'final')->>'termine')::boolean,
                   'drapeau termine une fois les 11 questions remplies');

-- personne ne lit les reponses d un autre
select assert_vrai((select count(*) from jsonb_object_keys(rpc_mes_reponses())) = 11,
                   'rpc_mes_reponses ne rend que les siennes');
reset role; select devenir(:p3::uuid); set role authenticated;
select assert_vrai((select count(*) from jsonb_object_keys(rpc_mes_reponses())) = 0,
                   'un autre joueur ne voit aucune reponse');

-- la TV voit des nombres, pas du contenu
reset role; select devenir(:tv::uuid); set role authenticated;
select assert_vrai((select termines from v_progression) = 1 and (select total from v_progression) = 4,
                   'la TV voit 1 joueur sur 4 termine, et rien d autre');

reset role;
\echo '=== TIRAGE ET PREPARATION : OK ==='
