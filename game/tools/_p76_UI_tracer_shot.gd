## Pass 76 (lane UI) scratch capture: the Revolver's tracer on the sand, frame by frame after a pull, plain, with Silver
## Bullet and with Venom Rounds (Garry: "Make the revolver basic projectile trail thing be a dim red instead of yellow.
## It's just not very visible right now. Make the trail a bit thicker too"). In the debug arena, a row of tough
## skeletons up the screen. Windowed, fixed 60 fps, bounded waits and a watchdog:
##   godot --audio-driver Dummy --fixed-fps 60 --resolution 1080x1920 --path game --script res://tools/_p76_UI_tracer_shot.gd -- out=<dir> [zoom=1.0] [frames=4,8,12,18]
## Writes <out>/<variant>_f<frame>.png (a 900 x 1100 crop from the hero to the skeletons) and <out>/<variant>_full.png.
extends SceneTree

const WATCHDOG_S := 120.0
const CROP := Vector2i(900, 1100)

var _out := "user://p76_ui_tracer"
var _zoom := 1.0
var _frames: Array = [4, 8, 12, 18]
var _run
var _save
var g
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
		elif a.begins_with("frames="):
			_frames = []
			for s in a.substr(7).split(","):
				_frames.append(int(s))
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG_S * 1000.0):
		print("p76_ui_tracer: WATCHDOG, quitting")
		quit(2)
	return false


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 3, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	if g == null or not g.has_method("set_paused"):
		print("p76_ui_tracer: no game scene")
		_save.data = keep
		quit(1)
		return
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	if g.camera:
		g.camera.zoom_override = _zoom
	await _wait(3.2)
	g.hud._banner.visible = false
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	for variant in ["plain", "silver_bullet", "venom_rounds"]:
		_run.debug_clear_items()
		_run.debug_set_item("weapon", "revolver", 3)
		if variant != "plain":
			_run.debug_set_item("mutation", variant, 1)
		_run.build_changed.emit()
		var em = g.enemies
		em.kill_all(false)
		var here: Vector3 = g.player.global_position
		for k in range(5):
			var s := -2.0 + 4.0 * float(k) / 4.0
			em.spawn("skeleton", here + Vector3(s, 0, -9.0 - 0.6 * float(k % 2)), null, 1.0, 400.0)
		em._rebuild_grid()
		await _wait(1.2)
		var b = g._behaviors.get("revolver")
		if b == null:
			print("p76_ui_tracer: no revolver behaviour")
			break
		# the next pull in 3 frames; frames counted from it
		b.cooldown_left = 3.0 / 60.0
		var fr := 0
		var last: int = int(_frames.max())
		var full_at: int = int(_frames[1]) if _frames.size() > 1 else int(_frames[0])
		while fr <= last + 3:
			await process_frame
			fr += 1
			if _frames.has(fr - 3):
				var img := root.get_viewport().get_texture().get_image()
				var a: Vector2 = cam.unproject_position(g.player.global_position)
				var t: Vector2 = cam.unproject_position(here + Vector3(0, 0, -9.0))
				var mid := (a + t) * 0.5
				var x := clampi(int(mid.x) - CROP.x / 2, 0, img.get_width() - CROP.x)
				var y := clampi(int(mid.y) - CROP.y / 2, 0, img.get_height() - CROP.y)
				img.get_region(Rect2i(x, y, CROP.x, CROP.y)).save_png(_out.path_join("%s_f%02d.png" % [variant, fr - 3]))
				if fr - 3 == full_at:
					img.save_png(_out.path_join("%s_full.png" % variant))
		b.cooldown_left = 99.0
		await _wait(1.6)
	_save.data = keep
	print("p76_ui_tracer: done -> ", _out)
	quit(0)
