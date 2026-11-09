## Wooden barrels (pass 44): thirty-five 3D barrels (COUNT; forty-four until pass 45, thirty-three until pass 87) scattered over the map by the run's
## seed, each a little apart from the next, clear of the flats, the rocks, the water, the structures and the painted
## scenery (never behind a billboard: the camera looks north from above, so a painting covers the ground just north of
## its foot for about its height).
## Dark barrels are common; the rare ones (`light`, they hold three times the gems) are matte black with brass hoops since
## pass 48 (Garry: black), so the good barrel still reads as the good one. The hero walking up to one breaks it:
## it bursts into splinters and a puff of dust, drops a handful of XP gems (a black one 1-5 coins too since pass 87),
## and the camera gives a small kick.
## Drawn as MultiMeshes of art/props/barrel.glb (`Body`, tinted dark or black; `Hoops`, iron on the common ones and brass
## on the rare ones, a MultiMesh each).
## Barrel Rush (pass 47, a passive): every barrel he smashes starts or refreshes a speed boost (Run.barrel_rush) and the
## game shows it on him (Game.barrel_rush_fx).
## Pass 112 (lane BARREL; Garry: barrels "should respawn every now and then ... a chance of a power up dropping from
## them ... never spawn where Player can see them"): the map's `timeline_data.barrels` block (core/systems/BarrelSpawns.gd)
## lays broken barrels again on a clock, off the screen (respawn_at, spawn_ok), and says what each type holds (its gems,
## its coins, the chance of a power-up thrown out of it for the hero to fetch: _throw_powerup). The start's placement is
## as before.
## Pass 116 (lane MAP; Garry: three kinds "from scratch", looking like his "Barrel Variant Terrain Comparison Board"): the
## barrels are 2.5D paintings now, cut straight from that board (tools/cut_barrels.py -> art/sprites/barrels/
## barrel_exp.png, barrel_coins.png, barrel_powerup.png), one camera-facing MultiMesh a kind drawn by
## prop_billboard.gdshader writing the structures' stencil (5). `light` holds each barrel's kind: 0 exp (brown, iron
## hoops: gems), 1 coins (gold hoops: gems and coins, pass 87's black barrel), 2 powerup (a white stripe: only a power-up).
## The kinds' shares and contents are the map's `barrels` block (BarrelSpawns.CONTENT_DEFAULTS `weight`).
class_name BarrelField
extends Node3D

## Pass 87 (lane FIXES): 35, the old 33 that roll LIGHT_FRAC plus EXTRA_DARK black ones on top (always black).
const COUNT := 35
const LIGHT_FRAC := 0.22
## Pass 87 (lane FIXES, Garry: "Add 2 more dark barrels to the random number of barrels that appear on the map"): the
## last EXTRA_DARK of the COUNT spots are always the black ("darker", `light` in code) kind; the others roll LIGHT_FRAC.
const EXTRA_DARK := 2
## Pass 87 (lane FIXES, Garry: "The darker barrels should now give between 1-5 coins"): a black barrel bursts into
## COIN_MIN..COIN_MAX coins (uniform, whole), each worth COIN_VALUE (the stage scales it when it is taken, like every
## coin), counted as gold source "barrel". Each black barrel's count is rolled once per map (`coins`, from the run's seed)
## and the creatures' first coins of the run hold back that much in all (PickupManager.coin_debt), so breaking every black
## barrel pays what the kills paid before.
const COIN_MIN := 1
const COIN_MAX := 5
const COIN_VALUE := 1.0
const MIN_GAP := 6.5
const RADIUS := 0.31
const BREAK_REACH := 1.05
const CAMERA_PITCH_DEG := 46.0
## a structure's painting is about this wide either side of its foot (the cover band's half width, pass 54)
const STRUCTURE_HALF_W := 1.8
## and a barrel stands at least this far outside a structure's ring (pass 54)
const RING_CLEAR := 0.5
const DARK := Color(0.40, 0.25, 0.13)
## the rare barrel's body (pass 48: matte black; it was a light wood, Color(0.80, 0.60, 0.36)) and its hoops
const LIGHT := Color(0.05, 0.05, 0.06)
const BRASS := Color(0.85, 0.62, 0.22)

var game: Node
var map: MapBase
var pos: PackedVector3Array = PackedVector3Array()
var light: PackedByteArray = PackedByteArray()
var alive: PackedByteArray = PackedByteArray()
var broken := 0
## Coins the black barrels dropped this map (pass 87; tests and the capture).
var coins_dropped := 0
## The coins each spot's barrel holds (pass 87): COIN_MIN..COIN_MAX for a black one, 0 for a brown one (_roll_coins).
var coins: PackedByteArray = PackedByteArray()
## pass 116: one billboard MultiMesh a kind (exp, coins, powerup); the names are pass 48's (dark = exp, light = coins)
var _body_dark: MultiMesh
var _body_light: MultiMesh
var _body_power: MultiMesh
## The pieces a smashed barrel's painting breaks into (2026-10-31, BarrelDebris).
var debris: BarrelDebris
## pass 116: each kind's painting and its height on the ground (metres the square picture stands; the painted barrel's
## own height is a little under it). Heights keep the board's sizes: the coins barrel a touch bigger.
const SPRITES := ["res://art/sprites/barrels/barrel_exp.png", "res://art/sprites/barrels/barrel_coins.png",
	"res://art/sprites/barrels/barrel_powerup.png"]
const QUAD_M := [1.06, 1.15, 1.12]
## the white of the power-up barrel's stripe and the gold of the coins barrel's hoops (their splinters)
const STRIPE := Color(0.92, 0.92, 0.9)
const GOLD := Color(0.86, 0.66, 0.2)
const IRON := Color(0.36, 0.36, 0.38)
static var _shader_5: Shader = null
var _index_in: PackedInt32Array = PackedInt32Array()   # a barrel's instance index inside its body (and hoop) MultiMesh
## Pass 122 (lane S3WORLD; Garry: barrels "more visible on all that red"): on a hell stage (the Blood Moon) every barrel
## wears a pale rim light (prop_billboard.gdshader `rim`, `rim_color`, `rim_width`; the shader's own default rim 0 is
## pass 116's look, so no prop changes). StageLook hands the hell in with the stage (set_hell): the rim fades in with the
## red ground, RIM_HELL strong at full hell; every other stage draws them as before. The three kinds' materials, the rim
## drawn now, its tween. Pass 123 (Garry, 2026-11-03: "Remove the white outline on the barrel cz it looks bad"): RIM_HELL
## 0, so no stage draws the rim; the mechanism stays one number away.
const RIM_HELL := 0.0
const RIM_COLOR := Color(1.0, 0.94, 0.82)
const RIM_WIDTH := 0.03
var _mats: Array = []
var rim := 0.0
var _rim_tween: Tween
## Pass 83 (lane SCENE; Garry: "barrels, signs, and structures too. Want them to feel like they are part of the world"):
## each barrel stands on a ground shadow in the scenery's shadow MultiMesh (PropField.add_shadow, the map's props), this
## wide and deep (metres), this dark, shifted by the sun for a thing SHADOW_TALL high; gone when the barrel breaks.
const SHADOW_W := 0.95
const SHADOW_D := 0.66
const SHADOW_A := 0.5
const SHADOW_TALL := 0.9
var shadows: PackedInt32Array = PackedInt32Array()
## Pass 112 (lane BARREL): the respawn clock (made at its first tick from the map's `barrels` block and the run's seed; a
## test or a tool may hand one in), each kind's MultiMeshes' spare room for respawns past the broken slots (SPARE), the
## barrels' own dice (power-ups, a respawn's coins), and how many barrels came back and power-ups were thrown this run.
var spawns: BarrelSpawns = null
const SPARE := 24
var _dice := RandomNumberGenerator.new()
var respawned := 0
var powerups_thrown := 0
## Pass 137 (lane BARRELS; Garry: "If a shot (projectile) flies through it the Barrel gets knocked back the first time and
## the second time it gets destroyed. Wooden 2 shots, Golden 3, Power-up 5 ... A togglable option in the settings, on by
## default"; answers: flying rounds only, walking into one still breaks it): see shot_through. A round within SHOT_R (plus
## its own radius, at most SHOT_ROUND_MAX) of a barrel's axis, between SHOT_LOW and SHOT_HIGH over its foot, hits it once
## and flies on (no pierce spent). Every hit before its kind's `shots` (BarrelSpawns.contents_of) slides it KNOCK_M along
## the round's flight (half that when the spot is taken, none when that is too: never into a rock, the water, a structure's
## ring, a painting's cover band, another barrel or past the arena) with a squash and a wobble over WOBBLE_S, chips and a
## knock (st_barrel_hit); the last breaks it as walking into it does (_break: the same loot, debris, sound and Barrel
## Rush). The rule position moves at once; only the drawing slides. GRID_CELL m cells over the standing barrels (each
## barrel in every cell within GRID_PAD of it: i + 1, or -1 where two meet) let a round ask one cell a tick.
const SHOT_R := 0.36
const SHOT_ROUND_MAX := 0.6
const SHOT_LOW := -0.4
const SHOT_HIGH := 1.7
const KNOCK_M := 0.6
const KNOCK_S := 0.22
const WOBBLE_S := 0.5
const KNOCK_HOP := 0.1
const GRID_CELL := 1.0
const GRID_PAD := 1.6
## each barrel's hits so far (index -> count; gone when it breaks or stands again), and every one's life (index -> how many
## times its slot stood again: a round's memory of a barrel it struck is that barrel's, not its slot's)
var shot_hits: Dictionary = {}
var _life: Dictionary = {}
## rounds that knocked a barrel back, barrels broken by rounds (tests, the capture)
var shot_knocks := 0
var shot_breaks := 0
## the grid (ProjectileManager reads it inline, and checks a one-barrel cell's barrel against the step's midpoint before
## asking): cells, its width and height in cells, its corner (x, z)
var grid := PackedInt32Array()
var grid_w := 0
var grid_h := 0
var grid_o := Vector2.ZERO
var _grid_dirty := true
var _grid_n := -1
## a knocked barrel's drawing (index -> {from, to, t}): looks only
var _anims: Dictionary = {}
var _knock_ctx_cache: Dictionary = {}
var _shots := PackedInt32Array()


func setup(p_game: Node, p_map: MapBase) -> void:
	game = p_game
	map = p_map
	if Run.rng_seed != 0:
		_dice.seed = hash([Run.rng_seed, "barrels"])
	else:
		_dice.randomize()
	_place()
	# pass 87 (lane FIXES): the black barrels' coins, and the creatures' coins hold back as much (PickupManager.coin_debt)
	_roll_coins()
	var pk = game.get("pickups") if game != null else null
	if pk != null and pk.has_method("set_coin_debt"):
		pk.set_coin_debt(float(coins_total()))
	var n := [0, 0, 0]
	for i in pos.size():
		n[light[i]] += 1
	_body_dark = _billboards(0, n[0], SPARE)
	_body_light = _billboards(1, n[1], SPARE)
	_body_power = _billboards(2, n[2], SPARE)
	# 2026-10-31 (Garry: "the breaking isn't clear"): a smashed barrel's painting comes apart (BarrelDebris)
	debris = BarrelDebris.new()
	debris.name = "BarrelDebris"
	add_child(debris)
	debris.setup(game, map, SPRITES)
	var k := [0, 0, 0]
	for i in pos.size():
		var t: int = light[i]
		var mm := _mm_of(t)
		if mm:
			mm.set_instance_transform(k[t], instance_transform(i, "body"))
		_index_in.append(k[t])
		k[t] += 1
	_add_shadows()
	apply_glint(BarrelSpawns.glint_of(_block()))


## Pass 135: the glint (prop_billboard.gdshader `glint*`) on every kind's material from a filled block
## (BarrelSpawns.glint_of).
func apply_glint(g: Dictionary) -> void:
	for m: ShaderMaterial in _mats:
		m.set_shader_parameter("glint", float(g["strength"]))
		m.set_shader_parameter("glint_every", float(g["every"]))
		m.set_shader_parameter("glint_length", float(g["length"]))
		m.set_shader_parameter("glint_width", float(g["width"]))


## The barrels' ground shadows (pass 83), one each in the map's scenery shadows; none on a map without props.
func _add_shadows() -> void:
	shadows.clear()
	var props = map.get("props") if map else null
	for i in pos.size():
		shadows.append(props.add_shadow(pos[i], SHADOW_W, SHADOW_D, SHADOW_A, SHADOW_TALL) if props is PropField else -1)


## A barrel's own place on the map: its painting's square scaled to its kind's height, its foot on its spot (pass 116; the
## shader turns it to the camera).
func barrel_transform(i: int) -> Transform3D:
	var t: int = light[i] if i < light.size() else 0
	var m := float(QUAD_M[clampi(t, 0, 2)])
	return Transform3D(Basis().scaled(Vector3(m, m, m)), pos[i])


## Where barrel `i` is drawn (pass 116: one painting, `part` kept for old callers). The headless renderer keeps no instance
## transforms, so the tests read this.
func instance_transform(i: int, _part: String = "body") -> Transform3D:
	return barrel_transform(i)


## Kind `t`'s MultiMesh (0 exp, 1 coins, 2 powerup).
func _mm_of(t: int) -> MultiMesh:
	return _body_light if t == 1 else (_body_power if t == 2 else _body_dark)


## The painted barrels' shader: prop_billboard's with the structures' stencil (5) in place of the scenery's (4).
static func barrel_shader() -> Shader:
	if _shader_5 == null:
		var base: Shader = load("res://core/shaders/prop_billboard.gdshader")
		_shader_5 = Shader.new()
		_shader_5.code = base.code.replace("stencil_mode write, compare_always, %d;" % SceneryStencil.VALUE,
			"stencil_mode write, compare_always, %d;" % SceneryStencil.STRUCTURE)
	return _shader_5


## Kind `t`'s billboards: `n` standing, `spare` more waiting unseen for respawns (pass 112: the count cannot grow without
## clearing the transforms). Null when the painting is missing.
func _billboards(t: int, n: int, spare: int = 0) -> MultiMesh:
	if not ResourceLoader.exists(SPRITES[t]):
		return null
	var mat := ShaderMaterial.new()
	mat.shader = barrel_shader()
	mat.set_shader_parameter("sprite", load(SPRITES[t]))
	mat.set_shader_parameter("mute", 0.04)
	# pass 122 (lane S3WORLD): the rim light, off until a hell stage says otherwise (set_hell)
	mat.set_shader_parameter("rim", rim)
	mat.set_shader_parameter("rim_color", RIM_COLOR)
	mat.set_shader_parameter("rim_width", RIM_WIDTH)
	_mats.append(mat)
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var mm := _multimesh(quad, n, mat, spare, true)
	# pass 135: each instance its own glint clock (INSTANCE_CUSTOM.z; the shader hashes it, the sway stays 0)
	for k in mm.instance_count:
		mm.set_instance_custom_data(k, Color(0.0, 0.0, float(k) * 1.618 + float(t) * 7.31, 0.0))
	return mm


## Pass 122 (lane S3WORLD): the stage's hell `f` (0..1; StageLook.show_stage, with the map's set_hell): the barrels' rim
## light goes to RIM_HELL x f over `seconds` (0: at once).
func set_hell(f: float, seconds: float = 0.0) -> void:
	if _rim_tween:
		_rim_tween.kill()
		_rim_tween = null
	var want := RIM_HELL * clampf(f, 0.0, 1.0)
	if seconds <= 0.0 or not is_inside_tree():
		_apply_rim(want)
		return
	_rim_tween = create_tween()
	_rim_tween.tween_method(_apply_rim, rim, want, seconds)


func _apply_rim(v: float) -> void:
	rim = v
	for m: ShaderMaterial in _mats:
		m.set_shader_parameter("rim", v)


## The barrels' materials (tests): one a kind, in SPRITES' order.
func materials() -> Array:
	return _mats


## Where `node` stands inside the model whose root is `root`: its own transform under every Node3D above it, the root's
## included (the scene is not in a tree, so no global transform is asked for).
static func part_transform(root: Node, node: Node3D) -> Transform3D:
	var xf := node.transform
	var p := node.get_parent()
	while p != null:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		if p == root:
			break
		p = p.get_parent()
	return xf


## `spare` instances past `n` wait unseen for respawns (pass 112: the count cannot grow without clearing the transforms).
func _multimesh(mesh: Mesh, n: int, mat: Material, spare: int = 0, custom: bool = false) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# pass 116: the billboard shader reads INSTANCE_CUSTOM (flip, sway, phase, tint: all 0 here)
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = maxi(n + spare, 1)
	mm.visible_instance_count = n
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if mat:
		mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	# pass 72: scenery (a creature a barrel hides is outlined, SceneryStencil)
	# pass 105 (lane LOOK): with the structures (the stage's filter darkens them less, StageLook `structures`)
	SceneryStencil.mark_tree(mmi, SceneryStencil.STRUCTURE)
	add_child(mmi)
	return mm


## Spots at least MIN_GAP apart, clear of everything that would hide or crowd a barrel; the gap relaxes when the map
## fights back, so there are always COUNT of them.
func _place() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Run.map_seed * 13 + 7
	var fc := Vector2(map.flats_center.x, map.flats_center.z)
	var start := map.player_start()
	var covers: Array = _covers()
	var rings: Array = structure_rings(game)
	var tries := 0
	var limit := COUNT * 400
	while pos.size() < COUNT and tries < limit:
		tries += 1
		var relax := 1.0 - 0.6 * clampf(float(tries) / float(limit), 0.0, 1.0)
		var a := rng.randf() * TAU
		var r := rng.randf_range(map.arena_radius * 0.12, map.arena_radius * 0.92)
		var p := Vector2(cos(a) * r, sin(a) * r)
		if (p - fc).length() < map.flats_radius * 0.5:
			continue
		if p.distance_to(Vector2(start.x, start.z)) < 5.0:
			continue
		if map.has_method("in_water") and map.in_water(Vector3(p.x, 0, p.y)):
			continue
		var ok := true
		for o: Vector3 in map.obstacles:
			if p.distance_to(Vector2(o.x, o.y)) < o.z + RADIUS + 0.9:
				ok = false
				break
		if not ok:
			continue
		if in_cover(covers, p, RADIUS):
			continue
		# never inside a structure's ring either (pass 54: its cover band only reaches 0.7 m south of the foot)
		for g: Vector3 in rings:
			if p.distance_to(Vector2(g.x, g.y)) < g.z + RADIUS + RING_CLEAR:
				ok = false
				break
		if not ok:
			continue
		for q in pos:
			if p.distance_to(Vector2(q.x, q.z)) < MIN_GAP * relax:
				ok = false
				break
		if not ok:
			continue
		pos.append(Vector3(p.x, map.height_at(p.x, p.y), p.y))
		# pass 87 (lane FIXES): the last EXTRA_DARK spots are black whatever the roll
		# pass 116 (lane MAP): the others by the kinds' weights (exp, coins, powerup; one roll as before)
		light.append(BarrelSpawns.COINS if pos.size() > COUNT - EXTRA_DARK else BarrelSpawns.pick_kind(_block(), rng))
		alive.append(1)


## Every billboard on the map as (x, z, half width, cover length north): the painted scenery and the structures.
func _covers() -> Array:
	return covers_of(game, map)


## The cover bands of `map`'s painted scenery and of `game`'s structures, as (x, z, half width, cover length north)
## (pass 54: shared with SignField). A structure is its own Node3D (StructureManager.items); the band used to be read off
## a `node` field no Structure has, so it never counted and barrels landed behind the paintings.
static func covers_of(p_game: Node, p_map: Node) -> Array:
	var out: Array = []
	var cot := 1.0 / tan(deg_to_rad(CAMERA_PITCH_DEG))
	var props = p_map.get("props") if p_map != null else null
	if props is PropField:
		for row in (props as PropField).placed:
			var id := str(row["id"])
			var h: float = (props as PropField).height_of(id) * float(row["scale"])
			var at: Vector3 = row["pos"]
			out.append(Vector4(at.x, at.z, h * 0.5, h * cot))
	for s in structures_of(p_game):
		var at := structure_position(s)
		var d = s.get("def")
		var tall: float = float(d.height) if d != null else 3.2
		out.append(Vector4(at.x, at.z, STRUCTURE_HALF_W, tall * cot))
	return out


## Inside any cover band, for something `r` metres round standing at `p` (x, z)? A band runs from 0.7 m south of the
## painting's foot to its cover length north of it (the camera looks north from above), its half width either side.
static func in_cover(covers: Array, p: Vector2, r: float) -> bool:
	for c: Vector4 in covers:
		if absf(p.x - c.x) < c.z + r and p.y < c.y + 0.7 and p.y > c.y - c.w - r:
			return true
	return false


## Every structure's ring as (x, z, radius) (pass 54).
static func structure_rings(p_game: Node) -> Array:
	var out: Array = []
	for s in structures_of(p_game):
		var at := structure_position(s)
		var d = s.get("def")
		out.append(Vector3(at.x, at.z, float(d.radius) if d != null else 2.2))
	return out


## The game's structures (StructureManager.items, Structure nodes), none when it has none.
static func structures_of(p_game: Node) -> Array:
	var out: Array = []
	var sm = p_game.get("structures") if p_game != null else null
	if not (sm is Object) or not is_instance_valid(sm):
		return out
	var items = sm.get("items")
	if not (items is Array):
		return out
	for s in items:
		if s is Node3D and is_instance_valid(s):
			out.append(s)
	return out


## Where a structure stands: its global position once it is in the tree (Game._ready), its own position before.
static func structure_position(s: Node3D) -> Vector3:
	return s.global_position if s.is_inside_tree() else s.position


func _enter_tree() -> void:
	# pass 114 (lane REPLAY): the replay driver's group (Lockstep)
	Lockstep.join(self)


func _physics_process(delta: float) -> void:
	# pass 114 (lane REPLAY): a replay's driver runs these steps itself (Lockstep)
	if Lockstep.phys_skip():
		return
	if game == null or pos.is_empty() or bool(game.get("paused")) or game.player == null or game.player.dead:
		return
	# pass 112 (lane BARREL): broken barrels come back now and then, off the screen
	_tick_spawns(delta)
	var pp: Vector3 = game.player.global_position
	for i in pos.size():
		if alive[i] == 0:
			continue
		var d := Vector2(pp.x - pos[i].x, pp.z - pos[i].z).length()
		if d < RADIUS + BREAK_REACH:
			_break(i)


## The barrel bursts: splinters in its own wood, dust, gems (three times as many from a light one), a crack and a kick.
## Pass 137 (lane BARRELS): `from` is where the blow came from (a round's side; INF = the hero: walking into it).
func _break(i: int, from: Vector3 = Vector3.INF) -> void:
	alive[i] = 0
	broken += 1
	shot_hits.erase(i)
	_anims.erase(i)
	_grid_dirty = true
	# pass 113 (lane TASKS): one barrel broken by the hero (brown and black alike), for the barrel tasks
	Run.barrels_broken += 1
	var at := pos[i]
	var gone := Transform3D(Basis().scaled(Vector3.ZERO), at)
	var t: int = light[i]
	var mm := _mm_of(t)
	if mm:
		mm.set_instance_transform(_index_in[i], gone)
	if i < shadows.size() and shadows[i] >= 0 and map and map.get("props") is PropField:
		(map.get("props") as PropField).hide_shadow(shadows[i])
	var wood := DARK
	if debris != null:
		if from == Vector3.INF:
			from = game.player.global_position if game.player != null else at
		debris.burst(t, at, float(QUAD_M[clampi(t, 0, 2)]), from)
	if game.fx:
		# staves, hoop pieces and a cloud of dust, big enough to read from the camera's height (pass 116: the wood of the
		# board's barrels, gold hoop bits from the coins one, white stripe bits from the power-up one)
		game.fx.splinters(at, wood, 22 if t == 1 else 18, 0.27)
		game.fx.splinters(at, wood.darkened(0.3), 8, 0.16)
		game.fx.splinters(at, GOLD if t == 1 else IRON, 6 if t == 1 else 5, 0.15)
		if t == 2:
			game.fx.splinters(at, STRIPE, 6, 0.14)
		game.fx.sand(at, 2.2)
		game.fx.burst(at + Vector3(0, 0.6, 0), Color(0.86, 0.7, 0.45), 1.3)
	# the gems: a small gem is worth more the deeper the run (a level needs 15 + 6L + L²/2)
	# pass 79 (lane MUT): the card levels (Run.card_level), so a barrel pays at a minute what it paid before
	var per := 1.0 + float(Run.card_level()) * 0.15
	var pk = game.pickups
	# pass 112 (lane BARREL): what this kind holds, the map's `barrels` block (today's when it names none: a brown one 8
	# small gems, a black one 10 small and 4 medium and its 1-5 coins)
	var cc := contents(t)
	if pk:
		for k in int(cc["gems_small"]):
			pk.spawn(pk.KIND_GEM_S, at + Vector3(Dice.r.randf_range(-0.5, 0.5), 0.3, Dice.r.randf_range(-0.5, 0.5)), per)
		for k in int(cc["gems_medium"]):
			pk.spawn(pk.KIND_GEM_M, at + Vector3(Dice.r.randf_range(-0.6, 0.6), 0.5, Dice.r.randf_range(-0.6, 0.6)), per * 4.0)
		# pass 87 (lane FIXES): and its coins (a black one's; a brown one's only when the map gives it some)
		if t == 1 or (i < coins.size() and coins[i] > 0):
			_drop_coins(i, at, pk)
		# pass 112 (lane BARREL): now and then a power-up hops out of it, for the hero to fetch or leave
		_throw_powerup(cc, at, pk)
	Audio.play("st_barrel_break", at)
	if game.camera:
		game.camera.shake(0.45 if t == 1 else 0.3)
	if game.hud and t == 1:
		game.hud.toast(Loc.t("toast.good_barrel"), Color(1.0, 0.85, 0.4))
	_rush()


## Each black barrel's coins (pass 87, lane FIXES): COIN_MIN..COIN_MAX (uniform, whole), rolled once per map on the run's
## seed (its own dice, after the spots, so the spots are as before); a brown barrel holds none.
## Pass 112 (lane BARREL): each kind's count from the map's `barrels` block (`coins`: today's 1-5 black, none brown).
func _roll_coins() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Run.map_seed * 31 + 11
	coins.resize(pos.size())
	var ranges := [contents(0)["coins"], contents(1)["coins"], contents(2)["coins"]]
	for i in pos.size():
		var r: Vector2i = ranges[light[i]]
		coins[i] = rng.randi_range(r.x, r.y) if r.y > 0 else 0


## All the coins the map's barrels hold (broken or not).
func coins_total() -> int:
	var n := 0
	for c in coins:
		n += c
	return n


## Black barrel `i`'s coins (pass 87, lane FIXES): what it holds (`coins`; COIN_MIN..COIN_MAX at random for one set up by
## hand), worth COIN_VALUE each, scattered round it like its gems, each marked as the "barrel" gold source. Returns how
## many.
func _drop_coins(i: int, at: Vector3, pk) -> int:
	var r: Vector2i = contents(light[i])["coins"]
	var n: int = coins[i] if i < coins.size() and coins[i] > 0 else Dice.r.randi_range(r.x, r.y)
	for k in n:
		var c: int = pk.spawn(pk.KIND_COIN, at + Vector3(Dice.r.randf_range(-0.6, 0.6), 0.5, Dice.r.randf_range(-0.6, 0.6)), COIN_VALUE)
		if pk.has_method("mark_coin"):
			pk.mark_coin(c, "barrel")
	coins_dropped += n
	return n


## Barrel Rush (pass 47, Garry: "Smacking Barrels Causes Player to get a speed boost"): Run starts or refreshes the boost
## when the hero holds it; the game bursts gold round him (`fresh` when none was running). True when it did.
func _rush() -> bool:
	var fresh := Run.boost_left(Run.BARREL_RUSH) <= 0.0
	if not Run.barrel_rush():
		return false
	if game != null and game.has_method("barrel_rush_fx"):
		game.barrel_rush_fx(fresh)
	return true


func alive_count() -> int:
	var n := 0
	for i in alive.size():
		n += alive[i]
	return n


# ---------------------------------------------------------------- the Outlaw's rounds hit barrels (pass 137, lane BARRELS)

## Whether a round may hit a barrel now: the player's switch (Settings.shoot_barrels) on and a barrel standing. Brings the
## grid up to date first, so a caller may read `grid` straight after.
func shootable() -> bool:
	if not bool(Settings.shoot_barrels) or pos.is_empty():
		return false
	if _grid_dirty or _grid_n != pos.size():
		_build_grid()
	return grid_w > 0


## The grid over the standing barrels: GRID_CELL m cells, each barrel in every cell that comes within GRID_PAD of it (i + 1;
## -1 where two meet). A round whose tick's midpoint falls in an empty cell passes no barrel: its reach (at most 0.96 m)
## plus half its step stays inside GRID_PAD up to a step of 1.28 m a tick (77 m/s at 60 ticks; a 0.3 m round's 113 m/s).
func _build_grid() -> void:
	_grid_dirty = false
	_grid_n = pos.size()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in pos.size():
		if i < alive.size() and alive[i] == 1:
			lo = Vector2(minf(lo.x, pos[i].x), minf(lo.y, pos[i].z))
			hi = Vector2(maxf(hi.x, pos[i].x), maxf(hi.y, pos[i].z))
	if lo.x == INF:
		grid_w = 0
		grid_h = 0
		grid.clear()
		return
	grid_o = lo - Vector2(GRID_PAD + GRID_CELL, GRID_PAD + GRID_CELL)
	grid_w = int(ceilf((hi.x - grid_o.x + GRID_PAD + GRID_CELL) / GRID_CELL)) + 1
	grid_h = int(ceilf((hi.y - grid_o.y + GRID_PAD + GRID_CELL) / GRID_CELL)) + 1
	grid.resize(grid_w * grid_h)
	grid.fill(0)
	for i in pos.size():
		if i >= alive.size() or alive[i] == 0:
			continue
		var x0 := int((pos[i].x - GRID_PAD - grid_o.x) / GRID_CELL)
		var x1 := int((pos[i].x + GRID_PAD - grid_o.x) / GRID_CELL)
		var z0 := int((pos[i].z - GRID_PAD - grid_o.y) / GRID_CELL)
		var z1 := int((pos[i].z + GRID_PAD - grid_o.y) / GRID_CELL)
		for cz in range(maxi(z0, 0), mini(z1, grid_h - 1) + 1):
			for cx in range(maxi(x0, 0), mini(x1, grid_w - 1) + 1):
				# the cell's nearest point to the barrel within GRID_PAD of it
				var nx := clampf(pos[i].x, grid_o.x + cx * GRID_CELL, grid_o.x + (cx + 1) * GRID_CELL) - pos[i].x
				var nz := clampf(pos[i].z, grid_o.y + cz * GRID_CELL, grid_o.y + (cz + 1) * GRID_CELL) - pos[i].z
				if nx * nx + nz * nz > GRID_PAD * GRID_PAD:
					continue
				var k := cz * grid_w + cx
				grid[k] = i + 1 if grid[k] == 0 else -1


## The grid's cell at (x, z): 0 no barrel near, i + 1 barrel i, -1 several (call shootable() first).
func grid_at(x: float, z: float) -> int:
	if grid_w <= 0:
		return 0
	var cx := int(floorf((x - grid_o.x) / GRID_CELL))
	var cz := int(floorf((z - grid_o.y) / GRID_CELL))
	if cx < 0 or cz < 0 or cx >= grid_w or cz >= grid_h:
		return 0
	return grid[cz * grid_w + cx]


## A round of the Outlaw's (`r` its radius) that flew from `p0` to `p1` this tick: every standing barrel it passed through
## and has not struck yet (`seen` is the round's own memory: barrel index -> that barrel's life) takes a hit, knocked back
## along the flight or broken on its last; the round flies on. `cell` is the grid's cell at the step's midpoint (-1 = look
## at every barrel). How many barrels it struck.
func shot_through(p0: Vector3, p1: Vector3, r: float, seen: Dictionary, cell: int = -1) -> int:
	if cell == 0 or not bool(Settings.shoot_barrels):
		return 0
	var reach := SHOT_R + clampf(r, 0.0, SHOT_ROUND_MAX)
	var n := 0
	if cell > 0:
		n += _shot_one(cell - 1, p0, p1, reach, seen)
	else:
		for i in pos.size():
			n += _shot_one(i, p0, p1, reach, seen)
	return n


func _shot_one(i: int, p0: Vector3, p1: Vector3, reach: float, seen: Dictionary) -> int:
	if i < 0 or i >= pos.size() or i >= alive.size() or alive[i] == 0:
		return 0
	var c := pos[i]
	var up := p1.y - c.y
	if up < SHOT_LOW or up > SHOT_HIGH:
		return 0
	# the flat distance from the barrel's axis to the round's step
	var a := Vector2(p0.x - c.x, p0.z - c.z)
	var d := Vector2(p1.x - p0.x, p1.z - p0.z)
	var dd := d.length_squared()
	var t := clampf(-a.dot(d) / dd, 0.0, 1.0) if dd > 0.000001 else 1.0
	if (a + d * t).length_squared() > reach * reach:
		return 0
	var life := int(_life.get(i, 0))
	if seen.has(i) and int(seen[i]) == life:
		return 0
	seen[i] = life
	shot_hit(i, Vector3(d.x, 0.0, d.y), p0)
	return 1


## Barrel `i` takes one of the Outlaw's rounds flying along `dir` (flat) from `from`: knocked back, or broken by the last
## of its kind's `shots`.
func shot_hit(i: int, dir: Vector3, from: Vector3) -> void:
	if i < 0 or i >= alive.size() or alive[i] == 0:
		return
	var need := shots_to_break(light[i] if i < light.size() else 0)
	var n := int(shot_hits.get(i, 0)) + 1
	if n >= need:
		shot_breaks += 1
		_break(i, from)
		return
	shot_hits[i] = n
	shot_knocks += 1
	_knock(i, dir)


## The rounds a barrel of kind `t` takes to break (its kind's `shots`, at least 1; read from the map's block once a field).
func shots_to_break(t: int) -> int:
	var k := clampi(t, 0, 2)
	if _shots.is_empty():
		for j in range(3):
			_shots.append(maxi(int(contents(j).get("shots", 1)), 1))
	return _shots[k]


## The knock: the barrel's rule place moves KNOCK_M along `dir` at once (half that, or not at all, when the spot is not
## free), its drawing slides there with a squash and a wobble (_process); chips, a puff and a knock.
func _knock(i: int, dir: Vector3) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 0.000001 and game != null and game.get("player") != null:
		var hp: Vector3 = (game.player as Node3D).global_position
		d = Vector3(pos[i].x - hp.x, 0.0, pos[i].z - hp.z)
	d = d.normalized() if d.length_squared() > 0.000001 else Vector3.FORWARD
	var at := pos[i]
	var to := at
	for f: float in [1.0, 0.5]:
		var q := at + d * KNOCK_M * f
		if knock_ok(i, q):
			to = Vector3(q.x, map.height_at(q.x, q.z) if map != null else at.y, q.z)
			break
	pos[i] = to
	_grid_dirty = true
	if Run.sim_mode:
		_draw_barrel(i, to, 0.0)
		return
	_anims[i] = {"from": at, "to": to, "t": 0.0}
	var wood: Color = GOLD if light[i] == 1 else (STRIPE if light[i] == 2 else DARK)
	if game != null and game.get("fx") != null:
		game.fx.splinters(at + Vector3(0, 0.45, 0), DARK, 6, 0.14)
		game.fx.splinters(at + Vector3(0, 0.45, 0), wood, 3, 0.11)
		game.fx.sand(at, 0.7)
	Audio.play("st_barrel_hit", at)


## Whether barrel `i` may stand at `q` after a knock: clear of the other barrels, and on a map inside 0.92 of the arena,
## out of the water, off the rocks, out of the structures' rings and of the paintings' cover bands (a barrel already in a
## band may stay in it).
func knock_ok(i: int, q: Vector3) -> bool:
	var p := Vector2(q.x, q.z)
	for k in pos.size():
		if k != i and k < alive.size() and alive[k] == 1 and p.distance_to(Vector2(pos[k].x, pos[k].z)) < RADIUS * 2.0 + 0.2:
			return false
	if map == null:
		return true
	if p.length() > map.arena_radius * 0.92:
		return false
	if map.has_method("in_water") and map.in_water(Vector3(p.x, 0, p.y)):
		return false
	for o: Vector3 in map.obstacles:
		if p.distance_to(Vector2(o.x, o.y)) < o.z + RADIUS + 0.1:
			return false
	if _knock_ctx_cache.is_empty():
		_knock_ctx_cache = spawn_ctx()
	for g: Vector3 in _knock_ctx_cache.get("rings", []):
		if p.distance_to(Vector2(g.x, g.y)) < g.z + RADIUS:
			return false
	var covers: Array = _knock_ctx_cache.get("covers", [])
	if in_cover(covers, p, RADIUS) and not in_cover(covers, Vector2(pos[i].x, pos[i].z), RADIUS):
		return false
	return true


## Barrel `i` drawn at `at`, `w` its squash (0 = at rest), its shadow under it.
func _draw_barrel(i: int, at: Vector3, w: float) -> void:
	var t: int = light[i] if i < light.size() else 0
	var m := float(QUAD_M[clampi(t, 0, 2)])
	var mm := _mm_of(t)
	if mm != null and i < _index_in.size():
		mm.set_instance_transform(_index_in[i], Transform3D(Basis().scaled(Vector3(m * (1.0 + 0.16 * w), m * (1.0 - 0.14 * w), m)), at))
	if i < shadows.size() and shadows[i] >= 0 and map != null and map.get("props") is PropField:
		(map.get("props") as PropField).move_shadow(shadows[i], at)


## The knocked barrels' drawing (looks only): the slide eases out over KNOCK_S with a small hop, the squash rings down over
## WOBBLE_S.
func _process(delta: float) -> void:
	if _anims.is_empty():
		return
	delta = Lockstep.dt(delta)
	if game != null and bool(game.get("paused")):
		return
	for i in _anims.keys():
		var a: Dictionary = _anims[i]
		var t: float = float(a["t"]) + delta
		a["t"] = t
		if i >= alive.size() or alive[i] == 0:
			_anims.erase(i)
			continue
		if t >= WOBBLE_S:
			_anims.erase(i)
			_draw_barrel(i, pos[i], 0.0)
			continue
		var f := clampf(t / KNOCK_S, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - f, 3.0)
		var at: Vector3 = (a["from"] as Vector3).lerp(a["to"], e)
		at.y += KNOCK_HOP * sin(PI * f)
		_draw_barrel(i, at, exp(-t * 9.0) * cos(t * 30.0))


# ---------------------------------------------------------------- respawns, contents, power-ups (pass 112, lane BARREL)

## The map's `barrels` block: the director's timeline's, else the run's map's ({} in a test without either).
func _timeline() -> WaveTimeline:
	var d = game.get("director") if game != null else null
	if d != null and d.get("timeline") is WaveTimeline:
		return d.get("timeline")
	return Run.map.timeline if Run.map != null else null


func _block() -> Dictionary:
	var tl := _timeline()
	return tl.barrels if tl != null else {}


## What a barrel of this kind holds (`kind`: 0 exp, 1 coins, 2 powerup, or pass 112's bool black; BarrelSpawns.contents_of):
## gems_small, gems_medium, coins (Vector2i), powerup_chance (0 but for the powerup kind), powerups, throw_distance.
func contents(kind) -> Dictionary:
	return BarrelSpawns.contents_of(_block(), kind)


func respawn_clock() -> BarrelSpawns:
	if spawns == null:
		spawns = BarrelSpawns.new()
		spawns.setup(_block(), int(Run.rng_seed))
	return spawns


## One tick of the respawn clock: only while the director runs a stage (never in the debug arena, nor in a test's game
## without a director), in the phases the block lets its clock run in.
func _tick_spawns(delta: float) -> void:
	var d = game.get("director") if game != null else null
	if d == null or not bool(d.get("running")) or Run.arena:
		return
	respawn_clock().tick(self, delta, int(d.get("phase")))


## A power-up thrown out of a barrel smashed at `at` (pass 112): its kind's `powerup_chance` on the barrels' own dice,
## drawn by weight from its `powerups` (none listed: the map's power-up drops roster), thrown `throw_distance` m away on
## a visible hop (PickupManager.throw_powerup: away from the hero and on the screen where it can be, never taken in the
## air, never pulled by a magnet, lying its own lifetime). The power-up, or null when none came.
func _throw_powerup(cc: Dictionary, at: Vector3, pk) -> Powerup:
	var chance := float(cc["powerup_chance"])
	if pk == null or not pk.has_method("throw_powerup") or chance <= 0.0 or _dice.randf() >= chance:
		return null
	var list: Array = cc["powerups"]
	if list.is_empty():
		var tl := _timeline()
		if tl != null:
			list = BarrelSpawns.weight_list(tl.pickups.get("roster", []))
	# pass 129 (lane TRAILCORE): a power-up a Trail node gives is not thrown until that node is bought (the same list when
	# no node names one; a list left empty throws nothing, as an empty roster always did)
	list = Trail.rows_open("powerup", list)
	var def: PickupDef = Registry.pickup(BarrelSpawns.pick_weighted(list, _dice))
	if def == null:
		return null
	powerups_thrown += 1
	return pk.throw_powerup(def, at, cc["throw_distance"], _dice)


# BarrelSpawns' host: the hero, the camera's view, the spot rules, a barrel laid again

func spawn_hero() -> Vector3:
	if game == null or game.get("player") == null:
		return Vector3.INF
	return (game.player as Node3D).global_position


## The camera's frustum planes, facing out (empty without a camera: nobody sees).
func spawn_planes() -> Array:
	var rig = game.get("camera") if game != null else null
	var cam: Camera3D = null
	if rig is Camera3D:
		cam = rig
	elif rig is Object and is_instance_valid(rig) and rig.get("camera") is Camera3D:
		cam = rig.get("camera")
	if cam == null and is_inside_tree():
		cam = get_viewport().get_camera_3d()
	return Array(cam.get_frustum()) if cam != null and cam.is_inside_tree() else []


## What the spot rules read, gathered once a search: the paintings' cover bands and the structures' rings.
func spawn_ctx() -> Dictionary:
	return {"covers": _covers(), "rings": structure_rings(game)}


## `p` grounded when a barrel may stand there, Vector3.INF when not: the start's rules (_place: inside 0.92 of the
## arena's radius, off the flats' middle, out of the water, off the rocks, out of every painting's cover band and
## structure ring) and MIN_GAP from every barrel standing.
func spawn_ok(p: Vector3, ctx: Dictionary) -> Vector3:
	var q := Vector2(p.x, p.z)
	for i in pos.size():
		if alive[i] == 1 and q.distance_to(Vector2(pos[i].x, pos[i].z)) < MIN_GAP:
			return Vector3.INF
	if map == null:
		return Vector3(p.x, 0.0, p.z)
	if q.length() > map.arena_radius * 0.92:
		return Vector3.INF
	if (q - Vector2(map.flats_center.x, map.flats_center.z)).length() < map.flats_radius * 0.5:
		return Vector3.INF
	if map.has_method("in_water") and map.in_water(Vector3(p.x, 0, p.z)):
		return Vector3.INF
	for o: Vector3 in map.obstacles:
		if q.distance_to(Vector2(o.x, o.y)) < o.z + RADIUS + 0.9:
			return Vector3.INF
	if in_cover(ctx.get("covers", []), q, RADIUS):
		return Vector3.INF
	for g: Vector3 in ctx.get("rings", []):
		if q.distance_to(Vector2(g.x, g.y)) < g.z + RADIUS + RING_CLEAR:
			return Vector3.INF
	return Vector3(p.x, map.height_at(p.x, p.z), p.z)


## A barrel laid again at `at` (pass 112): a broken one of its kind stands up there (its slot, its instance, its shadow),
## else a new one from its kind's spare instances, else (none of either) one of the other kind. Its coins are rolled from
## its kind's `coins` (extra gold: only the start's barrels are held back from the creatures' coins). False when no slot.
func respawn_at(at: Vector3, kind) -> bool:
	var t := BarrelSpawns.TYPES.find(BarrelSpawns.kind_key(kind))
	var i := _slot_for(t)
	if i < 0:
		# pass 116: no slot of its kind: any other kind's
		for o in [0, 1, 2]:
			if o != t:
				i = _slot_for(o)
				if i >= 0:
					t = o
					break
	if i < 0:
		return false
	pos[i] = at
	alive[i] = 1
	# pass 137 (lane BARRELS): a new barrel in the slot: no hits, its own life, the grid stale
	shot_hits.erase(i)
	_anims.erase(i)
	_life[i] = int(_life.get(i, 0)) + 1
	_grid_dirty = true
	var r: Vector2i = contents(t)["coins"]
	coins[i] = _dice.randi_range(r.x, r.y) if r.y > 0 else 0
	var body := _mm_of(t)
	if body:
		body.set_instance_transform(_index_in[i], instance_transform(i, "body"))
	var props = map.get("props") if map else null
	if props is PropField:
		if shadows[i] >= 0:
			(props as PropField).move_shadow(shadows[i], at)
		else:
			shadows[i] = (props as PropField).add_shadow(at, SHADOW_W, SHADOW_D, SHADOW_A, SHADOW_TALL)
	respawned += 1
	return true


## A slot for a barrel of kind `t` (1 black): the first broken one of that kind, else a new one on a spare instance of
## its MultiMeshes (the arrays grow by one); -1 when there is neither.
func _slot_for(t: int) -> int:
	for k in pos.size():
		if alive[k] == 0 and light[k] == t:
			return k
	var body := _mm_of(t)
	if body == null or body.visible_instance_count >= body.instance_count:
		return -1
	var n := body.visible_instance_count
	body.visible_instance_count = n + 1
	pos.append(Vector3.ZERO)
	light.append(t)
	alive.append(0)
	coins.append(0)
	_index_in.append(n)
	shadows.append(-1)
	return pos.size() - 1
