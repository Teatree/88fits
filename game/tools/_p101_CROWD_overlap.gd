## Pass 101, lane CROWD: how much the crowd stands inside itself at each separation cell size (Garry: "Test that there
## are no overlaps with 12 neighbours and increase if necessary"). The stage-3 look, the director held, the hero in god
## mode with no weapon (nothing dies), a stage-3 mix topped up to `n` round him; per scenario (stand: a tight ring round
## a standing hero; walk: the S of perf_late, a crowd that flows) and per cell size (EnemyManager.set_sep_cell; 2.5 is
## today's) the same spawns (one seed), `settle` s, then `hold` s measured: every 3rd frame every pair of standing
## creatures (alive, not dying, buried, held, in the air or rising) is checked by brute force: pairs closer than the sum
## of their radii x tol (tol 1.0 / 0.8 / 0.5) per creature, the mean depth ((ri + rj - d) / (ri + rj) summed over the
## overlapping pairs, per creature), the big list's size (wide bodies past half a cell) and how often it was past
## BIG_LIST_MAX, the neighbours each creature's separation walks, and enemies.sim (ms a frame, the game's own Perf key).
##   bash tools/godot.sh --headless --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/_p101_CROWD_overlap.gd -- tag=a [cells=2.5,1.75,1.5,1.25] [n=300] [settle=4] [hold=15] [scen=stand,walk] [seed=7] [far=4]
## Results: tools/dl/p101/CROWD/overlap_<tag>.txt (+ .json). Never touches Settings or the save. Watchdog 1500 s.
extends SceneTree

const MIX := [["skeleton", 4], ["skeleton_knight", 3], ["hellhound", 3], ["imp", 3], ["dust_mummy", 2], ["fire_ant", 2],
	["horned_toad", 2], ["dust_shaman", 1], ["werewolf", 1], ["armadillo", 1], ["buckshot_dwarf", 1], ["hammer_giant", 1],
	["bull_beetle", 1], ["spit_cactus", 1]]
const TOLS := [1.0, 0.8, 0.5]

var _cells: Array = [2.5, 1.75, 1.5, 1.25]
var _scens: Array = ["stand", "walk"]
var _n := 300
var _settle := 4.0
var _hold := 15.0
var _seed := 7
var _seeds: Array = []
var _far := -1
var _tag := "a"
var _game: Node
var _run: Node
var _perf
var _t := 0.0
var _phases: Array = []
var _pi := -1
var _pt := 0.0
var _rng := RandomNumberGenerator.new()
var _pool: Array = []
var _acc := {}
var _samples := 0
var _frame := 0
var _out: Array = []
var _rows: Array = []
var _C: Dictionary = {}
var _walk_t := 0.0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"cells": _cells = Array(kv[1].split(",")).map(func(x): return float(x))
			"scen": _scens = Array(kv[1].split(","))
			"n": _n = int(kv[1])
			"settle": _settle = float(kv[1])
			"hold": _hold = float(kv[1])
			"seed": _seed = int(kv[1])
			"seeds": _seeds = Array(kv[1].split(",")).map(func(x): return int(x))
			"tag": _tag = kv[1]
			"far": _far = int(kv[1])
	for m in MIX:
		for k in range(int(m[1])):
			_pool.append(m[0])
	if _seeds.is_empty():
		_seeds = [_seed]
	for sd in _seeds:
		for sc in _scens:
			for c in _cells:
				_phases.append({"scen": sc, "cell": c, "seed": sd})
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "peashooter", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	root.get_node("Save").data["runs_started"] = 1
	_run = root.get_node("Run")
	_perf = load("res://core/systems/Perf.gd")
	change_scene_to_file("res://game/Game.tscn")
	process_frame.connect(_tick)


func _tick() -> void:
	var dt := root.get_process_delta_time()
	_t += dt
	if _t > 1500.0:
		_log("watchdog: quit at 1500 s")
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
		if _far > 0 and "steer_far_every" in _game.enemies:
			_game.enemies.steer_far_every = _far
		_log("setup: clock %.0f, director held, no weapons, n %d, settle %.0f s, hold %.0f s, seed %d, far every %s" % [_run.elapsed, _n, _settle, _hold, _seed, str(_game.enemies.get("steer_far_every"))])
		return
	_keep_playing(dt)
	if _pi < 0:
		if _t > 2.0:
			_next()
		return
	var ph: Dictionary = _phases[_pi]
	_top_up()
	_pt += dt
	if _pt < _settle:
		return
	if _pt - dt < _settle:
		_perf.report()
		_acc = {}
		_samples = 0
		return
	_frame += 1
	if _frame % 3 == 0:
		_measure()
	if _pt >= _settle + _hold:
		_report(ph)
		_next()


func _next() -> void:
	_pi += 1
	if _pi >= _phases.size():
		_finish()
		return
	_pt = 0.0
	var ph: Dictionary = _phases[_pi]
	var em = _game.enemies
	em.kill_all(false)
	# the bodies of kill_all(false) are freed at once; the same spawns for every phase
	if em.has_method("set_sep_cell"):
		em.set_sep_cell(float(ph["cell"]))
	_rng.seed = int(ph["seed"])
	_walk_t = 0.0
	_game.player.global_position = Vector3(0, _game.player.global_position.y, 0)


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
		inp.touch_pos = inp.origin + Vector2(sin(_walk_t * 0.5) * 90.0, -110.0)
	else:
		inp.wants_move = false
	if _game.cards and _game.cards.visible and not _game.cards._offer.is_empty() and not _game.cards._picking:
		_game.cards._pick(_game.cards._offer[0])


func _top_up() -> void:
	var em = _game.enemies
	var need := mini(_n - int(em.count_alive), 25)
	var hp: Vector3 = _game.player.global_position
	for k in range(need):
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(3.0, 15.0)
		var at := hp + Vector3(cos(a) * r, 0, sin(a) * r * 1.3)
		em.spawn(str(_pool[_rng.randi() % _pool.size()]), at, null, 1.0, 2.5)


func _add(k: String, v: float) -> void:
	_acc[k] = float(_acc.get(k, 0.0)) + v


func _measure() -> void:
	var em = _game.enemies
	var idx := PackedInt32Array()
	for i in range(_C["MAX"]):
		if em.alive[i] == 0 or em.state[i] == _C["STATE_DYING"] or em.hidden[i] == 1 or em.held[i] == 1:
			continue
		if em.lift_h[i] > 0.01 or em.rise_t[i] < 1.0:
			continue
		idx.append(i)
	var n := idx.size()
	var cnt := [0, 0, 0]
	var depth := 0.0
	var worst := 0.0
	# a wide body and a narrow one: the narrow one sees the wide one only inside its 3 x 3 separation cells, or through
	# the big list while that is BIG_LIST_MAX or shorter; otherwise only the wide one pushes (one-sided)
	var big_r: float = em._big_r if "_big_r" in em else float(_C["CELL"]) * 0.5
	var listed: bool = em._big.size() <= int(_C["BIG_LIST_MAX"])
	var use_s: bool = "_s_head" in em and em._sw > 0
	var bn_pairs := 0
	var bn_depth := 0.0
	var missed := 0
	var missed_depth := 0.0
	for a in range(n):
		var i: int = idx[a]
		var pi: Vector3 = em.pos[i]
		var ri: float = em.radius[i]
		for b in range(a + 1, n):
			var j: int = idx[b]
			var dx: float = pi.x - em.pos[j].x
			var dz: float = pi.z - em.pos[j].z
			var s: float = ri + em.radius[j]
			var d2 := dx * dx + dz * dz
			if d2 >= s * s:
				continue
			var d := sqrt(d2)
			var dep := (s - d) / s
			depth += dep
			worst = maxf(worst, dep)
			var rj: float = em.radius[j]
			if (ri > big_r) != (rj > big_r):
				bn_pairs += 1
				bn_depth += dep
				var nn: int = i if ri <= big_r else j
				var bb: int = j if ri <= big_r else i
				var c_n := Vector2i(em._scol(em.pos[nn].x), em._scol(em.pos[nn].z)) if use_s else Vector2i(em._gcol(em.pos[nn].x), em._gcol(em.pos[nn].z))
				var c_b := Vector2i(em._scol(em.pos[bb].x), em._scol(em.pos[bb].z)) if use_s else Vector2i(em._gcol(em.pos[bb].x), em._gcol(em.pos[bb].z))
				if absi(c_n.x - c_b.x) > 1 or absi(c_n.y - c_b.y) > 1:
					var felt := listed
					if "_bg_head" in em:
						# pass 101: the wide bodies listed by cell (_sep_bigs)
						felt = false
						if em._bg_n > 0:
							var e: int = em._bg_head[c_n.y * em._sw + c_n.x]
							while e >= 0:
								if em._bg_j[e] == bb:
									felt = true
									break
								e = em._bg_next[e]
					if not felt:
						missed += 1
						missed_depth += dep
			for k in range(3):
				var tl: float = TOLS[k] * s
				if d2 < tl * tl:
					cnt[k] += 1
	_samples += 1
	_add("standing", float(n))
	for k in range(3):
		_add("pairs_tol%.1f" % TOLS[k], float(cnt[k]) / maxf(float(n), 1.0))
	_add("depth", depth / maxf(float(n), 1.0))
	_add("worst", worst)
	_add("bn_pairs", float(bn_pairs) / maxf(float(n), 1.0))
	_add("bn_depth", bn_depth / maxf(float(bn_pairs), 1.0))
	_add("missed", float(missed) / maxf(float(n), 1.0))
	_add("missed_depth", missed_depth / maxf(float(missed), 1.0))
	var big: int = em._big.size()
	_add("big", float(big))
	_add("big_over", 1.0 if big > int(_C["BIG_LIST_MAX"]) else 0.0)
	# the neighbours each standing creature's separation walks (its 3 x 3 cells of the separation grid)
	var nb := 0
	for i in idx:
		var gx: int = em._scol(em.pos[i].x) if use_s else em._gcol(em.pos[i].x)
		var gz: int = em._scol(em.pos[i].z) if use_s else em._gcol(em.pos[i].z)
		var w: int = em._sw if use_s else em._gw
		for cx in range(maxi(gx - 1, 0), mini(gx + 2, w)):
			for cz in range(maxi(gz - 1, 0), mini(gz + 2, w)):
				var j: int = em._s_head[cz * w + cx] if use_s else em._g_head[cz * w + cx]
				while j >= 0:
					nb += 1
					j = em._s_next[j] if use_s else em._g_next[j]
	_add("neighbours", float(nb) / maxf(float(n), 1.0))


func _report(ph: Dictionary) -> void:
	var r: Dictionary = _perf.report()
	var s := maxf(float(_samples), 1.0)
	var row := {"scen": ph["scen"], "cell": ph["cell"], "seed": ph["seed"], "samples": _samples, "enemies_sim_ms": float(r.get("enemies.sim", 0.0))}
	for k in _acc.keys():
		row[k] = float(_acc[k]) / s
	_rows.append(row)
	_log("[%s cell %.2f seed %d] standing %.0f | overlapping pairs per creature: tol1.0 %.3f, tol0.8 %.3f, tol0.5 %.4f | depth %.4f, worst %.3f | wide-narrow pairs %.3f (depth %.3f), one-sided %.4f (depth %.3f) | big %.1f (over %d: %.0f%% of samples) | neighbours %.1f | enemies.sim %.2f ms" % [
		ph["scen"], ph["cell"], ph["seed"], row.get("standing", 0.0), row.get("pairs_tol1.0", 0.0), row.get("pairs_tol0.8", 0.0), row.get("pairs_tol0.5", 0.0),
		row.get("depth", 0.0), row.get("worst", 0.0), row.get("bn_pairs", 0.0), row.get("bn_depth", 0.0), row.get("missed", 0.0), row.get("missed_depth", 0.0),
		row.get("big", 0.0), int(_C["BIG_LIST_MAX"]), 100.0 * float(row.get("big_over", 0.0)),
		row.get("neighbours", 0.0), row["enemies_sim_ms"]])


func _log(s: String) -> void:
	print("p101overlap: " + s)
	_out.append(s)


func _finish() -> void:
	var dir := "D:/_projects/88fits/tools/dl/p101/CROWD"
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir + "/overlap_%s.txt" % _tag, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_out) + "\n")
		f.close()
	var j := FileAccess.open(dir + "/overlap_%s.json" % _tag, FileAccess.WRITE)
	if j:
		j.store_string(JSON.stringify(_rows, " "))
		j.close()
	quit(0)


## The run's own screens closed through their own paths, as smoke_run does (a totem, the Stranger, the shop, a chest, the
## portal), so a walk past a structure never leaves the run paused.
func _close_modals() -> void:
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
