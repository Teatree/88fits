## Pass 114 (lane REPLAY; Garry: "Go ahead and implement it as described in run_replay_options.md as Option 1"): every
## run's input recording, and the driver that plays one back through the real game (docs/research/run_replay_options.md
## option 1; analytics/howto/04_replays.md; BALANCING.md 57.REPLAY; the file: analytics/SCHEMA.md "The replay file").
##
## What a recording keeps (enough for the same build to play the run again exactly):
## - the run's seed (Run.run_seed: every rule's dice, Dice), the launch (hero, map and its seed, stage, the spawn beam),
##   the save as the run began (the Upgrade board, what is owned and unlocked, quests, looks) and the settings;
## - every engine frame from the first after Game._ready: k = the 60 Hz world steps it ran, pd = their delta, d = the
##   frame's delta, whether the run's world ran (not paused), the game's time scale (run-length coded, gzip+base64);
## - the stick as the world steps read it at each frame's start (Lockstep.q2: 1/1024 steps), its base for the ghost;
## - every decision a tap took, by id, with its frame and phase (note(); a replay calls the same function again);
## - every finger's touch (for the rings), checkpoints every CHECK_EVERY s of play (the hero, HP, level, XP, kills,
##   the crowd, gold, the rule dice's state), the hero's track every TRACK_EVERY s, and the run's marks for the reel.
## Saved at the run's end beside the run record (user://analytics/replays/<stamp>.json; a phone keeps the newest
## KEEP_FILES; the PC from the repo mirrors to analytics/runs/replays/) and sent to PostHog as `run_replay` parts under
## the play-data consent (Analytics.run_replay; never from the arena, tools, headless runs, the sim or a replay).
##
## A replay (mode REPLAY: `plan` set by the viewer, game/replay/ReplayViewer.gd, before the Game is made) runs the build
## with --fixed-fps 64 and 64 physics ticks (Lockstep.REPLAY_HZ): each engine frame is one recorded frame; its Head (the
## first physics and process callback) applies the decisions due, sets the stick, sets Lockstep.proc_d, and runs the
## frame's k world steps itself (the Lockstep group, in the engine's order); its Tail (the last process callback)
## compares the checkpoints and sets Engine.time_scale for the next frame so every engine delta is the recorded one.
class_name RunReplay
extends Node

const SCHEMA := 1
const KIND := "88fits_replay"
const DIR := "user://analytics/replays"
const KEEP_FILES := 50
## seconds of play (Run.play_clock) between checkpoints, and between two points of the hero's track
const CHECK_EVERY := 5.0
const TRACK_EVERY := 0.5
## a decision whose screen is not up at its frame waits at most this many frames (then it is dropped and reported)
const WAIT_FRAMES := 900
## after a drift a recorded card that is not offered waits this many frames, then the like one is taken (_card_like)
const OFFER_WAIT := 60
## the save keys whose values a replay needs nothing of: kept (the game reads them) but blanked (never sent)
const SAVE_BLANK := {"install_id": "", "survey": {}}
enum { OFF, RECORD, REPLAY }

## the run's recorder or driver (null between runs)
static var I: RunReplay = null
## the replay the next Game plays (the parsed file; set by the viewer, read once by attach)
static var plan: Dictionary = {}
## the build this game is (game/config/build.json), read once
static var _build: Dictionary = {}

signal checkpoint_compared(i: int, ok: bool, diffs: Dictionary)
signal decision_applied(dec: Dictionary, late: int)
signal finished_frames

var mode := OFF
var game: Node
## the frame now running (0 = the first frame after Game._ready)
var frame := -1
## between the tail of one frame and the head of the next: an input event's time
var _between := true
var _pf_seen := -1
var _head: Node
var _tail: Node
var _started_ms := 0

# ---- recording
var _k := 0
var _pd := 0.0
var _ran := false
var _ts := 1.0
var _cur := []          # the frame tuple being run-length coded: [k, ran, pd, d, ts]
var _cur_n := 0
var _runs := StreamPeerBuffer.new()
var _runs_n := 0
var _stick := StreamPeerBuffer.new()
var _stick_n := 0
var _last_stick := [-1, 0, 0, 0]
var _origin_last := Vector2(-99999, -99999)
var _origins: Array = []
var decisions: Array = []
var taps: Array = []
var checks: Array = []
var marks: Array = []
var _track := StreamPeerBuffer.new()
var _track_n := 0
## the hero's exact place after each of his slides (Player.hero_moved): float32 bits, second differences, zigzag varints
var _hero := StreamPeerBuffer.new()
var _hero_n := 0
var _hb_prev := PackedInt32Array([0, 0, 0])
var _hb_d := PackedInt32Array([0, 0, 0])
var _next_check := 0.0
var _check_every := CHECK_EVERY
var _next_track := 0.0
var header: Dictionary = {}
var _closed := false
## a tool's recording (the launch's analytics_memory): kept in last_json for the tool, no file, nothing sent
var memory_only := false
var last_path := ""
var last_json := ""

# ---- replaying
var frames_n := 0
var _fk := PackedByteArray()
var _fran := PackedByteArray()
var _fpd := PackedFloat64Array()
var _fd := PackedFloat64Array()
var _fts := PackedFloat64Array()
var _stick_f := PackedInt32Array()
var _stick_v := PackedInt64Array()
var _dec_i := 0
var _pending: Array = []
var _check_i := 0
var _track_f := PackedInt32Array()
var _track_xz := PackedVector2Array()
var _track_hp := PackedFloat32Array()
var _track_i := 0
var _hero_pos := PackedFloat32Array()
var _hero_i := 0
## the slides whose result the physics engine gave in other last bits than on the recording's machine (then taken from it)
var hero_fixes := 0
## the frame of the first checkpoint that differed (-1: none yet) and what differed
var drift_frame := -1
var drift_what: Dictionary = {}
var checks_ok := 0
var checks_bad := 0
var late_decisions := 0
var dropped_decisions: Array = []
var assisted := 0
## frames with a recorded decision the replay could not apply, and the debug actions it cannot replay
var notes: Array = []
## a seek (the viewer): frames run without drawing until this frame
var seek_to := -1
## the safety net after a drift (the viewer's switch): the hero pulled to his recorded track (_assist)
var assist := true
## the viewer's pause: no frame advances while held (the game's processing off, the engine's clock at 0); requests are
## taken at a frame's end, so a frame always runs whole
var _held := false
var _hold_req := -1
var _step_left := 0
var _rehold_at := -1
var _game_mode := Node.PROCESS_MODE_INHERIT
var _eng_step := 0
## a diagnostic (the launch's replay_trace [from, to] frames): the hero's exact state at every world step, printed
var _trace := Vector2i(-1, -1)


# ---------------------------------------------------------------- set up

## Game._enter_tree, before any of the run's systems is ready: the run's seed (Run.begin_run_seed) and, for a
## recording, the save and the settings as the run is about to start them.
static func before_run(p_game: Node) -> Dictionary:
	var snap := {}
	var lo: Dictionary = Run.launch_override
	# a tool's replay comes in through the launch (it cannot name this class at compile time)
	if lo.has("replay_plan"):
		if plan.is_empty() and lo["replay_plan"] is Dictionary:
			plan = lo["replay_plan"]
		lo.erase("replay_plan")
	if not plan.is_empty() and not Settings.is_prod():
		Run.forced_run_seed = int(plan.get("run_seed", 0))
	Run.begin_run_seed(lo)
	snap["save"] = _save_snapshot()
	snap["settings"] = Settings.to_dict()
	snap["d_ready"] = p_game.get_process_delta_time() if p_game.is_inside_tree() else 0.0
	return snap


static func _save_snapshot() -> Dictionary:
	var d: Dictionary = Save.data.duplicate(true)
	for k in SAVE_BLANK:
		if d.has(k):
			d[k] = SAVE_BLANK[k]
	return d


## Game._ready, once the run has started (Run.start, the stage chosen, the player made): the recorder (or the replay's
## driver) under the game. `launch` is what the game started from; `snap` what before_run kept.
static func attach(p_game: Node, launch: Dictionary, snap: Dictionary) -> RunReplay:
	var rr := RunReplay.new()
	rr.name = "RunReplay"
	rr.game = p_game
	rr.process_mode = Node.PROCESS_MODE_ALWAYS
	rr.mode = rr._choose_mode(launch)
	I = rr
	Lockstep.clear_timers()
	Lockstep.ticking += 1
	p_game.add_child(rr)
	if launch.get("replay_trace") is Array:
		rr._trace = Vector2i(int(launch["replay_trace"][0]), int(launch["replay_trace"][1]))
	rr._make_hooks()
	if rr.mode == RECORD:
		rr._begin_record(launch, snap)
	elif rr.mode == REPLAY:
		rr._begin_replay()
	return rr


func _choose_mode(launch: Dictionary) -> int:
	if not plan.is_empty() and not Settings.is_prod():
		return REPLAY
	if Run.arena:
		return OFF
	if bool(launch.get("replay_record", false)):
		return RECORD
	if bool(launch.get("analytics_memory", false)) or bool(launch.get("sim_fast", false)) or bool(launch.get("sim_clock", false)):
		return OFF
	if RunAnalytics.is_tool_process():
		return OFF
	return RECORD


func _exit_tree() -> void:
	# a run left without an end (the window closed, back to the title through a tool): what was recorded is still kept
	if mode == RECORD and not _closed and frame > 0:
		finish("quit")
	Lockstep.ticking = maxi(Lockstep.ticking - 1, 0)
	if Lockstep.ticking == 0:
		Lockstep.clear_timers()
	if I == self:
		I = null
	if mode == REPLAY:
		Lockstep.replaying = false
		Lockstep.driving = false
		Engine.time_scale = 1.0
		plan = {}


func _make_hooks() -> void:
	_head = _Head.new()
	_head.rr = self
	_head.name = "Head"
	_head.process_priority = -1000000
	_head.process_physics_priority = -1000000
	_head.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_head)
	_tail = _Tail.new()
	_tail.rr = self
	_tail.name = "Tail"
	_tail.process_priority = 1000000
	_tail.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_tail)


# ---------------------------------------------------------------- the build

## The build this game is: game/config/build.json as ship.sh stamped it ({id, version, utc, git, dirty}); the version
## alone when the file is missing (a run from the editor binary between builds).
static func build_info() -> Dictionary:
	if not _build.is_empty():
		return _build
	var b := {}
	# the editor binary runs the repo as it is now: never the last build's stamp (tools/replay.py replays such a run on
	# the repo's snapshot and says so)
	if not OS.has_feature("editor") and FileAccess.file_exists("res://config/build.json"):
		var j = JSON.parse_string(FileAccess.get_file_as_string("res://config/build.json"))
		if j is Dictionary:
			b = j
	var ver := str(ProjectSettings.get_setting("application/config/version", "?"))
	if not b.has("id"):
		b["id"] = ("editor-" if OS.has_feature("editor") else "dev-") + ver
		b["version"] = ver
		b["unstamped"] = true
	b["engine"] = Engine.get_version_info().get("string", "")
	b["editor"] = OS.has_feature("editor")
	_build = b
	return b


# ---------------------------------------------------------------- recording

func _begin_record(launch: Dictionary, snap: Dictionary) -> void:
	_started_ms = Time.get_ticks_msec()
	var vp := get_viewport()
	var canvas: Vector2 = vp.get_visible_rect().size if vp else Vector2.ZERO
	var look := ""
	if Run.character:
		var hl = Save.data.get("hero_look", {})
		look = str((hl as Dictionary).get(Run.character.id, "")) if hl is Dictionary else ""
	var eff := {}
	for k in launch:
		var v = launch[k]
		if v is String or v is int or v is float or v is bool:
			eff[str(k)] = v
	eff["character"] = Run.character.id if Run.character else ""
	eff["map"] = Run.map.id if Run.map else ""
	eff["map_seed"] = Run.map_seed
	eff["stage"] = Run.stage + 1
	eff["spawn"] = bool(launch.get("spawn", launch.is_empty()))
	header = {
		"kind": KIND, "schema": SCHEMA, "build": build_info(),
		"recorded": Time.get_datetime_string_from_system(false, true), "recorded_utc": int(Time.get_unix_time_from_system()),
		"stamp": Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_"),
		"player": Save.player_name() if Save.has_method("player_name") else "",
		"platform": OS.get_name(), "device": OS.get_model_name(), "mobile": OS.has_feature("mobile"),
		"hero": eff["character"], "look": look, "stage": eff["stage"], "map": eff["map"], "map_seed": Run.map_seed,
		"run_seed": Run.run_seed, "launch": eff, "save": snap.get("save", {}), "settings": snap.get("settings", {}),
		"canvas": [canvas.x, canvas.y], "vp_px": _vp_px(vp), "safe_top": W.safe_top() if canvas.y > 0.0 else 0.0,
		"d_ready": float(snap.get("d_ready", 0.0)), "hz": Engine.physics_ticks_per_second,
		"check_every": CHECK_EVERY, "track_every": TRACK_EVERY,
	}
	memory_only = bool(launch.get("analytics_memory", false))
	_check_every = float(launch.get("replay_check", CHECK_EVERY))
	_next_check = _check_every
	header["check_every"] = _check_every
	_next_track = 0.0


static func _vp_px(vp: Viewport) -> Array:
	var s = vp.get("size") if vp else null
	if s is Vector2i:
		return [s.x, s.y]
	return []


## A player's decision (a tap's handler, or a tool's driver inside Lockstep.input_depth): kept with its frame and
## phase. `args` identify it (a card's id, an index, a bool). Nothing outside a recording; nothing while a replay plays
## (its own calls land here too).
static func note(kind: String, args: Dictionary = {}) -> void:
	var rr := I
	if rr == null or rr.mode != RECORD or rr._closed:
		return
	if not rr._between and Lockstep.input_depth <= 0:
		return
	var d := args.duplicate()
	d["k"] = kind
	# between frames: before the next frame's world steps (a tap); inside one (the bot at the frame's process start)
	d["f"] = rr.frame + 1 if rr._between else rr.frame
	d["p"] = 0 if rr._between else 1
	d["t"] = snappedf(Run.play_clock, 0.01)
	rr.decisions.append(d)


## A mark for the reel (RunAnalytics.event forwards the run's events: level-ups, chests, totems, bosses, ...).
static func mark(kind: String, id: String = "", level: int = 0) -> void:
	var rr := I
	if rr == null or rr.mode != RECORD or rr._closed:
		return
	rr.marks.append([maxi(rr.frame, 0), snappedf(Run.play_clock, 0.01), kind, id, level])


func _frame_head() -> void:
	frame += 1
	if frame >= _trace.x and frame <= _trace.y:
		print("HEAD f%d in_physics=%s pf=%d ticks=%d ts=%.6f" % [frame, str(Engine.is_in_physics_frame()), Engine.get_process_frames(), Engine.physics_ticks_per_second, Engine.time_scale])
	_between = false
	_k = 0
	_pd = 0.0
	_ran = false
	_ts = Engine.time_scale
	if mode == RECORD:
		_note_stick()
	elif mode == REPLAY:
		_replay_head()


func _note_stick() -> void:
	var inp = game.player.input if game and game.get("player") and game.player.get("input") else null
	if inp == null:
		return
	var q := Lockstep.q2(inp.stick_dir)
	var flags := (1 if inp.wants_move else 0) | (2 if inp.keyboard else 0) | (4 if inp.lifted_once else 0)
	var qx := int(roundf(q.x * Lockstep.STICK_Q))
	var qy := int(roundf(q.y * Lockstep.STICK_Q))
	if flags != _last_stick[1] or qx != _last_stick[2] or qy != _last_stick[3] or _last_stick[0] < 0:
		_last_stick = [frame, flags, qx, qy]
		_stick.put_u32(frame)
		_stick.put_u8(flags)
		_stick.put_16(qx)
		_stick.put_16(qy)
		_stick_n += 1
	if inp.wants_move and not inp.keyboard:
		var o: Vector2 = inp.origin
		if o.distance_to(_origin_last) >= 1.0:
			_origin_last = o
			_origins.append([frame, int(roundf(o.x)), int(roundf(o.y))])


func _on_physics(delta: float) -> void:
	if _held:
		return
	if Engine.get_process_frames() != _pf_seen:
		_pf_seen = Engine.get_process_frames()
		_frame_head()
		_eng_step = 0
	if mode == RECORD:
		_trace_step(_k)
		_k += 1
		_pd = delta
		if not get_tree().paused:
			_ran = true
	elif mode == REPLAY:
		_replay_step(_eng_step)
		_eng_step += 1


func _on_process_head(_delta: float) -> void:
	if _held:
		return
	if Engine.get_process_frames() != _pf_seen:
		_pf_seen = Engine.get_process_frames()
		_frame_head()


## A replay's phase-1 decisions (a driver's, taken at the frame's process start: the tree's process_frame signal, where the
## bot and the tools act) at the same point.
func _on_process_frame() -> void:
	if _held or mode != REPLAY or frame < 0:
		return
	if Engine.get_process_frames() != _pf_seen:
		return
	_apply_due(1)


func _on_process_tail(delta: float) -> void:
	if _held:
		_held_tail()
		return
	if frame < 0:
		return
	Lockstep.tick_timers(Lockstep.dt(delta), get_tree().paused)
	if mode == RECORD:
		_record_tail(delta)
	elif mode == REPLAY:
		_replay_tail()
	_between = true


func _record_tail(d: float) -> void:
	if _closed:
		return
	var tup := [_k, 1 if _ran else 0, _pd if _k > 0 else 0.0, d, _ts]
	if _cur_n > 0 and tup == _cur:
		_cur_n += 1
	else:
		_flush_run()
		_cur = tup
		_cur_n = 1
	var pc := Run.play_clock
	if pc >= _next_track:
		_next_track = pc + TRACK_EVERY
		_put_track()
	if pc >= _next_check:
		_next_check += _check_every
		var c := check_values()
		c["f"] = frame
		checks.append(c)
	if game and bool(game.get("_ended")) and not _closed:
		finish("end")


func _flush_run() -> void:
	if _cur_n <= 0:
		return
	_runs.put_u32(_cur_n)
	_runs.put_u8(int(_cur[0]) | (int(_cur[1]) << 4))
	_runs.put_double(float(_cur[2]))
	_runs.put_double(float(_cur[3]))
	_runs.put_double(float(_cur[4]))
	_runs_n += 1
	_cur_n = 0


func _put_track() -> void:
	var p = game.get("player") if game else null
	if p == null:
		return
	var pos: Vector3 = p.global_position
	_track.put_u32(frame)
	_track.put_32(int(roundf(pos.x * 100.0)))
	_track.put_32(int(roundf(pos.z * 100.0)))
	_track.put_float(float(p.get("hp")))
	_track_n += 1


## A finger's touch for the rings (Head._input, a recording): canvas pixels, frame, down/up.
func _on_input(e: InputEvent) -> void:
	if mode != RECORD or _closed:
		return
	var f := frame + 1 if _between else frame
	if e is InputEventScreenTouch:
		taps.append([f, int(roundf(e.position.x)), int(roundf(e.position.y)), 1 if e.pressed else 0, e.index])
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		taps.append([f, int(roundf(e.position.x)), int(roundf(e.position.y)), 1 if e.pressed else 0, -1])


## Player, after each of his slides: a recording keeps his exact place; a replay puts him on the recorded place (the
## same unless the physics engine's last bits differ: an engine-internal order, another CPU), so nothing reads a
## place the player's run never had.
static func hero_moved(p: Node3D) -> void:
	var rr := I
	if rr == null:
		return
	if rr.mode == RECORD and not rr._closed:
		rr._put_hero(p.global_position)
	elif rr.mode == REPLAY:
		rr._lock_hero(p)


func _put_hero(v: Vector3) -> void:
	var bits := PackedFloat32Array([v.x, v.y, v.z]).to_byte_array().to_int32_array()
	for a in range(3):
		var d1 := bits[a] - _hb_prev[a]
		var d2 := d1 - _hb_d[a]
		_hb_prev[a] = bits[a]
		_hb_d[a] = d1
		_put_varint(_hero, (d2 << 1) ^ (d2 >> 63))
	_hero_n += 1


static func _put_varint(b: StreamPeerBuffer, u: int) -> void:
	while true:
		var byte := u & 127
		u = (u >> 7) & 0x01FFFFFFFFFFFFFF
		if u == 0:
			b.put_u8(byte)
			return
		b.put_u8(byte | 128)


func _decode_hero(blob: String, n: int) -> void:
	_hero_pos = PackedFloat32Array()
	_hero_i = 0
	if blob == "" or n <= 0:
		return
	var raw := _unblob(blob)
	var bits := PackedInt32Array()
	bits.resize(n * 3)
	var prev := [0, 0, 0]
	var dd := [0, 0, 0]
	var at := 0
	for e in range(n):
		for a in range(3):
			var u := 0
			var shift := 0
			while at < raw.size():
				var byte := raw[at]
				at += 1
				u |= (byte & 127) << shift
				shift += 7
				if byte < 128:
					break
			var d2 := (u >> 1) ^ -(u & 1)
			dd[a] = int(dd[a]) + d2
			prev[a] = int(prev[a]) + int(dd[a])
			# back to a 32-bit pattern (the sums wrap as the recording's did)
			var v := int(prev[a]) & 0xFFFFFFFF
			if v >= 0x80000000:
				v -= 0x100000000
			bits[e * 3 + a] = v
	_hero_pos = bits.to_byte_array().to_float32_array()


func _lock_hero(p: Node3D) -> void:
	if _hero_i * 3 + 2 >= _hero_pos.size():
		return
	var want := Vector3(_hero_pos[_hero_i * 3], _hero_pos[_hero_i * 3 + 1], _hero_pos[_hero_i * 3 + 2])
	_hero_i += 1
	if p.global_position != want:
		hero_fixes += 1
		p.global_position = want


## The checkpoint's numbers: the same in a recording and its replay as long as the replay keeps step.
## `h` hashes the exact values (every bit: equal only if the replay keeps step); the rest are the same numbers rounded,
## for the viewer to say what parted and by how much.
func check_values() -> Dictionary:
	var p = game.get("player") if game else null
	var em = game.get("enemies") if game else null
	var exact: Array = [Run.play_clock, Run.level, Run.xp, Run.kills, Run.run_gold, Dice.r.state]
	var c := {"t": snappedf(Run.play_clock, 0.001), "lv": Run.level, "xp": snappedf(Run.xp, 0.01), "kills": Run.kills,
		"gold": Run.run_gold, "dice": str(Dice.r.state)}
	if p:
		var pos: Vector3 = p.global_position
		c["x"] = snappedf(pos.x, 0.001)
		c["z"] = snappedf(pos.z, 0.001)
		c["hp"] = snappedf(float(p.get("hp")), 0.01)
		exact.append(pos)
		exact.append(float(p.get("hp")))
	if em:
		var n := 0
		var h := 0
		var sx := 0.0
		var sz := 0.0
		var alive: PackedByteArray = em.alive
		var pos: PackedVector3Array = em.pos
		for i in range(mini(alive.size(), pos.size())):
			if alive[i] != 0:
				n += 1
				h = hash([h, pos[i]])
				sx += pos[i].x
				sz += pos[i].z
		c["alive"] = n
		c["crowd"] = str(h)
		c["cx"] = snappedf(sx / maxf(n, 1), 0.001)
		c["cz"] = snappedf(sz / maxf(n, 1), 0.001)
		exact.append(h)
	# the shots and the pickups in flight or lying (counts: they name the system that parted first)
	var pm = game.get("projectiles") if game else null
	if pm and pm.get("count") != null:
		c["shots"] = int(pm.get("count"))
		exact.append(c["shots"])
	var pk = game.get("pickups") if game else null
	if pk and pk.get("count") != null:
		c["picks"] = int(pk.get("count"))
		exact.append(c["picks"])
	c["h"] = str(hash(exact))
	# the exact bits of the floats, field by field (clock, XP, hero x, z, HP), so a drift names its first field exactly
	var fb := PackedFloat64Array([Run.play_clock, Run.xp])
	if p:
		var pp: Vector3 = p.global_position
		fb.append(pp.x)
		fb.append(pp.z)
		fb.append(float(p.get("hp")))
	c["b"] = fb.to_byte_array().hex_encode()
	return c


## The recording closed and written (Game.end_run, abandon, the app closing mid-run): the header's end, the file, the
## send. `reason` the run's end as RunAnalytics names it.
func finish(reason: String = "end") -> String:
	if mode != RECORD or _closed:
		return ""
	_closed = true
	_flush_run()
	var p = game.get("player") if game and is_instance_valid(game) else null
	if reason != "quit" or (p != null and is_instance_valid(p) and p.is_inside_tree()):
		var c := check_values()
		c["f"] = frame
		checks.append(c)
	var result := "end"
	if Run.extracted:
		result = "extract"
	elif Run.died:
		result = "death"
	elif reason == "abandon" or (RunAnalytics.I != null and RunAnalytics.I.abandoned):
		result = "abandon"
	header["result"] = result
	header["end_reason"] = reason
	header["frames_n"] = frame + 1
	header["play_s"] = snappedf(Run.play_clock, 0.01)
	header["wall_s"] = snappedf(float(Time.get_ticks_msec() - _started_ms) / 1000.0, 0.1)
	header["level"] = Run.level
	header["kills"] = Run.kills
	header["gold"] = Run.run_gold
	header["frames"] = _blob(_runs)
	header["frames_runs"] = _runs_n
	header["stick"] = _blob(_stick)
	header["stick_n"] = _stick_n
	header["origins"] = _origins
	header["track"] = _blob(_track)
	header["track_n"] = _track_n
	header["hero_steps"] = _blob(_hero)
	header["hero_steps_n"] = _hero_n
	header["decisions"] = decisions
	header["taps"] = taps
	header["checks"] = checks
	header["marks"] = marks
	last_json = JSON.stringify(header)
	if memory_only:
		return ""
	last_path = _write(last_json)
	Analytics.run_replay(last_json, {"build_id": str((header["build"] as Dictionary).get("id", "")), "hero": header["hero"],
		"stage": header["stage"], "result": result, "play_s": header["play_s"]})
	return last_path


static func _blob(b: StreamPeerBuffer) -> String:
	var raw := b.data_array
	return Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_GZIP)) + ":" + str(raw.size())


static func _unblob(s: String) -> PackedByteArray:
	var i := s.rfind(":")
	if i < 0:
		return PackedByteArray()
	var gz := Marshalls.base64_to_raw(s.substr(0, i))
	return gz.decompress(int(s.substr(i + 1)), FileAccess.COMPRESSION_GZIP)


func _write(json: String) -> String:
	var fname := str(header.get("stamp", "run")) + "_replay.json"
	DirAccess.make_dir_recursive_absolute(DIR)
	var out := DIR.path_join(fname)
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f:
		f.store_string(json)
		f.close()
	if OS.has_feature("mobile"):
		RunAnalytics.prune(DIR, KEEP_FILES)
	else:
		# the PC from the repo (the editor binary): a copy beside the run records, for tools/replay.py --latest
		var repo := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
		var mdir := repo.path_join("analytics")
		if DirAccess.dir_exists_absolute(mdir) and OS.has_feature("editor"):
			mdir = mdir.path_join("runs").path_join("replays")
			DirAccess.make_dir_recursive_absolute(mdir)
			var g := FileAccess.open(mdir.path_join(fname), FileAccess.WRITE)
			if g:
				g.store_string(json)
				g.close()
				out = mdir.path_join(fname)
	print("replay: %s (%d frames, %d decisions, %d KB)" % [out, frame + 1, decisions.size(), json.length() / 1024])
	return out


# ---------------------------------------------------------------- replaying

func _begin_replay() -> void:
	Lockstep.replaying = true
	# the engine's step count is exactly the ticks asked (no jitter smoothing), set per frame by _set_scale_for
	Engine.physics_jitter_fix = 0.0
	Engine.physics_ticks_per_second = Lockstep.REPLAY_HZ
	get_tree().process_frame.connect(_on_process_frame)
	Lockstep.driving = false
	Lockstep.game_scale = 1.0
	_decode(plan)
	var inp = game.player.input if game and game.get("player") and game.player.get("input") else null
	if inp:
		inp.enabled = false
	# the first frame's engine deltas
	_set_scale_for(0)


func _decode(p: Dictionary) -> void:
	frames_n = int(p.get("frames_n", 0))
	_fk.resize(frames_n)
	_fran.resize(frames_n)
	_fpd.resize(frames_n)
	_fd.resize(frames_n)
	_fts.resize(frames_n)
	var b := StreamPeerBuffer.new()
	b.data_array = _unblob(str(p.get("frames", "")))
	var i := 0
	while b.get_position() < b.get_size() and i < frames_n:
		var n := b.get_u32()
		var kr := b.get_u8()
		var pd := b.get_double()
		var d := b.get_double()
		var ts := b.get_double()
		for _j in range(n):
			if i >= frames_n:
				break
			_fk[i] = kr & 15
			_fran[i] = (kr >> 4) & 1
			_fpd[i] = pd
			_fd[i] = d
			_fts[i] = ts
			i += 1
	frames_n = i
	var s := StreamPeerBuffer.new()
	s.data_array = _unblob(str(p.get("stick", "")))
	while s.get_position() + 9 <= s.get_size():
		_stick_f.append(s.get_u32())
		var fl := s.get_u8()
		var qx := s.get_16()
		var qy := s.get_16()
		_stick_v.append(fl | ((qx & 0xFFFF) << 8) | ((qy & 0xFFFF) << 24))
	var t := StreamPeerBuffer.new()
	t.data_array = _unblob(str(p.get("track", "")))
	while t.get_position() + 16 <= t.get_size():
		_track_f.append(t.get_u32())
		var x := float(t.get_32()) / 100.0
		var z := float(t.get_32()) / 100.0
		_track_xz.append(Vector2(x, z))
		_track_hp.append(t.get_float())
	_decode_hero(str(p.get("hero_steps", "")), int(p.get("hero_steps_n", 0)))
	_dec_i = 0
	_check_i = 0


## The engine's time scale for frame `f` (set in the frame before): its process delta is the recorded d (64 * d / 64),
## or, in a frame where the run's world steps ran, their delta pd (so the hero's move_and_slide gets pd exactly; the
## rules' _process read d through Lockstep.dt and every tween is stretched to d in Head).
func _set_scale_for(f: int) -> void:
	if f < 0 or f >= frames_n:
		Engine.time_scale = 1.0
		return
	var hz := float(Lockstep.REPLAY_HZ)
	if _fk[f] > 0 and _fran[f] == 1:
		# k engine physics steps (ticks hz x k), each with the recorded delta pd (ts / (hz x k)): the hero's move_and_slide
		# reads it; the frame's process delta is then k x pd (the rules read d through Lockstep.dt, tweens are stretched)
		var kk := clampi(int(_fk[f]), 1, Lockstep.PHYS_PER_FRAME)
		Engine.physics_ticks_per_second = Lockstep.REPLAY_HZ * kk
		Engine.time_scale = hz * float(kk) * _fpd[f]
	else:
		# a paused frame keeps its engine physics steps too (the physics server stepped that often on the device)
		Engine.physics_ticks_per_second = Lockstep.REPLAY_HZ * clampi(int(_fk[f]), 1, Lockstep.PHYS_PER_FRAME)
		Engine.time_scale = hz * _fd[f]


func _replay_head() -> void:
	if frame >= frames_n:
		if frame == frames_n:
			finished_frames.emit()
		return
	Lockstep.proc_d = _fd[frame]
	Lockstep.game_scale = _fts[frame]
	_tween_stretch()
	_apply_stick()
	_apply_due(0)


## One of the frame's engine physics steps (a replay's engine runs Lockstep.PHYS_PER_FRAME of them a frame): the s-th runs
## the recording's s-th world step, if the frame had one, through every gated node in the engine's order; between two
## steps the engine does what it did on the device (the deferred calls, the frees, the physics space's step).
func _replay_step(s: int) -> void:
	if frame < 0 or frame >= frames_n or s >= int(_fk[frame]):
		return
	_trace_step(s)
	var pd := _fpd[frame]
	# a recorded frame with more steps than the engine gives a frame (a fixed-rate tool's recording under 32 fps) runs the
	# rest in its last engine step
	var n_steps := 1
	if s == Lockstep.PHYS_PER_FRAME - 1 and int(_fk[frame]) > Lockstep.PHYS_PER_FRAME:
		n_steps = int(_fk[frame]) - s
	Lockstep.driving = true
	for _i in range(n_steps):
		var nodes: Array = get_tree().get_nodes_in_group(Lockstep.GROUP)
		nodes.sort_custom(_phys_order)
		for n: Node in nodes:
			if is_instance_valid(n) and n.is_inside_tree() and not n.is_queued_for_deletion() and n.is_physics_processing() and n.can_process():
				n._physics_process(pd)
	Lockstep.driving = false


func _trace_step(s: int) -> void:
	if frame < _trace.x or frame > _trace.y:
		return
	var p = game.get("player") if game else null
	if p == null:
		return
	var b := PackedFloat64Array([p.global_position.x, p.global_position.y, p.global_position.z, p.velocity.x, p.velocity.y, p.velocity.z,
		float(p.get("facing")), Run.play_clock, get_physics_process_delta_time()])
	var kb = p.get("_kb")
	if kb is Vector3:
		b.append_array(PackedFloat64Array([kb.x, kb.z]))
	var lm: Vector3 = p.get_last_motion()
	var fnrm: Vector3 = p.get_floor_normal()
	b.append_array(PackedFloat64Array([lm.x, lm.y, lm.z, fnrm.x, fnrm.y, fnrm.z, float(p.get_slide_collision_count())]))
	var cols := PackedStringArray()
	for ci in range(p.get_slide_collision_count()):
		var kc: KinematicCollision3D = p.get_slide_collision(ci)
		var co = kc.get_collider()
		var cpos: Vector3 = (co as Node3D).global_position if co is Node3D else Vector3.ZERO
		var cbas: Basis = (co as Node3D).global_transform.basis if co is Node3D else Basis()
		cols.append("%s@%s n=%s" % [str(co.get_path()) if co is Node else str(co), PackedFloat32Array([cpos.x, cpos.y, cpos.z, cbas.x.x, cbas.x.z]).to_byte_array().hex_encode(),
			PackedFloat32Array([kc.get_normal().x, kc.get_normal().y, kc.get_normal().z]).to_byte_array().hex_encode()])
	var inp = p.get("input")
	var st := "%s,%s,%s" % [str(inp.wants_move), str(Lockstep.q2(inp.stick_dir).x), str(Lockstep.q2(inp.stick_dir).y)] if inp else "-"
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam:
		var cx := cam.global_transform
		st += " cam=" + PackedFloat32Array([cx.origin.x, cx.origin.y, cx.origin.z, cx.basis.z.x, cx.basis.z.y, cx.basis.z.z, cam.fov]).to_byte_array().hex_encode()
		st += " vp=" + str(get_viewport().get_visible_rect().size) + " vs=" + str(get_viewport().get("size"))
	var em2 = game.get("enemies")
	if em2 and em2.get("drawn_vis") != null:
		var dv := 0
		for v in em2.drawn_vis:
			dv += int(v)
		st += " drawn=%d" % dv
	print("TRACE f%d s%d %s on_floor=%s paused=%s spawning=%s gp=%s stick=%s dice=%s cols=%s" % [frame, s, b.to_byte_array().hex_encode(), str(p.is_on_floor()),
		str(get_tree().paused), str(game.get("spawning")), str(game.get("paused")), st, str(Dice.r.state), " | ".join(cols)])
	var em = game.get("enemies")
	if em:
		var al: PackedByteArray = em.alive
		var ps: PackedVector3Array = em.pos
		var parts := PackedStringArray()
		for i in range(mini(al.size(), ps.size())):
			if al[i] != 0:
				parts.append("%d:%s:%s" % [i, str(em.type_idx[i]) if em.get("type_idx") != null else "?", PackedFloat32Array([ps[i].x, ps[i].z]).to_byte_array().hex_encode()])
		print("CROWD f%d s%d %s" % [frame, s, " ".join(parts)])


static func _phys_order(a: Node, b: Node) -> bool:
	if a.process_physics_priority != b.process_physics_priority:
		return a.process_physics_priority < b.process_physics_priority
	return b.is_greater_than(a)


## In a frame whose engine delta is pd (the world ran) every tween is stretched to the recorded d (its speed x d / pd,
## put back in the next frame's head).
var _stretched: Array = []
func _tween_stretch() -> void:
	for pair in _stretched:
		var tw: Tween = pair[0]
		if tw != null and tw.is_valid():
			tw.set_speed_scale(float(pair[1]))
	_stretched.clear()
	var f := frame
	if _fk[f] <= 0 or _fran[f] == 0 or _fpd[f] <= 0.0:
		return
	# the engine's process delta in such a frame is k x pd
	var eng := _fpd[f] * float(clampi(int(_fk[f]), 1, Lockstep.PHYS_PER_FRAME))
	if eng == _fd[f]:
		return
	var k := _fd[f] / eng
	for tw: Tween in get_tree().get_processed_tweens():
		if tw.is_valid():
			var sp := 1.0
			# Tween has no speed getter: a tween a screen hurried keeps its own speed in a meta of ours
			if tw.has_meta(&"speed"):
				sp = float(tw.get_meta(&"speed"))
			_stretched.append([tw, sp])
			tw.set_speed_scale(sp * k)


func _apply_stick() -> void:
	var inp = game.player.input if game and game.get("player") and game.player.get("input") else null
	if inp == null:
		return
	# the newest change at or before this frame
	var lo := 0
	var hi := _stick_f.size() - 1
	var at := -1
	while lo <= hi:
		var mid := (lo + hi) >> 1
		if _stick_f[mid] <= frame:
			at = mid
			lo = mid + 1
		else:
			hi = mid - 1
	if at < 0:
		return
	var v := _stick_v[at]
	var fl := v & 255
	var qx := (v >> 8) & 0xFFFF
	var qy := (v >> 24) & 0xFFFF
	if qx > 32767:
		qx -= 65536
	if qy > 32767:
		qy -= 65536
	inp.wants_move = (fl & 1) != 0
	inp.keyboard = (fl & 2) != 0
	inp.lifted_once = (fl & 4) != 0
	inp.stick_dir = Vector2(float(qx) / Lockstep.STICK_Q, float(qy) / Lockstep.STICK_Q)


func _apply_due(phase: int) -> void:
	var decs: Array = plan.get("decisions", [])
	# the ones still waiting for their screen first
	if not _pending.is_empty():
		var keep: Array = []
		for d: Dictionary in _pending:
			if int(d["p"]) != phase:
				keep.append(d)
				continue
			_took = ""
			if _apply(d):
				late_decisions += 1
				decision_applied.emit(_with_took(d), frame - int(d["f"]))
			elif frame - int(d["f"]) > WAIT_FRAMES:
				dropped_decisions.append(d)
				notes.append("%s at %.1f s could not be replayed (its screen never came: the replay had parted)" % [_kind_words(str(d["k"])), float(d.get("t", 0.0))])
			else:
				keep.append(d)
		_pending = keep
	while _dec_i < decs.size():
		var d: Dictionary = decs[_dec_i]
		if int(d["f"]) > frame or (int(d["f"]) == frame and int(d["p"]) > phase):
			break
		_dec_i += 1
		if int(d["p"]) != phase and int(d["f"]) == frame:
			_pending.append(d)
			continue
		_took = ""
		if _apply(d):
			decision_applied.emit(_with_took(d), frame - int(d["f"]))
		else:
			_pending.append(d)


## Calls the function the recorded tap called, by id; false when its screen is not up (yet).
func _apply(d: Dictionary) -> bool:
	var g := game
	var k := str(d["k"])
	match k:
		"card":
			var cs = g.get("cards")
			if cs == null or not cs.visible or (cs._offer as Array).is_empty() or bool(cs._picking):
				return false
			var card := _card_in(cs._offer, d)
			if card.is_empty():
				# not offered here (the replay has parted): after OFFER_WAIT frames the offered card of the same kind is
				# taken (else the first), and said, so the run goes on as near to the player's as it can
				if frame - int(d["f"]) < OFFER_WAIT:
					return false
				card = _card_like(cs._offer, d)
				if card.is_empty():
					return false
				notes.append("%s was not offered at %.1f s (the replay had parted): took %s" % [item_name(str(d.get("id", ""))),
					float(d.get("t", 0.0)), item_name(str(card.get("id", "")))])
				_took = str(card.get("id", ""))
			cs._pick(card)
			return true
		"card_skip":
			var cs = g.get("cards")
			if cs == null or not cs.visible:
				return false
			cs._skip()
			return true
		"card_reroll":
			var cs = g.get("cards")
			if cs == null or not cs.visible:
				return false
			cs._reroll()
			return true
		"card_banish_mode":
			var cs = g.get("cards")
			if cs == null or not cs.visible:
				return false
			cs._toggle_banish()
			return true
		"reel_skip":
			var cs = g.get("cards")
			var reel = cs.get("_reel") if cs else null
			if reel == null or not is_instance_valid(reel) or not reel.is_visible_in_tree():
				return false
			reel.skip()
			return true
		"chest_intro":
			var ch = g.get("chest_screen")
			if ch == null or not ch.visible:
				return false
			ch.skip_intro()
			return true
		"chest_hurry":
			var ch = g.get("chest_screen")
			if ch == null or not ch.visible:
				return false
			ch.hurry()
			return true
		"chest_finish":
			var ch = g.get("chest_screen")
			if ch == null or not ch.visible or bool(ch._spinning):
				return false
			ch._finish(bool(d.get("take", true)))
			return true
		"chest_banish":
			var ch = g.get("chest_screen")
			if ch == null or not ch.visible or bool(ch._spinning):
				return false
			ch._banish()
			return true
		"shop_buy":
			var sh = g.get("structure_shop")
			if sh == null or not sh.visible or bool(sh.get("_done")):
				return false
			var i := int(d.get("i", -1))
			var offer: Array = sh._offer
			var cards: Array = sh._cards
			if i < 0 or i >= offer.size() or i >= cards.size():
				return false
			sh._buy(offer[i], int(d.get("price", sh.price_of(offer[i]))), cards[i])
			return true
		"shop_leave":
			var sh = g.get("structure_shop")
			if sh == null or not sh.visible:
				return false
			sh._finish(false)
			return true
		"stranger":
			var ss = g.get("stranger_screen")
			if ss == null or not ss.visible:
				return false
			ss._finish(bool(d.get("took", false)))
			return true
		"totem":
			var ts = g.get("totem_screen")
			if ts == null or not ts.visible or bool(ts._done):
				return false
			var rows: Array = ts.planks()
			var row = null
			for r in rows:
				if is_instance_valid(r) and str((r.boon as Dictionary).get("id", "")) == str(d.get("id", "")):
					row = r
					break
			if row == null:
				var i := int(d.get("i", -1))
				if i < 0 or i >= rows.size():
					return false
				row = rows[i]
			ts._pick(row)
			return true
		"portal_extract":
			var pd = g.get("portal_dialog")
			if pd == null or not pd.visible:
				return false
			pd.extract()
			return true
		"portal_decline":
			var pd = g.get("portal_dialog")
			if pd == null or not pd.visible:
				return false
			pd.decline()
			return true
		"revive":
			var rs = g.get("revive_screen")
			if rs == null or not rs.visible:
				return false
			rs._decide(str(d.get("kind", "give_up")))
			return true
		"revive_hold":
			var rs = g.get("revive_screen")
			if rs == null or not rs.visible:
				return false
			rs._toggle_hold()
			return true
		"gate":
			var gt = g.get("resume_gate")
			if gt == null or not gt.visible:
				return false
			gt.tap()
			return true
		"pause":
			if bool(g.get("paused")):
				return false
			g.open_pause()
			return true
		"resume":
			g.close_pause()
			return true
		"abandon":
			var ps = g.get("pause_screen")
			if ps and ps.has_method("close"):
				ps.close()
			g.abandon_run()
			return true
		"spawn_hurry":
			g.spawn_hurry()
			return true
		"bounty":
			var bp = g.get("bounty_posters")
			if bp == null or not bp.visible or bp.is_done():
				return false
			bp.choose(int(d.get("i", -1)))
			return true
		"bounty_reroll":
			var bp = g.get("bounty_posters")
			if bp == null or not bp.visible:
				return false
			bp._on_reroll()
			return true
		"setting":
			Settings.set(str(d.get("key", "")), d.get("value"))
			Settings.changed.emit()
			return true
		"god":
			if g.has_method("set_god"):
				g.set_god(bool(d.get("on", false)))
			return true
		"debug":
			notes.append("debug action '%s' at %.1f s is not replayed" % [str(d.get("what", "")), float(d.get("t", 0.0))])
			return true
	notes.append("unknown decision '%s'" % k)
	return true


var _took := ""


func _with_took(d: Dictionary) -> Dictionary:
	if _took == "":
		return d
	var c := d.duplicate()
	c["took"] = _took
	return c


## An item's name for the notes (its id when the Registry has none).
static func _kind_words(k: String) -> String:
	return {"card": "a card pick", "gate": "TAP TO GO", "totem": "a totem gift", "stranger": "the Stranger's deal", "chest_finish": "a chest",
		"chest_intro": "a chest's opening", "chest_hurry": "a chest's reel", "shop_buy": "a purchase", "shop_leave": "leaving the shop",
		"revive": "the Down! choice", "bounty": "the Wanted posters", "reel_skip": "the mutation reel", "portal_extract": "EXTRACT",
		"portal_decline": "Not yet"}.get(k, k)


static func item_name(id: String) -> String:
	for getter in ["weapon", "passive", "evolution", "mutation", "perk"]:
		if Registry.has_method(getter):
			var def = Registry.call(getter, id)
			if def != null and def.get("display_name") != null:
				return str(def.display_name)
	return id


static func _card_like(offer: Array, d: Dictionary) -> Dictionary:
	var first := {}
	for c in offer:
		if not (c is Dictionary):
			continue
		if first.is_empty():
			first = c
		if str((c as Dictionary).get("type", "")) == str(d.get("type", "")):
			return c
	return first


static func _card_in(offer: Array, d: Dictionary) -> Dictionary:
	var want := str(d.get("id", ""))
	var lvl := int(d.get("lv", -1))
	var by_id := {}
	for c in offer:
		if c is Dictionary and str(c.get("id", "")) == want:
			if lvl < 0 or int(c.get("level_to", -1)) == lvl:
				return c
			by_id = c
	return by_id


func _replay_tail() -> void:
	var checks_r: Array = plan.get("checks", [])
	while _check_i < checks_r.size() and int((checks_r[_check_i] as Dictionary).get("f", -1)) <= frame:
		var rec: Dictionary = checks_r[_check_i]
		if int(rec.get("f", -1)) == frame:
			_compare(_check_i, rec)
		_check_i += 1
	if assist and drift_frame >= 0:
		_assist()
	_set_scale_for(frame + 1)
	if frame >= frames_n - 1 or _hold_req == 1 or (_rehold_at >= 0 and frame >= _rehold_at):
		_hold()


## The viewer's pause (request_hold / request_step; taken at a frame's end).
func request_hold(v: bool) -> void:
	_hold_req = 1 if v else 0
	if not v:
		_rehold_at = -1


func request_step(n: int = 1) -> void:
	_step_left += maxi(n, 0)


func is_held() -> bool:
	return _held


func _hold() -> void:
	_held = true
	_hold_req = -1
	_rehold_at = -1
	Engine.time_scale = 0.0
	Lockstep.proc_d = 0.0
	if game and is_instance_valid(game):
		if game.process_mode != Node.PROCESS_MODE_DISABLED:
			_game_mode = game.process_mode
		game.process_mode = Node.PROCESS_MODE_DISABLED


func _held_tail() -> void:
	if frame >= frames_n - 1:
		_hold_req = -1
		_step_left = 0
		return
	if _hold_req == 0:
		_release()
	elif _step_left > 0:
		_step_left -= 1
		_release()
		_rehold_at = frame + 1


func _release() -> void:
	_held = false
	_hold_req = -1
	_set_scale_for(frame + 1)
	if game and is_instance_valid(game):
		game.process_mode = _game_mode


func _compare(i: int, rec: Dictionary) -> void:
	var now := check_values()
	var diffs := {}
	for key in rec:
		if key == "f" or key == "h" or key == "b":
			continue
		var a = rec[key]
		var b = now.get(key)
		if b == null:
			continue
		if (a is float or a is int) and (b is float or b is int):
			if absf(float(a) - float(b)) > 1e-6 * maxf(1.0, absf(float(a))):
				diffs[key] = [a, b]
		elif str(a) != str(b):
			diffs[key] = [a, b]
	var ok := str(rec.get("h", "")) == str(now.get("h", "")) and diffs.is_empty()
	if not ok and diffs.is_empty():
		var names := ["clock", "xp", "x", "z", "hp"]
		var ra := PackedByteArray(str(rec.get("b", "")).hex_decode()).to_float64_array()
		var rb := PackedByteArray(str(now.get("b", "")).hex_decode()).to_float64_array()
		for j in range(mini(ra.size(), rb.size())):
			if ra[j] != rb[j]:
				diffs[names[j] if j < names.size() else str(j)] = ["%.17f" % ra[j], "%.17f" % rb[j]]
		if diffs.is_empty():
			diffs["bits"] = ["the same to 3 decimals", "different in the last bits"]
	if ok:
		checks_ok += 1
	else:
		checks_bad += 1
		if drift_frame < 0:
			drift_frame = frame
			drift_what = diffs
	checkpoint_compared.emit(i, ok, diffs)


## The safety net after a drift: at each point of the recorded track the hero is pulled half way to where the player
## really was, and his HP set to the recorded HP (the viewer says so while it does).
func _assist() -> void:
	while _track_i < _track_f.size() and _track_f[_track_i] < frame:
		_track_i += 1
	if _track_i >= _track_f.size() or _track_f[_track_i] != frame:
		return
	var p = game.get("player") if game else null
	if p == null or bool(p.get("dead")):
		return
	var want := _track_xz[_track_i]
	var pos: Vector3 = p.global_position
	var off := Vector2(pos.x, pos.z).distance_to(want)
	if off > 0.25:
		var to := Vector2(pos.x, pos.z).lerp(want, 0.5)
		p.global_position = Vector3(to.x, pos.y, to.y)
		assisted += 1
	var hp := _track_hp[_track_i]
	if absf(float(p.get("hp")) - hp) > 0.5 and hp > 0.0:
		p.set("hp", hp)


## The recorded hero's place at frame `f` (the track), for the viewer's map and the assist.
func track_at(f: int) -> Vector2:
	if _track_f.is_empty():
		return Vector2.INF
	var lo := 0
	var hi := _track_f.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if _track_f[mid] <= f:
			lo = mid
		else:
			hi = mid - 1
	return _track_xz[lo]


# ---------------------------------------------------------------- the frame hooks

class _Head:
	extends Node
	var rr: RunReplay
	func _physics_process(delta: float) -> void:
		rr._on_physics(delta)
	func _process(delta: float) -> void:
		rr._on_process_head(delta)
	func _input(event: InputEvent) -> void:
		rr._on_input(event)


class _Tail:
	extends Node
	var rr: RunReplay
	func _process(delta: float) -> void:
		rr._on_process_tail(delta)
