## NACHTFLUG interior (Prototype 001): enclosed room with dance floor, bar, DJ, dancers, Lea.
##
## Built procedurally at `origin` (below the street, out of sight). StrayInteractions moves the
## player in after the bouncer admits them and out through the exit door. Config:
## data/p001/club_interior.json. Design: docs/STRAY_GDD.md (NIGHTLIFE).
class_name StrayClubInterior
extends Node3D

var cfg: Dictionary = {}
var origin := Vector3.ZERO
## Interaction points in world space: "bar", "lea", "exit".
var points: Dictionary = {}
var dancers: Array[Node3D] = []
var music: AudioStreamPlayer
var _tiles: Array[StandardMaterial3D] = []
var _spinners: Array[Dictionary] = []
var _time := 0.0
var _rng := RandomNumberGenerator.new()


func setup(p_cfg: Dictionary, character_cfg: Dictionary) -> void:
	cfg = p_cfg
	var o: Array = cfg.get("origin", [0, -60, 0])
	origin = Vector3(o[0], o[1], o[2])
	position = origin
	_rng.seed = int(cfg.get("dancers", {}).get("seed", 1))
	_build_room()
	_build_dance_floor()
	_build_bar()
	_build_dj(character_cfg)
	_build_lights()
	_build_dancers(character_cfg)
	_build_bartender(character_cfg)
	_build_lea(character_cfg)
	var ex: Array = cfg.get("exit", {}).get("center", [0, 6.6])
	points["exit"] = to_global(Vector3(ex[0], 0.0, ex[1] - 0.8))
	music = AudioStreamPlayer.new()
	music.name = "ClubMusic"
	var st: AudioStream = load(cfg.get("audio", {}).get("stream", "")) if ResourceLoader.exists(cfg.get("audio", {}).get("stream", "")) else null
	if st is AudioStreamWAV:
		var w := st as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = int(w.get_length() * w.mix_rate)
	music.stream = st
	music.volume_db = cfg.get("audio", {}).get("volume_db", -4.0)
	add_child(music)
	print("STRAY_DIAG club_interior origin=%s dancers=%d lights=%d" % [origin, dancers.size(), _spinners.size()])


func _mat(c: Color, rough: float = 0.8, emission: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	return m


func _box(pos: Vector3, size: Vector3, m: Material, collide: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
		body.position = pos
		add_child(body)
	return mi


func _build_room() -> void:
	var r: Dictionary = cfg.get("room", {})
	var w: float = r.get("width", 18.0)
	var d: float = r.get("depth", 14.0)
	var h: float = r.get("height", 5.0)
	var wc: Array = cfg.get("wall_color", [0.09, 0.07, 0.12])
	var wall := _mat(Color(wc[0], wc[1], wc[2]), 0.9)
	_box(Vector3(0, -0.25, 0), Vector3(w, 0.5, d), _mat(Color(0.05, 0.05, 0.06), 0.4))   # floor
	_box(Vector3(0, h + 0.25, 0), Vector3(w, 0.5, d), wall)                              # ceiling
	_box(Vector3(-w * 0.5 - 0.25, h * 0.5, 0), Vector3(0.5, h, d), wall)
	_box(Vector3(w * 0.5 + 0.25, h * 0.5, 0), Vector3(0.5, h, d), wall)
	_box(Vector3(0, h * 0.5, -d * 0.5 - 0.25), Vector3(w, h, 0.5), wall)
	_box(Vector3(0, h * 0.5, d * 0.5 + 0.25), Vector3(w, h, 0.5), wall)
	# Exit door with a green emergency sign (as required in real clubs).
	var ex: Array = cfg.get("exit", {}).get("center", [0, 6.6])
	_box(Vector3(ex[0], 1.2, d * 0.5 - 0.02), Vector3(1.6, 2.4, 0.06), _mat(Color(0.08, 0.08, 0.09), 0.5), false)
	_box(Vector3(ex[0], 2.75, d * 0.5 - 0.05), Vector3(0.9, 0.3, 0.04), _mat(Color(0.1, 0.9, 0.35), 0.5, 3.0), false)
	# LED strips along the side walls just under the ceiling.
	var lc: Array = cfg.get("led_strip_color", [1.0, 0.15, 0.65])
	var led := _mat(Color(lc[0], lc[1], lc[2]), 0.5, 3.0)
	_box(Vector3(-w * 0.5 + 0.03, h - 0.4, 0), Vector3(0.04, 0.06, d - 0.6), led, false)
	_box(Vector3(w * 0.5 - 0.03, h - 0.4, 0), Vector3(0.04, 0.06, d - 0.6), led, false)
	_box(Vector3(0, h - 0.4, -d * 0.5 + 0.03), Vector3(w - 0.6, 0.06, 0.04), led, false)
	var amb := OmniLight3D.new()
	amb.light_color = Color(0.5, 0.3, 0.9)
	amb.light_energy = float(cfg.get("ambient_energy", 1.6))
	amb.omni_range = 16.0
	amb.position = Vector3(0, h - 0.5, 0)
	add_child(amb)


func _build_dance_floor() -> void:
	var df: Dictionary = cfg.get("dance_floor", {})
	var c: Array = df.get("center", [0, 1])
	var s: Array = df.get("size", [8, 6])
	var n: int = df.get("tiles", 6)
	var tw: float = float(s[0]) / n
	var td: float = float(s[1]) / n
	for i in n:
		for j in n:
			var m := _mat(Color(0.2, 0.0, 0.3), 0.3, float(df.get("emission", 2.0)))
			_tiles.append(m)
			_box(Vector3(float(c[0]) - float(s[0]) * 0.5 + tw * (i + 0.5), 0.01, float(c[1]) - float(s[1]) * 0.5 + td * (j + 0.5)),
				Vector3(tw * 0.94, 0.04, td * 0.94), m, false)


func _build_bar() -> void:
	var b: Dictionary = cfg.get("bar", {})
	var c: Array = b.get("center", [-6.6, -5.2])
	var length: float = b.get("length", 6.0)
	_box(Vector3(c[0], float(b.get("height", 1.1)) * 0.5, c[1]), Vector3(length, b.get("height", 1.1), b.get("depth", 0.9)), _mat(Color(0.12, 0.07, 0.05), 0.35))
	_box(Vector3(c[0], float(b.get("height", 1.1)) + 0.03, c[1]), Vector3(length + 0.1, 0.06, float(b.get("depth", 0.9)) + 0.1), _mat(Color(0.75, 0.75, 0.78), 0.15), false)
	# Back shelf with glowing bottles.
	_box(Vector3(c[0], 1.6, float(c[1]) - 1.4), Vector3(length, 1.6, 0.3), _mat(Color(0.05, 0.03, 0.03), 0.6))
	for k in 14:
		var col := Color.from_hsv(_rng.randf(), 0.6, 1.0)
		_box(Vector3(float(c[0]) - length * 0.45 + k * length * 0.9 / 13.0, 1.75 + (k % 2) * 0.45, float(c[1]) - 1.2), Vector3(0.12, 0.35, 0.12), _mat(col, 0.1, 1.2), false)
	# Customer side of the counter.
	points["bar"] = to_global(Vector3(c[0], 0.0, float(c[1]) + 1.2))
	var bar_light := OmniLight3D.new()
	bar_light.light_color = Color(1.0, 0.7, 0.4)
	bar_light.light_energy = 1.4
	bar_light.omni_range = 5.0
	bar_light.position = Vector3(c[0], 2.6, float(c[1]) - 0.3)
	add_child(bar_light)


## `look`: character_looks.json id (R10); `color` is only used without the look shader.
func _character(character_cfg: Dictionary, color: Color, anim: String, pos: Vector3, yaw: float, scale_f: float = 1.0, look: String = "") -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	add_child(root)
	if not ResourceLoader.exists(character_cfg.get("scene", "")):
		return root
	var model: Node3D = load(character_cfg["scene"]).instantiate()
	model.rotation.y = deg_to_rad(character_cfg.get("yaw_offset_deg", 180.0))
	model.scale = Vector3.ONE * scale_f
	if look.is_empty() or not StrayCharacterLook.apply(model, look):
		var m := _mat(color, 0.7)
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			for i in (mi as MeshInstance3D).mesh.get_surface_count():
				(mi as MeshInstance3D).set_surface_override_material(i, m)
	root.add_child(model)
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		var ap: AnimationPlayer = aps[0]
		ap.play(anim if ap.has_animation(anim) else "Idle")
		ap.seek(_rng.randf() * ap.current_animation_length, true)
		ap.speed_scale = _rng.randf_range(0.9, 1.1)
	var body := StaticBody3D.new()
	body.collision_layer = 4
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	body.add_child(cs)
	root.add_child(body)
	return root


func _build_dj(character_cfg: Dictionary) -> void:
	var c: Array = cfg.get("dj", {}).get("center", [6.8, 1.0])
	_box(Vector3(c[0], 0.55, c[1]), Vector3(1.0, 1.1, 2.4), _mat(Color(0.04, 0.04, 0.05), 0.4))
	_box(Vector3(float(c[0]) - 0.52, 0.8, c[1]), Vector3(0.04, 0.5, 2.2), _mat(Color(0.1, 0.3, 1.0), 0.5, 2.5), false)
	_character(character_cfg, Color(0.1, 0.1, 0.12), "Dance", Vector3(float(c[0]) + 0.9, 0.0, c[1]), -PI * 0.5, 1.0, "club_black_shirt")


func _build_lights() -> void:
	for l in cfg.get("lights", []):
		var spot := SpotLight3D.new()
		spot.light_color = Color(l["color"][0], l["color"][1], l["color"][2])
		spot.light_energy = cfg.get("light_energy", 7.0)
		spot.spot_range = 12.0
		spot.spot_angle = 28.0
		spot.position = Vector3(l["pos"][0], l["pos"][1], l["pos"][2])
		spot.rotation_degrees = Vector3(-62, _rng.randf_range(0, 360), 0)
		add_child(spot)
		_spinners.append({"light": spot, "speed": float(l.get("spin_deg_s", 0.0))})


func _build_dancers(character_cfg: Dictionary) -> void:
	var dc: Dictionary = cfg.get("dancers", {})
	var df: Dictionary = cfg.get("dance_floor", {})
	var c: Array = df.get("center", [0, 1])
	var s: Array = df.get("size", [8, 6])
	var anims: Array = dc.get("anims", ["Dance"])
	var placed: Array[Vector2] = []
	var tries := 0
	while dancers.size() < int(dc.get("count", 10)) and tries < 400:
		tries += 1
		var p := Vector2(float(c[0]) + _rng.randf_range(-0.45, 0.45) * float(s[0]), float(c[1]) + _rng.randf_range(-0.45, 0.45) * float(s[1]))
		var ok := true
		for q in placed:
			if q.distance_to(p) < 1.1:
				ok = false
				break
		if not ok:
			continue
		placed.append(p)
		var col := Color.from_hsv(_rng.randf(), 0.55, _rng.randf_range(0.3, 0.8))
		var club_looks := StrayCharacterLook.group("club")
		dancers.append(_character(character_cfg, col, anims[_rng.randi() % anims.size()], Vector3(p.x, 0.0, p.y),
			_rng.randf_range(0, TAU), _rng.randf_range(0.93, 1.06), String(club_looks[dancers.size() % club_looks.size()]) if not club_looks.is_empty() else ""))


func _build_bartender(character_cfg: Dictionary) -> void:
	var st: Array = cfg.get("bartender", {}).get("stand", [-6.6, -6.2])
	_character(character_cfg, Color(0.08, 0.08, 0.09), "Idle", Vector3(st[0], 0.0, st[1]), PI, 1.0, "bartender")  # faces the guests (+Z)


func _build_lea(character_cfg: Dictionary) -> void:
	var lea: Dictionary = cfg.get("lea", {})
	var st: Array = lea.get("stand", [-3.6, -5.0])
	# Lea leans at the end of the bar, facing the room.
	_character(character_cfg, Color(0.55, 0.12, 0.2), "Idle_Talking", Vector3(st[0], 0.0, st[1]), PI, 0.97, "lea")  # faces the room (+Z)
	points["lea"] = to_global(Vector3(float(st[0]), 0.0, float(st[1]) + 1.1))


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	var bpm: float = cfg.get("dance_floor", {}).get("beat_bpm", 124.0)
	var beat := int(_time * bpm / 60.0)
	for i in _tiles.size():
		var h := fmod(float((i * 7 + beat * 3) % 23) / 23.0 + 0.8, 1.0)
		_tiles[i].albedo_color = Color.from_hsv(h, 0.85, 0.55 if (i + beat) % 3 else 0.12)
		_tiles[i].emission = _tiles[i].albedo_color
	for sp in _spinners:
		(sp.light as SpotLight3D).rotation_degrees.y += float(sp.speed) * delta
