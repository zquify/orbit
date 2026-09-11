extends Node3D
## Controls the player's third-person camera.
##
## The camera is designed to work with the custom gravity system used by
## player.gd. It does not assume that global Y is always the player's up
## direction.
##
## The camera follows a target position and rotates around the player's current
## up direction. Mouse and controller input control horizontal yaw and vertical
## pitch.
##
## Horizontal yaw is temporarily stored by the camera and transferred to the
## player through consume_yaw(). This allows the player and camera to maintain
## a consistent horizontal orientation while the player moves around curved
## surfaces.

#region Player

@export_category("Player")

## CharacterBody3D controlled by player.gd.
##
## If this is not assigned in the Inspector, the camera attempts to use its
## parent as the player.
@export var player: CharacterBody3D

#endregion


#region Camera

@export_category("Camera")

## Node3D that determines the camera's global position.
##
## This is normally a point attached to the player near the desired camera
## follow position.
@export var camera_target: Node3D

## Mouse camera sensitivity.
##
## Mouse motion already represents movement between input events, so delta is
## not required when applying mouse input.
@export var mouse_sensitivity: float = 0.003

## Controller camera sensitivity.
##
## Controller input is continuous, so it is multiplied by delta when applied.
@export var controller_sensitivity: float = 2.5

#endregion


#region Pitch

@export_category("Pitch")

## Minimum vertical camera angle in degrees.
@export var min_pitch: float = -60.0

## Maximum vertical camera angle in degrees.
@export var max_pitch: float = 60.0

#endregion


#region Zoom

@export_category("Zoom")

## Speed at which the camera transitions between normal and zoomed scale.
@export var zoom_speed: float = 10.0

## Scale applied to the camera rig while zooming.
##
## The current camera system uses scale rather than changing the Camera3D's
## field of view or physical distance.
@export var zoom_scale: Vector3 = Vector3(1.0, 0.55, 0.55)

## Sensitivity multiplier applied while zooming.
##
## A value of 0.5 makes mouse and controller camera movement half as sensitive
## while the zoom action is held.
@export var zoom_sensitivity_multiplier: float = 0.5

#endregion


#region Camera State

## Horizontal camera rotation in radians.
##
## This value accumulates mouse/controller yaw until player.gd consumes it.
var yaw: float = 0.0

## Vertical camera rotation in radians.
##
## The initial value points the camera 15 degrees downward.
var pitch: float = deg_to_rad(-15.0)

## Normal camera scale used when zoom is not active.
var normal_scale: Vector3 = Vector3.ONE

#endregion


#region Initialization

## Initializes the camera and captures the mouse.
func _ready() -> void:
	# Prevent the camera from inheriting the parent's transform automatically.
	#
	# Its global position and orientation are calculated manually in
	# update_camera_transform().
	top_level = true

	# If no player was assigned manually, use the parent as the player.
	if player == null:
		player = get_parent() as CharacterBody3D

	# Capture the mouse so mouse movement can control the camera immediately.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

#endregion


#region Camera Update

## Updates camera input, zoom, pitch limits, and the camera transform once
## per rendered frame.
func _process(delta: float) -> void:
	handle_controller_look(delta)
	handle_zoom(delta)

	# Keep pitch inside its configured range.
	pitch = clamp(
		pitch,
		deg_to_rad(min_pitch),
		deg_to_rad(max_pitch)
	)

	update_camera_transform()


## Rebuilds the camera's global position and orientation from the player's
## orientation, camera yaw, and camera pitch.
func update_camera_transform() -> void:
	if player == null:
		return

	# Position the camera at the configured target.
	global_position = camera_target.global_position

	var player_basis: Basis = player.global_transform.basis

	# Use the player's current local Y axis as the yaw axis.
	#
	# This is important for arbitrary gravity: global Y may not be the player's
	# actual up direction.
	var yaw_rotation := Quaternion(
		player_basis.y,
		yaw
	)

	# Start with the player's orientation and apply the camera's horizontal
	# rotation around the player's current up direction.
	var camera_basis: Basis = (
		Basis(yaw_rotation) * player_basis
	).orthonormalized()

	# Apply vertical rotation around the camera's local X/right axis.
	var pitch_rotation := Quaternion(
		camera_basis.x,
		pitch
	)

	camera_basis = (
		Basis(pitch_rotation) * camera_basis
	).orthonormalized()

	# Updating global_transform.basis replaces the basis portion of the
	# transform. Save the current scale so the zoom system is preserved.
	var current_scale: Vector3 = scale

	global_transform.basis = camera_basis

	scale = current_scale

#endregion


#region Yaw

## Returns the camera's accumulated horizontal rotation and resets it.
##
## player.gd calls this once per physics frame to transfer horizontal camera
## rotation to the player.
func consume_yaw() -> float:
	var current_yaw: float = yaw
	yaw = 0.0

	return current_yaw

#endregion


#region Input

## Processes mouse movement, mouse capture, and mouse-release input.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# Zooming also reduces camera sensitivity.
		var sensitivity_multiplier: float = (
			zoom_sensitivity_multiplier
			if Input.is_action_pressed("zoom")
			else 1.0
		)

		# Horizontal mouse movement changes camera yaw.
		yaw -= (
			event.relative.x
			* mouse_sensitivity
			* sensitivity_multiplier
		)

		# Vertical mouse movement changes camera pitch.
		pitch -= (
			event.relative.y
			* mouse_sensitivity
			* sensitivity_multiplier
		)

		# Clamp immediately so pitch never remains outside the valid range.
		pitch = clamp(
			pitch,
			deg_to_rad(min_pitch),
			deg_to_rad(max_pitch)
		)

	elif event is InputEventKey:
		# Escape toggles mouse capture so the player can release the mouse
		# without closing the game.
		if event.keycode == KEY_ESCAPE and event.pressed:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	elif event is InputEventMouseButton:
		# Clicking the left mouse button captures the mouse again.
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Processes controller input for horizontal and vertical camera movement.
##
## Controller input is multiplied by delta so camera rotation remains
## consistent across different frame rates.
func handle_controller_look(delta: float) -> void:
	var look_input: Vector2 = Input.get_vector(
		"look_left",
		"look_right",
		"look_up",
		"look_down"
	)

	# Ignore controller input that is effectively zero.
	if look_input.length_squared() < 0.0001:
		return

	# Zooming reduces camera sensitivity.
	var sensitivity_multiplier: float = (
		zoom_sensitivity_multiplier
		if Input.is_action_pressed("zoom")
		else 1.0
	)

	# Apply horizontal controller input to yaw.
	yaw -= (
		look_input.x
		* controller_sensitivity
		* sensitivity_multiplier
		* delta
	)

	# Apply vertical controller input to pitch.
	pitch -= (
		look_input.y
		* controller_sensitivity
		* sensitivity_multiplier
		* delta
	)

	# Keep pitch inside the configured limits.
	pitch = clamp(
		pitch,
		deg_to_rad(min_pitch),
		deg_to_rad(max_pitch)
	)

#endregion


#region Zoom

## Smoothly transitions the camera between normal and zoomed scale.
##
## Zoom is controlled by holding the "zoom" input action.
func handle_zoom(delta: float) -> void:
	var target_scale: Vector3 = (
		zoom_scale
		if Input.is_action_pressed("zoom")
		else normal_scale
	)

	# Smoothly approach the desired scale.
	#
	# The exponential smoothing factor makes the transition independent of
	# frame rate.
	scale = scale.lerp(
		target_scale,
		1.0 - exp(-zoom_speed * delta)
	)

#endregion
