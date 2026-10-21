## Pass 95, lane VACE: the Desert Spider's side walk in the game, for the eye (before and after a Frames export).
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --script res://tools/_p95_VACE_shot.gd -- out=<dir> [code=SP-B] [zoom=0.5] [shots=10]
## The debug arena, the hero in god mode without a weapon, four spiders in the chosen look placed level with him to his
## left and right (so they walk sideways at him and play run_s), PNGs every few frames. Every wait is bounded.
extends SceneTree

var _out := "user://p95_vace_shots"
var _code := "SP-B"
var _zoom := 0.5
var _shots := 10
var _run
var _save
var g


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("code="):
			_code = a.substr(5)
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
		elif a.begins_with("shots="):
			_shots = int(a.substr(6))
	DirAccess.make_dir_recursive_absolute(_out)
	process_frame.connect(_main, CONNECT_ONE_SHOT)
	# the watchdog: whatever happens, the window closes
	create_timer(60.0, true, false, true).timeout.connect(func() -> void: print("p95_vace_shot: watchdog"); quit(1))


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p95_vace_shot: ", name)


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	_save.begin_sandbox()
	var keep: Dictionary = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "peashooter", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	if g == null:
		print("p95_vace_shot: no game scene")
		quit(1)
		return
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	_run.debug_clear_items()
	_run.build_changed.emit()
	await _wait(0.5)
	var em = g.enemies
	em.kill_all(false)
	await _wait(0.6)
	var here: Vector3 = g.player.global_position
	var made: Array = []
	for x: float in [-4.5, -3.0, 3.0, 4.5]:
		made.append(em.spawn("desert_spider", here + Vector3(x, 0, -1.5), null, 1.0, 100.0, _code))
	print("p95_vace_shot: spawned ", made)
	em._rebuild_grid()
	g.camera.zoom_override = _zoom
	for k in range(20):
		await process_frame
	for k in range(_shots):
		await _shot("walk_%02d" % k)
		for j in range(4):
			await process_frame
	_save.data = keep
	quit(0)
