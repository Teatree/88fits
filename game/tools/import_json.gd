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


## A talent whose ranks and prices (or per-rank effect lists) differ in length: TalentDef.cost_of_rank stops at the
## shorter of ranks and the price list, so say so here rather than let a rank go missing quietly. Read by name: naming
## TalentDef here would compile Effect and TextGen, which names the Registry, before the autoloads exist.
func _check_talent(t: Resource, json: String) -> void:
	var id := str(t.get("id"))
	var ranks := int(t.get("ranks"))
	var cost: Array = t.get("cost")
	var forms: Array = t.get("forms")
	if cost.size() != ranks:
		push_warning("import_json: talent %s has %d ranks but %d prices (%s)" % [id, ranks, cost.size(), json])
	for f: int in range(forms.size()):
		var rl = (forms[f] as Dictionary).get("rank_effects", []) if forms[f] is Dictionary else []
		if rl is Array and not (rl as Array).is_empty() and (rl as Array).size() != ranks:
			push_warning("import_json: talent %s form %d has %d rank_effects lists for %d ranks (%s)" % [id, f, (rl as Array).size(), ranks, json])


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
			if type == "talents":
				_check_talent(res, json)
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
