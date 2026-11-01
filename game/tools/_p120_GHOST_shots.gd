## Pass 120 lane GHOST capture: the Undertaker's Shovel's floating ghost circling its grave and firing ghost bolts, at a
## low power (one bolt a volley) and a high one (six), several frames each so its front and its back both show. Windowed,
## bounded (WATCHDOG_S), the save in the sandbox. The hero holds no weapon (only the ghost's bolts fly) and is a god.
## Run: GODOT_TIMEOUT=300 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p120_GHOST_shots.gd -- out=<dir> [only=low|high] [frames=8] [gap=0.12] (gap: seconds of the run's clock after a volley)
extends SceneTree

const WATCHDOG_S := 200.0
## Graveyard's phases (its enum, by value)
const FIGHT := 3
const VANISH := 4
var _out := "user://p120_ghost"
var _only := ""
var _frames := 8
var _gap := 0.12
var _save
var _run


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5)
		elif a.begins_with("frames="):
			_frames = int(a.substr(7))
		elif a.begins_with("gap="):
			_gap = float(a.substr(4))
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(WATCHDOG_S, true, false, true).timeout.connect(func():
		print("p120_ghost: watchdog, quitting")
		quit(2))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


## `s` seconds of the run's own clock (a capture's PNG costs frames: wall time would race ahead of the game)
func _wait_game(s: float) -> void:
	var t0: float = float(_run.get("elapsed"))
	var guard := 0
	while guard < 2000 and float(_run.get("elapsed")) - t0 < s:
		await process_frame
		guard += 1


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p120_ghost: ", name)


func _main() -> void:
	_save = root.get_node("Save")
	_run = root.get_node("Run")
	_save.begin_sandbox()
	if _only == "" or _only == "low":
		await _scene("low", 1.0)
	if _only == "" or _only == "high":
		await _scene("high", 25.0)
	quit(0)


## A run of the Drifter with no spawning; the Game scene once it stands.
func _launch() -> Node:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"character": "drifter", "weapon": "revolver", "level": 3, "map": "red_canyon",
		"map_seed": 7, "spawn": false, "analytics": false, "stage": 1}))
	f.close()
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	var g = current_scene
	if g != null and g.get("player") != null:
		g.player.god = true
	return g


## Skeletons at `spots` round the hero (offsets), up out of the sand, tough.
func _crowd(g: Node, spots: Array, hp_mult: float) -> Array:
	var out: Array = []
	var at0: Vector3 = g.player.global_position
	for o: Vector3 in spots:
		var p: Vector3 = at0 + o
		p.y = g.map.height_at(p.x, p.z) if g.map else 0.0
		var i: int = g.enemies.spawn("skeleton", p, null, 1.0, hp_mult)
		if i >= 0:
			out.append(i)
	return out


func _scene(tag: String, power: float) -> void:
	var g = await _launch()
	if g == null:
		return
	# only the ghost's bolts fly: the hero holds nothing
	_run.debug_clear_items()
	_run.add_or_level_passive("undertakers_shovel")
	_run.rebuild_sheets()
	# by name only through the scene (a tool compiles before the autoloads: naming Graveyard here would break it)
	var gy = g._graveyard()
	gy.power_override = power
	var here: Vector3 = g.player.global_position
	gy.dig(here + Vector3(0.0, 0, -3.2))
	var spots: Array = []
	for k in range(9):
		var a := TAU * float(k) / 9.0 + 0.3
		spots.append(Vector3(cos(a) * 6.5, 0, -3.2 + sin(a) * 5.5))
	# nothing but the capture's own crowd
	g.enemies.kill_all(false)
	await _crowd(g, spots, 400.0)
	var guard := 0
	while guard < 900 and not gy.graves.is_empty() and int((gy.graves[0] as Dictionary)["phase"]) < FIGHT:
		await process_frame
		guard += 1
	# the paper turn between its front and its back, caught half-way (it narrows to an edge)
	var guard3 := 0
	while guard3 < 900 and not gy.graves.is_empty():
		var tr: float = float((gy.graves[0] as Dictionary).get("turn", -1.0))
		if tr >= 0.3 and tr < 0.48:
			await _shot("%s_turn" % tag)
			break
		await process_frame
		guard3 += 1
	# frames caught just after a volley (its bolts in the air), a little later each time, so the ghost is shown all round
	# its circle, front and back
	for k in range(_frames):
		var v0: int = int(gy.volleys)
		var guard2 := 0
		while guard2 < 600 and int(gy.volleys) == v0 and not gy.graves.is_empty():
			await process_frame
			guard2 += 1
		if gy.graves.is_empty() or int((gy.graves[0] as Dictionary)["phase"]) > FIGHT:
			break
		await _wait_game(_gap + 0.06 * float(k % 3))
		var gr: Dictionary = gy.graves[0] if not gy.graves.is_empty() else {}
		var face := int(gr.get("face", 0))
		await _shot("%s_%02d_%s" % [tag, k, "front" if face > 0 else "back"])
		print("p120_ghost:   phase %d t %.2f theta %.2f rad %.2f face %d turn %.2f | volleys %d in flight %d drawn %d | clock %.2f fps %.0f" % [
			int(gr.get("phase", -1)), float(gr.get("t", 0.0)), float(gr.get("theta", 0.0)), float(gr.get("rad", 0.0)), face,
			float(gr.get("turn", -1.0)), gy.volleys, gy.bolts.count, gy.bolts.drawn(), float(_run.get("elapsed")), Engine.get_frames_per_second()])
	print("p120_ghost: %s power %.1f: volleys %d bolts %d hits %d fizzles %d dealt %.0f" % [tag, power, gy.volleys, gy.shots,
		gy.bolts.hits, gy.bolts.fizzles, gy.bolts.dealt])
