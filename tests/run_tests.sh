#!/usr/bin/env bash
# Runs the Godot test scripts headless. Usage: GODOT=/path/to/godot tests/run_tests.sh
set -u
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
fail=0
# Register new class_name scripts / import assets first (otherwise new classes are "not found").
timeout 900 "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
for t in tests/unit/p001/street_layout_test.gd tests/unit/p001/life_rules_test.gd tests/integration/p001/walk_test.gd tests/integration/p001/street_life_test.gd tests/integration/p001/interaction_test.gd tests/unit/p001/phone_logic_test.gd tests/integration/p001/phone_test.gd tests/integration/p001/club_test.gd tests/unit/p001/save_roundtrip_test.gd tests/integration/p001/save_load_test.gd tests/unit/p001/day_rent_test.gd tests/integration/p001/home_test.gd; do
  # A script error leaves Godot running instead of quitting: the timeout turns that into a failure.
  out=$(timeout 600 "$GODOT" --headless --path . --audio-driver Dummy -s "res://$t" 2>&1); rc=$?
  echo "$out" | grep -E "^(PASS|FAIL|RESULT)|SCRIPT ERROR|Parse Error" || true
  [ $rc -eq 0 ] || { echo "EXIT $rc for $t"; fail=1; }
  # Godot keeps running after many script errors; any SCRIPT ERROR is a failure.
  if echo "$out" | grep -q "SCRIPT ERROR"; then echo "SCRIPT ERROR in $t"; fail=1; fi
done
py=$(python3 -m unittest discover -s tools/geodata/tests 2>&1 | tail -1)
echo "python data tests: $py"
case "$py" in OK*) ;; *) fail=1 ;; esac
echo "ALL_TESTS_EXIT=$fail"
exit $fail
