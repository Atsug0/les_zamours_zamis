# Mise en ligne

De zéro à une partie jouable. Compter **30 minutes** la première fois.
Coût courant : **0 €**, hors nom de domaine si tu en veux un.

Tout ce qui suit a une étape obligatoire qu'on oublie toujours : §2.2 (la
connexion anonyme) et §6 (l'anti-pause). Sans la première, personne ne peut
jouer ; sans la seconde, ça marche trois semaines puis ça s'arrête.

---

## 1. Ce qu'il faut

| Outil | Pourquoi | Obligatoire |
|---|---|---|
| Un compte [Supabase](https://supabase.com) | base, temps réel, sessions | oui |
| Un compte Cloudflare **ou** Firebase | héberger le site | oui |
| Node 20 ou plus | construire le site | oui |
| Un dépôt GitHub | le cron anti-pause (§6) | fortement conseillé |
| `supabase` CLI | appliquer les migrations en une commande | non (§3.2 sinon) |
| Docker | rejouer les tests en local | non |

```bash
node --version            # >= 20
npm i -g supabase         # optionnel
```

---

## 2. Le projet Supabase

### 2.1 Créer
Dashboard → **New project**. Région **Europe (Frankfurt ou Paris)** : le jeu se joue
en direct, chaque aller-retour compte. Note le mot de passe de la base, il ne
s'affiche qu'une fois.

Récupère ensuite dans **Project Settings → API** :
- l'**URL du projet** (`https://xxxx.supabase.co`),
- la clé **anon public**.

> La clé anon est **publique par conception** : elle part dans le bundle du site.
> Toute la sécurité tient dans les RLS et les fonctions `SECURITY DEFINER`
> (ARCHITECTURE.md §3). La clé `service_role`, elle, ne doit **jamais** quitter
> tes secrets — elle contourne tout.

### 2.2 Activer la connexion anonyme — ÉTAPE OBLIGATOIRE
**Authentication → Sign In / Providers → Anonymous sign-ins → Enable.**

Elle est **désactivée par défaut**, et sans elle *personne ne peut rejoindre une
partie* : l'app n'a aucune identité à présenter, donc RLS refuse tout et le secret
des réponses s'effondre. C'est la panne numéro un à ce stade.

Pendant que tu y es, dans **Authentication → Attack Protection**, active le
**CAPTCHA** si le site devient public : une connexion anonyme est gratuite pour
toi comme pour un robot.

---

## 3. Appliquer la base

Onze migrations, dans l'ordre, puis le contenu.

### 3.1 Avec la CLI (recommandé)
```bash
supabase login
supabase link --project-ref <ref-du-projet>   # la ref est dans l'URL du dashboard
supabase db push                              # applique supabase/migrations/*
psql "$DATABASE_URL" -f supabase/seed_questions_index.sql
```

`DATABASE_URL` se trouve dans **Project Settings → Database → Connection string**
(prendre le mode *session*). Sans `psql` sous la main, voir §3.2 pour le seed.

### 3.2 Sans la CLI, par copier-coller
Dans **SQL Editor**, exécuter dans cet ordre exact, un fichier par onglet :

```
supabase/migrations/0001_schema.sql
supabase/migrations/0002_rls.sql
supabase/migrations/0003_lobby.sql
supabase/migrations/0004_partie.sql
supabase/migrations/0005_manches.sql
supabase/migrations/0006_finale.sql
supabase/migrations/0007_realtime.sql
supabase/migrations/0008_ping.sql
supabase/migrations/0009_droits.sql
supabase/migrations/0010_droits_tables.sql
supabase/migrations/0011_realtime_et_reprise.sql
supabase/seed_questions_index.sql
```

L'ordre n'est pas négociable : 0002 dépend des tables de 0001, le seed des colonnes de
0001, et **0009 puis 0010 doivent passer en dernier** — elles ferment les droits sur les
fonctions puis sur les tables et les vues, et doivent donc voir tout ce qui existe.

> `0010` corrige un trou trouvé en déployant pour de vrai. Supabase accorde par défaut
> **tous** les droits sur toute table du schéma `public` à `anon` et `authenticated`.
> Les migrations plus anciennes révoquaient une liste **nommée** de tables — mais les
> **vues** sont créées après, et restaient donc écrivables. Or une vue
> non-`security_invoker` s'exécute avec les droits de son *propriétaire* : écrire à
> travers elle **contournait entièrement les RLS**. `update v_recap set points = 9999`
> falsifiait les scores. 0010 repart de zéro par motif, jamais par liste nominative.

### 3.3 Vérifier que la base est saine
Dans **SQL Editor** :

```sql
-- 302 entrées attendues
select count(*) from questions_index;

-- les 5 tables diffusées, et SURTOUT pas reponses_prepa ni votes
select tablename from pg_publication_tables
where pubname = 'supabase_realtime' order by 1;

-- doit renvoyer 0 ligne : aucune table de jeu ouverte en écriture à l'API
select table_name, privilege_type
from information_schema.role_table_grants
where grantee in ('anon','authenticated')
  and privilege_type in ('INSERT','UPDATE','DELETE')
  and table_schema = 'public';

-- doit renvoyer exactement 3 lignes : ping, est_membre, nb_questions_prepa.
-- Toute autre fonction ici est un endpoint REST ouvert par accident.
select p.proname
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  and p.proname not like 'rpc\_%'
  and (has_function_privilege('anon', p.oid, 'execute')
    or has_function_privilege('authenticated', p.oid, 'execute'))
order by 1;

select ping();
```

Si la troisième requête renvoie quelque chose, **arrête-toi** : une table est
écrivable depuis le navigateur, et le jeu est trichable.

Si la quatrième renvoie autre chose que ces trois noms, `0009_droits.sql` n'est pas
passée. PostgREST publie **toute** fonction du schéma `public` joignable par `anon` ou
`authenticated` : un helper interne laissé ouvert devient un endpoint. Celui qui
attribue les points en fait partie.

---

## 4. Construire le site

```bash
cd app
cp .env.example .env.local
```

Remplir `.env.local` :
```
VITE_SUPABASE_URL=https://xxxx.supabase.co
VITE_SUPABASE_ANON_KEY=eyJhbGciOi...
```

```bash
npm install
npm run build        # copie le contenu, vérifie les types, teste les QR, compile
```

Le build **échoue volontairement** si un QR code ne se décode pas ou si un type
est faux. Un QR illisible est un bug invisible à l'œil : il ne doit pas pouvoir
partir en production.

Pour travailler en local : `npm run dev`, puis ouvrir deux fenêtres —
`localhost:5173/tv/CODE` d'un côté, `localhost:5173/p/CODE` de l'autre.

---

## 5. Héberger

**Le point à ne pas rater, quel que soit l'hébergeur : la réécriture page unique.**
Sans elle, recharger `/p/ABCD` renvoie un 404 — et un joueur qui recharge son
téléphone en pleine partie est éjecté. Les fichiers de config sont déjà dans le
dépôt.

### 5.1 Cloudflare Pages — recommandé
Aucun plafond de bande passante, et `app/public/_redirects` fait déjà la
réécriture.

```bash
npm i -g wrangler
cd app && wrangler pages deploy dist --project-name les-zamours-zamis
```

Ou par l'interface : **Workers & Pages → Create → Pages → Connect to Git**, avec
répertoire racine `app`, commande `npm run build`, dossier de sortie `dist`. Ne pas
oublier d'y déclarer les deux variables `VITE_*` — le build tourne chez eux.

### 5.2 Firebase Hosting — ce qui est en place
Le site tourne sur **https://les-zamours-zamis.web.app** (projet
`les-zamours-zamis`). `app/firebase.json` et `app/.firebaserc` sont dans le dépôt, donc
un déploiement se résume à :

```bash
cd app && npm run build && firebase deploy --only hosting
```

Pour repartir de zéro sur un autre compte :
```bash
npm i -g firebase-tools
firebase login
firebase projects:create mon-projet --display-name "Les Zamours Zamis"
# puis remplacer l'id dans app/.firebaserc
```

> **Le piège des en-têtes.** Firebase compare le `source` d'une règle `headers` au
> **chemin demandé**, pas au fichier finalement servi. Une règle sur `/index.html` ne
> s'applique donc **jamais** à `/`, `/tv/CODE` ou `/p/CODE`, qui passent par la
> réécriture : le document héritait du cache par défaut d'une heure, et un joueur
> pouvait garder une vieille version du jeu. La configuration met donc un fourre-tout
> `**` en `no-cache` d'abord, et les règles précises ensuite — les dernières l'emportent
> sur la même clé. Vérifiable en une commande :
>
> ```bash
> curl -sSI https://les-zamours-zamis.web.app/p/ABCD | grep -i cache-control
> ```

Plafond à connaître : **360 Mo de transfert par jour**. Le bundle fait **143 Ko
gzip**, soit environ **2 500 chargements quotidiens**. Largement suffisant, mais
c'est un plafond, là où Cloudflare n'en a pas.

### 5.3 Le cache de `index.html`
Les deux configs mettent `index.html` en `no-cache` et les assets en `immutable`.
C'est voulu : les noms de fichiers d'assets changent à chaque build, mais si le
document est caché, un joueur garde une vieille version du jeu et se
désynchronise des autres.

---

## 6. L'anti-pause — ÉTAPE OBLIGATOIRE

Un projet gratuit est **suspendu après 7 jours sans activité**. Un jeu de soirée,
par nature, ne tourne pas toutes les semaines.

`.github/workflows/supabase-eveil.yml` est déjà écrit : il appelle `ping()` tous
les 3 jours. Il faut juste créer les deux secrets dans
**Settings → Secrets and variables → Actions** :

```
SUPABASE_URL       https://xxxx.supabase.co
SUPABASE_ANON_KEY  eyJhbGciOi...
```

Puis le déclencher une fois à la main (**Actions → Éveil Supabase → Run
workflow**) pour vérifier qu'il renvoie bien `HTTP 200`.

> GitHub désactive les workflows planifiés d'un dépôt **sans activité depuis
> 60 jours**. Si tu ne touches plus au code pendant deux mois, repasse le
> réactiver — ou mets un rappel. C'est la seule faiblesse de ce montage.

Si le projet est déjà suspendu, le cron ne le réveille pas : il faut passer par
**le dashboard → Restore project**. Compter deux minutes.

---

## 7. La première partie, pour de vrai

À faire avec deux appareils minimum, avant d'inviter du monde :

1. Ouvrir `/` sur un ordinateur → **Ouvrir le plateau**. Un code à 4 lettres et un
   QR s'affichent.
2. **Scanner le QR avec un vrai téléphone.** C'est le seul test qui vaille : un QR
   se vérifie sur un capteur, pas dans un navigateur.
3. Rejoindre avec 4 joueurs (ou 4 onglets en navigation privée — chaque onglet
   privé a sa propre session). Noter le PIN affiché à chacun.
4. Former deux binômes, choisir les modes, lancer.
5. **Recharger brutalement un téléphone** en pleine partie : il doit retrouver sa
   place et sa phase sans rien demander.
6. **Fermer l'onglet du plateau** et le réouvrir sur `/tv/CODE` : la partie
   continue, l'état n'a pas bougé.

Si l'étape 3 bloque sur une erreur d'autorisation, retourner au §2.2.

### Les deux tests de fumée, avant même d'ouvrir un navigateur
```bash
node tools/fumee.mjs            # le parcours complet et les tentatives de triche
node tools/fumee-realtime.mjs   # le temps réel arrive-t-il vraiment au client ?
```

Le second est celui qu'on oublie, et c'est le plus traître : le temps réel **ne
fonctionne que sur les tables, jamais sur les vues**, et une politique RLS trop étroite
fige le lobby **sans produire la moindre erreur**. Les écrans restent simplement vides.
C'est ce qui est arrivé ici, et seule une vérification par le client l'a révélé.


Monte une partie de 4 joueurs **sur le vrai projet, par l'API HTTP et la clé
publique** — le chemin exact d'un téléphone. Il vérifie le parcours complet jusqu'au
lancement, puis rejoue trois tentatives de triche qui doivent toutes être refusées :
lire `reponses_prepa`, falsifier un score à travers une vue, appeler `juger_tour`
directement. La partie de test expire seule au bout de 12 h.

C'est le test à lancer en premier : s'il passe, le dos de l'application est sain.

---

## 8. Mettre à jour

### Le contenu des questions
`questions.json` est la source unique. Après toute modification :

```bash
python3 lint_questions.py            # refuse une question genrée ou mal formée
python3 tools/seed_index.py          # régénère le seed
# puis rejouer supabase/seed_questions_index.sql sur la base
cd app && npm run build              # le bundle embarque les textes
```

L'index en base et les textes du bundle doivent être régénérés **ensemble** :
sinon le serveur tire un identifiant dont le client n'a pas le texte.

### Le code
```bash
cd app && npm run build && wrangler pages deploy dist --project-name les-zamours-zamis
```

### Le schéma
Ajouter une migration numérotée dans `supabase/migrations/`, **jamais** modifier
une migration déjà appliquée. Vérifier en local d'abord :

```bash
./tools/db_local.sh --reset     # monte un Postgres jetable et rejoue les 115 tests
```

---

## 9. Quand ça ne marche pas

| Symptôme | Cause réelle |
|---|---|
| « Anonymous sign-ins are disabled » | §2.2 — la cause numéro un |
| Rejoindre échoue sans message clair | les migrations ne sont pas toutes passées ; rejouer §3.3 |
| Les écrans ne se mettent pas à jour tout seuls | `0007_realtime.sql` manquante — rien n'est diffusé |
| 404 en rechargeant `/p/ABCD` | la réécriture page unique n'est pas en place (§5) |
| « VITE_SUPABASE_URL manque » | `.env.local` absent en local, ou variables non déclarées chez l'hébergeur |
| Tout marchait, plus rien ne répond | projet suspendu — §6, puis **Restore project** |
| Un joueur voit les réponses d'un autre | **ne devrait pas arriver.** Rejouer la 3ᵉ requête du §3.3 et me le signaler |
| Les scores ne bougent pas | personne ne clôt les votes : le plateau doit rester ouvert, c'est lui l'horloge |

---

## 10. Ce que ça coûte vraiment

| Poste | Plan gratuit | Consommé par une soirée |
|---|---|---|
| Base | 500 Mo | < 1 Mo |
| Messages temps réel | 2 M / mois | ~3 000 par partie, soit ~600 parties |
| Connexions simultanées | 200 | 9 par partie → ~22 parties en parallèle |
| Egress | 5 Go / mois | négligeable |
| Hébergement | illimité (Cloudflare) / 360 Mo/j (Firebase) | 143 Ko par visiteur neuf |
| **Domaine** | — | **~12 €/an, et c'est tout** |

Le plafond qui mordra en premier n'est aucun de ces chiffres : ce sont les **200
connexions simultanées**. Si le jeu circule et que ça arrive, c'est le moment de
passer au plan payant — pas avant.
