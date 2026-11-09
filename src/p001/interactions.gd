## Prototype 001 interactions: KIOSK counter (shop menu) and the NACHTFLUG door (bouncer).
##
## Interaction points are derived from the layout (facade features). The player waits at the end
## of the club queue to "queue"; the bouncer then decides via StrayBouncerRules. Pure rules live in
## life_state.gd / kiosk_shop.gd / bouncer_rules.gd; this node only does proximity, input and UI.
## Config: data/p001/economy_config.json. Design: docs/STRAY_GDD.md (pillars LIFE, NIGHTLIFE,
## CONSEQUENCES).
class_name StrayInteractions
extends Node

## Emitted when the bouncer lets the player in (main.gd turns it into a phone message).
signal club_admitted
## Emitted when the player walks into / out of the club interior (audio switch in main.gd).
signal club_entered
signal club_left
## Emitted after the conversation with Lea; `reveal` = she told her name.
signal lea_met(reveal: bool, name: String)
## Emitted when the player confirms sleeping in their bed (main.gd advances the day).
signal sleep_requested
signal home_entered
signal home_left
## Emitted when a kiosk shift ends: result from StrayKioskJob.finish_shift().
signal shift_finished(result: Dictionary)

const RADIUS := 1.9

var layout: StrayStreetLayout
var econ: Dictionary = {}
var life: StrayLifeState
var shop: StrayKioskShop
var door: StrayBouncerRules
var player: StrayPlayer
var builder: StrayStreetBuilder
var ui: StrayUi
## Game clock (opening hours). Without one, the club counts as open whenever it is night.
var clock: StrayGameClock
var phone_cfg: Dictionary = {}
## Club interior (set by main.gd before setup); null = no interior.
var club: StrayClubInterior
var bar_shop: StrayKioskShop
var active_shop: StrayKioskShop
var lea_talked := false
## The player's flat (set by main.gd before setup); `rent` decides whether the key still works.
var home: StrayHome
var rent: StrayRent
var _options_context := ""
## Kiosk job (set by main.gd before setup).
var job: StrayKioskJob
var _customer: Node3D
var _char_cfg: Dictionary = {}
## Seconds the player has waited at the queue end (reset when they walk away).
var queued_seconds: float = 0.0
var points: Dictionary = {}  # id -> Vector3 (Godot)
var current: String = ""
var shop_open := false
var last_door_result: Dictionary = {}


func setup(p_layout: StrayStreetLayout, p_econ: Dictionary, p_player: StrayPlayer,
		p_builder: StrayStreetBuilder, p_ui: StrayUi, character_cfg: Dictionary) -> void:
	layout = p_layout
	econ = p_econ
	player = p_player
	builder = p_builder
	ui = p_ui
	life = StrayLifeState.new(int(econ.get("start_cash_cents", 0)), int(phone_cfg.get("bank", {}).get("start_account_cents", 0)))
	shop = StrayKioskShop.new(econ.get("kiosk", {}))
	door = StrayBouncerRules.new(econ.get("club", {}))
	var k := _frame(layout.kiosk)
	points["kiosk"] = _gp(k.pos + k.t * 1.75 + k.n * 1.0)
	var c := _frame(layout.club)
	points["club_door"] = _gp(c.pos + c.n * 1.6)
	var npc_q: Dictionary = _load_json("res://data/p001/npc_config.json").get("club_queue", {})
	var tail_along: float = float(npc_q.get("start_along", -1.8)) - float(npc_q.get("count", 5)) * float(npc_q.get("spacing", 0.9))
	points["queue_end"] = _gp(c.pos + c.n * float(npc_q.get("out", 2.7)) + c.t * tail_along)
	_char_cfg = character_cfg
	_spawn_bouncer(c, character_cfg)
	var atms: Array = layout.furniture.get("atms", [])
	for i in atms.size():
		var a := _frame(atms[i])
		points["atm_%d" % i] = _gp(a.pos + a.n * 0.8)
	life.cash_changed.connect(func(_c): ui.set_status(life))
	life.reputation_changed.connect(func(_a, _v): ui.set_status(life))
	ui.set_status(life)
	ui.shop_choice.connect(_on_shop_choice)
	ui.option_chosen.connect(_on_option)
	if home:
		var door := _home_door_entrance()
		if not door.is_empty():
			var hf := _frame(door)
			points["home_door"] = _gp(hf.pos + hf.n * 0.9)
			home.set_meta("street_door", door)
		points["home_bed"] = home.points["bed"]
		points["home_exit"] = home.points["exit"]
	if club:
		bar_shop = StrayKioskShop.new(club.cfg.get("bar_menu", {}))
		for id in ["bar", "lea", "exit"]:
			points["club_" + id] = club.points[id]
	ui.interact_pressed.connect(interact)
	print("STRAY_DIAG interactions kiosk=%s club_door=%s queue_end=%s cash=%s" % [
		points["kiosk"], points["club_door"], points["queue_end"], StrayLifeState.euro(life.cash_cents)])


static func _load_json(path: String) -> Dictionary:
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v if typeof(v) == TYPE_DICTIONARY else {}


func _frame(f: Dictionary) -> Dictionary:
	var pos := StrayStreetLayout._v2(f["en"])
	var n := StrayStreetLayout._v2(f["normal_en"]).normalized()
	return {"pos": pos, "n": n, "t": Vector2(n.y, -n.x)}


func _gp(en: Vector2) -> Vector3:
	return StrayStreetLayout.en_to_godot(en.x, en.y, layout.ground_z_at(en))


func _spawn_bouncer(c: Dictionary, character_cfg: Dictionary) -> void:
	if not ResourceLoader.exists(character_cfg.get("scene", "")):
		return
	var model: Node3D = load(character_cfg["scene"]).instantiate()
	var root := Node3D.new()
	root.name = "Bouncer"
	var p: Vector2 = c.pos + c.n * 0.9 + c.t * 1.55
	root.position = _gp(p)
	var face := StrayStreetLayout.en_dir_to_godot(c.n)
	root.rotation.y = atan2(-face.x, -face.z)
	model.rotation.y = deg_to_rad(character_cfg.get("yaw_offset_deg", 180.0))
	model.scale = Vector3.ONE * 1.1
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.03, 0.03, 0.035)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		for i in (mi as MeshInstance3D).mesh.get_surface_count():
			(mi as MeshInstance3D).set_surface_override_material(i, black)
	root.add_child(model)
	add_child(root)
	var ap: Array = model.find_children("*", "AnimationPlayer", true, false)
	if not ap.is_empty():
		(ap[0] as AnimationPlayer).play("Idle")
	var body := StaticBody3D.new()
	body.collision_layer = 4
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.9
	cs.shape = cap
	cs.position.y = 0.95
	body.add_child(cs)
	body.position = root.position
	add_child(body)


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _physics_process(delta: float) -> void:
	if player == null:
		return
	door.tick(delta)
	var pp := player.global_position
	var night := club_is_open()
	if night and _flat_dist(pp, points["queue_end"]) < float(econ.get("club", {}).get("queue_spot_radius", 1.6)):
		queued_seconds += delta
	elif _flat_dist(pp, points["club_door"]) > 12.0:
		queued_seconds = 0.0
	var best := ""
	var best_d := RADIUS
	for id in points:
		if id == "queue_end":
			continue
		var d := _flat_dist(pp, points[id])
		if d < best_d:
			best = id
			best_d = d
	if best != current:
		current = best
		if shop_open and current != "kiosk":
			_close_shop()
	var prompt := ""
	match current:
		"kiosk":
			prompt = "[E] Kiosk"
			if job and job.employed and not job.in_shift and clock and job.start_status(clock) in ["on_time", "late"]:
				prompt = String(job.cfg.get("texts", {}).get("start", "[E] Schicht beginnen"))
		"club_door":
			prompt = "[E] Mit dem Türsteher reden"
		"club_bar":
			prompt = "[E] Bar"
		"club_lea":
			prompt = "[E] Ansprechen"
		"club_exit":
			prompt = "[E] Rausgehen"
		"home_door":
			prompt = String(home.cfg.get("texts", {}).get("door", "[E] Nach Hause"))
		"home_bed":
			prompt = String(home.cfg.get("texts", {}).get("bed", "[E] Schlafen"))
		"home_exit":
			prompt = String(home.cfg.get("texts", {}).get("exit", "[E] Rausgehen"))
		_ when current.begins_with("atm_"):
			prompt = "[E] Geldautomat (%s abheben)" % StrayLifeState.euro(int(phone_cfg.get("bank", {}).get("atm_withdraw_cents", 2000)))
	if night and queued_seconds > 0.0 and current.is_empty() and _flat_dist(pp, points["queue_end"]) < 2.0:
		var need: float = econ.get("club", {}).get("queue_wait_seconds", 15.0)
		prompt = "Anstehen … %d / %d s" % [mini(int(queued_seconds), int(need)), int(need)]
	ui.show_prompt("" if shop_open else prompt)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		interact()


## Triggers the nearest interaction (also called by the touch button and by tests/autoshots).
func interact() -> void:
	if current.begins_with("atm_"):
		withdraw_at_atm()
		return
	match current:
		"kiosk":
			if job and job.employed and not job.in_shift and clock and job.start_status(clock) in ["on_time", "late"]:
				start_shift()
			else:
				_open_menu(shop, econ["kiosk"])
		"club_bar":
			_open_menu(bar_shop, club.cfg.get("bar_menu", {}))
		"club_lea":
			_talk_to_lea()
		"club_exit":
			leave_club()
		"home_door":
			enter_home()
		"home_bed":
			_ask_sleep()
		"home_exit":
			leave_home()
		"club_door":
			last_door_result = door.decide(life, club_is_open(), queued_seconds)
			ui.show_message("Türsteher", last_door_result.text)
			print("STRAY_DIAG door reason=%s cash=%s nightlife=%d queued=%.1f" % [
				last_door_result.reason, StrayLifeState.euro(life.cash_cents), int(life.reputation["nightlife"]), queued_seconds])
			if last_door_result.admitted:
				queued_seconds = 0.0
				club_admitted.emit()
				await get_tree().create_timer(1.5).timeout
				if club:
					enter_club()
				else:
					ui.show_message("", String(econ.get("club", {}).get("lines", {}).get("inside", "")), 6.0)


## True during the club's opening hours (game clock), or at night when there is no clock.
func club_is_open() -> bool:
	return clock.club_open() if clock else not builder.day_mode


func withdraw_at_atm() -> bool:
	var amount: int = int(phone_cfg.get("bank", {}).get("atm_withdraw_cents", 2000))
	var ok := life.withdraw(amount)
	ui.show_message(String(phone_cfg.get("bank", {}).get("atm_name", "Geldautomat")),
		("%s ausgezahlt. Kontostand %s." % [StrayLifeState.euro(amount), StrayLifeState.euro(life.account_cents)]) if ok
		else "Auszahlung nicht möglich. Kontostand %s." % StrayLifeState.euro(life.account_cents), 4.0)
	print("STRAY_DIAG atm ok=%s cash=%s account=%s" % [ok, StrayLifeState.euro(life.cash_cents), StrayLifeState.euro(life.account_cents)])
	return ok


func _open_menu(which: StrayKioskShop, menu_cfg: Dictionary) -> void:
	if shop_open:
		_close_shop()
		return
	active_shop = which
	shop_open = true
	player.input_enabled = false
	ui.open_shop(menu_cfg.get("title", ""), menu_cfg.get("greeting", ""), which.items())


## Moves the player into the club interior, just inside the exit door, facing the room.
func enter_club() -> void:
	player.global_position = club.points["exit"] + Vector3(0, 0.95, -0.6)
	player.velocity = Vector3.ZERO
	player.face_yaw(0.0)
	player.set_indoor_camera(true)
	life.flags["inside_club"] = true
	club.visible = true
	club_entered.emit()
	ui.show_message("", "NACHTFLUG – drinnen. Bar links, Tanzfläche in der Mitte.", 4.0)
	print("STRAY_DIAG club entered pos=%s" % player.global_position)


## Back to the street, in front of the club door.
func leave_club() -> void:
	var c := _frame(layout.club)
	player.global_position = _gp(c.pos + c.n * 1.6 + c.t * 1.0) + Vector3(0, 0.95, 0)
	player.velocity = Vector3.ZERO
	_face_along_street()
	player.set_indoor_camera(false)
	life.flags["inside_club"] = false
	club_left.emit()
	print("STRAY_DIAG club left pos=%s" % player.global_position)


## Picks the OSM entrance configured as the player's street door (nearest to `near_s`, preferring
## the configured entrance kind, on the configured side).
func _home_door_entrance() -> Dictionary:
	var dc: Dictionary = home.cfg.get("door_entrance", {})
	var best := {}
	var best_score := 1e9
	for e in layout.furniture.get("entrances", []):
		var sv := layout.to_street(StrayStreetLayout._v2(e["en"]))
		if signf(sv.y) != float(dc.get("side", 1)):
			continue
		var score := absf(float(e.get("s", sv.x)) - float(dc.get("near_s", 0.0)))
		if String(e.get("kind", "")) != String(dc.get("kind", "")):
			score += 5.0
		if score < best_score:
			best = e
			best_score = score
	return best


func enter_home() -> void:
	var t: Dictionary = home.cfg.get("texts", {})
	if rent and rent.evicted:
		ui.show_message("", String(t.get("locked_out", "")), 4.0)
		print("STRAY_DIAG home locked_out")
		return
	player.global_position = home.points["exit"] + Vector3(0, 0.95, 0)
	player.velocity = Vector3.ZERO
	player.face_yaw(0.0)
	player.set_indoor_camera(true)
	life.flags["inside_home"] = true
	home.visible = true
	home_entered.emit()
	ui.show_message("", String(t.get("home", "")), 3.0)
	print("STRAY_DIAG home entered")


func leave_home() -> void:
	var door: Dictionary = home.get_meta("street_door", {})
	if not door.is_empty():
		var hf := _frame(door)
		player.global_position = _gp(hf.pos + hf.n * 1.8) + Vector3(0, 0.95, 0)
	# Look along the street, not away from the building: the camera behind the player would
	# otherwise end up inside the facade.
	_face_along_street()
	player.set_indoor_camera(false)
	player.velocity = Vector3.ZERO
	life.flags["inside_home"] = false
	home.visible = false
	home_left.emit()
	print("STRAY_DIAG home left")


## Turns the player to look along the street axis (towards Friesenplatz).
func _face_along_street() -> void:
	var d := StrayStreetLayout.en_dir_to_godot(layout.axis_en())
	player.face_yaw(atan2(-d.x, -d.z))


# --- Kiosk shift (R3) --------------------------------------------------------------------------

## Starts today's shift at the kiosk; customers then order one after another.
func start_shift() -> void:
	var t: Dictionary = job.cfg.get("texts", {})
	var st := job.start_shift(clock)
	match st:
		"too_early":
			ui.show_message("Erol", String(t.get("too_early", "")) % job.cfg.get("shift_start", ""), 3.0)
			return
		"too_late":
			ui.show_message("Erol", String(t.get("too_late", "")), 3.0)
			return
		"late":
			ui.show_message("Erol", String(t.get("late", "")) % job.shift_late_minutes, 3.0)
	print("STRAY_DIAG shift start=%s status=%s customers=%d" % [clock.hhmm(), st, job.orders.size()])
	shop_open = true
	player.input_enabled = false
	_show_customer()


func _show_customer() -> void:
	var o := job.current_order()
	if o.is_empty():
		_finish_shift()
		return
	# One customer figure stands at the kiosk window for each order.
	if _customer == null and ResourceLoader.exists(_char_cfg.get("scene", "")):
		var k := _frame(layout.kiosk)
		_customer = Node3D.new()
		_customer.position = _gp(k.pos + k.n * 2.2 - k.t * 0.7)
		var face := StrayStreetLayout.en_dir_to_godot(-k.n)
		_customer.rotation.y = atan2(-face.x, -face.z)
		var model: Node3D = load(_char_cfg["scene"]).instantiate()
		model.rotation.y = deg_to_rad(_char_cfg.get("yaw_offset_deg", 180.0))
		_customer.add_child(model)
		add_child(_customer)
		var aps := model.find_children("*", "AnimationPlayer", true, false)
		if not aps.is_empty():
			(aps[0] as AnimationPlayer).play("Idle_Talking")
	if _customer:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.from_hsv(fmod(job.served * 0.137 + 0.05, 1.0), 0.5, 0.6)
		for mi in _customer.find_children("*", "MeshInstance3D", true, false):
			for i in (mi as MeshInstance3D).mesh.get_surface_count():
				(mi as MeshInstance3D).set_surface_override_material(i, m)
	var labels: Array = []
	for it in shop.items():
		labels.append(it.get("name", "?"))
	_options_context = "shift"
	ui.open_options("%s %d/%d" % [job.cfg.get("texts", {}).get("customer", "Kunde"), job.served + 1, job.orders.size()],
		String(o.get("line", "")), labels)


## Hands over the item at `index` (kiosk item order) to the current customer.
func serve_option(index: int) -> void:
	var items := shop.items()
	var t: Dictionary = job.cfg.get("texts", {})
	var ok := job.serve(String(items[index].get("id", "")) if index >= 0 and index < items.size() else "", life)
	ui.show_message("Kunde", String(t.get("served_ok" if ok else "served_wrong", "")), 1.5)
	_show_customer()


func _finish_shift() -> void:
	_options_context = ""
	clock.set_time(String(job.cfg.get("shift_end", "22:00")))
	var r := job.finish_shift(clock, life)
	if _customer:
		_customer.queue_free()
		_customer = null
	_close_shop()
	var t: Dictionary = job.cfg.get("texts", {})
	ui.show_message("Erol", String(t.get("shift_done", "")) % [job.correct, job.served, StrayLifeState.euro(r.wage), StrayLifeState.euro(r.tips)], 5.0)
	print("STRAY_DIAG shift done correct=%d/%d wage=%s warning=%s fired=%s" % [job.correct, job.served, StrayLifeState.euro(r.wage), r.warning, r.fired])
	shift_finished.emit(r)


func _ask_sleep() -> void:
	var t: Dictionary = home.cfg.get("texts", {})
	_options_context = "sleep"
	shop_open = true
	active_shop = null
	player.input_enabled = false
	ui.open_options("", String(t.get("sleep_question", "Schlafen bis %s?")) % home.cfg.get("sleep_until", "10:00"),
		[t.get("sleep_yes", "Ja"), t.get("sleep_no", "Nein")])


func _talk_to_lea() -> void:
	_options_context = "lea"
	var lea: Dictionary = club.cfg.get("lea", {})
	if lea_talked:
		ui.show_message("", String(lea.get("after", "")), 4.0)
		return
	var node: Dictionary = lea.get("dialogue", [{}])[0]
	var labels: Array = []
	for o in node.get("options", []):
		labels.append(o.get("label", "..."))
	shop_open = true
	active_shop = null
	player.input_enabled = false
	ui.open_options("???", String(node.get("text", "")), labels)


func _on_option(index: int) -> void:
	if _options_context == "shift":
		serve_option(index)
		return
	if _options_context == "sleep":
		_options_context = ""
		_close_shop()
		if index == 0:
			sleep_requested.emit()
		return
	var lea: Dictionary = club.cfg.get("lea", {})
	var opts: Array = lea.get("dialogue", [{}])[0].get("options", [])
	if index < 0 or index >= opts.size():
		return
	var o: Dictionary = opts[index]
	life.change_reputation("social", int(o.get("social", 0)))
	lea_talked = true
	_close_shop()
	var reveal: bool = o.get("reveal_name", false)
	ui.show_message(String(lea.get("name", "Lea")) if reveal else "???", String(o.get("reply", "")), 5.0)
	lea_met.emit(reveal, String(lea.get("name", "Lea")))
	print("STRAY_DIAG lea option=%d social=%d reveal=%s" % [index, int(life.reputation["social"]), reveal])


func buy(item_id: String) -> Dictionary:
	var which := active_shop if active_shop else shop
	var r := which.buy(life, item_id)
	ui.show_message("Bar" if which == bar_shop else "Kiosk", r.text, 3.5)
	print("STRAY_DIAG kiosk item=%s ok=%s cash=%s" % [item_id, r.ok, StrayLifeState.euro(life.cash_cents)])
	return r


func _on_shop_choice(item_id: String) -> void:
	if item_id.is_empty():
		_close_shop()
	else:
		buy(item_id)


func _close_shop() -> void:
	shop_open = false
	player.input_enabled = true
	ui.close_shop()
