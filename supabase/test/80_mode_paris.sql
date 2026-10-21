\set ON_ERROR_STOP on
\echo '=== MODE PARIS ==='
reset role;
select remise_a_zero();

\set tv '''11111111-1111-1111-1111-111111111111'''
\set p1 '''ffffffff-0000-0000-0000-000000000001'''
\set p2 '''ffffffff-0000-0000-0000-000000000002'''
\set p3 '''ffffffff-0000-0000-0000-000000000003'''
\set p4 '''ffffffff-0000-0000-0000-000000000004'''
\set p5 '''ffffffff-0000-0000-0000-000000000005'''

do $$
declare ids uuid[] := array[
  'ffffffff-0000-0000-0000-000000000001','ffffffff-0000-0000-0000-000000000002',
  'ffffffff-0000-0000-0000-000000000003','ffffffff-0000-0000-0000-000000000004',
  'ffffffff-0000-0000-0000-000000000005']::uuid[];
  noms text[] := array['Sam','Alex','Camille','Lou','Max'];
  code text; i int; q text;
begin
  perform devenir('11111111-1111-1111-1111-111111111111');
  code := rpc_creer_partie()->>'code';
  perform set_config('zz.code', code, false);
  for i in 1..5 loop perform devenir(ids[i]); perform rpc_rejoindre(code, noms[i]); end loop;
  perform devenir(ids[1]); perform rpc_apparier(ids[2]);
  perform devenir(ids[3]); perform rpc_apparier(ids[4]);
  perform devenir(ids[5]); perform rpc_devenir_presentateur();
  for i in 1..4 loop perform devenir(ids[i]); perform rpc_choisir_mode('zamours'); end loop;
  perform devenir(ids[5]);                     -- le presentateur choisit le mode de jeu
  perform rpc_choisir_mode_jeu('paris');
  perform devenir('11111111-1111-1111-1111-111111111111');
  perform set_config('zz.mode', rpc_lancer('court')->>'mode_jeu', false);
  for i in 1..4 loop
    perform devenir(ids[i]);
    for q in select x.value from jsonb_array_elements_text(rpc_mes_questions()->'questions') x loop
      perform rpc_repondre_prepa(q, 'bleu');
    end loop;
  end loop;
end $$;

select assert_vrai(current_setting('zz.mode') = 'paris', 'la partie est lancee en mode paris');

\echo '--- un tour : la consignation ouvre les paris ---'
select devenir(:tv::uuid); set role authenticated; select rpc_suivant() \g /dev/null
reset role;
select set_config('zz.t', (select tour_courant::text from parties), false);

select devenir((select repondant_id from tours where id = current_setting('zz.t')::uuid));
set role authenticated;
select assert_vrai((rpc_consigner(current_setting('zz.t')::uuid, 'bleu')->>'paris_ouverts')::boolean,
                   'en mode paris, meme un QCM ouvre les paris au lieu de se juger');
reset role;
select assert_vrai((select statut from tours where id = current_setting('zz.t')::uuid) = 'consigne',
                   'le tour attend les paris');
select assert_vrai((select verdict from tours where id = current_setting('zz.t')::uuid) is null,
                   'aucun verdict tant que le public n a pas parie');

-- qui parie, qui ne parie pas
select devenir((select repondant_id from tours where id = current_setting('zz.t')::uuid));
set role authenticated;
select assert_erreur(format('select rpc_parier(%L, true)', current_setting('zz.t')),
                     'le binome en jeu ne parie pas sur lui-meme');
reset role; select devenir(:p5::uuid); set role authenticated;
select assert_erreur(format('select rpc_parier(%L, true)', current_setting('zz.t')),
                     'le presentateur ne parie pas : c est lui qui peut corriger');
reset role;

-- les deux membres de l autre binome parient, l un juste l autre non
do $$
declare v uuid; i int := 0;
begin
  for v in select parieurs(current_setting('zz.t')::uuid) loop
    i := i + 1;
    perform devenir(v);
    perform rpc_parier(current_setting('zz.t')::uuid, i = 1);
  end loop;
end $$;
select assert_vrai((select reponses_recues from tours where id = current_setting('zz.t')::uuid) = 2,
                   'les deux parieurs se sont prononces');

-- cloture : la concordance est mecanique
select devenir(:tv::uuid); set role authenticated;
select set_config('zz.r', rpc_clore_paris(current_setting('zz.t')::uuid)::text, false);
reset role;
select assert_vrai((current_setting('zz.r')::jsonb->>'verdict')::boolean,
                   'la concordance est calculee, sans vote de la salle');
select assert_vrai((current_setting('zz.r')::jsonb->>'paris_justes')::int = 1,
                   'un seul parieur avait lu juste');
select assert_vrai((select score from binomes b join joueurs j on j.binome_id = b.id
                    where j.id = :p1::uuid) = 5,
                   'le binome en jeu marque sa manche : 5 points en QCM');
select assert_vrai((select score from binomes b join joueurs j on j.binome_id = b.id
                    where j.id = :p3::uuid) = 5,
                   'et le binome du parieur juste marque 5 points de lecture');

\echo '--- corriger un verdict est reserve a qui ne parie pas ---'
-- Il faut une partie SANS presentateur : avec lui, c est lui le
-- questionneur de tous les tours, et il a legitimement le droit de
-- corriger. Sans lui, le questionneur est un joueur d un autre binome,
-- donc un PARIEUR : il peut clore, mais pas corriger.
reset role; select remise_a_zero();
do $$
declare ids uuid[] := array[
  'ffffffff-1000-0000-0000-000000000001','ffffffff-1000-0000-0000-000000000002',
  'ffffffff-1000-0000-0000-000000000003','ffffffff-1000-0000-0000-000000000004']::uuid[];
  code text; i int; q text;
begin
  perform devenir('11111111-1111-1111-1111-111111111111');
  code := rpc_creer_partie()->>'code';
  perform set_config('zz.code', code, false);
  for i in 1..4 loop perform devenir(ids[i]); perform rpc_rejoindre(code, 'J' || i); end loop;
  perform devenir(ids[1]); perform rpc_apparier(ids[2]);
  perform devenir(ids[3]); perform rpc_apparier(ids[4]);
  for i in 1..4 loop perform devenir(ids[i]); perform rpc_choisir_mode('zamis'); end loop;
  perform devenir(ids[1]); perform rpc_choisir_mode_jeu('paris');
  perform devenir('11111111-1111-1111-1111-111111111111');
  perform rpc_lancer('court');
  for i in 1..4 loop
    perform devenir(ids[i]);
    for q in select x.value from jsonb_array_elements_text(rpc_mes_questions()->'questions') x loop
      perform rpc_repondre_prepa(q, 'bleu');
    end loop;
  end loop;
  perform devenir('11111111-1111-1111-1111-111111111111');
  perform rpc_suivant();
end $$;
select set_config('zz.t', (select tour_courant::text from parties), false);
-- Le questionneur peut se trouver etre aussi l hote, qui a le droit de
-- corriger : on rend le test explicite en donnant le role d hote au
-- plateau, qui n est pas un joueur. On teste ainsi le garde-fou, pas le
-- hasard du tirage.
update parties set hote_id = null;
select assert_vrai((select count(*) from tours t join joueurs j on j.id = t.questionneur_id
                    where t.id = current_setting('zz.t')::uuid
                      and j.id in (select parieurs(t.id))) = 1,
                   'sans presentateur, le questionneur est lui-meme un parieur');

select devenir((select repondant_id from tours where id = current_setting('zz.t')::uuid));
set role authenticated;
select rpc_consigner(current_setting('zz.t')::uuid, 'bleu marine') \g /dev/null
reset role;
do $$
declare v uuid;
begin
  for v in select parieurs(current_setting('zz.t')::uuid) loop
    perform devenir(v); perform rpc_parier(current_setting('zz.t')::uuid, true);
  end loop;
end $$;

select devenir((select questionneur_id from tours where id = current_setting('zz.t')::uuid));
set role authenticated;
select assert_erreur(format('select rpc_clore_paris(%L, true)', current_setting('zz.t')),
                     'un questionneur qui parie ne corrige pas le verdict');
select assert_vrai((rpc_clore_paris(current_setting('zz.t')::uuid)->>'verdict')::boolean is false,
                   'il peut clore : le verdict reste mecanique');
select assert_vrai((rpc_clore_paris(current_setting('zz.t')::uuid)->>'deja')::boolean,
                   'un tour clos ne se reclot pas');
reset role;

\echo '--- les paris demandent un public ---'
select remise_a_zero();
do $$
declare code text;
begin
  perform devenir('11111111-1111-1111-1111-111111111111');
  code := rpc_creer_partie()->>'code';
  perform devenir('ffffffff-0000-0000-0000-00000000000a'); perform rpc_rejoindre(code, 'Un');
  perform devenir('ffffffff-0000-0000-0000-00000000000b'); perform rpc_rejoindre(code, 'Deux');
  perform devenir('ffffffff-0000-0000-0000-00000000000a');
  perform rpc_apparier('ffffffff-0000-0000-0000-00000000000b');
  perform rpc_choisir_mode('zamours');
  perform devenir('ffffffff-0000-0000-0000-00000000000b');
  perform rpc_choisir_mode('zamours');
  perform devenir('11111111-1111-1111-1111-111111111111');
  perform rpc_choisir_mode_jeu('paris');
end $$;
select devenir(:tv::uuid); set role authenticated;
select assert_erreur('select rpc_lancer(''court'')',
                     'des paris a deux : refuse, il n y a pas de public');
reset role;
\echo '=== MODE PARIS : OK ==='
