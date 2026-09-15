## A tappable panel that sizes itself to its content, so icons and text can never hang outside it (a Button
## with an anchored HBox inside could). Handles touch and mouse (one is emulated from the other on PC), fires
## `pressed` once per tap, squashes while held, and gives the tap up when the list it lives in starts scrolling.
class_name TapCard
extends PanelContainer

signal pressed

## A finger may wander this far (design px) between press and release and still count as a tap.
const SLOP := 40.0

var _down := false
var _from := Vector2.ZERO


func _ready() -> void:
	# PASS, not STOP: the ScrollContainer above still sees the same drag and can scroll
	mouse_filter = Control.MOUSE_FILTER_PASS


func _gui_input(e: InputEvent) -> void:
	var is_press := false
	var is_release := false
	var pos := Vector2.ZERO
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		is_press = t.pressed
		is_release = not t.pressed
		pos = t.position
	elif e is InputEventMouseButton:
		var m := e as InputEventMouseButton
		if m.button_index != MOUSE_BUTTON_LEFT:
			return
		is_press = m.pressed
		is_release = not m.pressed
		pos = m.position
	else:
		return
	if is_press and not _down:
		_down = true
		_from = pos
		pivot_offset = size * 0.5
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector2(0.97, 0.97), 0.06).set_trans(Tween.TRANS_SINE)
	elif is_release and _down:
		_down = false
		_up()
		if pos.distance_to(_from) <= SLOP:
			pressed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_SCROLL_BEGIN and _down:
		_down = false
		_up()


func _up() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
