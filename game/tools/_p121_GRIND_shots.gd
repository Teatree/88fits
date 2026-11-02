## Pass 121 lane GRIND capture: the Grindstone's show (ui/GrindMoment.gd) frozen at its beats, a level-up (the Boomstick 2
## to 3) and an evolution (the Revolver into the Golden Revolver), then the gate it closes into. The show's own clock is
## stopped and stepped with seek() so every frame lands on its beat. Windowed, bounded (WATCHDOG_S, frame caps), the save
## in the sandbox; a few skeletons stand round the hero so the world shows under the dusk.
## Run: GODOT_TIMEOUT=300 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p121_GRIND_shots.gd -- out=<dir> [only=level|evolve]
extends SceneTree

const WATCHDOG_S := 220.0
## the beats captured (seconds into the show) for each case
const LEVEL_AT := [0.16, 0.42, 0.75, 1.15, 1.55, 1.86, 2.05, 2.12, 2.3, 2.75]
const EVOLVE_AT := [0.75, 1.4, 1.86, 2.1, 2.3, 2.42, 2.5, 2.75, 3.25]
var _out := "user://p121_grind"
var _only := ""
var _save
var _run


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5)
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(WATCHDOG_S, true, false, true).timeout.connect(func():
		print("p121_grind: watchdog, quitting")
		quit(2))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p121_grind: ", name)


func _main() -> void:
	_save = root.get_node("Save")
	_run = root.get_node("Run")
	_save.begin_sandbox()
	if _only == "" or _only == "level":
		await _scene("level")
	if _only == "" or _only == "evolve":
		await _scene("evolve")
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


func _scene(tag: String) -> void:
	var g = await _launch()
	if g == null:
		return
	var reg = root.get_node("Registry")
	g.enemies.kill_all(false)
	var at0: Vector3 = g.player.global_position
	for k in range(7):
		var a := TAU * float(k) / 7.0 + 0.4
		var p: Vector3 = at0 + Vector3(cos(a) * 6.0, 0, sin(a) * 5.0)
		p.y = g.map.height_at(p.x, p.z) if g.map else 0.0
		g.enemies.spawn("skeleton", p, null, 1.0, 400.0)
	if tag == "level":
		# the Boomstick at 2 is the weakest beside the Revolver at 3
		var boom = _run.add_weapon(reg.weapon("boomstick"), 2)
		print("p121_grind: boomstick ", boom.level if boom else -1)
	else:
		var rev = _run.weapon_instance("revolver")
		while rev.level < rev.def.max_level:
			_run.level_weapon("revolver")
		for m in reg.mutations_of("revolver"):
			_run.add_mutation(m.id, true)
	await _wait(0.6)
	_run.add_or_level_passive("grindstone")
	var guard := 0
	while guard < 120 and (g.get("grind_moment") == null or not bool(g.grind_moment.playing)):
		await process_frame
		guard += 1
	var gm = g.get("grind_moment")
	if gm == null or not bool(gm.playing):
		print("p121_grind: the show did not open (%s)" % tag)
		return
	# the show's own clock stopped: every frame on its beat
	gm.set_process(false)
	print("p121_grind: %s beats %s" % [tag, str(gm.beats())])
	var list: Array = LEVEL_AT if tag == "level" else EVOLVE_AT
	for t: float in list:
		gm.seek(t)
		await _shot("%s_%04d" % [tag, int(round(t * 1000.0))])
	# the end: the gate, the plate flying into the weapon's slot
	gm.set_process(true)
	gm.skip()
	await process_frame
	await _wait(0.18)
	await _shot("%s_gate" % tag)
	if g.resume_gate.visible:
		g.resume_gate.tap()
	await _wait(0.3)
