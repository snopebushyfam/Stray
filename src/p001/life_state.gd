## The player's life state for Prototype 001: cash, inventory, reputation, flags.
## Pure data + rules (no nodes) so every rule is unit-testable. GDD pillars: LIFE (money),
## CONSEQUENCES (reputation). Reputation axes per GDD: social, nightlife, police.
class_name StrayLifeState
extends RefCounted

signal cash_changed(cents: int)
signal reputation_changed(axis: String, value: int)
signal inventory_changed(item_id: String, count: int)
signal account_changed(cents: int)
## Fired for every booking: {label, cents (negative = spent), kind: "cash" | "account" | "atm"}.
signal transaction(entry: Dictionary)

var cash_cents: int = 0
var account_cents: int = 0
## Booking history (newest last), shown in the phone's bank app.
var transactions: Array[Dictionary] = []
var inventory: Dictionary = {}  # item_id -> count
var reputation: Dictionary = {"social": 0, "nightlife": 0, "police": 0}
var drinks_alcohol: int = 0
var flags: Dictionary = {}


func _init(start_cash_cents: int = 0, start_account_cents: int = 0) -> void:
	cash_cents = start_cash_cents
	account_cents = start_account_cents


## Formats cents as German euro text, e.g. 1550 -> "15,50 €".
static func euro(cents: int) -> String:
	var sign := "-" if cents < 0 else ""
	var c := absi(cents)
	return "%s%d,%02d €" % [sign, c / 100, c % 100]


## Takes cash if there is enough. Returns false (and changes nothing) otherwise.
func pay(cents: int, label: String = "") -> bool:
	if cents < 0 or cents > cash_cents:
		return false
	cash_cents -= cents
	cash_changed.emit(cash_cents)
	_book(label if not label.is_empty() else "Barzahlung", -cents, "cash")
	return true


## ATM: moves money from the account to cash. False when the account cannot cover it.
func withdraw(cents: int) -> bool:
	if cents <= 0 or cents > account_cents:
		return false
	account_cents -= cents
	cash_cents += cents
	account_changed.emit(account_cents)
	cash_changed.emit(cash_cents)
	_book("Geldautomat", -cents, "atm")
	return true


func _book(label: String, cents: int, kind: String) -> void:
	var e := {"label": label, "cents": cents, "kind": kind}
	transactions.append(e)
	transaction.emit(e)


func add_item(item_id: String, tags: Array = []) -> void:
	inventory[item_id] = int(inventory.get(item_id, 0)) + 1
	if "alcohol" in tags:
		drinks_alcohol += 1
	inventory_changed.emit(item_id, inventory[item_id])


## Serialises everything the save game needs.
func to_dict() -> Dictionary:
	return {"cash_cents": cash_cents, "account_cents": account_cents, "inventory": inventory.duplicate(),
		"reputation": reputation.duplicate(), "drinks_alcohol": drinks_alcohol, "flags": flags.duplicate(),
		"transactions": transactions.duplicate(true)}


## Restores from to_dict(); missing keys keep their current values (older saves stay loadable).
func from_dict(d: Dictionary) -> void:
	cash_cents = int(d.get("cash_cents", cash_cents))
	account_cents = int(d.get("account_cents", account_cents))
	inventory = {}
	for k in d.get("inventory", {}):
		inventory[k] = int(d["inventory"][k])
	for k in d.get("reputation", {}):
		reputation[k] = int(d["reputation"][k])
	drinks_alcohol = int(d.get("drinks_alcohol", drinks_alcohol))
	flags = d.get("flags", flags).duplicate()
	transactions.clear()
	for t in d.get("transactions", []):
		transactions.append({"label": String(t.get("label", "")), "cents": int(t.get("cents", 0)), "kind": String(t.get("kind", ""))})
	cash_changed.emit(cash_cents)
	account_changed.emit(account_cents)
	reputation_changed.emit("nightlife", int(reputation.get("nightlife", 0)))


func change_reputation(axis: String, delta: int) -> void:
	reputation[axis] = int(reputation.get(axis, 0)) + delta
	reputation_changed.emit(axis, reputation[axis])
