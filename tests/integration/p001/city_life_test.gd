## Integration test (R13 city life) in the real P001 scene:
## - every standing spot is on the sidewalk, free of world geometry (posts, fridge, walls), clear of
##   the queue/bouncer and >= 1.5 m from the player's interaction points and the spawn;
## - one minute of Saturday night with the player at the spawn: people walk, stand and talk, a KIOSK
##   customer comes, nobody blocks the KIOSK counter / club door / queue end, nobody overlaps, feet
##   stay on the ground, the queue stays where the club mechanic expects it;
## - KIOSK menu and the full queue -> bouncer -> admitted flow still work after that minute;
## - the player can still walk the sidewalk;
## - time of day: day profile (no queue, more traffic), back to night; save/load keeps the profile;
##   region change pauses and resumes the street.
## Run: godot --headless --path . -s res://tests/integration/p001/city_life_test.gd
extends SceneTree

const PATH := "user://test_city_life.json"
var _failed := 0
var _passed := 0
var main: Node
var ix: StrayInteractions
var L: StrayStreetLayout


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


func _go(p: Vector3) -> void:
	main.player.global_position = p + Vector3(0, 0.95, 0)
	main.player.velocity = Vector3.ZERO
	await _frames(20)


func _press_interact() -> void:
	Input.action_press("interact")
	var ev := InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(3)
	Input.action_release("interact")
	await _frames(3)


func _gp(sv: Vector2) -> Vector3:
	var en := L.to_en(sv.x, sv.y)
	return StrayStreetLayout.en_to_godot(en.x, en.y, L.ground_z_at(en))


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _set_clock(day: int, hhmm: String) -> void:
	main.clock.from_dict({"minutes": day * 1440.0 + StrayGameClock.parse_hhmm(hhmm)})
	await _frames(150)  # profile check runs every 2 s


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	main = load("res://src/p001/main.tscn").instantiate()
	main.save_path = PATH
	root.add_child(main)
	await _frames(30)
	ix = main.interactions
	L = main.builder.layout
	var peds: StrayPedestrians = main.pedestrians
	var life := peds.life
	await _set_clock(0, "23:10")
	check(life.profile_name == "night", "Saturday 23:10 -> night profile (%s)" % life.profile_name)

	# --- spots ------------------------------------------------------------------------------
	var key_points: Array[Vector3] = []
	for k in ix.points:
		var p: Vector3 = ix.points[k]
		if absf(p.y - _gp(L.to_street(Vector2(p.x, -p.z))).y) < 1.0 and L.is_on_sidewalk(Vector2(p.x, -p.z)):
			key_points.append(p)
	key_points.append(L.spawn_position(0.0))
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.6
	var bad: Array[String] = []
	var static_npcs: Array[Vector3] = []
	for q in peds.queue:
		static_npcs.append(q.global_position)
	static_npcs.append(ix.get_node("Bouncer").global_position)
	for sid in life.spots:
		var sv: Vector2 = life.spots[sid].pos
		var gp := _gp(sv)
		if not L.is_on_sidewalk(L.to_en(sv.x, sv.y)):
			bad.append(sid + ":off_sidewalk")
		var qp := PhysicsShapeQueryParameters3D.new()
		qp.shape = cap
		qp.transform = Transform3D(Basis(), gp + Vector3(0, 0.95, 0))
		qp.collision_mask = 1
		if not space.intersect_shape(qp, 1).is_empty():
			bad.append(sid + ":geometry")
		for p in key_points:
			if _flat(gp, p) < 1.5:
				bad.append(sid + ":interaction_point")
		for p in static_npcs:
			if _flat(gp, p) < 0.9:
				bad.append(sid + ":queue_or_bouncer")
	check(bad.is_empty(), "%d standing spots: on the sidewalk, free, clear of interaction points %s" % [life.spots.size(), bad])

	# --- one minute of Saturday night, player at the spawn -----------------------------------
	main.player.global_position = L.spawn_position(0.9)
	var queue_pos: Array[Vector3] = []
	for q in peds.queue:
		queue_pos.append(q.global_position)
	var blocked_points := 0
	var overlap := 0
	var floating := 0
	var talking := 0
	var walking := 0
	var kiosk_customer := false
	var states_seen := {}
	for t in 120:  # 60 s, sampled every 0.5 s
		await _frames(30)
		for w in peds.walkers:
			if w.hidden:
				continue
			var a := w.agent
			states_seen[StrayAmbientLife.STATE_NAMES[a.state]] = true
			var gp: Vector3 = w.root.global_position
			for k in ["kiosk", "club_door", "queue_end"]:
				if _flat(gp, ix.points[k]) < 0.9:
					blocked_points += 1
			if absf(gp.y - L.ground_z_at(Vector2(gp.x, -gp.z))) > 0.12:
				floating += 1
			for o in peds.walkers:
				if o != w and not o.hidden and _flat(gp, o.root.global_position) < 0.45:
					overlap += 1
			if a.spot.begins_with("kiosk_counter") and a.state == StrayAmbientLife.State.WAITING:
				kiosk_customer = true
		var c := life.census()
		talking = maxi(talking, int(c.get("TALKING", 0)))
		walking = maxi(walking, int(c.get("WALKING", 0)) + int(c.get("APPROACHING", 0)) + int(c.get("LEAVING", 0)))
	check(walking >= 3 and talking >= 2, "people walk (max %d) and talk (max %d) at the same time" % [walking, talking])
	check(states_seen.size() >= 5, "several activities within one minute %s" % [states_seen.keys()])
	check(kiosk_customer, "a KIOSK customer ordered within the minute")
	check(blocked_points == 0, "nobody stands on the KIOSK counter, club door or queue end (%d samples)" % blocked_points)
	check(overlap == 0, "people never overlap (%d samples)" % overlap)
	check(floating == 0, "feet on the ground (%d samples off)" % floating)
	var queue_ok := true
	for i in peds.queue.size():
		if peds.queue[i].global_position.distance_to(queue_pos[i]) > 0.01:
			queue_ok = false
	check(queue_ok and peds.queue.size() == 5, "the club queue stays in place for the door mechanic")

	# --- the player can still walk the sidewalk ----------------------------------------------
	main.player.global_position = L.spawn_position(0.9)
	main.player.face_yaw(L.spawn_yaw())
	var p0: Vector3 = main.player.global_position
	Input.action_press("move_forward")
	await _frames(360)
	Input.action_release("move_forward")
	check(_flat(main.player.global_position, p0) > 5.0, "player walks freely along the sidewalk (%.1f m in 6 s)" % _flat(main.player.global_position, p0))

	# --- KIOSK and club still work -----------------------------------------------------------
	await _go(ix.points["kiosk"])
	check(ix.current == "kiosk", "KIOSK counter reachable (prompt)")
	await _press_interact()
	check(ix.shop_open, "KIOSK menu opens")
	ix.close_all_panels()
	await _frames(5)
	await _go(ix.points["queue_end"])
	await _frames(int((float(ix.econ["club"]["queue_wait_seconds"]) + 1.0) * 60))
	check(ix.queued_seconds >= float(ix.econ["club"]["queue_wait_seconds"]), "queueing at the end still counts (%.1f s)" % ix.queued_seconds)
	await _go(ix.points["club_door"])
	await _press_interact()
	check(ix.last_door_result.get("admitted", false), "bouncer admits after queueing (%s)" % ix.last_door_result.get("reason"))
	await _frames(150)  # the bouncer lets you in after 1.5 s
	ix.leave_club()
	await _frames(30)

	# --- time of day -------------------------------------------------------------------------
	# Regression: the queue vanished in front of the camera (spawn, 42 m, looking at the club).
	main.player.global_position = L.spawn_position(0.9)
	main.player.face_yaw(L.spawn_yaw())
	await _frames(30)
	await _set_clock(0, "14:00")
	var seen_queue := 0
	for q in peds.queue:
		if q.visible:
			seen_queue += 1
	check(seen_queue == 5, "queue in view does not vanish on a clock jump (%d visible)" % seen_queue)
	await _set_clock(0, "23:10")
	# The queue only changes while its spot is not on screen: player at the south end, facing away.
	var south := L.to_en(L.s_start + 6.0, -13.1)
	main.player.global_position = StrayStreetLayout.en_to_godot(south.x, south.y, L.ground_z_at(south) + 0.95)
	var away := StrayStreetLayout.en_dir_to_godot(-L.axis_en())
	main.player.face_yaw(atan2(-away.x, -away.z))
	await _set_clock(0, "14:00")
	await _frames(30)
	var visible_queue := 0
	for q in peds.queue:
		if q.visible:
			visible_queue += 1
	check(life.profile_name == "day" and is_equal_approx(main.traffic.active_share, 1.0), "Saturday 14:00 -> day profile, full traffic (%s)" % life.profile_name)
	check(visible_queue == 0, "no club queue in the afternoon (%d visible)" % visible_queue)
	await _set_clock(1, "09:00")
	check(life.profile_name == "sunday_morning" and main.traffic.active_share < 0.9, "Sunday 09:00 -> quiet Sunday morning (%s)" % life.profile_name)
	await _set_clock(0, "14:00")
	check(main.save_game("test"), "saved in the afternoon")
	main.clock.from_dict({"minutes": 23 * 60.0 + 10.0})  # no frames in between: no autosave
	check(main.load_game(), "loaded")
	await _frames(150)
	check(life.profile_name == "day", "profile follows the loaded clock (%s at %s)" % [life.profile_name, main.clock.hhmm()])
	await _set_clock(0, "23:10")
	visible_queue = 0
	for q in peds.queue:
		if q.visible:
			visible_queue += 1
	check(life.profile_name == "night" and visible_queue == 5, "night again: queue back (%d)" % visible_queue)

	# --- region change -----------------------------------------------------------------------
	main.set_region("p002")
	var s0: float = peds.walkers[3].agent.s
	await _frames(60)
	check(peds.process_mode == Node.PROCESS_MODE_DISABLED and is_equal_approx(s0, peds.walkers[3].agent.s), "street paused in another region")
	main.set_region("p001")
	await _frames(120)
	var moving := 0
	for w in peds.walkers:
		if w.agent.cur_speed > 0.1:
			moving += 1
	check(moving > 0, "street resumes after returning (%d walking)" % moving)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("RESULT city_life_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
