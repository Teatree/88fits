## The slot machine's sound around a reel (pass 65, Garry: "a spinning slot machine sound effect ... when it's spinning
## and then when it lands on a choice. That whole sequence."): the lever's pull as the strip starts (`ui_slot_start`),
## the spinning loop while it runs (`ui_slot_spin`, its pitch following the strip's speed, so it winds down as the reel
## slows), the clunk of the reel stopping on the landing cell (`ui_slot_stop`), then the screen's own landing sound
## (jackpot, win). cancel() stops the loop when the reel is skipped or the screen closes. Used by ChestScreen and
## WWeaponReel; `events` keeps what it played, in order (the tests read it).
class_name WSlotSound
extends RefCounted

const START := "ui_slot_start"
const SPIN := "ui_slot_spin"
const STOP := "ui_slot_stop"
## The loop's pitch at full speed and as the strip crawls into the landing cell.
const PITCH_FAST := 1.15
const PITCH_SLOW := 0.7

var active := false
var events: Array = []
var _x := 0.0
var _ms := 0
var _peak := 1.0


func _audio() -> Node:
	return W.node("Audio")


## The strip starts moving: the lever, then the loop.
func begin() -> void:
	if active:
		return
	active = true
	_x = 0.0
	_ms = Time.get_ticks_msec()
	_peak = 1.0
	events.append(START)
	events.append(SPIN)
	W.sfx_first([START])
	var a := _audio()
	if a and a.has_method("play_loop"):
		a.play_loop(SPIN, PITCH_FAST)


## The strip is at `x` px now: the loop's pitch follows its speed against the fastest it went this spin.
func feed(x: float) -> void:
	if not active:
		return
	var now := Time.get_ticks_msec()
	var dt := float(now - _ms) / 1000.0
	if dt < 0.012:
		return
	var v := absf(x - _x) / dt
	_x = x
	_ms = now
	_peak = maxf(_peak, v)
	var a := _audio()
	if a and a.has_method("set_loop_pitch"):
		a.set_loop_pitch(SPIN, lerpf(PITCH_SLOW, PITCH_FAST, sqrt(clampf(v / _peak, 0.0, 1.0))))


## The reel stops on its landing cell: the loop ends, the clunk plays (the caller plays its landing sound after).
func land() -> void:
	if not active:
		return
	active = false
	_stop_loop()
	events.append(STOP)
	W.sfx_first([STOP])


## Skipped or closed mid-spin: the loop ends, quietly.
func cancel() -> void:
	if not active:
		return
	active = false
	_stop_loop()
	events.append("cancel")


func _stop_loop() -> void:
	var a := _audio()
	if a and a.has_method("stop_loop"):
		a.stop_loop(SPIN)
