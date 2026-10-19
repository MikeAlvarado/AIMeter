#!/usr/bin/env bash
#
# Prints the *shape* of the profile endpoint's response, never its values:
# GET https://api.anthropic.com/api/oauth/profile with your own Claude Code
# OAuth token, every key with the type of what it holds (a string's
# length, a number, a bool, null, an object or an array), so the data
# model can be checked against reality without a captured response that
# would carry your name, address or ids.
#
# Token sources, in order (same as probe-usage-endpoint.sh):
#   1. macOS Keychain item "Claude Code-credentials" (may prompt once)
#   2. ~/.claude/.credentials.json
#   3. AIMeter's own Keychain item, when Claude Code's holds no token
#
# The token is never printed and nothing is written to disk.
#
# Usage:
#   Scripts/probe-profile-endpoint.sh

set -euo pipefail

err() { echo "error: $*" >&2; exit 1; }
command -v jq >/dev/null || err "jq is required (brew install jq)"

CREDS_JSON=""
if [[ "$(uname)" == "Darwin" ]]; then
  CREDS_JSON="$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || true)"
fi
if [[ -z "$CREDS_JSON" && -f "$HOME/.claude/.credentials.json" ]]; then
  CREDS_JSON="$(cat "$HOME/.claude/.credentials.json")"
fi
[[ -n "$CREDS_JSON" ]] || err "no Claude Code credentials found. Is Claude Code installed and logged in?"
ACCESS_TOKEN="$(jq -r '.claudeAiOauth.accessToken // empty' <<<"$CREDS_JSON")"
unset CREDS_JSON

# --- 1b. AIMeter's own login, when Claude Code's item is a logged-out stub --
# Claude Code leaves its Keychain item behind with empty tokens on logout
# (measured 2026-10-19: accessToken "", expiresAt 0). The app's own copy of
# a login signed in through AIMeter lives under its bundle ID, one item per
# account (`claude.credentials.<accountID>`), as a bare credentials JSON.
if [[ -z "$ACCESS_TOKEN" && "$(uname)" == "Darwin" ]]; then
  OWN_JSON="$(security find-generic-password -s "com.mikealvarado.aimeter" -w 2>/dev/null || true)"
  if [[ -n "$OWN_JSON" ]]; then
    ACCESS_TOKEN="$(jq -r '.accessToken // empty' <<<"$OWN_JSON")"
    [[ -n "$ACCESS_TOKEN" ]] && echo "token source: AIMeter's own login (the Claude Code item holds no token)" >&2
  fi
  unset OWN_JSON
fi
[[ -n "$ACCESS_TOKEN" ]] || err "credentials found but no access token in them (Claude Code logged out, and no login signed in through AIMeter)"

CLAUDE_VERSION="$(claude --version 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' || echo "2.0.0")"
HTTP_RESPONSE="$(curl -sS -w '\n%{http_code}' \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -H "Accept: application/json" \
  -H "User-Agent: claude-code/$CLAUDE_VERSION" \
  "https://api.anthropic.com/api/oauth/profile")"
unset ACCESS_TOKEN
HTTP_CODE="$(tail -n1 <<<"$HTTP_RESPONSE")"
BODY="$(sed '$d' <<<"$HTTP_RESPONSE")"
echo "HTTP $HTTP_CODE"
[[ "$HTTP_CODE" == "200" ]] || { echo "$BODY" | head -c 400; echo; exit 1; }

# Every path with the type of its value; strings as their length only.
jq -r '
  def shape: if type == "string" then "string(\(length))"
    elif type == "object" then "object" elif type == "array" then "array[\(length)]"
    else type end;
  . as $root | [paths] | unique[] | . as $p
  | "\($p | map(tostring) | join(".")): \($root | getpath($p) | shape)"
' <<<"$BODY" | sort
