## Integration test (R9.2, tablet bug "invisible wall to the KIOSK"): the player WALKS (real input,
## real physics) from the west sidewalk across both carriageways and the median to Erol's KIOSK,
## uses it, walks back, and finishes the prologue on foot from the Friesenplatz U-Bahn exit.
## Moving traffic is parked out of the way (its collision is intended; this test is about the
## static street). Run: godot --headless --path . -s res://tests/integration/p001/kiosk_crossing_test.gd
extends SceneTree

var _failed := 0
var _passed := 0
var L: StrayStreetLayout
var last_blocker := ""


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


func _sv(p: StrayPlayer) -> Vector2:
	return L.to_street(Vector2(p.global_position.x, -p.global_position.z))


## Steers the player to a street-frame target (s, v) with the forward input, like a player
## would. Returns true when within `tol` metres; false when stuck for 2 s or after `max_s`.
func _walk_to(p: StrayPlayer, target_sv: Vector2, tol: float = 0.6, max_s: float = 40.0) -> bool:
	Input.action_press("move_forward")
	var best := INF
	var stuck := 0
	var ok := false
	for i in int(max_s * 60.0):
		var here := _sv(p)
		var d_en := L.to_en(target_sv.x, target_sv.y) - Vector2(p.global_position.x, -p.global_position.z)
		if d_en.length() < tol:
			ok = true
			break
		var d := StrayStreetLayout.en_dir_to_godot(d_en)
		p.face_yaw(atan2(-d.x, -d.z))
		await physics_frame
		for k in p.get_slide_collision_count():
			var c := p.get_slide_collision(k)
			if absf(c.get_normal().y) < 0.7 and c.get_collider():
				var cs := L.to_street(Vector2(c.get_position().x, -c.get_position().z))
				last_blocker = "%s at s=%.1f v=%.2f n=%s" % [(c.get_collider() as Node).name, cs.x, cs.y, c.get_normal()]
		if d_en.length() < best - 0.05:
			best = d_en.length()
			stuck = 0
		else:
			stuck += 1
			if stuck > 120:
				print("   stuck at s=%.1f v=%.2f, last blocker: %s" % [here.x, here.y, last_blocker])
				break
	Input.action_release("move_forward")
	await _frames(5)
	return ok


## Street position s where no parked car stands on either side within the player's width.
## Optional evidence screenshot when run with a renderer (env STRAY_SHOT_DIR).
func _shot(file_name: String) -> void:
	var dir := OS.get_environment("STRAY_SHOT_DIR")
	if dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(dir.path_join(file_name))


func _crossing_gap(near_s: float) -> float:
	var best := near_s
	var best_d := INF
	var s := L.s_start + 6.0
	while s < L.s_end - 6.0:
		var free := true
		for car in L.furniture.get("parked_cars", []):
			if absf(float(car["s"]) - s) < float(car["length"]) * 0.5 + 0.9:
				free = false
				break
		if free and absf(s - near_s) < best_d:
			best = s
			best_d = absf(s - near_s)
		s += 0.25
	return best


func _run() -> void:
	var m: Node = load("res://src/p001/main.tscn").instantiate()
	root.add_child(m)
	await _frames(30)
	L = m.builder.layout
	var p: StrayPlayer = m.player
	var ix: StrayInteractions = m.interactions
	for c in m.traffic.cars:
		c.body.collision_layer = 0
	m.traffic.process_mode = Node.PROCESS_MODE_DISABLED
	var kerb := L.kerb_half_width + StrayStreetLayout.KERB_STONE_WIDTH
	var kiosk_sv := L.to_street(Vector2(ix.points["kiosk"].x, -ix.points["kiosk"].z))
	var gap := _crossing_gap(kiosk_sv.x)
	print("   kiosk at s=%.1f v=%.2f, crossing gap at s=%.1f" % [kiosk_sv.x, kiosk_sv.y, gap])

	# 1) West sidewalk -> across the Ring -> east sidewalk.
	var start := L.to_en(gap, -kerb - 2.5)
	p.global_position = StrayStreetLayout.en_to_godot(start.x, start.y, L.ground_z_at(start) + 0.95)
	await _frames(15)
	await _shot("R92_cross_0_west_sidewalk.png")
	check(await _walk_to(p, Vector2(gap, -0.9)), "reaches the median from the west")
	await _shot("R92_cross_1_median.png")
	check(await _walk_to(p, Vector2(gap, kerb + 1.5)), "climbs onto the east sidewalk (s=%.1f v=%.2f)" % [_sv(p).x, _sv(p).y])
	check(p.is_on_floor() and _sv(p).y > kerb and absf(p.global_position.y - 0.9 - L.ground_z_at(Vector2(p.global_position.x, -p.global_position.z))) < 0.25, "standing on the east sidewalk surface (v=%.2f)" % _sv(p).y)
	# 2) Along the east sidewalk to the KIOSK and use it.
	check(await _walk_to(p, kiosk_sv, 0.5), "walks to the KIOSK counter")
	await _frames(10)
	check(ix.current == "kiosk", "KIOSK prompt active")
	ix.interact()
	check(m.ui.shop_panel.visible, "KIOSK menu opens")
	await _shot("R92_cross_2_kiosk_menu.png")
	ix._on_shop_choice("")
	# 3) Back to the west side.
	check(await _walk_to(p, Vector2(gap, kerb + 1.0)), "back to the crossing point")
	check(await _walk_to(p, Vector2(gap, -kerb - 2.0)), "crosses back onto the west sidewalk (v=%.2f)" % _sv(p).y)
	# 3b) Step-up must not climb cars or walls: a parked car and a facade still block.
	var car: Dictionary = {}
	for c in L.furniture.get("parked_cars", []):
		if int(c["side"]) == -1 and float(c["s"]) > 10.0:
			car = c
			break
	var cs := float(car["s"])
	var a := L.to_en(cs, -kerb - 1.2)
	p.global_position = StrayStreetLayout.en_to_godot(a.x, a.y, L.ground_z_at(a) + 0.95)
	await _frames(15)
	var through := await _walk_to(p, Vector2(cs, -4.0), 0.6, 6.0)
	check(not through and _sv(p).y < -9.0 and p.global_position.y < L.ground_z_at(a) + 1.3, "parked car still blocks (stopped at v=%.2f, y=%.2f)" % [_sv(p).y, p.global_position.y])
	var w := L.to_en(30.0, -12.0)
	p.global_position = StrayStreetLayout.en_to_godot(w.x, w.y, L.ground_z_at(w) + 0.95)
	await _frames(15)
	await _walk_to(p, Vector2(30.0, L.facade_v_west - 4.0), 0.6, 6.0)
	check(_sv(p).y > L.facade_v_west - 0.8, "building facade still blocks (v=%.2f, facade %.2f)" % [_sv(p).y, L.facade_v_west])
	check(p.step_count > 0, "kerbs were climbed by stepping (%d steps)" % p.step_count)
	# 4) Prologue on foot: U-Bahn exit at Friesenplatz -> KIOSK -> done.
	m.prologue.start()
	for e in ["metro_entered", "ticket_bought", "rode_friesenplatz", "surface_friesenplatz"]:
		m.prologue.event(e)
	check(m.prologue.current_id() == "kiosk", "prologue at the KIOSK step")
	m.transit.station = "friesenplatz"
	m.metro_ix.leave_station()
	await _frames(20)
	var exit_sv := _sv(p)
	# Along the west sidewalk outside the pedestrian lanes (v -11.9 / -13.1), then to the kerb.
	check(await _walk_to(p, Vector2(exit_sv.x, -15.0), 0.6, 20.0) and await _walk_to(p, Vector2(gap, -15.0), 0.6, 60.0)
		and await _walk_to(p, Vector2(gap, -kerb - 1.0), 0.6, 20.0), "walks from the U-Bahn exit (s=%.1f) to the crossing" % exit_sv.x)
	check(await _walk_to(p, Vector2(gap, kerb + 1.5)), "crosses the Ring")
	check(await _walk_to(p, kiosk_sv, 0.8), "reaches the KIOSK")
	await _frames(15)
	check(m.prologue.is_done(), "prologue finished at Erol's KIOSK")
	await _frames(30)
	await _shot("R92_cross_3_prologue_done.png")
	print("RESULT kiosk_crossing_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
