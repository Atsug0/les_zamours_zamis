#!/usr/bin/env python3
"""Récupère et auto-héberge les polices de la DA.

Aucun CDN : l'app doit tourner sur le wifi d'un salon, et la direction
artistique ne doit pas dépendre d'un tiers. On ne garde que le
sous-ensemble latin — le reste est du poids mort pour un jeu français.

    cd app && python3 tools/polices.py

Régénère public/polices/*.woff2 et src/styles/polices.css.
"""
import hashlib, pathlib, re, urllib.request

AGENT = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
         "(KHTML, like Gecko) Chrome/120 Safari/537.36")   # sinon Google sert du woff, plus lourd
FAMILLES = [("Bangers", "400", False), ("Archivo", "400;700", True)]

racine = pathlib.Path(__file__).resolve().parent.parent
dossier = racine / "public" / "polices"
dossier.mkdir(parents=True, exist_ok=True)
for ancien in dossier.glob("*.woff2"):
    ancien.unlink()

blocs = []
for nom, poids, variable in FAMILLES:
    req = urllib.request.Request(
        f"https://fonts.googleapis.com/css2?family={nom}:wght@{poids}&display=swap",
        headers={"User-Agent": AGENT})
    css = urllib.request.urlopen(req).read().decode("utf-8")

    vus = {}
    for sous, corps in re.findall(r"/\*\s*([\w-]+)\s*\*/\s*(@font-face\s*\{[^}]+\})", css):
        if sous != "latin":
            continue
        url = re.search(r"url\((https://[^)]+)\)", corps).group(1)
        octets = urllib.request.urlopen(url).read()
        somme = hashlib.md5(octets).hexdigest()
        if somme in vus:          # police variable : un seul fichier pour toutes les graisses
            continue
        vus[somme] = True
        cible = dossier / f"{nom.lower()}.woff2"
        cible.write_bytes(octets)
        corps = re.sub(r"url\(https://[^)]+\)", f"url(/polices/{cible.name})", corps)
        if variable:
            corps = re.sub(r"font-weight:\s*\d+;", "font-weight: 100 900;", corps)
        blocs.append(corps.strip())
        print(f"  {cible.name:18s} {len(octets)/1024:5.1f} Ko")

entete = """/* ============================================================
   Polices auto-hébergées. Aucun CDN : l'app doit tourner sur le
   wifi d'un salon, et la DA ne doit pas dépendre d'un tiers.
   Sous-ensemble latin uniquement — le reste est du poids mort ici.

   Bangers (OFL) : le lettrage de couverture comics, une seule graisse.
   Archivo (OFL) : le grotesque du corps, police variable 100-900.
   Les chiffres restent en monospace système : aucune police à
   charger pour des scores et des chronos.

   GÉNÉRÉ par tools/polices.py — ne pas éditer à la main.
   ============================================================ */

"""
(racine / "src" / "styles" / "polices.css").write_text(entete + "\n\n".join(blocs) + "\n",
                                                       encoding="utf-8")
total = sum(f.stat().st_size for f in dossier.glob("*.woff2"))
print(f"total : {total/1024:.1f} Ko")

# Garde-fou : une url() qui ne résout pas fait silencieusement retomber
# la page sur Impact, et la DA validée disparaît sans erreur.
import sys
css = (racine / "src" / "styles" / "polices.css").read_text(encoding="utf-8")
manquants = [u for u in re.findall(r"url\(/polices/([^)]+)\)", css)
             if not (dossier / u).exists()]
if manquants:
    print("ÉCHEC : fichiers de police introuvables ->", manquants)
    sys.exit(1)
print("✓ toutes les url() résolvent")
