## Cluster Munitions' bomblets (pass 53, the Rocket Pod's volume path; Garry: "a small field of small dot like cluster
## bombs that if an enemy steps on will create a small explosion ... the explosion radius can be smaller"). When a
## rocket's blast goes off, with `cluster.chance` it scatters `count` bomblets within `spread` metres: each hops out of
## the blast onto the sand over TOSS seconds and lies there armed for `life` seconds; a creature within `trigger` metres
## pops it, a `radius` blast for `damage_frac` of the rocket's damage with a small knockback (`knockback`). At most `max`
## lie per weapon (the oldest goes quietly). The Hellfire Battery's `chain`: a pop sets off every bomblet within
## `chain_radius` (CHAIN_RADIUS) of it, and those set off theirs.
## Every bomblet is one instance in two MultiMeshes, a dark body and a red lamp that blinks (two draw calls however many
## lie there, the way Fx and the shots are drawn), and every clock runs in step() on the physics tick, so the field
## pauses with the game and tests can drive it. ProjectileManager owns the one field (its `bomblets`).
class_name Bomblets
extends Node3D

const MAX := 96
## the hop out of the blast: this long, this high at the top, growing to full size on the way
const TOSS := 0.28
const TOSS_APEX := 0.9
const BODY_R := 0.085
const LAMP_R := 0.03
const LAMP_ON := Color(1.0, 0.22, 0.14)
const LAMP_OFF := Color(0.42, 0.08, 0.06)
const BLINK_HZ := 3.0
const CHAIN_RADIUS := 1.2
const KNOCKBACK := 2.5
## an armed bomblet looks for a foot this often (a field of thirty is thirty grid looks a frame otherwise)
const LOOK_EVERY := 0.05

var game: Node
var pos := PackedVector3Array()
var from_p := PackedVector3Array()
var to_p := PackedVector3Array()
var age := PackedFloat32Array()      # seconds since it was scattered (the hop runs on it)
var life := PackedFloat32Array()     # seconds left once it lies armed
var dmg := PackedFloat32Array()
var radius := PackedFloat32Array()
var trigger := PackedFloat32Array()
var kbf := PackedFloat32Array()
var look_t := PackedFloat32Array()
var chain := PackedByteArray()
var alive := PackedByteArray()
var order := PackedInt32Array()      # a running number: the oldest of a weapon's has the smallest
var weapon: Array = []               # WeaponInstance per slot
var count := 0
## diagnostics and tests: bomblets scattered and popped so far
var scattered := 0
var pops := 0
var _serial := 0
var _free: Array = []
var _body_mm: MultiMesh
var _lamp_mm: MultiMesh
var _clock := 0.0


func _ready() -> void:
	pos.resize(MAX); from_p.resize(MAX); to_p.resize(MAX); age.resize(MAX); life.resize(MAX); dmg.resize(MAX)
	radius.resize(MAX); trigger.resize(MAX); kbf.resize(MAX); look_t.resize(MAX); chain.resize(MAX); alive.resize(MAX); order.resize(MAX)
	weapon.resize(MAX)
	for i in range(MAX - 1, -1, -1):
		alive[i] = 0
		_free.append(i)
	# the body: a small dark sphere, a little metal in it so it catches the light on the sand
	var body := SphereMesh.new()
	body.radius = BODY_R
	body.height = BODY_R * 2.0
	body.radial_segments = 8
	body.rings = 4
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.13, 0.13, 0.15)
	bmat.metallic = 0.35
	bmat.roughness = 0.6
	_body_mm = _pool(body, bmat, false)
	# the lamp: a red dot on top, unshaded, its instance colour blinking
	var lamp := SphereMesh.new()
	lamp.radius = LAMP_R
	lamp.height = LAMP_R * 2.0
	lamp.radial_segments = 6
	lamp.rings = 3
	var lmat := StandardMaterial3D.new()
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lmat.vertex_color_use_as_albedo = true
	_lamp_mm = _pool(lamp, lmat, true)


func _pool(mesh: Mesh, mat: Material, colors: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(mmi)
	return mm


## The cluster's numbers with their defaults filled in.
static func config(cfg: Dictionary) -> Dictionary:
	return {
		"count": maxi(int(cfg.get("count", 5)), 1),
		"damage_frac": float(cfg.get("damage_frac", 0.25)),
		"radius": float(cfg.get("radius", 0.8)),
		"life": float(cfg.get("life", 6.0)),
		"spread": float(cfg.get("spread", 1.6)),
		"max": maxi(int(cfg.get("max", 20)), 1),
		"trigger": float(cfg.get("trigger", 0.55)),
		"chain": bool(cfg.get("chain", false)),
		"knockback": float(cfg.get("knockback", KNOCKBACK)),
	}


## Scatters `cfg.count` bomblets round `at` for weapon `w`, each worth `damage_frac` of `damage`; the weapon's oldest go
## when it would hold more than `cfg.max`. Returns how many were scattered.
func scatter(w: WeaponInstance, at: Vector3, damage: float, cfg: Dictionary) -> int:
	var c := config(cfg)
	var n := 0
	var wid: String = w.def.id if w else ""
	for k in range(int(c["count"])):
		while count_of_id(wid) >= int(c["max"]):
			_drop_oldest(wid)
		if _free.is_empty():
			break
		var i: int = _free.pop_back()
		alive[i] = 1
		count += 1
		_serial += 1
		order[i] = _serial
		weapon[i] = w
		var a := TAU * (float(k) + randf() * 0.6) / float(c["count"])
		var r: float = randf_range(0.3, maxf(float(c["spread"]), 0.3))
		from_p[i] = at
		var to := at + Vector3(cos(a) * r, 0.0, sin(a) * r)
		to.y = _ground(to)
		to_p[i] = to
		pos[i] = at
		age[i] = 0.0
		life[i] = float(c["life"])
		dmg[i] = damage * float(c["damage_frac"])
		radius[i] = float(c["radius"])
		trigger[i] = float(c["trigger"])
		kbf[i] = float(c["knockback"])
		chain[i] = 1 if bool(c["chain"]) else 0
		look_t[i] = randf() * LOOK_EVERY
		n += 1
		scattered += 1
	return n


## How many bomblets of weapon `w` lie there (hopping ones included).
func count_of(w: WeaponInstance) -> int:
	return count_of_id(w.def.id if w else "")


func count_of_id(wid: String) -> int:
	var n := 0
	for i in range(MAX):
		if alive[i] == 1 and weapon[i] != null and (weapon[i] as WeaponInstance).def.id == wid:
			n += 1
	return n


## The live bomblets' slots (tests).
func live() -> Array:
	var out: Array = []
	for i in range(MAX):
		if alive[i] == 1:
			out.append(i)
	return out


## Whether bomblet `i` lies armed on the sand (its hop over).
func is_armed(i: int) -> bool:
	return alive[i] == 1 and age[i] >= TOSS


func _drop_oldest(wid: String) -> void:
	var best := -1
	for i in range(MAX):
		if alive[i] == 1 and weapon[i] != null and (weapon[i] as WeaponInstance).def.id == wid:
			if best < 0 or order[i] < order[best]:
				best = i
	if best >= 0:
		_release(best)


func _release(i: int) -> void:
	if alive[i] == 0:
		return
	alive[i] = 0
	weapon[i] = null
	count -= 1
	_free.append(i)


func clear() -> void:
	for i in range(MAX):
		_release(i)


## The sand under `p` (0 without a map: a test's flat world).
func _ground(p: Vector3) -> float:
	if game and game.get("map") != null and game.map.has_method("height_at"):
		return game.map.height_at(p.x, p.z)
	return 0.0


func _physics_process(delta: float) -> void:
	if game == null or count == 0 or bool(game.get("paused")):
		return
	step(delta)


## One tick of every bomblet (tests call it directly): the hop out of the blast, then the wait for a foot or the end of
## its life.
func step(delta: float) -> void:
	_clock += delta
	var em: EnemyManager = game.get("enemies") if game else null
	for i in range(MAX):
		if alive[i] == 0:
			continue
		var was_armed := age[i] >= TOSS
		age[i] += delta
		if age[i] < TOSS:
			var u: float = clampf(age[i] / TOSS, 0.0, 1.0)
			pos[i] = from_p[i].lerp(to_p[i], u) + Vector3(0.0, TOSS_APEX * 4.0 * u * (1.0 - u), 0.0)
			continue
		if not was_armed:
			pos[i] = to_p[i]
		life[i] -= delta
		if life[i] <= 0.0:
			_release(i)
			continue
		if em == null:
			continue
		look_t[i] -= delta
		if look_t[i] > 0.0:
			continue
		look_t[i] = LOOK_EVERY
		# a trigger, on the screen or off it (pass 54)
		if em.nearest_index(pos[i], trigger[i], "", true) >= 0:
			pop(i)


## Bomblet `i` goes off (and, chained, every bomblet within CHAIN_RADIUS of it, and theirs): the blast, a burst of fire, the
## lob's boom.
func pop(i: int) -> void:
	if alive[i] == 0:
		return
	var stack: Array = [i]
	while not stack.is_empty():
		var j: int = stack.pop_back()
		if alive[j] == 0:
			continue
		var at: Vector3 = pos[j]
		var chained := chain[j] == 1
		_blast(j)
		_release(j)
		if chained:
			for k in range(MAX):
				if alive[k] == 1 and Vector2(pos[k].x - at.x, pos[k].z - at.z).length() <= CHAIN_RADIUS:
					stack.append(k)


func _blast(i: int) -> void:
	pops += 1
	var w: WeaponInstance = weapon[i]
	var em: EnemyManager = game.get("enemies") if game else null
	var at: Vector3 = pos[i]
	if em:
		var before := Run.kills
		em.damage_radius(at, radius[i], dmg[i], w.def.id if w else "", kbf[i])
		if w:
			w.kills += Run.kills - before
	if game and game.has_method("fx_burst"):
		game.fx_burst(at + Vector3(0, 0.2, 0), Color(1.0, 0.72, 0.3), radius[i])
	var fx = game.get("fx") if game else null
	if fx and fx.has_method("burst_strength"):
		fx.burst_strength(at, Color(1.0, 0.6, 0.2), radius[i] * 0.6, 1.4, false)
	if fx and fx.has_method("sand"):
		fx.sand(at, 0.5)
	Audio.play(str(w.def.sfx.get("hit", "w_lob_boom")) if w else "w_lob_boom", at)


func _process(_delta: float) -> void:
	_render()


## The bodies and their lamps: hopping ones grow and turn on the way out, armed ones blink red out of step with each other.
func _render() -> void:
	var n := 0
	for i in range(MAX):
		if alive[i] == 0:
			continue
		var s := 1.0
		var basis := Basis()
		if age[i] < TOSS:
			var u: float = clampf(age[i] / TOSS, 0.0, 1.0)
			s = lerpf(0.35, 1.0, u)
			basis = Basis(Vector3.UP, u * 7.0).rotated(Vector3.RIGHT, u * 4.0)
		_body_mm.set_instance_transform(n, Transform3D(basis.scaled(Vector3(s, s, s)), pos[i] + Vector3(0, BODY_R, 0)))
		var top: Vector3 = pos[i] + basis * Vector3(0, BODY_R + LAMP_R * 0.5, 0) * s + Vector3(0, BODY_R, 0)
		_lamp_mm.set_instance_transform(n, Transform3D(Basis().scaled(Vector3(s, s, s)), top))
		var on: bool = int((_clock + float(order[i]) * 0.37) * BLINK_HZ * 2.0) % 2 == 0
		_lamp_mm.set_instance_color(n, LAMP_ON if on else LAMP_OFF)
		n += 1
	_body_mm.visible_instance_count = n
	_lamp_mm.visible_instance_count = n
