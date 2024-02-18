extends RefCounted
const MQTTClient := preload("./client.gd")

const DEFAULT_BROKER_URLS = [
	"wss://mqtt.eclipseprojects.io/mqtt",
	"wss://mqtt-dashboard.com:8884/mqtt",
	"wss://broker.hivemq.com:8884/mqtt"
]
enum State { NEW, CLOSED, CONNECTING, CONNECTED }

## Signals
signal connecting
signal connected
signal closed
signal connect_failed
signal message(client_id: String, message: String, pub_key: String, private: bool)

## Members
var _state := State.NEW
var _client_id: String
var _room_id: String
var _room_topic: String
var _crypto := Crypto.new()
var _key: CryptoKey
var _pub_key: String
var _broker_urls := []
var _mqtt_clients: Array[MQTTClient] = []
var _message_ids := {}

var is_connected: bool:
	get: return _state == State.CONNECTED
var client_id: String:
	get: return _client_id
var key: CryptoKey:
	get: return _key

func _init(options:={}):
	_broker_urls = options.broker_urls if "broker_urls" in options else DEFAULT_BROKER_URLS
	_key = options.key if "key" in options else _crypto.generate_rsa(512)

	_pub_key = _key.save_to_string(true)
	_client_id = _pub_key.sha256_text().substr(0, 20)

## Public methods
func join(room_id: String, exit_message:="") -> Error:
	if _state > State.CLOSED:
		push_error("Room already in use")
		return ERR_ALREADY_IN_USE

	var room_topic := "godot/mqtt_messenger/%s" % room_id

	for broker_url in _broker_urls:
		var mqtt_client := MQTTClient.new({ timeout=5, client_id=_client_id })
		mqtt_client.connected.connect(self._on_mqtt_client_connected.bind(mqtt_client))
		mqtt_client.closed.connect(self._on_mqtt_client_closed.bind(mqtt_client))
		mqtt_client.subscribed.connect(self._on_mqtt_client_subscribed.bind(mqtt_client))
		mqtt_client.message.connect(self._on_mqtt_client_message.bind(mqtt_client))

		if exit_message != "":
			mqtt_client.set_forceful_close(true)
			mqtt_client.set_last_will(room_topic, JSON.stringify(_create_packet(exit_message)))

		if mqtt_client.connect_to_server(broker_url) == OK:
			_mqtt_clients.append(mqtt_client)

	if _mqtt_clients.size() == 0:
		push_error("Failed connecting to room")
		return ERR_CANT_CONNECT

	_room_id = room_id
	_room_topic = room_topic
	_state = State.CONNECTING
	connecting.emit()

	return OK

func leave() -> Error:
	if _state < State.CONNECTING:
		push_error("Not connected to room")
		return ERR_CONNECTION_ERROR

	for mqtt_client in _mqtt_clients.duplicate():
		mqtt_client.close()

	return OK

func send_message(message: String, wait_for_connect:=false) -> Error:
	var packet := _create_packet(message)
	var err := ERR_QUERY_FAILED

	for mqtt_client in _mqtt_clients:
		if mqtt_client.publish(_room_topic, JSON.stringify(packet), false, 0, wait_for_connect) == OK:
			err = OK

	return err

func send_message_to(message: String, target_pub_key: String, wait_for_connect:=false) -> Error:
	var id := ("%s" % randi()).sha256_text().substr(0, 20)
	# TODO: Implement encryption of data so others done see the content
	var sig := _crypto.sign(HashingContext.HASH_MD5, (id + message).md5_buffer(), _key)
	var packet := {
		"id": id,
		"pub": Marshalls.utf8_to_base64(_pub_key),
		"target": Marshalls.utf8_to_base64(target_pub_key),
		"data": message,
		"sig": Marshalls.raw_to_base64(sig)
	}
	var err := ERR_QUERY_FAILED
	for mqtt_client in _mqtt_clients:
		if mqtt_client.publish(_room_topic, JSON.stringify(packet), false, 0, wait_for_connect) == OK:
			err = OK

	return err

## Private methods
func _is_all_clients_connected() -> bool:
	return _mqtt_clients.reduce(func(accum, client: MQTTClient): return accum and client.is_connected, true)

func _create_packet(message: String) -> Dictionary:
	var id := ("%s" % randi()).sha256_text().substr(0, 20)
	var sig := _crypto.sign(HashingContext.HASH_MD5, (id + message).md5_buffer(), _key)
	return {
		"id": id,
		"pub": Marshalls.utf8_to_base64(_pub_key),
		"data": message,
		"sig": Marshalls.raw_to_base64(sig)
	}

## Callbacks
func _on_mqtt_client_connected(mqtt_client: MQTTClient) -> void:
	mqtt_client.subscribe(_room_topic)

func _on_mqtt_client_closed(mqtt_client: MQTTClient) -> void:
	_mqtt_clients.erase(mqtt_client)

	if _mqtt_clients.size() == 0:
		if _state == State.CONNECTING:
			_state = State.CLOSED
			connect_failed.emit()
		elif _state == State.CONNECTED:
			_state = State.CLOSED
			closed.emit()
	elif _state == State.CONNECTING and _is_all_clients_connected():
		_state = State.CONNECTED
		connected.emit()

func _on_mqtt_client_subscribed(mqtt_client: MQTTClient) -> void:
	if _state == State.CONNECTING and _is_all_clients_connected():
		_state = State.CONNECTED
		connected.emit()

func _on_mqtt_client_message(topic: String, msg_buffer: PackedByteArray, mqtt_client: MQTTClient) -> void:
	if _state != State.CONNECTED:
		return

	var packet := JSON.parse_string(msg_buffer.get_string_from_utf8())

	if typeof(packet) != TYPE_DICTIONARY:
		return
	for required_key in ["id", "pub", "data", "sig"]:
		if not required_key in packet:
			return

	var pub_key := Marshalls.base64_to_utf8(packet.pub)
	var client_id := pub_key.sha256_text().substr(0, 20)

	if client_id == _client_id:
		return
	if packet.id in _message_ids:
		return # We got this message already

	var packet_sig := Marshalls.base64_to_raw(packet.sig)
	var crypto_key := CryptoKey.new() # TODO: Cache?
	crypto_key.load_from_string(pub_key, true)

	if not _crypto.verify(HashingContext.HASH_MD5, (packet.id + packet.data).md5_buffer(), Marshalls.base64_to_raw(packet.sig), crypto_key):
		return

	var private: bool = "target" in packet
	if private:
		var target_pub_key := Marshalls.base64_to_utf8(packet.target)
		var target_client_id := target_pub_key.sha256_text().substr(0, 20)
		if target_client_id != _client_id:
			return # I was not meant
		# TODO: Implement decryption to hide data
		#packet.data = _crypto.decrypt(_key, Marshalls.base64_to_raw(packet.data)).get_string_from_utf8()

	_message_ids[packet.id] = true
	message.emit(client_id, packet.data, pub_key, private)

	# Remove the message id after 5 seconds (To prevent memory leak)
	await Engine.get_main_loop().create_timer(5).timeout
	_message_ids.erase(packet.id)
