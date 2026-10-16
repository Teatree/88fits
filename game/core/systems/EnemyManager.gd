## Every enemy in the arena lives in these packed arrays. One MultiMeshInstance3D per enemy type draws them
## as Y-billboards. Brains are a few lines of steering. No per-enemy nodes.
class_name EnemyManager
extends Node3D

signal enemy_died(def: EnemyDef, pos: Vector3, elite: EliteModDef, weapon_id: String)
signal boss_spawned(def: EnemyDef)
signal boss_died(def: EnemyDef, pos: Vector3)
signal boss_hp_changed(hp: float, max_hp: float)
## A creature is going down (pass 48), emitted in _die once it is STATE_DYING but before its poisons and burns are cleared,
## so a listener reads what it carried (a Moonshine body's splash, a Tarantula Hawk dying with its prey).
signal creature_dying(i: int, weapon_id: String)
## The field was emptied without a fight (pass 48: kill_all(false), the arena's CLEAR): the arena's dummies stay gone.
signal cleared

const MAX := 320
const CELL := 2.5
const STATE_MOVE := 0
const STATE_WINDUP := 1
const STATE_CHARGE := 2
const STATE_DYING := 3
const STATE_ATTACK := 4
const STATE_SPAWN := 5
## Seconds a body stays: the die frames play at the def's die fps, the body holds, then sinks in the last DIE_SINK.
const DIE_TIME := 1.4
const DIE_SINK := 0.3
## A hit's flags (pass 48, damage's `flags`): HIT_MINI is a mini crit (the Tommy Gun's Mini Crits, rolled as the round
## left the gun): half a crit's extra damage, 1 + (crit_damage - 1) / 2, unless a full crit rolled.
const HIT_MINI := 1
## HIT_CRIT (pass 62, Ironwood's Heartseeker: every 4th thrust a guaranteed crit) makes a weapon hit a full crit whatever
## the hero's crit chance, at his crit_damage as any crit (a poison or fire tick never crits).
const HIT_CRIT := 2
## Whether the last hit damage() landed was a full crit (pass 61, lane WP2: the Sabre's Critical Thinking streak and the
## Whirlwind's refund read it right after their own call); false when the hit did not land.
var last_crit := false
## Priority targeting (pass 48, priority_index): a creature weighs its max HP over the crowd's mean, from 1 up to this,
## and big game (a boss, an Elite, an elite-modded creature) weighs this; the smallest distance over weight is taken.
const PRIORITY_CAP := 3.0
## A blue burn's tint (pass 48: a creature Methanol or Moonshine set burning).
const BLUE_BURN := Color(0.25, 0.55, 1.0, 1.0)

var game: Node = null
var player: Node3D = null
var height_fn: Callable = Callable()
var obstacles: Array = []       # Vector3(x, z, radius)
var _splashing := false         # inside an Overkill splash: its kills do not splash again
var hidden := PackedByteArray()   # buried (the ambush brain) or under the sand (a boss burrow): not drawn, not hit, not targeted
var atk_i := PackedInt32Array()        # attack runner (boss and casters): which attack is next
var atk_t := PackedFloat32Array()      # seconds until the next attack
var atk_target := PackedVector3Array() # where a ring_at_hero attack lands
var frenzy_t := PackedFloat32Array()   # seconds of the shaman's drive left (+speed)
var arena_radius := 66.0
var stage_mult := 1.0
## creatures grow with the hero's level (the director sets these from the timeline)
var level_hp_mult := 1.0
var level_dmg_mult := 1.0
var stage_speed_mult := 1.0
var hp_time_mult := 1.0
## Pass 46, set by the director from the timeline. Every creature but a boss is `creature_hp_mult` beefier (1.3 on Red
## Canyon: Garry wanted them to take a little longer to fall). Colour waits for the run's `colour_after_kills`-th kill: no
## variance tint and no special before it, so the opening crowd is a plain one (the elite modifiers wait in the
## director). A touch from anything but a boss takes at most `contact_cap` of the hero's max HP (0 = no cap), so a
## ring of creatures can wear him down but never land a one-shot.
var creature_hp_mult := 1.0
## Pass 71 (the lead): no colour until a director says when (WaveDirector._apply_mults sets it from the timeline, 0 in
## the arena). A crowd built without one (tests, tools) spawns plain: since pass 69 a random special has x10 HP and
## x1.25 size, which made exact tests fail now and then (the Golden Pineapple's ride, Birdshot's lane).
const COLOUR_NEVER := 1 << 30
var colour_after_kills := COLOUR_NEVER
var contact_cap := 0.0
## Pass 54 (Garry: the creatures hit 25% harder), set by the director from the timeline through set() (lane WD): every
## hostile damage, a bite, a shot, a blast, a boss's or a caster's attack, is `creature_damage_mult` times its number
## (1.25 on Red Canyon, 1 in the arena) and `damage_time_mult` times, the timeline's damage curve now (1 without one).
## hostile_mult() is the two together; the Brander's ring of fire (Game._tick_hell) reads them too.
var creature_damage_mult := 1.0
var damage_time_mult := 1.0
## Pass 54 (Garry: "ranged weapons target only what is on screen", with a metre to spare): 1 for a creature on the screen
## or within SCREEN_MARGIN_M of its edge, refreshed for half the crowd every tick (refresh_onscreen), 1 for a fresh spawn
## and everywhere without a camera (tools, tests). nearest_index, priority_index, random_in_range and densest_point (and
## WeaponBehavior.crowd_spots) skip the 0s unless the caller asks for `any_screen` (the homing weapons, a pick close to a
## spot already chosen, a trigger) or Settings.ranged_on_screen is off; `screen_filter_on` is a switch a tool may clear.
var onscreen := PackedByteArray()
var screen_filter_on := true
const SCREEN_MARGIN_M := 1.0
## The shove a boss's, an Elite's or an elite-modded creature's bite gives the hero is this many times its number (pass 54).
const BIG_KNOCK := 1.6
## The blob shadows draw before the gems and coins among the see-through things (pass 54), so a gem at a creature's feet
## is not darkened by its shadow: one under PickupManager.PICKUP_PRIORITY. The hero's shadow (Player) takes it too.
const SHADOW_PRIORITY := -3
## Pass 47, the hero's sheet as this manager reads it: refreshed once a tick and whenever the build changes
## (Run.build_changed), never per creature. Ducktape's `debuff_duration` stretches every debuff put on a creature here
## (a burn, poison, a slow or a pin, Cauterize's mark, and since pass 70 a freeze and a stun; never a knockback, a lift,
## a bounce, a launch or a twister, nor a hero's perk), Big Game Hunter's `elite_damage` is extra damage on a boss, an
## Elite or an elite-modded creature, Hot Sauce's `difficulty` brings more coloured creatures and pays for them, White Phosphorus's `fire_vuln` and Rattle's
## `poison_slow` were read per creature before.
var _debuff_mult := 1.0
## Cold Snap (pass 47c): the chance a weapon hit freezes a creature for FREEZE_SECONDS, and Vulture's chance a crit heals
var _freeze_chance := 0.0
var _crit_heal := 0.0
const FREEZE_SECONDS := 1.0
## Vulture: a healing crit gives back this share of the hero's max HP
const CRIT_HEAL_FRAC := 0.02
## seconds a creature stays frozen (blue, still, harmless); a separate clock from slow_t so the tint knows
var freeze_t := PackedFloat32Array()
## A stun (pass 53, the Spear lane's `stun`): seconds the creature neither walks nor attacks, no ice, a pale yellow; never a
## boss, an Elite or an elite-modded one. Counted down in _steer like freeze_t.
var stun_t := PackedFloat32Array()
const STUN_TINT := Color(0.95, 0.9, 0.45, 0.75)
var _elite_dmg := 0.0
var _difficulty := 0.0
var _fire_vuln := 0.0
## Solenne's perks (pass 54): Sunburn's extra share on a burning or poisoned creature (0 without it), Lingering Light's
## burn and poison ticks (`_ll_harder` times as hard) and clocks (`_ll_longer` times as long; 1 and 1 without it)
var _sunburn := 0.0
var _ll_harder := 1.0
var _ll_longer := 1.0
var _pstats_dirty := true
## Hot Sauce (pass 47): a coloured creature (a variance special, or one wearing an elite modifier) killed while the hero
## carries `difficulty` drops a gem worth HOT_XP x difficulty of its XP, and a variance special a chest at
## HOT_CHEST_CHANCE x difficulty (an elite-modded one drops a chest anyway), no more than one every HOT_CHEST_GAP seconds
## of play so a run of coloured kills cannot bury the hero in reels.
const HOT_XP := 0.25
const HOT_CHEST_CHANCE := 0.05
const HOT_CHEST_GAP := 40.0
var _hot_chest_cd := 0.0
## Hot Sauce chests dropped this run (tests, the run recorder)
var hot_chests := 0
## The King's volley reaches this far past speed x life (pass 47): Game.tumbleweed_volley starts each tumbleweed 1.2 m
## out from the King, and one hits 0.6 m either side of its line.
const VOLLEY_START := 1.2
const VOLLEY_HIT := 0.6
## The pace of a creature's attack frames while it stands to attack (a wind-up, a scripted attack), whatever shoves it.
const ATTACK_FPS := 3.0
## A charger's carriage (pass 50, charge_pose): how far it rocks on its feet at the end of its wind-up (radians) and how
## high it bounces at each step of its charge (a share of its size).
const ROCK := 0.05
const BOUNCE := 0.035

# per-enemy data
var pos := PackedVector3Array()
var vel := PackedVector3Array()
var kb := PackedVector3Array()
var hp := PackedFloat32Array()
var max_hp := PackedFloat32Array()
var speed := PackedFloat32Array()
var dmg := PackedFloat32Array()
var radius := PackedFloat32Array()
var size := PackedFloat32Array()
var dr := PackedFloat32Array()      # damage reduction: the share of every hit it shrugs off
var type_idx := PackedInt32Array()
var elite_idx := PackedInt32Array()
var state := PackedInt32Array()
var timer := PackedFloat32Array()
var cooldown := PackedFloat32Array()
var anim_t := PackedFloat32Array()
var flash := PackedFloat32Array()
var squash := PackedFloat32Array()
var flip := PackedByteArray()
var contact_cd := PackedFloat32Array()
var alive := PackedByteArray()
var charge_dir := PackedVector3Array()
var xp_scale := PackedFloat32Array()
## The dying creature's whole XP scale while enemy_died is out (pass 47): its type's xp_mult, ×4 for an elite variant
## and its variance special's own `xp` (Game had paid the first two only, so the dark specials never paid more).
var died_xp_scale := 0.0
var vtint := PackedColorArray()   # per-spawn tint (rgb) and strength (a) from the def's variance block
var vspecial := PackedByteArray()  # 1 = rolled its variance special (the dark, big one): the hit log names its colour
## Pass 69 (lane EN): a variance special's glow, 0..1 (EnemyDef.special_value "glow"): the emissive rim
## enemy_billboard.gdshader draws round it in its tint's colour; 0 for everyone else. `special_defaults` is the map's
## timeline_data.special_defaults (the director sets it): a special's numbers the creature's own block does not name.
## `force_special`, held true by the director around a spawn (a swarm event with "special": true), makes that spawn its
## variance special whatever its chance and before colour_after_kills.
var vglow := PackedFloat32Array()
var special_defaults: Dictionary = {}
var force_special := false
## Pass 72 (lane SPEC): the variance specials alive now (vspecial 1 and not dying), kept by spawn, _die and _free; a roll
## that would pass EnemyDef.special_max_alive(special_defaults) comes plain (_special_room).
var specials_alive := 0
## Pass 58 (R1, Garry: "I don't actually want it to change for the same 'wave' of enemies on the fly, because then it feels
## weird for the Player that shooting the same enemy with the same weapon suddenly doesn't kill it"): a creature a spawn
## source brought (a roster row, a wave, an event; WaveDirector hands spawn() the source's `src`) carries its numbers
## fixed from that source: `fixed` 1, the stage multiplier at its spawn (`f_stage`), the source's HP and damage time
## factors (`f_hpt`, `f_dmt`: the curves at the source's start, 1 for an overridden number) and hero-level factors
## (`f_lvh`, `f_lvd`: the hero's level at the source's first spawn). Every hit it deals later reads these (stage_of, lvd_of,
## host_of) instead of the live values. `fixed` 0 (spawned by hand, a test, the arena; a boss or an Elite by its kind)
## plays the live numbers as before.
var fixed := PackedByteArray()
var f_stage := PackedFloat32Array()
var f_hpt := PackedFloat32Array()
var f_lvh := PackedFloat32Array()
var f_dmt := PackedFloat32Array()
var f_lvd := PackedFloat32Array()
## The fix round of pass 58 (the review: a split child re-rolled its row's size and hue and took the live stage): the size
## this creature rolled in its row's range, before any scale (`f_bsz`, 0 for none), and the share `u` its row's colour
## range rolled (`f_tu`, -1 for none). src_of hands both to a split child, with the stage at the parent's spawn.
var f_bsz := PackedFloat32Array()
var f_tu := PackedFloat32Array()
var away := PackedByteArray()      # 1 while walking away from the camera (back-view frames)
var view := PackedByteArray()      # eight-direction creatures: 0 front, 1 back, 2 side, 3 back-diagonal, 4 front-diagonal
## Each view's span of the heading angle (0 = away from the camera, PI = towards it), the hysteresis past a boundary
## before a creature changes view, and the dead band about the vertical before its picture mirrors (pass 43).
const VIEW_LO := [PI * 0.875, 0.0, PI * 0.375, PI * 0.125, PI * 0.625]
const VIEW_HI := [PI, PI * 0.125, PI * 0.625, PI * 0.375, PI * 0.875]
const VIEW_HYST := PI * 0.07
const FLIP_BAND := 0.2
## Poison: per enemy a dictionary of sources, weapon id -> {"stacks", "dmg", "t"}. One tick every POISON_TICK seconds
## deals the sum of stacks x dmg over all sources; a source hit again resets its timer instead of stacking.
var poison_src: Array = []
var poison_tick := PackedFloat32Array()
var flash_green := PackedByteArray()
const POISON_TICK := 2.0
## Fire: per enemy a dictionary of sources, weapon id -> {"dmg", "t", "dur", "spread", "root", "from"}. Hotter and shorter than
## poison (a tick every FIRE_TICK seconds), and every tick it can jump to a creature it is touching; a fire caught
## from another creature spreads at CHILD_SPREAD of the host's chance and never back to the creature it came from.
var fire_src: Array = []
var fire_tick := PackedFloat32Array()
var fire_puff := PackedFloat32Array()   # seconds until the next lick of flame (visual only)
var flash_hot := PackedByteArray()
const FIRE_TICK := 0.6
const CHILD_SPREAD := 0.4
var lift_t := PackedFloat32Array() # seconds left in the air (tornado)
## Pass 26 statuses: a slow (fraction, seconds), a mark (damage taken multiplier, seconds), the bees' old twister (seconds and
## where it drags the creature to) and a hold (a caster standing still while its rain falls).
var slow_t := PackedFloat32Array()
## the creature holding the hero on a rope (Game sets it): it stands where it threw from and never walks; its outline
## pulses red (the glow level rides on the flip channel, enemy_billboard.gdshader), and while the hero drags it (pass
## 33.10) it shows its wind-up frames for `tether_drag_t` seconds after each pull
var tethered_i := -1
var tether_drag_t := 0.0
## High Noon (the Drifter's perk, pass 34): every creature runs on this fraction of the clock while it lasts
var time_scale := 1.0
## Bounty Hunter (the Drifter's perk, pass 34): the creature wearing the bounty glows warm
var bounty_i := -1
# in a Gravity Gun's grip (pass 35): the gun moves it (pos on the ground under it, lift_h above), nothing hits it, it
# neither steers nor bites, and it is out of the grid; `release` hands it back to the crowd
var held := PackedByteArray()
var _glow_clock := 0.0
## a walking bomb that already went off: its death burst is not fired a second time
var blown := PackedByteArray()
## Rattle's slow, read once a frame in _physics_process instead of per creature
var _poison_slow := 0.0
## how many shadows a crowd may draw: beyond this only the creatures nearest the hero get one (a blend-mode quad
## each, and a phone pays for every overlapping one)
const SHADOW_BUDGET := 70
var slow_f := PackedFloat32Array()
var mark_t := PackedFloat32Array()
var mark_mult := PackedFloat32Array()
var spin_t := PackedFloat32Array()
var spin_to := PackedVector3Array()
var hold_t := PackedFloat32Array()
var _rains: Array = []   # the Djinn's strikes in flight: {left, next, interval, spread, radius, damage, strikes: [{at, t}]}
var _rumbles: Array = []   # the Gila's ground waves running down its fan (pass 43): {from, dir, len, front, speed, width, damage, kb, lift, hit, fx_t, info}
var _stalactites: Array = []   # the golem's swoops (pass 45): {center, dir, r, deg, left, gap, next, fall, damage, kb, lift, throw, throw_r, owner, hit, falling: [{at, t}], info}
var lift_d := PackedFloat32Array() # total lift duration
var lift_h := PackedFloat32Array() # current height above the ground
var lift_a := PackedFloat32Array() # swirl angle around the tornado
var lift_cd := PackedFloat32Array() # seconds before a tornado may grab this one again
## What kind of lift (pass 46): 0 the tornado's toss (spin, flung out, hurt on landing), 1 a bounce (`bounce`: straight
## up and down on the spot, no spin, no harm, the shove in `lift_knock` on landing, `lift_peak` metres at the top)
var lift_mode := PackedByteArray()
var lift_peak := PackedFloat32Array()
var lift_knock := PackedVector3Array()
## Pass 48, per creature: the spawn's running number (`serial`: a weapon can tell a creature from the next one put in its
## slot); a slow of its moves AND its attacks (`hamper_f` for `hamper_t` seconds: hamper, attack_clock); a tint held for a
## few seconds (`status_tint` for `status_t`: set_status_tint); a blue burn (`fire_blue`: Methanol, Moonshine); and the
## training dummy's two (`undying`: a hit that would kill it fills it up again; `home`: where the dummy brain walks back to,
## the spot it spawned on)
var serial := PackedInt32Array()
var hamper_t := PackedFloat32Array()
var hamper_f := PackedFloat32Array()
var status_tint := PackedColorArray()
var status_t := PackedFloat32Array()
var fire_blue := PackedByteArray()
var undying := PackedByteArray()
var home := PackedVector3Array()
## The training dummies' behaviours (pass 49, Garry's arena list; Game sets them per dummy through set_dummy_mode):
## DUMMY_STAND stands on its spot and walks back when shoved (pass 48); DUMMY_PATROL walks left and right along world X,
## DUMMY_BEAT metres either side of its spot, turning at the ends (shoved off, it carries on from where it lands, _patrol);
## DUMMY_MELEE chases the hero while he is within DUMMY_CHASE of its spot (else it goes back) and bites on a touch like a
## creature; DUMMY_RANGED stands and spits at him within its `ranged` block's range exactly like the Spit Cactus (the red
## ring where he stands, the lob, the splash). `dummy_roam` 1: an attacker with nothing to chase or spit at patrols
## instead of standing (the arena's Patrol setting); `patrol_dir` is the way its beat is heading, +1 east, -1 west.
const DUMMY_STAND := 0
const DUMMY_PATROL := 1
const DUMMY_MELEE := 2
const DUMMY_RANGED := 3
const DUMMY_BEAT := 2.0
const DUMMY_CHASE := 12.0
var dummy_mode := PackedByteArray()
var dummy_roam := PackedByteArray()
var patrol_dir := PackedFloat32Array()
## Pass 50 (Garry: the Bull Beetle should "push enemies out of the way, always to the side, and only a little bit"): the
## seconds before this creature can be shoved aside by a charger again, so a charger passing through gives it one shove
## (SHOVE_GRACE) instead of one on every tick it overlaps. SHOVE_REACH is how far past touching the shove reaches, so the
## crowd parts as the charger arrives rather than after it has run into them.
var shove_t := PackedFloat32Array()
const SHOVE_GRACE := 0.6
## Pass 51 (Garry: Dragon's Breath should give "a chance that an enemy will catch fire", 60%): a weapon's
## `params.ignite_chance` (WeaponInstance.ignite_chance) is rolled once per creature per shot. The pellets of one volley
## land on a creature within a few frames, so a roll holds IGNITE_ROLL_HOLD seconds for that weapon (`ign_t`, `ign_w`)
## and every pellet of the volley reads the same answer (`ign_ok`); the next volley, a second barrel 0.15 s later
## included, rolls again. Rolled on the crowd's own generator, never the shared one.
var ign_t := PackedFloat32Array()
var ign_ok := PackedByteArray()
var ign_w := PackedStringArray()
const IGNITE_ROLL_HOLD := 0.1
const SHOVE_REACH := 0.25
var _serial := 0
## The map's pace knob (pass 48, Run.move_pace, read every tick and at every spawn): a creature walks at its speed times
## this, a charge and a scripted roll run at it and last 1/pace as long (so they cover the same ground), every wind-up,
## telegraph and warning lasts 1/pace, and the creatures' shots fly on hostile_clock(). Never put into the creatures'
## shared delta: poison and fire ticks, attack cooldowns and the spawns keep their clocks. Pass 60: times
## `creature_speed_mult` (the timeline's, 0.9 on Red Canyon; Garry: "reduce the movement speed of all enemies by 10%"
## as "a multiplier for all"): the creatures, Elites, bosses and their shots, never the hero (Player reads Run.move_pace()).
var pace := 1.0
## The timeline's creature_speed_mult (pass 60, WaveTimeline.creature_speed_mult, set by WaveDirector._apply_mults at a
## run's start and every normal tick, in the arena too): folded into `pace` wherever it is read, so every walk, charge,
## roll, wind-up, warning and hostile shot goes at this multiple. 1 = as the creatures' data says.
var creature_speed_mult := 1.0
## How far up out of the sand a creature is (pass 60, Garry: "a visible sequence of the Scorpion actually popping from
## the ground"): 1 = standing on it, as every creature is; 0 at the moment a burrow brings one up. It climbs to 1 over
## RISE_TIME (at the creatures' pace), the painting rising out of the ground (_render sinks it along the billboard's up by
## the part still under, the terrain hides that part), its shadow growing with it; a rising creature can be hit (it is
## there to see) but does not bite and starts no attack until it is up.
var rise_t := PackedFloat32Array()
const RISE_TIME := 0.4
## Rides on the frame index's fraction in the instance data while a creature rises (both creature shaders floor the frame):
## enemy_silhouette.gdshader draws nothing for it then, since the part still under the sand, which the terrain hides from
## the main pass, had shown through the see-through pass as a ghost of the whole figure.
const RISE_FLAG := 0.5
## The burrow's mound: its radius as a share of the creature's size (0.9 m for the 3 m scorpion, 1.5 for the 5 m Gila), a
## dome of sand swelling under the ring through the wind-up (_mound_start, below rise_ease).
const MOUND_FRAC := 0.3
## Where each creature's brain means to go this tick (the `desired` velocity _steer computes, before the crowd's
## separation and any knockback), pass 60: a creature that fights at range (_t_faces) faces and walks by this, so a shove
## or a knock no longer turns it round (the Sun Prophet "flickered between frames": his view flipped every tick between
## his walk and the hero as the crowd pressed him).
var intent := PackedVector3Array()
## An eight-direction creature's view holds at least VIEW_MIN seconds after a change (pass 60), on top of the hysteresis.
var view_t := PackedFloat32Array()
const VIEW_MIN := 0.25
## The crowd's mean max HP (priority_index's yardstick), refreshed once a tick (and by refresh_crowd_stats).
var _mean_max_hp := 0.0
## The dying creature's max HP while enemy_died is out (pass 48: Powder Keg's blast is a share of it).
var died_max_hp := 0.0
## The dying creature's own size while enemy_died is out (pass 58: a size-range row rolls each creature's size, while its
## def's `size` stays the painting's JSON size), for whatever sizes an effect by the body.
var died_size := 0.0

var free_list: Array = []
var count_alive := 0
var boss_index := -1
var _tick := 0

# types
var types: Array = []          # {def, mm, mmi, frames, shadow}
var type_by_id: Dictionary = {}   # EnemyDef.type_key() -> index in `types` (id, id@variant, id@variant#overrides)
## Every type of one creature id (pass 53): the base, its art variants and its overridden copies, so alive_of / load_of
## and the director's max_alive see them as one creature. id -> Array of type indices.
var _types_of_id: Dictionary = {}
var elites: Array = []         # EliteModDef
var _shader: Shader = preload("res://core/shaders/enemy_billboard.gdshader")
var _sil_shader: Shader = preload("res://core/shaders/enemy_silhouette.gdshader")
var _shadow_shader: Shader = preload("res://core/shaders/blob_shadow.gdshader")
var _shadow_mm: MultiMesh
var _shadow_mmi: MultiMeshInstance3D
var _rng := RandomNumberGenerator.new()
## The crowd's grid (pass 33.8): flat arrays instead of a dictionary of arrays. Each cell holds the first creature in it
## (`_g_head`, -1 for none) and each creature the next one in its cell (`_g_next`), rebuilt every tick. Cells are CELL
## metres on the same boundaries as before, and each cell lists its creatures in index order, so every query returns
## what it always did, in the same order.
var _gw := 0
var _g_half := 0.0
var _g_head := PackedInt32Array()
var _g_next := PackedInt32Array()
## The map's obstacles by cell (pass 33.8): a creature checks only the obstacles whose circle, widened by the widest
## creature, reaches its cell. It used to check every obstacle on the map every time it steered.
const OBST_CELL := 4.0
var _obst_cells: Dictionary = {}   # Vector2i -> PackedInt32Array of obstacle indices, in order
var _obst_n := -1
var _obst_margin := 0.0
var _max_r := 0.0
## The wide bodies (pass 58 fix round, the review: a size range makes a giant of any creature, and _steer's 3 x 3 cells
## only see neighbours within one CELL, so two bodies wider than that together could stand inside each other): every
## creature in the grid wider than BIG_R (half a cell) and the widest radius, both as the grid saw them this tick. A wide
## body scans as many cells as its reach needs; a narrow one also checks the wide ones past its 3 x 3 while they are few.
const BIG_R := CELL * 0.5
const BIG_LIST_MAX := 16
var _big := PackedInt32Array()
var _grid_max_r := 0.0
## Per type, read every tick (pass 33.8: a dictionary lookup per creature per tick before): an eight-direction strip,
## its walk and death frame rates, whether it turns to face the hero when it stands (the ranged brains), its MultiMesh,
## its badge, and the frame table (offset and count of each of the 13 strips, and which of them exist).
var _t_eight := PackedByteArray()
var _t_run_fps := PackedFloat32Array()
var _t_die_fps := PackedFloat32Array()
var _t_faces := PackedByteArray()
## per type, two entries (front set, back set): how its painting is mirrored, 0 = painted facing screen-right (mirror
## while heading left), 1 = painted facing left (the mirror inverted), 2 = straight on (never mirrored); pass 45
var _t_face_fix := PackedByteArray()
var _t_mm: Array = []
var _t_badge := PackedStringArray()
var _t_hit_ok := PackedByteArray()
var _t_charge := PackedByteArray()
var _t_off := PackedInt32Array()
var _t_cnt := PackedInt32Array()
## per type (pass 47): 1 for an Elite or a boss by its kind (Big Game Hunter), and four numbers of its shadow tuning
## (EnemyDef.shadow): width and depth multipliers, metres up the screen at the def's size per metre of it, and the share
## of the cell the painting sinks
var _t_big := PackedByteArray()
var _t_sh := PackedFloat32Array()
## per type (pass 48): 1 for the training dummy's brain, whose touch never reaches the hero (pass 49: unless it is set
## to melee, dummy_mode)
var _t_dummy := PackedByteArray()
## seconds between two bites, per type (pass 53: EnemyDef.contact_cd, the wave schema's `contact_cd`; it was a literal 0.6)
var _t_ccd := PackedFloat32Array()
## per type (pass 67): the share of a hero-side shove the creature takes, 1 - EnemyDef.knockback_resist (the Hammer Giant
## 0.33): a hit's kb_force push, a blast's throw_radius, the pull and the Ram are multiplied by it; the boss's 0.15 is on
## top of it, never replaced by it
var _t_kbt := PackedFloat32Array()
## per type (pass 50, Garry: the Bull Beetle's charge "feels too static"): how a charger carries its charge, CV_N numbers
## each read off its `charge` block by charge_numbers(): the shake at the end of the wind-up (metres side to side), the
## crouch (a share of its height), the legs' speed (times its walk: the wind-up scrabbles up to it in place, the charge
## runs at it), the lean into the run (radians, the full angle heading straight across the screen), the dust (1 a full
## trail), the sideways shove for each creature in its way while it charges and while it walks (metres a second), and
## the wind-up's seconds. Every key is off by default, so a charger without them (the Dune Scorpion) is as it was.
var _t_cv := PackedFloat32Array()
const CV_N := 8
var _t_ok := PackedByteArray()     # eight-direction: the strip exists (frames_of > 0 and in the anims)
var _t_okb := PackedByteArray()    # the back strip counts (frames_of > 0, as the old check read it): run_b, idle_b
const ANIM_NAMES := ["run", "idle", "attack", "hit", "die", "run_b", "idle_b", "run_s", "idle_s", "run_bd", "idle_bd", "run_fd", "idle_fd"]
const N_ANIMS := 13
const A_RUN := 0
const A_IDLE := 1
const A_ATTACK := 2
const A_HIT := 3
const A_DIE := 4
## the strip for run (row 0) or idle (row 1) seen from view 0 front, 1 back, 2 side, 3 back-diagonal, 4 front-diagonal
const VIEW_ANIM := [[0, 5, 7, 9, 11], [1, 6, 8, 10, 12]]
var _cf_tick := Vector3(0, 0, -1)  # the camera's forward, read once a tick
var _ticks := 0                    # physics ticks run: the draw waits for a new one
var _drawn := -1


func _ready() -> void:
	_rng.randomize()
	pos.resize(MAX); vel.resize(MAX); kb.resize(MAX); hp.resize(MAX); max_hp.resize(MAX)
	speed.resize(MAX); dmg.resize(MAX); radius.resize(MAX); size.resize(MAX); dr.resize(MAX); blown.resize(MAX)
	hidden.resize(MAX); held.resize(MAX); atk_i.resize(MAX); atk_t.resize(MAX); atk_target.resize(MAX); frenzy_t.resize(MAX)
	freeze_t.resize(MAX); stun_t.resize(MAX); onscreen.resize(MAX)
	serial.resize(MAX); hamper_t.resize(MAX); hamper_f.resize(MAX); status_tint.resize(MAX); status_t.resize(MAX)
	fire_blue.resize(MAX); undying.resize(MAX); home.resize(MAX)
	dummy_mode.resize(MAX); dummy_roam.resize(MAX); patrol_dir.resize(MAX); shove_t.resize(MAX)
	ign_t.resize(MAX); ign_ok.resize(MAX); ign_w.resize(MAX)
	slow_t.resize(MAX); slow_f.resize(MAX); mark_t.resize(MAX); mark_mult.resize(MAX); spin_t.resize(MAX); spin_to.resize(MAX); hold_t.resize(MAX)
	type_idx.resize(MAX); elite_idx.resize(MAX); state.resize(MAX); timer.resize(MAX); cooldown.resize(MAX)
	anim_t.resize(MAX); flash.resize(MAX); squash.resize(MAX); flip.resize(MAX); contact_cd.resize(MAX)
	alive.resize(MAX); charge_dir.resize(MAX); xp_scale.resize(MAX); vtint.resize(MAX); vspecial.resize(MAX)
	vglow.resize(MAX)
	fixed.resize(MAX); f_stage.resize(MAX); f_hpt.resize(MAX); f_lvh.resize(MAX); f_dmt.resize(MAX); f_lvd.resize(MAX)
	f_bsz.resize(MAX); f_tu.resize(MAX)
	lift_mode.resize(MAX); lift_peak.resize(MAX); lift_knock.resize(MAX)
	away.resize(MAX); view.resize(MAX); poison_tick.resize(MAX); flash_green.resize(MAX)
	poison_src.resize(MAX); fire_src.resize(MAX); fire_tick.resize(MAX); flash_hot.resize(MAX); fire_puff.resize(MAX)
	# pass 60: everyone starts up on the sand, meaning to go nowhere, free to turn
	rise_t.resize(MAX); rise_t.fill(1.0); intent.resize(MAX); view_t.resize(MAX)
	# pass 73 (lane GROUND): how fast each one rises or sinks
	rise_v.resize(MAX)
	for i in range(MAX):
		poison_src[i] = {}; fire_src[i] = {}; lift_t.resize(MAX); lift_d.resize(MAX); lift_h.resize(MAX); lift_a.resize(MAX); lift_cd.resize(MAX)
	for i in range(MAX - 1, -1, -1):
		free_list.append(i)
	elites = Registry.elites_list()
	_build_shadows()
	if not Run.build_changed.is_connected(_on_build_changed):
		Run.build_changed.connect(_on_build_changed)


func _on_build_changed() -> void:
	_pstats_dirty = true


## The hero's numbers this manager reads (pass 47), read again only when marked stale: every tick and on a build change.
func _pstats() -> void:
	if not _pstats_dirty:
		return
	_pstats_dirty = false
	var s: StatSheet = Run.player_sheet
	if s == null:
		return
	_debuff_mult = maxf(s.get_stat("debuff_duration", 1.0), 0.0)
	_freeze_chance = clampf(s.get_stat("freeze_chance", 0.0), 0.0, 1.0)
	_crit_heal = clampf(s.get_stat("crit_heal_chance", 0.0), 0.0, 1.0)
	_elite_dmg = s.get_stat("elite_damage", 0.0)
	_difficulty = maxf(s.get_stat("difficulty", 0.0), 0.0)
	_fire_vuln = s.get_stat("fire_vuln", 0.0)
	_poison_slow = s.get_stat("poison_slow", 0.0)
	_sunburn = maxf(Run.perk_param("sunburn", "bonus", 0.2), 0.0) if Run.has_perk("sunburn") else 0.0
	var ll := Run.has_perk("lingering_light")
	_ll_harder = 1.0 + maxf(Run.perk_param("lingering_light", "harder", 0.3), 0.0) if ll else 1.0
	_ll_longer = 1.0 + maxf(Run.perk_param("lingering_light", "longer", 0.3), 0.0) if ll else 1.0
	# pass 70 (lane LINES): Bucking Bronco's chance, Prairie Fire's jumps
	_pstats_lines(s)


## Reads the hero's numbers again now (a test or a tool that edits Run.player_sheet by hand).
func refresh_player_stats() -> void:
	_pstats_dirty = true
	_pstats()


## Ducktape (pass 47): how many times longer a debuff lasts on the creatures (1 = as the item says).
func debuff_mult() -> float:
	_pstats()
	return _debuff_mult


## Big Game Hunter's prey (pass 47): the boss, an Elite (its kind) or a creature wearing an elite modifier.
func is_big_game(i: int) -> bool:
	if i < 0 or i >= MAX or alive[i] == 0:
		return false
	return i == boss_index or elite_idx[i] >= 0 or _t_big[type_idx[i]] == 1


## Every hostile damage's multiplier now (pass 54): the timeline's creature_damage_mult times its damage curve's value.
## Pass 58: a creature's own hits read host_of(i) instead; this is for what no creature owns (the Brander's ring, which
## Game burns with) and for a creature spawned by hand.
func hostile_mult() -> float:
	return creature_damage_mult * damage_time_mult


## The stage multiplier creature `i`'s hits carry (pass 58, R1): the one at its spawn when a source fixed its numbers,
## else the live one (a creature spawned by hand, a boss, an Elite by its kind: as before).
func stage_of(i: int) -> float:
	return f_stage[i] if fixed[i] == 1 else stage_mult


## The hero-level damage factor creature `i`'s hits carry (pass 58): its source's, fixed at the source's first spawn, else
## the live one.
func lvd_of(i: int) -> float:
	return f_lvd[i] if fixed[i] == 1 else level_dmg_mult


## creature_damage_mult times the damage curve creature `i`'s hits carry (pass 58): the curve at its source's start (1 for
## a source that overrides `damage`), else hostile_mult() now.
func host_of(i: int) -> float:
	return creature_damage_mult * f_dmt[i] if fixed[i] == 1 else hostile_mult()


## The source numbers creature `i` was spawned with (pass 58), as spawn() takes them: {} for a plain creature on the live
## numbers. A split child spawns with its parent's: the fixed factors and the stage at the parent's spawn (`stage`; the
## fix round: a stage-1 splitter killed after the portal made stage-2 children), and the parent's rolled size and hue
## (`size`, `tint_u`: a child re-rolled them, so a splitter of a [1, 3] row could burst into children bigger than itself,
## each a different colour).
func src_of(i: int) -> Dictionary:
	if i < 0 or i >= MAX:
		return {}
	var out: Dictionary = {}
	if fixed[i] == 1:
		out = {"hp_time": f_hpt[i], "dmg_time": f_dmt[i], "lv_hp": f_lvh[i], "lv_dmg": f_lvd[i], "stage": f_stage[i]}
	if f_bsz[i] > 0.0:
		out["size"] = f_bsz[i]
	if f_tu[i] >= 0.0:
		out["tint_u"] = f_tu[i]
	return out


## The source numbers of something that comes now (pass 58: a boss's brood, "the moment it fires"): the director's values
## of the moment (the clock stands still through a boss fight, so they are the fight's).
func now_src() -> Dictionary:
	return {"hp_time": hp_time_mult, "dmg_time": damage_time_mult, "lv_hp": level_hp_mult, "lv_dmg": level_dmg_mult}


## What a boss's brood of `id` plays (pass 58), as {stats, src}: the director's event_numbers (the moment it is called,
## or, the fix round, the numbers of a roster row or wave bringing the same creature then: the Brander's imps beside the
## imp row's), now_src() without a director (a test's crowd).
func brood_numbers(id: String) -> Dictionary:
	var d = game.get("director") if game else null
	if d != null and d.has_method("event_numbers"):
		return d.event_numbers(id, "", {})
	return {"stats": {}, "src": now_src()}


## The shove creature `i`'s bite gives the hero, m/s (pass 54, Garry: every creature its own number): its def's
## hit_knockback() (its own `knockback`, a row's override, else the default from its damage), BIG_KNOCK times for a boss,
## an Elite or a creature wearing an elite modifier. 0 for no creature.
func bite_knock(i: int) -> float:
	if i < 0 or i >= MAX or alive[i] == 0 or type_idx[i] < 0 or type_idx[i] >= types.size():
		return 0.0
	var def: EnemyDef = types[type_idx[i]]["def"]
	return def.hit_knockback() * (BIG_KNOCK if is_big_game(i) else 1.0)


## Which creatures show on the screen (pass 54): half the crowd a tick by `parity` (the other half on the next; -1 all of
## them), each tested a little above its feet against the screen grown by SCREEN_MARGIN_M at the hero's feet. Without a
## camera that can say (tools, tests, a stand-in rig) every creature counts as on the screen.
func refresh_onscreen(parity: int = -1) -> void:
	if onscreen.size() != MAX:
		return
	var rig = game.get("camera") if game != null else null
	var cam: Camera3D = null
	if rig is Node and (rig as Node).has_method("on_screen"):
		cam = (rig as Node).get("camera") as Camera3D
	if cam == null or not cam.is_inside_tree():
		onscreen.fill(1)
		return
	var ppm: float = float((rig as Node).call("pixels_per_metre")) if (rig as Node).has_method("pixels_per_metre") else 90.0
	var rect := cam.get_viewport().get_visible_rect().grow(SCREEN_MARGIN_M * ppm)
	for i in range(MAX):
		if alive[i] == 0 or (parity >= 0 and (i & 1) != parity):
			continue
		var p := pos[i] + Vector3(0, 0.6 + lift_h[i], 0)
		onscreen[i] = 0 if cam.is_position_behind(p) or not rect.has_point(cam.unproject_position(p)) else 1


## Whether the ranged weapons' picks skip what is off the screen (pass 54): unless the caller asks for `any_screen`, while
## Settings.ranged_on_screen and screen_filter_on are both on.
func _screen_only(any_screen: bool) -> bool:
	return not any_screen and screen_filter_on and onscreen.size() == MAX and Settings.ranged_on_screen


## Whether creature `i` may be a ranged weapon's pick (pass 54): it is on the screen, or the pick may be anywhere.
func screen_ok(i: int, any_screen: bool = false) -> bool:
	# pass 73 (lane GROUND): never one still rising out of the sand (targetable)
	if not targetable(i):
		return false
	return not _screen_only(any_screen) or (i >= 0 and i < onscreen.size() and onscreen[i] == 1)


## The lake (pass 54): a creature wading in it casts no shadow (its blob lay on the lake bed and drew over the water as a
## dark plate). Read off the map's lake_center / lake_radius the first time it is asked and again when the map changes;
## no lake, never in it. The edge is the map's in_water edge (1.02 of the radius). Pass 56: nor where the water as it is
## drawn (the map's water_disc, 1.06 of the radius) covers any of the blob from the camera, the hero's rule (shadow_wet).
var _lake_map := 0
var _lake_c := Vector2.ZERO
var _lake_r2 := 0.0
## The water's disc as the map draws it (pass 56): x and z its centre, y its top face, w its radius (0 = none); how far
## its rim reaches under the top; and, squared, how far from the lake's centre a shadow can be wet at all.
var _disc := Vector4.ZERO
var _disc_thick := 0.0
var _wet_far2 := 0.0
## Past the disc's edge, the widest blob (a big creature's, slid up the screen) and the line of sight's shift on a bank
## under the water's top stay inside this (pass 56): shadows further out are never asked.
const DISC_REACH := 4.0


func _lake_refresh() -> bool:
	if _lake_map == -1:
		# set by hand (set_lake): kept as it is
		return _lake_r2 > 0.0
	var map = game.get("map") if game != null else null
	if map == null or not is_instance_valid(map):
		if _lake_map != 0 or not _lakes_wet.is_empty():
			_clear_lakes()
		_lake_map = 0
		return false
	var id: int = (map as Object).get_instance_id()
	if id != _lake_map:
		_lake_map = id
		_clear_lakes()
		# pass 80 (lane OASIS): every lake the map names (map_lakes: its lakes(), else its one lake), each with the water
		# as it draws it (pass 56) when it tells it
		for l: Dictionary in map_lakes(map):
			var c: Vector2 = l["center"]
			var disc := Vector4.ZERO
			var thick := 0.0
			var dv: Variant = l.get("disc", null)
			if dv is Dictionary and not (dv as Dictionary).is_empty():
				var d: Dictionary = dv
				var dc: Vector2 = d.get("center", c)
				disc = Vector4(dc.x, float(d.get("top", 0.0)), dc.y, float(d.get("radius", 0.0)))
				thick = float(d.get("thick", 0.0))
			_add_lake(c, float(l["radius"]), disc, thick)
	return _lake_r2 > 0.0


## The drawn water's disc (pass 56, see _disc), and how far from the lake's centre a shadow can be wet with it.
func _set_disc(disc: Vector4, thick: float) -> void:
	_disc = disc if disc.w > 0.0 else Vector4.ZERO
	_disc_thick = maxf(thick, 0.0)
	var far := sqrt(_lake_r2)
	if _disc.w > 0.0:
		far = maxf(far, Vector2(_disc.x, _disc.z).distance_to(_lake_c) + _disc.w + DISC_REACH)
	_wet_far2 = far * far


## Whether `p` stands in the lake (pass 54, see _lake_refresh; set_lake for tests and tools without a map; pass 80: in
## any lake).
func in_lake(p: Vector3) -> bool:
	for l: Vector4 in _lakes_wet:
		var dx := p.x - l.x
		var dz := p.z - l.y
		if dx * dx + dz * dz < l.z:
			return true
	return false


## The lake by hand (tests, tools): centre and radius as the map gives them; a radius of 0 means none. `disc` and
## `thick` are the water as the map draws it (pass 56, its water_disc as a Vector4: x, z centre, y top face, w radius);
## without them only a wading creature loses its shadow. Pass 80: the one lake, in place of every lake there was
## (add_lake for more).
func set_lake(center: Vector2, r: float, disc := Vector4.ZERO, thick := 0.0) -> void:
	_clear_lakes()
	_lake_c = center
	_add_lake(center, r, disc, thick)
	_lake_map = -1


## One more lake by hand (pass 80, tests and tools; after set_lake).
func add_lake(center: Vector2, r: float, disc := Vector4.ZERO, thick := 0.0) -> void:
	_add_lake(center, r, disc, thick)
	_lake_map = -1


## Pass 80 (lane OASIS): every lake as the crowd reads it, the first also the one lake above (_lake_c, _lake_r2, _disc,
## _disc_thick, _wet_far2 as before): Vector4(x, z centre, the in_water edge squared, how far from the centre a shadow
## can be wet, squared), the drawn disc (as _disc; w 0 = none) and its thickness.
var _lakes_wet: Array[Vector4] = []
var _lakes_disc: Array[Vector4] = []
var _lakes_thick := PackedFloat32Array()


func _clear_lakes() -> void:
	_lake_r2 = 0.0
	_set_disc(Vector4.ZERO, 0.0)
	_lakes_wet.clear()
	_lakes_disc.clear()
	_lakes_thick = PackedFloat32Array()


func _add_lake(center: Vector2, r: float, disc: Vector4, thick: float) -> void:
	if r <= 0.0:
		return
	var r2 := (r * 1.02) * (r * 1.02)
	var d := disc if disc.w > 0.0 else Vector4.ZERO
	var far := sqrt(r2)
	if d.w > 0.0:
		far = maxf(far, Vector2(d.x, d.z).distance_to(center) + d.w + DISC_REACH)
	_lakes_wet.append(Vector4(center.x, center.y, r2, far * far))
	_lakes_disc.append(d)
	_lakes_thick.append(maxf(thick, 0.0))
	if _lakes_wet.size() == 1:
		_lake_c = center
		_lake_r2 = r2
		_set_disc(d, thick)


## Whether a shadow at `p` lies near enough any lake to be wet at all (pass 80: the render's cheap test before
## shadow_wet).
func _near_water(p: Vector3) -> bool:
	for l: Vector4 in _lakes_wet:
		var dx := p.x - l.x
		var dz := p.z - l.y
		if dx * dx + dz * dz < l.w:
			return true
	return false


## Whether creature `i`'s blob shadow, drawn with `xf` (shadow_xform), lies over the water (pass 54: it wades; pass 56:
## or the drawn disc covers any of the blob as the camera at `eye` sees it, Vector3.INF meaning from straight above):
## BillboardSprite.water_covers_blob, the very test of the hero's shadow in Game._sink_hero, so the two go at the same
## spot. Ask after _lake_refresh.
func shadow_wet(i: int, xf: Transform3D, eye: Vector3) -> bool:
	if in_lake(pos[i]):
		return true
	# pass 80: the drawn disc of whichever lake is near (each lake's own reach)
	for k in range(_lakes_disc.size()):
		var d: Vector4 = _lakes_disc[k]
		if d.w <= 0.0:
			continue
		var l: Vector4 = _lakes_wet[k]
		var dx := pos[i].x - l.x
		var dz := pos[i].z - l.y
		if dx * dx + dz * dz >= l.w:
			continue
		# the quad is a metre square (_build_shadows): its edges, halved, as drawn, are the blob's half-axes
		if BillboardSprite.water_covers_blob(xf.origin, xf.basis.x * 0.5, xf.basis.z * 0.5, eye, d, _lakes_thick[k]):
			return true
	return false


## Wading (pass 80, lane OASIS; Garry: "make the water slow everyone down when they walk though it, not by a lot, just
## 10%"): creature `i`'s walking speed factor, 1 - the map's water_slow (WaveTimeline, 0.1; _wade_slow, read once a tick
## by _wade_tick) while it stands in any lake: its own walk, charge, roll or brain's move (vel), never a push, knockback
## or pull (kb). Elites and bosses too; not one in the air (tossed, bounced, launched: those never walk), under the sand
## or part-way (rising out of it, sinking into a burrow), held or dying. The tick reads _wade_k: once a tick _wade_tick
## asks the crowd's grid which creatures stand in each lake (indices_in_radius) and marks them, so the cost is the few
## near the water, not the whole crowd.
var _wade_slow := 0.0
## each creature's factor this tick (1 unless it wades) and the ones marked, to put back next tick
var _wade_k := PackedFloat32Array()
var _wading := PackedInt32Array()


func _wade_tick() -> void:
	_lake_refresh()
	if _wade_k.size() != MAX:
		_wade_k.resize(MAX)
		_wade_k.fill(1.0)
	for i in _wading:
		_wade_k[i] = 1.0
	_wading.clear()
	if _lakes_wet.is_empty():
		_wade_slow = 0.0
		return
	var tl: WaveTimeline = Run.map.timeline if Run.map else null
	_wade_slow = clampf(tl.water_slow if tl else WaveTimeline.WATER_SLOW_DEFAULT, 0.0, 0.95)
	if _wade_slow <= 0.0:
		return
	var k := 1.0 - _wade_slow
	for l: Vector4 in _lakes_wet:
		# (the grid holds no one hidden, held or dying)
		for i in indices_in_radius(Vector3(l.x, 0.0, l.y), sqrt(l.z)):
			if lift_h[i] > 0.05 or rise_t[i] < 1.0 or _wade_k[i] < 1.0:
				continue
			_wade_k[i] = k
			_wading.append(i)


## The rule for one creature now (tools and tests; the tick reads _wade_k, marked by the same rule).
func _wade_mult(i: int) -> float:
	if _wade_slow <= 0.0 or i < 0 or i >= MAX or alive[i] == 0 or not in_lake(pos[i]):
		return 1.0
	if lift_h[i] > 0.05 or hidden[i] == 1 or held[i] == 1 or rise_t[i] < 1.0 or state[i] == STATE_DYING:
		return 1.0
	return 1.0 - _wade_slow


func _build_shadows() -> void:
	_shadow_mm = MultiMesh.new()
	_shadow_mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.orientation = PlaneMesh.FACE_Y
	_shadow_mm.mesh = quad
	_shadow_mm.instance_count = MAX
	_shadow_mm.visible_instance_count = 0
	_shadow_mmi = MultiMeshInstance3D.new()
	_shadow_mmi.multimesh = _shadow_mm
	var mat := ShaderMaterial.new()
	mat.shader = _shadow_shader
	# under the gems and coins (pass 54): a gem by a creature's feet lay in its shadow and read murky
	mat.render_priority = SHADOW_PRIORITY
	_shadow_mmi.material_override = mat
	_shadow_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# pass 84: never culled by a stale MultiMesh box (the shadows move every frame), as the scenery's (PropField)
	_shadow_mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(_shadow_mmi)


## Where a creature that fights at range stands so the player sees it: `keep` metres off the hero, on his portrait
## screen. That is up the screen from him (or a little below him when the creature is already well below him), and
## never more than `side` metres to either side: the screen is narrow, and a caster that parked 14 m off to the side
## sat under the HUD strip at the screen's edge, where nobody could find it (pass 33.1).
func _screen_spot(i: int, ppos: Vector3, keep: float, side: float) -> Vector3:
	var cf := _camera_forward()
	var cr := Vector3(-cf.z, 0, cf.x)
	var off := pos[i] - ppos
	off.y = 0.0
	var up := off.dot(cf)
	var along: float = keep if up > -keep * 0.35 else -minf(keep * 0.7, 6.0)
	return ppos + cf * along + cr * clampf(off.dot(cr), -side, side)


func _camera_forward() -> Vector3:
	var yaw: float = game.camera.current_yaw() if game and game.get("camera") and game.camera and game.camera.has_method("current_yaw") else 0.0
	return Vector3(-sin(yaw), 0, -cos(yaw))


## The camera's up, the billboards' own up (pass 47: a painting that sinks slides down it): the live camera's, else the
## fixed rig's, 46 degrees down along the camera's forward.
func _cam_up() -> Vector3:
	var vp := get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp else null
	if cam:
		return cam.global_transform.basis.y
	return Vector3(0, 0.695, 0) + _cf_tick * 0.719


## Tornado: every grounded enemy inside the radius is thrown into the air for `duration` seconds.
func lift_radius(center: Vector3, radius: float, duration: float = 1.6) -> int:
	var n := 0
	for i in indices_in_radius(center, radius):
		if lift_t[i] > 0.0 or lift_cd[i] > 0.0 or state[i] == STATE_DYING or i == boss_index:
			continue
		lift_mode[i] = 0
		lift_t[i] = duration
		lift_d[i] = duration
		lift_a[i] = atan2(pos[i].z - center.z, pos[i].x - center.x)
		kb[i] = Vector3.ZERO
		n += 1
	return n


## Tornado: airborne enemies near the centre swirl around it and drift with it.
func swirl(center: Vector3, radius: float, delta: float) -> void:
	for i in range(MAX):
		if alive[i] == 0 or lift_t[i] <= 0.0 or lift_mode[i] == 1:
			continue
		var d := pos[i] - center
		d.y = 0.0
		if d.length() > radius * 2.5:
			continue
		# spiral outward as the ride goes on, so the drop lands at the rim, not in the funnel
		var f := 1.0 - clampf(lift_t[i] / maxf(lift_d[i], 0.01), 0.0, 1.0)
		var r := clampf(d.length(), 0.6, radius) * (0.7 + 1.4 * f)
		var target := center + Vector3(cos(lift_a[i]), 0, sin(lift_a[i])) * r
		var np := pos[i].lerp(target, clampf(delta * 6.0, 0.0, 1.0))
		np.y = _height(np.x, np.z)
		pos[i] = np


## Register an enemy type so it can be spawned. Safe to call twice.
func register_type(def: EnemyDef) -> int:
	if def == null:
		return -1
	# one type per art variant (pass 34): the game's is keyed by the id, another by id@code (EnemyDef.type_key)
	var key := def.type_key()
	if type_by_id.has(key):
		return type_by_id[key]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	mm.mesh = quad
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.name = "MM_" + key.replace("@", "_")
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	var tex: Texture2D = def.sprite
	if tex == null:
		tex = PlaceholderArt.enemy_strip(def)
	mat.set_shader_parameter("sprite", tex)
	mat.set_shader_parameter("frames", float(def.total_frames()))
	var cols: int = def.strip_cols if def.sprite else 0
	mat.set_shader_parameter("cols", float(cols))
	mat.set_shader_parameter("rows", float(ceili(float(def.total_frames()) / float(cols))) if cols > 0 else 1.0)
	# the occluded pass: a rim where a prop hides the creature (bosses too); same strip uniforms
	var sil := ShaderMaterial.new()
	sil.shader = _sil_shader
	sil.set_shader_parameter("sprite", tex)
	sil.set_shader_parameter("frames", float(def.total_frames()))
	sil.set_shader_parameter("cols", float(cols))
	sil.set_shader_parameter("rows", float(ceili(float(def.total_frames()) / float(cols))) if cols > 0 else 1.0)
	mat.next_pass = sil
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(mmi)
	var t := {"def": def, "mm": mm, "mmi": mmi, "mat": mat, "share": def.cap_share, "frames": def.total_frames(), "run_fps": float(def.fps.get("run", 0.0)), "die_fps": float(def.fps.get("die", 6.0)), "eight": def.frames_of("run_s") > 0 and def.anims.has("run_s"),
		"badge": def.badge_for(), "head": def.head}
	types.append(t)
	type_by_id[key] = types.size() - 1
	# every type of this creature id under one name (pass 53): alive_of counts them together
	if not _types_of_id.has(def.id):
		_types_of_id[def.id] = []
	(_types_of_id[def.id] as Array).append(types.size() - 1)
	_t_ccd.append(maxf(def.contact_cd, 0.05))
	_t_kbt.append(1.0 - clampf(def.knockback_resist, 0.0, 1.0))
	_t_eight.append(1 if bool(t["eight"]) else 0)
	_t_run_fps.append(float(t["run_fps"]))
	_t_die_fps.append(float(t["die_fps"]))
	_t_faces.append(1 if def.brain in ["caster", "kite", "artillery", "support", "sniper"] else 0)
	_t_face_fix.append(_face_fix(def.front_faces))
	_t_face_fix.append(_face_fix(def.back_faces))
	_t_mm.append(mm)
	_t_badge.append(str(t["badge"]))
	_t_hit_ok.append(1 if def.frames_of("hit") > 0 else 0)
	_t_charge.append(1 if def.charge.size() > 0 else 0)
	for a: String in ANIM_NAMES:
		_t_off.append(def.frame_offset(a))
		_t_cnt.append(def.frames_of(a))
		_t_ok.append(1 if def.frames_of(a) > 0 and def.anims.has(a) else 0)
	_t_okb.append(1 if def.frames_of("run_b") > 0 else 0)
	_t_okb.append(1 if def.frames_of("idle_b") > 0 else 0)
	_t_big.append(1 if def.archetype == "elite" or def.archetype == "boss" else 0)
	_t_dummy.append(1 if def.brain == "dummy" else 0)
	# pass 73 (lane SNIPER): an attack strip painted front and back (EnemyDef.attack_views)
	_t_atkv.append(1 if def.attack_views == "front_back" else 0)
	_t_sh.append_array(shadow_numbers(def))
	_t_cv.append_array(charge_numbers(def))
	return types.size() - 1


## A def's charge carriage as the tick and the render read it (pass 50): [shake, crouch, legs, lean (radians), dust, shove,
## shove_walk, windup]. Each key of the `charge` block is off when it is missing: no shake, no crouch, legs at the walk's
## speed, no lean, no dust, no shove.
static func charge_numbers(def: EnemyDef) -> PackedFloat32Array:
	var c: Dictionary = def.charge
	return PackedFloat32Array([maxf(float(c.get("shake", 0.0)), 0.0), clampf(float(c.get("crouch", 0.0)), 0.0, 0.5),
		maxf(float(c.get("legs", 1.0)), 1.0), deg_to_rad(clampf(float(c.get("lean", 0.0)), -30.0, 30.0)), maxf(float(c.get("dust", 0.0)), 0.0),
		maxf(float(c.get("shove", 0.0)), 0.0), maxf(float(c.get("shove_walk", 0.0)), 0.0), maxf(float(c.get("windup", 0.8)), 0.05)])


## A def's shadow tuning as the render reads it (pass 47): [width mult, depth mult, up per metre of size, drop].
static func shadow_numbers(def: EnemyDef) -> PackedFloat32Array:
	var sh: Dictionary = def.shadow_tuning()
	var sw := 1.0
	var sd := 1.0
	var sc = sh.get("scale", 1.0)
	if sc is Array and (sc as Array).size() >= 2:
		sw = float(sc[0])
		sd = float(sc[1])
	elif sc is float or sc is int:
		sw = float(sc)
		sd = float(sc)
	var up := float(sh.get("up", 0.0)) / maxf(def.size, 0.01)
	return PackedFloat32Array([maxf(sw, 0.0), maxf(sd, 0.0), up, clampf(float(sh.get("drop", 0.0)), -0.5, 0.5)])


## Puts a type's shadow tuning in place now (pass 47: the capture tools try numbers by eye without an import).
func set_shadow_tuning(t: int, tuning: Dictionary) -> void:
	if t < 0 or t >= types.size():
		return
	var def: EnemyDef = types[t]["def"]
	var keep := def.shadow
	def.shadow = tuning
	var n := shadow_numbers(def)
	def.shadow = keep
	for k in range(4):
		_t_sh[t * 4 + k] = n[k]


func _height(x: float, z: float) -> float:
	if height_fn.is_valid():
		return height_fn.call(x, z)
	return 0.0


# ---------------------------------------------------------------- spawning

## One creature of `def_id` at `at`: wearing `elite` (a modifier) when given, at `scale_mult` of its size and `hp_mult`
## of its health (a split child), as art variant `variant` (the arena's comparison, a roster row's; its own when "") and
## with the wave schema's `overrides` on its numbers (pass 53, EnemyDef.with_overrides through Registry.enemy_with: the
## copy is its own type, so a row's tougher skeletons and the plain ones live side by side). The index, or -1. Pass 58:
## `src` is the spawn source's fixed numbers (R1, WaveDirector.source_for / fixed_numbers: {hp_time, dmg_time, lv_hp,
## lv_dmg}), used in place of the live time and hero-level factors and kept for its later hits; {} = the live numbers, as
## before (a creature spawned by hand). A boss or an Elite by its kind ignores it. A size-range row (R2) rolls the size
## and a colour-range row (R3) the tint, per creature.
func spawn(def_id: String, at: Vector3, elite: EliteModDef = null, scale_mult := 1.0, hp_mult := 1.0, variant := "", overrides := {}, src := {}) -> int:
	var def: EnemyDef = Registry.enemy_with(def_id, variant, overrides)
	if def == null or free_list.is_empty():
		return -1
	var t := register_type(def)
	# met (pass 44): the Collection shows a creature once it has been on the sand
	Save.mark_seen("enemy", def.id)
	# the pace knob as it is now (pass 48): the walk speed below is set with it; times the creatures' own multiplier (pass 60)
	pace = Run.move_pace() * creature_speed_mult
	var i: int = free_list.pop_back()
	_serial += 1
	serial[i] = _serial
	blown[i] = 0
	held[i] = 0
	# on the screen until the next refresh says otherwise (pass 54)
	if onscreen.size() == MAX:
		onscreen[i] = 1
	pos[i] = Vector3(at.x, _height(at.x, at.z), at.z)
	vel[i] = Vector3.ZERO
	kb[i] = Vector3.ZERO
	# pass 58 (R1): a creature its source brought plays the source's numbers, fixed from its start (the time curves at the
	# source's start, the hero's level at its first spawn) and the stage multiplier now, and keeps them for every later
	# hit; a boss and an Elite by its kind keep their own rules, and a creature spawned by hand the live numbers, as before
	var own := src.has("hp_time") and def.archetype != "boss" and def.archetype != "elite"
	var hpt: float = float(src.get("hp_time", 1.0)) if own else hp_time_mult
	var lvh: float = float(src.get("lv_hp", 1.0)) if own else level_hp_mult
	var dmt: float = float(src.get("dmg_time", 1.0)) if own else damage_time_mult
	var lvd: float = float(src.get("lv_dmg", 1.0)) if own else level_dmg_mult
	# the stage multiplier now, or a split child's parent's at its spawn (the fix round)
	var stg: float = float(src.get("stage", stage_mult)) if own else stage_mult
	fixed[i] = 1 if own else 0
	f_stage[i] = stg
	f_hpt[i] = hpt
	f_lvh[i] = lvh
	f_dmt[i] = dmt
	f_lvd[i] = lvd
	# creature_hp_mult reaches everything but a boss (the boss branch below sets its own health)
	var ehp := def.hp * stg * hpt * hp_mult * lvh * creature_hp_mult
	var esp := def.speed * stage_speed_mult
	var edm := def.damage * stg * lvd * creature_damage_mult * dmt
	var ear := def.damage_reduction
	# pass 58 (R2): a size-range row rolls this creature's size in its range (in place of the variance's jitter below), and
	# its body's radius follows the rolled size unless the row set a radius; a split child takes its parent's roll (the
	# fix round)
	var ranged_size := def.size_range != Vector2.ZERO
	var base_sz: float = def.size
	if ranged_size:
		base_sz = clampf(float(src["size"]), def.size_range.x, def.size_range.y) if src.has("size") else _rng.randf_range(def.size_range.x, def.size_range.y)
	f_bsz[i] = base_sz if ranged_size else 0.0
	var esz := base_sz * scale_mult
	var rad: float = def.radius * (base_sz / maxf(def.size_ref, 0.01) if ranged_size and def.radius_follows else 1.0)
	var xps := def.xp_mult
	elite_idx[i] = -1
	if elite != null:
		elite_idx[i] = elites.find(elite)
		var sheet := StatSheet.new()
		sheet.set_bases({"hp": ehp, "speed": esp, "damage": edm, "damage_reduction": def.damage_reduction, "size": esz})
		sheet.add_effects(elite.effects, elite.id)
		ehp = sheet.get_stat("hp"); esp = sheet.get_stat("speed"); edm = sheet.get_stat("damage")
		ear = clampf(sheet.get_stat("damage_reduction"), 0.0, 0.9); esz = sheet.get_stat("size") * elite.scale_mult
		xps *= 4.0
	var vt := Color(1, 1, 1, 0)
	# pass 58 (R3): a colour-range row's own tint, a hue rolled in its range, from the row's first creature on (it is the
	# row's design, not the random colour that waits for colour_after_kills); it stands in for the variance palette's
	# tint, and a special's own tint, an elite modifier's colour and the status tints still win (tint_of)
	var row_tint := not def.tint_range.is_empty()
	var tint_u := 0.0
	if row_tint:
		# a split child keeps its parent's hue (the fix round)
		tint_u = clampf(float(src["tint_u"]), 0.0, 1.0) if src.has("tint_u") else _rng.randf()
		vt = EnemyDef.tint_color(def.tint_range, tint_u)
	f_tu[i] = tint_u if row_tint else -1.0
	var vsize := 1.0
	vspecial[i] = 0
	vglow[i] = 0.0
	if elite == null and not def.variance.is_empty():
		# every spawn is a little different: size, speed, a tint from the palette, and the odd special one
		var vr: Dictionary = def.variance
		# a size-range row's size was rolled above: no jitter on top (pass 58)
		var jit := 0.0 if ranged_size else float(vr.get("size", 0.0))
		vsize = 1.0 + _rng.randf_range(-jit, jit)
		esp *= 1.0 + _rng.randf_range(-float(vr.get("speed", 0.0)), float(vr.get("speed", 0.0)))
		# the tint and the special are colour, and colour comes after the run's first kills (pass 46); the size and
		# speed jitter above is not colour and is always on
		# (pass 69: a forced special, force_special, comes whatever the kills)
		if Run.kills >= colour_after_kills or force_special:
			var tints: Array = vr.get("tints", [])
			if not tints.is_empty() and not row_tint:
				var c := Color(str(tints[_rng.randi() % tints.size()]))
				vt = Color(c.r, c.g, c.b, float(vr.get("tint_strength", 0.35)))
			# Hot Sauce (pass 47): the dark special comes (1 + difficulty) times as often
			_pstats()
			var sp_roll: bool = force_special or _rng.randf() < float(vr.get("special_chance", 0.0)) * (1.0 + _difficulty)
			# pass 72 (lane SPEC): at most special_max_alive at once; a roll past it comes plain, a forced one still comes
			if sp_roll and not force_special and not _special_room():
				sp_roll = false
			# pass 73 (lane GROUND): a boss's or a caster's summon is never a special (force_plain, held round it)
			if force_plain:
				sp_roll = false
			if sp_roll:
				var sp: Dictionary = vr.get("special", {})
				# pass 69: each number the creature's own, else the map's special_defaults, else EnemyDef.SPECIAL_DEFAULTS
				var spd := special_defaults
				# (pass 69, Garry: "Make them 1.25 times bigger"): exactly its size factor, the plain one's spread dropped, so
				# a special is never smaller than a big plain one
				vsize = EnemyDef.special_value(sp, spd, "size")
				if ranged_size:
					# a size-range row's special stays inside the range (the fix round; Garry: "between 3-5 for example"): its
					# size factor lifts it towards the top, never past it; its HP, damage, XP and colour are the special's
					vsize = minf(vsize, def.size_range.y / maxf(base_sz, 0.01))
				ehp *= EnemyDef.special_value(sp, spd, "hp")
				edm *= EnemyDef.special_value(sp, spd, "damage")
				xps *= EnemyDef.special_value(sp, spd, "xp")
				vspecial[i] = 1
				vglow[i] = clampf(EnemyDef.special_value(sp, spd, "glow"), 0.0, 1.0)
				if row_tint:
					# a colour-range row's special keeps the row's colour (pass 58, the lead): a darker, stronger shade of the
					# hue this one rolled, so it still reads as the special one of that wave (its own wine tint had read as
					# "lost the colour"); its size factor above stays
					vt = EnemyDef.tint_special_color(def.tint_range, tint_u, EnemyDef.special_value(sp, spd, "tint_strength"))
				elif sp.has("tint"):
					var sc := Color(str(sp["tint"]))
					vt = Color(sc.r, sc.g, sc.b, EnemyDef.special_value(sp, spd, "tint_strength"))
		esz *= vsize
	vtint[i] = vt
	hp[i] = ehp; max_hp[i] = ehp; speed[i] = esp * pace; dmg[i] = edm; dr[i] = ear
	radius[i] = rad * scale_mult * (elite.scale_mult if elite else 1.0) * vsize
	_max_r = maxf(_max_r, radius[i])
	size[i] = esz
	type_idx[i] = t
	state[i] = STATE_SPAWN
	timer[i] = 0.35
	cooldown[i] = _rng.randf_range(0.5, 2.0)
	hidden[i] = 0
	rise_t[i] = 1.0
	rise_v[i] = 0.0
	intent[i] = Vector3.ZERO
	view_t[i] = 0.0
	atk_i[i] = 0
	atk_t[i] = 2.0
	frenzy_t[i] = 0.0
	freeze_t[i] = 0.0
	stun_t[i] = 0.0
	slow_t[i] = 0.0; slow_f[i] = 0.0; mark_t[i] = 0.0; mark_mult[i] = 1.0; spin_t[i] = 0.0; hold_t[i] = 0.0
	hamper_t[i] = 0.0; hamper_f[i] = 0.0; status_t[i] = 0.0; fire_blue[i] = 0; undying[i] = 0
	home[i] = pos[i]
	dummy_mode[i] = DUMMY_STAND; dummy_roam[i] = 0; patrol_dir[i] = 1.0
	shove_t[i] = 0.0
	ign_t[i] = 0.0
	if def.brain == "ambush":
		# it waits under the sand for the hero to walk over it
		hidden[i] = 1
		state[i] = STATE_MOVE
	anim_t[i] = _rng.randf() * 10.0
	flash[i] = 0.0
	squash[i] = 0.3
	flip[i] = 0
	away[i] = 0
	view[i] = 0
	poison_src[i] = {}
	poison_tick[i] = 0.0
	flash_green[i] = 0
	fire_src[i] = {}
	fire_tick[i] = 0.0
	fire_puff[i] = 0.0
	flash_hot[i] = 0
	lift_t[i] = 0.0
	lift_d[i] = 0.0
	lift_h[i] = 0.0
	lift_cd[i] = 0.0
	lift_mode[i] = 0
	lift_peak[i] = 0.0
	lift_knock[i] = Vector3.ZERO
	contact_cd[i] = 0.0
	charge_dir[i] = Vector3.ZERO
	xp_scale[i] = xps
	alive[i] = 1
	count_alive += 1
	if vspecial[i] == 1:
		specials_alive += 1
	if RunAnalytics.I: RunAnalytics.I.spawned(def)
	if RunAnalytics.I and (vspecial[i] == 1 or elite != null): RunAnalytics.I.spawned_marked(def, elite, vspecial[i] == 1, force_special)
	if def.archetype == "boss":
		boss_index = i
		atk_i[i] = 0
		atk_t[i] = 2.0
		var extra := pow(float(def.boss.get("hp_mult_per_stage", 1.6)), float(Run.stage))
		hp[i] = def.hp * extra * max(stage_mult, 1.0)
		# pass 72 (lane BOSS): pegged to the hero's DPS (the director holds boss_hp_scale around the spawn, else 1)
		hp[i] *= boss_hp_scale
		# pass 83 (lane SCALE): the seconds mode's floor, the hero's full DPS x the boss's seconds (0 = none)
		hp[i] = maxf(hp[i], boss_hp_target)
		max_hp[i] = hp[i]
		boss_spawned.emit(def)
		boss_hp_changed.emit(hp[i], max_hp[i])
		Audio.play(str(def.sfx.get("spawn", "en_boss_roar")))
	elif def.archetype == "elite":
		# the mini-boss: scales with the stage like a boss does, but no bar, no intro, no phase change
		var extra := pow(float(def.elite.get("hp_mult_per_stage", 1.8)), float(Run.stage))
		hp[i] = def.hp * extra * maxf(stage_mult, 1.0) * creature_hp_mult
		max_hp[i] = hp[i]
		Audio.play("en_elite_spawn", pos[i])
	elif elite != null:
		Audio.play("en_elite_spawn", pos[i])
	if def.brain == "artillery":
		_stand_off(i, def)
	elif def.brain == "sniper":
		# pass 73 (lane SNIPER): the Saiga Sniper comes in at its stand-off too, its first aim a moment after
		_sniper_spawned(i, def)
	# pass 73 (lane GROUND): it grows out of the ground (the map's spawn_rise; nothing without a director)
	_emerge_start(i, def)
	return i


## `n` of a creature spread round `center` (its art variant and overrides passed on, pass 53; its source's fixed numbers,
## pass 58). Returns how many came.
func spawn_pack(def_id: String, center: Vector3, n: int, elite: EliteModDef = null, variant := "", overrides := {}, src := {}) -> int:
	var def: EnemyDef = Registry.enemy_with(def_id, variant, overrides)
	if def == null:
		return 0
	var spread: float = clamp(0.6 * sqrt(float(n)) * def.radius * 2.0, 1.0, 6.0)
	var came := 0
	for k in range(n):
		var off := Vector3(_rng.randf_range(-spread, spread), 0, _rng.randf_range(-spread, spread))
		if spawn(def_id, _clamp_arena(center + off), elite, 1.0, 1.0, variant, overrides, src) >= 0:
			came += 1
	return came


## `count` of a creature on a ring of `ring_radius` round `center` (a swarm event, the King's minions); the art variant
## and overrides are passed on (pass 53), and the source's fixed numbers (pass 58). Pass 58 too: by the wall the ring
## keeps to the arc of it inside the arena instead of piling onto the wall beside the centre, and a spot on a rock's
## painting or in the lake steps aside (ring_spots). Returns how many came.
func spawn_ring(def_id: String, count: int, center: Vector3, ring_radius: float, variant := "", overrides := {}, src := {}) -> int:
	var came := 0
	var slide := 0.1 / (TAU / float(maxi(count, 1)))
	var mp: Node = game.get("map") if game else null
	for p: Vector3 in ring_spots(center, ring_radius, count, arena_radius - 2.0, _rng, 0.0, slide, 0.0, mp):
		if spawn(def_id, _clamp_arena(p), null, 1.0, 1.0, variant, overrides, src) >= 0:
			came += 1
	return came


## A boss (or whatever a boss event names): a boss or an Elite by its kind keeps its own rules whatever `src` says (pass 58).
func spawn_boss(def_id: String, at: Vector3, variant := "", overrides := {}, src := {}) -> int:
	return spawn(def_id, at, null, 1.0, 1.0, variant, overrides, src)


func _clamp_arena(p: Vector3) -> Vector3:
	var flat := Vector2(p.x, p.z)
	if flat.length() > arena_radius - 2.0:
		flat = flat.normalized() * (arena_radius - 2.0)
	return Vector3(flat.x, p.y, flat.y)


# ---------------------------------------------------------------- spawn spots by the wall (pass 58)

## A rock's painted foot is its collider over 0.62 (the props' colliders are 62% of the painting, pass 22); a ring point
## keeps this much more than that, a body's width, so nothing comes up inside a rock's painting.
const ROCK_FOOT := 1.0 / 0.62
const ROCK_PAD := 0.5


## The arc of a ring of `ring_r` round `center` that lies inside a disc of `lim` round the arena's middle (pass 58, the
## review of pass 57: a ring round a hero by the wall was clamped onto the wall right beside him): Vector2(the arc's
## middle angle, its half width) in the ring's own angle (a point at angle `a` is center + (cos a, 0, sin a) x ring_r);
## the half width is PI for a ring that fits whole, 0 when none of it fits (never, for a hero inside the arena).
static func ring_arc(center: Vector3, ring_r: float, lim: float) -> Vector2:
	var d := Vector2(center.x, center.z).length()
	if d < 0.001 or ring_r <= 0.0:
		return Vector2(0.0, PI)
	# |center + ring_r u(a)|^2 <= lim^2  <=>  cos(a - phi) <= c, phi the angle of the centre from the middle
	var c := (lim * lim - d * d - ring_r * ring_r) / (2.0 * ring_r * d)
	if c >= 1.0:
		return Vector2(0.0, PI)
	var phi := atan2(center.z, center.x)
	if c <= -1.0:
		return Vector2(phi + PI, 0.0)
	return Vector2(phi + PI, PI - acos(c))


## The map's lake for the spawn spots (pass 58 fix round) as Vector3(x, z, radius), the radius as in_water() reads it
## (Red Canyon: 1.02 x the lake's); Vector3.ZERO when the map names no lake (a map that only answers in_water(): the
## spots ask it point by point instead). Pass 80: the first of lakes_of.
static func lake_of(map: Node) -> Vector3:
	var all := lakes_of(map)
	return all[0] if not all.is_empty() else Vector3.ZERO


## Every lake the map names (pass 80, lane OASIS: two or three oases) as Vector3(x, z, radius), the radius as in_water()
## reads it (1.02 x the lake's); [] when it names none.
static func lakes_of(map: Node) -> Array:
	var out: Array = []
	for l: Dictionary in map_lakes(map):
		var c: Vector2 = l["center"]
		out.append(Vector3(c.x, c.y, float(l["radius"]) * 1.02))
	return out


## Every lake the map names (pass 80): its lakes() when it has them, else its one lake (lake_center, lake_radius and,
## when it tells it, water_disc), as [{center: Vector2, radius: float, disc: water_disc's dictionary or {}}]; [] when it
## names none.
static func map_lakes(map: Node) -> Array:
	var out: Array = []
	if map == null:
		return out
	if map.has_method("lakes"):
		for l in map.call("lakes"):
			if l is Dictionary and (l as Dictionary).get("center") is Vector2 and float((l as Dictionary).get("radius", 0.0)) > 0.0:
				out.append(l)
		return out
	if map.has_method("lake_center") and map.has_method("lake_radius"):
		var c = map.call("lake_center")
		var r := float(map.call("lake_radius"))
		if c is Vector2 and r > 0.0:
			var dv: Variant = map.call("water_disc") if map.has_method("water_disc") else null
			out.append({"center": c, "radius": r, "disc": dv if dv is Dictionary else {}})
	return out


## The arc of a circle of `ring_r` round `center` that lies inside a disc of `disc_r` round `disc_c` (x, z) (pass 58 fix
## round, the lake): Vector2(the arc's middle angle, its half width) in the ring's own angle (a point at angle `a` is
## center + (cos a, 0, sin a) x ring_r); the half width is below 0 when the circle misses the disc, PI when it lies in it
## whole.
static func ring_in_disc(center: Vector3, ring_r: float, disc_c: Vector2, disc_r: float) -> Vector2:
	var dx := disc_c.x - center.x
	var dz := disc_c.y - center.z
	var d := sqrt(dx * dx + dz * dz)
	if d < 0.001 or ring_r <= 0.0:
		return Vector2(0.0, PI if ring_r < disc_r else -1.0)
	var c := (ring_r * ring_r + d * d - disc_r * disc_r) / (2.0 * ring_r * d)
	if c >= 1.0:
		return Vector2(0.0, -1.0)
	var phi := atan2(dz, dx)
	if c <= -1.0:
		return Vector2(phi, PI)
	return Vector2(phi, acos(c))


## The yaws (0 = -Z, the hero's facing convention) that take a point `r` metres from `from` past the lake when the one at
## yaw `a` lies in it (pass 58 fix round, the review: in_front's few degrees of steps could not clear a lake 13 m across,
## which spans some 40 degrees 20 m off): the nearer edge of the lake's arc at that distance first, then the farther,
## each a body (ROCK_PAD) and a little more clear of the water; [] when the point is dry or the map names no lake.
static func lake_turns(map: Node, from: Vector3, a: float, r: float) -> Array:
	# pass 80: the lake whose arc holds the yaw (the lakes lie far apart: one at most)
	for lake: Vector3 in lakes_of(map):
		if lake.z <= 0.0:
			continue
		var wet := ring_in_disc(from, r, Vector2(lake.x, lake.y), lake.z + ROCK_PAD)
		if wet.y <= 0.0 or wet.y >= PI:
			continue
		# the yaw's angle on the ring: (-sin a, -cos a) = (cos t, sin t)
		var t := -a - PI * 0.5
		var off := wrapf(t - wet.x, -PI, PI)
		if absf(off) >= wet.y:
			continue
		var side := 1.0 if off >= 0.0 else -1.0
		var near_t := wet.x + side * (wet.y + LAKE_TURN_MARGIN)
		var far_t := wet.x - side * (wet.y + LAKE_TURN_MARGIN)
		return [-near_t - PI * 0.5, -far_t - PI * 0.5]
	return []


## How far past the lake's edge (radians) lake_turns puts a point.
const LAKE_TURN_MARGIN := 0.05


## Whether a creature may come up at `p` (pass 58, the ring patterns, which put creatures on the screen): outside every
## rock's painted foot (ROCK_FOOT x its collider, plus ROCK_PAD) and out of the map's water (`in_water`, Red Canyon's lake).
static func spawn_clear(map: Node, p: Vector3) -> bool:
	if map == null:
		return true
	var obs = map.get("obstacles")
	if obs is Array:
		for o in obs:
			if o is Vector3:
				var ov: Vector3 = o
				var keep := ov.z * ROCK_FOOT + ROCK_PAD
				if Vector2(p.x - ov.x, p.z - ov.y).length_squared() < keep * keep:
					return false
	if map.has_method("in_water") and map.in_water(p):
		return false
	return true


## `n` spots on a ring of `ring_r` round `center` (pass 57's rings; pass 58: one that would cross the arena's wall spreads
## its spots evenly over the arc of it inside `lim` instead of piling them onto the wall beside the hero, so every spot
## stays a ring's width from him and the count is kept). From the angle `turn` (a random one for the director's rings),
## each slid up to `slide` of the spacing round the ring and `jitter` metres in or out (drawn on `rng`), then stepped a
## little round the ring or in and out when it lands on a rock's painting or in the water (spawn_clear on `map`; it stays
## put when nothing near is clear: the steering walks it out). `lim` is the usable radius; a spot is never outside it.
## Pass 58 fix round (the review: by the oasis 11-14% of the spots stayed in the water, and a 105-ring there cost 8-10 ms):
## the lake is cut out of the ring like the wall, by the circle's arc inside the lake (ring_in_disc, a body and the jitter
## wider than the water), and the `n` spots are spread over the dry arcs that are left, each arc its share by its length;
## the rocks a spot must keep off are gathered once a ring (_clear_ctx) instead of every rock of the map for every try.
static func ring_spots(center: Vector3, ring_r: float, n: int, lim: float, rng: RandomNumberGenerator, turn: float, slide: float, jitter: float, map: Node = null) -> Array:
	var out: Array = []
	if n <= 0:
		return out
	var jit := maxf(jitter, 0.0)
	# the arc for the outermost a spot may stray, so a jittered spot still fits
	var arc := ring_arc(center, ring_r + jit, lim)
	var whole := arc.y >= PI - 0.0001
	var ctx: Dictionary = _clear_ctx(map, center, ring_r - jit - 2.5, ring_r + jit + 3.0) if map != null else {}
	if not ctx.is_empty():
		# pass 80: every lake's arc cut out (two or three oases)
		var wets: Array = []
		for lake: Vector3 in ctx["lakes"]:
			if lake.z > 0.0:
				var wet := ring_in_disc(center, ring_r, Vector2(lake.x, lake.y), lake.z + ROCK_PAD + jit)
				if wet.y > 0.0 and wet.y < PI:
					wets.append(wet)
		if not wets.is_empty():
			var dry := _dry_arcs_many(arc, whole, turn, wets)
			if not dry.is_empty():
				return _spots_on(dry, center, ring_r, n, lim, rng, slide, jitter, ctx)
	var step := TAU / float(n) if whole else 2.0 * arc.y / float(n)
	var start := turn if whole else arc.x - arc.y + step * 0.5
	var hw := maxf(arc.y - 0.02, 0.0)
	for k in range(n):
		var a := start + step * (float(k) + rng.randf_range(-slide, slide))
		if not whole:
			# the slide stays inside the arc (pass 67: pass 60's fix of _spots_on, here too: an end spot slid past a
			# wall-clipped arc was pulled in radially by _inside and landed a few mm under the ring's distance)
			a = clampf(a, arc.x - hw, arc.x + hw)
		var r := ring_r + rng.randf_range(-jitter, jitter)
		var p := center + Vector3(cos(a), 0, sin(a)) * r
		if not ctx.is_empty() and not _clear_in(ctx, p):
			p = _step_clear(ctx, center, a, r, step, lim, p)
		out.append(_inside(p, lim))
	return out


## What a ring's spots must keep clear of (pass 58 fix round), gathered once a ring: the rocks whose painted foot (ROCK_FOOT
## x the collider + ROCK_PAD) reaches the band `r_in`..`r_out` round `center` that a spot or its steps may land in, as
## Vector3(x, z, the foot's radius), the map's lake (lake_of) and the map (asked in_water() when it names no lake).
static func _clear_ctx(map: Node, center: Vector3, r_in: float, r_out: float) -> Dictionary:
	var near: Array = []
	var obs = map.get("obstacles") if map else null
	if obs is Array:
		for o in obs:
			if o is Vector3:
				var ov: Vector3 = o
				var keep := ov.z * ROCK_FOOT + ROCK_PAD
				var d := Vector2(ov.x - center.x, ov.y - center.z).length()
				if d - keep <= r_out and d + keep >= r_in:
					near.append(Vector3(ov.x, ov.y, keep))
	# (pass 80: "lakes" every lake, "lake" the first as before)
	var lakes := lakes_of(map)
	return {"obs": near, "lake": lakes[0] if not lakes.is_empty() else Vector3.ZERO, "lakes": lakes, "map": map}


## spawn_clear() on a ring's gathered rocks and lake (_clear_ctx).
static func _clear_in(ctx: Dictionary, p: Vector3) -> bool:
	for o: Vector3 in ctx["obs"]:
		if Vector2(p.x - o.x, p.z - o.y).length_squared() < o.z * o.z:
			return false
	var lakes: Array = ctx.get("lakes", [])
	if not lakes.is_empty():
		# pass 80: clear of every lake
		for lake: Vector3 in lakes:
			if Vector2(p.x - lake.x, p.z - lake.y).length_squared() < lake.z * lake.z:
				return false
		return true
	var map: Node = ctx["map"]
	return map == null or not map.has_method("in_water") or not map.in_water(p)


## The arcs of a ring left dry (pass 58 fix round): the arena's arc of it (`arc` from ring_arc; the whole circle from
## `turn` when `whole`) less the lake's arc `wet` (ring_in_disc), as Vector2(start, end) angles, end > start; a sliver too
## short for a body is dropped.
static func _dry_arcs(arc: Vector2, whole: bool, turn: float, wet: Vector2) -> Array:
	return _dry_arcs_many(arc, whole, turn, [wet])


## _dry_arcs less every wet arc in `wets` (pass 80: a ring can cross two lakes).
static func _dry_arcs_many(arc: Vector2, whole: bool, turn: float, wets: Array) -> Array:
	var a0 := turn if whole else arc.x - arc.y
	var a1 := a0 + (TAU if whole else 2.0 * arc.y)
	var ivs: Array = [Vector2(a0, a1)]
	for wet: Vector2 in wets:
		# the wet arc moved by whole turns to start in a0 .. a0 + TAU
		var w0 := a0 + fposmod(wet.x - wet.y - a0, TAU)
		var w1 := w0 + 2.0 * wet.y
		ivs = _cut_arc(ivs, w0, w1)
		if w1 > a0 + TAU:
			ivs = _cut_arc(ivs, a0, w1 - TAU)
	var out: Array = []
	for v: Vector2 in ivs:
		if v.y - v.x > 0.02:
			out.append(v)
	return out


## `ivs` (Vector2(start, end) angle spans) less the span c0..c1.
static func _cut_arc(ivs: Array, c0: float, c1: float) -> Array:
	var out: Array = []
	for v: Vector2 in ivs:
		if c1 <= v.x or c0 >= v.y:
			out.append(v)
			continue
		if c0 > v.x:
			out.append(Vector2(v.x, c0))
		if c1 < v.y:
			out.append(Vector2(c1, v.y))
	return out


## `n` ring spots over the dry arcs `dry` (pass 58 fix round): each arc takes its share of `n` by its length (the largest
## remainders round up), spread evenly along it half a spacing in from its ends, each slid up to `slide` of its spacing
## and `jitter` in or out, then stepped off a rock as ring_spots does.
static func _spots_on(dry: Array, center: Vector3, ring_r: float, n: int, lim: float, rng: RandomNumberGenerator, slide: float, jitter: float, ctx: Dictionary) -> Array:
	var total := 0.0
	for v: Vector2 in dry:
		total += v.y - v.x
	var counts: Array = []
	var rems: Array = []
	var given := 0
	for v: Vector2 in dry:
		var share := float(n) * (v.y - v.x) / total
		counts.append(int(floor(share)))
		rems.append(share - floor(share))
		given += int(floor(share))
	while given < n:
		var best := 0
		for k in range(rems.size()):
			if float(rems[k]) > float(rems[best]):
				best = k
		counts[best] = int(counts[best]) + 1
		rems[best] = -1.0
		given += 1
	var out: Array = []
	for k in range(dry.size()):
		var v: Vector2 = dry[k]
		var m := int(counts[k])
		if m <= 0:
			continue
		var step := (v.y - v.x) / float(m)
		for q in range(m):
			# the slide stays inside the arc (pass 60: an end spot slid past a wall-clipped arc was pulled in radially by
			# _inside and landed under the ring's distance to the wall once in a few runs)
			var a := clampf(v.x + step * (float(q) + 0.5 + rng.randf_range(-slide, slide)), v.x + 0.02, v.y - 0.02)
			var r := ring_r + rng.randf_range(-jitter, jitter)
			var p := center + Vector3(cos(a), 0, sin(a)) * r
			if not _clear_in(ctx, p):
				p = _step_clear(ctx, center, a, r, step, lim, p)
			out.append(_inside(p, lim))
	return out


## Ring spot steps (pass 58): metres out (+) or in (-) from the ring, and shares of the spacing round it (never past half
## a spacing, so the spots keep their order); the smallest moves first, and never more than 2.5 m nearer the centre.
const RING_STEPS_OUT := [0.0, 1.0, -1.0, 2.0, -2.0, 3.0, -2.5]
const RING_STEPS_ROUND := [0.0, 0.2, -0.2, 0.4, -0.4]


## A ring spot at angle `a`, `r` from `center`, stepped off a rock's painting or the water (pass 58): the first clear spot
## (_clear_in on the ring's gathered rocks and lake, `ctx`) inside `lim` among RING_STEPS_OUT x RING_STEPS_ROUND (`step`
## the spacing in radians), else `fallback` (the steering walks a creature out of a rock, and one in the lake wades).
static func _step_clear(ctx: Dictionary, center: Vector3, a: float, r: float, step: float, lim: float, fallback: Vector3) -> Vector3:
	for d_out: float in RING_STEPS_OUT:
		for d_round: float in RING_STEPS_ROUND:
			if d_out == 0.0 and d_round == 0.0:
				continue
			var aa := a + step * d_round
			var q := center + Vector3(cos(aa), 0, sin(aa)) * maxf(r + d_out, 0.5)
			if Vector2(q.x, q.z).length() <= lim and _clear_in(ctx, q):
				return q
	return fallback


## The point `r` metres from `from` towards the yaw `a` (0 = -Z, the hero's facing convention), turned round the least
## way that keeps it inside a disc of `lim` round the arena's middle (pass 58, the review of pass 57: a spawn towards the
## wall was clamped onto the wall, beside a hero standing by it; now it keeps its distance from him). Each turn of 5
## degrees is tried both ways, the one deeper inside first; straight towards the middle fits whenever r < lim.
static func point_inside(from: Vector3, a: float, r: float, lim: float) -> Vector3:
	var p := from + Vector3(-sin(a), 0, -cos(a)) * r
	if Vector2(p.x, p.z).length() <= lim:
		return p
	for k in range(1, 37):
		var da := deg_to_rad(5.0 * float(k))
		var p1 := from + Vector3(-sin(a + da), 0, -cos(a + da)) * r
		var p2 := from + Vector3(-sin(a - da), 0, -cos(a - da)) * r
		var l1 := Vector2(p1.x, p1.z).length()
		var l2 := Vector2(p2.x, p2.z).length()
		if l1 <= lim or l2 <= lim:
			return p1 if (l1 <= lim and (l2 > lim or l1 <= l2)) else p2
	return _inside(p, lim)


## `p` pulled in onto a disc of `lim` round the arena's middle when it lies outside it.
static func _inside(p: Vector3, lim: float) -> Vector3:
	var flat := Vector2(p.x, p.z)
	if flat.length() > lim:
		flat = flat.normalized() * lim
	return Vector3(flat.x, p.y, flat.y)


## Everything on the field dies (`reward`: as a kill, with its drops) or simply goes. An undying training dummy (pass 48)
## never dies, so a kill leaves it standing; going takes it like anything else.
func kill_all(reward: bool = false) -> void:
	for i in range(MAX):
		if alive[i] == 1 and state[i] != STATE_DYING:
			if reward:
				if undying[i] == 0:
					_die(i, "")
			else:
				_free(i)
	if not reward:
		cleared.emit()


## Whether creature `i` is a training dummy (pass 48: the `dummy` brain, the debug arena's): it drops nothing and counts
## for no quest, and it never bites unless it is set to melee (pass 49, set_dummy_mode).
func is_dummy(i: int) -> bool:
	return i >= 0 and i < MAX and alive[i] == 1 and _t_dummy[type_idx[i]] == 1


## A training dummy's behaviour (pass 49, Game sets it as the dummy stands and when the arena's settings change): one of
## DUMMY_STAND, DUMMY_PATROL, DUMMY_MELEE, DUMMY_RANGED; `roam`, whether it patrols while it has nothing to hit; `dir`, the
## way its beat sets off (+1 east, -1 west; 0 keeps the way it has). A change of behaviour drops a spit it was winding up.
func set_dummy_mode(i: int, mode: int, roam: bool = false, dir: float = 0.0) -> void:
	if i < 0 or i >= MAX or alive[i] == 0:
		return
	if dummy_mode[i] != mode and state[i] == STATE_WINDUP:
		state[i] = STATE_MOVE
		timer[i] = 0.0
	dummy_mode[i] = clampi(mode, DUMMY_STAND, DUMMY_RANGED)
	dummy_roam[i] = 1 if roam else 0
	if dir != 0.0:
		patrol_dir[i] = signf(dir)


# ---------------------------------------------------------------- damage

## `flags` (pass 48): HIT_MINI makes the hit a mini crit. What the run records for the weapon (Run.add_damage: the
## Results screen, the run recorder, life steal) is the damage the creature still had in it, never the overkill; the
## floating number shows the whole hit.
func damage(i: int, amount: float, weapon_id: String = "", kb_dir: Vector3 = Vector3.ZERO, kb_force: float = 0.0, green: bool = false, hot: bool = false, flags: int = 0) -> bool:
	last_crit = false
	if i < 0 or i >= MAX or alive[i] == 0 or state[i] == STATE_DYING or hidden[i] == 1 or held[i] == 1:
		return false
	var dealt: float = amount * (1.0 - dr[i])
	# Big Game Hunter (pass 47): more on a boss, an Elite or an elite-modded creature, from all the hero sends (the
	# revive's flat tenth and a dead rocketeer's loose rocket are not his to aim)
	_pstats()
	if _elite_dmg > 0.0 and weapon_id != "revive" and weapon_id != "loose_rocket" and is_big_game(i):
		dealt *= 1.0 + _elite_dmg
	# Cauterize: a marked creature takes more from everything while the mark lasts
	if mark_t[i] > 0.0:
		dealt *= mark_mult[i]
	# Sunburn (pass 54, Solenne's perk): a burning or poisoned creature takes `bonus` more from everything she sends (the
	# revive's flat tenth and a loose rocket are not hers to aim)
	if _sunburn > 0.0 and weapon_id != "" and weapon_id != "revive" and weapon_id != "loose_rocket" and (is_burning(i) or is_poisoned(i)):
		dealt *= 1.0 + _sunburn
	# a weapon's own statuses: the mark, the twister, the pull (Wide Orbit, Lasso)
	if weapon_id != "" and not green and not hot:
		var wi := Run.weapon_instance(weapon_id)
		if wi:
			var mk: float = wi.stat("mark", 0.0)
			if mk > 0.0:
				# three seconds, stretched by Ducktape (pass 47)
				mark_t[i] = 3.0 * _debuff_mult
				mark_mult[i] = 1.0 + mk
			var sp: float = wi.stat("spin", 0.0)
			if sp > 0.0 and spin_t[i] <= 0.0 and i != boss_index:
				twist(i, sp, player.global_position if player else pos[i])
			var pl: float = wi.stat("pull", 0.0)
			if pl > 0.0 and player:
				var tow := player.global_position - pos[i]
				tow.y = 0.0
				if tow.length_squared() > 0.01:
					# a resisting creature is towed by its share (pass 67, knockback_resist)
					kb[i] += tow.normalized() * pl * _t_kbt[type_idx[i]]
	# Deadeye: a weapon hit (never a poison or fire tick) can crit for crit_damage times the damage
	var crit := false
	if weapon_id != "" and not green and not hot:
		# Counterpunch (pass 69): the attack after an evade hits double (Run.counterpunch_mult, 1 otherwise)
		dealt *= Run.counterpunch_mult(weapon_id)
		var cc: float = Run.player_sheet.get_stat("crit_chance", 0.0)
		# Trick Shot (pass 69): the weapon's own proc_mult on its crit, Vulture and Cold Snap chances
		var tpm: float = Run.trick_proc_mult(weapon_id)
		cc *= tpm
		# HIT_CRIT (pass 62): a forced crit needs no roll
		if (flags & HIT_CRIT) != 0 or (cc > 0.0 and randf() < cc):
			dealt *= Run.player_sheet.get_stat("crit_damage", 2.0)
			crit = true
			# Vulture (pass 47c): a crit may heal the hero a little
			if _crit_heal > 0.0 and randf() < _crit_heal * tpm and game and game.player and not game.player.dead:
				game.player.heal(game.player.max_hp * CRIT_HEAL_FRAC, "Vulture")
		# Cold Snap (pass 47c): a weapon hit may freeze the creature for a second, never a boss
		if _freeze_chance > 0.0 and i != boss_index and randf() < _freeze_chance * tpm:
			freeze(i, FREEZE_SECONDS)
	last_crit = crit
	# a mini crit (pass 48, HIT_MINI): half a crit's extra damage, when no full crit rolled
	var mini := false
	if not crit and (flags & HIT_MINI) != 0:
		dealt *= 1.0 + (Run.player_sheet.get_stat("crit_damage", 2.0) - 1.0) * 0.5
		mini = true
	var hp_before: float = hp[i]
	hp[i] -= dealt
	# the floating number over it (pass 46): one call, nothing when the HUD has no numbers up (tools, tests, the setting off)
	if DamageNumbers.I: DamageNumbers.I.add(i, pos[i] + Vector3(0, size[i] * 1.2 + lift_h[i], 0), dealt, crit, green, hot, mini)
	flash[i] = 1.0
	flash_green[i] = 1 if green else 0
	flash_hot[i] = 1 if hot else 0
	squash[i] = 0.55 if crit else (0.65 if mini else (0.9 if (green or hot) else 0.75))
	if crit and game:
		game.fx.burst(pos[i] + Vector3(0, size[i] * 0.7, 0), Color(1.0, 0.9, 0.35), 0.6)
	if weapon_id != "":
		# recorded up to what it had left (pass 48: a 500 hit on 20 HP is 20 dealt; a zero ring records nothing)
		var rec := minf(dealt, maxf(hp_before, 0.0))
		if rec > 0.0:
			Run.add_damage(weapon_id, rec)
	# Guillotine: a weapon hit finishes anything but a boss that is already below the threshold
	if hp[i] > 0.0 and weapon_id != "" and i != boss_index and str((types[type_idx[i]]["def"] as EnemyDef).archetype) != "boss":
		var ex: float = Run.player_sheet.get_stat("execute_frac", 0.0)
		if ex > 0.0 and hp[i] <= max_hp[i] * ex:
			hp[i] = 0.0
			if game:
				game.fx.burst(pos[i] + Vector3(0, size[i] * 0.5, 0), Color(0.9, 0.15, 0.2), 0.9)
	if kb_force > 0.0:
		# push away along the hit direction; heavy creatures (size in metres) budge less, a resisting one by its share
		# (pass 67: EnemyDef.knockback_resist, the Hammer Giant a third), the boss barely (its 0.15 on top of both)
		var mass: float = maxf(size[i], 0.8)
		var push: float = kb_force / mass * _t_kbt[type_idx[i]] * (0.15 if i == boss_index else 1.0)
		var d := Vector3(kb_dir.x, 0, kb_dir.z)
		if d.length_squared() < 0.0001:
			d = pos[i] - player.global_position if player else Vector3.FORWARD
		kb[i] += Vector3(d.x, 0, d.z).normalized() * push * _hero_push(weapon_id)
		# Bucking Bronco (pass 70): the knock may throw it up and away instead
		_bronco_kick(i, d, push, weapon_id)
	if i == boss_index:
		boss_hp_changed.emit(max(hp[i], 0.0), max_hp[i])
	var def: EnemyDef = types[type_idx[i]]["def"]
	if hp[i] <= 0.0 and undying[i] == 1:
		# a training dummy (pass 48): it never falls; the hit showed, its statuses stay, and it is whole again
		hp[i] = max_hp[i]
		Audio.play(str(def.sfx.get("hit", "")), pos[i])
		return false
	if hp[i] <= 0.0:
		var overflow: float = -hp[i]
		# pass 82 (lane FEEL): the killing hit's way and weight, for the body's throw (_corpse_begin)
		_corpse_note_kill(i, kb_dir, dealt, crit, mini)
		_die(i, weapon_id)
		_corpse_kill_i = -1
		# Overkill: the damage past the kill splashes onto whatever stood next to it (once, no chains)
		var ok: float = Run.player_sheet.get_stat("overkill", 0.0)
		if ok > 0.0 and overflow > 0.5 and weapon_id != "" and not _splashing:
			_splashing = true
			damage_radius(pos[i], 2.5, overflow * ok, weapon_id, 3.0)
			_splashing = false
			if game:
				game.fx.burst(pos[i] + Vector3(0, 0.5, 0), Color(1.0, 0.6, 0.25), 1.6)
		# the death and the overkill splash may have landed hits of their own since
		last_crit = crit
		return true
	# pass 73 (lane SNIPER): flee on hit, and a hit Vulture Raider's rockets shake and slow
	_on_hit_reactions(i, def, dealt, green or hot)
	Audio.play(str(def.sfx.get("hit", "")), pos[i])
	return false


## Poison from one item: a new source, or the same source's timer reset (stacks and damage take the higher value).
## `scaled` (pass 47): the duration is stretched by Ducktape's debuff_duration; false for a clock already stretched
## (Blight handing on what is left of a poison).
func poison(i: int, weapon_id: String, dmg_per_tick: float, stacks: int, duration: float, scaled: bool = true) -> void:
	if i < 0 or i >= MAX or alive[i] == 0 or state[i] == STATE_DYING:
		return
	# the item's own seconds (pass 70: a Prairie Fire jump starts from them)
	var own := duration
	if scaled:
		# Ducktape stretches it, and Lingering Light (pass 54, Solenne's hidden perk)
		duration *= debuff_mult() * _ll_longer
	var src: Dictionary = poison_src[i]
	var fresh := src.is_empty()
	if src.has(weapon_id):
		var e: Dictionary = src[weapon_id]
		e["t"] = duration
		e["stacks"] = maxi(int(e["stacks"]), stacks)
		e["dmg"] = maxf(float(e["dmg"]), dmg_per_tick)
	else:
		src[weapon_id] = {"stacks": stacks, "dmg": dmg_per_tick, "t": duration, "dur": own}
	if fresh:
		poison_tick[i] = POISON_TICK


## A slow: the stronger of the two when one is already on. A frac of 1 is a pin (the Spear). `scaled` (pass 47): the
## seconds are stretched by Ducktape's debuff_duration; a hero's perk (Serenade, Trail Dust) passes false.
func slow(i: int, frac: float, seconds: float, scaled: bool = true) -> void:
	if i < 0 or i >= MAX or alive[i] == 0:
		return
	if scaled:
		seconds *= debuff_mult()
	slow_f[i] = maxf(slow_f[i] if slow_t[i] > 0.0 else 0.0, frac)
	slow_t[i] = maxf(slow_t[i], seconds)


## A slow of moves AND attacks (pass 48: Curare, the Tarantula Hawk): its walk through slow(), and its attack clocks (a
## bite's and a shot's cooldown, a wind-up, a boss's script) run at 1 - frac while it lasts (attack_clock). A boss takes
## half the frac. `scaled` stretches the seconds by Ducktape's debuff_duration, as slow() does; the stronger of two holds.
func hamper(i: int, frac: float, seconds: float, scaled: bool = true) -> void:
	if i < 0 or i >= MAX or alive[i] == 0 or state[i] == STATE_DYING:
		return
	var f := clampf(frac, 0.0, 1.0)
	if i == boss_index or (types[type_idx[i]]["def"] as EnemyDef).archetype == "boss":
		f *= 0.5
	if scaled:
		seconds *= debuff_mult()
	slow(i, f, seconds, false)
	hamper_f[i] = maxf(hamper_f[i] if hamper_t[i] > 0.0 else 0.0, f)
	hamper_t[i] = maxf(hamper_t[i], seconds)


## How fast creature `i`'s attack clocks run right now (pass 48): 1, or 1 - its hamper while one lasts.
func attack_clock(i: int) -> float:
	return 1.0 - hamper_f[i] if hamper_t[i] > 0.0 else 1.0


## Holds `col` as creature `i`'s tint for `seconds` (pass 48: Curare's dark green, a Tarantula Hawk's purple prey), over a
## burn's or a poison's tint; a frozen creature's ice blue still wins. The colour's alpha is its strength (the shader mixes
## 65% of it). A new call replaces the old tint and its clock.
func set_status_tint(i: int, col: Color, seconds: float) -> void:
	if i < 0 or i >= MAX or alive[i] == 0:
		return
	status_tint[i] = col
	status_t[i] = maxf(seconds, 0.0)


## The clock the creatures' shots fly on (pass 48): High Noon's time_scale times the pace knob, so a shot crosses the same
## ground as before in 1/pace the time and the slower hero can still step out of its way (ProjectileManager's hostile
## shots and the rocketeer's rocket, the golem's boulder). Pass 60: the pace carries creature_speed_mult, so every
## hostile shot flies at the creatures' multiple too.
func hostile_clock() -> float:
	return time_scale * pace


## Cold Snap (pass 47c, Garry: "N% chance that enemies will freeze on hit ... only 1 second ... coloured blue ... a vfx"):
## the creature stops dead, bites nobody, shows ice blue, and a puff of frost bursts off it. Pass 70 (lane LINES, Slow
## Burn: "every status the game applies"): `scaled` stretches the seconds by debuff_duration (Ducktape, Slow Burn), as
## slow() does.
func freeze(i: int, seconds: float, scaled: bool = true) -> void:
	if i < 0 or i >= MAX or alive[i] == 0 or state[i] == STATE_DYING:
		return
	if scaled:
		seconds *= debuff_mult()
	var fresh := freeze_t[i] <= 0.0
	freeze_t[i] = maxf(freeze_t[i], seconds)
	slow(i, 1.0, seconds, false)
	if fresh and game and game.get("fx"):
		var at := pos[i] + Vector3(0, size[i] * 0.6, 0)
		game.fx.burst(at, Color(0.7, 0.9, 1.0), 0.8)
		for k in 6:
			var a := TAU * float(k) / 6.0 + randf() * 0.4
			game.fx.mote(at, Vector3(cos(a) * 2.2, 1.6 + randf(), sin(a) * 2.2), 0.45, 0.16, Color(0.8, 0.95, 1.0, 0.9))


## A stun (pass 53, for the Spear lane): creature `i` stops walking and attacking for `seconds`, like a freeze without the
## ice: no bites, no wind-up, charge or scripted attack goes on (one under way is dropped: its red mark on the sand would
## outlive it), a pale yellow tint (set_status_tint) and a few yellow motes. Never a boss, an Elite archetype or a
## creature wearing an elite modifier (nothing happens); a longer stun on one already stunned holds the longer time.
## Pass 70 (lane LINES, Slow Burn: "every status the game applies"): `scaled` stretches the seconds by debuff_duration
## (Ducktape, Slow Burn), as slow() does; it never was before.
func stun(i: int, seconds: float, scaled: bool = true) -> void:
	if i < 0 or i >= MAX or alive[i] == 0 or state[i] == STATE_DYING or seconds <= 0.0:
		return
	if i == boss_index or elite_idx[i] >= 0 or _t_big[type_idx[i]] == 1:
		return
	if scaled:
		seconds *= debuff_mult()
	var def: EnemyDef = types[type_idx[i]]["def"]
	var fresh := stun_t[i] <= 0.0
	stun_t[i] = maxf(stun_t[i], seconds)
	vel[i] = Vector3.ZERO
	match state[i]:
		STATE_WINDUP:
			# the shot or charge it was winding up never comes; a beat before it tries again
			state[i] = STATE_MOVE
			cooldown[i] = maxf(cooldown[i], 1.0)
		STATE_CHARGE:
			state[i] = STATE_MOVE
			cooldown[i] = float(def.charge.get("cooldown", 4.0)) if def.brain != "boss" else cooldown[i]
			_skid(i)
		STATE_ATTACK:
			# a scripted attack (the Hammer Giant's slam) is interrupted; its script goes on after the stun
			state[i] = STATE_MOVE
			atk_t[i] = maxf(atk_t[i], 1.0)
	set_status_tint(i, STUN_TINT, stun_t[i])
	if fresh and game and game.get("fx"):
		var fx = game.fx
		var at := pos[i] + Vector3(0, size[i] * 0.8, 0)
		if fx.has_method("mote"):
			for k in 5:
				var a := TAU * float(k) / 5.0 + randf() * 0.5
				fx.mote(at, Vector3(cos(a) * 1.4, 1.2 + randf() * 0.8, sin(a) * 1.4), 0.4, 0.14, Color(1.0, 0.92, 0.45, 0.9))
		elif fx.has_method("burst"):
			fx.burst(at, Color(1.0, 0.92, 0.45), 0.6)


## Whether creature `i` is stunned right now (pass 53).
func is_stunned(i: int) -> bool:
	return i >= 0 and i < MAX and alive[i] == 1 and stun_t[i] > 0.0


func slow_radius(center: Vector3, r: float, frac: float, seconds: float, scaled: bool = true) -> void:
	if scaled:
		seconds *= debuff_mult()
	for i in indices_in_radius(center, r):
		slow(i, frac, seconds, false)


## The bees' old twister (a Hornet Nest path until pass 30): the creature is lifted for `seconds`, cannot walk or bite, and drifts towards `to`.
func twist(i: int, seconds: float, to: Vector3) -> void:
	if i < 0 or i >= MAX or alive[i] == 0 or state[i] == STATE_DYING:
		return
	spin_t[i] = seconds
	spin_to[i] = to
	if lift_t[i] <= 0.0:
		lift_mode[i] = 0
		lift_t[i] = seconds
		lift_d[i] = seconds
		lift_a[i] = atan2(pos[i].z - to.z, pos[i].x - to.x)
	kb[i] = Vector3.ZERO
	if game:
		game.fx_burst(pos[i] + Vector3(0, size[i] * 0.4, 0), Color(0.98, 0.9, 0.6), 1.2)


## A bounce (pass 46): creature `i` goes `height` metres straight up and comes down on the same spot after `seconds`,
## with no spin, no turn and no harm, landing with `knock` as its shove (none by default). Never a boss, an Elite (by
## its archetype or a modifier), a held, buried or dying creature, or one already in the air (lift_t > 0). Returns
## whether it went up.
func bounce(i: int, height: float, seconds: float, knock: Vector3 = Vector3.ZERO) -> bool:
	if i < 0 or i >= MAX or alive[i] == 0 or state[i] == STATE_DYING or hidden[i] == 1 or held[i] == 1:
		return false
	if i == boss_index or elite_idx[i] >= 0 or lift_t[i] > 0.0 or seconds <= 0.0:
		return false
	var def: EnemyDef = types[type_idx[i]]["def"]
	if def.archetype == "elite" or def.archetype == "boss":
		return false
	lift_mode[i] = 1
	lift_t[i] = seconds
	lift_d[i] = seconds
	lift_peak[i] = maxf(height, 0.0)
	lift_knock[i] = Vector3(knock.x, 0.0, knock.z)
	kb[i] = Vector3.ZERO
	vel[i] = Vector3.ZERO
	return true


# ---------------------------------------------------------------- pass 69 (lane BB): Alley-Oop's launch
## Alley-Oop (pass 69, a weapon's `params.launch {chance, height, air_time, fall_damage_frac, sfx}`; Slam Dunk's `final`
## raises it): a weapon hit that does not kill rolls `chance` (ProjectileManager calls try_launch). A plain creature is
## thrown straight up (no drift, no turn), cannot move, bite or attack while it is up (a stun: the physics tick runs
## _tick_launch in place of its brain and its touch), and lands after `air_time` taking `fall_damage_frac` x that hit's
## damage through damage() (so every damage increase scales it, and it counts for kills, XP and the rest like any hit of
## that weapon). The boss, an Elite or an elite-modded creature (is_big_game) that rolls it takes the fall at once and
## stays on its feet. One already in the air (a launch, a bounce, a tornado), held, buried, rising out of the sand, roped
## to the hero or still in the spawn beam is not thrown; its roll does nothing. A launch rides lift_mode 1 (a bounce's:
## the tornado's swirl and grab, the Gravity Gun and the crowd's shove all leave it alone) with its own entry in
## _launched.
const LAUNCH_RISE := 0.3        # the share of the flight going up (fast, easing out)
const LAUNCH_HANG := 0.5        # the share by which the hang at the top ends and the drop begins (easing in)
const LAUNCH_FLOAT := 0.04      # the hang's little extra lift, a share of the height
const LAUNCH_DEAD_FALL := 22.0  # m/s² a body killed up there falls at, to land where it was
const LAUNCH_SFX := "w_grav_land"
## The creatures up in the air from a launch: index -> {"serial", "dmg", "wid", "sfx"} (the slot's spawn serial tells a
## stale entry from the next creature put in the slot).
var _launched: Dictionary = {}
## Diagnostics and tests: creatures thrown up, falls taken at once by big game, landings.
var launches := 0
var launch_instant := 0
var landings := 0


## The roll (pass 69): 0 nothing, 1 thrown up, 2 big game took the fall at once. `roll` (tests) replaces the random draw.
func try_launch(i: int, hit_damage: float, weapon_id: String, cfg: Dictionary, roll: float = -1.0) -> int:
	if i < 0 or i >= MAX or alive[i] == 0 or state[i] == STATE_DYING or hidden[i] == 1 or held[i] == 1:
		return 0
	var chance := clampf(float(cfg.get("chance", 0.15)), 0.0, 1.0)
	var r: float = roll if roll >= 0.0 else _rng.randf()
	if r >= chance:
		return 0
	var fall := maxf(hit_damage, 0.0) * maxf(float(cfg.get("fall_damage_frac", 1.0)), 0.0)
	if is_big_game(i):
		# the boss and the Elites (Garry: "just get the extra damage as if they had fallen, but no throw up"): at once,
		# with a thud at its feet
		launch_instant += 1
		_launch_thud(i, str(cfg.get("sfx", LAUNCH_SFX)), 0.6, false)
		if fall > 0.0:
			damage(i, fall, weapon_id)
		return 2
	if not launch(i, float(cfg.get("height", 3.5)), float(cfg.get("air_time", 0.9)), fall, weapon_id, str(cfg.get("sfx", LAUNCH_SFX))):
		return 0
	return 1


## Throws creature `i` straight up (pass 69): `height` metres at the top, down after `seconds`, `fall` damage from
## `weapon_id` on landing. False when it cannot go up (can_launch). A wind-up, a charge or a scripted attack it was in is
## dropped the way a stun drops it.
func launch(i: int, height: float, seconds: float, fall: float, weapon_id: String, sfx: String = LAUNCH_SFX) -> bool:
	if not can_launch(i) or seconds <= 0.0:
		return false
	var def: EnemyDef = types[type_idx[i]]["def"]
	match state[i]:
		STATE_WINDUP:
			state[i] = STATE_MOVE
			cooldown[i] = maxf(cooldown[i], 1.0)
		STATE_CHARGE:
			state[i] = STATE_MOVE
			cooldown[i] = float(def.charge.get("cooldown", 4.0))
		STATE_ATTACK:
			state[i] = STATE_MOVE
			atk_t[i] = maxf(atk_t[i], 1.0)
	lift_mode[i] = 1
	lift_t[i] = seconds
	lift_d[i] = seconds
	lift_peak[i] = maxf(height, 0.0)
	lift_knock[i] = Vector3.ZERO
	lift_h[i] = 0.0
	kb[i] = Vector3.ZERO
	vel[i] = Vector3.ZERO
	_launched[i] = {"serial": serial[i], "dmg": fall, "wid": weapon_id, "sfx": sfx}
	launches += 1
	squash[i] = 1.25
	var fx = game.get("fx") if game != null else null
	if fx != null and fx.has_method("sand"):
		fx.sand(pos[i], 0.35)
	return true


## Whether creature `i` may be thrown up now (pass 69): alive, not big game, on its feet and free.
func can_launch(i: int) -> bool:
	if i < 0 or i >= MAX or alive[i] == 0 or state[i] == STATE_DYING or state[i] == STATE_SPAWN:
		return false
	if hidden[i] == 1 or held[i] == 1 or lift_t[i] > 0.0 or rise_t[i] < 1.0 or i == tethered_i:
		return false
	return not is_big_game(i)


## Whether creature `i` is up in the air from a launch now (tests, other systems).
func is_launched(i: int) -> bool:
	return i >= 0 and i < MAX and alive[i] == 1 and lift_t[i] > 0.0 and _launch_of(i)


## Whether slot `i` holds a live launch entry (its creature's own, not a stale one).
func _launch_of(i: int) -> bool:
	var e = _launched.get(i)
	return e is Dictionary and int((e as Dictionary).get("serial", -1)) == serial[i]


## A launch's height at `f` (0 thrown .. 1 landing) as a share of its top: up fast (easing out), a hang with a little
## float, then the drop (easing in, gathering speed).
static func launch_curve(f: float) -> float:
	f = clampf(f, 0.0, 1.0)
	if f < LAUNCH_RISE:
		var u := 1.0 - f / LAUNCH_RISE
		return 1.0 - u * u
	if f < LAUNCH_HANG:
		return 1.0 + LAUNCH_FLOAT * sin(PI * (f - LAUNCH_RISE) / (LAUNCH_HANG - LAUNCH_RISE))
	var d := (f - LAUNCH_HANG) / (1.0 - LAUNCH_HANG)
	return 1.0 - d * d


## One tick of a launched creature (the physics tick calls it in place of everything else: no steering, no bite, no
## attack). Its burns and poisons keep ticking, its legs flail. On landing: squashed, a puff of dust, the thud, and the
## fall's damage through damage().
func _tick_launch(i: int, delta: float) -> void:
	lift_t[i] -= delta
	var f := 1.0 - clampf(lift_t[i] / maxf(lift_d[i], 0.01), 0.0, 1.0)
	lift_h[i] = launch_curve(f) * lift_peak[i]
	vel[i] = Vector3.ZERO
	kb[i] = Vector3.ZERO
	# Bucking Bronco's throw (pass 70) flies away as it goes up
	_bronco_drift(i, delta)
	anim_t[i] += delta * 14.0
	flash[i] = maxf(flash[i] - delta * 6.0, 0.0)
	squash[i] = lerpf(squash[i], 1.0, clampf(delta * 8.0, 0.0, 1.0))
	_tick_poison(i, delta)
	if alive[i] == 0 or state[i] == STATE_DYING:
		return
	_tick_fire(i, delta)
	if alive[i] == 0 or state[i] == STATE_DYING or lift_t[i] > 0.0:
		return
	var e: Dictionary = _launched.get(i, {})
	_launched.erase(i)
	lift_t[i] = 0.0
	lift_h[i] = 0.0
	lift_mode[i] = 0
	lift_cd[i] = 0.3
	squash[i] = 0.55
	landings += 1
	_launch_thud(i, str(e.get("sfx", LAUNCH_SFX)), 1.0, true)
	var fall := float(e.get("dmg", 0.0))
	if fall > 0.0:
		damage(i, fall, str(e.get("wid", "")))


## A launched creature killed up there (pass 69; the dying tick calls this while its death plays): the body falls to the
## sand where it was and lands with the thud.
func _drop_launched_body(i: int, delta: float) -> void:
	var e: Dictionary = _launched[i]
	var v: float = float(e.get("fall_v", 0.0)) + LAUNCH_DEAD_FALL * delta
	e["fall_v"] = v
	lift_h[i] = maxf(lift_h[i] - v * delta, 0.0)
	if lift_h[i] <= 0.0:
		_launch_thud(i, str(e.get("sfx", LAUNCH_SFX)), 0.8, true)
		_launched.erase(i)
		lift_t[i] = 0.0
		lift_mode[i] = 0


## A landing (pass 69): a spray of sand at its feet (`big` for a body coming down, a little more for a bigger creature;
## pass 69's captures: the burrow's full pop_dust buried a crowd that a quarter of the hits throws up) and the thud.
func _launch_thud(i: int, sfx: String, k: float, big: bool) -> void:
	var fx = game.get("fx") if game != null else null
	if fx != null and fx.has_method("sand"):
		fx.sand(pos[i], (clampf(size[i] * 0.5, 0.55, 1.0) if big else 0.5) * k)
	if sfx != "":
		Audio.play(sfx, pos[i])


# ---------------------------------------------------------------- pass 70 (lane LINES): Bucking Bronco, Prairie Fire
## Bucking Bronco (pass 70, Mule Kick's evolution; Garry: "the knockback gets a chance to launch the enemy up and away
## instead of just knocking them back. It's mostly a visual effect, so the chance can be high"): a hit from the hero's
## side (a weapon id, never the revive or a dead rocketeer's loose rocket) that knocks a creature back (damage() with a
## kb_force) and leaves it alive rolls the hero's `bronco_chance`. A creature that can go up (can_launch: never the boss,
## an Elite or an elite-modded one, which only take the knock; never one already in the air) is thrown BRONCO_HEIGHT m up
## and away along the knock instead of the shove: BRONCO_AWAY_BASE + BRONCO_AWAY_PER x the push (m/s), between
## BRONCO_AWAY_MIN and BRONCO_AWAY_MAX m, over BRONCO_AIR s. It cannot walk, bite or attack up there (the launch's stun)
## and lands in a puff of sand with the launch's thud; no fall damage. The roll is the manager's own dice.
const BRONCO_HEIGHT := 2.8
const BRONCO_AIR := 0.8
const BRONCO_AWAY_BASE := 1.5
const BRONCO_AWAY_PER := 0.3
const BRONCO_AWAY_MIN := 2.5
const BRONCO_AWAY_MAX := 6.0
var _bronco := 0.0
## Creatures Bucking Bronco has thrown (tests, the capture).
var bronco_launches := 0
## Prairie Fire (pass 70, Slow Burn's evolution): with the hero's `debuff_jump` above 0, a burn or a poison that runs out
## on a creature (_tick_fire, _tick_poison), or whose creature dies with it on (_die), jumps to the nearest other creature
## within PRAIRIE_R m that does not carry that source yet, at the item's full seconds (stretched once more by
## debuff_duration, as a new one is), while the source has jumped fewer than `debuff_jump` times (its "hops"). A fire
## never jumps onto the boss (as it never spreads onto him); a poison may. A quick ember (or green) streak shows the jump.
const PRAIRIE_R := 4.0
const PRAIRIE_FIRE := Color(1.0, 0.55, 0.15)
const PRAIRIE_POISON := Color(0.45, 1.0, 0.35)
var _prairie_hops := 0
## Jumps Prairie Fire has made (tests).
var prairie_jumps := 0


## The hero's numbers lane LINES reads (pass 70), from _pstats.
func _pstats_lines(s: StatSheet) -> void:
	_bronco = clampf(s.get_stat("bronco_chance", 0.0), 0.0, 1.0)
	_prairie_hops = maxi(int(round(s.get_stat("debuff_jump", 0.0))), 0)


## Bucking Bronco's roll on a knocked-back creature (pass 70; damage() calls it after the shove). `dir` is the knock's
## way, `push` its m/s; `roll` (tests) replaces the dice. True when the creature went up and away.
func _bronco_kick(i: int, dir: Vector3, push: float, weapon_id: String, roll: float = -1.0) -> bool:
	if _bronco <= 0.0 or weapon_id == "" or weapon_id == "revive" or weapon_id == "loose_rocket":
		return false
	if i < 0 or i >= MAX or hp[i] <= 0.0 or not can_launch(i):
		return false
	var r: float = roll if roll >= 0.0 else _rng.randf()
	if r >= _bronco:
		return false
	var fly := Vector3(dir.x, 0.0, dir.z)
	if fly.length_squared() < 0.0001:
		fly = pos[i] - player.global_position if player else Vector3.FORWARD
		fly.y = 0.0
	fly = fly.normalized() if fly.length_squared() > 0.0001 else Vector3.FORWARD
	if not launch(i, BRONCO_HEIGHT, BRONCO_AIR, 0.0, weapon_id):
		return false
	var dist := clampf(BRONCO_AWAY_BASE + BRONCO_AWAY_PER * maxf(push, 0.0), BRONCO_AWAY_MIN, BRONCO_AWAY_MAX) * hero_knock_mult()
	(_launched[i] as Dictionary)["drift"] = fly * (dist / BRONCO_AIR)
	bronco_launches += 1
	return true


## A Bucking Bronco throw's flight away (pass 70; _tick_launch calls it): the launch's entry carries its flat `drift`
## (m/s); the body goes with it over the sand, kept inside the arena.
func _bronco_drift(i: int, delta: float) -> void:
	var e = _launched.get(i)
	if not e is Dictionary or not (e as Dictionary).has("drift"):
		return
	var v: Vector3 = (e as Dictionary)["drift"]
	var p := _clamp_arena(pos[i] + v * delta)
	p.y = _height(p.x, p.z)
	pos[i] = p


## Prairie Fire's jump (pass 70): source `wid` (`e`, its entry in fire_src or poison_src of creature `i`) goes on to the
## nearest creature within PRAIRIE_R that lacks it. Returns the creature it reached, -1 for none.
func _prairie_jump(i: int, fire: bool, wid: String, e: Dictionary) -> int:
	if _prairie_hops <= 0 or i < 0 or i >= MAX:
		return -1
	var hops := int(e.get("hops", 0))
	if hops >= _prairie_hops:
		return -1
	var best := -1
	var best_d := PRAIRIE_R * PRAIRIE_R
	for j in indices_in_radius(pos[i], PRAIRIE_R):
		if j == i or alive[j] == 0 or state[j] == STATE_DYING or hidden[j] == 1 or held[j] == 1:
			continue
		if fire and j == boss_index:
			continue
		var carries: bool = (fire_src[j] as Dictionary).has(wid) if fire else (poison_src[j] as Dictionary).has(wid)
		if carries:
			continue
		var d := pos[j] - pos[i]
		d.y = 0.0
		if d.length_squared() < best_d:
			best_d = d.length_squared()
			best = j
	if best < 0:
		return -1
	if fire:
		ignite(best, wid, float(e.get("dmg", 1.0)), float(e.get("dur", 3.0)), float(e.get("spread", 0.0)), i, float(e.get("root", 0.0)))
		var ne = (fire_src[best] as Dictionary).get(wid)
		if ne is Dictionary:
			(ne as Dictionary)["hops"] = hops + 1
	else:
		poison(best, wid, float(e.get("dmg", 3.0)), int(e.get("stacks", 1)), float(e.get("dur", 4.0)))
		var np = (poison_src[best] as Dictionary).get(wid)
		if np is Dictionary:
			(np as Dictionary)["hops"] = hops + 1
	prairie_jumps += 1
	var fx = game.get("fx") if game != null else null
	if fx != null and fx.has_method("lightning"):
		var a := pos[i] + Vector3(0, size[i] * 0.5, 0)
		var b := pos[best] + Vector3(0, size[best] * 0.5, 0)
		fx.lightning([a, b], PRAIRIE_FIRE if fire else PRAIRIE_POISON, 0.45)
	return best


## Prairie Fire on a death (pass 70; _die calls it before the creature's burns and poisons are cleared): each source on
## it jumps on as one that ran out would.
func _prairie_on_death(i: int) -> void:
	if _prairie_hops <= 0:
		return
	for k in (fire_src[i] as Dictionary).keys():
		_prairie_jump(i, true, str(k), (fire_src[i] as Dictionary)[k])
	for k in (poison_src[i] as Dictionary).keys():
		_prairie_jump(i, false, str(k), (poison_src[i] as Dictionary)[k])


func is_poisoned(i: int) -> bool:
	return i >= 0 and i < MAX and not (poison_src[i] as Dictionary).is_empty()


## Fire from one item: a new source, or the same source's timer reset. `from_enemy` is the creature it jumped
## from (-1 when a weapon lit it); `spread` is this fire's own chance to jump on, per tick, per touching creature.
func ignite(i: int, weapon_id: String, dmg_per_tick: float, duration: float, spread: float, from_enemy: int = -1, root_spread: float = -1.0) -> void:
	if i < 0 or i >= MAX or alive[i] == 0 or state[i] == STATE_DYING:
		return
	# a weapon that sets only some of what it hits alight (pass 51, params.ignite_chance: Dragon's Breath, 60%): one roll a
	# creature a shot. A fire jumping on from a burning creature has its own odds (the spread) and never rolls.
	if from_enemy < 0 and not ignite_roll(i, weapon_id, _ignite_chance(weapon_id)):
		return
	var src: Dictionary = fire_src[i]
	var fresh := src.is_empty()
	# Ducktape (pass 47) stretches the burn; "dur" keeps the item's own seconds, so a fire that jumps on is stretched once,
	# not once more at every jump
	var burn: float = duration * debuff_mult() * _ll_longer
	# blue fire (pass 48): a source whose weapon burns blue (WeaponInstance.blue_fire: Methanol, Moonshine) burns blue,
	# and so does every creature it jumps to (the jump keeps the source's id)
	var blue := _burns_blue(weapon_id)
	if src.has(weapon_id):
		var e: Dictionary = src[weapon_id]
		e["t"] = burn
		e["dmg"] = maxf(float(e["dmg"]), dmg_per_tick)
		e["spread"] = maxf(float(e["spread"]), spread)
	else:
		src[weapon_id] = {"dmg": dmg_per_tick, "t": burn, "dur": duration, "spread": spread, "root": root_spread if root_spread >= 0.0 else spread, "from": from_enemy, "blue": blue}
	if blue:
		fire_blue[i] = 1
	elif fresh:
		fire_blue[i] = 0
	if fresh:
		fire_tick[i] = FIRE_TICK
		if game and game.has_method("fx_ignite"):
			game.fx_ignite(pos[i] + Vector3(0, size[i] * 0.4, 0), size[i], fire_blue[i] == 1)


## Whether weapon `weapon_id`'s hit sets creature `i` alight at `chance` (pass 51): always at 1 or more, never at 0, else
## one roll a creature a shot (the roll holds IGNITE_ROLL_HOLD seconds for that weapon, see ign_t).
func ignite_roll(i: int, weapon_id: String, chance: float) -> bool:
	if chance >= 1.0:
		return true
	if chance <= 0.0:
		return false
	if ign_t[i] > 0.0 and ign_w[i] == weapon_id:
		return ign_ok[i] == 1
	var ok := _rng.randf() < chance
	ign_t[i] = IGNITE_ROLL_HOLD
	ign_w[i] = weapon_id
	ign_ok[i] = 1 if ok else 0
	return ok


## The share of the creatures it hits that weapon `weapon_id` sets alight (pass 51): the held weapon's
## WeaponInstance.ignite_chance(), 1 for anything else (a structure's fire, a creature's).
func _ignite_chance(weapon_id: String) -> float:
	if weapon_id == "":
		return 1.0
	var wi := Run.weapon_instance(weapon_id)
	return wi.ignite_chance() if wi else 1.0


## Whether fire from `weapon_id` burns blue (pass 48): the held weapon's WeaponInstance.blue_fire().
func _burns_blue(weapon_id: String) -> bool:
	if weapon_id == "":
		return false
	var wi := Run.weapon_instance(weapon_id)
	return wi != null and wi.blue_fire()


func is_burning(i: int) -> bool:
	return i >= 0 and i < MAX and not (fire_src[i] as Dictionary).is_empty()


## True when the creature carries the given element ("poison" or "fire"); "" is never carried.
func has_element(i: int, element: String) -> bool:
	match element:
		"poison":
			return is_poisoned(i)
		"fire":
			return is_burning(i)
	return false


## Runs the fire clocks of one enemy: expires sources, every FIRE_TICK seconds deals the sum of their ticks, and
## every source rolls to jump onto each creature this one is touching.
func _tick_fire(i: int, delta: float) -> void:
	var src: Dictionary = fire_src[i]
	if src.is_empty():
		return
	var total := 0.0
	var best_id := ""
	var best := 0.0
	var gone := false
	for k in src.keys():
		var e: Dictionary = src[k]
		e["t"] = float(e["t"]) - delta
		if float(e["t"]) <= 0.0:
			# Prairie Fire (pass 70): a burn that runs out jumps on
			_prairie_jump(i, true, str(k), e)
			src.erase(k)
			gone = true
			continue
		var part: float = float(e["dmg"])
		total += part
		if part > best:
			best = part
			best_id = str(k)
	if src.is_empty():
		fire_blue[i] = 0
		return
	if gone and fire_blue[i] == 1:
		# a blue source burnt out (pass 48): blue while one is left
		var still := 0
		for k in src.keys():
			if bool((src[k] as Dictionary).get("blue", false)):
				still = 1
				break
		fire_blue[i] = still
	# flames lick up the whole time it burns, not only on the damage ticks
	fire_puff[i] -= delta
	if fire_puff[i] <= 0.0:
		fire_puff[i] = 0.18
		if game and game.has_method("fx_fire"):
			game.fx_fire(pos[i] + Vector3(0, size[i] * 0.3, 0), size[i], fire_blue[i] == 1)
	fire_tick[i] -= delta
	if fire_tick[i] <= 0.0:
		fire_tick[i] = FIRE_TICK
		# spread first, so a creature that dies of this tick still passes its fire on
		for k in src.keys():
			var e: Dictionary = src[k]
			var chance := float(e["spread"])
			if chance <= 0.0:
				continue
			for j in indices_in_radius(pos[i], radius[i] + 1.2):
				if j == i or j == int(e["from"]) or alive[j] == 0 or state[j] == STATE_DYING or j == boss_index:
					continue
				var touch: float = radius[i] + radius[j] + 0.25
				var d := pos[j] - pos[i]
				d.y = 0.0
				if d.length_squared() > touch * touch:
					continue
				if (fire_src[j] as Dictionary).has(k):
					continue
				if _rng.randf() < chance:
					# every caught fire spreads at a fixed fraction of the original weapon's chance, however far down the chain
					ignite(j, str(k), float(e["dmg"]), float(e["dur"]), float(e["root"]) * CHILD_SPREAD, i, float(e["root"]))
		_pstats()
		# White Phosphorus's extra, and Lingering Light's harder ticks (pass 54)
		damage(i, (total) * (1.0 + _fire_vuln) * _ll_harder, best_id, Vector3.ZERO, 0.0, false, true)


## Runs the poison clocks of one enemy: expires sources, and every POISON_TICK seconds deals the sum of their ticks.
func _tick_poison(i: int, delta: float) -> void:
	var src: Dictionary = poison_src[i]
	if src.is_empty():
		return
	var total := 0.0
	var best_id := ""
	var best := 0.0
	for k in src.keys():
		var e: Dictionary = src[k]
		e["t"] = float(e["t"]) - delta
		if float(e["t"]) <= 0.0:
			# Prairie Fire (pass 70): a poison that runs out jumps on
			_prairie_jump(i, false, str(k), e)
			src.erase(k)
			continue
		var part: float = float(e["dmg"]) * int(e["stacks"])
		total += part
		if part > best:
			best = part
			best_id = str(k)
	if src.is_empty():
		return
	poison_tick[i] -= delta
	if poison_tick[i] <= 0.0:
		poison_tick[i] = POISON_TICK
		# Lingering Light (pass 54) makes every tick harder
		_pstats()
		var was_dead := damage(i, total * _ll_harder, best_id, Vector3.ZERO, 0.0, true)
		if game and game.has_method("fx_poison"):
			game.fx_poison(pos[i] + Vector3(0, size[i] * 0.5, 0))
		if was_dead:
			return


## `weapon_id` "revive" is the hero standing up again: the crowd around him is gone outright, while an Elite or a
## boss takes a tenth of its health instead. "loose_rocket" is a rocket whose thrower died: it throws the crowd and
## barely scratches it.
## A blast throws everything within `r` away from `center` without hurting it (pass 33.3, the rocketeer's rocket): the
## push falls off to half at the rim, heavy creatures budge less, a resisting one by its share (pass 67,
## EnemyDef.knockback_resist: hero-side and hostile throws alike) and the boss barely, and each lands squashed.
## `except_i` is spared (pass 45: the golem stands at its own stalactites' apex and inside its own boulder's blast).
func throw_radius(center: Vector3, r: float, force: float, except_i: int = -1) -> int:
	var n := 0
	for i in indices_in_radius(center, r):
		if hidden[i] == 1 or state[i] == STATE_DYING or lift_t[i] > 0.0:
			continue
		if i == except_i:
			continue
		var d := pos[i] - center
		d.y = 0.0
		if d.length_squared() < 0.0001:
			d = Vector3(_rng.randf_range(-1.0, 1.0), 0, _rng.randf_range(-1.0, 1.0))
		var fall_off: float = 1.0 - 0.5 * clampf(d.length() / maxf(r, 0.1), 0.0, 1.0)
		var mass: float = maxf(size[i], 0.8)
		kb[i] += d.normalized() * force * fall_off / mass * _t_kbt[type_idx[i]] * (0.15 if i == boss_index else 1.0)
		squash[i] = 0.6
		flash[i] = maxf(flash[i], 0.5)
		n += 1
	return n


# ---------------------------------------------------------------- pass 72 (lane ITEMS): the hero's knockback halved
## Garry: "Half all the knockback effect, it's too easy to make enemies basically unable to get to you if you choose to
## scale that." One map number, WaveTimeline.hero_knockback_mult (Red Canyon 0.5), on every push the hero's side gives a
## creature: damage()'s kb_force from any hero source (every weapon, mutation, evolution, line, passive, perk, the ball,
## the frisbee, thorns, the revive), hero_throw_radius (the Nuke, Thruster Burst, Grand Finale), Buck's Ram, the
## tornado's toss, the Guitarra chord's bounce (ConeWave) and Bucking Bronco's throw distance. Never a hostile push (a dead
## rocketeer's loose rocket, a hostile blast's friendly fire, the golem's boulder, a charger's shove, an Elite's split),
## the pull, knockback_resist or a stun. `hero_knockback_override` >= 0 replaces the map's number (tests).
const HOSTILE_PUSH_IDS := ["loose_rocket", "blast"]
var hero_knockback_override := -1.0


## The map's multiplier on the hero's pushes now (1 without a map).
func hero_knock_mult() -> float:
	if hero_knockback_override >= 0.0:
		return hero_knockback_override
	var m: MapDef = Run.map
	if m == null or m.timeline == null:
		return 1.0
	return maxf(m.timeline.hero_knockback_mult, 0.0)


## A hit's push share by its source: hero_knock_mult() for the hero's, 1 for a hostile one (HOSTILE_PUSH_IDS).
func _hero_push(weapon_id: String) -> float:
	return 1.0 if weapon_id in HOSTILE_PUSH_IDS else hero_knock_mult()


## A blast from the hero's side throwing the crowd (throw_radius at the map's share of `force`).
func hero_throw_radius(center: Vector3, r: float, force: float, except_i: int = -1) -> int:
	return throw_radius(center, r, force * hero_knock_mult(), except_i)


## `flags` (pass 76, lane DYN): damage()'s hit flags for every creature in the blast (HIT_MINI: the dynamite's mass mini
## crits, ProjectileManager._mass_mini_flags).
func damage_radius(center: Vector3, r: float, amount: float, weapon_id: String = "", kb_force: float = 0.0, flags: int = 0) -> int:
	var hit := 0
	for i in indices_in_radius(center, r):
		var d := pos[i] - center
		var amt := amount
		if weapon_id == "revive":
			var bdef: EnemyDef = types[type_idx[i]]["def"]
			if i == boss_index or bdef.archetype == "elite" or bdef.archetype == "boss":
				amt = max_hp[i] * 0.1
		# pass 79 (lane FX): _die reads which creature a blast is striking (its body is thrown up, _corpse_begin)
		var blast_prev := _corpse_blast_i
		_corpse_blast_i = i if kb_force > 0.0 else -1
		if damage(i, amt, weapon_id, d, kb_force, false, false, flags):
			hit += 1
		else:
			hit += 1
		_corpse_blast_i = blast_prev
	return hit


## Pass 76 (lane DYN, the dynamite's mass mini crits, params.mass_mini): how many creatures a blast of radius `r` at
## `center` catches, counted as damage() takes them (alive, not dying, hidden or held), before damage_radius strikes.
func blast_count(center: Vector3, r: float) -> int:
	var n := 0
	for i in indices_in_radius(center, r):
		if alive[i] == 1 and state[i] != STATE_DYING and hidden[i] == 0 and held[i] == 0:
			n += 1
	return n


func _die(i: int, weapon_id: String) -> void:
	held[i] = 0
	var def: EnemyDef = types[type_idx[i]]["def"]
	var elite: EliteModDef = elites[elite_idx[i]] if elite_idx[i] >= 0 else null
	# Blight: a creature that dies poisoned passes every source on to the nearest one
	if Run.player_sheet.get_stat("poison_pass", 0.0) > 0.0 and not (poison_src[i] as Dictionary).is_empty():
		var best := -1
		var best_d := 9.0
		for j in indices_in_radius(pos[i], 3.0):
			if j == i or state[j] == STATE_DYING:
				continue
			var dd := pos[j].distance_squared_to(pos[i])
			if dd < best_d:
				best_d = dd
				best = j
		if best >= 0:
			for wid in (poison_src[i] as Dictionary).keys():
				var src: Dictionary = poison_src[i][wid]
				poison(best, str(wid), float(src.get("dmg", 3.0)), int(src.get("stacks", 1)), float(src.get("t", 8.0)), false)
			if game:
				game.fx_burst(pos[best] + Vector3(0, size[best] * 0.6, 0), Color(0.5, 1.0, 0.4), 0.9)
	# Prairie Fire (pass 70): its burns and poisons jump on before they go with it
	_prairie_on_death(i)
	state[i] = STATE_DYING
	timer[i] = DIE_TIME
	anim_t[i] = 0.0
	# pass 79 (lane FX): the body keeps its push and follows through (a blast's kill flies); the boss's is zeroed
	_corpse_begin(i)
	# pass 48: whoever listens reads the creature as it fell, its poisons and burns still on it (it is dying already, so a
	# hit from a listener cannot kill it twice)
	creature_dying.emit(i, weapon_id)
	poison_src[i] = {}
	fire_src[i] = {}
	fire_blue[i] = 0
	hamper_t[i] = 0.0
	status_t[i] = 0.0
	vel[i] = Vector3.ZERO
	count_alive -= 1
	if vspecial[i] == 1:
		specials_alive = maxi(specials_alive - 1, 0)
	Audio.play(str(def.sfx.get("die", "")), pos[i])
	Run.add_kill(def.id, weapon_id)
	# a training dummy (pass 48) counts for no quest: the run's own kill above still feeds what the hero carries
	if _t_dummy[type_idx[i]] == 0:
		Save.add_total("kills", 1)
		Save.add_keyed_total("kills_of_enemy", def.id, 1)
		if weapon_id != "":
			Save.add_keyed_total("kills_with_weapon", weapon_id, 1)
	died_xp_scale = xp_scale[i]
	died_max_hp = max_hp[i]
	died_size = size[i]
	enemy_died.emit(def, pos[i], elite, weapon_id)
	died_xp_scale = 0.0
	died_max_hp = 0.0
	died_size = 0.0
	_hot_sauce_pay(i, def, elite)
	_special_chest_drop(i, def, elite)
	if RunAnalytics.I and vspecial[i] == 1: RunAnalytics.I.special_killed(def, special_chests, weapon_id)
	if game and game.has_method("on_creature_died_index"):
		game.on_creature_died_index(i)
	if not def.death_burst.is_empty() and blown[i] == 0 and game and game.has_method("elite_explosion"):
		# the body goes off after a moment: a red ring on the corpse says so; the crowd around it takes a fifth
		var dbst: Dictionary = def.death_burst
		# the warning lasts 1/pace (pass 48); the body's own fixed numbers (pass 58)
		game.elite_explosion(pos[i], float(dbst.get("radius", 2.4)), float(dbst.get("damage", 12.0)) * stage_of(i) * lvd_of(i) * host_of(i),
			float(dbst.get("delay", 2.0)) / pace, float(dbst.get("knockback", 0.0)), 0.2, hit_info(i, "melee", ["death burst"]))
	if elite != null:
		match elite.on_death:
			"split":
				var n := int(elite.params.get("split_count", 3))
				var sc := float(elite.params.get("split_scale", 0.6))
				for k in range(n):
					var a := TAU * k / n
					var p := pos[i] + Vector3(cos(a), 0, sin(a)) * 1.2
					# the children are their parent's kind (pass 53): its art variant and its row's overrides, and its
					# source's fixed numbers (pass 58)
					var j := spawn(def.id, p, null, sc, 0.5, def.variant_code, def.override_stats, src_of(i))
					if j >= 0:
						kb[j] = Vector3(cos(a), 0, sin(a)) * 4.0
			"explode":
				if game and game.has_method("elite_explosion"):
					game.elite_explosion(pos[i], float(elite.params.get("explode_radius", 3.0)), float(elite.params.get("explode_damage", 25.0)) * host_of(i), float(elite.params.get("telegraph", 0.5)) / pace, 0.0, 0.2, hit_info(i, "melee", ["explosion"]))
	if i == boss_index:
		boss_index = -1
		Run.bosses_killed += 1
		boss_died.emit(def, pos[i])


## Hot Sauce's pay (pass 47) for a coloured creature the hero kills while he carries `difficulty`: a gem worth HOT_XP x
## difficulty of the kill's XP (as Game drops it: PickupManager.drop_from's 1, 5 and 25 at the def's chances, four times
## for an elite modifier), and for a variance special a chest at HOT_CHEST_CHANCE x difficulty, one per HOT_CHEST_GAP
## seconds at most (an elite-modded one drops a chest anyway). Never for a boss or an Elite, which pay anyway.
func _hot_sauce_pay(i: int, def: EnemyDef, elite: EliteModDef) -> void:
	_pstats()
	if _difficulty <= 0.0 or game == null or (vspecial[i] == 0 and elite == null):
		return
	if i == boss_index or def.archetype == "boss" or def.archetype == "elite":
		return
	var pk = game.get("pickups")
	if pk == null:
		return
	var d: Dictionary = def.drops
	var xp: float = xp_scale[i] * (float(d.get("small", 0.0)) + 5.0 * float(d.get("medium", 0.0)) + 25.0 * float(d.get("large", 0.0)))
	var bonus: float = xp * HOT_XP * _difficulty
	if bonus > 0.0:
		var gem: int = PickupManager.KIND_GEM_S if bonus < 5.0 else (PickupManager.KIND_GEM_M if bonus < 25.0 else PickupManager.KIND_GEM_L)
		pk.spawn(gem, pos[i], bonus)
	if elite == null and _hot_chest_cd <= 0.0 and game.get("no_random_chests") != true and _rng.randf() < HOT_CHEST_CHANCE * _difficulty:
		_hot_chest_cd = HOT_CHEST_GAP
		hot_chests += 1
		pk.spawn_chest(pos[i])


## Pass 72 (lane SPEC; Garry: specials "should have way more of a chance of dropping a box"): a variance special the hero
## kills drops a chest at its `chest_chance` (EnemyDef.special_value: the creature's own `variance.special.chest_chance`,
## else the map's special_defaults, else 0.35), on top of anything else its death pays (Hot Sauce's chest rolls apart).
## Never for a training dummy, an elite-modded one or a boss (none of them rolls a special), nor while a capture tool
## holds the kill chests back (game.no_random_chests). Returns whether it dropped one (tests).
var special_chests := 0
func _special_chest_drop(i: int, def: EnemyDef, elite: EliteModDef) -> bool:
	if vspecial[i] == 0 or elite != null or game == null or def.brain == "dummy" or def.archetype == "boss":
		return false
	if game.get("no_random_chests") == true:
		return false
	var pk = game.get("pickups")
	if pk == null:
		return false
	var chance := clampf(EnemyDef.special_value(def.variance.get("special", {}), special_defaults, "chest_chance"), 0.0, 1.0)
	if chance <= 0.0 or _rng.randf() >= chance:
		return false
	special_chests += 1
	pk.spawn_chest(pos[i])
	return true


## Whether one more variance special may come now (pass 72): fewer than EnemyDef.special_max_alive(special_defaults)
## alive (none when it is -1, no limit).
func _special_room() -> bool:
	var cap: int = EnemyDef.special_max_alive(special_defaults)
	return cap < 0 or specials_alive < cap


func _free(i: int) -> void:
	if alive[i] == 0:
		return
	if state[i] != STATE_DYING:
		count_alive -= 1
		if vspecial[i] == 1:
			specials_alive = maxi(specials_alive - 1, 0)
	alive[i] = 0
	held[i] = 0
	lift_mode[i] = 0
	vspecial[i] = 0
	vglow[i] = 0.0
	# one freed under the sand leaves no mound behind (pass 60)
	_mound_end(i)
	free_list.append(i)
	if i == boss_index:
		boss_index = -1


# ---------------------------------------------------------------- queries

func _cell(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))


## A grid column (or row) for a coordinate, clamped to the grid; the grid's edge sits on a CELL boundary, so the cells
## are the old ones.
func _gcol(v: float) -> int:
	return clampi(int(floor((v + _g_half) / CELL)), 0, _gw - 1)


func _rebuild_grid() -> void:
	# pass 73 (lane SNIPER): the priority creatures' list is gathered again after every rebuild (priority_target)
	_grid_epoch += 1
	var half: float = ceilf((arena_radius + 12.0) / CELL) * CELL
	if _gw == 0 or half != _g_half:
		_g_half = half
		_gw = int(half * 2.0 / CELL) + 1
		_g_head.resize(_gw * _gw)
		_g_next.resize(MAX)
	_g_head.fill(-1)
	_big.clear()
	_grid_max_r = 0.0
	# backwards, so every cell lists its creatures in index order
	for i in range(MAX - 1, -1, -1):
		if alive[i] == 0 or state[i] == STATE_DYING or hidden[i] == 1 or held[i] == 1:
			continue
		var c := _gcol(pos[i].z) * _gw + _gcol(pos[i].x)
		_g_next[i] = _g_head[c]
		_g_head[c] = i
		var r := radius[i]
		if r > _grid_max_r:
			_grid_max_r = r
		if r > BIG_R:
			_big.append(i)


func indices_in_radius(center: Vector3, r: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	if _gw == 0:
		return out
	var x0 := _gcol(center.x - r)
	var x1 := _gcol(center.x + r)
	var z0 := _gcol(center.z - r)
	var z1 := _gcol(center.z + r)
	var r2 := r * r
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			var i := _g_head[cz * _gw + cx]
			while i >= 0:
				var dx := pos[i].x - center.x
				var dz := pos[i].z - center.z
				if dx * dx + dz * dz <= r2:
					out.append(i)
				i = _g_next[i]
	return out


## A round's touch (pass 83, the lead; lane SCALE found the King's 2.2 m body let scattered rounds through): the creatures
## whose BODY a round of radius `r` at `center` touches, the reach being r + max(`pad`, the creature's radius - BODY_SLACK).
## For an ordinary creature (radius up to pad + BODY_SLACK = 0.5 m) this is exactly indices_in_radius(center, r + pad), as
## before; a bigger body (a boss, a beetle, a golem) is hit wherever it is drawn.
const BODY_SLACK := 0.15


func indices_touching(center: Vector3, r: float, pad: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	if _gw == 0:
		return out
	var reach := r + maxf(pad, _max_r - BODY_SLACK)
	var x0 := _gcol(center.x - reach)
	var x1 := _gcol(center.x + reach)
	var z0 := _gcol(center.z - reach)
	var z1 := _gcol(center.z + reach)
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			var i := _g_head[cz * _gw + cx]
			while i >= 0:
				var dx := pos[i].x - center.x
				var dz := pos[i].z - center.z
				var ri := r + maxf(pad, radius[i] - BODY_SLACK)
				if dx * dx + dz * dz <= ri * ri:
					out.append(i)
				i = _g_next[i]
	return out


## How hard the map's obstacles push creature `i` away: only the ones whose cell list reaches its cell, summed in the
## order of the map's list, as the loop over all of them did (a far obstacle added nothing).
func _obstacle_push(i: int) -> Vector3:
	var push := Vector3.ZERO
	var near_obst = _obst_cells.get(Vector2i(floori(pos[i].x / OBST_CELL), floori(pos[i].z / OBST_CELL)))
	if near_obst == null:
		return push
	var my_r := radius[i]
	for k: int in near_obst:
		var o: Vector3 = obstacles[k]
		var d := Vector3(pos[i].x - o.x, 0, pos[i].z - o.y)
		var l2 := d.length_squared()
		var min_d := o.z + my_r
		if l2 < min_d * min_d and l2 > 0.0001:
			var l := sqrt(l2)
			push += d / l * (min_d - l) * 3.0
	return push


## The obstacle cells, built again whenever the map's obstacles change in number or a wider creature turns up.
func _obstacle_cells() -> void:
	if _obst_n == obstacles.size() and _max_r <= _obst_margin:
		return
	_obst_cells.clear()
	_obst_n = obstacles.size()
	_obst_margin = maxf(_max_r, 1.5)
	for k in range(obstacles.size()):
		var o: Vector3 = obstacles[k]
		var reach: float = o.z + _obst_margin
		for cx in range(floori((o.x - reach) / OBST_CELL), floori((o.x + reach) / OBST_CELL) + 1):
			for cz in range(floori((o.y - reach) / OBST_CELL), floori((o.y + reach) / OBST_CELL) + 1):
				var key := Vector2i(cx, cz)
				var arr: PackedInt32Array = _obst_cells.get(key, PackedInt32Array())
				arr.append(k)
				_obst_cells[key] = arr


## The creature a priority weapon takes (pass 48: the single-target weapons with `"targeting": "priority"`,
## WeaponBehavior.aim_index): the one in range with the smallest distance over its weight, the weight its max HP over the
## crowd's mean, from 1 up to PRIORITY_CAP, and PRIORITY_CAP for big game (is_big_game). A creature twice the crowd's health
## is worth going twice as far for. `avoid` leaves out creatures carrying that element, as in nearest_index. -1 for none.
## Only what is on the screen unless `any_screen` (pass 54, _screen_only).
func priority_index(from: Vector3, max_range: float, avoid: String = "", any_screen: bool = false) -> int:
	if _mean_max_hp <= 0.0:
		refresh_crowd_stats()
	var inv_mean := 1.0 / maxf(_mean_max_hp, 0.001)
	var best := -1
	var best_k := INF
	var has_avoid := avoid != ""
	var so := _screen_only(any_screen)
	# is_big_game inlined (array reads, no call per candidate): the held gun's tracking asks every frame, every priority
	# weapon and every seeker's lock too, over most of the crowd (pass 48, perf_late)
	for i in indices_in_radius(from, max_range):
		if so and onscreen[i] == 0:
			continue
		# pass 73 (lane GROUND): one still rising out of the sand (or sinking into it) is never chosen yet
		if rise_t[i] < rise_targetable:
			continue
		if has_avoid and has_element(i, avoid):
			continue
		var dx := pos[i].x - from.x
		var dz := pos[i].z - from.z
		var w: float = PRIORITY_CAP
		if i != boss_index and elite_idx[i] < 0 and _t_big[type_idx[i]] == 0:
			w = clampf(max_hp[i] * inv_mean, 1.0, PRIORITY_CAP)
		var k := (dx * dx + dz * dz) / (w * w)
		if k < best_k:
			best_k = k
			best = i
	return best


## The crowd's numbers (pass 48), kept once a tick by the simulation and here for whoever places creatures by hand (tests,
## tools): its mean max HP (priority_index) and how many are poisoned (Run.poisoned_alive, Gas Mask).
func refresh_crowd_stats() -> void:
	var total := 0.0
	var n := 0
	var poisoned := 0
	for i in range(MAX):
		if alive[i] == 0 or state[i] == STATE_DYING:
			continue
		total += max_hp[i]
		n += 1
		if not (poison_src[i] as Dictionary).is_empty():
			poisoned += 1
	_mean_max_hp = total / float(n) if n > 0 else 0.0
	Run.poisoned_alive = poisoned


## The nearest creature within `max_range` (not carrying `avoid`'s element), on the screen unless `any_screen` (pass 54).
## -1 for none.
func nearest_index(from: Vector3, max_range: float, avoid: String = "", any_screen: bool = false) -> int:
	var best := -1
	var best_d := max_range * max_range
	var so := _screen_only(any_screen)
	for i in indices_in_radius(from, max_range):
		if so and onscreen[i] == 0:
			continue
		# pass 73 (lane GROUND): one still rising out of the sand (or sinking into it) is never chosen yet
		if rise_t[i] < rise_targetable:
			continue
		if avoid != "" and has_element(i, avoid):
			continue
		var d := pos[i] - from
		d.y = 0.0
		var l := d.length_squared()
		if l < best_d:
			best_d = l
			best = i
	return best


## A creature within `max_range` at random (not in `exclude`, not carrying `avoid`'s element), on the screen unless
## `any_screen` (pass 54). -1 for none.
func random_in_range(from: Vector3, max_range: float, exclude: Array = [], avoid: String = "", any_screen: bool = false) -> int:
	var cands := indices_in_radius(from, max_range)
	var pool: Array = []
	var so := _screen_only(any_screen)
	for i in cands:
		if so and onscreen[i] == 0:
			continue
		# pass 73 (lane GROUND): one still rising out of the sand (or sinking into it) is never chosen yet
		if rise_t[i] < rise_targetable:
			continue
		if avoid != "" and has_element(i, avoid):
			continue
		if not exclude.has(i):
			pool.append(i)
	if pool.is_empty():
		return -1
	return pool[_rng.randi() % pool.size()]


## The creature in range with the most others within 2.5 m. `avoid` leaves out creatures carrying that element (a fire
## bomb wants the unburnt); `keep_away` leaves out creatures within `keep_r` of those spots, as candidates and in the
## count (pass 36: where other bombs are headed or just landed, so two bomb weapons pick two crowds). Only what is on the
## screen counts, as a candidate and in the count, unless `any_screen` (pass 54).
func densest_point(from: Vector3, max_range: float, avoid: String = "", keep_away: Array = [], keep_r: float = 0.0, any_screen: bool = false) -> Vector3:
	var cands := indices_in_radius(from, max_range)
	if cands.is_empty():
		return Vector3.INF
	var best := -1
	var best_n := -1
	var step: int = max(1, cands.size() / 40)
	var kr2 := keep_r * keep_r
	var so := _screen_only(any_screen)
	for k in range(0, cands.size(), step):
		var i := cands[k]
		if so and onscreen[i] == 0:
			continue
		# pass 73 (lane GROUND): one still rising out of the sand (or sinking into it) is never chosen yet
		if rise_t[i] < rise_targetable:
			continue
		if avoid != "" and has_element(i, avoid):
			continue
		if _near_any(pos[i], keep_away, kr2):
			continue
		var n := 0
		for j in indices_in_radius(pos[i], 2.5):
			if so and onscreen[j] == 0:
				continue
			if (avoid == "" or not has_element(j, avoid)) and not _near_any(pos[j], keep_away, kr2):
				n += 1
		if n > best_n:
			best_n = n
			best = i
	return pos[best] if best >= 0 else Vector3.INF


func _near_any(p: Vector3, spots: Array, r2: float) -> bool:
	for s: Vector3 in spots:
		var dx := p.x - s.x
		var dz := p.z - s.z
		if dx * dx + dz * dz < r2:
			return true
	return false


## Pass 79 (lane WORLD; Garry: "Throw the dynamite in front of the enemies"): the mean ground velocity (m/s, on the
## world's clock: High Noon's slow is in it) of the creatures within `r` of `at` that walk on their own: in the grid (alive,
## not dying, not hidden or held), all the way up out of the sand. The push a hit gave them (kb) is left out: it dies away in
## a fraction of a second. Vector3.ZERO when there are none. Lobber leads a throw by it (params.lead).
func crowd_velocity(at: Vector3, r: float) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for i in indices_in_radius(at, r):
		if rise_t[i] < 1.0:
			continue
		sum += vel[i]
		n += 1
	if n == 0:
		return Vector3.ZERO
	var v := sum * (time_scale / float(n))
	v.y = 0.0
	return v


## Pass 79 (lane WORLD): the mean walking speed (m/s, the world's clock) of the creatures crowd_velocity counts: how fast
## the crowd closes on the hero whichever way each one heads (Lobber's chase lead). 0 when there are none.
func crowd_speed(at: Vector3, r: float) -> float:
	var sum := 0.0
	var n := 0
	for i in indices_in_radius(at, r):
		if rise_t[i] < 1.0:
			continue
		sum += Vector2(vel[i].x, vel[i].z).length()
		n += 1
	return sum * time_scale / float(n) if n > 0 else 0.0


## Pass 79 (lane WORLD): one creature's own ground velocity on the world's clock (a priority target the dynamite is led
## onto: a special, an Elite, the boss), as crowd_velocity counts it. Vector3.ZERO for one gone or still rising.
func walk_velocity(i: int) -> Vector3:
	if i < 0 or i >= MAX or alive[i] == 0 or state[i] == STATE_DYING or rise_t[i] < 1.0:
		return Vector3.ZERO
	var v := vel[i] * time_scale
	v.y = 0.0
	return v


## Pass 79 (lane WORLD): how many creatures will stand within `r` of each of `spots` in `t` seconds (Lobber's lead, mode
## "predict"). Every creature within `reach` of `center` that walks on its own (in the grid, risen) is taken to close on
## `goal` (where the hero will be) at its own walking speed on the world's clock, stopping `gap` m short of it; one standing
## still (winding up, biting) stays where it is. One count per spot, in the spots' order.
func predicted_counts(spots: Array, r: float, t: float, goal: Vector3, gap: float, center: Vector3, reach: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(spots.size())
	out.fill(0)
	var r2 := r * r
	var g := Vector2(goal.x, goal.z)
	for i in indices_in_radius(center, reach):
		if rise_t[i] < 1.0:
			continue
		var p := Vector2(pos[i].x, pos[i].z)
		var to := g - p
		var d := to.length()
		var step := minf(Vector2(vel[i].x, vel[i].z).length() * time_scale * t, maxf(d - gap, 0.0))
		if d > 0.001:
			p += to / d * step
		for k in range(spots.size()):
			var sp: Vector3 = spots[k]
			var dx := p.x - sp.x
			var dz := p.y - sp.z
			if dx * dx + dz * dz <= r2:
				out[k] += 1
	return out


func indices_in_cone(from: Vector3, dir: Vector3, max_range: float, half_angle_deg: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var d2 := Vector2(dir.x, dir.z).normalized()
	var cos_lim := cos(deg_to_rad(half_angle_deg))
	for i in indices_in_radius(from, max_range):
		var v := Vector2(pos[i].x - from.x, pos[i].z - from.z)
		if v.length() < 0.001:
			out.append(i)
			continue
		if v.normalized().dot(d2) >= cos_lim:
			out.append(i)
	return out


func alive_count() -> int:
	return count_alive


## The crowd against the director's cap: each living creature counts its `cap_share` (the fodder counts half).
func cap_load() -> float:
	var load := 0.0
	for i in range(MAX):
		if alive[i] == 1 and state[i] != STATE_DYING:
			load += float(types[type_idx[i]].get("share", 1.0))
	return load


## Who hit the hero, for his death log (pass 33.2): the creature's name ("Goblin", "Sun Prophet (Elite)"), how it hit
## ("melee", "ranged", or "boss" for anything a boss does) and what came with it ("knocked back", "roped" ...).
## Pass 46, for the Down! screen's rows: `role` is "boss", "elite" (the Elite archetype or a creature wearing an elite
## modifier), "special" (a gear badge: the rocketeer, the harpooner) or "", and `colour` the "#rrggbb" it wore: an
## elite modifier's outline, a variance special's dark tint, else "".
func hit_info(i: int, kind: String, fx: Array = []) -> Dictionary:
	var name := "something"
	var boss := false
	var id := ""
	var elite := false
	var role := ""
	var colour := ""
	if i >= 0 and i < MAX and type_idx[i] >= 0 and type_idx[i] < types.size():
		var def: EnemyDef = types[type_idx[i]]["def"]
		name = def.display_name
		id = def.id
		elite = elite_idx[i] >= 0 or def.archetype == "elite"
		if def.archetype == "elite":
			name += " (Elite)"
		boss = i == boss_index or def.archetype == "boss"
		if boss:
			role = "boss"
		elif elite:
			role = "elite"
		elif _t_badge[type_idx[i]] == "gear":
			role = "special"
		if elite_idx[i] >= 0 and elite_idx[i] < elites.size():
			colour = "#" + (elites[elite_idx[i]] as EliteModDef).outline.to_html(false)
		elif vspecial[i] == 1:
			colour = "#" + Color(vtint[i].r, vtint[i].g, vtint[i].b).to_html(false)
	# `id` and `elite` are for the run recorder (pass 45): damage taken keyed by creature, not by display name
	return {"by": name, "kind": "boss" if boss else kind, "fx": fx, "id": id, "elite": elite, "role": role, "colour": colour}


## How many of one creature are alive right now (the director's `max_alive` rows): every type of that id together, the
## base, its art variants and its overridden copies (pass 53), so a row's limit holds across them.
func alive_of(id: String) -> int:
	var tis: Array = _types_of_id.get(id, [])
	if tis.is_empty():
		return 0
	var n := 0
	if tis.size() == 1:
		var ti: int = tis[0]
		for i in range(MAX):
			if alive[i] == 1 and type_idx[i] == ti and state[i] != STATE_DYING:
				n += 1
		return n
	for i in range(MAX):
		if alive[i] == 1 and state[i] != STATE_DYING and tis.has(type_idx[i]):
			n += 1
	return n


## The load one creature id puts on the director's cap right now (pass 53): each living one its own type's cap_share (an
## overridden copy may carry another share than the base).
func load_of(id: String) -> float:
	var tis: Array = _types_of_id.get(id, [])
	if tis.is_empty():
		return 0.0
	var load := 0.0
	for i in range(MAX):
		if alive[i] == 1 and state[i] != STATE_DYING and tis.has(type_idx[i]):
			load += float(types[type_idx[i]].get("share", 1.0))
	return load


## The rope: a creature on a tether is pulled to `length` of the hero whenever the rope is taut, so the hero drags it
## along wherever he goes. Returns how far it was dragged this time (0 when the rope is slack), or -1 once it is gone.
func tether_pull(i: int, ppos: Vector3, length: float) -> float:
	if not is_alive(i):
		return -1.0
	var d := ppos - pos[i]
	d.y = 0.0
	var dist := d.length()
	if dist > length and dist > 0.01:
		var moved := dist - length
		pos[i] += d.normalized() * moved
		pos[i].y = _height(pos[i].x, pos[i].z)
		vel[i] = Vector3.ZERO
		if moved > 0.002:
			tether_drag_t = 0.18
		return moved
	return 0.0


## How strongly the roped creature's outline glows right now: a slow red pulse, 0.35 to 1 about every 1.4 s.
## Whether the Gravity Gun may take creature `i` (pass 35): an ordinary creature on its feet; never a boss, an Elite,
## an elite-modded one, a special (EnemyDef.can_be_grabbed false: the rocketeer, the harpooner) or one already held.
func grabbable(i: int) -> bool:
	if i < 0 or i >= MAX or alive[i] == 0 or state[i] == STATE_DYING or hidden[i] == 1 or held[i] == 1:
		return false
	if lift_t[i] > 0.0 or i == boss_index or elite_idx[i] >= 0 or i == tethered_i:
		return false
	var def: EnemyDef = types[type_idx[i]]["def"]
	return def.archetype != "boss" and def.archetype != "elite" and def.can_be_grabbed


## Into the grip: out of the crowd until `release`.
func grab(i: int) -> void:
	held[i] = 1
	vel[i] = Vector3.ZERO
	kb[i] = Vector3.ZERO
	charge_dir[i] = Vector3.ZERO
	state[i] = STATE_MOVE
	timer[i] = 0.0
	flash[i] = 0.8


## Where a held creature is (the Gravity Gun moves it through here: a write to `pos` from outside copies the array):
## `at` is where it floats, pos stays on the ground under it and lift_h carries the height. `wriggle` > 0 squashes it.
func place_held(i: int, at: Vector3, wriggle: float = -1.0, turn: bool = false) -> void:
	var gy := _height(at.x, at.z)
	pos[i] = Vector3(at.x, gy, at.z)
	lift_h[i] = maxf(at.y - gy, 0.0)
	if wriggle > 0.0:
		squash[i] = wriggle
	if turn:
		flip[i] = 1 - flip[i]


## The Singularity's drag (pass 35): everything within `r` of `center` moves up to `speed_mps` towards it this frame,
## harder near the middle; bosses and Elites at a fifth. A held or buried creature is out of the grid and stays put.
func drag_radius(center: Vector3, r: float, speed_mps: float, delta: float) -> void:
	for e in indices_in_radius(center, r):
		if state[e] == STATE_DYING or lift_t[e] > 0.0:
			continue
		var d := center - pos[e]
		d.y = 0.0
		var dist := d.length()
		if dist < 0.25:
			continue
		var strength: float = speed_mps * (0.45 + 0.55 * (1.0 - dist / maxf(r, 0.1)))
		var def: EnemyDef = types[type_idx[e]]["def"]
		if e == boss_index or def.archetype == "boss" or def.archetype == "elite":
			strength *= 0.2
		var np := pos[e] + d / dist * minf(strength * delta, dist - 0.2)
		np.y = _height(np.x, np.z)
		pos[e] = np


## Out of the grip, on the ground where the gun left it (pos), a little squashed from the landing.
func release(i: int) -> void:
	if i < 0 or i >= MAX:
		return
	held[i] = 0
	lift_h[i] = 0.0
	if alive[i] == 1 and state[i] != STATE_DYING:
		pos[i].y = _height(pos[i].x, pos[i].z)
		vel[i] = Vector3.ZERO
		kb[i] = Vector3.ZERO
		squash[i] = 0.5
		cooldown[i] = maxf(cooldown[i], 0.6)


func tether_glow() -> float:
	return 0.35 + 0.65 * (0.5 + 0.5 * sin(_glow_clock * 4.5))


## Pass 69 (lane EN): a variance special's glow (0..1) as the shader reads it off INSTANCE_CUSTOM.y: 16 levels in steps of
## SPECIAL_GLOW_STEP above the flip bit and the tether's glow (1 + 2 x 16 < 64), so mod(y, 2) is still the flip
## (enemy_silhouette) and mod(y, 64) the rest (enemy_billboard). Whole numbers to 1057: exact in a half float too.
const SPECIAL_GLOW_STEP := 64.0
static func special_glow_code(glow: float) -> float:
	return SPECIAL_GLOW_STEP * roundf(clampf(glow, 0.0, 1.0) * 16.0)


func boss_alive() -> bool:
	return boss_index >= 0


func position_of(i: int) -> Vector3:
	return pos[i]


func is_alive(i: int) -> bool:
	return i >= 0 and i < MAX and alive[i] == 1 and state[i] != STATE_DYING


# ---------------------------------------------------------------- simulation

func _physics_process(delta: float) -> void:
	if player == null:
		return
	var t0 := Time.get_ticks_usec()
	_tick += 1
	# every creature steers every other tick, as before, but half of the crowd on each tick (pass 33.8: all of them on
	# the even ticks made every other frame three times the cost of the one between)
	var parity := _tick & 1
	_rebuild_grid()
	_obstacle_cells()
	_cf_tick = _camera_forward()
	refresh_onscreen(parity)
	# the pace knob (pass 48): read once a tick, and never folded into the shared delta below (poison and fire ticks and
	# the cooldowns keep their clocks); walks, charges and rolls, wind-ups and warnings carry it themselves. Times the
	# timeline's creature_speed_mult (pass 60): the creatures' own knob, the hero's pace untouched
	pace = Run.move_pace() * creature_speed_mult
	# pass 80 (lane OASIS): the lakes and the water's slow, who wades this tick (_wade_k)
	_wade_tick()
	# High Noon slows the whole crowd's clock: steering, attacks, animations
	delta *= time_scale
	var ppos: Vector3 = player.global_position
	var sdt := delta * 2.0
	tether_drag_t = maxf(tether_drag_t - delta, 0.0)
	_glow_clock += delta
	_hot_chest_cd = maxf(_hot_chest_cd - delta, 0.0)
	# the hero's numbers once a tick instead of once per creature (Rattle's slow, read 150 times a frame at the new caps;
	# pass 47: Ducktape, Big Game Hunter, Hot Sauce and White Phosphorus with it)
	_pstats_dirty = true
	_pstats()
	# the crowd's numbers, kept as the loop passes (pass 48): its mean max HP (priority_index) and the poisoned (Gas Mask)
	var crowd_hp := 0.0
	var crowd_n := 0
	var poisoned := 0
	for i in range(MAX):
		if alive[i] == 0:
			continue
		var ti := type_idx[i]
		if state[i] == STATE_DYING:
			# the death plays through its frames (the fall, then the painted body), holds, and sinks away at the end
			timer[i] -= delta
			anim_t[i] += delta * _t_die_fps[ti]
			flash[i] = max(flash[i] - delta * 6.0, 0.0)
			if timer[i] < DIE_SINK:
				squash[i] = maxf(timer[i] / DIE_SINK, 0.02)
			# pass 69: a body killed up in a launch falls to the sand while its death plays
			if lift_h[i] > 0.0 and _launch_of(i):
				_drop_launched_body(i, delta)
			# pass 79 (lane FX): the body slides on with its push, or flies from a blast
			_corpse_tick(i, delta)
			if timer[i] <= 0.0:
				_free(i)
			continue
		crowd_hp += max_hp[i]
		crowd_n += 1
		if not (poison_src[i] as Dictionary).is_empty():
			poisoned += 1
		if held[i] == 1:
			# in the Gravity Gun's grip: its legs go, nothing else (the gun places it)
			anim_t[i] += delta * 20.0
			flash[i] = max(flash[i] - delta * 3.0, 0.0)
			squash[i] = lerp(squash[i], 1.0, delta * 6.0)
			continue
		if lift_t[i] > 0.0 and _launch_of(i):
			# pass 69: Alley-Oop's launch, its own flight (no brain, no bite) and its landing's damage
			_tick_launch(i, delta)
			continue
		if lift_t[i] > 0.0 and lift_mode[i] == 1:
			# a bounce (pass 46): up and down on the spot, no spin, no turn; it lands squashed, with its shove and no harm
			lift_t[i] -= delta
			var fb := 1.0 - clampf(lift_t[i] / maxf(lift_d[i], 0.01), 0.0, 1.0)
			lift_h[i] = sin(fb * PI) * lift_peak[i]
			vel[i] = Vector3.ZERO
			if lift_t[i] <= 0.0:
				lift_h[i] = 0.0
				lift_mode[i] = 0
				squash[i] = 0.7
				flash[i] = maxf(flash[i], 0.3)
				lift_cd[i] = 0.3
				if lift_knock[i].length_squared() > 0.0:
					kb[i] = lift_knock[i]
				lift_knock[i] = Vector3.ZERO
				var fx = game.get("fx") if game != null else null
				if fx != null and fx.has_method("sand"):
					fx.sand(pos[i], 0.5)
			continue
		if lift_t[i] > 0.0:
			# tossed by a tornado: rises, spins, drops, then lands with a thump; no steering meanwhile
			lift_t[i] -= delta
			var f := 1.0 - clampf(lift_t[i] / maxf(lift_d[i], 0.01), 0.0, 1.0)
			lift_h[i] = sin(f * PI) * 3.2 * maxf(size[i], 0.6)
			lift_a[i] += delta * 7.0
			anim_t[i] += delta * 14.0
			flip[i] = 1 if int(lift_a[i] * 1.5) % 2 == 0 else 0
			vel[i] = Vector3.ZERO
			if lift_t[i] <= 0.0:
				# thrown out and away, and immune to the next grab for a while so it cannot get stuck in the funnel
				lift_h[i] = 0.0
				squash[i] = 0.55
				flash[i] = 0.6
				lift_cd[i] = 4.0
				kb[i] = Vector3(cos(lift_a[i]), 0, sin(lift_a[i])) * 12.0 * hero_knock_mult()
				damage(i, max_hp[i] * 0.08, "", Vector3.ZERO, 0.0)
			continue
		if lift_cd[i] > 0.0:
			lift_cd[i] -= delta
		if state[i] == STATE_SPAWN:
			timer[i] -= delta
			squash[i] = lerp(squash[i], 1.0, delta * 10.0)
			# pass 73 (lane GROUND): growing out of the ground, the spawn state lasting the rise
			_tick_emerge(i, delta)
			if timer[i] <= 0.0:
				state[i] = STATE_MOVE
			continue
		# decay flash and squash
		flash[i] = max(flash[i] - delta * 6.0, 0.0)
		squash[i] = lerp(squash[i], 1.0, delta * 10.0)
		# a hampered creature's attack clocks run slow (pass 48, hamper); the hamper and a held tint run out on its clock
		var ac := attack_clock(i)
		contact_cd[i] = max(contact_cd[i] - delta * ac, 0.0)
		cooldown[i] = max(cooldown[i] - delta * ac, 0.0)
		if hamper_t[i] > 0.0:
			hamper_t[i] = maxf(hamper_t[i] - delta, 0.0)
		if status_t[i] > 0.0:
			status_t[i] = maxf(status_t[i] - delta, 0.0)
		if shove_t[i] > 0.0:
			shove_t[i] -= delta
		if ign_t[i] > 0.0:
			ign_t[i] -= delta
		# coming up out of the sand (pass 60): RISE_TIME at the creatures' pace, then it is up; pass 73 (lane GROUND): at
		# its own rate (rise_v), or sinking into it (a visible burrow)
		if rise_t[i] < 1.0 or rise_v[i] != 0.0:
			_tick_rise(i, delta)
		if view_t[i] > 0.0:
			view_t[i] -= delta
		if (i & 1) == parity:
			_steer(i, decoy_target(i, ppos), sdt)
		# integrate (pass 80: its own move wades at water_slow slower, a push never)
		var v := vel[i] * _wade_k[i] + kb[i]
		kb[i] = kb[i].lerp(Vector3.ZERO, delta * 6.0)
		var np := pos[i] + v * delta
		np = _clamp_arena(np)
		np.y = _height(np.x, np.z)
		pos[i] = np
		# the direction the creature faces: where it charges while winding up or charging, else where it moves
		var face := v
		if _t_faces[ti] == 1:
			# a creature that fights at range faces where its brain means to go (pass 60), never where the crowd shoves it
			# or a hit knocks it: the Sun Prophet turned his back on every knock and snapped round the next tick
			face = intent[i]
		if (state[i] == STATE_WINDUP or state[i] == STATE_CHARGE) and charge_dir[i].length_squared() > 0.01:
			face = charge_dir[i]
		else:
			if state[i] == STATE_ATTACK:
				# a scripted attack keeps the facing it started with: the crowd shoving it is not a turn (pass 47)
				face = Vector3.ZERO
			if face.length_squared() <= 0.04 and player and _t_faces[ti] == 1:
				# standing still: a creature that fights at range turns to face the hero (the centipede's eight views)
				var tf := player.global_position - pos[i]
				tf.y = 0.0
				face = tf
		if _t_eight[ti] == 1:
			if face.length_squared() > 0.04:
				var cf := _cf_tick
				var cr := Vector3(-cf.z, 0, cf.x)   # screen-right
				var fwd := face.dot(cf)
				var right := face.dot(cr)
				var a := absf(atan2(right, fwd))     # 0 = walking away from the camera, PI = towards it
				# the view it would show, and the one it shows: a creature heading between two views (up and to the
				# left, say) keeps the one it has until the heading is VIEW_HYST past the boundary (pass 43: the eight-way
				# creatures used to flick between two sets every tick there)
				var want := 0
				if a < PI * 0.125:
					want = 1
				elif a < PI * 0.375:
					want = 3
				elif a < PI * 0.625:
					want = 2
				elif a < PI * 0.875:
					want = 4
				var cur := int(view[i])
				if want != cur:
					var lo: float = VIEW_LO[cur]
					var hi: float = VIEW_HI[cur]
					if a >= lo - VIEW_HYST and a <= hi + VIEW_HYST:
						want = cur
					elif view_t[i] > 0.0:
						# a view holds VIEW_MIN after a change (pass 60): no set flicks back and forth within a quarter second
						want = cur
					else:
						view_t[i] = VIEW_MIN
				view[i] = want
				# side and diagonal sets face screen-right; mirror them when heading left, with a dead band about
				# straight up and down so a heading that wobbles about the vertical never flips the picture
				var len := face.length()
				if right < -FLIP_BAND * len:
					flip[i] = 1
				elif right > FLIP_BAND * len:
					flip[i] = 0
		else:
			var lenf := face.length()
			if face.x < -FLIP_BAND * lenf:
				flip[i] = 1
			elif face.x > FLIP_BAND * lenf:
				flip[i] = 0
			# walking away from the camera shows the back-view set (the camera forward is world -Z in fixed mode)
			if face.length_squared() > 0.04:
				var cf := _cf_tick
				away[i] = 1 if face.dot(cf) > face.length() * 0.2 else (0 if face.dot(cf) < -face.length() * 0.2 else away[i])
		_tick_poison(i, delta)
		if alive[i] == 0:
			continue
		_tick_fire(i, delta)
		if alive[i] == 0:
			continue
		# walk cycles cut from video clips carry their own frame rate (EnemyDef.fps); the old six-frame walks run at 10. A
		# creature standing to attack (a wind-up, a scripted attack) plays its frames at ATTACK_FPS whatever shoves it
		# (pass 47: the crowd pressing on the Tumbleweed King made every other tick a walking one, so the two frames of
		# his wind-up before the minion ring flicked at 9 a second instead of 3). The walk plays at the pace knob too (pass
		# 48): a creature that covers 0.8 of the ground a second takes 0.8 of the steps, so its feet keep to the sand
		var run_fps: float = _t_run_fps[ti]
		# a creature that fights at range walks when its brain walks it (pass 60, intent), not when the crowd shoves it
		var mv: Vector3 = intent[i] if _t_faces[ti] == 1 else v
		var walking: bool = mv.length() > 0.2 and state[i] != STATE_ATTACK and state[i] != STATE_WINDUP
		var steps: float = (run_fps if run_fps > 0.0 else 10.0) * pace if walking else ATTACK_FPS
		# a charger's legs (pass 50, charge.legs): they scrabble in place through the wind-up, from the walk's speed up to
		# `legs` times it by the launch, and run at `legs` times it through the charge (at the walk's speed the beetle's
		# feet slid over the sand at seven times their pace)
		var legs: float = _t_cv[ti * CV_N + 2]
		if legs > 1.0 and (state[i] == STATE_WINDUP or state[i] == STATE_CHARGE):
			var lf: float = legs if state[i] == STATE_CHARGE else lerpf(1.0, legs, windup_progress(i))
			steps = (run_fps if run_fps > 0.0 else 10.0) * pace * lf
		anim_t[i] += delta * steps
		# pass 69 (lane HERO): a creature fooled by May's inflatable double bites the doll, never her (bites do nothing)
		if decoy_on and is_fooled(i):
			_decoy_bite(i)
			continue
		# contact damage
		var d := ppos - pos[i]
		d.y = 0.0
		var reach := radius[i] + 0.45
		# a training dummy's touch never reaches the hero (pass 48: even a 0 would be a hit, a flash and a shake), but a
		# melee one's does (pass 49: the arena's attackers, an Elite or Boss dummy set to melee)
		# (pass 60: one still rising out of the sand bites nobody until it is up)
		if d.length_squared() < reach * reach and contact_cd[i] <= 0.0 and hidden[i] == 0 and rise_t[i] >= 1.0 and freeze_t[i] <= 0.0 and stun_t[i] <= 0.0 and (_t_dummy[ti] == 0 or dummy_mode[i] == DUMMY_MELEE):
			# the bite's cadence is the creature's own (pass 53, EnemyDef.contact_cd; 0.6 for everyone before)
			contact_cd[i] = _t_ccd[ti]
			var extra := 1.0
			var cfx: Array = []
			if state[i] == STATE_CHARGE:
				extra = 1.5
				cfx.append("charge")
				# a charge that connects throws him aside (once a second, whatever else is landing)
				var kn := float((types[type_idx[i]]["def"] as EnemyDef).charge.get("knockback", 0.0))
				if kn > 0.0:
					cfx.append("knocked back")
				if kn > 0.0 and player and player.has_method("shove"):
					var away2 := ppos - pos[i]
					away2.y = 0.0
					if away2.length_squared() > 0.01:
						player.shove(away2.normalized() * kn)
			# Ram: at full momentum Buck is the wall; the creature is shoved (a resisting one by its share, pass 67) and
			# spiked, he is not touched. Pass 67: from the perk's `from` charge (0.99), the spikes `per_level` more a level
			if Run.has_perk("ram") and Run.momentum >= Run.perk_param("ram", "from", 0.99) and state[i] != STATE_CHARGE and i != boss_index:
				var away := pos[i] - ppos
				away.y = 0.0
				kb[i] += (away.normalized() if away.length_squared() > 0.01 else Vector3.FORWARD) * Run.perk_param("ram", "shove", 9.0) * _t_kbt[ti] * hero_knock_mult()
				var th: float = Run.player_sheet.get_stat("thorns", 0.0) * Run.perk_param("ram", "thorns_mult", 3.0) + Run.perk_param("ram", "flat", 12.0) + Run.perk_param("ram", "per_level", 0.0) * float(Run.card_level())
				damage(i, th, "", away, 0.0)
				if game:
					game.fx_burst(pos[i] + Vector3(0, size[i] * 0.5, 0), Color(0.95, 0.75, 0.4), 1.0)
				continue
			var touch: float = dmg[i] * extra
			# no touch takes more than contact_cap of his health (pass 46: a ring of brutes could land a one-shot); a
			# boss's weight is its own. A stand-in hero without max_hp (the headless tests) is not capped.
			if contact_cap > 0.0 and i != boss_index and (types[ti]["def"] as EnemyDef).archetype != "boss":
				var mhp = player.get("max_hp")
				if mhp != null:
					touch = minf(touch, float(mhp) * contact_cap)
			# the bite shoves him by the creature's own number (pass 54, bite_knock); Player.take_damage applies it to a hit
			# or a shield's catch, never to an evaded or an immune one
			var binfo := hit_info(i, "melee", cfx)
			binfo["knock"] = bite_knock(i)
			player.take_damage(touch, pos[i], binfo)
	_mean_max_hp = crowd_hp / float(crowd_n) if crowd_n > 0 else 0.0
	Run.poisoned_alive = poisoned
	_update_boss(delta, ppos)
	# pass 73 (lane SNIPER): the Saiga Snipers' aims, locks and shots
	_tick_snipers(delta, ppos)
	# the burrows' mounds swell with their wind-ups (pass 60), after the runner has moved the timers
	_tick_mounds()
	_ticks += 1
	Perf.add("enemies.sim", t0)


## The draw runs once per shown frame, and only when a tick has moved something since the last one (pass 33.8: it ran
## inside the physics tick, so a phone below 60 fps drew the crowd twice for every frame it showed).
func _process(_delta: float) -> void:
	# pass 77 (lane SIMRUN): the run sim's fast mode draws no crowd (the tick keeps every number, refresh_onscreen too)
	if player == null or _drawn == _ticks or Run.sim_mode:
		return
	_drawn = _ticks
	var t0 := Time.get_ticks_usec()
	_render()
	Perf.add("enemies.render", t0)


func _steer(i: int, ppos: Vector3, dt: float) -> void:
	var def: EnemyDef = types[type_idx[i]]["def"]
	var to_player := ppos - pos[i]
	to_player.y = 0.0
	var dist := to_player.length()
	var dir := to_player / dist if dist > 0.001 else Vector3.ZERO
	var desired := Vector3.ZERO
	var spd := speed[i]
	# a training dummy on its way home walks through the crowd (pass 48: one shoved past its neighbour in the row was
	# held off its spot by that neighbour for good); rocks still push it
	var ghost := false
	if frenzy_t[i] > 0.0:
		frenzy_t[i] -= dt
		spd *= 1.3
	if freeze_t[i] > 0.0:
		freeze_t[i] -= dt
	if stun_t[i] > 0.0:
		# stunned (pass 53): it stands where it is and nothing of its brain runs, no wind-up, no charge, no shot; its
		# knockback still carries it, and the crowd still steps round it
		stun_t[i] -= dt
		vel[i] = Vector3.ZERO
		intent[i] = Vector3.ZERO
		return
	if rise_t[i] < 1.0:
		# still coming up out of the sand (pass 60): it stands where it broke through until it is up, no walk, no wind-up
		vel[i] = Vector3.ZERO
		intent[i] = Vector3.ZERO
		return
	if slow_t[i] > 0.0:
		slow_t[i] -= dt
		# 1.0 is a pin (pass 46: the Spear's Pinning Throw): it stands where it was struck; every other slow is a third or less
		spd *= 1.0 - clampf(slow_f[i], 0.0, 1.0)
		# a slowed creature kicks up dust at its feet
		if game and int(slow_t[i] * 3.0) != int((slow_t[i] + dt) * 3.0):
			game.fx_burst(pos[i] + Vector3(0, 0.15, 0), Color(0.85, 0.72, 0.5), 0.45)
	if mark_t[i] > 0.0:
		mark_t[i] -= dt
		# the brand glows while the mark lasts
		flash[i] = maxf(flash[i], 0.35)
		flash_hot[i] = 1
	# Rattle: poisoned creatures drag their feet
	var pslow: float = _poison_slow
	if pslow > 0.0 and not (poison_src[i] as Dictionary).is_empty():
		spd *= 1.0 - clampf(pslow, 0.0, 0.9)
	if spin_t[i] > 0.0:
		# the twister: no walking, no biting, a slow drag towards where the sting came from
		spin_t[i] -= dt
		var tow := spin_to[i] - pos[i]
		tow.y = 0.0
		if tow.length() > 0.3:
			pos[i] += tow.normalized() * 0.6 * dt
		vel[i] = Vector3.ZERO
		intent[i] = Vector3.ZERO
		if game and int(spin_t[i] * 8.0) != int((spin_t[i] + dt) * 8.0):
			game.fx_burst(pos[i] + Vector3(0, size[i] * 0.3, 0), Color(0.95, 0.85, 0.55), 0.7)
		return
	# pass 73 (lane SNIPER): flee on hit: straight away from the hero, no brain while it runs (_flee_steer)
	if not _flee.is_empty() and _flee.has(i) and _flee_steer(i, dir, spd, dt):
		return
	match state[i]:
		STATE_WINDUP:
			# a hampered creature winds up slower (pass 48)
			timer[i] -= dt * attack_clock(i)
			desired = Vector3.ZERO
			if def.brain == "charge" and timer[i] > 0.0:
				_paw(i, dt)
			if timer[i] <= 0.0:
				if def.brain == "artillery":
					_fire_artillery(i, def, ppos)
					state[i] = STATE_MOVE
				elif def.brain == "kite" or def.brain == "boss" or def.brain == "ambush" or def.brain == "support" or def.brain == "dummy":
					# a ranged training dummy's spit too (pass 49): the only wind-up a dummy has
					_do_attack(i, def, ppos)
					state[i] = STATE_MOVE
				else:
					# the charge runs along the line that was telegraphed at the start of the wind-up; the hero
					# moving in the meantime is exactly what the telegraph is for
					# at the pace knob's speed and 1/pace as long (pass 48): the same ground as the line on the sand
					state[i] = STATE_CHARGE
					timer[i] = float(def.charge.get("duration", 0.7)) / pace
					if charge_dir[i].length_squared() < 0.01:
						charge_dir[i] = dir
					Audio.play(str(def.sfx.get("attack", "")), pos[i])
					_launch(i)
		STATE_ATTACK:
			desired = Vector3.ZERO
		STATE_CHARGE:
			if def.brain == "boss":
				# a scripted roll (the King, the Gila, the Brander): _update_attacks owns its clock and its end. This branch
				# ran the same timer a second time at the steer rate, so every roll ended at half its `duration`, and read
				# charge.speed (9: no boss has a charge block) on steer ticks instead of the attack's `speed` (pass 45)
				desired = charge_dir[i] * _scripted_speed(i, def)
			else:
				timer[i] -= dt
				desired = charge_dir[i] * float(def.charge.get("speed", 9.0)) * pace
				_charge_dust(i)
				if timer[i] <= 0.0:
					state[i] = STATE_MOVE
					cooldown[i] = float(def.charge.get("cooldown", 4.0))
					_skid(i)
		_:
			match def.brain:
				"kamikaze":
					# the mines blink: a slow red pulse while it walks, fast once it is winding up to go off
					# the mine's lamp: a hard red blink, on for a beat and off for a beat, not a gentle glow
					var blink: float = 1.0 if fmod(anim_t[i] * 0.6 + float(i), 2.0) < 0.85 else 0.0
					flash[i] = maxf(flash[i], blink * 0.75)
					flash_hot[i] = 1
					# a walking bomb: it runs at the hero and goes off when it gets there (a beat of warning first);
					# it keeps the swarmer's wobble so a pack still fans out instead of filing in
					var kwob := Vector3(sin(anim_t[i] * 1.7 + i), 0, cos(anim_t[i] * 1.3 + i * 0.7)) * 0.6
					desired = (dir + kwob * 0.45).normalized() * spd
					if timer[i] > 0.0:
						desired = Vector3.ZERO
						timer[i] -= dt * attack_clock(i)
						flash[i] = 1.0
						flash_hot[i] = 1
						if timer[i] <= 0.0:
							_blow_up(i, def)
					elif dist < float(def.kamikaze.get("trigger", 1.1)) + size[i] * 0.4:
						timer[i] = float(def.kamikaze.get("windup", 0.35)) / pace
						if game:
							game.telegraph_ring(pos[i], float(def.kamikaze.get("radius", 2.6)), timer[i], Color(0.93, 0.29, 0.36), true)
				"chase":
					desired = dir * spd
				"flock":
					var wob := Vector3(sin(anim_t[i] * 1.7 + i), 0, cos(anim_t[i] * 1.3 + i * 0.7)) * 0.6
					desired = (dir + wob * 0.5).normalized() * spd
				"artillery":
					# far off and still: a wind-up, a rocket, and it sits and watches while the rocket hunts; the
					# moment its rocket is gone (it hit, or burnt out) it reloads and winds up again, so there is always
					# one of his in the air (pass 33.3: it used to fire once and never again). Placed at its stand-off
					# when it spawns (_stand_off).
					desired = Vector3.ZERO
					# and he is lit: a slow warm pulse, so the one thing on the far side of the screen that matters
					# is not a speck among the crowd
					flash[i] = maxf(flash[i], 0.3 + 0.22 * sin(anim_t[i] * 2.2))
					flash_hot[i] = 1
					# pass 73 (lane SNIPER): a wind-up something dropped (a stun, a launch, a hit's flee) leaves him ready
					# again, not waiting for a rocket that never left
					if atk_i[i] == 1:
						atk_i[i] = 0
					if atk_i[i] == 2 and not (game and game.has_method("rocket_out") and game.rocket_out(i)):
						atk_i[i] = 0
						cooldown[i] = float(def.artillery.get("reload", 2.5))
					if atk_i[i] == 0 and cooldown[i] <= 0.0:
						atk_i[i] = 1
						state[i] = STATE_WINDUP
						timer[i] = float(def.artillery.get("windup", 1.4)) / pace
						charge_dir[i] = dir
						if game and game.has_method("telegraph_line"):
							game.telegraph_line(pos[i], dir, 5.0, timer[i], Color(0.93, 0.29, 0.36))
						Audio.play(str(def.sfx.get("attack", "")), pos[i])
				"sniper":
					# pass 73 (lane SNIPER): the Saiga Sniper keeps far off, runs from the hero, and aims (_sniper_steer)
					desired = _sniper_steer(i, def, dir, dist, spd)
				"kite":
					var keep := float(def.ranged.get("keep_distance", 5.0))
					var rng := float(def.ranged.get("range", 8.0))
					if tethered_i == i:
						# hauling on the rope: it braces where it stands (the hero drags it, it never walks)
						desired = Vector3.ZERO
					elif dist < keep - 0.5:
						desired = -dir * spd
					elif dist > rng:
						desired = dir * spd
					else:
						desired = Vector3.ZERO
						if cooldown[i] <= 0.0:
							state[i] = STATE_WINDUP
							timer[i] = float(def.ranged.get("telegraph", 0.6)) / pace
							_telegraph_shot(i, def, ppos, dir, dist)
				"charge":
					desired = dir * spd
					if cooldown[i] <= 0.0 and dist < float(def.charge.get("trigger_range", 6.0)):
						state[i] = STATE_WINDUP
						timer[i] = float(def.charge.get("windup", 0.8)) / pace
						charge_dir[i] = dir
						if game and game.has_method("telegraph_line"):
							game.telegraph_line(pos[i], dir, dist + 4.0, timer[i], Color(0.93, 0.29, 0.36))
				"boss":
					desired = dir * spd if atk_t[i] > 0.0 else Vector3.ZERO
				"dummy":
					# a training dummy (pass 48, the debug arena): it stands where it was put and walks back there at its
					# speed once it is shoved more than 0.3 m off, through the crowd. Pass 49 (set_dummy_mode): a patrolling
					# one walks its beat, through the crowd too; a melee one chases the hero while he is near its spot; a
					# ranged one winds up a spit at him in range (the kite brain's telegraph, fired from the wind-up above)
					var dm := int(dummy_mode[i])
					var busy := false
					if dm == DUMMY_MELEE:
						var from_home := ppos - home[i]
						from_home.y = 0.0
						if from_home.length() < DUMMY_CHASE:
							desired = dir * spd
							busy = true
					elif dm == DUMMY_RANGED and not def.ranged.is_empty() and freeze_t[i] <= 0.0:
						if dist < float(def.ranged.get("range", 8.0)) and cooldown[i] <= 0.0:
							state[i] = STATE_WINDUP
							timer[i] = float(def.ranged.get("telegraph", 0.6)) / pace
							_telegraph_shot(i, def, ppos, dir, dist)
							desired = Vector3.ZERO
							busy = true
					if not busy:
						if dm == DUMMY_PATROL or (dummy_roam[i] == 1 and dm != DUMMY_STAND):
							desired = _patrol(i, spd)
							ghost = true
						else:
							var to_home := home[i] - pos[i]
							to_home.y = 0.0
							var hd := to_home.length()
							desired = to_home / hd * spd if hd > 0.3 else Vector3.ZERO
							ghost = hd > 0.3
				"ambush":
					# under the sand until the hero is close, then out and straight at him; a chaser after that, and
					# back under when it loses him
					var am: Dictionary = def.ambush
					if hidden[i] == 1:
						desired = Vector3.ZERO
						if game and _rng.randf() < dt * 0.6:
							game.fx_burst(pos[i] + Vector3(0, 0.1, 0), Color(0.86, 0.72, 0.5), 0.4)
						if dist < float(am.get("trigger", 5.0)):
							# up out of the sand, and straight into a silk line at the hero
							hidden[i] = 0
							state[i] = STATE_WINDUP
							timer[i] = float(def.ranged.get("telegraph", 0.45)) / pace
							if game:
								game.fx_burst(pos[i] + Vector3(0, 0.3, 0), Color(0.9, 0.75, 0.5), 1.8)
								game.hint_once("spider", "TRAPDOOR SPIDER: its silk pulls you in. Step off the red line.")
							_telegraph_shot(i, def, ppos, dir, dist)
							Audio.play(str(def.sfx.get("attack", "")), pos[i])
					else:
						desired = dir * spd
						if cooldown[i] <= 0.0 and dist > float(am.get("rehide_distance", 12.0)):
							hidden[i] = 1
							cooldown[i] = float(am.get("rehide_after", 6.0))
							if game:
								game.fx_burst(pos[i] + Vector3(0, 0.2, 0), Color(0.86, 0.72, 0.5), 1.2)
						elif cooldown[i] <= 0.0 and dist > 2.5 and dist < float(def.ranged.get("range", 9.0)):
							state[i] = STATE_WINDUP
							timer[i] = float(def.ranged.get("telegraph", 0.45)) / pace
							_telegraph_shot(i, def, ppos, dir, dist)
				"caster":
					# the ranged Elite walks to a spot keep_distance off the hero ON his portrait screen (see
					# _screen_spot), so the player can see who is casting; the tricks are its attack list, run below
					# like a boss's
					var cs: Dictionary = def.caster
					var spot := _screen_spot(i, ppos, float(cs.get("keep_distance", 7.0)), float(cs.get("side", 4.5)))
					var to_spot := spot - pos[i]
					to_spot.y = 0.0
					var sd := to_spot.length()
					# standing to cast (hold_t, the Prophet's pillars) it stays put (pass 60: the walk to the spot on every
					# steer tick against the hold's stop on the others tore him between the two, a view flip a tick)
					desired = to_spot / sd * spd * clampf(sd / 1.5, 0.3, 1.0) if sd > 0.6 and hold_t[i] <= 0.0 else Vector3.ZERO
				"support":
					# keeps its distance and, every few seconds, mends whatever stands around it
					var su: Dictionary = def.support
					var keep := float(su.get("keep_distance", 7.0))
					var far := float(su.get("range", 10.0))
					if dist < keep - 0.5:
						desired = -dir * spd
					elif dist > far:
						desired = dir * spd
					else:
						desired = Vector3.ZERO
					if cooldown[i] <= 0.0:
						cooldown[i] = float(su.get("interval", 4.0))
						_support_pulse(i, float(su.get("radius", 5.0)), float(su.get("heal", 0.25)), float(su.get("frenzy_seconds", 3.0)))
						Audio.play(str(def.sfx.get("attack", "")), pos[i])
				_:
					desired = dir * spd
	# separation: the creatures in this cell and the eight around it
	var sep := Vector3.ZERO
	var my_r := radius[i]
	var gx := _gcol(pos[i].x)
	var gz := _gcol(pos[i].z)
	# a charger shoves what stands in its way out to the side (pass 50, charge.shove while it charges, shove_walk while it
	# walks): the heading it is pushing along, and how hard
	var shove := 0.0
	var head := Vector3.ZERO
	var cvb := type_idx[i] * CV_N
	if state[i] == STATE_CHARGE and def.brain == "charge" and _t_cv[cvb + 5] > 0.0:
		shove = _t_cv[cvb + 5]
		head = charge_dir[i]
	elif state[i] == STATE_MOVE and _t_cv[cvb + 6] > 0.0 and desired.length_squared() > 0.01:
		shove = _t_cv[cvb + 6]
		head = desired.normalized()
	# the cells round it: 3 x 3, more for a body so wide that a neighbour past the next cell can still touch it (the fix
	# round of pass 58: a size range's giants)
	var reach := 1
	if my_r > BIG_R:
		reach = maxi(ceili((my_r + _grid_max_r) / CELL), 1)
	for cx in range(maxi(gx - reach, 0), mini(gx + reach + 1, _gw)):
		if ghost:
			break
		for cz in range(maxi(gz - reach, 0), mini(gz + reach + 1, _gw)):
			var j := _g_head[cz * _gw + cx]
			while j >= 0:
				if j != i:
					var d := pos[i] - pos[j]
					d.y = 0.0
					var min_d := my_r + radius[j]
					var l2 := d.length_squared()
					if shove > 0.0 and shove_t[j] <= 0.0 and l2 < (min_d + SHOVE_REACH) * (min_d + SHOVE_REACH):
						_shove(i, j, d, head, shove)
					if l2 < min_d * min_d and l2 > 0.0001:
						var l := sqrt(l2)
						sep += d / l * (min_d - l) / min_d
				j = _g_next[j]
	# a narrow body also feels the wide ones whose edge reaches past its 3 x 3 (a boss, an Elite, a size range's giants),
	# while they are few (the fix round; a wide one sees it from its own side anyway)
	if not ghost and my_r <= BIG_R and not _big.is_empty() and _big.size() <= BIG_LIST_MAX:
		for j: int in _big:
			if j == i or (absi(_gcol(pos[j].x) - gx) <= 1 and absi(_gcol(pos[j].z) - gz) <= 1):
				continue
			var d := pos[i] - pos[j]
			d.y = 0.0
			var min_d := my_r + radius[j]
			var l2 := d.length_squared()
			if l2 < min_d * min_d and l2 > 0.0001:
				var l := sqrt(l2)
				sep += d / l * (min_d - l) / min_d
	sep += _obstacle_push(i)
	var sep_w := 4.0 if state[i] != STATE_CHARGE else 0.5
	vel[i] = desired + sep * sep_w
	# what the brain meant, before the crowd's push (pass 60): a ranged creature's facing and walk read this
	intent[i] = desired


## Creature `j` shoved aside by charger `i` heading `head` (pass 50, Garry: "push enemies out of the way, always to the
## side, and only a little bit (enough for it to be noticeable, not enough to change the course of enemies movement)"):
## only one ahead of it or beside it, never one it has passed; straight out to the side it stands on (one dead ahead goes
## the way its index says, so a file splits both ways); `force` metres a second whatever its weight, about half a metre
## aside before it walks on (knockback dies away at 6 a second); never a boss, an Elite, one in the air or one bigger
## than the charger. It flinches (a squash) and, under a charge, scuffs a little sand. `d` = pos[i] - pos[j].
func _shove(i: int, j: int, d: Vector3, head: Vector3, force: float) -> void:
	var rel := -d
	if rel.dot(head) < -radius[i] * 0.3:
		return
	if j == boss_index or _t_big[type_idx[j]] == 1 or lift_t[j] > 0.0 or size[j] > size[i] * 1.05:
		return
	var side := Vector3(-head.z, 0.0, head.x)
	var across := rel.dot(side)
	var sgn := 1.0 if across > 0.02 else (-1.0 if across < -0.02 else (1.0 if (j & 1) == 0 else -1.0))
	kb[j] += side * (sgn * force)
	shove_t[j] = SHOVE_GRACE
	squash[j] = minf(squash[j], 0.86)
	if state[i] == STATE_CHARGE and game:
		var fx = game.get("fx")
		if fx and fx.has_method("shove_dust"):
			fx.shove_dust(pos[j], side * sgn)


## How far creature `i` is through its charge's wind-up (pass 50): 0 at the start, 1 at the launch.
func windup_progress(i: int) -> float:
	var total: float = _t_cv[type_idx[i] * CV_N + 7] / maxf(pace, 0.05)
	return clampf(1.0 - timer[i] / maxf(total, 0.01), 0.0, 1.0)


## The sand a charger with `charge.dust` paws back while it winds up (pass 50): from a fifth of the way in, more often
## and harder towards the launch.
func _paw(i: int, dt: float) -> void:
	var dust: float = _t_cv[type_idx[i] * CV_N + 4]
	if dust <= 0.0 or game == null:
		return
	var f := windup_progress(i)
	if f < 0.2 or _rng.randf() > dt * lerpf(4.0, 12.0, f):
		return
	var fx = game.get("fx")
	if fx and fx.has_method("paw_dust"):
		var back := -charge_dir[i]
		fx.paw_dust(pos[i] + back * radius[i] * 0.6, back, radius[i] * 1.2, dust * f)


## The launch (pass 50): it springs out of its crouch stretched long, with a burst of sand thrown back.
func _launch(i: int) -> void:
	var t := type_idx[i] * CV_N
	if _t_cv[t + 1] > 0.0:
		squash[i] = 1.0 + _t_cv[t + 1] * 1.6
	if _t_cv[t + 4] > 0.0 and game:
		var fx = game.get("fx")
		if fx and fx.has_method("charge_launch"):
			fx.charge_launch(pos[i] - charge_dir[i] * radius[i] * 0.6, -charge_dir[i], radius[i] * 1.2, _t_cv[t + 4])


## One beat of a charger's dust trail (pass 50, Garry: "a dust trail effect behind the Beetle as it runs"), every time it
## steers through its charge (thirty a second).
func _charge_dust(i: int) -> void:
	var dust: float = _t_cv[type_idx[i] * CV_N + 4]
	if dust <= 0.0 or game == null:
		return
	var fx = game.get("fx")
	if fx and fx.has_method("charge_dust"):
		var back := -charge_dir[i]
		fx.charge_dust(pos[i] + back * radius[i] * 0.7, back, radius[i] * 1.3, dust)


## The end of a charge (pass 50): it digs in squashed, pushing a little sand out ahead of it.
func _skid(i: int) -> void:
	var t := type_idx[i] * CV_N
	if _t_cv[t + 1] > 0.0:
		squash[i] = 1.0 - _t_cv[t + 1]
	if _t_cv[t + 4] > 0.0 and game:
		var fx = game.get("fx")
		if fx and fx.has_method("skid_dust"):
			fx.skid_dust(pos[i] + charge_dir[i] * radius[i] * 0.5, charge_dir[i], radius[i] * 1.3, _t_cv[t + 4])


## Creature `i`'s carriage through its charge (pass 50, Garry: the Bull Beetle's charge "feels too static"), as the render
## draws it and a test reads it: x metres along the screen's right (`scr`), y metres up, z the squash it multiplies in,
## w the roll about its feet in radians (the billboard shaders read the angle of the instance's x column). Winding up it
## crouches (charge.crouch, all the way down by 40% of the wind-up), rocks on its feet and shakes from side to side,
## harder and harder up to charge.shake metres at the launch; charging it bounces at every step with a little squash and
## stretch, rumbles, and leans into the run (charge.lean: the full angle heading straight across the screen, none heading
## up or down it, where a lean cannot show). Vector4(0, 0, 1, 0) for anything else.
func charge_pose(i: int, scr: Vector3) -> Vector4:
	var t := type_idx[i] * CV_N
	var shake: float = _t_cv[t]
	var crouch: float = _t_cv[t + 1]
	var lean: float = _t_cv[t + 3]
	var clock := _glow_clock + float(i) * 0.37
	if state[i] == STATE_WINDUP and (shake > 0.0 or crouch > 0.0):
		var f := windup_progress(i)
		var shk := shake * (0.25 + 0.75 * f * f) * (0.7 * sin(clock * TAU * 17.0) + 0.3 * sin(clock * TAU * 29.0 + 1.3))
		var rock := ROCK * f * sin(clock * TAU * 9.0) if shake > 0.0 else 0.0
		return Vector4(shk, 0.0, 1.0 - crouch * smoothstep(0.0, 0.4, f), rock)
	if state[i] == STATE_CHARGE and (shake > 0.0 or lean != 0.0 or crouch > 0.0):
		var ph := anim_t[i] * PI / 6.0
		return Vector4(shake * 0.25 * sin(clock * TAU * 23.0), absf(sin(ph)) * BOUNCE * size[i], 1.0 + 0.05 * cos(ph * 2.0),
			-lean * charge_dir[i].dot(scr))
	return Vector4(0.0, 0.0, 1.0, 0.0)


## The instance basis of a creature `s` metres tall rolled `roll` radians about its feet (pass 50, a charger's rock and
## lean): the billboard shaders read the columns' lengths as its size and the angle of the x column as the roll.
static func roll_basis(s: float, roll: float) -> Basis:
	return Basis(Vector3(cos(roll), sin(roll), 0.0) * s, Vector3(-sin(roll), cos(roll), 0.0) * s, Vector3(0.0, 0.0, s))


## A patrolling training dummy's walk (pass 49): towards the end of its beat it is heading for, DUMMY_BEAT metres east or
## west of its spot on the spot's line, turning round once it is level with that end. Shoved off, it carries on from
## where it landed and comes back onto the line on its way to the end. The velocity it wants, at `spd`.
func _patrol(i: int, spd: float) -> Vector3:
	var end_x := home[i].x + DUMMY_BEAT * patrol_dir[i]
	if (end_x - pos[i].x) * patrol_dir[i] <= 0.15:
		patrol_dir[i] = -patrol_dir[i]
		end_x = home[i].x + DUMMY_BEAT * patrol_dir[i]
	var to := Vector3(end_x - pos[i].x, 0.0, home[i].z - pos[i].z)
	var l := to.length()
	return to / l * spd if l > 0.01 else Vector3.ZERO


func _do_attack(i: int, def: EnemyDef, ppos: Vector3) -> void:
	cooldown[i] = float(def.ranged.get("cooldown", 2.5))
	Audio.play(str(def.sfx.get("attack", "")), pos[i])
	if game == null:
		return
	var from := pos[i] + Vector3(0, size[i] * 0.6, 0)
	if def.ranged.has("cone_deg"):
		# a cone of pellets across the wedge, each its own short straight shot
		var n := maxi(int(def.ranged.get("count", 5)), 1)
		var cone := deg_to_rad(float(def.ranged.get("cone_deg", 50.0)))
		for k in range(n):
			var a := -cone * 0.5 + cone * (float(k) + 0.5) / float(n)
			var target := pos[i] + charge_dir[i].rotated(Vector3.UP, a) * 12.0
			game.enemy_shot_straight(from, target, float(def.ranged.get("projectile_speed", 16.0)), dmg[i], float(def.ranged.get("splash", 0.45)), {"life": float(def.ranged.get("life", 0.45)), "shot": str(def.ranged.get("shot", "")), "knockback": float(def.ranged.get("knockback", 0.0)), "info": hit_info(i, "ranged", ["buckshot"])})
		if game.has_method("fx_burst"):
			game.fx_burst(from + charge_dir[i] * 0.8, Color(1.0, 0.8, 0.4), 1.3)
		return
	if bool(def.ranged.get("straight", false)):
		# along the telegraphed line, where the hero stood when the wind-up started
		var target := pos[i] + charge_dir[i] * 12.0
		var params := {"life": float(def.ranged.get("life", 1.4)), "shot": str(def.ranged.get("shot", "")),
			"knockback": float(def.ranged.get("knockback", 0.0)), "info": hit_info(i, "ranged", [])}
		if def.ranged.has("pull"):
			params["pull"] = float(def.ranged["pull"])
		if bool(def.ranged.get("harpoon", false)):
			# a harpoon on a rope: the hit tethers the hero to whoever threw it (Game.tether_start)
			params["harpoon"] = true
			params["shooter"] = i
			params["tether"] = def.ranged.get("tether", {})
		game.enemy_shot_straight(from, target, float(def.ranged.get("projectile_speed", 12.0)), dmg[i], float(def.ranged.get("splash", 0.8)), params)
	elif game.has_method("enemy_spit"):
		game.enemy_spit(from, ppos, float(def.ranged.get("projectile_speed", 6.0)), dmg[i], float(def.ranged.get("splash", 1.2)), hit_info(i, "ranged", ["spit"]))


## The rocketeer's shot: a slow rocket that hunts the hero and goes loose only when he dies (Game.enemy_missile). It
## leaves the launcher's open end (muzzle_point, pass 48).
func _fire_artillery(i: int, def: EnemyDef, ppos: Vector3) -> void:
	var ms: Dictionary = def.artillery.get("missile", {})
	if game and game.has_method("enemy_missile"):
		game.enemy_missile(i, muzzle_point(i, ppos - pos[i]), float(ms.get("speed", 4.0)), float(ms.get("turn", 1.3)),
			float(ms.get("damage", 22.0)) * stage_of(i) * lvd_of(i) * host_of(i), float(ms.get("area", 1.6)),
			float(ms.get("speed_of_hero", 0.0)), hit_info(i, "ranged", ["rocket"]), ms)
	atk_i[i] = 2
	Audio.play(str(def.sfx.get("attack", "")), pos[i])


## Where creature `i`'s rocket leaves (pass 48, the Vulture Raider: "the rocket appears at the open end of the tube"): the
## def's `artillery.muzzle` {up, side, forward}, metres measured on the painting at the def's size and scaled with this
## spawn's. `up` runs up the painting (the billboard's own up, the camera's: a point high on a figure is up and a little
## north of his feet); `side` is towards the hand that holds the launcher, his right: screen-left in the front painting,
## screen-right in the back one, and the other way round when the picture is mirrored (the strip and the mirror bit the
## render would draw him with this tick); `forward` is along `aim` (towards the hero), out of the painting's plane, so the
## rocket starts in front of a figure facing the camera and behind one walking away. Without a muzzle, 0.8 of his size
## straight up, as it was.
func muzzle_point(i: int, aim: Vector3 = Vector3.ZERO) -> Vector3:
	var def: EnemyDef = types[type_idx[i]]["def"]
	var mz = def.artillery.get("muzzle", {})
	if not (mz is Dictionary) or (mz as Dictionary).is_empty():
		return pos[i] + Vector3(0, size[i] * 0.8, 0)
	var k: float = size[i] / maxf(def.size, 0.01)
	var t := type_idx[i]
	var strip := _strip_of(i, t)
	var sgn := -1.0
	if _face_bit(flip[i], t, strip) > 0.5:
		sgn = -sgn
	if strip == 5 or strip == 6:
		sgn = -sgn
	var scr := Vector3(-_cf_tick.z, 0, _cf_tick.x)
	var cam_up := _cam_up()
	var a := Vector3(aim.x, 0, aim.z)
	a = a.normalized() if a.length_squared() > 0.0001 else Vector3.ZERO
	var at := pos[i] + Vector3(0, lift_h[i], 0) - sprite_sink(i, 1.0, cam_up)
	return at + cam_up * (float(mz.get("up", 0.0)) * k) + scr * (sgn * float(mz.get("side", 0.0)) * k) + a * (float(mz.get("forward", 0.0)) * k)


## An artillery creature spawns at its stand-off from the hero, never closer, inside the wall.
func _stand_off(i: int, def: EnemyDef) -> void:
	if player == null:
		return
	var so := float(def.artillery.get("stand_off", 28.0))
	var pp: Vector3 = player.global_position
	var d := pos[i] - pp
	d.y = 0.0
	if d.length_squared() < 0.01:
		d = Vector3.FORWARD
	if d.length() < so:
		var np: Vector3 = pp + d.normalized() * so
		if game and game.map and game.map.has_method("clamp_to_arena"):
			np = game.map.clamp_to_arena(np)
		pos[i] = Vector3(np.x, _height(np.x, np.z), np.z)
	atk_i[i] = 0
	cooldown[i] = 0.6


## A walking bomb goes off: the blast (Game.elite_explosion also hurts the crowd), then it dies without its death burst
## firing a second time.
func _blow_up(i: int, def: EnemyDef) -> void:
	var km: Dictionary = def.kamikaze
	if game and game.has_method("elite_explosion"):
		game.elite_explosion(pos[i], float(km.get("radius", 2.6)), float(km.get("damage", 26.0)) * stage_of(i) * lvd_of(i) * host_of(i),
			0.0, float(km.get("knockback", 9.0)), 0.2, hit_info(i, "melee", ["mine"]))
	blown[i] = 1
	_die(i, "")


## A shaman's mend: every creature within `r` of it (not itself, never a boss) heals `frac` of its max HP and flashes.
func _support_pulse(i: int, r: float, frac: float, frenzy_seconds: float) -> void:
	var n := 0
	for j in indices_in_radius(pos[i], r):
		if j == i or j == boss_index:
			continue
		hp[j] = minf(hp[j] + max_hp[j] * frac, max_hp[j])
		frenzy_t[j] = frenzy_seconds
		flash[j] = 0.7
		flash_green[j] = 1
		n += 1
		if game:
			game.fx_burst(pos[j] + Vector3(0, size[j] * 0.7, 0), Color(0.5, 1.0, 0.55), 0.7)
	if game:
		game.telegraph_ring(pos[i], r, 0.6, Color(0.45, 0.9, 0.55), true)
		game.fx_burst(pos[i] + Vector3(0, size[i] * 0.9, 0), Color(0.5, 1.0, 0.6), 1.6)
		if n > 0:
			game.hint_once("shaman", "DUST SHAMAN: it mends and drives its pack (green ring). Kill it first.")


## The wind-up mark for a ranged creature: a red line along a straight shot, a red ring where a lob will land.
func _telegraph_shot(i: int, def: EnemyDef, ppos: Vector3, dir: Vector3, dist: float) -> void:
	if game == null:
		return
	if def.ranged.has("cone_deg"):
		# the dwarf's wedge: everything inside it is about to be peppered
		charge_dir[i] = dir
		game.telegraph_sector(pos[i], dir, float(def.ranged.get("range", 5.0)) + 1.5, float(def.ranged.get("cone_deg", 50.0)), timer[i], Color(0.93, 0.29, 0.36))
	elif bool(def.ranged.get("straight", false)):
		var aim := dir
		if bool(def.ranged.get("lead", false)) and player:
			# the harpooner leads its throw: where the hero will be when the harpoon gets there, at his current pace
			var v: Vector3 = player.velocity
			v.y = 0.0
			# the throw flies on the paced shot clock (pass 48), so it is 1/pace as long in the air
			var flight: float = (dist + 1.0) / maxf(float(def.ranged.get("projectile_speed", 12.0)) * pace, 1.0) + timer[i] * 0.5
			var at := ppos + v * flight
			var to := at - pos[i]
			to.y = 0.0
			if to.length_squared() > 0.01:
				aim = to.normalized()
		charge_dir[i] = aim
		game.telegraph_line(pos[i], aim, minf(dist + 4.0, float(def.ranged.get("range", 9.0)) + 4.0), timer[i], Color(0.93, 0.29, 0.36))
	else:
		game.telegraph_ring(ppos, float(def.ranged.get("splash", 1.2)), timer[i], Color(0.93, 0.29, 0.36))


## The Djinn's rain: every `interval` a strike is placed (the first on the hero, the rest scattered around where he
## is right then) with a red ring, and lands `warn` later: damage in the ring, a bolt and a burst.
func _tick_rains(delta: float, ppos: Vector3) -> void:
	if _rains.is_empty():
		return
	var keep: Array = []
	for r in _rains:
		r["next"] -= delta
		if r["next"] <= 0.0 and int(r["left"]) > 0:
			r["next"] = float(r["interval"])
			r["left"] = int(r["left"]) - 1
			var at := ppos
			if not bool(r["first"]):
				var sp: float = float(r["spread"])
				at = ppos + Vector3(randf_range(-sp, sp), 0, randf_range(-sp, sp))
			r["first"] = false
			at.y = _height(at.x, at.z)
			if game:
				game.telegraph_ring(at, float(r["radius"]), float(r["warn"]), Color(0.93, 0.29, 0.36))
				if bool(r.get("pillar", false)) and game.has_method("light_pillar"):
					game.light_pillar(at, float(r["radius"]), float(r["warn"]))
				elif game.has_method("erupt_mound"):
					game.erupt_mound(at, float(r["radius"]), float(r["warn"]))
			(r["strikes"] as Array).append({"at": at, "t": float(r["warn"])})
		var left_strikes: Array = []
		for s in r["strikes"]:
			s["t"] = float(s["t"]) - delta
			if float(s["t"]) > 0.0:
				left_strikes.append(s)
				continue
			var at: Vector3 = s["at"]
			var d := ppos - at
			d.y = 0.0
			if player and not player.dead and d.length() <= float(r["radius"]) + 0.35:
				var rinfo: Dictionary = (r.get("info", {}) as Dictionary).duplicate(true)
				if float(r.get("knockback", 0.0)) > 0.0:
					(rinfo.get("fx", []) as Array).append("knocked back")
				player.take_damage(float(r["damage"]), at, rinfo)
				if float(r.get("knockback", 0.0)) > 0.0 and player.has_method("shove") and d.length_squared() > 0.01:
					player.shove(d.normalized() * float(r.get("knockback", 0.0)))
			var sp_id: String = str(r.get("spawn", ""))
			if sp_id != "":
				# the sand bursts and something comes up through it, thrown a little towards the hero
				# on the numbers of the moment the eruption was called (pass 58, R1; brood_numbers)
				# (pass 73, lane GROUND: a summon is never a variance special)
				force_plain = true
				var j := spawn(sp_id, at, null, 1.0, 1.0, "", r.get("stats", {}), r.get("src", {}))
				force_plain = false
				if j >= 0:
					var tow := ppos - at
					tow.y = 0.0
					kb[j] = (tow.normalized() if tow.length_squared() > 0.01 else Vector3.ZERO) * 3.0
					state[j] = STATE_MOVE
				if game:
					# sand thrown up where it breaks the surface (a burst that size was a pale cloud over the whole ring)
					game.fx_sand(at + Vector3(0, 0.2, 0), float(r["radius"]) * 0.9)
					if game.has_method("shockwave"):
						game.shockwave(at, float(r["radius"]))
					Audio.play("en_boss_attack", at)
			elif bool(r.get("pillar", false)) and game:
				# the Sun Idol's column lands: a flash of gold and a shock, no sand
				game.fx_burst(at + Vector3(0, 0.6, 0), Color(1.0, 0.85, 0.35), float(r["radius"]) * 1.6)
				if game.has_method("shockwave"):
					game.shockwave(at, float(r["radius"]))
				Audio.play("en_boss_attack", at)
			elif game:
				var jit := Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
				game.fx_lightning([at + Vector3(0, 11.0, 0) + jit * 2.0, at + Vector3(0, 6.0, 0) + jit, at + Vector3(0, 0.2, 0)])
				game.fx_burst(at + Vector3(0, 0.3, 0), Color(1.0, 0.85, 0.45), float(r["radius"]) * 1.1)
				if game.has_method("shockwave"):
					game.shockwave(at, float(r["radius"]))
				Audio.play("en_boss_attack", at)
		r["strikes"] = left_strikes
		if int(r["left"]) > 0 or not left_strikes.is_empty():
			keep.append(r)
	_rains = keep


## The Gila's rumble (pass 43): a wave of heaving sand runs from the boss down each line of its fan; the hero is hit once
## by each line he stands on as it passes (thrown along it), and the sand bursts at the wave's front as it goes.
func _tick_rumbles(delta: float, ppos: Vector3) -> void:
	if _rumbles.is_empty():
		return
	var keep: Array = []
	for r in _rumbles:
		var front: float = float(r["front"]) + float(r["speed"]) * delta
		r["front"] = front
		var from: Vector3 = r["from"]
		var dir: Vector3 = r["dir"]
		var at: Vector3 = from + dir * minf(front, float(r["len"]))
		at.y = _height(at.x, at.z)
		r["fx_t"] = float(r["fx_t"]) - delta
		if float(r["fx_t"]) <= 0.0 and game:
			r["fx_t"] = 0.07
			game.fx_sand(at + Vector3(0, 0.2, 0), 1.3)
			game.rumble_mark(at, float(r["width"]))
		if not bool(r["hit"]) and player and not player.dead:
			# the hero against the stretch the wave has covered
			var rel := ppos - from
			rel.y = 0.0
			var along := clampf(rel.dot(dir), 0.0, minf(front, float(r["len"])))
			var off := rel - dir * along
			if off.length() <= float(r["width"]) + 0.35 and along > 0.3:
				r["hit"] = true
				player.take_damage(float(r["damage"]), at, r["info"])
				if player.has_method("blast"):
					player.blast(dir * float(r["kb"]), float(r["lift"]))
		if front < float(r["len"]):
			keep.append(r)
	_rumbles = keep


## The golem's swoop (pass 45): every `gap` seconds a stalactite is placed on a random spot of the wedge (evenly over its
## area, never on the golem) and falls for `fall` seconds (Game.stalactite draws it). Where one lands the crowd is thrown
## back unhurt (never the golem) and, once per swoop, a hero still inside the wedge is hit and thrown away from its apex.
func _tick_stalactites(delta: float, ppos: Vector3) -> void:
	if _stalactites.is_empty():
		return
	var keep: Array = []
	for s in _stalactites:
		s["next"] = float(s["next"]) - delta
		var c: Vector3 = s["center"]
		var dir: Vector3 = s["dir"]
		var r: float = float(s["r"])
		var half: float = deg_to_rad(float(s["deg"])) * 0.5
		while float(s["next"]) <= 0.0 and int(s["left"]) > 0:
			s["next"] = float(s["next"]) + float(s["gap"])
			s["left"] = int(s["left"]) - 1
			var a := _rng.randf_range(-half, half)
			var d := r * sqrt(_rng.randf_range(0.04, 1.0))
			var at := c + dir.rotated(Vector3.UP, a) * d
			at.y = _height(at.x, at.z)
			(s["falling"] as Array).append({"at": at, "t": float(s["fall"])})
			if game and game.has_method("stalactite"):
				game.stalactite(at, float(s["fall"]), 1.0)
		var still: Array = []
		for f in s["falling"]:
			f["t"] = float(f["t"]) - delta
			if float(f["t"]) > 0.0:
				still.append(f)
				continue
			var at: Vector3 = f["at"]
			throw_radius(at, float(s["throw_r"]), float(s["throw"]), int(s["owner"]))
			if game and game.has_method("stalactite_hit"):
				game.stalactite_hit(at)
			if not bool(s["hit"]) and player and not player.dead:
				var rel := ppos - c
				rel.y = 0.0
				var inside: bool = rel.length() <= r + 0.35 and (rel.length() < 0.5 or absf(dir.signed_angle_to(rel.normalized(), Vector3.UP)) <= half + 0.08)
				if inside:
					s["hit"] = true
					player.take_damage(float(s["damage"]), at, s["info"])
					if player.has_method("blast") and str(player.get("last_outcome")) != "evaded":
						var fling: Vector3 = rel if rel.length_squared() > 0.01 else dir
						player.blast(fling.normalized() * float(s["kb"]), float(s["lift"]))
		s["falling"] = still
		if int(s["left"]) > 0 or not still.is_empty():
			keep.append(s)
	_stalactites = keep


# ---------------------------------------------------------------- the decoy (pass 69, lane HERO: May's Inflatable May)

## While May's inflatable double stands (core/systems/Decoy.gd), the creatures it fooled walk to `decoy_at` instead of
## her (their brain steers at it: chasers chase it, shooters aim at it) and bite it instead of her (bites do nothing).
## A fooled creature is kept by slot and spawn serial, so a slot reused by a new spawn is not fooled.
var decoy_on := false
var decoy_at := Vector3.ZERO
var decoy_bites := 0                 # bites the doll took (it wobbles on each)
var _fooled: Dictionary = {}         # index -> its spawn serial when it was fooled


## Whether creature `i` can be fooled: alive, up, not dying, not buried, never a boss (Elites are fooled too).
func foolable(i: int) -> bool:
	if i < 0 or i >= MAX or alive[i] == 0 or state[i] == STATE_DYING or hidden[i] != 0:
		return false
	if i == boss_index:
		return false
	return (types[type_idx[i]]["def"] as EnemyDef).archetype != "boss"


## Fool creature `i` (if it can be): it goes for the doll until unfool_all. Returns true when it was fooled now.
func fool(i: int) -> bool:
	if not foolable(i) or is_fooled(i):
		return false
	_fooled[i] = serial[i]
	return true


func is_fooled(i: int) -> bool:
	return _fooled.has(i) and int(_fooled[i]) == serial[i] and alive[i] == 1 and state[i] != STATE_DYING


## The fooled creatures alive right now (the "?" marks).
func fooled_indices() -> PackedInt32Array:
	var out := PackedInt32Array()
	for k in _fooled.keys():
		var i: int = int(k)
		if is_fooled(i):
			out.append(i)
	return out


func unfool_all() -> void:
	_fooled.clear()
	decoy_on = false


## Where creature `i`'s brain steers: the doll while it is fooled, else the hero.
func decoy_target(i: int, ppos: Vector3) -> Vector3:
	if decoy_on and is_fooled(i):
		return Vector3(decoy_at.x, ppos.y, decoy_at.z)
	return ppos


## A fooled creature next to the doll bites it on its own cadence; nothing is hurt, the doll wobbles (Decoy reads
## decoy_bites).
func _decoy_bite(i: int) -> void:
	var d := decoy_at - pos[i]
	d.y = 0.0
	var reach := radius[i] + 0.7
	if d.length_squared() < reach * reach and contact_cd[i] <= 0.0 and rise_t[i] >= 1.0 and freeze_t[i] <= 0.0 and stun_t[i] <= 0.0:
		contact_cd[i] = _t_ccd[type_idx[i]]
		decoy_bites += 1
		squash[i] = 0.8


func _update_boss(delta: float, ppos: Vector3) -> void:
	_tick_rains(delta, ppos)
	_tick_rumbles(delta, ppos)
	_tick_stalactites(delta, ppos)
	# pass 72 (lane BOSS): the custom attacks in the air (content/boss_attacks)
	_tick_custom_attacks(delta, ppos)
	if boss_index >= 0:
		_update_attacks(boss_index, delta, ppos)
	for i in range(MAX):
		if alive[i] == 1 and i != boss_index:
			var adef: EnemyDef = types[type_idx[i]]["def"]
			# casters live by their script; any other Elite with one runs it between whatever its brain does. The script
			# owns STATE_ATTACK, so it keeps running through the attack it started (pass 33.6: it only ran in STATE_MOVE,
			# so an attack never finished: the Dune Scorpion went under the sand for its burrow and never came up).
			# Pass 43: any creature with a script runs it (the Hammer Giant's slam, gated by its `reach`)
			if adef.brain == "caster" or not (adef.boss.get("attacks", []) as Array).is_empty():
				if state[i] == STATE_MOVE or state[i] == STATE_ATTACK or adef.brain == "caster":
					_update_attacks(i, delta, ppos)
				# and whatever happens, a scripted creature is never left buried outside its own attack (pass 60: it rises
				# out of the sand like one a burrow brings up, instead of standing there at once)
				if hidden[i] == 1 and state[i] != STATE_ATTACK and adef.brain != "ambush":
					hidden[i] = 0
					rise_t[i] = 0.0
	# pass 73 (lane GROUND): the burrows under way (the sink's sand, the predicted spot and its warning)
	_tick_burrows(delta, ppos)


## The attack runner: a creature with a `boss.attacks` list (the bosses, the casters) cycles through them, each with a
## wind-up and a telegraph, then the effect. State lives per creature, so a caster and the boss can run at once. Every
## attack's damage reads the attacker's own factors (pass 58: stage_of, lvd_of, host_of): fixed from its source for a
## creature a row brought (the Hammer Giant), the live ones for a boss or an Elite as before.
func _update_attacks(i: int, delta: float, ppos: Vector3) -> void:
	if alive[i] == 0 or state[i] == STATE_DYING:
		return
	if stun_t[i] > 0.0:
		# a stunned creature's script waits (pass 53; a boss or an Elite is never stunned, so this is the Hammer Giant's)
		vel[i] = Vector3.ZERO
		return
	var def: EnemyDef = types[type_idx[i]]["def"]
	var attacks: Array = def.boss.get("attacks", [])
	# pass 72 (lane BOSS): the entries naming a custom attack (content/boss_attacks) resolved
	attacks = custom_resolved(def, attacks)
	if attacks.is_empty():
		return
	if state[i] == STATE_MOVE:
		if rise_t[i] < 1.0:
			# still rising out of the sand (pass 60): nothing new until it is up
			vel[i] = Vector3.ZERO
			intent[i] = Vector3.ZERO
			return
		if hold_t[i] > 0.0:
			# standing and casting (the rain falls): no walking, nothing new
			hold_t[i] -= delta
			vel[i] = Vector3.ZERO
			intent[i] = Vector3.ZERO
			return
		# a hampered creature's script runs slow (pass 48)
		atk_t[i] -= delta * attack_clock(i)
		if atk_t[i] <= 0.0:
			# a caster saves its script for when the hero can see it: nothing new starts from past `attack_range`
			if def.brain == "caster" and def.caster.has("attack_range"):
				var reach := ppos - pos[i]
				reach.y = 0.0
				if reach.length() > float(def.caster["attack_range"]):
					atk_t[i] = 0.25
					return
			var atk: Dictionary = attacks[atk_i[i] % attacks.size()]
			var gap := ppos - pos[i]
			gap.y = 0.0
			var gap_d := gap.length()
			# an attack with a `reach` waits, walking on, until the hero is that close (the giant's hammer)
			if atk.has("reach"):
				if gap_d > float(atk["reach"]) + radius[i]:
					atk_t[i] = 0.15
					return
			# an attack with a minimum range is skipped while the hero is inside it (the rain never falls on his head);
			# one with a maximum range is skipped while he is beyond it (pass 45: the golem's smack and swoop give way to
			# its boulder when he keeps his distance)
			var tries := 0
			while _attack_out_of_range(atk, gap_d) and tries < attacks.size():
				atk_i[i] += 1
				atk = attacks[atk_i[i] % attacks.size()]
				tries += 1
			atk_i[i] += 1
			state[i] = STATE_ATTACK
			# every wind-up and its telegraph last 1/pace (pass 48), so the slower hero still has the time to get clear
			timer[i] = float(atk.get("windup", 1.0)) / pace
			var dir := ppos - pos[i]
			dir.y = 0.0
			dir = dir.normalized()
			charge_dir[i] = dir
			# pass 72 (lane BOSS): a custom attack's own wind-up marks (its entry's telegraph is "none")
			_custom_attack_begin(i, atk, ppos)
			match str(atk.get("telegraph", "none")):
				"line":
					# as long as the attack: a roll's speed x duration plus the body in front of its centre, a brand's `length`;
					# 22 m for anything else (pass 45: it was 22 for every line, so the King's 14.4 m roll looked like it
					# stopped half way)
					var tl: float = float(atk.get("length", 0.0))
					if tl <= 0.0:
						tl = float(atk.get("speed", 12.0)) * float(atk.get("duration", 1.2)) + radius[i] if str(atk.get("name", "")) == "roll" else 22.0
					if game: game.telegraph_line(pos[i], dir, tl, timer[i], Color(0.93, 0.29, 0.36))
				"ring":
					if game: game.telegraph_ring(pos[i], float(atk.get("radius", 6.0)), timer[i], Color(0.93, 0.29, 0.36))
				"ring_at_hero":
					atk_target[i] = ppos
					if game: game.telegraph_ring(ppos, float(atk.get("radius", 5.0)), timer[i], Color(0.93, 0.29, 0.36))
				"sector":
					# a wedge on the ground from the creature along its aim (pass 45: the golem's swoop, 180 degrees)
					if game and game.has_method("telegraph_sector"):
						game.telegraph_sector(pos[i], dir, float(atk.get("radius", 6.5)), float(atk.get("deg", 180.0)), timer[i], Color(0.93, 0.29, 0.36))
				"fan":
					if game:
						var fn := int(atk.get("count", 7))
						var fspread := deg_to_rad(float(atk.get("spread_deg", 90.0)))
						for k in range(fn):
							game.telegraph_line(pos[i], dir.rotated(Vector3.UP, -fspread * 0.5 + fspread * float(k) / float(maxi(fn - 1, 1))), float(atk.get("length", 14.0)), timer[i], Color(0.93, 0.29, 0.36))
				"spokes":
					# the King's volley (pass 45): a red line down every direction a tumbleweed will roll; the first spoke's
					# direction rides in charge_dir so the shots leave down the lines drawn. Pass 47 (Garry: "Marker for the
					# Tumbleweed attack is short while the attack is long"): each line runs as far as a tumbleweed rolls
					# (volley_reach), not 5 m; a positive `spoke_length` still names its own
					var sn := int(atk.get("count", 12))
					var sphase := _rng.randf() * TAU
					charge_dir[i] = Vector3(cos(sphase), 0, sin(sphase))
					var slen := float(atk.get("spoke_length", 0.0))
					if slen <= 0.0:
						slen = volley_reach(atk)
					if game:
						for k in range(sn):
							var sa := sphase + TAU * float(k) / float(maxi(sn, 1))
							game.telegraph_line(pos[i], Vector3(cos(sa), 0, sin(sa)), slen, timer[i], Color(0.93, 0.29, 0.36))
			if str(atk.get("name", "")) == "burrow":
				# under the sand for the wind-up (pass 60): the ring on the hero says where it comes up, and the sand there
				# swells into a mound through the wind-up (_mound_start, ticked from the wind-up's timer, gone at the pop).
				# Pass 73 (lane GROUND): with a `sink` it sinks out of sight where it stands first; one that `predict`s its
				# spot shows nothing until its warning (_burrow_begin, _tick_burrows)
				_burrow_begin(i, atk)
			Audio.play(str(def.sfx.get("attack", "en_boss_attack")), pos[i])
	elif state[i] == STATE_ATTACK:
		timer[i] -= delta * attack_clock(i)
		vel[i] = Vector3.ZERO
		intent[i] = Vector3.ZERO
		if timer[i] <= 0.0:
			var atk: Dictionary = attacks[(atk_i[i] - 1) % attacks.size()]
			match str(atk.get("name", "")):
				"roll":
					# at the pace knob's speed (_scripted_speed) and 1/pace as long: the length of its red line (pass 48)
					state[i] = STATE_CHARGE
					timer[i] = float(atk.get("duration", 1.2)) / pace
					dmg[i] = float(atk.get("damage", 25)) * stage_of(i) * host_of(i)
				"spawn_ring":
					# a boss's brood comes on the numbers of the moment it is called (pass 58, R1), or on a row's that
					# brings the same creature then (the fix round, brood_numbers)
					var bid := str(atk.get("enemy", "coyote"))
					var bn := brood_numbers(bid)
					# pass 73 (lane GROUND): a summon is never a variance special
					force_plain = true
					spawn_ring(bid, int(atk.get("count", 10)), pos[i], 5.0, "", bn["stats"], bn["src"])
					force_plain = false
					state[i] = STATE_MOVE
				"slam_at":
					# a rock on the marked spot: damage there, the caster stays where it is
					var rs := float(atk.get("radius", 2.6))
					var ds := ppos - atk_target[i]
					ds.y = 0.0
					if ds.length() <= rs + 0.4:
						player.take_damage(float(atk.get("damage", 18)) * stage_of(i) * host_of(i), atk_target[i], hit_info(i, "ranged", ["rock slam", "knocked back"]))
						if player.has_method("shove") and ds.length_squared() > 0.01:
							player.shove(ds.normalized() * float(atk.get("knockback", 6.0)))
					if game:
						if game.has_method("shockwave"):
							game.shockwave(atk_target[i], rs)
						game.fx_burst(atk_target[i] + Vector3(0, 0.4, 0), Color(0.85, 0.7, 0.5), 3.0)
					state[i] = STATE_MOVE
				"blink":
					var dest: Vector3
					if str(atk.get("to", "")) == "screen":
						# a fresh spot on the hero's screen, across from where it stood: the ranged Elite repositions,
						# it never blinks off the screen (it used to jump 8 m further off every cycle)
						var bf := _camera_forward()
						var br := Vector3(-bf.z, 0, bf.x)
						var bkeep := float(def.caster.get("keep_distance", 7.0))
						var bside := float(def.caster.get("side", 4.5))
						var across := (pos[i] - ppos).dot(br)
						var sgn: float = -signf(across) if absf(across) > 1.0 else (1.0 if _rng.randf() < 0.5 else -1.0)
						dest = ppos + bf * bkeep * _rng.randf_range(0.85, 1.05) + br * sgn * _rng.randf_range(1.5, bside)
					else:
						# away from the hero in a puff of sand, inside the arena
						var away := pos[i] - ppos
						away.y = 0.0
						if away.length_squared() < 0.01:
							away = Vector3.FORWARD
						dest = pos[i] + away.normalized() * float(atk.get("distance", 8.0))
					var lim: float = (game.map.arena_radius - 3.0) if game and game.map else 60.0
					if Vector2(dest.x, dest.z).length() > lim:
						var flat := Vector2(dest.x, dest.z).normalized() * lim
						dest = Vector3(flat.x, dest.y, flat.y)
					dest.y = _height(dest.x, dest.z)
					if game:
						game.fx_burst(pos[i] + Vector3(0, size[i] * 0.5, 0), Color(0.9, 0.78, 0.55), 2.2)
					pos[i] = dest
					if game:
						game.fx_burst(pos[i] + Vector3(0, size[i] * 0.5, 0), Color(0.9, 0.78, 0.55), 2.2)
					state[i] = STATE_MOVE
				"burrow":
					# up it comes (pass 60): the figure rises out of the sand (rise_t, drawn sunk by the part still under) in a
					# poof of soft dust (Fx.pop_dust), the damage landing at this moment as before. Pass 73 (lane GROUND): over
					# its own `rise`, through the ground-clip, throwing the hero and the crowd round it (_burrow_erupt)
					_burrow_erupt(i, atk, ppos)
					state[i] = STATE_MOVE
				"rain", "erupt":
					# a sequence of small strikes around the hero, each a red ring first: a dodge that lasts a few seconds;
					# "erupt" also brings a creature up through the sand at every ring (the Dune Centipede's young)
					var eid := str(atk.get("spawn", ""))
					var en: Dictionary = brood_numbers(eid) if eid != "" else {"stats": {}, "src": {}}
					_rains.append({"left": int(atk.get("count", 10)), "next": 0.0, "interval": float(atk.get("interval", 0.3)),
						"spread": float(atk.get("spread", 5.0)), "radius": float(atk.get("radius", 1.6)), "damage": float(atk.get("damage", 14)) * stage_of(i) * host_of(i),
						"warn": float(atk.get("warn", 0.55)) / pace, "strikes": [], "first": true, "spawn": eid, "src": en["src"], "stats": en["stats"],
						"pillar": bool(atk.get("pillar", false)), "knockback": float(atk.get("knockback", 0.0)),
						"info": hit_info(i, "ranged", ["pillar of light" if bool(atk.get("pillar", false)) else "eruption"])})
					hold_t[i] = float(atk.get("count", 10)) * float(atk.get("interval", 0.3)) + float(atk.get("warn", 0.55)) / pace + 0.3
					state[i] = STATE_MOVE
				"spit_volley":
					var vn := int(atk.get("count", 7))
					var vspread := deg_to_rad(float(atk.get("spread_deg", 90.0)))
					for k in range(vn):
						var va := -vspread * 0.5 + vspread * float(k) / float(maxi(vn - 1, 1))
						var target: Vector3 = pos[i] + charge_dir[i].rotated(Vector3.UP, va) * 12.0
						var vfrom: Vector3 = pos[i] + Vector3(0, size[i] * 0.6, 0)
						if bool(atk.get("straight", false)) and game and game.has_method("enemy_shot_straight"):
							# the fan on the ground is a set of lines: the shots fly down them, not over them
							game.enemy_shot_straight(vfrom, target, float(atk.get("speed", 14.0)), float(atk.get("damage", 12)) * stage_of(i) * lvd_of(i) * host_of(i),
								float(atk.get("splash", 0.5)), {"life": float(atk.get("life", 1.0)), "shot": str(atk.get("shot", "")),
								"knockback": float(atk.get("knockback", 0.0)), "info": hit_info(i, "ranged", [str(atk.get("shot", "volley"))])})
						elif game and game.has_method("enemy_spit"):
							game.enemy_spit(vfrom, target, float(atk.get("speed", 7.0)), float(atk.get("damage", 12)) * stage_of(i) * host_of(i), float(atk.get("splash", 1.4)), hit_info(i, "ranged", ["volley"]))
					state[i] = STATE_MOVE
				"slam":
					var r := float(atk.get("radius", 6.0))
					var d := ppos - pos[i]
					d.y = 0.0
					if d.length() <= r + 0.5:
						player.take_damage(float(atk.get("damage", 30)) * stage_of(i) * lvd_of(i) * host_of(i), pos[i], hit_info(i, "melee", ["slam", "knocked back"]))
						if atk.has("lift") and player.has_method("blast"):
							# the giant's hammer (pass 43): a real throw, past the shove's cap
							player.blast(d.normalized() * float(atk.get("knockback", 6.0)), float(atk["lift"]))
						elif player.has_method("apply_knockback"):
							player.apply_knockback(d.normalized() * float(atk.get("knockback", 6.0)))
					if game and game.has_method("shockwave"):
						game.shockwave(pos[i], r)
					if game and atk.has("lift"):
						game.camera.shake(1.4)
					state[i] = STATE_MOVE
				"rumble":
					# the Gila (pass 43): every line of the fan becomes a wave of heaving sand running out from the boss
					var rn := int(atk.get("count", 7))
					var rspread := deg_to_rad(float(atk.get("spread_deg", 90.0)))
					for k in range(rn):
						var ra := -rspread * 0.5 + rspread * float(k) / float(maxi(rn - 1, 1))
						_rumbles.append({"from": pos[i], "dir": charge_dir[i].rotated(Vector3.UP, ra), "len": float(atk.get("length", 14.0)), "front": 0.0,
							"speed": float(atk.get("speed", 13.0)) * pace, "width": float(atk.get("width", 1.2)), "damage": float(atk.get("damage", 16)) * stage_of(i) * lvd_of(i) * host_of(i),
							"kb": float(atk.get("knockback", 10.0)), "lift": float(atk.get("lift", 3.0)), "hit": false, "fx_t": 0.0,
							"info": hit_info(i, "ranged", ["ground rumble", "thrown"])})
					if game:
						game.camera.shake(0.8)
					state[i] = STATE_MOVE
				"brand":
					# the Brander's iron (pass 43): a line of fire on the sand that burns whoever crosses it for a while
					if game and game.has_method("hell_line"):
						# the line knows whose it is (pass 45): the Brander stood at its start and burned on his own iron
						game.hell_line(pos[i], charge_dir[i], float(atk.get("length", 16.0)), float(atk.get("life", 9.0)), float(atk.get("width", 1.1)),
							float(atk.get("damage", 12)) * stage_of(i) * lvd_of(i) * host_of(i), float(atk.get("tick", 0.5)), hit_info(i, "ranged", ["hellfire"]), i)
					state[i] = STATE_MOVE
				"tumbleweed_volley":
					# the King (pass 45): tumbleweeds roll out in every direction, far, whether the hero is near or not
					if game and game.has_method("tumbleweed_volley"):
						game.tumbleweed_volley(pos[i], charge_dir[i], int(atk.get("count", 12)), float(atk.get("speed", 9.0)),
							float(atk.get("damage", 14)) * stage_of(i) * lvd_of(i) * host_of(i), float(atk.get("life", 2.6)),
							float(atk.get("knockback", 14.0)), float(atk.get("lift", 2.5)), hit_info(i, "ranged", ["tumbleweed"]))
					state[i] = STATE_MOVE
				"swoop":
					# the golem's swoop (pass 45): stalactites blanket the half-disc it marked, `count` of them over `duration`
					# seconds, each falling `fall` seconds; the hero is hit once if he is still inside when one lands
					# (_tick_stalactites); the golem stands under them for the whole of it
					var sc := int(atk.get("count", 14))
					var sdur := float(atk.get("duration", 0.8))
					var sfall := float(atk.get("fall", 0.45)) / pace
					_stalactites.append({"center": pos[i], "dir": charge_dir[i], "r": float(atk.get("radius", 6.5)), "deg": float(atk.get("deg", 180.0)),
						"left": sc, "gap": sdur / maxf(float(sc), 1.0), "next": 0.0, "fall": sfall,
						"damage": float(atk.get("damage", 24)) * stage_of(i) * lvd_of(i) * host_of(i), "kb": float(atk.get("knockback", 14.0)), "lift": float(atk.get("lift", 3.0)),
						"throw": float(atk.get("throw", 12.0)), "throw_r": float(atk.get("throw_radius", 1.8)), "owner": i, "hit": false, "falling": [],
						"info": hit_info(i, "ranged", ["stalactites", "thrown"])})
					hold_t[i] = sdur + sfall + 0.2
					if game and game.camera:
						game.camera.shake(0.5)
					state[i] = STATE_MOVE
				"boulder":
					# the golem's boulder (pass 45): a rock on a high arc to the spot it marked, a blast when it lands
					# (Game.throw_boulder -> Boulder -> Game.boulder_land); the ring stays on the spot for the flight
					var bflight := float(atk.get("flight", 1.6))
					if game and game.has_method("throw_boulder"):
						game.throw_boulder(i, pos[i] + Vector3(0, size[i] * 0.8, 0), atk_target[i], atk, stage_of(i) * lvd_of(i) * host_of(i), hit_info(i, "ranged", ["boulder", "thrown"]))
						# the boulder flies on hostile_clock (pass 48), so its ring stays 1/pace as long
						game.telegraph_ring(atk_target[i], float(atk.get("radius", 4.6)), bflight / pace, Color(0.93, 0.29, 0.36))
					state[i] = STATE_MOVE
				_:
					# pass 72 (lane BOSS): a custom attack (content/boss_attacks) by its id
					_custom_attack_fire(i, atk, ppos)
					state[i] = STATE_MOVE
			atk_t[i] = float(def.boss.get("cooldown_between", 2.0))
			# pass 72 (lane BOSS): a custom attack's own rest after it, when it names one
			atk_t[i] = custom_rest(atk, atk_t[i])
	elif state[i] == STATE_CHARGE and str(def.brain) == "boss":
		timer[i] -= delta
		vel[i] = charge_dir[i] * _scripted_speed(i, def)
		if timer[i] <= 0.0:
			state[i] = STATE_MOVE
			dmg[i] = def.damage * stage_of(i) * host_of(i)
			atk_t[i] = float(def.boss.get("cooldown_between", 2.0))


## How far from the King a tumbleweed of his volley reaches (pass 47): it starts VOLLEY_START out, rolls `speed` x
## `life`, and hits VOLLEY_HIT past its centre.
static func volley_reach(atk: Dictionary) -> float:
	return VOLLEY_START + float(atk.get("speed", 9.0)) * float(atk.get("life", 2.6)) + VOLLEY_HIT


## An attack with `min_range` is skipped while the hero is inside it (the rain never falls on his head); one with
## `max_range` is skipped while he is beyond it (pass 45: the golem's smack and swoop give way to its boulder when he
## keeps his distance). `reach` is different: it waits, walking on, which would hold a cycle of close attacks for ever.
func _attack_out_of_range(atk: Dictionary, dist: float) -> bool:
	return (atk.has("min_range") and dist < float(atk["min_range"])) or (atk.has("max_range") and dist > float(atk["max_range"]))


## The speed of the scripted attack a creature is in the middle of (a boss's roll): _steer and the runner read one value.
## The pace knob is in it (pass 48).
func _scripted_speed(i: int, def: EnemyDef) -> float:
	var attacks: Array = def.boss.get("attacks", [])
	# pass 72 (lane BOSS): a custom `script` attack wrapping a roll rolls at its own speed
	attacks = custom_resolved(def, attacks)
	if attacks.is_empty():
		return float(def.charge.get("speed", 9.0)) * pace
	return float((attacks[(atk_i[i] - 1) % attacks.size()] as Dictionary).get("speed", 12.0)) * pace


## Warm-up: every type draws one instance at `at` (Vector3.INF stops it) so its shader variants compile behind the
## spawn beam. The render loop keeps that extra instance while the warm-up is on.
var _warm_at := Vector3.INF


func warm_draw(at: Vector3) -> void:
	_warm_at = at
	if at != Vector3.INF:
		for kind in ["crown", "skull", "gear"]:
			_badge_mm(kind)
	for t in types:
		var mm: MultiMesh = t["mm"]
		if at == Vector3.INF:
			mm.visible_instance_count = 0
		else:
			mm.set_instance_transform(0, Transform3D(Basis(), at))
			mm.set_instance_custom_data(0, Color(0, 0, 0.5, 1))
			mm.set_instance_color(0, Color(1, 1, 1, 0))
			mm.visible_instance_count = 1


# ---------------------------------------------------------------- badges

## Badges (pass 33.3): a crown floats over the two Elites (and nothing else), a skull over a boss, a gear over the specials (the harpooner,
## the rocketeer; their JSON `badge`). One MultiMesh per badge drawn by core/shaders/badge.gdshader, built the first
## time a creature wears it; `BADGE_SIZE` metres at the base zoom, growing a little as the camera pulls out.
const BADGE_SIZE := 0.72
const BADGE_MAX := 24
var _badges: Dictionary = {}   # badge -> MultiMesh (null when its painting is missing)
var _badge_scale := 1.0
var _badge_shader: Shader = preload("res://core/shaders/badge.gdshader")


func _badge_mm(kind: String) -> MultiMesh:
	if _badges.has(kind):
		return _badges[kind]
	var mm: MultiMesh = null
	var path := "res://art/ui/badges/%s.png" % kind
	if ResourceLoader.exists(path):
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		var quad := QuadMesh.new()
		quad.size = Vector2(1, 1)
		mm.mesh = quad
		mm.instance_count = BADGE_MAX
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = "Badge_" + kind
		var mat := ShaderMaterial.new()
		mat.shader = _badge_shader
		mat.set_shader_parameter("tex", load(path))
		mat.render_priority = 10
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
		add_child(mmi)
	_badges[kind] = mm
	return mm


## The badge a creature wears right now ("" for none): its type's (an elite modifier never adds one).
func badge_of(i: int) -> String:
	if i < 0 or i >= MAX or alive[i] == 0:
		return ""
	return str(types[type_idx[i]]["badge"])


var _mark := -1.0
## Far zoom (pass 33.2): past twice the camera's base distance every creature gets a thicker dark-red rim and a faint
## warm tint, fading in to full by 2.4x, so a crowd of specks stays readable around a small hero.
func _update_mark() -> void:
	var z: float = game.camera.zoom() if game and game.get("camera") and game.camera and game.camera.has_method("zoom") else 1.0
	# the badges grow a little as the camera pulls out, so a crown stays a crown when the crowd is specks
	_badge_scale = pow(maxf(z, 1.0), 0.6)
	var m: float = snappedf(clampf((z - 2.0) / 0.4, 0.0, 1.0), 0.05)
	if m == _mark:
		return
	_mark = m
	for t in types:
		(t["mat"] as ShaderMaterial).set_shader_parameter("mark", m)


## Which of the 13 strips (ANIM_NAMES) creature `i` of type `t` shows right now: the same choice as ever, read from the
## type's frame table (pass 33.8: the strip's name was built and looked up as a string, and frame_offset walked the
## list of strips, for every creature every tick).
func _strip_of(i: int, t: int) -> int:
	var st := state[i]
	# the walk or the stand (pass 60: a creature that fights at range by what its brain means, `intent`, so the crowd
	# shoving it is no walk)
	var mv: Vector3 = intent[i] if _t_faces[t] == 1 else vel[i]
	var move := A_IDLE if st == STATE_SPAWN or mv.length_squared() < 0.04 else A_RUN
	var a := move
	if st == STATE_DYING:
		a = A_DIE
	elif st == STATE_WINDUP or st == STATE_ATTACK:
		a = A_ATTACK
	if held[i] == 1 and st != STATE_DYING:
		# kicking its legs in the air
		a = A_RUN
	if i == tethered_i and tether_drag_t > 0.0 and st != STATE_DYING:
		# dragged on the rope: it digs in with the frames it shows before a throw
		a = A_ATTACK
	if flash[i] > 0.6 and _t_hit_ok[t] == 1 and st != STATE_DYING:
		a = A_HIT
	if _t_eight[t] == 1:
		# eight-direction creatures: chargers keep their directional run while charging and hold the idle set while winding up
		if st == STATE_CHARGE:
			a = A_RUN
		elif st == STATE_WINDUP and _t_charge[t] == 1:
			# one with charge.legs scrabbles in place (pass 50); the others hold their idle set
			a = A_RUN if _t_cv[t * CV_N + 2] > 1.0 else A_IDLE
		if (a == A_HIT or a == A_ATTACK) and view[i] != 0:
			# the hit and attack frames are painted facing the camera only (pass 60): off the front view the creature
			# keeps its stand or walk in the view it shows (the white flash still says it was hit), instead of popping
			# round to face the camera for a frame (the Sun Prophet's "flicker")
			a = move
		if a == A_RUN or a == A_IDLE:
			var cand: int = VIEW_ANIM[a][view[i]]
			if _t_ok[t * N_ANIMS + cand] == 1:
				return cand
		return a
	if away[i] == 1 and (a == A_RUN or a == A_IDLE) and _t_okb[t * 2 + a] == 1:
		return 5 if a == A_RUN else 6
	return a


## The tint creature `i` is drawn with (the shader mixes 65% of its alpha; pass 48: out of _render, so a test reads what is
## drawn): its variance tint, an elite modifier's outline colour over that, a burn's flicker (blue for a blue burn) or
## poison's green over those, a weapon's held tint (set_status_tint) over a burn or poison, and a frozen creature's ice
## blue over everything.
func tint_of(i: int) -> Color:
	var tint := vtint[i]
	if elite_idx[i] >= 0:
		var e: EliteModDef = elites[elite_idx[i]]
		tint = Color(e.outline.r, e.outline.g, e.outline.b, 0.7)
	if not (fire_src[i] as Dictionary).is_empty():
		if fire_blue[i] == 1:
			# a blue burn (pass 48: Methanol, Moonshine), flickering a little like the orange one
			tint = Color(BLUE_BURN.r, BLUE_BURN.g + 0.12 * absf(sin(anim_t[i] * 5.0 + float(i))), BLUE_BURN.b, 1.0)
		else:
			# red-orange that flickers between ember and flame while burning
			tint = Color(1.0, 0.18 + 0.22 * absf(sin(anim_t[i] * 5.0 + float(i))), 0.02, 1.0)
	elif not (poison_src[i] as Dictionary).is_empty():
		tint = Color(0.45, 1.0, 0.3, 0.8)   # bright green while poisoned
	if status_t[i] > 0.0:
		tint = status_tint[i]   # a weapon's held tint (pass 48, set_status_tint) over a burn or poison
	if freeze_t[i] > 0.0:
		tint = Color(0.2, 0.5, 1.0, 1.0)   # ice blue while frozen (Cold Snap)
	return tint


## The blob shadow under creature `i`: the plain ellipse at its feet (0.55 by 0.34 of its size, smaller while it is up in
## the air) with its type's tuning (pass 47, EnemyDef.shadow): wider or deeper, and slid `up` the screen along the
## camera's forward on the ground (`scf`; `scr` is the screen's right), on the ground there.
func shadow_xform(i: int, scf: Vector3, scr: Vector3) -> Transform3D:
	var sb := type_idx[i] * 4
	var s := size[i]
	var shs: float = s / (1.0 + lift_h[i] * 0.5)
	var at := pos[i]
	var up: float = _t_sh[sb + 2] * s
	if up != 0.0:
		at += scf * up
		at.y = _height(at.x, at.z)
	return drape(Transform3D(Basis(scr * (shs * 0.55 * _t_sh[sb]), Vector3.UP, -scf * (shs * 0.34 * _t_sh[sb + 1])), at), height_fn)


## shadow_xform, reused while creature `i` stands within SHADOW_CACHE_MOVE m of where it was draped, with the same type,
## the same shrink in the air and the same camera axes (pass 84: draping is five height samples; a crowd of 260 on
## screen re-drapes only the ones that moved).
const SHADOW_CACHE_MOVE := 0.08
var _shc_pos := PackedVector3Array()
var _shc_key := PackedFloat32Array()
var _shc_xf: Array[Transform3D] = []
var _shc_cf := Vector3.ZERO


func _shadow_xform_cached(i: int, scf: Vector3, scr: Vector3) -> Transform3D:
	if _shc_xf.size() != pos.size():
		_shc_pos.resize(pos.size())
		_shc_key.resize(pos.size() * 2)
		_shc_xf.resize(pos.size())
		_shc_key.fill(-1.0)
	if not scf.is_equal_approx(_shc_cf):
		_shc_cf = scf
		_shc_key.fill(-1.0)
	var shs: float = size[i] / (1.0 + lift_h[i] * 0.5)
	var k := i * 2
	if _shc_key[k] == float(type_idx[i]) and absf(_shc_key[k + 1] - shs) < 0.002 \
			and _shc_pos[i].distance_squared_to(pos[i]) < SHADOW_CACHE_MOVE * SHADOW_CACHE_MOVE:
		return _shc_xf[i]
	var xf := shadow_xform(i, scf, scr)
	_shc_pos[i] = pos[i]
	_shc_key[k] = float(type_idx[i])
	_shc_key[k + 1] = shs
	_shc_xf[i] = xf
	return xf


## A flat blob quad (`extent` metres square, scaled by `xf.basis`, lying at `xf.origin` on the ground) laid on the ground under it
## (pass 65: on any slope the flat quad cut into the sand and lost half its disc): tilted to the plane through the
## ground under its four edge midpoints (`h`, the map's height_at; the normal over the blob's own extent, not a point),
## then lifted by SHADOW_LIFT plus how far the ground bends above that plane (a dish or a river bank's foot, from the
## second differences), so no part sinks under the terrain. Five height samples; the creatures' are at most
## SHADOW_BUDGET a frame once the crowd is big.
const SHADOW_LIFT := 0.03
static func drape(xf: Transform3D, h: Callable, extent := 1.0) -> Transform3D:
	if not h.is_valid():
		return Transform3D(xf.basis, xf.origin + Vector3(0, SHADOW_LIFT, 0))
	var o := xf.origin
	var ax := Vector3(xf.basis.x.x, 0.0, xf.basis.x.z) * (0.5 * extent)
	var az := Vector3(xf.basis.z.x, 0.0, xf.basis.z.z) * (0.5 * extent)
	if ax.length_squared() < 0.0001 or az.length_squared() < 0.0001:
		return Transform3D(xf.basis, Vector3(o.x, float(h.call(o.x, o.z)) + SHADOW_LIFT, o.z))
	var hxp: float = h.call(o.x + ax.x, o.z + ax.z)
	var hxm: float = h.call(o.x - ax.x, o.z - ax.z)
	var hzp: float = h.call(o.x + az.x, o.z + az.z)
	var hzm: float = h.call(o.x - az.x, o.z - az.z)
	var hc: float = h.call(o.x, o.z)
	var tx := Vector3(ax.x * 2.0, hxp - hxm, ax.z * 2.0)
	var tz := Vector3(az.x * 2.0, hzp - hzm, az.z * 2.0)
	var n := tz.cross(tx).normalized()
	if n.y < 0.0:
		n = -n
	var base := 0.25 * (hxp + hxm + hzp + hzm)
	var c := Vector3(o.x, base, o.z)
	# how far the ground bends above that plane: the second differences along the two axes (a dish's corners and
	# middle, a ridge's middle), taken generously so no corner sinks without four more height samples a blob
	var dx2 := hxp + hxm - 2.0 * hc
	var dz2 := hzp + hzm - 2.0 * hc
	var over := (absf(dx2) + absf(dz2)) * 0.5
	return Transform3D(MapBase.ground_basis(n) * xf.basis, c + Vector3(0, over / maxf(n.y, 0.3) + SHADOW_LIFT, 0))


## How far creature `i`'s painting sinks (pass 47, EnemyDef.shadow "drop"): down the billboard's own plane (`cam_up`) by
## its type's share of the cell, at its size and squash `sq`. Zero for a type without a drop.
func sprite_sink(i: int, sq: float, cam_up: Vector3) -> Vector3:
	var drop: float = _t_sh[type_idx[i] * 4 + 3]
	return cam_up * (drop * size[i] * maxf(sq, 0.2)) if drop != 0.0 else Vector3.ZERO


## How far creature `i`'s painting sits down the billboard's up (`cam_up`) while it rises out of the sand (pass 60,
## rise_t): the part still under, the whole figure (its top at `head` of the cell, at its size and squash `sq`) at 0 and
## nothing at 1, eased so it comes up quick and settles (rise_ease). Zero once it is up.
func rise_sink(i: int, sq: float, cam_up: Vector3) -> Vector3:
	var rise: float = rise_t[i]
	if rise >= 1.0:
		return Vector3.ZERO
	var head: float = float((types[type_idx[i]] as Dictionary).get("head", 1.0))
	return cam_up * ((1.0 - rise_ease(rise)) * size[i] * head * maxf(sq, 0.2))


## The drawn share of a rise 0..1 (pass 60): an ease-out, so a figure pops up fast and settles into its last inch.
static func rise_ease(rise: float) -> float:
	var r := clampf(rise, 0.0, 1.0)
	return 1.0 - (1.0 - r) * (1.0 - r)


## The frame index as the instance data carries it (INSTANCE_CUSTOM.x, pass 60): the whole frame, plus RISE_FLAG in its
## fraction while the figure is still rising (`rise` < 1), which enemy_silhouette.gdshader reads to draw nothing; both
## creature shaders floor it for the frame.
static func frame_code(frame: int, rise: float) -> float:
	return float(frame) + (RISE_FLAG if rise < 1.0 else 0.0)


## The burrow's mound (pass 60, Garry: "a visible sequence of the Scorpion actually popping from the ground"): a dome of
## sand swelling out of the ground at the ring's centre through the whole wind-up, a dark ring of cracks widening round
## its foot, driven from the wind-up's timer (no Tween: the tests step it and it freezes with the pause); gone the moment
## the creature comes up (the poof and its clods are the mound bursting). One per creature, by its index. Game.erupt_mound
## (the Centipede's) was tried first: made for a 0.55 s warn, its ball starts 0.3 r under the sand and eases in, so over a
## 2.8 s wind-up it stayed buried for the first 60%.
var _mounds: Dictionary = {}
const MOUND_COLOR := Color(0.86, 0.68, 0.42)
const MOUND_CRACK := Color(0.36, 0.22, 0.12)
## The dome's height at its fullest as a share of its radius (a hemisphere SphereMesh of `height` 2 x this x r).
const MOUND_DOME := 0.45


func _mound_start(i: int, at: Vector3, r: float) -> void:
	_mound_end(i)
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * MOUND_DOME * 2.0
	sm.is_hemisphere = true
	sm.radial_segments = 16
	sm.rings = 6
	dome.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = MOUND_COLOR
	mat.roughness = 1.0
	dome.material_override = mat
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dome.position = at
	add_child(dome)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r * 0.95
	tm.outer_radius = r * 1.08
	tm.rings = 20
	tm.ring_segments = 5
	ring.mesh = tm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = MOUND_CRACK
	rmat.roughness = 1.0
	ring.material_override = rmat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = at + Vector3(0, 0.02, 0)
	# lying on the slope it opens in (pass 52), not level through it
	var mp = game.get("map") if game else null
	if mp and mp.has_method("normal_at"):
		ring.basis = MapBase.ground_basis(mp.normal_at(at.x, at.z, r))
	add_child(ring)
	_mounds[i] = {"dome": dome, "ring": ring, "t0": maxf(timer[i], 0.01)}
	_mound_shape(i, 0.0)


## The mound's shape at `p` of its wind-up (0 just started, 1 about to burst): the dome from a bump (0.12 of its height,
## 0.3 of its width) to its full dome, the cracks from 0.6 to 1.25 of its radius, on a sine ease-out so the swell shows
## from the first tick.
func _mound_shape(i: int, p: float) -> void:
	var m: Dictionary = _mounds[i]
	var q := mound_ease(p)
	(m["dome"] as MeshInstance3D).scale = Vector3(lerpf(0.3, 1.0, q), lerpf(0.12, 1.0, q), lerpf(0.3, 1.0, q))
	(m["ring"] as MeshInstance3D).scale = Vector3(lerpf(0.6, 1.25, q), lerpf(0.5, 0.7, q), lerpf(0.6, 1.25, q))


static func mound_ease(p: float) -> float:
	return sin(clampf(p, 0.0, 1.0) * PI * 0.5)


## The mounds swell with their wind-ups (every tick, after the attack runner has moved the timers); one whose creature is
## up, gone or out of its attack is cleared.
func _tick_mounds() -> void:
	if _mounds.is_empty():
		return
	for key in _mounds.keys():
		var i: int = key
		# (pass 73, lane GROUND: and while it sinks out of sight before it is under)
		if alive[i] == 0 or (hidden[i] == 0 and rise_v[i] >= 0.0) or state[i] != STATE_ATTACK:
			_mound_end(i)
			continue
		var m: Dictionary = _mounds[i]
		_mound_shape(i, 1.0 - timer[i] / float(m["t0"]))


func _mound_end(i: int) -> void:
	if not _mounds.has(i):
		return
	var m: Dictionary = _mounds[i]
	# hidden at once (a queued free is still drawn this frame, a frame of mound under the poof), then freed
	(m["dome"] as Node3D).visible = false
	(m["ring"] as Node3D).visible = false
	(m["dome"] as Node).queue_free()
	(m["ring"] as Node).queue_free()
	_mounds.erase(i)


## How far the mound under creature `i`'s coming-up stands out of the sand (metres; -1 without one), for tests and tools.
func mound_top(i: int) -> float:
	if not _mounds.has(i):
		return -1.0
	var dome: MeshInstance3D = _mounds[i]["dome"]
	return dome.scale.y * float((dome.mesh as SphereMesh).height) * 0.5


## The first frame of strip `strip` in type `t`'s sheet, and how many frames it has.
func strip_frames(t: int, strip: int) -> Vector2i:
	return Vector2i(_t_off[t * N_ANIMS + strip], _t_cnt[t * N_ANIMS + strip])


## EnemyDef.front_faces / back_faces as the _t_face_fix code (pass 45).
static func _face_fix(s: String) -> int:
	return 1 if s == "left" else (2 if s == "straight" else 0)


## The mirror bit the shader sees for creature `i`'s strip (pass 45): the tick's `flip` ("heading screen-left") as it
## is, inverted for a front or back painting that turns the other way (the hellhound's front cycle runs down-left, so
## as painted it looked away from the hero on both sides), cleared for one painted straight on. Side and diagonal sets
## (strips 7..12) always face right, so only the front set (0..4) and the back set (5, 6) read the table.
func _face_bit(f: int, t: int, strip: int) -> float:
	var fix: int = _t_face_fix[t * 2 + (1 if strip == 5 or strip == 6 else 0)]
	if fix == 1:
		return 1.0 - float(f)
	elif fix == 2:
		return 0.0
	return float(f)


func _render() -> void:
	_update_mark()
	# compact instances per type
	var counters := PackedInt32Array()
	counters.resize(types.size())
	var shadow_n := 0
	# with a big crowd only the creatures around the hero cast a shadow: the far ones are a metre of dark quad each
	# and they overlap into a wall of blending on a phone
	var shadow_all: bool = count_alive <= SHADOW_BUDGET
	var shadow_r2 := 100.0
	var badge_n: Dictionary = {}
	var ppos2: Vector3 = player.global_position if player else Vector3.ZERO
	var cam_x := 0.0
	# the shadow's axes follow the camera (screen-right, towards the camera on the ground), and a painting that sinks
	# (EnemyDef.shadow "drop", pass 47) slides down the billboard's own plane, the camera's up
	var scf := _cf_tick
	var scr := Vector3(-scf.z, 0, scf.x)
	var cam_up := _cam_up()
	# a creature wading in the lake casts no shadow (pass 54, in_lake), nor one the drawn water covers any of from the
	# camera (pass 56, shadow_wet); only those near the lake are asked (pass 80: near any lake, _near_water)
	var lake := _lake_refresh()
	var vp := get_viewport()
	var eye_cam: Camera3D = vp.get_camera_3d() if vp else null
	var eye: Vector3 = eye_cam.global_position if eye_cam else Vector3.INF
	for i in range(MAX):
		if alive[i] == 0 or hidden[i] == 1:
			continue
		var t := type_idx[i]
		var mm: MultiMesh = _t_mm[t]
		var k := counters[t]
		var s := size[i]
		var st := state[i]
		var strip := _strip_of(i, t)
		var n := _t_cnt[t * N_ANIMS + strip]
		var frame := _t_off[t * N_ANIMS + strip] + (mini(int(anim_t[i]), n - 1) if strip == A_DIE else (int(anim_t[i]) % maxi(n, 1)))
		if strip == A_ATTACK and _t_atkv[t] == 1:
			# pass 73 (lane SNIPER): the front or the back half of an attack strip painted both ways (the sniper's aim)
			frame = _attack_view_frame(i, t)
		var sq := squash[i]
		# procedural bob while moving
		if strip == A_RUN:
			sq += sin(anim_t[i] * 1.5) * 0.05
		# a charger's carriage through its wind-up and charge (pass 50, charge_pose): crouch, shake and rock, then bounce,
		# rumble and lean
		var cp := Vector4(0.0, 0.0, 1.0, 0.0)
		if st == STATE_WINDUP or st == STATE_CHARGE:
			cp = charge_pose(i, scr)
			sq *= cp.z
		# the painting sinks by its tuning's share of the cell (pass 47): the empty cell under painted legs goes under the
		# sand, and the legs stand on the foot point
		var drop: float = _t_sh[t * 4 + 3]
		var at := pos[i] + Vector3(0, lift_h[i] + cp.y, 0) + scr * cp.x
		if drop != 0.0:
			at -= sprite_sink(i, sq, cam_up)
		# rising out of the sand (pass 60): the painting sits down the billboard's up by the part still under, the terrain
		# hiding it; quick at first and settling (an ease-out), the figure's top (`head`) reaching the ground at 0
		var rise: float = rise_t[i]
		var rise_k := rise_ease(rise)
		if rise < 1.0:
			at -= rise_sink(i, sq, cam_up)
		var xb: Basis = Basis().scaled(Vector3(s, s, s)) if cp.w == 0.0 else roll_basis(s, cp.w)
		if rise < 1.0:
			# pass 73 (lane GROUND): the ground-clip, the share of the quad under the sand (the shader reads basis.z.y)
			xb.z = Vector3(xb.z.x, ground_clip(i), xb.z.z)
		mm.set_instance_transform(k, Transform3D(xb, at))
		# the flash: white, green for a poison tick (negative), orange for a fire tick (2 + flash)
		var fl: float = flash[i]
		if i == bounty_i and fl < 0.4:
			# the bounty: a strong warm pulse, brighter than the rocketeer's, so it stands out of a crowd
			fl = 0.4 + 0.25 * sin(_glow_clock * 3.0)
			flash_hot[i] = 1
		if flash_green[i] == 1:
			fl = -fl
		elif flash_hot[i] == 1:
			fl = 2.0 + fl
		var fy := _face_bit(flip[i], t, strip)
		if i == tethered_i and st != STATE_DYING:
			# the red outline of the creature holding the rope (levels 0..16 on top of the flip bit)
			fy += 2.0 * roundf(tether_glow() * 16.0)
		if vglow[i] > 0.0 and st != STATE_DYING:
			# pass 69: a variance special's rim in its tint's colour (special_glow_code: levels 0..16 above the rest)
			fy += special_glow_code(vglow[i])
		# (the frame carries RISE_FLAG in its fraction while the figure rises: no silhouette of the part under the sand)
		mm.set_instance_custom_data(k, Color(frame_code(frame, rise), fy, fl, sq))
		mm.set_instance_color(k, tint_of(i))
		counters[t] = k + 1
		# the badge over its head: from the feet up the screen past the top of the figure, then half the badge
		var bk: String = _t_badge[t]
		if bk != "" and st != STATE_DYING:
			var bmm := _badge_mm(bk)
			if bmm:
				var bn: int = int(badge_n.get(bk, 0))
				if bn < BADGE_MAX:
					var td: Dictionary = types[t]
					var def: EnemyDef = td["def"]
					# a skull is a boss's, and drawn at a boss's size wherever it hangs (pass 49: the arena's Boss dummy is an
					# Elite by its kind)
					var bs: float = BADGE_SIZE * _badge_scale * (1.3 if i == boss_index or def.archetype == "boss" or bk == "skull" else 1.0)
					bmm.set_instance_transform(bn, Transform3D(Basis(), pos[i] + Vector3(0, lift_h[i], 0)))
					# (pass 60: riding up with a rising figure's top)
					bmm.set_instance_custom_data(bn, Color(s * maxf(float(td["head"]) * rise_k - drop, 0.0) * maxf(sq, 0.2) + 0.12 + bs * 0.5, bs, float(i) * 1.7, 0.0))
					badge_n[bk] = bn + 1
		# shadow (stays on the ground and shrinks while the creature is in the air; none over the water, pass 54 and 56)
		# pass 84 (the lead; Garry: "The shadows on the enemies ... at certain angles and at certain distances they don't
		# render"): with a crowd over SHADOW_BUDGET only the first 70 within 10 m of the hero had a shadow, so the creatures
		# up the portrait screen lost theirs; now every creature the camera sees (or within 10 m) casts one, its draped
		# transform reused until it moves (_shadow_xform_cached)
		if shadow_all or pos[i].distance_squared_to(ppos2) < shadow_r2 or (eye_cam != null and eye_cam.is_position_in_frustum(pos[i])):
			var sxf := _shadow_xform_cached(i, scf, scr)
			if rise < 1.0:
				# the shadow grows in under a figure rising out of the sand (pass 60; the blob has no alpha of its own)
				var sk := lerpf(0.35, 1.0, rise_k)
				sxf.basis = sxf.basis.scaled(Vector3(sk, 1.0, sk))
			if not (lake and _near_water(pos[i]) and shadow_wet(i, sxf, eye)):
				_shadow_mm.set_instance_transform(shadow_n, sxf)
				shadow_n += 1
	for t in range(types.size()):
		if _warm_at != Vector3.INF:
			var mm: MultiMesh = types[t]["mm"]
			mm.set_instance_transform(counters[t], Transform3D(Basis(), _warm_at))
			mm.set_instance_custom_data(counters[t], Color(0, 0, 0.5, 1))
			mm.set_instance_color(counters[t], Color(1, 1, 1, 0))
			counters[t] += 1
		types[t]["mm"].visible_instance_count = counters[t]
	if _warm_at != Vector3.INF and shadow_n < MAX:
		# one shadow in the warm-up pit too, so its blend shader compiles behind the spawn beam (pass 47)
		_shadow_mm.set_instance_transform(shadow_n, Transform3D(Basis().scaled(Vector3(0.5, 1, 0.3)), _warm_at))
		shadow_n += 1
	_shadow_mm.visible_instance_count = shadow_n
	for bk in _badges.keys():
		var bmm2: MultiMesh = _badges[bk]
		if bmm2:
			var bn2: int = int(badge_n.get(bk, 0))
			if _warm_at != Vector3.INF and bn2 < BADGE_MAX:
				bmm2.set_instance_transform(bn2, Transform3D(Basis(), _warm_at))
				bmm2.set_instance_custom_data(bn2, Color(1.0, 0.3, 0.0, 0.0))
				bn2 += 1
			bmm2.visible_instance_count = bn2


# ---------------------------------------------------------------- pass 73 (lane SNIPER): target priority, flee on hit, the Saiga Sniper

## The weapons' target priority (pass 73; the map's `target_priority`, WaveTimeline, handed on by the director's
## _apply_mults): on or off, and how far from the hero (a turret: from itself) a special, an Elite or the boss is taken
## first. A manager without a director (tools, tests) plays WaveTimeline.TARGET_PRIORITY_DEFAULTS.
var target_priority_on := true
var target_priority_reach := 10.0
## diagnostics and tests: how many target choices the rule decided
var priority_picks := 0
## per type: 1 for a type every one of which is a priority creature (a gear-badge special, an Elite or a boss by its kind)
var _t_prio := PackedByteArray()
## per type: 1 when its attack strip holds the front and the back views (EnemyDef.attack_views "front_back")
var _t_atkv := PackedByteArray()


func set_target_priority(cfg: Dictionary) -> void:
	target_priority_on = bool(cfg.get("enabled", WaveTimeline.TARGET_PRIORITY_DEFAULTS["enabled"]))
	target_priority_reach = maxf(float(cfg.get("reach", WaveTimeline.TARGET_PRIORITY_DEFAULTS["reach"])), 0.0)


## Whether creature `i` is one the weapons take first (pass 73): a coloured variance special, a gear-badge special (the
## Vulture Raider, the harpooner, the Saiga Sniper), an Elite (by its kind, or wearing an elite modifier) or the boss.
func is_priority(i: int) -> bool:
	if i < 0 or i >= MAX or alive[i] == 0:
		return false
	_grow_prio()
	return vspecial[i] == 1 or elite_idx[i] >= 0 or i == boss_index or _t_prio[type_idx[i]] == 1


func _grow_prio() -> void:
	while _t_prio.size() < types.size():
		var t := _t_prio.size()
		_t_prio.append(1 if _t_big[t] == 1 or _t_badge[t] == "gear" else 0)


## The creature a weapon that chooses its target takes first (pass 73; Garry: "Player Attacks should prioritize Special
## Enemies, Elites and Bosses once Player is close enough to them. This is to make it more predictable to kill them"): the
## nearest priority creature (is_priority) within min(`range_m`, target_priority_reach) of `from`, standing (not dying,
## buried or held: the grid's own rule), on the screen unless `any_screen`. -1 for none, or with the rule off. Every
## chooser asks this first and falls back on its own rule (WeaponBehavior.aim_index and priority_pick; the seekers'
## retarget; only the first shot of a volley that spreads over different creatures).
func priority_target(from: Vector3, range_m: float, any_screen: bool = false) -> int:
	if not target_priority_on:
		return -1
	var reach := minf(range_m, target_priority_reach)
	if reach <= 0.0:
		return -1
	var list := _priority_list()
	if list.is_empty():
		return -1
	var so := _screen_only(any_screen)
	var best := -1
	var best_d := reach * reach
	for i in list:
		# standing as the grid keeps them: alive, not dying, buried or held
		if alive[i] == 0 or state[i] == STATE_DYING or hidden[i] == 1 or held[i] == 1:
			continue
		if so and onscreen[i] == 0:
			continue
		# pass 73 (lane GROUND): one still rising out of the sand (or sinking into it) is never chosen yet
		if rise_t[i] < rise_targetable:
			continue
		var dx := pos[i].x - from.x
		var dz := pos[i].z - from.z
		var d2 := dx * dx + dz * dz
		if d2 <= best_d:
			best_d = d2
			best = i
	if best >= 0:
		priority_picks += 1
	return best


## The priority creatures alive (pass 73), gathered again after each grid rebuild (once a tick) or spawn: priority_target
## scans this short list instead of the crowd in reach (perf_late, stage 3: the radius query on every weapon's pick cost
## about 0.2 ms a frame on the PC).
var _prio_list := PackedInt32Array()
var _prio_epoch := -1
var _prio_serial := -1
var _grid_epoch := 0


func _priority_list() -> PackedInt32Array:
	if _prio_epoch == _grid_epoch and _prio_serial == _serial:
		return _prio_list
	_prio_epoch = _grid_epoch
	_prio_serial = _serial
	_grow_prio()
	_prio_list.clear()
	for i in range(MAX):
		if alive[i] == 0 or state[i] == STATE_DYING:
			continue
		if vspecial[i] == 1 or elite_idx[i] >= 0 or i == boss_index or _t_prio[type_idx[i]] == 1:
			_prio_list.append(i)
	return _prio_list


## Flee on hit (pass 73; Garry: "Being hit causes the aiming to stop. And the enemy tries to run away with a small 1 second
## speed boost ... Add this ability as something I can add to any enemy"): creature index -> {serial, t, mult}.
var _flee: Dictionary = {}
## diagnostics and tests
var flee_starts := 0


## A hit landed on creature `i` (pass 73, from damage(): a hit that took health, never a poison or fire tick): its flee on
## hit (EnemyDef.flee_on_hit), and the rockets it has in the air shake and slow (ProjectileManager.shooter_hit).
func _on_hit_reactions(i: int, def: EnemyDef, dealt: float, tick: bool) -> void:
	if tick or dealt <= 0.0 or alive[i] == 0:
		return
	if not def.flee_on_hit.is_empty():
		flee_start(i, def)
	# pass 81 (lane POLISH): a sniper's aim is spoiled by a hit without any running (sniper_spoil_on_hit)
	if def.brain == "sniper":
		sniper_spoil_on_hit(i, def)
	if def.brain == "artillery" and game != null:
		var pm = game.get("projectiles")
		if pm != null and pm.has_method("shooter_hit"):
			pm.shooter_hit(i)


## Creature `i` starts (or starts again) its flee on hit (pass 73, EnemyDef.flee_on_hit {seconds 1, speed_mult 1.8,
## interrupts true}): with `interrupts` a wind-up or aim under way is dropped (_interrupt: the shot never comes), and for
## `seconds` it runs straight away from the hero at its speed x `speed_mult` (_flee_steer), its brain idle. A new hit
## starts the clock again (the run is never faster). Never a boss, nor one held, buried or in the air. True when it runs.
func flee_start(i: int, def: EnemyDef = null) -> bool:
	if i < 0 or i >= MAX or alive[i] == 0 or state[i] == STATE_DYING:
		return false
	if def == null:
		def = types[type_idx[i]]["def"]
	var fo: Dictionary = def.flee_on_hit
	if fo.is_empty() or i == boss_index or def.archetype == "boss" or held[i] == 1 or hidden[i] == 1 or lift_t[i] > 0.0:
		return false
	var secs := float(fo.get("seconds", 1.0))
	if secs <= 0.0:
		return false
	if bool(fo.get("interrupts", true)):
		_interrupt(i, def)
	_flee[i] = {"serial": serial[i], "t": secs, "mult": maxf(float(fo.get("speed_mult", 1.8)), 0.0)}
	flee_starts += 1
	return true


## Whether creature `i` is running from a hit right now (pass 73).
func is_fleeing(i: int) -> bool:
	return _flee.has(i) and int((_flee[i] as Dictionary)["serial"]) == serial[i] and alive[i] == 1


## A wind-up or aim under way is dropped (pass 73, flee on hit's `interrupts`), as a stun drops one: the shot, charge or
## scripted attack never comes and the next try waits a beat (a sniper: its aim and lines, _sniper_cancel; the Vulture
## Raider: his rocket stays in the tube and he reloads).
func _interrupt(i: int, def: EnemyDef) -> void:
	if def.brain == "sniper":
		_sniper_cancel(i, def)
		return
	match state[i]:
		STATE_WINDUP:
			state[i] = STATE_MOVE
			cooldown[i] = maxf(cooldown[i], 1.0)
			if def.brain == "artillery":
				atk_i[i] = 0
				cooldown[i] = maxf(cooldown[i], float(def.artillery.get("reload", 2.5)))
		STATE_ATTACK:
			state[i] = STATE_MOVE
			atk_t[i] = maxf(atk_t[i], 1.0)


## Flee on hit's run (pass 73), from _steer before the brain: straight away from the hero at its speed x mult (along the
## wall when backed against it), round the rocks; true while it runs (the brain waits), false once it is over.
func _flee_steer(i: int, dir: Vector3, spd: float, dt: float) -> bool:
	var f: Dictionary = _flee[i]
	if int(f["serial"]) != serial[i]:
		_flee.erase(i)
		return false
	var left := float(f["t"]) - dt
	if left <= 0.0:
		_flee.erase(i)
		return false
	f["t"] = left
	var run_dir := -dir
	if run_dir.length_squared() < 0.0001:
		run_dir = Vector3(cos(float(i)), 0.0, sin(float(i)))
	var want := _along_wall(i, run_dir) * spd * float(f["mult"])
	vel[i] = want + _obstacle_push(i) * 4.0
	intent[i] = want
	return true


## A run's heading `d` (flat, unit) near the arena's wall (pass 73): the part that would take it out of the walkable disc
## goes, so a creature backed against the wall slides along it instead of standing there.
func _along_wall(i: int, d: Vector3) -> Vector3:
	var flat := Vector2(pos[i].x, pos[i].z)
	var r := flat.length()
	if r < arena_radius - 6.0 or r < 0.001:
		return d
	var out := Vector3(flat.x / r, 0.0, flat.y / r)
	var o := d.dot(out)
	if o <= 0.0:
		return d
	var tg := d - out * o
	if tg.length_squared() < 0.0001:
		tg = Vector3(-out.z, 0.0, out.x)
	return tg.normalized()


## The frame of the `attack` strip creature `i` shows (pass 73, EnemyDef.attack_views "front_back"): the strip's first half
## is painted from the front and its second half from the back; the half its facing shows (away), at the attack's pace.
func _attack_view_frame(i: int, t: int) -> int:
	var n := _t_cnt[t * N_ANIMS + A_ATTACK]
	var off := _t_off[t * N_ANIMS + A_ATTACK]
	if n < 2:
		return off
	var half := n >> 1
	return off + (half if away[i] == 1 else 0) + (int(anim_t[i]) % half)


# ---- the Saiga Sniper (pass 73; content/enemies/saiga_sniper, EnemyDef.sniper; drawn by SniperFx)

const SNIPER_IDLE := 0
const SNIPER_AIM := 1
const SNIPER_LOCK := 2
## after the shot he keeps the aiming pose SNIPER_AFTER_HOLD seconds (the beam's flash and a breath): he dropped back to
## his walk on the very frame the beam showed (the capture with lane ART's painting)
const SNIPER_AFTER := 3
const SNIPER_AFTER_HOLD := 0.35
## the wind-up's own timer while a sniper aims: its clock is _tick_snipers', so _steer's wind-up branch never runs it out
const SNIPER_HELD := 1.0e6
## how fast the aim follows the hero (1/s: a quick ease, so a dash still drags the lines after him)
const SNIPER_FOLLOW := 10.0
## the hero's body on the beam: hit when his feet are within the beam's half width + this of its line
const SNIPER_HERO_R := 0.4
## a pushed creature's knockback, m/s for every metre of push (knockback dies away at 6 a second: v / 6 metres)
const KB_PER_M := 6.0
## sniper index -> {serial, phase, t, aim (the point it follows), dir (flat: from it to that point), lines (SniperFx.line_plan),
## from, ldir, d (the locked muzzle, line and distance)}
var _snipers: Dictionary = {}
var _sniper_fx: SniperFx = null
## diagnostics and tests
var sniper_aims := 0
var sniper_shots := 0
var sniper_hero_hits := 0
var sniper_cancels := 0
var sniper_last: Dictionary = {}


## A sniper comes in (pass 73, from spawn()): at its stand-off from the hero like the Vulture Raider (never closer, inside
## the wall), its first aim `first` seconds after it lands.
func _sniper_spawned(i: int, def: EnemyDef) -> void:
	var sn: Dictionary = def.sniper
	if player:
		var so := float(sn.get("stand_off", 26.0))
		var pp: Vector3 = player.global_position
		var d := pos[i] - pp
		d.y = 0.0
		if d.length_squared() < 0.01:
			d = Vector3.FORWARD
		if d.length() < so:
			var np: Vector3 = pp + d.normalized() * so
			var map = game.get("map") if game != null else null
			if map != null and map.has_method("clamp_to_arena"):
				np = map.clamp_to_arena(np)
			else:
				np = _clamp_arena(np)
			pos[i] = Vector3(np.x, _height(np.x, np.z), np.z)
			home[i] = pos[i]
	cooldown[i] = maxf(float(sn.get("first", 2.5)), 0.0)
	_snipers[i] = {"serial": serial[i], "phase": SNIPER_IDLE}


## The sniper's walk (pass 73, _steer's brain "sniper" while it is not aiming): inside `flee_range` of the hero it runs
## (straight away, along the wall when backed against it); past `follow` (stand_off + 12 m) it walks back in; between, it
## stands, and once its rest is over (cooldown) it starts an aim at him. Pass 81 (lane POLISH; Garry: "Remove that
## feature [his running away] entirely, just make it like a similar behaviour to the Cactus ranged enemy, but with a bit
## more speed"): `flee_range` is 0 unless the data names one (the Saiga's is 0: it never runs), so it walks the kite's
## way: in towards the hero while he is farther than `follow`, then it holds where it is and aims, and never backs off.
func _sniper_steer(i: int, def: EnemyDef, dir: Vector3, dist: float, spd: float) -> Vector3:
	var sn: Dictionary = def.sniper
	if dist < float(sn.get("flee_range", 0.0)):
		var run_dir := -dir if dir.length_squared() > 0.0001 else Vector3(cos(float(i)), 0.0, sin(float(i)))
		return _along_wall(i, run_dir) * spd
	if dist > float(sn.get("follow", float(sn.get("stand_off", 26.0)) + 12.0)):
		return dir * spd
	if cooldown[i] <= 0.0 and player != null and player.get("dead") != true:
		_sniper_aim_start(i, def, dir)
	return Vector3.ZERO


## The aim starts (pass 73): frozen in the aiming pose (a held wind-up: the `attack` strip), facing the hero, the lines'
## plan drawn for this aim.
func _sniper_aim_start(i: int, def: EnemyDef, dir: Vector3) -> void:
	var sn: Dictionary = def.sniper
	state[i] = STATE_WINDUP
	timer[i] = SNIPER_HELD
	charge_dir[i] = dir
	vel[i] = Vector3.ZERO
	_snipers[i] = {"serial": serial[i], "phase": SNIPER_AIM, "t": 0.0, "aim": player.global_position, "dir": dir,
		"lines": SniperFx.line_plan(int(sn.get("lines", 14)), float(sn.get("aim", 2.0)), float(sn.get("cone_deg", 44.0)), _rng)}
	sniper_aims += 1
	Audio.play(str(def.sfx.get("aim", "")), pos[i])
	if game != null and game.has_method("hint_once"):
		game.hint_once("sniper", "SAIGA SNIPER: step off his red line before he fires. Hit him to spoil his aim.")


## The aim is dropped (pass 73: a hit with flee on hit's `interrupts`, a stun, a freeze, a launch, the hero down): no shot,
## the lines go with it, and the next aim waits `recover` seconds (2.5) at least.
func _sniper_cancel(i: int, def: EnemyDef) -> void:
	var s: Dictionary = _snipers.get(i, {})
	if s.is_empty() or int(s.get("serial", -1)) != serial[i]:
		return
	var was := int(s.get("phase", SNIPER_IDLE))
	if was == SNIPER_AIM or was == SNIPER_LOCK:
		sniper_cancels += 1
		cooldown[i] = maxf(cooldown[i], float(def.sniper.get("recover", 2.5)))
	s["phase"] = SNIPER_IDLE
	if state[i] == STATE_WINDUP:
		state[i] = STATE_MOVE


## Pass 81 (lane POLISH): a hit that lands on a sniper (from _on_hit_reactions: one that took health, never a poison or
## fire tick) drops its aim or lock under way when its `sniper.spoil_on_hit` is true (the default): the shot never comes
## and the next aim waits `recover` (_sniper_cancel). Pass 73 had this from flee on hit's `interrupts`; the Saiga runs no
## more (Garry), so the spoil is the sniper's own. True when an aim was dropped.
func sniper_spoil_on_hit(i: int, def: EnemyDef) -> bool:
	if not bool(def.sniper.get("spoil_on_hit", true)):
		return false
	var s: Dictionary = _snipers.get(i, {})
	if s.is_empty() or int(s.get("serial", -1)) != serial[i]:
		return false
	var ph := int(s.get("phase", SNIPER_IDLE))
	if ph != SNIPER_AIM and ph != SNIPER_LOCK:
		return false
	_sniper_cancel(i, def)
	return true


## The snipers' aims, once a tick (pass 73, from _physics_process): the aim follows the hero for `aim` seconds, locks,
## holds `lock` seconds and fires (_sniper_fire), on the creatures' clock (a hamper slows it, the pace knob stretches it
## as it does every wind-up); anything that drops the wind-up (a stun, a launch, a freeze, a grab) drops the aim. What
## shows is handed to SniperFx every tick.
func _tick_snipers(delta: float, ppos: Vector3) -> void:
	if _snipers.is_empty() and _sniper_fx == null:
		return
	var fx := _sniper_fx_node()
	fx.time_scale = time_scale
	fx.begin()
	for key in _snipers.keys():
		var i: int = int(key)
		var s: Dictionary = _snipers[key]
		if alive[i] == 0 or serial[i] != int(s["serial"]) or state[i] == STATE_DYING:
			_snipers.erase(key)
			continue
		var phase := int(s["phase"])
		if phase == SNIPER_IDLE:
			continue
		if phase == SNIPER_AFTER:
			# the aiming pose held a breath after the shot; anything that moves him ends it at once
			s["t"] = float(s["t"]) + delta
			if float(s["t"]) >= SNIPER_AFTER_HOLD or state[i] != STATE_WINDUP or freeze_t[i] > 0.0 or stun_t[i] > 0.0:
				s["phase"] = SNIPER_IDLE
				if state[i] == STATE_WINDUP:
					state[i] = STATE_MOVE
			continue
		var def: EnemyDef = types[type_idx[i]]["def"]
		if state[i] != STATE_WINDUP or freeze_t[i] > 0.0 or stun_t[i] > 0.0 or held[i] == 1 or hidden[i] == 1 or lift_t[i] > 0.0 \
				or player == null or player.get("dead") == true:
			_sniper_cancel(i, def)
			continue
		var sn: Dictionary = def.sniper
		s["t"] = float(s["t"]) + delta * attack_clock(i) * pace
		if phase == SNIPER_AIM:
			var aim_pt: Vector3 = (s["aim"] as Vector3).lerp(ppos, clampf(delta * SNIPER_FOLLOW, 0.0, 1.0))
			s["aim"] = aim_pt
			var d := aim_pt - pos[i]
			d.y = 0.0
			if d.length_squared() > 0.01:
				s["dir"] = d.normalized()
				charge_dir[i] = d.normalized()
			var total := float(sn.get("aim", 2.0))
			var from := _sniper_muzzle(i, def, s["dir"])
			if float(s["t"]) < total:
				fx.aim(from, aim_pt, float(s["t"]), total, s["lines"])
				continue
			# the lock: the line stops following him
			var ld := Vector3(aim_pt.x - from.x, 0.0, aim_pt.z - from.z)
			s["phase"] = SNIPER_LOCK
			s["t"] = 0.0
			s["from"] = from
			s["ldir"] = ld.normalized() if ld.length_squared() > 0.0001 else s["dir"]
			s["d"] = ld.length()
			Audio.play(str(def.sfx.get("lock", "")), pos[i])
		var bm := _beam_block(def)
		var hold := float(sn.get("lock", 1.0))
		if float(s["t"]) >= hold:
			_sniper_fire(i, def, s)
		else:
			fx.lock(s["from"], s["ldir"], float(s["d"]), float(s["t"]), hold, float(bm.get("length", 60.0)), float(bm.get("width", 0.5)))


## Where the sniper's shot leaves (pass 73): the rifle's muzzle as painted, the def's `sniper.muzzle` {up, side, forward}
## in metres at its size, scaled with this spawn's: `up` along the billboard's up, `side` towards the barrel (screen-right
## as painted, screen-left when the painting is mirrored), `forward` along the aim. Without one, 0.65 of its size up.
func _sniper_muzzle(i: int, def: EnemyDef, aim: Vector3) -> Vector3:
	var mz = def.sniper.get("muzzle", {})
	if not (mz is Dictionary) or (mz as Dictionary).is_empty():
		return pos[i] + Vector3(0, size[i] * 0.65, 0)
	var k: float = size[i] / maxf(def.size, 0.01)
	var sgn := -1.0 if _face_bit(flip[i], type_idx[i], A_ATTACK) > 0.5 else 1.0
	var scr := Vector3(-_cf_tick.z, 0, _cf_tick.x)
	var a := Vector3(aim.x, 0, aim.z)
	a = a.normalized() if a.length_squared() > 0.0001 else Vector3.ZERO
	var at := pos[i] + Vector3(0, lift_h[i], 0)
	return at + _cam_up() * (float(mz.get("up", 0.0)) * k) + scr * (sgn * float(mz.get("side", 0.0)) * k) + a * (float(mz.get("forward", 0.0)) * k)


func _beam_block(def: EnemyDef) -> Dictionary:
	var b = def.sniper.get("beam", {})
	return b if b is Dictionary else {}


## The beam's damage to the hero (pass 73): `beam.damage_mult` (0.7) x the missile damage of the creature
## `beam.damage_from` names (the Vulture Raider's rocket, read from its data so his number leads), else `beam.damage`;
## times this sniper's own stage, level and hostile factors, as the rocket's (_fire_artillery).
func sniper_damage(i: int, def: EnemyDef) -> float:
	var bm := _beam_block(def)
	var base := float(bm.get("damage", 15.4))
	var src := str(bm.get("damage_from", ""))
	if src != "":
		var sd: EnemyDef = Registry.enemy(src)
		if sd != null and sd.artillery.get("missile") is Dictionary and (sd.artillery["missile"] as Dictionary).has("damage"):
			base = float(sd.artillery["missile"]["damage"]) * float(bm.get("damage_mult", 0.7))
	return base * stage_of(i) * lvd_of(i) * host_of(i)


## How far `p` stands off a beam from `from` along `dir` (flat, unit) for `length` m, on the ground's plane (pass 73).
static func beam_distance(p: Vector3, from: Vector3, dir: Vector3, length: float) -> float:
	var rx := p.x - from.x
	var rz := p.z - from.z
	var s := clampf(rx * dir.x + rz * dir.z, 0.0, length)
	return Vector2(rx - dir.x * s, rz - dir.z * s).length()


## The shot (pass 73): the beam from the muzzle along the locked line, `beam.length` m over the map, `beam.width` wide. The
## hero, when his feet are within half its width + SNIPER_HERO_R of its line, takes sniper_damage and a knock of
## `beam.knockback` along it; every creature on it takes `creature_frac` of its max HP (at most `creature_max`) and is
## pushed `push` m off the line to the side it stood on. Then the sparks, and a rest of interval +- interval_jitter from
## this shot to the next (less the aim and the hold, which run on the creatures' clock).
func _sniper_fire(i: int, def: EnemyDef, s: Dictionary) -> void:
	var sn: Dictionary = def.sniper
	var bm := _beam_block(def)
	var from: Vector3 = s["from"]
	var dir: Vector3 = s["ldir"]
	var length := float(bm.get("length", 60.0))
	var width := float(bm.get("width", 0.5))
	var half := width * 0.5
	var dealt := sniper_damage(i, def)
	var hit_hero := false
	if player != null and player.get("dead") != true:
		if beam_distance(player.global_position, from, dir, length) <= half + SNIPER_HERO_R:
			var info := hit_info(i, "ranged", ["laser"])
			info["knock"] = float(bm.get("knockback", 5.0))
			player.take_damage(dealt, from, info)
			hit_hero = true
			sniper_hero_hits += 1
	var frac := float(bm.get("creature_frac", 0.05))
	var cap := float(bm.get("creature_max", 40.0))
	var push := float(bm.get("push", 3.0))
	var side := Vector3(-dir.z, 0.0, dir.x)
	var hit := PackedInt32Array()
	for j in range(MAX):
		if j == i or alive[j] == 0 or state[j] == STATE_DYING or hidden[j] == 1 or held[j] == 1:
			continue
		if beam_distance(pos[j], from, dir, length) <= half + radius[j]:
			hit.append(j)
	for j in hit:
		if alive[j] == 0 or state[j] == STATE_DYING:
			continue
		var rel := Vector3(pos[j].x - from.x, 0.0, pos[j].z - from.z)
		var sg := 1.0 if rel.dot(side) >= 0.0 else -1.0
		kb[j] += side * (sg * push * KB_PER_M * _t_kbt[type_idx[j]] * (0.15 if j == boss_index else 1.0))
		damage(j, minf(max_hp[j] * frac, cap), "", Vector3.ZERO, 0.0)
	_sniper_fx_node().beam(from, dir, length, width, float(s["d"]), float(bm.get("seconds", 0.15)), float(bm.get("sparks", 1.5)))
	if game != null and game.has_method("fx_burst"):
		game.fx_burst(from, Color(1.0, 0.35, 0.3), 1.3)
	Audio.play(str(def.sfx.get("shot", "")), from)
	sniper_shots += 1
	sniper_last = {"from": from, "dir": dir, "length": length, "width": width, "damage": dealt, "hero_hit": hit_hero, "creatures": hit.size()}
	var iv := float(sn.get("interval", 9.0)) + _rng.randf_range(-1.0, 1.0) * float(sn.get("interval_jitter", 1.5))
	var p := maxf(pace, 0.05)
	cooldown[i] = maxf(iv - (float(sn.get("aim", 2.0)) + float(sn.get("lock", 1.0))) / p, 0.5)
	# the aiming pose held a breath after the shot (SNIPER_AFTER); the rest above runs from now
	s["phase"] = SNIPER_AFTER
	s["t"] = 0.0


func _sniper_fx_node() -> SniperFx:
	if _sniper_fx == null or not is_instance_valid(_sniper_fx):
		_sniper_fx = SniperFx.new()
		_sniper_fx.name = "SniperFx"
		_sniper_fx.height_fn = _height
		add_child(_sniper_fx)
	return _sniper_fx


# ---------------------------------------------------------------- custom boss attacks (pass 72, lane BOSS)

## Garry: "add the ability to create custom attacks for bosses. Like colouring the projectile, deciding the ranges, etc.
## Like create custom ones that I can name". A `boss.attacks` entry {"name": "<id>"} naming a content/boss_attacks attack
## (BossAttackDef) plays it: the runner's list is resolved once per def (custom_resolved, BossAttackDef.runner_entry: its
## wind-up, no built-in telegraph, or for a `script` attack the built-in it wraps), the wind-up's marks are drawn by
## _custom_attack_begin, the attack starts in the runner's fire step (its `_:` branch calls _custom_attack_fire), and
## _tick_custom_attacks plays whatever is in the air on the creatures' shot clock (delta x pace, delta already carrying
## High Noon's time_scale: the clock every hostile shot flies on, hostile_clock). BossAttackFx draws the shots.
## Boss HP pegged to the hero's DPS (pass 72): the multiplier the next boss spawn takes, held by the director around it
## (WaveDirector.boss_dps_scale), 1 otherwise.
var boss_hp_scale := 1.0
## Pass 83 (lane SCALE): the least HP the next boss spawn comes with (WaveDirector.boss_seconds_target, held around
## the spawn), 0 otherwise.
var boss_hp_target := 0.0
var _custom_runs: Array = []
var _custom_cache: Dictionary = {}     # a def's instance id -> [its attacks list, the resolved list]
var _custom_aim: Dictionary = {}       # creature -> {serial, aim, center}: what the wind-up showed, fixed for the fire
var _custom_fx: BossAttackFx = null
## Counts for the tests and the capture: spots landed, shots fired, hits on the hero, the last attack fired.
var custom_landed := 0
var custom_fired := 0
var custom_hits := 0
var custom_last: Dictionary = {}
## How long a landed spike stays stuck in the sand, on the shot clock.
const CUSTOM_STICK := 0.55
## Seconds of the shot clock between two of a rain's launch sounds.
const CUSTOM_SFX_GAP := 0.35


## The custom attack called `name`, or null (a built-in name never is one: BossAttackDef.SCRIPTS).
func custom_attack_of(name: String) -> BossAttackDef:
	if name == "" or BossAttackDef.SCRIPTS.has(name):
		return null
	return Registry.boss_attack(name)


## The attack list the runner plays for `def`: every entry naming a custom attack resolved (BossAttackDef.runner_entry),
## the others as they are; the list itself when it names none. Kept per def while the def's list is the same array.
func custom_resolved(def: EnemyDef, attacks: Array) -> Array:
	if attacks.is_empty() or def == null:
		return attacks
	var key: int = def.get_instance_id()
	var got = _custom_cache.get(key)
	if got is Array and is_same((got as Array)[0], attacks):
		return (got as Array)[1]
	var out: Array = []
	var any := false
	for a in attacks:
		var cdef: BossAttackDef = custom_attack_of(str((a as Dictionary).get("name", ""))) if a is Dictionary else null
		if cdef != null:
			out.append(cdef.runner_entry(a))
			any = true
		else:
			out.append(a)
	var res: Array = out if any else attacks
	_custom_cache[key] = [attacks, res]
	return res


## The rest after a custom attack: its own `timing.cooldown` when above 0, else `rest` (the boss's cooldown_between).
func custom_rest(atk: Dictionary, rest: float) -> float:
	if not atk.has("custom"):
		return rest
	var cdef := custom_attack_of(str(atk["custom"]))
	if cdef == null or cdef.num("timing", "cooldown") <= 0.0:
		return rest
	return cdef.num("timing", "cooldown")


func _custom_fx_node() -> BossAttackFx:
	if _custom_fx == null or not is_instance_valid(_custom_fx):
		_custom_fx = BossAttackFx.new()
		_custom_fx.name = "BossAttackFx"
		add_child(_custom_fx)
	return _custom_fx


## The wind-up of a custom attack (the runner has set its timer: the wind-up x 1/pace): its aim and centre are fixed now,
## as its marks show them: a slam's disc, a ring's circle, a volley's lines, the outline of a rain's whole area.
func _custom_attack_begin(i: int, atk: Dictionary, ppos: Vector3) -> void:
	if not atk.has("custom"):
		return
	var cdef := custom_attack_of(str(atk["custom"]))
	if cdef == null:
		return
	var center: Vector3 = ppos if cdef.text("pattern", "center") == "hero" else pos[i]
	center.y = _height(center.x, center.z)
	var aim := atan2(charge_dir[i].z, charge_dir[i].x)
	match cdef.text("pattern", "aim"):
		"random":
			aim = _rng.randf() * TAU
		"fixed":
			aim = 0.0
	_custom_aim[i] = {"serial": serial[i], "aim": aim, "center": center}
	var ws := cdef.text("sounds", "windup")
	if ws != "":
		Audio.play(ws, pos[i])
	# pass 73 (lane GROUND): a rain lit all at once or spewed lays its spots out now (_custom_lit_start); its circles go up
	# together before the spew instead of the area's edge
	if cdef.attack_kind == "rain" and (cdef.lit_at_once() or cdef.is_volley()):
		_custom_lit_start(i, cdef, center)
		if cdef.lit_at_once():
			return
	if game == null or cdef.text("telegraph", "kind") == "none":
		return
	var col := cdef.telegraph_color()
	var wind: float = maxf(timer[i], 0.05)
	var rmax := cdef.num("pattern", "radius_max")
	match cdef.attack_kind:
		"slam":
			game.telegraph_ring(center, rmax, wind, col)
		"ring":
			game.telegraph_ring(pos[i], rmax, wind, col, false)
		"rain":
			# the edge of where it will fall; each landing spot gets its own circle before its spike lands
			game.telegraph_ring(center, rmax, wind, Color(col.r, col.g, col.b, col.a * 0.6), false)
		"volley":
			for a: float in _custom_dirs(cdef, aim):
				game.telegraph_line(pos[i], Vector3(cos(a), 0, sin(a)), cdef.num("projectile", "range"), wind, col)


## The directions of a volley round `aim` (radians): `count` over `spread_deg` (all round at 360).
func _custom_dirs(cdef: BossAttackDef, aim: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := maxi(int(cdef.num("pattern", "count")), 1)
	var spread := deg_to_rad(clampf(cdef.num("pattern", "spread_deg"), 0.0, 360.0))
	for k in range(n):
		if spread >= TAU - 0.001:
			out.append(aim + TAU * float(k) / float(n))
		else:
			out.append(aim - spread * 0.5 + spread * float(k) / float(maxi(n - 1, 1)))
	return out


## The attack lands (the runner's fire step): a run is put in the air for the kinds that last (rain, volley, ring), a slam
## goes off at once. Its damage is `damage` x the boss's bite x its stage, hero-level and hostile factors (the factors
## every scripted attack carries); the boss stands for `timing.hold` (-1: while its shots leave).
func _custom_attack_fire(i: int, atk: Dictionary, ppos: Vector3) -> void:
	if not atk.has("custom"):
		return
	var cdef := custom_attack_of(str(atk["custom"]))
	if cdef == null:
		return
	var aimd: Dictionary = _custom_aim.get(i, {})
	if int(aimd.get("serial", -1)) != serial[i]:
		aimd = {"aim": atan2(charge_dir[i].z, charge_dir[i].x), "center": pos[i]}
	_custom_aim.erase(i)
	var bite: float = (types[type_idx[i]]["def"] as EnemyDef).damage
	var words: Array = [cdef.display_name.to_lower()]
	if cdef.knockback > 0.0:
		words.append("thrown" if cdef.lift > 0.0 else "knocked back")
	var look := cdef.text("projectile", "look")
	var tint := cdef.tint()
	var glow := cdef.num("projectile", "glow")
	var run := {"id": cdef.id, "def": cdef, "kind": cdef.attack_kind, "owner": i, "clock": 0.0,
		"damage": cdef.damage * bite * stage_of(i) * lvd_of(i) * host_of(i), "info": hit_info(i, "ranged", words),
		"look": look, "tint": tint, "glow": glow, "key": BossAttackFx.pool_key(look, tint, glow),
		"from": pos[i] + Vector3(0, size[i] * 0.75, 0), "center": aimd["center"]}
	var leave := 0.0
	match cdef.attack_kind:
		"rain":
			_custom_rain_start(run, cdef)
			leave = cdef.num("timing", "stagger")
			if cdef.is_volley():
				# pass 73 (lane GROUND): the spew from its mouth; it stands while its spikes leave and its stretch settles
				_custom_spew(i, cdef, run)
				leave = maxf(cdef.num("spew", "burst"), 0.0) + 0.35
		"volley":
			_custom_volley_start(run, cdef, float(aimd["aim"]))
			leave = maxf(cdef.num("pattern", "waves") - 1.0, 0.0) * cdef.num("pattern", "wave_gap")
		"ring":
			run["rings"] = []
			for w in range(maxi(int(cdef.num("pattern", "count")), 1)):
				(run["rings"] as Array).append({"t0": float(w) * cdef.num("pattern", "wave_gap"), "drawn": false, "hit": false})
			leave = maxf(cdef.num("pattern", "count") - 1.0, 0.0) * cdef.num("pattern", "wave_gap")
		"slam":
			_custom_slam(run, cdef, ppos)
		_:
			return
	if cdef.attack_kind != "slam":
		_custom_runs.append(run)
	var hold := cdef.num("timing", "hold")
	if hold < 0.0:
		hold = leave
	if hold > 0.0:
		hold_t[i] = maxf(hold_t[i], hold / maxf(pace, 0.05))
	var fs := cdef.text("sounds", "fire")
	if fs != "":
		Audio.play(fs, pos[i])
	custom_last = {"id": cdef.id, "kind": cdef.attack_kind, "spots": (run.get("spots", []) as Array).size(),
		"shots": (run.get("shots", []) as Array).size(), "center": run["center"], "damage": run["damage"]}
	if game and game.get("camera") and cdef.attack_kind != "slam":
		game.camera.shake(0.5)


## A rain's landing spots (BossAttackDef.rain_points round its centre, those past the arena's wall left out) and each
## one's landing time on the shot clock (BossAttackDef.land_times: the first after its flight, the last `stagger` later).
## Pass 73 (lane GROUND): _custom_rain_spots lays them out (a volley's on BossAttackDef.volley_times, each with its own
## flight `fl`); a rain lit or spewed at its wind-up's start takes the spots it laid out then (_custom_lit).
func _custom_rain_start(run: Dictionary, cdef: BossAttackDef) -> void:
	var i: int = run["owner"]
	var lit = _custom_lit.get(i)
	var spots: Array = []
	if lit is Dictionary and int((lit as Dictionary)["serial"]) == serial[i]:
		spots = (lit as Dictionary)["spots"]
		_custom_lit.erase(i)
	else:
		spots = _custom_rain_spots(cdef, run["center"])
	run["spots"] = spots
	run["flight"] = maxf(cdef.num("projectile", "flight"), 0.1)
	custom_fired += spots.size()


## A volley's shots: `waves` of them `wave_gap` apart, each wave one shot down every direction round the aim.
func _custom_volley_start(run: Dictionary, cdef: BossAttackDef, aim: float) -> void:
	var shots: Array = []
	var from: Vector3 = run["from"]
	from.y = _height(from.x, from.z) + 1.0
	for w in range(maxi(int(cdef.num("pattern", "waves")), 1)):
		for a: float in _custom_dirs(cdef, aim):
			shots.append({"t0": float(w) * cdef.num("pattern", "wave_gap"), "pos": from, "dir": Vector3(cos(a), 0, sin(a)),
				"gone": 0.0, "dead": false})
	run["shots"] = shots
	custom_fired += shots.size()


## A slam: the hero inside `radius_max` of its centre is hit, at once.
func _custom_slam(run: Dictionary, cdef: BossAttackDef, ppos: Vector3) -> void:
	var c: Vector3 = run["center"]
	var r := cdef.num("pattern", "radius_max")
	var d := ppos - c
	d.y = 0.0
	if d.length() <= r + 0.4:
		_custom_hit(run, cdef, c, ppos)
	if game:
		var tg = game.get("telegraphs")
		if tg and tg.has_method("flash_ring"):
			tg.flash_ring(c, r, cdef.tint(), 0.4)
		game.fx_burst(c + Vector3(0, 0.5, 0), cdef.tint(), r * 0.5)
		if game.get("camera"):
			game.camera.shake(1.0)


## The hero takes a custom attack's hit at `at`: its damage, and its knockback away from `at` (Player.take_damage's
## `knock`: a hit or a shield's catch moves him, an evade or a bubble never), thrown up `lift` metres when it has one.
func _custom_hit(run: Dictionary, cdef: BossAttackDef, at: Vector3, ppos: Vector3) -> void:
	if player == null or player.dead:
		return
	var info: Dictionary = (run["info"] as Dictionary).duplicate()
	info["knock"] = cdef.knockback
	player.take_damage(float(run["damage"]), at, info)
	custom_hits += 1
	if cdef.lift > 0.0 and cdef.knockback > 0.0 and player.has_method("blast") and str(player.get("last_outcome")) == "hit":
		var fling := ppos - at
		fling.y = 0.0
		if fling.length_squared() < 0.0001:
			fling = ppos - (run["from"] as Vector3)
			fling.y = 0.0
		if fling.length_squared() > 0.0001:
			player.blast(fling.normalized() * cdef.knockback, cdef.lift)


## Everything of the custom attacks in the air, a tick: the shot clock moves on, rains telegraph, fly and land, volleys fly
## and hit, rings race out; what is done is dropped. The shots are drawn afresh (BossAttackFx).
func _tick_custom_attacks(delta: float, ppos: Vector3) -> void:
	# pass 73 (lane GROUND): the rains lit or spewed whose wind-ups are on (their circles, the crouch)
	_tick_custom_lit(delta)
	if _custom_runs.is_empty():
		if _custom_fx != null and is_instance_valid(_custom_fx) and _custom_fx.drawn > 0:
			_custom_fx.begin()
			_custom_fx.finish()
		return
	var dc := delta * pace
	# shot-clock seconds a real second (the ground marks run on real time)
	var k_real := maxf(pace * time_scale, 0.05)
	var fx: BossAttackFx = _custom_fx_node() if game != null else null
	if fx:
		fx.begin()
	var keep: Array = []
	for run: Dictionary in _custom_runs:
		run["clock"] = float(run["clock"]) + dc
		var going := false
		match str(run["kind"]):
			"rain":
				going = _tick_custom_rain(run, ppos, k_real, fx)
			"volley":
				going = _tick_custom_volley(run, dc, ppos, fx)
			"ring":
				going = _tick_custom_ring(run, ppos, k_real)
		if going:
			keep.append(run)
	_custom_runs = keep
	if fx:
		fx.finish()


func _tick_custom_rain(run: Dictionary, ppos: Vector3, k_real: float, fx: BossAttackFx) -> bool:
	var cdef: BossAttackDef = run["def"]
	var c := float(run["clock"])
	var flight := float(run["flight"])
	var tel := maxf(cdef.num("telegraph", "seconds"), 0.0)
	var show_tel := cdef.text("telegraph", "kind") != "none" and game != null
	var lr := maxf(cdef.num("landing", "radius"), 0.05)
	var col := cdef.telegraph_color()
	var sz := maxf(cdef.num("projectile", "size"), 0.05)
	var peak := cdef.num("projectile", "arc")
	var trail := cdef.flag("projectile", "trail")
	var from: Vector3 = run["from"]
	var going := false
	var launching := false
	# pass 73 (lane GROUND): the circles lit all at once fill in as their shots come down
	_custom_marks_pulse(run["spots"], float(run["clock"]) / k_real, c)
	for s: Dictionary in run["spots"]:
		var land := float(s["land"])
		var at: Vector3 = s["at"]
		# (pass 73: a volley's spot has its own flight)
		var fl := float(s.get("fl", flight))
		if bool(s["done"]):
			if c - land < CUSTOM_STICK:
				going = true
				if fx:
					# stuck in the sand point first, sinking as it goes
					var sink := clampf((c - land) / CUSTOM_STICK, 0.0, 1.0)
					var dn := _custom_arc_dir(from, at, peak, 1.0)
					fx.put(run["key"], run["look"], run["tint"], run["glow"], _custom_xf(at - dn * (0.1 + 0.3 * sink) * sz, dn, sz * (1.0 - 0.4 * sink)))
			continue
		going = true
		if show_tel and not bool(s["tel"]) and c >= land - tel:
			s["tel"] = true
			game.telegraph_ring(at, lr, maxf(land - c, 0.05) / k_real, col, true)
		var launch := land - fl
		if c < launch:
			continue
		launching = launching or c - launch < 0.1
		if c >= land:
			s["done"] = true
			_custom_mark_release(s)
			_custom_land(run, cdef, at, lr, ppos)
			continue
		if fx:
			var u := clampf((c - launch) / maxf(fl, 0.05), 0.0, 1.0)
			fx.put(run["key"], run["look"], run["tint"], run["glow"], _custom_xf(_custom_arc(from, at, peak, u), _custom_arc_dir(from, at, peak, u), sz))
			if trail:
				for k in range(1, 4):
					var ut := u - 0.045 * float(k)
					if ut <= 0.0:
						break
					fx.put(run["key"], run["look"], run["tint"], run["glow"], _custom_xf(_custom_arc(from, at, peak, ut), _custom_arc_dir(from, at, peak, ut), sz * (0.78 - 0.17 * float(k))))
	# the launch sounds while spikes leave
	var fs := cdef.text("sounds", "fire")
	if fs != "" and launching and c - float(run.get("sfx_at", -10.0)) >= CUSTOM_SFX_GAP:
		run["sfx_at"] = c
		Audio.play(fs, from)
	return going


## A spot's spike comes down: the hero inside its circle (his body's middle within the radius and a little) is hit, the
## sand bursts, the sound plays (only near him, at most one every CUSTOM_SFX_GAP / 3 of the clock).
func _custom_land(run: Dictionary, cdef: BossAttackDef, at: Vector3, lr: float, ppos: Vector3) -> void:
	custom_landed += 1
	var d := ppos - at
	d.y = 0.0
	if d.length() <= lr + 0.2:
		_custom_hit(run, cdef, at, ppos)
	if game:
		game.fx_sand(at + Vector3(0, 0.15, 0), 0.6)
		var tg = game.get("telegraphs")
		if tg and tg.has_method("flash_ring"):
			tg.flash_ring(at, lr, cdef.tint(), 0.25)
	var ls := cdef.text("sounds", "land")
	var c := float(run["clock"])
	if ls != "" and d.length() < 14.0 and c - float(run.get("land_sfx_at", -10.0)) >= CUSTOM_SFX_GAP / 3.0:
		run["land_sfx_at"] = c
		Audio.play(ls, at)


## Where a thrown shot is at `u` (0..1) of its flight from `from` to `to`: the straight line lifted by a parabola that
## peaks `peak` metres up at the middle.
static func _custom_arc(from: Vector3, to: Vector3, peak: float, u: float) -> Vector3:
	return from.lerp(to, u) + Vector3(0, 4.0 * peak * u * (1.0 - u), 0)


static func _custom_arc_dir(from: Vector3, to: Vector3, peak: float, u: float) -> Vector3:
	var v := (to - from) + Vector3(0, 4.0 * peak * (1.0 - 2.0 * u), 0)
	return v.normalized() if v.length_squared() > 0.0001 else Vector3.DOWN


## A shot's transform: at `at`, its point (-Z) down `dir`, `s` times its size.
static func _custom_xf(at: Vector3, dir: Vector3, s: float) -> Transform3D:
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	return Transform3D(Basis.looking_at(dir, up).scaled(Vector3(s, s, s)), at)


func _tick_custom_volley(run: Dictionary, dc: float, ppos: Vector3, fx: BossAttackFx) -> bool:
	var cdef: BossAttackDef = run["def"]
	var c := float(run["clock"])
	var spd := maxf(cdef.num("projectile", "speed"), 0.1)
	var rng := maxf(cdef.num("projectile", "range"), 0.5)
	var hr := maxf(cdef.num("projectile", "hit_radius"), 0.05)
	var sz := maxf(cdef.num("projectile", "size"), 0.05)
	var going := false
	for s: Dictionary in run["shots"]:
		if bool(s["dead"]):
			continue
		going = true
		if c < float(s["t0"]):
			continue
		var step := minf(spd * dc, maxf(rng - float(s["gone"]), 0.0))
		var p: Vector3 = s["pos"] + (s["dir"] as Vector3) * step
		p.y = _height(p.x, p.z) + 1.0
		s["pos"] = p
		s["gone"] = float(s["gone"]) + step
		var d := ppos - p
		d.y = 0.0
		if d.length() <= hr + 0.3 and player and not player.dead:
			s["dead"] = true
			_custom_hit(run, cdef, p - (s["dir"] as Vector3), ppos)
			continue
		if float(s["gone"]) >= rng - 0.001:
			s["dead"] = true
			if game:
				game.fx_sand(p, 0.5)
			continue
		if fx:
			fx.put(run["key"], run["look"], run["tint"], run["glow"], _custom_xf(p, s["dir"], sz))
	return going


## A ring's front at `f` (0..1) of its race, as Telegraphs.race_ring draws it: out fast, slowing (1 - (1 - f)^3).
static func custom_ring_front(rmax: float, f: float) -> float:
	return rmax * (1.0 - pow(1.0 - clampf(f, 0.0, 1.0), 3.0))


func _tick_custom_ring(run: Dictionary, ppos: Vector3, k_real: float) -> bool:
	var cdef: BossAttackDef = run["def"]
	var c := float(run["clock"])
	var rmax := maxf(cdef.num("pattern", "radius_max"), 0.5)
	var width := clampf(cdef.num("pattern", "width"), 0.1, rmax)
	var dur := rmax / maxf(cdef.num("projectile", "speed"), 0.1)
	var center: Vector3 = run["center"]
	var going := false
	for r: Dictionary in run["rings"]:
		var t0 := float(r["t0"])
		if c < t0:
			going = true
			continue
		if not bool(r["drawn"]) and game:
			r["drawn"] = true
			var tg = game.get("telegraphs")
			if tg and tg.has_method("race_ring"):
				var tc: Color = cdef.tint()
				tg.race_ring(center, rmax, dur / k_real, Color(tc.r, tc.g, tc.b, 0.85), width / rmax)
		var f := (c - t0) / dur
		if f >= 1.0:
			continue
		going = true
		if bool(r["hit"]):
			continue
		var front := custom_ring_front(rmax, f)
		var d := ppos - center
		d.y = 0.0
		var dl := d.length()
		if dl <= front + 0.3 and dl >= front - front * width / rmax - 0.3:
			r["hit"] = true
			_custom_hit(run, cdef, center, ppos)
	return going


# ---------------------------------------------------------------- pass 73 (lane GROUND): the ground

## Garry (pass 73): "The Pop out of Sand Attack looks a bit weird because the boss just disappears and then pops out. It
## would be nice if I can actually see him burrowing into the ground"; "currently the enemies just kind of appear. Let's
## make it so that they grow out of the ground". THE GROUND-CLIP: while a creature rises out of the sand or sinks into it
## (rise_t < 1) _render slides its painting down the billboard's up by the part under (rise_sink, as pass 60 did) and
## hands enemy_billboard.gdshader the share of the quad under the sand line (ground_clip, in the instance basis' z
## column), which it cuts along a ragged line of sand: the cut no longer leans on the terrain hiding that part (a slope
## falling towards the camera had shown it). `rise_v` is how fast rise_t moves (a share a second at the creatures'
## pace): positive while it comes up (0 = RISE_TIME's rate), negative while it sinks (a visible burrow: hidden at 0).
var rise_v := PackedFloat32Array()
## Growing out of the ground (WaveTimeline.spawn_rise, handed over by the director: set_spawn_rise; 0 without one, so a
## crowd built by hand in a test or a tool appears at once as before): the seconds a spawn rises over (an Elite or a boss
## by its kind: spawn_rise_big_s), the share of the way up below which no weapon chooses it as its target (targetable; a
## sinking burrower too; area damage still hits it), the dust puff's size factor.
var spawn_rise_s := 0.0
var spawn_rise_big_s := 0.0
var rise_targetable := 0.7
var spawn_rise_dust := 1.0
## Summons (pass 73, Garry: "Spawning enemies with a skill should never allow for any special enemies"): held true by the
## attack runner around a scripted summon (spawn_ring, an erupt's young), so none of them rolls its variance special.
var force_plain := false
## The figure's stretch as it pushes up out of the sand (squash > 1: taller and narrower), easing to 1 at the top.
const EMERGE_STRETCH := 1.12
## A spawn this tall (m) or taller throws sand off itself all the way up (_tick_emerge).
const EMERGE_SPRAY_SIZE := 2.4
## The hero's gravity (Player: 24 m/s^2): a throw's air time from its height when the attack names none.
const THROW_G := 24.0
## Seconds between two sprays of sand off a creature sinking into its burrow.
const DIG_SPRAY_GAP := 0.09
## Spawns that rose out of the ground, burrows dug, eruptions, creatures and heroes they threw, the last eruption (tests,
## captures).
var emerged := 0
var digs := 0
var eruptions := 0
var erupt_thrown := 0
var erupt_hero_throws := 0
var last_erupt: Dictionary = {}
## The burrows under way: creature -> {serial, atk, warned, spray, from, erupted, closed}; _tick_burrows (_update_boss).
var _burrows: Dictionary = {}
## A rain that lights its circles all at once or spews them (pass 73): creature -> {serial, def, spots, shown, t}, laid
## out at the wind-up's start (_custom_lit_start), ticked by _tick_custom_lit until the spew takes the spots.
var _custom_lit: Dictionary = {}


## The map's spawn rise (pass 73, WaveDirector._apply_mults): seconds (0 = off), an Elite's or a boss's seconds, the
## share of the way up from which the hero may target and hit it, the dust's size factor.
func set_spawn_rise(seconds: float, big_seconds: float, targetable: float, dust: float) -> void:
	spawn_rise_s = maxf(seconds, 0.0)
	spawn_rise_big_s = maxf(big_seconds, 0.0)
	rise_targetable = clampf(targetable, 0.0, 1.0)
	spawn_rise_dust = maxf(dust, 0.0)


## Whether a weapon may choose creature `i` as its target (pass 73, the lead's rule): not while it is still under
## `rise_targetable` of the way up out of the sand (rising from a spawn or a burrow, or sinking into one). Area damage
## (blasts, the revive, the Nuke, patches, beams, rings, ground fire, the sniper's line) still hits it: it stays in the
## crowd's grid; only the choosers (nearest_index, priority_index, priority_target, random_in_range, densest_point,
## screen_ok, a beam's chain) pass it over. It bites and attacks only once it is all the way up.
func targetable(i: int) -> bool:
	return i < 0 or i >= rise_t.size() or rise_t[i] >= rise_targetable


## The share of creature `i`'s quad under the sand line while it rises or sinks (the billboard's ground-clip): its
## painting's own drop below its feet (EnemyDef.shadow "drop") plus the part of the figure still under (rise_sink's share
## of the cell; the size and the squash cancel out). 0 once it is up: nothing is cut.
func ground_clip(i: int) -> float:
	var rise: float = rise_t[i]
	if rise >= 1.0:
		return 0.0
	var t := type_idx[i]
	var head: float = float((types[t] as Dictionary).get("head", 1.0))
	return clampf(_t_sh[t * 4 + 3] + (1.0 - rise_ease(rise)) * head, 0.0, 1.0)


## One tick of creature `i`'s rise or sink (the physics tick, every state but the dying, STATE_SPAWN's too): rise_t moves
## by rise_v (RISE_TIME's rate when it rises without one) at the creatures' pace; a sink that reaches the bottom hides it
## (the burrow's wait under the sand); a rise that reaches the top is done. Nothing moves while it is hidden.
func _tick_rise(i: int, delta: float) -> void:
	if hidden[i] == 1:
		return
	var v: float = rise_v[i]
	if v < 0.0:
		rise_t[i] = maxf(rise_t[i] + delta * pace * v, 0.0)
		if rise_t[i] <= 0.0:
			rise_v[i] = 0.0
			hidden[i] = 1
		return
	if rise_t[i] < 1.0:
		rise_t[i] = minf(rise_t[i] + delta * pace * (v if v > 0.0 else 1.0 / RISE_TIME), 1.0)
		if rise_t[i] >= 1.0:
			rise_v[i] = 0.0


## Whether `p` shows on the screen (or within a metre of it): the spawn's dust is not thrown where nobody sees it. True
## without a camera that can say (tools, tests).
func _point_on_screen(p: Vector3) -> bool:
	var rig = game.get("camera") if game != null else null
	if not (rig is Node) or not (rig as Node).has_method("on_screen"):
		return true
	var cam := (rig as Node).get("camera") as Camera3D
	if cam == null or not cam.is_inside_tree():
		return true
	var ppm: float = float((rig as Node).call("pixels_per_metre")) if (rig as Node).has_method("pixels_per_metre") else 90.0
	var rect := cam.get_viewport().get_visible_rect().grow(SCREEN_MARGIN_M * ppm)
	var q := p + Vector3(0, 0.4, 0)
	return not cam.is_position_behind(q) and rect.has_point(cam.unproject_position(q))


## A spawn grows out of the ground (pass 73; spawn() calls it last): rise_t from 0 over spawn_rise_s (an Elite or a boss
## by its kind over spawn_rise_big_s) through its spawn state (it stands, bites nobody and starts nothing until it is all
## the way up), a small dust puff at its feet when the spot is on the screen. Nothing without the director's numbers
## (tests, tools), for one waiting buried (the ambush brain) or a rise of 0 s.
func _emerge_start(i: int, def: EnemyDef) -> void:
	if def == null or hidden[i] == 1 or alive[i] == 0:
		return
	var big := def.archetype == "boss" or def.archetype == "elite"
	var secs: float = spawn_rise_big_s if big else spawn_rise_s
	if secs <= 0.0:
		return
	rise_t[i] = 0.0
	rise_v[i] = 1.0 / secs
	squash[i] = EMERGE_STRETCH
	if state[i] == STATE_SPAWN:
		timer[i] = secs / maxf(pace, 0.05) + 0.02
	emerged += 1
	if spawn_rise_dust > 0.0 and game != null and _point_on_screen(pos[i]):
		var fx = game.get("fx")
		if fx != null and fx.has_method("emerge_dust"):
			fx.emerge_dust(pos[i], size[i] * spawn_rise_dust, big)


## The spawn state's rise (pass 73; the physics tick's STATE_SPAWN branch calls it): the rise goes on, the figure a touch
## stretched as it pushes up (EMERGE_STRETCH, easing to 1), and the state holds until it is all the way up.
func _tick_emerge(i: int, delta: float) -> void:
	if rise_t[i] >= 1.0 and rise_v[i] <= 0.0:
		return
	_tick_rise(i, delta)
	squash[i] = lerpf(EMERGE_STRETCH, 1.0, rise_ease(rise_t[i]))
	timer[i] = maxf(timer[i], 0.01) if rise_t[i] < 1.0 else 0.0
	# a big one (EMERGE_SPRAY_SIZE m and up: the Elites, the bosses, the giants) throws sand off as it pushes up, every few
	# ticks while it rises, so its foot never shows as a bare cut
	if size[i] >= EMERGE_SPRAY_SIZE and rise_t[i] < 0.95 and spawn_rise_dust > 0.0 and (_tick + i) % 5 == 0 and game != null:
		var fx = game.get("fx")
		if fx != null and fx.has_method("dig_spray"):
			fx.dig_spray(pos[i], size[i] * spawn_rise_dust, rise_t[i])


## The burrow's start (pass 73; the runner's wind-up calls it in place of pass 60's dig): with `sink` > 0 the creature
## sinks out of sight where it stands over that many seconds (rise_v < 0; hidden at the bottom), a ring of dust round it
## and sand spraying off it while it goes (_tick_burrows), the sand closing over it in a small poof; with none it is gone
## at once in that poof (pass 60). The mound swells on the ring at the hero (atk_target) through the wind-up, unless the
## attack predicts its spot (`predict` > 0: nothing shows until its warning) or says `mound` false.
func _burrow_begin(i: int, atk: Dictionary) -> void:
	var sink := maxf(float(atk.get("sink", 0.0)), 0.0)
	var predict := maxf(float(atk.get("predict", 0.0)), 0.0)
	_burrows[i] = {"serial": serial[i], "atk": atk, "warned": false, "spray": 0.0, "from": pos[i], "erupted": false,
		"closed": sink <= 0.0, "k": atk_i[i]}
	digs += 1
	var fx = game.get("fx") if game != null else null
	if sink > 0.0:
		rise_v[i] = -1.0 / sink
		if fx != null and fx.has_method("dig_ring"):
			fx.dig_ring(pos[i], size[i])
	else:
		hidden[i] = 1
		if game:
			game.fx_burst(pos[i] + Vector3(0, 0.5, 0), Color(0.85, 0.7, 0.5), 0.4 * size[i])
			if fx != null and fx.has_method("pop_dust"):
				fx.pop_dust(pos[i], size[i] * 0.6)
	if predict <= 0.0 and bool(atk.get("mound", true)):
		var mt: Vector3 = atk_target[i]
		_mound_start(i, Vector3(mt.x, _height(mt.x, mt.z), mt.z), MOUND_FRAC * size[i])


## Where the hero will be `ahead` seconds from now if he keeps going (pass 73, the Gila's eruption): his place plus his
## flat velocity x `ahead`, kept on the walkable map (the map's clamp_to_arena, else the arena's circle).
func predict_spot(ppos: Vector3, ahead: float) -> Vector3:
	var flat := Vector3.ZERO
	var v = player.get("velocity") if player != null else null
	if v is Vector3:
		flat = Vector3((v as Vector3).x, 0.0, (v as Vector3).z)
	var p := ppos + flat * maxf(ahead, 0.0)
	var mp = game.get("map") if game != null else null
	if mp != null and mp.has_method("clamp_to_arena"):
		p = mp.clamp_to_arena(p)
	else:
		p = _clamp_arena(p)
	p.y = _height(p.x, p.z)
	return p


## The burrows under way, a tick (pass 73; _update_boss calls it after the runner): sand sprays off a creature sinking
## and closes over it in a poof once it is under; a predicting burrow (the Gila's) picks its spot `warn` seconds (x 1/pace)
## before it erupts, where the hero will be (predict_spot), and rings it for those seconds; a creature whose burrow was
## dropped before it erupted (it left its attack) comes back up where it is.
func _tick_burrows(delta: float, ppos: Vector3) -> void:
	if _burrows.is_empty():
		return
	for key in _burrows.keys():
		var i: int = key
		var b: Dictionary = _burrows[i]
		if alive[i] == 0 or serial[i] != int(b["serial"]) or state[i] == STATE_DYING:
			_burrows.erase(i)
			continue
		# its attack is over (it erupted), or dropped or replaced (another started) before it erupted: back up if it was
		# going under
		if state[i] != STATE_ATTACK or atk_i[i] != int(b["k"]):
			if not bool(b["erupted"]) and (hidden[i] == 1 or rise_v[i] < 0.0):
				hidden[i] = 0
				rise_v[i] = 1.0 / RISE_TIME
			_burrows.erase(i)
			continue
		var atk: Dictionary = b["atk"]
		var fx = game.get("fx") if game != null else null
		if rise_v[i] < 0.0 and hidden[i] == 0:
			b["spray"] = float(b["spray"]) - delta
			if float(b["spray"]) <= 0.0:
				b["spray"] = DIG_SPRAY_GAP
				if fx != null and fx.has_method("dig_spray"):
					fx.dig_spray(pos[i], size[i], 1.0 - rise_t[i])
		elif hidden[i] == 1 and not bool(b["closed"]):
			b["closed"] = true
			if fx != null and fx.has_method("pop_dust"):
				fx.pop_dust(pos[i], size[i] * 0.6)
		if float(atk.get("predict", 0.0)) > 0.0 and not bool(b["warned"]):
			var warn := maxf(float(atk.get("warn", 0.4)), 0.0) / maxf(pace, 0.05)
			if timer[i] <= warn:
				_burrow_warn(i, atk, b, ppos)


## A predicting burrow's warning (pass 73): its spot fixed where the hero will be, a red ring there for what is left of
## the wind-up.
func _burrow_warn(i: int, atk: Dictionary, b: Dictionary, ppos: Vector3) -> void:
	b["warned"] = true
	var spot := predict_spot(ppos, float(atk.get("predict", 0.0)))
	atk_target[i] = spot
	if game:
		game.telegraph_ring(spot, float(atk.get("radius", 5.0)), maxf(timer[i], 0.05), Color(0.93, 0.29, 0.36))


## The burrow's eruption (pass 73; the runner's fire step calls it): up it comes at its spot (atk_target: the ring at the
## hero, or the predicted spot), rising over `rise` seconds (RISE_TIME without one) through the ground-clip in a poof of
## dust; the hero within `radius` takes the hit (damage x stage x host, as pass 60) and is thrown `throw_up` m up and
## `throw_out` m out on a real arc (_erupt_throw_hero; with no throw the old shove of `knockback`); every creature within
## it but the burrower is thrown `creature_up` m up and `creature_out` m away, taking `creature_damage` of its max HP
## (_erupt_throw_crowd).
func _burrow_erupt(i: int, atk: Dictionary, ppos: Vector3) -> void:
	var b: Dictionary = _burrows.get(i, {})
	if not b.is_empty():
		b["erupted"] = true
		if float(atk.get("predict", 0.0)) > 0.0 and not bool(b["warned"]):
			_burrow_warn(i, atk, b, ppos)
	hidden[i] = 0
	rise_t[i] = 0.0
	var rs := float(atk.get("rise", 0.0))
	rise_v[i] = 1.0 / rs if rs > 0.0 else 0.0
	_mound_end(i)
	var bp: Vector3 = atk_target[i]
	pos[i] = Vector3(bp.x, _height(bp.x, bp.z), bp.z)
	eruptions += 1
	if game:
		var pfx = game.get("fx")
		if pfx and pfx.has_method("pop_dust"):
			pfx.pop_dust(pos[i], size[i])
	var rb := float(atk.get("radius", 5.0))
	var up := maxf(float(atk.get("throw_up", 0.0)), 0.0)
	var db := ppos - pos[i]
	db.y = 0.0
	var thrown := false
	if player and not bool(player.get("dead")) and db.length() <= rb + 0.5:
		var words: Array = ["burst up from the sand", "thrown" if up > 0.0 else "knocked back"]
		player.take_damage(float(atk.get("damage", 28)) * stage_of(i) * host_of(i), pos[i], hit_info(i, "melee", words))
		if up > 0.0:
			thrown = _erupt_throw_hero(i, atk, db, b)
		elif player.has_method("shove"):
			player.shove(db.normalized() * float(atk.get("knockback", 8.0)))
	var cup := maxf(float(atk.get("creature_up", 0.0)), 0.0)
	var cfrac := maxf(float(atk.get("creature_damage", 0.0)), 0.0)
	var n := 0
	if cup > 0.0 or cfrac > 0.0:
		n = _erupt_throw_crowd(i, rb, cup, maxf(float(atk.get("creature_out", 0.0)), 0.0), cfrac)
	last_erupt = {"at": pos[i], "radius": rb, "hero_thrown": thrown, "crowd": n, "id": (types[type_idx[i]]["def"] as EnemyDef).id}
	if game:
		# the hit's ring and the camera's kick without the shockwave's 6 m burst (pass 60)
		var tg = game.get("telegraphs")
		if tg and tg.has_method("flash_ring"):
			tg.flash_ring(pos[i], rb, Color(1.0, 0.6, 0.3), 0.4)
		elif game.has_method("shockwave"):
			game.shockwave(pos[i], rb)
		var cam = game.get("camera")
		if cam and cam.has_method("shake"):
			cam.shake(1.0 if up <= 0.0 else 1.3)
		game.fx_burst(pos[i] + Vector3(0, 0.5, 0), Color(0.85, 0.7, 0.5), 0.4 * size[i])


## The hero thrown by an eruption (pass 73; Garry: "a real throw instead of just a knockback"): when the hit landed (or
## a line's Energy Shield caught it; never an evade, the Invincibility bubble or a blink), up `throw_up` m and out
## `throw_out` m away from the eruption's middle (away from where it dug in when he stands right on it) on the arc of his
## airborne flight (Player.trampoline_launch, pass 70: he cannot be hit up there, the stick bends the arc by
## `throw_control` of his walk), over `throw_air` seconds (at his own gravity from the height when the attack names
## none). True when he went up.
func _erupt_throw_hero(i: int, atk: Dictionary, off: Vector3, b: Dictionary) -> bool:
	var outcome := str(player.get("last_outcome"))
	if outcome != "hit" and outcome != "shield":
		return false
	if player.has_method("knock_immune") and bool(player.call("knock_immune")):
		return false
	var dir := Vector3(off.x, 0.0, off.z)
	if dir.length_squared() < 0.09:
		var from: Vector3 = b.get("from", pos[i])
		dir = player.global_position - from
		dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var up := maxf(float(atk.get("throw_up", 0.0)), 0.0)
	var out := maxf(float(atk.get("throw_out", 0.0)), 0.0)
	var air := float(atk.get("throw_air", 0.0))
	if air <= 0.0:
		air = sqrt(8.0 * up / THROW_G)
	air = maxf(air, 0.2)
	var went := false
	if player.has_method("trampoline_launch"):
		went = bool(player.call("trampoline_launch", dir, up, out, air, clampf(float(atk.get("throw_control", 0.15)), 0.0, 1.0)))
	elif player.has_method("blast"):
		player.blast(dir * (out / air), 4.0 * up / air)
		went = true
	if went:
		erupt_hero_throws += 1
	return went


## The crowd an eruption throws (pass 73; Garry: "throw other enemies out of the way ... Enemies don't get a lot of damage
## because of this at all"): every creature within `r` (+0.5) of creature `i`'s spot but `i` goes `up` m up (pass 69's
## launch) and `out` m away from the middle while it flies (its share of a shove: knockback_resist), taking `frac` of its
## max HP as it lands; one that cannot go up (the boss, an Elite, an elite-modded one, one already in the air) takes it
## at once and a shove of about half that way. How many went up.
func _erupt_throw_crowd(i: int, r: float, up: float, out: float, frac: float) -> int:
	var n := 0
	var air := clampf(sqrt(8.0 * up / THROW_G), 0.45, 1.4) if up > 0.0 else 0.0
	for j in indices_in_radius(pos[i], r + 0.5):
		if j == i or alive[j] == 0 or state[j] == STATE_DYING or hidden[j] == 1 or held[j] == 1:
			continue
		var off := pos[j] - pos[i]
		off.y = 0.0
		var dir := off.normalized() if off.length_squared() > 0.0001 else Vector3(cos(float(j)), 0.0, sin(float(j)))
		var fall := max_hp[j] * frac
		if up > 0.0 and launch(j, up, air, fall, ""):
			(_launched[j] as Dictionary)["drift"] = dir * (out * _t_kbt[type_idx[j]] / air)
			n += 1
			continue
		if fall > 0.0:
			damage(j, fall, "")
		if alive[j] == 1 and state[j] != STATE_DYING and out > 0.0:
			kb[j] += dir * out * 3.0 * _t_kbt[type_idx[j]] * (0.15 if j == boss_index else 1.0)
	erupt_thrown += n
	return n


# ---------------------------------------------------------------- pass 73 (lane GROUND): the volley rain

## The spots of a rain round `c` (BossAttackDef.rain_points, those past the arena's wall left out), each with its landing
## time and flight on the shot clock: staggered (BossAttackDef.land_times over every point, as pass 72) or, for a volley,
## all in one spew landing within the stagger (BossAttackDef.volley_times over the spots that fall).
func _custom_rain_spots(cdef: BossAttackDef, c: Vector3) -> Array:
	var pts := cdef.rain_points(_rng)
	var flight := maxf(cdef.num("projectile", "flight"), 0.1)
	var lim := arena_radius - 1.0
	var spots: Array = []
	if not cdef.is_volley():
		var times := BossAttackDef.land_times(pts.size(), cdef.num("timing", "stagger"), flight)
		for k in range(pts.size()):
			var at := Vector3(c.x + pts[k].x, 0.0, c.z + pts[k].y)
			if Vector2(at.x, at.z).length() > lim:
				continue
			at.y = _height(at.x, at.z)
			spots.append({"at": at, "land": times[k], "fl": flight, "tel": false, "done": false})
		return spots
	var keep := PackedVector2Array()
	for p: Vector2 in pts:
		if Vector2(c.x + p.x, c.z + p.y).length() <= lim:
			keep.append(p)
	var vt: Array = BossAttackDef.volley_times(keep, flight, cdef.num("timing", "stagger"), cdef.num("spew", "burst"), _rng)
	var deps: PackedFloat32Array = vt[0]
	var lands: PackedFloat32Array = vt[1]
	for k in range(keep.size()):
		var at := Vector3(c.x + keep[k].x, 0.0, c.z + keep[k].y)
		at.y = _height(at.x, at.z)
		spots.append({"at": at, "land": lands[k], "fl": lands[k] - deps[k], "tel": false, "done": false})
	return spots


## A rain that lights its circles all at once or spews its shots (pass 73; _custom_attack_begin calls it at the wind-up's
## start): its spots are laid out now round `center` and kept for the spew (_custom_rain_start takes them); the circles
## go up `telegraph.seconds` before the spew (_tick_custom_lit).
func _custom_lit_start(i: int, cdef: BossAttackDef, center: Vector3) -> void:
	_custom_lit_drop(i)
	var spots := _custom_rain_spots(cdef, center)
	if cdef.lit_at_once():
		for s: Dictionary in spots:
			s["tel"] = true
	_custom_lit[i] = {"serial": serial[i], "def": cdef, "spots": spots, "shown": false, "t": 0.0}
	# the circles go up now when the wind-up is no longer than their warning (the runner set its timer)
	if cdef.lit_at_once() and timer[i] <= maxf(cdef.num("telegraph", "seconds"), 0.0) / maxf(pace, 0.05) + 0.0001:
		_custom_lit[i]["shown"] = true
		_custom_marks_show(cdef, spots, timer[i])


## A wind-up's lit rain dropped (its boss gone, or out of its attack before the spew): its circles go.
func _custom_lit_drop(i: int) -> void:
	var lit = _custom_lit.get(i)
	if lit is Dictionary:
		for s: Dictionary in (lit as Dictionary)["spots"]:
			_custom_mark_release(s)
	_custom_lit.erase(i)


## The lit rains through their wind-ups, a tick (pass 73; _tick_custom_attacks calls it first): the circles go up
## `telegraph.seconds` (x 1/pace) before the spew and pulse while they wait; a volley's boss crouches through the last
## `spew.crouch` seconds (squashed to `spew.squash`); one whose boss died or left its attack is dropped.
func _tick_custom_lit(delta: float) -> void:
	if _custom_lit.is_empty():
		return
	for key in _custom_lit.keys():
		var i: int = key
		var lit: Dictionary = _custom_lit[i]
		if alive[i] == 0 or serial[i] != int(lit["serial"]) or state[i] != STATE_ATTACK:
			_custom_lit_drop(i)
			continue
		var cdef: BossAttackDef = lit["def"]
		var k := maxf(pace, 0.05)
		lit["t"] = float(lit["t"]) + delta
		if cdef.lit_at_once():
			if not bool(lit["shown"]) and timer[i] <= maxf(cdef.num("telegraph", "seconds"), 0.0) / k + 0.0001:
				lit["shown"] = true
				_custom_marks_show(cdef, lit["spots"], timer[i])
			if bool(lit["shown"]):
				_custom_marks_pulse(lit["spots"], float(lit["t"]), -1.0)
		if cdef.is_volley():
			var cr := maxf(cdef.num("spew", "crouch"), 0.0) / k
			if cr > 0.0 and timer[i] < cr:
				squash[i] = lerpf(1.0, cdef.num("spew", "squash"), clampf(1.0 - timer[i] / cr, 0.0, 1.0))


## Every landing circle of a lit rain goes up at once (pass 73): a held disc and ring per spot on the ground marks
## (Telegraphs.hold_disc / hold_ring: full size from the start, their alpha set every tick, gone as the shot lands); a
## stand-in game without them (tests) gets one telegraph ring per spot lasting until its landing.
func _custom_marks_show(cdef: BossAttackDef, spots: Array, wind_left: float) -> void:
	if game == null:
		return
	var col := cdef.telegraph_color()
	var lr := maxf(cdef.num("landing", "radius"), 0.05)
	var tg = game.get("telegraphs")
	var held_ok: bool = tg != null and tg.has_method("hold_disc") and tg.has_method("hold_ring")
	var k_real := maxf(pace * time_scale, 0.05)
	for s: Dictionary in spots:
		if held_ok:
			s["mk"] = [tg.hold_disc(s["at"], lr, Color(col.r, col.g, col.b, 0.26)), tg.hold_ring(s["at"], lr, Color(col.r, col.g, col.b, 0.85))]
		else:
			game.telegraph_ring(s["at"], lr, maxf(wind_left, 0.0) + float(s["land"]) / k_real, col, true)


## The lit circles' strength (pass 73): before the spew (`c` < 0) a steady pulse; after it (`c` the run's clock) each
## fills in as its shot comes down and blinks in its last 0.3 s.
func _custom_marks_pulse(spots: Array, t: float, c: float) -> void:
	var tg = game.get("telegraphs") if game != null else null
	if tg == null:
		return
	for s: Dictionary in spots:
		if not s.has("mk") or bool(s["done"]):
			continue
		var mk: Array = s["mk"]
		var a_disc := 0.26
		var a_ring := 0.74 + 0.14 * sin(t * 7.0)
		if c >= 0.0:
			var land := float(s["land"])
			var left := land - c
			var f := clampf(c / maxf(land, 0.05), 0.0, 1.0)
			a_disc = 0.26 + 0.2 * f
			a_ring = 0.9 if left > 0.3 or int(t * 12.0) % 2 == 0 else 0.45
		tg.set_alpha(int(mk[0]), a_disc)
		tg.set_alpha(int(mk[1]), a_ring)


## A spot's held circles go (its shot landed, or its rain was dropped).
func _custom_mark_release(s: Dictionary) -> void:
	if not s.has("mk"):
		return
	var tg = game.get("telegraphs") if game != null else null
	if tg != null and tg.has_method("release"):
		for id in (s["mk"] as Array):
			tg.release(int(id))
	s.erase("mk")


## The camera's back (towards the camera; the billboards face it): the live camera's, else the fixed rig's.
func _cam_back() -> Vector3:
	var vp := get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp else null
	if cam:
		return cam.global_transform.basis.z
	return Vector3(0, 0.719, 0) - _cf_tick * 0.695


## Where a volley rain's shots leave from (pass 73): the boss's mouth, `spew.mouth` of its size up its painting (the
## billboard's up from its feet), a little in front of the painting so the shots are drawn over it.
func custom_mouth(i: int, cdef: BossAttackDef) -> Vector3:
	var cam_up := _cam_up()
	var at := pos[i] + Vector3(0, lift_h[i], 0) - sprite_sink(i, 1.0, cam_up)
	return at + cam_up * (cdef.num("spew", "mouth") * size[i]) + _cam_back() * 0.45


## The spew (pass 73; _custom_attack_fire calls it for a volley rain): the shots leave from the mouth, the boss stretches
## up (`spew.stretch`, easing back to 1 by itself), a burst of its colour at its mouth and the camera's kick.
func _custom_spew(i: int, cdef: BossAttackDef, run: Dictionary) -> void:
	var mouth := custom_mouth(i, cdef)
	run["from"] = mouth
	squash[i] = cdef.num("spew", "stretch")
	flash[i] = maxf(flash[i], 0.25)
	if game:
		game.fx_burst(mouth, cdef.tint(), clampf(size[i] * 0.12, 0.35, 0.9))


# ---------------------------------------------------------------- pass 79 (lane FX): corpses follow through
## Garry: "enemies that die have their corpses follow through with their knockback. So when an explosion kills an enemy
## fly off like the live ones." A creature that dies keeps the push it had (damage() adds the killing hit's before
## _die): its body slides on with it while its death plays, the push dying away as a live one's does
## (CORPSE_GROUND_DECAY, the physics tick's own), kept inside the arena, on the ground, and off the map's rocks (a body
## that runs into one slides along it). A kill by a blast (a damage_radius hit with a push: the dynamite, Powder Keg,
## rockets, mines, bomblets, a turret's boom, Overkill's splash, a hostile blast on its own crowd) also throws the body up:
## CORPSE_TOSS_PER m of height for every m/s of its push, at most CORPSE_TOSS_MAX, none under CORPSE_TOSS_MIN, falling at
## CORPSE_G; up there the push dies away at CORPSE_AIR_DRAG only, so it sails, and it lands in a little sand. Its death
## lasts at least the flight plus CORPSE_REST (it lies a moment, then sinks as every body does over DIE_SINK).
## Never the boss (his death is as before: no slide, no throw); big game (an Elite, an elite-modded creature) slides but
## is never thrown up (as only the small ones are ever launched alive); a body up in a launch (Alley-Oop, Bucking
## Bronco) falls as before (_drop_launched_body), Bucking Bronco's drift kept as its push. A body left up in the air by
## anything else (a tornado's toss, a bounce) falls from where it was.
const CORPSE_GROUND_DECAY := 6.0
const CORPSE_AIR_DRAG := 1.5
const CORPSE_TOSS_PER := 0.3
const CORPSE_TOSS_MIN := 0.3
const CORPSE_TOSS_MAX := 2.5
const CORPSE_G := 22.0
const CORPSE_REST := 0.6
## A push below this (m/s) is spent: the body stops.
const CORPSE_STOP := 0.05
## The creature a blast is striking now (damage_radius sets it round each damage() call; -1 for a blast with no push), so
## _corpse_begin knows a blast killed it.
var _corpse_blast_i := -1
## Bodies up in the air (thrown by a blast, or falling from a toss): index -> {"serial", "vy" (m/s, up)}.
var _corpse_air: Dictionary = {}
## Diagnostics and tests: bodies a blast threw up, bodies that came down.
var corpse_tosses := 0
var corpse_landings := 0

# ---------------------------------------------------------------- pass 82 (lane FEEL): every kill throws its body
## Garry: "The explosion thing that affects the enemy's corpses with knockback should come from all weapons. I think
## currently it's just the dynamite." Every kill by a hit (damage(): any weapon, its burns and poisons, a blast, the
## revive) now follows through like a blast's: the body is driven along the killing hit (the hit's own direction: the
## shot's travel, the blade's swing, out of the blast; for a hit with none, away from the hero) at no less than
## CORPSE_FLOOR_PUSH m/s, and thrown up CORPSE_FLOOR_TOSS m. Both grow with the hit's weight w (0..1: its damage over
## CORPSE_HEAVY_RATIO times the creature's max HP, CORPSE_CRIT_WEIGHT more for a crit, half that for a mini crit) up to
## CORPSE_HEAVY_PUSH / CORPSE_HEAVY_TOSS; the push the body already had along the hit adds CORPSE_HIT_TOSS_PER m of
## height per m/s, the height capped at CORPSE_HIT_TOSS_MAX (a blast's own throw, corpse_toss_height, still applies when
## it is higher, up to CORPSE_TOSS_MAX). The floor push shrinks for a heavy body: x CORPSE_HEFT_SIZE / its size, never
## under CORPSE_HEFT_MIN. Never the boss, big game (an Elite, an elite-modded creature: it slides on its push as before),
## a body in a launch (as before), or one still coming up out of the sand below rise_targetable (it sinks where it is;
## one nearly up is shown whole and thrown); nothing changes for the living. A kill with no hit behind it (kill_all, a
## walking bomb going off) is as before.
const CORPSE_FLOOR_PUSH := 4.0
const CORPSE_FLOOR_TOSS := 0.4
const CORPSE_HEAVY_PUSH := 5.5
const CORPSE_HEAVY_TOSS := 0.8
const CORPSE_HEAVY_RATIO := 4.0
const CORPSE_CRIT_WEIGHT := 0.35
const CORPSE_HIT_TOSS_PER := 0.1
const CORPSE_HIT_TOSS_MAX := 1.6
const CORPSE_HEFT_SIZE := 1.5
const CORPSE_HEFT_MIN := 0.5
## The creature damage() is killing now (-1 outside a kill), the killing hit's flat way (unit) and its weight (0..1).
var _corpse_kill_i := -1
var _corpse_kill_dir := Vector3.FORWARD
var _corpse_kill_w := 0.0


## damage() calls it right before _die: remembers the killing hit's way (`hit_dir` flattened, else away from the hero,
## else any way) and weight for _corpse_begin.
func _corpse_note_kill(i: int, hit_dir: Vector3, dealt: float, crit: bool, mini_crit: bool) -> void:
	var d := Vector3(hit_dir.x, 0.0, hit_dir.z)
	if d.length_squared() < 0.0001 and player != null:
		d = pos[i] - player.global_position
		d.y = 0.0
	if d.length_squared() < 0.0001:
		d = Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0))
	_corpse_kill_dir = d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD
	_corpse_kill_w = corpse_kill_weight(dealt / maxf(max_hp[i], 1.0), crit, mini_crit)
	_corpse_kill_i = i


## A killing hit's weight (0..1) from its damage over the creature's max HP (`ratio`) and whether it was a crit.
static func corpse_kill_weight(ratio: float, crit: bool, mini_crit: bool = false) -> float:
	var w := clampf(ratio / CORPSE_HEAVY_RATIO, 0.0, 1.0)
	if crit:
		w += CORPSE_CRIT_WEIGHT
	elif mini_crit:
		w += CORPSE_CRIT_WEIGHT * 0.5
	return clampf(w, 0.0, 1.0)


## The least push (m/s) along the killing hit a body of `body_size` m gets from a hit of weight `w`.
static func corpse_floor_push(w: float, body_size: float = 1.0) -> float:
	var heft := clampf(CORPSE_HEFT_SIZE / maxf(body_size, 0.8), CORPSE_HEFT_MIN, 1.0)
	return lerpf(CORPSE_FLOOR_PUSH, CORPSE_HEAVY_PUSH, clampf(w, 0.0, 1.0)) * heft


## How high (m) a kill of weight `w` throws a body that had `push` m/s along the hit.
static func corpse_kill_toss(w: float, push: float) -> float:
	return minf(lerpf(CORPSE_FLOOR_TOSS, CORPSE_HEAVY_TOSS, clampf(w, 0.0, 1.0)) + maxf(push, 0.0) * CORPSE_HIT_TOSS_PER, CORPSE_HIT_TOSS_MAX)


## The follow-through of the kill _corpse_note_kill remembered: the body's push raised to the floor along the hit (its
## push across the hit kept) and the height it is thrown (0: none, as for big game and a body still rising).
func _corpse_follow(i: int, push: Vector3) -> float:
	if is_big_game(i) or rise_t[i] < rise_targetable:
		return 0.0
	if rise_t[i] < 1.0:
		# killed nearly up (a target already): thrown clear of the sand, its whole body shown
		rise_t[i] = 1.0
		rise_v[i] = 0.0
	var along := push.dot(_corpse_kill_dir)
	var fp := corpse_floor_push(_corpse_kill_w, size[i])
	if along < fp:
		kb[i] = push + _corpse_kill_dir * (fp - along)
	return corpse_kill_toss(_corpse_kill_w, along)


## A body starts its follow-through (_die calls it once the creature is STATE_DYING): its push kept (flat), the boss's
## zeroed; a blast's kill thrown up by its push; a body up in the air falling from there. Pass 82: every kill by a hit
## driven along it and thrown up (_corpse_follow).
func _corpse_begin(i: int) -> void:
	var def: EnemyDef = types[type_idx[i]]["def"]
	if i == boss_index or def.archetype == "boss":
		kb[i] = Vector3.ZERO
		return
	var push := Vector3(kb[i].x, 0.0, kb[i].z)
	if _launch_of(i):
		var e: Dictionary = _launched[i]
		if e.get("drift") is Vector3:
			push += e["drift"] as Vector3
		kb[i] = push
		return
	kb[i] = push
	var vy := 0.0
	# pass 82 (lane FEEL): the killing hit's follow-through (a blast's own throw when that is higher)
	var h := _corpse_follow(i, push) if _corpse_kill_i == i else 0.0
	if _corpse_blast_i == i and not is_big_game(i):
		h = maxf(h, corpse_toss_height(push.length()))
	if h > 0.0:
		vy = sqrt(2.0 * CORPSE_G * h)
		corpse_tosses += 1
	if vy <= 0.0 and lift_h[i] <= 0.0:
		return
	_corpse_air[i] = {"serial": serial[i], "vy": vy}
	timer[i] = maxf(timer[i], corpse_air_time(vy, lift_h[i]) + CORPSE_REST)


## Seconds a body thrown up at `vy` m/s from `h` m above the sand flies before it lands (CORPSE_G).
static func corpse_air_time(vy: float, h: float) -> float:
	return (vy + sqrt(vy * vy + 2.0 * CORPSE_G * maxf(h, 0.0))) / CORPSE_G


## The height a blast's push of `push` m/s throws a body (0 under CORPSE_TOSS_MIN; tests, the docs).
static func corpse_toss_height(push: float) -> float:
	var h := minf(maxf(push, 0.0) * CORPSE_TOSS_PER, CORPSE_TOSS_MAX)
	return h if h >= CORPSE_TOSS_MIN else 0.0


## One tick of a body (the dying tick calls it while its death plays): up in the air it rises and falls; it moves with
## its push, which dies away (slower in the air), inside the arena, on the ground, never into a rock.
func _corpse_tick(i: int, delta: float) -> void:
	var air := false
	var e = _corpse_air.get(i)
	if e is Dictionary:
		if int((e as Dictionary).get("serial", -1)) != serial[i] or timer[i] <= 0.0:
			_corpse_air.erase(i)
		else:
			air = true
			var vy: float = float(e["vy"]) - CORPSE_G * delta
			e["vy"] = vy
			lift_h[i] = lift_h[i] + vy * delta
			if lift_h[i] <= 0.0:
				lift_h[i] = 0.0
				_corpse_air.erase(i)
				corpse_landings += 1
				var fx = game.get("fx") if game != null else null
				if fx != null and fx.has_method("sand"):
					fx.sand(pos[i], clampf(size[i] * 0.4, 0.4, 0.8))
	elif lift_h[i] > 0.0 and _launch_of(i):
		air = true
	var k := kb[i]
	if k.length_squared() < CORPSE_STOP * CORPSE_STOP:
		kb[i] = Vector3.ZERO
		return
	var np := _clamp_arena(pos[i] + k * delta)
	np.y = _height(np.x, np.z)
	pos[i] = np
	var ob := _obstacle_push(i)
	if ob.length_squared() > 0.0:
		var n := ob.normalized()
		var into := k.dot(n)
		if into < 0.0:
			k -= n * into
	kb[i] = k.lerp(Vector3.ZERO, clampf(delta * (CORPSE_AIR_DRAG if air else CORPSE_GROUND_DECAY), 0.0, 1.0))
