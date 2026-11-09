## Consequences framework (R4, GDD pillar CONSEQUENCES): police attention ("heat"), incident
## record, police check outcomes, shoplifting, kiosk ban, platzverweis. Pure rules (no nodes).
##
## Heat rises from events (each with a cooldown), decays per game hour and is clamped 0..heat_max.
## A police check resolves by heat and drinks: warning < warning_below <= fine < fine_below <=
## platzverweis; running away adds heat, and heat >= arrest_from_heat means arrest (night in a
## cell, fine). Config: data/p001/consequences_config.json.
class_name StrayConsequences
extends RefCounted

signal heat_changed(value: float)

var cfg: Dictionary = {}
var heat: float = 0.0
var incidents: Array[Dictionary] = []   # {type, label, day, time}
var police_record: int = 0              # checks that ended in fine / platzverweis / arrest
var kiosk_banned := false
var platzverweis_until_minutes: float = -1.0   # absolute clock minutes; -1 = none
var last_check_minutes: float = -1e9
var thefts_ok: int = 0
var _last_event_minutes: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _init(p_cfg: Dictionary = {}) -> void:
	cfg = p_cfg
	_rng.seed = int(cfg.get("shoplifting", {}).get("seed", 1))


func _set_heat(v: float) -> void:
	heat = clampf(v, 0.0, float(cfg.get("heat_max", 100)))
	heat_changed.emit(heat)


## Records an event from config "sources". Respects the per-source cooldown. Returns heat added.
func report(event: String, clock: StrayGameClock) -> float:
	var src: Dictionary = cfg.get("sources", {}).get(event, {})
	if src.is_empty():
		return 0.0
	var cd := float(src.get("cooldown_minutes", 0))
	if cd > 0.0 and clock.minutes - float(_last_event_minutes.get(event, -1e9)) < cd:
		return 0.0
	_last_event_minutes[event] = clock.minutes
	var add := float(src.get("heat", 0))
	_set_heat(heat + add)
	incidents.append({"type": event, "label": String(src.get("label", event)), "day": clock.day_index(), "time": clock.hhmm()})
	return add


## Heat decays with game time (call with elapsed game minutes).
func decay(game_minutes: float) -> void:
	if heat > 0.0 and game_minutes > 0.0:
		_set_heat(heat - float(cfg.get("decay_per_game_hour", 6.0)) * game_minutes / 60.0)


## True when a passing police car should stop the player.
func police_wants_check(clock: StrayGameClock, distance_m: float) -> bool:
	var p: Dictionary = cfg.get("police", {})
	return heat >= float(p.get("check_from_heat", 30)) and distance_m <= float(p.get("check_radius_m", 22.0)) \
		and clock.minutes - last_check_minutes >= float(p.get("check_cooldown_minutes", 45))


## Resolves a police check. `cooperate` = showed ID, else ran away.
## Returns {outcome: "warning"|"fine"|"platzverweis"|"arrest"|"ran", fine_cents, text}.
## Applies money (cash first, then account), heat, record, platzverweis and arrest time skip.
func resolve_check(cooperate: bool, life: StrayLifeState, clock: StrayGameClock) -> Dictionary:
	var p: Dictionary = cfg.get("police", {})
	var t: Dictionary = cfg.get("texts", {})
	last_check_minutes = clock.minutes
	if not cooperate:
		report("ran_from_police", clock)
		if heat < float(p.get("arrest_from_heat", 100)):
			return {"outcome": "ran", "fine_cents": 0, "text": String(t.get("ran_away", ""))}
	if heat >= float(p.get("arrest_from_heat", 100)):
		var fine := int(p.get("arrest_fine_cents", 20000))
		_take_fine(fine, life, "Bußgeld + Gewahrsam")
		police_record += 1
		_set_heat(0.0)
		clock.set_time(String(p.get("arrest_release", "08:00")))
		return {"outcome": "arrest", "fine_cents": fine, "text": String(t.get("arrest", ""))}
	if life.drinks_alcohol >= int(p.get("drunk_platzverweis_from_drinks", 5)) or heat >= float(p.get("fine_below", 80)):
		var until := String(p.get("platzverweis_until", "06:00"))
		var day_start: float = floorf(clock.minutes / 1440.0) * 1440.0
		var u: float = day_start + StrayGameClock.parse_hhmm(until)
		if u <= clock.minutes:
			u += 1440.0
		platzverweis_until_minutes = u
		police_record += 1
		_set_heat(heat + float(p.get("heat_after_platzverweis", -25)))
		return {"outcome": "platzverweis", "fine_cents": 0, "text": String(t.get("platzverweis", "")) % until}
	if heat >= float(p.get("warning_below", 50)):
		var f := int(p.get("fine_cents", 6000))
		_take_fine(f, life, "Bußgeld Polizei")
		police_record += 1
		_set_heat(heat + float(p.get("heat_after_fine", -35)))
		return {"outcome": "fine", "fine_cents": f, "text": String(t.get("fine", "")) % StrayLifeState.euro(f)}
	_set_heat(heat + float(p.get("heat_after_warning", -20)))
	return {"outcome": "warning", "fine_cents": 0, "text": String(t.get("warning", ""))}


## Fines are paid from cash first, the rest from the account (may go negative = debt).
func _take_fine(cents: int, life: StrayLifeState, label: String) -> void:
	var from_cash := mini(cents, life.cash_cents)
	if from_cash > 0:
		life.pay(from_cash, label)
	var rest := cents - from_cash
	if rest > 0:
		life.account_cents -= rest
		life.account_changed.emit(life.account_cents)
		life._book(label, -rest, "account")


func has_platzverweis(clock: StrayGameClock) -> bool:
	return platzverweis_until_minutes >= 0.0 and clock.minutes < platzverweis_until_minutes


## Shoplifting attempt at the kiosk. Returns {caught: bool}. Caught = kiosk ban + heat.
func try_shoplift(clock: StrayGameClock) -> Dictionary:
	var s: Dictionary = cfg.get("shoplifting", {})
	var chance := float(s.get("catch_chance_after_success", 0.8)) if thefts_ok > 0 else float(s.get("catch_chance", 0.55))
	var caught := _rng.randf() < chance
	if caught:
		kiosk_banned = true
		report("theft_caught", clock)
	else:
		thefts_ok += 1
	return {"caught": caught}


func to_dict() -> Dictionary:
	return {"heat": heat, "incidents": incidents.duplicate(true), "police_record": police_record, "kiosk_banned": kiosk_banned,
		"platzverweis_until": platzverweis_until_minutes, "last_check": last_check_minutes, "thefts_ok": thefts_ok,
		"last_events": _last_event_minutes.duplicate()}


func from_dict(d: Dictionary) -> void:
	heat = float(d.get("heat", 0.0))
	incidents.clear()
	for i in d.get("incidents", []):
		incidents.append((i as Dictionary).duplicate())
	police_record = int(d.get("police_record", 0))
	kiosk_banned = bool(d.get("kiosk_banned", false))
	platzverweis_until_minutes = float(d.get("platzverweis_until", -1.0))
	last_check_minutes = float(d.get("last_check", -1e9))
	thefts_ok = int(d.get("thefts_ok", 0))
	_last_event_minutes = (d.get("last_events", {}) as Dictionary).duplicate()
	heat_changed.emit(heat)
