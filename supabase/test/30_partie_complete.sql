\set ON_ERROR_STOP on
\echo '=== PARTIE COMPLETE ==='
reset role;
select remise_a_zero();

\set tv '''11111111-1111-1111-1111-111111111111'''
\set p1 '''aaaaaaaa-0000-0000-0000-000000000001'''
\set p2 '''aaaaaaaa-0000-0000-0000-000000000002'''
\set p3 '''aaaaaaaa-0000-0000-0000-000000000003'''
\set p4 '''aaaaaaaa-0000-0000-0000-000000000004'''
\set p5 '''aaaaaaaa-0000-0000-0000-000000000005'''

-- Deux binomes Zamours + un presentateur. Les votants d un tour sont
-- donc les 2 membres de l autre binome : l egalite est possible, ce
-- qui permet de tester l arbitrage.
do $$
declare ids uuid[] := array[
  'aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000002',
  'aaaaaaaa-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-000000000004',
  'aaaaaaaa-0000-0000-0000-000000000005']::uuid[];
  noms text[] := array['Sam','Alex','Camille','Lou','Max'];
  code text; i int; q text;
begin
  perform devenir('11111111-1111-1111-1111-111111111111');
  code := rpc_creer_partie()->>'code';
  perform set_config('zz.code', code, false);
  for i in 1..5 loop
    perform devenir(ids[i]);
    perform rpc_rejoindre(code, noms[i]);
  end loop;
  perform devenir(ids[1]); perform rpc_apparier(ids[2]);
  perform devenir(ids[3]); perform rpc_apparier(ids[4]);
  perform devenir(ids[5]); perform rpc_devenir_presentateur();
  for i in 1..4 loop perform devenir(ids[i]); perform rpc_choisir_mode('zamours'); end loop;
  perform devenir('11111111-1111-1111-1111-111111111111');
  perform rpc_lancer('court');
  -- tout le monde prepare, et repond 'oui' partout : la concordance
  -- devient donc entierement pilotee par ce que repond le joueur en jeu
  for i in 1..4 loop
    perform devenir(ids[i]);
    for q in select x.value from jsonb_array_elements_text(rpc_mes_questions()->'questions') x loop
      perform rpc_repondre_prepa(q, 'oui');
    end loop;
  end loop;
end $$;

select assert_vrai((select count(*) from reponses_prepa) = 36, '4 joueurs x 9 questions preparees');
select assert_vrai((select termines from v_progression) = 4, 'la TV voit 4 joueurs sur 4 termines');

\echo '--- manche QCM : le joueur tape son propre choix ---'
select devenir(:tv::uuid);
select assert_vrai((rpc_suivant()->>'etat') = 'qcm', 'premier tour : manche QCM');
select set_config('zz.t', (select tour_courant::text from parties), false);

-- le questionneur ne consigne PAS un QCM
select devenir((select questionneur_id from tours where id = current_setting('zz.t')::uuid));
select assert_erreur(format('select rpc_consigner(%L, ''oui'')', current_setting('zz.t')),
                     'en QCM le questionneur ne consigne pas');
-- un spectateur non plus
select devenir(:tv::uuid);
select assert_erreur(format('select rpc_consigner(%L, ''oui'')', current_setting('zz.t')),
                     'le plateau ne consigne pas a la place du joueur');

select devenir((select repondant_id from tours where id = current_setting('zz.t')::uuid));
select assert_vrai((rpc_consigner(current_setting('zz.t')::uuid, 'oui')->>'verdict')::boolean,
                   'QCM juste : valide automatiquement, sans vote');
select assert_vrai((select points from tours where id = current_setting('zz.t')::uuid) = 5,
                   'un QCM juste rapporte 5 points');
select assert_vrai((select statut from tours where id = current_setting('zz.t')::uuid) = 'juge',
                   'le QCM ne passe jamais par le vote');

select devenir(:tv::uuid); select rpc_suivant() \g /dev/null
select set_config('zz.t', (select tour_courant::text from parties), false);
select devenir((select repondant_id from tours where id = current_setting('zz.t')::uuid));
select assert_vrai((rpc_consigner(current_setting('zz.t')::uuid, 'non')->>'verdict')::boolean is false,
                   'QCM faux : refuse automatiquement');
select assert_vrai((select points from tours where id = current_setting('zz.t')::uuid) = 0,
                   'un QCM faux rapporte 0');

-- on joue les QCM restants
do $$
declare t tours;
begin
  loop
    perform devenir('11111111-1111-1111-1111-111111111111');
    if (rpc_suivant()->>'etat') <> 'qcm' then exit; end if;
    select * into t from tours where id = (select tour_courant from parties);
    perform devenir(t.repondant_id);
    perform rpc_consigner(t.id, 'oui');
  end loop;
end $$;
select assert_vrai((select count(*) from tours where manche='qcm' and statut='juge') = 4,
                   'les 4 tours QCM sont joues');

\echo '--- manche libre : consignation, revelation, vote ---'
select devenir(:tv::uuid); select rpc_suivant() \g /dev/null
select set_config('zz.t', (select tour_courant::text from parties), false);
select assert_vrai((select manche from tours where id = current_setting('zz.t')::uuid) = 'libre',
                   'on est passe a la manche libre');

-- la reponse enregistree n est PAS visible avant la revelation
select devenir((select questionneur_id from tours where id = current_setting('zz.t')::uuid));
select assert_vrai((select reponse_revelee from v_tours where id = current_setting('zz.t')::uuid) is null,
                   'avant revelation, la reponse enregistree est invisible, meme pour le questionneur');
select assert_erreur(format('select rpc_reveler(%L)', current_setting('zz.t')),
                     'reveler avant d avoir consigne');
select assert_vrai((rpc_consigner(current_setting('zz.t')::uuid, 'oui')->>'statut') = 'consigne',
                   'le questionneur consigne la reponse orale');
select assert_vrai((rpc_reveler(current_setting('zz.t')::uuid)->>'votants')::int = 2,
                   'deux votants : les membres de l autre binome');
select assert_vrai((select reponse_revelee from v_tours where id = current_setting('zz.t')::uuid) = 'oui',
                   'apres revelation, la reponse enregistree devient publique');

-- qui ne vote pas
select devenir((select repondant_id from tours where id = current_setting('zz.t')::uuid));
select assert_erreur(format('select rpc_voter(%L, true)', current_setting('zz.t')),
                     'un membre du binome concerne ne vote pas');
select devenir(:p5::uuid);
select assert_erreur(format('select rpc_voter(%L, true)', current_setting('zz.t')),
                     'le presentateur ne vote pas, il arbitre');

-- cloture prematuree refusee
select devenir(:tv::uuid);
select assert_erreur(format('select rpc_clore_vote(%L)', current_setting('zz.t')),
                     'clore le vote avant la fin de la fenetre');

-- les deux votants valident -> cloture anticipee autorisee
do $$
declare t tours; v uuid;
begin
  select * into t from tours where id = current_setting('zz.t')::uuid;
  for v in select votants(t.id) loop perform devenir(v); perform rpc_voter(t.id, true); end loop;
end $$;
select devenir(:tv::uuid);
select assert_vrai((rpc_clore_vote(current_setting('zz.t')::uuid)->>'verdict')::boolean,
                   'tout le monde a vote : on clot avant l heure');
select assert_vrai((select points from tours where id = current_setting('zz.t')::uuid) = 15,
                   'une question libre validee rapporte 15 points');
select assert_vrai((select voix_pour from v_tours where id = current_setting('zz.t')::uuid) = 2,
                   'le decompte des voix n apparait qu une fois juge');

select assert_erreur(format('select rpc_voter(%L, true)', current_setting('zz.t')),
                     'voter apres la cloture');

\echo '--- egalite des voix : le presentateur arbitre ---'
select devenir(:tv::uuid); select rpc_suivant() \g /dev/null
select set_config('zz.t', (select tour_courant::text from parties), false);
do $$
declare t tours; v uuid; i int := 0;
begin
  select * into t from tours where id = current_setting('zz.t')::uuid;
  perform devenir(t.questionneur_id);
  perform rpc_consigner(t.id, 'peut-etre');
  perform rpc_reveler(t.id);
  for v in select votants(t.id) loop
    i := i + 1;
    perform devenir(v);
    perform rpc_voter(t.id, i = 1);     -- un pour, un contre
  end loop;
end $$;
select devenir(:tv::uuid);
select assert_vrai((rpc_clore_vote(current_setting('zz.t')::uuid)->>'arbitrage_requis')::boolean,
                   'egalite : la cloture demande un arbitrage');
select devenir(:p1::uuid);
select assert_erreur(format('select rpc_arbitrer(%L, true)', current_setting('zz.t')),
                     'un joueur ne s arbitre pas lui-meme');
select devenir(:p5::uuid);
select assert_vrai((rpc_arbitrer(current_setting('zz.t')::uuid, false)->>'verdict')::boolean is false,
                   'le presentateur tranche');
select assert_vrai((select points from tours where id = current_setting('zz.t')::uuid) = 0,
                   'arbitrage negatif : 0 point');

\echo '--- gel des chronos sur deconnexion ---'
select devenir(:tv::uuid); select rpc_suivant() \g /dev/null
select set_config('zz.t', (select tour_courant::text from parties), false);
do $$
declare t tours;
begin
  select * into t from tours where id = current_setting('zz.t')::uuid;
  perform devenir(t.questionneur_id);
  perform rpc_consigner(t.id, 'oui');
  perform rpc_reveler(t.id);
end $$;
select devenir(:tv::uuid); select rpc_geler('absence') \g /dev/null
select assert_vrai((select en_pause from parties), 'la partie est gelee');
select assert_vrai((select vote_fin_at from tours where id = current_setting('zz.t')::uuid) is null
               and (select vote_restant_ms from tours where id = current_setting('zz.t')::uuid) > 0,
                   'la fenetre de vote garde son reste au lieu de courir');
do $$
declare t tours; v uuid;
begin
  select * into t from tours where id = current_setting('zz.t')::uuid;
  select votants(t.id) into v limit 1;
  perform devenir(v);
end $$;
select assert_erreur(format('select rpc_voter(%L, true)', current_setting('zz.t')),
                     'on ne vote pas pendant une pause');
select devenir(:tv::uuid); select rpc_degeler() \g /dev/null
select assert_vrai((select en_pause from parties) is false, 'la partie repart');
select assert_vrai((select vote_fin_at from tours where id = current_setting('zz.t')::uuid) > now(),
                   'le chrono repart la ou il s etait arrete');

-- On joue tout le reste des manches. La boucle reprend un tour la ou
-- il en est : c est exactement ce que fait le plateau apres une pause.
do $$
declare tv uuid := '11111111-1111-1111-1111-111111111111'; t tours; v uuid; etat text;
begin
  loop
    perform devenir(tv);
    etat := rpc_suivant()->>'etat';
    exit when etat not in ('qcm','libre','bonus');
    select * into t from tours where id = (select tour_courant from parties);

    if t.statut = 'attente' then
      if t.manche = 'qcm' then
        perform devenir(t.repondant_id);
        perform rpc_consigner(t.id, 'oui');
      elsif t.manche = 'bonus' then
        perform devenir(t.questionneur_id);
        perform rpc_reveler(t.id);
      else
        perform devenir(t.questionneur_id);
        perform rpc_consigner(t.id, 'oui');
        perform rpc_reveler(t.id);
      end if;
      select * into t from tours where id = t.id;
    elsif t.statut = 'consigne' then
      perform devenir(t.questionneur_id);
      perform rpc_reveler(t.id);
      select * into t from tours where id = t.id;
    end if;

    if t.statut = 'vote' then
      for v in select votants(t.id) loop perform devenir(v); perform rpc_voter(t.id, true); end loop;
      perform devenir(tv);
      perform rpc_clore_vote(t.id);
    end if;
  end loop;
end $$;

select assert_vrai((select count(*) from tours where statut <> 'juge') = 0, 'tous les tours sont joues');
select assert_vrai((select count(*) from tours where manche = 'bonus' and verdict) = 2,
                   'le bonus compare les deux reponses de prepa, sans consignation');
select assert_vrai((select sum(points) from tours where manche = 'bonus') = 60,
                   'un bonus concordant vaut 30 points');

\echo '--- la finale ---'
select assert_vrai((select etat from parties) = 'finale', 'on passe en finale');
select assert_vrai((select count(*) from passages_finale) = 2, 'un passage par binome');
select assert_vrai((
  select bool_and(ok) from (
    select f.ordre, b.score, lag(b.score) over (order by f.ordre) <= b.score as ok
    from passages_finale f join binomes b on b.id = f.binome_id
  ) z where ordre > 1
), 'ordre de passage du dernier au premier : le leader finit sous pression');

select set_config('zz.f', (select id::text from passages_finale order by ordre limit 1), false);
select devenir((select questionneur_id from passages_finale where id = current_setting('zz.f')::uuid));
select assert_erreur(format('select rpc_demarrer_passage(%L)', current_setting('zz.f')),
                     'demarrer sans avoir designe le finaliste');

-- le binome designe qui joue
do $$
declare f passages_finale; v_j uuid;
begin
  select * into f from passages_finale where id = current_setting('zz.f')::uuid;
  select id into v_j from joueurs where binome_id = f.binome_id order by role limit 1;
  perform devenir(v_j);
  perform rpc_designer_finaliste(f.id, v_j);
  perform set_config('zz.fj', v_j::text, false);
end $$;
select assert_vrai((select joueur_id from passages_finale where id = current_setting('zz.f')::uuid)
                   = current_setting('zz.fj')::uuid, 'le binome designe son finaliste');

-- seul le questionneur mene le passage, et lui seul voit les reponses
select devenir(current_setting('zz.fj')::uuid);
select assert_erreur(format('select rpc_demarrer_passage(%L)', current_setting('zz.f')),
                     'le finaliste ne lance pas son propre passage');
select devenir((select questionneur_id from passages_finale where id = current_setting('zz.f')::uuid));
select assert_vrai(jsonb_array_length(rpc_demarrer_passage(current_setting('zz.f')::uuid)->'questions') = 5,
                   'le questionneur recoit les 5 reponses attendues, lui seul');
select assert_vrai((select count(*) from unnest(
                      (select jugements from passages_finale where id = current_setting('zz.f')::uuid)
                    ) x where x = 'attente') = 5, 'cinq pastilles en attente');

-- 3 justes sur 5 : le seuil est atteint
do $$
declare i int;
begin
  perform devenir((select questionneur_id from passages_finale where id = current_setting('zz.f')::uuid));
  for i in 1..5 loop
    perform rpc_juger(current_setting('zz.f')::uuid, i,
                      case when i <= 3 then 'juste' else 'faux' end);
  end loop;
end $$;
select assert_vrai((rpc_clore_passage(current_setting('zz.f')::uuid)->>'seuil_atteint')::boolean,
                   '3 bonnes reponses sur 5 : seuil atteint');
select assert_vrai((select points from passages_finale where id = current_setting('zz.f')::uuid) = 76,
                   '3 x 12 + prime de 40 = 76 points');

-- second passage : 2 justes, sous le seuil
do $$
declare f passages_finale; v_j uuid; i int;
begin
  select * into f from passages_finale where seuil_atteint is null order by ordre limit 1;
  select id into v_j from joueurs where binome_id = f.binome_id order by role limit 1;
  perform devenir(v_j); perform rpc_designer_finaliste(f.id, v_j);
  perform devenir(f.questionneur_id);
  perform rpc_demarrer_passage(f.id);
  for i in 1..5 loop
    perform rpc_juger(f.id, i, case when i <= 2 then 'juste' else 'faux' end);
  end loop;
  perform rpc_clore_passage(f.id);
  perform set_config('zz.f2', f.id::text, false);
end $$;
select assert_vrai((select seuil_atteint from passages_finale where id = current_setting('zz.f2')::uuid) is false,
                   '2 sur 5 : seuil manque');
select assert_vrai((select points from passages_finale where id = current_setting('zz.f2')::uuid) = 24,
                   'sous le seuil : 2 x 12 = 24 points, les bonnes reponses restent acquises');

\echo '--- palmares ---'
select devenir(:tv::uuid);
select assert_vrai((rpc_suivant()->>'etat') = 'palmares', 'la partie se termine sur le palmares');
set role authenticated;
select assert_vrai((select count(*) from v_palmares) = 2, 'le palmares liste les deux binomes');
select assert_vrai((select count(*) from v_palmares where rang = 1) = 1, 'un seul binome en tete');
select assert_vrai((select count(*) from v_recap) = 14, 'le recap contient les 14 tours joues');
-- verifie depuis les VUES : un client a de quoi recalculer les scores
select assert_vrai((
  select bool_and(pal.score = a.m + b.f) from v_palmares pal
  cross join lateral (select coalesce(sum(t.points),0) as m from v_tours t
                      where t.binome_id = pal.binome_id) a
  cross join lateral (select coalesce(sum(x.points),0) as f from v_passages_finale x
                      where x.binome_id = pal.binome_id) b
), 'le score de chaque binome est exactement manches + finale');
select assert_erreur('select count(*) from tours',
                     'les tables de jeu restent fermees en lecture directe');

reset role;
\echo '=== PARTIE COMPLETE : OK ==='
