## Unit test (R13 city life): StrayAmbientLife state machines with the real npc_config.json data
## and a fixed seed - state transitions, meetings, KIOSK use, spot reservations, lanes kept free,
## sidewalk bounds, time-of-day profiles, going off stage only far from the player, walking around
## a player who stands on a lane, determinism.
## Run: godot --headless --path . -s res://tests/unit/p001/ambient_life_test.gd
extends SceneTree

var _failed := 0
var _passed := 0
var cfg: Dictionary
var ped: Dictionary
const S_LO := -41.0
const S_HI := 101.0
const FAR_PLAYER := Vector2(-200.0, 0.0)


func check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
		print("PASS ", what)
	else:
		_failed += 1
		print("FAIL ", what)


func _make(seed: int, profile: String = "night") -> StrayAmbientLife:
	var life := StrayAmbientLife.new()
	life.setup(cfg.get("ambient", {}), ped.get("lanes", []), S_LO, S_HI, seed)
	life.set_profile(profile)
	var lanes: Array = ped.get("lanes", [])
	var r := RandomNumberGenerator.new()
	r.seed = seed
	for li in lanes.size():
		var n := int(lanes[li].get("count", 3))
		for k in n:
			life.add_agent(S_LO + (S_HI - S_LO) * (k + r.randf_range(0.1, 0.9)) / float(n), float(lanes[li].v), int(lanes[li].dir), r.randf_range(1.05, 1.55))
	return life


func _initialize() -> void:
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/p001/npc_config.json"))
	ped = cfg.get("pedestrians", {})
	test_states_meetings_and_kiosk_occur()
	test_spots_and_lanes_stay_free()
	test_profiles_follow_clock()
	test_day_profile_no_club_and_offstage_far_from_player()
	test_player_on_lane_is_walked_around()
	test_same_seed_same_street()
	test_many_seeds_no_overlap_no_deadlock()
	test_club_empties_after_switch_to_day()
	print("RESULT ambient_life_test passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func test_states_meetings_and_kiosk_occur() -> void:
	var life := _make(11)
	var met := false
	var kiosk_bought := false
	var double_owner := false
	var simultaneous := {}
	for i in 3000:  # 600 s
		life.update(0.2, FAR_PLAYER)
		var c := life.census()
		for k in c:
			simultaneous[k] = maxi(int(simultaneous.get(k, 0)), int(c[k]))
		for a in life.agents:
			if a.plan == "meet" and a.state == StrayAmbientLife.State.TALKING and a.partner >= 0 \
					and life.agents[a.partner].state == StrayAmbientLife.State.TALKING:
				met = true
			if a.spot.begins_with("kiosk_counter") and a.state == StrayAmbientLife.State.WAITING:
				kiosk_bought = true
		var seen := {}
		for a in life.agents:
			if not a.spot.is_empty():
				if seen.has(a.spot):
					double_owner = true
				seen[a.spot] = true
	for st in ["WALKING", "APPROACHING", "WAITING", "TALKING", "IDLE", "LEAVING"]:
		check(int(life.state_counts.get(st, 0)) > 0, "state %s entered (%d x)" % [st, int(life.state_counts.get(st, 0))])
	check(met, "two passers-by met and talked at the same time")
	check(kiosk_bought, "a KIOSK customer ordered at the counter")
	check(not double_owner, "no spot ever held by two people")
	check(int(simultaneous.get("TALKING", 0)) >= 3 and int(simultaneous.get("WALKING", 0)) + int(simultaneous.get("LEAVING", 0)) + int(simultaneous.get("APPROACHING", 0)) >= 3,
		"different activities at the same time (max talking %d)" % int(simultaneous.get("TALKING", 0)))


func test_spots_and_lanes_stay_free() -> void:
	var life := _make(12)
	var lanes: Array = ped.get("lanes", [])
	var spot_on_lane := ""
	for sid in life.spots:
		var p: Vector2 = life.spots[sid].pos
		for l in lanes:
			if absf(p.y - float(l.v)) < 0.65:
				spot_on_lane = sid
	check(spot_on_lane.is_empty(), "no standing spot on a walking lane (%s)" % spot_on_lane)
	var standing_on_lane := 0
	var off_sidewalk := 0
	var min_sep := 1e9
	for i in 2000:
		life.update(0.2, FAR_PLAYER)
		if i % 10 != 0:
			continue
		for a in life.agents:
			if a.state == StrayAmbientLife.State.OFFSTAGE:
				continue
			if absf(a.v) < 10.6 or absf(a.v) > 18.4 or a.s < S_LO - 0.1 or a.s > S_HI + 0.1:
				off_sidewalk += 1
			if a.state in [StrayAmbientLife.State.TALKING, StrayAmbientLife.State.IDLE] and not a.spot.is_empty():
				for l in lanes:
					if absf(a.v - float(l.v)) < 0.5:
						standing_on_lane += 1
			for o in life.agents:
				if o != a and o.state != StrayAmbientLife.State.OFFSTAGE:
					min_sep = minf(min_sep, Vector2(a.s, a.v).distance_to(Vector2(o.s, o.v)))
	check(standing_on_lane == 0, "standing people never stand on a lane (%d samples)" % standing_on_lane)
	check(off_sidewalk == 0, "everyone stays on the sidewalk band (%d samples outside)" % off_sidewalk)
	check(min_sep > 0.45, "people do not walk into each other (min %.2f m)" % min_sep)


func test_profiles_follow_clock() -> void:
	var rules: Array = cfg.ambient.schedule
	var cases := [["Sa", "14:00", "day"], ["Sa", "20:30", "evening"], ["Sa", "23:10", "night"], ["So", "02:00", "night"],
		["So", "09:00", "sunday_morning"], ["Sa", "06:30", "early"]]
	for c in cases:
		var got := StrayAmbientLife.profile_for(rules, StrayGameClock.parse_hhmm(c[1]), c[0])
		check(got == c[2], "%s %s -> profile %s (%s)" % [c[0], c[1], c[2], got])
	var p: Dictionary = cfg.ambient.profiles
	check(int(p.day.queue) == 0 and int(p.night.queue) > 0, "club queue only in the evening/night")
	check(float(p.night.weights.club) > float(p.day.weights.club) and int(p.early.active) < int(p.night.active),
		"night has more club life, early morning fewer people")


func test_day_profile_no_club_and_offstage_far_from_player() -> void:
	var life := _make(13, "night")
	for i in 1000:
		life.update(0.2, FAR_PLAYER)
	life.set_profile("early")
	var player := Vector2(30.0, -12.0)
	var new_club := 0
	var offstage_near := 0
	var prev := {}
	for a in life.agents:
		prev[a.id] = a.state
	for i in 4000:  # 800 s
		life.update(0.2, player)
		for a in life.agents:
			if a.state != prev[a.id]:
				if a.state == StrayAmbientLife.State.OFFSTAGE and absf(a.s - player.x) < 30.0:
					offstage_near += 1
				if a.state == StrayAmbientLife.State.APPROACHING and a.plan == "club":
					new_club += 1
				prev[a.id] = a.state
	check(life.active_count() <= life.target_active() + 1, "early morning: active people go down to the target (%d / %d)" % [life.active_count(), life.target_active()])
	check(offstage_near == 0, "nobody leaves the scene within 30 m of the player")
	life.set_profile("day")
	var club_day := 0
	for a in life.agents:
		prev[a.id] = a.plan
	for i in 3000:
		life.update(0.2, player)
		for a in life.agents:
			if a.plan == "club" and prev[a.id] != "club":
				club_day += 1  # a new decision to go to the club
			prev[a.id] = a.plan
	check(club_day == 0, "day profile: nobody heads for the club forecourt")
	check(life.active_count() > 6, "day profile: people come back (%d active)" % life.active_count())


func test_player_on_lane_is_walked_around() -> void:
	var life := _make(14)
	var player := Vector2(22.0, -12.68)  # the real spawn, between the two west lanes
	var max_wait := 0.0
	var max_blocked := 0.0
	for i in 3000:
		life.update(0.2, player)
		for a in life.agents:
			max_wait = maxf(max_wait, a.player_wait)
			max_blocked = maxf(max_blocked, a.blocked)
	check(max_wait < 3.0, "people walk around a player standing on the lane (longest wait %.1f s)" % max_wait)
	check(max_blocked < 4.0, "nobody stays stuck behind someone (longest %.1f s)" % max_blocked)


func test_same_seed_same_street() -> void:
	var a := _make(15)
	var b := _make(15)
	for i in 1500:
		a.update(0.2, FAR_PLAYER)
		b.update(0.2, FAR_PLAYER)
	var same := true
	for k in a.agents.size():
		if a.agents[k].state != b.agents[k].state or not is_equal_approx(a.agents[k].s, b.agents[k].s):
			same = false
	check(same, "same seed -> identical street (reproducible tests)")


## Robustness over several seeds with the player standing between the west lanes at the spawn
## (the case that first jammed people behind the player and later made detours meet head-on).
func test_many_seeds_no_overlap_no_deadlock() -> void:
	var worst_sep := 1e9
	var worst_block := 0.0
	for seed in range(20, 28):
		var life := _make(seed)
		for i in 3000:
			life.update(0.2, Vector2(22.0, -12.68))
			for a in life.agents:
				if a.state == StrayAmbientLife.State.OFFSTAGE:
					continue
				worst_block = maxf(worst_block, a.blocked)
				for o in life.agents:
					if a.id < o.id and o.state != StrayAmbientLife.State.OFFSTAGE:
						worst_sep = minf(worst_sep, Vector2(a.s, a.v).distance_to(Vector2(o.s, o.v)))
	check(worst_sep > 0.45, "8 seeds x 10 min: people never overlap (min %.2f m)" % worst_sep)
	check(worst_block < 4.0, "8 seeds x 10 min: nobody stuck (longest %.1f s)" % worst_block)


## Regression (R13 evidence): after a clock jump from night to the afternoon the club guests stood
## on at the closed club for their full stay (up to 3.5 min). Now they leave within 20 s.
func test_club_empties_after_switch_to_day() -> void:
	var life := _make(16, "night")
	for i in 1500:
		life.update(0.2, FAR_PLAYER)
	var at_club := 0
	for a in life.agents:
		if a.plan == "club":
			at_club += 1
	life.set_profile("day")
	for i in 125:  # 25 s
		life.update(0.2, FAR_PLAYER)
	var left := 0
	for a in life.agents:
		if a.plan == "club" and a.state in [StrayAmbientLife.State.WAITING, StrayAmbientLife.State.TALKING, StrayAmbientLife.State.APPROACHING]:
			left += 1
	check(at_club > 0 and left == 0, "after night -> day the club guests (%d) have left within 25 s (%d remain)" % [at_club, left])
