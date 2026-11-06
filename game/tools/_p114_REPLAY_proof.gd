## Pass 114 (lane REPLAY): the determinism proof. One run recorded with the bot driving (its stick and its taps go
## through the same paths a player's do, wrapped in Lockstep.input_depth so the recorder keeps them), then the recording
## replayed through the real game with nothing but the file, and every checkpoint compared.
##   record: bash tools/godot.sh --headless --path game --script res://tools/_p114_REPLAY_proof.gd -- mode=record \
##              out=<file> hero=drifter stage=1 seed=7 limit=600 [res=504x1122] [trail=half] [unlocks=all] [check=1] [bot.<k>=v]
##           (no --fixed-fps: the frames come as the machine gives them, irregular deltas and 0, 1 or 2 world steps)
##   replay: bash tools/godot.sh --headless --fixed-fps 64 --path game --script res://tools/_p114_REPLAY_proof.gd -- \
##              mode=replay file=<file> out=<report.json> [res=504x1122] [seek=0] [assist=1]
## Pass 120 (lane REPLAY): record options downs=debug,ad,... (Down! answered in turn by these taps after down_wait=<s> of
## its count, then give_up), give=<id,id> (handed over by the level-up's debug hand at the first card screen: the Phoenix
## Feather); the report adds the replay's downs and revives (events), corpse_holds, down_parts, ended_early, dead, hp.
## The report: checkpoints equal / different, the first frame that differed and what, decisions late or dropped, the
## wall time. Autoloads are reached through the tree (a SceneTree script compiles before they exist); RunReplay is not
## named (it names autoloads): its plan goes in through the launch (`replay_plan`).
extends SceneTree

const BOT := preload("res://tools/bot/Bot.gd")
const TRAIL_ARG := preload("res://tools/trail_arg.gd")
const BOT_ARGS := ["preset", "skill", "style", "reaction", "dodge", "daring", "stray", "explore", "totems", "barrels", "powerups",
	"structures", "shop", "stranger", "boss", "cards", "lure_w", "lure_close", "breakout", "specials", "portal"]

var _mode := "record"
var _out := ""
var _file := ""
var _hero := "drifter"
var _stage := 1
var _seed := 7
var _limit := 600.0
var _res := Vector2i(504, 1122)
## trail=none|quarter|half|full|<level> (tools/trail_arg.gd; board=<ranks> is its old name): the Trail the recorded save holds
var _trail := "none"
var _unlocks := "all"
var _wall := 3600.0
## the bot's answer to Down!: end (give up) or ad (the ad revive, a tap the recording keeps)
var _death := "end"
## finger=1: the bot's thumb becomes real touch events (pressed, dragged, lifted: PlayerInput reads them as a phone's),
## so the recording has its taps (the rings) and the stick comes the way a player's does
var _finger := false
## god=1: the debug panel's God mode from the first frame (through Game.set_god: the recording keeps it), so a run reaches
## the boss and Endless
var _god := false
## write=1: the recording also goes to its files as a played run's does (user://analytics/replays/ and the repo's mirror)
var _write_files := false
## pass 120 (lane REPLAY): Down!'s answers in turn (then give_up), after this many seconds of its count; the debug hand's
## items at the first card screen; a replay with the safety net on (assist=1)
var _downs: Array = []
var _down_wait := 0.0
var _down_t := -1.0
var _give := ""
var _given := false
var _assist := false
## pass 125: native=0|1: the crowd's compiled loops off or on for this run (_p125_NATIVE_proof.gd); empty: as Settings says
var _native := ""
## stakes=<n>: the Trail's first n Stakes nodes (the optional ones that give the upgrade "stakes": creatures tougher)
## bought in the recorded save, so the hero goes down sooner (the replay reads the same save). Until pass 129 these were
## ranks of the Upgrade board's Stakes.
var _stakes := 0
## down_tap=1: Down!'s debug and ad answers are real finger taps on its buttons (pressed, then lifted: a tap between frames,
## as the player's are), with the developer menu's free revive button shown
var _down_tap := false
var _tap_at := Vector2.INF
var _finger_down := false
var _finger_at := Vector2.ZERO
var _bot_raw := {}
var _check := 0.0
var _trace: Array = []
## a diagnostic: the decorative tumbleweeds removed as they are made (both modes)
var _no_tumble := false

var _run: Node
var _save: Node
var _game: Node
var _bot
var _t := 0.0
var _done := false
var _ending := false
var _t0_ms := 0
var _last_say := 0.0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var i := a.find("=")
		if i <= 0:
			continue
		var k := a.substr(0, i)
		var v := a.substr(i + 1)
		match k:
			"mode": _mode = v
			"out": _out = v
			"file": _file = v
			"hero": _hero = v
			"stage": _stage = maxi(int(v), 1)
			"seed": _seed = int(v)
			"limit": _limit = float(v)
			"trail": _trail = v
			"board": _trail = TRAIL_ARG.board_to_trail(v, 70)
			"unlocks": _unlocks = v
			"wall": _wall = float(v)
			"death": _death = v
			"finger": _finger = v == "1"
			"god": _god = v == "1"
			"write": _write_files = v == "1"
			"downs": _downs = Array(v.split(",", false))
			"down_wait": _down_wait = float(v)
			"give": _give = v
			"assist": _assist = v == "1"
			"stakes": _stakes = int(v)
			"down_tap": _down_tap = v == "1"
			"check": _check = float(v)
			"no_tumble": _no_tumble = v == "1"
			"native": _native = v
			"trace":
				var tr := v.split("-")
				_trace = [int(tr[0]), int(tr[1])]
			"res":
				var wh := v.split("x")
				if wh.size() == 2:
					_res = Vector2i(int(wh[0]), int(wh[1]))
			_:
				if k.begins_with("bot."):
					_bot_raw[k.substr(4)] = v
				elif BOT_ARGS.has(k):
					_bot_raw[k] = v
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _say(s: String) -> void:
	print("proof: " + s)


func _start() -> void:
	_t0_ms = Time.get_ticks_msec()
	if _no_tumble:
		node_added.connect(func(n: Node) -> void:
			if n.get_script() != null and str(n.get_script().resource_path).ends_with("Tumbleweed.gd"):
				n.ready.connect(func() -> void:
					n.set_physics_process(false)
					n.remove_from_group(&"lockstep_phys"), CONNECT_ONE_SHOT))
	_run = root.get_node_or_null("Run")
	_save = root.get_node_or_null("Save")
	var settings := root.get_node_or_null("Settings")
	var reg := root.get_node_or_null("Registry")
	if _run == null or _save == null or reg == null:
		printerr("proof: autoloads missing")
		quit(2)
		return
	_save.set("_dirty", false)
	_save.begin_sandbox()
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.size = _res
	if _mode == "replay":
		var txt := FileAccess.get_file_as_string(_file)
		var plan = JSON.parse_string(txt)
		if not (plan is Dictionary):
			printerr("proof: cannot read " + _file)
			quit(2)
			return
		Engine.physics_ticks_per_second = 64
		Engine.physics_jitter_fix = 0.0
		_save.set("data", (plan["save"] as Dictionary).duplicate(true))
		settings.from_dict(plan["settings"])
		if _native != "":
			settings.set("native_crowd", _native == "1")
		var lo: Dictionary = (plan["launch"] as Dictionary).duplicate()
		lo["replay_plan"] = plan
		if not _trace.is_empty():
			lo["replay_trace"] = _trace
		lo["analytics_memory"] = true
		_run.launch_override = lo
		# the frame the game is made in runs at the recorded delta too (its _ready's tweens and timers)
		Engine.time_scale = 64.0 * float(plan.get("d_ready", 1.0 / 64.0))
		_say("replaying %s: %s stage %s, %d frames, %d decisions, build %s" % [_file.get_file(), str(plan["hero"]), str(plan["stage"]),
			int(plan["frames_n"]), (plan["decisions"] as Array).size(), str((plan["build"] as Dictionary).get("id", ""))])
	else:
		_save.data["runs_started"] = 1
		if _unlocks == "all":
			var done: Array = []
			for qid in (reg.get("quests") as Dictionary).keys():
				done.append(str(qid))
			_save.data["quests_done"] = done
		var tinfo: Dictionary = TRAIL_ARG.apply(_save, _trail)
		if tinfo.has("error"):
			_say(str(tinfo["error"]) + ": no Trail node is bought")
			TRAIL_ARG.apply(_save, "none")
		if _stakes > 0:
			var left := _stakes
			var bought: Array = (_save.data["trail"] as Dictionary)["bought"]
			for n: Dictionary in Trail.nodes():
				var g: Dictionary = n["gives"]
				if left > 0 and str(g.get("type", "")) == "upgrade" and str(g.get("upgrade", "")) == "stakes" and not bought.has(str(n["id"])):
					bought.append(str(n["id"]))
					left -= 1
			Trail.refresh()
		if settings:
			settings.camera_mode = 0
			settings.show_hints = false
			settings.damage_numbers = true
			settings.debug_mode = false
			settings.set("free_revive_button", _down_tap)
			if _native != "":
				settings.set("native_crowd", _native == "1")
		# pass 120 (lane REPLAY): replay_code: the recording names its files as a played run from the editor does
		_run.launch_override = {"character": _hero, "stage": _stage, "spawn": true, "replay_record": true, "analytics_memory": not _write_files,
			"run_seed": _seed, "replay_code": true}
		if _check > 0.0:
			_run.launch_override["replay_check"] = _check
		if not _trace.is_empty():
			_run.launch_override["replay_trace"] = _trace
	# a frame later, so the frame the game is made in has the time scale set above
	process_frame.connect(func() -> void:
		change_scene_to_file("res://game/Game.tscn")
		process_frame.connect(_tick), CONNECT_ONE_SHOT)


func _rr() -> Node:
	return _game.get_node_or_null("RunReplay") if _game != null and is_instance_valid(_game) else null


func _tick() -> void:
	if _done:
		return
	var dt: float = root.get_process_delta_time()
	_t += dt
	if float(Time.get_ticks_msec() - _t0_ms) / 1000.0 > _wall:
		_end_report("wall")
		return
	if _game == null:
		var g = current_scene
		if g == null or not g.has_method("open_pause") or g.get("player") == null:
			return
		_game = g
		if _mode == "record":
			var o := _bot_raw.duplicate()
			o["seed"] = _seed
			o["death"] = _death
			o["t0"] = _t
			_bot = BOT.new(_game, o)
			_say("recording: hero %s stage %d seed %d limit %.0f s" % [_hero, _stage, _seed, _limit])
		return
	var rr := _rr()
	if _mode == "record":
		if rr != null and str(rr.get("last_json")) != "":
			_store_recording(rr)
			return
		if not is_instance_valid(_game) or bool(_game.get("_ended")):
			return
		Lockstep.input_depth += 1
		if _god and not bool(_game.player.get("god")):
			_game.set_god(true)
		var inp = _game.player.input if _game.get("player") else null
		var was := [inp.wants_move, inp.origin, inp.touch_pos] if (inp and _finger) else []
		_give_once()
		if not _answer_down():
			_bot.tick(dt)
		if _finger and inp:
			_finger_from_bot(inp, was)
		var pc := float(_run.get("play_clock"))
		if pc >= _limit and not _ending:
			_ending = true
			_game.end_run()
		Lockstep.input_depth -= 1
		if pc - _last_say >= 60.0:
			_last_say = pc
			_say("  t %.0f level %d kills %d alive %d" % [pc, int(_run.level), int(_run.kills), int(_run.alive)])
	else:
		if rr == null:
			if _game != null and not is_instance_valid(_game):
				_end_report("the game ended before the recording did")
			return
		# the proof measures the game alone: no safety net (assist=1: with it, as the viewer starts)
		rr.set("assist", _assist)
		var f := int(rr.get("frame"))
		var n := int(rr.get("frames_n"))
		if f - _last_say >= 3600:
			_last_say = f
			_say("  frame %d / %d  checks ok %d bad %d" % [f, n, int(rr.get("checks_ok")), int(rr.get("checks_bad"))])
		# pass 120 (lane REPLAY): after the last frame's tail (the driver holds there), so its last check is compared too
		if f >= n - 1 and bool(rr.call("is_held")):
			_end_report("frames")


## Pass 120 (lane REPLAY): Down! answered by `downs` in turn once its count has run `down_wait` s (true while it is up:
## the bot is not ticked then); "ad" only while the ad is on offer.
func _answer_down() -> bool:
	if _downs.is_empty() and _down_wait <= 0.0:
		return false
	var rs = _game.get("revive_screen")
	if rs == null or not rs.visible:
		if _tap_at != Vector2.INF:
			var u := InputEventScreenTouch.new()
			u.index = 1
			u.pressed = false
			u.position = _tap_at
			Input.parse_input_event(u)
			_tap_at = Vector2.INF
		_down_t = -1.0
		return false
	if _down_t < 0.0:
		_down_t = _t
	if _tap_at != Vector2.INF:
		# the finger lifts a frame after it pressed (the tap's handler runs between frames)
		var u := InputEventScreenTouch.new()
		u.index = 1
		u.pressed = false
		u.position = _tap_at
		Input.parse_input_event(u)
		_tap_at = Vector2.INF
		return true
	if _t - _down_t < _down_wait:
		return true
	var kind := str(_downs[0]) if not _downs.is_empty() else "give_up"
	if kind == "ad" and not BOT.ad_offered(rs):
		kind = "give_up"
	var btn = rs.get("_debug_btn2") if kind == "debug" else (rs.get("_ad_btn") if kind == "ad" else null)
	if _down_tap and btn is Control and (btn as Control).is_visible_in_tree():
		var r: Rect2 = (btn as Control).get_global_rect()
		var k := float(root.size.x) / maxf(root.get_visible_rect().size.x, 1.0)
		_tap_at = r.get_center() * k
		var e := InputEventScreenTouch.new()
		e.index = 1
		e.pressed = true
		e.position = _tap_at
		Input.parse_input_event(e)
		_say("  Down! at %.1f s: %s (a tap)" % [float(_run.get("play_clock")), kind])
		_downs.pop_front()
		_down_t = -1.0
		return true
	if not _downs.is_empty():
		_downs.pop_front()
	_down_t = -1.0
	_say("  Down! at %.1f s: %s" % [float(_run.get("play_clock")), kind])
	rs._decide(kind)
	return true


## `give` handed over by the level-up's debug hand at the first card screen (a decision the recording keeps).
func _give_once() -> void:
	if _give == "" or _given:
		return
	var cs = _game.get("cards")
	if cs == null or not cs.visible or (cs.get("_offer") as Array).is_empty():
		return
	_given = true
	var reg := root.get_node_or_null("Registry")
	var items: Array = []
	for id in _give.split(",", false):
		var kind := "passive"
		if reg != null and reg.weapon(id) != null:
			kind = "weapon"
		items.append([kind, id, 1])
	cs._open_debug()
	cs.get("_debug").give_list(items)
	_say("  gave %s at %.1f s" % [_give, float(_run.get("play_clock"))])


## The bot wrote the thumb it wants into PlayerInput (BotLegs: wants_move, origin, touch_pos); that is put back and sent as
## the touch events that would make it (in window pixels; Godot hands them to the game before the next frame).
func _finger_from_bot(inp, was: Array) -> void:
	var want: bool = inp.wants_move
	var at: Vector2 = inp.touch_pos
	var from: Vector2 = inp.origin
	inp.wants_move = was[0]
	inp.origin = was[1]
	inp.touch_pos = was[2]
	var k := float(root.size.x) / maxf(root.get_visible_rect().size.x, 1.0)
	if want and not _finger_down:
		var e := InputEventScreenTouch.new()
		e.index = 0
		e.pressed = true
		e.position = from * k
		Input.parse_input_event(e)
		_finger_down = true
		_finger_at = from
	if want and _finger_down and at.distance_to(_finger_at) > 0.5:
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = at * k
		d.relative = (at - _finger_at) * k
		Input.parse_input_event(d)
		_finger_at = at
	elif not want and _finger_down:
		var u := InputEventScreenTouch.new()
		u.index = 0
		u.pressed = false
		u.position = _finger_at * k
		Input.parse_input_event(u)
		_finger_down = false


func _store_recording(rr: Node) -> void:
	_done = true
	var json := str(rr.get("last_json"))
	var f := FileAccess.open(_out, FileAccess.WRITE)
	if f:
		f.store_string(json)
		f.close()
	# pass 116 (lane REPLAY): the run's events as the recording met them (the Elites, their modifiers, the specials, ...)
	var ef := FileAccess.open(_out + ".events.json", FileAccess.WRITE)
	if ef:
		ef.store_string(JSON.stringify(rr.get("event_log")))
		ef.close()
	var h = JSON.parse_string(json)
	var wall := float(Time.get_ticks_msec() - _t0_ms) / 1000.0
	_say("RECORDED %s: %d frames, play %.1f s, %d decisions, %d taps, %d checks, %d KB (frames %d runs, stick %d changes) wall %.1f s" % [
		_out, int(h["frames_n"]), float(h["play_s"]), (h["decisions"] as Array).size(), (h["taps"] as Array).size(),
		(h["checks"] as Array).size(), json.length() / 1024, int(h["frames_runs"]), int(h["stick_n"]), wall])
	quit(0)


func _end_report(why: String) -> void:
	_done = true
	var rr := _rr()
	var rep := {"why": why, "wall_s": float(Time.get_ticks_msec() - _t0_ms) / 1000.0}
	if rr:
		for k in ["frame", "frames_n", "checks_ok", "checks_bad", "drift_frame", "late_decisions", "assisted", "hero_fixes",
				"corpse_holds", "down_parts", "ended_early", "screens_netted"]:
			rep[k] = rr.get(k)
		var pl = _game.get("player") if _game != null and is_instance_valid(_game) else null
		if pl != null:
			rep["dead"] = bool(pl.get("dead"))
			rep["hp"] = float(pl.get("hp"))
		rep["revives_used"] = int(_run.get("revives_used"))
		rep["drift_what"] = rr.get("drift_what")
		rep["dropped"] = rr.get("dropped_decisions")
		rep["notes"] = rr.get("notes")
		rep["events"] = rr.get("event_log")
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(rep, "  "))
			f.close()
	_say("REPLAY %s: frames %s/%s checks ok %s bad %s drift_frame %s late %s dropped %d hero_fixes %s wall %.1f s" % [why, str(rep.get("frame")),
		str(rep.get("frames_n")), str(rep.get("checks_ok")), str(rep.get("checks_bad")), str(rep.get("drift_frame")),
		str(rep.get("late_decisions")), (rep.get("dropped", []) as Array).size(), str(rep.get("hero_fixes")), float(rep["wall_s"])])
	if rr and int(rr.get("checks_bad")) > 0:
		_say("first difference: " + JSON.stringify(rr.get("drift_what")))
	quit(0)
