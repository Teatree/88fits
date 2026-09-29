## A blade that lives inside the hero and only shows itself to strike. When a creature is within `range` the blade
## thrusts out of the hero towards the nearest one (`amount` blades fan out around that line), hits everything along
## its length once, and slides back in; with nothing in range there is nothing to see. The visual scene's "Blade" node
## is the 3D blade, modelled one metre long down -Z and one unit wide, scaled to the reach and the hit width; the Halberd's `sweep_deg` swings it
## sideways while it is out. Tuning lives in `params.thrust`: out, hold and back seconds, the blade's half-width, the
## fan between blades.
## Slice mode (pass 35, the Sabre and the Zweihänder): `thrust.slice_deg` > 0 swings the blade across the target through
## that arc instead of poking it: `out` seconds to appear at one end of the arc, `slice` seconds a swing, `back` to go.
## Each of `amount` swings runs the other way (left, right, left), the edge hits what it passes once a swing, and a hit
## throws the creature away from the hero and along the swing together (`side` weighs the sideways part). A crescent
## trail follows the edge.
class_name Thruster
extends WeaponBehavior

var _proto: Node3D
var _blades: Array = []
var _active := 0
var _t := -1.0
var _dir := Vector3.FORWARD
var _hit_done := false
# slice mode
var _swing := -1
var _swing_hits: Dictionary = {}
var _edge_prev := 0.0
var _trail: MeshInstance3D
var _trail_mesh: ImmediateMesh
var _trail_pts: Array = []   # Vector3(edge yaw, time laid, reach), one per tick of a swing
var _clock := 0.0
var _trail_col := Color(0.86, 0.92, 1.0)


func _on_setup() -> void:
	_proto = visual.get_node_or_null("Blade")
	if _proto:
		_proto.visible = false


func _thrust(key: String, default: float) -> float:
	var t = inst.params.get("thrust", {})
	return float(t.get(key, default)) if t is Dictionary else default


func _slices() -> bool:
	return _thrust("slice_deg", 0.0) > 0.0


func _ensure_blades(n: int) -> void:
	if _proto == null:
		return
	while _blades.size() < n:
		var b: Node3D = _proto.duplicate()
		b.visible = false
		visual.add_child(b)
		_blades.append(b)


func _fire() -> bool:
	var em: EnemyManager = game.enemies
	var reach := stat("range", 2.6)
	var t := em.nearest_index(player.global_position, reach + 0.6)
	if t < 0:
		return false
	var d: Vector3 = em.pos[t] - player.global_position
	d.y = 0.0
	_dir = d.normalized() if d.length_squared() > 0.001 else player.forward()
	_active = maxi(stat_int("amount", 1), 1)
	if _slices():
		# one blade does every swing, one after the other
		_ensure_blades(1)
		for k in range(_blades.size()):
			_blades[k].visible = k == 0
		_swing = -1
		_edge_prev = 0.0
	else:
		_ensure_blades(_active)
		for k in range(_blades.size()):
			_blades[k].visible = k < _active
	_t = 0.0
	_hit_done = false
	# Lunge: the stroke carries the hero at the target
	var lg := _thrust("lunge", 0.0)
	if lg > 0.0 and player.has_method("apply_knockback"):
		player.apply_knockback(_dir * lg * 4.5)
	# a slice sounds on every swing (_tick_slice)
	if not _slices():
		sfx("fire", player.aim_origin(_dir))
	return true


func _tick(delta: float) -> void:
	_clock += delta
	if _t >= 0.0 and not _blades.is_empty():
		if _slices():
			_tick_slice(delta)
		else:
			_tick_thrust(delta)
	# after the blade has moved, so the newest spokes draw this frame at full strength
	_tick_trail()


func _tick_thrust(delta: float) -> void:
	var out := _thrust("out", 0.12)
	var hold := _thrust("hold", 0.08)
	var back := _thrust("back", 0.2)
	_t += delta
	var ext := 0.0
	if _t < out:
		ext = _t / out
	elif _t < out + hold:
		ext = 1.0
	elif _t < out + hold + back:
		ext = 1.0 - (_t - out - hold) / back
	else:
		for b in _blades:
			b.visible = false
		_t = -1.0
		return
	var reach := stat("range", 2.6)
	var width := _thrust("width", 0.7) * stat("area", 1.0)
	var fan := deg_to_rad(_thrust("fan_deg", 35.0))
	var sweep := deg_to_rad(_thrust("sweep_deg", 0.0))
	# the sweep swings the whole fan from one side to the other over the stroke
	var swing: float = (clampf(_t / (out + hold + back), 0.0, 1.0) - 0.5) * sweep
	var base := player.global_position + Vector3(0, 0.95, 0)
	for k in range(_active):
		var off: float = (float(k) - float(_active - 1) * 0.5) * fan + swing
		var yaw: float = atan2(-_dir.x, -_dir.z) + off
		var b: Node3D = _blades[k]
		b.global_position = base
		b.rotation = Vector3(0, yaw, 0)
		b.scale = Vector3(width, 1.0, maxf(reach * ext, 0.05))
	if not _hit_done and _t >= out:
		_hit_done = true
		_strike(reach, width, fan, swing)


## The edge's angle off the target line at swing progress u (0..1): swing k runs one way, k + 1 the other.
func _edge(k: int, u: float) -> float:
	var half := deg_to_rad(_thrust("slice_deg", 150.0)) * 0.5
	var s := 1.0 if k % 2 == 0 else -1.0
	var e := 0.5 - 0.5 * cos(PI * clampf(u, 0.0, 1.0))
	return s * half * (2.0 * e - 1.0)


func _tick_slice(delta: float) -> void:
	var out := _thrust("out", 0.06)
	var sl := maxf(_thrust("slice", 0.16), 0.02)
	var back := _thrust("back", 0.12)
	_t += delta
	var reach := stat("range", 2.6)
	var width := _thrust("width", 0.7) * stat("area", 1.0)
	var ext := 1.0
	var k := 0
	var u := 0.0
	var total := out + sl * float(_active)
	if _t < out:
		ext = _t / out
	elif _t < total:
		k = mini(int((_t - out) / sl), _active - 1)
		u = (_t - out - sl * float(k)) / sl
	elif _t < total + back:
		k = _active - 1
		u = 1.0
		ext = 1.0 - (_t - total) / back
	else:
		for b in _blades:
			b.visible = false
		_t = -1.0
		_swing = -1
		return
	var yaw0: float = atan2(-_dir.x, -_dir.z)
	var a := _edge(k, u)
	var b: Node3D = _blades[0]
	b.global_position = player.global_position + Vector3(0, 0.95, 0)
	# a little roll into the cut, so the flat of the blade shows while it swings
	var s := 1.0 if k % 2 == 0 else -1.0
	b.rotation = Vector3(0, yaw0 + a, s * 0.35 * sin(PI * clampf(u, 0.0, 1.0)))
	b.scale = Vector3(width, 1.0, maxf(reach * ext, 0.05))
	if _t < out or _t >= total:
		_edge_prev = a
		return
	if k != _swing:
		# a new swing: a fresh hit list, and the edge starts where this swing starts
		_swing = k
		_swing_hits.clear()
		_edge_prev = _edge(k, 0.0)
		sfx("fire", player.aim_origin(_dir))
	_cut(yaw0, _edge_prev, a, reach, width, s)
	# spokes no more than ~7 degrees apart, so the crescent stays round at 30 fps
	var steps := maxi(ceili(absf(a - _edge_prev) / 0.12), 1)
	for j in range(1, steps + 1):
		_trail_pts.append(Vector3(yaw0 + lerpf(_edge_prev, a, float(j) / float(steps)), _clock, reach))
	_edge_prev = a


## Everything between the edge's last angle and this one, within reach, takes the cut once this swing.
func _cut(yaw0: float, a0: float, a1: float, reach: float, width: float, s: float) -> void:
	var em: EnemyManager = game.enemies
	var wid := inst.def.id
	var lo := minf(a0, a1)
	var hi := maxf(a0, a1)
	var dmg := stat("damage", 16.0)
	var knock := stat("knockback", 6.0)
	var side := _thrust("side", 1.0)
	var pdmg := stat("poison_damage", 0.0)
	var fdmg := stat("fire_damage", 0.0)
	var pp := player.global_position
	var any := false
	for e in em.indices_in_radius(pp, reach + 0.8):
		if _swing_hits.has(e):
			continue
		var d: Vector3 = em.pos[e] - pp
		d.y = 0.0
		var dist := d.length()
		if dist > reach + em.radius[e]:
			continue
		var rel := 0.0
		if dist > 0.05:
			rel = wrapf(atan2(-d.x, -d.z) - yaw0, -PI, PI)
		# the creature's own width, as an angle at its distance
		var pad := atan2(em.radius[e] + width * 0.5, maxf(dist, 0.3))
		if rel < lo - pad or rel > hi + pad:
			continue
		_swing_hits[e] = true
		var radial := d / dist if dist > 0.05 else _dir
		var cy: float = yaw0 + rel
		# the way the edge travels at the creature: the tangent of the swing
		var tangent := Vector3(-cos(cy), 0.0, sin(cy)) * s
		var kdir := radial + tangent * side
		if pdmg > 0.0:
			em.poison(e, wid, pdmg, maxi(stat_int("poison_stacks", 1), 1), stat("poison_duration", 8.0))
		if fdmg > 0.0:
			em.ignite(e, wid, fdmg, stat("fire_duration", 1.8), stat("fire_spread", 0.4))
		if em.damage(e, dmg, wid, kdir, knock * kdir.length()):
			inst.kills += 1
		game.fx_hit(em.pos[e] + Vector3(0, 0.5, 0), inst.def)
		any = true
	if any:
		sfx("hit", pp)


## The crescent behind the edge: every tick of a swing leaves a spoke; spokes fade out over TRAIL_LIFE.
const TRAIL_LIFE := 0.18


func _tick_trail() -> void:
	if _trail_pts.is_empty():
		if _trail and _trail.visible:
			_trail.visible = false
		return
	if _trail == null:
		_trail_mesh = ImmediateMesh.new()
		_trail = MeshInstance3D.new()
		_trail.mesh = _trail_mesh
		_trail.top_level = true
		_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_trail.material_override = Fx.glow_ribbon_material()
		add_child(_trail)
	# the colour follows the blade's element
	if stat("fire_damage", 0.0) > 0.0:
		_trail_col = Color(1.0, 0.55, 0.2)
	elif stat("poison_damage", 0.0) > 0.0:
		_trail_col = Color(0.5, 1.0, 0.35)
	else:
		_trail_col = Color(0.86, 0.92, 1.0)
	while not _trail_pts.is_empty() and _clock - (_trail_pts[0] as Vector3).y > TRAIL_LIFE:
		_trail_pts.pop_front()
	_trail_mesh.clear_surfaces()
	if _trail_pts.size() < 2:
		_trail.visible = false
		return
	_trail.visible = true
	_trail.global_position = player.global_position + Vector3(0, 0.95, 0)
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(_trail_pts.size() - 1):
		var p0: Vector3 = _trail_pts[k]
		var p1: Vector3 = _trail_pts[k + 1]
		var a0 := 1.0 - (_clock - p0.y) / TRAIL_LIFE
		var a1 := 1.0 - (_clock - p1.y) / TRAIL_LIFE
		var d0 := Vector3(-sin(p0.x), 0.0, -cos(p0.x))
		var d1 := Vector3(-sin(p1.x), 0.0, -cos(p1.x))
		var in0 := d0 * p0.z * 0.45
		var out0 := d0 * p0.z * 1.02
		var in1 := d1 * p1.z * 0.45
		var out1 := d1 * p1.z * 1.02
		var c0 := Color(_trail_col.r, _trail_col.g, _trail_col.b, 0.75 * a0 * a0)
		var c1 := Color(_trail_col.r, _trail_col.g, _trail_col.b, 0.75 * a1 * a1)
		var ci0 := Color(c0.r, c0.g, c0.b, 0.0)
		var ci1 := Color(c1.r, c1.g, c1.b, 0.0)
		_trail_mesh.surface_set_color(ci0)
		_trail_mesh.surface_add_vertex(in0)
		_trail_mesh.surface_set_color(c0)
		_trail_mesh.surface_add_vertex(out0)
		_trail_mesh.surface_set_color(c1)
		_trail_mesh.surface_add_vertex(out1)
		_trail_mesh.surface_set_color(ci0)
		_trail_mesh.surface_add_vertex(in0)
		_trail_mesh.surface_set_color(c1)
		_trail_mesh.surface_add_vertex(out1)
		_trail_mesh.surface_set_color(ci1)
		_trail_mesh.surface_add_vertex(in1)
	_trail_mesh.surface_end()


func _strike(reach: float, width: float, fan: float, swing: float) -> void:
	var em: EnemyManager = game.enemies
	var wid := inst.def.id
	var hits := em.indices_in_radius(player.global_position, reach + 0.8)
	var dmg := stat("damage", 16.0)
	var knock := stat("knockback", 6.0)
	var pdmg := stat("poison_damage", 0.0)
	var fdmg := stat("fire_damage", 0.0)
	var any := false
	for e in hits:
		var d: Vector3 = em.pos[e] - player.global_position
		d.y = 0.0
		for k in range(_active):
			var off: float = (float(k) - float(_active - 1) * 0.5) * fan + swing
			var bdir := _dir.rotated(Vector3.UP, off)
			var along := d.dot(bdir)
			var side := (d - bdir * along).length()
			if along > 0.0 and along <= reach + em.radius[e] and side <= width * 0.5 + em.radius[e]:
				if pdmg > 0.0:
					em.poison(e, wid, pdmg, maxi(stat_int("poison_stacks", 1), 1), stat("poison_duration", 8.0))
				if fdmg > 0.0:
					em.ignite(e, wid, fdmg, stat("fire_duration", 1.8), stat("fire_spread", 0.4))
				if em.damage(e, dmg, wid, bdir, knock):
					inst.kills += 1
				game.fx_hit(em.pos[e] + Vector3(0, 0.5, 0), inst.def)
				any = true
				break
	if any:
		sfx("hit", player.global_position)
