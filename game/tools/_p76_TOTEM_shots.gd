## Pass 76, lane TOTEM: the screenshots of the Claude Design brief for the Totem Pole's screen (docs/ui_review/totem/).
## Windowed, silent, at the phone's canvas:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --script res://tools/_p76_TOTEM_shots.gd -- out=<dir> [only=world,hud,menu,siblings,art] [inset=130] [seed=11]
## One real run of Red Canyon (not the arena: the map's own poles and signs), the Drifter in god mode:
##   world:    a sign whose arm points at a pole and the pole (08), the hero in its ring with the pie filling (09), the
##             menu the game rolls itself (07), a real tap on a plank and the toast (10), the same view with the pole
##             grey and the arm pale (11).
##   hud:      the run at 2:30 with a mid-run build and the crowd, the floating stick down (12).
##   menu:     the totem screen on three chosen offers over the live run (01, 02, 03; with inset=130 the same at the
##             top inset a camera cutout asks for).
##   siblings: the level-up cards (13) and the Stranger's bargain (14) over the same run.
##   art:      the pole's painting and its used grey as the game makes it (art_*.png).
## Every wait is bounded and a watchdog quits after 240 s whatever happens. The save is never written (godot.sh keeps
## the PC's aside as well).
extends SceneTree

var _out := "user://p76_totem_shots"
var _only: Array = []
var _inset := -1
var _seed := 11
var _suffix := ""
var _run
var _save
var _reg
var g
var _boons


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",", false)
		elif a.begins_with("inset="):
			_inset = int(a.substr(6))
		elif a.begins_with("seed="):
			_seed = int(a.substr(5))
	if _inset >= 0:
		_suffix = "_inset%d" % _inset
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(240.0, true, false, true).timeout.connect(func() -> void:
		print("p76_totem: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _want(n: String) -> bool:
	return _only.is_empty() or _only.has(n)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(n: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(n + _suffix + ".png"))
	print("p76_totem: ", n + _suffix)


func _launch(d: Dictionary) -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	_reg = root.get_node("Registry")
	_boons = load("res://core/systems/TotemBoons.gd")
	var keep: Dictionary = _save.data.duplicate(true)
	var st = root.get_node("Settings")
	var inset_was: int = st.top_inset
	if _inset >= 0:
		st.top_inset = _inset
	# a player's screens: the developer's debug buttons off for the captures (set back at the end, never saved)
	var dbg_was: bool = st.debug_mode
	var dbg_btn_was: bool = st.debug_modal_buttons
	st.debug_mode = false
	st.debug_modal_buttons = false
	if _want("art"):
		_art()
	if _want("world") or _want("hud") or _want("menu") or _want("siblings"):
		await _start_run()
		_mid_run()
		if _want("world"):
			await _world()
		if _want("hud") or _want("menu") or _want("siblings"):
			await _in_play()
		if _want("menu"):
			await _menus()
		if _want("siblings"):
			await _siblings()
	st.top_inset = inset_was
	st.debug_mode = dbg_was
	st.debug_modal_buttons = dbg_btn_was
	_save.data = keep
	print("p76_totem: done")
	quit(0)


## The pole's painting and its used grey, as the game draws them.
func _art() -> void:
	var d = _reg.structure("totem_pole")
	var tex: Texture2D = load("res://art/sprites/props/st_totem_pole.png")
	if tex:
		tex.get_image().save_png(_out.path_join("art_totem_pole_painting.png"))
	var sm = load("res://core/systems/StructureManager.gd")
	var grey: Texture2D = sm.grey_painting(d)
	if grey:
		grey.get_image().save_png(_out.path_join("art_totem_pole_painting_used.png"))
	print("p76_totem: art")


## A real run of the map (its own poles and signs), the Drifter in god mode, the clock stopped while the world is shot.
func _start_run() -> void:
	_launch({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": _seed, "analytics": false})
	_run.arena_next = false
	change_scene_to_file("res://game/Game.tscn")
	await _game_ready()
	await _wait(2.5)
	g.player.god = true
	g.director.stop()
	g.enemies.kill_all(false)
	await _wait(1.0)


func _game_ready() -> void:
	for k in range(900):
		await process_frame
		g = current_scene
		if g and g.get("enemies") != null and g.get("player") != null and g.player.is_inside_tree() and g.get("director") != null:
			return


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, g.map.height_at(p.x, p.z), p.z)


func _put_hero(p: Vector3) -> void:
	g.player.global_position = _ground(p)
	g.player.velocity = Vector3.ZERO
	g.camera.snap_to(g.player)


## The nearest sign arm that points at a pole: [sign foot, pole]; the nearest pole to the start when no arm does.
func _sign_and_pole() -> Array:
	var signs = g.get_node_or_null("Signs")
	var best = null
	var best_d := INF
	var at := Vector3.ZERO
	if signs:
		for rec: Dictionary in signs.arms:
			var s = rec.get("structure")
			if s == null or not is_instance_valid(s) or s.def.id != "totem_pole":
				continue
			var foot: Vector3 = signs.spots[int(rec["sign"])]
			var dd := Vector2(foot.x - s.global_position.x, foot.z - s.global_position.z).length()
			if dd < best_d:
				best_d = dd
				best = s
				at = foot
	if best == null:
		for s in g.structures.items:
			if s.def.id == "totem_pole":
				var d0: float = s.global_position.length()
				if d0 < best_d:
					best_d = d0
					best = s
					at = s.global_position + Vector3(4, 0, 4)
	print("p76_totem: sign at %s, pole at %s, %.1f m apart" % [at, best.global_position if best else Vector3.ZERO, best_d])
	return [at, best]


func _world() -> void:
	var pair := _sign_and_pole()
	var foot: Vector3 = pair[0]
	var pole = pair[1]
	if pole == null:
		print("p76_totem: no pole")
		return
	var pp: Vector3 = pole.global_position
	# the hero south of the two, both up the screen; the camera backs off for a pair far apart
	var mid := (foot + pp) * 0.5
	var dx := absf(foot.x - pp.x)
	var dz := absf(foot.z - pp.z)
	var zoom := clampf(maxf(dx / 9.0, dz / 16.0), 1.0, 1.9)
	var view_at := mid + Vector3(0.0, 0.0, 7.5 * zoom)
	g.camera.zoom_override = zoom
	_put_hero(view_at)
	await _wait(1.6)
	await _shot("08_world_pole_and_sign")
	# the hero steps into the pole's small circle beside it and stands: the pie fills (3 s); a nearer camera
	g.camera.zoom_override = 0.65
	_put_hero(pp + Vector3(0.8, 0.0, 0.15))
	await _wait(1.6)
	await _shot("09_world_standing_in_ring")
	var waited := 0.0
	while waited < 6.0 and not g.totem_screen.visible:
		await _wait(0.1)
		waited += 0.1
	await _wait(1.0)
	await _shot("07_totem_screen_from_a_pole")
	print("p76_totem: rolled ", g.totem_screen.offer())
	# a real tap on the first plank
	var pl: Array = g.totem_screen.planks()
	if pl.size() >= 1:
		await _tap((pl[0] as Control).get_global_rect().get_center())
	waited = 0.0
	while waited < 3.0 and g.totem_screen.visible:
		await _wait(0.05)
		waited += 0.05
	await _wait(0.5)
	await _shot("10_world_after_the_pick")
	# the same view as 08, the pole used
	_put_hero(view_at)
	g.camera.zoom_override = zoom
	await _wait(2.2)
	await _shot("11_world_used_pole_grey")
	g.camera.zoom_override = 0.0
	print("p76_totem: boons now ", _run.totem_boons)


func _tap(at: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = at
	e.pressed = true
	root.push_input(e)
	await process_frame
	await process_frame
	var u := InputEventScreenTouch.new()
	u.index = 0
	u.position = at
	u.pressed = false
	root.push_input(u)
	await process_frame


## A mid-run kit on the HUD before anything is shot: level 9 at 2:30, three weapons (the Revolver with a mutation), three
## fortune cards and a passive item, some gold; no path offer comes due (the slots spent), so only the captures open
## screens.
func _mid_run() -> void:
	_run.debug_clear_items()
	for it in [["weapon", "revolver", 4], ["weapon", "boomstick", 3], ["weapon", "land_mine", 2],
			["passive", "stride", 2], ["passive", "brawn", 1], ["passive", "deadeye", 1], ["passive", "desperado", 1]]:
		_run.debug_set_item(it[0], it[1], it[2])
	var ms: Array = _reg.mutations_of("revolver")
	for m in ms:
		if not m.is_hero():
			_run.debug_set_item("mutation", m.id, 1)
			break
	_run.build_changed.emit()
	_run.level = 9
	_xp_at(0.55)
	_run.run_gold = 47
	_run.gold_changed.emit(47)
	_run.elapsed = 150.0
	_run.path_slot = 99
	_run.rebuild_sheets()


func _xp_at(frac: float) -> void:
	_run.xp = _run.xp_to_next() * frac
	_run.xp_changed.emit(_run.xp, _run.xp_to_next())


## Any screen the run opened by itself (a level-up, a chest) closed again.
func _close_modals() -> void:
	var up: Array = g.visible_modals()
	if up.is_empty():
		return
	print("p76_totem: closing ", up)
	for m in [g.cards, g.chest_screen, g.totem_screen, g.stranger_screen]:
		if m and is_instance_valid(m):
			m.visible = false
	if g.get("resume_gate") and g.resume_gate:
		g.resume_gate.visible = false
	g.modal_reset()
	g.set_paused(false)


## The run at 2:30 with the mid-run kit, the crowd coming, the stick down: the HUD in play (12). The XP is held at 55%
## every frame so no level-up opens its cards over it.
func _in_play() -> void:
	_put_hero(Vector3.ZERO)
	var d = g.director
	for k in range(d.timeline.events.size()):
		if float(d.timeline.events[k].get("t", 0.0)) < _run.elapsed:
			d._event_i = k + 1
	d._apply_mults()
	d.running = true
	var inp = g.player.input
	var origin := Vector2(300, 1480)
	var r: float = inp.radius_px()
	var t0 := Time.get_ticks_msec()
	var frames := 0
	while Time.get_ticks_msec() - t0 < 16000 and frames < 4000:
		var a := float(Time.get_ticks_msec() - t0) / 1000.0 * 0.55
		inp.wants_move = true
		inp.keyboard = false
		inp.origin = origin
		inp.touch_pos = origin + Vector2(cos(a), sin(a)) * r * 0.8
		_xp_at(0.55)
		if not g.visible_modals().is_empty():
			_close_modals()
		await process_frame
		frames += 1
	_close_modals()
	await _wait(0.3)
	if _want("hud"):
		await _shot("12_hud_in_play")
	# the thumb lifts: the screens that follow open over the crowd, the stick gone
	inp.force_release()
	inp.wants_move = false
	_xp_at(0.55)


## A chosen gift: a pool entry with its amount set, its feathers from TotemBoons.quality.
func _boon(id: String, value: float) -> Dictionary:
	var d = _reg.structure("totem_pole")
	for e: Dictionary in _boons.pool_of(d):
		if str(e["id"]) == id:
			var lo := float(e["min"])
			var hi := float(e["max"])
			return {"id": id, "name": str(e["name"]), "animal": str(e["animal"]), "stat": str(e["stat"]), "op": str(e["op"]),
				"value": value, "min": lo, "max": hi, "quality": _boons.quality(value, lo, hi)}
	return {}


## Three offers on the totem screen over the live run: the commons, the three without an animal's line, the long words.
func _menus() -> void:
	var d = _reg.structure("totem_pole")
	var offers := [
		["01_totem_screen_offer_a", [_boon("wolf", 0.02), _boon("whale", 5.0), _boon("bear", 0.02)]],
		["02_totem_screen_offer_b", [_boon("thunderbird", -0.04), _boon("frog", 0.03), _boon("raven", 0.02)]],
		["03_totem_screen_offer_c", [_boon("serpent", 0.03), _boon("killer_whale", 0.04), _boon("salmon", 0.1)]],
	]
	for o in offers:
		g.set_paused(true)
		g.totem_screen.open(o[1], d)
		await _wait(1.2)
		await _shot(str(o[0]))
		g.totem_screen.visible = false
		g.set_paused(false)
		await _wait(0.3)


func _card(type: String, def, from: int, to: int) -> Dictionary:
	return {"type": type, "id": def.id, "def": def, "level_from": from, "level_to": to, "is_new": from == 0, "weight": 1.0}


## The level-up cards (13) and the Stranger's bargain (14), over the same run.
func _siblings() -> void:
	g.player.input.wants_move = false
	var offer := [_card("weapon", _reg.weapon("boomstick"), 3, 4), _card("passive", _reg.passive("stride"), 2, 3),
		_card("passive", _reg.passive("desperado"), 1, 2)]
	_run.rerolls_left = 1
	_run.skips_left = 2
	_run.banishes_left = 1
	g.set_paused(true)
	g.cards.show_offer(offer, "LEVEL 10!", false)
	await _wait(1.2)
	await _shot("13_sibling_level_up_cards")
	g.cards.visible = false
	g.set_paused(false)
	await _wait(0.3)
	g.set_paused(true)
	g.stranger_screen.open({"type": "passive", "id": "guillotine", "def": _reg.passive("guillotine"), "level_from": 0, "level_to": 2, "is_new": true}, 0.15)
	await _wait(1.2)
	await _shot("14_sibling_the_stranger")
	g.stranger_screen.visible = false
	g.set_paused(false)
	await _wait(0.3)
