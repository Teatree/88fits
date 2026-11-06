## Regenerates <id>.tres from <id>.json for every content folder, plus soundmap.tres.
## Run: godot --headless --path game --script res://tools/import_json.gd [-- only=type[/id],type2,...]
## `only=` (pass 46) limits the run to those folders: a bare type is every folder of it, type/id one folder, and
## "sounds" the sound map (left out unless named once `only=` is given). Example: -- only=maps/red_canyon,passives
extends SceneTree

const ROOT := "res://content/"


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


## type -> [] for every folder of it, or the folder ids asked for; empty = no filter (everything).
func _only() -> Dictionary:
	var want: Dictionary = {}
	for a: String in OS.get_cmdline_user_args():
		if not a.begins_with("only="):
			continue
		for part: String in a.trim_prefix("only=").split(",", false):
			var p := part.strip_edges().trim_suffix("/")
			if p == "":
				continue
			var type := p.get_slice("/", 0)
			var id := p.substr(type.length() + 1) if p.contains("/") else ""
			if type != "sounds" and not JsonContent.TYPES.has(type):
				push_warning("import_json: only= names an unknown content type '%s'" % type)
			if id == "":
				want[type] = []
			elif not want.has(type):
				want[type] = [id]
			elif not (want[type] as Array).is_empty():
				(want[type] as Array).append(id)
	return want


func _run() -> void:
	var count := 0
	var errors := 0
	var only := _only()
	if not only.is_empty():
		print("import_json: only ", only)
	for type: String in JsonContent.TYPES:
		if not only.is_empty() and not only.has(type):
			continue
		var ids: Array = only.get(type, [])
		var base := ROOT + type + "/"
		var dir := DirAccess.open(base)
		if dir == null:
			continue
		for sub: String in dir.get_directories():
			if not ids.is_empty() and not ids.has(sub):
				continue
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
	if FileAccess.file_exists(sjson) and (only.is_empty() or only.has("sounds")):
		var sm := JsonContent.soundmap_from_dict(JsonContent.load_json(sjson), ROOT + "sounds/")
		var err := ResourceSaver.save(sm, ROOT + "sounds/soundmap.tres")
		if err != OK:
			printerr("import_json: failed to save soundmap.tres (%d)" % err)
			errors += 1
		else:
			count += 1
	print("import_json: wrote %d resources, %d errors" % [count, errors])
	quit(1 if errors > 0 else 0)
