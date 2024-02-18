extends Node2D
const Room := preload("res://addons/matcha/room.gd")

var server_room: Room
var client_room: Room

func _on_start_server_pressed():
	$start_server.disabled = true
	server_room = Room.new()
	server_room.create_server()
	$server_roomid_edit.text = server_room.room_id
	$client_roomid_edit.text = server_room.room_id
	$start_client.disabled = false
	$logs.text += "[Server] Joined (room_id=%s)\n" % [server_room.room_id]

	server_room.peer_joined.connect(func(peer_id: int):
		$logs.text += "[Server] Peer joined (id=%s)\n" % [peer_id]
	)
	server_room.peer_left.connect(func(peer_id: int):
		$logs.text += "[Server] Peer left (id=%s)\n" % [peer_id]
	)

func _on_start_client_pressed():
	$start_client.disabled = true
	$client_roomid_edit.editable = false
	client_room = Room.new()
	client_room.create_client($client_roomid_edit.text)
	$logs.text += "[Client] Joined (room_id=%s)\n" % [$client_roomid_edit.text]

	client_room.peer_joined.connect(func(peer_id: int):
		$logs.text += "[Client] Peer joined (id=%s)\n" % [peer_id]
	)
	client_room.peer_left.connect(func(peer_id: int):
		$logs.text += "[Client] Peer left (id=%s)\n" % [peer_id]
	)

func _on_client_roomid_edit_text_changed(new_text):
	$start_client.disabled = new_text.length() == 0
