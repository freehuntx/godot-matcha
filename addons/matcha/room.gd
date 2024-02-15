extends RefCounted
const MQTTMessenger := preload("./mqtt/messenger.gd")

enum Mode { NONE, CLIENT, SERVER, MESH }

signal joining
signal joined
signal left
signal joining_failed
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal event(peer_id: int, name: String, args: Array, broadcast: bool)

## Members
var _mode := Mode.NONE
var _peer_id: int
var _room_id: String
var _mqtt_messenger := MQTTMessenger.new()
var _multiplayer_peer := WebRTCMultiplayerPeer.new()
var _clients := {}

var peer_id: int:
	get: return _peer_id
var room_id: String:
	get: return _room_id
var multiplayer_peer: WebRTCMultiplayerPeer:
	get: return _multiplayer_peer

## Constructor
func _init(options:={}):
	_mqtt_messenger.connecting.connect(self._on_messenger_connecting)
	_mqtt_messenger.connected.connect(self._on_messenger_connected)
	_mqtt_messenger.closed.connect(self._on_messenger_closed)
	_mqtt_messenger.connect_failed.connect(self._on_messenger_connect_failed)
	_mqtt_messenger.message.connect(self._on_messenger_message)

	_multiplayer_peer.peer_connected.connect(self._on_peer_connected)
	_multiplayer_peer.peer_disconnected.connect(self._on_peer_disconnected)

	if not "autopoll" in options or options.autopoll == true:
		Engine.get_main_loop().process_frame.connect(self.poll)

## Public methods
func create_server() -> Error:
	var err := _multiplayer_peer.create_server()
	if err != OK:
		return err

	err = _mqtt_messenger.join(_mqtt_messenger.peer_id)
	if err == OK:
		_mode = Mode.SERVER
		_room_id = _mqtt_messenger.client_id
		_peer_id = _multiplayer_peer.get_unique_id()

	return err

func create_client(room_id: String) -> Error:
	var err := _multiplayer_peer.create_client(_multiplayer_peer.generate_unique_id())
	if err != OK:
		return err

	err = _mqtt_messenger.join(room_id)
	if err == OK:
		_mode = Mode.CLIENT
		_room_id = room_id
		_peer_id = _multiplayer_peer.get_unique_id()

	return err

func create_mesh(room_id: String) -> Error:
	var err := _multiplayer_peer.create_mesh(_multiplayer_peer.generate_unique_id())
	if err != OK:
		return err

	err = _mqtt_messenger.join(room_id)
	if err  == OK:
		_mode = Mode.MESH
		_room_id = room_id
		_peer_id = _multiplayer_peer.get_unique_id()

	return err

func close() -> Error:
	if _mqtt_messenger == null:
		push_error("close failed: Not open")
		return ERR_DOES_NOT_EXIST
	_mqtt_messenger = null
	return OK

func leave() -> Error:
	if _multiplayer_peer == null:
		push_error("leave failed: Not connected")
		return ERR_DOES_NOT_EXIST
	_mqtt_messenger = null
	_multiplayer_peer = null
	_clients = {}
	left.emit()
	return OK

func send_event(event_name: String, event_args:=[], target_peer_ids := []) -> Error:
	var broadcast = target_peer_ids.size() == 0
	var pack_array = [event_name, broadcast]
	
	if event_args.size() > 0:
		pack_array.append(event_args)

	for client in _clients.values():
		if broadcast or target_peer_ids.has(client.peer_id):
			client.event_channel.put_packet(var_to_bytes(pack_array)) # TODO: Use seriously?

	return ERR_METHOD_NOT_FOUND

func poll() -> void:
	_multiplayer_peer.poll()

	for client in _clients.values():
		client.event_channel.poll()

		while client.event_channel.get_available_packet_count():
			var buffer: PackedByteArray = client.event_channel.get_packet()
			var args: Array = bytes_to_var(buffer) # TODO: Use seriously?
			if typeof(args) != TYPE_ARRAY or args.size() < 2 or typeof(args[0]) != TYPE_STRING or typeof(args[1]) != TYPE_BOOL:
				continue
			if args.size() == 3 and typeof(args[2]) != TYPE_ARRAY:
				continue
			var event_args := []
			if args.size() == 3:
				event_args = args[2]
			event.emit(client.peer_id, args[0], event_args, args[1])

## Callbacks
func _on_messenger_connecting() -> void:
	joining.emit()

func _on_messenger_connected() -> void:
	joined.emit()
	_mqtt_messenger.send_message(JSON.stringify({
		"op": "join",
		"peer_id": _peer_id
	}))

func _on_messenger_closed() -> void:
	left.emit()

func _on_messenger_connect_failed() -> void:
	joining_failed.emit()

func _on_messenger_message(client_id: String, message: String, sender_pub_key: String, private: bool) -> void:
	var packet := JSON.parse_string(message)
	if typeof(packet) != TYPE_DICTIONARY or not "op" in packet or typeof(packet.op) != TYPE_STRING:
		return

	if packet.op == "join":
		if client_id in _clients:
			return
		if not "peer_id" in packet or is_nan(packet.peer_id):
			return
		if _multiplayer_peer.has_peer(packet.peer_id):
			return
		if _mode == Mode.CLIENT:
			if packet.peer_id != 1 or client_id != _room_id:
				return

		var client := { "id": client_id, "peer_id": packet.peer_id, "local_sdp": "" }
		var webrtc_peer := WebRTCPeerConnection.new()
		webrtc_peer.ice_candidate_created.connect(func(media: String, index: int, name: String):
			client.local_sdp += "a=%s\n" % name
		)
		webrtc_peer.session_description_created.connect(func(type: String, sdp: String):
			client.local_sdp = sdp
			webrtc_peer.set_local_description("offer", sdp)
		)

		if webrtc_peer.initialize({ "iceServers": [{"urls": ["stun:stun.l.google.com:19302"]}] }) != OK:
			return
			
		_multiplayer_peer.add_peer(webrtc_peer, packet.peer_id)
		client.event_channel = webrtc_peer.create_data_channel("events", {"id": 555, "negotiated": true})

		if webrtc_peer.create_offer() != OK:
			_multiplayer_peer.remove_peer(packet.peer_id)
			return

		_clients[client.id] = client

		# Wait for sdp
		while true:
			await Engine.get_main_loop().process_frame
			webrtc_peer.poll()

			if webrtc_peer.get_gathering_state() == WebRTCPeerConnection.GATHERING_STATE_COMPLETE:
				break

		# TODO: Fix connecting state. Can be called too early?
		_mqtt_messenger.send_message_to(JSON.stringify({
			"op": "offer",
			"peer_id": _peer_id,
			"sdp": client.local_sdp
		}), sender_pub_key)
		return

	if packet.op == "offer":
		if not "peer_id" in packet or is_nan(packet.peer_id):
			return
		if not "sdp" in packet or typeof(packet.sdp) != TYPE_STRING:
			return

		var client: Dictionary

		# Handle glare (both sent offer at the same time). Smaller id wins
		if client_id in _clients:
			client = _clients[client_id]

			if _peer_id > client.peer_id:
				_multiplayer_peer.remove_peer(client.peer_id)
			else:
				return
		else:
			client = { "id": client_id, "peer_id": packet.peer_id, "local_sdp": "" }
			_clients[client.id] = client

		var webrtc_peer := WebRTCPeerConnection.new()
		webrtc_peer.ice_candidate_created.connect(func(media: String, index: int, name: String):
			client.local_sdp += "a=%s\n" % name
		)
		webrtc_peer.session_description_created.connect(func(type: String, sdp: String):
			client.local_sdp = sdp
			webrtc_peer.set_local_description("answer", sdp)
		)

		if webrtc_peer.initialize({ "iceServers": [{"urls": ["stun:stun.l.google.com:19302"]}] }) != OK:
			_clients.erase(client.id)
			return

		client.event_channel = webrtc_peer.create_data_channel("events", {"id": 555, "negotiated": true})
		_multiplayer_peer.add_peer(webrtc_peer, packet.peer_id)

		if webrtc_peer.set_remote_description("offer", packet.sdp) != OK:
			_multiplayer_peer.remove_peer(packet.peer_id)
			return

		# Wait for sdp
		while true:
			await Engine.get_main_loop().process_frame
			webrtc_peer.poll()

			if webrtc_peer.get_gathering_state() == WebRTCPeerConnection.GATHERING_STATE_COMPLETE:
				break

		_mqtt_messenger.send_message_to(JSON.stringify({
			"op": "answer",
			"sdp": client.local_sdp
		}), sender_pub_key)
		return

	if packet.op == "answer":
		if not client_id in _clients:
			return
		if not "sdp" in packet or typeof(packet.sdp) != TYPE_STRING:
			return

		var client: Dictionary = _clients[client_id]
		if not _multiplayer_peer.has_peer(client.peer_id):
			return

		_multiplayer_peer.get_peer(client.peer_id).connection.set_remote_description("answer", packet.sdp)

func _on_peer_connected(peer_id: int) -> void:
	peer_joined.emit(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	peer_left.emit(peer_id)
