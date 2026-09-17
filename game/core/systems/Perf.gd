## Frame-time bookkeeping for the smoke run and the debug panel: each system adds the microseconds it spent,
## Perf.report() hands back the average milliseconds per frame since the last report. Costs two clock reads a call.
class_name Perf
extends RefCounted

static var usec: Dictionary = {}
static var frames := 0
static var worst_ms := 0.0
static var slow_frames := 0   # frames over 33 ms since the last report
static var _last_tick := 0
static var _this_frame: Dictionary = {}
static var context := ""   # what the game was doing (set by the game around notable moments)
static var slow_log: Array = []   # {"ms", "at", "parts"} for every frame over 33 ms since the last report


static func add(key: String, from_usec: int) -> void:
	var d := Time.get_ticks_usec() - from_usec
	usec[key] = int(usec.get(key, 0)) + d
	_this_frame[key] = int(_this_frame.get(key, 0)) + d


## Called once per rendered frame by the game: frame statistics.
static func frame() -> void:
	var now := Time.get_ticks_usec()
	if _last_tick > 0:
		var ms := float(now - _last_tick) / 1000.0
		worst_ms = maxf(worst_ms, ms)
		if ms > 33.0:
			slow_frames += 1
			slow_log.append({"ms": ms, "parts": _this_frame.duplicate(), "clock": Time.get_ticks_msec(), "ctx": context})
	_this_frame.clear()
	_last_tick = now
	frames += 1


## The game is paused: the next frame's delta is not a hitch.
static func pause() -> void:
	_last_tick = 0


static func report() -> Dictionary:
	var out := {"frames": frames, "worst_ms": worst_ms, "slow": slow_frames}
	for k in usec.keys():
		out[k] = float(usec[k]) / 1000.0 / maxf(float(frames), 1.0)
	usec.clear()
	frames = 0
	worst_ms = 0.0
	slow_frames = 0
	out["slow_log"] = slow_log.duplicate()
	slow_log.clear()
	return out
