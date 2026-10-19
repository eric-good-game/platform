#!/usr/bin/env bash
# Comprueba que la plataforma base está sana y cumple las invariantes del hito 1
# (documento 7: invariantes 6 y 11). Uso: make check
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

COMPOSE=(docker compose --env-file envs/base.env --env-file secrets/compose.env)

fail() { echo "FALLO: $*" >&2; exit 1; }
ok() { echo "OK: $*"; }

# 1. Los servicios están sanos.
for service in postgres rabbitmq; do
  container="$("${COMPOSE[@]}" ps -q "$service")"
  [ -n "$container" ] || fail "el servicio $service no está levantado"
  health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}sin healthcheck{{end}}' "$container")"
  [ "$health" = "healthy" ] || fail "$service no está sano (estado: $health)"
  ok "$service sano"
done

# 2. Los exchanges de la plataforma existen (invariante 11).
exchanges="$("${COMPOSE[@]}" exec -T rabbitmq rabbitmqctl -q list_exchanges name)"
echo "$exchanges" | grep -qx "events" || fail "no existe el exchange events"
echo "$exchanges" | grep -qx "events.dlx" || fail "no existe el exchange events.dlx"
ok "exchanges events y events.dlx declarados"

# 3. Cada base de servicio existe.
for db in identity inventory store reports tickets; do
  "${COMPOSE[@]}" exec -T postgres psql -U postgres -d postgres -tAc \
    "SELECT 1 FROM pg_database WHERE datname = '$db'" | grep -qx 1 \
    || fail "no existe la base $db"
done
ok "bases identity, inventory, store, reports y tickets creadas"

# 4. Aislamiento: cada usuario entra en su base y no en la de otro (invariante 6).
container="$("${COMPOSE[@]}" ps -q postgres)"

psql_as() {
  local user="$1" password="$2" db="$3" query="$4"
  docker exec -e PGPASSWORD="$password" -e PGCONNECT_TIMEOUT=5 "$container" \
    psql -h 127.0.0.1 --username "$user" --dbname "$db" -tAc "$query"
}

if ! psql_as inventory "$(cat secrets/db_inventory_password)" inventory "SELECT 1" | grep -qx 1; then
  fail "el usuario inventory no puede conectarse a la base inventory"
fi
ok "el usuario inventory entra en su base"

if psql_as inventory "$(cat secrets/db_inventory_password)" identity "SELECT 1" >/dev/null 2>&1; then
  fail "el usuario inventory pudo conectarse a la base identity"
fi
ok "el usuario inventory no puede conectarse a la base identity"

echo "Plataforma correcta."
