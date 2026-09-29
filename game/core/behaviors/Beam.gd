## Chain lightning. Picks a random enemy in range, chains to the nearest unhit enemies.
## Storm Cloud (params.follow) strikes from a cloud above the player instead.
class_name Beam
extends WeaponBehavior

var _cloud: Node3D


func _shows_held() -> bool:
	return bool(inst.params.get("follow", false))


func _on_setup() -> void:
	_cloud = visual.get_node_or_null("Held")


func _tick(delta: float) -> void:
	if _cloud and _cloud.visible:
		_cloud.global_position = _cloud.global_position.lerp(player.global_position + Vector3(0, 3.2, 0), delta * 4.0)
		_cloud.rotation.y += delta * 0.5


func _fire() -> bool:
	var enemies: EnemyManager = game.enemies
	var range_m := stat("range", 9.0)
	var first := enemies.random_in_range(player.global_position, range_m)
	if first < 0:
		return false
	var chains: int = max(stat_int("chains", 2), 0)
	var damage := stat("damage", 12.0)
	var pdmg := stat("poison_damage", 0.0)
	var fdmg := stat("fire_damage", 0.0)
	var zone = inst.params.get("zone")
	var origin: Vector3 = _cloud.global_position if (_cloud and _cloud.visible) else player.global_position + Vector3(0, 1.0, 0)
	var points: Array = [origin]
	var hit: Array = []
	var current := first
	for k in range(chains + 1):
		if current < 0:
			break
		hit.append(current)
		var p: Vector3 = enemies.pos[current] + Vector3(0, 0.6, 0)
		points.append(p)
		# Venom Arc, Plasma: the arc carries the element; Static Field: it leaves a shocking patch under every hit
		if pdmg > 0.0:
			enemies.poison(current, inst.def.id, pdmg, maxi(stat_int("poison_stacks", 1), 1), stat("poison_duration", 8.0))
		if fdmg > 0.0:
			enemies.ignite(current, inst.def.id, fdmg, stat("fire_duration", 1.8), stat("fire_spread", 0.4))
		if zone is Dictionary:
			game.spawn_zone(enemies.pos[current], float(zone.get("radius", 1.2)), float(zone.get("seconds", 2.0)), damage * float(zone.get("damage_mult", 0.35)) / maxf(float(zone.get("tick", 0.5)), 0.1), float(zone.get("tick", 0.5)), inst, 0.0)
		if enemies.damage(current, damage, inst.def.id, enemies.pos[current] - player.global_position, stat("knockback", 0.0)):
			inst.kills += 1
		game.fx_hit(p, inst.def)
		# next: nearest unhit within 5 m of the current one
		var best := -1
		var best_d := 25.0
		for e in enemies.indices_in_radius(enemies.pos[current], 5.0):
			if hit.has(e):
				continue
			var d := enemies.pos[e].distance_squared_to(enemies.pos[current])
			if d < best_d:
				best_d = d
				best = e
		current = best
	game.fx_lightning(points)
	sfx("fire", origin)
	return true
