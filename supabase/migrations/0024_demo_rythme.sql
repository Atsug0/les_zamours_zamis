-- =============================================================
-- 0024 — Le rythme d'une partie de démonstration
--
-- Une fenêtre de vote de quinze secondes est juste quand une salle
-- délibère ; elle est interminable quand on déroule une partie tout
-- seul pour vérifier quelque chose. Les parties de démo prennent donc
-- des délais courts.
--
-- Les réglages restent dans `parties.reglages` : rien de particulier
-- à prévoir côté client, il affiche ce que la base lui donne.
-- =============================================================

create or replace function rpc_creer_demo(p_mode_jeu text default 'binomes',
                                          p_bots int default 3,
                                          p_mode text default 'zamis')
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  p parties; v_moi uuid; v_bid uuid; v_bot uuid; i int; v_nb int;
  noms text[] := array['Bot Ana','Bot Bruno','Bot Chloé','Bot Diego','Bot Elsa','Bot Fred','Bot Gaby'];
  couleurs text[] := array['rouge','jaune','bleu','vert','orange','violet'];
  v_libre uuid; v_couleur int := 0;
begin
  v_moi := auth.uid();
  if v_moi is null then raise exception 'session requise'; end if;
  if p_mode_jeu not in ('binomes','paris','sujet','tournoi','duel') then
    raise exception 'mode de jeu inconnu';
  end if;
  if p_mode not in ('zamours','zamis') then raise exception 'mode inconnu'; end if;

  v_nb := greatest(1, least(p_bots, 6));

  insert into parties (code, plateau_id, demo, reglages)
  values (tirer_code(), v_moi, true,
          jsonb_build_object('questionsFinale', 5, 'seuilFinale', 3,
                             'chronoFinaleMs', 20000, 'fenetreVoteMs', 4000,
                             'fenetreBonusMs', 5000, 'toleranceNumerique', 0.10))
  returning * into p;

  insert into joueurs (id, partie_id, prenom) values (v_moi, p.id, 'Toi');
  insert into sieges (joueur_id, pin) values (v_moi, tirer_pin());
  update parties set hote_id = v_moi where id = p.id;

  for i in 1..v_nb loop
    v_bot := gen_random_uuid();
    insert into joueurs (id, partie_id, prenom, bot) values (v_bot, p.id, noms[i], true);
    insert into sieges (joueur_id, pin) values (v_bot, tirer_pin());
  end loop;

  if p_mode_jeu in ('binomes','paris','duel') then
    v_couleur := 1;
    select id into v_bot from joueurs where partie_id = p.id and bot order by prenom limit 1;
    insert into binomes (partie_id, mode, couleur, verrouille)
    values (p.id, p_mode, couleurs[v_couleur], true) returning id into v_bid;
    update joueurs set binome_id = v_bid, role = 'A', mode_choisi = p_mode where id = v_moi;
    update joueurs set binome_id = v_bid, role = 'B', mode_choisi = p_mode where id = v_bot;

    loop
      select id into v_libre from joueurs
      where partie_id = p.id and bot and binome_id is null order by prenom limit 1;
      exit when v_libre is null;
      select id into v_bot from joueurs
      where partie_id = p.id and bot and binome_id is null and id <> v_libre
      order by prenom limit 1;
      if v_bot is null then
        update parties set presentateur_id = v_libre where id = p.id;
        exit;
      end if;
      v_couleur := v_couleur + 1;
      insert into binomes (partie_id, mode, couleur, verrouille)
      values (p.id, p_mode, couleurs[v_couleur], true) returning id into v_bid;
      update joueurs set binome_id = v_bid, role = 'A', mode_choisi = p_mode where id = v_libre;
      update joueurs set binome_id = v_bid, role = 'B', mode_choisi = p_mode where id = v_bot;
    end loop;

    if p_mode_jeu = 'paris' then
      update parties set mode_jeu = 'paris' where id = p.id;
    end if;

  elsif p_mode_jeu = 'sujet' then
    select id into v_bot from joueurs where partie_id = p.id and bot order by prenom limit 1;
    update parties set mode_jeu = 'sujet', sujet_id = v_bot, presentateur_id = v_bot
    where id = p.id;
    update joueurs set mode_choisi = p_mode where partie_id = p.id;
  else
    update joueurs set mode_choisi = p_mode where partie_id = p.id;
  end if;

  return jsonb_build_object('partie_id', p.id, 'code', p.code,
                            'mode_jeu', p_mode_jeu, 'bots', v_nb);
end $$;

revoke all on function rpc_creer_demo(text, int, text) from public, anon;
grant execute on function rpc_creer_demo(text, int, text) to authenticated;
