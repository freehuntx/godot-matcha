extends Node2D

@onready var _room_list: ItemList = $room_list
var _lobby := MatchaLobby.new({ "identifier": "com.matcha.examples.lobby" })
var _selected_room

func _init():
	_lobby.joined_room.connect(self._on_joined_room)
	_lobby.left_room.connect(self._on_left_room)
	_lobby.room_created.connect(self._on_room_created)
	_lobby.room_updated.connect(self._on_room_updated)
	_lobby.room_closed.connect(self._on_room_closed)

#func _ready():
#	lobby.create_room({ "name": "Penis" })

# Private methods

# Callbacks
func _on_joined_room(room: MatchaRoom):
	room.peer_joined.connect(self._on_peer_joined_room)
	room.peer_left.connect(self._on_peer_left_room)
	$room_join_btn.disabled = true
	$room_create_btn.disabled = true
	$current_room/room_log.text = "You joined the room: %s\n" % [room.id]
	$current_room/room_leave_btn.disabled = false

func _on_left_room(_room: MatchaRoom):
	$current_room/room_log.text += "You left the room\n"
	$current_room/room_leave_btn.disabled = true
	$room_join_btn.disabled = false
	$room_create_btn.disabled = false

func _on_room_created(room: Dictionary) -> void:
	var room_name = "Unnamed room (%s)" % [room.id]
	if "name" in room.meta and room.meta.name != "":
		room_name = room.meta.name

	var index := _room_list.add_item(room_name)
	_room_list.set_item_metadata(index, room)

func _on_room_updated(room: Dictionary) -> void:
	for i in _room_list.item_count:
		var list_room = _room_list.get_item_metadata(i)
		if list_room.id != room.id: continue
		_room_list.set_item_metadata(i, room)

		if "name" in room.meta and room.meta.name != "":
			_room_list.set_item_text(i, room.meta.name)

		return

func _on_room_closed(room: Dictionary) -> void:
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
	if _lobby.current_room != null: return
	_lobby.create_room({ "name": $room_name_edit.text })

func _on_room_list_item_selected(index: int):
	if _lobby.current_room != null: return
	_selected_room = _room_list.get_item_metadata(index)
	$room_join_btn.disabled = false

func _on_room_list_empty_clicked(_at_position, _mouse_button_index):
	if _lobby.current_room != null: return
	_room_list.deselect_all()
	_selected_room = null
	$room_join_btn.disabled = true

func _on_room_leave_btn_pressed():
	if _lobby.current_room == null: return
	_lobby.leave_room()

func _on_room_join_btn_pressed():
	if _lobby.current_room != null: return
	if _selected_room == null: return
	_lobby.join_room(_selected_room.id)
