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
## Pass 136 (lane GUNS): the dead zone's cap under the aim rule, a share of the stick's reach.
const AIM_DEADZONE := 0.05

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
## Pass 119 (the lead; Garry: "when I return from the level up screen I often end up loosing a bit of momentum because of
## a tiny delay between the tap being registered and the move actually starting"): a fresh touch starts the stick at
## rest, so after TAP TO GO the hero crept until the thumb had dragged half the stick's reach (about 80 px on a phone).
## Now the stick a pause took away (force_release) is carried: the first touch that starts the stick within
## CARRY_WINDOW s of the run going on starts it pushed as it was (the same way, the same throttle), and the thumb's own
## drag takes over as it grows: the carried push fades out over CARRY_FADE of the stick's reach. A lift drops it.
const CARRY_WINDOW := 1.0
const CARRY_FADE := 0.6
var carry := Vector2.ZERO
var _carry_ready := Vector2.ZERO
var _resumed_ms := -100000


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
				# pass 119: the push the pause took away, if this is the first touch since the run went on
				if _carry_ready.length() > 0.05 and Time.get_ticks_msec() - _resumed_ms <= int(CARRY_WINDOW * 1000.0):
					carry = _carry_ready
				_carry_ready = Vector2.ZERO
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
	carry = Vector2.ZERO
	lifted_once = true
	touch_ended.emit()


func force_release() -> void:
	if active_index != -1:
		# pass 119: the push it had, carried to the first touch after the pause (CARRY_WINDOW)
		var had := stick_dir
		_release()
		_carry_ready = had


## The run went on after a pause (Game.set_paused(false)): the carried push waits CARRY_WINDOW s for a touch (pass 119).
func resumed() -> void:
	_resumed_ms = Time.get_ticks_msec()


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
	# pass 119: the carried push, fading as the thumb's own drag grows (CARRY_FADE of the reach), then gone for good
	var pushed := v
	if carry != Vector2.ZERO:
		var w := clampf(1.0 - v.length() / maxf(r * CARRY_FADE, 1.0), 0.0, 1.0)
		if w <= 0.0:
			carry = Vector2.ZERO
		else:
			pushed = v + carry * r * w
	# pass 136 (lane GUNS, R1): under the aim rule the dead zone is at most AIM_DEADZONE of the reach, so the turn-on-the-
	# spot zone (Player.TURN_ZONE, 15%) stays usable whatever the stick size (6 px is 17% of a stick at size 0.6)
	var dz := DEADZONE_PX * px_scale
	if Aim.on():
		dz = minf(dz, r * AIM_DEADZONE)
	if pushed.length() < dz:
		stick_dir = Vector2.ZERO
	else:
		stick_dir = (pushed / r).limit_length(1.0)
	# the base follows a long drag, so a thumb that wandered still steers from where it is
	if v.length() > r:
		origin = touch_pos - v.normalized() * r
