## Pass 102 (lane STEADY, Garry's phone run: 60 fps to late Endless, then 15-27 fps): what each played frame cost, for
## the run record (RunAnalytics, schema 4). Two marker nodes bracket the frame's work: one runs first and one last of all
## the tree's _physics_process callbacks (the world update: the crowd, the shots, the hero, the pickups at 60 Hz) and of
## all its _process callbacks (weapons, Fx, HUD, the director, ...); what is left of the frame's wall time is the drawing
## and the wait for the GPU and the screen (rest). It also counts the world steps a frame ran (at most
## Engine.max_physics_steps_per_frame: Game.CATCH_UP_STEPS = 2 while the game plays, since pass 102) and the world time the cap dropped (a frame that ran the cap's
## steps and whose wall time was longer than its delta: Godot shortens the delta by the steps it did not run, so the whole
## game slows together instead of piling up steps).
## Performance.TIME_PROCESS / TIME_PHYSICS_PROCESS are the engine's own figures but only the slowest frame of each wall
## second, updated once a second (measured in 4.7, tools/dl/p102/STEADY), so the means come from these brackets.
## Only frames RunAnalytics ticked (unpaused play) that follow a ticked frame are counted (the gap after a pause is not
## a frame). Cost: four clock reads a frame and one per world step.
class_name WorkClock
extends Node

## The markers' priority: before and after every other node's callbacks.
const EDGE := 1 << 30

## The cap the frames ran under (Engine.max_physics_steps_per_frame when the clock began).
var steps_cap := 2
## false under --fixed-fps or headless (RunAnalytics.frame_timing): the wall clock then says nothing about lost time.
var count_lost := true
## The engine frame RunAnalytics ticked last (tick_frame).
var ticked_frame := -1

# this frame
var _steps := 0
var _phys_t0 := 0
var _phys_us := 0
var _phys_step_max := 0
var _proc_t0 := 0
var _delta := 0.0
var _end_us := 0
var _end_pf := -1
# the second so far
var _f := 0
var _st := 0
var _st_max := 0
var _ph_us := 0
var _ph_max := 0
var _pr_us := 0
var _pr_max := 0
var _rest_us := 0
var _lost := 0.0
# the run so far
var frames_total := 0
var steps_total := 0
var lost_total := 0.0


class Mark extends Node:
	var clock: WorkClock
	var first := true

	func _physics_process(_d: float) -> void:
		if first:
			clock._phys_begin()
		else:
			clock._phys_end()

	func _process(d: float) -> void:
		if first:
			clock._proc_begin(d)
		else:
			clock._proc_end()


func _ready() -> void:
	steps_cap = Engine.max_physics_steps_per_frame
	for first in [true, false]:
		var m := Mark.new()
		m.name = "First" if first else "Last"
		m.clock = self
		m.first = first
		m.process_mode = Node.PROCESS_MODE_ALWAYS
		m.process_priority = -EDGE if first else EDGE
		m.process_physics_priority = -EDGE if first else EDGE
		add_child(m)


## From RunAnalytics.tick: this frame is played time.
func tick_frame() -> void:
	ticked_frame = Engine.get_process_frames()


func _phys_begin() -> void:
	_phys_t0 = Time.get_ticks_usec()
	_steps += 1


func _phys_end() -> void:
	if _phys_t0 <= 0:
		return
	var d := Time.get_ticks_usec() - _phys_t0
	_phys_us += d
	_phys_step_max = maxi(_phys_step_max, d)


func _proc_begin(delta: float) -> void:
	_proc_t0 = Time.get_ticks_usec()
	_delta = delta


func _proc_end() -> void:
	var now := Time.get_ticks_usec()
	var pf := Engine.get_process_frames()
	if _proc_t0 > 0 and _end_us > 0 and ticked_frame == pf and _end_pf == pf - 1:
		add_frame(now - _end_us, _steps, _phys_us, _phys_step_max, now - _proc_t0, _delta)
	_end_pf = pf if ticked_frame == pf else -1
	_end_us = now
	_steps = 0
	_phys_us = 0
	_phys_step_max = 0


## One counted frame into the second (microseconds; delta in seconds): its wall time, the world steps it ran and their
## time, its slowest step, its process time and its delta. Public for the tests.
func add_frame(wall_us: int, steps: int, phys_us: int, phys_step_max: int, proc_us: int, delta: float) -> void:
	_f += 1
	_st += steps
	_st_max = maxi(_st_max, steps)
	_ph_us += phys_us
	_ph_max = maxi(_ph_max, phys_step_max)
	_pr_us += proc_us
	_pr_max = maxi(_pr_max, proc_us)
	_rest_us += maxi(wall_us - phys_us - proc_us, 0)
	frames_total += 1
	steps_total += steps
	if count_lost and steps >= steps_cap:
		var lost := maxf(float(wall_us) / 1.0e6 - delta, 0.0)
		_lost += lost
		lost_total += lost


## The second's figures into a row, then the second starts over. Nothing without a counted frame. steps: world steps
## run, steps_max: the most in one frame, phys_ms: a world step's mean time, phys_max: the slowest step, proc_ms: the
## frame's process time (mean), proc_max: the slowest, rest_ms: the rest of the frame (drawing, waiting for the GPU and
## the screen; mean), lost_ms: world time the cap dropped (left out at 0).
func put_second(row: Dictionary) -> void:
	if _f > 0:
		row["steps"] = _st
		row["steps_max"] = _st_max
		if _st > 0:
			row["phys_ms"] = snappedf(float(_ph_us) / float(_st) / 1000.0, 0.01)
			row["phys_max"] = snappedf(float(_ph_max) / 1000.0, 0.1)
		row["proc_ms"] = snappedf(float(_pr_us) / float(_f) / 1000.0, 0.01)
		row["proc_max"] = snappedf(float(_pr_max) / 1000.0, 0.1)
		row["rest_ms"] = snappedf(float(_rest_us) / float(_f) / 1000.0, 0.1)
		var lost_ms := int(round(_lost * 1000.0))
		if lost_ms > 0:
			row["lost_ms"] = lost_ms
	_f = 0
	_st = 0
	_st_max = 0
	_ph_us = 0
	_ph_max = 0
	_pr_us = 0
	_pr_max = 0
	_rest_us = 0
	_lost = 0.0
