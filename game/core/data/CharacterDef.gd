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
## Weapon id always present in the starter offer.
@export var favourite_weapon: String = ""
## Bonus when the favourite is picked: {"type": "level", "value": 2} or {"type": "effects", "effects": [Effect...]}
@export var favourite_bonus: Dictionary = {}
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


func kind() -> String:
	return "character"
