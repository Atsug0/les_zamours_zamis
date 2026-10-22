/**
 * Les sons du plateau.
 *
 * Tout est SYNTHÉTISÉ à la volée : aucun fichier, aucun octet de bundle,
 * aucune dépendance. Les jingles de l'émission d'origine sont protégés —
 * ce sont donc des sons originaux, écrits dans le même registre : des
 * timbres francs, des attaques nettes, rien de feutré. Le pendant sonore
 * d'un aplat cerné de noir.
 *
 * SEUL LE PLATEAU SONNE. Huit téléphones qui buzzent avec des latences
 * différentes, c'est une cacophonie ; la télé est l'enceinte, comme elle
 * est déjà l'horloge et la scène.
 */

type Cue =
  | "arrivee"      // un joueur rejoint
  | "depart"       // la partie se lance
  | "question"     // une question s'affiche
  | "roulement"    // juste avant une révélation
  | "revelation"   // l'éclat
  | "juste"        // ça concorde
  | "faux"         // ça ne concorde pas
  | "vote"         // une voix tombe
  | "tic"          // dernières secondes du chrono
  | "prime"        // le seuil de finale est atteint
  | "victoire";    // le palmarès

let ctx: AudioContext | null = null;
let maitre: GainNode | null = null;
let bruitBlanc: AudioBuffer | null = null;

const CLE = "zamours.muet";
let muet = (() => {
  try {
    return localStorage.getItem(CLE) === "1";
  } catch {
    return false;
  }
})();

/**
 * Les navigateurs refusent de produire du son avant un geste de
 * l'utilisateur. On crée donc le contexte au premier clic ou à la
 * première touche, et on n'y pense plus.
 */
export function reveillerLeSon() {
  if (ctx) {
    if (ctx.state === "suspended") void ctx.resume();
    return;
  }
  const C = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
  if (!C) return;
  ctx = new C();
  maitre = ctx.createGain();
  maitre.gain.value = muet ? 0 : 0.5;
  maitre.connect(ctx.destination);

  // un peu de bruit blanc, pour les percussions et le buzzer
  const n = ctx.sampleRate * 1.2;
  bruitBlanc = ctx.createBuffer(1, n, ctx.sampleRate);
  const d = bruitBlanc.getChannelData(0);
  for (let i = 0; i < n; i++) d[i] = Math.random() * 2 - 1;
}

export function estMuet() {
  return muet;
}

export function basculerLeSon() {
  muet = !muet;
  try {
    localStorage.setItem(CLE, muet ? "1" : "0");
  } catch {
    /* navigation privée : tant pis, le réglage ne survivra pas */
  }
  if (maitre && ctx) maitre.gain.setTargetAtTime(muet ? 0 : 0.5, ctx.currentTime, 0.02);
  return muet;
}

/** Une note : forme d'onde, hauteur, durée, et une enveloppe franche. */
function note(
  freq: number,
  debut: number,
  duree: number,
  forme: OscillatorType = "square",
  volume = 0.25,
  glissando?: number
) {
  if (!ctx || !maitre) return;
  const o = ctx.createOscillator();
  const g = ctx.createGain();
  o.type = forme;
  o.frequency.setValueAtTime(freq, debut);
  if (glissando) o.frequency.exponentialRampToValueAtTime(Math.max(40, glissando), debut + duree);
  // attaque quasi instantanée : c'est ce qui donne le côté « imprimé »
  g.gain.setValueAtTime(0.0001, debut);
  g.gain.exponentialRampToValueAtTime(volume, debut + 0.008);
  g.gain.exponentialRampToValueAtTime(0.0001, debut + duree);
  o.connect(g).connect(maitre);
  o.start(debut);
  o.stop(debut + duree + 0.02);
}

/** Une frappe de percussion, pour le roulement et le buzzer. */
function frappe(debut: number, duree: number, filtre: number, volume = 0.3) {
  if (!ctx || !maitre || !bruitBlanc) return;
  const s = ctx.createBufferSource();
  s.buffer = bruitBlanc;
  const f = ctx.createBiquadFilter();
  f.type = "bandpass";
  f.frequency.value = filtre;
  f.Q.value = 1.2;
  const g = ctx.createGain();
  g.gain.setValueAtTime(volume, debut);
  g.gain.exponentialRampToValueAtTime(0.0001, debut + duree);
  s.connect(f).connect(g).connect(maitre);
  s.start(debut);
  s.stop(debut + duree + 0.02);
}

export function jouer(cue: Cue) {
  if (muet) return;
  reveillerLeSon();
  if (!ctx) return;
  const t = ctx.currentTime;

  switch (cue) {
    case "arrivee": // deux notes montantes, brèves
      note(660, t, 0.07, "square", 0.18);
      note(880, t + 0.07, 0.1, "square", 0.18);
      break;

    case "depart": // la petite fanfare d'ouverture
      [523, 659, 784, 1047].forEach((f, i) => note(f, t + i * 0.09, 0.14, "square", 0.22));
      note(1319, t + 0.38, 0.3, "triangle", 0.2);
      break;

    case "question": // un claquement sec, comme une case qui tombe
      note(440, t, 0.06, "square", 0.16, 300);
      frappe(t, 0.05, 1800, 0.12);
      break;

    case "roulement": // tambour qui accélère
      for (let i = 0; i < 16; i++) {
        frappe(t + i * (0.07 - i * 0.002), 0.045, 220 + i * 12, 0.1 + i * 0.012);
      }
      break;

    case "revelation": // l'éclat : un accord qui s'ouvre
      [523, 784, 1047].forEach((f, i) => note(f, t + i * 0.02, 0.35, "sawtooth", 0.16));
      frappe(t, 0.25, 900, 0.18);
      break;

    case "juste": // deux notes claires, vers le haut
      note(784, t, 0.09, "triangle", 0.26);
      note(1175, t + 0.08, 0.22, "triangle", 0.26);
      break;

    case "faux": // le buzzer : grave, sale, court
      note(150, t, 0.3, "sawtooth", 0.22, 90);
      frappe(t, 0.28, 180, 0.16);
      break;

    case "vote": // une voix qui tombe sur le tableau
      note(1046, t, 0.05, "square", 0.12);
      break;

    case "tic": // dernières secondes
      note(1600, t, 0.035, "square", 0.14);
      break;

    case "prime": // la prime de finale, montante
      [523, 659, 784, 1047, 1319].forEach((f, i) =>
        note(f, t + i * 0.07, 0.18, "square", 0.24)
      );
      break;

    case "victoire": // le palmarès
      [523, 659, 784].forEach((f, i) => note(f, t + i * 0.1, 0.5, "triangle", 0.2));
      [1047, 1319].forEach((f, i) => note(f, t + 0.3 + i * 0.12, 0.6, "square", 0.18));
      frappe(t + 0.3, 0.5, 700, 0.14);
      break;
  }
}
