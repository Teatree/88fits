## Pass 101, lane CROWD: the off-screen steer's proof in play (A/B in one build: EnemyManager.steer_far_every 2 = every
## creature every 2nd tick as before pass 101, 4 = off the screen every 4th). Stage 3's numbers, the hero in god mode
## with no weapon (nothing is killed, his build never grows), the director held. Every `every` s a wave of `wave`
## creatures of stage 3's mix comes up `r0`..`r1` m from the hero (off the screen: a phone's 504 x 1122 view), and every
## creature that comes within `reach` m of him is taken away (counted), so the crowd never piles up on him. Each arm
## plays the same waves (one seed per rep), the arms interleaved (2, 4, 2, 4 ...). Scenarios:
##   open   the hero standing in the open middle of the map
##   rocks  standing at the rockiest clear spot of the map (the crowd comes past the rocks and cacti)
##   wall   standing 6 m in from the fort wall (the waves come up along it and slide along it)
##   walk   walking a slow S in the middle (the crowd chases)
##   pack   standing; each wave a tight pack (a 3.5 m disc) at one spot of the ring
##   ring   standing; each wave a ring of `wave` round him at 18 m (the map's ring rows)
## fars: 2, 4, and 4u (the far steer without far_push_scale)
## Measured: the time from a creature's spawn to its coming within `reach` (median, mean, p90, how many came and how
## many never did by the phase's end), how fast creatures not drawn close in on him (m/s, sampled each second over the
## walking ones), the stuck ones (walking, wanting to move, farther than reach, moved under 0.3 m in 2 s: by a rock or
## cactus, at the wall, or in the crowd) in creature-seconds a minute, the share not drawn, and enemies.sim.
##   bash tools/godot.sh --headless --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/_p101_CROWD_steer.gd -- tag=b [scen=open,rocks,wall,walk] [fars=2,4] [reps=3] [secs=40] [wave=40] [every=5] [r0=20] [r1=32] [reach=4]
## Results: tools/dl/p101/CROWD/steer_<tag>.txt (+ .json). Watchdog 3000 s. Never touches Settings or the save.
extends SceneTree

const MIX := [["skeleton", 4], ["skeleton_knight", 3], ["hellhound", 3], ["imp", 3], ["dust_mummy", 2], ["fire_ant", 2],
	["horned_toad", 2], ["dust_shaman", 1], ["werewolf", 1], ["armadillo", 1], ["buckshot_dwarf", 1], ["hammer_giant", 1],
	["bull_beetle", 1], ["spit_cactus", 1]]

var _scens: Array = ["open", "rocks", "wall", "walk"]
var _fars: Array = ["2", "4"]
var _reps := 3
var _secs := 40.0
var _wave := 40
var _every := 5.0
var _r0 := 20.0
var _r1 := 32.0
var _reach := 4.0
var _tag := "b"
var _game: Node
var _run: Node
var _perf
var _t := 0.0
var _phases: Array = []
var _pi := -1
var _pt := 0.0
var _next_wave := 0.0
var _C: Dictionary = {}
var _out: Array = []
var _rows: Array = []
var _rng := RandomNumberGenerator.new()
var _pool: Array = []
var _born := {}
var _hist := {}
var _reach_times: Array = []
var _acc := {}
var _samples := 0
var _sec_t := 0.0
var _spot := Vector3.ZERO
var _walk_t := 0.0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"scen": _scens = Array(kv[1].split(","))
			"fars": _fars = Array(kv[1].split(","))
			"reps": _reps = int(kv[1])
			"secs": _secs = float(kv[1])
			"wave": _wave = int(kv[1])
			"every": _every = float(kv[1])
			"r0": _r0 = float(kv[1])
			"r1": _r1 = float(kv[1])
			"reach": _reach = float(kv[1])
			"tag": _tag = kv[1]
	for m in MIX:
		for k in range(int(m[1])):
			_pool.append(m[0])
	for sc in _scens:
		for r in range(_reps):
			for f in _fars:
				_phases.append({"scen": sc, "far": f, "rep": r})
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "peashooter", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	root.get_node("Save").data["runs_started"] = 1
	_run = root.get_node("Run")
	_perf = load("res://core/systems/Perf.gd")
	# the phone's view, as the run sim plays it (sim_run.gd): what is drawn depends on it
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.size = Vector2i(504, 1122)
	change_scene_to_file("res://game/Game.tscn")
	process_frame.connect(_tick)


func _tick() -> void:
	var dt := root.get_process_delta_time()
	_t += dt
	if _t > 3000.0:
		_log("watchdog: quit at 3000 s")
		_finish()
		return
	if _game == null:
		var g = current_scene
		if g == null or not g.has_method("open_pause") or g.player == null or g.get("director") == null:
			return
		_game = g
		_game.player.god = true
		_C = _game.enemies.get_script().get_script_constant_map()
		var d = _game.director
		d.running = false
		_run.stage = 2
		_run.elapsed = float(d.timeline.stage_start(2)) + float(d.timeline.stage_len(2)) / 3.0
		d._apply_mults()
		_run.debug_clear_items()
		_run.rebuild_sheets()
		_game.enemies.kill_all(false)
		_log("setup: view %s, reach %.1f m, waves of %d every %.1f s at %.0f..%.0f m, %d phases of %.0f s" % [str(root.get_visible_rect().size), _reach, _wave, _every, _r0, _r1, _phases.size(), _secs])
		return
	_keep_playing(dt)
	if _pi < 0:
		if _t > 2.0:
			_next()
		return
	_pt += dt
	_track()
	if _pt >= _next_wave and _pt < _secs - 8.0:
		_next_wave += _every
		_spawn_wave()
	_sec_t += dt
	if _sec_t >= 1.0:
		_sec_t -= 1.0
		_sample()
	if _pt >= _secs:
		_report(_phases[_pi])
		_next()


func _next() -> void:
	_pi += 1
	if _pi >= _phases.size():
		_finish()
		return
	var ph: Dictionary = _phases[_pi]
	var em = _game.enemies
	em.steer_far_every = int(str(ph["far"]).trim_suffix("u"))
	# "4u": the far steer without far_push_scale (the A/B of the push's hold)
	if "far_push_scale" in em:
		em.far_push_scale = not str(ph["far"]).ends_with("u")
	em.kill_all(false)
	_pt = 0.0
	_next_wave = 0.5
	_walk_t = 0.0
	_sec_t = 0.0
	_rng.seed = 1000 + int(ph["rep"]) * 17 + _scens.find(ph["scen"]) * 101
	_spot = Vector3.ZERO
	match str(ph["scen"]):
		"wall":
			_spot = Vector3(float(em.arena_radius) - 6.0, 0, 0)
		"rocks":
			_spot = _rocky_spot()
	_game.player.global_position = Vector3(_spot.x, _game.map.height_at(_spot.x, _spot.z), _spot.z)
	_game.player.velocity = Vector3.ZERO
	if _game.camera and _game.camera.has_method("snap_to"):
		_game.camera.snap_to(_game.player)
	_born = {}
	_hist = {}
	_reach_times = []
	_acc = {}
	_samples = 0
	_perf.report()


## The point of the map with the most obstacle circles within 12 m of it (on a 6 m lattice inside the arena), clear itself.
func _rocky_spot() -> Vector3:
	var em = _game.enemies
	var best := Vector3.ZERO
	var best_n := -1
	var lim: float = float(em.arena_radius) - 14.0
	var x := -lim
	while x <= lim:
		var z := -lim
		while z <= lim:
			if Vector2(x, z).length() <= lim:
				var n := 0
				var clear := true
				for o: Vector3 in em.obstacles:
					var dd := Vector2(o.x - x, o.y - z).length()
					if dd < 12.0:
						n += 1
					if dd < o.z + 1.5:
						clear = false
				if clear and n > best_n:
					best_n = n
					best = Vector3(x, 0, z)
			z += 6.0
		x += 6.0
	return best


func _spawn_wave() -> void:
	var em = _game.enemies
	var hp: Vector3 = _game.player.global_position
	var scen := str(_phases[_pi]["scen"])
	var pa := _rng.randf() * TAU
	var pr := _rng.randf_range(_r0, _r1)
	for k in range(_wave):
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(_r0, _r1)
		var id := str(_pool[_rng.randi() % _pool.size()])
		var at := hp + Vector3(cos(a) * r, 0, sin(a) * r)
		if scen == "pack":
			# a tight pack (a disc of 3.5 m) at one spot of the ring
			var q := Vector2.from_angle(a) * sqrt(_rng.randf()) * 3.5
			at = hp + Vector3(cos(pa) * pr + q.x, 0, sin(pa) * pr + q.y)
		elif scen == "ring":
			# a ring round him at 18 m, as the map's ring rows spawn
			var ra := TAU * float(k) / float(_wave)
			at = hp + Vector3(cos(ra) * 18.0, 0, sin(ra) * 18.0)
		var i: int = em.spawn(id, at, null, 1.0, 1.0)
		if i >= 0:
			_born[em.serial[i]] = _pt


func _keep_playing(dt: float) -> void:
	_close_modals()
	var inp = _game.player.input
	if inp == null or _game.paused:
		return
	var walk := _pi >= 0 and str(_phases[_pi]["scen"]) == "walk"
	if walk:
		_walk_t += dt
		inp.wants_move = true
		inp.origin = Vector2(216, 500)
		inp.touch_pos = inp.origin + Vector2(sin(_walk_t * 0.5) * 50.0, -40.0 * (1.0 if fmod(_walk_t, 20.0) < 10.0 else -1.0))
	else:
		inp.wants_move = false
		if _pi >= 0:
			_game.player.global_position = Vector3(_spot.x, _game.player.global_position.y, _spot.z)


## Every frame: a creature within reach is counted (its time from its spawn) and taken away.
func _track() -> void:
	var em = _game.enemies
	var hp: Vector3 = _game.player.global_position
	for i in range(_C["MAX"]):
		if em.alive[i] == 0 or em.state[i] == _C["STATE_DYING"]:
			continue
		var d: Vector3 = em.pos[i] - hp
		d.y = 0.0
		if d.length() <= _reach:
			var sr: int = em.serial[i]
			if _born.has(sr):
				_reach_times.append(_pt - float(_born[sr]))
				_born.erase(sr)
			em._free(i)


func _add(k: String, v: float) -> void:
	_acc[k] = float(_acc.get(k, 0.0)) + v


## Each second: the approach speed of the creatures not drawn, the stuck ones, the share not drawn.
func _sample() -> void:
	var em = _game.enemies
	var hp: Vector3 = _game.player.global_position
	var obst: Array = em.obstacles
	var ar: float = em.arena_radius
	var far_n := 0
	var far_v := 0.0
	var all_v := 0.0
	var all_n := 0
	var undrawn := 0
	var alive := 0
	var near8 := 0
	var st := {"rock": 0, "wall": 0, "crowd": 0}
	var seen := {}
	for i in range(_C["MAX"]):
		if em.alive[i] == 0 or em.state[i] == _C["STATE_DYING"]:
			continue
		alive += 1
		var drawn: bool = em.drawn_vis[i] == 1
		if not drawn:
			undrawn += 1
		var sr: int = em.serial[i]
		seen[sr] = true
		var d: Vector3 = em.pos[i] - hp
		d.y = 0.0
		var dist := d.length()
		if dist <= 8.0:
			near8 += 1
		var walking: bool = em.state[i] == _C["STATE_MOVE"] and em.hidden[i] == 0 and em.held[i] == 0 and em.lift_h[i] <= 0.01 \
			and em.rise_t[i] >= 1.0 and em.slow_t[i] <= 0.0 and em.freeze_t[i] <= 0.0 and em.stun_t[i] <= 0.0
		var h: Array = _hist.get(sr, [])
		h.append([em.pos[i], dist, walking, drawn])
		if h.size() > 3:
			h.pop_front()
		_hist[sr] = h
		if h.size() >= 2 and walking and bool(h[-2][2]) and dist > _reach:
			var v := float(h[-2][1]) - dist
			all_v += v
			all_n += 1
			if not drawn and not bool(h[-2][3]):
				far_v += v
				far_n += 1
		if h.size() == 3 and walking and bool(h[0][2]) and dist > _reach and em.intent[i].length() > 0.5 * float(em.speed[i]):
			var p0: Vector3 = h[0][0]
			var moved := Vector2(em.pos[i].x - p0.x, em.pos[i].z - p0.z).length()
			if moved < 0.3:
				var why := "crowd"
				if Vector2(em.pos[i].x, em.pos[i].z).length() > ar - 3.5:
					why = "wall"
				else:
					for o: Vector3 in obst:
						if Vector2(em.pos[i].x - o.x, em.pos[i].z - o.y).length() < o.z + float(em.radius[i]) + 0.6:
							why = "rock"
							break
				st[why] = int(st[why]) + 1
	for k in _hist.keys():
		if not seen.has(k):
			_hist.erase(k)
	_samples += 1
	_add("alive", float(alive))
	_add("undrawn", float(undrawn))
	_add("near8", float(near8))
	_add("far_v_sum", far_v)
	_add("far_n", float(far_n))
	_add("all_v_sum", all_v)
	_add("all_n", float(all_n))
	for k in st.keys():
		_add("stuck_" + str(k), float(st[k]))


func _report(ph: Dictionary) -> void:
	var r: Dictionary = _perf.report()
	var s := maxf(float(_samples), 1.0)
	var mins := _secs / 60.0
	_reach_times.sort()
	var n := _reach_times.size()
	var med: float = _reach_times[n / 2] if n > 0 else 0.0
	var p90: float = _reach_times[int(n * 0.9)] if n > 0 else 0.0
	var mean := 0.0
	for x in _reach_times:
		mean += float(x)
	mean = mean / maxf(float(n), 1.0)
	var row := {"scen": ph["scen"], "far": ph["far"], "rep": ph["rep"], "reach_n": n, "never": _born.size(), "reach_med": med, "reach_mean": mean, "reach_p90": p90,
		"far_close_mps": float(_acc.get("far_v_sum", 0.0)) / maxf(float(_acc.get("far_n", 0.0)), 1.0),
		"all_close_mps": float(_acc.get("all_v_sum", 0.0)) / maxf(float(_acc.get("all_n", 0.0)), 1.0),
		"far_samples": _acc.get("far_n", 0.0), "alive": float(_acc.get("alive", 0.0)) / s, "undrawn_share": float(_acc.get("undrawn", 0.0)) / maxf(float(_acc.get("alive", 0.0)), 1.0),
		"stuck_rock_pm": float(_acc.get("stuck_rock", 0.0)) / mins, "stuck_wall_pm": float(_acc.get("stuck_wall", 0.0)) / mins, "stuck_crowd_pm": float(_acc.get("stuck_crowd", 0.0)) / mins,
		"near8": float(_acc.get("near8", 0.0)) / s, "enemies_sim_ms": float(r.get("enemies.sim", 0.0))}
	_rows.append(row)
	_log("[%s far %s rep %d] alive %.0f, not drawn %.0f%% | to %.0f m: %d came (%d never), median %.2f s, mean %.2f, p90 %.2f | closing: not drawn %.3f m/s (%d samples), all %.3f | stuck creature-s a minute: rock %.1f, wall %.1f, crowd %.1f | within 8 m %.1f | enemies.sim %.2f ms" % [
		ph["scen"], ph["far"], ph["rep"], row["alive"], 100.0 * float(row["undrawn_share"]), _reach, n, row["never"], med, mean, p90,
		row["far_close_mps"], int(row["far_samples"]), row["all_close_mps"], row["stuck_rock_pm"], row["stuck_wall_pm"], row["stuck_crowd_pm"],
		row["near8"], row["enemies_sim_ms"]])


func _log(s: String) -> void:
	print("p101steer: " + s)
	_out.append(s)


func _finish() -> void:
	# the arms' means over the reps, per scenario
	for sc in _scens:
		for f in _fars:
			var rs: Array = _rows.filter(func(x): return x["scen"] == sc and str(x["far"]) == str(f))
			if rs.is_empty():
				continue
			var keys := ["reach_n", "never", "reach_med", "reach_mean", "reach_p90", "far_close_mps", "all_close_mps", "undrawn_share", "stuck_rock_pm", "stuck_wall_pm", "stuck_crowd_pm", "near8", "enemies_sim_ms"]
			var parts: Array = []
			for k in keys:
				var m := 0.0
				for x in rs:
					m += float(x[k])
				parts.append("%s %.3f" % [k, m / float(rs.size())])
			_log("MEAN %s far %s (%d reps): %s" % [sc, str(f), rs.size(), ", ".join(parts)])
	var dir := "D:/_projects/88fits/tools/dl/p101/CROWD"
	DirAccess.make_dir_recursive_absolute(dir)
	var fl := FileAccess.open(dir + "/steer_%s.txt" % _tag, FileAccess.WRITE)
	if fl:
		fl.store_string("\n".join(_out) + "\n")
		fl.close()
	var j := FileAccess.open(dir + "/steer_%s.json" % _tag, FileAccess.WRITE)
	if j:
		j.store_string(JSON.stringify(_rows, " "))
		j.close()
	quit(0)


## The run's own screens closed through their own paths, as smoke_run does.
func _close_modals() -> void:
	if _game == null:
		return
	if _game.cards and _game.cards.visible and not _game.cards._offer.is_empty() and not _game.cards._picking:
		_game.cards._pick(_game.cards._offer[0])
	if _game.get("chest_screen") and _game.chest_screen and _game.chest_screen.visible and not _game.chest_screen._spinning:
		_game.chest_screen._finish(false)
	if _game.get("resume_gate") and _game.resume_gate and _game.resume_gate.visible:
		_game.resume_gate.tap()
	if _game.get("stranger_screen") and _game.stranger_screen and _game.stranger_screen.visible:
		_game.stranger_screen._finish(false)
	if _game.get("structure_shop") and _game.structure_shop and _game.structure_shop.visible:
		_game.structure_shop._finish(false)
	if _game.get("totem_screen") and _game.totem_screen and _game.totem_screen.visible and not _game.totem_screen._done:
		var tp: Array = _game.totem_screen.planks()
		if not tp.is_empty():
			_game.totem_screen._pick(tp[0])
	if _game.portal_dialog and _game.portal_dialog.visible:
		_game.portal_dialog.visible = false
		_game.portal_dialog.decided.emit(false)
