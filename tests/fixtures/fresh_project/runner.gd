extends SceneTree

var dependency: FreshBase

func _initialize() -> void:
	dependency = FreshBase.new()
	quit(0 if dependency != null else 1)
