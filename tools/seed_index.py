#!/usr/bin/env python3
"""Génère supabase/seed_questions_index.sql depuis questions.json.

Seuls les identifiants partent en base : le texte des questions reste
dans le bundle de l'app (ARCHITECTURE.md §3.e). La base n'a besoin que
de quoi faire un TIRAGE équitable côté serveur.

À relancer après toute modification de questions.json.
"""
import json, pathlib

racine = pathlib.Path(__file__).resolve().parent.parent
d = json.loads((racine / "questions.json").read_text(encoding="utf-8"))
lignes = []

def ajoute(qid, kind, modes, occasion=None, sensible=False, paire=None, slot=None, theme=None):
    lignes.append((qid, paire, slot, theme, kind, modes, occasion, bool(sensible)))

for cle, kind in (("paires_ouvertes", "ouverte"), ("paires_qcm", "qcm")):
    for p in d[cle]:
        for slot in ("a", "b"):
            ajoute(f"{p['id']}.{slot}", kind, p["modes"], p.get("occasion"),
                   p.get("sensible", False), paire=p["id"], slot=slot, theme=p["theme"])

for b in d["bonus"]:
    ajoute(b["id"], "bonus", b["modes"], b.get("occasion"), b.get("sensible", False))

for s in d["series_finale"]:
    ajoute(s["id"], "serie_finale", s["modes"], s.get("occasion"), s.get("sensible", False),
           theme=s["id"])
    for i in range(1, len(s["questions"]) + 1):
        ajoute(f"{s['id']}.{i}", "finale", s["modes"], s.get("occasion"),
               s.get("sensible", False), paire=s["id"], theme=s["id"])

for c in d["citez_trois"]:
    ajoute(c["id"], "citez3", c["modes"], c.get("occasion"), c.get("sensible", False))

def sql(v):
    if v is None: return "null"
    if isinstance(v, bool): return "true" if v else "false"
    if isinstance(v, list):
        return "array[" + ",".join("'" + x.replace("'", "''") + "'" for x in v) + "]::text[]"
    return "'" + str(v).replace("'", "''") + "'"

sortie = [
    "-- GÉNÉRÉ par tools/seed_index.py depuis questions.json — ne pas éditer à la main.",
    f"-- {len(lignes)} entrées, banque version {d['version']}.",
    "",
    "truncate questions_index;",
    "insert into questions_index (id, paire, slot, theme, kind, modes, occasion, sensible) values",
]
sortie.append(",\n".join("  (" + ", ".join(sql(c) for c in l) + ")" for l in lignes) + ";")

cible = racine / "supabase" / "seed_questions_index.sql"
cible.write_text("\n".join(sortie) + "\n", encoding="utf-8")

from collections import Counter
print(f"{len(lignes)} entrées -> {cible.relative_to(racine)}")
for k, n in sorted(Counter(l[4] for l in lignes).items()):
    print(f"  {k:14s} {n}")
