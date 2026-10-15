## Pass 82 (lane FEEL) scratch benchmark: what every kill's follow-through costs. The real game in the debug arena, a
## standing crowd of goblins round the hero kept at `crowd`, `kills` of them killed by a hit every frame (and as many
## spawned again). Blocks of `block` seconds alternate A (the pass 82 follow-through: each one up out of the sand before
## the kill) and B (as before pass 82: the same kill with the body still under rise_targetable, so _corpse_follow skips
## it), and each block prints ms per frame of the enemies' sim and render, the effects and the whole frame.
##   godot --audio-driver Dummy --resolution 504x1122 --fixed-fps 60 --path game --script res://tools/_p82_FEEL_bench.gd -- [kills=4] [crowd=250] [block=4] [blocks=6]
extends SceneTree

const WATCHDOG_S := 200.0

var _kills := 4
var _crowd := 250
var _block := 4.0
var _blocks := 6
var _run
var _perf
var g
var _t0 := 0
var _alive: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("kills="):
			_kills = int(a.substr(6))
		elif a.begins_with("crowd="):
			_crowd = int(a.substr(6))
		elif a.begins_with("block="):
			_block = float(a.substr(6))
		elif a.begins_with("blocks="):
			_blocks = int(a.substr(7))
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG_S * 1000.0):
		print("p82_bench: WATCHDOG, quitting")
		quit(2)
	return false


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _main() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_run = root.get_node("Run")
	var save = root.get_node("Save")
	var keep: Dictionary = save.data.duplicate(true)
	_perf = load("res://core/systems/Perf.gd")
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	if g == null or not g.has_method("set_paused"):
		print("p82_bench: no game scene")
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
	for k in range(_crowd):
		_spawn_one()
	await _wait(1.0)
	var res := {"A": {}, "B": {}}
	for blk in range(_blocks):
		var mode := "A" if blk % 2 == 0 else "B"
		_perf.report()
		var frames := 0
		var t_start := Time.get_ticks_usec()
		var t_end := t_start + int(_block * 1000000.0)
		var tosses0: int = em.corpse_tosses
		while Time.get_ticks_usec() < t_end:
			_kill_some(mode)
			await process_frame
			frames += 1
		var wall := float(Time.get_ticks_usec() - t_start) / 1000.0 / float(maxi(frames, 1))
		var r: Dictionary = _perf.report()
		var line := "p82_bench: block %d %s | %.2f ms/frame (%d frames) | sim %.3f render %.3f fx %.3f | particles %d | tosses %d" % [blk, mode, wall, frames, float(r.get("enemies.sim", 0.0)), float(r.get("enemies.render", 0.0)), float(r.get("fx", 0.0)), int(g.fx._n), int(em.corpse_tosses) - tosses0]
		print(line)
		var acc: Dictionary = res[mode]
		for k in ["wall", "sim", "render", "fx"]:
			acc[k] = float(acc.get(k, 0.0))
		acc["wall"] += wall
		acc["sim"] += float(r.get("enemies.sim", 0.0))
		acc["render"] += float(r.get("enemies.render", 0.0))
		acc["fx"] += float(r.get("fx", 0.0))
		acc["n"] = int(acc.get("n", 0)) + 1
	for mode in ["A", "B"]:
		var acc: Dictionary = res[mode]
		var n := float(maxi(int(acc.get("n", 1)), 1))
		print("p82_bench: mean %s | %.2f ms/frame | sim %.3f render %.3f fx %.3f" % [mode, float(acc["wall"]) / n, float(acc["sim"]) / n, float(acc["render"]) / n, float(acc["fx"]) / n])
	save.data = keep
	quit(0)


func _spawn_one() -> void:
	var em = g.enemies
	var here: Vector3 = g.player.global_position
	var a := randf() * TAU
	var r := randf_range(4.0, 13.0)
	var i: int = em.spawn("goblin", here + Vector3(cos(a), 0, sin(a)) * r, null, 1.0, 50.0)
	if i >= 0:
		em.speed[i] = 0.0
		em.rise_t[i] = 1.0
		_alive.append(i)


func _kill_some(mode: String) -> void:
	var em = g.enemies
	var here: Vector3 = g.player.global_position
	var done := 0
	while done < _kills and not _alive.is_empty():
		var i: int = _alive.pop_front()
		if em.alive[i] == 0 or em.state[i] == em.STATE_DYING:
			continue
		em.rise_t[i] = 1.0 if mode == "A" else em.rise_targetable * 0.5
		em.damage(i, 99999999.0, "revolver", em.pos[i] - here, 0.0)
		done += 1
	for k in range(done):
		_spawn_one()
