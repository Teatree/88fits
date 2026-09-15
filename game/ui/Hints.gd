## First-play hints from design bible section 11. Each appears once, is skippable, and is remembered.
class_name Hints
extends Control

var game: Node
var _label: Label
var _step := ""
var _t := 0.0
var _pause_toast_done := false
var _panel: PanelContainer


func _ready() -> void:
	UiKit.fullscreen(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = UiKit.panel(Color(0, 0, 0, 0.55), 30, UiKit.ACCENT, 3)
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.offset_left = -440
	_panel.offset_right = 440
	_panel.offset_top = -560
	_panel.offset_bottom = -420
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = UiKit.label("", 40, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)
	_panel.visible = false
	add_child(_panel)


func begin() -> void:
	if not Settings.show_hints or game == null:
		return
	if not Save.hint_seen("hold"):
		_show("hold", "TOUCH and DRAG anywhere below to move")
		game.player.moved_first.connect(func(): _done("hold"), CONNECT_ONE_SHOT)
	game.player.input.touch_ended.connect(_on_release)


func _on_release() -> void:
	pass


func _show(step: String, text: String) -> void:
	_step = step
	_label.text = text
	_panel.visible = true
	_panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_panel, "modulate:a", 1.0, 0.3)


func _done(step: String) -> void:
	if _step != step:
		return
	Save.mark_hint(step)
	_panel.visible = false
	_step = ""
	match step:
		"hold":
			if not Save.hint_seen("slide"):
				_show("slide", "Drag in any direction. Lift to stop.")
		"slide":
			if not Save.hint_seen("gems"):
				_show("gems", "Walk over GEMS to level up")


func tick(delta: float) -> void:
	if game == null or not Settings.show_hints:
		return
	_t += delta
	match _step:
		"slide":
			if Run.kills >= 1 and _t > 4.0:
				_done("slide")
		"gems":
			if Run.xp > 0.0 or Run.level > 1:
				_done("gems")
		"":
			if not _pause_toast_done and Run.elapsed >= 90.0 and not Save.hint_seen("pause"):
				_pause_toast_done = true
				Save.mark_hint("pause")
				game.toast("Tap the top bar any time to pause and see your build", UiKit.INK2)
	# steering hint completes once the player has pushed the stick properly for a moment
	if _step == "slide" and game.player.input.wants_move and game.player.input.stick_dir.length() > 0.6 and _t > 2.0:
		_done("slide")
