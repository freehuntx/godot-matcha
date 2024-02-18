extends RefCounted
const MQTTMessenger := preload("./mqtt/messenger.gd")

enum Mode { NONE, CLIENT, SERVER, MESH }
enum State { NONE, LEFT, JOINING, JOINED }

signal joining
signal joined
signal left
signal joining_failed
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal event(peer_id: int, name: String, args: Array, broadcast: bool)

## Members
var _mode := Mode.NONE
var _state := State.NONE
var _peer_id: int
var _room_id: String
var _mqtt_messenger := MQTTMessenger.new()
var _multiplayer_peer := WebRTCMultiplayerPeer.new()
var _clients := {}
var _join_time: float

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

	err = _mqtt_messenger.join(_mqtt_messenger.client_id, JSON.stringify({ op="leave" }))
	if err == OK:
		_mode = Mode.SERVER
		_room_id = _mqtt_messenger.client_id
		_peer_id = _multiplayer_peer.get_unique_id()

	return err

func create_client(room_id: String) -> Error:
	if room_id.length() != 20:
		push_error("Invalid room id! Must be 20 characters long.")
		return ERR_INVALID_PARAMETER

	var err := _multiplayer_peer.create_client(_multiplayer_peer.generate_unique_id())
	if err != OK:
		return err

	err = _mqtt_messenger.join(room_id, JSON.stringify({ op="leave" }))
	if err == OK:
		_mode = Mode.CLIENT
		_room_id = room_id
		_peer_id = _multiplayer_peer.get_unique_id()

	return err

func create_mesh(room_id: String) -> Error:
	if room_id.length() != 20 or not room_id.is_valid_hex_number():
		room_id = room_id.sha256_text().substr(0, 20)
		#push_error("Invalid room id! Must be 20 characters long. Forgot to hash it?")
		#return ERR_INVALID_PARAMETER

	var err := _multiplayer_peer.create_mesh(_multiplayer_peer.generate_unique_id())
	if err != OK:
		return err

	err = _mqtt_messenger.join(room_id, JSON.stringify({ op="leave" }))
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
	_state = State.LEFT
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
# Callbacks: Mqtt Messenger
func _on_messenger_connecting() -> void:
	_state = State.JOINING
	joining.emit()

func _on_messenger_connected() -> void:
	_state = State.JOINED
	joined.emit()
	_join_time = Time.get_unix_time_from_system()
	_mqtt_messenger.send_message(JSON.stringify({
		"op": "join",
		"peer_id": _peer_id
	}))

func _on_messenger_closed() -> void:
	_state = State.LEFT
	left.emit()

func _on_messenger_connect_failed() -> void:
	_state = State.NONE
	joining_failed.emit()

func _on_messenger_message(client_id: String, message: String, sender_pub_key: String, private: bool) -> void:
	if _state != State.JOINED:
		return

	var packet := JSON.parse_string(message)
	if typeof(packet) != TYPE_DICTIONARY or not "op" in packet or typeof(packet.op) != TYPE_STRING:
		return

	if packet.op == "join":
		if not "peer_id" in packet or is_nan(packet.peer_id):
			return

		await _on_peer_join_message(client_id, packet.peer_id, sender_pub_key)
	elif packet.op == "offer":
		if not "peer_id" in packet or is_nan(packet.peer_id):
			return
		if not "sdp" in packet or typeof(packet.sdp) != TYPE_STRING:
			return

		await _on_peer_offer_message(client_id, packet.peer_id, sender_pub_key, packet.sdp)
	elif packet.op == "answer":
		if not "sdp" in packet or typeof(packet.sdp) != TYPE_STRING:
			return

		await _on_peer_answer_message(client_id, sender_pub_key, packet.sdp)
	elif packet.op == "leave":
		await _on_peer_leave_message(client_id, sender_pub_key)
	else:
		push_error("Unknown op: ", packet.op)

# Callbacks: OP messages
func _on_peer_leave_message(client_id: String, sender_pub_key: String) -> void:
	if not client_id in _clients:
		return

	var client = _clients[client_id]
	if _multiplayer_peer.has_peer(client.peer_id):
		_multiplayer_peer.remove_peer(client.peer_id)

	_clients.erase(client_id)

func _on_peer_join_message(client_id: String, peer_id: int, peer_pub_key: String) -> void:
	if client_id in _clients:
		return # Should not happen
	if _multiplayer_peer.has_peer(peer_id):
		return # Should not exist

	# In client mode make sure we are talking to the server
	if _mode == Mode.CLIENT:
		if peer_id != 1 or client_id != _room_id:
			return

	var peer := WebRTCPeerConnection.new()
	var client := { "id": client_id, "peer_id": peer_id, "event_channel": null, "local_sdp": "" }

	peer.session_description_created.connect(func(type: String, sdp: String):
		client.local_sdp = sdp
		peer.set_local_description("offer", sdp)
	)
	peer.ice_candidate_created.connect(func(media: String, index: int, name: String):
		client.local_sdp += "a=%s\n" % name
	)

	if peer.initialize({ "iceServers": [{"urls": ["stun:stun.l.google.com:19302"]}] }) != OK:
		return
			
	_multiplayer_peer.add_peer(peer, peer_id)
	client.event_channel = peer.create_data_channel("events", {"id": 555, "negotiated": true})

	if peer.create_offer() != OK:
		_multiplayer_peer.remove_peer(peer_id)
		return

	_clients[client.id] = client

	# Wait for sdp
	while true:
		await Engine.get_main_loop().process_frame
		peer.poll()

		if peer.get_gathering_state() == WebRTCPeerConnection.GATHERING_STATE_COMPLETE:
			break

	# TODO: Fix connecting state. Can be called too early?
	_mqtt_messenger.send_message_to(JSON.stringify({
		"op": "offer",
		"peer_id": _peer_id,
		"sdp": client.local_sdp
	}), peer_pub_key)

func _on_peer_offer_message(client_id: String, peer_id: int, peer_pub_key: String, offer_sdp: String) -> void:
	var client: Dictionary

	## Handle glare (both sent offer at the same time). Smaller id wins
	if client_id in _clients: # This should just be the case, when we got a join and send an offer
		if _peer_id < peer_id: # When our id is smaller, ignore this offer! We won!
			return

		_multiplayer_peer.remove_peer(peer_id) # Remove our offer peer. We lost!
	else:
		client = { "id": client_id, "peer_id": peer_id, "event_channel": null, "local_sdp": "" }
		_clients[client.id] = client

	var peer := WebRTCPeerConnection.new()
	peer.session_description_created.connect(func(type: String, sdp: String):
		client.local_sdp = sdp
		peer.set_local_description("answer", sdp)
	)
	peer.ice_candidate_created.connect(func(media: String, index: int, name: String):
		client.local_sdp += "a=%s\n" % name
	)

	if peer.initialize({ "iceServers": [{"urls": ["stun:stun.l.google.com:19302"]}] }) != OK:
		return

	client.event_channel = peer.create_data_channel("events", {"id": 555, "negotiated": true})
	_multiplayer_peer.add_peer(peer, peer_id)

	if peer.set_remote_description("offer", offer_sdp) != OK:
		_multiplayer_peer.remove_peer(peer_id)
		return

	# Wait for sdp
	while true:
		await Engine.get_main_loop().process_frame
		peer.poll()

		if peer.get_gathering_state() == WebRTCPeerConnection.GATHERING_STATE_COMPLETE:
			break

	_mqtt_messenger.send_message_to(JSON.stringify({
		"op": "answer",
		"sdp": client.local_sdp
	}), peer_pub_key)

func _on_peer_answer_message(client_id: String, peer_pub_key: String, answer_sdp: String) -> void:
	if not client_id in _clients:
		return

	var client: Dictionary = _clients[client_id]
	if not _multiplayer_peer.has_peer(client.peer_id):
		return

	# TODO: Glare seems to still be a problem sometimes :/
	var peer: WebRTCPeerConnection = _multiplayer_peer.get_peer(client.peer_id).connection
	peer.set_remote_description("answer", answer_sdp)

# Callbacks: Multiplayer peer
func _on_peer_connected(peer_id: int) -> void:
	peer_joined.emit(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	peer_left.emit(peer_id)
