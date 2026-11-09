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
const GAME_CONFIG := "res://data/p001/game_config.json"
const HOME_CONFIG := "res://data/p001/home_config.json"
const JOBS_CONFIG := "res://data/p001/jobs_config.json"
const CONSEQUENCES_CONFIG := "res://data/p001/consequences_config.json"
const TRANSIT_CONFIG := "res://data/p002/transit_config.json"
const AREA_P002 := "res://data/p002/P002_Area.json"

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
var menu: StrayMenu
var home: StrayHome
var rent: StrayRent
var job: StrayKioskJob
var consequences: StrayConsequences
## R5: second area (Hbf), U-Bahn rules, platform interior and its interactions.
var area: StrayAreaBuilder
var transit: StrayTransit
var metro: StrayMetroStation
var metro_ix: StrayMetroInteractions
## Which part of the world is drawn: "p001" (Ringe), "p002" (Hbf) or "metro" (platform).
var region: String = "p001"
var hud_info: Label
var _jaywalk_time := 0.0
var _last_clock_minutes := -1.0
var game_cfg: Dictionary = {}
## Save file path (tests override it before the node enters the tree).
var save_path: String = ""
var _autosave_left: float = 0.0


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
	var home_cfg := _load_json(HOME_CONFIG)
	home = StrayHome.new()
	home.name = "Home"
	add_child(home)
	home.setup(home_cfg)
	home.visible = false
	rent = StrayRent.new(home_cfg.get("rent", {}))
	interactions.home = home
	interactions.rent = rent
	job = StrayKioskJob.new(_load_json(JOBS_CONFIG).get("kiosk_job", {}))
	interactions.job = job
	consequences = StrayConsequences.new(_load_json(CONSEQUENCES_CONFIG))
	interactions.consequences = consequences
	add_child(interactions)
	interactions.setup(builder.layout, _load_json(ECONOMY_CONFIG), player, builder, ui, player_cfg.get("character", {}))
	_build_transit()
	_build_phone(phone_cfg)
	_setup_menu_and_save()
	interactions.club_entered.connect(func(): save_game("club_entered"))
	interactions.sleep_requested.connect(sleep_until_morning)
	clock.day_changed.connect(_on_day_changed)
	clock.hour_changed.connect(_on_hour_changed)
	interactions.club_left.connect(func(): save_game("club_left"))
	if "--autoshots" in OS.get_cmdline_user_args():
		_run_autoshots.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_day_night"):
		toggle_day_night()
	elif event.is_action_pressed("pause") and menu and menu.mode.is_empty():
		open_pause_menu()


# --------------------------------------------------------------------------------------------
# Menus + save game (R1)
# --------------------------------------------------------------------------------------------

func _setup_menu_and_save() -> void:
	game_cfg = _load_json(GAME_CONFIG)
	var sv: Dictionary = game_cfg.get("save", {})
	if save_path.is_empty():
		save_path = String(sv.get("path", "user://stray_save_1.json"))
	_autosave_left = float(sv.get("autosave_seconds", 90.0))
	menu = StrayMenu.new()
	menu.name = "Menu"
	add_child(menu)
	menu.setup(game_cfg.get("menu", {}))
	menu.new_game.connect(_on_new_game)
	menu.continue_game.connect(func():
		var ok := load_game()
		_start_playing("" if ok else String(menu.txt.get("load_failed", ""))))
	menu.resume.connect(func(): _start_playing(""))
	menu.save_requested.connect(func():
		menu.set_note(String(menu.txt.get("saved", "")) if save_game("menu") else "Speichern fehlgeschlagen."))
	menu.load_requested.connect(func():
		var ok := load_game()
		_start_playing(String(menu.txt.get("loaded", "")) if ok else String(menu.txt.get("load_failed", ""))))
	menu.main_menu.connect(func():
		save_game("main_menu")
		get_tree().paused = false
		get_tree().reload_current_scene())
	menu.quit_requested.connect(func():
		save_game("quit")
		get_tree().quit())
	# The start screen only appears when this scene is the game itself (not inside tests/tools).
	if get_tree().current_scene == self and not "--autoshots" in OS.get_cmdline_user_args():
		get_tree().paused = true
		menu.show_start(StraySaveGame.exists(save_path))
		if "--menushots" in OS.get_cmdline_user_args():
			_run_menushots.call_deferred()


## Evidence capture of the start and pause menus (cmdline: -- --menushots [--shots-dir=...]).
func _run_menushots() -> void:
	var dir := _shots_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(2.0).timeout
	await _snap(dir, "P001_40_start_menu.png")
	_start_playing("")
	await get_tree().create_timer(1.5).timeout
	open_pause_menu()
	await get_tree().create_timer(0.5).timeout
	await _snap(dir, "P001_41_pause_menu.png")
	print("STRAY_DIAG menushots=done")
	get_tree().quit()


func _on_new_game() -> void:
	_start_playing("")
	messages.trigger("start", clock.hhmm())


func _start_playing(note: String) -> void:
	menu.hide_menu()
	get_tree().paused = false
	if not note.is_empty():
		ui.show_message("", note, 3.0)


func open_pause_menu() -> void:
	get_tree().paused = true
	menu.show_pause(StraySaveGame.exists(save_path))


## Writes the save file. `reason` only goes to the log.
func save_game(reason: String = "") -> bool:
	var err := StraySaveGame.write(save_path, StraySaveGame.capture(self))
	print("STRAY_DIAG save reason=%s path=%s ok=%s %s" % [reason, save_path, err.is_empty(), err])
	return err.is_empty()


## Loads the save file into the running game. False when missing/corrupt/unsupported.
func load_game() -> bool:
	var d := StraySaveGame.read(save_path)
	if d.is_empty():
		print("STRAY_DIAG load path=%s ok=false (missing or corrupt)" % save_path)
		return false
	var err := StraySaveGame.apply(self, d)
	_sync_daylight()
	ui.set_status(interactions.life)
	print("STRAY_DIAG load path=%s ok=%s time=%s %s" % [save_path, err.is_empty(), clock.hhmm(), err])
	return err.is_empty()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and menu:
		save_game("window_closed")


## Debug / touch: jump the clock to the afternoon or to late night; lighting follows the clock.
func toggle_day_night() -> void:
	clock.set_time("23:30" if clock.is_daytime() else "14:00")
	_sync_daylight()


## Sleeps in the flat until the configured morning time: next day, sober, phone charged, saved.
func sleep_until_morning() -> void:
	var t: Dictionary = home.cfg.get("texts", {})
	clock.set_time(String(home.cfg.get("sleep_until", "10:00")))
	interactions.life.drinks_alcohol = 0
	phone.battery = 100.0
	_sync_daylight()
	ui.show_message("", String(t.get("woke_up", "Guten Morgen. %s, %s.")) % [clock.date_text(), clock.hhmm()], 4.0)
	print("STRAY_DIAG slept until %s %s" % [clock.date_text(), clock.hhmm()])
	save_game("slept")


## Day change: rent standing order, rent/landlord messages, morning messages.
func _on_day_changed(day: int) -> void:
	var events := rent.process_until(clock, day, interactions.life)
	for e in events:
		messages.trigger(e, clock.hhmm())
	print("STRAY_DIAG day=%d date=%s rent_events=%s account=%s" % [day, clock.date_text(), events, StrayLifeState.euro(interactions.life.account_cents)])
	if rent.evicted and interactions.life.flags.get("inside_home", false):
		interactions.leave_home()


## Morning messages ("new_day_N") arrive from 08:00, not at midnight (or on waking up later).
func _on_hour_changed(hour: int) -> void:
	if hour >= int(game_cfg.get("morning_from_hour", 8)) and clock.day_index() > 0:
		messages.trigger("new_day_%d" % clock.day_index(), clock.hhmm())
	if job:
		var missed := job.check_missed(clock)
		if missed == "missed":
			messages.trigger("job_warning_%d" % job.warnings, clock.hhmm())
		elif missed == "fired":
			messages.trigger("job_fired", clock.hhmm())
		if not missed.is_empty():
			print("STRAY_DIAG job %s warnings=%d" % [missed, job.warnings])


func _on_theft_caught() -> void:
	if job.employed:
		job.employed = false
		job.fired = true
		messages.trigger("theft_caught_job", clock.hhmm())
	save_game("theft_caught")


func _on_police_check_done(r: Dictionary) -> void:
	traffic.police_hold = false
	if consequences.police_record >= 1:
		messages.trigger("police_record_1", clock.hhmm())
	_sync_daylight()
	save_game("police_check")


## Per-frame consequence checks on the street: jaywalking, public drunkenness, police patrol.
func _update_consequences(delta: float) -> void:
	if consequences == null or interactions == null or player == null:
		return
	if _last_clock_minutes >= 0.0:
		consequences.decay(clock.minutes - _last_clock_minutes)
	_last_clock_minutes = clock.minutes
	var life := interactions.life
	if life.flags.get("inside_club", false) or life.flags.get("inside_home", false) or life.flags.get("inside_metro", false) \
			or region != "p001" or interactions.police_check_open or interactions.shop_open:
		_jaywalk_time = 0.0
		return
	var L := builder.layout
	var p := player.global_position
	var sv := L.to_street(Vector2(p.x, -p.z))
	if sv.x > L.s_start and sv.x < L.s_end and absf(sv.y) < L.kerb_half_width - 0.3:
		_jaywalk_time += delta
		if _jaywalk_time >= float(consequences.cfg.get("jaywalk_seconds", 2.5)):
			_jaywalk_time = 0.0
			consequences.report("jaywalk", clock)
	else:
		_jaywalk_time = 0.0
	if life.drinks_alcohol >= int(consequences.cfg.get("public_drunk_from_drinks", 3)):
		consequences.report("public_drunk", clock)
	var pc := traffic.police_car()
	if pc and pc.active:
		var pen := L.to_en(pc.s, pc.v)
		var d := Vector2(p.x, -p.z).distance_to(pen)
		if consequences.police_wants_check(clock, d):
			traffic.police_hold = true
			interactions.start_police_check()


func _on_shift_finished(r: Dictionary) -> void:
	messages.trigger("job_paid_%d" % job.shifts_done, clock.hhmm())
	if r.fired:
		messages.trigger("job_fired", clock.hhmm())
	elif r.warning:
		messages.trigger("job_warning_%d" % job.warnings, clock.hhmm())
	save_game("shift_done")


func _sync_daylight() -> void:
	if builder and builder.day_mode != clock.is_daytime():
		builder.set_day_mode(clock.is_daytime())
	if area and area.area:
		area.set_day_mode(builder.day_mode)


## R5: Hbf area, U-Bahn platform and the entrances (Friesenplatz stele on the Ring).
func _build_transit() -> void:
	var tcfg := _load_json(TRANSIT_CONFIG)
	transit = StrayTransit.new(tcfg)
	area = StrayAreaBuilder.new()
	area.name = "AreaP002"
	add_child(area)
	area.build(builder, AREA_P002)
	metro = StrayMetroStation.new()
	metro.name = "MetroStation"
	add_child(metro)
	metro.setup(tcfg)
	metro.visible = false
	metro_ix = StrayMetroInteractions.new()
	metro_ix.name = "MetroInteractions"
	add_child(metro_ix)
	metro_ix.setup(interactions, transit, metro, area.area)
	var fp: Dictionary = tcfg.get("stations", {}).get("friesenplatz", {})
	var L := builder.layout
	var en := L.to_en(float(fp.get("s", 100.0)), float(fp.get("v", -10.4)))
	StrayAreaBuilder.build_ubahn_stele(builder, StrayStreetLayout.en_to_godot(en.x, en.y, L.ground_z_at(en)), L.right_en(), transit.station_name("friesenplatz"))
	metro_ix.metro_entered.connect(func(_st): set_region("metro"))
	metro_ix.metro_left.connect(func(st):
		set_region(String(transit.cfg.get("stations", {}).get(st, {}).get("area", "p001")))
		save_game("metro_left"))
	metro_ix.rode.connect(func(_r): _sync_daylight())
	set_region("p001")


## Shows only the given region: "p001" (street, NPCs, traffic), "p002" (Hbf area) or "metro".
func set_region(id: String) -> void:
	region = id
	builder.set_region_visible(id == "p001")
	for n in [pedestrians, traffic]:
		if n:
			n.visible = id == "p001"
			n.process_mode = Node.PROCESS_MODE_INHERIT if id == "p001" else Node.PROCESS_MODE_DISABLED
	if area:
		area.visible = id == "p002"
	if metro:
		metro.visible = id == "metro"
	if hud_info:
		var lines := hud_info.text.split("\n")
		lines[0] = _hud_title(id)
		hud_info.text = "\n".join(lines)
	_sync_daylight()
	print("STRAY_DIAG region=%s" % id)


## First HUD line: where the player is (+ data credits for the real-data areas).
func _hud_title(id: String) -> String:
	var titles: Dictionary = transit.cfg.get("region_titles", {}) if transit else {}
	return "STRAY · " + String(titles.get(id, "Hohenzollernring, Köln")) + " (LoD2/DGM1 Geobasis NRW, © OSM)"


func _process(delta: float) -> void:
	if menu and menu.mode.is_empty() and not save_path.is_empty():
		_autosave_left -= delta
		if _autosave_left <= 0.0:
			_autosave_left = float(game_cfg.get("save", {}).get("autosave_seconds", 90.0))
			save_game("autosave")
	if clock:
		clock.advance(delta)
		var stamp := "%s  %s" % [clock.date_text(), clock.hhmm()]
		if ui and interactions and ui.clock_text != stamp:
			ui.clock_text = stamp
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
	phone.rent = rent
	phone.job = job
	phone.apply_job.connect(func(_id):
		if job.apply():
			messages.trigger("job_accepted", clock.hhmm())
			print("STRAY_DIAG job applied"))
	interactions.shift_finished.connect(_on_shift_finished)
	interactions.theft_caught.connect(_on_theft_caught)
	interactions.police_check_done.connect(_on_police_check_done)
	consequences.heat_changed.connect(func(h):
		ui.police_heat = h
		ui.set_status(interactions.life))
	if interactions.points.has("home_door"):
		var hp: Vector3 = interactions.points["home_door"]
		map.markers.append({"en": Vector2(hp.x, -hp.z), "color": Color(1.0, 0.85, 0.3), "label": "Zuhause"})
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
	# Start messages arrive once play begins (immediately when there is no start screen).
	if not (get_tree().current_scene == self and not "--autoshots" in OS.get_cmdline_user_args()):
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


func _physics_process(delta: float) -> void:
	_update_consequences(delta)
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
	hud_info = info
	info.text = _hud_title("p001") + "\n" \
		+ "WASD/Stick: gehen · Shift: rennen · Leertaste: springen · Maus: Kamera · E: interagieren · Tab: Handy · N: Tag/Nacht · Esc: Menü"
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
		var menu_b := Button.new()
		menu_b.text = "Menü"
		menu_b.position = Vector2(140, 60)
		menu_b.pressed.connect(open_pause_menu)
		hud.add_child(menu_b)
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


## R5 evidence: U-Bahn entrance on the Ring, platform + ticket machine, Hbf area night/day.
func _autoshots_transit(dir: String, cam: Camera3D) -> void:
	var L := builder.layout
	var e := metro_ix.ix.points["ubahn_friesenplatz"] as Vector3
	var eye_en := L.to_en(92.0, -4.0)
	cam.global_position = StrayStreetLayout.en_to_godot(eye_en.x, eye_en.y, L.ground_z_at(eye_en) + 1.7)
	cam.look_at(e + Vector3(0, 2.2, 0), Vector3.UP)
	cam.make_current()
	await _snap(dir, "P002_00_ubahn_friesenplatz_night.png")
	player.camera.make_current()
	metro_ix.enter_station("friesenplatz")
	player.global_position = metro.points["ticket"] + Vector3(4.0, 0.95, -2.5)
	player.face_yaw(deg_to_rad(80.0))
	await get_tree().create_timer(0.8).timeout
	await _snap(dir, "P002_01_metro_platform.png")
	interactions.life.cash_cents += 1000  # evidence run: enough cash for the ticket
	player.global_position = metro.points["ticket"] + Vector3(0, 0.95, 0)
	player.face_yaw(PI)
	await get_tree().create_timer(0.4).timeout
	interactions.current = "metro_ticket"
	interactions.interact()
	await _snap(dir, "P002_02_metro_ticket_machine.png")
	interactions._on_option(0)
	metro_ix.ride()
	await get_tree().create_timer(0.6).timeout
	await _snap(dir, "P002_03_metro_arrived_dom_hbf.png")
	metro_ix.leave_station()
	await get_tree().create_timer(1.0).timeout
	await _snap(dir, "P002_04_hbf_player_exit_night.png")
	for day in [false, true]:
		builder.set_day_mode(day)
		area.set_day_mode(day)
		var idx := 10
		for vp in area.area.viewpoints:
			var a: StrayAreaLayout = area.area
			var eye := StrayStreetLayout._v2(vp["en"])
			var look := StrayStreetLayout._v2(vp["look_en"])
			cam.global_position = StrayStreetLayout.en_to_godot(eye.x, eye.y, a.ground_z_at(eye) + float(vp["h"]))
			cam.look_at(StrayStreetLayout.en_to_godot(look.x, look.y, a.ground_z_at(look) + float(vp["look_h"])), Vector3.UP)
			cam.make_current()
			await _snap(dir, "P002_%02d_%s_%s.png" % [idx, vp["name"], "day" if day else "night"])
			idx += 1
	builder.set_day_mode(false)
	_sync_daylight()
	player.camera.make_current()
	# Back to the Ring for the remaining captures.
	metro_ix.enter_station("dom_hbf")
	metro_ix.ride()
	metro_ix.leave_station()
	await get_tree().create_timer(0.5).timeout


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
	# Police check: high attention, stand next to the patrol car.
	consequences._set_heat(60.0)
	var pc := traffic.police_car()
	var L := builder.layout
	for i in 600:
		if pc.active and pc.s > L.s_start + 15.0 and pc.s < L.s_end - 15.0:
			break
		await get_tree().physics_frame
	var side := 1.0 if pc.v > 0.0 else -1.0
	var pen := L.to_en(pc.s + 5.0 * pc.dir, side * (L.kerb_half_width + 1.4))
	player.global_position = StrayStreetLayout.en_to_godot(pen.x, pen.y, L.ground_z_at(pen) + 0.95)
	var back := StrayStreetLayout.en_dir_to_godot(-L.axis_en() * pc.dir)
	player.face_yaw(atan2(-back.x, -back.z))
	await get_tree().create_timer(2.5).timeout
	await _snap(dir, "P001_70_police_check.png")
	if interactions.police_check_open:
		interactions._on_option(0)
	consequences._set_heat(0.0)
	await _autoshots_transit(dir, cam)
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
	# Flat: inside view, then sleep and step out into Sunday morning.
	interactions.enter_home()
	player.global_position = home.points["exit"] + Vector3(0, 0.95, 0.3)
	player.face_yaw(0.0)
	await get_tree().create_timer(0.8).timeout
	await _snap(dir, "P001_50_home.png")
	sleep_until_morning()
	interactions.leave_home()
	await get_tree().create_timer(1.0).timeout
	await _snap(dir, "P001_51_sunday_morning_street.png")
	# Job: hired, Sunday 18:05 at the kiosk, first customer orders.
	job.apply()
	clock.set_time("18:05")
	_sync_daylight()
	var kin := StrayStreetLayout.en_dir_to_godot(-StrayStreetLayout._v2(builder.layout.kiosk["normal_en"]))
	player.global_position = interactions.points["kiosk"] + Vector3(0, 0.95, 0) - kin * 0.8
	player.face_yaw(atan2(-kin.x, -kin.z))
	await get_tree().create_timer(0.8).timeout
	interactions.current = "kiosk"
	interactions.interact()
	await get_tree().create_timer(0.6).timeout
	await _snap(dir, "P001_60_kiosk_shift.png")
	print("STRAY_DIAG autoshots=done dir=%s" % dir)
	get_tree().quit()
