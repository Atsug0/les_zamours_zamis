-- =============================================================
-- 0002 — RLS, vues publiques, droits
-- Principe (ARCHITECTURE.md §3.a et §3.b) :
--   * aucune écriture directe depuis le client, jamais ;
--   * les colonnes secrètes ne sortent que par une vue filtrée
--     ou par une fonction, une fois la phase atteinte.
-- =============================================================

alter table parties          enable row level security;
alter table binomes          enable row level security;
alter table joueurs          enable row level security;
alter table reponses_prepa   enable row level security;
alter table tours            enable row level security;
alter table votes            enable row level security;
alter table passages_finale  enable row level security;
alter table questions_index  enable row level security;

-- Aucun INSERT / UPDATE / DELETE pour les rôles de l'API : tout
-- passe par les fonctions SECURITY DEFINER.
revoke all on table parties, binomes, joueurs, reponses_prepa,
                    tours, votes, passages_finale, questions_index
  from anon, authenticated;

-- ---- Lecture directe : seulement ce qui est public par nature ----
grant select on table parties, binomes, joueurs to anon, authenticated;

create policy lire_partie on parties for select
  using (est_membre(id));

create policy lire_binomes on binomes for select
  using (est_membre(partie_id));

-- Les prénoms, couleurs et binômes des autres sont publics dans la
-- partie. Le PIN et le choix de mode en attente ne le sont pas :
-- ils sont retirés par la vue v_joueurs ci-dessous, et la table
-- n'est lisible que par son propriétaire.
create policy lire_moi on joueurs for select
  using (id = auth.uid());

-- reponses_prepa, votes : AUCUNE politique. RLS activé = refus total.
-- Seules les fonctions SECURITY DEFINER y accèdent.

-- =============================================================
-- Vues publiques. security_invoker reste à false : la vue tourne
-- avec les droits de son propriétaire et contourne donc le RLS
-- des tables sous-jacentes — c'est voulu, le filtre est DANS la
-- vue, colonne par colonne.
-- =============================================================

create view v_joueurs as
  select j.id, j.partie_id, j.prenom, j.binome_id, j.role,
         j.vu_le,
         (j.vu_le > now() - interval '30 seconds') as present,
         (j.mode_choisi is not null)              as a_choisi_mode
  from joueurs j
  where est_membre(j.partie_id);

create view v_tours as
  select t.id, t.partie_id, t.ordre, t.manche, t.binome_id,
         t.question_id, t.repondant_id, t.questionneur_id,
         t.statut, t.vote_fin_at, t.verdict, t.points,
         t.reponse_donnee,
         -- la réponse enregistrée n'existe pour le client qu'une fois révélée
         case when t.statut in ('revele','vote','juge')
              then t.reponse_revelee end as reponse_revelee,
         -- le décompte des votes ne sort qu'après le verdict (§6)
         case when t.statut = 'juge'
              then (select count(*) from votes v where v.tour_id = t.id and v.pour) end as voix_pour,
         case when t.statut = 'juge'
              then (select count(*) from votes v where v.tour_id = t.id and not v.pour) end as voix_contre,
         -- en revanche, savoir SI on a voté n'est pas un secret
         exists (select 1 from votes v where v.tour_id = t.id and v.joueur_id = auth.uid()) as j_ai_vote
  from tours t
  where est_membre(t.partie_id);

create view v_passages_finale as
  select p.id, p.partie_id, p.binome_id, p.ordre, p.joueur_id,
         p.questionneur_id, p.serie_id, p.jugements,
         p.chrono_fin_at, p.chrono_restant_ms, p.seuil_atteint, p.points
  from passages_finale p
  where est_membre(p.partie_id);

grant select on v_joueurs, v_tours, v_passages_finale to anon, authenticated;
