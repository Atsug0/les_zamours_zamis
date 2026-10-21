import { useEffect, useRef } from "react";
import { rpc } from "./rpc";
import { suisJePlateau, tourCourant, type Etat } from "./usePartie";

/** Combien de temps on laisse le verdict à l'écran avant d'enchaîner. */
const PAUSE_VERDICT_MS = 4500;

/**
 * Le plateau est l'horloge de la partie (ARCHITECTURE.md §3.e).
 * Il ne décide rien : il déclenche, et la base refuse si le délai n'est
 * pas réellement écoulé. Aucune tâche planifiée nulle part.
 *
 * Trois déclenchements :
 *   - aucun tour courant alors qu'une manche est en cours -> avancer ;
 *   - fenêtre de vote écoulée -> clore ;
 *   - verdict affiché assez longtemps -> avancer.
 */
export function useOrchestration(e: Etat) {
  const faits = useRef(new Set<string>());
  const minuteur = useRef<number | null>(null);

  useEffect(() => {
    if (!e.partie || !suisJePlateau(e) || e.partie.en_pause) return;

    const unefois = (cle: string, action: () => Promise<unknown>) => {
      if (faits.current.has(cle)) return;
      faits.current.add(cle);
      action().catch(() => {
        // on autorise une nouvelle tentative : coupure réseau, course entre
        // deux écrans, ou délai pas encore écoulé côté serveur.
        setTimeout(() => faits.current.delete(cle), 3000);
      });
    };

    const etat = e.partie.etat;
    const tour = tourCourant(e);

    if (["qcm", "libre", "citez3", "bonus"].includes(etat) && !tour) {
      unefois(`avancer:${etat}:${e.tours.filter((t) => t.statut === "juge").length}`, rpc.suivant);
      return;
    }
    if (etat === "finale" && !e.passages.some((p) => p.seuil_atteint === null)) {
      unefois("finale:terminee", rpc.suivant);
      return;
    }
    if (!tour) return;

    if (tour.statut === "vote" && tour.vote_fin_at) {
      const reste = new Date(tour.vote_fin_at).getTime() - Date.now();
      const clore = () => unefois(`clore:${tour.id}`, () => rpc.cloreVote(tour.id));
      if (reste <= 0) clore();
      else {
        minuteur.current = window.setTimeout(clore, reste + 250);
        return () => {
          if (minuteur.current) window.clearTimeout(minuteur.current);
        };
      }
    }

    if (tour.statut === "juge") {
      minuteur.current = window.setTimeout(
        () => unefois(`suite:${tour.id}`, rpc.suivant),
        PAUSE_VERDICT_MS
      );
      return () => {
        if (minuteur.current) window.clearTimeout(minuteur.current);
      };
    }
    return;
  }, [
    e.partie?.id,
    e.partie?.etat,
    e.partie?.en_pause,
    e.partie?.tour_courant,
    e.moi,
    tourCourant(e)?.statut,
    e.tours.length,
    e.passages.filter((p) => p.seuil_atteint === null).length,
  ]);
}
