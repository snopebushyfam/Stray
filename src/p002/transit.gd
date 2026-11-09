## U-Bahn rules (Roadmap R5): tickets, rides between two stations, fare checks and fines.
## Pure logic (RefCounted, no nodes). Config: data/p002/transit_config.json. GDD: STRAY_GDD.md
## (Mobilität / U-Bahn). Deterministic: fare checks come from a seeded RNG whose state is saved.
class_name StrayTransit
extends RefCounted

var cfg: Dictionary = {}
## Station id the player is at (or last left from the surface).
var station: String = ""
var has_ticket := false
var rides := 0
var checks := 0
## Fines that could not be paid on the spot (no cash, account too low).
var unpaid_fines_cents := 0
var _rng := RandomNumberGenerator.new()


func _init(p_cfg: Dictionary = {}) -> void:
	cfg = p_cfg
	station = String(cfg.get("start_station", "friesenplatz"))
	_rng.seed = int(cfg.get("fare_dodging", {}).get("seed", 77))


## Display name of a station id.
func station_name(id: String) -> String:
	return String(cfg.get("stations", {}).get(id, {}).get("name", id))


## The other end of the line (two stations in the rough build).
func other_station(id: String = station) -> String:
	for k in cfg.get("stations", {}):
		if k != id:
			return k
	return id


## Total game minutes of one ride (waiting on the platform + travel).
func ride_minutes() -> int:
	return int(cfg.get("wait_minutes", 0)) + int(cfg.get("ride_minutes", 0))


func ticket_price() -> int:
	return int(cfg.get("ticket", {}).get("price_cents", 0))


## Buys a single ticket with cash. Returns {ok, reason: "bought"|"already"|"no_money"}.
func buy_ticket(life: StrayLifeState) -> Dictionary:
	if has_ticket:
		return {"ok": false, "reason": "already"}
	if not life.pay(ticket_price(), String(cfg.get("ticket", {}).get("label", "Fahrkarte"))):
		return {"ok": false, "reason": "no_money"}
	has_ticket = true
	return {"ok": true, "reason": "bought"}


## Rides to the other station: advances the clock, may run a fare check, consumes the ticket.
## Returns {from, to, minutes, checked, had_ticket, fined_cents, paid: "cash"|"account"|"unpaid"|""}.
func ride(life: StrayLifeState, clock: StrayGameClock) -> Dictionary:
	var fd: Dictionary = cfg.get("fare_dodging", {})
	var r := {"from": station, "to": other_station(), "minutes": ride_minutes(), "checked": false,
		"had_ticket": has_ticket, "fined_cents": 0, "paid": ""}
	# Always roll, so the sequence of checks does not depend on whether a ticket was bought.
	r.checked = _rng.randf() < float(fd.get("check_chance", 0.0))
	if r.checked:
		checks += 1
		if not has_ticket:
			var fine := int(fd.get("fine_cents", 6000))
			r.fined_cents = fine
			if life.pay(fine, "Erhöhtes Beförderungsentgelt"):
				r.paid = "cash"
			elif life.debit_account(fine, "Erhöhtes Beförderungsentgelt"):
				r.paid = "account"
			else:
				unpaid_fines_cents += fine
				r.paid = "unpaid"
	has_ticket = false
	station = r.to
	rides += 1
	if clock:
		clock.advance_minutes(float(r.minutes))
	return r


func to_dict() -> Dictionary:
	return {"station": station, "has_ticket": has_ticket, "rides": rides, "checks": checks,
		"unpaid_fines_cents": unpaid_fines_cents, "rng_state": str(_rng.state)}


## Restores from to_dict(); missing keys keep the current values.
func from_dict(d: Dictionary) -> void:
	station = String(d.get("station", station))
	has_ticket = bool(d.get("has_ticket", has_ticket))
	rides = int(d.get("rides", rides))
	checks = int(d.get("checks", checks))
	unpaid_fines_cents = int(d.get("unpaid_fines_cents", unpaid_fines_cents))
	if d.has("rng_state"):
		_rng.state = int(String(d["rng_state"]))
