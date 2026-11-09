## Integration test (R9.1): optional FPS display - off by default, F3 / toggle_fps() shows it,
## text updates, never captures touches, second toggle hides it, player control unaffected.
## Run: godot --headless --path . -s res://tests/integration/p001/fps_display_test.gd
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


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var m: Node = load("res://src/p001/main.tscn").instantiate()
	root.add_child(m)
	await _frames(20)
	check(m.fps_label != null and not m.fps_label.visible, "FPS display off by default")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F3
	ev.pressed = true
	m._unhandled_input(ev)
	await _frames(30)
	check(m.fps_label.visible and m.fps_label.text.begins_with("FPS "), "F3 shows it: '%s'" % m.fps_label.text)
	check("Ø 10 s" in m.fps_label.text, "shows the 10 s average")
	check(m.fps_label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "does not capture touches")
	check(m.player.input_enabled and m.menu.mode.is_empty(), "player control unaffected")
	m.toggle_fps()
	check(not m.fps_label.visible, "second toggle hides it")
	print("RESULT fps_display_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
