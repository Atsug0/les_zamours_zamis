import { useEffect, useState } from "react";
import { session } from "../jeu/supabase";
import { usePartie } from "../jeu/usePartie";
import { rpc } from "../jeu/rpc";
import { Erreur, Lettrage, Narration, Trame } from "../ui";
import LobbyPlateau from "../phases/Lobby.plateau";
import EnConstruction from "../phases/EnConstruction";

/** La vue télé. C'est aussi l'horloge de la partie (ARCHITECTURE.md §3.d). */
export default function Plateau({ code }: { code: string }) {
  const [moi, setMoi] = useState<string | null>(null);
  useEffect(() => {
    void session().then(setMoi);
  }, []);

  const e = usePartie(code, moi);

  // Le plateau surveille la présence du joueur attendu et gèle les
  // chronos s'il disparaît. Aucun job planifié n'est nécessaire.
  useEffect(() => {
    if (!e.partie || e.partie.plateau_id !== moi) return;
    const t = setInterval(() => void rpc.verifierPresence().catch(() => {}), 8_000);
    return () => clearInterval(t);
  }, [e.partie?.id, e.partie?.plateau_id, moi]);

  if (e.chargement) return <Attente />;
  if (e.erreur || !e.partie) return <div className="centre"><Erreur>{e.erreur ?? "Partie introuvable."}</Erreur></div>;

  return (
    <div className="plateau-cadre">
      <Bandeau code={e.partie.code} phase={e.partie.etat} enPause={e.partie.en_pause} />
      {e.partie.etat === "lobby" ? <LobbyPlateau e={e} /> : <EnConstruction e={e} cote="plateau" />}
    </div>
  );
}

function Bandeau({ code, phase, enPause }: { code: string; phase: string; enPause: boolean }) {
  const noms: Record<string, string> = {
    lobby: "en attente des joueurs",
    prep: "préparation",
    qcm: "manche 1 · QCM",
    libre: "manche 2 · questions libres",
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
