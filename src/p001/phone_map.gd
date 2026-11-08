## Map app: real LoD2 footprints (north up) with the street, landmarks and the player.
## Drawn with Control._draw from data/p001/LoD2_P001_Hohenzollernring.json (ground rings).
class_name StrayPhoneMap
extends Control

var footprints: Array[PackedVector2Array] = []  # local EN metres
var street_poly := PackedVector2Array()
var markers: Array[Dictionary] = []  # {en: Vector2, color: Color, label: String}
var player_en := Vector2.ZERO
var player_dir_en := Vector2(0, 1)
var bounds := Rect2()


## Loads footprints and builds the street outline from the layout.
func setup(layout: StrayStreetLayout, lod2_json_path: String) -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(lod2_json_path))
	if typeof(data) == TYPE_DICTIONARY:
		for b in data.get("buildings", []):
			for ring in b.get("ground_rings_local", []):
				var poly := PackedVector2Array()
				for p in ring:
					poly.append(Vector2(p[0], p[1]))
				if poly.size() >= 3:
					footprints.append(poly)
	var w := layout.sidewalk_west_outer
	var e := layout.sidewalk_east_outer
	for sv in [Vector2(layout.s_start, w), Vector2(layout.s_end, w), Vector2(layout.s_end, e), Vector2(layout.s_start, e)]:
		street_poly.append(layout.to_en(sv.x, sv.y))
	bounds = Rect2(layout.to_en(layout.s_start, 0.0), Vector2.ZERO)
	for sv in [Vector2(layout.s_start - 25, w - 25), Vector2(layout.s_end + 25, e + 25), Vector2(layout.s_start - 25, e + 25), Vector2(layout.s_end + 25, w - 25)]:
		bounds = bounds.expand(layout.to_en(sv.x, sv.y))


func _to_px(en: Vector2) -> Vector2:
	var sc := minf(size.x / bounds.size.x, size.y / bounds.size.y)
	var off := (size - bounds.size * sc) * 0.5
	return Vector2((en.x - bounds.position.x) * sc + off.x, (bounds.end.y - en.y) * sc + off.y)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.08, 0.1))
	var sp := PackedVector2Array()
	for p in street_poly:
		sp.append(_to_px(p))
	draw_colored_polygon(sp, Color(0.25, 0.26, 0.3))
	for poly in footprints:
		var pp := PackedVector2Array()
		for p in poly:
			pp.append(_to_px(p))
		if Geometry2D.triangulate_polygon(pp).size() > 0:
			draw_colored_polygon(pp, Color(0.42, 0.40, 0.36))
		pp.append(pp[0])
		draw_polyline(pp, Color(0.2, 0.19, 0.17), 1.0)
	var font := ThemeDB.fallback_font
	for m in markers:
		var p := _to_px(m.en)
		draw_circle(p, 6.0, m.color)
		draw_string(font, p + Vector2(8, 5), m.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	var pp := _to_px(player_en)
	var d := Vector2(player_dir_en.x, -player_dir_en.y).normalized()
	var side := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([pp + d * 11.0, pp - d * 6.0 + side * 6.0, pp - d * 6.0 - side * 6.0]), Color(0.2, 0.75, 1.0))
	draw_string(font, Vector2(8, 16), "N ↑  ·  Hohenzollernring", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.7))
