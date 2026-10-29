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
## add run_s/idle_s, run_bd/idle_bd, run_fd/idle_fd, side and diagonals facing screen-right, mirrored for the other half;
## pass 111: idle_l/run_l/attack_l/hit_l/run_bl/idle_bl, the left-heading sets, frame_offset)
@export var anims: Dictionary = {"idle": 2, "run": 2, "attack": 2, "hit": 1, "die": 1}
## Pass 101 (lane LOOKS): the strip is kept as a path (`sprite_path`, the res:// path JsonContent resolved; "" = no
## strip) and `sprite` loads it the first time something asks (LookArt: boot loads no strip; a run pins its own set,
## RunLooks). Setting a texture holds that one; setting null clears the path too (no strip). An old .tres that still
## names the texture sets it here and plays as before.
var sprite: Texture2D:
	get:
		return _sprite if _sprite != null else LookArt.tex(sprite_path)
	set(value):
		_sprite = value
		sprite_path = value.resource_path if value != null else ""
var _sprite: Texture2D = null
@export var sprite_path: String = ""
@export var sprite_file: String = ""
## Frame size in pixels of the sprite strip.
@export var frame_px: int = 128
## Frames per row when the strip is a grid (0 = one row). Written by tools/gen_art.py.
@export var strip_cols: int = 0
## Frames per second per animation prefix, e.g. {"run": 15}.
@export var fps: Dictionary = {}
## Seconds between two bites on the hero (pass 53, the wave schema's `contact_cd`; EnemyManager read a literal 0.6).
@export var contact_cd: float = 0.6
## Pass 53 (the wave schema): this creature's kills roll the timeline's power-up chance (`pickups.per_kill`) times this,
## and a non-empty `pickup_weights` {id: weight} replaces the timeline's power-up roster for its kills (an id missing from
## it is never dropped by this creature). Both may come from a roster row's `stats` (with_overrides).
@export var pickup_chance_mult: float = 1.0
@export var pickup_weights: Dictionary = {}
## Ranged enemies: {"range": 7.0, "keep_distance": 5.0, "cooldown": 2.5, "projectile_speed": 6.0, "telegraph": 0.6}
@export var ranged: Dictionary = {}
## Chargers: {"windup": 0.8, "speed": 9.0, "duration": 0.6, "cooldown": 4.0, "trigger_range": 6.0}
@export var charge: Dictionary = {}
## flat damage taken off every hit (a toad's hide); the elite modifiers add to it
## Damage reduction (pass 43, was a flat `armor`): the fraction of every hit it shrugs off, 0..0.9.
@export var damage_reduction: float = 0.0
## The shove the hero takes from this creature's bite, m/s (pass 54, Garry: every creature its own number, set from
## its damage, melee about 35% over the old fixed 2.5; the Level Editor edits it per row as `stats.knockback`). 0 =
## default_knockback(damage); hit_knockback() is what EnemyManager's bite loop reads. A hostile shot shoves by its
## `ranged.knockback` when the block has one, else 0.7 of this; `charge.knockback`, `kamikaze.knockback`,
## `artillery.missile.knockback` and the boss attacks keep their own numbers (the dwarf's shotgun, the rocketeer's rocket).
@export var knockback: float = 0.0
## The share of every shove from the hero's side this creature shrugs off, 0..1 (pass 67, Garry: the Hammer Giant
## "should take 1/3 of the knockback it currently does"; 0.67 on it). A hit's kb_force, a blast's throw_radius (hostile
## throws too), the pull (Lasso, Wide Orbit) and Buck's Ram are multiplied by (1 - knockback_resist) on top of the mass
## rule (kb_force / max(size, 0.8)) and the boss's own 0.15 (a boss keeps 0 here). 1 = never moved. NOT the shove it
## deals the hero: that is `knockback` above. A roster row may set `stats.knockback_resist`; EnemyManager reads it per type.
@export var knockback_resist: float = 0.0
## never more than this many alive at once (0 = no limit): the director skips the row while the count holds
@export var max_alive: int = 0
## The icon that floats over it (pass 33.3): "crown", "skull", "gear" (art/ui/badges/<badge>.png) or "none"; empty takes
## its role's: a skull over a boss, a crown over an Elite (badge_for). A crown is only ever an Elite's (pass 33.6).
@export var badge: String = ""
## The top of the figure as a fraction of the sprite's height (the badge hangs just above it); tools/measure_heads.py
## measures it from the strip's first frame.
@export var head: float = 0.86
## The blob shadow under it, tuned by eye (pass 47, Garry: the Dune Scorpion "looks like it's floating over" its
## shadow): {"scale": [w, d] times the usual ellipse's width and depth (one number scales both), "up": metres up the
## screen (the camera's forward on the ground, at the creature's own size) to slide the shadow under the body, "drop": a
## share of the cell height to sink the painting by, so legs painted above the cell's bottom edge stand on the ground}.
## A low, wide creature seen from above has its body up the screen from its foot point, and its frames carry empty cell
## under the legs (the scorpion: 13 to 28 px of 224), so the shadow showed below it. A `variants` entry may carry its own
## (apply_art); empty = the plain shadow at the foot point. EnemyManager reads it through shadow_tuning().
@export var shadow: Dictionary = {}
## The colour of the splash it leaves when it dies (pass 58, Garry: "a red splash VFX ... The colour of the poor is
## different for different enemies (it's supposed to be blood kind of ...)"): the JSON's `blood` ("#rrggbb"), red when
## it has none. The Level Editor's Creatures tab sets it.
@export var blood: Color = Color(0.78, 0.05, 0.05)
## Which way the front painting's three-quarter turns (pass 45): "right" (the default: shown as painted while the
## creature heads screen-right, mirrored while it heads left, like every side set), "left" (painted heading screen-left,
## so the mirror is inverted) or "straight" (never mirrored). The hellhound's front cycle came out running down and to
## the viewer's left, so under the default it looked away from the hero on both halves of the screen. `back_faces` is
## the same rule for run_b / idle_b.
@export var front_faces: String = "right"
@export var back_faces: String = "right"
## Out of the game but kept (pass 33.3: the goblins, the mine crab, the jackalope): no map brings it and the collection
## leaves it out; its art, data and brain stay for later.
@export var retired: bool = false
## Art variants (pass 34): code -> {sprite, sprite_file, anims, fps, strip_cols, head, note}, every strip the arena can
## spawn this creature with so they can be compared in play ("GOB-A".."GOB-D"). `variant` is the code the game plays;
## its art is the def's own. A copy made by variant_def() carries `variant_code`, and EnemyManager keeps a type per code.
@export var variants: Dictionary = {}
@export var variant: String = ""
var variant_code := ""
## Pass 53 (the wave schema's `stats`): a copy made by with_overrides() carries the first 8 hex chars of the md5 of its
## stats' canonical JSON here, so equal overrides share one EnemyManager type (type_key = id[@variant][#key]), and the
## stats themselves in `override_stats` (a split child spawns with its parent's). Empty on a creature as its JSON made it.
var override_key := ""
var override_stats: Dictionary = {}
## Pass 54 (a roster row's `stats`, set by with_overrides): this row's weight when a random Elite candidate is drawn
## for an `elite` / `elite_every` event that names no creature (0 = never, like can_be_elite false), and how its
## elite-modified creature arrives, {single, pack, ring} chances (normalised; empty = single). Plain vars: they belong
## to the row, never to a creature's JSON.
var elite_weight := 1.0
var elite_formats: Dictionary = {}
## Pass 58 (a row's `stats.size` as [min, max], Garry: "editable as a kind of a range (between 3-5 for example)"): every
## creature of the row rolls its own size in `size_range` (x = min, y = max; ZERO = no range, `size` as it is) instead of
## the variance's size jitter. A range copy keeps `size` at the painting's JSON size, so the per-type numbers measured on
## the painting (the shadow's slide, the rocket's muzzle) stay right, and remembers it in `size_ref`: the radius follows
## the rolled size (radius x rolled / size_ref) unless the row sets `stats.radius` (`radius_follows` false). Row fields
## like the two above, set by with_overrides.
var size_range := Vector2.ZERO
var size_ref := 0.0
var radius_follows := false
## Pass 58 (a row's `stats.tint`, Garry: "a version that kind of colours all the enemies that come out of that wave"):
## {h0, h1, sat, val, amount} as tint_range_of() reads it, {} for none. Every creature of the row rolls a hue in
## h0..h1 (degrees, through red when h1 < h0, roll_hue) and is tinted Color.from_hsv(h / 360, sat, val) at strength
## `amount` through EnemyManager.vtint, in place of the variance palette's tint.
var tint_range: Dictionary = {}
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
## Pass 73 (lane SNIPER): the sniper brain (the Saiga Sniper): {stand_off, flee_range, follow, first, aim, lock, interval,
## interval_jitter, recover, cone_deg, lines, beam {length, width, seconds, damage_from, damage_mult, damage, knockback,
## creature_frac, creature_max, push, sparks}, muzzle {up, side, forward}} (EnemyManager._sniper_*). Pass 81: flee_range
## defaults to 0 (never runs), `spoil_on_hit` (default true) drops its aim on a hit (EnemyManager.sniper_spoil_on_hit)
@export var sniper: Dictionary = {}
## Pass 112 (lane MONK): the squad brain (the Monk): {sizes, weights, spacing, keep_distance, range, band_from, cooldown,
## first, rise, release, hold, breath_fps, gain, catch_up, leash, hands {up, from_up, side, forward}, orb {speed, range,
## size, hit_radius, damage_mult, lead, hover, knockback, color, pulse_hz, pulse, trail {every, life, size, alpha}}, glow
## {from}}; every key optional (SQUAD_DEFAULTS). Creatures spawned together are one squad: one movement decision, one
## attack clock (core/systems/Squads.gd), their spheres flown by core/systems/EnergyOrbs.gd. {} = none.
@export var squad: Dictionary = {}
## Pass 73 (lane SNIPER): flee on hit, for any creature: {seconds, speed_mult, interrupts}. A hit that lands stops its
## wind-up or aim (`interrupts`) and it runs straight away from the hero at its speed x `speed_mult` for `seconds`
## (EnemyManager.flee_start). {} = none.
@export var flee_on_hit: Dictionary = {}
## Pass 73: "front_back" = the `attack` strip's first half is painted from the front and its second half from the back
## (the Saiga Sniper's aiming pose; EnemyManager._attack_view_frame); "" = every attack frame faces the camera.
@export var attack_views: String = ""
## Pass 85 (lane BANDIT): true = each view's half of the `attack` strip is a throw: its first half the wind-up (shown
## while the creature winds up) and its second half the release (shown while it holds the throw, ranged.release_hold;
## EnemyManager._throw_frame). A look entry may carry its own `attack_views` / `attack_throw` (apply_art).
@export var attack_throw: bool = false
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


## The EnemyManager's key for this def's type: its id, id@code for another art variant than the game's, and #key on the
## end for a copy with stat overrides (pass 53): "skeleton", "skeleton@SK-B", "skeleton@SK-B#1a2b3c4d".
func type_key() -> String:
	var k := id if variant_code == "" or variant_code == variant else id + "@" + variant_code
	return k if override_key == "" else k + "#" + override_key


## A look entry's strip as this def's own (pass 101): a res:// path (what JsonContent writes since pass 101, loaded
## on the first ask), a texture (an old .tres, a test's or a tool's stand-in entry), or nothing (keeps its own).
func take_strip(s) -> void:
	if s is Texture2D:
		_sprite = s
		sprite_path = (s as Texture2D).resource_path
	elif s is String and str(s) != "":
		_sprite = null
		sprite_path = str(s)


## The res:// path of the strip this def draws ("" when it has none), without loading it.
func strip_path() -> String:
	return _sprite.resource_path if _sprite != null else sprite_path


## The res:// path of the strip look `code` draws (pass 101; the def's own for "", its own code or an unknown one, as
## variant_def falls back), without loading it or making a copy.
func look_strip_path(code: String) -> String:
	if code == "" or code == variant or not variants.has(code):
		return strip_path()
	var s = (variants[code] as Dictionary).get("sprite") if variants[code] is Dictionary else null
	if s is Texture2D:
		return (s as Texture2D).resource_path
	return str(s) if s is String and str(s) != "" else strip_path()


## Takes one variant's art (a `variants` entry) as its own, and its facing when the entry gives one (pass 46: a
## variant's painting may turn the other way from the top-level strip's).
func apply_art(a: Dictionary) -> void:
	take_strip(a.get("sprite"))
	sprite_file = str(a.get("sprite_file", sprite_file))
	anims = a.get("anims", anims)
	fps = a.get("fps", fps)
	strip_cols = int(a.get("strip_cols", strip_cols))
	head = float(a.get("head", head))
	# pass 101 (lane LOOKS): the entry's icon is its path (LookArt.icon loads it), or a texture
	var ic := LookArt.icon(a.get("icon"))
	if ic != null:
		icon = ic
	if a.has("front_faces"):
		front_faces = str(a["front_faces"])
	if a.has("back_faces"):
		back_faces = str(a["back_faces"])
	if a.get("shadow") is Dictionary:
		shadow = a["shadow"]
	apply_attack_layout(a)


## Pass 85 (lane BANDIT): a look's attack strip layout (`attack_views`, `attack_throw`) when its entry names one.
func apply_attack_layout(a: Dictionary) -> void:
	if a.has("attack_views"):
		attack_views = str(a["attack_views"])
	if a.has("attack_throw"):
		attack_throw = bool(a["attack_throw"])


## This creature with another art variant (a copy; itself for its own code or an unknown one).
func variant_def(code: String) -> EnemyDef:
	if code == "" or code == variant or not variants.has(code):
		return self
	var v: EnemyDef = duplicate()
	v.variant_code = code
	v.source_dir = source_dir
	# its own shadow, not the one the def it was copied from plays (the variant entry's: JsonContent puts the creature's
	# own block in an entry that has none)
	v.shadow = {}
	v.apply_art(variants[code])
	return v


## The wave schema's stat overrides that set one field as they are (pass 53): JSON key -> field. `pack` is the pack
## size. The `*_mult` keys, the blocks and the three clock/speed/knockback multipliers are handled in with_overrides.
const OVERRIDE_FIELDS := {"hp": "hp", "damage": "damage", "speed": "speed", "size": "size", "radius": "radius",
	"damage_reduction": "damage_reduction", "contact_cd": "contact_cd", "pack": "pack_size", "max_alive": "max_alive",
	"cap_share": "cap_share", "xp_mult": "xp_mult", "can_be_elite": "can_be_elite", "pickup_chance_mult": "pickup_chance_mult",
	"knockback": "knockback", "knockback_resist": "knockback_resist"}
## The `*_mult` overrides and the base field each multiplies (after a direct value for that field).
const OVERRIDE_MULTS := {"hp_mult": "hp", "damage_mult": "damage", "speed_mult": "speed", "size_mult": "size", "radius_mult": "radius"}


## This creature with the wave schema's `stats` overrides on it (pass 53; a roster row's, a wave alt's or an event's
## `stats`, the Level Editor's "Stat overrides"): a copy, its art variant kept like variant_def's, whose type_key ends in
## "#" + the stats' hash so EnemyManager keeps one type per distinct set (Registry.enemy_with caches them). Itself for
## empty stats. Every key is optional and a missing one keeps the creature's own number: the direct fields
## (OVERRIDE_FIELDS), then the `*_mult` keys on the base; `pickup_weights` replaces; ranged / charge / drops / elite /
## kamikaze / artillery / boss deep-merge over the creature's blocks, `boss.attacks` as a name -> on/off map (false
## removes that attack, true keeps it, an unknown name adds nothing; a list replaces the attacks); `attack_rate_mult`
## divides ranged.cooldown, charge.cooldown, kamikaze.windup, boss.cooldown_between and contact_cd (the code's defaults
## when a block has no such key); `projectile_speed_mult` multiplies ranged.projectile_speed (or `speed`),
## artillery.missile.speed and the `speed` of every boss attack that has one; `knockback_mult` multiplies the knockback
## of charge, ranged and kamikaze and of every boss attack, where one is written, and (pass 54) the contact knockback,
## which the copy then carries resolved (hit_knockback() of the base times the multiplier). Pass 54 too: `knockback`
## sets the contact knockback, `variance` deep-merges over the creature's variance block (its `tints` replaced whole
## when given), `elite_weight` and `elite_formats` land on the copy's row fields. Pass 58: `size` may be [min, max] (the
## copy's size_range, `size_mult` scaling both ends; its `size` stays the JSON size) and `tint` a colour range
## (tint_range); EnemyManager.spawn rolls both per creature, so a range never makes one type per rolled value.
func with_overrides(stats: Dictionary) -> EnemyDef:
	if stats.is_empty():
		return self
	var v: EnemyDef = duplicate()
	v.variant_code = variant_code
	v.source_dir = source_dir
	v.override_key = override_key_of(stats)
	v.override_stats = stats.duplicate(true)
	# the row fields (pass 54): a duplicate() need not carry a plain var, so they are set here
	v.elite_weight = maxf(float(stats.get("elite_weight", elite_weight)), 0.0)
	v.elite_formats = (stats["elite_formats"] as Dictionary).duplicate(true) if stats.get("elite_formats") is Dictionary else elite_formats.duplicate(true)
	if stats.get("variance") is Dictionary:
		v.variance = deep_merge(variance, stats["variance"])
	# the blocks the overrides may touch, as deep copies: a Resource's duplicate() leaves the nested dictionaries
	# (boss.attacks, artillery.missile) shared with the original
	v.ranged = ranged.duplicate(true)
	v.charge = charge.duplicate(true)
	v.drops = drops.duplicate(true)
	v.elite = elite.duplicate(true)
	v.boss = boss.duplicate(true)
	v.kamikaze = kamikaze.duplicate(true)
	v.artillery = artillery.duplicate(true)
	# pass 73 (lane SNIPER): the sniper's block and flee on hit, as deep copies too (a row may override them)
	v.sniper = sniper.duplicate(true)
	v.flee_on_hit = flee_on_hit.duplicate(true)
	# pass 112 (lane MONK): the squad's block too (a row may override its sizes, its clock, its sphere)
	v.squad = squad.duplicate(true)
	v.pickup_weights = pickup_weights.duplicate(true)
	# pass 58: `size` may be a range [min, max] (each creature rolls its own; `size_mult` scales both ends), and `tint` a
	# colour range; a plain size goes through the direct fields as before
	var sr := size_range_of(stats.get("size"))
	if sr != Vector2.ZERO:
		var sm := float(stats.get("size_mult", 1.0))
		v.size_range = Vector2(maxf(sr.x * sm, SIZE_MIN), maxf(sr.y * sm, SIZE_MIN))
		v.size_ref = size
		v.radius_follows = not stats.has("radius")
	if stats.get("tint") is Dictionary:
		v.tint_range = tint_range_of(stats["tint"])
	for key: String in OVERRIDE_FIELDS.keys():
		if stats.has(key):
			# a range was read above; a list or a block where a number belongs (a malformed range) is left alone rather
			# than cast (float() of a list is an error)
			if stats[key] is Array or stats[key] is Dictionary:
				continue
			var field: String = str(OVERRIDE_FIELDS[key])
			v.set(field, _typed_like(v.get(field), stats[key]))
	for key: String in OVERRIDE_MULTS.keys():
		if stats.has(key):
			if key == "size_mult" and v.size_range != Vector2.ZERO:
				continue
			var field: String = str(OVERRIDE_MULTS[key])
			v.set(field, float(v.get(field)) * float(stats[key]))
	v.damage_reduction = clampf(v.damage_reduction, 0.0, 0.9)
	# pass 67: a share above 1 would flip the push towards the hero
	v.knockback_resist = clampf(v.knockback_resist, 0.0, 1.0)
	v.pack_size = maxi(v.pack_size, 1)
	if stats.get("pickup_weights") is Dictionary:
		v.pickup_weights = (stats["pickup_weights"] as Dictionary).duplicate(true)
	for block: String in ["ranged", "charge", "drops", "elite", "kamikaze", "artillery", "sniper", "flee_on_hit", "squad"]:
		if stats.get(block) is Dictionary:
			v.set(block, deep_merge(v.get(block), stats[block]))
	if stats.get("boss") is Dictionary:
		var ob: Dictionary = (stats["boss"] as Dictionary).duplicate(true)
		var atk_map = ob.get("attacks")
		ob.erase("attacks")
		v.boss = deep_merge(v.boss, ob)
		if atk_map is Dictionary:
			var kept: Array = []
			for a in v.boss.get("attacks", []):
				if a is Dictionary and bool((atk_map as Dictionary).get(str((a as Dictionary).get("name", "")), true)):
					kept.append(a)
			v.boss["attacks"] = kept
		elif atk_map is Array:
			v.boss["attacks"] = (atk_map as Array).duplicate(true)
	var rate := float(stats.get("attack_rate_mult", 1.0))
	if rate > 0.0 and rate != 1.0:
		v.contact_cd /= rate
		if not v.ranged.is_empty():
			v.ranged["cooldown"] = float(v.ranged.get("cooldown", 2.5)) / rate
		if not v.charge.is_empty():
			v.charge["cooldown"] = float(v.charge.get("cooldown", 4.0)) / rate
		if not v.kamikaze.is_empty():
			v.kamikaze["windup"] = float(v.kamikaze.get("windup", 0.35)) / rate
		if not v.boss.is_empty():
			v.boss["cooldown_between"] = float(v.boss.get("cooldown_between", 2.0)) / rate
		# pass 112 (lane MONK): a squad's volleys come `rate` times as often
		if v.brain == "squad":
			v.squad["cooldown"] = float(v.squad.get("cooldown", SQUAD_DEFAULTS["cooldown"])) / rate
	var psm := float(stats.get("projectile_speed_mult", 1.0))
	if psm > 0.0 and psm != 1.0:
		if v.ranged.has("speed"):
			v.ranged["speed"] = float(v.ranged["speed"]) * psm
		elif not v.ranged.is_empty():
			v.ranged["projectile_speed"] = float(v.ranged.get("projectile_speed", ranged_speed_default(v.ranged))) * psm
		if v.artillery.get("missile") is Dictionary:
			var ms: Dictionary = v.artillery["missile"]
			ms["speed"] = float(ms.get("speed", 4.0)) * psm
		for a in v.boss.get("attacks", []):
			if a is Dictionary and (a as Dictionary).has("speed"):
				a["speed"] = float(a["speed"]) * psm
		# pass 112 (lane MONK): a squad's spheres fly `psm` times as fast (their range unchanged)
		if v.brain == "squad":
			var ob: Dictionary = (v.squad.get("orb", {}) as Dictionary).duplicate(true) if v.squad.get("orb") is Dictionary else {}
			ob["speed"] = float(ob.get("speed", SQUAD_DEFAULTS["orb"]["speed"])) * psm
			v.squad["orb"] = ob
	var kbm := float(stats.get("knockback_mult", 1.0))
	if kbm >= 0.0 and kbm != 1.0:
		for block: String in ["charge", "ranged", "kamikaze"]:
			var b: Dictionary = v.get(block)
			if b.has("knockback"):
				b["knockback"] = float(b["knockback"]) * kbm
		for a in v.boss.get("attacks", []):
			if a is Dictionary and (a as Dictionary).has("knockback"):
				a["knockback"] = float(a["knockback"]) * kbm
		# the contact knockback too (pass 54), resolved from the default when the creature names none (a multiplier of 0
		# leaves a hair over 0: a knockback of 0 means "the default")
		v.knockback = maxf(v.hit_knockback() * kbm, 0.001)
	return v


## The contact knockback a bite deals when the creature's data names none (pass 54): from its damage, 3.4 m/s for a
## 4-damage bite (about 35% over the old fixed 2.5), growing with the square root of the damage, never under 2.5 or
## over 7 (a 3-damage skeleton 2.94, a 14-damage mummy 6.36, a boss 7).
static func default_knockback(bite: float) -> float:
	return clampf(3.4 * sqrt(maxf(bite, 0.0) / 4.0), 2.5, 7.0)


## The shove the hero takes from this creature's bite, m/s (pass 54): its own `knockback`, else the default from its
## damage. EnemyManager's bite loop reads it; a hostile shot without a `ranged.knockback` shoves by 0.7 of it.
func hit_knockback() -> float:
	return knockback if knockback > 0.0 else default_knockback(damage)


## The smallest size a range may roll (pass 58): a range end under it is lifted to it.
const SIZE_MIN := 0.05
## The colour range's defaults (pass 58, docs/waves_schema.md): saturation, value and strength when the row names none.
const TINT_SAT := 0.85
const TINT_VAL := 1.0
const TINT_AMOUNT := 0.5


## A row's `stats.size` as a range (pass 58): [min, max] as Vector2(min, max) (two numbers in either order; a list of one
## number is that number for both ends), Vector2.ZERO for a plain number, a missing key or anything unreadable (the plain
## size path takes a number as it always did).
static func size_range_of(v) -> Vector2:
	if not (v is Array) or (v as Array).is_empty():
		return Vector2.ZERO
	var a: Array = v
	var nums: Array = []
	for e in a:
		if e is float or e is int:
			nums.append(float(e))
	if nums.size() != a.size() or nums.size() > 2:
		return Vector2.ZERO
	var lo: float = nums[0]
	var hi: float = nums[nums.size() - 1]
	return Vector2(maxf(minf(lo, hi), SIZE_MIN), maxf(maxf(lo, hi), SIZE_MIN))


## A row's `stats.tint` read (pass 58): {"hue": [h0, h1] (degrees 0..360; one number = that hue), "sat", "val", "amount"
## (0..1; defaults TINT_SAT, TINT_VAL, TINT_AMOUNT)} -> {h0, h1, sat, val, amount}, everything clamped; {} without a
## readable hue.
static func tint_range_of(d: Dictionary) -> Dictionary:
	var hv = d.get("hue")
	var hs: Array = []
	if hv is float or hv is int:
		hs = [float(hv), float(hv)]
	elif hv is Array:
		for e in hv:
			if e is float or e is int:
				hs.append(float(e))
		if hs.size() == 1:
			hs.append(hs[0])
	if hs.size() != 2:
		return {}
	return {"h0": clampf(float(hs[0]), 0.0, 360.0), "h1": clampf(float(hs[1]), 0.0, 360.0),
		"sat": clampf(float(d.get("sat", TINT_SAT)), 0.0, 1.0), "val": clampf(float(d.get("val", TINT_VAL)), 0.0, 1.0),
		"amount": clampf(float(d.get("amount", TINT_AMOUNT)), 0.0, 1.0)}


## The hue (degrees, 0 <= h < 360) at `u` (0..1) of the way from h0 to h1 going up the colour wheel (pass 58): when h1 is
## below h0 the range runs on through red (350 -> 10 is twenty degrees round red, not 340 the other way).
static func roll_hue(h0: float, h1: float, u: float) -> float:
	var span := h1 - h0
	if span < 0.0:
		span += 360.0
	return fposmod(h0 + clampf(u, 0.0, 1.0) * span, 360.0)


## The tint a creature of a colour-range row is drawn with (pass 58): the hue rolled at `u`, the range's saturation and
## value, and its strength as the alpha (the billboard draws mix(rgb, tint, alpha x 0.65)).
static func tint_color(range_: Dictionary, u: float) -> Color:
	var h := roll_hue(float(range_.get("h0", 0.0)), float(range_.get("h1", 0.0)), u)
	var c := Color.from_hsv(h / 360.0, float(range_.get("sat", TINT_SAT)), float(range_.get("val", TINT_VAL)))
	return Color(c.r, c.g, c.b, float(range_.get("amount", TINT_AMOUNT)))


## A colour-range row's variance special (pass 58, the lead: in its own wine tint it "lost the colour" of its wave): the
## hue this creature rolled at `u`, in a darker, stronger shade: saturation + SPECIAL_SAT_ADD (at most 1), value x
## SPECIAL_VAL_MULT, at the row's `amount` or the special's own `tint_strength`, whichever is more, + SPECIAL_STRENGTH_ADD
## (at most 1). Tuned by eye in the arena: the lead's first numbers (value x 0.55 at the plain strength) came out muddy
## olive on green skeletons and maroon, not blue, on red goblins in a blue row (a dark tint brings little hue against a
## painting's own colour); value x 0.7 at 0.15 more strength reads as the row's colour, deeper, on all of them.
const SPECIAL_SAT_ADD := 0.15
const SPECIAL_VAL_MULT := 0.7
const SPECIAL_STRENGTH_ADD := 0.15


static func tint_special_color(range_: Dictionary, u: float, special_strength: float) -> Color:
	var h := roll_hue(float(range_.get("h0", 0.0)), float(range_.get("h1", 0.0)), u)
	var c := Color.from_hsv(h / 360.0, minf(float(range_.get("sat", TINT_SAT)) + SPECIAL_SAT_ADD, 1.0), float(range_.get("val", TINT_VAL)) * SPECIAL_VAL_MULT)
	return Color(c.r, c.g, c.b, minf(maxf(float(range_.get("amount", TINT_AMOUNT)), special_strength) + SPECIAL_STRENGTH_ADD, 1.0))


## Pass 69 (lane EN; Garry: the specials "3 times more rare ... 1.25 times bigger ... HP x10 ... ATK x2", and their
## colouring "possible in the Level Editor"): what a variance special's numbers fall back to, key by key, when neither the
## creature's own `variance.special` nor the map's `timeline_data.special_defaults` names them (they were 1.3 / 1.6 / 1.2
## / 2 / 0.6 in code before). `glow` 0..1 is the emissive rim enemy_billboard.gdshader draws round a special in its
## tint's colour (0 = none), the width and the brightness of the rim.
## Pass 72 (lane SPEC; Garry: "Specials should be more noticeable. They should be bigger ... way more of a chance of
## dropping a box ... higher HP"): size 1.25 -> 1.5, hp 10 -> 15, and `chest_chance` 0.35, the chance its death drops a
## chest (EnemyManager._special_chest_drop).
const SPECIAL_DEFAULTS := {"size": 1.5, "hp": 15.0, "damage": 2.0, "xp": 2.0, "tint_strength": 0.6, "glow": 0.6, "chest_chance": 0.35}
## Pass 72 (lane SPEC; Garry: "There should be a limit to how many of them are there"): at most this many variance
## specials alive at once when the map's `timeline_data.special_defaults.max_alive` names none (0 there = no limit, as a
## creature's own max_alive). A roll past it makes a plain creature; a forced special (a Special swarm) still comes.
const SPECIAL_MAX_ALIVE := 3


## The most variance specials alive at once on a map whose special_defaults are `defaults` (pass 72): the map's
## `max_alive`, else SPECIAL_MAX_ALIVE; 0 or below = no limit (returned as -1).
static func special_max_alive(defaults: Dictionary) -> int:
	var n: int = int(defaults.get("max_alive", SPECIAL_MAX_ALIVE))
	return n if n > 0 else -1


## One number of a variance special: the creature's own `sp[key]`, else the map's `defaults[key]`, else SPECIAL_DEFAULTS.
static func special_value(sp: Dictionary, defaults: Dictionary, key: String) -> float:
	if sp.has(key):
		return float(sp[key])
	if defaults.has(key):
		return float(defaults[key])
	return float(SPECIAL_DEFAULTS.get(key, 1.0))


## The shot speed EnemyManager plays when a `ranged` block names none (pass 53, for projectile_speed_mult): 16 for a
## cone of pellets, 12 for a straight shot, 6 for a lobbed spit (its _do_attack defaults).
static func ranged_speed_default(r: Dictionary) -> float:
	if r.has("cone_deg"):
		return 16.0
	return 12.0 if bool(r.get("straight", false)) else 6.0


## `value` cast to the type `current` has (pass 53): the JSON's 5.0 lands in an int field as 5, its 1 in a bool as true.
static func _typed_like(current, value):
	match typeof(current):
		TYPE_INT:
			return int(value)
		TYPE_FLOAT:
			return float(value)
		TYPE_BOOL:
			return bool(value)
		TYPE_STRING:
			return str(value)
	return value


## `over` laid over `base` (pass 53): a key whose value is a dictionary on both sides merges inside, anything else
## replaces. A new dictionary; neither argument is touched.
static func deep_merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	for k in over.keys():
		if over[k] is Dictionary and out.get(k) is Dictionary:
			out[k] = deep_merge(out[k], over[k])
		elif over[k] is Dictionary or over[k] is Array:
			out[k] = over[k].duplicate(true)
		else:
			out[k] = over[k]
	return out


## The hash two equal override sets share (pass 53): the first 8 hex chars of the md5 of their canonical JSON (keys
## sorted at every level, whole floats written as integers, so the editor's 10 and the .tres's 10.0 are one set).
## JSON.stringify keeps a dictionary's own order, so the canonical text is built here.
static func override_key_of(stats: Dictionary) -> String:
	return canonical_json(stats).md5_text().substr(0, 8)


static func canonical_json(v) -> String:
	if v is Dictionary:
		var d: Dictionary = v
		var by_name: Dictionary = {}
		for k in d.keys():
			by_name[str(k)] = k
		var names: Array = by_name.keys()
		names.sort()
		var parts: PackedStringArray = PackedStringArray()
		for n in names:
			parts.append(JSON.stringify(str(n)) + ":" + canonical_json(d[by_name[n]]))
		return "{" + ",".join(parts) + "}"
	if v is Array:
		var items: PackedStringArray = PackedStringArray()
		for e in v:
			items.append(canonical_json(e))
		return "[" + ",".join(items) + "]"
	if v is float:
		var f: float = v
		if f == floorf(f) and absf(f) < 1e15:
			return str(int(f))
		return JSON.stringify(f)
	return JSON.stringify(v)


## The shadow tuning this def draws with (pass 47): `shadow` as JsonContent loaded it, the variant entry's when the art
## it plays has its own, else the creature's top-level block; empty = the plain shadow at the foot point.
func shadow_tuning() -> Dictionary:
	return shadow


## The variant codes in order (empty when it has one art). A shelved look (`variants[CODE].shelved`, pass 66: the Level
## Editor's shelve, a look kept but out of the way) is left out unless asked for, so the arena chips and the default
## lists skip it; variant_def(code) and Registry.enemy_with still wear it when named (a wave row).
func variant_codes(include_shelved := false) -> Array:
	var out: Array = []
	for code in variants.keys():
		if include_shelved or not variant_shelved(str(code)):
			out.append(code)
	out.sort()
	return out if out.size() > 1 else []


## Whether a look is shelved (pass 66); false for a code it does not have.
func variant_shelved(code: String) -> bool:
	var e = variants.get(code)
	return e is Dictionary and bool((e as Dictionary).get("shelved", false))


func frames_of(anim: String) -> int:
	return int(anims.get(anim, 1))


## The badge shown over one of these: its own, else its role's. "" for none. The crown belongs to the Elites (the
## Dune Scorpion, the Sun Prophet, the Stone Golem since pass 45) and nobody else: not a creature with an elite modifier, not a special variant, not a
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


## Whether this look's strip carries its own left-heading sets (pass 111, lane ENEMY): idle_l or run_l with frames. The
## optional sets (idle_l, run_l, attack_l, hit_l: the front set while it heads screen-left; run_bl, idle_bl: the back set
## heading left) come last in the strip (frame_offset). A look that has them is never mirrored by code: EnemyManager
## shows them while it heads left and the usual sets while it heads right, both as painted (tools/add_left_sets.py).
func has_left_sets() -> bool:
	return int(anims.get("idle_l", 0)) > 0 or int(anims.get("run_l", 0)) > 0


func frame_offset(anim: String) -> int:
	## Frame strips are packed in a fixed order so the shader can index them (pass 111: the left-heading sets last).
	var n := 0
	for k in ["idle", "run", "attack", "hit", "die", "run_b", "idle_b", "run_s", "idle_s", "run_bd", "idle_bd", "run_fd", "idle_fd", "idle_l", "run_l", "attack_l", "hit_l", "run_bl", "idle_bl"]:
		if k == anim:
			return n
		n += int(anims.get(k, 0))
	return 0


# ---------------------------------------------------------------- pass 112 (lane MONK): the squad brain

## Every key of the `squad` block with the game's own numbers (Squads reads the block laid over these, deep_merge):
##   sizes [10, 20, 30] / weights [1, 1, 1]  how many come together (a roster row's `pack` wins), drawn by the weights
##   spacing 1.4      metres between two neighbours of the formation (a hex blob round its centre)
##   keep_distance 5.5 / range 8.0   the kite's band (the Spit Cactus's): backs off nearer than keep - 0.5, walks in past
##                    range, stands and may attack between; measured from the formation's near edge (`band_from` "edge")
##                    or its centre ("center")
##   cooldown 5.2     seconds from one volley's start to the next (half as often as the Spit Cactus's 2.6)
##   first 1.5        seconds after it forms before its first volley may start (+ up to 1 s at random per squad)
##   rise 0.5 / release 1.0 / hold 3.0   seconds into the stop: the hands are up, the spheres leave, it walks again
##                    (plain seconds: the map's pace knob never stretches them; High Noon slows them)
##   breath_fps 2.0   the hands-up frames' breath while they hold
##   gain 2.5, catch_up 1.5, leash 1.2   a member steers to its slot at `gain` x the gap on top of the squad's walk, at
##                    most `catch_up` x its own walk; the centre waits when the members are `leash` m behind it
##   hands {up 1.75, from_up 1.05, side 0, forward 0.2}   where the glow gathers (metres at the def's size, as a muzzle):
##                    rising from `from_up` to `up` while the hands rise
##   orb {...}        the sphere (EnergyOrbs): speed 4 m/s, range 17.5 m (1.25 x the Revolver's 14), size 0.5 m across,
##                    hit_radius 0.22 (+ the hero's 0.5), damage_mult 1 (x the monk's damage, its stage and level),
##                    lead 0 (a share of the hero's run over the flight), hover 1.0 m over the sand, knockback 0 (a plain
##                    shot: no push), color "#2F7BFF", pulse_hz 3, pulse 0.12, trail {every 0.04, life 0.35, size 0.6,
##                    alpha 0.45}
##   glow {from 0.2}  the gathering glow starts at this share of the sphere's size and is full at the release
const SQUAD_DEFAULTS := {
	"sizes": [10, 20, 30], "weights": [1.0, 1.0, 1.0], "spacing": 1.4, "keep_distance": 5.5, "range": 8.0,
	"band_from": "edge", "cooldown": 5.2, "first": 1.5, "rise": 0.5, "release": 1.0, "hold": 3.0, "breath_fps": 2.0,
	"gain": 2.5, "catch_up": 1.5, "leash": 1.2,
	"hands": {"up": 1.75, "from_up": 1.05, "side": 0.0, "forward": 0.2},
	"orb": {"aim": "cloud", "speed": 4.0, "range": 17.5, "size": 0.5, "hit_radius": 0.22, "damage_mult": 1.0, "lead": 0.0, "hover": 1.0,
		"knockback": 0.0, "color": "#2F7BFF", "pulse_hz": 3.0, "pulse": 0.12,
		"trail": {"every": 0.04, "life": 0.35, "size": 0.6, "alpha": 0.45}},
	"glow": {"from": 0.2},
}


## Whether this creature fights as a squad (the squad brain).
func is_squad() -> bool:
	return brain == "squad"


## Its squad block laid over SQUAD_DEFAULTS (a new dictionary).
func squad_cfg() -> Dictionary:
	return deep_merge(SQUAD_DEFAULTS, squad)


## The squad sizes it may come in (whole numbers of at least 1, in the block's order); [pack_size] when the block has none.
func squad_sizes() -> PackedInt32Array:
	var out := PackedInt32Array()
	var s = squad_cfg().get("sizes", [])
	if s is Array:
		for v in s:
			if (v is float or v is int) and int(v) >= 1:
				out.append(int(v))
	if out.is_empty():
		out.append(maxi(pack_size, 1))
	return out


## The largest squad it comes in.
func squad_max() -> int:
	var m := 1
	for v: int in squad_sizes():
		m = maxi(m, v)
	return m


## One squad's size drawn by the block's `weights` (one weight per size; a missing one weighs 1, 0 never comes; all 0 =
## the first size). `u` is a roll in 0..1.
func squad_roll(u: float) -> int:
	var sizes := squad_sizes()
	var w = squad_cfg().get("weights", [])
	var ws := PackedFloat32Array()
	var total := 0.0
	for k in range(sizes.size()):
		var x := 1.0
		if w is Array and k < (w as Array).size() and ((w as Array)[k] is float or (w as Array)[k] is int):
			x = maxf(float((w as Array)[k]), 0.0)
		ws.append(x)
		total += x
	if total <= 0.0:
		return sizes[0]
	var pick := clampf(u, 0.0, 0.999999) * total
	for k in range(sizes.size()):
		pick -= ws[k]
		if pick < 0.0:
			return sizes[k]
	return sizes[sizes.size() - 1]
