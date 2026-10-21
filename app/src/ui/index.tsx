import type { CSSProperties, ReactNode } from "react";
import type { Couleur } from "../jeu/types";

/** Les composants de la DA (voir DA.html). Tout vient des jetons. */

export function Trame({ children, mode = "points", style }: {
  children?: ReactNode;
  mode?: "points" | "rayures" | "aucune";
  style?: CSSProperties;
}) {
  const fond: CSSProperties =
    mode === "points"
      ? {
          backgroundImage:
            "radial-gradient(var(--trame) var(--trame-point), transparent calc(var(--trame-point) + .1px)), radial-gradient(var(--trame) var(--trame-point), transparent calc(var(--trame-point) + .1px))",
          backgroundSize: "var(--trame-pas) var(--trame-pas)",
          backgroundPosition: "0 0, calc(var(--trame-pas)/2) calc(var(--trame-pas)/2)",
        }
      : mode === "rayures"
        ? {
            backgroundImage:
              "repeating-linear-gradient(45deg, var(--trame) 0 2px, transparent 2px var(--trame-pas))",
          }
        : {};
  return <div style={{ ...fond, ...style }}>{children}</div>;
}

export function Panneau({ children, fort = false, style }: {
  children: ReactNode;
  fort?: boolean;
  style?: CSSProperties;
}) {
  return (
    <div
      style={{
        background: "var(--papier)",
        border: `${fort ? "var(--filet-fort)" : "var(--filet)"} solid var(--bord)`,
        boxShadow: "var(--decalage) var(--decalage) 0 var(--ombre)",
        padding: "var(--e-4)",
        ...style,
      }}
    >
      {children}
    </div>
  );
}

/** La voix du jeu : consignes, phases. Jamais une réponse de joueur. */
export function Narration({ children, petit = false }: { children: ReactNode; petit?: boolean }) {
  return (
    <span
      style={{
        display: "inline-block",
        background: "var(--jaune)",
        color: "#15101b",
        border: "var(--filet) solid #15101b",
        padding: petit ? "var(--e-1) var(--e-3)" : "var(--e-2) var(--e-4)",
        fontFamily: "var(--display)",
        textTransform: "uppercase",
        letterSpacing: ".05em",
        fontSize: petit ? "var(--t-s)" : "var(--t-l)",
        transform: "rotate(-1.2deg)",
        boxShadow: "var(--decalage) var(--decalage) 0 var(--ombre)",
      }}
    >
      {children}
    </span>
  );
}

/**
 * Lettrage de couverture.
 *
 * RÈGLE DE LISIBILITÉ, apprise en cassant la DA : le remplissage est
 * TOUJOURS `--texte` sur fond papier. Le jaune est une couleur de FOND,
 * pas de texte : #ffd400 sur blanc donne 1,43:1 quand il en faut 4,5.
 *
 * On avait fait reposer le contraste sur `-webkit-text-stroke`, qui est
 * non standard : là où elle ne s'applique pas, il ne reste que du jaune
 * sur du blanc. Le contour est désormais une DÉCORATION, et la couleur
 * vient de l'ombre portée — qui n'a aucun rôle de contraste.
 *
 * `couleur` ne doit être forcée que sur un fond d'encre (le bandeau).
 * Les accents (rose, bleu, rouge) restent admissibles en GRAND texte —
 * le seuil y est de 3:1 et ils le passent — mais jamais le jaune.
 */
export function Lettrage({ children, taille = "var(--t-2xl)", couleur = "var(--texte)", ombre }: {
  children: ReactNode;
  taille?: string;
  /** à ne changer que sur un fond sombre */
  couleur?: string;
  /** l'aplat de couleur, décalé : c'est lui qui porte la DA */
  ombre?: string;
}) {
  return (
    <span
      style={{
        fontFamily: "var(--display)",
        textTransform: "uppercase",
        fontWeight: 900,
        letterSpacing: ".01em",
        lineHeight: 0.92,
        fontSize: taille,
        color: couleur,
        ...(ombre ? { textShadow: `4px 4px 0 ${ombre}` } : {}),
        textWrap: "balance",
      }}
    >
      {children}
    </span>
  );
}

/**
 * Le même lettrage, mais posé sur un aplat d'encre : c'est le SEUL
 * endroit où le jaune peut porter du texte (13:1 sur l'encre).
 */
export function LettrageSurEncre({ children, taille = "var(--t-2xl)", couleur = "var(--jaune)" }: {
  children: ReactNode;
  taille?: string;
  couleur?: string;
}) {
  return (
    <span
      style={{
        display: "inline-block",
        background: "var(--encre)",
        border: "var(--filet) solid var(--bord)",
        boxShadow: "var(--decalage) var(--decalage) 0 var(--ombre)",
        padding: "var(--e-2) var(--e-4)",
        fontFamily: "var(--display)",
        textTransform: "uppercase",
        fontWeight: 900,
        letterSpacing: ".02em",
        lineHeight: 1,
        fontSize: taille,
        color: couleur,
        textWrap: "balance",
      }}
    >
      {children}
    </span>
  );
}

/** Ce qu'un joueur a dit à voix haute. Le composant central du jeu. */
export function Bulle({ qui, children }: { qui?: string; children: ReactNode }) {
  return (
    <div
      style={{
        position: "relative",
        background: "var(--papier)",
        border: "var(--filet) solid var(--bord)",
        padding: "var(--e-3) var(--e-4)",
        fontSize: "var(--t-l)",
        boxShadow: "var(--decalage) var(--decalage) 0 var(--ombre)",
      }}
    >
      {qui && (
        <strong
          style={{
            display: "block",
            fontFamily: "var(--display)",
            textTransform: "uppercase",
            letterSpacing: ".03em",
            fontSize: "var(--t-s)",
            color: "var(--texte-2)",
          }}
        >
          {qui}
        </strong>
      )}
      {children}
    </div>
  );
}

export function PastilleBinome({ couleur, prenoms, score, present = true }: {
  couleur: Couleur;
  prenoms: string[];
  score?: number;
  present?: boolean;
}) {
  const clair = couleur === "jaune";
  return (
    <span
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: "var(--e-2)",
        border: "var(--filet) solid var(--bord)",
        padding: "var(--e-1) var(--e-3)",
        fontFamily: "var(--display)",
        textTransform: "uppercase",
        letterSpacing: ".05em",
        boxShadow: "4px 4px 0 var(--ombre)",
        background: `var(--${couleur})`,
        color: clair ? "#15101b" : "#fff",
        opacity: present ? 1 : 0.55,
      }}
    >
      {prenoms.join(" & ")}
      {score !== undefined && (
        <span style={{ fontFamily: "var(--donnees)", fontVariantNumeric: "tabular-nums", fontWeight: 700 }}>
          {score}
        </span>
      )}
    </span>
  );
}

/** Le bouton s'enfonce dans son ombre : la mécanique du tampon. */
export function BoutonTampon({ children, onClick, ton = "jaune", disabled, large = true, tc = false }: {
  children: ReactNode;
  onClick?: () => void;
  ton?: "jaune" | "valide" | "refuse" | "neutre";
  disabled?: boolean;
  large?: boolean;
  /** navigable à la télécommande (écran plateau) */
  tc?: boolean;
}) {
  const fonds: Record<string, [string, string]> = {
    jaune: ["var(--jaune)", "#15101b"],
    valide: ["var(--valide)", "var(--sur-semantique)"],
    refuse: ["var(--refuse)", "var(--sur-semantique)"],
    neutre: ["var(--papier-2)", "var(--texte)"],
  };
  const [bg, fg] = fonds[ton] ?? fonds["jaune"]!;
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      {...(tc ? { "data-tc": "" } : {})}
      style={{
        width: large ? "100%" : "auto",
        textAlign: "center",
        cursor: disabled ? "not-allowed" : "pointer",
        fontFamily: "var(--display)",
        textTransform: "uppercase",
        letterSpacing: ".06em",
        fontSize: "var(--t-l)",
        padding: "var(--e-3) var(--e-4)",
        border: "var(--filet) solid var(--bord)",
        background: bg,
        color: fg,
        boxShadow: "var(--decalage) var(--decalage) 0 var(--ombre)",
        opacity: disabled ? 0.5 : 1,
        transition: "transform var(--pop), box-shadow var(--pop)",
      }}
      onPointerDown={(e) => {
        if (disabled) return;
        e.currentTarget.style.transform = "translate(var(--decalage), var(--decalage))";
        e.currentTarget.style.boxShadow = "0 0 0 var(--ombre)";
      }}
      onPointerUp={(e) => {
        e.currentTarget.style.transform = "";
        e.currentTarget.style.boxShadow = "var(--decalage) var(--decalage) 0 var(--ombre)";
      }}
      onPointerLeave={(e) => {
        e.currentTarget.style.transform = "";
        e.currentTarget.style.boxShadow = "var(--decalage) var(--decalage) 0 var(--ombre)";
      }}
    >
      {children}
    </button>
  );
}

export function Verdict({ etat }: { etat: "valide" | "refuse" | "attente" }) {
  const fonds = {
    valide: ["var(--valide)", "var(--sur-semantique)", "Ça compte"],
    refuse: ["var(--refuse)", "var(--sur-semantique)", "Ça compte pas"],
    attente: ["var(--papier-2)", "var(--texte)", "Au vote…"],
  } as const;
  const [bg, fg, mot] = fonds[etat];
  return (
    <span
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: "var(--e-2)",
        padding: "var(--e-2) var(--e-3)",
        border: "var(--filet) solid var(--bord)",
        fontFamily: "var(--display)",
        textTransform: "uppercase",
        letterSpacing: ".06em",
        boxShadow: "4px 4px 0 var(--ombre)",
        background: bg,
        color: fg,
      }}
    >
      {etat === "valide" && (
        <svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true">
          <path d="M2 9l4 4 8-10" fill="none" stroke="currentColor" strokeWidth="3" />
        </svg>
      )}
      {etat === "refuse" && (
        <svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true">
          <path d="M3 3l10 10M13 3L3 13" fill="none" stroke="currentColor" strokeWidth="3" />
        </svg>
      )}
      {mot}
    </span>
  );
}

export function Coeur({ taille = 44, couleur = "var(--zamours)" }: { taille?: number; couleur?: string }) {
  return (
    <svg width={taille} height={taille} viewBox="0 0 100 100" aria-hidden="true">
      <path
        d="M50 88C28 72 8 56 8 36 8 22 19 12 32 12c8 0 15 4 18 10 3-6 10-10 18-10 13 0 24 10 24 24 0 20-20 36-42 52z"
        fill={couleur}
        stroke="var(--encre)"
        strokeWidth="5"
      />
    </svg>
  );
}

export function Eclair({ taille = 44, couleur = "var(--zamis)" }: { taille?: number; couleur?: string }) {
  return (
    <svg width={taille} height={taille} viewBox="0 0 100 100" aria-hidden="true">
      <path
        d="M58 6 22 54h22l-8 40 40-52H52z"
        fill={couleur}
        stroke="var(--encre)"
        strokeWidth="5"
        strokeLinejoin="round"
      />
    </svg>
  );
}

export function Erreur({ children }: { children: ReactNode }) {
  return (
    <div
      role="alert"
      style={{
        border: "var(--filet) solid var(--refuse)",
        background: "var(--papier)",
        color: "var(--texte)",
        padding: "var(--e-3)",
        boxShadow: "4px 4px 0 var(--refuse)",
        fontSize: "var(--t-s)",
      }}
    >
      {children}
    </div>
  );
}
