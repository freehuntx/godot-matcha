class_name MatchaLobby extends RefCounted

# Signals
signal joined_room(room: MatchaRoom)
signal left_room(room: MatchaRoom)
signal room_created(room: Dictionary)
signal room_updated(room: Dictionary)
signal room_closed(room: Dictionary)

# Members
var _lobby: MatchaRoom
var _rooms := {}
var _current_room: MatchaRoom

# Getters
var room_list:
	get: return _rooms.values()
var current_room:
	get: return _current_room

# Constructor
func _init(options:={}):
	if not "identifier" in options: options.identifier = "com.matcha.lobby"
	_lobby = MatchaRoom.create_mesh_room(options)
	_lobby.peer_joined.connect(self._on_peer_joined)
	_lobby.peer_left.connect(self._on_peer_left)

# Public methods
func join_room(room_id: String) -> Error:
	var room = _find_room_by_id(room_id)
	if room == null:
		push_error("Room not found")
		return Error.ERR_DOES_NOT_EXIST
	if _current_room != null:
		push_error("Already in a room")
		return Error.ERR_ALREADY_IN_USE

	_current_room = MatchaRoom.create_client_room(room_id)
	joined_room.emit(_current_room)

	return Error.OK

func create_room(room_meta:={}) -> Error:
	if _current_room != null:
		push_error("Already in a room")
		return Error.ERR_ALREADY_IN_USE
	if _lobby.peer_id in _rooms:
		push_error("Already opened a room. Close it first!")
		return Error.ERR_ALREADY_IN_USE

	_current_room = MatchaRoom.create_server_room()
	var room = {
		"id": _current_room.id,
		"meta": room_meta
	}
	_rooms[_lobby.peer_id] = room

	_lobby.send_event("create_room", [room])
	room_created.emit(room)
	joined_room.emit(_current_room)

	return Error.OK

func update_room(room_meta:={}) -> Error:
	if not _lobby.peer_id in _rooms:
		push_error("No room opened.")
		return Error.ERR_DOES_NOT_EXIST

	var room = _rooms[_lobby.peer_id]
	room.meta = room_meta
	_lobby.send_event("update_room", [room.meta])
	room_updated.emit(room)

	return Error.OK

func leave_room() -> Error:
	if _current_room == null:
		push_error("Not in a room.")
		return Error.ERR_DOES_NOT_EXIST

	if _lobby.peer_id in _rooms:
		var room = _rooms[_lobby.peer_id]
		_rooms.erase(_lobby.peer_id)
		_lobby.send_event("close_room")
		room_closed.emit(room)

	var previous_room = _current_room
	_current_room = null
	left_room.emit(previous_room)

	return Error.OK

# Private methods
func _find_room_by_id(room_id: String):
	for room: Dictionary in _rooms.values():
		if room.id == room_id: return room
	return null

func _verify_room(room: Dictionary) -> bool:
	if typeof(room) != TYPE_DICTIONARY: return false
	if not "id" in room or not "meta" in room: return false
	if typeof(room.id) != TYPE_STRING or not _verify_room_meta(room.meta): return false
	return true

func _verify_room_meta(room_meta: Dictionary) -> bool:
	return typeof(room_meta) == TYPE_DICTIONARY

func _remove_room(room_id: String) -> bool:
	for peer_id: String in _rooms.keys():
		var room: Dictionary = _rooms[peer_id]
		if room.id != room_id: continue

		_rooms.erase(peer_id)
		if peer_id == _lobby.peer_id:
			_lobby.send_event("close_room")
		room_closed.emit(room)
		return true

	return false

# Peer callbacks
func _on_peer_joined(id: int, peer: MatchaPeer) -> void:
	peer.on_event("create_room", self._on_peer_created_room.bind(peer))
	peer.on_event("update_room", self._on_peer_updated_room.bind(peer))
	peer.on_event("close_room", self._on_peer_closed_room.bind(peer))

	if _lobby.peer_id in _rooms:
		peer.send_event("create_room", [_rooms[_lobby.peer_id]])

func _on_peer_left(_rpc_id: int, peer: MatchaPeer) -> void:
	if peer.id in _rooms:
		var room = _rooms[peer.id]
		_rooms.erase(peer.id)
		room_closed.emit(room)

# Peer events
func _on_peer_created_room(room, peer: MatchaPeer) -> void:
	if peer.id in _rooms: return
	if not _verify_room(room): return

	_rooms[peer.id] = room
	room_created.emit(room)

func _on_peer_updated_room(room_meta: Dictionary, peer: MatchaPeer) -> void:
	if not peer.id in _rooms: return
	if not _verify_room_meta(room_meta): return

	_rooms[peer.id].meta = room_meta
	room_updated.emit(_rooms[peer.id])

func _on_peer_closed_room(peer: MatchaPeer) -> void:
	if peer.id in _rooms:
		var room = _rooms[peer.id]
		_rooms.erase(peer.id)
		room_closed.emit(room)
