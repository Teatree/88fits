## Pass 101, lane CROWD: what each piece of the crowd's tick costs now (ms a call, the mean of `n` calls each, outside
## the tick), on 300 of stage 3's mix round the hero in god mode at play zoom, windowed or headless (the frustum is the
## window's): the grid build (both grids and the wide bodies' cell lists), _sep_bigs alone, refresh_drawn for half the
## crowd, refresh_onscreen for half, a steer of every moving creature (dt 0), and _render.
##   bash tools/godot.sh --audio-driver Dummy --resolution 504x1122 --path D:/_projects/88fits/game --script res://tools/_p101_CROWD_bench.gd -- [n=200] [tag=a]
extends SceneTree

const MIX := [["skeleton", 4], ["skeleton_knight", 3], ["hellhound", 3], ["imp", 3], ["dust_mummy", 2], ["fire_ant", 2],
	["horned_toad", 2], ["dust_shaman", 1], ["werewolf", 1], ["armadillo", 1], ["buckshot_dwarf", 1], ["hammer_giant", 1],
	["bull_beetle", 1], ["spit_cactus", 1]]
var _n := 200
var _tag := "a"
var _r0 := 5.0
var _r1 := 15.0
var _game: Node
var _run: Node
var _frames := 0
var _rng := RandomNumberGenerator.new()
var _pool: Array = []
var _C := {}


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("n="):
			_n = int(a.substr(2))
		elif a.begins_with("tag="):
			_tag = a.substr(4)
		elif a.begins_with("r0="):
			_r0 = float(a.substr(3))
		elif a.begins_with("r1="):
			_r1 = float(a.substr(3))
	_rng.seed = 5
	for m in MIX:
		for k in range(int(m[1])):
			_pool.append(m[0])
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "peashooter", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	root.get_node("Save").data["runs_started"] = 1
	_run = root.get_node("Run")
	change_scene_to_file("res://game/Game.tscn")
	process_frame.connect(_tick)


func _tick() -> void:
	_frames += 1
	if _frames > 4000:
		quit(1)
		return
	if _game == null:
		var g = current_scene
		if g == null or not g.has_method("open_pause") or g.player == null or g.get("director") == null:
			return
		_game = g
		_game.player.god = true
		_C = _game.enemies.get_script().get_script_constant_map()
		_game.director.running = false
		_run.debug_clear_items()
		_run.rebuild_sheets()
		_game.enemies.kill_all(false)
		return
	var em = _game.enemies
	if em.count_alive < 300:
		var hp: Vector3 = _game.player.global_position
		for k in range(mini(300 - em.count_alive, 30)):
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(_r0, _r1)
			em.spawn(str(_pool[_rng.randi() % _pool.size()]), hp + Vector3(cos(a) * r, 0, sin(a) * r * 1.3), null, 1.0, 2.5)
		return
	if _frames < 400:
		return
	var out: Array = []
	var ppos: Vector3 = _game.player.global_position
	out.append("bench (%d calls each, ms a call; 300 creatures %.0f..%.0f m round the hero; window %s):" % [_n, _r0, _r1, str(root.get_visible_rect().size)])
	out.append("  grid (both + wide lists) %.4f" % _time(func(): em._rebuild_grid()))
	if em.has_method("_sep_bigs"):
		out.append("  _sep_bigs alone          %.4f" % _time(func(): em._sep_bigs()))
	if em.has_method("refresh_drawn"):
		out.append("  refresh_drawn(half)      %.4f" % _time(func(): em.refresh_drawn(_frames & 1)))
	out.append("  refresh_onscreen(half)   %.4f" % _time(func(): em.refresh_onscreen(_frames & 1)))
	out.append("  steer every moving (dt0) %.4f" % _time(func():
		for i in range(_C["MAX"]):
			if em.alive[i] == 1 and em.state[i] == _C["STATE_MOVE"]:
				em._steer(i, ppos, 0.0)))
	out.append("  _render                  %.4f" % _time(func(): em._render()))
	var drawn := 0
	if "drawn_vis" in em:
		for i in range(_C["MAX"]):
			if em.alive[i] == 1 and em.drawn_vis[i] == 1:
				drawn += 1
	var near_ob := 0
	var undrawn := 0
	for i in range(_C["MAX"]):
		if em.alive[i] == 1 and em.drawn_vis[i] == 0:
			undrawn += 1
			if em._obst_cells.has(Vector2i(floori(em.pos[i].x / 4.0), floori(em.pos[i].z / 4.0))):
				near_ob += 1
	out.append("  drawn %d of %d; of the %d not drawn, %d in an obstacle cell (steer every 2nd)" % [drawn, em.count_alive, undrawn, near_ob])
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var rect := cam.get_viewport().get_visible_rect()
	var feet_in := 0
	for i in range(_C["MAX"]):
		if em.alive[i] == 1 and not cam.is_position_behind(em.pos[i]) and rect.has_point(cam.unproject_position(em.pos[i])):
			feet_in += 1
	out.append("  feet inside the view %d; onscreen flags %d; cam fov %.1f, rect %s, cam move %.3f turn %.4f, cam %s" % [feet_in, Array(em.onscreen).count(1), cam.fov, str(rect), em._vis_cam_move, em._vis_cam_turn, str(cam.global_position)])
	var shown := 0
	for i in range(_C["MAX"]):
		if em.alive[i] == 1 and shown < 12:
			var b: PackedFloat32Array = em.vis_bounds(i, cam.global_transform.basis.y, em._cf_tick)
			out.append("    #%d pos %s size %.2f drawn %d feet %s | sphere r %.2f border %.2f" % [i, str(em.pos[i]), em.size[i], em.drawn_vis[i], str(cam.unproject_position(em.pos[i])), b[3], em._vis_border(i, cam.global_position.distance_to(Vector3(b[0], b[1], b[2])), 3.0 / 60.0)])
			shown += 1
	for s in out:
		print("p101bench: " + s)
	var fl := FileAccess.open("D:/_projects/88fits/tools/dl/p101/CROWD/bench_%s.txt" % _tag, FileAccess.WRITE)
	if fl:
		fl.store_string("\n".join(out) + "\n")
		fl.close()
	quit(0)


func _time(fn: Callable) -> float:
	var t0 := Time.get_ticks_usec()
	for k in range(_n):
		fn.call()
	return float(Time.get_ticks_usec() - t0) / 1000.0 / float(_n)
