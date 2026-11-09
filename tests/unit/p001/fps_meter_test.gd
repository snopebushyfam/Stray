## Unit tests (R9.1): FPS meter - current rate, 10 s moving average, window trimming.
## Run: godot --headless --path . -s res://tests/unit/p001/fps_meter_test.gd
extends SceneTree

var _failed := 0
var _passed := 0


func check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("FAIL ", what)


func _initialize() -> void:
	test_steady_60_fps()
	test_average_covers_ten_seconds_current_follows_drop()
	test_ignores_bad_deltas_and_resets()
	print("RESULT fps_meter_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func test_steady_60_fps() -> void:
	var m := StrayFpsMeter.new()
	check(m.average_fps() == 0.0 and m.current_fps() == 0.0, "no data -> 0")
	for i in 600:
		m.add_frame(1.0 / 60.0)
	check(absf(m.average_fps() - 60.0) < 0.01 and absf(m.current_fps() - 60.0) < 0.01, "steady 60 fps")


func test_average_covers_ten_seconds_current_follows_drop() -> void:
	var m := StrayFpsMeter.new()
	for i in 600:          # 10 s at 60 fps
		m.add_frame(1.0 / 60.0)
	for i in 50:           # then 5 s at 10 fps
		m.add_frame(0.1)
	# Window = last 10 s: 5 s at 60 (300 frames) + 5 s at 10 (50 frames) -> 35 fps.
	check(absf(m.average_fps() - 35.0) < 0.5, "10 s average 35 fps (%.2f)" % m.average_fps())
	check(absf(m.current_fps() - 10.0) < 0.01, "current follows the drop (%.2f)" % m.current_fps())
	check(absf(m.covered_seconds() - 10.0) < 0.05, "window trimmed to 10 s (%.2f)" % m.covered_seconds())


func test_ignores_bad_deltas_and_resets() -> void:
	var m := StrayFpsMeter.new()
	m.add_frame(0.0)
	m.add_frame(-1.0)
	check(m.average_fps() == 0.0, "zero/negative deltas ignored")
	m.add_frame(0.5)
	m.reset()
	check(m.average_fps() == 0.0 and m.covered_seconds() == 0.0, "reset clears")
