## Pass 139 (lane SWING) capture: the Sabre's swing on uneven sand, before and after the arc was laid on the ground
## (_mfx.ground_follow), and pass 139's alternative (no depth test) for comparison. Built on _p138_MELEE_shots.gd: the
## game is held (Game.paused) and the behaviour's clock stepped by hand. It first scans the map round its middle for
## spots (the steepest 3.5 m disc, the sharpest crest, the flattest) and stands the Outlaw on each, facing uphill.
##   GODOT_TIMEOUT=300 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path game --log-file <f>
##       --script res://tools/_p139_SWING_shots.gd -- out=<dir> [stages=0,3] [modes=before,after,nodepth]
##       [only=slope,crest,flat,crowd,classic,cel,whirl,sweep,down] [crop=760]
## Writes <out>/s<stage>_<case>_<mode>_<k>.png (crop px round the Outlaw) and <out>/spots.txt (the spots, their height
## range, the fit's numbers).
extends SceneTree

const WATCHDOG_S := 290.0
const DT := 1.0 / 60.0
## case -> [spot, weapon id, level, mutations, fx_style ("" = the weapon's), crowd, facing ("up", "down", "across")]
const CASES := {
	"slope": ["slope", "sabre", 1, [], "", 0, "up"],
	"down": ["slope", "sabre", 1, [], "", 0, "down"],
	"crest": ["crest", "sabre", 1, [], "", 0, "up"],
	"flat": ["flat", "sabre", 1, [], "", 0, "up"],
	"crowd": ["slope", "sabre", 3, [], "", 9, "up"],
	"classic": ["slope", "sabre", 1, [], "classic", 0, "across"],
	"cel": ["slope", "sabre", 1, [], "cel", 0, "across"],
	"whirl": ["slope", "whirlwind", 1, [], "", 0, "up"],
	"sweep": ["bank", "pike", 3, ["pike_sweep"], "", 0, "up"],
	"away": ["flat", "sabre", 1, [], "", 0, "away"],
	"away_slope": ["slope", "sabre", 1, [], "", 0, "away"],
	"toward": ["slope", "sabre", 1, [], "", 0, "toward"],
	"crowd_away": ["flat", "sabre", 3, [], "", 9, "away"],
}
const TIMES := [0.1, 0.18, 0.3]

var _out := "user://p139_swing"
var _stages: Array = [0, 3]
var _modes: Array = ["before", "after", "nodepth"]
var _crop := 760
var _only: Array = []
var _run
var _save
var _settings
var g
var _t0 := 0
var _spots: Dictionary = {}
var _nodepth: Dictionary = {}
## core/systems/MeleeFx.gd, loaded (it names the Run autoload, so not by its class name here)
var _mfx


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("stages="):
			_stages = Array(a.substr(7).split(",", false)).map(func(x: String) -> int: return int(x))
		elif a.begins_with("modes="):
			_modes = Array(a.substr(6).split(",", false))
		elif a.begins_with("crop="):
			_crop = int(a.substr(5))
		elif a.begins_with("only="):
			_only = Array(a.substr(5).split(",", false))
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG_S * 1000.0):
		print("p139_swing: WATCHDOG, quitting")
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
	_mfx = load("res://core/systems/MeleeFx.gd")
	var keep: Dictionary = _save.data.duplicate(true)
	var keep_aim: bool = _settings.aim_mode
	_settings.aim_mode = true
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "ironwood", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	if g == null or not g.has_method("set_paused"):
		print("p139_swing: no game scene")
		_finish(keep, keep_aim, 1)
		return
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	# the damage numbers hide the swing in the crowd's shots
	if g.get("damage_numbers"):
		g.damage_numbers.suppressed = true
	_find_spots()
	var log := FileAccess.open(_out.path_join("spots.txt"), FileAccess.WRITE)
	for k: String in _spots.keys():
		log.store_line("%s: %s" % [k, str(_spots[k])])
	for st: int in _stages:
		load("res://core/systems/StageLook.gd").of(g).show_stage(st, 0.0)
		await _wait(0.6)
		for c: String in CASES.keys():
			if not _only.is_empty() and not _only.has(c):
				continue
			var line: String = await _film(st, c)
			log.store_line(line)
			print("p139_swing: ", line)
	log.close()
	print("p139_swing: done -> ", _out)
	_finish(keep, keep_aim, 0)


func _finish(keep: Dictionary, keep_aim: bool, code: int) -> void:
	_mfx.ground_follow = true
	_save.data = keep
	_settings.aim_mode = keep_aim
	quit(code)


## The spots: on a 2 m grid within 34 m of the middle, away from water, the disc of 3.5 m whose height range is the
## largest (slope), whose middle stands highest over its ring (crest), the smallest range (flat), and the steepest at
## the dry river's bank (bank: the largest range where the middle is below its ring, a dip).
func _find_spots() -> void:
	var m = g.map
	var best := {"slope": [-1.0, Vector3.ZERO], "crest": [-1.0, Vector3.ZERO], "flat": [-1e9, Vector3.ZERO], "bank": [-1.0, Vector3.ZERO]}
	var x := -34.0
	while x <= 34.0:
		var z := -34.0
		while z <= 34.0:
			var c := Vector3(x, m.height_at(x, z), z)
			z += 2.0
			if Vector2(c.x, c.z).length() > 34.0 or Vector2(c.x, c.z).length() < 4.0:
				continue
			if m.has_method("in_water") and m.in_water(c):
				continue
			var lo := c.y
			var hi := c.y
			var ring := 0.0
			for k in range(12):
				var a := TAU * float(k) / 12.0
				for r: float in [1.75, 3.5]:
					var h: float = m.height_at(c.x + cos(a) * r, c.z + sin(a) * r)
					lo = minf(lo, h)
					hi = maxf(hi, h)
					if r > 3.0:
						ring += h / 12.0
			var span := hi - lo
			if span > float(best["slope"][0]) and c.y - ring > -0.15 and c.y - ring < 0.15:
				best["slope"] = [span, c]
			if c.y - ring > float(best["crest"][0]):
				best["crest"] = [c.y - ring, c]
			if -span > float(best["flat"][0]):
				best["flat"] = [-span, c]
			if span > float(best["bank"][0]) and c.y - ring < -0.15:
				best["bank"] = [span, c]
		x += 2.0
	for k: String in best.keys():
		var c: Vector3 = best[k][1]
		var grad := Vector2(m.height_at(c.x + 1.0, c.z) - m.height_at(c.x - 1.0, c.z), m.height_at(c.x, c.z + 1.0) - m.height_at(c.x, c.z - 1.0)) * 0.5
		_spots[k] = {"at": c, "score": snappedf(float(best[k][0]), 0.01), "grad": grad}


func _facing_for(spot: Dictionary, how: String) -> float:
	# away from the camera (up the screen), towards it
	if how == "away":
		return 0.0
	if how == "toward":
		return PI
	var grad: Vector2 = spot["grad"]
	if grad.length() < 0.01:
		return 0.35
	var want := Vector3(grad.x, 0, grad.y).normalized()
	if how == "down":
		want = -want
	elif how == "across":
		want = Vector3(-want.z, 0, want.x)
	# forward() = (-sin f, 0, -cos f)
	return atan2(-want.x, -want.z)


func _film(st: int, c: String) -> String:
	var spec: Array = CASES[c]
	var spot: Dictionary = _spots[spec[0]]
	var wid: String = spec[1]
	var lvl: int = spec[2]
	var muts: Array = spec[3]
	var style: String = spec[4]
	var crowd: int = spec[5]
	g.paused = false
	_run.debug_clear_items()
	for mu: String in muts:
		_run.debug_set_item("mutation", mu, 1)
	_run.debug_set_item("weapon", wid, lvl)
	_run.rebuild_sheets()
	_run.build_changed.emit()
	await _wait(0.4)
	var b = g._behaviors.get(wid)
	if b == null:
		return "%s: no behaviour" % c
	b.cooldown_left = 99.0
	if style != "":
		b.inst.params["fx_style"] = style
	var em = g.enemies
	em.kill_all(false)
	var p: Node3D = g.player
	var at: Vector3 = spot["at"]
	p.global_position = Vector3(at.x, g.map.height_at(at.x, at.z), at.z)
	if "velocity" in p:
		p.velocity = Vector3.ZERO
	var facing := _facing_for(spot, str(spec[6]))
	p.facing = facing
	await _frames_wait(6)
	if g.camera and g.camera.has_method("snap_to"):
		g.camera.snap_to(p)
	await _frames_wait(20)
	var fwd: Vector3 = p.forward()
	var here: Vector3 = p.global_position
	var side := Vector3(-fwd.z, 0, fwd.x)
	var mine: Array = []
	var reach: float = b.stat("range", 2.6)
	for k in range(crowd):
		var u := float(k % 3) - 1.0
		var row := float(k / 3)
		var sp: Vector3 = here + fwd * reach * (0.45 + 0.3 * row) + side * u * reach * 0.45
		sp.y = g.map.height_at(sp.x, sp.z)
		var i: int = em.spawn("skeleton", sp, null, 1.0, 400.0)
		if i >= 0:
			em.speed[i] = 0.0
			mine.append(i)
	em._rebuild_grid()
	await _frames_wait(40)
	var result := "s%d %s: %s L%d at %s facing %.2f" % [st, c, wid, lvl, str(here.snapped(Vector3.ONE * 0.01)), facing]
	for mode: String in _modes:
		g.paused = true
		p.global_position = here
		p.facing = facing
		_mfx.ground_follow = mode == "after"
		await _frames_wait(3)
		var cam: Camera3D = root.get_viewport().get_camera_3d()
		b.cooldown_left = 99.0
		for q in range(240):
			if not b.stroke_running():
				break
			b._tick(DT)
		var fx = b.effects()
		if fx:
			fx.clear()
		b._fire()
		fx = b.effects()
		if mode == "nodepth" and fx:
			_no_depth(fx)
		var t := 0.0
		var k := 0
		for want: float in TIMES:
			while t + DT * 0.5 < want:
				b._tick(DT)
				t += DT
				if mode == "nodepth" and b.effects():
					_no_depth(b.effects())
			await _frames_wait(2)
			var img := root.get_viewport().get_texture().get_image()
			_crop_at(img, cam, here + Vector3(0, 0.5, 0)).save_png(_out.path_join("s%d_%s_%s_%d.png" % [st, c, mode, k]))
			k += 1
		if fx and mode == "after":
			result += " fits %d" % fx.fits_made
			for e: Dictionary in fx._arcs:
				if e.has("fit"):
					result += " fit %s" % str((e["fit"] as Vector3).snapped(Vector3.ONE * 0.01))
					break
		for q in range(90):
			b._tick(DT)
	_mfx.ground_follow = true
	g.paused = false
	for i: int in mine:
		em.despawn(i)
	await _frames_wait(10)
	return result


## Pass 139's alternative (a): every live arc drawn with a copy of its shader that has no depth test.
func _no_depth(fx) -> void:
	for e: Dictionary in fx._arcs:
		if not bool(e["live"]):
			continue
		var mat: ShaderMaterial = e["mat"]
		var sh: Shader = mat.shader
		if _nodepth.values().has(sh):
			continue
		# its uniforms kept across the swap
		var vals := {}
		for u: Dictionary in sh.get_shader_uniform_list():
			vals[u["name"]] = mat.get_shader_parameter(u["name"])
		if not _nodepth.has(sh):
			var s2 := Shader.new()
			s2.code = sh.code.replace("render_mode unshaded,", "render_mode unshaded, depth_test_disabled,")
			_nodepth[sh] = s2
		mat.shader = _nodepth[sh]
		for k: String in vals.keys():
			mat.set_shader_parameter(k, vals[k])
		mat.set_shader_parameter("pull", 0.0)


func _crop_at(img: Image, cam: Camera3D, at: Vector3) -> Image:
	if cam == null:
		return img
	var sp: Vector2 = cam.unproject_position(at)
	var w := mini(_crop, img.get_width())
	var h := mini(_crop, img.get_height())
	var x := clampi(int(sp.x) - w / 2, 0, img.get_width() - w)
	var y := clampi(int(sp.y) - h / 2, 0, img.get_height() - h)
	return img.get_region(Rect2i(x, y, w, h))
