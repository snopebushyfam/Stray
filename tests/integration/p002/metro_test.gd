## Integration test (R5): Friesenplatz U-Bahn -> ticket -> ride to Dom/Hbf -> Hbf area on real
## ground -> fare dodging back with a check -> save/load at the Hbf.
## Run: godot --headless --path . -s res://tests/integration/p002/metro_test.gd
extends SceneTree

const PATH := "user://test_metro_it.json"
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


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var m: Node = await _new_game()
	var ix: StrayInteractions = m.interactions
	var life: StrayLifeState = ix.life
	var t: StrayTransit = m.transit
	check(m.area.stats.area and m.area.stats.buildings > 50, "Hbf area built (%d LoD2 buildings)" % m.area.stats.buildings)
	check(not m.area.visible and m.region == "p001", "starts on the Ringe, Hbf hidden")

	# Down at Friesenplatz.
	await _go(m, ix.points["ubahn_friesenplatz"])
	check(ix.current == "ubahn_friesenplatz" and "U-Bahn Friesenplatz" in m.ui.prompt_label.text, "entrance prompt on the Ring")
	ix.interact()
	await _frames(20)
	check(life.flags.get("inside_metro", false) and m.region == "metro" and m.metro.visible, "on the platform")
	check(m.player.is_on_floor() and m.player.global_position.y < -95.0, "standing on the platform floor")

	# Ticket.
	var cash0 := life.cash_cents
	await _go(m, ix.points["metro_ticket"])
	check(ix.current == "metro_ticket", "ticket machine prompt")
	ix.interact()
	check(m.ui.shop_panel.visible, "machine question shown")
	ix._on_option(0)
	check(t.has_ticket and life.cash_cents == cash0 - t.ticket_price(), "ticket bought: %s" % StrayLifeState.euro(life.cash_cents))
	check(not m.ui.shop_panel.visible and m.player.input_enabled, "panel closed, control back")

	# Ride to Dom/Hbf.
	await _go(m, ix.points["metro_board"])
	var min0: float = m.clock.minutes
	check(ix.current == "metro_board" and "Dom/Hbf" in m.ui.prompt_label.text, "boarding prompt names Dom/Hbf")
	ix.interact()
	ix._on_option(0)
	var dmin: float = m.clock.minutes - min0
	await _frames(10)
	check(t.station == "dom_hbf" and not t.has_ticket, "arrived at Dom/Hbf, ticket used")
	check(absf(dmin - float(t.ride_minutes())) < 0.05, "clock +%d min (%.2f)" % [t.ride_minutes(), dmin])
	check(m.metro_ix.last_ride.fined_cents == 0, "no fine with a ticket")

	# Up into the Hbf area.
	await _go(m, ix.points["metro_exit"])
	check(ix.current == "metro_exit", "exit prompt")
	ix.interact()
	await _frames(40)
	var a: StrayAreaLayout = m.area.area
	var pp: Vector3 = m.player.global_position
	var pen := Vector2(pp.x, -pp.z)
	check(m.region == "p002" and m.area.visible and not m.metro.visible, "Hbf region visible")
	check(m.player.is_on_floor(), "standing on the DGM1 ground at the Hbf")
	var feet: float = pp.y - 0.9
	check(absf(feet - a.ground_z_at(pen)) < 0.2, "feet on the real ground (%.2f vs %.2f)" % [feet, a.ground_z_at(pen)])
	check(pen.distance_to(a.hbf_en) < 120.0, "near the Hauptbahnhof (%.0f m)" % pen.distance_to(a.hbf_en))
	# Walk 2 s towards the Dom: stays on the ground, does not fall through.
	Input.action_press("move_forward")
	await _frames(120)
	Input.action_release("move_forward")
	await _frames(20)
	pp = m.player.global_position
	pen = Vector2(pp.x, -pp.z)
	check(m.player.is_on_floor() and absf(pp.y - 0.9 - a.ground_z_at(pen)) < 0.3, "walked on the plaza (%.1f m moved)" % pen.distance_to(a.spawn_en))
	check("hbf_door" in ix.points, "Hbf door point")

	# Save at the Hbf, load into a fresh game.
	check(m.save_game("test"), "saved at the Hbf")
	var saved_pos: Vector3 = m.player.global_position
	m.queue_free()
	await _frames(5)
	var m2: Node = await _new_game()
	check(m2.load_game(), "loaded")
	await _frames(20)
	check(m2.region == "p002" and m2.area.visible and m2.transit.station == "dom_hbf", "back at the Hbf after loading")
	check(m2.player.global_position.distance_to(saved_pos) < 1.0, "player position restored")

	# Fare dodging back, forced check.
	var ix2: StrayInteractions = m2.interactions
	var t2: StrayTransit = m2.transit
	t2.cfg["fare_dodging"]["check_chance"] = 1.0
	await _go(m2, ix2.points["ubahn_dom_hbf"])
	check(ix2.current == "ubahn_dom_hbf", "Dom/Hbf entrance prompt")
	ix2.interact()
	await _frames(10)
	var cash1 := ix2.life.cash_cents
	await _go(m2, ix2.points["metro_board"])
	ix2.interact()
	check("ohne Fahrkarte" in m2.ui.options_text, "warned: no ticket")
	ix2._on_option(0)
	var r: Dictionary = m2.metro_ix.last_ride
	check(r.checked and r.fined_cents == int(t2.cfg["fare_dodging"]["fine_cents"]), "checked without ticket: fined")
	check((r.paid == "cash" and ix2.life.cash_cents == cash1 - r.fined_cents) or r.paid != "cash", "fine booked (%s)" % r.paid)
	check(t2.station == "friesenplatz", "back at Friesenplatz")
	await _go(m2, ix2.points["metro_exit"])
	ix2.interact()
	await _frames(40)
	var sv: Vector2 = m2.builder.layout.to_street(Vector2(m2.player.global_position.x, -m2.player.global_position.z))
	check(m2.region == "p001" and m2.player.is_on_floor() and sv.y < -9.0 and sv.x > 90.0, "up on the Ring west sidewalk (s=%.1f v=%.1f)" % [sv.x, sv.y])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("RESULT metro_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
