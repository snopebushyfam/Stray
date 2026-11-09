## Unit tests (R3): kiosk job rules - punctuality, serving, wage, warnings, firing.
## Run: godot --headless --path . -s res://tests/unit/p001/kiosk_job_test.gd
extends SceneTree

var _failed := 0
var _passed := 0
var jobs: Dictionary
var phone: Dictionary


func check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("FAIL ", what)


func _initialize() -> void:
	jobs = JSON.parse_string(FileAccess.get_file_as_string("res://data/p001/jobs_config.json"))
	phone = JSON.parse_string(FileAccess.get_file_as_string("res://data/p001/phone_config.json"))
	test_not_employed_until_applied()
	test_start_window()
	test_perfect_shift_pays_wage_and_tips()
	test_late_start_cuts_wage()
	test_mistakes_warn_then_fire()
	test_missed_shift_warns()
	test_orders_deterministic_per_day()
	print("RESULT kiosk_job_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _job() -> StrayKioskJob:
	return StrayKioskJob.new(jobs["kiosk_job"])


func _clock_at(day: int, hhmm: String) -> StrayGameClock:
	var c := StrayGameClock.new(phone["clock"])
	c.minutes = day * 1440.0 + StrayGameClock.parse_hhmm(hhmm)
	return c


func _work(j: StrayKioskJob, life: StrayLifeState, right: int) -> void:
	for i in j.orders.size():
		j.serve(String(j.current_order().item) if i < right else "nonsense", life)


func test_not_employed_until_applied() -> void:
	var j := _job()
	check(j.start_status(_clock_at(1, "18:00")) == "not_employed", "cannot work before applying")
	check(j.apply() and not j.apply(), "apply once")


func test_start_window() -> void:
	var j := _job()
	j.apply()
	check(j.start_status(_clock_at(1, "17:30")) == "too_early", "17:30 too early")
	check(j.start_status(_clock_at(1, "18:10")) == "on_time", "18:10 on time")
	check(j.start_status(_clock_at(1, "18:40")) == "late", "18:40 late")
	check(j.start_status(_clock_at(1, "19:30")) == "too_late", "19:30 too late")


func test_perfect_shift_pays_wage_and_tips() -> void:
	var j := _job()
	j.apply()
	var life := StrayLifeState.new(0, 0)
	var c := _clock_at(1, "18:05")
	check(j.start_shift(c) == "on_time" and j.orders.size() == 8, "shift with 8 customers")
	_work(j, life, 8)
	check(j.shift_complete() and j.correct == 8, "all served right")
	var r := j.finish_shift(c, life)
	check(r.wage == 5400 and life.account_cents == 5400, "4 h x 13,50 = 54 € to the account")
	check(life.cash_cents == 400 and not r.warning, "8 x 0,50 € tips in cash, no warning")
	check(j.start_status(c) == "done_today", "one shift per day")


func test_late_start_cuts_wage() -> void:
	var j := _job()
	j.apply()
	var life := StrayLifeState.new(0, 0)
	var c := _clock_at(1, "18:30")
	check(j.start_shift(c) == "late" and j.shift_late_minutes == 30, "30 min late")
	_work(j, life, 8)
	check(j.finish_shift(c, life).wage == 4050, "late: 25 % cut -> 40,50 €")


func test_mistakes_warn_then_fire() -> void:
	var j := _job()
	j.apply()
	var life := StrayLifeState.new(0, 0)
	var c := _clock_at(1, "18:00")
	j.start_shift(c)
	_work(j, life, 5)  # 3 mistakes > 2
	var r := j.finish_shift(c, life)
	check(r.warning and j.warnings == 1 and j.employed, "3 mistakes -> warning, still employed")
	var c2 := _clock_at(2, "18:00")
	j.start_shift(c2)
	_work(j, life, 4)
	r = j.finish_shift(c2, life)
	check(r.fired and j.fired and not j.employed, "second warning -> fired")
	check(j.start_status(_clock_at(3, "18:00")) == "not_employed" and not j.apply(), "fired: no shifts, cannot re-apply")


func test_missed_shift_warns() -> void:
	var j := _job()
	j.apply()
	check(j.check_missed(_clock_at(1, "18:30")) == "", "not missed while still inside the window")
	check(j.check_missed(_clock_at(1, "19:30")) == "missed" and j.warnings == 1, "no show by 19:00 -> missed + warning")
	check(j.check_missed(_clock_at(1, "21:00")) == "", "counted once per day")
	var j2 := StrayKioskJob.new(jobs["kiosk_job"])
	j2.from_dict(JSON.parse_string(JSON.stringify(j.to_dict())))
	check(j2.employed and j2.warnings == 1 and j2.last_shift_day == 1, "job state survives saving")


func test_orders_deterministic_per_day() -> void:
	var a := _job()
	a.apply()
	a.start_shift(_clock_at(3, "18:00"))
	var b := _job()
	b.apply()
	b.start_shift(_clock_at(3, "18:00"))
	check(JSON.stringify(a.orders) == JSON.stringify(b.orders), "same day -> same customers")
