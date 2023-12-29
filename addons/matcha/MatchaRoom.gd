# TODO: DOCUMENT, DOCUMENT, DOCUMENT!

class_name MatchaRoom extends MultiplayerPeerExtension
const Utils := preload("res://addons/matcha/lib/Utils.gd")
const TrackerClient := preload("./tracker/TrackerClient.gd")
const MatchaPeer := preload("./MatchaPeer.gd")

# Signals
signal peer_joined(rpc_id: int, peer: MatchaPeer) # Emitted when a peer joined the room
signal peer_left(rpc_id: int, peer: MatchaPeer) # Emitted when a peer left the room

# Members
var _mp := WebRTCMultiplayerPeer.new() # Our internal reference to the multiplayer peer
var _tracker_clients: Array[TrackerClient] = [] # A list of tracker clients we use to share/get offers/answers
var _room_id: String # An unique identifier
var _peer_id := Utils.gen_id()
var _type: String
var _offer_timeout := 30
var _pool_size := 10
var _connected_peers = {}

# Getters
var rpc_id:
	get: return get_unique_id()
var peer_id:
	get: return _peer_id
var type:
	get: return _type
var room_id:
	get: return _room_id
var _peers:
	get: return _mp.get_peers().values().map(func(v): return v.connection)

# Static methods
static func create_mesh_room(options:={}) -> MatchaRoom:
	options.type = "mesh"
	return MatchaRoom.new(options)

static func create_server_room(options:={}) -> MatchaRoom:
	options.type = "server"
	return MatchaRoom.new(options)

static func create_client_room(room_id: String, options:={}) -> MatchaRoom:
	options.type = "client"
	options.room_id = room_id
	return MatchaRoom.new(options)

# Constructor
func _init(options:={}) -> void:
	if not "pool_size" in options: options.pool_size = _pool_size
	if not "offer_timeout" in options: options.offer_timeout = _offer_timeout
	if not "identifier" in options: options.identifier = "com.matcha.default"
	if not "tracker_urls" in options: options.tracker_urls = ["wss://tracker.webtorrent.dev"]
	if not "room_id" in options: options.room_id = options.identifier.sha1_text().substr(0, 20)
	if not "type" in options: options.type = "mesh"
	_pool_size = options.pool_size
	_offer_timeout = options.offer_timeout
	_room_id = options.room_id
	_type = options.type
	
	_mp.peer_connected.connect(self._on_peer_connected)
	_mp.peer_disconnected.connect(self._on_peer_disconnected)

	if _type == "mesh":
		assert(_mp.create_mesh(generate_unique_id()) == OK, "Creating mesh failed")
	elif _type == "client":
		assert(_mp.create_client(generate_unique_id()) == OK, "Creating client failed")
	elif _type == "server":
		_room_id = _peer_id # Our room_id should be our peer_id to identify ourself as the server
		assert(_mp.create_server() == OK, "Creating server failed")
	else:
		assert(false, "Invalid type")

	# Create the tracker_clients based on the urls
	for tracker_url in options.tracker_urls:
		var tracker_client := TrackerClient.new(tracker_url, _peer_id)
		tracker_client.got_offer.connect(self._on_got_offer.bind(tracker_client))
		tracker_client.got_answer.connect(self._on_got_answer.bind(tracker_client))
		tracker_client.failure.connect(self._on_failure.bind(tracker_client))
		_tracker_clients.append(tracker_client)

	Engine.get_main_loop().process_frame.connect(self.poll)

# Public methods
func find_peers(filter:={}) -> Array[MatchaPeer]:
	var result: Array[MatchaPeer] = []
	for peer in _peers:
		var matched := true
		for key in filter:
			if not key in peer or peer[key] != filter[key]:
				matched = false
				break
		if matched:
			result.append(peer)
	return result

func find_peer(filter:={}, allow_multiple_results:=false) -> MatchaPeer:
	var matches := find_peers(filter)
	if not allow_multiple_results and matches.size() > 1: return null
	if matches.size() == 0: return null
	return matches[0]

# Private methods
func _poll(): # Virtual
	_mp.poll()
	_create_offers()
	_handle_offers_announcment()

func _remove_unanswered_offer(offer_id: String) -> void:
	var offer := find_peer({ "answered": false, "offer_id": offer_id })
	if offer != null:
		offer.close()

func _create_offer() -> void:
	if _type == "client" and _mp.has_peer(1): return # We already created the host offer. So lets ignore the offer creating

	var offer_peer = MatchaPeer.create_offer_peer()
	_mp.add_peer(offer_peer, 1 if _type == "client" else generate_unique_id())

	# Cleanup when the offer was not answered for long time
	Engine.get_main_loop().create_timer(_offer_timeout).timeout.connect(self._remove_unanswered_offer.bind(offer_peer.offer_id))

func _create_offers() -> void:
	var unanswered_offers := find_peers({ "type": "offer", "answered": false })
	if unanswered_offers.size() > 0: return # There are ongoing offers. Dont refresh the pool.
	if _type == "client" and _mp.has_peer(1): return # If we are already connected in client mode dont create further offers

	# Create as many offers as the pool_size
	for i in range(_pool_size):
		_create_offer()

func _handle_offers_announcment():
	var unannounced_offers := find_peers({ "type": "offer", "announced": false })
	if unannounced_offers.size() == 0: return # There are no offers to announce

	var announce_offers: Array = [] # The array we need for the tracker offer announcements
	for offer_peer: MatchaPeer in unannounced_offers:
		if not offer_peer.gathered: return # If we have ungathered offers we are not ready yet to announce.

		if _type == "client":
			# As client lets announce the host peer multiple times. Since we cannot have multiple peers with id 1 setup
			assert(unannounced_offers.size() == 1, "In client mode you should have just 1 offer")
			for i in range(_pool_size):
				announce_offers.append({ "offer_id": Utils.gen_id(), "offer": { "type": "offer", "sdp": offer_peer.local_sdp } })
		else:
			announce_offers.append({ "offer_id": offer_peer.offer_id, "offer": { "type": "offer", "sdp": offer_peer.local_sdp } })

	for offer_peer: MatchaPeer in unannounced_offers:
		offer_peer.mark_as_announced()

	for tracker_client in _tracker_clients: # Announce the offers via every tracker
		tracker_client.announce(_room_id, announce_offers)

func _send_answer_sdp(answer_sdp: String, peer: MatchaPeer, tracker_client: TrackerClient):
	tracker_client.answer(_room_id, peer.peer_id, peer.offer_id, answer_sdp)

func _on_got_offer(offer: TrackerClient.Response, tracker_client: TrackerClient) -> void:
	if offer.info_hash != _room_id: return
	if find_peer({ "peer_id": offer.peer_id }) != null: return # Ignore if the peer is already known
	if _type == "client" and offer.peer_id != room_id: return # Ignore offers from others than host (in client mode)

	var peer := MatchaPeer.create_answer_peer(offer.offer_id, offer.sdp)
	peer.set_peer_id(offer.peer_id)

	peer.sdp_created.connect(self._send_answer_sdp.bind(peer, tracker_client))
	_mp.add_peer(peer, 1 if _type == "client" else generate_unique_id())

func _on_got_answer(answer: TrackerClient.Response, tracker_client: TrackerClient) -> void:
	if answer.info_hash != _room_id: return
	if _type == "client" and answer.peer_id != room_id: return # As client we just accept answers from the host

	var offer_peer: MatchaPeer
	if _type == "client":
		if _mp.has_peer(1):
			offer_peer = _mp.get_peer(1).connection
			offer_peer.set_offer_id(answer.offer_id) # Fix the offer_id since we gave the server alot of offers to choose from
	else:
		offer_peer = find_peer({ "offer_id": answer.offer_id })
	if offer_peer == null: return # Ignore if we dont know that offer

	offer_peer.set_peer_id(answer.peer_id)
	offer_peer.set_answer(answer.sdp)

func _on_failure(reason: String, tracker_client: TrackerClient) -> void:
	print("Tracker failure: ", reason, ", Tracker: ", tracker_client.tracker_url)

func _on_peer_connected(id: int) -> void:
	peer_connected.emit(id)

	var peer: MatchaPeer = _mp.get_peer(id).connection
	_connected_peers[id] = peer
	peer_joined.emit(id, peer)

func _on_peer_disconnected(id: int) -> void:
	peer_disconnected.emit(id)

	var peer: MatchaPeer = _connected_peers[id]
	_connected_peers.erase(id)
	peer_left.emit(id, peer)

# Virtuals
func _get_unique_id(): return _mp.get_unique_id()
func _get_available_packet_count(): return _mp.get_available_packet_count()
func _get_connection_status(): return _mp.get_connection_status()
func _close(): _mp.close()
func _disconnect_peer(p_peer, p_force): _mp.disconnect_peer(p_peer, p_force)
func _get_max_packet_size(): return _mp.get_max_packet_size()
func _get_packet_channel(): return _mp.get_packet_channel()
func _get_packet_mode(): return _mp.get_packet_mode()
func _get_packet_peer(): return _mp.get_packet_peer()
func _get_packet_script(): return _mp.get_packet()
func _get_transfer_channel(): return _mp.get_transfer_channel()
func _get_transfer_mode(): return _mp.get_transfer_mode()
func _is_refusing_new_connections(): return _mp.is_refusing_new_connections()
func _is_server(): return _mp.is_server()
func _is_server_relay_supported(): return _mp.is_server_relay_supported()
func _put_packet_script(p_buffer): return _mp.put_packet(p_buffer)
func _set_refuse_new_connections(p_enable): _mp.set_refuse_new_connections(p_enable)
func _set_target_peer(p_peer): _mp.set_target_peer(p_peer)
func _set_transfer_channel(p_channel): _mp.set_transfer_channel(p_channel)
func _set_transfer_mode(p_mode): _mp.set_transfer_mode(p_mode)
