## R12.1 anatomy audit: renders the R12 NPCs (baked animations, exactly as in the game) for
## before/after comparison: bind pose, Idle front/side/back, shoulder 45 deg, both hands, Walk and
## Idle_Talking in 6 phases, and debug views (bone axes, skin weights of clavicle/upperarm/spine).
##   xvfb-run godot --path . -s res://tools/character/r12_audit.gd -- <out_dir> [ids...]
extends SceneTree

var out := "user://"
var cam: Camera3D
var w: Node3D
var lines: MeshInstance3D


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
	pm.size = Vector2(20, 20)
	fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.3, 0.31)
	fl.material_override = fm
	w.add_child(fl)
	cam = Camera3D.new()
	w.add_child(cam)
	cam.make_current()
	lines = MeshInstance3D.new()
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.vertex_color_use_as_albedo = true
	lm.no_depth_test = true
	lines.material_override = lm
	w.add_child(lines)


func _bone_pos(sk: Skeleton3D, b: String) -> Vector3:
	return (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b))).origin


## Draws bone segments (white) and local axes X red / Y green / Z blue for arm/hand bones.
func _draw_bones(sk: Skeleton3D) -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in sk.get_bone_count():
		var p := sk.get_bone_parent(i)
		var a: Transform3D = sk.global_transform * sk.get_bone_global_pose(i)
		if p >= 0:
			im.surface_set_color(Color(1, 1, 1))
			im.surface_add_vertex((sk.global_transform * sk.get_bone_global_pose(p)).origin)
			im.surface_add_vertex(a.origin)
		var bn := sk.get_bone_name(i)
		if bn.contains("clavicle") or bn.contains("arm") or bn.begins_with("hand") or bn.contains("_01_") or bn.begins_with("spine_03"):
			var s := 0.05 if not bn.contains("_01_") else 0.025
			for ax in 3:
				im.surface_set_color([Color.RED, Color.GREEN, Color.BLUE][ax])
				im.surface_add_vertex(a.origin)
				im.surface_add_vertex(a.origin + a.basis[ax].normalized() * s)
	im.surface_end()
	lines.mesh = im


## Weight heat map: R = clavicle_l + clavicle_r, G = upperarm_l + upperarm_r, B = spine_03.
func _weight_view(n: Node3D) -> MeshInstance3D:
	var mi: MeshInstance3D = n.find_children("*", "MeshInstance3D", true, false)[0]
	var sk := mi.get_node(mi.skeleton) as Skeleton3D
	var ids := {}
	for k in ["clavicle_l", "clavicle_r", "upperarm_l", "upperarm_r", "spine_03"]:
		ids[k] = sk.find_bone(k)
	var arr := mi.mesh.surface_get_arrays(0)
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var nv := (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var per := bones.size() / nv
	var cols := PackedColorArray()
	cols.resize(nv)
	# Skin bone indices are skin-bind indices; map them to skeleton names via the Skin resource.
	var skin: Skin = mi.skin
	for v in nv:
		var c := Color(0.08, 0.08, 0.08)
		for k in per:
			var bi := bones[v * per + k]
			var bn: String = String(skin.get_bind_name(bi)) if skin and bi < skin.get_bind_count() else sk.get_bone_name(bi)
			var wv := wts[v * per + k]
			if bn.begins_with("clavicle"): c.r += wv
			elif bn.begins_with("upperarm"): c.g += wv
			elif bn == "spine_03": c.b += wv
		cols[v] = c
	arr[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var dbg := MeshInstance3D.new()
	dbg.mesh = m
	dbg.skin = mi.skin
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dbg.material_override = mat
	mi.get_parent().add_child(dbg)
	dbg.transform = mi.transform
	dbg.skeleton = dbg.get_path_to(sk)
	mi.visible = false
	return dbg


func _pose(ap: AnimationPlayer, anim: String, t: float) -> void:
	ap.play(anim)
	ap.seek(t, true)
	ap.pause()
	await _frames(2)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	var ids: Array = args.slice(1) if args.size() > 1 else ["passerby_m", "passerby_f", "bouncer"]
	DirAccess.make_dir_recursive_absolute(out)
	_scene()
	for id in ids:
		var n: Node3D = StrayNpcHuman.create(String(id))
		w.add_child(n)
		var ap: AnimationPlayer = n.get_node("AnimationPlayer")
		var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
		var p := String(id)
		# 1) Bind / rest pose (no animation applied).
		sk.reset_bone_poses()
		await _frames(3)
		_look(Vector3(0, 1.0, 4.0), Vector3(0, 0.95, 0), 40)
		await _snap(p + "_00_bindpose.png")
		_draw_bones(sk)
		await _snap(p + "_01_bindpose_bones.png")
		lines.mesh = null
		# 2) Idle front / side / back / shoulder 45 / hands.
		await _pose(ap, "Idle", 0.5)
		_look(Vector3(0, 1.0, 4.0), Vector3(0, 0.95, 0), 40)
		await _snap(p + "_02_idle_front.png")
		_look(Vector3(4.0, 1.0, 0), Vector3(0, 0.95, 0), 40)
		await _snap(p + "_03_idle_side.png")
		_look(Vector3(0, 1.0, -4.0), Vector3(0, 0.95, 0), 40)
		await _snap(p + "_04_idle_back.png")
		var sh := (_bone_pos(sk, "clavicle_l") + _bone_pos(sk, "clavicle_r")) * 0.5
		_look(sh + Vector3(1.0, 0.25, 1.0), sh + Vector3(0, -0.05, 0), 38)
		await _snap(p + "_05_idle_shoulder45.png")
		_draw_bones(sk)
		await _snap(p + "_06_idle_shoulder45_bones.png")
		lines.mesh = null
		for side in ["l", "r"]:
			var hp := _bone_pos(sk, "hand_" + side)
			var out_dir := Vector3(1.0 if side == "l" else -1.0, 0, 0)
			_look(hp + out_dir * 0.3 + Vector3(0, 0.05, 0.5), hp + Vector3(0, -0.07, 0), 30)
			await _snap(p + "_07_idle_hand_%s.png" % side)
		# 3) Weight debug at the shoulder (idle pose).
		var dbg := _weight_view(n)
		_look(sh + Vector3(1.0, 0.25, 1.0), sh + Vector3(0, -0.05, 0), 38)
		await _snap(p + "_08_weights_shoulder.png")
		dbg.queue_free()
		(n.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).visible = true
		# 4) Walk (side) + Idle_Talking (front 3/4), 6 phases.
		for a in ["Walk", "Idle_Talking"]:
			var len_s := ap.get_animation(a).length
			for k in 6:
				await _pose(ap, a, len_s * k / 6.0)
				if a == "Walk":
					_look(Vector3(3.6, 0.95, 0.4), Vector3(0, 0.9, 0), 36)
				else:
					_look(Vector3(1.3, 1.15, 2.6), Vector3(0, 1.0, 0), 38)
				await _snap(p + "_%s_%d.png" % ["10_walk" if a == "Walk" else "20_talk", k])
		n.queue_free()
		await _frames(3)
	print("AUDIT done")
	quit(0)
