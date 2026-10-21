import { Coeur, Eclair, Lettrage, Narration, Panneau, PastilleBinome, Trame } from "../ui";
import { QR } from "../ui/QR";
import { membres, modeSujet, type Etat } from "../jeu/usePartie";

/** Le lobby vu de la télé : le code en grand, les binômes qui se forment. */
export default function LobbyPlateau({ e }: { e: Etat }) {
  const p = e.partie!;
  const libres = e.joueurs.filter((j) => !j.binome_id && j.id !== p.presentateur_id);
  const presentateur = e.joueurs.find((j) => j.id === p.presentateur_id);
  const prets = e.binomes.filter((b) => b.verrouille).length;
  // le QR mène droit au pupitre : un scan, un prénom, c'est tout
  const lienJoueur = `${location.origin}/p/${p.code}`;

  return (
    <Trame style={{ minHeight: "100%" }}>
      <div className="centre">
        <Narration>Rejoignez la partie</Narration>

        <div
          style={{
            display: "flex",
            gap: "var(--e-6)",
            alignItems: "center",
            justifyContent: "center",
            flexWrap: "wrap",
          }}
        >
          <div style={{ display: "grid", gap: "var(--e-2)" }}>
            {/* Jaune sur aplat d'encre : 13:1. Sur le papier blanc il
                tombait à 1,43:1 — illisible dès que -webkit-text-stroke
                ne s'applique pas. */}
            <div
              style={{
                display: "inline-block",
                background: "var(--encre)",
                border: "var(--filet-fort) solid var(--bord)",
                boxShadow: "10px 10px 0 var(--bleu)",
                padding: "var(--e-2) var(--e-4)",
                fontFamily: "var(--display)",
                fontSize: "clamp(3.2rem, 13vw, 9rem)",
                letterSpacing: ".08em",
                lineHeight: 1.05,
                color: "var(--jaune)",
                maxWidth: "100%",
              }}
            >
              {p.code}
            </div>
            <p style={{ margin: 0, color: "var(--texte-2)", fontSize: "var(--t-l)" }}>
              Tapez ce code, ou scannez
            </p>
          </div>

          <div style={{ display: "grid", gap: "var(--e-2)", justifyItems: "center" }}>
            <QR valeur={lienJoueur} taille={240} />
            <code
              style={{
                fontFamily: "var(--donnees)",
                fontSize: "var(--t-xs)",
                color: "var(--texte-2)",
              }}
            >
              {lienJoueur.replace(/^https?:\/\//, "")}
            </code>
          </div>
        </div>

        {modeSujet(e) ? (
          <div style={{ display: "grid", gap: "var(--e-3)", justifyItems: "center" }}>
            <Narration>
              Qui connaît le mieux{" "}
              {e.joueurs.find((j) => j.id === p.sujet_id)?.prenom ?? "?"} ?
            </Narration>
            <p style={{ margin: 0, color: "var(--texte-2)" }}>
              Pas de binôme : chacun joue pour soi, et le sujet valide.
            </p>
            <div className="rangee" style={{ justifyContent: "center" }}>
              {e.joueurs
                .filter((j) => j.id !== p.sujet_id)
                .map((j) => (
                  <span
                    key={j.id}
                    style={{
                      border: "var(--filet) solid var(--bord)",
                      background: "var(--papier)",
                      padding: "var(--e-1) var(--e-3)",
                      fontFamily: "var(--display)",
                      textTransform: "uppercase",
                      boxShadow: "4px 4px 0 var(--ombre)",
                      opacity: j.present ? 1 : 0.5,
                    }}
                  >
                    {j.prenom}
                  </span>
                ))}
            </div>
          </div>
        ) : e.joueurs.length === 0 ? (
          <p style={{ color: "var(--texte-2)" }}>Personne n'est encore arrivé.</p>
        ) : (
          <div style={{ display: "grid", gap: "var(--e-4)", width: "min(900px, 100%)" }}>
            <div className="rangee" style={{ justifyContent: "center" }}>
              {e.binomes.map((b) => {
                const m = membres(e, b.id);
                return (
                  <div key={b.id} style={{ display: "grid", gap: "var(--e-1)", justifyItems: "center" }}>
                    <PastilleBinome
                      couleur={b.couleur}
                      prenoms={m.map((j) => j.prenom)}
                      present={m.every((j) => j.present)}
                    />
                    <span style={{ fontSize: "var(--t-xs)", color: "var(--texte-2)" }}>
                      {b.verrouille ? (
                        <span className="rangee" style={{ alignItems: "center", gap: 4 }}>
                          {b.mode === "zamours" ? <Coeur taille={16} /> : <Eclair taille={16} />}
                          {b.mode === "zamours" ? "Zamours" : "Zamis"}
                        </span>
                      ) : (
                        "choisit son mode…"
                      )}
                    </span>
                  </div>
                );
              })}
            </div>

            {libres.length > 0 && (
              <Panneau>
                <Lettrage taille="var(--t-l)" couleur="var(--texte)">
                  En attente d'un binôme
                </Lettrage>
                <div className="rangee" style={{ marginTop: "var(--e-2)" }}>
                  {libres.map((j) => (
                    <span
                      key={j.id}
                      style={{
                        border: "var(--filet) solid var(--bord)",
                        padding: "2px var(--e-2)",
                        opacity: j.present ? 1 : 0.5,
                      }}
                    >
                      {j.prenom}
                    </span>
                  ))}
                </div>
              </Panneau>
            )}

            {presentateur && (
              <Narration petit>À la présentation : {presentateur.prenom}</Narration>
            )}

            <p style={{ margin: 0, color: "var(--texte-2)", fontSize: "var(--t-s)" }}>
              {prets} binôme{prets > 1 ? "s" : ""} prêt{prets > 1 ? "s" : ""}
              {e.binomes.length > prets && ` · ${e.binomes.length - prets} en attente de mode`}
            </p>
          </div>
        )}
      </div>
    </Trame>
  );
}
