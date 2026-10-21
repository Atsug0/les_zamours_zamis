import { question as texteQuestion } from "../jeu/banque";
import { Lettrage, Narration, PastilleBinome, Trame } from "../ui";
import { membres, sujetDuTour, type Etat } from "../jeu/usePartie";
import type { Tour } from "../jeu/types";

/**
 * Mode « qui connaît le mieux X », vu de la télé.
 *
 * Le sujet répond en secret, puis tout le monde répond en même temps,
 * puis on dévoile tout d'un coup. C'est beaucoup plus nerveux que le
 * jeu à binômes : chaque question est jouée par toute la salle.
 */
export default function SujetPlateau({ e, tour }: { e: Etat; tour: Tour }) {
  // en tournoi, le sujet change à chaque bloc de questions
  const sujet = sujetDuTour(e, tour);
  const challengers = e.joueurs.filter((j) => j.id !== sujet?.id);
  const q = texteQuestion(tour.question_id, sujet?.prenom ?? "lui");
  const reponses = e.reponsesManche.filter((r) => r.tour_id === tour.id);

  return (
    <Trame style={{ minHeight: "100%" }}>
      <div className="centre" style={{ gap: "var(--e-4)" }}>
        <Narration petit>
          Qui connaît le mieux {sujet?.prenom ?? "?"} · question {tour.ordre}
        </Narration>

        <p
          style={{
            fontFamily: "var(--display)",
            textTransform: "uppercase",
            fontSize: "clamp(1.5rem, 4.2vw, 3.2rem)",
            lineHeight: 1.05,
            margin: 0,
            maxWidth: "24ch",
            /* encre sur papier : 18,7:1 dans les deux thèmes, et la
               couleur passe dans l'ombre, qui ne porte aucun contraste */
            color: "var(--texte)",
            textShadow: "5px 5px 0 var(--jaune)",
            textWrap: "balance",
          }}
        >
          {q?.jeu ?? tour.question_id}
        </p>

        {q?.props && tour.statut !== "juge" && (
          <div className="rangee" style={{ justifyContent: "center" }}>
            {q.props.map((p, i) => (
              <span
                key={p}
                style={{
                  border: "var(--filet) solid var(--bord)",
                  background: "var(--papier)",
                  padding: "var(--e-2) var(--e-3)",
                  fontSize: "var(--t-l)",
                  boxShadow: "4px 4px 0 var(--ombre)",
                }}
              >
                <strong style={{ fontFamily: "var(--display)", marginRight: 8 }}>{i + 1}</strong>
                {p}
              </span>
            ))}
          </div>
        )}

        {tour.statut === "attente" && (
          <Lettrage taille="clamp(1.4rem,3.6vw,2.6rem)" couleur="var(--zamours)">
            {sujet?.prenom} répond en secret…
          </Lettrage>
        )}

        {tour.statut === "consigne" && (
          <>
            <Lettrage taille="clamp(1.4rem,3.6vw,2.6rem)" couleur="var(--zamours)">
              À vous — tous en même temps !
            </Lettrage>
            <div className="rangee" style={{ justifyContent: "center" }}>
              {challengers.map((j) => {
                const repondu = reponses.some((r) => r.joueur_id === j.id);
                return (
                  <span
                    key={j.id}
                    style={{
                      border: "var(--filet) solid var(--bord)",
                      background: repondu ? "var(--valide)" : "var(--papier)",
                      color: repondu ? "var(--sur-semantique)" : "var(--texte-2)",
                      padding: "var(--e-1) var(--e-3)",
                      fontFamily: "var(--display)",
                      textTransform: "uppercase",
                      boxShadow: "4px 4px 0 var(--ombre)",
                    }}
                  >
                    {j.prenom} {repondu ? "✓" : "…"}
                  </span>
                );
              })}
            </div>
            <span style={{ fontFamily: "var(--donnees)", fontSize: "var(--t-xl)" }}>
              {tour.reponses_recues} / {challengers.length}
            </span>
          </>
        )}

        {(tour.statut === "revele" || tour.statut === "juge") && (
          <>
            <div
              style={{
                border: "var(--filet-fort) solid var(--bord)",
                background: "var(--jaune)",
                color: "#15101b",
                padding: "var(--e-3) var(--e-5)",
                boxShadow: "8px 8px 0 var(--ombre)",
                display: "grid",
                gap: 2,
              }}
            >
              <span
                style={{
                  fontFamily: "var(--display)",
                  textTransform: "uppercase",
                  fontSize: "var(--t-xs)",
                  letterSpacing: ".1em",
                }}
              >
                {sujet?.prenom} avait dit
              </span>
              <strong style={{ fontFamily: "var(--display)", fontSize: "clamp(1.6rem,5vw,3rem)" }}>
                {tour.reponse_revelee}
              </strong>
            </div>

            <div
              style={{
                display: "grid",
                gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))",
                gap: "var(--e-2)",
                width: "min(900px, 100%)",
              }}
            >
              {reponses.map((r) => (
                <div
                  key={r.joueur_id}
                  style={{
                    border: "var(--filet) solid var(--bord)",
                    background:
                      r.juste === true
                        ? "var(--valide)"
                        : r.juste === false
                          ? "var(--papier)"
                          : "var(--papier-2)",
                    color: r.juste === true ? "var(--sur-semantique)" : "var(--texte)",
                    boxShadow: "4px 4px 0 var(--ombre)",
                    padding: "var(--e-2) var(--e-3)",
                    textAlign: "left",
                    display: "grid",
                    gap: 2,
                  }}
                >
                  <span
                    style={{
                      fontFamily: "var(--display)",
                      textTransform: "uppercase",
                      fontSize: "var(--t-xs)",
                      letterSpacing: ".06em",
                      opacity: 0.8,
                    }}
                  >
                    {r.prenom} {r.juste === true ? "✓" : r.juste === false ? "✗" : ""}
                  </span>
                  <strong style={{ fontSize: "var(--t-l)" }}>{r.valeur}</strong>
                </div>
              ))}
            </div>

            {tour.statut === "juge" && (
              <Lettrage taille="var(--t-2xl)" couleur="var(--valide)">
                +{tour.manche === "qcm" ? 5 : 10} pour chaque bonne réponse
              </Lettrage>
            )}
          </>
        )}

        <div className="rangee" style={{ justifyContent: "center", marginTop: "var(--e-3)" }}>
          {e.binomes.map((b) => (
            <PastilleBinome
              key={b.id}
              couleur={b.couleur}
              prenoms={membres(e, b.id).map((j) => j.prenom)}
              score={b.score}
            />
          ))}
        </div>
      </div>
    </Trame>
  );
}
