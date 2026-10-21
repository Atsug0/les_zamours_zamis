-- =============================================================
-- 0007 — Diffusion temps réel
--
-- Sans publication, aucun changement n'est poussé aux clients et
-- chaque écran reste figé. Les tables SECRÈTES (reponses_prepa,
-- votes) sont volontairement absentes : rien à diffuser, c'est le
-- sens même du jeu.
--
-- replica identity full est nécessaire pour que Realtime puisse
-- appliquer les RLS aux UPDATE (il a besoin de l'ancienne ligne).
-- =============================================================

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;

do $$
declare t text;
begin
  foreach t in array array['parties','binomes','joueurs','tours','passages_finale'] loop
    execute format('alter table %I replica identity full', t);
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime'
                     and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table %I', t);
    end if;
  end loop;
end $$;
