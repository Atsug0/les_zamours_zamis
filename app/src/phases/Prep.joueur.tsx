import { useEffect, useMemo, useState } from "react";
import { rpc } from "../jeu/rpc";
import { question as texteQuestion } from "../jeu/banque";
import { BoutonTampon, Erreur, Narration, Panneau } from "../ui";
import { partenaire, type Etat } from "../jeu/usePartie";

type Reponses = Record<string, { valeur: string; passee: boolean }>;

/**
 * La préparation sur le téléphone : une question à la fois, sur
 * soi-même, au tutoiement. Chaque réponse est envoyée séparément —
 * fermer la page ne perd que la saisie en cours (§10.d).
 */
export default function PrepJoueur({ e }: { e: Etat }) {
  const [questions, setQuestions] = useState<string[] | null>(null);
  const [reponses, setReponses] = useState<Reponses>({});
  const [index, setIndex] = useState<number | null>(null);
  const [saisie, setSaisie] = useState("");
  const [erreur, setErreur] = useState<string | null>(null);
  const [occupe, setOccupe] = useState(false);
  const autre = partenaire(e);

  useEffect(() => {
    let vivant = true;
    void (async () => {
      try {
        const [q, r] = await Promise.all([rpc.mesQuestions(), rpc.mesReponses()]);
        if (!vivant) return;
        setQuestions(q.questions);
        setReponses(r);
        const premier = q.questions.findIndex((id) => !(id in r));
        setIndex(premier === -1 ? null : premier);
      } catch (ex) {
        if (vivant) setErreur(ex instanceof Error ? ex.message : String(ex));
      }
    })();
    return () => {
      vivant = false;
    };
  }, []);

  const courante = useMemo(() => {
    if (!questions || index === null) return null;
    const id = questions[index];
    // les énoncés « cite 3 » parlent du partenaire : il faut son prénom
    return id ? { id, q: texteQuestion(id, autre?.prenom ?? "ton binôme") } : null;
  }, [questions, index, autre?.prenom]);

  useEffect(() => {
    if (!courante) return;
    setSaisie(reponses[courante.id]?.valeur ?? "");
  }, [courante?.id]);

  if (erreur && !questions) return <div className="pile"><Erreur>{erreur}</Erreur></div>;
  if (!questions) return <div className="centre">On prépare tes questions…</div>;

  const faites = Object.keys(reponses).length;
  const total = questions.length;

  const envoyer = async (passee: boolean) => {
    if (!courante) return;
    setErreur(null);
    setOccupe(true);
    try {
      await rpc.repondrePrepa(courante.id, passee ? "" : saisie, passee);
      setReponses((r) => ({ ...r, [courante.id]: { valeur: passee ? "" : saisie, passee } }));
      const suivant = questions.findIndex(
        (id, i) => i > (index ?? -1) && !(id in reponses) && id !== courante.id
      );
      setIndex(suivant === -1 ? null : suivant);
    } catch (ex) {
      setErreur(ex instanceof Error ? ex.message : String(ex));
    } finally {
      setOccupe(false);
    }
  };

  // Tout est rempli : on peut encore revenir corriger.
  if (!courante) {
    return (
      <div className="pile">
        <Narration petit>C'est bon pour toi</Narration>
        <p style={{ margin: 0, color: "var(--texte-2)", fontSize: "var(--t-s)" }}>
          {autre ? `${autre.prenom} devra retrouver ces réponses.` : null} On attend les autres —
          regarde la télé. Tu peux encore corriger ce que tu veux.
        </p>
        <div style={{ display: "grid", gap: "var(--e-2)" }}>
          {questions.map((id, i) => {
            const q = texteQuestion(id, autre?.prenom ?? "ton binôme");
            const r = reponses[id];
            return (
              <button
                key={id}
                type="button"
                onClick={() => setIndex(i)}
                style={{
                  textAlign: "left",
                  border: "var(--filet) solid var(--bord)",
                  background: "var(--papier)",
                  padding: "var(--e-2) var(--e-3)",
                  cursor: "pointer",
                  display: "grid",
                  gap: 2,
                }}
              >
                <span style={{ fontSize: "var(--t-xs)", color: "var(--texte-2)" }}>
                  {q?.prepa ?? id}
                </span>
                <span style={{ fontSize: "var(--t-l)" }}>
                  {r?.passee ? <em style={{ color: "var(--texte-2)" }}>passée</em> : r?.valeur}
                </span>
              </button>
            );
          })}
        </div>
      </div>
    );
  }

  return (
    <div className="pile">
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          fontFamily: "var(--donnees)",
          fontSize: "var(--t-xs)",
          color: "var(--texte-2)",
        }}
      >
        <span>
          question {(index ?? 0) + 1} / {total}
        </span>
        <span>{faites} remplie{faites > 1 ? "s" : ""}</span>
      </div>

      {erreur && <Erreur>{erreur}</Erreur>}

      <Panneau>
        <p style={{ margin: 0, fontSize: "var(--t-xl)", lineHeight: 1.25 }}>
          {courante.q?.prepa ?? courante.id}
        </p>
        {courante.q?.tol && (
          <p style={{ margin: "var(--e-2) 0 0", fontSize: "var(--t-xs)", color: "var(--texte-2)" }}>
            tolérance à l'arbitrage : {courante.q.tol}
          </p>
        )}
      </Panneau>

      {courante.q?.props ? (
        <div style={{ display: "grid", gap: "var(--e-2)" }}>
          {courante.q.props.map((p) => (
            <BoutonTampon
              key={p}
              ton={saisie === p ? "jaune" : "neutre"}
              disabled={occupe}
              onClick={() => setSaisie(p)}
            >
              {p}
            </BoutonTampon>
          ))}
        </div>
      ) : (
        <input
          value={saisie}
          onChange={(ev) => setSaisie(ev.target.value.slice(0, 80))}
          placeholder="Ta réponse, en quelques mots"
          autoFocus
          style={{
            border: "var(--filet) solid var(--bord)",
            background: "var(--papier)",
            color: "var(--texte)",
            padding: "var(--e-3)",
            fontSize: "var(--t-l)",
            fontFamily: "var(--corps)",
          }}
        />
      )}

      <BoutonTampon disabled={occupe || saisie.trim().length === 0} onClick={() => void envoyer(false)}>
        Valider
      </BoutonTampon>
      <BoutonTampon ton="neutre" disabled={occupe} onClick={() => void envoyer(true)}>
        Passer cette question
      </BoutonTampon>
      <p style={{ margin: 0, fontSize: "var(--t-xs)", color: "var(--texte-2)" }}>
        Passer ne coûte que le point. Aucune question n'est obligatoire.
      </p>
    </div>
  );
}
