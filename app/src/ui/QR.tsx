import qrcode from "qrcode-generator";

/**
 * QR code rendu en SVG, dans le registre de la DA : modules d'encre
 * carrés, filet épais, aucun arrondi, aucun flou.
 *
 * L'encodeur est une lib éprouvée (correction d'erreur Reed-Solomon) :
 * écrire ça à la main produit silencieusement des codes illisibles.
 * Le rendu, lui, est à nous — c'est là qu'est le travail de DA.
 *
 * Vérifié de bout en bout par tools/verif-qr.mjs : on encode, on
 * rastérise, et on redécode avec un décodeur indépendant.
 */
export function QR({ valeur, taille = 220, marge = 2 }: {
  valeur: string;
  taille?: number;
  /** zone de silence, en modules. 2 est le minimum qui scanne de façon fiable. */
  marge?: number;
}) {
  // typeNumber 0 = la lib choisit la plus petite version qui tient.
  // 'M' = ~15 % de correction : assez pour une télé filmée de travers.
  const t = qrcode(0, "M");
  t.addData(valeur);
  t.make();

  const n = t.getModuleCount();
  const total = n + marge * 2;
  const chemins: string[] = [];

  for (let y = 0; y < n; y++) {
    for (let x = 0; x < n; x++) {
      if (t.isDark(y, x)) {
        chemins.push(`M${x + marge},${y + marge}h1v1h-1z`);
      }
    }
  }

  return (
    <svg
      viewBox={`0 0 ${total} ${total}`}
      width={taille}
      height={taille}
      role="img"
      aria-label={`QR code vers ${valeur}`}
      style={{
        border: "var(--filet) solid var(--bord)",
        boxShadow: "var(--decalage) var(--decalage) 0 var(--ombre)",
        display: "block",
        // les modules doivent rester nets quand la télé agrandit l'image
        imageRendering: "pixelated",
        shapeRendering: "crispEdges",
      }}
    >
      {/* fond toujours clair : un QR en négatif ne scanne pas sur tous les téléphones */}
      <rect width={total} height={total} fill="#ffffff" />
      <path d={chemins.join("")} fill="#15101b" />
    </svg>
  );
}
