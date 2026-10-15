## Pass 80 (lane OASIS): top-down overviews of Red Canyon for a few seeds (the whole arena from straight above,
## orthographic), one PNG a seed, so the oases' places can be checked by eye. Windowed; every wait is bounded (a frame
## cap a seed and a watchdog for the whole run).
##   bash tools/godot.sh --audio-driver Dummy --resolution 1024x1024 --path game --script res://tools/_p80_OASIS_overview.gd -- out=<dir> seeds=5,6,7,11,88 [size=150]
extends SceneTree

var _out := "user://p80_oasis"
var _seeds: Array = [5, 6, 7, 11, 88]
var _size := 150.0
var _focus := -1   # focus=k: centre on lake k (size= then the width in metres)
var _k := -1
var _frames := 0
var _map: Node3D
var _cam: Camera3D
var _t0 := 0
const SETTLE := 6
const WATCHDOG_MS := 180000


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("seeds="):
			_seeds = Array(a.substr(6).split(",")).map(func(s): return int(s))
		elif a.begins_with("size="):
			_size = float(a.substr(5))
		elif a.begins_with("focus="):
			_focus = int(a.substr(6))
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_tick)


func _tick() -> void:
	if Time.get_ticks_msec() - _t0 > WATCHDOG_MS:
		print("oasis_overview: watchdog, quitting")
		quit(2)
		return
	if _map == null:
		_k += 1
		if _k >= _seeds.size():
			var run = root.get_node("Run")
			run.forced_map_seed = 0
			run.end()
			print("oasis_overview: done")
			quit(0)
			return
		_build(int(_seeds[_k]))
		_frames = 0
		return
	_frames += 1
	if _frames < SETTLE:
		return
	var img := root.get_texture().get_image()
	var n: int = (_map.call("lakes") as Array).size()
	var path := "%s/overview_seed%d_%dlakes%s.png" % [_out, int(_seeds[_k]), n, ("_lake%d" % _focus) if _focus >= 0 else ""]
	img.save_png(path)
	print("oasis_overview: ", path, " lakes ", JSON.stringify((_map.call("lakes") as Array).map(func(l): return [snappedf(l["center"].x, 0.1), snappedf(l["center"].y, 0.1), snappedf(l["radius"], 0.01)])))
	_map.queue_free()
	_cam.queue_free()
	_map = null


func _build(ms: int) -> void:
	var run = root.get_node("Run")
	var reg = root.get_node("Registry")
	run.forced_map_seed = ms
	run.end()
	run.start(reg.character("drifter"), reg.map("red_canyon"))
	_map = (reg.map("red_canyon").scene as PackedScene).instantiate()
	root.add_child(_map)
	# no haze from up here (the run's fog tints the water grey at this height)
	for we in _map.find_children("*", "WorldEnvironment", true, false):
		(we as WorldEnvironment).environment.fog_enabled = false
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = _size
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_cam.far = 400.0
	_cam.position = Vector3(0, 160, 0)
	var lakes: Array = _map.call("lakes")
	if _focus >= 0 and _focus < lakes.size():
		var c: Vector2 = (lakes[_focus] as Dictionary)["center"]
		_cam.position = Vector3(c.x, 160, c.y)
	_cam.rotation_degrees = Vector3(-90, 0, 0)
	root.add_child(_cam)
	_cam.make_current()
