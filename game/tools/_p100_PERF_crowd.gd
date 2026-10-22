## Pass 100, lane PERF (assessment only): what a crowd costs as it grows, on the PC. The stage-3 look, the director held,
## a controlled crowd of a stage-3 mix topped up to N every frame round the god-mode hero, who walks the S of perf_late.
## Each phase settles 2 s and is measured `hold` s: wall ms a frame, the game's Perf keys, draw calls, render cpu/gpu,
## video and texture memory. Then A/B toggles at the top crowd (creature shadows hidden, the occluded-outline pass off,
## the 3D pass at the phone's pixel count), a sub-timing phase of EnemyManager's pieces called once more each frame, and
## the late build (six) at the top crowd. Results also go to tools/dl/p100/PERF/crowd_<tag>.txt.
##   bash tools/godot.sh --audio-driver Dummy --resolution 504x1122 --fixed-fps 60 --path game --script res://tools/_p100_PERF_crowd.gd -- tag=a
## args: hold= (s, default 6), tag=, plan=sizes|toggles|sub|six|all (default all), phone_scale= (default 2.13: 1075x2394
## 3D pixels, the Pixel 8 Pro's 1344x2992 at scale 0.8, from a 504x1122 window)
## Never touches Settings or the save (tools/godot.sh keeps the PC save aside anyway). A watchdog quits at 600 s.
extends SceneTree

const MIX := [["skeleton", 4], ["skeleton_knight", 3], ["hellhound", 3], ["imp", 3], ["dust_mummy", 2], ["fire_ant", 2],
	["horned_toad", 2], ["dust_shaman", 1], ["werewolf", 1], ["armadillo", 1], ["buckshot_dwarf", 1], ["hammer_giant", 1],
	["bull_beetle", 1], ["spit_cactus", 1]]
const SIX := ["chicago_typewriter", "missile_massacre", "saw_halo", "firestorm", "storm_cloud", "killer_swarm"]
const PASSIVES := ["multishot", "haste", "reach", "quickdraw", "overkill", "ricochet"]

var _hold := 6.0
var _tag := "a"
var _plan := "all"
var _phone_scale := 2.13
var _hero := "drifter"
var _weapon := "peashooter"
var _sizes: Array = [0, 50, 100, 150, 200, 250, 300]
var _game: Node
var _run: Node
var _perf
var _vp: RID
var _t := 0.0
var _wall_t0 := 0
var _phases: Array = []
var _pi := -1
var _phase_t := 0.0
var _target := 0
var _sum := {}
var _frames := 0
var _rng := RandomNumberGenerator.new()
var _pool: Array = []
var _out: Array = []
var _last_us := 0
var _worst := 0.0
var _frame_ms: Array = []
var _C: Dictionary = {}


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("hold="):
			_hold = float(a.substr(5))
		elif a.begins_with("tag="):
			_tag = a.substr(4)
		elif a.begins_with("plan="):
			_plan = a.substr(5)
		elif a.begins_with("phone_scale="):
			_phone_scale = float(a.substr(12))
		elif a.begins_with("hero="):
			_hero = a.substr(5)
		elif a.begins_with("weapon="):
			_weapon = a.substr(7)
		elif a.begins_with("sizes="):
			_sizes = Array(a.substr(6).split(",")).map(func(x): return int(x))
	_rng.seed = 100
	for m in MIX:
		for k in range(int(m[1])):
			_pool.append(m[0])
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": _weapon, "level": 1, "character": _hero, "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	root.get_node("Save").data["runs_started"] = 1
	_run = root.get_node("Run")
	_perf = load("res://core/systems/Perf.gd")
	_vp = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	change_scene_to_file("res://game/Game.tscn")
	process_frame.connect(_tick)
	_build_plan()


func _build_plan() -> void:
	# {name, n, shadows, sil, scale, sub, six}
	var base := {"shadows": true, "sil": true, "scale": 1.0, "sub": false, "six": false, "numbers": true, "od": false}
	if _plan in ["all", "sizes"]:
		for n in _sizes:
			_phases.append(_ph(base, "crowd %d" % n, n, {}))
	if _plan in ["all", "toggles"]:
		_phases.append(_ph(base, "300 base", 300, {}))
		_phases.append(_ph(base, "300 no creature shadows", 300, {"shadows": false}))
		_phases.append(_ph(base, "300 no occluded-outline pass", 300, {"sil": false}))
		_phases.append(_ph(base, "300 neither", 300, {"shadows": false, "sil": false}))
		_phases.append(_ph(base, "300 phone pixels", 300, {"scale": _phone_scale}))
		_phases.append(_ph(base, "300 phone pixels, neither", 300, {"scale": _phone_scale, "shadows": false, "sil": false}))
		_phases.append(_ph(base, "0 phone pixels", 0, {"scale": _phone_scale}))
		_phases.append(_ph(base, "150 phone pixels", 150, {"scale": _phone_scale}))
	if _plan == "natural":
		for k in range(6):
			_phases.append(_ph(base, "natural director %d" % k, -1, {"od": true, "six": k >= 3}))
	if _plan == "gpu":
		_phases.append(_ph(base, "gpu six phone px base", 300, {"six": true, "scale": _phone_scale}))
		for k in range(40):
			_phases.append(_ph(base, "gpu hide #%d" % k, 300, {"six": true, "scale": _phone_scale, "hide": k}))
		_phases.append(_ph(base, "gpu six phone px base again", 300, {"six": true, "scale": _phone_scale}))
	if _plan in ["all", "sub"]:
		_phases.append(_ph(base, "300 sub-timings", 300, {"sub": true}))
		_phases.append(_ph(base, "300 overdraw and neighbours", 300, {"od": true}))
		_phases.append(_ph(base, "150 overdraw and neighbours", 150, {"od": true}))
		_phases.append(_ph(base, "300 no damage numbers", 300, {"numbers": false}))
	if _plan in ["all", "six"]:
		_phases.append(_ph(base, "300 build six", 300, {"six": true}))
		_phases.append(_ph(base, "300 build six phone pixels", 300, {"six": true, "scale": _phone_scale}))


func _ph(base: Dictionary, name: String, n: int, over: Dictionary) -> Dictionary:
	var p := base.duplicate()
	p.merge(over, true)
	p["name"] = name
	p["n"] = n
	return p


func _tick() -> void:
	var dt := root.get_process_delta_time()
	_t += dt
	if _t > 600.0:
		_log("watchdog: quit at 600 s")
		_finish()
		return
	if _game == null:
		var g = current_scene
		if g == null or not g.has_method("open_pause") or g.player == null or g.get("director") == null:
			return
		_game = g
		_game.player.god = true
		_C = _game.enemies.get_script().get_script_constant_map()
		_setup_world()
		return
	_keep_playing()
	if _pi < 0:
		if _t > 3.0:
			_next_phase()
		return
	var ph: Dictionary = _phases[_pi]
	_top_up(int(ph["n"]))
	_phase_t += dt
	if _phase_t < 2.0:
		return
	if _phase_t - dt < 2.0:
		_perf.report()
		_reset()
		return
	_sample(ph)
	if _phase_t >= 2.0 + _hold:
		if ph["name"] != "skip":
			_report(ph)
		_next_phase()


func _setup_world() -> void:
	var d = _game.director
	d.running = _plan == "natural"
	_run.stage = 2
	var tl3 = d.timeline
	_run.elapsed = float(tl3.stage_start(2)) + float(tl3.stage_len(2)) / 3.0
	d._apply_mults()
	var look = load("res://core/systems/StageLook.gd").of(_game)
	look.stage = -1
	look.show_stage(2, 0.0)
	if _plan != "natural":
		_game.enemies.kill_all(false)
	else:
		for k in range(d.timeline.events.size()):
			if float(d.timeline.events[k].get("t", 0.0)) < _run.elapsed:
				d._event_i = k + 1
	_log("setup: stage look 3, clock %.0f, director held; window %s; renderer %s" % [_run.elapsed, str(root.size), RenderingServer.get_current_rendering_method()])


func _keep_playing() -> void:
	var inp = _game.player.input
	if inp and not _game.paused:
		inp.wants_move = true
		inp.origin = Vector2(216, 500)
		inp.touch_pos = inp.origin + Vector2(sin(_t * 0.5) * 90.0, -110.0)
	if _game.cards and _game.cards.visible and not _game.cards._offer.is_empty() and not _game.cards._picking:
		_game.cards._pick(_game.cards._offer[0])
	if _game.get("chest_screen") and _game.chest_screen and _game.chest_screen.visible and not _game.chest_screen._spinning:
		_game.chest_screen._finish(false)
	if _game.get("resume_gate") and _game.resume_gate and _game.resume_gate.visible:
		_game.resume_gate.tap()
	if _game.portal_dialog and _game.portal_dialog.visible:
		_game.portal_dialog.visible = false
		_game.portal_dialog.decided.emit(false)


func _top_up(n: int) -> void:
	if n < 0:
		return
	var em = _game.enemies
	var live: int = em.count_alive
	if live > n:
		# trim the extra (a phase that lowers the crowd): free the newest ones
		var drop := live - n
		for i in range(_C["MAX"] - 1, -1, -1):
			if drop <= 0:
				break
			if em.alive[i] == 1 and em.state[i] != _C["STATE_DYING"]:
				em._free(i)
				drop -= 1
		return
	var need := mini(n - live, 12)
	var hp: Vector3 = _game.player.global_position
	for k in range(need):
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(5.0, 15.0)
		var at := hp + Vector3(cos(a) * r, 0, sin(a) * r * 1.3)
		em.spawn(str(_pool[_rng.randi() % _pool.size()]), at, null, 1.0, 2.5)


func _next_phase() -> void:
	_pi += 1
	if _pi >= _phases.size():
		_finish()
		return
	_phase_t = 0.0
	var ph: Dictionary = _phases[_pi]
	_apply(ph)


func _apply(ph: Dictionary) -> void:
	var em = _game.enemies
	em._shadow_mmi.visible = bool(ph["shadows"])
	for t in em.types:
		var mat: ShaderMaterial = t["mat"]
		if bool(ph["sil"]):
			if mat.next_pass == null and t.has("_sil_keep"):
				mat.next_pass = t["_sil_keep"]
		elif mat.next_pass != null:
			t["_sil_keep"] = mat.next_pass
			mat.next_pass = null
	root.scaling_3d_scale = float(ph["scale"])
	# the gpu plan: one of the game's (and its map's) visible 3D children hidden at a time
	var cands := _hide_cands()
	for c: Node3D in cands:
		c.visible = true
	if ph.has("hide"):
		var k: int = ph["hide"]
		if k >= cands.size():
			ph["name"] = "skip"
			_phase_t = 999.0
		else:
			cands[k].visible = false
			ph["name"] = "gpu hidden: %s (%s)" % [str(_game.get_path_to(cands[k])), cands[k].get_class()]
	if _game.get("damage_numbers") != null and _game.damage_numbers:
		_game.damage_numbers.suppressed = not bool(ph["numbers"])
	if bool(ph["six"]) and not _run.weapons.any(func(w): return w.def.id == "chicago_typewriter"):
		var reg = root.get_node("Registry")
		_run.debug_clear_items()
		for id in SIX:
			_run.debug_set_item("evolution", id, 99)
			var inst = _run.weapon_instance(id)
			if inst == null:
				continue
			var picks := 0
			for m in reg.mutations_of(inst.family_id()):
				if picks < 2 and not m.is_hero():
					_run.debug_set_item("mutation", m.id, 1)
					picks += 1
		for p in PASSIVES:
			_run.debug_set_item("passive", p, 99)
		_run.level = 45
		_run.rebuild_sheets()


var _cands: Array = []


func _hide_cands() -> Array:
	if not _cands.is_empty():
		return _cands
	for c in _game.get_children():
		if c is Node3D and (c as Node3D).visible:
			_cands.append(c)
	var m = _game.get("map")
	if m is Node:
		for c in (m as Node).get_children():
			if c is Node3D and (c as Node3D).visible:
				_cands.append(c)
	return _cands


func _reset() -> void:
	_sum = {}
	_frames = 0
	_wall_t0 = Time.get_ticks_usec()
	_last_us = _wall_t0
	_worst = 0.0
	_frame_ms = []


func _add(k: String, v: float) -> void:
	_sum[k] = float(_sum.get(k, 0.0)) + v


func _sample(ph: Dictionary) -> void:
	var now := Time.get_ticks_usec()
	var ms := float(now - _last_us) / 1000.0
	_last_us = now
	_worst = maxf(_worst, ms)
	_frame_ms.append(ms)
	_frames += 1
	_add("draws", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_add("objects", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	_add("prims", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_add("rcpu", RenderingServer.viewport_get_measured_render_time_cpu(_vp))
	_add("rgpu", RenderingServer.viewport_get_measured_render_time_gpu(_vp))
	_add("enemies", _game.enemies.count_alive)
	_add("shots", _game.projectiles.count)
	_add("fx", _game.fx._n)
	if bool(ph["sub"]):
		_sub_timings()
	if bool(ph["od"]):
		_overdraw()


## EnemyManager's pieces, each called once more this frame and timed (the tick's own calls are untouched): the grid, the
## obstacle cells, the screen flags, the steering of every creature (dt 0: no clocks move), the height lookups, the draw.
func _sub_timings() -> void:
	var em = _game.enemies
	var ppos: Vector3 = _game.player.global_position
	var t0 := Time.get_ticks_usec()
	em._rebuild_grid()
	var t1 := Time.get_ticks_usec()
	em._obstacle_cells()
	var t2 := Time.get_ticks_usec()
	em.refresh_onscreen(-1)
	var t3 := Time.get_ticks_usec()
	for i in range(_C["MAX"]):
		if em.alive[i] == 1 and em.state[i] == _C["STATE_MOVE"]:
			em._steer(i, ppos, 0.0)
	var t4 := Time.get_ticks_usec()
	var hs := 0.0
	for i in range(_C["MAX"]):
		if em.alive[i] == 1:
			hs += em._height(em.pos[i].x, em.pos[i].z)
	var t5 := Time.get_ticks_usec()
	em._render()
	var t6 := Time.get_ticks_usec()
	var n := 0
	for i in range(_C["MAX"]):
		if em.alive[i] == 1:
			n += 1
			em.tint_of(i)
			em._strip_of(i, em.type_idx[i])
	var t7 := Time.get_ticks_usec()
	_add("sub.grid", float(t1 - t0) / 1000.0)
	_add("sub.obstacle_cells", float(t2 - t1) / 1000.0)
	_add("sub.onscreen(all)", float(t3 - t2) / 1000.0)
	_add("sub.steer(all moving)", float(t4 - t3) / 1000.0)
	_add("sub.height(all)", float(t5 - t4) / 1000.0)
	_add("sub.render", float(t6 - t5) / 1000.0)
	_add("sub.tint+strip(all)", float(t7 - t6) / 1000.0)


## The pixels the crowd covers this frame (its quads as drawn, before the alpha cut) and the creature shadows' quads, over
## the viewport's pixels; and how many creatures each one's separation walks over (its 3 x 3 grid cells).
func _overdraw() -> void:
	var em = _game.enemies
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	if cam == null:
		return
	var right := cam.global_transform.basis.x
	var up := cam.global_transform.basis.y
	var area := 0.0
	var on := 0
	var nb := 0
	var nn := 0
	var vr := root.get_visible_rect()
	for i in range(_C["MAX"]):
		if em.alive[i] == 0 or em.hidden[i] == 1:
			continue
		var s: float = em.size[i]
		var foot: Vector3 = em.pos[i]
		if cam.is_position_behind(foot):
			continue
		var a := cam.unproject_position(foot)
		var b := cam.unproject_position(foot + up * s)
		var c := cam.unproject_position(foot + up * (s * 0.5) - right * (s * 0.5))
		var d := cam.unproject_position(foot + up * (s * 0.5) + right * (s * 0.5))
		var r := Rect2(a, Vector2.ZERO).expand(b).expand(c).expand(d)
		var vis := r.intersection(vr)
		if vis.has_area():
			area += vis.get_area()
			on += 1
		var gx: int = em._gcol(foot.x)
		var gz: int = em._gcol(foot.z)
		for cx in range(maxi(gx - 1, 0), mini(gx + 2, em._gw)):
			for cz in range(maxi(gz - 1, 0), mini(gz + 2, em._gw)):
				var j: int = em._g_head[cz * em._gw + cx]
				while j >= 0:
					nb += 1
					j = em._g_next[j]
		nn += 1
	var sh := 0.0
	var smm: MultiMesh = em._shadow_mm
	for k in range(smm.visible_instance_count):
		var xf := smm.get_instance_transform(k)
		var pts: Array = []
		for o in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
			var w: Vector3 = xf.origin + xf.basis.x * o.x + xf.basis.z * o.y
			if cam.is_position_behind(w):
				pts = []
				break
			pts.append(cam.unproject_position(w))
		if pts.size() == 4:
			var sa := 0.0
			for q in range(4):
				var p0: Vector2 = pts[q]
				var p1: Vector2 = pts[(q + 1) % 4]
				sa += p0.x * p1.y - p1.x * p0.y
			sh += absf(sa) * 0.5
	var px := vr.get_area()
	var flags := 0
	for i in range(_C["MAX"]):
		if em.alive[i] == 1 and em.onscreen[i] == 1:
			flags += 1
	_add("od.game_onscreen_flags", float(flags))
	_add("od.alive", float(em.count_alive))
	_add("od.creature_quads_on_screen", float(on))
	_add("od.creature_quad_px/screen", area / px)
	_add("od.shadow_px/screen", sh / px)
	_add("od.shadows", float(smm.visible_instance_count))
	_add("od.neighbours_walked_per_creature", float(nb) / maxf(float(nn), 1.0))
	_add("od.ppm", float(_game.camera.pixels_per_metre()) if _game.camera.has_method("pixels_per_metre") else 0.0)


func _report(ph: Dictionary) -> void:
	var r: Dictionary = _perf.report()
	var n := maxf(_frames, 1)
	var wall := float(Time.get_ticks_usec() - _wall_t0) / 1000.0 / n
	_frame_ms.sort()
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
	_log("[%s] %.2f ms/frame (p95 %.1f, worst %.1f) | timed systems %.2f: %s" % [ph["name"], wall, p95, _worst, game_ms, ", ".join(parts)])
	_log("    creatures %.0f, shots %.0f, particles %.0f | draws %.0f, objects %.0f, prims %.0f | render cpu %.2f, gpu %.2f ms | vmem %.0f MB, tex %.0f MB, 3d scale %.2f" % [
		_sum["enemies"] / n, _sum["shots"] / n, _sum["fx"] / n, _sum["draws"] / n, _sum["objects"] / n, _sum["prims"] / n,
		_sum["rcpu"] / n, _sum["rgpu"] / n, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, root.scaling_3d_scale])
	if bool(ph["sub"]):
		var sp: Array = []
		for k in _sum.keys():
			if str(k).begins_with("sub."):
				sp.append("%s %.3f" % [str(k).substr(4), float(_sum[k]) / n])
		_log("    sub-timings (ms a frame, an extra call each): " + ", ".join(sp))
	if bool(ph["od"]):
		var op: Array = []
		for k in _sum.keys():
			if str(k).begins_with("od."):
				op.append("%s %.2f" % [str(k).substr(3), float(_sum[k]) / n])
		_log("    overdraw (window %s): %s" % [str(root.get_visible_rect().size), ", ".join(op)])
	if _pi == 0 or ph["name"] == "300 base":
		var tl: Array = []
		for t in _game.enemies.types:
			var mm: MultiMesh = t["mm"]
			if mm.visible_instance_count > 0:
				tl.append("%s x%d" % [str(t["def"].type_key()), mm.visible_instance_count])
		_log("    types drawn (%d): %s" % [tl.size(), ", ".join(tl)])


func _log(s: String) -> void:
	print("p100perf: " + s)
	_out.append(s)


func _finish() -> void:
	var path := "D:/_projects/88fits/tools/dl/p100/PERF/crowd_%s.txt" % _tag
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_out) + "\n")
		f.close()
	quit(0)
