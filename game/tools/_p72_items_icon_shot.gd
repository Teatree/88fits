## Pass 72, lane ITEMS: Rebound's new icon where the game shows it: the basketball's path offer (On Fire, Alley-Oop,
## Rebound) as Fadeaway, and the HUD with the build. A watchdog quits after `limit` seconds; every wait is bounded.
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game --script res://tools/_p72_items_icon_shot.gd -- out=<dir> [limit=90]
extends SceneTree

var _out := "user://p72_icon"
var _limit := 90.0
var _run
var _reg
var _save
var g


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("limit="):
			_limit = float(a.substr(6))
	DirAccess.make_dir_recursive_absolute(_out)
	process_frame.connect(_main, CONNECT_ONE_SHOT)
	create_timer(_limit, true, false, true).timeout.connect(_watchdog)


func _watchdog() -> void:
	print("p72_icon: WATCHDOG")
	if _save != null and _save.has_method("end_sandbox"):
		_save.end_sandbox()
	quit(3)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p72_icon: ", name)


func _main() -> void:
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save = root.get_node("Save")
	_save.begin_sandbox()
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "basketball", "level": 3, "character": "fadeaway", "map": "red_canyon", "map_seed": 7}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	await _wait(2.0)
	_run.debug_clear_items()
	_run.debug_set_item("weapon", "basketball", 3)
	_run.debug_set_item("mutation", "rebound", 1)
	_run.build_changed.emit()
	await _wait(0.6)
	await _shot("hud_with_rebound")
	var offer: Array = []
	for id in ["on_fire", "alley_oop", "rebound"]:
		var m = _reg.mutation(id)
		offer.append({"type": "mutation", "id": m.id, "def": m, "level_from": 0, "level_to": 1, "is_new": true, "weight": 1.0})
	g.set_paused(true)
	g.cards.show_offer(offer, "PATH · BASKETBALL", false, true)
	var waited := 0.0
	while waited < 5.0 and g.cards.reel_running():
		await _wait(0.1)
		waited += 0.1
	await _wait(1.0)
	await _shot("path_offer")
	_save.end_sandbox()
	quit(0)
