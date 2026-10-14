## The difficulty probe (pass 62): a fixed build with a Mirror at rank 0, 3 or 6 dropped into the live
## director at a clock of the timeline, a kiting autopilot, and what the window cost him: HP lost a minute in max-HP
## units (gross and net of his healing), kills, the crowd against the cap. Never a death: below DOWN_AT of his health
## (or down) he is put back to full and the shortfall is counted, so the window plays to its end. The Save is sandboxed
## before anything changes (Save.begin_sandbox, never ended: the PC's save.json is never written), and the run writes no
## analytics record.
##   "$GODOT" --headless --fixed-fps 60 --path game --script res://tools/difficulty_probe.gd -- t0=300 secs=130 stage=0 \
##       level=22 build=b1 mirror=0 hero=calavera seed=11
## `mirror` may be fractional (pass 64): 1.5 = a quarter of the board, the talents in FORMS order taking 2 and 1 ranks
## by turns (grit 2, drive 1, stride 2, fortune 1, choice 2, nerve 1, study 2, spite 1 = 12 of 48 ranks); a whole
## number gives every talent that many. `grit=` and `spite=` pick those talents' forms (spite 1 = Thirst, the default;
## spite=0 = Thorns, a Mirror without lifesteal: Thirst's first rank already reaches the 4 % lifesteal cap). Ranks are
## written as pass 63's picks (every rank in the talent's FORMS form). The probe is not deterministic (two runs of one
## seed can differ by 0.4 maxHP a minute): pool several seeds and both heroes before reading a cell.
## Autoloads are reached through the tree (SceneTree scripts compile before they exist).
extends SceneTree

const DOWN_AT := 0.4
## Builds (lane PC's assumptions, see its report): the hero's five weapons with levels and path mutations (or the
## evolution), his lines and passive items, at about 7:10 (b1), 14:20 (b2) and 21:30 (b3).
const BUILDS := {
	"calavera": {
		"b1": {"weapons": [["guitarra", 3, ["far_reach"]], ["molotov", 2, ["accelerant"]], ["boomstick", 2, ["both_barrels"]], ["tommy_gun", 2, ["drum_mag"]], ["zap_beam", 1, ["fork"]]],
			"passives": [["brawn", 2], ["mend", 2], ["vigour", 1], ["reach", 1], ["cold_snap", 2], ["desperado", 2], ["powder_keg", 2], ["skedaddle", 1]]},
		"b2": {"weapons": [["requiem", 0, []], ["molotov", 4, ["accelerant", "methanol"]], ["boomstick", 4, ["both_barrels", "birdshot_lane"]], ["tommy_gun", 3, ["drum_mag", "mini_crits"]], ["zap_beam", 3, ["fork", "echo_zap"]]],
			"passives": [["brawn", 3], ["mend", 3], ["vigour", 2], ["haste", 2], ["multishot", 1], ["reach", 2], ["cold_snap", 2], ["desperado", 2], ["powder_keg", 2], ["skedaddle", 1]]},
		"b3": {"weapons": [["requiem", 0, []], ["moonshine", 0, []], ["blunderbuss", 0, []], ["chicago_typewriter", 0, []], ["zap_beam", 5, ["fork", "echo_zap"]]],
			"passives": [["juggernaut", 1], ["mend", 3], ["vigour", 2], ["haste", 4], ["multishot", 3], ["reach", 3], ["cold_snap", 3], ["desperado", 3], ["powder_keg", 3], ["skedaddle", 2]]},
	},
	"drifter": {
		"b1": {"weapons": [["revolver", 3, ["hip_shot"]], ["molotov", 2, ["accelerant"]], ["orbit_saws", 2, ["saw_swarm"]], ["sabre", 2, ["flurry"]], ["peashooter", 1, []]],
			"passives": [["brawn", 2], ["mend", 1], ["vigour", 2], ["deadeye", 1], ["reach", 1], ["powder_keg", 2], ["quickdraw", 1], ["cold_snap", 1]]},
		"b2": {"weapons": [["golden_revolver", 0, []], ["molotov", 4, ["accelerant", "methanol"]], ["orbit_saws", 4, ["saw_swarm", "rust"]], ["sabre", 3, ["flurry", "critical_thinking"]], ["peashooter", 3, ["big_peas", "bouncing_peas"]]],
			"passives": [["brawn", 3], ["mend", 2], ["vigour", 3], ["deadeye", 2], ["multishot", 1], ["reach", 2], ["powder_keg", 2], ["quickdraw", 2], ["cold_snap", 2]]},
		"b3": {"weapons": [["golden_revolver", 0, []], ["moonshine", 0, []], ["saw_halo", 0, []], ["whirlwind", 0, []], ["peashooter", 5, ["big_peas", "bouncing_peas"]]],
			"passives": [["juggernaut", 1], ["mend", 2], ["vigour", 4], ["deadeye", 4], ["multishot", 3], ["reach", 3], ["powder_keg", 3], ["quickdraw", 3], ["cold_snap", 3]]},
	},
	# pass 67 (lane M): Calavera's budget with Buck's Tommy Gun in place of the Guitarra; pass 69 (lane HERO): Buck is
	# Jeżyk, landing with the Frisbee (Carry its stage-1 pick, the Flying Saucer in b3) and loving the Salt (his Salt Flats)
	# in the Tommy Gun's and the Orbit Saws' old slots
	"buck": {
		"b1": {"weapons": [["frisbee", 3, ["carry"]], ["salt", 2, ["salt_flats"]], ["molotov", 2, ["accelerant"]], ["boomstick", 2, ["both_barrels"]], ["zap_beam", 1, ["fork"]]],
			"passives": [["brawn", 2], ["mend", 2], ["vigour", 1], ["reach", 1], ["cold_snap", 2], ["desperado", 2], ["powder_keg", 2], ["skedaddle", 1]]},
		"b2": {"weapons": [["frisbee", 4, ["carry", "poison_razors"]], ["salt", 4, ["salt_flats", "salt_spill"]], ["molotov", 4, ["accelerant", "methanol"]], ["boomstick", 4, ["both_barrels", "birdshot_lane"]], ["zap_beam", 3, ["fork", "echo_zap"]]],
			"passives": [["brawn", 3], ["mend", 3], ["vigour", 2], ["haste", 2], ["multishot", 1], ["reach", 2], ["cold_snap", 2], ["desperado", 2], ["powder_keg", 2], ["skedaddle", 1]]},
		"b3": {"weapons": [["flying_saucer", 0, []], ["hiwa_kai", 0, ["salt_flats"]], ["moonshine", 0, []], ["blunderbuss", 0, []], ["zap_beam", 5, ["fork", "echo_zap"]]],
			"passives": [["juggernaut", 1], ["mend", 3], ["vigour", 2], ["haste", 4], ["multishot", 3], ["reach", 3], ["cold_snap", 3], ["desperado", 3], ["powder_keg", 3], ["skedaddle", 2]]},
	},
	# pass 67 (the lead): Calavera's budget with Fadeaway's Basketball (On Fire its stage-1 pick, Slam Dunk from b3) in
	# place of the Guitarra, and his favourite line Evade (Ghost Step evolved in b3) in Brawn's slot
	"fadeaway": {
		"b1": {"weapons": [["basketball", 3, ["on_fire"]], ["molotov", 2, ["accelerant"]], ["boomstick", 2, ["both_barrels"]], ["tommy_gun", 2, ["drum_mag"]], ["zap_beam", 1, ["fork"]]],
			"passives": [["evade", 2], ["mend", 2], ["vigour", 1], ["reach", 1], ["cold_snap", 2], ["desperado", 2], ["powder_keg", 2], ["skedaddle", 1]]},
		"b3": {"weapons": [["slam_dunk", 0, []], ["moonshine", 0, []], ["blunderbuss", 0, []], ["chicago_typewriter", 0, []], ["zap_beam", 5, ["fork", "echo_zap"]]],
			"passives": [["ghost_step", 1], ["mend", 3], ["vigour", 2], ["haste", 4], ["multishot", 3], ["reach", 3], ["cold_snap", 3], ["desperado", 3], ["powder_keg", 3], ["skedaddle", 2]]},
	},
}
const START := {"calavera": "guitarra", "drifter": "revolver", "astro": "gravity_gun", "solenne": "sun_scepter", "ironwood": "pike", "buck": "frisbee", "fadeaway": "basketball"}
## The Mirror's forms the probe plays (lane PC: the defensive and damage forms; Omen, Reroll and Field Notes change
## nothing a fixed build shows, so Fortune and Choice ride along and Study is Poultice): talent id -> form index.
const FORMS := {"grit": 0, "drive": 0, "stride": 0, "fortune": 0, "choice": 0, "nerve": 1, "study": 1, "spite": 1}

var _t0 := 300.0
var _secs := 130.0
var _stage := 0
var _level := 22
var _build := "b1"
var _mirror := 0.0
var _hero := "calavera"
var _seed := 11
var _grit := 0
var _spite := 1
var _hpx := 1.0
var _dmgx := 1.0
var _game: Node
var _run: Node
var _t := 0.0
var _set := false
var _set_t := 0.0
var _last_hp := -1.0
var _lost := 0.0
var _healed := 0.0
var _refills := 0
var _downs := 0
var _kills0 := 0
var _dmg0 := 0.0
var _samples: Array = []
var _next_sample := 0.0
var _cards := 0
var _chests := 0
var _strafe := 1.0
var _strafe_t := 0.0
var _rng := RandomNumberGenerator.new()
var _last_log = null
var _by: Dictionary = {}
var _hits := 0
var _big := 0
## pass 72 (lane BOSS): `boss=1` plays on through the boss fight the window runs into and reports it (the HP it came with,
## the DPS scaling the director read, the fight's length); `scale=0` turns the map's boss_hp_scaling off for the run.
var _boss_mode := false
var _scale := -1
var _boss_seen := false
var _boss_done := false
var _boss_t0 := 0.0
var _boss_fight := 0.0
var _boss_info: Dictionary = {}


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"t0": _t0 = float(kv[1])
			"secs": _secs = float(kv[1])
			"stage": _stage = int(kv[1])
			"level": _level = int(kv[1])
			"build": _build = kv[1]
			"mirror": _mirror = float(kv[1])
			"hero": _hero = kv[1]
			"seed": _seed = int(kv[1])
			"grit": _grit = int(kv[1])
			"spite": _spite = int(kv[1])
			"hpx": _hpx = float(kv[1])
			"dmgx": _dmgx = float(kv[1])
			"boss": _boss_mode = kv[1] == "1"
			"scale": _scale = int(kv[1])
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	_rng.seed = _seed
	var save := root.get_node_or_null("Save")
	if save == null or root.get_node_or_null("Run") == null:
		printerr("probe: the autoloads did not load (a script error elsewhere); nothing run")
		quit(2)
		return
	# nothing from here on reaches the disk (the sandbox is never ended: its flush on quit writes nothing)
	save.begin_sandbox()
	save.data["runs_started"] = 1
	var talents := {}
	if _mirror > 0.0:
		var k := 0
		for id: String in FORMS.keys():
			var form: int = FORMS[id]
			if id == "grit":
				form = _grit
			elif id == "spite":
				form = _spite
			var rank := rank_for(_mirror, k)
			k += 1
			if rank <= 0:
				continue
			var picks: Array = []
			for _r in range(rank):
				picks.append(form)
			talents[id] = {"picks": picks, "rank": rank, "form": form}
	save.data["talents"] = talents
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": START.get(_hero, "revolver"), "level": 1, "character": _hero, "map": "red_canyon", "map_seed": _seed, "analytics": false}))
	f.close()
	_run = root.get_node("Run")
	change_scene_to_file("res://game/Game.tscn")
	process_frame.connect(_tick)


## The ranks the k-th talent (FORMS order) takes at a Mirror of `m` ranks a talent on average: whole numbers for every
## talent, a half by turns (the ceiling first).
static func rank_for(m: float, k: int) -> int:
	var lo := floori(m)
	var frac := m - float(lo)
	if frac <= 0.001:
		return clampi(lo, 0, 6)
	return clampi(lo + (1 if k % 2 == 0 else 0), 0, 6)


func _tick() -> void:
	var dt: float = root.get_process_delta_time()
	_t += dt
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
	if not _set:
		return
	_steer(dt)
	_track()
	var ran: float = _run.elapsed - _t0
	if ran >= _next_sample:
		_next_sample += 10.0
		_sample(ran)
	if _boss_mode:
		# pass 72: on through the boss fight (the stage clock stands still in it), until the boss falls or time is up
		_watch_boss()
		if _boss_done or _t - _set_t > _secs * 3.0 + 300.0:
			_report(ran)
			quit(0)
		return
	if ran >= _secs or _t - _set_t > _secs * 3.0 + 60.0:
		_report(ran)
		quit(0)


## The boss the window ran into (pass 72): when it comes, its HP and the scaling the director read; when it falls, the
## fight's length in game seconds.
func _watch_boss() -> void:
	var em = _game.enemies
	if not _boss_seen and em.boss_index >= 0:
		_boss_seen = true
		_boss_t0 = _t
		var i: int = em.boss_index
		var sc = _game.director.get("last_boss_scale")
		_boss_info = {"id": str(em.types[em.type_idx[i]]["def"].id), "hp": float(em.max_hp[i]), "scale": (sc as Dictionary).duplicate() if sc is Dictionary else {}}
	elif _boss_seen and not _boss_done and em.boss_index < 0:
		_boss_done = true
		_boss_fight = _t - _boss_t0


func _setup() -> void:
	_set = true
	_set_t = _t
	var reg := root.get_node("Registry")
	var b: Dictionary = BUILDS.get(_hero, BUILDS["calavera"]).get(_build, {})
	_run.debug_clear_items()
	for w: Array in b.get("weapons", []):
		var id: String = w[0]
		var lv: int = int(w[1])
		var def = reg.weapon(id)
		if def == null:
			print("probe: no weapon %s" % id)
			continue
		_run.debug_set_item("evolution" if def.is_evolution else "weapon", id, 99 if lv <= 0 else lv)
		var muts: Array = (w[2] as Array).duplicate()
		if def.is_evolution:
			# an evolution keeps every path mutation it needed (Run.path_progress: all of the family's, hero ones optional)
			var inst = _run.weapon_instance(id)
			if inst:
				for m in reg.mutations_of(inst.family_id()):
					if not m.is_hero():
						muts.append(m.id)
		for m: String in muts:
			_run.debug_set_item("mutation", m, 1)
	for p: Array in b.get("passives", []):
		if _run.debug_set_item("passive", p[0], int(p[1])) == 0:
			print("probe: passive %s not set" % p[0])
	_run.level = _level
	_run.stage = _stage
	_run.elapsed = _t0
	_run.kills = 1000
	_run.path_slot = 99
	var d = _game.director
	d.skip_events_before(_t0)
	# the repeating coloured-Elite timer of an elite_every dated before t0 runs on from t0
	for ev: Dictionary in d.timeline.events:
		if str(ev.get("type", "")) == "elite_every" and float(ev.get("t", 0.0)) < _t0:
			d._run_event(ev)
	d.timeline.creature_hp_mult *= _hpx
	d.timeline.creature_damage_mult *= _dmgx
	# pass 72: scale=0 plays the bosses at their data HP (the DPS scaling off), scale=1 forces it on
	if _scale >= 0:
		d.timeline.boss_hp_scaling["enabled"] = _scale == 1
	d.forget_sources()
	d._apply_mults()
	_game.enemies.kill_all(false)
	_run.rebuild_sheets()
	_game.player.refresh_stats()
	_game.player.god = false
	_game.player.hp = _game.player.max_hp
	_last_hp = _game.player.hp
	_kills0 = int(_run.kills)
	_dmg0 = _total_dmg()
	var ws: Array = []
	var est := 0.0
	for w in _run.weapons:
		ws.append("%s L%d %s est %.0f" % [w.def.id, w.level, str(w.mutations.map(func(m): return m.id)), w.dps_estimate()])
		est += w.dps_estimate()
	var sh = _run.player_sheet
	print("probe: hero %s build %s mirror %.1f (grit form %d, spite form %d) level %d stage %d t0 %.0f seed %d hpx %.2f dmgx %.2f" % [_hero, _build, _mirror, _grit, _spite, _level, _stage, _t0, _seed, _hpx, _dmgx])
	print("probe: weapons %s" % str(ws))
	print("probe: passives %s" % str(_run.passives))
	print("probe: est_total %.0f | max_hp %.0f dr %.2f regen %.2f lifesteal %.3f move %.2f might %.2f cooldown %.2f area %.2f amount %.1f crit %.2f" % [est,
		sh.get_stat("max_hp", 100.0), sh.get_stat("damage_reduction", 0.0), sh.get_stat("regen", 0.0), sh.get_stat("lifesteal", 0.0),
		sh.get_stat("move_speed", 3.6), sh.get_stat("might", 1.0), sh.get_stat("cooldown", 1.0), sh.get_stat("area", 1.0), sh.get_stat("amount", 0.0), sh.get_stat("crit_chance", 0.0)])


func _total_dmg() -> float:
	var s := 0.0
	for k in _run.damage_by_weapon.keys():
		s += float(_run.damage_by_weapon[k])
	return s


## The modal screens a run raises: a level-up takes its first card, a chest is taken, the gate is tapped, the Stranger
## and the shop are left.
func _screens() -> void:
	if _game.cards and _game.cards.visible and not _game.cards._offer.is_empty() and not _game.cards._picking:
		_cards += 1
		_game.cards._pick(_game.cards._offer[0])
	if _game.get("chest_screen") and _game.chest_screen and _game.chest_screen.visible and not _game.chest_screen._spinning:
		_chests += 1
		_game.chest_screen._finish(true)
	if _game.get("resume_gate") and _game.resume_gate and _game.resume_gate.visible:
		_game.resume_gate.tap()
	if _game.get("stranger_screen") and _game.stranger_screen and _game.stranger_screen.visible:
		_game.stranger_screen._finish(false)
	if _game.get("structure_shop") and _game.structure_shop and _game.structure_shop.visible:
		_game.structure_shop._finish(false)
	# pass 73 (lane STRUCT): a Totem Pole stood in: its first gift taken, so the run goes on
	if _game.get("totem_screen") and _game.totem_screen and _game.totem_screen.visible and not _game.totem_screen._done:
		var tp: Array = _game.totem_screen.planks()
		if not tp.is_empty():
			_game.totem_screen._pick(tp[0])
	if _game.portal_dialog and _game.portal_dialog.visible:
		_game.portal_dialog.visible = false
		_game.portal_dialog.decided.emit(false)


## The autopilot (a circle-strafer): it keeps the nearest creature about KEEP metres off, drifting round the crowd (a
## sideways drift that flips now and then), flees what is closer than FLEE, closes in when nothing is near, and is pulled
## back towards the arena's middle near the wall.
const KEEP := 4.5
const FLEE := 2.6


func _steer(dt: float) -> void:
	var p: Node3D = _game.player
	var inp = p.input
	if inp == null or _game.paused:
		return
	var em = _game.enemies
	var me: Vector3 = p.global_position
	var away := Vector3.ZERO
	var nearest := INF
	var toward := Vector3.ZERO
	for i in range(em.MAX):
		if em.alive[i] != 1:
			continue
		var d: Vector3 = me - em.pos[i]
		d.y = 0.0
		var l2 := d.length_squared()
		if l2 < nearest:
			nearest = l2
			toward = -d
		if l2 > 100.0 or l2 < 0.0001:
			continue
		away += d / l2
	nearest = sqrt(nearest) if nearest < INF else INF
	# what a player watches for (lane PC: the bot had walked into every telegraphed hit): a hammer giant, a charger or an
	# Elite close by pushes six times as hard, and a hostile rocket within 10 m sends him straight away from it
	var danger := Vector3.ZERO
	for i in range(em.MAX):
		if em.alive[i] != 1:
			continue
		var def = em.types[em.type_idx[i]]["def"]
		if not (def.id in ["hammer_giant", "bull_beetle"] or def.archetype == "elite" or def.archetype == "boss"):
			continue
		var dd: Vector3 = me - em.pos[i]
		dd.y = 0.0
		var l2 := dd.length_squared()
		if l2 < 49.0 and l2 > 0.0001:
			danger += dd / l2 * 6.0
	var pm = _game.projectiles
	if pm:
		for pi in pm.rocket_of.keys():
			var k := int(pi)
			if pm.alive[k] != 1:
				continue
			var dr: Vector3 = me - pm.pos[k]
			dr.y = 0.0
			if dr.length_squared() < 100.0 and dr.length_squared() > 0.0001:
				danger += dr.normalized() * 3.0
	away += danger
	_strafe_t -= dt
	if _strafe_t <= 0.0:
		_strafe_t = _rng.randf_range(3.0, 7.0)
		_strafe = -_strafe
	var dir := Vector3.ZERO
	if away.length() > 0.0001:
		var a := away.normalized()
		var side := Vector3(-a.z, 0, a.x) * _strafe
		if danger.length() > 0.4:
			dir = a + side * 0.25
		elif nearest < FLEE:
			dir = a + side * 0.5
		elif nearest < KEEP:
			dir = side + a * 0.35
		else:
			dir = side - a * 0.4
	elif toward.length() > 0.001:
		dir = toward.normalized()
	else:
		dir = Vector3(sin(_t * 0.4), 0, cos(_t * 0.4))
	var mb = _game.map
	if mb:
		var c: Vector3 = mb.flats_center if mb.get("flats_center") != null else Vector3.ZERO
		var to_c: Vector3 = c - me
		to_c.y = 0.0
		var r: float = mb.arena_radius if mb.get("arena_radius") != null else 60.0
		var k := clampf((to_c.length() - r * 0.45) / (r * 0.4), 0.0, 1.5)
		if to_c.length() > 0.01:
			dir += to_c.normalized() * k * 1.4
	dir.y = 0.0
	if dir.length() < 0.001:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	inp.wants_move = true
	inp.origin = Vector2(216, 500)
	inp.touch_pos = inp.origin + Vector2(dir.x, dir.z) * 120.0


## HP bookkeeping: every drop is a loss, every rise a heal; below DOWN_AT (or down) he is put back to full and the
## shortfall counted, so the window plays out.
func _track() -> void:
	var p = _game.player
	var log: Array = p.damage_log
	var k := log.size() - 1
	var fresh: Array = []
	while k >= 0 and not is_same(log[k], _last_log):
		fresh.push_front(log[k])
		k -= 1
	if not log.is_empty():
		_last_log = log[log.size() - 1]
	for e: Dictionary in fresh:
		var dealt := float(e.get("dealt", 0.0))
		if dealt <= 0.0:
			continue
		var key := "%s/%s" % [str(e.get("id", "")) if str(e.get("id", "")) != "" else str(e.get("by", "?")), str(e.get("kind", ""))]
		_by[key] = float(_by.get(key, 0.0)) + dealt
		_hits += 1
		if dealt > p.max_hp * 0.25:
			_big += 1
	if p.dead:
		_downs += 1
		_lost += maxf(_last_hp, 0.0)
		p.revive()
		p.hp = p.max_hp
		p.invuln = 0.0
		_refills += 1
		_last_hp = p.hp
		return
	var hp: float = p.hp
	if hp < _last_hp:
		_lost += _last_hp - hp
	elif hp > _last_hp:
		_healed += hp - _last_hp
	if hp < p.max_hp * DOWN_AT:
		_refills += 1
		p.hp = p.max_hp
		hp = p.hp
	_last_hp = hp


func _sample(ran: float) -> void:
	var em = _game.enemies
	var d = _game.director
	_samples.append({"t": ran, "alive": em.count_alive, "load": em.cap_load(), "cap": d.current_cap(), "kills": int(_run.kills) - _kills0, "lost": _lost, "hp": _game.player.hp})


func _report(ran: float) -> void:
	var p = _game.player
	var mins := maxf(ran / 60.0, 0.01)
	var mh: float = p.max_hp
	var alive := 0.0
	var load := 0.0
	var cap := 0.0
	for s: Dictionary in _samples:
		alive += float(s["alive"])
		load += float(s["load"])
		cap += float(s["cap"])
	var n := maxf(_samples.size(), 1)
	var dealt := _total_dmg() - _dmg0
	print("probe: RESULT hero=%s build=%s mirror=%.1f grit=%d spite=%d hpx=%.2f dmgx=%.2f t0=%.0f secs=%.0f seed=%d | lost/min %.2f maxHP (gross %.0f HP, healed %.0f) net/min %.2f | refills %d downs %d | kills/min %.0f dealt/s %.0f | alive %.0f load %.1f cap %.1f | cards %d chests %d | max_hp %.0f" % [
		_hero, _build, _mirror, _grit, _spite, _hpx, _dmgx, _t0, ran, _seed, _lost / mh / mins, _lost, _healed, (_lost - _healed) / mh / mins, _refills, _downs,
		float(int(_run.kills) - _kills0) / mins, dealt / maxf(ran, 1.0), alive / n, load / n, cap / n, _cards, _chests, mh])
	var keys: Array = _by.keys()
	keys.sort_custom(func(a, b): return float(_by[a]) > float(_by[b]))
	var parts: Array = []
	for key in keys:
		parts.append("%s %.2f" % [key, float(_by[key]) / mh / mins])
	print("probe: BY hits %d big %d | lost/min by source (maxHP): %s" % [_hits, _big, ", ".join(parts)])
	# pass 72 (lane BOSS): the DPS the boss HP scaling reads (the last 45 s of the clock), and the boss fight
	print("probe: DPS45 %.0f | window dealt/s %.0f" % [_run.recent_dps(45.0), dealt / maxf(ran, 1.0)])
	if _boss_mode:
		var sc: Dictionary = _boss_info.get("scale", {})
		print("probe: BOSS %s hp %.0f | scaling dps %.0f ref %.0f x%.2f | fight %s" % [str(_boss_info.get("id", "none")), float(_boss_info.get("hp", 0.0)),
			float(sc.get("dps", 0.0)), float(sc.get("ref", 0.0)), float(sc.get("mult", 1.0)), ("%.1f s" % _boss_fight) if _boss_done else "not over"])
	for s: Dictionary in _samples:
		print("probe:   t+%3d alive %3d load %5.1f cap %3d kills %5d lost %6.0f hp %4.0f" % [int(s["t"]), int(s["alive"]), float(s["load"]), int(s["cap"]), int(s["kills"]), float(s["lost"]), float(s["hp"])])
