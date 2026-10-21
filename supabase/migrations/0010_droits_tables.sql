-- =============================================================
-- 0010 — Droits sur les tables ET LES VUES. À passer en dernier.
--
-- Supabase accorde par défaut TOUS les droits sur toute table du
-- schéma public à anon et authenticated. Les migrations précédentes
-- révoquaient une liste nommée de tables — mais les VUES sont créées
-- après, et sont donc restées écrivables.
--
-- Ce n'était pas théorique : v_joueurs, v_tours, v_recap et
-- v_passages_finale sont auto-modifiables au sens de Postgres, et une
-- vue non-security_invoker s'exécute avec les droits de son
-- PROPRIÉTAIRE. Écrire à travers elles contournait donc entièrement
-- les RLS :
--
--   update v_recap set points = 9999         -> falsifie les scores
--   update v_joueurs set binome_id = '...'   -> change de binôme
--   update v_tours set verdict = true        -> se valide soi-même
--
-- On repart donc de zéro sur TOUT le schéma, par motif et non par
-- liste nominative, puis on rouvre la seule lecture nécessaire.
-- =============================================================

-- 1. Table rase : plus aucun droit, sur aucune relation.
revoke all on all tables in schema public from anon, authenticated;

-- 2. Et pour tout ce qui sera créé plus tard, par nous.
alter default privileges in schema public revoke all on tables from anon, authenticated;

-- 3. Lecture seule, et seulement là où une politique RLS ou une vue
--    filtrante protège le contenu.
grant select on table parties  to anon, authenticated;   -- RLS : est_membre
grant select on table binomes  to anon, authenticated;   -- RLS : est_membre
grant select on table joueurs  to anon, authenticated;   -- RLS : sa propre ligne
grant select on v_joueurs, v_tours, v_passages_finale,
                v_progression, v_palmares, v_recap to anon, authenticated;

-- Volontairement absentes, et elles doivent le rester :
--   reponses_prepa  le secret du jeu
--   votes           secrets jusqu'au verdict
--   tours           lu via v_tours, qui masque la réponse non révélée
--   passages_finale lu via v_passages_finale
--   questions_index le client a déjà les textes dans son bundle

-- 4. Aucune séquence non plus : rien à incrémenter depuis le navigateur.
revoke all on all sequences in schema public from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
