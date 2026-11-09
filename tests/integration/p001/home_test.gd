## Integration test (R2): flat, sleep -> next day, rent standing order, eviction, save in the flat.
## Run: godot --headless --path . -s res://tests/integration/p001/home_test.gd
extends SceneTree

const PATH := "user://test_home_it.json"
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


## Advances the game clock by exactly one day (fires day_changed once).
func _next_day(m: Node) -> void:
	m.clock.from_dict({"minutes": m.clock.minutes + 1440.0})


func _go(m: Node, p: Vector3) -> void:
	m.player.global_position = p + Vector3(0, 0.95, 0)
	m.player.velocity = Vector3.ZERO
	await _frames(15)


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var m: Node = await _new_game()
	var ix: StrayInteractions = m.interactions
	var life: StrayLifeState = ix.life
	check(ix.points.has("home_door"), "street door from a real OSM entrance")
	check(m.clock.date_text() == "Sa 14.11.", "starts Saturday 14.11.")

	# Go home.
	await _go(m, ix.points["home_door"])
	check(ix.current == "home_door" and "Nach Hause" in m.ui.prompt_label.text, "home door prompt")
	ix.interact()
	await _frames(20)
	check(life.flags.get("inside_home", false) and m.home.visible and m.player.global_position.y < -95.0, "inside the flat")
	check(m.player.is_on_floor(), "standing on the flat's floor")

	# No "Guten Morgen" at night: pass midnight without sleeping.
	var night_clock: float = m.clock.minutes
	m.clock.from_dict({"minutes": night_clock + 60.0})  # 00:10
	var early := false
	for msg in m.messages.inbox:
		if msg.id == "mama_morning":
			early = true
	check(not early, "no morning message at %s" % m.clock.hhmm())
	m.clock.from_dict({"minutes": night_clock})
	# Sleep.
	life.drinks_alcohol = 2
	m.phone.battery = 20.0
	await _go(m, ix.points["home_bed"])
	check(ix.current == "home_bed", "bed prompt")
	ix.interact()
	check(m.ui.shop_panel.visible, "sleep question shown")
	ix._on_option(0)
	await _frames(10)
	check(m.clock.date_text() == "So 15.11." and m.clock.hhmm() == "10:00", "woke up Sunday 10:00 (%s %s)" % [m.clock.date_text(), m.clock.hhmm()])
	check(m.builder.day_mode, "daylight in the morning")
	check(life.drinks_alcohol == 0 and m.phone.battery >= 99.0, "sober and phone charged")
	check(StraySaveGame.exists(PATH), "autosaved after sleeping")
	var mama := false
	for msg in m.messages.inbox:
		if msg.id == "mama_morning":
			mama = true
	check(mama, "morning message from Mama")
	check("So 15.11." in m.ui.status_label.text, "HUD shows the new date")

	# Save + load inside the flat.
	check(m.save_game("test"), "save in the flat")
	m.queue_free()
	await _frames(5)
	var m2: Node = await _new_game()
	check(m2.load_game(), "load")
	await _frames(20)
	check(m2.home.visible and m2.interactions.life.flags.get("inside_home", false) and m2.player.global_position.y < -95.0, "still in the flat after loading")
	check(m2.clock.date_text() == "So 15.11." and m2.rent.last_processed_day == 1, "date + rent state restored (no double processing)")

	# Rent day with enough money: paid by standing order.
	var ix2: StrayInteractions = m2.interactions
	ix2.life.credit_account(40000, "Test-Gutschrift")
	var before: int = ix2.life.account_cents
	while m2.clock.date_text() != "Di 01.12.":
		_next_day(m2)
	check(ix2.life.account_cents == before - 45000 and m2.rent.payments == 1, "rent 450 € debited on Di 01.12.")
	var paid := false
	for msg in m2.messages.inbox:
		if msg.id == "rent_paid":
			paid = true
	check(paid, "landlord confirms the payment")

	# Next month without money: overdue, then evicted and locked out.
	ix2.life.debit_account(ix2.life.account_cents, "Test: alles weg")
	while m2.clock.date_text() != "Mo 04.01.":
		_next_day(m2)
	check(m2.rent.evicted, "evicted after the grace period (overdue %d days)" % m2.rent.overdue_days)
	check(not ix2.life.flags.get("inside_home", false) and m2.player.global_position.y > -5.0, "put out on the street")
	await _frames(40)
	var L: StrayStreetLayout = m2.builder.layout
	var cam: Vector3 = m2.player.camera.global_position
	var cam_v := L.to_street(Vector2(cam.x, -cam.z)).y
	check(cam_v < L.facade_v_east - 0.3, "camera stays on the street side of the facade (v=%.2f, facade %.2f)" % [cam_v, L.facade_v_east])
	await _go(m2, ix2.points["home_door"])
	ix2.interact()
	await _frames(5)
	check(not ix2.life.flags.get("inside_home", false) and "ausgetauscht" in m2.ui.message_label.text, "locked out: key no longer fits")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("RESULT home_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
