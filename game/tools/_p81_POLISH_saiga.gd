## Pass 81 (lane POLISH) scratch capture: the Saiga Sniper in play, in the debug arena (no weapons, god mode).
## 1 he comes in at his stand-off up the screen and walks in towards the hero to his range; 2 he holds, aims (the red
## lines), locks and fires; 3 the hero walks right up to him (he never runs); 4 a hit spoils his next aim.
##   godot --audio-driver Dummy --fixed-fps 60 --resolution 1080x1920 --path game --script res://tools/_p81_POLISH_saiga.gd -- out=<dir> [every=15] [scale=0.5]
## Writes <out>/saiga_f<frame>.png (scaled) and <out>/saiga.txt (a line every 15 frames). Bounded waits and a watchdog.
extends SceneTree

const WATCHDOG_S := 300.0

var _out := "user://p81_saiga"
var _every := 15
var _scale := 0.5
var _run
var _save
var g
var _t0 := 0
var _fr := 0
var _log: FileAccess


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("every="):
			_every = maxi(int(a.substr(6)), 1)
		elif a.begins_with("scale="):
			_scale = float(a.substr(6))
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG_S * 1000.0):
		print("p81_saiga: WATCHDOG, quitting")
		quit(2)
	return false


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	if g == null or not g.has_method("set_paused"):
		print("p81_saiga: no game scene")
		quit(1)
		return
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	_run.debug_clear_items()
	_run.rebuild_sheets()
	_run.build_changed.emit()
	await _wait(0.5)
	var em = g.enemies
	em.kill_all(false)
	g.projectiles.clear_all()
	await _wait(0.5)
	_log = FileAccess.open(_out.path_join("saiga.txt"), FileAccess.WRITE)
	var hero: Node3D = g.player
	var here: Vector3 = hero.global_position
	var i: int = em.spawn("saiga_sniper", here + Vector3(0, 0, -20.0))
	_log.store_line("spawned %d at %.2f m (stand_off), pace %.3f, speed %.3f, follow %s" % [i, _flat(em.pos[i], here), em.pace, em.speed[i], str(em.types[em.type_idx[i]]["def"].sniper.get("follow"))])
	# 1-2: in, hold, aim, shot
	var phase := "approach"
	var shot_at := -1
	var guard := 0
	while guard < 60 * 30:
		guard += 1
		await _tick(i, phase)
		if phase == "approach" and em.state[i] == 1:
			phase = "aim"
		if em.sniper_shots > 0 and shot_at < 0:
			shot_at = _fr
			phase = "shot"
		if shot_at >= 0 and _fr > shot_at + 60:
			break
	# 3: the hero walks right up to him
	phase = "walk_up"
	guard = 0
	while guard < 60 * 8 and _flat(em.pos[i], hero.global_position) > 3.0:
		guard += 1
		var to: Vector3 = em.pos[i] - hero.global_position
		to.y = 0.0
		hero.global_position += to.normalized() * float(hero.max_speed()) / 60.0
		await _tick(i, phase)
	phase = "close"
	for k in range(90):
		await _tick(i, phase)
	# 4: the hero steps back out and hits him while he aims: the aim is spoiled
	phase = "back_out"
	guard = 0
	while guard < 60 * 4 and _flat(em.pos[i], hero.global_position) < 9.0:
		guard += 1
		var away: Vector3 = hero.global_position - em.pos[i]
		away.y = 0.0
		hero.global_position += away.normalized() * float(hero.max_speed()) / 60.0
		await _tick(i, phase)
	phase = "wait_aim"
	guard = 0
	var hit := false
	while guard < 60 * 14:
		guard += 1
		await _tick(i, phase)
		if not hit and em._snipers.has(i) and int(em._snipers[i]["phase"]) == 1 and float(em._snipers[i]["t"]) > 0.8:
			em.damage(i, 1.0, "revolver")
			hit = true
			phase = "hit"
		if hit and phase == "hit":
			for k in range(60):
				await _tick(i, phase)
			break
	_log.store_line("done: shots %d, cancels %d, flee_starts %d, fleeing %s" % [em.sniper_shots, em.sniper_cancels, em.flee_starts, str(em.is_fleeing(i))])
	_log.close()
	print("p81_saiga: done -> ", _out)
	_save.data = keep
	quit(0)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _tick(i: int, phase: String) -> void:
	await process_frame
	_fr += 1
	var em = g.enemies
	if _fr % 15 == 0:
		var ph := int(em._snipers[i]["phase"]) if em._snipers.has(i) else -1
		_log.store_line("f%04d %-9s dist %.2f state %d sniper_phase %d shots %d cancels %d fleeing %s" % [_fr, phase, _flat(em.pos[i], g.player.global_position), em.state[i], ph, em.sniper_shots, em.sniper_cancels, str(em.is_fleeing(i))])
	if _fr % _every != 0:
		return
	var img := root.get_viewport().get_texture().get_image()
	if _scale != 1.0:
		img.resize(int(img.get_width() * _scale), int(img.get_height() * _scale), Image.INTERPOLATE_BILINEAR)
	img.save_png(_out.path_join("saiga_f%04d.png" % _fr))
