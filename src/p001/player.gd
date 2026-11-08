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

	# Placeholder body: clearly not a final character.
	_visual = Node3D.new()
	add_child(_visual)
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
