## R12.4 evidence: the player figure in the real game, seen through the player camera at night:
## standing, walking, jogging (run) and mid-jump.
##   xvfb-run godot --path . -s res://tools/character/r12_player_shots.gd -- <out_dir> [r10]
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _shot(dir: String, name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("SHOT ", name)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else "user://"
	DirAccess.make_dir_recursive_absolute(dir)
	var m: Node = load("res://src/p001/main.tscn").instantiate()
	root.add_child(m)
	for i in 60:
		await process_frame
	if m.menu:
		m.menu.hide_menu()
	paused = false
	var p: StrayPlayer = m.player
	if "r10" in args:
		p.set_character_variant("r10")
	print("STRAY_DIAG variant=", p.character_variant)
	for i in 30:
		await process_frame
	await _shot(dir, "1_idle")
	Input.action_press("move_forward")
	for i in 50:
		await process_frame
	await _shot(dir, "2_walk")
	Input.action_press("run")
	for i in 50:
		await process_frame
	await _shot(dir, "3_jog")
	Input.action_press("jump")
	for i in 8:
		await process_frame
	Input.action_release("jump")
	await _shot(dir, "4_jump")
	Input.action_release("run")
	Input.action_release("move_forward")
	print("STRAY_DIAG anim=", p.anim_state)
	quit(0)
