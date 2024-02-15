extends Node2D
const Room := preload("res://addons/matcha/room.gd")
const PlayerComponent := preload("./components/player.tscn")

var room: Room
var players := {}
var local_player:
	get:
		if not room.peer_id in players: return null
		return players[room.peer_id]

func _enter_tree():
	room = Room.new()
	room.peer_joined.connect(self._on_peer_joined)
	room.peer_left.connect(self._on_peer_left)
	room.event.connect(self._on_room_event)
	room.create_mesh("com.matcha.examples.bobble")
	multiplayer.multiplayer_peer = room.multiplayer_peer

func _exit_tree():
	room = null

func _ready():
	_add_player(room.peer_id) # Add ourself

func _add_player(peer_id: int) -> void:
	if peer_id in players: return # That peer is already known

	var node := PlayerComponent.instantiate()
	node.name = "%s" % peer_id # The node must have the same name for every person. Otherwise syncing it will fail because path mismatch
	node.position = Vector2(randi() % 500, randi() % 500)
	players[peer_id] = node
	$Players.add_child(node)
	node.set_multiplayer_authority(peer_id)

func _remove_player(peer_id: int) -> void:
	if not peer_id in players: return # That peer is not known
	if $Players.has_node("%s" % peer_id):
		$Players.remove_child($Players.get_node("%s" % peer_id))

# Peer callbacks
func _on_peer_joined(peer_id: int) -> void:
	_add_player(peer_id) # Create the player

func _on_peer_left(peer_id: int) -> void:
	_remove_player(peer_id)

func _on_room_event(peer_id: int, event_name: String, event_args: Array, _broadcast: bool) -> void:
	if not peer_id in players:
		return

	var peer_node = players[peer_id]
	if event_name == "chat":
		var message = event_args[0]
		$UI/chat_history.text += "\n%s: %s" % [peer_id, message]
		peer_node.set_message(message)
	elif event_name == "secret":
		var sprite: Sprite2D = peer_node.get_node("Sprite2D")
		sprite.modulate = Color.from_hsv((randi() % 12) / 12.0, 1, 1)

# UI Callbacks
func _on_line_edit_text_submitted(new_text) -> void:
	if new_text == "": return
	$UI/chat_input.text = ""
	$UI/chat_history.text += "\n%s (Me): %s" % [room.peer_id, new_text]
	local_player.set_message(new_text)
	room.send_event("chat", [new_text])

func _on_secret_button_pressed() -> void:
	room.send_event("secret")

func _on_chat_send_pressed() -> void:
	_on_line_edit_text_submitted($UI/chat_input.text)
