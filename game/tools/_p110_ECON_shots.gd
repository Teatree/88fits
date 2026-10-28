## Pass 110 lane ECON scratch capture: the Upgrade board with the new rank prices at their widest (every talent at rank 5,
## the sixth rank's price on each tile: up to 18,000), Nerve's sheet with its two 18,000 buy buttons, and the title's hero
## drawer with the new hero prices. Windowed, bounded (a watchdog quits after WATCHDOG_S), the save kept aside and put
## back (Save.begin_sandbox; tools/godot.sh keeps the PC save aside too).
## Run: bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p110_ECON_shots.gd -- out=<dir>
extends SceneTree

const WATCHDOG_S := 90.0

var _out := "user://p110_econ"
var _save
var _reg


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(WATCHDOG_S, true, false, true).timeout.connect(func():
		print("p110_econ: watchdog, quitting")
		quit(2))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p110_econ: ", name)


func _main() -> void:
	_save = root.get_node("Save")
	_reg = root.get_node("Registry")
	_save.begin_sandbox()
	# every talent at rank 5: each tile shows its sixth rank's price, the widest numbers on the board
	var talents := {}
	var spent := 0
	for td in _reg.talents_list():
		talents[td.id] = {"picks": [0, 1, 0, 1, 0]}
		for k in range(5):
			spent += td.cost_of_rank(k)
	_save.data["talents"] = talents
	_save.data["talent_spent"] = spent
	_save.data["gold"] = 123456
	change_scene_to_file("res://ui/HomesteadScreen.tscn")
	await _wait(1.0)
	await _shot("p110-mirror-rank5")
	current_scene._open(_reg.talent("nerve"))
	await _wait(0.6)
	await _shot("p110-mirror-nerve-sheet")
	current_scene._close(false)
	# a fresh board: the first ranks' prices (unchanged)
	_save.data["talents"] = {}
	_save.data["talent_spent"] = 0
	_save.data["gold"] = 2500
	current_scene._refresh()
	await _wait(0.4)
	await _shot("p110-mirror-fresh")
	# the title's hero drawer: every quest done so every hero but Mira is on sale at his new price
	_save.data["gold"] = 2600
	# nobody bought yet (the Drifter is free), so every hero shows his price
	_save.data["heroes_owned"] = []
	var done: Array = _save.data["quests_done"]
	for q in _reg.quests.values():
		if not done.has(q.id) and str(q.id).begins_with("unlock_") and q.id != "unlock_mira":
			done.append(q.id)
	change_scene_to_file("res://ui/TitleScreen.tscn")
	await _wait(1.2)
	if current_scene.has_method("open_drawer"):
		current_scene.open_drawer()
		await _wait(0.8)
	await _shot("p110-title-drawer")
	_save.end_sandbox()
	quit()
