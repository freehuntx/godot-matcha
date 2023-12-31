extends Node2D
const PlayerComponent := preload("./components/player.tscn")

var matcha_room := MatchaRoom.create_mesh_room()
var players := {}
var local_player:
	get:
		if not matcha_room.peer_id in players: return null
		return players[matcha_room.peer_id]

func _init():
	matcha_room.peer_joined.connect(self._on_peer_joined)
	matcha_room.peer_left.connect(self._on_peer_left)

func _enter_tree():
	multiplayer.multiplayer_peer = matcha_room

func _ready():
	_add_player(matcha_room.peer_id, multiplayer.get_unique_id()) # Add ourself

func _add_player(peer_id: String, authority_id: int) -> void:
	if peer_id in players: return # That peer is already known

	var node := PlayerComponent.instantiate()
	node.name = peer_id # The node must have the same name for every person. Otherwise syncing it will fail because path mismatch
	node.position = Vector2(100, 100)
	players[peer_id] = node
	$Players.add_child(node)
	node.set_multiplayer_authority(authority_id)

func _remove_player(peer_id: String) -> void:
	if not peer_id in players: return # That peer is not known
	$Players.remove_child($Players.get_node(peer_id))

# Peer callbacks
func _on_peer_joined(id: int, peer: MatchaPeer) -> void:
	# Listen to events the other peer may send
	peer.on_event("chat", self._on_peer_chat.bind(peer))
	peer.on_event("secret", self._on_peer_secret.bind(peer))
	_add_player(peer.peer_id, id) # Create the player

func _on_peer_left(_id: int, peer: MatchaPeer) -> void:
	_remove_player(peer.peer_id)

func _on_peer_chat(message: String, peer: MatchaPeer) -> void:
	$UI/chat_history.text += "\n%s: %s" % [peer.peer_id, message]
	players[peer.peer_id].set_message(message)

func _on_peer_secret(peer: MatchaPeer) -> void:
	var sprite: Sprite2D = players[peer.peer_id].get_node("Sprite2D")
	sprite.modulate = Color.from_hsv((randi() % 12) / 12.0, 1, 1)

# UI Callbacks
func _on_line_edit_text_submitted(new_text) -> void:
	if new_text == "": return
	$UI/chat_input.text = ""
	$UI/chat_history.text += "\n%s (Me): %s" % [matcha_room.peer_id, new_text]
	local_player.set_message(new_text)
	matcha_room.send_event("chat", [new_text])

func _on_secret_button_pressed() -> void:
	matcha_room.send_event("secret")

func _on_chat_send_pressed() -> void:
	_on_line_edit_text_submitted($UI/chat_input.text)
