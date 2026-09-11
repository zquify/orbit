extends Control
@onready var crosshair: AnimatedSprite2D = $Crosshair
@onready var room_code: Label = $RoomCode


func _ready() -> void:
	room_code.text = "Room Code: " + str(Network.peer.room_id)

# Called every frame. 'delta' is the elapsed time since the previous frame. If the "zoom" key is held, switch to "small" animation, otherwise switch to "big" animation
func _process(_delta: float) -> void:
	if Input.is_action_pressed("zoom"):
		crosshair.animation = "small"
	else:
		crosshair.animation = "big"
