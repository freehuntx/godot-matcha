extends RefCounted

# Signals
signal connected
signal connecting_failed
signal disconnected
signal sdp_created(sdp: String)

# Members
var _peer: WebRTCPeerConnection
var _gathered := false
var _connecting := false
var _connected := false
var _type: String
var _local_sdp: String
var _remote_sdp: String
var _rtc_peer: WebRTCMultiplayerPeer
var _rtc_peer_id: int

var peer:
	get: return _peer
var gathered:
	get: return _gathered
var local_sdp:
	get: return _local_sdp

# Constructor
func _init(rtc_peer: WebRTCMultiplayerPeer):
	_rtc_peer = rtc_peer
	_rtc_peer_id = rtc_peer.generate_unique_id()
	_peer = WebRTCPeerConnection.new()
	_peer.initialize({"iceServers":[{"urls":["stun:stun.l.google.com:19302"]}]})
	_peer.session_description_created.connect(self._on_sdp_created)
	_peer.ice_candidate_created.connect(self._on_icecandidate_created)
	_rtc_peer.add_peer(_peer, _rtc_peer_id)
	_poll()

# Public methods
func close():
	if _rtc_peer.has_peer(_rtc_peer_id):
		_rtc_peer.remove_peer(_rtc_peer_id)

func set_answer(remote_sdp: String):
	assert(_type == "offer", "The peer is not an offer")
	assert(_remote_sdp == "", "The offer was already answered")
	_remote_sdp = remote_sdp
	_peer.set_remote_description("answer", remote_sdp)

func create_offer() -> Error:
	assert(_type == "", "The peer is already in use")
	_type = "offer"
	var err := _peer.create_offer()
	if err != OK:
		close()
	return err

func create_answer(remote_sdp: String):
	assert(_type == "", "The peer is already in use")
	_type = "answer"
	_peer.set_remote_description("offer", remote_sdp)

# Private methods
func _poll():
	_peer.poll()
	if not _gathered:
		if _peer.get_gathering_state() == WebRTCPeerConnection.GATHERING_STATE_COMPLETE:
			_gathered = true
			_connecting = true
			_peer.set_local_description(_type, _local_sdp)
			sdp_created.emit(_local_sdp)
	if _connecting:
		var state := _peer.get_connection_state()
		if not state == WebRTCPeerConnection.STATE_CONNECTING:
			_connecting = false
			_connected = state == WebRTCPeerConnection.STATE_CONNECTED
			if _connected:
				connected.emit()
			else:
				connecting_failed.emit()
				close()
				return
	if _connected:
		var state := _peer.get_connection_state()
		if state != WebRTCPeerConnection.STATE_CONNECTED:
			_connected = false
			disconnected.emit()
			close()
			return

	Engine.get_main_loop().create_timer(0.1).timeout.connect(self._poll)

func _on_sdp_created(type: String, sdp: String):
	_local_sdp = sdp

func _on_icecandidate_created(media: String, index: int, name: String):
	_local_sdp += "a=%s\r\n" % [name]
	
