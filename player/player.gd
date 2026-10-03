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

#region Combat

@export_category("Combat")
@export var max_health: float = 100.0
@export var damage_per_shot: float = 20.0

var health: float

signal health_changed(current_health: float, maximum_health: float)
signal player_ready(player: CharacterBody3D)

@onready var body_mesh: CSGMesh3D = $CSGMesh3D
var normal_color: Color
var hit_color := Color("#ff5454")

#endregion


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

## Maximum speed while sprinting along a surface.
@export var sprint_speed: float = 16.0

## Multiplier applied to acceleration while sprinting.
@export var sprint_acceleration_multiplier: float = 1.5

## Rate at which the player accelerates toward the target movement speed
## while standing on a surface.
@export var ground_acceleration: float = 55.0

## Rate at which the player slows down while standing on a surface.
@export var ground_deceleration: float = 100.0

## Rate at which the player changes horizontal movement while airborne.
@export var air_acceleration: float = 22.0

## Rate at which the player loses horizontal movement while airborne.
@export var air_deceleration: float = 10.0

@export_category("Stamina")

## Maximum stamina available.
@export var max_stamina: float = 100.0

## Stamina consumed per second while sprinting.
@export var stamina_drain_rate: float = 25.0

## Stamina recovered per second when not sprinting.
@export var stamina_regen_rate: float = 20.0

## Stamina required before sprinting can resume after exhaustion.
@export var stamina_recovery_threshold: float = 15.0

## Current stamina.
var stamina: float = 100.0

## Prevents sprinting until stamina has recovered enough.
var stamina_exhausted: bool = false

#endregion

#region Crouching

@export_category("Crouching")

## Vertical scale of the player mesh while crouching.
@export_range(0.1, 1.0) var crouch_scale: float = 0.6

## Maximum movement speed while crouching.
@export var crouch_speed: float = 5.0

## Speed at which crouch visuals transition.
@export var crouch_transition_speed: float = 10.0

## Whether the player is currently crouching.
var is_crouching: bool = false

#endregion

#region Sliding

@export_category("Sliding")

## Minimum surface speed required to start a slide.
@export var slide_min_speed: float = 8.0

## Additional surface speed applied when a slide starts.
@export var slide_initial_boost: float = 2.0

## Surface speed lost per second while sliding.
@export var slide_deceleration: float = 2.0

## Surface speed at which a slide ends.
@export var slide_end_speed: float = 5.0

## Backward visual tilt applied while sliding, in degrees.
@export_range(0.0, 90.0) var slide_tilt_degrees: float = 55.0

## Whether the player is currently sliding.
var is_sliding: bool = false

#endregion

#region Crouch Visual State

## Original scale of the player mesh.
var standing_mesh_scale: Vector3

## Original position of the player mesh.
var standing_mesh_position: Vector3

## Original rotation of the player mesh.
var standing_mesh_rotation: Vector3

## Original height of the player's capsule collider.
var standing_collider_height: float

## Original position of the player's capsule collider.
var standing_collider_position: Vector3

## Original position of the camera target.
var standing_camera_target_position: Vector3

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

## Pivot used to control the player camera.
@onready var camera_pivot: Node3D = $CameraPivot

## Target position followed by the player camera.
@onready var camera_target: Node3D = $CameraTarget

## Collision shape used for the player's physical body.
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

#endregion


#region Initialization

func _ready() -> void:
	# Only the peer that owns this player should control its camera.
	var local_player := is_multiplayer_authority()

	camera_pivot.set_process(local_player)
	camera_pivot.set_physics_process(local_player)
	camera_pivot.set_process_unhandled_input(local_player)

	var camera := camera_pivot.get_node_or_null("Camera3D")

	if camera:
		camera.current = local_player

	health = max_health

	stamina = max_stamina

	body_mesh.material = body_mesh.material.duplicate()
	normal_color = body_mesh.material.albedo_color

	standing_mesh_scale = body_mesh.scale
	standing_mesh_position = body_mesh.position
	standing_mesh_rotation = body_mesh.rotation
	standing_camera_target_position = camera_target.position

	var capsule: CapsuleShape3D = collision_shape.shape.duplicate()
	collision_shape.shape = capsule

	standing_collider_height = capsule.height
	standing_collider_position = collision_shape.position

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
	
	if is_multiplayer_authority():
		player_ready.emit(self)

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
	update_crouch_visuals(delta)
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

## Updates surface movement, sprinting, stamina, crouching, and sliding.
func handle_movement(gravity_up: Vector3, delta: float) -> void:
	var input_2d: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_backward",
		"move_forward"
	)

	var gravity_velocity: Vector3 = velocity.project(gravity_up)
	var surface_velocity: Vector3 = velocity - gravity_velocity

	var camera_forward: Vector3 = -camera_pivot.global_transform.basis.z
	var camera_right: Vector3 = camera_pivot.global_transform.basis.x

	camera_forward = camera_forward.slide(gravity_up)
	camera_right = camera_right.slide(gravity_up)

	if camera_forward.length_squared() > VECTOR_EPSILON_SQUARED:
		camera_forward = camera_forward.normalized()

	if camera_right.length_squared() > VECTOR_EPSILON_SQUARED:
		camera_right = camera_right.normalized()

	var move_direction: Vector3 = (
		camera_right * input_2d.x
		+ camera_forward * input_2d.y
	)

	if move_direction.length_squared() > VECTOR_EPSILON_SQUARED:
		move_direction = move_direction.normalized()

	var has_movement_input: bool = (
		move_direction.length_squared() > VECTOR_EPSILON_SQUARED
	)

	var sprint_held: bool = Input.is_action_pressed("sprint")
	var crouch_held: bool = Input.is_action_pressed("crouch")
	var surface_speed: float = surface_velocity.length()

	var wants_to_sprint: bool = (
		sprint_held
		and has_movement_input
		and not crouch_held
		and not stamina_exhausted
		and stamina > 0.0
	)

	var acceleration: float
	var deceleration: float

	if is_on_floor():
		acceleration = ground_acceleration
		deceleration = ground_deceleration
	else:
		acceleration = air_acceleration
		deceleration = air_deceleration

	if (
		not is_sliding
		and crouch_held
		and sprint_held
		and has_movement_input
		and not stamina_exhausted
		and stamina > 0.0
		and surface_speed >= slide_min_speed
	):
		is_sliding = true
		surface_velocity += surface_velocity.normalized() * slide_initial_boost
		surface_speed = surface_velocity.length()

	if is_sliding and (
		not crouch_held
		or surface_speed <= slide_end_speed
	):
		is_sliding = false

	is_crouching = crouch_held and not is_sliding

	var is_sprinting: bool = false

	if not is_sliding:
		if wants_to_sprint:
			stamina = maxf(
				stamina - stamina_drain_rate * delta,
				0.0
			)

			if stamina <= 0.0:
				stamina_exhausted = true
			else:
				is_sprinting = true

		elif not sprint_held:
			stamina = minf(
				stamina + stamina_regen_rate * delta,
				max_stamina
			)

			if (
				stamina_exhausted
				and stamina >= stamina_recovery_threshold
			):
				stamina_exhausted = false

	var target_speed: float = move_speed

	if is_sliding:
		target_speed = surface_speed
	elif is_crouching:
		target_speed = crouch_speed
	elif is_sprinting:
		target_speed = sprint_speed

	if is_sliding:
		# Preserve momentum while sliding; do not drain stamina.
		surface_velocity = surface_velocity.move_toward(
			Vector3.ZERO,
			slide_deceleration * delta
		)

	elif has_movement_input:
		var target_velocity: Vector3 = move_direction * target_speed
		var movement_acceleration: float = acceleration

		if is_sprinting:
			movement_acceleration *= sprint_acceleration_multiplier

		surface_velocity = surface_velocity.move_toward(
			target_velocity,
			movement_acceleration * delta
		)

	else:
		surface_velocity = surface_velocity.move_toward(
			Vector3.ZERO,
			deceleration * delta
		)

	if is_on_floor():
		var current_surface_speed: float = surface_velocity.length()
		var surface_speed_limit: float = move_speed

		if is_sliding:
			surface_speed_limit = maxf(
				sprint_speed,
				slide_min_speed + slide_initial_boost
			)
		elif is_sprinting:
			surface_speed_limit = sprint_speed
		elif is_crouching:
			surface_speed_limit = crouch_speed

		if current_surface_speed > surface_speed_limit:
			surface_velocity = (
				surface_velocity.normalized() * surface_speed_limit
			)

	velocity = surface_velocity + gravity_velocity


#endregion

#region Crouching

## Smoothly updates the mesh and camera target for crouching and sliding.
func update_crouch_visuals(delta: float) -> void:
	var target_scale: Vector3 = standing_mesh_scale
	var target_position: Vector3 = standing_mesh_position
	var target_rotation: Vector3 = standing_mesh_rotation
	var target_camera_position: Vector3 = standing_camera_target_position

	if is_crouching:
		target_scale.y *= crouch_scale
		target_position.y = standing_mesh_position.y * crouch_scale
		target_camera_position.y *= crouch_scale

		var capsule: CapsuleShape3D = collision_shape.shape
		capsule.height = standing_collider_height * crouch_scale
		collision_shape.position.y = (
			standing_collider_position.y * crouch_scale
		)
	else:
		var capsule: CapsuleShape3D = collision_shape.shape
		capsule.height = standing_collider_height
		collision_shape.position = standing_collider_position

	if is_sliding:
		target_rotation.x += deg_to_rad(slide_tilt_degrees)

	var weight: float = 1.0 - exp(-crouch_transition_speed * delta)

	body_mesh.scale = body_mesh.scale.lerp(target_scale, weight)
	body_mesh.position = body_mesh.position.lerp(target_position, weight)
	body_mesh.rotation = body_mesh.rotation.lerp(target_rotation, weight)

	camera_target.position = camera_target.position.lerp(
		target_camera_position,
		weight
	)

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


#region Combat

@rpc("any_peer", "call_remote", "reliable")
func take_damage(amount: float) -> void:
	if not is_multiplayer_authority():
		return

	health = max(health - amount, 0.0)
	health_changed.emit(health, max_health)

	print(name, " took ", amount, " damage. Health: ", health)

	flash_hit.rpc()

	if health <= 0.0:
		die()



@rpc("authority", "call_local", "reliable")
func flash_hit() -> void:
	body_mesh.material.albedo_color = hit_color
	await get_tree().create_timer(0.08).timeout
	body_mesh.material.albedo_color = normal_color


func die() -> void:
	var world := get_parent().get_parent()

	if not world.has_method("get_spawn_transform"):
		return

	global_transform = world.get_spawn_transform(int(name))
	velocity = Vector3.ZERO

	health = max_health
	health_changed.emit(health, max_health)


func respawn(spawn_transform: Transform3D) -> void:
	global_transform = spawn_transform
	velocity = Vector3.ZERO

	health = max_health
	health_changed.emit(health, max_health)

#endregion
