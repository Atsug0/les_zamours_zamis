import { useEffect, useState } from "react";
import { session } from "../jeu/supabase";
import { monJoueur, tourCourant, usePartie } from "../jeu/usePartie";
import { BoutonTampon, Erreur, Narration, Panneau } from "../ui";
import { rpc } from "../jeu/rpc";
import LobbyJoueur from "../phases/Lobby.joueur";
import PrepJoueur from "../phases/Prep.joueur";
import mancheJoueur from "../phases/Manche.joueur";
import FinaleJoueur from "../phases/Finale.joueur";
import PalmaresJoueur from "../phases/Palmares.joueur";
import SujetJoueur from "../phases/Sujet.joueur";

/** La vue téléphone : une seule action à la fois. */
export default function Joueur({ code }: { code: string }) {
  const [moi, setMoi] = useState<string | null>(null);
  useEffect(() => {
    void session().then(setMoi);
  }, []);

  const e = usePartie(code, moi);
  const j = monJoueur(e);
  const pin = sessionStorage.getItem("zamours.pin");

  if (e.chargement) return <div className="centre">Un instant…</div>;
  if (e.erreur || !e.partie)
    return (
      <div className="centre">
        <Erreur>{e.erreur ?? "Partie introuvable."}</Erreur>
      </div>
    );

  // Session perdue (autre navigateur, données effacées) : reprise par PIN.
  if (!j && e.partie.plateau_id !== moi) return <Reprise code={code} />;

  return (
    <div className="tel-cadre">
      <header
        style={{
          display: "flex",
          justifyContent: "space-between",
          padding: "var(--e-2) var(--e-3)",
          borderBottom: "var(--filet) solid var(--bord)",
          fontFamily: "var(--donnees)",
          fontSize: "var(--t-xs)",
          color: "var(--texte-2)",
        }}
      >
        <span>{e.partie.code}</span>
        <span>{j?.prenom ?? "plateau"}</span>
      </header>

      {e.partie.en_pause && (
        <div style={{ padding: "var(--e-3)" }}>
          <Narration petit>En pause — on attend quelqu'un</Narration>
        </div>
      )}

      <Pupitre e={e} pin={pin} />
    </div>
  );
}

function Pupitre({ e, pin }: { e: ReturnType<typeof usePartie>; pin: string | null }) {
  const tour = tourCourant(e);
  switch (e.partie?.etat) {
    case "lobby":
      return <LobbyJoueur e={e} pin={pin} />;
    case "prep":
      return <PrepJoueur e={e} />;
    case "qcm":
    case "libre":
    case "citez3":
    case "bonus":
      if (!tour) return <div className="centre">Un instant…</div>;
      return e.partie?.mode_jeu === "sujet"
        ? SujetJoueur({ e, tour })
        : mancheJoueur({ e, tour });
    case "finale":
      return <FinaleJoueur e={e} />;
    case "palmares":
      return <PalmaresJoueur e={e} />;
    default:
      return <div className="centre">Un instant…</div>;
  }
}

/** Reprise de siège par PIN (ARCHITECTURE.md §10.b). */
function Reprise({ code }: { code: string }) {
  const [prenom, setPrenom] = useState("");
  const [pin, setPin] = useState("");
  const [erreur, setErreur] = useState<string | null>(null);

  return (
    <div className="pile">
      <Narration petit>Reprendre ta place</Narration>
      <p style={{ margin: 0, color: "var(--texte-2)", fontSize: "var(--t-s)" }}>
        Ce navigateur ne reconnaît pas ta session. Entre ton prénom et le code de reprise à
        4 chiffres qu'on t'a montré au départ.
      </p>
      {erreur && <Erreur>{erreur}</Erreur>}
      <input
        value={prenom}
        onChange={(e) => setPrenom(e.target.value)}
        placeholder="Ton prénom"
        style={{ border: "var(--filet) solid var(--bord)", padding: "var(--e-2)", fontSize: "var(--t-l)" }}
      />
      <input
        value={pin}
        onChange={(e) => setPin(e.target.value.replace(/\D/g, "").slice(0, 4))}
        placeholder="0000"
        inputMode="numeric"
        style={{
          border: "var(--filet) solid var(--bord)",
          padding: "var(--e-2)",
          fontFamily: "var(--donnees)",
          fontSize: "var(--t-2xl)",
          letterSpacing: ".3em",
        }}
      />
      <BoutonTampon
        disabled={prenom.trim().length === 0 || pin.length !== 4}
        onClick={() => {
          setErreur(null);
          rpc
            .reprendreSiege(code, prenom, pin)
            .then(() => location.reload())
            .catch((ex: unknown) => setErreur(ex instanceof Error ? ex.message : String(ex)));
        }}
      >
        Reprendre ma place
      </BoutonTampon>
      <Panneau style={{ background: "var(--papier-2)" }}>
        <p style={{ margin: 0, fontSize: "var(--t-s)", color: "var(--texte-2)" }}>
          Tu n'as plus le code ? L'hôte peut te rendre ta place depuis son téléphone.
        </p>
      </Panneau>
    </div>
  );
}
