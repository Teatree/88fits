## Pass 73, lane CARDS, scratch captures: the fortune cards in play, in every look (A the old icons, B-E the four card
## framings) as a phone's kept card look puts them on (Save.set_card_look -> Registry.apply_card_looks): the HUD with five
## cards and an evolved one, a level-up offer of two cards and a Risen card, the pause screen's Build tab. Windowed at
## the phone's canvas:
##   godot --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p73_CARDS_shots.gd -- out=<dir> [looks=A,B,C,D,E]
extends SceneTree

var _out := "user://p73_cards"
var _looks: PackedStringArray = ["A", "B", "C", "D", "E"]
var _run
var _reg
var _save
var g


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("looks="):
			_looks = a.substr(6).split(",", false)
	DirAccess.make_dir_recursive_absolute(_out)
	process_frame.connect(_main, CONNECT_ONE_SHOT)
	# a watchdog: an error mid-way must never leave the Godot lock held
	create_timer(240.0, true, false, true).timeout.connect(func():
		print("p73_cards: watchdog quit")
		quit(3))


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	for k in range(3):
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p73_cards: ", name)


func _main() -> void:
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save = root.get_node("Save")
	_save.begin_sandbox()
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 2, "character": "drifter", "map": "red_canyon", "map_seed": 7}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	_run.debug_clear_items()
	_run.debug_set_item("weapon", "revolver", 3)
	for pair in [["brawn", 2], ["clover", 1], ["lodestone", 3], ["evade", 4], ["thirst", 1], ["marshals_star", 1]]:
		_run.debug_set_item("passive", str(pair[0]), int(pair[1]))
	await _wait(1.0)
	for code in _looks:
		_save.set_card_look(code)
		_run.build_changed.emit()
		await _wait(0.4)
		await _shot("hud_%s" % code)
		# a level-up offer: a new card, an upgrade, a Risen card
		var offer: Array = [
			{"type": "passive", "id": "deadeye", "def": _reg.passive("deadeye"), "level_from": 0, "level_to": 1, "is_new": true, "weight": 1.0},
			{"type": "passive", "id": "brawn", "def": _reg.passive("brawn"), "level_from": 2, "level_to": 3, "is_new": false, "weight": 1.0},
			{"type": "passive", "id": "shackles", "def": _reg.passive("shackles"), "level_from": 4, "level_to": 5, "is_new": false, "weight": 1.0,
				"evolve": true, "src_id": "ducktape"},
		]
		g.set_paused(true)
		g.cards.show_offer(offer, "LEVEL 7!", false)
		await _wait(1.2)
		await _shot("levelup_%s" % code)
		g.cards.visible = false
		g.set_paused(false)
		await _wait(0.2)
		g.open_pause()
		await _wait(0.6)
		await _shot("pause_%s" % code)
		g.close_pause()
		await _wait(0.3)
	_save.set_card_look("")
	_save.end_sandbox()
	quit(0)
