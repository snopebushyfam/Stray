## The player's flat (Prototype 001, GDD: Wohnung). Small enclosed room built at `origin`
## (below the street, hidden until entered): bed, desk with lamp, wardrobe, window with a
## night-city backdrop, door. Points: "bed", "exit". Config: data/p001/home_config.json.
class_name StrayHome
extends Node3D

var cfg: Dictionary = {}
var points: Dictionary = {}


func setup(p_cfg: Dictionary) -> void:
	cfg = p_cfg
	var o: Array = cfg.get("origin", [40, -100, 0])
	position = Vector3(o[0], o[1], o[2])
	var r: Dictionary = cfg.get("room", {})
	var w: float = r.get("width", 5.0)
	var d: float = r.get("depth", 6.0)
	var h: float = r.get("height", 2.8)
	var wall := _mat(Color(0.62, 0.6, 0.56), 0.9)
	_box(Vector3(0, -0.1, 0), Vector3(w, 0.2, d), _mat(Color(0.32, 0.22, 0.14), 0.6))   # wooden floor
	_box(Vector3(0, h + 0.1, 0), Vector3(w, 0.2, d), wall)
	_box(Vector3(-w * 0.5 - 0.1, h * 0.5, 0), Vector3(0.2, h, d), wall)
	_box(Vector3(w * 0.5 + 0.1, h * 0.5, 0), Vector3(0.2, h, d), wall)
	_box(Vector3(0, h * 0.5, -d * 0.5 - 0.1), Vector3(w, h, 0.2), wall)
	_box(Vector3(0, h * 0.5, d * 0.5 + 0.1), Vector3(w, h, 0.2), wall)
	# Window in the back wall: dark blue glass with a few lit "windows across the street".
	_box(Vector3(0.6, 1.5, -d * 0.5 + 0.02), Vector3(1.6, 1.3, 0.04), _mat(Color(0.03, 0.05, 0.12), 0.1, 0.6), false)
	for i in 7:
		_box(Vector3(0.0 + (i % 4) * 0.35, 1.2 + (i / 4) * 0.45, -d * 0.5 + 0.05), Vector3(0.12, 0.16, 0.01), _mat(Color(1.0, 0.75, 0.4), 0.5, 1.5), false)
	# Bed (back left), desk + lamp (right), wardrobe (left front), rug.
	_box(Vector3(-1.4, 0.25, -1.7), Vector3(1.5, 0.5, 2.1), _mat(Color(0.25, 0.25, 0.3), 0.8))
	_box(Vector3(-1.4, 0.55, -1.0), Vector3(1.4, 0.12, 0.7), _mat(Color(0.75, 0.75, 0.78), 0.9), false)    # pillow end
	_box(Vector3(-1.4, 0.53, -2.0), Vector3(1.45, 0.08, 1.4), _mat(Color(0.2, 0.3, 0.45), 0.9), false)     # blanket
	_box(Vector3(1.7, 0.75, -1.0), Vector3(1.0, 0.06, 1.6), _mat(Color(0.45, 0.32, 0.2), 0.6))
	_box(Vector3(1.7, 0.37, -1.0), Vector3(0.9, 0.74, 1.5), _mat(Color(0.3, 0.2, 0.12), 0.7), false)
	_box(Vector3(1.85, 1.05, -1.5), Vector3(0.12, 0.5, 0.12), _mat(Color(1.0, 0.85, 0.6), 0.5, 2.0), false)
	_box(Vector3(-1.9, 1.0, 1.6), Vector3(0.6, 2.0, 1.2), _mat(Color(0.5, 0.45, 0.4), 0.7))
	_box(Vector3(0, 0.01, 0.3), Vector3(2.2, 0.02, 1.6), _mat(Color(0.45, 0.12, 0.12), 0.95), false)
	# Door (front wall).
	_box(Vector3(0.8, 1.05, d * 0.5 - 0.02), Vector3(0.95, 2.1, 0.05), _mat(Color(0.35, 0.25, 0.15), 0.6), false)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.82, 0.6)
	lamp.light_energy = 1.6
	lamp.omni_range = 7.0
	lamp.position = Vector3(1.6, 1.6, -1.2)
	add_child(lamp)
	var ceiling := OmniLight3D.new()
	ceiling.light_color = Color(1.0, 0.9, 0.8)
	ceiling.light_energy = 0.8
	ceiling.omni_range = 6.0
	ceiling.position = Vector3(0, h - 0.3, 0)
	add_child(ceiling)
	points["bed"] = to_global(Vector3(-1.4, 0.0, -0.1))
	points["exit"] = to_global(Vector3(0.8, 0.0, d * 0.5 - 0.7))
	print("STRAY_DIAG home origin=%s" % position)


func _mat(c: Color, rough: float = 0.8, emission: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	return m


func _box(pos: Vector3, size: Vector3, m: Material, collide: bool = true) -> void:
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
