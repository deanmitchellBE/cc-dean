#!/usr/bin/env bash
# Test de connexion SECIB en lecture seule (GET Cabinet/GetInfoCabinet).
# Variables : SECIB_API_TOKEN (obligatoire), SECIB_CABINET_ID (obligatoire),
#             SECIB_BASE_URL (défaut : https://secibneo.secib.fr/8.6.0).
# Le token n'est jamais affiché. Un seul appel, pas de boucle.
set -euo pipefail

: "${SECIB_API_TOKEN:?SECIB_API_TOKEN absent}"
: "${SECIB_CABINET_ID:?SECIB_CABINET_ID absent}"
BASE="${SECIB_BASE_URL:-https://secibneo.secib.fr/8.6.0}"
URL="$BASE/$SECIB_CABINET_ID/api/v1/Cabinet/GetInfoCabinet"

body="$(mktemp)"; trap 'rm -f "$body"' EXIT
meta="$(curl -sS --max-time 30 -o "$body" -w '%{http_code} %{time_total}' \
  -H "Authorization: Bearer $SECIB_API_TOKEN" -H 'Accept: application/json' "$URL")"

echo "URL    : $URL"
echo "HTTP   : ${meta% *}"
echo "Durée  : ${meta#* }s"
echo "Corps  : $(head -c 300 "$body")"
