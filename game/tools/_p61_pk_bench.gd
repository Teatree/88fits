## Pass 61 lane PK's pickups benchmark (scratch): the debug arena (no crowd, god mode), the hero walking a wide circle,
## N XP gems lying spread over the whole arena (75 % small, 20 % medium, 5 % large, worth nothing so no level-up stops
## the clock), then a vacuum (vacuum_all(true)). For each N it prints the milliseconds a frame the pickups took
## (Perf "pickups" = the physics tick, "pickups.draw" = the MultiMesh writes), the whole frame's wall time, the render
## thread's CPU and GPU time and the draw calls while they lie there, and over the vacuum the mean and worst frame, the
## pickups' own worst frame and how long until every gem was in. The old manager fused gems past 300 (_merge): its
## `_merging` is held on for the whole bench so its pool really holds what is asked (up to its 600).
##   godot --audio-driver Dummy --resolution 504x1122 --fixed-fps 60 --path game --script res://tools/_p61_pk_bench.gd -- n=300,600,1500,3000
##   args: n= (the field sizes), rest= (seconds measured lying, 6), vac= (seconds measured after the pull, 6), coins= (the
##         share of coins, 0)
extends SceneTree

var _ns: Array = [300, 600, 1500, 3000]
var _rest := 6.0
var _vac := 6.0
var _coins := 0.0
var _run
var _save
var _perf
var g
var _vp: RID
var _t := 0.0
var _walk := false
var _results: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("n="):
			_ns = Array(a.substr(2).split(",")).map(func(s: String) -> int: return int(s))
		elif a.begins_with("rest="):
			_rest = float(a.substr(5))
		elif a.begins_with("vac="):
			_vac = float(a.substr(4))
		elif a.begins_with("coins="):
			_coins = float(a.substr(6))
	process_frame.connect(_main, CONNECT_ONE_SHOT)
	process_frame.connect(_steer)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


## The hero walks a circle about 12 m across while the bench runs.
func _steer() -> void:
	_t += root.get_process_delta_time()
	if not _walk or g == null or not is_instance_valid(g) or g.player == null:
		return
	var inp = g.player.input
	if inp:
		inp.wants_move = true
		inp.origin = Vector2(216, 500)
		inp.touch_pos = inp.origin + Vector2(cos(_t * 0.4), sin(_t * 0.4)) * 110.0


func _main() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	_perf = load("res://core/systems/Perf.gd")
	_vp = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	var keep: Dictionary = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "peashooter", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	# no weapon firing at anything: the build is the Peashooter and the arena has no crowd but its dummies
	await _wait(2.0)
	_walk = true
	await _wait(1.0)
	for n in _ns:
		await _bench(int(n))
	print("pk_bench: ---- summary ----")
	for r in _results:
		print(r)
	_save.data = keep
	quit(0)


func _spawn_field(n: int) -> void:
	var pm = g.pickups
	pm.clear_all()
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	var old: bool = "_merging" in pm
	if old:
		pm.set("_merging", true)
	var reach: float = float(g.map.arena_radius) - 4.0 if g.map else 60.0
	var made := 0
	var slowest := 0
	var slowest_k := -1
	for k in range(n):
		var u := rng.randf()
		var kind: int = 0 if u < 0.75 else (1 if u < 0.95 else 2)
		if _coins > 0.0 and rng.randf() < _coins:
			kind = 3
		var a := rng.randf() * TAU
		var d := reach * sqrt(rng.randf())
		var t0 := Time.get_ticks_usec()
		if pm.spawn(kind, Vector3(cos(a) * d, 0.0, sin(a) * d), 0.0) >= 0:
			made += 1
		var us := Time.get_ticks_usec() - t0
		if us > slowest:
			slowest = us
			slowest_k = k
	# (the old manager's merge stays off for the whole bench: a barrel's burst or any later drop would merge the field)
	print("pk_bench: N=%d asked, %d made, %d alive | slowest spawn %.3f ms (spawn #%d; the pool now %d slots, %s instances a kind)" % [
		n, made, pm.count, float(slowest) / 1000.0, slowest_k, pm.alive.size(), str(pm.get("_icap"))])


func _bench(n: int) -> void:
	_spawn_field(n)
	# the drops land
	await _wait(1.5)
	var pm = g.pickups
	var alive0: int = pm.count
	_perf.report()
	var frames := 0
	var wall0 := Time.get_ticks_usec()
	var draws := 0.0
	var rcpu := 0.0
	var rgpu := 0.0
	var until := _t + _rest
	while _t < until:
		await process_frame
		frames += 1
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		rcpu += RenderingServer.viewport_get_measured_render_time_cpu(_vp)
		rgpu += RenderingServer.viewport_get_measured_render_time_gpu(_vp)
	var wall := float(Time.get_ticks_usec() - wall0) / 1000.0 / maxf(frames, 1)
	var r: Dictionary = _perf.report()
	var tick := float(r.get("pickups", 0.0))
	var draw := float(r.get("pickups.draw", 0.0))
	var line := "pk_bench: N=%4d lying %4d | pickups tick %.3f + draw %.3f = %.3f ms | frame %.2f ms (worst %.1f) | render cpu %.2f gpu %.2f | draws %.0f" % [
		n, alive0, tick, draw, tick + draw, wall, float(r["worst_ms"]), rcpu / maxf(frames, 1), rgpu / maxf(frames, 1), draws / maxf(frames, 1)]
	print(line)
	# the pull: every gem on the arena
	var before: int = pm.count
	frames = 0
	var worst_pk := 0.0
	var worst_frame := 0.0
	var over20 := 0
	var sum_pk := 0.0
	wall0 = Time.get_ticks_usec()
	var last := wall0
	var vac_t0 := _t
	var all_in := -1.0
	var t50 := -1.0
	var t90 := -1.0
	var t99 := -1.0
	var most_flying := 0
	var bench_us := 0
	pm.vacuum_all(true)
	until = _t + _vac
	while _t < until:
		var pk0: float = float(_perf.usec.get("pickups", 0)) + float(_perf.usec.get("pickups.draw", 0))
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := float(now - last) / 1000.0
		last = now
		frames += 1
		worst_frame = maxf(worst_frame, ms)
		if ms > 20.0:
			over20 += 1
		var pk1: float = float(_perf.usec.get("pickups", 0)) + float(_perf.usec.get("pickups.draw", 0))
		var pk_ms := (pk1 - pk0) / 1000.0
		sum_pk += pk_ms
		worst_pk = maxf(worst_pk, pk_ms)
		# the bench's own count of the gems in flight is kept out of the frame times
		var b0 := Time.get_ticks_usec()
		var fl := 0
		if "_flying_n" in pm:
			fl = int(pm.get("_flying_n"))
		else:
			for i in range(mini(pm.flying.size(), pm.alive.size())):
				if pm.alive[i] == 1 and pm.flying[i] == 1:
					fl += 1
		most_flying = maxi(most_flying, fl)
		if all_in < 0.0 and pm.count == 0:
			all_in = _t - vac_t0
		var got_share := 1.0 - float(pm.count) / maxf(float(before), 1.0)
		if t50 < 0.0 and got_share >= 0.5:
			t50 = _t - vac_t0
		if t90 < 0.0 and got_share >= 0.9:
			t90 = _t - vac_t0
		if t99 < 0.0 and got_share >= 0.99:
			t99 = _t - vac_t0
		var spent := Time.get_ticks_usec() - b0
		bench_us += spent
		last += spent
	var vwall := float(Time.get_ticks_usec() - wall0 - bench_us) / 1000.0 / maxf(frames, 1)
	_perf.report()
	var line2 := "pk_bench: N=%4d vacuum of %4d | frame mean %.2f ms worst %.1f ms, %d over 20 ms | pickups mean %.3f worst %.3f ms | most in flight %d | half in %.2f s, 90%% %.2f s, 99%% %.2f s, all in after %s" % [
		n, before, vwall, worst_frame, over20, sum_pk / maxf(frames, 1), worst_pk, most_flying, t50, t90, t99, ("%.2f s" % all_in) if all_in >= 0.0 else ("not (%d left)" % pm.count)]
	print(line2)
	_results.append(line)
	_results.append(line2)
