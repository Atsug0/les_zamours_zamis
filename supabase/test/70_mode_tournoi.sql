\set ON_ERROR_STOP on
\echo '=== MODE TOURNOI ==='
reset role;
select remise_a_zero();

\set tv '''11111111-1111-1111-1111-111111111111'''
do $$
declare ids uuid[] := array[
  'eeeeeeee-0000-0000-0000-000000000001','eeeeeeee-0000-0000-0000-000000000002',
  'eeeeeeee-0000-0000-0000-000000000003','eeeeeeee-0000-0000-0000-000000000004']::uuid[];
  noms text[] := array['Alex','Camille','Lou','Sam'];
  code text; i int;
begin
  perform devenir('11111111-1111-1111-1111-111111111111');
  code := rpc_creer_partie()->>'code';
  perform set_config('zz.code', code, false);
  for i in 1..4 loop perform devenir(ids[i]); perform rpc_rejoindre(code, noms[i]); end loop;
end $$;

-- il faut au moins trois joueurs
select devenir(:tv::uuid); set role authenticated;
select assert_vrai((rpc_lancer_tournoi('court')->>'tours')::int = 16,
                   '4 joueurs x 2 paires x 2 slots = 16 tours');
reset role;
select assert_vrai((select mode_jeu from parties) = 'tournoi', 'la partie est en tournoi');
select assert_vrai((select sujet_id from parties) is null,
                   'aucun sujet de partie : le sujet est une propriete du tour');
select assert_vrai((select count(*) from binomes) = 4,
                   'tout le monde marque, donc tout le monde a son equipe');
select assert_vrai((select count(distinct sujet_id) from tours) = 4,
                   'les quatre joueurs sont sujets a leur tour');
select assert_vrai((select count(*) = 4 from (
                      select sujet_id, count(*) n from tours group by sujet_id
                    ) z where n = 4), 'chacun est sujet pour quatre questions d affilee');
select assert_vrai((select count(*) = 0 from (
                      select sujet_id, min(ordre) mn, max(ordre) mx, count(*) n
                      from tours group by sujet_id
                    ) z where mx - mn + 1 <> n),
                   'les passages d un meme sujet sont consecutifs : « c est au tour de X » reste lisible');
select assert_vrai((select count(*) from tours where questionneur_id = sujet_id) = 16,
                   'le sujet mene ses propres questions');

\echo '--- un tour ---'
select set_config('zz.t', (select tour_courant::text from parties), false);
select set_config('zz.s', (select sujet_id::text from tours where id = current_setting('zz.t')::uuid), false);

-- seul le sujet du tour repond
select devenir((select id from joueurs where id <> current_setting('zz.s')::uuid limit 1));
set role authenticated;
select assert_erreur(format('select rpc_sujet_repond(%L, ''bleu'')', current_setting('zz.t')),
                     'un autre joueur ne repond pas a la place du sujet du tour');
reset role;
select devenir(current_setting('zz.s')::uuid); set role authenticated;
select assert_vrai((rpc_sujet_repond(current_setting('zz.t')::uuid, 'bleu')->>'statut') = 'consigne',
                   'le sujet du tour repond en secret');
select assert_erreur(format('select rpc_defier(%L, ''bleu'')', current_setting('zz.t')),
                     'le sujet ne se devine pas lui-meme');
reset role;

-- les trois autres defient
do $$
declare j record; i int := 0;
begin
  for j in select id from joueurs
           where id <> current_setting('zz.s')::uuid order by prenom loop
    i := i + 1;
    perform devenir(j.id);
    perform rpc_defier(current_setting('zz.t')::uuid,
                       case when i = 1 then 'bleu' else 'vert' end);
  end loop;
end $$;
select assert_vrai((select reponses_recues from tours where id = current_setting('zz.t')::uuid) = 3,
                   'les trois challengers ont repondu');

select devenir(current_setting('zz.s')::uuid); set role authenticated;
select rpc_reveler_defis(current_setting('zz.t')::uuid) \g /dev/null
select assert_vrai((rpc_clore_defis(current_setting('zz.t')::uuid)->>'justes')::int = 1,
                   'une seule bonne reponse');
reset role;
select assert_vrai((select count(*) from binomes where score = 15) = 1,
                   'une question libre rapporte 15 points, a son auteur seul');
select assert_vrai((select score from binomes b join joueurs j on j.binome_id = b.id
                    where j.id = current_setting('zz.s')::uuid) = 0,
                   'le sujet ne marque rien sur ses propres questions');

\echo '--- la partie entiere ---'
do $$
declare tv uuid := '11111111-1111-1111-1111-111111111111';
  t tours; j record; etat text; garde int := 0; v_sujet uuid;
begin
  loop
    garde := garde + 1; exit when garde > 60;
    perform devenir(tv);
    etat := rpc_suivant()->>'etat';
    exit when etat = 'palmares';
    select * into t from tours where id = (select tour_courant from parties);
    if t.statut = 'juge' then continue; end if;
    v_sujet := t.sujet_id;
    if t.statut = 'attente' then
      perform devenir(v_sujet);
      perform rpc_sujet_repond(t.id, 'rep' || t.ordre);
      select * into t from tours where id = t.id;
    end if;
    if t.statut = 'consigne' then
      for j in select id from joueurs where partie_id = t.partie_id and id <> v_sujet loop
        perform devenir(j.id);
        perform rpc_defier(t.id, case when random() < 0.4 then 'rep' || t.ordre else 'rate' end);
      end loop;
      perform devenir(v_sujet); perform rpc_reveler_defis(t.id);
      select * into t from tours where id = t.id;
    end if;
    if t.statut = 'revele' then
      perform devenir(v_sujet); perform rpc_clore_defis(t.id);
    end if;
  end loop;
end $$;
select assert_vrai((select count(*) from tours where statut <> 'juge') = 0, 'les 16 tours sont joues');
select assert_vrai((select etat from parties) = 'palmares', 'le tournoi finit sur le palmares');
select assert_vrai((select count(*) from passages_finale) = 0, 'et sans finale');
select devenir('eeeeeeee-0000-0000-0000-000000000001'::uuid); set role authenticated;
select assert_vrai((select count(*) from v_palmares) = 4,
                   'le palmares classe les quatre joueurs : qui connait le mieux le groupe');
reset role;

\echo '--- deux joueurs : ce n est plus un tournoi ---'
select remise_a_zero();
do $$
declare code text;
begin
  perform devenir('11111111-1111-1111-1111-111111111111');
  code := rpc_creer_partie()->>'code';
  perform set_config('zz.code2', code, false);
  perform devenir('eeeeeeee-0000-0000-0000-00000000000a'); perform rpc_rejoindre(code, 'Un');
  perform devenir('eeeeeeee-0000-0000-0000-00000000000b'); perform rpc_rejoindre(code, 'Deux');
end $$;
select devenir(:tv::uuid); set role authenticated;
select assert_erreur('select rpc_lancer_tournoi(''court'')',
                     'un tournoi a deux : refuse, c est un duel');
reset role;
\echo '=== MODE TOURNOI : OK ==='
