# The local player: input → move, aim, shoot. Only the owning peer runs
# input; everyone else sees this body through _sync_state.
extends BaseCharacter

enum CameraMode { FIRST_PERSON, THIRD_PERSON }

const MOUSE_SENS := 0.0025
const LOCAL_BODY_VIS_LAYER := 5
const THIRD_SIDE_ANGLE := PI / 4.0          # 45° off the right shoulder
const THIRD_SPRING_LENGTH := 4.5
const THIRD_PITCH := -0.28                  # ~-16°: looks down past the head
const THIRD_SIDE_OFFSET := 0.95             # shifts the rig right so the body sits left of the crosshair

var weapon := Weapon.new()
var _eye_height := DEFAULT_EYE_HEIGHT
var _third_pivot_height := 2.05
var _head: Node3D
var _spring_side: Node3D
var _spring: SpringArm3D
var _camera: Camera3D
var _ray: RayCast3D
var _camera_mode := CameraMode.FIRST_PERSON
var _body_layer_bit := 0
var _viewmodel: Node3D
var _viewmodel_muzzle: Node3D
var _now := 0.0

func _ready() -> void:
	super()
	display_name = "Player %s" % name.trim_prefix("Player_")
	get_node("NameLabel").text = display_name
	if is_multiplayer_authority():
		_eye_height = eye_height()
		_third_pivot_height = _eye_height + 0.45
		_build_camera_rig()
		get_node("NameLabel").visible = false
		_set_camera_mode(CameraMode.FIRST_PERSON)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		health.changed.connect(func(hp): get_tree().call_group("hud", "set_hp", hp))
		health.died.connect(_on_local_death)

func _build_camera_rig() -> void:
	_body_layer_bit = 1 << (LOCAL_BODY_VIS_LAYER - 1)
	_assign_visual_layer(get_node("Model"), _body_layer_bit)
	get_node("NameLabel").layers = _body_layer_bit

	_head = Node3D.new()
	_head.name = "CameraHead"
	add_child(_head)

	_spring_side = Node3D.new()
	_spring_side.name = "SpringSide"
	_head.add_child(_spring_side)

	_spring = SpringArm3D.new()
	_spring.collision_mask = 1
	_spring_side.add_child(_spring)

	_camera = Camera3D.new()
	_camera.current = true
	_spring.add_child(_camera)

	_ray = RayCast3D.new()
	_ray.target_position = Vector3(0, 0, -100)
	_ray.collision_mask = 0b11                 # world + characters
	# The camera sits behind the local body, so the aim ray would pass through
	# ourselves at close range — exclude our own body from the ray.
	_ray.add_exception(self)
	_camera.add_child(_ray)

	_viewmodel = FpsGun.build_viewmodel(_camera)
	_viewmodel_muzzle = FpsGun.muzzle_node(_viewmodel)
	_shoot_flash.reparent(_viewmodel_muzzle)
	_shoot_flash.position = Vector3.ZERO
	_gun_sfx.reparent(_viewmodel_muzzle)
	_gun_sfx.position = Vector3.ZERO

func _set_camera_mode(mode: CameraMode) -> void:
	_camera_mode = mode
	match mode:
		CameraMode.FIRST_PERSON:
			_head.position.y = _eye_height
			_head.position.x = 0.0
			_spring_side.rotation.y = 0.0
			_spring.spring_length = 0.0
			_set_local_body_visible(false)
			_set_muzzle_source(_viewmodel_muzzle)
			if _viewmodel:
				_viewmodel.visible = true
			if _world_gun:
				_world_gun.visible = false
		CameraMode.THIRD_PERSON:
			_head.position.y = _third_pivot_height
			_head.position.x = THIRD_SIDE_OFFSET
			_spring_side.rotation.y = THIRD_SIDE_ANGLE
			_spring.spring_length = THIRD_SPRING_LENGTH
			_head.rotation.x = THIRD_PITCH
			_set_local_body_visible(true)
			if _world_gun:
				_set_muzzle_source(FpsGun.muzzle_node(_world_gun))
				_world_gun.visible = true
			if _viewmodel:
				_viewmodel.visible = false

func _set_muzzle_source(muzzle: Node3D) -> void:
	if muzzle == null:
		return
	_shoot_flash.reparent(muzzle)
	_shoot_flash.position = Vector3.ZERO
	_gun_sfx.reparent(muzzle)
	_gun_sfx.position = Vector3.ZERO

func _set_local_body_visible(visible: bool) -> void:
	if visible:
		_camera.cull_mask |= _body_layer_bit
	else:
		_camera.cull_mask &= ~_body_layer_bit

func _assign_visual_layer(node: Node, mask: int) -> void:
	if node is VisualInstance3D:
		node.layers = mask
	for child in node.get_children():
		_assign_visual_layer(child, mask)

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * MOUSE_SENS
		var pitch_min := -1.1 if _camera_mode == CameraMode.FIRST_PERSON else -0.8
		var pitch_max := 0.5 if _camera_mode == CameraMode.FIRST_PERSON else 0.45
		_head.rotation.x = clampf(
			_head.rotation.x - event.relative.y * MOUSE_SENS, pitch_min, pitch_max)
	elif event.is_action_pressed("toggle_camera"):
		var next := (CameraMode.FIRST_PERSON if _camera_mode == CameraMode.THIRD_PERSON
			else CameraMode.THIRD_PERSON)
		_set_camera_mode(next)
	elif event.is_action_pressed("toggle_mouse"):
		Input.mouse_mode = (Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta: float) -> void:
	_now += delta
	if is_multiplayer_authority() and not is_dead():
		weapon.update(_now)
		_handle_move(delta)
		if Input.is_action_pressed("shoot") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_try_shoot()
		if Input.is_action_just_pressed("reload"):
			if weapon.start_reload(_now):
				play_reload()
		get_tree().call_group("hud", "set_ammo", weapon.ammo,
			weapon.is_reloading(_now))
	super(delta)

func _handle_move(_delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right",
		"move_forward", "move_back")
	var direction := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_SPEED

func _try_shoot() -> void:
	if not weapon.fire(_now):
		return
	flash_muzzle()
	_ray.force_raycast_update()
	var target := _find_character(_ray.get_collider())
	if target and not target.is_dead():
		# Never let the aim ray (which passes through our own body at close
		# range) hurt the local player.
		if target == self:
			return
		# Ask the referee (host). rpc_id(1, …) runs locally when we ARE the host.
		get_node("/root/Game").request_hit.rpc_id(
			1, target.get_path(), Weapon.DAMAGE)
		get_tree().call_group("hud", "show_hit_marker")

func _find_character(node: Node) -> BaseCharacter:
	# A ray may hit an inner mesh/collision child; walk up to the owning body.
	var current := node
	while current:
		if current is BaseCharacter:
			return current
		current = current.get_parent()
	return null

func _on_local_death() -> void:
	# Spectate: detach the camera high above the arena.
	var pivot := Node3D.new()
	get_node("/root/Game").add_child(pivot)
	pivot.position = Vector3(0, 55, 35)
	_head.reparent(pivot)
	_head.rotation.x = -0.9
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().call_group("hud", "show_death")
