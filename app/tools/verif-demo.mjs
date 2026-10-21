#!/usr/bin/env node
// Déroule une partie de démonstration dans un VRAI navigateur, contre
// la vraie base. C'est le seul test qui exerce la chaîne complète :
// session anonyme, temps réel, orchestration du plateau, bots.
import { chromium } from "playwright";
import { spawn } from "node:child_process";
import { mkdirSync } from "node:fs";

const PORT = 4319;
const serveur = spawn("npx", ["vite", "preview", "--port", String(PORT), "--strictPort"], { stdio: "ignore" });
for (let i = 0; i < 80; i++) {
  try { if ((await fetch(`http://localhost:${PORT}/`)).ok) break; } catch {}
  await new Promise((r) => setTimeout(r, 250));
}

mkdirSync("captures", { recursive: true });
const b = await chromium.launch();
const ctx = await b.newContext({ viewport: { width: 1280, height: 800 } });
const page = await ctx.newPage();
const erreurs = [];
page.on("pageerror", (e) => erreurs.push(e.message));

let ko = 0;
const ok = (c, l, d = "") => { console.log(`${c ? "  ok  " : "ÉCHEC "} ${l}${d ? "  " + d : ""}`); if (!c) ko++; };

await page.goto(`http://localhost:${PORT}/`, { waitUntil: "networkidle" });
await page.getByRole("button", { name: "Partie de démonstration" }).click();
await page.getByRole("button", { name: "Binômes", exact: true }).click();
await page.waitForURL(/\/tv\/[A-Z]{4}/, { timeout: 20000 });
const code = page.url().split("/").pop();
ok(/^[A-HJ-NP-Z]{4}$/.test(code ?? ""), "la démo crée une partie et ouvre le plateau", code);

// le lobby doit montrer les bots
await page.waitForTimeout(2500);
const texte = await page.locator("body").innerText();
// le CSS met les prénoms en capitales : innerText rend le texte AFFICHÉ
ok(/bot /i.test(texte), "les bots sont dans le lobby");
await page.screenshot({ path: "captures/demo-lobby.png" });

// on lance depuis le pupitre, dans un second onglet
const tel = await ctx.newPage();
await tel.goto(`http://localhost:${PORT}/p/${code}`, { waitUntil: "networkidle" });
await tel.waitForTimeout(1500);
const lancer = tel.getByRole("button", { name: /Lancer la partie/i });
ok(await lancer.count() > 0, "le pupitre propose de lancer");
await lancer.first().click();
await tel.waitForTimeout(2500);

// la prépa : on la remplit au hasard
const remplir = tel.getByRole("button", { name: /remplir tout au hasard/i });
if (await remplir.count()) { await remplir.first().click(); ok(true, "la prépa se remplit d'un coup"); }
await page.waitForTimeout(4000);
await page.screenshot({ path: "captures/demo-prep.png" });

// les bots font avancer la partie
let etats = new Set();
for (let i = 0; i < 24; i++) {
  await page.waitForTimeout(2000);
  const phase = await page.locator("header").innerText().catch(() => "");
  // l'en-tête contient plusieurs lignes : on cherche celle du code
  const m = /[A-Z]{4} · (.+)/.exec(phase);
  if (m && m[1]) etats.add(m[1].trim());
  // L'humain joue sa part. On ne devine pas les libellés — ils changent
  // d'un mode à l'autre : on remplit les champs présents, puis on clique
  // la première action proposée, en écartant les commandes de service.
  const ignorer = /démo|sauter|plein écran|oublier|y retourner/i;
  const champs = tel.locator(".pile input");
  for (let k = 0; k < (await champs.count()); k++) {
    await champs.nth(k).fill("bleu").catch(() => {});
  }
  const boutons = tel.locator(".pile button:not([disabled])");
  for (let k = 0; k < (await boutons.count()); k++) {
    const libelle = (await boutons.nth(k).innerText().catch(() => "")) || "";
    if (ignorer.test(libelle)) continue;
    await boutons.nth(k).click().catch(() => {});
    break;
  }
}
await page.screenshot({ path: "captures/demo-manche.png", fullPage: true });
console.log("  phases traversées :", [...etats].join(" → ") || "aucune");
ok(etats.size >= 2, "la partie avance toute seule à travers les phases");
ok(erreurs.length === 0, "aucune erreur JS sur le plateau", erreurs[0] ?? "");

await b.close();
serveur.kill("SIGTERM");
console.log(ko ? `\n${ko} vérification(s) en échec.` : "\n✓ une partie de démo se déroule dans un vrai navigateur");
process.exit(ko ? 1 : 0);
