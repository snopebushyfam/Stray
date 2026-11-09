## Area P002 "Bahnhofsvorplatz / Domplatte": builds the Köln Hbf surroundings from data at runtime.
##
## Data: res://data/p002/P002_Area.json (+ LoD2 OBJ). Render tuning is shared with P001
## (godot_render.json via the street builder). Real: LoD2 buildings (Hbf, Dom ...), DGM1 ground,
## OSM lamps / bins / U-Bahn entrance. Procedural: fill-in lamps (marked in the data). The area is
## hidden while the player is in P001 (and vice versa), which keeps the light count low.
class_name StrayAreaBuilder
extends Node3D

const CHUNK := 20  # terrain chunk size in grid cells: keeps each mesh under the light limit

var area: StrayAreaLayout
var street: StrayStreetBuilder
var stats: Dictionary = {}
var _lamp_lights: Array[SpotLight3D] = []
var _mats: Dictionary = {}


## Builds everything. `street` provides the shared materials / render config.
func build(p_street: StrayStreetBuilder, area_path: String = "res://data/p002/P002_Area.json") -> Dictionary:
	street = p_street
	stats = {"area": false, "buildings": 0, "lod2_triangles": 0, "terrain_chunks": 0, "lights": 0, "error": ""}
	area = StrayAreaLayout.load_file(area_path)
	if area == null:
		stats.error = "area missing"
		print("STRAY_DIAG area_build=failed")
		return stats
	stats.area = true
	_build_terrain()
	_build_buildings()
	_build_bounds()
	_build_lamps()
	_build_bins()
	_build_ubahn_sign()
	_build_hbf_sign()
	print("STRAY_DIAG area_build=ok buildings=%d lod2_tris=%d terrain_chunks=%d lights=%d" % [
		stats.buildings, stats.lod2_triangles, stats.terrain_chunks, stats.lights])
	return stats


## Lamps follow the day/night preset of the shared render config.
func set_day_mode(day: bool) -> void:
	var lamps_on: bool = street.render.get("day" if day else "night", {}).get("street_lamps_on", true)
	for l in _lamp_lights:
		l.visible = lamps_on


func _surface(c: Color, rough: float = 0.85) -> StandardMaterial3D:
	var key := "%s_%.2f" % [c.to_html(), rough]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		_mats[key] = m
	return _mats[key]


func _emissive(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _gp(p_en: Vector2, up: float) -> Vector3:
	return StrayStreetLayout.en_to_godot(p_en.x, p_en.y, up)


func _box(xf: Transform3D, size: Vector3, mat: Material, collide: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.transform = xf
	add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
		body.transform = xf
		add_child(body)
	return mi


## Paving material: the P001 street shader in "slabs" mode, aligned to the Hbf front.
func _paving() -> Material:
	var shader: Shader = load(street.render.get("street_shader", "")) if street.render.has("street_shader") else null
	var col := StrayStreetBuilder._col(street.render.get("colors", {}).get("paving", [0.24, 0.23, 0.22]))
	if shader == null:
		return _surface(col, 0.9)
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("surface_kind", 1)
	m.set_shader_parameter("base_color", col)
	var n := StrayStreetLayout._v2(area.hbf_main_exit.get("normal_en", [0, 1]))
	var ax := StrayStreetLayout.en_dir_to_godot(Vector2(n.y, -n.x))
	m.set_shader_parameter("street_axis", Vector2(ax.x, ax.z))
	m.set_shader_parameter("slab_size", Vector2(0.6, 0.6))
	return m


# --- Ground ------------------------------------------------------------------------------------

func _build_terrain() -> void:
	var mat := _paving()
	for cj in range(0, area.ny - 1, CHUNK):
		for ci in range(0, area.nx - 1, CHUNK):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for j in range(cj, mini(cj + CHUNK, area.ny - 1)):
				for i in range(ci, mini(ci + CHUNK, area.nx - 1)):
					var a := _vert(i, j)
					var b := _vert(i + 1, j)
					var c := _vert(i + 1, j + 1)
					var d := _vert(i, j + 1)
					# Godot front faces are clockwise seen from the front (above).
					for v in [a, c, b, a, d, c]:
						st.add_vertex(v)
			st.generate_normals()
			var mi := MeshInstance3D.new()
			mi.name = "Ground_%d_%d" % [ci, cj]
			mi.mesh = st.commit()
			mi.material_override = mat
			add_child(mi)
			stats.terrain_chunks += 1
	# Collision: one height map over the whole grid (cell size 1 m = grid step; scaled otherwise).
	var hm := HeightMapShape3D.new()
	hm.map_width = area.nx
	hm.map_depth = area.ny
	var data := PackedFloat32Array()
	data.resize(area.nx * area.ny)
	for k in area.ny:
		for i in area.nx:
			data[k * area.nx + i] = area.z_at(i, area.ny - 1 - k)  # depth runs north -> south (+Z)
	hm.map_data = data
	var body := StaticBody3D.new()
	body.name = "GroundCollision"
	var cs := CollisionShape3D.new()
	cs.shape = hm
	cs.scale = Vector3(area.grid_step, 1.0, area.grid_step)
	body.add_child(cs)
	var centre := area.grid_min + Vector2(area.nx - 1, area.ny - 1) * area.grid_step * 0.5
	body.position = Vector3(centre.x, 0.0, -centre.y)
	add_child(body)


func _vert(i: int, j: int) -> Vector3:
	var p := area.grid_min + Vector2(i, j) * area.grid_step
	return _gp(p, area.z_at(i, j))


func _build_buildings() -> void:
	var m := StrayObjMesh.load_file(area.resolve(area.lod2_mesh))
	if m == null:
		stats.error = "LoD2 mesh missing"
		return
	var mats := {
		"M_LoD2_wall": street.facade_material(),
		"M_LoD2_roof": _surface(StrayStreetBuilder._col(street.render.get("colors", {}).get("roof", [0.3, 0.27, 0.26])), 0.8),
		"M_LoD2_ground": _surface(Color(0.3, 0.3, 0.3), 0.95),
	}
	# The Dom (by far the tallest building) gets dark sandstone instead of the window-grid facade.
	var stone := _surface(Color(0.2, 0.19, 0.17), 0.95)
	var holder := Node3D.new()
	holder.name = "Lod2Buildings"
	add_child(holder)
	for o in m.objects:
		var mi := MeshInstance3D.new()
		mi.name = o.name
		var aabb := AABB()
		mi.mesh = StrayObjMesh.build_mesh(o, mats, mats["M_LoD2_wall"], StrayObjMesh.building_params(o))
		aabb = mi.mesh.get_aabb()
		if aabb.size.y > 80.0:
			for s in mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, stone)
		holder.add_child(mi)
	var body := StaticBody3D.new()
	body.name = "Lod2Collision"
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(m.collision_faces())
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	stats.buildings = m.objects.size()
	stats.lod2_triangles = m.triangle_count


## Invisible walls along the walkable rectangle (the grid edge minus the margin).
func _build_bounds() -> void:
	var lo := area.grid_min + Vector2.ONE * area.bounds_margin
	var hi := area.grid_max() - Vector2.ONE * area.bounds_margin
	var mid := (lo + hi) * 0.5
	var size := hi - lo
	var h := area.z_max - area.z_min + 20.0
	var y := (area.z_min + area.z_max) * 0.5
	for w in [[Vector2(mid.x, lo.y), Vector3(size.x, h, 0.5)], [Vector2(mid.x, hi.y), Vector3(size.x, h, 0.5)],
			[Vector2(lo.x, mid.y), Vector3(0.5, h, size.y)], [Vector2(hi.x, mid.y), Vector3(0.5, h, size.y)]]:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = w[1]
		cs.shape = sh
		body.add_child(cs)
		body.position = _gp(w[0], y)
		add_child(body)


# --- Furniture ---------------------------------------------------------------------------------

func _build_lamps() -> void:
	var cfg: Dictionary = street.render.get("street_lamp", {})
	var h: float = area.lamps.get("height", 7.0)
	var pole_mat := _surface(Color(0.12, 0.12, 0.13), 0.5)
	var col := StrayStreetBuilder._col(cfg.get("color", [1, 0.85, 0.6]))
	var lens := _emissive(col, cfg.get("lens_emission", 5.0))
	for item in area.lamps.get("items", []):
		var p := StrayStreetLayout._v2(item["en"])
		var g := area.ground_z_at(p)
		var pole := _box(Transform3D(Basis(), _gp(p, g + h * 0.5)), Vector3(0.14, h, 0.14), pole_mat, true)
		pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var head := _box(Transform3D(Basis(), _gp(p, g + h + 0.1)), Vector3(0.6, 0.2, 0.6), pole_mat)
		head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_box(Transform3D(Basis(), _gp(p, g + h - 0.01)), Vector3(0.5, 0.02, 0.5), lens)
		var spot := SpotLight3D.new()
		spot.name = "PlazaLamp"
		spot.light_color = col
		spot.light_energy = cfg.get("energy", 6.0)
		spot.spot_range = cfg.get("range", 26.0)
		spot.spot_angle = cfg.get("angle_deg", 58.0)
		spot.spot_attenuation = cfg.get("attenuation", 1.2)
		spot.shadow_enabled = false
		spot.position = _gp(p, g + h - 0.05)
		spot.rotation_degrees = Vector3(-90, 0, 0)
		add_child(spot)
		_lamp_lights.append(spot)
		stats.lights += 1


func _build_bins() -> void:
	var m := _surface(Color(0.3, 0.3, 0.31), 0.6)
	for b in area.waste_baskets:
		var p := StrayStreetLayout._v2(b["en"])
		_box(Transform3D(Basis(), _gp(p, area.ground_z_at(p) + 0.45)), Vector3(0.4, 0.9, 0.4), m, true)


## U-Bahn stele (blue sign, white "U") at the player's entrance.
func _build_ubahn_sign() -> void:
	var p := StrayStreetLayout._v2(area.ubahn_player["en"])
	build_ubahn_stele(self, _gp(p, area.ground_z_at(p)), StrayStreetLayout._v2(area.ubahn_player.get("exit_dir_en", [0, 1])),
		String(area.ubahn_player.get("name", "Dom/Hbf")))


## Shared U-Bahn stele: post, blue box with a white "U" on both faces and the station name.
static func build_ubahn_stele(parent: Node3D, ground: Vector3, face_en: Vector2, station: String) -> void:
	var basis := StrayStreetLayout.facing_basis(face_en)
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.12, 3.0, 0.12)
	post.mesh = pm
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.35, 0.36, 0.38)
	post.material_override = grey
	post.position = ground + Vector3(0, 1.5, 0)
	parent.add_child(post)
	var sign := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.7, 0.7, 0.12)
	sign.mesh = sm
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color(0.05, 0.25, 0.65)
	blue.emission_enabled = true
	blue.emission = Color(0.05, 0.25, 0.65)
	blue.emission_energy_multiplier = 1.5
	sign.material_override = blue
	sign.transform = Transform3D(basis, ground + Vector3(0, 3.2, 0))
	parent.add_child(sign)
	for flip in [0.0, PI]:
		var b2 := basis.rotated(Vector3.UP, flip)
		var u := Label3D.new()
		u.text = "U"
		u.font_size = 128
		u.pixel_size = 0.004
		u.modulate = Color(1, 1, 1)
		u.outline_size = 0
		u.shaded = false
		u.double_sided = false
		u.transform = Transform3D(b2, ground + Vector3(0, 3.2, 0) + b2.z * 0.07)
		parent.add_child(u)
		var n := Label3D.new()
		n.text = station
		n.font_size = 40
		n.pixel_size = 0.004
		n.modulate = Color(1, 1, 1)
		n.outline_size = 6
		n.shaded = false
		n.double_sided = false
		n.transform = Transform3D(b2, ground + Vector3(0, 2.72, 0) + b2.z * 0.07)
		parent.add_child(n)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.2, 3.0, 0.2)
	cs.shape = sh
	body.add_child(cs)
	body.position = ground + Vector3(0, 1.5, 0)
	parent.add_child(body)


## Lettering above the main exit (the real hall carries the station name on its front).
func _build_hbf_sign() -> void:
	var p := StrayStreetLayout._v2(area.hbf_main_exit["en"])
	var n := StrayStreetLayout._v2(area.hbf_main_exit.get("normal_en", [0, 1]))
	var l := Label3D.new()
	l.text = "Köln Hauptbahnhof"
	l.font_size = 160
	l.pixel_size = 0.01
	l.modulate = Color(1.0, 0.95, 0.85)
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.transform = Transform3D(StrayStreetLayout.facing_basis(n), _gp(p + n * 0.6, area.ground_z_at(p) + 9.0))
	add_child(l)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.9, 0.75)
	lamp.light_energy = 3.0
	lamp.omni_range = 14.0
	lamp.position = _gp(p + n * 3.0, area.ground_z_at(p) + 4.0)
	add_child(lamp)
	stats.lights += 1
