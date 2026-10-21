import { useEffect, useState } from "react";

/**
 * Compte à rebours dérivé d'une date de fin SERVEUR.
 * L'horloge du téléphone n'a aucune autorité : elle sert juste à
 * animer. Le serveur refuse tout ce qui arrive hors délai (§3.c).
 */
export function useChrono(finAt: string | null, restantMs: number | null = null) {
  const [maintenant, setMaintenant] = useState(() => Date.now());

  useEffect(() => {
    if (!finAt) return;
    const t = setInterval(() => setMaintenant(Date.now()), 100);
    return () => clearInterval(t);
  }, [finAt]);

  // Partie gelée : on affiche le reste figé, pas un décompte (§10.c).
  if (!finAt) {
    return { ms: restantMs ?? 0, gele: restantMs !== null, ecoule: false };
  }
  const ms = Math.max(0, new Date(finAt).getTime() - maintenant);
  return { ms, gele: false, ecoule: ms === 0 };
}

export function formater(ms: number): string {
  const s = Math.ceil(ms / 1000);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}
