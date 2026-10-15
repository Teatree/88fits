## Pass 81 (lane PROD): the production build from boot to a run, in the STAGING copy with the production switch forced
## (exported templates take no --script and no scene on the command line, so tools/prod_probe.py can only time the
## exported exe's cold start to the title; this is the same scripts and the same pruned content, played):
##   godot --headless --fixed-fps 60 --path tools/dl/prod/stage/game --script res://tools/prod_run_check.gd [-- seconds=12]
## 1. a tool's launch file asking for the debug arena with a hidden hero is planted in user://, and Run.arena_next is set,
##    as a leftover would be;
## 2. Boot -> the title: the ARENA button hidden; Settings: twelve taps on the hints switch leave the debug mode off,
##    holding the version line 2.5 s opens no developer menu, and the developer menu itself goes straight back;
## 3. the Game: a real run (not the arena, the save's hero, the launch file ignored and left where it was), played
##    `seconds`; F1 opens no debug panel; creatures came.
## Prints "prod_run_check: OK ..." (exit 0) or "prod_run_check: FAIL ..." (exit 1); a watchdog fails it after 240 s.
extends SceneTree

const TITLE := "res://ui/TitleScreen.tscn"
const SETTINGS := "res://ui/SettingsScreen.tscn"
const DEVMENU := "res://ui/DevMenu.tscn"
const GAME := "res://game/Game.tscn"

var _seconds := 12.0
var _phase := "boot"
var _t := 0.0
var _wall0 := 0
var _fails: Array = []
var _notes: Array = []
var _game: Node
var _played_from := -1.0
var _held_since := -1.0


func _init() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("seconds="):
			_seconds = float(a.trim_prefix("seconds="))
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _fail(s: String) -> void:
	_fails.append(s)
	print("prod_run_check: FAIL " + s)


func _start() -> void:
	_wall0 = Time.get_ticks_msec()
	var settings: Node = root.get_node("Settings")
	settings.call("force_prod", true)
	root.get_node("Save").call("begin_sandbox")
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"arena": true, "character": "dad", "weapon": "peashooter", "spawn": false}))
	f.close()
	root.get_node("Run").set("arena_next", true)
	change_scene_to_file("res://ui/Boot.tscn")
	process_frame.connect(_tick)


func _scene_path() -> String:
	return current_scene.scene_file_path if current_scene else ""


func _tick() -> void:
	var dt := 1.0 / 60.0
	_t += dt
	if Time.get_ticks_msec() - _wall0 > 240000:
		_fail("timed out in phase %s" % _phase)
		_finish()
		return
	var settings: Node = root.get_node("Settings")
	match _phase:
		"boot":
			if _scene_path() == TITLE and _t > 1.0:
				var arena := current_scene.find_child("ArenaButton", true, false)
				if arena == null:
					_fail("the title has no ArenaButton to check")
				elif (arena as Control).visible:
					_fail("the title shows the ARENA button")
				_notes.append("title at %.1f s" % _t)
				change_scene_to_file(SETTINGS)
				_phase = "settings"
				_t = 0.0
			elif _t > 60.0:
				_fail("no title after 60 s (scene %s)" % _scene_path())
				_finish()
		"settings":
			if _scene_path() == SETTINGS and _t > 0.5:
				for i in 12:
					current_scene.call("_count_hint_tap")
				if bool(settings.get("debug_mode")):
					_fail("twelve taps on the hints switch turned the debug mode on")
				var down := InputEventScreenTouch.new()
				down.pressed = true
				down.position = Vector2(540, 1850)
				current_scene.call("_on_version_input", down)
				_held_since = _t
				_phase = "hold"
		"hold":
			if _t - _held_since > 2.5:
				if _scene_path() != SETTINGS:
					_fail("holding the version line left Settings for %s" % _scene_path())
				change_scene_to_file(DEVMENU)
				_phase = "devmenu"
				_t = 0.0
		"devmenu":
			if _t > 2.0:
				if _scene_path() == DEVMENU:
					_fail("the developer menu stayed open")
				change_scene_to_file(GAME)
				_phase = "game"
				_t = 0.0
		"game":
			if _scene_path() == GAME:
				_game = current_scene
				var run: Node = root.get_node("Run")
				if bool(run.get("arena")) or _game.get("arena_panel") != null:
					_fail("the game opened the debug arena")
				var ch = run.get("character")
				if ch == null or str(ch.id) == "dad":
					_fail("the run plays %s (the launch file's hidden hero?)" % (str(ch.id) if ch else "nobody"))
				if not FileAccess.file_exists("user://debug_launch.json"):
					_fail("the launch file was read and removed")
				if _game.has_method("spawn_hurry"):
					_game.call("spawn_hurry")
				_phase = "play"
				_t = 0.0
			elif _t > 30.0:
				_fail("no game after 30 s")
				_finish()
		"play":
			if bool(_game.get("_run_started")) and _played_from < 0.0:
				_played_from = _t
				var key := InputEventKey.new()
				key.keycode = KEY_F1
				key.pressed = true
				_game.call("_unhandled_input", key)
				var dp = _game.get("debug_panel")
				if dp != null and (dp as Control).visible:
					_fail("F1 opened the debug panel")
			if _played_from >= 0.0 and _t - _played_from >= _seconds:
				var run: Node = root.get_node("Run")
				var en = _game.get("enemies")
				var alive := int(en.call("alive_count")) if en != null and en.has_method("alive_count") else -1
				_notes.append("played %.0f s, clock %.1f s, level %d, creatures alive %d" % [_t - _played_from,
					float(run.get("elapsed")), int(run.get("level")), alive])
				if float(run.get("elapsed")) < _seconds * 0.5:
					_fail("the run's clock stood still (%.1f s)" % float(run.get("elapsed")))
				_finish()
			elif _t > _seconds + 40.0:
				_fail("the run never started (no landing after %.0f s)" % _t)
				_finish()


func _finish() -> void:
	_phase = "done"
	if FileAccess.file_exists("user://debug_launch.json"):
		DirAccess.remove_absolute("user://debug_launch.json")
	if _fails.is_empty():
		print("prod_run_check: OK prod forced, %s" % ", ".join(_notes))
		quit(0)
	else:
		print("prod_run_check: FAIL %d problems (%s)" % [_fails.size(), ", ".join(_notes)])
		quit(1)
