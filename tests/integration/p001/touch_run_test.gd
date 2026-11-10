## Regression test (R7 tablet feedback 2026-11-09): on tablets there was no way to run (Shift only).
## Now: joystick pushed to the edge runs (touch only), and a "Rennen" toggle runs too.
## Run: godot --headless --path . -s res://tests/integration/p001/touch_run_test.gd
extends SceneTree

var _failed := 0
var _passed := 0


func check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
		print("PASS ", what)
	else:
		_failed += 1
		print("FAIL ", what)


func _initialize() -> void:
	_run.call_deferred()


func _speed_after(m: Node, strength: float) -> float:
	var p: StrayPlayer = m.player
	p.global_position = m.builder.layout.spawn_position(0.9)
	p.velocity = Vector3.ZERO
	Input.action_press("move_forward", strength)
	# Peak speed: a pedestrian crossing the path can deflect the player late in the run.
	var v := 0.0
	for i in 60:
		await physics_frame
		v = maxf(v, Vector2(p.velocity.x, p.velocity.z).length())
	Input.action_release("move_forward")
	for i in 10:
		await physics_frame
	return v


func _run() -> void:
	var m: Node = load("res://src/p001/main.tscn").instantiate()
	root.add_child(m)
	for i in 20:
		await physics_frame
	var p: StrayPlayer = m.player
	var walk: float = p.cfg.get("walk_speed", 1.35)
	var run: float = p.cfg.get("run_speed", 4.5)
	p.touch_mode = false
	var v := await _speed_after(m, 1.0)
	check(absf(v - walk) < 0.3, "keyboard full forward walks (%.2f m/s)" % v)
	p.touch_mode = true
	v = await _speed_after(m, 1.0)
	check(absf(v - run) < 0.3, "touch: stick at the edge runs (%.2f m/s)" % v)
	v = await _speed_after(m, 0.6)
	check(v < walk + 0.1, "touch: stick half way walks (%.2f m/s)" % v)
	p.run_toggle = true
	v = await _speed_after(m, 0.6)
	# half stick + toggle: run speed scaled by the stick (R12.5 run speed 3.8 -> ~1.9 m/s), faster than full walking
	check(v > walk, "toggle 'Rennen' runs (%.2f m/s)" % v)
	print("RESULT touch_run_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
