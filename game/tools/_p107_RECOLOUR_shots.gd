## Pass 107 lane RECOLOUR (scratch): each creature's played look beside its two new recolour looks, in Sundown's and
## Nightfall's look (StageLook.show_stage), in the debug arena.
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game --script res://tools/_p107_RECOLOUR_shots.gd -- out=<dir> [only=<id>] [zoom=0.6]  (one creature a run: the bodies of the one before stay on the ground)
## Columns left to right: the played look, the first new look, the second; two of each (above and below the hero).
## Bounded: a 120 s watchdog and an 8,000-frame cap quit with code 2 whatever is waiting. The PC save is put back.
extends SceneTree

const SETS := [
	["bull_beetle", ["BB-C", "BB-E", "BB-F"]],
	["fire_ant", ["ANT-E", "ANT-G", "ANT-H"]],
	["lesser_scorpion", ["LS-B", "LS-D", "LS-E"]],
]

var _out := "user://p107_recolour"
var _zoom := 0.6
var _only := ""
var _frames := 0
var _run
var _save
var _keep: Dictionary = {}
var g


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5)
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(120.0, true, false, true).timeout.connect(_bail.bind("watchdog 120 s"))
	process_frame.connect(_count)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _count() -> void:
	_frames += 1
	if _frames > 8000:
		_bail("frame cap 8000")


func _bail(why: String) -> void:
	print("p107_recolour: stopped: ", why)
	if _save != null and not _keep.is_empty():
		_save.data = _keep
	quit(2)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p107_recolour: ", name)


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	_keep = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "peashooter", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	if _zoom > 0.0 and g.camera:
		g.camera.zoom_override = _zoom
	await _wait(4.0)
	for s in SETS:
		if _only == "" or _only == str(s[0]):
			await _one(str(s[0]), s[1])
	_save.data = _keep
	quit(0)


func _look(s: int) -> void:
	var sl = load("res://core/systems/StageLook.gd").of(g)
	sl.show_stage(s, 0.0)


func _one(id: String, codes: Array) -> void:
	_run.debug_clear_items()
	_run.build_changed.emit()
	var em = g.enemies
	em.kill_all(false)
	_look(0)
	await _wait(0.4)
	var here: Vector3 = g.player.global_position
	# no growing out of the ground and no dust: the looks stand whole at once
	em.spawn_rise_s = 0.0
	em.spawn_rise_big_s = 0.0
	em.spawn_rise_dust = 0.0
	for c in range(codes.size()):
		var x := -2.6 + 2.6 * float(c)
		em.spawn(id, here + Vector3(x, 0, -3.2), null, 1.0, 100.0, str(codes[c]))
		em.spawn(id, here + Vector3(x, 0, 2.0), null, 1.0, 100.0, str(codes[c]))
	em._rebuild_grid()
	await _wait(0.5)
	paused = true
	await _shot(id + "_sundown")
	_look(1)
	await _wait(0.1)
	await _shot(id + "_nightfall")
	_look(0)
	paused = false
	em.kill_all(true)
	await _wait(0.25)
	paused = true
	await _shot(id + "_die_sundown")
	_look(1)
	await _wait(0.1)
	await _shot(id + "_die_nightfall")
	_look(0)
	paused = false
	await _wait(0.8)
