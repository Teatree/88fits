## A first look at the Wanted kit: the level-up screen's pieces laid out from the mock's numbers, saved as a PNG.
## godot --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/wanted_kit.gd -- out=<png>
extends SceneTree

var _out := "user://wanted_kit.png"
var _frames := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	process_frame.connect(_build, CONNECT_ONE_SHOT)


func _build() -> void:
	var reg = root.get_node("Registry")
	var kit = load("res://ui/wanted/W.gd")
	var root_c := Control.new()
	root_c.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(root_c)
	var bg := ColorRect.new()
	bg.color = Color("5d4f43")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_c.add_child(bg)
	var header = load("res://ui/wanted/WModalHeader.gd").make("Wanted", "LEVEL 3", "Pick one. The desert waits.")
	root_c.add_child(header)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 44)
	col.position = Vector2(48, 470)
	col.size = Vector2(984, 900)
	root_c.add_child(col)
	var WCardS = load("res://ui/wanted/WCard.gd")
	var bristle = reg.passive("bristle")
	var notes = reg.passive("field_notes")
	var boom = reg.weapon("boomstick")
	col.add_child(WCardS.make(bristle, {"word": "NEW PASSIVE", "word_color": kit.SAGE, "stars": [4, 0, 1], "effect": "+8 thorns damage a level. Trade: cooldowns 4% longer.", "rarity": "rare", "plate_px": 180.0, "seal_px": 104.0, "icon_frac": 0.72}))
	var c2 = WCardS.make(notes, {"word": "NEW PASSIVE", "word_color": kit.SAGE, "stars": [5, 0, 1], "effect": "+8% XP from every gem.", "rarity": "common", "plate_px": 180.0, "seal_px": 104.0, "icon_frac": 0.7})
	col.add_child(c2)
	col.add_child(WCardS.make(boom, {"word": "WEAPON · LV 5 → 6", "word_color": kit.BRASS_DARK, "stars": [8, 5, 6], "effect": "Next: +2 knockback", "rarity": "epic", "plate_px": 180.0, "seal_px": 104.0, "icon_frac": 0.78}))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.position = Vector2(48, 1920 - 90 - 108)
	row.size = Vector2(984, 108)
	root_c.add_child(row)
	var WB = load("res://ui/wanted/WButton.gd")
	for spec in [[["REROLL ", ["×1", kit.BRASS_DARK]], false], [["SKIP ", ["+10", kit.BRASS_DARK]], false], [["BANISH ×0"], true]]:
		var b = WB.make(spec[0], 34, "secondary", 5, 8, 26.0, 0.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.locked = spec[1]
		row.add_child(b)
	await process_frame
	c2.show_held(true)
	process_frame.connect(_tick)


func _tick() -> void:
	_frames += 1
	if _frames == 8:
		root.get_viewport().get_texture().get_image().save_png(_out)
		print("wanted_kit: ", _out)
		quit()
