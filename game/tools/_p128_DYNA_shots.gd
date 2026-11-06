## Pass 128 (lane DYNA) capture: look B's eight dynamite models in the game, each thrown by the real weapon with its
## mutations (in a given order), filmed once in the air and once lying on the sand with its spark lit, under a stage's
## filter. Windowed, fixed 60 fps, bounded waits and a watchdog:
##   GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --fixed-fps 60 --resolution 1080x1920 --path game
##       --script res://tools/_p128_DYNA_shots.gd -- out=<dir> [stage=0] [zoom=0.6] [crop=420] [only=stick,bundle_wire_tar] [look=B]
## Writes <out>/s<stage>_<combo>_fly.png and _lie.png (crop px round the shot), <out>/s<stage>_<combo>_full.png (the whole
## frame at half size, lying) and <out>/s<stage>.txt (per combo: the mutations, the model the Lobber chose).
## stage: 0 Sundown (no filter), 1 Nightfall, 2 The Dust Bowl, 3 Blood Moon. zoom 0 = the run's own camera.
extends SceneTree

const WATCHDOG_S := 200.0
## combo -> the mutations, in the order they are taken (wire_tar and bundle_wire_tar take them in two different orders)
const COMBOS := {
	"stick": [],
	"stick_wire": ["frag"],
	"stick_tar": ["sticky"],
	"stick_wire_tar": ["sticky", "frag"],
	"bundle": ["new_equipment"],
	"bundle_wire": ["frag", "new_equipment"],
	"bundle_tar": ["new_equipment", "sticky"],
	"bundle_wire_tar": ["frag", "sticky", "new_equipment"],
}

var _out := "user://p128_dyna"
var _look := "B"
var _stage := 0
var _zoom := 0.6
var _crop := 420
var _only: Array = []
var _run
var _save
var _reg
var g
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("look="):
			_look = a.substr(5)
		elif a.begins_with("stage="):
			_stage = int(a.substr(6))
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
		elif a.begins_with("crop="):
			_crop = int(a.substr(5))
		elif a.begins_with("only="):
			_only = Array(a.substr(5).split(",", false))
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG_S * 1000.0):
		print("p128_dyna: WATCHDOG, quitting")
		quit(2)
	return false


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _frames_wait(n: int) -> void:
	for i in range(n):
		await process_frame


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	_reg = root.get_node("Registry")
	var keep: Dictionary = _save.data.duplicate(true)
	if not _save.data.get("item_looks") is Dictionary:
		_save.data["item_looks"] = {}
	_save.data["item_looks"]["lob_grenade"] = _look
	if _reg.has_method("apply_item_looks"):
		_reg.apply_item_looks()
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	if g == null or not g.has_method("set_paused"):
		print("p128_dyna: no game scene")
		_save.data = keep
		quit(1)
		return
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	if g.camera and _zoom > 0.0:
		g.camera.zoom_override = _zoom
	if _stage > 0:
		load("res://core/systems/StageLook.gd").of(g).show_stage(_stage, 0.0)
	await _wait(1.0)
	var log := FileAccess.open(_out.path_join("s%d.txt" % _stage), FileAccess.WRITE)
	for combo: String in COMBOS.keys():
		if not _only.is_empty() and not _only.has(combo):
			continue
		var line: String = await _film(combo)
		log.store_line(line)
		print("p128_dyna: ", line)
	log.close()
	print("p128_dyna: done -> ", _out)
	_save.data = keep
	quit(0)


func _film(combo: String) -> String:
	var muts: Array = COMBOS[combo]
	_run.debug_clear_items()
	for m: String in muts:
		_run.debug_set_item("mutation", m, 1)
	_run.debug_set_item("weapon", "lob_grenade", 3)
	_run.rebuild_sheets()
	_run.build_changed.emit()
	await _wait(0.6)
	var b = g._behaviors.get("lob_grenade")
	if b == null:
		return "%s: no behaviour" % combo
	b.cooldown_left = 99.0
	var em = g.enemies
	var pm = g.projectiles
	em.kill_all(false)
	pm.clear_all()
	await _frames_wait(30)
	var here: Vector3 = g.player.global_position
	var centre := here + Vector3(0.8, 0, -5.0)
	var mine: Array = []
	for k in range(3):
		var a := TAU * float(k) / 3.0
		var i: int = em.spawn("skeleton", centre + Vector3(cos(a), 0, sin(a)) * 0.5, null, 1.0, 400.0)
		if i >= 0:
			em.speed[i] = 0.0
			mine.append(i)
	em._rebuild_grid()
	# (they rise out of the sand first; a rising one is no target yet)
	await _frames_wait(70)
	var inst = _run.weapon_instance("lob_grenade")
	var model_path := str(b.call("model_path"))
	var before := {}
	for j in range(pm.MAX):
		if pm.alive[j] == 1:
			before[j] = true
	b.cooldown_left = 1.0 / 60.0
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var shot := -1
	var flown := false
	var lain := -1
	var result := "%s muts %s model %s" % [combo, str(muts), model_path]
	for fr in range(360):
		await process_frame
		if shot < 0:
			for j in range(pm.MAX):
				if pm.alive[j] == 1 and not before.has(j) and pm.weapon[j] == inst and (pm.extra[j] as Dictionary).has("fz"):
					shot = j
					b.cooldown_left = 99.0
					# the crowd goes without a trace: the stick lies where it lands (Sticky finds nobody to ride)
					for i: int in mine:
						em.despawn(i)
					break
			continue
		if pm.alive[shot] != 1 or pm.weapon[shot] != inst:
			result += " GONE at f%d" % fr
			break
		var ex: Dictionary = pm.extra[shot]
		var at: Vector3 = pm.pos[shot]
		if not flown and pm.vel[shot].y < 0.5:
			flown = true
			_grab(cam, at).save_png(_out.path_join("s%d_%s_fly.png" % [_stage, combo]))
		if ex.has("lie_t"):
			if lain < 0:
				lain = fr
			if fr - lain == 14:
				var whole := root.get_viewport().get_texture().get_image()
				_crop_at(whole, cam, at).save_png(_out.path_join("s%d_%s_lie.png" % [_stage, combo]))
				whole.resize(whole.get_width() / 2, whole.get_height() / 2, Image.INTERPOLATE_BILINEAR)
				whole.save_png(_out.path_join("s%d_%s_full.png" % [_stage, combo]))
				result += " lay at f%d" % lain
				break
	b.cooldown_left = 99.0
	pm.clear_all()
	await _frames_wait(20)
	return result


func _grab(cam: Camera3D, at: Vector3) -> Image:
	return _crop_at(root.get_viewport().get_texture().get_image(), cam, at)


func _crop_at(img: Image, cam: Camera3D, at: Vector3) -> Image:
	if cam == null:
		return img
	var sp: Vector2 = cam.unproject_position(at)
	var x := clampi(int(sp.x) - _crop / 2, 0, img.get_width() - _crop)
	var y := clampi(int(sp.y) - _crop / 2, 0, img.get_height() - _crop)
	return img.get_region(Rect2i(x, y, _crop, _crop))
