#!/usr/bin/env node
/**
 * Déroule une partie entière dans deux navigateurs côte à côte — la
 * télé et un téléphone — et capture CHAQUE étape des deux points de
 * vue. Produit captures/deroule/index.html : le déroulé complet,
 * image par image, à feuilleter.
 *
 *   node tools/scenario.mjs [binomes|paris|duel|sujet|tournoi]
 *
 * C'est le seul test qui vérifie ce qu'un joueur VOIT. Les assertions
 * SQL disent que l'état est correct ; celui-ci dit que les deux écrans
 * racontent la même histoire, au même moment.
 */
import { chromium } from "playwright";
import { spawn } from "node:child_process";
import { mkdirSync, writeFileSync, rmSync } from "node:fs";

const MODE = process.argv[2] ?? "binomes";
const LIBELLES = {
  binomes: "Binômes",
  paris: "Tous contre le binôme",
  duel: "Duel",
  sujet: "Qui me connaît le mieux",
  tournoi: "Tournoi",
};
const BOTS = MODE === "duel" ? 1 : 3;
const PORT = 4320;
const DOSSIER = "captures/deroule";
const MAX_ETAPES = 160;

const serveur = spawn("npx", ["vite", "preview", "--port", String(PORT), "--strictPort"], { stdio: "ignore" });
for (let i = 0; i < 80; i++) {
  try { if ((await fetch(`http://localhost:${PORT}/`)).ok) break; } catch {}
  await new Promise((r) => setTimeout(r, 250));
}

rmSync(DOSSIER, { recursive: true, force: true });
mkdirSync(DOSSIER, { recursive: true });

const nav = await chromium.launch();
// UN SEUL contexte : deux contextes = deux localStorage = deux sessions
// anonymes, et le téléphone ne serait pas le même joueur que la télé.
// On règle la taille écran par écran.
const ctx = await nav.newContext({ viewport: { width: 1280, height: 800 } });
const tv = await ctx.newPage();
const tel = await ctx.newPage();
await tel.setViewportSize({ width: 390, height: 844 });
const erreurs = [];
tv.on("pageerror", (e) => erreurs.push(`télé : ${e.message}`));
tel.on("pageerror", (e) => erreurs.push(`téléphone : ${e.message}`));

let ko = 0;
const ok = (c, l, d = "") => { console.log(`${c ? "  ok  " : "ÉCHEC "} ${l}${d ? "  " + d : ""}`); if (!c) ko++; };

const etapes = [];
let n = 0;
async function capturer(titre, detail = "") {
  n += 1;
  const base = String(n).padStart(2, "0");
  await Promise.all([
    tv.screenshot({ path: `${DOSSIER}/${base}-tv.png`, fullPage: true }),
    tel.screenshot({ path: `${DOSSIER}/${base}-tel.png`, fullPage: true }),
  ]);
  etapes.push({ n: base, titre, detail });
  console.log(`  ${base}  ${titre}${detail ? " — " + detail : ""}`);
}

/** Où en est la partie, lu sur le plateau — pas deviné sur un libellé. */
const etat = () =>
  tv.evaluate(() => {
    const d = document.querySelector(".plateau-cadre");
    return d
      ? { phase: d.dataset.phase, tour: d.dataset.tour, statut: d.dataset.statut, pause: d.dataset.pause }
      : { phase: "?", tour: "", statut: "", pause: "" };
  });

/** L'humain joue sa part : on remplit, puis on clique la première action. */
async function jouerSonTour() {
  const ignorer = /démo|sauter|plein écran|oublier|y retourner|son/i;
  const champs = tel.locator(".pile input, .tel-cadre input");
  for (let k = 0; k < (await champs.count()); k++) {
    await champs.nth(k).fill("bleu").catch(() => {});
  }
  const boutons = tel.locator(".pile button:not([disabled]), .tel-cadre button:not([disabled])");
  for (let k = 0; k < (await boutons.count()); k++) {
    const t = (await boutons.nth(k).innerText().catch(() => "")) || "";
    if (ignorer.test(t)) continue;
    await boutons.nth(k).click().catch(() => {});
    return t.split("\n")[0].slice(0, 40);
  }
  return null;
}

// ---------------------------------------------------------------
console.log(`\nDéroulé — mode « ${LIBELLES[MODE] ?? MODE} »\n`);
await tv.goto(`http://localhost:${PORT}/`, { waitUntil: "networkidle" });
await tv.getByRole("button", { name: "Partie de démonstration" }).click();
await capturer("L'accueil", "le choix du mode de démonstration");
await tv.getByRole("button", { name: LIBELLES[MODE], exact: true }).click();
await tv.waitForURL(/\/tv\/[A-Z]{4}/, { timeout: 20000 });
const code = tv.url().split("/").pop();
ok(/^[A-HJ-NP-Z]{4}$/.test(code ?? ""), "la partie est créée", code);

await tel.goto(`http://localhost:${PORT}/p/${code}`, { waitUntil: "networkidle" });
await tel.waitForSelector(".tel-cadre", { timeout: 20000 });
await tv.waitForTimeout(2500);
await capturer("Le lobby", "le code, le QR, et les binômes formés");

let avant = "";
let fige = 0;
for (let i = 0; i < MAX_ETAPES; i++) {
  const e = await etat();
  if (e.phase === "palmares") break;

  // Le lobby ne se joue pas comme un tour : on lance, et c'est tout.
  // Cliquer « la première action » y choisirait un mode au hasard.
  if (e.phase === "lobby") {
    const lancer = tel.getByRole("button", { name: /Lancer la partie|Lancer un tournoi/i });
    if (await lancer.count()) await lancer.first().click().catch(() => {});
    await tv.waitForTimeout(2000);
    if (++fige > 8) { ok(false, "impossible de lancer la partie depuis le lobby"); break; }
    continue;
  }

  if (e.phase === "prep") {
    const remplir = tel.getByRole("button", { name: /remplir tout au hasard/i });
    if (await remplir.count()) {
      await capturer("La préparation", "chacun répond sur soi-même, la télé ne montre rien");
      await remplir.first().click();
    }
  } else {
    const cle = `${e.phase}|${e.tour}|${e.statut}`;
    if (cle !== avant) {
      const titres = {
        qcm: "Manche 1 · QCM",
        libre: "Manche 2 · question libre",
        citez3: "Manche « cite 3 »",
        bonus: "La question bonus",
        finale: "La finale",
      };
      const statuts = {
        attente: "la question est posée",
        consigne: "la réponse est consignée",
        vote: "la salle vote",
        revele: "révélation",
        juge: "le verdict",
      };
      await capturer(
        `${titres[e.phase] ?? e.phase}${e.tour ? ` · tour ${e.tour}` : ""}`,
        statuts[e.statut] ?? ""
      );
      avant = cle;
      fige = 0;
    } else if (++fige > 14) {
      ok(false, `bloqué en ${e.phase} (tour ${e.tour}, statut ${e.statut})`);
      break;
    }
  }

  await jouerSonTour();
  await tv.waitForTimeout(1100);
}

const fin = await etat();
if (fin.phase === "palmares") {
  await tv.waitForTimeout(1500);
  await capturer("Le palmarès", "le classement et le récap de la soirée");
}
ok(fin.phase === "palmares", "la partie va jusqu'au palmarès", fin.phase);
ok(erreurs.length === 0, "aucune erreur JS sur les deux écrans", erreurs[0] ?? "");
ok(n >= 6, "le déroulé est capturé étape par étape", `${n} étapes`);

// ---- la planche à feuilleter ----
const html = `<title>Déroulé d'une partie — ${LIBELLES[MODE] ?? MODE}</title>
<style>
:root{--encre:#15101b;--papier:#fff;--jaune:#ffd400;--rouge:#e8112d;--bleu:#0b5fd9;--gris:#5a4b55}
*{box-sizing:border-box}
body{margin:0;background:var(--papier);color:var(--encre);
 font:16px/1.5 Archivo,"Helvetica Neue",Arial,sans-serif;
 background-image:radial-gradient(rgba(232,17,45,.18) 1.6px,transparent 1.7px),radial-gradient(rgba(232,17,45,.18) 1.6px,transparent 1.7px);
 background-size:7px 7px;background-position:0 0,3.5px 3.5px}
header{border-bottom:5px solid var(--encre);background:var(--encre);color:#fff;padding:18px 24px}
h1{margin:0;font:900 28px/1 Impact,"Arial Black",sans-serif;letter-spacing:.04em;text-transform:uppercase;color:var(--jaune)}
header p{margin:6px 0 0;color:#cfc6cc;font-size:14px}
main{max-width:1180px;margin:0 auto;padding:24px}
section{background:#fff;border:3px solid var(--encre);box-shadow:6px 6px 0 var(--encre);margin:0 0 28px;padding:16px}
h2{margin:0;font:900 18px/1.2 Impact,"Arial Black",sans-serif;text-transform:uppercase;letter-spacing:.04em;
 background:var(--jaune);border:3px solid var(--encre);display:inline-block;padding:6px 12px;transform:rotate(-1deg)}
.detail{color:var(--gris);font-size:14px;margin:12px 0 14px}
.paire{display:grid;grid-template-columns:1fr 300px;gap:16px;align-items:start}
@media(max-width:800px){.paire{grid-template-columns:1fr}}
figure{margin:0}
figcaption{font:900 11px/1 Impact,sans-serif;text-transform:uppercase;letter-spacing:.1em;color:var(--gris);margin:0 0 6px}
img{width:100%;display:block;border:3px solid var(--encre);background:#fff}
</style>
<header>
  <h1>Déroulé d'une partie · ${LIBELLES[MODE] ?? MODE}</h1>
  <p>${n} étapes, capturées des deux côtés : la télé et un téléphone, au même instant.</p>
</header>
<main>
${etapes
  .map(
    (e) => `  <section>
    <h2>${e.n} · ${e.titre}</h2>
    ${e.detail ? `<p class="detail">${e.detail}</p>` : ""}
    <div class="paire">
      <figure><figcaption>La télé</figcaption><img src="${e.n}-tv.png" alt="plateau, étape ${e.n}"></figure>
      <figure><figcaption>Le téléphone</figcaption><img src="${e.n}-tel.png" alt="pupitre, étape ${e.n}"></figure>
    </div>
  </section>`
  )
  .join("\n")}
</main>`;
writeFileSync(`${DOSSIER}/index.html`, html);
console.log(`\n→ ${DOSSIER}/index.html`);

await nav.close();
serveur.kill("SIGTERM");
console.log(ko ? `\n${ko} vérification(s) en échec.` : "\n✓ le déroulé complet est capturé des deux points de vue");
process.exit(ko ? 1 : 0);
