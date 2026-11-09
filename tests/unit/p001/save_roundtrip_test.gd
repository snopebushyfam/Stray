## Unit tests (R1): to_dict/from_dict round trips of the saved systems + file read/write.
## Run: godot --headless --path . -s res://tests/unit/p001/save_roundtrip_test.gd
extends SceneTree

var _failed := 0
var _passed := 0


func check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("FAIL ", what)


func _initialize() -> void:
	var phone: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/p001/phone_config.json"))
	# Life state.
	var a := StrayLifeState.new(3500, 12000)
	a.withdraw(2000)
	a.pay(180, "Kiosk: Kölsch")
	a.add_item("koelsch", ["alcohol"])
	a.change_reputation("nightlife", -2)
	a.flags["inside_club"] = true
	var json := JSON.stringify(a.to_dict())
	var b := StrayLifeState.new(0, 0)
	b.from_dict(JSON.parse_string(json))
	check(b.cash_cents == a.cash_cents and b.account_cents == a.account_cents, "money survives JSON")
	check(b.inventory.get("koelsch", 0) == 1 and b.drinks_alcohol == 1, "inventory + alcohol survive")
	check(b.reputation["nightlife"] == -2 and b.flags.get("inside_club", false), "reputation + flags survive")
	check(b.transactions.size() == 2 and b.transactions[1].label == "Kiosk: Kölsch" and b.transactions[1].cents == -180, "bookings survive")
	# Clock.
	var c := StrayGameClock.new(phone["clock"])
	c.advance(1234.0)
	var c2 := StrayGameClock.new(phone["clock"])
	c2.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	check(c2.hhmm() == c.hhmm() and is_equal_approx(c2.minutes, c.minutes), "clock survives (%s)" % c2.hhmm())
	# Messages, including a renamed contact.
	var m := StrayMessages.new(phone)
	m.trigger("start", "23:10")
	m.trigger("club_admitted", "23:40")
	m.contacts["unbekannt"]["name"] = "Lea"
	m.mark_all_read()
	var m2 := StrayMessages.new(phone)
	m2.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())))
	check(m2.inbox.size() == 3 and m2.unread == 0, "inbox + read state survive")
	check("Lea" in m2.known_contacts(), "renamed contact survives")
	check(m2.trigger("start") == 0 and m2.trigger("club_admitted") == 0, "delivered messages are not sent again after loading")
	# Older/partial save: missing keys keep defaults.
	var d := StrayLifeState.new(500, 900)
	d.from_dict({"cash_cents": 100})
	check(d.cash_cents == 100 and d.account_cents == 900, "missing keys keep defaults")
	# File round trip + corrupt file.
	var path := "user://test_save_roundtrip.json"
	check(StraySaveGame.write(path, {"version": 1, "x": 5}).is_empty(), "write save file")
	check(int(StraySaveGame.read(path).get("x", 0)) == 5, "read save file")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	check(StraySaveGame.read(path).is_empty() and not StraySaveGame.exists(path), "corrupt file reads as no save")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("RESULT save_roundtrip_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
