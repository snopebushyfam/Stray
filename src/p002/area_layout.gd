## Area P002 (Bahnhofsvorplatz / Domplatte, Köln Hbf) layout: plain data + pure math (no nodes).
##
## Source: res://data/p002/P002_Area.json, written by tools/geodata/build_p002.py from Geobasis
## NRW LoD2 + DGM1 and OpenStreetMap. Same local EN frame as P001 (StrayStreetLayout), so both
## areas sit at their real relative positions in one Godot world.
class_name StrayAreaLayout
extends RefCounted

const SCHEMA := "stray.p002.area/1"

var source_dir: String = ""
var lod2_mesh: String = ""
var hbf_en := Vector2.ZERO
var grid_min := Vector2.ZERO
var grid_step: float = 1.0
var nx: int = 0
var ny: int = 0
var z_min: float = 0.0
var z_max: float = 0.0
var heights := PackedFloat32Array()
var bounds_margin: float = 2.0
var lamps: Dictionary = {}
var waste_baskets: Array = []
var ubahn_entrances: Array = []
var ubahn_player: Dictionary = {}
var hbf_main_exit: Dictionary = {}
var spawn_en := Vector2.ZERO
var spawn_dir_en := Vector2(0, 1)
var viewpoints: Array = []


## Loads and parses an area file. Returns null and pushes an error on failure.
static func load_file(path: String) -> StrayAreaLayout:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("STRAY_DIAG area=failed cannot read %s" % path)
		return null
	var a := StrayAreaLayout.new()
	var err := a.parse(text)
	if not err.is_empty():
		push_error("STRAY_DIAG area=failed %s: %s" % [path, err])
		return null
	a.source_dir = path.get_base_dir()
	return a


## Parses area JSON text. Returns "" on success, otherwise an error message.
func parse(text: String) -> String:
	var root: Variant = JSON.parse_string(text)
	if typeof(root) != TYPE_DICTIONARY:
		return "area is not valid JSON"
	if root.get("schema", "") != SCHEMA:
		return "unexpected schema '%s'" % root.get("schema", "")
	lod2_mesh = root.get("lod2_mesh", "")
	hbf_en = StrayStreetLayout._v2(root.get("hbf_en", [0, 0]))
	var g: Dictionary = root.get("height_grid", {})
	grid_min = StrayStreetLayout._v2(g.get("min_en", [0, 0]))
	grid_step = float(g.get("step", 1.0))
	nx = int(g.get("nx", 0))
	ny = int(g.get("ny", 0))
	heights = PackedFloat32Array(g.get("z", []))
	if nx < 2 or ny < 2 or heights.size() != nx * ny:
		return "height grid size mismatch (%d x %d vs %d values)" % [nx, ny, heights.size()]
	z_min = float(g.get("z_min", 0.0))
	z_max = float(g.get("z_max", 0.0))
	bounds_margin = float(root.get("bounds_margin", 2.0))
	lamps = root.get("lamps", {})
	waste_baskets = root.get("waste_baskets", [])
	ubahn_entrances = root.get("ubahn_entrances", [])
	ubahn_player = root.get("ubahn_player", {})
	hbf_main_exit = root.get("hbf_main_exit", {})
	if ubahn_player.is_empty():
		return "missing ubahn_player"
	var sp: Dictionary = root.get("spawn", {})
	spawn_en = StrayStreetLayout._v2(sp.get("en", ubahn_player.get("exit_en", [0, 0])))
	spawn_dir_en = StrayStreetLayout._v2(sp.get("yaw_dir_en", [0, 1]))
	viewpoints = root.get("viewpoints", [])
	return ""


func resolve(relative: String) -> String:
	return source_dir.path_join(relative)


func grid_max() -> Vector2:
	return grid_min + Vector2(nx - 1, ny - 1) * grid_step


## Height (m above the local origin) of grid vertex (i = east index, j = north index), clamped.
func z_at(i: int, j: int) -> float:
	return heights[clampi(j, 0, ny - 1) * nx + clampi(i, 0, nx - 1)]


## Bilinear DGM1 ground height at a local EN point (clamped to the grid).
func ground_z_at(p_en: Vector2) -> float:
	var f := (p_en - grid_min) / grid_step
	var i0 := clampi(int(floor(f.x)), 0, nx - 2)
	var j0 := clampi(int(floor(f.y)), 0, ny - 2)
	var fx := clampf(f.x - i0, 0.0, 1.0)
	var fy := clampf(f.y - j0, 0.0, 1.0)
	return lerpf(lerpf(z_at(i0, j0), z_at(i0 + 1, j0), fx), lerpf(z_at(i0, j0 + 1), z_at(i0 + 1, j0 + 1), fx), fy)


## True when a local EN point lies inside the walkable rectangle (grid minus the margin).
func contains(p_en: Vector2, margin: float = -1.0) -> bool:
	var m := bounds_margin if margin < 0.0 else margin
	var lo := grid_min + Vector2(m, m)
	var hi := grid_max() - Vector2(m, m)
	return p_en.x >= lo.x and p_en.y >= lo.y and p_en.x <= hi.x and p_en.y <= hi.y


## Godot position for a capsule whose bottom sits `clearance` m above the ground at `p_en`.
func stand_position(p_en: Vector2, capsule_half_height: float, clearance: float = 0.05) -> Vector3:
	return StrayStreetLayout.en_to_godot(p_en.x, p_en.y, ground_z_at(p_en) + capsule_half_height + clearance)


## Godot yaw that makes -Z face a horizontal EN direction.
static func yaw_of(dir_en: Vector2) -> float:
	var d := StrayStreetLayout.en_dir_to_godot(dir_en)
	return atan2(-d.x, -d.z)
