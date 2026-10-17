## Pass 87, lane SOL, scratch captures in the debug arena: Solenne in a chosen look (look=SOL-F) standing, then walking in
## eight directions (several frames each), for the puppet looks' check in game (size, sliding feet, the face angle: her
## sun face must look where she walks). Windowed at the phone's canvas, a watchdog quits a hung run:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/_p87_SOL_shot.gd -- out=<dir> look=SOL-F
extends SceneTree

const WATCHDOG := 150.0

var _out := "user://p87_sol"
var _look := "SOL-F"
var _zoom := 0.0
var _run
var _save
var g


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("look="):
			_look = a.substr(5)
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(WATCHDOG, true, false, true).timeout.connect(func():
		print("p87_sol: WATCHDOG fired, quitting")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _frames(n: int) -> void:
	for k in range(n):
		await process_frame


func _save_shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p87_sol: ", name)


func _stick(stick: Vector2) -> void:
	var inp = g.player.input
	inp.set_process(false)
	inp.wants_move = stick.length() > 0.0
	inp.stick_dir = stick


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	_save.set_hero_look("solenne", _look)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "sun_scepter", "level": 1, "character": "solenne", "map": "red_canyon", "map_seed": 7}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	if g.camera and _zoom > 0.0:
		g.camera.zoom_override = _zoom
	g.enemies.kill_all(false)
	print("p87_sol: look ", g.player.look.look_code() if g.player.look else "?")
	await _wait(2.0)
	_stick(Vector2.ZERO)
	await _wait(0.6)
	_save_shot("idle_0")
	await _frames(7)
	_save_shot("idle_1")
	var dirs := {"up": Vector2(0, -1), "upright": Vector2(0.7071, -0.7071), "right": Vector2(1, 0), "downright": Vector2(0.7071, 0.7071),
		"down": Vector2(0, 1), "downleft": Vector2(-0.7071, 0.7071), "left": Vector2(-1, 0), "upleft": Vector2(-0.7071, -0.7071)}
	for name: String in dirs.keys():
		g.enemies.kill_all(false)
		_stick(dirs[name])
		await _wait(0.8)
		for k in range(4):
			_save_shot("run_%s_%d" % [name, k])
			await _frames(5)
		# back towards the start so the arena's edge never stops her
		_stick(-(dirs[name] as Vector2))
		await _wait(0.8)
	_stick(Vector2.ZERO)
	_save.data = keep
	quit(0)
