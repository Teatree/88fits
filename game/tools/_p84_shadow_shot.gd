## Pass 84 (the lead) scratch: creature shadows over the whole screen with a crowd over SHADOW_BUDGET. Spawns `n`
## skeletons in a grid over the visible ground (up the screen, the sides, below the hero), freezes them, counts the
## shadows drawn against the creatures on screen and saves the frame.
##   bash tools/godot.sh --audio-driver Dummy --fixed-fps 60 --resolution 1080x1920 --path game --script res://tools/_p84_shadow_shot.gd -- out=<dir> [n=200]
extends SceneTree

const WATCHDOG_S := 120.0

var _out := "user://p84_shadow"
var _n := 200
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("n="):
			_n = int(a.substr(2))
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG_S * 1000.0):
		print("p84_shadow: WATCHDOG")
		quit(2)
	return false


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _main() -> void:
	var run = root.get_node("Run")
	var save = root.get_node("Save")
	var keep: Dictionary = save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	var g = current_scene
	if g == null or not g.has_method("set_paused"):
		print("p84_shadow: no game scene")
		quit(1)
		return
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	await _wait(0.5)
	var em = g.enemies
	em.kill_all(false)
	await _wait(0.3)
	var p: Vector3 = g.player.global_position
	var cols := 14
	var rows := maxi(_n / cols, 1)
	for r in range(rows):
		for c in range(cols):
			var x := p.x - 11.0 + 22.0 * float(c) / float(cols - 1)
			var z := p.z - 30.0 + 38.0 * float(r) / float(maxi(rows - 1, 1))
			em.spawn("skeleton", Vector3(x, 0.0, z))
	await _wait(1.2)
	for i in range(em.pos.size()):
		if em.is_alive(i):
			em.speed[i] = 0.0
	await _wait(0.4)
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var alive := 0
	var seen := 0
	for i in range(em.pos.size()):
		if em.is_alive(i):
			alive += 1
			if cam.is_position_in_frustum(em.pos[i]):
				seen += 1
	var sh: int = em._shadow_mm.visible_instance_count
	print("p84_shadow: alive %d on screen %d shadows %d" % [alive, seen, sh])
	root.get_viewport().get_texture().get_image().save_png(_out.path_join("crowd.png"))
	save.data = keep
	quit(0)
