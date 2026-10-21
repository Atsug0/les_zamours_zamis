# Les Zamours Zamis

Un jeu de complicité **web + mobile**, librement inspiré des *Z'amours*. Deux écrans :
la télé fait le **plateau**, les téléphones font les **pupitres**.

**→ https://les-zamours-zamis.web.app**

Un binôme répond à des questions sur lui-même avant la partie ; pendant la partie,
chacun doit retrouver ce que son partenaire a répondu. On ne juge jamais si une réponse
est *vraie* — seulement si elle **correspond**.

Deux modes par binôme : **Zamours** (en couple) et **Zamis** (amis, colocs, famille).
Ce n'est pas une nuance de ton : le mode change le pool de questions.

---

## Où est quoi

| Document | Contenu |
|---|---|
| **[REGLES.md](REGLES.md)** | les règles du jeu, de bout en bout |
| **[ARCHITECTURE.md](ARCHITECTURE.md)** | comment la plateforme fonctionne, modèle de données, décisions |
| **[BANQUE.md](BANQUE.md)** | charte éditoriale des questions, et l'audit de la refonte |
| **[DEPLOIEMENT.md](DEPLOIEMENT.md)** | mise en ligne, de zéro à une partie jouable |
| **DA.html** | la direction artistique, à ouvrir dans un navigateur |

| Code | |
|---|---|
| `supabase/migrations/` | le schéma, les RLS, les 24 fonctions RPC |
| `supabase/test/` | 265 assertions, dont une partie complète jouée dans chacun des cinq modes |
| `app/` | le front React + Vite |
| `questions.json` | **la banque de questions — source unique** |
| `tools/db_prod.sh` | migrations et contrôles sur la base de production |
| `tokens.css` | **les jetons de la DA — source unique** |

Les deux fichiers marqués *source unique* sont copiés dans le bundle à la compilation.
Ne jamais éditer leurs copies dans `app/src/`.

---

## Ce qui tourne

**Le backend est complet.** Lobby, appariement, modes, tirage serveur, préparation,
manche QCM, manche libre avec vote, question bonus, finale chronométrée, palmarès, gel
des chronos sur déconnexion, reprise de siège par PIN.

**Le front est jouable de bout en bout** : accueil, lobby avec QR code, préparation,
manches QCM et libres, question bonus, finale chronométrée, palmarès et mort subite —
des deux côtés, télé et téléphone, avec l'orchestration par le plateau. Navigable à la
télécommande, en plein écran.

### Cinq façons de jouer

| Mode | Qui joue | Comment on juge |
|---|---|---|
| **Binômes** | 2 à 6 binômes, Zamours ou Zamis | les autres binômes votent à la majorité |
| **Tous contre le binôme** | idem, mais le public **parie** à chaque question | concordance calculée ; seul le présentateur peut corriger |
| **Duel** | exactement deux personnes | concordance calculée, contestation possible une fois |
| **Sujet** | une personne qu'on doit deviner, les autres s'affrontent | le sujet valide — c'est lui qui sait |
| **Tournoi** | 3 à 6 joueurs, chacun est le sujet à son tour | le sujet du moment valide |

Quelques conséquences de conception :

- ****Pour essayer seul**, l'accueil propose une **partie de démonstration** : elle est
peuplée de bots qui jouent leur part — y compris la préparation — pendant que tu joues
la tienne. Les bots empruntent exactement les mêmes fonctions qu'un humain, en endossant
leur identité le temps de l'action : une partie de démo est donc aussi un test
d'intégration qui se joue tout seul.

Le duel s'active de lui-même** : deux joueurs, un binôme, on lance. Et comme il n'y
  a plus aucun votant, la concordance y est calculée mécaniquement — celui qui n'est pas
  d'accord conteste une fois, et l'autre tranche.
- **Les modes sujet et tournoi n'ont aucune phase de préparation.** Le sujet répond en
  secret juste avant les autres, question par question : zéro temps mort, et sa réponse
  est verrouillée avant que quiconque réponde.
- **Dans le mode paris, le public ne juge pas.** On ne peut pas à la fois parier sur un
  résultat et le décider : qui a parié « ça va rater » aurait intérêt à refuser la
  réponse. Le verdict est donc mécanique, et seul le présentateur — qui ne parie pas —
  peut le corriger.

Polices auto-hébergées, format court ou long, catégories sensibles et bloc mariage,
variante « cite 3 », reprise du plateau depuis un téléphone. Le site est déployé sur
Firebase Hosting.

### Trois invariants, tenus par le serveur et non par le client

1. **Aucune écriture directe depuis le navigateur.** Toute transition passe par une
   fonction Postgres qui revérifie l'appelant, la phase et les délais.
2. **Les réponses de préparation ne descendent jamais dans le navigateur avant la
   révélation.** `reponses_prepa` n'a aucun droit de lecture, pour personne. Le secret
   des réponses *est* le jeu.
3. **Le temps vit en base.** Les chronos et fenêtres de vote sont validés côté serveur,
   et se **gèlent** si le joueur attendu se déconnecte : personne ne perd de points à
   cause du wifi.

---

## Développer

```bash
# base de test jetable : monte un Postgres, applique tout, joue les 124 assertions
./tools/db_local.sh --reset

# le front
cd app
cp .env.example .env.local      # puis remplir avec l'URL et la clé anon Supabase
npm install
npm run dev
```

Ouvrir ensuite deux fenêtres : `localhost:5173/tv/CODE` d'un côté,
`localhost:5173/p/CODE` de l'autre.

### Vérifier avant de pousser

```bash
python3 lint_questions.py       # refuse une question genrée ou non concordable
./tools/db_local.sh             # 265 assertions SQL
node tools/fumee.mjs            # une vraie partie sur le vrai projet, par HTTP
node tools/fumee-realtime.mjs   # le temps réel arrive-t-il vraiment au client ?
cd app
npm run build                   # types stricts + les QR se décodent vraiment
npm run mise-en-page            # aucune page ne déborde, de 320 à 1920 px
npm run demo                    # une partie de démo dans un vrai navigateur
```

Les trois derniers tournent dans un navigateur sans tête. Ils existent parce que trois
bugs sont passés à travers tout le reste : des champs qui sortaient du cadre, du jaune
illisible sur blanc, et une partie gelée parce que les bots n'envoient pas de pouls —
aucun n'était visible dans un typage ni dans une assertion SQL.

Le build **échoue** si un QR code ne se décode pas : on le vérifie en le redécodant
avec un décodeur indépendant de l'encodeur, parce qu'un QR cassé est invisible à l'œil.

### Après avoir modifié `questions.json`

```bash
python3 lint_questions.py
python3 tools/seed_index.py                     # régénère l'index SQL
# puis rejouer supabase/seed_questions_index.sql sur la base
```

L'index en base et les textes du bundle doivent être régénérés **ensemble**, sinon le
serveur tire un identifiant dont le client n'a pas le texte.

---

## Coût

Zéro, hors nom de domaine : Supabase gratuit + hébergement statique gratuit. Les deux
pièges à connaître sont dans [DEPLOIEMENT.md](DEPLOIEMENT.md) — un projet Supabase
inactif 7 jours est **suspendu**, et la connexion anonyme est **désactivée par défaut**.

---

## Crédits

La direction artistique reprend celle du jeu télé, dont le décor était explicitement
inspiré de **Roy Lichtenstein** : pop art, canapés rouge, jaune et bleu, et un cœur
géant au sol.

La banque de questions part d'un questionnaire de 340 questions de
[idees-de-jeux.fr](https://www.idees-de-jeux.fr/animations/questionnaire-les-zamours),
entièrement réécrit : plus aucun pronom de genre, un prénom injecté à la place, et un
tri par mode pour qu'une question qui présuppose un couple ne soit jamais posée à deux
amis. Le détail est dans [BANQUE.md](BANQUE.md).
