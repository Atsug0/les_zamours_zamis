# Les Zamours Zamis — comment le site fonctionne

Résumé fonctionnel et technique du produit. React + Supabase, hébergement statique,
**coût courant : 0 €**. Les trois pièges du gratuit sont traités au §8 — le premier est
sérieux et n'a rien à voir avec les quotas.

Documents liés : `REGLES.md` (règles du jeu), `questions.json` + `BANQUE.md` (contenu),
`DA.html` + `tokens.css` (direction artistique).

---

## 1. Le principe en une page

Un seul site, **deux écrans, trois rôles**.

```
        ┌──────────────────────────────────────────────┐
        │  LE PLATEAU   ·   le site ouvert sur la télé │
        │  grande question, scores, chrono, révélation │
        │  → c'est aussi L'HORLOGE de la partie        │
        └───────────────────┬──────────────────────────┘
                            │  Supabase
        ┌───────────────────┴──────────────────────────┐
        │                                              │
   ┌────┴─────┐  ┌──────────┐  ┌──────────┐  ┌────────┴───┐
   │ Téléphone│  │ Téléphone│  │ Téléphone│  │ Téléphone  │
   │  joueur  │  │  joueur  │  │  joueur  │  │ questionneur│
   └──────────┘  └──────────┘  └──────────┘  └────────────┘
```

**La base de données est la seule source de vérité.** Aucun écran ne détient d'état de
jeu : chaque appareil affiche une projection de la ligne `parties` et se resynchronise
tout seul après un rafraîchissement, une perte de réseau ou un téléphone à plat.

**Rien ne s'écrit directement depuis le client.** Toute transition passe par une
fonction Postgres qui valide avant d'écrire. C'est la décision qui protège le jeu : le
secret des réponses *est* le jeu, un joueur qui ouvre les devtools ne doit rien y
trouver.

---

## 2. Le parcours complet d'une partie

### Étape 1 — Ouvrir le plateau (30 s)
Quelqu'un ouvre le site sur la télé — Chromecast, HDMI, ou simplement un laptop posé
devant le canapé. Un bouton : **« Nouvelle partie »**.

L'appareil appelle `rpc_creer_partie()` et devient le **plateau**. L'écran affiche en
grand un **code à 4 lettres** et un **QR code** généré sur l'appareil (pas d'appel à un
service d'images, le QR est dessiné en SVG par une lib embarquée).

Le code est tiré dans un alphabet sans ambiguïté — **pas de I, O, 0, 1** — pour qu'on
puisse le crier à travers une pièce. Collision vérifiée en base, durée de vie 6 heures.

### Étape 2 — Les joueurs rejoignent
Chacun scanne, ou tape le code sur `leszamours.app`. Un seul champ : **son prénom**.
L'app crée une session anonyme Supabase, stocke le jeton en `localStorage`, et appelle
`rpc_rejoindre(code, prenom)`.

Sur la télé, les prénoms tombent un par un dans des pastilles — c'est le premier moment
où le groupe voit que ça marche.

### Étape 3 — Se mettre en binôme
Chaque téléphone affiche la liste des joueurs non appariés. On touche un nom, l'autre
reçoit l'invitation et accepte. `rpc_apparier(cible_id)` verrouille le binôme et lui
attribue **la prochaine couleur de canapé libre** (rouge, puis jaune, puis bleu, puis
les extensions — voir la DA).

**Nombre impair** : le joueur qui reste voit apparaître un bouton
**« Je présente »**. Il devient présentateur, ne marque pas de points, et récupère les
commandes d'arbitrage. S'il refuse, la partie refuse de démarrer — on ne joue pas à
sept.

### Étape 4 — Choisir le mode, par binôme
Les deux membres choisissent **Zamours** ou **Zamis**. Tant qu'ils ne sont pas d'accord,
le binôme reste en attente — c'est volontaire, le mode change le pool de questions et
doit être un accord explicite. Un panneau optionnel permet d'activer les
**catégories sensibles** et les **blocs d'occasion** (le mariage), à l'unanimité du
binôme.

### Étape 5 — Le tirage
L'hôte lance la partie. `rpc_lancer()` tire, **pour chaque mode présent dans la salle**,
2 paires ouvertes + 1 paire QCM + 1 bonus + 1 série de finale en format court (3 et 2 en
format long, règles §12.2), en respectant les filtres
(mode, occasions actives, sensible) et **sert le même tirage à tous les binômes du même
mode** — c'est ce qui rend le vote des autres équitable (règles §3.1).

Seuls les **identifiants** des questions partent en base. La banque elle-même est
embarquée dans l'app : elle n'est pas secrète, et ça économise la base et l'egress.

### Étape 6 — La préparation (3 min)
Tout le monde répond en même temps, **chacun sur son téléphone**, 9 questions sur
soi-même. La télé n'affiche qu'une barre de progression anonyme : *« 5 joueurs sur 8 ont
terminé »*. Aucun contenu, jamais.

C'est le seul moment mort de la soirée. Il est volontairement court, et la télé affiche
pendant ce temps les règles du vote — les gens les lisent parce qu'ils attendent.

### Étape 7 — Les manches
Pour chaque tour, le plateau orchestre une séquence de six temps :

| Temps | Télé | Téléphones |
|---|---|---|
| Annonce | binôme appelé, qui répond sur qui | écran neutre |
| Question | énoncé en grand, prénom injecté | le questionneur voit l'énoncé + le champ de consignation |
| Réponse | — | **le joueur répond à voix haute** (§4.1 des règles) |
| Consignation | — | le questionneur tape 2-3 mots, puis **Révéler** |
| Révélation | les deux réponses en deux cases, séparées d'un `=` ou `≠` | — |
| Vote | décompte masqué, puis verdict | ✅ / ❌ chez les votants, écran neutre chez le binôme concerné |

Ordre des manches : **QCM** (validation automatique, pas de vote) → **libre** (vote) →
**bonus** (révélation simultanée des deux membres).

### Étape 8 — La finale
Chaque binôme passe, du dernier au premier au classement. Le binôme désigne lequel des
deux joue. Le questionneur lit les 5 questions à voix haute et tranche ✓ / ✗ / passer
pendant que la télé affiche un chrono géant de **30 secondes** et la file des 5
pastilles.

C'est le seul moment où le questionneur voit la réponse attendue : il n'y a pas de vote,
il arbitre seul.

### Étape 9 — Palmarès
Scores cumulés, binôme gagnant, et un **récap des meilleures réponses de la soirée** —
construit à partir des consignations du questionneur. C'est pour ça qu'on consigne 2-3
mots plutôt que rien : ça ne sert pas à arbitrer, ça sert à finir la soirée.

---

## 3. Les cinq décisions d'architecture

### a. Le serveur est la seule autorité
Toute transition d'état est une **fonction Postgres `SECURITY DEFINER`** appelée en RPC.
Le client n'a **aucun droit d'écriture direct** sur les tables de jeu. Chaque fonction
revérifie : l'appelant est-il dans cette partie ? a-t-il le rôle requis ? la partie est-elle
dans la bonne phase ? le délai est-il écoulé ?

Sans ça, n'importe qui s'attribue 100 points depuis la console du navigateur.

### b. Les réponses de préparation ne descendent jamais dans le navigateur
C'est **la** contrainte du produit. Le secret des réponses est le jeu lui-même.

- `reponses_prepa` est en **RLS deny-all**. Personne ne la lit, même pas son auteur,
  en SELECT direct.
- Un joueur relit ses propres réponses via `rpc_mes_reponses()`.
- La réponse attendue n'est renvoyée que par `rpc_reveler(tour_id)`, qui **écrit d'abord
  la révélation en base** puis la renvoie. Le serveur ne divulgue donc que ce qui est
  déjà public pour toute la salle.
- En finale, `rpc_demarrer_passage()` renvoie les 5 réponses attendues **au seul
  questionneur du passage**, et seulement une fois le chrono démarré.

### c. Le temps vit en base, jamais dans le client
Les chronos et fenêtres de vote sont stockés en `fin_at timestamptz`. Les clients
affichent `fin_at - now()` et n'ont **aucune autorité** : une consignation arrivée après
`fin_at` est rejetée par la fonction, quelle que soit l'horloge du téléphone.

### d. Pas de tâche planifiée : la télé est l'horloge
Supabase gratuit n'offre pas de job fiable, et un cron pour fermer les fenêtres de vote
serait une dépense d'architecture pour rien. À la place : **le plateau appelle les RPC de
clôture** quand son compte à rebours tombe à zéro, et la base **refuse si le délai n'est
pas réellement écoulé**.

Le plateau ne décide rien, il déclenche. S'il se déconnecte, le présentateur ou l'hôte
peut déclencher la même transition — l'état n'est jamais bloqué dans un seul appareil.

### e. Tout le schéma public est une API, qu'on le veuille ou non
Deux pièges jumeaux, et les deux ont été des trous réels.

**Les fonctions.** PostgREST publie **comme endpoint REST** chaque fonction de `public`
exécutable par `anon` ou `authenticated`. Ce n'est pas une option : c'est le fonctionnement normal de
Supabase, et ça transforme le moindre helper oublié en porte d'entrée.

`0009_droits.sql` est donc la source unique de vérité sur les droits : elle révoque
tout, puis rouvre les `rpc_*` à `authenticated`, `ping()` à `anon`, et **rien d'autre
en dehors d'une liste blanche de deux fonctions** — `est_membre`, appelée dans les
politiques RLS, et `nb_questions_prepa`, appelée dans une vue. Les deux sont des
nécessités techniques, pas des choix :

- une **politique RLS** s'évalue avec les droits du rôle *appelant* ;
- dans une **vue** non-`security_invoker`, Postgres vérifie l'accès aux *tables* avec
  les droits du propriétaire, mais l'exécution des *fonctions* avec ceux de l'appelant.

**Les tables, et surtout les vues.** Supabase accorde par défaut **tous** les droits sur
toute table de `public` à `anon` et `authenticated`. Révoquer une liste *nommée* ne
suffit pas : les **vues** sont créées après, et une vue non-`security_invoker` s'exécute
avec les droits de son **propriétaire**. Y écrire contourne donc les RLS entièrement —
`update v_recap set points = 9999` falsifiait les scores, et `update v_joueurs set
binome_id = …` changeait de binôme. `0010_droits_tables.sql` révoque donc **par motif**
(`all tables in schema public`), ajuste aussi les *default privileges* pour les objets
futurs, puis rouvre la seule lecture nécessaire.

`supabase/test/05_droits.sql` échoue si quoi que ce soit sort de ces listes. Les deux
tests existent parce que les deux trous étaient réels, et exploitables en une requête.

> Le second n'avait pas été vu en local, parce qu'un Postgres nu n'a pas les *default
> privileges* permissifs de Supabase. `supabase/test/00_shim.sql` les reproduit
> maintenant : un environnement de test qui est plus sûr que la production ne teste
> rien.

### f. La banque de questions est dans le bundle, pas en base
`questions.json` (~70 Ko) est importé par l'app. La base ne stocke que des identifiants.
Conséquences : la base reste minuscule, le contenu se versionne avec le code, et le
workflow `lint_questions.py` continue de marcher. Les questions n'ont aucun besoin
d'être secrètes — **les réponses, oui.**

---

## 4. Modèle de données

```sql
-- une partie = une ligne, c'est l'objet que tous les écrans observent
create table parties (
  id            uuid primary key default gen_random_uuid(),
  code          char(4) unique not null,          -- alphabet sans I O 0 1
  etat          text not null default 'lobby',     -- lobby|prep|qcm|libre|bonus|finale|palmares
  plateau_id    uuid,                              -- l'appareil qui tient la télé
  hote_id       uuid not null,
  presentateur_id uuid,                            -- null si effectif pair
  format        text not null default 'court',     -- court|long
  reglages      jsonb not null default '{}',       -- seuils, chronos, fenêtre de vote
  tirage        jsonb not null default '{}',       -- {zamours:[ids...], zamis:[ids...]}
  tour_courant  uuid,
  en_pause      boolean not null default false,     -- gelée : un joueur attendu est absent
  pause_depuis  timestamptz,
  cree_le       timestamptz default now(),
  expire_le     timestamptz default now() + interval '12 hours'
);

create table joueurs (
  id         uuid primary key,                     -- = auth.uid() de la session anonyme
  partie_id  uuid not null references parties on delete cascade,
  prenom     text not null,
  binome_id  uuid,
  role       char(1),                              -- 'A' | 'B'
  vu_le      timestamptz default now(),            -- pouls, rafraîchi toutes les 10 s
  pin        char(4) not null,                     -- code de reprise, montré une fois
  reprise_le timestamptz                           -- dernière reprise de siège
);

create table binomes (
  id          uuid primary key default gen_random_uuid(),
  partie_id   uuid not null references parties on delete cascade,
  mode        text not null,                       -- zamours | zamis
  couleur     text not null,                       -- rouge|jaune|bleu|vert|orange|violet
  score       int not null default 0,
  verrouille  boolean default false,
  sensibles   boolean default false,
  occasions   text[] default '{}',                 -- ['mariage']
  pronostic   int
);

-- RLS DENY ALL. Lue uniquement par les fonctions SECURITY DEFINER.
create table reponses_prepa (
  joueur_id   uuid not null references joueurs on delete cascade,
  question_id text not null,                       -- id dans questions.json
  valeur      text not null,
  passee      boolean default false,
  primary key (joueur_id, question_id)
);

create table tours (
  id             uuid primary key default gen_random_uuid(),
  partie_id      uuid not null references parties on delete cascade,
  ordre          int not null,
  manche         text not null,                    -- qcm|libre|bonus
  binome_id      uuid not null references binomes,
  question_id    text not null,
  repondant_id   uuid not null references joueurs, -- celui qui devine
  questionneur_id uuid not null references joueurs,
  reponse_donnee text,                             -- consignée, 2-3 mots
  reponse_revelee text,                            -- écrite AU MOMENT de la révélation
  statut         text not null default 'attente',  -- attente|consigne|revele|vote|juge
  vote_fin_at    timestamptz,
  vote_restant_ms int,                             -- fenêtre gelée pendant une pause
  verdict        boolean,
  points         int default 0
);

-- insert-only : les votes restent secrets jusqu'au verdict (règle du jeu ET économie
-- de messages realtime, voir §6)
create table votes (
  tour_id   uuid not null references tours on delete cascade,
  joueur_id uuid not null references joueurs on delete cascade,
  pour      boolean not null,
  primary key (tour_id, joueur_id)
);

create table passages_finale (
  id             uuid primary key default gen_random_uuid(),
  partie_id      uuid not null references parties on delete cascade,
  binome_id      uuid not null references binomes,
  joueur_id      uuid not null references joueurs,
  questionneur_id uuid not null references joueurs,
  serie_id       text not null,
  jugements      text[] not null default '{}',     -- juste|faux|passee
  chrono_fin_at  timestamptz,
  chrono_restant_ms int,                           -- chrono gelé pendant une pause
  seuil_atteint  boolean,
  points         int default 0
);
```

### Politiques RLS en une phrase chacune

| Table | Lecture | Écriture |
|---|---|---|
| `parties` | les joueurs de la partie | **aucune** — RPC uniquement |
| `joueurs` | les joueurs de la même partie (prénom, binôme, couleur) | aucune |
| `binomes` | idem | aucune |
| `reponses_prepa` | **personne** | aucune |
| `tours` | les joueurs de la partie, **sauf `reponse_revelee` tant que `statut <> 'revele'`** (via vue) | aucune |
| `votes` | **personne** | aucune |
| `passages_finale` | les joueurs de la partie, sans les réponses attendues | aucune |

Les clients lisent à travers des **vues** qui excluent les colonnes secrètes. Ça évite
de faire confiance au `select()` du client.

---

## 5. Les fonctions RPC — l'API du jeu

| Fonction | Appelée par | Ce qu'elle valide |
|---|---|---|
| `rpc_creer_partie()` | la télé | rien ; renvoie code + id, pose `plateau_id` |
| `rpc_rejoindre(code, prenom)` | un téléphone | partie en `lobby`, non expirée, prénom libre |
| `rpc_apparier(cible_id)` | un joueur | les deux libres, même partie |
| `rpc_choisir_mode(mode, sensibles, occasions)` | un joueur | accord des deux membres avant verrouillage |
| `rpc_devenir_presentateur()` | un joueur | effectif impair, place libre |
| `rpc_lancer(format)` | l'hôte | tous les binômes verrouillés, effectif pair hors présentateur |
| `rpc_repondre_prepa(question_id, valeur)` | un joueur | phase `prep`, question bien dans **son** set |
| `rpc_consigner(tour_id, valeur)` | le questionneur du tour | rôle, phase, `statut = 'attente'`, pas son binôme |
| `rpc_reveler(tour_id)` | le questionneur | écrit `reponse_revelee`, ouvre `vote_fin_at`, **puis** renvoie |
| `rpc_voter(tour_id, pour)` | un votant | hors du binôme, `now() < vote_fin_at`, un seul vote |
| `rpc_clore_vote(tour_id)` | la télé ou le présentateur | **`now() >= vote_fin_at`**, calcule la majorité et les points |
| `rpc_arbitrer(tour_id, pour)` | le présentateur | uniquement en cas d'égalité des voix |
| `rpc_demarrer_passage(binome_id, joueur_id)` | le questionneur | pose `chrono_fin_at`, renvoie les 5 réponses attendues **à lui seul** |
| `rpc_juger(passage_id, index, jugement)` | le questionneur | `now() < chrono_fin_at` |
| `rpc_clore_passage(passage_id)` | la télé | chrono écoulé ou 5 jugements, calcule seuil + points |
| `rpc_suivant()` | la télé, le présentateur ou l'hôte | fait avancer la machine à états |
| `rpc_pouls()` | tous les écrans, toutes les 10 s | rafraîchit `vu_le`, sort de pause si l'attendu revient |
| `rpc_reprendre_siege(code, prenom, pin)` | un téléphone qui a perdu sa session | siège absent depuis > 30 s, PIN correct |
| `rpc_reclamer_plateau()` | l'hôte ou le présentateur | reprend le rôle de plateau, état inchangé |
| `rpc_geler(raison)` / `rpc_degeler()` | la télé | met la partie en pause et **gèle les chronos** |
| `rpc_sauter_tour(tour_id)` | l'hôte ou le présentateur | tour perdu à 0 point, après 60 s d'absence |

Une règle transversale : **aucune fonction ne fait confiance à un identifiant de joueur
passé en paramètre**. L'appelant est toujours `auth.uid()`.

---

## 6. Temps réel

Chaque écran s'abonne à **un seul canal** : `partie:<id>`, sur les changements Postgres
de `parties`, `joueurs`, `binomes` et la vue publique de `tours`. Un changement d'état
redessine l'écran concerné.

**Les votes ne sont jamais diffusés** — ni le détail, ni le compteur. Ils sont
insert-only et personne ne les lit. Seul le **verdict** est diffusé, une fois. La règle
du jeu (votes secrets jusqu'à la fin de la fenêtre) et l'économie de messages pointent
dans le même sens.

Budget, pour une partie de 4 binômes sur 40 minutes :

```
~350 changements d'état  ×  9 écrans abonnés  ≈  3 000 messages
quota gratuit : 2 000 000 / mois              ≈  600 parties / mois
```

Le plafond qui mordra en premier n'est pas le volume mais les **200 connexions
simultanées**, soit environ **22 parties en même temps**. Large pour un jeu de soirée
entre amis ; à surveiller le jour où ça circule.

---

## 7. Authentification

**Connexion anonyme Supabase**, déclenchée au moment où on tape son prénom. Aucun compte,
aucun mot de passe, aucun e-mail.

Ce n'est pas un raccourci, c'est **nécessaire** : sans identité, RLS ne peut pas
distinguer un joueur d'un autre, et le secret des réponses s'effondre. Le jeton est
conservé en `localStorage` : un téléphone qui recharge, se verrouille ou perd le réseau
retrouve sa place et sa phase. Un téléphone complètement perdu rejoint avec le code —
le même `auth.uid()` le replace dans son binôme.

---

## 8. Le coût, et ses trois pièges

| Poste | Plan | Ce qu'on consomme |
|---|---|---|
| Base, realtime, auth | Supabase gratuit | base < 10 Mo, egress négligeable |
| Hébergement du site | statique gratuit | 137 Ko gzip par visiteur neuf (mesuré) |
| Domaine | **le seul vrai coût** | ~12 €/an, et optionnel |

### Piège n°1 — la pause après 7 jours d'inactivité. Le vrai problème.
Un projet Supabase gratuit est **mis en pause après une semaine sans activité**. Et un
jeu de soirée, par nature, **ne tourne pas toutes les semaines**. Le scénario qui casse
le produit : vendredi soir, huit personnes autour de la télé, le site ne répond pas.

Deux parades :
1. **Un ping hebdomadaire par GitHub Actions** (gratuit sur dépôt public) : un cron qui
   appelle une requête triviale tous les 3 jours. C'est la solution, elle coûte 15 lignes
   de YAML.
2. Réveiller le projet à la main depuis le dashboard — une minute, mais il faut y penser
   avant que les invités arrivent, pas pendant.

**À mettre en place dès le premier déploiement**, pas plus tard : c'est le genre de
problème qu'on découvre au pire moment.

### Piège n°2 — le plafond de transfert de l'hébergeur
**Firebase Hosting (Spark)** : 10 Go de stockage, **360 Mo de transfert par jour**.
Mesuré sur le bundle réel (`npm run build`) : **137 Ko gzip** par visiteur neuf —
135 Ko de JS, dont la banque de questions embarquée, et 1,5 Ko de CSS. Soit environ
**2 600 chargements par jour**, très au-delà de l'usage réel, et le CDN sert les
visiteurs connus en cache.

Reste que **Cloudflare Pages** offre un hébergement statique gratuit **sans plafond de
bande passante**. Si tu n'as pas d'attache à l'écosystème Firebase, c'est le choix plus
robuste pour un site qui pourrait circuler d'un coup. Firebase Hosting fonctionne très
bien et ne coûtera rien — c'est juste un plafond en moins à surveiller.

### Piège n°3 — deux projets actifs maximum
Le gratuit Supabase plafonne à **2 projets actifs**. Donc **pas de projet de
développement séparé** sans sacrifier quelque chose. Le plus simple : un seul projet,
deux schémas (`public` et `dev`), ou un préfixe d'environnement sur le code de partie.

### Les quotas qui ne poseront pas de problème
500 Mo de base (on en utilise ~10), 5 Go d'egress par mois, 50 000 utilisateurs actifs,
500 000 invocations de fonctions edge — qu'on n'utilise pas, tout tient dans Postgres.

---

## 9. Structure du projet React

```
src/
  main.tsx
  routes/
    Accueil.tsx            — saisie du code + prénom
    Plateau.tsx            — /tv/:code, la vue télé
    Joueur.tsx             — /p/:code, la vue téléphone
  phases/                  — un composant par état, des deux côtés
    Lobby.plateau.tsx      Lobby.joueur.tsx
    Prep.plateau.tsx       Prep.joueur.tsx
    Manche.plateau.tsx     Manche.joueur.tsx
    Bonus.plateau.tsx      Bonus.joueur.tsx
    Finale.plateau.tsx     Finale.joueur.tsx
    Palmares.plateau.tsx
  jeu/
    usePartie.ts           — abonnement realtime + état projeté. LE hook central.
    rpc.ts                 — un wrapper typé par fonction du §5
    tirage.ts              — filtre et tire dans questions.json
    chrono.ts              — compte à rebours dérivé de fin_at, jamais de l'horloge locale
  ui/                      — les composants de la DA
    Panneau.tsx Narration.tsx Bulle.tsx PastilleBinome.tsx
    Chrono.tsx Verdict.tsx BoutonTampon.tsx Trame.tsx
  contenu/
    questions.json         — copié depuis la racine à la compilation
  styles/
    tokens.css             — les jetons de la DA, tels quels
```

**Pas de store client** — ni Redux, ni Zustand. La base *est* le store ; `usePartie`
projette la ligne `parties` et ses satellites, et chaque composant lit la phase. Ajouter
un store dupliquerait la vérité et créerait exactement les désynchronisations que
l'architecture évite.

**Deux routes, pas deux applications.** `/tv/:code` et `/p/:code` partagent les jetons,
les composants d'UI et le hook. Seule la mise en page change : la télé compose une
planche, le téléphone compose une case.

---

## 10. Déconnexions, reprises, abandons

Un jeu de soirée tourne sur huit téléphones, un wifi de salon et des gens qui posent
leur appareil sur la table. **La déconnexion est le cas normal, pas l'exception.** Quatre
mécanismes la couvrent.

### a. La session survit à la fermeture de l'onglet
La session anonyme Supabase est persistée en `localStorage` avec son jeton de
rafraîchissement. Fermer l'onglet, verrouiller l'écran, redémarrer le téléphone, revenir
une heure plus tard : **c'est le même `auth.uid()`**, donc le même joueur, dans le même
binôme, avec ses réponses de préparation intactes.

L'app mémorise aussi le **dernier code de partie**. Rouvrir le site sans rien taper
renvoie **directement dans la phase en cours** — pas de lobby, pas de nouveau prénom.

### b. Le siège se reprend par PIN quand la session est vraiment perdue
Trois cas la détruisent : navigation privée, effacement des données, et le plus fréquent —
**scanner le QR code ouvre un autre navigateur** que celui utilisé pour rejoindre.

À l'arrivée dans le lobby, chaque joueur voit donc une fois un **PIN à 4 chiffres**, avec
la consigne de ne pas le fermer. `rpc_reprendre_siege(code, prenom, pin)` rend le siège,
à deux conditions : le PIN est bon, et le siège est **absent depuis plus de 30 secondes**.
Impossible de voler la place de quelqu'un qui joue à côté de soi.

Sans le PIN, l'hôte peut rendre un siège depuis son téléphone. Dans une pièce où tout le
monde se voit, c'est suffisant — et c'est toujours mieux qu'une partie bloquée.

### c. Rien n'expire pendant qu'on attend quelqu'un
**La règle qui compte.** Un pouls (`rpc_pouls`) rafraîchit `vu_le` toutes les 10 secondes.
Si le joueur **attendu** — celui qui doit répondre, le questionneur du tour, ou le
finaliste en plein chrono — disparaît, le plateau **gèle la partie** : les chronos et la
fenêtre de vote s'arrêtent, leur reste est stocké en millisecondes, et la télé affiche
*« on attend Camille »*.

Personne ne doit perdre de points à cause du réseau. C'est pour ça que les chronos sont
gelables alors qu'ils vivent côté serveur : on stocke un **restant**, pas seulement une
date de fin.

Au retour, le chrono repart là où il s'était arrêté. Si l'absence dure, l'hôte ou le
présentateur peut **sauter le tour** (0 point, la partie continue) — le choix reste
humain, jamais automatique.

Un **votant** absent, lui, ne gèle rien : c'est une abstention, elle ne pèse pas sur la
majorité (règles §6.1). Et s'il revient avant la fin de la fenêtre, son vote est encore
accepté.

### d. La partie survive à l'abandon
Rien n'est détenu par un appareil : tout l'état est en base.

- **La télé s'éteint en pleine finale** → l'hôte ou le présentateur appelle
  `rpc_reclamer_plateau()` depuis son téléphone et devient le plateau. L'état ne bouge pas.
- **Le présentateur part** → l'arbitrage des égalités retombe sur la règle sans
  présentateur : l'égalité vaut validation.
- **Tout le monde ferme tout** → la partie reste reprenable **12 heures**. On revient avec
  le code, on retombe exactement dans la phase quittée. Une soirée coupée par un dîner se
  reprend au dessert.
- **Une réponse de préparation est écrite question par question**, jamais en un seul envoi
  final : fermer la page au milieu de la prépa ne perd que la question en cours de saisie,
  conservée en brouillon local.

---

## 11. Ce qui reste à trancher

- **Le domaine.** Le seul poste payant. Un sous-domaine gratuit de l'hébergeur suffit
  pour commencer, mais un code à 4 lettres sur une URL en `.pages.dev` est moins facile
  à crier à travers un salon.
- **La modération des parties publiques.** Tant que les parties se créent par code à
  usage privé, il n'y a rien à modérer. Si un jour le site devient un lieu, c'est un
  autre produit.
