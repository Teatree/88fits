## Pass 79, lane WORLD: does the dynamite's lead (Lobber params.lead) catch more of the crowd? One headless process plays
## the same window of Red Canyon for every seed twice, the lead off then on (the weapon's params.lead set on its def before
## each run), and counts, for every Dynamite Stick that blows, the creatures inside its blast as it goes off
## (EnemyManager.blast_count the frame before, the bomb's own radius), its kills and its damage.
##   bash tools/godot.sh --headless --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/_p79_WORLD_lead_probe.gd \
##       -- seeds=1,2,3 t0=150 secs=75 pilot=kite share=1.0 [shares=0,1] [build=dyn|mix] [mode=predict|chase|walk] [level=5]
## pilot: kite (tools/sim_pilot.gd, the run sim's circle-strafer) or stand (the hero stands where he is). build dyn: the
## Dynamite Stick at level 5 alone; mix: with the Revolver at 3 (some of the crowd thinned by gunfire). The hero is in god
## mode (a window that plays to its end). The Save is sandboxed (Save.begin_sandbox, never ended), no analytics record.
## Prints one RESULT line per run and a SUMMARY per share. Every wait is bounded: a run ends after `secs` of game clock or
## 4 x secs + 60 s of real time, and a watchdog quits the whole process after an hour.
## The paired count (CF lines): the runs differ more from one another than the lead changes them, so every throw is also
## scored where each way of aiming would have put it. As a stick is thrown (the step after) the probe works out the
## candidate spots from the same crowd (none: the unled spot; walk / chase at shares and hero_ahead values, _lb.lead_spot)
## and, as it blows, counts the creatures inside the blast's radius round each of them at that moment. Same crowd, same
## moment: the difference between two candidates is the lead's own.
extends SceneTree

const PILOT := preload("res://tools/sim_pilot.gd")

var _seeds: Array = [1, 2, 3]
var _shares: Array = [0.0, 1.0]
var _t0 := 150.0
var _secs := 75.0
var _pilot_mode := "kite"
var _build := "dyn"
var _mode := "predict"
var _level := 5
var _runs: Array = []
var _k := -1
var _game: Node
var _run: Node
var _reg: Node
var _pilot: PILOT
var _t := 0.0
var _set := false
var _set_t := 0.0
var _el0 := 0.0
var _kills := 0
var _dmg0 := 0.0
var _blasts := 0
var _caught := 0
var _caught_hist: Dictionary = {}
var _led := 0
var _lead_m := 0.0
var _results: Array = []
## the paired count: projectile slot -> {"target", "cands": {name: spot}}; per candidate the sums over every blast
var _cf_track: Dictionary = {}
var _cf_sum: Dictionary = {}
var _cf_sq: Dictionary = {}
var _cf_n := 0
## Lobber's script, loaded once the autoloads exist (a SceneTree script naming the class would not compile)
var _lb
const CANDS := {
	"none": {},
	"walk_1": {"share": 1.0, "mode": "walk"},
	"walk_05": {"share": 0.5, "mode": "walk"},
	"chase_1": {"share": 1.0, "mode": "chase"},
	"chase_075": {"share": 0.75, "mode": "chase"},
	"chase_05": {"share": 0.5, "mode": "chase"},
	"chase_1_now": {"share": 1.0, "mode": "chase", "hero_ahead": 0.0},
	"chase_1_far": {"share": 1.0, "mode": "chase", "hero_ahead": 1.0},
	"predict": {},
	"predict_g25": {},
	"predict_back": {},
	"actual": {},
}


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"seeds": _seeds = Array(kv[1].split(",", false)).map(func(s): return int(s))
			"shares": _shares = Array(kv[1].split(",", false)).map(func(s): return float(s))
			"share": _shares = [0.0, float(kv[1])]
			"t0": _t0 = float(kv[1])
			"secs": _secs = float(kv[1])
			"pilot": _pilot_mode = kv[1]
			"build": _build = kv[1]
			"mode": _mode = kv[1]
			"level": _level = int(kv[1])
	for s in _seeds:
		for sh in _shares:
			_runs.append({"seed": int(s), "share": float(sh)})
	create_timer(3600.0, true, false, true).timeout.connect(func() -> void:
		print("lead_probe: watchdog quit")
		quit(3))
	process_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	var save := root.get_node_or_null("Save")
	if save == null or root.get_node_or_null("Run") == null:
		printerr("lead_probe: the autoloads did not load; nothing run")
		quit(2)
		return
	save.begin_sandbox()
	save.data["runs_started"] = 1
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_lb = load("res://core/behaviors/Lobber.gd")
	process_frame.connect(_tick)
	physics_frame.connect(_physics)
	_next()


func _next() -> void:
	_k += 1
	_game = null
	_set = false
	_t = 0.0
	if _k >= _runs.size():
		_summary()
		quit(0)
		return
	var r: Dictionary = _runs[_k]
	_pilot = PILOT.new(int(r["seed"]))
	# the lead on the weapon's def (every instance folds its params from it)
	var def = _reg.weapon("lob_grenade")
	def.params["lead"] = {"share": float(r["share"]), "mode": _mode}
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "lob_grenade", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": int(r["seed"]), "analytics": false, "sim_clock": true}))
	f.close()
	change_scene_to_file("res://game/Game.tscn")


func _tick() -> void:
	if _k >= _runs.size():
		return
	var dt: float = root.get_process_delta_time()
	_t += dt
	if _game == null:
		var g = current_scene
		if g == null or not g.has_method("open_pause") or g.get("player") == null or g.player == null:
			return
		_game = g
		_game.player.god = true
		if _game.get("damage_numbers") != null and _game.damage_numbers:
			_game.damage_numbers.suppressed = true
	_screens()
	if not _set and _t > 0.6 and not _run.weapons.is_empty():
		_setup()
	if not _set:
		return
	if _pilot_mode == "kite":
		_pilot.steer(_game, dt, _t)
	var ran: float = _run.elapsed - _el0
	if ran >= _secs or _t - _set_t > _secs * 4.0 + 60.0:
		_report(ran)
		_next()


## Every physics step, before the systems run: a lying Dynamite Stick whose fuse runs out this step is counted with the
## creatures inside its blast now.
func _physics() -> void:
	if not _set or _game == null or not is_instance_valid(_game):
		return
	var pm = _game.get("projectiles")
	var em = _game.get("enemies")
	if pm == null or em == null:
		return
	var step: float = 1.0 / float(Engine.physics_ticks_per_second)
	_cf_throws(pm, em)
	for i in range(pm.MAX):
		if pm.alive[i] == 0 or pm.hostile[i] == 1 or pm.arc[i] == 0:
			continue
		var ex = pm.extra[i]
		if not ex is Dictionary or not (ex as Dictionary).has("lie_t"):
			continue
		var w = pm.weapon[i]
		if w == null or w.def.id != "lob_grenade" or (ex as Dictionary).has("is_bomblet"):
			continue
		if float(ex["lie_t"]) <= step + 0.0001:
			var n: int = em.blast_count(pm.pos[i], pm.area[i])
			_blasts += 1
			_caught += n
			_caught_hist[mini(n, 10)] = int(_caught_hist.get(mini(n, 10), 0)) + 1
			_cf_blast(i, pm, em)


func _setup() -> void:
	_set = true
	_set_t = _t
	_run.debug_clear_items()
	_run.debug_set_item("weapon", "lob_grenade", _level)
	if _build == "mix":
		_run.debug_set_item("weapon", "revolver", 3)
	_run.level = 12
	_run.stage = 0
	_run.elapsed = _t0
	_run.kills = 1000
	_run.path_slot = 99
	var d = _game.director
	d.skip_events_before(_t0)
	d.forget_sources()
	d._apply_mults()
	_game.enemies.kill_all(false)
	_run.rebuild_sheets()
	_game.player.refresh_stats()
	_el0 = _run.elapsed
	_kills = 0
	_dmg0 = float(_run.damage_by_weapon.get("lob_grenade", 0.0))
	_blasts = 0
	_caught = 0
	_caught_hist = {}
	if not _game.enemies.enemy_died.is_connected(_on_died):
		_game.enemies.enemy_died.connect(_on_died)


func _on_died(_def, _pos, _elite, weapon_id: String) -> void:
	if weapon_id == "lob_grenade":
		_kills += 1


## The Lobber that throws the dynamite (its lead counters).
func _lobber() -> Node:
	for n in _game.find_children("*", "", true, false):
		if n.get_script() and str(n.get_script().resource_path).ends_with("Lobber.gd") and n.get("inst") and n.inst.def.id == "lob_grenade":
			return n
	return null


func _screens() -> void:
	if _game.cards and _game.cards.visible and not _game.cards._offer.is_empty() and not _game.cards._picking:
		_game.cards.visible = false
		_game.modal_reset()
		_game.set_paused(false)
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


func _report(ran: float) -> void:
	var r: Dictionary = _runs[_k]
	var lb = _lobber()
	var led: int = int(lb.leads) if lb else -1
	var dealt: float = float(_run.damage_by_weapon.get("lob_grenade", 0.0)) - _dmg0
	var mins := maxf(ran / 60.0, 0.01)
	var row := {"seed": r["seed"], "share": r["share"], "ran": ran, "blasts": _blasts, "caught": _caught, "kills": _kills, "dealt": dealt, "led": led, "hist": _caught_hist.duplicate()}
	_results.append(row)
	print("lead_probe: RESULT seed=%d share=%.2f mode=%s pilot=%s build=%s t0=%.0f ran=%.0f | blasts %d caught %d (%.2f a blast) | kills %d (%.1f/min, %.2f a blast) | dealt/s %.0f | led throws %d | hist %s | alive %d" % [
		int(r["seed"]), float(r["share"]), _mode, _pilot_mode, _build, _t0, ran, _blasts, _caught, float(_caught) / maxf(_blasts, 1), _kills, _kills / mins,
		float(_kills) / maxf(_blasts, 1), dealt / maxf(ran, 1.0), led, str(_caught_hist), int(_game.enemies.count_alive)])


func _summary() -> void:
	_cf_report()
	for sh in _shares:
		var b := 0
		var c := 0
		var k := 0
		var d := 0.0
		var ran := 0.0
		for row: Dictionary in _results:
			if absf(float(row["share"]) - float(sh)) > 0.001:
				continue
			b += int(row["blasts"])
			c += int(row["caught"])
			k += int(row["kills"])
			d += float(row["dealt"])
			ran += float(row["ran"])
		print("lead_probe: SUMMARY share=%.2f mode=%s pilot=%s build=%s seeds=%s | blasts %d | caught a blast %.2f | kills a blast %.2f | kills/min %.1f | dealt/s %.0f" % [
			float(sh), _mode, _pilot_mode, _build, str(_seeds), b, float(c) / maxf(b, 1), float(k) / maxf(b, 1), float(k) / maxf(ran / 60.0, 0.01), d / maxf(ran, 1.0)])


## A stick just thrown (a slot with a target the probe has not seen): its candidate spots from the crowd as it is now.
func _cf_throws(pm, em) -> void:
	for i in range(pm.MAX):
		if pm.alive[i] == 0 or pm.hostile[i] == 1 or pm.arc[i] == 0:
			_cf_track.erase(i)
			continue
		var ex = pm.extra[i]
		if not ex is Dictionary or not (ex as Dictionary).has("target") or (ex as Dictionary).has("is_bomblet"):
			continue
		var w = pm.weapon[i]
		if w == null or w.def.id != "lob_grenade":
			continue
		var tg: Vector3 = ex["target"]
		if _cf_track.has(i) and (_cf_track[i]["target"] as Vector3).is_equal_approx(tg):
			continue
		var unled: Vector3 = ex.get("lead_from", tg)
		var hero: Vector3 = _game.player.global_position
		var hv: Vector3 = _game.player.velocity
		hv.y = 0.0
		var v: Vector3 = em.crowd_velocity(unled, _lb.LEAD_RADIUS)
		var pace: float = em.crowd_speed(unled, _lb.LEAD_RADIUS)
		var from := hero + Vector3(0, 1.2, 0)
		var cands := {}
		for name: String in CANDS:
			var cfg: Dictionary = CANDS[name]
			if name.begins_with("predict") or name == "actual":
				continue
			if cfg.is_empty():
				cands[name] = unled
			else:
				cands[name] = _lb.lead_spot(unled, from, v, w.stat("speed", 9.0), 1.0, _lb.lead_config({"lead": cfg}), hero, w.stat("range", 10.0), 64.5, hv, pace)
		# predict: the spot along the way to the full chase lead where the most creatures are foreseen at the blast
		var area: float = w.stat("area", 2.8)
		var t := clampf(maxf(Vector2(unled.x - from.x, unled.z - from.z).length(), 0.5) / maxf(w.stat("speed", 9.0), 1.0), 0.35, 2.5) + 1.0
		var goal := hero + hv * (t * 0.5)
		var full: Vector3 = cands["chase_1"]
		var spots: Array = []
		for f in [0.0, 0.25, 0.5, 0.75, 1.0]:
			spots.append(unled.lerp(full, f))
		for gname: String in ["predict", "predict_g25", "predict_back"]:
			var gap := 2.5 if gname == "predict_g25" else 1.5
			var counts: PackedInt32Array = em.predicted_counts(spots, area, t, goal, gap, unled, area + unled.distance_to(full) + 6.0)
			var best := 0
			for k in range(spots.size()):
				if counts[k] > counts[best] or (counts[k] == counts[best] and gname != "predict_back"):
					best = k
			cands[gname] = spots[best]
		cands["actual"] = tg
		_cf_track[i] = {"target": tg, "cands": cands}


## A stick blowing: the creatures inside its radius round every candidate spot, now.
func _cf_blast(i: int, pm, em) -> void:
	if not _cf_track.has(i):
		return
	var cands: Dictionary = _cf_track[i]["cands"]
	_cf_n += 1
	var base := float(em.blast_count(cands["none"], pm.area[i]))
	for name: String in cands:
		var n := float(em.blast_count(cands[name], pm.area[i]))
		_cf_sum[name] = float(_cf_sum.get(name, 0.0)) + n
		var d := n - base
		_cf_sq[name] = float(_cf_sq.get(name, 0.0)) + d * d
		_cf_sum[name + "/d"] = float(_cf_sum.get(name + "/d", 0.0)) + d
	_cf_track.erase(i)


func _cf_report() -> void:
	if _cf_n == 0:
		return
	var n := float(_cf_n)
	var parts: Array = []
	for name: String in CANDS:
		var mean := float(_cf_sum.get(name, 0.0)) / n
		var md := float(_cf_sum.get(name + "/d", 0.0)) / n
		var var_d := maxf(float(_cf_sq.get(name, 0.0)) / n - md * md, 0.0)
		var se := sqrt(var_d / n)
		parts.append("%s %.2f (%+.2f +- %.2f)" % [name, mean, md, se])
	print("lead_probe: CF pilot=%s build=%s level=%d blasts %d | caught a blast at each spot (vs none, +- standard error): %s" % [_pilot_mode, _build, _level, _cf_n, " | ".join(parts)])
