## Pass 69, lane FRIS, scratch captures in the debug arena: the Frisbee's throws frame by frame, plain (one disc, then a
## level-5 volley of three), Carry (its chance forced to 1 so a creature rides), Poison Razors and the Flying Saucer
## (its path, a ride and the loop). Windowed at the phone's canvas:
##   godot --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p69_fris_shot.gd -- out=<dir> [only=plain,volley,carry,razors,saucer]
extends SceneTree

var _out := "user://p69_fris"
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
	# a watchdog: whatever happens, the window closes and the Godot lock goes back (a first run hung here)
	create_timer(150.0, true, false, true).timeout.connect(func() -> void:
		printerr("p69_fris: watchdog, quitting")
		quit(2))


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _save_shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p69_fris: ", name)


func _main() -> void:
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "peashooter", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	printerr("p69_fris: scene ", g)
	if g == null:
		quit(1)
		return
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	if g.camera:
		g.camera.zoom_override = 0.62
	await _wait(2.0)
	if _on("plain"):
		await _throw("frisbee", 1, [], "plain", false)
	if _on("volley"):
		await _throw("frisbee", 5, [], "volley", false)
	if _on("carry"):
		await _throw("frisbee", 3, ["carry"], "carry", true)
	if _on("razors"):
		await _throw("frisbee", 3, ["poison_razors"], "razors", false)
	if _on("saucer"):
		await _throw("flying_saucer", 1, ["carry", "poison_razors", "frisbee_trick_shot"], "saucer", true)
	_save.data = keep
	quit(0)


func _on(section: String) -> bool:
	return _only.is_empty() or _only.has(section)


func _build(wid: String, level: int, muts: Array, ahead: float, count := 7) -> void:
	_run.debug_clear_items()
	for m in muts:
		_run.debug_set_item("mutation", str(m), 1)
	var def = _reg.weapon(wid)
	_run.debug_set_item("evolution" if def.is_evolution else "weapon", wid, level)
	_run.build_changed.emit()
	var em = g.enemies
	em.kill_all(false)
	var here: Vector3 = g.player.global_position
	for k in range(count):
		var s := -3.0 + 6.0 * float(k) / maxf(float(count - 1), 1.0)
		em.spawn("skeleton", here + Vector3(s, 0, -ahead - 1.2 * float(k % 3)), null, 1.0, 60.0)
	em._rebuild_grid()


## The weapon built, a throw waited for, then frames 0, 6, 15, 25, 40, 55 and 75 after it. `ride` forces Carry's chance
## to 1 so the first creature hit rides the disc.
func _throw(wid: String, level: int, muts: Array, name: String, ride: bool) -> void:
	await _build(wid, level, muts, 5.0)
	# a build change may open a screen that pauses the run: every wait below is capped, and the run unpaused
	g.set_paused(false)
	await _wait(0.6)
	g.set_paused(false)
	var b = g._behaviors.get(wid)
	if b == null:
		printerr("p69_fris: no behaviour for ", wid)
		return
	if ride:
		var cr = b.inst.params.get("carry")
		if cr is Dictionary:
			cr["chance"] = 1.0
	# let the discs in the air go (two seconds at most), then the next throw
	var guard := 0
	while not (b.discs as Array).is_empty() and guard < 120:
		await process_frame
		guard += 1
	b.cooldown_left = 0.0
	var t0: int = b.throws
	guard = 0
	while b.throws == t0 and guard < 300:
		await process_frame
		guard += 1
	printerr("p69_fris: ", name, " thrown after ", guard, " frames, paused ", g.paused, ", discs ", (b.discs as Array).size())
	await process_frame
	var n := 0
	for at in [0, 6, 15, 25, 40, 55, 75]:
		while n < int(at):
			await process_frame
			n += 1
		_save_shot("%s_f%02d" % [name, int(at)])
	printerr("p69_fris: ", name, " throws ", b.throws, " carries ", b.carries, " loops ", b.loops, " hits ", b.hits)
