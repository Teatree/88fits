## Pass 122 (lane UIKIT_B): does Resource.duplicate() copy a StyleBox script's plain variables? HardBox.pressed() relies
## on it (the role, the fill, the shadow, the inner band of the pressed copy). Headless:
##   bash tools/godot.sh --headless --path game --script res://tools/_p122_UIKIT_dupprobe.gd
extends SceneTree


func _initialize() -> void:
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _main() -> void:
	var hb = load("res://ui/wanted/HardBox.gd").new()
	hb.fill = Color.RED
	hb.border = 7
	hb.shadow = 9
	hb.role = "gold"
	hb.inner = 3
	hb.content_margin_left = 11.0
	var d = hb.duplicate()
	print("dupprobe: fill=%s border=%d shadow=%d role='%s' inner=%d margin_left=%.0f" % [d.fill, d.border, d.shadow, d.role, d.inner, d.content_margin_left])
	for p in hb.get_property_list():
		if str(p["name"]) in ["fill", "role", "shadow", "inner"]:
			print("dupprobe: property %s usage=%d" % [p["name"], int(p["usage"])])
	quit()
