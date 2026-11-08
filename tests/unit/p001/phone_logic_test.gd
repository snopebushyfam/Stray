## Unit tests (Schritt 4): game clock, bank/ATM bookings, messenger triggers.
## Run: godot --headless --path . -s res://tests/unit/p001/phone_logic_test.gd
extends SceneTree

var _failed := 0
var _passed := 0
var phone: Dictionary


func check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("FAIL ", what)


func _initialize() -> void:
	phone = JSON.parse_string(FileAccess.get_file_as_string("res://data/p001/phone_config.json"))
	test_clock_starts_and_advances()
	test_clock_wraps_past_midnight_and_club_hours()
	test_clock_daytime_and_set_time()
	test_bank_withdraw_and_bookings()
	test_withdraw_refused_without_balance()
	test_messages_start_and_once_only()
	test_messages_event_reveals_unknown_contact()
	test_messages_cash_threshold()
	print("RESULT phone_logic_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func test_clock_starts_and_advances() -> void:
	var c := StrayGameClock.new(phone["clock"])
	check(c.hhmm() == "23:10", "starts 23:10 (%s)" % c.hhmm())
	c.advance(60.0)  # 60 real s * 10 = 10 game minutes
	check(c.hhmm() == "23:20", "10x speed: 60 s real = 10 min (%s)" % c.hhmm())


func test_clock_wraps_past_midnight_and_club_hours() -> void:
	var c := StrayGameClock.new(phone["clock"])
	check(c.club_open(), "club open at 23:10")
	c.advance(360.0)  # 360 real s * 10 = 60 game min -> 00:10
	check(c.hhmm() == "00:10" and c.hour() == 0, "wraps to 00:10 (%s)" % c.hhmm())
	check(c.club_open(), "club still open after midnight")
	c.set_time("06:30")
	check(not c.club_open(), "club closed at 06:30")
	c.set_time("22:59")
	check(not c.club_open(), "club closed at 22:59")


func test_clock_daytime_and_set_time() -> void:
	var c := StrayGameClock.new(phone["clock"])
	check(not c.is_daytime(), "23:10 is night")
	c.set_time("14:00")
	check(c.is_daytime() and c.hhmm() == "14:00", "14:00 is day")
	check(c.minutes > StrayGameClock.parse_hhmm("23:10"), "set_time never goes back in time")


func test_bank_withdraw_and_bookings() -> void:
	var s := StrayLifeState.new(500, 12000)
	check(s.withdraw(2000) and s.cash_cents == 2500 and s.account_cents == 10000, "ATM: 20 € account -> cash")
	s.pay(180, "Kiosk: Kölsch")
	check(s.transactions.size() == 2 and s.transactions[1].label == "Kiosk: Kölsch" and s.transactions[1].cents == -180, "bookings recorded")


func test_withdraw_refused_without_balance() -> void:
	var s := StrayLifeState.new(0, 1000)
	check(not s.withdraw(2000) and s.account_cents == 1000 and s.transactions.is_empty(), "no withdrawal beyond the balance")


func test_messages_start_and_once_only() -> void:
	var m := StrayMessages.new(phone)
	check(m.trigger("start", "23:10") == 2 and m.unread == 2, "two start messages")
	check(m.trigger("start") == 0 and m.inbox.size() == 2, "delivered only once")


func test_messages_event_reveals_unknown_contact() -> void:
	var m := StrayMessages.new(phone)
	check(not "Unbekannt" in m.known_contacts(), "unknown contact hidden at start")
	m.trigger("club_admitted")
	check("Unbekannt" in m.known_contacts() and m.inbox[-1].id == "club_seen", "club event delivers + reveals contact")


func test_messages_cash_threshold() -> void:
	var m := StrayMessages.new(phone)
	m.check_cash(800)
	check(m.inbox.is_empty(), "no low-cash message at 8 €")
	m.check_cash(450)
	check(m.inbox.size() == 1 and m.inbox[0].id == "broke", "low-cash message below 5 €")
