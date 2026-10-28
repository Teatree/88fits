## Pass 111 lane WANTED capture: the Bounty Board (its three posters, then one picked), the run it starts with the HUD's
## bounty plate, the pause screen's Bounty row, the contract DONE banner, and the Results' BOUNTY panel. Windowed,
## bounded (a watchdog quits after WATCHDOG_S), the save in the sandbox (Save.begin_sandbox; tools/godot.sh keeps the PC
## save aside too). The board is rolled from a seed until it holds a creature poster, so the shots show a front still.
## Run: bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p111_wanted_shots.gd -- out=<dir>
extends SceneTree

const WATCHDOG_S := 120.0

var _out := "user://p111_wanted"
var _save
var _reg
var _run
var WB


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(WATCHDOG_S, true, false, true).timeout.connect(func():
		print("p111_wanted: watchdog, quitting")
		quit(2))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p111_wanted: ", name)


func _main() -> void:
	_save = root.get_node("Save")
	_reg = root.get_node("Registry")
	_run = root.get_node("Run")
	WB = load("res://core/systems/WantedBoard.gd")
	_save.begin_sandbox()
	# a player with a few runs behind him, stage 1 beaten, everything met and seen
	_save.data["totals"]["runs"] = 6
	_save.data["stages_beaten"] = {"red_canyon": [true, false, false]}
	_save.data["last_character"] = "drifter"
	_save.data["last_map"] = "red_canyon"
	for id in _reg.enemies.keys():
		_save.mark_seen("enemy", str(id))
	for id in _reg.weapons.keys():
		_save.mark_seen("weapon", str(id))
	for id in _reg.passives.keys():
		_save.mark_seen("passive", str(id))
	_run.choose_stage(0)
	# a board with a creature poster on it (the seeds tried in order)
	var posters: Array = []
	for s in range(1, 80):
		WB.store()["boards"] = {}
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		posters = WB.board_for("red_canyon", 0, "drifter", rng)
		var types := posters.map(func(c): return str(c["type"]))
		if types.has("kill_enemy") and (types.has("hero_level") or types.has("boss_fast") or types.has("kill_total")):
			break
	change_scene_to_file("res://ui/WantedBoardScreen.tscn")
	await _wait(1.6)
	await _shot("board")
	var pick := 0
	for i in posters.size():
		if str(posters[i]["type"]) == "kill_enemy":
			pick = i
	current_scene._on_poster(pick)
	await _wait(0.5)
	await _shot("board_picked")
	var contract: Dictionary = posters[pick]
	# the run it starts: the instant start (a launch file), the hero untouchable
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"character": "drifter", "weapon": "revolver", "level": 1, "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	current_scene._on_take()
	await _wait(0.35)
	await _shot("board_taken")
	var w := 0.0
	while w < 10.0 and not (current_scene and current_scene.scene_file_path == "res://game/Game.tscn" and current_scene.get("hud") != null):
		await _wait(0.2)
		w += 0.2
	var g = current_scene
	if g == null or g.scene_file_path != "res://game/Game.tscn":
		print("p111_wanted: the run did not start")
		_save.end_sandbox()
		quit(1)
		return
	g.player.god = true
	await _wait(2.5)
	_run.kills_by_enemy[str(contract["target"])] = int(int(contract["n"]) * 0.45)
	var tracker = g.get_node_or_null("WantedRun")
	if tracker:
		tracker.check()
	await _wait(0.3)
	await _shot("hud_plate")
	g.open_pause()
	await _wait(0.6)
	await _shot("pause_bounty")
	g.close_pause()
	await _wait(0.8)
	_run.kills_by_enemy[str(contract["target"])] = int(contract["n"])
	if tracker:
		tracker.check()
	await _wait(0.5)
	await _shot("hud_done")
	g.end_run()
	await _wait(6.5)
	await _shot("results_bounty")
	_save.end_sandbox()
	quit()
