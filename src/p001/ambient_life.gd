## R13 city life: behaviour of the ambient pedestrians as small state machines (pure logic, no nodes).
##
## Positions are street-frame (s along, v across) like StrayStreetLayout. Agents walk on the existing
## directional sidewalk lanes and only step sideways at their destination, so lanes never carry
## oncoming walkers and standing people never stand in a lane. Destinations are checked spots from
## npc_config.json ("ambient"): meeting pairs, groups in front of shops, the NACHTFLUG forecourt,
## the KIOSK counter/waiting/talking spots and lookout spots. Every spot is reserved by one agent.
##
## Plans (what an agent decides to do next, weighted by the time-of-day profile):
##   pass    walk on to the end of the block (there: turn, or go off stage if fewer people are wanted)
##   linger  stand at a lookout spot, look around (IDLE), walk on
##   meet    two passers-by on the same side meet at a pair of spots, talk, part in opposite directions
##   group   join a group spot in front of a shop; talk while others are there, wait while alone
##   club    the same at the NACHTFLUG forecourt (west side)
##   kiosk   KIOSK customer: wait if the counter is taken, order at the counter, walk on
## States: WALKING, APPROACHING (to a spot), WAITING, TALKING, IDLE, LEAVING, OFFSTAGE (hidden at a
## street end, only where the player is far away - nobody vanishes in front of the camera).
## Deterministic for a given seed (tests). Cost: neighbour checks only within 3 m on the same side
## (~0.2 ms per frame for 15 people on the cloud CPU, docs/R13_CITY_LIFE.md).
class_name StrayAmbientLife
extends RefCounted

enum State { WALKING, APPROACHING, WAITING, TALKING, IDLE, LEAVING, OFFSTAGE }
const STATE_NAMES := ["WALKING", "APPROACHING", "WAITING", "TALKING", "IDLE", "LEAVING", "OFFSTAGE"]


class Agent:
	var id := 0
	var side := 1  # -1 west sidewalk, +1 east sidewalk
	var s := 0.0
	var v := 0.0
	var dir := 1  # travel direction along s on the lanes
	var speed := 1.3
	var cur_speed := 0.0
	var state := State.WALKING
	var plan := "pass"
	var route: Array[Vector2] = []
	var timer := 0.0
	var spot := ""
	var partner := -1
	var anim := "walk"  # walk | idle | talk
	var face := Vector2(1, 0)  # facing (street frame), turned smoothly towards face_target
	var face_target := Vector2(1, 0)
	var base_face := Vector2(1, 0)
	var talk_timer := 0.0
	var look_timer := 0.0
	var blocked := 0.0
	var player_wait := 0.0
	var blocked_by_player := false
	var yielding := false
	var block_pos := Vector2.ZERO


var cfg: Dictionary = {}
var lanes: Array = []
var s_lo := 0.0
var s_hi := 0.0
var agents: Array[Agent] = []
var spots: Dictionary = {}  # id -> {pos: Vector2, group: String, face: Vector2}
var groups: Dictionary = {}  # id -> {kind: String, slots: Array[String], center: Vector2}
var owner: Dictionary = {}  # spot id -> agent id
var profile_name := ""
var profile: Dictionary = {}
## Number of entries into each state since setup (tests, diagnostics).
var state_counts: Dictionary = {}
var rng := RandomNumberGenerator.new()
var _balance_in := 0.0


## `p_cfg`: npc_config.json "ambient"; `p_lanes`: pedestrians lanes [{v, dir}]; s range of the block.
func setup(p_cfg: Dictionary, p_lanes: Array, p_s_lo: float, p_s_hi: float, seed: int) -> void:
	cfg = p_cfg
	lanes = p_lanes
	s_lo = p_s_lo
	s_hi = p_s_hi
	rng.seed = seed
	for n in STATE_NAMES:
		state_counts[n] = 0
	var gdefs: Dictionary = cfg.get("groups", {})
	for gid in gdefs:
		var g: Dictionary = gdefs[gid]
		var slots: Array[String] = []
		var center := Vector2.ZERO
		var raw: Array = g.get("slots", [])
		for i in raw.size():
			var sid := "%s_%d" % [gid, i]
			var p := Vector2(float(raw[i][0]), float(raw[i][1]))
			slots.append(sid)
			center += p
			spots[sid] = {"pos": p, "group": gid}
		center /= maxf(raw.size(), 1)
		var face := Vector2.ZERO
		if g.has("face"):
			face = Vector2(float(g.face[0]), float(g.face[1])).normalized()
		for sid in slots:
			var f := face
			if f == Vector2.ZERO:
				f = (center - (spots[sid].pos as Vector2)).normalized() if slots.size() > 1 else Vector2(0, signf((spots[sid].pos as Vector2).y))
			spots[sid]["face"] = f
		groups[gid] = {"kind": String(g.get("kind", "group")), "slots": slots, "center": center,
			"priority": float(g.get("priority", 0.0))}
	set_profile(String(cfg.get("default_profile", "night")))


## Picks the activity profile for a clock time: first rule whose weekday (optional) and hour window match.
static func profile_for(rules: Array, minutes: float, weekday: String) -> String:
	var m := fposmod(minutes, 1440.0)
	for r in rules:
		if r.has("weekday") and String(r.weekday) != weekday:
			continue
		var a := StrayGameClock.parse_hhmm(String(r.get("from", "00:00")))
		var b := StrayGameClock.parse_hhmm(String(r.get("until", "24:00")))
		if (a <= b and m >= a and m < b) or (a > b and (m >= a or m < b)):
			return String(r.profile)
	return ""


func set_profile(p_name: String) -> void:
	var all: Dictionary = cfg.get("profiles", {})
	if p_name.is_empty() or not all.has(p_name) or p_name == profile_name:
		return
	profile_name = p_name
	profile = all[p_name]
	# Activities the new time of day does not have (e.g. the club forecourt in the afternoon) end
	# calmly within 5-20 s: people finish their conversation and walk on (nobody vanishes).
	var w: Dictionary = profile.get("weights", {})
	var mx: Dictionary = profile.get("max", {})
	for a in agents:
		if a.plan in ["club", "group", "kiosk", "linger", "meet"] and (float(w.get(a.plan, 1.0)) <= 0.0 or int(mx.get(a.plan, 99)) <= 0):
			if a.state == State.APPROACHING:
				_leave(a)
			elif a.state in [State.WAITING, State.TALKING, State.IDLE]:
				a.timer = minf(a.timer, rng.randf_range(5.0, 20.0))


func target_active() -> int:
	return int(profile.get("active", agents.size()))


func active_count() -> int:
	var n := 0
	for a in agents:
		if a.state != State.OFFSTAGE:
			n += 1
	return n


func add_agent(s: float, v: float, dir: int, speed: float) -> Agent:
	var a := Agent.new()
	a.id = agents.size()
	a.side = 1 if v > 0.0 else -1
	a.s = s
	a.v = v
	a.dir = dir
	a.speed = speed
	a.face = Vector2(dir, 0)
	a.face_target = a.face
	agents.append(a)
	_walk_on(a, rng.randf_range(5.0, 40.0))
	return a


## Runs the simulation for `seconds` before the first frame, so the street starts mid-life.
func warm_up(seconds: float, player_sv: Vector2) -> void:
	var t := 0.0
	while t < seconds:
		update(0.2, player_sv)
		t += 0.2


func update(dt: float, player_sv: Vector2) -> void:
	_balance_in -= dt
	if _balance_in <= 0.0:
		_balance_in = 1.0
		_balance(player_sv)
	for a in agents:
		match a.state:
			State.OFFSTAGE:
				continue
			State.WALKING, State.APPROACHING, State.LEAVING:
				_move(a, dt, player_sv)
			_:
				_stand(a, dt)
		_turn(a, dt)


# --- movement ---------------------------------------------------------------------------------

func _lane_v(side: int, dir: int, near_v: float) -> float:
	var best := near_v
	var best_d := 1e9
	for l in lanes:
		var lv := float(l["v"])
		if int(l["dir"]) == dir and signf(lv) == float(side) and absf(lv - near_v) < best_d:
			best = lv
			best_d = absf(lv - near_v)
	return best


## Route over the lanes to `to` (street frame): step onto the lane, walk along it, step aside.
func _route_to(a: Agent, to: Vector2) -> void:
	a.route.clear()
	var ds := to.x - a.s
	if absf(ds) < 1.0:
		a.route.append(to)
		return
	a.dir = 1 if ds > 0.0 else -1
	var lv := _lane_v(a.side, a.dir, a.v)
	a.route.append(Vector2(a.s + a.dir * 0.6, lv))
	a.route.append(Vector2(to.x - a.dir * 0.6, lv))
	a.route.append(to)


func _move(a: Agent, dt: float, psv: Vector2) -> void:
	if a.route.is_empty():
		_arrive(a)
		return
	var pos := Vector2(a.s, a.v)
	var to := a.route[0] - pos
	var dist := to.length()
	if dist < 0.04:
		a.route.pop_front()
		if a.route.is_empty():
			_arrive(a)
		return
	var dirv := to / dist
	var along := absf(dirv.x) > 0.7
	var want := a.speed if along else minf(a.speed, 0.8)
	if a.route.size() == 1 and a.state == State.APPROACHING:
		want = minf(want, maxf(0.3, dist * 1.2))  # slow down into the spot
	a.yielding = false
	var lim := _limit(a, pos, dirv, psv)
	if lim <= 0.01 and not a.yielding:
		a.blocked += dt
		a.player_wait = a.blocked if a.blocked_by_player else 0.0
		# Someone stands in the way (the player or another person): walk around them; on a
		# sideways step skip that step; if they stand on one's own spot, give the spot up.
		if a.blocked > 1.2:
			var resolved := false
			if along:
				resolved = _detour(a, a.block_pos, signf(dirv.x))
			elif a.route.size() > 1:
				# sideways step blocked: join the lane 1.5 m further along instead
				var ds := signf(a.route[1].x - a.route[0].x)
				a.route[0] = a.route[0] + Vector2((ds if ds != 0.0 else float(a.dir)) * 1.5, 0.0)
				resolved = true
			elif a.state != State.APPROACHING:
				a.route.clear()  # just strolling: end this stretch here and decide anew
				resolved = true
			elif a.blocked > 3.0:
				_leave(a)
				resolved = true
			if resolved:
				a.blocked = 0.0
				a.player_wait = 0.0
				return
	else:
		a.blocked = 0.0
		a.player_wait = 0.0
	want = minf(want, lim)
	a.cur_speed = move_toward(a.cur_speed, want, (2.5 if want > a.cur_speed else 4.0) * dt)
	var step := minf(a.cur_speed * dt, dist)
	a.s += dirv.x * step
	a.v += dirv.y * step
	if a.cur_speed > 0.05:
		a.face_target = dirv
	a.anim = "walk" if a.cur_speed > 0.15 else "idle"


## Walk around an obstacle `obs` (street frame) that blocks the lane in direction `d` (+1/-1):
## 1.1 m to the side (fixed side per direction) inside the sidewalk band, then on along the remaining route (the destination
## is always kept). False if there is no room on either side.
func _detour(a: Agent, obs: Vector2, d: float) -> bool:
	var band: Array = cfg.get("sidewalk_band_east" if a.side > 0 else "sidewalk_band_west", [10.6, 18.3] if a.side > 0 else [-16.2, -10.6])
	var lo := minf(float(band[0]), float(band[1]))
	var hi := maxf(float(band[0]), float(band[1]))
	# fixed passing side: northbound (+s) towards the road, southbound towards the facades, so two
	# people walking around the same person from both directions never meet head-on
	var first := obs.y - float(a.side) * 1.1 * d
	var second := obs.y + float(a.side) * 1.1 * d
	var dv := first if first >= lo and first <= hi else second
	if dv < lo or dv > hi:
		return false
	var route: Array[Vector2] = [Vector2(obs.x - d * 0.9, dv), Vector2(obs.x + d * 1.3, dv)]
	for i in a.route.size():
		var p := a.route[i]
		if (p.x - obs.x) * d > 1.3 or i == a.route.size() - 1:
			route.append(p)
	a.route = route
	return true


## Speed limit from the player and other people in front (along the walking direction). Sets
## `block_pos` / `blocked_by_player` when it returns 0 (used by _detour).
func _limit(a: Agent, pos: Vector2, dirv: Vector2, psv: Vector2) -> float:
	var lim := 1e9
	var yr: float = cfg.get("yield_radius", 1.4)
	var rel := psv - pos
	var ahead := rel.dot(dirv)
	a.blocked_by_player = false
	if ahead > 0.0 and ahead < yr + 0.6 and absf(rel.cross(dirv)) < 0.8:
		a.block_pos = psv
		a.blocked_by_player = true
		return 0.0
	if a.blocked > 6.0:
		return lim  # no room to walk around for 6 s: squeeze past (never a permanent deadlock)
	var gap: float = cfg.get("follow_gap", 1.6)
	# Stepping sideways across lanes: people walking on any lane this step crosses have right of
	# way (wait at the edge until they have passed; not counted as blocked).
	if absf(dirv.x) <= 0.7 and not a.route.is_empty():
		var join: Vector2 = a.route[0]
		var v_lo := minf(pos.y, join.y) - 0.5
		var v_hi := maxf(pos.y, join.y) + 0.5
		for o in agents:
			if o == a or o.side != a.side or o.state == State.OFFSTAGE or o.cur_speed < 0.1 or absf(o.face_target.x) < 0.7:
				continue
			if o.v > v_lo and o.v < v_hi and absf(o.v - pos.y) > 0.3 and absf(o.s - pos.x) < 2.6 \
					and (pos.x - o.s) * signf(o.face_target.x) > -0.6:
				a.yielding = true
				return 0.0
	var final_group := String(spots[a.spot].group) if a.route.size() == 1 and not a.spot.is_empty() else ""
	for o in agents:
		if o == a or o.side != a.side or o.state == State.OFFSTAGE or absf(o.s - pos.x) > 3.0:
			continue
		if not final_group.is_empty() and not o.spot.is_empty() and String(spots[o.spot].group) == final_group:
			continue  # stepping into one's own group: the others make room by standing still
		rel = Vector2(o.s, o.v) - pos
		ahead = rel.dot(dirv)
		# personal space: two people converging side by side - the later one (higher id) waits
		if rel.length() < 0.6 and ahead > -0.2 and o.id < a.id:
			a.block_pos = Vector2(o.s, o.v)
			return 0.0
		if ahead <= 0.0 or ahead > gap or absf(rel.cross(dirv)) > 0.6:
			continue
		var same_way := o.cur_speed > 0.1 and o.face_target.dot(dirv) > 0.5
		if same_way and ahead > 0.9:
			lim = minf(lim, o.cur_speed * clampf((ahead - 0.9) / 0.8, 0.0, 1.0))  # stopped at 0.9 m
		elif ahead < 1.0:
			a.block_pos = Vector2(o.s, o.v)
			lim = 0.0
	return lim


func _turn(a: Agent, dt: float) -> void:
	var ang := a.face.angle_to(a.face_target)
	var max_step := 3.0 * dt
	a.face = a.face.rotated(clampf(ang, -max_step, max_step))


# --- standing ---------------------------------------------------------------------------------

func _group_present(a: Agent) -> int:
	if a.spot.is_empty():
		return 0
	var n := 0
	for sid in (groups[spots[a.spot].group].slots as Array):
		if sid != a.spot and owner.has(sid):
			var o := agents[int(owner[sid])]
			if o.state in [State.WAITING, State.TALKING, State.IDLE]:
				n += 1
	return n


func _stand(a: Agent, dt: float) -> void:
	a.cur_speed = 0.0
	a.timer -= dt
	var d: Dictionary = cfg.get("durations", {})
	match a.plan:
		"kiosk":
			if a.spot.begins_with("kiosk_wait"):
				var counter := _free_slot("kiosk_counter")
				if not counter.is_empty():
					_release(a)
					_reserve(a, counter)
					_set_state(a, State.APPROACHING)
					_route_to(a, spots[counter].pos)
					return
		"meet":
			if a.state == State.WAITING:
				var p := agents[a.partner] if a.partner >= 0 else null
				if p and p.state == State.WAITING and p.partner == a.id:
					var talk := rng.randf_range(_r(d, "meet", 0), _r(d, "meet", 1))
					for x in [a, p]:
						_set_state(x, State.TALKING)
						x.timer = talk
				elif a.timer <= 0.0:
					_leave(a)
				return
		"group", "club":
			var others := _group_present(a)
			if others > 0 and a.state != State.TALKING:
				_set_state(a, State.TALKING)
			elif others == 0 and a.state == State.TALKING:
				_set_state(a, State.WAITING)
	if a.state == State.TALKING:
		a.talk_timer -= dt
		if a.talk_timer <= 0.0:
			# speaker / listener alternate calmly (no constant gesturing)
			a.anim = "idle" if a.anim == "talk" else "talk"
			a.talk_timer = rng.randf_range(_r(d, "talk_swap", 0), _r(d, "talk_swap", 1))
	elif a.state in [State.IDLE, State.WAITING] and not a.spot.begins_with("kiosk_counter"):
		a.look_timer -= dt
		if a.look_timer <= 0.0:
			a.look_timer = rng.randf_range(_r(d, "look", 0), _r(d, "look", 1))
			a.face_target = a.base_face.rotated(deg_to_rad(rng.randf_range(-45.0, 45.0)))
	if a.timer <= 0.0:
		_leave(a)


static func _r(d: Dictionary, key: String, i: int) -> float:
	var defaults := {"meet": [20.0, 45.0], "group": [60.0, 160.0], "club": [80.0, 220.0], "linger": [10.0, 28.0],
		"kiosk_buy": [6.0, 11.0], "kiosk_wait": [25.0, 25.0], "meet_wait": [40.0, 40.0], "leave": [8.0, 30.0],
		"talk_swap": [5.0, 12.0], "look": [4.0, 9.0]}
	return float(d.get(key, defaults.get(key, [5.0, 10.0]))[i])


# --- plans ------------------------------------------------------------------------------------

func _set_state(a: Agent, st: State) -> void:
	if a.state == st:
		return
	a.state = st
	state_counts[STATE_NAMES[st]] = int(state_counts.get(STATE_NAMES[st], 0)) + 1
	match st:
		State.TALKING:
			a.anim = "talk" if rng.randf() < 0.5 else "idle"
			a.talk_timer = rng.randf_range(2.0, 8.0)
		State.IDLE, State.WAITING:
			a.anim = "idle"
			a.look_timer = rng.randf_range(2.0, 6.0)
		State.WALKING, State.APPROACHING, State.LEAVING:
			a.anim = "walk"


func _free_slot(gid: String) -> String:
	if not groups.has(gid):
		return ""
	for sid in (groups[gid].slots as Array):
		if not owner.has(sid):
			return sid
	return ""


func _reserve(a: Agent, sid: String) -> void:
	owner[sid] = a.id
	a.spot = sid


func _release(a: Agent) -> void:
	if not a.spot.is_empty() and owner.get(a.spot, -1) == a.id:
		owner.erase(a.spot)
	a.spot = ""


func _arrive(a: Agent) -> void:
	a.cur_speed = 0.0
	var d: Dictionary = cfg.get("durations", {})
	if a.state == State.APPROACHING and not a.spot.is_empty():
		a.base_face = spots[a.spot].face
		a.face_target = a.base_face
		match a.plan:
			"linger":
				_set_state(a, State.IDLE)
				a.timer = rng.randf_range(_r(d, "linger", 0), _r(d, "linger", 1))
			"kiosk":
				if a.spot.begins_with("kiosk_wait"):
					_set_state(a, State.WAITING)
					a.timer = _r(d, "kiosk_wait", 0)
				else:
					_set_state(a, State.WAITING)
					a.anim = "talk"  # ordering at the window
					a.talk_timer = 1e9
					a.timer = rng.randf_range(_r(d, "kiosk_buy", 0), _r(d, "kiosk_buy", 1))
			"meet":
				_set_state(a, State.WAITING)
				a.timer = _r(d, "meet_wait", 0)
			_:
				_set_state(a, State.WAITING)
				var key := "club" if a.plan == "club" else "group"
				a.timer = rng.randf_range(_r(d, key, 0), _r(d, key, 1)) * float(profile.get("stay_scale", 1.0))
		return
	if a.s <= s_lo + 0.5 or a.s >= s_hi - 0.5:
		_at_end(a)
	else:
		_choose_plan(a)


func _leave(a: Agent) -> void:
	var partner := a.partner
	_release(a)
	a.partner = -1
	_set_state(a, State.LEAVING)
	a.plan = "leave"
	var dir := a.dir if rng.randf() < 0.5 else -a.dir
	if partner >= 0:
		var p := agents[partner]
		if p.state == State.LEAVING:
			dir = -p.dir  # partners part in opposite directions
	if (dir > 0 and a.s > s_hi - 6.0) or (dir < 0 and a.s < s_lo + 6.0):
		dir = -dir
	var dist := rng.randf_range(_r(cfg.get("durations", {}), "leave", 0), _r(cfg.get("durations", {}), "leave", 1))
	var to_s := clampf(a.s + dir * dist, s_lo, s_hi)
	a.dir = dir
	var lv := _lane_v(a.side, dir, a.v)
	a.route.clear()
	a.route.append(Vector2(a.s + dir * 0.6, lv))
	a.route.append(Vector2(to_s, lv))


func _walk_on(a: Agent, dist: float) -> void:
	_set_state(a, State.WALKING)
	a.plan = "pass"
	if (a.dir > 0 and a.s > s_hi - 2.0) or (a.dir < 0 and a.s < s_lo + 2.0):
		a.dir = -a.dir
	var lv := _lane_v(a.side, a.dir, a.v)
	a.route.clear()
	a.route.append(Vector2(clampf(a.s + a.dir * 0.6, s_lo, s_hi), lv))  # onto the lane first
	a.route.append(Vector2(clampf(a.s + a.dir * dist, s_lo, s_hi), lv))


func _at_end(a: Agent) -> void:
	# Fewer people wanted (time of day) -> leave the scene here, out of the player's sight.
	if active_count() > target_active() and absf(_last_player_s - a.s) > float(cfg.get("offstage_min_player_distance", 30.0)) \
			and (not can_vanish.is_valid() or bool(can_vanish.call(a.s, a.v))):
		_set_state(a, State.OFFSTAGE)
		a.route.clear()
		return
	a.dir = -a.dir
	_choose_plan(a)


var _last_player_s := 0.0
## Optional check from the scene (s, v) -> bool: may a person disappear / appear there now
## (not in the camera's view)? Without it only the distance to the player counts (unit tests).
var can_vanish: Callable


func _balance(psv: Vector2) -> void:
	_last_player_s = psv.x
	if active_count() >= target_active():
		return
	for a in agents:
		if a.state != State.OFFSTAGE:
			continue
		# Re-enter at the street end farther from the player, walking inwards on a lane.
		var at_lo := absf(psv.x - s_lo) > absf(psv.x - s_hi)
		if can_vanish.is_valid() and not bool(can_vanish.call(s_lo if at_lo else s_hi, float(a.side) * 13.0)):
			return  # the entry point is in view: try again next second
		a.s = s_lo if at_lo else s_hi
		a.dir = 1 if at_lo else -1
		a.v = _lane_v(a.side, a.dir, float(a.side) * 13.0)
		a.cur_speed = a.speed
		a.face = Vector2(a.dir, 0)
		a.face_target = a.face
		_walk_on(a, rng.randf_range(15.0, 45.0))
		return  # one per second: no crowd appearing at once


func _plan_ok(a: Agent, plan: String) -> bool:
	var mx: Dictionary = profile.get("max", {})
	if mx.has(plan):
		var n := 0
		for o in agents:
			if o != a and o.plan == plan and o.state != State.OFFSTAGE:
				n += 1
		if n >= int(mx[plan]) - (1 if plan == "meet" else 0):
			return false
	match plan:
		"pass":
			return true
		"kiosk":
			return a.side > 0 and (not _free_slot("kiosk_counter").is_empty() or not _free_slot("kiosk_wait").is_empty())
		"club":
			return a.side < 0 and not _free_kind("club").is_empty()
		"group":
			return not _free_kind("group", a.side).is_empty()
		"linger":
			return not _free_kind("look", a.side).is_empty()
		"meet":
			return _meet_partner(a) >= 0 and not _free_kind("meet", a.side).is_empty()
	return false


## Free group of `kind` on `side` (0 = any). Score: people already there (friends join friends)
## minus distance (`near_s`, people prefer places on their way); 1 person ~ 30 m.
func _free_kind(kind: String, side: int = 0, near_s: float = INF) -> String:
	var best := ""
	var best_n := -1e9
	for gid in groups:
		var g: Dictionary = groups[gid]
		if g.kind != kind or (side != 0 and signf((g.center as Vector2).y) != float(side)):
			continue
		if kind == "meet" and owner.has(g.slots[0]) or kind == "meet" and owner.has(g.slots[1]):
			continue
		var used := 0
		var free := false
		for sid in (g.slots as Array):
			if owner.has(sid):
				used += 1
			else:
				free = true
		var score := used * 30.0 + float(g.priority) - (absf((g.center as Vector2).x - near_s) if near_s != INF else 0.0)
		if free and score > best_n:
			best = gid
			best_n = score
	return best


func _meet_partner(a: Agent) -> int:
	for o in agents:
		if o != a and o.side == a.side and o.state in [State.WALKING, State.LEAVING] and o.partner < 0 \
				and absf(o.s - a.s) < 30.0 and o.s > s_lo + 8.0 and o.s < s_hi - 8.0:
			return o.id
	return -1


func _choose_plan(a: Agent) -> void:
	var w: Dictionary = profile.get("weights", {"pass": 1.0})
	var total := 0.0
	var options: Array = []
	for p in w:
		if float(w[p]) > 0.0 and _plan_ok(a, String(p)):
			var weight := float(w[p])
			# spontaneous: passing the KIOSK within 30 m makes a quick purchase more likely
			if p == "kiosk" and groups.has("kiosk_counter") and absf((groups.kiosk_counter.center as Vector2).x - a.s) < 30.0:
				weight *= float(cfg.get("kiosk_near_factor", 2.0))
			options.append([String(p), weight])
			total += weight
	var pick := "pass"
	var x := rng.randf() * total
	for o in options:
		x -= float(o[1])
		if x <= 0.0:
			pick = o[0]
			break
	a.plan = pick
	match pick:
		"pass":
			_walk_on(a, rng.randf_range(15.0, 60.0))
		"kiosk":
			var sid := _free_slot("kiosk_counter")
			if sid.is_empty():
				sid = _free_slot("kiosk_wait")
			_go_to(a, sid)
		"club", "group", "linger":
			var gid := _free_kind({"club": "club", "group": "group", "linger": "look"}[pick], 0 if pick == "club" else a.side, a.s)
			_go_to(a, _free_slot(gid))
		"meet":
			var p := agents[_meet_partner(a)]
			var g: Dictionary = groups[_free_kind("meet", a.side, (a.s + p.s) * 0.5)]
			# the slot nearer to each person
			var s0: String = g.slots[0]
			var s1: String = g.slots[1]
			if (spots[s0].pos as Vector2).distance_to(Vector2(a.s, a.v)) > (spots[s1].pos as Vector2).distance_to(Vector2(a.s, a.v)):
				var t := s0
				s0 = s1
				s1 = t
			a.partner = p.id
			p.partner = a.id
			p.plan = "meet"
			_release(p)
			_go_to(a, s0)
			_go_to(p, s1)


func _go_to(a: Agent, sid: String) -> void:
	if sid.is_empty():
		_walk_on(a, 20.0)
		return
	_release(a)
	_reserve(a, sid)
	_set_state(a, State.APPROACHING)
	_route_to(a, spots[sid].pos)


## Agents per state name (diagnostics / tests).
func census() -> Dictionary:
	var c := {}
	for a in agents:
		var n: String = STATE_NAMES[a.state]
		c[n] = int(c.get(n, 0)) + 1
	return c
