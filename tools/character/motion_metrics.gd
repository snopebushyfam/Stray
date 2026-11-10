## R12.2 motion metrics: samples an animation on a skeleton and prints posture/motion numbers so the
## source (Quaternius UAL mannequin) and the baked NPC animations can be compared objectively.
##   godot --headless --path . -s res://tools/character/motion_metrics.gd
## Model space: +Y up, model faces +Z. All lengths in metres, angles in degrees.
extends SceneTree

const UAL := "res://assets/characters/quaternius_ual/UAL1_Standard.glb"


func _initialize() -> void:
	_run.call_deferred()


static func _wp(sk: Skeleton3D, root: Node3D, b: String) -> Vector3:
	var i := sk.find_bone(b)
	if i < 0:
		for k in sk.get_bone_count():
			if sk.get_bone_name(k).to_lower() == b.to_lower():
				i = k
	return root.global_transform.affine_inverse() * (sk.global_transform * sk.get_bone_global_pose(i)).origin


static func _sag(v: Vector3) -> float:
	# forward lean of a vector in the sagittal plane (deg), + = towards +Z (front)
	return rad_to_deg(atan2(v.z, v.y))


## Returns a Dictionary of metrics for animation `a` on (root, sk, ap).
static func measure(root: Node3D, sk: Skeleton3D, ap: AnimationPlayer, a: String, samples: int = 60) -> Dictionary:
	var anim := ap.get_animation(a)
	ap.play(a)
	var L := anim.length
	var hip_w := 0.0
	var st := 0.0
	var lean := 0.0
	var neck := 0.0
	var knee := 0.0
	var mn := {}
	var mx := {}
	var arm_min := INF
	var arm_max := -INF
	var foot_min_y := INF
	var feet := []
	for k in samples:
		ap.seek(L * k / samples, true)
		sk.force_update_all_bone_transforms()
		var p := {}
		for b in ["pelvis", "neck_01", "head", "thigh_l", "thigh_r", "calf_l", "foot_l", "foot_r", "hand_l", "hand_r", "upperarm_l"]:
			p[b] = _wp(sk, root, b)
		hip_w += absf(p.thigh_l.x - p.thigh_r.x)
		st += absf(p.foot_l.x - p.foot_r.x)
		lean += _sag(p.neck_01 - p.pelvis)
		neck += _sag(p.head - p.neck_01)
		knee += rad_to_deg((p.calf_l - p.thigh_l).angle_to(p.foot_l - p.calf_l))
		var av: Vector3 = p.hand_l - p.upperarm_l
		var arm := rad_to_deg(atan2(av.z, -av.y))  # 0 = hanging straight down, + = forward
		arm_min = minf(arm_min, arm)
		arm_max = maxf(arm_max, arm)
		for b in ["head", "pelvis", "hand_l"]:
			mn[b] = (mn[b] as Vector3).min(p[b]) if mn.has(b) else p[b]
			mx[b] = (mx[b] as Vector3).max(p[b]) if mx.has(b) else p[b]
		foot_min_y = minf(foot_min_y, minf(p.foot_l.y, p.foot_r.y))
		feet.append([p.foot_l, p.foot_r])
	# Foot slide (in-place walk): backward speed of the planted foot (the lower one).
	var slide := 0.0
	var n_slide := 0
	var dt := L / samples
	for k in samples:
		var a0: Array = feet[k]
		var a1: Array = feet[(k + 1) % samples]
		for f in 2:
			if (a0[f] as Vector3).y < foot_min_y + 0.015:
				slide += -((a1[f] as Vector3).z - (a0[f] as Vector3).z) / dt
				n_slide += 1
	return {"stance_ratio": st / hip_w, "stance_m": st / samples, "lean_deg": lean / samples, "head_deg": neck / samples,
		"knee_deg": knee / samples, "arm_swing_deg": arm_max - arm_min,
		"head_move_cm": ((mx.head as Vector3) - (mn.head as Vector3)).length() * 100.0,
		"pelvis_sway_cm": ((mx.pelvis as Vector3) - (mn.pelvis as Vector3)).length() * 100.0,
		"hand_move_cm": ((mx.hand_l as Vector3) - (mn.hand_l as Vector3)).length() * 100.0,
		"plant_speed": slide / maxf(n_slide, 1), "length_s": L}


static func line(tag: String, m: Dictionary) -> String:
	return "%-24s stance %.2f (%.2fm) lean %+5.1f head %+5.1f knee %4.1f armswing %4.1f headmove %4.1fcm pelvis %4.1fcm hand %4.1fcm plant %.2fm/s len %.2fs" % [
		tag, m.stance_ratio, m.stance_m, m.lean_deg, m.head_deg, m.knee_deg, m.arm_swing_deg, m.head_move_cm, m.pelvis_sway_cm, m.hand_move_cm, m.plant_speed, m.length_s]


func _run() -> void:
	var ual: Node3D = load(UAL).instantiate()
	root.add_child(ual)
	var usk: Skeleton3D = ual.find_children("*", "Skeleton3D", true, false)[0]
	var uap: AnimationPlayer = ual.find_children("*", "AnimationPlayer", true, false)[0]
	for a in ["Idle", "Idle_Talking", "Walk", "Walk_Formal", "Jog_Fwd"]:
		print("SRC ", line("UAL " + a, measure(ual, usk, uap, a)))
	for id in ["passerby_m", "passerby_f", "bouncer", "player"]:
		var n: Node3D = StrayNpcHuman.create(id)
		root.add_child(n)
		var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
		var ap: AnimationPlayer = n.get_node("AnimationPlayer")
		for a in ap.get_animation_list():
			print("NPC ", line(id + " " + a, measure(n, sk, ap, a)))
	quit(0)
