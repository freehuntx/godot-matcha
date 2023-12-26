GDPC                �                                                                         T   res://.godot/exported/133200997/export-61e474ebecd96a8a7bfc183b8acbdb18-bobble.scn  C      �      ��������6��8�:�    P   res://.godot/exported/133200997/export-6581cd44ca730c421bddc3302d6ce6cc-root.scnV      �      5�*[�@T�����_�    T   res://.godot/exported/133200997/export-bab7f66da158eb92d4a519c9e5bf8439-player.scn  P6            L��,_� %�=PZ���h    ,   res://.godot/global_script_class_cache.cfg  �Z      �       0,m� k������n    D   res://.godot/imported/icon.svg-218a8f2b3041327d8a5756f3a245f83b.ctex�G      �      �Yz=������������       res://.godot/uid_cache.bin  P_      �       �B}_j���q��.�    $   res://addons/matcha/MatchaPeer.gd          
      A�������O�s��`    $   res://addons/matcha/MatchaRoom.gd   #      �      LK��)��?���@        res://addons/matcha/lib/Utils.gd              ��Odpu����'���    ,   res://addons/matcha/lib/WebSocketClient.gd        =      ���"u1�"�0�6�^��    ,   res://addons/matcha/tracker/TrackerClient.gdP      �
      +j_�0��@�H��N        res://examples/bobble/bobble.gd `>      �      �S;�Ǡ�`�$y�    (   res://examples/bobble/bobble.tscn.remap Z      c       f�!˵[��6m毽    ,   res://examples/bobble/components/player.gd   3      E      $}��9�K^�~�C���    4   res://examples/bobble/components/player.tscn.remap  �Y      c       ͅX�j�Oc6�i�       res://icon.svg  �[      �      C��=U���^Qu��U3       res://icon.svg.import   �T      �       ׶^㉕�N�߳�3��       res://project.binary�_      �      J�Ǿ�Z���@�Y�
       res://root.gd   `U      �       �!%b��V�4�{+�&       res://root.tscn.remap   �Z      a       ;�/q�;X�����=�k                # Generate an random string with a certain length
static func gen_id(len:=20, charset:="0123456789aAbBcCdDeEfFgGhHiIjJkKlLmMnNoOpPqQrRsStTuUvVwWxXyYzZ") -> String:
	var word: String
	var n_char = len(charset)
	for i in range(len):
		word += charset[randi()% n_char]
	return word

# Create an signal for async code
static func create_signal(executor=null) -> Signal:
	var node := Node.new()
	node.add_user_signal("completed")
	var sig := Signal(node, "completed")
	sig.connect(func(_val=null): node.queue_free(), CONNECT_ONE_SHOT)
	if executor != null: executor.call(func (val=null): sig.emit(val))
	return sig

static func string_to_id(string: String) -> int:
	var buffer := string.sha256_buffer()
	var id := 0
	for i in range(buffer.size()):
		id += buffer[i] * i
	return id
        extends RefCounted

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
   extends RefCounted
const Utils := preload("../lib/Utils.gd")
const WebSocketClient := preload("../lib/WebSocketClient.gd")

# Signals
signal connected
signal disconnected
signal reconnecting
signal failure(reason: String)
signal offer(offer: Dictionary)
signal answer(answer: Dictionary)

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
	_socket.connected.connect(self._on_tracker_connected)
	_socket.disconnected.connect(self._on_tracker_disconnected)
	_socket.reconnecting.connect(self._on_tracker_reconnecting)
	_socket.message.connect(self._on_tracker_message)

# Public methods
func send_answer(info_hash: String, answer: Dictionary) -> void:
	if not is_connected:
		connected.connect(send_answer.bind(info_hash, answer), CONNECT_ONE_SHOT)
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
		connected.connect(announce.bind(info_hash, offers), CONNECT_ONE_SHOT)
		return

	var announce_offers := []
	for offer in offers:
		announce_offers.append(offer)

	_socket.send({
		"action": "announce",
		"info_hash": info_hash,
		"peer_id": _options.peer_id,
		"numwant": announce_offers.size(),
		"offers": announce_offers
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
		if "offer" in data:
			offer.emit({
				"info_hash": data.info_hash,
				"peer_id": data.peer_id,
				"offer_id": data.offer_id,
				"sdp": data.offer.sdp
			})
		if "answer" in data:
			answer.emit({
				"info_hash": data.info_hash,
				"peer_id": data.peer_id,
				"offer_id": data.offer_id,
				"sdp": data.answer.sdp
			})
      extends RefCounted

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
	
          class_name MatchaRoom extends RefCounted
const Utils := preload("res://addons/matcha/lib/Utils.gd")
const TrackerClient := preload("./tracker/TrackerClient.gd")
const MatchaPeer := preload("./MatchaPeer.gd")
const POOL_SIZE := 10
const POLL_INTERVAL := 0.1
const OFFER_TIMEOUT := 30

# Members
var _tracker_clients: Array[TrackerClient] = []
var _info_hash: String
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
		var tracker_client := TrackerClient.new({ "tracker_url": tracker_url })
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
	peer.disconnected.connect(func():
		if not offer.peer_id in _peers: return
		_peers.erase(offer.peer_id)
	)
	peer.connecting_failed.connect(func():
		if not offer.peer_id in _peers: return
		_peers.erase(offer.peer_id)
	)
	peer.sdp_created.connect(func(sdp):
		tracker_client.send_answer(_info_hash, {
			"peer_id": offer.peer_id,
			"offer_id": offer.offer_id,
			"sdp": sdp
		})
	)
	# TODO: Find a cleaner way for this whole cleanup step
	unreference()
	unreference()
	unreference()
	peer.create_answer(offer.sdp)
	_peers[offer.peer_id] = peer

func _on_answer(answer: Dictionary, tracker_client: TrackerClient) -> void:
	if not answer.offer_id in _offers: return
	var offer = _offers[answer.offer_id]
	_offers.erase(answer.offer_id)
	
	if answer.peer_id in _peers: return
	_peers[answer.peer_id] = offer.peer
	offer.peer.set_answer(answer.sdp)

func _on_failure(reason: String, tracker_client: TrackerClient) -> void:
	pass
    extends CharacterBody2D

const SPEED = 300.0
var chat_message_time: float

func set_message(message: String) -> void:
	if get_multiplayer_authority() != multiplayer.get_unique_id(): return
	$Label.text = message
	chat_message_time = Time.get_unix_time_from_system()

func _handle_walk():
	var x_dir = Input.get_axis("ui_left", "ui_right")
	var y_dir = Input.get_axis("ui_up", "ui_down")
	
	if x_dir: velocity.x = x_dir * SPEED
	else: velocity.x = move_toward(velocity.x, 0, SPEED)
	
	if y_dir: velocity.y = y_dir * SPEED
	else: velocity.y = move_toward(velocity.y, 0, SPEED)

	move_and_slide()

func _process(_delta):
	if get_multiplayer_authority() != multiplayer.get_unique_id(): return
	_handle_walk()
	if chat_message_time > 0 and Time.get_unix_time_from_system() - chat_message_time > 10:
		chat_message_time = 0
		$Label.text = ""
           RSRC                    PackedScene            ��������                                                  . 	   position 	   velocity    Label    text    resource_local_to_scene    resource_name    custom_solver_bias    size    script    diffuse_texture    normal_texture    specular_texture    specular_color    specular_shininess    texture_filter    texture_repeat    properties/0/path    properties/0/spawn    properties/0/sync    properties/0/watch    properties/1/path    properties/1/spawn    properties/1/sync    properties/1/watch    properties/2/path    properties/2/spawn    properties/2/sync    properties/2/watch 	   _bundled       Script +   res://examples/bobble/components/player.gd ��������      local://RectangleShape2D_368qq �         local://CanvasTexture_8dapy �      %   local://SceneReplicationConfig_j4wkt �         local://PackedScene_es6is �         RectangleShape2D       
     �A  �A	         CanvasTexture    	         SceneReplicationConfig                                                                                                                                    	         PackedScene          	         names "         Player    script    CharacterBody2D    CollisionShape2D    shape 	   Sprite2D    scale    texture    Label    offset_left    offset_top    offset_right    offset_bottom    horizontal_alignment    MultiplayerSynchronizer    replication_config    	   variants    
                       
     �A  �A              ��     PA     �B     C                     node_count             nodes     7   ��������       ����                            ����                           ����                                 ����   	      
                                          ����      	             conn_count              conns               node_paths              editable_instances              version       	      RSRC        extends Node2D

var matcha_room := MatchaRoom.new()
var players = {}

var local_player:
	get: return players[multiplayer.get_unique_id()]

func _ready():
	multiplayer.multiplayer_peer = matcha_room.rtc_peer
	_register(multiplayer.get_unique_id())

	matcha_room.rtc_peer.peer_connected.connect(func(peer_id):
		_register.rpc_id(peer_id, multiplayer.get_unique_id())
	)
	matcha_room.rtc_peer.peer_disconnected.connect(func(peer_id):
		if peer_id in players:
			$Players.remove_child(players[peer_id].node)
	)

@rpc("any_peer", "call_remote")
func _register(real_peer_id: int):
	var peer_id = multiplayer.get_unique_id() if multiplayer.get_remote_sender_id() == 0 else multiplayer.get_remote_sender_id()
	if peer_id in players: return

	var node := preload("res://examples/bobble/components/player.tscn").instantiate()
	var player = {
		"peer_id": peer_id,
		"real_peer_id": real_peer_id,
		"node": node
	}
	node.name = "Player_%s" % real_peer_id
	node.position = Vector2(100, 100)
	players[player.peer_id] = player
	$Players.add_child(node)
	node.set_multiplayer_authority(player.peer_id)

func _on_line_edit_text_submitted(new_text):
	$UI/LineEdit.text = ""
	local_player.node.set_message(new_text)
  RSRC                    PackedScene            ��������                                                  resource_local_to_scene    resource_name 	   _bundled    script       Script     res://examples/bobble/bobble.gd ��������      local://PackedScene_gfak4          PackedScene          	         names "         Bobble    script    Node2D    Players    UI    layout_mode    anchors_preset    offset_left    offset_top    offset_right    offset_bottom    Control 	   LineEdit    placeholder_text    _on_line_edit_text_submitted    text_submitted    	   variants                                   ��    @D     �D    �"D     |B      A    ��D     XB      Type a chat message...       node_count             nodes     6   ��������       ����                            ����                      ����                           	      
                       ����                     	   	   
   
                   conn_count             conns                                      node_paths              editable_instances              version             RSRC            GST2   �   �      ����               � �        �  RIFF�  WEBPVP8L�  /������!"2�H�$�n윦���z�x����դ�<����q����F��Z��?&,
ScI_L �;����In#Y��0�p~��Z��m[��N����R,��#"� )���d��mG�������ڶ�$�ʹ���۶�=���mϬm۶mc�9��z��T��7�m+�}�����v��ح����mow�*��f�&��Cp�ȑD_��ٮ}�)� C+���UE��tlp�V/<p��ҕ�ig���E�W�����Sթ�� ӗ�A~@2�E�G"���~ ��5tQ#�+�@.ݡ�i۳�3�5�l��^c��=�x�Н&rA��a�lN��TgK㼧�)݉J�N���I�9��R���$`��[���=i�QgK�4c��%�*�D#I-�<�)&a��J�� ���d+�-Ֆ
��Ζ���Ut��(Q�h:�K��xZ�-��b��ٞ%+�]�p�yFV�F'����kd�^���:[Z��/��ʡy�����EJo�񷰼s�ɿ�A���N�O��Y��D��8�c)���TZ6�7m�A��\oE�hZ�{YJ�)u\a{W��>�?�]���+T�<o�{dU�`��5�Hf1�ۗ�j�b�2�,%85�G.�A�J�"���i��e)!	�Z؊U�u�X��j�c�_�r�`֩A�O��X5��F+YNL��A��ƩƗp��ױب���>J�[a|	�J��;�ʴb���F�^�PT�s�)+Xe)qL^wS�`�)%��9�x��bZ��y
Y4�F����$G�$�Rz����[���lu�ie)qN��K�<)�:�,�=�ۼ�R����x��5�'+X�OV�<���F[�g=w[-�A�����v����$+��Ҳ�i����*���	�e͙�Y���:5FM{6�����d)锵Z�*ʹ�v�U+�9�\���������P�e-��Eb)j�y��RwJ�6��Mrd\�pyYJ���t�mMO�'a8�R4��̍ﾒX��R�Vsb|q�id)	�ݛ��GR��$p�����Y��$r�J��^hi�̃�ūu'2+��s�rp�&��U��Pf��+�7�:w��|��EUe�`����$G�C�q�ō&1ŎG�s� Dq�Q�{�p��x���|��S%��<
\�n���9�X�_�y���6]���մ�Ŝt�q�<�RW����A �y��ػ����������p�7�l���?�:������*.ո;i��5�	 Ύ�ș`D*�JZA����V^���%�~������1�#�a'a*�;Qa�y�b��[��'[�"a���H�$��4� ���	j�ô7�xS�@�W�@ ��DF"���X����4g��'4��F�@ ����ܿ� ���e�~�U�T#�x��)vr#�Q��?���2��]i�{8>9^[�� �4�2{�F'&����|���|�.�?��Ȩ"�� 3Tp��93/Dp>ϙ�@�B�\���E��#��YA 7 `�2"���%�c�YM: ��S���"�+ P�9=+D�%�i �3� �G�vs�D ?&"� !�3nEФ��?Q��@D �Z4�]�~D �������6�	q�\.[[7����!��P�=��J��H�*]_��q�s��s��V�=w�� ��9wr��(Z����)'�IH����t�'0��y�luG�9@��UDV�W ��0ݙe)i e��.�� ����<����	�}m֛�������L ,6�  �x����~Tg����&c�U��` ���iڛu����<���?" �-��s[�!}����W�_�J���f����+^*����n�;�SSyp��c��6��e�G���;3Z�A�3�t��i�9b�Pg�����^����t����x��)O��Q�My95�G���;w9�n��$�z[������<w�#�)+��"������" U~}����O��[��|��]q;�lzt�;��Ȱ:��7�������E��*��oh�z���N<_�>���>>��|O�׷_L��/������զ9̳���{���z~����Ŀ?� �.݌��?�N����|��ZgO�o�����9��!�
Ƽ�}S߫˓���:����q�;i��i�]�t� G��Q0�_î!�w��?-��0_�|��nk�S�0l�>=]�e9�G��v��J[=Y9b�3�mE�X�X�-A��fV�2K�jS0"��2!��7��؀�3���3�\�+2�Z`��T	�hI-��N�2���A��M�@�jl����	���5�a�Y�6-o���������x}�}t��Zgs>1)���mQ?����vbZR����m���C��C�{�3o��=}b"/�|���o��?_^�_�+��,���5�U��� 4��]>	@Cl5���w��_$�c��V��sr*5 5��I��9��
�hJV�!�jk�A�=ٞ7���9<T�gť�o�٣����������l��Y�:���}�G�R}Ο����������r!Nϊ�C�;m7�dg����Ez���S%��8��)2Kͪ�6̰�5�/Ӥ�ag�1���,9Pu�]o�Q��{��;�J?<�Yo^_��~��.�>�����]����>߿Y�_�,�U_��o�~��[?n�=��Wg����>���������}y��N�m	n���Kro�䨯rJ���.u�e���-K��䐖��Y�['��N��p������r�Εܪ�x]���j1=^�wʩ4�,���!�&;ج��j�e��EcL���b�_��E�ϕ�u�$�Y��Lj��*���٢Z�y�F��m�p�
�Rw�����,Y�/q��h�M!���,V� �g��Y�J��
.��e�h#�m�d���Y�h�������k�c�q��ǷN��6�z���kD�6�L;�N\���Y�����
�O�ʨ1*]a�SN�=	fH�JN�9%'�S<C:��:`�s��~��jKEU�#i����$�K�TQD���G0H�=�� �d�-Q�H�4�5��L�r?����}��B+��,Q�yO�H�jD�4d�����0*�]�	~�ӎ�.�"����%
��d$"5zxA:�U��H���H%jس{���kW��)�	8J��v�}�rK�F�@�t)FXu����G'.X�8�KH;���[          [remap]

importer="texture"
type="CompressedTexture2D"
uid="uid://citg1d4ms6pyp"
path="res://.godot/imported/icon.svg-218a8f2b3041327d8a5756f3a245f83b.ctex"
metadata={
"vram_texture": false
}
                extends Node2D

func _on_bobble_btn_pressed():
	get_parent().add_child(load("res://examples/bobble/bobble.tscn").instantiate())
	get_parent().remove_child(self)
               RSRC                    PackedScene            ��������                                                  resource_local_to_scene    resource_name 	   _bundled    script       Script    res://root.gd ��������      local://PackedScene_vl7kb          PackedScene          	         names "         root    script    Node2D    bobble_btn    offset_left    offset_top    offset_right    offset_bottom    text    Button    _on_bobble_btn_pressed    pressed    	   variants                      �C     PC     D     oC      Start bobble       node_count             nodes        ��������       ����                      	      ����                                           conn_count             conns                  
                    node_paths              editable_instances              version             RSRC        [remap]

path="res://.godot/exported/133200997/export-bab7f66da158eb92d4a519c9e5bf8439-player.scn"
             [remap]

path="res://.godot/exported/133200997/export-61e474ebecd96a8a7bfc183b8acbdb18-bobble.scn"
             [remap]

path="res://.godot/exported/133200997/export-6581cd44ca730c421bddc3302d6ce6cc-root.scn"
               list=Array[Dictionary]([{
"base": &"RefCounted",
"class": &"MatchaRoom",
"icon": "",
"language": &"GDScript",
"path": "res://addons/matcha/MatchaRoom.gd"
}])
  <svg height="128" width="128" xmlns="http://www.w3.org/2000/svg"><rect x="2" y="2" width="124" height="124" rx="14" fill="#363d52" stroke="#212532" stroke-width="4"/><g transform="scale(.101) translate(122 122)"><g fill="#fff"><path d="M105 673v33q407 354 814 0v-33z"/><path fill="#478cbf" d="m105 673 152 14q12 1 15 14l4 67 132 10 8-61q2-11 15-15h162q13 4 15 15l8 61 132-10 4-67q3-13 15-14l152-14V427q30-39 56-81-35-59-83-108-43 20-82 47-40-37-88-64 7-51 8-102-59-28-123-42-26 43-46 89-49-7-98 0-20-46-46-89-64 14-123 42 1 51 8 102-48 27-88 64-39-27-82-47-48 49-83 108 26 42 56 81zm0 33v39c0 276 813 276 813 0v-39l-134 12-5 69q-2 10-14 13l-162 11q-12 0-16-11l-10-65H447l-10 65q-4 11-16 11l-162-11q-12-3-14-13l-5-69z"/><path d="M483 600c3 34 55 34 58 0v-86c-3-34-55-34-58 0z"/><circle cx="725" cy="526" r="90"/><circle cx="299" cy="526" r="90"/></g><g fill="#414042"><circle cx="307" cy="532" r="60"/><circle cx="717" cy="532" r="60"/></g></g></svg>
             �$��)T&,   res://examples/bobble/components/player.tscnCx�@Lr!   res://examples/bobble/bobble.tscns�4�\��*   res://root.tscn��� <�J   res://icon.svg  ECFG      application/config/name         matcha     application/run/main_scene         res://root.tscn    application/config/features(   "         4.1    GL Compatibility       application/config/icon         res://icon.svg  "   display/window/size/viewport_width      �  #   display/window/size/viewport_height            display/window/stretch/mode         viewport   display/window/stretch/aspect      
   keep_width  #   rendering/renderer/rendering_method         gl_compatibility*   rendering/renderer/rendering_method.mobile         gl_compatibility4   rendering/textures/vram_compression/import_etc2_astc                    