-- Outils de test : assertions lisibles dans la sortie psql.
create or replace function assert_vrai(cond boolean, libelle text) returns void
language plpgsql as $$
begin
  if cond is not true then raise exception 'ECHEC -- %', libelle; end if;
  raise notice '  ok   %', libelle;
end $$;

create or replace function assert_erreur(sql_text text, libelle text) returns void
language plpgsql as $$
begin
  begin
    execute sql_text;
  exception when others then
    raise notice '  ok   % (refuse : %)', libelle, left(sqlerrm, 55);
    return;
  end;
  raise exception 'ECHEC -- % : aucune erreur levee', libelle;
end $$;

create or replace function remise_a_zero() returns void language sql as $$
  truncate parties cascade;
$$;
