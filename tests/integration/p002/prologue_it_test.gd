## Integration test (R6): new-game prologue from Köln Hbf via U-Bahn to Erol's KIOSK, with
## objectives, Erol's messages, save/load mid-prologue and the finished state.
## Run: godot --headless --path . -s res://tests/integration/p002/prologue_it_test.gd
extends SceneTree

const PATH := "user://test_prologue_it.json"
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
		await physics_frame


func _new_game() -> Node:
	var m: Node = load("res://src/p001/main.tscn").instantiate()
	m.save_path = PATH
	root.add_child(m)
	await _frames(30)
	return m


func _go(m: Node, p: Vector3) -> void:
	m.player.global_position = p + Vector3(0, 0.95, 0)
	m.player.velocity = Vector3.ZERO
	await _frames(15)


func _has_msg(m: Node, id: String) -> bool:
	for msg in m.messages.inbox:
		if msg.id == id:
			return true
	return false


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var m: Node = await _new_game()
	var ix: StrayInteractions = m.interactions
	check(m.prologue.is_done() and m.ui.objective_label.text == "", "no prologue without 'Neues Spiel'")
	m._on_new_game()
	await _frames(40)
	var a: StrayAreaLayout = m.area.area
	var pp: Vector3 = m.player.global_position
	check(m.region == "p002" and m.player.is_on_floor(), "arrives on the Bahnhofsvorplatz, standing")
	check(Vector2(pp.x, -pp.z).distance_to(StrayStreetLayout._v2(a.hbf_main_exit["en"])) < 6.0, "in front of the Hbf exit")
	check(m.clock.hhmm().begins_with("22:4"), "arrival around 22:40 (%s)" % m.clock.hhmm())
	check("U-Bahn" in m.ui.objective_label.text, "objective: U-Bahn")
	check(_has_msg(m, "erol_welcome") and m.messages.contacts["erol"]["known"], "Erol's message, contact known")

	await _go(m, ix.points["ubahn_dom_hbf"])
	ix.interact()
	await _frames(10)
	check(m.prologue.current_id() == "ticket" and "Fahrkarte" in m.ui.objective_label.text, "objective: ticket")
	# Save on the platform, reload: the step survives.
	check(m.save_game("test"), "saved mid-prologue")
	m.queue_free()
	await _frames(5)
	m = await _new_game()
	ix = m.interactions
	check(m.load_game(), "loaded")
	await _frames(10)
	check(m.prologue.current_id() == "ticket" and "Fahrkarte" in m.ui.objective_label.text and m.region == "metro", "still at the ticket step on the platform")

	await _go(m, ix.points["metro_ticket"])
	ix.interact()
	ix._on_option(0)
	check(m.prologue.current_id() == "ride", "objective: ride")
	await _go(m, ix.points["metro_board"])
	ix.interact()
	ix._on_option(0)
	await _frames(5)
	check(m.prologue.current_id() == "surface" and m.transit.station == "friesenplatz", "arrived at Friesenplatz: objective stairs")
	await _go(m, ix.points["metro_exit"])
	ix.interact()
	await _frames(20)
	check(m.prologue.current_id() == "kiosk" and m.region == "p001", "on the Ring: objective KIOSK")
	# Regression: the autosave on coming up must already hold the new step.
	var p_ring: Vector3 = m.player.global_position
	check(m.load_game() and m.prologue.current_id() == "kiosk", "autosave after the stairs holds the KIOSK step (%s)" % m.prologue.current_id())
	m.player.global_position = p_ring
	await _go(m, ix.points["kiosk"])
	await _frames(10)
	check(m.prologue.is_done() and m.ui.objective_label.text == "", "prologue finished at the KIOSK")
	check(_has_msg(m, "erol_arrived"), "Erol points to the Jobs app")
	check(m.load_game() and m.prologue.is_done(), "finished state saved (autosave on finish)")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("RESULT prologue_it_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
