## Screenshots of the debug arena's panel, one per tab and one of the quick column over a crowd (pass 33.4), for checking
## the layout without the full capture run. Windowed:
##   "$GODOT" --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/arena_shots.gd -- out=<dir>
extends SceneTree

const TABS := ["enemy", "waves", "items", "hero", "drops", "world"]
var _out := "user://arena_shots"
var _t := 0.0
var _step := 0
var _k := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	process_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	root.get_node("Run").arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	process_frame.connect(_tick)


func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))
	print("arena_shots: ", name)


func _tick() -> void:
	_t += root.get_process_delta_time()
	var g = current_scene
	if g == null or g.get("arena_panel") == null:
		return
	match _step:
		0:
			if _t > 2.0:
				_shot("arena_0_field")
				g.arena_panel.open()
				_step = 1
				_t = 0.0
		1:
			if _t > 0.35:
				if _k > 0:
					_shot("arena_%d_%s" % [_k, TABS[_k - 1]])
				if _k >= TABS.size():
					g.arena_panel.close()
					g.arena_panel.set_clock(6.0)
					g.arena_panel.crowd(150)
					_step = 2
				else:
					g.arena_panel._tab = TABS[_k]
					g.arena_panel._refresh()
					_k += 1
				_t = 0.0
		2:
			if _t > 2.5:
				_shot("arena_7_crowd")
				# the hero's bars (pass 33.6): with the Energy Shield charged, then with the camera pulled out
				g.arena_panel._clear_field()
				root.get_node("Run").debug_set_item("passive", "energy_shield", 3)
				g.player.shield_pts = 999.0
				g.player.hp = g.player.max_hp * 0.6
				g.hud.set_hp(g.player.hp, g.player.max_hp)
				_step = 3
				_t = 0.0
		3:
			if _t > 0.6:
				_shot("arena_8_bars")
				g.camera.zoom_override = 2.5
				_step = 4
				_t = 0.0
		4:
			if _t > 0.6:
				_shot("arena_9_bars_zoomed")
				g.camera.zoom_override = 0.0
				g.leave_arena()
				_step = 5
				_t = 0.0
		5:
			if _t > 1.0:
				quit(0)
