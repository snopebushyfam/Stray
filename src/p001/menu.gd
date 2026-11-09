## Start and pause menu for Prototype 001. Runs while the tree is paused (PROCESS_MODE_ALWAYS).
## Pure UI: emits signals; main.gd does the actual new game / load / save / quit.
## Texts: data/p001/game_config.json ["menu"].
class_name StrayMenu
extends CanvasLayer

signal new_game
signal continue_game
signal resume
signal save_requested
signal load_requested
signal main_menu
signal quit_requested

var txt: Dictionary = {}
var mode := ""  # "start" | "pause" | ""
var _panel: PanelContainer
var _box: VBoxContainer
var _note: Label


func setup(menu_txt: Dictionary) -> void:
	txt = menu_txt
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -220
	_panel.offset_right = 220
	_panel.offset_top = -230
	_panel.offset_bottom = 230
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.02, 0.04, 0.88)
	sb.border_color = Color(1.0, 0.3, 0.75, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(22)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	_panel.add_child(_box)
	_panel.visible = false


func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	_box.add_child(l)
	return l


func _button(text: String, sig: Signal) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 52)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(func(): sig.emit())
	_box.add_child(b)
	return b


func _clear() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()


## Start screen. `has_save` shows "Weiterspielen" first.
func show_start(has_save: bool, note: String = "") -> void:
	mode = "start"
	_clear()
	_label(String(txt.get("title", "STRAY")), 64, Color(1.0, 0.35, 0.8))
	_label(String(txt.get("subtitle", "")), 16, Color(1, 1, 1, 0.7))
	if has_save:
		_button(String(txt.get("continue", "Weiterspielen")), continue_game).grab_focus()
	_button(String(txt.get("new_game", "Neues Spiel")), new_game)
	if not OS.has_feature("web"):
		_button(String(txt.get("quit", "Beenden")), quit_requested)
	_note = _label(note, 14, Color(1, 1, 1, 0.6))
	_show()


## Pause screen while playing.
func show_pause(has_save: bool, note: String = "") -> void:
	mode = "pause"
	_clear()
	_label(String(txt.get("title", "STRAY")), 40, Color(1.0, 0.35, 0.8))
	_button(String(txt.get("resume", "Fortsetzen")), resume).grab_focus()
	_button(String(txt.get("save", "Speichern")), save_requested)
	var load_b := _button(String(txt.get("load", "Laden")), load_requested)
	load_b.disabled = not has_save
	_button(String(txt.get("main_menu", "Hauptmenü")), main_menu)
	_note = _label(note, 14, Color(1, 1, 1, 0.6))
	_show()


func set_note(text: String) -> void:
	if _note:
		_note.text = text


func _show() -> void:
	_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_fit.call_deferred()


## Shrinks the panel to its content (centred).
func _fit() -> void:
	var h := _box.get_combined_minimum_size().y + 48.0
	_panel.offset_top = -h * 0.5
	_panel.offset_bottom = h * 0.5


func hide_menu() -> void:
	mode = ""
	_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if mode == "pause" and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		resume.emit()
