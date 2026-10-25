## Pass 106 (lane DRUM; Garry: "this thing should be more powerful and longer lasting than the Rage Power-up. It's only one
## time thing and it should be a big deal"): the War Drum's boost once its moment (ui/DrumMoment.gd) has played, and how it
## shows on the hero. Any buff structure whose params carry a `moment` gets it (StructureDef.params, the War Drum's JSON):
## - the buff: params.effects for params.seconds on the buffs' clock (Run.add_timed_effects under "structure:<id>", so the
##   hero's buff_seconds stretch it as every structure's buff; the same structure again starts its clock over);
## - the stacking rule (params.stack: [{with, stats, keep}]): while the timed buff `with` runs beside it (a power-up's id:
##   "rage" the Berserk, "sprint" the Sprint), each of this boost's effects on one of `stats` gives only `keep` of its
##   bonus (value x keep): the War Drum's x2 attack damage and x2 weapon speed are x1.5 under a Berserk, its +15% move
##   speed +7.5% under a Sprint. Checked every frame (retuned when a Berserk or a Sprint starts or ends: Run.retune_timed);
## - the look (params.aura): red speed lines trailing him at three heights and red streaks rushing past while he runs
##   (one mesh of this node's own, blended over the sand rather than added to it: an additive red vanished on the
##   sand), and a ground ring under him that thumps on a beat (`beat` s, `accents` per beat) with a red wave racing out
##   on every beat (Telegraphs.race_ring, `radius` m, `wave_seconds`), for the whole boost.
## The HUD shows its seconds on a plate with the structure's icon (params.plate: HUD.plate_key).
class_name DrumBoost
extends Node

const STREAK_MAX := 18
const STREAK_WIDTH := 0.09
const RING_R := 0.85
const RING_THUMP := 0.35
const DEFAULT_COLOUR := Color(1.0, 0.23, 0.18)
## the speed lines' and streaks' red (blended, so it reads on the pale sand)
const LINE_COLOUR := Color(0.8, 0.06, 0.04)
const TRAIL_SECONDS := 0.45
const TRAIL_STEP := 0.025
## the speed lines: [height above his feet, width at his back] each
const TRAIL_LINES := [[0.45, 0.2], [0.95, 0.32], [1.45, 0.2]]

var game: Node = null
var def: StructureDef = null
## the timed buff's id in Run.timed ("structure:<id>")
var id := ""
## the stacking state applied now ("rage=1,sprint=0"; tests)
var applied_key := ""
## beats played since the boost began, waves sent (tests, the capture)
var beats := 0
var _beat_t := 0.0
var _ring := -1
var _thump := 0.0
var _col := DEFAULT_COLOUR
var _streak_pos := PackedVector3Array()
var _streak_vel := PackedVector3Array()
var _streak_age := PackedFloat32Array()
var _streak_life := PackedFloat32Array()
var _streak_clock := 0.0
var _mesh: ImmediateMesh = null
var _trail_pts := PackedVector3Array()
var _trail_age := PackedFloat32Array()
var _trail_clock := 0.0
static var _line_mat: StandardMaterial3D = null


## The timed buff's id for a structure.
static func timed_id(d: StructureDef) -> String:
	return "structure:" + d.id


## The stacking rules a structure's params carry ([{with, stats, keep}], none without).
static func stack_rules(d: StructureDef) -> Array:
	var s = d.params.get("stack", []) if d != null else []
	return s if s is Array else []


## Which of the rules' `with` buffs run now, as {id: bool} (Run.boost_left above 0).
static func withs_running(rules: Array) -> Dictionary:
	var on := {}
	for r in rules:
		if r is Dictionary:
			var w := str((r as Dictionary).get("with", ""))
			if w != "":
				on[w] = Run.boost_left(w) > 0.0
	return on


## The boost's effects with the stacking rule applied: each effect's value times every running rule's `keep` whose
## `stats` name its stat (fresh Effects; the def's own are never changed).
static func stacked_effects(effects: Array, rules: Array, on: Dictionary) -> Array:
	var out: Array = []
	for e in effects:
		if not e is Effect:
			continue
		var v := (e as Effect).value
		for r in rules:
			if not r is Dictionary:
				continue
			var rd := r as Dictionary
			if not bool(on.get(str(rd.get("with", "")), false)):
				continue
			var stats = rd.get("stats", [])
			if stats is Array and (stats as Array).has((e as Effect).stat):
				v *= float(rd.get("keep", 1.0))
		out.append(Effect.make((e as Effect).stat, (e as Effect).op, v, (e as Effect).target))
	return out


## "rage=1,sprint=0": the running-state key the boost was last built for.
static func key_of(on: Dictionary) -> String:
	var parts: Array = []
	for k in on.keys():
		parts.append("%s=%d" % [k, 1 if on[k] else 0])
	parts.sort()
	return ",".join(parts)


## The boost in words for the moment's last line ("×2 DAMAGE · ×2 ATTACK SPEED · KNOCKBACK · +15% SPEED · 15 SECONDS"), read
## from the effects as they will run (the stacking rule applied).
static func summary(effects: Array, seconds: float) -> String:
	var parts: Array = []
	var kb := false
	for e in effects:
		if not e is Effect:
			continue
		var ef := e as Effect
		match ef.stat:
			"might":
				parts.append("×%s DAMAGE" % _num(1.0 + ef.value))
			"haste":
				parts.append("×%s ATTACK SPEED" % _num(1.0 + ef.value))
			"move_speed":
				parts.append("+%d%% SPEED" % int(round(ef.value * 100.0)))
			"knockback":
				kb = true
	if kb:
		parts.insert(mini(2, parts.size()), "KNOCKBACK")
	parts.append("%d SECONDS" % int(round(seconds)))
	return " · ".join(parts)


static func _num(v: float) -> String:
	return str(int(round(v))) if absf(v - round(v)) < 0.01 else ("%.2f" % v).rstrip("0").rstrip(".")


## The boost starts (the moment over): its effects as they stack now, on Run's timed buffs for params.seconds.
func start(p_def: StructureDef) -> void:
	def = p_def
	id = timed_id(def)
	var aura = def.params.get("aura", {})
	if aura is Dictionary and (aura as Dictionary).has("color"):
		_col = Color(str((aura as Dictionary)["color"]))
	var on := withs_running(stack_rules(def))
	applied_key = key_of(on)
	Run.add_timed_effects(id, def.display_name, stacked_effects(def.effects, stack_rules(def), on), float(def.params.get("seconds", 15.0)))
	# a structure used again while its boost runs keeps the stacking as it is now
	Run.retune_timed(id, stacked_effects(def.effects, stack_rules(def), on))
	_beat_t = 0.0
	beats = 0


## Seconds left of the boost (0 when it is not running).
func left() -> float:
	return Run.boost_left(id) if id != "" else 0.0


func running() -> bool:
	return left() > 0.0


func _process(delta: float) -> void:
	if def == null:
		return
	var up: bool = running()
	if up:
		_retune()
	var p = game.get("player") if game != null else null
	var alive: bool = up and p != null and not bool(p.dead)
	_tick_look(delta, alive, p)


## The stacking rule, every frame: the boost is rebuilt only when a `with` buff started or ended.
func _retune() -> void:
	var rules := stack_rules(def)
	if rules.is_empty():
		return
	var on := withs_running(rules)
	var k := key_of(on)
	if k == applied_key:
		return
	applied_key = k
	Run.retune_timed(id, stacked_effects(def.effects, rules, on))


func _tick_look(delta: float, on: bool, p) -> void:
	if Run.sim_mode or game == null:
		return
	var fx = game.get("fx")
	var tg = game.get("telegraphs")
	var feet: Vector3 = (p as Node3D).global_position if p != null else Vector3.ZERO
	var flat := Vector3.ZERO
	if p != null:
		flat = Vector3(p.velocity.x, 0.0, p.velocity.z)
	var moving: bool = on and flat.length() > 0.6
	_tick_trail(delta, feet, moving)
	_tick_streaks(delta, feet, flat, on, moving)
	_tick_ring(delta, on, feet, tg, fx)


## The ring under him: held while the boost runs, thumping wider and brighter on each beat and settling between; on every
## beat a wave races out over the sand, as strong as the beat's accent.
func _tick_ring(delta: float, on: bool, feet: Vector3, tg, fx) -> void:
	if tg == null:
		return
	if not on:
		if _ring >= 0:
			tg.release(_ring)
			_ring = -1
		return
	var aura: Dictionary = def.params.get("aura", {}) if def.params.get("aura", {}) is Dictionary else {}
	var every := maxf(float(aura.get("beat", 0.5)), 0.1)
	var acc: Array = aura.get("accents", [1.0]) if aura.get("accents", [1.0]) is Array else [1.0]
	var map = game.get("map")
	var g := Vector3(feet.x, map.height_at(feet.x, feet.z) if map != null else feet.y, feet.z)
	_beat_t -= delta
	if _beat_t <= 0.0:
		_beat_t += every
		var a: float = float(acc[beats % maxi(acc.size(), 1)]) if not acc.is_empty() else 1.0
		beats += 1
		_thump = a
		tg.race_ring(g, float(aura.get("radius", 3.0)) * (0.55 + 0.45 * a), float(aura.get("wave_seconds", 0.55)), Color(_col, 0.35 + 0.4 * a), 0.22)
		if fx != null and a >= 0.7:
			for k in range(3):
				var ang := randf() * TAU
				fx.mote(g + Vector3(cos(ang) * RING_R, 0.15, sin(ang) * RING_R), Vector3(cos(ang) * 0.8, 2.2, sin(ang) * 0.8), 0.45, 0.16, Color(1.0, 0.45, 0.3, 0.9))
	_thump = maxf(_thump - delta * 4.0, 0.0)
	var r := RING_R + RING_THUMP * _thump
	if _ring < 0:
		_ring = tg.hold_ring(g, r, Color(_col, 1.0))
	tg.move_held(_ring, g, r)
	tg.set_alpha(_ring, 0.28 + 0.55 * _thump)


## The speed lines' path: a point every TRAIL_STEP s while he runs, each living TRAIL_SECONDS.
func _tick_trail(delta: float, feet: Vector3, moving: bool) -> void:
	for k in range(_trail_age.size()):
		_trail_age[k] += delta
	while not _trail_age.is_empty() and _trail_age[0] >= TRAIL_SECONDS:
		_trail_age.remove_at(0)
		_trail_pts.remove_at(0)
	if moving:
		_trail_clock -= delta
		if _trail_clock <= 0.0 or _trail_pts.is_empty():
			_trail_clock = TRAIL_STEP
			_trail_pts.append(feet)
			_trail_age.append(0.0)
		else:
			_trail_pts[_trail_pts.size() - 1] = feet


func trail_points() -> int:
	return _trail_pts.size()


## The blended red the lines and streaks are drawn in (the speed ribbons' see-through queue: under the hero).
static func line_material() -> StandardMaterial3D:
	if _line_mat == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.render_priority = Fx.SPEED_TRAIL_PRIORITY
		_line_mat = m
	return _line_mat


## Red streaks rushing back past him while he runs (rising round him while he stands), thin and see-through at both ends.
func _tick_streaks(delta: float, feet: Vector3, flat: Vector3, on: bool, moving: bool) -> void:
	var k := 0
	while k < _streak_age.size():
		_streak_age[k] += delta
		if _streak_age[k] >= _streak_life[k]:
			var last := _streak_age.size() - 1
			_streak_pos[k] = _streak_pos[last]
			_streak_vel[k] = _streak_vel[last]
			_streak_age[k] = _streak_age[last]
			_streak_life[k] = _streak_life[last]
			_streak_pos.resize(last)
			_streak_vel.resize(last)
			_streak_age.resize(last)
			_streak_life.resize(last)
			continue
		_streak_pos[k] += _streak_vel[k] * delta
		k += 1
	if on:
		_streak_clock -= delta
		while _streak_clock <= 0.0:
			_streak_clock += 0.04 if moving else 0.14
			if _streak_age.size() >= STREAK_MAX:
				continue
			if moving:
				var fw := flat.normalized()
				var side := Vector3(-fw.z, 0.0, fw.x)
				_streak_pos.append(feet + fw * randf_range(0.5, 1.6) + side * randf_range(-1.0, 1.0) + Vector3(0, randf_range(0.2, 1.8), 0))
				_streak_vel.append(-fw * randf_range(10.0, 14.0))
				_streak_life.append(randf_range(0.18, 0.28))
			else:
				var a := randf() * TAU
				var r := randf_range(0.45, 0.9)
				_streak_pos.append(feet + Vector3(cos(a) * r, randf_range(0.1, 0.6), sin(a) * r))
				_streak_vel.append(Vector3(0, randf_range(3.0, 4.2), 0))
				_streak_life.append(0.3)
			_streak_age.append(0.0)
	_draw_look()


func streak_count() -> int:
	return _streak_age.size()


func _draw_look() -> void:
	if _mesh == null:
		if _streak_age.is_empty() and _trail_pts.size() < 2:
			return
		_mesh = ImmediateMesh.new()
		var mi := MeshInstance3D.new()
		mi.name = "DrumStreaks"
		mi.mesh = _mesh
		mi.material_override = line_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
		mi.top_level = true
		add_child(mi)
	_mesh.clear_surfaces()
	if _streak_age.is_empty() and _trail_pts.size() < 2:
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# one empty triangle first: a surface with no vertices is an error, and every band can be skipped on a frame
	for k in range(3):
		_mesh.surface_set_color(Color(0, 0, 0, 0))
		_mesh.surface_add_vertex(_trail_pts[0] if not _trail_pts.is_empty() else _streak_pos[0])
	_draw_trail(cam)
	for k in range(_streak_age.size()):
		var head := _streak_pos[k]
		var dir: Vector3 = _streak_vel[k].normalized() if _streak_vel[k].length_squared() > 0.0001 else Vector3.UP
		var length := 1.4 if absf(dir.y) < 0.5 else 0.6
		var tail := head - dir * length
		var mid := head - dir * length * 0.4
		var to_cam: Vector3 = (cam.global_position - mid).normalized() if cam else Vector3.UP
		var side := dir.cross(to_cam)
		side = side.normalized() * STREAK_WIDTH * 0.5 if side.length_squared() > 0.000001 else Vector3.RIGHT * STREAK_WIDTH * 0.5
		var f: float = _streak_age[k] / maxf(_streak_life[k], 0.01)
		var a: float = clampf(f * 6.0, 0.0, 1.0) * (1.0 - f * f) * 0.9
		var c0 := Color(LINE_COLOUR, 0.0)
		var c1 := Color(LINE_COLOUR, a)
		_quad(tail, mid, side, c0, c1)
		_quad(mid, head, side, c1, c0)
	_mesh.surface_end()


## The speed lines: one camera-facing band per TRAIL_LINES row along his path, widest and strongest at his back, nothing
## at the tail.
func _draw_trail(cam: Camera3D) -> void:
	var n := _trail_pts.size()
	if n < 2:
		return
	for row in TRAIL_LINES:
		var lift := Vector3(0.0, float(row[0]), 0.0)
		var width := float(row[1])
		for k in range(n - 1):
			var p0 := _trail_pts[k] + lift
			var p1 := _trail_pts[k + 1] + lift
			var dir := p1 - p0
			if dir.length_squared() < 0.000001:
				continue
			var to_cam: Vector3 = (cam.global_position - p1).normalized() if cam else Vector3.UP
			var side := dir.normalized().cross(to_cam)
			if side.length_squared() < 0.000001:
				continue
			side = side.normalized()
			var f0 := clampf(1.0 - _trail_age[k] / TRAIL_SECONDS, 0.0, 1.0)
			var f1 := clampf(1.0 - _trail_age[k + 1] / TRAIL_SECONDS, 0.0, 1.0)
			var c0 := Color(LINE_COLOUR, 0.85 * f0 * f0)
			var c1 := Color(LINE_COLOUR, 0.85 * f1 * f1)
			var s0 := side * width * 0.5 * f0
			var s1 := side * width * 0.5 * f1
			_mesh.surface_set_color(c0)
			_mesh.surface_add_vertex(p0 - s0)
			_mesh.surface_set_color(c0)
			_mesh.surface_add_vertex(p0 + s0)
			_mesh.surface_set_color(c1)
			_mesh.surface_add_vertex(p1 + s1)
			_mesh.surface_set_color(c0)
			_mesh.surface_add_vertex(p0 - s0)
			_mesh.surface_set_color(c1)
			_mesh.surface_add_vertex(p1 + s1)
			_mesh.surface_set_color(c1)
			_mesh.surface_add_vertex(p1 - s1)


func _quad(p0: Vector3, p1: Vector3, side: Vector3, c0: Color, c1: Color) -> void:
	_mesh.surface_set_color(c0)
	_mesh.surface_add_vertex(p0 - side)
	_mesh.surface_set_color(c0)
	_mesh.surface_add_vertex(p0 + side)
	_mesh.surface_set_color(c1)
	_mesh.surface_add_vertex(p1 + side)
	_mesh.surface_set_color(c0)
	_mesh.surface_add_vertex(p0 - side)
	_mesh.surface_set_color(c1)
	_mesh.surface_add_vertex(p1 + side)
	_mesh.surface_set_color(c1)
	_mesh.surface_add_vertex(p1 - side)


func _exit_tree() -> void:
	if _ring >= 0 and game != null and game.get("telegraphs") != null:
		game.telegraphs.release(_ring)
		_ring = -1
