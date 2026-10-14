## Pass 76, lane LOOKS (scratch): every weapon family with looks, worn in each of its looks in turn: the weapon's name, its
## thing words, its card's first sentence, its members' names and icons' files, and the params a held instance folds
## (the drawing keys). Runs in the save's sandbox and puts every family back in its JSON look after.
## godot --headless --path game --script res://tools/_p76_LOOKS_probe.gd
extends SceneTree


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var reg := root.get_node("Registry")
	var sv := root.get_node("Save")
	sv.begin_sandbox()
	for w in reg.weapons.values():
		if w.is_evolution or reg.item_look_codes(w.id).is_empty():
			continue
		print("p76_looks: family %s plays %s, looks %s" % [w.id, reg.played_item_look(w.id), str(reg.item_look_codes(w.id))])
		for code in reg.item_look_codes(w.id):
			sv.set_item_look(w.id, str(code))
			var inst = load("res://core/systems/WeaponInstance.gd").new(w, 1)
			inst.rebuild(load("res://core/systems/StatSheet.gd").new(), [inst])
			var draw := {}
			for k in ["model", "models", "model_form", "model_colour", "fuse_tip", "tint", "wick_flame", "pool_flame", "size_mult"]:
				if inst.params.has(k):
					draw[k] = inst.params[k] if not (inst.params[k] is Dictionary) else "{%d keys}" % (inst.params[k] as Dictionary).size()
			var desc: String = inst.description()
			print("p76_looks:   %s: %s | nouns %s | icon %s | visual %s | %s" % [str(code), w.display_name, str(load("res://core/systems/TextGen.gd").weapon_nouns(w)),
				w.icon_file, w.visual_file, desc.substr(0, desc.find(".") + 1)])
			print("p76_looks:      draw %s" % str(draw))
			var names: Array = []
			for m in reg.item_family(w.id):
				if m != w:
					names.append("%s=%s (%s)" % [m.id, m.display_name, m.icon_file.get_file()])
			print("p76_looks:      members %s" % ", ".join(names))
		sv.set_item_look(w.id, "")
	sv.end_sandbox()
	quit(0)
