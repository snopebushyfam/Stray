## NACHTFLUG door decision (Prototype 001, GDD pillars NIGHTLIFE + CONSEQUENCES).
##
## Order of checks (first match decides): closed by day -> recently refused (pestering) ->
## nightlife reputation too low -> did not queue -> too drunk -> cannot pay -> admitted.
## Reputation consequences come from config: refusal, pestering and admission change the
## "nightlife" axis. Config: data/p001/economy_config.json ["club"].
class_name StrayBouncerRules
extends RefCounted

var cfg: Dictionary = {}
## Seconds of game time since the last refusal (INF = never refused).
var since_refusal: float = INF


func _init(club_cfg: Dictionary = {}) -> void:
	cfg = club_cfg


func _line(key: String) -> String:
	return String(cfg.get("lines", {}).get(key, key))


## Advances the refusal timer.
func tick(delta: float) -> void:
	since_refusal += delta


## Decides at the door. `queued_seconds` = time the player waited at the queue end.
## Returns {admitted: bool, reason: String, text: String}. Applies money and reputation.
func decide(state: StrayLifeState, is_night: bool, queued_seconds: float) -> Dictionary:
	var rep: Dictionary = cfg.get("reputation", {})
	if not is_night:
		return {"admitted": false, "reason": "closed", "text": _line("closed")}
	if since_refusal < float(cfg.get("annoyed_cooldown_seconds", 30.0)):
		state.change_reputation("nightlife", int(rep.get("pestered", -2)))
		since_refusal = 0.0
		return {"admitted": false, "reason": "annoyed", "text": _line("annoyed")}
	var result := {}
	if int(state.reputation.get("nightlife", 0)) <= int(rep.get("min_nightlife", -3)):
		result = {"admitted": false, "reason": "rep_low", "text": _line("rep_low")}
	elif queued_seconds < float(cfg.get("queue_wait_seconds", 15.0)):
		result = {"admitted": false, "reason": "queue", "text": _line("queue")}
	elif state.drinks_alcohol >= int(cfg.get("drunk_limit", 3)):
		result = {"admitted": false, "reason": "drunk", "text": _line("drunk")}
	else:
		var fee: int = int(cfg.get("entry_fee", 1500))
		if not state.pay(fee, "Eintritt %s" % String(cfg.get("name", "Club"))):
			result = {"admitted": false, "reason": "broke", "text": _line("broke") % StrayLifeState.euro(fee)}
		else:
			state.change_reputation("nightlife", int(rep.get("admitted", 1)))
			state.flags["inside_club"] = true
			return {"admitted": true, "reason": "welcome", "text": _line("welcome") % StrayLifeState.euro(fee)}
	# Being sent to the back of the queue is a normal instruction: no reputation loss, and it does
	# not start the "pestering" cooldown (the player is expected to come back after queueing).
	if result.reason != "queue":
		state.change_reputation("nightlife", int(rep.get("rejected", -1)))
		since_refusal = 0.0
	return result
