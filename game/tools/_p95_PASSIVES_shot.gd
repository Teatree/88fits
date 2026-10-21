## Pass 95, lane PASSIVES: captures of the passive items on the rarity ladder at the phone's canvas, for the eye.
##   godot --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p95_PASSIVES_shot.gd -- out=<dir>
## 01-cards-rungs: a level-up offer of three upgrades landing on Uncommon, Legendary and Evolved (the dark plate in the
## brass ring with the Evolved icon, the EVOLVED tag, the ember band); 02-cards-common-ladder: the Cake's last three
## rungs (Epic, Legendary, Evolved); 03-cards-new: three new items (their rarity's plate, no rung word); 04-pause-build:
## the Build tab with items at every rung, the Cake open on its Evolved rung; 05-collection-cake: the Collection page
## of a common item (the kind line and the level grid with its rung names and colours); 06-collection-magnet: an epic's.
## Every wait is bounded and a watchdog quits after WATCHDOG seconds.
extends SceneTree

const WATCHDOG := 150.0
var _out := "user://p95_passives"
var _run
var _reg
var _save
var g


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p95_passives_shot: ", name)


func _watchdog() -> void:
	await create_timer(WATCHDOG, true, false, true).timeout
	print("p95_passives_shot: watchdog: quitting after %d s" % int(WATCHDOG))
	quit(2)


func _card(type: String, def, from: int, to: int) -> Dictionary:
	return {"type": type, "id": def.id, "def": def, "level_from": from, "level_to": to, "is_new": from == 0, "weight": 1.0}


func _build(items: Array) -> void:
	_run.debug_clear_items()
	for it in items:
		_run.debug_set_item(it[0], it[1], it[2])
	_run.build_changed.emit()


func _main() -> void:
	_watchdog()
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save = root.get_node("Save")
	var kept := FileAccess.get_file_as_string("user://save.json")
	# a run in the debug arena (god mode, no crowd)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 3, "character": "drifter", "map": "red_canyon", "map_seed": 7}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	await _wait(2.5)
	g.hud._banner.visible = false
	g.player.input.wants_move = false
	var cake = _reg.passive("cake")
	var desp = _reg.passive("desperado")
	var magnet = _reg.passive("magnet")
	# 01: three upgrades, each on a different rung
	_build([["weapon", "revolver", 3], ["passive", "cake", 1], ["passive", "desperado", 2], ["passive", "magnet", 2]])
	_run.level = 9
	g.set_paused(true)
	g.cards.show_offer([_card("passive", cake, 1, 2), _card("passive", desp, 2, 3), _card("passive", magnet, 2, 3)], "LEVEL 9!", false)
	await _wait(1.0)
	await _shot("01-cards-rungs")
	g.cards.visible = false
	# 02: the common item's last three rungs
	_build([["weapon", "revolver", 3], ["passive", "cake", 5]])
	g.cards.show_offer([_card("passive", cake, 3, 4), _card("passive", cake, 4, 5), _card("passive", cake, 5, 6)], "LEVEL 12!", false)
	await _wait(1.0)
	await _shot("02-cards-common-ladder")
	g.cards.visible = false
	# 03: new items, their rarity's plate and no rung word
	_build([["weapon", "revolver", 3]])
	g.cards.show_offer([_card("passive", cake, 0, 1), _card("passive", desp, 0, 1), _card("passive", magnet, 0, 1)], "LEVEL 2!", false)
	await _wait(1.0)
	await _shot("03-cards-new")
	g.cards.visible = false
	g.set_paused(false)
	# 04: the Build tab with items at every rung, the Cake open on its Evolved rung
	_build([["weapon", "revolver", 3], ["weapon", "boomstick", 2], ["passive", "brawn", 2], ["passive", "cake", 6], ["passive", "desperado", 4],
		["passive", "magnet", 3], ["passive", "siesta", 2], ["passive", "beer", 3], ["passive", "skedaddle", 1], ["passive", "phoenix_feather", 5]])
	_run.level = 14
	g.open_pause()
	g.pause_screen._expanded = "cake"
	g.pause_screen._tab = 0
	g.pause_screen._refresh()
	await _wait(0.8)
	g.pause_screen._scroll.scroll_vertical = 999999
	await _wait(0.4)
	await _shot("04-pause-build")
	g.pause_screen._expanded = ""
	g.pause_screen._refresh()
	g.close_pause()
	await _wait(0.3)
	# 05 / 06: the Collection's pages (a save that has met them, in memory only)
	for p in _reg.passives.values():
		_save.mark_seen("passive", p.id)
	_run.end()
	change_scene_to_file("res://ui/CollectionScreen.tscn")
	await _wait(1.2)
	current_scene._open_page(cake)
	await _wait(0.6)
	await _shot("05-collection-cake")
	current_scene._open_page(magnet)
	await _wait(0.6)
	await _shot("06-collection-magnet")
	if kept != "":
		var fk := FileAccess.open("user://save.json", FileAccess.WRITE)
		fk.store_string(kept)
		fk.close()
	print("p95_passives_shot: done")
	quit()
