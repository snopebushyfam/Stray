## R12 isolated test scene: the three pilot NPCs with their pre-baked animations (no runtime
## retargeting). Renders evidence images and measures render/animation cost against R10 and R11.
##   xvfb-run godot --path . -s res://tools/character/r12_preview.gd -- <out_dir> [shots|perf]
extends SceneTree

const UAL := "res://assets/characters/quaternius_ual/UAL1_Standard.glb"
const R11 := "res://assets/characters/r11_human/stray_r11_male.glb"
const IDS := ["passerby_m", "passerby_f", "bouncer"]
var out := "user://"
var cam: Camera3D
var w: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _snap(file_name: String) -> void:
	await _frames(3)
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
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	w.add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.3, 0.31)
	fl.material_override = fm
	w.add_child(fl)
	cam = Camera3D.new()
	w.add_child(cam)
	cam.make_current()


func _npc(id: String, pos: Vector3, anim: String) -> Node3D:
	var n := StrayNpcHuman.create(id)
	n.position = pos
	w.add_child(n)
	var ap: AnimationPlayer = n.get_node("AnimationPlayer")
	ap.play(anim)
	return n


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var mode: String = args[1] if args.size() > 1 else "shots"
	DirAccess.make_dir_recursive_absolute(out)
	_scene()
	if mode == "perf":
		await _perf()
		quit(0)
		return
	var npcs: Array[Node3D] = []
	for i in IDS.size():
		npcs.append(_npc(IDS[i], Vector3(i * 1.1 - 1.1, 0, 0), "Idle"))
	await _frames(20)
	_look(Vector3(0, 1.0, 5.0), Vector3(0, 0.95, 0), 40)
	await _snap("r12_lineup_front.png")
	_look(Vector3(0, 1.0, -5.0), Vector3(0, 0.95, 0), 40)
	await _snap("r12_lineup_back.png")
	for i in IDS.size():
		var x := i * 1.1 - 1.1
		var hy: float = {"passerby_m": 1.62, "passerby_f": 1.5, "bouncer": 1.72}[IDS[i]]  # approx. eye height (m)
		_look(Vector3(x + 0.25, hy + 0.02, 1.2), Vector3(x, hy - 0.05, 0), 32)
		await _snap("r12_face_%s.png" % IDS[i])
	# Animation strips (6 phases each): Walk side view, Idle, Idle_Talking.
	for i in IDS.size():
		for n in npcs:
			n.visible = false
		var n := npcs[i]
		n.visible = true
		var ap: AnimationPlayer = n.get_node("AnimationPlayer")
		for a in ["Walk", "Idle", "Idle_Talking"]:
			ap.play(a)
			for k in 6:
				ap.seek(ap.current_animation_length * k / 6.0, true)
				await _frames(2)
				if a == "Walk":
					_look(n.position + Vector3(3.5, 0.9, 0.3), n.position + Vector3(0, 0.85, 0), 36)
				else:
					_look(n.position + Vector3(1.4, 1.1, 2.6), n.position + Vector3(0, 0.95, 0), 40)
				await _snap("r12_anim_%s_%s_%d.png" % [IDS[i], a, k])
	print("R12 shots done")
	quit(0)


## Render + animation cost: 3 characters per variant, near and far, plus CPU time with 30 animated.
func _perf() -> void:
	for variant in ["none", "r10", "r11", "r12"]:
		var holder := Node3D.new()
		w.add_child(holder)
		var count := 3
		for i in count:
			var p := Vector3(i * 1.1 - 1.1, 0, 0)
			if variant == "r10":
				var m: Node3D = load(UAL).instantiate()
				m.position = p
				holder.add_child(m)
				StrayCharacterLook.apply(m, "player")
				(m.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer).play("Walk")
			elif variant == "r11":
				var r := StrayHumanRig.new()
				r.position = p
				holder.add_child(r)
				r.setup(load(R11), load(UAL))
				r.anim.play("Walk")
			elif variant == "r12":
				var n := StrayNpcHuman.create(IDS[i])
				n.position = p
				holder.add_child(n)
				(n.get_node("AnimationPlayer") as AnimationPlayer).play("Walk")
		for dist in [4.0, 25.0]:
			_look(Vector3(0, 1.0, dist), Vector3(0, 0.9, 0), 40)
			await _frames(20)
			var dc := 0.0
			var pr := 0.0
			for f in 10:
				await process_frame
				dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
				pr += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			print("R12PERF %s x%d dist=%.0f draw_calls=%.0f primitives=%.0f tex_mem_mb=%.1f buf_mem_mb=%.1f" % [variant, count, dist, dc / 10.0, pr / 10.0,
				Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0])
		holder.queue_free()
		await _frames(5)
	# CPU animation cost per character: advance the animation (and for R11 the runtime retarget)
	# 300 times and time it with the wall clock (process monitors were too noisy in software rendering).
	for variant in ["r10", "r11", "r12"]:
		var holder := Node3D.new()
		w.add_child(holder)
		var ap: AnimationPlayer
		var rig: StrayHumanRig
		var sk: Skeleton3D
		if variant == "r10":
			var m: Node3D = load(UAL).instantiate()
			holder.add_child(m)
			ap = m.find_children("*", "AnimationPlayer", true, false)[0]
			sk = m.find_children("*", "Skeleton3D", true, false)[0]
		elif variant == "r11":
			rig = StrayHumanRig.new()
			holder.add_child(rig)
			rig.setup(load(R11), load(UAL))
			ap = rig.anim
			sk = rig.dst
		else:
			var n := StrayNpcHuman.create("passerby_m")
			holder.add_child(n)
			ap = n.get_node("AnimationPlayer")
			sk = n.find_children("*", "Skeleton3D", true, false)[0]
		ap.play("Walk")
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		await _frames(3)
		var t0 := Time.get_ticks_usec()
		for k in 300:
			ap.advance(1.0 / 60.0)
			if rig:
				rig.retarget()
			sk.force_update_all_bone_transforms()
		var us := float(Time.get_ticks_usec() - t0) / 300.0
		print("R12ANIM %s per_character_us=%.0f (animation%s + skeleton update)" % [variant, us, " + retarget" if rig else ""])
		holder.queue_free()
		await _frames(3)
