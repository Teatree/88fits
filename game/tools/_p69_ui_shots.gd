## Pass 69, lane UI: the title's hero drawer, a locked hero, a buyable hero and the buy question, captured windowed:
## godot --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p69_ui_shots.gd -- out=<dir> [inset=130] [only=a,b] [style=live|painted]
## The save is a sandbox (nothing reaches the disk); godot.sh keeps the PC save aside as well.
extends SceneTree

var _out := "user://p69_ui_shots"
var _inset := -1
var _only: Array = []
var _style := "live"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("inset="):
			_inset = int(a.substr(6))
		elif a.begins_with("only="):
			_only = a.substr(5).split(",")
		elif a.begins_with("style="):
			_style = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _want(n: String) -> bool:
	return _only.is_empty() or _only.has(n)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var tag := ("_inset%d" % _inset) if _inset >= 0 else ""
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + tag + ".png"))
	print("p69_ui_shots: ", name + tag)


func _title() -> Node:
	change_scene_to_file("res://ui/TitleScreen.tscn")
	await _wait(1.6)
	return current_scene


func _show(t: Node, id: String) -> void:
	for i in (t._heroes as Array).size():
		if str((t._heroes[i] as Resource).get("id")) == id:
			t._index = i
			t._show_hero(1)
			t._place()
	await _wait(0.9)


func _main() -> void:
	var save = root.get_node("Save")
	var st = root.get_node("Settings")
	save.begin_sandbox()
	if _inset >= 0:
		st.top_inset = _inset
	st.menu_style = _style
	save.data["gold"] = 640
	save.data["last_character"] = "drifter"
	save.data["heroes_owned"] = []
	var qd: Array = save.data["quests_done"]
	# Calavera's requirement met (the Tumbleweed King killed), the others not
	if not qd.has("unlock_calavera"):
		qd.append("unlock_calavera")
	if not save.data["once"].has("boss_red_canyon_1"):
		save.data["once"].append("boss_red_canyon_1")
	var t: Node = await _title()
	if _want("base"):
		await _shot("p69_title_drifter")
	if _want("drawer") and t.has_method("open_drawer"):
		t.open_drawer()
		await _wait(0.6)
		await _shot("p69_title_drawer_open")
		t.close_drawer()
		await _wait(0.4)
	if _want("locked"):
		await _show(t, "ironwood")
		await _shot("p69_title_locked_ironwood")
		await _show(t, "mira")
		await _shot("p69_title_locked_mira")
	if _want("buyable"):
		await _show(t, "fadeaway")
		await _shot("p69_title_buyable_fadeaway")
		await _show(t, "calavera")
		await _shot("p69_title_buyable_calavera")
		if t.has_method("ask_buy"):
			t.ask_buy()
			await _wait(0.6)
			await _shot("p69_title_buy_confirm")
	if _want("short"):
		save.data["gold"] = 20
		t = await _title()
		await _show(t, "fadeaway")
		await _shot("p69_title_buyable_short")
	if _want("sheet"):
		await _show(t, "ironwood")
		t.open_sheet()
		await _wait(0.8)
		await _shot("p69_sheet_locked_ironwood")
	if _want("owned"):
		save.data["gold"] = 640
		save.data["heroes_owned"] = ["calavera", "fadeaway", "ironwood", "solenne", "buck", "may", "mira"]
		t = await _title()
		await _show(t, "calavera")
		await _shot("p69_title_owned_calavera")
		if t.has_method("open_drawer"):
			t.open_drawer()
			await _wait(0.6)
			await _shot("p69_title_drawer_all_owned")
	save.end_sandbox()
	quit()
