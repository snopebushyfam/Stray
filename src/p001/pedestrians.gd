## Ambient pedestrians for Prototype 001 (GDD: "Ambient" NPC type) + the NACHTFLUG door queue.
##
## R13: the behaviour (where to go, when to stop, meet, talk, buy at the KIOSK, hang out at
## NACHTFLUG, leave) comes from StrayAmbientLife (pure state machines on the sidewalk lanes, street
## frame s/v). This node only turns agents into characters: position, facing, animation, collision
## body (AnimatableBody3D, so the player cannot walk through), and the time-of-day profile from the
## game clock. The queue stays where the club mechanic expects it; it only shows calm life
## (talking/idle swaps, small turns) and its size follows the profile - changed only while the
## player is away and the spot is not on screen (_unseen), like people leaving at the block ends.
## Config: res://data/p001/npc_config.json. Characters: R10 looks / R12 humans (unchanged).
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
	## R13: the agent driving this walker (StrayAmbientLife.Agent).
	var agent: StrayAmbientLife.Agent
	var anim_name := ""
	var hidden := false
	var anim_acc := 0.0

var layout: StrayStreetLayout
var cfg: Dictionary = {}
var walkers: Array[Walker] = []
var queue: Array[Node3D] = []
var player: Node3D
var _char_cfg: Dictionary = {}
var _rng := RandomNumberGenerator.new()
## R13 behaviour + time of day (main.gd sets `clock`).
var life := StrayAmbientLife.new()
var clock: StrayGameClock
var _profile_check := 0.0
var _frame := 0
var _queue_life: Array[Dictionary] = []
## Emitted when the time-of-day profile changes (main.gd forwards traffic density).
signal profile_changed(name: String, profile: Dictionary)
## Pedestrian logic time of the last physics tick, microseconds (diagnostics).
var logic_usec := 0
# cached config (no dictionary lookups / allocations per character and frame)
var _anim_names := {}
var _walk_natural := 0.97
var _lod_d2 := 1600.0
var _lod_every := 3


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
		var n_lane := int(lanes[li].get("count", per_lane))
		for k in n_lane:
			var w := Walker.new()
			w.lane = li
			w.v = float(lanes[li]["v"])
			w.dir = int(lanes[li]["dir"])
			w.s = layout.s_start + margin + span * (k + _rng.randf_range(0.1, 0.9)) / n_lane
			if absf(w.s - spawn_sv.x) < 3.0 and absf(w.v - spawn_sv.y) < 2.0:
				w.s += 6.0  # keep the player's spawn point free
			w.speed = _rng.randf_range(ped.get("speed_min", 1.1), ped.get("speed_max", 1.5))
			_make_body(w, ped)
			walkers.append(w)
	_build_queue(cfg.get("club_queue", {}), ped)
	_setup_life(ped)
	print("STRAY_DIAG pedestrians walkers=%d queue=%d profile=%s" % [walkers.size(), queue.size(), life.profile_name])


func _setup_life(ped: Dictionary) -> void:
	var amb: Dictionary = cfg.get("ambient", {})
	_anim_names = {"walk": String(ped.get("anim_walk", "Walk")), "idle": String(ped.get("anim_idle", "Idle")),
		"talk": String(ped.get("anim_talk", "Idle_Talking"))}
	_walk_natural = float(ped.get("walk_natural_speed", 0.97))
	_lod_d2 = pow(float(amb.get("lod_distance", 40.0)), 2)
	_lod_every = int(amb.get("lod_every_frames", 3))
	var margin: float = ped.get("turn_margin", 4.0)
	life.setup(amb, ped.get("lanes", []), layout.s_start + margin, layout.s_end - margin, int(cfg.get("seed", 1)) + 7)
	for w in walkers:
		w.agent = life.add_agent(w.s, w.v, w.dir, w.speed)
	life.can_vanish = func(s: float, v: float) -> bool:
		var en := layout.to_en(s, v)
		return _unseen(StrayStreetLayout.en_to_godot(en.x, en.y, layout.ground_z_at(en)))
	life.warm_up(float(amb.get("warm_up_seconds", 120.0)), _player_sv() if player else Vector2(1e9, 1e9))
	for w in walkers:
		_sync(w, 0.0)


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
		_queue_life.append({"ap": ap, "yaw": root.rotation.y, "body": body, "pos": root.position,
			"t": _rng.randf_range(3.0, 20.0)})


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


## Profile from the game clock (checked every 2 s; schedule in npc_config.json "ambient").
func _update_profile() -> void:
	if clock == null:
		return
	var amb: Dictionary = cfg.get("ambient", {})
	var p := StrayAmbientLife.profile_for(amb.get("schedule", []), clock.minutes, String(clock.date_of(clock.day_index()).weekday))
	if p != life.profile_name and not p.is_empty():
		life.set_profile(p)
		print("STRAY_DIAG city_life profile=%s target_active=%d" % [p, life.target_active()])
		profile_changed.emit(p, life.profile)


func _physics_process(delta: float) -> void:
	if layout == null:
		return
	var t0 := Time.get_ticks_usec()
	_frame += 1
	_profile_check -= delta
	if _profile_check <= 0.0:
		_profile_check = 2.0
		_update_profile()
	var psv := _player_sv() if player else Vector2(1e9, 1e9)
	life.update(delta, psv)
	for w in walkers:
		_sync(w, delta)
	_update_queue(delta)
	logic_usec = Time.get_ticks_usec() - t0


## Agent -> character: position, facing, animation, body; far characters animate at a lower rate.
func _sync(w: Walker, delta: float) -> void:
	var a := w.agent
	var off := a.state == StrayAmbientLife.State.OFFSTAGE
	if off != w.hidden:
		w.hidden = off
		w.root.visible = not off
		if off:
			w.body.global_transform = Transform3D(Basis(), Vector3(0, -500, 0))
	if off:
		return
	w.s = a.s
	w.v = a.v
	w.dir = a.dir
	w.cur_speed = a.cur_speed
	var pos := w.root.position
	if a.cur_speed > 0.0 or delta == 0.0:  # standing people: no transform/body update
		var en := layout.to_en(a.s, a.v)
		pos = StrayStreetLayout.en_to_godot(en.x, en.y, layout.ground_z_at(en))
		w.root.position = pos
		w.body.global_transform = Transform3D(Basis(), pos)
	var d := StrayStreetLayout.en_dir_to_godot(layout.axis_en() * a.face.x + layout.right_en() * a.face.y)
	w.root.rotation.y = atan2(-d.x, -d.z)
	if w.anim == null:
		return
	var want: String = _anim_names[a.anim]
	if want != w.anim_name:
		w.anim.play(want, 0.35)
		w.anim_name = want
		# R12 NPCs carry their measured walk speed (no foot sliding); R10 uses the config value.
		w.anim.set_meta("natural", float(w.anim.get_parent().get_meta("walk_natural_speed", _walk_natural)))
	w.walking = a.anim == "walk"
	w.anim.speed_scale = clampf(a.cur_speed / float(w.anim.get_meta("natural", _walk_natural)), 0.5, 2.0) if w.walking else 1.0
	_advance_anim(w, pos, delta)


## Manual animation update: every frame near the player, every `lod_every_frames` far away.
func _advance_anim(w: Walker, pos: Vector3, delta: float) -> void:
	var ap := w.anim
	if ap.callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL:
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	w.anim_acc += delta
	var far := player != null and pos.distance_squared_to(player.global_position) > _lod_d2
	if not far or (_frame + w.agent.id) % _lod_every == 0:
		ap.advance(w.anim_acc)
		w.anim_acc = 0.0


## True when a person at `p` can appear or disappear unnoticed: outside the active camera's view
## or farther than `vanish_distance` (70 m) from it.
func _unseen(p: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return true
	if cam.global_position.distance_to(p) > float(cfg.get("ambient", {}).get("vanish_distance", 70.0)):
		return true
	return not cam.is_position_in_frustum(p + Vector3(0, 1.0, 0))


## Queue: calm life in place (speaker/listener swaps, small turns towards neighbours); the number
## of people follows the profile, changed only while the player is far from the club.
func _update_queue(delta: float) -> void:
	var ql: Dictionary = cfg.get("ambient", {}).get("queue_life", {})
	var want := int(life.profile.get("queue", queue.size()))
	var club := StrayStreetLayout._v2(layout.club["en"])
	var pp := Vector2(player.global_position.x, -player.global_position.z) if player else Vector2(1e9, 1e9)
	var far := pp.distance_to(club) > float(ql.get("hide_min_player_distance", 30.0))
	for i in _queue_life.size():
		var q: Dictionary = _queue_life[i]
		var root := queue[i]
		var show := i < want
		# only while the player is away from the club and the spot is not on screen
		if far and root.visible != show and _unseen(q["pos"]):
			root.visible = show
			(q["body"] as Node3D).position = q["pos"] if show else Vector3(0, -500, 0)
		if not root.visible:
			continue
		q["t"] = float(q["t"]) - delta
		if float(q["t"]) <= 0.0:
			q["t"] = _rng.randf_range(float(ql.get("swap_min", 12.0)), float(ql.get("swap_max", 35.0)))
			var ap: AnimationPlayer = q["ap"]
			if ap:
				ap.play("Idle" if ap.current_animation == "Idle_Talking" else "Idle_Talking", 0.5)
			q["turn"] = deg_to_rad(_rng.randf_range(-1.0, 1.0) * float(ql.get("turn_deg", 14.0)))
		root.rotation.y = lerp_angle(root.rotation.y, float(q["yaw"]) + float(q.get("turn", 0.0)), minf(1.0, delta * 1.5))
