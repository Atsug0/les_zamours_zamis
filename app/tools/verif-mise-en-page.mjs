#!/usr/bin/env node
// Vérifie qu'AUCUNE page ne déborde horizontalement, et prend des
// captures pour qu'on puisse les regarder.
//
//   cd app && npm run build && node tools/verif-mise-en-page.mjs
//
// Le test objectif est simple : si documentElement.scrollWidth dépasse
// la largeur de la fenêtre, quelque chose sort du cadre. C'est ce qui
// manquait — « ça sort du cadre » ne se voit pas dans un typage.
import { chromium } from "playwright";
import { spawn } from "node:child_process";
import { mkdirSync } from "node:fs";

const PORT = 4317;
const ECRANS = [
  { nom: "iphone-se", w: 375, h: 667 },
  { nom: "iphone-14", w: 390, h: 844 },
  { nom: "pixel-etroit", w: 320, h: 720 },
  { nom: "tablette", w: 820, h: 1180 },
  { nom: "television", w: 1920, h: 1080 },
];
const PAGES = [
  { nom: "accueil", chemin: "/" },
  { nom: "plateau", chemin: "/tv/ABCD" },
  { nom: "pupitre", chemin: "/p/ABCD" },
];

const serveur = spawn("npx", ["vite", "preview", "--port", String(PORT), "--strictPort"], {
  stdio: "ignore",
  detached: false,
});
const fin = async () => {
  serveur.kill("SIGTERM");
};
process.on("exit", fin);

// on attend que le serveur réponde
await new Promise(async (r) => {
  for (let i = 0; i < 60; i++) {
    try {
      const rep = await fetch(`http://localhost:${PORT}/`);
      if (rep.ok) return r();
    } catch {}
    await new Promise((x) => setTimeout(x, 250));
  }
  r();
});

mkdirSync("captures", { recursive: true });
const navigateur = await chromium.launch();
let ko = 0;

for (const p of PAGES) {
  for (const e of ECRANS) {
    const ctx = await navigateur.newContext({
      viewport: { width: e.w, height: e.h },
      deviceScaleFactor: 1,
    });
    const page = await ctx.newPage();
    const erreurs = [];
    page.on("pageerror", (ex) => erreurs.push(ex.message));
    await page.goto(`http://localhost:${PORT}${p.chemin}`, { waitUntil: "networkidle" });
    await page.waitForTimeout(400);

    // Une police qui ne charge pas ne produit aucune erreur : la page
    // retombe sur un repli système et la DA disparaît en silence.
    if (p.nom === "accueil" && e.nom === "iphone-14") {
      const polices = await page.evaluate(async () => {
        await document.fonts.ready;
        return { bangers: document.fonts.check("16px Bangers"),
                 archivo: document.fonts.check("16px Archivo") };
      });
      if (!polices.bangers || !polices.archivo) {
        console.log(`ÉCHEC  polices : Bangers=${polices.bangers} Archivo=${polices.archivo}`);
        ko++;
      } else {
        console.log("  ok   polices  Bangers et Archivo chargées, pas de repli système");
      }
    }

    const mesure = await page.evaluate(() => {
      const racine = document.documentElement;
      // tous les éléments qui dépassent à droite ou à gauche
      const coupables = [...document.querySelectorAll("*")]
        .filter((n) => {
          const r = n.getBoundingClientRect();
          return r.width > 0 && (r.right > window.innerWidth + 1 || r.left < -1);
        })
        .slice(0, 4)
        .map((n) => `${n.tagName.toLowerCase()}${n.className ? "." + String(n.className).split(" ")[0] : ""} (${Math.round(n.getBoundingClientRect().right)}px)`);
      return { scroll: racine.scrollWidth, fenetre: window.innerWidth, coupables };
    });

    const debordement = mesure.scroll > mesure.fenetre + 1;
    const etat = debordement || erreurs.length ? "ÉCHEC " : "  ok  ";
    if (debordement || erreurs.length) ko++;
    console.log(
      `${etat} ${p.nom.padEnd(8)} ${e.nom.padEnd(13)} ${e.w}px` +
        (debordement ? `  -> déborde de ${mesure.scroll - mesure.fenetre}px : ${mesure.coupables.join(", ")}` : "") +
        (erreurs.length ? `  -> erreur JS : ${erreurs[0]}` : "")
    );
    if (e.nom === "iphone-14" || e.nom === "television") {
      await page.screenshot({ path: `captures/${p.nom}-${e.nom}.png`, fullPage: true });
    }
    await ctx.close();
  }
}

await navigateur.close();
await fin();
console.log(ko ? `\n${ko} page(s) en échec.` : "\n✓ aucune page ne déborde, aucune erreur JS");
process.exit(ko ? 1 : 0);
