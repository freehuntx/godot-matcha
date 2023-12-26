extends Node2D

var matcha_room := MatchaRoom.new()
var players = {}

var local_player:
	get: return players[multiplayer.get_unique_id()]

func _ready():
	multiplayer.multiplayer_peer = matcha_room.rtc_peer
	_register(multiplayer.get_unique_id())

	matcha_room.rtc_peer.peer_connected.connect(func(peer_id):
		_register.rpc_id(peer_id, multiplayer.get_unique_id())
	)
	matcha_room.rtc_peer.peer_disconnected.connect(func(peer_id):
		if peer_id in players:
			$Players.remove_child(players[peer_id].node)
	)

@rpc("any_peer", "call_remote")
func _register(real_peer_id: int):
	var peer_id = multiplayer.get_unique_id() if multiplayer.get_remote_sender_id() == 0 else multiplayer.get_remote_sender_id()
	if peer_id in players: return

	var node := preload("res://examples/bobble/components/player.tscn").instantiate()
	var player = {
		"peer_id": peer_id,
		"real_peer_id": real_peer_id,
		"node": node
	}
	node.name = "Player_%s" % real_peer_id
	node.position = Vector2(100, 100)
	players[player.peer_id] = player
	$Players.add_child(node)
	node.set_multiplayer_authority(player.peer_id)

func _on_line_edit_text_submitted(new_text):
	$UI/LineEdit.text = ""
	local_player.node.set_message(new_text)
