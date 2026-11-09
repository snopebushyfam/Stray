## Integration test (R11): the optional MakeHuman player figure - default stays R10, switching to
## R11 animates the human skeleton (walk), feet stay near the ground, the choice is saved, and
## switching back restores R10. Run: godot --headless --path . -s res://tests/integration/p001/character_variant_test.gd
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


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var m: Node = load("res://src/p001/main.tscn").instantiate()
	m.save_path = PATH
	root.add_child(m)
	await _frames(30)
	var p: StrayPlayer = m.player
	check(p.character_variant == "r10" and not (p._visual.get_node("Character") is StrayHumanRig), "default figure is R10")
	p.set_character_variant("r11")
	await _frames(5)
	var rig := p._visual.get_node("Character") as StrayHumanRig
	check(rig != null and rig.mapped_bones >= 20, "R11 figure loaded (%d mapped bones)" % (rig.mapped_bones if rig else 0))
	Input.action_press("move_forward")
	await _frames(60)
	check(p.anim_state == "walk" and rig.anim.current_animation == "Walk", "walk animation plays on R11 (%s)" % p.anim_state)
	var sk := rig.dst
	var thigh := sk.find_bone("thigh_l")
	var moved := not sk.get_bone_pose_rotation(thigh).is_equal_approx(sk.get_bone_rest(thigh).basis.get_rotation_quaternion())
	check(moved, "human thigh is animated (not frozen in rest pose)")
	var feet_ok := true
	var lowest := INF
	for i in 30:
		await process_frame
		for b in ["foot_l", "foot_r"]:
			var y := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b))).origin.y - (p.global_position.y - 0.9)
			lowest = minf(lowest, y)
			if y < -0.08 or y > 0.45:
				feet_ok = false
	check(feet_ok and lowest < 0.2, "feet stay near the ground while walking (lowest ankle %.2f m)" % lowest)
	Input.action_release("move_forward")
	check(m.save_game("test"), "saved with R11")
	p.set_character_variant("r10")
	check(m.load_game() and p.character_variant == "r11", "R11 choice restored by loading")
	p.set_character_variant("r10")
	await _frames(5)
	check(not (p._visual.get_node("Character") is StrayHumanRig) and p._anim != null, "back to R10 with its animations")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("RESULT character_variant_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
