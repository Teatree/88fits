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
	if absf(deg - cone_deg) > 0.01 or (_mi.mesh == null and deg > 0.0):
		cone_deg = deg
		if deg > 0.0:
			_mi.mesh = build_mesh(deg)
			_mat.set_shader_parameter("half_angle", deg_to_rad(deg) * 0.5)


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


## The wedge (full angle `deg`) and the chevron as one flat mesh, forward -Z: COLOR.a each vertex's share of the alpha
## (brighter along the edges, fading in near him and out at the far end), UV (metres out, angle off the facing).
static func build_mesh(deg: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := deg_to_rad(deg) * 0.5
	var cols := maxi(int(ceil(deg / 6.0)), 4)
	var rows := 6
	var grid: Array = []
	for r in range(rows + 1):
		var fr := float(r) / float(rows)
		var rad := lerpf(WEDGE_FROM, WEDGE_TO, fr)
		# in over the first 20%, out over the last 45%
		var ra := smoothstep(0.0, 0.2, fr) * (1.0 - smoothstep(0.55, 1.0, fr))
		var row: Array = []
		for c in range(cols + 1):
			var fc := float(c) / float(cols)
			var ang := lerpf(-half, half, fc)
			# angle grows towards local +X; forward is -Z (the shader draws the edge lines from UV.y)
			var p := Vector3(sin(ang) * rad, 0.0, -cos(ang) * rad)
			row.append([p, Color(1, 1, 1, ra), Vector2(rad, ang)])
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
