-- =============================================================
-- 0014 — Rendre visible le choix en attente du partenaire
--
-- Un binôme doit s'accorder sur le mode, les catégories sensibles
-- ET les blocs d'occasion, à l'identique. Or v_joueurs n'exposait
-- qu'un booléen « a choisi » : impossible de savoir SUR QUOI
-- s'aligner. On devine, on se trompe, le binôme ne se verrouille
-- jamais et personne ne comprend pourquoi.
--
-- Ces valeurs ne sont pas secrètes : les deux doivent de toute
-- façon tomber d'accord dessus.
-- =============================================================

drop view if exists v_joueurs;
create view v_joueurs as
  select j.id, j.partie_id, j.prenom, j.binome_id, j.role, j.vu_le,
         (j.vu_le > now() - interval '30 seconds') as present,
         (j.mode_choisi is not null)               as a_choisi_mode,
         j.prepa_faites,
         j.mode_choisi, j.sensibles_choisi, j.occasions_choisies
  from joueurs j
  where est_membre(j.partie_id);

grant select on v_joueurs to anon, authenticated;
