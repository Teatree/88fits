## Headless integration run. Starts a run straight into gameplay, simulates a thumb that steers in an S,
## auto-picks cards, fast-forwards to the first boss, walks into the portal, continues, extracts, then
## visits Results, Title, Shop, Collection, Settings and PlaySetup. Exit code 0 only if the whole path ran.
## Run: godot --headless --path game --script res://tools/smoke_run.gd -- seconds=90 weapon=boomstick
## Autoloads are reached through the tree because SceneTree scripts compile before autoloads exist.
extends SceneTree

var _seconds := 90.0
var _weapon := "boomstick"
var _map := "dry_gulch"
var _character := "astro"
var _pickups_done := false
var _lobs := [0, 0]
var _t := 0.0
var _last_report := -1
var _game: Node
var _run: Node
var _phase := "run"
var _boss_forced := false
var _portal_decided := 0
var _screens := ["res://ui/ResultsScreen.tscn", "res://ui/TitleScreen.tscn", "res://ui/ShopScreen.tscn", "res://ui/CollectionScreen.tscn", "res://ui/SettingsScreen.tscn", "res://ui/PlaySetup.tscn"]
var _screen_i := -1
var _screen_t := 0.0
var _cards_picked := 0
var _errors: Array = []
var _last_clear := -1


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
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": _weapon, "level": 3, "character": _character, "map": _map}))
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
	if not is_instance_valid(_game) or current_scene != _game:
		_phase = "screens"
		_screen_t = 0.0
		return
	if _game.player and _game.player.input and not _game.paused:
		var inp = _game.player.input
		inp.wants_move = true
		inp.origin = Vector2(216, 500)
		inp.touch_pos = inp.origin + Vector2(sin(_t * 0.5) * 90.0, -110.0)
	if _game.cards and _game.cards.visible and not _game.cards._offer.is_empty() and not _game.cards._picking:
		_cards_picked += 1
		_game.cards._pick(_game.cards._offer[0])
	if _game.portal_dialog and _game.portal_dialog.visible:
		_portal_decided += 1
		var extract: bool = _portal_decided >= 2
		_game.portal_dialog.visible = false
		_game.portal_dialog.decided.emit(extract)
		print("smoke_run: portal decision %d -> %s" % [_portal_decided, "extract" if extract else "continue"])
	if _t > 6.0 and not _boss_forced:
		_boss_forced = true
		_run.elapsed = 296.0
		for k in range(6):
			_run.add_xp(_run.xp_to_next() + 1.0)
		# exercise the evolution path: max the starter, add its passive, open a chest
		if not _run.weapons.is_empty():
			var w = _run.weapons[0]
			w.level = w.def.max_level
			if w.def.evolves_with != "":
				_run.add_or_level_passive(w.def.evolves_with)
			_run.rebuild_sheets()
			var r = _run.open_chest()
			print("smoke_run: chest -> %s" % str(r))
		print("smoke_run: fast-forward to boss")
	if _t > 3.0 and not _pickups_done and _game.pickups and _game.player:
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
		print("smoke_run: structures on the map %d, kinds used %d" % [_game.structures.items.size(), used])
	if _game.projectiles:
		_lobs = [_game.projectiles.lobs_fired, _game.projectiles.lobs_exploded]
	var em = _game.enemies
	if em and em.boss_alive() and _t > 10.0:
		em.damage(em.boss_index, 100000.0, _weapon)
	if _boss_forced and int(_t) % 3 == 0 and int(_t) != _last_clear and em:
		_last_clear = int(_t)
		em.kill_all(true)
	if _game.portal and is_instance_valid(_game.portal) and _game.portal.armed and not _game.paused:
		_game.player.global_position = _game.portal.global_position + Vector3(0.2, 0.5, 0)
	if _portal_decided == 1 and _run.stage == 1 and _run.elapsed < 590.0:
		_run.elapsed = 596.0
	var sec := int(_t)
	if sec != _last_report and sec % 2 == 0:
		_last_report = sec
		print("t=%3ds  stage=%d  clock=%s  alive=%3d  kills=%4d  level=%2d  proj=%3d  gems=%3d  weapons=%d  passives=%d  cards=%d  pos=%s" % [
			sec, _run.stage + 1, "%d:%02d" % [int(_run.elapsed) / 60, int(_run.elapsed) % 60], _run.alive, _run.kills, _run.level, _game.projectiles.count, _game.pickups.count,
			_run.weapons.size(), _run.passives.size(), _cards_picked, str(_game.player.global_position.round()) if _game.player else "?"])


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
	var ok: bool = problem == "" and _errors.is_empty() and _portal_decided >= 1 and _cards_picked >= 3
	if problem != "":
		_errors.append(problem)
	if _lobs[0] > 0:
		print("smoke_run: lobs fired %d, exploded on landing %d" % [_lobs[0], _lobs[1]])
	print("smoke_run: %s after %.0fs (kills=%d cards=%d portals=%d errors=%s)" % ["OK" if ok else "FAIL", _t, _run.kills, _cards_picked, _portal_decided, str(_errors)])
	quit(0 if ok else 2)
