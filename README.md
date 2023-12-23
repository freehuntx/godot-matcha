# godot-matcha
Easy webrtc matchmaking using WebTorrent tracker.  
This project uses webtorrent to do signaling. This allows you to connect players peer2peer without a server!  
I plan on improving this library and add more features. Stay tuned!

## Installation
1. Copy `addons/matcha` to your godot project.
2. Done!

## Usage
Example:
```
extends Node

var tracker_room1 := TrackerRoom.new({ "identifier": "my-unique-game-identifier" })
var tracker_room2 := TrackerRoom.new({ "identifier": "my-unique-game-identifier" })

func _init():
  tracker_room1.on("peer_connected", func(peer_id: String, peer: WebRtcPeerConnection):
    print("(1) Peer connected: ", peer_id)
  )
  tracker_room1.on("peer_disconnected", func(peer_id: String, peer: WebRtcPeerConnection):
    print("(1) Peer disconnected: ", peer_id)
  )
  
  tracker_room2.on("peer_connected", func(peer_id: String, peer: WebRtcPeerConnection):
    print("(2) Peer connected: ", peer_id)
  )
  tracker_room2.on("peer_disconnected", func(peer_id: String, peer: WebRtcPeerConnection):
    print("(2) Peer disconnected: ", peer_id)
  )
```
