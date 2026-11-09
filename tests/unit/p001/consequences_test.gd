## Unit tests (R4): heat sources + cooldowns, decay, police check outcomes, fines, platzverweis,
## arrest, shoplifting, persistence.
## Run: godot --headless --path . -s res://tests/unit/p001/consequences_test.gd
extends SceneTree

var _failed := 0
var _passed := 0
var cfg: Dictionary
var phone: Dictionary


func check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("FAIL ", what)


func _initialize() -> void:
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/p001/consequences_config.json"))
	phone = JSON.parse_string(FileAccess.get_file_as_string("res://data/p001/phone_config.json"))
	test_sources_and_cooldown()
	test_decay()
	test_check_trigger()
	test_outcome_warning()
	test_outcome_fine_cash_then_account()
	test_outcome_platzverweis_drunk()
	test_run_away_then_arrest()
	test_shoplifting()
	test_persistence()
	print("RESULT consequences_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _c() -> StrayConsequences:
	return StrayConsequences.new(cfg)


func _clock() -> StrayGameClock:
	return StrayGameClock.new(phone["clock"])


func test_sources_and_cooldown() -> void:
	var c := _c()
	var k := _clock()
	check(c.report("jaywalk", k) == 6.0 and c.heat == 6.0, "jaywalk +6")
	check(c.report("jaywalk", k) == 0.0, "cooldown blocks a second jaywalk")
	k.advance(60.0 * 6.0)  # +6 game minutes
	check(c.report("jaywalk", k) == 6.0 and c.incidents.size() == 2, "after the cooldown it counts again")
	check(c.report("unknown", k) == 0.0, "unknown events ignored")


func test_decay() -> void:
	var c := _c()
	c._set_heat(30.0)
	c.decay(120.0)
	check(is_equal_approx(c.heat, 18.0), "decays 6 per game hour (%.1f)" % c.heat)
	c.decay(10000.0)
	check(c.heat == 0.0, "never below 0")


func test_check_trigger() -> void:
	var c := _c()
	var k := _clock()
	c._set_heat(20.0)
	check(not c.police_wants_check(k, 5.0), "no check below 30 heat")
	c._set_heat(35.0)
	check(c.police_wants_check(k, 10.0) and not c.police_wants_check(k, 40.0), "check when close and heat >= 30")


func test_outcome_warning() -> void:
	var c := _c()
	var k := _clock()
	var life := StrayLifeState.new(1000, 0)
	c._set_heat(35.0)
	var r := c.resolve_check(true, life, k)
	check(r.outcome == "warning" and life.cash_cents == 1000 and c.heat == 15.0 and c.police_record == 0, "35 -> warning, no fine, heat 15")
	check(not c.police_wants_check(k, 1.0), "cooldown after a check")


func test_outcome_fine_cash_then_account() -> void:
	var c := _c()
	var life := StrayLifeState.new(2000, 10000)
	c._set_heat(60.0)
	var r := c.resolve_check(true, life, _clock())
	check(r.outcome == "fine" and r.fine_cents == 6000, "60 -> 60 € fine")
	check(life.cash_cents == 0 and life.account_cents == 6000, "20 € cash + 40 € from the account")
	check(c.police_record == 1 and is_equal_approx(c.heat, 25.0), "record +1, heat 25")


func test_outcome_platzverweis_drunk() -> void:
	var c := _c()
	var k := _clock()
	var life := StrayLifeState.new(0, 0)
	life.drinks_alcohol = 5
	c._set_heat(40.0)
	var r := c.resolve_check(true, life, k)
	check(r.outcome == "platzverweis" and c.has_platzverweis(k), "drunk (5) -> platzverweis")
	k.set_time("05:59")
	check(c.has_platzverweis(k), "still valid at 05:59")
	k.set_time("06:00")
	check(not c.has_platzverweis(k), "over at 06:00")


func test_run_away_then_arrest() -> void:
	var c := _c()
	var k := _clock()
	var life := StrayLifeState.new(5000, 50000)
	c._set_heat(40.0)
	var r := c.resolve_check(false, life, k)
	check(r.outcome == "ran" and is_equal_approx(c.heat, 75.0), "running away: +35 heat")
	c._set_heat(95.0)
	c.last_check_minutes = -1e9
	r = c.resolve_check(false, life, k)
	check(r.outcome == "arrest" and k.hhmm() == "08:00" and k.day_index() == 1, "heat >= 100 -> arrest, released next day 08:00")
	check(life.cash_cents + life.account_cents == 55000 - 20000 and c.heat == 0.0, "200 € fine, heat reset")


func test_shoplifting() -> void:
	var c := _c()
	var k := _clock()
	var results: Array = []
	for i in 6:
		results.append(c.try_shoplift(k).caught)
		if c.kiosk_banned:
			break
	check(c.kiosk_banned and results[-1] == true, "eventually caught -> kiosk ban (%s)" % [results])
	check(c.heat >= 45.0, "caught -> heat +45")
	var c2 := _c()
	var r2: Array = []
	for i in 6:
		r2.append(c2.try_shoplift(k).caught)
		if c2.kiosk_banned:
			break
	check(results == r2, "deterministic with the configured seed")


func test_persistence() -> void:
	var c := _c()
	var k := _clock()
	c.report("public_drunk", k)
	c.kiosk_banned = true
	c.platzverweis_until_minutes = 2000.0
	var c2 := _c()
	c2.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	check(c2.heat == c.heat and c2.kiosk_banned and c2.platzverweis_until_minutes == 2000.0 and c2.incidents.size() == 1, "state survives saving")
	check(c2.report("public_drunk", k) == 0.0, "cooldowns survive saving")
