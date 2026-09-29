## The Hammer (pass 35): a hammer appears over the hero's head, rears back and comes down in an overhead swoop on the
## thickest crowd within `range`. Where it lands is a small explosion: `damage` to everything inside the blast
## (params.smash.radius times `area`), thrown outwards from the impact. `amount` hammers come down a beat apart, each
## on a crowd of its own while there are crowds enough (WeaponBehavior.crowd_spots).
## The visual scene's "Hammer" node is the model: its grip at the origin, a "Handle" running one metre down -Z (stretched
## to the reach while it swings) and a "Head" at the far end (moved with the handle and sized with the blast).
## params.smash: radius, rise, swing, hold, fade, stagger, shake; `aftershock` {frac, scale, delay}: a second, wider ring
## a beat after the impact; `quake` {lines, length, width, frac}: fissures split the ground from every impact.
class_name Smasher
extends WeaponBehavior

const GRIP_UP := 1.75      # the grip hangs this far over the hero's feet
const HEAD_HALF := 0.32    # half the head's height at scale 1: the head's face meets the ground, not its middle
const REST_LEN := 1.1      # the handle's length while the hammer is raised
const SMEAR_LIFE := 0.14

var _proto: Node3D
var _pool: Array = []      # hammer nodes, reused
var _swings: Array = []    # {node, handle, head, at, yaw, t, hit, len1, pitch1, smear: []}
var _later: Array = []     # {t, fn}: aftershocks waiting their beat
var _smear: MeshInstance3D
var _smear_mesh: ImmediateMesh
var _clock := 0.0


func _on_setup() -> void:
	_proto = visual.get_node_or_null("Hammer")
	if _proto:
		_proto.visible = false


func _smash(key: String, default: float) -> float:
	var s = inst.params.get("smash", {})
	return float(s.get(key, default)) if s is Dictionary else default


func _smash_dict(key: String) -> Dictionary:
	var s = inst.params.get("smash", {})
	if s is Dictionary and s.get(key) is Dictionary:
		return s[key]
	return {}


func _blast_r() -> float:
	return _smash("radius", 1.6) * stat("area", 1.0)


func _take_node() -> Dictionary:
	for it: Dictionary in _pool:
		if not it["busy"]:
			it["busy"] = true
			return it
	if _proto == null:
		return {}
	var n: Node3D = _proto.duplicate()
	n.top_level = true
	visual.add_child(n)
	var it := {"node": n, "handle": n.find_child("Handle", true, false), "head": n.find_child("Head", true, false), "busy": true}
	_pool.append(it)
	return it


func _fire() -> bool:
	var reach := stat("range", 4.6)
	var r := _blast_r()
	var n: int = maxi(stat_int("amount", 1), 1)
	var spots := crowd_spots(n, reach, r)
	if spots.is_empty():
		return false
	var stagger := _smash("stagger", 0.12)
	for k in range(n):
		var at: Vector3 = spots[k % spots.size()]
		if k >= spots.size():
			# more hammers than crowds: the extra ones land round the thickest, not on the same spot
			at += Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * r * 0.6
		at.y = game.map.height_at(at.x, at.z) if game.map else at.y
		var it := _take_node()
		if it.is_empty():
			break
		var d: Vector3 = at - player.global_position
		d.y = 0.0
		if d.length_squared() < 0.01:
			d = player.forward()
		var sw := {"it": it, "at": at, "yaw": atan2(-d.x, -d.z),
				"t": -stagger * float(k), "hit": false, "smear": []}
		_swings.append(sw)
	return true


## Where the grip is: over the hero's head, a little towards the strike.
func _grip(sw: Dictionary) -> Vector3:
	var yaw: float = sw["yaw"]
	return player.global_position + Vector3(0, GRIP_UP, 0) + Vector3(-sin(yaw), 0.0, -cos(yaw)) * 0.25


func _tick(delta: float) -> void:
	_clock += delta
	var rise := _smash("rise", 0.22)
	var swing := maxf(_smash("swing", 0.16), 0.04)
	var hold := _smash("hold", 0.14)
	var fade := maxf(_smash("fade", 0.2), 0.05)
	var r := _blast_r()
	var head_s := clampf(r / 1.6, 0.75, 1.9)
	for k in range(_swings.size() - 1, -1, -1):
		var sw: Dictionary = _swings[k]
		var it: Dictionary = sw["it"]
		var n: Node3D = it["node"]
		sw["t"] = float(sw["t"]) + delta
		var t: float = sw["t"]
		if t < 0.0:
			n.visible = false
			continue
		if not n.visible:
			sfx("fire", player.global_position)
		n.visible = true
		var grip := _grip(sw)
		var at: Vector3 = sw["at"]
		# the pitch that puts the head's face on the target: the handle points down at the ground past the crowd's centre
		var flat := Vector2(at.x - grip.x, at.z - grip.z).length()
		var drop: float = grip.y - (at.y + HEAD_HALF * head_s)
		var len1 := sqrt(flat * flat + drop * drop)
		var pitch1 := -atan2(drop, maxf(flat, 0.05))
		var pitch := 0.0
		var length := REST_LEN
		var s := 1.0
		if t < rise:
			# it appears overhead and rears back past upright
			var u := t / rise
			s = _back_out(u)
			pitch = lerpf(1.2, 1.95, 1.0 - pow(1.0 - u, 2.0))
		elif t < rise + swing:
			# the swoop: faster and faster, the handle reaching out to the crowd on the way down
			var u2 := (t - rise) / swing
			var e := u2 * u2
			pitch = lerpf(1.95, pitch1, e)
			length = lerpf(REST_LEN, len1, e)
			_add_smear(sw, grip, pitch, length, sw["yaw"])
		elif t < rise + swing + hold:
			if not sw["hit"]:
				sw["hit"] = true
				_impact(at, r)
			# planted, with a little bounce off the ground
			var u3 := (t - rise - swing) / hold
			pitch = pitch1 + 0.1 * sin(PI * u3)
			length = len1
		elif t < rise + swing + hold + fade:
			var u4 := (t - rise - swing - hold) / fade
			pitch = pitch1 + 0.25 * u4
			length = len1
			s = 1.0 - u4 * u4
		else:
			n.visible = false
			it["busy"] = false
			_swings.remove_at(k)
			continue
		n.global_position = grip
		n.rotation = Vector3(pitch, sw["yaw"], 0.0)
		n.scale = Vector3.ONE * maxf(s, 0.01)
		var handle: Node3D = it["handle"]
		var head: Node3D = it["head"]
		if handle:
			handle.scale = Vector3(1.0, 1.0, length / REST_LEN)
		if head:
			head.position = Vector3(0.0, 0.0, -length)
			head.scale = Vector3.ONE * head_s
	_tick_later(delta)
	_draw_smear()


## An elastic pop-in: overshoots a touch and settles.
func _back_out(u: float) -> float:
	var c := 1.9
	var x := u - 1.0
	return 1.0 + (c + 1.0) * x * x * x + c * x * x


func _impact(at: Vector3, r: float) -> void:
	var em: EnemyManager = game.enemies
	var wid := inst.def.id
	var dmg := stat("damage", 20.0)
	var knock := stat("knockback", 10.0)
	var pdmg := stat("poison_damage", 0.0)
	var fdmg := stat("fire_damage", 0.0)
	for e in em.indices_in_radius(at, r):
		var away: Vector3 = em.pos[e] - at
		away.y = 0.0
		if pdmg > 0.0:
			em.poison(e, wid, pdmg, maxi(stat_int("poison_stacks", 1), 1), stat("poison_duration", 8.0))
		if fdmg > 0.0:
			em.ignite(e, wid, fdmg, stat("fire_duration", 1.8), stat("fire_spread", 0.4))
		# the closer to the head, the harder it flies
		var f: float = knock * (1.0 - 0.45 * clampf(away.length() / maxf(r, 0.1), 0.0, 1.0))
		if em.damage(e, dmg, wid, away, f):
			inst.kills += 1
	var hot := fdmg > 0.0
	game.fx.sand(at, 0.9 + 0.3 * r)
	game.fx.burst(at + Vector3(0, 0.35, 0), Color(1.0, 0.55, 0.2) if hot else Color(0.95, 0.85, 0.65), r * 0.75)
	game.telegraphs.flash_ring(at, r, Color(1.0, 0.6, 0.25) if hot else Color(1.0, 0.9, 0.6), 0.32)
	game.telegraphs.scorch(at, r * 0.6, Color(0.12, 0.08, 0.06, 0.55), Color(0.25, 0.16, 0.1, 0.0), 0.8, 1.6)
	game.camera.shake(_smash("shake", 0.35))
	sfx("hit", at)
	var af := _smash_dict("aftershock")
	if not af.is_empty():
		_later.append({"t": float(af.get("delay", 0.18)), "at": at, "r": r * float(af.get("scale", 2.0)), "frac": float(af.get("frac", 0.4)), "kind": "aftershock"})
	var qk := _smash_dict("quake")
	if not qk.is_empty():
		_quake(at, qk, dmg)


## The Earthshaker's fissures: `lines` cracks run out from the impact, and whatever stands on one takes `frac` of the hit.
func _quake(at: Vector3, qk: Dictionary, dmg: float) -> void:
	var em: EnemyManager = game.enemies
	var wid := inst.def.id
	var n := int(qk.get("lines", 4))
	var length := float(qk.get("length", 4.5)) * stat("area", 1.0)
	var width := float(qk.get("width", 0.9))
	var frac := float(qk.get("frac", 0.6))
	var a0 := randf() * TAU
	var col := Color(1.0, 0.5, 0.15)
	for k in range(n):
		var a := a0 + TAU * float(k) / float(n) + randf_range(-0.2, 0.2)
		var dir := Vector3(cos(a), 0.0, sin(a))
		game.telegraphs.line(at, dir, length, 0.9, col, width)
		for j in range(3):
			var p := at + dir * length * (0.3 + 0.3 * float(j))
			p.y = game.map.height_at(p.x, p.z) if game.map else at.y
			game.fx.sand(p, 0.7)
			game.fx.flame(p, 0.8, 0.5)
		for e in em.indices_in_radius(at + dir * length * 0.5, length * 0.5 + width):
			var d: Vector3 = em.pos[e] - at
			d.y = 0.0
			var along := d.dot(dir)
			if along < 0.0 or along > length:
				continue
			var side := d - dir * along
			if side.length() > width * 0.5 + em.radius[e]:
				continue
			# thrown off the crack, to whichever side it stood
			if em.damage(e, dmg * frac, wid, side if side.length_squared() > 0.01 else dir, 6.0):
				inst.kills += 1


func _tick_later(delta: float) -> void:
	var em: EnemyManager = game.enemies
	for k in range(_later.size() - 1, -1, -1):
		var job: Dictionary = _later[k]
		job["t"] = float(job["t"]) - delta
		if float(job["t"]) > 0.0:
			continue
		_later.remove_at(k)
		var at: Vector3 = job["at"]
		var r: float = job["r"]
		var before := Run.kills
		for e in em.indices_in_radius(at, r):
			var away: Vector3 = em.pos[e] - at
			away.y = 0.0
			em.damage(e, stat("damage", 20.0) * float(job["frac"]), inst.def.id, away, stat("knockback", 10.0) * 0.6)
		inst.kills += Run.kills - before
		game.telegraphs.flash_ring(at, r, Color(1.0, 0.85, 0.55), 0.4)
		for j in range(6):
			var a := TAU * float(j) / 6.0
			var p := at + Vector3(cos(a), 0.0, sin(a)) * r * 0.85
			p.y = game.map.height_at(p.x, p.z) if game.map else at.y
			game.fx.sand(p, 0.6)
		game.camera.shake(0.2)


## The swoop's smear: a fan of the handle's outer half behind the head, fading in SMEAR_LIFE.
func _add_smear(sw: Dictionary, grip: Vector3, pitch: float, length: float, yaw: float) -> void:
	var b := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var axis := b * Vector3(0, 0, -1)
	(sw["smear"] as Array).append({"a": grip + axis * length * 0.55, "b": grip + axis * (length + 0.35), "born": _clock})


func _draw_smear() -> void:
	var any := false
	for sw: Dictionary in _swings:
		var pts: Array = sw["smear"]
		while not pts.is_empty() and _clock - float(pts[0]["born"]) > SMEAR_LIFE:
			pts.pop_front()
		if pts.size() >= 2:
			any = true
	if not any:
		if _smear:
			_smear.visible = false
		return
	if _smear == null:
		_smear_mesh = ImmediateMesh.new()
		_smear = MeshInstance3D.new()
		_smear.mesh = _smear_mesh
		_smear.top_level = true
		_smear.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_smear.material_override = Fx.glow_ribbon_material()
		add_child(_smear)
		_smear.global_transform = Transform3D.IDENTITY
	_smear.visible = true
	_smear_mesh.clear_surfaces()
	_smear_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var hot := stat("fire_damage", 0.0) > 0.0
	var col := Color(1.0, 0.6, 0.25) if hot else Color(1.0, 0.95, 0.8)
	for sw: Dictionary in _swings:
		var pts: Array = sw["smear"]
		for k in range(pts.size() - 1):
			var p0: Dictionary = pts[k]
			var p1: Dictionary = pts[k + 1]
			var a0 := 1.0 - (_clock - float(p0["born"])) / SMEAR_LIFE
			var a1 := 1.0 - (_clock - float(p1["born"])) / SMEAR_LIFE
			var c0 := Color(col.r, col.g, col.b, 0.55 * a0)
			var c1 := Color(col.r, col.g, col.b, 0.55 * a1)
			var i0 := Color(col.r, col.g, col.b, 0.0)
			_smear_mesh.surface_set_color(i0)
			_smear_mesh.surface_add_vertex(p0["a"])
			_smear_mesh.surface_set_color(c0)
			_smear_mesh.surface_add_vertex(p0["b"])
			_smear_mesh.surface_set_color(c1)
			_smear_mesh.surface_add_vertex(p1["b"])
			_smear_mesh.surface_set_color(i0)
			_smear_mesh.surface_add_vertex(p0["a"])
			_smear_mesh.surface_set_color(c1)
			_smear_mesh.surface_add_vertex(p1["b"])
			_smear_mesh.surface_set_color(i0)
			_smear_mesh.surface_add_vertex(p1["a"])
	_smear_mesh.surface_end()
