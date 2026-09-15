## A playable character: a trait (Effects on the player) plus a favourite weapon with a bonus.
class_name CharacterDef
extends ContentDef

## Effects applied to the player StatSheet at run start.
@export var trait_effects: Array = []
## Weapon id always present in the starter offer.
@export var favourite_weapon: String = ""
## Bonus when the favourite is picked: {"type": "level", "value": 2} or {"type": "effects", "effects": [Effect...]}
@export var favourite_bonus: Dictionary = {}
## Special rules by id: "cannot_stop", "auto_magnet"
@export var specials: Array = []
## Quest id that unlocks this character; empty = unlocked from the start.
@export var unlock_quest: String = ""
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
