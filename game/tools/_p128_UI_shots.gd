## Pass 128 (lane UI): the board screens' scroll against their sheet, proved by eye. Each board screen at rest; the Outlaws
## screen also scrolled by 40, 90 and 160 px (and any other screen in `scrolls=`). `before=1` lays every scroll as it was
## before pass 128 (board_room() over the board, whatever the sheet), so the same run makes the "before" pictures.
## `open_on=<outlaw id>` opens the Outlaws screen on that outlaw (HeroesScreen.open_on, job 4).
## Windowed, bounded (a watchdog quits after 150 s; the save is sandboxed):
##   GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --script res://tools/_p128_UI_shots.gd -- out=<dir> [before=1] [only=heroes,mirror,settings,stages,collection,shop,results]
extends SceneTree

const SCREENS := [["heroes", "res://ui/HeroesScreen.tscn"], ["mirror", "res://ui/HomesteadScreen.tscn"],
	["settings", "res://ui/SettingsScreen.tscn"], ["stages", "res://ui/StagesScreen.tscn"],
	["collection", "res://ui/CollectionScreen.tscn"], ["shop", "res://ui/ShopScreen.tscn"], ["results", "res://ui/ResultsScreen.tscn"]]
## how far each screen is scrolled for its extra shots (px)
const SCROLLS := {"heroes": [40, 90, 160], "results": [60], "settings": [40]}
var _out := "user://p128_ui_shots"
var _only: Array = []
var _before := false
var _open_on := ""
var _t0 := 0
var _save


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",")
		elif a == "before=1":
			_before = true
		elif a.begins_with("open_on="):
			_open_on = a.substr(8)
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_watch)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _watch() -> void:
	if Time.get_ticks_msec() - _t0 > 150000:
		print("p128_ui_shots: watchdog")
		_end(2)


func _end(code: int) -> void:
	if _save:
		_save.end_sandbox()
	quit(code)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p128_ui_shots: ", name)


## The scroll as it lay before pass 128: board_room() over the board, the margin that much.
func _lay_before(s) -> void:
	if s.get("scroll") == null or s.get("margin") == null or not s.has_method("board_room"):
		return
	var room: float = s.board_room()
	if int(s.margin.get_theme_constant("margin_top")) == int(s.board_top() - s.scroll_top()):
		s.scroll.offset_top = s.board_top() - room + load("res://ui/wanted/W.gd").safe_top()
		s.margin.add_theme_constant_override("margin_top", int(room))


func _main() -> void:
	_save = root.get_node("Save")
	_save.begin_sandbox()
	var st = root.get_node("Settings")
	for k in ["debug_modal_buttons", "free_revive_button", "hit_log", "debug_panel", "debug_mode"]:
		st.set(k, false)
	var run = root.get_node("Run")
	var tag := "before" if _before else "after"
	for row: Array in SCREENS:
		var key: String = row[0]
		if not _only.is_empty() and not _only.has(key):
			continue
		if key == "results":
			var story = load("res://tools/results_story.gd")
			story.fill(run, _save, load("res://core/systems/QuestTracker.gd"), false)
		if key == "heroes" and _open_on != "":
			load("res://ui/HeroesScreen.gd").set("open_on", _open_on)
		change_scene_to_file(str(row[1]))
		# a slow load eats the timer: frames as well, so the board's slide-in (ScreenBase._enter, 0.25 s) is over
		await _wait(0.6)
		for k in range(45):
			await process_frame
		await _wait(0.5)
		var s = current_scene
		if s == null:
			print("p128_ui_shots: no scene for ", key)
			continue
		if s.has_method("skip_all"):
			s.skip_all()
			await _wait(2.2)
		if _before:
			_lay_before(s)
			await _wait(0.2)
		if s.get("scroll") != null:
			s.scroll.scroll_vertical = 0
			await _wait(0.2)
			print("p128_ui_shots: %s scroll top %.0f, sheet top %s, content top %.0f" % [key, s.scroll.offset_top,
				str(s.board_sheet_node.offset_top) if s.get("board_sheet_node") else "-", s.content.get_global_rect().position.y])
		await _shot("%s_%s_rest" % [key, tag])
		for px: int in SCROLLS.get(key, []):
			if s.get("scroll") == null:
				break
			s.scroll.scroll_vertical = px
			await _wait(0.25)
			await _shot("%s_%s_scroll%d" % [key, tag, int(s.scroll.scroll_vertical)])
	# only=comeswith (asked for by name): on a save that owns no bought outlaw, the Collection's weapons grid, the Big
	# Mouth's locked page ("Comes with May") and the Outlaws screen as a tap on that line opens it
	if _only.has("comeswith"):
		_save.data["heroes_owned"] = []
		var reg = root.get_node("Registry")
		change_scene_to_file("res://ui/CollectionScreen.tscn")
		await _wait(0.6)
		for k in range(45):
			await process_frame
		await _wait(0.5)
		await _shot("comeswith_collection_grid")
		current_scene._open_locked(reg.weapon("big_mouth"))
		await _wait(0.5)
		await _shot("comeswith_collection_page")
		var tap = current_scene.content.find_child("ComesWith", true, false)
		print("p128_ui_shots: the line reads '%s'" % (str(tap.find_child("Words", true, false).text) if tap else "-"))
		if tap:
			tap.emit_signal("pressed")
		await _wait(1.2)
		for k in range(45):
			await process_frame
		await _wait(0.6)
		print("p128_ui_shots: the tap opened %s on %s" % [current_scene.scene_file_path, str(current_scene.get("shown").id) if current_scene.get("shown") else "-"])
		await _shot("comeswith_outlaws_on_may")
	print("p128_ui_shots: done")
	_end(0)
