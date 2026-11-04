## Pass 125 (performance): a phone run replayed on the PC with its script work measured second by second, so the
## phone's own figures can be set against the same moments of the same run on a machine whose speed does not change.
## The replay is _p114_REPLAY_proof.gd's (mode=replay; assist=1 keeps the hero where the player was); this adds, for
## every second of play the run recorder (RunAnalytics, in memory) writes, the Perf timers' milliseconds a frame by
## system over that second, and at the end writes {samples, perf, report} to perf_out.
##   GODOT_TIMEOUT=2400 bash tools/godot.sh --audio-driver Dummy --fixed-fps 64 --disable-vsync --resolution 504x1122 \
##     --path game --script res://tools/_p125_PERF_replay.gd -- mode=replay assist=1 file=<replay.json> \
##     out=<report.json> perf_out=<record.json> res=504x1122
## Autoloads are reached through the tree (a SceneTree script compiles before they exist).
extends "res://tools/_p114_REPLAY_proof.gd"

var _perf_out := ""
var _perf_rows: Array = []
var _seen := 0
var _perf_cls = null


func _init() -> void:
	super._init()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("perf_out="):
			_perf_out = a.substr(9)
	_perf_cls = load("res://core/systems/Perf.gd")
	process_frame.connect(_perf_tick)


func _ra() -> Node:
	return _game.get_node_or_null("RunAnalytics") if _game != null and is_instance_valid(_game) else null


func _perf_tick() -> void:
	var ra := _ra()
	if ra == null:
		return
	var s: Array = ra.get("samples")
	if s.size() > _seen:
		_seen = s.size()
		var rep: Dictionary = _perf_cls.report()
		rep.erase("slow_log")
		var last: Dictionary = s[s.size() - 1]
		rep["t"] = last.get("t", 0.0)
		rep["alive"] = last.get("alive", 0)
		_perf_rows.append(rep)


func _end_report(why: String) -> void:
	var ra := _ra()
	if _perf_out != "" and ra != null:
		var f := FileAccess.open(_perf_out, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"samples": ra.get("samples"), "perf": _perf_rows, "why": why}))
			f.close()
			_say("perf rows %d, samples %d -> %s" % [_perf_rows.size(), (ra.get("samples") as Array).size(), _perf_out])
	super._end_report(why)
