extends Node3D
## Controls the multiplayer game world.
##
## The server creates players through MultiplayerSpawner, which replicates
## them to the other peers. Each player is owned by the peer controlling it.

const PLAYER_SCENE := preload("res://player/player.tscn")

@onready var players: Node3D = $Players
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var spawn_points: Node3D = $SpawnPoints


func _ready() -> void:
	# Tell the spawner how to create a player.
	player_spawner.spawn_function = _spawn_player

	if multiplayer.is_server():
		# The server creates all player instances.
		spawn_player(multiplayer.get_unique_id())

		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func spawn_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	player_spawner.spawn(peer_id)


func _spawn_player(peer_id: Variant) -> Node:
	var player := PLAYER_SCENE.instantiate()

	# Give the player the same name on every peer so its replicated NodePath
	# stays consistent.
	player.name = str(peer_id)

	# The peer that owns this player is responsible for controlling it.
	player.set_multiplayer_authority(int(peer_id), true)

	# Select a spawn point based on the peer ID.
	var spawn_index: int = (int(peer_id) - 1) % spawn_points.get_child_count()
	var spawn_point: Marker3D = spawn_points.get_child(spawn_index)

	# Place the player at the selected spawn point.
	player.global_transform = spawn_point.global_transform

	return player


func _on_peer_connected(id: int) -> void:
	print("World: spawning player for peer ", id)

	spawn_player(id)


func _on_peer_disconnected(id: int) -> void:
	print("World: peer disconnected: ", id)

	var player := players.get_node_or_null(str(id))

	if player:
		player.queue_free()
