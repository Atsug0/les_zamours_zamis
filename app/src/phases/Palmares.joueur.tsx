import { useState } from "react";
import { rpc } from "../jeu/rpc";
import { BoutonTampon, Erreur, Lettrage, Narration, Panneau } from "../ui";
import { monBinome, peutOrchestrer, type Etat } from "../jeu/usePartie";

export default function PalmaresJoueur({ e }: { e: Etat }) {
  const [erreur, setErreur] = useState<string | null>(null);
  const [occupe, setOccupe] = useState(false);
  const mien = monBinome(e);
  const ligne = e.palmares.find((l) => l.binome_id === mien?.id);
  const premiers = e.palmares.filter((l) => l.rang === 1);
  const egalite = premiers.length > 1;

  if (egalite) {
    return (
      <div className="pile">
        <Narration petit>Mort subite</Narration>
        <p style={{ margin: 0, fontSize: "var(--t-s)", color: "var(--texte-2)" }}>
          {premiers.map((l) => l.prenoms.join(" & ")).join(" et ")} sont à égalité. Une question
          ouverte commune, à l'oral — le premier binôme à concorder gagne.
        </p>
        {erreur && <Erreur>{erreur}</Erreur>}
        {peutOrchestrer(e) ? (
          <>
            <p style={{ margin: 0, fontSize: "var(--t-s)" }}>Qui a concordé le premier ?</p>
            {premiers.map((l) => (
              <BoutonTampon
                key={l.binome_id}
                disabled={occupe}
                onClick={() => {
                  setErreur(null);
                  setOccupe(true);
                  rpc
                    .mortSubite(l.binome_id)
                    .catch((ex: unknown) => setErreur(ex instanceof Error ? ex.message : String(ex)))
                    .finally(() => setOccupe(false));
                }}
              >
                {l.prenoms.join(" & ")}
              </BoutonTampon>
            ))}
          </>
        ) : (
          <p style={{ margin: 0, color: "var(--texte-2)" }}>Regarde la télé.</p>
        )}
      </div>
    );
  }

  return (
    <div className="pile">
      <Narration petit>{ligne?.rang === 1 ? "Vous gagnez" : "C'est fini"}</Narration>
      {ligne && (
        <Panneau>
          <Lettrage taille="var(--t-2xl)" couleur={`var(--${ligne.couleur})`}>
            {ligne.prenoms.join(" & ")}
          </Lettrage>
          <div
            style={{
              fontFamily: "var(--donnees)",
              fontSize: "var(--t-2xl)",
              marginTop: "var(--e-2)",
            }}
          >
            {ligne.score} points
          </div>
          <div style={{ fontSize: "var(--t-s)", color: "var(--texte-2)" }}>
            {ligne.rang}ᵉ sur {e.palmares.length} · finale +{ligne.points_finale ?? 0}
            {ligne.seuil_atteint ? " avec la prime" : " sans la prime"}
          </div>
        </Panneau>
      )}
      <p style={{ margin: 0, color: "var(--texte-2)", fontSize: "var(--t-s)" }}>
        Le récap de la soirée est sur la télé.
      </p>
    </div>
  );
}
