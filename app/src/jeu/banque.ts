import brut from "../contenu/questions.json";
import type { Mode } from "./types";

/**
 * Accès au texte des questions. La banque est embarquée dans le bundle :
 * la base ne connaît que les identifiants (ARCHITECTURE.md §3.e).
 *
 * Règle absolue : aucun énoncé ne contient de pronom de genre. La forme
 * de jeu porte un {P} qu'on remplace par le prénom (BANQUE.md §2).
 */
interface Enonce {
  prepa: string;
  jeu: string;
  props?: string[];
  verifiable?: boolean;
}
interface Paire {
  id: string;
  theme: string;
  modes: Mode[];
  diff: number;
  sensible: boolean;
  tol?: string;
  occasion?: string;
  jumeau?: string;
  a: Enonce;
  b: Enonce;
}
interface Bonus {
  id: string;
  modes: Mode[];
  diff: number;
  sensible?: boolean;
  occasion?: string;
  enonce: string;
}
interface SerieFinale {
  id: string;
  titre: string;
  modes: Mode[];
  occasion?: string;
  questions: { prepa: string; jeu: string }[];
}

const banque = brut as unknown as {
  version: string;
  paires_ouvertes: Paire[];
  paires_qcm: Paire[];
  bonus: Bonus[];
  series_finale: SerieFinale[];
  citez_trois: { id: string; modes: Mode[]; enonce: string }[];
};

const paires = new Map<string, Paire>();
for (const p of [...banque.paires_ouvertes, ...banque.paires_qcm]) paires.set(p.id, p);
const bonus = new Map(banque.bonus.map((b) => [b.id, b]));
const series = new Map(banque.series_finale.map((s) => [s.id, s]));

export const version = banque.version;

/** Remplace {P} par le prénom du partenaire. */
export function avecPrenom(texte: string, prenom: string): string {
  return texte.replaceAll("{P}", prenom);
}

export interface Question {
  id: string;
  /** posé au joueur sur lui-même, au tutoiement */
  prepa: string;
  /** affiché sur la télé, {P} déjà remplacé si un prénom est fourni */
  jeu: string;
  props?: string[];
  verifiable: boolean;
  theme?: string;
  tol?: string;
}

/**
 * Résout n'importe quel identifiant : 'quo-01.a', 'bon-02',
 * 'fin-gouts.3'. Renvoie null si l'id est inconnu — ça ne doit pas
 * arriver, mais un écran ne doit jamais planter pour autant.
 */
export function question(id: string, prenom = "{P}"): Question | null {
  const slot = id.endsWith(".a") ? "a" : id.endsWith(".b") ? "b" : null;
  if (slot) {
    const p = paires.get(id.slice(0, -2));
    if (!p) return null;
    const e = slot === "a" ? p.a : p.b;
    return {
      id,
      prepa: e.prepa,
      jeu: avecPrenom(e.jeu, prenom),
      ...(e.props ? { props: e.props } : {}),
      verifiable: e.verifiable === true,
      theme: p.theme,
      ...(p.tol ? { tol: p.tol } : {}),
    };
  }

  const b = bonus.get(id);
  if (b) {
    return { id, prepa: b.enonce, jeu: avecPrenom(b.enonce, prenom), verifiable: false };
  }

  const m = /^(.*)\.(\d+)$/.exec(id);
  if (m && m[1] && m[2]) {
    const s = series.get(m[1]);
    const q = s?.questions[Number(m[2]) - 1];
    if (q) {
      return { id, prepa: q.prepa, jeu: avecPrenom(q.jeu, prenom), verifiable: false };
    }
  }
  return null;
}

export function titreSerie(id: string): string {
  return series.get(id)?.titre ?? "La finale";
}
