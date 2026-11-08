## Integration test: pedestrians and traffic in the real P001 scene (Ambient NPCs, GDD step 2).
## Run: godot --headless --path . -s res://tests/integration/p001/street_life_test.gd
extends SceneTree

var _failed := 0
var _passed := 0
var main: Node
var L: StrayStreetLayout


func check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
		print("PASS ", what)
	else:
		_failed += 1
		print("FAIL ", what)


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _sv(p: Vector3) -> Vector2:
	return L.to_street(Vector2(p.x, -p.z))


func _run() -> void:
	main = load("res://src/p001/main.tscn").instantiate()
	root.add_child(main)
	await _frames(30)
	L = main.builder.layout
	var traffic: StrayTraffic = main.traffic
	var peds: StrayPedestrians = main.pedestrians
	var cfg: Dictionary = traffic.cfg

	# Park the player out of the way (west sidewalk, south end) so nothing yields to them.
	var park := L.to_en(L.s_start + 2.0, L.sidewalk_west_outer + 0.8)
	main.player.global_position = StrayStreetLayout.en_to_godot(park.x, park.y, L.ground_z_at(park) + 0.95)
	var start_s: Array[float] = []
	for c in traffic.cars:
		start_s.append(c.s)
	var ped_start: Array[float] = []
	for w in peds.walkers:
		ped_start.append(w.s)
	await _frames(300)  # 5 s

	# --- traffic ----------------------------------------------------------------------------
	check(traffic.cars.size() >= 8, "%d cars spawned" % traffic.cars.size())
	var moved := 0.0
	var worst_height := 0.0
	var min_gap := 1e9
	var right_side := true
	for i in traffic.cars.size():
		var c: StrayTraffic.Car = traffic.cars[i]
		if not c.active:
			continue
		moved += absf(c.s - start_s[i])
		if c.s > L.s_start and c.s < L.s_end:
			var en := L.to_en(c.s, c.v)
			worst_height = maxf(worst_height, absf(c.y - L.road_z(c.s, c.v)))
		if signf(c.v) != signf(c.dir):
			right_side = false  # northbound must use the east (+v) carriageway: driving on the right
		for o in traffic.cars:
			if o != c and o.active and o.lane == c.lane:
				min_gap = minf(min_gap, absf(o.s - c.s) - (o.length + c.length) * 0.5)
	check(moved > 5.0 * 8.0 * 4.0, "cars moved (%.0f m total in 5 s)" % moved)
	check(worst_height < 0.25, "cars sit on the road surface (worst %.3f m)" % worst_height)
	check(min_gap > float(cfg.get("stop_gap", 4.0)) - 1.0, "same-lane gap kept (min %.2f m)" % min_gap)
	check(right_side, "traffic drives on the right")

	# Player steps into the northbound outer lane: the approaching car must stop short.
	var lane_v: float = 5.6
	var p_s := 40.0
	var pen := L.to_en(p_s, lane_v)
	main.player.global_position = StrayStreetLayout.en_to_godot(pen.x, pen.y, L.road_z(p_s, lane_v) + 0.95)
	await _frames(600)  # 10 s
	var nearest := 1e9
	var waiting := 0
	for c in traffic.cars:
		if c.active and absf(c.v - lane_v) < 0.5 and (p_s - c.s) * c.dir > 0.0:
			nearest = minf(nearest, (p_s - c.s) * c.dir - c.length * 0.5)
			if c.speed < 0.3:
				waiting += 1
	check(nearest > 2.0, "approaching car stays clear of the player (%.2f m)" % nearest)
	check(waiting >= 1, "%d car(s) stopped and waiting behind the player" % waiting)

	# --- pedestrians --------------------------------------------------------------------------
	main.player.global_position = StrayStreetLayout.en_to_godot(park.x, park.y, L.ground_z_at(park) + 0.95)
	await _frames(60)
	check(peds.walkers.size() >= 10 and peds.queue.size() >= 3, "%d walkers + %d in the NACHTFLUG queue" % [peds.walkers.size(), peds.queue.size()])
	var on_sidewalk := true
	var walked := 0.0
	for i in peds.walkers.size():
		var w: StrayPedestrians.Walker = peds.walkers[i]
		walked += absf(w.s - ped_start[i])
		var sv := _sv(w.root.global_position)
		if absf(sv.y) < L.kerb_half_width + 0.5 or sv.y < L.facade_v_west + 0.4 or sv.y > L.facade_v_east - 0.4:
			on_sidewalk = false
	check(on_sidewalk, "all walkers stay on the sidewalks, clear of kerb and facades")
	check(walked > 10.0, "walkers moved (%.1f m total)" % walked)
	var min_sep := 1e9
	for a in peds.walkers:
		for b in peds.walkers:
			if a != b:
				min_sep = minf(min_sep, a.root.global_position.distance_to(b.root.global_position))
	check(min_sep > 0.45, "walkers do not overlap (min %.2f m)" % min_sep)

	# Yield: stand right in front of a walker that is under way.
	var w0: StrayPedestrians.Walker = peds.walkers[0]
	var front := L.to_en(w0.s + w0.dir * 1.6, w0.v)
	main.player.global_position = StrayStreetLayout.en_to_godot(front.x, front.y, L.ground_z_at(front) + 0.95)
	await _frames(120)
	var d := Vector2(w0.root.global_position.x, w0.root.global_position.z).distance_to(Vector2(main.player.global_position.x, main.player.global_position.z))
	check(d > 0.6, "walker stops in front of the player (%.2f m)" % d)

	print("RESULT street_life_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
