## Writes placeholder sprite strips and icons as PNGs into every content folder that lacks them,
## using each item's `placeholder` hints. Run, then `--import`, then `import_json.gd` to bind them.
## godot --headless --path game --script res://tools/gen_placeholders.gd [-- force] [-- only=type[/id],type2,...]
## `only=` (pass 66, the Level Editor's register job) limits the run to those folders, parsed as import_json.gd parses
## its own: a bare type is every folder of it, type/id one folder, several parts comma-separated
## (only=enemies/test_beast,mutations). Without it every folder is looked at, as before.
extends SceneTree

const ROOT := "res://content/"

var _force := false


func _init() -> void:
	_force = OS.get_cmdline_user_args().has("force")
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var written := write_for(ROOT, parse_only(OS.get_cmdline_user_args()), _force)
	print("gen_placeholders: wrote %d files" % written)
	quit(0)


## type -> [] for every folder of it, or the folder ids asked for; empty = no filter (everything). import_json.gd's
## reading of `only=`: comma-split, spaces and a trailing `/` trimmed, a bare type beats ids given for it, an unknown
## type only warns.
static func parse_only(args: PackedStringArray) -> Dictionary:
	var want: Dictionary = {}
	for a: String in args:
		if not a.begins_with("only="):
			continue
		for part: String in a.trim_prefix("only=").split(",", false):
			var p := part.strip_edges().trim_suffix("/")
			if p == "":
				continue
			var type := p.get_slice("/", 0)
			var id := p.substr(type.length() + 1) if p.contains("/") else ""
			if not JsonContent.TYPES.has(type):
				push_warning("gen_placeholders: only= names an unknown content type '%s'" % type)
			if id == "":
				want[type] = []
			elif not want.has(type):
				want[type] = [id]
			elif not (want[type] as Array).is_empty():
				(want[type] as Array).append(id)
	return want


## The placeholders under `content_root` (ROOT in the tool; a test's copy under user://, so nothing under res://content is
## touched) for the folders `only` names (every folder when empty): an icon, and a strip for a creature or a hero, each
## written when its file is missing or always with `force`. Returns how many files were written.
static func write_for(content_root: String, only: Dictionary, force: bool) -> int:
	var written := 0
	for type: String in JsonContent.TYPES:
		if not only.is_empty() and not only.has(type):
			continue
		var ids: Array = only.get(type, [])
		var base := content_root + type + "/"
		var dir := DirAccess.open(base)
		if dir == null:
			continue
		for sub: String in dir.get_directories():
			if not ids.is_empty() and not ids.has(sub):
				continue
			var folder := base + sub + "/"
			var d := JsonContent.load_json(folder + sub + ".json")
			if d.is_empty():
				continue
			var def := JsonContent.build(type, d, folder)
			if def == null:
				continue
			var icon_path := folder + str(d.get("icon", sub + "_icon.png"))
			if force or not FileAccess.file_exists(icon_path):
				var img := PlaceholderArt.icon_image(def, 256)
				if img.save_png(icon_path) == OK:
					written += 1
			if def is EnemyDef:
				var sp := folder + str(d.get("sprite", sub + "_sprite.png"))
				if force or not FileAccess.file_exists(sp):
					if PlaceholderArt.enemy_image(def).save_png(sp) == OK:
						written += 1
			elif def is CharacterDef:
				var sp := folder + str(d.get("sprite", sub + "_sprite.png"))
				if force or not FileAccess.file_exists(sp):
					if PlaceholderArt.character_image(def).save_png(sp) == OK:
						written += 1
	return written
