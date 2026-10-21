-- =============================================================
-- 0023 — Les bots sont toujours présents
--
-- rpc_verifier_presence lit la table `joueurs` et non la vue : elle
-- voyait donc les bots comme déconnectés — ils n'envoient aucun
-- pouls, par nature — et gelait la partie de démonstration au
-- premier tour. L'écran affichait « EN PAUSE » et plus rien ne
-- bougeait.
--
-- Vu sur une capture d'écran du plateau, pas par un test : un gel
-- est un état valide, aucune assertion ne s'en plaignait.
-- =============================================================

create or replace function rpc_verifier_presence()
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  p parties; v_partie uuid; v_absents text[]; v_seuil timestamptz;
begin
  select id into v_partie from parties where plateau_id = auth.uid();
  if v_partie is null then select partie_id into v_partie from joueurs where id = auth.uid(); end if;
  if not peut_orchestrer(v_partie) then raise exception 'non autorisé'; end if;
  select * into p from parties where id = v_partie;
  v_seuil := now() - interval '30 seconds';

  select array_agg(distinct j.prenom) into v_absents
  from joueurs j
  where j.partie_id = v_partie
    and not j.bot                      -- un bot ne se déconnecte jamais
    and j.vu_le < v_seuil and (
        j.id in (select unnest(array[t.repondant_id, t.questionneur_id])
                 from tours t where t.partie_id = v_partie
                   and t.statut in ('attente','consigne'))
     or j.id in (select unnest(array[f.joueur_id, f.questionneur_id])
                 from passages_finale f where f.partie_id = v_partie
                   and f.seuil_atteint is null and f.serie_id is not null));

  if v_absents is not null and not p.en_pause then
    perform rpc_geler('absence');
    return jsonb_build_object('en_pause', true, 'attend', to_jsonb(v_absents));
  elsif v_absents is null and p.en_pause and p.pause_motif = 'absence' then
    perform rpc_degeler();
    return jsonb_build_object('en_pause', false, 'reprise', true);
  end if;
  return jsonb_build_object('en_pause', p.en_pause,
                            'attend', coalesce(to_jsonb(v_absents), '[]'::jsonb));
end $$;

revoke all on function rpc_verifier_presence() from public, anon;
grant execute on function rpc_verifier_presence() to authenticated;
