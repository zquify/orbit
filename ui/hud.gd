extends Control

@onready var crosshair: AnimatedSprite2D = $Crosshair
@onready var room_code: Label = $RoomCode
@onready var health_bar: ProgressBar = $HealthBar

var player: CharacterBody3D


func _ready() -> void:
	room_code.text = "Room Code: " + str(Network.peer.room_id)

	await get_tree().process_frame

	while player == null:
		_find_local_player()
		if player == null:
			await get_tree().process_frame


func _process(_delta: float) -> void:
	if Input.is_action_pressed("zoom"):
		crosshair.animation = "small"
	else:
		crosshair.animation = "big"


func _find_local_player() -> void:
	var players_node := get_parent().get_node("Players")

	for node in players_node.get_children():
		if node is CharacterBody3D and node.is_multiplayer_authority():
			player = node
			_connect_to_player(player)
			return



func _connect_to_player(player_node: CharacterBody3D) -> void:
	health_bar.max_value = player_node.max_health
	health_bar.value = player_node.health

	player_node.health_changed.connect(_on_health_changed)


func _on_health_changed(current_health: float, maximum_health: float) -> void:
	health_bar.max_value = maximum_health
	health_bar.value = current_health
