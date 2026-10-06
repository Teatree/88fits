## Chain lightning. Picks a random enemy in range, chains to the nearest unhit enemies.
## Storm Cloud (params.follow) strikes from a cloud above the player instead.
## Echo Zap (pass 53, params.echo_zap {chance, count, damage_frac, gap}; "Aftershock" in Garry's words, but that name is the
## Hammer's motion pick since pass 35; Garry: "a hit or a chain hit have 20% chance
## of a smaller version of the zap to hit the same enemy 3 more time with less damage ... there should be visible electric
## discharge on the enemy who is affected by this"): every hit of the arc rolls `chance`; a proc queues `count` follow-up
## zaps on that creature (its slot and its serial, so the next creature in the slot is never zapped), `gap` seconds apart,
## each for `damage_frac` of the hit, with a discharge: three or four short bolts out of the air round it into its body,
## sparks, and a pale blue tint while they last. The Storm Cloud's `final` lifts the chance to 35%.
class_name Beam
extends WeaponBehavior

const SHOCK_TINT := Color(0.62, 0.8, 1.0)
const SHOCK_COLOR := Color(0.55, 0.75, 1.0)

var _cloud: Node3D
## the echoes waiting: {i, serial, left, t, gap, dmg}
var _shocks: Array = []
## echoes landed (tests, the smoke run)
var shocks_landed := 0


func _shows_held() -> bool:
	return bool(inst.params.get("follow", false))


func _on_setup() -> void:
	_cloud = visual.get_node_or_null("Held")


func _tick(delta: float) -> void:
	if _cloud and _cloud.visible:
		_cloud.global_position = _cloud.global_position.lerp(player.global_position + Vector3(0, 3.2, 0), delta * 4.0)
		_cloud.rotation.y += delta * 0.5
	_tick_shocks(delta)


## How many echoes are still to land (tests).
func pending_shocks() -> int:
	var n := 0
	for s: Dictionary in _shocks:
		n += int(s["left"])
	return n


## A hit on creature `i` for `damage` procs Echo Zap: `count` smaller zaps queued on it, the first a `gap` away.
func _queue_shock(enemies: EnemyManager, i: int, damage: float, cfg: Dictionary) -> void:
	var gap: float = maxf(float(cfg.get("gap", 0.25)), 0.02)
	_shocks.append({"i": i, "serial": enemies.serial[i], "left": maxi(int(cfg.get("count", 3)), 1), "t": gap, "gap": gap,
		"dmg": damage * float(cfg.get("damage_frac", 0.4))})


func _tick_shocks(delta: float) -> void:
	if _shocks.is_empty():
		return
	var enemies: EnemyManager = game.enemies
	for k in range(_shocks.size() - 1, -1, -1):
		var s: Dictionary = _shocks[k]
		s["t"] = float(s["t"]) - delta
		if float(s["t"]) > 0.0:
			continue
		var i: int = int(s["i"])
		if not enemies.is_alive(i) or enemies.serial[i] != int(s["serial"]) or enemies.hidden[i] == 1:
			# the creature is gone (or another stands in its slot): the rest of its echoes go with it
			_shocks.remove_at(k)
			continue
		s["t"] = float(s["gap"])
		s["left"] = int(s["left"]) - 1
		_zap(enemies, i, float(s["dmg"]), float(s["gap"]))
		if int(s["left"]) <= 0:
			_shocks.remove_at(k)


## One echo on creature `i`: the damage, and the discharge on it.
func _zap(enemies: EnemyManager, i: int, damage: float, gap: float) -> void:
	var body: Vector3 = enemies.pos[i] + Vector3(0, enemies.size[i] * 0.5, 0)
	if enemies.damage(i, damage, inst.def.id, Vector3.ZERO, 0.0):
		inst.kills += 1
	shocks_landed += 1
	var fx = game.get("fx")
	if fx and fx.has_method("lightning"):
		# three or four short jagged bolts from the air round it into its body
		var n: int = 3 + (randi() % 2)
		for b in range(n):
			var a: float = randf() * TAU
			var r: float = randf_range(0.6, 1.0)
			var from: Vector3 = body + Vector3(cos(a) * r, randf_range(-0.2, 0.6), sin(a) * r)
			fx.lightning([from, body], SHOCK_COLOR, 0.5)
		if fx.has_method("mote"):
			for s in range(3):
				fx.mote(body, Vector3(randf_range(-2.0, 2.0), randf_range(1.0, 3.0), randf_range(-2.0, 2.0)), 0.3, 0.12, Color(0.8, 0.92, 1.0, 0.9))
	if enemies.is_alive(i):
		enemies.set_status_tint(i, SHOCK_TINT, gap + 0.1)
	sfx("hit", body)


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
		# Echo Zap (pass 53): a hit, first or chained, may queue smaller zaps on the same creature (never on a kill)
		var asf = inst.params.get("echo_zap")
		if asf is Dictionary and enemies.is_alive(current) and randf() < float((asf as Dictionary).get("chance", 0.0)):
			_queue_shock(enemies, current, damage, asf)
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
