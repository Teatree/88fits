## Pass 72, lane ITEMS: the basketball's colour, before and after the fix. Frames of a throw at Heat 0 / 5 / 10, the
## Alley-Oop ball cold and hot, Slam Dunk's cold and hot, from a close camera; each frame also measures the ball's own
## pixels (the mean colour in a small disc round the ball's screen point) and the run prints its materials, so "white"
## is a number and not only a look. A watchdog quits after `limit` seconds whatever happens; every wait is bounded.
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/_p72_items_ball_shot.gd -- out=<dir> [only=heat,oop,dunk] [zoom=0.5] [limit=150]
extends SceneTree

var _out := "user://p72_ball"
var _only: PackedStringArray = []
var _zoom := 0.5
var _limit := 150.0
var _run
var _reg
var _save
var g
var _heat := -1
var _log: FileAccess


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",", false)
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
		elif a.begins_with("limit="):
			_limit = float(a.substr(6))
	DirAccess.make_dir_recursive_absolute(_out)
	_log = FileAccess.open(_out.path_join("ball.log"), FileAccess.WRITE)
	process_frame.connect(_main, CONNECT_ONE_SHOT)
	process_frame.connect(_hold_heat)
	# the watchdog: whatever hangs, the run ends
	var t := create_timer(_limit, true, false, true)
	t.timeout.connect(_watchdog)


func _watchdog() -> void:
	_note("WATCHDOG: quit after %.0f s" % _limit)
	if _save != null and _save.has_method("end_sandbox"):
		_save.end_sandbox()
	quit(3)


func _note(s: String) -> void:
	print("p72_ball: ", s)
	if _log:
		_log.store_line(s)
		_log.flush()


func _hold_heat() -> void:
	if _heat >= 0 and _run != null:
		_run.heat = _heat


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _main() -> void:
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save = root.get_node("Save")
	_save.begin_sandbox()
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "basketball", "level": 1, "character": "fadeaway", "map": "red_canyon", "map_seed": 7}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	if g.camera:
		g.camera.zoom_override = _zoom
	await _wait(3.0)
	if _on("heat"):
		await _throw("basketball", 3, [], 0, "heat0")
		await _throw("basketball", 3, [], 5, "heat5")
		await _throw("basketball", 3, [], 10, "heat10")
	if _on("oop"):
		await _throw("basketball", 3, ["alley_oop"], 0, "oop0")
		await _throw("basketball", 3, ["alley_oop"], 10, "oop10")
	if _on("dunk"):
		await _throw("slam_dunk", 1, ["on_fire", "alley_oop", "rebound"], 0, "dunk0")
		await _throw("slam_dunk", 1, ["on_fire", "alley_oop", "rebound"], 10, "dunk10")
	if _on("fire"):
		await _throw("basketball", 3, ["on_fire"], 0, "fire0")
		await _throw("basketball", 3, ["on_fire"], 5, "fire5")
		await _throw("basketball", 3, ["on_fire"], 10, "fire10")
	if _on("free"):
		await _free_show()
	if _on("far"):
		if g.camera:
			g.camera.zoom_override = 1.0
		await _throw("basketball", 3, [], 0, "far_heat0")
		await _throw("basketball", 3, [], 10, "far_heat10")
		await _throw("basketball", 3, ["on_fire"], 10, "far_fire10")
		if g.camera:
			g.camera.zoom_override = _zoom
	_heat = -1
	_note("done")
	if _save.has_method("end_sandbox"):
		_save.end_sandbox()
	quit(0)


func _on(section: String) -> bool:
	return _only.is_empty() or _only.has(section)


func _build(wid: String, level: int, muts: Array, ahead: float, count := 5) -> void:
	_run.debug_clear_items()
	for m in muts:
		_run.debug_set_item("mutation", str(m), 1)
	var def = _reg.weapon(wid)
	_run.debug_set_item("evolution" if def.is_evolution else "weapon", wid, level)
	_run.build_changed.emit()
	var em = g.enemies
	em.kill_all(false)
	var here: Vector3 = g.player.global_position
	for k in range(count):
		var s := -2.0 + 4.0 * float(k) / maxf(float(count - 1), 1.0)
		em.spawn("skeleton", here + Vector3(s * 0.8, 0, -ahead - 0.8 * float(k % 2)), null, 1.0, 400.0)
	em._rebuild_grid()


func _throw(wid: String, level: int, muts: Array, heat: int, name: String, times: Array = [0.1, 0.2, 0.3, 0.45, 0.7]) -> void:
	_heat = heat
	await _build(wid, level, muts, 5.0)
	await _wait(0.6)
	var b = g._behaviors.get(wid)
	var frames := 0
	var last: float = b.cooldown_left if b else 0.0
	while frames < 600:
		await process_frame
		frames += 1
		if b and b.cooldown_left > last + 0.05:
			break
		if b:
			last = b.cooldown_left
	_note("%s heat %d shown %.2f (waited %d frames)" % [name, _run.heat, float(b.get("heat_level_shown")) if b else -1.0, frames])
	_dump_kinds(b)
	var f0 := Engine.get_process_frames()
	for k in range(times.size()):
		var want := int(round(float(times[k]) * 60.0))
		var guard := 0
		while Engine.get_process_frames() - f0 < want and guard < 600:
			await process_frame
			guard += 1
		_shot(name + "_t%02d" % k, b)


## Free Throw: an evade throws a ball at once (drawn in FREE_TINT before pass 72).
func _free_show() -> void:
	_heat = 0
	await _build("basketball", 3, ["free_throw"], 5.0)
	await _wait(0.6)
	var b = g._behaviors.get("basketball")
	if b == null:
		return
	b.cooldown_left = 5.0
	b.on_hero_evaded()
	_note("free throws %d" % int(b.get("free_throws")))
	_dump_kinds(b)
	var f0 := Engine.get_process_frames()
	for k in range(3):
		var want := int(round((0.08 + 0.12 * float(k)) * 60.0))
		var guard := 0
		while Engine.get_process_frames() - f0 < want and guard < 600:
			await process_frame
			guard += 1
		_shot("free_t%02d" % k, b)


## The materials of the kinds this weapon's balls are drawn in now.
func _dump_kinds(b) -> void:
	if b == null:
		return
	var pm = g.projectiles
	var seen := {}
	for i in range(pm.MAX):
		if pm.alive[i] == 1 and pm.weapon[i] == b.inst:
			seen[int(pm.kind[i])] = true
	for kh in b.get("_heat_kinds").keys():
		seen[int(kh)] = true
	for k in seen.keys():
		var kd: Dictionary = pm.kinds[k]
		var mesh: Mesh = (kd["mm"] as MultiMesh).mesh
		var over: Material = (kd["mmi"] as MultiMeshInstance3D).material_override
		var line := "  kind %d surfaces %d over %s" % [k, mesh.get_surface_count() if mesh else -1, _mat_s(over)]
		_note(line)
		if mesh:
			for s in range(mesh.get_surface_count()):
				_note("    s%d %s" % [s, _mat_s(mesh.surface_get_material(s))])


func _mat_s(m: Material) -> String:
	if m == null:
		return "null"
	if not (m is StandardMaterial3D):
		return m.get_class()
	var sm := m as StandardMaterial3D
	return "albedo %s vc %s emit %s %s x%.2f amb_off %s unshaded %s" % [sm.albedo_color.to_html(false), sm.vertex_color_use_as_albedo,
			sm.emission_enabled, sm.emission.to_html(false), sm.emission_energy_multiplier, sm.disable_ambient_light,
			sm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED]


## Saves the frame and measures the balls' pixels: the mean colour within a few pixels of each ball's screen point.
func _shot(name: String, b) -> void:
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var pm = g.projectiles
	var parts: Array = []
	if b and cam:
		for i in range(pm.MAX):
			if pm.alive[i] != 1 or pm.weapon[i] != b.inst:
				continue
			var p: Vector2 = cam.unproject_position(pm.pos[i])
			var rr := 7
			var acc := Color(0, 0, 0, 0)
			var n := 0
			for dy in range(-rr, rr + 1):
				for dx in range(-rr, rr + 1):
					if dx * dx + dy * dy > rr * rr:
						continue
					var x := int(p.x) + dx
					var y := int(p.y) + dy
					if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
						continue
					acc += img.get_pixel(x, y)
					n += 1
			if n > 0:
				var c := Color(acc.r / n, acc.g / n, acc.b / n)
				parts.append("ball@(%d,%d) %s h%.2f s%.2f v%.2f" % [int(p.x), int(p.y), c.to_html(false), c.h, c.s, c.v])
	_note("%s %s" % [name, " | ".join(parts)])
