## Red Canyon. Nothing here is a 3D prop: the ground (dunes, one sunken dry river, two or three oasis lakes, a flat centre, a
## red-rock rim), a rugged mountain wall around the arena with ranges beyond it, and painted 2.5D scenery, structures,
## tumbleweeds and a dust devil on top. The layout rolls per run (Run.map_seed): the river's course, the lakes' places,
## the dunes and where the scenery stands; the wall, the flats and the rim never move. Every number here is a tunable
## exported for the editor.
extends MapBase

@export var seed := 88
@export var dune_height := 1.5
@export var river_depth := 2.0
@export var river_width := 6.0
@export var flats_radius := 16.0
## The ground's flat tones (pass 54): the painted terrain shader mixes its textures towards these (`calm`), so they are
## the knob for the sand's and the river bed's colour; a little lighter and less orange than before (Garry).
## Pass 61 (Garry): the sand even lighter (was 0.88, 0.72, 0.48), and the dry river no longer the old brown (was 0.66, 0.50,
## 0.36) but "a slightly browner shade of the generic desert colour": the sand's hue a touch redder, a step darker and
## a little more saturated, so it reads as the same sand gone damp and packed (its course, banks and depth unchanged)
@export var sand_color := Color(0.90, 0.78, 0.58)
@export var river_color := Color(0.80, 0.67, 0.50)
@export var wall_color := Color(0.56, 0.31, 0.17)
## Tumbleweeds are hidden since pass 44 (Garry: no more of them, the gusts carry the desert now); the feature stays.
@export var tumbleweeds := 0
@export var lake_depth := 0.45
## The Oasis disc (pass 56: _build_lake draws it, water_disc tells it): its radius over the lake's, and its thickness
const LAKE_DISC := 1.06
const LAKE_THICK := 0.08
## Bush patches (pass 61, Garry: "Add another type of a patch of greenery. This one containing only bushes, make the bush
## distribution quite sparse, but the patch itself should be more frequent then the trees one. None of the bushes have
## collision."): this many patches a run (the green stands are three, cactus or trees), each a few bushes spread thin over
## BUSH_PATCH_R metres with open sand between (no two closer than BUSH_SPACING + 0.6 m), its centre BUSH_PATCH_APART from
## any other region's. Every id here has radius 0 in props.json: walked through, no collider, no obstacle circle.
const BUSH_PATCHES := Vector2i(5, 7)
const BUSH_PER_PATCH := Vector2i(4, 6)
const BUSH_PATCH_R := 7.0
const BUSH_SPACING := 1.9
const BUSH_PATCH_APART := 18.0
## Pass 83 (lane SCENE; Garry: "another small bushlike thing"): the brittlebush joins them (a pick draws once whatever
## the table, so every seed keeps its spots; only which bush stands on one changes).
const BUSH_IDS := [["desert_bush", 3.0], ["creosote_bush", 3.0], ["dead_shrub", 2.0], ["brittlebush", 2.0]]
## Pass 80 (lane OASIS): a patch keeps its centre 11 m + 0.6 of its radius off every lake's water (clear of the oasis's
## greenery); past BUSH_LAKE_RELAX of its 300 tries only BUSH_LAKE_NEAR m + 0.6 of its radius; a map still short of
## BUSH_PATCHES.x patches gets BUSH_EXTRA_TRIES more for each, out to 10 m inside the wall and the regions 0.6 of
## BUSH_PATCH_APART apart, so three oases still leave room for five patches (200 seeds checked).
const BUSH_LAKE_RELAX := 200
const BUSH_LAKE_NEAR := 6.0
const BUSH_EXTRA_TRIES := 200

## the run's roll: the river's waypoints, the lake's centre, radius, water level and floor (pass 80: the first lake's)
var _river: Array = []
var _lake_c := Vector2(30, -20)
var _lake_r := 6.5
var _lake_y := 0.0
var _lake_floor := -1.4
## Pass 80 (lane OASIS; Garry: "make it so there are 2 oasis at least per level generation in the red canyon, sometimes
## 3"): every lake of the run, in the order rolled, the first exactly as the one lake was rolled before (the same draws,
## so a seed keeps its first oasis): centres, radii, water levels and floors.
var _lake_cs := PackedVector2Array()
var _lake_rs := PackedFloat32Array()
var _lake_ys := PackedFloat32Array()
var _lake_floors := PackedFloat32Array()
## The dish round a lake reaches this many of its radii (_terrain_height); the lakes' radii are drawn in LAKE_R.
const LAKE_DISH := 1.6
const LAKE_R := Vector2(5.5, 7.5)
## in_water's edge: this many of the lake's radius (the disc as drawn is LAKE_DISC of it)
const LAKE_WET := 1.02
## The oasis ground (pass 81, oasis_wet): wet out to OASIS_WET_TO m past a lake's edge, gone OASIS_REACH m +
## OASIS_REACH_PER_R of its radius out, that reach moved OASIS_WOBBLE m either way by the noise
const OASIS_WET_TO := 0.6
const OASIS_REACH := 3.5
const OASIS_REACH_PER_R := 0.45
const OASIS_WOBBLE := 2.2
## The smooth noises (r, g, b) the water and the ground read (pass 81, tools/gen_textures.py noise_rgb)
const NOISE_TEX := "res://art/env/noise_rgb.png"
## The sands (pass 82, lane SAND; Garry: "Sand Texture is still not very good ... maybe a couple (4) variants to try out
## ... I like the little rocks in the texture though, can you keep them in 2 out of the 4 variants. Add the previous sand
## texture as the 5th variant as well. I want to be able to switch between them easily."): the map file's `sand`
## (timeline_data; WaveTimeline.sand; the Level Editor's World card, the arena's WORLD tab) picks one: its painting
## (tools/gen_sand.py; every one at the same mean colour) and `scale`, the painting's size on the ground against pass
## 81's 11 m a tile (the shader's sand_scale: below 1 = bigger). "" or an id not here plays SAND_DEFAULT.
const SANDS := {
	"pass81": {"file": "res://art/env/sand.png", "scale": 1.0, "name": "Pass 81 sand (today's)", "short": "Pass 81"},
	"dunes": {"file": "res://art/env/sand_dunes.png", "scale": 0.8, "name": "Soft dunes", "short": "Dunes"},
	"dunes_pebbles": {"file": "res://art/env/sand_dunes_pebbles.png", "scale": 1.0, "name": "Soft dunes + pebbles", "short": "Dunes+P"},
	"ripples": {"file": "res://art/env/sand_ripples.png", "scale": 1.0, "name": "Wind ripples", "short": "Ripples"},
	"ripples_pebbles": {"file": "res://art/env/sand_ripples_pebbles.png", "scale": 1.0, "name": "Wind ripples + pebbles", "short": "Rip+P"},
}
const SAND_DEFAULT := "pass81"
## the sand the terrain is painted with (an id of SANDS; set as the terrain builds, and by set_sand)
var sand_id := ""
var _rng := RandomNumberGenerator.new()
var run_seed := 0
## the rim: the ground rises towards the wall from this radius out (pass 80: the sand climbs to the wall's foot, drifted
## against it; the red rock lies only outside the wall)
@export var rim_start := 44.0
@export var rim_height := 2.2
## pass 80: the rim's bumps (metres at the wall; were 1.2 m of broken rock at 2.5x the dunes' frequency): softer and
## longer drifts now that the rim is sand
@export var rim_bumps := 0.45
@export var rim_bump_freq := 1.4
## pass 80: the ground's red rock starts this far past the arena's edge (under the wall; the sand reaches its foot)
const ROCK_FROM := 0.4
## The map's sides (pass 79, lane WORLD; Garry: "Map the sides are too orange"): the red-rock rim's colour and the walls'
## when the map file's timeline_data names none (its `rock_color` and `wall_colors`, WaveTimeline; read by _read_colours
## as the map builds). Less saturated, a little browner and duskier than before, still red rock: the sun and the sky's
## light are warm (they push every colour towards orange on the screen), so the colours as authored lean a touch towards
## rose. The rock painting is recoloured to rock_color in the terrain shader (its bands and cracks kept as light and dark)
## and the cliffs' sandstone painting is grey since pass 79, so each colour here is the colour the side is drawn in.
## Pass 78's: rock (0.62, 0.34, 0.24) over the orange redrock painting; the cliffs (0.78, 0.6, 0.5), (0.62, 0.42, 0.36),
## (0.46, 0.30, 0.30) as tints over the orange sandstone painting; the boundary wall (0.60, 0.40, 0.30) and
## (0.68, 0.47, 0.35), its cap (0.40, 0.26, 0.21), the risers (0.34, 0.22, 0.18), the boulders (0.5, 0.33, 0.26).
## Pass 80 (lane WALLS; Garry: "Make the walls look like sandstone castle walls (but western)"): the boundary is a
## sandstone fort wall (CanyonWalls.fort_wall) and its keys say so: `stone` its dressed blocks, `light` the dressed trim
## (the cap course, the merlons' rounded tops, the parapet's top), `cap` the wall-walk and the towers' roofs, `riser` the
## shaded sides (the steps where the walk climbs, the merlons' sides, the cap course's underside), `beams` the vigas (the
## round beam ends along the wall; `boulders` is gone with the boulders). A warm buff sandstone, picked by eye from six
## palettes on the phone's canvas (tools/dl/p80/WALLS/pal_ADEF.png: "D"), lighter than the rose cliffs behind it and
## browner than the sand before it; the wall is drawn unshaded, so these are the colours drawn (times the painting, grey
## at about 0.8 on average). Pass 79's wall: stone (0.48, 0.39, 0.39), light
## (0.55, 0.45, 0.44), cap (0.33, 0.25, 0.27), riser (0.28, 0.22, 0.23), boulders (0.42, 0.33, 0.34). The cliffs and the
## rock keep pass 79's colours over the new rock painting (art/env/cliff_rock.png, grey on average).
const ROCK_COLOR := Color(0.47, 0.36, 0.37)
const WALL_COLORS := {
	"near": Color(0.52, 0.42, 0.43), "far": Color(0.44, 0.35, 0.39), "farther": Color(0.35, 0.29, 0.34),
	"stone": Color(0.773, 0.62, 0.482), "light": Color(0.871, 0.753, 0.624), "cap": Color(0.647, 0.51, 0.4),
	"riser": Color(0.478, 0.376, 0.306), "beams": Color(0.31, 0.212, 0.149),
}
const WALLS := preload("res://world/maps/red_canyon/CanyonWalls.gd")
## The colours this map is built in (the file's, else the defaults above).
var rock_color: Color = ROCK_COLOR
var wall_colors: Dictionary = WALL_COLORS.duplicate()

var _static: StaticBody3D
var _noise := FastNoiseLite.new()
var props: PropField
## the scatter's regions as placed (pass 61, for tests and captures): the green stands ({center, kind "cactus"|"trees"})
## and the bush patches ({center, radius, bushes [{id, pos}]})
var _stands: Array = []
var _bush_patches: Array = []


func _ready() -> void:
	run_seed = seed
	if Run.map_seed != 0:
		run_seed = Run.map_seed
	_rng.seed = run_seed
	_noise.seed = run_seed
	_noise.frequency = 0.045
	_noise.fractal_octaves = 3
	flats_center = Vector3(0, 0, 8)
	_read_colours()
	_roll_layout()
	_build_terrain()
	_build_wall()
	_build_lake()
	_build_props()
	_build_sky()
	_build_movers()


# ---------------------------------------------------------------- the roll

## The run's layout: one dry river from rim to rim with a wandering middle that bends around the flats, and one oasis
## lake off the river and the flats, well inside the wall (pass 80: then the others, _roll_oases).
func _roll_layout() -> void:
	var fc := Vector2(flats_center.x, flats_center.z)
	var a0 := _rng.randf() * TAU
	var a1 := a0 + PI + _rng.randf_range(-0.7, 0.7)
	var rr := arena_radius + 6.0
	var p0 := Vector2(cos(a0), sin(a0)) * rr
	var p1 := Vector2(cos(a1), sin(a1)) * rr
	var perp := (p1 - p0).normalized().rotated(PI * 0.5)
	var n := 6
	_river.clear()
	for k in range(n + 1):
		var f := float(k) / float(n)
		var pt := p0.lerp(p1, f)
		if k > 0 and k < n:
			pt += perp * _rng.randf_range(-14.0, 14.0)
			var d := pt - fc
			var keep := flats_radius + river_width + 4.0
			if d.length() < keep:
				pt = fc + (d.normalized() if d.length() > 0.01 else Vector2(1, 0)) * keep
		_river.append(pt)
	_lake_r = _rng.randf_range(5.5, 7.5)
	_lake_c = Vector2(0, -34)
	for tries in range(200):
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(24.0, arena_radius - 18.0)
		var c := Vector2(cos(a) * r, sin(a) * r)
		if (c - fc).length() < flats_radius + _lake_r + 8.0:
			continue
		if _river_dist(c) < river_width * 0.5 + _lake_r + 5.0:
			continue
		_lake_c = c
		break
	var base := _noise.get_noise_2d(_lake_c.x, _lake_c.y) * dune_height
	# a wading pool: the floor is knee-deep under a surface level with the shore, and anyone can walk in
	_lake_y = base - 0.04
	_lake_floor = base - lake_depth
	# pass 80 (lane OASIS): the first lake as it always was, then the others
	_roll_oases()


## The oases past the first (pass 80, lane OASIS): how many from the map file's `oases` (WaveTimeline.OASES_DEFAULTS for
## what it leaves out): `min` of them, then one more with `extra_chance` each up to `max`; each like the first (a radius in LAKE_R, a
## centre 24 m out to 18 m inside the wall, clear of the flats by 8 m past its radius and of the dry river's bed by 5 m),
## and its dish at least `gap` m of open ground from every other lake's (the dishes reach LAKE_DISH of the radius). A
## lake that finds no spot in 240 tries takes a third of the gap for 120 more, then none (dishes still apart); one past
## `min` that still finds none is left out (the map is then a lake short; every seed checked holds `min`).
func _roll_oases() -> void:
	_lake_cs = PackedVector2Array([_lake_c])
	_lake_rs = PackedFloat32Array([_lake_r])
	_lake_ys = PackedFloat32Array([_lake_y])
	_lake_floors = PackedFloat32Array([_lake_floor])
	var cfg := oases_config()
	var lo := clampi(int(cfg["min"]), 1, 6)
	var hi := clampi(int(cfg["max"]), lo, 6)
	var want := lo
	while want < hi and _rng.randf() < float(cfg["extra_chance"]):
		want += 1
	var fc := Vector2(flats_center.x, flats_center.z)
	var gap := maxf(float(cfg["gap"]), 0.0)
	for k in range(1, want):
		var lr := _rng.randf_range(LAKE_R.x, LAKE_R.y)
		var at := Vector2.INF
		for tries in range(480):
			var g := gap if tries < 240 else (gap / 3.0 if tries < 360 else 0.0)
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(24.0, arena_radius - 18.0)
			var c := Vector2(cos(a) * r, sin(a) * r)
			if (c - fc).length() < flats_radius + lr + 8.0:
				continue
			if _river_dist(c) < river_width * 0.5 + lr + 5.0:
				continue
			var ok := true
			for j in range(_lake_cs.size()):
				if c.distance_to(_lake_cs[j]) < (lr + _lake_rs[j]) * LAKE_DISH + g:
					ok = false
					break
			if ok:
				at = c
				break
		if at == Vector2.INF:
			continue
		var b := _noise.get_noise_2d(at.x, at.y) * dune_height
		_lake_cs.append(at)
		_lake_rs.append(lr)
		_lake_ys.append(b - 0.04)
		_lake_floors.append(b - lake_depth)


## The map file's oases block (timeline_data `oases`, pass 80) over WaveTimeline.OASES_DEFAULTS: {min, max, extra_chance,
## gap}.
func oases_config() -> Dictionary:
	var out: Dictionary = WaveTimeline.OASES_DEFAULTS.duplicate()
	var tl: WaveTimeline = Run.map.timeline if Run.map else null
	if tl == null:
		return out
	var o = tl.oases
	if o is Dictionary:
		for k: String in WaveTimeline.OASES_DEFAULTS:
			var v = (o as Dictionary).get(k)
			if v is float or v is int:
				out[k] = v
	return out


## The rock's and the walls' colours from the map file (pass 79: timeline_data `rock_color`, `wall_colors`), each key it
## leaves out or cannot read at the default (ROCK_COLOR, WALL_COLORS). Before anything is built.
func _read_colours() -> void:
	rock_color = ROCK_COLOR
	wall_colors = WALL_COLORS.duplicate()
	var tl: WaveTimeline = Run.map.timeline if Run.map else null
	if tl == null:
		return
	rock_color = WaveTimeline.color_of(tl.rock_color, ROCK_COLOR)
	for k: String in WALL_COLORS:
		wall_colors[k] = WaveTimeline.color_of(tl.wall_colors.get(k), WALL_COLORS[k])


## The sand the map file names (pass 82: timeline_data `sand`), SAND_DEFAULT for none, an id not in SANDS, or a painting
## that is missing.
func map_sand_id() -> String:
	var tl: WaveTimeline = Run.map.timeline if Run.map else null
	return sand_or_default(str(tl.get("sand")) if tl and tl.get("sand") != null else "")


## `id` when SANDS has it and its painting is there, else SAND_DEFAULT (pass 82).
static func sand_or_default(id: String) -> String:
	if SANDS.has(id) and ResourceLoader.exists(str((SANDS[id] as Dictionary)["file"])):
		return id
	return SAND_DEFAULT


## Every sand the map knows (pass 82): SANDS (the arena's WORLD tab lists them).
func sands() -> Dictionary:
	return SANDS


## The terrain painted with sand `id` (pass 82): its painting and its size on the ground. The arena's WORLD tab switches it
## for a visit; a run plays the map file's.
func set_sand(id: String) -> void:
	if _terrain_mat:
		_apply_sand(_terrain_mat, sand_or_default(id))


func _apply_sand(mat: ShaderMaterial, id: String) -> void:
	var s: Dictionary = SANDS[id]
	mat.set_shader_parameter("sand_tex", load(str(s["file"])))
	mat.set_shader_parameter("sand_scale", float(s.get("scale", 1.0)))
	sand_id = id


func river_points() -> Array:
	return _river


## The first lake's centre and radius (the one lake before pass 80; old callers and tools). Every lake: lakes().
func lake_center() -> Vector2:
	return _lake_c


func lake_radius() -> float:
	return _lake_r


## Every lake of the run (pass 80, lane OASIS), the first first: [{center: Vector2, radius, level (the water's surface),
## floor (the dish's), disc (water_disc's dictionary)}].
func lakes() -> Array:
	var out: Array = []
	for k in range(_lake_cs.size()):
		out.append({"center": _lake_cs[k], "radius": _lake_rs[k], "level": _lake_ys[k], "floor": _lake_floors[k], "disc": _disc_of(k)})
	return out


## How many lakes the run has (pass 80).
func lake_count() -> int:
	return _lake_cs.size()


## The lake `p` (x, z) stands in, else the one whose shore is nearest (pass 80); 0 before the roll.
func lake_index(p: Vector2) -> int:
	var best := 0
	var best_d := INF
	for k in range(_lake_cs.size()):
		var d := p.distance_to(_lake_cs[k]) - _lake_rs[k]
		if d < best_d:
			best_d = d
			best = k
	return best


## The green stands as placed: [{center: Vector2, kind: "cactus" | "trees"}] (pass 61).
func green_stands() -> Array:
	return _stands


## The bush patches as placed: [{center: Vector2, radius: float, bushes: [{id, pos: Vector2}]}] (pass 61).
func bush_patches() -> Array:
	return _bush_patches


# ---------------------------------------------------------------- terrain

func _river_dist(p: Vector2) -> float:
	var best := 1e9
	for k in range(_river.size() - 1):
		var a: Vector2 = _river[k]
		var b: Vector2 = _river[k + 1]
		var ab := b - a
		var t: float = clamp((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = min(best, (a + ab * t - p).length())
	return best


## How far `p` lies from the nearest lake's edge (pass 80: every lake; below 0 in the water).
func _lake_edge(p: Vector2) -> float:
	var best := INF
	for k in range(_lake_cs.size()):
		best = minf(best, p.distance_to(_lake_cs[k]) - _lake_rs[k])
	return best


## The ground's red rock at `p` (x, z), 0 on the sand to 1 (pass 80: 0 everywhere inside the wall, 1 from ROCK_FROM
## past the arena's edge; the terrain shader reads it from the vertex colour's blue).
func rock_weight(p: Vector2) -> float:
	return 1.0 if p.length() >= arena_radius + ROCK_FROM else 0.0


## How far into the rim a point is, 0 on the flat sand to 1 at the wall (the sand rises over it).
func _rim(p: Vector2) -> float:
	return clampf((p.length() - rim_start) / maxf(arena_radius - rim_start, 1.0), 0.0, 1.0)


func _in_mesa(_p: Vector2) -> bool:
	return false


func _terrain_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := _noise.get_noise_2d(x, z) * dune_height
	var d_flat := (p - Vector2(flats_center.x, flats_center.z)).length()
	var flat_w: float = clamp((d_flat - flats_radius) / 8.0, 0.0, 1.0)
	h *= flat_w
	var rd := _river_dist(p)
	var rw: float = clamp(1.0 - rd / river_width, 0.0, 1.0)
	h -= river_depth * smoothstep(0.0, 1.0, rw) * flat_w
	# the rim climbs towards the wall (pass 80: sand drifted against it, its bumps soft; was broken red rock, 1.2 m of
	# bumps at 2.5x)
	var rim := _rim(p)
	h += rim_height * rim * rim + _noise.get_noise_2d(x * rim_bump_freq + 40.0, z * rim_bump_freq) * rim * rim_bumps
	# the oasis: a shallow dish with a flat floor under the water (pass 80: round every lake; the dishes never meet)
	for k in range(_lake_cs.size()):
		var lr: float = _lake_rs[k]
		var dl := p.distance_to(_lake_cs[k])
		if dl < lr * LAKE_DISH:
			var w := 1.0 - smoothstep(lr * 0.7, lr * LAKE_DISH, dl)
			h = lerpf(h, _lake_floors[k], w)
	return h


func _build_terrain() -> void:
	grid_n = int(size_m * resolution) + 1
	heights.resize(grid_n * grid_n)
	var half := size_m * 0.5
	for iz in range(grid_n):
		for ix in range(grid_n):
			var x := ix / resolution - half
			var z := iz / resolution - half
			heights[iz * grid_n + ix] = _terrain_height(x, z)
	# mesh. Pass 81 (lane MAP): every corner its own colour (_color_at at each grid point, blended across the quad); one
	# flat colour a quad drew a faint metre checker over the sand and blocky steps round the lakes
	var cols := PackedColorArray()
	cols.resize(grid_n * grid_n)
	for iz in range(grid_n):
		for ix in range(grid_n):
			cols[iz * grid_n + ix] = _color_at(ix / resolution - half, iz / resolution - half, heights[iz * grid_n + ix])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in range(grid_n - 1):
		for ix in range(grid_n - 1):
			var x0 := ix / resolution - half
			var z0 := iz / resolution - half
			var x1 := x0 + 1.0 / resolution
			var z1 := z0 + 1.0 / resolution
			var i00 := iz * grid_n + ix
			var p00 := Vector3(x0, heights[i00], z0)
			var p10 := Vector3(x1, heights[i00 + 1], z0)
			var p01 := Vector3(x0, heights[i00 + grid_n], z1)
			var p11 := Vector3(x1, heights[i00 + grid_n + 1], z1)
			var c00 := cols[i00]
			var c10 := cols[i00 + 1]
			var c01 := cols[i00 + grid_n]
			var c11 := cols[i00 + grid_n + 1]
			# Godot front faces are clockwise: (x0,z0) -> (x1,z0) -> (x0,z1) seen from above
			st.set_color(c00); st.add_vertex(p00)
			st.set_color(c10); st.add_vertex(p10)
			st.set_color(c01); st.add_vertex(p01)
			st.set_color(c10); st.add_vertex(p10)
			st.set_color(c11); st.add_vertex(p11)
			st.set_color(c01); st.add_vertex(p01)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://core/shaders/terrain_painted.gdshader")
	if ResourceLoader.exists("res://art/env/sand.png") and ResourceLoader.exists("res://art/env/cracked.png"):
		# pass 82: the map file's sand (SANDS), pass 81's when it names none
		_apply_sand(mat, map_sand_id())
		mat.set_shader_parameter("cracked_tex", load("res://art/env/cracked.png"))
		if ResourceLoader.exists("res://art/env/redrock.png"):
			mat.set_shader_parameter("rock_tex", load("res://art/env/redrock.png"))
		# the flat tones the textures are calmed towards (pass 54): the exports, so the ground is tunable in the editor
		mat.set_shader_parameter("sand_flat", sand_color)
		mat.set_shader_parameter("cracked_flat", river_color)
		# pass 79: the rim's rock in the map's colour (the shader recolours the rock painting to it)
		mat.set_shader_parameter("rock_flat", rock_color)
		# pass 81: the smooth noises for the sand's large-scale variation and the oasis ground's ragged edge and green
		if ResourceLoader.exists(NOISE_TEX):
			mat.set_shader_parameter("noise_tex", load(NOISE_TEX))
	else:
		var fallback := StandardMaterial3D.new()
		fallback.vertex_color_use_as_albedo = true
		mi.material_override = fallback
	if mi.material_override == null:
		mi.material_override = mat
		_terrain_mat = mat
	add_child(mi)
	# collision
	_static = StaticBody3D.new()
	_static.name = "TerrainBody"
	_static.collision_layer = 1
	var shape := HeightMapShape3D.new()
	shape.map_width = grid_n
	shape.map_depth = grid_n
	shape.map_data = heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(1.0 / resolution, 1.0, 1.0 / resolution)
	_static.add_child(cs)
	add_child(_static)


func _color_at(x: float, z: float, h: float) -> Color:
	## r = riverbed blend, g = shade multiplier, b = red-rock blend, a = the oasis ground (pass 81: 1 at the water's edge,
	## 0 on the dry sand; oasis_wet). The painted terrain shader reads these.
	var rd := _river_dist(Vector2(x, z))
	var t: float = clamp(1.0 - rd / (river_width * 0.9), 0.0, 1.0)
	# pass 81 (lane MAP): the damp ring round the water (pass 80: a 0.35 mix of the cracked river bed in r) is the oasis
	# ground in a now, wet sand at the water fading through damp earth and sparse green into the dry sand
	var n := _noise.get_noise_2d(x * 3.0 + 100.0, z * 3.0)
	var shade: float = clamp(1.0 - n * 0.35 + h * 0.05, 0.6, 1.15)
	# pass 80 (Garry: "make the edges of the map just sand ... that orange-dark stuff should be behind the walls"): the
	# red rock only outside the wall, from ROCK_FROM past the arena's edge (under the wall); was the rim from rim_start
	var rock: float = rock_weight(Vector2(x, z))
	return Color(t, shade, rock, oasis_wet(Vector2(x, z)))


## The oasis ground at `p` (x, z) (pass 81, lane MAP; Garry: "Do a bit of a ground texture shading around the water.
## Basically make it look more natural, like an oasis."): 1 up to OASIS_WET_TO m past the nearest lake's edge (and
## under the water), falling to 0 OASIS_REACH m out (plus OASIS_REACH_PER_R of the lake's radius), that reach moved in
## and out by OASIS_WOBBLE m of slow noise so the band is ragged, never a ring. The terrain shader turns it into wet
## sand, damp earth with sparse green, and the dry sand (terrain_painted.gdshader `oasis_*`).
func oasis_wet(p: Vector2) -> float:
	var best := 0.0
	for k in range(_lake_cs.size()):
		var lr: float = _lake_rs[k]
		var reach: float = OASIS_REACH + OASIS_REACH_PER_R * lr
		var dl := p.distance_to(_lake_cs[k])
		if dl > lr + reach + OASIS_WOBBLE:
			continue
		var wob := clampf(_noise.get_noise_2d(p.x * 1.7 + 211.0, p.y * 1.7 - 73.0) * 2.0, -1.0, 1.0)
		var de := dl - lr - OASIS_WET_TO
		var span := maxf(reach + wob * OASIS_WOBBLE - OASIS_WET_TO, 0.5)
		best = maxf(best, 1.0 - smoothstep(0.0, span, de))
	return best


# ---------------------------------------------------------------- geometry helpers

var _stone_mat: StandardMaterial3D
var _terrain_mat: ShaderMaterial
## the lakes' water (pass 81): stage 3's hell reddens it as it does the ground
var _water_mat: ShaderMaterial
var _env: Environment
var _hell := 0.0
var _hell_tween: Tween
## the fort wall's material (pass 80): stage 3's hell tints it as it tints the ground (the wall is unshaded, so the hell's
## light alone would leave it pale)
var _wall_mat: StandardMaterial3D
const HELL_WALL := Color(0.97, 0.79, 0.72)


func _stone() -> StandardMaterial3D:
	if _stone_mat == null:
		_stone_mat = StandardMaterial3D.new()
		if ResourceLoader.exists("res://art/env/sandstone.png"):
			_stone_mat.albedo_texture = load("res://art/env/sandstone.png")
			_stone_mat.uv1_triplanar = true
			_stone_mat.uv1_world_triplanar = true
			_stone_mat.uv1_scale = Vector3(0.12, 0.12, 0.12)
		else:
			_stone_mat.albedo_color = wall_color
		_stone_mat.roughness = 1.0
	return _stone_mat


func _box(p: Vector3, s: Vector3, color: Color, obstacle_r := 0.0, rot_y := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = s
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = s
	mi.mesh = m
	if color == wall_color or color == Color(0.72, 0.42, 0.24) or color == Color(0.83, 0.63, 0.42):
		mi.material_override = _stone()
		if color != wall_color:
			mi.material_override = _stone().duplicate()
			mi.material_override.albedo_color = color.lightened(0.15)
	else:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 1.0
		mi.material_override = mat
	body.add_child(mi)
	body.position = p
	body.rotation.y = rot_y
	add_child(body)
	if obstacle_r > 0.0:
		obstacles.append(Vector3(p.x, p.z, obstacle_r))
	return body


func _cylinder(p: Vector3, r: float, h: float, color: Color, obstacle := true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = h
	cs.shape = shape
	cs.position.y = h * 0.5
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	mi.mesh = m
	mi.position.y = h * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	body.add_child(mi)
	body.position = p
	add_child(body)
	if obstacle:
		obstacles.append(Vector3(p.x, p.z, r + 0.2))
	return body


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, height_at(x, z), z)


# ---------------------------------------------------------------- the wall

func _build_wall() -> void:
	# the mountain wall: a ring of cliff faces whose height wanders, one mesh, rock-painted; the ranges beyond are the
	# same ring twice more, bigger and darker, so the horizon has depth without a single box. Pass 80 (lane WALLS): a
	# hi-res rock painting (art/env/cliff_rock.png) on the ring's own UVs in metres (CanyonWalls.CLIFF_TILES: 14, 20 and 28
	# m a tile, the farther ranges' strata bigger), the face broken into ledges; the colours still the map's wall_colors
	# (the painting grey on average, so the tint is the colour drawn)
	var near := WALLS.cliff_material(wall_colors["near"])
	# pass 72: the near cliffs and the boundary wall are scenery (a creature they hide is outlined, SceneryStencil)
	add_child(SceneryStencil.mark_tree(_ridge(arena_radius + 4.0, 9.0, 6.0, 96, near, 1.0, WALLS.CLIFF_TILES[0])))
	var far := WALLS.cliff_material(wall_colors["far"])
	add_child(_ridge(arena_radius + 26.0, 16.0, 9.0, 72, far, 2.3, WALLS.CLIFF_TILES[1]))
	var farther := WALLS.cliff_material(wall_colors["farther"])
	add_child(_ridge(arena_radius + 52.0, 24.0, 12.0, 60, farther, 5.1, WALLS.CLIFF_TILES[2]))
	# the boundary itself: a western sandstone fort wall right on the arena's edge (pass 80), with posts and skulls before
	# it, so the line the hero cannot cross is a thing in the world and not a place where he stops for no reason
	add_child(SceneryStencil.mark_tree(_boundary_wall(arena_radius, 120)))
	# invisible fence a little inside so the player never wedges into the cliffs
	var n := 40
	for k2 in range(n):
		var a := TAU * k2 / n
		var r := arena_radius - 1.1   # the wall's inner face, so the hero stops at the stone and not inside it
		var p := Vector3(cos(a) * r, 2.0, sin(a) * r)
		# (pass 80: a plain colour, the box is never drawn: the stone material would load the old sandstone painting, 4 MB of
		# texture for nothing)
		var body := _box(p, Vector3(TAU * r / n + 1.0, 8.0, 0.5), Color.BLACK, 0.0, -a + PI * 0.5)
		for c in body.get_children():
			if c is MeshInstance3D:
				c.visible = false


## The boundary (pass 80, lane WALLS): a western sandstone fort wall, 1.7 m thick on the arena's edge, its walk about 2 m
## over the ground with a cap course, a parapet with rounded merlons, vigas and a squat tower every 30 degrees
## (CanyonWalls.fort_wall, in the map's wall_colors), and before it tall wooden posts every ten degrees (one MultiMesh)
## with a skull on every fourth. Pass 79's stacked-stone wall with battlements and boulders on top is gone; the footprint,
## the height and the fence (in _build_wall) are as they were.
func _boundary_wall(r: float, segs: int) -> Node3D:
	var root: Node3D = WALLS.fort_wall(self, r, segs, wall_colors, _noise)
	_wall_mat = (root.get_node("Wall") as MeshInstance3D).material_override as StandardMaterial3D
	# posts and skulls: the posts are one MultiMesh (pass 33.8: 36 meshes with a material each, a draw call apiece)
	var post_n := 36
	var skull_scene: PackedScene = load("res://art/props/skull.glb") if ResourceLoader.exists("res://art/props/skull.glb") else null
	var cm := CylinderMesh.new()
	cm.top_radius = 0.11
	cm.bottom_radius = 0.15
	cm.height = 4.0
	cm.radial_segments = 6
	var pmm := MultiMesh.new()
	pmm.transform_format = MultiMesh.TRANSFORM_3D
	pmm.mesh = cm
	pmm.instance_count = post_n
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.36, 0.25, 0.16)
	pm.roughness = 1.0
	var posts := MultiMeshInstance3D.new()
	posts.name = "Posts"
	posts.multimesh = pmm
	posts.material_override = pm
	root.add_child(posts)
	for k2 in range(post_n):
		var a := TAU * k2 / post_n + 0.04
		var px := cos(a) * (r - 1.3)
		var pz := sin(a) * (r - 1.3)
		var gy := height_at(px, pz)
		pmm.set_instance_transform(k2, Transform3D(Basis.from_euler(Vector3(0, 0, 0.05 * sin(a * 5.0))), Vector3(px, gy + 1.6, pz)))
		if k2 % 4 == 0 and skull_scene:
			var sk: Node3D = skull_scene.instantiate()
			sk.position = Vector3(px, gy + 3.7, pz)
			sk.rotation.y = -a + PI * 0.5
			sk.scale = Vector3.ONE * 0.9
			root.add_child(sk)
	return root


func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, c: Color) -> void:
	for v in [p0, p1, p2, p0, p2, p3]:
		st.set_color(c)
		st.add_vertex(v)


## A ring of cliffs: an inner face that leans outward, broken into ledges, a jagged top, height wandering with noise
## around the ring (pass 80: CanyonWalls.ridge, the rock painting `tile` m a tile).
func _ridge(r: float, h: float, h_var: float, segs: int, mat: Material, noise_off: float, tile: float = 14.0) -> MeshInstance3D:
	return WALLS.ridge(self, arena_radius, r, h, h_var, segs, mat, noise_off, _noise, tile)


## The oasis: one flat half-transparent disc at the water level (`_lake_y`) over the dish; no collider and no obstacle
## circle, anyone wades in (pass 29; the pass 31 shader is gone, the collider went with the dish).
## Pass 80 (lane OASIS): one disc a lake, "Oasis" the first, "Oasis2", "Oasis3" the others, all of one material.
## Pass 81 (lane MAP; Garry: "Make the water look more like water. Maybe a cheap (in terms of performance) shader."):
## that material is core/shaders/water_lake.gdshader (deep middle, shallow rim, a ragged shore that fades out, slow
## ripples, a lapping line, glints; unshaded, three samples of art/env/noise_rgb.png); the disc is unchanged.
func _build_lake() -> void:
	var mat := _water_material()
	for k in range(_lake_cs.size()):
		var mi := MeshInstance3D.new()
		mi.name = "Oasis" if k == 0 else "Oasis%d" % (k + 1)
		var cm := CylinderMesh.new()
		cm.top_radius = _lake_rs[k] * LAKE_DISC
		cm.bottom_radius = _lake_rs[k] * LAKE_DISC
		cm.height = LAKE_THICK
		cm.radial_segments = 40
		cm.rings = 1
		mi.mesh = cm
		mi.material_override = mat
		mi.position = Vector3(_lake_cs[k].x, _lake_ys[k], _lake_cs[k].y)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


## The lakes' one material (pass 81): the water shader, under the ground marks (their pools draw at priority -5..-1, pass
## 33.8, so a red ring on the lake bed always reads), as the flat colour it replaces was.
func _water_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://core/shaders/water_lake.gdshader")
	if ResourceLoader.exists(NOISE_TEX):
		mat.set_shader_parameter("noise_tex", load(NOISE_TEX))
	mat.render_priority = -10
	_water_mat = mat
	return mat


## Standing in the water? (the hero's ripples, Game; pass 80: in any lake, LAKE_WET of its radius)
func in_water(p: Vector3) -> bool:
	var q := Vector2(p.x, p.z)
	for k in range(_lake_cs.size()):
		var rw: float = _lake_rs[k] * LAKE_WET
		if q.distance_squared_to(_lake_cs[k]) < rw * rw:
			return true
	return false


## The water's surface height (pass 54): where the ripples of anyone wading are drawn and under which a shadow is
## hidden; the lake's floor lies `lake_depth` under the shore, the surface 4 cm under it. Pass 80: the lake `p` stands
## in or nearest it (lake_index); without `p`, the first lake's.
func water_level(p: Vector3 = Vector3.INF) -> float:
	if _lake_ys.is_empty():
		return _lake_y
	return _lake_ys[0 if not p.is_finite() else lake_index(Vector2(p.x, p.z))]


## The water's disc as it is drawn (pass 56): its middle (x, z), the height of its top face, its radius and its
## thickness, for whatever must leave out what the water covers (the hero's second pass, Game._sink_hero). Pass 80: the
## lake `p` stands in or nearest it (lake_index); without `p`, the first lake's.
func water_disc(p: Vector3 = Vector3.INF) -> Dictionary:
	if _lake_cs.is_empty():
		return {"center": _lake_c, "top": _lake_y + LAKE_THICK * 0.5, "radius": _lake_r * LAKE_DISC, "thick": LAKE_THICK}
	return _disc_of(0 if not p.is_finite() else lake_index(Vector2(p.x, p.z)))


## Lake `k`'s disc as water_disc tells it.
func _disc_of(k: int) -> Dictionary:
	return {"center": _lake_cs[k], "top": _lake_ys[k] + LAKE_THICK * 0.5, "radius": _lake_rs[k] * LAKE_DISC, "thick": LAKE_THICK}


func _build_props() -> void:
	# painted scenery only: cacti, trees, bushes, rocks, bones and signposts, placed by region from the run's roll
	_scatter_sprites()


func _build_sky() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	if ResourceLoader.exists("res://art/env/sky_panorama.png"):
		var pm := PanoramaSkyMaterial.new()
		pm.panorama = load("res://art/env/sky_panorama.png")
		pm.filter = true
		sky.sky_material = pm
	else:
		var sm := ProceduralSkyMaterial.new()
		sm.sky_top_color = Color(0.21, 0.14, 0.31)
		sm.sky_horizon_color = Color(0.89, 0.53, 0.30)
		sm.ground_bottom_color = Color(0.55, 0.36, 0.20)
		sm.ground_horizon_color = Color(0.80, 0.50, 0.28)
		sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.95, 0.80, 0.66)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.93, 0.66, 0.42)
	env.fog_density = 0.004
	var we := WorldEnvironment.new()
	we.environment = env
	_env = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.85, 0.65)
	sun.light_energy = 1.3
	sun.rotation_degrees = Vector3(-42, 140, 0)
	sun.shadow_enabled = false
	add_child(sun)


## Stage 3 is hell (pass 43): the sand goes a shade redder and darker, the light and the haze with it, over `seconds`.
func set_hell(f: float, seconds: float = 3.0) -> void:
	if _hell_tween:
		_hell_tween.kill()
	_hell_tween = create_tween()
	_hell_tween.tween_method(_apply_hell, _hell, clampf(f, 0.0, 1.0), maxf(seconds, 0.01))


func _apply_hell(f: float) -> void:
	_hell = f
	if _terrain_mat:
		_terrain_mat.set_shader_parameter("hell", f)
	if _water_mat:
		_water_mat.set_shader_parameter("hell", f)
	if _wall_mat:
		_wall_mat.albedo_color = Color.WHITE.lerp(HELL_WALL, f)
	if _env:
		_env.ambient_light_color = Color(0.95, 0.80, 0.66).lerp(Color(0.92, 0.70, 0.60), f)
		_env.fog_light_color = Color(0.93, 0.66, 0.42).lerp(Color(0.86, 0.54, 0.38), f)


func _build_movers() -> void:
	var dd := DustDevil.new()
	dd.loop_center = flats_center + Vector3(6, 0, 4)
	add_child(dd)
	# gusts of dusty wind now and then (pass 44), the look of the desert and nothing else
	var gust := DustGust.new()
	gust.name = "DustGust"
	gust.map = self
	add_child(gust)
	for k in range(tumbleweeds):
		var tw := Tumbleweed.new()
		add_child(tw)
		tw.setup(self, Vector3(1, 0, 0.3), randf_range(0.5, 0.9))
		tw.global_position = Vector3(randf_range(-50, 50), 0, randf_range(-50, 50))


func bind_game(game: Node) -> void:
	for c in get_children():
		if c is DustDevil or c is DustGust:
			c.game = game


# ---------------------------------------------------------------- painted scenery

## A PropField of painted sprites laid down by region, so like stands with like: the oasis (palms and green around
## the water), three green stands (a cactus stand or a tree stand with the low greenery around it), dead trees and
## shrubs on the dry river's banks with bones in its bed, rock fields near the rim with skulls among them, a few
## lone things, and (pass 61) five to seven sparse bush patches. Anything with a collider radius gets a cylinder body and
## an obstacle circle; bushes have none.
func _scatter_sprites() -> void:
	_stands.clear()
	_bush_patches.clear()
	props = PropField.new()
	props.name = "Props"
	add_child(props)
	# pass 83: the ground shadows lie on the slopes
	props.height_fn = height_at
	props.setup()
	if not props.has("saguaro_big"):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed * 7 + 3
	var taken: Array = []   # Vector3(x, z, keep-out radius)
	var fc := Vector2(flats_center.x, flats_center.z)

	var free := func(pt: Vector2, keep: float, in_bed := false) -> bool:
		if (pt - fc).length() < flats_radius + 3.0:
			return false
		if pt.length() > arena_radius - 5.0:
			return false
		if not in_bed and _river_dist(pt) < river_width * 0.5 + 1.0:
			return false
		if _lake_edge(pt) < 1.2:
			return false
		for t: Vector3 in taken:
			if (pt - Vector2(t.x, t.y)).length() < t.z + keep:
				return false
		return true

	var place := func(id: String, pt: Vector2, scale: float, sway: float) -> bool:
		# a hidden painting (props.json "hidden": the signpost and the yucca since pass 49) is never placed
		if not props.has(id) or props.is_hidden(id):
			return false
		var g := _ground(pt.x, pt.y)
		var added := props.add(id, g, scale, rng.randf() < 0.5, sway)
		var r := props.radius_of(id) * scale
		if r > 0.0:
			_sprite_collider(g, r, props.height_of(id) * scale)
		taken.append(Vector3(pt.x, pt.y, maxf(r, 0.6)))
		return added

	var around := func(centre: Vector2, rmin: float, rmax: float, keep: float) -> Vector2:
		for k in range(30):
			var a := rng.randf() * TAU
			var r := rng.randf_range(rmin, rmax)
			var pt := centre + Vector2(cos(a) * r, sin(a) * r)
			if free.call(pt, keep):
				return pt
		return Vector2.INF

	var spot := func(keep: float, rmin: float, rmax: float, away: Array, away_r: float) -> Vector2:
		for k in range(80):
			var a := rng.randf() * TAU
			var r := rng.randf_range(rmin, rmax)
			var pt := Vector2(cos(a) * r, sin(a) * r)
			if not free.call(pt, keep):
				continue
			var ok := true
			for c: Vector2 in away:
				if (pt - c).length() < away_r:
					ok = false
			if ok:
				return pt
		return Vector2.INF

	var pick := func(table: Array) -> String:
		# [[id, weight], ...]; a hidden painting's row is left out, so the others fill its share
		var rows: Array = table.filter(func(row) -> bool: return not props.is_hidden(str(row[0])))
		if rows.is_empty():
			rows = table
		var total := 0.0
		for row in rows:
			total += float(row[1])
		var x := rng.randf() * total
		for row in rows:
			x -= float(row[1])
			if x <= 0.0:
				return str(row[0])
		return str(rows[0][0])

	# --- the oasis: palms right at the shore, green a little further out, a rock or two at the water (pass 80: round
	# every lake in turn, the first one's draws first, so its greenery stands where it did)
	var greens: Array = []
	var oasis_low: Array = [["desert_bush", 3], ["creosote_bush", 2], ["agave", 2], ["yucca", 2], ["ocotillo", 1], ["mesquite_tree", 1], ["rock_small", 1], ["brittlebush", 1]]
	for lk in range(maxi(_lake_cs.size(), 1)):
		var lc: Vector2 = _lake_cs[lk] if lk < _lake_cs.size() else _lake_c
		var lr: float = _lake_rs[lk] if lk < _lake_rs.size() else _lake_r
		greens.append(lc)
		for k in range(rng.randi_range(8, 10)):
			var pt: Vector2 = around.call(lc, lr + 1.4, lr + 5.0, 1.2)
			if pt != Vector2.INF:
				place.call("fan_palm", pt, rng.randf_range(0.9, 1.15), 0.05)
		for k in range(rng.randi_range(22, 28)):
			var pt: Vector2 = around.call(lc, lr + 1.0, lr + 11.0, 0.6)
			if pt != Vector2.INF:
				var id: String = pick.call(oasis_low)
				place.call(id, pt, rng.randf_range(0.8, 1.2), 0.0 if id == "rock_small" else 0.06)
	# --- three green stands: cactus or trees, with the low greenery around
	for c in range(3):
		var centre: Vector2 = spot.call(3.0, 22.0, arena_radius - 12.0, greens, 22.0)
		if centre == Vector2.INF:
			continue
		greens.append(centre)
		var cactus := rng.randf() < 0.5
		_stands.append({"center": centre, "kind": "cactus" if cactus else "trees"})
		if cactus:
			for k in range(rng.randi_range(2, 3)):
				var pt: Vector2 = around.call(centre, 0.0, 5.0, 1.5)
				if pt != Vector2.INF:
					place.call("saguaro_big", pt, rng.randf_range(0.9, 1.15), 0.05)
			for k in range(rng.randi_range(3, 5)):
				var pt: Vector2 = around.call(centre, 1.0, 7.0, 0.8)
				if pt != Vector2.INF:
					place.call("saguaro_small", pt, rng.randf_range(0.85, 1.1), 0.06)
			var low: Array = [["barrel_cactus", 3], ["agave", 2], ["yucca", 2], ["ocotillo", 1.5], ["desert_bush", 2], ["dead_shrub", 1]]
			for k in range(rng.randi_range(8, 12)):
				var pt: Vector2 = around.call(centre, 1.0, 9.0, 0.6)
				if pt != Vector2.INF:
					var id: String = pick.call(low)
					place.call(id, pt, rng.randf_range(0.8, 1.2), 0.04)
		else:
			var trees: Array = [["mesquite_tree", 3], ["palo_verde", 2], ["joshua_tree", 2]]
			for k in range(rng.randi_range(3, 4)):
				var pt: Vector2 = around.call(centre, 0.0, 6.0, 2.0)
				if pt != Vector2.INF:
					place.call(pick.call(trees), pt, rng.randf_range(0.85, 1.15), 0.03)
			var under: Array = [["desert_bush", 3], ["creosote_bush", 3], ["yucca", 1.5], ["ocotillo", 1], ["agave", 1], ["brittlebush", 1.5]]
			for k in range(rng.randi_range(7, 10)):
				var pt: Vector2 = around.call(centre, 1.0, 9.0, 0.6)
				if pt != Vector2.INF:
					var id: String = pick.call(under)
					place.call(id, pt, rng.randf_range(0.8, 1.2), 0.08)
	# --- the dry river: dead trees and shrubs on its banks, bones in the bed
	if _river.size() >= 2:
		for k in range(rng.randi_range(7, 10)):
			var seg := rng.randi() % (_river.size() - 1)
			var a: Vector2 = _river[seg]
			var b: Vector2 = _river[seg + 1]
			var along := a.lerp(b, rng.randf())
			var side := (b - a).normalized().rotated(PI * 0.5) * (1.0 if rng.randf() < 0.5 else -1.0)
			var pt := along + side * rng.randf_range(river_width * 0.5 + 1.5, river_width * 0.5 + 5.5)
			if free.call(pt, 1.0):
				place.call("dead_tree" if rng.randf() < 0.45 else "dead_shrub", pt, rng.randf_range(0.8, 1.15), 0.06)
		for k in range(rng.randi_range(6, 9)):
			var seg := rng.randi() % (_river.size() - 1)
			var a: Vector2 = _river[seg]
			var b: Vector2 = _river[seg + 1]
			var along := a.lerp(b, rng.randf())
			var side := (b - a).normalized().rotated(PI * 0.5)
			var pt := along + side * rng.randf_range(-river_width * 0.4, river_width * 0.4)
			if free.call(pt, 0.8, true):
				var bone := rng.randf()
				place.call("skull" if bone < 0.35 else ("bones" if bone < 0.7 else "skull_small"), pt, rng.randf_range(0.8, 1.2), 0.0)
	# --- rock fields near the rim, skulls among the stones
	var rocks: Array = []
	for c in range(rng.randi_range(3, 4)):
		var centre: Vector2 = spot.call(3.0, 36.0, arena_radius - 7.0, greens + rocks, 16.0)
		if centre == Vector2.INF:
			continue
		rocks.append(centre)
		for k in range(rng.randi_range(1, 2)):
			var pt: Vector2 = around.call(centre, 0.0, 4.0, 1.5)
			if pt != Vector2.INF:
				place.call("boulder", pt, rng.randf_range(0.85, 1.15), 0.0)
		for k in range(rng.randi_range(3, 4)):
			var pt: Vector2 = around.call(centre, 1.0, 7.0, 0.8)
			if pt != Vector2.INF:
				place.call("rock_big", pt, rng.randf_range(0.85, 1.15), 0.0)
		for k in range(rng.randi_range(6, 9)):
			var pt: Vector2 = around.call(centre, 1.0, 9.0, 0.4)
			if pt != Vector2.INF:
				place.call("rock_small", pt, rng.randf_range(0.7, 1.2), 0.0)
		for k in range(rng.randi_range(2, 3)):
			var pt: Vector2 = around.call(centre, 2.0, 9.0, 0.5)
			if pt != Vector2.INF:
				place.call("skull" if rng.randf() < 0.5 else "bones", pt, rng.randf_range(0.8, 1.2), 0.0)
	# --- a few lone things: bushes and shrubs in the open, three signposts near the flats (hidden since pass 49)
	for k in range(6):
		var pt: Vector2 = spot.call(1.5, 16.0, arena_radius - 8.0, [], 0.0)
		if pt != Vector2.INF:
			place.call(["desert_bush", "creosote_bush", "dead_shrub"][rng.randi() % 3], pt, rng.randf_range(0.8, 1.2), 0.08)
	for k in range(3):
		var pt: Vector2 = spot.call(3.0, 18.0, 34.0, [], 0.0)
		if pt != Vector2.INF:
			place.call("signpost", pt, 1.0, 0.0)
	# --- bush patches (pass 61): last, so every other region keeps the very spots it had for a seed and the patches find
	# the open ground between them. Each centre on the sand inside the red-rock rim, clear of the flats (the patch's half
	# width past them), the lake's greenery, the river bed (the patch's 0.6 off it, so its bushes stand on the open sand,
	# not on the banks' dead trees) and every other region's centre; a few bushes round it, nearer the middle than the
	# edge, BUSH_SPACING apart
	var away: Array = greens.slice(maxi(_lake_cs.size(), 1)) + rocks
	for c in range(rng.randi_range(BUSH_PATCHES.x, BUSH_PATCHES.y)):
		var centre := Vector2.INF
		# (pass 80: a map still short of BUSH_PATCHES.x patches gets BUSH_EXTRA_TRIES more, out to 10 m inside the wall and
		# the regions closer still)
		for k in range(300 if _bush_patches.size() >= BUSH_PATCHES.x else 300 + BUSH_EXTRA_TRIES):
			# on the open sand between the flats and the red-rock rim; past half the tries the regions may close in a little
			var a := rng.randf() * TAU
			var r := rng.randf_range(flats_radius + 6.0, rim_start - 1.0 if k < 300 else arena_radius - 10.0)
			var pt := Vector2(cos(a) * r, sin(a) * r)
			var apart := BUSH_PATCH_APART if k < 150 else BUSH_PATCH_APART * (0.75 if k < 300 else 0.6)
			if (pt - fc).length() < flats_radius + 3.0 + BUSH_PATCH_R * 0.5:
				continue
			# (pass 80: two or three oases take much of the sand, so past BUSH_LAKE_RELAX of the tries a patch may stand at
			# the outer greenery of an oasis, BUSH_LAKE_NEAR m off the water instead of 11)
			if _lake_edge(pt) < (11.0 if k < BUSH_LAKE_RELAX else BUSH_LAKE_NEAR) + BUSH_PATCH_R * 0.6:
				continue
			if _river_dist(pt) < river_width * 0.5 + BUSH_PATCH_R * 0.6:
				continue
			if not free.call(pt, 1.0):
				continue
			var ok := true
			for q: Vector2 in away:
				if pt.distance_to(q) < apart:
					ok = false
					break
			if ok:
				centre = pt
				break
		if centre == Vector2.INF:
			continue
		away.append(centre)
		var bushes: Array = []
		for k in range(rng.randi_range(BUSH_PER_PATCH.x, BUSH_PER_PATCH.y)):
			var pt: Vector2 = around.call(centre, 0.0, BUSH_PATCH_R, BUSH_SPACING)
			if pt == Vector2.INF:
				continue
			var id: String = pick.call(BUSH_IDS)
			if place.call(id, pt, rng.randf_range(0.8, 1.15), 0.07):
				bushes.append({"id": id, "pos": pt})
		if not bushes.is_empty():
			_bush_patches.append({"center": centre, "radius": BUSH_PATCH_R, "bushes": bushes})


func _sprite_collider(g: Vector3, r: float, h: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = maxf(h, 1.0)
	cs.shape = shape
	cs.position.y = maxf(h, 1.0) * 0.5
	body.add_child(cs)
	body.position = g
	add_child(body)
	# creatures steer around the painting's foot, not around a halo of it
	obstacles.append(Vector3(g.x, g.z, r + 0.08))
