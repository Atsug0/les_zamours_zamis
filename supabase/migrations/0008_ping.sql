-- =============================================================
-- 0008 — Signe de vie
--
-- Un projet Supabase gratuit est mis en pause après 7 jours sans
-- activité, et un jeu de soirée ne tourne pas toutes les semaines
-- (ARCHITECTURE.md §8, piège n°1). Cette fonction existe pour qu'un
-- cron gratuit puisse réveiller le projet sans authentification.
--
-- Nommée SANS le préfixe rpc_ volontairement : les migrations
-- révoquent les droits d'anon sur toutes les fonctions rpc_%, et
-- celle-ci doit justement rester accessible à anon.
-- =============================================================

create or replace function ping()
returns jsonb language sql stable
set search_path = public, pg_temp as $$
  select jsonb_build_object('vivant', true, 'at', now());
$$;

-- La seule fonction ouverte à anon. Elle ne lit aucune donnée.
grant execute on function ping() to anon, authenticated;
