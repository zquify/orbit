extends Control
## Handles the game's host and join menu.
##
## NodeTunnel handles creating and joining rooms. Godot's multiplayer API
## handles the actual game networking once a room is connected.

@onready var host_button: Button = $VBoxContainer/HostButton
@onready var room_code: LineEdit = $VBoxContainer/RoomCode
@onready var join_button: Button = $VBoxContainer/JoinButton
@onready var status: Label = $VBoxContainer/Status


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)

	host_button.disabled = true
	join_button.disabled = true
	room_code.editable = false

	status.text = "Connecting to NodeTunnel..."

	Network.peer.authenticated.connect(_on_authenticated)
	Network.peer.room_connected.connect(_on_room_connected)
	Network.peer.error.connect(_on_error)
	Network.peer.forced_disconnect.connect(_on_forced_disconnect)


func _on_authenticated() -> void:
	status.text = "Connected to NodeTunnel."

	host_button.disabled = false
	join_button.disabled = false
	room_code.editable = true


func _on_host_pressed() -> void:
	print("Network: hosting room")

	status.text = "Creating room..."

	host_button.disabled = true
	join_button.disabled = true
	room_code.editable = false

	var err := Network.peer.host_room(true, "UNL Pitch Test")

	print("host_room() returned: ", err)

	if err != OK:
		status.text = "Failed to create room."

		host_button.disabled = false
		join_button.disabled = false
		room_code.editable = true


func _on_join_pressed() -> void:
	var code := room_code.text.strip_edges()

	if code.is_empty():
		status.text = "Enter a room code first."
		return

	print("Network: joining room ", code)

	status.text = "Joining room..."

	host_button.disabled = true
	join_button.disabled = true
	room_code.editable = false

	var err := Network.peer.join_room(code)

	print("join_room() returned: ", err)

	if err != OK:
		status.text = "Failed to join room."

		host_button.disabled = false
		join_button.disabled = false
		room_code.editable = true


func _on_room_connected() -> void:
	print("Network: room connected!")
	print("Network: room code: ", Network.peer.room_id)

	room_code.text = Network.peer.room_id
	status.text = "Connected to room: " + str(Network.peer.room_id)

	# For the prototype, immediately enter the game world.
	get_tree().change_scene_to_file("res://world/world.tscn")


func _on_error(message: String) -> void:
	status.text = "Error: " + message

	host_button.disabled = false
	join_button.disabled = false
	room_code.editable = true


func _on_forced_disconnect() -> void:
	status.text = "Disconnected from NodeTunnel."

	host_button.disabled = true
	join_button.disabled = true
	room_code.editable = false
