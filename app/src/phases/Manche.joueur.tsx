import { useEffect, useState } from "react";
import { rpc } from "../jeu/rpc";
import { question as texteQuestion } from "../jeu/banque";
import { formater, useChrono } from "../jeu/chrono";
import { BoutonTampon, Erreur, Narration, Panneau } from "../ui";
import {
  membres, modeDuel, monJoueur, peutOrchestrer, suisJeVotant, type Etat,
} from "../jeu/usePartie";
import type { Tour } from "../jeu/types";

/**
 * La manche sur le téléphone. Un rôle, un écran, une action.
 * Le téléphone de quelqu'un dont le binôme joue reste neutre :
 * ni vote, ni indice (règles §11.2).
 */
export default function mancheJoueur({ e, tour }: { e: Etat; tour: Tour }) {
  const [erreur, setErreur] = useState<string | null>(null);
  const [occupe, setOccupe] = useState(false);
  const [consigne, setConsigne] = useState("");
  const [trois, setTrois] = useState(["", "", ""]);
  const [concordes, setConcordes] = useState<number | null>(null);
  const moi = monJoueur(e);
  const equipe = membres(e, tour.binome_id);
  const prepare = equipe.find((j) => j.id !== tour.repondant_id);
  const q = texteQuestion(tour.question_id, prepare?.prenom ?? "ton binôme");
  const chrono = useChrono(tour.vote_fin_at, null);

  const duel = modeDuel(e);
  const monTour = moi?.binome_id === tour.binome_id;
  const jeRepond = moi?.id === tour.repondant_id;
  const jeQuestionne = moi?.id === tour.questionneur_id;
  const jeVote = suisJeVotant(e, tour);
  const jeSuisPresentateur = e.partie?.presentateur_id === moi?.id;

  useEffect(() => {
    setConsigne("");
    setTrois(["", "", ""]);
    setConcordes(null);
  }, [tour.id]);

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
      {peutOrchestrer(e) && tour.statut !== "juge" && (
        <BoutonTampon ton="neutre" disabled={occupe} onClick={() => void faire(() => rpc.sauterTour(tour.id))}>
          Sauter ce tour
        </BoutonTampon>
      )}
    </div>
  );

  // ================= DUEL =================
  // Aucun votant : chacun saisit sa propre réponse, la concordance est
  // calculée mécaniquement, et la contestation remplace le vote.
  if (duel && jeRepond && tour.statut === "attente" && tour.manche !== "bonus") {
    return cadre(
      <>
        <Narration petit>À toi — dis-le d'abord à voix haute</Narration>
        <Panneau>
          <p style={{ margin: 0, fontSize: "var(--t-l)" }}>{q?.jeu}</p>
        </Panneau>
        {q?.props ? (
          <div style={{ display: "grid", gap: "var(--e-2)" }}>
            {q.props.map((p, i) => (
              <BoutonTampon
                key={p}
                disabled={occupe}
                onClick={() => void faire(() => rpc.consigner(tour.id, p))}
              >
                {i + 1} · {p}
              </BoutonTampon>
            ))}
          </div>
        ) : (
          <>
            <input
              value={consigne}
              onChange={(ev) => setConsigne(ev.target.value.slice(0, 60))}
              placeholder="Ta réponse"
              autoFocus
              style={{
                border: "var(--filet) solid var(--bord)",
                padding: "var(--e-3)",
                fontSize: "var(--t-l)",
                background: "var(--papier)",
                color: "var(--texte)",
              }}
            />
            <BoutonTampon
              disabled={occupe || consigne.trim().length === 0}
              onClick={() => void faire(() => rpc.consigner(tour.id, consigne))}
            >
              Valider
            </BoutonTampon>
          </>
        )}
        <p style={{ margin: 0, fontSize: "var(--t-xs)", color: "var(--texte-2)" }}>
          En duel, il n'y a personne pour voter : la comparaison est automatique. Si elle te
          paraît injuste, tu pourras contester une fois.
        </p>
      </>
    );
  }

  if (duel && tour.statut === "juge" && tour.verdict === false && !tour.contestee && jeRepond) {
    return cadre(
      <>
        <Narration petit>Pas de concordance</Narration>
        <Panneau>
          <div style={{ fontSize: "var(--t-xs)", color: "var(--texte-2)" }}>tu as dit</div>
          <div style={{ fontSize: "var(--t-l)" }}>{tour.reponse_donnee}</div>
          <div style={{ fontSize: "var(--t-xs)", color: "var(--texte-2)", marginTop: "var(--e-2)" }}>
            la réponse enregistrée
          </div>
          <div style={{ fontSize: "var(--t-l)" }}>{tour.reponse_revelee}</div>
        </Panneau>
        <BoutonTampon ton="neutre" disabled={occupe} onClick={() => void faire(() => rpc.contester(tour.id))}>
          Contester — c'est la même chose
        </BoutonTampon>
        <p style={{ margin: 0, fontSize: "var(--t-xs)", color: "var(--texte-2)" }}>
          Une seule fois par tour, et c'est l'autre qui tranche.
        </p>
      </>
    );
  }

  if (duel && tour.contestee && tour.statut === "revele" && monTour && !jeRepond) {
    return cadre(
      <>
        <Narration petit>Contestation — à toi de trancher</Narration>
        <Panneau>
          <div style={{ fontSize: "var(--t-xs)", color: "var(--texte-2)" }}>
            {e.joueurs.find((j) => j.id === tour.repondant_id)?.prenom} a dit
          </div>
          <div style={{ fontSize: "var(--t-xl)" }}>{tour.reponse_donnee}</div>
          <div style={{ fontSize: "var(--t-xs)", color: "var(--texte-2)", marginTop: "var(--e-2)" }}>
            tu avais écrit
          </div>
          <div style={{ fontSize: "var(--t-xl)" }}>{tour.reponse_revelee}</div>
        </Panneau>
        <p style={{ margin: 0, fontSize: "var(--t-s)", color: "var(--texte-2)" }}>
          Même idée, autres mots ? Alors ça compte. Un refus de mauvaise foi se voit.
        </p>
        <div className="duo">
          <BoutonTampon
            ton="valide"
            disabled={occupe}
            onClick={() => void faire(() => rpc.trancherContestation(tour.id, true))}
          >
            Ça compte
          </BoutonTampon>
          <BoutonTampon
            ton="refuse"
            disabled={occupe}
            onClick={() => void faire(() => rpc.trancherContestation(tour.id, false))}
          >
            Non
          </BoutonTampon>
        </div>
      </>
    );
  }

  // ---- « Cite 3 » : trois réponses, puis le questionneur annonce
  //      combien ont concordé. Pas de vote : trois votes d'affilée
  //      casseraient le rythme (règles §9.3).
  if (jeQuestionne && tour.manche === "citez3" && tour.statut !== "juge") {
    const remplies = trois.filter((x) => x.trim().length > 0).length;
    return cadre(
      <>
        <Narration petit>Cite 3 — note les trois réponses</Narration>
        <Panneau>
          <p style={{ margin: 0, fontSize: "var(--t-l)" }}>{q?.jeu}</p>
        </Panneau>
        {trois.map((v, i) => (
          <input
            key={i}
            value={v}
            onChange={(ev) =>
              setTrois((t) => t.map((x, k) => (k === i ? ev.target.value.slice(0, 40) : x)))
            }
            placeholder={`réponse ${i + 1}`}
            style={{
              border: "var(--filet) solid var(--bord)",
              padding: "var(--e-2) var(--e-3)",
              fontSize: "var(--t-l)",
              background: "var(--papier)",
              color: "var(--texte)",
            }}
          />
        ))}
        <p style={{ margin: 0, fontSize: "var(--t-s)", color: "var(--texte-2)" }}>
          Révèle les trois réponses enregistrées, puis dis combien ont concordé. 5 points chacune.
        </p>
        <div className="rangee">
          {[0, 1, 2, 3].map((n) => (
            <BoutonTampon
              key={n}
              large={false}
              ton={concordes === n ? "valide" : "neutre"}
              disabled={occupe}
              onClick={() => setConcordes(n)}
            >
              {n}
            </BoutonTampon>
          ))}
        </div>
        <BoutonTampon
          disabled={occupe || remplies === 0 || concordes === null}
          onClick={() =>
            void faire(() => rpc.jugerCitez3(tour.id, trois, concordes ?? 0))
          }
        >
          {concordes === null ? "Choisis d'abord le nombre" : `Valider · ${concordes * 5} points`}
        </BoutonTampon>
      </>
    );
  }

  // ---- QCM : le joueur annonce son choix à voix haute, puis le tape ----
  if (jeRepond && tour.manche === "qcm" && tour.statut === "attente") {
    return cadre(
      <>
        <Narration petit>À toi — dis-le à voix haute d'abord</Narration>
        <Panneau>
          <p style={{ margin: 0, fontSize: "var(--t-l)" }}>{q?.jeu}</p>
        </Panneau>
        <div style={{ display: "grid", gap: "var(--e-2)" }}>
          {(q?.props ?? []).map((p, i) => (
            <BoutonTampon
              key={p}
              disabled={occupe}
              onClick={() => void faire(() => rpc.consigner(tour.id, p))}
            >
              {i + 1} · {p}
            </BoutonTampon>
          ))}
        </div>
      </>
    );
  }

  // ---- Questionneur : consigner puis révéler ----
  if (jeQuestionne && tour.manche !== "qcm" && tour.statut === "attente") {
    if (tour.manche === "bonus") {
      return cadre(
        <>
          <Narration petit>Tu mènes le bonus</Narration>
          <Panneau>
            <p style={{ margin: 0, fontSize: "var(--t-l)" }}>{q?.jeu}</p>
            <p style={{ margin: "var(--e-2) 0 0", fontSize: "var(--t-s)", color: "var(--texte-2)" }}>
              Les deux ont déjà répondu pendant la préparation. Fais monter la sauce, puis révèle.
            </p>
          </Panneau>
          <BoutonTampon disabled={occupe} onClick={() => void faire(() => rpc.reveler(tour.id))}>
            Révéler les deux réponses
          </BoutonTampon>
        </>
      );
    }
    return cadre(
      <>
        <Narration petit>Tu questionnes — note sa réponse</Narration>
        <Panneau>
          <p style={{ margin: 0, fontSize: "var(--t-l)" }}>{q?.jeu}</p>
        </Panneau>
        <p style={{ margin: 0, fontSize: "var(--t-s)", color: "var(--texte-2)" }}>
          Attends la <strong>réponse ferme</strong> — « ma réponse, c'est… » — puis note-la en deux
          ou trois mots. Tu ne vois pas ce qui était enregistré : personne ne doit pouvoir le lire
          sur ton visage.
        </p>
        <input
          value={consigne}
          onChange={(ev) => setConsigne(ev.target.value.slice(0, 60))}
          placeholder="Ce qu'il/elle vient de dire"
          autoFocus
          style={{
            border: "var(--filet) solid var(--bord)",
            padding: "var(--e-3)",
            fontSize: "var(--t-l)",
            background: "var(--papier)",
            color: "var(--texte)",
          }}
        />
        <BoutonTampon
          disabled={occupe || consigne.trim().length === 0}
          onClick={() =>
            void faire(async () => {
              await rpc.consigner(tour.id, consigne);
              await rpc.reveler(tour.id);
            })
          }
        >
          Consigner et révéler
        </BoutonTampon>
      </>
    );
  }

  if (jeQuestionne && tour.statut === "consigne") {
    return cadre(
      <>
        <Narration petit>Prêt à révéler</Narration>
        <BoutonTampon disabled={occupe} onClick={() => void faire(() => rpc.reveler(tour.id))}>
          Révéler
        </BoutonTampon>
      </>
    );
  }

  // ---- Vote ----
  if (tour.statut === "vote" && jeVote && !tour.j_ai_vote) {
    if (q?.verifiable) {
      return cadre(
        <>
          <Narration petit>Pas de vote ici</Narration>
          <Panneau>
            <p style={{ margin: 0, fontSize: "var(--t-s)" }}>
              Cette réponse se vérifie sur le téléphone. On regarde l'écran, la preuve tranche
              mieux qu'une majorité.
            </p>
          </Panneau>
        </>
      );
    }
    return cadre(
      <>
        <Narration petit>Est-ce que ça compte ? · {formater(chrono.ms)}</Narration>
        <Panneau>
          <div style={{ fontSize: "var(--t-xs)", color: "var(--texte-2)" }}>a dit</div>
          <div style={{ fontSize: "var(--t-l)" }}>{tour.reponse_donnee}</div>
          <div style={{ fontSize: "var(--t-xs)", color: "var(--texte-2)", marginTop: "var(--e-2)" }}>
            avait écrit
          </div>
          <div style={{ fontSize: "var(--t-l)" }}>{tour.reponse_revelee}</div>
        </Panneau>
        <div className="duo">
          <BoutonTampon ton="valide" disabled={occupe} onClick={() => void faire(() => rpc.voter(tour.id, true))}>
            Oui
          </BoutonTampon>
          <BoutonTampon ton="refuse" disabled={occupe} onClick={() => void faire(() => rpc.voter(tour.id, false))}>
            Non
          </BoutonTampon>
        </div>
        <p style={{ margin: 0, fontSize: "var(--t-xs)", color: "var(--texte-2)" }}>
          Les votes restent cachés jusqu'à la fin de la fenêtre.
        </p>
      </>
    );
  }

  // ---- Arbitrage : seulement sur égalité, et seulement une fois le temps écoulé ----
  if (tour.statut === "vote" && jeSuisPresentateur && chrono.ecoule) {
    return cadre(
      <>
        <Narration petit>Égalité des voix — tu tranches</Narration>
        <Panneau>
          <div style={{ fontSize: "var(--t-l)" }}>{tour.reponse_donnee}</div>
          <div style={{ fontSize: "var(--t-xs)", color: "var(--texte-2)" }}>contre</div>
          <div style={{ fontSize: "var(--t-l)" }}>{tour.reponse_revelee}</div>
        </Panneau>
        <div className="duo">
          <BoutonTampon ton="valide" disabled={occupe} onClick={() => void faire(() => rpc.arbitrer(tour.id, true))}>
            Ça compte
          </BoutonTampon>
          <BoutonTampon ton="refuse" disabled={occupe} onClick={() => void faire(() => rpc.arbitrer(tour.id, false))}>
            Ça compte pas
          </BoutonTampon>
        </div>
      </>
    );
  }

  // ---- Écrans neutres ----
  if (monTour) {
    return cadre(
      <>
        <Narration petit>C'est à vous</Narration>
        <p style={{ margin: 0, color: "var(--texte-2)" }}>
          Regarde la télé.{" "}
          {jeRepond
            ? tour.manche === "citez3"
              ? "Donne tes trois réponses à voix haute."
              : "À toi de répondre, à voix haute."
            : null}
        </p>
      </>
    );
  }

  return cadre(
    <>
      <Narration petit>
        {tour.statut === "juge"
          ? tour.verdict
            ? "Ça comptait"
            : "Ça comptait pas"
          : tour.j_ai_vote
            ? "Ton vote est enregistré"
            : "Au tour des autres"}
      </Narration>
      <p style={{ margin: 0, color: "var(--texte-2)", fontSize: "var(--t-s)" }}>
        {equipe.map((j) => j.prenom).join(" & ")} sont en jeu. Regarde la télé.
      </p>
    </>
  );
}
