## Pass 139 (lane AIM) capture: the aim wedge's tell for the Dragon's Breath and the Big Mouth (charging, ready, winding up,
## firing; both held at once) on Sundown and Nightfall, and a strip of eight frames across the Big Mouth's wind-up, in the
## arena under the aim at the game's own zoom. Each state is held by hand (the behaviour's fields set, its processing
## stopped) so the frame shows exactly that state. Run with --fixed-fps 60 so frames count time. Windowed:
##   GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 \
##       --path D:/_projects/88fits/game --log-file <abs> --script res://tools/_p139_AIM_shots.gd -- out=<dir> [zoom=0]
##       [only=breath,mouth,both,strip] [stages=0,1]
## Writes <out>/<stage>_<state>.png cropped round the Outlaw and his aim, and <out>/strip_<k>.png round the mouth. Every
## wait is bounded (a watchdog quits after WATCHDOG seconds). The save and the settings in memory go back as they were.
extends SceneTree

const WATCHDOG := 220.0
## the crop round the Outlaw (px at 1080x1920) and how far ahead of him its middle sits (m)
const CROP := Vector2i(1000, 1240)
const CROP_AHEAD := 3.2
const STRIP_CROP := Vector2i(440, 440)
const FACING := -0.6

var _out := "user://p139_aim"
var _zoom := 0.0
var _only: PackedStringArray = []
var _stages: Array = [0, 1]
var _run
var _save
var _settings
var _keep: Dictionary = {}
var _aim := true
var _show := true
var g
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("zoom="):
			_zoom = float(a.substr(5))
		elif a.begins_with("only="):
			_only = a.substr(5).split(",")
		elif a.begins_with("stages="):
			_stages = Array(a.substr(7).split(",")).map(func(x): return int(x))
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_watch)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _restore() -> void:
	if _save:
		_save.data = _keep
	if _settings:
		_settings.aim_mode = _aim
		_settings.show_aim = _show


func _watch() -> void:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG * 1000.0):
		print("p139_aim: watchdog, quitting")
		_restore()
		quit(3)


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _want(name: String) -> bool:
	return _only.is_empty() or _only.has(name)


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	_settings = root.get_node("Settings")
	_keep = _save.data.duplicate(true)
	_aim = bool(_settings.aim_mode)
	_show = bool(_settings.show_aim)
	_settings.aim_mode = true
	_settings.show_aim = true
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 11, "analytics": false}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _frames(150)
	g = current_scene
	if g == null or not g.has_method("set_paused"):
		print("p139_aim: no game scene")
		_restore()
		quit(1)
		return
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	if g.camera and _zoom > 0.0:
		g.camera.zoom_override = _zoom
	await _frames(60)
	for st: int in _stages:
		var tag := "sundown" if st == 0 else "nightfall"
		if st > 0:
			load("res://core/systems/StageLook.gd").call("of", g).show_stage(st, 0.0)
			await _frames(20)
		if _want("breath"):
			await _shot_breath(tag)
		if _want("mouth"):
			await _shot_mouth(tag)
		if _want("both"):
			await _shot_both(tag)
	if _want("strip"):
		await _shot_strip()
	print("p139_aim: done -> ", _out)
	_restore()
	quit(0)


## Arms `ids` (each at level 1) and nothing else, clears the crowd, stands the Outlaw still facing FACING.
func _arm(ids: Array) -> void:
	g.enemies.kill_all(false)
	g.projectiles.clear_all()
	_run.debug_clear_items()
	for id: String in ids:
		_run.debug_set_item("weapon", id, 1)
	_run.rebuild_sheets()
	_run.build_changed.emit()
	await _frames(1)
	for id: String in ids:
		var b := _b(id)
		if b:
			_idle(b)
	g.player.facing = FACING
	g.player.velocity = Vector3.ZERO
	await _frames(40)


## Nothing under way: no wind-up, beam or breath, the clock far off (it settles while it runs on).
func _idle(b: Node) -> void:
	b.set_process(true)
	b.cooldown_left = 99.0
	if "_windup_t" in b:
		b._windup_t = 0.0
		b._beam_t = 0.0
		if b._beam:
			b._beam.visible = false
	if b.has_method("burning") and b.burning():
		b._end()


func _b(id: String) -> Node:
	return g._behaviors.get(id)


## A charge held at `c` (0..1): the cooldown set to that share of a recovery, the behaviour stopped.
func _hold_charge(b: Node, c: float) -> void:
	b.set_process(true)
	var rec: float = maxf(float(b.stat("cooldown", 1.0)) - 2.5, 1.0)
	b._recover_len = rec
	b.cooldown_left = rec * (1.0 - c)
	if "_ready_for" in b:
		b._ready_for = 0.0
	if "_armed" in b:
		b._armed = false
	b.set_process(false)


## Ready and waiting: the cooldown out, nobody in the cone, the behaviour stopped.
func _hold_ready(b: Node) -> void:
	b.cooldown_left = 0.0
	b.set_process(false)


## Creatures standing still ahead of the Outlaw (metres out along his facing, metres to his right).
func _crowd(spots: Array) -> void:
	var em = g.enemies
	var here: Vector3 = g.player.global_position
	var f: Vector3 = g.player.forward()
	var right := f.cross(Vector3.UP)
	for p: Vector2 in spots:
		var i: int = em.spawn("skeleton", here + f * p.x + right * p.y, null, 1.0, 400.0)
		if i >= 0:
			em.speed[i] = 0.0
	em._rebuild_grid()
	await _frames(70)


func _shot(name: String, centre: Vector3 = Vector3.INF, size: Vector2i = CROP) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var cam := root.get_viewport().get_camera_3d()
	var at := centre
	if at == Vector3.INF:
		at = g.player.global_position + g.player.forward() * CROP_AHEAD
	var px := cam.unproject_position(at) if cam else Vector2(img.get_width() * 0.5, img.get_height() * 0.5)
	var x := clampi(int(px.x) - size.x / 2, 0, maxi(img.get_width() - size.x, 0))
	var y := clampi(int(px.y) - size.y / 2, 0, maxi(img.get_height() - size.y, 0))
	var sub := img.get_region(Rect2i(x, y, mini(size.x, img.get_width()), mini(size.y, img.get_height())))
	sub.save_png(_out.path_join(name + ".png"))
	print("p139_aim: ", name)


func _shot_breath(tag: String) -> void:
	await _arm(["dragons_breath"])
	var b := _b("dragons_breath")
	if b == null:
		print("p139_aim: no breath")
		return
	for c: float in [0.3, 0.7]:
		_hold_charge(b, c)
		await _frames(6)
		_shot("%s_breath_charge%02d" % [tag, int(c * 100.0)])
	_hold_ready(b)
	await _frames(30)
	_shot("%s_breath_ready" % tag)
	b.set_process(true)
	b.cooldown_left = 99.0
	await _crowd([Vector2(3.0, 0.0), Vector2(4.0, 0.8)])
	b.cooldown_left = 0.0
	await _frames(30)
	_shot("%s_breath_firing" % tag)
	await _frames(int(b.breath_seconds() * 60.0) + 10)
	_shot("%s_breath_after" % tag)


func _shot_mouth(tag: String) -> void:
	await _arm(["big_mouth"])
	var b := _b("big_mouth")
	if b == null:
		print("p139_aim: no mouth")
		return
	_hold_charge(b, 0.4)
	await _frames(6)
	_shot("%s_mouth_charge40" % tag)
	_hold_ready(b)
	await _frames(30)
	_shot("%s_mouth_ready" % tag)
	b.set_process(true)
	b.cooldown_left = 99.0
	b._armed = false
	await _crowd([Vector2(5.0, 0.0), Vector2(8.0, 0.3)])
	b.cooldown_left = 0.0
	await _frames(int(b.windup_seconds() * 60.0 * 0.6))
	b.set_process(false)
	await _frames(3)
	_shot("%s_mouth_windup" % tag)
	b.set_process(true)
	await _frames(int(b.windup_seconds() * 60.0 * 0.4) + 48)
	_shot("%s_mouth_firing" % tag)


func _shot_both(tag: String) -> void:
	await _arm(["dragons_breath", "big_mouth"])
	var br := _b("dragons_breath")
	var mo := _b("big_mouth")
	if br == null or mo == null:
		print("p139_aim: both not armed")
		return
	_hold_charge(br, 0.55)
	_hold_charge(mo, 0.35)
	await _frames(6)
	_shot("%s_both_charge" % tag)
	_hold_ready(br)
	_hold_ready(mo)
	await _frames(30)
	_shot("%s_both_ready" % tag)
	br.set_process(true)
	mo.set_process(true)


## Eight frames across the Big Mouth's wind-up (Sundown), from its first frame to the beam leaving, round the mouth.
func _shot_strip() -> void:
	if _stages.has(1):
		load("res://core/systems/StageLook.gd").call("of", g).show_stage(0, 0.0)
		await _frames(20)
	await _arm(["big_mouth"])
	var b := _b("big_mouth")
	if b == null:
		return
	await _crowd([Vector2(6.0, 0.0)])
	b.cooldown_left = 0.0
	await _frames(1)
	var n := int(round(b.windup_seconds() * 60.0))
	var step := maxi(int(round(float(n) / 7.0)), 1)
	for k in range(8):
		var m: Vector3 = b.muzzle()
		_shot("strip_%d" % k, m + Vector3(0, -0.3, 0), STRIP_CROP)
		await _frames(step)
