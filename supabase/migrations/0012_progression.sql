-- =============================================================
-- 0012 — Faire remonter la progression de la préparation
--
-- `reponses_prepa` n'est pas diffusée en temps réel, et ce n'est pas
-- un oubli : c'est le secret du jeu. Mais le plateau doit afficher
-- « 5 joueurs sur 8 ont terminé », et sans diffusion il faudrait
-- interroger la base en boucle.
--
-- On publie donc un COMPTEUR sur `joueurs`, table déjà diffusée.
-- Un nombre ne révèle rien du contenu.
--
-- Effet de bord utile : v_progression n'a plus besoin d'appeler
-- nb_questions_prepa, qui sort donc de la liste blanche des
-- fonctions joignables (0009). Une porte de moins.
-- =============================================================

alter table joueurs add column prepa_faites int not null default 0;

update joueurs j set prepa_faites =
  (select count(*) from reponses_prepa r where r.joueur_id = j.id);

create or replace function rpc_repondre_prepa(p_question text, p_valeur text,
                                              p_passee boolean default false)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  j joueurs; p parties; attendues jsonb; faites int; total int;
begin
  select * into j from joueurs where id = auth.uid();
  if j.id is null then raise exception 'rejoins la partie d''abord'; end if;
  select * into p from parties where id = j.partie_id;
  if p.etat <> 'prep' then raise exception 'ce n''est plus la phase de préparation'; end if;

  attendues := (rpc_mes_questions())->'questions';
  if not (attendues ? p_question) then
    raise exception 'cette question n''est pas dans ton set';
  end if;
  if not coalesce(p_passee,false) and length(btrim(coalesce(p_valeur,''))) = 0 then
    raise exception 'réponse vide : utilise « passer »';
  end if;

  insert into reponses_prepa (joueur_id, question_id, valeur, passee)
  values (j.id, p_question, btrim(coalesce(p_valeur,'')), coalesce(p_passee,false))
  on conflict (joueur_id, question_id)
    do update set valeur = excluded.valeur, passee = excluded.passee, ecrit_le = now();

  select count(*) into faites from reponses_prepa where joueur_id = j.id;
  total := nb_questions_prepa(p.id);

  -- le compteur passe par joueurs, donc il est diffusé en temps réel
  update joueurs set prepa_faites = faites where id = j.id;

  return jsonb_build_object('faites', faites, 'total', total, 'termine', faites >= total);
end $$;

drop view if exists v_progression;
create view v_progression as
  select j.partie_id,
         count(*) filter (where j.prepa_faites >= att.total) as termines,
         count(*) as total,
         min(att.total) as questions_par_joueur
  from joueurs j
  join parties p on p.id = j.partie_id
  cross join lateral (
    select case p.format when 'court' then 2 else 3 end     -- ouvertes
         + case p.format when 'court' then 1 else 2 end     -- qcm
         + 1                                                -- bonus
         + (p.reglages->>'questionsFinale')::int as total   -- série de finale
  ) att
  where j.binome_id is not null and est_membre(j.partie_id)
  group by j.partie_id;

grant select on v_progression to anon, authenticated;

-- v_progression n'appelle plus de fonction : on referme celle-ci.
revoke all on function nb_questions_prepa(uuid) from public, anon, authenticated;

-- v_joueurs expose le compteur : le téléphone affiche sa propre
-- progression, et le plateau celle de la salle, sans aucun contenu.
drop view if exists v_joueurs;
create view v_joueurs as
  select j.id, j.partie_id, j.prenom, j.binome_id, j.role,
         j.vu_le,
         (j.vu_le > now() - interval '30 seconds') as present,
         (j.mode_choisi is not null)              as a_choisi_mode,
         j.prepa_faites
  from joueurs j
  where est_membre(j.partie_id);

grant select on v_joueurs to anon, authenticated;
