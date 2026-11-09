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
## R12.1 anatomy corrections (docs/R12_1_ANATOMY_REPAIR.md):
## - arm_adduction_deg: the UAL mannequin's bulky torso holds the arms ~20 deg out in Idle; slim
##   human bodies get the arms rotated towards the body by this amount (scaled by how far down
##   the arm points, so raised arms are unaffected).
## - clavicle_weight: share of the mannequin's clavicle motion transferred (its rest pose differs
##   by ~37 deg; the full motion rolled the human shoulders forward and down).
## - finger_flex: relaxed hand, flexion per joint (radians) for index/middle/ring/pinky, thumb.
var arm_adduction_deg := 12.0
var clavicle_weight := 0.4
## Extra flexion on top of MakeHuman's rest hand, which is already relaxed (~20 deg per finger);
## more than this read as claws in the R12.1 audit.
var finger_flex := {"index": [0.04, 0.06, 0.04], "middle": [0.06, 0.08, 0.05], "ring": [0.08, 0.10, 0.06],
	"pinky": [0.10, 0.12, 0.08], "thumb": [0.0, 0.04, 0.04]}
## Virtual T-pose rest (dst skeleton space): the bind pose may be MakeHuman's A-pose; limbs are
## aligned to the driver's rest directions here instead of baking a T-pose into the mesh.
var _vt_q: Array[Quaternion] = []
## Share of the rest finger spread removed (0 = MakeHuman rest, 1 = fingers parallel to the middle).
var finger_spread_reduce := 0.6
## Relaxed local rotations for finger bones (relative to their parent), from the palm normal.
var _finger_local: Dictionary = {}


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
	_build_virtual_tpose()
	_build_relaxed_fingers()
	_spaces_ready = true
	print("STRAY_DIAG human_rig hip_scale=%.3f" % _hip_scale)


const _ALIGN := {"upperarm_l": "lowerarm_l", "lowerarm_l": "hand_l", "hand_l": "middle_01_l",
	"upperarm_r": "lowerarm_r", "lowerarm_r": "hand_r", "hand_r": "middle_01_r",
	"thigh_l": "calf_l", "calf_l": "foot_l", "thigh_r": "calf_r", "calf_r": "foot_r"}


func _src_rest_dir_dst(a: String, b: String) -> Vector3:
	var ia := -1
	var ib := -1
	for i in src.get_bone_count():
		var nm := src.get_bone_name(i).to_lower()
		if nm == a: ia = i
		if nm == b: ib = i
	if ia < 0 or ib < 0:
		return Vector3.ZERO
	var d := src.get_bone_global_rest(ib).origin - src.get_bone_global_rest(ia).origin
	return (_dst_basis_q.inverse() * (_src_basis_q * d)).normalized()


static func _frame(a: Vector3, b: Vector3) -> Basis:
	var x := a.normalized()
	var y := (b - x * x.dot(b)).normalized()
	return Basis(x, y, x.cross(y))


## Palm normal of a rest pose (back of hand -> palm side is not assumed; same formula on both rigs:
## along x across, which keeps the two rigs consistent and mirrors correctly for l/r).
## `is_src`: vector from the driver rig, returned in dst skeleton space.
func _palm_rest(sk: Skeleton3D, side: String, is_src: bool) -> Vector3:
	var f := func(nm: String) -> Vector3:
		for i in sk.get_bone_count():
			if sk.get_bone_name(i).to_lower() == nm + side:
				return sk.get_bone_global_rest(i).origin
		return Vector3.ZERO
	var along: Vector3 = f.call("middle_01_") - f.call("hand_")
	var across: Vector3 = f.call("index_01_") - f.call("pinky_01_")
	var nrm := along.cross(across).normalized()
	if is_src:
		nrm = (_dst_basis_q.inverse() * (_src_basis_q * nrm)).normalized()
	return nrm


## Limb directions of the human rest pose are aligned to the driver's rest (T-pose arms, straight
## legs) by accumulating corrections parent -> child. Identity for an already matching rig.
func _build_virtual_tpose() -> void:
	var n := dst.get_bone_count()
	var corr: Array[Quaternion] = []
	corr.resize(n)
	_vt_q.resize(n)
	for i in _order:
		var p := dst.get_bone_parent(i)
		var c := corr[p] if p >= 0 else Quaternion.IDENTITY
		var nm := dst.get_bone_name(i).to_lower()
		if _ALIGN.has(nm):
			var ci := dst.find_bone(_ALIGN[nm])
			if ci >= 0:
				var d := (c * (dst.get_bone_global_rest(ci).origin - dst.get_bone_global_rest(i).origin)).normalized()
				var t := _src_rest_dir_dst(nm, _ALIGN[nm])
				var side := nm.right(1)
				if t != Vector3.ZERO and (nm.begins_with("hand_") or nm.begins_with("lowerarm_")):
					# Forearm and hand: align the full frame (bone direction + palm normal). The shortest
					# arc alone left MakeHuman's forward-turned A-pose palm twisted against the UAL palm.
					var n_dst := c * _palm_rest(dst, side, false)
					var n_src := _palm_rest(src, side, true)
					c = (_frame(t, n_src) * _frame(d, n_dst).inverse()).get_rotation_quaternion() * c
				elif t != Vector3.ZERO and d.dot(t) < 0.9999:
					c = Quaternion(d, t) * c
		corr[i] = c
		_vt_q[i] = (c * _dst_rest_q[i]).normalized()
	_dst_rest_q = _vt_q.duplicate()


## Relaxed fingers: flex each finger chain about the axis perpendicular to the finger and the palm
## normal (anatomical flexion, mirrored correctly for both hands - the fixed local axis of R11/R12
## bent one hand backwards).
func _build_relaxed_fingers() -> void:
	_finger_local.clear()
	for side in ["l", "r"]:
		var h := dst.find_bone("hand_" + side)
		var idx := dst.find_bone("index_01_" + side)
		var pk := dst.find_bone("pinky_01_" + side)
		var mid := dst.find_bone("middle_01_" + side)
		if h < 0 or idx < 0 or pk < 0 or mid < 0:
			continue
		var hq := _vt_q[h]
		var hr := dst.get_bone_global_rest(h)
		# Rest-space vectors rotated into the virtual T-pose by the hand's correction.
		var hc := hq * hr.basis.get_rotation_quaternion().inverse()
		var across := hc * (dst.get_bone_global_rest(idx).origin - dst.get_bone_global_rest(pk).origin)
		var along := hc * (dst.get_bone_global_rest(mid).origin - hr.origin)
		var palm := along.cross(across).normalized()
		if palm.y > 0.0:
			palm = -palm  # T-pose palms face down
		for f in ["index", "middle", "ring", "pinky", "thumb"]:
			var chain := []
			for k in [1, 2, 3]:
				var b := dst.find_bone("%s_0%d_%s" % [f, k, side])
				if b >= 0:
					chain.append(b)
			if chain.size() < 2:
				continue
			var b0: int = chain[0]
			var b1: int = chain[1]
			var fdir := hc * (dst.get_bone_global_rest(b1).origin - dst.get_bone_global_rest(b0).origin)
			var spread_q := Quaternion.IDENTITY
			if f != "thumb" and f != "middle":
				# Bring the finger towards the middle finger in the palm plane (less fan-like hand).
				var m1 := dst.find_bone("middle_02_" + side)
				var mdir := hc * (dst.get_bone_global_rest(m1).origin - dst.get_bone_global_rest(mid).origin)
				var a := (fdir - palm * palm.dot(fdir)).normalized()
				var b := (mdir - palm * palm.dot(mdir)).normalized()
				var ang := a.signed_angle_to(b, palm)
				spread_q = Quaternion(palm, ang * finger_spread_reduce)
				fdir = spread_q * fdir
			var axis := fdir.cross(palm).normalized()
			if f == "thumb":
				# Thumb flexes towards the index finger and slightly into the palm.
				axis = fdir.cross((palm * 0.6 + along.normalized() * 0.4).normalized()).normalized()
			var acc := 0.0
			var prev_global := hq
			var angles: Array = finger_flex[f]
			for k in chain.size():
				var b: int = chain[k]
				acc += float(angles[mini(k, angles.size() - 1)])
				var g := (Quaternion(axis, acc) * spread_q * _vt_q[b]).normalized()
				_finger_local[b] = (prev_global.inverse() * g).normalized()
				prev_global = g


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
## Rotation (about the character's forward axis) that brings a hanging upper arm closer to the body.
func _adduction(g_upper: Quaternion, i: int) -> Quaternion:
	var nm := dst.get_bone_name(i).to_lower()
	var child := dst.find_bone(_ALIGN.get(nm, ""))
	if child < 0:
		return Quaternion.IDENTITY
	var rest_dir := (_vt_q[i] * dst.get_bone_global_rest(i).basis.get_rotation_quaternion().inverse()) \
		* (dst.get_bone_global_rest(child).origin - dst.get_bone_global_rest(i).origin)
	var d := (g_upper * _vt_q[i].inverse() * rest_dir).normalized()
	var down := _dst_basis_q.inverse() * Vector3.DOWN
	var fwd := _dst_basis_q.inverse() * Vector3.BACK  # model front is +Z
	var hang := clampf(d.dot(down), 0.0, 1.0)
	if hang <= 0.0:
		return Quaternion.IDENTITY
	var a := deg_to_rad(arm_adduction_deg) * hang
	var qa := Quaternion(fwd, a)
	var qb := Quaternion(fwd, -a)
	return qa if (qa * d).dot(down) > (qb * d).dot(down) else qb


func retarget() -> void:
	if not _spaces_ready:
		_init_spaces()
	var glob: Array[Quaternion] = []
	glob.resize(dst.get_bone_count())
	var arm_corr := {}
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
			var nm := dst.get_bone_name(i).to_lower()
			if nm.begins_with("clavicle"):
				delta_dst = Quaternion.IDENTITY.slerp(delta_dst, clavicle_weight)
			g = delta_dst * _dst_rest_q[i]
			var side := nm.right(1)
			if nm.begins_with("upperarm_") and arm_adduction_deg > 0.0:
				arm_corr[side] = _adduction(g, i)
			if arm_corr.has(side) and (nm.begins_with("upperarm_") or nm.begins_with("lowerarm_") or nm.begins_with("hand_")):
				g = arm_corr[side] * g
		else:
			var local_q: Quaternion = _finger_local.get(i, dst.get_bone_rest(i).basis.get_rotation_quaternion())
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
