## Pass 126 lane ITEMS captures: the two new items as the player meets them: the level-up cards (new, upgrade, Evolved),
## the pause screen's Build and Stats tabs, the toast after a paid skip, the word under the slots, the Collection's text
## read off TextGen. Windowed, silent, bounded by a watchdog and frame counts; the save in the sandbox.
## Run: GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game --log-file <f> --script res://tools/_p126_ITEMS_shots.gd -- out=<dir>
extends SceneTree

var _out := ""
var _run
var _reg


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	create_timer(180.0, true, false, true).timeout.connect(func():
		print("p126_shots: watchdog, quitting")
		quit(2))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _frames(n: int) -> void:
	for _k in range(n):
		await process_frame


func _shot(name: String) -> void:
	await _frames(3)
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p126_shots: ", name)


func _card(id: String, from: int, to: int) -> Dictionary:
	return {"type": "passive", "id": id, "def": _reg.passive(id), "level_from": from, "level_to": to, "is_new": from == 0}


func _main() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("Save").begin_sandbox()
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"character": "drifter", "level": 1, "map": "red_canyon", "map_seed": 5, "spawn": false,
		"analytics": false, "stage": 1}))
	f.close()
	change_scene_to_file("res://game/Game.tscn")
	await _frames(120)
	var g = current_scene
	g.player.god = true
	g.director.set_process(false)
	g.director.set_physics_process(false)
	# the words, for the log
	var tg = load("res://core/systems/TextGen.gd")
	for id: String in ["assayers_scale", "canteen"]:
		var d = _reg.passive(id)
		print("p126_shots: TEXT ", id, ": ", tg.passive_text(d))
		for lv in range(1, d.max_level + 1):
			print("p126_shots:   L%d %s | next: %s" % [lv, tg.passive_description(d, lv), tg.next_level_text(d, lv)])
	var th = _reg.passive("thirst")
	for lv in range(1, 5):
		print("p126_shots:   Death L%d %s" % [lv, tg.passive_description(th, lv)])
	print("p126_shots:   Death Risen %s" % tg.passive_description(_reg.passive("bloodthirst"), 1))
	# the cards: both new, then the upgrades, then Evolved
	g.set_paused(true)
	g.cards.show_offer([_card("assayers_scale", 0, 1), _card("canteen", 0, 1), _card("thirst", 0, 1)], "LEVEL 4!", false)
	await _frames(60)
	await _shot("cards_new")
	g.cards.visible = false
	_run.add_or_level_passive("assayers_scale")
	_run.add_or_level_passive("canteen")
	await _frames(2)
	g.cards.show_offer([_card("assayers_scale", 1, 2), _card("canteen", 1, 2)], "LEVEL 5!", false)
	await _frames(60)
	await _shot("cards_upgrade")
	g.cards.visible = false
	while _run.passive_level("assayers_scale") < 3:
		_run.add_or_level_passive("assayers_scale")
	while _run.passive_level("canteen") < 4:
		_run.add_or_level_passive("canteen")
	await _frames(2)
	g.cards.show_offer([_card("assayers_scale", 3, 4), _card("canteen", 4, 5)], "LEVEL 9!", false)
	await _frames(60)
	await _shot("cards_evolved")
	g.cards.visible = false
	_run.add_or_level_passive("assayers_scale")
	_run.add_or_level_passive("canteen")
	await _frames(2)
	g.set_paused(false)
	# the pause screen
	g.open_pause()
	await _frames(20)
	g.pause_screen._tab = 0
	g.pause_screen._refresh()
	await _frames(10)
	g.pause_screen._scroll.scroll_vertical = 999999
	await _shot("pause_build")
	g.pause_screen._tab = 1
	g.pause_screen._refresh()
	await _frames(10)
	await _shot("pause_stats_0")
	g.pause_screen._scroll.scroll_vertical = 999999
	await _shot("pause_stats_1")
	g.close_pause()
	await _frames(10)
	if g.resume_gate.visible:
		g.resume_gate.tap()
	g.set_paused(false)
	await _frames(10)
	# a paid skip's toast and coin pop, the word under the slots
	_run.skips_left = 2
	_run.canteen_left = 12.0
	_run.use_skip()
	await _frames(25)
	await _shot("toast_paid")
	quit(0)
