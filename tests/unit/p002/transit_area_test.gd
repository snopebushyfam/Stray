## Unit tests (R5): U-Bahn rules (tickets, rides, fare checks, fines, save state) and the P002
## area height grid. Run: godot --headless --path . -s res://tests/unit/p002/transit_area_test.gd
extends SceneTree

var _failed := 0
var _passed := 0
var tcfg: Dictionary
var phone: Dictionary


func check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("FAIL ", what)


func _initialize() -> void:
	tcfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/p002/transit_config.json"))
	phone = JSON.parse_string(FileAccess.get_file_as_string("res://data/p001/phone_config.json"))
	test_ticket_purchase_takes_cash_once()
	test_ticket_purchase_without_cash_fails()
	test_ride_switches_station_and_advances_clock()
	test_ride_with_ticket_never_fined()
	test_fare_dodging_checked_pays_fine_from_cash_then_account_then_unpaid()
	test_check_sequence_is_deterministic_and_saved()
	test_area_grid_sampling_matches_vertices()
	test_area_points_on_real_data()
	print("RESULT transit_area_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _cfg(chance: float) -> Dictionary:
	var c: Dictionary = tcfg.duplicate(true)
	c["fare_dodging"]["check_chance"] = chance
	return c


func test_ticket_purchase_takes_cash_once() -> void:
	var t := StrayTransit.new(tcfg)
	var life := StrayLifeState.new(1000, 0)
	var r := t.buy_ticket(life)
	check(r.ok and t.has_ticket and life.cash_cents == 1000 - t.ticket_price(), "ticket bought for %d ct" % t.ticket_price())
	check(t.buy_ticket(life).reason == "already" and life.cash_cents == 1000 - t.ticket_price(), "second ticket refused, no charge")


func test_ticket_purchase_without_cash_fails() -> void:
	var t := StrayTransit.new(tcfg)
	var life := StrayLifeState.new(100, 50000)
	check(t.buy_ticket(life).reason == "no_money" and not t.has_ticket and life.cash_cents == 100, "machine takes cash only")


func test_ride_switches_station_and_advances_clock() -> void:
	var t := StrayTransit.new(_cfg(0.0))
	var clock := StrayGameClock.new(phone["clock"])
	var m0 := clock.minutes
	var r := t.ride(StrayLifeState.new(0, 0), clock)
	check(r.from == "friesenplatz" and r.to == "dom_hbf" and t.station == "dom_hbf", "Friesenplatz -> Dom/Hbf")
	check(is_equal_approx(clock.minutes - m0, float(t.ride_minutes())), "clock +%d min" % t.ride_minutes())
	t.ride(StrayLifeState.new(0, 0), clock)
	check(t.station == "friesenplatz" and t.rides == 2, "and back")


func test_ride_with_ticket_never_fined() -> void:
	var t := StrayTransit.new(_cfg(1.0))
	var life := StrayLifeState.new(1000, 0)
	t.buy_ticket(life)
	var r := t.ride(life, null)
	check(r.checked and r.had_ticket and r.fined_cents == 0 and life.cash_cents == 1000 - t.ticket_price(), "checked with ticket: no fine")
	check(not t.has_ticket, "ticket used up")


func test_fare_dodging_checked_pays_fine_from_cash_then_account_then_unpaid() -> void:
	var fine := int(tcfg["fare_dodging"]["fine_cents"])
	var t := StrayTransit.new(_cfg(1.0))
	var rich := StrayLifeState.new(fine + 10, 0)
	var r := t.ride(rich, null)
	check(r.fined_cents == fine and r.paid == "cash" and rich.cash_cents == 10, "fine paid in cash")
	var bank := StrayLifeState.new(0, fine)
	r = t.ride(bank, null)
	check(r.paid == "account" and bank.account_cents == 0, "fine debited from the account")
	var broke := StrayLifeState.new(0, 0)
	r = t.ride(broke, null)
	check(r.paid == "unpaid" and t.unpaid_fines_cents == fine, "fine left unpaid")
	var t0 := StrayTransit.new(_cfg(0.0))
	r = t0.ride(StrayLifeState.new(5000, 0), null)
	check(not r.checked and r.fined_cents == 0, "no check, no fine")


func test_check_sequence_is_deterministic_and_saved() -> void:
	var a := StrayTransit.new(_cfg(0.5))
	var b := StrayTransit.new(_cfg(0.5))
	var seq_a: Array = []
	var seq_b: Array = []
	for i in 6:
		seq_a.append(a.ride(StrayLifeState.new(0, 0), null).checked)
	for i in 3:
		seq_b.append(b.ride(StrayLifeState.new(0, 0), null).checked)
	var c := StrayTransit.new(_cfg(0.5))
	c.from_dict(JSON.parse_string(JSON.stringify(b.to_dict())))
	for i in 3:
		seq_b.append(c.ride(StrayLifeState.new(0, 0), null).checked)
	check(seq_a == seq_b, "same check sequence after save/load %s vs %s" % [seq_a, seq_b])
	check(c.station == a.station and c.rides == 6, "station + ride count restored")
	check(seq_a.has(true) and seq_a.has(false), "chance 0.5 gives both outcomes in 6 rides")


func test_area_grid_sampling_matches_vertices() -> void:
	var a := StrayAreaLayout.new()
	var json := {"schema": StrayAreaLayout.SCHEMA, "lod2_mesh": "x.obj", "hbf_en": [0, 0],
		"height_grid": {"min_en": [10, 20], "step": 2.0, "nx": 3, "ny": 2, "z": [0, 1, 2, 3, 4, 5]},
		"ubahn_player": {"en": [12, 21], "exit_en": [12, 21]}}
	check(a.parse(JSON.stringify(json)) == "", "parses a 3x2 grid")
	check(is_equal_approx(a.ground_z_at(Vector2(10, 20)), 0.0) and is_equal_approx(a.ground_z_at(Vector2(14, 22)), 5.0), "corner vertices")
	check(is_equal_approx(a.ground_z_at(Vector2(11, 21)), 2.0), "bilinear centre of first cell = 2.0")
	check(is_equal_approx(a.ground_z_at(Vector2(-50, 99)), 3.0), "clamped outside the grid")
	check(a.contains(Vector2(12, 21), 0.5) and not a.contains(Vector2(9, 21), 0.5), "contains()")
	json["height_grid"]["z"] = [0, 1]
	check(a.parse(JSON.stringify(json)) != "", "size mismatch rejected")


func test_area_points_on_real_data() -> void:
	var a := StrayAreaLayout.load_file("res://data/p002/P002_Area.json")
	check(a != null, "P002 area loads")
	if a == null:
		return
	var up := StrayStreetLayout._v2(a.ubahn_player["en"])
	check(a.contains(up) and a.contains(a.spawn_en), "U-Bahn entrance + spawn inside the walkable area")
	check(a.hbf_en.distance_to(up) < 120.0, "U-Bahn entrance near the Hbf (%.0f m)" % a.hbf_en.distance_to(up))
	var g := a.ground_z_at(a.spawn_en)
	check(g > a.z_min - 0.01 and g < a.z_max + 0.01, "spawn ground within the DGM range (%.2f m)" % g)
	check(a.lamps.get("items", []).size() >= 10, "at least 10 lamps")
