## An enemy: an archetype brain, numbers, a sprite strip, drops, and sounds.
class_name EnemyDef
extends ContentDef

## walker | swarmer | spitter | brute | ... | elite (a mini-boss creature) | boss
@export var archetype: String = "walker"
## One line on what it does, for the Collection's creature page and the bible's creature table (the JSON's `doc`).
@export var doc: String = ""
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
## flat damage taken off every hit (a toad's hide); the elite modifiers add to it
## Damage reduction (pass 43, was a flat `armor`): the fraction of every hit it shrugs off, 0..0.9.
@export var damage_reduction: float = 0.0
## never more than this many alive at once (0 = no limit): the director skips the row while the count holds
@export var max_alive: int = 0
## The icon that floats over it (pass 33.3): "crown", "skull", "gear" (art/ui/badges/<badge>.png) or "none"; empty takes
## its role's: a skull over a boss, a crown over an Elite (badge_for). A crown is only ever an Elite's (pass 33.6).
@export var badge: String = ""
## The top of the figure as a fraction of the sprite's height (the badge hangs just above it); tools/measure_heads.py
## measures it from the strip's first frame.
@export var head: float = 0.86
## Out of the game but kept (pass 33.3: the goblins, the mine crab, the jackalope): no map brings it and the collection
## leaves it out; its art, data and brain stay for later.
@export var retired: bool = false
## Art variants (pass 34): code -> {sprite, sprite_file, anims, fps, strip_cols, head, note}, every strip the arena can
## spawn this creature with so they can be compared in play ("GOB-A".."GOB-D"). `variant` is the code the game plays;
## its art is the def's own. A copy made by variant_def() carries `variant_code`, and EnemyManager keeps a type per code.
@export var variants: Dictionary = {}
@export var variant: String = ""
var variant_code := ""
## Whether an elite modifier may be put on it (pass 33.4: a crowned spit cactus showed up; a planted cactus and the
## one-at-a-time specials are never Elites).
@export var can_be_elite: bool = true
## false keeps the Gravity Gun's hands off it (pass 35: the specials); bosses and Elites are never grabbed anyway
@export var can_be_grabbed: bool = true
## How much of the director's live cap one of these takes (pass 33.2: the goblins and fire ants come twice as many at
## half the HP each, and count half, so the rest of the roster keeps its room).
@export var cap_share: float = 1.0
## the ambush brain: {trigger, rehide_distance, rehide_after}; the lunge itself is the `charge` block
@export var ambush: Dictionary = {}
## the support brain: {keep_distance, range, interval, radius, heal, frenzy, frenzy_seconds}
@export var support: Dictionary = {}
## the body bursts after death: {delay, radius, damage} (the toad)
@export var death_burst: Dictionary = {}
## the caster brain: {keep_distance, range}; its tricks are the `boss.attacks` list, run like a boss's
@export var caster: Dictionary = {}
## a walking bomb (the mine crab): {radius, damage, knockback, windup, trigger} -- it goes off at the hero's feet
@export var kamikaze: Dictionary = {}
## the artillery brain (the rocketeer): {stand_off, windup, missile {speed, turn, damage, area}}
@export var artillery: Dictionary = {}
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


## The EnemyManager's key for this def's type: its id, or id@code for another art variant than the game's.
func type_key() -> String:
	return id if variant_code == "" or variant_code == variant else id + "@" + variant_code


## Takes one variant's art (a `variants` entry) as its own.
func apply_art(a: Dictionary) -> void:
	sprite = a.get("sprite", sprite)
	sprite_file = str(a.get("sprite_file", sprite_file))
	anims = a.get("anims", anims)
	fps = a.get("fps", fps)
	strip_cols = int(a.get("strip_cols", strip_cols))
	head = float(a.get("head", head))
	if a.get("icon") != null:
		icon = a["icon"]


## This creature with another art variant (a copy; itself for its own code or an unknown one).
func variant_def(code: String) -> EnemyDef:
	if code == "" or code == variant or not variants.has(code):
		return self
	var v: EnemyDef = duplicate()
	v.variant_code = code
	v.apply_art(variants[code])
	return v


## The variant codes in order (empty when it has one art).
func variant_codes() -> Array:
	var out: Array = variants.keys()
	out.sort()
	return out if out.size() > 1 else []


func frames_of(anim: String) -> int:
	return int(anims.get(anim, 1))


## The badge shown over one of these: its own, else its role's. "" for none. The crown belongs to the two Elites (the
## Dune Scorpion, the Sun Prophet) and nobody else: not a creature with an elite modifier, not a special variant, not a
## JSON asking for one (pass 33.6: crowns showed up over ordinary creatures wearing a modifier).
func badge_for() -> String:
	var b := badge
	if b == "":
		b = "skull" if archetype == "boss" else ("crown" if archetype == "elite" else "")
	if b == "none" or (b == "crown" and archetype != "elite"):
		return ""
	return b


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
