import { useEffect, useState } from "react";
import { rpc } from "../jeu/rpc";
import { question as texteQuestion } from "../jeu/banque";
import { BoutonTampon, Erreur, Narration, Panneau } from "../ui";
import { monJoueur, sujetDuTour, type Etat } from "../jeu/usePartie";
import type { Tour } from "../jeu/types";

/** Mode sujet, sur le téléphone. */
export default function SujetJoueur({ e, tour }: { e: Etat; tour: Tour }) {
  const [erreur, setErreur] = useState<string | null>(null);
  const [occupe, setOccupe] = useState(false);
  const [saisie, setSaisie] = useState("");
  const moi = monJoueur(e);
  // en tournoi, le sujet change à chaque bloc de questions
  const sujet = sujetDuTour(e, tour);
  const jeSuisLeSujet = !!moi && moi.id === sujet?.id;
  const challengers = e.joueurs.filter((j) => j.id !== sujet?.id);
  const q = texteQuestion(tour.question_id, sujet?.prenom ?? "lui");
  const reponses = e.reponsesManche.filter((r) => r.tour_id === tour.id);
  const maReponse = reponses.find((r) => r.joueur_id === moi?.id);

  useEffect(() => setSaisie(""), [tour.id, tour.statut]);

  const faire = async (f: () => Promise<unknown>) => {
    setErreur(null);
    setOccupe(true);
    try {
      await f();
    } catch (ex) {
      setErreur(ex instanceof Error ? ex.message : String(ex));
    } finally {
      setOccupe(false);
    }
  };

  const cadre = (contenu: React.ReactNode) => (
    <div className="pile">
      {erreur && <Erreur>{erreur}</Erreur>}
      {contenu}
    </div>
  );

  const champ = (placeholder: string) =>
    q?.props ? (
      <div style={{ display: "grid", gap: "var(--e-2)" }}>
        {q.props.map((p, i) => (
          <BoutonTampon
            key={p}
            ton={saisie === p ? "jaune" : "neutre"}
            disabled={occupe}
            onClick={() => setSaisie(p)}
          >
            {i + 1} · {p}
          </BoutonTampon>
        ))}
      </div>
    ) : (
      <input
        value={saisie}
        onChange={(ev) => setSaisie(ev.target.value.slice(0, 60))}
        placeholder={placeholder}
        autoFocus
        style={{
          border: "var(--filet) solid var(--bord)",
          padding: "var(--e-3)",
          fontSize: "var(--t-l)",
          background: "var(--papier)",
          color: "var(--texte)",
        }}
      />
    );

  // ================= LE SUJET =================
  if (jeSuisLeSujet) {
    if (tour.statut === "attente") {
      return cadre(
        <>
          <Narration petit>Réponds en secret — personne ne le voit</Narration>
          <Panneau>
            <p style={{ margin: 0, fontSize: "var(--t-l)" }}>{q?.prepa ?? q?.jeu}</p>
          </Panneau>
          {champ("Ta réponse")}
          <BoutonTampon
            disabled={occupe || saisie.trim().length === 0}
            onClick={() => void faire(() => rpc.sujetRepond(tour.id, saisie))}
          >
            Verrouiller ma réponse
          </BoutonTampon>
          <p style={{ margin: 0, fontSize: "var(--t-xs)", color: "var(--texte-2)" }}>
            Elle est verrouillée avant que quiconque réponde : c'est ce qui rend le jeu juste.
          </p>
        </>
      );
    }

    if (tour.statut === "consigne") {
      const tous = tour.reponses_recues >= challengers.length;
      return cadre(
        <>
          <Narration petit>
            {tour.reponses_recues} / {challengers.length} ont répondu
          </Narration>
          <p style={{ margin: 0, color: "var(--texte-2)", fontSize: "var(--t-s)" }}>
            {tous ? "Tout le monde a répondu." : "On attend les derniers."}
          </p>
          <BoutonTampon
            ton={tous ? "jaune" : "neutre"}
            disabled={occupe || tour.reponses_recues === 0}
            onClick={() => void faire(() => rpc.revelerDefis(tour.id))}
          >
            Révéler
          </BoutonTampon>
        </>
      );
    }

    if (tour.statut === "revele") {
      return cadre(
        <>
          <Narration petit>Tu avais dit « {tour.reponse_revelee} »</Narration>
          <p style={{ margin: 0, fontSize: "var(--t-s)", color: "var(--texte-2)" }}>
            Le comptage est pré-rempli. Corrige ce qui compte quand même — même idée, autres mots.
          </p>
          <div style={{ display: "grid", gap: "var(--e-2)" }}>
            {reponses.map((r) => (
              <button
                key={r.joueur_id}
                type="button"
                disabled={occupe}
                onClick={() => void faire(() => rpc.jugerDefi(tour.id, r.joueur_id, !r.juste))}
                style={{
                  display: "flex",
                  justifyContent: "space-between",
                  alignItems: "center",
                  gap: "var(--e-3)",
                  textAlign: "left",
                  border: "var(--filet) solid var(--bord)",
                  background: r.juste ? "var(--valide)" : "var(--papier)",
                  color: r.juste ? "var(--sur-semantique)" : "var(--texte)",
                  padding: "var(--e-2) var(--e-3)",
                  cursor: "pointer",
                }}
              >
                <span>
                  <strong style={{ display: "block", fontSize: "var(--t-l)" }}>{r.valeur}</strong>
                  <span style={{ fontSize: "var(--t-xs)", opacity: 0.8 }}>{r.prenom}</span>
                </span>
                <span style={{ fontFamily: "var(--display)", fontSize: "var(--t-xl)" }}>
                  {r.juste ? "✓" : "✗"}
                </span>
              </button>
            ))}
          </div>
          <BoutonTampon disabled={occupe} onClick={() => void faire(() => rpc.cloreDefis(tour.id))}>
            Valider et marquer les points
          </BoutonTampon>
        </>
      );
    }

    return cadre(
      <>
        <Narration petit>
          {reponses.filter((r) => r.juste).length} sur {reponses.length} t'ont trouvé
        </Narration>
        <p style={{ margin: 0, color: "var(--texte-2)" }}>Question suivante dans un instant.</p>
      </>
    );
  }

  // ================= LES CHALLENGERS =================
  if (tour.statut === "attente") {
    return cadre(
      <>
        <Narration petit>{sujet?.prenom} réfléchit</Narration>
        <p style={{ margin: 0, color: "var(--texte-2)", fontSize: "var(--t-s)" }}>
          Il répond en secret. Ensuite, à toi.
        </p>
      </>
    );
  }

  if (tour.statut === "consigne") {
    if (tour.j_ai_repondu) {
      return cadre(
        <>
          <Narration petit>Ta réponse est enregistrée</Narration>
          <p style={{ margin: 0, color: "var(--texte-2)", fontSize: "var(--t-s)" }}>
            {tour.reponses_recues} / {challengers.length} ont répondu. On attend les autres.
          </p>
        </>
      );
    }
    return cadre(
      <>
        <Narration petit>À toi — qu'a dit {sujet?.prenom} ?</Narration>
        <Panneau>
          <p style={{ margin: 0, fontSize: "var(--t-l)" }}>{q?.jeu}</p>
        </Panneau>
        {champ(`Ce que ${sujet?.prenom ?? "il"} a répondu`)}
        <BoutonTampon
          disabled={occupe || saisie.trim().length === 0}
          onClick={() => void faire(() => rpc.defier(tour.id, saisie))}
        >
          Valider
        </BoutonTampon>
      </>
    );
  }

  return cadre(
    <>
      <Narration petit>
        {maReponse?.juste === true ? "Trouvé !" : maReponse?.juste === false ? "Raté" : "Révélation"}
      </Narration>
      <Panneau>
        <div style={{ fontSize: "var(--t-xs)", color: "var(--texte-2)" }}>
          {sujet?.prenom} avait dit
        </div>
        <div style={{ fontSize: "var(--t-xl)" }}>{tour.reponse_revelee}</div>
        {maReponse?.valeur && (
          <>
            <div
              style={{ fontSize: "var(--t-xs)", color: "var(--texte-2)", marginTop: "var(--e-2)" }}
            >
              toi
            </div>
            <div style={{ fontSize: "var(--t-l)" }}>{maReponse.valeur}</div>
          </>
        )}
      </Panneau>
      <p style={{ margin: 0, color: "var(--texte-2)", fontSize: "var(--t-s)" }}>
        Regarde la télé.
      </p>
    </>
  );
}
