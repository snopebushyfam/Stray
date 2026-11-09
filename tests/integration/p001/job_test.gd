## Integration test (R3): apply via phone, work a kiosk shift, get paid, miss a shift.
## Run: godot --headless --path . -s res://tests/integration/p001/job_test.gd
extends SceneTree

const PATH := "user://test_job_it.json"
var _failed := 0
var _passed := 0


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


func _has_msg(m: Node, id: String) -> bool:
	for msg in m.messages.inbox:
		if msg.id == id:
			return true
	return false


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var m: Node = load("res://src/p001/main.tscn").instantiate()
	m.save_path = PATH
	root.add_child(m)
	await _frames(30)
	var ix: StrayInteractions = m.interactions
	var life: StrayLifeState = ix.life
	var job: StrayKioskJob = m.job

	# Apply in the phone's jobs app.
	m.phone.toggle()
	m.phone.open_app("jobs")
	var apply_btn: Button = null
	for c in m.phone._body.get_children():
		if c is Button and (c as Button).text == "Bewerben":
			apply_btn = c
	check(apply_btn != null, "jobs app offers 'Bewerben'")
	apply_btn.pressed.emit()
	await _frames(3)
	check(job.employed and _has_msg(m, "job_accepted") and "Erol (Kiosk)" in m.messages.known_contacts(), "hired; Erol writes and is a contact")
	m.phone.toggle()

	# Next day 18:05 at the kiosk.
	m.clock.from_dict({"minutes": 1440.0 + StrayGameClock.parse_hhmm("18:05")})
	await _frames(5)
	m.player.global_position = ix.points["kiosk"] + Vector3(0, 0.95, 0)
	await _frames(15)
	check("Schicht beginnen" in m.ui.prompt_label.text, "kiosk offers 'Schicht beginnen' (%s)" % m.ui.prompt_label.text)
	var account: int = life.account_cents
	var cash: int = life.cash_cents
	ix.interact()
	check(job.in_shift and m.ui.shop_panel.visible and not m.player.input_enabled, "shift started, first customer orders")
	check(ix._customer != null, "customer figure at the kiosk")
	# Serve every order correctly by picking the matching kiosk item.
	var items: Array = ix.shop.items()
	var guard := 0
	while job.in_shift and guard < 20:
		var want: String = job.current_order().get("item", "")
		var idx := -1
		for i in items.size():
			if items[i].id == want:
				idx = i
		ix._on_option(idx)
		guard += 1
		await _frames(2)
	check(not job.in_shift and job.correct == 8 and job.shifts_done == 1, "8/8 served, shift over")
	check(life.account_cents == account + 5400, "54 € wage to the account")
	check(life.cash_cents == cash + 400, "4 € tips in cash")
	check(m.clock.hhmm() == "22:00", "clock at shift end (%s)" % m.clock.hhmm())
	check(_has_msg(m, "job_paid") and ix._customer == null and m.player.input_enabled, "Erol confirms, customer gone, control back")
	check(StraySaveGame.exists(PATH), "autosaved after the shift")

	# Skip the next shift: warning.
	m.clock.from_dict({"minutes": 2.0 * 1440.0 + StrayGameClock.parse_hhmm("17:00")})
	m.clock.from_dict({"minutes": 2.0 * 1440.0 + StrayGameClock.parse_hhmm("20:00")})
	await _frames(3)
	check(job.warnings == 1 and _has_msg(m, "job_warning"), "missed shift -> warning from Erol")

	# Save / load keeps the job.
	check(m.save_game("test"), "save")
	m.queue_free()
	await _frames(5)
	var m2: Node = load("res://src/p001/main.tscn").instantiate()
	m2.save_path = PATH
	root.add_child(m2)
	await _frames(30)
	check(m2.load_game() and m2.job.employed and m2.job.warnings == 1 and m2.job.shifts_done == 1, "job state restored")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("RESULT job_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
