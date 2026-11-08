## Prototype 001 street layout: plain data + pure math (no nodes).
##
## Source: res://data/p001/P001_Layout.json, written by tools/geodata/build_p001.py from
## Geobasis NRW LoD2 + DGM1 and OpenStreetMap. Design: docs/STRAY_GDD.md (Prototype 001),
## docs/TECHNICAL_PLAN.md. This is the GDScript twin of Unreal/Source/Stray/.../StrayStreetLayout.
##
## Coordinates
## - Local "EN" frame (data): metres, x = East, y = North, z = Up (right-handed).
## - Godot: metres, Y up, right-handed. East -> +X, Up -> +Y, North -> -Z (a pure rotation).
class_name StrayStreetLayout
extends RefCounted

const SCHEMA := "stray.p001.layout/2"
const MEDIAN_RISE := 0.12
const KERB_STONE_WIDTH := 0.18

var source_dir: String = ""
var lod2_mesh: String = ""
var terrain_mesh: String = ""
var utm_origin := Vector3.ZERO

# Street frame: s along the axis (towards Friesenplatz), v across (+ = east side).
var origin_en := Vector2.ZERO
var bearing_deg: float = 0.0
var s_start: float = 0.0
var s_end: float = 0.0
var median_half_width: float = 0.6
var lane_divider_offset: float = 3.7
var carriageway_half_width: float = 7.0
var kerb_half_width: float = 9.0
var kerb_height: float = 0.15
var sidewalk_west_outer: float = -19.0
var sidewalk_east_outer: float = 22.0

## Profile rows: [s, road_centre, edge_w, edge_e, walk_w, walk_e, facade_w, facade_e] (metres).
var profile: Array[PackedFloat64Array] = []
var facade_v_west: float = -16.5
var facade_v_east: float = 19.0

var ground_min_en := Vector2.ZERO
var ground_max_en := Vector2.ZERO
var ground_z: float = -1.0

var lamps: Dictionary = {}
var shopfronts: Dictionary = {}
var upper_windows: Dictionary = {}
var kiosk: Dictionary = {}
var club: Dictionary = {}
var spawn_en := Vector2.ZERO
var spawn_dir_en := Vector2(0, 1)
var viewpoints: Array = []
var lighting: Dictionary = {}
## OSM street furniture + procedural parked cars (see tools/geodata/build_p001.py).
var furniture: Dictionary = {}


## Converts local EN(U) metres to Godot space.
static func en_to_godot(east: float, north: float, up: float) -> Vector3:
	return Vector3(east, up, -north)


## Converts a horizontal EN direction to a normalised Godot direction (y = 0).
static func en_dir_to_godot(dir_en: Vector2) -> Vector3:
	return Vector3(dir_en.x, 0.0, -dir_en.y).normalized()


## Basis whose local +Z points along a horizontal EN direction (front of signs, panels).
static func facing_basis(dir_en: Vector2) -> Basis:
	return Basis.looking_at(-en_dir_to_godot(dir_en), Vector3.UP)


## Loads and parses a layout file. Returns null and pushes an error on failure.
static func load_file(path: String) -> StrayStreetLayout:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("STRAY_DIAG layout=failed cannot read %s (err %d)" % [path, FileAccess.get_open_error()])
		return null
	var layout := StrayStreetLayout.new()
	var err := layout.parse(text)
	if not err.is_empty():
		push_error("STRAY_DIAG layout=failed %s: %s" % [path, err])
		return null
	layout.source_dir = path.get_base_dir()
	return layout


## Parses layout JSON text. Returns "" on success, otherwise an error message.
func parse(text: String) -> String:
	var root: Variant = JSON.parse_string(text)
	if typeof(root) != TYPE_DICTIONARY:
		return "layout is not valid JSON"
	if root.get("schema", "") != SCHEMA:
		return "unexpected schema '%s'" % root.get("schema", "")
	lod2_mesh = root.get("lod2_mesh", "")
	terrain_mesh = root.get("terrain_mesh", "")
	if lod2_mesh.is_empty():
		return "missing lod2_mesh"
	var o: Array = root.get("georef", {}).get("local_origin_utm", [0, 0, 0])
	utm_origin = Vector3(o[0], o[1], o[2])

	var st: Dictionary = root.get("street", {})
	if not st.has("origin_en"):
		return "missing street.origin_en"
	origin_en = _v2(st["origin_en"])
	bearing_deg = st.get("bearing_deg", 0.0)
	s_start = st.get("s_start", 0.0)
	s_end = st.get("s_end", 0.0)
	median_half_width = st.get("median_half_width", median_half_width)
	lane_divider_offset = st.get("lane_divider_offset", lane_divider_offset)
	carriageway_half_width = st.get("carriageway_half_width", carriageway_half_width)
	kerb_half_width = st.get("kerb_half_width", kerb_half_width)
	kerb_height = st.get("kerb_height", kerb_height)
	sidewalk_west_outer = st.get("sidewalk_west_outer", sidewalk_west_outer)
	sidewalk_east_outer = st.get("sidewalk_east_outer", sidewalk_east_outer)
	if s_end - s_start <= 1.0:
		return "street segment is degenerate"

	var prof: Dictionary = root.get("profile", {})
	for row in prof.get("samples", []):
		var r := PackedFloat64Array(row)
		if r.size() >= 6:
			if r.size() < 8:
				r.append(r[4])
				r.append(r[5])
			profile.append(r)
	profile.sort_custom(func(a, b): return a[0] < b[0])
	var fv: Array = prof.get("facade_v", [])
	if fv.size() == 2:
		facade_v_west = fv[0]
		facade_v_east = fv[1]

	var gp: Dictionary = root.get("ground_plane", {})
	ground_min_en = _v2(gp.get("min_en", [0, 0]))
	ground_max_en = _v2(gp.get("max_en", [0, 0]))
	ground_z = gp.get("z", ground_z)

	lamps = root.get("lamps", {})
	shopfronts = root.get("shopfronts", {})
	upper_windows = root.get("upper_windows", {})
	kiosk = root.get("kiosk", {})
	club = root.get("club", {})
	if kiosk.is_empty() or club.is_empty():
		return "missing kiosk or club"
	var sp: Dictionary = root.get("spawn", {})
	if not sp.has("en"):
		return "missing spawn"
	spawn_en = _v2(sp["en"])
	spawn_dir_en = _v2(sp.get("yaw_dir_en", [0, 1]))
	viewpoints = root.get("viewpoints", [])
	furniture = root.get("furniture", {})
	lighting = root.get("lighting", {})
	return ""


## Absolute/res path of a data file named in the layout.
func resolve(relative: String) -> String:
	return source_dir.path_join(relative)


func axis_en() -> Vector2:
	var b := deg_to_rad(bearing_deg)
	return Vector2(sin(b), cos(b))


func right_en() -> Vector2:
	var u := axis_en()
	return Vector2(u.y, -u.x)


## Street frame (s, v) -> local EN metres.
func to_en(s: float, v: float) -> Vector2:
	return origin_en + axis_en() * s + right_en() * v


## Local EN -> street frame (s, v).
func to_street(p_en: Vector2) -> Vector2:
	var d := p_en - origin_en
	return Vector2(d.dot(axis_en()), d.dot(right_en()))


func street_length() -> float:
	return s_end - s_start


## Profile row at s, linearly interpolated and clamped. Flat fallback without a profile.
func profile_at(s: float) -> PackedFloat64Array:
	if profile.is_empty():
		return PackedFloat64Array([s, 0.0, 0.0, 0.0, kerb_height, kerb_height, kerb_height, kerb_height])
	if s <= profile[0][0]:
		return profile[0]
	if s >= profile[-1][0]:
		return profile[-1]
	var i := 1
	while profile[i][0] < s:
		i += 1
	var a := profile[i - 1]
	var b := profile[i]
	var t := (s - a[0]) / maxf(b[0] - a[0], 1e-6)
	var out := PackedFloat64Array()
	out.resize(8)
	out[0] = s
	for k in range(1, 8):
		out[k] = lerpf(a[k], b[k], t)
	return out


## Carriageway height at (s, v): linear from the centre to the gutter on that side.
func road_z(s: float, v: float) -> float:
	var p := profile_at(s)
	var t := clampf(absf(v) / maxf(kerb_half_width, 1e-6), 0.0, 1.0)
	return lerpf(p[1], p[2] if v < 0.0 else p[3], t)


## Sidewalk height at (s, v) beyond the kerb: kerb value -> facade value (cross-fall).
func sidewalk_z(s: float, v: float) -> float:
	var p := profile_at(s)
	var kerb := kerb_half_width + KERB_STONE_WIDTH
	if v < 0.0:
		var tw := clampf((-v - kerb) / maxf(-facade_v_west - kerb, 1e-6), 0.0, 1.0)
		return lerpf(p[4], p[6], tw)
	var te := clampf((v - kerb) / maxf(facade_v_east - kerb, 1e-6), 0.0, 1.0)
	return lerpf(p[5], p[7], te)


## Walkable surface height at a local EN point (sidewalk, median or carriageway).
func ground_z_at(p_en: Vector2) -> float:
	var sv := to_street(p_en)
	if absf(sv.y) >= kerb_half_width:
		return sidewalk_z(sv.x, sv.y)
	if absf(sv.y) <= median_half_width:
		return profile_at(sv.x)[1] + MEDIAN_RISE
	return road_z(sv.x, sv.y)


## True when a local EN point lies on a sidewalk inside the segment.
func is_on_sidewalk(p_en: Vector2) -> bool:
	var sv := to_street(p_en)
	if sv.x < s_start or sv.x > s_end:
		return false
	return (sv.y >= sidewalk_west_outer and sv.y <= -kerb_half_width) \
		or (sv.y >= kerb_half_width and sv.y <= sidewalk_east_outer)


## Godot position for a capsule whose bottom sits `clearance` m above the ground at the spawn.
func spawn_position(capsule_half_height: float, clearance: float = 0.05) -> Vector3:
	var g := ground_z_at(spawn_en)
	return en_to_godot(spawn_en.x, spawn_en.y, g + capsule_half_height + clearance)


## Godot yaw (radians, rotation about +Y) that makes -Z face the spawn direction.
func spawn_yaw() -> float:
	var d := en_dir_to_godot(spawn_dir_en)
	return atan2(-d.x, -d.z)


static func _v2(a: Array) -> Vector2:
	return Vector2(a[0], a[1])
