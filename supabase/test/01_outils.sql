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

-- Le harnais tourne APRÈS les migrations, dont 0009_droits.sql qui
-- referme toutes les fonctions non-rpc_ — y compris `devenir`, créée
-- par le shim. On la rouvre ici : c'est l'outillage de test, jamais
-- déployé en production (0009 reste la source de vérité là-bas).
grant execute on function devenir(uuid) to anon, authenticated;
