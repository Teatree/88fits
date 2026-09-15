@tool
extends EditorPlugin

var _dock: Control


func _enter_tree() -> void:
	_dock = preload("res://addons/content_dock/ContentDock.gd").new()
	_dock.name = "Content"
	_dock.plugin = self
	add_control_to_dock(DOCK_SLOT_LEFT_BR, _dock)


func _exit_tree() -> void:
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
