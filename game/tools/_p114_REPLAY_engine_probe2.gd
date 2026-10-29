## Pass 114 (lane REPLAY): the replay engine's per-frame physics ticks: --fixed-fps 64, Engine.physics_jitter_fix 0, and
## each frame's ticks (64 or 128) and time scale set in the frame before: the physics steps a frame and both deltas, bit
## exact. Tools only.
##   bash tools/godot.sh --headless --fixed-fps 64 --path game --script res://tools/_p114_REPLAY_engine_probe2.gd
extends SceneTree

var _frame := 0
var _k := 0
var _pd := 0.0
var _bad := 0
const PD := 1.0 / 60.0
## the plan: [k, d] per frame (k = 1 or 2 world steps of PD, or 0 = none)
var _plan := []


class Probe:
	extends Node
	var t
	func _physics_process(d: float) -> void:
		t._k += 1
		t._pd = d
	func _process(d: float) -> void:
		t._on_proc(d)


func _init() -> void:
	Engine.physics_jitter_fix = 0.0
	Engine.physics_ticks_per_second = 64
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in range(400):
		var r := rng.randi() % 4
		if r == 0:
			_plan.append([0, rng.randf_range(0.004, 0.02)])
		elif r == 1:
			_plan.append([2, 2.0 * PD + rng.randf_range(-0.002, 0.002)])
		else:
			_plan.append([1, PD + (rng.randf_range(-0.001, 0.001) if r == 3 else 0.0)])
	var p := Probe.new()
	p.t = self
	p.process_priority = -1000
	p.process_physics_priority = -1000
	root.add_child(p)
	_apply(0)


func _apply(f: int) -> void:
	if f >= _plan.size():
		return
	var k: int = _plan[f][0]
	var d: float = _plan[f][1]
	if k > 0:
		Engine.physics_ticks_per_second = 64 * k
		Engine.time_scale = 64.0 * float(k) * PD
	else:
		Engine.physics_ticks_per_second = 64
		Engine.time_scale = 64.0 * d


func _on_proc(d: float) -> void:
	# frame 0 ran on the defaults (set in _init, before the first frame); from frame 1 each frame was set by the one before
	if _frame >= 1 and _frame - 1 < _plan.size():
		var want: Array = _plan[_frame - 1]
		var k: int = want[0]
		var want_steps := k if k > 0 else 1
		var want_d: float = float(k) * PD if k > 0 else float(want[1])
		var ok := _k == want_steps and d == want_d and (k == 0 or _pd == PD)
		if not ok:
			_bad += 1
			if _bad < 10:
				print("frame %d: want k=%d d=%.17f got steps=%d d=%.17f pd=%.17f" % [_frame, want_steps, want_d, _k, d, _pd])
	_k = 0
	_apply(_frame)
	_frame += 1
	if _frame > _plan.size():
		print("probe2: %d frames, %d not as planned" % [_plan.size(), _bad])
		quit(0)
