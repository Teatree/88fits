## Pass 112 (lane ENEMY; Garry: "the new bombs and harpoons take a second to load when they are first seen"): the frame
## times round the first bomb throw, the first harpoon and the first chain break of a run, with and without Warmup's
## creature warm-up (Warmup.SKIP_CREATURE_FX_META).
## The debug arena (its instant start runs Warmup as a run's spawn beam does), the hero in god mode with no weapons; once
## the warm-up is long done: 120 frames of the quiet arena (the baseline), a Spit Cactus 6.5 m off with its throw ready
## (frames from its wind-up to the blast), then a harpooner 13 m off (its throw, the hook-in) and its death (the break).
## Each event's frame and the slowest frame round it (from 2 frames before to 8 after) are printed, in ms of real time.
##   bash tools/godot.sh --audio-driver Dummy --resolution 504x1122 --path D:/_projects/88fits/game \
##       --script res://tools/_p112_ENEMY_firstuse.gd -- [nowarm=1] [out=<file.json>]
## Real frames (no --fixed-fps; --disable-vsync for the frames' own cost: every wait is in seconds). A watchdog quits after 120 s; every wait is bounded. The PC save is put back as it was.
extends SceneTree

var _nowarm := false
## parts=1: no creatures; the first throw's pieces timed one by one on the CPU, each followed by the frames it costs
var _parts := false
## prewarm=pit|tiny|visible|none (parts=1): a second warm draw of the shot kinds just before the first throw, to see which
## kind of draw keeps the throw's first frame smooth
var _prewarm := "none"
var _out := ""
var g
var _run
var _save
var _times: Array = []        # [frame index, ms]
var _parts_of: Dictionary = {}  # frame index -> {system: ms} over 0.3 ms
var _marks: Dictionary = {}   # event -> frame index
var _n := 0
var _last := 0
var _base_end := 0
## the game's own per-system microseconds (core/systems/Perf.gd) at the last frame, and each frame's share of them
var _perf_prev: Dictionary = {}
var _perf = null


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "nowarm=1":
			_nowarm = true
		elif a.begins_with("out="):
			_out = a.substr(4)
		elif a == "parts=1":
			_parts = true
		elif a.begins_with("prewarm="):
			_prewarm = a.substr(8)
	if _nowarm:
		# the warm-up as pass 111 had it: no creature shots, no frame minimum
		Engine.set_meta(&"warmup_skip_creature_fx", "all")
	create_timer(120.0, true, false, true).timeout.connect(func() -> void:
		print("p112_firstuse: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _tick() -> void:
	var now := Time.get_ticks_usec()
	if _perf == null:
		_perf = load("res://core/systems/Perf.gd")
	var cur: Dictionary = (_perf.usec as Dictionary).duplicate()
	var parts := {}
	for k in cur.keys():
		var d := int(cur[k]) - int(_perf_prev.get(k, 0))
		if d > 300:
			parts[k] = snappedf(float(d) / 1000.0, 0.1)
	_perf_prev = cur
	if _last > 0:
		_parts_of[_n] = parts
		# the frame's real time, and of it the scripts' process and physics time (Performance): a spike neither shows
		# is the renderer's (a shader compiled at its first draw)
		_times.append([_n, float(now - _last) / 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	_last = now
	_n += 1


func _frames(k: int) -> void:
	for j in range(k):
		await process_frame
		_tick()
		if g != null and g.player:
			g.player.velocity = Vector3.ZERO


## Frames for `secs` seconds of real time (the waits hold with vsync on or off).
func _secs(secs: float) -> void:
	var until := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < until:
		await _frames(1)


func _mark(name: String) -> void:
	if not _marks.has(name):
		_marks[name] = _n


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	for k in range(900):
		await process_frame
		g = current_scene
		if g and g.get("enemies") != null and g.get("player") != null and g.player.is_inside_tree():
			break
	# how many frames the warm-up drew (pass 112: Warmup.MIN_FRAMES)
	var wf := 0
	var t_w := Time.get_ticks_msec()
	for k in range(600):
		var w = g.get_node_or_null("Warmup")
		if w == null:
			break
		wf = int(w.get("_drawn_frames")) if w.get("_drawn_frames") != null else -1
		await process_frame
	print("p112_warmup: drew %d frames, gone after %d ms" % [wf, Time.get_ticks_msec() - t_w])
	await _secs(3.0)
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	_run.debug_clear_items()
	_run.build_changed.emit()
	g.enemies.kill_all(false)
	await _secs(1.0)
	var here: Vector3 = g.player.global_position
	if _parts:
		await _time_parts(here)
		_save.data = keep
		quit(0)
		return
	_times.clear()
	_mark("baseline")
	await _secs(2.0)
	_base_end = _n
	var em = g.enemies
	var pm = g.projectiles
	# the bomb
	var c: int = em.spawn("spit_cactus", _ground(here + Vector3(6.5, 0, -1.0)), null, 1.0, 400.0)
	em.rise_t[c] = 1.0
	em.vspecial[c] = 0
	em.cooldown[c] = 0.0
	var thrown0: int = int(pm.dynamite_thrown)
	var lain0: int = int(pm.dynamite_lain)
	var blast0: int = int(pm.dynamite_blasts)
	var until := Time.get_ticks_msec() + 7000
	while Time.get_ticks_msec() < until:
		await _frames(1)
		if int(pm.dynamite_thrown) > thrown0:
			_mark("bomb_throw")
		if int(pm.dynamite_lain) > lain0:
			_mark("bomb_land")
		if int(pm.dynamite_blasts) > blast0:
			_mark("bomb_blast")
			break
	em.kill_all(false)
	await _secs(0.6)
	# the harpoon: the throw, the hook-in, then its thrower dies (the break)
	var h: int = em.spawn("harpoon_troglodyte", _ground(here + Vector3(6.0, 0, -11.5)), null, 1.0, 400.0)
	em.rise_t[h] = 1.0
	em.vspecial[h] = 0
	em.cooldown[h] = 0.0
	until = Time.get_ticks_msec() + 7000
	while Time.get_ticks_msec() < until:
		await _frames(1)
		if g.get("_harpoon_proj") != null and int(g._harpoon_proj) >= 0:
			_mark("harpoon_throw")
		if int(g.tether_i) >= 0:
			_mark("harpoon_hook")
			break
	await _secs(0.7)
	if em.is_alive(h):
		em.damage(h, 1.0e9, "probe")
	_mark("chain_break")
	await _secs(1.2)
	_report()
	_save.data = keep
	quit(0)


## The first throw's pieces on their own: each call's CPU time (us), then the next 3 frames' real times (ms).
func _time_parts(here: Vector3) -> void:
	var pm = g.projectiles
	var em = g.enemies
	var audio = root.get_node("Audio")
	var reg = root.get_node("Registry")
	var cactus: EnemyDef = reg.enemy("spit_cactus")
	var bomb: Dictionary = cactus.ranged["bomb"]
	var out := {}
	# the lights round the hero (an omni light's own pass is a shader variant of its own in the Compatibility renderer)
	var lights: Array = []
	for l in root.find_children("*", "Light3D", true, false):
		var lt := l as Light3D
		if lt.is_visible_in_tree():
			lights.append([lt.get_class(), str(lt.get_path()).get_file(), snappedf(lt.global_position.distance_to(here), 0.1), snappedf(float(lt.get("omni_range")) if lt is OmniLight3D else -1.0, 0.1)])
	print("p112_lights: ", lights)
	var pieces := [
		["tracer_line", func() -> void: pm._tracer_lay(here + Vector3(-3, 1, -3), here + Vector3(-1, 1, -3), Color(0.2, 0.2, 0.2, 0.5), 0.3, 0.8, pm.clock, pm.clock, 0, -1.0)],
		["tracer_streak", func() -> void: pm._tracer_lay(here + Vector3(-3, 1, -4), here + Vector3(-1, 1, -4), Color(1, 1, 0.9, 1), 0.2, 0.3, pm.clock, pm.clock, 1, -1.0)],
		["audio_lob_throw", func() -> void: audio.play("w_lob_throw", here)],
		["audio_spear_throw", func() -> void: audio.play("w_spear_throw", here)],
		["audio_beetle_charge", func() -> void: audio.play("en_beetle_charge", here)],
		["bomb_kind", func() -> void: pm.dynamite_kind(str(bomb["model"]), float(bomb["scale"]), bomb.get("material", {}))],
		["pm_prewarm", func() -> void: _prewarm_call(pm, here)],
		["pm_warm_off", func() -> void: pm.warm_draw(Vector3.INF)],
		["bomb_throw_call", func() -> void: pm.hostile_dynamite(here + Vector3(4, 1.3, 0), here + Vector3(0, 0, 3), 9.0, 1.0, 2.0, bomb, {})],
		["harpoon_chain_make", func() -> void: g.harpoon_chain()],
		["harpoon_shot_call", func() -> void: g.enemy_shot_straight(here + Vector3(6, 1.0, -6), here + Vector3(-6, 0, 6), 20.0, 1.0, 0.5, {"harpoon": true, "shooter": -1, "life": 0.6, "harpoon_fx": reg.enemy("harpoon_troglodyte").ranged.get("harpoon_fx", {})})],
		["fx_clang", func() -> void: g.fx.clang_spark(here + Vector3(0, 1, 2), Vector3.RIGHT)],
		["fx_splinters", func() -> void: g.fx.splinters(here + Vector3(0, 1, 2), Color(0.5, 0.5, 0.55), 8, 0.14)],
		["fx_smoke", func() -> void: g.fx.smoke_puff(here + Vector3(0, 1, 2), Vector3.UP, 0.6, 0.18, 0.6, Color(0.35, 0.33, 0.32, 0.7))],
	]
	# the creatures' own attack calls (the brain's _do_attack, outside the wind-up) and a death
	var c: int = em.spawn("spit_cactus", _ground(here + Vector3(5.0, 0, -2.0)), null, 1.0, 400.0)
	var h: int = em.spawn("harpoon_troglodyte", _ground(here + Vector3(6.0, 0, -8.0)), null, 1.0, 400.0)
	for i in [c, h]:
		em.rise_t[i] = 1.0
		em.vspecial[i] = 0
		em.cooldown[i] = 99.0
	pieces.append(["cactus_do_attack", func() -> void: em._do_attack(c, cactus, here)])
	pieces.append(["harpoon_do_attack", func() -> void: em._do_attack(h, reg.enemy("harpoon_troglodyte"), here)])
	pieces.append(["fx_blood", func() -> void: g.fx.blood(here + Vector3(-2, 0.5, 2), Color(0.6, 0.1, 0.1), 1.0)])
	pieces.append(["harpooner_dies", func() -> void: em.damage(h, 1.0e9, "probe")])
	for pc in pieces:
		await _frames(30)
		var t0 := Time.get_ticks_usec()
		(pc[1] as Callable).call()
		var cpu := Time.get_ticks_usec() - t0
		var f0 := _n
		await _frames(8)
		var fr: Array = []
		for t in _times:
			if int(t[0]) > f0:
				fr.append(snappedf(float(t[1]), 0.1))
		var worst_parts := {}
		var worst := 0.0
		for t in _times:
			if int(t[0]) > f0 and float(t[1]) > worst:
				worst = float(t[1])
				worst_parts = _parts_of.get(int(t[0]), {})
		out[pc[0]] = {"cpu_us": cpu, "next_frames_ms": fr, "worst_parts": worst_parts}
	print("p112_parts: ", JSON.stringify(out))


func _prewarm_call(pm, here: Vector3) -> void:
	if _prewarm == "pit":
		pm.warm_draw(here + Vector3(0, -8.0, 0))
	elif _prewarm == "tiny":
		pm.warm_draw(here + Vector3(0, 0.6, 0), 0.03)
	elif _prewarm == "visible":
		pm.warm_draw(here + Vector3(0, 1.0, 3.0))


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, g.map.height_at(p.x, p.z), p.z)


func _report() -> void:
	var base: Array = []
	for t in _times:
		if int(t[0]) >= int(_marks.get("baseline", 0)) and int(t[0]) < _base_end:
			base.append(float(t[1]))
	base.sort()
	var med: float = base[base.size() / 2] if not base.is_empty() else 0.0
	var res := {"nowarm": _nowarm, "baseline_median_ms": med, "baseline_max_ms": base.back() if not base.is_empty() else 0.0, "events": {}}
	for ev in ["bomb_throw", "bomb_land", "bomb_blast", "harpoon_throw", "harpoon_hook", "chain_break"]:
		if not _marks.has(ev):
			res["events"][ev] = "not seen"
			continue
		var at: int = _marks[ev]
		var worst := 0.0
		var row: Array = []
		var proc: Array = []
		var phys: Array = []
		for t in _times:
			if int(t[0]) >= at - 2 and int(t[0]) <= at + 8:
				worst = maxf(worst, float(t[1]))
				row.append(snappedf(float(t[1]), 0.1))
				proc.append(snappedf(float(t[2]), 0.1))
				phys.append(snappedf(float(t[3]), 0.1))
		res["events"][ev] = {"max_ms": snappedf(worst, 0.1), "frames": row, "process": proc, "physics": phys}
	print("p112_firstuse: ", JSON.stringify(res))
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(res, "  "))
			f.close()
