## Pass 69, lane SALT, scratch captures in the debug arena: the Salt's shaker and patches as the hero walks an arc (white,
## Sea Salt's pink, Hiwa Kai's black with its crystals), at the game's own camera and closer, and the shaker mid-pour.
## Windowed at the phone's canvas:
##   godot --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p69_salt_shot.gd -- out=<dir> [only=white,pink,black,spill]
extends SceneTree

var _out := "user://p69_salt"
var _only: PackedStringArray = []
var _hero := "drifter"
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
		elif a.begins_with("hero="):
			_hero = a.substr(5)
	DirAccess.make_dir_recursive_absolute(_out)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _save_shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p69_salt: ", name)


func _on(section: String) -> bool:
	return _only.is_empty() or _only.has(section)


func _main() -> void:
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "salt", "level": 1, "character": _hero, "map": "red_canyon", "map_seed": 7}))
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
	if _on("white"):
		await _salt("salt", 5, [], "white")
	if _on("pink"):
		await _salt("salt", 5, ["sea_salt"], "pink")
	if _on("spill"):
		await _salt("salt", 5, ["salt_spill"], "spill")
	if _on("black"):
		await _salt("hiwa_kai", 1, ["sea_salt", "salt_spill", "thing_about_luck"], "black")
	if _on("flats"):
		await _flats()
	_save.data = keep
	quit(0)


## Nothing but `wid` with `muts`; the hero walks an arc of about 12 m over 4 s, laying salt, a few skeletons walk into
## it; shots at the game's camera, mid-pour close up, and closer still.
func _salt(wid: String, level: int, muts: Array, name: String) -> void:
	_run.debug_clear_items()
	for m in muts:
		_run.debug_set_item("mutation", str(m), 1)
	var def = _reg.weapon(wid)
	_run.debug_set_item("evolution" if def.is_evolution else "weapon", wid, level)
	_run.build_changed.emit()
	await process_frame
	var em = g.enemies
	em.kill_all(false)
	var c: Vector3 = g.player.global_position
	var b = g._behaviors.get(wid)
	if b == null:
		print("p69_salt: no behaviour for ", wid)
		return
	g.camera.zoom_override = 0.0
	# the arc: a half circle of radius 4 m round a point to his right
	var centre := c + Vector3(4, 0, 0)
	var t := 0.0
	var spawned := false
	while t < 4.2:
		var a := PI - PI * (t / 4.2)
		var p := centre + Vector3(cos(a) * 4.0, 0, -sin(a) * 4.0)
		p.y = g.map.height_at(p.x, p.z)
		g.player.global_position = p
		g.player.velocity = Vector3.ZERO
		if t > 2.0 and not spawned:
			spawned = true
			for k in range(4):
				em.spawn("skeleton", c + Vector3(-2.0 + float(k) * 1.2, 0, 3.5), null, 1.0, 80.0)
		await process_frame
		t += 1.0 / 60.0
	print("p69_salt: ", wid, " patches ", b.patches.patches.size(), " laid ", b.laid, " ticks ", b.ticks_dealt, " crunches ", b.crunches)
	_save_shot(name + "_game")
	# mid-pour, closer
	g.camera.zoom_override = 0.55
	await _wait(0.4)
	b.cooldown_left = 0.0
	await _wait(0.18)
	_save_shot(name + "_pour")
	await _wait(0.6)
	g.camera.zoom_override = 0.4
	await _wait(0.3)
	_save_shot(name + "_close")
	g.camera.zoom_override = 0.22
	await _wait(0.5)
	_save_shot(name + "_shaker")
	g.camera.zoom_override = 0.0
	await _wait(0.2)


## Salt Flats on the real hero (run with hero=buck): a patch laid ahead, he walks away from it with a low charge, then
## back into it: the charge is full at once.
func _flats() -> void:
	_run.debug_clear_items()
	_run.debug_set_item("mutation", "salt_flats", 1)
	_run.debug_set_item("weapon", "salt", 1)
	_run.build_changed.emit()
	await process_frame
	var b = g._behaviors.get("salt")
	if b == null:
		print("p69_salt: flats: no salt behaviour")
		return
	var p0: Vector3 = g.player.global_position
	b.patches.patches.clear()
	b.patches.add(p0 + Vector3(4, 0, 0), 1.4, 30.0, p0)
	b.cooldown_left = 99.0
	g.player._momentum_t = 0.0
	_run.momentum = 0.0
	print("p69_salt: flats: hero ", g.player.character.id if g.player.character else "?", " momentum hero ", g.player.momentum, " charge ", _run.momentum)
	for k in range(40):
		var p := p0 + Vector3(4.0 * float(k) / 39.0, 0, 0)
		p.y = g.map.height_at(p.x, p.z)
		g.player.global_position = p
		await process_frame
	print("p69_salt: flats: after walking in, charge ", _run.momentum, " flats ", b.flats)
	await _shot("flats_in")


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	_save_shot(name)
