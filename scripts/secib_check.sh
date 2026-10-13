#!/usr/bin/env bash
# Test de connexion SECIB en lecture seule : obtention du token puis GET Cabinet/GetInfoCabinet.
# Variables :
#   SECIB_CABINET_ID     (obligatoire) GUID du cabinet, sans accolades
#   SECIB_CLIENT_ID      } identifiants OAuth2 client_credentials,
#   SECIB_CLIENT_SECRET  } utilisés si SECIB_API_TOKEN est absent
#   SECIB_API_TOKEN      (optionnel) access token déjà obtenu
#   SECIB_TOKEN_URL      (défaut : https://api.secib.fr/forward/$SECIB_CABINET_ID/ApiToken)
#   SECIB_BASE_URL       (défaut : https://secibneo.secib.fr/8.6.0)
# Le token n'est jamais affiché. Un appel de token + un appel GET, pas de boucle.
set -euo pipefail

: "${SECIB_CABINET_ID:?SECIB_CABINET_ID absent}"
BASE="${SECIB_BASE_URL:-https://secibneo.secib.fr/8.6.0}"
TOKEN_URL="${SECIB_TOKEN_URL:-https://api.secib.fr/forward/$SECIB_CABINET_ID/ApiToken}"

body="$(mktemp)"; trap 'rm -f "$body"' EXIT

if [ -z "${SECIB_API_TOKEN:-}" ]; then
  : "${SECIB_CLIENT_ID:?SECIB_CLIENT_ID absent}"
  : "${SECIB_CLIENT_SECRET:?SECIB_CLIENT_SECRET absent}"
  meta="$(curl -sS --max-time 30 -o "$body" -w '%{http_code} %{time_total}' -X POST \
    --data-urlencode "client_id=$SECIB_CLIENT_ID" \
    --data-urlencode "client_secret=$SECIB_CLIENT_SECRET" \
    --data-urlencode "grant_type=client_credentials" "$TOKEN_URL")"
  echo "Token  : $TOKEN_URL -> HTTP ${meta% *} (${meta#* }s)"
  SECIB_API_TOKEN="$(python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
print(d.get("access_token",""))
if "access_token" not in d: sys.stderr.write("Erreur : %s\n" % d)' "$body")"
  [ -n "$SECIB_API_TOKEN" ] || exit 1
fi

URL="$BASE/$SECIB_CABINET_ID/api/v1/Cabinet/GetInfoCabinet"
meta="$(curl -sS --max-time 30 -o "$body" -w '%{http_code} %{time_total}' \
  -H "Authorization: Bearer $SECIB_API_TOKEN" -H 'Accept: application/json' "$URL")"

echo "URL    : $URL"
echo "HTTP   : ${meta% *}"
echo "Durée  : ${meta#* }s"
echo "Corps  : $(head -c 300 "$body")"
