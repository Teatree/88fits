## The aim shown on the sand (pass 136, lane GUNS; R7 of the weapons-aim proposal, Garry: "R7 - Yes, this is especially
## important for Rockets"): a faint wedge in front of the Outlaw, as wide as the widest aim cone among the weapons he
## holds that aim where he faces (Aim.covers; the "aimed" family, else the "melee" one), WEDGE_TO metres out, a soft dark
## shade about 12% opaque between two thin pale edge lines, and a small pale chevron at his feet. It brightens for PULSE
## seconds when an aimed weapon fires (pulse(); a shot's own line flashes down it with pulse_dir(dir)). Shown only while Settings.show_aim (a player setting, on by default)
## and Aim.on(). One mesh, one draw call, laid over the terrain by core/shaders/aim_wedge.gdshader; transparent, so the
## stage filter never darkens it. Looks only: nothing here rolls a rule die.
##
## The Game makes one a run (Game._ready, after the Telegraphs know the ground) and the weapon behaviours call the
## static pulse() / pulse_dir() without holding it (a no-op when none is alive).
##
## Pass 139 (lane AIM; Garry: "Dragon's Breath, Big Mouth. Now that we have a kind of a attack direction indicator, let's go
## ahead and try to use that to indicate when dragon's breath and big mouth will attack next ... You should consider how
## this attack indicator will work for both of these attacks as well"): the tell. Every RECHECK the wedge looks for the
## held Dragon's Breath / Fire Eater (FireBreath) and Big Mouth / Loudmouth (LaserBeam) that aim by the rule, and every
## frame reads each one's tell_state() (TELL_CHARGE, TELL_READY, TELL_WINDUP, TELL_FIRING) and tell_charge() (0..1: the
## cooldown's progress from the end of the last attack, 1 ready; while firing, the share of the attack left):
##   the Breath: a band in its own colour (orange, Blue Flame blue) over its own cone (its range from BAND_FROM, its width)
##      in the wedge's own mesh and material (the fan is built out to cover it: no new draw call); faintly outlined, it
##      fills from his feet to the far end as the cooldown runs, a bright front where the fill has got to; full and
##      breathing (BEAT_HZ) while it is ready and waits for a creature in the cone; a flash (FLASH s) as it breathes,
##      then it drains as the breath runs out.
##   the Mouth: a narrow line in the beam's colour (Slow Roast orange, Bad Breath green) down the beam's own line, from
##      the floating mouth along its own (lagging) aim to its reach: a strip of its own (LINE_W wide, one more draw call
##      only while the Mouth is held), dashed to its full reach, a solid line filling along it as the cooldown runs, full
##      and pulsing while ready, brighter and wider with dashes racing out through the wind-up (LaserBeam's), a flash as
##      the beam leaves, draining while it pours.
## Both held at once: a cone and a line, two colours, two reaches. Other aimed weapons' pulses brighten the wedge, never
## the bands. The tell is part of the wedge: off with "Show aim", gone with the aim rule (no wedge, no tell). Looks only.
class_name AimWedge
extends Node3D

## Where the wedge starts and ends, metres from the Outlaw's feet.
const WEDGE_FROM := 0.9
const WEDGE_TO := 3.0
## The cone's full angle is clamped to these (degrees).
const MIN_DEG := 20.0
const MAX_DEG := 150.0
## The pulse: seconds, and how much brighter at its start.
const PULSE := 0.1
const PULSE_GAIN := 1.8
## How bright a shot's line flashes down the wedge at its start.
const RAY_GAIN := 0.35
## Seconds between two looks at the build (the widest cone; a mutation may change it).
const RECHECK := 0.25
## Draw order: under every Telegraphs mark (their lowest is -5).
const PRIORITY := -6
## The chevron at his feet: its tip, metres ahead, and its arms' reach.
const CHEVRON_TIP := 0.78
## Pass 139 (lane AIM): the tell's states (a behaviour's tell_state()).
const TELL_CHARGE := 0
const TELL_READY := 1
const TELL_WINDUP := 2
const TELL_FIRING := 3
## Where the Breath's band starts (m from his feet), the flash's seconds as an attack starts, the ready beat (Hz), the
## Mouth's strip: its width (m) and its segments along (it lies on the terrain vertex by vertex).
const BAND_FROM := 0.45
const FLASH := 0.25
const BEAT_HZ := 1.6
const LINE_W := 0.9
## Pass 143 (Garry: "make the indicator for it's attack about half as noticeable since Right now it's almost as noticeable
## as the shot itself"): the Mouth's line drawn at this share of its opacity in every state.
const MOUTH_GAIN := 0.5
const LINE_SEGMENTS := 40
## The fan's rows: one every this many metres out (it lies on the terrain vertex by vertex).
const ROW_STEP := 0.35

static var _live: WeakRef = null

var game: Node
var player: Node3D
var cone_deg := 0.0
var _mi: MeshInstance3D
var _mat: ShaderMaterial
var _pulse_t := 0.0
var _ray_t := 0.0
var _recheck_t := 0.0
## pulses so far (tests)
var pulses := 0
## Pass 139 (lane AIM): the tell's sources (weak: a weapon swapped or evolved frees its behaviour), the fan's band as
## it was built (reach, full degrees; 0 without the Breath), the Mouth's strip, the flashes' clocks, the states seen
## last frame (a fresh attack flashes), the beat's clock; flashes so far (tests)
var _breath_ref: WeakRef = null
var _mouth_ref: WeakRef = null
var band_reach := 0.0
var band_deg := 0.0
var _line: MeshInstance3D
var _line_mat: ShaderMaterial
var _b_flash_t := 0.0
var _m_flash_t := 0.0
var _b_last := -1
var _m_last := -1
var _clock := 0.0
var flashes := 0


## The wedge for `p_game` (its player and Telegraphs); added under the game by the caller.
static func make(p_game: Node) -> AimWedge:
	var w := AimWedge.new()
	w.name = "AimWedge"
	w.game = p_game
	w.player = p_game.get("player")
	return w


## The live wedge, or null.
static func live() -> AimWedge:
	if _live == null:
		return null
	var w = _live.get_ref()
	return w as AimWedge if is_instance_valid(w) else null


## An aimed weapon fired: the wedge brightens for PULSE seconds.
static func pulse() -> void:
	var w := live()
	if w:
		w._pulse_t = PULSE
		w.pulses += 1


## The same, and the shot's line (`dir`, flat) flashes down the wedge.
static func pulse_dir(dir: Vector3) -> void:
	var w := live()
	if w == null:
		return
	w._pulse_t = PULSE
	w.pulses += 1
	if w.player and dir.length_squared() > 0.0001 and w._mat:
		w._mat.set_shader_parameter("ray_angle", local_angle(float(w.player.get("facing")), dir))
		w._ray_t = PULSE * 1.5


## The angle of the flat world direction `dir` off a facing of yaw `facing` (radians), in the wedge mesh's own measure
## (UV.y: positive towards the Outlaw's right).
static func local_angle(facing: float, dir: Vector3) -> float:
	var l := Basis(Vector3.UP, facing).inverse() * Vector3(dir.x, 0.0, dir.z)
	return atan2(l.x, -l.z)


## The widest aim cone (full degrees) among `weapons` (WeaponInstance) that aim by the rule now: the "aimed" family's,
## else the "melee" one's; 0 when none does.
static func widest_cone(weapons: Array) -> float:
	var aimed := 0.0
	var melee := 0.0
	for w in weapons:
		var inst := w as WeaponInstance
		if inst == null or not Aim.covers(inst):
			continue
		var c := Aim.cfg(inst)
		var deg := float(c.get("cone", Aim.DEFAULT_CONE))
		match str(c.get("family", "aimed")):
			"aimed":
				aimed = maxf(aimed, deg)
			"melee":
				melee = maxf(melee, deg)
	var out := aimed if aimed > 0.0 else melee
	return clampf(out, MIN_DEG, MAX_DEG) if out > 0.0 else 0.0


func _ready() -> void:
	_live = weakref(self)
	_mi = MeshInstance3D.new()
	_mi.name = "Wedge"
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.extra_cull_margin = 4.0
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://core/shaders/aim_wedge.gdshader")
	_mat.render_priority = PRIORITY
	var tg = game.get("telegraphs") if game else null
	if tg != null and tg.has_method("_ground_uniforms"):
		tg._ground_uniforms(_mat)
	_mi.material_override = _mat
	add_child(_mi)
	# pass 139 (lane AIM): the Mouth's line, a strip placed in the world each frame (hidden without a held Mouth)
	_line = MeshInstance3D.new()
	_line.name = "MouthLine"
	_line.top_level = true
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_line.extra_cull_margin = 4.0
	_line.mesh = build_line_mesh()
	_line_mat = ShaderMaterial.new()
	_line_mat.shader = _mat.shader
	_line_mat.render_priority = PRIORITY
	if tg != null and tg.has_method("_ground_uniforms"):
		tg._ground_uniforms(_line_mat)
	_line_mat.set_shader_parameter("kind", 1)
	_line_mat.set_shader_parameter("m_width", LINE_W)
	_line.material_override = _line_mat
	_line.visible = false
	add_child(_line)
	visible = false
	_recheck()


func _exit_tree() -> void:
	if live() == self:
		_live = null


## Whether the wedge should show now.
func wanted() -> bool:
	if not bool(Settings.get("show_aim")) or not Aim.on():
		return false
	if player == null or not is_instance_valid(player):
		return false
	if bool(player.get("dead")) or bool(player.get("cinematic")):
		return false
	return cone_deg > 0.0


func _recheck() -> void:
	var deg := widest_cone(Run.weapons)
	_find_sources()
	var br := breath_source()
	var b_reach := 0.0
	var b_deg := 0.0
	if br:
		b_reach = br.tell_reach()
		b_deg = clampf(br.tell_deg(), 1.0, 360.0)
	var changed := absf(b_reach - band_reach) > 0.01 or absf(b_deg - band_deg) > 0.01
	if absf(deg - cone_deg) > 0.01 or changed or (_mi.mesh == null and deg > 0.0):
		cone_deg = deg
		band_reach = b_reach
		band_deg = b_deg
		if deg > 0.0:
			_mi.mesh = build_mesh(deg, band_reach, band_deg)
			_mat.set_shader_parameter("half_angle", deg_to_rad(deg) * 0.5)
			_mat.set_shader_parameter("b_reach", band_reach)
			_mat.set_shader_parameter("b_half", deg_to_rad(band_deg) * 0.5)
			_mat.set_shader_parameter("b_from", BAND_FROM)


## Pass 139 (lane AIM): the held Breath and Mouth that aim by the rule (the Game's behaviours; a test's fake game: its
## children).
func _find_sources() -> void:
	var found_b: Node = null
	var found_m: Node = null
	var pool: Array = []
	var d = game.get("_behaviors") if game else null
	if d is Dictionary:
		pool = (d as Dictionary).values()
	elif game:
		pool = game.get_children()
	for b in pool:
		if not is_instance_valid(b) or not (b is WeaponBehavior):
			continue
		var wb := b as WeaponBehavior
		if wb.inst == null or not Aim.covers(wb.inst) or not wb.has_method("tell_state"):
			continue
		if wb is FireBreath and found_b == null:
			found_b = wb
		elif wb is LaserBeam and found_m == null:
			found_m = wb
	_breath_ref = weakref(found_b) if found_b else null
	_mouth_ref = weakref(found_m) if found_m else null


## The Breath the band shows (null: none).
func breath_source() -> FireBreath:
	var b = _breath_ref.get_ref() if _breath_ref else null
	return b as FireBreath if is_instance_valid(b) else null


## The Mouth the line shows (null: none).
func mouth_source() -> LaserBeam:
	var m = _mouth_ref.get_ref() if _mouth_ref else null
	return m as LaserBeam if is_instance_valid(m) else null


func _process(delta: float) -> void:
	if player == null and game:
		player = game.get("player")
	_recheck_t -= delta
	if _recheck_t <= 0.0:
		_recheck_t = RECHECK
		_recheck()
	var on := wanted()
	visible = on
	if not on:
		return
	var at: Vector3 = player.global_position
	global_position = Vector3(at.x, 0.0, at.z)
	rotation = Vector3(0.0, float(player.get("facing")), 0.0)
	_pulse_t = maxf(_pulse_t - delta, 0.0)
	_ray_t = maxf(_ray_t - delta, 0.0)
	_mat.set_shader_parameter("strength", 1.0 + PULSE_GAIN * (_pulse_t / PULSE))
	_mat.set_shader_parameter("ray_strength", RAY_GAIN * clampf(_ray_t / (PULSE * 1.5), 0.0, 1.0))
	_clock += delta
	_tell_breath(delta)
	_tell_mouth(delta)


## Pass 139 (lane AIM): a band colour's deep shade: more saturated, a little darker (a pale fill vanished on Sundown's sand).
static func deep_of(c: Color) -> Color:
	return Color.from_hsv(c.h, minf(c.s * 1.25, 1.0), c.v * 0.85)


## Pass 139 (lane AIM): the beat while ready, 0..1.
func beat() -> float:
	return 0.5 + 0.5 * sin(_clock * TAU * BEAT_HZ)


## Pass 139 (lane AIM): the Breath's band from its behaviour's tell, on the wedge's own material.
func _tell_breath(delta: float) -> void:
	var br := breath_source()
	if br == null or band_reach <= 0.0:
		if _b_last != -1:
			_mat.set_shader_parameter("b_on", 0.0)
			_b_last = -1
		return
	var st := br.tell_state()
	if st == TELL_FIRING and _b_last != TELL_FIRING and _b_last != -1:
		_b_flash_t = FLASH
		flashes += 1
	_b_last = st
	_b_flash_t = maxf(_b_flash_t - delta, 0.0)
	_mat.set_shader_parameter("b_on", 1.0)
	_mat.set_shader_parameter("b_state", st)
	_mat.set_shader_parameter("b_charge", br.tell_charge())
	var col := br.tell_color()
	_mat.set_shader_parameter("b_color", col)
	_mat.set_shader_parameter("b_deep", deep_of(col))
	_mat.set_shader_parameter("b_flash", _b_flash_t / FLASH)
	_mat.set_shader_parameter("b_beat", beat())


## Pass 139 (lane AIM): the Mouth's line from its behaviour's tell: the strip laid from the mouth down its aim to its
## reach (one transform a frame; the mesh is never rebuilt).
func _tell_mouth(delta: float) -> void:
	var lb := mouth_source()
	if lb == null:
		_line.visible = false
		_m_last = -1
		return
	var ln := lb.tell_line()
	var reach := float(ln["reach"])
	var d: Vector3 = ln["dir"]
	if reach <= 0.0 or d.length_squared() < 0.0001:
		_line.visible = false
		return
	var st := lb.tell_state()
	if st == TELL_FIRING and _m_last != TELL_FIRING and _m_last != -1:
		_m_flash_t = FLASH
		flashes += 1
	_m_last = st
	_m_flash_t = maxf(_m_flash_t - delta, 0.0)
	var from: Vector3 = ln["from"]
	var yaw := atan2(-d.x, -d.z)
	_line.global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(LINE_W, 1.0, reach)), Vector3(from.x, 0.0, from.z))
	_line.visible = true
	_line_mat.set_shader_parameter("m_reach", reach)
	_line_mat.set_shader_parameter("m_state", st)
	_line_mat.set_shader_parameter("m_charge", lb.tell_charge())
	_line_mat.set_shader_parameter("m_color", ln["color"])
	_line_mat.set_shader_parameter("m_flash", _m_flash_t / FLASH)
	_line_mat.set_shader_parameter("m_beat", beat())
	_line_mat.set_shader_parameter("m_wind", lb.windup_f() if st == TELL_WINDUP else 0.0)
	_line_mat.set_shader_parameter("m_clock", _clock)
	_line_mat.set_shader_parameter("m_gain", MOUTH_GAIN)


## Pass 139 (lane AIM): the Mouth's strip: LINE_SEGMENTS quads along -Z from 0 to 1 m, 1 m wide (the node scales it to
## LINE_W and the reach); UV.x the share along, UV.y -0.5..0.5 across.
static func build_line_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(LINE_SEGMENTS):
		var f0 := float(k) / float(LINE_SEGMENTS)
		var f1 := float(k + 1) / float(LINE_SEGMENTS)
		var a := [Vector3(-0.5, 0.0, -f0), Vector2(f0, -0.5)]
		var b := [Vector3(0.5, 0.0, -f0), Vector2(f0, 0.5)]
		var c := [Vector3(-0.5, 0.0, -f1), Vector2(f1, -0.5)]
		var e := [Vector3(0.5, 0.0, -f1), Vector2(f1, 0.5)]
		for v: Array in [a, c, b, b, c, e]:
			st.set_uv(v[1])
			st.add_vertex(v[0])
	return st.commit()


## The wedge (full angle `deg`) and the chevron as one flat mesh, forward -Z, UV (metres out, angle off the facing); the
## shader fades the wedge in near him and out at its far end. Pass 139 (lane AIM): with the Breath's band (`b_reach` m,
## `b_deg` full degrees) the fan reaches out and round to cover it too (from BAND_FROM); the shader draws each inside its
## own span.
static func build_mesh(deg: float, b_reach := 0.0, b_deg := 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fan := deg
	var r0 := WEDGE_FROM
	var r1 := WEDGE_TO
	if b_reach > 0.0:
		fan = maxf(deg, b_deg)
		r0 = minf(r0, BAND_FROM)
		r1 = maxf(r1, b_reach + 0.1)
	fan = clampf(fan, 1.0, 360.0)
	var half := deg_to_rad(fan) * 0.5
	var cols := maxi(int(ceil(fan / 6.0)), 4)
	var rows := maxi(int(ceil((r1 - r0) / ROW_STEP)), 6)
	var grid: Array = []
	for r in range(rows + 1):
		var fr := float(r) / float(rows)
		var rad := lerpf(r0, r1, fr)
		var row: Array = []
		for c in range(cols + 1):
			var fc := float(c) / float(cols)
			var ang := lerpf(-half, half, fc)
			# angle grows towards local +X; forward is -Z (the shader draws the edge lines from UV.y)
			var p := Vector3(sin(ang) * rad, 0.0, -cos(ang) * rad)
			row.append([p, Color(1, 1, 1, 1), Vector2(rad, ang)])
		grid.append(row)
	for r in range(rows):
		for c in range(cols):
			var a: Array = grid[r][c]
			var b: Array = grid[r][c + 1]
			var d: Array = grid[r + 1][c]
			var e: Array = grid[r + 1][c + 1]
			for v: Array in [a, d, b, b, d, e]:
				st.set_color(v[1])
				st.set_uv(v[2])
				st.add_vertex(v[0])
	# the chevron at his feet: a V pointing ahead, brighter than the wedge
	var tip := Vector3(0.0, 0.0, -CHEVRON_TIP)
	var arm := 0.2
	var back := 0.17
	var thick := 0.06
	for s: float in [-1.0, 1.0]:
		var o0 := tip
		var o1 := tip + Vector3(s * arm, 0.0, back)
		var i0 := tip + Vector3(0.0, 0.0, thick * 1.4)
		var i1 := o1 + Vector3(0.0, 0.0, thick * 1.4)
		for v: Vector3 in [o0, i0, o1, o1, i0, i1]:
			# UV.x -1 marks the chevron (the shader draws it pale)
			st.set_color(Color(1, 1, 1, 1))
			st.set_uv(Vector2(-1.0, 0.0))
			st.add_vertex(v)
	return st.commit()
