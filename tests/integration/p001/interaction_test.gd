## Integration test (Schritt 3): KIOSK purchase and the NACHTFLUG door in the real scene.
## Run: godot --headless --path . -s res://tests/integration/p001/interaction_test.gd
extends SceneTree

var _failed := 0
var _passed := 0
var main: Node
var ix: StrayInteractions


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


func _go(p: Vector3) -> void:
	main.player.global_position = p + Vector3(0, 0.95, 0)
	main.player.velocity = Vector3.ZERO
	await _frames(20)


func _press_interact() -> void:
	Input.action_press("interact")
	var ev := InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(3)
	Input.action_release("interact")
	await _frames(3)


func _run() -> void:
	main = load("res://src/p001/main.tscn").instantiate()
	root.add_child(main)
	await _frames(30)
	ix = main.interactions
	var start: int = ix.life.cash_cents
	check(start == 3500, "start cash 35,00 € (%s)" % StrayLifeState.euro(start))
	check("35,00 €" in main.ui.status_label.text, "HUD shows cash")

	# Kiosk: prompt, open menu via the interact action, buy a water.
	await _go(ix.points["kiosk"])
	check(ix.current == "kiosk" and "Kiosk" in main.ui.prompt_label.text, "kiosk prompt near the counter")
	await _press_interact()
	check(ix.shop_open and main.ui.shop_panel.visible, "interact opens the kiosk menu")
	check(not main.player.input_enabled, "player movement paused while the menu is open")
	ix._on_shop_choice("water")
	check(ix.life.cash_cents == start - 150 and ix.life.inventory.get("water", 0) == 1, "bought water for 1,50 €")
	check("33,50 €" in main.ui.status_label.text, "HUD cash updated")
	ix._on_shop_choice("")
	check(not ix.shop_open and main.player.input_enabled, "Tschüss closes the menu")

	# Door: jumping the queue is refused without reputation loss.
	await _go(ix.points["club_door"])
	await _press_interact()
	check(ix.last_door_result.get("reason") == "queue", "bouncer sends you to the back of the queue")
	check(int(ix.life.reputation["nightlife"]) == 0, "no reputation lost for asking once")
	check("anstellen" in main.ui.message_label.text, "bouncer line shown")

	# Queue at the end for queue_wait_seconds, then return: obeying is not pestering.
	await _go(ix.points["queue_end"])
	await _frames(int((float(ix.econ["club"]["queue_wait_seconds"]) + 1.0) * 60))
	check(ix.queued_seconds >= float(ix.econ["club"]["queue_wait_seconds"]), "waited in the queue (%.1f s)" % ix.queued_seconds)
	await _go(ix.points["club_door"])
	await _press_interact()
	check(ix.last_door_result.get("admitted", false), "admitted after queueing (%s)" % ix.last_door_result.get("reason"))
	check(ix.life.cash_cents == start - 150 - 1500, "entry fee 15 € paid (%s)" % StrayLifeState.euro(ix.life.cash_cents))
	check(int(ix.life.reputation["nightlife"]) == 1, "nightlife reputation +1")

	# Daytime: closed.
	main.builder.set_day_mode(true)
	ix.door.since_refusal = INF
	await _press_interact()
	check(ix.last_door_result.get("reason") == "closed", "closed during the day")
	print("RESULT interaction_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
