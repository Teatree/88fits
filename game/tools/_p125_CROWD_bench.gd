## Pass 125: what a crowd of N costs, compiled or by the script, at each steering cadence: the god-mode Drifter with no weapon
## walks perf_late's S in the first stage's look, the director held, a mix of walkers topped up to `n` from a ring 19-24 m out;
## `settle` seconds, then `hold` seconds measured: wall ms a frame (mean, p50, p95), the game's Perf keys, draw calls.
##   bash tools/godot.sh --audio-driver Dummy --resolution 504x1122 --fixed-fps 60 --disable-vsync --path D:/_projects/88fits/game --script res://tools/_p125_CROWD_bench.gd -- n=300 every=2 far=4 [native=0] [mix=skeleton:4,goblin:3] [settle=6] [hold=12] [out=<file>]
## A line per run on stdout (and appended to out=). Never touches Settings or the save. Bounded: 300 s of wall time.
extends SceneTree

var _n := 300
var _every := 2
var _far := 4
var _settle := 6.0
var _hold := 12.0
var _out := ""
var _mix: Array = [["skeleton", 4], ["goblin", 3], ["red_goblin", 2], ["lesser_scorpion", 2], ["werewolf", 1], ["dust_mummy", 1], ["spit_cactus", 1]]
var _game: Node
var _run: Node
var _perf
var _t := 0.0
var _walk := 0.0
var _phase := 0
var _next_spawn := 0
var _rng := RandomNumberGenerator.new()
var _pool: Array = []
var _times := PackedFloat32Array()
var _last := 0
var _wall0 := 0
var _draws := 0.0
var _frames := 0
var _alive := 0.0
var _vp: RID


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"n": _n = int(kv[1])
			"every": _every = int(kv[1])
			"far": _far = int(kv[1])
			"settle": _settle = float(kv[1])
			"hold": _hold = float(kv[1])
			"out": _out = kv[1]
			"mix":
				_mix = []
				for p in kv[1].split(","):
					var q := p.split(":")
					_mix.append([q[0], int(q[1]) if q.size() > 1 else 1])
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	_wall0 = Time.get_ticks_msec()
	_rng.seed = 11
	for m: Array in _mix:
		for _k in range(int(m[1])):
			_pool.append(str(m[0]))
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "peashooter", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	root.get_node("Save").data["runs_started"] = 1
	_run = root.get_node("Run")
	_perf = load("res://core/systems/Perf.gd")
	_vp = root.get_viewport_rid()
	change_scene_to_file("res://game/Game.tscn")
	process_frame.connect(_tick)


func _tick() -> void:
	if Time.get_ticks_msec() - _wall0 > 300000:
		print("p125bench: watchdog")
		quit(1)
		return
	if _game == null:
		var g = current_scene
		if g == null or not g.has_method("open_pause") or g.get("player") == null or g.get("director") == null:
			return
		_game = g
		_game.player.god = true
		_game.director.running = false
		_run.debug_clear_items()
		_run.rebuild_sheets()
		var em = _game.enemies
		em.kill_all(false)
		if _n > em.pool_max:
			em.grow_pool(_n + 8)
		em.steer_every = _every
		em.steer_far_every = _far
		_last = Time.get_ticks_usec()
		return
	var dt: float = root.get_process_delta_time()
	_t += dt
	_walk += dt
	var now := Time.get_ticks_usec()
	var em = _game.enemies
	_close_modals()
	var inp = _game.player.input
	if inp and not _game.paused:
		inp.wants_move = true
		inp.origin = Vector2(216, 500)
		inp.touch_pos = inp.origin + Vector2(sin(_walk * 0.5) * 90.0, -110.0 * (1.0 if fmod(_walk, 20.0) < 10.0 else -1.0))
	_top_up(em)
	if _phase == 0 and _t > _settle:
		_phase = 1
		_perf.report()
		_times.clear()
		_frames = 0
		_alive = 0.0
		_draws = 0.0
		_t = 0.0
	elif _phase == 1:
		_times.append(float(now - _last) / 1000.0)
		_frames += 1
		_alive += float(em.count_alive)
		_draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		if _t > _hold:
			_report(em)
			quit(0)
			return
	_last = Time.get_ticks_usec()


func _close_modals() -> void:
	if _game.cards and _game.cards.visible and not _game.cards._offer.is_empty() and not _game.cards._picking:
		_game.cards._pick(_game.cards._offer[0])
	if _game.get("resume_gate") and _game.resume_gate and _game.resume_gate.visible:
		_game.resume_gate.tap()


func _top_up(em) -> void:
	var c: Vector3 = _game.player.global_position
	var made := 0
	while em.count_alive < _n and made < 24:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(19.0, 24.0)
		var p := Vector3(c.x + cos(a) * r, 0.0, c.z + sin(a) * r)
		p.y = _game.map.height_at(p.x, p.z)
		var id: String = _pool[_next_spawn % _pool.size()]
		_next_spawn += 1
		if em.spawn(id, p) < 0:
			break
		made += 1


func _report(em) -> void:
	var s := _times.duplicate()
	s.sort()
	var total := 0.0
	for v in s:
		total += v
	var mean := total / float(maxi(s.size(), 1))
	var r: Dictionary = _perf.report()
	var parts := []
	var keys: Array = r.keys()
	keys.sort_custom(func(x, y): return (float(r[x]) if r[x] is float else 0.0) > (float(r[y]) if r[y] is float else 0.0))
	var timed := 0.0
	for k in keys:
		if k in ["frames", "worst_ms", "slow", "slow_log"]:
			continue
		timed += float(r[k])
		if parts.size() < 16:
			parts.append("%s %.2f" % [k, float(r[k])])
	var line := "p125bench: n=%d every=%d far=%d native=%s alive %.0f | %.2f ms/frame (p50 %.2f, p95 %.2f) | timed %.2f: %s | draws %.0f" % [_n, int(em.steer_every), int(em.steer_far_every), str(em.native_on()), _alive / float(maxi(_frames, 1)), mean, s[s.size() / 2], s[int(s.size() * 0.95)], timed, ", ".join(parts), _draws / float(maxi(_frames, 1))]
	print(line)
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.READ_WRITE)
		if f == null:
			f = FileAccess.open(_out, FileAccess.WRITE)
		else:
			f.seek_end()
		if f:
			f.store_line(line)
			f.close()
