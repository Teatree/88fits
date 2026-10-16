## Pass 83 (lane SCALE): the boss HP probe. mode=base prints every hero's power at level 1 with his own weapon on a clean
## save (the Drifter's full DPS and effective HP are HeroPower.BASE_DPS / BASE_EHP); mode=boss sets up a build of
## tools/difficulty_probe.gd (hero, build, level, stage, mirror), stops the director, brings boss `boss` through
## WaveDirector._start_boss (the seconds mode) a few metres in front of the hero, pins it (no walking, no attacks, no
## burrows: every shot can land) and measures the kill from its first lost HP. Prints the HP it came with, the full DPS the
## director read, the seconds asked and the seconds it took. Sandboxed save; no analytics.
##   bash tools/godot.sh --headless --fixed-fps 60 --path game --script res://tools/_p83_SCALE_boss_probe.gd -- mode=boss \
##       hero=calavera build=b1 level=22 stage=0 mirror=0 boss=tumbleweed_king
extends SceneTree

const DP := preload("res://tools/difficulty_probe.gd")

var _mode := "boss"
var _hero := "drifter"
var _build := "b1"
var _level := 22
var _stage := 0
var _mirror := 0.0
var _boss := "tumbleweed_king"
var _pin := true
## weapons=id:level,id:level (in place of the build's weapons; the build's passives stay); dist= the boss's distance
## beyond its own radius (m)
var _weapons := ""
var _dist := 1.5
var _game: Node
var _run: Node
var _t := 0.0
var _phase := 0
var _bi := -1
var _hp0 := 0.0
var _t_first := -1.0
var _t_spawn := 0.0
var _info: Dictionary = {}
var _heroes: Array = []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"mode": _mode = kv[1]
			"hero": _hero = kv[1]
			"build": _build = kv[1]
			"level": _level = int(kv[1])
			"stage": _stage = int(kv[1])
			"mirror": _mirror = float(kv[1])
			"boss": _boss = kv[1]
			"pin": _pin = kv[1] != "0"
			"weapons": _weapons = kv[1]
			"dist": _dist = float(kv[1])
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var save := root.get_node_or_null("Save")
	save.begin_sandbox()
	save.data["runs_started"] = 1
	var talents := {}
	if _mirror > 0.0:
		var k := 0
		for id: String in DP.FORMS.keys():
			var rank := DP.rank_for(_mirror, k)
			k += 1
			if rank <= 0:
				continue
			var picks: Array = []
			for _r in range(rank):
				picks.append(int(DP.FORMS[id]))
			talents[id] = {"picks": picks, "rank": rank, "form": int(DP.FORMS[id])}
	save.data["talents"] = talents
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": DP.START.get(_hero, "revolver"), "level": 1, "character": _hero, "map": "red_canyon", "map_seed": 11, "analytics": false, "sim_clock": true}))
	f.close()
	_run = root.get_node("Run")
	change_scene_to_file("res://game/Game.tscn")
	process_frame.connect(_tick)


func _tick() -> void:
	var dt: float = root.get_process_delta_time()
	_t += dt
	if _game == null:
		var g = current_scene
		if g == null or not g.has_method("open_pause") or g.player == null:
			return
		_game = g
		_game.player.god = true
	if _t > 400.0:
		print("probe83: TIMEOUT")
		quit(1)
		return
	_screens()
	if _phase == 0 and _t > 0.6 and not _run.weapons.is_empty():
		if _mode == "base":
			_base()
			return
		_setup()
	elif _phase == 1:
		_fight(dt)


func _screens() -> void:
	if _game.cards and _game.cards.visible and not _game.cards._offer.is_empty() and not _game.cards._picking:
		_game.cards._pick(_game.cards._offer[0])
	if _game.get("chest_screen") and _game.chest_screen and _game.chest_screen.visible and not _game.chest_screen._spinning:
		_game.chest_screen._finish(true)
	if _game.portal_dialog and _game.portal_dialog.visible:
		_game.portal_dialog.visible = false
		_game.portal_dialog.decided.emit(false)


## Every hero's power at level 1 with his own weapon, no talents.
func _base() -> void:
	_phase = 9
	var reg := root.get_node("Registry")
	for hero: String in ["drifter", "astro", "calavera", "ironwood", "solenne", "fadeaway", "buck", "may"]:
		var c = reg.character(hero) if reg.has_method("character") else null
		_run.debug_clear_items()
		var wid: String = DP.START.get(hero, "")
		if wid == "" and c != null:
			wid = str(c.get("start_weapon"))
		if wid == "" or reg.weapon(wid) == null:
			print("probe83: BASE %s no weapon" % hero)
			continue
		_run.debug_set_item("weapon", wid, 1)
		_run.rebuild_sheets()
		HeroPower.forget()
		var m: Dictionary = HeroPower.measure(_run.weapons, _run.player_sheet)
		var w = _run.weapons[0]
		print("probe83: BASE %s %s est %.1f full_dps %.2f ehp %.1f power %.3f (crowd %.2f elem %.2f crit x%.3f)" % [hero, wid, w.dps_estimate(), float(m["dps"]), float(m["ehp"]), float(m["power"]),
			HeroPower.crowd_of(w), HeroPower.element_dps(w), HeroPower.crit_factor(_run.player_sheet)])
	quit(0)


func _setup() -> void:
	_phase = 1
	var reg := root.get_node("Registry")
	var b: Dictionary = (DP.BUILDS.get(_hero, DP.BUILDS["calavera"]).get(_build, {}) as Dictionary).duplicate(true)
	if _weapons != "":
		var ws: Array = []
		for part in _weapons.split(","):
			var kv := part.split(":")
			ws.append([kv[0], int(kv[1]) if kv.size() > 1 else 1, []])
		b["weapons"] = ws
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
	_run.stage = _stage
	_run.elapsed = 430.0 * float(_stage + 1)
	_run.kills = 1000
	_run.path_slot = 99
	var d = _game.director
	d.stop()
	_game.enemies.kill_all(false)
	_run.rebuild_sheets()
	_game.player.refresh_stats()
	HeroPower.forget()
	var m: Dictionary = HeroPower.measure(_run.weapons, _run.player_sheet)
	var parts: Array = []
	for w in _run.weapons:
		parts.append("%s est %.0f one %.0f" % [w.def.id, w.dps_estimate(), HeroPower.weapon_dps(w)])
	print("probe83: hero %s build %s level %d stage %d mirror %.1f | %s" % [_hero, _build, _level, _stage, _mirror, ", ".join(parts)])
	print("probe83: full_dps %.0f boss_dps %.0f ehp %.0f power %.2f crit x%.2f" % [float(m["dps"]), HeroPower.boss_dps_now(), float(m["ehp"]), float(m["power"]), HeroPower.crit_factor(_run.player_sheet)])
	var bdef = reg.enemy(_boss)
	var at: Vector3 = _game.player.global_position + Vector3(0, 0, -(float(bdef.radius) + _dist))
	d._start_boss(_boss, at)
	_bi = _game.enemies.boss_index
	_info = (d.last_boss_scale as Dictionary).duplicate()
	if _bi < 0:
		print("probe83: no boss came")
		quit(1)
		return
	_hp0 = float(_game.enemies.max_hp[_bi])
	_dmg0 = (_run.damage_by_weapon as Dictionary).duplicate()
	_t_spawn = _t
	_pin_at = at


var _pin_at := Vector3.ZERO
var _dmg0: Dictionary = {}


func _fight(_dt: float) -> void:
	var em = _game.enemies
	_game.player.hp = _game.player.max_hp
	if em.boss_index < 0 or em.alive[_bi] == 0 or em.state[_bi] == em.STATE_DYING:
		var took := _t - (_t_first if _t_first >= 0.0 else _t_spawn)
		var want: float = float(_info.get("seconds", 0.0))
		print("probe83: RESULT boss=%s hero=%s build=%s hp %.0f (data %.0f) full_dps %.0f x %.0f s | killed in %.1f s (%.0f%% of asked) | pin %s" % [_boss, _hero, _build, _hp0,
			float(_info.get("base", 0.0)), float(_info.get("full_dps", 0.0)), want, took, 100.0 * took / maxf(want, 0.001), str(_pin)])
		var per: Array = []
		for k in _run.damage_by_weapon.keys():
			var est := 0.0
			var wi = _run.weapon_instance(str(k))
			if wi:
				est = HeroPower.weapon_dps(wi) * HeroPower.crit_factor(_run.player_sheet)
			per.append("%s %.0f/s (one %.0f)" % [k, (float(_run.damage_by_weapon[k]) - float(_dmg0.get(k, 0.0))) / maxf(took, 0.01), est])
		print("probe83: PER " + ", ".join(per))
		quit(0)
		return
	if _t_first < 0.0 and em.hp[_bi] < _hp0 - 0.01:
		_t_first = _t
	if _pin:
		em.pos[_bi] = Vector3(_pin_at.x, em.pos[_bi].y, _pin_at.z)
		em.vel[_bi] = Vector3.ZERO
		em.kb[_bi] = Vector3.ZERO
		em.atk_t[_bi] = 99.0
		if em.state[_bi] != em.STATE_SPAWN:
			em.state[_bi] = em.STATE_MOVE
		em.hidden[_bi] = 0
	if _t - _t_spawn > 380.0:
		print("probe83: RESULT boss=%s hero=%s build=%s hp %.0f full_dps %.0f | NOT KILLED, hp left %.0f" % [_boss, _hero, _build, _hp0, float(_info.get("full_dps", 0.0)), float(em.hp[_bi])])
		quit(0)
