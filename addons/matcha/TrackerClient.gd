extends "./EventEmitter.gd"
const WebSocketClient := preload("./WebSocketClient.gd")
const Utils := preload("./Utils.gd")

# Members
var _socket: WebSocketClient
var _options: Dictionary

# Getters
var is_connected:
	get: return _socket != null and _socket.is_connected
var tracker_url:
	get: return _options.tracker_url
var peer_id:
	get: return _options.peer_id

# Constructor
func _init(options:={}) -> void:
	assert("tracker_url" in options, "MISSING_TRACKER_URL")
	if not "peer_id" in options: options.peer_id = Utils.gen_id()
	_options = options
	
	_socket = WebSocketClient.new(_options.tracker_url, {
		"mode": WebSocketClient.Mode.JSON,
		"reconnect_time": 3
	})
	_socket.on("connected", self._on_tracker_connected)
	_socket.on("disconnected", self._on_tracker_disconnected)
	_socket.on("reconnecting", self._on_tracker_reconnecting)
	_socket.on("message", self._on_tracker_message)

# Public methods
func send_answer(info_hash: String, answer: Dictionary) -> void:
	if not is_connected:
		once("connected", send_answer.bind(info_hash, answer))
		return
	_socket.send({
		"action": "announce",
		"info_hash": info_hash,
		"peer_id": _options.peer_id,
		"to_peer_id": answer.peer_id,
		"offer_id": answer.offer_id,
		"answer": {
			"type": "answer",
			"sdp": answer.sdp
		}
	})

func announce(info_hash: String, offers: Array) -> void:
	if not is_connected:
		once("connected", announce.bind(info_hash, offers))
		return
	_socket.send({
		"action": "announce",
		"info_hash": info_hash,
		"peer_id": _options.peer_id,
		"numwant": offers.size(),
		"offers": offers
	})

# Private methods
func _on_tracker_connected() -> void:
	emit("connected")

func _on_tracker_disconnected() -> void:
	emit("disconnected")

func _on_tracker_reconnecting() -> void:
	emit("reconnecting")

func _on_tracker_message(data) -> void:
	if not typeof(data) == TYPE_DICTIONARY: return
	if "failure reason" in data:
		emit("failure", [data["failure reason"]])
		return
	if not "action" in data or data.action != "announce": return
	if not "info_hash" in data: return
	if "peer_id" in data and "offer_id" in data:
		if "offer" in data:
			emit("offer", [{
				"info_hash": data.info_hash,
				"peer_id": data.peer_id,
				"offer_id": data.offer_id,
				"sdp": data.offer.sdp
			}])
		if "answer" in data:
			emit("answer", [{
				"info_hash": data.info_hash,
				"peer_id": data.peer_id,
				"offer_id": data.offer_id,
				"sdp": data.answer.sdp
			}])
