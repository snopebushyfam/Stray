## Integration test: load the real P001 scene and drive the player through input actions.
## Checks spawn on ground, walking, stepping off the kerb, facade collision and the end wall.
## Run: godot --headless --path . -s res://tests/integration/p001/walk_test.gd
extends SceneTree

var _failed := 0
var _passed := 0
var main: Node
var player: StrayPlayer
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


func _hold(action: String, seconds: float) -> void:
	Input.action_press(action)
	await _frames(int(seconds * 60.0))
	Input.action_release(action)
	await _frames(20)


func _sv() -> Vector2:
	var p := player.global_position
	return L.to_street(Vector2(p.x, -p.z))


func _place(s: float, v: float, face_dir_en: Vector2) -> void:
	var en := L.to_en(s, v)
	player.global_position = StrayStreetLayout.en_to_godot(en.x, en.y, L.ground_z_at(en) + 0.95)
	player.velocity = Vector3.ZERO
	var d := StrayStreetLayout.en_dir_to_godot(face_dir_en)
	player.face_yaw(atan2(-d.x, -d.z))
	await _frames(30)


## A street position (s) on `side` with no parked car within 4 m, or -1.
func _free_parking_s(side: int) -> float:
	var s := 10.0
	while s < 90.0:
		var clear := true
		for car in L.furniture.get("parked_cars", []):
			if int(car["side"]) == side and absf(float(car["s"]) - s) < float(car["length"]) * 0.5 + 1.5:
				clear = false
				break
		if clear:
			return s
		s += 0.5
	return -1.0


func _first_car(side: int) -> Dictionary:
	for car in L.furniture.get("parked_cars", []):
		if int(car["side"]) == side and float(car["s"]) > 0.0:
			return car
	return {}


func _run() -> void:
	main = load("res://src/p001/main.tscn").instantiate()
	root.add_child(main)
	await _frames(40)
	player = main.player
	L = main.builder.layout
	var half := 0.9

	# 1. Spawn: standing on the sidewalk, not below it.
	var g0 := L.ground_z_at(L.spawn_en)
	check(player.is_on_floor(), "spawned player is on the floor")
	check(absf((player.global_position.y - half) - g0) < 0.08, "capsule bottom within 8 cm of sidewalk (%.3f vs %.3f)" % [player.global_position.y - half, g0])

	# 2. Walk forward (along the street, towards Friesenplatz) for 3 s at walking speed.
	var s_before := _sv().x
	check(player.anim_state == "idle", "idle animation when standing (%s)" % player.anim_state)
	Input.action_press("move_forward")
	await _frames(120)
	check(player.anim_state == "walk", "walk animation while walking (%s)" % player.anim_state)
	await _frames(60)
	Input.action_release("move_forward")
	await _frames(40)
	check(player.anim_state == "idle", "back to idle after stopping (%s)" % player.anim_state)
	var walked := _sv().x - s_before
	var expected: float = float(player.cfg.get("walk_speed", 1.35)) * 3.0
	check(walked > expected * 0.75 and walked < expected * 1.3, "walked %.2f m in 3 s (expected ~%.2f)" % [walked, expected])
	check(player.is_on_floor(), "still on the floor after walking")

	# 3. Step off the kerb onto the road (move right = towards the street centre, east),
	#    at a spot with no parked car on the west side.
	var free_s := _free_parking_s(-1)
	check(free_s > 0.0, "found a kerb section without a parked car (s=%.1f)" % free_s)
	await _place(free_s, -L.kerb_half_width - 1.0, L.axis_en())
	await _hold("move_right", 2.0)
	var sv := _sv()
	check(sv.y > -L.kerb_half_width, "crossed the kerb onto the carriageway (v=%.2f)" % sv.y)
	check(absf((player.global_position.y - half) - L.ground_z_at(L.to_en(sv.x, sv.y))) < 0.1, "standing on the road surface")

	# 3b. Parked cars block: walk from the sidewalk into the first west-side car.
	var car := _first_car(-1)
	if not car.is_empty():
		var car_s: float = car["s"]
		await _place(car_s, -L.kerb_half_width - 1.0, L.axis_en())
		await _hold("move_right", 2.0)
		check(_sv().y < -L.kerb_half_width + 0.6, "parked car blocks the way (v=%.2f)" % _sv().y)

	# 4. Facade collision: run west into the NACHTFLUG building for 3 s.
	var club_sv := L.to_street(Vector2(L.club["en"][0], L.club["en"][1]))
	await _place(club_sv.x + 6.0, club_sv.y + 3.0, L.axis_en())
	Input.action_press("run")
	await _hold("move_left", 3.0)
	Input.action_release("run")
	check(_sv().y > club_sv.y - 0.2, "blocked by the facade (v=%.2f, facade %.2f)" % [_sv().y, club_sv.y])

	# 5. End wall: run north past the end of the prototype.
	await _place(L.s_end - 6.0, -12.0, L.axis_en())
	Input.action_press("run")
	await _hold("move_forward", 4.0)
	Input.action_release("run")
	check(_sv().x < L.s_end, "end wall holds (s=%.2f < %.2f)" % [_sv().x, L.s_end])
	check(player.global_position.y > L.ground_z - 0.5, "never fell through the world")

	print("RESULT walk_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
