#!/usr/bin/env bash
# Monte un Postgres jetable, applique le schéma, les RLS, les RPC,
# l'index des questions, puis joue la suite de tests.
#
#   ./tools/db_local.sh          applique tout et teste
#   ./tools/db_local.sh --reset  détruit et recrée le conteneur d'abord
#
# Rien de tout ça ne touche à Supabase : c'est un bac à sable local.
set -euo pipefail
cd "$(dirname "$0")/.."

PORT=54399
CONTENEUR=zz-pg
export PGPASSWORD=zz
psql_() { psql -h 127.0.0.1 -p $PORT -U postgres -d zz -v ON_ERROR_STOP=1 -q "$@"; }

if [[ "${1:-}" == "--reset" ]] || ! docker ps --filter "name=$CONTENEUR" --format '{{.Names}}' | grep -q .; then
  docker rm -f $CONTENEUR >/dev/null 2>&1 || true
  RECREE=1
  docker run -d --name $CONTENEUR -e POSTGRES_PASSWORD=zz -e POSTGRES_DB=zz \
    -p $PORT:5432 postgres:16-alpine >/dev/null
  printf 'postgres démarre'
  until psql_ -c 'select 1' >/dev/null 2>&1; do printf '.'; sleep 1; done
  echo ' prêt'
  psql_ -f supabase/test/00_shim.sql     # auth.uid(), rôles anon/authenticated
fi

# Toujours repartir d'un schéma vide : une migration n'est pas idempotente,
# et des erreurs de « already exists » masqueraient les vrais problèmes.
if [[ "${RECREE:-}" != "1" ]]; then
  psql_ -c 'drop schema public cascade; create schema public;' >/dev/null
  psql_ -f supabase/test/00_shim.sql
fi

for f in supabase/migrations/*.sql; do
  psql_ -f "$f" && echo "appliqué  $(basename "$f")"
done

python3 tools/seed_index.py >/dev/null
psql_ -f supabase/seed_questions_index.sql
echo "chargé    $(psql_ -At -c 'select count(*) from questions_index') questions dans l'index"

psql_ -f supabase/test/01_outils.sql
echo
# 00_shim et 01_outils sont des prérequis, pas des suites de tests
for t in supabase/test/[0-9][0-9]_*.sql; do
  case "$(basename "$t")" in 00_*|01_*) continue;; esac
  psql_ -f "$t" 2>&1 | grep -E 'ok |ECHEC|ERROR|===' | sed 's/^psql:[^ ]* //;s/NOTICE:  //'
done
