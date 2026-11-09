## Prologue / tutorial (Roadmap R6): arrival at Köln Hbf -> U-Bahn -> Friesenplatz -> KIOSK.
## Pure logic (RefCounted): an ordered list of steps, each finished by one of its `done_on` game
## events. One event may finish several steps in a row (riding without a ticket skips the ticket
## step). Config: data/p002/prologue_config.json. GDD: STRAY_GDD.md (Spielbeginn, R6).
class_name StrayPrologue
extends RefCounted

## A new step became current (hint may be empty).
signal step_started(id: String, objective: String, hint: String)
## The last step was finished.
signal finished

var cfg: Dictionary = {}
var steps: Array = []
## Index of the current step; == steps.size() when done; -1 before start().
var index: int = -1


func _init(p_cfg: Dictionary = {}) -> void:
	cfg = p_cfg
	steps = cfg.get("steps", [])


func active() -> bool:
	return index >= 0 and index < steps.size()


func is_done() -> bool:
	return index >= steps.size()


func current_id() -> String:
	return String(steps[index].get("id", "")) if active() else ""


## Objective line for the HUD ("" when not running).
func objective() -> String:
	return String(cfg.get("objective_prefix", "")) + String(steps[index].get("objective", "")) if active() else ""


## Begins at the first step.
func start() -> void:
	index = 0
	_announce()


## Feeds a game event. Returns how many steps it finished.
func event(name: String) -> int:
	var n := 0
	while active() and name in steps[index].get("done_on", []):
		index += 1
		n += 1
	if n > 0:
		if is_done():
			finished.emit()
		else:
			_announce()
	return n


## Marks the prologue as finished without playing it (old saves, skip).
func skip() -> void:
	index = steps.size()


func _announce() -> void:
	var s: Dictionary = steps[index]
	step_started.emit(String(s.get("id", "")), objective(), String(s.get("hint", "")))


func to_dict() -> Dictionary:
	return {"index": index}


## Restores; a save without prologue state counts as finished (saves from before R6).
func from_dict(d: Dictionary) -> void:
	index = int(d.get("index", steps.size()))
