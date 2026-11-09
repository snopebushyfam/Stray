#!/usr/bin/env bash
# Builds the HTML5 (Web, no threads) release and packs the ZIP for itch.io.
# Usage: GODOT=/path/to/godot tools/release/package_itch.sh
# Output: build/stray_web_itch.zip (index.html at the zip root, as itch.io requires).
# Guide: docs/RELEASE_ITCH.md
set -euo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/../.."
mkdir -p build/web
# Keep Godot from importing the exported files as project assets (left *.import junk before).
touch build/.gdignore
rm -f build/web/* build/stray_web_itch.zip
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Web" build/web/index.html
for f in index.html index.js index.wasm index.pck; do
  [ -s "build/web/$f" ] || { echo "missing build/web/$f"; exit 1; }
done
(cd build/web && zip -q -9 ../stray_web_itch.zip ./*)
ls -la build/web build/stray_web_itch.zip
unzip -l build/stray_web_itch.zip
echo "OK: build/stray_web_itch.zip"
