extends SceneTree
## Pass 88 lane MIRROR scratch capture: the Upgrade board in its new order with the Stakes, the refund's toasts, the
## Stakes sheet. Args: out=<dir>. Sandboxed save; a 60 s watchdog.

var _out := "user://p88_mirror"
var _save
var _reg


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(60.0, true, false, true).timeout.connect(func(): print("board: watchdog"); quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("board: ", name)


func _main() -> void:
	_save = root.get_node("Save")
	_reg = root.get_node("Registry")
	_save.begin_sandbox()
	_save.data["gold"] = 12345
	_save.data["talents"] = {"grit": {"picks": [0, 1]}, "spite": {"picks": [0]}}
	_save.data["talent_spent"] = 1360
	_save.data["board_note"] = {"kind": "stakes_refund", "gold": 2900, "ranks": 3}
	change_scene_to_file("res://ui/HomesteadScreen.tscn")
	await _wait(0.35)
	await _shot("01-board-toast")
	await _wait(0.6)
	await _shot("02-board-toast-2")
	await _wait(2.0)
	await _shot("03-board")
	var sc = current_scene
	var scroll: ScrollContainer = sc.find_child("*Scroll*", true, false) as ScrollContainer
	if scroll:
		scroll.scroll_vertical = 2000
	await _wait(0.4)
	await _shot("04-board-foot")
	sc._open(_reg.talent("spite"))
	await _wait(0.6)
	await _shot("05-stakes-sheet")
	quit()
