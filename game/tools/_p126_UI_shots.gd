## Pass 126 (lane UI): the captures wanted_shots has no state for, at full resolution:
##  - feet_title.png: every hero on the main menu, standing, cropped round his feet (his shadow must touch his soles);
##  - feet_heroes.png: every hero on the Heroes screen, each frame of his run cycle, cropped round his feet;
##  - swap_NN.png: the main menu's hero swap at slow time, every 40 ms of game time (the run-off's quicker fade, the run-in as it was);
##  - title_<hero>.png and heroes_<hero>.png: the whole screens for a few heroes (nothing collides with the bigger figure).
## Windowed, on the sandboxed save, every wait bounded:
## GODOT_TIMEOUT=300 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game --log-file <abs> --script res://tools/_p126_UI_shots.gd -- out=<dir> [inset=130] [only=feet,swap,full]
extends SceneTree

const HEROES := ["drifter", "astro", "calavera", "ironwood", "solenne", "fadeaway", "buck", "may"]
const TITLE_CROP := Rect2i(340, 1040, 400, 200)
const STAGE_CROP := Rect2i(90, 440, 300, 110)

var _out := "user://p126_ui"
var _only: Array = []
var _inset := -1
var _save
var _reg


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",")
		elif a.begins_with("inset="):
			_inset = int(a.substr(6))
	DirAccess.make_dir_recursive_absolute(_out)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _want(n: String) -> bool:
	return _only.is_empty() or _only.has(n)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _grab() -> Image:
	await process_frame
	await process_frame
	return root.get_viewport().get_texture().get_image()


func _main() -> void:
	_save = root.get_node("Save")
	_reg = root.get_node("Registry")
	_save.begin_sandbox()
	if _inset >= 0:
		root.get_node("Settings").top_inset = _inset
	_save.data["gold"] = 104711
	var all: Array = []
	for id in HEROES:
		all.append(id)
	_save.data["heroes_owned"] = all
	_save.data["last_character"] = "drifter"
	if _want("feet"):
		await _feet_title()
		await _feet_heroes()
	if _want("swap"):
		await _swap()
	if _want("full"):
		await _full()
	quit()


func _title_at(id: String) -> Control:
	change_scene_to_file("res://ui/TitleScreen.tscn")
	await _wait(0.9)
	var t = current_scene
	for i in (t._heroes as Array).size():
		if (t._heroes[i] as Resource).get("id") == id:
			t._index = i
			t._show_hero(0)
	t._place()
	await _wait(0.25)
	return t


func _feet_title() -> void:
	var cols := 2
	var rows := int(ceil(float(HEROES.size()) / float(cols)))
	var sheet := Image.create(TITLE_CROP.size.x * cols + 8 * (cols - 1), (TITLE_CROP.size.y + 8) * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.MAGENTA)
	var k := 0
	change_scene_to_file("res://ui/TitleScreen.tscn")
	await _wait(0.9)
	var t = current_scene
	for id: String in HEROES:
		for i in (t._heroes as Array).size():
			if (t._heroes[i] as Resource).get("id") == id:
				t._index = i
				t._show_hero(0)
		t._place()
		await _wait(0.3)
		var img: Image = await _grab()
		img.convert(Image.FORMAT_RGBA8)
		var crop := TITLE_CROP
		crop.position.y += int((img.get_height() - 1920) * 0.5)
		sheet.blit_rect(img, crop, Vector2i((k % cols) * (TITLE_CROP.size.x + 8), (k / cols) * (TITLE_CROP.size.y + 8)))
		k += 1
	sheet.save_png(_out.path_join("feet_title.png"))
	print("p126: feet_title")


func _feet_heroes() -> void:
	change_scene_to_file("res://ui/HeroesScreen.tscn")
	await _wait(1.0)
	var s = current_scene
	s.set_process(false)
	var cols := 6
	var rows := HEROES.size()
	var sheet := Image.create((STAGE_CROP.size.x / 2 + 4) * cols, (STAGE_CROP.size.y + 6) * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.MAGENTA)
	var row := 0
	for id: String in HEROES:
		s.show_hero(_reg.character(id))
		await _wait(0.3)
		var n: int = s.get("_anim_n")
		for c in cols:
			s.set("_frame", int(float(c) * float(n) / float(cols)))
			(s.get("_sprite") as Control).queue_redraw()
			var img: Image = await _grab()
			img.convert(Image.FORMAT_RGBA8)
			var crop := STAGE_CROP
			crop.position.y += int(W_safe_top())
			var half := Rect2i(crop.position + Vector2i(crop.size.x / 4, 0), Vector2i(crop.size.x / 2, crop.size.y))
			sheet.blit_rect(img, half, Vector2i(c * (STAGE_CROP.size.x / 2 + 4), row * (STAGE_CROP.size.y + 6)))
		row += 1
	sheet.save_png(_out.path_join("feet_heroes.png"))
	print("p126: feet_heroes")
	s.set_process(true)


func W_safe_top() -> float:
	return float(root.get_node("Settings").top_inset) if int(root.get_node("Settings").top_inset) > 0 else 0.0


## The swap at a tenth of the speed: a picture every 40 ms of game time from the press, in a row.
func _swap() -> void:
	var t: Control = await _title_at("drifter")
	Engine.time_scale = 0.1
	var frames: Array = []
	t.call("_step", 1)
	for k in 10:
		await _wait(0.4)
		var img: Image = await _grab()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(360, int(360.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_LANCZOS)
		frames.append(img)
		print("p126: swap %d alpha" % k)
	Engine.time_scale = 1.0
	var w: int = frames[0].get_width()
	var h: int = frames[0].get_height()
	var crop_h := int(h * 0.45)
	var sheet := Image.create((w + 4) * 5, (crop_h + 4) * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.MAGENTA)
	for k in frames.size():
		sheet.blit_rect(frames[k], Rect2i(0, int(h * 0.38), w, crop_h), Vector2i((k % 5) * (w + 4), (k / 5) * (crop_h + 4)))
	sheet.save_png(_out.path_join("swap.png"))
	print("p126: swap")


func _full() -> void:
	for id: String in ["ironwood", "calavera", "solenne", "may"]:
		await _title_at(id)
		var img: Image = await _grab()
		img.save_png(_out.path_join("title_%s.png" % id))
	# on sale, and locked: the BUY and the requirement over the bigger figure
	_save.data["heroes_owned"] = ["drifter"]
	await _title_at("ironwood")
	(await _grab()).save_png(_out.path_join("title_onsale.png"))
	await _title_at("fadeaway")
	(await _grab()).save_png(_out.path_join("title_locked.png"))
	print("p126: full")
