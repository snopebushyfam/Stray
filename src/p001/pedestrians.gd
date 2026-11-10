## Ambient pedestrians for Prototype 001 (GDD: "Ambient" NPC type) + the NACHTFLUG door queue.
##
## Each pedestrian walks along a sidewalk lane (street frame: s along, v across) and switches to
## the nearest opposite-direction lane on the same side at the segment ends, so lanes never carry
## oncoming traffic. Rules: keep `follow_gap` behind the walker ahead, stop when the player stands
## within `yield_radius` in front. Bodies are AnimatableBody3D so the player cannot walk through.
## Config: res://data/p001/npc_config.json. Character: CC0 Quaternius mannequin (player_config.json).
class_name StrayPedestrians
extends Node3D

## Collision layer of NPC bodies (bit 3). The player's mask includes it.
const NPC_LAYER := 4

class Walker:
	var root: Node3D
	var body: AnimatableBody3D
	var anim: AnimationPlayer
	var s: float
	var v: float
	var lane: int
	var dir: int
	var speed: float
	var cur_speed: float = 0.0
	var walking := false

var layout: StrayStreetLayout
var cfg: Dictionary = {}
var walkers: Array[Walker] = []
var queue: Array[Node3D] = []
var player: Node3D
var _char_cfg: Dictionary = {}
var _rng := RandomNumberGenerator.new()


## Spawns all pedestrians. `character_cfg` is player_config.json["character"].
func setup(p_layout: StrayStreetLayout, p_cfg: Dictionary, character_cfg: Dictionary, p_player: Node3D) -> void:
	layout = p_layout
	cfg = p_cfg
	_char_cfg = character_cfg
	player = p_player
	_rng.seed = int(cfg.get("seed", 1))
	var ped: Dictionary = cfg.get("pedestrians", {})
	var lanes: Array = ped.get("lanes", [])
	var margin: float = ped.get("turn_margin", 4.0)
	var per_lane: int = ped.get("count_per_lane", 3)
	var span := layout.street_length() - 2.0 * margin
	var spawn_sv := layout.to_street(layout.spawn_en)
	for li in lanes.size():
		for k in per_lane:
			var w := Walker.new()
			w.lane = li
			w.v = float(lanes[li]["v"])
			w.dir = int(lanes[li]["dir"])
			w.s = layout.s_start + margin + span * (k + _rng.randf_range(0.1, 0.9)) / per_lane
			if absf(w.s - spawn_sv.x) < 3.0 and absf(w.v - spawn_sv.y) < 2.0:
				w.s += 6.0  # keep the player's spawn point free
			w.speed = _rng.randf_range(ped.get("speed_min", 1.1), ped.get("speed_max", 1.5))
			_make_body(w, ped)
			walkers.append(w)
	_build_queue(cfg.get("club_queue", {}), ped)
	print("STRAY_DIAG pedestrians walkers=%d queue=%d" % [walkers.size(), queue.size()])


## `human_type`: R12 pilot NPC id (StrayNpcHuman); "" or unavailable -> R10 mannequin with a look.
func _make_character(ped: Dictionary, color_index: int, human_type: String = "") -> Array:
	if not human_type.is_empty() and StrayNpcHuman.available(human_type):
		var h := StrayNpcHuman.create(human_type)
		h.rotation.y = deg_to_rad(_char_cfg.get("yaw_offset_deg", 180.0))
		return [h, h.get_node("AnimationPlayer")]
	var scene: PackedScene = load(_char_cfg.get("scene", ""))
	var model: Node3D = scene.instantiate()
	model.rotation.y = deg_to_rad(_char_cfg.get("yaw_offset_deg", 180.0))
	# R10: everyday outfits (character_looks.json); the walkers use the "street" group.
	var looks := StrayCharacterLook.group(String(ped.get("look_group", "street")))
	StrayCharacterLook.apply(model, String(looks[color_index % looks.size()]) if not looks.is_empty() else "")
	var players := model.find_children("*", "AnimationPlayer", true, false)
	return [model, players[0] if not players.is_empty() else null]


func _make_body(w: Walker, ped: Dictionary) -> void:
	w.root = Node3D.new()
	add_child(w.root)
	var pilot: Dictionary = cfg.get("r12_pilot", {}) if bool(cfg.get("r12_pilot", {}).get("enabled", false)) else {}
	var human := String(pilot.get("walker_type", "")) if walkers.size() == int(pilot.get("walker_index", -1)) else ""
	var made := _make_character(ped, _rng.randi(), human)
	var model: Node3D = made[0]
	var hs := _rng.randf_range(ped.get("height_scale_min", 0.95), ped.get("height_scale_max", 1.05))
	model.scale = Vector3.ONE * hs
	w.root.add_child(model)
	w.anim = made[1]
	if w.anim:
		w.anim.play(ped.get("anim_walk", "Walk"))
		w.anim.seek(_rng.randf() * w.anim.current_animation_length, true)
		w.walking = true
	w.body = AnimatableBody3D.new()
	w.body.collision_layer = NPC_LAYER
	w.body.collision_mask = 0
	w.body.sync_to_physics = false
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	w.body.add_child(cs)
	add_child(w.body)
	_place(w)


func _build_queue(q: Dictionary, ped: Dictionary) -> void:
	if q.is_empty():
		return
	var pos := StrayStreetLayout._v2(layout.club["en"])
	var n := StrayStreetLayout._v2(layout.club["normal_en"]).normalized()
	var t := Vector2(n.y, -n.x)
	for i in int(q.get("count", 5)):
		var p: Vector2 = pos + n * float(q.get("out", 2.7)) + t * (float(q.get("start_along", -1.8)) - i * float(q.get("spacing", 0.9)))
		var qp: Dictionary = cfg.get("r12_pilot", {}) if bool(cfg.get("r12_pilot", {}).get("enabled", false)) else {}
		var made := _make_character(ped.merged({"look_group": "queue"}), i + 3,
			String(qp.get("queue_type", "")) if i == int(qp.get("queue_index", -1)) else "")
		var model: Node3D = made[0]
		var root := Node3D.new()
		root.position = StrayStreetLayout.en_to_godot(p.x, p.y, layout.ground_z_at(p))
		# Face along the queue towards the door (+t direction), slightly turned to the street.
		var face := StrayStreetLayout.en_dir_to_godot((t + n * 0.35).normalized())
		root.rotation.y = atan2(-face.x, -face.z)
		root.add_child(model)
		add_child(root)
		var ap: AnimationPlayer = made[1]
		if ap:
			ap.play(q.get("anim", "Idle_Talking") if i % 2 == 0 else ped.get("anim_idle", "Idle"))
			ap.seek(_rng.randf() * ap.current_animation_length, true)
		var body := StaticBody3D.new()
		body.collision_layer = NPC_LAYER
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.28
		cap.height = 1.75
		cs.shape = cap
		cs.position.y = 0.875
		body.add_child(cs)
		body.position = root.position
		add_child(body)
		queue.append(root)


func _place(w: Walker) -> void:
	var en := layout.to_en(w.s, w.v)
	var pos := StrayStreetLayout.en_to_godot(en.x, en.y, layout.ground_z_at(en))
	w.root.position = pos
	var d := StrayStreetLayout.en_dir_to_godot(layout.axis_en() * w.dir)
	w.root.rotation.y = atan2(-d.x, -d.z)
	w.body.global_transform = Transform3D(Basis(), pos)


func _player_sv() -> Vector2:
	var p := player.global_position
	return layout.to_street(Vector2(p.x, -p.z))


func _physics_process(delta: float) -> void:
	if layout == null:
		return
	var ped: Dictionary = cfg.get("pedestrians", {})
	var lanes: Array = ped.get("lanes", [])
	var margin: float = ped.get("turn_margin", 4.0)
	var gap_keep: float = ped.get("follow_gap", 1.6)
	var yield_r: float = ped.get("yield_radius", 1.4)
	var psv := _player_sv() if player else Vector2(1e9, 1e9)
	for w in walkers:
		var target := w.speed
		# Yield to the player standing in front.
		var ahead := (psv.x - w.s) * w.dir
		if ahead > 0.0 and ahead < yield_r + 0.6 and absf(psv.y - w.v) < 0.8:
			target = 0.0
		# Keep distance to the walker ahead in the same lane.
		for o in walkers:
			if o != w and o.lane == w.lane:
				var g := (o.s - w.s) * w.dir
				if g > 0.0 and g < gap_keep:
					target = minf(target, o.cur_speed * 0.9)
		w.cur_speed = move_toward(w.cur_speed, target, 3.0 * delta)
		w.s += w.dir * w.cur_speed * delta
		# Turn at the ends: hop to the nearest opposite-direction lane on the same side.
		if (w.dir > 0 and w.s > layout.s_end - margin) or (w.dir < 0 and w.s < layout.s_start + margin):
			var best := w.lane
			var best_d := 1e9
			for li in lanes.size():
				var lv: float = lanes[li]["v"]
				if int(lanes[li]["dir"]) != w.dir and signf(lv) == signf(w.v) and absf(lv - w.v) < best_d:
					best = li
					best_d = absf(lv - w.v)
			w.lane = best
			w.dir = int(lanes[best]["dir"])
		# Drift smoothly onto the lane line (lane changes at the ends).
		w.v = move_toward(w.v, float(lanes[w.lane]["v"]), 1.0 * delta)
		_place(w)
		if w.anim:
			var moving := w.cur_speed > 0.15
			if moving != w.walking:
				w.anim.play(ped.get("anim_walk", "Walk") if moving else ped.get("anim_idle", "Idle"), 0.25)
				w.walking = moving
			# R12 NPCs carry their measured walk speed (no foot sliding); R10 uses the config value.
			var natural: float = float(w.anim.get_parent().get_meta("walk_natural_speed", ped.get("walk_natural_speed", 0.97)))
			w.anim.speed_scale = clampf(w.cur_speed / natural, 0.5, 2.0) if moving else 1.0
