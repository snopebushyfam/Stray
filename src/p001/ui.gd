## Prototype 001 HUD for life systems: cash/reputation, interaction prompt, speech messages,
## kiosk menu. Touch-friendly (large buttons). Driven by StrayInteractions via signals/calls.
class_name StrayUi
extends CanvasLayer

## Emitted when the player picks a kiosk item (item id) or closes the menu ("").
signal shop_choice(item_id: String)
## Emitted when the player picks a dialogue option (index into the shown options).
signal option_chosen(index: int)
## Emitted by the on-screen "Interagieren" button (touch devices).
signal interact_pressed

var status_label: Label
var prompt_label: Label
## Current goal (prologue / tutorial), top left under the controls line.
var objective_label: Label
var message_panel: PanelContainer
var message_label: Label
var shop_panel: PanelContainer
var shop_box: VBoxContainer
var interact_button: Button
var _message_left: float = 0.0
var touch := false


func _ready() -> void:
	touch = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	status_label = Label.new()
	status_label.anchor_left = 1.0
	status_label.anchor_right = 1.0
	status_label.offset_left = -340
	status_label.offset_right = -14
	status_label.offset_top = 10
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.add_theme_font_size_override("font_size", 18)
	add_child(status_label)

	objective_label = Label.new()
	objective_label.offset_left = 12
	# Touch devices have the Tag/Nacht, Menü and Handy buttons there: goal goes below them.
	objective_label.offset_top = 150 if touch else 52
	objective_label.offset_right = 760
	objective_label.add_theme_font_size_override("font_size", 20)
	objective_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	objective_label.add_theme_color_override("font_outline_color", Color.BLACK)
	objective_label.add_theme_constant_override("outline_size", 6)
	add_child(objective_label)

	prompt_label = Label.new()
	prompt_label.anchor_left = 0.5
	prompt_label.anchor_right = 0.5
	prompt_label.anchor_top = 1.0
	prompt_label.anchor_bottom = 1.0
	prompt_label.offset_left = -300
	prompt_label.offset_right = 300
	prompt_label.offset_top = -150
	prompt_label.offset_bottom = -115
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", 20)
	prompt_label.add_theme_color_override("font_outline_color", Color.BLACK)
	prompt_label.add_theme_constant_override("outline_size", 6)
	add_child(prompt_label)

	message_panel = _panel(Vector2(-330, -105), Vector2(330, -20))
	message_label = Label.new()
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.add_theme_font_size_override("font_size", 18)
	message_panel.add_child(message_label)
	message_panel.visible = false

	shop_panel = _panel(Vector2(-200, -330), Vector2(200, -120))
	shop_box = VBoxContainer.new()
	shop_box.add_theme_constant_override("separation", 6)
	shop_panel.add_child(shop_box)
	shop_panel.visible = false

	interact_button = Button.new()
	interact_button.text = "Interagieren"
	interact_button.anchor_left = 1.0
	interact_button.anchor_right = 1.0
	interact_button.anchor_top = 1.0
	interact_button.anchor_bottom = 1.0
	interact_button.offset_left = -170
	interact_button.offset_right = -20
	interact_button.offset_top = -190
	interact_button.offset_bottom = -110
	interact_button.add_theme_font_size_override("font_size", 20)
	interact_button.visible = false
	interact_button.pressed.connect(func(): interact_pressed.emit())
	add_child(interact_button)


func _panel(top_left: Vector2, bottom_right: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 1.0
	p.anchor_bottom = 1.0
	p.offset_left = top_left.x
	p.offset_top = top_left.y
	p.offset_right = bottom_right.x
	p.offset_bottom = bottom_right.y
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.05, 0.86)
	sb.border_color = Color(1.0, 0.3, 0.75, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	add_child(p)
	return p


var clock_text: String = ""
## Police attention 0..100 (shown as 5 dots when > 0).
var police_heat: float = 0.0


func set_status(state: StrayLifeState) -> void:
	var dots := ""
	if police_heat > 0.5:
		var n := clampi(int(ceil(police_heat / 20.0)), 1, 5)
		dots = "\nPolizei " + "●".repeat(n) + "○".repeat(5 - n)
	status_label.text = "%sBargeld %s\nRuf Nachtleben %+d%s" % [("%s\n" % clock_text) if not clock_text.is_empty() else "",
		StrayLifeState.euro(state.cash_cents), int(state.reputation.get("nightlife", 0)), dots]


## Shows the current goal ("" hides it).
func set_objective(text: String) -> void:
	objective_label.text = text


func show_prompt(text: String) -> void:
	prompt_label.text = text
	interact_button.visible = touch and not text.is_empty()


## Speech line from an NPC, hidden after `seconds`.
func show_message(speaker: String, text: String, seconds: float = 5.0) -> void:
	message_label.text = "%s: %s" % [speaker, text] if not speaker.is_empty() else text
	message_panel.visible = true
	_message_left = seconds


func open_shop(title: String, greeting: String, items: Array, extra_label: String = "") -> void:
	for c in shop_box.get_children():
		c.queue_free()
	var head := Label.new()
	head.text = "%s – %s" % [title, greeting]
	head.add_theme_font_size_override("font_size", 18)
	shop_box.add_child(head)
	for it in items:
		var b := Button.new()
		b.text = "%s  ·  %s" % [it.get("name", "?"), StrayLifeState.euro(int(it.get("price", 0)))]
		b.custom_minimum_size = Vector2(0, 40)
		var id: String = it.get("id", "")
		b.pressed.connect(func(): shop_choice.emit(id))
		shop_box.add_child(b)
	if not extra_label.is_empty():
		var ex := Button.new()
		ex.text = extra_label
		ex.custom_minimum_size = Vector2(0, 40)
		ex.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
		ex.pressed.connect(func(): shop_choice.emit("__extra"))
		shop_box.add_child(ex)
	var bye := Button.new()
	bye.text = "Tschüss"
	bye.custom_minimum_size = Vector2(0, 40)
	bye.pressed.connect(func(): shop_choice.emit(""))
	shop_box.add_child(bye)
	_show_panel()


## Opens the menu/options panel and hides an older speech message (both sit at the bottom).
func _show_panel() -> void:
	shop_panel.visible = true
	message_panel.visible = false
	_message_left = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Dialogue choices: a line from the NPC, then one button per answer.
## Question text of the last options panel (tests, accessibility).
var options_text: String = ""


func open_options(speaker: String, text: String, labels: Array) -> void:
	options_text = text
	for c in shop_box.get_children():
		c.queue_free()
	var head := Label.new()
	head.text = "%s: %s" % [speaker, text]
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.custom_minimum_size = Vector2(360, 0)
	head.add_theme_font_size_override("font_size", 18)
	shop_box.add_child(head)
	for i in labels.size():
		var b := Button.new()
		b.text = String(labels[i])
		b.custom_minimum_size = Vector2(0, 42)
		var idx := i
		b.pressed.connect(func(): option_chosen.emit(idx))
		shop_box.add_child(b)
	_show_panel()


func close_shop() -> void:
	shop_panel.visible = false


func _process(delta: float) -> void:
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			message_panel.visible = false
