## Integration test (R1): play, save, start a fresh game instance, load, compare.
## Run: godot --headless --path . -s res://tests/integration/p001/save_load_test.gd
extends SceneTree

const PATH := "user://test_save_load_it.json"
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


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	# --- session 1: do things, save -----------------------------------------------------------
	var a: Node = await _new_game()
	check(not paused, "no start menu / pause inside tests")
	var ix: StrayInteractions = a.interactions
	a.player.global_position = ix.points["atm_0"] + Vector3(0, 0.95, 0)
	await _frames(15)
	ix.interact()  # ATM: +20 € cash
	a.player.global_position = ix.points["kiosk"] + Vector3(0, 0.95, 0)
	await _frames(15)
	ix.interact()
	ix._on_shop_choice("koelsch")
	ix._on_shop_choice("")
	a.phone.open_app("messages")  # marks read
	a.clock.advance(600.0)  # +100 game minutes
	var spot: Vector3 = a.builder.layout.spawn_position(0.9) + Vector3(2.0, 0.0, -3.0)
	a.player.global_position = spot
	a.player.face_yaw(1.0)
	await _frames(10)
	var snap := {"cash": ix.life.cash_cents, "account": ix.life.account_cents, "time": a.clock.hhmm(),
		"pos": a.player.global_position, "tx": ix.life.transactions.size()}
	check(a.save_game("test"), "save written")
	check(StraySaveGame.exists(PATH), "save file exists")
	a.queue_free()
	await _frames(5)

	# --- session 2: fresh game, load ------------------------------------------------------------
	var b: Node = await _new_game()
	check(b.interactions.life.cash_cents == 3500 and b.clock.hhmm() == "23:10", "fresh game starts clean")
	check(b.load_game(), "load ok")
	var life: StrayLifeState = b.interactions.life
	check(life.cash_cents == snap.cash and life.account_cents == snap.account, "money restored (%s / %s)" % [StrayLifeState.euro(life.cash_cents), StrayLifeState.euro(life.account_cents)])
	check(life.inventory.get("koelsch", 0) == 1 and life.drinks_alcohol == 1, "inventory restored")
	check(life.transactions.size() == snap.tx, "bookings restored (%d)" % life.transactions.size())
	check(b.clock.hhmm() == snap.time, "clock restored (%s)" % b.clock.hhmm())
	check(b.messages.unread == 0 and b.messages.inbox.size() == 2, "messages restored and still read")
	check(b.player.global_position.distance_to(snap.pos) < 0.1, "player position restored")
	check(is_equal_approx(b.player.get_yaw(), 1.0), "player facing restored")
	check(StrayLifeState.euro(life.cash_cents) in b.ui.status_label.text, "HUD shows loaded cash")
	await _frames(30)
	check(b.player.is_on_floor(), "standing on the ground after loading")

	# --- inside the club ------------------------------------------------------------------------
	b.interactions.enter_club()
	b.interactions.lea_talked = true
	await _frames(10)
	check(b.save_game("club"), "save inside the club")
	b.queue_free()
	await _frames(5)
	var c: Node = await _new_game()
	check(c.load_game(), "load club save")
	await _frames(20)
	check(c.interactions.life.flags.get("inside_club", false) and c.club.visible and c.player.global_position.y < -55.0, "back inside the club")
	check(c.club.music.playing and not c.club_audio.playing, "club audio restored")
	check(c.interactions.lea_talked, "Lea conversation remembered")

	# --- missing / corrupt save ---------------------------------------------------------------
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("kaputt")
	f.close()
	check(not c.load_game(), "corrupt save is rejected, game keeps running")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("RESULT save_load_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
