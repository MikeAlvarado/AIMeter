#!/usr/bin/env bash
#
# Captures Claude's public status page summary — the Atlassian Statuspage
# JSON AIMeter reads to tell a service incident apart from an account
# problem (GET https://status.claude.com/api/v2/summary.json; the old
# status.anthropic.com host redirects there). No credentials involved.
#
# Prints the response, and with -o also saves the raw JSON — that's how
# Tests/UsageKitTests/Fixtures/status-summary-operational.json was made.
# Re-run during a real incident to capture a degraded fixture.
#
# Usage:
#   Scripts/probe-status-endpoint.sh            # pretty-print
#   Scripts/probe-status-endpoint.sh -o FILE    # also save raw JSON to FILE

set -euo pipefail

OUT_FILE=""
while getopts "o:" opt; do
  case "$opt" in
    o) OUT_FILE="$OPTARG" ;;
    *) echo "usage: $0 [-o output.json]" >&2; exit 2 ;;
  esac
done

ENDPOINT="https://status.claude.com/api/v2/summary.json"
RESPONSE="$(curl -sS --fail -L --max-time 15 -H "Accept: application/json" "$ENDPOINT")"

if [[ -n "$OUT_FILE" ]]; then
  printf '%s\n' "$RESPONSE" | python3 -m json.tool > "$OUT_FILE"
  echo "saved to $OUT_FILE" >&2
fi

printf '%s\n' "$RESPONSE" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print("status:", d["status"]["indicator"], "-", d["status"]["description"])
for c in d["components"]:
    if not c.get("group"):
        print(f"  {c[\"name\"]}: {c[\"status\"]}")
print("incidents:", len(d["incidents"]), " scheduled maintenances:", len(d.get("scheduled_maintenances", [])))
for i in d["incidents"]:
    print(f"  [{i[\"impact\"]}] {i[\"name\"]} ({i[\"status\"]}) {i.get(\"shortlink\", \"\")}")
'
