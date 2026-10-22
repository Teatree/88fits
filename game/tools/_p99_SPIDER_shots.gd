## Pass 99 lane SPIDER (scratch): SP-G and SP-H walking at the hero from every side, then dying, in the debug arena.
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p99_SPIDER_shots.gd -- out=<dir> [codes=SP-G,SP-H] [zoom=0.6]
## Bounded: a 90 s watchdog and a 6,000-frame cap quit with code 2 whatever is waiting. The PC save is put back.
extends SceneTree

var _out := "user://p99_spider"
var _codes: Array = ["SP-G", "SP-H"]
var _zoom := 0.6
var _frames := 0
var _run
var _reg
var _save
var _keep: Dictionary = {}
var g


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("codes="):
			_codes = Array(a.substr(6).split(","))
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(90.0, true, false, true).timeout.connect(_bail.bind("watchdog 90 s"))
	process_frame.connect(_count)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _count() -> void:
	_frames += 1
	if _frames > 6000:
		_bail("frame cap 6000")


func _bail(why: String) -> void:
	print("p99_spider: stopped: ", why)
	if _save != null and not _keep.is_empty():
		_save.data = _keep
	quit(2)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p99_spider: ", name)


func _main() -> void:
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save = root.get_node("Save")
	_keep = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "peashooter", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	if _zoom > 0.0 and g.camera:
		g.camera.zoom_override = _zoom
	await _wait(4.0)
	for code in _codes:
		await _one(str(code))
	_save.data = _keep
	quit(0)


func _one(code: String) -> void:
	_run.debug_clear_items()
	_run.build_changed.emit()
	var em = g.enemies
	em.kill_all(false)
	await _wait(0.3)
	var here: Vector3 = g.player.global_position
	# eight around the hero, so every view of the eight directions walks in at once
	for k in range(8):
		var a := TAU * float(k) / 8.0
		em.spawn("desert_spider", here + Vector3(cos(a) * 2.4, 0, sin(a) * 3.4), null, 1.0, 100.0, code)
	em._rebuild_grid()
	var tag := code.replace("-", "").to_lower()
	await _wait(0.4)
	await _shot(tag + "_walk_a")
	await _wait(0.35)
	await _shot(tag + "_walk_b")
	em.kill_all(true)
	await _wait(0.2)
	await _shot(tag + "_die_a")
	await _wait(0.35)
	await _shot(tag + "_die_b")
	await _wait(0.6)
	await _shot(tag + "_dead")
