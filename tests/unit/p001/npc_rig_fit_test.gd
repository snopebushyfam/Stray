## Unit test (R12.3): the exported MakeHuman NPC rigs must be fitted to their own bodies.
## R12-R12.2 shipped the MPFB default joint positions for every NPC (build without joint helpers):
## shoulders and neck pivoted around wrong joints, which made the bouncer look monstrous.
## Checks per NPC: head joint at 88-94 % of body height, shoulder joint inside the shoulder line,
## and different bodies have different skeletons.
## Run: godot --headless --path . -s res://tests/unit/p001/npc_rig_fit_test.gd
extends SceneTree

const IDS := ["passerby_m", "passerby_f", "bouncer"]
const HEAD_RATIO_MIN := 0.88  # anatomy: head joint (top of neck) ~0.9 of standing height
const HEAD_RATIO_MAX := 0.94
const SHOULDER_RATIO_MAX := 0.125  # shoulder joint half-width / height upper bound (sanity check)

var _failed := 0
var _passed := 0


func check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
		print("PASS ", what)
	else:
		_failed += 1
		print("FAIL ", what)


func _initialize() -> void:
	_run.call_deferred()


func _bind_pos(skin: Skin, bone: String) -> Vector3:
	for i in skin.get_bind_count():
		if skin.get_bind_name(i) == bone:
			return skin.get_bind_pose(i).affine_inverse().origin
	return Vector3.ZERO


func _run() -> void:
	var heads := {}
	for id in IDS:
		var n: Node = (load("res://assets/characters/r12_npc/%s.glb" % id) as PackedScene).instantiate()
		root.add_child(n)
		var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
		var mi: MeshInstance3D = n.find_children("*", "MeshInstance3D", true, false)[0]
		var top := -INF
		for v: Vector3 in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			top = maxf(top, v.y)
		# Joint positions in the mesh's bind space (skin bind poses), so mesh and joints compare 1:1.
		var head_y := _bind_pos(mi.skin, "head").y
		var arm_x := absf(_bind_pos(mi.skin, "upperarm_l").x)
		var r := head_y / top
		check(r > HEAD_RATIO_MIN and r < HEAD_RATIO_MAX, "%s head joint at %.3f of body height %.2f m" % [id, r, top])
		check(arm_x / top < SHOULDER_RATIO_MAX, "%s shoulder joint half-width %.3f m fits body" % [id, arm_x])
		heads[id] = head_y
		n.queue_free()
	check(absf(float(heads["bouncer"]) - float(heads["passerby_f"])) > 0.1, "bouncer and passer-by (f) have different skeletons")
	print("RESULT npc_rig_fit_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
