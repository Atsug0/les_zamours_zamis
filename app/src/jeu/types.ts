export type Mode = "zamours" | "zamis";
export type Couleur = "rouge" | "jaune" | "bleu" | "vert" | "orange" | "violet";
export type Etat =
  | "lobby" | "prep" | "qcm" | "libre" | "citez3" | "bonus" | "finale" | "palmares";
export type Manche = "qcm" | "libre" | "citez3" | "bonus";
export type StatutTour = "attente" | "consigne" | "revele" | "vote" | "juge";
export type Jugement = "attente" | "juste" | "faux" | "passee";

export type ModeJeu = "binomes" | "sujet" | "duel";

export interface Partie {
  id: string;
  code: string;
  etat: Etat;
  mode_jeu: ModeJeu;
  /** en mode sujet : la personne qu'on doit deviner, et qui valide */
  sujet_id: string | null;
  plateau_id: string;
  hote_id: string | null;
  presentateur_id: string | null;
  format: "court" | "long";
  reglages: Reglages;
  tirage: Record<string, TirageMode>;
  tour_courant: string | null;
  avec_citez3: boolean;
  en_pause: boolean;
  pause_motif: string | null;
}

export interface Reglages {
  questionsFinale: number;
  seuilFinale: number;
  chronoFinaleMs: number;
  fenetreVoteMs: number;
  fenetreBonusMs: number;
  toleranceNumerique: number;
}

export interface TirageMode {
  ouvertes: string[];
  qcm: string[];
  bonus: string;
  finale: string;
  sensibles: boolean;
  occasions: string[];
}

export interface Joueur {
  id: string;
  partie_id: string;
  prenom: string;
  binome_id: string | null;
  role: "A" | "B" | null;
  vu_le: string;
  present: boolean;
  a_choisi_mode: boolean;
  prepa_faites: number;
  /** choix en attente d'accord du partenaire — pas un secret, les deux doivent s'aligner */
  mode_choisi: Mode | null;
  sensibles_choisi: boolean;
  occasions_choisies: string[];
}

export interface Progression {
  partie_id: string;
  termines: number;
  total: number;
  questions_par_joueur: number;
}

export interface Binome {
  id: string;
  partie_id: string;
  mode: Mode | null;
  couleur: Couleur;
  score: number;
  verrouille: boolean;
  sensibles: boolean;
  occasions: string[];
}

export interface Tour {
  id: string;
  partie_id: string;
  ordre: number;
  manche: Manche;
  binome_id: string;
  question_id: string;
  repondant_id: string | null;
  questionneur_id: string | null;
  statut: StatutTour;
  vote_fin_at: string | null;
  verdict: boolean | null;
  points: number;
  reponse_donnee: string | null;
  /** null tant que le tour n'est pas révélé — le serveur ne l'envoie pas. */
  reponse_revelee: string | null;
  voix_pour: number | null;
  voix_contre: number | null;
  j_ai_vote: boolean;
  /** mode sujet : compteurs diffusés, car reponses_manche est muette */
  reponses_recues: number;
  revision: number;
  j_ai_repondu: boolean;
  /** duel : une contestation a déjà été utilisée sur ce tour */
  contestee: boolean;
}

export interface ReponseManche {
  tour_id: string;
  joueur_id: string;
  prenom: string;
  /** null tant que le tour n'est pas révélé */
  valeur: string | null;
  juste: boolean | null;
  c_est_moi: boolean;
}

export interface PassageFinale {
  id: string;
  partie_id: string;
  binome_id: string;
  ordre: number;
  joueur_id: string | null;
  questionneur_id: string | null;
  serie_id: string | null;
  jugements: Jugement[];
  chrono_fin_at: string | null;
  chrono_restant_ms: number | null;
  seuil_atteint: boolean | null;
  points: number;
}

export interface LignePalmares {
  partie_id: string;
  binome_id: string;
  couleur: Couleur;
  mode: Mode | null;
  score: number;
  rang: number;
  prenoms: string[];
  points_finale: number | null;
  seuil_atteint: boolean | null;
}

export interface LigneRecap {
  partie_id: string;
  ordre: number;
  manche: Manche;
  binome_id: string;
  question_id: string;
  reponse_donnee: string | null;
  reponse_revelee: string | null;
  verdict: boolean | null;
  points: number;
  repondant: string | null;
}
