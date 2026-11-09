## Character looks (R10): dresses the CC0 Quaternius UAL mannequin as everyday people.
##
## - dressed_mesh(): once per source mesh, builds ONE shared ArrayMesh (both mannequin surfaces
##   merged -> 1 draw call per character, auto LODs) whose vertex colour holds the clothing zone
##   (from the dominant bone + bind pose) and the bind-pose position for the shader.
## - material(): one ShaderMaterial per look id (data/p001/character_looks.json), shared.
## - apply(): swaps mesh + material on an instantiated UAL model. Skeleton, animations and the
##   AnimationPlayer are untouched, so every existing animation keeps working.
class_name StrayCharacterLook
extends RefCounted

const LOOKS_PATH := "res://data/p001/character_looks.json"
const SHADER_PATH := "res://assets/shaders/spatial_char_clothing.gdshader"
enum Zone { SKIN, HAIR, TOP, SLEEVE, PANTS, SHOES, NECK, HANDS, FACE }

static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}
static var _cfg: Dictionary = {}
static var _face: Dictionary = {}


static func config() -> Dictionary:
	if _cfg.is_empty():
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOOKS_PATH))
		_cfg = v if typeof(v) == TYPE_DICTIONARY else {"looks": {}}
	return _cfg


## Look ids of a group ("street", "club", ...), in config order.
static func group(name: String) -> Array:
	return config().get("groups", {}).get(name, [])


static func _zone_of(bone: String, p: Vector3, head: Dictionary) -> int:
	if bone == "Head":
		var y0: float = head["y0"]
		var y1: float = head["y1"]
		var zc: float = head["zc"]
		var rel: float = (p.y - y0) / maxf(y1 - y0, 0.001)
		# Hair: crown, plus the back of the head down to the nape.
		if rel > 0.7 or (p.z < zc - 0.02 and rel > 0.32):
			return Zone.HAIR
		return Zone.FACE
	if bone == "neck_01":
		return Zone.NECK
	if bone.begins_with("hand") or bone.begins_with("index") or bone.begins_with("middle") \
			or bone.begins_with("ring") or bone.begins_with("pinky") or bone.begins_with("thumb"):
		return Zone.HANDS
	if bone.begins_with("lowerarm"):
		return Zone.SLEEVE
	if bone.begins_with("spine") or bone.begins_with("clavicle") or bone.begins_with("upperarm"):
		return Zone.TOP
	if bone == "pelvis":
		return Zone.TOP if p.y > 1.0 else Zone.PANTS
	if bone.begins_with("thigh") or bone.begins_with("calf"):
		return Zone.SHOES if p.y < 0.09 else Zone.PANTS
	if bone.begins_with("foot") or bone.begins_with("ball"):
		return Zone.SHOES
	return Zone.SKIN


## Shared dressed mesh for a mannequin MeshInstance3D (cached per source mesh).
static func dressed_mesh(src: MeshInstance3D) -> Mesh:
	var key := src.mesh.resource_path if not src.mesh.resource_path.is_empty() else str(src.mesh.get_instance_id())
	if _meshes.has(key):
		return _meshes[key]
	var skel := src.get_node_or_null(src.skeleton) as Skeleton3D
	if skel == null:
		return src.mesh
	var names: PackedStringArray = []
	for i in skel.get_bone_count():
		names.append(skel.get_bone_name(i))
	# Pass 1: head bounds (bind pose) for hair/face split and eye placement.
	var head := {"y0": INF, "y1": -INF, "zc": 0.0, "zmax": -INF}
	var n := 0
	var all_arrays := []
	for s in src.mesh.get_surface_count():
		var arr := src.mesh.surface_get_arrays(s)
		all_arrays.append(arr)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / v.size()
		for i in v.size():
			if names[_dominant(bones, w, i, per)] == "Head":
				head["y0"] = minf(head["y0"], v[i].y)
				head["y1"] = maxf(head["y1"], v[i].y)
				head["zc"] = float(head["zc"]) + v[i].z
				head["zmax"] = maxf(head["zmax"], v[i].z)
				n += 1
	head["zc"] = float(head["zc"]) / maxf(n, 1)
	_face = {"eye_y": float(head["y0"]) + 0.5 * (float(head["y1"]) - float(head["y0"])), "face_z": float(head["zmax"]),
		"head_y0": float(head["y0"]), "head_y1": float(head["y1"]), "head_zc": float(head["zc"])}
	# Landmarks from the rest skeleton (bind pose): elbows, wrists, neck, pelvis, ankles.
	var rest := func(bone: String) -> Vector3:
		var bi := skel.find_bone(bone)
		return skel.get_bone_global_rest(bi).origin if bi >= 0 else Vector3.ZERO
	_face["shoulder_x"] = absf(rest.call("upperarm_l").x)
	_face["elbow_x"] = absf(rest.call("lowerarm_l").x)
	_face["wrist_x"] = absf(rest.call("hand_l").x)
	_face["neck_y"] = rest.call("neck_01").y
	_face["belt_y"] = rest.call("pelvis").y + 0.02
	_face["ankle_y"] = rest.call("foot_l").y + 0.02
	print("STRAY_DIAG character rig landmarks %s" % JSON.stringify(_face))
	# Pass 2: merge both surfaces, zone + bind pose into COLOR.
	var out := {}
	for key2 in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
		out[key2] = null
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var bones_out := PackedInt32Array()
	var weights_out := PackedFloat32Array()
	var idx_out := PackedInt32Array()
	for arr in all_arrays:
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var per := bones.size() / v.size()
		var base := verts.size()
		for i in v.size():
			var z := _zone_of(names[_dominant(bones, w, i, per)], v[i], head)
			cols.append(Color(float(z) / 15.0, clampf(v[i].y * 0.5, 0, 1), clampf(v[i].x * 0.5 + 0.5, 0, 1), clampf(v[i].z * 0.5 + 0.5, 0, 1)))
			# Normalise to 4 influences (Godot's default skinning).
			for k in 4:
				bones_out.append(bones[i * per + k] if k < per else 0)
				weights_out.append(w[i * per + k] if k < per else 0.0)
		verts.append_array(v)
		norms.append_array(nr)
		for i in idx:
			idx_out.append(base + i)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_BONES] = bones_out
	arrays[Mesh.ARRAY_WEIGHTS] = weights_out
	arrays[Mesh.ARRAY_INDEX] = idx_out
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	im.generate_lods(25.0, 60.0, [])
	var mesh := im.get_mesh()
	_meshes[key] = mesh
	print("STRAY_DIAG character dressed_mesh verts=%d tris=%d head_y=[%.2f,%.2f]" % [verts.size(), idx_out.size() / 3, head["y0"], head["y1"]])
	return mesh


static func _dominant(bones: PackedInt32Array, w: PackedFloat32Array, i: int, per: int) -> int:
	var best := 0
	var bw := -1.0
	for k in per:
		if w[i * per + k] > bw:
			bw = w[i * per + k]
			best = bones[i * per + k]
	return best


## Shared material for a look id (falls back to the first look).
static func material(look_id: String) -> ShaderMaterial:
	if _materials.has(look_id):
		return _materials[look_id]
	var looks: Dictionary = config().get("looks", {})
	var look: Dictionary = looks.get(look_id, looks.values()[0] if not looks.is_empty() else {})
	var m := ShaderMaterial.new()
	m.shader = load(SHADER_PATH)
	for k in look:
		var v: Variant = look[k]
		if typeof(v) == TYPE_ARRAY and (v as Array).size() == 3:
			m.set_shader_parameter(k, Color(v[0], v[1], v[2]))
		elif typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
			m.set_shader_parameter(k, float(v))
	for k in _face:
		m.set_shader_parameter(k, float(_face[k]))
	_materials[look_id] = m
	return m


## Dresses an instantiated UAL model with a look. Returns false when no mannequin mesh is found.
static func apply(model: Node, look_id: String) -> bool:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		if m3.skin == null or m3.mesh == null:
			continue
		m3.mesh = dressed_mesh(m3)
		for s in m3.get_surface_override_material_count():
			m3.set_surface_override_material(s, null)
		m3.material_override = material(look_id)
		return true
	return false
