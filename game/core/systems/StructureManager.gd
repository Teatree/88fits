## Scatters the map's structures (content/structures) at run start and runs their interaction: stand inside the ring
## for `interact_time` seconds and a draped pie fills up on the ground; leave and it drains. At full, the effect fires
## once and the structure goes grey. Positions avoid the start clearing, obstacles and each other, so finding them
## means crossing the map.
class_name StructureManager
extends Node3D

## The Strongbox's coin stream (pass 58, core/systems/CoinStream.gd; by path: a new script's class name is unknown until
## the editor imports it)
const COIN_STREAM := preload("res://core/systems/CoinStream.gd")
## Where the coins go into the Strongbox: this share of its painting's height up the picture (the lid's top is at 0.44 of
## st_gold_bank.png), and this far in front of it, so a coin drops onto the lid rather than through the picture
const LID := 0.4
const LID_TOWARD := 0.3
## The box's bounce as a coin drops in: a spring (stiffness, damping) kicked down by BOUNCE_KICK (less per coin the denser
## the stream, so a big deposit is a jiggle, not a jump), the squash it shows (BOUNCE_SQUASH of the spring's swing
## across), and a shine: a flicker of white over the painting, SHINE of it at a landing (less the denser the stream),
## gone at SHINE_FADE a second, so the box glints as each coin goes in and never stays washed out; the last coin kicks it
## LAST_KICK times as hard and shines LAST_SHINE
const BOUNCE_K := 420.0
const BOUNCE_DAMP := 16.0
const BOUNCE_KICK := 2.4
const BOUNCE_SQUASH := 0.55
const SHINE := 0.24
const SHINE_FADE := 6.0
const LAST_KICK := 1.8
const LAST_SHINE := 0.5
## The beat between the last coin in and the balloon lifting the box off (the lift's own wait before, pass 33)
const LIFT_BEAT := 0.35
## Pass 83: a Strongbox coming down has its whole shadow under it once it is this many metres up
const SHADOW_IN := 6.0
## A structure stands at least this far from any bush of the map's bush patches (pass 61, RedCanyon.bush_patches): a
## bush has no collider and so no obstacle circle to keep a ring off it, and a patch is a stretch of open ground the
## structures would otherwise favour
const BUSH_CLEAR := 3.0
## The returning Strongbox (pass 64, Garry: "the balloon structure ... actually returns every 30-60 seconds after it's
## used. It spawns in a random place ... fly down from the sky (basically a reverse of the fly away animation) ...
## Signs don't suddenly start showing direction towards the newly spawned Balloon"): a structure whose JSON has
## `params.respawn {min, max}` comes back that many seconds (a random draw, counted only while the run runs) after it has
## flown away, as a new box at a fresh spot (find_spot: the start's rules, plus the hero's surroundings, the water, the
## signposts, the live barrels and the paintings' cover bands), floating down under its balloon (DESCEND_TIME from
## DESCEND_HEIGHT up, swaying, slowing, then SETTLE_TIME onto the sand with a bump) and usable once it stands. One at a
## time: no second return is counted while one is due or the box that came back still stands unused. The signs chose
## their structures at the start and never look again, so no arm turns to it (the arm that pointed at the first box went
## blank when it was used, as before).
const DESCEND_HEIGHT := 18.0
const DESCEND_TIME := 4.5
const SETTLE_LIFT := 0.7       # the last stretch: from this high to the sand (the lift's first hop, the other way)
const SETTLE_TIME := 0.6
const SWAY := 0.14             # radians of roll at the top of the descent, dying away as it lands
const SWAY_RATE := 2.4
const RETURN_HERO_CLEAR := 20.0  # never lands within this of the hero
const RETURN_SIGN_CLEAR := 4.0
const RETURN_BARREL_CLEAR := 2.5
const RETURN_RETRY := 5.0      # no spot found (a crowded map): try again this much later
## Pass 73 (the Totem Poles, Garry: "There are always between 10-12 of them on the map"): a structure whose JSON has
## `params.per_map {min, max, spacing}` stands min..max times a run (a fresh count each run) apart from the weighted
## draw, spread over the map: each one the best of PER_MAP_CANDIDATES fair spots (the farthest from everything already
## standing), within the band PER_MAP_BAND of the arena's radius, off the dry river's bed (RIVER_CLEAR past its half
## width) and out of every painting's cover band.
const PER_MAP_CANDIDATES := 16
const PER_MAP_BAND := Vector2(0.24, 0.88)
const PER_MAP_TRIES := 500
const RIVER_CLEAR := 1.5
## the spent painting of a structure with `params.spent "grey"` (pass 73, the Totem Pole, Garry: "When used they turn
## gray as well, but they don't get 'destroyed'"): its own painting with the colour taken out, this much darker, a
## little flatter, and tinted by SPENT_GREY_TINT; made once per structure kind (_grey_cache)
const SPENT_GREY_BRIGHTNESS := 0.86
const SPENT_GREY_CONTRAST := 0.92
const SPENT_GREY_TINT := Color(0.93, 0.92, 0.92, 1.0)
static var _grey_cache: Dictionary = {}

var game: Node
var map: MapBase
var items: Array = []   # Structure nodes
## the coins flying into a Strongbox (pass 58): one CoinStream for every deposit
var coins: Node3D
var _rng := RandomNumberGenerator.new()
## the map's structure plan's spacing, kept for the returns
var _spacing := 16.0
## the Strongbox's return (pass 64): seconds until it comes (-1 = none due), what comes, and the box that came (landing
## or standing unused); `returns` counts the boxes that came back this run
var return_t := -1.0
var _return_def: StructureDef
var returner: Structure
var returns := 0


class Structure:
	extends Node3D
	var def: StructureDef
	var progress := 0.0
	var used := false
	var ring: MeshInstance3D
	var pie: MeshInstance3D
	## pass 81 (Garry: "The radial animation thing that plays under the structures has a black line. Can you remove
	## it."): the dark clock hand on the pie's leading edge is gone; the field stays (always null) for old tools and tests
	var hand: MeshInstance3D
	var glow: OmniLight3D
	var visual: Node3D
	var portal: MeshInstance3D     # the Teleport's swirl in its ring (params.portal)
	var portal_mat: ShaderMaterial
	var _t := 0.0
	var _last_frac := -1.0
	var _mote_t := 0.0
	## the Strongbox (pass 58): coins still flying into it, the lift waiting on them, leaving on its balloon, and its
	## bounce (a spring, its swing and speed) and shine while they land
	var streaming := false
	var lift_waiting := false
	var leaving := false
	var bounce := 0.0
	var bounce_v := 0.0
	var shine := 0.0
	var reacting := false
	## pass 64: floating down under its balloon (not usable until it stands), how long it has been, where its visual
	## rests and the drift it comes in on; `flown` once it has left on its balloon
	var arriving := false
	var arrive_t := 0.0
	var rest := Vector3.ZERO
	var drift := Vector3.ZERO
	var flown := false
	## pass 83 (lane SCENE): its ground shadow in the map's scenery shadows (PropField.add_shadow), -1 for none
	var shadow := -1


func setup(p_game: Node, p_map: MapBase, plan: Dictionary) -> void:
	game = p_game
	map = p_map
	_rng.randomize()
	# pass 77 (lane SIMRUN): a run sim's seed places them (Run.rng_seed; 0 in play: random as ever)
	if Run.rng_seed != 0:
		_rng.seed = hash([Run.rng_seed, "structures"])
	_make_coin_stream()
	var count := int(plan.get("count", 8))
	var spacing := float(plan.get("min_spacing", 16.0))
	_spacing = spacing
	var roster: Array = plan.get("roster", [])
	var defs: Array = []
	if roster.is_empty():
		defs = Registry.structures.values()
	else:
		for id in roster:
			var d: StructureDef = Registry.structure(str(id))
			if d:
				defs.append(d)
	defs = in_play(defs)
	# pass 73: the structures that stand their own count (params.per_map, the Totem Poles) come after the draw
	var apart := placed_apart(defs)
	defs = drawn(defs)
	if count <= 0 or (defs.is_empty() and apart.is_empty()):
		return
	var placed: Array = []
	if not defs.is_empty():
		# every kind appears at least once per run; the rest of the count is drawn by weight
		count = maxi(count, defs.size())
		var picks: Array = defs.duplicate()
		picks.shuffle()
		while picks.size() < count:
			picks.append(_pick(defs))
		var tries := 0
		# every kind must land: when the map fights back, the spacing relaxes rather than a structure being dropped
		while placed.size() < count and tries < count * 200:
			tries += 1
			var relax: float = 1.0 - 0.5 * clampf(float(tries) / float(count * 100), 0.0, 1.0)
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(map.arena_radius * 0.3, map.arena_radius * 0.86)
			var p := Vector3(cos(a) * r, 0, sin(a) * r)
			if not start_spot_ok(p, placed, spacing, relax):
				continue
			p.y = map.height_at(p.x, p.z)
			placed.append(p)
		for k in range(placed.size()):
			var def: StructureDef = picks[k]
			var _st := _spawn(def, placed[k])
		if placed.size() < defs.size():
			push_warning("StructureManager: placed %d of %d kinds" % [placed.size(), defs.size()])
	for d: StructureDef in apart:
		var _n := place_apart(d, placed)


## The structures of `defs` the weighted draw scatters (pass 73): every one without `params.per_map`.
static func drawn(defs: Array) -> Array:
	var out: Array = []
	for d: StructureDef in defs:
		if d != null and per_map_range(d) == Vector2i(-1, -1):
			out.append(d)
	return out


## The structures of `defs` that stand their own count apart from the draw (pass 73): every one with `params.per_map`.
static func placed_apart(defs: Array) -> Array:
	var out: Array = []
	for d: StructureDef in defs:
		if d != null and per_map_range(d) != Vector2i(-1, -1):
			out.append(d)
	return out


## How many of a structure stand on a map apart from the draw (pass 73): (min, max) from `params.per_map`, max never
## under min, neither under 0; (-1, -1) when it has none (it is drawn by weight).
static func per_map_range(d: StructureDef) -> Vector2i:
	var pm = d.params.get("per_map") if d != null else null
	if not pm is Dictionary:
		return Vector2i(-1, -1)
	var lo := maxi(int((pm as Dictionary).get("min", 1)), 0)
	var hi := maxi(int((pm as Dictionary).get("max", lo)), lo)
	return Vector2i(lo, hi)


## Stands a `params.per_map` structure its count of times (pass 73, PER_MAP_*): a fresh count in its range, each one at
## the best of PER_MAP_CANDIDATES fair spots (start_spot_ok against everything in `placed` at the structure's own
## `spacing`, relaxing to half as the tries run out; off the river's bed; out of the paintings' cover bands), the one
## farthest from everything standing. `placed` grows with each one. Returns how many stood.
func place_apart(def: StructureDef, placed: Array) -> int:
	var rng := per_map_range(def)
	if rng.y <= 0:
		return 0
	var n := _rng.randi_range(rng.x, rng.y)
	var spacing := own_spacing(def)
	var covers: Array = BarrelField.covers_of(game, map) if game else []
	var made := 0
	for k in range(n):
		var best := Vector3.INF
		var best_d := -1.0
		var found := 0
		var tries := 0
		while found < PER_MAP_CANDIDATES and tries < PER_MAP_TRIES:
			tries += 1
			var relax: float = 1.0 - 0.5 * clampf(float(tries) / float(PER_MAP_TRIES * 0.6), 0.0, 1.0)
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(map.arena_radius * PER_MAP_BAND.x, map.arena_radius * PER_MAP_BAND.y)
			var p := Vector3(cos(a) * r, 0, sin(a) * r)
			if not start_spot_ok(p, placed, spacing, relax) or not off_river(p):
				continue
			if BarrelField.in_cover(covers, Vector2(p.x, p.z), 1.0):
				continue
			found += 1
			var dmin := nearest_distance(p, placed)
			if dmin > best_d:
				best_d = dmin
				best = p
		if best == Vector3.INF:
			break
		best.y = map.height_at(best.x, best.z)
		placed.append(best)
		var s := _spawn(def, best)
		# its own painting's cover band, so the next one keeps out of it
		covers.append(Vector4(best.x, best.z, BarrelField.STRUCTURE_HALF_W, def.height / tan(deg_to_rad(BarrelField.CAMERA_PITCH_DEG))))
		if s:
			made += 1
	if made < rng.x:
		push_warning("StructureManager: placed %d of %d %s" % [made, rng.x, def.id])
	return made


## A per-map structure's own spacing (`params.per_map.spacing`), the map's when it names none.
func own_spacing(d: StructureDef) -> float:
	var pm = d.params.get("per_map") if d != null else null
	return float((pm as Dictionary).get("spacing", _spacing)) if pm is Dictionary else _spacing


## The flat distance from `p` to the nearest of `placed` (INF when there is none).
static func nearest_distance(p: Vector3, placed: Array) -> float:
	var best := INF
	for q: Vector3 in placed:
		best = minf(best, Vector2(p.x - q.x, p.z - q.z).length())
	return best


## Whether `p` keeps off the map's dry river bed (pass 73: the Totem Poles stand beside the paths, never in their
## middle): RIVER_CLEAR past the bed's half width from the river's line (RedCanyon.river_points); true on a map without
## a river.
func off_river(p: Vector3) -> bool:
	if map == null or not map.has_method("river_points"):
		return true
	var pts: Array = map.call("river_points")
	var half: float = float(map.get("river_width")) * 0.5 if map.get("river_width") != null else 3.0
	return river_distance(Vector2(p.x, p.z), pts) >= half + RIVER_CLEAR


## The flat distance from `p` to a polyline of Vector2 points (INF with fewer than two).
static func river_distance(p: Vector2, pts: Array) -> float:
	var best := INF
	for k in range(pts.size() - 1):
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


## The structures that may stand on a map (pass 70, Garry: "Remove the Balloon Chest thing now"): every one but a
## `hidden` one (the retired Strongbox, gold_bank), whether the map names a roster or takes them all. A hidden structure
## keeps its content folder and its effect's code; it never spawns, so it never returns either.
static func in_play(defs: Array) -> Array:
	var out: Array = []
	for d: StructureDef in defs:
		if d != null and not d.hidden:
			out.append(d)
	return out


## The start's rules for a structure at `p` (shared with the returns, pass 64): clear of the flats (18 m), of every spot
## in `placed` by `spacing`, of the obstacle circles by 3.5 m, of the bushes and (pass 64) of the water by 3 m; `relax`
## shrinks the distances as the tries run out.
func start_spot_ok(p: Vector3, placed: Array, spacing: float, relax: float = 1.0) -> bool:
	var fc := map.flats_center
	if Vector2(p.x - fc.x, p.z - fc.z).length() < 18.0 * relax:
		return false
	for q: Vector3 in placed:
		if Vector2(p.x - q.x, p.z - q.z).length() < spacing * relax:
			return false
	for o: Vector3 in map.obstacles:
		if Vector2(p.x - o.x, p.z - o.y).length() < o.z + 3.5:
			return false
	if map.has_method("bush_patches") and not clear_of_bushes(Vector2(p.x, p.z), map.call("bush_patches")):
		return false
	if _wet(p, 3.0):
		return false
	return true


## In the water, or within `r` of it (its middle and four points round `p`)?
func _wet(p: Vector3, r: float) -> bool:
	if not map.has_method("in_water"):
		return false
	for o: Vector3 in [Vector3.ZERO, Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, 0, r), Vector3(0, 0, -r)]:
		if map.in_water(p + o):
			return true
	return false


## A fresh spot for a returning structure (pass 64): random over the start's band (0.3 to 0.86 of the arena's radius),
## the start's rules against every structure still standing, and clear of the hero (RETURN_HERO_CLEAR), the signposts,
## the live barrels and every painting's cover band (so the box is never hidden behind a cactus). The spacing relaxes to
## half as the tries run out, like the start's. Vector3.INF when the map has no room.
func find_spot() -> Vector3:
	var standing: Array = []
	# pass 73: a structure standing its own count (a Totem Pole) is kept at its own spacing, not the map's
	var apart_at: Array = []
	for st: Structure in items:
		if is_instance_valid(st) and not st.flown and not st.leaving:
			if per_map_range(st.def) == Vector2i(-1, -1):
				standing.append(st.global_position)
			else:
				apart_at.append(Vector4(st.global_position.x, st.global_position.z, own_spacing(st.def), 0.0))
	var hero := Vector3.INF
	if game and game.get("player") and is_instance_valid(game.player):
		hero = game.player.global_position
	var signs: Array = []
	var sf = game.get_node_or_null("Signs") if game else null
	if sf and sf.get("spots") is Array:
		signs = sf.spots
	var barrels = game.get("barrels") if game else null
	var covers: Array = BarrelField.covers_of(game, map) if game else []
	var tries := 600
	for k in range(tries):
		var relax: float = 1.0 - 0.5 * clampf(float(k) / (float(tries) * 0.5), 0.0, 1.0)
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(map.arena_radius * 0.3, map.arena_radius * 0.86)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if not start_spot_ok(p, standing, _spacing, relax):
			continue
		if hero != Vector3.INF and Vector2(p.x - hero.x, p.z - hero.z).length() < RETURN_HERO_CLEAR:
			continue
		var ok := true
		for q: Vector4 in apart_at:
			if Vector2(p.x - q.x, p.z - q.y).length() < q.z * relax:
				ok = false
				break
		for q: Vector3 in signs:
			if Vector2(p.x - q.x, p.z - q.z).length() < RETURN_SIGN_CLEAR:
				ok = false
				break
		if ok and barrels is BarrelField:
			var bf := barrels as BarrelField
			for i in bf.pos.size():
				if bf.alive[i] != 0 and Vector2(p.x - bf.pos[i].x, p.z - bf.pos[i].z).length() < RETURN_BARREL_CLEAR:
					ok = false
					break
		if ok and BarrelField.in_cover(covers, Vector2(p.x, p.z), 1.5):
			ok = false
		if not ok:
			continue
		p.y = map.height_at(p.x, p.z)
		return p
	return Vector3.INF


## Whether a structure at `p` (x, z) keeps BUSH_CLEAR from every bush of `patches` (RedCanyon.bush_patches, pass 61).
static func clear_of_bushes(p: Vector2, patches: Array) -> bool:
	for bp: Dictionary in patches:
		for b: Dictionary in bp["bushes"]:
			if p.distance_to(b["pos"]) < BUSH_CLEAR:
				return false
	return true


func _pick(defs: Array) -> StructureDef:
	var total := 0.0
	for d: StructureDef in defs:
		total += maxf(d.weight, 0.01)
	var x := _rng.randf() * total
	for d: StructureDef in defs:
		x -= maxf(d.weight, 0.01)
		if x <= 0.0:
			return d
	return defs[0]


func _spawn(def: StructureDef, at: Vector3) -> Structure:
	var s := Structure.new()
	s.def = def
	add_child(s)
	s.global_position = at
	# the landmark itself
	# painted first (art/sprites/props/st_<id>.png, a billboard like the scenery), the Blender prop if there is no painting
	var sprite_path := "res://art/sprites/props/st_%s.png" % def.id
	var path := "res://art/props/%s.glb" % def.prop
	if ResourceLoader.exists(sprite_path):
		var bs := BillboardSprite.new()
		# pass 72: scenery (a creature it hides is outlined, SceneryStencil)
		bs.scenery = true
		s.visual = bs
		s.add_child(bs)
		bs.setup(load(sprite_path), {"idle": 1}, ["idle"], def.height * 1.15)
		# one frame: nothing to play (pass 73: a dozen Totem Poles no longer set their frame every frame)
		bs.playing = false
		bs.position.y = 0.04
		if def.params.get("portal") is Dictionary:
			_add_portal(s, def.params["portal"], def.height * 1.15, def.color)
	else:
		if def.prop != "" and ResourceLoader.exists(path):
			s.visual = (load(path) as PackedScene).instantiate()
		else:
			s.visual = _fallback_visual(def)
		SceneryStencil.mark_tree(s.visual)
		s.add_child(s.visual)
		s.visual.rotation.y = _rng.randf() * TAU
	_add_shadow(s, def, at)
	# the ring on the ground, in the structure's colour, always visible until used
	var tg: Telegraphs = game.telegraphs
	s.ring = MeshInstance3D.new()
	s.ring.mesh = tg.draped_ring(at, def.radius - 0.22, def.radius)
	s.ring.material_override = _mat(def.color, 0.75)
	s.ring.top_level = true
	add_child(s.ring)
	s.pie = MeshInstance3D.new()
	s.pie.material_override = _mat(def.color, 0.62)
	s.pie.top_level = true
	s.pie.visible = false
	add_child(s.pie)
	# pass 73: `params.glow` false leaves the light off (the dozen Totem Poles: their ring shows them)
	if Fx.want_lights() and bool(def.params.get("glow", true)):
		s.glow = OmniLight3D.new()
		s.glow.light_color = def.color
		s.glow.omni_range = 5.0
		s.glow.light_energy = 1.1
		s.glow.position.y = def.height * 0.7
		s.add_child(s.glow)
	items.append(s)
	return s


## The Teleport's portal (pass 35): a spiral turning in the ring's hole, standing up to the camera like the painting and a
## little behind it, so the stone covers its edge. `cfg` is where the hole is in the painting, as fractions of its
## square: {x, y (from the top), r}; `side` is the painting's side in metres.
func _add_portal(s: Structure, cfg: Dictionary, side: float, color: Color) -> void:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	q.mesh = qm
	q.custom_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 8, 8))
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = preload("res://core/shaders/swirl.gdshader")
	m.set_shader_parameter("billboard", 1.0)
	m.set_shader_parameter("size", 2.0 * float(cfg.get("r", 0.2)) * side * 1.08)
	m.set_shader_parameter("lift", (1.0 - float(cfg.get("y", 0.45))) * side + 0.04)
	m.set_shader_parameter("shift", (float(cfg.get("x", 0.5)) - 0.5) * side)
	m.set_shader_parameter("push", 0.08)
	m.set_shader_parameter("color_a", Color(color.r * 0.45, color.g * 0.2, color.b * 0.6, 0.85))
	m.set_shader_parameter("color_b", Color(color.r, color.g, color.b, 0.95))
	m.set_shader_parameter("color_eye", Color(1.0, 0.92, 1.0, 0.95))
	m.set_shader_parameter("eye", 0.22)
	m.set_shader_parameter("arms", 4.0)
	m.set_shader_parameter("twist", 1.4)
	m.set_shader_parameter("speed", 2.2)
	q.material_override = m
	s.add_child(q)
	s.portal = q
	s.portal_mat = m


## Pass 83 (lane SCENE; Garry: "barrels, signs, and structures too. Want them to feel like they are part of the world"):
## a structure stands on a ground shadow in the map's scenery shadows (PropField.add_shadow), measured from its painting
## like a prop's (props.json `st_<id>` `shadow`, shares of the drawn painting's height, def.height x 1.15), or the default
## shares for a model; it shrinks away as the Strongbox lifts off and grows back under one coming down (shadow_k).
func _add_shadow(s: Structure, def: StructureDef, at: Vector3) -> void:
	var props = map.get("props") if map else null
	if not props is PropField:
		return
	var pf := props as PropField
	var h := def.height * 1.15
	var sh := pf.shadow_of("st_" + def.id)
	s.shadow = pf.add_shadow(at + Vector3(float(sh["x"]) * h, 0.0, float(sh["z"]) * h), float(sh["w"]) * h, float(sh["d"]) * h, float(sh["a"]), h)


## Structure `s`'s shadow at `k` of its size (1 standing, 0 gone) under where it stands.
func shadow_k(s: Structure, k: float) -> void:
	var props = map.get("props") if map else null
	if s.shadow < 0 or not props is PropField:
		return
	var pf := props as PropField
	var h := s.def.height * 1.15
	var sh := pf.shadow_of("st_" + s.def.id)
	pf.move_shadow(s.shadow, s.global_position + Vector3(float(sh["x"]) * h, 0.0, float(sh["z"]) * h), clampf(k, 0.0, 1.0))


func _mat(color: Color, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## A stand-in when the GLB is missing: a plinth with a coloured shape on top, so the game never breaks on art.
func _fallback_visual(def: StructureDef) -> Node3D:
	var root := Node3D.new()
	var plinth := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.8
	cm.bottom_radius = 1.0
	cm.height = 0.5
	plinth.mesh = cm
	plinth.position.y = 0.25
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.45, 0.42, 0.4)
	plinth.material_override = pm
	root.add_child(plinth)
	var top := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, def.height - 0.5, 0.9)
	top.mesh = bm
	top.position.y = 0.5 + (def.height - 0.5) * 0.5
	var tm := StandardMaterial3D.new()
	tm.albedo_color = def.color
	tm.emission_enabled = true
	tm.emission = def.color
	tm.emission_energy_multiplier = 0.4
	top.material_override = tm
	root.add_child(top)
	return root


func _process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	# a Strongbox taking coins bounces and shines whatever the hero is doing (pass 58)
	for s: Structure in items:
		if s.reacting:
			_tick_bounce(s, delta)
	if game == null or game.paused or game.player == null or game.player.dead:
		Perf.add("structures", _t0)
		return
	var pp: Vector3 = game.player.global_position
	var tg: Telegraphs = game.telegraphs
	for s: Structure in items:
		if s.arriving:
			_tick_descend(s, delta)
			continue
		if s.used:
			continue
		s._t += delta
		var d: float = Vector2(pp.x - s.global_position.x, pp.z - s.global_position.z).length()
		var inside: bool = d < s.def.radius
		if inside:
			s.progress = minf(s.progress + delta / maxf(s.def.interact_time, 0.1), 1.0)
		else:
			s.progress = maxf(s.progress - delta * 0.6, 0.0)
		# the ring breathes; the pie shows how far along the hero is
		var rm := s.ring.material_override as StandardMaterial3D
		rm.albedo_color.a = 0.55 + 0.3 * absf(sin(s._t * 2.5))
		if s.glow:
			s.glow.light_energy = 0.9 + 0.5 * absf(sin(s._t * 2.5)) + (1.5 if inside else 0.0)
		if s.progress > 0.0:
			var frac := snappedf(s.progress, 0.02)
			if frac != s._last_frac:
				s._last_frac = frac
				s.pie.mesh = tg.draped_sector(s.global_position, s.def.radius * 0.96, frac)
			s.pie.visible = true
		else:
			s.pie.visible = false
		if s.portal_mat:
			_tick_portal(s, delta, inside, d)
		if s.progress >= 1.0:
			_use(s)
	# after the loop: a box brought back now starts its descent on the next frame
	_tick_return(delta)
	Perf.add("structures", _t0)


## The portal breathes and turns, faster and brighter as the hero charges it, and throws sparks up out of the ring.
func _tick_portal(s: Structure, delta: float, inside: bool, dist: float) -> void:
	var p := s.progress
	s.portal_mat.set_shader_parameter("speed", lerpf(2.2, 10.0, p))
	s.portal_mat.set_shader_parameter("energy", 1.0 + 0.9 * p + 0.12 * sin(s._t * 5.0))
	s.portal_mat.set_shader_parameter("alpha", 0.9 + 0.1 * sin(s._t * 3.0))
	if dist > 26.0:
		return
	s._mote_t -= delta
	if s._mote_t <= 0.0:
		s._mote_t = 0.05 if inside else 0.16
		var a := randf() * TAU
		var at: Vector3 = s.global_position + Vector3(cos(a) * s.def.radius * 0.8, 0.15, sin(a) * s.def.radius * 0.8)
		var col: Color = s.def.color
		game.fx.mote(at, Vector3(-cos(a) * 0.6, randf_range(1.6, 2.6) * (1.6 if inside else 1.0), -sin(a) * 0.6), 0.9, 0.18, Color(col.r, col.g, col.b, 0.9))


func _use(s: Structure) -> void:
	s.used = true
	s.pie.visible = false
	# pass 82 (lane TOTEM): a structure with `params.spent_motion` (the Totem Pole) keeps its paint and its ring while its
	# screen is up; the game greys it when the gift is taken (spend_slowly), as the screen closes
	if s.def.params.get("spent_motion") is Dictionary and str(s.def.params.get("spent", "")) == "grey":
		game.use_structure(s.def, s.global_position)
		return
	s.ring.visible = false
	if s.portal:
		s.portal.visible = false
	if s.glow:
		s.glow.light_energy = 0.0
	# the spent painting (art/sprites/props/st_<id>_off.png) when there is one, a grey tint otherwise; a prop with
	# params.spent "fly_away" leaves on its balloon instead, once what it was given is in (pass 58: the Strongbox's
	# coins, so the game is told first: its deposit starts the coin stream the lift waits for)
	var off_path := "res://art/sprites/props/st_%s_off.png" % s.def.id
	var flies := str(s.def.params.get("spent", "")) == "fly_away"
	if not flies:
		if s.visual is BillboardSprite and ResourceLoader.exists(off_path):
			(s.visual as BillboardSprite).set_texture(load(off_path))
			(s.visual as BillboardSprite).set_tint(Color(0.8, 0.78, 0.78, 1.0))
		elif s.visual is BillboardSprite and str(s.def.params.get("spent", "")) == "grey" and grey_painting(s.def) != null:
			# pass 73 (the Totem Pole): its own painting in grey, standing where it stood
			(s.visual as BillboardSprite).set_texture(grey_painting(s.def))
			(s.visual as BillboardSprite).set_tint(SPENT_GREY_TINT)
		else:
			_grey_out(s.visual)
	game.use_structure(s.def, s.global_position)
	if flies:
		_fly_away(s)


## The Strongbox's exit: once the coins are in (pass 58: the lift waits for the stream, deposit), the balloon lifts it.
func _fly_away(s: Structure) -> void:
	if s.streaming:
		s.lift_waiting = true
		return
	_lift(s)


## The balloon lifts the painted box off the sand (pass 33): a beat, then up, slow at first, and it drifts up and away over
## the canyon until it is gone. The gold is safe whatever happens next.
func _lift(s: Structure) -> void:
	s.lift_waiting = false
	s.leaving = true
	var v := s.visual
	if v == null:
		return
	game.fx_burst(s.global_position + Vector3(0, 0.9, 0), Color(1.0, 0.85, 0.35), 1.2)
	var start := v.position
	var drift := Vector3(_rng.randf_range(-2.5, 2.5), 18.0, _rng.randf_range(-6.0, -3.0))
	var tw := v.create_tween()
	tw.tween_interval(0.45)
	tw.tween_property(v, "position", start + Vector3(0, 0.7, 0), 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(v, "position", start + drift, 4.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(v, "rotation:y", v.rotation.y + 1.4, 4.5)
	tw.tween_callback(v.hide)
	tw.tween_callback(func() -> void: _on_flown(s))
	# pass 83: its shadow shrinks away as it rises
	var stw := s.create_tween()
	stw.tween_interval(0.45)
	stw.tween_method(func(k: float) -> void: shadow_k(s, k), 1.0, 0.0, 2.2).set_ease(Tween.EASE_IN)


# ---------------------------------------------------------------- the Strongbox comes back (pass 64)

## The box is gone over the canyon: a structure with `params.respawn` sets its return going, unless one is already due
## or the box that came back still stands unused.
func _on_flown(s: Structure) -> void:
	s.flown = true
	var rp = s.def.params.get("respawn")
	if not rp is Dictionary:
		return
	if return_t >= 0.0:
		return
	if returner != null and is_instance_valid(returner) and returner != s and not returner.used:
		return
	var lo := maxf(float((rp as Dictionary).get("min", 30.0)), 0.0)
	var hi := maxf(float((rp as Dictionary).get("max", 60.0)), lo)
	return_t = _rng.randf_range(lo, hi)
	_return_def = s.def


## The return's clock: counted only while the run runs (called from _process past its pause check).
func _tick_return(delta: float) -> void:
	if return_t < 0.0:
		return
	return_t -= delta
	if return_t <= 0.0:
		return_t = -1.0
		bring_back()


## A new box of the kind that flew off at a fresh spot, floating down from the sky. Returns it (null with no spot: tried
## again RETURN_RETRY seconds later).
func bring_back() -> Structure:
	var def: StructureDef = _return_def
	if def == null:
		return null
	var at := find_spot()
	if at == Vector3.INF:
		return_t = RETURN_RETRY
		return null
	var s := _spawn(def, at)
	returner = s
	returns += 1
	_descend(s)
	# a quiet word when it comes down out of sight (on the screen the box says it itself)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var hud = game.get("hud") if game else null
	if hud and hud.has_method("toast") and (cam == null or not _on_screen(cam, at)):
		hud.toast("A STRONGBOX DRIFTS DOWN", Color(1.0, 0.85, 0.35))
	return s


func _on_screen(cam: Camera3D, at: Vector3) -> bool:
	if cam.is_position_behind(at):
		return false
	return get_viewport().get_visible_rect().has_point(cam.unproject_position(at))


## The fly-away in reverse: the box starts DESCEND_HEIGHT up on the drift it would have left on, its ring, pie and glow
## hidden until it stands.
func _descend(s: Structure) -> void:
	s.arriving = true
	s.arrive_t = 0.0
	s.ring.visible = false
	if s.glow:
		s.glow.light_energy = 0.0
	if s.visual:
		s.rest = s.visual.position
		s.drift = Vector3(_rng.randf_range(-2.5, 2.5), DESCEND_HEIGHT, _rng.randf_range(-6.0, -3.0))
		s.visual.position = descend_offset(s, 0.0)
	shadow_k(s, 0.0)


## Where the box's visual hangs `t` seconds into its arrival (its resting position at the end): DESCEND_TIME coming down
## the drift, slowing all the way (the lift's ease-in, reversed), to SETTLE_LIFT over its spot, then SETTLE_TIME easing
## onto the sand.
static func descend_offset(s: Structure, t: float) -> Vector3:
	var hop := Vector3(0, SETTLE_LIFT, 0)
	if t < DESCEND_TIME:
		var u := 1.0 - t / DESCEND_TIME
		return s.rest + hop + s.drift * (u * u)
	var q := clampf((t - DESCEND_TIME) / SETTLE_TIME, 0.0, 1.0)
	var e := 0.5 - 0.5 * cos(q * PI)
	return s.rest + hop * (1.0 - e)


## The sway as it comes down: a slow roll under the balloon, dying away by the time it lands.
static func descend_roll(t: float) -> float:
	if t >= DESCEND_TIME:
		return 0.0
	return SWAY * sin(t * SWAY_RATE) * (1.0 - t / DESCEND_TIME)


func _tick_descend(s: Structure, delta: float) -> void:
	s.arrive_t += delta
	var v := s.visual
	if v:
		v.position = descend_offset(s, s.arrive_t)
		if v is BillboardSprite:
			(v as BillboardSprite).set_roll(descend_roll(s.arrive_t))
	# pass 83: the shadow grows in under it as it comes down (full by the time it is SHADOW_IN metres up)
	if v:
		shadow_k(s, 1.0 - clampf((v.position.y - s.rest.y) / SHADOW_IN, 0.0, 1.0))
	if s.arrive_t >= DESCEND_TIME + SETTLE_TIME:
		_land(s)


## It stands: a bump, a puff of sand and a flash of its ring, and it is a Strongbox like any other.
func _land(s: Structure) -> void:
	s.arriving = false
	if s.visual:
		s.visual.position = s.rest
		if s.visual is BillboardSprite:
			(s.visual as BillboardSprite).set_roll(0.0)
	shadow_k(s, 1.0)
	s.ring.visible = true
	s.bounce_v -= BOUNCE_KICK * 1.4
	s.reacting = true
	if game:
		if game.get("telegraphs"):
			game.telegraphs.flash_ring(s.global_position, s.def.radius + 0.4, s.def.color, 0.4)
		if game.get("fx"):
			for k in 4:
				var a := TAU * float(k) / 4.0
				game.fx.sand(s.global_position + Vector3(cos(a) * 0.8, 0.1, sin(a) * 0.8), 1.0)


## The coin stream (pass 58), made once at setup and warmed (its coin drawn under the map while the run starts).
func _make_coin_stream() -> void:
	if coins != null:
		return
	coins = COIN_STREAM.new()
	coins.name = "CoinStream"
	coins.game = game
	coins.map = map
	add_child(coins)
	coins.warm()


## The Strongbox's deposit (pass 58, Game.use_structure's "bank", Garry: "coins flying out of the player and into the
## chest ... After the coins arrive the chest flies away"): `gold` flies from the hero into the box standing at `at`
## (CoinStream), the box bouncing and shining as each coin drops in, and the balloon lifts it only once the last is in
## (_fly_away waits). Returns the stream's seconds; 0 when there is nothing to show (no gold, no box there).
func deposit(at: Vector3, gold: int) -> float:
	if gold <= 0:
		return 0.0
	_make_coin_stream()
	var s := _structure_at(at)
	if s == null:
		return 0.0
	var hero: Node3D = game.player if game and game.get("player") else null
	var dur: float = coins.start(hero, _lid_point(s), gold, func(landed: int, count: int) -> void: _on_coin(s, landed, count),
		func() -> void: _on_stream_done(s))
	if dur > 0.0:
		s.streaming = true
	return dur


## The structure standing at `at` (the spot use_structure was given).
func _structure_at(at: Vector3) -> Structure:
	var best: Structure = null
	var best_d := 0.25
	for s: Structure in items:
		var d := Vector2(s.global_position.x - at.x, s.global_position.z - at.z).length()
		if d < best_d:
			best_d = d
			best = s
	return best


## Where the coins go in: the box's lid on its painting (camera-facing, standing on its feet), a little in front of it;
## the middle of a 3D stand-in.
func _lid_point(s: Structure) -> Vector3:
	if s.visual is BillboardSprite:
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		var up: Vector3 = cam.global_transform.basis.y.normalized() if cam else Vector3.UP
		var back: Vector3 = cam.global_transform.basis.z.normalized() if cam else Vector3.BACK
		var foot := s.global_position + Vector3(0.0, s.visual.position.y, 0.0)
		return foot + up * (LID * s.def.height * 1.15) + back * LID_TOWARD
	return s.global_position + Vector3(0.0, s.def.height * 0.5, 0.0)


## A coin dropped in: the box gives a little bounce and a shine (the last one a bigger one).
func _on_coin(s: Structure, landed: int, count: int) -> void:
	var dense: float = clampf(sqrt(float(count)) / 4.0, 1.0, 3.0)
	var kick := BOUNCE_KICK / dense
	if landed >= count:
		kick = BOUNCE_KICK * LAST_KICK
	s.bounce_v -= kick
	s.shine = maxf(s.shine, LAST_SHINE if landed >= count else SHINE / dense)
	s.reacting = true


func _on_stream_done(s: Structure) -> void:
	s.streaming = false
	if s.lift_waiting:
		get_tree().create_timer(LIFT_BEAT, false).timeout.connect(func() -> void:
			if is_instance_valid(s):
				_lift(s))


## The Strongbox's spring and shine: squashed wide and short as a coin lands, springing back; settles and stops.
func _tick_bounce(s: Structure, delta: float) -> void:
	var dt := minf(delta, 0.05)
	s.bounce_v += (-BOUNCE_K * s.bounce - BOUNCE_DAMP * s.bounce_v) * dt
	s.bounce += s.bounce_v * dt
	s.shine = maxf(s.shine - SHINE_FADE * dt, 0.0)
	var sy := 1.0 + s.bounce
	var sx := 1.0 - s.bounce * BOUNCE_SQUASH
	if s.visual is BillboardSprite:
		(s.visual as BillboardSprite).set_squash(sx, sy)
		(s.visual as BillboardSprite).set_flash(s.shine)
	elif s.visual:
		s.visual.scale = Vector3(sx, sy, sx)
	if s.shine <= 0.0 and absf(s.bounce) < 0.002 and absf(s.bounce_v) < 0.02:
		s.reacting = false
		s.bounce = 0.0
		s.bounce_v = 0.0
		if s.visual is BillboardSprite:
			(s.visual as BillboardSprite).set_squash(1.0, 1.0)
			(s.visual as BillboardSprite).set_flash(0.0)
		elif s.visual:
			s.visual.scale = Vector3.ONE


## A structure's painting with the colour taken out (pass 73, `params.spent "grey"`): art/sprites/props/st_<id>.png as an
## image, desaturated, SPENT_GREY_BRIGHTNESS darker and SPENT_GREY_CONTRAST flatter, made once per kind and kept; null
## when the painting is missing or its pixels cannot be read (the tint grey-out then stands in).
static func grey_painting(def: StructureDef) -> Texture2D:
	if def == null:
		return null
	if _grey_cache.has(def.id):
		return _grey_cache[def.id]
	var path := "res://art/sprites/props/st_%s.png" % def.id
	var out: Texture2D = null
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		var img: Image = tex.get_image() if tex else null
		if img != null and not img.is_empty():
			img = img.duplicate() as Image
			if img.is_compressed():
				img.decompress()
			if img.get_format() != Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGBA8)
			img.adjust_bcs(SPENT_GREY_BRIGHTNESS, SPENT_GREY_CONTRAST, 0.0)
			out = ImageTexture.create_from_image(img)
	_grey_cache[def.id] = out
	return out


func _grey_out(n: Node) -> void:
	if n is BillboardSprite:
		(n as BillboardSprite).set_tint(Color(0.45, 0.42, 0.42, 1.0))
		return
	if n is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.42, 0.4, 0.4)
		mat.roughness = 1.0
		(n as MeshInstance3D).material_override = SceneryStencil.mark(mat)
	for c in n.get_children():
		_grey_out(c)


# ---------------------------------------------------------------- a Totem Pole's motion (pass 82, lane TOTEM)
## design_handoff_88fits_totem (README "Motion"): the pie completes, the in-world ring flashes turquoise (`spent_motion`
## `flash` seconds) and the gift screen comes up over the pole still in its paint; the gift taken, the pole drains to
## grey over `fade` seconds and its ring fades, ending in the grey painting it has stood in since pass 73. Run while the
## game is paused behind the screen (the tweens process through the pause).

## The flash on the ring of the structure standing at `at` (the gift screen opening).
func flash_ring(at: Vector3) -> void:
	var s := _structure_at(at)
	if s == null or s.ring == null:
		return
	var secs := float((s.def.params.get("spent_motion", {}) as Dictionary).get("flash", 0.12))
	var rm := s.ring.material_override as StandardMaterial3D
	if rm == null or secs <= 0.0:
		return
	s.ring.visible = true
	var base := Color(s.def.color.r, s.def.color.g, s.def.color.b, 0.75)
	var hot := Color(s.def.color.lerp(Color.WHITE, 0.55), 1.0)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(rm, "albedo_color", hot, secs * 0.4)
	tw.tween_property(rm, "albedo_color", base, secs * 0.6)


## The structure standing at `at` spent: its painting drained to grey over `seconds` (spent_motion `fade` when -1; 0 at
## once), its ring faded, then the grey painting and tint of a used pole (the end state is pass 73's).
func spend_slowly(at: Vector3, seconds: float = -1.0) -> void:
	var s := _structure_at(at)
	if s == null:
		return
	var secs := seconds
	if secs < 0.0:
		secs = float((s.def.params.get("spent_motion", {}) as Dictionary).get("fade", 0.4))
	var bs := s.visual as BillboardSprite
	var grey := grey_painting(s.def)
	var rm: StandardMaterial3D = null
	if s.ring:
		rm = s.ring.material_override as StandardMaterial3D
	var finish := func() -> void:
		if not is_instance_valid(s):
			return
		if s.ring:
			s.ring.visible = false
		if bs and grey:
			bs.set_texture(grey)
			bs.set_desat(0.0)
			bs.set_tint(SPENT_GREY_TINT)
		elif s.visual:
			_grey_out(s.visual)
	if secs <= 0.0 or bs == null:
		finish.call()
		return
	# drained of colour and darkened towards the grey painting's brightness, then the painting itself
	var end_tint := Color(SPENT_GREY_TINT.r * SPENT_GREY_BRIGHTNESS, SPENT_GREY_TINT.g * SPENT_GREY_BRIGHTNESS,
		SPENT_GREY_TINT.b * SPENT_GREY_BRIGHTNESS, 1.0)
	var tw := create_tween().set_parallel(true)
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_method(func(v: float) -> void:
		if is_instance_valid(bs):
			bs.set_desat(v)
			bs.set_tint(Color.WHITE.lerp(end_tint, v)), 0.0, 1.0, secs)
	if rm:
		var from := rm.albedo_color
		tw.tween_property(rm, "albedo_color", Color(from.r, from.g, from.b, 0.0), secs)
	tw.chain().tween_callback(finish)


## How many structures of kind `id` stand on the map (the Totem screen's "TOTEM 4 OF 11").
func count_of(id: String) -> int:
	var n := 0
	for s: Structure in items:
		if s.def and s.def.id == id:
			n += 1
	return n


func used_count() -> int:
	var n := 0
	for s: Structure in items:
		if s.used:
			n += 1
	return n
