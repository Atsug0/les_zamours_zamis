-- Reproduit le strict nécessaire de l'environnement Supabase pour
-- pouvoir appliquer et tester les migrations sur un Postgres nu.
create schema if not exists auth;
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
end $$;
-- auth.uid() lit la session courante, exactement comme en prod via le JWT
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;
create or replace function devenir(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p::text, false);
$$;
grant usage on schema public to anon, authenticated;
grant usage on schema auth to anon, authenticated;
