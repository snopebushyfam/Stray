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
var _anim: AnimationPlayer
var _anim_names: Dictionary = {}
## Name of the locomotion state currently shown ("idle", "walk", "run", "air"), "" without a rig.
var anim_state: String = ""
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
	var model: Node3D = scene.instantiate()
	model.name = "Character"
	model.rotation.y = deg_to_rad(c.get("yaw_offset_deg", 180.0))  # glTF faces +Z, Godot forward is -Z
	model.position.y = -h * 0.5  # model feet at y = 0, capsule centre at the body origin
	_visual.add_child(model)
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(c.get("body_color", [0.14, 0.16, 0.21])[0], c.get("body_color", [0.14, 0.16, 0.21])[1], c.get("body_color", [0.14, 0.16, 0.21])[2])
	body.roughness = 0.7
	var joints := StandardMaterial3D.new()
	var jc: Array = c.get("joint_color", [0.05, 0.05, 0.06])
	joints.albedo_color = Color(jc[0], jc[1], jc[2])
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(i)
			m.set_surface_override_material(i, joints if src != null and "Joint" in src.resource_name else body)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return true
	_anim = players[0]
	_anim_names = c.get("anims", {})
	_set_anim("idle", 1.0)
	return true


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
		var state := "run" if Input.is_action_pressed("run") else "walk"
		var nat: float = natural.get(_anim_names.get(state, ""), 1.0)
		# Scale the cycle to the real speed so the feet do not slide.
		_set_anim(state, clampf(h_speed / maxf(nat, 0.01), 0.4, 2.0))


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
		elif not event.pressed and event.index == _look_touch_index:
			_look_touch_index = -1
	elif event is InputEventScreenDrag and event.index == _look_touch_index:
		_look(event.relative * touch_sens)


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
	elif Input.is_action_just_pressed("jump"):
		velocity.y = cfg.get("jump_velocity", 3.6)

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam_basis := _yaw_pivot.global_transform.basis
	var dir := (cam_basis * Vector3(input.x, 0.0, input.y))
	dir.y = 0.0
	dir = dir.normalized() * minf(input.length(), 1.0)
	var speed: float = cfg.get("run_speed", 4.5) if Input.is_action_pressed("run") else cfg.get("walk_speed", 1.6)
	var accel: float = cfg.get("acceleration", 10.0)
	var target := dir * speed
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)
	if dir.length() > 0.05:
		var want := atan2(-dir.x, -dir.z)
		var turn := deg_to_rad(cfg.get("turn_speed_deg", 540.0)) * delta
		_visual.rotation.y = rotate_toward(_visual.rotation.y, want, turn)
	move_and_slide()
	_update_animation()

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
