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
var _state := State.DISCONNECTED
var _url: String
var _socket: WebSocketPeer
var _options: Dictionary

# Getters
var is_connected:
	get: return _state == State.CONNECTED

# Constructor
func _init(url: String, options:={}) -> void:
	if not "mode" in options: options.mode = Mode.BYTES
	_url = url
	_options = options
	Engine.get_main_loop().process_frame.connect(self._poll)
	Engine.get_main_loop().process_frame.connect(self._start, CONNECT_ONE_SHOT)

# Public methods
func send(data, mode=_options.mode) -> void:
	assert(is_connected, "NOT_CONNECTED")

	if mode == Mode.BYTES and typeof(data) != TYPE_PACKED_BYTE_ARRAY:
		if typeof(data) == TYPE_STRING: data = data.to_utf8_buffer()
		else: assert(false, "UNKNOWN_TYPE")
	elif mode == Mode.TEXT and typeof(data) != TYPE_STRING:
		if typeof(data) == TYPE_PACKED_BYTE_ARRAY: data = data.get_string_from_utf8()
		else: assert(false, "UNKNOWN_TYPE")
	elif mode == Mode.JSON:
		data = JSON.stringify(data)
		if data == null: assert(false, "INVALID_JSON")

	assert(typeof(data) == TYPE_STRING, "INVALID_DATA")
	_socket.send_text(data)

func close(was_error=false) -> void:
	if _socket != null:
		_socket.close()
		_socket = null
	if _state == State.CONNECTING:
		_state = State.DISCONNECTED
	if _state == State.CONNECTED:
		_state = State.DISCONNECTED
		disconnected.emit()
	if was_error and _state != State.RECONNECTING and "reconnect_time" in _options:
		_state = State.RECONNECTING
		reconnecting.emit()
		Engine.get_main_loop().create_timer(_options.reconnect_time).timeout.connect(func():
			_state = State.DISCONNECTED
			_start()
		)

# Private methods
func _start() -> void:
	if _socket != null: close()
	_socket = WebSocketPeer.new()
	if OS.get_name() != "Web":
		_socket.handshake_headers = PackedStringArray([
			"user-agent: lel"
		])
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
		connected.emit()

	while _socket.get_available_packet_count():
		_on_packet(_socket.get_packet())

func _on_packet(buffer: PackedByteArray) -> void:
	if _options.mode == Mode.BYTES:
		message.emit(buffer)
	elif _options.mode == Mode.TEXT:
		message.emit(buffer.get_string_from_utf8())
	elif _options.mode == Mode.JSON:
		var data = JSON.parse_string(buffer.get_string_from_utf8())
		if data == null: assert(false, "INVALID_JSON")
		message.emit(data)
