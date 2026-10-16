#!/usr/bin/env bash
#
# Draws every session pet into one PNG from the app's own sprite code
# (Shared/SessionPet.swift and SessionPet+Sprites.swift, compiled with
# Scripts/PetsPreview/main.swift): a row per creature, standing, mid-step,
# waiting and asleep, with each accessory and in each color, on the notch
# island's black. For looking at a new or changed pet before it ships; see
# "A new pet" under "Recipes" in CLAUDE.md.
#
# Usage:
#   Scripts/pets-preview.sh            # pets.png in a new temporary folder
#   Scripts/pets-preview.sh DIR        # DIR/pets.png

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-$(mktemp -d)}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT_DIR"
swiftc -swift-version 5 -O \
  "$ROOT/Shared/SessionPet.swift" "$ROOT/Shared/SessionPet+Sprites.swift" \
  "$ROOT/Scripts/PetsPreview/main.swift" -o "$WORK/pets-preview"
"$WORK/pets-preview" "$OUT_DIR/pets.png"
