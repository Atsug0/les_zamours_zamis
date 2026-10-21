import { supabase } from "./supabase";
import type { Jugement, Mode } from "./types";

/**
 * Enveloppes typées des fonctions Postgres. Le client n'écrit JAMAIS
 * dans les tables : tout passe par ici (ARCHITECTURE.md §3.a).
 */
async function appel<T>(nom: string, args: Record<string, unknown> = {}): Promise<T> {
  const { data, error } = await supabase.rpc(nom, args);
  if (error) {
    // Les messages des fonctions sont écrits pour être montrés tels quels.
    throw new Error(error.message.replace(/^.*?:\s*/, ""));
  }
  return data as T;
}

export const rpc = {
  // ---- lobby ----
  creerPartie: () => appel<{ partie_id: string; code: string; etat: string }>("rpc_creer_partie"),

  rejoindre: (code: string, prenom: string) =>
    appel<{ partie_id: string; joueur_id: string; prenom: string; pin: string; reprise: boolean }>(
      "rpc_rejoindre",
      { p_code: code, p_prenom: prenom }
    ),

  apparier: (cible: string) =>
    appel<{ binome_id: string; couleur: string }>("rpc_apparier", { p_cible: cible }),

  choisirMode: (mode: Mode, sensibles = false, occasions: string[] = []) =>
    appel<{ accord: boolean; attend: boolean }>("rpc_choisir_mode", {
      p_mode: mode,
      p_sensibles: sensibles,
      p_occasions: occasions,
    }),

  devenirPresentateur: () => appel<{ presentateur_id: string }>("rpc_devenir_presentateur"),

  reprendreSiege: (code: string, prenom: string, pin: string) =>
    appel<{ partie_id: string; joueur_id: string; prenom: string }>("rpc_reprendre_siege", {
      p_code: code,
      p_prenom: prenom,
      p_pin: pin,
    }),

  reclamerPlateau: (code: string) =>
    appel<{ partie_id: string; plateau_id: string }>("rpc_reclamer_plateau", { p_code: code }),

  // ---- lancement et préparation ----
  lancer: (format: "court" | "long" = "court") =>
    appel<{ etat: string; tours: number }>("rpc_lancer", { p_format: format }),

  mesQuestions: () =>
    appel<{ role: "A" | "B"; mode: Mode; questions: string[]; total: number }>("rpc_mes_questions"),

  mesReponses: () =>
    appel<Record<string, { valeur: string; passee: boolean }>>("rpc_mes_reponses"),

  repondrePrepa: (question: string, valeur: string, passee = false) =>
    appel<{ faites: number; total: number; termine: boolean }>("rpc_repondre_prepa", {
      p_question: question,
      p_valeur: valeur,
      p_passee: passee,
    }),

  // ---- manches ----
  consigner: (tour: string, valeur: string) =>
    appel<{ statut: string; verdict?: boolean; reponse_revelee?: string }>("rpc_consigner", {
      p_tour: tour,
      p_valeur: valeur,
    }),

  reveler: (tour: string) =>
    appel<{
      statut: string;
      reponse_donnee: string;
      reponse_revelee: string;
      vote_fin_at: string;
      votants: number;
    }>("rpc_reveler", { p_tour: tour }),

  voter: (tour: string, pour: boolean) =>
    appel<{ vote_enregistre: boolean; tous_ont_vote: boolean }>("rpc_voter", {
      p_tour: tour,
      p_pour: pour,
    }),

  cloreVote: (tour: string) =>
    appel<{
      statut: string;
      verdict?: boolean;
      pour?: number;
      contre?: number;
      arbitrage_requis?: boolean;
    }>("rpc_clore_vote", { p_tour: tour }),

  arbitrer: (tour: string, pour: boolean) =>
    appel<{ statut: string; verdict: boolean }>("rpc_arbitrer", { p_tour: tour, p_pour: pour }),

  sauterTour: (tour: string) => appel<{ saute: boolean }>("rpc_sauter_tour", { p_tour: tour }),

  // ---- présence et pause ----
  pouls: () => appel<{ partie_id: string | null }>("rpc_pouls"),
  geler: (motif = "absence") => appel<{ en_pause: boolean }>("rpc_geler", { p_motif: motif }),
  degeler: () => appel<{ en_pause: boolean }>("rpc_degeler"),
  verifierPresence: () =>
    appel<{ en_pause: boolean; attend: string[] }>("rpc_verifier_presence"),

  // ---- finale ----
  designerFinaliste: (passage: string, joueur: string) =>
    appel<{ joueur_id: string }>("rpc_designer_finaliste", {
      p_passage: passage,
      p_joueur: joueur,
    }),

  demarrerPassage: (passage: string) =>
    appel<{
      chrono_fin_at: string;
      serie_id: string;
      questions: { question_id: string; attendue: string | null; passee: boolean | null }[];
    }>("rpc_demarrer_passage", { p_passage: passage }),

  juger: (passage: string, index: number, jugement: Jugement) =>
    appel<{ jugements: Jugement[]; restantes: number; justes: number }>("rpc_juger", {
      p_passage: passage,
      p_index: index,
      p_jugement: jugement,
    }),

  clorePassage: (passage: string) =>
    appel<{ justes: number; seuil_atteint: boolean; prime: number; points: number }>(
      "rpc_clore_passage",
      { p_passage: passage }
    ),

  // ---- machine à états ----
  suivant: () => appel<{ etat: string; tour_id?: string; passage_courant?: string }>("rpc_suivant"),
};
