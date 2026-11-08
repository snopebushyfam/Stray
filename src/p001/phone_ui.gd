## Smartphone UI for Prototype 001 (GDD: messenger, map, bank, jobs, contacts).
## Portrait phone on the right; Tab / touch button toggles it. Apps read StrayLifeState,
## StrayMessages, StrayGameClock and phone_config.json; nothing here owns game rules.
class_name StrayPhone
extends CanvasLayer

signal opened_changed(open: bool)

var life: StrayLifeState
var messages: StrayMessages
var clock: StrayGameClock
var cfg: Dictionary = {}
var battery: float = 64.0
var is_open := false
var current_app := "home"
var map: StrayPhoneMap

var _frame: PanelContainer
var _status: Label
var _body: VBoxContainer
var _toggle_button: Button


func setup(p_life: StrayLifeState, p_messages: StrayMessages, p_clock: StrayGameClock, p_cfg: Dictionary, p_map: StrayPhoneMap) -> void:
	life = p_life
	messages = p_messages
	clock = p_clock
	cfg = p_cfg
	map = p_map
	battery = float(cfg.get("battery", {}).get("start_percent", 64))
	_frame = PanelContainer.new()
	_frame.anchor_left = 1.0
	_frame.anchor_right = 1.0
	_frame.anchor_top = 0.5
	_frame.anchor_bottom = 0.5
	_frame.offset_left = -400
	_frame.offset_right = -30
	_frame.offset_top = -330
	_frame.offset_bottom = 330
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.07, 0.97)
	sb.border_color = Color(0.55, 0.55, 0.6)
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(28)
	sb.set_content_margin_all(16)
	_frame.add_theme_stylebox_override("panel", sb)
	add_child(_frame)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_frame.add_child(col)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 15)
	col.add_child(_status)
	_body = VBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	col.add_child(_body)
	_frame.visible = false
	_toggle_button = Button.new()
	_toggle_button.text = "Handy"
	_toggle_button.position = Vector2(12, 110)
	_toggle_button.custom_minimum_size = Vector2(110, 44)
	_toggle_button.visible = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	_toggle_button.pressed.connect(toggle)
	add_child(_toggle_button)
	messages.received.connect(func(_m): _refresh())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("phone"):
		toggle()


func toggle() -> void:
	is_open = not is_open
	_frame.visible = is_open
	if is_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		open_app("home")
	opened_changed.emit(is_open)


func _process(delta: float) -> void:
	if clock:
		var per_hour: float = float(cfg.get("battery", {}).get("drain_percent_per_game_hour", 6.0))
		battery = maxf(1.0, battery - per_hour * delta * clock.rate / 3600.0)
	if is_open:
		_status.text = "%s %s  %s      🔋 %d%%%s" % [clock.cfg.get("weekday", ""), clock.cfg.get("date", ""), clock.hhmm(), int(battery),
			("   ✉ %d" % messages.unread) if messages.unread > 0 else ""]
		if current_app == "map":
			map.queue_redraw()


func _clear() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		if c != map:
			c.queue_free()


func _title(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 22)
	_body.add_child(l)


func _line(text: String, size: int = 16, color := Color(1, 1, 1, 0.9)) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	_body.add_child(l)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(cb)
	_body.add_child(b)
	return b


func _back() -> void:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(spacer)
	_button("← Zurück", func(): open_app("home"))


func _refresh() -> void:
	if is_open:
		open_app(current_app)


## Shows an app: "home", "bank", "map", "messages", "contacts", "jobs".
func open_app(app: String) -> void:
	current_app = app
	_clear()
	match app:
		"home":
			_title("STRAY")
			_button("💶  Bank", func(): open_app("bank"))
			_button("🗺  Karte", func(): open_app("map"))
			_button("✉  Nachrichten%s" % ((" (%d neu)" % messages.unread) if messages.unread > 0 else ""), func(): open_app("messages"))
			_button("👤  Kontakte", func(): open_app("contacts"))
			_button("💼  Jobs", func(): open_app("jobs"))
		"bank":
			_title("Bank")
			_line("Konto:   %s" % StrayLifeState.euro(life.account_cents), 20)
			_line("Bargeld: %s" % StrayLifeState.euro(life.cash_cents), 20)
			_line("Letzte Buchungen", 15, Color(1, 1, 1, 0.6))
			var shown := 0
			for i in range(life.transactions.size() - 1, -1, -1):
				var t: Dictionary = life.transactions[i]
				_line("%s   %s" % [t.label, StrayLifeState.euro(t.cents)], 15)
				shown += 1
				if shown >= 6:
					break
			if shown == 0:
				_line("Noch keine Buchungen.", 15, Color(1, 1, 1, 0.6))
			_back()
		"map":
			_title("Karte")
			map.custom_minimum_size = Vector2(320, 420)
			_body.add_child(map)
			map.queue_redraw()
			_back()
		"messages":
			_title("Nachrichten")
			messages.mark_all_read()
			for i in range(messages.inbox.size() - 1, -1, -1):
				var m: Dictionary = messages.inbox[i]
				_line("%s · %s" % [m.name, m.time], 14, Color(1.0, 0.55, 0.85))
				_line(m.text, 16)
			if messages.inbox.is_empty():
				_line("Keine Nachrichten.", 15, Color(1, 1, 1, 0.6))
			_back()
		"contacts":
			_title("Kontakte")
			for n in messages.known_contacts():
				_line("👤  %s" % n, 18)
			_back()
		"jobs":
			_title("Jobs in der Nähe")
			for j in cfg.get("jobs", []):
				_line("%s" % j.get("title", ""), 17)
				_line("%s · %s · %s" % [j.get("where", ""), j.get("pay", ""), j.get("status", "")], 14, Color(1, 1, 1, 0.6))
			_back()
