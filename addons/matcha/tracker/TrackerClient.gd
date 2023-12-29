# The TrackerClient is a simple implementation of a WebTorrent Tracker Client
# Learn more about it here (js): https://github.com/webtorrent/bittorrent-tracker
# TODO: DOCUMENT, DOCUMENT, DOCUMENT!

extends RefCounted
const Utils := preload("../lib/Utils.gd")
const WebSocketClient := preload("../lib/WebSocketClient.gd")

# Classes
class Response:
	var type: String # The type of the response ("offer" or "answer")
	var info_hash: String # The info_hash which the repsonse belongs to
	var peer_id: String # The peer_id of the other peer (who've sent it)
	var offer_id: String # The offer_id that this offer/answer belongs to
	var sdp: String # The sdp (webrtc session description) of the other peer

# Signals
signal connected # Emitted when we connected to the tracker
signal disconnected # Emitted when we disconnected from the tracker
signal reconnecting # Emitted when we are reconnecting to the tracker (after unexpected disconnect)
signal failure(reason: String) # Emitted when the tracker did not like something
signal got_offer(offer: Response) # Emitted when we got an offer
signal got_answer(answer: Response) # Emitted when we got an answer

# Members
var _socket: WebSocketClient # An internal reference to the websocket client
var _peer_id: String # Our peer_id that is used to identify us
var _tracker_url: String # The tracker we are connected to

# Getters
var is_connected:
	get: return _socket != null and _socket.is_connected
var tracker_url:
	get: return _tracker_url
var peer_id:
	get: return _peer_id

# Constructor
func _init(tracker_url: String, peer_id:=Utils.gen_id()) -> void:
	_tracker_url = tracker_url
	_peer_id = peer_id
	
	_socket = WebSocketClient.new(_tracker_url, {
		"mode": WebSocketClient.Mode.JSON,
		"reconnect_time": 3,
		"reconnect_tries": 3
	})
	_socket.connected.connect(self._on_tracker_connected)
	_socket.disconnected.connect(self._on_tracker_disconnected)
	_socket.reconnecting.connect(self._on_tracker_reconnecting)
	_socket.message.connect(self._on_tracker_message)

# Public methods
# This method is used to share our answer to an offer
func answer(info_hash: String, to_peer_id: String, offer_id: String, sdp: String) -> void:
	if not is_connected:
		connected.connect(answer.bind(info_hash, to_peer_id, offer_id, sdp), CONNECT_ONE_SHOT)
		return
	_socket.send({
		"action": "announce",
		"info_hash": info_hash,
		"peer_id": _peer_id,
		"to_peer_id": to_peer_id,
		"offer_id": offer_id,
		"answer": {
			"type": "answer",
			"sdp": sdp
		}
	})

# This method is used to
func announce(info_hash: String, offers: Array) -> void:
	if not is_connected:
		connected.connect(announce.bind(info_hash, offers), CONNECT_ONE_SHOT)
		return

	_socket.send({
		"action": "announce",
		"info_hash": info_hash,
		"peer_id": _peer_id,
		"numwant": offers.size(),
		"offers": offers
	})

# Private methods
func _on_tracker_connected() -> void:
	connected.emit()

func _on_tracker_disconnected() -> void:
	disconnected.emit()

func _on_tracker_reconnecting() -> void:
	reconnecting.emit()

func _on_tracker_message(data) -> void:
	if not typeof(data) == TYPE_DICTIONARY: return
	if "failure reason" in data:
		failure.emit(data["failure reason"])
		return
	if not "action" in data or data.action != "announce": return
	if not "info_hash" in data: return
	if "peer_id" in data and "offer_id" in data:
		var response := Response.new()
		response.info_hash = data.info_hash
		response.peer_id = data.peer_id
		response.offer_id = data.offer_id

		if "offer" in data:
			response.type = "offer"
			response.sdp = data.offer.sdp
			got_offer.emit(response)
		if "answer" in data:
			response.type = "answer"
			response.sdp = data.answer.sdp
			got_answer.emit(response)
