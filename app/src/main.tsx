import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./styles/base.css";
import { useRoute } from "./routeur";
import Accueil from "./routes/Accueil";
import Plateau from "./routes/Plateau";
import Joueur from "./routes/Joueur";
import { Erreur } from "./ui";

function App() {
  const route = useRoute();
  switch (route.nom) {
    case "plateau":
      return <Plateau code={route.code} />;
    case "joueur":
      return <Joueur code={route.code} />;
    case "accueil":
      return <Accueil />;
    default:
      return (
        <div className="centre">
          <Erreur>
            Cette adresse ne mène nulle part. <a href="/">Revenir à l'accueil</a>
          </Erreur>
        </div>
      );
  }
}

createRoot(document.getElementById("racine")!).render(
  <StrictMode>
    <App />
  </StrictMode>
);
