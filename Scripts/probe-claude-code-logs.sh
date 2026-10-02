#!/usr/bin/env bash
#
# Prints the *shape* of Claude Code's local usage logs
# (~/.claude/projects/**/*.jsonl) — record types, the keys of `assistant`
# and `cost-state` records, the `usage` keys, model ids and Claude Code
# versions seen — never any conversation content. This is what the
# ClaudeCode reader in UsageKit is written against; re-run after a Claude
# Code update to catch a format change before users do.
#
# Usage:
#   Scripts/probe-claude-code-logs.sh            # ~/.claude/projects
#   Scripts/probe-claude-code-logs.sh DIR        # another logs root

set -euo pipefail
ROOT="${1:-$HOME/.claude/projects}"
export ROOT
python3 - <<'PY'
import collections, glob, json, os
root = os.environ["ROOT"]
files = glob.glob(os.path.join(root, "**", "*.jsonl"), recursive=True)
types = collections.Counter(); asst_keys = set(); cost_keys = set(); usage_keys = set()
models = collections.Counter(); versions = set(); dup = 0; total_asst = 0
print(f"files: {len(files)} under {root}")
for f in files:
    seen = set()
    with open(f, "rb") as fh:
        for raw in fh:
            try: o = json.loads(raw)
            except Exception: types["<unparseable>"] += 1; continue
            t = o.get("type"); types[t] += 1
            if t == "assistant":
                total_asst += 1
                asst_keys.update(o.keys()); m = o.get("message") or {}
                usage_keys.update((m.get("usage") or {}).keys()); models[m.get("model")] += 1
                versions.add(o.get("version"))
                key = (m.get("id"), o.get("requestId"))
                if key in seen: dup += 1
                seen.add(key)
            elif t == "cost-state":
                cost_keys.update(o.keys())
print("record types:", dict(types))
print("assistant keys:", sorted(k for k in asst_keys if k))
print("usage keys:", sorted(usage_keys))
print("cost-state keys:", sorted(cost_keys))
print("models:", dict(models))
print("claude code versions:", sorted(v for v in versions if v))
print(f"assistant lines: {total_asst}, duplicate (message.id, requestId) lines: {dup}")
PY
