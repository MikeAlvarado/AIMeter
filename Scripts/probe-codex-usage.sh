#!/usr/bin/env bash
#
# Prints what Codex's usage endpoint returns for your own login, the one
# the Codex CLI's `/status` and ChatGPT's usage page read:
# GET https://chatgpt.com/backend-api/wham/usage with the CLI's OAuth
# access token and its `ChatGPT-Account-Id` header (the request the CLI
# itself sends, codex-rs/backend-client/src/client/rate_limit_resets.rs).
# Undocumented; a server change must only touch Providers/Codex/.
#
# Token source: $CODEX_HOME/auth.json, else ~/.codex/auth.json (the file
# `codex login` writes; a keyring-stored login is not read). The token is
# never printed and nothing is written unless -o is given. Identifiers in
# the response (account ids, emails, anything *_id) are redacted before
# printing or saving, so the output can become a test fixture.
#
# Usage:
#   Scripts/probe-codex-usage.sh            # pretty-print (redacted)
#   Scripts/probe-codex-usage.sh -o FILE    # also save the redacted JSON

set -euo pipefail

OUT_FILE=""
while getopts "o:" opt; do
  case "$opt" in
    o) OUT_FILE="$OPTARG" ;;
    *) echo "usage: $0 [-o output.json]" >&2; exit 2 ;;
  esac
done

err() { echo "error: $*" >&2; exit 1; }
command -v jq >/dev/null || err "jq is required (brew install jq)"

AUTH_FILE="${CODEX_HOME:-$HOME/.codex}/auth.json"
[[ -f "$AUTH_FILE" ]] || err "no $AUTH_FILE. Is Codex installed and logged in (codex login)?"

ACCESS_TOKEN="$(jq -r '.tokens.access_token // empty' "$AUTH_FILE")"
ACCOUNT_ID="$(jq -r '.tokens.account_id // empty' "$AUTH_FILE")"
LAST_REFRESH="$(jq -r '.last_refresh // "unknown"' "$AUTH_FILE")"
[[ -n "$ACCESS_TOKEN" ]] || err "auth.json holds no access token (an API-key login, or logged out)"

# The access token is a JWT: read only its expiry and plan claim, never
# the rest (it carries the email).
PAYLOAD="$(cut -d. -f2 <<<"$ACCESS_TOKEN" | tr '_-' '/+' | awk '{ l=length($0)%4; if (l==2) print $0"=="; else if (l==3) print $0"="; else print $0 }' | base64 -d 2>/dev/null || true)"
EXP="$(jq -r '.exp // 0' <<<"$PAYLOAD" 2>/dev/null || echo 0)"
PLAN="$(jq -r '."https://api.openai.com/auth".chatgpt_plan_type // "unknown"' <<<"$PAYLOAD" 2>/dev/null || echo unknown)"
unset PAYLOAD

echo "plan (token claim): $PLAN"
echo "last refresh:       $LAST_REFRESH"
if (( EXP > 0 )); then
  echo "token valid:        until $(date -r "$EXP" '+%Y-%m-%d %H:%M:%S')"
  (( EXP > $(date +%s) )) || echo "warning: the access token has expired; run any 'codex' command to refresh it, then retry." >&2
fi
echo

HTTP_RESPONSE="$(curl -sS -w '\n%{http_code}' \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "ChatGPT-Account-Id: $ACCOUNT_ID" \
  -H "Accept: application/json" \
  -H "User-Agent: AIMeter-probe" \
  "https://chatgpt.com/backend-api/wham/usage")"
unset ACCESS_TOKEN

HTTP_CODE="$(tail -n1 <<<"$HTTP_RESPONSE")"
BODY="$(sed '$d' <<<"$HTTP_RESPONSE")"
echo "HTTP $HTTP_CODE"
echo

if [[ "$HTTP_CODE" != "200" ]]; then
  echo "$BODY" | jq . 2>/dev/null || echo "$BODY" | head -c 600
  exit 1
fi

# Redact identifiers wherever they sit: any key ending in "id" or "_id",
# and emails. Figures and dates stay, they are what the fixture is for.
REDACTED="$(jq '
  walk(if type == "object" then with_entries(
    if (.key | test("(^|_)id$|email|user_name|name$"; "i")) and (.value | type) == "string"
    then .value = "<redacted>" else . end) else . end)
' <<<"$BODY")"

echo "$REDACTED"
if [[ -n "$OUT_FILE" ]]; then
  echo "$REDACTED" > "$OUT_FILE"
  echo
  echo "redacted response saved to: $OUT_FILE"
fi
