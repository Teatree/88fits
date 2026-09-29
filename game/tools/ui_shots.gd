## The screens screenshot_run.gd does not reach (pass 34, for the UI review pack): the pause menu's Options tab, the
## portal dialog, the results screen after a run, the collection's hidden part and the bottoms of the Mirror and Settings. Windowed at the phone's 1080x1920:
## godot --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/ui_shots.gd -- out=<dir>
extends SceneTree

var _out := "user://ui_shots"
var _t := 0.0
var _step := 0
var _t0 := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	process_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "boomstick", "level": 4, "character": "astro", "map": "red_canyon", "map_seed": 88}))
	f.close()
	root.get_node("Save").data["runs_started"] = 1
	change_scene_to_file("res://game/Game.tscn")
	process_frame.connect(_tick)


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("ui_shots: ", name)


func _tick() -> void:
	# real time: the window may run uncapped (1000+ fps), and a frame count would leave every fade half done
	_t += root.get_process_delta_time()
	var g = current_scene
	if _step == 0 and g and g.get("pause_screen") and g.player:
		# half a minute of play first, so the pause and results screens have a run to show: a thumb pushing up-screen,
		# every level-up card taken, every resume gate tapped
		g.player.god = true
		var inp = g.player.input
		inp.wants_move = true
		inp.origin = Vector2(540, 1400)
		inp.touch_pos = inp.origin + Vector2(sin(_t * 0.7) * 220.0, -260.0)
		if g.cards and g.cards.visible and not g.cards._offer.is_empty() and not g.cards._picking:
			g.cards._pick(g.cards._offer[0])
		if g.get("resume_gate") and g.resume_gate and g.resume_gate.visible:
			g.resume_gate.tap()
	match _step:
		0:
			if g and g.get("pause_screen") and g.player and _t > 30.0 and not g.paused:
				g.player.input.wants_move = false
				g.open_pause()
				_step = 1
				_t0 = _t
		1:
			if _t - _t0 > 0.6:
				g.pause_screen._tab = 2
				g.pause_screen._refresh()
				_step = 2
				_t0 = _t
		2:
			if _t - _t0 > 0.5:
				_shot("pause_options")
				g.close_pause()
				_step = 3
				_t0 = _t
		3:
			if _t - _t0 > 1.0:
				g.portal_dialog.open(1, true, false)
				_step = 4
				_t0 = _t
		4:
			if _t - _t0 > 0.8:
				_shot("portal_dialog")
				g.portal_dialog.visible = false
				g.set_paused(false)
				root.get_node("Run").died = true
				g.end_run()
				_step = 5
				_t0 = _t
		5:
			if (_t - _t0 > 3.5 and current_scene and current_scene.name.to_lower().contains("result")) or _t - _t0 > 8.0:
				_shot("results")
				change_scene_to_file("res://ui/CollectionScreen.tscn")
				_step = 6
				_t0 = _t
		6:
			# the collection's hidden part, at the end of the book
			if _t - _t0 > 1.2 and current_scene and current_scene.get("scroll"):
				var sc: ScrollContainer = current_scene.scroll
				var y := -1.0
				for c in current_scene.content.get_children():
					if c is Label and (c as Label).text.begins_with("Hidden"):
						y = (c as Control).position.y
				sc.scroll_vertical = int(maxf(y - 60.0, 0.0)) if y >= 0.0 else 999999
				_step = 7
				_t0 = _t
		7:
			if _t - _t0 > 0.5:
				_shot("collection_hidden")
				change_scene_to_file("res://ui/HomesteadScreen.tscn")
				_step = 8
				_t0 = _t
		8:
			if _t - _t0 > 1.2 and current_scene and current_scene.get("_scroll"):
				current_scene._scroll.scroll_vertical = 999999
				_step = 9
				_t0 = _t
		9:
			if _t - _t0 > 0.5:
				_shot("mirror_bottom")
				change_scene_to_file("res://ui/SettingsScreen.tscn")
				_step = 10
				_t0 = _t
		10:
			if _t - _t0 > 1.2 and current_scene and current_scene.get("scroll"):
				current_scene.scroll.scroll_vertical = 999999
				_step = 11
				_t0 = _t
		11:
			if _t - _t0 > 0.5:
				_shot("settings_bottom")
				_step = 12
		12:
			quit(0)
