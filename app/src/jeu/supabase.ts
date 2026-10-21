import { createClient } from "@supabase/supabase-js";

const url = import.meta.env.VITE_SUPABASE_URL;
const cle = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!url || !cle) {
  throw new Error(
    "VITE_SUPABASE_URL et VITE_SUPABASE_ANON_KEY manquent. Copie .env.example en .env.local."
  );
}

export const supabase = createClient(url, cle, {
  auth: {
    // La session anonyme survit à la fermeture de l'onglet : c'est elle
    // qui rend un joueur à sa place après un rechargement (§10.a).
    persistSession: true,
    autoRefreshToken: true,
    storageKey: "zamours.session",
  },
  realtime: { params: { eventsPerSecond: 5 } },
});

/** Ouvre une session anonyme si besoin. Aucun compte, aucun e-mail. */
export async function session(): Promise<string> {
  const { data } = await supabase.auth.getSession();
  if (data.session) return data.session.user.id;
  const { data: anon, error } = await supabase.auth.signInAnonymously();
  if (error) throw error;
  if (!anon.session) throw new Error("session anonyme refusée");
  return anon.session.user.id;
}

/** Mémoire locale de la dernière partie : rouvrir le site y renvoie. */
export const memoire = {
  lire(): { code: string; role: "plateau" | "joueur" } | null {
    try {
      const brut = localStorage.getItem("zamours.derniere");
      return brut ? JSON.parse(brut) : null;
    } catch {
      return null;
    }
  },
  ecrire(code: string, role: "plateau" | "joueur") {
    localStorage.setItem("zamours.derniere", JSON.stringify({ code, role }));
  },
  oublier() {
    localStorage.removeItem("zamours.derniere");
  },
};
