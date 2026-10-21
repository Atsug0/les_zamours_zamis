\set ON_ERROR_STOP on
\echo '=== MODE SUJET ==='
reset role;
select remise_a_zero();

\set tv '''11111111-1111-1111-1111-111111111111'''
\set s  '''cccccccc-0000-0000-0000-000000000001'''
\set c1 '''cccccccc-0000-0000-0000-000000000002'''
\set c2 '''cccccccc-0000-0000-0000-000000000003'''
\set c3 '''cccccccc-0000-0000-0000-000000000004'''

do $$
declare ids uuid[] := array[
  'cccccccc-0000-0000-0000-000000000001','cccccccc-0000-0000-0000-000000000002',
  'cccccccc-0000-0000-0000-000000000003','cccccccc-0000-0000-0000-000000000004']::uuid[];
  noms text[] := array['Sam','Alex','Camille','Lou'];
  code text; i int;
begin
  perform devenir('11111111-1111-1111-1111-111111111111');
  code := rpc_creer_partie()->>'code';
  perform set_config('zz.code', code, false);
  for i in 1..4 loop perform devenir(ids[i]); perform rpc_rejoindre(code, noms[i]); end loop;
  perform devenir(ids[1]);            -- Sam devient le sujet
  perform rpc_devenir_sujet();
end $$;

select assert_vrai((select mode_jeu from parties) = 'sujet', 'la partie bascule en mode sujet');
select assert_vrai((select sujet_id from parties) = :s::uuid, 'Sam est le sujet');
select assert_vrai((select presentateur_id from parties) = :s::uuid,
                   'le sujet est aussi le presentateur : c est lui qui sait');

-- on ne vole pas la place de sujet
select devenir(:c1::uuid); set role authenticated;
select assert_erreur('select rpc_devenir_sujet()', 'devenir sujet quand il y en a deja un');
reset role;

-- il faut au moins deux challengers
do $$ begin perform devenir('11111111-1111-1111-1111-111111111111'); end $$;
select devenir(:tv::uuid); set role authenticated;
select assert_vrai((rpc_lancer_sujet('court')->>'tours')::int = 12,
                   'format court : 12 questions, 8 ouvertes + 4 QCM');
reset role;
select assert_vrai((select count(*) from binomes) = 3,
                   'une equipe d une personne par challenger');
select assert_vrai((select count(*) from joueurs where binome_id is null) = 1,
                   'seul le sujet n a pas d equipe');
select assert_vrai((select count(*) from tours where binome_id is not null) = 0,
                   'un tour du mode sujet n appartient a aucune equipe');
select assert_vrai((select count(*) from tours where questionneur_id = :s::uuid) = 12,
                   'le sujet mene tous les tours');
select assert_vrai((select etat from parties) = 'qcm', 'on demarre sur les QCM, sans prepa');
select assert_vrai((select count(*) from reponses_prepa) = 0,
                   'aucune preparation : le sujet repondra en direct');

\echo '--- un tour complet ---'
select set_config('zz.t', (select tour_courant::text from parties), false);

-- les challengers ne peuvent pas repondre avant le sujet
select devenir(:c1::uuid); set role authenticated;
select assert_erreur(format('select rpc_defier(%L, ''bleu'')', current_setting('zz.t')),
                     'repondre avant que le sujet ait repondu');
-- et le sujet ne se devine pas lui-meme
reset role; select devenir(:s::uuid); set role authenticated;
select assert_vrai((rpc_sujet_repond(current_setting('zz.t')::uuid, 'bleu')->>'statut') = 'consigne',
                   'le sujet repond en secret');
select assert_erreur(format('select rpc_sujet_repond(%L, ''rouge'')', current_setting('zz.t')),
                     'le sujet ne change pas sa reponse');
select assert_erreur(format('select rpc_defier(%L, ''bleu'')', current_setting('zz.t')),
                     'le sujet ne se devine pas lui-meme');

-- sa reponse reste invisible, meme pour les challengers
reset role; select devenir(:c1::uuid); set role authenticated;
select assert_vrai((select reponse_revelee from v_tours where id = current_setting('zz.t')::uuid) is null,
                   'la reponse du sujet est invisible avant la revelation');

-- les trois challengers repondent
do $$
declare ids uuid[] := array[
  'cccccccc-0000-0000-0000-000000000002','cccccccc-0000-0000-0000-000000000003',
  'cccccccc-0000-0000-0000-000000000004']::uuid[];
  rep text[] := array['bleu','  BLEU  ','vert'];   -- 2 justes dont une a la casse pres
  i int;
begin
  for i in 1..3 loop
    perform devenir(ids[i]);
    perform rpc_defier(current_setting('zz.t')::uuid, rep[i]);
  end loop;
end $$;
reset role;
select assert_vrai((select count(*) from reponses_manche
                    where tour_id = current_setting('zz.t')::uuid) = 3,
                   'les trois challengers ont repondu');
-- le compteur doit remonter : reponses_manche est muette par conception
select assert_vrai((select reponses_recues from tours
                    where id = current_setting('zz.t')::uuid) = 3,
                   'le compteur sur tours remonte, lui, en temps reel');

-- personne ne lit les reponses des autres avant la revelation
select devenir(:c1::uuid); set role authenticated;
select assert_vrai((select count(*) from v_reponses_manche
                    where tour_id = current_setting('zz.t')::uuid and valeur is not null) = 0,
                   'aucune reponse de challenger lisible avant la revelation');

-- revelation : le jugement est pre-rempli par comparaison normalisee
reset role; select devenir(:s::uuid); set role authenticated;
select assert_vrai(jsonb_array_length(
                     rpc_reveler_defis(current_setting('zz.t')::uuid)->'reponses') = 3,
                   'la revelation rend les trois reponses');
reset role;
select assert_vrai((select count(*) from reponses_manche
                    where tour_id = current_setting('zz.t')::uuid and juste) = 2,
                   'deux bonnes reponses, dont une a la casse et aux espaces pres');

-- le sujet corrige un cas limite
select devenir(:s::uuid); set role authenticated;
-- lu via la vue : ca prouve au passage qu elle expose bien la revision
select set_config('zz.rev', (select revision::text from v_tours
                             where id = current_setting('zz.t')::uuid), false);
select assert_vrai((rpc_juger_defi(current_setting('zz.t')::uuid, :c3::uuid, true)->>'juste')::boolean,
                   'le sujet peut valider une reponse formulee autrement');
select assert_vrai((select revision from v_tours where id = current_setting('zz.t')::uuid)
                   > current_setting('zz.rev')::int,
                   'un jugement incremente la revision, sinon rien ne serait diffuse');
select assert_vrai((rpc_clore_defis(current_setting('zz.t')::uuid)->>'justes')::int = 3,
                   'cloture : trois justes apres correction');
reset role;
select assert_vrai((select count(*) from binomes where score = 5) = 3,
                   'chaque bonne reponse rapporte 5 points en QCM, a son auteur');

-- un challenger ne clot pas le tour
select devenir(:c1::uuid); set role authenticated;
select assert_erreur(format('select rpc_juger_defi(%L, %L, true)',
                            current_setting('zz.t'), :c1), 'un challenger ne juge pas');
reset role;

\echo '--- la partie entiere ---'
do $$
declare tv uuid := '11111111-1111-1111-1111-111111111111';
  sujet uuid := 'cccccccc-0000-0000-0000-000000000001';
  t tours; j record; etat text; garde int := 0;
begin
  loop
    garde := garde + 1; exit when garde > 40;
    perform devenir(tv);
    etat := rpc_suivant()->>'etat';
    exit when etat = 'palmares';
    select * into t from tours where id = (select tour_courant from parties);
    if t.statut = 'juge' then continue; end if;
    if t.statut = 'attente' then
      perform devenir(sujet); perform rpc_sujet_repond(t.id, 'reponse ' || t.ordre);
      select * into t from tours where id = t.id;
    end if;
    if t.statut = 'consigne' then
      for j in select id from joueurs where partie_id = t.partie_id and id <> sujet loop
        perform devenir(j.id);
        perform rpc_defier(t.id, case when random() < 0.5 then 'reponse ' || t.ordre else 'rate' end);
      end loop;
      perform devenir(sujet); perform rpc_reveler_defis(t.id);
      select * into t from tours where id = t.id;
    end if;
    if t.statut = 'revele' then
      perform devenir(sujet); perform rpc_clore_defis(t.id);
    end if;
  end loop;
end $$;
select assert_vrai((select count(*) from tours where statut <> 'juge') = 0,
                   'les 12 tours sont joues');
select assert_vrai((select etat from parties) = 'palmares',
                   'le mode sujet va des manches droit au palmares : il n y a pas de partenaire a deviner');
select assert_vrai((select count(*) from passages_finale) = 0, 'et aucune finale creee');
select devenir(:c1::uuid); set role authenticated;
select assert_vrai((select count(*) from v_palmares) = 3,
                   'le palmares classe les trois challengers');
select assert_vrai((select count(*) from v_palmares where rang = 1) >= 1, 'il y a un premier');
reset role;
\echo '=== MODE SUJET : OK ==='
