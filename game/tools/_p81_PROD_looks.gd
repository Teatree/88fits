## Scratch (pass 81, lane PROD): every hero's played look, every creature's played and named looks and every card's icon
## as the Registry serves them (texture file, anims, strip columns, fps, frame size, icon), to compare the source with
## the production build's staging copy.  godot --headless --path <project> --script res://tools/_p81_PROD_looks.gd -- out=<file>
extends SceneTree


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _tex(t) -> String:
	return (t as Resource).resource_path.get_file() if t is Resource else ""


func _run() -> void:
	var out := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.trim_prefix("out=")
	var reg: Node = root.get_node("Registry")
	var d := {}
	for c in reg.sorted_characters():
		var l = reg.played_look(c)
		d["hero " + c.id] = {"look": l.look_code(), "sprite": _tex(l.sprite), "anims": l.anims, "cols": l.strip_cols, "fps": l.fps,
			"px": l.frame_px, "icon": _tex(c.icon), "title": l.title_path()}
	for e in reg.enemies.values():
		var codes: Array = [""] + Array(e.variants.keys())
		for code in codes:
			var v = reg.enemy_with(e.id, str(code))
			if v == null or (str(code) != "" and not reg.enemy(e.id).variants.has(code)):
				continue
			d["creature %s@%s" % [e.id, code]] = {"sprite": _tex(v.sprite), "anims": v.anims, "cols": v.strip_cols, "fps": v.fps,
				"icon": _tex(v.icon), "front": v.front_faces, "back": v.back_faces}
	for p in reg.passives.values():
		d["card " + p.id] = {"look": p.variant, "icon": _tex(p.icon)}
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, " ", true))
	f.close()
	print("_p81_PROD_looks: %d entries -> %s" % [d.size(), out])
	quit(0)
