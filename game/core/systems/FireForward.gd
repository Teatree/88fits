## "Fire forward" (pass 95, lane ITEMS; Garry: "Change the following items to always fire at a sequence (add this as a
## togglable option in the debug version of settings, by default it's off): Saber, Spear, Hammer, Frisbee, Tumbleweed -
## always in the direction Player is facing; Basketball - always throw in front of where player is facing, but since it
## needs to bounce off of an enemy when hitting them, it will simply fall to the floor and disappear in case there are
## no nearby enemies; All of these will stop just shooting forward once there is an enemy that's 75% of the weapon's
## attack range from the hero").
## The one rule, read by the behaviours at every pull (ProjectileEmitter._fire's usual aim, Thruster._fire,
## Smasher._fire, Frisbee._fire): while the debug switch Settings.fire_forward is on (off for everyone, locked off in
## the production build) and the weapon carries `params.fire_forward` (content: the Sabre, the Spear (pike), the Hammer,
## the Frisbee, the Tumbleweed, the Basketball and their evolutions), it fires along the hero's facing unless a living
## creature stands within NEAR_FRAC (75%) of the weapon's `range` of him (the sheet's number, so Reach and the like
## count; the Sabre's 2.6 m makes that 1.95 m, the Hammer's 4.6 m 3.45 m); then it aims as it always did. The
## Basketball thrown this way carries "drop_alone" (ProjectileEmitter._throw_ball): with nobody within its bounce reach
## at the end of its flight it drops to the sand and is gone (ProjectileManager._drop_alone): no return, no catch, no
## Heat. The Hammer's forward blow lands NEAR_FRAC of its reach ahead (Smasher._fire), the Frisbee's arc crosses its
## line at the range's end.
class_name FireForward
extends RefCounted

## The share of the weapon's range within which a creature puts it back on its usual aim.
const NEAR_FRAC := 0.75


## Whether the switch is on (Settings.fire_forward).
static func on() -> bool:
	return bool(Settings.fire_forward)


## Whether `inst` is one of the weapons the rule covers (`params.fire_forward` in its content).
static func covers(inst: WeaponInstance) -> bool:
	return inst != null and bool(inst.params.get("fire_forward", false))


## The reach within which a creature puts the weapon back on its usual aim: NEAR_FRAC x the sheet's range (`default_range`
## when the sheet has none).
static func near_range(inst: WeaponInstance, default_range: float) -> float:
	return maxf(inst.stat("range", default_range), 0.0) * NEAR_FRAC


## Whether a living creature (not dying, not still rising out of the sand) stands within `r` of `hero` on the ground plane.
static func creature_near(em: EnemyManager, hero: Vector3, r: float) -> bool:
	if em == null or not is_instance_valid(em) or r <= 0.0:
		return false
	var r2 := r * r
	for e in em.indices_in_radius(hero, r + 0.5):
		if em.alive[e] == 0 or em.state[e] == EnemyManager.STATE_DYING:
			continue
		if em.has_method("targetable") and not em.targetable(e):
			continue
		var dx: float = em.pos[e].x - hero.x
		var dz: float = em.pos[e].z - hero.z
		if dx * dx + dz * dz <= r2:
			return true
	return false


## The way the weapon fires now: the hero's facing (on the ground plane, unit length) when the switch is on, the weapon is
## covered and no creature stands within near_range of the hero; Vector3.ZERO = aim as usual.
static func dir(inst: WeaponInstance, player: Node3D, em: EnemyManager, default_range: float = 9.0) -> Vector3:
	if player == null or not on() or not covers(inst):
		return Vector3.ZERO
	if creature_near(em, player.global_position, near_range(inst, default_range)):
		return Vector3.ZERO
	return facing(player)


## The hero's facing on the ground plane (Vector3.FORWARD for a hero without one).
static func facing(player: Node3D) -> Vector3:
	var f: Vector3 = player.forward() if player.has_method("forward") else Vector3.FORWARD
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD
