import { useState } from "react";
import { rpc } from "../jeu/rpc";
import { question as texteQuestion } from "../jeu/banque";
import { Coeur, Eclair, Lettrage, Narration, Panneau, Trame } from "../ui";
import { membres, peutOrchestrer, type Etat } from "../jeu/usePartie";

/** Le palmarès, et le récap de la soirée. */
export default function PalmaresPlateau({ e }: { e: Etat }) {
  const [occupe, setOccupe] = useState(false);
  const classement = e.palmares;
  const premiers = classement.filter((l) => l.rang === 1);
  const egalite = premiers.length > 1;

  // Les réponses libres qui ont concordé : c'est à ça que servaient les
  // deux ou trois mots consignés par le questionneur (règles §9).
  const pepites = e.recap.filter((t) => t.manche !== "qcm" && t.verdict).slice(0, 8);

  return (
    <Trame style={{ minHeight: "100%" }}>
      <div className="centre" style={{ gap: "var(--e-4)" }}>
        {egalite ? (
          <>
            <Narration>Égalité au sommet</Narration>
            <Lettrage taille="clamp(1.8rem,5vw,3.4rem)" couleur="var(--rouge)" ombre="var(--bleu)">
              Mort subite
            </Lettrage>
            <Panneau style={{ maxWidth: "52ch" }}>
              <p style={{ margin: 0, fontSize: "var(--t-s)" }}>
                {premiers.map((l) => l.prenoms.join(" & ")).join(" et ")} sont à{" "}
                <strong>{premiers[0]?.score} points</strong>. Une question ouverte commune, les
                deux binômes jouent, le premier à concorder gagne. Le présentateur déclare le
                vainqueur sur son téléphone.
              </p>
            </Panneau>
          </>
        ) : (
          <>
            <Narration>Palmarès</Narration>
            {classement[0] && (
              <div style={{ display: "grid", gap: "var(--e-2)", justifyItems: "center" }}>
                {classement[0].mode === "zamours" ? <Coeur taille={64} /> : <Eclair taille={64} />}
                <Lettrage taille="clamp(2rem,6vw,4rem)" ombre="var(--jaune)">
                  {classement[0].prenoms.join(" & ")}
                </Lettrage>
                <span style={{ fontFamily: "var(--donnees)", fontSize: "var(--t-2xl)" }}>
                  {classement[0].score} points
                </span>
              </div>
            )}
          </>
        )}

        <div style={{ display: "grid", gap: "var(--e-2)", width: "min(720px, 100%)" }}>
          {classement.map((l) => (
            <div
              key={l.binome_id}
              style={{
                display: "grid",
                gridTemplateColumns: "auto 1fr auto auto",
                gap: "var(--e-3)",
                alignItems: "center",
                border: "var(--filet) solid var(--bord)",
                boxShadow: "4px 4px 0 var(--ombre)",
                background: `var(--${l.couleur})`,
                color: l.couleur === "jaune" ? "#15101b" : "#fff",
                padding: "var(--e-2) var(--e-3)",
                textAlign: "left",
              }}
            >
              <span style={{ fontFamily: "var(--display)", fontSize: "var(--t-xl)" }}>{l.rang}</span>
              <span style={{ fontFamily: "var(--display)", textTransform: "uppercase" }}>
                {l.prenoms.join(" & ")}
              </span>
              <span style={{ fontFamily: "var(--donnees)", fontSize: "var(--t-s)", opacity: 0.85 }}>
                finale +{l.points_finale ?? 0}
                {l.seuil_atteint ? " ✦" : ""}
              </span>
              <span
                style={{
                  fontFamily: "var(--donnees)",
                  fontSize: "var(--t-xl)",
                  fontVariantNumeric: "tabular-nums",
                }}
              >
                {l.score}
              </span>
            </div>
          ))}
        </div>

        {pepites.length > 0 && (
          <Panneau style={{ width: "min(760px, 100%)", textAlign: "left" }}>
            <Narration petit>Ce qui a marché ce soir</Narration>
            <div
              style={{
                display: "grid",
                gap: "var(--e-2)",
                marginTop: "var(--e-3)",
                maxHeight: "32vh",
                overflowY: "auto",
              }}
            >
              {pepites.map((t) => {
                const b = e.binomes.find((x) => x.id === t.binome_id);
                const noms = b ? membres(e, b.id).map((j) => j.prenom) : [];
                const q = texteQuestion(t.question_id, noms[1] ?? "");
                return (
                  <div key={t.ordre} style={{ fontSize: "var(--t-s)" }}>
                    <div style={{ color: "var(--texte-2)" }}>{q?.jeu ?? t.question_id}</div>
                    <div>
                      <strong>{t.reponse_donnee}</strong>
                      {t.reponse_revelee && t.reponse_revelee !== t.reponse_donnee && (
                        <span style={{ color: "var(--texte-2)" }}> · pour « {t.reponse_revelee} »</span>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          </Panneau>
        )}

        {egalite && peutOrchestrer(e) && (
          <div className="rangee" style={{ justifyContent: "center" }}>
            {premiers.map((l) => (
              <button
                key={l.binome_id}
                type="button"
                data-tc=""
                disabled={occupe}
                onClick={() => {
                  setOccupe(true);
                  void rpc.mortSubite(l.binome_id).finally(() => setOccupe(false));
                }}
                style={{
                  fontFamily: "var(--display)",
                  textTransform: "uppercase",
                  fontSize: "var(--t-l)",
                  padding: "var(--e-2) var(--e-4)",
                  border: "var(--filet) solid var(--bord)",
                  background: `var(--${l.couleur})`,
                  color: l.couleur === "jaune" ? "#15101b" : "#fff",
                  boxShadow: "var(--decalage) var(--decalage) 0 var(--ombre)",
                  cursor: "pointer",
                }}
              >
                {l.prenoms.join(" & ")} gagnent
              </button>
            ))}
          </div>
        )}
      </div>
    </Trame>
  );
}
