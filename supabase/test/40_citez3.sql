\set ON_ERROR_STOP on
\echo '=== MANCHE CITE 3 ==='
reset role;
select remise_a_zero();

\set tv '''11111111-1111-1111-1111-111111111111'''
do $$
declare ids uuid[] := array[
  'aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000002',
  'aaaaaaaa-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-000000000004']::uuid[];
  noms text[] := array['Sam','Alex','Camille','Lou'];
  code text; i int; q text;
begin
  perform devenir('11111111-1111-1111-1111-111111111111');
  code := rpc_creer_partie()->>'code';
  perform set_config('zz.code', code, false);
  for i in 1..4 loop perform devenir(ids[i]); perform rpc_rejoindre(code, noms[i]); end loop;
  perform devenir(ids[1]); perform rpc_apparier(ids[2]);
  perform devenir(ids[3]); perform rpc_apparier(ids[4]);
  for i in 1..4 loop perform devenir(ids[i]); perform rpc_choisir_mode('zamis'); end loop;
  perform devenir('11111111-1111-1111-1111-111111111111');
  perform rpc_lancer('court', true);          -- variante activee
  for i in 1..4 loop
    perform devenir(ids[i]);
    for q in select x.value from jsonb_array_elements_text(rpc_mes_questions()->'questions') x loop
      perform rpc_repondre_prepa(q, 'reponse ' || q);
    end loop;
  end loop;
end $$;

select assert_vrai((select avec_citez3 from parties), 'la variante est activee sur la partie');
select assert_vrai((select jsonb_array_length(tirage->'zamis'->'citez3') from parties) = 2,
                   'deux enonces cite 3 tires, un par slot');
select assert_vrai((
  select count(distinct x.value) = 2 from parties p,
         jsonb_array_elements_text(p.tirage->'zamis'->'citez3') x
), 'les deux enonces sont distincts');

-- prepa : 9 questions + 3 sous-reponses
select assert_vrai((select nb_questions_prepa(id) from parties) = 12,
                   'la prepa passe a 12 questions : 9 + les 3 reponses du cite 3');
select assert_vrai((select count(*) from reponses_prepa) = 48, '4 joueurs x 12 reponses');
select assert_vrai((select count(*) from reponses_prepa where question_id like 'c3-%') = 12,
                   '3 sous-reponses par joueur pour le cite 3');

-- tours : 2 passages de plus par binome, juste avant le bonus
select assert_vrai((select count(*) from tours where manche = 'citez3') = 4,
                   'deux passages cite 3 par binome');
select assert_vrai((select min(ordre) from tours where manche = 'citez3')
                 > (select max(ordre) from tours where manche = 'libre'),
                   'cite 3 passe apres la manche libre');
select assert_vrai((select max(ordre) from tours where manche = 'citez3')
                 < (select min(ordre) from tours where manche = 'bonus'),
                   'cite 3 passe avant le bonus');
select assert_vrai((
  select count(*) = 0 from tours t join joueurs j on j.id = t.repondant_id
  where t.manche = 'citez3' and j.binome_id <> t.binome_id
), 'le repondant est bien du binome interroge');

-- jugement
select set_config('zz.t', (select id::text from tours where manche = 'citez3' order by ordre limit 1), false);
select devenir((select repondant_id from tours where id = current_setting('zz.t')::uuid));
select assert_erreur(format('select rpc_juger_citez3(%L, array[''a'',''b'',''c''], 3)',
                            current_setting('zz.t')),
                     'le joueur ne juge pas son propre cite 3');
select devenir((select questionneur_id from tours where id = current_setting('zz.t')::uuid));
select assert_erreur(format('select rpc_juger_citez3(%L, array[''a''], 4)', current_setting('zz.t')),
                     'plus de 3 reponses communes');
select assert_vrai((rpc_juger_citez3(current_setting('zz.t')::uuid,
                    array['un','deux','trois'], 2)->>'points')::int = 10,
                   '2 reponses communes sur 3 : 10 points');
reset role;
select assert_vrai((select points from tours where id = current_setting('zz.t')::uuid) = 10,
                   'les points sont bien au tour');
select assert_vrai((select reponse_revelee from tours where id = current_setting('zz.t')::uuid)
                   like '%reponse c3-%',
                   'les trois reponses attendues sont revelees ensemble');
select assert_vrai((select array_length(string_to_array(
                      (select reponse_donnee from tours where id = current_setting('zz.t')::uuid),
                      ' · '), 1)) = 3, 'les trois reponses donnees sont consignees');

-- la machine a etats doit pouvoir ENTRER dans la manche : rpc_suivant
-- ecrit « etat = manche », donc la contrainte sur parties.etat doit la
-- connaitre. Sans ca, la partie plante en arrivant sur le cite 3.
reset role;
do $$
declare t tours; v uuid; etat text; tv uuid := '11111111-1111-1111-1111-111111111111';
begin
  loop
    perform devenir(tv);
    etat := rpc_suivant()->>'etat';
    exit when etat not in ('qcm','libre','citez3','bonus');
    select * into t from tours where id = (select tour_courant from parties);
    if t.statut = 'juge' then continue; end if;
    if t.manche = 'qcm' then
      perform devenir(t.repondant_id); perform rpc_consigner(t.id, 'oui');
    elsif t.manche = 'citez3' then
      perform devenir(t.questionneur_id);
      perform rpc_juger_citez3(t.id, array['x','y','z'], 1);
    else
      perform devenir(t.questionneur_id);
      if t.manche <> 'bonus' then perform rpc_consigner(t.id, 'oui'); end if;
      perform rpc_reveler(t.id);
      for v in select votants(t.id) loop perform devenir(v); perform rpc_voter(t.id, true); end loop;
      perform devenir(tv); perform rpc_clore_vote(t.id);
    end if;
  end loop;
end $$;
select assert_vrai((select count(*) from tours where statut <> 'juge') = 0,
                   'la machine a etats traverse la manche cite 3 sans planter');
select assert_vrai((select etat from parties) = 'finale',
                   'et arrive bien en finale');

-- une partie sans la variante n a aucun tour cite 3
reset role; select remise_a_zero();
do $$
declare ids uuid[] := array[
  'bbbbbbbb-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000002',
  'bbbbbbbb-0000-0000-0000-000000000003','bbbbbbbb-0000-0000-0000-000000000004']::uuid[];
  code text; i int;
begin
  perform devenir('11111111-1111-1111-1111-111111111111');
  code := rpc_creer_partie()->>'code';
  for i in 1..4 loop perform devenir(ids[i]); perform rpc_rejoindre(code, 'J' || i); end loop;
  perform devenir(ids[1]); perform rpc_apparier(ids[2]);
  perform devenir(ids[3]); perform rpc_apparier(ids[4]);
  for i in 1..4 loop perform devenir(ids[i]); perform rpc_choisir_mode('zamis'); end loop;
  perform devenir('11111111-1111-1111-1111-111111111111');
  perform rpc_lancer('court');
end $$;
select assert_vrai((select count(*) from tours where manche = 'citez3') = 0,
                   'variante desactivee : aucun tour cite 3');
select assert_vrai((select nb_questions_prepa(id) from parties) = 9,
                   'et la prepa reste a 9 questions');

reset role;
\echo '=== MANCHE CITE 3 : OK ==='
