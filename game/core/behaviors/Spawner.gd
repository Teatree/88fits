## Drops stationary turrets that shoot the nearest enemy. Turret Family turrets never expire and pull gems.
## The visual scene's "Turret" node is the model every turret copies (pass 46, art/props/turret_buddy.glb; Turret.gd shows
## the stance's stand); without one each turret is built from the "Held" box as before. `amount` turrets a drop, set
## round the hero; at most params.max_turrets (6) times params.max_turrets_mult (Buddy Squad: 2) stand at once, the
## oldest going first.
class_name Spawner
extends WeaponBehavior

var _turrets: Array = []
var _turret_mesh: Mesh
var _turret_mat: Material
var _proto: Node3D


func _on_setup() -> void:
	_proto = visual.get_node_or_null("Turret") as Node3D
	if _proto:
		_proto.visible = false
	var held := visual.get_node_or_null("Held")
	if held is MeshInstance3D and held.mesh:
		_turret_mesh = held.mesh
		_turret_mat = held.material_override
		held.visible = false
	else:
		var b := BoxMesh.new()
		b.size = Vector3(0.7, 0.7, 0.7)
		_turret_mesh = b
		_turret_mat = _default_material()


## How many turrets may stand at once.
func max_turrets() -> int:
	return maxi(int(round(float(inst.params.get("max_turrets", 6)) * float(inst.params.get("max_turrets_mult", 1.0)))), 1)


## The turrets standing now (tests).
func standing() -> Array:
	return _turrets.filter(func(t): return is_instance_valid(t) and not (t as Turret)._expiring)


func _fire() -> bool:
	var amount: int = max(stat_int("amount", 1), 1)
	var cap := max_turrets()
	if Aim.covers(inst):
		return _fire_placed(amount, cap)
	var a0 := Dice.r.randf() * TAU
	for k in range(amount):
		var t := Turret.new()
		t.setup(self, _proto, _turret_mesh, _turret_mat)
		game.add_child(t)
		# one turret lands anywhere near the hero; a drop of several spreads round him instead of in a heap
		var off := Vector3(Dice.r.randf_range(-1.2, 1.2), 0, Dice.r.randf_range(-1.2, 1.2))
		if amount > 1:
			var a := a0 + TAU * float(k) / float(amount) + Dice.r.randf_range(-0.25, 0.25)
			off = Vector3(cos(a), 0, sin(a)) * Dice.r.randf_range(1.0, 1.6)
		var p: Vector3 = player.global_position + off
		p.y = game.map.height_at(p.x, p.z) if game.map else 0.0
		t.global_position = p
		_turrets.append(t)
	while _turrets.size() > cap:
		var old: Turret = _turrets.pop_front()
		if is_instance_valid(old):
			old.expire()
	sfx("place", player.global_position)
	return true


## Pass 136 (lane PLACED; the aim proposal: "The turret is set down 2 to 3 m ahead, on the crowd's side ... Its own gun
## keeps aiming by itself"; Garry's R6: in a circle, not a cone): while Aim.covers(this weapon) each turret of a drop
## goes on a spot in the ring `params.aim.min_r`..`max_r` (2-3 m) round the Outlaw (Aim.circle_spots), each candidate
## scored by the creatures within its gun's `range` of it (the crowd's side), the best `best_chance` of the time; the
## turrets of a drop keep `apart` (1 m) x APART from each other. Every turret starts with its head turned down his facing
## (the Bunker's slow traverse: its first shots go where he looked); then it aims by itself as ever.
func _fire_placed(amount: int, cap: int) -> bool:
	var c := Aim.cfg(inst)
	var hero: Vector3 = player.global_position
	var lo := float(c.get("min_r", 2.0))
	var hi := maxf(float(c.get("max_r", 3.0)), lo + 0.1)
	var reach := stat("range", 8.0)
	var em: EnemyManager = game.enemies
	var scorer := func(cands: Array) -> Array:
		var out: Array = []
		for p: Vector3 in cands:
			out.append(Aim.spot_score(em, p, reach))
		return out
	var spots: Array = Aim.circle_spots(em, hero, lo, hi, amount, float(c.get("apart", 1.0)), float(c["best_chance"]), "", [], Aim.arena_ok(game), scorer)
	var f := Aim.facing(player)
	for at: Vector3 in spots:
		var t := Turret.new()
		t.setup(self, _proto, _turret_mesh, _turret_mat)
		game.add_child(t)
		var p := at
		p.y = game.map.height_at(p.x, p.z) if game.map else 0.0
		t.global_position = p
		t._set_head_yaw(atan2(-f.x, -f.z))
		_turrets.append(t)
	while _turrets.size() > cap:
		var old: Turret = _turrets.pop_front()
		if is_instance_valid(old):
			old.expire()
	sfx("place", player.global_position)
	return not spots.is_empty()


func _tick(_delta: float) -> void:
	_turrets = _turrets.filter(func(t): return is_instance_valid(t))
