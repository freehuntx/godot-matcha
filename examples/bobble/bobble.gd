extends Node2D
const PlayerComponent := preload("./components/player.tscn")

var matcha_room := MatchaRoom.create_mesh_room()
var local_player:
	get:
		if not $Players.has_node(matcha_room.peer_id): return null
		return $Players.get_node(matcha_room.peer_id)

func _ready():
	multiplayer.multiplayer_peer = matcha_room
	_join.rpc(matcha_room.peer_id)

	matcha_room.peer_joined.connect(func(id: int, _peer: MatchaPeer):
		_join.rpc_id(id, matcha_room.peer_id) # Tell the new peer about us
	)
	matcha_room.peer_left.connect(func(_id: int, peer: MatchaPeer):
		if $Players.has_node(peer.peer_id): # Remove the player if it exists
			$Players.remove_child($Players.get_node(peer.peer_id))
	)

@rpc("any_peer", "call_local")
func _join(peer_id: String):
	if $Players.has_node(peer_id): return # That peer is already known
		
	var node := PlayerComponent.instantiate()
	node.name = peer_id # The node must have the same name for every person. Otherwise syncing it will fail because path mismatch
	node.position = Vector2(100, 100)
	$Players.add_child(node)
	node.set_multiplayer_authority(multiplayer.get_remote_sender_id())

func _on_line_edit_text_submitted(new_text):
	$UI/LineEdit.text = ""
	local_player.set_message(new_text)
