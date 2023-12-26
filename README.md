# godot-matcha
Easy webrtc matchmaking using WebTorrent tracker.  
This project uses webtorrent to do signaling. This allows you to connect players peer2peer without a server!  
I plan on improving this library and add more features. Stay tuned!

### [Try the demo here](https://freehuntx.github.io/godot-matcha/) (Currently not working)

## Installation
1. Copy `addons/matcha` to your godot project.
2. For non browser builds: Install [webrtc-native](https://github.com/godotengine/webrtc-native)
3. Done!

## Usage
Example:
```
extends Node

var room1 := MatchaRoom.new({ "identifier": "my-unique-game-identifier" })
var room2 := MatchaRoom.new({ "identifier": "my-unique-game-identifier" })

func _init():
	var rtc1: WebRTCMultiplayerPeer = room1.rtc_peer
	var rtc2: WebRTCMultiplayerPeer = room1.rtc_peer

	rtc1.peer_connected.connect(func(id):
		print("(1) Peer connected: ", id)
	)

	rtc1.peer_disconnected.connect(func(id):
		print("(1) Peer disconnected: ", id)
	)

	rtc2.peer_connected.connect(func(id):
		print("(2) Peer connected: ", id)
	)

	rtc2.peer_disconnected.connect(func(id):
		print("(2) Peer disconnected: ", id)
	)
```

# Changelog
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
