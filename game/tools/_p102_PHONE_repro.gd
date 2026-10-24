## Pass 102, lane REPRO (investigation only): Garry's Pixel 8 Pro run (v0.86, Drifter, stage 1 then Endless; record
## analytics/remote/Hungry_Outlaw_94/2026-10-23T18-50-34_01a16974.json) held 60 fps at 150-300 creatures to 14:00, then
## fell to 16-27 fps at the same crowd. This probe puts the god-mode Drifter, walking perf_late's S, in a forced Endless
## crowd of N creatures (dust_mummy / werewolf / bull_beetle / spit_cactus in the record's alive shares, the director
## held, topped up every frame from the director's own spawn points 19-24 m out) whose numbers are Endless wave W's (the
## director's own source_for: the row's fixed numbers x WaveTimeline.endless_mults(W), at the hero's level `src_level`),
## and gives him the record's build A (t=780 s) or B (t=1060 s), optionally changed item by item (over=). Each phase
## (one wave each) settles `settle` s and is measured `hold` s: wall ms a frame (p50/p95), the game's Perf keys, draw
## calls, render cpu/gpu, the crowd, how many burn/are poisoned/frozen/slowed, how many stand within 3 and 6 m, drawn
## creatures, shots, particles, damage numbers, kills and damage a second. XP is held at nothing (no level-ups) and the
## build is put back if a chest changes it. Results: tools/dl/p102/repro_<tag>.txt.
##   bash tools/godot.sh --audio-driver Dummy --resolution 504x1122 --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/_p102_PHONE_repro.gd -- build=B waves=20,34,48 tag=b1
## args: build=A|B|none, waves=20,34 (Endless waves, one phase each), n=240 (crowd), settle=12, hold=20 (game s),
##   seed=7, src_level=42 (the hero level the creatures' numbers are fixed at), level= (the hero's; default the build's),
##   mix=dust_mummy:56,werewolf:42,bull_beetle:1,spit_cactus:1, over=id:level,... (0 removes; weapon or passive by id),
##   drop_mut=id,... (mutations taken away), numbers=0 (damage numbers suppressed), mode=forced|natural (natural: the
##   director runs Endless from wave W itself, n ignored), tag=
## Never touches Settings or the save (tools/godot.sh keeps the PC save aside). A watchdog quits at 1500 s of wall time.
extends SceneTree

const BUILD_A := {
	"level": 40,
	"weapons": {"revolver": 3, "frisbee": 3, "boomstick": 4, "dragons_breath": 2, "rocket_pod": 1},
	"mutations": ["poison_razors", "silver_bullet", "dragons_breath", "blue_flame", "both_barrels"],
	"lines": {"almanac": 1, "juggernaut": 1, "mother_lode": 1, "multishot": 2, "quicksilver": 1},
	"passives": {"adrenaline": 3, "barrel_rush": 1, "beer": 2, "big_game_hunter": 1, "cold_snap": 2, "desperado": 2,
		"heavyweight": 1, "hot_springs": 1, "hot_streak": 3, "kindling": 2, "loose_change": 2, "phoenix_feather": 1,
		"pocket_watch": 4, "powder_keg": 3, "quickdraw": 2, "reach": 5, "ricochet": 2, "skedaddle": 2, "steady_hand": 2,
		"venom": 4, "vulture": 4},
}
const BUILD_B := {
	"level": 46,
	"weapons": {"revolver": 5, "frisbee": 3, "boomstick": 5, "dragons_breath": 3, "rocket_pod": 2},
	"mutations": ["poison_razors", "silver_bullet", "dragons_breath", "blue_flame", "both_barrels"],
	"lines": {"almanac": 1, "juggernaut": 1, "mother_lode": 1, "multishot": 3, "quicksilver": 1},
	"passives": {"adrenaline": 3, "barrel_rush": 1, "beer": 3, "big_game_hunter": 1, "cold_snap": 4, "desperado": 2,
		"heavyweight": 1, "hot_springs": 2, "hot_streak": 3, "kindling": 4, "loose_change": 3, "overkill": 1,
		"phoenix_feather": 1, "pickpocket": 6, "pocket_watch": 5, "powder_keg": 3, "quickdraw": 3, "reach": 5,
		"ricochet": 3, "siesta": 2, "skedaddle": 3, "snake_oil": 1, "steady_hand": 4, "venom": 5, "vulture": 5},
}

var _build_name := "B"
var _waves: Array = [20, 34]
var _n := 240
var _settle := 12.0
var _hold := 20.0
var _seed := 7
var _src_level := 42
var _level := -1
var _mix := {"dust_mummy": 56.0, "werewolf": 42.0, "bull_beetle": 1.0, "spit_cactus": 1.0}
var _over := {}
var _drop_mut: Array = []
var _numbers := true
var _mode := "forced"
var _tag := "a"
var _berserk := false   # berserk=1 : the Berserk power-up (rage: might x1.5, haste x2) held the whole run, as Garry's
## record had it on at times (haste 2.0)
var _walk := "circle"   # walk=circle (default: a steady loop of `period` s round the start, as a kiting player walks) | s
## (perf_late's S, which walks one way and reaches the map's edge within a phase) | still
var _period := 40.0
var _home := Vector3.INF
var _hits_prof := false   # prof=1 (pass 102, lane HITS)
var _hits_old := false    # hits=old (pass 102, lane HITS)
var _shot := ""           # shot=<prefix> (pass 102, lane HITS)
var _shots := 0
# pass 102 lane STEADY: busy_tick=<ms> (a busy-wait in every 60 Hz world step), busy_frame=<ms> (one a drawn frame),
# steps=<n> (Engine.max_physics_steps_per_frame for the run: 8 = before pass 102, 2 = the cap): run WITHOUT --fixed-fps
# (which skips the cap) to see the catch-up; the result rows gain steps_mean, steps_max, world_speed, cap
var _busy_tick := 0.0
var _busy_frame := 0.0
var _steps_cap := -1
var _phys_n := 0
var _steps_sum := 0
var _steps_max := 0
var _pf0 := 0
var _scale := 1.0   # scale= : the 3D pass's pixels (2.13 = the Pixel 8 Pro's 1075x2394 3D pixels from a 504x1122 window)

var _game: Node
var _run: Node
var _perf
var _vp: RID
var _C: Dictionary = {}
var _t := 0.0
var _wall_start := 0
var _pi := -1
var _phase_t := 0.0
var _measuring := false
var _src: Dictionary = {}   # enemy id -> {row, src}
var _build: Dictionary = {}
var _sig := ""
var _restores := 0
var _sum := {}
var _frames := 0
var _wall_t0 := 0
var _last_us := 0
var _probe_us := 0
var _frame_ms: Array = []
var _kills0 := 0
var _dmg0 := 0.0
var _spawned := 0
var _out: Array = []
var _rows: Array = []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("build="):
			_build_name = a.substr(6)
		elif a.begins_with("waves="):
			_waves = Array(a.substr(6).split(",")).map(func(x): return int(x))
		elif a.begins_with("n="):
			_n = int(a.substr(2))
		elif a.begins_with("settle="):
			_settle = float(a.substr(7))
		elif a.begins_with("hold="):
			_hold = float(a.substr(5))
		elif a.begins_with("seed="):
			_seed = int(a.substr(5))
		elif a.begins_with("src_level="):
			_src_level = int(a.substr(10))
		elif a.begins_with("level="):
			_level = int(a.substr(6))
		elif a.begins_with("mix="):
			_mix = {}
			for p in a.substr(4).split(","):
				var kv := p.split(":")
				_mix[kv[0]] = float(kv[1])
		elif a.begins_with("over="):
			for p in a.substr(5).split(","):
				var kv := p.split(":")
				_over[kv[0]] = int(kv[1])
		elif a.begins_with("drop_mut="):
			_drop_mut = Array(a.substr(9).split(","))
		elif a == "numbers=0":
			_numbers = false
		elif a.begins_with("mode="):
			_mode = a.substr(5)
		elif a.begins_with("tag="):
			_tag = a.substr(4)
		elif a.begins_with("walk="):
			_walk = a.substr(5)
		elif a.begins_with("period="):
			_period = float(a.substr(7))
		elif a == "berserk=1":
			_berserk = true
		elif a.begins_with("scale="):
			_scale = float(a.substr(6))
		# pass 102 (lane HITS): prof=1 times the numbers, the burns, poisons, hit sounds and flames (Perf keys numbers.*,
		# hits.*); hits=old plays pass 101's rules (every hit's sound, every flame, no full-screen numbers)
		elif a == "prof=1":
			_hits_prof = true
		elif a == "hits=old":
			_hits_old = true
		elif a.begins_with("busy_tick="):
			_busy_tick = float(a.substr(10))
		elif a.begins_with("busy_frame="):
			_busy_frame = float(a.substr(11))
		elif a.begins_with("steps="):
			_steps_cap = int(a.substr(6))
		elif a.begins_with("shot="):
			# shot=<path prefix>: three frames of the measured crowd, 0.4 s apart from 2 s into the hold (pass 102, HITS)
			_shot = a.substr(5)
	seed(_seed)
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	_wall_start = Time.get_ticks_msec()
	# pass 102 (lane HITS): loaded here, after the autoloads (in _init the scripts would not compile)
	if _hits_prof:
		load("res://ui/DamageNumbers.gd").prof = true
		load("res://core/systems/EnemyManager.gd").prof_hits = true
	if _hits_old:
		load("res://ui/DamageNumbers.gd").crowd_from = 1 << 30
		load("res://core/systems/EnemyManager.gd").hit_sound_gap_ms = 0
		load("res://core/systems/EnemyManager.gd").fire_fx_full = 0
	# pass 102 (lane STEADY): the busy-wait in every world step (the cap is set once the game is up: Game._ready sets its own)
	physics_frame.connect(_on_phys)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": _seed, "analytics": false}))
	f.close()
	root.get_node("Save").data["runs_started"] = 1
	_run = root.get_node("Run")
	_perf = load("res://core/systems/Perf.gd")
	_vp = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	change_scene_to_file("res://game/Game.tscn")
	process_frame.connect(_tick)


## Pass 102 (lane STEADY): busy-waits for the overload knobs.
func _spin(ms: float) -> void:
	var t := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t < int(ms * 1000.0):
		pass


func _on_phys() -> void:
	_phys_n += 1
	if _busy_tick > 0.0 and _pi >= 0:
		_spin(_busy_tick)


func _tick() -> void:
	# pass 102 (lane STEADY): this frame's world steps, and the frame's busy-wait
	var steps := _phys_n
	_phys_n = 0
	if _busy_frame > 0.0 and _pi >= 0:
		_spin(_busy_frame)
	var dt := root.get_process_delta_time()
	_t += dt
	if Time.get_ticks_msec() - _wall_start > 1500000:
		_log("watchdog: quit at 1500 s wall")
		_finish()
		return
	if _game == null:
		var g = current_scene
		if g == null or not g.has_method("open_pause") or g.player == null or g.get("director") == null:
			return
		_game = g
		_game.player.god = true
		if _steps_cap > 0:
			Engine.max_physics_steps_per_frame = _steps_cap
		_C = _game.enemies.get_script().get_script_constant_map()
		if _scale != 1.0:
			root.scaling_3d_scale = _scale
		if not _numbers and _game.get("damage_numbers") != null and _game.damage_numbers:
			_game.damage_numbers.suppressed = true
		return
	_keep_playing()
	if _pi < 0:
		if _t > 2.0:
			_make_build()
			_next_phase()
		return
	var ps := Time.get_ticks_usec()
	_run.xp = -1.0e12
	if _mode == "forced":
		_top_up()
	_check_build()
	_probe_us += Time.get_ticks_usec() - ps
	_phase_t += dt
	if _phase_t < _settle:
		return
	if not _measuring:
		_measuring = true
		_perf.report()
		_reset()
		return
	_steps_sum += steps
	_steps_max = maxi(_steps_max, steps)
	_sample()
	if _shot != "" and _shots < 3 and _phase_t >= _settle + 2.0 + 0.4 * _shots:
		_shots += 1
		root.get_texture().get_image().save_png("%s_%d.png" % [_shot, _shots])
	if _phase_t >= _settle + _hold:
		_report()
		_next_phase()


# ---------------------------------------------------------------- the build

func _make_build() -> void:
	var b: Dictionary = (BUILD_A if _build_name == "A" else BUILD_B).duplicate(true)
	if _build_name == "none":
		b = {"level": 40, "weapons": {"revolver": 1}, "mutations": [], "lines": {}, "passives": {}}
	for id in _over.keys():
		var lv: int = int(_over[id])
		var key := "weapons" if b["weapons"].has(id) or root.get_node("Registry").weapon(id) != null else ("lines" if b["lines"].has(id) else "passives")
		if lv <= 0:
			(b[key] as Dictionary).erase(id)
		else:
			b[key][id] = lv
	for m in _drop_mut:
		(b["mutations"] as Array).erase(m)
	if _level > 0:
		b["level"] = _level
	_build = b
	_apply_build()
	var st = _run.player_sheet
	var ws: Array = []
	for w in _run.weapons:
		ws.append("%s %d (amount %.0f, cd %.3f, dmg %.0f, area %.2f, pierce %.0f, muts %s)" % [w.def.id, w.level, w.stat("amount", 0.0), w.stat("cooldown", 0.0), w.stat("damage", 0.0), w.stat("area", 0.0), w.stat("pierce", 0.0), str(w.mutations.map(func(m): return m.id))])
	_log("berserk %s, haste %.2f" % [str(_berserk), _run.haste])
	_log("build %s%s%s level %d (card %d): %s" % [_build_name, (" over " + str(_over)) if not _over.is_empty() else "", (" drop_mut " + str(_drop_mut)) if not _drop_mut.is_empty() else "", _run.level, _run.card_level(), "; ".join(ws)])
	_log("    passives %s | lines %s" % [str(_run.passives), str(_build["lines"])])
	_log("    sheet: amount %.2f, area %.3f, cooldown %.3f, crit %.2f, might %.3f, duration %.2f, debuff %.2f" % [st.get_stat("amount", 0.0), st.get_stat("area", 1.0), st.get_stat("cooldown", 1.0), st.get_stat("crit_chance", 0.0), st.get_stat("might", 1.0), st.get_stat("duration", 1.0), st.get_stat("debuff_duration", 1.0)])


func _apply_build() -> void:
	_run.debug_clear_items()
	for id in _build["weapons"].keys():
		_run.debug_set_item("weapon", id, int(_build["weapons"][id]))
	for m in _build["mutations"]:
		_run.debug_set_item("mutation", m, 1)
	for id in _build["lines"].keys():
		_run.debug_set_item("passive", id, int(_build["lines"][id]))
	for id in _build["passives"].keys():
		_run.debug_set_item("passive", id, int(_build["passives"][id]))
	_run.mutation_levels = 4
	_run.level = int(_build["level"])
	_run.rebuild_sheets()
	if _berserk:
		var E = load("res://core/data/Effect.gd")
		_run.add_timed_effects("rage", "Berserk", [E.make("might", "mul", 0.5, "player"), E.make("haste", "mul", 1.0, "player")], 99999.0, true)
	_sig = _signature()


func _signature() -> String:
	var parts: Array = []
	for w in _run.weapons:
		parts.append("%s%d%s" % [w.def.id, w.level, str(w.mutations.size())])
	var ks: Array = _run.passives.keys()
	ks.sort()
	for k in ks:
		parts.append("%s%d" % [k, int(_run.passives[k])])
	parts.append(str(_run.level))
	return ",".join(parts)


func _check_build() -> void:
	if _frames % 30 != 0 and _measuring:
		return
	if _signature() != _sig:
		_restores += 1
		_apply_build()


func _keep_playing() -> void:
	var inp = _game.player.input
	if inp and not _game.paused:
		inp.wants_move = _walk != "still"
		inp.origin = Vector2(216, 500)
		if _walk == "s":
			inp.touch_pos = inp.origin + Vector2(sin(_t * 0.5) * 90.0, -110.0)
		else:
			var a := _phase_t * TAU / maxf(_period, 1.0)
			inp.touch_pos = inp.origin + Vector2(cos(a), sin(a)) * 110.0
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


# ---------------------------------------------------------------- the crowd

func _next_phase() -> void:
	_pi += 1
	if _pi >= _waves.size():
		_finish()
		return
	_phase_t = 0.0
	_measuring = false
	var w: int = int(_waves[_pi])
	var d = _game.director
	var em = _game.enemies
	em.kill_all(false)
	# every phase starts from the same spot (the walk would otherwise carry the hero to the map's edge)
	if _home == Vector3.INF:
		_home = _game.player.global_position
	else:
		_game.player.global_position = _home
	_run.stage = 0
	var tl = d.timeline
	_run.elapsed = float(tl.stage_end(0))
	_run.endless = true
	_run.endless_time = d.endless_wave_start(w) + 0.5
	d.set("_endless_speed", float(tl.endless_mults(w, 0)["speed"]))
	d.forget_sources()
	# the creatures' numbers at the hero level `src_level`, the same for every build
	var keep_level: int = _run.level
	_run.level = _src_level
	_src = {}
	var rows: Array = d.endless_rows()
	for id in _mix.keys():
		var best: Dictionary = {}
		var bw := -1.0
		for p: Dictionary in rows:
			if str(p["row"].get("enemy", "")) == id and float(p["w"]) > bw:
				bw = float(p["w"])
				best = p["row"]
		if best.is_empty():
			_src[id] = {"row": {}, "src": {}}
		else:
			_src[id] = {"row": best, "src": d._row_src(best)}
	d._apply_mults()
	_run.level = keep_level
	_run.rebuild_sheets()
	if _mode == "natural":
		d.running = true
		d.start_endless()
		em.kill_all(false)
		_run.endless_time = d.endless_wave_start(w)
		d._endless_wave = w - 1
	else:
		d.running = false
	var m: Dictionary = tl.endless_mults(w, 0)
	var info: Array = []
	for id in _src.keys():
		var s: Dictionary = _src[id]["src"]
		var def = root.get_node("Registry").enemy(id)
		var hp: float = def.hp * float(s.get("hp_time", 1.0)) * float(s.get("lv_hp", 1.0)) * em.creature_hp_mult * em.stage_mult if def else 0.0
		info.append("%s hp %.0f" % [id, hp])
	_log("phase %d: Endless wave %d (hp x%.2f, atk x%.2f, speed x%.2f), mode %s, crowd %d; creature HP at spawn (before variance): %s" % [_pi, w, float(m["hp"]), float(m["atk"]), float(m["speed"]), _mode, _n, ", ".join(info)])


func _top_up() -> void:
	var em = _game.enemies
	var live: int = em.count_alive
	if live >= _n:
		return
	var total := 0.0
	for id in _mix.keys():
		total += float(_mix[id])
	var d = _game.director
	for k in range(mini(_n - live, 12)):
		# the type furthest below its share of the crowd
		var pick := ""
		var worst := -INF
		for id in _mix.keys():
			var gap: float = float(_mix[id]) / total * float(_n) - float(em.alive_of(id))
			if gap > worst:
				worst = gap
				pick = id
		var e: Dictionary = _src.get(pick, {})
		if em.spawn(pick, d._spawn_point(), null, 1.0, 1.0, str(e.get("row", {}).get("variant", "")), d._stats_of(e.get("row", {})), e.get("src", {})) >= 0:
			_spawned += 1


# ---------------------------------------------------------------- measuring

func _reset() -> void:
	_sum = {}
	_frames = 0
	_probe_us = 0
	_wall_t0 = Time.get_ticks_usec()
	_last_us = _wall_t0
	_frame_ms = []
	_kills0 = int(_run.kills)
	_dmg0 = _dmg_total()
	_spawned = 0
	_steps_sum = 0
	_steps_max = 0
	_pf0 = Engine.get_physics_frames()


func _dmg_total() -> float:
	var s := 0.0
	for k in _run.damage_by_weapon.keys():
		s += float(_run.damage_by_weapon[k])
	return s


func _add(k: String, v: float) -> void:
	_sum[k] = float(_sum.get(k, 0.0)) + v


func _sample() -> void:
	var now := Time.get_ticks_usec()
	_frame_ms.append(float(now - _last_us) / 1000.0)
	_last_us = now
	_frames += 1
	_add("draws", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_add("t_physics", Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_add("t_process", Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_add("objects", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	_add("rcpu", RenderingServer.viewport_get_measured_render_time_cpu(_vp))
	_add("rgpu", RenderingServer.viewport_get_measured_render_time_gpu(_vp))
	_add("enemies", _game.enemies.count_alive)
	_add("shots", _game.projectiles.count)
	_add("fx", _game.fx._n)
	_add("pickups", _game.pickups.count)
	if _game.get("damage_numbers") != null and _game.damage_numbers:
		_add("numbers", _game.damage_numbers.count())
	if _frames % 6 == 0:
		var ps := Time.get_ticks_usec()
		_statuses()
		_probe_us += Time.get_ticks_usec() - ps


## How many creatures burn, are poisoned, frozen, slowed; how many stand within 3 and 6 m of the hero; how many are drawn;
## their mean HP left and max (every 6th frame).
func _statuses() -> void:
	var em = _game.enemies
	var ppos: Vector3 = _game.player.global_position
	var burn := 0
	var pois := 0
	var fro := 0
	var slo := 0
	var n3 := 0
	var n6 := 0
	var drawn := 0
	var hpl := 0.0
	var hpm := 0.0
	var n := 0
	var fire_srcs := 0
	var pois_srcs := 0
	for i in range(_C["MAX"]):
		if em.alive[i] == 0:
			continue
		n += 1
		var fs: Dictionary = em.fire_src[i]
		if not fs.is_empty():
			burn += 1
			fire_srcs += fs.size()
		var pz: Dictionary = em.poison_src[i]
		if not pz.is_empty():
			pois += 1
			pois_srcs += pz.size()
		if em.freeze_t[i] > 0.0:
			fro += 1
		if em.slow_t[i] > 0.0:
			slo += 1
		var dx: float = em.pos[i].x - ppos.x
		var dz: float = em.pos[i].z - ppos.z
		var d2 := dx * dx + dz * dz
		if d2 < 9.0:
			n3 += 1
		if d2 < 36.0:
			n6 += 1
		if em.drawn_vis[i] == 1:
			drawn += 1
		hpl += em.hp[i]
		hpm += em.max_hp[i]
	_add("st.n", 1.0)
	_add("st.burning", burn)
	_add("st.poisoned", pois)
	_add("st.frozen", fro)
	_add("st.slowed", slo)
	_add("st.fire_srcs", fire_srcs)
	_add("st.poison_srcs", pois_srcs)
	_add("st.near3", n3)
	_add("st.near6", n6)
	_add("st.drawn", drawn)
	_add("st.hp_left", hpl / maxf(n, 1))
	_add("st.might", _run.player_sheet.get_stat("might", 1.0))
	_add("st.haste", _run.haste)
	# the crowd's quads on the screen (as drawn, before the alpha cut) over the screen's pixels: the GPU's fill, which a
	# PC's timers cannot show for a phone
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	if cam:
		var up := cam.global_transform.basis.y
		var right := cam.global_transform.basis.x
		var vr := root.get_visible_rect()
		var area := 0.0
		for i in range(_C["MAX"]):
			if em.alive[i] == 0 or em.hidden[i] == 1 or em.drawn_vis[i] == 0:
				continue
			var s: float = em.size[i]
			var foot: Vector3 = em.pos[i]
			if cam.is_position_behind(foot):
				continue
			var a := cam.unproject_position(foot)
			var r := Rect2(a, Vector2.ZERO).expand(cam.unproject_position(foot + up * s)).expand(cam.unproject_position(foot + up * (s * 0.5) - right * (s * 0.5))).expand(cam.unproject_position(foot + up * (s * 0.5) + right * (s * 0.5)))
			var vis := r.intersection(vr)
			if vis.has_area():
				area += vis.get_area()
		_add("st.quad_screens", area / vr.get_area())
	_add("st.hp_max", hpm / maxf(n, 1))


func _report() -> void:
	var r: Dictionary = _perf.report()
	var n := maxf(_frames, 1)
	var wall := float(Time.get_ticks_usec() - _wall_t0 - _probe_us) / 1000.0 / n
	_frame_ms.sort()
	var p50: float = _frame_ms[int(_frame_ms.size() * 0.5)] if not _frame_ms.is_empty() else 0.0
	var p95: float = _frame_ms[int(_frame_ms.size() * 0.95)] if not _frame_ms.is_empty() else 0.0
	var keys: Array = []
	for k in r.keys():
		if not k in ["frames", "worst_ms", "slow", "slow_log"]:
			keys.append(k)
	keys.sort_custom(func(a, b): return float(r[a]) > float(r[b]))
	var parts: Array = []
	var game_ms := 0.0
	for k in keys:
		game_ms += float(r[k])
		if float(r[k]) >= 0.02:
			parts.append("%s %.2f" % [k, r[k]])
	var sn := maxf(float(_sum.get("st.n", 1.0)), 1.0)
	var secs := n / 60.0
	var row := {"tag": _tag, "build": _build_name, "over": _over, "drop_mut": _drop_mut, "wave": int(_waves[_pi]), "mode": _mode,
		"wall_ms": wall, "p50": p50, "p95": p95, "timed_ms": game_ms, "perf": {}, "draws": _sum["draws"] / n,
		"rcpu": _sum["rcpu"] / n, "rgpu": _sum["rgpu"] / n, "alive": _sum["enemies"] / n, "shots": _sum["shots"] / n,
		"fx": _sum["fx"] / n, "pickups": _sum["pickups"] / n, "numbers": float(_sum.get("numbers", 0.0)) / n,
		"kills_s": float(int(_run.kills) - _kills0) / secs, "dmg_s": (_dmg_total() - _dmg0) / secs,
		"spawned_s": float(_spawned) / secs, "restores": _restores,
		"t_physics": _sum["t_physics"] / n, "t_process": _sum["t_process"] / n, "haste_now": _run.haste,
		"cap": Engine.max_physics_steps_per_frame, "busy_tick": _busy_tick, "busy_frame": _busy_frame,
		"steps_mean": float(_steps_sum) / n, "steps_max": _steps_max,
		"world_speed": float(Engine.get_physics_frames() - _pf0) / float(Engine.physics_ticks_per_second) / maxf(float(Time.get_ticks_usec() - _wall_t0) / 1.0e6, 0.001)}
	for k in keys:
		row["perf"][k] = float(r[k])
	for k in ["burning", "poisoned", "frozen", "slowed", "fire_srcs", "poison_srcs", "near3", "near6", "drawn", "hp_left", "hp_max", "might", "haste", "quad_screens"]:
		row[k] = float(_sum.get("st." + k, 0.0)) / sn
	_rows.append(row)
	_log("[%s wave %d] %.2f ms/frame (p50 %.1f, p95 %.1f) | timed systems %.2f: %s" % [_build_name, int(_waves[_pi]), wall, p50, p95, game_ms, ", ".join(parts)])
	_log("    crowd %.0f (drawn %.0f, within 6 m %.0f, within 3 m %.0f), mean HP %.0f of %.0f | burning %.0f (%.1f sources), poisoned %.0f, frozen %.0f, slowed %.0f" % [row["alive"], row["drawn"], row["near6"], row["near3"], row["hp_left"], row["hp_max"], row["burning"], row["fire_srcs"], row["poisoned"], row["frozen"], row["slowed"]])
	var hp3: Vector3 = _game.player.global_position
	_log("    hero at (%.0f, %.0f), %.0f m from the phase's start" % [hp3.x, hp3.z, Vector2(hp3.x - _home.x, hp3.z - _home.z).length()])
	_log("    hero might %.2f, haste %.2f | creature quads %.2f screens | engine: physics step %.2f ms, process step %.2f ms" % [row["might"], row["haste"], row["quad_screens"], row["t_physics"], row["t_process"]])
	var em = _game.enemies
	var dn = _game.get("damage_numbers")
	_log("    hits (lane HITS, since the start): hit sounds %d played, %d gated | flames %d drawn, %d skipped | numbers joined %d, let go %d" % [int(em.get("hit_sounds")), int(em.get("hit_sounds_gated")), int(em.get("fire_fx_drawn")), int(em.get("fire_fx_skipped")), int(dn.get("crowd_merged")) if dn else 0, int(dn.get("crowd_dropped")) if dn else 0])
	_log("    shots %.0f, particles %.0f, pickups %.0f, numbers %.0f | kills %.1f/s, spawns %.1f/s, damage %.0f/s | draws %.0f, objects %.0f, render cpu %.2f, gpu %.2f ms | build restores %d" % [row["shots"], row["fx"], row["pickups"], row["numbers"], row["kills_s"], row["spawned_s"], row["dmg_s"], row["draws"], _sum["objects"] / n, row["rcpu"], row["rgpu"], _restores])


func _log(s: String) -> void:
	print("p102repro: " + s)
	_out.append(s)


func _finish() -> void:
	var dir := "D:/_projects/88fits/tools/dl/p102"
	var f := FileAccess.open(dir + "/repro_%s.txt" % _tag, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_out) + "\n")
		f.close()
	var j := FileAccess.open(dir + "/repro_%s.json" % _tag, FileAccess.WRITE)
	if j:
		j.store_string(JSON.stringify(_rows, " "))
		j.close()
	quit(0)
