## XP gems and coins as 3D meshes in MultiMeshes. Magnet pull, merge when crowded, vacuum, chests.
## Pass 46, the Vampire Survivors pickup: a gem or coin the hero calls (his magnet's reach, a turret's, a vacuum) first
## hops OUT, away from him, on a little arc with a scale pop, then flies IN to his chest, its speed climbing from a
## standstill and its line bending a little sideways, and only when it gets there is the XP or the gold his.
## Pass 48, Loose Change: a coin knocked out of the hero (toss_coin) flies off on an arc, lands a few steps away and lies
## there a moment out of the magnet's reach, so he goes and gets it.
## Pass 54 (Garry: gems by the hero vanished; gems and coins too big, and drawn over the sprites): a crowded pool fuses
## only far gems, cluster by cluster, into one large gem where they lay (_merge); coins have their own cap (COIN_CAP);
## gems are half their old size and coins three quarters, and both are see-through materials that write no depth, drawn
## only where no painting wrote the stencil (PAINTING_STENCIL), so creatures, the hero, props and structures cover them.
## Pass 56 (Garry: "more of a Rhombohedron shape, but 3d obviously ... like a gem", then "I mean octahedron"; "just 5%
## bigger"; "an occasional, very rare, little extra hop" on top of the float; the medium and large gems "glint now and
## then"): every gem and the vacuum are a faceted octahedron (octahedron_mesh), the gems 5 % bigger on the screen and the
## vacuum the size it was (GEM_GROW, GEM_LOOK, VACUUM_LOOK), the bigger ones resting a little higher (rest_of) and
## dropping from as much higher (_drop_y), a gem lying on the sand hops now and then but never more than one on the
## screen every HOP_EXTRA_GAP s (HOP_EXTRA_*, _idle), and a medium or large one glints where it can be seen (GLINT_*,
## core/shaders/gem_glint.gdshader).
## Pass 60 (Garry: the magnet "should make the gems fly up and then down to the Player", "a cheap shader that makes the
## gems look like they are 'charged' while they are flying", for "the things that do big pulls" only, and the gems "a
## shade darker so they are more easily visible on the sand ... maybe add low emit"): a big pull (vacuum_all: the Magnet
## Pulse, the Uber Magnet, the boss chest's opening, the Elite's vacuum gem; a Turret Family attractor) starts the trip
## with `arc`: the gem waits its turn in a ripple spreading from the hero (PHASE_ARC_WAIT), is thrown straight up with a
## little outward drift to an apex metres over where it lay (PHASE_ARC_RISE), hangs a beat and dives into him on the
## flight's own code (PHASE_FLY), charged the whole way (charge_of -> INSTANCE_CUSTOM.x on core/shaders/gem.gdshader,
## which now draws every gem kind: brighter, shimmering, a pale rim); the walk-up pull keeps the hop. The gems are
## GEM_SHADE darker with a low glow (GEM_EMISSION) and the motes and glints keep the bright colours (GLINT_COLOURS).
## Pass 61 (Garry: "The EXP gems still disappear. Now they combine into a big gem. I'd prefer that they don't disappear
## ever, but don't affect the performance negatively at all"): nothing merges and nothing is lost. The pool starts at MAX
## slots and doubles when it is full (_grow), each kind's MultiMesh with it (_grow_instances); every pickup keeps one
## instance of its kind's MultiMesh for its whole life (inst, dense: a freed one's place is taken by the kind's last).
## A pickup lying on the sand costs nothing: its instance is written once when it lands and never again, because the
## float and the idle spin are the vertex shaders' (gem.gdshader, coin.gdshader: `t_now` is the run's clock, set once a
## drawn frame, so they stop when the run pauses; a gem's phase is its slot in INSTANCE_CUSTOM.y, a coin's is turned
## into its basis), and it is not looked at by the tick: it lies in a coarse grid (GRID_*) that only the cells round the
## hero's magnet and round each turret's pull are read from, and its hop and glint turns wait on a timing wheel
## (IDLE_BUCKET) that hands it to the tick only when one is due. Only the moving ones (falling, on their way, tossed,
## held, hopping, glinting) are in the active list (_act), ticked and drawn every frame. A hop whose turn comes off the
## screen lets it pass, as a glint always did: nobody sees it. A big pull (vacuum_all) walks the grid from the hero
## outwards (_vacuum_step): the ones on the screen go up the pass-60 arc, at most FLIGHT_MAX on their way at once; one off
## the screen is not thrown up where nobody sees it but starts its dive just past the screen's edge when it would have
## come over it (FAR_LEAD, _tick_vq), at most EDGE_MAX of those in the air, and one whose turn finds that stream full is
## taken unseen when it would have reached the hero, so a sea of gems costs a pull no more than today's 600 did.
class_name PickupManager
extends Node3D

## The pool's starting size (600 and full until pass 61, when a crowded pool fused far gems and a full one lost drops):
## it doubles whenever it fills (_grow), so no drop is ever lost. 2048, so a real run never grows (the most a stage-1 run
## left lying in pass 61's count was 876 at 7:00): the doubling is the rare fallback.
const MAX := 2048
const KIND_GEM_S := 0
const KIND_GEM_M := 1
const KIND_GEM_L := 2
const KIND_COIN := 3
const KIND_VACUUM := 4
const KINDS := 5
## Each kind's MultiMesh starts with this many instances and doubles with its pool (pass 61, _grow_instances; started
## big enough that a real run never needs it).
const INST_START := 1024
## The resting pickups' grid (pass 61): GRID_N x GRID_N cells of GRID_CELL m over the square GRID_HALF m round the
## arena's middle (a pickup outside it counts in the edge cell). The magnet and a turret's pull read only the cells their
## reach touches.
const GRID_CELL := 4.0
const GRID_HALF := 96.0
const GRID_N := 48
## The idle turns' timing wheel (pass 61): one bucket a IDLE_BUCKET s of the run's clock.
const IDLE_BUCKET := 0.05
## A big pull (pass 61): no more than FLIGHT_MAX pickups on their way at once (the old pool's whole 600, so a pull costs
## a frame no more than pulling a full old pool did), and the walk over the grid looks at WALK_MAX lying pickups and
## WALK_CELLS of its cells a tick at most (the whole grid in well under FAR_LEAD).
## One on the screen goes up the pass-60 arc. One off it is never thrown up where nobody sees it: it waits, lying where it
## is, until it would have come over the screen's edge (FAR_LEAD s, the arc's wait, rise and hang, plus the flight from
## its arc's top to the edge at the top speed), then starts its dive EDGE_MARGIN m past the edge on that line, at most
## EDGE_MAX of them in the air at once; one whose turn finds that stream full is taken where it lies, unseen, when it
## would have reached the hero (its XP or gold his, quietly, as if it had flown in). The screen's edge on the sand round
## the hero is EDGE_BINS directions' distances to the camera's footprint (_edge_table).
const FLIGHT_MAX := 600
const WALK_MAX := 80
const WALK_CELLS := 400
const FAR_LEAD := 1.25
const EDGE_MARGIN := 2.5
const EDGE_MAX := 80
const EDGE_BINS := 32
## The off-screen turns a tick takes at most (pass 61): a burst of them (every pickup just past the edge comes due in
## the same moment) waits a tick or two instead of making one frame dear; nobody sees the difference.
const VQ_TURNS := 40
## The float's middle over the rest (float_y), and the shaders' clocks: `t_now` wraps where every turn the float and the
## spin make is whole, so the wrap never shows (gems 2 t and 2.4 t: 5 pi; the coin 3 t and 2.4 t: 10 pi / 3), and a long
## run's clock never reaches the size where a GPU's sine loses its way.
const FLOAT_BASE := 0.06
const GEM_WRAP := 5.0 * PI
const COIN_WRAP := 10.0 * PI / 3.0
## The meshes (pass 54: gems half their old size, coins three quarters): a gem's radius by kind (small, medium, large),
## the vacuum's, the coin's radius and thickness. Pass 56 (Garry: "make them just 5% bigger than they are now"): the
## three gems GEM_GROW times pass 54's 0.11, 0.16 and 0.225 m; the vacuum and the coin as they were.
const GEM_GROW := 1.05
const GEM_R := [0.11 * GEM_GROW, 0.16 * GEM_GROW, 0.225 * GEM_GROW]
## GEM_R and VACUUM_R are sizes as pass 54's wedge (a PrismMesh 2 r wide, 2.4 r tall, 2 r deep) measured them. The
## octahedron that replaced it (pass 56) keeps the wedge's proportions, GEM_TALL times its own radius from tip to tip and
## twice it across, but is drawn larger (gem_radius), by its kind's factor: an octahedron as wide and tall as the wedge
## covers only 37 % of the screen the wedge covered from the run's camera, so at the wedge's size the gems looked a third
## smaller, not 5 % bigger. The factors are measured as the camera sees both shapes (46 degrees down, spinning, over the
## whole float, the sand hiding whatever dips into it: the old wedge at REST, the octahedron at rest_of, where the sand
## never cuts it; pass56_pk_test measures them): GEM_LOOK makes each gem GEM_GROW times what its wedge showed, and
## VACUUM_LOOK makes the vacuum show what its wedge did. The large wedge sat 5 % in the sand at the float's lowest and the
## vacuum's 23 %, so their factors are smaller (the fix round of pass 56, the lead: one factor of 1.64 for every kind had
## made the large gem 1.08 times its old size and the vacuum 1.14 times, 1.5 m from tip to tip).
const GEM_TALL := 2.4
const GEM_LOOK := [1.641, 1.641, 1.598]
const VACUUM_LOOK := 1.444
## The lower tip of a gem tall enough to reach the sand at the bottom of its float would dip into it: such a gem rests
## higher (rest_of), its tip GEM_CLEAR m over the sand at the float's lowest.
const GEM_CLEAR := 0.04
const VACUUM_R := 0.38
const COIN_R := 0.21
const COIN_H := 0.06
## Gems and coins are see-through and write no depth, at this priority among the see-through (pass 54): over the blob
## shadows (EnemyManager.SHADOW_PRIORITY), under the hero's over pass (BillboardSprite.OVER_PRIORITY -1), with his speed
## trails; opaque things in front of them still hide them.
const PICKUP_PRIORITY := -2
## The stencil value every painting writes where it draws a pixel (pass 54: enemy_billboard, sprite_billboard and
## prop_billboard say `stencil_mode write, compare_always, 1`): the gems and the coin (coin.gdshader) draw only where the
## stencil is not this, so they lie under every 2.5D sprite, in front of its plane or behind it.
## Pass 72 (lane SPEC): the scenery (props, structures, signs, barrels, the wall) writes SceneryStencil.VALUE (2) instead,
## so a creature's outline shows only behind scenery; the gems, coins and glints now draw where the stencil is 0.
const PAINTING_STENCIL := 1
## each kind's colour (gem small, medium, large, coin, vacuum): the mesh. Pass 60 (Garry: "a shade darker so they are
## more easily visible on the sand"): the three gems are GEM_SHADE of their pass-46 colours (the same hues), so they read
## as solid coloured stones on the pale sand instead of pale lit glass; the coin and the vacuum are as they were.
const GEM_SHADE := 0.78
const COLOURS := [Color(0.4836, 0.3744, 0.78), Color(0.351, 0.663, 0.78), Color(0.78, 0.429, 0.663), Color(1.0, 0.72, 0.25), Color(1.0, 1.0, 1.0)]
## The bright copy (pass 60): the colours before GEM_SHADE, for the mote where a pickup is taken or a merge pops
## (_glint, _merge_glint) and the resting gems' star glints (glint_color), which stay as bright as they were.
const GLINT_COLOURS := [Color(0.62, 0.48, 1.0), Color(0.45, 0.85, 1.0), Color(1.0, 0.55, 0.85), Color(1.0, 0.72, 0.25), Color(1.0, 1.0, 1.0)]
## The gems' glow (gem.gdshader `rest_emission`; pass 60: 0.3, was 0.6 on the old StandardMaterial3D) and what it climbs
## to while charged on the magnet arc (`charged_emission`, before the shimmer; the shader puts it on the stone's bright
## pass-46 colour, so 1.0 is that colour lit from within: the Compatibility renderer clips at 1 with no tonemapping, and
## 1.8 had read as white paper scraps in the capture).
const GEM_EMISSION := 0.3
const CHARGED_EMISSION := 1.0
## The trip in (pass 46). 0 on the ground (or still falling from the kill), 1 the hop out, 2 the flight in.
const PHASE_GROUND := 0
const PHASE_HOP := 1
const PHASE_FLY := 2
## A coin knocked out of the hero (pass 48, Loose Change) on its arc to where it lands (toss_coin); on the ground after.
const PHASE_TOSS := 3
## The magnet arc (pass 60, Garry: the magnet "should make the gems fly up and then down to the Player", as Megabonk's
## throws every gem into the air to shower down on him; "only ... the things that do big pulls": vacuum_all's callers
## and the Turret Family's attractors; the walk-up pull keeps the hop). 4: it waits its turn, charging, where it lies;
## 5: thrown up, then hanging at the apex; then FLY, the dive, on the flight's own code.
const PHASE_ARC_WAIT := 4
const PHASE_ARC_RISE := 5
const ARC_WAIT_PER_M := 0.035   # s of wait a metre from the hero, so the pull ripples outward from him ...
const ARC_WAIT_MAX := 0.5       # ... up to this ...
const ARC_WAIT_JITTER := 0.12   # ... plus up to this, random (never past 0.62 s in all)
const ARC_HEIGHT_MIN := 2.4     # m over where it lies the apex sits, at least ...
const ARC_HEIGHT_RANGE := 1.4   # ... plus up to this, random ...
const ARC_HEIGHT_PER_M := 0.02  # ... plus this a metre from the hero (a far gem goes a little higher)
const ARC_GRAV := 20.0          # the rise's gravity: it leaves at sqrt(2 g h) m/s
const ARC_DRIFT_MIN := 0.4      # m/s outward as it rises, random between the two ...
const ARC_DRIFT_MAX := 0.9
const ARC_DRIFT_FAN := 0.5      # radians either side of straight away the drift may point, so the dives fan out
const ARC_HANG_MIN := 0.06      # s it hangs at the apex before the dive, random between the two
const ARC_HANG_MAX := 0.16
const ARC_SPIN := 9.0           # radians a second of extra spin while it rises (half that through the dive)
const ARC_POP_TIME := 0.3       # the launch's scale pop (HOP_POP) eases back to 1 over this
const CHARGE_RISE := 0.05       # the charge fades in over the wait; a wait shorter than this charges at once
const HOP_TIME := 0.22      # seconds of the hop
const HOP_OUT := 3.5        # m/s away from the hero
const HOP_UP := 4.0         # m/s up at the start of the hop, under the drop's own gravity
const HOP_GRAV := 20.0
const HOP_POP := 1.35       # its scale as the hop starts, easing back to 1 by the end
const FLY_ACCEL := 70.0     # m/s per second from a standstill at the top of the hop, up to the magnet's top speed
const FLY_CURVE := 0.35     # the sideways share of its heading as it sets off, gone by FLY_CURVE_TIME and near him
const FLY_CURVE_TIME := 0.35
const CHEST := 0.8          # where it flies to: metres above the hero's feet
const COLLECT_R := 0.45     # taken this close to his chest (0.6 before pass 46)
## How high a pickup rests over the sand (0.35 before pass 54 halved the gems): where a coin rests, and the lowest any
## pickup rests. Since pass 56 the gems and the vacuum rest at their own rest_of, higher for the bigger octahedra.
const REST := 0.22
const BOB := 0.09           # how far it bobs (0.13 before pass 54)
## A drop starts DROP_FROM m over where it was let go (a creature's feet), plus as much as its kind rests higher than
## REST (_drop_y), and pops up from there.
const DROP_FROM := 0.4
## The mote a pickup leaves where it is taken, or a tossed coin where it lands (_glint): at most one this often (a
## vacuum takes hundreds at once). The gems' star glints keep their own spacing (GLINT_GAP).
const SPARK_GAP := 0.04
## What a gem of each size (small, medium, large) is worth before the creature's xp scale, as drop_from pays it.
const GEM_VALUE := [1.0, 5.0, 25.0]
## The idle hop (pass 56, Garry: "an occasional, very rare, little extra hop to the idle float that they are doing right
## now", each gem "once every 40-60 s"): on top of the float, which is as it was (float_y), a gem resting on the sand
## hops once at a random moment HOP_EXTRA_MIN..HOP_EXTRA_MAX s after it lands and again that long after each hop:
## HOP_EXTRA_HEIGHT m up and back down on a parabola in HOP_EXTRA_TIME s, stretched a little as it leaves the sand
## (HOP_EXTRA_STRETCH tall), turning HOP_EXTRA_SPIN radians more while in the air (a half turn: the four-sided gem looks
## the same a quarter turn round, so the spin is back in step when it lands), and squashed as it lands
## (HOP_EXTRA_SQUASH_Y tall, HOP_EXTRA_SQUASH_XZ wide), back to its shape in HOP_EXTRA_SQUASH_TIME s. Only a gem lying on
## the sand: never one falling from a kill, on its trip to the hero or popping out of a merge; coins and the vacuum keep
## the plain float. Drawn only (_render): the gem itself stays where it lies.
const HOP_EXTRA_MIN := 40.0
const HOP_EXTRA_MAX := 60.0
const HOP_EXTRA_HEIGHT := 0.3
const HOP_EXTRA_TIME := 0.38
const HOP_EXTRA_SPIN := PI
const HOP_EXTRA_STRETCH := 1.1
const HOP_EXTRA_SQUASH_Y := 0.85
const HOP_EXTRA_SQUASH_XZ := 1.1
const HOP_EXTRA_SQUASH_TIME := 0.09
## The field's pace (the fix round of pass 56, the lead: with 150 to 210 gems resting on the screen, each on its own 40 to
## 60 s, the field hopped 1.3 to 3.6 times a second, which does not read as "very rare"): a hop that would start on the
## screen (anywhere the camera shows, the HUD's strip too) waits until HOP_EXTRA_GAP s after the last one that did, and
## a gem whose turn comes inside the gap lets it pass and draws a new HOP_EXTRA_MIN..HOP_EXTRA_MAX wait. Off the screen a
## gem hops on its own clock: nobody sees it.
const HOP_EXTRA_GAP := 0.75
## Glints (pass 56, Garry: the medium and large gems "glint now and then"): a medium or large gem resting on the sand
## flashes a small four-point star (core/shaders/gem_glint.gdshader, the chest's sparkle) at its own random moments,
## GLINT_EVERY[size] s apart (x..y; the large a little more often), a GLINT_TIME s flare GLINT_SIZE times the gem's
## radius (gem_radius) across at its brightest, in its colour paled GLINT_PALE towards white, riding on the gem. So a
## sea of gems never floods the screen, a glint starts at most every GLINT_GAP s across the field, no more than
## GLINT_MAX show at once, and a gem off the screen lets its turn pass. Small gems, coins and the vacuum never glint.
const GLINT_EVERY := [Vector2.ZERO, Vector2(4.0, 6.5), Vector2(3.0, 5.0)]
const GLINT_TIME := 0.34
const GLINT_SIZE := 2.0
const GLINT_PALE := 0.6
const GLINT_GAP := 0.2
const GLINT_MAX := 8
## The glints draw right after the gems (the stencil still keeps them under every painting), so a gem never covers its
## own glint.
const GLINT_PRIORITY := PICKUP_PRIORITY + 1
## Loose Change's coin (pass 48, toss_coin): it leaves TOSS_FROM m above the hero's feet and comes down TOSS_MIN..TOSS_MAX
## m away (inside the arena by TOSS_EDGE, TOSS_CLEAR off a rock's edge, TOSS_TRIES tries) after TOSS_TIME s, flipping
## TOSS_FLIP radians a second; it bounces TOSS_BOUNCE m/s up as it lands, and for TOSS_HOLD s the magnet and the turrets'
## pull leave it alone (a hero within TOSS_TOUCH of it still takes it).
const TOSS_MIN := 2.0
const TOSS_MAX := 3.5
const TOSS_FROM := 1.0
const TOSS_TIME := 0.6
const TOSS_FLIP := 20.0
const TOSS_BOUNCE := 2.4
const TOSS_HOLD := 1.0
const TOSS_TOUCH := 1.0
const TOSS_EDGE := 2.0
const TOSS_CLEAR := 0.4
const TOSS_TRIES := 8

var game: Node
var pos := PackedVector3Array()
var kind := PackedInt32Array()
var value := PackedFloat32Array()
var vel := PackedVector3Array()
var flying := PackedByteArray()
var alive := PackedByteArray()
var born := PackedFloat32Array()
var phase := PackedByteArray()        # where it is on the trip in (PHASE_*); `flying` is 1 for the hop and the flight
var phase_t := PackedFloat32Array()   # seconds into the phase
var hop_dir := PackedVector3Array()   # the way it hopped (flat, away from the hero); the flight bends off across it
var hold := PackedFloat32Array()      # seconds the magnet and the pull leave it alone (a tossed coin once it lands)
## The magnet arc (pass 60): 1 while its trip is an arc (the charge and the extra spin read it; 0 on the walk-up hop)
var arced := PackedByteArray()
var arc_delay := PackedFloat32Array()   # ARC_WAIT: seconds it waits its turn
var arc_v0 := PackedFloat32Array()      # the launch: m/s up ...
var arc_drift := PackedFloat32Array()   # ... and m/s along hop_dir
var arc_hang := PackedFloat32Array()    # ARC_RISE: seconds it hangs at the apex
var arc_apex := PackedFloat32Array()    # ARC_RISE: phase_t at the apex; < 0 while still rising
var arc_spin := PackedFloat32Array()    # radians of extra spin it has turned on its arc
var hop_next := PackedFloat32Array()  # pass 56: when its next idle hop starts (_time); < 0 until it lies on the sand
var hop_t := PackedFloat32Array()     # seconds into its idle hop and the squash after it; < 0 when it is not hopping
var glint_next := PackedFloat32Array()  # pass 56: when it next glints (_time); < 0 until it lies on the sand
var glint_t := PackedFloat32Array()     # seconds into its glint; < 0 when it is not glinting
## pass 56: when _idle next has work for it (_time): its next hop or glint, 0 while either runs, < 0 to look at once (it
## has just landed), so a gem lying still costs the tick one comparison
var idle_due := PackedFloat32Array()
var free_list: Array = []
var count := 0
var _time := 0.0
var _ticks := 0      # physics ticks run; the draw waits for a new one (pass 33.8)
var _drawn := -1
var _mms: Array = []
var _attractors: Array = []   # {pos, r} set each frame by turrets
var chests: Array = []
var specials: Array = []       # Powerup nodes waiting on the ground
var _spark_last := -1.0
var coins := 0                 # coins on the ground (pass 54)
## Pass 61 (the gold board): where a coin came from when it is not a creature's drop, {slot: source} (mark_coin;
## RunAnalytics.GOLD_SOURCES), read when it is taken (a big pull's unseen take too) and dropped when its slot frees.
var coin_from: Dictionary = {}
## Pass 56: the idle hops' and glints' own dice, so these looks never move the run's shared random sequence.
var _rng := RandomNumberGenerator.new()
var _glint_mm: MultiMesh        # the glints' four-point stars (GLINT_*)
var _glints := 0                # glints showing now
var _glint_last := -INF         # when the last one started
var _rest_k := PackedFloat32Array()   # rest_of by kind, read every tick
var _hop_last := -INF           # when the last idle hop on the screen started (HOP_EXTRA_GAP)
## Pass 60: each slot's seed for the gem shader's shimmer (the shader works it out of the slot in custom y the same way),
## and how many custom-data writes were made (tests: a field of resting gems makes none once it is down).
var _seed := PackedFloat32Array()
## (custom y since the review of pass 61: the seed, 0..1; the shaders' phase is seed x TAU, phase_of)
var custom_writes := 0
var instance_writes := 0        # pass 61: transforms written (tests: a field lying still makes none)
## Pass 61: how many slots the pool has now (MAX, doubling), and how many pickups are on their way (flying).
var _cap := 0
var _flying_n := 0
## Pass 61, the instances: each pickup's place in its kind's MultiMesh (inst, -1 for none) and, by kind x _icap +
## place, which pickup holds it (_islot) and the charge its custom data says (_ich; -1 unknown); _inst_n by kind; _icap
## instances a kind, the same for every kind.
var inst := PackedInt32Array()
var _islot := PackedInt32Array()
var _ich := PackedFloat32Array()
var _inst_n := PackedInt32Array()
var _icap := 0
var _gem_mats: Array = []      # the four gem materials (t_now is set on them each drawn frame)
## Pass 61, the active list: every pickup the tick and the draw look at (falling, on its way, tossed, held, hopping,
## glinting), with each one's place in it (act_at, -1 when it lies still); and the pickups whose instance the next draw
## writes once (_dirty: it has just landed or stopped hopping).
var _act := PackedInt32Array()
var act_at := PackedInt32Array()
var _dirty := PackedInt32Array()
var _dirty_f := PackedByteArray()
## Pass 61, the grid of pickups lying on the sand: the first in each cell (_g_head) and each one's cell and neighbours
## (g_cell, -1 when it is not lying in the grid).
var _g_head := PackedInt32Array()
var g_cell := PackedInt32Array()
var _g_next := PackedInt32Array()
var _g_prev := PackedInt32Array()
## Pass 61, the idle turns' timing wheel: bucket -> the slots due in it (stale entries are skipped: idle_due says when a
## gem is really due), and the next bucket to read.
var _wheel := {}
var _wheel_next := 0
var _glinting := PackedInt32Array()   # the gems glinting now (GLINT_MAX at most)
## Pass 61, a big pull under way (vacuum_all, _vacuum_step): the grid's cells in rings from the cell it was called from
## (_ring_off: dx, dz pairs nearest first; _ring_d: their distance in cells), how far it has got, the coins too or not,
## when it was called, from where, and the distance beyond which nothing is on the screen (INF without a camera).
static var _ring_off := PackedInt32Array()
static var _ring_d := PackedFloat32Array()
var _vac_on := false
var _vac_k := 0
var _vac_cx := 0
var _vac_cz := 0
var _vac_coins := false
var _vac_t0 := 0.0
var _top := 17.0                # the flight's top speed as the last tick had it
## Pass 61, the off-screen ones of a big pull: each one's wait (vac_q: 1 to come over the edge, 2 to be taken unseen; 0
## none) and when it is due (_vq_due), the waits by bucket of the run's clock (_vq, read from _vq_next), the dives
## started past the edge in the air (edge_f, _edge_n), the screen's edge on the sand by direction from the hero (_edge_r,
## empty without a camera: then everything is on the screen) and when it was last measured, and the XP taken unseen
## this tick (handed to the run in one go).
var vac_q := PackedByteArray()
var _vq_due := PackedFloat32Array()
var _vq_b := PackedInt32Array()   # the bucket a slot's one live wait sits in (an entry in any other is stale)
var _vq := {}
var _vq_next := 0
var edge_f := PackedByteArray()
var _edge_n := 0
var _edge_r := PackedFloat32Array()
var _edge_t := -INF
var _credit_xp := 0.0


func _ready() -> void:
	_alloc(MAX)
	for i in range(MAX - 1, -1, -1):
		free_list.append(i)
	_inst_n.resize(KINDS)
	_icap = INST_START
	_islot.resize(KINDS * _icap)
	_islot.fill(-1)
	_ich.resize(KINDS * _icap)
	_ich.fill(-1.0)
	_mms.append(_make_mm(_gem_mesh(gem_radius(KIND_GEM_S)), COLOURS[KIND_GEM_S]))
	_mms.append(_make_mm(_gem_mesh(gem_radius(KIND_GEM_M)), COLOURS[KIND_GEM_M]))
	_mms.append(_make_mm(_gem_mesh(gem_radius(KIND_GEM_L)), COLOURS[KIND_GEM_L]))
	_mms.append(_make_mm(_coin_mesh(), COLOURS[KIND_COIN], coin_material()))
	_mms.append(_make_mm(_gem_mesh(gem_radius(KIND_VACUUM)), COLOURS[KIND_VACUUM]))
	_glint_mm = _make_glint_mm()
	for k in range(_mms.size()):
		_rest_k.append(rest_of(k))
	_g_head.resize(GRID_N * GRID_N)
	_g_head.fill(-1)
	_build_rings()
	_wheel_next = floori(_time / IDLE_BUCKET)
	_rng.randomize()


## Sizes every per-slot array to `n` slots (pass 61: at the start and whenever the pool doubles), the new ones empty.
func _alloc(n: int) -> void:
	var from := _cap
	# (packed arrays are values: each is sized where it lives)
	pos.resize(n); kind.resize(n); value.resize(n); vel.resize(n); flying.resize(n); alive.resize(n); born.resize(n)
	phase.resize(n); phase_t.resize(n); hop_dir.resize(n); hold.resize(n)
	hop_next.resize(n); hop_t.resize(n); glint_next.resize(n); glint_t.resize(n); idle_due.resize(n)
	# the magnet arc (pass 60)
	arced.resize(n); arc_delay.resize(n); arc_v0.resize(n); arc_drift.resize(n); arc_hang.resize(n); arc_apex.resize(n); arc_spin.resize(n)
	_seed.resize(n)
	inst.resize(n); act_at.resize(n); _dirty_f.resize(n); g_cell.resize(n); _g_next.resize(n); _g_prev.resize(n)
	vac_q.resize(n); _vq_due.resize(n); edge_f.resize(n); _vq_b.resize(n)
	for i in range(from, n):
		alive[i] = 0
		flying[i] = 0
		hop_next[i] = -1.0
		hop_t[i] = -1.0
		glint_next[i] = -1.0
		glint_t[i] = -1.0
		idle_due[i] = -1.0
		_seed[i] = fmod(float(i) * 0.6180339887, 1.0)
		inst[i] = -1
		act_at[i] = -1
		g_cell[i] = -1
		_g_next[i] = -1
		_g_prev[i] = -1
		_vq_b[i] = -1
	if record_draws:
		drawn_xf.resize(n)
		drawn_charge.resize(n)
	_cap = n


## The pool is full (pass 61): it doubles, the new slots joining the free list (the lowest first).
func _grow() -> void:
	var from := _cap
	_alloc(_cap * 2)
	for i in range(_cap - 1, from - 1, -1):
		free_list.append(i)


## A kind's MultiMesh is full (pass 61): every kind's doubles, keeping what its instances hold (the buffer copied over in
## one go) and showing as many as before.
func _grow_instances() -> void:
	var old := _icap
	_icap *= 2
	var slot := PackedInt32Array()
	slot.resize(KINDS * _icap)
	slot.fill(-1)
	var ch := PackedFloat32Array()
	ch.resize(KINDS * _icap)
	ch.fill(-1.0)
	for k in range(KINDS):
		for n in range(old):
			slot[k * _icap + n] = _islot[k * old + n]
			ch[k * _icap + n] = _ich[k * old + n]
		var mm: MultiMesh = _mms[k]
		var stride := 12 + (4 if mm.use_custom_data else 0)
		var buf: PackedFloat32Array = mm.buffer
		var shown := mm.visible_instance_count
		mm.instance_count = _icap
		buf.resize(_icap * stride)
		mm.buffer = buf
		mm.visible_instance_count = shown
	_islot = slot
	_ich = ch


## The grid's cells in the order a big pull walks them (pass 61, once a run of the game): every (dx, dz) from -GRID_N
## to GRID_N, nearest first (sorted by half cells of distance), with its distance in cells.
func _build_rings() -> void:
	if not _ring_d.is_empty():
		return
	var n := GRID_N
	var nb := int(ceil(float(n) * 1.4143 * 2.0)) + 2
	var buckets: Array = []
	buckets.resize(nb)
	for b in range(nb):
		buckets[b] = []
	for dz in range(-n, n + 1):
		for dx in range(-n, n + 1):
			var d := sqrt(float(dx * dx + dz * dz))
			(buckets[int(d * 2.0)] as Array).append(Vector3i(dx, dz, 0))
	var off := PackedInt32Array()
	var dist := PackedFloat32Array()
	for b in range(nb):
		for v: Vector3i in buckets[b]:
			off.append(v.x)
			off.append(v.y)
			dist.append(sqrt(float(v.x * v.x + v.y * v.y)))
	_ring_off = off
	_ring_d = dist


## The grid's column (or row) at x (or z) metres (pass 61), the edge one for anything beyond it.
static func _cell_x(x: float) -> int:
	return clampi(floori((x + GRID_HALF) / GRID_CELL), 0, GRID_N - 1)


## Pickup `i` lies down in the grid where it is (pass 61).
func _g_add(i: int) -> void:
	if g_cell[i] >= 0:
		return
	var c := _cell_x(pos[i].z) * GRID_N + _cell_x(pos[i].x)
	var h := _g_head[c]
	_g_prev[i] = -1
	_g_next[i] = h
	if h >= 0:
		_g_prev[h] = i
	_g_head[c] = i
	g_cell[i] = c


## Pickup `i` leaves the grid (pass 61): it is on its way, or gone.
func _g_del(i: int) -> void:
	var c := g_cell[i]
	if c < 0:
		return
	var p := _g_prev[i]
	var nx := _g_next[i]
	if p >= 0:
		_g_next[p] = nx
	else:
		_g_head[c] = nx
	if nx >= 0:
		_g_prev[nx] = p
	g_cell[i] = -1
	_g_next[i] = -1
	_g_prev[i] = -1


## Pickup `i` joins the active list: the tick and the draw look at it every frame (pass 61).
func _act_add(i: int) -> void:
	if act_at[i] >= 0:
		return
	act_at[i] = _act.size()
	_act.append(i)


## Pickup `i` leaves the active list (pass 61); still on the sand, its instance is written once more as it lies.
func _act_del(i: int) -> void:
	var a := act_at[i]
	if a < 0:
		return
	var last := _act.size() - 1
	var j := _act[last]
	_act[a] = j
	act_at[j] = a
	_act.resize(last)
	act_at[i] = -1
	if alive[i] == 1:
		_mark_dirty(i)


## The next draw writes pickup `i`'s instance once (pass 61).
func _mark_dirty(i: int) -> void:
	if _dirty_f[i] == 1:
		return
	_dirty_f[i] = 1
	_dirty.append(i)


## Gem `i`'s idle turn at `t` goes on the wheel (pass 61); a time already passed is read with the next bucket.
func _wheel_add(i: int, t: float) -> void:
	var b := maxi(floori(t / IDLE_BUCKET), _wheel_next)
	var arr = _wheel.get(b)
	if arr == null:
		arr = []
		_wheel[b] = arr
	(arr as Array).append(i)


## Gem `i`'s idle next has something to do at `t` (pass 61: idle_due, and a turn on the wheel when it lies still). Tests
## force a turn with it; a gem lying still is never looked at otherwise.
func set_idle_due(i: int, t: float) -> void:
	idle_due[i] = t
	if alive[i] == 1 and g_cell[i] >= 0 and act_at[i] < 0:
		# (read back: the wheel's buckets are worked out from the stored time, as _wheel_run reads it)
		_wheel_add(i, idle_due[i])


## The wheel's turns that are due (pass 61): every bucket the clock has passed, then the ones due in the bucket it is in.
## An entry is stale when its gem has gone, left the sand, is being looked at every tick anyway (hopping, glinting) or
## was put off to a later time (idle_due is the truth); a gem due now has its turn (_idle).
func _tick_wheel(delta: float) -> void:
	var now_b := floori(_time / IDLE_BUCKET)
	if now_b - _wheel_next > 2048:
		# the clock jumped far (tests): only the buckets that hold something
		var keys: Array = []
		for b in _wheel.keys():
			if int(b) < now_b:
				keys.append(int(b))
		keys.sort()
		_wheel_next = now_b
		for b: int in keys:
			var arr = _wheel.get(b)
			_wheel.erase(b)
			if arr != null:
				_wheel_run(arr as Array, delta, -1)
	while _wheel_next < now_b:
		var b := _wheel_next
		_wheel_next += 1
		var arr = _wheel.get(b)
		if arr != null:
			_wheel.erase(b)
			_wheel_run(arr as Array, delta, -1)
	var cur = _wheel.get(now_b)
	if cur != null:
		_wheel.erase(now_b)
		var keep := _wheel_run(cur as Array, delta, now_b)
		if not keep.is_empty():
			var more = _wheel.get(now_b)
			if more != null:
				keep.append_array(more as Array)
			_wheel[now_b] = keep


## One bucket's entries (pass 61): each gem due has its turn; with `bucket` >= 0 the ones not due yet that belong to it
## are handed back to wait.
func _wheel_run(arr: Array, delta: float, bucket: int) -> Array:
	var keep: Array = []
	for i: int in arr:
		if i >= _cap or alive[i] == 0 or g_cell[i] < 0 or act_at[i] >= 0:
			continue
		var due := idle_due[i]
		if due < 0.0:
			continue
		if due > _time:
			if bucket >= 0 and floori(due / IDLE_BUCKET) == bucket:
				keep.append(i)
			continue
		_idle(i, delta)
	return keep


## Pickup `i` comes to rest on the sand (pass 61): into the grid, out of the active list (its instance written once more
## where it lies) and, a gem, its idle clocks start (_idle's first call puts its first turn on the wheel).
func _rest(i: int) -> void:
	vel[i] = Vector3.ZERO
	_g_add(i)
	_act_del(i)
	_mark_dirty(i)
	if kind[i] <= KIND_GEM_L:
		_idle(i, 0.0)


## Every pickup lying within `r` m (flat) of `c` sets off for the hero at `hero` (pass 61: the magnet round the hero, a
## turret's pull round the turret, `arc` for the big pull's arc), read from the grid's cells that reach touches.
func _pull_round(c: Vector3, r: float, hero: Vector3, arc: bool) -> void:
	var x0 := _cell_x(c.x - r)
	var x1 := _cell_x(c.x + r)
	var z0 := _cell_x(c.z - r)
	var z1 := _cell_x(c.z + r)
	var r2 := r * r
	for cz in range(z0, z1 + 1):
		for cx in range(x0, x1 + 1):
			var i := _g_head[cz * GRID_N + cx]
			while i >= 0:
				var nx := _g_next[i]
				var dx := pos[i].x - c.x
				var dz := pos[i].z - c.z
				if dx * dx + dz * dz < r2:
					_start_trip(i, hero, arc)
				i = nx


## The screen's edge on the sand round the hero at `hero` (pass 61): the camera's four corner rays meet the sand at his
## height in a four-sided footprint around him, and _edge_r[b] is how far its edge lies (+ EDGE_MARGIN) in direction
## bin b (atan2(dz, dx) from -PI, EDGE_BINS of them), the farthest of the bin's two sides and its middle, so a point past
## it is surely off the screen. Empty without a camera (tests, tools) or when a corner looks over the horizon: then
## everything counts as on the screen.
func _edge_table(hero: Vector3) -> void:
	_edge_r = PackedFloat32Array()
	_edge_t = _time
	var rig := _rig()
	if rig == null or rig.camera == null or hero == Vector3.INF:
		return
	var cam: Camera3D = rig.camera
	var vp := rig.get_viewport().get_visible_rect().size
	var poly := PackedVector2Array()
	for corner in [Vector2.ZERO, Vector2(vp.x, 0.0), vp, Vector2(0.0, vp.y)]:
		var o := cam.project_ray_origin(corner)
		var d := cam.project_ray_normal(corner)
		if d.y > -0.05:
			return
		var p := o + d * ((hero.y - o.y) / d.y)
		poly.append(Vector2(p.x - hero.x, p.z - hero.z))
	var out := PackedFloat32Array()
	out.resize(EDGE_BINS)
	for b in range(EDGE_BINS):
		var a0 := -PI + TAU * float(b) / float(EDGE_BINS)
		var a1 := a0 + TAU / float(EDGE_BINS)
		out[b] = maxf(maxf(_exit(poly, a0), _exit(poly, a1)), _exit(poly, (a0 + a1) * 0.5)) + EDGE_MARGIN
	_edge_r = out


## How far the ray from the middle of the footprint `poly` (the hero, at the origin) in direction `a` runs before it
## leaves it (pass 61); INF when it never does (the hero outside it: everything then counts as on the screen).
static func _exit(poly: PackedVector2Array, a: float) -> float:
	var u := Vector2(cos(a), sin(a))
	var best := INF
	for k in range(poly.size()):
		var p := poly[k]
		var e := poly[(k + 1) % poly.size()] - p
		var den := u.x * e.y - u.y * e.x
		if absf(den) < 0.000001:
			continue
		var t := (p.x * e.y - p.y * e.x) / den
		var s := (p.x * u.y - p.y * u.x) / den
		if t > 0.0 and s >= -0.0001 and s <= 1.0001:
			best = minf(best, t)
	return best


## How far the screen's edge lies from the hero at `hero` towards `at` on the sand (pass 61, _edge_table); INF without a
## measure (everything on the screen).
func edge_at(at: Vector3, hero: Vector3) -> float:
	if _edge_r.is_empty():
		return INF
	var b := int((atan2(at.z - hero.z, at.x - hero.x) + PI) / TAU * float(EDGE_BINS))
	return _edge_r[clampi(b, 0, EDGE_BINS - 1)]


## One step of a big pull under way (pass 61, vacuum_all): the grid's cells nearest the cell it was called from first,
## WALK_MAX lying pickups and WALK_CELLS cells at most a tick (coins with `_vac_coins`): one on the screen sets off on the arc while fewer than
## FLIGHT_MAX are on their way (else the walk waits for room), its wait in the ripple shortened by the ticks the walk
## took to reach it; one off it waits where it lies for its turn to come over the edge (vac_q 1, _tick_vq). Goes on next
## tick from where it stopped.
func _vacuum_step(hero: Vector3) -> void:
	if _time - _edge_t > 0.5:
		_edge_table(hero)
	var budget := FLIGHT_MAX - _flying_n
	var looked := 0
	var cells := 0
	var late := _time - _vac_t0
	var n := _ring_d.size()
	while _vac_k < n:
		cells += 1
		if cells > WALK_CELLS:
			return
		var cx := _vac_cx + _ring_off[_vac_k * 2]
		var cz := _vac_cz + _ring_off[_vac_k * 2 + 1]
		if cx < 0 or cz < 0 or cx >= GRID_N or cz >= GRID_N:
			_vac_k += 1
			continue
		var i := _g_head[cz * GRID_N + cx]
		while i >= 0:
			var nx := _g_next[i]
			if vac_q[i] == 0 and (_vac_coins or kind[i] != KIND_COIN):
				looked += 1
				var d := Vector2(pos[i].x - hero.x, pos[i].z - hero.z).length()
				var r := edge_at(pos[i], hero)
				if d <= r:
					if budget <= 0:
						return
					_start_trip(i, hero, true, late)
					budget -= 1
				else:
					vac_q[i] = 1
					_vq_add(i, _vac_t0 + FAR_LEAD + (d - r) / _top)
			i = nx
			if looked >= WALK_MAX and i >= 0:
				# the rest of this cell next tick
				return
		_vac_k += 1
	_vac_on = false


## Off-screen pickup `i`'s wait (pass 61) goes on the pull's own wheel, due at `t`, never before the bucket the reading
## is at; its one live entry (_vq_b), so an older one is stale.
func _vq_add(i: int, t: float) -> void:
	_vq_due[i] = t
	var b := maxi(floori(float(_vq_due[i]) / IDLE_BUCKET), _vq_next)
	_vq_b[i] = b
	var arr = _vq.get(b)
	if arr == null:
		arr = []
		_vq[b] = arr
	(arr as Array).append(i)


## The off-screen waits that are due (pass 61): every bucket the clock has passed, then the due ones of the bucket it is
## in. A stale entry (gone, taken by the magnet, called by a later pull) is skipped.
func _tick_vq(hero: Vector3) -> void:
	if _time - _edge_t > 0.5:
		_edge_table(hero)
	var now_b := floori(_time / IDLE_BUCKET)
	if now_b - _vq_next > 2048:
		# the clock jumped far (tests): straight to the first bucket that holds something
		var first := now_b
		for k in _vq.keys():
			first = mini(first, int(k))
		_vq_next = first
	var turns := 0
	while _vq_next <= now_b:
		var b := _vq_next
		var arr = _vq.get(b)
		var full := false
		if arr != null:
			_vq.erase(b)
			var keep: Array = []
			for i: int in arr:
				if full:
					# past this tick's VQ_TURNS: the rest wait for the next tick (they are off the screen)
					keep.append(i)
					continue
				if i >= _cap or alive[i] == 0 or g_cell[i] < 0 or vac_q[i] == 0 or _vq_b[i] != b:
					continue
				if _vq_due[i] > _time:
					keep.append(i)
					continue
				_vq_turn(i, hero)
				turns += 1
				full = turns >= VQ_TURNS
			if not keep.is_empty():
				# back where the reading is (it has not moved: b), with anything added there meanwhile
				var kb := maxi(b, _vq_next)
				for i: int in keep:
					if _vq_b[i] == b:
						_vq_b[i] = kb
				var more = _vq.get(kb)
				if more != null:
					keep.append_array(more as Array)
				_vq[kb] = keep
		if b == now_b or full:
			break
		_vq_next += 1


## Off-screen pickup `i`'s turn has come (pass 61). If he has walked so near that it shows, it goes up the arc as the ones
## on the screen did (or waits a beat for room). Its turn to come over the edge: its dive starts just past the edge
## (_launch_far) while the stream has room, else it waits until it would have reached him. That turn: taken where it
## lies, quietly (_collect's quiet way), never where it can be seen.
func _vq_turn(i: int, hero: Vector3) -> void:
	var d := Vector2(pos[i].x - hero.x, pos[i].z - hero.z).length()
	var r := edge_at(pos[i], hero)
	if d <= r:
		if _flying_n < FLIGHT_MAX:
			_start_trip(i, hero, true)
		else:
			_vq_add(i, _time + 0.1)
		return
	if vac_q[i] == 1:
		if _edge_n < EDGE_MAX and _flying_n < FLIGHT_MAX:
			_launch_far(i, hero, d, r)
		else:
			vac_q[i] = 2
			_vq_add(i, _time + r / _top)
		return
	_collect(i, true)


## A pickup the big pull calls from beyond the screen when its turn to come over the edge has come (pass 61): nobody saw
## its wait, its throw or the first part of its dive, so it starts the dive `r` m from the hero (the edge and a margin)
## on the line from his chest to where its arc's top would have been over the spot it lay `d` m away, already at the top
## speed and charged.
func _launch_far(i: int, hero: Vector3, d: float, r: float) -> void:
	_end_idle(i)
	_g_del(i)
	vac_q[i] = 0
	var h: float = ARC_HEIGHT_MIN + _rng.randf() * ARC_HEIGHT_RANGE + ARC_HEIGHT_PER_M * d
	var chest := hero + Vector3(0.0, CHEST, 0.0)
	var apex := Vector3(pos[i].x, pos[i].y + h, pos[i].z)
	pos[i] = chest + (apex - chest) * clampf(r / maxf(d, 0.001), 0.0, 1.0)
	vel[i] = Vector3.ZERO
	hop_dir[i] = Vector3(apex.x - hero.x, 0.0, apex.z - hero.z).normalized()
	flying[i] = 1
	_flying_n += 1
	edge_f[i] = 1
	_edge_n += 1
	arced[i] = 1
	arc_spin[i] = _rng.randf() * TAU
	phase[i] = PHASE_FLY
	phase_t[i] = maxf(_top / FLY_ACCEL, FLY_CURVE_TIME)
	_act_add(i)


func _gem_mesh(r: float) -> Mesh:
	return octahedron_mesh(r)


## The radius of kind `k`'s octahedron as drawn (pass 56): its size (GEM_R, VACUUM_R) times its kind's look factor
## (GEM_LOOK, VACUUM_LOOK); 0 for a coin.
static func gem_radius(k: int) -> float:
	if k >= KIND_GEM_S and k <= KIND_GEM_L:
		return float(GEM_R[k]) * float(GEM_LOOK[k])
	if k == KIND_VACUUM:
		return VACUUM_R * VACUUM_LOOK
	return 0.0


## How high a pickup of kind `k` rests over the sand (pass 56): REST, or for a gem whose lower tip would dip into the
## sand at the bottom of its float (float_y at its lowest), just high enough that the tip clears it by GEM_CLEAR.
static func rest_of(k: int) -> float:
	var half := gem_radius(k) * GEM_TALL * 0.5
	if half <= 0.0:
		return REST
	return maxf(REST, half + GEM_CLEAR - (0.06 - BOB))


## Pickup `i` starts no lower than where it rests over the sand (pass 56: a gem merged at the middle of smaller ones lies
## under a large gem's rest_of; it pops up from its rest instead of snapping up to it a frame later).
func _lift_to_rest(i: int) -> void:
	var rest: float = _ground_at(pos[i].x, pos[i].z) + rest_of(kind[i])
	if pos[i].y < rest:
		pos[i].y = rest


## The sand's height at (x, z): the map's, 0 without one (tests).
func _ground_at(x: float, z: float) -> float:
	var map = game.get("map") if game != null else null
	return map.height_at(x, z) if map else 0.0


## How high a drop of kind `k` let go at `p` starts (the fix round of pass 56, the lead: the bigger gems rest higher since
## pass 56, rest_of, and from DROP_FROM over the creature's feet they fell about half as far after the pop as in v0.41):
## DROP_FROM - REST over its own rest, so every size falls from its pop as far as v0.41's did. One let go above the sand
## (a barrel's burst, a creature dying in the air) keeps that height on top, as it always did.
func _drop_y(k: int, p: Vector3) -> float:
	return maxf(p.y, _ground_at(p.x, p.z)) + DROP_FROM + rest_of(k) - REST


## The gem (pass 56, Garry: "more of a Rhombohedron shape, but 3d obviously ... like a gem", then "I mean octahedron"):
## six points (a tip at the top, one at the bottom and four round the middle) and eight triangular faces, GEM_TALL r from
## tip to tip and 2 r across. Every face has its own three corners and one flat normal pointing out, so each facet
## catches the sun differently as the gem spins. Godot draws a triangle whose corners run clockwise seen from outside
## (a counter-clockwise one is culled), so each face's corners are laid down that way.
static func octahedron_mesh(r: float) -> ArrayMesh:
	var half := r * GEM_TALL * 0.5
	var tips := [Vector3(0.0, half, 0.0), Vector3(0.0, -half, 0.0)]
	var ring := [Vector3(r, 0.0, 0.0), Vector3(0.0, 0.0, r), Vector3(-r, 0.0, 0.0), Vector3(0.0, 0.0, -r)]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for tip: Vector3 in tips:
		for k in range(4):
			var a: Vector3 = ring[k]
			var b: Vector3 = ring[(k + 1) % 4]
			var n := (a - tip).cross(b - tip).normalized()
			if n.dot(tip + a + b) < 0.0:
				n = -n
			# clockwise from outside: (second - first) x (third - first) points into the gem
			var tri := [tip, a, b] if (a - tip).cross(b - tip).dot(n) < 0.0 else [tip, b, a]
			for p: Vector3 in tri:
				verts.append(p)
				norms.append(n)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _coin_mesh() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = COIN_R
	m.bottom_radius = COIN_R
	m.height = COIN_H
	m.radial_segments = 12
	return m


## The coin's look (pass 52, Garry: the coin "blends in with the floor sand way too well"): core/shaders/coin.gdshader, a
## bright face in a dark outline that the sun never washes out. One material for every coin (Warmup draws it once).
## Pass 54: the shader writes ALPHA 1 and no depth, so the coin is drawn see-through at PICKUP_PRIORITY like the gems; its
## face pattern is laid out for COIN_R.
static var _coin_mat: ShaderMaterial = null
static func coin_material() -> ShaderMaterial:
	if _coin_mat == null:
		_coin_mat = ShaderMaterial.new()
		_coin_mat.shader = load("res://core/shaders/coin.gdshader")
		_coin_mat.set_shader_parameter("radius", COIN_R)
		# the float the shader does (pass 61): its height and middle; `t_now` is the run's clock (_render)
		_coin_mat.set_shader_parameter("bob", BOB)
		_coin_mat.set_shader_parameter("float_base", FLOAT_BASE)
		_coin_mat.render_priority = PICKUP_PRIORITY
	return _coin_mat


## The gems' material (pass 60): core/shaders/gem.gdshader in `color` with the rest glow GEM_EMISSION, see-through and
## depth-less at PICKUP_PRIORITY and reading the stencil (the shader says so: pass 54's rules), one a kind. The charge
## rides on the MultiMesh's custom data (charge_of, _render).
static var _gem_shader: Shader = null
static func gem_material(color: Color) -> ShaderMaterial:
	if _gem_shader == null:
		_gem_shader = load("res://core/shaders/gem.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _gem_shader
	m.set_shader_parameter("albedo", Color(color.r, color.g, color.b, 1.0))
	m.set_shader_parameter("rest_emission", GEM_EMISSION)
	m.set_shader_parameter("charged_emission", CHARGED_EMISSION)
	# the float and the spin the shader does (pass 61); `t_now` is the run's clock (_render)
	m.set_shader_parameter("bob", BOB)
	m.set_shader_parameter("float_base", FLOAT_BASE)
	m.render_priority = PICKUP_PRIORITY
	return m


## One kind's MultiMesh: a gem in `color` on the gem shader (gem_material; pass 60: with custom data for the charge), or
## `mat` when it has a look of its own (the coin).
func _make_mm(mesh: Mesh, color: Color, mat: Material = null) -> MultiMesh:
	var gem := mat == null
	if gem:
		# see-through and depth-less (pass 54): drawn after every opaque thing, and only where no painting is (the
		# stencil, PAINTING_STENCIL), so a creature's, the hero's or a prop's painting covers a gem at its feet
		mat = gem_material(color)
		_gem_mats.append(mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# the charge (pass 60) and the float's seed (pass 61; the coin's too), set before the count: a MultiMesh lays its
	# buffer out when it is sized
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = _icap
	mm.visible_instance_count = 0
	# pass 61: the box it may fill, so the server never measures its instances again when one moves or the count changes
	mm.set("custom_aabb", AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(mmi)
	return mm


## The glints' MultiMesh (pass 56): unit quads that core/shaders/gem_glint.gdshader turns to the camera as four-point
## stars, each instance's colour its tint and brightness and its custom x its turn; GLINT_MAX of them and one for the
## warm-up.
func _make_glint_mm() -> MultiMesh:
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = GLINT_MAX + 1
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Glints"
	mmi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://core/shaders/gem_glint.gdshader")
	mat.render_priority = GLINT_PRIORITY
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(mmi)
	return mm


## A drop of `p_kind` worth `v` let go at `at`; its slot. Pass 61: never lost and never merged (the pool doubles when it
## is full); it takes the next place in its kind's MultiMesh, whose custom data (the gem shader's charge 0 and the seed
## its float and spin are timed by, phase_of; the coin's too) is written now, once, and falls in the active list until
## it lands.
func spawn(p_kind: int, at: Vector3, v: float) -> int:
	if free_list.is_empty():
		_grow()
	var i: int = free_list.pop_back()
	pos[i] = at + Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4))
	# DROP_FROM over where it was let go, and as much higher again as its kind rests (the fix round of pass 56)
	pos[i].y = _drop_y(p_kind, pos[i])
	kind[i] = p_kind
	value[i] = v
	vel[i] = Vector3(randf_range(-1.5, 1.5), 3.0, randf_range(-1.5, 1.5))
	flying[i] = 0
	phase[i] = PHASE_GROUND
	phase_t[i] = 0.0
	hop_dir[i] = Vector3.ZERO
	hold[i] = 0.0
	arced[i] = 0
	# its idle hop and glint clocks start when it lands (pass 56, _idle)
	hop_next[i] = -1.0
	hop_t[i] = -1.0
	glint_next[i] = -1.0
	idle_due[i] = -1.0
	alive[i] = 1
	born[i] = _time
	count += 1
	if p_kind == KIND_COIN:
		coins += 1
	# its instance (pass 61): the kind's next place, the MultiMeshes doubling when one is full
	if _inst_n[p_kind] >= _icap:
		_grow_instances()
	var n := _inst_n[p_kind]
	_inst_n[p_kind] = n + 1
	inst[i] = n
	_islot[p_kind * _icap + n] = i
	(_mms[p_kind] as MultiMesh).set_instance_custom_data(n, Color(0.0, _seed[i], 0.0, 0.0))
	_ich[p_kind * _icap + n] = 0.0
	custom_writes += 1
	_act_add(i)
	return i


## The coin in slot `i` (a spawn's answer; -1 does nothing) came from `source` (pass 61: gold_dust, boss_coins, ...); the
## gold it pays when taken is counted under it. Returns `i`.
func mark_coin(i: int, source: String) -> int:
	if i >= 0:
		coin_from[i] = source
	return i


## Loose Change (pass 48, a passive item): a coin worth `v` a hit knocks out of the hero standing at `at`
## (Game._on_player_hit; the stage scales it when it is taken, like every coin). It flies on an arc to a spot TOSS_MIN to
## TOSS_MAX m away (toss_spot), lands with a little bounce and a glint, and lies TOSS_HOLD s where the magnet and the
## turrets' pull leave it alone, so he goes and gets it; then it is a coin like any other. A vacuum still calls it.
## Returns its index (-1 with the pool full).
func toss_coin(at: Vector3, v: float = 10.0) -> int:
	var i := spawn(KIND_COIN, at, v)
	if i < 0:
		return i
	mark_coin(i, "loose_change")
	var map = game.get("map") if game != null else null
	var to := toss_spot(at, map)
	var land := Vector3(to.x, (map.height_at(to.x, to.z) if map else 0.0) + REST, to.z)
	var from := at + Vector3(0.0, TOSS_FROM, 0.0)
	pos[i] = from
	# the arc that lands on the spot at TOSS_TIME under the drop's gravity
	vel[i] = Vector3((land.x - from.x) / TOSS_TIME, (land.y - from.y) / TOSS_TIME + 0.5 * HOP_GRAV * TOSS_TIME,
		(land.z - from.z) / TOSS_TIME)
	phase[i] = PHASE_TOSS
	phase_t[i] = 0.0
	var away := Vector3(land.x - at.x, 0.0, land.z - at.z)
	hop_dir[i] = away.normalized() if away.length_squared() > 0.0001 else Vector3.FORWARD
	Audio.play("pk_coin", from)
	return i


## Where a tossed coin comes down (pass 48): TOSS_MIN..TOSS_MAX m from `at` in a random direction, inside the arena by
## TOSS_EDGE and off the rocks (the map's obstacle circles); after TOSS_TRIES blocked tries, TOSS_MIN towards the
## arena's middle. Without a map anywhere on the ring.
func toss_spot(at: Vector3, map = null) -> Vector3:
	var rim := INF
	var rocks: Array = []
	if map != null:
		var ar = map.get("arena_radius")
		if ar != null:
			rim = float(ar) - TOSS_EDGE
		var ob = map.get("obstacles")
		if ob is Array:
			rocks = ob
	for k in range(TOSS_TRIES):
		var a := randf() * TAU
		var d := randf_range(TOSS_MIN, TOSS_MAX)
		var p := Vector3(at.x + cos(a) * d, at.y, at.z + sin(a) * d)
		if Vector2(p.x, p.z).length() <= rim and not _on_rock(p, rocks):
			return p
	var inward := Vector3(-at.x, 0.0, -at.z)
	if inward.length_squared() < 0.0001:
		inward = Vector3.FORWARD
	return at + inward.normalized() * TOSS_MIN


## Whether `p` lies on a rock (an obstacle circle Vector3(x, z, r)) or within TOSS_CLEAR of its edge.
static func _on_rock(p: Vector3, rocks: Array) -> bool:
	for o in rocks:
		if not o is Vector3:
			continue
		var ob: Vector3 = o
		if Vector2(p.x - ob.x, p.z - ob.y).length() < ob.z + TOSS_CLEAR:
			return true
	return false


## One tick of a tossed coin's arc (exact for a constant pull, so it comes down on its spot), kept over the sand where a
## dune rises in its way; at TOSS_TIME it lands with a bounce and a glint, and its hold starts.
func _toss_tick(i: int, delta: float, map) -> void:
	var dt := clampf(TOSS_TIME - phase_t[i], 0.0, delta)
	phase_t[i] += delta
	pos[i] += vel[i] * dt + Vector3(0.0, -0.5 * HOP_GRAV * dt * dt, 0.0)
	vel[i].y -= HOP_GRAV * dt
	var ground: float = (map.height_at(pos[i].x, pos[i].z) if map else 0.0) + REST
	if pos[i].y < ground:
		pos[i].y = ground
	if phase_t[i] < TOSS_TIME:
		return
	pos[i].y = ground
	phase[i] = PHASE_GROUND
	phase_t[i] = 0.0
	vel[i] = Vector3(0.0, TOSS_BOUNCE, 0.0)
	hold[i] = TOSS_HOLD
	_glint(i)


## An Elite's or a boss's own coin (drops.gold) is worth this many times a creature's (pass 70, Garry: "Make Elites and
## Bosses give much more Coins"; their purses are Game.ELITE_PURSE / BOSS_PURSE).
## Pass 110 (lane ECON; Garry: "Reduce the coins gain from Boss, Elite and Specials. By 50%"): 5 -> 2.5 (a coin of 1-3 x
## 2.5, the fraction paid by chance in MirrorDanger.scaled_count, so on average exactly half of pass 70's).
const BIG_COIN_MULT := 2.5
## Pass 110 (lane ECON): a variance special's own coin (its creature's drops.gold roll) comes this share as often; the
## purses and BIG_COIN_MULT are the Elites' and bosses' half.
const SPECIAL_COIN_MULT := 0.5


## The factor on the drops.gold coin of `def`: BIG_COIN_MULT for an Elite (its kind, or a creature wearing an Elite
## modifier: `is_elite`) and a boss, 1 for the rest.
static func big_coin_mult(def: EnemyDef, is_elite: bool) -> float:
	if is_elite or (def != null and (def.archetype == "elite" or def.archetype == "boss")):
		return BIG_COIN_MULT
	return 1.0


## Pass 87 (lane SGAME): in Endless a creature's coin roll happens only this share of the time (WaveDirector.start_endless
## sets the map's endless.coin_chance; 1 outside Endless). Garry: "drop coins very very rarely".
var endless_coin_chance := 1.0


## `coin_mult` (pass 110) scales the chance of its coin: SPECIAL_COIN_MULT for a variance special, 1 for the rest.
func drop_from(def: EnemyDef, at: Vector3, xp_scale: float, is_elite: bool, coin_mult: float = 1.0) -> void:
	var d := def.drops
	var luck: float = Run.player_sheet.get_stat("luck", 0.0)
	# pass 87 (lane SGAME): Endless's coins, only endless_coin_chance of the time
	if endless_coin_chance < 1.0 and float(d.get("gold", 0.0)) > 0.0 and randf() >= endless_coin_chance:
		d = d.duplicate()
		d["gold"] = 0.0
	if randf() < float(d.get("small", 0.0)):
		spawn(KIND_GEM_S, at, 1.0 * xp_scale)
	if randf() < float(d.get("medium", 0.0)) + luck * 0.1:
		spawn(KIND_GEM_M, at, 5.0 * xp_scale)
	if randf() < float(d.get("large", 0.0)):
		spawn(KIND_GEM_L, at, 25.0 * xp_scale)
	if randf() < float(d.get("gold", 0.0)) * (1.0 + luck) * coin_mult:
		# pass 87 (lane FIXES): the black barrels' coins come out of the creatures' (coin_debt, COIN_DEBT_SHARE of them)
		var cv := _after_coin_debt(float(1 + randi() % 3) * big_coin_mult(def, is_elite))
		# pass 88 (lane MIRROR): the Stakes' bounty on its kind, a fraction paid by chance (MirrorDanger.scaled_count)
		cv = float(MirrorDanger.scaled_count(cv, MirrorDanger.factor_of(def, "bounty")))
		if cv > 0.0:
			spawn(KIND_COIN, at, cv)
	if is_elite and randf() < 0.05 + luck * 0.1:
		spawn(KIND_VACUUM, at, 0.0)


# ---------------------------------------------------------------- pass 87 (lane FIXES): the black barrels' coins
## Garry: "The darker barrels should now give between 1-5 coins. Because of this you reduce the number of coins that
## Player could have normally have gotten from just killing enemies by the equivalent of claiming all of the dark barrels
## around the map." The coin value the creatures' coins still owe this run: every coin the map's black barrels hold
## (BarrelField.coins_total, set when the barrels are laid out). While anything is owed, a coin a creature would drop
## (drops.gold, Elites' and bosses' too) goes to the bill COIN_DEBT_SHARE of the time: the bill takes its value (before
## the stage and greed) and it does not drop, or only what is left of it once the bill is paid. So a run that breaks every
## black barrel earns what it earned before, a short one gives up only its share, and once the bill is paid the kills
## drop their coins as ever; purses, chests and the rest are untouched.
const COIN_DEBT_SHARE := 0.4
var coin_debt := 0.0
## The coin value the bill took so far this run (tests, the sim's numbers).
var coin_debt_paid := 0.0


func set_coin_debt(v: float) -> void:
	coin_debt = maxf(v, 0.0)


## What drops of a creature's coin worth `v` (0: nothing): the bill takes it COIN_DEBT_SHARE of the time while anything is
## owed (`share` stands in for the share in tests).
func _after_coin_debt(v: float, share: float = COIN_DEBT_SHARE) -> float:
	if coin_debt <= 0.0 or v <= 0.0 or randf() >= share:
		return v
	var take := minf(coin_debt, v)
	coin_debt -= take
	coin_debt_paid += take
	return v - take


## The gem a creature mostly drops (pass 47, for Prospector's extra one): the size with the best chance in its drops, the
## larger on a tie; small when it drops none.
static func base_gem_kind(def: EnemyDef) -> int:
	var d: Dictionary = def.drops if def else {}
	var sm := float(d.get("small", 0.0))
	var md := float(d.get("medium", 0.0))
	var lg := float(d.get("large", 0.0))
	if lg > 0.0 and lg >= md and lg >= sm:
		return KIND_GEM_L
	if md > 0.0 and md >= sm:
		return KIND_GEM_M
	return KIND_GEM_S


## Prospector (pass 47, Garry: "chance to spawn an extra XP shard when killing an enemy"): with `chance`, one more gem of
## the creature's base size where it fell, worth what that gem is worth from it (`xp_scale` as drop_from takes it). True
## when it dropped one.
func prospector(def: EnemyDef, at: Vector3, xp_scale: float, chance: float) -> bool:
	# Eureka (pass 70): its vein rolls with the extra gem
	vein(def, at, xp_scale)
	if chance <= 0.0 or randf() >= chance:
		return false
	var k := base_gem_kind(def)
	return spawn(k, at, float(GEM_VALUE[k]) * xp_scale) >= 0


# ---------------------------------------------------------------- pass 70 (lane LINES): Eureka, Mother Lode
## Eureka (pass 70, Prospector's evolution): with the hero's `vein_chance` (or `chance` when given), a kill strikes a vein:
## VEIN_GEMS more gems of the creature's base size, each worth what that gem is from it, burst out of where it fell in a
## fountain (VEIN_OUT m/s outward, VEIN_UP up) and land round it, with a gold glint and the big gem's ding. Rolled on the
## manager's own dice, with Prospector's extra gem (prospector() calls it). True when it struck.
const VEIN_GEMS := 5
const VEIN_OUT := Vector2(1.6, 3.2)
const VEIN_UP := 6.0
const VEIN_COLOUR := Color(1.0, 0.85, 0.35)
## Veins struck this run (tests, the capture).
var veins := 0


func vein(def: EnemyDef, at: Vector3, xp_scale: float, chance: float = -1.0) -> bool:
	var c := chance
	if c < 0.0:
		c = Run.player_sheet.get_stat("vein_chance", 0.0) if Run.player_sheet else 0.0
	if c <= 0.0 or _rng.randf() >= c:
		return false
	var k := base_gem_kind(def)
	var a0 := _rng.randf() * TAU
	for n in range(VEIN_GEMS):
		var i := spawn(k, at, float(GEM_VALUE[k]) * xp_scale)
		if i < 0:
			continue
		var a := a0 + TAU * float(n) / float(VEIN_GEMS) + _rng.randf_range(-0.3, 0.3)
		var out := _rng.randf_range(VEIN_OUT.x, VEIN_OUT.y)
		vel[i] = Vector3(cos(a) * out, VEIN_UP + _rng.randf_range(-0.8, 0.8), sin(a) * out)
	veins += 1
	var fx = game.get("fx") if game != null else null
	if fx != null and fx.has_method("burst"):
		fx.burst(at + Vector3(0, 0.5, 0), VEIN_COLOUR, 1.1)
	Audio.play("pk_gem_l", at)
	return true


## Mother Lode (pass 70, Lodestone's evolution): with the hero's `gem_sweep_every` above 0, every that many seconds every
## XP gem on the screen (lying, landing or hopping; never a coin or a vacuum, never one already on its way) sets off for
## him on the magnet arc (sweep_screen); the first sweep GEM_SWEEP_FIRST s after it is taken, a gold ring at his feet and
## the pull's sound when any came.
const GEM_SWEEP_R := 32.0
const GEM_SWEEP_FIRST := 1.0
const GEM_SWEEP_RING := 5.0
const GEM_SWEEP_COLOUR := Color(1.0, 0.78, 0.3, 0.6)
var _sweep_t := -1.0
## Sweeps made this run and how many gems the last one took (tests, the capture).
var gem_sweeps := 0
var gem_sweep_last := 0


func _tick_gem_sweep(delta: float, hero: Vector3) -> void:
	var every: float = Run.player_sheet.get_stat("gem_sweep_every", 0.0) if Run.player_sheet else 0.0
	if every <= 0.0:
		_sweep_t = -1.0
		return
	if _sweep_t < 0.0:
		_sweep_t = minf(GEM_SWEEP_FIRST, every)
	_sweep_t -= delta
	if _sweep_t > 0.0:
		return
	_sweep_t = every
	gem_sweeps += 1
	gem_sweep_last = sweep_screen(hero)
	if gem_sweep_last > 0:
		var tg = game.get("telegraphs") if game != null else null
		if tg != null:
			tg.flash_ring(hero, GEM_SWEEP_RING, GEM_SWEEP_COLOUR, 0.5)
		Audio.play("it_xp_pull", hero)


## Every XP gem on the screen (_on_screen; within GEM_SWEEP_R m of `center`) sets off for the hero on the magnet arc, as
## pull_xp does round a spot. How many set off.
func sweep_screen(center: Vector3) -> int:
	if _cap <= 0 or center == Vector3.INF:
		return 0
	var hero := _hero_at()
	if hero == Vector3.INF:
		hero = center
	var r2 := GEM_SWEEP_R * GEM_SWEEP_R
	var n := 0
	for i in _act.duplicate():
		if alive[i] == 1 and flying[i] == 0 and kind[i] <= KIND_GEM_L and phase[i] != PHASE_TOSS:
			var dx := pos[i].x - center.x
			var dz := pos[i].z - center.z
			if dx * dx + dz * dz < r2 and _on_screen(pos[i]):
				_start_trip(i, hero, true)
				n += 1
	var x0 := _cell_x(center.x - GEM_SWEEP_R)
	var x1 := _cell_x(center.x + GEM_SWEEP_R)
	var z0 := _cell_x(center.z - GEM_SWEEP_R)
	var z1 := _cell_x(center.z + GEM_SWEEP_R)
	for cz in range(z0, z1 + 1):
		for cx in range(x0, x1 + 1):
			var i := _g_head[cz * GRID_N + cx]
			while i >= 0:
				var nx := _g_next[i]
				if flying[i] == 0 and kind[i] <= KIND_GEM_L:
					var dx := pos[i].x - center.x
					var dz := pos[i].z - center.z
					if dx * dx + dz * dz < r2 and _on_screen(pos[i]):
						_start_trip(i, hero, true)
						n += 1
				i = nx
	return n


## The big pull (the Magnet Pulse, the Uber Magnet, the boss chest's opening, the Elite's vacuum gem, the arena's button):
## every pickup on the field (coins only with `coins_too`) goes up on the magnet arc and dives into the hero (pass 60,
## _start_trip with `arc`; the hop and the flight before), and with `chests_too` the chests slide to him.
## Pass 61: the moving ones (falling, tossed, held) set off at once; the ones lying on the sand are called from the grid,
## nearest first, by _vacuum_step (now and on the ticks after): the ones on the screen up the arc, at most FLIGHT_MAX on
## their way at once, the ones off it in their turn from just past the screen's edge or, past EDGE_MAX of those, taken
## unseen (_tick_vq).
func vacuum_all(coins_too: bool = false, chests_too: bool = false) -> void:
	# a manager that never entered the tree has no pools (tests): only the chests
	if _cap > 0:
		var hero := _hero_at()
		var moving := _act.duplicate()
		for i in moving:
			if alive[i] == 1 and flying[i] == 0 and (coins_too or kind[i] != KIND_COIN):
				_start_trip(i, hero, true)
		_vac_coins = coins_too or (_vac_on and _vac_coins)
		_vac_on = true
		_vac_k = 0
		_vac_t0 = _time
		var c := hero if hero != Vector3.INF else Vector3.ZERO
		_vac_cx = _cell_x(c.x)
		_vac_cz = _cell_x(c.z)
		_top = clampf(8.0 + _magnet() * 6.0, 12.0, 40.0)
		# nothing waits from an earlier pull: the reading starts at the clock's bucket (it is not read between pulls; it
		# is never moved while it reads, the review of pass 61)
		if _vq.is_empty():
			_vq_next = maxi(_vq_next, floori(_time / IDLE_BUCKET))
		_edge_table(hero)
		_vacuum_step(hero)
	if chests_too:
		# a boss kill: the chests come to the hero too, instead of the hero crossing the arena for them
		for c in chests:
			if is_instance_valid(c) and not c.opened:
				c.pulled = true
	Audio.play("pk_vacuum")


## The Magnet (pass 69, Garry: "Instead of a static increase in pull it will ... occasionally pull a bunch of EXP around the
## Player ... only EXP, not Chest or Power-up ... frequency of pulls ... decently frequent, but quite random, area should
## never be beyond what a large explosion produces"): with `xp_pull_radius` held, every XP_PULL_EVERY seconds (a random
## wait between the two, divided by 1 + `xp_pull_rate`) every EXP gem within that radius, XP_PULL_MAX_R at most, comes to
## the hero on the magnet arc (pull_xp); a faint purple ring at the reach shows it when any came. The waits are the
## manager's own dice (_rng), so the pulls never move the run's random sequence.
const XP_PULL_EVERY := Vector2(3.0, 8.0)
const XP_PULL_MAX_R := 8.5
const XP_PULL_COLOUR := Color(0.62, 0.48, 1.0, 0.55)
var _xp_pull_t := -1.0
## How many pulls went off this run and how many gems the last one took (tests, the capture).
var xp_pulls := 0
var xp_pull_last := 0


func _tick_xp_pulls(delta: float, hero: Vector3) -> void:
	var r := xp_pull_radius()
	if r <= 0.0:
		_xp_pull_t = -1.0
		return
	if _xp_pull_t < 0.0:
		_xp_pull_t = xp_pull_wait()
	_xp_pull_t -= delta
	if _xp_pull_t > 0.0:
		return
	_xp_pull_t = xp_pull_wait()
	xp_pulls += 1
	xp_pull_last = pull_xp(hero, r)
	if xp_pull_last > 0:
		var tg = game.get("telegraphs") if game != null else null
		if tg != null:
			tg.flash_ring(hero, r, XP_PULL_COLOUR, 0.45)
		Audio.play("it_xp_pull", hero)


## The Magnet's reach now: the `xp_pull_radius` the hero's sheet holds, never past XP_PULL_MAX_R (0 without the item).
func xp_pull_radius() -> float:
	if Run.player_sheet == null:
		return 0.0
	return clampf(Run.player_sheet.get_stat("xp_pull_radius", 0.0), 0.0, XP_PULL_MAX_R)


## The shortest and longest wait between two pulls at `rate` (`xp_pull_rate`: 0 at level 1, 1 at level 5, halving them).
static func xp_pull_span(rate: float) -> Vector2:
	return XP_PULL_EVERY / (1.0 + maxf(rate, 0.0))


## A wait before the next pull, at random within xp_pull_span for the sheet's rate.
func xp_pull_wait() -> float:
	var span := xp_pull_span(Run.player_sheet.get_stat("xp_pull_rate", 0.0) if Run.player_sheet else 0.0)
	return _rng.randf_range(span.x, span.y)


## Every EXP gem (never a coin or a vacuum) lying, landing or hopping within `r` m (flat) of `center` sets off for the hero
## on the magnet arc, the big pull's look (pass 60); one already on its way is left alone. How many set off.
func pull_xp(center: Vector3, r: float) -> int:
	if _cap <= 0 or r <= 0.0:
		return 0
	var hero := _hero_at()
	if hero == Vector3.INF:
		hero = center
	var r2 := r * r
	var n := 0
	for i in _act.duplicate():
		if alive[i] == 1 and flying[i] == 0 and kind[i] <= KIND_GEM_L and phase[i] != PHASE_TOSS:
			var dx := pos[i].x - center.x
			var dz := pos[i].z - center.z
			if dx * dx + dz * dz < r2:
				_start_trip(i, hero, true)
				n += 1
	var x0 := _cell_x(center.x - r)
	var x1 := _cell_x(center.x + r)
	var z0 := _cell_x(center.z - r)
	var z1 := _cell_x(center.z + r)
	for cz in range(z0, z1 + 1):
		for cx in range(x0, x1 + 1):
			var i := _g_head[cz * GRID_N + cx]
			while i >= 0:
				var nx := _g_next[i]
				if flying[i] == 0 and kind[i] <= KIND_GEM_L:
					var dx := pos[i].x - center.x
					var dz := pos[i].z - center.z
					if dx * dx + dz * dz < r2:
						_start_trip(i, hero, true)
						n += 1
				i = nx
	return n


func add_attractor(p: Vector3, r: float) -> void:
	_attractors.append({"pos": p, "r": r})


## The hero's feet, or Vector3.INF with no hero.
func _hero_at() -> Vector3:
	if game == null or game.get("player") == null:
		return Vector3.INF
	var p: Node3D = game.player
	return p.global_position


## A pickup the hero has called sets off. The walk-up pull (his magnet's reach, his feet on a held coin): a hop out,
## straight away from him (any way when he stands on it), then the flight. A big pull (`arc`, pass 60: vacuum_all, a
## turret's attractor): the magnet arc, ARC_WAIT its turn in the ripple (ARC_WAIT_* by its distance from him), then thrown
## ARC_HEIGHT_* over where it lies with a little drift (ARC_DRIFT_*) along a line turned up to ARC_DRIFT_FAN off straight
## away, a hang at the apex and the dive. One already on its way is left alone, so a magnet, a turret or a vacuum never
## restarts a trip (a gem waiting its turn counts as on its way). The arc's dice are the manager's own (_rng), like the
## idle looks', so a pull never moves the run's shared random sequence.
func _start_trip(i: int, hero: Vector3, arc: bool = false, late: float = 0.0) -> void:
	if flying[i] == 1:
		return
	# no longer waiting for a big pull's turn off the screen (pass 61)
	vac_q[i] = 0
	# called mid idle hop (pass 56): it sets off from the height it was drawn at, never dropping back to the sand first
	if hop_t[i] >= 0.0:
		pos[i].y += hop_extra_y(hop_t[i])
	_end_idle(i)
	# off the sand and into the active list (pass 61)
	_g_del(i)
	_act_add(i)
	flying[i] = 1
	_flying_n += 1
	phase_t[i] = 0.0
	var away := Vector3.ZERO
	if hero != Vector3.INF:
		away = Vector3(pos[i].x - hero.x, 0.0, pos[i].z - hero.z)
	var d := away.length()
	if d < 0.02:
		var a := randf() * TAU
		away = Vector3(cos(a), 0.0, sin(a))
	arced[i] = 1 if arc else 0
	arc_spin[i] = 0.0
	if arc:
		phase[i] = PHASE_ARC_WAIT
		# (pass 61: less the ticks a big pull's walk took to reach it, so the ripple keeps its timing)
		arc_delay[i] = maxf(minf(ARC_WAIT_PER_M * d, ARC_WAIT_MAX) + _rng.randf() * ARC_WAIT_JITTER - late, 0.0)
		arc_hang[i] = _rng.randf_range(ARC_HANG_MIN, ARC_HANG_MAX)
		arc_apex[i] = -1.0
		# thrown up to its apex (v0 = sqrt(2 g h)) and a little outward along a line turned off straight away, so the
		# dives fan out; the flight's bend goes off that line too
		var h: float = ARC_HEIGHT_MIN + _rng.randf() * ARC_HEIGHT_RANGE + ARC_HEIGHT_PER_M * d
		arc_v0[i] = sqrt(2.0 * ARC_GRAV * h)
		arc_drift[i] = _rng.randf_range(ARC_DRIFT_MIN, ARC_DRIFT_MAX)
		hop_dir[i] = away.normalized().rotated(Vector3.UP, _rng.randf_range(-ARC_DRIFT_FAN, ARC_DRIFT_FAN))
		# until its turn it goes on settling where it lies (vel as it was)
		return
	phase[i] = PHASE_HOP
	hop_dir[i] = away.normalized()
	vel[i] = hop_dir[i] * HOP_OUT + Vector3.UP * HOP_UP


## How charged pickup `i` looks (pass 60, the gem shader's INSTANCE_CUSTOM.x): 1 on the magnet arc's rise and dive,
## fading in over its wait (full by the launch, at once for a wait under CHARGE_RISE); 0 lying on the sand and on the
## walk-up hop and its flight. A coin on the arc is charged too, but its own shader (coin.gdshader) shows none.
func charge_of(i: int) -> float:
	if flying[i] == 0 or arced[i] == 0:
		return 0.0
	if phase[i] == PHASE_ARC_WAIT:
		return clampf(phase_t[i] / maxf(arc_delay[i], CHARGE_RISE), 0.0, 1.0)
	return 1.0


## One tick of a pickup on its trip: the hop (out and up, falling back under gravity), or the magnet arc (pass 60: the
## wait, settling where it lies; the rise under ARC_GRAV with its drift; the hang at the apex), then the flight to his
## chest, its speed climbing at FLY_ACCEL to `top`, bending off sideways as it sets out; taken when it is COLLECT_R from
## his chest.
func _travel(i: int, chest: Vector3, top: float, delta: float, map) -> void:
	phase_t[i] += delta
	if phase[i] == PHASE_ARC_WAIT:
		if phase_t[i] >= arc_delay[i]:
			# its turn in the ripple: thrown up
			phase[i] = PHASE_ARC_RISE
			phase_t[i] = 0.0
			vel[i] = hop_dir[i] * arc_drift[i] + Vector3.UP * arc_v0[i]
			return
		# until then it settles where it lies, as a resting one does (a drop still falling when the pull came)
		vel[i].y -= HOP_GRAV * delta
		pos[i] += vel[i] * delta
		var rest: float = (map.height_at(pos[i].x, pos[i].z) if map else 0.0) + _rest_k[kind[i]]
		if pos[i].y < rest:
			pos[i].y = rest
			if vel[i].y <= 0.0:
				vel[i] = Vector3.ZERO
		return
	if phase[i] == PHASE_ARC_RISE:
		arc_spin[i] += ARC_SPIN * delta
		if arc_apex[i] < 0.0:
			vel[i].y -= ARC_GRAV * delta
			pos[i] += vel[i] * delta
			if vel[i].y <= 0.0:
				# the apex: it hangs a beat, then dives
				arc_apex[i] = phase_t[i]
				vel[i] = Vector3.ZERO
		elif phase_t[i] - arc_apex[i] >= arc_hang[i]:
			phase[i] = PHASE_FLY
			phase_t[i] = 0.0
		return
	if phase[i] == PHASE_HOP:
		vel[i].y -= HOP_GRAV * delta
		pos[i] += vel[i] * delta
		var ground: float = (map.height_at(pos[i].x, pos[i].z) if map else 0.0) + _rest_k[kind[i]]
		if pos[i].y < ground:
			pos[i].y = ground
		if phase_t[i] >= HOP_TIME:
			# the top of the hop: it hangs there a beat while its speed builds
			phase[i] = PHASE_FLY
			phase_t[i] = 0.0
			vel[i] = Vector3.ZERO
		return
	if arced[i] == 1:
		# the dive keeps some of the rise's extra spin (pass 60)
		arc_spin[i] += ARC_SPIN * 0.5 * delta
	var to := chest - pos[i]
	var l := to.length()
	if l < COLLECT_R:
		if _down:
			_drop_here(i, map)
		else:
			_collect(i)
		return
	var dir := to / l
	# every other one bends the other way; the bend fades as it gets going and as it closes in, so it always arrives
	var bend: float = FLY_CURVE * clampf(1.0 - phase_t[i] / FLY_CURVE_TIME, 0.0, 1.0) * clampf(l / 2.0, 0.0, 1.0)
	if bend > 0.0:
		var side := Vector3(-hop_dir[i].z, 0.0, hop_dir[i].x) * (1.0 if (i & 1) == 0 else -1.0)
		dir = (dir + side * bend).normalized()
	var sp: float = minf(FLY_ACCEL * phase_t[i], top)
	pos[i] += dir * minf(sp * delta, l)
	if pos[i].distance_squared_to(chest) < COLLECT_R * COLLECT_R:
		if _down:
			_drop_here(i, map)
		else:
			_collect(i)


## The hero's magnet reach as the pull reads it (the stat, 1.6 times for an auto-magnet hero); 1.5 without a run sheet.
func _magnet() -> float:
	var m := 1.5
	if Run.player_sheet:
		m = Run.player_sheet.get_stat("magnet", 1.5)
	var p = game.get("player") if game != null else null
	if p != null and p.get("character") != null and p.character.specials.has("auto_magnet"):
		m *= 1.6
	return m


## How many coins lie on the ground (pass 54, the coins' own cap).
func count_coins() -> int:
	return coins


## Pickup `i` is gone (taken). Pass 61: out of the grid and the active list, and its kind's last instance moves into
## the place it leaves (written there at once: its transform and custom data), so the MultiMesh stays packed.
func _free(i: int) -> void:
	if alive[i] == 0:
		return
	alive[i] = 0
	if flying[i] == 1:
		_flying_n -= 1
	if edge_f[i] == 1:
		edge_f[i] = 0
		_edge_n -= 1
	vac_q[i] = 0
	flying[i] = 0
	phase[i] = PHASE_GROUND
	_end_idle(i)
	_g_del(i)
	_act_del(i)
	var k := kind[i]
	var n := inst[i]
	if n >= 0:
		var last := _inst_n[k] - 1
		if n != last:
			var j := _islot[k * _icap + last]
			_islot[k * _icap + n] = j
			inst[j] = n
			_ich[k * _icap + n] = -1.0
			_write(j, record_draws, true)
		_islot[k * _icap + last] = -1
		_inst_n[k] = last
		inst[i] = -1
	free_list.append(i)
	count -= 1
	if kind[i] == KIND_COIN:
		coins -= 1
		coin_from.erase(i)


## Everything on the field goes at once (pass 61: in one sweep of the pools, no instance written; the next draw shows
## none).
func clear_all() -> void:
	if _cap == 0:
		return
	for i in range(_cap):
		if alive[i] == 1:
			_end_idle(i)
		alive[i] = 0
		flying[i] = 0
		phase[i] = PHASE_GROUND
		inst[i] = -1
		act_at[i] = -1
		g_cell[i] = -1
		_g_next[i] = -1
		_g_prev[i] = -1
		_dirty_f[i] = 0
		vac_q[i] = 0
		edge_f[i] = 0
		_vq_b[i] = -1
	free_list.clear()
	for i in range(_cap - 1, -1, -1):
		free_list.append(i)
	_inst_n.fill(0)
	_islot.fill(-1)
	_ich.fill(-1.0)
	_g_head.fill(-1)
	_act.clear()
	_dirty.clear()
	_wheel.clear()
	_glinting.clear()
	_glints = 0
	_flying_n = 0
	_edge_n = 0
	_vq.clear()
	_vac_on = false
	count = 0
	coins = 0
	coin_from.clear()


## true while the hero is down (pass 60): see _physics_process
var _down := false


func _physics_process(delta: float) -> void:
	_time += delta
	if game == null or game.player == null:
		return
	var t0 := Time.get_ticks_usec()
	var player: Node3D = game.player
	var hero: Vector3 = player.global_position
	# pass 60 (death wins): while the hero is down nothing is collected and no pull starts; a gem that reaches him
	# lies down where it is and the pull takes it again once he is up
	_down = bool(player.get("dead"))
	var chest: Vector3 = hero + Vector3(0, CHEST, 0)
	var magnet: float = Run.player_sheet.get_stat("magnet", 1.5)
	if player.character and player.character.specials.has("auto_magnet"):
		magnet *= 1.6
	var m2 := magnet * magnet
	# the flight's top speed: the magnet's, never under 12 m/s so a slow magnet still lands them in a beat
	var top: float = clampf(8.0 + magnet * 6.0, 12.0, 40.0)
	_top = top
	var map = game.map
	# pass 61: only the active ones (falling, on their way, tossed, held, hopping, glinting); a pickup lying still is
	# reached through the grid below. A copy of the list: a pickup may leave it, or a pull add others, as it goes
	var moving := _act.duplicate()
	for i in moving:
		if alive[i] == 0 or act_at[i] < 0:
			continue
		if flying[i] == 1:
			_travel(i, chest, top, delta, map)
			continue
		# a coin knocked out of the hero (Loose Change, pass 48) on its way down
		if phase[i] == PHASE_TOSS:
			_toss_tick(i, delta, map)
			continue
		# lying on the sand, looked at only while its idle hop or glint runs (pass 56, pass 61)
		if g_cell[i] >= 0:
			_idle(i, delta)
			continue
		# settle (pass 56: a big gem a little higher, rest_of)
		vel[i].y -= HOP_GRAV * delta
		pos[i] += vel[i] * delta
		var ground: float = (map.height_at(pos[i].x, pos[i].z) if map else 0.0) + _rest_k[kind[i]]
		var landed := false
		if pos[i].y < ground:
			pos[i].y = ground
			# down: it lies there (pass 56: one still on its way up, below a big gem's higher rest, keeps its pop)
			if vel[i].y <= 0.0:
				vel[i] = Vector3.ZERO
				landed = true
		var dx := hero.x - pos[i].x
		var dz := hero.z - pos[i].z
		var d2 := dx * dx + dz * dz
		# ... and a moment after it lands: no magnet, no pull, only his own feet (pass 48)
		if hold[i] > 0.0:
			hold[i] -= delta
			if d2 < TOSS_TOUCH * TOSS_TOUCH:
				hold[i] = 0.0
				_start_trip(i, hero)
			continue
		if d2 < m2:
			if not _down:
				_start_trip(i, hero)
				continue
		elif not _down:
			var pulled := false
			for a in _attractors:
				var da: Vector3 = a["pos"] - pos[i]
				da.y = 0.0
				if da.length() < a["r"]:
					# a turret's pull is a big one (pass 60): the magnet arc
					_start_trip(i, hero, true)
					pulled = true
					break
			if pulled:
				continue
		if landed:
			# down for good (pass 61): into the grid, out of the tick
			_rest(i)
	if not _down:
		# the Magnet's pulls (pass 69): now and then every EXP gem round him comes on the magnet arc
		_tick_xp_pulls(delta, hero)
		# Mother Lode's sweeps (pass 70): now and then every EXP gem on the screen
		_tick_gem_sweep(delta, hero)
		# the Magnet power-up (pass 95, lane WORLD): for its seconds every gem and coin within its reach comes
		_tick_magnet(delta, hero)
		# the ones lying on the sand within his magnet's reach, and within a turret's pull (pass 61: the grid's cells)
		_pull_round(hero, magnet, hero, false)
		for a in _attractors:
			_pull_round(a["pos"], float(a["r"]), hero, true)
		# a big pull under way calls the next ones, and the ones off the screen whose turn has come
		if _vac_on:
			_vacuum_step(hero)
		if not _vq.is_empty():
			_tick_vq(hero)
		if _credit_xp > 0.0:
			Run.add_xp(_credit_xp)
			_credit_xp = 0.0
	# the idle turns that are due
	_tick_wheel(delta)
	_attractors.clear()
	_check_chests(player, delta)
	_check_specials(player, delta)
	_ticks += 1
	Perf.add("pickups", t0)


## One tick of gem `i` lying on the sand (pass 56): its idle hop's clock (the first one HOP_EXTRA_MIN..HOP_EXTRA_MAX s
## after it lands, then as long again after each; a turn on the screen inside HOP_EXTRA_GAP of the last hop there passes
## and waits a full wait again), and a medium or large gem's glint (its own GLINT_EVERY wait, then a glint if the field's
## GLINT_GAP and GLINT_MAX allow and it can be seen, _on_screen; a turn passed up waits a full wait again).
## Pass 61: a hop whose turn comes off the screen passes too (nobody sees it, and a gem lying still costs nothing), and
## the gem is ticked only while its hop or glint runs (the active list); otherwise its next turn waits on the wheel.
func _idle(i: int, delta: float) -> void:
	if hop_t[i] >= 0.0:
		hop_t[i] += delta
		if hop_t[i] >= HOP_EXTRA_TIME + HOP_EXTRA_SQUASH_TIME:
			hop_t[i] = -1.0
			hop_next[i] = _time + _rng.randf_range(HOP_EXTRA_MIN, HOP_EXTRA_MAX)
	elif hop_next[i] < 0.0:
		hop_next[i] = _time + _rng.randf_range(HOP_EXTRA_MIN, HOP_EXTRA_MAX)
	elif _time >= hop_next[i]:
		# on the screen, one hop every HOP_EXTRA_GAP s at most across the field (the fix round of pass 56); off it, none
		# (pass 61)
		if not _in_view(pos[i]) or _time - _hop_last < HOP_EXTRA_GAP:
			hop_next[i] = _time + _rng.randf_range(HOP_EXTRA_MIN, HOP_EXTRA_MAX)
		else:
			hop_t[i] = 0.0
			_hop_last = _time
	var k := kind[i]
	var glints := k == KIND_GEM_M or k == KIND_GEM_L
	if glints:
		if glint_t[i] >= 0.0:
			glint_t[i] += delta
			if glint_t[i] >= GLINT_TIME:
				_end_glint(i)
		elif glint_next[i] < 0.0:
			glint_next[i] = _time + glint_wait(k)
		elif _time >= glint_next[i]:
			glint_next[i] = _time + glint_wait(k)
			if _time - _glint_last >= GLINT_GAP and _glints < GLINT_MAX and _on_screen(pos[i]):
				start_glint(i)
	# its next call: every tick while a hop or a glint runs (the active list), else at the sooner of the two (the wheel)
	if hop_t[i] >= 0.0 or glint_t[i] >= 0.0:
		idle_due[i] = 0.0
		_act_add(i)
	else:
		idle_due[i] = minf(hop_next[i], glint_next[i]) if glints else hop_next[i]
		_act_del(i)
		_wheel_add(i, idle_due[i])


## Seconds a gem of kind `k` waits for its next glint (GLINT_EVERY); 0 for a kind that never glints.
func glint_wait(k: int) -> float:
	if k < 0 or k >= GLINT_EVERY.size():
		return 0.0
	var w: Vector2 = GLINT_EVERY[k]
	return _rng.randf_range(w.x, w.y)


## Gem `i` glints now (pass 56): the flare starts and counts against the field's GLINT_GAP and GLINT_MAX. One already
## glinting is left alone.
func start_glint(i: int) -> void:
	if glint_t[i] >= 0.0:
		return
	glint_t[i] = 0.0
	_glints += 1
	_glint_last = _time
	idle_due[i] = 0.0
	# drawn every frame it lasts, and ticked (pass 61)
	_glinting.append(i)
	if alive[i] == 1 and g_cell[i] >= 0:
		_act_add(i)


## Glints showing now (tests).
func glint_count() -> int:
	return _glints


func _end_glint(i: int) -> void:
	if glint_t[i] < 0.0:
		return
	glint_t[i] = -1.0
	_glints -= 1
	var at := _glinting.find(i)
	if at >= 0:
		_glinting.remove_at(at)


## A pickup leaves the sand (taken, called by the magnet): its idle hop and glint stop and their clocks wait for it to
## land again (pass 56).
func _end_idle(i: int) -> void:
	if i >= hop_t.size():
		return
	hop_t[i] = -1.0
	hop_next[i] = -1.0
	glint_next[i] = -1.0
	idle_due[i] = -1.0
	_end_glint(i)


## The run's camera rig (Game.camera) while it is in the tree; null without one (tests, tools).
func _rig() -> CameraRig:
	var rig = game.get("camera") if game != null else null
	if rig is CameraRig and (rig as CameraRig).is_inside_tree():
		return rig
	return null


## Whether `p` shows anywhere on the screen (the fix round of pass 56: the camera rig's own on_screen; the idle hops'
## gap reads it). True without a camera (tests, tools).
func _in_view(p: Vector3) -> bool:
	var rig := _rig()
	return rig == null or rig.on_screen(p)


## Whether a glint at `p` would be seen (pass 56; the fix round, the lead: a glint under the HUD's strip spent the
## allowance unseen): on the screen and lower than the strip, HUD.band_h design pixels scaled to the canvas's width the
## way PlayerInput's thumb zone reads it. True without a camera (tests, tools).
func _on_screen(p: Vector3) -> bool:
	var rig := _rig()
	if rig == null:
		return true
	if not rig.on_screen(p):
		return false
	var cam: Camera3D = rig.camera
	if cam == null:
		return true
	var vp := rig.get_viewport().get_visible_rect().size
	return cam.unproject_position(p).y > HUD.band_h * vp.x / 1080.0


## The float every resting pickup does (pass 54, unchanged in pass 56): `i`'s height over where it lies at `t` s.
static func float_y(i: int, t: float) -> float:
	return FLOAT_BASE + sin(t * 2.4 + phase_of(i) * 0.9) * BOB


## Slot `i`'s phase for the float and the idle spin (the review of pass 61): its seed (0..1, the shimmer's too) times
## TAU, the value the shaders get in INSTANCE_CUSTOM.y (a half float on the Compatibility renderer: exact enough for
## 0..1, where a raw slot past 2048 was not).
static func phase_of(i: int) -> float:
	return fmod(float(i) * 0.6180339887, 1.0) * TAU


## The idle hop's height over the float `t` s into it (pass 56): a parabola, 0 as it leaves and lands, HOP_EXTRA_HEIGHT
## halfway; 0 outside it and through the squash.
static func hop_extra_y(t: float) -> float:
	if t <= 0.0 or t >= HOP_EXTRA_TIME:
		return 0.0
	var f := t / HOP_EXTRA_TIME
	return 4.0 * HOP_EXTRA_HEIGHT * f * (1.0 - f)


## How much further the gem has turned `t` s into its idle hop (pass 56): HOP_EXTRA_SPIN by the landing, fastest at the
## top; 0 before and after (the same pose: a multiple of the gem's quarter turn).
static func hop_extra_spin(t: float) -> float:
	if t <= 0.0 or t >= HOP_EXTRA_TIME:
		return 0.0
	var f := t / HOP_EXTRA_TIME
	return HOP_EXTRA_SPIN * f * f * (3.0 - 2.0 * f)


## The gem's shape `t` s into its idle hop (pass 56): (across, tall) times its own. Stretched up to HOP_EXTRA_STRETCH
## tall on the fast way up (most a quarter of the way in), its own shape again by the top; squashed HOP_EXTRA_SQUASH_Y
## tall and HOP_EXTRA_SQUASH_XZ wide as it lands, easing back over HOP_EXTRA_SQUASH_TIME; (1, 1) outside the hop.
static func hop_extra_scale(t: float) -> Vector2:
	if t < 0.0:
		return Vector2.ONE
	if t < HOP_EXTRA_TIME:
		var f := t / HOP_EXTRA_TIME
		var s: float = (HOP_EXTRA_STRETCH - 1.0) * sin(TAU * f) if f < 0.5 else 0.0
		return Vector2(1.0 - s * 0.5, 1.0 + s)
	var g := (t - HOP_EXTRA_TIME) / HOP_EXTRA_SQUASH_TIME
	if g >= 1.0:
		return Vector2.ONE
	var e := (1.0 - g) * (1.0 - g)
	return Vector2(lerpf(1.0, HOP_EXTRA_SQUASH_XZ, e), lerpf(1.0, HOP_EXTRA_SQUASH_Y, e))


## A glint's brightness `t` s into it (pass 56): up fast, down a little slower, 0 outside GLINT_TIME.
static func glint_level(t: float) -> float:
	if t <= 0.0 or t >= GLINT_TIME:
		return 0.0
	var f := t / GLINT_TIME
	return sin(PI * pow(f, 0.7))


## Gems and coins are drawn once per shown frame, after a tick has moved them (pass 33.8).
func _process(_delta: float) -> void:
	# pass 77 (lane SIMRUN): the run sim's fast mode draws no gems or coins (the tick keeps every pickup's number)
	if game == null or _drawn == _ticks or Run.sim_mode:
		return
	_drawn = _ticks
	var t0 := Time.get_ticks_usec()
	_render()
	Perf.add("pickups.draw", t0)


## A pickup that reached a hero who is down lies down where it is (pass 60: death wins; no XP on the corpse).
func _drop_here(i: int, map) -> void:
	if flying[i] == 1:
		_flying_n -= 1
	if edge_f[i] == 1:
		edge_f[i] = 0
		_edge_n -= 1
	flying[i] = 0
	arced[i] = 0
	phase[i] = PHASE_GROUND
	phase_t[i] = 0.0
	vel[i] = Vector3.ZERO
	pos[i].y = (map.height_at(pos[i].x, pos[i].z) if map else 0.0) + _rest_k[kind[i]]
	# it lies in the grid (pass 61) until the pull takes it again
	_rest(i)


## Pickup `i` is the hero's. `quiet` (pass 61: one a big pull takes unseen, off the screen): no sound and no mote, a
## gem's XP is gathered and handed to the run once at the end of the tick (_credit_xp), and a vacuum gem starts nothing.
func _collect(i: int, quiet: bool = false) -> void:
	if quiet:
		match kind[i]:
			KIND_COIN:
				Run.add_gold(int(value[i]) * max(int(round(Run.stage_mult())), 1), str(coin_from.get(i, "coins")))
			KIND_VACUUM:
				# taken unseen while a pull runs: no second pull, no sound (only one the hero reaches starts a pull)
				pass
			_:
				_credit_xp += value[i]
		_free(i)
		return
	match kind[i]:
		KIND_COIN:
			Run.add_gold(int(value[i]) * max(int(round(Run.stage_mult())), 1), str(coin_from.get(i, "coins")))
			Audio.play("pk_coin")
		KIND_VACUUM:
			vacuum_all()
		KIND_GEM_L:
			Run.add_xp(value[i])
			Audio.play("pk_gem_l")
		KIND_GEM_M:
			Run.add_xp(value[i])
			Audio.play("pk_gem_m")
		_:
			Run.add_xp(value[i])
			Audio.play("pk_gem_s")
	_glint(i)
	_free(i)


## A glint where a pickup went in (pass 46): one mote in its colour, at most one every SPARK_GAP seconds.
func _glint(i: int) -> void:
	if _time - _spark_last < SPARK_GAP:
		return
	_spark_last = _time
	var fx = game.get("fx") if game != null else null
	if fx != null and fx.has_method("mote"):
		fx.mote(pos[i], Vector3(randf_range(-0.6, 0.6), 1.8, randf_range(-0.6, 0.6)), 0.3, 0.24, GLINT_COLOURS[clampi(kind[i], 0, GLINT_COLOURS.size() - 1)])


func spawn_chest(at: Vector3, boss: bool = false) -> void:
	var c := Chest.new()
	c.boss = boss
	add_child(c)
	c.global_position = at
	chests.append(c)


## `quiet`: no fanfare (the drop passives' cake slices and coin bags fall often).
func spawn_special(def: PickupDef, at: Vector3, quiet: bool = false) -> void:
	var p := Powerup.new()
	p.setup(def)
	add_child(p)
	p.global_position = at
	specials.append(p)
	if not quiet:
		Audio.play("pk_chest_open", at)


## Whether a special pickup of id `id` lies on the ground now, waiting to be taken (pass 67: Fadeaway's Timeout comes one
## at a time, Game._tick_timeout): one not taken and not fading out of the world.
func special_lying(id: String) -> bool:
	for p in specials:
		if is_instance_valid(p) and not p.taken and not p.is_queued_for_deletion() and p.def and p.def.id == id:
			return true
	return false


func _check_specials(player: Node3D, delta: float = 0.0) -> void:
	var keep: Array = []
	var magnet: float = Run.player_sheet.get_stat("magnet", 1.5)
	for p in specials:
		if not is_instance_valid(p) or p.taken:
			continue
		var d: Vector3 = player.global_position - p.global_position
		d.y = 0.0
		# a coin bag picks up like coins: inside the magnet's reach it flies to the hero
		if bool(p.def.params.get("magnet", false)) and d.length() < magnet * 1.6 and delta > 0.0:
			p.global_position += d.normalized() * minf(d.length(), (8.0 + magnet * 6.0) * delta)
		if d.length() < 1.25 and not _down:
			p.collect_anim()
			game.apply_pickup(p.def, p.global_position)
		else:
			# pass 60: a power-up waits while he is down (death wins: no Nuke, no pulse, no Berserk clock on the corpse)
			keep.append(p)
	specials = keep


func _check_chests(player: Node3D, delta: float = 0.0) -> void:
	var keep: Array = []
	for c in chests:
		if not is_instance_valid(c):
			continue
		var d: Vector3 = player.global_position - c.global_position
		d.y = 0.0
		if c.pulled and not c.opened and delta > 0.0 and d.length() > 0.5:
			# a pulled chest slides to the hero, gathering speed, and rises to his height so it never sinks into a slope
			c.pull_speed = minf(c.pull_speed + delta * 28.0, 20.0)
			c.global_position += d.normalized() * minf(c.pull_speed * delta, d.length())
			c.global_position.y = lerpf(c.global_position.y, player.global_position.y, clampf(delta * 6.0, 0.0, 1.0))
		if d.length() < 1.3 and not c.opened:
			c.opened = true
			game.open_chest(c.global_position, c.boss)
			c.open_anim()
		else:
			keep.append(c)
	chests = keep


## Warm-up (pass 54): one of every kind drawn at `at` (Vector3.INF stops it), so the see-through gem and coin materials
## compile in the spawn beam's pit, not at the first kill. Warmup calls it beside the creatures' and the shots'.
var _warm_at := Vector3.INF
## Tests (pass 56): _render keeps the transform it hands each pickup's MultiMesh in drawn_xf (by slot) while
## record_draws is on, because a MultiMesh gives nothing back in a headless run.
var record_draws := false
var drawn_xf: Array = []
var drawn_charge := PackedFloat32Array()   # pass 60: the charge handed the gem shader (charge_of), by slot


func warm_draw(at: Vector3) -> void:
	_warm_at = at
	_drawn = -1


## Pass 61: the shaders' clocks first (the float and the spin of everything lying still), then only the active pickups'
## instances and the ones that have just come to rest (_dirty); a pickup lying still is not written at all.
func _render() -> void:
	for m in _gem_mats:
		(m as ShaderMaterial).set_shader_parameter("t_now", fmod(_time, GEM_WRAP))
	coin_material().set_shader_parameter("t_now", fmod(_time, COIN_WRAP))
	var rec := record_draws
	if rec and drawn_xf.size() != _cap:
		drawn_xf.resize(_cap)
		drawn_charge.resize(_cap)
	for i in _act:
		if alive[i] == 1:
			_write(i, rec)
	for i in _dirty:
		_dirty_f[i] = 0
		if alive[i] == 1 and act_at[i] < 0 and inst[i] >= 0:
			_write(i, rec)
	_dirty.clear()
	var ng := 0
	for i in _glinting:
		if ng >= GLINT_MAX:
			break
		_glint_mm.set_instance_transform(ng, glint_xform(i, _shown_origin(i)))
		_glint_mm.set_instance_color(ng, glint_color(i))
		_glint_mm.set_instance_custom_data(ng, Color(0.3 + glint_t[i] * 1.8, 0.0, 0.0, 0.0))
		ng += 1
	var extra := 0
	if _warm_at != Vector3.INF:
		extra = 1
		for k in range(KINDS):
			if _inst_n[k] >= _icap:
				_grow_instances()
		for k in range(KINDS):
			var mm: MultiMesh = _mms[k]
			var n := _inst_n[k]
			mm.set_instance_transform(n, Transform3D(Basis(), _warm_at))
			# charged (pass 60), so the gem shader runs its charged sums under the beam too (the coin: no charge)
			mm.set_instance_custom_data(n, Color(1.0 if k != KIND_COIN else 0.0, 0.0, 0.0, 0.0))
			_ich[k * _icap + n] = 1.0
		# and one all but invisible glint, so its shader compiles under the spawn beam too (pass 56)
		_glint_mm.set_instance_transform(ng, Transform3D(Basis().scaled(Vector3.ONE * 0.2), _warm_at))
		_glint_mm.set_instance_color(ng, Color(1, 1, 1, 0.02))
		_glint_mm.set_instance_custom_data(ng, Color(0, 0, 0, 0))
		ng += 1
	for k in range(KINDS):
		var mm: MultiMesh = _mms[k]
		var want := _inst_n[k] + extra
		if mm.visible_instance_count != want:
			mm.visible_instance_count = want
	_glint_mm.visible_instance_count = ng


## Pickup `i`'s instance written from where it is (pass 61): its transform (_instance_xf: no float, no idle spin, the
## shaders add those) and, a gem, the charge in its custom data when it has changed (with `full`, the custom data
## whatever it held: a pickup moved into another's place).
func _write(i: int, rec: bool, full: bool = false) -> void:
	var k := kind[i]
	var n := inst[i]
	var mm: MultiMesh = _mms[k]
	var xf := _instance_xf(i)
	mm.set_instance_transform(n, xf)
	instance_writes += 1
	if rec and i < drawn_xf.size():
		drawn_xf[i] = xf
	if k == KIND_COIN:
		# the coin's custom data is its seed only (no charge): written when it is made, and again when it moves place
		if full:
			mm.set_instance_custom_data(n, Color(0.0, _seed[i], 0.0, 0.0))
			custom_writes += 1
		return
	var ch := charge_of(i)
	var c := k * _icap + n
	if full or ch != _ich[c]:
		mm.set_instance_custom_data(n, Color(ch, _seed[i], 0.0, 0.0))
		_ich[c] = ch
		custom_writes += 1
	if rec and i < drawn_charge.size():
		drawn_charge[i] = ch


## Pickup `i`'s instance transform (pass 61): where it is and what it does beyond the float and the idle spin, which the
## shaders add (gem.gdshader: B * spin(2 t + phase) and the float over it; coin.gdshader: B * spin(3 t + phase) * on edge
## and the float straight up in the world; phase_of). A gem: its idle hop's lift, extra spin and stretch (pass 56), the
## walk-up hop's pop (pass 46), the arc's extra spin and pop (pass 60). A coin: nothing lying still; knocked loose (pass
## 48), end over end along its throw with the shader's spin taken back out.
func _instance_xf(i: int) -> Transform3D:
	var k := kind[i]
	var b := Basis()
	var up := 0.0
	if k == KIND_COIN:
		if phase[i] == PHASE_TOSS:
			b = Basis(Vector3.UP, atan2(hop_dir[i].x, hop_dir[i].z)) * Basis(Vector3.RIGHT, phase_t[i] * TOSS_FLIP) * Basis(Vector3.UP, -(3.0 * _time + phase_of(i)))
	elif hop_t[i] >= 0.0:
		# the idle hop (pass 56): up and down over the float with a flick of spin, stretched as it leaves the sand and
		# squashed as it lands
		var ht: float = hop_t[i]
		var hs := hop_extra_scale(ht)
		b = Basis(Vector3.UP, hop_extra_spin(ht)).scaled(Vector3(hs.x, hs.y, hs.x))
		up = hop_extra_y(ht)
	if flying[i] == 1:
		var ph := phase[i]
		if ph == PHASE_HOP:
			# the pop: big as it leaves the sand, its own size again at the top of the hop
			var sc: float = lerpf(HOP_POP, 1.0, clampf(phase_t[i] / HOP_TIME, 0.0, 1.0))
			b = b.scaled(Vector3(sc, sc, sc))
		elif arced[i] == 1 and ph != PHASE_ARC_WAIT:
			# the magnet arc (pass 60): spinning faster from the launch, with the hop's pop as it leaves
			b = b.rotated(Vector3.UP, arc_spin[i])
			if ph == PHASE_ARC_RISE:
				var sc: float = lerpf(HOP_POP, 1.0, clampf(phase_t[i] / ARC_POP_TIME, 0.0, 1.0))
				b = b.scaled(Vector3(sc, sc, sc))
	return Transform3D(b, pos[i] + Vector3(0.0, up, 0.0))


## How pickup `i` shows on the screen now (pass 61; tests, and the glints' spot): its instance transform with what the
## shader adds at the run's clock, worked out here the way the shader does it.
func shown_xf(i: int) -> Transform3D:
	var xf := _instance_xf(i)
	var sy := maxf(xf.basis.y.length(), 0.0001)
	if kind[i] == KIND_COIN:
		# its spin on edge, and its float straight up in the world whatever its basis (the review of pass 61)
		var cb := xf.basis * Basis(Vector3.UP, 3.0 * _time + phase_of(i)) * Basis(Vector3.RIGHT, PI * 0.5)
		return Transform3D(cb, xf.origin + Vector3(0.0, float_y(i, _time), 0.0))
	var gb := xf.basis * Basis(Vector3.UP, 2.0 * _time + phase_of(i))
	return Transform3D(gb, xf.origin + xf.basis * Vector3(0.0, float_y(i, _time) / sy, 0.0))


## Where gem `i` shows (pass 61: the float and its idle hop over where it lies), for its glint.
func _shown_origin(i: int) -> Vector3:
	var y := pos[i].y + float_y(i, _time)
	if hop_t[i] >= 0.0:
		y += hop_extra_y(hop_t[i])
	return Vector3(pos[i].x, y, pos[i].z)


## Gem `i`'s glint on the gem drawn at `at` (pass 56): a star GLINT_SIZE times the gem's radius across at its brightest
## (a third of that as it flares up and dies), over its upper facets, each gem on its own side.
func glint_xform(i: int, at: Vector3) -> Transform3D:
	var r := gem_radius(kind[i])
	var lv := glint_level(glint_t[i])
	var a := float(i) * 2.39996
	var spot := at + Vector3(cos(a) * r * 0.35, r * GEM_TALL * 0.25, sin(a) * r * 0.35)
	var s: float = GLINT_SIZE * r * (0.35 + 0.65 * lv)
	return Transform3D(Basis().scaled(Vector3(s, s, s)), spot)


## Gem `i`'s glint colour now (pass 56): its own colour paled GLINT_PALE towards white, as bright (alpha) as the flare.
func glint_color(i: int) -> Color:
	var c: Color = (GLINT_COLOURS[clampi(kind[i], 0, GLINT_COLOURS.size() - 1)] as Color).lerp(Color.WHITE, GLINT_PALE)
	return Color(c.r, c.g, c.b, glint_level(glint_t[i]))


# ---------------------------------------------------------------- the Magnet power-up (pass 95, lane WORLD)

## Pass 95 (lane WORLD; Garry: "Magnet - should not pull everything. Should just affect a big area and work for a time
## (like 10s) maybe. For that time there should be a 2d magnet icon floating around the Player and the usual UI elements
## indicating that Player is 'magnetizing' things in that moment. The area of effect should be quite big, around 2.5
## times larger than the Magnet Epic Item. Making the player move around and such."): the Magnet pickup
## (content/pickups/magnet_pulse, effect "magnet", Game._apply_magnet_pickup) runs for its `duration` seconds on the
## buffs' clock, kept in Run.timed under the pickup's id (so the HUD's plate counts it down as Sprint's does, it wears off
## with the others' toast, and a second Magnet while one runs ADDS its seconds, magnet_start); every tick every gem and
## coin lying within magnet_r m (flat) of the hero sets off for him on the magnet arc (magnet_pull: never a vacuum gem, a
## chest or a power-up), so walking about gathers more; a faint ring at the reach every MAGNET_RING_EVERY s while any
## came; the 2D magnet (MagnetBuff) orbits him meanwhile with its field lines to the nearest ones (magnet_targets).
## magnet_r = the pickup's params.radius_mult (2.5) x the reach the Magnet card gives at its level 1 (its xp_pull_radius
## add, magnet_item_reach: 5 m today, so 12.5 m).
const MAGNET_RING_EVERY := 0.6
const MAGNET_COLOUR := Color(1.0, 0.71, 0.18, 0.5)
const MAGNET_ITEM_REACH_FALLBACK := 5.0
const MAGNET_SFX := "pk_vacuum"
var magnet_id := ""
var magnet_r := 0.0
## How many pickups the running magnet set off this run, and how many magnets were started (tests, the capture).
var magnet_pulls := 0
var magnet_starts := 0
var magnet_buff: MagnetBuff = null
var _magnet_ring_t := 0.0


## The reach the Magnet card gives at its level 1: its first level's `xp_pull_radius` add (the card may be retuned; this
## follows it), MAGNET_ITEM_REACH_FALLBACK without the card.
static func magnet_item_reach() -> float:
	var p: PassiveDef = Registry.passive("magnet")
	if p != null:
		for e in p.effects_at_level(1):
			if e is Effect and str(e.stat) == "xp_pull_radius" and str(e.op) == "add":
				return maxf(float(e.value), 0.0)
	return MAGNET_ITEM_REACH_FALLBACK


## The power-up's reach: its params.radius_mult (2.5) times the card's level-1 reach.
static func magnet_radius(def: PickupDef) -> float:
	var mult: float = float(def.params.get("radius_mult", 2.5)) if def != null else 2.5
	return maxf(mult, 0.0) * magnet_item_reach()


## The Magnet starts, or runs `seconds` longer when one runs already (the seconds are the power-up's, before the hero's
## buff_seconds, which Run.add_timed_effects applies; the extension keeps what is left). Returns the seconds it runs from
## now, as the HUD's plate shows them.
func magnet_start(def: PickupDef, seconds: float) -> float:
	if def == null or Run.player_sheet == null:
		return 0.0
	var left := Run.boost_left(def.id)
	var total := left + Run.buff_seconds(maxf(seconds, 0.0))
	var mult := maxf(Run.player_sheet.get_stat("buff_duration", 1.0), 0.0)
	Run.add_timed_effects(def.id, def.display_name, [], total / mult if mult > 0.0 else total)
	magnet_id = def.id
	magnet_r = magnet_radius(def)
	magnet_starts += 1
	_magnet_ring_t = 0.0
	var hero := _hero_at()
	_magnet_show()
	Audio.play(MAGNET_SFX, hero if hero != Vector3.INF else Vector3.ZERO)
	return total


## Whether the Magnet runs now (its seconds left on the buffs' clock, Run.boost_left).
func magnet_running() -> bool:
	return magnet_id != "" and Run.boost_left(magnet_id) > 0.0


func magnet_left() -> float:
	return Run.boost_left(magnet_id) if magnet_id != "" else 0.0


## One tick of the Magnet (the pickups' tick, while the hero is up): the pull round him, the ring, the icon.
func _tick_magnet(delta: float, hero: Vector3) -> void:
	if not magnet_running():
		if magnet_buff != null:
			if is_instance_valid(magnet_buff):
				magnet_buff.queue_free()
			magnet_buff = null
		return
	var n := magnet_pull(hero, magnet_r)
	magnet_pulls += n
	_magnet_ring_t -= delta
	if n > 0 and _magnet_ring_t <= 0.0:
		_magnet_ring_t = MAGNET_RING_EVERY
		var tg = game.get("telegraphs") if game != null else null
		if tg != null and tg.has_method("flash_ring"):
			tg.flash_ring(hero, magnet_r, MAGNET_COLOUR, 0.45)
	_magnet_show()
	if magnet_buff != null:
		magnet_buff.follow(hero, magnet_targets(hero, magnet_r, MagnetBuff.LINES), magnet_left(), delta)


## The 2D magnet comes (once; never in the run sim's fast mode, which draws nothing).
func _magnet_show() -> void:
	if magnet_buff != null or game == null or bool(Run.get("sim_mode")):
		return
	var def: PickupDef = Registry.pickup(magnet_id)
	if def == null:
		return
	var mb := MagnetBuff.new()
	mb.setup(def)
	mb.fx = game.get("fx")
	game.add_child(mb)
	magnet_buff = mb


## Every gem and coin lying within `r` m (flat) of `c` sets off for the hero on the magnet arc (the big pull's look);
## never a vacuum gem (its own pull would take the whole map). How many set off.
func magnet_pull(c: Vector3, r: float) -> int:
	if _cap <= 0 or r <= 0.0 or _g_head.is_empty():
		return 0
	var hero := _hero_at()
	if hero == Vector3.INF:
		hero = c
	var x0 := _cell_x(c.x - r)
	var x1 := _cell_x(c.x + r)
	var z0 := _cell_x(c.z - r)
	var z1 := _cell_x(c.z + r)
	var r2 := r * r
	var n := 0
	for cz in range(z0, z1 + 1):
		for cx in range(x0, x1 + 1):
			var i := _g_head[cz * GRID_N + cx]
			while i >= 0:
				var nx := _g_next[i]
				if kind[i] != KIND_VACUUM:
					var dx := pos[i].x - c.x
					var dz := pos[i].z - c.z
					if dx * dx + dz * dz < r2:
						_start_trip(i, hero, true)
						n += 1
				i = nx
	return n


## Up to `n` spots the magnet's field lines point at, nearest first: the gems and coins on their way to the hero on the
## arc, then the ones lying past the reach `r` but within MAGNET_LOOK x r of `c` (the next to come as he walks).
const MAGNET_LOOK := 1.6
func magnet_targets(c: Vector3, r: float, n: int) -> PackedVector3Array:
	var best: Array = []
	if _cap > 0:
		for i in _act:
			if alive[i] == 1 and flying[i] == 1 and arced[i] == 1 and kind[i] != KIND_VACUUM:
				_magnet_consider(best, pos[i], Vector2(pos[i].x - c.x, pos[i].z - c.z).length_squared(), n)
		if best.size() < n and not _g_head.is_empty():
			var look := r * MAGNET_LOOK
			var x0 := _cell_x(c.x - look)
			var x1 := _cell_x(c.x + look)
			var z0 := _cell_x(c.z - look)
			var z1 := _cell_x(c.z + look)
			for cz in range(z0, z1 + 1):
				for cx in range(x0, x1 + 1):
					var i := _g_head[cz * GRID_N + cx]
					while i >= 0:
						if kind[i] != KIND_VACUUM:
							var d2 := Vector2(pos[i].x - c.x, pos[i].z - c.z).length_squared()
							if d2 < look * look:
								_magnet_consider(best, pos[i], d2, n)
						i = _g_next[i]
	var out := PackedVector3Array()
	for b in best:
		out.append(b[0])
	return out


## Keeps `best` (pairs [pos, d2], nearest first) to `n` entries.
static func _magnet_consider(best: Array, p: Vector3, d2: float, n: int) -> void:
	var k := 0
	while k < best.size() and float(best[k][1]) <= d2:
		k += 1
	if k >= n:
		return
	best.insert(k, [p, d2])
	if best.size() > n:
		best.resize(n)
