## Where an elemental bomb landed: a cloud of green smoke (poison) or a pool of fire. Poison is a draped disc and a
## few billowing puffs; fire (pass 33) is a thin spill of oil soaking into the sand, see-through and fading at its lobed
## rim, with flame tongues (Fx.flame) licking up all over it. Every creature inside is poisoned or set alight (the
## effects themselves live in EnemyManager). Fades in its last second. Since pass 33.8 the spill and the puffs are
## instances in the Telegraphs pools (one draw call for every spill on the map), not meshes of their own.
## Pass 48 reads a few keys off `params` (as Game.spawn_cloud hands them on): `pool_seconds` replaces the weapon's
## cloud_seconds (a Pea Cannon's puff, a Moonshine line or death pool), `pool_grow` grows the spill to (1 + grow) x its
## first radius over its life (the Moonshine), `line_to` (a ground point) makes it a burning line from where it stands to
## there, `radius` either side (the Moonshine's trail), and `death_of` (a weapon id) counts it among that weapon's
## death pools (group DEATH_GROUP). A poison cloud's poisonings go through ProjectileManager.weapon_poison, so Curare
## rolls on them.
class_name ElementCloud
extends Node3D

## Every spill a creature's death splashed (the Moonshine's, pass 48): Lobber counts them to keep its cap.
const DEATH_GROUP := "death_pool"
## A burning line is drawn as spills this far apart, as a share of its radius.
const LINE_STEP := 1.1

var game: Node
var weapon: WeaponInstance
var element := "poison"
var radius := 2.2
var life := 4.0
var dmg := 3.0
var stacks := 1
var duration := 10.0
var spread := 0.5
var slow := 0.0     # Oil Slick: creatures in the cloud move this much slower
## Blue fire (pass 48: Methanol, Moonshine; the weapon's WeaponInstance.blue_fire): the pool's flames burn blue. The
## creatures it lights burn blue on their own (EnemyManager.ignite asks the weapon).
var blue := false
## The spill's own params as Game.spawn_cloud got them (pass 48, see the head of this file).
var params: Dictionary = {}
## Pass 48 (the Moonshine): how much the spill grows over its life, 0 = it stays as it landed.
var grow := 0.0
## Pass 48 (the Moonshine's trail): the far end of a burning line on the ground, INF for a round spill.
var line_to := Vector3.INF
var _r0 := 2.2           # the radius it landed with (a growing spill grows from it)
var _r_drawn := 0.0      # the radius the spill was last drawn at
var _seed := 0.0
var _disc_col := Color(1, 1, 1, 1)
var _puff_col := Color(0.6, 0.84, 0.5, 0.16)
var _t := 0.0
var _total := 4.0
var _check := 0.0
var _tg: Telegraphs
var _disc := -1           # the spill's id in the Telegraphs pools
var _line_discs: Array = []   # a burning line's spills, ids in the pools
var _puffs: Array = []    # {id, r (sphere radius), at (offset from the cloud), rot}
var _flame_t := 0.0


func setup(p_game: Node, w: WeaponInstance, r: float, cloud_seconds: float, p_dmg: float, p_stacks: int, p_duration: float, p_element: String = "poison", p_spread: float = 0.5) -> void:
	game = p_game
	weapon = w
	radius = r
	life = cloud_seconds
	_total = cloud_seconds
	dmg = p_dmg
	stacks = p_stacks
	duration = p_duration
	element = p_element
	spread = p_spread
	if element == "fire":
		_disc_col = Color(1.0, 0.45, 0.12, 0.45)
		_puff_col = Color(1.0, 0.6, 0.2, 0.5)
	# pass 48: the keys the spill's own params may carry
	if params.has("pool_seconds"):
		life = maxf(float(params["pool_seconds"]), 0.1)
		_total = life
	grow = maxf(float(params.get("pool_grow", 0.0)), 0.0)
	var lt = params.get("line_to")
	if lt is Vector3:
		line_to = lt
	if str(params.get("death_of", "")) != "":
		add_to_group(DEATH_GROUP)


func _ready() -> void:
	_tg = game.telegraphs
	var at := global_position
	_seed = randf()
	if line_to != Vector3.INF:
		_ready_line()
		return
	_disc = _hold_spill(at, radius)
	_r_drawn = radius
	_r0 = radius
	# the spill's colours are its own, so the disc's alpha is the fade alone
	_disc_col = Color(1, 1, 1, 1)
	radius = maxf(radius, 0.4)
	if element == "fire":
		# the oil catches the moment it lands: two tongues at once, the rest follow on the clock
		for k in range(2):
			_flame_at(1.0)
		return
	for k in range(6):
		var pr := radius * randf_range(0.28, 0.42)
		var a := TAU * k / 6.0 + randf() * 0.6
		var off := Vector3(cos(a) * radius * 0.5, 0.4 + randf() * 0.4, sin(a) * radius * 0.5)
		_puffs.append({"id": _tg.hold_puff(_puff_col), "r": pr, "at": off, "rot": 0.0})
	_place_puffs(0.0, 1.0)


## The spill itself at `at`, `r` across: black oil (fire) or a muted green puddle (poison), see-through, gone at its
## lobed rim. Returns its id in the pools.
func _hold_spill(at: Vector3, r: float) -> int:
	if element == "fire":
		# the spill: black oil, see-through, gone at the rim (33.4: the faint orange pool of 33.2 did not show on the sand)
		return _tg.hold_blob(at, r, _seed, Color(0.02, 0.02, 0.02, 0.55), Color(0.03, 0.03, 0.03, 0.0))
	# a poison puddle (pass 33.1): muted green, see-through, gone at its lobed rim (it was a saturated green plate)
	return _tg.hold_blob(at, r, _seed, Color(0.34, 0.56, 0.26, 0.22), Color(0.45, 0.7, 0.34, 0.0))


## A burning line (pass 48, the Moonshine's trail): spills of `radius` every LINE_STEP x radius from here to `line_to`,
## two tongues of flame along it at once.
func _ready_line() -> void:
	_disc_col = Color(1, 1, 1, 1)
	radius = maxf(radius, 0.25)
	var a := global_position
	var b := line_to
	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var n: int = maxi(int(ceil(flat.length() / (radius * LINE_STEP))), 1)
	for k in range(n + 1):
		var p := a + flat * (float(k) / float(n))
		if game.map:
			p.y = game.map.height_at(p.x, p.z)
		_line_discs.append(_hold_spill(p, radius))
	if element == "fire":
		for k in range(2):
			_flame_at(1.0)


func _exit_tree() -> void:
	if is_instance_valid(_tg):
		_tg.release(_disc)
		for id in _line_discs:
			_tg.release(int(id))
		for p in _puffs:
			_tg.release(int(p["id"]))
	_disc = -1
	_line_discs.clear()
	_puffs.clear()


## One flame tongue at a random spot on the spill (or along the line), `k` times its full height.
func _flame_at(k: float) -> void:
	var at: Vector3
	if line_to != Vector3.INF:
		var f := randf()
		at = global_position.lerp(Vector3(line_to.x, global_position.y, line_to.z), f)
		var a0 := randf() * TAU
		at += Vector3(cos(a0), 0.0, sin(a0)) * randf() * radius * 0.6
	else:
		var a := randf() * TAU
		var rr := sqrt(randf()) * radius * 0.82
		at = global_position + Vector3(cos(a) * rr, 0.0, sin(a) * rr)
	if game.map:
		at.y = game.map.height_at(at.x, at.z)
	var h: float = clampf(0.6 + radius * 0.45, 0.6, 1.9) * randf_range(0.75, 1.2) * k
	# pass 76 (lane MOLO): a weapon whose look burns its pool in its own style (params.pool_flame {style, size}) stands
	# its flames there (WickFlames.ground_flame); without it, Fx's tongues as before
	if _pool_flame(at, h):
		return
	game.fx.flame(at, h, randf_range(0.45, 0.7), Fx.FLAME_ORANGE, blue)


## Pass 76 (lane MOLO): one of the spill's flames in the weapon's look (params.pool_flame {style, size, life}: "torch"
## or "cartoon", `size` x the height the spill gives it, `life` x its life), through ProjectileManager's wick flames.
## False (Fx's tongue instead) when the weapon has no pool_flame.
func _pool_flame(at: Vector3, h: float) -> bool:
	var pf = weapon.params.get("pool_flame") if weapon else null
	if not (pf is Dictionary):
		return false
	var pm = game.get("projectiles")
	if pm == null or not pm.has_method("wick_flames"):
		return false
	var d: Dictionary = pf
	var life: float = randf_range(0.45, 0.7) * float(d.get("life", 1.0))
	pm.wick_flames().ground_flame(at, h * float(d.get("size", 1.0)), life, str(d.get("style", "torch")), blue, _t < 0.05)
	return true


## The billows: each breathes, rises slowly and turns, and fades with the cloud (`fade` 0..1).
func _place_puffs(delta: float, fade: float) -> void:
	var grow_in: float = clampf(_t / 0.35, 0.0, 1.0)
	var at := global_position
	for k in range(_puffs.size()):
		var p: Dictionary = _puffs[k]
		var s: float = grow_in * (0.85 + 0.25 * sin(_t * 2.0 + k))
		var off: Vector3 = p["at"]
		off.y += delta * 0.12
		p["at"] = off
		p["rot"] = float(p["rot"]) + delta * 0.6
		var d: float = float(p["r"]) * 2.0 * s
		var xf := Transform3D(Basis(Vector3.UP, float(p["rot"])).scaled(Vector3(d, d, d)), at + off)
		_tg.set_puff(int(p["id"]), xf, _puff_col.a * fade * (0.8 + 0.2 * sin(_t * 3.0 + k * 1.3)))


## A growing spill (pass 48, the Moonshine): its radius now, eased out over its life.
func _grown_radius() -> float:
	var f: float = clampf(_t / maxf(_total, 0.1), 0.0, 1.0)
	return _r0 * (1.0 + grow * (1.0 - (1.0 - f) * (1.0 - f)))


## How much ground the spill covers (the flame clock's pace): a disc, or a line's length times its width.
func _area_m2() -> float:
	if line_to != Vector3.INF:
		var flat := Vector3(line_to.x - global_position.x, 0.0, line_to.z - global_position.z)
		return maxf(flat.length() * radius * 2.0, radius * radius)
	return radius * radius


func _process(delta: float) -> void:
	# pass 114 (lane REPLAY): the recorded frame's delta in a replay (Lockstep.dt)
	delta = Lockstep.dt(delta)
	if game == null or game.paused:
		return
	_t += delta
	life -= delta
	var fade: float = clampf(life / 1.0, 0.0, 1.0)
	var grow_in: float = clampf(_t / 0.35, 0.0, 1.0)
	if grow > 0.0 and _disc >= 0:
		radius = _grown_radius()
		# the pools have no resize for a spill: a new one in its place once it has grown by a twentieth
		if radius > _r_drawn * 1.05:
			_tg.release(_disc)
			_disc = _hold_spill(global_position, radius)
			_r_drawn = radius
	_tg.set_alpha(_disc, _disc_col.a * fade)
	for id in _line_discs:
		_tg.set_alpha(int(id), _disc_col.a * fade)
	if element == "fire":
		# tongues of fire all over the spill, as many at once as its size holds, lower as it burns out
		_flame_t -= delta
		if _flame_t <= 0.0 and life > 0.2:
			_flame_t = clampf(0.24 / _area_m2(), 0.045, 0.22)
			_flame_at((0.45 + 0.55 * fade) * (0.6 + 0.4 * grow_in))
	elif not _puffs.is_empty():
		_place_puffs(delta, fade)
	_check -= delta
	if _check <= 0.0:
		_check = 0.3
		_work()
	if life <= 0.0:
		queue_free()


## Everything standing in the spill is poisoned or set alight, and slowed by an Oil Slick's.
func _work() -> void:
	var em: EnemyManager = game.enemies
	var wid: String = weapon.def.id if weapon else ""
	var pm = game.get("projectiles")
	for e in _inside(em):
		if element == "fire":
			em.ignite(e, wid, dmg, duration, spread)
		elif weapon and pm != null and pm.has_method("weapon_poison"):
			# through the weapon's own poisoning (pass 48), so Curare rolls on a cloud too
			pm.weapon_poison(e, weapon, dmg, stacks, duration)
		else:
			em.poison(e, wid, dmg, stacks, duration)
		if slow > 0.0:
			em.slow(e, slow, 0.5)


## The creatures in the spill: within its radius, or within its radius of the line (the creature's own half-width
## counts, so one at the edge of a thin line is caught).
func _inside(em: EnemyManager) -> PackedInt32Array:
	if line_to == Vector3.INF:
		return em.indices_in_radius(global_position, radius)
	var a := global_position
	var ab := Vector3(line_to.x - a.x, 0.0, line_to.z - a.z)
	var l := ab.length()
	var out := PackedInt32Array()
	for e in em.indices_in_radius(a + ab * 0.5, l * 0.5 + radius + 0.6):
		var d := Vector3(em.pos[e].x - a.x, 0.0, em.pos[e].z - a.z)
		var along := clampf(d.dot(ab / l), 0.0, l) if l > 0.001 else 0.0
		var off := d - (ab / l) * along if l > 0.001 else d
		if off.length() <= radius + em.radius[e] * 0.5:
			out.append(e)
	return out
