## Pass 126 (lane BOSS): Black Sunday's fight watched, headless, bounded. The Dust Bowl's stage run, a fixed build, dropped in
## `before` seconds before the stage's end; the hero never hurt (god); the boss comes by the timeline as he does in play and
## is held alive `secs` seconds, then killed. It logs every attack he starts, every whirl (creatures taken, killed by the fall,
## the hero's throws and how far), that hits land x1 while he spins and x1.5 while he is dazed, the bullet heaven's numbers,
## and that he dies and pays (his chest).
##   bash tools/godot.sh --headless --fixed-fps 60 --path game --log-file <abs> --script res://tools/_p126_BOSS_fight.gd -- \
##       stage=2 build=b2 level=30 hero=calavera secs=150 before=20 seed=11 pilot=stand
## pilot: stand (the hero stands: every attack reaches him), kite (tools/sim_pilot.gd walks him). Save sandboxed, no analytics.
extends SceneTree

const PILOT := preload("res://tools/sim_pilot.gd")
const PROBE := preload("res://tools/difficulty_probe.gd")

var _stage := 2
var _build := "b2"
var _level := 30
var _hero := "calavera"
var _secs := 150.0
var _before := 20.0
var _seed := 11
var _pilot_mode := "stand"
var _game: Node
var _run: Node
var _pilot: PILOT
var _t := 0.0
var _set := false
var _fight_t0 := -1.0
var _done := false
var _dead_t := -1.0
var _atk_seen := -1
var _counts: Dictionary = {}
var _phase_seen := -1
var _kills_at := 0
var _whirl_rows: Array = []
var _spin_check := false
var _dazed_check := false
var _toss_seen := 0
var _toss_from := Vector3.ZERO
var _toss_watch := false
var _toss_air := 0.0
var _throws: Array = []
var _cast := PackedStringArray()
var _gold0 := 0
var _max_alive := 0


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
			"pilot": _pilot_mode = kv[1]
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	_pilot = PILOT.new(_seed)
	var save := root.get_node_or_null("Save")
	if save == null or root.get_node_or_null("Run") == null:
		printerr("sunday: the autoloads did not load; nothing run")
		quit(2)
		return
	save.begin_sandbox()
	save.data["runs_started"] = 1
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
		print("sunday: watchdog after %.0f s" % _t)
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
	if _pilot_mode == "kite":
		_pilot.steer(_game, dt, _t)
	var em = _game.enemies
	if _fight_t0 < 0.0 and em.boss_index >= 0:
		_fight_t0 = _t
		_gold0 = int(_run.run_gold)
		print("sunday: he came at run %.1f (stage clock %.1f): hp %.0f, damage %.1f, %d alive, stage mult %.2f" % [_run.elapsed, _run.stage_clock() if _run.has_method("stage_clock") else -1.0, em.hp[em.boss_index], em.dmg[em.boss_index], em.alive_count(), _run.stage_mult() if _run.has_method("stage_mult") else -1.0])
	if _fight_t0 < 0.0:
		return
	var b: int = em.boss_index
	if b < 0:
		if _dead_t < 0.0:
			_dead_t = _t
			print("sunday: he is dead at fight %.1f: bosses_killed %d, chests on the ground %s" % [_t - _fight_t0, _run.bosses_killed, str(_chests())])
		if _t - _dead_t > 3.0:
			_done = true
			print("sunday: 3 s after his death: gold +%d, chests %s" % [int(_run.run_gold) - _gold0, str(_chests())])
			_report()
			quit(0)
		return
	var ft := _t - _fight_t0
	if ft < _secs:
		em.hp[b] = maxf(em.hp[b], em.max_hp[b] * 0.45)
	_watch_attacks(em, b, ft)
	_watch_whirl(em, b, ft, dt)
	_max_alive = maxi(_max_alive, em.alive_count())
	if ft >= _secs:
		# let him fall to the weapons, helped along
		em.damage(b, em.max_hp[b] * 0.02, "", Vector3.ZERO, 0.0)


func _watch_attacks(em, b: int, ft: float) -> void:
	if em.atk_i[b] == _atk_seen:
		return
	_atk_seen = em.atk_i[b]
	var def = em.types[em.type_idx[b]]["def"]
	var list: Array = em.custom_resolved(def, def.boss["attacks"])
	if list.is_empty() or em.state[b] != 4:
		return
	var nm := str((list[(em.atk_i[b] - 1) % list.size()] as Dictionary).get("name", ""))
	_counts[nm] = int(_counts.get(nm, 0)) + 1
	_cast.append("%.0f %s" % [ft, nm])
	print("sunday: fight %6.1f s: %s (cycle), %d alive" % [ft, nm, em.alive_count()])


func _watch_whirl(em, b: int, ft: float, dt: float) -> void:
	var w = em.whirls
	if em.patterns != null and em.patterns.phase_of(b) == 0 and not _counts.has("blizzard_at_%d" % em.patterns.started):
		_counts["blizzard_at_%d" % em.patterns.started] = ft
		print("sunday: fight %6.1f s: the bullet heaven's tell (%d so far), %d alive" % [ft, em.patterns.started, em.alive_count()])
	if w == null:
		return
	var ph: int = w.phase_of(b)
	if ph != _phase_seen:
		print("sunday: fight %6.1f s: whirl phase %d -> %d: started %d, lifted %d, tosses %d, saved %d, kills %d, %d alive, at %s, hero at %s" % [ft, _phase_seen, ph, w.started, w.lifted, w.tosses, w.saved, _run.kills, em.alive_count(), str(em.pos[b]), str(_game.player.global_position)])
		if ph == 1:
			_kills_at = _run.kills
			_spin_check = false
		if ph == 2:
			_dazed_check = false
			_whirl_rows.append({"at": ft, "kills": _run.kills - _kills_at, "lifted": w.lifted, "tosses": w.tosses})
		_phase_seen = ph
	if ph == 1 and not _spin_check and em.state[b] == 4:
		_spin_check = true
		var h0: float = em.hp[b]
		em.damage(b, 100.0, "", Vector3.ZERO, 0.0)
		print("sunday: while he spins a 100 hit takes %.1f" % (h0 - em.hp[b]))
	if ph == 2 and not _dazed_check:
		_dazed_check = true
		var h1: float = em.hp[b]
		em.damage(b, 100.0, "", Vector3.ZERO, 0.0)
		print("sunday: while he is dazed a 100 hit takes %.1f" % (h1 - em.hp[b]))
	if w.tosses != _toss_seen:
		_toss_seen = w.tosses
		_toss_from = _game.player.global_position
		_toss_watch = true
		_toss_air = 0.0
	elif _toss_watch:
		_toss_air += dt
		if _toss_air > 0.1 and _game.player.is_on_floor():
			_toss_watch = false
			var d := Vector2(_game.player.global_position.x - _toss_from.x, _game.player.global_position.z - _toss_from.z).length()
			_throws.append(snappedf(d, 0.01))
			print("sunday: the throw carried him %.2f m in %.2f s" % [d, _toss_air])


func _chests() -> Dictionary:
	var pk = _game.pickups
	var out := {"chests": 0, "boss_chest": ""}
	for c in pk.chests:
		if is_instance_valid(c):
			out["chests"] = int(out["chests"]) + 1
			if str(c.boss_id) != "":
				out["boss_chest"] = str(c.boss_id)
	return out


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
		for m: String in muts:
			_run.debug_set_item("mutation", m, 1)
	for p: Array in b.get("passives", []):
		_run.debug_set_item("passive", p[0], int(p[1]))
	_run.level = _level
	_run.kills = 1000
	_run.path_slot = 99
	var d = _game.director
	var tl = d.timeline
	var t0: float = maxf(tl.stage_end(_stage) - _before, tl.stage_start(_stage))
	_run.elapsed = t0
	d.skip_events_before(t0)
	d.forget_sources()
	d._apply_mults()
	_game.enemies.kill_all(false)
	_run.rebuild_sheets()
	_game.player.refresh_stats()
	print("sunday: stage %d (%s) hero %s build %s level %d pilot %s, from run %.0f, the boss at %.0f; window: %s" % [_stage + 1, tl.stage_name(_stage), _hero, _build, _level, _pilot_mode, t0, tl.stage_end(_stage), "none" if not tl.has_boss_fight(_stage) else "%d s cycle, max %d bodies" % [int(tl.boss_fight_length(_stage)), tl.boss_fight_max_count(_stage)]])


func _report() -> void:
	var em = _game.enemies if _game else null
	if em == null:
		return
	print("sunday: REPORT attacks %s" % str(_counts))
	print("sunday: REPORT whirls %s; throws (m) %s" % [str(_whirl_rows), str(_throws)])
	if em.whirls != null:
		print("sunday: REPORT whirl started %d ended %d cut %d lifted %d tosses %d saved %d" % [em.whirls.started, em.whirls.ended, em.whirls.cut, em.whirls.lifted, em.whirls.tosses, em.whirls.saved])
	if em.patterns != null:
		print("sunday: REPORT patterns started %d ended %d fired %d hits %d peak %d walls %d last %s" % [em.patterns.started, em.patterns.ended, em.patterns.fired, em.patterns.hits, em.patterns.peak, em.patterns.walls, str(em.patterns.last)])
	print("sunday: REPORT most alive %d; bosses_killed %d" % [_max_alive, _run.bosses_killed])


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
