## A slider a finger can move (pass 37). The phone sends raw touch with no mouse events behind it (project.godot keeps
## emulate_mouse_from_touch off), and Godot's Slider only listens to the mouse, so on the phone the volume sliders never
## moved. The first few pixels decide what a finger means, as phones do: sideways, it takes the knob and carries it (the
## finger is then held, `holds`, so the screen's TouchScroll does not move the page under it); up or down, it lets go and
## the page scrolls; a tap without moving puts the knob where it landed. The mouse still works on a PC.
class_name TouchSlider
extends HSlider

## How far a finger moves before its way is read (less than TouchScroll.SLOP, so the slider has decided before the page
## would start to scroll).
const DECIDE := 10.0

## Touch indices a slider has taken: TouchScroll leaves those fingers alone.
static var _held: Dictionary = {}

var _finger := -1
var _from := Vector2.ZERO
var _taking := false


static func holds(index: int) -> bool:
	return _held.has(index)


func _gui_input(e: InputEvent) -> void:
	if not editable:
		return
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.pressed and _finger < 0:
			_finger = t.index
			_from = t.position
			_taking = false
			accept_event()
		elif not t.pressed and t.index == _finger:
			# a drag it took ends where the finger lifts; a tap puts the knob there
			if _taking or t.position.distance_to(_from) < DECIDE:
				_follow(t.position)
			_let_go()
			accept_event()
	elif e is InputEventScreenDrag:
		var d := e as InputEventScreenDrag
		if d.index != _finger:
			return
		if not _taking:
			var mv := d.position - _from
			if mv.length() < DECIDE:
				return
			if absf(mv.x) < absf(mv.y):
				# up or down: a scroll, not a slide
				_finger = -1
				return
			_taking = true
			_held[_finger] = true
		_follow(d.position)
		accept_event()


## The knob's middle under `local.x`: its travel is the track less half a knob at each end, as the Slider draws it.
func _follow(local: Vector2) -> void:
	var knob := 0.0
	var tex := get_theme_icon("grabber")
	if tex:
		knob = float(tex.get_width())
	var travel := maxf(size.x - knob, 1.0)
	var f := clampf((local.x - knob * 0.5) / travel, 0.0, 1.0)
	value = min_value + f * (max_value - min_value)


func _let_go() -> void:
	_held.erase(_finger)
	_finger = -1
	_taking = false


func _notification(what: int) -> void:
	# hidden or gone mid-drag: the finger is not held any more
	if (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()) or what == NOTIFICATION_EXIT_TREE:
		if _finger >= 0:
			_let_go()
