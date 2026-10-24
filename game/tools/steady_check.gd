## Pass 102 (lane STEADY): the whole game slows together when a frame overruns. Plays one run (the Drifter, the
## Revolver, god mode, the director running) through phases that load the frame differently with busy-waits (one per
## drawn frame, one per 60 Hz world step), and in each measures, against the world's own time (physics steps / 60):
## the game's delta summed, the run clock (Run.elapsed), the rules' clock (Run.rule_seconds), the Revolver's fire
## period (each fire's play-clock stamp; its cooldown restarts on the frame it fires, so the period rounds up to a whole
## frame), and creatures walking in from a ring 26 m out (metres a world second); also the steps a frame and the wall
## frame time. Passes (exit 0) when every phase's clocks match the world within a step, the fire period is its cooldown
## within a frame and the walk speed matches the free phase's within 4%, steps a frame never pass the cap and the
## overloaded phase's frames stay bounded (no spiral).
##   bash tools/godot.sh --headless --path D:/_projects/88fits/game --script res://tools/steady_check.gd -- [phases=free,30,over] [hold=12] [out=<dir>]
## A phase: free (no load), 30 (a 31 ms frame: two steps a frame, at the cap but under it), over (a 30 ms frame and
## 10 ms a world step: the cap bites, the world runs at about two thirds), spiral (over with steps=8: the old catch-up),
## or frame:<ms>/tick:<ms>[/steps:<n>]. Watchdog: quits (exit 2) after 400 s of wall time. Never touches the save
## (tools/godot.sh keeps the PC save aside; the launch file only).
extends SceneTree

const PRESETS := {"warm": {"frame": 0.0, "tick": 0.0}, "free": {"frame": 0.0, "tick": 0.0}, "30": {"frame": 31.0, "tick": 0.0},
	"over": {"frame": 30.0, "tick": 10.0}, "spiral": {"frame": 30.0, "tick": 10.0, "steps": 8}}
const RING := 26.0
const WALKERS := 10
const ANCHORS := 4
const WALK_WINDOW := 3.0

var _phases: Array = ["free", "30", "over"]
var _hold := 12.0
var _settle := 1.5
var _out := "res://../tools/dl/p102/STEADY"
var _game: Node
var _run: Node
var _wall0 := 0
var _pi := -1
var _cfg := {}
var _t := 0.0          # game seconds in the phase (the frames' deltas)
var _phys := 0         # world steps this frame
var _steps_sum := 0
var _steps_max := 0
var _frames := 0
var _frame_us := 0
var _wall_ms: Array = []
var _m := {}
var _walk0 := {}       # walker index -> start distance
var _walk_w0 := 0
var _walk_done := false
var _cd_last := {}     # weapon id -> cooldown_left last frame
var _fires: Array = []
var _results: Array = []
var _fail: Array = []
var _done := false


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("phases="):
			_phases = Array(a.substr(7).split(","))
		elif a.begins_with("hold="):
			_hold = float(a.substr(5))
		elif a.begins_with("out="):
			_out = a.substr(4)
	# a warm-up phase first, never judged: the run's first seconds walk the creatures slower (the start's own state)
	_phases.push_front("warm")
	physics_frame.connect(_on_physics)
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	_wall0 = Time.get_ticks_msec()
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	root.get_node("Save").data["runs_started"] = 1
	_run = root.get_node("Run")
	change_scene_to_file("res://game/Game.tscn")
	process_frame.connect(_tick)


func _spin(ms: float) -> void:
	if ms <= 0.0:
		return
	var t := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t < int(ms * 1000.0):
		pass


func _on_physics() -> void:
	_phys += 1
	if _pi >= 0:
		_spin(float(_cfg.get("tick", 0.0)))


func _tick() -> void:
	if _done:
		return
	if Time.get_ticks_msec() - _wall0 > 400000:
		print("steady_check: watchdog at 400 s")
		_finish(2)
		return
	var steps := _phys
	_phys = 0
	var now := Time.get_ticks_usec()
	var wall := float(now - _frame_us) / 1000.0 if _frame_us > 0 else 0.0
	_frame_us = now
	if _game != null and (not is_instance_valid(_game) or _game.get("enemies") == null or _game.get("director") == null):
		print("steady_check: the game lost its enemy manager or director (a script failed to compile?)")
		_finish(2)
		return
	if _game == null:
		if Time.get_ticks_msec() - _wall0 > 60000:
			print("steady_check: no playable game after 60 s (a script failed to compile?)")
			_finish(2)
			return
		var g = current_scene
		if g == null or not g.has_method("open_pause") or g.get("player") == null or g.get("director") == null or g.get("enemies") == null:
			return
		if g.get("spawning") or not bool(g.get("_run_started")):
			return
		_game = g
		_game.player.god = true
		_next_phase()
		return
	_keep_playing()
	var dt := root.get_process_delta_time()
	_t += dt
	if _m.is_empty():
		if _t >= _settle:
			_mark()
		_spin(float(_cfg.get("frame", 0.0)))
		return
	_frames += 1
	_steps_sum += steps
	_steps_max = maxi(_steps_max, steps)
	_wall_ms.append(wall)
	_count_fires()
	_walk()
	if _t >= float(_m["t"]) + _hold:
		_report()
		_next_phase()
		return
	_spin(float(_cfg.get("frame", 0.0)))


func _keep_playing() -> void:
	var inp = _game.player.input
	if inp:
		inp.wants_move = false
	for nm in ["cards", "chest_screen", "stranger_screen", "structure_shop", "totem_screen", "resume_gate", "portal_dialog"]:
		var s = _game.get(nm)
		if s != null and is_instance_valid(s) and s.visible:
			if nm == "cards" and not s._offer.is_empty() and not s._picking:
				s._pick(s._offer[0])
			elif nm == "chest_screen" and not s._spinning:
				s._finish(false)
			elif nm == "stranger_screen" or nm == "structure_shop":
				s._finish(false)
			elif nm == "totem_screen" and not s._done:
				var tp: Array = s.planks()
				if not tp.is_empty():
					s._pick(tp[0])
			elif nm == "resume_gate":
				s.tap()
			elif nm == "portal_dialog":
				s.visible = false
	_run.xp = 0.0


func _next_phase() -> void:
	_pi += 1
	if _pi >= _phases.size():
		_finish(0 if _fail.is_empty() else 1)
		return
	var name: String = str(_phases[_pi])
	_cfg = PRESETS.get(name, {}).duplicate()
	if _cfg.is_empty():
		for part in name.split("/"):
			var kv := part.split(":")
			if kv.size() == 2:
				_cfg[kv[0]] = float(kv[1])
	_cfg["name"] = name
	# the game's own cap (Game.CATCH_UP_STEPS, set by Game._ready) unless the phase names one
	Engine.max_physics_steps_per_frame = int(_cfg.get("steps", int(_game.get("CATCH_UP_STEPS"))))
	_t = 0.0
	_frames = 0
	_steps_sum = 0
	_steps_max = 0
	_wall_ms = []
	_m = {}
	_walk0 = {}
	_walk_done = false
	_fires = []
	_cd_last = {}
	var em = _game.enemies
	em.kill_all(false)
	var hero: Vector3 = _game.player.global_position
	for k in range(ANCHORS):
		var a := TAU * float(k) / float(ANCHORS)
		var i: int = em.spawn("dust_mummy", hero + Vector3(cos(a), 0.0, sin(a)) * 3.5)
		if i >= 0:
			em.hp[i] = 1.0e12
			em.max_hp[i] = 1.0e12
	for k in range(WALKERS):
		var a := TAU * (float(k) + 0.5) / float(WALKERS)
		var i: int = em.spawn("dust_mummy", hero + Vector3(cos(a), 0.0, sin(a)) * RING)
		if i >= 0:
			em.hp[i] = 1.0e12
			em.max_hp[i] = 1.0e12
			_walk0[i] = -1.0


func _mark() -> void:
	_m = {"world": Engine.get_physics_frames(), "clock": float(_run.elapsed), "rule": float(_run.rule_seconds()),
		"play": float(_run.play_clock), "wall": Time.get_ticks_usec(), "t": _t}
	var hero: Vector3 = _game.player.global_position
	for i in _walk0.keys():
		_walk0[i] = _flat(_game.enemies.pos[i] - hero)
	_walk_w0 = Engine.get_physics_frames()


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _count_fires() -> void:
	for id in _game._behaviors.keys():
		var b = _game._behaviors[id]
		var cd := float(b.cooldown_left)
		if _cd_last.has(id) and cd > float(_cd_last[id]) + 0.2 and id == "revolver":
			_fires.append({"play": float(_run.play_clock), "cd": float(b.stat("cooldown", 1.0))})
		_cd_last[id] = cd


func _walk() -> void:
	if _walk_done or _m.is_empty():
		return
	if _t < float(_m["t"]) + WALK_WINDOW:
		return
	_walk_done = true
	var hero: Vector3 = _game.player.global_position
	var world_s := float(Engine.get_physics_frames() - _walk_w0) / float(Engine.physics_ticks_per_second)
	var sum := 0.0
	var frac := 0.0
	var n := 0
	for i in _walk0.keys():
		var em = _game.enemies
		if em.alive[i] != 1:
			continue
		var d := _flat(em.pos[i] - hero)
		if d < 8.0:
			continue
		sum += (float(_walk0[i]) - d) / maxf(world_s, 0.001)
		# its own speed (each creature rolls its own): the share of it walked a world second
		frac += (float(_walk0[i]) - d) / maxf(world_s * float(em.speed[i]), 0.001)
		n += 1
	_m["walk"] = sum / float(maxi(n, 1))
	_m["walk_frac"] = frac / float(maxi(n, 1))
	_m["walkers"] = n


func _report() -> void:
	var hz := float(Engine.physics_ticks_per_second)
	var world_s := float(Engine.get_physics_frames() - int(_m["world"])) / hz
	var game_s := _t - float(_m["t"])
	var clock_s := float(_run.elapsed) - float(_m["clock"])
	var rule_s := float(_run.rule_seconds()) - float(_m["rule"])
	var wall_s := float(Time.get_ticks_usec() - int(_m["wall"])) / 1.0e6
	var period := 0.0
	var cd := 0.0
	if _fires.size() >= 3:
		period = (float(_fires[-1]["play"]) - float(_fires[0]["play"])) / float(_fires.size() - 1)
		cd = float(_fires[-1]["cd"])
	var ws: Array = _wall_ms.duplicate()
	ws.sort()
	var mean := 0.0
	for v in ws:
		mean += float(v)
	mean /= float(maxi(ws.size(), 1))
	var p95: float = float(ws[clampi(int(ceil(0.95 * ws.size())) - 1, 0, ws.size() - 1)]) if not ws.is_empty() else 0.0
	var dt_mean := game_s / float(maxi(_frames, 1))
	var r := {"phase": _cfg["name"], "cap": Engine.max_physics_steps_per_frame, "frame_busy": _cfg.get("frame", 0.0), "tick_busy": _cfg.get("tick", 0.0),
		"frames": _frames, "wall_s": snappedf(wall_s, 0.001), "world_s": snappedf(world_s, 0.001), "game_s": snappedf(game_s, 0.001),
		"clock_s": snappedf(clock_s, 0.001), "rule_s": snappedf(rule_s, 0.001), "world_speed": snappedf(world_s / maxf(wall_s, 0.001), 0.001),
		"steps_mean": snappedf(float(_steps_sum) / float(maxi(_frames, 1)), 0.01), "steps_max": _steps_max,
		"frame_ms": snappedf(mean, 0.1), "frame_p95": snappedf(p95, 0.1), "frame_max": snappedf(float(ws[-1]) if not ws.is_empty() else 0.0, 0.1),
		"dt_ms": snappedf(dt_mean * 1000.0, 0.01), "fires": _fires.size(), "fire_period": snappedf(period, 0.001), "cooldown": snappedf(cd, 0.001),
		"walk_mps": snappedf(float(_m.get("walk", 0.0)), 0.001), "walk_frac": snappedf(float(_m.get("walk_frac", 0.0)), 0.001), "walkers": int(_m.get("walkers", 0))}
	_results.append(r)
	if str(_cfg["name"]) == "warm":
		r["ok"] = true
		print("steady_check: %s" % JSON.stringify(r))
		return
	var ref: Dictionary = _results[1] if _results.size() > 1 else r
	var step := 1.0 / hz
	var bad: Array = []
	var cap := Engine.max_physics_steps_per_frame
	if absf(game_s - world_s) > 2.0 * step + 0.02 * world_s:
		bad.append("game time %.3f s vs world %.3f s" % [game_s, world_s])
	if absf(rule_s - game_s) > 0.05:
		bad.append("rules' clock %.3f s vs game %.3f s" % [rule_s, game_s])
	if absf(clock_s - game_s) > 0.05:
		bad.append("run clock %.3f s vs game %.3f s" % [clock_s, game_s])
	if _fires.size() < 3:
		bad.append("only %d fires" % _fires.size())
	elif period < cd - 0.002 or period > cd + dt_mean + 0.006:
		bad.append("fire period %.3f s for a %.3f s cooldown (frames of %.1f ms)" % [period, cd, dt_mean * 1000.0])
	if _steps_max > cap:
		bad.append("%d steps in one frame past the cap %d" % [_steps_max, cap])
	if int(_m.get("walkers", 0)) < 3:
		bad.append("only %d walkers measured" % int(_m.get("walkers", 0)))
	elif float(ref["walk_frac"]) > 0.0 and absf(float(r["walk_frac"]) / float(ref["walk_frac"]) - 1.0) > 0.04:
		bad.append("walked %.3f of its speed a world second vs the first phase's %.3f" % [float(r["walk_frac"]), float(ref["walk_frac"])])
	if str(_cfg["name"]) == "over" and cap <= 3:
		# no spiral: the frame is the work of at most `cap` steps (30 ms + cap x 10 ms + the game's own), never more
		var bound := float(_cfg.get("frame", 0.0)) + float(cap) * float(_cfg.get("tick", 0.0)) + 25.0
		if p95 > bound:
			bad.append("frames p95 %.1f ms past %.1f ms" % [p95, bound])
	r["ok"] = bad.is_empty()
	if not bad.is_empty():
		r["why"] = bad
		_fail.append("%s: %s" % [_cfg["name"], "; ".join(bad)])
	print("steady_check: %s" % JSON.stringify(r))


func _finish(code: int) -> void:
	if _done:
		return
	_done = true
	Engine.max_physics_steps_per_frame = int(ProjectSettings.get_setting("physics/common/max_physics_steps_per_frame", 8))
	var dir := ProjectSettings.globalize_path(_out) if _out.begins_with("res://") else _out
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("steady_check.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_results, "\t"))
		f.close()
	for r in _results:
		print("steady_check: %-6s cap %d  world x%.2f  frame %5.1f ms (p95 %5.1f, max %5.1f)  steps %.2f (max %d)  game/world %.3f/%.3f  clock %.3f  rules %.3f  fire %.3f s (cd %.3f, %d)  walk %.3f m/s, %.3f of its speed (%d)  %s" % [
			r["phase"], r["cap"], r["world_speed"], r["frame_ms"], r["frame_p95"], r["frame_max"], r["steps_mean"], r["steps_max"], r["game_s"], r["world_s"], r["clock_s"], r["rule_s"],
			r["fire_period"], r["cooldown"], r["fires"], r["walk_mps"], r["walk_frac"], r["walkers"], "ok" if r.get("ok", false) else "FAIL"])
	if not _fail.is_empty():
		print("steady_check: FAIL " + " | ".join(_fail))
	elif code == 0:
		print("steady_check: PASS")
	quit(code)
