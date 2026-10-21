import { useEffect, useMemo, useState } from "react";
import { rpc } from "../jeu/rpc";
import { question as texteQuestion } from "../jeu/banque";
import { formater, useChrono } from "../jeu/chrono";
import { BoutonTampon, Erreur, Narration, Panneau } from "../ui";
import { membres, monJoueur, peutOrchestrer, type Etat } from "../jeu/usePartie";
import type { Jugement } from "../jeu/types";

interface Attendue {
  question_id: string;
  attendue: string | null;
  passee: boolean | null;
}

/**
 * La finale sur le téléphone. Le questionneur est le SEUL à voir les
 * réponses attendues, et seulement une fois le chrono lancé.
 * Elles ne vivent que dans sa mémoire de navigateur — d'où
 * l'idempotence de rpc_demarrer_passage (0013) : un rechargement en
 * pleine finale les retrouve.
 */
export default function FinaleJoueur({ e }: { e: Etat }) {
  const [erreur, setErreur] = useState<string | null>(null);
  const [occupe, setOccupe] = useState(false);
  const [attendues, setAttendues] = useState<Attendue[] | null>(null);
  const moi = monJoueur(e);
  const passage = e.passages.find((p) => p.seuil_atteint === null) ?? null;
  const chrono = useChrono(passage?.chrono_fin_at ?? null, passage?.chrono_restant_ms ?? null);

  const jeQuestionne = !!passage && moi?.id === passage.questionneur_id;
  const monBinomeJoue = !!passage && moi?.binome_id === passage.binome_id;
  const lance = !!passage && (!!passage.chrono_fin_at || !!passage.chrono_restant_ms);

  // Reprise automatique : si je questionne un passage déjà lancé et que
  // je n'ai pas les réponses (rechargement), je les redemande.
  useEffect(() => {
    if (!jeQuestionne || !passage || !lance || attendues) return;
    void rpc
      .demarrerPassage(passage.id)
      .then((r) => setAttendues(r.questions))
      .catch((ex: unknown) => setErreur(ex instanceof Error ? ex.message : String(ex)));
  }, [jeQuestionne, passage?.id, lance, attendues]);

  useEffect(() => setAttendues(null), [passage?.id]);

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

  // L'ordre de lecture : les questions en attente d'abord, puis celles
  // qu'on a passées — « passer » les remet en fin de file (règles §8.1).
  const index = useMemo(() => {
    if (!passage) return null;
    const enAttente = passage.jugements.findIndex((j) => j === "attente");
    if (enAttente !== -1) return enAttente;
    const passees = passage.jugements.findIndex((j) => j === "passee");
    return passees === -1 ? null : passees;
  }, [passage?.jugements]);

  if (!passage) {
    return (
      <div className="pile">
        <Narration petit>La finale est jouée</Narration>
        <p style={{ margin: 0, color: "var(--texte-2)" }}>Regarde la télé.</p>
      </div>
    );
  }

  const equipe = membres(e, passage.binome_id);
  const cadre = (contenu: React.ReactNode) => (
    <div className="pile">
      {erreur && <Erreur>{erreur}</Erreur>}
      {contenu}
    </div>
  );

  // ---- Le binôme désigne qui joue ----
  if (monBinomeJoue && !passage.joueur_id) {
    return cadre(
      <>
        <Narration petit>Lequel de vous deux joue ?</Narration>
        <p style={{ margin: 0, fontSize: "var(--t-s)", color: "var(--texte-2)" }}>
          Celui qui joue devine les {e.partie?.reglages.questionsFinale} réponses de l'autre.
        </p>
        <div style={{ display: "grid", gap: "var(--e-2)" }}>
          {equipe.map((j) => (
            <BoutonTampon
              key={j.id}
              disabled={occupe}
              onClick={() => void faire(() => rpc.designerFinaliste(passage.id, j.id))}
            >
              {j.id === moi?.id ? `${j.prenom} (moi)` : j.prenom}
            </BoutonTampon>
          ))}
        </div>
      </>
    );
  }

  // ---- Le questionneur lance ----
  if (jeQuestionne && !lance) {
    const finaliste = e.joueurs.find((j) => j.id === passage.joueur_id);
    return cadre(
      <>
        <Narration petit>Tu mènes la finale</Narration>
        <Panneau>
          <p style={{ margin: 0, fontSize: "var(--t-s)" }}>
            Tu vas lire {e.partie?.reglages.questionsFinale} questions à voix haute et trancher
            au vol. Tu verras les réponses attendues — <strong>toi seul</strong>.
            {finaliste ? ` ${finaliste.prenom} répond à l'oral, immédiatement.` : null}
          </p>
        </Panneau>
        <BoutonTampon
          disabled={occupe}
          onClick={() =>
            void faire(async () => {
              const r = await rpc.demarrerPassage(passage.id);
              setAttendues(r.questions);
            })
          }
        >
          Lancer le chrono
        </BoutonTampon>
      </>
    );
  }

  // ---- Le questionneur tranche ----
  if (jeQuestionne && lance) {
    const q = index !== null ? attendues?.[index] : undefined;
    const texte = q ? texteQuestion(q.question_id) : null;
    const justes = passage.jugements.filter((j) => j === "juste").length;
    const reste = passage.jugements.filter((j) => j === "attente" || j === "passee").length;
    const fini = reste === 0 || chrono.ecoule;

    return cadre(
      <>
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            fontFamily: "var(--donnees)",
            fontSize: "var(--t-l)",
            fontVariantNumeric: "tabular-nums",
          }}
        >
          <span style={{ color: chrono.ms < 5000 ? "var(--refuse)" : "var(--texte)" }}>
            {formater(chrono.ms)}
          </span>
          <span>{justes} juste{justes > 1 ? "s" : ""}</span>
        </div>

        {fini ? (
          <>
            <Narration petit>{chrono.ecoule ? "Temps écoulé" : "Les cinq sont tranchées"}</Narration>
            <BoutonTampon
              disabled={occupe}
              onClick={() => void faire(() => rpc.clorePassage(passage.id))}
            >
              Clore le passage
            </BoutonTampon>
          </>
        ) : !attendues ? (
          <p style={{ color: "var(--texte-2)" }}>On récupère les réponses…</p>
        ) : q && index !== null ? (
          <>
            <Panneau>
              <div style={{ fontSize: "var(--t-xs)", color: "var(--texte-2)" }}>
                question {index + 1} — lis-la à voix haute
              </div>
              <p style={{ margin: "4px 0 0", fontSize: "var(--t-l)", lineHeight: 1.25 }}>
                {texte?.jeu ?? q.question_id}
              </p>
              <div
                style={{
                  marginTop: "var(--e-3)",
                  paddingTop: "var(--e-2)",
                  borderTop: "var(--filet) solid var(--bord)",
                }}
              >
                <div style={{ fontSize: "var(--t-xs)", color: "var(--texte-2)" }}>
                  réponse attendue
                </div>
                <strong style={{ fontSize: "var(--t-xl)" }}>
                  {q.passee ? <em style={{ color: "var(--texte-2)" }}>passée en prépa</em> : q.attendue}
                </strong>
              </div>
            </Panneau>
            <div className="duo">
              <BoutonTampon
                ton="valide"
                disabled={occupe}
                onClick={() => void faire(() => rpc.juger(passage.id, index + 1, "juste"))}
              >
                Juste
              </BoutonTampon>
              <BoutonTampon
                ton="refuse"
                disabled={occupe}
                onClick={() => void faire(() => rpc.juger(passage.id, index + 1, "faux"))}
              >
                Faux
              </BoutonTampon>
            </div>
            <BoutonTampon
              ton="neutre"
              disabled={occupe}
              onClick={() => void faire(() => rpc.juger(passage.id, index + 1, "passee" as Jugement))}
            >
              Passer — on y revient si le temps le permet
            </BoutonTampon>
          </>
        ) : null}
      </>
    );
  }

  // ---- Le finaliste, et tous les autres ----
  if (passage.joueur_id === moi?.id) {
    return cadre(
      <>
        <Narration petit>À toi — réponds à voix haute</Narration>
        <p style={{ margin: 0, color: "var(--texte-2)" }}>
          Ne regarde pas ton téléphone, regarde la télé. {formater(chrono.ms)}
        </p>
        {peutOrchestrer(e) && null}
      </>
    );
  }

  return cadre(
    <>
      <Narration petit>
        {equipe.map((j) => j.prenom).join(" & ")} en finale
      </Narration>
      <p style={{ margin: 0, color: "var(--texte-2)", fontSize: "var(--t-s)" }}>
        {monBinomeJoue ? "Tu as laissé la main. Silence." : "Regarde la télé."}
      </p>
    </>
  );
}
