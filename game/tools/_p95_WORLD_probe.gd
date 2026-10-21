## Pass 95 lane WORLD's despawn probe (scratch, after smoke_run.gd): a headless run of the real game on Red Canyon
## where the hero (in god mode) walks a square, 25 s a side, so the crowd is left behind again and again. Every frame it
## reads the crowd on its own: a creature that was alive and not dying last frame and is gone this frame went without a
## death (a despawn), and it must have been OFF the screen (the camera's own test, CameraRig.on_screen with the manager's
## margin) and farther than the map's despawn distance. Every 5 s a line: the clock, alive against the cap, the
## manager's despawned count, the probe's own count, how far the farthest creature is, violations. Exit 1 on any
## violation or a script error. Headless:
##   bash tools/godot.sh --headless --path D:/_projects/88fits/game --script res://tools/_p95_WORLD_probe.gd -- seconds=120
extends SceneTree

const LEG_S := 25.0
const DIRS := [Vector2(0, -110), Vector2(110, 0), Vector2(0, 110), Vector2(-110, 0)]

var _seconds := 120.0
var _game
var _run
var _t := 0.0
var _game_t := -1.0
var _last: Dictionary = {}
var _gone := 0
var _bad := 0
var _notes: Array = []
var _report_t := 0.0
var _cards := 0
var _alive_min_after := 999
var _refill_seen := false
var _wall0 := 0.0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seconds="):
			_seconds = float(a.trim_prefix("seconds="))
	_wall0 = Time.get_unix_time_from_system()
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 3, "character": "drifter", "map": "red_canyon", "spawn": false, "stage": 1}))
	f.close()
	var save := root.get_node("Save")
	if save.has_method("begin_sandbox"):
		save.begin_sandbox()
	save.data["runs_started"] = 1
	_run = root.get_node("Run")
	var err := change_scene_to_file("res://game/Game.tscn")
	if err != OK:
		printerr("p95_world_probe: could not load Game.tscn (%d)" % err)
		quit(1)
		return
	process_frame.connect(_tick)


func _tick() -> void:
	var dt: float = root.get_process_delta_time()
	_t += dt
	if Time.get_unix_time_from_system() - _wall0 > _seconds * 4.0 + 60.0:
		printerr("p95_world_probe: watchdog: the wall clock ran away")
		_finish()
		return
	if _game == null:
		_game = current_scene
		if _game == null or not _game.has_method("open_pause"):
			_game = null
			return
		if _game.player:
			_game.player.god = true
		_game_t = _t
		return
	if not is_instance_valid(_game) or current_scene != _game:
		printerr("p95_world_probe: the game scene went away")
		_finish()
		return
	# the walk: a square, LEG_S a side
	if _game.player and _game.player.input and not _game.paused:
		var inp = _game.player.input
		inp.wants_move = true
		inp.origin = Vector2(216, 500)
		inp.touch_pos = inp.origin + DIRS[int((_t - _game_t) / LEG_S) % 4]
	# the screens, as smoke_run answers them: the first card, the chest's roll taken, the Stranger and the shop left,
	# the totem's first gift, the resume gate tapped
	if _game.cards and _game.cards.visible and not _game.cards._offer.is_empty() and not _game.cards._picking:
		_cards += 1
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
	var em = _game.enemies
	var cam = _game.camera
	if em == null or cam == null or _game.player == null:
		return
	var ppm: float = float(cam.pixels_per_metre()) if cam.has_method("pixels_per_metre") else 90.0
	var margin: float = float(em.SCREEN_MARGIN_M) * ppm
	var hero: Vector3 = _game.player.global_position
	var dist: float = float(em.despawn_cfg.get("distance", 40.0))
	var dying: int = int(em.STATE_DYING)
	var now := {}
	var far_max := 0.0
	for i in range(int(em.MAX)):
		if em.alive[i] != 1:
			continue
		var p: Vector3 = em.pos[i]
		var d := Vector2(p.x - hero.x, p.z - hero.z).length()
		far_max = maxf(far_max, d)
		var on: bool = cam.on_screen(p + Vector3(0, 0.6 + em.lift_h[i], 0), margin)
		now[i] = [int(em.serial[i]), int(em.state[i]), on, d, str(em.types[em.type_idx[i]]["def"].id)]
	for i in _last:
		var l: Array = _last[i]
		if now.has(i) and int(now[i][0]) == int(l[0]):
			continue
		if int(l[1]) == dying:
			continue
		# gone without a death: a despawn (nothing else frees a living creature in a run)
		_gone += 1
		if bool(l[2]) or float(l[3]) <= dist:
			_bad += 1
			if _notes.size() < 12:
				_notes.append("t %.1f: %s went %s at %.1f m" % [_t - _game_t, l[4], "ON THE SCREEN" if bool(l[2]) else "within the distance", float(l[3])])
	_last = now
	var alive: int = em.alive_count()
	if em.despawned > 0:
		_alive_min_after = mini(_alive_min_after, alive)
		var dir = _game.get("director")
		if dir != null and alive >= int(float(dir.current_cap()) * 0.5):
			_refill_seen = true
	if _t - _report_t >= 5.0:
		_report_t = _t
		var dir = _game.get("director")
		var cap: int = int(dir.current_cap()) if dir != null else -1
		print("p95_world_probe: t %5.1f  alive %3d / cap %3d  despawned %3d (probe saw %3d)  farthest %5.1f m  hero (%.0f, %.0f)  violations %d" % [_t - _game_t, alive, cap, int(em.despawned), _gone, far_max, hero.x, hero.z, _bad])
	if _t - _game_t >= _seconds:
		_finish()


func _finish() -> void:
	var em = _game.enemies if _game != null and is_instance_valid(_game) else null
	var by: Dictionary = em.despawned_by if em != null else {}
	print("p95_world_probe: done after %.0f s: despawned %d (by creature %s), the probe counted %d gone without a death, %d violations, cards %d, the crowd refilled past half the cap after a despawn: %s, the least alive after one: %d" % [
		_t - _game_t, int(em.despawned) if em != null else -1, str(by), _gone, _bad, _cards, str(_refill_seen), _alive_min_after])
	for n in _notes:
		print("p95_world_probe:   " + str(n))
	quit(1 if _bad > 0 else 0)
