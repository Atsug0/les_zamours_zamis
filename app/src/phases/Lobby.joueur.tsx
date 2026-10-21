import { useState } from "react";
import { rpc } from "../jeu/rpc";
import { BoutonTampon, Coeur, Eclair, Erreur, Narration, Panneau } from "../ui";
import { monBinome, monJoueur, partenaire, peutOrchestrer, type Etat } from "../jeu/usePartie";
import type { Mode } from "../jeu/types";

/** Le lobby vu du téléphone : s'apparier, choisir son mode. */
export default function LobbyJoueur({ e, pin }: { e: Etat; pin: string | null }) {
  const [erreur, setErreur] = useState<string | null>(null);
  const [occupe, setOccupe] = useState(false);
  const moi = monJoueur(e);
  const binome = monBinome(e);
  const autre = partenaire(e);
  const p = e.partie!;
  const jeSuisPresentateur = p.presentateur_id === e.moi;

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

  const libres = e.joueurs.filter(
    (j) => !j.binome_id && j.id !== e.moi && j.id !== p.presentateur_id
  );
  const seulSansBinome =
    !moi?.binome_id &&
    e.joueurs.filter((j) => !j.binome_id).length === 1 &&
    !p.presentateur_id;

  return (
    <div className="pile">
      {erreur && <Erreur>{erreur}</Erreur>}

      {pin && (
        <Panneau style={{ background: "var(--papier-2)" }}>
          <div style={{ fontSize: "var(--t-s)", color: "var(--texte-2)" }}>
            Ton code de reprise, si tu perds cet écran
          </div>
          <div
            style={{
              fontFamily: "var(--donnees)",
              fontSize: "var(--t-2xl)",
              fontWeight: 700,
              letterSpacing: ".2em",
            }}
          >
            {pin}
          </div>
        </Panneau>
      )}

      {jeSuisPresentateur ? (
        <Panneau>
          <Narration petit>Tu présentes</Narration>
          <p style={{ fontSize: "var(--t-s)", color: "var(--texte-2)" }}>
            Tu ne marques pas de points : tu arbitres les égalités et tu fais avancer l'émission.
          </p>
        </Panneau>
      ) : !binome ? (
        <>
          <Narration petit>Choisis ton binôme</Narration>
          {libres.length === 0 ? (
            <p style={{ color: "var(--texte-2)" }}>
              Personne d'autre n'est libre pour l'instant. Attends que quelqu'un rejoigne.
            </p>
          ) : (
            <div style={{ display: "grid", gap: "var(--e-2)" }}>
              {libres.map((j) => (
                <BoutonTampon
                  key={j.id}
                  ton="neutre"
                  disabled={occupe}
                  onClick={() => void faire(() => rpc.apparier(j.id))}
                >
                  {j.prenom}
                </BoutonTampon>
              ))}
            </div>
          )}
          {seulSansBinome && (
            <>
              <p style={{ color: "var(--texte-2)", fontSize: "var(--t-s)", margin: 0 }}>
                Vous êtes en nombre impair : tu peux présenter.
              </p>
              <BoutonTampon
                disabled={occupe}
                onClick={() => void faire(() => rpc.devenirPresentateur())}
              >
                Je présente
              </BoutonTampon>
            </>
          )}
        </>
      ) : !binome.verrouille ? (
        <>
          <Narration petit>Avec {autre?.prenom ?? "…"}</Narration>
          <p style={{ margin: 0, color: "var(--texte-2)", fontSize: "var(--t-s)" }}>
            Vous devez choisir <strong>le même mode</strong> tous les deux. Il décide des questions
            que vous aurez — pas seulement du ton.
          </p>
          <div style={{ display: "grid", gap: "var(--e-3)" }}>
            <ChoixMode
              mode="zamours"
              titre="Les Zamours"
              dit="En couple"
              choisi={moi?.a_choisi_mode === true}
              disabled={occupe}
              onClick={() => void faire(() => rpc.choisirMode("zamours"))}
            />
            <ChoixMode
              mode="zamis"
              titre="Les Zamis"
              dit="Amis, colocs, famille"
              choisi={moi?.a_choisi_mode === true}
              disabled={occupe}
              onClick={() => void faire(() => rpc.choisirMode("zamis"))}
            />
          </div>
          {autre && (
            <p style={{ margin: 0, fontSize: "var(--t-s)", color: "var(--texte-2)" }}>
              {autre.a_choisi_mode
                ? `${autre.prenom} a choisi. Si vos choix diffèrent, rien ne se verrouille.`
                : `${autre.prenom} n'a pas encore choisi.`}
            </p>
          )}
        </>
      ) : (
        <Panneau>
          <div className="rangee" style={{ alignItems: "center" }}>
            {binome.mode === "zamours" ? <Coeur taille={32} /> : <Eclair taille={32} />}
            <div>
              <div style={{ fontFamily: "var(--display)", textTransform: "uppercase" }}>
                {binome.mode === "zamours" ? "Les Zamours" : "Les Zamis"}
              </div>
              <div style={{ fontSize: "var(--t-s)", color: "var(--texte-2)" }}>
                Avec {autre?.prenom ?? "…"} · binôme {binome.couleur}
              </div>
            </div>
          </div>
          <p style={{ fontSize: "var(--t-s)", color: "var(--texte-2)", marginBottom: 0 }}>
            On attend que tous les binômes soient prêts.
          </p>
        </Panneau>
      )}

      {peutOrchestrer(e) && (
        <BoutonTampon disabled={occupe} onClick={() => void faire(() => rpc.lancer("court"))}>
          Lancer la partie
        </BoutonTampon>
      )}
    </div>
  );
}

function ChoixMode({ mode, titre, dit, choisi, disabled, onClick }: {
  mode: Mode;
  titre: string;
  dit: string;
  choisi: boolean;
  disabled: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      style={{
        display: "flex",
        alignItems: "center",
        gap: "var(--e-3)",
        textAlign: "left",
        cursor: disabled ? "not-allowed" : "pointer",
        border: "var(--filet-fort) solid var(--bord)",
        boxShadow: "var(--decalage) var(--decalage) 0 var(--ombre)",
        background: mode === "zamours" ? "var(--zamours)" : "var(--zamis)",
        color: "#15101b",
        padding: "var(--e-3)",
        opacity: choisi ? 0.75 : 1,
      }}
    >
      {mode === "zamours" ? <Coeur taille={38} couleur="#fff" /> : <Eclair taille={38} couleur="#fff" />}
      <span>
        <span
          style={{
            display: "block",
            fontFamily: "var(--display)",
            textTransform: "uppercase",
            fontSize: "var(--t-xl)",
          }}
        >
          {titre}
        </span>
        <span style={{ fontSize: "var(--t-s)" }}>{dit}</span>
      </span>
    </button>
  );
}
