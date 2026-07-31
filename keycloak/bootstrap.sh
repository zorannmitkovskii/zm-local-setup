#!/usr/bin/env bash
# ============================================================================
# zm-local-setup — Keycloak bootstrap (one-shot)
#
# Waits for Keycloak to answer, then ensures a confidential admin client
# exists in the `master` realm with:
#   * a known secret (so services can authenticate without a human),
#   * service accounts enabled (client-credentials grant),
#   * the master `admin` realm role (full admin over every realm).
#
# zm-iam-service uses this client (KEYCLOAK_ADMIN_CLIENT_ID / _SECRET) to
# reach the Keycloak Admin API. Idempotent: safe to re-run.
# ============================================================================
set -euo pipefail

KCADM=/opt/keycloak/bin/kcadm.sh
SERVER="${KC_SERVER:-http://keycloak:8080}"
ADMIN_USER="${KC_ADMIN:-admin}"
ADMIN_PASS="${KC_ADMIN_PASSWORD:-admin}"
CLIENT_ID="${ADMIN_CLIENT_ID:-zm-admin-cli}"
CLIENT_SECRET="${ADMIN_CLIENT_SECRET:-zm-admin-secret}"

echo "[bootstrap] Waiting for Keycloak at ${SERVER} ..."
until "${KCADM}" config credentials \
      --server "${SERVER}" --realm master \
      --user "${ADMIN_USER}" --password "${ADMIN_PASS}" >/dev/null 2>&1; do
  echo "[bootstrap]   ...not ready yet, retrying in 3s"
  sleep 3
done
echo "[bootstrap] Keycloak is up."

echo "[bootstrap] Ensuring admin client '${CLIENT_ID}' in master realm ..."
EXISTING_ID="$("${KCADM}" get clients -r master -q clientId="${CLIENT_ID}" \
                --fields id --format csv 2>/dev/null | tr -d '"' | head -n1 || true)"

if [ -z "${EXISTING_ID}" ]; then
  echo "[bootstrap]   creating client '${CLIENT_ID}'"
  "${KCADM}" create clients -r master \
    -s clientId="${CLIENT_ID}" \
    -s enabled=true \
    -s publicClient=false \
    -s serviceAccountsEnabled=true \
    -s standardFlowEnabled=false \
    -s directAccessGrantsEnabled=false \
    -s secret="${CLIENT_SECRET}"
  EXISTING_ID="$("${KCADM}" get clients -r master -q clientId="${CLIENT_ID}" \
                  --fields id --format csv | tr -d '"' | head -n1)"
else
  echo "[bootstrap]   client already exists (id=${EXISTING_ID}), refreshing secret"
fi

# Keep the secret in sync with what the services expect.
"${KCADM}" update "clients/${EXISTING_ID}" -r master -s secret="${CLIENT_SECRET}"

# Grant the service account full admin over the Keycloak instance.
echo "[bootstrap] Granting master 'admin' role to service-account-${CLIENT_ID} ..."
"${KCADM}" add-roles -r master \
  --uusername "service-account-${CLIENT_ID}" \
  --rolename admin || echo "[bootstrap]   (role already assigned)"

echo "[bootstrap] Done. zm-iam-service can now authenticate as '${CLIENT_ID}'."
