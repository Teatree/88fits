## Where an elemental bomb landed: a cloud of green smoke (poison) or a pool of fire. Poison is a draped disc and a
## few billowing puffs; fire (pass 33) is a thin spill of oil soaking into the sand, see-through and fading at its lobed
## rim, with flame tongues (Fx.flame) licking up all over it. Every creature inside is poisoned or set alight (the
## effects themselves live in EnemyManager). Fades in its last second. Since pass 33.8 the spill and the puffs are
## instances in the Telegraphs pools (one draw call for every spill on the map), not meshes of their own.
class_name ElementCloud
extends Node3D

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
var _disc_col := Color(1, 1, 1, 1)
var _puff_col := Color(0.6, 0.84, 0.5, 0.16)
var _t := 0.0
var _total := 4.0
var _check := 0.0
var _tg: Telegraphs
var _disc := -1           # the spill's id in the Telegraphs pools
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


func _ready() -> void:
	_tg = game.telegraphs
	var at := global_position
	if element == "fire":
		# the spill: black oil, see-through, gone at the rim (33.4: the faint orange pool of 33.2 did not show on the sand)
		_disc = _tg.hold_blob(at, radius, randf(), Color(0.02, 0.02, 0.02, 0.55), Color(0.03, 0.03, 0.03, 0.0))
	else:
		# a poison puddle (pass 33.1): muted green, see-through, gone at its lobed rim (it was a saturated green plate)
		_disc = _tg.hold_blob(at, radius, randf(), Color(0.34, 0.56, 0.26, 0.22), Color(0.45, 0.7, 0.34, 0.0))
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


func _exit_tree() -> void:
	if is_instance_valid(_tg):
		_tg.release(_disc)
		for p in _puffs:
			_tg.release(int(p["id"]))
	_disc = -1
	_puffs.clear()


## One flame tongue at a random spot on the spill, `k` times its full height.
func _flame_at(k: float) -> void:
	var a := randf() * TAU
	var rr := sqrt(randf()) * radius * 0.82
	var at := global_position + Vector3(cos(a) * rr, 0.0, sin(a) * rr)
	if game.map:
		at.y = game.map.height_at(at.x, at.z)
	var h: float = clampf(0.6 + radius * 0.45, 0.6, 1.9) * randf_range(0.75, 1.2) * k
	game.fx.flame(at, h, randf_range(0.45, 0.7))


## The billows: each breathes, rises slowly and turns, and fades with the cloud (`fade` 0..1).
func _place_puffs(delta: float, fade: float) -> void:
	var grow: float = clampf(_t / 0.35, 0.0, 1.0)
	var at := global_position
	for k in range(_puffs.size()):
		var p: Dictionary = _puffs[k]
		var s: float = grow * (0.85 + 0.25 * sin(_t * 2.0 + k))
		var off: Vector3 = p["at"]
		off.y += delta * 0.12
		p["at"] = off
		p["rot"] = float(p["rot"]) + delta * 0.6
		var d: float = float(p["r"]) * 2.0 * s
		var xf := Transform3D(Basis(Vector3.UP, float(p["rot"])).scaled(Vector3(d, d, d)), at + off)
		_tg.set_puff(int(p["id"]), xf, _puff_col.a * fade * (0.8 + 0.2 * sin(_t * 3.0 + k * 1.3)))


func _process(delta: float) -> void:
	if game == null or game.paused:
		return
	_t += delta
	life -= delta
	var fade: float = clampf(life / 1.0, 0.0, 1.0)
	var grow: float = clampf(_t / 0.35, 0.0, 1.0)
	_tg.set_alpha(_disc, _disc_col.a * fade)
	if element == "fire":
		# tongues of fire all over the spill, as many at once as its size holds, lower as it burns out
		_flame_t -= delta
		if _flame_t <= 0.0 and life > 0.2:
			_flame_t = clampf(0.24 / (radius * radius), 0.045, 0.22)
			_flame_at((0.45 + 0.55 * fade) * (0.6 + 0.4 * grow))
	elif not _puffs.is_empty():
		_place_puffs(delta, fade)
	_check -= delta
	if _check <= 0.0:
		_check = 0.3
		var em: EnemyManager = game.enemies
		var wid: String = weapon.def.id if weapon else ""
		for e in em.indices_in_radius(global_position, radius):
			if element == "fire":
				em.ignite(e, wid, dmg, duration, spread)
			else:
				em.poison(e, wid, dmg, stacks, duration)
			if slow > 0.0:
				em.slow(e, slow, 0.5)
	if life <= 0.0:
		queue_free()
