## Integration test (R4): jaywalking heat, police patrol check + fine, platzverweis at the club
## door, shoplifting -> kiosk ban + fired, persistence.
## Run: godot --headless --path . -s res://tests/integration/p001/consequences_it_test.gd
extends SceneTree

const PATH := "user://test_consequences_it.json"
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


func _has_msg(m: Node, id: String) -> bool:
	for msg in m.messages.inbox:
		if msg.id == id:
			return true
	return false


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var m: Node = load("res://src/p001/main.tscn").instantiate()
	m.save_path = PATH
	root.add_child(m)
	await _frames(30)
	var ix: StrayInteractions = m.interactions
	var con: StrayConsequences = m.consequences
	var L: StrayStreetLayout = m.builder.layout
	var life: StrayLifeState = ix.life
	check(m.traffic.police_car() != null, "a police car patrols the Ring")

	# 1. Jaywalking: stand on the carriageway away from traffic lanes' cars for 3 s.
	var road := L.to_en(30.0, -0.9 - L.median_half_width)
	m.player.global_position = StrayStreetLayout.en_to_godot(road.x, road.y, L.road_z(30.0, -1.5) + 0.95)
	await _frames(200)
	check(con.heat >= 5.5 and con.incidents.size() >= 1, "standing on the road raises police attention (%.2f, decays slowly)" % con.heat)
	check("Polizei" in m.ui.status_label.text, "HUD shows the police indicator")

	# 2. Police check: heat 60, police car passes the player -> stop, ID, 60 € fine.
	con._set_heat(60.0)
	var pc: StrayTraffic.Car = m.traffic.police_car()
	var guard := 0
	while not ix.police_check_open and guard < 1800:
		# Stand on the sidewalk next to wherever the police car currently is.
		if pc.active:
			var side := 1.0 if pc.v > 0.0 else -1.0
			var en := L.to_en(clampf(pc.s, L.s_start + 2.0, L.s_end - 2.0), side * (L.kerb_half_width + 1.5))
			m.player.global_position = StrayStreetLayout.en_to_godot(en.x, en.y, L.ground_z_at(en) + 0.95)
		await _frames(1)
		guard += 1
	check(ix.police_check_open and m.traffic.police_hold, "police car stops, check starts")
	await _frames(150)  # braking from ~9 m/s at 6 m/s^2 takes ~1.5 s
	check(pc.speed < 0.5, "police car is standing (%.1f m/s)" % pc.speed)
	var money: int = life.cash_cents + life.account_cents
	ix._on_option(0)  # show ID
	await _frames(5)
	check(life.cash_cents + life.account_cents == money - 6000 and con.police_record == 1, "60 € fine, police record 1")
	check(not m.traffic.police_hold and m.player.input_enabled, "patrol drives on, control back")
	check(_has_msg(m, "mama_police"), "Mama heard about it")

	# 3. Platzverweis: drunk at the next check -> bouncer refuses.
	life.drinks_alcohol = 5
	con._set_heat(40.0)
	con.last_check_minutes = -1e9
	var r := con.resolve_check(true, life, m.clock)
	check(r.outcome == "platzverweis", "drunk -> platzverweis")
	m.player.global_position = ix.points["club_door"] + Vector3(0, 0.95, 0)
	await _frames(15)
	ix.interact()
	check(ix.last_door_result.reason == "platzverweis", "bouncer turns you away (platzverweis)")
	life.drinks_alcohol = 0

	# 4. Shoplifting until caught (hired first, so Erol fires you).
	m.job.apply()
	m.player.global_position = ix.points["kiosk"] + Vector3(0, 0.95, 0)
	await _frames(15)
	var tries := 0
	while not con.kiosk_banned and tries < 8:
		ix.interact()               # open the kiosk menu
		ix._on_shop_choice("__extra")
		ix._on_option(1)            # try to pocket a Kölsch
		tries += 1
		await _frames(3)
	check(con.kiosk_banned, "caught shoplifting after %d tries" % tries)
	check(m.job.fired and _has_msg(m, "erol_theft"), "Erol fires you for stealing")
	ix.interact()
	check(not ix.shop_open and "Hausverbot" in m.ui.message_label.text, "kiosk refuses to serve you")

	# 5. Persistence.
	check(m.save_game("test"), "save")
	var heat_before: float = con.heat
	m.queue_free()
	await _frames(5)
	var m2: Node = load("res://src/p001/main.tscn").instantiate()
	m2.save_path = PATH
	root.add_child(m2)
	await _frames(30)
	check(m2.load_game(), "load")
	check(m2.consequences.kiosk_banned and m2.consequences.police_record >= 2 and absf(m2.consequences.heat - heat_before) < 3.0, "ban, record and heat restored")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("RESULT consequences_it_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
