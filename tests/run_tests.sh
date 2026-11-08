#!/usr/bin/env bash
# Runs the Godot test scripts headless. Usage: GODOT=/path/to/godot tests/run_tests.sh
set -u
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
fail=0
for t in tests/unit/p001/street_layout_test.gd tests/integration/p001/walk_test.gd; do
  "$GODOT" --headless --path . --audio-driver Dummy -s "res://$t" 2>&1 | grep -E "^(PASS|FAIL|RESULT)|SCRIPT ERROR|Parse Error" || true
  "$GODOT" --headless --path . --audio-driver Dummy -s "res://$t" >/dev/null 2>&1 || fail=1
done
python3 -m unittest discover -s tools/geodata/tests 2>&1 | tail -1
exit $fail
