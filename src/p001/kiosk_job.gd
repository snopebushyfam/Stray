## Kiosk night-help job (R3, GDD LIFE: Arbeit). Pure rules; the scene side lives in interactions.gd.
##
## Flow: apply -> employed. Every day a shift runs shift_start..shift_end. Starting within
## on_time_minutes is on time; later (up to latest_start_minutes) cuts the wage; later still or not
## showing up = missed shift. A shift serves `customers_per_shift` orders; each correct order earns a
## cash tip. Ending the shift pays hours * hourly to the account (minus a late cut). Too many
## mistakes or a missed shift = warning; `warnings_to_fire` warnings = fired.
## Config: data/p001/jobs_config.json ["kiosk_job"].
class_name StrayKioskJob
extends RefCounted

var cfg: Dictionary = {}
var employed := false
var fired := false
var warnings: int = 0
var shifts_done: int = 0
var last_shift_day: int = -1     # day index of the last worked (or missed) shift
var in_shift := false
var shift_late_minutes: int = 0
var orders: Array = []           # this shift's orders (dicts from config)
var served: int = 0
var correct: int = 0


func _init(job_cfg: Dictionary = {}) -> void:
	cfg = job_cfg


func apply() -> bool:
	if employed or fired:
		return false
	employed = true
	return true


## "too_early" | "on_time" | "late" | "too_late" | "done_today" | "not_employed"
func start_status(clock: StrayGameClock) -> String:
	if not employed or fired:
		return "not_employed"
	if last_shift_day == clock.day_index():
		return "done_today"
	var now := fmod(clock.minutes, 1440.0)
	var start := StrayGameClock.parse_hhmm(String(cfg.get("shift_start", "18:00")))
	var end := StrayGameClock.parse_hhmm(String(cfg.get("shift_end", "22:00")))
	if now < start:
		return "too_early"
	if now > end or now - start > float(cfg.get("latest_start_minutes", 60)):
		return "too_late"
	return "on_time" if now - start <= float(cfg.get("on_time_minutes", 15)) else "late"


## Starts today's shift; returns start_status. Orders are deterministic per day.
func start_shift(clock: StrayGameClock) -> String:
	var st := start_status(clock)
	if st != "on_time" and st != "late":
		return st
	in_shift = true
	served = 0
	correct = 0
	shift_late_minutes = 0
	if st == "late":
		shift_late_minutes = int(fmod(clock.minutes, 1440.0) - StrayGameClock.parse_hhmm(String(cfg.get("shift_start", "18:00"))))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cfg.get("seed", 1)) + clock.day_index() * 7919
	var pool: Array = cfg.get("orders", [])
	orders = []
	for i in int(cfg.get("customers_per_shift", 8)):
		orders.append(pool[rng.randi() % pool.size()])
	return st


func current_order() -> Dictionary:
	return orders[served] if in_shift and served < orders.size() else {}


## Serves the current customer with `item_id`. Returns true when it was what they asked for.
func serve(item_id: String, life: StrayLifeState) -> bool:
	var o := current_order()
	if o.is_empty():
		return false
	var ok: bool = String(o.get("item", "")) == item_id
	served += 1
	if ok:
		correct += 1
		life.cash_cents += int(cfg.get("tip_cents", 50))
		life.cash_changed.emit(life.cash_cents)
	return ok


func shift_complete() -> bool:
	return in_shift and served >= orders.size()


## Ends the shift: wage to the account, warning if too many mistakes. Returns
## {wage, tips, warning: bool, fired: bool}.
func finish_shift(clock: StrayGameClock, life: StrayLifeState) -> Dictionary:
	var hours := (StrayGameClock.parse_hhmm(String(cfg.get("shift_end", "22:00"))) - StrayGameClock.parse_hhmm(String(cfg.get("shift_start", "18:00")))) / 60.0
	var wage := int(round(hours * float(cfg.get("hourly_cents", 1350))))
	if shift_late_minutes > 0:
		wage = int(round(wage * (1.0 - float(cfg.get("late_cut_percent", 25)) / 100.0)))
	life.credit_account(wage, "Lohn Kiosk")
	var mistakes := served - correct
	var warn := mistakes > int(cfg.get("max_mistakes_ok", 2))
	if warn:
		_warn()
	in_shift = false
	shifts_done += 1
	last_shift_day = clock.day_index()
	return {"wage": wage, "tips": correct * int(cfg.get("tip_cents", 50)), "warning": warn, "fired": fired}


## Call when the shift window has passed: a day without a shift while employed = missed.
## Returns "missed" (warning), "fired" or "".
func check_missed(clock: StrayGameClock) -> String:
	if not employed or fired or in_shift or last_shift_day == clock.day_index():
		return ""
	var now := fmod(clock.minutes, 1440.0)
	if now <= StrayGameClock.parse_hhmm(String(cfg.get("shift_start", "18:00"))) + float(cfg.get("latest_start_minutes", 60)):
		return ""
	last_shift_day = clock.day_index()
	_warn()
	return "fired" if fired else "missed"


func _warn() -> void:
	warnings += 1
	if warnings >= int(cfg.get("warnings_to_fire", 2)):
		fired = true
		employed = false


func to_dict() -> Dictionary:
	return {"employed": employed, "fired": fired, "warnings": warnings, "shifts_done": shifts_done,
		"last_shift_day": last_shift_day}


func from_dict(d: Dictionary) -> void:
	employed = bool(d.get("employed", false))
	fired = bool(d.get("fired", false))
	warnings = int(d.get("warnings", 0))
	shifts_done = int(d.get("shifts_done", 0))
	last_shift_day = int(d.get("last_shift_day", -1))
	in_shift = false
