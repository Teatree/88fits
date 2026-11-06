## Pass 129 (lane TRAILCORE): the game's own reading of a Trail file: what it holds, what a new save could buy first,
## and Trail.check's warnings (the same lines the Level Editor's Trail tab shows).
## Run: bash tools/godot.sh --headless --path <project> --script res://tools/trail_check.gd --log-file <f> [-- file=<path>]
## (`file`: a res:// or absolute path; the game's content/trail/trail.json by default). Reads only: no save is touched.
## Prints "trail_check: OK ..." (exit 0), or every warning and "trail_check: N warnings" (exit 1).
extends SceneTree


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	# by path, at run time: a tool script is compiled before the autoloads exist
	var trail = load("res://core/systems/Trail.gd")
	var path: String = trail.DEFAULT
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("file="):
			path = a.trim_prefix("file=")
	var data: Dictionary = trail.read_file(path)
	if data.is_empty():
		print("trail_check: %s is missing or not a JSON object" % path)
		quit(1)
		return
	var warnings: Array = trail.check(data)
	trail.load_data(data)
	var ups: Variant = data.get("upgrades")
	var top: int = trail.levels()
	var cfg: Variant = data.get("price")
	var total := 0
	for n: Dictionary in trail.nodes():
		total += int(trail.price(str(n["id"])))
	print("trail_check: %s: %d upgrade types, %d nodes on %d levels; the curve costs %d at level 1 and %d at level %d; every node together %d %s" % [
		path, (ups as Dictionary).size() if ups is Dictionary else 0, (trail.nodes() as Array).size(), top,
		int(trail.price_at(cfg if cfg is Dictionary else {}, 1)), int(trail.price_at(cfg if cfg is Dictionary else {}, maxi(top, 1))), maxi(top, 1),
		total, str(trail.currency())])
	for w in warnings:
		print("  " + str(w))
	trail.load_from()
	if warnings.is_empty():
		print("trail_check: OK, no warnings")
		quit(0)
	else:
		print("trail_check: %d warning%s" % [warnings.size(), "" if warnings.size() == 1 else "s"])
		quit(1)
