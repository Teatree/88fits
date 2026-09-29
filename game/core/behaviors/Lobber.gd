## Lobs an arcing projectile at the densest crowd. Explodes on landing. Evolution splits into bomblets.
## Bombs spread (pass 36): each bomb of a volley, and each bomb weapon, picks a crowd no other bomb is headed for or has
## just come down on (ProjectileManager.claimed_spots); they double up only when there is no other crowd in range.
class_name Lobber
extends WeaponBehavior


func _fire() -> bool:
	var enemies: EnemyManager = game.enemies
	var range_m := stat("range", 10.0)
	# a poison or fire bomb looks for the thickest crowd of creatures not carrying its element; plain bombs take any crowd
	var healthy := inst.def.targeting == "densest_healthy" or inst.def.targeting == "healthy"
	var el := inst.element() if healthy else ""
	var amount: int = max(stat_int("amount", 1), 1)
	var hero := player.global_position
	var keep_r := maxf(stat("area", 2.5), 1.5)
	var taken: Array = game.projectiles.claimed_spots()
	var targets: Array = []
	for k in range(amount):
		var avoid: Array = taken + targets
		var t := enemies.densest_point(hero, range_m, el, avoid, keep_r)
		if t == Vector3.INF and el != "":
			t = enemies.densest_point(hero, range_m, "", avoid, keep_r)
		if t == Vector3.INF:
			break
		targets.append(t)
	if targets.is_empty():
		# every crowd in range is already someone's target (or there is only the one): the thickest again
		var t0 := enemies.densest_point(hero, range_m, el)
		if t0 == Vector3.INF and el != "":
			t0 = enemies.densest_point(hero, range_m, "")
		if t0 == Vector3.INF:
			var n := enemies.nearest_index(hero, range_m * 1.5)
			if n < 0:
				return false
			t0 = enemies.pos[n]
		targets.append(t0)
	# bombs left over land round the crowds found, not on the same spot
	var found := targets.size()
	while targets.size() < amount:
		var b: Vector3 = targets[targets.size() % found]
		targets.append(b + Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0)))
	# from the companion when it has one (Needle Rain throws from the dart), else from the hero's hand
	var from: Vector3 = _stray.global_position if _stray else hero + Vector3(0, 1.2, 0)
	for target: Vector3 in targets:
		var lp: Dictionary = inst.params.duplicate()
		lp["throw_dir"] = (target - from) * Vector3(1, 0, 1)
		game.projectiles.lob(projectile_kind, from, target, stat("speed", 9.0), stat("damage", 25.0), stat("area", 2.5), inst, stat("knockback", 3.0), lp)
	sfx("fire", from)
	return true
