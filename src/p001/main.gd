## Prototype 001 entry scene: builds the street, spawns the player, adds HUD + touch controls.
##
## Command-line (after "--"):
##   --autoshots            capture evidence screenshots (player view + every layout viewpoint,
##                          night and day) and quit
##   --shots-dir=<dir>      where to write them (default res://production/qa/evidence/godot)
## Design: docs/STRAY_GDD.md (Prototype 001), docs/TECHNICAL_PLAN.md.
extends Node3D

const PLAYER_CONFIG := "res://data/p001/player_config.json"
const AUDIO_CONFIG := "res://data/p001/audio_config.json"
const NPC_CONFIG := "res://data/p001/npc_config.json"
const ECONOMY_CONFIG := "res://data/p001/economy_config.json"
const PHONE_CONFIG := "res://data/p001/phone_config.json"
const CLUB_CONFIG := "res://data/p001/club_interior.json"

var builder: StrayStreetBuilder
var player: StrayPlayer
var player_cfg: Dictionary = {}
var city_audio: AudioStreamPlayer
var club_audio: AudioStreamPlayer3D
var pedestrians: StrayPedestrians
var traffic: StrayTraffic
var ui: StrayUi
var interactions: StrayInteractions
var clock: StrayGameClock
var messages: StrayMessages
var phone: StrayPhone
var club: StrayClubInterior


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
	_build_audio()
	var npc_cfg := _load_json(NPC_CONFIG)
	pedestrians = StrayPedestrians.new()
	pedestrians.name = "Pedestrians"
	add_child(pedestrians)
	pedestrians.setup(builder.layout, npc_cfg, player_cfg.get("character", {}), player)
	traffic = StrayTraffic.new()
	traffic.name = "Traffic"
	add_child(traffic)
	traffic.setup(builder.layout, npc_cfg, player)
	_build_hud()
	ui = StrayUi.new()
	ui.name = "LifeUi"
	add_child(ui)
	var phone_cfg := _load_json(PHONE_CONFIG)
	clock = StrayGameClock.new(phone_cfg.get("clock", {}))
	clock.hour_changed.connect(func(_h): _sync_daylight())
	_sync_daylight()
	interactions = StrayInteractions.new()
	interactions.name = "Interactions"
	interactions.clock = clock
	interactions.phone_cfg = phone_cfg
	club = StrayClubInterior.new()
	club.name = "ClubInterior"
	add_child(club)
	club.setup(_load_json(CLUB_CONFIG), player_cfg.get("character", {}))
	club.visible = false
	interactions.club = club
	add_child(interactions)
	interactions.setup(builder.layout, _load_json(ECONOMY_CONFIG), player, builder, ui, player_cfg.get("character", {}))
	_build_phone(phone_cfg)
	if "--autoshots" in OS.get_cmdline_user_args():
		_run_autoshots.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_day_night"):
		toggle_day_night()


## Debug / touch: jump the clock to the afternoon or to late night; lighting follows the clock.
func toggle_day_night() -> void:
	clock.set_time("23:30" if clock.is_daytime() else "14:00")
	_sync_daylight()


func _sync_daylight() -> void:
	if builder and builder.day_mode != clock.is_daytime():
		builder.set_day_mode(clock.is_daytime())


func _process(delta: float) -> void:
	if clock:
		clock.advance(delta)
		if ui and interactions and ui.clock_text != clock.hhmm():
			ui.clock_text = clock.hhmm()
			ui.set_status(interactions.life)


func _build_phone(phone_cfg: Dictionary) -> void:
	messages = StrayMessages.new(phone_cfg)
	var map := StrayPhoneMap.new()
	map.setup(builder.layout, builder.layout.resolve("LoD2_P001_Hohenzollernring.json"))
	var L := builder.layout
	map.markers.append({"en": StrayStreetLayout._v2(L.kiosk["en"]), "color": Color(0.2, 0.9, 0.4), "label": "KIOSK"})
	map.markers.append({"en": StrayStreetLayout._v2(L.club["en"]), "color": Color(1.0, 0.2, 0.7), "label": "NACHTFLUG"})
	for a in L.furniture.get("atms", []):
		map.markers.append({"en": StrayStreetLayout._v2(a["en"]), "color": Color(0.3, 0.6, 1.0), "label": "€"})
	phone = StrayPhone.new()
	phone.name = "Phone"
	add_child(phone)
	phone.setup(interactions.life, messages, clock, phone_cfg, map)
	phone.opened_changed.connect(func(open):
		player.input_enabled = not open and not interactions.shop_open
		ui.status_label.visible = not open)  # the phone covers the top-right HUD; it shows time + money itself
	messages.received.connect(func(m): if not phone.is_open: ui.show_message("📱 %s" % m.name, m.text, 5.0))
	interactions.club_admitted.connect(func(): messages.trigger("club_admitted", clock.hhmm()))
	interactions.club_entered.connect(_on_club_entered)
	interactions.club_left.connect(_on_club_left)
	interactions.lea_met.connect(func(reveal, lea_name):
		if reveal and messages.contacts.has("unbekannt"):
			messages.contacts["unbekannt"]["name"] = lea_name
			messages.contacts["unbekannt"]["known"] = true)
	interactions.life.cash_changed.connect(func(c): messages.check_cash(c, clock.hhmm()))
	messages.trigger("start", clock.hhmm())
	print("STRAY_DIAG phone clock=%s messages=%d contacts=%d account=%s" % [clock.hhmm(), messages.inbox.size(),
		messages.known_contacts().size(), StrayLifeState.euro(interactions.life.account_cents)])


func _on_club_entered() -> void:
	club_audio.stop()
	city_audio.volume_db -= 18.0
	club.music.play()


func _on_club_left() -> void:
	club.music.stop()
	city_audio.volume_db += 18.0
	club_audio.play()
	club.visible = false


func _physics_process(_delta: float) -> void:
	if phone and phone.map and player:
		var p := player.global_position
		phone.map.player_en = Vector2(p.x, -p.z)
		var f := -player.camera.global_transform.basis.z
		phone.map.player_dir_en = Vector2(f.x, -f.z)


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


## Loads a WAV/OGG stream and makes it loop over its whole length.
static func _looping_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_error("STRAY_DIAG audio=missing %s" % path)
		return null
	var st: AudioStream = load(path)
	if st is AudioStreamWAV:
		var w := st as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	elif st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	return st


func _build_audio() -> void:
	var cfg := _load_json(AUDIO_CONFIG)
	var city: Dictionary = cfg.get("city", {})
	city_audio = AudioStreamPlayer.new()
	city_audio.name = "CityAmbience"
	city_audio.stream = _looping_stream(city.get("stream", ""))
	city_audio.volume_db = city.get("volume_db", -10.0)
	add_child(city_audio)
	city_audio.play()
	# Club bass: positioned just outside the NACHTFLUG door, attenuates with distance.
	var club: Dictionary = cfg.get("club", {})
	var L := builder.layout
	var pos := StrayStreetLayout._v2(L.club["en"])
	var n := StrayStreetLayout._v2(L.club["normal_en"]).normalized()
	var p := pos + n * float(club.get("out_m", 0.6))
	club_audio = AudioStreamPlayer3D.new()
	club_audio.name = "ClubBass"
	club_audio.stream = _looping_stream(club.get("stream", ""))
	club_audio.volume_db = club.get("volume_db", 0.0)
	club_audio.unit_size = club.get("unit_size", 5.0)
	club_audio.max_distance = club.get("max_distance", 70.0)
	club_audio.position = StrayStreetLayout.en_to_godot(p.x, p.y, L.ground_z_at(p) + float(club.get("up_m", 1.6)))
	add_child(club_audio)
	club_audio.play()
	player.setup_footsteps(cfg.get("footsteps", {}))
	print("STRAY_DIAG audio city=%s club=%s club_pos=%s footsteps=%d" % [
		city_audio.stream != null, club_audio.stream != null, club_audio.position, player.footstep_streams.size()])


static func _load_json(path: String) -> Dictionary:
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v if typeof(v) == TYPE_DICTIONARY else {}


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)
	var info := Label.new()
	info.text = "STRAY · Prototyp 001 · Hohenzollernring, Köln (LoD2/DGM1 Geobasis NRW, © OSM)\n" \
		+ "WASD/Stick: gehen · Shift: rennen · Leertaste: springen · Maus: Kamera · E: interagieren · Tab: Handy · N: Tag/Nacht"
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
		day.pressed.connect(toggle_day_night)
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
	# Walking pose: hold forward for 1.2 s, capture mid-stride from the player camera.
	Input.action_press("move_forward")
	await get_tree().create_timer(1.2).timeout
	await _snap(dir, "P001_00b_player_walking_night.png")
	Input.action_release("move_forward")
	print("STRAY_DIAG anim_state_while_walking=%s" % player.anim_state)
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
	# Interaction captures from the player camera: kiosk menu, then the bouncer's answer.
	player.camera.make_current()
	player.global_position = interactions.points["kiosk"] + Vector3(0, 0.95, 0)
	# Face the kiosk facade (opposite of its outward normal) so the camera looks at the shop.
	var kn := StrayStreetLayout.en_dir_to_godot(-StrayStreetLayout._v2(builder.layout.kiosk["normal_en"]))
	player.face_yaw(atan2(-kn.x, -kn.z))
	player.global_position += StrayStreetLayout.en_dir_to_godot(StrayStreetLayout._v2(builder.layout.kiosk["normal_en"])) * 0.8
	await get_tree().create_timer(0.8).timeout
	interactions.interact()
	await _snap(dir, "P001_10_kiosk_menu_night.png")
	interactions._on_shop_choice("koelsch")
	interactions._on_shop_choice("")
	player.global_position = interactions.points["club_door"] + Vector3(0, 0.95, 0)
	await get_tree().create_timer(0.8).timeout
	interactions.interact()
	await _snap(dir, "P001_11_bouncer_queue_night.png")
	# Smartphone apps.
	player.global_position = builder.layout.spawn_position(0.9) + Vector3(0, 0.05, 0)
	player.face_yaw(builder.layout.spawn_yaw())
	interactions.withdraw_at_atm()
	phone.toggle()
	for app in ["home", "map", "messages", "bank"]:
		phone.open_app(app)
		await _snap(dir, "P001_2%d_phone_%s.png" % [["home", "map", "messages", "bank"].find(app), app])
	phone.toggle()
	# Club interior: entrance view over the dance floor, the bar, then Lea's dialogue.
	interactions.enter_club()
	await get_tree().create_timer(1.0).timeout
	await _snap(dir, "P001_30_club_dancefloor.png")
	player.global_position = interactions.points["club_bar"] + Vector3(1.5, 0.95, 2.5)
	player.face_yaw(deg_to_rad(30.0))
	await get_tree().create_timer(0.8).timeout
	await _snap(dir, "P001_31_club_bar.png")
	player.global_position = interactions.points["club_lea"] + Vector3(0, 0.95, 0.4)
	player.face_yaw(0.0)
	await get_tree().create_timer(0.6).timeout
	interactions.current = "club_lea"
	interactions.interact()
	await _snap(dir, "P001_32_club_lea_dialogue.png")
	interactions._on_option(0)
	interactions.leave_club()
	print("STRAY_DIAG autoshots=done dir=%s" % dir)
	get_tree().quit()
