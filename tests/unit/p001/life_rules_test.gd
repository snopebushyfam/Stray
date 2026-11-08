## Unit tests: money, kiosk purchases, NACHTFLUG door rules (Logic stories, Schritt 3).
## Run: godot --headless --path . -s res://tests/unit/p001/life_rules_test.gd
extends SceneTree

var _failed := 0
var _passed := 0
var econ: Dictionary


func check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("FAIL ", what)


func _initialize() -> void:
	econ = JSON.parse_string(FileAccess.get_file_as_string("res://data/p001/economy_config.json"))
	test_euro_format()
	test_pay_refuses_more_than_cash()
	test_kiosk_buy_deducts_and_adds_item()
	test_kiosk_buy_fails_when_broke()
	test_door_closed_by_day()
	test_door_requires_queue_without_rep_loss()
	test_door_admits_and_charges()
	test_door_refuses_drunk_and_costs_rep()
	test_door_pestering_costs_more()
	test_door_broke()
	test_door_rep_low_blocks()
	test_door_queue_then_return_is_not_pestering()
	print("RESULT life_rules_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _door() -> StrayBouncerRules:
	return StrayBouncerRules.new(econ["club"])


func test_euro_format() -> void:
	check(StrayLifeState.euro(1550) == "15,50 €", "euro 1550")
	check(StrayLifeState.euro(5) == "0,05 €", "euro 5")


func test_pay_refuses_more_than_cash() -> void:
	var s := StrayLifeState.new(100)
	check(not s.pay(150) and s.cash_cents == 100, "cannot pay 1,50 with 1,00")
	check(s.pay(100) and s.cash_cents == 0, "pay all")


func test_kiosk_buy_deducts_and_adds_item() -> void:
	var s := StrayLifeState.new(500)
	var shop := StrayKioskShop.new(econ["kiosk"])
	var r := shop.buy(s, "koelsch")
	check(r.ok and s.cash_cents == 320, "Kölsch costs 1,80 (cash %d)" % s.cash_cents)
	check(s.inventory.get("koelsch", 0) == 1 and s.drinks_alcohol == 1, "Kölsch in inventory, counts as alcohol")


func test_kiosk_buy_fails_when_broke() -> void:
	var s := StrayLifeState.new(100)
	var r := StrayKioskShop.new(econ["kiosk"]).buy(s, "mate")
	check(not r.ok and s.cash_cents == 100 and s.inventory.is_empty(), "no Mate for 1,00")
	check("2,50 €" in r.text, "shopkeeper names the price")


func test_door_closed_by_day() -> void:
	var s := StrayLifeState.new(5000)
	var r := _door().decide(s, false, 99.0)
	check(not r.admitted and r.reason == "closed" and s.cash_cents == 5000, "closed by day, no charge")


func test_door_requires_queue_without_rep_loss() -> void:
	var s := StrayLifeState.new(5000)
	var r := _door().decide(s, true, 3.0)
	check(not r.admitted and r.reason == "queue", "must queue")
	check(s.reputation["nightlife"] == 0, "queue-jumping costs no reputation")


func test_door_admits_and_charges() -> void:
	var s := StrayLifeState.new(5000)
	var r := _door().decide(s, true, 20.0)
	check(r.admitted and s.cash_cents == 3500 and s.reputation["nightlife"] == 1, "admitted, 15 € paid, +1 nightlife")
	check(s.flags.get("inside_club", false), "inside flag set")


func test_door_refuses_drunk_and_costs_rep() -> void:
	var s := StrayLifeState.new(5000)
	s.drinks_alcohol = 3
	var r := _door().decide(s, true, 20.0)
	check(not r.admitted and r.reason == "drunk" and s.reputation["nightlife"] == -1 and s.cash_cents == 5000, "too drunk: refused, -1, no charge")


func test_door_pestering_costs_more() -> void:
	var s := StrayLifeState.new(5000)
	s.drinks_alcohol = 3
	var d := _door()
	d.decide(s, true, 20.0)
	d.tick(5.0)
	var r := d.decide(s, true, 20.0)
	check(r.reason == "annoyed" and s.reputation["nightlife"] == -3, "asking again within 30 s: annoyed, -2 more")
	d.tick(31.0)
	s.drinks_alcohol = 0
	r = d.decide(s, true, 20.0)
	check(r.reason == "rep_low", "after cooldown the bad reputation (-3) still blocks")


func test_door_broke() -> void:
	var s := StrayLifeState.new(1000)
	var r := _door().decide(s, true, 20.0)
	check(not r.admitted and r.reason == "broke" and s.cash_cents == 1000 and "15,00 €" in r.text, "cannot pay entry")


func test_door_rep_low_blocks() -> void:
	var s := StrayLifeState.new(5000)
	s.reputation["nightlife"] = -3
	check(_door().decide(s, true, 20.0).reason == "rep_low", "reputation -3 blocks")


func test_door_queue_then_return_is_not_pestering() -> void:
	# Sent to the back, queued 16 s, came back: that is obeying, not pestering.
	var s := StrayLifeState.new(5000)
	var d := _door()
	d.decide(s, true, 0.0)
	d.tick(16.0)
	var r := d.decide(s, true, 16.0)
	check(r.admitted, "queue as told, then admitted (got %s)" % r.reason)
	check(s.reputation["nightlife"] == 1, "no pestering penalty (nightlife %d)" % s.reputation["nightlife"])
