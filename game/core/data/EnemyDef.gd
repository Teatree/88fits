## An enemy: an archetype brain, numbers, a sprite strip, drops, and sounds.
class_name EnemyDef
extends ContentDef

## walker | swarmer | spitter | brute | ... | elite (a mini-boss creature) | boss
@export var archetype: String = "walker"
## chase | flock | kite | charge | boss
@export var brain: String = "chase"
@export var hp: float = 10.0
@export var speed: float = 2.5
@export var damage: float = 5.0
## Contact radius in metres (also the separation radius).
@export var radius: float = 0.5
## Sprite height in metres.
@export var size: float = 1.0
## How many spawn together.
@export var pack_size: int = 1
## {"small": 1.0, "medium": 0.0, "large": 0.0} probabilities, plus "gold": chance of a coin.
@export var drops: Dictionary = {"small": 1.0, "gold": 0.02}
## Frames per animation, e.g. {"idle": 4, "run": 6, "attack": 2, "hit": 1, "die": 1, "run_b": 6, "idle_b": 4}
## (run_b / idle_b: the creature seen from behind, used while it walks away from the camera; eight-direction creatures
## add run_s/idle_s, run_bd/idle_bd, run_fd/idle_fd, side and diagonals facing screen-right, mirrored for the other half)
@export var anims: Dictionary = {"idle": 2, "run": 2, "attack": 2, "hit": 1, "die": 1}
@export var sprite: Texture2D
@export var sprite_file: String = ""
## Frame size in pixels of the sprite strip.
@export var frame_px: int = 128
## Frames per row when the strip is a grid (0 = one row). Written by tools/gen_art.py.
@export var strip_cols: int = 0
## Frames per second per animation prefix, e.g. {"run": 15}.
@export var fps: Dictionary = {}
## Ranged enemies: {"range": 7.0, "keep_distance": 5.0, "cooldown": 2.5, "projectile_speed": 6.0, "telegraph": 0.6}
@export var ranged: Dictionary = {}
## Chargers: {"windup": 0.8, "speed": 9.0, "duration": 0.6, "cooldown": 4.0, "trigger_range": 6.0}
@export var charge: Dictionary = {}
## Boss: {"attacks": [ {"name":"roll", ...}, ... ], "hp_mult_per_stage": 1.0 }
@export var boss: Dictionary = {}
## Mini-boss tuning: {"hp_mult_per_stage": 1.8}
@export var elite: Dictionary = {}
## Sound ids: hit, die, attack, spawn
@export var sfx: Dictionary = {}
## XP value multiplier for the drops (elites multiply further).
@export var xp_mult: float = 1.0
## Per-spawn randomness: {"size": 0.12, "speed": 0.1, "tints": ["#hex", ...], "tint_strength": 0.35,
##  "special_chance": 0.08, "special": {"size": 1.35, "hp": 1.8, "damage": 1.3, "xp": 2.5, "tint": "#hex", "tint_strength": 0.6}}
@export var variance: Dictionary = {}


func kind() -> String:
	return "enemy"


func frames_of(anim: String) -> int:
	return int(anims.get(anim, 1))


func total_frames() -> int:
	var n := 0
	for k in anims.keys():
		n += int(anims[k])
	return max(n, 1)


func frame_offset(anim: String) -> int:
	## Frame strips are packed in a fixed order so the shader can index them.
	var n := 0
	for k in ["idle", "run", "attack", "hit", "die", "run_b", "idle_b", "run_s", "idle_s", "run_bd", "idle_bd", "run_fd", "idle_fd"]:
		if k == anim:
			return n
		n += int(anims.get(k, 0))
	return 0
