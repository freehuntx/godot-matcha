extends CharacterBody2D

const SPEED = 300.0
var chat_message_time: float

func set_message(message: String) -> void:
	$Label.text = message
	chat_message_time = Time.get_unix_time_from_system()

func _handle_walk():
	var x_dir = Input.get_axis("ui_left", "ui_right")
	var y_dir = Input.get_axis("ui_up", "ui_down")
	
	if x_dir: velocity.x = x_dir * SPEED
	else: velocity.x = move_toward(velocity.x, 0, SPEED)
	
	if y_dir: velocity.y = y_dir * SPEED
	else: velocity.y = move_toward(velocity.y, 0, SPEED)

	move_and_slide()

func _process(_delta):
	if get_multiplayer_authority() != multiplayer.get_unique_id(): return
	_handle_walk()
	if chat_message_time > 0 and Time.get_unix_time_from_system() - chat_message_time > 10:
		chat_message_time = 0
		$Label.text = ""
