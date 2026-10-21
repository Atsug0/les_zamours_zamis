import { useMemo } from "react";
import { Lettrage, Narration, Panneau, PastilleBinome, Trame } from "../ui";
import { membres, peutOrchestrer, type Etat } from "../jeu/usePartie";

/**
 * La préparation vue de la télé : des NOMBRES, aucun contenu.
 * C'est le seul temps mort de la soirée, alors l'écran affiche les
 * règles du vote — les gens les lisent parce qu'ils attendent.
 */
export default function PrepPlateau({ e, onSuivant }: { e: Etat; onSuivant: () => void }) {
  const prog = e.progression;
  const total = prog?.total ?? 0;
  const termines = prog?.termines ?? 0;
  const parJoueur = prog?.questions_par_joueur ?? 9;
  const tousPrets = total > 0 && termines === total;

  const joueurs = useMemo(
    () => e.joueurs.filter((j) => j.binome_id).sort((a, b) => a.prenom.localeCompare(b.prenom)),
    [e.joueurs]
  );

  return (
    <Trame style={{ minHeight: "100%" }}>
      <div className="centre">
        <Narration>Préparation</Narration>

        <Lettrage taille="clamp(1.6rem, 4vw, 3rem)" couleur="var(--zamours)" ombre="var(--bleu)">
          Chacun répond sur soi-même
        </Lettrage>

        <div style={{ display: "grid", gap: "var(--e-3)", width: "min(760px, 100%)" }}>
          <div
            style={{
              fontFamily: "var(--donnees)",
              fontSize: "var(--t-2xl)",
              fontVariantNumeric: "tabular-nums",
            }}
          >
            {termines} / {total}
          </div>
          <div
            style={{
              height: 26,
              border: "var(--filet) solid var(--bord)",
              background: "var(--papier)",
              boxShadow: "4px 4px 0 var(--ombre)",
            }}
          >
            <div
              style={{
                height: "100%",
                width: total ? `${(termines / total) * 100}%` : 0,
                background: "var(--jaune)",
                borderRight: termines && termines < total ? "var(--filet) solid var(--bord)" : "none",
                transition: "width var(--pop)",
              }}
            />
          </div>

          <div className="rangee" style={{ justifyContent: "center" }}>
            {joueurs.map((j) => {
              const fini = j.prepa_faites >= parJoueur;
              return (
                <span
                  key={j.id}
                  style={{
                    border: "var(--filet) solid var(--bord)",
                    padding: "2px var(--e-2)",
                    background: fini ? "var(--valide)" : "var(--papier)",
                    color: fini ? "var(--sur-semantique)" : "var(--texte-2)",
                    fontFamily: "var(--donnees)",
                    fontSize: "var(--t-s)",
                    opacity: j.present ? 1 : 0.5,
                  }}
                >
                  {j.prenom} {fini ? "✓" : `${j.prepa_faites}/${parJoueur}`}
                </span>
              );
            })}
          </div>
        </div>

        <Panneau style={{ maxWidth: "62ch", textAlign: "left" }}>
          <Narration petit>Pendant qu'on attend : le vote</Narration>
          <ul style={{ margin: "var(--e-3) 0 0", paddingLeft: "1.2em", fontSize: "var(--t-s)" }}>
            <li>Même idée, autres mots → <strong>ça compte</strong>.</li>
            <li>Bonne catégorie mais pas la bonne réponse → <strong>ça compte pas</strong>.</li>
            <li>« Ça dépend », « un peu tout » → <strong>ça compte pas</strong>. C'est la seule
              règle stricte : les réponses vagues tuent le jeu.</li>
            <li>Sur les chiffres, tolérance de <strong>± 10 %</strong>.</li>
          </ul>
        </Panneau>

        <div className="rangee" style={{ justifyContent: "center" }}>
          {e.binomes.map((b) => (
            <PastilleBinome
              key={b.id}
              couleur={b.couleur}
              prenoms={membres(e, b.id).map((j) => j.prenom)}
            />
          ))}
        </div>

        {tousPrets && peutOrchestrer(e) && (
          <button
            type="button"
            onClick={onSuivant}
            style={{
              fontFamily: "var(--display)",
              textTransform: "uppercase",
              letterSpacing: ".06em",
              fontSize: "var(--t-xl)",
              padding: "var(--e-3) var(--e-5)",
              border: "var(--filet-fort) solid var(--bord)",
              background: "var(--jaune)",
              color: "#15101b",
              boxShadow: "var(--decalage) var(--decalage) 0 var(--ombre)",
              cursor: "pointer",
            }}
          >
            Que le jeu commence
          </button>
        )}
        {tousPrets && !peutOrchestrer(e) && (
          <Narration petit>Tout le monde est prêt</Narration>
        )}
      </div>
    </Trame>
  );
}
