## Extract (bank gold at ×1.25) or continue to a harder stage. Two thumb-sized buttons.
class_name PortalDialog
extends Control

signal decided(extract: bool)

var _title: Label
var _body: Label
var _continue: Button
var _extract: Button
var _box: VBoxContainer


func _ready() -> void:
	UiKit.fullscreen(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_child(UiKit.dim(0.85))
	_box = UiKit.vbox(24)
	var v := _box
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.offset_left = -460
	v.offset_right = 460
	v.offset_top = -380
	v.offset_bottom = 380
	add_child(v)
	_title = UiKit.label("PORTAL", 84, UiKit.GOOD, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_title)
	_body = UiKit.label("", 32, UiKit.INK2, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_body)
	v.add_child(UiKit.spacer(20))
	_extract = UiKit.button("Extract", 44, true, 130)
	_extract.pressed.connect(func(): visible = false; decided.emit(true))
	v.add_child(_extract)
	_continue = UiKit.button("Continue", 44, false, 130)
	_continue.pressed.connect(func(): visible = false; decided.emit(false))
	v.add_child(_continue)


func open(stage_cleared: int, can_continue: bool, final_stage: bool) -> void:
	var gold := Run.run_gold
	_title.text = "STAGE %d CLEAR" % stage_cleared
	var lines: Array = ["Extract now: bank %d gold (×1.25 = %d)." % [gold, int(round(gold * 1.25))]]
	if can_continue:
		lines.append("Continue: %s, gold stays at ×1.0 until you extract or die." % ("endless mode, harder every minute" if final_stage else "stage %d, harder waves" % (stage_cleared + 1)))
	else:
		lines.append("Endless mode is locked. Kill the stage 3 boss to unlock it.")
	_body.text = "\n".join(lines)
	_continue.visible = can_continue
	_continue.text = "Continue to endless" if final_stage else "Continue to stage %d" % (stage_cleared + 1)
	visible = true
	UiFx.enter(self)
	UiFx.pop(_box, 0.05, 0.8, 0.36)
