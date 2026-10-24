## Pass 102 lane STEADY: how Godot 4.7 hands out process delta when a frame overruns and the physics catch-up is capped.
##   bash tools/godot.sh --headless --path D:/_projects/88fits/game --script res://tools/_p102_STEADY_delta.gd -- busy=50 cap=2
extends SceneTree

var _busy := 50
var _cap := 8
var _frames := 0
var _phys := 0
var _sum_delta := 0.0
var _t0 := 0
var _rows: Array = []

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := String(a).split("=")
		if kv.size() == 2 and kv[0] == "busy": _busy = int(kv[1])
		if kv.size() == 2 and kv[0] == "cap": _cap = int(kv[1])
	Engine.max_physics_steps_per_frame = _cap
	physics_frame.connect(func() -> void: _phys += 1)
	_t0 = Time.get_ticks_usec()

func _process(delta: float) -> bool:
	_frames += 1
	if _frames > 3:
		_sum_delta += delta
		_rows.append([snappedf(delta * 1000.0, 0.01), _phys])
	_phys = 0
	var t := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t < _busy * 1000:
		pass
	if _frames >= 40:
		var wall := (Time.get_ticks_usec() - _t0) / 1e6
		print("cap=%d busy=%d frames=%d sum_delta=%.3f wall=%.3f physics_frames=%d" % [_cap, _busy, _frames, _sum_delta, wall, Engine.get_physics_frames()])
		print(_rows.slice(0, 12))
		return true
	return false
