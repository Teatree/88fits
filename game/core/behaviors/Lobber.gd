## Lobs an arcing projectile at the densest crowd. Explodes on landing. Evolution splits into bomblets.
class_name Lobber
extends WeaponBehavior


func _fire() -> bool:
	var enemies: EnemyManager = game.enemies
	var range_m := stat("range", 10.0)
	# a poison or fire bomb looks for the thickest crowd of creatures not carrying its element; plain bombs take any crowd
	var healthy := inst.def.targeting == "densest_healthy" or inst.def.targeting == "healthy"
	var target := enemies.densest_point(player.global_position, range_m, inst.element() if healthy else "")
	if target == Vector3.INF and healthy:
		target = enemies.densest_point(player.global_position, range_m, "")
	if target == Vector3.INF:
		var t := enemies.nearest_index(player.global_position, range_m * 1.5)
		if t < 0:
			return false
		target = enemies.pos[t]
	var amount: int = max(stat_int("amount", 1), 1)
	var from: Vector3 = player.global_position + Vector3(0, 1.2, 0)
	for k in range(amount):
		var off := Vector3.ZERO
		if k > 0:
			off = Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0))
		game.projectiles.lob(projectile_kind, from, target + off, stat("speed", 9.0), stat("damage", 25.0), stat("area", 2.5), inst, stat("knockback", 3.0), inst.def.params)
	sfx("fire", from)
	return true
