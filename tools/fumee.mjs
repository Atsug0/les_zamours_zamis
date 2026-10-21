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

console.log(
  ko
    ? `\n${ko} vérification(s) en échec.`
    : `\n✓ la chaîne complète tourne sur le vrai projet — partie de test ${partie.code}, elle expire seule.`
);
process.exit(ko ? 1 : 0);
