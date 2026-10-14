## Pass 74 (lane ANALYTICS) scratch: a windowed run driven by a tool, so the run recorder writes a schema 2 file with every
## new part in it (the dashboard's and the CSVs' test record): Astro on Red Canyon, two Totem Poles, the Stranger twice
## (one deal taken, one turned down), a forced special, an Elite-modified pack and an Elite, heals of every kind, a
## reroll, a banish and a skip, the first boss with its HP pegging, the portal into stage 2, a revive, and a death given
## up on Down!. Bounded: a wall-clock watchdog (wall=, seconds) quits whatever happens, and every phase has a cap.
##   bash tools/godot.sh --audio-driver Dummy --resolution 540x960 --fixed-fps 60 --path game --script res://tools/_p74_ANALYTICS_run.gd -- wall=420
## Autoloads through the tree (a tool compiles before them); the recorder is found as the Game's "RunAnalytics" child.
extends SceneTree

var _wall_ms := 420000
var _t0 := 0
var _game: Node
var _run: Node
var _reg: Node
var _done := {}
var _stranger_n := 0
var _totem_n := 0
var _downs := 0
var _offers := 0
var _boss_seen_at := -1.0
var _portal_n := 0
var _stage2_at := -1.0
var _end_ms := -1
var _last_heal := -100.0
var _dying := false
var _log: Array = []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("wall="):
			_wall_ms = int(float(a.substr(5)) * 1000.0)
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _say(s: String) -> void:
	print("p74 run: ", s)


func _start() -> void:
	_t0 = Time.get_ticks_msec()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"character": "astro", "map": "red_canyon", "map_seed": 88, "spawn": true}))
	f.close()
	root.get_node("Save").data["runs_started"] = 1
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	change_scene_to_file("res://game/Game.tscn")
	process_frame.connect(_tick)


func _ra() -> Node:
	return _game.get_node_or_null("RunAnalytics") if _game and is_instance_valid(_game) else null


func _play_t() -> float:
	var ra := _ra()
	return float(ra.get("play_t")) if ra else 0.0


func _tick() -> void:
	if Time.get_ticks_msec() - _t0 > _wall_ms:
		_finish("watchdog after %d ms" % (Time.get_ticks_msec() - _t0))
		return
	if _end_ms > 0:
		if Time.get_ticks_msec() - _end_ms > 2500:
			_finish("done")
		return
	if _game == null:
		var cs = current_scene
		if cs == null or not cs.has_method("open_pause"):
			return
		_game = cs
		_game.player.god = true
		_say("game up")
		return
	if not is_instance_valid(_game) or current_scene != _game:
		_say("the run ended; the Results are up")
		_end_ms = Time.get_ticks_msec()
		return
	_steer()
	_screens()
	_moments()


func _steer() -> void:
	if _game.player and _game.player.input and not _game.paused:
		var inp = _game.player.input
		var t := _play_t()
		inp.wants_move = true
		inp.origin = Vector2(270, 600)
		inp.touch_pos = inp.origin + Vector2(sin(t * 0.45) * 100.0, -100.0 + cos(t * 0.3) * 30.0)


func _screens() -> void:
	var g := _game
	if g.cards and g.cards.visible and not g.cards._offer.is_empty() and not g.cards._picking:
		if g.cards.has_method("reel_running") and g.cards.reel_running():
			return
		_offers += 1
		if _offers == 3 and _run.rerolls_left > 0:
			_say("reroll")
			g.cards._reroll()
			return
		if _offers == 5 and _run.banishes_left > 0 and not g.cards.banish_mode() and g.cards._offer.size() > 1:
			_say("banish")
			g.cards._toggle_banish()
			if g.cards.banish_mode():
				g.cards._pick(g.cards._offer[g.cards._offer.size() - 1])
			return
		if g.cards.banish_mode():
			g.cards._toggle_banish()
		if _offers == 7 and _run.skips_left > 0:
			_say("skip")
			g.cards._skip()
			return
		g.cards._pick(g.cards._offer[0])
		return
	if g.get("chest_screen") and g.chest_screen and g.chest_screen.visible and not g.chest_screen._spinning:
		g.chest_screen._finish(true)
		return
	if g.get("resume_gate") and g.resume_gate and g.resume_gate.visible:
		g.resume_gate.tap()
	if g.get("stranger_screen") and g.stranger_screen and g.stranger_screen.visible:
		_stranger_n += 1
		var take := _stranger_n == 1
		_say("the Stranger -> " + ("deal" if take else "no"))
		g.stranger_screen._finish(take)
		return
	if g.get("structure_shop") and g.structure_shop and g.structure_shop.visible:
		g.structure_shop._finish(false)
		return
	if g.get("totem_screen") and g.totem_screen and g.totem_screen.visible and not g.totem_screen._done:
		var tp: Array = g.totem_screen.planks()
		if not tp.is_empty():
			_totem_n += 1
			var p = tp[mini(_totem_n, tp.size() - 1)]
			_say("totem -> " + str(p.boon.get("id", "")))
			g.totem_screen._pick(p)
		return
	if g.portal_dialog and g.portal_dialog.visible:
		_portal_n += 1
		var extract := _portal_n >= 2
		_say("portal -> " + ("extract" if extract else "continue"))
		g.portal_dialog.visible = false
		g.portal_dialog.decided.emit(extract)
		return
	if g.get("revive_screen") and g.revive_screen and g.revive_screen.visible:
		if not _dying:
			# a fall the script did not plan: up again on the debug revive (it costs no chance), the story goes on
			_say("down (unplanned) -> debug revive")
			g.revive_screen._decide("debug")
			return
		_downs += 1
		if _downs == 1:
			var kind := "gold" if _run.run_gold >= 150 else "debug"
			_say("down -> get up (" + kind + ")")
			g.revive_screen._decide(kind)
		else:
			_say("down -> give up")
			g.revive_screen._decide("give_up")
		return


func _once(key: String, at: float) -> bool:
	if _done.has(key) or _play_t() < at:
		return false
	_done[key] = true
	return true


func _ra_via(v: String) -> void:
	var ra := _ra()
	if ra:
		ra.set("via", v)


func _moments() -> void:
	var g := _game
	if g.paused or g.get("spawning") == true:
		return
	var at: Vector3 = g.player.global_position
	var em = g.enemies
	if _once("god_off", 3.0):
		g.player.god = false
		_say("god off")
	# keep him standing until the planned fall: a Heart when he is low (a named heal)
	if not _dying and g.player.max_hp > 0.0 and g.player.hp < g.player.max_hp * 0.5 and _play_t() - _last_heal > 2.0:
		_last_heal = _play_t()
		g.apply_pickup(_reg.pickup("heart"), at)
	if _once("items", 5.0):
		_ra_via("debug")
		for pid in ["bloodthirst", "mend", "vulture", "brawn", "beer"]:
			if _reg.passive(pid) != null:
				_run.add_or_level_passive(pid)
		_run.rebuild_sheets()
		g.player.refresh_stats()
		_ra_via("card")
		_say("items: lifesteal, regen, Vulture, a line, a passive")
	if _once("totem1", 8.0):
		g.use_structure(_reg.structure("totem_pole"), at + Vector3(2, 0, 0))
	if _once("stranger1", 12.0):
		g.use_structure(_reg.structure("hooded_figure"), at + Vector3(2, 0, 0))
	if _once("special", 16.0):
		g.director._run_event({"type": "swarm", "enemy": "red_goblin", "variant": "RG-B", "count": 1, "pattern": "in_front", "special": true, "name": "Special Goblin"})
		_say("a forced special")
	if _once("elite_mod", 20.0):
		g.director._spawn_elite("", "")
		_say("an Elite-modified pack")
	if _once("elite", 24.0):
		g.director._run_event({"type": "elite_boss", "enemy": "dune_scorpion"})
		_say("an Elite")
	if _once("pickups", 28.0):
		g.apply_pickup(_reg.pickup("cake_slice"), at)
		g.use_structure(_reg.structure("healing_well"), at + Vector3(2, 0, 0))
		_say("a cake slice and the healing well")
	if _once("totem2", 32.0):
		g.use_structure(_reg.structure("totem_pole"), at + Vector3(-2, 0, 0))
	if _once("stranger2", 36.0):
		g.use_structure(_reg.structure("hooded_figure"), at + Vector3(-2, 0, 0))
	if _once("levels", 40.0):
		for k in range(4):
			_run.add_xp(_run.xp_to_next() - _run.xp + 0.01)
		_say("four levels")
	if _once("boss_clock", 48.0):
		var sl: float = float(g.director.timeline.stage_length)
		_run.elapsed = sl - 3.0
		_say("the clock to the first boss")
	# the boss: let him fight it for a while, then thin it so the build finishes it
	if _boss_seen_at < 0.0 and em.boss_index >= 0:
		_boss_seen_at = _play_t()
		_say("boss up: %s" % str(em.types[em.type_idx[em.boss_index]]["def"].id))
	if _boss_seen_at >= 0.0 and em.boss_index >= 0 and _play_t() - _boss_seen_at > 35.0 and not _done.has("boss_thin"):
		_done["boss_thin"] = true
		em.hp[em.boss_index] = maxf(em.max_hp[em.boss_index] * 0.02, 1.0)
		_say("boss thinned")
	if _portal_n >= 1 and _stage2_at < 0.0 and _run.stage >= 1:
		_stage2_at = _play_t()
		_say("stage 2")
	# stage 2: an Elite-modified pack and forty seconds, then the fall (a revive), then the last one (given up)
	if _stage2_at >= 0.0 and _play_t() - _stage2_at > 8.0 and not _done.has("elite_mod2"):
		_done["elite_mod2"] = true
		g.director._spawn_elite("", "")
		_say("stage 2: an Elite-modified pack")
	if _stage2_at >= 0.0 and _play_t() - _stage2_at > 40.0 and _downs == 0 and not g.player.dead and not _done.has("fall1"):
		_done["fall1"] = true
		_dying = true
		g.player.hp = 1.0
		em.spawn_pack("goblin", at + Vector3(1.5, 0, 0), 5)
		_say("the first fall")
	if _done.has("fall1") and _downs == 1 and not g.player.dead and not _done.has("fall2"):
		if not _done.has("fall2_wait"):
			_done["fall2_wait"] = _play_t()
		elif _play_t() - float(_done["fall2_wait"]) > 12.0:
			_done["fall2"] = true
			g.player.hp = 1.0
			em.spawn_pack("goblin", at + Vector3(1.5, 0, 0), 5)
			_say("the last fall")


func _finish(why: String) -> void:
	_say("finish: " + why)
	quit(0)
