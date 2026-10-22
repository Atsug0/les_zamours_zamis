#!/usr/bin/env node
// Assemble les captures du déroulé en UNE page autonome : les images
// sont inlinées, donc la planche se partage, s'archive et s'ouvre
// n'importe où sans son dossier.
import { readdirSync, readFileSync, writeFileSync } from "node:fs";

const D = "captures/deroule";
const html = readFileSync(`${D}/index.html`, "utf8");
const images = Object.fromEntries(
  readdirSync(D)
    .filter((f) => f.endsWith(".png"))
    .map((f) => [f, `data:image/png;base64,${readFileSync(`${D}/${f}`).toString("base64")}`])
);
const inline = html.replace(/src="([^"]+\.png)"/g, (m, f) => `src="${images[f] ?? f}"`);
writeFileSync(`${D}/planche.html`, inline);
console.log(`planche.html — ${(Buffer.byteLength(inline) / 1e6).toFixed(1)} Mo, ${Object.keys(images).length} images inlinées`);
