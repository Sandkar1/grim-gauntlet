#!/usr/bin/env bash
# Builds a standalone Windows executable of Grim Gauntlet from Linux.
#
#   ./build.sh                 -> build/windows/GrimGauntlet.exe
#   ./build.sh /mnt/c/Games    -> also copies the .exe there
#
# Needs the Godot 4.7.2 Linux binary and its Windows export templates
# (see README, "Building").
set -euo pipefail
cd "$(dirname "$0")"

GODOT="${GODOT:-$HOME/.local/godot/Godot_v4.7.2-stable_linux.x86_64}"
OUT="build/windows/GrimGauntlet.exe"

mkdir -p "$(dirname "$OUT")"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Windows Desktop" "$OUT"
echo "Built $OUT ($(du -h "$OUT" | cut -f1))"

if [[ $# -ge 1 ]]; then
	mkdir -p "$1"
	cp "$OUT" "$1/"
	echo "Copied to $1/GrimGauntlet.exe"
fi
