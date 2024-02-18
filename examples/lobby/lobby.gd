extends Node2D
const Room := preload("res://addons/matcha/room.gd")
const Lobby := preload("res://addons/matcha/lobby.gd")

@onready var _room_list: ItemList = $room_list
var _lobby := Lobby.new()
var _current_room: Room
var _selected_room

func _init():
	#_lobby.joined_room.connect(self._on_joined_room)
	#_lobby.left_room.connect(self._on_left_room)
	#_lobby.room_created.connect(self._on_room_created)
	#_lobby.room_updated.connect(self._on_room_updated)
	#_lobby.room_closed.connect(self._on_room_closed)
#signal room_list_updated
#signal room_created(id: String, type: RoomType, meta: Dictionary)
#signal room_updated(id: String, type, RoomType, meta: Dictionary)
#signal room_closed(id: String)
	_lobby.room_created.connect(self._on_room_created)
	_lobby.room_updated.connect(self._on_room_updated)
	_lobby.room_closed.connect(self._on_room_closed)
	_lobby.join("com.matcha.examples.lobby")

#func _ready():
#	lobby.create_room({ "name": "Penis" })

# Private methods

# Callbacks
func _on_room_created(id: String, type: Lobby.RoomType, meta: Dictionary) -> void:
	var room_name = "Unnamed room (%s)" % [id]
	if "name" in meta and meta.name != "":
		room_name = meta.name

	var index := _room_list.add_item(room_name)
	_room_list.set_item_metadata(index, { id=id, type=type, meta=meta })

func _on_room_updated(id: String, type: Lobby.RoomType, meta: Dictionary) -> void:
	for i in _room_list.item_count:
		var list_room = _room_list.get_item_metadata(i)
		if list_room.id != id: continue
		_room_list.set_item_metadata(i, { id=id, type=type, meta=meta })

		if "name" in meta and meta.name != "":
			_room_list.set_item_text(i, meta.name)

		return

func _on_room_closed(id: String) -> void:
	for i in _room_list.item_count:
		var list_room = _room_list.get_item_metadata(i)
		if list_room.id != id: continue
		_room_list.remove_item(i)
		return

func _on_joined_room():
	$current_room/room_log.text += "Joined the room!\n"
	$current_room/room_leave_btn.disabled = false

func _on_left_room():
	_current_room = null
	$current_room/room_log.text += "Left the room\n"
	$current_room/room_leave_btn.disabled = true
	$room_join_btn.disabled = false
	$room_create_btn.disabled = false

func _on_failed_room() -> void:
	$current_room/room_log.text += "Failed joining the room!\n"
	$current_room/room_leave_btn.disabled = true
	$room_join_btn.disabled = false
	$room_create_btn.disabled = false

func _on_peer_joined(peer_id: int) -> void:
	$current_room/room_log.text += "Peer '%s' joined the room\n" % peer_id

func _on_peer_left(peer_id: int) -> void:
	$current_room/room_log.text += "Peer '%s' left the room\n" % peer_id

func _on_room_created2(room: Dictionary) -> void:
	var room_name = "Unnamed room (%s)" % [room.id]
	if "name" in room.meta and room.meta.name != "":
		room_name = room.meta.name

	var index := _room_list.add_item(room_name)
	_room_list.set_item_metadata(index, room)

func _on_room_updated2(room: Dictionary) -> void:
	for i in _room_list.item_count:
		var list_room = _room_list.get_item_metadata(i)
		if list_room.id != room.id: continue
		_room_list.set_item_metadata(i, room)

		if "name" in room.meta and room.meta.name != "":
			_room_list.set_item_text(i, room.meta.name)

		return

func _on_room_closed2(room: Dictionary) -> void:
	for i in _room_list.item_count:
		var list_room = _room_list.get_item_metadata(i)
		if list_room.id != room.id: continue
		_room_list.remove_item(i)
		return

func _on_peer_joined_room(_rpc_id: int, peer: MatchaPeer):
	$current_room/room_log.text += "Peer joined the room (id: %s)\n" % [peer.id]

func _on_peer_left_room(_rpc_id: int, peer: MatchaPeer):
	$current_room/room_log.text += "Peer left the room (id: %s)\n" % [peer.id]

# UI Callbacks
func _on_room_create_btn_pressed() -> void:
	if _current_room != null: return

	_current_room = _lobby.create_mesh_room({ name=$room_name_edit.text })
	if _current_room == null:
		return

	_on_current_room()

func _on_room_list_item_selected(index: int):
	if _current_room != null: return

	_selected_room = _room_list.get_item_metadata(index)
	$room_join_btn.disabled = false

func _on_room_list_empty_clicked(_at_position, _mouse_button_index):
	_room_list.deselect_all()
	_selected_room = null
	$room_join_btn.disabled = true

func _on_room_leave_btn_pressed():
	if _current_room == null: return
	_lobby.close_room()
	_current_room.leave()

func _on_room_join_btn_pressed():
	if _selected_room == null or _current_room != null:
		return

	_current_room = _lobby.join_room(_selected_room.id)
	if _current_room == null:
		return

	_on_current_room()

func _on_current_room() -> void:
	$room_join_btn.disabled = true
	$room_create_btn.disabled = true
	$current_room/room_log.text = "Joining room '%s'...\n" % [_current_room.room_id]

	_current_room.joined.connect(self._on_joined_room)
	_current_room.left.connect(self._on_left_room)
	_current_room.joining_failed.connect(self._on_failed_room)
	_current_room.peer_joined.connect(self._on_peer_joined)
	_current_room.peer_left.connect(self._on_peer_left)
