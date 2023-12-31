extends MultiplayerSynchronizer

func _init():
	visibility_update_mode = MultiplayerSynchronizer.VISIBILITY_PROCESS_NONE

func _enter_tree():
	visibility_update_mode = MultiplayerSynchronizer.VISIBILITY_PROCESS_IDLE

func _exit_tree():
	visibility_update_mode = MultiplayerSynchronizer.VISIBILITY_PROCESS_NONE
