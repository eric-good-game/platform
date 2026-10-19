#!/usr/bin/env bash
# Crea una base de datos y un usuario por servicio y retira el acceso público.
# Se ejecuta una sola vez, en el primer arranque de PostgreSQL
# (documento 7, sección 4). Un servicio nuevo añade aquí su entrada.
set -euo pipefail

: "${POSTGRES_USER:?falta POSTGRES_USER}"

run_psql() {
  local db="$1"
  shift
  psql --username "$POSTGRES_USER" --dbname "$db" --no-psqlrc --set ON_ERROR_STOP=1 "$@"
}

# $1 = rol/usuario, $2 = base de datos, $3 = variable con su contraseña.
create_role_and_database() {
  local role="$1" db="$2" password_var="$3"
  local password="${!password_var:?falta la variable $password_var}"

  run_psql postgres --set role="$role" --set pass="$password" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'role', :'pass')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'role') \gexec
SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'role', :'pass') \gexec
SQL

  run_psql postgres --set db="$db" --set role="$role" <<'SQL'
SELECT format('CREATE DATABASE %I OWNER %I', :'db', :'role')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db') \gexec
SQL

  # Solo el dueño se conecta a la base; PUBLIC pierde el acceso.
  run_psql "$db" --set db="$db" --set role="$role" <<'SQL'
REVOKE ALL ON DATABASE :"db" FROM PUBLIC;
ALTER DATABASE :"db" OWNER TO :"role";
GRANT CONNECT ON DATABASE :"db" TO :"role";
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO :"role";
SQL
}

create_role_and_database identity identity DB_IDENTITY_PASSWORD
create_role_and_database inventory inventory DB_INVENTORY_PASSWORD
create_role_and_database store store DB_STORE_PASSWORD
create_role_and_database reports reports DB_REPORTS_PASSWORD
create_role_and_database tickets tickets DB_TICKETS_PASSWORD

# La base de mantenimiento tampoco se deja abierta a PUBLIC.
run_psql postgres <<'SQL'
REVOKE ALL ON DATABASE postgres FROM PUBLIC;
SQL
