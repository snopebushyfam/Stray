## R13 city-life evidence + load probe. Works on any commit (before/after comparison).
##   xvfb-run godot --path . -s res://tools/perf/r13_city_probe.gd -- shots <out_dir> [HH:MM]
##   xvfb-run godot --path . -s res://tools/perf/r13_city_probe.gd -- perf [HH:MM]
##   godot --headless --path . -s res://tools/perf/r13_city_probe.gd -- cpu [HH:MM]
##   xvfb-run godot --path . -s res://tools/perf/r13_city_probe.gd -- film <out_dir> [HH:MM] [seconds]
## film:  the same three cameras, 2 frames per game second for one session (-> mp4 with ffmpeg).
## shots: one running session, three fixed observer cameras (A Ring sidewalk, B NACHTFLUG, C KIOSK);
##        stills after 0/20/40/60 s of game physics time and a film strip (one frame per 3 s per spot).
##        The player stands at the spawn (Hohenzollernring) the whole time.
## cpu:   headless (no rendering noise): CPU time of pedestrians and traffic (logic + animation)
##        as process+physics time with the node enabled minus disabled, 4 alternations x 300 frames.
## perf:  the player camera looks at A, B and C; per spot the Performance monitors are averaged and
##        the CPU cost of the pedestrians / traffic is measured as the difference of the frame's
##        process+physics time with the node enabled vs disabled. Cloud renderer (llvmpipe): load
##        numbers only, never device FPS.
extends SceneTree

const VIEWS := {
	# street frame: [s, v, height] of the camera, [s, v, height] of the look target
	"A_ring": [[14.0, -11.2, 2.3], [34.0, -14.0, 1.0]],
	"B_nachtflug": [[53.0, -11.0, 2.5], [62.0, -15.4, 1.0]],
	"C_kiosk": [[39.0, 11.4, 2.4], [49.0, 17.4, 1.0]],
}
var m: Node
var L: StrayStreetLayout
var cams := {}


func _initialize() -> void:
	_run.call_deferred()


func _physics(n: int) -> void:
	for i in n:
		await physics_frame


func _gp(s: float, v: float, h: float) -> Vector3:
	var en := L.to_en(s, v)
	return StrayStreetLayout.en_to_godot(en.x, en.y, L.ground_z_at(en) + h)


func _make_cams() -> void:
	for id in VIEWS:
		var c := Camera3D.new()
		c.fov = 62.0
		m.add_child(c)
		var a: Array = VIEWS[id][0]
		var b: Array = VIEWS[id][1]
		c.global_position = _gp(a[0], a[1], a[2])
		c.look_at(_gp(b[0], b[1], b[2]), Vector3.UP)
		cams[id] = c


## Game paused while an observer camera is current: the street logic (which lets people appear or
## disappear only where the active camera does not look) must only ever see the player's camera.
func _shot(id: String, path: String) -> void:
	paused = true
	(cams[id] as Camera3D).make_current()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	m.player.camera.make_current()
	paused = false


func _start(time: String) -> void:
	m = load("res://src/p001/main.tscn").instantiate()
	root.add_child(m)
	await _physics(30)
	if m.menu:
		m.menu.hide_menu()
	paused = false
	# absolute: "[sa|so] HH:MM" (default Saturday = day 0 of the game)
	var day := 1 if time.begins_with("so ") else 0
	m.clock.from_dict({"minutes": day * 1440.0 + StrayGameClock.parse_hhmm(time.trim_prefix("so ").trim_prefix("sa "))})
	L = m.builder.layout
	m.player.global_position = L.spawn_position(0.9)
	m.player.face_yaw(L.spawn_yaw())
	await _physics(60)


func _shots(dir: String, time: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await _start(time)
	_make_cams()
	var t := 0
	for k in 21:  # 0..60 s, every 3 s
		for id in cams:
			if t in [0, 20, 40, 60] or true:
				await _shot(id, dir.path_join("%s_t%02d.png" % [id, t]))
		print("SHOTS t=%d s clock=%s" % [t, m.clock.hhmm()])
		m.player.camera.make_current()
		await _physics(180)
		t += 3
	m.player.camera.make_current()


func _film(dir: String, time: String, seconds: int) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await _start(time)
	_make_cams()
	for k in seconds * 2:
		for id in cams:
			await _shot(id, dir.path_join("%s_%04d.png" % [id, k]))
		# between shots the game runs with the player's own camera (what the street logic must
		# respect when it lets people appear/disappear) - not with the last observer camera
		m.player.camera.make_current()
		await _physics(30)
	print("FILM frames=%d clock=%s" % [seconds * 2, m.clock.hhmm()])


func _avg(tag: String) -> Dictionary:
	var keys := {"draw_calls": Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME, "primitives": Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME,
		"objects": Performance.RENDER_TOTAL_OBJECTS_IN_FRAME, "t_process": Performance.TIME_PROCESS, "t_physics": Performance.TIME_PHYSICS_PROCESS}
	var acc := {}
	for k in keys:
		acc[k] = 0.0
	await _physics(20)
	var n := 60
	for i in n:
		await process_frame
		for k in keys:
			acc[k] += Performance.get_monitor(keys[k])
	for k in acc:
		acc[k] /= n
	return acc


func _perf(time: String) -> void:
	await _start(time)
	var pl: StrayPlayer = m.player
	for id in VIEWS:
		var a: Array = VIEWS[id][0]
		var b: Array = VIEWS[id][1]
		pl.global_position = _gp(a[0], a[1], 0.95)
		var d := _gp(b[0], b[1], 0.0) - _gp(a[0], a[1], 0.0)
		pl.face_yaw(atan2(-d.x, -d.z))
		var on := await _avg(id)
		var peds: Node = m.pedestrians
		peds.process_mode = Node.PROCESS_MODE_DISABLED
		var off := await _avg(id)
		peds.process_mode = Node.PROCESS_MODE_INHERIT
		m.traffic.process_mode = Node.PROCESS_MODE_DISABLED
		var toff := await _avg(id)
		m.traffic.process_mode = Node.PROCESS_MODE_INHERIT
		var npc_visible := 0
		for n in peds.get_children():
			if n is Node3D and (n as Node3D).visible and not n is CollisionObject3D:
				npc_visible += 1
		var ped_ms: float = (on.t_process + on.t_physics - off.t_process - off.t_physics) * 1000.0
		var traf_ms: float = (on.t_process + on.t_physics - toff.t_process - toff.t_physics) * 1000.0
		print("PERF %-12s draw_calls=%4d primitives=%7d objects=%4d frame_cpu_ms=%.2f peds_ms=%.2f traffic_ms=%.2f npc_nodes=%d mem_static_mb=%.1f" % [
			id, int(on.draw_calls), int(on.primitives), int(on.objects), (on.t_process + on.t_physics) * 1000.0, ped_ms, traf_ms,
			npc_visible, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])


func _cpu_ms(n: int) -> float:
	var acc := 0.0
	for i in n:
		await physics_frame
		acc += Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	return acc / n * 1000.0


func _cpu(time: String) -> void:
	await _start(time)
	for node_name in ["pedestrians", "traffic"]:
		var node: Node = m.get(node_name)
		var on := 0.0
		var off := 0.0
		for k in 4:
			node.process_mode = Node.PROCESS_MODE_INHERIT
			await _physics(30)
			on += await _cpu_ms(300)
			node.process_mode = Node.PROCESS_MODE_DISABLED
			await _physics(30)
			off += await _cpu_ms(300)
		node.process_mode = Node.PROCESS_MODE_INHERIT
		print("CPU %-12s on=%.3f ms off=%.3f ms cost=%.3f ms/frame" % [node_name, on / 4.0, off / 4.0, (on - off) / 4.0])
	var active := 0
	if m.pedestrians.get("walkers") != null:
		for w in m.pedestrians.walkers:
			if w.root.visible:
				active += 1
	print("CPU npc walkers_visible=%d queue=%d mem_static_mb=%.1f objects=%d" % [active, m.pedestrians.queue.size(),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.OBJECT_COUNT)])


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "perf"
	if mode == "film":
		await _film(args[1], args[2] if args.size() > 2 else "23:10", int(args[3]) if args.size() > 3 else 40)
	elif mode == "cpu":
		await _cpu(args[1] if args.size() > 1 else "23:10")
	elif mode == "shots":
		await _shots(args[1], args[2] if args.size() > 2 else "23:10")
	else:
		await _perf(args[1] if args.size() > 1 else "23:10")
	quit(0)
