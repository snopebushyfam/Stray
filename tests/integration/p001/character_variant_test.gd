## Integration test (R11, R12.4): the MakeHuman player figure is the default ("human": fitted rig,
## baked animations); walking/running play the baked clips and move the skeleton, feet stay near
## the ground, the choice is saved, R10 can be selected and restored, old "r11" saves load "human". Run: godot --headless --path . -s res://tests/integration/p001/character_variant_test.gd
extends SceneTree

const PATH := "user://test_character_variant.json"
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
		await process_frame


func _skel(p: StrayPlayer) -> Skeleton3D:
	return p._visual.get_node("Character").find_children("*", "Skeleton3D", true, false)[0]


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var m: Node = load("res://src/p001/main.tscn").instantiate()
	m.save_path = PATH
	root.add_child(m)
	await _frames(30)
	var p: StrayPlayer = m.player
	var ch: Node = p._visual.get_node("Character")
	check(p.character_variant == "human" and String(ch.get_meta("npc_type", "")) == "player", "default figure is the human player model")
	check(p._anim != null and p._anim.has_animation("Jog_Fwd") and p._anim.has_animation("Jump"), "baked Idle/Walk/Jog_Fwd/Jump present")
	Input.action_press("move_forward")
	await _frames(60)
	check(p.anim_state == "walk" and p._anim.current_animation == "Walk", "walk animation plays (%s)" % p.anim_state)
	var sk := _skel(p)
	var thigh := sk.find_bone("thigh_l")
	var q0 := sk.get_bone_pose_rotation(thigh)
	var feet_ok := true
	var lowest := INF
	for i in 30:
		await process_frame
		for b in ["foot_l", "foot_r"]:
			var y := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b))).origin.y - (p.global_position.y - 0.9)
			lowest = minf(lowest, y)
			if y < -0.08 or y > 0.45:
				feet_ok = false
	check(not sk.get_bone_pose_rotation(thigh).is_equal_approx(q0), "human thigh is animated (not frozen)")
	check(feet_ok and lowest < 0.2, "feet stay near the ground while walking (lowest ankle %.2f m)" % lowest)
	Input.action_release("move_forward")
	p.set_character_variant("r10")
	await _frames(5)
	check(p.character_variant == "r10" and not p._visual.get_node("Character").has_meta("npc_type") and p._anim != null, "R10 figure selectable with its animations")
	check(m.save_game("test"), "saved with R10")
	p.set_character_variant("human")
	check(m.load_game() and p.character_variant == "r10", "R10 choice restored by loading")
	p.set_character_variant("r11")
	await _frames(5)
	check(p.character_variant == "human", "old R11 choice maps to the human figure")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("RESULT character_variant_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
