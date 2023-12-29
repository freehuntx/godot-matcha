# TODO: DOCUMENT, DOCUMENT, DOCUMENT!

class_name MatchaPeer extends WebRTCPeerConnectionExtension
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
var _peer := WebRTCPeerConnection.new()
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

static func create_answer_peer(offer_id: String, offer_sdp: String) -> MatchaPeer:
	return MatchaPeer.new("answer", offer_id, offer_sdp)

# Constructor
func _init(type: String, offer_id: String, sdp=""):
	assert(type == "offer" or type == "answer", "Invalid type: %s" % [type])
	_type = type
	_offer_id = offer_id

	_peer.session_description_created.connect(self._on_session_description_created)
	_peer.ice_candidate_created.connect(self._on_ice_candidate_created)
	_peer.data_channel_received.connect(self._on_data_channel_received)

	initialize({"iceServers":[{"urls":["stun:stun.l.google.com:19302"]}]})

	# Initialize deferred so the peer can be added to multiplayer first
	Engine.get_main_loop().create_timer(0).timeout.connect(func():
		_state = State.GATHERING
		if type == "offer":
			create_offer()
		elif type == "answer":
			assert(sdp != "", "Missing sdp")
			_remote_sdp = sdp
			set_remote_description("offer", sdp)

		Engine.get_main_loop().process_frame.connect(self.poll) # Start the poll loop
	)

# Public methods
func set_peer_id(new_peer_id: String) -> void:
	_peer_id = new_peer_id

func set_offer_id(new_offer_id: String) -> void:
	_offer_id = new_offer_id

func set_answer(remote_sdp: String):
	assert(_type == "offer", "The peer is not an offer")
	assert(not _answered, "The offer was already answered")
	_answered = true
	_remote_sdp = remote_sdp
	set_remote_description("answer", remote_sdp)

func mark_as_announced():
	assert(_announced == false, "Already announced")
	_announced = true

# Private methods
func _close(): # Virtual
	if _state == State.CLOSED:
		return

	_peer.close()

	if _state == State.CONNECTING:
		connecting_failed.emit()
	elif _state == State.CONNECTED:
		disconnected.emit()

	_state = State.CLOSED
	closed.emit()

func _poll(): # Virtual
	if _state == State.GATHERING:
		get_gathering_state()
	elif _state == State.CONNECTING or _state == State.CONNECTED:
		get_connection_state()
	return _peer.poll()

func _get_gathering_state(): # Virtual
	var gathering_state := _peer.get_gathering_state()

	if _state == State.GATHERING and gathering_state == WebRTCPeerConnection.GATHERING_STATE_COMPLETE:
		_state = State.CONNECTING
		sdp_created.emit(_local_sdp)
		connecting.emit()

	return gathering_state

func _get_connection_state(): # Virtual
	var connection_state := _peer.get_connection_state()

	if _state == State.CONNECTING and connection_state != WebRTCPeerConnection.STATE_CONNECTING:
		if connection_state != WebRTCPeerConnection.STATE_CONNECTED:
			close()
		else:
			_state = State.CONNECTED
			connected.emit()

	if _state == State.CONNECTED:
		if connection_state != WebRTCPeerConnection.STATE_CONNECTED:
			close()

	return connection_state

func _add_ice_candidate(p_sdp_mid_name: String, p_sdp_mline_index: int, p_sdp_name: String): return _peer.add_ice_candidate(p_sdp_mid_name, p_sdp_mline_index, p_sdp_name)
func _create_data_channel(p_label: String, p_config: Dictionary): return _peer.create_data_channel(p_label, p_config)
func _create_offer(): return _peer.create_offer()
func _get_signaling_state(): return _peer.get_signaling_state()
func _initialize(p_config: Dictionary): return _peer.initialize(p_config)
func _set_local_description(p_type: String, p_sdp: String): return _peer.set_local_description(p_type, p_sdp)
func _set_remote_description(p_type: String, p_sdp: String): return _peer.set_remote_description(p_type, p_sdp)

# Callbacks
func _on_session_description_created(type: String, sdp: String):
	_local_sdp = sdp
	session_description_created.emit(type, sdp)
	set_local_description(type, sdp)

func _on_ice_candidate_created(media: String, index: int, name: String):
	_local_sdp += "a=%s\r\n" % [name]
	ice_candidate_created.emit(media, index, name)

func _on_data_channel_received(channel: WebRTCDataChannel):
	data_channel_received.emit(channel)
