#!/usr/bin/env bash
#
# Prints what GitHub Copilot's quota endpoint returns for your own account:
# GET https://api.github.com/copilot_internal/user, the undocumented
# request the Copilot editor plug-ins send (monthly premium requests,
# chat and completions: entitlement, remaining, the reset date).
#
# Token: GitHub's OAuth device flow with Copilot's own OAuth App id, the
# one VS Code's Copilot, the Copilot CLI and opencode sign in with (no
# public registration for third parties exists). The script prints a
# code and a URL; you open the URL, sign in to GitHub yourself and enter
# the code. The token lives in this shell only: never printed, never
# written. The quota response is printed with identifiers redacted, and
# -o saves that redacted JSON (what a test fixture is made of).
#
# The quota call is tried first with plain headers and, if GitHub refuses
# that, again with the editor headers the plug-ins send, so the output
# says which the app will need.
#
# Usage:
#   Scripts/probe-copilot-quota.sh            # pretty-print (redacted)
#   Scripts/probe-copilot-quota.sh -o FILE    # also save the redacted JSON

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

CLIENT_ID="Iv1.b507a08c87ecfe98"

# --- 1. Device flow ----------------------------------------------------------

START="$(curl -sS -X POST "https://github.com/login/device/code" \
  -H "Accept: application/json" \
  --data-urlencode "client_id=$CLIENT_ID" \
  --data-urlencode "scope=read:user")"
DEVICE_CODE="$(jq -r '.device_code // empty' <<<"$START")"
USER_CODE="$(jq -r '.user_code // empty' <<<"$START")"
VERIFY_URL="$(jq -r '.verification_uri // empty' <<<"$START")"
INTERVAL="$(jq -r '.interval // 5' <<<"$START")"
EXPIRES_IN="$(jq -r '.expires_in // 900' <<<"$START")"
[[ -n "$DEVICE_CODE" && -n "$USER_CODE" ]] || err "device flow did not start: $(head -c 300 <<<"$START")"

echo
echo "1. Open $VERIFY_URL in your browser and sign in to GitHub."
echo "2. Enter this one-time code (expires in $((EXPIRES_IN / 60)) minutes):"
echo
echo "       $USER_CODE"
echo
echo "Waiting for the authorization..."

ACCESS_TOKEN=""
SCOPES=""
DEADLINE=$(( $(date +%s) + EXPIRES_IN ))
while (( $(date +%s) < DEADLINE )); do
  sleep "$INTERVAL"
  POLL="$(curl -sS -X POST "https://github.com/login/oauth/access_token" \
    -H "Accept: application/json" \
    --data-urlencode "client_id=$CLIENT_ID" \
    --data-urlencode "device_code=$DEVICE_CODE" \
    --data-urlencode "grant_type=urn:ietf:params:oauth:grant-type:device_code")"
  ACCESS_TOKEN="$(jq -r '.access_token // empty' <<<"$POLL")"
  if [[ -n "$ACCESS_TOKEN" ]]; then
    SCOPES="$(jq -r '.scope // "none"' <<<"$POLL")"
    break
  fi
  case "$(jq -r '.error // empty' <<<"$POLL")" in
    authorization_pending) ;;
    slow_down) INTERVAL=$((INTERVAL + 5)) ;;
    "") err "unexpected poll response: $(head -c 300 <<<"$POLL")" ;;
    *) err "authorization failed: $(jq -r '.error' <<<"$POLL") ($(jq -r '.error_description // ""' <<<"$POLL"))" ;;
  esac
done
unset POLL DEVICE_CODE
[[ -n "$ACCESS_TOKEN" ]] || err "the code expired before it was entered"
echo "Authorized. Scopes granted: $SCOPES"
echo

# --- 2. Quota ----------------------------------------------------------------

quota() {  # $1: "plain" | "editor"
  local extra=()
  if [[ "$1" == "editor" ]]; then
    extra=(-H "Editor-Version: vscode/1.107.0" -H "Editor-Plugin-Version: copilot-chat/0.35.0" \
           -H "User-Agent: GitHubCopilotChat/0.35.0" -H "Copilot-Integration-Id: vscode-chat")
  else
    extra=(-H "User-Agent: AIMeter-probe")
  fi
  curl -sS -w '\n%{http_code}' \
    -H "Authorization: token $ACCESS_TOKEN" \
    -H "Accept: application/json" \
    "${extra[@]}" \
    "https://api.github.com/copilot_internal/user"
}

HTTP_RESPONSE="$(quota plain)"
HTTP_CODE="$(tail -n1 <<<"$HTTP_RESPONSE")"
BODY="$(sed '$d' <<<"$HTTP_RESPONSE")"
echo "plain headers:  HTTP $HTTP_CODE"
if [[ "$HTTP_CODE" != "200" ]]; then
  echo "  $(head -c 200 <<<"$BODY" | tr '\n' ' ')"
  HTTP_RESPONSE="$(quota editor)"
  HTTP_CODE="$(tail -n1 <<<"$HTTP_RESPONSE")"
  BODY="$(sed '$d' <<<"$HTTP_RESPONSE")"
  echo "editor headers: HTTP $HTTP_CODE"
fi
unset ACCESS_TOKEN
echo

if [[ "$HTTP_CODE" != "200" ]]; then
  echo "$BODY" | jq . 2>/dev/null || echo "$BODY" | head -c 600
  exit 1
fi

# Redact identifiers wherever they sit: keys ending in id, logins, names,
# emails, tracking ids; lists of logins become a count.
REDACTED="$(jq '
  walk(if type == "object" then with_entries(
    if (.key | test("(^|_)id$|login|email|tracking|name$"; "i")) then
      (if (.value | type) == "string" then .value = "<redacted>"
       elif (.value | type) == "array" then .value = ["<redacted x\(.value | length)>"]
       else . end)
    else . end) else . end)
' <<<"$BODY")"

echo "$REDACTED"
if [[ -n "$OUT_FILE" ]]; then
  echo "$REDACTED" > "$OUT_FILE"
  echo
  echo "redacted response saved to: $OUT_FILE"
fi
