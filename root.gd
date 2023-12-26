extends Node2D

func _on_bobble_btn_pressed():
	get_parent().add_child(load("res://examples/bobble/bobble.tscn").instantiate())
	get_parent().remove_child(self)

func _on_lobby_btn_pressed():
	get_parent().add_child(load("res://examples/lobby/lobby.tscn").instantiate())
	get_parent().remove_child(self)
