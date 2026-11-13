## Pass 147 (lane SHOP): the Store's captures. A sandboxed save (the PC's save is never written) with `gold` coins; the
## Settings changed in memory only. Windowed and bounded (a watchdog quits after 150 s):
##   GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --log-file <abs> --script res://tools/_p147_STORE_shots.gd -- out=<abs dir> [only=store,message,locked,open,inset,settings] [tag=<name>] [gold=1250]
## store.png the Store (store_open on); message.png a price tapped (the "Coming soon" modal); title_locked.png the main menu's tab bar with
## the Store shut (the default); title_open.png with it open; store_inset130.png the Store under a 130 px camera cutout;
## settings_debug.png the Settings screen's debug panel with its "Store" row. `tag` prefixes every file (a second
## resolution's run).
extends SceneTree

const STORE := "res://ui/StoreScreen.tscn"
const TITLE := "res://ui/TitleScreen.tscn"
const SETTINGS := "res://ui/SettingsScreen.tscn"
var _out := "user://p147_store_shots"
var _only: Array = []
var _tag := ""
var _gold := 1250
var _save
var _settings
var _kept: Dictionary = {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = Array(a.substr(5).split(",", false))
		elif a.begins_with("tag="):
			_tag = a.substr(4) + "_"
		elif a.begins_with("gold="):
			_gold = int(a.substr(5))
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(150.0, true, false, true).timeout.connect(func() -> void:
		print("p147_store_shots: watchdog")
		_end(2))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _want(n: String) -> bool:
	return _only.is_empty() or _only.has(n)


func _end(code: int) -> void:
	if _settings:
		for k: String in _kept:
			_settings.set(k, _kept[k])
	if _save:
		_save.end_sandbox()
	quit(code)


func _frames(n: int) -> void:
	for k in range(n):
		await process_frame


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await _frames(3)
	var p := _out.path_join(_tag + name)
	root.get_viewport().get_texture().get_image().save_png(p)
	print("p147_store_shots: ", p)


func _main() -> void:
	_save = root.get_node("Save")
	_settings = root.get_node("Settings")
	_save.begin_sandbox()
	for k in ["debug_modal_buttons", "free_revive_button", "hit_log", "debug_panel", "debug_mode", "store_open", "top_inset"]:
		_kept[k] = _settings.get(k)
	for k in ["debug_modal_buttons", "free_revive_button", "hit_log", "debug_panel", "debug_mode"]:
		_settings.set(k, false)
	_settings.set("top_inset", 0)
	_save.data["gold"] = _gold
	_save.data["consent"] = "no"
	_save.skip_trail_tutorial()
	if _want("locked"):
		_settings.set("store_open", false)
		change_scene_to_file(TITLE)
		await _wait(3.0)
		await _shot("title_locked.png")
	if _want("open"):
		_settings.set("store_open", true)
		change_scene_to_file(TITLE)
		await _wait(3.0)
		await _shot("title_open.png")
	_settings.set("store_open", true)
	if _want("store") or _want("message"):
		change_scene_to_file(STORE)
		await _wait(1.0)
		if _want("store"):
			await _shot("store.png")
		if _want("message"):
			var card: Control = current_scene.call("card_of", "pack_pouch")
			var b: Control = card.get_node("Price") if card else null
			if b:
				b.call("show_held", true)
				await _frames(4)
				b.call("show_held", false)
				b.emit_signal("pressed")
			await _wait(0.7)
			await _shot("message.png")
	if _want("inset"):
		_settings.set("top_inset", 130)
		change_scene_to_file(STORE)
		await _wait(1.0)
		await _shot("store_inset130.png")
		_settings.set("top_inset", 0)
	if _want("settings"):
		_settings.set("debug_mode", true)
		change_scene_to_file(SETTINGS)
		await _wait(1.0)
		var s = current_scene
		var sw: Control = s.find_child("StoreOpen", true, false)
		if sw and s.get("scroll"):
			var sc: ScrollContainer = s.scroll
			var want := int(sw.get_global_rect().get_center().y - sc.get_global_rect().get_center().y)
			sc.scroll_vertical = maxi(want, 0)
			await _frames(4)
		await _shot("settings_debug.png")
		_settings.set("debug_mode", false)
	_end(0)
