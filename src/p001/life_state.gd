## The player's life state for Prototype 001: cash, inventory, reputation, flags.
## Pure data + rules (no nodes) so every rule is unit-testable. GDD pillars: LIFE (money),
## CONSEQUENCES (reputation). Reputation axes per GDD: social, nightlife, police.
class_name StrayLifeState
extends RefCounted

signal cash_changed(cents: int)
signal reputation_changed(axis: String, value: int)
signal inventory_changed(item_id: String, count: int)

var cash_cents: int = 0
var inventory: Dictionary = {}  # item_id -> count
var reputation: Dictionary = {"social": 0, "nightlife": 0, "police": 0}
var drinks_alcohol: int = 0
var flags: Dictionary = {}


func _init(start_cash_cents: int = 0) -> void:
	cash_cents = start_cash_cents


## Formats cents as German euro text, e.g. 1550 -> "15,50 €".
static func euro(cents: int) -> String:
	var sign := "-" if cents < 0 else ""
	var c := absi(cents)
	return "%s%d,%02d €" % [sign, c / 100, c % 100]


## Takes money if there is enough. Returns false (and changes nothing) otherwise.
func pay(cents: int) -> bool:
	if cents < 0 or cents > cash_cents:
		return false
	cash_cents -= cents
	cash_changed.emit(cash_cents)
	return true


func add_item(item_id: String, tags: Array = []) -> void:
	inventory[item_id] = int(inventory.get(item_id, 0)) + 1
	if "alcohol" in tags:
		drinks_alcohol += 1
	inventory_changed.emit(item_id, inventory[item_id])


func change_reputation(axis: String, delta: int) -> void:
	reputation[axis] = int(reputation.get(axis, 0)) + delta
	reputation_changed.emit(axis, reputation[axis])
