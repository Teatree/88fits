## Late-game performance benchmark (pass 33.8): a maxed build in the stage-3 crowd, god mode, an S-shaped walk, and
## every 10 s of game time the milliseconds each system took per frame, the frame's wall time and worst frame, the
## crowd, shots and particles, and (windowed) the draw calls. With --fixed-fps every frame is exactly one frame of game
## time, so --fixed-fps 60 is a 60 fps phone and --fixed-fps 30 one that has dropped to 30 (two physics ticks a frame).
##   "$GODOT" --audio-driver Dummy --resolution 504x1122 --fixed-fps 60 --path game --script res://tools/perf_late.gd -- seconds=40 build=six
##   args: seconds= (measured, default 40), warm= (seconds before measuring, 15), build=six|six_b|none, t= (the clock; by
##         default a third of the way into stage 3: 700 s of 300 s stages, 1003 s of Red Canyon's 430 s stages since pass
##         46, the same crowd), level= (45), analytics=0, numbers=0 (no damage numbers: the game's DamageNumbers is
##         suppressed, Settings never touched, so the save keeps the player's switch; pass 47), shadows=0 (the scenery's
##         ground shadows hidden, pass 83). Headless works too, without
##         the draw calls.
## Autoloads are reached through the tree: SceneTree scripts compile before they exist.
extends SceneTree

const BUILDS := {
	"six": ["chicago_typewriter", "missile_massacre", "saw_halo", "firestorm", "storm_cloud", "killer_swarm"],
	"six_b": ["bullet_hose", "doomstick", "cluster_bomb", "plague_volley", "loudmouth", "turret_family"],
}
const PASSIVES := ["multishot", "haste", "reach", "quickdraw", "overkill", "ricochet"]

var _secs := 40.0
var _warm := 15.0
var _build := "six"
var _clock := -1.0        # below zero: from the map's stage length (see the header)
var _level := 45
var _t := 0.0
var _game: Node
var _run: Node
var _perf
var _vp: RID
var _setup := false
var _measuring := false
var _next := 0.0
var _wall := 0
var _frames := 0
var _analytics := true   # analytics=0: no run recorder (pass 45), the A/B of its cost
var _numbers := true     # numbers=0: no damage numbers (pass 46), the A/B of their cost (never through Settings: pass 47)
var _sum := {}
## shadows=0 (pass 83): the scenery's ground shadows hidden (PropField's GroundShadows), the A/B of their cost
var _shadows := true


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seconds="):
			_secs = float(a.substr(8))
		elif a.begins_with("warm="):
			_warm = float(a.substr(5))
		elif a.begins_with("build="):
			_build = a.substr(6)
		elif a.begins_with("t="):
			_clock = float(a.substr(2))
		elif a.begins_with("level="):
			_level = int(a.substr(6))
		elif a == "analytics=0":
			_analytics = false
		elif a == "numbers=0":
			_numbers = false
		elif a == "shadows=0":
			_shadows = false
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "peashooter", "level": 1, "character": "astro", "map": "red_canyon", "map_seed": 7, "analytics": _analytics}))
	f.close()
	root.get_node("Save").data["runs_started"] = 1
	_run = root.get_node("Run")
	_perf = load("res://core/systems/Perf.gd")
	_vp = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	change_scene_to_file("res://game/Game.tscn")
	process_frame.connect(_tick)


func _tick() -> void:
	_t += root.get_process_delta_time()
	if _game == null:
		var g = current_scene
		if g == null or not g.has_method("open_pause") or g.player == null:
			return
		_game = g
		_game.player.god = true
		# numbers=0 switches off this run's numbers only: setting Settings.damage_numbers here was saved by the run's
		# next save and left the PC without numbers (pass 47)
		if not _numbers and _game.get("damage_numbers") != null:
			_game.damage_numbers.suppressed = true
		if not _shadows and _game.map and _game.map.get("props") != null:
			var gs: Node = _game.map.get("props").get_node_or_null("GroundShadows")
			if gs:
				gs.visible = false
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
	if not _setup and _t > 1.0 and not _run.weapons.is_empty():
		_setup = true
		_make_build()
	if _setup and not _measuring and _t > _warm:
		_measuring = true
		_perf.report()
		_reset()
		_next = _t + 10.0
	if _measuring:
		_sample()
		if _t >= _next:
			_report()
			_next = _t + 10.0
	if _t > _warm + _secs:
		quit(0)


func _make_build() -> void:
	var reg = root.get_node("Registry")
	_run.debug_clear_items()
	if _build == "none":
		_run.debug_set_item("weapon", "peashooter", 1)
	else:
		for id in BUILDS.get(_build, BUILDS["six"]):
			_run.debug_set_item("evolution", id, 99)
			var inst = _run.weapon_instance(id)
			if inst == null:
				# past the weapon slots (five since pass 52): the build is the first five
				continue
			var picks := 0
			for m in reg.mutations_of(inst.family_id()):
				if picks < 2 and not m.is_hero():
					_run.debug_set_item("mutation", m.id, 1)
					picks += 1
		for p in PASSIVES:
			_run.debug_set_item("passive", p, 99)
	_run.level = _level
	_run.stage = 2
	if _clock < 0.0:
		var sl: float = float(_game.director.timeline.stage_length)
		_clock = 2.0 * sl + sl / 3.0
	_run.elapsed = _clock
	var d = _game.director
	for k in range(d.timeline.events.size()):
		if float(d.timeline.events[k].get("t", 0.0)) < _clock:
			d._event_i = k + 1
	d._apply_mults()
	_run.rebuild_sheets()
	print("perf_late: build %s -> %s, level %d, clock %.0f" % [_build, str(_run.weapons.map(func(w): return w.def.id)), _run.level, _run.elapsed])


func _reset() -> void:
	_sum = {}
	_frames = 0
	_wall = Time.get_ticks_usec()


func _add(k: String, v: float) -> void:
	_sum[k] = float(_sum.get(k, 0.0)) + v


func _sample() -> void:
	_frames += 1
	_add("draws", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_add("rcpu", RenderingServer.viewport_get_measured_render_time_cpu(_vp))
	_add("enemies", _game.enemies.count_alive)
	_add("shots", _game.projectiles.count)
	_add("fx", _game.fx._n)


func _report() -> void:
	var r: Dictionary = _perf.report()
	var n := maxf(_frames, 1)
	var wall := float(Time.get_ticks_usec() - _wall) / 1000.0 / n
	var keys: Array = []
	for k in r.keys():
		if not k in ["frames", "worst_ms", "slow", "slow_log"]:
			keys.append(k)
	keys.sort_custom(func(a, b): return float(r[a]) > float(r[b]))
	var parts: Array = []
	for k in keys:
		if float(r[k]) >= 0.02:
			parts.append("%s %.2f" % [k, r[k]])
	print("perf_late: t=%3d | %.2f ms/frame, worst %.1f | %s" % [int(_t), wall, r["worst_ms"], ", ".join(parts)])
	print("perf_late:        creatures %.0f, shots %.0f, particles %.0f | draw calls %.0f, render cpu %.2f ms" % [_sum["enemies"] / n, _sum["shots"] / n, _sum["fx"] / n, _sum["draws"] / n, _sum["rcpu"] / n])
	_reset()
