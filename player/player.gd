extends CharacterBody3D
## Controls the player's movement, jumping, launching, and orientation.
##
## This controller uses custom gravity instead of assuming that gravity always
## points toward the world's global negative Y direction.
##
## Node3D objects placed in the "gravity_body" group act as gravity sources.
## The player combines the influence of all gravity sources to determine its
## current gravity direction.
##
## Because the player's "up" direction is the opposite of gravity, the player
## can walk around spherical or otherwise curved gravity bodies while staying
## oriented to their surface.

#region Gravity

@export_category("Gravity")

## Strength of the gravity applied to the player.
##
## Gravity direction changes based on the player's position relative to gravity
## bodies, but the final gravity vector always has this magnitude.
@export var gravity_strength: float = 32.0

## Gravity bodies that can affect the player.
##
## Populated from the "gravity_body" group in _ready().
var gravity_bodies: Array[Node3D] = []

## Threshold for treating very small vectors as zero.
const VECTOR_EPSILON_SQUARED: float = 0.0001

#endregion


#region Movement

@export_category("Movement")

## Maximum speed of the player's movement along a surface.
@export var move_speed: float = 10.0

## Rate at which the player accelerates toward the target movement speed
## while standing on a surface.
@export var ground_acceleration: float = 55.0

## Rate at which the player slows down while standing on a surface.
@export var ground_deceleration: float = 100.0

## Rate at which the player changes horizontal movement while airborne.
@export var air_acceleration: float = 22.0

## Rate at which the player loses horizontal movement while airborne.
@export var air_deceleration: float = 10.0

#endregion


#region Jump

@export_category("Jump")

## Initial velocity given to the player when jumping.
##
## The velocity is applied in the direction opposite to gravity, meaning the
## player jumps away from the current surface.
@export var jump_velocity: float = 12.0

#endregion


#region Launch

@export_category("Launch")

## Additional velocity given to the player when launching.
##
## The velocity is applied in the direction the camera is facing.
@export var launch_strength: float = 20.0

#endregion


#region Orientation

@export_category("Orientation")

## Maximum speed at which the player rotates to match the current gravity.
##
## This value is measured in radians per second.
@export var rotation_speed: float = 10.0

#endregion


#region References

## Camera pivot used to determine camera-relative movement and launching.
##
## The camera pivot also provides the consume_yaw() function used to transfer
## horizontal camera rotation to the player.
@onready var camera_pivot: Node3D = $CameraPivot

#endregion


#region Initialization

func _ready() -> void:
	# Only the peer that owns this player should control its camera.
	var local_player := is_multiplayer_authority()

	camera_pivot.set_process(local_player)
	camera_pivot.set_physics_process(local_player)

	var camera := camera_pivot.get_node_or_null("Camera3D")

	if camera:
		camera.current = local_player

	# Allow the CharacterBody3D to remain attached to nearby surfaces.
	#
	# This is especially useful for curved gravity because the floor may not
	# be aligned with the world's global Y axis.
	floor_snap_length = 0.5

	# Find all Node3D objects that have been placed in the gravity_body group.
	for node in get_tree().get_nodes_in_group("gravity_body"):
		if node is Node3D:
			gravity_bodies.append(node)

	# Calculate gravity at the player's starting position.
	var gravity: Vector3 = calculate_gravity()

	if gravity.length_squared() > VECTOR_EPSILON_SQUARED:
		# Gravity points toward the gravity source, so the opposite direction
		# is the direction the player considers "up".
		var gravity_up: Vector3 = -gravity.normalized()

		# Tell CharacterBody3D which direction should count as "up".
		#
		# This allows functions such as is_on_floor() to work correctly with
		# custom gravity.
		up_direction = gravity_up

		# Immediately align the player with the starting gravity direction.
		#
		# The player is being initialized here rather than moving normally, so
		# there is no need to gradually rotate over several frames.
		align_to_surface(gravity_up, 1.0)

#endregion


#region Physics

## Updates the player's movement and physics once per physics frame.
##
## The general order is:
## 1. Calculate gravity.
## 2. Determine the player's local up direction.
## 3. Process movement.
## 4. Process jumping and launching.
## 5. Apply gravity.
## 6. Rotate the player toward the gravity direction.
## 7. Apply camera rotation.
## 8. Move the CharacterBody3D.
func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	
	var gravity: Vector3 = calculate_gravity()

	# Without gravity, we can't determine the player's up direction.
	# Still move using the current velocity.
	if gravity.length_squared() < VECTOR_EPSILON_SQUARED:
		move_and_slide()
		return

	# Gravity points toward the gravity source, so "up" points away from it.
	var gravity_up: Vector3 = -gravity.normalized()

	# CharacterBody3D uses up_direction when determining what counts as a floor.
	up_direction = gravity_up

	# Process player-controlled velocity.
	handle_movement(gravity_up, delta)
	handle_jump(gravity_up)
	handle_launch()

	# Apply gravity after input so jumps and launches get their full initial velocity.
	apply_gravity(gravity, delta)

	# Gradually rotate the player so its up direction matches gravity.
	align_to_surface(gravity_up, delta)

	# Apply horizontal camera rotation to the player.
	handle_camera_rotation(gravity_up)

	# Move the CharacterBody3D and resolve collisions.
	move_and_slide()

	if is_on_floor():
		# Remove velocity pointing into the surface.
		#
		# Gravity is applied every frame, so without this cleanup the player
		# could continue accumulating downward velocity while standing on a floor.
		var gravity_velocity: Vector3 = velocity.project(gravity_up)

		if gravity_velocity.dot(gravity_up) < 0.0:
			velocity -= gravity_velocity

#endregion


#region Gravity

## Calculates the combined gravity vector produced by all gravity bodies.
##
## Each gravity body pulls toward its origin. Its influence decreases with
## distance, with a minimum distance used to prevent extreme weights near
## the center.
##
## This causes nearby gravity bodies to have more influence than distant ones.
##
## The individual gravity directions are combined, normalized, and multiplied
## by gravity_strength.
##
## The final gravity magnitude is therefore controlled by gravity_strength,
## while the positions of the gravity bodies determine the direction.
##
## Returns Vector3.ZERO when there are no valid gravity sources.
func calculate_gravity() -> Vector3:
	var gravity_direction: Vector3 = Vector3.ZERO
	var total_weight: float = 0.0

	for body in gravity_bodies:
		# A gravity body may have been removed from the scene after the array
		# was populated. Ignore an invalid reference.
		if body == null:
			continue

		# Calculate the direction and distance from the player to this gravity
		# body's origin.
		var direction: Vector3 = body.global_position - global_position
		var distance: float = direction.length()

		# Avoid normalizing a vector that is too close to zero.
		if distance < 0.001:
			continue

		# Use inverse-square weighting so closer gravity bodies have greater
		# influence.
		#
		# Prevent very small distances from producing an extremely large weight
		# when the player is very close to a gravity body's origin.
		var weight: float = 1.0 / max(distance * distance, 1.0)

		# Add this gravity body's weighted direction to the combined result.
		gravity_direction += direction.normalized() * weight
		total_weight += weight

	# No valid gravity bodies contributed to the calculation.
	if total_weight <= 0.0:
		return Vector3.ZERO

	# Normalize the combined direction so gravity has a consistent strength.
	return gravity_direction.normalized() * gravity_strength


## Applies gravity acceleration to the player's velocity.
##
## Delta is used so the amount of acceleration is independent of the physics
## frame rate.
func apply_gravity(gravity: Vector3, delta: float) -> void:
	velocity += gravity * delta

#endregion


#region Movement

## Handles camera-relative movement while preserving gravity-direction velocity.
##
## Movement velocity is separated into two parts:
## - Surface velocity: movement along the current surface.
## - Gravity velocity: movement along the gravity axis, such as jumping or falling.
##
## This separation prevents walking input from interfering with vertical
## movement.
func handle_movement(gravity_up: Vector3, delta: float) -> void:
	var input_2d: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_backward",
		"move_forward"
	)

	# Extract the portion of velocity moving along the gravity axis.
	var gravity_velocity: Vector3 = velocity.project(gravity_up)

	# The remaining velocity lies along the surface.
	var surface_velocity: Vector3 = velocity - gravity_velocity

	# Get the camera's forward and right directions.
	#
	# A Node3D's forward direction is its negative Z axis.
	var camera_forward: Vector3 = -camera_pivot.global_transform.basis.z
	var camera_right: Vector3 = camera_pivot.global_transform.basis.x

	# Project the camera directions onto the surface.
	#
	# This prevents forward/backward movement from pushing the player into or
	# away from the gravity body when standing on a curved surface.
	camera_forward = camera_forward.slide(gravity_up)
	camera_right = camera_right.slide(gravity_up)

	# Normalize the projected directions so they only represent direction.
	if camera_forward.length_squared() > VECTOR_EPSILON_SQUARED:
		camera_forward = camera_forward.normalized()

	if camera_right.length_squared() > VECTOR_EPSILON_SQUARED:
		camera_right = camera_right.normalized()

	# Convert the 2D movement input into a 3D direction relative to the camera.
	var move_direction: Vector3 = (
		camera_right * input_2d.x +
		camera_forward * input_2d.y
	)

	# Normalize the final direction so diagonal movement is not faster than
	# movement in a single direction.
	if move_direction.length_squared() > VECTOR_EPSILON_SQUARED:
		move_direction = move_direction.normalized()

	var acceleration: float
	var deceleration: float

	if is_on_floor():
		acceleration = ground_acceleration
		deceleration = ground_deceleration
	else:
		acceleration = air_acceleration
		deceleration = air_deceleration

	if move_direction.length_squared() > VECTOR_EPSILON_SQUARED:
		# Convert the desired direction into the target surface velocity.
		var target_velocity: Vector3 = move_direction * move_speed

		surface_velocity = surface_velocity.move_toward(
			target_velocity,
			acceleration * delta
		)
	else:
		# No movement input means the player gradually slows down.
		surface_velocity = surface_velocity.move_toward(
			Vector3.ZERO,
			deceleration * delta
		)

	if is_on_floor():
		# Only surface movement is capped.
		#
		# Falling, jumping, and launching can still make total velocity greater
		# than move_speed.
		var surface_speed: float = surface_velocity.length()

		if surface_speed > move_speed:
			surface_velocity = surface_velocity.normalized() * move_speed

	# Restore the gravity-direction component that was separated at the start.
	velocity = surface_velocity + gravity_velocity

#endregion


#region Jump

## Makes the player jump away from the current surface.
##
## Jumping is only possible while the player is considered to be on a floor.
## Any velocity currently pushing the player into the surface is removed before
## the jump velocity is applied.
func handle_jump(gravity_up: Vector3) -> void:
	if not Input.is_action_just_pressed("jump") or not is_on_floor():
		return

	# Determine how much of the player's velocity is moving along the up axis.
	#
	# A negative value means the player is moving toward the surface.
	var vertical_velocity: float = velocity.dot(gravity_up)

	if vertical_velocity < 0.0:
		# Remove the downward portion before applying the jump.
		velocity -= gravity_up * vertical_velocity

	# Add the jump velocity away from the surface.
	velocity += gravity_up * jump_velocity

#endregion


#region Launch

## Launches the player in the direction the camera is facing.
##
## Unlike normal movement, the launch direction is not projected onto the
## surface. The player can therefore launch upward, downward, sideways, or
## in any other direction the camera is pointing.
##
## Launching is not restricted to the ground, so it can also be performed
## while the player is airborne.
func handle_launch() -> void:
	if not Input.is_action_just_pressed("launch"):
		return

	# A Node3D faces along its negative Z axis.
	var launch_direction: Vector3 = (
		-camera_pivot.global_transform.basis.z
	).normalized()

	# Add launch velocity to the existing velocity rather than replacing it.
	velocity += launch_direction * launch_strength

#endregion


#region Orientation

## Applies accumulated horizontal camera rotation to the player.
##
## camera.gd stores horizontal camera rotation as yaw. This function consumes
## that yaw and rotates the player around its current gravity-up direction.
##
## Rotating around gravity_up instead of global Y allows the player to rotate
## correctly while standing on curved or non-horizontal surfaces.
func handle_camera_rotation(gravity_up: Vector3) -> void:
	# CameraPivot is typed as Node3D, so use call() to access consume_yaw().
	var camera_yaw: float = camera_pivot.call("consume_yaw")

	if abs(camera_yaw) < 0.000001:
		return

	# Create a rotation around the player's current up direction.
	var rotation_quaternion := Quaternion(
		gravity_up,
		camera_yaw
	)

	# Apply the rotation and orthonormalize the basis to prevent small
	# numerical errors from accumulating over time.
	global_transform.basis = (
		Basis(rotation_quaternion) * global_transform.basis
	).orthonormalized()


## Rotates the player toward the current gravity-up direction.
##
## The rotation is limited by rotation_speed, allowing the player to smoothly
## follow changing gravity instead of instantly snapping to the new orientation.
func align_to_surface(gravity_up: Vector3, delta: float) -> void:
	var current_basis: Basis = global_transform.basis

	# The player's local Y axis represents its current up direction.
	var current_up: Vector3 = current_basis.y

	# Find the axis we need to rotate around.
	var rotation_axis: Vector3 = current_up.cross(gravity_up)

	# No rotation is needed when the two directions are parallel.
	#
	# Note: this also includes the 180-degree opposite case, where the cross
	# product is zero.
	if rotation_axis.length_squared() < VECTOR_EPSILON_SQUARED:
		return

	rotation_axis = rotation_axis.normalized()

	# Find the angle between the current and target up directions.
	# Clamp the dot product to avoid floating-point errors with acos().
	var angle: float = acos(
		clamp(current_up.dot(gravity_up), -1.0, 1.0)
	)

	# Limit the amount of rotation that can happen during this physics frame.
	var rotation_amount: float = minf(
		angle,
		rotation_speed * delta
	)

	var rotation_quaternion := Quaternion(
		rotation_axis,
		rotation_amount
	)

	# Keep the basis orthonormal after rotating.
	global_transform.basis = (
		Basis(rotation_quaternion) * current_basis
	).orthonormalized()

#endregion
