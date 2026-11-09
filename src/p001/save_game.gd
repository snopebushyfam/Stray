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
		"rent": main.rent.to_dict(),
		"job": main.job.to_dict(),
		"consequences": main.consequences.to_dict(),
		"transit": main.transit.to_dict() if main.transit else {},
		"prologue": main.prologue.to_dict() if main.prologue else {},
		"world": {
			"player_pos": [p.x, p.y, p.z],
			"player_yaw": main.player.get_yaw(),
			"inside_club": bool(main.interactions.life.flags.get("inside_club", false)),
			"inside_home": bool(main.interactions.life.flags.get("inside_home", false)),
			"inside_metro": bool(main.interactions.life.flags.get("inside_metro", false)),
			"region": main.region,
			"lea_talked": main.interactions.lea_talked,
			"battery": main.phone.battery,
			"character_variant": main.player.character_variant,
		},
	}


## Applies a save dictionary to the running game. Returns "" or an error message.
static func apply(main: Node, d: Dictionary) -> String:
	if int(d.get("version", -1)) < 1 or int(d.get("version", -1)) > VERSION:
		return "unsupported save version %s" % d.get("version", "?")
	# A menu open at save/load time must not survive into the loaded place (R9.2).
	main.interactions.close_all_panels()
	main.interactions.life.from_dict(d.get("life", {}))
	# Order matters: messages + rent first, so the day_changed fired by restoring the clock finds
	# the rent already processed up to the saved day (no double debit, no duplicate messages).
	main.messages.from_dict(d.get("messages", {}))
	main.job.from_dict(d.get("job", {}))
	main.consequences.from_dict(d.get("consequences", {}))
	var clock_min: float = float(d.get("clock", {}).get("minutes", main.clock.minutes))
	main.rent.from_dict(d.get("rent", {"last_processed_day": int(floor(clock_min / 1440.0))}))
	main.clock.from_dict(d.get("clock", {}))
	var w: Dictionary = d.get("world", {})
	main.interactions.lea_talked = bool(w.get("lea_talked", false))
	main.phone.battery = float(w.get("battery", main.phone.battery))
	main.player.set_character_variant(String(w.get("character_variant", "r10")))
	if main.menu:
		main.menu.character_label = main._character_label()
	var inside := bool(w.get("inside_club", false))
	var at_home := bool(w.get("inside_home", false))
	if inside:
		main.interactions.enter_club()
	elif main.interactions.life.flags.get("inside_club", false) or main.club.visible:
		main.interactions.leave_club()
	main.home.visible = at_home
	main.interactions.life.flags["inside_home"] = at_home
	main.player.set_indoor_camera(inside or at_home)
	var pp: Array = w.get("player_pos", [])
	if pp.size() == 3:
		main.player.global_position = Vector3(pp[0], pp[1], pp[2])
		main.player.velocity = Vector3.ZERO
	main.player.face_yaw(float(w.get("player_yaw", 0.0)))
	main.interactions.life.flags["inside_club"] = inside
	# R5: U-Bahn state and the visible region (older saves: Ringe, street level).
	if main.transit:
		main.transit.from_dict(d.get("transit", {}))
		var in_metro := bool(w.get("inside_metro", false))
		main.interactions.life.flags["inside_metro"] = in_metro
		if in_metro:
			main.metro.set_station(main.transit.station_name(main.transit.station))
		main.player.set_indoor_camera(inside or at_home or in_metro)
		main.set_region(String(w.get("region", "metro" if in_metro else "p001")))
	if main.prologue:
		main.prologue.from_dict(d.get("prologue", {}))
		main.ui.set_objective(main.prologue.objective())
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
