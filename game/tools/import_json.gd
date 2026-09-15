## Regenerates <id>.tres from <id>.json for every content folder, plus soundmap.tres.
## Run: godot --headless --path game --script res://tools/import_json.gd
extends SceneTree

const ROOT := "res://content/"


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var count := 0
	var errors := 0
	for type: String in JsonContent.TYPES:
		var base := ROOT + type + "/"
		var dir := DirAccess.open(base)
		if dir == null:
			continue
		for sub: String in dir.get_directories():
			var folder := base + sub + "/"
			var json := folder + sub + ".json"
			if not FileAccess.file_exists(json):
				continue
			var d := JsonContent.load_json(json)
			if d.is_empty():
				printerr("import_json: empty or invalid ", json)
				errors += 1
				continue
			var res := JsonContent.build(type, d, folder)
			if res == null:
				errors += 1
				continue
			var out := folder + sub + ".tres"
			var err := ResourceSaver.save(res, out)
			if err != OK:
				printerr("import_json: failed to save %s (%d)" % [out, err])
				errors += 1
			else:
				count += 1
	# sound map
	var sjson := ROOT + "sounds/soundmap.json"
	if FileAccess.file_exists(sjson):
		var sm := JsonContent.soundmap_from_dict(JsonContent.load_json(sjson), ROOT + "sounds/")
		var err := ResourceSaver.save(sm, ROOT + "sounds/soundmap.tres")
		if err != OK:
			printerr("import_json: failed to save soundmap.tres (%d)" % err)
			errors += 1
		else:
			count += 1
	print("import_json: wrote %d resources, %d errors" % [count, errors])
	quit(1 if errors > 0 else 0)
