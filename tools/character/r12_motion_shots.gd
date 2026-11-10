## R12.2 motion evidence: renders time sequences of an NPC with a given animation library
## (before/after comparison with identical cameras): Idle over a full clip (front + side), Walk
## cycle (side), Idle_Talking (3/4), transition Idle -> Walk -> Idle with the game's 0.25 s blend,
## shoulder and both hands in idle.
##   xvfb-run godot --path . -s res://tools/character/r12_motion_shots.gd -- <out_dir> <anim_dir> [ids]
extends SceneTree

var out := ""
var cam: Camera3D
var w: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _snap(file_name: String) -> void:
	await _frames(2)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out.path_join(file_name))


func _look(pos: Vector3, target: Vector3, fov: float) -> void:
	cam.fov = fov
	cam.global_position = pos
	cam.look_at(target, Vector3.UP)


func _scene() -> void:
	w = Node3D.new()
	root.add_child(w)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.36, 0.38, 0.42)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.64, 0.7)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	w.add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.3, 0.31)
	fl.material_override = fm
	w.add_child(fl)
	# Floor markers every 0.5 m along Z: foot sliding is visible against them.
	for i in range(-8, 9):
		var mk := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.6, 0.002, 0.02)
		mk.mesh = bm
		var mm := StandardMaterial3D.new()
		mm.albedo_color = Color(0.55, 0.55, 0.5)
		mk.material_override = mm
		mk.position = Vector3(0, 0.001, i * 0.5)
		w.add_child(mk)
	cam = Camera3D.new()
	w.add_child(cam)
	cam.make_current()


func _bone(sk: Skeleton3D, b: String) -> Vector3:
	return (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b))).origin


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	var anim_dir: String = args[1]
	var ids: Array = args.slice(2) if args.size() > 2 else ["passerby_m", "passerby_f", "bouncer"]
	DirAccess.make_dir_recursive_absolute(out)
	_scene()
	for id in ids:
		var root_n := Node3D.new()
		w.add_child(root_n)
		var n: Node3D = load("res://assets/characters/r12_npc/%s.glb" % id).instantiate()
		root_n.add_child(n)
		var ap := AnimationPlayer.new()
		n.add_child(ap)
		var lib: AnimationLibrary = load(anim_dir.path_join("%s_anims.res" % id))
		ap.add_animation_library("", lib)
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
		var p := String(id)
		# Idle: 8 frames over the whole clip, front and side.
		var il := ap.get_animation("Idle").length
		ap.play("Idle")
		for view in ["front", "side"]:
			for k in 8:
				ap.seek(il * k / 8.0, true)
				ap.advance(0)
				if view == "front":
					_look(Vector3(0, 1.0, 3.6), Vector3(0, 0.9, 0), 40)
				else:
					_look(Vector3(3.6, 1.0, 0), Vector3(0, 0.9, 0), 40)
				await _snap("%s_idle_%s_%d.png" % [p, view, k])
		# Shoulder 45 + hands at mid idle.
		ap.seek(il * 0.5, true)
		ap.advance(0)
		var sh := (_bone(sk, "clavicle_l") + _bone(sk, "clavicle_r")) * 0.5
		_look(sh + Vector3(1.0, 0.25, 1.0), sh + Vector3(0, -0.05, 0), 38)
		await _snap("%s_shoulder45.png" % p)
		for side in ["l", "r"]:
			var hp := _bone(sk, "hand_" + side)
			_look(hp + Vector3(0.3 if side == "l" else -0.3, 0.05, 0.5), hp + Vector3(0, -0.07, 0), 30)
			await _snap("%s_hand_%s.png" % [p, side])
		# Walk cycle: 8 frames side; the root moves with the game's speed scaling (foot slide check).
		var wl := ap.get_animation("Walk").length
		var nat: float = lib.get_meta("walk_natural_speed", 0.97)
		ap.play("Walk")
		for k in 8:
			var t := wl * k / 8.0
			ap.seek(t, true)
			ap.advance(0)
			root_n.position.z = t * nat  # body speed = natural speed at speed_scale 1
			_look(Vector3(3.6, 0.95, root_n.position.z), Vector3(0, 0.85, root_n.position.z), 36)
			await _snap("%s_walk_%d.png" % [p, k])
		root_n.position.z = 0
		# Talk: 8 frames 3/4 view.
		var tl := ap.get_animation("Idle_Talking").length
		ap.play("Idle_Talking")
		for k in 8:
			ap.seek(tl * k / 8.0, true)
			ap.advance(0)
			_look(Vector3(1.3, 1.15, 2.6), Vector3(0, 1.0, 0), 38)
			await _snap("%s_talk_%d.png" % [p, k])
		# Transition Idle (1 s) -> Walk (1.5 s) -> Idle (1.5 s), blend 0.25 s like pedestrians.gd.
		ap.play("Idle")
		ap.seek(0.0, true)
		var shot := 0
		var dt := 1.0 / 30.0
		for f in 120:
			var t := f * dt
			if f == 30:
				ap.play("Walk", 0.25)
			elif f == 75:
				ap.play("Idle", 0.25)
			ap.advance(dt)
			if f % 10 == 0:
				_look(Vector3(3.6, 1.0, 0), Vector3(0, 0.9, 0), 40)
				await _snap("%s_trans_%02d.png" % [p, shot])
				shot += 1
		root_n.queue_free()
		await _frames(3)
	print("MOTION done")
	quit(0)
