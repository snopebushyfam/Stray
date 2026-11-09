## Integration test (R12 NPC pilot): exactly three NPCs use the MakeHuman models - walker 0 on the
## Ring, queue person 0 at NACHTFLUG, the bouncer - with pre-baked animations that really move the
## skeleton; walker 0 still walks its lane; every other NPC stays R10; the bouncer still answers.
## Run: godot --headless --path . -s res://tests/integration/p001/npc_pilot_test.gd
extends SceneTree

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


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _type_of(n: Node) -> String:
	for c in n.find_children("*", "Node3D", true, false):
		if c.has_meta("npc_type"):
			return String(c.get_meta("npc_type"))
	return String(n.get_meta("npc_type", ""))


func _thigh_changes(n: Node) -> bool:
	var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
	var b := sk.find_bone("thigh_l")
	var q0 := sk.get_bone_pose_rotation(b)
	await _frames(20)
	return not sk.get_bone_pose_rotation(b).is_equal_approx(q0)


func _run() -> void:
	var m: Node = load("res://src/p001/main.tscn").instantiate()
	root.add_child(m)
	await _frames(30)
	var peds: StrayPedestrians = m.pedestrians
	var w0 = peds.walkers[0]
	check(_type_of(w0.root) == "passerby_m", "walker 0 is the R12 passer-by (%s)" % _type_of(w0.root))
	check(_type_of(peds.queue[0]) == "passerby_f", "queue person 0 is the R12 passer-by (f)")
	var bouncer: Node = m.interactions.get_node("Bouncer")
	check(_type_of(bouncer) == "bouncer", "bouncer is the R12 model")
	var others := 0
	for i in range(1, peds.walkers.size()):
		if _type_of(peds.walkers[i].root) == "":
			others += 1
	for i in range(1, peds.queue.size()):
		if _type_of(peds.queue[i]) == "":
			others += 1
	check(others == peds.walkers.size() - 1 + peds.queue.size() - 1, "all other NPCs stay R10 (%d)" % others)
	check(await _thigh_changes(w0.root), "walker 0 legs animate (baked Walk)")
	var qap: AnimationPlayer = peds.queue[0].find_children("*", "AnimationPlayer", true, false)[0]
	check(qap.is_playing() and qap.current_animation in ["Idle", "Idle_Talking"], "queue person plays %s" % qap.current_animation)
	var sk: Skeleton3D = bouncer.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = bouncer.find_children("*", "AnimationPlayer", true, false)[0]
	check(ap.is_playing() and ap.current_animation == "Idle", "bouncer plays Idle")
	var p0: Vector3 = w0.root.global_position
	await _frames(90)
	check(w0.root.global_position.distance_to(p0) > 0.5 or not w0.walking, "walker 0 moves along its lane (%.1f m)" % w0.root.global_position.distance_to(p0))
	# Feet on the ground: lowest foot bone of the walking passer-by within 0.25 m of its root.
	var wsk: Skeleton3D = w0.root.find_children("*", "Skeleton3D", true, false)[0]
	var low := INF
	for k in 30:
		await process_frame
		for bn in ["foot_l", "foot_r"]:
			low = minf(low, (wsk.global_transform * wsk.get_bone_global_pose(wsk.find_bone(bn))).origin.y - w0.root.global_position.y)
	check(low > -0.08 and low < 0.25, "walker 0 feet at ground level (lowest ankle %.2f m)" % low)
	# The bouncer interaction still works.
	m.player.global_position = m.interactions.points["club_door"] + Vector3(0, 0.95, 0)
	await _frames(15)
	m.interactions.interact()
	check(not m.interactions.last_door_result.is_empty() and m.ui.message_panel.visible, "bouncer answers (%s)" % m.interactions.last_door_result.get("reason", "-"))
	print("RESULT npc_pilot_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
