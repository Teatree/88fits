## Pass 141 (lane TRAIL): the one-lane Trail and its unlock nodes proved by eye, on the game's own file with a sandboxed
## save: a new save; the first unlocks bought (UNLOCKED) with the next ones ahead (UNLOCK); a stage node open with the
## dock on it; an outlaw, the skin and Blood Moon ahead in the dark band; a choice and a rails-meeting milestone.
## Windowed and bounded (a watchdog quits after 150 s):
##   GODOT_TIMEOUT=220 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --script res://tools/_p141_TRAIL_shots.gd -- out=<dir> [only=new,first,stage,ahead,meet]
extends SceneTree

const TRAIL := "res://ui/TrailScreen.tscn"
var _out := "user://p141_trail_shots"
var _only: Array = []
var _t0 := 0
var _save
var _trail


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",")
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_watch)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _watch() -> void:
	if Time.get_ticks_msec() - _t0 > 150000:
		print("p141_trail_shots: watchdog")
		_end(2)


func _end(code: int) -> void:
	if _trail:
		_trail.load_from()
	if _save:
		_save.end_sandbox()
	quit(code)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _frames(n: int) -> void:
	for k in range(n):
		await process_frame


func _want(name: String) -> bool:
	return _only.is_empty() or _only.has(name)


func _shot(name: String) -> void:
	await _frames(3)
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p141_trail_shots: ", name)


## Every required node of levels 1..`level` (a choice: its first member).
func _upto(level: int) -> Array:
	var out: Array = []
	for n in _trail.nodes():
		if int(n["level"]) > level or str(n["kind"]) == "optional":
			continue
		if str(n["kind"]) == "choice" and str(_trail.group(str(n["id"]))[0]) != str(n["id"]):
			continue
		out.append(str(n["id"]))
	return out


func _lend(bought: Array, gold: int) -> void:
	_save.data["trail"] = {"bought": bought.duplicate(), "spent": 0, "had": []}
	_save.data["gold"] = gold
	_save.data["heroes_owned"] = []
	_save.data["skins_owned"] = []
	_save.data.erase("board_note")
	for k in ["trail_open", "buy_tapped"]:
		_save.mark_tutorial(k)
	_trail.refresh()


func _open() -> Node:
	change_scene_to_file(TRAIL)
	await _wait(0.5)
	await _frames(30)
	await _wait(0.4)
	return current_scene


func _look(s, l: int, id: String = "") -> void:
	s.scroll.scroll_vertical = int(s._scroll_for(s._row_y(l)))
	await _frames(3)
	if id != "":
		s.select(id)
		await _wait(0.35)


func _node_of(type: String, id: String) -> String:
	return str(_trail.gate(type, id).get("id", ""))


func _main() -> void:
	_save = root.get_node("Save")
	_save.begin_sandbox()
	_trail = load("res://core/systems/Trail.gd")
	var st = root.get_node("Settings")
	for k in ["debug_modal_buttons", "free_revive_button", "hit_log", "debug_panel", "debug_mode"]:
		st.set(k, false)
	_trail.load_from()
	print("p141_trail_shots: %d nodes on %d levels" % [_trail.nodes().size(), _trail.levels()])
	var s
	if _want("new"):
		_lend([], 50)
		s = await _open()
		await _shot("01_new_save")
	if _want("first"):
		_lend(_upto(9), 400)
		s = await _open()
		await _shot("02_first_unlocks_bought")
		var pk := _node_of("passive", "powder_keg")
		await _look(s, 9, pk)
		await _shot("03_dock_unlock_bought")
	if _want("stage"):
		_lend(_upto(25), 2500)
		s = await _open()
		await _shot("04_dust_bowl_open")
	if _want("ahead"):
		_lend(_upto(30), 900)
		s = await _open()
		await _look(s, 33)
		await _shot("05_solenne_ahead")
		await _look(s, 45, _node_of("skin", "astro:AST-B") if _node_of("skin", "astro:AST-B") != "" else _node_of("skin", "astro:AST-D"))
		await _shot("06_skin_and_moon_ahead")
	if _want("meet"):
		_lend(_upto(60), 40000)
		s = await _open()
		await _look(s, 62)
		await _shot("07_choice_and_meeting")
	_end(0)
