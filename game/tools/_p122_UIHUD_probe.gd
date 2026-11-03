## Pass 122 (lane UIHUD): the HUD's top-row type measured in both faces, so the Royale plates can keep today's boxes.
## Prints, for every string the LV, clock and gold plates show, its width and line box in Alfa Slab One (the Wanted
## face) and in Ultra (the Royale face) at the HUD's sizes (PLATE_PX 36, TIMER_PX 56), and W.normal_height of each.
##   bash tools/godot.sh --headless --path D:/_projects/88fits/game --script res://tools/_p122_UIHUD_probe.gd
## Autoloads are reached through the tree (a SceneTree script compiles before they exist); nothing is written.
extends SceneTree

const STRINGS := {36: ["LV 1", "LV 14", "LV 100", "0", "312", "1,234", "12,345"], 56: ["00:00", "04:12", "13:00"]}


func _initialize() -> void:
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _main() -> void:
	var wanted: Font = load("res://ui/fonts/AlfaSlabOne-Regular.ttf")
	var royale: Font = load("res://ui/fonts/Ultra-Regular.ttf")
	for px in STRINGS:
		var size: int = int(px)
		print("size %d: line box Alfa %.0f (height %.1f asc %.1f) / Ultra %.0f (height %.1f asc %.1f)" % [size,
			_normal(wanted, size), wanted.get_height(size), wanted.get_ascent(size),
			_normal(royale, size), royale.get_height(size), royale.get_ascent(size)])
		for s in STRINGS[px]:
			var a := wanted.get_string_size(str(s), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var b := royale.get_string_size(str(s), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			print("  %-8s Alfa %6.1f  Ultra %6.1f  (%+.1f px, %+.0f%%)" % [str(s), a, b, b - a, (b / maxf(a, 1.0) - 1.0) * 100.0])
	quit()


## W.normal_height's rule without W (the autoloads are not up): the face's metrics table.
static func _normal(f: Font, px: int) -> float:
	var path := f.resource_path
	if path.contains("AlfaSlab"):
		return roundf(1.036 * px) + roundf(0.333 * px)
	if path.contains("Ultra"):
		return roundf(1.0088 * px) + roundf(0.2739 * px)
	return f.get_height(px)
