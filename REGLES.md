# Les Zamours Zamis — Règles du jeu

Jeu de complicité **web + mobile**, inspiré des *Z'amours*, conçu pour une soirée
entre amis ou en couple. Deux écrans :

- **L'écran TV** (le site ouvert sur une télé, un vidéoproj, un laptop) = **le plateau**.
  Tout le monde le regarde. Il affiche la question en cours, qui joue, le chrono,
  les scores, les révélations.
- **Les téléphones** = **les pupitres**. Chacun y prépare ses réponses, y vote, y
  arbitre, et ne voit que ce qu'il a le droit de voir.

**Les réponses se donnent à voix haute.** Le téléphone ne sert jamais à répondre à la
place du joueur : il sert à préparer, à consigner, à voter. Tout ce qui se joue se joue
dans la pièce (§4.1).

Aucun secret ne transite par l'écran TV. Aucune info publique ne reste coincée
sur un téléphone.

Le contenu du jeu vit dans **`questions.json`** ; sa charte de rédaction et l'audit de
la banque sont dans **`BANQUE.md`**.

---

## 1. Principe

Un **binôme** = 2 joueurs. Avant la partie, chacun répond à des questions **sur
lui-même**. Pendant la partie, son partenaire doit **retrouver ce qu'il a répondu**.

On ne juge jamais si une réponse est « vraie ». On juge si elle **correspond**.

---

## 2. Lobby

### 2.1 Constitution des binômes
1. Les joueurs rejoignent le salon (code à 4 lettres ou QR code affiché sur l'écran TV).
2. Chacun se met **en paire** avec un autre joueur : l'un envoie l'invitation, l'autre
   accepte. Le binôme est verrouillé quand les deux ont confirmé.
3. **Nombre impair de joueurs** → le joueur restant devient le **présentateur**.
   Il ne marque pas de points : il arbitre, valide, et fait avancer l'émission.
4. **Nombre pair** → pas de présentateur, le jeu s'auto-arbitre (voir §5.3 et §7.3).
   Un joueur peut aussi se **déclarer présentateur volontairement**, à condition que
   le reste des joueurs soit en nombre pair.

### 2.2 Choix du mode, par binôme
Chaque binôme choisit son mode. **Les deux membres doivent choisir le même**, sinon
le binôme reste bloqué dans le lobby.

| Mode | Pour qui | Tonalité des questions |
|---|---|---|
| **Les Zamours** | couples | vie commune, intimité, rencontre, projets, petites guerres de ménage |
| **Les Zamis** | amis, colocs, collègues, famille | souvenirs, soirées, habitudes, goûts, qui est le plus … du groupe |

Le mode **détermine le pool de questions tiré**, et ce n'est pas une nuance de ton :
une question qui présuppose une relation amoureuse (la rencontre, le premier « je
t'aime », le côté du lit) n'est pas *adoucie* en mode Zamis, elle est **écartée**, ou
**remplacée par sa jumelle** écrite pour un lien amical. Le détail est dans `BANQUE.md`.

Les deux modes peuvent coexister dans la même partie : les binômes ne jouent pas les
mêmes questions, mais elles sont **calibrées sur la même difficulté** et le barème est
identique.

### 2.2.1 Blocs d'occasion
Certaines questions présupposent un **événement** et non un lien : le mariage, par
exemple. Elles vivent dans des blocs optionnels, **jamais tirés par défaut**, qu'un
binôme active au lobby (un binôme qui se marie dans trois mois a tout intérêt à cocher
la case). Le fonds commun suffit à tenir une partie entière sans aucun bloc.

### 2.3 Effectif
- **Minimum : 2 binômes** (4 joueurs). En dessous, personne ne peut voter sur les
  réponses libres.
- **Idéal : 3 à 4 binômes**, soit **35 à 50 minutes** de partie en format par défaut.
- À **2 ou 3 binômes**, le *format long* (§9.1) est jouable et tient l'heure.
- Au-delà de **6 binômes**, scinder en deux parties parallèles : le temps d'attente
  entre deux tours devient le vrai problème, pas la durée totale.

### 2.4 Réglages de la partie (hôte)
Format (**court** par défaut, ou long), seuil et chrono de la finale, fenêtre de vote,
activation des catégories sensibles, tolérance numérique. Les valeurs par défaut de ce
document sont calibrées pour une partie de 40 minutes à 4 binômes.

---

## 3. Phase de préparation

Lancement de la partie → **tout le monde répond en même temps, sur son téléphone**.
L'écran TV n'affiche qu'une barre de progression anonyme (« 5 joueurs sur 8 ont
terminé »). **Rien du contenu n'y apparaît.**

Chaque joueur répond à **sa propre série** :

| # | Type | Objet |
|---|---|---|
| 2 | **questions ouvertes** | sur lui-même, réponse libre et courte |
| 1 | **QCM** | sur lui-même, 3 propositions |
| 1 | **question bonus** | la même pour les deux membres du binôme |
| 5 | **série finale** | sur lui-même, réponses courtes, servira à la finale |

Soit **9 questions par joueur**, environ 3 minutes de préparation. C'est volontairement
court : la prépa est le seul moment mort de la soirée, personne ne la regarde.

### 3.1 La règle des sets croisés

C'est le point structurant du jeu.

```
Au sein d'un binôme, les deux joueurs n'ont PAS les mêmes questions.

  Joueur A  →  Q1  Q2  (ouvertes)  +  Q3  (QCM)
  Joueur B  →  Q4  Q5  (ouvertes)  +  Q6  (QCM)

Entre binômes du même mode, les sets sont les MÊMES.

  Binôme 1 : A1 → Q1-Q3    B1 → Q4-Q6
  Binôme 2 : A2 → Q1-Q3    B2 → Q4-Q6
  Binôme 3 : A3 → Q1-Q3    B3 → Q4-Q6
```

Deux conséquences :
- **Aucune redondance** dans le binôme : chaque sujet n'est joué qu'une fois.
  (Si les deux répondaient à la même question, on jouerait deux fois le même fait.)
- **Comparabilité** entre binômes : quand l'écran affiche *« Q5 : le pire défaut de
  son partenaire »*, tous les binômes passent par là. Le vote des autres joueurs est
  donc rendu sur une base identique, et les scores sont comparables.

Le rôle **A / B** est tiré au sort à la création du binôme et affiché à chacun.

### 3.2 La question bonus
Seule question où **les deux membres reçoivent le même énoncé**, et répondent chacun
de leur côté. Elle n'est pas devinée : elle est **révélée simultanément** en fin de
partie. Elle porte sur le binôme lui-même (« combien de temps avant que l'un des deux
craque », « qui a dit je t'aime en premier », « votre pire souvenir commun »).

### 3.3 Passer une question
Un joueur peut **passer** n'importe quelle question de préparation. Elle est remplacée
par une question de secours de même type et même valeur. Les questions marquées
*sensibles* ne sont tirées que si le binôme a activé la catégorie au lobby.

---

## 4. Déroulé de l'émission

```
LOBBY  →  PRÉPARATION  →  MANCHE 1 : QCM  →  MANCHE 2 : LIBRE  →  BONUS  →  FINALE  →  PALMARÈS
```

L'écran TV mène la danse. Le présentateur (ou l'hôte) appuie sur **Suivant** pour
enchaîner. À chaque question :

1. **Annonce** — l'écran TV affiche le binôme appelé et qui des deux va répondre.
2. **Question** — l'énoncé apparaît en grand sur la TV, **avec le prénom du partenaire
   dedans** : « Combien de temps Sam passe sous la douche ? ». Aucune question ne
   contient de pronom de genre, ce qui la rend valable pour n'importe quel binôme
   (§12.1).
3. **Réponse** — le joueur répond **à voix haute**. Il peut hésiter, penser tout haut,
   se faire chahuter par la salle. Puis sa réponse est **consignée** (§4.1).
4. **Révélation** — l'écran TV affiche côte à côte la réponse donnée et la réponse
   enregistrée par le partenaire.
5. **Jugement** — automatique en QCM, par vote en libre.
6. **Points** — le score du binôme s'anime sur la TV.

### 4.1 La réponse orale

C'est la mécanique centrale du jeu, et ce qui fait sa vie : **on répond en parlant**.
Le joueur peut réfléchir à voix haute, se contredire, négocier avec la salle, lire son
partenaire. Trois règles l'encadrent, et elles suffisent.

**a. La réponse enregistrée reste cachée jusqu'à la consignation.**
L'écran TV n'affiche **rien** de ce que le partenaire a répondu avant que la réponse
orale soit consignée. Le joueur parle donc à l'aveugle : il n'y a rien à ajuster.
C'est cette règle, et elle seule, qui rend l'oral équitable.

**b. La règle de la réponse ferme.**
Penser tout haut est libre. Mais une seule réponse compte : la première annoncée comme
ferme. La formule attendue, affichée sur la TV pendant la saisie :

> **« Ma réponse, c'est … »**

Le questionneur peut aussi la provoquer — « c'est ta réponse ? » — et le joueur dit oui.
Après ça, plus de retour en arrière : un « attends non, je voulais dire » n'est pas
recevable, même avant la révélation.

**c. Quelqu'un consigne.**

| Phase | Qui consigne | Geste |
|---|---|---|
| QCM | le joueur lui-même | il annonce son choix à voix haute, **puis** tape la proposition sur son téléphone |
| Libre et bonus | le questionneur du tour (§8.3) | il tape **2-3 mots** résumant la réponse, puis **Révéler** |
| Finale | le questionneur | **✓ / ✗ / passer**, au fil du chrono |

La consignation du questionneur sert à deux choses : déclencher la révélation, et
alimenter le récap de fin de soirée (§8.4). Elle ne juge pas — le jugement, c'est le
vote de la salle.

**d. S'il n'y a pas de présentateur.**
Le questionneur du tour est un joueur **d'un autre binôme**, désigné à la rotation
automatique. Il ne consigne jamais pour son propre binôme. Son téléphone affiche
l'énoncé et le champ de consignation — **jamais la réponse enregistrée**, qui ne
s'affiche qu'au moment de la révélation, sur la TV, pour tout le monde en même temps.

### 4.2 Quand quelqu'un se déconnecte

Le jeu tourne sur le wifi d'un salon et sur des téléphones qu'on pose sur la table : la
déconnexion est un cas normal. Deux règles de fair-play, tenues par le produit et pas par
la bonne volonté.

**Personne ne perd de points à cause du réseau.** Si le joueur attendu — celui qui doit
répondre, le questionneur du tour, ou le finaliste en pleine course — disparaît, la partie
**gèle** : le chrono et la fenêtre de vote s'arrêtent net, et reprennent là où ils en
étaient. L'écran TV affiche qui on attend. Si l'absence s'installe, l'hôte ou le
présentateur peut **sauter le tour** à 0 point — c'est une décision humaine, jamais
automatique.

**Un votant absent est une abstention.** Il ne gèle rien et ne pèse pas sur la majorité
(§6.1). S'il revient avant la fin de la fenêtre, son vote compte encore.

Tout le reste se reprend sans rien perdre : un téléphone qui recharge ou se verrouille
retrouve sa place et sa phase, un siège vraiment perdu se récupère avec le PIN à 4
chiffres donné au lobby, et une partie abandonnée reste reprenable **12 heures** avec son
code. Mécanique détaillée dans `ARCHITECTURE.md` §10.

---

## 5. Manche 1 — QCM

- On joue **le QCM de chaque joueur**, soit **2 questions par binôme**.
- L'ordre de passage alterne entre les binômes, pour que personne n'attende 10 questions.
- Les **3 propositions s'affichent sur la TV**, en grand, numérotées. Le joueur annonce
  son choix à voix haute, puis le tape sur son téléphone pour le consigner.
- **Validation automatique** : identique = juste, différent = faux. Pas de vote, pas de
  débat. C'est la manche rapide, elle sert à chauffer la salle.

**5 points** par concordance.

---

## 6. Manche 2 — Questions libres

Le cœur du jeu, et son twist.

- On joue **les 2 questions ouvertes de chaque joueur**, soit **4 questions par binôme**.
- Le joueur répond à voix haute, en toutes lettres. Pas de liste, pas d'indice, pas de
  filet. Il peut tourner autour, la salle peut le chahuter — jusqu'à la réponse ferme.
- Le questionneur consigne, puis déclenche la **révélation** : les deux réponses
  apparaissent côte à côte sur la TV.
- Puis **le vote s'ouvre**.

### 6.1 Le vote
> « Est-ce que ça compte ? »

- **Qui vote** : tous les joueurs **sauf les deux membres du binôme concerné**.
  Une voix chacun. Le présentateur ne vote pas (il arbitre).
- **Comment** : deux boutons sur le téléphone, ✅ / ❌. Fenêtre de **15 secondes**.
  Les votes sont **secrets jusqu'à la fin de la fenêtre**, puis le décompte s'affiche
  sur la TV avant le verdict — c'est le moment de spectacle.
- **Verdict** : **majorité simple**.
- **Égalité** : le **présentateur tranche**. S'il n'y a pas de présentateur,
  **l'égalité vaut validation** (le doute profite au binôme).
- **Non-votant** : qui ne vote pas dans la fenêtre est compté comme abstention et ne
  pèse pas sur la majorité.

### 6.2 Ce que le vote est censé juger
À afficher sur la TV pendant la fenêtre de vote, pour cadrer la salle :

- Même idée formulée autrement → **ça compte** (« la vaisselle » / « laver les assiettes »).
- Bonne catégorie mais pas la bonne réponse → **ça ne compte pas** (« le bleu » / « le vert »).
- Réponse parapluie, du type « ça dépend », « un peu tout » → **ça ne compte pas**.
  C'est la seule règle stricte : les réponses vagues tuent le jeu.
- Sur les chiffres, tolérance de **± 10 %**, ou l'intervalle réglé au lobby — certaines
  questions portent leur propre tolérance.

**Questions vérifiables.** Quelques questions ont une réponse consultable en direct sur
le téléphone du joueur : temps d'écran, emoji le plus envoyé, titre le plus écouté de
l'année, nombre de photos. Elles portent le flag `verifiable` dans la banque. Pour
celles-là, **pas de vote** : l'app demande au joueur d'ouvrir ses réglages et de montrer
l'écran. La preuve tranche mieux que la majorité, et le joueur se trahit tout seul.

**15 points** par concordance validée.

---

## 7. La question bonus

Un seul passage par binôme, en fin de manches.

1. L'écran TV affiche l'énoncé — le même pour les deux membres.
2. Roulement, puis **les deux réponses apparaissent en même temps**.
3. Jugement : **vote de tous les autres joueurs**, mêmes règles qu'en §6.1, mais
   fenêtre de **20 secondes** et le présentateur commente avant d'ouvrir le vote.

**30 points** si les deux réponses concordent.

### 7.1 Score maximum avant la finale

| Manche | Détail | Points |
|---|---|---|
| QCM | 2 × 5 | 10 |
| Libre | 4 × 15 | 60 |
| Bonus | 1 × 30 | 30 |
| **Total** | | **100** |

Un score sur 100 à l'entrée de la finale : lisible pour tout le monde, à l'œil, sur la TV.

---

## 8. La finale

**Tous les binômes la jouent**, chacun son tour. Le classement des manches ne sert
pas à éliminer : il fixe **l'ordre de passage**, du dernier au premier. Le leader
passe en dernier, avec la pression.

### 8.1 Déroulé d'un passage
1. Le binôme désigne **lequel des deux joue**. L'autre s'assoit et se tait.
2. Le joueur qui joue doit retrouver les **5 réponses de la série finale** de son
   partenaire (§3, préparées en phase de prépa).
3. **Chrono : 30 secondes** pour enchaîner les 5.
4. Les questions sont **lues à voix haute** par le **questionneur** (§8.3), qui les
   voit sur son téléphone. L'écran TV affiche le chrono, la question en cours et la
   file des 5 pastilles.
5. Le joueur répond **à l'oral**, immédiatement. Le questionneur appuie sur
   **✓ / ✗ / passer**. Pas de discussion pendant le chrono.
6. **Passer** est gratuit : la question est remise en fin de file et rejouée si le
   chrono le permet.
7. Le passage s'arrête quand les 5 sont tranchées **ou** que le chrono tombe à zéro.

### 8.2 Barème de la finale
- **12 points** par bonne réponse.
- **Seuil : 3 bonnes réponses sur 5** → **prime de 40 points**.
- En dessous du seuil, les bonnes réponses restent acquises, mais pas la prime.
- Maximum sur la finale : 60 + 40 = **100 points**.

La finale pèse donc autant que toutes les manches réunies : un binôme largué peut
revenir, un leader peut tout perdre. C'est volontaire — c'est le dernier acte.

### 8.3 Qui pose et qui valide
- **S'il y a un présentateur** : c'est lui, pour tous les passages.
- **Sinon** : un joueur **d'un autre binôme** est désigné questionneur, à la rotation
  automatique. Il ne peut jamais questionner son propre binôme.
- En finale **seulement**, le questionneur a sur son téléphone l'énoncé **et** la
  réponse enregistrée : il n'y a pas de vote, il tranche seul, en direct. **Sa décision est sans appel** pendant le chrono.
- **Contestation** : une seule, après le chrono, par le binôme concerné. On rejoue le
  point au vote de la salle (§6.1). Chrono non rendu.

### 8.4 Palmarès
Score des manches + score de finale. Le binôme en tête gagne.
**Égalité au sommet** → mort subite : une question ouverte commune, les deux binômes
jouent, le premier à concorder gagne.

---

## 9. Variantes et réglages

### 9.1 Format long (2 ou 3 binômes, soirée qui s'étire)
- 2 QCM + 3 questions ouvertes par joueur, finale à 7 questions en 45 s, seuil 4/7
- Barème inchangé par question : QCM 5, libre 15, bonus 30, finale 12 + prime 40
- Score max avant finale : 20 + 90 + 30 = 140 ; finale : 84 + 40 = 124
- Compter **le double de temps** : c'est le format d'une vraie partie de fin de soirée.

### 9.2 Manche « ou pas »
À insérer entre les QCM et les libres : l'écran affiche une affirmation sur le binôme,
les deux membres répondent **vrai / faux simultanément** sur leur téléphone (la seule
manche sans oral, justement pour la vitesse). Concordance = 5 points, zéro arbitrage.

### 9.3 Manche « cite 3 »
Reprise du principe des questions finales du jeu d'origine, activable au lancement.

En **préparation**, chaque joueur cite **trois choses sur son partenaire** — « cite 3
défauts de Sam ». Pendant la manche, le partenaire doit retrouver les trois, à voix
haute. Le questionneur les note, révèle les trois enregistrées, puis **annonce combien
ont concordé**.

- **5 points par réponse commune**, soit 15 par passage.
- **Deux passages par binôme**, un par sens : la manche est ainsi symétrique avec toutes
  les autres, et réutilise les paires et les sets croisés. Maximum **30 points**.
- **Jugée par le questionneur, pas par un vote.** Faire voter trois réponses une par une
  casserait le rythme ; la salle voit les deux triplets côte à côte et le questionneur
  tranche. C'est le seul endroit des manches où le vote ne décide pas.
- Se place **juste avant le bonus**, et allonge la partie d'environ un quart d'heure.

Énoncés dans `questions.json` → `citez_trois`.

### 9.4 Mise
Avant chaque question libre, le binôme mise **0, 5 ou 10 points** de son capital.
Concordance validée → la mise est doublée. Échec → la mise est perdue.
Pour les groupes qui connaissent déjà le jeu.

### 9.5 Sans écran TV
La vue plateau se replie dans le téléphone : chacun voit la scène en lecture seule
entre ses tours. Même partie, moins de spectacle.

---

## 10. Règles de bonne tenue

Le jeu expose une intimité **consentie**. Ces règles sont dans le produit, pas en option :

- Chaque joueur peut **passer** n'importe quelle question, en prépa comme en manche,
  sans justification. Le point est perdu, rien d'autre.
- Les **catégories sensibles** (ex, argent, famille, santé, sexualité) sont
  **désactivées par défaut** et s'activent **par binôme**, à l'unanimité des deux.
- Un joueur peut **signaler** une question : elle est remplacée immédiatement et ne
  revient pas dans la partie.
- Les réponses de préparation d'un joueur ne sont **jamais** visibles par son
  partenaire, ni avant, ni après la question jouée.

---

## 11. Architecture des écrans

### 11.1 Écran TV — le plateau (lecture seule, aucun secret)

| Phase | Affichage |
|---|---|
| Lobby | code / QR, binômes en train de se former, mode choisi par chacun |
| Préparation | progression anonyme, aucun contenu |
| Manche | binôme appelé, énoncé en grand, réponse en attente, puis double révélation |
| Vote | décompte des votes masqué → révélé → verdict |
| Bonus | roulement, puis les deux réponses simultanément |
| Finale | chrono géant, question en cours, 5 pastilles ✓/✗/en attente |
| Palmarès | classement final, meilleures réponses de la soirée |

### 11.2 Téléphone — selon le rôle et la phase

| Rôle | Ce qu'il voit |
|---|---|
| **Joueur, prépa** | sa propre série, une question à la fois, bouton passer |
| **Joueur, son tour** | l'énoncé, le rappel « Ma réponse, c'est … » ; en QCM, les 3 propositions à taper |
| **Questionneur du tour** | l'énoncé, le champ de consignation, le bouton Révéler — **jamais** la réponse enregistrée |
| **Joueur, tour d'un autre binôme** | ✅ / ❌ pendant la fenêtre de vote, sinon vue plateau réduite |
| **Joueur, tour de son binôme** | écran neutre — **pas de vote, pas d'indice** |
| **Présentateur** | commande Suivant, arbitrage des égalités, consignation, énoncés + réponses de la finale, ✓ / ✗ / passer |
| **Questionneur, finale** | les 5 énoncés + réponses du binôme qu'il interroge, ✓ / ✗ / passer |

### 11.3 Machine à états

```
lobby
  └─ pairing ──(tous les binômes verrouillés)──► prep
prep
  └─ answering ──(tous ont terminé)──► round_qcm
round_qcm
  └─ [annonce → question → réponse → révélation → score] × n ──► round_libre
round_libre
  └─ [annonce → question → réponse → révélation → vote → verdict → score] × n ──► bonus
bonus
  └─ [révélation simultanée → vote → verdict → score] × binômes ──► finale
finale
  └─ [désignation → chrono 30 s → 5 jugements → score] × binômes ──► palmares
palmares
```

---

## 12. Modèle de données

```ts
type Mode = "zamours" | "zamis";
type Role = "A" | "B";

// Reflet de questions.json : le contenu est écrit PAR PAIRES, pas par question.
interface PaireQuestion {
  id: string;
  theme: "quotidien" | "ecrans" | "gouts" | "souvenirs" | "amitie" | "perso"
       | "drole" | "enfance" | "boulot" | "avenir" | "argent" | "intime" | "mariage";
  modes: Mode[];               // ["zamours"], ["zamis"], ou les deux
  diff: 1 | 2 | 3;
  sensible: boolean;
  tol?: string;                // "±10 %", "±1 h" — tolérance d'arbitrage
  occasion?: "mariage";        // bloc opt-in, jamais tiré par défaut
  jumeau?: string;             // id de la paire équivalente dans l'autre mode
  a: Enonce;                   // servi au joueur A du binôme
  b: Enonce;                   // servi au joueur B — sujet distinct, même difficulté
}

interface Enonce {
  prepa: string;               // "Quel est ton pire défaut ?"        (tutoiement)
  jeu: string;                 // "Quel est le pire défaut de {P} ?"  ({P} = prénom)
  props?: [string, string, string];  // QCM : exactement 3
  verifiable?: boolean;        // réponse consultable sur le téléphone → pas de vote
}

interface Joueur {
  id: string; pseudo: string;
  binomeId: string | null;
  role: Role | null;
  presentateur: boolean;
  reponses: Record<string, Reponse>;   // questionId → réponse de prépa
}

interface Reponse { questionId: string; valeur: string; passee: boolean; }

interface Binome {
  id: string; mode: Mode;
  joueurs: [string, string];
  score: number;
  verrouille: boolean;
  categoriesSensibles: boolean;
}

interface Tour {
  binomeId: string;
  questionId: string;
  repondantId: string;          // celui qui devine
  reponseDonnee: string | null;      // consignée par le questionneur (2-3 mots)
  questionneurId: string;            // présentateur, ou joueur d'un autre binôme
  reponseAttendue: string;
  statut: "attente" | "consigne" | "revele" | "vote" | "juge";
  votes: Record<string, boolean>;   // joueurId → ✅ / ❌
  verdict: boolean | null;
  arbitreParPresentateur: boolean;
}

interface PassageFinale {
  binomeId: string;
  joueurId: string;             // celui qui devine
  questionneurId: string;
  jugements: ("juste" | "faux" | "passee" | "attente")[];  // 5, ou 7 en format long
  tempsRestantMs: number;
  seuilAtteint: boolean;
  pointsGagnes: number;
}

interface Partie {
  code: string;
  etat: "lobby" | "prep" | "round_qcm" | "round_libre" | "bonus" | "finale" | "palmares";
  format: "court" | "long";
  binomes: Binome[];
  joueurs: Joueur[];
  tours: Tour[];
  finale: PassageFinale[];
  reglages: {
    questionsFinale: number;    // 5   (7 en format long)
    seuilFinale: number;        // 3   (4 en format long)
    chronoFinaleMs: number;     // 30000  (45000 en format long)
    fenetreVoteMs: number;      // 15000
    toleranceNumerique: number; // 0.10
  };
}
```

### 12.1 Deux énoncés, zéro pronom
`prepa` est posé au joueur sur lui-même, **au tutoiement**. `jeu` est affiché sur la TV
avec **`{P}` remplacé par le prénom** du partenaire. Aucun des deux ne contient de
pronom de genre — ni `il/elle`, ni `(e)`, ni `son/sa`.

C'est ce qui rend le jeu utilisable tel quel pour un couple gay, lesbien, hétéro, une
personne non-binaire, deux amis, deux frères, deux collègues : la question ne porte
**aucune hypothèse** sur qui joue. Et « Combien de temps Sam passe sous la douche ? »
se lit à voix haute sans trébucher, ce qu'aucun `il/elle` ne permet.

`lint_questions.py` fait échouer toute question qui réintroduirait une forme genrée.

### 12.2 Appariement des sets croisés
Le contenu n'est pas écrit question par question mais **par paires** : chaque entrée
porte un `a` et un `b`, de même difficulté, sur des **sujets distincts** du même thème.

Le tirage prend **3 paires** du mode du binôme (5 en format long), sert tous les `a` au
joueur A et tous les `b` au joueur B, et répète le même tirage pour **tous les binômes
du même mode**. D'où les deux propriétés promises en §3.1, gratuitement : un binôme ne
joue jamais deux fois le même sujet, et deux binômes du même mode sont comparables.

Filtres appliqués avant tirage : `modes` contient le mode du binôme, `occasion` est
absente (sauf bloc activé), et `sensible` est faux (sauf catégories activées).
