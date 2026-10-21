-- =============================================================
-- 0003 — Lobby : créer, rejoindre, s'apparier, choisir son mode
-- Toutes ces fonctions sont SECURITY DEFINER et ne font JAMAIS
-- confiance à un identifiant passé en paramètre : l'appelant est
-- toujours auth.uid().
-- =============================================================

-- La télé ouvre la partie et devient le plateau.
create or replace function rpc_creer_partie()
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare p parties;
begin
  if auth.uid() is null then raise exception 'session requise'; end if;
  insert into parties (code, plateau_id) values (tirer_code(), auth.uid())
  returning * into p;
  return jsonb_build_object('partie_id', p.id, 'code', p.code, 'etat', p.etat);
end $$;

-- Un téléphone rejoint avec le code et un prénom.
-- Idempotent : rappeler la fonction depuis la même session rend le
-- même siège, c'est le chemin normal d'une reconnexion (§10.a).
create or replace function rpc_rejoindre(p_code text, p_prenom text)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  p parties;
  j joueurs;
  v_prenom text := btrim(p_prenom);
begin
  if auth.uid() is null then raise exception 'session requise'; end if;
  if length(v_prenom) = 0 or length(v_prenom) > 24 then
    raise exception 'prénom entre 1 et 24 caractères';
  end if;

  select * into p from parties where code = upper(btrim(p_code)) and expire_le > now();
  if p.id is null then raise exception 'aucune partie avec ce code'; end if;

  select * into j from joueurs where partie_id = p.id and id = auth.uid();
  if j.id is not null then
    update joueurs set vu_le = now() where id = j.id;
    return jsonb_build_object('partie_id', p.id, 'joueur_id', j.id, 'prenom', j.prenom,
                              'pin', j.pin, 'etat', p.etat, 'reprise', true);
  end if;

  if p.etat <> 'lobby' then raise exception 'la partie a déjà commencé'; end if;
  if (select count(*) from joueurs where partie_id = p.id) >= 12 then
    raise exception 'partie complète';
  end if;

  insert into joueurs (id, partie_id, prenom, pin)
  values (auth.uid(), p.id, v_prenom, tirer_pin())
  returning * into j;

  -- le premier arrivé devient l'hôte
  update parties set hote_id = coalesce(hote_id, j.id) where id = p.id;

  return jsonb_build_object('partie_id', p.id, 'joueur_id', j.id, 'prenom', j.prenom,
                            'pin', j.pin, 'etat', p.etat, 'reprise', false);
exception when unique_violation then
  raise exception 'ce prénom est déjà pris dans la partie';
end $$;

-- Former un binôme. L'appelant invite, la cible est appariée.
create or replace function rpc_apparier(p_cible uuid)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  moi joueurs; autre joueurs; p parties;
  v_couleur text; b binomes;
  couleurs text[] := array['rouge','jaune','bleu','vert','orange','violet'];
begin
  select * into moi from joueurs where id = auth.uid();
  if moi.id is null then raise exception 'rejoins la partie d''abord'; end if;
  if p_cible = moi.id then raise exception 'il faut être deux'; end if;

  select * into p from parties where id = moi.partie_id;
  if p.etat <> 'lobby' then raise exception 'les binômes sont figés'; end if;

  select * into autre from joueurs where id = p_cible and partie_id = moi.partie_id;
  if autre.id is null then raise exception 'joueur introuvable dans cette partie'; end if;
  if moi.binome_id is not null or autre.binome_id is not null then
    raise exception 'un des deux est déjà en binôme';
  end if;
  if p.presentateur_id in (moi.id, autre.id) then
    raise exception 'le présentateur ne joue pas';
  end if;

  select c into v_couleur from unnest(couleurs) c
  where c not in (select couleur from binomes where partie_id = p.id)
  limit 1;
  if v_couleur is null then raise exception 'six binômes au maximum'; end if;

  insert into binomes (partie_id, couleur) values (p.id, v_couleur) returning * into b;

  -- A et B tirés au sort : le rôle décide quel set de questions on prépare
  if random() < 0.5 then
    update joueurs set binome_id = b.id, role = 'A' where id = moi.id;
    update joueurs set binome_id = b.id, role = 'B' where id = autre.id;
  else
    update joueurs set binome_id = b.id, role = 'B' where id = moi.id;
    update joueurs set binome_id = b.id, role = 'A' where id = autre.id;
  end if;

  return jsonb_build_object('binome_id', b.id, 'couleur', b.couleur);
end $$;

-- Choisir Zamours ou Zamis. Le binôme ne se verrouille que si les
-- deux membres choisissent exactement la même chose (règles §2.2).
create or replace function rpc_choisir_mode(p_mode text, p_sensibles boolean default false,
                                            p_occasions text[] default '{}')
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare moi joueurs; partenaire joueurs; accord boolean := false;
begin
  if p_mode not in ('zamours','zamis') then raise exception 'mode inconnu'; end if;
  select * into moi from joueurs where id = auth.uid();
  if moi.binome_id is null then raise exception 'forme un binôme d''abord'; end if;

  update joueurs set mode_choisi = p_mode, sensibles_choisi = coalesce(p_sensibles,false),
                     occasions_choisies = coalesce(p_occasions,'{}')
  where id = moi.id;

  select * into partenaire from joueurs
  where binome_id = moi.binome_id and id <> moi.id;

  -- coalesce : sans partenaire, ou tant qu'il n'a pas choisi, la
  -- comparaison vaut NULL. L'API ne renvoie jamais un booléen nul.
  accord := coalesce(
        partenaire.mode_choisi = p_mode
    and partenaire.sensibles_choisi = coalesce(p_sensibles,false)
    and partenaire.occasions_choisies = coalesce(p_occasions,'{}'), false);

  if accord then
    update binomes set mode = p_mode, sensibles = coalesce(p_sensibles,false),
                       occasions = coalesce(p_occasions,'{}'), verrouille = true
    where id = moi.binome_id;
  else
    update binomes set verrouille = false where id = moi.binome_id;
  end if;

  return jsonb_build_object('accord', accord, 'attend', not accord);
end $$;

-- Effectif impair : le joueur qui reste peut présenter.
create or replace function rpc_devenir_presentateur()
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare moi joueurs; p parties; seuls int;
begin
  select * into moi from joueurs where id = auth.uid();
  if moi.id is null then raise exception 'rejoins la partie d''abord'; end if;
  select * into p from parties where id = moi.partie_id;
  if p.etat <> 'lobby' then raise exception 'trop tard'; end if;
  if p.presentateur_id is not null then raise exception 'il y a déjà un présentateur'; end if;
  if moi.binome_id is not null then raise exception 'quitte ton binôme d''abord'; end if;

  select count(*) into seuls from joueurs
  where partie_id = p.id and binome_id is null;
  if seuls <> 1 then
    raise exception 'le présentateur est le joueur en trop : il en reste % sans binôme', seuls;
  end if;

  update parties set presentateur_id = moi.id where id = p.id;
  return jsonb_build_object('presentateur_id', moi.id);
end $$;

-- Reprise de siège quand la session est vraiment perdue : autre
-- navigateur, navigation privée, données effacées (§10.b).
create or replace function rpc_reprendre_siege(p_code text, p_prenom text, p_pin text)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare p parties; j joueurs;
begin
  if auth.uid() is null then raise exception 'session requise'; end if;
  select * into p from parties where code = upper(btrim(p_code)) and expire_le > now();
  if p.id is null then raise exception 'aucune partie avec ce code'; end if;

  select * into j from joueurs
  where partie_id = p.id and lower(prenom) = lower(btrim(p_prenom));
  if j.id is null then raise exception 'ce prénom n''est pas dans la partie'; end if;
  if j.pin <> btrim(p_pin) then raise exception 'code de reprise incorrect'; end if;
  if j.id = auth.uid() then
    return jsonb_build_object('joueur_id', j.id, 'deja', true);
  end if;
  -- on ne vole pas le siège de quelqu'un qui joue à côté de soi
  if j.vu_le > now() - interval '30 seconds' then
    raise exception 'ce joueur est encore connecté';
  end if;

  update parties set presentateur_id = auth.uid() where presentateur_id = j.id;
  update parties set hote_id        = auth.uid() where hote_id        = j.id;
  update joueurs set id = auth.uid(), vu_le = now(), reprise_le = now() where id = j.id;

  return jsonb_build_object('partie_id', p.id, 'joueur_id', auth.uid(),
                            'prenom', j.prenom, 'etat', p.etat, 'reprise', true);
end $$;

-- La télé s'est éteinte : l'hôte ou le présentateur reprend le plateau.
create or replace function rpc_reclamer_plateau(p_code text)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare p parties;
begin
  select * into p from parties where code = upper(btrim(p_code)) and expire_le > now();
  if p.id is null then raise exception 'aucune partie avec ce code'; end if;
  if auth.uid() not in (coalesce(p.hote_id, p.plateau_id), coalesce(p.presentateur_id, p.plateau_id)) then
    raise exception 'seuls l''hôte et le présentateur peuvent reprendre le plateau';
  end if;
  update parties set plateau_id = auth.uid() where id = p.id;
  return jsonb_build_object('partie_id', p.id, 'plateau_id', auth.uid(), 'etat', p.etat);
end $$;

-- Les fonctions exigent toutes une identité : rien pour anon.
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p
           join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like 'rpc_%'
  loop
    execute format('revoke execute on function %s from public, anon', f.sig);
    execute format('grant  execute on function %s to authenticated', f.sig);
  end loop;
end $$;
