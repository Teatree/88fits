## One-thumb input: a floating virtual joystick, the scheme every portrait survivor game uses (Archero,
## Survivor.io, Vampire Survivors mobile). Touch anywhere below the HUD band: the stick appears under the thumb,
## dragging sets the move direction and throttle, the base trails a long drag so it never runs away, lifting stops.
## On PC the WASD / arrow actions (project.godot, Input Map) do the same job.
## Exposes: wants_move, stick_dir (screen-space, length 0..1), origin (stick base, for the HUD), radius_px(), keyboard.
class_name PlayerInput
extends Node

signal touch_started(screen_pos: Vector2)
signal touch_ended

const DEADZONE_PX := 6.0
## Full deflection distance at the 432 px reference width (scaled by the viewport and the stick size setting).
const STICK_FULL_PX := 60.0

var wants_move := false
var stick_dir := Vector2.ZERO
var touch_pos := Vector2.ZERO
var origin := Vector2.ZERO
var active_index := -1
var lifted_once := false
var enabled := true
var ui_blocking := false
## True while WASD / the arrow keys drive the hero (PC only; phones never set it).
var keyboard := false


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or ui_blocking:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if active_index == -1 and _in_thumb_zone(event.position):
				active_index = event.index
				origin = event.position
				touch_pos = event.position
				wants_move = true
				touch_started.emit(event.position)
		else:
			if event.index == active_index:
				_release()
	elif event is InputEventScreenDrag:
		if event.index == active_index:
			touch_pos = event.position


func _release() -> void:
	active_index = -1
	wants_move = false
	stick_dir = Vector2.ZERO
	lifted_once = true
	touch_ended.emit()


func force_release() -> void:
	if active_index != -1:
		_release()


func _in_thumb_zone(p: Vector2) -> bool:
	var vp := get_viewport().get_visible_rect().size
	if vp.y <= 0.0:
		return true
	# below the HUD's strip (the top row and the item slots), scaled with the canvas width
	return p.y > HUD.band_h * vp.x / 1080.0


## Full-deflection radius in screen pixels.
func radius_px() -> float:
	var vp := get_viewport().get_visible_rect().size
	var px_scale: float = vp.x / 432.0 if vp.x > 0.0 else 1.0
	return STICK_FULL_PX * px_scale * float(Settings.stick_size)


func _process(_delta: float) -> void:
	# pass 114 (lane REPLAY): a replay sets the stick itself at each frame's start (RunReplay)
	if Lockstep.replaying:
		return
	# PC: WASD or the arrows move the hero like a full stick push, whenever no finger is on the screen
	if active_index == -1 and enabled and not ui_blocking:
		var kv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if kv.length() > 0.1:
			keyboard = true
			wants_move = true
			stick_dir = kv.limit_length(1.0)
			return
		elif keyboard:
			keyboard = false
			wants_move = false
			stick_dir = Vector2.ZERO
			lifted_once = true
			touch_ended.emit()
	if not wants_move:
		return
	var r := radius_px()
	var vp := get_viewport().get_visible_rect().size
	var px_scale: float = vp.x / 432.0 if vp.x > 0.0 else 1.0
	var v := touch_pos - origin
	if v.length() < DEADZONE_PX * px_scale:
		stick_dir = Vector2.ZERO
	else:
		stick_dir = (v / r).limit_length(1.0)
	# the base follows a long drag, so a thumb that wandered still steers from where it is
	if v.length() > r:
		origin = touch_pos - v.normalized() * r
