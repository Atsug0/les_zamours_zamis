\set ON_ERROR_STOP on
\echo '=== PARTIES DE DEMONSTRATION ==='
reset role;
select remise_a_zero();
\set moi '''99999999-0000-0000-0000-000000000001'''

-- Une partie de demo se deroule TOUTE SEULE jusqu au palmares : c est a
-- la fois l outil pour tester seul, et un test d integration qui
-- emprunte exactement les memes fonctions qu un humain.
create or replace function derouler_demo(p_mode text, p_bots int, p_max int default 400)
returns jsonb language plpgsql as $$
declare
  v_code text; v_partie uuid; i int := 0; v_etat text; v_avant text := '';
  v_moi uuid := '99999999-0000-0000-0000-000000000001';
  t tours; v_fige int := 0;
begin
  perform devenir(v_moi);
  v_code := rpc_creer_demo(p_mode, p_bots, 'zamis')->>'code';
  select id into v_partie from parties where code = v_code;

  if p_mode in ('binomes','paris','duel') then
    perform rpc_lancer('court');
  elsif p_mode = 'sujet' then
    perform rpc_lancer_sujet('court');
  else
    perform rpc_lancer_tournoi('court');
  end if;

  loop
    i := i + 1; exit when i > p_max;
    perform devenir(v_moi);
    select etat into v_etat from parties where id = v_partie;
    exit when v_etat = 'palmares';

    -- l humain fait sa part : sa prepa, puis ses propres actions
    if v_etat = 'prep' then
      perform rpc_remplir_ma_prepa();
    end if;
    perform rpc_bots_agir(v_partie);

    perform devenir(v_moi);
    select * into t from tours where partie_id = v_partie and statut <> 'juge'
    order by ordre limit 1;

    -- ce que l humain doit faire lui-meme
    if t.id is not null then
      if t.statut = 'attente' and t.repondant_id = v_moi
         and (t.manche = 'qcm' or (select mode_jeu from parties where id = v_partie) = 'duel') then
        perform rpc_consigner(t.id, 'reponse humaine');
      elsif t.statut = 'attente' and t.questionneur_id = v_moi and t.manche = 'bonus' then
        perform rpc_reveler(t.id);
      elsif t.statut = 'attente' and t.questionneur_id = v_moi
            and t.manche not in ('qcm','bonus')
            and (select mode_jeu from parties where id = v_partie) <> 'duel' then
        -- sur un QCM c est le repondant qui saisit, pas le questionneur
        perform rpc_consigner(t.id, 'reponse humaine');
      elsif t.statut = 'attente' and sujet_du_tour(t.id) = v_moi then
        perform rpc_sujet_repond(t.id, 'reponse humaine');
      elsif t.statut = 'consigne' and t.questionneur_id = v_moi
            and (select mode_jeu from parties where id = v_partie) = 'paris' then
        perform rpc_clore_paris(t.id);
      elsif t.statut = 'consigne' and sujet_du_tour(t.id) = v_moi
            and (select mode_jeu from parties where id = v_partie) in ('sujet','tournoi') then
        -- en tournoi le sujet EST le questionneur : tester le mode d abord
        perform rpc_reveler_defis(t.id);
      elsif t.statut = 'consigne' and t.questionneur_id = v_moi
            and (select mode_jeu from parties where id = v_partie)
                in ('binomes','duel','paris') then
        perform rpc_reveler(t.id);
      elsif t.statut = 'consigne' and (select mode_jeu from parties where id = v_partie) = 'paris'
            and v_moi in (select parieurs(t.id)) then
        perform rpc_parier(t.id, true);
      elsif t.statut = 'consigne'
            and (select mode_jeu from parties where id = v_partie) in ('sujet','tournoi')
            and sujet_du_tour(t.id) <> v_moi then
        perform rpc_defier(t.id, 'reponse humaine');
      elsif t.statut = 'vote' and v_moi in (select votants(t.id)) then
        perform rpc_voter(t.id, true);
      elsif t.statut = 'revele' and sujet_du_tour(t.id) = v_moi then
        perform rpc_clore_defis(t.id);
      end if;
    end if;

    -- la finale : l humain peut en etre le questionneur d un autre binome
    if v_etat = 'finale' then
      perform devenir(v_moi);
      declare f passages_finale; k int; begin
        select * into f from passages_finale
        where partie_id = v_partie and seuil_atteint is null order by ordre limit 1;
        if f.id is not null then
          if f.joueur_id is null
             and exists (select 1 from joueurs where binome_id = f.binome_id and id = v_moi) then
            perform rpc_designer_finaliste(f.id, v_moi);
          elsif f.questionneur_id = v_moi and f.joueur_id is not null then
            if f.chrono_fin_at is null and f.chrono_restant_ms is null then
              perform rpc_demarrer_passage(f.id);
              select * into f from passages_finale where id = f.id;
            end if;
            for k in 1..coalesce(array_length(f.jugements,1),0) loop
              if f.jugements[k] = 'attente' then
                perform rpc_juger(f.id, k, 'juste');
              end if;
            end loop;
            perform rpc_clore_passage(f.id);
          end if;
        end if;
      end;
    end if;

    -- le plateau fait avancer l emission
    perform devenir(v_moi);
    begin perform rpc_clore_vote(t.id); exception when others then null; end;
    begin perform rpc_suivant(); exception when others then null; end;

    -- detection de blocage : rien n a bouge depuis 25 tours de boucle
    if v_avant = v_etat || coalesce(t.id::text,'') || coalesce(t.statut,'') then
      v_fige := v_fige + 1;
      if v_fige > 25 then
        raise exception 'bloque en % (tour % statut %)', v_etat, t.ordre, t.statut;
      end if;
    else v_fige := 0; end if;
    v_avant := v_etat || coalesce(t.id::text,'') || coalesce(t.statut,'');
  end loop;

  return jsonb_build_object('mode', p_mode, 'boucles', i,
    'etat', (select etat from parties where id = v_partie),
    'tours_joues', (select count(*) from tours where partie_id = v_partie and statut = 'juge'),
    'tours_total', (select count(*) from tours where partie_id = v_partie),
    'scores', (select jsonb_agg(score order by score desc) from binomes where partie_id = v_partie));
end $$;

\echo '--- chaque mode se deroule seul jusqu au palmares ---'
select assert_vrai((derouler_demo('binomes', 3)->>'etat') = 'palmares', 'mode binomes');
select remise_a_zero();
select assert_vrai((derouler_demo('paris', 3)->>'etat') = 'palmares', 'mode paris');
select remise_a_zero();
select assert_vrai((derouler_demo('duel', 1)->>'etat') = 'palmares', 'mode duel');
select remise_a_zero();
select assert_vrai((derouler_demo('sujet', 3)->>'etat') = 'palmares', 'mode sujet');
select remise_a_zero();
select assert_vrai((derouler_demo('tournoi', 3)->>'etat') = 'palmares', 'mode tournoi');

\echo '--- et tous les tours sont bien joues ---'
select assert_vrai((select count(*) from tours where statut <> 'juge') = 0,
                   'aucun tour laisse en plan');
select assert_vrai((select sum(score) from binomes) > 0, 'des points ont ete marques');

\echo '--- les verrous de surete ---'
reset role; select remise_a_zero();
do $$
declare v_code text;
begin
  perform devenir('99999999-0000-0000-0000-000000000001');
  v_code := rpc_creer_demo('binomes', 3, 'zamis')->>'code';
  perform set_config('zz.demo', (select id::text from parties where code = v_code), false);
  -- une partie NORMALE a cote
  perform devenir('99999999-0000-0000-0000-00000000000a');
  v_code := rpc_creer_partie()->>'code';
  perform devenir('99999999-0000-0000-0000-00000000000b');
  perform rpc_rejoindre(v_code, 'Vrai');
  perform set_config('zz.vraie', (select id::text from parties where code = v_code), false);
end $$;
select devenir('99999999-0000-0000-0000-00000000000b'::uuid); set role authenticated;
select assert_erreur(format('select rpc_bots_agir(%L)', current_setting('zz.vraie')),
                     'piloter des bots sur une partie normale');
select assert_erreur(format('select rpc_bots_agir(%L)', current_setting('zz.demo')),
                     'piloter les bots d une partie ou on n est pas');
select assert_erreur('select rpc_remplir_ma_prepa()',
                     'se remplir sa prepa dans une partie normale');
reset role;
select assert_vrai((select count(*) from joueurs where bot) = 3,
                   'seuls les bots de la demo sont marques bot');
select assert_vrai((select count(*) from parties where demo) = 1,
                   'une seule partie est marquee demo');

reset role;
\echo '=== DEMONSTRATION : OK ==='
