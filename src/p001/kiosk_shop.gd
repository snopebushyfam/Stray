## Kiosk purchase rules (Prototype 001). Config: data/p001/economy_config.json ["kiosk"].
class_name StrayKioskShop
extends RefCounted

var cfg: Dictionary = {}


func _init(kiosk_cfg: Dictionary = {}) -> void:
	cfg = kiosk_cfg


func items() -> Array:
	return cfg.get("items", [])


func find(item_id: String) -> Dictionary:
	for it in items():
		if it.get("id", "") == item_id:
			return it
	return {}


## Buys one item. Returns {ok: bool, text: String} with the shopkeeper's line.
func buy(state: StrayLifeState, item_id: String) -> Dictionary:
	var it := find(item_id)
	if it.is_empty():
		return {"ok": false, "text": "Haben wir nicht."}
	var price: int = int(it.get("price", 0))
	if not state.pay(price, "Kiosk: %s" % it.get("name", item_id)):
		return {"ok": false, "text": String(cfg.get("too_poor", "Reicht nicht. %s")) % StrayLifeState.euro(price)}
	state.add_item(item_id, it.get("tags", []))
	return {"ok": true, "text": String(cfg.get("bought", "%s für %s.")) % [it.get("name", item_id), StrayLifeState.euro(price)]}
