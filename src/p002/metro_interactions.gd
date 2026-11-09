## U-Bahn interactions (Roadmap R5): surface entrances (Friesenplatz in P001, Dom/Hbf in P002),
## ticket machine, boarding, stairs up, Hbf door. Rules live in StrayTransit; this node does the
## points, prompts, option panels and teleports. Plugs into StrayInteractions as an extension.
## Config: data/p002/transit_config.json.
class_name StrayMetroInteractions
extends Node

## Entered the platform of `station` (id).
signal metro_entered(station: String)
## Came up to the surface at `station`; main.gd switches the visible area.
signal metro_left(station: String)
## A ticket was bought at the machine.
signal ticket_bought
## A ride finished (result of StrayTransit.ride()).
signal rode(result: Dictionary)

const IDS := ["ubahn_friesenplatz", "ubahn_dom_hbf", "metro_ticket", "metro_board", "metro_exit", "hbf_door"]

var transit: StrayTransit
var station_node: StrayMetroStation
var area: StrayAreaLayout
var ix: StrayInteractions
var texts: Dictionary = {}
var last_ride: Dictionary = {}
var _ask: String = ""


func setup(p_ix: StrayInteractions, p_transit: StrayTransit, p_station: StrayMetroStation, p_area: StrayAreaLayout) -> void:
	ix = p_ix
	transit = p_transit
	station_node = p_station
	area = p_area
	texts = transit.cfg.get("texts", {})
	var fp: Dictionary = transit.cfg.get("stations", {}).get("friesenplatz", {})
	ix.points["ubahn_friesenplatz"] = _street_point(float(fp.get("s", 100.0)), float(fp.get("v", -10.4)) - 0.9)
	if area:
		ix.points["ubahn_dom_hbf"] = _area_point(StrayStreetLayout._v2(area.ubahn_player["en"]) + StrayStreetLayout._v2(area.ubahn_player.get("exit_dir_en", [0, 1])) * 0.9)
		var he := StrayStreetLayout._v2(area.hbf_main_exit["en"]) + StrayStreetLayout._v2(area.hbf_main_exit.get("normal_en", [0, 1])) * 1.2
		ix.points["hbf_door"] = _area_point(he)
	ix.points["metro_ticket"] = station_node.points["ticket"]
	ix.points["metro_board"] = station_node.points["board"]
	ix.points["metro_exit"] = station_node.points["exit"]
	ix.extensions.append(self)
	print("STRAY_DIAG metro entrances friesenplatz=%s dom_hbf=%s" % [ix.points["ubahn_friesenplatz"], ix.points.get("ubahn_dom_hbf", "-")])


## Ground point in the P001 street frame.
func _street_point(s: float, v: float) -> Vector3:
	var en := ix.layout.to_en(s, v)
	return StrayStreetLayout.en_to_godot(en.x, en.y, ix.layout.ground_z_at(en))


func _area_point(en: Vector2) -> Vector3:
	return StrayStreetLayout.en_to_godot(en.x, en.y, area.ground_z_at(en))


func handles(id: String) -> bool:
	return id in IDS


func prompt(id: String) -> String:
	match id:
		"ubahn_friesenplatz":
			return String(texts.get("entrance", "[E] U-Bahn %s")) % transit.station_name("friesenplatz")
		"ubahn_dom_hbf":
			return String(texts.get("entrance", "[E] U-Bahn %s")) % transit.station_name("dom_hbf")
		"metro_ticket":
			return String(texts.get("machine", "[E] Fahrkartenautomat"))
		"metro_board":
			return String(texts.get("board", "[E] Einsteigen")) % [transit.cfg.get("line", "5"), transit.station_name(transit.other_station())]
		"metro_exit":
			return String(texts.get("exit", "[E] Nach oben"))
		"hbf_door":
			return String(texts.get("hbf_door", "[E] Hauptbahnhof"))
	return ""


func interact(id: String) -> void:
	match id:
		"ubahn_friesenplatz":
			enter_station("friesenplatz")
		"ubahn_dom_hbf":
			enter_station("dom_hbf")
		"metro_ticket":
			_ask = "ticket"
			ix.open_extension_options(self, String(texts.get("machine_title", "")),
				String(texts.get("machine_question", "%s für %s?")) % [transit.cfg.get("ticket", {}).get("label", "Fahrkarte"), StrayLifeState.euro(transit.ticket_price())],
				[texts.get("buy", "Kaufen"), texts.get("cancel", "Abbrechen")])
		"metro_board":
			_ask = "ride"
			var q := String(texts.get("board_question" if transit.has_ticket else "board_no_ticket", "%s? (%d)"))
			ix.open_extension_options(self, String(texts.get("board_title", "Linie %s")) % transit.cfg.get("line", "5"),
				q % [transit.station_name(transit.other_station()), transit.ride_minutes()],
				[texts.get("ride", "Fahren"), texts.get("wait", "Warten")])
		"metro_exit":
			leave_station()
		"hbf_door":
			ix.ui.show_message("Köln Hbf", String(texts.get("hbf_closed", "")), 4.0)


func option(index: int) -> void:
	var what := _ask
	_ask = ""
	ix.close_panel()
	if index != 0:
		return
	if what == "ticket":
		buy_ticket()
	elif what == "ride":
		ride()


## Goes down to the platform of `station_id`.
func enter_station(station_id: String) -> void:
	transit.station = station_id
	station_node.set_station(transit.station_name(station_id))
	station_node.visible = true
	# Face along the platform (-X, towards machine and train door); +PI/2 makes -Z point to -X.
	_place(station_node.points["exit"] + Vector3(-1.5, 0.0, -1.0), PI * 0.5)
	ix.player.set_indoor_camera(true)
	ix.life.flags["inside_metro"] = true
	metro_entered.emit(station_id)
	print("STRAY_DIAG metro entered station=%s" % station_id)


func buy_ticket() -> Dictionary:
	var r := transit.buy_ticket(ix.life)
	var msg := ""
	match r.reason:
		"bought":
			msg = String(texts.get("bought", "%s")) % StrayLifeState.euro(transit.ticket_price())
		"already":
			msg = String(texts.get("already", ""))
		_:
			msg = String(texts.get("no_money", ""))
	ix.ui.show_message(String(texts.get("machine_title", "")), msg, 3.0)
	if r.ok:
		ticket_bought.emit()
	print("STRAY_DIAG metro ticket=%s cash=%s" % [r.reason, StrayLifeState.euro(ix.life.cash_cents)])
	return r


## Rides to the other station (fade-less in the rough build: the platform sign changes).
func ride() -> Dictionary:
	var r := transit.ride(ix.life, ix.clock)
	last_ride = r
	station_node.set_station(transit.station_name(transit.station))
	_place(station_node.points["arrive"], 0.0)
	var msg := String(texts.get("arrived", "%s.")) % transit.station_name(transit.station)
	if r.checked:
		if r.fined_cents == 0:
			msg += "\n" + String(texts.get("check_ok", ""))
		elif r.paid == "unpaid":
			msg += "\n" + String(texts.get("check_billed", "%s")) % StrayLifeState.euro(r.fined_cents)
		else:
			msg += "\n" + String(texts.get("check_fined", "%s")) % StrayLifeState.euro(r.fined_cents)
	ix.ui.show_message("Linie %s" % transit.cfg.get("line", "5"), msg, 5.0)
	print("STRAY_DIAG metro ride %s->%s min=%d checked=%s ticket=%s fine=%d paid=%s time=%s" % [
		r.from, r.to, r.minutes, r.checked, r.had_ticket, r.fined_cents, r.paid, ix.clock.hhmm() if ix.clock else "-"])
	rode.emit(r)
	return r


## Climbs the stairs to the surface entrance of the current station.
func leave_station() -> void:
	var st := transit.station
	station_node.visible = false
	ix.life.flags["inside_metro"] = false
	ix.player.set_indoor_camera(false)
	if st == "dom_hbf" and area:
		var p := area.stand_position(area.spawn_en, 0.9)
		_place(p - Vector3(0, 0.95, 0), StrayAreaLayout.yaw_of(area.spawn_dir_en))
	else:
		var fp: Dictionary = transit.cfg.get("stations", {}).get("friesenplatz", {})
		# 6 m south of the stele: the camera (3.8 m behind the player) stays clear of the sign.
		var p2 := _street_point(float(fp.get("s", 100.0)) - 6.0, float(fp.get("v", -10.4)) - 1.5)
		var d := StrayStreetLayout.en_dir_to_godot(-ix.layout.axis_en())
		_place(p2, atan2(-d.x, -d.z))
	metro_left.emit(st)
	print("STRAY_DIAG metro left station=%s pos=%s" % [st, ix.player.global_position])


func _place(ground: Vector3, yaw: float) -> void:
	ix.player.global_position = ground + Vector3(0, 0.95, 0)
	ix.player.velocity = Vector3.ZERO
	ix.player.face_yaw(yaw)
