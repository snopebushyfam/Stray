## Unit tests (R2): calendar days, rent standing order, overdue, eviction.
## Run: godot --headless --path . -s res://tests/unit/p001/day_rent_test.gd
extends SceneTree

var _failed := 0
var _passed := 0
var phone: Dictionary
var home: Dictionary


func check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("FAIL ", what)


func _initialize() -> void:
	phone = JSON.parse_string(FileAccess.get_file_as_string("res://data/p001/phone_config.json"))
	home = JSON.parse_string(FileAccess.get_file_as_string("res://data/p001/home_config.json"))
	test_calendar()
	test_day_changed_signal_and_sleep_jump()
	test_rent_due_in_17_days_from_start()
	test_rent_paid_on_due_day()
	test_rent_reminder_three_days_before()
	test_rent_overdue_then_paid_after_wage()
	test_rent_eviction_after_grace()
	print("RESULT day_rent_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _clock() -> StrayGameClock:
	return StrayGameClock.new(phone["clock"])


func test_calendar() -> void:
	var c := _clock()
	check(c.date_text() == "Sa 14.11.", "start Sa 14.11. (%s)" % c.date_text())
	check(String(c.date_of(1).text) == "So 15.11.", "day 1 = So 15.11.")
	check(String(c.date_of(17).text) == "Di 01.12.", "day 17 = Di 01.12. (%s)" % c.date_of(17).text)
	check(String(c.date_of(48).text) == "Fr 01.01." and int(c.date_of(48).year) == 2027, "year rolls over (%s %d)" % [c.date_of(48).text, c.date_of(48).year])


func test_day_changed_signal_and_sleep_jump() -> void:
	var c := _clock()
	var days: Array[int] = []
	c.day_changed.connect(func(d): days.append(d))
	c.set_time("10:00")  # 23:10 -> next morning 10:00
	check(c.day_index() == 1 and c.hhmm() == "10:00" and days == [1], "sleep to 10:00 = next day (%s, %s)" % [c.date_text(), days])
	check(c.is_daytime(), "10:00 is daylight")


func test_rent_due_in_17_days_from_start() -> void:
	var r := StrayRent.new(home["rent"])
	check(r.days_until_due(_clock(), 0) == 17, "rent due in 17 days from 14.11.")


func test_rent_paid_on_due_day() -> void:
	var c := _clock()
	var r := StrayRent.new(home["rent"])
	var life := StrayLifeState.new(0, 50000)
	var ev := r.process_until(c, 17, life)
	check("rent_paid" in ev and life.account_cents == 5000 and r.payments == 1, "450 € debited on 01.12. (events %s)" % [ev])
	check(life.transactions[-1].label == "Miete (Dauerauftrag)", "booking label")


func test_rent_reminder_three_days_before() -> void:
	var r := StrayRent.new(home["rent"])
	var ev := r.process_until(_clock(), 14, StrayLifeState.new(0, 0))
	check(ev == ["rent_due_in_3"], "only the 3-day reminder up to 28.11. (%s)" % [ev])


func test_rent_overdue_then_paid_after_wage() -> void:
	var c := _clock()
	var r := StrayRent.new(home["rent"])
	var life := StrayLifeState.new(0, 12000)
	var ev := r.process_until(c, 17, life)
	check("rent_failed" in ev and r.overdue_days == 1 and life.account_cents == 12000, "failed debit -> overdue, no partial debit")
	life.credit_account(40000, "Lohn")
	ev = r.process_until(c, 18, life)
	check("rent_paid" in ev and r.overdue_days == 0 and not r.evicted, "retried next day and paid")


func test_rent_eviction_after_grace() -> void:
	var c := _clock()
	var r := StrayRent.new(home["rent"])
	# Due Tue 01.12. (day 17) = overdue day 1; grace 3 -> still housed through day 19 (Thu 03.12.).
	var ev := r.process_until(c, 19, StrayLifeState.new(0, 0))
	check(not r.evicted and r.overdue_days == 3, "still housed on overdue day 3 (%s)" % [ev])
	ev = r.process_until(c, 20, StrayLifeState.new(0, 0))
	check(r.evicted and "evicted" in ev, "evicted on overdue day 4 (Fr 04.12.)")
	var r2 := StrayRent.new(home["rent"])
	r2.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	check(r2.evicted and r2.last_processed_day == 20, "rent state survives saving")
