// questions.json et tokens.css sont les sources uniques : on les copie
// dans le bundle plutôt que de les dupliquer à la main
// (voir BANQUE.md et DA.html).
import { copyFileSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ici = dirname(fileURLToPath(import.meta.url));
const copies = [
  ["../../questions.json", "../src/contenu/questions.json"],
  ["../../tokens.css", "../src/styles/tokens.css"],
];

for (const [de, vers] of copies) {
  const src = resolve(ici, de);
  const dst = resolve(ici, vers);
  mkdirSync(dirname(dst), { recursive: true });
  copyFileSync(src, dst);
  console.log(`copié  ${de.replace("../../", "")}`);
}
