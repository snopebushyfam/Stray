## Unit tests: StrayStreetLayout + StrayObjMesh on the committed P001 data (Logic).
## Run: godot --headless --path . -s res://tests/unit/p001/street_layout_test.gd
## (gdUnit4 is not installed yet; this runner prints PASS/FAIL and exits non-zero on failure.)
extends SceneTree

var _failed := 0
var _passed := 0


func check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("FAIL ", what)


func _initialize() -> void:
	test_en_to_godot_is_a_rotation_east_up_minus_north()
	test_layout_loads_with_profile_and_landmarks()
	test_spawn_capsule_bottom_sits_above_sidewalk()
	test_ground_steps_up_at_the_kerb()
	test_lod2_obj_parses_with_outward_normals()
	print("RESULT street_layout_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _layout() -> StrayStreetLayout:
	return StrayStreetLayout.load_file("res://data/p001/P001_Layout.json")


func test_en_to_godot_is_a_rotation_east_up_minus_north() -> void:
	check(StrayStreetLayout.en_to_godot(1, 0, 0) == Vector3(1, 0, 0), "east -> +X")
	check(StrayStreetLayout.en_to_godot(0, 1, 0) == Vector3(0, 0, -1), "north -> -Z")
	check(StrayStreetLayout.en_to_godot(0, 0, 1) == Vector3(0, 1, 0), "up -> +Y")
	var b := StrayStreetLayout.facing_basis(Vector2(0, 1))
	check(b.z.is_equal_approx(Vector3(0, 0, -1)), "facing_basis(+north): local +Z points north")


func test_layout_loads_with_profile_and_landmarks() -> void:
	var L := _layout()
	check(L != null, "layout loads")
	if L == null:
		return
	check(absf(L.street_length() - 150.0) < 5.0, "segment ~150 m")
	check(L.profile.size() >= 40, "profile rows")
	check(L.kiosk.get("label") == "KIOSK" and L.club.get("label") == "NACHTFLUG", "landmark labels")
	check(L.profile_at(L.s_start)[1] - L.profile_at(L.s_end)[1] > 0.2, "road falls towards Friesenplatz")


func test_spawn_capsule_bottom_sits_above_sidewalk() -> void:
	var L := _layout()
	var pos := L.spawn_position(0.9, 0.05)
	check(is_equal_approx(pos.y - 0.9, L.ground_z_at(L.spawn_en) + 0.05), "capsule bottom 5 cm above ground")
	check(L.is_on_sidewalk(L.spawn_en), "spawn on sidewalk")


func test_ground_steps_up_at_the_kerb() -> void:
	var L := _layout()
	var s := 20.0
	var road := L.ground_z_at(L.to_en(s, -L.kerb_half_width + 0.05))
	var walk := L.ground_z_at(L.to_en(s, -L.kerb_half_width - 0.3))
	check(walk - road >= 0.08 and walk - road <= 0.35, "kerb step 8..35 cm (got %.3f)" % (walk - road))


func test_lod2_obj_parses_with_outward_normals() -> void:
	var L := _layout()
	var m := StrayObjMesh.load_file(L.resolve(L.lod2_mesh))
	check(m != null and m.objects.size() > 100, ">100 buildings")
	if m == null:
		return
	var up := 0
	var total := 0
	for o in m.objects:
		if o.surfaces.has("M_LoD2_roof"):
			var t: PackedVector3Array = o.surfaces["M_LoD2_roof"]
			for i in range(0, t.size(), 3):
				# Godot front face is clockwise: outward normal = (c - a) x (b - a).
				var n := (t[i + 2] - t[i]).cross(t[i + 1] - t[i])
				total += 1
				if n.y > 0.0:
					up += 1
	check(total > 0 and up > total * 0.95, "roof normals point up (%d/%d)" % [up, total])
	check(m.aabb.size.y < 80.0 and absf(m.aabb.position.y) < 3.0, "metres, ground near y=0")
