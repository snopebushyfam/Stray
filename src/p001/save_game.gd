## Save game for Prototype 001: one JSON file (user://, persists in the browser too).
##
## Composes the to_dict() of each system (life, clock, messages) plus world state (player
## position/yaw, inside club, Lea talked, phone battery). Versioned; unknown keys are ignored and
## missing keys fall back to defaults, so older saves stay loadable. Config: game_config.json.
class_name StraySaveGame
extends RefCounted

const VERSION := 1


## Builds the save dictionary from the running game (`main` = main.gd node).
static func capture(main: Node) -> Dictionary:
	var p: Vector3 = main.player.global_position
	return {
		"version": VERSION,
		"saved_at_game_time": main.clock.hhmm(),
		"life": main.interactions.life.to_dict(),
		"clock": main.clock.to_dict(),
		"messages": main.messages.to_dict(),
		"world": {
			"player_pos": [p.x, p.y, p.z],
			"player_yaw": main.player.get_yaw(),
			"inside_club": bool(main.interactions.life.flags.get("inside_club", false)),
			"lea_talked": main.interactions.lea_talked,
			"battery": main.phone.battery,
		},
	}


## Applies a save dictionary to the running game. Returns "" or an error message.
static func apply(main: Node, d: Dictionary) -> String:
	if int(d.get("version", -1)) < 1 or int(d.get("version", -1)) > VERSION:
		return "unsupported save version %s" % d.get("version", "?")
	main.interactions.life.from_dict(d.get("life", {}))
	main.clock.from_dict(d.get("clock", {}))
	main.messages.from_dict(d.get("messages", {}))
	var w: Dictionary = d.get("world", {})
	main.interactions.lea_talked = bool(w.get("lea_talked", false))
	main.phone.battery = float(w.get("battery", main.phone.battery))
	var inside := bool(w.get("inside_club", false))
	if inside:
		main.interactions.enter_club()
	elif main.interactions.life.flags.get("inside_club", false) or main.club.visible:
		main.interactions.leave_club()
	var pp: Array = w.get("player_pos", [])
	if pp.size() == 3:
		main.player.global_position = Vector3(pp[0], pp[1], pp[2])
		main.player.velocity = Vector3.ZERO
	main.player.face_yaw(float(w.get("player_yaw", 0.0)))
	main.interactions.life.flags["inside_club"] = inside
	return ""


static func write(path: String, d: Dictionary) -> String:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "cannot write %s (err %d)" % [path, FileAccess.get_open_error()]
	f.store_string(JSON.stringify(d, "  "))
	f.close()
	return ""


## Reads a save file. Returns {} when missing or corrupt.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v if typeof(v) == TYPE_DICTIONARY else {}


static func exists(path: String) -> bool:
	return FileAccess.file_exists(path) and not read(path).is_empty()
