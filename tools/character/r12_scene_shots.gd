## R12 in-game evidence: loads the real game scene at night and photographs the three pilot slots
## (walker 0 on the Ring, queue person 0, the bouncer) with fixed cameras relative to those NPCs,
## plus a NACHTFLUG overview, and prints render cost. Works on any commit (before/after compare).
##   xvfb-run godot --path . -s res://tools/character/r12_scene_shots.gd -- <out_dir> <prefix>
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _snap(path: String) -> void:
	await _frames(4)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)


func _cost(tag: String) -> void:
	var d := 0.0
	var p := 0.0
	for i in 10:
		await process_frame
		d += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		p += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	print("R12SCENE %-18s draw_calls=%5d primitives=%7d" % [tag, int(d / 10.0), int(p / 10.0)])


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var prefix: String = args[1]
	DirAccess.make_dir_recursive_absolute(out)
	var m: Node = load("res://src/p001/main.tscn").instantiate()
	root.add_child(m)
	await _frames(60)
	var L: StrayStreetLayout = m.builder.layout
	m.player.visible = false
	var cam := Camera3D.new()
	cam.fov = 45
	m.add_child(cam)
	cam.make_current()
	var c := StrayStreetLayout._v2(L.club["en"])
	var cn := StrayStreetLayout._v2(L.club["normal_en"]).normalized()
	# 1) NACHTFLUG overview at night (queue + bouncer).
	var e := c + cn * 7.0 - L.axis_en() * 9.0
	cam.global_position = StrayStreetLayout.en_to_godot(e.x, e.y, L.ground_z_at(e) + 1.7)
	cam.look_at(StrayStreetLayout.en_to_godot(c.x, c.y, L.ground_z_at(c) + 1.4), Vector3.UP)
	await _snap(out.path_join(prefix + "_1_nachtflug_night.png"))
	await _cost("nachtflug_view")
	# 2) Bouncer + queue head, close.
	var b: Node3D = m.interactions.get_node("Bouncer")
	var q0: Node3D = m.pedestrians.queue[0]
	var mid := (b.global_position + q0.global_position) * 0.5
	var outw := StrayStreetLayout.en_dir_to_godot(cn)
	cam.global_position = mid + outw * 3.2 + Vector3(0, 1.6, 0)
	cam.look_at(mid + Vector3(0, 1.2, 0), Vector3.UP)
	await _snap(out.path_join(prefix + "_2_bouncer_queue_close.png"))
	# 3) Walker 0 on the Ring: freeze its walk and look at it from the front-side.
	var w0 = m.pedestrians.walkers[0]
	m.pedestrians.process_mode = Node.PROCESS_MODE_DISABLED
	var r: Node3D = w0.root
	var fwd := -r.global_transform.basis.z
	cam.global_position = r.global_position + fwd * 3.0 + r.global_transform.basis.x * 1.2 + Vector3(0, 1.55, 0)
	cam.look_at(r.global_position + Vector3(0, 1.0, 0), Vector3.UP)
	await _snap(out.path_join(prefix + "_3_ring_walker_close.png"))
	# 4) Render cost at the R9 spots (player view).
	m.pedestrians.process_mode = Node.PROCESS_MODE_INHERIT
	m.player.visible = true
	m.player.camera.make_current()
	m.player.global_position = L.spawn_position(0.9)
	m.player.face_yaw(L.spawn_yaw())
	await _frames(20)
	await _cost("ring_spawn")
	var n := c + cn * 6.0 - L.axis_en() * 10.0
	m.player.global_position = StrayStreetLayout.en_to_godot(n.x, n.y, L.ground_z_at(n) + 0.95)
	var d := StrayStreetLayout.en_dir_to_godot(L.axis_en())
	m.player.face_yaw(atan2(-d.x, -d.z))
	await _frames(20)
	await _cost("nachtflug_player")
	quit(0)
