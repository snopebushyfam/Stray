## U-Bahn platform interior (Roadmap R5): one generic underground station reused for every stop;
## the name signs change with the station. Built at `station_origin` (deep below the city,
## hidden until entered). Points: "ticket" (machine), "board" (train door), "exit" (stairs up).
## Config: data/p002/transit_config.json. Geometry is generic, NOT a model of the real stations.
class_name StrayMetroStation
extends Node3D

const LENGTH := 44.0
const PLATFORM_W := 6.0
const PIT_W := 4.6
const HEIGHT := 4.4

var cfg: Dictionary = {}
var points: Dictionary = {}
var train: Node3D
var _name_labels: Array[Label3D] = []


func setup(p_cfg: Dictionary) -> void:
	cfg = p_cfg
	var o: Array = cfg.get("station_origin", [-70.0, -100.0, 0.0])
	position = Vector3(o[0], o[1], o[2])
	var tile := _mat(Color(0.78, 0.74, 0.62), 0.6)
	var floor_m := _mat(Color(0.42, 0.41, 0.4), 0.8)
	var dark := _mat(Color(0.08, 0.08, 0.09), 0.9)
	var hl := LENGTH * 0.5
	# Platform (z 0..W), track pit (z -PIT_W..0, 1.1 m lower), tunnel wall behind the tracks.
	_box(Vector3(0, -0.1, PLATFORM_W * 0.5), Vector3(LENGTH, 0.2, PLATFORM_W), floor_m)
	_box(Vector3(0, -1.2, -PIT_W * 0.5), Vector3(LENGTH, 0.2, PIT_W), dark)
	_box(Vector3(0, -0.55, -0.05), Vector3(LENGTH, 1.1, 0.1), floor_m)
	_box(Vector3(0, 0.005, 0.25), Vector3(LENGTH, 0.01, 0.12), _mat(Color(0.95, 0.85, 0.1), 0.5, 0.4), false)  # safety line
	_box(Vector3(0, HEIGHT * 0.5 - 1.2, -PIT_W - 0.1), Vector3(LENGTH, HEIGHT + 1.2, 0.2), tile)
	_box(Vector3(0, HEIGHT * 0.5, PLATFORM_W + 0.1), Vector3(LENGTH, HEIGHT, 0.2), tile)
	_box(Vector3(0, HEIGHT + 0.1, (PLATFORM_W - PIT_W) * 0.5), Vector3(LENGTH, 0.2, PLATFORM_W + PIT_W), _mat(Color(0.3, 0.3, 0.32), 0.8))
	for sx in [-1.0, 1.0]:
		_box(Vector3(sx * (hl + 0.1), HEIGHT * 0.5 - 0.6, (PLATFORM_W - PIT_W) * 0.5), Vector3(0.2, HEIGHT + 1.2, PLATFORM_W + PIT_W), dark)
	# Invisible edge barrier: nobody falls onto the tracks in the rough build.
	var edge := StaticBody3D.new()
	var ecs := CollisionShape3D.new()
	var esh := BoxShape3D.new()
	esh.size = Vector3(LENGTH, 2.0, 0.1)
	ecs.shape = esh
	edge.add_child(ecs)
	edge.position = Vector3(0, 1.0, -0.05)
	add_child(edge)
	# Pillars, ceiling light strips, a few omni lights.
	for i in range(-2, 3):
		_box(Vector3(i * 8.0, HEIGHT * 0.5, PLATFORM_W * 0.55), Vector3(0.5, HEIGHT, 0.5), _mat(Color(0.15, 0.3, 0.55), 0.5))
		_box(Vector3(i * 8.0 + 4.0, HEIGHT - 0.02, 1.5), Vector3(3.0, 0.04, 0.25), _mat(Color(0.9, 0.95, 1.0), 0.5, 3.0), false)
	for x in [-14.0, 0.0, 14.0]:
		var l := OmniLight3D.new()
		l.light_color = Color(0.9, 0.95, 1.0)
		l.light_energy = 1.4
		l.omni_range = 14.0
		l.position = Vector3(x, HEIGHT - 0.6, 1.5)
		add_child(l)
	# Station name signs: back wall and tunnel wall (updated by set_station()).
	for z_face in [[PLATFORM_W - 0.01, PI], [-PIT_W + 0.01, 0.0]]:
		for x in [-10.0, 10.0]:
			_box(Vector3(x, 2.6, z_face[0] + (-0.02 if z_face[1] == PI else 0.02)), Vector3(3.6, 0.6, 0.02), _mat(Color(0.05, 0.25, 0.65), 0.5, 0.8), false)
			var lab := Label3D.new()
			lab.font_size = 96
			lab.pixel_size = 0.005
			lab.modulate = Color(1, 1, 1)
			lab.outline_size = 0
			lab.shaded = false
			lab.double_sided = false
			lab.position = Vector3(x, 2.6, z_face[0] + (-0.05 if z_face[1] == PI else 0.05))
			lab.rotation.y = z_face[1]
			add_child(lab)
			_name_labels.append(lab)
	# Ticket machine (left), stairs up (right end), train in the pit.
	_box(Vector3(-8.0, 0.9, PLATFORM_W - 0.45), Vector3(0.9, 1.8, 0.6), _mat(Color(0.55, 0.56, 0.6), 0.4))
	_box(Vector3(-8.0, 1.25, PLATFORM_W - 0.77), Vector3(0.5, 0.35, 0.02), _mat(Color(0.3, 0.6, 0.9), 0.3, 1.5), false)
	for i in 8:
		_box(Vector3(hl - 3.0 + 0.0, 0.15 + i * 0.3, PLATFORM_W - 2.2 - i * 0.0), Vector3(3.0, 0.3, 0.1), floor_m, false)
		_box(Vector3(hl - 3.0, 0.15 + i * 0.3 + 0.15, PLATFORM_W - 1.5 + i * 0.28), Vector3(3.0, 0.3 + i * 0.3, 0.28), floor_m, false)
	var arrow := Label3D.new()
	arrow.text = "↑ Ausgang"
	arrow.font_size = 64
	arrow.pixel_size = 0.005
	arrow.shaded = false
	arrow.position = Vector3(hl - 3.0, 3.4, PLATFORM_W - 2.4)
	arrow.rotation.y = PI
	add_child(arrow)
	_build_train()
	points["ticket"] = to_global(Vector3(-8.0, 0.0, PLATFORM_W - 1.4))
	points["board"] = to_global(Vector3(0.0, 0.0, 1.0))
	points["exit"] = to_global(Vector3(hl - 3.0, 0.0, PLATFORM_W - 3.2))
	points["arrive"] = to_global(Vector3(0.0, 0.0, 2.2))
	print("STRAY_DIAG metro origin=%s" % position)


## Updates every name sign on the platform.
func set_station(display_name: String) -> void:
	for l in _name_labels:
		l.text = display_name


## Train (generic light Stadtbahn car, two units) standing in the pit.
func _build_train() -> void:
	train = Node3D.new()
	train.name = "Train"
	add_child(train)
	var body := _mat(Color(0.88, 0.88, 0.86), 0.4)
	var red := _mat(Color(0.75, 0.1, 0.1), 0.4)
	var glass := _mat(Color(0.25, 0.3, 0.35), 0.1, 0.4)
	for u in [-8.0, 8.0]:
		_box(Vector3(u, 0.6, -PIT_W * 0.5), Vector3(15.6, 3.2, 2.6), body, true, train)
		_box(Vector3(u, -0.45, -PIT_W * 0.5 + 1.31), Vector3(15.6, 0.3, 0.02), red, false, train)
		for w in range(-3, 4):
			_box(Vector3(u + w * 2.0, 1.15, -PIT_W * 0.5 + 1.31), Vector3(1.4, 0.9, 0.02), glass, false, train)
	var door := _mat(Color(0.95, 0.75, 0.2), 0.4, 0.3)
	_box(Vector3(0.0, 0.3, -PIT_W * 0.5 + 1.32), Vector3(1.3, 2.0, 0.02), door, false, train)
	var line := Label3D.new()
	line.text = "5"
	line.font_size = 96
	line.pixel_size = 0.005
	line.shaded = false
	line.position = Vector3(-14.0, 1.85, -PIT_W * 0.5 + 1.33)
	train.add_child(line)


func _mat(c: Color, rough: float = 0.8, emission: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	return m


func _box(pos: Vector3, size: Vector3, m: Material, collide: bool = true, parent: Node3D = self) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	if collide:
		var b := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		b.add_child(cs)
		b.position = pos
		parent.add_child(b)
