#!/usr/bin/env python3
"""Garde-fous de la banque de questions. Échoue si une règle de la charte est violée."""
import json, re, sys
from collections import Counter

d = json.load(open("questions.json"))
err = []

# Vocabulaire qui présuppose un lien amoureux : interdit hors des paires zamours-only.
AMOUR = re.compile(r"\b(couple|mariage|mari[ée]|conjoint|amoureux|fianc|baiser|je t'aime|noces|c[ée]r[ée]monie|premier pas|t[ée]moin)\b", re.I)
# Formes genrées que le PDF d'origine utilisait partout.
GENRE = re.compile(r"il/elle|/elle\b|\(e\)\b|son/sa|ton/ta|le/la\b|heureux/heureuse|\bsa femme\b|\bson mari\b")

def textes(o):
    for k in ("prepa", "jeu", "enonce", "titre"):
        if k in o: yield k, o[k]
    for pr in o.get("props", []): yield "props", pr

def parcours():
    for pr in d["paires_ouvertes"] + d["paires_qcm"]:
        for side in ("a", "b"):
            yield pr, pr[side]
    for b in d["bonus"]: yield b, b
    for s in d["series_finale"]:
        for q in s["questions"]: yield s, q
    for c in d["citez_trois"]: yield c, c

for parent, item in parcours():
    pid, modes = parent["id"], parent.get("modes", [])
    for champ, txt in textes(item):
        if GENRE.search(txt):
            err.append(f"{pid}.{champ} : forme genrée -> {txt}")
        if "zamis" in modes and AMOUR.search(txt):
            err.append(f"{pid}.{champ} : vocabulaire de couple dans une question jouable en zamis -> {txt}")
        if len(txt) > 110:
            err.append(f"{pid}.{champ} : trop long pour un écran TV ({len(txt)} car.)")
        if re.search(r"\bça d[ée]pend\b", txt, re.I):
            err.append(f"{pid}.{champ} : réponse parapluie proposée -> {txt}")

for pr in d["paires_qcm"]:
    for side in ("a", "b"):
        if len(pr[side].get("props", [])) != 3:
            err.append(f"{pr['id']}.{side} : il faut exactement 3 propositions")

for pr in d["paires_ouvertes"] + d["paires_qcm"]:
    if pr["a"]["prepa"] == pr["b"]["prepa"]:
        err.append(f"{pr['id']} : les deux slots posent la même question")

ids = [o["id"] for o in d["paires_ouvertes"] + d["paires_qcm"] + d["bonus"] + d["series_finale"] + d["citez_trois"]]
for i, n in Counter(ids).items():
    if n > 1: err.append(f"id dupliqué : {i}")

for pr in d["paires_ouvertes"]:
    j = pr.get("jumeau")
    if j and not any(x["id"] == j for x in d["paires_ouvertes"]):
        err.append(f"{pr['id']} : jumeau introuvable ({j})")

# Un mode doit pouvoir tenir une partie sans puiser dans les blocs d'occasion.
for m in ("zamours", "zamis"):
    fonds = lambda xs: [x for x in xs if m in x.get("modes", []) and "occasion" not in x]
    o, q, s, b = (len(fonds(d["paires_ouvertes"])), len(fonds(d["paires_qcm"])),
                  len(fonds(d["series_finale"])), len(fonds(d["bonus"])))
    if o < 20: err.append(f"{m} : seulement {o} paires ouvertes au fonds commun (min 20)")
    if q < 8:  err.append(f"{m} : seulement {q} paires QCM au fonds commun (min 8)")
    if s < 3:  err.append(f"{m} : seulement {s} séries de finale (min 3)")
    if b < 5:  err.append(f"{m} : seulement {b} bonus (min 5)")
    print(f"{m:8s} fonds commun : {o} paires ouvertes, {q} paires QCM, {b} bonus, {s} séries de finale")

print()
if err:
    print(f"✗ {len(err)} problème(s) :")
    for e in err: print("  -", e)
    sys.exit(1)
print("✓ banque conforme à la charte")
