import { useEffect, useRef } from "react";
import { jouer, reveillerLeSon } from "./sons";
import { suisJePlateau, tourCourant, type Etat } from "./usePartie";

/**
 * Sonorise le plateau, et lui seul. On observe les transitions d'état
 * plutôt que d'appeler `jouer()` depuis les composants : les écrans
 * restent déclaratifs, et un son ne peut pas partir deux fois parce
 * qu'un composant s'est remonté.
 */
export function useSons(e: Etat) {
  const precedent = useRef<{
    etat?: string;
    tour?: string;
    statut?: string;
    joueurs: number;
    recues: number;
    primes: number;
  }>({ joueurs: 0, recues: 0, primes: 0 });

  // Les navigateurs exigent un geste avant d'émettre du son.
  useEffect(() => {
    const eveil = () => reveillerLeSon();
    addEventListener("pointerdown", eveil, { once: true });
    addEventListener("keydown", eveil, { once: true });
    return () => {
      removeEventListener("pointerdown", eveil);
      removeEventListener("keydown", eveil);
    };
  }, []);

  useEffect(() => {
    if (!e.partie || !suisJePlateau(e)) return;
    const p = precedent.current;
    const t = tourCourant(e);
    const etat = e.partie.etat;

    if (p.etat !== undefined) {
      if (etat !== p.etat) {
        if (etat === "prep") jouer("depart");
        else if (etat === "palmares") jouer("victoire");
      }
      if (etat === "lobby" && e.joueurs.length > p.joueurs) jouer("arrivee");

      if (t) {
        if (t.id !== p.tour) {
          jouer("question");
        } else if (t.statut !== p.statut) {
          if (t.statut === "consigne") jouer("roulement");
          else if (t.statut === "vote" || t.statut === "revele") jouer("revelation");
          else if (t.statut === "juge") jouer(t.verdict ? "juste" : "faux");
        }
        // une voix ou un pari qui tombe
        if (t.id === p.tour && t.reponses_recues > p.recues) jouer("vote");
      }

      const primes = e.passages.filter((x) => x.seuil_atteint === true).length;
      if (primes > p.primes) jouer("prime");
    }

    precedent.current = {
      etat,
      ...(t ? { tour: t.id, statut: t.statut } : {}),
      joueurs: e.joueurs.length,
      recues: t?.reponses_recues ?? 0,
      primes: e.passages.filter((x) => x.seuil_atteint === true).length,
    };
  }, [
    e.partie?.etat,
    e.partie?.tour_courant,
    tourCourant(e)?.statut,
    tourCourant(e)?.reponses_recues,
    e.joueurs.length,
    e.passages.length,
    e.moi,
  ]);
}

/** Le tic-tac des dernières secondes, piloté par le chrono affiché. */
export function useTicTac(ms: number | null, actif: boolean) {
  const dernier = useRef<number | null>(null);
  useEffect(() => {
    if (!actif || ms === null || ms > 5000 || ms <= 0) return;
    const s = Math.ceil(ms / 1000);
    if (dernier.current !== s) {
      dernier.current = s;
      jouer("tic");
    }
  }, [ms, actif]);
}
