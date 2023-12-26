class_name MatchaRoom extends RefCounted
const Utils := preload("res://addons/matcha/lib/Utils.gd")
const TrackerClient := preload("./tracker/TrackerClient.gd")
const MatchaPeer := preload("./MatchaPeer.gd")
const POOL_SIZE := 10
const POLL_INTERVAL := 0.1
const OFFER_TIMEOUT := 30

# Members
var _tracker_clients: Array[TrackerClient] = []
var _info_hash: String
var _peer_id := Utils.gen_id()
var _rtc_peer := WebRTCMultiplayerPeer.new()
var _rtc_peer_id: int
var _peers := {}
var _offers := {}

# Getters
var rtc_peer:
	get: return _rtc_peer
var rtc_peer_id:
	get: return _rtc_peer_id

# Constructor
func _init(options:={}) -> void:
	var room_identifier: String = "com.matcha.default" if not "identifier" in options else options.identifier
	var tracker_urls = ["wss://tracker.webtorrent.dev"] if not "tracker_urls" in options else options.tracker_urls
	_info_hash = room_identifier.sha1_text().substr(0, 20)
	_rtc_peer_id = _rtc_peer.generate_unique_id()
	_rtc_peer.create_mesh(_rtc_peer_id)

	for tracker_url in tracker_urls:
		var tracker_client := TrackerClient.new({ "tracker_url": tracker_url, "peer_id": _peer_id })
		tracker_client.offer.connect(self._on_offer.bind(tracker_client))
		tracker_client.answer.connect(self._on_answer.bind(tracker_client))
		tracker_client.failure.connect(self._on_failure.bind(tracker_client))
		_tracker_clients.append(tracker_client)

	_poll() # Starts the poll loop

# Private methods
func _poll():
	_rtc_peer.poll()
	_cleanup_offers()
	_create_offers()
	_handle_offers_announcment()

	Engine.get_main_loop().create_timer(POLL_INTERVAL).timeout.connect(self._poll) # Run poll in x seconds again

func _cleanup_offers() -> void:
	var current_time := Time.get_unix_time_from_system()
	for offer in _offers.values():
		if current_time - offer.created_at > OFFER_TIMEOUT:
			offer.peer.close()
			_offers.erase(offer.id)

func _create_offer() -> void:
	var offer = {
		"id": Utils.gen_id(),
		"peer": MatchaPeer.new(_rtc_peer),
		"announced": false,
		"created_at": Time.get_unix_time_from_system()
	}
	if offer.peer.create_offer() != OK:
		return
	_offers[offer.id] = offer

func _create_offers() -> void:
	if _offers.size() > 0: return

	for i in range(POOL_SIZE):
		_create_offer()

func _cleanup_peer_id(peer_id: String):
	if peer_id in _peers:
		_peers.erase(peer_id)

func _handle_offers_announcment():
	if _offers.size() == 0: return # No announcements needed if we have no offers

	var announce_offers := [] # The array we need for the tracker offer announcements
	for offer in _offers.values():
		if not offer.peer.gathered: return # If we have ungathered offers we are not ready yet to announce.
		if offer.announced: return # If we have announced offers something is wrong. We stop the announcement then.
		announce_offers.append({ "offer_id": offer.id, "offer": { "type": "offer", "sdp": offer.peer.local_sdp } })
	for offer in _offers.values():
		offer.announced = true # Mark the offer as announced
	for tracker_client in _tracker_clients: # Announce the offers via every tracker
		tracker_client.announce(_info_hash, announce_offers)

func _on_offer(offer: Dictionary, tracker_client: TrackerClient) -> void:
	if offer.peer_id in _peers: return # Ignore the offer if we know the peer already

	var peer := MatchaPeer.new(_rtc_peer)
	peer.disconnected.connect(self._cleanup_peer_id.bind(offer.peer_id))
	peer.connecting_failed.connect(self._cleanup_peer_id.bind(offer.peer_id))
	peer.sdp_created.connect(self._send_answer_sdp.bind(offer.peer_id, offer.offer_id, tracker_client))
	peer.create_answer(offer.sdp)
	_peers[offer.peer_id] = peer

func _on_answer(answer: Dictionary, tracker_client: TrackerClient) -> void:
	if not answer.offer_id in _offers: return
	var offer = _offers[answer.offer_id]
	_offers.erase(answer.offer_id)
	
	if answer.peer_id in _peers: return

	offer.peer.disconnected.connect(self._cleanup_peer_id.bind(answer.peer_id))
	offer.peer.connecting_failed.connect(self._cleanup_peer_id.bind(answer.peer_id))
	_peers[answer.peer_id] = offer.peer
	offer.peer.set_answer(answer.sdp)

func _send_answer_sdp(answer_sdp: String, peer_id: String, offer_id: String, tracker_client: TrackerClient):
	tracker_client.send_answer(_info_hash, {
		"peer_id": peer_id,
		"offer_id": offer_id,
		"sdp": answer_sdp
	})

func _on_failure(reason: String, tracker_client: TrackerClient) -> void:
	print("Tracker failure: ", reason, ", Tracker: ", tracker_client.tracker_url)
