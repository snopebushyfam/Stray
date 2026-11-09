## Render-load probe (R9.2): places the player at fixed spots and reads Godot's Performance
## monitors (objects, draw calls, primitives, lights) per frame. Needs a real renderer (not
## --headless), e.g. xvfb-run godot --path . -s res://tools/perf/render_probe.gd
## Prints "PROBE <spot> ..." lines. These are load numbers, not tablet frame rates.
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _sample(tag: String) -> void:
	await _frames(20)
	var o := 0.0
	var d := 0.0
	var p := 0.0
	for i in 10:
		await process_frame
		o += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		d += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		p += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	print("PROBE %-22s objects=%5d draw_calls=%5d primitives=%7d" % [tag, int(o / 10.0), int(d / 10.0), int(p / 10.0)])


func _run() -> void:
	var m: Node = load("res://src/p001/main.tscn").instantiate()
	root.add_child(m)
	await _frames(40)
	if "--r11" in OS.get_cmdline_user_args():
		m.player.set_character_variant("r11")
		await _frames(10)
	var L: StrayStreetLayout = m.builder.layout
	var pl: StrayPlayer = m.player
	var lights := 0
	for n in m.find_children("*", "Light3D", true, false):
		lights += 1
	var meshes := m.find_children("*", "MeshInstance3D", true, false).size()
	print("PROBE scene mesh_instances=%d lights=%d" % [meshes, lights])
	pl.global_position = L.spawn_position(0.9)
	pl.face_yaw(L.spawn_yaw())
	await _sample("ring_spawn")
	var c := StrayStreetLayout._v2(L.club["en"])
	var cn := StrayStreetLayout._v2(L.club["normal_en"])
	var e := c + cn * 6.0 - L.axis_en() * 10.0
	pl.global_position = StrayStreetLayout.en_to_godot(e.x, e.y, L.ground_z_at(e) + 0.95)
	var d := StrayStreetLayout.en_dir_to_godot(L.axis_en())
	pl.face_yaw(atan2(-d.x, -d.z))
	await _sample("nachtflug")
	pl.global_position = m.interactions.points["kiosk"] + Vector3(0, 0.95, 0)
	await _sample("kiosk")
	m.interactions.enter_club()
	await _sample("club_inside")
	m.interactions.leave_club()
	m.metro_ix.enter_station("friesenplatz")
	await _sample("metro")
	m.metro_ix.ride()
	m.metro_ix.leave_station()
	await _sample("hbf")
	quit(0)
