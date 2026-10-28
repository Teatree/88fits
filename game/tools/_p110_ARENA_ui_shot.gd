## Pass 110 (lane ARENA): the arena's new controls as Garry sees them, captured (windowed, bounded): the SHOTS tab (top,
## middle, picker with a creature and its looks open), the quick column with the framing's band guide, the field with
## everything hidden.
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p110_ARENA_ui_shot.gd -- out=<dir>
extends SceneTree

var A: Dictionary = {}
var g = null
var _ended := false
var _out := "D:/_projects/88fits/tools/dl/p110/arena/ui"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=", true, 1)
		A[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_out = str(A.get("out", _out))
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(120.0, true, false, true).timeout.connect(func(): print("ui_shot: watchdog"); _end(2))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _end(code: int) -> void:
	if _ended:
		return
	_ended = true
	paused = false
	Engine.time_scale = 1.0
	quit(code)


func _frames(n: int) -> void:
	for k in range(n):
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))
	print("ui_shot: saved ", name)


func _main() -> void:
	var save = root.get_node("Save")
	var keep: Dictionary = save.data.duplicate(true)
	root.get_node("Run").launch_override = {"arena": true, "analytics": false, "character": "drifter"}
	change_scene_to_file("res://game/Game.tscn")
	for k in range(1200):
		await process_frame
		var cs = current_scene
		if cs != null and cs.get("arena_panel") != null and cs.get("player") != null:
			g = cs
			break
	if g == null:
		print("ui_shot: no arena")
		_end(1)
		return
	await _frames(30)
	var p = g.arena_panel
	p.toggle_crowd("lesser_scorpion")
	p.toggle_crowd_look("lesser_scorpion", "LS-D")
	p.toggle_crowd("fire_ant")
	p.open()
	p._tab = "shots"
	p._refresh()
	await _frames(4)
	await _shot("shots_tab_top")
	p._scroll.scroll_vertical = 900
	await _frames(4)
	await _shot("shots_tab_picker")
	p._scroll.scroll_vertical = 100000
	await _frames(4)
	await _shot("shots_tab_bottom")
	p.close()
	p.set_framing(true)
	p.set_freeze(1)
	p.set_speed(0.5)
	p.mass_spawn(p.crowd_entries(), 600, {"layout": "ring", "clear_r": 4.0, "seed": 3})
	await _frames(10)
	await _shot("quick_column_framed")
	p.set_clean(true)
	await _frames(4)
	await _shot("clean_hint")
	await create_timer(3.5, true, false, true).timeout
	await _shot("clean")
	save.data = keep
	_end(0)
