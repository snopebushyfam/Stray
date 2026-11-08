## Prototype 001 entry scene: builds the street, spawns the player, adds HUD + touch controls.
##
## Command-line (after "--"):
##   --autoshots            capture evidence screenshots (player view + every layout viewpoint,
##                          night and day) and quit
##   --shots-dir=<dir>      where to write them (default res://production/qa/evidence/godot)
## Design: docs/STRAY_GDD.md (Prototype 001), docs/TECHNICAL_PLAN.md.
extends Node3D

const PLAYER_CONFIG := "res://data/p001/player_config.json"

var builder: StrayStreetBuilder
var player: StrayPlayer
var player_cfg: Dictionary = {}


func _ready() -> void:
	player_cfg = _load_json(PLAYER_CONFIG)
	register_input_actions(player_cfg.get("controls", {}))
	builder = StrayStreetBuilder.new()
	builder.name = "Street"
	add_child(builder)
	var stats := builder.build()
	if not stats.layout:
		push_error("STRAY_DIAG main=failed street not built")
		return
	player = StrayPlayer.new()
	player.name = "Player"
	player.setup(player_cfg)
	add_child(player)
	var half: float = float(player_cfg.get("capsule_height", 1.8)) * 0.5
	player.global_position = builder.layout.spawn_position(half, player_cfg.get("spawn_clearance", 0.05))
	player.face_yaw(builder.layout.spawn_yaw())
	player.camera.make_current()
	print("STRAY_DIAG spawn pos=%s yaw_deg=%.1f" % [player.global_position, rad_to_deg(builder.layout.spawn_yaw())])
	_build_hud()
	if "--autoshots" in OS.get_cmdline_user_args():
		_run_autoshots.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_day_night"):
		builder.set_day_mode(not builder.day_mode)


## Registers keyboard + gamepad bindings for the actions named in the player config.
static func register_input_actions(controls: Dictionary) -> void:
	for action in controls:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for key_name in controls[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = OS.find_keycode_from_string(key_name)
			InputMap.action_add_event(action, ev)
	var pad := {"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
		"move_forward": [JOY_AXIS_LEFT_Y, -1.0], "move_back": [JOY_AXIS_LEFT_Y, 1.0]}
	for action in pad:
		if InputMap.has_action(action):
			var j := InputEventJoypadMotion.new()
			j.axis = pad[action][0]
			j.axis_value = pad[action][1]
			InputMap.action_add_event(action, j)
	if InputMap.has_action("jump"):
		var b := InputEventJoypadButton.new()
		b.button_index = JOY_BUTTON_A
		InputMap.action_add_event("jump", b)


static func _load_json(path: String) -> Dictionary:
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v if typeof(v) == TYPE_DICTIONARY else {}


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)
	var info := Label.new()
	info.text = "STRAY · Prototyp 001 · Hohenzollernring, Köln (LoD2/DGM1 Geobasis NRW, © OSM)\n" \
		+ "WASD/Stick: gehen · Shift: rennen · Leertaste: springen · Maus: Kamera · N: Tag/Nacht"
	info.position = Vector2(12, 8)
	info.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	info.add_theme_font_size_override("font_size", 14)
	hud.add_child(info)
	var touch := DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	if touch:
		var joy := VirtualJoystick.new()
		joy.joystick_mode = VirtualJoystick.JOYSTICK_DYNAMIC
		joy.action_left = &"move_left"
		joy.action_right = &"move_right"
		joy.action_up = &"move_forward"
		joy.action_down = &"move_back"
		joy.anchor_top = 0.45
		joy.anchor_bottom = 1.0
		joy.anchor_right = 0.5
		hud.add_child(joy)
		var day := Button.new()
		day.text = "Tag/Nacht"
		day.position = Vector2(12, 60)
		day.pressed.connect(func(): builder.set_day_mode(not builder.day_mode))
		hud.add_child(day)
		var jump := Button.new()
		jump.text = "Springen"
		jump.anchor_left = 1.0
		jump.anchor_right = 1.0
		jump.anchor_top = 1.0
		jump.anchor_bottom = 1.0
		jump.offset_left = -150
		jump.offset_top = -90
		jump.offset_right = -20
		jump.offset_bottom = -20
		jump.button_down.connect(func(): Input.action_press("jump"))
		jump.button_up.connect(func(): Input.action_release("jump"))
		hud.add_child(jump)
	print("STRAY_DIAG hud touch_controls=%s" % touch)


# --------------------------------------------------------------------------------------------
# Evidence screenshots
# --------------------------------------------------------------------------------------------

func _shots_dir() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots-dir="):
			return a.trim_prefix("--shots-dir=")
	return ProjectSettings.globalize_path("res://production/qa/evidence/godot")


func _snap(dir: String, file_name: String) -> void:
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := dir.path_join(file_name)
	var err := img.save_png(path)
	print("STRAY_DIAG autoshot=%s err=%d size=%s" % [path, err, img.get_size()])


func _run_autoshots() -> void:
	var dir := _shots_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(1.5).timeout  # let physics settle (ground check at frame 30)
	await _snap(dir, "P001_00_player_spawn_night.png")
	var cam := Camera3D.new()
	cam.fov = 75.0
	add_child(cam)
	for day in [false, true]:
		builder.set_day_mode(day)
		var idx := 1
		for vp in builder.layout.viewpoints:
			var eye := Vector2(vp["en"][0], vp["en"][1])
			var look := Vector2(vp["look_en"][0], vp["look_en"][1])
			var e3 := StrayStreetLayout.en_to_godot(eye.x, eye.y, builder.layout.ground_z_at(eye) + float(vp["h"]))
			var l3 := StrayStreetLayout.en_to_godot(look.x, look.y, builder.layout.ground_z_at(look) + float(vp["look_h"]))
			cam.global_position = e3
			cam.look_at(l3, Vector3.UP)
			cam.make_current()
			await _snap(dir, "P001_%02d_%s_%s.png" % [idx, vp["name"], "day" if day else "night"])
			idx += 1
	builder.set_day_mode(false)
	print("STRAY_DIAG autoshots=done dir=%s" % dir)
	get_tree().quit()
