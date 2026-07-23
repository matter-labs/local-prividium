#!/usr/bin/env bash
set -Eeuo pipefail

required=(
  KEYCLOAK_URL
  KEYCLOAK_BOOTSTRAP_ADMIN_USERNAME
  KEYCLOAK_BOOTSTRAP_ADMIN_PASSWORD
  SANDBOX_DOMAIN
  DEMO_USER_1_EMAIL
  DEMO_USER_1_PASSWORD
  DEMO_USER_2_EMAIL
  DEMO_USER_2_PASSWORD
)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required demo identity setting: ${name}" >&2
    exit 1
  fi
done

kcadm=/opt/keycloak/bin/kcadm.sh
"$kcadm" config credentials \
  --server "$KEYCLOAK_URL" \
  --realm master \
  --user "$KEYCLOAK_BOOTSTRAP_ADMIN_USERNAME" \
  --password "$KEYCLOAK_BOOTSTRAP_ADMIN_PASSWORD"

if "$kcadm" get realms/acme >/dev/null 2>&1; then
  "$kcadm" update realms/acme \
    -s enabled=true \
    -s sslRequired=external \
    -s registrationAllowed=false \
    -s loginWithEmailAllowed=true \
    -s resetPasswordAllowed=true \
    -s bruteForceProtected=true
else
  "$kcadm" create realms \
    -s id=acme \
    -s realm=acme \
    -s enabled=true \
    -s sslRequired=external \
    -s registrationAllowed=false \
    -s loginWithEmailAllowed=true \
    -s resetPasswordAllowed=true \
    -s bruteForceProtected=true
fi

if ! "$kcadm" get roles/user -r acme >/dev/null 2>&1; then
  "$kcadm" create roles -r acme -s name=user -s description="Institutional demo user"
fi

client_uuid=$(
  "$kcadm" get clients -r acme -q clientId=acme-client --fields id --format csv --noquotes |
    tail -n 1
)
redirects="[\"https://app.${SANDBOX_DOMAIN}/*\",\"https://admin.${SANDBOX_DOMAIN}/*\",\"https://demo.${SANDBOX_DOMAIN}/*\"]"
origins="[\"https://app.${SANDBOX_DOMAIN}\",\"https://admin.${SANDBOX_DOMAIN}\",\"https://demo.${SANDBOX_DOMAIN}\"]"

if [[ -z "$client_uuid" ]]; then
  "$kcadm" create clients -r acme \
    -s clientId=acme-client \
    -s name="Institutional Sandbox Demo" \
    -s enabled=true \
    -s publicClient=true \
    -s standardFlowEnabled=true \
    -s directAccessGrantsEnabled=false \
    -s 'attributes."pkce.code.challenge.method"=S256' \
    -s "redirectUris=${redirects}" \
    -s "webOrigins=${origins}"
else
  "$kcadm" update "clients/${client_uuid}" -r acme \
    -s enabled=true \
    -s publicClient=true \
    -s standardFlowEnabled=true \
    -s directAccessGrantsEnabled=false \
    -s "redirectUris=${redirects}" \
    -s "webOrigins=${origins}"
fi

upsert_user() {
  local user_id="$1"
  local email="$2"
  local password="$3"
  local existing_id
  existing_id=$(
    "$kcadm" get users -r acme -q "username=${email}" --fields id --format csv --noquotes |
      tail -n 1
  )

  if [[ -z "$existing_id" ]]; then
    "$kcadm" create users -r acme \
      -s "id=${user_id}" \
      -s "username=${email}" \
      -s "email=${email}" \
      -s enabled=true \
      -s emailVerified=true
  else
    user_id="$existing_id"
    "$kcadm" update "users/${user_id}" -r acme \
      -s "email=${email}" \
      -s enabled=true \
      -s emailVerified=true
  fi

  "$kcadm" set-password -r acme --userid "$user_id" --new-password "$password" --temporary=false
  "$kcadm" add-roles -r acme --uid "$user_id" --rolename user
}

upsert_user "10000000-0000-0000-0000-000000000001" "$DEMO_USER_1_EMAIL" "$DEMO_USER_1_PASSWORD"
upsert_user "10000000-0000-0000-0000-000000000002" "$DEMO_USER_2_EMAIL" "$DEMO_USER_2_PASSWORD"

echo "Institutional demo realm and two SOPS-managed users are ready."
