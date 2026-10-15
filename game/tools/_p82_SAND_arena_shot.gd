## Pass 82, lane SAND: the arena's WORLD tab with its Sand row, and the ground after a tap on "Dunes+P", as the window
## shows them. Windowed, silent, bounded (a watchdog quits after 90 s):
##   bash tools/godot.sh --audio-driver Dummy --resolution 432x960 --path D:/_projects/88fits/game \
##       --script res://tools/_p82_SAND_arena_shot.gd -- out=<dir>
extends SceneTree

var _out := "user://p82_sand_arena"
var g


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(90.0, true, false, true).timeout.connect(func() -> void:
		print("p82_sand_arena: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(n: String) -> void:
	for k in range(3):
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(n + ".png"))
	print("p82_sand_arena: ", n)


func _main() -> void:
	var save = root.get_node("Save")
	var keep: Dictionary = save.data.duplicate(true)
	root.get_node("Run").arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	for k in range(600):
		await process_frame
		g = current_scene
		if g and g.get("arena_panel") != null and g.get("map") != null:
			break
	await _wait(2.0)
	var p = g.arena_panel
	p.open()
	p._tab = "world"
	p._refresh()
	await _wait(0.5)
	await _shot("arena_world")
	# a tap on the Sand row's "Dunes+P" (the row named SandChoice)
	var row: Node = p.find_child("SandChoice", true, false)
	if row:
		for b in row.get_children():
			if b is Button and (b as Button).text == "Dunes+P":
				(b as Button).pressed.emit()
	await _wait(0.3)
	print("p82_sand_arena: sand_id ", g.map.get("sand_id"))
	await _shot("arena_world_after")
	p.close()
	await _wait(0.5)
	await _shot("arena_ground_after")
	save.data = keep
	quit(0)
