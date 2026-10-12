## Pass 69, lane HERO, scratch captures in the debug arena with May: the Inflatable May moment (the throw, the landing
## with its circle, the fooled crowd with their "?" marks, the pop) and Trigger Happy's stream (with nobody in range, then
## at a pack). Windowed at the phone's canvas:
##   godot --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 --path game --script res://tools/_p69_hero_shot.gd -- out=<dir> [only=decoy,stream] [zoom=1.0]
extends SceneTree

var _out := "user://p69_hero"
var _only: PackedStringArray = []
var _zoom := 1.0
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
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
	DirAccess.make_dir_recursive_absolute(_out)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _frames(n: int) -> void:
	for k in range(n):
		await process_frame


func _save_shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p69_hero: ", name)


func _on(section: String) -> bool:
	return _only.is_empty() or _only.has(section)


func _main() -> void:
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "peashooter", "level": 1, "character": "may", "map": "red_canyon", "map_seed": 7}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	if g.camera:
		g.camera.zoom_override = _zoom
	await _wait(3.0)
	if _on("decoy"):
		await _decoy()
	if _on("stream"):
		await _stream()
	_save.data = keep
	quit(0)


func _clear() -> void:
	_run.debug_clear_items()
	_run.build_changed.emit()
	g.enemies.kill_all(false)
	await _frames(3)


## A ring of slow, tough creatures round her, the doll thrown 5.5 m to her right (up the screen and right), frames of the
## flight, the landing, the fooled crowd and the pop.
func _decoy() -> void:
	await _clear()
	_run.add_perk("inflatable_may")
	var em = g.enemies
	var here: Vector3 = g.player.global_position
	var ids := ["skeleton", "goblin", "skeleton", "goblin"]
	for k in range(22):
		var a := TAU * float(k) / 22.0
		var r := 5.0 + 4.0 * float(k % 3) / 2.0
		var i: int = em.spawn(str(ids[k % ids.size()]), here + Vector3(cos(a) * r, 0, sin(a) * r), null, 1.0, 400.0)
		if i >= 0:
			em.speed[i] *= 0.35
	em._rebuild_grid()
	await _wait(1.0)
	g._tick_decoy(0.0)
	var dc = g.decoy
	dc.throw_now()
	dc.to = g.map.clamp_to_arena(g.player.global_position + Vector3(4.2, 0, -3.6))
	dc.to.y = g.map.height_at(dc.to.x, dc.to.z)
	var f0 := Engine.get_process_frames()
	for pair in [[0.15, "decoy_a_throw"], [0.4, "decoy_b_flight"], [0.7, "decoy_c_landed"], [1.3, "decoy_d_fooled"],
			[2.0, "decoy_e_fooled_late"], [2.5, "decoy_f_last"], [2.75, "decoy_g_pop"], [3.6, "decoy_h_after"]]:
		var want := int(round(float(pair[0]) * 60.0))
		while Engine.get_process_frames() - f0 < want:
			await process_frame
		_save_shot(str(pair[1]))
		print("   phase ", dc.phase, " fooled ", em.fooled_indices().size(), " marks ", dc.marks_shown)


## The Tommy with Trigger Happy: the stream along her facing with nobody in range, then into a pack.
func _stream() -> void:
	await _clear()
	_run.debug_set_item("weapon", "tommy_gun", 3)
	_run.debug_set_item("mutation", "trigger_happy", 1)
	_run.build_changed.emit()
	await _wait(1.6)
	_save_shot("stream_a_nobody")
	await _frames(9)
	_save_shot("stream_b_nobody")
	var em = g.enemies
	var here: Vector3 = g.player.global_position
	for k in range(6):
		em.spawn("skeleton", here + Vector3(-2.0 + 0.8 * float(k), 0, -7.0 - 0.6 * float(k % 2)), null, 1.0, 400.0)
	em._rebuild_grid()
	await _wait(1.2)
	_save_shot("stream_c_pack")
	await _frames(9)
	_save_shot("stream_d_pack")
