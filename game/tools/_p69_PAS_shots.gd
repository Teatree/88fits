## Pass 69, lane PAS, scratch captures in the debug arena: Snake Oil's pink overheal on the HP bar, Last Stand's cold
## drained screen with its red heartbeat rim (beside a plain frame and High Noon's gold), the Magnet's pull (gems up on the
## magnet arc, the purple ring) and Hot Springs' pulse ring. Windowed at the phone's canvas:
##   godot --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p69_PAS_shots.gd -- out=<dir> [only=overheal,last_stand,magnet,springs]
extends SceneTree

var _out := "user://p69_pas"
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
		print("p69_pas: watchdog quit")
		Engine.time_scale = 1.0
		quit(3))


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	var lsf = g.get("last_stand_fx") if g else null
	print("p69_pas: ", name, "  fps ", Engine.get_frames_per_second(), "  scale ", Engine.time_scale,
		("  left %.2f str %.2f" % [lsf.left, lsf._strength]) if lsf else "")


## A state change seen on the screen: a few drawn frames, then `s` more seconds (the window can run slowly on a busy PC).
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
	var keep: Dictionary = _save.data.duplicate(true)
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
	if _on("overheal"):
		await _overheal()
	if _on("last_stand"):
		await _last_stand()
	if _on("magnet"):
		await _magnet()
	if _on("springs"):
		await _springs()
	Engine.time_scale = 1.0
	_save.data = keep
	quit(0)


func _crowd(n: int, r: float, id := "skeleton") -> void:
	var c: Vector3 = g.player.global_position
	for k in range(n):
		var a := TAU * float(k) / float(n)
		g.enemies.spawn(id, c + Vector3(cos(a) * r, 0, sin(a) * r), null, 1.0, 200.0)


## Snake Oil maxed: a full bar with no overheal, half the overheal, all of it, close up on the bar.
func _overheal() -> void:
	_run.debug_clear_items()
	_run.debug_set_item("passive", "snake_oil", 3)
	_run.build_changed.emit()
	await process_frame
	g.player.refresh_stats()
	g.camera.zoom_override = 0.6
	g.player.hp = g.player.max_hp
	g.player.overheal = 0.0
	g.player.damaged.emit(g.player.hp, g.player.max_hp)
	await _settle(0.6)
	_shot("overheal_none")
	g.player.overheal = g.player.overheal_cap() * 0.5
	await _settle(0.3)
	_shot("overheal_half")
	g.player.heal(10000.0)
	await _settle(0.3)
	print("p69_pas: overheal ", g.player.overheal, " of ", g.player.overheal_cap(), " max ", g.player.max_hp)
	_shot("overheal_full")
	# a wounded bar beside it, to see the pink never shows on a bar that is not full
	g.player.overheal = 0.0
	g.player.hp = g.player.max_hp * 0.6
	g.player.damaged.emit(g.player.hp, g.player.max_hp)
	await _settle(0.3)
	_shot("overheal_wounded")
	g.camera.zoom_override = 0.0
	g.player.hp = g.player.max_hp


## Last Stand: first the real thing run out on its own (2 s of real time; the clock must come back), then again held open
## longer for the pictures: a plain frame, the slowed time on a heartbeat and between beats, and High Noon's look.
func _last_stand() -> void:
	_run.debug_clear_items()
	_run.debug_set_item("passive", "last_stand", 3)
	_run.debug_set_item("weapon", "revolver", 3)
	_run.build_changed.emit()
	await process_frame
	g.enemies.kill_all(false)
	_crowd(10, 4.0)
	_crowd(8, 7.0, "goblin")
	g.camera.zoom_override = 0.0
	await _settle(1.2)
	_shot("last_stand_before")
	g.player.hp = g.player.max_hp * 0.25
	g.player.damaged.emit(g.player.hp, g.player.max_hp)
	_run.last_stand_next = 0.0
	var t0 := Time.get_ticks_msec()
	if _run.last_stand_check(g.player.hp, g.player.max_hp):
		g._last_stand()
	print("p69_pas: started, time_scale ", Engine.time_scale, " might x", _run.last_stand_mult())
	while g.last_stand_fx.active and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
	print("p69_pas: ended by itself after %.2f s of wall time, time_scale %.2f, active %s" % [float(Time.get_ticks_msec() - t0) / 1000.0, Engine.time_scale, _run.last_stand_active])
	# again, held open for the pictures
	await _settle(0.5)
	_run.last_stand_next = 0.0
	if _run.last_stand_check(g.player.hp, g.player.max_hp):
		g._last_stand()
	g.last_stand_fx.start(30.0)
	await _settle(0.6)
	_shot("last_stand_on")
	# the beat: wait for the swell, then for the quiet between
	for k in range(200):
		await process_frame
		if g.last_stand_fx.beat_at(g.last_stand_fx._beat_t) > 0.85:
			break
	_shot("last_stand_beat")
	for k in range(200):
		await process_frame
		if g.last_stand_fx.beat_at(g.last_stand_fx._beat_t) < 0.05:
			break
	_shot("last_stand_between")
	g.last_stand_fx.finish()
	await _settle(0.8)
	print("p69_pas: finished, time_scale ", Engine.time_scale, " active ", _run.last_stand_active)
	_shot("last_stand_after")
	# High Noon's look (its gold flash) for the difference
	g.hud.flash(Color(1.0, 0.78, 0.3, 0.32), 1.5)
	g.hud.toast("HIGH NOON", Color(1.0, 0.82, 0.35))
	await _settle(0.05)
	_shot("high_noon_compare")
	g.player.hp = g.player.max_hp
	g.enemies.kill_all(false)
	await _settle(1.0)


## The Magnet at level 3 (7 m): gems scattered 2.5-10 m round him and a few coins; the pull goes off, the gems within
## reach thrown up on the arc and diving in, the purple ring at the reach.
func _magnet() -> void:
	_run.debug_clear_items()
	_run.debug_set_item("passive", "magnet", 3)
	_run.build_changed.emit()
	await process_frame
	g.enemies.kill_all(false)
	var pm = g.pickups
	var c: Vector3 = g.player.global_position
	for k in range(40):
		var a := randf() * TAU
		var r := randf_range(2.5, 10.0)
		pm.spawn(pm.KIND_GEM_S if k % 3 else pm.KIND_GEM_M, c + Vector3(cos(a) * r, 0, sin(a) * r), 1.0)
	for k in range(6):
		var a := randf() * TAU
		pm.spawn(pm.KIND_COIN, c + Vector3(cos(a) * 4.0, 0, sin(a) * 4.0), 1.0)
	g.camera.zoom_override = 0.0
	await _settle(1.5)
	_shot("magnet_before")
	pm._xp_pull_t = 0.001
	await _settle(0.05)
	print("p69_pas: pull took ", pm.xp_pull_last, " gems, reach ", pm.xp_pull_radius())
	_shot("magnet_pull")
	await _settle(0.15)
	_shot("magnet_arc")
	await _settle(1.0)
	_shot("magnet_after")


## Hot Springs: creatures round him, a big heal: the green-gold ring races out over 3 m and the crowd takes the pulse.
func _springs() -> void:
	_run.debug_clear_items()
	_run.debug_set_item("passive", "hot_springs", 3)
	_run.build_changed.emit()
	await process_frame
	g.player.refresh_stats()
	g.enemies.kill_all(false)
	_crowd(8, 2.2)
	g.camera.zoom_override = 0.5
	await _settle(1.0)
	g.player.hp = g.player.max_hp * 0.5
	g.player._pulse_cd = 0.0
	g.player.heal(20.0)
	for k in range(3):
		await process_frame
	_shot("springs_pulse")
	for k in range(3):
		await process_frame
	_shot("springs_pulse2")
	g.camera.zoom_override = 0.0
