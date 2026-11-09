## Phone messenger for Prototype 001: event-triggered messages + contacts.
## Triggers: "start", "club_admitted", "cash_below_<cents>". Each message is delivered once.
## Config: data/p001/phone_config.json ["messages"], ["contacts"].
class_name StrayMessages
extends RefCounted

signal received(message: Dictionary)

var defs: Array = []
var contacts: Dictionary = {}  # id -> {name, known}
var inbox: Array[Dictionary] = []
var unread: int = 0
var _delivered: Dictionary = {}


func _init(phone_cfg: Dictionary = {}) -> void:
	defs = phone_cfg.get("messages", [])
	for c in phone_cfg.get("contacts", []):
		contacts[c["id"]] = {"name": c.get("name", c["id"]), "known": bool(c.get("known_at_start", false))}


## Fires an event; delivers every not-yet-delivered message with that trigger.
func trigger(event: String, time_text: String = "") -> int:
	var n := 0
	for d in defs:
		if d.get("trigger", "") == event and not _delivered.has(d["id"]):
			_deliver(d, time_text)
			n += 1
	return n


## Checks "cash_below_<cents>" triggers against the current cash.
func check_cash(cash_cents: int, time_text: String = "") -> void:
	for d in defs:
		var t: String = d.get("trigger", "")
		if t.begins_with("cash_below_") and cash_cents < int(t.trim_prefix("cash_below_")) and not _delivered.has(d["id"]):
			_deliver(d, time_text)


func _deliver(d: Dictionary, time_text: String) -> void:
	_delivered[d["id"]] = true
	var from: String = d.get("from", "")
	if contacts.has(from):
		contacts[from]["known"] = true
	var m := {"id": d["id"], "from": from, "name": contacts.get(from, {}).get("name", from),
		"text": d.get("text", ""), "time": time_text}
	inbox.append(m)
	unread += 1
	received.emit(m)


func to_dict() -> Dictionary:
	return {"inbox": inbox.duplicate(true), "unread": unread, "delivered": _delivered.keys(), "contacts": contacts.duplicate(true)}


## Restores state. Contacts keep config entries; saved names/known flags override them.
func from_dict(d: Dictionary) -> void:
	inbox.clear()
	for m in d.get("inbox", []):
		inbox.append((m as Dictionary).duplicate())
	unread = int(d.get("unread", 0))
	_delivered = {}
	for id in d.get("delivered", []):
		_delivered[String(id)] = true
	var sc: Dictionary = d.get("contacts", {})
	for id in sc:
		contacts[id] = {"name": String(sc[id].get("name", id)), "known": bool(sc[id].get("known", false))}


func mark_all_read() -> void:
	unread = 0


func known_contacts() -> Array:
	var out := []
	for id in contacts:
		if contacts[id]["known"]:
			out.append(contacts[id]["name"])
	return out
