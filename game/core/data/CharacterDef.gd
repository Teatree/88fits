## A playable character: a trait (Effects on the player) plus a favourite weapon with a bonus.
class_name CharacterDef
extends ContentDef

## Effects applied to the player StatSheet at run start.
@export var trait_effects: Array = []
## the trait as the player reads it: a name and one line (traits with a mechanic behind them cannot be generated from effects)
@export var trait_name: String = ""
@export var trait_text: String = ""
## "he", "she" or "they": the words the first-play hints use for the hero ("she shoots by herself")
@export var pronoun: String = "they"
## fraction of max HP healed on every level-up (Astro's suit); 0 for none
@export var level_heal: float = 0.0
## The favourite: FAVOURITE on the title plaque, the hero path sits on it, a bonus when it is picked or when he starts with it.
@export var favourite_weapon: String = ""
## Bonus when the favourite is picked: {"type": "level", "value": 2} or {"type": "effects", "effects": [Effect...]}
@export var favourite_bonus: Dictionary = {}
## The weapon in his hand when he lands (pass 45): his own gun (WeaponDef.hero) by default; empty = the favourite, then
## the Peashooter.
@export var start_weapon: String = ""
## A favourite passive or line (pass 46: Ironwood's Cake; pass 47: his Brawn, the attack-damage line, at level 2), empty
## for none, and what finding it gives, the same shape as favourite_bonus: {"type": "max"} (full at once; on a line that
## would be maxed and offering its evolution at the first pick), {"type": "level", "value": 2} or
## {"type": "effects", "effects": [Effect...]}.
@export var favourite_passive: String = ""
@export var favourite_passive_bonus: Dictionary = {}
## Special rules by id: "cannot_stop", "auto_magnet"
@export var specials: Array = []
## Buck's trait: {"ramp_seconds", "speed_bonus", "might_bonus"}; speed and might climb while unhurt and reset on a hit
@export var momentum: Dictionary = {}
## Quest id that unlocks this character; empty = unlocked from the start.
@export var unlock_quest: String = ""
## Kept but not playable (pass 33.4: Buck, Dad and Mira): out of play setup, the collection and the title screen; its
## art, perks and logic stay for later.
@export var sprite: Texture2D
@export var sprite_file: String = ""
@export var frame_px: int = 256
@export var anims: Dictionary = {"idle": 2, "run": 4, "turn": 1, "hit": 1, "die": 1, "cheer": 1}
## Frames per row when the strip is a grid (0 = one row). Written by tools/gen_art.py.
@export var strip_cols: int = 0
## Frames per second per animation prefix, e.g. {"run": 28}; unlisted ones use the sprite player's defaults.
@export var fps: Dictionary = {}
## Art variants (pass 55, the creatures' scheme of pass 34): code -> {sprite, sprite_file, anims, fps, strip_cols, frame_px,
## icon, note}, every strip the hero can be drawn with ("SOL-A".."SOL-D", Solenne's walks). `variant` is the look the game
## plays unless the player kept another (Save.hero_look, the arena's HERO tab); its art is the def's own. Only the art
## differs between them: the id, the trait, the perks and the weapons are the hero's whatever look he wears.
@export var variants: Dictionary = {}
@export var variant: String = ""
## The look a copy made by variant_def() wears ("" on the def itself, which wears `variant`).
var variant_code := ""


func kind() -> String:
	return "character"


## Takes one variant's art (a `variants` entry) as its own.
func apply_art(a: Dictionary) -> void:
	sprite = a.get("sprite", sprite)
	sprite_file = str(a.get("sprite_file", sprite_file))
	anims = a.get("anims", anims)
	fps = a.get("fps", fps)
	strip_cols = int(a.get("strip_cols", strip_cols))
	frame_px = int(a.get("frame_px", frame_px))
	if a.get("icon") != null:
		icon = a["icon"]


## This hero drawn with another look: a copy wearing that variant's strip, everything else his. Itself for the look it
## wears already, for "" and for a code it does not have (a look kept for a strip that has since gone), so a missing
## look falls back to the JSON's.
func variant_def(code: String) -> CharacterDef:
	if code == "" or code == look_code() or not variants.has(code):
		return self
	var v: CharacterDef = duplicate()
	v.variant_code = code
	v.source_dir = source_dir
	v.apply_art(variants[code])
	return v


## The look this def wears: the copy's code, else the JSON's `variant` ("" for a hero with one art).
func look_code() -> String:
	return variant_code if variant_code != "" else variant


## The look codes in order (empty when he has one art).
func variant_codes() -> Array:
	var out: Array = variants.keys()
	out.sort()
	return out if out.size() > 1 else []


## A look's note from the JSON ("" when it has none).
func variant_note(code: String) -> String:
	var e = variants.get(code)
	return str((e as Dictionary).get("note", "")) if e is Dictionary else ""
