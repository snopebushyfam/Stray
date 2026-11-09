## Regression test (R9.2, tablet bug "BAR menu on the street"): a menu opened inside the club must
## never stay open outside - loading a save, leaving the club, or arriving next to the KIOSK.
## Run: godot --headless --path . -s res://tests/integration/p001/ui_state_test.gd
extends SceneTree

const PATH := "user://test_ui_state.json"
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


func _open_bar(m: Node) -> void:
	var ix: StrayInteractions = m.interactions
	if not ix.life.flags.get("inside_club", false):
		ix.enter_club()
	m.player.global_position = ix.points["club_bar"] + Vector3(0, 0.95, 0)
	await _frames(10)
	ix.interact()
	await _frames(2)


func _menu_closed(m: Node) -> bool:
	return not m.ui.shop_panel.visible and not m.interactions.shop_open and m.player.input_enabled


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var m: Node = load("res://src/p001/main.tscn").instantiate()
	m.save_path = PATH
	root.add_child(m)
	await _frames(30)
	var ix: StrayInteractions = m.interactions
	ix.life.cash_cents = 5000
	# Save outside, standing at the KIOSK.
	m.player.global_position = ix.points["kiosk"] + Vector3(0, 0.95, 0)
	await _frames(10)
	# Entering the club autosaves; keep the street state and write it back right before loading.
	var street_save := StraySaveGame.capture(m)
	# A) Bar menu open in the club, then "Laden" from the pause menu (save made on the street).
	await _open_bar(m)
	check(m.ui.shop_panel.visible and ix.active_shop == ix.bar_shop, "bar menu open in the club")
	check(StraySaveGame.write(PATH, street_save).is_empty() and m.load_game(), "loaded the street save")
	await _frames(15)
	check(not ix.life.flags.get("inside_club", false), "back on the street")
	check(_menu_closed(m), "bar menu closed after loading outside (panel=%s shop_open=%s)" % [m.ui.shop_panel.visible, ix.shop_open])
	# B) Bar menu open, then leaving the club (exit / scripted).
	await _open_bar(m)
	ix.leave_club()
	await _frames(15)
	check(_menu_closed(m), "bar menu closed when leaving the club")
	# C) Bar menu open, save inside, load: arrives at the club entrance without a stale menu.
	await _open_bar(m)
	m.save_game("in_club")
	check(m.load_game(), "loaded the club save")
	await _frames(15)
	check(_menu_closed(m), "no stale menu after loading inside the club (panel=%s shop_open=%s input=%s)" % [m.ui.shop_panel.visible, ix.shop_open, m.player.input_enabled])
	# C2) ... and walking out through the exit must not carry a menu onto the street.
	m.player.global_position = ix.points["club_exit"] + Vector3(0, 0.95, 0)
	await _frames(10)
	ix.interact()
	await _frames(15)
	check(not ix.life.flags.get("inside_club", false) and _menu_closed(m), "outside after the exit, no BAR menu (panel=%s)" % m.ui.shop_panel.visible)
	# D) The KIOSK menu still works normally afterwards.
	ix.leave_club()
	m.player.global_position = ix.points["kiosk"] + Vector3(0, 0.95, 0)
	await _frames(10)
	ix.interact()
	check(m.ui.shop_panel.visible and ix.active_shop == ix.shop, "KIOSK menu opens normally")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("RESULT ui_state_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
