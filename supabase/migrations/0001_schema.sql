-- =============================================================
-- 0001 — Schéma de base
-- Les Zamours Zamis. Voir ARCHITECTURE.md §4.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- Index des questions.
-- Le TEXTE des questions vit dans questions.json, embarqué dans
-- l'app (ARCHITECTURE.md §3.e). Seuls les identifiants arrivent
-- ici, pour que le TIRAGE soit fait par le serveur et donc
-- identique et non négociable pour tous les binômes d'un mode.
-- Peuplé par tools/seed_index.py.
-- -------------------------------------------------------------
create table questions_index (
  id       text primary key,              -- 'quo-01.a', 'bon-01', 'fin-quotidien', 'fin-quotidien.3'
  paire    text,                          -- 'quo-01' — null pour un bonus
  slot     char(1),                       -- 'a' | 'b' — null hors paires
  theme    text,                          -- sert à garantir un tirage sans thème répété
  kind     text not null check (kind in ('ouverte','qcm','bonus','serie_finale','finale','citez3')),
  modes    text[] not null,
  occasion text,
  sensible boolean not null default false
);
create index on questions_index (kind);
create index on questions_index (paire);
create index on questions_index (kind, theme);

-- -------------------------------------------------------------
-- Parties
-- -------------------------------------------------------------
create table parties (
  id              uuid primary key default gen_random_uuid(),
  code            char(4) not null unique,
  etat            text not null default 'lobby'
                  -- 'citez3' est ajouté par 0015 : rpc_suivant écrit « etat = manche »
                  check (etat in ('lobby','prep','qcm','libre','bonus','finale','palmares')),
  plateau_id      uuid not null,                  -- l'appareil qui tient la télé
  hote_id         uuid,                           -- premier joueur arrivé
  presentateur_id uuid,
  format          text not null default 'court' check (format in ('court','long')),
  reglages        jsonb not null default jsonb_build_object(
                    'questionsFinale', 5, 'seuilFinale', 3,
                    'chronoFinaleMs', 30000, 'fenetreVoteMs', 15000,
                    'fenetreBonusMs', 20000, 'toleranceNumerique', 0.10),
  tirage          jsonb not null default '{}'::jsonb,   -- {zamours:{ouvertes:[],qcm:[],bonus:'',finale:''}, zamis:{...}}
  tour_courant    uuid,
  en_pause        boolean not null default false,
  pause_motif     text,
  pause_depuis    timestamptz,
  cree_le         timestamptz not null default now(),
  expire_le       timestamptz not null default now() + interval '12 hours'
);
create index on parties (expire_le);

-- -------------------------------------------------------------
-- Binômes
-- -------------------------------------------------------------
create table binomes (
  id         uuid primary key default gen_random_uuid(),
  partie_id  uuid not null references parties on delete cascade,
  mode       text check (mode in ('zamours','zamis')),
  couleur    text not null check (couleur in ('rouge','jaune','bleu','vert','orange','violet')),
  score      int not null default 0,
  verrouille boolean not null default false,
  sensibles  boolean not null default false,
  occasions  text[] not null default '{}',
  pronostic  int,
  unique (partie_id, couleur)
);

-- -------------------------------------------------------------
-- Joueurs — l'id EST l'auth.uid() de la session anonyme
-- -------------------------------------------------------------
create table joueurs (
  id          uuid primary key,
  partie_id   uuid not null references parties on delete cascade,
  prenom      text not null,
  binome_id   uuid references binomes on delete set null,
  role        char(1) check (role in ('A','B')),
  pin         char(4) not null,             -- code de reprise de siège (§10.b)
  vu_le       timestamptz not null default now(),
  reprise_le  timestamptz,
  -- choix de mode en attente d'accord du partenaire
  mode_choisi       text check (mode_choisi in ('zamours','zamis')),
  sensibles_choisi  boolean not null default false,
  occasions_choisies text[] not null default '{}'
);
create unique index joueurs_prenom_unique on joueurs (partie_id, lower(prenom));
create index on joueurs (partie_id);
create index on joueurs (binome_id);

alter table parties
  add constraint parties_presentateur_fk
  foreign key (presentateur_id) references joueurs on delete set null;

-- -------------------------------------------------------------
-- Réponses de préparation — LE secret du jeu.
-- RLS deny-all. Jamais lue en SELECT direct, par personne.
-- -------------------------------------------------------------
create table reponses_prepa (
  joueur_id   uuid not null references joueurs on delete cascade,
  question_id text not null,
  valeur      text not null,
  passee      boolean not null default false,
  ecrit_le    timestamptz not null default now(),
  primary key (joueur_id, question_id)
);

-- -------------------------------------------------------------
-- Tours
-- -------------------------------------------------------------
create table tours (
  id              uuid primary key default gen_random_uuid(),
  partie_id       uuid not null references parties on delete cascade,
  ordre           int not null,
  manche          text not null check (manche in ('qcm','libre','bonus')),
  binome_id       uuid not null references binomes on delete cascade,
  question_id     text not null,
  repondant_id    uuid references joueurs on delete set null,   -- null en bonus : les deux répondent
  questionneur_id uuid references joueurs on delete set null,
  reponse_donnee  text,
  reponse_revelee text,            -- écrite AU MOMENT de la révélation, pas avant
  statut          text not null default 'attente'
                  check (statut in ('attente','consigne','revele','vote','juge')),
  vote_fin_at     timestamptz,
  vote_restant_ms int,             -- fenêtre gelée pendant une pause (§10.c)
  verdict         boolean,
  points          int not null default 0,
  unique (partie_id, ordre)
);
create index on tours (partie_id, manche, ordre);

-- -------------------------------------------------------------
-- Votes — insert-only, jamais lus par un client (§6)
-- -------------------------------------------------------------
create table votes (
  tour_id   uuid not null references tours on delete cascade,
  joueur_id uuid not null references joueurs on delete cascade,
  pour      boolean not null,
  vote_le   timestamptz not null default now(),
  primary key (tour_id, joueur_id)
);

-- -------------------------------------------------------------
-- Passages de finale
-- -------------------------------------------------------------
create table passages_finale (
  id                uuid primary key default gen_random_uuid(),
  partie_id         uuid not null references parties on delete cascade,
  binome_id         uuid not null references binomes on delete cascade,
  ordre             int not null,
  joueur_id         uuid references joueurs on delete set null,
  questionneur_id   uuid references joueurs on delete set null,
  serie_id          text,
  jugements         text[] not null default '{}',
  chrono_fin_at     timestamptz,
  chrono_restant_ms int,
  seuil_atteint     boolean,
  points            int not null default 0,
  unique (partie_id, ordre)
);

-- =============================================================
-- Helpers. SECURITY DEFINER : contournent RLS, donc jamais de
-- recursion de politique, et search_path figé contre le
-- détournement de schéma.
-- =============================================================

-- Membre = joueur de la partie, OU l'appareil qui tient le plateau.
create or replace function est_membre(p_partie uuid)
returns boolean language sql security definer stable
set search_path = public, pg_temp as $$
  select exists (select 1 from joueurs  j where j.partie_id = p_partie and j.id = auth.uid())
      or exists (select 1 from parties  p where p.id = p_partie and p.plateau_id = auth.uid());
$$;

create or replace function mon_joueur()
returns joueurs language sql security definer stable
set search_path = public, pg_temp as $$
  select * from joueurs where id = auth.uid() limit 1;
$$;

-- Le plateau, le présentateur et l'hôte peuvent faire avancer l'émission.
create or replace function peut_orchestrer(p_partie uuid)
returns boolean language sql security definer stable
set search_path = public, pg_temp as $$
  select exists (
    select 1 from parties p
    where p.id = p_partie
      and auth.uid() in (p.plateau_id, p.hote_id, p.presentateur_id)
  );
$$;

-- Code de partie : 4 lettres, alphabet sans I ni O (ni chiffre, donc
-- ni 0 ni 1). On doit pouvoir le crier à travers une pièce.
create or replace function tirer_code()
returns char(4) language plpgsql
set search_path = public, pg_temp as $$
declare
  alpha text := 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  essai char(4);
  i int;
begin
  for i in 1..200 loop
    essai := (select string_agg(substr(alpha, 1 + floor(random()*length(alpha))::int, 1), '')
              from generate_series(1,4));
    if not exists (select 1 from parties where code = essai and expire_le > now()) then
      return essai;
    end if;
  end loop;
  raise exception 'impossible de tirer un code libre';
end;
$$;

create or replace function tirer_pin()
returns char(4) language sql
set search_path = public, pg_temp as $$
  select lpad(floor(random()*10000)::text, 4, '0')::char(4);
$$;
