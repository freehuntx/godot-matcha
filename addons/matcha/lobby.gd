extends RefCounted
const MQTTMessenger := preload("./mqtt/messenger.gd")
const Room := preload("./room.gd")

enum RoomType { SERVER, MESH }

## Signals
signal ready
signal room_created(id: String, type: RoomType, meta: Dictionary)
signal room_updated(id: String, type, RoomType, meta: Dictionary)
signal room_closed(id: String)

## Members
var _mqtt_messenger: MQTTMessenger
var _lobby_room_id: String
var _rooms := {}

var room_list: Array:
	get: return _rooms.values()
var own_room: Variant:
	get:
		if _mqtt_messenger == null or not _mqtt_messenger.client_id in _rooms:
			return null
		return _rooms[_mqtt_messenger.client_id]

## Public methods
func join(identifier: String) -> Error:
	if _mqtt_messenger != null:
		return ERR_ALREADY_EXISTS

	_lobby_room_id = identifier.sha256_text().substr(0, 20)

	_mqtt_messenger = MQTTMessenger.new()
	_mqtt_messenger.connecting.connect(self._on_messenger_connecting)
	_mqtt_messenger.connected.connect(self._on_messenger_connected)
	_mqtt_messenger.closed.connect(self._on_messenger_closed)
	_mqtt_messenger.connect_failed.connect(self._on_messenger_connect_failed)
	_mqtt_messenger.message.connect(self._on_messenger_message)

	var err := _mqtt_messenger.join(_lobby_room_id, JSON.stringify({ op="close" }))
	if err != OK:
		_mqtt_messenger = null

	return err

func join_room(id: String) -> Room:
	if not id in _rooms:
		push_error("Room '%s' does not exist" % id)
		return null

	var room := Room.new()

	if _rooms[id].type == RoomType.SERVER:
		room.create_client(id)
	else:
		room.create_mesh(id)

	return room

func create_room(type: RoomType, meta:={}) -> Room:
	if _mqtt_messenger.client_id in _rooms:
		push_error("Room already created! Close it first.")
		return null

	var room := Room.new({ key=_mqtt_messenger.key })
	var err: Error = room.create_server() if type == RoomType.SERVER else room.create_mesh(_mqtt_messenger.client_id)

	if err != OK:
		return null

	err = _mqtt_messenger.send_message(JSON.stringify({
		op="update",
		type=type,
		meta=meta
	}), true)

	if err != OK:
		return null

	var list_room := { id=room.room_id, type=type, meta=meta }
	_rooms[room.room_id] = list_room
	room_created.emit(list_room.id, list_room.type, list_room.meta)
	Engine.get_main_loop().create_timer(5).timeout.connect(func():
		update_room({ name="Penis2" })
	)

	return room

func create_server_room(meta:={}) -> Room:
	return create_room(RoomType.SERVER, meta)

func create_mesh_room(meta:={}) -> Room:
	return create_room(RoomType.MESH, meta)

func update_room(meta: Dictionary) -> Error:
	if not _mqtt_messenger.client_id in _rooms:
		return ERR_DOES_NOT_EXIST

	var list_room: Dictionary = _rooms[_mqtt_messenger.client_id]

	var was_updated := false
	if meta.size() != list_room.meta.size():
		was_updated = true
	else:
		for key in meta.keys():
			if key in list_room.meta and list_room.meta[key] == meta[key]:
				continue
			was_updated = true
			break

	if not was_updated:
		return ERR_UNCONFIGURED

	list_room.meta = meta
	room_updated.emit(list_room.id, list_room.type, list_room.meta)

	return _mqtt_messenger.send_message(JSON.stringify({
		op="update",
		type=list_room.type,
		meta=list_room.meta
	}), true)

func close_room() -> Error:
	var created_room = own_room
	if created_room == null:
		return ERR_DOES_NOT_EXIST

	_rooms.erase(created_room.id)
	room_closed.emit(created_room.id)

	return _mqtt_messenger.send_message(JSON.stringify({ op="close" }))

## Private methods

## Callbacks
func _on_messenger_connecting() -> void:
	pass

func _on_messenger_connected() -> void:
	ready.emit()

	_mqtt_messenger.send_message(JSON.stringify({
		op="enter"
	}))

func _on_messenger_closed() -> void:
	pass

func _on_messenger_connect_failed() -> void:
	pass

func _on_messenger_message(client_id: String, message: String, sender_pub_key: String, private: bool) -> void:
	var packet := JSON.parse_string(message)
	if typeof(packet) != TYPE_DICTIONARY or not "op" in packet or typeof(packet.op) != TYPE_STRING:
		return

	if packet.op == "enter":
		if own_room == null:
			return
		_mqtt_messenger.send_message_to(JSON.stringify({
			op="update",
			type=own_room.type,
			meta=own_room.meta
		}), sender_pub_key)
	elif packet.op == "update":
		if not "meta" in packet or typeof(packet.meta) != TYPE_DICTIONARY:
			return
		if not "type" in packet or is_nan(packet.type):
			return
		var is_new_room: bool = not client_id in _rooms
		_rooms[client_id] = { id=client_id, type=packet.type, meta=packet.meta }
		if is_new_room:
			room_created.emit(client_id, packet.type, packet.meta)
		else:
			room_updated.emit(client_id, packet.type, packet.meta)
	elif packet.op == "close":
		if not client_id in _rooms:
			return
		_rooms.erase(client_id)
		room_closed.emit(client_id)
