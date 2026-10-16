## The still of the desert behind every menu (art/ui/wanted/menu_backdrop.jpg, ScreenBase's backdrop under its 82 % paper
## wash). Since pass 83 (lane SCENE) it is the live title's composed scene (TitleStage.compose, art/ui/title_scene.json)
## with no hero and no UI, so the menus open on the same desert the title shows; before, wanted_shots.gd only=backdrop
## shot the arena from a run's camera. Windowed:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game --script res://tools/menu_backdrop.gd [-- out=<file.jpg>]
## The save is sandboxed; a watchdog quits after 60 s.
extends SceneTree

var _out := "res://art/ui/wanted/menu_backdrop.jpg"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	create_timer(60.0, true, false, true).timeout.connect(func() -> void:
		push_error("menu_backdrop: watchdog")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _main() -> void:
	var save = root.get_node("Save")
	save.begin_sandbox()
	root.get_node("Settings").menu_style = "live"
	change_scene_to_file("res://ui/TitleScreen.tscn")
	await _wait(1.6)
	var t = current_scene
	for c in t.get_children():
		if c is CanvasItem and c.name != "TitleStage":
			(c as CanvasItem).visible = false
	var stage = t.get_node_or_null("TitleStage")
	if stage == null or stage.hero == null:
		push_error("menu_backdrop: no live title")
		save.end_sandbox()
		quit(2)
		return
	stage.hero.visible = false
	await process_frame
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var path := ProjectSettings.globalize_path(_out) if _out.begins_with("res://") else _out
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_jpg(path, 0.85)
	print("menu_backdrop: -> ", path)
	save.end_sandbox()
	quit(0)
