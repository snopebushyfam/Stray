## Procedural car model (R9 visual upgrade): shared by parked cars (street_builder.gd) and moving
## traffic (traffic.gd). Generic hatchback/saloon proportions built from boxes and cylinders -
## no brand, no real model. Local frame: front at -Z, width along X, ground at y = 0.
class_name StrayCarModel
extends RefCounted

static var _mats: Dictionary = {}


static func _mat(key: String, c: Color, rough: float, emissive: float = 0.0, metal: float = 0.0) -> StandardMaterial3D:
	var k := "%s_%s_%.2f" % [key, c.to_html(), emissive]
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		if emissive > 0.0:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = emissive
		_mats[k] = m
	return _mats[k]


static func _box(parent: Node3D, pos: Vector3, size: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


## Builds the visual under `parent`. Returns the four wheel nodes (traffic spins them).
## `lights_on`: headlights/taillights glow (moving traffic); parked cars only show dark lenses.
static func build(parent: Node3D, length: float, width: float, paint_color: Color, lights_on: bool,
		head_emission: float = 3.0, tail_emission: float = 2.5) -> Array[MeshInstance3D]:
	var L := length
	var w := width
	# Low metallic: the Compatibility renderer has no sky reflections, metal paint would read black.
	var paint := _mat("paint", paint_color, 0.28, 0.0, 0.1)
	parent.set_meta("paint", paint)  # traffic.gd repaints police cars by this material
	var trim := _mat("trim", Color(0.05, 0.05, 0.055), 0.6)
	var glass := _mat("glass", Color(0.03, 0.04, 0.05), 0.3)
	var tyre := _mat("tyre", Color(0.025, 0.025, 0.025), 0.9)
	var rim := _mat("rim", Color(0.45, 0.46, 0.48), 0.35, 0.0, 0.4)
	# Body: lower hull, bonnet slightly lower than the boot line, cabin set back with glass sides.
	_box(parent, Vector3(0, 0.55, 0), Vector3(w, 0.5, L * 0.98), paint)
	_box(parent, Vector3(0, 0.83, -L * 0.33), Vector3(w * 0.96, 0.08, L * 0.3), paint)          # bonnet
	_box(parent, Vector3(0, 0.84, L * 0.36), Vector3(w * 0.96, 0.1, L * 0.24), paint)           # boot
	_box(parent, Vector3(0, 1.08, L * 0.05), Vector3(w * 0.86, 0.42, L * 0.44), glass)          # glasshouse
	_box(parent, Vector3(0, 1.31, L * 0.06), Vector3(w * 0.84, 0.05, L * 0.38), paint)          # roof
	_box(parent, Vector3(0, 1.08, L * 0.05), Vector3(w * 0.87, 0.06, L * 0.012), paint)         # B-pillar
	# Bumpers, side skirts, mirrors.
	_box(parent, Vector3(0, 0.38, -L * 0.495), Vector3(w * 1.01, 0.2, 0.08), trim)
	_box(parent, Vector3(0, 0.38, L * 0.495), Vector3(w * 1.01, 0.2, 0.08), trim)
	for x in [-w * 0.5, w * 0.5]:
		_box(parent, Vector3(x, 0.33, 0), Vector3(0.03, 0.08, L * 0.6), trim)
		_box(parent, Vector3(x * 1.08, 0.98, -L * 0.18), Vector3(0.1, 0.08, 0.16), paint)
	# Lights: headlights white, taillights red; parked cars show dark lenses.
	var head := _mat("head", Color(1.0, 0.95, 0.85), 0.35, head_emission if lights_on else 0.0)
	var tail := _mat("tail", Color(0.75, 0.05, 0.03), 0.3, tail_emission if lights_on else 0.0)
	for x in [-w * 0.35, w * 0.35]:
		_box(parent, Vector3(x, 0.66, -L * 0.5 - 0.01), Vector3(0.36, 0.12, 0.03), head)
		_box(parent, Vector3(x, 0.72, L * 0.5 + 0.01), Vector3(0.34, 0.1, 0.03), tail)
	_box(parent, Vector3(0, 0.5, -L * 0.5 - 0.02), Vector3(0.52, 0.11, 0.02), trim)             # number plate area
	_box(parent, Vector3(0, 0.5, L * 0.5 + 0.02), Vector3(0.52, 0.11, 0.02), _mat("plate", Color(0.85, 0.85, 0.82), 0.5))
	var wheels: Array[MeshInstance3D] = []
	for z in [-L * 0.31, L * 0.31]:
		for x in [-w * 0.45, w * 0.45]:
			var wheel := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.31
			cyl.bottom_radius = 0.31
			cyl.height = 0.21
			cyl.radial_segments = 14
			wheel.mesh = cyl
			wheel.material_override = tyre
			wheel.position = Vector3(x, 0.31, z)
			wheel.rotation = Vector3(0, 0, PI * 0.5)
			parent.add_child(wheel)
			var hub := MeshInstance3D.new()
			var hc := CylinderMesh.new()
			hc.top_radius = 0.18
			hc.bottom_radius = 0.18
			hc.height = 0.215
			hc.radial_segments = 10
			hub.mesh = hc
			hub.material_override = rim
			wheel.add_child(hub)
			wheels.append(wheel)
	return wheels
