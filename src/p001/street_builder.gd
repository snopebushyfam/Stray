## Prototype 001 "The Street": builds the Hohenzollernring segment from data at runtime.
##
## Data: res://data/p001/P001_Layout.json (+ LoD2 / DGM1 OBJ), res://data/p001/godot_render.json.
## Design: docs/STRAY_GDD.md (Prototype 001), docs/TECHNICAL_PLAN.md.
## Everything is generated from data; nothing is hand-placed in a scene. Lighting is fully
## dynamic (no baking). Emits "STRAY_DIAG ..." lines as machine-checkable evidence.
class_name StrayStreetBuilder
extends Node3D

## Emitted after build(); `stats` holds counts and errors.
signal built(stats: Dictionary)

## Street chunk length (m). Chunks keep each mesh under the per-object light limit.
const CHUNK_LENGTH := 12.0
const PROFILE_STEP := 1.5
const SKIRT := 1.2

var layout: StrayStreetLayout
var render: Dictionary = {}
var stats: Dictionary = {}
var day_mode := false

var _env: WorldEnvironment
var _key: DirectionalLight3D
var _lamp_lights: Array[SpotLight3D] = []
var _materials: Dictionary = {}
var _facade_mat: ShaderMaterial


## Builds the whole street. `layout_path` / `render_path` are res:// or absolute paths.
func build(layout_path: String = "res://data/p001/P001_Layout.json",
		render_path: String = "res://data/p001/godot_render.json") -> Dictionary:
	stats = {"layout": false, "lod2": false, "terrain": false, "buildings": 0, "lod2_triangles": 0,
		"terrain_triangles": 0, "street_triangles": 0, "lights": 0, "shadow_lights": 0, "error": ""}
	layout = StrayStreetLayout.load_file(layout_path)
	var rtext := FileAccess.get_file_as_string(render_path)
	var r: Variant = JSON.parse_string(rtext) if not rtext.is_empty() else null
	render = r if typeof(r) == TYPE_DICTIONARY else {}
	if layout == null or render.is_empty():
		stats.error = "layout or render config missing"
		print("STRAY_DIAG build=failed ", stats.error)
		built.emit(stats)
		return stats
	stats.layout = true
	_build_environment()
	_build_safety_plate()
	_build_terrain()
	_build_buildings()
	_build_street_surface()
	_build_markings()
	_build_lamps()
	_build_shopfronts()
	_build_windows()
	_build_kiosk()
	_build_club()
	_build_end_barriers()
	_build_furniture()
	set_day_mode(false)
	print("STRAY_DIAG build=ok lod2=%d buildings=%d lod2_tris=%d terrain=%d terrain_tris=%d street_tris=%d profile_rows=%d lights=%d shadow_lights=%d street_len_m=%.1f" % [
		int(stats.lod2), stats.buildings, stats.lod2_triangles, int(stats.terrain), stats.terrain_triangles,
		stats.street_triangles, layout.profile.size(), stats.lights, stats.shadow_lights, layout.street_length()])
	built.emit(stats)
	return stats


## Switches between the night (default) and day presets.
func set_day_mode(day: bool) -> void:
	day_mode = day
	var p: Dictionary = render.get("day" if day else "night", {})
	var e := _env.environment
	e.background_color = _col(p.get("background", [0, 0, 0]))
	e.ambient_light_color = _col(p.get("ambient_color", [0.2, 0.2, 0.2]))
	e.ambient_light_energy = p.get("ambient_energy", 0.1)
	e.fog_density = p.get("fog_density", 0.0)
	e.fog_light_color = _col(p.get("fog_color", [0.1, 0.1, 0.1]))
	e.tonemap_exposure = p.get("exposure", 1.0)
	e.glow_intensity = p.get("glow_intensity", 0.5)
	e.glow_bloom = p.get("glow_bloom", 0.0)
	_key.light_energy = p.get("moon_energy", 0.1)
	_key.light_color = _col(p.get("moon_color", [1, 1, 1]))
	_key.rotation_degrees = Vector3(p.get("moon_pitch_deg", -30.0), p.get("moon_yaw_deg", 0.0), 0.0)
	# R9.2: the moon (energy ~0.06) casts no visible shadow, but its shadow map re-renders the scene.
	_key.shadow_enabled = bool(p.get("key_shadows", true))
	if _facade_mat:
		_facade_mat.set_shader_parameter("night_factor", p.get("facade_night_factor", 0.0 if day else 1.0))
	var lamps_on: bool = p.get("street_lamps_on", true)
	for l in _lamp_lights:
		l.visible = lamps_on
	for gl in _glow_nodes:
		gl.visible = not day
	print("STRAY_DIAG lighting=%s" % ("day" if day else "night"))


# --------------------------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------------------------

static func _col(a: Array) -> Color:
	return Color(a[0], a[1], a[2])


func _color_of(key: String) -> Color:
	return _col(render.get("colors", {}).get(key, [0.5, 0.5, 0.5]))


## Lit opaque material, cached per colour/roughness.
func _surface(c: Color, roughness: float = 0.85) -> StandardMaterial3D:
	var key := "s_%s_%.2f" % [c.to_html(), roughness]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = roughness
		_materials[key] = m
	return _materials[key]


## Unshaded emissive material (signs, windows, lamp lenses), cached.
func _emissive(c: Color, energy: float) -> StandardMaterial3D:
	var key := "e_%s_%.2f" % [c.to_html(), energy]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
		_materials[key] = m
	return _materials[key]


## Ground height (m) at a local EN point (profile-aware).
func _g(p_en: Vector2) -> float:
	return layout.ground_z_at(p_en)


func _gp(p_en: Vector2, up: float) -> Vector3:
	return StrayStreetLayout.en_to_godot(p_en.x, p_en.y, up)


## Adds a box mesh (size in metres: x = across/width, y = height, z = depth) at a transform.
func _box(xf: Transform3D, size: Vector3, mat: Material, collide: bool = false, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.transform = xf
	parent.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
		body.transform = xf
		parent.add_child(body)
	return mi


var _glow_nodes: Array[MeshInstance3D] = []
var _glow_tex: GradientTexture2D


## Additive camera-facing halo (night atmosphere around lamps and signs; hidden by day).
## Size/energy from render.glow["<kind>_size"/"<kind>_energy"].
func _glow(pos: Vector3, kind: String, c: Color) -> MeshInstance3D:
	var g: Dictionary = render.get("glow", {})
	if g.is_empty():
		return null
	if _glow_tex == null:
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 1))
		grad.set_color(1, Color(1, 1, 1, 0))
		grad.add_point(0.35, Color(1, 1, 1, 0.25))
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = grad
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
		_glow_tex.width = 64
		_glow_tex.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _glow_tex
	m.albedo_color = Color(c.r, c.g, c.b, float(g.get(kind + "_energy", 0.4)))
	m.no_depth_test = false
	m.disable_fog = true
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	var sz: float = g.get(kind + "_size", 1.0)
	q.size = Vector2(sz, sz)
	mi.mesh = q
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_glow_nodes.append(mi)
	return mi


func _count_light(shadows: bool) -> void:
	stats.lights += 1
	if shadows:
		stats.shadow_lights += 1


func _static_concave(faces: PackedVector3Array, node_name: String) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true  # never fall through, whatever the winding
	shape.set_faces(faces)
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


# --------------------------------------------------------------------------------------------
# Environment, ground, terrain, buildings
# --------------------------------------------------------------------------------------------

func _build_environment() -> void:
	_env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.glow_enabled = true
	_env.environment = e
	add_child(_env)
	_key = DirectionalLight3D.new()
	_key.name = "KeyLight"
	_key.shadow_enabled = true
	# R9: per-building facade colours made shadow acne visible as speckles on glass and signs.
	var sh: Dictionary = render.get("key_shadow", {})
	_key.shadow_bias = float(sh.get("bias", 0.1))
	_key.shadow_normal_bias = float(sh.get("normal_bias", 2.0))
	_key.directional_shadow_max_distance = float(sh.get("max_distance", 100.0))
	add_child(_key)
	_count_light(true)


func _build_safety_plate() -> void:
	# 1 m below the lowest terrain point: catches any hole, normally never visible.
	var mid := (layout.ground_min_en + layout.ground_max_en) * 0.5
	var size := layout.ground_max_en - layout.ground_min_en
	_box(Transform3D(Basis(), _gp(mid, layout.ground_z - 0.25)), Vector3(size.x, 0.5, size.y),
		_surface(_color_of("terrain"), 0.95), true)


func _build_terrain() -> void:
	if layout.terrain_mesh.is_empty():
		return
	var m := StrayObjMesh.load_file(layout.resolve(layout.terrain_mesh))
	if m == null:
		return
	var mat := _surface(_color_of("terrain"), 0.95)
	for o in m.objects:
		var mi := MeshInstance3D.new()
		mi.name = "Dgm1Terrain"
		mi.mesh = StrayObjMesh.build_mesh(o, {}, mat)
		add_child(mi)
	_static_concave(m.collision_faces(), "Dgm1TerrainCollision")
	stats.terrain = true
	stats.terrain_triangles = m.triangle_count


func _build_buildings() -> void:
	var m := StrayObjMesh.load_file(layout.resolve(layout.lod2_mesh))
	if m == null:
		stats.error = "LoD2 mesh missing"
		return
	var mats := {
		"M_LoD2_wall": _facade_material(),
		"M_LoD2_roof": _surface(_color_of("roof"), 0.8),
		"M_LoD2_ground": _surface(_color_of("terrain"), 0.95),
	}
	var holder := Node3D.new()
	holder.name = "Lod2Buildings"
	add_child(holder)
	for o in m.objects:
		# One mesh per building: each stays under the per-object light limit.
		var mi := MeshInstance3D.new()
		mi.name = o.name
		mi.mesh = StrayObjMesh.build_mesh(o, mats, mats["M_LoD2_wall"], StrayObjMesh.building_params(o))
		holder.add_child(mi)
	_static_concave(m.collision_faces(), "Lod2Collision")
	stats.lod2 = true
	stats.buildings = m.objects.size()
	stats.lod2_triangles = m.triangle_count


## Shared facade material (created once; other areas reuse it so day/night switches them too).
func facade_material() -> Material:
	if _facade_mat == null:
		return _facade_material()
	return _facade_mat


## Shows/hides the whole street (P001) except the environment and the moon/sun light: only the
## area the player is in is drawn (keeps the Compatibility renderer under its light limits).
func set_region_visible(on: bool) -> void:
	for c in get_children():
		if c == _env or c == _key or not (c is Node3D):
			continue
		(c as Node3D).visible = on
	if on:
		set_day_mode(day_mode)


## Facade ShaderMaterial (world-space window grid) or a flat fallback when the shader is missing.
func _facade_material() -> Material:
	var cfg: Dictionary = render.get("facade", {})
	var shader: Shader = load(cfg.get("shader", "")) if cfg.has("shader") else null
	if shader == null:
		return _surface(_color_of("facade"), 0.9)
	_facade_mat = ShaderMaterial.new()
	_facade_mat.shader = shader
	_facade_mat.set_shader_parameter("plaster_color", _col(cfg.get("plaster", [0.46, 0.42, 0.37])))
	_facade_mat.set_shader_parameter("frame_color", _col(cfg.get("frame", [0.18, 0.17, 0.16])))
	_facade_mat.set_shader_parameter("glass_color", _col(cfg.get("glass", [0.03, 0.03, 0.04])))
	for key in ["lit_ratio", "lit_energy", "shop_energy", "street_bounce"]:
		if cfg.has(key):
			_facade_mat.set_shader_parameter(key, cfg[key])
	return _facade_mat


## Street ShaderMaterial (asphalt / paving / kerb) aligned to the street axis, or a flat fallback.
func _street_material(kind: int, color: Color) -> Material:
	var shader: Shader = load(render.get("street_shader", "")) if render.has("street_shader") else null
	if shader == null:
		return _surface(color, 0.85)
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("surface_kind", kind)
	m.set_shader_parameter("base_color", color)
	var ax := StrayStreetLayout.en_dir_to_godot(layout.axis_en())
	m.set_shader_parameter("street_axis", Vector2(ax.x, ax.z))
	return m


# --------------------------------------------------------------------------------------------
# Street surface (follows the DGM1 profile; chunked)
# --------------------------------------------------------------------------------------------

## Triangle soup per material section; tri() orients triangles to face `desired`.
class Soup:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()

	func tri(a: Vector3, b: Vector3, c: Vector3, desired: Vector3) -> void:
		# Godot front face is clockwise: front normal = (c - a) x (b - a).
		var n := (c - a).cross(b - a)
		if n.length_squared() < 1e-10:
			return
		if n.dot(desired) < 0.0:
			var t := b
			b = c
			c = t
			n = -n
		n = n.normalized()
		verts.append_array(PackedVector3Array([a, b, c]))
		normals.append_array(PackedVector3Array([n, n, n]))

	func quad(p00: Vector3, p10: Vector3, p11: Vector3, p01: Vector3, desired: Vector3) -> void:
		tri(p00, p10, p11, desired)
		tri(p00, p11, p01, desired)


func _build_street_surface() -> void:
	var L := layout
	var k := L.kerb_half_width
	var md := L.median_half_width
	var kw := StrayStreetLayout.KERB_STONE_WIDTH
	var fw := L.facade_v_west
	var fe := L.facade_v_east
	var up := Vector3.UP
	var right := StrayStreetLayout.en_dir_to_godot(L.right_en())
	var along := StrayStreetLayout.en_dir_to_godot(L.axis_en())
	var sections := ["asphalt", "median", "paving", "kerb", "terrain"]
	var section_mats: Array[Material] = [
		_street_material(0, _color_of("asphalt")), _street_material(2, _color_of("median")),
		_street_material(1, _color_of("paving")), _street_material(2, _color_of("kerb")),
		_surface(_color_of("terrain"), 0.95)]
	var all_faces := PackedVector3Array()
	var holder := Node3D.new()
	holder.name = "StreetSurface"
	add_child(holder)

	var p := func(s: float, v: float, z: float) -> Vector3:
		return _gp(L.to_en(s, v), z)
	var road := func(s: float, v: float) -> float: return L.road_z(s, v)
	var walk := func(s: float, v: float) -> float: return L.sidewalk_z(s, v)
	var kerb_top := func(s: float, v: float) -> float: return L.sidewalk_z(s, -k - kw if v < 0.0 else k + kw) + 0.005
	var med_top := func(s: float, _v: float) -> float: return L.profile_at(s)[1] + StrayStreetLayout.MEDIAN_RISE

	var c0 := L.s_start
	while c0 < L.s_end - 0.01:
		var c1 := minf(c0 + CHUNK_LENGTH, L.s_end)
		var soups: Array[Soup] = []
		for _i in sections.size():
			soups.append(Soup.new())
		var s0 := c0
		while s0 < c1 - 0.001:
			var s1 := minf(s0 + PROFILE_STEP, c1)
			var top := func(sec: int, v0: float, v1: float, zf: Callable) -> void:
				soups[sec].quad(p.call(s0, v0, zf.call(s0, v0)), p.call(s1, v0, zf.call(s1, v0)),
					p.call(s1, v1, zf.call(s1, v1)), p.call(s0, v1, zf.call(s0, v1)), up)
			var wall := func(sec: int, v: float, lo: Callable, hi: Callable, facing: Vector3) -> void:
				soups[sec].quad(p.call(s0, v, lo.call(s0, v)), p.call(s1, v, lo.call(s1, v)),
					p.call(s1, v, hi.call(s1, v)), p.call(s0, v, hi.call(s0, v)), facing)
			top.call(2, L.sidewalk_west_outer, fw, walk)
			top.call(2, fw, -k - kw, walk)
			top.call(3, -k - kw, -k, kerb_top)
			top.call(0, -k, -md, road)
			top.call(1, -md, md, med_top)
			top.call(0, md, k, road)
			top.call(3, k, k + kw, kerb_top)
			top.call(2, k + kw, fe, walk)
			top.call(2, fe, L.sidewalk_east_outer, walk)
			wall.call(3, -k, road, kerb_top, right)
			wall.call(3, k, road, kerb_top, -right)
			wall.call(1, -md, road, med_top, -right)
			wall.call(1, md, road, med_top, right)
			var skirt_lo := func(s: float, v: float) -> float: return L.sidewalk_z(s, v) - SKIRT
			wall.call(4, L.sidewalk_west_outer, skirt_lo, walk, -right)
			wall.call(4, L.sidewalk_east_outer, skirt_lo, walk, right)
			s0 = s1
		# End caps of the whole street body.
		for s_end_cap in [L.s_start, L.s_end]:
			if not (is_equal_approx(s_end_cap, c0) or is_equal_approx(s_end_cap, c1)):
				continue
			var facing: Vector3 = -along if is_equal_approx(s_end_cap, L.s_start) else along
			var prow := L.profile_at(s_end_cap)
			var bottom := minf(prow[2], prow[3]) - SKIRT
			var vs := [L.sidewalk_west_outer, fw, -k, -md, md, k, fe, L.sidewalk_east_outer]
			var topz := func(v: float) -> float:
				var z := L.road_z(s_end_cap, v)
				if absf(v) >= k - 1e-6:
					z = maxf(z, L.sidewalk_z(s_end_cap, v) + 0.005)
				if absf(v) <= md + 1e-6:
					z = maxf(z, prow[1] + StrayStreetLayout.MEDIAN_RISE)
				return z
			for j in vs.size() - 1:
				soups[4].quad(p.call(s_end_cap, vs[j], bottom), p.call(s_end_cap, vs[j + 1], bottom),
					p.call(s_end_cap, vs[j + 1], topz.call(vs[j + 1])), p.call(s_end_cap, vs[j], topz.call(vs[j])), facing)

		var mesh := ArrayMesh.new()
		for i in sections.size():
			if soups[i].verts.is_empty():
				continue
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = soups[i].verts
			arrays[Mesh.ARRAY_NORMAL] = soups[i].normals
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, section_mats[i])
			all_faces.append_array(soups[i].verts)
			stats.street_triangles += soups[i].verts.size() / 3
		var mi := MeshInstance3D.new()
		mi.name = "Chunk_%d" % int(c0)
		mi.mesh = mesh
		holder.add_child(mi)
		c0 = c1
	_static_concave(all_faces, "StreetCollision")


func _build_markings() -> void:
	var L := layout
	var xforms: Array[Transform3D] = []
	var basis := Basis.looking_at(-StrayStreetLayout.en_dir_to_godot(L.axis_en()), Vector3.UP)
	var piece := func(s_mid: float, v: float, length: float) -> void:
		var pos := _gp(L.to_en(s_mid, v), L.road_z(s_mid, v) + 0.006)
		xforms.append(Transform3D(basis * Basis.from_scale(Vector3(0.12, 0.02, length)), pos))
	var s := L.s_start
	while s + 3.0 <= L.s_end + 1e-3:
		piece.call(s + 1.5, -L.carriageway_half_width, 3.02)
		piece.call(s + 1.5, L.carriageway_half_width, 3.02)
		s += 3.0
	s = L.s_start + 1.5
	while s + 3.0 < L.s_end:
		piece.call(s + 1.5, -L.lane_divider_offset, 3.0)
		piece.call(s + 1.5, L.lane_divider_offset, 3.0)
		s += 9.0
	_multimesh(xforms, _surface(_color_of("paint"), 0.6), "Markings")


func _multimesh(xforms: Array[Transform3D], mat: Material, node_name: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	mm.mesh = bm
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
	return mmi


# --------------------------------------------------------------------------------------------
# Lamps, shopfronts, windows
# --------------------------------------------------------------------------------------------

func _build_lamps() -> void:
	var cfg: Dictionary = render.get("street_lamp", {})
	var h: float = layout.lamps.get("height", 8.0)
	var pole_mat := _surface(_color_of("metal"), 0.5)
	var lamp_col := _col(cfg.get("color", [1, 0.85, 0.6]))
	var lens := _emissive(lamp_col, cfg.get("lens_emission", 5.0))
	for item in layout.lamps.get("positions", []):
		var pos := StrayStreetLayout._v2(item["en"])
		var arm := StrayStreetLayout._v2(item["arm_dir_en"]).normalized()
		var g := _g(pos)
		var arm_basis := StrayStreetLayout.facing_basis(arm)  # +Z along the arm
		var pole := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.07
		cyl.bottom_radius = 0.09
		cyl.height = h
		pole.mesh = cyl
		pole.material_override = pole_mat
		pole.position = _gp(pos, g + h * 0.5)
		# Lamp hardware sits next to its own light: its shadow showed up as jagged wedges.
		pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(pole)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var cshape := CylinderShape3D.new()
		cshape.radius = 0.09
		cshape.height = h
		cs.shape = cshape
		body.add_child(cs)
		body.position = pole.position
		add_child(body)
		for part in [
				_box(Transform3D(arm_basis, _gp(pos + arm * 0.8, g + h - 0.10)), Vector3(0.08, 0.08, 1.6), pole_mat),
				_box(Transform3D(arm_basis, _gp(pos + arm * 1.5, g + h - 0.20)), Vector3(0.30, 0.14, 0.70), pole_mat),
				_box(Transform3D(arm_basis, _gp(pos + arm * 1.5, g + h - 0.275)), Vector3(0.22, 0.02, 0.60), lens)]:
			part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var spot := SpotLight3D.new()
		spot.name = "StreetLamp"
		spot.light_color = lamp_col
		spot.light_energy = cfg.get("energy", 6.0)
		spot.spot_range = cfg.get("range", 26.0)
		spot.spot_angle = cfg.get("angle_deg", 58.0)
		spot.spot_attenuation = cfg.get("attenuation", 1.2)
		spot.shadow_enabled = cfg.get("shadows", true)
		spot.position = _gp(pos + arm * 1.5, g + h - 0.30)
		spot.rotation_degrees = Vector3(-90, 0, 0)  # -Z (light direction) points down
		add_child(spot)
		_lamp_lights.append(spot)
		_count_light(spot.shadow_enabled)
		_glow(_gp(pos + arm * 1.5, g + h - 0.45), "lamp", lamp_col)


func _build_shopfronts() -> void:
	var cfg: Dictionary = render.get("shopfront", {})
	for f in layout.shopfronts.get("items", []):
		var pos := StrayStreetLayout._v2(f["en"])
		var n := StrayStreetLayout._v2(f["normal_en"]).normalized()
		var w: float = f.get("width", 4.0)
		var hh: float = f.get("height", 2.8)
		var c := _col(f.get("color", [1, 0.85, 0.65]))
		var zc := _g(pos + n) + 0.30 + hh * 0.5
		var b := StrayStreetLayout.facing_basis(n)
		if not cfg.get("panels", true):
			# Shop glazing comes from the facade shader; keep only the light spilling onto the sidewalk.
			var spill := OmniLight3D.new()
			spill.light_color = c
			spill.light_energy = cfg.get("energy", 1.5)
			spill.omni_range = cfg.get("range", 7.0)
			spill.position = _gp(pos + n * 0.9, zc)
			add_child(spill)
			_count_light(false)
			continue
		_box(Transform3D(b, _gp(pos, zc)), Vector3(w + 0.35, hh + 0.35, 0.16), _surface(_color_of("metal"), 0.4))
		# Panel sits 3 cm proud of the frame's front face (frame front = 0.08 m) - no z-fighting.
		_box(Transform3D(b, _gp(pos + n * 0.12, zc)), Vector3(w, hh, 0.02), _emissive(c * float(cfg.get("panel_tint", 1.0)), cfg.get("emission", 2.0)))
		# Mullion + stall riser in front of the glow: reads as a shop window, not a light board.
		var frame_mat := _surface(_color_of("metal"), 0.4)
		_box(Transform3D(b, _gp(pos + n * 0.15, zc)), Vector3(0.08, hh, 0.03), frame_mat)
		_box(Transform3D(b, _gp(pos + n * 0.15, zc - hh * 0.5 + 0.25)), Vector3(w, 0.5, 0.03), frame_mat)
		var omni := OmniLight3D.new()
		omni.light_color = c
		omni.light_energy = cfg.get("energy", 1.5)
		omni.omni_range = cfg.get("range", 7.0)
		omni.position = _gp(pos + n * 0.9, zc)
		add_child(omni)
		_count_light(false)


func _build_windows() -> void:
	if not render.get("use_window_instances", true):
		return  # the facade shader draws (and lights) the upper-floor windows
	var w: float = layout.upper_windows.get("width", 1.2)
	var hh: float = layout.upper_windows.get("height", 1.5)
	var warm: Array[Transform3D] = []
	var cool: Array[Transform3D] = []
	for f in layout.upper_windows.get("items", []):
		var pos := StrayStreetLayout._v2(f["en"])
		var n := StrayStreetLayout._v2(f["normal_en"]).normalized()
		var xf := Transform3D(StrayStreetLayout.facing_basis(n) * Basis.from_scale(Vector3(w, hh, 0.04)),
			_gp(pos + n * 0.03, _g(pos + n) + float(f.get("z", 5.0))))
		(warm if f.get("warm", true) else cool).append(xf)
	var e: float = render.get("upper_window_emission", 1.0)
	_multimesh(warm, _emissive(Color(1.0, 0.75, 0.45), e), "WindowsWarm")
	_multimesh(cool, _emissive(Color(0.70, 0.82, 1.0), e), "WindowsCool")


# --------------------------------------------------------------------------------------------
# Landmarks
# --------------------------------------------------------------------------------------------

## Helper for facade features: position `along` the facade, `out` from it, `up` above ground.
func _feature_frame(f: Dictionary) -> Dictionary:
	var pos := StrayStreetLayout._v2(f["en"])
	var n := StrayStreetLayout._v2(f["normal_en"]).normalized()
	var t := Vector2(n.y, -n.x)
	return {"pos": pos, "n": n, "t": t, "g": _g(pos + n), "basis": StrayStreetLayout.facing_basis(n)}


func _at(fr: Dictionary, along: float, out: float, up: float) -> Vector3:
	var p: Vector2 = fr.pos + fr.t * along + fr.n * out
	return _gp(p, fr.g + up)


func _label(text: String, pos: Vector3, basis: Basis, px: float, color: Color, size: int = 96) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.modulate = color
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.transform = Transform3D(basis, pos)
	add_child(l)


func _build_kiosk() -> void:
	var cfg: Dictionary = render.get("kiosk", {})
	var fr := _feature_frame(layout.kiosk)
	var b: Basis = fr.basis
	var warm := Color(1.0, 0.84, 0.62)
	_box(Transform3D(b, _at(fr, 0.0, 0.05, 1.55)), Vector3(5.2, 3.1, 0.20), _surface(_color_of("metal"), 0.35))
	_box(Transform3D(b, _at(fr, -0.7, 0.16, 1.35)), Vector3(3.1, 2.2, 0.04), _emissive(warm, cfg.get("window_emission", 3.0)))
	_box(Transform3D(b, _at(fr, 1.75, 0.16, 1.15)), Vector3(1.05, 2.25, 0.04), _surface(Color(0.01, 0.01, 0.012), 0.05))
	_box(Transform3D(b, _at(fr, 0.0, 0.20, 3.45)), Vector3(4.6, 0.75, 0.25), _emissive(Color(0.93, 0.9, 0.84), cfg.get("sign_emission", 4.0)))
	_label("KIOSK", _at(fr, 0.0, 0.34, 3.45), b, 0.006, Color(0.6, 0.02, 0.02), 96)
	_label("Getränke · Snacks · Tabak · 24/7", _at(fr, 0.0, 0.36, 2.95), b, 0.0025, Color(1.0, 0.94, 0.82), 64)
	_box(Transform3D(b, _at(fr, 0.0, 0.75, 2.95)), Vector3(5.2, 0.08, 1.3), _surface(Color(0.25, 0.03, 0.03), 0.6))
	# Drinks fridge: shaded cabinet with a dimly lit glass door (was a flat white emissive block).
	_box(Transform3D(b, _at(fr, -2.4, 0.45, 0.95)), Vector3(0.8, 1.9, 0.7), _surface(Color(0.75, 0.76, 0.78), 0.5), true)
	var fridge_glass := _emissive(Color(0.45, 0.62, 0.78), cfg.get("fridge_emission", 1.6))
	_box(Transform3D(b, _at(fr, -2.4, 0.81, 1.0)), Vector3(0.66, 1.55, 0.02), fridge_glass)
	_glow(_at(fr, 0.0, 0.9, 3.45), "kiosk", Color(1.0, 0.9, 0.75))
	var spot := SpotLight3D.new()
	spot.light_color = warm
	spot.light_energy = cfg.get("light_energy", 2.5)
	spot.spot_range = cfg.get("light_range", 9.0)
	spot.spot_angle = 70.0
	spot.shadow_enabled = true
	# Light shines along -Z: point it out of the shop and down onto the sidewalk.
	spot.transform = Transform3D(Basis.looking_at((StrayStreetLayout.en_dir_to_godot(fr.n) + Vector3.DOWN * 0.6).normalized(), Vector3.UP), _at(fr, 0.0, 1.0, 2.7))
	add_child(spot)
	_count_light(true)


func _build_club() -> void:
	var cfg: Dictionary = render.get("club", {})
	var fr := _feature_frame(layout.club)
	var b: Basis = fr.basis
	var magenta := Color(1.0, 0.05, 0.55)
	var ice := Color(0.25, 0.45, 1.0)
	_box(Transform3D(b, _at(fr, 0.0, 0.08, 1.6)), Vector3(4.2, 3.2, 0.25), _surface(Color(0.01, 0.01, 0.01), 0.3))
	_box(Transform3D(b, _at(fr, 0.0, 0.22, 1.3)), Vector3(2.0, 2.6, 0.05), _surface(Color(0.01, 0.01, 0.012), 0.15))
	for side in [-1.15, 1.15]:
		_box(Transform3D(b, _at(fr, side, 0.23, 1.4)), Vector3(0.08, 2.8, 0.05), _emissive(magenta, cfg.get("strip_emission", 6.0)))
	_box(Transform3D(b, _at(fr, 0.0, 1.1, 3.35)), Vector3(4.6, 0.25, 2.2), _surface(Color(0.015, 0.015, 0.02), 0.4))
	_box(Transform3D(b, _at(fr, 0.0, 2.21, 3.35)), Vector3(4.4, 0.2, 0.03), _emissive(ice, cfg.get("canopy_emission", 5.0)))
	_box(Transform3D(b, _at(fr, 0.0, 0.20, 4.15)), Vector3(4.4, 0.9, 0.12), _surface(Color(0.01, 0.01, 0.012), 0.3))
	_label("NACHTFLUG", _at(fr, 0.0, 0.28, 4.15), b, 0.0075, Color(1.0, 0.35, 0.8), 112)
	_glow(_at(fr, 0.0, 1.0, 4.1), "neon", Color(1.0, 0.3, 0.75))
	for i in 4:
		var along := -2.6 + i * 1.2
		var post := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.04
		cyl.bottom_radius = 0.05
		cyl.height = 1.0
		post.mesh = cyl
		post.material_override = _surface(Color(0.6, 0.6, 0.62), 0.15)
		post.position = _at(fr, along, 2.0, 0.5)
		add_child(post)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 0.05
		sh.height = 1.0
		cs.shape = sh
		body.add_child(cs)
		body.position = post.position
		add_child(body)
		if i < 3:
			_box(Transform3D(b, _at(fr, along + 0.6, 2.0, 0.85)), Vector3(1.15, 0.04, 0.04), _surface(Color(0.35, 0.0, 0.02), 0.5))
	var wash := SpotLight3D.new()
	wash.light_color = magenta
	wash.light_energy = cfg.get("wash_energy", 3.5)
	wash.spot_range = cfg.get("wash_range", 12.0)
	wash.spot_angle = 65.0
	wash.shadow_enabled = true
	var out_dir := StrayStreetLayout.en_dir_to_godot(fr.n)
	wash.transform = Transform3D(Basis.looking_at((out_dir + Vector3.DOWN * 0.9).normalized(), Vector3.UP), _at(fr, 0.0, 2.0, 3.15))
	add_child(wash)
	_count_light(true)
	var door := SpotLight3D.new()
	door.light_color = ice
	door.light_energy = cfg.get("door_energy", 4.0)
	door.spot_range = 6.0
	door.spot_angle = 40.0
	door.position = _at(fr, 0.0, 1.2, 3.18)
	door.rotation_degrees = Vector3(-90, 0, 0)
	add_child(door)
	_count_light(false)


func _build_end_barriers() -> void:
	var L := layout
	var basis := Basis.looking_at(-StrayStreetLayout.en_dir_to_godot(L.axis_en()), Vector3.UP)
	var red: Array[Transform3D] = []
	var white: Array[Transform3D] = []
	for s in [L.s_start + 0.3, L.s_end - 0.3]:
		var i := 0
		var v := L.sidewalk_west_outer + 0.6
		while v < L.sidewalk_east_outer - 0.5:
			if absf(v) < L.kerb_half_width:
				# Carriageway stays open for through traffic (the player is still blocked
				# by the invisible end wall below).
				v += 1.25
				i += 1
				continue
			var bp := L.to_en(s, v)
			var xf := Transform3D(basis * Basis.from_scale(Vector3(1.2, 1.1, 0.3)), _gp(bp, _g(bp) + 0.55))
			(white if i % 2 else red).append(xf)
			v += 1.25
			i += 1
		# Invisible wall: the prototype ends here (the city beyond is not built yet).
		var mid := L.to_en(s, (L.sidewalk_west_outer + L.sidewalk_east_outer) * 0.5)
		var body := StaticBody3D.new()
		body.name = "EndWall"
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(L.sidewalk_east_outer - L.sidewalk_west_outer + 4.0, 12.0, 0.5)
		cs.shape = sh
		body.add_child(cs)
		body.transform = Transform3D(basis, _gp(mid, L.profile_at(s)[1] + 5.0))
		add_child(body)
	_multimesh(red, _surface(Color(0.5, 0.02, 0.02), 0.6), "BarriersRed")
	_multimesh(white, _surface(Color(0.7, 0.7, 0.7), 0.6), "BarriersWhite")


# --------------------------------------------------------------------------------------------
# Street furniture (OSM positions; parked cars procedural)
# --------------------------------------------------------------------------------------------

func _fcol(key: String, fallback: Array) -> Color:
	return _col(render.get("furniture", {}).get(key, fallback))


func _cyl(pos: Vector3, radius: float, height: float, mat: Material, collide: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = radius
		sh.height = height
		cs.shape = sh
		body.add_child(cs)
		body.position = pos
		add_child(body)
	return mi


func _build_furniture() -> void:
	var f: Dictionary = layout.furniture
	if f.is_empty():
		return
	var counts := {}
	var axis_basis := Basis.looking_at(-StrayStreetLayout.en_dir_to_godot(layout.axis_en()), Vector3.UP)

	# Trees (real OSM positions): trunk with collision + two crown spheres.
	for t in f.get("trees", []):
		var p := StrayStreetLayout._v2(t["en"])
		var g := _g(p)
		_cyl(_gp(p, g + 1.6), 0.16, 3.2, _surface(_fcol("trunk", [0.16, 0.11, 0.07]), 0.9), true)
		for c in [[0.0, 4.6, 2.3], [0.6, 5.6, 1.7]]:
			var crown := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = c[2]
			sm.height = c[2] * 1.7
			crown.mesh = sm
			crown.material_override = _surface(_fcol("tree_crown", [0.07, 0.16, 0.06]), 0.95)
			crown.position = _gp(p + layout.axis_en() * float(c[0]), g + float(c[1]))
			add_child(crown)
	counts["trees"] = f.get("trees", []).size()

	# Waste baskets (OSM).
	for w in f.get("waste_baskets", []):
		var p := StrayStreetLayout._v2(w["en"])
		_cyl(_gp(p, _g(p) + 0.45), 0.22, 0.9, _surface(_fcol("bin", [0.3, 0.3, 0.31]), 0.6), true)
	counts["bins"] = f.get("waste_baskets", []).size()

	# Bicycle racks (OSM): five "Kreuzberger Bügel" across the parking strip.
	for b in f.get("bicycle_parking", []):
		var rack := _surface(_fcol("rack", [0.55, 0.56, 0.58]), 0.3)
		for i in 5:
			var p: Vector2 = layout.to_en(float(b["s"]) - 2.4 + i * 1.2, float(b["v"]))
			var g := _g(p)
			for side in [-0.35, 0.35]:
				_box(Transform3D(axis_basis, _gp(p + layout.axis_en() * side, g + 0.4)), Vector3(0.05, 0.8, 0.05), rack, true)
			_box(Transform3D(axis_basis, _gp(p, g + 0.8)), Vector3(0.05, 0.05, 0.75), rack)
	counts["bike_racks"] = f.get("bicycle_parking", []).size()

	# Building entrances (OSM), skipped where a shopfront / landmark already occupies the facade.
	var occupied: Array[Vector2] = []
	for sf in layout.shopfronts.get("items", []):
		occupied.append(StrayStreetLayout._v2(sf["en"]))
	occupied.append(StrayStreetLayout._v2(layout.kiosk["en"]))
	occupied.append(StrayStreetLayout._v2(layout.club["en"]))
	var doors := 0
	for e in f.get("entrances", []):
		var p := StrayStreetLayout._v2(e["en"])
		var free := true
		for o in occupied:
			if o.distance_to(p) < 3.2:
				free = false
				break
		if not free:
			continue
		var n := StrayStreetLayout._v2(e["normal_en"]).normalized()
		var bas := StrayStreetLayout.facing_basis(n)
		var g := _g(p + n)
		var glass: bool = e.get("kind", "yes") == "shop"
		_box(Transform3D(bas, _gp(p + n * 0.05, g + 1.2)), Vector3(1.5, 2.5, 0.12), _surface(Color(0.1, 0.09, 0.08), 0.5))
		_box(Transform3D(bas, _gp(p + n * 0.12, g + 1.12)), Vector3(1.2, 2.2, 0.04),
			_surface(_fcol("door_glass" if glass else "door_wood", [0.16, 0.1, 0.06]), 0.25 if glass else 0.6))
		_box(Transform3D(bas, _gp(p + n * 0.16, g + 2.45)), Vector3(0.3, 0.08, 0.06), _emissive(Color(1.0, 0.85, 0.6), 2.5))
		occupied.append(p)
		doors += 1
	counts["doors"] = doors

	# ATMs (OSM): steel panel with a lit screen and a keypad.
	for a in f.get("atms", []):
		var p := StrayStreetLayout._v2(a["en"])
		var n := StrayStreetLayout._v2(a["normal_en"]).normalized()
		var bas := StrayStreetLayout.facing_basis(n)
		var g := _g(p + n)
		_box(Transform3D(bas, _gp(p + n * 0.1, g + 1.15)), Vector3(0.75, 1.1, 0.2), _surface(Color(0.45, 0.47, 0.5), 0.35))
		_box(Transform3D(bas, _gp(p + n * 0.21, g + 1.35)), Vector3(0.4, 0.3, 0.02), _emissive(Color(0.35, 0.65, 1.0), 2.5))
		_box(Transform3D(bas, _gp(p + n * 0.24, g + 1.02)), Vector3(0.3, 0.12, 0.1), _surface(Color(0.12, 0.12, 0.13), 0.5))
		_box(Transform3D(bas, _gp(p + n * 0.2, g + 1.85)), Vector3(0.75, 0.22, 0.04), _emissive(Color(0.2, 0.45, 0.9), 1.8))
	counts["atms"] = f.get("atms", []).size()

	# Surveillance cameras (OSM).
	for c in f.get("cameras", []):
		var p := StrayStreetLayout._v2(c["en"])
		var n := StrayStreetLayout._v2(c["normal_en"]).normalized()
		_box(Transform3D(StrayStreetLayout.facing_basis(n), _gp(p + n * 0.25, _g(p + n) + 3.4)), Vector3(0.12, 0.12, 0.35), _surface(Color(0.8, 0.8, 0.78), 0.4))

	# Traffic signal + pedestrian ford (OSM signal position).
	for sig in f.get("traffic_signals", []):
		_build_signal(float(sig["s"]), float(sig.get("ford_s", float(sig["s"]) - 3.0)), axis_basis)
	counts["signals"] = f.get("traffic_signals", []).size()

	# Parked cars (procedural placeholders, collision boxes).
	for car in f.get("parked_cars", []):
		_build_car(StrayStreetLayout._v2(car["en"]), float(car["length"]), _col(car["color"]), axis_basis)
	counts["cars"] = f.get("parked_cars", []).size()
	print("STRAY_DIAG furniture %s" % JSON.stringify(counts))


func _build_signal(s_sig: float, s_ford: float, axis_basis: Basis) -> void:
	var L := layout
	var housing := _surface(_fcol("signal_housing", [0.05, 0.05, 0.05]), 0.5)
	var red := _emissive(Color(1.0, 0.08, 0.05), render.get("furniture", {}).get("signal_red_emission", 5.0))
	var green := _emissive(Color(0.1, 1.0, 0.45), render.get("furniture", {}).get("signal_green_emission", 5.0))
	# Poles on both kerbs and the median; vehicle heads face oncoming traffic (northbound east side,
	# southbound west side), pedestrian heads face across the street.
	for v in [-L.kerb_half_width - 0.5, 0.0, L.kerb_half_width + 0.5]:
		var p: Vector2 = L.to_en(s_sig, v)
		var g := _g(p)
		_cyl(_gp(p, g + 1.75), 0.06, 3.5, housing, true)
		var toward_south := -L.axis_en() if v >= 0.0 else L.axis_en()
		var head_basis := StrayStreetLayout.facing_basis(toward_south if v != 0.0 else -L.axis_en())
		var head := p + toward_south * 0.12
		_box(Transform3D(head_basis, _gp(head, g + 3.0)), Vector3(0.3, 0.9, 0.22), housing)
		var off := StrayStreetLayout.en_dir_to_godot(toward_south if v != 0.0 else -L.axis_en()) * 0.12
		# Vehicles have green (bottom lamp lit), pedestrians red.
		_box(Transform3D(head_basis, _gp(head, g + 3.28) + off), Vector3(0.2, 0.2, 0.02), _surface(Color(0.08, 0.01, 0.01), 0.3))
		_box(Transform3D(head_basis, _gp(head, g + 2.72) + off), Vector3(0.2, 0.2, 0.02), green)
		if v != 0.0:
			var across := L.right_en() * (1.0 if v < 0.0 else -1.0)
			var ped_basis := StrayStreetLayout.facing_basis(across)
			_box(Transform3D(ped_basis, _gp(p + across * 0.1, g + 2.3)), Vector3(0.25, 0.5, 0.15), housing)
			_box(Transform3D(ped_basis, _gp(p + across * 0.18, g + 2.42)), Vector3(0.16, 0.16, 0.02), red)
	# Ford markings: two dashed lines across the carriageways (German signalised crossing).
	var xforms: Array[Transform3D] = []
	for ds in [-2.0, 2.0]:
		var v := -L.kerb_half_width + 0.3
		while v < L.kerb_half_width - 0.3:
			if absf(v) > L.median_half_width + 0.2:
				var pp: Vector2 = L.to_en(s_ford + ds, v)
				xforms.append(Transform3D(axis_basis * Basis.from_scale(Vector3(0.5, 0.02, 0.12)), _gp(pp, L.road_z(s_ford + ds, v) + 0.006)))
			v += 1.0
	_multimesh(xforms, _surface(_color_of("paint"), 0.6), "PedestrianFord")
	var stop: Array[Transform3D] = []
	for v_stop in [-L.carriageway_half_width * 0.5 - 0.3, L.carriageway_half_width * 0.5 + 0.3]:
		var sp: Vector2 = L.to_en(s_ford + (-3.2 if v_stop > 0.0 else 3.2), v_stop)
		stop.append(Transform3D(axis_basis * Basis.from_scale(Vector3(L.carriageway_half_width - 1.0, 0.02, 0.4)), _gp(sp, L.road_z(s_ford, v_stop) + 0.006)))
	_multimesh(stop, _surface(_color_of("paint"), 0.6), "StopLines")
	print("STRAY_DIAG signal s=%.1f ford_s=%.1f" % [s_sig, s_ford])


func _build_car(p: Vector2, length: float, color: Color, axis_basis: Basis) -> void:
	var g := layout.ground_z_at(p)
	var w := 1.8
	var root := Node3D.new()
	# Car model local -Z = front; parked cars face along the street axis.
	root.transform = Transform3D(axis_basis.rotated(Vector3.UP, PI), _gp(p, g))
	add_child(root)
	StrayCarModel.build(root, length, w, color, false)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(w, 1.45, length)
	cs.shape = sh
	body.add_child(cs)
	body.transform = Transform3D(axis_basis, _gp(p, g + 0.75))
	add_child(body)
