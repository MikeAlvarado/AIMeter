#!/usr/bin/env bash
#
# Phase 1 validation script for AIMeter.
#
# Calls the undocumented usage endpoint that Claude Code uses internally
# (GET https://api.anthropic.com/api/oauth/usage) with your own Claude
# Code OAuth token, and prints the raw JSON response so we can confirm
# which usage windows the account actually returns (5h session, weekly,
# per-model weekly) and freeze the data model against reality.
#
# Token sources, in order:
#   1. macOS Keychain item "Claude Code-credentials" (what Claude Code
#      uses on macOS; may prompt for permission the first time)
#   2. ~/.claude/.credentials.json (Linux / older setups)
#
# The token is never printed and never written to disk by this script.
#
# Usage:
#   Scripts/probe-usage-endpoint.sh            # pretty-print response
#   Scripts/probe-usage-endpoint.sh -o FILE    # also save raw JSON to FILE

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

# --- 1. Locate credentials JSON ---------------------------------------------

CREDS_JSON=""
if [[ "$(uname)" == "Darwin" ]]; then
  CREDS_JSON="$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || true)"
fi
if [[ -z "$CREDS_JSON" && -f "$HOME/.claude/.credentials.json" ]]; then
  CREDS_JSON="$(cat "$HOME/.claude/.credentials.json")"
fi
[[ -n "$CREDS_JSON" ]] || err "no Claude Code credentials found (Keychain item 'Claude Code-credentials' or ~/.claude/.credentials.json). Is Claude Code installed and logged in?"

ACCESS_TOKEN="$(jq -r '.claudeAiOauth.accessToken // empty' <<<"$CREDS_JSON")"
EXPIRES_AT_MS="$(jq -r '.claudeAiOauth.expiresAt // 0' <<<"$CREDS_JSON")"
SUBSCRIPTION="$(jq -r '.claudeAiOauth.subscriptionType // "unknown"' <<<"$CREDS_JSON")"
SCOPES="$(jq -r '(.claudeAiOauth.scopes // []) | join(" ")' <<<"$CREDS_JSON")"
unset CREDS_JSON

[[ -n "$ACCESS_TOKEN" ]] || err "credentials found but no claudeAiOauth.accessToken field"

NOW_MS=$(( $(date +%s) * 1000 ))
if (( EXPIRES_AT_MS > 0 && EXPIRES_AT_MS < NOW_MS )); then
  echo "warning: token expired at $(date -r $((EXPIRES_AT_MS / 1000)) '+%Y-%m-%d %H:%M:%S')." >&2
  echo "         Run any 'claude' command to refresh it, then retry." >&2
fi

echo "subscription: $SUBSCRIPTION"
echo "scopes:       $SCOPES"
if (( EXPIRES_AT_MS > 0 )); then
  echo "token valid:  until $(date -r $((EXPIRES_AT_MS / 1000)) '+%Y-%m-%d %H:%M:%S')"
fi
echo

# --- 2. Call the usage endpoint ----------------------------------------------

# User-Agent matters: without a claude-code UA the endpoint applies a much
# stricter rate-limit bucket (persistent 429s).
CLAUDE_VERSION="$(claude --version 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' || echo "2.0.0")"

HTTP_RESPONSE="$(curl -sS -w '\n%{http_code}' \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "User-Agent: claude-code/$CLAUDE_VERSION" \
  "https://api.anthropic.com/api/oauth/usage")"
unset ACCESS_TOKEN

HTTP_CODE="$(tail -n1 <<<"$HTTP_RESPONSE")"
BODY="$(sed '$d' <<<"$HTTP_RESPONSE")"

echo "HTTP $HTTP_CODE"
echo

if [[ "$HTTP_CODE" != "200" ]]; then
  echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
  exit 1
fi

echo "$BODY" | jq .

if [[ -n "$OUT_FILE" ]]; then
  echo "$BODY" | jq . > "$OUT_FILE"
  echo
  echo "raw response saved to: $OUT_FILE"
fi
