import { Narration, Panneau } from "../ui";
import type { Etat } from "../jeu/usePartie";

/**
 * Les phases de jeu dont l'écran n'est pas encore écrit. Le backend les
 * gère déjà entièrement (migrations 0004 à 0006, 115 assertions) : il ne
 * manque que l'interface.
 */
export default function EnConstruction({ e, cote }: { e: Etat; cote: "plateau" | "joueur" }) {
  const phases: Record<string, string> = {
    prep: "La préparation",
    qcm: "Manche 1 · les QCM",
    libre: "Manche 2 · les questions libres",
    bonus: "La question bonus",
    finale: "La finale",
    palmares: "Le palmarès",
  };
  return (
    <div className="centre">
      <Narration>{phases[e.partie?.etat ?? ""] ?? "À venir"}</Narration>
      <Panneau style={{ maxWidth: "48ch" }}>
        <p style={{ margin: 0 }}>
          Cet écran ({cote}) n'est pas encore écrit. Le serveur, lui, sait déjà jouer cette phase
          de bout en bout.
        </p>
      </Panneau>
    </div>
  );
}
