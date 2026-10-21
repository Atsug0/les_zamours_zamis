import { useState } from "react";
import { rpc } from "../jeu/rpc";
import { memoire, session } from "../jeu/supabase";
import { BoutonTampon, Coeur, Erreur, Lettrage, Narration, Panneau, Trame } from "../ui";
import { aller } from "../routeur";
import { useTelecommande } from "../jeu/telecommande";

/** Page d'entrée : créer une partie sur la télé, ou rejoindre avec un code. */
export default function Accueil() {
  const [code, setCode] = useState("");
  const [prenom, setPrenom] = useState("");
  const [erreur, setErreur] = useState<string | null>(null);
  const [occupe, setOccupe] = useState(false);
  const derniere = memoire.lire();
  useTelecommande(true);

  const faire = async (f: () => Promise<void>) => {
    setErreur(null);
    setOccupe(true);
    try {
      await session();
      await f();
    } catch (ex) {
      setErreur(ex instanceof Error ? ex.message : String(ex));
    } finally {
      setOccupe(false);
    }
  };

  return (
    <Trame style={{ minHeight: "100%" }}>
      <div className="centre">
        <div style={{ display: "grid", gap: "var(--e-3)", justifyItems: "center" }}>
          <Coeur taille={72} />
          <h1 style={{ margin: 0 }}>
            <Lettrage taille="clamp(2.5rem, 9vw, 4.5rem)" couleur="var(--zamours)" ombre="var(--bleu)">
              Les Zamours
            </Lettrage>
            <br />
            <Lettrage taille="clamp(2.5rem, 9vw, 4.5rem)" couleur="var(--zamis)" ombre="var(--bleu)">
              Zamis
            </Lettrage>
          </h1>
          <p style={{ margin: 0, color: "var(--texte-2)", maxWidth: "40ch" }}>
            Le jeu de complicité. La télé fait le plateau, les téléphones font les pupitres.
          </p>
        </div>

        {erreur && <Erreur>{erreur}</Erreur>}

        {derniere && (
          <Panneau style={{ background: "var(--papier-2)" }}>
            <div style={{ fontSize: "var(--t-s)", color: "var(--texte-2)" }}>
              Tu étais dans la partie {derniere.code}
            </div>
            <div className="rangee" style={{ marginTop: "var(--e-2)" }}>
              <BoutonTampon
                large={false}
                onClick={() =>
                  aller(derniere.role === "plateau" ? `/tv/${derniere.code}` : `/p/${derniere.code}`)
                }
              >
                Y retourner
              </BoutonTampon>
              <BoutonTampon large={false} ton="neutre" onClick={() => { memoire.oublier(); location.reload(); }}>
                Oublier
              </BoutonTampon>
            </div>
          </Panneau>
        )}

        <Panneau style={{ width: "min(420px, 100%)", textAlign: "left" }}>
          <Narration petit>Sur le téléphone</Narration>
          <div style={{ display: "grid", gap: "var(--e-3)", marginTop: "var(--e-3)" }}>
            <Champ
              etiquette="Le code affiché sur la télé"
              valeur={code}
              onChange={(v) => setCode(v.toUpperCase().slice(0, 4))}
              placeholder="ABCD"
              style={{
                fontFamily: "var(--donnees)",
                fontSize: "var(--t-2xl)",
                letterSpacing: ".3em",
                textTransform: "uppercase",
              }}
            />
            <Champ
              etiquette="Ton prénom"
              valeur={prenom}
              onChange={(v) => setPrenom(v.slice(0, 24))}
              placeholder="Sam"
            />
            <BoutonTampon
              disabled={occupe || code.length !== 4 || prenom.trim().length === 0}
              onClick={() =>
                void faire(async () => {
                  const r = await rpc.rejoindre(code, prenom);
                  sessionStorage.setItem("zamours.pin", r.pin);
                  memoire.ecrire(code.toUpperCase(), "joueur");
                  aller(`/p/${code.toUpperCase()}`);
                })
              }
            >
              Rejoindre
            </BoutonTampon>
          </div>
        </Panneau>

        <Panneau style={{ width: "min(420px, 100%)", textAlign: "left" }}>
          <Narration petit>Sur la télé</Narration>
          <p style={{ fontSize: "var(--t-s)", color: "var(--texte-2)", margin: "var(--e-3) 0" }}>
            À faire sur l'écran que tout le monde regarde. Il affichera le code à partager.
          </p>
          <BoutonTampon
            ton="neutre"
            disabled={occupe}
            onClick={() =>
              void faire(async () => {
                const r = await rpc.creerPartie();
                memoire.ecrire(r.code, "plateau");
                aller(`/tv/${r.code}`);
              })
            }
          >
            Ouvrir le plateau
          </BoutonTampon>
        </Panneau>
      </div>
    </Trame>
  );
}

function Champ({ etiquette, valeur, onChange, placeholder, style }: {
  etiquette: string;
  valeur: string;
  onChange: (v: string) => void;
  placeholder?: string;
  style?: React.CSSProperties;
}) {
  return (
    <label style={{ display: "grid", gap: "var(--e-1)" }}>
      <span
        style={{
          fontFamily: "var(--display)",
          textTransform: "uppercase",
          fontSize: "var(--t-xs)",
          letterSpacing: ".08em",
          color: "var(--texte-2)",
        }}
      >
        {etiquette}
      </span>
      <input
        value={valeur}
        onChange={(ev) => onChange(ev.target.value)}
        placeholder={placeholder}
        autoComplete="off"
        style={{
          border: "var(--filet) solid var(--bord)",
          background: "var(--papier)",
          color: "var(--texte)",
          padding: "var(--e-2) var(--e-3)",
          fontSize: "var(--t-l)",
          fontFamily: "var(--corps)",
          ...style,
        }}
      />
    </label>
  );
}
