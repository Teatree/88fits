## A tappable piece of the kit (buttons, cards, rows, choices). Raw touch and the mouse both work; a tap is a press and
## a release within SLOP of each other; the list it sits in taking the drag (NOTIFICATION_SCROLL_BEGIN) cancels it.
## Pressed, it sits on its shadow (the HardBox moves by the shadow offset, content with it, in 60 ms; back in 90 ms),
## a primary darkens to brass dark, and a card shows its brass inner outline. Locked pieces show aged at 45 % and still
## emit `pressed`, so the screen can say why (a spent Reroll, a price that is 8 short). Pass 122, under Royale: a locked
## piece is the grey role on the box's own base (HardBox.copy keeps its border, shadow and corners) at 75 %.
class_name WTap
extends PanelContainer

signal pressed

const SLOP := 40.0

var box: HardBox:
	set(v):
		box = v
		_restyle()
## The box while held (made from `box` when left null).
var box_down: HardBox
var locked := false:
	set(v):
		locked = v
		_restyle()
## The look while locked: aged fill, no shadow, the whole piece at this opacity.
var locked_alpha := 0.45

var _down := false
var _from := Vector2.ZERO
var _held_look := false


func _ready() -> void:
	# PASS: a scroll list above still sees the drag and can take it
	mouse_filter = Control.MOUSE_FILTER_PASS
	_restyle()


func _restyle() -> void:
	if box == null:
		return
	var b: HardBox = box
	if locked:
		# pass 122 (lane UIKIT_A): the locked face is the grey role on its base (the kit sheet's LOCKED), at 75 %;
		# copy() carries the box's border, shadow, radius and corners (duplicate() keeps no HardBox field)
		b = box.copy()
		b.role = "locked"
		b.inner = 0
	elif _held_look:
		b = box_down if box_down else box.pressed()
	add_theme_stylebox_override("panel", b)
	var a := locked_alpha
	if locked and is_equal_approx(a, 0.45):
		a = R.LOCKED_ALPHA
	modulate.a = a if locked else 1.0


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
		_set_held(true)
	elif is_release and _down:
		_down = false
		_set_held(false)
		if pos.distance_to(_from) <= SLOP:
			W.sfx("ui_tap")
			pressed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_SCROLL_BEGIN and _down:
		_down = false
		_set_held(false)
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree() and _down:
		_down = false
		_set_held(false)


func _set_held(on: bool) -> void:
	if locked:
		return
	_held_look = on
	_restyle()


## Show the held look without a finger (the mock's "pressed" state, and the capture tool).
func show_held(on: bool) -> void:
	_held_look = on
	_restyle()
