## Procedural car model (R9 look, R9.2 performance): shared by parked cars (street_builder.gd) and
## moving traffic (traffic.gd). Generic hatchback/saloon proportions - no brand, no real model.
## Local frame: front at -Z, width along X, ground at y = 0.
##
## R9.2: the R9 version used ~27 MeshInstances per car (one per box/wheel). With ~40 cars that was
## ~1000 draw calls on the Ring - the main cost measured on the tablet. Now each car is ONE mesh
## with two surfaces (body parts coloured per vertex + emissive lights), cached and shared between
## identical cars. Moving traffic keeps four separate wheels so they can spin.
class_name StrayCarModel
extends RefCounted

static var _meshes: Dictionary = {}
static var _wheel_mesh: ArrayMesh
static var _body_mat: StandardMaterial3D
static var _light_mats: Dictionary = {}

const TRIM := Color(0.05, 0.05, 0.055)
const GLASS := Color(0.03, 0.04, 0.05)
const TYRE := Color(0.025, 0.025, 0.025)
const RIM := Color(0.45, 0.46, 0.48)
const PLATE := Color(0.85, 0.85, 0.82)
const HEAD := Color(1.0, 0.95, 0.85)
const TAIL := Color(0.75, 0.05, 0.03)


## Opaque body material: albedo from vertex colours (paint, trim, glass, tyres in one draw call).
static func body_material() -> StandardMaterial3D:
	if _body_mat == null:
		_body_mat = StandardMaterial3D.new()
		_body_mat.vertex_color_use_as_albedo = true
		_body_mat.vertex_color_is_srgb = true
		_body_mat.roughness = 0.35
	return _body_mat


static func _light_material(on: bool, energy: float) -> StandardMaterial3D:
	var k := "%s_%.2f" % [on, energy]
	if not _light_mats.has(k):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 0.35
		if on:
			m.emission_enabled = true
			m.emission = Color(1, 1, 1)
			m.emission_energy_multiplier = energy
			m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY  # emission tinted by albedo
		_light_mats[k] = m
	return _light_mats[k]


## Appends a primitive mesh, transformed and coloured, to a SurfaceTool.
static func _add(st: SurfaceTool, prim: PrimitiveMesh, xf: Transform3D, c: Color) -> void:
	var arr := prim.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for i in idx:
		st.set_color(c)
		st.set_normal((xf.basis * norms[i]).normalized())
		st.add_vertex(xf * verts[i])


static func _box(st: SurfaceTool, pos: Vector3, size: Vector3, c: Color) -> void:
	var b := BoxMesh.new()
	b.size = size
	_add(st, b, Transform3D(Basis(), pos), c)


static func _wheel(st: SurfaceTool, xf: Transform3D) -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.31
	cyl.bottom_radius = 0.31
	cyl.height = 0.21
	cyl.radial_segments = 14
	cyl.rings = 1
	_add(st, cyl, xf, TYRE)
	var hub := CylinderMesh.new()
	hub.top_radius = 0.18
	hub.bottom_radius = 0.18
	hub.height = 0.215
	hub.radial_segments = 10
	hub.rings = 1
	_add(st, hub, xf, RIM)


static func _wheel_positions(L: float, w: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for z in [-L * 0.31, L * 0.31]:
		for x in [-w * 0.45, w * 0.45]:
			out.append(Vector3(x, 0.31, z))
	return out


## Cached car mesh. `with_wheels` bakes the wheels in (parked cars).
static func car_mesh(length: float, width: float, paint: Color, lights_on: bool, with_wheels: bool,
		head_emission: float = 3.0, tail_emission: float = 2.5) -> ArrayMesh:
	var key := "%.2f_%.2f_%s_%s_%s_%.1f_%.1f" % [length, width, paint.to_html(), lights_on, with_wheels, head_emission, tail_emission]
	if _meshes.has(key):
		return _meshes[key]
	var L := length
	var w := width
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Body: lower hull, bonnet, boot, glasshouse, roof, B-pillar.
	_box(st, Vector3(0, 0.55, 0), Vector3(w, 0.5, L * 0.98), paint)
	_box(st, Vector3(0, 0.83, -L * 0.33), Vector3(w * 0.96, 0.08, L * 0.3), paint)
	_box(st, Vector3(0, 0.84, L * 0.36), Vector3(w * 0.96, 0.1, L * 0.24), paint)
	_box(st, Vector3(0, 1.08, L * 0.05), Vector3(w * 0.86, 0.42, L * 0.44), GLASS)
	_box(st, Vector3(0, 1.31, L * 0.06), Vector3(w * 0.84, 0.05, L * 0.38), paint)
	_box(st, Vector3(0, 1.08, L * 0.05), Vector3(w * 0.87, 0.06, L * 0.012), paint)
	# Bumpers, side skirts, mirrors, number plates.
	_box(st, Vector3(0, 0.38, -L * 0.495), Vector3(w * 1.01, 0.2, 0.08), TRIM)
	_box(st, Vector3(0, 0.38, L * 0.495), Vector3(w * 1.01, 0.2, 0.08), TRIM)
	for x in [-w * 0.5, w * 0.5]:
		_box(st, Vector3(x, 0.33, 0), Vector3(0.03, 0.08, L * 0.6), TRIM)
		_box(st, Vector3(x * 1.08, 0.98, -L * 0.18), Vector3(0.1, 0.08, 0.16), paint)
	_box(st, Vector3(0, 0.5, -L * 0.5 - 0.02), Vector3(0.52, 0.11, 0.02), TRIM)
	_box(st, Vector3(0, 0.5, L * 0.5 + 0.02), Vector3(0.52, 0.11, 0.02), PLATE)
	if with_wheels:
		for p in _wheel_positions(L, w):
			_wheel(st, Transform3D(Basis(Vector3.BACK, PI * 0.5), p))
	var mesh := st.commit()
	mesh.surface_set_material(0, body_material())
	# Lights: second surface (emissive when on; dark lenses on parked cars).
	var lt := SurfaceTool.new()
	lt.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in [-w * 0.35, w * 0.35]:
		_box(lt, Vector3(x, 0.66, -L * 0.5 - 0.01), Vector3(0.36, 0.12, 0.03), HEAD)
		_box(lt, Vector3(x, 0.72, L * 0.5 + 0.01), Vector3(0.34, 0.1, 0.03), TAIL)
	lt.commit(mesh)
	mesh.surface_set_material(1, _light_material(lights_on, head_emission))
	_meshes[key] = mesh
	return mesh


## One wheel (tyre + rim), shared by all moving cars.
static func wheel_mesh() -> ArrayMesh:
	if _wheel_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_wheel(st, Transform3D())
		_wheel_mesh = st.commit()
		_wheel_mesh.surface_set_material(0, body_material())
	return _wheel_mesh


## Builds the visual under `parent`. Parked cars (`lights_on` false): one MeshInstance incl.
## wheels. Moving cars: body MeshInstance + four spinning wheel instances (returned).
static func build(parent: Node3D, length: float, width: float, paint_color: Color, lights_on: bool,
		head_emission: float = 3.0, tail_emission: float = 2.5) -> Array[MeshInstance3D]:
	var wheels: Array[MeshInstance3D] = []
	var body := MeshInstance3D.new()
	body.name = "CarBody"
	body.mesh = car_mesh(length, width, paint_color, lights_on, not lights_on, head_emission, tail_emission)
	parent.add_child(body)
	if lights_on:
		for p in _wheel_positions(length, width):
			var wheel := MeshInstance3D.new()
			wheel.mesh = wheel_mesh()
			wheel.position = p
			wheel.rotation = Vector3(0, 0, PI * 0.5)
			parent.add_child(wheel)
			wheels.append(wheel)
	return wheels
