## Pass 112 (lane MONK; Garry: "Projectile Shot - a bright, very noticeable blue energy sphere. Does not touch other
## enemies. The range of the projectile is about 25% further than that of Drifter's Revolver."): the squads' spheres
## (Squads._fire) and the glows gathering between the raised hands (Squads._glows), all of them in one MultiMesh of
## camera-facing quads (core/shaders/energy_orb.gdshader: a white-hot core, the colour, a darker rim, a soft halo; beads
## for the trail), one draw call for every sphere, glow and bead on the screen.
##
## A sphere flies straight along the flat line it left on, `speed` m/s on the creatures' shot clock (High Noon and the
## pace knob, EnemyManager.hostile_clock), from its hands down to `hover` m over the sand within DESCEND s, then
## following the ground at that height. It touches nothing but the hero: no creature, no rock, no other shot. It is spent
## when it reaches him (his body: its `hit_radius` + HERO_R flat, his height band; he takes its damage as a hostile
## shot's hit: an evade, the shield, the blink after a hit apply; a plain shot, no push unless `knockback`) or when it
## has flown `range` m (it bursts into a puff). It breathes (`pulse_hz`, `pulse` either way of its size) and drops a
## bead of its colour every `trail.every` s that shrinks and fades over `trail.life`. Under the shots node, so a stage
## filter never darkens it (see-through materials are drawn after the filter anyway).
class_name EnergyOrbs
extends Node3D

const MAX := 384
const GLOW_MAX := 192
const TRAIL_MAX := 1536
## the hero's body round a sphere's hit radius (ProjectileManager's hostile shots: radius + 0.5)
const HERO_R := 0.5
## seconds a sphere takes from the hands down to its flying height
const DESCEND := 0.35
## the hero's height band a sphere hits in (metres over his feet), as the hostile shots'
const BAND_LO := -0.6
const BAND_HI := 2.4

var game: Node
var enemies: EnemyManager

var pos := PackedVector3Array()
var dir := PackedVector3Array()
var spd := PackedFloat32Array()
var flown := PackedFloat32Array()
var reach := PackedFloat32Array()
var dmg := PackedFloat32Array()
var hit_r := PackedFloat32Array()
var size := PackedFloat32Array()
var h0 := PackedFloat32Array()
var hover := PackedFloat32Array()
var age := PackedFloat32Array()
var knock := PackedFloat32Array()
var col := PackedColorArray()
var pulse_hz := PackedFloat32Array()
var pulse_amp := PackedFloat32Array()
var phase := PackedFloat32Array()
var tr_every := PackedFloat32Array()
var tr_life := PackedFloat32Array()
var tr_size := PackedFloat32Array()
var tr_alpha := PackedFloat32Array()
var tr_t := PackedFloat32Array()
var info: Array = []
var alive := PackedByteArray()
var free_list: Array = []
var count := 0
## diagnostics and tests
var fired := 0
var hits := 0
var spent := 0
## the distance the last sphere to run out had flown
var last_spent_flown := 0.0

var _glows := PackedVector4Array()
var _glow_cols := PackedColorArray()
var _b_pos := PackedVector3Array()
var _b_age := PackedFloat32Array()
var _b_life := PackedFloat32Array()
var _b_size := PackedFloat32Array()
var _b_col := PackedColorArray()
var _b_next := 0
## the frame clock past which no bead is left (the draw stops when there is nothing to show)
var _b_until := 0.0
var _clock := 0.0
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _ticks := 0
var _drawn := -1


func _ready() -> void:
	pos.resize(MAX); dir.resize(MAX); spd.resize(MAX); flown.resize(MAX); reach.resize(MAX); dmg.resize(MAX)
	hit_r.resize(MAX); size.resize(MAX); h0.resize(MAX); hover.resize(MAX); age.resize(MAX); knock.resize(MAX)
	col.resize(MAX); pulse_hz.resize(MAX); pulse_amp.resize(MAX); phase.resize(MAX)
	tr_every.resize(MAX); tr_life.resize(MAX); tr_size.resize(MAX); tr_alpha.resize(MAX); tr_t.resize(MAX)
	alive.resize(MAX)
	info.resize(MAX)
	for i in range(MAX - 1, -1, -1):
		free_list.append(i)
	_b_pos.resize(TRAIL_MAX); _b_age.resize(TRAIL_MAX); _b_life.resize(TRAIL_MAX); _b_size.resize(TRAIL_MAX); _b_col.resize(TRAIL_MAX)
	for k in range(TRAIL_MAX):
		_b_age[k] = 1.0
		_b_life[k] = 0.0
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	_mm.mesh = quad
	_mm.instance_count = TRAIL_MAX + GLOW_MAX + MAX
	_mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://core/shaders/energy_orb.gdshader")
	_mmi.material_override = mat
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(_mmi)


## One sphere from `from` along the flat unit `along` (EnergyOrbs' header), its look and numbers from the squad block's
## `look` (the `orb` block), its hit's `p_info` (EnemyManager.hit_info). Returns its index, -1 when the pool is full.
func fire(from: Vector3, along: Vector3, speed: float, range_m: float, damage: float, look: Dictionary, p_info: Dictionary) -> int:
	if free_list.is_empty():
		return -1
	var i: int = free_list.pop_back()
	pos[i] = from
	var d := Vector3(along.x, 0.0, along.z)
	dir[i] = d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD
	spd[i] = maxf(speed, 0.1)
	flown[i] = 0.0
	reach[i] = maxf(range_m, 0.1)
	dmg[i] = damage
	hit_r[i] = maxf(float(look.get("hit_radius", 0.22)), 0.0)
	size[i] = maxf(float(look.get("size", 0.5)), 0.05)
	var g := _ground(from)
	h0[i] = from.y - g
	hover[i] = float(look.get("hover", 1.0))
	age[i] = 0.0
	knock[i] = maxf(float(look.get("knockback", 0.0)), 0.0)
	col[i] = Color(str(look.get("color", "#2F7BFF")))
	pulse_hz[i] = float(look.get("pulse_hz", 3.0))
	pulse_amp[i] = float(look.get("pulse", 0.12))
	phase[i] = randf()
	var tl: Dictionary = look.get("trail", {}) if look.get("trail") is Dictionary else {}
	tr_every[i] = float(tl.get("every", 0.04))
	tr_life[i] = float(tl.get("life", 0.35))
	tr_size[i] = float(tl.get("size", 0.6))
	tr_alpha[i] = float(tl.get("alpha", 0.45))
	tr_t[i] = 0.0
	info[i] = p_info
	alive[i] = 1
	count += 1
	fired += 1
	return i


## The glows gathering between raised hands this tick (Squads.tick): (x, y, z, size) and their colours.
func set_glows(pts: PackedVector4Array, cols: PackedColorArray) -> void:
	_glows = pts.duplicate()
	_glow_cols = cols.duplicate()


func clear() -> void:
	for i in range(MAX):
		if alive[i] == 1:
			_free(i)
	_glows.clear()
	_glow_cols.clear()


func _free(i: int) -> void:
	if alive[i] == 0:
		return
	alive[i] = 0
	info[i] = null
	free_list.append(i)
	count -= 1


func _ground(p: Vector3) -> float:
	if game != null:
		var mp = game.get("map")
		if mp != null and mp.has_method("height_at"):
			return mp.height_at(p.x, p.z)
	if enemies != null:
		return enemies._height(p.x, p.z)
	return 0.0


func _physics_process(delta: float) -> void:
	_ticks += 1
	_clock += delta
	if count <= 0:
		return
	var clock_k: float = enemies.hostile_clock() if enemies != null else 1.0
	var dt := delta * clock_k
	var player: Node3D = enemies.player if enemies != null else null
	var hero_ok: bool = player != null and is_instance_valid(player)
	if hero_ok:
		var dd = player.get("dead")
		hero_ok = not (dd is bool and dd)
	var hp: Vector3 = player.global_position if hero_ok else Vector3.INF
	for i in range(MAX):
		if alive[i] == 0:
			continue
		age[i] += dt
		var step := spd[i] * dt
		pos[i] += dir[i] * step
		flown[i] += step
		var k := clampf(age[i] / DESCEND, 0.0, 1.0)
		var h := lerpf(h0[i], hover[i], k * (2.0 - k))
		pos[i].y = _ground(pos[i]) + h
		# the trail (real time: a slowed sphere still leaves its beads)
		tr_t[i] -= delta
		if tr_t[i] <= 0.0 and tr_every[i] > 0.0:
			tr_t[i] = tr_every[i]
			_bead(pos[i], size[i] * tr_size[i], tr_life[i], Color(col[i].r, col[i].g, col[i].b, tr_alpha[i]))
		if hero_ok:
			var d := Vector2(hp.x - pos[i].x, hp.z - pos[i].z)
			var dy := pos[i].y - hp.y
			if d.length() < hit_r[i] + HERO_R and dy > BAND_LO and dy < BAND_HI:
				_hit(i, player)
				continue
		if flown[i] >= reach[i]:
			last_spent_flown = flown[i]
			spent += 1
			# it bursts into a puff where it ran out
			_bead(pos[i], size[i] * 1.6, 0.3, Color(col[i].r, col[i].g, col[i].b, 0.6))
			_free(i)


func _hit(i: int, player: Node3D) -> void:
	var inf: Dictionary = (info[i] as Dictionary).duplicate(true) if info[i] is Dictionary else {}
	if knock[i] > 0.0:
		inf["knock"] = knock[i]
		inf["special_knock"] = true
	else:
		# a plain shot (pass 89: no push), its shove written as every hostile shot's would be
		ProjectileManager.put_shot_knock(inf)
		inf["special_knock"] = false
	player.take_damage(dmg[i], pos[i], inf)
	hits += 1
	_bead(pos[i], size[i] * 2.0, 0.25, Color(col[i].r, col[i].g, col[i].b, 0.7))
	if game != null and game.has_method("fx_burst"):
		game.fx_burst(pos[i], col[i], 0.9)
	_free(i)


func _bead(at: Vector3, s: float, life: float, c: Color) -> void:
	if life <= 0.0:
		return
	_b_pos[_b_next] = at
	_b_age[_b_next] = 0.0
	_b_life[_b_next] = life
	_b_size[_b_next] = s
	_b_col[_b_next] = c
	_b_next = (_b_next + 1) % TRAIL_MAX
	_b_until = maxf(_b_until, _clock + life + 0.05)


func _process(delta: float) -> void:
	# nothing in the air, gathering or fading: nothing to draw
	if count <= 0 and _glows.is_empty() and _clock > _b_until:
		if _mm.visible_instance_count != 0:
			_mm.visible_instance_count = 0
		return
	# the beads age on the frame's clock; the run sim's fast mode draws nothing
	for k in range(TRAIL_MAX):
		if _b_life[k] > 0.0 and _b_age[k] < 1.0:
			_b_age[k] += delta / _b_life[k]
	if Run.sim_mode:
		return
	_render()


func _render() -> void:
	var n := 0
	# the beads first (under the spheres)
	for k in range(TRAIL_MAX):
		if _b_life[k] <= 0.0 or _b_age[k] >= 1.0:
			continue
		var f := _b_age[k]
		var s := _b_size[k] * (1.0 - 0.6 * f)
		_mm.set_instance_transform(n, Transform3D(Basis().scaled(Vector3(s, s, s)), _b_pos[k]))
		var c := _b_col[k]
		_mm.set_instance_color(n, Color(c.r, c.g, c.b, c.a * (1.0 - f)))
		_mm.set_instance_custom_data(n, Color(0.0, 1.0, 0.0, 0.0))
		n += 1
	# the glows gathering between raised hands
	for g in range(mini(_glows.size(), GLOW_MAX)):
		var p := _glows[g]
		var pul := 0.5 + 0.5 * sin(TAU * (_clock * 4.0 + float(g) * 0.37))
		var s2 := p.w * 2.0 * (1.0 + 0.08 * (2.0 * pul - 1.0))
		_mm.set_instance_transform(n, Transform3D(Basis().scaled(Vector3(s2, s2, s2)), Vector3(p.x, p.y, p.z)))
		var gc: Color = _glow_cols[g] if g < _glow_cols.size() else Color(0.18, 0.48, 1.0)
		_mm.set_instance_color(n, Color(gc.r, gc.g, gc.b, 1.0))
		_mm.set_instance_custom_data(n, Color(pul, 0.0, 0.0, 0.0))
		n += 1
	# the spheres
	for i in range(MAX):
		if alive[i] == 0:
			continue
		var pul2 := 0.5 + 0.5 * sin(TAU * (_clock * pulse_hz[i] + phase[i]))
		var s3 := size[i] * 2.0 * (1.0 + pulse_amp[i] * (2.0 * pul2 - 1.0))
		_mm.set_instance_transform(n, Transform3D(Basis().scaled(Vector3(s3, s3, s3)), pos[i]))
		_mm.set_instance_color(n, Color(col[i].r, col[i].g, col[i].b, 1.0))
		_mm.set_instance_custom_data(n, Color(pul2, 0.0, 0.0, 0.0))
		n += 1
	_mm.visible_instance_count = n
