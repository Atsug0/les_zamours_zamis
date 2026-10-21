import { formater, useChrono } from "../jeu/chrono";
import { titreSerie } from "../jeu/banque";
import { Lettrage, Narration, PastilleBinome, Trame } from "../ui";
import { membres, type Etat } from "../jeu/usePartie";
import type { PassageFinale } from "../jeu/types";

/**
 * La finale vue de la télé : le chrono géant et la file des pastilles.
 * C'est le seul cercle de toute la DA — c'est ce qui le rend
 * impossible à manquer.
 */
export default function FinalePlateau({ e }: { e: Etat }) {
  const passage = e.passages.find((p) => p.seuil_atteint === null) ?? null;
  const finis = e.passages.filter((p) => p.seuil_atteint !== null);
  const seuil = e.partie?.reglages.seuilFinale ?? 3;

  if (!passage) {
    return (
      <Trame style={{ minHeight: "100%" }}>
        <div className="centre">
          <Narration>La finale est jouée</Narration>
          <Resultats passages={finis} e={e} seuil={seuil} />
        </div>
      </Trame>
    );
  }

  const equipe = membres(e, passage.binome_id);
  const binome = e.binomes.find((b) => b.id === passage.binome_id);
  const finaliste = e.joueurs.find((j) => j.id === passage.joueur_id);
  const questionneur = e.joueurs.find((j) => j.id === passage.questionneur_id);
  const chrono = useChrono(passage.chrono_fin_at, passage.chrono_restant_ms);
  const justes = passage.jugements.filter((j) => j === "juste").length;
  const urgence = chrono.ms > 0 && chrono.ms < 5000;

  return (
    <Trame style={{ minHeight: "100%" }}>
      <div className="centre" style={{ gap: "var(--e-4)" }}>
        <Narration>
          Finale {finis.length + 1} / {e.passages.length} · {titreSerie(passage.serie_id ?? "")}
        </Narration>

        <div className="rangee" style={{ justifyContent: "center" }}>
          {binome && (
            <PastilleBinome
              couleur={binome.couleur}
              prenoms={equipe.map((j) => j.prenom)}
              score={binome.score}
            />
          )}
        </div>

        {!passage.joueur_id ? (
          <>
            <Lettrage taille="clamp(1.6rem,4vw,3rem)" couleur="var(--zamours)" ombre="var(--bleu)">
              Lequel de vous deux joue ?
            </Lettrage>
            <p style={{ color: "var(--texte-2)", margin: 0 }}>
              Choisissez sur votre téléphone. L'autre s'assoit et se tait.
            </p>
          </>
        ) : !passage.chrono_fin_at && !passage.chrono_restant_ms ? (
          <>
            <Lettrage taille="clamp(1.6rem,4vw,3rem)" couleur="var(--zamours)" ombre="var(--bleu)">
              {finaliste?.prenom} est prêt
            </Lettrage>
            <p style={{ color: "var(--texte-2)", margin: 0 }}>
              {questionneur?.prenom} lance le chrono. {e.partie?.reglages.questionsFinale} questions,{" "}
              {Math.round((e.partie?.reglages.chronoFinaleMs ?? 30000) / 1000)} secondes,{" "}
              {seuil} bonnes réponses pour la prime.
            </p>
          </>
        ) : (
          <>
            <div
              style={{
                display: "inline-grid",
                placeItems: "center",
                width: "min(42vh, 300px)",
                aspectRatio: "1",
                border: `var(--filet-fort) solid ${urgence ? "var(--rouge)" : "var(--bord)"}`,
                borderRadius: "50%",
                background: "var(--jaune)",
                color: "#15101b",
                boxShadow: urgence
                  ? "12px 12px 0 var(--rouge)"
                  : "7px 7px 0 var(--ombre)",
              }}
            >
              <b
                style={{
                  fontFamily: "var(--display)",
                  fontSize: "clamp(3rem, 12vh, 7rem)",
                  lineHeight: 1,
                  fontVariantNumeric: "tabular-nums",
                }}
              >
                {chrono.gele ? formater(chrono.ms) : formater(chrono.ms)}
              </b>
              <span
                style={{
                  fontFamily: "var(--display)",
                  textTransform: "uppercase",
                  fontSize: "var(--t-s)",
                  letterSpacing: ".14em",
                }}
              >
                {chrono.gele ? "en pause" : `${finaliste?.prenom ?? ""}`}
              </span>
            </div>

            <div className="rangee" style={{ justifyContent: "center" }}>
              {passage.jugements.map((j, i) => (
                <span
                  key={i}
                  style={{
                    width: 54,
                    height: 54,
                    display: "grid",
                    placeItems: "center",
                    border: "var(--filet) solid var(--bord)",
                    fontFamily: "var(--display)",
                    fontSize: "var(--t-2xl)",
                    background:
                      j === "juste"
                        ? "var(--valide)"
                        : j === "faux"
                          ? "var(--refuse)"
                          : j === "passee"
                            ? "var(--jaune)"
                            : "var(--papier)",
                    color:
                      j === "juste" || j === "faux" ? "var(--sur-semantique)" : "#15101b",
                  }}
                >
                  {j === "juste" ? "✓" : j === "faux" ? "✗" : j === "passee" ? "↷" : ""}
                </span>
              ))}
            </div>

            <span
              style={{
                fontFamily: "var(--donnees)",
                fontSize: "var(--t-l)",
                fontVariantNumeric: "tabular-nums",
                color: justes >= seuil ? "var(--valide)" : "var(--texte-2)",
              }}
            >
              {justes} / {seuil} pour la prime
            </span>
          </>
        )}

        {finis.length > 0 && <Resultats passages={finis} e={e} seuil={seuil} />}
      </div>
    </Trame>
  );
}

function Resultats({ passages, e, seuil }: { passages: PassageFinale[]; e: Etat; seuil: number }) {
  return (
    <div className="rangee" style={{ justifyContent: "center" }}>
      {passages.map((p) => {
        const b = e.binomes.find((x) => x.id === p.binome_id);
        const justes = p.jugements.filter((j) => j === "juste").length;
        return (
          <span
            key={p.id}
            style={{
              border: "var(--filet) solid var(--bord)",
              background: "var(--papier)",
              padding: "var(--e-1) var(--e-3)",
              fontSize: "var(--t-s)",
              boxShadow: "4px 4px 0 var(--ombre)",
            }}
          >
            <strong>{b ? membres(e, b.id).map((j) => j.prenom).join(" & ") : "?"}</strong>{" "}
            {justes}/{seuil} · <strong>+{p.points}</strong>
            {p.seuil_atteint ? " avec la prime" : ""}
          </span>
        );
      })}
    </div>
  );
}
