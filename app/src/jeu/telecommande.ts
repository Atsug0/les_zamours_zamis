import { useCallback, useEffect, useState } from "react";

/**
 * Navigation à la télécommande.
 *
 * Une télé — Chromecast, Android TV, box, Apple TV — n'envoie au fond
 * que des FLÈCHES, un OK et un RETOUR. Les navigateurs ne déplacent pas
 * le focus aux flèches (la navigation spatiale n'est pas standard), donc
 * on le fait à la main.
 *
 * Les éléments navigables se déclarent avec `data-tc`. L'ordre du DOM
 * est l'ordre de navigation : le plateau n'a jamais plus de deux ou
 * trois actions, inutile de modéliser une grille.
 */
export function useTelecommande(actif = true) {
  useEffect(() => {
    if (!actif) return;

    const cibles = () =>
      Array.from(
        document.querySelectorAll<HTMLElement>("[data-tc]:not([disabled]):not([hidden])")
      );

    const deplacer = (pas: number) => {
      const liste = cibles();
      if (liste.length === 0) return;
      const i = liste.indexOf(document.activeElement as HTMLElement);
      const suivant = liste[(i + pas + liste.length) % liste.length] ?? liste[0];
      suivant?.focus();
    };

    const sur = (ev: KeyboardEvent) => {
      // on ne vole jamais les flèches à un champ de saisie
      const a = document.activeElement;
      if (a instanceof HTMLInputElement || a instanceof HTMLTextAreaElement) return;

      switch (ev.key) {
        case "ArrowRight":
        case "ArrowDown":
          ev.preventDefault();
          deplacer(1);
          break;
        case "ArrowLeft":
        case "ArrowUp":
          ev.preventDefault();
          deplacer(-1);
          break;
        case "Enter":
        case " ":
          if (document.activeElement instanceof HTMLElement && document.activeElement.dataset.tc) {
            ev.preventDefault();
            document.activeElement.click();
          } else {
            // rien de focalisé : OK active la première action de l'écran
            const premier = cibles()[0];
            if (premier) {
              ev.preventDefault();
              premier.focus();
            }
          }
          break;
        case "Escape":
        case "Backspace":
          if (document.fullscreenElement) {
            ev.preventDefault();
            void document.exitFullscreen();
          }
          break;
      }
    };

    addEventListener("keydown", sur);
    return () => removeEventListener("keydown", sur);
  }, [actif]);
}

/** Plein écran, et l'échelle de lecture qui va avec. */
export function usePleinEcran() {
  const [plein, setPlein] = useState(() => !!document.fullscreenElement);

  useEffect(() => {
    const maj = () => {
      const p = !!document.fullscreenElement;
      setPlein(p);
      // on regarde un plateau à trois mètres, pas à cinquante centimètres
      document.documentElement.classList.toggle("plein-ecran", p);
    };
    document.addEventListener("fullscreenchange", maj);
    return () => document.removeEventListener("fullscreenchange", maj);
  }, []);

  const basculer = useCallback(() => {
    if (document.fullscreenElement) void document.exitFullscreen();
    else void document.documentElement.requestFullscreen().catch(() => {});
  }, []);

  return { plein, basculer, possible: typeof document.documentElement.requestFullscreen === "function" };
}
