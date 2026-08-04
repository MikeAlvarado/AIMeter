#!/usr/bin/env bash
#
# Peak-hours investigation probe for AIMeter.
#
# Anthropic has repeatedly introduced/reverted a "peak hours" policy where
# 5-hour session usage burns faster on weekday mornings PT. This script
# does NOT assume where that signal lives. It dumps the COMPLETE raw JSON
# of both undocumented endpoints AIMeter already calls, unfiltered, plus
# timing metadata, so two captures (one during the documented peak window,
# one outside it) can be diffed byte-for-byte to see whether anything
# beyond the usage percentages changes.
#
# Token sources, in order (same as probe-usage-endpoint.sh):
#   1. macOS Keychain item "Claude Code-credentials"
#   2. ~/.claude/.credentials.json
#
# The token is never printed and never written to disk by this script.
#
# Usage:
#   Scripts/probe-peak-hours.sh                # pretty-print both responses
#   Scripts/probe-peak-hours.sh -o DIR         # also save timestamped raw
#                                                 JSON + metadata into DIR
#
# To compare two captures:
#   diff <(jq -S . DIR/usage-CAPTURE1.json) <(jq -S . DIR/usage-CAPTURE2.json)

set -euo pipefail

OUT_DIR=""
while getopts "o:" opt; do
  case "$opt" in
    o) OUT_DIR="$OPTARG" ;;
    *) echo "usage: $0 [-o output_dir]" >&2; exit 2 ;;
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
unset CREDS_JSON

[[ -n "$ACCESS_TOKEN" ]] || err "credentials found but no claudeAiOauth.accessToken field"

NOW_MS=$(( $(date +%s) * 1000 ))
if (( EXPIRES_AT_MS > 0 && EXPIRES_AT_MS < NOW_MS )); then
  echo "warning: token expired. Run any 'claude' command to refresh it, then retry." >&2
fi

# --- 2. Timing metadata (this is the whole point: record exactly when) -----

UTC_NOW="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
LOCAL_NOW="$(date '+%Y-%m-%d %H:%M:%S %Z (%A)')"
DOW="$(date -u '+%A')"
PT_NOW="$(TZ='America/Los_Angeles' date '+%Y-%m-%d %H:%M:%S %Z (%A)')"

echo "=== capture timing ==="
echo "UTC:            $UTC_NOW"
echo "local:          $LOCAL_NOW"
echo "America/Los_Angeles: $PT_NOW"
echo "subscription:   $SUBSCRIPTION"
echo
echo "documented policy: weekday 5:00-11:00 AM PT = peak (2x burn), weekends fully off-peak."
echo "(this line is informational only - nothing below assumes it's true)"
echo

CLAUDE_VERSION="$(claude --version 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' || echo "2.0.0")"

fetch() {
  local url="$1"
  curl -sS -w '\n%{http_code}' \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -H "User-Agent: claude-code/$CLAUDE_VERSION" \
    "$url"
}

# --- 3. Usage endpoint --------------------------------------------------

echo "=== GET /api/oauth/usage (full raw response, no field filtering) ==="
USAGE_RESPONSE="$(fetch "https://api.anthropic.com/api/oauth/usage")"
USAGE_HTTP_CODE="$(tail -n1 <<<"$USAGE_RESPONSE")"
USAGE_BODY="$(sed '$d' <<<"$USAGE_RESPONSE")"
echo "HTTP $USAGE_HTTP_CODE"
if [[ "$USAGE_HTTP_CODE" == "200" ]]; then
  echo "$USAGE_BODY" | jq .
else
  echo "$USAGE_BODY" | jq . 2>/dev/null || echo "$USAGE_BODY"
fi
echo

# --- 4. Profile endpoint --------------------------------------------------

echo "=== GET /api/oauth/profile (full raw response, no field filtering) ==="
PROFILE_RESPONSE="$(fetch "https://api.anthropic.com/api/oauth/profile")"
unset ACCESS_TOKEN
PROFILE_HTTP_CODE="$(tail -n1 <<<"$PROFILE_RESPONSE")"
PROFILE_BODY="$(sed '$d' <<<"$PROFILE_RESPONSE")"
echo "HTTP $PROFILE_HTTP_CODE"
if [[ "$PROFILE_HTTP_CODE" == "200" ]]; then
  echo "$PROFILE_BODY" | jq .
else
  echo "$PROFILE_BODY" | jq . 2>/dev/null || echo "$PROFILE_BODY"
fi
echo

# --- 5. Grep both bodies for anything peak/rate-shaping related ------------

echo "=== grep for peak-related keys/values (both bodies, case-insensitive) ==="
PATTERN='peak|multiplier|surge|off_peak|offpeak|schedule|tier|factor|weight|"rate"|cost'
COMBINED="$USAGE_BODY"$'\n'"$PROFILE_BODY"
if grep -inE "$PATTERN" <<<"$COMBINED"; then
  echo "(matches above - inspect closely, could be false positive e.g. 'weekly')"
else
  echo "no matches for: $PATTERN"
fi
echo

# --- 6. Optional: save timestamped artifacts for diffing -------------------

if [[ -n "$OUT_DIR" ]]; then
  mkdir -p "$OUT_DIR"
  STAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
  echo "$USAGE_BODY" | jq . > "$OUT_DIR/usage-$STAMP.json"
  echo "$PROFILE_BODY" | jq . > "$OUT_DIR/profile-$STAMP.json"
  {
    echo "utc: $UTC_NOW"
    echo "local: $LOCAL_NOW"
    echo "pt: $PT_NOW"
    echo "day_of_week_utc: $DOW"
  } > "$OUT_DIR/meta-$STAMP.txt"
  echo "saved to: $OUT_DIR/{usage,profile,meta}-$STAMP.json"
fi
