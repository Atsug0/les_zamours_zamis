# Banque de questions — charte éditoriale et audit

La banque vit dans **`questions.json`**. Les garde-fous sont dans **`lint_questions.py`** :
`python3 lint_questions.py` échoue si une règle ci-dessous est violée. À lancer avant
tout commit de contenu.

État actuel : **plus de 300 questions jouables** — 84 paires ouvertes (168), 18 paires QCM (36),
17 bonus, 11 séries de finale (55), 15 « cite 3 ». Fonds commun utilisable sans aucun bloc
d'occasion : **69 paires ouvertes en zamours, 65 en zamis**.

---

## 1. Le point de départ

`Questionnaire_Les_Zamours_340_Questions.pdf` (idees-de-jeux.fr) : 340 questions en
10 rubriques, pensées pour une animation de mariage avec un animateur et du papier.
Bonne matière première, mais **aucune ligne n'était réutilisable telle quelle**, pour
une raison qui n'a rien à voir avec l'âge du contenu.

## 2. Le problème de fond : le PDF parle à la place du joueur

Les 340 questions sont écrites à la troisième personne avec un genre flottant :

> Q3. Combien de temps passe-**t-il/elle** sous la douche en moyenne ?
> Q35. Quelle est **sa** tâche ménagère préférée ?

Trois défauts cumulés :
1. **`il/elle` est illisible à l'écran** et impossible à lire à voix haute proprement.
2. Ça **présuppose un genre connu et binaire**, et un couple homme-femme.
3. Ça ne dit pas **qui** répond : la même phrase sert à interroger le joueur sur
   lui-même et à interroger son partenaire. Or notre jeu a besoin des deux
   formulations, distinctes (§12.1 des règles).

### La règle qui règle tout : zéro pronom, un prénom

Chaque question existe en deux versions, et **aucune ne contient de pronom de genre** :

| Champ | Destinataire | Forme | Exemple |
|---|---|---|---|
| `prepa` | le joueur, sur lui-même, en phase de préparation | **tutoiement** | « Combien de temps tu passes sous la douche ? » |
| `jeu` | affiché sur l'écran TV pendant la manche | **prénom injecté** via `{P}` | « Combien de temps **{P}** passe sous la douche ? » |

`{P}` est remplacé par le prénom réel au moment de l'affichage. Conséquences :

- **Couples gays, lesbiens, non-binaires, amis, frères et sœurs, collègues** : aucune
  adaptation nécessaire, la question ne porte aucune hypothèse.
- Rien à accorder, donc rien à casser.
- Le prénom à l'écran est plus vivant qu'un pronom : **« Combien de temps Sam passe
  sous la douche ? »** se lit à voix haute sans trébucher.

Le lint refuse toute occurrence de `il/elle`, `(e)`, `son/sa`, `ton/ta`.

## 3. Zamis ≠ Zamours : trois niveaux de traitement

Une question inappropriée entre amis ne doit pas être « adoucie » : elle doit être
**écartée** ou **réécrite**. Trois cas, tous encodés dans `modes` :

### a. Exclue — `modes: ["zamours"]`
Tout ce qui présuppose une relation amoureuse : la rencontre, le premier « je t'aime »,
le premier baiser, le côté du lit, ce qui plaît physiquement chez l'autre.
Entre amis, ces questions ne sont pas « gênantes » : elles sont **absurdes**.

### b. Réécrite — paires jumelles, champ `jumeau`
Le même emplacement de jeu, deux formulations selon le lien. C'est le travail le plus
utile de la refonte :

| Sujet | Zamours | Zamis |
|---|---|---|
| L'origine | Où vous êtes-vous rencontrés ? **Qui a fait le premier pas ?** | Où vous êtes-vous rencontrés ? **Qui écrit le premier message ?** |
| Le code privé | Le surnom quand personne n'écoute / la blague privée | Le surnom / l'expression que tu lui as volée |
| Le rituel | Votre chanson / la série que vous regardez à deux | Votre rituel / ce que vous commandez systématiquement |
| Le point de friction | Le sujet de dispute récurrent | Ce sur quoi vous ne serez jamais d'accord |

### c. Commune — `modes: ["zamours", "zamis"]`
Le fonds commun : quotidien, écrans, goûts, caractère, enfance, boulot, bizarreries.
**Contrainte stricte** : une question commune ne doit contenir **aucun** vocabulaire de
couple. Le lint interdit `couple`, `mariage`, `conjoint`, `amoureux`, `baiser`,
`je t'aime`, `noces`, `cérémonie`, `témoin` dans toute question jouable en zamis.

> Ce garde-fou a attrapé une vraie erreur pendant l'écriture : un QCM sur
> « faire le **premier pas** après une dispute », parfaitement valide entre amis mais
> dont la formulation sonnait amoureuse. Réécrit en « faire le **premier geste** après
> une brouille ».

### d. Les blocs d'occasion — champ `occasion`
Les 20 questions « spéciales mariage » du PDF ne sont ni communes ni zamis : elles
présupposent un **événement**. Elles deviennent un bloc `occasion: "mariage"`,
**jamais tiré par défaut**, activable par un binôme au lobby. Le lint vérifie que
chaque mode tient une partie complète **sans** aucun bloc d'occasion.

C'est le patron à suivre pour toute extension : coloc, grossesse, pot de départ,
anniversaire de X ans. Un bloc, un opt-in, zéro contamination du fonds commun.

## 4. Les présupposés qu'on a retirés au-delà du genre

Le PDF suppose en permanence une vie-type. Retiré ou rendu conditionnel :

| Présupposé | Exemple du PDF | Traitement |
|---|---|---|
| Mariage / noces | Q290 voyage de noces, Q301-320 | bloc `occasion: "mariage"` |
| Enfants désirés | Q274 « Aimerait-il avoir des enfants ? Combien ? » | retiré — non concordable et intrusif en groupe |
| Cohabitation | Q4 côté du lit, Q26 coin de la maison | `zamours` pour le lit, reformulé en « chez toi » pour le reste |
| Deux parents vivants | Q211 prénoms des parents, Q234 leur profession | retiré |
| Religion | Q228 parrain / marraine | retiré |
| Voiture, bureau, patron | Q247 nom du patron, Q254 transport | reformulés sans présupposé, ou retirés |
| Rôles genrés | Q68 « talons ou baskets ? » | retiré |

## 5. Ce qui a été retiré pour des raisons de jeu, pas d'inclusivité

Notre jeu exige une **réponse courte, unique et arbitrable** (règles §6.2). Beaucoup de
questions du PDF ne le permettent pas :

| Motif | Exemples écartés |
|---|---|
| Réponse non concordable, trop ouverte | Q11 « sa routine du matin », Q154 « se décrit en trois mots », Q297 « comment définit-il le bonheur », Q299 « sa vie idéale » |
| Aucune tension, réponse connue d'avance | Q87 « son nombre préféré », Q88 « sa lettre préférée », Q232 « l'origine de son nom de famille » |
| Fait deviner l'identité de gens absents | Q218 prénom du meilleur ami, Q247 du patron, Q249 d'un collègue, Q230 des grands-parents |
| Appelle « ça dépend » | Q29 « quelle température aime-t-il dans la maison ? » |
| Réponse sans référent commun | Q83 « son œuvre d'art préférée », Q115 « votre plus belle photo » |

Le lint refuse toute question contenant « ça dépend » dans ses propositions, et toute
question de plus de 110 caractères — au-delà, ça ne tient pas sur un écran de télé lu
à 3 mètres.

## 6. La mise à jour 2026

### Ce qui a été remplacé
| Daté | 2026 |
|---|---|
| Q7-8 « son émission de télé préférée » | la plateforme la plus ouverte, la dernière série terminée, **la série abandonnée en cours de route** |
| Q191 « combien de fois vérifie-t-il ses réseaux ? » | **son temps d'écran quotidien**, qu'on vérifie sur son téléphone en direct |
| Q184 « quelle émission regarde-t-il en cachette ? » | **quel abonnement il paie sans jamais l'utiliser** |
| Q62 livres papier ou numériques | vocal, texte ou appel — le vrai clivage de 2026 |
| Q9 « son réseau social préféré » | l'appli la plus utilisée, et **celle qu'il a désinstallée puis réinstallée** |

### Le thème ajouté : `ecrans` (10 paires)
Temps d'écran, notifications non lues, ce qu'il demande à une IA, l'onglet ouvert
depuis des semaines, l'emoji le plus envoyé, le titre le plus écouté de l'année, la
dernière livraison, le dernier achat en seconde main, où dort le téléphone.

### L'idée produit qui en sort : `verifiable: true`
Certaines réponses 2026 sont **consultables en direct sur le téléphone du joueur** :
temps d'écran, emoji le plus utilisé, titre le plus écouté, nombre de photos, fond
d'écran. Ces questions portent le flag `verifiable`.

À la révélation, l'app invite le joueur à **ouvrir ses réglages et montrer l'écran**.
C'est le meilleur moment de jeu disponible : **la preuve remplace le vote**, personne ne
peut contester, et le joueur se trahit lui-même. Aucune question du PDF ne pouvait
faire ça en 2015.

## 6 bis. Le piquant, ou pourquoi la première version était ennuyeuse

La charte de départ optimisait la **concordance** : réponse courte, unique, arbitrable.
Elle a produit une banque techniquement impeccable et **sans relief** — un audit l'a
chiffré : **77 % des questions n'avaient aucun enjeu**. « À quelle heure tu te lèves le
samedi ? » coche toutes les règles et ne fait rire personne.

La concordance est la mécanique, pas le but. Une bonne question a en plus **une prise** :

| Elle a une prise quand… | Exemple |
|---|---|
| elle **révèle** un travers | « Sur quoi {P} ment systématiquement, même pour rien ? » |
| elle **embarrasse** avec affection | « De quoi {P} se vante alors que ce n'est pas vrai ? » |
| elle **oppose** les deux réponses | « Lequel de vous deux parle trop fort au restaurant ? » |
| elle **force une anecdote** | « Quelle est la dernière chose que {P} a cassée ? » |
| elle est **drôle avant la réponse** | « Lequel de vous deux ronfle et le nie ? » |

À l'inverse, ces formulations sont presque toujours plates : *à quelle heure…*,
*combien de temps…*, *quel est son X préféré*, *où range-t-il…*. Un fait neutre se
vérifie, mais ne raconte rien.

### Le registre : actuel, direct, allusif
Le fonds a été réécrit thème par thème pour parler de 2026 et pas de 1998 : les stories
qu'on regarde trois fois, le message laissé en vu, la capture d'écran envoyée aux potes,
ce qu'on demande à une IA et qu'on n'oserait demander à personne, l'achat planqué en
rentrant, l'artiste qu'on écoute en cachette.

**Le coquin est admis, et il est allusif.** C'est le registre de l'émission d'origine —
on suggère, on ne décrit pas : « où est-ce que vous avez failli vous faire surprendre »,
« quelle célébrité aurait droit à ta carte blanche », « si personne ne devait jamais le
savoir, qu'est-ce que tu ferais ». Une question explicite sort du jeu : elle gêne au
lieu de faire rire, et elle ferme la table au lieu de l'ouvrir.

### Le curseur `piquant`
Chaque question porte un niveau de 1 à 3. **Ce n'est pas la difficulté** : une question
peut être facile et gênante.

- **1 — tout public.** Ça passe à Noël avec les beaux-parents.
- **2 — ça pique.** Le registre par défaut du jeu : on se chambre.
- **3 — croustillant.** Marqué `sensible`, donc **tiré seulement si les deux membres du
  binôme ont activé les catégories sensibles au lobby**. Le consentement existait déjà,
  il sert maintenant de curseur.

## 7. Charte de rédaction — pour écrire la suite

0. **Une question doit avoir une prise.** Si elle ne révèle rien, n'embarrasse
   personne et ne fait pas se contredire deux personnes, elle n'a pas sa place —
   même si elle se juge parfaitement. C'est la règle qui manquait (§6 bis).
1. **Zéro pronom de genre.** Jamais. `{P}` et le tutoiement suffisent à tout.
2. **Deux formulations obligatoires** : `prepa` au tutoiement, `jeu` avec `{P}`.
3. **Réponse en 4 mots maximum**, unique, qu'un tiers peut arbitrer. Si la réponse
   honnête est « ça dépend » ou « un peu tout », la question est morte.
4. **Chiffres : toujours une tolérance** (`tol`), sinon le vote est ingérable.
5. **Écrire par paires.** Deux sujets **distincts** de **difficulté égale** : c'est ce
   qui permet aux deux membres d'un binôme de ne jamais jouer le même sujet (règles
   §3.1). Le lint refuse une paire dont les deux slots posent la même question.
6. **110 caractères max.** Ça se lit sur une télé, à voix haute, en une respiration.
7. **Un présupposé = un `mode` ou une `occasion`.** Jamais une question commune qui
   « marche à peu près » pour tout le monde.
8. **Pas de nom de tiers absent.** On ne fait pas deviner le prénom du patron devant
   huit personnes.
9. **`sensible: true`** dès qu'on touche à l'argent, la famille, la santé, l'intime.
   Opt-in par binôme, jamais par défaut.
10. **Durée de vie de deux ans minimum.** Une marque, une appli ou une série nommée
    périme ; un usage, non. Préférer « la série que tu as abandonnée » à un titre précis.

## 8. Structure du fichier

```
questions.json
├── convention        glossaire des champs, lisible par un humain
├── paires_ouvertes   84 paires → 168 questions (manche libre, 15 pts)
├── paires_qcm        18 paires → 36 questions  (manche QCM, 5 pts, 3 propositions)
├── bonus             17 énoncés communs aux deux membres (30 pts)
├── series_finale     11 séries de 5 questions → 55 (finale, 12 pts + prime)
└── citez_trois       15 énoncés pour la variante « cite 3 » (règles §9.3)
```

Champs d'une paire : `id`, `theme`, `modes`, `diff` (1-3), `sensible`, `tol`,
`occasion`, `jumeau`, puis `a` et `b` — chacun avec `prepa`, `jeu`, et selon le cas
`props` (QCM) ou `verifiable`.
