## R13 traffic evidence: waits until the taxi stands at the kerb and photographs it (with the
## cars passing / braking behind it), then a car braking for the player in its lane.
##   xvfb-run godot --path . -s res://tools/perf/r13_traffic_shot.gd -- <out_dir>
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _gp(L: StrayStreetLayout, s: float, v: float, h: float) -> Vector3:
	var en := L.to_en(s, v)
	return StrayStreetLayout.en_to_godot(en.x, en.y, L.ground_z_at(en) + h)


func _shot(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("TRAFFIC_SHOT ", path)


func _run() -> void:
	var dir: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(dir)
	var m: Node = load("res://src/p001/main.tscn").instantiate()
	root.add_child(m)
	for i in 30:
		await physics_frame
	if m.menu:
		m.menu.hide_menu()
	paused = false
	m.clock.from_dict({"minutes": 23 * 60.0 + 10.0})
	var L: StrayStreetLayout = m.builder.layout
	m.player.global_position = L.spawn_position(0.9)
	var cam := Camera3D.new()
	m.add_child(cam)
	cam.global_position = _gp(L, 22.0, 11.2, 2.2)
	cam.look_at(_gp(L, 33.0, 6.5, 0.8), Vector3.UP)
	cam.make_current()
	var taxi: StrayTraffic.Car
	for c in m.traffic.cars:
		if c.is_taxi:
			taxi = c
	var got := false
	for i in 60 * 240:  # up to 4 min of game physics time
		await physics_frame
		if taxi and taxi.taxi == "stop" and taxi.stop_timer < 4.0 and not got:
			got = true
			print("TRAFFIC taxi stopped at s=%.1f v=%.2f brake=%s" % [taxi.s, taxi.v, taxi.brake.visible])
			await _shot(dir.path_join("taxi_stop.png"))
		if got and taxi.taxi == "out":
			await _shot(dir.path_join("taxi_pulls_out.png"))
			break
	# a car braking for the player standing in its lane (brake lights)
	var p_s := 40.0
	m.player.global_position = _gp(L, p_s, 5.6, 0.95)
	cam.global_position = _gp(L, 24.0, 3.9, 1.6)  # behind the approaching car (its rear lights)
	cam.look_at(_gp(L, 37.0, 5.6, 0.8), Vector3.UP)
	for i in 60 * 30:
		await physics_frame
		for c in m.traffic.cars:
			if c.active and absf(c.lane_v - 5.6) < 0.5 and c.braking and (p_s - c.s) > 3.0 and (p_s - c.s) < 12.0 and c.speed < 2.0:
				print("TRAFFIC braking car s=%.1f speed=%.2f brake=%s" % [c.s, c.speed, c.brake.visible])
				await _shot(dir.path_join("brake_lights.png"))
				quit(0)
				return
	quit(0)
