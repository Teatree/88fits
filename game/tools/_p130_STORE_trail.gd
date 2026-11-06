## Pass 130: the Trail on the game's own file, for the Google Play screenshot (docs/store/06_trail.png): a sandboxed save
## that has every required node up to `level` bought and `gold` coins, the Trail screen scrolled so level `look` is in
## the middle with node `node` chosen (its dock open). Windowed and bounded (a watchdog quits after 120 s):
##   GODOT_TIMEOUT=200 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --script res://tools/_p130_STORE_trail.gd -- out=<dir> shots=8:9:,15:16:,27:29:   (level:look:node[, ...]) [gold=4200]
extends SceneTree

const TRAIL := "res://ui/TrailScreen.tscn"
const TRAIL_ARG := preload("res://tools/trail_arg.gd")
var _out := "user://p130_store_trail"
var _shots: Array = ["15:16:"]
var _gold := 4200
var _save
var _trail


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("shots="):
			_shots = Array(a.substr(6).split(",", false))
		elif a.begins_with("gold="):
			_gold = int(a.substr(5))
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(120.0, true, false, true).timeout.connect(func() -> void:
		print("p130_store_trail: watchdog")
		_end(2))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _end(code: int) -> void:
	if _save:
		_save.end_sandbox()
	quit(code)


func _frames(n: int) -> void:
	for k in range(n):
		await process_frame


func _main() -> void:
	_save = root.get_node("Save")
	_save.begin_sandbox()
	_trail = load("res://core/systems/Trail.gd")
	var st = root.get_node("Settings")
	for k in ["debug_modal_buttons", "free_revive_button", "hit_log", "debug_panel", "debug_mode"]:
		st.set(k, false)
	for shot: String in _shots:
		var p := shot.split(":")
		var level := int(p[0])
		var look := int(p[1]) if p.size() > 1 and p[1] != "" else level + 1
		var node := p[2] if p.size() > 2 else ""
		var info: Dictionary = TRAIL_ARG.apply(_save, str(level))
		_save.data["gold"] = _gold
		_save.data.erase("board_note")
		_trail.refresh()
		change_scene_to_file(TRAIL)
		await create_timer(0.5, true, false, true).timeout
		await _frames(30)
		await create_timer(0.4, true, false, true).timeout
		var s = current_scene
		s.scroll.scroll_vertical = int(s._scroll_for(s._row_y(look)))
		await _frames(3)
		if node != "":
			s.select(node)
			await create_timer(0.4, true, false, true).timeout
		await _frames(3)
		var name := "trail_L%d_at%d%s.png" % [level, look, ("_" + node) if node != "" else ""]
		root.get_viewport().get_texture().get_image().save_png(_out.path_join(name))
		print("p130_store_trail: %s (%s)" % [name, str(info.get("label", info))])
	_end(0)
