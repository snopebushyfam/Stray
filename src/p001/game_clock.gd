## In-game clock for Prototype 001: Saturday night, runs faster than real time.
## Pure logic; config data/p001/phone_config.json ["clock"]. Minutes since the start day's 00:00.
class_name StrayGameClock
extends RefCounted

signal hour_changed(hour: int)

var minutes: float = 0.0
var rate: float = 10.0  # game seconds per real second
var cfg: Dictionary = {}


func _init(clock_cfg: Dictionary = {}) -> void:
	cfg = clock_cfg
	minutes = parse_hhmm(String(cfg.get("start", "23:00")))
	rate = float(cfg.get("game_seconds_per_real_second", 10.0))


## "23:10" -> 1390.0 minutes.
static func parse_hhmm(t: String) -> float:
	var p := t.split(":")
	return float(int(p[0]) * 60 + int(p[1]))


## Advances by real seconds.
func advance(real_seconds: float) -> void:
	var before := hour()
	minutes += real_seconds * rate / 60.0
	if hour() != before:
		hour_changed.emit(hour())


## Hour of day 0..23 (wraps past midnight).
func hour() -> int:
	return int(fmod(minutes, 1440.0) / 60.0)


func hhmm() -> String:
	var m := int(fmod(minutes, 1440.0))
	return "%02d:%02d" % [m / 60, m % 60]


func is_daytime() -> bool:
	var h := hour()
	return h >= int(cfg.get("day_from_hour", 7)) and h < int(cfg.get("night_from_hour", 20))


## True inside [from, until) of a window that may wrap past midnight.
func in_window(from_hhmm: String, until_hhmm: String) -> bool:
	var m := fmod(minutes, 1440.0)
	var a := parse_hhmm(from_hhmm)
	var b := parse_hhmm(until_hhmm)
	return (m >= a and m < b) if a < b else (m >= a or m < b)


func club_open() -> bool:
	return in_window(String(cfg.get("club_open_from", "23:00")), String(cfg.get("club_open_until", "06:00")))


## Jumps to a time of day (today, or tomorrow if earlier than now). Used by the day/night toggle.
func set_time(hhmm_text: String) -> void:
	var target := parse_hhmm(hhmm_text)
	var day_start: float = floorf(minutes / 1440.0) * 1440.0
	var t: float = day_start + target
	if t < minutes:
		t += 1440.0
	var before := hour()
	minutes = t
	if hour() != before:
		hour_changed.emit(hour())
