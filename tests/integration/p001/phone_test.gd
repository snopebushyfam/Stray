## Integration test (Schritt 4): game clock, smartphone apps, ATM, messages in the real scene.
## Run: godot --headless --path . -s res://tests/integration/p001/phone_test.gd
extends SceneTree

var _failed := 0
var _passed := 0
var main: Node


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


func _tap(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(3)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(3)


func _run() -> void:
	main = load("res://src/p001/main.tscn").instantiate()
	root.add_child(main)
	await _frames(30)
	var phone: StrayPhone = main.phone
	var life: StrayLifeState = main.interactions.life
	var t0: float = main.clock.minutes

	# Clock runs at 10x and is shown in the HUD; start is Saturday night.
	await _frames(360)  # 6 s real -> 1 game minute
	check(main.clock.minutes - t0 >= 0.9 and main.clock.minutes - t0 <= 1.3, "clock advanced ~1 game min in 6 s (%.2f)" % (main.clock.minutes - t0))
	check(main.clock.hhmm() in main.ui.status_label.text, "HUD shows the time (%s)" % main.clock.hhmm())
	check(not main.builder.day_mode, "23:1x is night lighting")

	# Start messages arrived (rent reminder, mother).
	check(main.messages.inbox.size() == 2 and main.messages.unread == 2, "2 start messages, unread")

	# Phone opens with Tab, movement stops; apps render.
	await _tap("phone")
	check(phone.is_open and not main.player.input_enabled, "Tab opens the phone and pauses movement")
	check(not main.ui.status_label.visible, "HUD status hidden behind the open phone")
	phone.open_app("messages")
	check(main.messages.unread == 0, "reading marks messages as read")
	phone.open_app("bank")
	var bank_text := ""
	for c in phone._body.get_children():
		if c is Label:
			bank_text += (c as Label).text + "\n"
	check("120,00 €" in bank_text and "35,00 €" in bank_text, "bank shows account 120 € and cash 35 €")
	phone.open_app("map")
	check(phone.map.get_parent() != null and phone.map.footprints.size() > 100, "map shows %d real LoD2 footprints" % phone.map.footprints.size())
	check(phone.map.markers.size() >= 4, "map markers: kiosk, club, 2 ATMs")
	await _tap("phone")
	check(not phone.is_open and main.player.input_enabled, "Tab closes the phone")

	# ATM: walk up, withdraw 20 €.
	var ix: StrayInteractions = main.interactions
	check(ix.points.has("atm_0"), "ATM interaction point from OSM")
	main.player.global_position = ix.points["atm_0"] + Vector3(0, 0.95, 0)
	await _frames(20)
	check(ix.current == "atm_0" and "Geldautomat" in main.ui.prompt_label.text, "ATM prompt")
	await _tap("interact")
	check(life.cash_cents == 5500 and life.account_cents == 10000, "withdrew 20 € (cash %s, account %s)" % [StrayLifeState.euro(life.cash_cents), StrayLifeState.euro(life.account_cents)])
	check(life.transactions.size() >= 1 and life.transactions[-1].kind == "atm", "ATM booking recorded")

	# Day/night via the clock: afternoon -> daylight, club closed; back to night.
	main.toggle_day_night()
	await _frames(5)
	check(main.clock.hhmm() == "14:00" and main.builder.day_mode, "N jumps to 14:00 with daylight")
	main.toggle_day_night()
	await _frames(5)
	check(main.clock.hhmm() == "23:30" and not main.builder.day_mode and ix.club_is_open(), "back to 23:30, night, club open")

	print("RESULT phone_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
