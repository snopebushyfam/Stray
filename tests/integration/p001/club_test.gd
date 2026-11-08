## Integration test (club interior): admission -> inside, bar, Lea, exit, audio switch.
## Run: godot --headless --path . -s res://tests/integration/p001/club_test.gd
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


func _go(p: Vector3) -> void:
	main.player.global_position = p + Vector3(0, 0.95, 0)
	main.player.velocity = Vector3.ZERO
	await _frames(15)


func _run() -> void:
	main = load("res://src/p001/main.tscn").instantiate()
	root.add_child(main)
	await _frames(30)
	var ix: StrayInteractions = main.interactions
	var club: StrayClubInterior = main.club
	var life: StrayLifeState = ix.life
	check(not club.visible, "interior hidden while outside")

	# Queue, then get in.
	await _go(ix.points["queue_end"])
	await _frames(int((float(ix.econ["club"]["queue_wait_seconds"]) + 1.0) * 60))
	await _go(ix.points["club_door"])
	ix.interact()
	await _frames(int(2.0 * 60))
	check(life.flags.get("inside_club", false) and club.visible, "admitted -> inside the club")
	check(main.player.global_position.y < -55.0, "player is in the interior (y=%.1f)" % main.player.global_position.y)
	await _frames(30)
	check(main.player.is_on_floor(), "standing on the club floor")
	check(club.music.playing and not main.club_audio.playing, "club music on, street bass off")
	check(club.dancers.size() >= 8, "%d dancers on the floor" % club.dancers.size())

	# Bar: club prices.
	await _go(ix.points["club_bar"])
	check(ix.current == "club_bar" and "Bar" in main.ui.prompt_label.text, "bar prompt")
	var cash: int = life.cash_cents
	ix.interact()
	check(ix.shop_open and ix.active_shop == ix.bar_shop, "bar menu open")
	ix._on_shop_choice("koelsch_bar")
	check(life.cash_cents == cash - 350 and life.drinks_alcohol == 1, "Kölsch at the bar costs 3,50 €")
	ix._on_shop_choice("")

	# Lea: friendly answer -> social +1 and her name in the contacts.
	await _go(ix.points["club_lea"])
	check(ix.current == "club_lea", "Lea prompt")
	ix.interact()
	check(main.ui.shop_panel.visible, "dialogue options shown")
	ix._on_option(0)
	check(int(life.reputation["social"]) == 1, "friendly answer: social +1")
	check("Lea" in main.messages.known_contacts(), "Lea saved in contacts")
	check(main.player.input_enabled, "dialogue closed, movement back")

	# Out again.
	await _go(ix.points["club_exit"])
	ix.interact()
	await _frames(20)
	check(not life.flags.get("inside_club", true) and main.player.global_position.y > -5.0, "back on the street (y=%.1f)" % main.player.global_position.y)
	check(main.club_audio.playing and not club.music.playing and not club.visible, "street audio back, interior hidden")
	print("RESULT club_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
