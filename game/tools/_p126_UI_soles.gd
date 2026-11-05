## Pass 126 (lane UI): where a hero's soles really stand in his strip's frames, as a share of the frame from its top, against
## TitleStage.FIGURE_FEET (0.953): the gap Garry sees under the feet ("so it's actually touching their feet"). For each hero's
## played look, each animation the menus play: the lowest row of each frame that holds some solid paint, the frame's lowest
## and highest such row, and their mean. Prints only.
## bash tools/godot.sh --headless --path D:/_projects/88fits/game --log-file <abs> --script res://tools/_p126_UI_soles.gd
extends SceneTree

const ORDER := ["idle", "run", "turn", "hit", "die", "cheer", "idle_f", "run_f", "idle_s", "run_s", "idle_bd", "run_bd",
	"idle_fd", "run_fd", "run_b", "idle_b", "attack"]


func _initialize() -> void:
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _main() -> void:
	var reg = root.get_node("Registry")
	var ts: GDScript = load("res://ui/TitleStage.gd")
	var order: Array = ts.get("ORDER") if ts.get("ORDER") != null else ORDER
	for c in reg.sorted_characters():
		var look = reg.played_look(c)
		if look == null or look.sprite == null:
			print("%-10s no sprite" % c.id)
			continue
		var img: Image = look.sprite.get_image()
		if img == null:
			print("%-10s no image" % c.id)
			continue
		if img.is_compressed():
			img.decompress()
		var cols: int = look.strip_cols
		var total := 0
		for a in order:
			total += int(look.anims.get(a, 0))
		if cols <= 0:
			cols = maxi(total, 1)
		var rows := int(ceil(float(total) / float(cols)))
		var cw := float(img.get_width()) / float(cols)
		var ch := float(img.get_height()) / float(maxi(rows, 1))
		var at := 0
		var line := "%-10s %s cell %d:" % [c.id, look.look_code() if look.has_method("look_code") else "", int(ch)]
		for a in order:
			var n := int(look.anims.get(a, 0))
			if a in ["idle_f", "idle_fd", "idle", "run_fd", "run_s", "run_f"] and n > 0:
				var lo := 1.0
				var hi := 0.0
				var sum := 0.0
				for k in n:
					var i := at + k
					var x0 := int(float(i % cols) * cw)
					var y0 := int(float(i / cols) * ch)
					var y := _lowest(img, x0, y0, int(cw), int(ch))
					var f := float(y) / ch
					lo = minf(lo, f)
					hi = maxf(hi, f)
					sum += f
				line += "  %s %.3f..%.3f (mean %.3f)" % [a, lo, hi, sum / float(n)]
			at += n
		print(line)
	quit()


## The lowest row of the frame at (x0, y0) with at least four solid pixels.
func _lowest(img: Image, x0: int, y0: int, w: int, h: int) -> int:
	for y in range(h - 1, -1, -1):
		var hits := 0
		for x in range(0, w, 2):
			if img.get_pixel(x0 + x, y0 + y).a > 0.5:
				hits += 1
				if hits >= 2:
					return y
	return 0
