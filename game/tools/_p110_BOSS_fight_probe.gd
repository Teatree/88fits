## Pass 110 (lane BOSS): one stage's boss fight watched. A stage run (its window's start, the stage's own clock), a fixed
## build from tools/difficulty_probe.gd dropped in `before` seconds before the stage's end (the stage's last rows build
## their crowd), the kiting autopilot (tools/sim_pilot.gd), the hero never hurt (god), and the boss held alive (its HP put
## back every frame) so the fight plays `secs` seconds. Every 5 s of the fight: the bodies alive, the load, the cap the
## director reports, the window's cycle second and what it brought, the crowd by creature. `window=0` switches the
## stage's boss-fight window off (enabled false in memory only): the fight as it was before pass 110, to compare. The Save
## is sandboxed (never written), the run writes no analytics record, a watchdog quits a stuck run.
##   bash tools/godot.sh --headless --fixed-fps 60 --path game --script res://tools/_p110_BOSS_fight_probe.gd -- \
##       stage=0 build=b1 level=22 hero=calavera secs=150 before=60 seed=11 window=1
## Autoloads are reached through the tree (SceneTree scripts compile before they exist).
extends SceneTree

const PILOT := preload("res://tools/sim_pilot.gd")
const PROBE := preload("res://tools/difficulty_probe.gd")

var _stage := 0
var _build := "b1"
var _level := 22
var _hero := "calavera"
var _secs := 150.0
var _before := 60.0
var _seed := 11
var _window := 1
var _game: Node
var _run: Node
var _pilot: PILOT
var _t := 0.0
var _set := false
var _fight_t0 := -1.0
var _next := 0.0
var _rows: Array = []
var _arrival: Dictionary = {}
var _alive_series: Array = []
var _done := false


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"stage": _stage = int(kv[1])
			"build": _build = kv[1]
			"level": _level = int(kv[1])
			"hero": _hero = kv[1]
			"secs": _secs = float(kv[1])
			"before": _before = float(kv[1])
			"seed": _seed = int(kv[1])
			"window": _window = int(kv[1])
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	_pilot = PILOT.new(_seed)
	var save := root.get_node_or_null("Save")
	if save == null or root.get_node_or_null("Run") == null:
		printerr("bossprobe: the autoloads did not load; nothing run")
		quit(2)
		return
	save.begin_sandbox()
	save.data["runs_started"] = 1
	save.data["talents"] = {}
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": PROBE.START.get(_hero, "revolver"), "level": 1, "character": _hero, "map": "red_canyon",
		"map_seed": _seed, "analytics": false, "sim_clock": true, "stage": _stage + 1}))
	f.close()
	_run = root.get_node("Run")
	change_scene_to_file("res://game/Game.tscn")
	process_frame.connect(_tick)


func _tick() -> void:
	var dt: float = root.get_process_delta_time()
	_t += dt
	if _t > (_before + _secs) * 3.0 + 240.0 and not _done:
		print("bossprobe: watchdog after %.0f s" % _t)
		_report()
		quit(3)
		return
	if _game == null:
		var g = current_scene
		if g == null or not g.has_method("open_pause") or g.player == null:
			return
		_game = g
		_game.player.god = true
		if _game.get("damage_numbers") != null and _game.damage_numbers:
			_game.damage_numbers.suppressed = true
	_screens()
	if not _set and _t > 0.6 and not _run.weapons.is_empty():
		_setup()
	if not _set or _done:
		return
	_game.player.god = true
	_game.player.hp = _game.player.max_hp
	_pilot.steer(_game, dt, _t)
	var em = _game.enemies
	var d = _game.director
	if _fight_t0 < 0.0 and em.boss_index >= 0:
		_fight_t0 = _t
		_next = 0.0
		_arrival = {"alive": em.alive_count(), "load": em.cap_load(), "by": _by_creature(em), "window": d.boss_window.active, "cap": d.current_cap()}
		print("bossprobe: the boss came at run %.1f: %d alive (load %.0f), window %s, cap %d, by %s" % [_run.elapsed, _arrival["alive"], _arrival["load"], str(_arrival["window"]), _arrival["cap"], str(_arrival["by"])])
	if _fight_t0 < 0.0:
		return
	if em.boss_index >= 0:
		em.hp[em.boss_index] = em.max_hp[em.boss_index]
	var ft := _t - _fight_t0
	if ft >= _next:
		_next += 5.0
		var bw = d.boss_window
		var row := {"t": ft, "alive": em.alive_count(), "load": em.cap_load(), "cap": d.current_cap(), "ct": bw.cycle_time() if bw.active else -1.0,
			"came": bw.came_total, "by": _by_creature(em)}
		_rows.append(row)
		_alive_series.append(int(row["alive"]))
		print("bossprobe: fight %5.1f s | alive %3d load %6.1f cap %4d | cycle %5.1f came %3d | %s" % [ft, row["alive"], row["load"], row["cap"], row["ct"], row["came"], str(row["by"])])
	if ft >= _secs:
		_done = true
		_report()
		quit(0)


func _setup() -> void:
	_set = true
	var reg := root.get_node("Registry")
	var b: Dictionary = PROBE.BUILDS.get(_hero, PROBE.BUILDS["calavera"]).get(_build, {})
	_run.debug_clear_items()
	for w: Array in b.get("weapons", []):
		var id: String = w[0]
		var lv: int = int(w[1])
		var def = reg.weapon(id)
		if def == null:
			continue
		_run.debug_set_item("evolution" if def.is_evolution else "weapon", id, 99 if lv <= 0 else lv)
		var muts: Array = (w[2] as Array).duplicate()
		if def.is_evolution:
			var inst = _run.weapon_instance(id)
			if inst:
				for m in reg.mutations_of(inst.family_id()):
					if not m.is_hero():
						muts.append(m.id)
		for m: String in muts:
			_run.debug_set_item("mutation", m, 1)
	for p: Array in b.get("passives", []):
		_run.debug_set_item("passive", p[0], int(p[1]))
	_run.level = _level
	_run.kills = 1000
	_run.path_slot = 99
	var d = _game.director
	var tl = d.timeline
	if _window == 0:
		var e = tl.stage_list[_stage] if _stage < tl.stage_list.size() else null
		if e is Dictionary and e.get("boss_fight") is Dictionary:
			e["boss_fight"]["enabled"] = false
	var t0: float = maxf(tl.stage_end(_stage) - _before, tl.stage_start(_stage))
	_run.elapsed = t0
	d.skip_events_before(t0)
	d.forget_sources()
	d._apply_mults()
	_game.enemies.kill_all(false)
	_run.rebuild_sheets()
	_game.player.refresh_stats()
	print("bossprobe: stage %d (%s) hero %s build %s level %d window %d, from run %.0f, the boss at %.0f; window: %s" % [_stage + 1,
		tl.stage_name(_stage), _hero, _build, _level, _window, t0, tl.stage_end(_stage),
		"none" if not tl.has_boss_fight(_stage) else "%d s cycle, max %d bodies, %d rows" % [int(tl.boss_fight_length(_stage)), tl.boss_fight_max_count(_stage), tl.boss_fight_rows(_stage).size()]])


func _by_creature(em) -> Dictionary:
	var out := {}
	for i in range(em.pool_max):
		if em.alive[i] == 1 and em.state[i] != 3:
			var id: String = str(em.types[em.type_idx[i]]["def"].id)
			out[id] = int(out.get(id, 0)) + 1
	return out


func _report() -> void:
	var em = _game.enemies if _game else null
	if em == null:
		return
	var n := _alive_series.size()
	var lo := 9999
	var hi := 0
	var sum := 0
	for v: int in _alive_series:
		lo = mini(lo, v)
		hi = maxi(hi, v)
		sum += v
	var bw = _game.director.boss_window
	print("bossprobe: REPORT stage %d window %d: at arrival %s alive; during the fight (%d samples) min %d mean %.1f max %d; window came %d over %d cycle(s): %s" % [
		_stage + 1, _window, str(_arrival.get("alive", "?")), n, lo if n > 0 else 0, float(sum) / maxf(float(n), 1.0), hi, bw.came_total, bw.cycles, str(bw.came_by)])
	# the later half of the fight (the stage's leftovers gone): the window's own crowd
	var half: Array = _alive_series.slice(int(n / 2.0))
	var hs := 0
	var hh := 0
	for v: int in half:
		hs += v
		hh = maxi(hh, v)
	print("bossprobe: REPORT stage %d window %d: second half mean %.1f max %d; by creature at the end %s" % [_stage + 1, _window, float(hs) / maxf(float(half.size()), 1.0), hh, str(_by_creature(em))])


func _screens() -> void:
	if _game.cards and _game.cards.visible and not _game.cards._offer.is_empty() and not _game.cards._picking:
		_game.cards._pick(_game.cards._offer[0])
	if _game.get("chest_screen") and _game.chest_screen and _game.chest_screen.visible and not _game.chest_screen._spinning:
		_game.chest_screen._finish(true)
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
