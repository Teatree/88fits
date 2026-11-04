## Pass 112 lane WANTED capture: the floating Wanted posters over a real run, after the spawn beam's landing: as they
## hang and sway (two moments), a poster taken (the stamp, the flight into the HUD's bounty plate, the plate after), and a
## second run's "No bounty" (the posters blowing away). Windowed, bounded (a watchdog quits after WATCHDOG_S), the save
## in the sandbox (Save.begin_sandbox; tools/godot.sh keeps the PC save aside too).
## Run: bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p112_wanted_shots.gd -- out=<dir>
extends SceneTree

const WATCHDOG_S := 120.0

var _out := "user://p112_wanted"
var _save
var _reg


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(WATCHDOG_S, true, false, true).timeout.connect(func():
		print("p112_wanted: watchdog, quitting")
		quit(2))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p112_wanted: ", name)


## A real run with the spawn beam; returns the Game once the posters hang (null when they never come).
func _run_to_posters(seed: int) -> Node:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"character": "drifter", "weapon": "revolver", "level": 1, "map": "red_canyon", "map_seed": seed,
		"spawn": true, "analytics": false}))
	f.close()
	change_scene_to_file("res://game/Game.tscn")
	var w := 0.0
	while w < 12.0 and not (current_scene and current_scene.get("bounty_posters") != null and current_scene.bounty_posters.visible):
		if current_scene and current_scene.get("player") != null:
			current_scene.player.god = true
		await _wait(0.1)
		w += 0.1
	if current_scene == null or current_scene.get("bounty_posters") == null or not current_scene.bounty_posters.visible:
		return null
	return current_scene


func _main() -> void:
	_save = root.get_node("Save")
	_reg = root.get_node("Registry")
	_save.begin_sandbox()
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
	root.get_node("Run").choose_stage(0)
	# a board with a creature on it (the board kept in the save is what the run shows)
	var WB = load("res://core/systems/WantedBoard.gd")
	for s in range(1, 80):
		WB.store()["boards"] = {}
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var posters: Array = WB.board_for("red_canyon", 0, "drifter", rng)
		var types := posters.map(func(c): return str(c["type"]))
		if types.has("kill_enemy") and (types.has("hero_level") or types.has("boss_fast") or types.has("kill_total")):
			break
	var g = await _run_to_posters(7)
	if g == null:
		print("p112_wanted: the posters never came")
		_save.end_sandbox()
		quit(1)
		return
	await _wait(0.25)
	await _shot("posters_drop")
	await _wait(0.9)
	await _shot("posters_hang")
	await _wait(1.1)
	await _shot("posters_sway")
	var bp = g.bounty_posters
	var pick := 0
	for i in (bp.posters as Array).size():
		if str(bp.posters[i]["type"]) == "kill_enemy":
			pick = i
	var t0 := Time.get_ticks_msec()
	bp.closed.connect(func(_c): print("p112_wanted: closed after %d ms" % (Time.get_ticks_msec() - t0)))
	bp.choose(pick)
	var card: Control = bp.cards()[pick]
	await _wait(0.3)
	await _shot("taken_stamp")
	# the flight, caught half way (polled frame by frame, so a slow capture frame cannot skip it)
	var w := 0.0
	while w < 3.0 and is_instance_valid(card) and card.scale.x > 0.55:
		await process_frame
		w += root.get_process_delta_time()
	if is_instance_valid(card):
		await _shot("taken_flight")
	w = 0.0
	while w < 4.0 and bp.visible:
		await _wait(0.05)
		w += 0.05
	await _wait(0.6)
	await _shot("taken_plate")
	# a second run: No bounty
	g = await _run_to_posters(9)
	if g:
		await _wait(1.0)
		g.bounty_posters.choose(-1)
		await _wait(0.22)
		await _shot("none_blow")
		await _wait(1.0)
		await _shot("none_after")
	_save.end_sandbox()
	quit()
