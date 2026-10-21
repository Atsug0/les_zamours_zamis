import { formater, useChrono } from "../jeu/chrono";
import { question as texteQuestion } from "../jeu/banque";
import { Lettrage, Narration, PastilleBinome, Trame, Verdict } from "../ui";
import { membres, modeDuel, modeParis, type Etat } from "../jeu/usePartie";
import type { Tour } from "../jeu/types";

/**
 * La manche vue de la télé. Une seule chose grande au centre, et la
 * double révélation en deux cases séparées d'un = ou d'un ≠ : le
 * résultat se lit graphiquement avant d'être lu textuellement.
 */
export default function manchePlateau({ e, tour }: { e: Etat; tour: Tour }) {
  const binome = e.binomes.find((b) => b.id === tour.binome_id);
  const equipe = membres(e, tour.binome_id);
  const repondant = e.joueurs.find((j) => j.id === tour.repondant_id);
  const prepare = equipe.find((j) => j.id !== tour.repondant_id);
  const bonus = tour.manche === "bonus";

  const q = texteQuestion(tour.question_id, prepare?.prenom ?? "ton binôme");
  const chrono = useChrono(tour.vote_fin_at, null);
  const duel = modeDuel(e);
  const paris = modeParis(e);
  const parieurs = e.joueurs.filter(
    (j) => j.binome_id && j.binome_id !== tour.binome_id && j.id !== e.partie?.presentateur_id
  ).length;

  const signe =
    tour.statut === "juge" ? (tour.verdict ? "=" : "≠") : tour.statut === "vote" ? "?" : "";
  const votants = e.joueurs.filter(
    (j) => j.binome_id && j.binome_id !== tour.binome_id && j.id !== e.partie?.presentateur_id
  ).length;

  return (
    <Trame style={{ minHeight: "100%" }}>
      <div className="centre" style={{ gap: "var(--e-4)" }}>
        <Narration petit>
          {bonus
            ? `Question bonus · ${equipe.map((j) => j.prenom).join(" & ")}`
            : tour.manche === "citez3"
              ? `Cite 3 · ${repondant?.prenom ?? "?"} devine ce que ${prepare?.prenom ?? "?"} a dit`
              : `${repondant?.prenom ?? "?"} répond sur ${prepare?.prenom ?? "?"}`}
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

        {/* Les propositions d'un QCM s'affichent en grand : le joueur les
            annonce à voix haute avant de les taper. */}
        {q?.props && tour.statut === "attente" && (
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
          <Lettrage taille="var(--t-xl)" couleur="var(--zamours)">
            {bonus
              ? "Roulement…"
              : tour.manche === "citez3"
                ? "Trois réponses !"
                : duel
                  ? "À voix haute, puis tape-la"
                  : "À voix haute !"}
          </Lettrage>
        )}
        {tour.statut === "consigne" && !paris && (
          <Lettrage taille="var(--t-xl)" couleur="var(--zamours)">
            Réponse consignée…
          </Lettrage>
        )}

        {tour.statut === "consigne" && paris && (
          <>
            <Case qui={`${repondant?.prenom ?? "?"} a répondu`} quoi={tour.reponse_donnee} />
            <Narration>Ça va concorder ? Pariez !</Narration>
            <span
              style={{
                fontFamily: "var(--donnees)",
                fontSize: "var(--t-2xl)",
                fontVariantNumeric: "tabular-nums",
              }}
            >
              {tour.reponses_recues} / {parieurs}
            </span>
            <span style={{ color: "var(--texte-2)", fontSize: "var(--t-s)" }}>
              paris secrets · 5 points à qui lit juste
            </span>
          </>
        )}

        {(tour.statut === "vote" || tour.statut === "juge") && (
          <div
            style={{
              display: "grid",
              gridTemplateColumns: "1fr auto 1fr",
              gap: "var(--e-3)",
              width: "min(780px, 100%)",
              alignItems: "stretch",
            }}
          >
            <Case
              qui={bonus ? (equipe[0]?.prenom ?? "A") : `${repondant?.prenom ?? "?"} a dit`}
              quoi={tour.reponse_donnee}
              liste={tour.manche === "citez3"}
            />
            <div
              style={{
                display: "grid",
                placeItems: "center",
                fontFamily: "var(--display)",
                fontSize: "var(--t-3xl)",
                color: tour.statut === "juge" && tour.verdict ? "var(--valide)" : "var(--rouge)",
              }}
            >
              {signe}
            </div>
            <Case
              qui={bonus ? (equipe[1]?.prenom ?? "B") : `${prepare?.prenom ?? "?"} avait écrit`}
              quoi={tour.reponse_revelee}
              liste={tour.manche === "citez3"}
            />
          </div>
        )}

        {duel && tour.contestee && tour.statut === "revele" && (
          <Narration>Contestation — l'autre tranche</Narration>
        )}

        {tour.statut === "vote" && (
          <div className="rangee" style={{ justifyContent: "center", alignItems: "center" }}>
            <Narration>
              {q?.verifiable ? "Montre ton écran !" : "Est-ce que ça compte ?"}
            </Narration>
            {!q?.verifiable && (
              <>
                <span
                  style={{
                    fontFamily: "var(--donnees)",
                    fontSize: "var(--t-2xl)",
                    fontVariantNumeric: "tabular-nums",
                  }}
                >
                  {formater(chrono.ms)}
                </span>
                <span style={{ color: "var(--texte-2)", fontSize: "var(--t-s)" }}>
                  {votants} votant{votants > 1 ? "s" : ""} · votes secrets
                </span>
              </>
            )}
          </div>
        )}

        {tour.statut === "juge" && (
          <div className="rangee" style={{ justifyContent: "center", alignItems: "center" }}>
            <Verdict etat={tour.verdict ? "valide" : "refuse"} />
            {tour.voix_pour !== null && (
              <span style={{ fontFamily: "var(--donnees)", fontSize: "var(--t-l)" }}>
                {tour.voix_pour} – {tour.voix_contre}
              </span>
            )}
            {tour.points > 0 && (
              <Lettrage taille="var(--t-2xl)" couleur="var(--valide)">
                +{tour.points}
              </Lettrage>
            )}
            {paris && (
              <span style={{ color: "var(--texte-2)", fontSize: "var(--t-s)" }}>
                et 5 points à chaque pari juste
              </span>
            )}
          </div>
        )}

        <div className="rangee" style={{ justifyContent: "center", marginTop: "var(--e-3)" }}>
          {e.binomes.map((b) => (
            <PastilleBinome
              key={b.id}
              couleur={b.couleur}
              prenoms={membres(e, b.id).map((j) => j.prenom)}
              score={b.score}
              present={b.id !== binome?.id ? true : equipe.every((j) => j.present)}
            />
          ))}
        </div>
      </div>
    </Trame>
  );
}

function Case({ qui, quoi, liste = false }: { qui: string; quoi: string | null; liste?: boolean }) {
  const trois = liste && quoi ? quoi.split(" · ") : null;
  return (
    <div
      style={{
        border: "var(--filet) solid var(--bord)",
        background: "var(--papier)",
        boxShadow: "var(--decalage) var(--decalage) 0 var(--ombre)",
        padding: "var(--e-3)",
        textAlign: "left",
        display: "grid",
        gap: 4,
        alignContent: "start",
      }}
    >
      <em
        style={{
          fontFamily: "var(--display)",
          fontStyle: "normal",
          textTransform: "uppercase",
          fontSize: "var(--t-xs)",
          letterSpacing: ".08em",
          color: "var(--texte-2)",
        }}
      >
        {qui}
      </em>
      {trois ? (
        <ol style={{ margin: 0, paddingLeft: "1.2em", fontSize: "var(--t-l)", lineHeight: 1.35 }}>
          {trois.map((x, i) => (
            <li key={i}>
              <strong>{x}</strong>
            </li>
          ))}
        </ol>
      ) : (
        <strong style={{ fontSize: "var(--t-xl)", lineHeight: 1.2 }}>
          {quoi && quoi.length > 0 ? quoi : <span style={{ color: "var(--texte-2)" }}>— passée —</span>}
        </strong>
      )}
    </div>
  );
}
