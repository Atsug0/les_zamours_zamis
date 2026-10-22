import { useEffect, useState } from "react";
import { session } from "../jeu/supabase";
import { tourCourant, usePartie } from "../jeu/usePartie";
import { useBots, useOrchestration } from "../jeu/orchestration";
import { usePleinEcran, useTelecommande } from "../jeu/telecommande";
import { useSons } from "../jeu/useSons";
import { basculerLeSon, estMuet } from "../jeu/sons";
import { rpc } from "../jeu/rpc";
import { Erreur, Lettrage, Narration, Trame } from "../ui";
import LobbyPlateau from "../phases/Lobby.plateau";
import PrepPlateau from "../phases/Prep.plateau";
import manchePlateau from "../phases/Manche.plateau";
import FinalePlateau from "../phases/Finale.plateau";
import PalmaresPlateau from "../phases/Palmares.plateau";
import SujetPlateau from "../phases/Sujet.plateau";
import { rpc as api } from "../jeu/rpc";

/** La vue télé. C'est aussi l'horloge de la partie (ARCHITECTURE.md §3.d). */
export default function Plateau({ code }: { code: string }) {
  const [moi, setMoi] = useState<string | null>(null);
  useEffect(() => {
    void session().then(setMoi);
  }, []);

  const e = usePartie(code, moi);
  useOrchestration(e);
  useBots(e);
  useSons(e);
  useTelecommande(true);
  const [muet, setMuet] = useState(() => estMuet());
  const { plein, basculer, possible } = usePleinEcran();

  // Le plateau surveille la présence du joueur attendu et gèle les
  // chronos s'il disparaît. Aucun job planifié n'est nécessaire.
  useEffect(() => {
    if (!e.partie || e.partie.plateau_id !== moi) return;
    const t = setInterval(() => void rpc.verifierPresence().catch(() => {}), 8_000);
    return () => clearInterval(t);
  }, [e.partie?.id, e.partie?.plateau_id, moi]);

  if (e.chargement) return <Attente />;
  if (e.erreur || !e.partie) return <div className="centre"><Erreur>{e.erreur ?? "Partie introuvable."}</Erreur></div>;

  const tour = tourCourant(e);
  return (
    <div
      className="plateau-cadre"
      data-phase={e.partie.etat}
      data-mode={e.partie.mode_jeu}
      data-tour={tour?.ordre ?? ""}
      data-statut={tour?.statut ?? ""}
      data-pause={e.partie.en_pause ? "1" : ""}
    >
      <Bandeau
        code={e.partie.code}
        phase={e.partie.etat}
        enPause={e.partie.en_pause}
        demo={e.partie.demo}
        muet={muet}
        couperLeSon={() => setMuet(basculerLeSon())}
        plein={plein}
        basculer={basculer}
        possible={possible}
      />
      <Scene e={e} />
    </div>
  );
}

function Scene({ e }: { e: ReturnType<typeof usePartie> }) {
  const tour = tourCourant(e);
  switch (e.partie?.etat) {
    case "lobby":
      return <LobbyPlateau e={e} />;
    case "prep":
      return <PrepPlateau e={e} onSuivant={() => void api.suivant().catch(() => {})} />;
    case "qcm":
    case "libre":
    case "citez3":
    case "bonus":
      if (!tour) return <Attente />;
      return e.partie.mode_jeu === "sujet" || e.partie.mode_jeu === "tournoi"
        ? SujetPlateau({ e, tour })
        : manchePlateau({ e, tour });
    case "finale":
      return <FinalePlateau e={e} />;
    case "palmares":
      return <PalmaresPlateau e={e} />;
    default:
      return <Attente />;
  }
}

function Bandeau({ code, phase, enPause, demo, muet, couperLeSon, plein, basculer, possible }: {
  code: string;
  phase: string;
  enPause: boolean;
  demo: boolean;
  muet: boolean;
  couperLeSon: () => void;
  plein: boolean;
  basculer: () => void;
  possible: boolean;
}) {
  const noms: Record<string, string> = {
    lobby: "en attente des joueurs",
    prep: "préparation",
    qcm: "manche 1 · QCM",
    libre: "manche 2 · questions libres",
    citez3: "manche « cite 3 »",
    bonus: "question bonus",
    finale: "finale",
    palmares: "palmarès",
  };
  return (
    <header
      style={{
        display: "flex",
        justifyContent: "space-between",
        alignItems: "center",
        gap: "var(--e-3)",
        padding: "var(--e-3) var(--e-4)",
        borderBottom: "var(--filet) solid var(--bord)",
        background: "var(--encre)",
      }}
    >
      <Lettrage taille="var(--t-l)" couleur="var(--jaune)">
        Les Zamours Zamis
      </Lettrage>
      <span
        style={{
          fontFamily: "var(--donnees)",
          fontSize: "var(--t-xs)",
          color: "var(--papier)",
          opacity: 0.75,
        }}
      >
        {code} · {noms[phase] ?? phase}
      </span>
      {enPause && <Narration petit>En pause</Narration>}
      {demo && <Narration petit>Démo</Narration>}
      <button
        type="button"
        data-tc=""
        onClick={couperLeSon}
        aria-label={muet ? "Remettre le son" : "Couper le son"}
        style={{
          border: "var(--filet) solid var(--papier)",
          background: "transparent",
          color: "var(--papier)",
          fontSize: "var(--t-s)",
          lineHeight: 1,
          padding: "4px 8px",
          cursor: "pointer",
        }}
      >
        {/* une icône dessinée plutôt qu'un emoji : tous les navigateurs
            n'embarquent pas de police emoji, et une télé encore moins */}
        <svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true">
          <path d="M4 9h4l5-4v14l-5-4H4z" fill="currentColor" />
          {muet ? (
            <path d="M16 9l5 6M21 9l-5 6" stroke="currentColor" strokeWidth="2" fill="none" />
          ) : (
            <path
              d="M16.5 8.5a5 5 0 0 1 0 7M19 6a8.5 8.5 0 0 1 0 12"
              stroke="currentColor"
              strokeWidth="2"
              fill="none"
            />
          )}
        </svg>
      </button>
      {possible && !plein && (
        <button
          type="button"
          data-tc=""
          onClick={basculer}
          className="masquer-en-plein"
          style={{
            border: "var(--filet) solid var(--papier)",
            background: "transparent",
            color: "var(--papier)",
            fontFamily: "var(--display)",
            textTransform: "uppercase",
            letterSpacing: ".06em",
            fontSize: "var(--t-xs)",
            padding: "2px var(--e-2)",
            cursor: "pointer",
          }}
        >
          Plein écran
        </button>
      )}
    </header>
  );
}

function Attente() {
  return (
    <Trame style={{ minHeight: "100%" }}>
      <div className="centre">
        <Lettrage taille="var(--t-2xl)" couleur="var(--zamours)">
          On allume le plateau…
        </Lettrage>
      </div>
    </Trame>
  );
}
