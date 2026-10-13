## Pass 70, lane LINES, scratch captures in the debug arena: Bucking Bronco throwing knocked creatures up and away (the
## Hammer's blows on a ring of skeletons), Marshal's Star over the hero, its block and its return, Mother Lode's sweep of
## the screen's gems, Eureka's vein, Prairie Fire's jump. Windowed at the phone's canvas:
##   godot --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p70_LINES_shots.gd -- out=<dir> [only=bronco,star,sweep,vein,prairie]
extends SceneTree

var _out := "user://p70_lines"
var _only: PackedStringArray = []
var _run
var _reg
var _save
var g


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",", false)
	DirAccess.make_dir_recursive_absolute(_out)
	process_frame.connect(_main, CONNECT_ONE_SHOT)
	# a watchdog: an error mid-way must never leave the Godot lock held
	create_timer(240.0, true, false, true).timeout.connect(func():
		print("p70_lines: watchdog quit")
		Engine.time_scale = 1.0
		quit(3))


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p70_lines: ", name, "  fps ", Engine.get_frames_per_second())


## A state change seen on the screen: a few drawn frames, then `s` more seconds.
func _settle(s: float) -> void:
	for k in range(4):
		await process_frame
	await _wait(s)


func _on(section: String) -> bool:
	return _only.is_empty() or _only.has(section)


func _main() -> void:
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save = root.get_node("Save")
	_save.begin_sandbox()
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	await _wait(2.0)
	if _on("bronco"):
		await _bronco()
	if _on("star"):
		await _star()
	if _on("sweep"):
		await _sweep()
	if _on("vein"):
		await _vein()
	if _on("prairie"):
		await _prairie()
	Engine.time_scale = 1.0
	_save.end_sandbox()
	quit(0)


func _crowd(n: int, r: float, id := "skeleton", hp := 400.0) -> void:
	var c: Vector3 = g.player.global_position
	for k in range(n):
		var a := TAU * float(k) / float(n)
		var i: int = g.enemies.spawn(id, c + Vector3(cos(a) * r, 0, sin(a) * r), null, 1.0, hp)
		if i >= 0:
			g.enemies.rise_t[i] = 1.0


## Bucking Bronco with the Hammer: a ring of tough skeletons round the hero; the blows knock them back and about a third
## go up and away; frames a beat apart while they fly.
func _bronco() -> void:
	_run.debug_clear_items()
	_run.debug_set_item("weapon", "hammer", 3)
	_run.debug_set_item("passive", "bucking_bronco", 1)
	_run.build_changed.emit()
	await process_frame
	g.enemies.kill_all(false)
	g.camera.zoom_override = 0.7
	_crowd(12, 2.6)
	_crowd(10, 4.0, "goblin")
	await _settle(0.2)
	var n0: int = g.enemies.bronco_launches
	var taken := 0
	var t0 := Time.get_ticks_msec()
	while taken < 6 and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
		var up := 0
		for i in range(g.enemies.MAX):
			if g.enemies.is_launched(i) and g.enemies.lift_h[i] > 1.2:
				up += 1
		if up >= 2:
			_shot("bronco_%d" % taken)
			taken += 1
			await _wait(0.12)
	print("p70_lines: bronco launches ", g.enemies.bronco_launches - n0, " knock x", _run.weapon_instance("hammer").stat("knockback"))
	await _settle(1.0)
	_shot("bronco_after")
	g.enemies.kill_all(false)
	g.camera.zoom_override = 0.0


## Marshal's Star: the star over his head, the block (a gold burst, BLOCK), the spent star, its return.
func _star() -> void:
	_run.debug_clear_items()
	_run.debug_set_item("passive", "marshals_star", 1)
	_run.build_changed.emit()
	await process_frame
	g.player.refresh_stats()
	g.enemies.kill_all(false)
	g.camera.zoom_override = 0.45
	await _settle(0.8)
	_shot("star_ready")
	g.player.god = false
	g.player.invuln = 0.0
	g.player.hp = g.player.max_hp
	g.player.take_damage(20.0, g.player.global_position + Vector3(1, 0, 0), {"by": "the capture"})
	print("p70_lines: star outcome ", g.player.last_outcome, " hp ", g.player.hp, "/", g.player.max_hp, " blocks ", g.player.star_guard.blocks)
	for k in range(3):
		await process_frame
	_shot("star_block")
	await _wait(0.12)
	_shot("star_block2")
	await _settle(0.6)
	_shot("star_spent")
	# its seconds on the buffs' clock: jump the clock to just before it comes back, then watch it pop in
	g.player.star_guard.ready_at = _run.buff_clock() + 0.25
	await _wait(0.33)
	_shot("star_back_pop")
	await _settle(0.5)
	_shot("star_back")
	g.player.god = true
	g.camera.zoom_override = 0.0


## Mother Lode: gems all over the screen, the sweep: every one up on the magnet arc at once.
func _sweep() -> void:
	_run.debug_clear_items()
	_run.debug_set_item("passive", "mother_lode", 1)
	_run.build_changed.emit()
	await process_frame
	g.enemies.kill_all(false)
	var pm = g.pickups
	pm._sweep_t = 100.0
	var c: Vector3 = g.player.global_position
	for k in range(70):
		var a := randf() * TAU
		var r := randf_range(7.5, 16.0)
		pm.spawn(pm.KIND_GEM_S if k % 3 else pm.KIND_GEM_M, c + Vector3(cos(a) * r, 0, sin(a) * r * 1.4), 1.0)
	g.camera.zoom_override = 0.0
	await _settle(1.5)
	_shot("sweep_before")
	pm._sweep_t = 0.001
	await _settle(0.05)
	print("p70_lines: sweep took ", pm.gem_sweep_last, " gems")
	_shot("sweep_go")
	await _wait(0.2)
	_shot("sweep_arc")
	await _settle(1.2)
	_shot("sweep_after")


## Eureka: a vein bursting out of a kill (forced, so the frame is sure).
func _vein() -> void:
	_run.debug_clear_items()
	_run.debug_set_item("passive", "eureka", 1)
	_run.build_changed.emit()
	await process_frame
	g.enemies.kill_all(false)
	g.camera.zoom_override = 0.5
	await _settle(0.5)
	var at: Vector3 = g.player.global_position + Vector3(1.5, 0, -8.0)
	g.pickups.vein(_reg.enemy("goblin"), at, 1.0, 1.0)
	for k in range(2):
		await process_frame
	_shot("vein_burst")
	await _wait(0.2)
	_shot("vein_fly")
	await _settle(0.8)
	_shot("vein_landed")
	g.camera.zoom_override = 0.0


## Prairie Fire: a burning skeleton whose burn runs out beside another: the ember streak and the next one alight.
func _prairie() -> void:
	_run.debug_clear_items()
	_run.debug_set_item("passive", "prairie_fire", 1)
	_run.build_changed.emit()
	await process_frame
	g.enemies.kill_all(false)
	g.camera.zoom_override = 0.5
	var em = g.enemies
	em.refresh_player_stats()
	var c: Vector3 = g.player.global_position
	var a: int = em.spawn("skeleton", c + Vector3(-1.5, 0, -4.0), null, 1.0, 400.0)
	var b: int = em.spawn("skeleton", c + Vector3(1.5, 0, -5.5), null, 1.0, 400.0)
	em.rise_t[a] = 1.0
	em.rise_t[b] = 1.0
	await _settle(0.5)
	em.ignite(a, "molotov", 1.0, 0.6, 0.0)
	await _wait(0.3)
	_shot("prairie_burning")
	var t0 := Time.get_ticks_msec()
	while em.prairie_jumps == 0 and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	_shot("prairie_jump")
	await _wait(0.25)
	_shot("prairie_caught")
	print("p70_lines: prairie jumps ", em.prairie_jumps, " b burning ", em.is_burning(b))
	g.camera.zoom_override = 0.0
