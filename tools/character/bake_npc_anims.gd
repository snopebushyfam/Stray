## R12 / R12.2: bakes the CC0 Quaternius UAL animations onto each NPC rig ONCE (offline), using the
## runtime retarget (StrayHumanRig, incl. the R12.1 anatomy fixes) as the sampler, then applies a
## bake-time "motion polish" (R12.2) to the sampled human pose. Result:
## assets/characters/r12_npc/<id>_anims.res - plain bone tracks, no runtime skeleton or IK.
##   godot --headless --path . -s res://tools/character/bake_npc_anims.gd
##
## Motion polish (measured causes, docs/R12_2_NATURAL_MOTION.md; values in npc_specs.json "motion"):
## - stance: the UAL Idle stands with feet at ~2x hip width -> feet moved inward (two-bone leg IK,
##   foot orientation kept), knees straightened by raising the pelvis to a target knee angle.
## - lean: UAL leans the trunk 8-11 deg forward -> spine_01 rotated back; head_back undoes the
##   +10 deg head-forward offset that comes from MakeHuman's different neck/head rest.
## - life: the source idle hardly moves (pelvis 1 cm) -> idle baked over 2 source cycles with a slow
##   weight shift (pelvis sway, legs re-solved so feet stay planted), breathing and a small head turn.
## - gestures: Idle_Talking arms blended towards the Idle arms (gesture_scale) for calmer talking.
## - walk speed: the stance-foot speed of the baked walk is measured and stored as library meta
##   "walk_natural_speed" (pedestrians scale playback with it -> no foot sliding).
extends SceneTree

const UAL := "res://assets/characters/quaternius_ual/UAL1_Standard.glb"
const DIR := "res://assets/characters/r12_npc/"
const NPCS := ["passerby_m", "passerby_f", "bouncer", "player"]
## Default clip set; a type may list its own in npc_specs.json "anims" (R12.4: the player needs
## Idle, Walk, Jog_Fwd and Jump).
const ANIMS := ["Idle", "Walk", "Idle_Talking"]
const FPS := 30.0
const MM := preload("res://tools/character/motion_metrics.gd")
const ARM := ["clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r"]

var rig: StrayHumanRig
var sk: Skeleton3D
var src_cache := {}
## R12.4: mean local rotation of thighs/calves over the clip being baked (leg_swing_scale).
var leg_mean := {}
## R12.4: lowest ankle height of the clip being baked (ground contact level, flight_cm).
var leg_ground := 0.0


func _initialize() -> void:
	_run.call_deferred()


## Poses the driver at `time` of `a` (tracks evaluated directly) and retargets onto the human.
func _sample(a: String, time: float) -> void:
	var src_anim: Animation = rig.anim.get_animation(a)
	if not src_cache.has(a):
		var tracks := []
		for t in src_anim.get_track_count():
			var bone := rig.src.find_bone(String(src_anim.track_get_path(t).get_concatenated_subnames()))
			if bone >= 0:
				tracks.append([t, bone, src_anim.track_get_type(t)])
		src_cache[a] = tracks
	for st in src_cache[a]:
		if st[2] == Animation.TYPE_ROTATION_3D:
			rig.src.set_bone_pose_rotation(st[1], src_anim.rotation_track_interpolate(st[0], time))
		elif st[2] == Animation.TYPE_POSITION_3D:
			rig.src.set_bone_pose_position(st[1], src_anim.position_track_interpolate(st[0], time))
		elif st[2] == Animation.TYPE_SCALE_3D:
			rig.src.set_bone_pose_scale(st[1], src_anim.scale_track_interpolate(st[0], time))
	rig.src.force_update_all_bone_transforms()  # global poses are cached until the next skeleton update
	rig.retarget()
	sk.force_update_all_bone_transforms()


func _gq(b: int) -> Quaternion:
	return sk.get_bone_global_pose(b).basis.get_rotation_quaternion()


func _gp(b: int) -> Vector3:
	return sk.get_bone_global_pose(b).origin


## Rotates bone `b` by a skeleton-space rotation about its own joint (children follow).
func _rotate_world(b: int, r: Quaternion) -> void:
	var p := sk.get_bone_parent(b)
	var pq := _gq(p) if p >= 0 else Quaternion.IDENTITY
	sk.set_bone_pose_rotation(b, ((pq.inverse() * r * pq) * sk.get_bone_pose_rotation(b)).normalized())
	sk.force_update_all_bone_transforms()


## Two-bone IK: places the ankle of thigh->calf->foot at `target`, keeps the knee plane and the
## foot's skeleton-space rotation `foot_q`.
func _leg_ik(side: String, target: Vector3, foot_q: Quaternion) -> void:
	var th := sk.find_bone("thigh_" + side)
	var ca := sk.find_bone("calf_" + side)
	var fo := sk.find_bone("foot_" + side)
	var h := _gp(th)
	var k := _gp(ca)
	var a := _gp(fo)
	var l1 := h.distance_to(k)
	var l2 := k.distance_to(a)
	var to_t := target - h
	var d := clampf(to_t.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var n := (k - h).cross(a - h)
	if n.length() < 1e-5:
		n = Vector3.RIGHT  # straight leg: knees bend forward (+Z), axis = lateral
	n = n.normalized()
	var alpha := acos(clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0))
	var dir := to_t.normalized()
	var k1 := h + dir.rotated(n, alpha) * l1
	var k2 := h + dir.rotated(n, -alpha) * l1
	var k_new := k1 if k1.distance_to(k) < k2.distance_to(k) else k2
	var a_new := h + dir * d
	_rotate_world(th, Quaternion((k - h).normalized(), (k_new - h).normalized()))
	var k_cur := _gp(ca)
	var a_cur := _gp(fo)
	_rotate_world(ca, Quaternion((a_cur - k_cur).normalized(), (a_new - k_cur).normalized()))
	var cq := _gq(ca)
	sk.set_bone_pose_rotation(fo, (cq.inverse() * foot_q).normalized())
	sk.force_update_all_bone_transforms()


## Bake-time motion polish of the current human pose. `t` = bake time, `T` = bake clip length.
func _polish(m: Dictionary, t: float, T: float, raise: float, idle_arms: Dictionary) -> void:
	var pel := sk.find_bone("pelvis")
	# 1) calmer gestures: arms towards the idle pose at the same moment
	if not idle_arms.is_empty():
		var g: float = m.get("gesture_scale", 1.0)
		for bn in ARM:
			var b := sk.find_bone(bn)
			sk.set_bone_pose_rotation(b, (idle_arms[b] as Quaternion).slerp(sk.get_bone_pose_rotation(b), g))
		sk.force_update_all_bone_transforms()
	# 1b) jog (R12.4): upper arms towards hanging (idle) while the elbows stay bent; shorter strides
	#     (thighs/calves towards their clip mean) with the lowest foot kept at the source height.
	if m.has("upperarm_to_idle") and not idle_arms.is_empty():
		for bn in ["clavicle_l", "upperarm_l", "clavicle_r", "upperarm_r"]:
			var b := sk.find_bone(bn)
			sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b).slerp(idle_arms[b], float(m.upperarm_to_idle)))
		sk.force_update_all_bone_transforms()
	if m.has("leg_swing_scale") and not leg_mean.is_empty():
		var low0 := minf(_gp(sk.find_bone("foot_l")).y, _gp(sk.find_bone("foot_r")).y)
		for b in leg_mean:
			sk.set_bone_pose_rotation(b, (leg_mean[b] as Quaternion).slerp(sk.get_bone_pose_rotation(b), float(m.leg_swing_scale)))
		sk.force_update_all_bone_transforms()
		var low1 := minf(_gp(sk.find_bone("foot_l")).y, _gp(sk.find_bone("foot_r")).y)
		# The source "jog" floats up to ~25 cm in its flight phase; real jogging ~5 cm.
		if m.has("flight_cm"):
			low0 = minf(low0, leg_ground + float(m.flight_cm) * 0.01)
		var pel0 := sk.find_bone("pelvis")
		var pp0 := sk.get_bone_parent(pel0)
		var pq0 := _gq(pp0) if pp0 >= 0 else Quaternion.IDENTITY
		sk.set_bone_pose_position(pel0, sk.get_bone_pose_position(pel0) + pq0.inverse() * Vector3(0, low0 - low1, 0))
		sk.force_update_all_bone_transforms()
	# 2) remember planted feet (after retarget, before body changes)
	var feet := {}
	for s in ["l", "r"]:
		var fo := sk.find_bone("foot_" + s)
		feet[s] = [_gp(fo), _gq(fo)]
	# 3) pelvis: raise (straighter knees) + slow weight shift (one sway cycle per clip)
	var w := TAU * t / T
	var sway: float = m.get("sway_cm", 0.0) * 0.01 * sin(w)
	var bob: float = m.get("sway_cm", 0.0) * 0.002 * (1.0 - cos(2.0 * w))  # dip when weight passes centre
	var pp := sk.get_bone_parent(pel)
	var pq := _gq(pp) if pp >= 0 else Quaternion.IDENTITY
	sk.set_bone_pose_position(pel, sk.get_bone_pose_position(pel) + pq.inverse() * Vector3(sway, raise - bob, 0.0))
	sk.force_update_all_bone_transforms()
	if m.get("sway_cm", 0.0) > 0.0:
		_rotate_world(pel, Quaternion(Vector3.BACK, deg_to_rad(-1.2) * sin(w)))  # hip drops on the free side
	# 4) upright trunk, breathing, head
	var breath := sin(TAU * t * float(m.get("breaths_per_clip", 0.0)) / T)
	_rotate_world(sk.find_bone("spine_01"), Quaternion(Vector3.RIGHT, deg_to_rad(-float(m.get("lean_back_deg", 0.0)))))
	_rotate_world(sk.find_bone("spine_03"), Quaternion(Vector3.RIGHT, deg_to_rad(-0.8 * breath)))
	var head := sk.find_bone("head")
	_rotate_world(head, Quaternion(Vector3.RIGHT, deg_to_rad(-float(m.get("head_back_deg", 0.0)))))
	_rotate_world(head, Quaternion(Vector3.UP, deg_to_rad(float(m.get("head_turn_deg", 0.0)) * sin(w + 0.7))))
	# 5) feet: inward to the target stance, planted; legs re-solved
	var narrow: float = m.get("stance_scale", 1.0)
	for s in ["l", "r"]:
		var p0: Vector3 = feet[s][0]
		var tgt := Vector3(p0.x * narrow, p0.y, p0.z)
		if narrow != 1.0 or raise != 0.0 or m.get("sway_cm", 0.0) > 0.0:
			_leg_ik(s, tgt, feet[s][1])


## Lowest ankle height over clip `a` (source pose, 24 samples).
func _lowest_ankle(a: String) -> float:
	var L := rig.anim.get_animation(a).length
	var low := INF
	for k in 24:
		_sample(a, L * k / 24.0)
		low = minf(low, minf(_gp(sk.find_bone("foot_l")).y, _gp(sk.find_bone("foot_r")).y))
	return low


## Mean local rotation of `bones` over clip `a` (sign-aligned quaternion average).
func _bone_mean(a: String, bones: Array) -> Dictionary:
	var L := rig.anim.get_animation(a).length
	var out := {}
	var acc := {}
	for k in 12:
		_sample(a, L * k / 12.0)
		for bn in bones:
			var b := sk.find_bone(bn)
			var q := sk.get_bone_pose_rotation(b)
			if acc.has(b):
				var s: Quaternion = acc[b]
				if s.dot(q) < 0.0:
					q = -q
				acc[b] = Quaternion(s.x + q.x, s.y + q.y, s.z + q.z, s.w + q.w)
			else:
				acc[b] = q
	for b in acc:
		out[b] = (acc[b] as Quaternion).normalized()
	return out


## Pelvis raise (m) that brings the mean knee angle of clip `a` to `knee_deg` (narrowed feet).
func _raise_for(a: String, m: Dictionary) -> float:
	if not m.has("knee_deg"):
		return 0.0
	var L := rig.anim.get_animation(a).length
	var total := 0.0
	var n := 0
	for k in 6:
		_sample(a, L * k / 6.0)
		for s in ["l", "r"]:
			var th := sk.find_bone("thigh_" + s)
			var h := _gp(th)
			var kn := _gp(sk.find_bone("calf_" + s))
			var an := _gp(sk.find_bone("foot_" + s))
			var l1 := h.distance_to(kn)
			var l2 := kn.distance_to(an)
			var tgt := Vector3(an.x * float(m.get("stance_scale", 1.0)), an.y, an.z)
			var horiz := Vector2(tgt.x - h.x, tgt.z - h.z).length()
			var dt := sqrt(l1 * l1 + l2 * l2 + 2.0 * l1 * l2 * cos(deg_to_rad(float(m.knee_deg))))
			var need := sqrt(maxf(dt * dt - horiz * horiz, 0.0)) - (h.y - tgt.y)
			total += need
			n += 1
	# Mean, not min: the min left the knees bent (8 mm raise). The IK clamps overextension.
	return maxf(total / maxf(n, 1), 0.0)


func _run() -> void:
	var specs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/character/npc_specs.json"))
	for id in NPCS:
		var spec: Dictionary = specs.get("npcs", {}).get(String(id), {})
		rig = StrayHumanRig.new()
		# Per-type retarget tuning (R12.1): npc_specs.json -> npcs.<id>.retarget
		var rt: Dictionary = spec.get("retarget", {})
		for k in rt:
			rig.set(k, rt[k])
		root.add_child(rig)
		if not rig.setup(load(DIR + String(id) + ".glb"), load(UAL)):
			push_error("bake: setup failed for " + id)
			continue
		rig.anim.stop()
		sk = rig.dst
		src_cache.clear()
		var motion: Dictionary = specs.get("motion", {})
		var base_path := String(rig.human.get_path_to(sk))
		var lib := AnimationLibrary.new()
		for a in spec.get("anims", ANIMS):
			var m: Dictionary = (motion.get(a, {}) as Dictionary).merged(spec.get("motion", {}).get(a, {}), true)
			var L := rig.anim.get_animation(a).length
			var T := L * float(m.get("cycles", 1))
			var raise := _raise_for(a, m)
			leg_mean = _bone_mean(a, ["thigh_l", "thigh_r", "calf_l", "calf_r"]) if m.has("leg_swing_scale") else {}
			leg_ground = _lowest_ankle(a)
			var anim := Animation.new()
			anim.length = T
			# NPC clips always loop; extra clips (Jog_Fwd, Jump) keep the source loop mode.
			anim.loop_mode = Animation.LOOP_LINEAR if a in ANIMS else rig.anim.get_animation(a).loop_mode
			var rot_tracks := {}
			for b in sk.get_bone_count():
				var tr := anim.add_track(Animation.TYPE_ROTATION_3D)
				anim.track_set_path(tr, NodePath("%s:%s" % [base_path, sk.get_bone_name(b)]))
				rot_tracks[b] = tr
			var hip := sk.find_bone("pelvis")
			var pos_track := anim.add_track(Animation.TYPE_POSITION_3D)
			anim.track_set_path(pos_track, NodePath("%s:pelvis" % base_path))
			var frames := int(ceil(T * FPS))
			for f in frames + 1:
				var time := minf(f / FPS, T)
				var idle_arms := {}
				if m.has("gesture_scale") or m.has("upperarm_to_idle"):
					_sample("Idle", fmod(time, rig.anim.get_animation("Idle").length))
					for bn in ARM:
						var b := sk.find_bone(bn)
						idle_arms[b] = sk.get_bone_pose_rotation(b)
				_sample(a, fmod(time, L) if time < T else L)
				if not m.is_empty():
					_polish(m, time, T, raise, idle_arms)
				for b in sk.get_bone_count():
					anim.rotation_track_insert_key(rot_tracks[b], time, sk.get_bone_pose_rotation(b))
				anim.position_track_insert_key(pos_track, time, sk.get_bone_pose_position(hip))
			# Drop redundant keys (static fingers etc.). Third argument is an INT precision: passing 0.01
			# (-> 0) collapsed every track to one key in the first bake.
			anim.optimize(0.005, 0.005, 3)
			lib.add_animation(a, anim)
			print("BAKE %s %s len=%.2fs pelvis_raise=%.3fm polish=%s" % [id, a, T, raise, not m.is_empty()])
		# Measured stance-foot speed of the baked walk -> playback scaling without foot sliding.
		var n: Node3D = load(DIR + String(id) + ".glb").instantiate()
		var ap := AnimationPlayer.new()
		n.add_child(ap)
		ap.add_animation_library("", lib)
		root.add_child(n)
		var nsk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
		var wm: Dictionary = MM.measure(n, nsk, ap, "Walk", 120)
		lib.set_meta("walk_natural_speed", snappedf(float(wm.plant_speed), 0.01))
		# R12.4: every locomotion clip's stance-foot speed (the player also scales Jog_Fwd with it).
		var nat := {"Walk": lib.get_meta("walk_natural_speed")}
		if lib.has_animation("Jog_Fwd"):
			nat["Jog_Fwd"] = snappedf(float(MM.measure(n, nsk, ap, "Jog_Fwd", 90).plant_speed), 0.01)
		lib.set_meta("natural_speed", nat)
		n.queue_free()
		var out: String = DIR + String(id) + "_anims.res"
		var err := ResourceSaver.save(lib, out, ResourceSaver.FLAG_COMPRESS)
		print("BAKE %s natural_speed=%s err=%d" % [id, lib.get_meta("natural_speed"), err])
		rig.queue_free()
		await process_frame
	quit(0)
