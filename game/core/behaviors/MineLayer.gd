## Drops a mine where the hero walks. A mine waits on the ground until a creature steps on it, then explodes with the
## weapon's damage and area; old mines beyond params.max_mines are removed, and every mine expires after `lifetime`.
## Pass 48: Extra Supply (params.extra_supply): that share of the drops lays twice as many mines; the Jackrabbit's
## `jackrabbit.double` doubles every drop. The cap counts every mine, and takes the oldest one still lying armed (a mine
## in the air is about to blow anyway). Wide Reach's springs ask spring_target for a creature, so the mines in reach
## share the crowd out instead of all leaping at its first goblin (see Mine.gd).
## Pass 51, `params.lay_ahead` (the Jackrabbit Mines, Garry: "the mines appear a bit in front of where the Player is
## walking to, allowing a small level of control"): while the hero walks (faster than LAY_AHEAD_SPEED), each drop is
## flicked that many metres ahead along his walk (Mine.toss_to: a short hop from his feet) instead of left at his heels;
## standing, they drop at his feet as ever.
class_name MineLayer
extends WeaponBehavior

var _mines: Array = []
var _mine_mesh: Mesh
var _mine_mat: Material
## the creature each springing mine is after: {spawn serial: mine}
var _claims: Dictionary = {}
## drops so far and how many of them were doubled (tests, the arena)
var drops := 0
var doubled := 0
## below this speed (m/s) the hero is standing and the mines drop at his feet (params.lay_ahead)
const LAY_AHEAD_SPEED := 0.6


func _on_setup() -> void:
	var held := visual.get_node_or_null("Held")
	if held is MeshInstance3D and held.mesh:
		_mine_mesh = held.mesh
		_mine_mat = held.material_override
		held.visible = false
	else:
		var c := CylinderMesh.new()
		c.top_radius = 0.28
		c.bottom_radius = 0.34
		c.height = 0.16
		c.radial_segments = 10
		_mine_mesh = c
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.36, 0.42, 0.28)
		_mine_mat = m


## Where this drop's mines go (pass 51): `params.lay_ahead` metres ahead of the hero along his walk while he walks, else
## at his feet.
func lay_point() -> Vector3:
	var at: Vector3 = player.global_position
	var la := float(inst.params.get("lay_ahead", 0.0))
	if la <= 0.0:
		return at
	var v = player.get("velocity")
	var flat := Vector3.ZERO
	if v is Vector3:
		flat = Vector3((v as Vector3).x, 0.0, (v as Vector3).z)
	if flat.length() < LAY_AHEAD_SPEED:
		return at
	return at + flat.normalized() * la


## Whether this drop lays twice as many: always for the Jackrabbit, else Extra Supply's share of the time.
func _doubles() -> bool:
	var jb = inst.params.get("jackrabbit")
	if jb is Dictionary and bool((jb as Dictionary).get("double", false)):
		return true
	var p := float(inst.params.get("extra_supply", 0.0))
	return p > 0.0 and Dice.r.randf() < p


func _fire() -> bool:
	var amount: int = maxi(stat_int("amount", 1), 1)
	drops += 1
	if _doubles():
		amount *= 2
		doubled += 1
	var max_mines := int(inst.params.get("max_mines", 8))
	var ahead := lay_point()
	for k in range(amount):
		var mine := Mine.new()
		mine.setup(self, _mine_mesh, _mine_mat, stat("damage", 25.0), stat("area", 2.2), stat("knockback", 6.0), stat("lifetime", 25.0), float(inst.params.get("trigger_radius", 0.7)))
		game.add_child(mine)
		var off := Vector3.ZERO
		if k > 0:
			off = Vector3(Dice.r.randf_range(-1.5, 1.5), 0, Dice.r.randf_range(-1.5, 1.5))
		var p: Vector3 = ahead + off
		p.y = game.map.height_at(p.x, p.z) if game.map else 0.0
		var feet: Vector3 = player.global_position
		if ahead.distance_squared_to(feet) > 0.01:
			# flicked ahead from his feet (pass 51, lay_ahead): it lands armed where he is heading
			feet.y = game.map.height_at(feet.x, feet.z) if game.map else 0.0
			mine.global_position = feet
			mine.toss_to(p)
		else:
			mine.global_position = p
		_mines.append(mine)
	_mines = _mines.filter(func(m): return is_instance_valid(m) and not m.is_queued_for_deletion())
	# over the cap: the oldest armed ones go (a mine already crouching or in the air blows on its own)
	var over := _mines.size() - max_mines
	var k2 := 0
	while over > 0 and k2 < _mines.size():
		var old: Mine = _mines[k2]
		if old.is_armed():
			_mines.remove_at(k2)
			old.queue_free()
			over -= 1
		else:
			k2 += 1
	sfx("place", player.global_position)
	return true


## The mines lying now (tests).
func mines() -> Array:
	return _mines.filter(func(m): return is_instance_valid(m) and not m.is_queued_for_deletion())


## Wide Reach: the creature a mine at `from` springs at, the nearest within `sense` that no other mine is after; the
## mine claims it. -1 for none.
func spring_target(from: Vector3, sense: float, mine: Node) -> int:
	var em: EnemyManager = game.enemies
	var best := -1
	var best_d := sense * sense
	for i in em.indices_in_radius(from, sense):
		# (pass 73, lane GROUND: never one still rising out of the sand)
		if em.alive[i] == 0 or em.state[i] == EnemyManager.STATE_DYING or not em.targetable(i):
			continue
		var holder = _claims.get(em.serial[i])
		if holder != null and is_instance_valid(holder) and holder != mine:
			continue
		var d := Vector2(em.pos[i].x - from.x, em.pos[i].z - from.z).length_squared()
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		release_claim(mine)
		_claims[em.serial[best]] = mine
	return best


## A mine lets go of the creature it was after (it blew, or went for another).
func release_claim(mine: Node) -> void:
	for key in _claims.keys():
		if _claims[key] == mine:
			_claims.erase(key)


func _tick(_delta: float) -> void:
	_mines = _mines.filter(func(m): return is_instance_valid(m))
	for key in _claims.keys():
		if not is_instance_valid(_claims[key]):
			_claims.erase(key)


## The mines go with the weapon (a swap, the evolution).
func _exit_tree() -> void:
	for m in _mines:
		if is_instance_valid(m):
			m.queue_free()
	_mines.clear()
	_claims.clear()
