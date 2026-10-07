## Headless integration run. Starts a run straight into gameplay, simulates a thumb that steers in an S,
## auto-picks cards, fast-forwards to the first boss, walks into the portal, says "Not yet" once (pass 48: the run goes
## on, the portal waits, and asks again once he has stepped out and back in), continues, extracts, then
## visits Results, Title, Shop, Collection, Settings, the Mirror and the developer menu. Exit code 0 only if the whole
## path ran. A revive (pass 48) and the Nuke run on the way, and the run file must record no damage past what the
## creatures had (no zero rows, nothing near the revive's or the boss kill's 100 000).
## Run: godot --headless --path game --script res://tools/smoke_run.gd -- seconds=90 weapon=boomstick
## Autoloads are reached through the tree because SceneTree scripts compile before autoloads exist.
extends SceneTree

var _seconds := 90.0
var _weapon := "boomstick"
var _map := "red_canyon"
var _character := "astro"
var _perf_lines: Array = []
var _perf := false        # perf=1: no fast-forward, no boss kill; play the first minutes as they are and print Perf every 10 s
var _pickups_done := false
var _lobs := [0, 0]
var _t := 0.0
var _last_report := -1
var _game: Node
var _run: Node
var _phase := "run"
var _boss_forced := false
var _boss_n := 1          # boss=2: jump to the second boss with a stage-2 build (the pass 29 crash report)
var _evolve_all := false  # evolve=all: every base weapon added, maxed, mutated twice and evolved in the live game
var _evolved := false
var _portal_decided := 0
var _screens := ["res://ui/ResultsScreen.tscn", "res://ui/TitleScreen.tscn", "res://ui/ShopScreen.tscn", "res://ui/CollectionScreen.tscn", "res://ui/SettingsScreen.tscn", "res://ui/HomesteadScreen.tscn", "res://ui/DevMenu.tscn"]
var _screen_i := -1
var _screen_t := 0.0
var _cards_picked := 0
var _chests := 0
var _errors: Array = []
var _last_clear := -1
var _start_unix := 0.0
var _game_t := -1.0        # the tool's clock when the Game scene appeared
var _spawn_seen := false   # the spawn beam (pass 45): the hero high in the beam after the first second
var _landed_checked := false
var _chest_banished := false  # the chest's BANISH once (pass 47: the reel spins again to a new roll)
var _numbers_seen := 0        # the most numbers in the air at once (pass 47, DamageNumbers keeps its list headless)
var _hero_numbers := false    # whether one of the hero's own numbers was seen
var _barrels_broken := 0      # barrels the hero walked into, and whether Barrel Rush (held since 3 s) ever ran
var _rush_seen := false
var _revived := false         # pass 48: a Nuke and a debug revive mid-run, the revive's blast on a pack at his feet
var _declined := false        # pass 48: the first portal visit says "Not yet"
var _declined_at := -1.0
var _asked_again := false


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seconds="):
			_seconds = float(a.trim_prefix("seconds="))
		elif a.begins_with("weapon="):
			_weapon = a.trim_prefix("weapon=")
		elif a.begins_with("map="):
			_map = a.trim_prefix("map=")
		elif a.begins_with("character="):
			_character = a.trim_prefix("character=")
		elif a == "perf=1":
			_perf = true
		elif a.begins_with("boss="):
			_boss_n = int(a.trim_prefix("boss="))
		elif a == "evolve=all":
			_evolve_all = true
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	_start_unix = Time.get_unix_time_from_system()
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": _weapon, "level": 3, "character": _character, "map": _map, "spawn": true}))
	f.close()
	var save := root.get_node("Save")
	save.data["runs_started"] = 1
	_run = root.get_node("Run")
	var err := change_scene_to_file("res://game/Game.tscn")
	if err != OK:
		printerr("smoke_run: could not load Game.tscn (%d)" % err)
		quit(1)
		return
	process_frame.connect(_tick)


func _tick() -> void:
	var dt: float = root.get_process_delta_time()
	_t += dt
	match _phase:
		"run":
			_tick_run(dt)
		"screens":
			_tick_screens(dt)
	if _t >= _seconds:
		_finish("timeout in phase " + _phase)


func _tick_run(dt: float) -> void:
	if _game == null:
		_game = current_scene
		if _game == null or not _game.has_method("open_pause"):
			_game = null
			return
		if _game.player:
			_game.player.god = true
		_game_t = _t
	if not is_instance_valid(_game) or current_scene != _game:
		_phase = "screens"
		_screen_t = 0.0
		return
	# the spawn beam (pass 45): the launch file says "spawn": true, so the run opens with the hero high in the beam and
	# the clock held; two seconds later he has landed with his weapon and the director is running
	if _t - _game_t > 0.8 and not _spawn_seen:
		_spawn_seen = true
		var hero_y: float = _game.player.global_position.y if _game.player else 0.0
		var ground_y: float = _game.map.player_start().y
		if not _game.spawning or hero_y < ground_y + 3.0:
			_errors.append("no spawn beam: spawning=%s hero y=%.1f ground y=%.1f" % [str(_game.spawning), hero_y, ground_y])
		else:
			print("smoke_run: spawn beam up, hero %.1f m over the sand" % (hero_y - ground_y))
	if _t - _game_t > 4.0 and not _landed_checked:
		_landed_checked = true
		if _game.spawning or not _game._run_started or _run.weapons.is_empty():
			_errors.append("the spawn cinematic did not end / no weapon in hand (spawning=%s started=%s weapons=%d)" % [str(_game.spawning), str(_game._run_started), _run.weapons.size()])
		else:
			print("smoke_run: landed with %s" % str(_run.weapons[0].def.id))
	if _game.player and _game.player.input and not _game.paused:
		var inp = _game.player.input
		inp.wants_move = true
		inp.origin = Vector2(216, 500)
		inp.touch_pos = inp.origin + Vector2(sin(_t * 0.5) * 90.0, -110.0)
	if _game.cards and _game.cards.visible and not _game.cards._offer.is_empty() and not _game.cards._picking:
		_cards_picked += 1
		_game.cards._pick(_game.cards._offer[0])
	if _game.get("chest_screen") and _game.chest_screen and _game.chest_screen.visible and not _game.chest_screen._spinning:
		var cs = _game.chest_screen
		# pass 58: only a roll the chest may banish (a new item; never one the hero holds, an evolution or gold)
		var may_banish: bool = not cs.has_method("can_banish") or bool(cs.can_banish(cs.result()))
		if not _chest_banished and cs.has_method("_banish") and _run.banishes_left > 0 and cs.result().get("def") != null and may_banish:
			# pass 47: the first chest with an item banishes it once, and the reel spins again to a new roll
			_chest_banished = true
			var gone := str(cs.result().get("id", ""))
			cs._banish()
			print("smoke_run: chest banished %s, the reel spins again (banishes left %d)" % [gone, _run.banishes_left])
		else:
			# the reel landed: take the item (every other one is let go for one of the stage's skips while it has one) so
			# both paths run
			_chests += 1
			var take: bool = _chests % 2 == 1 or _run.skips_left <= 0
			cs._finish(take)
			print("smoke_run: chest %d -> %s (%s, skips left %d)" % [_chests, "take" if take else "skip", str(cs.result().get("id", "gold")), _run.skips_left])
	if _game.get("resume_gate") and _game.resume_gate and _game.resume_gate.visible:
		_game.resume_gate.tap()
	if _game.portal_dialog and _game.portal_dialog.visible:
		if not _declined and _game.portal_dialog.has_signal("declined"):
			# pass 48: "Not yet" the first time: unpaused, the portal still there; out past 2.5 m and back in, it asks again
			_declined = true
			_declined_at = _t
			print("smoke_run: portal wave brought %d, cap now %d" % [int(_game.director.portal_wave_spawned), _game.director.current_cap()])
			if _game.director.has_portal_wave() and _game.director.current_cap() != 0:
				_errors.append("the portal wait spawns past its wave (cap %d)" % _game.director.current_cap())
			_game.portal_dialog.declined.emit()
			if _game.paused or _game.portal_dialog.visible:
				_errors.append("Not yet left the run paused or the dialog up")
			if _game.portal == null or not is_instance_valid(_game.portal):
				_errors.append("Not yet took the portal away")
			else:
				_game.player.global_position = _game.portal.global_position + Vector3(3.5, 0.5, 0)
			print("smoke_run: portal -> not yet (paused %s, portal kept %s)" % [str(_game.paused), str(_game.portal != null)])
		else:
			if _declined and not _asked_again:
				_asked_again = true
				print("smoke_run: the portal asked again %.1f s after Not yet" % (_t - _declined_at))
			_portal_decided += 1
			var extract: bool = _portal_decided >= 2
			_game.portal_dialog.visible = false
			_game.portal_dialog.decided.emit(extract)
			print("smoke_run: portal decision %d -> %s" % [_portal_decided, "extract" if extract else "continue"])
	if _perf:
		if int(_t) % 10 == 0 and int(_t) != _last_clear and _t > 1.0:
			_last_clear = int(_t)
			var r: Dictionary = load("res://core/systems/Perf.gd").report()
			var parts: Array = []
			for k in r.keys():
				if k in ["frames", "worst_ms", "slow", "slow_log"]:
					continue
				parts.append("%s %.2f" % [k, r[k]])
			_perf_lines.append("perf t=%3ds frames=%d worst=%.0fms slow=%d | %s | nodes=%d" % [int(_t), r["frames"], r["worst_ms"], r["slow"], " ".join(parts), root.get_child_count() if _game == null else _game.get_tree().get_node_count()])
			for sl in r["slow_log"]:
				_perf_lines.append("   slow frame %.0f ms at clock %s ctx=%s: %s" % [sl["ms"], sl.get("clock", "?"), sl.get("ctx", ""), str(sl["parts"])])
		if _t >= _seconds - 0.5:
			_finish("")
		return
	if _t > 4.0 and _evolve_all and not _evolved and not _run.weapons.is_empty():
		# every evolution once, in the live game: the weapon maxed with two forced path picks, then evolved, so every
		# evolved behaviour and visual runs a few seconds alongside the rest of the build
		_evolved = true
		var reg = root.get_node("Registry")
		var n := 0
		for wid in reg.weapons.keys():
			var wdef = reg.weapon(wid)
			if wdef.is_evolution or wdef.evolves_into == "":
				continue
			var inst = _run.weapon_instance(wid)
			if inst == null:
				inst = load("res://core/systems/WeaponInstance.gd").new(wdef, wdef.max_level)
				_run.weapons.append(inst)
			inst.level = wdef.max_level
			var picks := 0
			for m in reg.mutations_of(wid):
				if picks >= 2:
					break
				if not m.is_hero() and _run.add_mutation(m.id, true):
					picks += 1
			_run.rebuild_sheets()
			var ev = _run.evolve(inst)
			if ev:
				n += 1
		print("smoke_run: evolved %d weapons; build now %s" % [n, str(_run.weapons.map(func(w): return w.def.id))])
	if _t > 6.0 and not _boss_forced:
		_boss_forced = true
		# the stage clock comes from the timeline (pass 46 stretched Red Canyon's stages from 300 s to 430 s)
		var sl := _stage_len()
		if _boss_n >= 2:
			# the second boss straight away: stage 2, the clock just before its event, the director past the earlier ones
			_run.stage = 1
			_run.elapsed = 2.0 * sl - 4.0
			var tl = _game.director.timeline
			for k in range(tl.events.size()):
				if float(tl.events[k].get("t", 0.0)) < 2.0 * sl:
					_game.director._event_i = k + 1
			_game.director._apply_mults()
			print("smoke_run: jumped to the second boss (stage 2, event %d)" % _game.director._event_i)
		else:
			_run.elapsed = sl - 4.0
		for k in range(6):
			_run.add_xp(_run.xp_to_next() + 1.0)
		# exercise the evolution path: max the first weapon, add its passive, open a chest
		if not _run.weapons.is_empty():
			var w = _run.weapons[0]
			w.level = w.def.max_level
			if w.def.evolves_with != "":
				_run.add_or_level_passive(w.def.evolves_with)
			_run.rebuild_sheets()
			var r = _run.open_chest()
			print("smoke_run: chest -> %s" % str(r))
		print("smoke_run: fast-forward to boss")
	if _t > 3.0 and not _pickups_done and _game.pickups and _game.player and not _game.spawning:
		# every pickup kind once: on the ground, and applied straight away (heal, buff, shield, vacuum)
		_pickups_done = true
		var reg = root.get_node("Registry")
		var n := 0
		for id in reg.pickups.keys():
			var pdef = reg.pickup(id)
			_game.pickups.spawn_special(pdef, _game.player.global_position + Vector3(3.0, 0, 0))
			_game.apply_pickup(pdef, _game.player.global_position)
			n += 1
		print("smoke_run: pickups applied %d, timed buffs %d, specials on the ground %d" % [n, _run.timed.size(), _game.pickups.specials.size()])
		# every structure kind once (the shop opens its overlay; the smoke buys nothing and leaves)
		var used := 0
		for sid in reg.structures.keys():
			var sdef = reg.structure(sid)
			if sdef.effect_kind == "shop":
				continue
			_game.use_structure(sdef, _game.player.global_position + Vector3(3, 0, 0))
			used += 1
		var kinds := {}
		for st in _game.structures.items:
			kinds[st.def.id] = true
		print("smoke_run: structures on the map %d, kinds present %d/%d, kinds used %d" % [_game.structures.items.size(), kinds.size(), reg.structures.size(), used])
		# pass 47's items on the hero: Barrel Rush and Prospector work on their own as he runs (Siesta and Steady Hand need
		# him still, which the smoke's S-walk never is)
		for pid in ["barrel_rush", "prospector", "siesta", "steady_hand"]:
			if reg.passive(pid) != null:
				_run.add_or_level_passive(pid)
		print("smoke_run: pass 47 items held %s" % str(_run.passives.keys()))
		# the barrels (pass 44): forty-odd placed, and the hero has walked into some
		if _game.get("barrels") != null:
			print("smoke_run: barrels placed %d, broken %d" % [_game.barrels.pos.size(), _game.barrels.broken])
			# 44 in pass 44; pass 45 took a quarter away (BarrelField.COUNT 33)
			if _game.barrels.pos.size() < 30:
				_errors.append("fewer than 30 barrels placed")
		# the mini-boss once, near the hero, and a chest on the ground to run the reel
		_game.director._run_event({"type": "elite_boss", "enemy": _run.map.skins.get("elite", "")})
		print("smoke_run: elite spawned at %s" % str(_game.director.elite_position().round()))
		_game.pickups.spawn_chest(_game.player.global_position + Vector3(0.5, 0, 0))
		# one pack of every creature on the roster, so every brain runs at least once (the buried spider, the shaman's mend)
		for r in _run.map.timeline.roster:
			_game.enemies.spawn_pack(str(r["enemy"]), _game.player.global_position + Vector3(6, 0, 4), 2)
		print("smoke_run: roster packs spawned: %d kinds" % _run.map.timeline.roster.size())
	if _t > 4.0 and _pickups_done and not _revived and _game.player and not _game.spawning and not _game.paused:
		# pass 48: a pack in the Nuke's reach and the Nuke, then a second pack at his feet and a revive mid-run (the debug
		# kind: no chance spent): the blasts kill the crowd round him (the revive at 100 000 a creature), and the run file
		# must record only what they had, and both. The crowd's grid is rebuilt by hand so each new pack is found this
		# frame.
		_revived = true
		var em = _game.enemies
		em.spawn_pack("skeleton", _game.player.global_position + Vector3(3.0, 0, 0), 4)
		em._rebuild_grid()
		_game.apply_pickup(root.get_node("Registry").pickup("nuke"), _game.player.global_position)
		em.spawn_pack("skeleton", _game.player.global_position + Vector3(-1.5, 0, 0), 4)
		em._rebuild_grid()
		_game._revive("debug")
		print("smoke_run: Nuke and revive (debug), recorded nuke %.0f, revive %.0f" % [float(_run.damage_by_weapon.get("nuke", 0.0)), float(_run.damage_by_weapon.get("revive", 0.0))])
	if _game.projectiles:
		_lobs = [_game.projectiles.lobs_fired, _game.projectiles.lobs_exploded]
	# the floating numbers (pass 47): the crowd's, and the hero's own once something reaches him (god mode: none)
	var dn = _game.get("damage_numbers")
	if dn:
		_numbers_seen = maxi(_numbers_seen, dn.count())
		for n in dn.live():
			if n.who == -2:   # DamageNumbers.HERO (the class is not named here: tools compile before the autoloads)
				_hero_numbers = true
	if _game.get("barrels") != null:
		_barrels_broken = _game.barrels.broken
	if _run.boost_left("barrel_rush") > 0.0:
		_rush_seen = true
	var em = _game.enemies
	if em and em.boss_alive() and _t > 10.0:
		em.damage(em.boss_index, 100000.0, _weapon)
	if _boss_forced and int(_t) % 3 == 0 and int(_t) != _last_clear and em:
		_last_clear = int(_t)
		em.kill_all(true)
	if _game.portal and is_instance_valid(_game.portal) and _game.portal.armed and not _game.paused:
		_game.player.global_position = _game.portal.global_position + Vector3(0.2, 0.5, 0)
	if _portal_decided == 1 and _run.stage == 1 and _run.elapsed < 2.0 * _stage_len() - 10.0:
		_run.elapsed = 2.0 * _stage_len() - 4.0
	var sec := int(_t)
	if sec != _last_report and sec % 2 == 0 and not _perf:
		_last_report = sec
		var cap: int = _game.director.current_cap() if _game.director and _game.director.timeline else -1
		print("t=%3ds  stage=%d  clock=%s  alive=%3d  cap=%3d  kills=%4d  level=%2d  proj=%3d  gems=%3d  weapons=%d  passives=%d  cards=%d  pos=%s" % [
			sec, _run.stage + 1, "%d:%02d" % [int(_run.elapsed) / 60, int(_run.elapsed) % 60], _run.alive, cap, _run.kills, _run.level, _game.projectiles.count, _game.pickups.count,
			_run.weapons.size(), _run.passives.size(), _cards_picked, str(_game.player.global_position.round()) if _game.player else "?"])


## The map's stage length in seconds (the director's timeline once the game is up, else the map's own, else 300).
func _stage_len() -> float:
	if is_instance_valid(_game) and _game.director and _game.director.timeline:
		return float(_game.director.timeline.stage_length)
	if _run and _run.map and _run.map.timeline:
		return float(_run.map.timeline.stage_length)
	return 300.0


func _tick_screens(dt: float) -> void:
	_screen_t += dt
	if _screen_i == -1:
		if _screen_t < 1.0:
			return
		var name: String = current_scene.scene_file_path if current_scene else "?"
		print("smoke_run: after run, scene = %s" % name)
		if not name.ends_with("ResultsScreen.tscn"):
			_errors.append("expected ResultsScreen, got " + name)
		_screen_i = 1
		_screen_t = 0.0
		change_scene_to_file(_screens[_screen_i])
		return
	if _screen_t > 0.8:
		var name: String = current_scene.scene_file_path if current_scene else "?"
		if not name.ends_with(_screens[_screen_i].get_file()):
			_errors.append("expected %s, got %s" % [_screens[_screen_i], name])
		print("smoke_run: visited %s (%d children)" % [name.get_file(), current_scene.get_child_count() if current_scene else -1])
		_screen_i += 1
		_screen_t = 0.0
		if _screen_i >= _screens.size():
			_finish("")
			return
		change_scene_to_file(_screens[_screen_i])


func _finish(problem: String) -> void:
	for l in _perf_lines:
		print(l)
	if not _perf and _declined and not _asked_again:
		_errors.append("the portal never asked again after Not yet")
	var ok: bool = problem == "" and _errors.is_empty() and _portal_decided >= 1 and _cards_picked >= 3
	if problem != "":
		_errors.append(problem)
	if _lobs[0] > 0:
		print("smoke_run: lobs fired %d, exploded on landing %d" % [_lobs[0], _lobs[1]])
	print("smoke_run: damage numbers at most %d in the air, hero numbers seen %s" % [_numbers_seen, str(_hero_numbers)])
	print("smoke_run: barrels broken %d, Barrel Rush ran %s" % [_barrels_broken, str(_rush_seen)])
	if _game and is_instance_valid(_game) and _game.get("projectiles") and _game.projectiles:
		print("smoke_run: missiles by weapon %s" % str(_game.projectiles.missiles_by_weapon))
		print("smoke_run: weapon sheets: %s" % str(_run.weapons.map(func(w): return "%s amount %d cd %.2f" % [w.def.id, w.stat_int("amount", 1), w.stat("cooldown", 1.0)])))
	# the run recorder (pass 45): this run's file under user://analytics/runs/, with rows and the key events
	var an := _analytics_check()
	if an != "":
		_errors.append(an)
		ok = false
	print("smoke_run: %s after %.0fs (kills=%d cards=%d chests=%d portals=%d errors=%s)" % ["OK" if ok else "FAIL", _t, _run.kills, _cards_picked, _chests, _portal_decided, str(_errors)])
	quit(0 if ok else 2)


## The run file this process wrote (its header carries the pid), parsed and checked: rows, a weapon pick, the boss; and
## on the PC the mirror's latest.js, which dashboard.html loads by script tag. Nothing to check in perf mode (no end_run).
func _analytics_check() -> String:
	if _perf:
		return ""
	var dir := "user://analytics/runs"
	var mine: Dictionary = {}
	var fname := ""
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".json") or FileAccess.get_modified_time(dir.path_join(f)) < int(_start_unix) - 2:
			continue
		var fa := FileAccess.open(dir.path_join(f), FileAccess.READ)
		if fa == null:
			continue
		var doc = JSON.parse_string(fa.get_as_text())
		fa.close()
		if doc is Dictionary and int(doc.get("pid", -1)) == OS.get_process_id():
			mine = doc
			fname = f
	if mine.is_empty():
		return "no analytics run file from this run under %s" % dir
	var samples: Array = mine.get("samples", [])
	var events: Array = mine.get("events", [])
	var kinds := {}
	for e in events:
		kinds[str(e.get("kind", ""))] = true
	print("smoke_run: analytics samples=%d events=%d result=%s file=%s" % [samples.size(), events.size(), str(mine.get("result", "")), fname])
	if samples.is_empty():
		return "the analytics run file has no samples"
	if not kinds.has("weapon"):
		return "the analytics events have no weapon pick"
	if not kinds.has("boss_start"):
		return "the analytics events have no boss_start"
	# pass 48: damage is recorded up to what a creature had left, for every source: no zero rows (the revive's 0-damage
	# Nuke ring used to add "nuke: 0"), nothing near the 100 000 a revive or the boss kill deals
	var totals: Dictionary = (mine.get("totals", {}) as Dictionary).get("damage_by_weapon", {})
	print("smoke_run: analytics damage by source %s" % str(totals))
	for k in totals:
		var v := float(totals[k])
		if v <= 0.0:
			return "the run file records a zero damage row: %s %.1f" % [str(k), v]
		if v >= 100000.0:
			return "the run file records overkill: %s %.0f" % [str(k), v]
	if not kinds.has("revive"):
		return "the analytics events have no revive"
	if not totals.has("revive") or not totals.has("nuke"):
		return "the revive's or the Nuke's damage is not in the run file (%s)" % str(totals.keys())
	var mirror := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("analytics/runs")
	if DirAccess.dir_exists_absolute(mirror):
		var lj := mirror.path_join("latest.js")
		if not FileAccess.file_exists(lj):
			return "analytics/runs/latest.js was not written"
		var lf := FileAccess.open(lj, FileAccess.READ)
		var head := lf.get_buffer(13).get_string_from_utf8()
		lf.close()
		if head != "window.RUN = ":
			return "analytics/runs/latest.js does not start with window.RUN = "
	return ""
