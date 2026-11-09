## Third-person pedestrian for Prototype 001 (placeholder body until a character asset exists).
##
## Tuning: res://data/p001/player_config.json (injected via setup()). Design: docs/STRAY_GDD.md.
## Input actions (move_*, run, jump) are registered by main.gd from the same config, so keyboard,
## gamepad and the on-screen VirtualJoystick all drive the same actions.
class_name StrayPlayer
extends CharacterBody3D

## Emitted once after the first physics frames with the result of the ground check.
signal ground_checked(on_floor: bool, gap: float)

var cfg: Dictionary = {}
var camera: Camera3D
var _yaw_pivot: Node3D
var _pitch_pivot: Node3D
var _arm: SpringArm3D
var _visual: Node3D
var _gravity: float = 9.81
var _frames: int = 0
var _look_touch_index: int = -1
## Visible character: "r10" (default, dressed mannequin) or "r11" (MakeHuman prototype).
var character_variant := "r10"
## Number of ledges climbed (kerbs, median) - diagnostics / tests.
var step_count := 0
## Touch controls active (set by main.gd): pushing the joystick to its edge then runs.
var touch_mode := false
## "Rennen" toggle button on touch screens.
var run_toggle := false
## Last accepted position of the look finger (the camera uses positions, not event.relative).
var _look_touch_last := Vector2.ZERO
var _anim: AnimationPlayer
var _anim_names: Dictionary = {}
## Name of the locomotion state currently shown ("idle", "walk", "run", "air"), "" without a rig.
var anim_state: String = ""
## Footstep sounds (Kenney CC0, concrete); one is played per stride while on the floor.
var footstep_streams: Array[AudioStream] = []
var footstep_count: int = 0
var _step_cfg: Dictionary = {}
var _step_player: AudioStreamPlayer3D
var _stride_acc: float = 0.0
var _rng := RandomNumberGenerator.new()
## False while a menu is open: no movement or jumping (gravity still applies).
var input_enabled := true
## Look input from scripts/tests (degrees per call, x = yaw, y = pitch).
var injected_look := Vector2.ZERO


## Builds the collision capsule, placeholder body and camera rig from config.
func setup(config: Dictionary) -> void:
	cfg = config
	var r: float = cfg.get("capsule_radius", 0.35)
	var h: float = cfg.get("capsule_height", 1.8)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = r
	cap.height = h
	cs.shape = cap
	add_child(cs)
	# Collide with world (1), cars (2) and pedestrians (4).
	collision_mask = 1 | 2 | 4
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(50.0)

	_visual = Node3D.new()
	add_child(_visual)
	if _load_character(cfg.get("character", {}), h):
		_build_camera(h)
		return
	# Fallback placeholder body when the character asset is missing.
	var body := MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = r * 0.85
	bm.height = h * 0.92
	body.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.24, 0.38)
	body.material_override = mat
	body.position.y = -h * 0.04
	_visual.add_child(body)
	var nose := MeshInstance3D.new()
	var nm := BoxMesh.new()
	nm.size = Vector3(0.18, 0.08, 0.12)
	nose.mesh = nm
	var nmat := StandardMaterial3D.new()
	nmat.albedo_color = Color(0.85, 0.65, 0.5)
	nose.material_override = nmat
	nose.position = Vector3(0, h * 0.35, -r * 0.8)  # shows the facing direction (-Z)
	_visual.add_child(nose)

	_build_camera(h)


func _build_camera(h: float) -> void:
	_yaw_pivot = Node3D.new()
	_yaw_pivot.position.y = float(cfg.get("camera_height", 1.55)) - h * 0.5
	add_child(_yaw_pivot)
	_pitch_pivot = Node3D.new()
	_pitch_pivot.rotation_degrees.x = -15.0
	_yaw_pivot.add_child(_pitch_pivot)
	_arm = SpringArm3D.new()
	_arm.spring_length = cfg.get("camera_distance", 3.2)
	_arm.margin = 0.2
	_arm.position.x = cfg.get("camera_shoulder_offset", 0.45)
	_arm.add_excluded_object(get_rid())
	# A sphere probe (not a thin ray) keeps the camera out of walls next to doors.
	var probe := SphereShape3D.new()
	probe.radius = float(cfg.get("camera_probe_radius", 0.25))
	_arm.shape = probe
	_pitch_pivot.add_child(_arm)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.near = 0.05
	_arm.add_child(camera)


## Instances the rigged character (CC0 Quaternius mannequin) and tints its two materials.
## Returns false when the scene is missing, so setup() falls back to the placeholder.
func _load_character(c: Dictionary, h: float) -> bool:
	if c.is_empty() or not ResourceLoader.exists(c.get("scene", "")):
		return false
	var scene: PackedScene = load(c["scene"])
	if scene == null:
		return false
	var model: Node3D
	var human_path := String(c.get("human_scene", ""))
	if character_variant == "r11" and ResourceLoader.exists(human_path):
		# R11 prototype: MakeHuman character driven by the UAL animations (human_rig.gd).
		var rig := StrayHumanRig.new()
		if rig.setup(load(human_path), scene):
			model = rig
		else:
			rig.free()
			character_variant = "r10"
	if model == null:
		model = scene.instantiate()
		# R10: dressed with an everyday outfit (look "player"), see character_look.gd.
		if not StrayCharacterLook.apply(model, String(c.get("look", "player"))):
			push_warning("STRAY_DIAG character look not applied")
	model.name = "Character"
	model.rotation.y = deg_to_rad(c.get("yaw_offset_deg", 180.0))  # glTF faces +Z, Godot forward is -Z
	model.position.y = -h * 0.5  # model feet at y = 0, capsule centre at the body origin
	_visual.add_child(model)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return true
	_anim = players[0]
	_anim_names = c.get("anims", {})
	_set_anim("idle", 1.0)
	return true


## Swaps the visible character between "r10" (dressed mannequin, default) and "r11" (MakeHuman
## prototype). Animation state, collision and camera are untouched.
func set_character_variant(v: String) -> void:
	if v == character_variant and _visual.get_node_or_null("Character") != null:
		return
	character_variant = v
	var old := _visual.get_node_or_null("Character")
	if old:
		_visual.remove_child(old)
		old.queue_free()
	_anim = null
	anim_state = ""
	_load_character(cfg.get("character", {}), float(cfg.get("capsule_height", 1.8)))
	print("STRAY_DIAG character_variant=%s" % character_variant)


func _set_anim(state: String, speed_scale: float) -> void:
	if _anim == null:
		return
	var anim_name: String = _anim_names.get(state, "")
	if anim_name.is_empty() or not _anim.has_animation(anim_name):
		return
	if anim_state != state:
		_anim.play(anim_name, float(cfg.get("character", {}).get("blend_time", 0.2)))
		anim_state = state
	_anim.speed_scale = speed_scale


func _update_animation() -> void:
	if _anim == null:
		return
	var c: Dictionary = cfg.get("character", {})
	var natural: Dictionary = c.get("natural_speed_mps", {})
	var h_speed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor():
		_set_anim("air", 1.0)
	elif h_speed < float(c.get("idle_below_mps", 0.15)):
		_set_anim("idle", 1.0)
	else:
		var state := "run" if wants_run() else "walk"
		var nat: float = natural.get(_anim_names.get(state, ""), 1.0)
		# Scale the cycle to the real speed so the feet do not slide.
		_set_anim(state, clampf(h_speed / maxf(nat, 0.01), 0.4, 2.0))


## Configures footstep audio from audio_config.json ("footsteps" section).
func setup_footsteps(cfg_steps: Dictionary) -> void:
	_step_cfg = cfg_steps
	for path in cfg_steps.get("streams", []):
		if ResourceLoader.exists(path):
			footstep_streams.append(load(path))
	_step_player = AudioStreamPlayer3D.new()
	_step_player.name = "Footsteps"
	_step_player.volume_db = cfg_steps.get("volume_db", -6.0)
	_step_player.position.y = -float(cfg.get("capsule_height", 1.8)) * 0.5
	_step_player.max_polyphony = 2
	add_child(_step_player)
	_rng.seed = 7


func _update_footsteps(delta: float) -> void:
	if footstep_streams.is_empty() or not is_on_floor():
		_stride_acc = 0.0
		return
	var h_speed := Vector2(velocity.x, velocity.z).length()
	if h_speed < 0.2:
		_stride_acc = 0.0
		return
	_stride_acc += h_speed * delta
	var stride: float = _step_cfg.get("run_stride_m", 1.25) if wants_run() else _step_cfg.get("walk_stride_m", 0.65)
	if _stride_acc >= stride:
		_stride_acc -= stride
		var jitter: float = _step_cfg.get("pitch_jitter", 0.06)
		_step_player.stream = footstep_streams[_rng.randi_range(0, footstep_streams.size() - 1)]
		_step_player.pitch_scale = 1.0 + _rng.randf_range(-jitter, jitter)
		_step_player.play()
		footstep_count += 1


## Indoors the camera sits closer (small rooms); outdoors it uses camera_distance.
func set_indoor_camera(indoor: bool) -> void:
	if _arm:
		_arm.spring_length = float(cfg.get("camera_distance_indoor", 2.2)) if indoor else float(cfg.get("camera_distance", 3.8))


## Current facing yaw (camera pivot), for the save game.
func get_yaw() -> float:
	return _yaw_pivot.rotation.y


## Points character and camera along a yaw (radians, about +Y).
func face_yaw(yaw: float) -> void:
	_visual.rotation.y = yaw
	_yaw_pivot.rotation.y = yaw


func _unhandled_input(event: InputEvent) -> void:
	var mouse_sens: float = cfg.get("mouse_sensitivity_deg_per_px", 0.15)
	var touch_sens: float = cfg.get("touch_look_sensitivity_deg_per_px", 0.25)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(event.relative * mouse_sens)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			and not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventScreenTouch:
		# Right half of the screen = camera look (left half is the VirtualJoystick).
		if event.pressed and event.position.x > get_viewport().get_visible_rect().size.x * 0.5:
			_look_touch_index = event.index
			_look_touch_last = event.position
		elif not event.pressed and event.index == _look_touch_index:
			_look_touch_index = -1
	elif event is InputEventScreenDrag and event.index == _look_touch_index:
		_look(touch_look_delta(event.position) * touch_sens)


## Camera delta (px) for a drag of the look finger. Mobile browsers sometimes report the
## joystick finger under the look finger's index (huge jumps, the camera "jittered" on tablets):
## positions in the joystick half are ignored, and one event never moves more than a cap.
func touch_look_delta(pos: Vector2) -> Vector2:
	var half := get_viewport().get_visible_rect().size.x * float(cfg.get("touch_look_min_x_ratio", 0.45))
	if pos.x < half:
		return Vector2.ZERO
	var d := pos - _look_touch_last
	_look_touch_last = pos
	var cap: float = cfg.get("touch_look_max_step_px", 60.0)
	return d.limit_length(cap)


## True while the character should run: Shift/gamepad "run", the touch toggle, or (touch only)
## the joystick pushed to its edge.
func wants_run() -> bool:
	if Input.is_action_pressed("run") or run_toggle:
		return true
	if touch_mode and input_enabled:
		var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		return v.length() >= float(cfg.get("touch_run_from_stick", 0.9))
	return false


## Steps up onto a low ledge (kerbs 0.10-0.25 m, the 0.12 m median) that stopped the capsule.
## Without this the player could walk down from a sidewalk but never back up - an invisible wall
## at every kerb (tablet report R9.2). Only ledges up to `max_step_height` count; walls, cars and
## benches are higher and still block. Uses test_move (no collision changes, nothing removed).
func _try_step_up(h_motion: Vector3, delta: float) -> void:
	var blocked := false
	for k in get_slide_collision_count():
		var n := get_slide_collision(k).get_normal()
		if n.y < 0.7 and n.y > -0.1 and Vector2(n.x, n.z).dot(Vector2(h_motion.x, h_motion.z)) < 0.0:
			blocked = true
			break
	if not blocked or h_motion.length() < 0.05:
		return
	var step_h: float = cfg.get("max_step_height", 0.3)
	var radius: float = cfg.get("capsule_radius", 0.35)
	var fwd := h_motion.normalized() * maxf(h_motion.length() * delta, radius * 0.5)
	var xf := global_transform
	if test_move(xf, Vector3.UP * step_h):
		return  # no head room
	var up_xf := xf.translated(Vector3.UP * step_h)
	if test_move(up_xf, fwd):
		return  # still blocked at step height: a real wall
	var probe := KinematicCollision3D.new()
	var fwd_xf := up_xf.translated(fwd)
	if not test_move(fwd_xf, Vector3.DOWN * (step_h + 0.05), probe):
		return  # nothing to stand on (would be a drop, not a step)
	if probe.get_normal().y < cos(floor_max_angle):
		return  # landing too steep
	var landed := fwd_xf.origin + probe.get_travel()
	if landed.y - xf.origin.y < 0.02:
		return
	global_position = landed
	step_count += 1


func _look(delta_deg: Vector2) -> void:
	_yaw_pivot.rotation.y -= deg_to_rad(delta_deg.x)
	var p := _pitch_pivot.rotation_degrees.x - delta_deg.y
	_pitch_pivot.rotation_degrees.x = clampf(p, cfg.get("camera_pitch_min_deg", -70.0), cfg.get("camera_pitch_max_deg", 35.0))


func _physics_process(delta: float) -> void:
	if injected_look != Vector2.ZERO:
		_look(injected_look)
		injected_look = Vector2.ZERO
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif input_enabled and Input.is_action_just_pressed("jump"):
		velocity.y = cfg.get("jump_velocity", 3.6)

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if input_enabled else Vector2.ZERO
	var cam_basis := _yaw_pivot.global_transform.basis
	var dir := (cam_basis * Vector3(input.x, 0.0, input.y))
	dir.y = 0.0
	dir = dir.normalized() * minf(input.length(), 1.0)
	var speed: float = cfg.get("run_speed", 4.5) if wants_run() else cfg.get("walk_speed", 1.6)
	var accel: float = cfg.get("acceleration", 10.0)
	var target := dir * speed
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)
	if dir.length() > 0.05:
		var want := atan2(-dir.x, -dir.z)
		var turn := deg_to_rad(cfg.get("turn_speed_deg", 540.0)) * delta
		_visual.rotation.y = rotate_toward(_visual.rotation.y, want, turn)
	var pre_step_velocity := velocity
	move_and_slide()
	if dir.length() > 0.05:
		_try_step_up(Vector3(pre_step_velocity.x, 0.0, pre_step_velocity.z), delta)
	_update_animation()
	_update_footsteps(delta)

	_frames += 1
	if _frames == 30:
		var gap := _ground_gap()
		print("STRAY_DIAG ground_check on_floor=%s gap_m=%.3f pos=%s" % [is_on_floor(), gap, global_position])
		ground_checked.emit(is_on_floor(), gap)


## Distance from the capsule bottom to the ground below (m), or -1 when nothing is below.
func _ground_gap() -> float:
	var space := get_world_3d().direct_space_state
	var h: float = cfg.get("capsule_height", 1.8)
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * 5.0)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return -1.0
	return (global_position.y - h * 0.5) - hit.position.y
