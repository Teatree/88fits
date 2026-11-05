## Pass 126 (lane STAGE): the hero's real throw in the real game: the debug arena, Player's own physics, a dust devil's toss of each
## stage (WaveTimeline.dust_devils_at): how far along the ground he lands, how high he goes, how long he is up. Prints one line a
## stage. Headless, bounded (a frame cap and a watchdog), the save untouched (the arena's sandbox; godot.sh keeps the file aside).
##   bash tools/godot.sh --headless --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/_p126_STAGE_throw.gd
extends SceneTree

const WATCHDOG_MS := 120000
const FRAME_CAP := 20000

var g = null
var _t0 := 0


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	_t0 = Time.get_ticks_msec()
	var run = root.get_node("Run")
	root.get_node("Save").begin_sandbox()
	run.launch_override = {"arena": true, "analytics": false, "character": "drifter"}
	change_scene_to_file("res://game/Game.tscn")
	var frames := 0
	while frames < FRAME_CAP and Time.get_ticks_msec() - _t0 < WATCHDOG_MS:
		await process_frame
		frames += 1
		var cs = current_scene
		if cs != null and cs.get("player") != null and cs.get("enemies") != null and frames > 60:
			g = cs
			break
	if g == null:
		printerr("throw: the arena never came up")
		quit(2)
		return
	var tl = run.map.timeline
	var DD = load("res://core/systems/DustDevils.gd")
	var pl: Node3D = g.player
	pl.god = true
	for k in range(tl.stage_count()):
		var c: Dictionary = DD.config_of(tl.dust_devils_at(k))
		var res: Dictionary = await _toss(pl, float(c["toss"]["up"]), float(c["toss"]["out"]))
		print("throw: stage %d %s: toss up %.1f out %.1f: lands %.2f m along the ground, %.2f m high, %.2f s up (fling %.1f, radius %.1f, size %.2f, every %s, first %.0f)" % [
			k + 1, tl.stage_name(k), float(c["toss"]["up"]), float(c["toss"]["out"]), res["far"], res["high"], res["air"], float(c["fling"]), float(c["radius"]), float(c["size"]), str(c["every"]), float(c["first"])])
	quit(0)


## One throw along +x from where he stands, the stick still, on the ground again by the end.
func _toss(pl: Node3D, up: float, out: float) -> Dictionary:
	for k in range(60):
		await physics_frame
	var a := pl.global_position
	pl.launch(Vector3(out, up, 0.0))
	var high := a.y
	var air := 0.0
	var left := false
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var n := 0
	while n < 600:
		await physics_frame
		n += 1
		high = maxf(high, pl.global_position.y)
		air += dt
		if not left and not pl.is_on_floor():
			left = true
		elif left and pl.is_on_floor():
			break
	# the rest of the shove along the ground
	for k in range(60):
		await physics_frame
	var b := pl.global_position
	return {"far": Vector2(b.x - a.x, b.z - a.z).length(), "high": high - a.y, "air": air}
