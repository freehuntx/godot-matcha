# TODO: DOCUMENT, DOCUMENT, DOCUMENT!

extends RefCounted

# Signals
signal disconnected
signal reconnecting
signal connecting
signal connected
signal message(data)

# Constants
enum Mode { BYTES, TEXT, JSON }
enum State { DISCONNECTED, CONNECTING, CONNECTED, RECONNECTING }

# Members
var _user_agent: String
var _state := State.DISCONNECTED
var _url: String
var _socket: WebSocketPeer
var _reconnect_try_counter := 0
var _options: Dictionary

# Getters
var is_connected:
	get: return _state == State.CONNECTED

# Constructor
func _init(url: String, options:={}) -> void:
	if not "mode" in options: options.mode = Mode.BYTES
	if not "reconnect_tries" in options: options.reconnect_tries = 0
	_url = url
	_options = options

	_user_agent = "Matcha/0.0.0 (%s; %s; %s) Godot/%s" % [
		OS.get_name(),
		OS.get_version(),
		Engine.get_architecture_name(),
		Engine.get_version_info().string.split(" ")[0]
	]

	Engine.get_main_loop().process_frame.connect(self._poll)
	Engine.get_main_loop().process_frame.connect(self._start, CONNECT_ONE_SHOT)

# Public methods
func send(data, mode=_options.mode) -> Error:
	if not is_connected:
		push_error("NOT_CONNECTED")
		return Error.ERR_CONNECTION_ERROR

	if mode == Mode.BYTES and typeof(data) != TYPE_PACKED_BYTE_ARRAY:
		if typeof(data) == TYPE_STRING:
			data = data.to_utf8_buffer()
		else:
			push_error("UNKOWN_TYPE")
			return Error.ERR_INVALID_DATA
	elif mode == Mode.TEXT and typeof(data) != TYPE_STRING:
		if typeof(data) == TYPE_PACKED_BYTE_ARRAY:
			data = data.get_string_from_utf8()
		else:
			push_error("UNKNOWN_TYPE")
			return Error.ERR_INVALID_DATA
	elif mode == Mode.JSON:
		data = JSON.stringify(data)
		if data == null:
			push_error("INVALID_JSON")
			return Error.ERR_INVALID_DATA

	if typeof(data) != TYPE_STRING:
		push_error("INVALID_DATA")
		return Error.ERR_INVALID_DATA

	return _socket.send_text(data)

func close(was_error=false) -> void:
	if _socket != null:
		_socket.close()
		_socket = null

	if _state == State.CONNECTING:
		_state = State.DISCONNECTED

	if _state == State.CONNECTED:
		_state = State.DISCONNECTED
		disconnected.emit()

	if was_error and _state != State.RECONNECTING and _options.reconnect_tries > 0:
		_reconnect_try_counter += 1

		if _reconnect_try_counter > _options.reconnect_tries:
			return

		_state = State.RECONNECTING
		reconnecting.emit()
		Engine.get_main_loop().create_timer(_options.reconnect_time).timeout.connect(func():
			_state = State.DISCONNECTED
			_start()
		)

# Private methods
func _start() -> void:
	if _socket != null:
		close()

	_socket = WebSocketPeer.new()

	if OS.get_name() != "Web":
		# When not in web we should use an useragent. Some servers dont accept requests without an user-agent
		_socket.handshake_headers = PackedStringArray([ "user-agent: %s" % [_user_agent] ])

	if _socket.connect_to_url(_url) != OK:
		close(true)
		return

	_state = State.CONNECTING
	connecting.emit()

func _poll() -> void:
	if _socket == null: return
	_socket.poll()

	var state = _socket.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED:
		close(true)
		return

	if state != WebSocketPeer.STATE_OPEN:
		return

	if _state != State.CONNECTED:
		_state = State.CONNECTED
		_reconnect_try_counter = 0
		connected.emit()

	while _socket.get_available_packet_count():
		_on_packet(_socket.get_packet())

func _on_packet(buffer: PackedByteArray) -> void:
	if _options.mode == Mode.BYTES:
		message.emit(buffer)
	elif _options.mode == Mode.TEXT:
		message.emit(buffer.get_string_from_utf8())
	elif _options.mode == Mode.JSON:
		var str := buffer.get_string_from_utf8()
		var data = JSON.parse_string(str)
		if data == null:
			push_error("[WebSocketClient] Invalid json: %s" % [str])
		else:
			message.emit(data)
