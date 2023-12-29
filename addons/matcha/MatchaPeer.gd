# TODO: DOCUMENT, DOCUMENT, DOCUMENT!

class_name MatchaPeer extends WebRTCPeerConnection
const Utils := preload("./lib/Utils.gd")

enum State { NEW, GATHERING, CONNECTING, CONNECTED, CLOSED }

# Signals
signal connecting
signal connected
signal disconnected
signal closed
signal connecting_failed
signal sdp_created(sdp: String)

# Members
var _announced := false
var _peer_id: String
var _offer_id: String
var _state := State.NEW
var _answered := false
var _type: String
var _local_sdp: String
var _remote_sdp: String

var is_connected:
	get: return _state == State.CONNECTED
var type:
	get: return _type
var offer_id:
	get: return _offer_id
var gathered:
	get: return _state > State.GATHERING
var announced:
	get: return _announced
var answered:
	get: return _answered
var local_sdp:
	get: return _local_sdp
var peer_id:
	get: return _peer_id

# Static methods
static func create_offer_peer(offer_id := Utils.gen_id()) -> MatchaPeer:
	return MatchaPeer.new("offer", offer_id)

static func create_answer_peer(offer_id: String, remote_sdp: String) -> MatchaPeer:
	return MatchaPeer.new("answer", offer_id, remote_sdp)

# Constructor
func _init(type: String, offer_id: String, remote_sdp=""):
	_type = type
	_offer_id = offer_id
	_remote_sdp = remote_sdp

	session_description_created.connect(self._on_session_description_created)
	ice_candidate_created.connect(self._on_ice_candidate_created)

	var err := initialize({"iceServers":[{"urls":["stun:stun.l.google.com:19302"]}]})
	if err != OK:
		push_error("Initializing failed")
		_state = State.CLOSED

# Public methods
func start() -> Error:
	if _state != State.NEW:
		push_error("Peer state is not new")
		return Error.ERR_ALREADY_IN_USE

	_state = State.GATHERING

	if _type == "offer":
		var err := create_offer()
		if err != OK:
			push_error("Creating offer failed")
			return err
	elif _type == "answer":
		if _remote_sdp == "":
			push_error("Missing sdp")
			return Error.ERR_INVALID_DATA

		var err := set_remote_description("offer", _remote_sdp)
		if err != OK:
			push_error("Creating answer failed")
			return err
	else:
		push_error("Unknown type: ", _type)
		return Error.ERR_INVALID_DATA

	Engine.get_main_loop().process_frame.connect(self.__poll) # Start the poll loop
	return Error.OK

func set_peer_id(new_peer_id: String) -> void:
	_peer_id = new_peer_id

func set_offer_id(new_offer_id: String) -> void:
	_offer_id = new_offer_id

func set_answer(remote_sdp: String) -> Error:
	if _type != "offer":
		push_error("The peer is not an offer")
		return Error.ERR_INVALID_DATA
	if _answered:
		push_error("The offer was already answered")
		return Error.ERR_ALREADY_IN_USE

	_answered = true
	_remote_sdp = remote_sdp
	return set_remote_description("answer", remote_sdp)

func mark_as_announced() -> Error:
	if _announced:
		push_error("The offer was already answered")
		return Error.ERR_ALREADY_IN_USE
		
	_announced = true
	return Error.OK

# Private methods
func __poll():
	if _state == State.NEW or _state == State.CLOSED: return
	poll()

	if _state == State.GATHERING:
		var gathering_state := get_gathering_state()
		if gathering_state != WebRTCPeerConnection.GATHERING_STATE_COMPLETE:
			return

		_state = State.CONNECTING
		sdp_created.emit(_local_sdp)
		connecting.emit()

	var connection_state := get_connection_state()
	if _state == State.CONNECTING:
		if connection_state == WebRTCPeerConnection.STATE_CONNECTING:
			return
		if connection_state != WebRTCPeerConnection.STATE_CONNECTED:
			__close()
			return

		_state = State.CONNECTED
		connected.emit()

	if _state == State.CONNECTED:
		if connection_state != WebRTCPeerConnection.STATE_CONNECTED:
			__close()
			return

func __close():
	if _state == State.CLOSED:
		return

	close()

	if _state == State.CONNECTING:
		connecting_failed.emit()
	elif _state == State.CONNECTED:
		disconnected.emit()

	_state = State.CLOSED
	closed.emit()

# Callbacks
func _on_session_description_created(type: String, sdp: String):
	_local_sdp = sdp
	set_local_description(type, sdp)

func _on_ice_candidate_created(media: String, index: int, name: String):
	_local_sdp += "a=%s\r\n" % [name]
