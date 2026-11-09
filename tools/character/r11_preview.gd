## R11 isolated test scene: renders the real-human prototype (static rest, animated poses, close-ups,
## R10 comparison) to PNG files. Needs a renderer:
##   xvfb-run godot --path . -s res://tools/character/r11_preview.gd -- <out_dir> [mode]
## mode "rest": static model only (front/side), "full": all evidence images.
extends SceneTree

const HUMAN := "res://assets/characters/r11_human/stray_r11_male.glb"
const UAL := "res://assets/characters/quaternius_ual/UAL1_Standard.glb"
var out := "user://"
var cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _snap(file_name: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out.path_join(file_name))
	print("R11SHOT ", file_name)


func _look(pos: Vector3, target: Vector3, fov: float) -> void:
	cam.fov = fov
	cam.global_position = pos
	cam.look_at(target, Vector3.UP)


func _env(w: Node3D) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.36, 0.38, 0.42)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.64, 0.7)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	w.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.3, 0.31)
	floor_mi.material_override = fm
	w.add_child(floor_mi)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var mode: String = args[1] if args.size() > 1 else "full"
	DirAccess.make_dir_recursive_absolute(out)
	var w := Node3D.new()
	root.add_child(w)
	_env(w)
	cam = Camera3D.new()
	w.add_child(cam)
	cam.make_current()
	if mode == "rest":
		var h: Node3D = load(HUMAN).instantiate()
		w.add_child(h)
		_look(Vector3(0, 1.0, 4.0), Vector3(0, 0.9, 0), 40)
		await _snap("r11_rest_front.png")
		_look(Vector3(4.0, 1.0, 0), Vector3(0, 0.9, 0), 40)
		await _snap("r11_rest_side.png")
		quit(0)
		return
	if mode == "perf":
		# Render cost of ONE character, R10 vs R11, near (3 m) and far (25 m, LOD).
		for variant in ["none", "r10", "r11"]:
			var holder := Node3D.new()
			w.add_child(holder)
			if variant == "r10":
				var m: Node3D = load(UAL).instantiate()
				holder.add_child(m)
				StrayCharacterLook.apply(m, "player")
				(m.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer).play("Walk")
			elif variant == "r11":
				var r := StrayHumanRig.new()
				holder.add_child(r)
				r.setup(load(HUMAN), load(UAL))
				r.anim.play("Walk")
			for dist in [3.0, 25.0]:
				_look(Vector3(0, 1.0, dist), Vector3(0, 0.9, 0), 40)
				await _frames(20)
				var dc := 0.0
				var pr := 0.0
				for f in 10:
					await process_frame
					dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
					pr += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
				print("R11PERF %s dist=%.0f draw_calls=%.0f primitives=%.0f tex_mem_mb=%.1f buf_mem_mb=%.1f" % [variant, dist, dc / 10.0, pr / 10.0,
					Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0])
			holder.queue_free()
			await _frames(5)
		quit(0)
		return
	if mode == "hands":
		var k := 0
		for ax in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
			var r := StrayHumanRig.new()
			r.position = Vector3(k * 1.2, 0, 0)
			w.add_child(r)
			r.setup(load(HUMAN), load(UAL))
			r.finger_curl_axis = ax
			r.anim.play("Idle")
			k += 1
		await _frames(20)
		for j in 4:
			_look(Vector3(j * 1.2 + 0.55, 0.95, 0.75), Vector3(j * 1.2 + 0.25, 0.8, 0), 30)
			await _snap("r11_hand_axis_%d.png" % j)
		quit(0)
		return
	var rig := StrayHumanRig.new()
	w.add_child(rig)
	rig.setup(load(HUMAN), load(UAL))
	rig.rotation.y = 0.0
	var ap := rig.anim
	# Full body front / side / back in Idle.
	ap.play("Idle")
	await _frames(20)
	_look(Vector3(0, 1.0, 4.2), Vector3(0, 0.9, 0), 38)
	await _snap("r11_idle_front.png")
	_look(Vector3(4.2, 1.0, 0), Vector3(0, 0.9, 0), 38)
	await _snap("r11_idle_side.png")
	_look(Vector3(0, 1.0, -4.2), Vector3(0, 0.9, 0), 38)
	await _snap("r11_idle_back.png")
	# Face and clothes close-up.
	_look(Vector3(0.25, 1.68, 0.75), Vector3(0, 1.62, 0), 30)
	await _snap("r11_face_closeup.png")
	_look(Vector3(0.6, 1.1, 1.4), Vector3(0, 0.9, 0), 45)
	await _snap("r11_clothes_closeup.png")
	# Animation strips: 6 frames each, side view (foot contact readable on the floor).
	for a in ["Walk", "Jog_Fwd", "Sprint", "Dance", "Idle_Talking"]:
		ap.play(a)
		var len_s := ap.current_animation_length
		for k in 6:
			ap.seek(len_s * k / 6.0, true)
			await _frames(2)
			if a == "Dance" or a == "Idle_Talking":
				_look(Vector3(1.8, 1.1, 3.0), Vector3(0, 0.95, 0), 40)
			else:
				_look(Vector3(4.0, 0.9, 0.3), Vector3(0, 0.85, 0), 36)
			await _snap("r11_anim_%s_%d.png" % [a, k])
	# Comparison with the R10 mannequin (same Idle frame), side by side.
	ap.play("Idle")
	ap.seek(0.5, true)
	var r10: Node3D = load(UAL).instantiate()
	r10.position = Vector3(-1.0, 0, 0)
	r10.rotation.y = 0.0
	w.add_child(r10)
	StrayCharacterLook.apply(r10, "player")
	var rap: AnimationPlayer = r10.find_children("*", "AnimationPlayer", true, false)[0]
	rap.play("Idle")
	rap.seek(0.5, true)
	rig.position = Vector3(0.0, 0, 0)
	await _frames(10)
	_look(Vector3(-0.5, 1.05, 3.6), Vector3(-0.5, 0.9, 0), 40)
	await _snap("r11_vs_r10.png")
	print("R11 done mapped=%d" % rig.mapped_bones)
	quit(0)
