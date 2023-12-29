# godot-matcha
Easy webrtc matchmaking using WebTorrent tracker.  
This project uses webtorrent to do signaling. This allows you to connect players peer2peer without a server!  
I plan on improving this library and add more features. Stay tuned!

### [Try the demo here](https://freehuntx.github.io/godot-matcha/)

## Installation
1. Copy `addons/matcha` to your godot project.
2. For non browser builds: Install [webrtc-native](https://github.com/godotengine/webrtc-native)
3. Done!

## Usage
### Example (Mesh):

```
extends Node

var mp1 := MatchaRoom.create_mesh_room({ "identifier": "my-unique-game-identifier" })
var mp2 := MatchaRoom.create_mesh_room({ "identifier": "my-unique-game-identifier" })

func _init():
	mp1.peer_joined.connect(func(_id, peer):
		print("(1) Peer connected: ", peer.peer_id)
	)

	mp1.peer_left.connect(func(_id, peer):
		print("(1) Peer disconnected: ", peer.peer_id)
	)

	mp2.peer_joined.connect(func(_id, peer):
		print("(2) Peer connected: ", peer.peer_id)
	)

	mp2.peer_left.connect(func(_id, peer):
		print("(2) Peer disconnected: ", peer.peer_id)
	)
```

### Example (Server/Client):
```
extends Node

var server := MatchaRoom.create_server_room()
var client := MatchaRoom.create_client_room(server.room_id) # Client must know the room id

func _init():
	server.peer_joined.connect(func(_id, peer):
		print("(server) Peer connected: ", peer.peer_id)
	)

	server.peer_left.connect(func(_id, peer):
		print("(server) Peer disconnected: ", peer.peer_id)
	)

	client.peer_joined.connect(func(_id, peer):
		print("(client) Peer connected: ", peer.peer_id)
	)

	client.peer_left.connect(func(_id, peer):
		print("(client) Peer disconnected: ", peer.peer_id)
	)
```

# Changelog
### 29. Dec. 2023
- Added example for server/client implementation
- Improved MatchaPeer class
  - Made it extend from WebRTCPeerConnectionExtension
    - This allows you to use it like an WebRTCPeerConnection
- Improved MatchaRoom class
  - Made it extend from MultiplayerPeerExtension
    - This allows you to use it like an MultiplayerPeer
  - Added peer_joined/peer_left signals for direct access to the peer
  - Changed naming from info_hash to room_id
  - Added client/server/mesh functionality
- Improved TrackerClient class
  - Proper user-agent for non-web environment
  - Cleaner code
  - More documentation
- Prepared nostr implementation
  - In the future you can use nostr aswell as webtorrent
- Prepared lobby implementation
  - In the future you can find/list/create lobbies


### 26. Dec. 2023
- Replaces EventEmitter with native Signals
  - EventEmitter did not improve RefCounted reference issue behaviour so replaced it with signals
- Removed TrackerRoom class
  - Got replaced with MatchaRoom
- Exposed MatchaRoom class
  - Using multiplayer api
- Added example game "bobble"
- Added web export github page for example

### 23. Dec. 2023
- Initial commit
- Exposed TrackerRoom class
