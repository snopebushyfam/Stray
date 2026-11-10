## R12.4 evidence: side view of one baked clip of an R12 human in N phases, as one strip image.
##   xvfb-run godot --path . -s res://tools/character/r12_clip_side.gd -- <out.png> <id> <clip> [phases]
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var id: String = a[1]
	var clip: String = a[2]
	var phases := int(a[3]) if a.size() > 3 else 6
	root.size = Vector2i(420, 640)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.36, 0.38, 0.43)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment.ambient_light_energy = 0.6
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	root.add_child(sun)
	var n := StrayNpcHuman.create(id)
	root.add_child(n)
	var ap: AnimationPlayer = n.get_node("AnimationPlayer")
	var cam := Camera3D.new()
	cam.position = Vector3(3.2, 0.95, 0)
	cam.fov = 40
	root.add_child(cam)
	cam.look_at(Vector3(0, 0.9, 0))
	var L := ap.get_animation(clip).length
	var strip := Image.create(420 * phases, 640, false, Image.FORMAT_RGBA8)
	for k in phases:
		ap.play(clip)
		ap.seek(L * k / phases, true)
		ap.pause()
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		strip.blit_rect(img, Rect2i(0, 0, 420, 640), Vector2i(420 * k, 0))
	strip.save_png(out)
	print("CLIPSIDE ", out)
	quit(0)
