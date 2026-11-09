## Unit tests (R6): prologue step order, multi-step events, skip, save state.
## Run: godot --headless --path . -s res://tests/unit/p002/prologue_test.gd
extends SceneTree

var _failed := 0
var _passed := 0
var cfg: Dictionary


func check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("FAIL ", what)


func _initialize() -> void:
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/p002/prologue_config.json"))
	test_start_shows_first_objective()
	test_steps_advance_in_order_and_ignore_other_events()
	test_ride_without_ticket_finishes_ticket_and_ride()
	test_finish_emits_once_and_clears_objective()
	test_save_state_roundtrip_and_old_saves_count_as_done()
	print("RESULT prologue_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func test_start_shows_first_objective() -> void:
	var p := StrayPrologue.new(cfg)
	check(not p.active() and p.objective() == "", "inactive before start")
	var seen: Array = []
	p.step_started.connect(func(id, _o, _h): seen.append(id))
	p.start()
	check(p.current_id() == "to_ubahn" and "U-Bahn" in p.objective() and seen == ["to_ubahn"], "first step: to_ubahn")


func test_steps_advance_in_order_and_ignore_other_events() -> void:
	var p := StrayPrologue.new(cfg)
	p.start()
	check(p.event("near_kiosk") == 0 and p.current_id() == "to_ubahn", "kiosk before the U-Bahn does nothing")
	check(p.event("metro_entered") == 1 and p.current_id() == "ticket", "metro -> ticket")
	check(p.event("ticket_bought") == 1 and p.current_id() == "ride", "ticket -> ride")
	check(p.event("rode_friesenplatz") == 1 and p.current_id() == "surface", "ride -> surface")
	check(p.event("surface_friesenplatz") == 1 and p.current_id() == "kiosk", "surface -> kiosk")


func test_ride_without_ticket_finishes_ticket_and_ride() -> void:
	var p := StrayPrologue.new(cfg)
	p.start()
	p.event("metro_entered")
	check(p.event("rode_friesenplatz") == 2 and p.current_id() == "surface", "fare dodging skips the ticket step")


func test_finish_emits_once_and_clears_objective() -> void:
	var p := StrayPrologue.new(cfg)
	var fin := [0]
	p.finished.connect(func(): fin[0] += 1)
	p.start()
	for e in ["metro_entered", "ticket_bought", "rode_friesenplatz", "surface_friesenplatz", "near_kiosk", "near_kiosk"]:
		p.event(e)
	check(p.is_done() and not p.active() and p.objective() == "" and fin[0] == 1, "done, finished emitted once")


func test_save_state_roundtrip_and_old_saves_count_as_done() -> void:
	var p := StrayPrologue.new(cfg)
	p.start()
	p.event("metro_entered")
	var q := StrayPrologue.new(cfg)
	q.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	check(q.current_id() == "ticket", "step restored")
	var old := StrayPrologue.new(cfg)
	old.from_dict({})
	check(old.is_done(), "save without prologue = done")
