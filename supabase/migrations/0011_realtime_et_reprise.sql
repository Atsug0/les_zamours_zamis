-- =============================================================
-- 0011 — Deux bugs trouvés en vérifiant le temps réel en production
--
-- BUG 1 — Le lobby restait figé, sans aucune erreur.
-- Le temps réel ne fonctionne QUE SUR LES TABLES, jamais sur les
-- vues. La politique de `joueurs` limitait la lecture à sa propre
-- ligne (« id = auth.uid() »), et le reste passait par v_joueurs :
-- le plateau ne recevait donc AUCUN événement sur les joueurs, et
-- personne ne voyait personne arriver.
-- Cette restriction n'existait que pour protéger `pin`, qui est un
-- identifiant secret. On le sort donc de la table, et `joueurs`
-- s'ouvre aux membres de la partie.
--
-- BUG 2 — La reprise de siège ne marchait que dans le lobby.
-- rpc_reprendre_siege réattribue `joueurs.id`, et les sept clés
-- étrangères qui le référencent étaient en NO ACTION : dès qu'un
-- joueur avait écrit une réponse de préparation, l'opération
-- échouait. Donc exactement quand on en a besoin.
-- =============================================================

-- -------------------------------------------------------------
-- 1. Le PIN quitte joueurs pour sa propre table, sans aucun droit.
-- -------------------------------------------------------------
create table sieges (
  joueur_id uuid primary key references joueurs on delete cascade on update cascade,
  pin       char(4) not null
);
alter table sieges enable row level security;   -- aucune politique = refus total
revoke all on table sieges from anon, authenticated;

insert into sieges (joueur_id, pin) select id, pin from joueurs;
alter table joueurs drop column pin;

-- -------------------------------------------------------------
-- 2. joueurs devient lisible par les membres de la partie.
--    Plus rien de secret n'y reste : prénom, binôme, rôle, présence,
--    et le choix de mode en attente — qu'un partenaire peut voir sans
--    dommage, puisqu'il doit de toute façon s'accorder avec lui.
-- -------------------------------------------------------------
drop policy if exists lire_moi on joueurs;
create policy lire_joueurs on joueurs for select using (est_membre(partie_id));

-- -------------------------------------------------------------
-- 3. Les sept clés étrangères suivent un changement d'identité.
-- -------------------------------------------------------------
alter table parties         drop constraint parties_presentateur_fk,
  add constraint parties_presentateur_fk foreign key (presentateur_id)
      references joueurs on delete set null on update cascade;

alter table reponses_prepa  drop constraint reponses_prepa_joueur_id_fkey,
  add constraint reponses_prepa_joueur_id_fkey foreign key (joueur_id)
      references joueurs on delete cascade on update cascade;

alter table votes           drop constraint votes_joueur_id_fkey,
  add constraint votes_joueur_id_fkey foreign key (joueur_id)
      references joueurs on delete cascade on update cascade;

alter table tours           drop constraint tours_repondant_id_fkey,
  add constraint tours_repondant_id_fkey foreign key (repondant_id)
      references joueurs on delete set null on update cascade;

alter table tours           drop constraint tours_questionneur_id_fkey,
  add constraint tours_questionneur_id_fkey foreign key (questionneur_id)
      references joueurs on delete set null on update cascade;

alter table passages_finale drop constraint passages_finale_joueur_id_fkey,
  add constraint passages_finale_joueur_id_fkey foreign key (joueur_id)
      references joueurs on delete set null on update cascade;

alter table passages_finale drop constraint passages_finale_questionneur_id_fkey,
  add constraint passages_finale_questionneur_id_fkey foreign key (questionneur_id)
      references joueurs on delete set null on update cascade;

-- -------------------------------------------------------------
-- 4. Les deux fonctions qui touchaient au PIN.
-- -------------------------------------------------------------
create or replace function rpc_rejoindre(p_code text, p_prenom text)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  p parties;
  j joueurs;
  v_pin text;
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
    select pin into v_pin from sieges where joueur_id = j.id;
    return jsonb_build_object('partie_id', p.id, 'joueur_id', j.id, 'prenom', j.prenom,
                              'pin', v_pin, 'etat', p.etat, 'reprise', true);
  end if;

  if p.etat <> 'lobby' then raise exception 'la partie a déjà commencé'; end if;
  if (select count(*) from joueurs where partie_id = p.id) >= 12 then
    raise exception 'partie complète';
  end if;

  insert into joueurs (id, partie_id, prenom) values (auth.uid(), p.id, v_prenom)
  returning * into j;
  v_pin := tirer_pin();
  insert into sieges (joueur_id, pin) values (j.id, v_pin);

  update parties set hote_id = coalesce(hote_id, j.id) where id = p.id;

  return jsonb_build_object('partie_id', p.id, 'joueur_id', j.id, 'prenom', j.prenom,
                            'pin', v_pin, 'etat', p.etat, 'reprise', false);
exception when unique_violation then
  raise exception 'ce prénom est déjà pris dans la partie';
end $$;

create or replace function rpc_reprendre_siege(p_code text, p_prenom text, p_pin text)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare p parties; j joueurs; v_pin text;
begin
  if auth.uid() is null then raise exception 'session requise'; end if;
  select * into p from parties where code = upper(btrim(p_code)) and expire_le > now();
  if p.id is null then raise exception 'aucune partie avec ce code'; end if;

  select * into j from joueurs
  where partie_id = p.id and lower(prenom) = lower(btrim(p_prenom));
  if j.id is null then raise exception 'ce prénom n''est pas dans la partie'; end if;

  select pin into v_pin from sieges where joueur_id = j.id;
  if v_pin is distinct from btrim(p_pin) then
    raise exception 'code de reprise incorrect';
  end if;
  if j.id = auth.uid() then
    return jsonb_build_object('partie_id', p.id, 'joueur_id', j.id,
                              'prenom', j.prenom, 'etat', p.etat, 'deja', true);
  end if;
  -- on ne vole pas le siège de quelqu'un qui joue à côté de soi
  if j.vu_le > now() - interval '30 seconds' then
    raise exception 'ce joueur est encore connecté';
  end if;

  update parties set presentateur_id = auth.uid() where presentateur_id = j.id;
  update parties set hote_id         = auth.uid() where hote_id         = j.id;
  -- les clés étrangères suivent grâce au ON UPDATE CASCADE ci-dessus :
  -- réponses de préparation, votes, tours et passages de finale restent
  -- rattachés au joueur.
  update joueurs set id = auth.uid(), vu_le = now(), reprise_le = now() where id = j.id;

  return jsonb_build_object('partie_id', p.id, 'joueur_id', auth.uid(),
                            'prenom', j.prenom, 'etat', p.etat, 'reprise', true);
end $$;

do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p
           join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('rpc_rejoindre','rpc_reprendre_siege')
  loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
