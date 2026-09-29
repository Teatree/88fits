## A weapon: a reusable behaviour scene plus numbers, a level table of Effects, and a visual scene.
class_name WeaponDef
extends ContentDef

## Behaviour primitive: ProjectileEmitter | Orbiter | Lobber | Beam | Spawner
@export var behavior: String = "ProjectileEmitter"
## free-form tags ("homing", "explosive"): passives can aim at every weapon carrying one (`target: "tag:homing"`)
@export var tags: Array = []
## nearest | forward | random | densest | orbit
@export var targeting: String = "nearest"
## Base weapon stats: damage, cooldown, amount, pierce, area, speed, duration, knockback, chains, range, spread_deg...
@export var base: Dictionary = {}
## levels[i] is an Array of Effect applied cumulatively when reaching level i+1. levels[0] is usually empty.
@export var levels: Array = []
@export var max_level: int = 8
## Passive id required for evolution, and the weapon id it becomes.
@export var evolves_with: String = ""
@export var evolves_into: String = ""
## True for evolved forms: never offered in cards, cannot level.
@export var is_evolution: bool = false
## Which weapon this evolved from (set on evolutions for the collection screen).
@export var evolved_from: String = ""
## Sound ids by event: fire, hit, loop, place, boom...
@export var sfx: Dictionary = {}
## Visual scene: Held (mesh near player), Projectile (MeshInstance3D template), Muzzle/Hit particles.
@export var visual: PackedScene
@export var visual_file: String = ""
## Extra behaviour parameters that are not stats, e.g. {"orbit_radius": 2.0}
@export var params: Dictionary = {}
## One hero's own weapon (pass 35: the Drifter's Revolver): offered to nobody else, by cards, chests, shops or the Stranger.
@export var hero: String = ""


func kind() -> String:
	return "weapon"


func effects_for_level(level: int) -> Array:
	## All effects accumulated from level 1 up to and including `level`.
	var out: Array = []
	for i in range(min(level, levels.size())):
		var lv = levels[i]
		if lv is Array:
			for e in lv:
				if e is Effect:
					out.append(e)
	return out


func effects_at_level(level: int) -> Array:
	## Only the effects gained by reaching exactly `level` (1-based).
	if level - 1 < 0 or level - 1 >= levels.size():
		return []
	var lv = levels[level - 1]
	return lv if lv is Array else []
