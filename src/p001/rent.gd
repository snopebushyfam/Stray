## Rent rules for Prototype 001 (GDD: LIFE pillar "laufende Miete" + CONSEQUENCES).
##
## A standing order debits the rent from the account on the due day of each month. If the account
## cannot cover it the rent is overdue (the due day counts as overdue day 1); it is retried every
## following day; on overdue day `grace_days` + 1 the player is evicted (home door locked).
## With grace_days = 3: due Tue 01.12., evicted Fri 04.12. if still unpaid. Events are returned as trigger names for
## the messenger: rent_due_in_N, rent_paid, rent_failed, evicted. Config: home_config.json ["rent"].
class_name StrayRent
extends RefCounted

var cfg: Dictionary = {}
var overdue_days: int = 0
var evicted := false
var last_processed_day: int = 0
var payments: int = 0


func _init(rent_cfg: Dictionary = {}) -> void:
	cfg = rent_cfg


func amount() -> int:
	return int(cfg.get("cents", 45000))


## Days from `day` until the next due day (0 = today), using the clock's calendar.
func days_until_due(clock: StrayGameClock, day: int) -> int:
	var due := int(cfg.get("due_day_of_month", 1))
	for k in 40:
		if int(clock.date_of(day + k).day) == due:
			return k
	return -1


## Processes every calendar day from the last processed one up to `day` (sleeping can skip days).
## Returns the list of message triggers that happened.
func process_until(clock: StrayGameClock, day: int, life: StrayLifeState) -> Array[String]:
	var events: Array[String] = []
	while last_processed_day < day:
		last_processed_day += 1
		events.append_array(_process_day(clock, last_processed_day, life))
	return events


func _process_day(clock: StrayGameClock, day: int, life: StrayLifeState) -> Array[String]:
	var events: Array[String] = []
	if evicted:
		return events
	var due_today := days_until_due(clock, day) == 0
	if due_today or overdue_days > 0:
		if life.debit_account(amount(), "Miete (Dauerauftrag)"):
			overdue_days = 0
			payments += 1
			events.append("rent_paid")
		else:
			overdue_days += 1
			if overdue_days == 1:
				events.append("rent_failed")
			if overdue_days > int(cfg.get("grace_days", 3)):
				evicted = true
				events.append("evicted")
	else:
		var n := days_until_due(clock, day)
		if n == int(cfg.get("remind_days_before", 3)):
			events.append("rent_due_in_%d" % n)
	return events


func to_dict() -> Dictionary:
	return {"overdue_days": overdue_days, "evicted": evicted, "last_processed_day": last_processed_day, "payments": payments}


func from_dict(d: Dictionary) -> void:
	overdue_days = int(d.get("overdue_days", 0))
	evicted = bool(d.get("evicted", false))
	last_processed_day = int(d.get("last_processed_day", 0))
	payments = int(d.get("payments", 0))
