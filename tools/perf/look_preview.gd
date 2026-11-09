## Renders all character looks side by side (R10 preview / evidence).
## xvfb-run godot --path . -s res://tools/perf/look_preview.gd -- <out.png> [anim]
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://looks.png"
	var anim: String = args[1] if args.size() > 1 else "Idle"
	var w := Node3D.new()
	root.add_child(w)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.32, 0.34, 0.38)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.7)
	e.ambient_light_energy = 0.5
	env.environment = e
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 1.4
	w.add_child(sun)
	var ids: Array = StrayCharacterLook.config().get("looks", {}).keys()
	var x := -(ids.size() - 1) * 0.45
	for id in ids:
		var m: Node3D = load("res://assets/characters/quaternius_ual/UAL1_Standard.glb").instantiate()
		m.position = Vector3(x, 0, 0)
		w.add_child(m)
		StrayCharacterLook.apply(m, id)
		var ap: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
		ap.play(anim)
		ap.seek(0.4, true)
		x += 0.9
	var cam := Camera3D.new()
	cam.fov = 38
	cam.position = Vector3(0, 1.1, 9.5)
	w.add_child(cam)
	cam.make_current()
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out)
	# Close-up of the player look.
	cam.fov = 22
	cam.position = Vector3(-(ids.size() - 1) * 0.45 + (ids.find("player")) * 0.9, 1.2, 4.0)
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out.replace(".png", "_closeup.png"))
	quit(0)
