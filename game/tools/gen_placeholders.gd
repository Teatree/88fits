## Writes placeholder sprite strips and icons as PNGs into every content folder that lacks them,
## using each item's `placeholder` hints. Run, then `--import`, then `import_json.gd` to bind them.
## godot --headless --path game --script res://tools/gen_placeholders.gd [-- force]
extends SceneTree

var _force := false


func _init() -> void:
	_force = OS.get_cmdline_user_args().has("force")
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var written := 0
	for type in JsonContent.TYPES:
		var base := "res://content/%s/" % type
		var dir := DirAccess.open(base)
		if dir == null:
			continue
		for sub: String in dir.get_directories():
			var folder := base + sub + "/"
			var d := JsonContent.load_json(folder + sub + ".json")
			if d.is_empty():
				continue
			var def := JsonContent.build(type, d, folder)
			if def == null:
				continue
			var icon_path := folder + str(d.get("icon", sub + "_icon.png"))
			if _force or not FileAccess.file_exists(icon_path):
				var img := PlaceholderArt.icon_image(def, 256)
				if img.save_png(icon_path) == OK:
					written += 1
			if def is EnemyDef:
				var sp := folder + str(d.get("sprite", sub + "_sprite.png"))
				if _force or not FileAccess.file_exists(sp):
					if PlaceholderArt.enemy_image(def).save_png(sp) == OK:
						written += 1
			elif def is CharacterDef:
				var sp := folder + str(d.get("sprite", sub + "_sprite.png"))
				if _force or not FileAccess.file_exists(sp):
					if PlaceholderArt.character_image(def).save_png(sp) == OK:
						written += 1
	print("gen_placeholders: wrote %d files" % written)
	quit(0)
