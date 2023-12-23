extends Node2D

var tracker_room := TrackerRoom.new({ "info_hash": "2v2s134t4t245168j4w5" })

func _init():
	tracker_room.on("peer_connected", func(peer_id, peer):
		print("Peer connected: ", peer_id)
	)
	
	tracker_room.on("peer_disconnected", func(peer_id, peer):
		print("Peer disconnected: ", peer_id)
	)
