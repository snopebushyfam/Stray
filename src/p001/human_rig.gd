## R11 real-human prototype: plays the CC0 Quaternius UAL animations on a MakeHuman/MPFB character.
##
## A hidden "driver" UAL model runs the AnimationPlayer; every frame the world-space rotation delta of
## each driver bone (pose vs. its bind/rest pose) is applied to the bone of the same name on the human
## skeleton (pose = delta * human rest). Both rests are T-poses (the human was converted to a T-pose
## in tools/character/build_r11_human.py) and both rigs use Unreal-style names (game_engine rig),
## so the mapping is by name (case-insensitive: head/Head, root/Root). The pelvis translation is
## scaled by the hip-height ratio so feet keep contact.
## The driver's AnimationPlayer is a child of this node, so StrayPlayer / NPC code that looks for
## an AnimationPlayer works unchanged.
class_name StrayHumanRig
extends Node3D

var human: Node3D
var driver: Node3D
var src: Skeleton3D
var dst: Skeleton3D
var anim: AnimationPlayer
## dst bone index -> src bone index (-1 = keep rest)
var _map := PackedInt32Array()
var _order := PackedInt32Array()
var _src_rest_q: Array[Quaternion] = []
var _dst_rest_q: Array[Quaternion] = []
var _src_basis_q := Quaternion.IDENTITY
var _dst_basis_q := Quaternion.IDENTITY
var _hip_src := -1
var _hip_dst := -1
var _hip_scale := 1.0
var mapped_bones := 0
## Relaxed finger curl (radians per joint) and the local bone axis it bends about (measured for the
## MPFB game_engine rig in tools/character/r11_preview.gd "hands" mode).
var finger_curl := 0.28
var finger_curl_axis := Vector3.LEFT


## Builds the rig from the two scenes. Returns false when a skeleton is missing.
func setup(human_scene: PackedScene, driver_scene: PackedScene) -> bool:
	process_priority = 100  # after the AnimationPlayer (priority 0) has posed the driver this frame
	human = human_scene.instantiate()
	add_child(human)
	driver = driver_scene.instantiate()
	add_child(driver)
	for mi in driver.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visible = false  # the driver is never drawn
	var ss := driver.find_children("*", "Skeleton3D", true, false)
	var ds := human.find_children("*", "Skeleton3D", true, false)
	var aps := driver.find_children("*", "AnimationPlayer", true, false)
	if ss.is_empty() or ds.is_empty() or aps.is_empty():
		return false
	src = ss[0]
	dst = ds[0]
	anim = aps[0]
	_src_basis_q = (global_transform.affine_inverse() * src.global_transform).basis.get_rotation_quaternion() if is_inside_tree() else src.transform.basis.get_rotation_quaternion()
	_dst_basis_q = (global_transform.affine_inverse() * dst.global_transform).basis.get_rotation_quaternion() if is_inside_tree() else dst.transform.basis.get_rotation_quaternion()
	var lower := {}
	for i in src.get_bone_count():
		lower[src.get_bone_name(i).to_lower()] = i
	_map.resize(dst.get_bone_count())
	for i in dst.get_bone_count():
		var bn := dst.get_bone_name(i).to_lower()
		# Fingers are not transferred: the two rigs' finger rest poses differ (UAL curled, MakeHuman
		# flat), so rotation deltas turned the hands into claws. They get a fixed relaxed curl instead.
		_map[i] = -1 if _is_finger(bn) else int(lower.get(bn, -1))
		if _map[i] >= 0:
			mapped_bones += 1
		_dst_rest_q.append(dst.get_bone_global_rest(i).basis.get_rotation_quaternion())
	for i in src.get_bone_count():
		_src_rest_q.append(src.get_bone_global_rest(i).basis.get_rotation_quaternion())
	# Parents before children.
	var depth := {}
	for i in dst.get_bone_count():
		var d := 0
		var p := dst.get_bone_parent(i)
		while p >= 0:
			d += 1
			p = dst.get_bone_parent(p)
		depth[i] = d
	var idx: Array = range(dst.get_bone_count())
	idx.sort_custom(func(a, b): return depth[a] < depth[b])
	_order = PackedInt32Array(idx)
	_hip_src = src.find_bone("pelvis")
	_hip_dst = dst.find_bone("pelvis")
	print("STRAY_DIAG human_rig mapped=%d/%d (fingers posed, not transferred)" % [mapped_bones, dst.get_bone_count()])
	return true


## Skeleton-space -> rig-space transforms, measured once inside the tree (skeleton nodes of glTF
## imports can carry scale/rotation, e.g. the UAL armature).
var _spaces_ready := false
var _src_to_rig := Transform3D.IDENTITY
var _dst_to_rig := Transform3D.IDENTITY


func _init_spaces() -> void:
	_src_to_rig = global_transform.affine_inverse() * src.global_transform
	_dst_to_rig = global_transform.affine_inverse() * dst.global_transform
	_src_basis_q = _src_to_rig.basis.get_rotation_quaternion()
	_dst_basis_q = _dst_to_rig.basis.get_rotation_quaternion()
	if _hip_src >= 0 and _hip_dst >= 0:
		var hs := (_src_to_rig * src.get_bone_global_rest(_hip_src)).origin.y
		var hd := (_dst_to_rig * dst.get_bone_global_rest(_hip_dst)).origin.y
		_hip_scale = hd / maxf(hs, 0.01)
	_spaces_ready = true
	print("STRAY_DIAG human_rig hip_scale=%.3f" % _hip_scale)


static func _is_finger(bn: String) -> bool:
	for f in ["thumb_", "index_", "middle_", "ring_", "pinky_"]:
		if bn.begins_with(f):
			return true
	return false


func _process(_delta: float) -> void:
	if src == null or dst == null or not visible:
		return
	retarget()


## Copies the driver pose onto the human skeleton (call after the AnimationPlayer has run).
func retarget() -> void:
	if not _spaces_ready:
		_init_spaces()
	var glob: Array[Quaternion] = []
	glob.resize(dst.get_bone_count())
	for i in _order:
		var s := _map[i]
		var parent := dst.get_bone_parent(i)
		var parent_q := glob[parent] if parent >= 0 else Quaternion.IDENTITY
		var g: Quaternion
		if s >= 0:
			# World-space delta of the driver bone, moved into the human skeleton space.
			var src_pose_q := src.get_bone_global_pose(s).basis.get_rotation_quaternion()
			var delta_rig := _src_basis_q * (src_pose_q * _src_rest_q[s].inverse()) * _src_basis_q.inverse()
			var delta_dst := _dst_basis_q.inverse() * delta_rig * _dst_basis_q
			g = delta_dst * _dst_rest_q[i]
		else:
			var local_q := dst.get_bone_rest(i).basis.get_rotation_quaternion()
			if _is_finger(dst.get_bone_name(i).to_lower()):
				# Relaxed hand: curl each finger joint about its local X (thumb less).
				var curl := finger_curl * (0.4 if dst.get_bone_name(i).to_lower().begins_with("thumb_") else 1.0)
				local_q = local_q * Quaternion(finger_curl_axis, curl)
			g = parent_q * local_q
		glob[i] = g
		dst.set_bone_pose_rotation(i, (parent_q.inverse() * g).normalized())
	if _hip_src >= 0 and _hip_dst >= 0:
		# Pelvis offset from its rest, in rig space, scaled by the hip-height ratio (feet contact).
		var d_rig := _src_to_rig.basis * (src.get_bone_global_pose(_hip_src).origin - src.get_bone_global_rest(_hip_src).origin)
		var d_dst := _dst_to_rig.basis.inverse() * (d_rig * _hip_scale)
		var rest := dst.get_bone_rest(_hip_dst).origin
		var parent := dst.get_bone_parent(_hip_dst)
		var pq := glob[parent] if parent >= 0 else Quaternion.IDENTITY
		dst.set_bone_pose_position(_hip_dst, rest + pq.inverse() * d_dst)
