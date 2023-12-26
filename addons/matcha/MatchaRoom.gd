class_name MatchaRoom extends RefCounted
const Utils := preload("res://addons/matcha/lib/Utils.gd")
const TrackerClient := preload("./tracker/TrackerClient.gd")
const MatchaPeer := preload("./MatchaPeer.gd")
const POOL_SIZE := 10
const OFFER_TIMEOUT := 30

# Members
var _tracker_clients: Array[TrackerClient] = []
var _info_hash: String
var _peer_id := Utils.gen_id()
var _rtc_peer := WebRTCMultiplayerPeer.new()
var _rtc_peer_id: int
var _peers: Array[MatchaPeer] = []

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

	Engine.get_main_loop().process_frame.connect(self._poll)

# Private methods
func _poll():
	_rtc_peer.poll()
	_create_offers()
	_handle_offers_announcment()

func _remove_offer(offer_id: String) -> void:
	for peer in _peers:
		if peer.offer_id != offer_id: continue
		peer.close()
		_peers.erase(peer)

func _remove_peer_id(peer_id: String) -> void:
	for peer in _peers:
		if peer.peer_id != peer_id: continue
		peer.close()
		_peers.erase(peer)

func _create_offer() -> void:
	var offer_peer := MatchaPeer.new(_rtc_peer)
	if offer_peer.create_offer() != OK: return
	offer_peer.closed.connect(self._remove_offer.bind(offer_peer.offer_id))
	_peers.append(offer_peer)

	Engine.get_main_loop().create_timer(OFFER_TIMEOUT).timeout.connect(self._remove_offer.bind(offer_peer.offer_id))

func _create_offers() -> void:
	var unanswered_offers := _peers.filter(func(p): return p.type == "offer" and not p.answered)
	if unanswered_offers.size() > 0: return # There are ongoing offers. Dont refresh the pool.

	for i in range(POOL_SIZE):
		_create_offer()

func _handle_offers_announcment():
	var unannounced_offers := _peers.filter(func(p): return p.type == "offer" and not p.announced)
	if unannounced_offers.size() == 0: return # There are no offers to announce

	var announce_offers := [] # The array we need for the tracker offer announcements
	for offer_peer in unannounced_offers:
		if not offer_peer.gathered: return # If we have ungathered offers we are not ready yet to announce.
		announce_offers.append({ "offer_id": offer_peer.offer_id, "offer": { "type": "offer", "sdp": offer_peer.local_sdp } })
	for offer_peer in unannounced_offers:
		offer_peer.announced = true # Mark the offer as announced
	for tracker_client in _tracker_clients: # Announce the offers via every tracker
		tracker_client.announce(_info_hash, announce_offers)

func _on_offer(offer: Dictionary, tracker_client: TrackerClient) -> void:
	for peer in _peers:
		if peer.peer_id == offer.peer_id: return

	var peer := MatchaPeer.new(_rtc_peer)
	peer.peer_id = offer.peer_id
	peer.offer_id = offer.offer_id
	peer.sdp_created.connect(self._send_answer_sdp.bind(offer.peer_id, offer.offer_id, tracker_client))
	peer.closed.connect(self._remove_offer.bind(offer.offer_id))
	peer.create_answer(offer.sdp)
	_peers.append(peer)

func _on_answer(answer: Dictionary, tracker_client: TrackerClient) -> void:
	var offer: MatchaPeer
	for peer in _peers:
		if peer.peer_id == answer.peer_id: return
		if peer.type != "offer" or peer.offer_id != answer.offer_id or peer.answered: continue
		offer = peer
		break

	if offer == null: return
	offer.peer_id = answer.peer_id
	offer.set_answer(answer.sdp)

func _send_answer_sdp(answer_sdp: String, peer_id: String, offer_id: String, tracker_client: TrackerClient):
	tracker_client.send_answer(_info_hash, {
		"peer_id": peer_id,
		"offer_id": offer_id,
		"sdp": answer_sdp
	})

func _on_failure(reason: String, tracker_client: TrackerClient) -> void:
	print("Tracker failure: ", reason, ", Tracker: ", tracker_client.tracker_url)
