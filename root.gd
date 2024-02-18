extends Node2D
const MQTTPacket := preload("res://addons/matcha/mqtt/packet.gd")

func _ready():
	var foo := ("%s" % randi()).sha256_text().substr(0, 20) + "000000000000000000000000000000000000000000000000000000000000000000000000"
	print(foo.is_valid_hex_number())

func _on_bobble_btn_pressed():
	get_parent().add_child(load("res://examples/bobble/bobble.tscn").instantiate())
	get_parent().remove_child(self)

func _on_lobby_btn_pressed():
	get_parent().add_child(load("res://examples/lobby/lobby.tscn").instantiate())
	get_parent().remove_child(self)

func _on_server_client_btn_pressed():
	get_parent().add_child(load("res://examples/server_client/server_client.tscn").instantiate())
	get_parent().remove_child(self)


func _on_spam_btn_pressed():
	for i in 20:
		get_parent().add_child(load("res://examples/bobble/bobble.tscn").instantiate())
