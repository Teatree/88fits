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
## Pass 76 (lane LOOKS): the family's looks (ItemLooks): code -> the JSON entry resolved (only the keys it has: name,
## flavour, icon a Texture2D, visual a PackedScene, params, noun, nouns, note, shelved, fresh), `variant_base` the code
## the top-level fields are, `variant` on a base weapon the code its whole family plays (Registry.played_item_look: a
## phone's Save.item_looks over it; on an evolution it is not read). A look is worn in place (wear_look): display_name,
## flavour, icon, visual, params, noun and nouns are the look's while it is worn, the top level kept in `look_top`.
@export var variants: Dictionary = {}
@export var variant_base: String = ""
@export var variant: String = ""
## The weapon's thing words for TextGen ("stick" / "sticks"; "" = the behaviour's own: a Lobber's "grenade" / "grenades"):
## the top level's or the look's (TextGen.weapon_nouns; an evolution without any takes its family weapon's).
@export var noun: String = ""
@export var nouns: String = ""
## The top level while a look is worn (ItemLooks.top_of), and the family code it was last asked to wear ("?" never).
var look_top: Dictionary = {}
var look_worn := "?"
## The looks' code (pass 76), preloaded: it has no class_name (see its header).
const ItemLooks := preload("res://core/data/ItemLooks.gd")


func kind() -> String:
	return "weapon"


## The looks it can play (pass 76): its base first, then by code; shelved ones only when asked; [] with one look.
func variant_codes(include_shelved := false) -> Array:
	var all: Array = ItemLooks.codes(self, include_shelved)
	return all if all.size() > 1 else []


func variant_shelved(code: String) -> bool:
	return ItemLooks.shelved(self, code)


func variant_note(code: String) -> String:
	return ItemLooks.note(self, code)


## Its icon and its name in look `code` (its own entry's, else the top level's).
func look_icon(code: String) -> Texture2D:
	return ItemLooks.look_icon(self, code)


func look_name(code: String) -> String:
	return ItemLooks.look_name(self, code)


## Wears look `code` from now on (Registry.apply_item_looks wears the whole family); returns the code worn.
func wear_look(code: String) -> String:
	return ItemLooks.wear(self, code)


## The code of the look it wears now ("" without looks).
func look_code() -> String:
	return ItemLooks.code_worn(self)


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
