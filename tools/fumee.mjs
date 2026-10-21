#!/usr/bin/env node
// Test de fumée sur le VRAI projet, à travers l'API HTTP et la clé
// publique — exactement le chemin qu'emprunte un téléphone.
//
//   node tools/fumee.mjs
//
// Monte une partie de 4 joueurs, forme deux binômes, choisit les modes,
// lance, et vérifie que le tirage et les tours sont bien là. N'écrit
// jamais rien qu'une partie de test, qui expire d'elle-même en 12 h.
import { readFileSync } from "node:fs";

const env = Object.fromEntries(
  readFileSync(new URL("../app/.env.local", import.meta.url), "utf8")
    .split("\n").filter((l) => l.includes("=")).map((l) => {
      const i = l.indexOf("=");
      return [l.slice(0, i).trim(), l.slice(i + 1).trim()];
    })
);
const URL_BASE = env.VITE_SUPABASE_URL;
const CLE = env.VITE_SUPABASE_ANON_KEY;
if (!URL_BASE || !CLE) throw new Error("app/.env.local incomplet");

let ko = 0;
const ok = (cond, libelle, detail = "") => {
  console.log(`${cond ? "  ok  " : "ÉCHEC "} ${libelle}${detail ? "  " + detail : ""}`);
  if (!cond) ko++;
};

/** Ouvre une session anonyme, comme le fait l'app au premier écran. */
async function session(nom) {
  const r = await fetch(`${URL_BASE}/auth/v1/signup`, {
    method: "POST",
    headers: { apikey: CLE, "Content-Type": "application/json" },
    body: "{}",
  });
  const d = await r.json();
  if (!d.access_token) {
    throw new Error(
      `session anonyme refusée pour ${nom} : ${d.msg ?? d.error_description ?? JSON.stringify(d)}` +
        `\n\n-> Authentication > Sign In / Providers > Anonymous sign-ins > Enable`
    );
  }
  return d.access_token;
}

async function rpc(jeton, nom, args = {}) {
  const r = await fetch(`${URL_BASE}/rest/v1/rpc/${nom}`, {
    method: "POST",
    headers: { apikey: CLE, Authorization: `Bearer ${jeton}`, "Content-Type": "application/json" },
    body: JSON.stringify(args),
  });
  const d = await r.json().catch(() => null);
  if (!r.ok) throw new Error(`${nom} -> HTTP ${r.status} ${d?.message ?? ""}`);
  return d;
}

async function lire(jeton, chemin) {
  const r = await fetch(`${URL_BASE}/rest/v1/${chemin}`, {
    headers: { apikey: CLE, Authorization: `Bearer ${jeton}` },
  });
  return r.ok ? r.json() : { erreur: r.status };
}

console.log("Test de fumée —", URL_BASE, "\n");

const tv = await session("plateau");
const partie = await rpc(tv, "rpc_creer_partie");
ok(/^[A-HJ-NP-Z]{4}$/.test(partie.code), "le plateau obtient un code criable", partie.code);

const noms = ["Sam", "Alex", "Camille", "Lou"];
const jetons = [];
for (const nom of noms) {
  const j = await session(nom);
  const r = await rpc(j, "rpc_rejoindre", { p_code: partie.code, p_prenom: nom });
  jetons.push({ nom, jeton: j, id: r.joueur_id, pin: r.pin });
}
ok(jetons.length === 4, "quatre joueurs ont rejoint");
ok(jetons.every((j) => /^\d{4}$/.test(j.pin)), "chacun a reçu un PIN de reprise");

await rpc(jetons[0].jeton, "rpc_apparier", { p_cible: jetons[1].id });
await rpc(jetons[2].jeton, "rpc_apparier", { p_cible: jetons[3].id });
const binomes = await lire(tv, `binomes?partie_id=eq.${partie.partie_id}&select=couleur,mode`);
ok(binomes.length === 2, "deux binômes formés");
ok(
  binomes.map((b) => b.couleur).sort().join(",") === "jaune,rouge",
  "couleurs dans l'ordre du plateau"
);

const un = await rpc(jetons[0].jeton, "rpc_choisir_mode", { p_mode: "zamours" });
ok(un.accord === false, "un seul choix ne verrouille rien");
await rpc(jetons[1].jeton, "rpc_choisir_mode", { p_mode: "zamours" });
await rpc(jetons[2].jeton, "rpc_choisir_mode", { p_mode: "zamis" });
const deux = await rpc(jetons[3].jeton, "rpc_choisir_mode", { p_mode: "zamis" });
ok(deux.accord === true, "les deux d'accord : binôme verrouillé");

const lance = await rpc(tv, "rpc_lancer", { p_format: "court" });
ok(lance.etat === "prep", "la partie passe en préparation");
ok(lance.tours === 14, "14 tours fabriqués", `(${lance.tours})`);

const mes = await rpc(jetons[0].jeton, "rpc_mes_questions");
ok(mes.total === 9, "9 questions à préparer");
ok(
  mes.questions.filter((q) => /\.[ab]$/.test(q)).every((q) => q.endsWith(mes.role.toLowerCase())),
  "les paires servies correspondent au slot du joueur"
);

// Le cœur de la sécurité : personne ne lit les secrets, personne n'écrit.
const fuite = await lire(jetons[0].jeton, "reponses_prepa?select=valeur");
ok(fuite.erreur !== undefined, "reponses_prepa reste inaccessible par l'API");
const triche = await fetch(`${URL_BASE}/rest/v1/v_recap?ordre=eq.-1`, {
  method: "PATCH",
  headers: {
    apikey: CLE,
    Authorization: `Bearer ${jetons[0].jeton}`,
    "Content-Type": "application/json",
  },
  body: JSON.stringify({ points: 9999 }),
});
ok(!triche.ok, "falsifier un score à travers une vue est refusé", `HTTP ${triche.status}`);
const interne = await fetch(`${URL_BASE}/rest/v1/rpc/juger_tour`, {
  method: "POST",
  headers: { apikey: CLE, Authorization: `Bearer ${jetons[0].jeton}`, "Content-Type": "application/json" },
  body: JSON.stringify({ p_tour: partie.partie_id, p_verdict: true }),
});
ok(!interne.ok, "appeler juger_tour directement est refusé", `HTTP ${interne.status}`);

// ---------------------------------------------------------------
// Les noms de paramètres de app/src/jeu/rpc.ts correspondent-ils aux
// signatures réelles ? Un nom faux ne se voit pas à la compilation et
// casse l'écran au moment précis où on en a besoin. PostgREST publie
// sa spec : on compare.
// ---------------------------------------------------------------
{
  const spec = await (await fetch(`${URL_BASE}/rest/v1/`, { headers: { apikey: CLE } })).json();
  const src = readFileSync(new URL("../app/src/jeu/rpc.ts", import.meta.url), "utf8");
  let faux = 0;
  for (const [chemin, def] of Object.entries(spec.paths ?? {})) {
    const m = /^\/rpc\/(rpc_\w+)$/.exec(chemin);
    if (!m) continue;
    const corps = def.post?.parameters?.find((p) => p.name === "args")?.schema?.properties ?? {};
    const attendus = Object.keys(corps);
    // on ne vérifie que les fonctions réellement appelées par le front
    const bloc = new RegExp(`appel<[^>]*>\\(\\s*"${m[1]}"([\\s\\S]{0,400}?)\\)\\s*,?\\n`, "m").exec(src);
    if (!bloc) continue;
    for (const nom of attendus) {
      if (!bloc[1].includes(nom)) {
        console.log(`ÉCHEC  ${m[1]} : le front n'envoie pas « ${nom} »`);
        faux++;
      }
    }
  }
  ok(faux === 0, "les paramètres de rpc.ts correspondent aux signatures réelles");
}

// ---------------------------------------------------------------
// La partie complète, dans l'ORDRE EXACT où les écrans appellent.
// ---------------------------------------------------------------
const parJeton = new Map(jetons.map((j) => [j.id, j.jeton]));
const quiJoue = (id) => parJeton.get(id) ?? tv;

for (const j of jetons) {
  const q = await rpc(j.jeton, "rpc_mes_questions");
  for (const id of q.questions) {
    await rpc(j.jeton, "rpc_repondre_prepa", { p_question: id, p_valeur: "oui" });
  }
}
const prog = await lire(tv, `v_progression?partie_id=eq.${partie.partie_id}`);
ok(prog[0]?.termines === 4, "la TV voit 4 joueurs sur 4 prêts", `(${prog[0]?.termines})`);

let garde = 0;
let etat = (await rpc(tv, "rpc_suivant")).etat;
while (["qcm", "libre", "bonus"].includes(etat) && garde++ < 60) {
  const [t] = await lire(tv, `v_tours?partie_id=eq.${partie.partie_id}&statut=neq.juge&order=ordre&limit=1`);
  if (!t) { etat = (await rpc(tv, "rpc_suivant")).etat; continue; }

  if (t.manche === "qcm") {
    const q = await rpc(quiJoue(t.repondant_id), "rpc_mes_questions").catch(() => null);
    void q;
    await rpc(quiJoue(t.repondant_id), "rpc_consigner", { p_tour: t.id, p_valeur: "oui" });
  } else {
    if (t.manche !== "bonus") {
      await rpc(quiJoue(t.questionneur_id), "rpc_consigner", { p_tour: t.id, p_valeur: "oui" });
    }
    await rpc(quiJoue(t.questionneur_id), "rpc_reveler", { p_tour: t.id });
    for (const j of jetons) {
      await rpc(j.jeton, "rpc_voter", { p_tour: t.id, p_pour: true }).catch(() => {});
    }
    await rpc(tv, "rpc_clore_vote", { p_tour: t.id });
  }
  etat = (await rpc(tv, "rpc_suivant")).etat;
}
ok(etat === "finale", "les manches s'enchaînent jusqu'à la finale", `(${etat})`);

const tours = await lire(tv, `v_tours?partie_id=eq.${partie.partie_id}&select=statut,points,manche`);
ok(tours.every((t) => t.statut === "juge"), "les 14 tours sont jugés");
ok(
  tours.filter((t) => t.manche === "bonus").every((t) => t.points === 30),
  "le bonus concordant vaut 30 points"
);

const passages = await lire(tv, `v_passages_finale?partie_id=eq.${partie.partie_id}&order=ordre`);
ok(passages.length === 2, "deux passages de finale créés");

for (const f of passages) {
  const membres = await lire(tv, `v_joueurs?binome_id=eq.${f.binome_id}&select=id,role&order=role`);
  const finaliste = membres[0].id;
  await rpc(quiJoue(finaliste), "rpc_designer_finaliste", { p_passage: f.id, p_joueur: finaliste });
  const lance = await rpc(quiJoue(f.questionneur_id), "rpc_demarrer_passage", { p_passage: f.id });
  ok(lance.questions.length === 5, `le questionneur reçoit les 5 réponses attendues`);
  for (let i = 1; i <= 5; i++) {
    await rpc(quiJoue(f.questionneur_id), "rpc_juger", {
      p_passage: f.id, p_index: i, p_jugement: i <= 3 ? "juste" : "faux",
    });
  }
  const clos = await rpc(tv, "rpc_clore_passage", { p_passage: f.id });
  ok(clos.points === 76, "3 justes sur 5 : 36 + prime 40 = 76 points", `(${clos.points})`);
}

const fin = await rpc(tv, "rpc_suivant");
ok(fin.etat === "palmares", "la partie se termine sur le palmarès");
const palmares = await lire(tv, `v_palmares?partie_id=eq.${partie.partie_id}&order=rang`);
ok(palmares.length === 2 && palmares[0].rang === 1, "le palmarès classe les binômes");
const recap = await lire(tv, `v_recap?partie_id=eq.${partie.partie_id}&select=ordre`);
ok(recap.length === 14, "le récap de soirée contient les 14 tours");

console.log(
  ko
    ? `\n${ko} vérification(s) en échec.`
    : `\n✓ une partie entière se joue sur le vrai projet — ${partie.code}, elle expire seule.`
);
process.exit(ko ? 1 : 0);
