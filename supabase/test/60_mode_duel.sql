\set ON_ERROR_STOP on
\echo '=== MODE DUEL ==='
reset role;
select remise_a_zero();

\set tv '''11111111-1111-1111-1111-111111111111'''
\set a  '''dddddddd-0000-0000-0000-000000000001'''
\set b  '''dddddddd-0000-0000-0000-000000000002'''

do $$
declare code text; q text;
begin
  perform devenir('11111111-1111-1111-1111-111111111111');
  code := rpc_creer_partie()->>'code';
  perform set_config('zz.code', code, false);
  perform devenir('dddddddd-0000-0000-0000-000000000001');
  perform rpc_rejoindre(code, 'Sam');
  perform devenir('dddddddd-0000-0000-0000-000000000002');
  perform rpc_rejoindre(code, 'Alex');
  perform devenir('dddddddd-0000-0000-0000-000000000001');
  perform rpc_apparier('dddddddd-0000-0000-0000-000000000002');
  perform rpc_choisir_mode('zamours');
  perform devenir('dddddddd-0000-0000-0000-000000000002');
  perform rpc_choisir_mode('zamours');
  perform devenir('11111111-1111-1111-1111-111111111111');
  perform set_config('zz.mode', rpc_lancer('court')->>'mode_jeu', false);
  -- les deux preparent, avec des reponses connues
  perform devenir('dddddddd-0000-0000-0000-000000000001');
  for q in select x.value from jsonb_array_elements_text(rpc_mes_questions()->'questions') x loop
    perform rpc_repondre_prepa(q, 'bleu');
  end loop;
  perform devenir('dddddddd-0000-0000-0000-000000000002');
  for q in select x.value from jsonb_array_elements_text(rpc_mes_questions()->'questions') x loop
    perform rpc_repondre_prepa(q, 'bleu');
  end loop;
end $$;

select assert_vrai(current_setting('zz.mode') = 'duel',
                   'le duel s active de lui-meme : deux joueurs, un binome');
select assert_vrai((select mode_jeu from parties) = 'duel', 'et la partie le sait');
select assert_vrai((select count(*) from tours) = 9,
                   '9 tours : 2 QCM + 4 libres + 3 duos, pour un seul binome');

\echo '--- QCM et questions libres : jugement mecanique ---'
select devenir(:tv::uuid); set role authenticated;
select rpc_suivant() \g /dev/null
reset role;
select set_config('zz.t', (select tour_courant::text from parties), false);

-- en duel, c est le repondant qui saisit, meme sur une question libre
select devenir((select questionneur_id from tours where id = current_setting('zz.t')::uuid));
set role authenticated;
select assert_erreur(format('select rpc_consigner(%L, ''bleu'')', current_setting('zz.t')),
                     'le questionneur ne saisit pas a la place du repondant');
reset role;
select devenir((select repondant_id from tours where id = current_setting('zz.t')::uuid));
set role authenticated;
select assert_vrai((rpc_consigner(current_setting('zz.t')::uuid, 'bleu')->>'verdict')::boolean,
                   'concordance calculee mecaniquement : aucun vote');
reset role;
select assert_vrai((select statut from tours where id = current_setting('zz.t')::uuid) = 'juge',
                   'le tour est juge immediatement');

\echo '--- contestation ---'
select devenir(:tv::uuid); set role authenticated; select rpc_suivant() \g /dev/null
reset role;
select set_config('zz.t', (select tour_courant::text from parties), false);
select devenir((select repondant_id from tours where id = current_setting('zz.t')::uuid));
set role authenticated;
select assert_vrai((rpc_consigner(current_setting('zz.t')::uuid, 'bleu nuit')->>'contestable')::boolean,
                   'une reponse proche mais differente est refusee, et contestable');
reset role;
select set_config('zz.score', (select score::text from binomes), false);
select assert_vrai((select points from tours where id = current_setting('zz.t')::uuid) = 0,
                   'zero point pour l instant');

select devenir((select repondant_id from tours where id = current_setting('zz.t')::uuid));
set role authenticated;
select assert_vrai((rpc_contester(current_setting('zz.t')::uuid)->>'contestee')::boolean,
                   'le repondant conteste');
select assert_erreur(format('select rpc_trancher_contestation(%L, true)', current_setting('zz.t')),
                     'on ne s accorde pas ses propres points');
reset role;
select assert_vrai((select statut from tours where id = current_setting('zz.t')::uuid) = 'revele',
                   'le tour est rouvert');

-- l adversaire tranche
select devenir((select id from joueurs
                where id <> (select repondant_id from tours where id = current_setting('zz.t')::uuid)
                  and binome_id is not null limit 1));
set role authenticated;
select assert_vrai((rpc_trancher_contestation(current_setting('zz.t')::uuid, true)->>'verdict')::boolean,
                   'l adversaire accepte : la reponse compte');
reset role;
-- le bareme depend de la manche : 5 en QCM, 15 en libre
select set_config('zz.att', (select points_manche(manche)::text from tours
                             where id = current_setting('zz.t')::uuid), false);
select assert_vrai((select points from tours where id = current_setting('zz.t')::uuid)
                   = current_setting('zz.att')::int,
                   'la reponse acceptee rapporte le bareme de sa manche');
select assert_vrai((select score from binomes)
                   = current_setting('zz.score')::int + current_setting('zz.att')::int,
                   'et le score suit, sans double comptage apres la contestation');

select devenir((select repondant_id from tours where id = current_setting('zz.t')::uuid));
set role authenticated;
select assert_erreur(format('select rpc_contester(%L)', current_setting('zz.t')),
                     'on ne conteste pas une reponse acceptee');
reset role;

\echo '--- la partie entiere, bonus et finale compris ---'
do $$
declare tv uuid := '11111111-1111-1111-1111-111111111111'; t tours; etat text; garde int := 0;
begin
  loop
    garde := garde + 1; exit when garde > 30;
    perform devenir(tv);
    etat := rpc_suivant()->>'etat';
    exit when etat not in ('qcm','libre','citez3','bonus');
    select * into t from tours where id = (select tour_courant from parties);
    if t.statut = 'juge' then continue; end if;
    if t.manche = 'bonus' then
      perform devenir(t.questionneur_id); perform rpc_reveler(t.id);
    else
      perform devenir(t.repondant_id); perform rpc_consigner(t.id, 'bleu');
    end if;
  end loop;
end $$;
select assert_vrai((select count(*) from tours where statut <> 'juge') = 0,
                   'tous les tours sont joues, sans jamais un seul vote');
select assert_vrai((select count(*) from votes) = 0,
                   'aucun vote enregistre : il n y avait personne pour voter');
select assert_vrai((select etat from parties) = 'finale', 'on arrive en finale');
select assert_vrai((select count(*) from passages_finale) = 1, 'un seul passage de finale');

reset role;
\echo '=== MODE DUEL : OK ==='
