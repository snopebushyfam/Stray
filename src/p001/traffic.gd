## Car traffic for Prototype 001: both carriageways, two lanes each (driving on the right).
##
## Simple car-following: cruise speed per car, slow to the leader inside `safe_gap`, stop inside
## `stop_gap`; stop for the player standing in the lane ahead. Cars run from s_min to s_max (beyond
## the playable 150 m, on the real DGM1 terrain which includes the road surface) and respawn at the
## start after a short delay. Heights come from a ray cast onto the static world each tick.
## Config: res://data/p001/npc_config.json ("traffic").
class_name StrayTraffic
extends Node3D

## Collision layer of car bodies (bit 2). World geometry is layer 1.
const CAR_LAYER := 2

class Car:
	var root: Node3D
	var body: AnimatableBody3D
	var wheels: Array[Node3D] = []
	var lane: int
	var dir: int
	var s: float
	var v: float
	var length: float
	var cruise: float
	var speed: float
	var active := true
	var respawn_in := 0.0
	var y := 0.0
	var is_police := false
	var light_bar: Array[StandardMaterial3D] = []

var layout: StrayStreetLayout
var cfg: Dictionary = {}
var cars: Array[Car] = []
var player: Node3D
var _rng := RandomNumberGenerator.new()
var _mats: Dictionary = {}
## While true the police car brakes to a stop and flashes its lights (police check in progress).
var police_hold := false
var _blink := 0.0


## Spawns the cars spread over each lane.
func setup(p_layout: StrayStreetLayout, p_cfg: Dictionary, p_player: Node3D) -> void:
	layout = p_layout
	cfg = p_cfg.get("traffic", {})
	player = p_player
	_rng.seed = int(p_cfg.get("seed", 1)) + 99
	var lanes: Array = cfg.get("lanes", [])
	var s_min: float = cfg.get("s_min", -80.0)
	var s_max: float = cfg.get("s_max", 165.0)
	var per_lane: int = cfg.get("cars_per_lane", 3)
	for li in lanes.size():
		for k in per_lane:
			var c := Car.new()
			c.lane = li
			c.dir = int(lanes[li]["dir"])
			c.v = float(lanes[li]["v"])
			c.length = _rng.randf_range(4.1, 4.9)
			c.cruise = _rng.randf_range(cfg.get("speed_min", 8.0), cfg.get("speed_max", 12.0))
			c.speed = c.cruise
			c.s = s_min + (s_max - s_min) * (k + _rng.randf_range(0.15, 0.85)) / per_lane
			_build_car(c)
			cars.append(c)
	for k in int(cfg.get("police_cars", 0)):
		if k < cars.size():
			_make_police(cars[k * per_lane])
	print("STRAY_DIAG traffic cars=%d lanes=%d police=%d" % [cars.size(), lanes.size(), int(cfg.get("police_cars", 0))])


## Turns a car into a police car: silver-white body, blue side stripe, roof light bar.
func _make_police(c: Car) -> void:
	c.is_police = true
	c.cruise = minf(c.cruise, 9.0)
	var white := _mat("police_body", Color(0.85, 0.87, 0.9))
	var stripe := _mat("police_stripe", Color(0.1, 0.25, 0.6))
	var paint: Variant = c.root.get_meta("paint", null)
	for child in c.root.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).material_override == paint:
			(child as MeshInstance3D).material_override = white
	_box(c.root, Vector3(0, 0.75, 0), Vector3(1.82, 0.12, c.length * 0.9), stripe)
	for x in [-0.35, 0.35]:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.1, 0.3, 1.0)
		m.emission_enabled = true
		m.emission = Color(0.1, 0.3, 1.0)
		m.emission_energy_multiplier = 0.3
		_box(c.root, Vector3(x, 1.4, c.length * 0.06), Vector3(0.5, 0.12, 0.25), m)
		c.light_bar.append(m)


## The police car (first one), or null.
func police_car() -> Car:
	for c in cars:
		if c.is_police:
			return c
	return null


func _mat(key: String, c: Color, emissive: float = 0.0) -> StandardMaterial3D:
	var k := "%s_%s_%.1f" % [key, c.to_html(), emissive]
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.3
		m.metallic = 0.1
		if emissive > 0.0:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = emissive
		_mats[k] = m
	return _mats[k]


func _box(parent: Node3D, pos: Vector3, size: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


## Car visual in local space: length along -Z (front at -Z), width along X, ground at y = 0.
func _build_car(c: Car) -> void:
	var colors: Array = cfg.get("colors", [[0.3, 0.3, 0.3]])
	var col: Array = colors[_rng.randi() % colors.size()]
	var w := 1.8
	var L := c.length
	c.root = Node3D.new()
	add_child(c.root)
	# One material per colour (before R9 all cars shared the first car's paint).
	for wheel in StrayCarModel.build(c.root, L, w, Color(col[0], col[1], col[2]), true,
			cfg.get("headlight_emission", 4.0), cfg.get("taillight_emission", 3.0)):
		c.wheels.append(wheel)
	c.body = AnimatableBody3D.new()
	c.body.collision_layer = CAR_LAYER
	c.body.collision_mask = 0
	c.body.sync_to_physics = false
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(w, 1.45, L)
	cs.shape = sh
	cs.position.y = 0.75
	c.body.add_child(cs)
	add_child(c.body)


func _ground_y(en: Vector2, fallback: float) -> float:
	var space := get_world_3d().direct_space_state
	var top := StrayStreetLayout.en_to_godot(en.x, en.y, 40.0)
	var q := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 80.0, 1)
	if player is CollisionObject3D:
		q.exclude = [(player as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(q)
	return hit.position.y if not hit.is_empty() else fallback


func _player_sv() -> Vector2:
	var p := player.global_position
	return layout.to_street(Vector2(p.x, -p.z))


func _physics_process(delta: float) -> void:
	if layout == null:
		return
	var s_min: float = cfg.get("s_min", -80.0)
	var s_max: float = cfg.get("s_max", 165.0)
	var safe: float = cfg.get("safe_gap", 8.0)
	var stop: float = cfg.get("stop_gap", 4.0)
	var psv := _player_sv() if player else Vector2(1e9, 1e9)
	for c in cars:
		if not c.active:
			c.respawn_in -= delta
			if c.respawn_in <= 0.0 and _entry_clear(c):
				c.s = s_min if c.dir > 0 else s_max
				c.speed = c.cruise
				c.active = true
				c.root.visible = true
			continue
		var target := c.cruise
		if c.is_police and police_hold:
			target = 0.0
		# Leader in the same lane.
		for o in cars:
			if o != c and o.active and o.lane == c.lane:
				var gap := (o.s - c.s) * c.dir - (o.length + c.length) * 0.5
				if gap > -0.5 and gap < safe:
					target = minf(target, o.speed * clampf((gap - stop) / (safe - stop), 0.0, 1.0))
		# Player in this lane ahead: stop short of them.
		var p_ahead := (psv.x - c.s) * c.dir - c.length * 0.5
		if absf(psv.y - c.v) < 1.7 and p_ahead > -0.5 and p_ahead < float(cfg.get("player_stop_distance", 9.0)):
			target = 0.0 if p_ahead < 3.5 else minf(target, c.cruise * (p_ahead - 3.5) / 5.5)
		var rate: float = cfg.get("accel", 2.5) if target > c.speed else cfg.get("brake", 6.0)
		c.speed = move_toward(c.speed, target, rate * delta)
		c.s += c.dir * c.speed * delta
		if (c.dir > 0 and c.s > s_max) or (c.dir < 0 and c.s < s_min):
			c.active = false
			c.root.visible = false
			c.respawn_in = _rng.randf_range(cfg.get("respawn_delay_min", 0.5), cfg.get("respawn_delay_max", 4.0))
			c.body.global_transform = Transform3D(Basis(), Vector3(0, -500, 0))
			continue
		var en := layout.to_en(c.s, c.v)
		c.y = _ground_y(en, layout.ground_z_at(en))
		var d := StrayStreetLayout.en_dir_to_godot(layout.axis_en() * c.dir)
		var xf := Transform3D(Basis.looking_at(d, Vector3.UP), StrayStreetLayout.en_to_godot(en.x, en.y, 0.0) + Vector3(0, c.y, 0))
		c.root.global_transform = xf
		c.body.global_transform = xf
		for wh in c.wheels:
			wh.rotate_object_local(Vector3.UP, -c.speed * delta / 0.32)
		if c.is_police:
			_blink += delta
			for i in c.light_bar.size():
				var on := police_hold and int(_blink * 4.0 + i) % 2 == 0
				c.light_bar[i].emission_energy_multiplier = 6.0 if on else 0.3


func _entry_clear(c: Car) -> bool:
	var entry: float = cfg.get("s_min", -80.0) if c.dir > 0 else cfg.get("s_max", 165.0)
	for o in cars:
		if o != c and o.active and o.lane == c.lane and absf(o.s - float(entry)) < float(cfg.get("safe_gap", 8.0)) * 2.0:
			return false
	return true
