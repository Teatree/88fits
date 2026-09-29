## The switch: 140 x 80 outside (130 x 70 inside a 5 px ink border), brass when on (the knob right), aged when off (the knob left); the knob
## is a 50 px paper square with its own 5 px border.
class_name WSwitch
extends Control

signal toggled(on: bool)

var on := false:
	set(v):
		on = v
		queue_redraw()
var _down := false
var _from := Vector2.ZERO


func _init() -> void:
	custom_minimum_size = Vector2(140, 80)
	size_flags_horizontal = Control.SIZE_SHRINK_END
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_PASS


static func make(p_on: bool) -> WSwitch:
	var s := WSwitch.new()
	s.on = p_on
	return s


func _gui_input(e: InputEvent) -> void:
	var press := false
	var release := false
	var pos := Vector2.ZERO
	if e is InputEventScreenTouch:
		press = (e as InputEventScreenTouch).pressed
		release = not press
		pos = (e as InputEventScreenTouch).position
	elif e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		press = (e as InputEventMouseButton).pressed
		release = not press
		pos = (e as InputEventMouseButton).position
	else:
		return
	if press:
		_down = true
		_from = pos
	elif release and _down:
		_down = false
		if pos.distance_to(_from) <= WTap.SLOP:
			on = not on
			W.sfx("ui_tap")
			toggled.emit(on)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SCROLL_BEGIN:
		_down = false


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, custom_minimum_size)
	draw_rect(r, W.INK)
	draw_rect(r.grow(-5.0), W.BRASS if on else W.AGED)
	# the knob sits 5 px inside the 5 px border (the mock's right:5px / left:5px on the padding box)
	var k := Rect2(Vector2(r.size.x - 10.0 - 50.0 if on else 10.0, 10.0), Vector2(50, 50))
	draw_rect(k, W.INK)
	draw_rect(k.grow(-5.0), W.PAPER)
