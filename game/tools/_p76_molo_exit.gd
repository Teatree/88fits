## Pass 76 (lane MOLO) scratch probe: does a ProjectileManager with wick flames exit cleanly? Headless:
##   godot --headless --path game --script res://tools/_p76_molo_exit.gd -- mode=wick|none|game [frames=30]
## mode=game loads the Game scene in the arena (Warmup makes the wick flames) and quits after `frames`.
extends SceneTree

var _mode := "wick"
var _frames := 30
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("mode="):
			_mode = a.substr(5)
		elif a.begins_with("frames="):
			_frames = int(a.substr(7))
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _t0 > 60000:
		print("p76_molo_exit: WATCHDOG")
		quit(2)
	return false


func _main() -> void:
	if _mode == "warm":
		# no arena: a tool's instant start runs Warmup.run (Game._ready) before anything is thrown
		var f2 := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
		f2.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
		f2.close()
		change_scene_to_file("res://game/Game.tscn")
		for i in range(4):
			await process_frame
		var g2 = current_scene
		var wk = g2.projectiles.get("_wick") if g2 and g2.get("projectiles") else null
		print("p76_molo_exit: warm made ", wk != null, " drawn ", wk._mm.visible_instance_count if wk else -1, " warmup node ", g2.get_node_or_null("Warmup") != null)
		quit(0)
		return
	if _mode == "game":
		var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"weapon": "molotov", "level": 3, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
		f.close()
		root.get_node("Run").arena_next = true
		change_scene_to_file("res://game/Game.tscn")
		for i in range(_frames):
			await process_frame
		var g = current_scene
		if g and g.get("projectiles") and g.projectiles.get("_wick") == null:
			# the arena may not have warmed up yet: a flame on a bottle makes the system as a run does
			g.projectiles.wick_flames()
		for i in range(30):
			await process_frame
		print("p76_molo_exit: game ", g != null, " wick ", g.projectiles.get("_wick") != null if g and g.get("projectiles") else false)
		quit(0)
		return
	var holder := Node3D.new()
	root.add_child(holder)
	var pm = load("res://core/systems/ProjectileManager.gd").new()
	holder.add_child(pm)
	if _mode == "wick":
		pm.warm_wick_flames(Vector3(0, -8, 0))
		pm.wick_flames().ground_flame(Vector3.ZERO, 1.0, 0.5, "torch", false, true)
	for i in range(_frames):
		await process_frame
	if _mode == "wick":
		pm.warm_wick_flames(Vector3.INF)
	print("p76_molo_exit: ", _mode, " done")
	quit(0)
