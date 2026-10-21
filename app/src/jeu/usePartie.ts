import { useCallback, useEffect, useRef, useState } from "react";
import { supabase } from "./supabase";
import { rpc } from "./rpc";
import type {
  Binome, Joueur, LignePalmares, LigneRecap, Partie, PassageFinale, Progression, Tour,
} from "./types";

export interface Etat {
  partie: Partie | null;
  joueurs: Joueur[];
  binomes: Binome[];
  tours: Tour[];
  passages: PassageFinale[];
  progression: Progression | null;
  palmares: LignePalmares[];
  recap: LigneRecap[];
  moi: string | null;
  chargement: boolean;
  erreur: string | null;
}

const vide: Etat = {
  partie: null,
  joueurs: [],
  binomes: [],
  tours: [],
  passages: [],
  progression: null,
  palmares: [],
  recap: [],
  moi: null,
  chargement: true,
  erreur: null,
};

/**
 * LE hook central. La base est le store : on ne garde aucun état de jeu
 * en mémoire côté client, on projette ce que la base dit. Un
 * rafraîchissement, une coupure réseau ou un téléphone à plat se
 * rattrapent tout seuls (ARCHITECTURE.md §9).
 */
export function usePartie(code: string | null, moi: string | null) {
  const [etat, setEtat] = useState<Etat>(vide);
  const partieId = useRef<string | null>(null);

  const recharger = useCallback(async () => {
    if (!code) return;
    const { data: p, error } = await supabase
      .from("parties")
      .select("*")
      .eq("code", code.toUpperCase())
      .maybeSingle();

    if (error) {
      setEtat((e) => ({ ...e, chargement: false, erreur: error.message }));
      return;
    }
    if (!p) {
      setEtat((e) => ({ ...e, chargement: false, erreur: "Cette partie n'existe plus." }));
      return;
    }
    partieId.current = p.id;

    const [j, b, t, f, g, pal, rec] = await Promise.all([
      supabase.from("v_joueurs").select("*").eq("partie_id", p.id),
      supabase.from("binomes").select("*").eq("partie_id", p.id).order("couleur"),
      supabase.from("v_tours").select("*").eq("partie_id", p.id).order("ordre"),
      supabase.from("v_passages_finale").select("*").eq("partie_id", p.id).order("ordre"),
      // dérivée de joueurs.prepa_faites, donc rafraîchie par le temps réel (0012)
      supabase.from("v_progression").select("*").eq("partie_id", p.id).maybeSingle(),
      supabase.from("v_palmares").select("*").eq("partie_id", p.id).order("rang"),
      supabase.from("v_recap").select("*").eq("partie_id", p.id).order("ordre"),
    ]);

    setEtat({
      partie: p as Partie,
      joueurs: (j.data ?? []) as Joueur[],
      binomes: (b.data ?? []) as Binome[],
      tours: (t.data ?? []) as Tour[],
      passages: (f.data ?? []) as PassageFinale[],
      progression: (g.data ?? null) as Progression | null,
      palmares: (pal.data ?? []) as LignePalmares[],
      recap: (rec.data ?? []) as LigneRecap[],
      moi,
      chargement: false,
      erreur: null,
    });
  }, [code, moi]);

  // Chargement initial
  useEffect(() => {
    void recharger();
  }, [recharger]);

  // Un seul canal par partie. Toute diffusion déclenche un rechargement :
  // à ce volume, c'est plus sûr qu'appliquer des deltas à la main, et le
  // budget de messages le permet largement (ARCHITECTURE.md §6).
  useEffect(() => {
    if (!partieId.current) return;
    const canal = supabase
      .channel(`partie:${partieId.current}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "parties" }, () => void recharger())
      .on("postgres_changes", { event: "*", schema: "public", table: "joueurs" }, () => void recharger())
      .on("postgres_changes", { event: "*", schema: "public", table: "binomes" }, () => void recharger())
      .on("postgres_changes", { event: "*", schema: "public", table: "tours" }, () => void recharger())
      .on("postgres_changes", { event: "*", schema: "public", table: "passages_finale" }, () => void recharger())
      .subscribe();
    return () => void supabase.removeChannel(canal);
  }, [etat.partie?.id, recharger]);

  // Pouls de présence : c'est lui qui permet au plateau de geler les
  // chronos quand le joueur attendu disparaît (§10.c).
  useEffect(() => {
    if (!etat.partie) return;
    const battre = () => void rpc.pouls().catch(() => {});
    battre();
    const t = setInterval(battre, 10_000);
    return () => clearInterval(t);
  }, [etat.partie?.id]);

  return { ...etat, recharger };
}

// ---- Sélecteurs ----

export function monJoueur(e: Etat): Joueur | null {
  return e.joueurs.find((j) => j.id === e.moi) ?? null;
}

export function monBinome(e: Etat): Binome | null {
  const j = monJoueur(e);
  return j?.binome_id ? (e.binomes.find((b) => b.id === j.binome_id) ?? null) : null;
}

export function partenaire(e: Etat): Joueur | null {
  const j = monJoueur(e);
  if (!j?.binome_id) return null;
  return e.joueurs.find((o) => o.binome_id === j.binome_id && o.id !== j.id) ?? null;
}

export function membres(e: Etat, binomeId: string): Joueur[] {
  return e.joueurs
    .filter((j) => j.binome_id === binomeId)
    .sort((a, b) => (a.role ?? "").localeCompare(b.role ?? ""));
}

export function tourCourant(e: Etat): Tour | null {
  if (!e.partie?.tour_courant) return null;
  return e.tours.find((t) => t.id === e.partie!.tour_courant) ?? null;
}

export function suisJePresentateur(e: Etat): boolean {
  return !!e.moi && e.partie?.presentateur_id === e.moi;
}

export function suisJePlateau(e: Etat): boolean {
  return !!e.moi && e.partie?.plateau_id === e.moi;
}

export function peutOrchestrer(e: Etat): boolean {
  if (!e.moi || !e.partie) return false;
  return [e.partie.plateau_id, e.partie.hote_id, e.partie.presentateur_id].includes(e.moi);
}

/** Les votants d'un tour : tout le monde sauf le binôme concerné et le présentateur. */
export function suisJeVotant(e: Etat, t: Tour | null): boolean {
  const j = monJoueur(e);
  if (!t || !j || !j.binome_id) return false;
  return j.binome_id !== t.binome_id && j.id !== e.partie?.presentateur_id;
}
