## Pass 123 (lane UPGRADE): what the Royale tiles' effect lines read (TextGen of each form's one-rank effects, "per rank")
## and how wide they are in Rubik 500 at 20 / 22 px, beside the form's own words. Headless:
## bash tools/godot.sh --headless --path game --script res://tools/_p123_UPGRADE_probe.gd
extends SceneTree


func _initialize() -> void:
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _main() -> void:
	var reg = root.get_node("Registry")
	var R_: GDScript = load("res://ui/wanted/R.gd")
	var TG: GDScript = load("res://core/systems/TextGen.gd")
	var body: Font = R_.body(500)
	var bold: Font = R_.body(700)
	for def in reg.talents_list():
		print("%s (%s) first %d" % [def.display_name, def.id, def.first_price()])
		for f in 2:
			var line: String = TG.describe_effects(def.summed_effects(f, 1))
			var name: String = def.form_name(f)
			var w_name := bold.get_string_size(name + "  ", HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
			var w20 := body.get_string_size(line + " per rank", HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			print("   %-12s | %s per rank | name %d + line %d px | own: %s" % [name, line, int(w_name), int(w20), def.form_text(f)])
	quit()
