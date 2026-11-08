## Pass 136 (lane MELEE) capture: the Sabre's swings and the Spear's thrusts drawn as effects (MeleeFx), each case held
## at points through one stroke at the game's real camera, three creatures standing in front. The game is held
## (Game.paused, so nothing else moves) and the behaviour's clock is stepped by hand to each time. Windowed, bounded:
##   GODOT_TIMEOUT=300 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path game
##       --script res://tools/_p136_MELEE_shots.gd -- out=<dir> [stage=0|3] [only=s1,p1] [crop=760] [zoom=0] [aim=1]
## Writes <out>/s<stage>_<case>_<k>.png (crop px round the Outlaw, k = the k-th time), <out>/s<stage>_<case>_full.png
## (one whole frame at half size) and <out>/s<stage>.txt (per case: the effects counted, the stroke's aim).
extends SceneTree

const WATCHDOG_S := 280.0
const DT := 1.0 / 60.0
## case -> [weapon id, level, mutations, times (s into the stroke), facing (radians), extra]
const CASES := {
	"s1": ["sabre", 1, [], [0.08, 0.12, 0.16, 0.22, 0.28], 0.35, {}],
	"s5": ["sabre", 5, [], [0.12, 0.2, 0.3, 0.42, 0.52], 0.35, {}],
	"sct": ["sabre", 3, ["critical_thinking"], [0.1, 0.14, 0.2, 0.26], 0.35, {}],
	"srip": ["sabre", 1, ["riposte"], [0.1, 0.18, 0.24, 0.28, 0.32], 0.35, {}],
	"sflu": ["sabre", 3, ["flurry"], [0.12, 0.24, 0.4, 0.56], 0.35, {}],
	"sww": ["whirlwind", 1, [], [0.08, 0.12, 0.16, 0.22, 0.3], 0.35, {}],
	"p1": ["pike", 1, [], [0.15, 0.18, 0.21, 0.25, 0.32, 0.4], 0.25, {}],
	"p5": ["pike", 5, [], [0.18, 0.21, 0.26, 0.34], 0.25, {}],
	"phs": ["pike", 3, ["heartseeker"], [0.18, 0.21, 0.26, 0.34], 0.25, {"crit_count": 3}],
	"phw": ["pike", 3, ["heartseeker"], [0.21, 0.26], 0.25, {"crit_count": 2}],
	"pws": ["pike", 3, ["pike_sweep"], [0.1, 0.16, 0.22, 0.3], 0.25, {}],
	"pst": ["pike", 3, ["stunning_thrust"], [0.21, 0.26, 0.3], 0.25, {"stun": 1.0}],
	"ptl": ["thunder_lance", 1, [], [0.12, 0.2, 0.26, 0.6, 0.66, 0.72, 0.85], 0.25, {}],
}

var _out := "user://p136_melee"
var _stage := 0
var _crop := 760
var _zoom := 0.0
var _aim := true
var _only: Array = []
var _run
var _save
var _settings
var g
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("stage="):
			_stage = int(a.substr(6))
		elif a.begins_with("crop="):
			_crop = int(a.substr(5))
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
		elif a.begins_with("aim="):
			_aim = a.substr(4) != "0"
		elif a.begins_with("only="):
			_only = Array(a.substr(5).split(",", false))
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG_S * 1000.0):
		print("p136_melee: WATCHDOG, quitting")
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
	_settings = root.get_node("Settings")
	var keep: Dictionary = _save.data.duplicate(true)
	var keep_aim: bool = _settings.aim_mode
	_settings.aim_mode = _aim
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "ironwood", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	if g == null or not g.has_method("set_paused"):
		print("p136_melee: no game scene")
		_finish(keep, keep_aim, 1)
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
	for c: String in CASES.keys():
		if not _only.is_empty() and not _only.has(c):
			continue
		var line: String = await _film(c)
		log.store_line(line)
		print("p136_melee: ", line)
	log.close()
	print("p136_melee: done -> ", _out)
	_finish(keep, keep_aim, 0)


func _finish(keep: Dictionary, keep_aim: bool, code: int) -> void:
	_save.data = keep
	_settings.aim_mode = keep_aim
	quit(code)


func _film(c: String) -> String:
	var spec: Array = CASES[c]
	var wid: String = spec[0]
	var lvl: int = spec[1]
	var muts: Array = spec[2]
	var times: Array = spec[3]
	var facing: float = spec[4]
	var extra: Dictionary = spec[5]
	g.paused = false
	_run.debug_clear_items()
	for m: String in muts:
		_run.debug_set_item("mutation", m, 1)
	_run.debug_set_item("weapon", wid, lvl)
	_run.rebuild_sheets()
	_run.build_changed.emit()
	await _wait(0.5)
	var b = g._behaviors.get(wid)
	if b == null:
		return "%s: no behaviour" % c
	b.cooldown_left = 99.0
	var em = g.enemies
	em.kill_all(false)
	await _frames_wait(20)
	var p: Node3D = g.player
	p.facing = facing
	var fwd: Vector3 = p.forward()
	var here: Vector3 = p.global_position
	var side := Vector3(-fwd.z, 0, fwd.x)
	var mine: Array = []
	var reach: float = b.stat("range", 2.6)
	# three standing in front: one on the line, two a little to the sides
	for k in range(3):
		var at: Vector3 = here + fwd * reach * (0.55 + 0.2 * k) + side * (float(k) - 1.0) * reach * 0.35
		var i: int = em.spawn("skeleton", at, null, 1.0, 400.0)
		if i >= 0:
			em.speed[i] = 0.0
			mine.append(i)
	em._rebuild_grid()
	await _frames_wait(70)
	if extra.has("stun"):
		var th: Dictionary = (b.inst.params.get("thrust", {}) as Dictionary).duplicate(true)
		th["stun"] = {"chance": 1.0, "seconds": 1.0}
		b.inst.params["thrust"] = th
	# hold the world, then one stroke by hand
	g.paused = true
	p.facing = facing
	await _frames_wait(3)
	if extra.has("crit_count"):
		b.crit_count = int(extra["crit_count"])
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	b.cooldown_left = 99.0
	b._fire()
	var t := 0.0
	var k := 0
	var result := "%s: %s L%d %s" % [c, wid, lvl, str(muts)]
	for want: float in times:
		while t + DT * 0.5 < want:
			b._tick(DT)
			t += DT
		await _frames_wait(2)
		var img := root.get_viewport().get_texture().get_image()
		_crop_at(img, cam, here + Vector3(0, 0.5, 0) + fwd * reach * 0.35).save_png(_out.path_join("s%d_%s_%d.png" % [_stage, c, k]))
		if k == 1:
			var whole := img.duplicate() as Image
			whole.resize(whole.get_width() / 2, whole.get_height() / 2, Image.INTERPOLATE_BILINEAR)
			whole.save_png(_out.path_join("s%d_%s_full.png" % [_stage, c]))
		k += 1
	var fx = b.effects() if b.has_method("effects") else null
	if fx:
		result += " arcs %d thrusts %d flashes %d" % [fx.arcs_made, fx.thrusts_made, fx.flashes_made]
	result += " fx_on %s target %d stun_rings %d bolts %d" % [str(b.fx_on()), b.target, b.stun_rings, b.tip_bolts]
	# let it finish
	for q in range(90):
		b._tick(DT)
	g.paused = false
	for i: int in mine:
		em.despawn(i)
	await _frames_wait(10)
	return result


func _crop_at(img: Image, cam: Camera3D, at: Vector3) -> Image:
	if cam == null:
		return img
	var sp: Vector2 = cam.unproject_position(at)
	var w := mini(_crop, img.get_width())
	var h := mini(_crop, img.get_height())
	var x := clampi(int(sp.x) - w / 2, 0, img.get_width() - w)
	var y := clampi(int(sp.y) - h / 2, 0, img.get_height() - h)
	return img.get_region(Rect2i(x, y, w, h))
