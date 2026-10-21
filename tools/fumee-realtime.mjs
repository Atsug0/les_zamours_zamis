#!/usr/bin/env node
// Vérifie que le TEMPS RÉEL arrive vraiment au client.
//
//   node tools/fumee-realtime.mjs
//
// C'est la pièce qui échoue en silence : publication oubliée, RLS qui
// filtre tout, jeton non transmis au canal. Et sans elle, la télé et les
// téléphones ne se mettent jamais à jour — le jeu ne marche pas, sans
// qu'aucune erreur n'apparaisse nulle part.
import { createClient } from "../app/node_modules/@supabase/supabase-js/dist/index.mjs";
import { readFileSync } from "node:fs";

const env = Object.fromEntries(
  readFileSync(new URL("../app/.env.local", import.meta.url), "utf8")
    .split("\n").filter((l) => l.includes("=")).map((l) => {
      const i = l.indexOf("=");
      return [l.slice(0, i).trim(), l.slice(i + 1).trim()];
    })
);

const neuf = () =>
  createClient(env.VITE_SUPABASE_URL, env.VITE_SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

let ko = 0;
const ok = (c, l, d = "") => {
  console.log(`${c ? "  ok  " : "ÉCHEC "} ${l}${d ? "  " + d : ""}`);
  if (!c) ko++;
};

// --- le plateau ouvre une partie et s'abonne, comme la télé ---
const tv = neuf();
await tv.auth.signInAnonymously();
const { data: partie, error } = await tv.rpc("rpc_creer_partie");
if (error) throw new Error(`rpc_creer_partie : ${error.message}`);
console.log("Temps réel — partie", partie.code, "\n");

const recus = [];
const abonne = await new Promise((resolve) => {
  const canal = tv
    .channel(`partie:${partie.partie_id}`)
    .on("postgres_changes", { event: "*", schema: "public", table: "joueurs" },
        (p) => recus.push(["joueurs", p.eventType]))
    .on("postgres_changes", { event: "*", schema: "public", table: "parties" },
        (p) => recus.push(["parties", p.eventType]))
    .on("postgres_changes", { event: "*", schema: "public", table: "binomes" },
        (p) => recus.push(["binomes", p.eventType]))
    .subscribe((statut) => {
      if (statut === "SUBSCRIBED") resolve(canal);
      if (statut === "CHANNEL_ERROR" || statut === "TIMED_OUT") resolve(null);
    });
  setTimeout(() => resolve(null), 10_000);
});
ok(abonne !== null, "le plateau s'abonne au canal de la partie");

// --- deux téléphones rejoignent et s'apparient ---
const tels = [];
for (const nom of ["Sam", "Alex"]) {
  const c = neuf();
  await c.auth.signInAnonymously();
  const { data, error: e } = await c.rpc("rpc_rejoindre", {
    p_code: partie.code, p_prenom: nom,
  });
  if (e) throw new Error(`rpc_rejoindre ${nom} : ${e.message}`);
  tels.push({ c, id: data.joueur_id });
}
await tels[0].c.rpc("rpc_apparier", { p_cible: tels[1].id });

// --- on laisse le temps aux messages d'arriver ---
await new Promise((r) => setTimeout(r, 3_000));

const tables = new Set(recus.map(([t]) => t));
ok(recus.length > 0, "des changements arrivent au plateau sans qu'il demande rien",
   `(${recus.length} messages)`);
ok(tables.has("joueurs"), "les arrivées de joueurs sont diffusées");
ok(tables.has("binomes"), "la formation des binômes est diffusée");

// --- et ce qui ne doit JAMAIS être diffusé ---
const espion = neuf();
await espion.auth.signInAnonymously();
const fuite = await new Promise((resolve) => {
  let vu = false;
  espion
    .channel("espion")
    .on("postgres_changes", { event: "*", schema: "public", table: "reponses_prepa" },
        () => { vu = true; })
    .subscribe();
  setTimeout(() => resolve(vu), 4_000);
});
ok(fuite === false, "reponses_prepa n'est jamais diffusée");

console.log(
  ko ? `\n${ko} vérification(s) en échec.`
     : "\n✓ le temps réel arrive, et les tables secrètes restent muettes."
);
process.exit(ko ? 1 : 0);
