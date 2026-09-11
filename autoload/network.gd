extends Node
## Manages the game's multiplayer connection.
##
## NodeTunnel provides the MultiplayerPeer used by Godot's high-level
## multiplayer API.

const RELAY := "us-east.nodetunnel.io:8080"
const APP_ID := "pvaffvacbfy6i8t"

var peer: NodeTunnelPeer


func _ready() -> void:
	# Create the NodeTunnel multiplayer peer.
	peer = NodeTunnelPeer.new()

	# Connect NodeTunnel signals.
	peer.error.connect(_on_error)
	peer.forced_disconnect.connect(_on_forced_disconnect)
	peer.authenticated.connect(_on_authenticated)
	peer.room_connected.connect(_on_room_connected)

	# Connect Godot multiplayer signals.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	print("Connecting to NodeTunnel relay...")

	var err := peer.connect_to_relay(RELAY, APP_ID)

	print("connect_to_relay() returned: ", err)

	if err != OK:
		push_error("Failed to connect to NodeTunnel.")
		return

	# NodeTunnel is our MultiplayerPeer.
	#
	# From this point onward, Godot's multiplayer API uses it for
	# peer-to-peer communication.
	multiplayer.multiplayer_peer = peer

	print("Peer assigned to multiplayer.")


func _on_authenticated() -> void:
	print("Network: authenticated")


func _on_room_connected() -> void:
	print("Network: room connected")
	print("Network: room code: ", peer.room_id)


func _on_peer_connected(id: int) -> void:
	print("Network: player joined")
	print("Network: peer ID: ", id)


func _on_peer_disconnected(id: int) -> void:
	print("Network: player disconnected")
	print("Network: peer ID: ", id)


func _on_connected_to_server() -> void:
	print("Network: Godot multiplayer connected to server.")
	print("Network: my peer ID: ", multiplayer.get_unique_id())


func _on_server_disconnected() -> void:
	print("Network: Godot multiplayer server disconnected.")


func _on_error(message: String) -> void:
	print("Network: NODETUNNEL ERROR:")
	print(message)


func _on_forced_disconnect() -> void:
	print("Network: NODETUNNEL FORCED DISCONNECT")
