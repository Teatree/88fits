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
## then"): every gem and the vacuum are a faceted octahedron (octahedron_mesh), the gems 5 % bigger on the screen
## (GEM_GROW, GEM_LOOK) and the bigger ones resting a little higher (rest_of), a gem lying on the sand hops now and then
## (HOP_EXTRA_*, _idle) and a medium or large one glints (GLINT_*, core/shaders/gem_glint.gdshader).
class_name PickupManager
extends Node3D

const MAX := 600
const KIND_GEM_S := 0
const KIND_GEM_M := 1
const KIND_GEM_L := 2
const KIND_COIN := 3
const KIND_VACUUM := 4
const MERGE_AT := 300
## The merge (pass 54): only resting gems more than the magnet's reach + MERGE_CLEAR m from the hero (flat) fuse, the oldest
## first, each with every other within MERGE_REACH of it (MERGE_CLUSTER at most) into one large gem at their centroid worth
## their sum, which pops up at MERGE_POP m/s with a glint. A merge on the crowded path waits MERGE_GAP s after the last
## one (a pool too full to merge would scan every spawn).
const MERGE_CLEAR := 4.0
const MERGE_REACH := 6.0
const MERGE_CLUSTER := 40
const MERGE_POP := 2.0
const MERGE_GAP := 0.25
## Coins have their own cap (pass 54): past it, far coins fuse the same way into one coin worth their sum, so a sea of
## coins never takes the gems' slots.
const COIN_CAP := 150
## The meshes (pass 54: gems half their old size, coins three quarters): a gem's radius by kind (small, medium, large),
## the vacuum's, the coin's radius and thickness. Pass 56 (Garry: "make them just 5% bigger than they are now"): the
## three gems GEM_GROW times pass 54's 0.11, 0.16 and 0.225 m; the vacuum and the coin as they were.
const GEM_GROW := 1.05
const GEM_R := [0.11 * GEM_GROW, 0.16 * GEM_GROW, 0.225 * GEM_GROW]
## GEM_R and VACUUM_R are sizes as pass 54's wedge (a PrismMesh 2 r wide, 2.4 r tall, 2 r deep) measured them. The
## octahedron that replaced it (pass 56) keeps the wedge's proportions, GEM_TALL times its own radius from tip to tip and
## twice it across, but is drawn GEM_LOOK times as large (gem_radius): an octahedron as wide and tall as the wedge covers
## only 37 % of the screen the wedge covered from the run's camera (46 degrees down, spinning; pass56_pk_test projects
## both), so at the wedge's size the gems looked a third smaller, not 5 % bigger. At GEM_LOOK it covers what the wedge
## covered, and GEM_GROW makes it 5 % bigger than that.
const GEM_TALL := 2.4
const GEM_LOOK := 1.64
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
const PAINTING_STENCIL := 1
## each kind's colour (gem small, medium, large, coin, vacuum): the mesh and the glint when it is taken
const COLOURS := [Color(0.62, 0.48, 1.0), Color(0.45, 0.85, 1.0), Color(1.0, 0.55, 0.85), Color(1.0, 0.72, 0.25), Color(1.0, 1.0, 1.0)]
## The trip in (pass 46). 0 on the ground (or still falling from the kill), 1 the hop out, 2 the flight in.
const PHASE_GROUND := 0
const PHASE_HOP := 1
const PHASE_FLY := 2
## A coin knocked out of the hero (pass 48, Loose Change) on its arc to where it lands (toss_coin); on the ground after.
const PHASE_TOSS := 3
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
const REST := 0.22          # how high a gem rests over the sand (0.35 before pass 54 halved the gems)
const BOB := 0.09           # how far it bobs (0.13 before pass 54)
const SPARK_GAP := 0.04     # at most one glint this often (a vacuum takes hundreds at once)
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
var coins := 0                 # coins on the ground (pass 54: they have their own cap)
var _merging := false          # inside a merge: its own spawns never start another
var _merge_last := -INF        # when the crowded path last tried a merge
var _full_warned := false      # the pool ran out once this run (a warning, once)
## Pass 56: the idle hops' and glints' own dice, so these looks never move the run's shared random sequence.
var _rng := RandomNumberGenerator.new()
var _glint_mm: MultiMesh        # the glints' four-point stars (GLINT_*)
var _glints := 0                # glints showing now
var _glint_last := -INF         # when the last one started
var _rest_k := PackedFloat32Array()   # rest_of by kind, read every tick


func _ready() -> void:
	pos.resize(MAX); kind.resize(MAX); value.resize(MAX); vel.resize(MAX); flying.resize(MAX); alive.resize(MAX); born.resize(MAX)
	phase.resize(MAX); phase_t.resize(MAX); hop_dir.resize(MAX); hold.resize(MAX)
	# (packed arrays are values: each is sized where it lives)
	hop_next.resize(MAX); hop_t.resize(MAX); glint_next.resize(MAX); glint_t.resize(MAX); idle_due.resize(MAX)
	hop_next.fill(-1.0); hop_t.fill(-1.0); glint_next.fill(-1.0); glint_t.fill(-1.0); idle_due.fill(-1.0)
	for i in range(MAX - 1, -1, -1):
		free_list.append(i)
	_mms.append(_make_mm(_gem_mesh(gem_radius(KIND_GEM_S)), COLOURS[KIND_GEM_S]))
	_mms.append(_make_mm(_gem_mesh(gem_radius(KIND_GEM_M)), COLOURS[KIND_GEM_M]))
	_mms.append(_make_mm(_gem_mesh(gem_radius(KIND_GEM_L)), COLOURS[KIND_GEM_L]))
	_mms.append(_make_mm(_coin_mesh(), COLOURS[KIND_COIN], coin_material()))
	_mms.append(_make_mm(_gem_mesh(gem_radius(KIND_VACUUM)), COLOURS[KIND_VACUUM]))
	_glint_mm = _make_glint_mm()
	for k in range(_mms.size()):
		_rest_k.append(rest_of(k))
	_rng.randomize()


func _gem_mesh(r: float) -> Mesh:
	return octahedron_mesh(r)


## The radius of kind `k`'s octahedron as drawn (pass 56): its size (GEM_R, VACUUM_R) times GEM_LOOK; 0 for a coin.
static func gem_radius(k: int) -> float:
	if k >= KIND_GEM_S and k <= KIND_GEM_L:
		return float(GEM_R[k]) * GEM_LOOK
	if k == KIND_VACUUM:
		return VACUUM_R * GEM_LOOK
	return 0.0


## How high a pickup of kind `k` rests over the sand (pass 56): REST, or for a gem whose lower tip would dip into the
## sand at the bottom of its float (float_y at its lowest), just high enough that the tip clears it by GEM_CLEAR.
static func rest_of(k: int) -> float:
	var half := gem_radius(k) * GEM_TALL * 0.5
	if half <= 0.0:
		return REST
	return maxf(REST, half + GEM_CLEAR - (0.06 - BOB))


## Pickup `i` starts no lower than where it rests over the sand (pass 56: a drop starts 0.4 m over the creature's feet,
## under a big gem's rest_of; it pops up from its rest instead of snapping up to it a frame later).
func _lift_to_rest(i: int) -> void:
	if _rest_k.size() <= kind[i]:
		return
	var map = game.get("map") if game != null else null
	var ground: float = (map.height_at(pos[i].x, pos[i].z) if map else 0.0) + _rest_k[kind[i]]
	if pos[i].y < ground:
		pos[i].y = ground


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
		_coin_mat.render_priority = PICKUP_PRIORITY
	return _coin_mat


## One kind's MultiMesh: lit gold-and-glow by `color`, or `mat` when it has a look of its own (the coin).
func _make_mm(mesh: Mesh, color: Color, mat: Material = null) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if mat == null:
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(color.r, color.g, color.b, 1.0)
		sm.emission_enabled = true
		sm.emission = color
		sm.emission_energy_multiplier = 0.6
		# see-through and depth-less (pass 54): drawn after every opaque thing, and only where no painting is (the
		# stencil, PAINTING_STENCIL), so a creature's, the hero's or a prop's painting covers a gem at its feet
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		sm.render_priority = PICKUP_PRIORITY
		sm.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
		sm.stencil_flags = BaseMaterial3D.STENCIL_FLAG_READ
		sm.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_NOT_EQUAL
		sm.stencil_reference = PAINTING_STENCIL
		mat = sm
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


func spawn(p_kind: int, at: Vector3, v: float) -> int:
	if free_list.is_empty() and not _merging:
		_merge(120)
		_merge(60, KIND_COIN)
	if free_list.is_empty():
		# nothing far enough to fuse: the drop is lost, as before; said once a run (pass 54)
		if not _full_warned:
			_full_warned = true
			push_warning("PickupManager: the pool of %d is full and nothing far from the hero can merge; a drop was lost" % MAX)
		return -1
	var i: int = free_list.pop_back()
	pos[i] = at + Vector3(randf_range(-0.4, 0.4), 0.4, randf_range(-0.4, 0.4))
	kind[i] = p_kind
	value[i] = v
	vel[i] = Vector3(randf_range(-1.5, 1.5), 3.0, randf_range(-1.5, 1.5))
	flying[i] = 0
	phase[i] = PHASE_GROUND
	phase_t[i] = 0.0
	hop_dir[i] = Vector3.ZERO
	hold[i] = 0.0
	# its idle hop and glint clocks start when it lands (pass 56, _idle)
	hop_next[i] = -1.0
	hop_t[i] = -1.0
	glint_next[i] = -1.0
	idle_due[i] = -1.0
	# a big gem rests higher than a drop starts (pass 56, rest_of): it pops up from there instead
	_lift_to_rest(i)
	alive[i] = 1
	born[i] = _time
	count += 1
	if p_kind == KIND_COIN:
		coins += 1
	if not _merging and _time - _merge_last >= MERGE_GAP:
		if count > MERGE_AT:
			_merge_last = _time
			_merge(100)
		elif coins > COIN_CAP:
			_merge_last = _time
			_merge(coins - COIN_CAP + 20, KIND_COIN)
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


func drop_from(def: EnemyDef, at: Vector3, xp_scale: float, is_elite: bool) -> void:
	var d := def.drops
	var luck: float = Run.player_sheet.get_stat("luck", 0.0)
	if randf() < float(d.get("small", 0.0)):
		spawn(KIND_GEM_S, at, 1.0 * xp_scale)
	if randf() < float(d.get("medium", 0.0)) + luck * 0.1:
		spawn(KIND_GEM_M, at, 5.0 * xp_scale)
	if randf() < float(d.get("large", 0.0)):
		spawn(KIND_GEM_L, at, 25.0 * xp_scale)
	if randf() < float(d.get("gold", 0.0)) * (1.0 + luck):
		spawn(KIND_COIN, at, float(1 + randi() % 3))
	if is_elite and randf() < 0.05 + luck * 0.1:
		spawn(KIND_VACUUM, at, 0.0)


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
	if chance <= 0.0 or randf() >= chance:
		return false
	var k := base_gem_kind(def)
	return spawn(k, at, float(GEM_VALUE[k]) * xp_scale) >= 0


func vacuum_all(coins_too: bool = false, chests_too: bool = false) -> void:
	# every one hops out and flies in like a magnet catch (pass 46); the pools are only read for a pickup that is there
	# (a manager that never entered the tree has `alive` and nothing else)
	var hero := Vector3.INF
	var asked := false
	for i in range(MAX):
		if alive[i] == 1 and (coins_too or kind[i] != KIND_COIN):
			if not asked:
				asked = true
				hero = _hero_at()
			_start_trip(i, hero)
	if chests_too:
		# a boss kill: the chests come to the hero too, instead of the hero crossing the arena for them
		for c in chests:
			if is_instance_valid(c) and not c.opened:
				c.pulled = true
	Audio.play("pk_vacuum")


func add_attractor(p: Vector3, r: float) -> void:
	_attractors.append({"pos": p, "r": r})


## The hero's feet, or Vector3.INF with no hero.
func _hero_at() -> Vector3:
	if game == null or game.get("player") == null:
		return Vector3.INF
	var p: Node3D = game.player
	return p.global_position


## A pickup the hero has called sets off: a hop out, straight away from him (any way when he stands on it). One already
## on its way is left alone, so a magnet, a turret or a vacuum never restarts a trip.
func _start_trip(i: int, hero: Vector3) -> void:
	if flying[i] == 1:
		return
	# called mid idle hop (pass 56): it sets off from the height it was drawn at, never dropping back to the sand first
	if hop_t.size() == MAX and hop_t[i] >= 0.0:
		pos[i].y += hop_extra_y(hop_t[i])
	_end_idle(i)
	flying[i] = 1
	phase[i] = PHASE_HOP
	phase_t[i] = 0.0
	var away := Vector3.ZERO
	if hero != Vector3.INF:
		away = Vector3(pos[i].x - hero.x, 0.0, pos[i].z - hero.z)
	if away.length_squared() < 0.0004:
		var a := randf() * TAU
		away = Vector3(cos(a), 0.0, sin(a))
	hop_dir[i] = away.normalized()
	vel[i] = hop_dir[i] * HOP_OUT + Vector3.UP * HOP_UP


## One tick of a pickup on its trip: the hop (out and up, falling back under gravity), then the flight to his chest, its
## speed climbing at FLY_ACCEL to `top`, bending off sideways as it sets out; taken when it is COLLECT_R from his chest.
func _travel(i: int, chest: Vector3, top: float, delta: float, map) -> void:
	phase_t[i] += delta
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
	var to := chest - pos[i]
	var l := to.length()
	if l < COLLECT_R:
		_collect(i)
		return
	var dir := to / l
	# every other one bends the other way; the bend fades as it gets going and as it closes in, so it always arrives
	var side := Vector3(-hop_dir[i].z, 0.0, hop_dir[i].x) * (1.0 if (i & 1) == 0 else -1.0)
	var bend: float = FLY_CURVE * clampf(1.0 - phase_t[i] / FLY_CURVE_TIME, 0.0, 1.0) * clampf(l / 2.0, 0.0, 1.0)
	if bend > 0.0:
		dir = (dir + side * bend).normalized()
	var sp: float = minf(FLY_ACCEL * phase_t[i], top)
	pos[i] += dir * minf(sp * delta, l)
	if pos[i].distance_squared_to(chest) < COLLECT_R * COLLECT_R:
		_collect(i)


## Frees about `n` slots by fusing pickups (pass 54, Garry: a gem by the hero vanished and its XP turned up far away;
## the old merge took the hundred oldest gems anywhere). Only resting ones of `which` (the gems, any size; or the coins)
## more than the magnet's reach + MERGE_CLEAR m from the hero (flat), never one on its way to him or a tossed coin still
## lying out of reach, cluster by cluster: the oldest left and every other within MERGE_REACH of it (MERGE_CLUSTER at
## most) become one at their centroid worth their sum (a large gem, or a coin), popping up with a glint; again until `n`
## slots are free or no cluster of two is left. Returns the slots freed.
func _merge(n: int, which: int = KIND_GEM_L) -> int:
	var coin := which == KIND_COIN
	var hero := _hero_at()
	var clear := _magnet() + MERGE_CLEAR
	var idx: Array = []
	for i in range(MAX):
		if alive[i] == 0 or flying[i] == 1 or phase[i] != PHASE_GROUND or hold[i] > 0.0:
			continue
		if (kind[i] == KIND_COIN) != coin or kind[i] == KIND_VACUUM:
			continue
		if hero != Vector3.INF:
			var dx := pos[i].x - hero.x
			var dz := pos[i].z - hero.z
			if dx * dx + dz * dz <= clear * clear:
				continue
		idx.append(i)
	if idx.size() < 2:
		return 0
	idx.sort_custom(func(a, b): return born[a] < born[b])
	# the candidates by MERGE_REACH cells, oldest first in each, so a cluster looks at its own neighbourhood only
	var cells := {}
	for i: int in idx:
		var key := Vector2i(floori(pos[i].x / MERGE_REACH), floori(pos[i].z / MERGE_REACH))
		if not cells.has(key):
			cells[key] = []
		(cells[key] as Array).append(i)
	var used := PackedByteArray()
	used.resize(MAX)
	var r2 := MERGE_REACH * MERGE_REACH
	var freed := 0
	_merging = true
	for a: int in idx:
		if freed >= n:
			break
		if used[a] == 1:
			continue
		var group: Array = [a]
		var ca := Vector2i(floori(pos[a].x / MERGE_REACH), floori(pos[a].z / MERGE_REACH))
		for cx in range(ca.x - 1, ca.x + 2):
			for cz in range(ca.y - 1, ca.y + 2):
				for b: int in cells.get(Vector2i(cx, cz), []):
					if group.size() >= MERGE_CLUSTER:
						break
					if b == a or used[b] == 1:
						continue
					var dx := pos[b].x - pos[a].x
					var dz := pos[b].z - pos[a].z
					if dx * dx + dz * dz <= r2:
						group.append(b)
		if group.size() < 2:
			continue
		var total := 0.0
		var centroid := Vector3.ZERO
		for g: int in group:
			used[g] = 1
			total += value[g]
			centroid += pos[g]
			_free(g)
		centroid /= float(group.size())
		var j := spawn(KIND_COIN if coin else KIND_GEM_L, centroid, total)
		if j >= 0:
			# where they lay, no scatter (no lower than its own rest: pass 56), a little pop and a glint
			pos[j] = centroid
			_lift_to_rest(j)
			vel[j] = Vector3(0.0, MERGE_POP, 0.0)
			_merge_glint(j)
		freed += group.size() - 1
	_merging = false
	return freed


## A merged pickup's glint (pass 54): one mote in its colour, whatever the glint gap says.
func _merge_glint(i: int) -> void:
	var fx = game.get("fx") if game != null else null
	if fx != null and fx.has_method("mote"):
		fx.mote(pos[i] + Vector3(0, 0.15, 0), Vector3(0, 2.2, 0), 0.45, 0.32, COLOURS[clampi(kind[i], 0, COLOURS.size() - 1)])


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


func _free(i: int) -> void:
	if alive[i] == 0:
		return
	alive[i] = 0
	flying[i] = 0
	phase[i] = PHASE_GROUND
	_end_idle(i)
	free_list.append(i)
	count -= 1
	if kind[i] == KIND_COIN:
		coins -= 1


func clear_all() -> void:
	for i in range(MAX):
		_free(i)


func _physics_process(delta: float) -> void:
	_time += delta
	if game == null or game.player == null:
		return
	var t0 := Time.get_ticks_usec()
	var player: Node3D = game.player
	var hero: Vector3 = player.global_position
	var chest: Vector3 = hero + Vector3(0, CHEST, 0)
	var magnet: float = Run.player_sheet.get_stat("magnet", 1.5)
	if player.character and player.character.specials.has("auto_magnet"):
		magnet *= 1.6
	var m2 := magnet * magnet
	# the flight's top speed: the magnet's, never under 12 m/s so a slow magnet still lands them in a beat
	var top: float = clampf(8.0 + magnet * 6.0, 12.0, 40.0)
	var map = game.map
	for i in range(MAX):
		if alive[i] == 0:
			continue
		if flying[i] == 1:
			_travel(i, chest, top, delta, map)
			continue
		# a coin knocked out of the hero (Loose Change, pass 48) on its way down
		if phase[i] == PHASE_TOSS:
			_toss_tick(i, delta, map)
			continue
		# settle (pass 56: a big gem a little higher, rest_of)
		vel[i].y -= HOP_GRAV * delta
		pos[i] += vel[i] * delta
		var ground: float = (map.height_at(pos[i].x, pos[i].z) if map else 0.0) + _rest_k[kind[i]]
		if pos[i].y < ground:
			pos[i].y = ground
			# down: it lies there (pass 56: one still on its way up, below a big gem's higher rest, keeps its pop)
			if vel[i].y <= 0.0:
				vel[i] = Vector3.ZERO
				# lying on the sand (pass 56): a gem's idle hop and glint, when either has something to do
				if kind[i] <= KIND_GEM_L and _time >= idle_due[i]:
					_idle(i, delta)
		var dd := hero - pos[i]
		dd.y = 0.0
		# ... and a moment after it lands: no magnet, no pull, only his own feet (pass 48)
		if hold[i] > 0.0:
			hold[i] -= delta
			if dd.length_squared() < TOSS_TOUCH * TOSS_TOUCH:
				hold[i] = 0.0
				_start_trip(i, hero)
			continue
		if dd.length_squared() < m2:
			_start_trip(i, hero)
		else:
			for a in _attractors:
				var da: Vector3 = a["pos"] - pos[i]
				da.y = 0.0
				if da.length() < a["r"]:
					_start_trip(i, hero)
					break
	_attractors.clear()
	_check_chests(player, delta)
	_check_specials(player, delta)
	_ticks += 1
	Perf.add("pickups", t0)


## One tick of gem `i` lying on the sand (pass 56): its idle hop's clock (the first one HOP_EXTRA_MIN..HOP_EXTRA_MAX s
## after it lands, then as long again after each), and a medium or large gem's glint (its own GLINT_EVERY wait, then a
## glint if the field's GLINT_GAP and GLINT_MAX allow and it is on the screen; a turn passed up waits a full wait again).
func _idle(i: int, delta: float) -> void:
	if hop_t[i] >= 0.0:
		hop_t[i] += delta
		if hop_t[i] >= HOP_EXTRA_TIME + HOP_EXTRA_SQUASH_TIME:
			hop_t[i] = -1.0
			hop_next[i] = _time + _rng.randf_range(HOP_EXTRA_MIN, HOP_EXTRA_MAX)
	elif hop_next[i] < 0.0:
		hop_next[i] = _time + _rng.randf_range(HOP_EXTRA_MIN, HOP_EXTRA_MAX)
	elif _time >= hop_next[i]:
		hop_t[i] = 0.0
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
	# its next call: every tick while a hop or a glint runs, else at the sooner of the two
	if hop_t[i] >= 0.0 or glint_t[i] >= 0.0:
		idle_due[i] = 0.0
	else:
		idle_due[i] = minf(hop_next[i], glint_next[i]) if glints else hop_next[i]


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


## Glints showing now (tests).
func glint_count() -> int:
	return _glints


func _end_glint(i: int) -> void:
	if glint_t[i] < 0.0:
		return
	glint_t[i] = -1.0
	_glints -= 1


## A pickup leaves the sand (taken, merged, called by the magnet): its idle hop and glint stop and their clocks wait for
## it to land again (pass 56).
func _end_idle(i: int) -> void:
	if hop_t.size() != MAX:
		return
	hop_t[i] = -1.0
	hop_next[i] = -1.0
	glint_next[i] = -1.0
	idle_due[i] = -1.0
	_end_glint(i)


## Whether `p` shows on the screen (pass 56, a glint's turn): the camera's view; true without a camera (tests, tools).
func _on_screen(p: Vector3) -> bool:
	var rig = game.get("camera") if game != null else null
	if not (rig is Node):
		return true
	var cam = (rig as Node).get("camera")
	if not (cam is Camera3D) or not (cam as Camera3D).is_inside_tree():
		return true
	var c: Camera3D = cam
	return not c.is_position_behind(p) and c.get_viewport().get_visible_rect().has_point(c.unproject_position(p))


## The float every resting pickup does (pass 54, unchanged in pass 56): `i`'s height over where it lies at `t` s.
static func float_y(i: int, t: float) -> float:
	return 0.06 + sin(t * 2.4 + float(i) * 0.9) * BOB


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
	if game == null or _drawn == _ticks:
		return
	_drawn = _ticks
	var t0 := Time.get_ticks_usec()
	_render()
	Perf.add("pickups.draw", t0)


func _collect(i: int) -> void:
	match kind[i]:
		KIND_COIN:
			Run.add_gold(int(value[i]) * max(int(round(Run.stage_mult())), 1))
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
		fx.mote(pos[i], Vector3(randf_range(-0.6, 0.6), 1.8, randf_range(-0.6, 0.6)), 0.3, 0.24, COLOURS[clampi(kind[i], 0, COLOURS.size() - 1)])


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
		if d.length() < 1.25:
			p.collect_anim()
			game.apply_pickup(p.def, p.global_position)
		else:
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


func warm_draw(at: Vector3) -> void:
	_warm_at = at
	_drawn = -1


func _render() -> void:
	var counters := PackedInt32Array()
	counters.resize(_mms.size())
	var ng := 0
	var rec := record_draws
	if rec and drawn_xf.size() != MAX:
		drawn_xf.resize(MAX)
	for i in range(MAX):
		if alive[i] == 0:
			continue
		var k := kind[i]
		var mm: MultiMesh = _mms[k]
		var n := counters[k]
		var b := Basis().rotated(Vector3.UP, _time * 2.0 + float(i))
		# the float (float_y, written out here: this runs for every pickup every frame)
		var lift := 0.06 + sin(_time * 2.4 + float(i) * 0.9) * BOB
		if k == KIND_COIN:
			if phase[i] == PHASE_TOSS:
				# knocked loose (pass 48): end over end along its throw
				b = Basis().rotated(Vector3.RIGHT, PI * 0.5 + phase_t[i] * TOSS_FLIP).rotated(Vector3.UP, atan2(hop_dir[i].x, hop_dir[i].z))
			else:
				b = Basis().rotated(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, _time * 3.0 + float(i))
		elif hop_t[i] >= 0.0:
			# the idle hop (pass 56): up and down over the float with a flick of spin, stretched as it leaves the sand
			# and squashed as it lands
			var ht: float = hop_t[i]
			b = Basis().rotated(Vector3.UP, _time * 2.0 + float(i) + hop_extra_spin(ht))
			var hs := hop_extra_scale(ht)
			b = b.scaled(Vector3(hs.x, hs.y, hs.x))
			lift += hop_extra_y(ht)
		if phase[i] == PHASE_HOP:
			# the pop: big as it leaves the sand, its own size again at the top of the hop
			var sc: float = lerpf(HOP_POP, 1.0, clampf(phase_t[i] / HOP_TIME, 0.0, 1.0))
			b = b.scaled(Vector3(sc, sc, sc))
		var xf := Transform3D(b, pos[i] + Vector3(0, lift, 0))
		mm.set_instance_transform(n, xf)
		counters[k] = n + 1
		if rec:
			drawn_xf[i] = xf
		if glint_t[i] >= 0.0 and ng < GLINT_MAX:
			_glint_mm.set_instance_transform(ng, glint_xform(i, xf.origin))
			_glint_mm.set_instance_color(ng, glint_color(i))
			_glint_mm.set_instance_custom_data(ng, Color(0.3 + glint_t[i] * 1.8, 0.0, 0.0, 0.0))
			ng += 1
	if _warm_at != Vector3.INF:
		for k in range(_mms.size()):
			if counters[k] < MAX:
				(_mms[k] as MultiMesh).set_instance_transform(counters[k], Transform3D(Basis(), _warm_at))
				counters[k] += 1
		# and one all but invisible glint, so its shader compiles under the spawn beam too (pass 56)
		_glint_mm.set_instance_transform(ng, Transform3D(Basis().scaled(Vector3.ONE * 0.2), _warm_at))
		_glint_mm.set_instance_color(ng, Color(1, 1, 1, 0.02))
		_glint_mm.set_instance_custom_data(ng, Color(0, 0, 0, 0))
		ng += 1
	for k in range(_mms.size()):
		_mms[k].visible_instance_count = counters[k]
	_glint_mm.visible_instance_count = ng


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
	var c: Color = (COLOURS[clampi(kind[i], 0, COLOURS.size() - 1)] as Color).lerp(Color.WHITE, GLINT_PALE)
	return Color(c.r, c.g, c.b, glint_level(glint_t[i]))
