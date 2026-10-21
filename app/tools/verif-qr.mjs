// Vérifie que le QR qu'on affiche se SCANNE vraiment.
//
// On encode une URL de partie, on rastérise la matrice comme le ferait
// un téléphone qui photographie la télé, puis on la redécode avec un
// décodeur INDÉPENDANT de l'encodeur. Un QR qui ne se décode pas est
// un bug invisible à l'œil : il faut le tester, pas le regarder.
import qrcode from "qrcode-generator";
import jsQR from "jsqr";

const MODULE = 8; // pixels par module
const MARGE = 2; // en modules, comme le composant

function rasteriser(valeur) {
  const t = qrcode(0, "M");
  t.addData(valeur);
  t.make();
  const n = t.getModuleCount();
  const cote = (n + MARGE * 2) * MODULE;
  const px = new Uint8ClampedArray(cote * cote * 4).fill(255);

  for (let y = 0; y < n; y++) {
    for (let x = 0; x < n; x++) {
      if (!t.isDark(y, x)) continue;
      for (let dy = 0; dy < MODULE; dy++) {
        for (let dx = 0; dx < MODULE; dx++) {
          const px0 = ((y + MARGE) * MODULE + dy) * cote + (x + MARGE) * MODULE + dx;
          px[px0 * 4] = 0;
          px[px0 * 4 + 1] = 0;
          px[px0 * 4 + 2] = 0;
        }
      }
    }
  }
  return { px, cote, version: (n - 17) / 4 };
}

const cas = [
  "https://leszamours.app/p/ABCD",
  "https://les-zamours-zamis.pages.dev/p/WQKP",
  // le pire cas réaliste : un sous-domaine d'hébergeur, bien plus long
  "https://les-zamours-zamis-preview-42.firebaseapp.com/p/ZFTR",
];

let ko = 0;
for (const valeur of cas) {
  const { px, cote, version } = rasteriser(valeur);
  const lu = jsQR(px, cote, cote);
  const ok = lu && lu.data === valeur;
  console.log(
    `${ok ? "  ok  " : "ÉCHEC "} v${version} ${cote}px  ${valeur}` +
      (ok ? "" : `  -> décodé : ${lu ? lu.data : "illisible"}`)
  );
  if (!ok) ko++;
}

if (ko) {
  console.error(`\n${ko} QR sur ${cas.length} ne se décodent pas.`);
  process.exit(1);
}
console.log(`\n✓ les ${cas.length} QR se décodent, encodeur et décodeur indépendants`);
