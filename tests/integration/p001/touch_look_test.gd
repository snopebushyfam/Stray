## Regression test (R7 tablet feedback 2026-11-09): with one finger on the joystick (left) and one
## dragging the camera (right), the camera jittered wildly. Mobile browsers can mix up the two
## fingers, so a "look" drag arrives with the joystick finger's position and a huge `relative`.
## The camera must ignore such jumps and still follow the real look finger.
## Run: godot --headless --path . -s res://tests/integration/p001/touch_look_test.gd
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


func _touch(p: StrayPlayer, index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	p._unhandled_input(e)


func _drag(p: StrayPlayer, index: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	e.relative = rel
	p._unhandled_input(e)


func _run() -> void:
	var m: Node = load("res://src/p001/main.tscn").instantiate()
	root.add_child(m)
	for i in 20:
		await physics_frame
	var p: StrayPlayer = m.player
	var w: float = p.get_viewport().get_visible_rect().size.x
	var stick := Vector2(w * 0.15, 500)
	var look := Vector2(w * 0.75, 400)
	_touch(p, 0, stick, true)
	_touch(p, 1, look, true)
	var max_step := 0.0
	var yaw0 := p.get_yaw()
	var prev := yaw0
	var lp := look
	for i in 20:
		lp += Vector2(4, 0)
		_drag(p, 1, lp, Vector2(4, 0))                       # real look finger
		max_step = maxf(max_step, absf(rad_to_deg(p.get_yaw() - prev)))
		prev = p.get_yaw()
		var stick_now := stick + Vector2((i % 5) * 8 - 16, (i % 3) * 10 - 10)  # deterministic wobble
		_drag(p, 1, stick_now, stick_now - lp)               # browser mixed up the fingers
		max_step = maxf(max_step, absf(rad_to_deg(p.get_yaw() - prev)))
		prev = p.get_yaw()
	var total := absf(rad_to_deg(p.get_yaw() - yaw0))
	var sens: float = p.cfg.get("touch_look_sensitivity_deg_per_px", 0.25)
	check(max_step < 5.0, "no camera jumps (largest step %.1f deg)" % max_step)
	check(absf(total - 80.0 * sens) < 2.0, "camera follows the look finger (%.1f deg, expected %.1f)" % [total, 80.0 * sens])
	print("RESULT touch_look_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
