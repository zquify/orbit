extends Node3D

@export var damage: float = 20.0
@export var range: float = 200.0

@onready var player: CharacterBody3D = get_parent()

func _unhandled_input(event: InputEvent) -> void:
	if not player.is_multiplayer_authority():
		return

	if event.is_action_pressed("fire_weapon"):
		shoot()


func shoot() -> void:
	print("SHOOT")

	var camera: Camera3D = get_viewport().get_camera_3d()

	if camera == null:
		print("NO CAMERA")
		return

	var origin := camera.global_position
	var direction := -camera.global_transform.basis.z
	var end := origin + direction * range

	var query := PhysicsRayQueryParameters3D.create(origin, end)

	query.exclude = [player.get_rid()]

	var result := get_world_3d().direct_space_state.intersect_ray(query)

	if result.is_empty():
		print("MISS")
		return

	var hit_object = result["collider"]

	print("HIT: ", hit_object.name)

	if hit_object.has_method("take_damage"):
		print("DAMAGE!")
		hit_object.rpc("take_damage", damage)
	else:
		print("OBJECT CANNOT TAKE DAMAGE")
