#!/usr/bin/env bash
# Applique un fichier SQL ou une requête à la base de PRODUCTION.
#
#   ./tools/db_prod.sh supabase/migrations/0021_xxx.sql
#   ./tools/db_prod.sh -c 'select count(*) from questions_index'
#   ./tools/db_prod.sh --migrations        applique toutes les migrations
#   ./tools/db_prod.sh --controle          rejoue les contrôles de sécurité
#
# Les identifiants viennent de .env.local, à la racine, non versionné.
# Le mot de passe passe par PGPASSWORD : il ne transite donc jamais par
# la ligne de commande, et n'a pas besoin d'être encodé en URL.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f .env.local ]]; then
  echo "Il manque .env.local à la racine. Voir DEPLOIEMENT.md §2.1." >&2
  exit 1
fi
set -a; source .env.local; set +a
: "${SUPABASE_DB_HOST:?absent de .env.local}" "${SUPABASE_DB_PASSWORD:?absent de .env.local}"

export PGPASSWORD="$SUPABASE_DB_PASSWORD"
# </dev/null : sans -f ni -c, psql attend sur l'entrée standard et le
# script reste bloqué indéfiniment. Une erreur d'usage ne doit pas pendre.
prod() { psql -h "$SUPABASE_DB_HOST" -p 5432 -U postgres -d postgres -v ON_ERROR_STOP=1 "$@" </dev/null; }

echo "→ $SUPABASE_DB_HOST (PRODUCTION)"

case "${1:-}" in
  --migrations)
    for f in supabase/migrations/*.sql; do
      if prod -q -f "$f" >/dev/null; then echo "  appliqué  $(basename "$f")"
      else echo "  ÉCHEC     $(basename "$f")"; exit 1; fi
    done
    prod -q -f supabase/seed_questions_index.sql
    echo "  chargé    $(prod -At -c 'select count(*) from questions_index') questions"
    ;;
  --controle)
    echo "  écrivable depuis le navigateur (doit être vide) :"
    prod -At -c "select '    '||table_name||' '||privilege_type
                 from information_schema.role_table_grants
                 where grantee in ('anon','authenticated') and table_schema='public'
                   and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES')"
    echo "  fonctions non-rpc joignables (attendu : est_membre, ping) :"
    prod -At -c "select '    '||p.proname from pg_proc p
                 join pg_namespace n on n.oid=p.pronamespace
                 where n.nspname='public'
                   and not exists (select 1 from pg_depend d where d.objid=p.oid and d.deptype='e')
                   and p.proname not like 'rpc\_%'
                   and (has_function_privilege('anon',p.oid,'execute')
                     or has_function_privilege('authenticated',p.oid,'execute'))
                 order by 1"
    echo "  diffusé en temps réel :"
    prod -At -c "select '    '||tablename from pg_publication_tables
                 where pubname='supabase_realtime' order by 1"
    ;;
  "")
    echo "Rien à faire. Voir l'en-tête du script pour les usages." >&2
    exit 1
    ;;
  *)
    # Un nom de fichier doit passer par -f : psql ignore silencieusement
    # un argument positionnel, et la migration ne s'applique jamais.
    if [[ -f "$1" ]]; then
      prod -q -f "$1"
      echo "  appliqué  $(basename "$1")"
    else
      prod "$@"
    fi
    ;;
esac
