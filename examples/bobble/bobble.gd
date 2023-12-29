extends Node2D
const PlayerComponent := preload("./components/player.tscn")

var matcha_room := MatchaRoom.create_mesh_room()
var local_player:
	get:
		if not $Players.has_node(matcha_room.peer_id): return null
		return $Players.get_node(matcha_room.peer_id)

func _enter_tree():
	multiplayer.multiplayer_peer = matcha_room

func _ready():
	_create_player(matcha_room.peer_id, multiplayer.get_unique_id())

	matcha_room.peer_joined.connect(func(id: int, peer: MatchaPeer):
		_create_player(peer.peer_id, id)
	)
	matcha_room.peer_left.connect(func(_id: int, peer: MatchaPeer):
		if $Players.has_node(peer.peer_id): # Remove the player if it exists
			$Players.remove_child($Players.get_node(peer.peer_id))
	)

func _create_player(peer_id: String, authority_id: int):
	if $Players.has_node(peer_id): return # That peer is already known

	var node := PlayerComponent.instantiate()
	node.name = peer_id # The node must have the same name for every person. Otherwise syncing it will fail because path mismatch
	node.position = Vector2(100, 100)
	$Players.add_child(node)
	node.set_multiplayer_authority(authority_id)

func _on_line_edit_text_submitted(new_text):
	$UI/LineEdit.text = ""
	local_player.set_message(new_text)
