#!/usr/bin/env bash
set -Eeuo pipefail

required=(
  PRIVIDIUM_DB_NAME PRIVIDIUM_DB_USER PRIVIDIUM_DB_PASSWORD
  EXPLORER_DB_NAME EXPLORER_DB_USER EXPLORER_DB_PASSWORD
  KEYCLOAK_DB_NAME KEYCLOAK_DB_USER KEYCLOAK_DB_PASSWORD
  WEBHOOK_DB_NAME WEBHOOK_DB_USER WEBHOOK_DB_PASSWORD
)

for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required database setting: ${name}" >&2
    exit 1
  fi
done

create_role_and_database() {
  local database_name="$1"
  local role_name="$2"
  local role_password="$3"

  psql --set=ON_ERROR_STOP=1 \
    --username "$POSTGRES_USER" \
    --dbname postgres \
    --set=db_name="$database_name" \
    --set=role_name="$role_name" \
    --set=role_password="$role_password" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'role_name', :'role_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'role_name')
\gexec

SELECT format('CREATE DATABASE %I OWNER %I', :'db_name', :'role_name')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db_name')
\gexec
SQL
}

create_role_and_database "$PRIVIDIUM_DB_NAME" "$PRIVIDIUM_DB_USER" "$PRIVIDIUM_DB_PASSWORD"
create_role_and_database "$EXPLORER_DB_NAME" "$EXPLORER_DB_USER" "$EXPLORER_DB_PASSWORD"
create_role_and_database "$KEYCLOAK_DB_NAME" "$KEYCLOAK_DB_USER" "$KEYCLOAK_DB_PASSWORD"
create_role_and_database "$WEBHOOK_DB_NAME" "$WEBHOOK_DB_USER" "$WEBHOOK_DB_PASSWORD"
