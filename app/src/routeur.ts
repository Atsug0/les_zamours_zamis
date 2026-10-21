import { useEffect, useState } from "react";

/**
 * Routeur minimal. Trois routes suffisent :
 *   /            l'accueil
 *   /tv/:code    le plateau
 *   /p/:code     le pupitre
 * Une dépendance de moins, et le bundle reste petit — le plafond de
 * transfert de l'hébergement gratuit n'est pas infini (ARCHITECTURE.md §8).
 */
export type Route =
  | { nom: "accueil" }
  | { nom: "plateau"; code: string }
  | { nom: "joueur"; code: string }
  | { nom: "inconnue" };

export function lire(chemin = location.pathname): Route {
  const m = /^\/(tv|p)\/([A-Za-z]{4})\/?$/.exec(chemin);
  if (m && m[1] && m[2]) {
    const code = m[2].toUpperCase();
    return m[1] === "tv" ? { nom: "plateau", code } : { nom: "joueur", code };
  }
  if (chemin === "/" || chemin === "") return { nom: "accueil" };
  return { nom: "inconnue" };
}

export function aller(chemin: string) {
  history.pushState({}, "", chemin);
  dispatchEvent(new PopStateEvent("popstate"));
}

export function useRoute(): Route {
  const [route, setRoute] = useState(() => lire());
  useEffect(() => {
    const maj = () => setRoute(lire());
    addEventListener("popstate", maj);
    return () => removeEventListener("popstate", maj);
  }, []);
  return route;
}
