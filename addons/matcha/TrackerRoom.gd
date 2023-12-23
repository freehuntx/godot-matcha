class_name TrackerRoom extends "./EventEmitter.gd"
const TrackerClient := preload("./TrackerClient.gd")
const Utils := preload("./Utils.gd")

# Members
var _options: Dictionary
var _tracker_clients: Array[TrackerClient] = []
var _peers := {}
var _offers := {}

# Constructor
func _init(options:={}) -> void:
	if not "peer_id" in options: options.peer_id = Utils.gen_id()
	if not "tracker_urls" in options: options.tracker_urls = ["wss://tracker.webtorrent.dev"]
	if not "identifier" in options: options.identifier = "com.matcha.default"
	if not "info_hash" in options: options.info_hash = options.identifier.sha1_text().substr(0, 20)
	if not "pool_size" in options: options.pool_size = 10
	if not "poll_interval" in options: options.poll_interval = 0.1
	if not "offer_timeout" in options: options.offer_timeout = 30
	_options = options

	for tracker_url in options.tracker_urls:
		var tracker_client = TrackerClient.new({
			"tracker_url": tracker_url,
			"peer_id": _options.peer_id
		})
		tracker_client.on("offer", func(offer): _on_offer(tracker_client, offer))
		tracker_client.on("answer", func(answer): _on_answer(tracker_client, answer))
		tracker_client.on("failure", func(reason): _on_failure(tracker_client, reason))
		_tracker_clients.append(tracker_client)

	_poll() # Starts the poll loop

# Private methods
func _poll() -> void:
	_cleanup_offers()
	_create_offers()
	_handle_offers_gathering_state()
	_handle_offers_announcment()
	_handle_peers()

	Engine.get_main_loop().create_timer(_options.poll_interval).timeout.connect(self._poll)

func _create_offers() -> void:
	if _offers.size() != 0: return

	var current_time := Time.get_unix_time_from_system()
	for i in range(_options.pool_size):
		var offer = {
			"id": Utils.gen_id(),
			"peer": null,
			"sdp": "",
			"gathered": false,
			"announced": false,
			"created_at": current_time
		}

		offer.peer = WebRTCPeerConnection.new()
		offer.peer.initialize({"iceServers":[{"urls":["stun:stun.l.google.com:19302"]}]})
		offer.peer.create_data_channel("default")
		offer.peer.session_description_created.connect(func(type: String, sdp: String):
			offer.sdp = sdp
		)
		offer.peer.ice_candidate_created.connect(func(media: String, index: int, name: String):
			offer.sdp += "a=%s\r\n" % [name]
		)
		if offer.peer.create_offer() == OK: _offers[offer.id] = offer

func _cleanup_offers() -> void:
	var current_time := Time.get_unix_time_from_system()
	for offer in _offers.values():
		if current_time - offer.created_at > _options.offer_timeout:
			_offers.erase(offer.id)

func _handle_offers_gathering_state() -> void:
	for offer in _offers.values():
		if offer.gathered: continue
		offer.peer.poll()
		if offer.peer.get_gathering_state() == WebRTCPeerConnection.GATHERING_STATE_COMPLETE:
			offer.gathered = true
			offer.peer.set_local_description("offer", offer.sdp)

func _handle_offers_announcment() -> void:
	if _offers.size() == 0: return

	var announce_offers := []
	for offer in _offers.values():
		if offer.announced: return
		if not offer.gathered: return
		announce_offers.append({ "offer_id": offer.id, "offer": { "type": "offer", "sdp": offer.sdp } })

	for offer in _offers.values():
		offer.announced = true
	for tracker_client in _tracker_clients:
		tracker_client.announce(_options.info_hash, announce_offers)

func _handle_peers():
	for peer in _peers.values():
		peer.peer.poll()
		var state = peer.peer.get_connection_state()

		if peer.connecting:
			if state == WebRTCPeerConnection.STATE_CONNECTED:
				peer.connecting = false
				peer.connected = true
				emit("peer_connected", [peer.id, peer.peer])
			elif state != WebRTCPeerConnection.STATE_CONNECTING:
				_peers.erase(peer.id)
				continue
		elif peer.connected:
			if state != WebRTCPeerConnection.STATE_CONNECTED:
				peer.connected = false
				emit("peer_disconnected", [peer.id, peer.peer])
				_peers.erase(peer.id)
				continue
		else:
			_peers.erase(peer.id)
			continue

func _on_offer(tracker: TrackerClient, offer: Dictionary) -> void:
	if offer.peer_id in _peers: return

	var answer := { "sdp": "", "gathered": false }
	var peer := WebRTCPeerConnection.new()
	peer.initialize({"iceServers":[{"urls":["stun:stun.l.google.com:19302"]}]})
	peer.create_data_channel("default")
	peer.session_description_created.connect(func(type: String, sdp: String):
		answer.sdp = sdp
	)
	peer.ice_candidate_created.connect(func(media: String, index: int, name: String):
		answer.sdp += "a=%s\r\n" % [name]
	)
	peer.set_remote_description("offer", offer.sdp)

	var start_time := Time.get_unix_time_from_system()
	while true:
		await Engine.get_main_loop().create_timer(0.1).timeout
		if Time.get_unix_time_from_system() - start_time > _options.offer_timeout: return
		if offer.peer_id in _peers: return
		peer.poll()

		if not answer.gathered:
			if peer.get_gathering_state() != WebRTCPeerConnection.GATHERING_STATE_COMPLETE: continue
			answer.gathered = true
			peer.set_local_description("answer", answer.sdp)

		tracker.send_answer(offer.info_hash, {
			"peer_id": offer.peer_id,
			"offer_id": offer.offer_id,
			"sdp": answer.sdp
		})
		_peers[offer.peer_id] = { "id": offer.peer_id, "peer": peer, "connected": false, "connecting": true }
		return

func _on_answer(tracker: TrackerClient, answer: Dictionary) -> void:
	if not answer.offer_id in _offers: return

	var offer = _offers[answer.offer_id]
	_offers.erase(offer.id)

	if answer.peer_id in _peers: return
	_peers[answer.peer_id] = { "id": answer.peer_id, "peer": offer.peer, "connected": false, "connecting": true }
	offer.peer.set_remote_description("answer", answer.sdp)

func _on_failure(tracker: TrackerClient, reason: String) -> void:
	assert(false, "Tracker fail: %s" % reason)
