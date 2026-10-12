## Finger scrolling for a ScrollContainer, one helper for every screen (pass 37; by hand since pass 25). The phone sends
## raw touch with no mouse events (project.godot keeps emulate_mouse_from_touch off) and a ScrollContainer never saw a
## drag that started on a control inside it, so the owner feeds its `_input` here and the list's scroll_vertical is moved
## from the ScreenDrag events, with a fling that coasts after the finger lifts. Past SLOP the list is told it is
## scrolling (NOTIFICATION_SCROLL_BEGIN): that takes the tap back from the button or card the finger came down on, which
## otherwise fired on release (a swipe down the Mirror bought talents). A finger a slider holds is left alone.
class_name TouchScroll
extends RefCounted

const SLOP := 22.0

var scroll: ScrollContainer
## Only a finger that comes down on the list moves it (else any finger anywhere on the screen does).
var only_inside := false
## How much of the fling is left each frame.
var decay := 0.93
## Pass 69 (the title's hero drawer): the list moves sideways, scroll_horizontal from the drag's x.
var horizontal := false
var _id := -1
var _moved := 0.0
var _scrolling := false
var _fling := 0.0


func _init(p_scroll: ScrollContainer, p_only_inside := false, p_decay := 0.93) -> void:
	scroll = p_scroll
	only_inside = p_only_inside
	decay = p_decay


func input(event: InputEvent) -> void:
	if scroll == null or not is_instance_valid(scroll) or not scroll.is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _id < 0:
			if only_inside and not scroll.get_global_rect().has_point(t.position):
				return
			_id = t.index
			_moved = 0.0
			_scrolling = false
			_fling = 0.0
		elif not t.pressed and t.index == _id:
			_id = -1
			if _scrolling:
				_scrolling = false
				scroll.propagate_notification(Control.NOTIFICATION_SCROLL_END)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index != _id or TouchSlider.holds(d.index):
			return
		if not _scrolling:
			_moved += d.relative.length()
			if _moved < SLOP:
				return
			_scrolling = true
			scroll.propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
		if horizontal:
			scroll.scroll_horizontal -= int(round(d.relative.x))
			_fling = d.relative.x
			return
		scroll.scroll_vertical -= int(round(d.relative.y))
		_fling = d.relative.y


func process() -> void:
	if scroll == null or not is_instance_valid(scroll) or not scroll.is_visible_in_tree():
		return
	if _id < 0 and absf(_fling) > 0.4:
		if horizontal:
			scroll.scroll_horizontal -= int(round(_fling))
		else:
			scroll.scroll_vertical -= int(round(_fling))
		_fling *= decay


## Drop the finger (the owner closed): no half gesture carries into the next time it opens.
func reset() -> void:
	if _scrolling and scroll and is_instance_valid(scroll):
		scroll.propagate_notification(Control.NOTIFICATION_SCROLL_END)
	_id = -1
	_scrolling = false
	_fling = 0.0
