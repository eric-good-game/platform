#!/usr/bin/env bash
# Genera los secretos locales de la plataforma. Es idempotente: solo crea lo que falta.
# Uso: make setup   (o ENV_FILE=envs/full.env bash scripts/setup.sh)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_DIR="${SECRETS_DIR:-$ROOT_DIR/secrets}"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/envs/base.env}"

command -v openssl >/dev/null 2>&1 || {
  echo "Falta openssl: es necesario para generar las contraseñas y el par de claves." >&2
  exit 1
}

umask 077
mkdir -p "$SECRETS_DIR"

new_secret() {
  openssl rand -hex 24
}

# Crea el archivo con un secreto aleatorio si no existe o está vacío.
ensure_secret_file() {
  local path="$1"
  if [ ! -s "$path" ]; then
    new_secret > "$path"
    echo "Generado: ${path#"$ROOT_DIR"/}"
  fi
}

# --- Contraseñas de bases de datos y del broker ------------------------------

ensure_secret_file "$SECRETS_DIR/postgres_superuser_password"
for service in identity inventory store reports tickets; do
  ensure_secret_file "$SECRETS_DIR/db_${service}_password"
done
ensure_secret_file "$SECRETS_DIR/rabbitmq_password"

# --- Par de claves de firma de Identity (RS256) ------------------------------

if [ ! -s "$SECRETS_DIR/jwt-private.pem" ]; then
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
    -out "$SECRETS_DIR/jwt-private.pem" 2>/dev/null
  chmod 600 "$SECRETS_DIR/jwt-private.pem"
  echo "Generado: secrets/jwt-private.pem"
fi

if [ ! -s "$SECRETS_DIR/jwt-public.pem" ]; then
  openssl rsa -in "$SECRETS_DIR/jwt-private.pem" -pubout \
    -out "$SECRETS_DIR/jwt-public.pem" 2>/dev/null
  echo "Generado: secrets/jwt-public.pem"
fi

if [ ! -s "$SECRETS_DIR/jwt-kid" ]; then
  printf 'identity-%s\n' "$(openssl rand -hex 6)" > "$SECRETS_DIR/jwt-kid"
  echo "Generado: secrets/jwt-kid"
fi

# --- Contraseña del primer admin (solo sin datos de demostración) ------------

seed_demo_data="true"
if [ -f "$ENV_FILE" ]; then
  seed_demo_data="$(sed -n 's/^SEED_DEMO_DATA=//p' "$ENV_FILE" | tail -1)"
  seed_demo_data="${seed_demo_data:-true}"
fi

if [ "$seed_demo_data" != "true" ] && [ ! -s "$SECRETS_DIR/initial_admin_password" ]; then
  new_secret > "$SECRETS_DIR/initial_admin_password"
  echo
  echo "No hay datos de demostración: contraseña del primer admin (se muestra una sola vez)."
  echo "  $(cat "$SECRETS_DIR/initial_admin_password")"
  echo
fi

# --- Archivo derivado para docker compose ------------------------------------

# La fuente de verdad son los archivos individuales de secrets/. Este archivo
# solo reúne las variables que docker-compose.yml necesita sustituir.
compose_env="$SECRETS_DIR/compose.env"
{
  echo "# Generado por scripts/setup.sh a partir de los archivos de secrets/."
  echo "# No lo edites a mano: se regenera en cada 'make setup'."
  echo "POSTGRES_SUPERUSER_PASSWORD=$(cat "$SECRETS_DIR/postgres_superuser_password")"
  echo "DB_IDENTITY_PASSWORD=$(cat "$SECRETS_DIR/db_identity_password")"
  echo "DB_INVENTORY_PASSWORD=$(cat "$SECRETS_DIR/db_inventory_password")"
  echo "DB_STORE_PASSWORD=$(cat "$SECRETS_DIR/db_store_password")"
  echo "DB_REPORTS_PASSWORD=$(cat "$SECRETS_DIR/db_reports_password")"
  echo "DB_TICKETS_PASSWORD=$(cat "$SECRETS_DIR/db_tickets_password")"
  echo "RABBITMQ_PASSWORD=$(cat "$SECRETS_DIR/rabbitmq_password")"
  echo "JWT_KID=$(cat "$SECRETS_DIR/jwt-kid")"
  if [ -s "$SECRETS_DIR/initial_admin_password" ]; then
    echo "INITIAL_ADMIN_PASSWORD=$(cat "$SECRETS_DIR/initial_admin_password")"
  fi
} > "$compose_env"
chmod 600 "$compose_env"

# --- Definiciones de RabbitMQ con el usuario y la contraseña -----------------

# La plantilla versionada (broker/definitions.template.json) no lleva secretos:
# aquí se sustituye el marcador por la contraseña generada. RabbitMQ carga este
# archivo al arrancar y crea el usuario y los exchanges (documento 7, sección 5).
rabbitmq_password="$(cat "$SECRETS_DIR/rabbitmq_password")"
sed "s|__RABBITMQ_PASSWORD__|${rabbitmq_password}|" \
  "$ROOT_DIR/broker/definitions.template.json" > "$SECRETS_DIR/rabbitmq-definitions.json"
chmod 600 "$SECRETS_DIR/rabbitmq-definitions.json"

echo "Secretos listos en secrets/."
