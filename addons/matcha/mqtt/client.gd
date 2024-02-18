extends RefCounted
const MQTTPacket := preload("./packet.gd")

## Constants
enum State { NEW, CLOSED, WS_CONNECTING, CONNECTING, CONNECTED }
enum ControlFlags {
	RETAIN = 0x01,
	QOS = 0x02,
	DUP = 0x04
}
enum ConnectFlags {
	CLEAN_SESSION		= 0x02,
	LAST_WILL			= 0x04,
	LAST_WILL_QOS_1		= 0x08,
	LAST_WILL_QOS_2		= 0x10,
	LAST_WILL_RETAIN	= 0x20,
	PASS				= 0x40,
	USER				= 0x80
}
enum PacketType {
	CONNECT	= 1,
	CONNACK,
	PUBLISH,
	PUBACK,
	PUBREC,
	PUBREL,
	PUBCOMP,
	SUBSCRIBE,
	SUBACK,
	UNSUBSCRIBE,
	UNSUBACK,
	PING,
	PONG,
	DISCONNECT
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
var _keep_alive := 60
var _recv_buffer: PackedByteArray
var _last_will = null
var _clean_session := true
var _forceful_close := false
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
	_socket.inbound_buffer_size = 1024 * 1024
	_socket.supported_protocols = PackedStringArray(["mqtt"])

	# When not in web we should use an useragent. Some servers dont accept requests without an user-agent
	if OS.get_name() != "Web":
		_socket.handshake_headers = PackedStringArray([
			"user-agent: Godot"
		])

	var err := _socket.connect_to_url(broker_url)
	if err != OK:
		_socket = null
		return err

	_packet_identifier = 0
	_broker_url = broker_url
	_state = State.WS_CONNECTING
	connecting.emit()

	return OK

func close() -> Error:
	if _socket == null:
		return Error.ERR_DOES_NOT_EXIST

	_socket.poll()

	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN and not _forceful_close:
		_socket.send(MQTTPacket.Builder.new(PacketType.DISCONNECT).build())

	var old_state = _state
	_socket.close()
	_socket = null
	_state = State.CLOSED

	if old_state == State.CONNECTED:
		disconnected.emit()

	closed.emit()

	return Error.OK

func set_forceful_close(value: bool) -> void:
	_forceful_close = value

func poll() -> void:
	if _socket == null or _state == State.NEW or _state == State.CLOSED:
		return

	_socket.poll()

	var ready_state := _socket.get_ready_state()
	if ready_state != WebSocketPeer.STATE_OPEN:
		if ready_state != WebSocketPeer.STATE_CONNECTING:
			close() # Not open? Not connecting? Then its closed!
		return

	if _state == State.WS_CONNECTING:
		_state = State.CONNECTING
		_send_connect_packet()

	# Append buffer
	var got_bytes := false
	while _socket.get_available_packet_count():
		got_bytes = true
		_recv_buffer.append_array(_socket.get_packet())

	if got_bytes:
		while true:
			var packet = MQTTPacket.Parser.read(_recv_buffer)
			if packet == null:
				break

			_recv_buffer = _recv_buffer.slice(packet.packet_size) # Remove the packet from the recv buffer
			_handle_packet(packet.type, packet.flags, packet.payload)

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

	var packet := MQTTPacket.Builder.new(PacketType.SUBSCRIBE, ControlFlags.QOS)
	packet.push("u16", _packet_identifier)
	packet.push("str", topic)
	packet.push("u8", qos)
	return _socket.send(packet.build())

func unsubscribe(topic: String) -> Error:
	_packet_identifier += 1

	var packet := MQTTPacket.Builder.new(PacketType.UNSUBSCRIBE, ControlFlags.QOS)
	packet.push("u16", _packet_identifier)
	packet.push("str", topic)
	return _socket.send(packet.build())

func publish(topic: String, msg, retain:=false, qos:=0, wait_for_connect:=false) -> Error:
	if _state != State.CONNECTED:
		if wait_for_connect:
			connected.connect(self.publish.bind(topic, msg, retain, qos, wait_for_connect), CONNECT_ONE_SHOT)
			return OK

		push_error("publish failed: Not connected")
		return ERR_CONNECTION_ERROR

	var control_flags := (ControlFlags.QOS if qos else 0) | (ControlFlags.RETAIN if retain else 0)
	var packet := MQTTPacket.Builder.new(PacketType.PUBLISH, control_flags)
	packet.push("str", topic)

	if qos > 0:
		_packet_identifier += 1
		packet.push("u16", _packet_identifier)
		packet.append(_packet_identifier >> 8)

	if typeof(msg) == TYPE_STRING:
		packet.push("data", msg.to_utf8_buffer())
	else:
		packet.push("data", msg)

	return _socket.send(packet.build())

func ping() -> Error:
	return _socket.send(MQTTPacket.Builder.new(PacketType.PING).build())

## Private methods
func _handle_packet(packet_type: int, flags: int, payload_buffer: PackedByteArray) -> Error:
	if packet_type == PacketType.CONNACK:
		if payload_buffer.size() != 2:
			push_error("CONNACK packet does not match argument count")
			return ERR_INVALID_DATA

		var ret_code := payload_buffer[1]
		if ret_code == 0:
			_state = State.CONNECTED
			connected.emit()
			return OK
		else:
			push_error("Connecting failed! ret_code=%s" % [ret_code])
			close()
			return ERR_CONNECTION_ERROR

	if packet_type == PacketType.PONG:
		if payload_buffer.size() != 0:
			push_error("PONG packet does not match argument count")
			return ERR_INVALID_DATA
		return OK

	if packet_type == PacketType.SUBACK:
		if payload_buffer.size() != 3:
			push_error("SUBACK packet does not match argument count")
			return ERR_INVALID_DATA
		if payload_buffer[2] == 0x80: # qos 0, 1 or 2
			push_error("SUBACK unknown error")
			return ERR_QUERY_FAILED
		subscribed.emit()
		return OK

	if packet_type == PacketType.UNSUBACK:
		if payload_buffer.size() != 2:
			push_error("UNSUBACK packet does not match argument count")
			return ERR_INVALID_DATA
		return OK

#	if op & 0xF0 == OpCodes.PUBLISH:
	if packet_type == PacketType.PUBLISH:
		var stream := StreamPeerBuffer.new()
		stream.data_array = payload_buffer

		var topic_len := (stream.get_u8() << 8) + stream.get_u8()
		var topic := stream.get_utf8_string(topic_len)
		var packet_identifier := 0
		if flags & 6:
			packet_identifier = (stream.get_u8() << 8) + stream.get_u8()
		var msg_buffer := stream.get_data(stream.get_size() - stream.get_position())
		
		message.emit(topic, msg_buffer[1])

		if flags == 2:
			return _socket.send(PackedByteArray([ PacketType.PUBACK << 4, 0x02, packet_identifier >> 8, packet_identifier & 0xFF ]))
		#elif op & 6 == 4:
		#	print("?")

		return OK

	push_warning("Unhandled mqtt packet type: %s" % packet_type)
	return ERR_UNCONFIGURED

func _send_connect_packet() -> Error:
	var connect_flags = 0x00
	
	if _clean_session:
		connect_flags |= ConnectFlags.CLEAN_SESSION

	if _last_will != null:
		connect_flags |= ConnectFlags.LAST_WILL

		if _last_will.retain:
			connect_flags |= ConnectFlags.LAST_WILL_RETAIN

		if _last_will.qos == 1:
			connect_flags |= ConnectFlags.LAST_WILL_QOS_1
		elif _last_will.qos == 2:
			connect_flags |= ConnectFlags.LAST_WILL_QOS_2

	if _username != "":
		connect_flags |= ConnectFlags.USER

	if _password != "":
		connect_flags |= ConnectFlags.PASS

	if _keep_alive < 0 or _keep_alive > 0xFFFF:
		push_error("Invalid keep_alive")
		_keep_alive = 60

	var packet := MQTTPacket.Builder.new(PacketType.CONNECT)
	packet.push("str", "MQTT")
	packet.push("u8", 4) # Protocol Level = 4 -> 3.1.X  / 5 -> 5
	packet.push("u8", connect_flags)
	packet.push("u16", _keep_alive)
	packet.push("str", _client_id)

	if _last_will != null:
		packet.push("u16", _last_will.topic.size())
		packet.push("data", _last_will.topic)
		packet.push("u16", _last_will.msg.size())
		packet.push("data", _last_will.msg)

	if _username != "":
		packet.push("str", _username)

	if _password != "":
		packet.push("str", _password)

	return _socket.send(packet.build())

## Callbacks
func _on_timeout():
	if _state != State.CONNECTED:
		close()
