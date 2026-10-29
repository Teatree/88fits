## Pass 114 (lane REPLAY): what the engine does with --fixed-fps and Engine.time_scale, frame by frame: the physics
## steps a frame, the physics and process deltas (bit-exact, as %a), a time scale written in _process (which frame it
## reaches) and a timer's and a tween's progress. Tools only.
##   bash tools/godot.sh --headless --fixed-fps 64 --path game --script res://tools/_p114_REPLAY_engine_probe.gd
extends SceneTree

var _frame := 0
var _phys_this := 0
var _pd := 0.0
var _probe: Node
var _timer_left := -1.0
var _tw_val := 0.0


class Probe:
	extends Node
	var owner_tree
	func _physics_process(d: float) -> void:
		owner_tree._on_phys(d)
	func _process(d: float) -> void:
		owner_tree._on_proc(d)


func _init() -> void:
	Engine.physics_ticks_per_second = int(OS.get_environment("P114_TICKS")) if OS.get_environment("P114_TICKS") != "" else 64
	_probe = Probe.new()
	_probe.owner_tree = self
	_probe.process_priority = -1000
	_probe.process_physics_priority = -1000
	root.add_child(_probe)


func _on_phys(d: float) -> void:
	_phys_this += 1
	_pd = d


func _on_proc(d: float) -> void:
	var line := "f%d k=%d pd=%.17f d=%.17f ts=%.17f" % [_frame, _phys_this, _pd, d, Engine.time_scale]
	if _frame == 3:
		var t := create_timer(0.05)
		t.timeout.connect(func(): print("  timer fired at frame %d" % _frame))
	if _frame == 4:
		Engine.time_scale = 64.0 * (1.0 / 60.0)
		line += " (wrote ts=64/60)"
	if _frame == 8:
		Engine.time_scale = 64.0 * 0.0213
		line += " (wrote ts=64*0.0213)"
	if _frame == 12:
		Engine.time_scale = 1.0
	if _frame >= 5 and _frame <= 10:
		line += " exact1/60=%s" % str(d == 1.0 / 60.0)
	if _frame == 9 or _frame == 10:
		line += " exact0.0213=%s pdexact=%s" % [str(d == 0.0213), str(_pd == 0.0213)]
	print(line)
	_phys_this = 0
	_frame += 1
	if _frame > 300:
		# count the frames that ran other than one physics step (the steady accumulator check)
		quit(0)
