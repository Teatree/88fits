## Pass 73, lane CARDS: what the game reads of the cards' looks (the .tres the import wrote): per card its look in play,
## its codes and the icon file it draws. Headless:
##   godot --headless --path game --script res://tools/_p73_CARDS_probe.gd [-- ids=brawn,juggernaut]
extends SceneTree


func _initialize() -> void:
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _main() -> void:
	var reg := root.get_node("Registry")
	var want: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("ids="):
			want = a.substr(4).split(",", false)
	var n := 0
	for p in reg.passives.values():
		if not p.is_line():
			continue
		if not want.is_empty() and not want.has(p.id):
			continue
		var path: String = p.icon.resource_path if p.icon else "(none)"
		print("p73_cards_probe: %s '%s' plays %s codes %s icon %s" % [p.id, p.display_name, p.variant, str(p.variant_codes()), path.get_file()])
		n += 1
	print("p73_cards_probe: %d cards" % n)
	quit(0)
