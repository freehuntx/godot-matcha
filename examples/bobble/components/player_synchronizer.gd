extends MultiplayerSynchronizer

func _init():
	visibility_update_mode = MultiplayerSynchronizer.VISIBILITY_PROCESS_NONE

func _ready():
	visibility_update_mode = MultiplayerSynchronizer.VISIBILITY_PROCESS_NONE

func _enter_tree():
	pass
	#visibility_update_mode = MultiplayerSynchronizer.VISIBILITY_PROCESS_IDLE

func _exit_tree():
	pass
	#visibility_update_mode = MultiplayerSynchronizer.VISIBILITY_PROCESS_NONE
