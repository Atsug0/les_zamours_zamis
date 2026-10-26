import { useState } from "react";
import { rpc } from "../jeu/rpc";
import { BoutonTampon, Coeur, Eclair, Erreur, Narration, Panneau } from "../ui";
import {
  modeSujet, monBinome, monJoueur, partenaire, peutOrchestrer, suisJeSujet, type Etat,
} from "../jeu/usePartie";
import type { Mode } from "../jeu/types";
import { aller } from "../routeur";

/** Le lobby vu du téléphone : s'apparier, choisir son mode. */
export default function LobbyJoueur({ e, pin }: { e: Etat; pin: string | null }) {
  const [erreur, setErreur] = useState<string | null>(null);
  const [occupe, setOccupe] = useState(false);
  const [modeVoulu, setModeVoulu] = useState<Mode | null>(null);
  const [sensibles, setSensibles] = useState(false);
  const [mariage, setMariage] = useState(false);
  const [format, setFormat] = useState<"court" | "long">("court");
  const [citez3, setCitez3] = useState(false);
  const [modeJeu, setModeJeu] = useState<"binomes" | "paris">("binomes");
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
  const sujet = modeSujet(e);
  const jeSuisLeSujet = suisJeSujet(e);
  const challengers = e.joueurs.filter((j) => j.id !== p.sujet_id);
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

      {sujet ? (
        jeSuisLeSujet ? (
          <Panneau>
            <Narration petit>Tu es le sujet</Narration>
            <p style={{ fontSize: "var(--t-s)", color: "var(--texte-2)" }}>
              Tout le monde va essayer de te deviner. Tu réponds en secret juste avant eux,
              question par question — <strong>aucune préparation</strong> — et c'est toi qui dis
              si une réponse compte. Tu ne marques pas de points : tu es la ligne d'arrivée.
            </p>
            <p style={{ fontSize: "var(--t-s)", margin: 0 }}>
              {challengers.length} challenger{challengers.length > 1 ? "s" : ""} :{" "}
              {challengers.map((j) => j.prenom).join(", ") || "personne encore"}
            </p>
          </Panneau>
        ) : (
          <Panneau>
            <Narration petit>
              Qui connaît le mieux {e.joueurs.find((j) => j.id === p.sujet_id)?.prenom ?? "?"} ?
            </Narration>
            <p style={{ fontSize: "var(--t-s)", color: "var(--texte-2)", marginBottom: 0 }}>
              Pas de binôme dans ce mode : tu joues pour toi. À chaque question, tout le monde
              répond en même temps et le sujet dit qui a trouvé.
            </p>
          </Panneau>
        )
      ) : jeSuisPresentateur ? (
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
          <Panneau style={{ background: "var(--papier-2)" }}>
            <Narration petit>Ou un autre jeu</Narration>
            <p style={{ fontSize: "var(--t-s)", color: "var(--texte-2)" }}>
              <strong>Qui connaît le mieux… toi ?</strong> Tu réponds à tout, les autres
              s'affrontent pour te deviner. Sans binôme, et sans préparation.
            </p>
            <BoutonTampon
              ton="neutre"
              disabled={occupe}
              onClick={() => void faire(() => rpc.devenirSujet())}
            >
              Je suis le sujet
            </BoutonTampon>

            {peutOrchestrer(e) && e.joueurs.length >= 3 && (
              <>
                <p style={{ fontSize: "var(--t-s)", color: "var(--texte-2)", marginTop: "var(--e-4)" }}>
                  <strong>Le tournoi.</strong> Chacun passe sur le gril à son tour, et marque des
                  points en devinant les autres le reste du temps. Un seul classement : qui connaît
                  le mieux le groupe.
                </p>
                <BoutonTampon
                  ton="neutre"
                  disabled={occupe}
                  onClick={() => void faire(() => rpc.lancerTournoi(format))}
                >
                  Lancer un tournoi
                </BoutonTampon>
              </>
            )}
          </Panneau>

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
            Vous devez choisir <strong>exactement la même chose</strong> tous les deux : le mode
            décide des questions que vous aurez, pas seulement du ton.
          </p>

          <div style={{ display: "grid", gap: "var(--e-3)" }}>
            <ChoixMode
              mode="zamours"
              titre="Les Zamours"
              dit="En couple"
              choisi={modeVoulu === "zamours"}
              disabled={occupe}
              onClick={() => setModeVoulu("zamours")}
            />
            <ChoixMode
              mode="zamis"
              titre="Les Zamis"
              dit="Amis, colocs, famille"
              choisi={modeVoulu === "zamis"}
              disabled={occupe}
              onClick={() => { setModeVoulu("zamis"); setMariage(false); }}
            />
          </div>

          {modeVoulu && (
            <Panneau style={{ background: "var(--papier-2)" }}>
              <Narration petit>Options du binôme</Narration>
              <div style={{ display: "grid", gap: "var(--e-3)", marginTop: "var(--e-3)" }}>
                <Bascule
                  active={sensibles}
                  onChange={setSensibles}
                  titre="Mode croustillant"
                  dit="Débloque les questions qui piquent vraiment : rancunes, petits mensonges, argent, intime. Il faut être d'accord à deux."
                />
                {modeVoulu === "zamours" && (
                  <Bascule
                    active={mariage}
                    onChange={setMariage}
                    titre="Bloc mariage"
                    dit="Les questions du jour J. À cocher si vous vous mariez bientôt."
                  />
                )}
              </div>
              <p style={{ margin: "var(--e-3) 0 0", fontSize: "var(--t-xs)", color: "var(--texte-2)" }}>
                Une option n'est retenue que si <strong>tous les binômes du même mode</strong>
                l'activent : le tirage doit rester identique pour que le vote des autres soit juste.
              </p>
            </Panneau>
          )}

          {modeVoulu && (
            <BoutonTampon
              disabled={occupe}
              onClick={() =>
                void faire(() =>
                  rpc.choisirMode(modeVoulu, sensibles, mariage ? ["mariage"] : [])
                )
              }
            >
              Je valide ce choix
            </BoutonTampon>
          )}

          {autre?.mode_choisi && (
            <Panneau>
              <div style={{ fontSize: "var(--t-s)" }}>
                <strong>{autre.prenom}</strong> a choisi{" "}
                <strong>{autre.mode_choisi === "zamours" ? "Les Zamours" : "Les Zamis"}</strong>
                {autre.sensibles_choisi ? ", catégories sensibles activées" : ""}
                {autre.occasions_choisies.includes("mariage") ? ", bloc mariage" : ""}.
              </div>
              <button
                type="button"
                disabled={occupe}
                onClick={() => {
                  setModeVoulu(autre.mode_choisi);
                  setSensibles(autre.sensibles_choisi);
                  setMariage(autre.occasions_choisies.includes("mariage"));
                }}
                style={{
                  marginTop: "var(--e-2)",
                  border: "var(--filet) solid var(--bord)",
                  background: "var(--jaune)",
                  color: "#15101b",
                  padding: "var(--e-1) var(--e-3)",
                  fontFamily: "var(--display)",
                  textTransform: "uppercase",
                  cursor: "pointer",
                }}
              >
                M'aligner sur son choix
              </button>
            </Panneau>
          )}
          {autre && !autre.mode_choisi && (
            <p style={{ margin: 0, fontSize: "var(--t-s)", color: "var(--texte-2)" }}>
              {autre.prenom} n'a pas encore choisi.
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
        <Panneau>
          <Narration petit>À toi de lancer</Narration>
          <div style={{ display: "grid", gap: "var(--e-2)", margin: "var(--e-3) 0" }}>
            <ChoixFormat
              actif={format === "court"}
              onClick={() => setFormat("court")}
              titre="Format court"
              dit="2 ouvertes + 1 QCM par joueur, finale à 5 questions. 35 à 50 min à 4 binômes."
            />
            <ChoixFormat
              actif={format === "long"}
              onClick={() => setFormat("long")}
              titre="Format long"
              dit="3 ouvertes + 2 QCM, finale à 7 questions en 45 s. Le double de temps."
            />
          </div>
          {!sujet && e.binomes.length >= 2 && (
            <div style={{ display: "grid", gap: "var(--e-2)", marginBottom: "var(--e-3)" }}>
              <ChoixFormat
                actif={modeJeu === "binomes"}
                onClick={() => void faire(async () => {
                  setModeJeu("binomes");
                  await rpc.choisirModeJeu("binomes");
                })}
                titre="Binômes classiques"
                dit="Les autres binômes votent sur les réponses libres."
              />
              <ChoixFormat
                actif={modeJeu === "paris"}
                onClick={() => void faire(async () => {
                  setModeJeu("paris");
                  await rpc.choisirModeJeu("paris");
                })}
                titre="Tous contre le binôme"
                dit="À chaque question, le reste de la salle parie sur la concordance avant la révélation. 5 points par pari juste. Le public a quelque chose à faire à chaque tour."
              />
            </div>
          )}
          <div style={{ marginBottom: "var(--e-3)", display: sujet ? "none" : "block" }}>
            <Bascule
              active={citez3}
              onChange={setCitez3}
              titre="Manche « cite 3 »"
              dit="Chacun cite trois choses sur l'autre en prépa, le partenaire doit les retrouver. 5 points par réponse commune. Allonge la partie d'un quart d'heure."
            />
          </div>
          <BoutonTampon
            disabled={occupe}
            onClick={() =>
              void faire(() => (sujet ? rpc.lancerSujet(format) : rpc.lancer(format, citez3)))
            }
          >
            Lancer la partie
          </BoutonTampon>
          <button
            type="button"
            disabled={occupe}
            onClick={() =>
              void faire(async () => {
                await rpc.reclamerPlateau(e.partie!.code);
                aller(`/tv/${e.partie!.code}`);
              })
            }
            style={{
              marginTop: "var(--e-3)",
              width: "100%",
              border: "var(--filet) solid var(--bord)",
              background: "var(--papier-2)",
              color: "var(--texte)",
              padding: "var(--e-2)",
              fontSize: "var(--t-s)",
              cursor: "pointer",
            }}
          >
            La télé s'est éteinte — afficher le plateau ici
          </button>
        </Panneau>
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

function Bascule({ active, onChange, titre, dit }: {
  active: boolean;
  onChange: (v: boolean) => void;
  titre: string;
  dit: string;
}) {
  return (
    <label style={{ display: "flex", gap: "var(--e-3)", alignItems: "flex-start", cursor: "pointer" }}>
      <input
        type="checkbox"
        checked={active}
        onChange={(ev) => onChange(ev.target.checked)}
        style={{ width: 24, height: 24, flex: "none", accentColor: "var(--rouge)" }}
      />
      <span>
        <span
          style={{
            display: "block",
            fontFamily: "var(--display)",
            textTransform: "uppercase",
            fontSize: "var(--t-m)",
          }}
        >
          {titre}
        </span>
        <span style={{ fontSize: "var(--t-xs)", color: "var(--texte-2)" }}>{dit}</span>
      </span>
    </label>
  );
}

function ChoixFormat({ actif, onClick, titre, dit }: {
  actif: boolean;
  onClick: () => void;
  titre: string;
  dit: string;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      style={{
        textAlign: "left",
        border: `${actif ? "var(--filet-fort)" : "var(--filet)"} solid var(--bord)`,
        background: actif ? "var(--jaune)" : "var(--papier)",
        color: actif ? "#15101b" : "var(--texte)",
        padding: "var(--e-2) var(--e-3)",
        cursor: "pointer",
      }}
    >
      <span
        style={{
          display: "block",
          fontFamily: "var(--display)",
          textTransform: "uppercase",
          fontSize: "var(--t-m)",
        }}
      >
        {titre}
      </span>
      <span style={{ fontSize: "var(--t-xs)", opacity: 0.8 }}>{dit}</span>
    </button>
  );
}
