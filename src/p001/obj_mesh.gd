## Minimal Wavefront OBJ reader for the LoD2 / DGM1 cut-outs (triangles only).
##
## The OBJ files come from tools/geodata (local EN metres, Z up, triangles counter-clockwise
## seen from outside). Godot draws CLOCKWISE triangles as front faces, so the index order is
## reversed here; the EN -> Godot mapping itself is a pure rotation and keeps handedness.
class_name StrayObjMesh
extends RefCounted

## One OBJ object ("o" line) with its triangles split by material.
class ObjObject:
	var name: String = ""
	## material name -> PackedVector3Array (3 vertices per triangle, Godot space, CW front)
	var surfaces: Dictionary = {}
	var aabb := AABB()
	var has_aabb := false

var objects: Array[ObjObject] = []
var triangle_count: int = 0
var aabb := AABB()


## Parses OBJ text. Returns "" on success, otherwise an error message.
func parse(text: String) -> String:
	var verts := PackedVector3Array()
	var current: ObjObject = null
	var material := "default"
	var first := true
	for raw_line in text.split("\n", false):
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var tok := line.split(" ", false)
		match tok[0]:
			"v":
				verts.append(StrayStreetLayout.en_to_godot(tok[1].to_float(), tok[2].to_float(), tok[3].to_float()))
			"o":
				current = ObjObject.new()
				current.name = tok[1] if tok.size() > 1 else "object_%d" % objects.size()
				objects.append(current)
			"usemtl":
				material = tok[1] if tok.size() > 1 else "default"
			"f":
				if tok.size() != 4:
					return "only triangles are supported: '%s'" % line
				if current == null:
					current = ObjObject.new()
					current.name = "default"
					objects.append(current)
				var idx := PackedInt32Array()
				for k in range(1, 4):
					var i := tok[k].get_slice("/", 0).to_int() - 1
					if i < 0 or i >= verts.size():
						return "vertex index out of range: '%s'" % line
					idx.append(i)
				var a := verts[idx[0]]
				var b := verts[idx[1]]
				var c := verts[idx[2]]
				if (b - a).cross(c - a).length_squared() < 1e-12:
					continue
				if not current.surfaces.has(material):
					current.surfaces[material] = PackedVector3Array()
				var arr: PackedVector3Array = current.surfaces[material]
				arr.append(a)
				arr.append(c)  # reversed: CCW (data) -> CW (Godot front face)
				arr.append(b)
				current.surfaces[material] = arr
				triangle_count += 1
				for p in [a, b, c]:
					if current.has_aabb:
						current.aabb = current.aabb.expand(p)
					else:
						current.aabb = AABB(p, Vector3.ZERO)
						current.has_aabb = true
					if first:
						aabb = AABB(p, Vector3.ZERO)
						first = false
					else:
						aabb = aabb.expand(p)
	if triangle_count == 0:
		return "OBJ contains no triangles"
	return ""


## Reads and parses a file. Returns null and pushes an error on failure.
static func load_file(path: String) -> StrayObjMesh:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("STRAY_DIAG obj=failed cannot read %s" % path)
		return null
	if text.begins_with("version https://git-lfs"):
		push_error("STRAY_DIAG obj=failed %s is a Git LFS pointer - run 'git lfs pull'" % path)
		return null
	var m := StrayObjMesh.new()
	var err := m.parse(text)
	if not err.is_empty():
		push_error("STRAY_DIAG obj=failed %s: %s" % [path, err])
		return null
	return m


## Builds a flat-shaded ArrayMesh for one object; `materials` maps material name -> Material.
## `vertex_color` (optional) is written to every vertex: the facade shader reads per-building
## parameters from it (material seed, window seed, height, base).
static func build_mesh(obj: ObjObject, materials: Dictionary, fallback: Material, vertex_color: Variant = null) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for mat_name in obj.surfaces:
		var tris: PackedVector3Array = obj.surfaces[mat_name]
		var normals := PackedVector3Array()
		normals.resize(tris.size())
		for t in range(0, tris.size(), 3):
			# Godot front face is CW, so the outward normal is (c - a) x (b - a).
			var n := (tris[t + 2] - tris[t]).cross(tris[t + 1] - tris[t]).normalized()
			normals[t] = n
			normals[t + 1] = n
			normals[t + 2] = n
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = tris
		arrays[Mesh.ARRAY_NORMAL] = normals
		if vertex_color != null:
			var cols := PackedColorArray()
			cols.resize(tris.size())
			cols.fill(vertex_color)
			arrays[Mesh.ARRAY_COLOR] = cols
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials.get(mat_name, fallback))
	return mesh


## Per-building shader parameters packed into a vertex colour: r = material seed, g = window
## seed (both stable hashes of the building id), b = height / 100 m, a = (base + 10 m) / 20 m.
static func building_params(obj: ObjObject) -> Color:
	var lo := INF
	var hi := -INF
	for mat_name in obj.surfaces:
		for v in obj.surfaces[mat_name]:
			lo = minf(lo, v.y)
			hi = maxf(hi, v.y)
	var h := hash(obj.name)
	return Color(float(h & 0xFFFF) / 65535.0, float((h >> 16) & 0xFFFF) / 65535.0,
		clampf((hi - lo) / 100.0, 0.0, 1.0), clampf((lo + 10.0) / 20.0, 0.0, 1.0))


## All triangles of all objects, for a ConcavePolygonShape3D.
func collision_faces() -> PackedVector3Array:
	var faces := PackedVector3Array()
	for o in objects:
		for mat_name in o.surfaces:
			faces.append_array(o.surfaces[mat_name])
	return faces
