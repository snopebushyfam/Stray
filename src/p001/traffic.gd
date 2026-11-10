## Car traffic for Prototype 001: both carriageways, two lanes each (driving on the right).
##
## Simple car-following: cruise speed per car, slow to the leader inside `safe_gap`, stop inside
## `stop_gap`; stop for the player standing in the lane ahead. Cars run from s_min to s_max (beyond
## the playable 150 m, on the real DGM1 terrain which includes the road surface) and respawn at the
## start after a short delay. Heights come from a ray cast onto the static world (R13: every 4th tick
## per car, staggered; in between the last height is kept).
## R13 city life: cruise speeds drift slightly over time, brake lights light up while slowing or
## standing, one taxi sometimes pulls over to the kerb (in a gap of the parked cars) for a few
## seconds, and the number of cars on the road follows the time-of-day profile (`active_share`).
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
	var base_cruise := 10.0
	var drift_in := 0.0
	var brake: MeshInstance3D
	var braking := false
	var ray_in := 0
	var lane_v := 0.0
	var is_taxi := false
	## Taxi stop: "" (driving) | "in" (pulling over) | "stop" | "out" (rejoining the lane)
	var taxi := ""
	var taxi_stop_s := 0.0
	var taxi_will_stop := false
	var stop_timer := 0.0

var layout: StrayStreetLayout
var cfg: Dictionary = {}
var cars: Array[Car] = []
var player: Node3D
var _rng := RandomNumberGenerator.new()
var _mats: Dictionary = {}
## While true the police car brakes to a stop and flashes its lights (police check in progress).
var police_hold := false
var _blink := 0.0
## R13: share of the cars that drive (time-of-day profile); the rest wait off the playable block.
var active_share := 1.0
static var _brake_mesh: ArrayMesh
static var _brake_mat: StandardMaterial3D


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
			c.base_cruise = c.cruise
			c.drift_in = _rng.randf_range(4.0, 14.0)
			c.lane_v = c.v
			c.ray_in = cars.size() % 4
			c.speed = c.cruise
			c.s = s_min + (s_max - s_min) * (k + _rng.randf_range(0.15, 0.85)) / per_lane
			_build_car(c)
			cars.append(c)
	for k in int(cfg.get("police_cars", 0)):
		if k < cars.size():
			_make_police(cars[k * per_lane])
	var tx: Dictionary = cfg.get("taxi", {})
	if bool(tx.get("enabled", false)):
		var idx := int(tx.get("lane", 1)) * per_lane + 1
		if idx < cars.size() and not cars[idx].is_police:
			_make_taxi(cars[idx], tx)
	print("STRAY_DIAG traffic cars=%d lanes=%d police=%d" % [cars.size(), lanes.size(), int(cfg.get("police_cars", 0))])


## Turns a car into a police car: silver-white body, blue side stripe, roof light bar.
func _make_police(c: Car) -> void:
	c.is_police = true
	c.cruise = minf(c.cruise, 9.0)
	var white := _mat("police_body", Color(0.85, 0.87, 0.9))
	var stripe := _mat("police_stripe", Color(0.1, 0.25, 0.6))
	# Rebuild the (merged) car visual in police colours, keep the spinning wheels.
	for child in c.root.get_children():
		if child.name == "CarBody":
			(child as MeshInstance3D).mesh = StrayCarModel.car_mesh(c.length, 1.8, white.albedo_color, true, false,
				cfg.get("headlight_emission", 4.0), cfg.get("taillight_emission", 3.0))
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


## Taxi: cream body with a lit roof sign; stops now and then at the kerb (see _taxi_target).
func _make_taxi(c: Car, tx: Dictionary) -> void:
	c.is_taxi = true
	var col: Array = tx.get("color", [0.86, 0.82, 0.62])
	for child in c.root.get_children():
		if child.name == "CarBody":
			(child as MeshInstance3D).mesh = StrayCarModel.car_mesh(c.length, 1.8, Color(col[0], col[1], col[2]), true, false,
				cfg.get("headlight_emission", 4.0), cfg.get("taillight_emission", 3.0))
	_box(c.root, Vector3(0, 1.42, c.length * 0.05), Vector3(0.55, 0.16, 0.22), _mat("taxi_sign", Color(1.0, 0.85, 0.3), 2.5))
	_plan_taxi(c)


func _plan_taxi(c: Car) -> void:
	var tx: Dictionary = cfg.get("taxi", {})
	var r: Array = tx.get("stop_s", [29.0, 35.0])
	c.taxi_will_stop = _rng.randf() < float(tx.get("chance", 0.7))
	c.taxi_stop_s = _rng.randf_range(float(r[0]), float(r[1]))
	c.taxi = ""


## Two red brake lamps behind the tail lights, shown only while braking/standing (one shared mesh).
func _add_brake_lights(c: Car) -> void:
	if _brake_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for x in [-0.63, 0.63]:
			var b := BoxMesh.new()
			b.size = Vector3(0.34, 0.1, 0.02)
			var arr := b.get_mesh_arrays()
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for i in (arr[Mesh.ARRAY_INDEX] as PackedInt32Array):
				st.add_vertex(verts[i] + Vector3(x, 0, 0))
		_brake_mesh = st.commit()
		_brake_mat = StandardMaterial3D.new()
		_brake_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_brake_mat.albedo_color = Color(1.0, 0.08, 0.05)
		_brake_mat.emission_enabled = true
		_brake_mat.emission = Color(1.0, 0.08, 0.05)
		_brake_mat.emission_energy_multiplier = 4.0
	c.brake = MeshInstance3D.new()
	c.brake.mesh = _brake_mesh
	c.brake.material_override = _brake_mat
	c.brake.position = Vector3(0, 0.72, c.length * 0.5 + 0.035)
	c.brake.visible = false
	c.brake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.root.add_child(c.brake)


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
	_add_brake_lights(c)
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
				if not c.is_police and active_count() >= roundi(cars.size() * active_share):
					c.respawn_in = 5.0  # fewer cars at this time of day: wait off the block
					continue
				c.s = s_min if c.dir > 0 else s_max
				c.v = c.lane_v
				c.speed = c.cruise
				c.active = true
				c.root.visible = true
				if c.is_taxi:
					_plan_taxi(c)
			continue
		# Drivers differ and vary a little: new cruise speed within +-12 % every few seconds.
		c.drift_in -= delta
		if c.drift_in <= 0.0:
			c.drift_in = _rng.randf_range(5.0, 15.0)
			c.cruise = c.base_cruise * _rng.randf_range(0.88, 1.12)
		var target := c.cruise
		if c.is_police and police_hold:
			target = 0.0
		if c.is_taxi:
			target = _taxi_target(c, target, delta)
		# Leader in the same lane (a taxi standing at the kerb is out of the lane).
		for o in cars:
			if o != c and o.active and o.lane == c.lane and absf(o.v - o.lane_v) < 1.0:
				var gap := (o.s - c.s) * c.dir - (o.length + c.length) * 0.5
				if gap > -0.5 and gap < safe:
					target = minf(target, o.speed * clampf((gap - stop) / (safe - stop), 0.0, 1.0))
		# Player in this lane ahead: stop short of them.
		# R13: the look-ahead grows with the braking distance (cruise speeds now drift up to +12 %).
		var p_ahead := (psv.x - c.s) * c.dir - c.length * 0.5
		var brake_dist := 3.5 + c.speed * c.speed / (2.0 * float(cfg.get("brake", 6.0)))
		var look := maxf(float(cfg.get("player_stop_distance", 9.0)), brake_dist + 2.0)
		if absf(psv.y - c.v) < 1.7 and p_ahead > -0.5 and p_ahead < look:
			if p_ahead < brake_dist + 0.5:
				target = 0.0
			else:
				target = minf(target, c.cruise * (p_ahead - 3.5) / maxf(look - 3.5, 0.1))
		var rate: float = cfg.get("accel", 2.5) if target > c.speed else cfg.get("brake", 6.0)
		var braking := target < c.speed - 0.2 or c.speed < 0.3
		if braking != c.braking:
			c.braking = braking
			c.brake.visible = braking
		c.speed = move_toward(c.speed, target, rate * delta)
		c.s += c.dir * c.speed * delta
		if (c.dir > 0 and c.s > s_max) or (c.dir < 0 and c.s < s_min):
			c.active = false
			c.root.visible = false
			c.respawn_in = _rng.randf_range(cfg.get("respawn_delay_min", 0.5), cfg.get("respawn_delay_max", 4.0))
			c.body.global_transform = Transform3D(Basis(), Vector3(0, -500, 0))
			continue
		var en := layout.to_en(c.s, c.v)
		c.ray_in -= 1
		if c.ray_in <= 0 or c.y == 0.0:
			c.ray_in = 4
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


func active_count() -> int:
	var n := 0
	for c in cars:
		if c.active:
			n += 1
	return n


## Taxi stop: slow down towards the stop point while easing to the kerb, stand a few seconds,
## rejoin the lane only when no car is close behind. Returns the target speed.
func _taxi_target(c: Car, target: float, delta: float) -> float:
	var tx: Dictionary = cfg.get("taxi", {})
	var pull_v := float(tx.get("pull_v", 7.6)) * signf(c.lane_v)
	var to_stop := (c.taxi_stop_s - c.s) * c.dir
	match c.taxi:
		"":
			if c.taxi_will_stop and to_stop > 0.0 and to_stop < 25.0:
				c.taxi = "in"
		"in":
			c.v = lerpf(c.lane_v, pull_v, clampf(1.0 - to_stop / 12.0, 0.0, 1.0))
			target = minf(target, maxf(0.0, c.cruise * clampf(to_stop / 18.0, 0.0, 1.0)))
			if to_stop < 0.4:
				target = 0.0
				if c.speed < 0.2:
					c.taxi = "stop"
					var r: Array = tx.get("stop_seconds", [6.0, 11.0])
					c.stop_timer = _rng.randf_range(float(r[0]), float(r[1]))
		"stop":
			target = 0.0
			c.v = pull_v
			c.stop_timer -= delta
			if c.stop_timer <= 0.0 and _lane_clear_behind(c, 18.0) and _player_clear_ahead(c, 14.0):
				c.taxi = "out"
				c.taxi_stop_s = c.s
		"out":
			var gone := (c.s - c.taxi_stop_s) * c.dir
			c.v = lerpf(pull_v, c.lane_v, clampf(gone / 10.0, 0.0, 1.0))
			if gone >= 10.0:
				c.v = c.lane_v
				c.taxi = ""
				c.taxi_will_stop = false
	return target


## No player standing in the lane in front of a car that is about to pull out.
func _player_clear_ahead(c: Car, dist: float) -> bool:
	if player == null:
		return true
	var psv := _player_sv()
	var ahead := (psv.x - c.s) * c.dir
	return not (absf(psv.y - c.lane_v) < 2.2 and ahead > -1.0 and ahead < dist)


func _lane_clear_behind(c: Car, dist: float) -> bool:
	for o in cars:
		if o != c and o.active and o.lane == c.lane:
			var behind := (c.s - o.s) * c.dir
			if behind > 0.0 and behind < dist:
				return false
	return true


func _entry_clear(c: Car) -> bool:
	var entry: float = cfg.get("s_min", -80.0) if c.dir > 0 else cfg.get("s_max", 165.0)
	for o in cars:
		if o != c and o.active and o.lane == c.lane and absf(o.s - float(entry)) < float(cfg.get("safe_gap", 8.0)) * 2.0:
			return false
	return true
