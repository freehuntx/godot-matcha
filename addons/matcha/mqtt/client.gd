extends RefCounted

## Constants
enum State { NEW, CLOSED, WS_CONNECTING, CONNECTING, CONNECTED }
enum ConnectFlags {
	CLEAN_SESSION		= 0x02,
	LAST_WILL			= 0x04,
	LAST_WILL_QOS_1		= 0x08,
	LAST_WILL_QOS_2		= 0x10,
	LAST_WILL_RETAIN	= 0x20,
	PASS				= 0x40,
	USER				= 0x80
}
enum OpCodes {
	CONNECT_REQ		= 0x10,
	CONNECT_RES		= 0x20,
	PUBLISH_REQ		= 0x30,
	PUBLISH_RES		= 0x40,
	SUBSCRIBE_REQ	= 0x82,
	SUBSCRIBE_RES	= 0x90,
	UNSUBSCRIBE_REQ	= 0xa2,
	UNSUBSCRIBE_RES	= 0xb0,
	PING_REQ		= 0xc0,
	PING_RES		= 0xd0,
	DISCONNECT		= 0xe0
}

## Signals
signal connecting
signal connected
signal disconnected
signal closed
signal subscribed
signal message(topic: String, message: PackedByteArray)

## Members
var _state := State.NEW
var _socket: WebSocketPeer
var _broker_url: String
var _client_id: String
var _username: String
var _password: String
var _keep_alive := 120
var _recv_buffer: PackedByteArray
var _last_will = null
var _clean_session := true
var _packet_identifier := 0

var is_connected: bool:
	get: return _state == State.CONNECTED

## Constructor
func _init(options:={}):
	randomize()

	_client_id = options.client_id if "client_id" in options else "rr%d" % randi()
	_broker_url = options.broker_url if "broker_url" in options else ""
	_clean_session = options.clean_session if "clean_session" in options else true
	_username = options.username if "username" in options else ""
	_password = options.password if "password" in options else ""

	if not "autopoll" in options or options.autopoll == true:
		Engine.get_main_loop().process_frame.connect(self.poll)
	if "timeout" in options:
		Engine.get_main_loop().create_timer(options.timeout).timeout.connect(self._on_timeout)

## Public methods
func connect_to_server(broker_url:=_broker_url) -> Error:
	if _socket != null:
		push_error("mqttclient already in use")
		return ERR_ALREADY_IN_USE

	_recv_buffer = PackedByteArray()
	_socket = WebSocketPeer.new()
	_socket.supported_protocols = PackedStringArray(["mqttv3.1"])

	# When not in web we should use an useragent. Some servers dont accept requests without an user-agent
	if OS.get_name() != "Web":
		_socket.handshake_headers = PackedStringArray([
			"user-agent: Godot"
		])

	var err := _socket.connect_to_url(broker_url)
	if err != OK:
		_socket = null
		return err

	_packet_identifier = 0 # Reset to 0 is smart?
	_broker_url = broker_url
	_state = State.WS_CONNECTING
	connecting.emit()

	return OK

func close() -> Error:
	if _socket == null:
		return Error.ERR_DOES_NOT_EXIST

	_socket.poll()

	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send(PackedByteArray([ OpCodes.DISCONNECT, 0x00 ]))

	var old_state = _state
	_socket.close()
	_socket = null
	_state = State.CLOSED

	if old_state == State.CONNECTED:
		disconnected.emit()

	closed.emit()

	return Error.OK

func poll() -> void:
	if _socket == null or _state == State.NEW or _state == State.CLOSED:
		return

	_socket.poll()

	var ready_state = _socket.get_ready_state()
	if ready_state != WebSocketPeer.STATE_OPEN:
		if ready_state != WebSocketPeer.STATE_CONNECTING:
			close() # Not open? Not connecting? Then its closed!
		return

	if _state == State.WS_CONNECTING:
		_state = State.CONNECTING
		_socket.send(_create_connect_packet())

	# Append buffer
	while _socket.get_available_packet_count():
		_recv_buffer.append_array(_socket.get_packet())

	var packets := _read_packets()
	for packet in packets:
		_handle_packet(packet.op, packet.buffer)

func set_last_will(topic: String, msg="", retain:=false, qos:=0) -> Error:
	if _state == State.CONNECTED:
		push_warning("set_last_will should be used before connecting to the broker!")
	if qos < 0 or qos > 2:
		push_error("Invalid qos: ", qos)
		return ERR_INVALID_PARAMETER

	_last_will = {
		topic=topic.to_utf8_buffer(),
		msg=msg.to_utf8_buffer() if typeof(msg) == TYPE_STRING else msg,
		qos=qos,
		retain=retain
	}

	return OK

func subscribe(topic: String, qos:=0, wait_for_connect:=false) -> Error:
	if _state != State.CONNECTED:
		if wait_for_connect:
			connected.connect(self.subscribe.bind(topic, qos, wait_for_connect), CONNECT_ONE_SHOT)
			return OK

		push_error("subscribe failed: Not connected")
		return ERR_CONNECTION_ERROR

	_packet_identifier += 1

	var topic_buffer := topic.to_utf8_buffer()
	var payload := PackedByteArray([
		_packet_identifier >> 8,
		_packet_identifier & 0xFF,
		topic_buffer.size() >> 8,
		topic_buffer.size() & 0xFF
	])
	payload.append_array(topic_buffer)
	payload.append(qos)

	var msg = PackedByteArray([
		OpCodes.SUBSCRIBE_REQ, # Op
		payload.size()
	])
	msg.append_array(payload)
	return _socket.send(msg)

func unsubscribe(topic: String) -> Error:
	_packet_identifier += 1

	var topic_buffer := topic.to_utf8_buffer()
	var payload := PackedByteArray([
		_packet_identifier >> 8,
		_packet_identifier & 0xFF,
		topic_buffer.size() >> 8,
		topic_buffer.size() & 0xFF
	])
	payload.append_array(topic_buffer)

	var msg = PackedByteArray([
		OpCodes.UNSUBSCRIBE_REQ, # Op
		payload.size()
	])
	msg.append_array(payload)
	return _socket.send(msg)

func publish(topic: String, msg, retain:=false, qos:=0, wait_for_connect:=false) -> Error:
	if _state != State.CONNECTED:
		if wait_for_connect:
			connected.connect(self.publish.bind(topic, msg, retain, qos, wait_for_connect), CONNECT_ONE_SHOT)
			return OK

		push_error("publish failed: Not connected")
		return ERR_CONNECTION_ERROR

	var msg_buffer: PackedByteArray = msg.to_utf8_buffer() if typeof(msg) == TYPE_STRING else msg
	var topic_buffer := topic.to_utf8_buffer()
	var packet := PackedByteArray()
	packet.append(OpCodes.PUBLISH_REQ | (2 if qos else 0) | (1 if retain else 0))
	packet.append(0x00)

	var payload_size := 2 + topic_buffer.size() + msg_buffer.size()
	if qos > 0:
		payload_size += 2

	if payload_size < 0 or payload_size >= 2097152:
		push_error("Payload size to small or to big")
		return ERR_INVALID_DATA

	# Add dynamic payload size
	var offset := 1
	while payload_size > 0x7F:
		packet[offset] = (payload_size & 0x7F) | 0x80
		payload_size >>= 7
		offset += 1
		if offset + 1 > packet.size():
			packet.append(0x00)

	packet[offset] = payload_size

	packet.append(topic_buffer.size() >> 8)
	packet.append(topic_buffer.size() & 0xFF)
	packet.append_array(topic_buffer)

	if qos > 0:
		_packet_identifier += 1
		packet.append(_packet_identifier >> 8)
		packet.append(_packet_identifier & 0xFF)

	packet.append_array(msg_buffer)
	return _socket.send(packet)

func ping() -> Error:
	return _socket.send(PackedByteArray([OpCodes.PING_REQ, 0x00]))

## Private methods
func _read_packets() -> Array:
	var packets := []

	while true:
		var buffer_size = _recv_buffer.size()
		if buffer_size < 2:
			break

		var op := _recv_buffer[0]
		var buffer_offset := 1
		var payload_size := _recv_buffer[buffer_offset] & 0x7F # Just read 7 bits always

		# Read dynamic int (payload size)
		while (_recv_buffer[buffer_offset] & 0x80): # While highest bit is 1, we have more bytes to come
			buffer_offset += 1

			if buffer_offset >= buffer_size:
				break # We dont have enough bytes in buffer to parse the dynamic int (payload size)

			payload_size += (_recv_buffer[buffer_offset] & 0x7F) << ((buffer_offset-1)*7) # Add

		buffer_offset += 1

		if buffer_size < buffer_offset + payload_size:
			break # We dont have enough bytes in buffer to parse the whole packet

		packets.append({
			op=op,
			buffer=_recv_buffer.slice(buffer_offset, buffer_offset + payload_size)
		})

		_recv_buffer = _recv_buffer.slice(buffer_offset + payload_size) # Remove the packet from the recv buffer

	return packets

func _handle_packet(op: int, buffer: PackedByteArray) -> Error:
	if op == OpCodes.CONNECT_RES:
		if buffer.size() != 2:
			push_error("CONNECT_RES packet does not match argument count")
			return ERR_INVALID_DATA

		var ret_code := buffer[1]
		if ret_code == 0:
			_state = State.CONNECTED
			connected.emit()
			return OK
		else:
			push_error("Connecting failed! ret_code=%s" % [ret_code])
			close()
			return ERR_CONNECTION_ERROR

	if op == OpCodes.PING_RES:
		if buffer.size() != 0:
			push_error("PING_RES packet does not match argument count")
			return ERR_INVALID_DATA
		return OK

	if op == OpCodes.SUBSCRIBE_RES:
		if buffer.size() != 3:
			push_error("SUBSCRIBE_RES packet does not match argument count")
			return ERR_INVALID_DATA
		if buffer[2] == 0x80: # qos 0, 1 or 2
			push_error("SUBSCRIBE_RES unknown error")
			return ERR_QUERY_FAILED
		subscribed.emit()
		return OK

	if op == OpCodes.UNSUBSCRIBE_RES:
		if buffer.size() != 2:
			push_error("UNSUBSCRIBE_RES packet does not match argument count")
			return ERR_INVALID_DATA
		return OK

#	if op & 0xF0 == OpCodes.PUBLISH_REQ:
	if op == OpCodes.PUBLISH_REQ:
		var stream := StreamPeerBuffer.new()
		stream.data_array = buffer

		var topic_len := (stream.get_u8() << 8) + stream.get_u8()
		var topic := stream.get_utf8_string(topic_len)
		var packet_identifier := 0
		if op & 6:
			packet_identifier = (stream.get_u8() << 8) + stream.get_u8()
		var msg_buffer := stream.get_data(stream.get_size() - stream.get_position())
		
		message.emit(topic, msg_buffer[1])

		if op & 6 == 2:
			return _socket.send(PackedByteArray([ OpCodes.PUBLISH_RES, 0x02, packet_identifier >> 8, packet_identifier & 0xFF ]))
		#elif op & 6 == 4:
		#	print("?")

		return OK

	push_warning("Unhandled mqtt opcode: %s" % op)
	return ERR_UNCONFIGURED

func _create_connect_packet() -> PackedByteArray:
	var flags = 0x00 # Connect Flags
	
	if _clean_session:
		flags |= ConnectFlags.CLEAN_SESSION

	if _last_will != null:
		flags |= ConnectFlags.LAST_WILL

		if _last_will.retain:
			flags |= ConnectFlags.LAST_WILL_RETAIN

		if _last_will.qos == 1:
			flags |= ConnectFlags.LAST_WILL_QOS_1
		elif _last_will.qos == 2:
			flags |= ConnectFlags.LAST_WILL_QOS_2

	if _username != "":
		flags |= ConnectFlags.USER

		if _password != "":
			flags |= ConnectFlags.PASS

	if _keep_alive < 0 or _keep_alive > 0xFFFF:
		push_error("Invalid keep_alive")
		_keep_alive = 120

	## PAYLOAD
	var connect_payload: PackedByteArray
	connect_payload.append_array([0x00, 0x04]) # MQTT String length
	connect_payload.append_array("MQTT".to_utf8_buffer())
	connect_payload.append(0x04) # Protocol Level = 4 -> 3.1.X  / 5 -> 5
	connect_payload.append(flags) # Connect flags
	connect_payload.append_array([_keep_alive >> 8, _keep_alive & 0xFF]) # Keep alive

	# ClientId
	connect_payload.append(_client_id.length() >> 8)
	connect_payload.append(_client_id.length() & 0xFF)
	connect_payload.append_array(_client_id.to_utf8_buffer())

	if _last_will != null:
		connect_payload.append(_last_will.topic.size() >> 8)
		connect_payload.append(_last_will.topic.size() & 0xFF)
		connect_payload.append_array(_last_will.topic)
		connect_payload.append(_last_will.msg.size() >> 8)
		connect_payload.append(_last_will.msg.size() & 0xFF)
		connect_payload.append_array(_last_will.msg)

	if _username != "":
		connect_payload.append(_username.length() >> 8)
		connect_payload.append(_username.length() & 0xFF)
		connect_payload.append_array(_username.to_utf8_buffer())

		if _password != "":
			connect_payload.append(_password.length() >> 8)
			connect_payload.append(_password.length() & 0xFF)
			connect_payload.append_array(_password.to_utf8_buffer())

	var connect_msg = PackedByteArray([
		OpCodes.CONNECT_REQ, # CONNECT Packet fixed header 0x10
		connect_payload.size(), # Payload size
	])
	connect_msg.append_array(connect_payload)

	return connect_msg

## Callbacks
func _on_timeout():
	if _state != State.CONNECTED:
		close()
