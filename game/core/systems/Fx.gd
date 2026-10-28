## Cheap visual effects. Every burst, puff, spark and flash is one instance in one of five pooled MultiMeshes
## (spheres with alpha, opaque shards, flame tongues, musical notes, soft dust), so a hundred deaths a minute cost five
## draw calls and no nodes; the death splashes (pass 58) have a sixth pool of their own, animated by its shader.
## Lightning bolts are ribbons in two shared ImmediateMeshes, a coloured sheath and a white core (pass 33.8: two nodes,
## two materials and two draw calls per strike before). Lights are skipped on phones.
class_name Fx
extends Node3D

const MAX_P := 400
## Pass 110 (lane VFX): room past MAX_P that only the effects marked `must` may take (an Elite's burst, a rocket's
## explosion, the sparks of a launch...). Before, `must` only spared an effect the budget's thinning: at the cap (a
## late-game crowd holds the pool at 394 of 400) it was dropped like the rest. The pools hold POOL_MAX.
const MUST_RESERVE := 120
const POOL_MAX := MAX_P + MUST_RESERVE

# per particle
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _s0 := PackedFloat32Array()
var _s1 := PackedFloat32Array()
var _a0 := PackedFloat32Array()
var _a1 := PackedFloat32Array()
var _grav := PackedFloat32Array()
var _col := PackedColorArray()
var _shard := PackedByteArray()   # 1 = box shard pool, 0 = sphere pool, 2 = flame pool, 3 = note pool, 4 = dust pool
var _seed := PackedFloat32Array()  # flames: where each one reads the noise, so no two burn alike; notes: glyph + phase
var _blue := PackedByteArray()     # flames: 1 = the blue palette (pass 48: Methanol, Moonshine), the shader's custom z
var _n := 0

var _sph_mm: MultiMesh
var _box_mm: MultiMesh
## Flame tongues (pass 33): camera-facing quads drawn by core/shaders/fire_billboard.gdshader
var _flame_mm: MultiMesh
const FLAME_ORANGE := Color(1.0, 0.56, 0.13)
## A blue flame's body (pass 48: Methanol and Moonshine burn blue); the shader swaps its heart and rim to match. The blue
## drop and sparks go with it.
const FLAME_BLUE := Color(0.3, 0.56, 1.0)
const DROP_BLUE := Color(0.36, 0.62, 1.0)
const SPARK_BLUE := Color(0.62, 0.82, 1.0)
## Musical notes (pass 46, the Guitarra's cone of melody): camera-facing glyphs cut from art/fx/notes.png by
## core/shaders/note_billboard.gdshader; they pop in, wobble, slow down and fade.
var _note_mm: MultiMesh
## Dust puffs (pass 50, the Bull Beetle's charge): camera-facing quads drawn by core/shaders/dust_puff.gdshader, soft
## clouds frayed by the flames' noise; they drift, slow, swell and thin out.
var _dust_mm: MultiMesh
const DUST_DRAG := 1.8
## The death splash (pass 58, Garry: "a red splash VFX ... a kind of a puff or something. This way it will make it easier
## to tell when an enemy died. It should[n't] be a lot, but it should be noticeable saturated colour that is visible on
## enemies when they die. The animation is brief. The colour ... is different for different enemies"): a splat in the
## creature's own blood (EnemyDef.blood) at its body, popping open and breaking up in about a third of a second, and a few
## drops flung out of it. A pool of its own, apart from the shared particles above (perf_late: they sit at their cap, 394
## of 400, all through a late-game crowd, so a splash there would be thinned away): a ring of BLOOD_MAX instances on one
## MultiMesh, drawn by core/shaders/blood_splash.gdshader, which moves, sizes and fades every piece from what was written
## once when it was thrown, so the only work a frame is the clock. The cap is the ring: past it the oldest pieces, nearly
## faded, are reused. A regular creature's splash throws fewer drops while many die at once (BLOOD_BUSY_*), and its
## splat is smaller when a crowd dies in the same moment (BLOOD_BURST_*); the splat always shows, and an Elite's and a
## boss's are never thinned.
const BLOOD_MAX := 384
## The splat's width against the creature's size (its painting's height in metres) and its life in seconds; an Elite's
## and a boss's splash (any elite-modded creature's too) are BLOOD_BIG times as wide and live longer. Past BLOOD_SOFT m
## the splash grows only with the square root of the size (blood_size; pass 58 review: a boss's splat was 4.2 m across,
## a third of the screen, and hid its fall): the Brander's is 2.6 m across, still the biggest.
const BLOOD_SPLAT := 0.62
const BLOOD_SOFT := 2.0
const BLOOD_LIFE := 0.36
const BLOOD_BIG := [1.0, 1.2, 1.3]
## Drops a splash throws (a regular creature, an Elite, a boss); with more than BLOOD_BUSY_MID deaths in the last moment a
## regular one throws half as many, past BLOOD_BUSY_HIGH two, past BLOOD_BUSY_MAX none (`_blood_busy` decays by
## BLOOD_BUSY_DECAY a second: ten deaths a second hold it near five)
const BLOOD_DROPS := [6, 10, 16]
const BLOOD_BUSY_MID := 8.0
const BLOOD_BUSY_HIGH := 16.0
const BLOOD_BUSY_MAX := 48.0
const BLOOD_BUSY_DECAY := 2.0
## A crowd dying in the same moment (an explosion, a hammer, a black hole; pass 58 review: 37 killed at once had merged
## into one sheet of colour at the late zoom): `_blood_burst` counts deaths with a short memory (it falls by
## BLOOD_BURST_DECAY a second, so thirty deaths a second, two at a time, hold it near four). Past BLOOD_BURST_FROM a
## regular creature's splat shrinks, down to BLOOD_BURST_SHRINK of its width and BLOOD_BURST_SHORT of its life
## BLOOD_BURST_SPAN deaths later, so a mass kill reads as many small pops; a lone death, a pair and a steady stream keep
## the full splat.
const BLOOD_BURST_DECAY := 10.0
const BLOOD_BURST_FROM := 3.0
const BLOOD_BURST_SPAN := 10.0
const BLOOD_BURST_SHRINK := 0.55
const BLOOD_BURST_SHORT := 0.75
## Where the body is: the splash starts this share of the creature's size above its feet; it is drawn BLOOD_TOWARD m
## (and a quarter of its size) towards the camera, so it lies over the dying creature's painting
const BLOOD_BODY := 0.55
const BLOOD_TOWARD := 0.45
const BLOOD_GRAV := 14.0
## Over the other effects (an Elite's gold burst must not wash over its splash)
const BLOOD_PRIORITY := 1
var _blood_mm: MultiMesh
var _blood_mat: ShaderMaterial
var _blood_end := PackedFloat32Array()   # per slot: when its piece is gone (Fx's clock)
## per slot, kept here as well as on the MultiMesh (a headless run's renderer gives nothing back): its kind (0 the splat,
## 1 a drop), its colour and its size at its fullest
var _blood_kind := PackedByteArray()
var _blood_col := PackedColorArray()
var _blood_w := PackedFloat32Array()
var _blood_head := 0                     # the next slot of the ring
var _blood_used := 0                     # slots written so far (drawn while anything lives)
var _blood_clock := 0.0                  # Fx's own clock (it stops with the game); the shader's `now`
var _blood_last := -1.0                  # when the last piece is gone
var _blood_busy := 0.0                   # deaths lately (decaying)
var _blood_burst := 0.0                  # deaths this very moment (decaying fast)
## its own random sequence: the shared one is replayed by the tests, and a death must not shift it
var _blood_rng := RandomNumberGenerator.new()
const NOTES_PNG := "res://art/fx/notes.png"
const NOTE_CELLS := 4
const NOTE_DRAG := 1.6
## Barrel Rush's gold (pass 47).
const RUSH_GOLD := Color(1.0, 0.8, 0.28)
## The hero's speed trails (pass 48, Garry: "the speed VFX after a barrel looks bad, simpler; a different, stronger one
## for the movement power-up; both must work together"): one ribbon per source along the last seconds of his path, a
## point every RUSH_TRAIL_STEP, widest at his back and nothing at its tail, facing the camera and additive, each at its
## own height so two or three run side by side: Barrel Rush's thin faint gold at the hips ("gold"), a Sprint's strong blue
## higher up ("blue", with its wind: wind()), Skedaddle's red lower down ("red"). One ImmediateMesh per source in the
## glow-ribbon material, rebuilt only while it has points. RUSH_TRAIL_SECONDS is the gold one's length in seconds.
const RUSH_TRAIL_SECONDS := 0.45
const RUSH_TRAIL_STEP := 0.025
const RUSH_TRAIL_HIP := 0.85
const SPRINT_BLUE := Color(0.3, 0.72, 1.0)
const SKEDADDLE_RED := Color(1.0, 0.24, 0.18)
## per source: colour, height above his feet, width at his back (m), brightness there, seconds of tail
const TRAILS := {
	"gold": {"col": RUSH_GOLD, "hip": RUSH_TRAIL_HIP, "width": 0.3, "alpha": 0.42, "seconds": RUSH_TRAIL_SECONDS},
	"blue": {"col": SPRINT_BLUE, "hip": 1.3, "width": 0.95, "alpha": 0.9, "seconds": 0.55},
	"red": {"col": SKEDADDLE_RED, "hip": 0.42, "width": 0.6, "alpha": 0.75, "seconds": 0.4},
}
var _trails: Dictionary = {}   # source -> SpeedTrail
## A Sprint's wind (pass 48): thin blue-white streaks rushing back past the running hero at every height from his knees
## to over his head (standing, they rise round him), feathered at both ends; one ImmediateMesh, rebuilt while any live.
const WIND_COL := Color(0.62, 0.88, 1.0)
const WIND_MAX := 28
const WIND_WIDTH := 0.07
var _wind_pos := PackedVector3Array()   # each streak's head
var _wind_vel := PackedVector3Array()
var _wind_age := PackedFloat32Array()
var _wind_life := PackedFloat32Array()
var _wind_len := PackedFloat32Array()
var _wind_clock := 0.0
var _wind_mesh: ImmediateMesh
var _live := 0   # bolts still showing
const MAX_LIVE := 40
## live bolts: {sheath: PackedVector3Array, core: PackedVector3Array (triangles, built once), color: Color, t: seconds}
var _bolts: Array = []
var _sheath_mesh: ImmediateMesh
var _core_mesh: ImmediateMesh
var _sheath_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _bolts_drawn := false
const SHEATH_LIFE := 0.32
const CORE_LIFE := 0.26


## Whether short-lived point lights are worth it on this device (never on phones: every lit pixel pays for them).
static func want_lights() -> bool:
	return not OS.has_feature("mobile")


func _ready() -> void:
	_pos.resize(POOL_MAX); _vel.resize(POOL_MAX); _age.resize(POOL_MAX); _life.resize(POOL_MAX)
	_s0.resize(POOL_MAX); _s1.resize(POOL_MAX); _a0.resize(POOL_MAX); _a1.resize(POOL_MAX); _grav.resize(POOL_MAX)
	_col.resize(POOL_MAX); _shard.resize(POOL_MAX); _seed.resize(POOL_MAX); _blue.resize(POOL_MAX)
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 8
	s.rings = 4
	_sph_mm = _pool(s, true)
	var b := BoxMesh.new()
	b.size = Vector3(0.26, 0.26, 0.26)
	_box_mm = _pool(b, false)
	_flame_mm = _flame_pool()
	_note_mm = _note_pool()
	_dust_mm = _dust_pool()
	_blood_pool()
	_blast_pool()
	_build_bolt_meshes()
	# one invisible note far under the map on the first frames, so the note shader compiles with the rest of the start
	# (under the spawn beam), not on the guitar's first chord
	_emit(Vector3(0, -60.0, 0), Vector3.ZERO, 0.5, 0.1, 0.1, 0.01, 0.0, Color(1, 1, 1), 0.0, false, true)
	_shard[_n - 1] = 3
	_seed[_n - 1] = 0.0
	# and one puff of dust (pass 50), so the dust shader compiles with them (its seed fixed: the start draws nothing from
	# the shared random sequence, which the tests replay)
	_emit_dust(Vector3(0, -60.0, 0), Vector3.ZERO, 0.5, 0.1, 0.1, 0.01, Color(1, 1, 1), true, 0.0)
	# and one piece of blood (pass 58) for its shader, kept out of blood_count
	_blood_piece(Vector3(0, -60.0, 0), Vector3(0, 0.1, 0), 0.1, 0.1, 0.0, 0.5, 0.0, 0.0, Color(1, 1, 1), 0.0, 0.0, 0.0)
	_blood_end[0] = 0.0


## The two meshes every bolt is drawn into: see-through, both sides, over everything (as the per-strike ones were).
func _build_bolt_meshes() -> void:
	_sheath_mat = _bolt_material(0)
	_core_mat = _bolt_material(1)
	_sheath_mesh = ImmediateMesh.new()
	_core_mesh = ImmediateMesh.new()
	for pair in [[_sheath_mesh, _sheath_mat], [_core_mesh, _core_mat]]:
		var mi := MeshInstance3D.new()
		mi.mesh = pair[0]
		mi.material_override = pair[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
		mi.top_level = true
		add_child(mi)


func _bolt_material(priority: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = priority
	return mat


## The flame pool: unit quads that the fire shader turns to the camera and stands on their base.
func _flame_pool() -> MultiMesh:
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = POOL_MAX
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://core/shaders/fire_billboard.gdshader")
	mat.set_shader_parameter("noise_tex", load("res://art/fx/fire_noise.png"))
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(mmi)
	return mm


## The note pool: unit quads the note shader turns to the camera, each showing one cell of the atlas.
func _note_pool() -> MultiMesh:
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = POOL_MAX
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://core/shaders/note_billboard.gdshader")
	var tex := note_atlas()
	mat.set_shader_parameter("has_atlas", tex != null)
	if tex:
		mat.set_shader_parameter("atlas", tex)
	mat.set_shader_parameter("cells", float(NOTE_CELLS))
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -80, -200), Vector3(400, 120, 400))
	add_child(mmi)
	return mm


## The dust pool (pass 50): unit quads the dust shader turns to the camera, each a soft cloud frayed by the noise the
## flames use.
func _dust_pool() -> MultiMesh:
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = POOL_MAX
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://core/shaders/dust_puff.gdshader")
	mat.set_shader_parameter("noise_tex", load("res://art/fx/fire_noise.png"))
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -80, -200), Vector3(400, 120, 400))
	add_child(mmi)
	return mm


## The blood pool (pass 58): unit quads the splash shader moves and faces to the camera. Its instance transforms are data
## (see core/shaders/blood_splash.gdshader), so both bounding boxes are fixed: no box is ever worked out from them.
func _blood_pool() -> void:
	_blood_end.resize(BLOOD_MAX)
	_blood_kind.resize(BLOOD_MAX)
	_blood_col.resize(BLOOD_MAX)
	_blood_w.resize(BLOOD_MAX)
	_blood_rng.randomize()
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = BLOOD_MAX
	mm.visible_instance_count = 0
	mm.custom_aabb = AABB(Vector3(-200, -80, -200), Vector3(400, 120, 400))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Blood"
	mmi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://core/shaders/blood_splash.gdshader")
	mat.set_shader_parameter("noise_tex", load("res://art/fx/fire_noise.png"))
	mat.render_priority = BLOOD_PRIORITY
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -80, -200), Vector3(400, 120, 400))
	add_child(mmi)
	_blood_mm = mm
	_blood_mat = mat


## One piece of blood into the ring: it starts at `at` `delay` seconds from now and flies on `vel` under `grav`, from
## `s0` to `s1` metres across over `life` seconds; `stretch` how much longer a drop is drawn per m/s; `kind` 0 the splat,
## 1 a drop; `toward` metres towards the camera.
func _blood_piece(at: Vector3, vel: Vector3, s0: float, s1: float, grav: float, life: float, delay: float, stretch: float, col: Color, seed_v: float, kind: float, toward: float) -> void:
	var i := _blood_head
	_blood_head = (_blood_head + 1) % BLOOD_MAX
	_blood_used = maxi(_blood_used, i + 1)
	var birth := _blood_clock + delay
	_blood_mm.set_instance_transform(i, Transform3D(Basis(vel, Vector3(s0, s1, grav), Vector3(birth, maxf(life, 0.01), stretch)), at))
	_blood_mm.set_instance_color(i, Color(col.r, col.g, col.b, 1.0))
	_blood_mm.set_instance_custom_data(i, Color(seed_v, kind, toward, 0.0))
	_blood_end[i] = birth + life
	_blood_kind[i] = 1 if kind > 0.5 else 0
	_blood_col[i] = Color(col.r, col.g, col.b, 1.0)
	_blood_w[i] = maxf(s0, s1)
	_blood_last = maxf(_blood_last, birth + life)
	_blood_mm.visible_instance_count = _blood_used
	_blood_mat.set_shader_parameter("now", _blood_clock)


## A creature's death splash (pass 58): `at` its feet, `col` its blood (EnemyDef.blood), `size` its size (the painting's
## height in metres), `big` 0 a regular creature, 1 an Elite (or any elite-modded one), 2 a boss. A splat at its body that
## pops open in the creature's colour with a pale hot middle and breaks into spatter, and drops flung out across the
## screen that fall and shrink; a boss's bursts twice.
func blood(at: Vector3, col: Color, size: float = 1.0, big: int = 0) -> void:
	if Run.sim_mode:
		return
	if _blood_mm == null:
		return
	big = clampi(big, 0, 2)
	var k: float = BLOOD_BIG[big]
	var s: float = maxf(size, 0.3)
	# the splash's own size (past BLOOD_SOFT only the square root); the body it starts at is the creature's own
	var sw: float = blood_size(s)
	var c := at + Vector3(0.0, s * BLOOD_BODY, 0.0)
	var toward: float = BLOOD_TOWARD + s * 0.25
	_blood_busy += 1.0
	_blood_burst += 1.0
	# the screen's own axes, so the drops fly out across it (the camera is north-up: right is east)
	var right := Vector3.RIGHT
	var up := Vector3.UP
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam:
		right = cam.global_transform.basis.x.normalized()
		up = cam.global_transform.basis.y.normalized()
	# a crowd dying in the same moment: a regular creature's splat smaller and shorter (many small pops, not one sheet)
	var thin := 0.0
	if big == 0:
		thin = clampf((_blood_burst - BLOOD_BURST_FROM) / BLOOD_BURST_SPAN, 0.0, 1.0)
	var w: float = sw * BLOOD_SPLAT * k * lerpf(1.0, BLOOD_BURST_SHRINK, thin)
	var life: float = BLOOD_LIFE * lerpf(1.0, k, 1.5) * lerpf(1.0, BLOOD_BURST_SHORT, thin)
	# the drops first: a MultiMesh draws in slot order, so the splat written after them lies on top and they burst out
	# from under its edge (on top they read as beads stuck to it)
	var n: int = BLOOD_DROPS[big]
	if big == 0:
		if _blood_busy > BLOOD_BUSY_MAX:
			n = 0
		elif _blood_busy > BLOOD_BUSY_HIGH:
			n = 2
		elif _blood_busy > BLOOD_BUSY_MID:
			n = int(n * 0.5)
	for j in range(n):
		var a: float = TAU * (float(j) + _blood_rng.randf() * 0.8) / float(n)
		var dir: Vector3 = right * cos(a) + up * sin(a) * 0.85
		var sp: float = _blood_rng.randf_range(2.2, 4.4) * (0.75 + 0.25 * sw) * lerpf(1.0, k, 0.5)
		var v: Vector3 = dir * sp + Vector3(0.0, _blood_rng.randf_range(1.2, 2.8), 0.0)
		var d: float = sw * _blood_rng.randf_range(0.1, 0.17) * lerpf(1.0, k, 0.5)
		_blood_piece(c + dir * w * 0.15, v, d, d * 0.45, BLOOD_GRAV, _blood_rng.randf_range(0.26, 0.4) * lerpf(1.0, k, 1.2),
			_blood_rng.randf_range(0.0, 0.03), 0.06, col, _blood_rng.randf(), 1.0, toward)
	_blood_piece(c, Vector3(0, 0.45, 0), w * 0.3, w, 0.0, life, 0.0, 0.0, col, _blood_rng.randf(), 0.0, toward)
	if big == 2:
		# a boss bursts twice: a second splat a beat later, beside the first
		var o := (right * _blood_rng.randf_range(-0.25, 0.25) + up * _blood_rng.randf_range(0.05, 0.3)) * sw
		_blood_piece(c + o, Vector3(0, 0.6, 0), w * 0.25, w * 0.8, 0.0, life, 0.14, 0.0, col, _blood_rng.randf(), 0.0, toward + 0.1)


## The size a creature's splash is drawn for (pass 58 review): its own up to BLOOD_SOFT m, past it growing only with the
## square root (the Brander, 5.2 m tall, splashes as if 3.2 m).
static func blood_size(size: float) -> float:
	if size <= BLOOD_SOFT:
		return size
	return BLOOD_SOFT * sqrt(size / BLOOD_SOFT)


## How many pieces of blood are showing or about to (tests: a splash shows, then is gone within a second).
func blood_count() -> int:
	var n := 0
	for i in range(_blood_used):
		if _blood_end[i] > _blood_clock:
			n += 1
	return n


## The colours of the pieces showing now (tests: a splash is in the creature's own colour).
func blood_colors() -> Array:
	var out: Array = []
	for i in range(_blood_used):
		if _blood_end[i] > _blood_clock:
			out.append(_blood_col[i])
	return out


## The splats showing now, as their widths at their fullest (tests: one a death, two for a boss, wider for bigger ones).
func blood_splats() -> Array:
	var out: Array = []
	for i in range(_blood_used):
		if _blood_end[i] > _blood_clock and _blood_kind[i] == 0:
			out.append(_blood_w[i])
	return out


## How many drops are flying now (tests).
func blood_drops() -> int:
	var n := 0
	for i in range(_blood_used):
		if _blood_end[i] > _blood_clock and _blood_kind[i] == 1:
			n += 1
	return n


## Fx's clock and the shader's `now`; the pool stops drawing once its last piece is gone.
func _tick_blood(delta: float) -> void:
	_blood_clock += delta
	_blood_busy *= exp(-BLOOD_BUSY_DECAY * delta)
	_blood_burst *= exp(-BLOOD_BURST_DECAY * delta)
	if _blood_mm == null or _blood_mm.visible_instance_count == 0:
		return
	if _blood_clock > _blood_last:
		_blood_mm.visible_instance_count = 0
		return
	_blood_mat.set_shader_parameter("now", _blood_clock)


## The notes' atlas: NOTE_CELLS glyphs side by side. Read straight from the PNG while it waits for its import (a new
## file the editor has not seen), so the notes show from the first run; null when it is not there at all.
static func note_atlas() -> Texture2D:
	if ResourceLoader.exists(NOTES_PNG):
		var t = load(NOTES_PNG)
		if t is Texture2D:
			return t
	if FileAccess.file_exists(NOTES_PNG):
		var img := Image.load_from_file(ProjectSettings.globalize_path(NOTES_PNG))
		if img and not img.is_empty():
			img.generate_mipmaps()
			return ImageTexture.create_from_image(img)
	return null


func _pool(mesh: Mesh, alpha: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = POOL_MAX
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	if alpha:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(mmi)
	return mm


## How much of the effect budget a spawn may use: full while the fight is small, a third of the particles once the
## crowd is at its cap, so a hundred hits a second do not each pay for a puff (the phone's fill rate, not the CPU).
func _busy_skip() -> bool:
	if _n < MAX_P / 3:
		return false
	if _n >= MAX_P * 3 / 4:
		return randf() < 0.66
	return randf() < 0.33


func _emit(at: Vector3, vel: Vector3, life: float, s0: float, s1: float, a0: float, a1: float, col: Color, grav := 0.0, shard := false, must := false) -> void:
	if Run.sim_mode:
		return
	if _n >= (POOL_MAX if must else MAX_P):
		return
	if not must and _busy_skip():
		return
	var i := _n
	_n += 1
	_pos[i] = at; _vel[i] = vel; _age[i] = 0.0; _life[i] = maxf(life, 0.01)
	_s0[i] = s0; _s1[i] = s1; _a0[i] = a0; _a1[i] = a1; _grav[i] = grav
	_col[i] = col; _shard[i] = 1 if shard else 0; _blue[i] = 0


## One flame tongue: it grows from `s0` to `s1` metres tall while the shader's noise eats it away with age. `blue` (pass
## 48) burns it in the blue palette: a blue body (FLAME_BLUE at `col`'s alpha) and the shader's blue heart and rim.
func _emit_flame(at: Vector3, vel: Vector3, life: float, s0: float, s1: float, col: Color, must := false, blue := false) -> void:
	if Run.sim_mode:
		return
	if _n >= (POOL_MAX if must else MAX_P):
		return
	if not must and _busy_skip():
		return
	var i := _n
	_n += 1
	if blue:
		col = Color(FLAME_BLUE.r, FLAME_BLUE.g, FLAME_BLUE.b, col.a)
	_pos[i] = at; _vel[i] = vel; _age[i] = 0.0; _life[i] = maxf(life, 0.01)
	_s0[i] = s0; _s1[i] = s1; _a0[i] = col.a; _a1[i] = col.a * 0.85; _grav[i] = 0.0
	_col[i] = col; _shard[i] = 2; _seed[i] = randf(); _blue[i] = 1 if blue else 0


## One dust puff (pass 50): a soft cloud from `s0` to `s1` metres across over `life` seconds, `a0` opaque at first and
## thinning to nothing, fraying as it ages (the shader). `noise_seed` places its noise (negative: a random one).
func _emit_dust(at: Vector3, vel: Vector3, life: float, s0: float, s1: float, a0: float, col: Color, must := false, noise_seed := -1.0) -> void:
	if Run.sim_mode:
		return
	if _n >= (POOL_MAX if must else MAX_P):
		return
	if not must and _busy_skip():
		return
	var i := _n
	_n += 1
	_pos[i] = at; _vel[i] = vel; _age[i] = 0.0; _life[i] = maxf(life, 0.01)
	_s0[i] = s0; _s1[i] = s1; _a0[i] = a0; _a1[i] = 0.0; _grav[i] = 0.0
	_col[i] = col; _shard[i] = 4; _seed[i] = randf() if noise_seed < 0.0 else noise_seed; _blue[i] = 0


## A flame standing on `at`, `height` metres tall at its fullest (a burning pool, a Berserk hero); `blue` (pass 48) in
## the blue palette.
func flame(at: Vector3, height: float, life: float = 0.55, col: Color = FLAME_ORANGE, blue: bool = false) -> void:
	_emit_flame(at, Vector3(randf_range(-0.12, 0.12), randf_range(0.5, 0.9), randf_range(-0.12, 0.12)), life, height * 0.5, height, col, false, blue)


## A drop of burning oil falling from `at` for `fall` seconds (the Oil Slick's leak); `blue` (pass 48: Methanol) a blue one.
func drop(at: Vector3, fall: float, blue: bool = false) -> void:
	_emit(at, Vector3(0, -0.5, 0), maxf(fall, 0.05), 0.2, 0.14, 1.0, 1.0, DROP_BLUE if blue else Color(1.0, 0.62, 0.2), 24.0)


## `must` (pass 110): never thinned by the budget and allowed into the pool's reserve (the Nuke's flash).
func burst(at: Vector3, color: Color, size: float = 1.0, strength: float = 1.0, must := false) -> void:
	# the coloured cloud that grows and fades, and a hot white core that pops first so the burst has a snap
	_emit(at, Vector3.ZERO, 0.34, 0.2, size * 2.2, 0.9, 0.0, color, 0.0, false, must)
	_emit(at, Vector3.ZERO, 0.16, 0.1, size * 1.1, 0.95, 0.0, Color(1, 1, 1), 0.0, false, must)
	if strength > 1.0:
		burst_strength(at, color, size, strength)


## The extra of a strong burst (pass 53, the Heavy Warhead's `blast_fx`; Garry: "the visual of the explosion becomes
## 'stronger' looking"): a wide white flash that pops (`flash`), a second hotter ball swelling up, and a ring of sparks
## flung out and up, more of them as `strength` grows past 1. None of it is thinned for the budget: a rocket's blast must
## read.
func burst_strength(at: Vector3, color: Color, size: float, strength: float, flash: bool = true) -> void:
	var k: float = clampf(strength - 1.0, 0.0, 2.0)
	var c := at + Vector3(0, 0.3, 0)
	if flash:
		_emit(c, Vector3.ZERO, 0.14, 0.3 * size, size * (2.6 + 0.8 * k), 1.0, 0.0, Color(1.0, 0.97, 0.88), 0.0, false, true)
	_emit(c, Vector3(0, 1.2, 0), 0.4, 0.3 * size, size * (1.6 + 0.5 * k), 0.9, 0.0, color.lerp(Color(1.0, 0.5, 0.12), 0.5), 0.0, false, true)
	var n: int = int(8 + 6 * k)
	for j in range(n):
		var a: float = TAU * float(j) / float(n) + randf() * 0.3
		var v := Vector3(cos(a), 0, sin(a)) * randf_range(3.5, 6.5) * (0.6 + 0.4 * size) + Vector3(0, randf_range(2.5, 5.5), 0)
		_emit(c, v, randf_range(0.35, 0.6), 0.5, 0.1, 1.0, 0.9, Color(1.0, 0.82, 0.35), 12.0, true, true)


## A big explosion (pass 33.3, the rocketeer's rocket), `r` metres: a white flash that pops, orange and red balls
## swelling out of it, a fireball of flame tongues thrown out and up, sparks and grit flung wide, and a beat later dark
## smoke rolling up where it was. None of it is thinned for the budget: it is the one thing on screen that must read.
func explosion(at: Vector3, r: float = 1.6) -> void:
	var c := at + Vector3(0, 0.45, 0)
	_emit(c + Vector3(0, 0.35, 0), Vector3.ZERO, 0.16, 0.5 * r, 2.3 * r, 1.0, 0.0, Color(1.0, 0.97, 0.86), 0.0, false, true)
	for k in range(6):
		var o := Vector3(randf_range(-0.55, 0.55), randf_range(0.1, 0.8), randf_range(-0.55, 0.55)) * r
		var col := Color(1.0, 0.62 + 0.2 * randf(), 0.18) if k % 2 == 0 else Color(1.0, 0.32, 0.08)
		_emit(c + o, o * 1.6 + Vector3(0, 1.4, 0), randf_range(0.38, 0.55), 0.35 * r, randf_range(1.0, 1.4) * r, 0.95, 0.0, col, 0.0, false, true)
	for k in range(14):
		var a := TAU * float(k) / 14.0 + randf() * 0.4
		var out := Vector3(cos(a), 0, sin(a))
		var h: float = randf_range(1.0, 1.7) * r
		_emit_flame(c + out * 0.35 * r, out * randf_range(1.2, 2.8) * r + Vector3(0, randf_range(1.8, 3.6), 0), randf_range(0.45, 0.7), h * 0.45, h, FLAME_ORANGE, true)
	for k in range(18):
		var a2 := randf() * TAU
		var v := Vector3(cos(a2), 0, sin(a2)) * randf_range(4.0, 9.0) + Vector3(0, randf_range(3.0, 7.5), 0)
		_emit(c, v, randf_range(0.45, 0.85), 0.75, 0.15, 1.0, 0.9, Color(1.0, 0.82, 0.35), 14.0, true, true)
	for k in range(8):
		var a3 := randf() * TAU
		var v3 := Vector3(cos(a3), 0, sin(a3)) * randf_range(3.0, 6.5) + Vector3(0, randf_range(4.0, 8.0), 0)
		_emit(at + Vector3(0, 0.2, 0), v3, randf_range(0.6, 0.95), 1.3, 0.8, 1.0, 1.0, Color(0.36, 0.22, 0.14), 20.0, true, true)
	for k in range(5):
		var a4 := TAU * float(k) / 5.0
		sand(at + Vector3(cos(a4), 0.1, sin(a4)) * r * 0.7, 1.3)
	if want_lights():
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.6, 0.25)
		glow.omni_range = r * 6.0
		glow.light_energy = 6.0
		glow.position = c + Vector3(0, 0.8, 0)
		add_child(glow)
		var tw := create_tween()
		tw.tween_property(glow, "light_energy", 0.0, 0.4)
		tw.tween_callback(glow.queue_free)
	# the smoke comes a beat after the fire, so it rolls up out of the fireball instead of greying it from the start
	get_tree().create_timer(0.12, false).timeout.connect(func() -> void:
		for k in range(8):
			var o2 := Vector3(randf_range(-0.8, 0.8), randf_range(0.3, 1.1), randf_range(-0.8, 0.8)) * r
			_emit(c + o2, Vector3(o2.x * 0.5, randf_range(1.0, 2.0), o2.z * 0.5), randf_range(1.1, 1.7), 0.45 * r, randf_range(1.3, 1.9) * r, 0.62, 0.0, Color(0.2, 0.18, 0.17), -0.4, false, true))


## Sand thrown up from a point: a low tan puff and a spray of grains that fall back (the eruption, a burrow).
func sand(at: Vector3, size: float = 1.0) -> void:
	_emit(at, Vector3(0, 0.6, 0), 0.4, 0.25 * size, 0.8 * size, 0.7, 0.0, Color(0.9, 0.78, 0.55))
	_emit(at, Vector3(0, 1.2, 0), 0.22, 0.15 * size, 0.5 * size, 0.9, 0.0, Color(1.0, 0.95, 0.8))
	for k in range(10):
		var v := Vector3(randf_range(-2.2, 2.2), randf_range(3.0, 6.0), randf_range(-2.2, 2.2)) * size
		_emit(at, v, randf_range(0.35, 0.6), 0.14 * size, 0.06 * size, 1.0, 0.6, Color(0.8, 0.62, 0.38), 12.0, true)


## Sand kicked up round a creature's feet while it is dragged (pass 33.10: the harpooner on its rope, `pull` the way it is
## hauled): two low puffs spread round the feet and a few grains thrown back against the pull.
func drag_dust(at: Vector3, pull: Vector3) -> void:
	var back := -Vector3(pull.x, 0.0, pull.z)
	for k in range(2):
		var off := Vector3(randf_range(-0.6, 0.6), 0.15, randf_range(-0.4, 0.4))
		_emit(at + off, back * 0.7 + Vector3(0, 0.45, 0), randf_range(0.45, 0.6), 0.35, 1.4, 0.7, 0.0, Color(0.9, 0.76, 0.52))
	if _busy_skip():
		return
	for k in range(3):
		var v := back * randf_range(1.0, 2.2) + Vector3(randf_range(-0.8, 0.8), randf_range(1.5, 3.0), randf_range(-0.8, 0.8))
		_emit(at + Vector3(0, 0.1, 0), v, randf_range(0.3, 0.5), 0.12, 0.05, 1.0, 0.6, Color(0.78, 0.6, 0.36), 10.0, true)


## The sand a charging brute throws up (pass 50, Garry: "a dust trail effect behind the Bull Beetle as it runs"): pooled
## puffs and grains like every other burst, thinned by the budget. `back` is the way behind it on the ground (a unit
## vector), `width` how wide its body is in metres, `k` how strong (its charge.dust, 1 a full trail).
const DUST_TAN := Color(0.86, 0.73, 0.52)
const DUST_PALE := Color(0.95, 0.88, 0.72)
const DUST_GRAIN := Color(0.76, 0.58, 0.36)


## One beat of the trail behind a charging brute (thirty a second while it runs): a low puff from under its back end,
## somewhere across its width, that drifts back and up, swells and thins out over most of a second; now and then a paler
## one inside it, and a couple of grains kicked back.
func charge_dust(at: Vector3, back: Vector3, width: float, k: float = 1.0) -> void:
	var side := Vector3(-back.z, 0.0, back.x)
	var o := at + side * randf_range(-0.45, 0.45) * width + Vector3(0, 0.2, 0)
	_emit_dust(o, back * randf_range(0.5, 1.2) + side * randf_range(-0.5, 0.5) + Vector3(0, randf_range(0.3, 0.7), 0),
		randf_range(0.75, 1.05), 0.35 * width, randf_range(1.1, 1.45) * width * k, 0.62 * minf(k, 1.2), DUST_TAN)
	if randf() < 0.4:
		_emit_dust(o + Vector3(0, 0.12, 0), back * 0.4 + Vector3(0, 0.55, 0), 0.55, 0.2 * width, 0.75 * width * k, 0.55, DUST_PALE)
	if _busy_skip():
		return
	for n in range(2):
		var v := back * randf_range(1.5, 3.5) + side * randf_range(-1.0, 1.0) + Vector3(0, randf_range(1.5, 3.2), 0)
		_emit(o, v, randf_range(0.3, 0.5), 0.1, 0.05, 1.0, 0.6, DUST_GRAIN, 12.0, true)


## Sand pawed back from under a brute winding up its charge: a small puff behind it and a spray of grains flung back and
## up, harder as `k` grows towards the launch.
func paw_dust(at: Vector3, back: Vector3, width: float, k: float = 1.0) -> void:
	var side := Vector3(-back.z, 0.0, back.x)
	var o := at + side * randf_range(-0.4, 0.4) * width + Vector3(0, 0.1, 0)
	_emit_dust(o, back * 0.8 + Vector3(0, 0.45, 0), randf_range(0.5, 0.65), 0.2 * width, (0.55 + 0.4 * k) * width, 0.6, DUST_TAN)
	for n in range(2 + int(2.0 * k)):
		var v := back * randf_range(1.2, 2.8) * (0.6 + 0.6 * k) + side * randf_range(-0.8, 0.8) + Vector3(0, randf_range(1.8, 3.4), 0)
		_emit(o, v, randf_range(0.3, 0.45), 0.09, 0.05, 1.0, 0.6, DUST_GRAIN, 12.0, true)


## The launch: a burst of sand thrown back as it springs off, a wide low cloud across its back end and a spray of grains.
## The cloud is never thinned: it is the moment the charge starts.
func charge_launch(at: Vector3, back: Vector3, width: float, k: float = 1.0) -> void:
	var side := Vector3(-back.z, 0.0, back.x)
	for n in range(4):
		var u := float(n) / 3.0 - 0.5
		_emit_dust(at + side * u * width + Vector3(0, 0.2, 0), back * randf_range(1.2, 2.2) + side * u * 1.5 + Vector3(0, randf_range(0.5, 0.9), 0),
			randf_range(0.65, 0.9), 0.4 * width, randf_range(1.2, 1.6) * width * k, 0.7, DUST_TAN, true)
	for n in range(8):
		var v := back * randf_range(2.0, 4.5) + side * randf_range(-1.6, 1.6) + Vector3(0, randf_range(2.0, 4.0), 0)
		_emit(at + Vector3(0, 0.1, 0), v, randf_range(0.35, 0.55), 0.11, 0.05, 1.0, 0.6, DUST_GRAIN, 12.0, true)


## The poof of a creature bursting up out of the sand (pass 60, Garry: "use dust effect from the Bull Beetle, but as a
## poof when Scorpion actually pops out"; the Dune Scorpion's and the Gila's burrow): the launch's soft cloud as one
## burst all round the spot, 12 to 16 puffs flung out and up (a paler one in every three), a column of three rising
## about 1.5 m from the middle, and a spray of grains; never thinned, it is the moment. `size` is the creature's size in
## metres: the body is about 0.7 of it wide, and the puffs are sized to that.
func pop_dust(at: Vector3, size: float = 1.0) -> void:
	var w := maxf(size * 0.7, 0.6)
	var n := 12 + mini(int(size), 4)
	var phase := randf() * TAU
	for k in range(n):
		var ang := phase + TAU * float(k) / float(n)
		var out := Vector3(cos(ang), 0.0, sin(ang))
		var o := at + out * randf_range(0.1, 0.3) * w + Vector3(0, 0.2, 0)
		var v := out * randf_range(0.9, 1.6) * w + Vector3(0, randf_range(0.7, 1.4), 0)
		_emit_dust(o, v, randf_range(0.7, 1.0), 0.35 * w, randf_range(1.1, 1.5) * w, 0.72, DUST_PALE if k % 3 == 1 else DUST_TAN, true)
	for k in range(3):
		# the column: up the middle, each puff a little higher and slower than the last
		var vy := 2.2 - 0.4 * float(k)
		_emit_dust(at + Vector3(randf_range(-0.1, 0.1) * w, 0.25 + 0.3 * float(k), randf_range(-0.1, 0.1) * w), Vector3(0, vy, 0),
			randf_range(0.75, 0.95), 0.3 * w, randf_range(0.8, 1.1) * w, 0.7, DUST_TAN if k != 1 else DUST_PALE, true)
	for k in range(10):
		var ga := randf() * TAU
		var gv := Vector3(cos(ga), 0.0, sin(ga)) * randf_range(1.5, 4.0) * w * 0.5 + Vector3(0, randf_range(2.5, 4.5), 0)
		_emit(at + Vector3(0, 0.1, 0), gv, randf_range(0.35, 0.55), 0.11, 0.05, 1.0, 0.6, DUST_GRAIN, 12.0, true)
	for k in range(6):
		# clods of the mound thrown out and up, falling back under gravity (the Centipede's eruption throws them too)
		var ca := phase + TAU * (float(k) + 0.5) / 6.0
		var cv := Vector3(cos(ca), 0.0, sin(ca)) * randf_range(1.2, 2.2) * w * 0.5 + Vector3(0, randf_range(3.0, 4.5), 0)
		_emit(at + Vector3(cos(ca) * 0.2 * w, 0.25, sin(ca) * 0.2 * w), cv, randf_range(0.5, 0.7), 0.1 * w, 0.07 * w, 1.0, 0.9, CLOD, 12.0, true, true)


## The colour of a clod of packed sand (pass 60, pop_dust): the mound's, a shade deeper than the dust.
const CLOD := Color(0.86, 0.68, 0.42)


## The skid at the end of a charge: sand pushed out ahead and to both sides as it digs in.
func skid_dust(at: Vector3, ahead: Vector3, width: float, k: float = 1.0) -> void:
	var side := Vector3(-ahead.z, 0.0, ahead.x)
	for n in range(3):
		var u := float(n) - 1.0
		_emit_dust(at + side * u * 0.4 * width + Vector3(0, 0.16, 0), ahead * randf_range(0.8, 1.6) + side * u * 1.2 + Vector3(0, 0.4, 0),
			randf_range(0.55, 0.75), 0.3 * width, 1.15 * width * k, 0.6, DUST_TAN)


## A little sand scuffed up at the feet of a creature a charger shoves aside, `dir` the way it is pushed: it trails the
## other way.
func shove_dust(at: Vector3, dir: Vector3) -> void:
	if _busy_skip():
		return
	_emit_dust(at + Vector3(0, 0.15, 0), -dir * 0.6 + Vector3(0, 0.4, 0), 0.5, 0.2, 0.8, 0.55, DUST_TAN)
	for n in range(2):
		var v := -dir * randf_range(1.0, 2.0) + Vector3(randf_range(-0.6, 0.6), randf_range(1.5, 2.5), randf_range(-0.6, 0.6))
		_emit(at + Vector3(0, 0.1, 0), v, randf_range(0.25, 0.4), 0.08, 0.04, 1.0, 0.6, DUST_GRAIN, 12.0, true)


## A mote drifting along `vel` and shrinking as it goes (pass 35: dust drawn into the Singularity's black hole).
func mote(at: Vector3, vel: Vector3, life: float, size: float, col: Color) -> void:
	_emit(at, vel, life, size, size * 0.3, col.a, 0.0, Color(col.r, col.g, col.b))


## A musical note (pass 46, the Guitarra): it pops out at `at` to `size` metres, flies along `vel` slowing as it goes,
## wobbles, and fades over the last half of `life`; `col` tints the white glyph (its outline stays dark), `glyph` picks
## the atlas cell (-1 any).
func note(at: Vector3, vel: Vector3, life: float, size: float, col: Color, glyph: int = -1) -> void:
	if Run.sim_mode:
		return
	if _n >= MAX_P or _busy_skip():
		return
	var i := _n
	_n += 1
	_pos[i] = at; _vel[i] = vel; _age[i] = 0.0; _life[i] = maxf(life, 0.01)
	_s0[i] = size * 0.3; _s1[i] = size; _a0[i] = col.a; _a1[i] = 0.0; _grav[i] = 0.0
	_col[i] = Color(col.r, col.g, col.b); _shard[i] = 3; _blue[i] = 0
	var g: int = glyph if glyph >= 0 else randi() % NOTE_CELLS
	_seed[i] = float(clampi(g, 0, NOTE_CELLS - 1)) + randf() * 0.99


## How many notes are flying (tests).
func note_count() -> int:
	var n := 0
	for i in range(_n):
		if _shard[i] == 3:
			n += 1
	return n


## The material every swept trail shares (pass 35: the Sabre's crescent, the Hammer's smear, the Gravity Gun's beam, the
## Golden Revolver's lines): additive and vertex-coloured, one instance so its shader compiles once, in the warm-up.
static var _glow_ribbon: StandardMaterial3D


## Its see-through twin (not additive), for a ribbon that must keep its colour on bright sand: the Gravity Gun's beam.
static var _tint_ribbon: StandardMaterial3D


static func tint_ribbon_material() -> StandardMaterial3D:
	if _tint_ribbon == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_tint_ribbon = m
	return _tint_ribbon


## The hero's speed trails and a Sprint's wind (pass 49, Garry: "rendered underneath the 2.5d sprite of the hero"): the
## glow ribbon at SPEED_TRAIL_PRIORITY in the see-through queue, so they draw before the hero's second pass
## (BillboardSprite.enable_over_trails, at OVER_PRIORITY) and he covers them wherever they cross him. In the oasis, below
## the water's surface, that pass leaves him out (BillboardSprite.set_water), so there a trail crosses him as it crosses
## the water (pass 56).
const SPEED_TRAIL_PRIORITY := -2
static var _speed_ribbon: StandardMaterial3D


static func speed_ribbon_material() -> StandardMaterial3D:
	if _speed_ribbon == null:
		var m := glow_ribbon_material().duplicate() as StandardMaterial3D
		m.render_priority = SPEED_TRAIL_PRIORITY
		_speed_ribbon = m
	return _speed_ribbon


static func glow_ribbon_material() -> StandardMaterial3D:
	if _glow_ribbon == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_glow_ribbon = m
	return _glow_ribbon


## A poison tick: two small green puffs drifting up, so the damage is seen.
func poison(at: Vector3) -> void:
	for k in range(2):
		var p := at + Vector3(randf_range(-0.3, 0.3), 0.1, randf_range(-0.3, 0.3))
		_emit(p, Vector3(0, 2.2, 0), 0.5, 0.22, 0.55, 0.85, 0.0, Color(0.5, 1.0, 0.4))


## A burning creature, every 0.18 s: one flame tongue licking up its body (a gold heart, an orange body, a red rim),
## and now and then an ember flying off the top. `blue` (pass 48: a creature Methanol or Moonshine set burning) blue.
func fire(at: Vector3, size: float = 1.0, blue: bool = false) -> void:
	var p := at + Vector3(randf_range(-0.28, 0.28) * size, randf_range(-0.1, 0.2) * size, randf_range(-0.2, 0.2) * size)
	var h: float = clampf(0.75 + 0.5 * size, 0.8, 2.6) * randf_range(0.85, 1.15)
	_emit_flame(p, Vector3(randf_range(-0.2, 0.2), randf_range(0.8, 1.3), randf_range(-0.2, 0.2)), randf_range(0.45, 0.6), h * 0.5, h, FLAME_ORANGE, false, blue)
	if randf() < 0.3:
		_emit(p + Vector3(0, h * 0.6, 0), Vector3(randf_range(-0.8, 0.8), randf_range(2.0, 3.0), randf_range(-0.8, 0.8)), 0.4, 0.3, 0.12, 1.0, 0.8, SPARK_BLUE if blue else Color(1.0, 0.8, 0.35), 2.0, true)


## Catching fire: three tongues flare up at once, and a ring of sparks; `blue` (pass 48) in the blue palette.
func ignite(at: Vector3, size: float = 1.0, blue: bool = false) -> void:
	for k in range(3):
		var p := at + Vector3(randf_range(-0.3, 0.3) * size, -0.15 * size, randf_range(-0.2, 0.2) * size)
		var h: float = clampf(0.9 + 0.55 * size, 1.0, 3.0)
		_emit_flame(p, Vector3(0, 1.4, 0), 0.5, h * 0.4, h, FLAME_ORANGE, false, blue)
	for k in range(5):
		var a := TAU * k / 5.0 + randf() * 0.5
		_emit(at + Vector3(0, 0.3, 0), Vector3(cos(a) * 2.5, 3.0, sin(a) * 2.5), 0.35, 0.5, 0.05, 1.0, 1.0, SPARK_BLUE if blue else Color(1.0, 0.8, 0.3), 12.0, true)


func hit(at: Vector3, color: Color) -> void:
	if randf() > 0.7:
		return
	# two bright shards flung out of the impact, plus a tiny flash
	var c := color.lightened(0.25)
	for k in range(2):
		_emit(at, Vector3(randf_range(-3.6, 3.6), randf_range(2.0, 6.0), randf_range(-3.6, 3.6)), 0.3, 1.0, 0.05, 1.0, 1.0, c, 0.0, true)
	_emit(at, Vector3.ZERO, 0.12, 0.2, 0.7, 0.8, 0.0, Color(1, 1, 1))


## Momentum (Buck): dust kicked up at the heels while it builds, and past half charge warm streaks trailing behind,
## brighter and longer the closer he is to full. `back` points away from where he is running, `strength` is 0..1.
func trail(at: Vector3, back: Vector3, strength: float) -> void:
	var p := at + Vector3(randf_range(-0.25, 0.25), 0.08, randf_range(-0.25, 0.25))
	_emit(p, back * randf_range(1.0, 2.0) + Vector3(0, 0.9, 0), 0.45, 0.22 + 0.3 * strength, 0.8 + strength, 0.5, 0.0, Color(0.9, 0.78, 0.55))
	if strength > 0.5:
		var c := Color(1.0, 0.72 + 0.25 * strength, 0.3)
		var q := at + Vector3(randf_range(-0.2, 0.2), randf_range(0.3, 1.3), randf_range(-0.2, 0.2))
		_emit(q, back * randf_range(3.0, 5.5), 0.28, 0.5 + 0.5 * strength, 0.05, 0.9, 1.0, c, 0.0, true)
	if strength > 0.95:
		# full charge: a white-hot spark now and then, the sign to keep running
		_emit(at + Vector3(0, 0.9, 0), back * 2.0 + Vector3(0, 1.5, 0), 0.22, 0.35, 0.05, 1.0, 1.0, Color(1, 1, 0.9), 0.0, true)


## A spent casing out of the breech: one brass shard flung up and to `side`, dropping under gravity.
func shell(at: Vector3, side: Vector3) -> void:
	_emit(at, side * randf_range(1.2, 2.2) + Vector3(0, randf_range(2.2, 3.2), 0), 0.5, 0.12, 0.1, 1.0, 0.7, Color(0.95, 0.75, 0.3), 12.0, true)


## Splinters (pass 44, the barrels): `n` tumbling chunks in `col` thrown up and out from `at`, falling under gravity.
func splinters(at: Vector3, col: Color, n: int = 14, size: float = 0.2) -> void:
	for k in n:
		var a := randf() * TAU
		var sp := randf_range(1.8, 5.5)
		var v := Vector3(cos(a) * sp, randf_range(3.0, 6.8), sin(a) * sp)
		_emit(at + Vector3(0, 0.45, 0), v, randf_range(0.7, 1.15), size * randf_range(0.7, 1.3), size * 0.6, 1.0, 0.75, col, 14.0, true, true)


## One source's ribbon (pass 48, TRAILS): its points along his path and their ages, its clock and its mesh.
class SpeedTrail:
	var pts := PackedVector3Array()
	var age := PackedFloat32Array()
	var clock := 0.0
	var mesh: ImmediateMesh
	var col := Color.WHITE
	var hip := 0.85
	var width := 0.3
	var alpha := 0.5
	var seconds := 0.45


## A speed trail (pass 48, TRAILS): `source` "gold", "blue" or "red"; `at` is the hero's feet this frame; `moving` adds to
## the tail (standing, or once the boost is over, it shrinks away over its seconds).
func speed_trail(source: String, at: Vector3, delta: float, moving: bool) -> void:
	if Run.sim_mode:
		return
	var tr := _trail(source)
	if tr == null:
		return
	for k in range(tr.age.size()):
		tr.age[k] += delta
	while not tr.age.is_empty() and tr.age[0] >= tr.seconds:
		tr.age.remove_at(0)
		tr.pts.remove_at(0)
	var hip := at + Vector3(0.0, tr.hip, 0.0)
	if moving:
		tr.clock -= delta
		if tr.clock <= 0.0 or tr.pts.is_empty():
			tr.clock = RUSH_TRAIL_STEP
			tr.pts.append(hip)
			tr.age.append(0.0)
		else:
			# the head keeps to him between the points it leaves behind
			tr.pts[tr.pts.size() - 1] = hip
	_draw_trail(tr)


## Whether a source's ribbon still has a tail to fade out.
func speed_trail_live(source: String) -> bool:
	var tr: SpeedTrail = _trails.get(source)
	return tr != null and not tr.pts.is_empty()


## How many points a source's ribbon has now (tests: the gold one is all there is of Barrel Rush).
func speed_trail_points(source: String) -> int:
	var tr: SpeedTrail = _trails.get(source)
	return tr.pts.size() if tr else 0


## Barrel Rush's ribbon (the gold trail under its pass 47 name).
func rush_trail(at: Vector3, delta: float, moving: bool) -> void:
	speed_trail("gold", at, delta, moving)


func rush_trail_live() -> bool:
	return speed_trail_live("gold")


func _trail(source: String) -> SpeedTrail:
	var tr: SpeedTrail = _trails.get(source)
	if tr:
		return tr
	if not TRAILS.has(source):
		return null
	var cfg: Dictionary = TRAILS[source]
	tr = SpeedTrail.new()
	tr.col = cfg["col"]
	tr.hip = float(cfg["hip"])
	tr.width = float(cfg["width"])
	tr.alpha = float(cfg["alpha"])
	tr.seconds = float(cfg["seconds"])
	tr.mesh = ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.name = "Trail_" + source
	mi.mesh = tr.mesh
	# under the hero, never over him (pass 49)
	mi.material_override = speed_ribbon_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	mi.top_level = true
	add_child(mi)
	_trails[source] = tr
	return tr


func _draw_trail(tr: SpeedTrail) -> void:
	tr.mesh.clear_surfaces()
	var n := tr.pts.size()
	if n < 2:
		return
	var cam := get_viewport().get_camera_3d()
	var to_cam: Vector3 = (cam.global_position - tr.pts[n - 1]).normalized() if cam else Vector3.UP
	tr.mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for k in range(n):
		var p := tr.pts[k]
		var dir := (tr.pts[mini(k + 1, n - 1)] - tr.pts[maxi(k - 1, 0)])
		if dir.length_squared() < 0.000001:
			dir = Vector3.FORWARD
		var side := dir.normalized().cross(to_cam)
		if side.length_squared() < 0.000001:
			side = Vector3.RIGHT
		# 1 at his back, 0 at the tail: wide and bright there, nothing here
		var f := clampf(1.0 - tr.age[k] / tr.seconds, 0.0, 1.0)
		var half := side.normalized() * tr.width * 0.5 * f
		var c := Color(tr.col, tr.alpha * f * f)
		tr.mesh.surface_set_color(c)
		tr.mesh.surface_add_vertex(p - half)
		tr.mesh.surface_set_color(c)
		tr.mesh.surface_add_vertex(p + half)
	tr.mesh.surface_end()


## A Sprint's wind (pass 48): `at` the hero's feet, `forward` where he runs; `on` while the boost lasts (new streaks come
## only then), `moving` while he runs (streaks rush back past him; standing, they rise round him). Old streaks fly on and
## fade after the boost.
func wind(at: Vector3, forward: Vector3, delta: float, on: bool, moving: bool) -> void:
	if Run.sim_mode:
		return
	var k := 0
	while k < _wind_age.size():
		_wind_age[k] += delta
		if _wind_age[k] >= _wind_life[k]:
			var last := _wind_age.size() - 1
			_wind_pos[k] = _wind_pos[last]
			_wind_vel[k] = _wind_vel[last]
			_wind_age[k] = _wind_age[last]
			_wind_life[k] = _wind_life[last]
			_wind_len[k] = _wind_len[last]
			_wind_pos.resize(last)
			_wind_vel.resize(last)
			_wind_age.resize(last)
			_wind_life.resize(last)
			_wind_len.resize(last)
			continue
		_wind_pos[k] += _wind_vel[k] * delta
		k += 1
	if on:
		_wind_clock -= delta
		var f := Vector3(forward.x, 0.0, forward.z)
		var runs: bool = moving and f.length_squared() > 0.01
		while _wind_clock <= 0.0:
			_wind_clock += 0.035 if runs else 0.11
			if _wind_age.size() >= WIND_MAX:
				continue
			if runs:
				var fw := f.normalized()
				var side := Vector3(-fw.z, 0.0, fw.x)
				_wind_pos.append(at + fw * randf_range(0.6, 1.8) + side * randf_range(-1.2, 1.2) + Vector3(0, randf_range(0.25, 2.0), 0))
				_wind_vel.append(-fw * randf_range(9.0, 13.0))
				_wind_life.append(randf_range(0.22, 0.34))
				_wind_len.append(randf_range(1.0, 1.8))
			else:
				var a := randf() * TAU
				var r := randf_range(0.5, 0.95)
				_wind_pos.append(at + Vector3(cos(a) * r, randf_range(0.1, 0.7), sin(a) * r))
				_wind_vel.append(Vector3(0, randf_range(3.0, 4.5), 0))
				_wind_life.append(0.35)
				_wind_len.append(0.7)
			_wind_age.append(0.0)
	_draw_wind()


## Whether any streak of a Sprint's wind is still in the air, and how many.
func wind_live() -> bool:
	return not _wind_age.is_empty()


func wind_count() -> int:
	return _wind_age.size()


func _draw_wind() -> void:
	if _wind_mesh == null:
		if _wind_age.is_empty():
			return
		_wind_mesh = ImmediateMesh.new()
		var mi := MeshInstance3D.new()
		mi.name = "Wind"
		mi.mesh = _wind_mesh
		mi.material_override = speed_ribbon_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
		mi.top_level = true
		add_child(mi)
	_wind_mesh.clear_surfaces()
	if _wind_age.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	_wind_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(_wind_age.size()):
		var head := _wind_pos[k]
		var dir: Vector3 = _wind_vel[k].normalized() if _wind_vel[k].length_squared() > 0.0001 else Vector3.UP
		var tail := head - dir * _wind_len[k]
		var mid := head - dir * _wind_len[k] * 0.4
		var to_cam: Vector3 = (cam.global_position - mid).normalized() if cam else Vector3.UP
		var side := dir.cross(to_cam)
		side = side.normalized() * WIND_WIDTH * 0.5 if side.length_squared() > 0.000001 else Vector3.RIGHT * WIND_WIDTH * 0.5
		var f: float = _wind_age[k] / maxf(_wind_life[k], 0.01)
		# in quickly, out slowly: bright while it passes him
		var a: float = clampf(f * 6.0, 0.0, 1.0) * (1.0 - f * f) * 0.85
		var c0 := Color(WIND_COL, 0.0)
		var c1 := Color(WIND_COL, a)
		# tail to the middle, the middle to the head: see-through at both ends
		_wind_quad(tail, mid, side, c0, c1)
		_wind_quad(mid, head, side, c1, c0)
	_wind_mesh.surface_end()


func _wind_quad(p0: Vector3, p1: Vector3, side: Vector3, c0: Color, c1: Color) -> void:
	_wind_mesh.surface_set_color(c0)
	_wind_mesh.surface_add_vertex(p0 - side)
	_wind_mesh.surface_set_color(c0)
	_wind_mesh.surface_add_vertex(p0 + side)
	_wind_mesh.surface_set_color(c1)
	_wind_mesh.surface_add_vertex(p1 + side)
	_wind_mesh.surface_set_color(c0)
	_wind_mesh.surface_add_vertex(p0 - side)
	_wind_mesh.surface_set_color(c1)
	_wind_mesh.surface_add_vertex(p1 + side)
	_wind_mesh.surface_set_color(c1)
	_wind_mesh.surface_add_vertex(p1 - side)


## A speed boost starting (pass 48: a Sprint's blue, Skedaddle's red): a flash at his middle and a ring of `col` streaks
## flung out low and fast; `small` for a lighter one (Skedaddle starts on every hit).
func speed_burst(at: Vector3, col: Color, small: bool = false) -> void:
	var c := at + Vector3(0, 0.9, 0)
	_emit(c, Vector3.ZERO, 0.3, 0.3, 1.5 if small else 2.6, 0.8, 0.0, col, 0.0, false, true)
	if not small:
		_emit(c, Vector3.ZERO, 0.14, 0.2, 1.3, 1.0, 0.0, Color(1, 1, 1), 0.0, false, true)
	var n := 7 if small else 16
	for k in range(n):
		var a := TAU * float(k) / float(n) + randf() * 0.3
		var v := Vector3(cos(a), 0, sin(a)) * randf_range(5.0, 7.5 if small else 10.0) + Vector3(0, randf_range(0.5, 2.0), 0)
		_emit(at + Vector3(0, 0.5, 0), v, randf_range(0.25, 0.4), 0.42 if small else 0.55, 0.05, 1.0, 1.0, col, 3.0, true, true)


## A jittered bolt through `points` as a camera-facing ribbon: a white-hot core and a wide coloured sheath (a one-pixel
## line was lost on the sand), a flash at every point, gone in a third of a second with a flicker.
## `width` (pass 48): Thor's Wrath's and the Earthshaker's small zaps are thinner bolts with a tighter zigzag (0.5).
func lightning(points: Array, color: Color = Color(0.3, 0.58, 1.0), width: float = 1.0) -> void:
	if Run.sim_mode:
		return
	if points.size() < 2 or _live >= MAX_LIVE:
		return
	# a zigzag between the points: a bolt, not a line (additive washed to white over the sand, so the sheath is a
	# solid saturated blue and only the core is white)
	var jit: Array = []
	for k in range(points.size() - 1):
		var a: Vector3 = points[k]
		var b: Vector3 = points[k + 1]
		var segs := 6
		for s in range(segs + (1 if k == points.size() - 2 else 0)):
			var p := a.lerp(b, float(s) / segs)
			if s > 0 and s < segs:
				var side := (0.55 if s % 2 == 0 else -0.55) * width
				p += Vector3(randf_range(-0.2, 0.2) * width + side * randf_range(0.5, 1.0), randf_range(-0.2, 0.2) * width, randf_range(-0.2, 0.2) * width + side * randf_range(0.5, 1.0))
			jit.append(p)
	var cam := get_viewport().get_camera_3d()
	var to_cam: Vector3 = (cam.global_position - jit[0]).normalized() if cam else Vector3.UP
	# the sheath fades from 0.85 and the core from 1.0, each on a quadratic ease-in, as their tweens did
	_bolts.append({"sheath": _ribbon_tris(jit, 0.36 * width, to_cam), "core": _ribbon_tris(jit, 0.12 * width, to_cam), "color": color, "t": 0.0})
	_live += 1
	# into the meshes now, so the strike shows this frame (a node added mid-frame did)
	_draw_bolts(0.0)
	if want_lights():
		var glow := OmniLight3D.new()
		glow.light_color = color
		glow.omni_range = 6.0
		glow.light_energy = 3.0
		glow.position = points[1]
		add_child(glow)
		var tw := create_tween()
		tw.tween_interval(0.32)
		tw.tween_property(glow, "light_energy", 0.0, 0.18)
		tw.tween_callback(func(): glow.queue_free())
	# a flash and sparks where it lands, a spark at the source
	_emit(points[0], Vector3.ZERO, 0.14, 0.25, 0.5, 1.0, 0.0, Color(1.0, 1.0, 1.0))
	for k in range(1, points.size()):
		_emit(points[k], Vector3.ZERO, 0.2, 0.35, 0.9, 1.0, 0.0, Color(1.0, 1.0, 1.0))
		_emit(points[k], Vector3.ZERO, 0.28, 0.6, 1.4, 0.6, 0.0, color)
		for s in range(4):
			_emit(points[k], Vector3(randf_range(-3, 3), randf_range(1.5, 4.5), randf_range(-3, 3)), 0.4, 0.16, 0.05, 1.0, 0.0, Color(0.75, 0.88, 1.0), 9.0)


## The same ribbon as triangles (two per step), so many bolts can share one mesh: the strip's own triangles, in order.
func _ribbon_tris(pts: Array, width: float, to_cam: Vector3) -> PackedVector3Array:
	var edge := PackedVector3Array()
	for k in range(pts.size()):
		var p: Vector3 = pts[k]
		var dir: Vector3 = (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
		var side := dir.cross(to_cam).normalized() * width * 0.5
		var taper := 1.0 if (k > 0 and k < pts.size() - 1) else 0.35
		edge.append(p - side * taper)
		edge.append(p + side * taper)
	var tris := PackedVector3Array()
	for k in range(edge.size() - 2):
		tris.append(edge[k])
		tris.append(edge[k + 1])
		tris.append(edge[k + 2])
	return tris


## Every live bolt into the two meshes, at this moment's alpha; the finished ones go.
func _draw_bolts(delta: float) -> void:
	if _bolts.is_empty():
		if _bolts_drawn:
			_sheath_mesh.clear_surfaces()
			_core_mesh.clear_surfaces()
			_bolts_drawn = false
		return
	_sheath_mesh.clear_surfaces()
	_core_mesh.clear_surfaces()
	var keep: Array = []
	for b in _bolts:
		b["t"] = float(b["t"]) + delta
		if float(b["t"]) >= SHEATH_LIFE:
			_live -= 1
			continue
		keep.append(b)
	_bolts = keep
	if _bolts.is_empty():
		_bolts_drawn = false
		return
	_sheath_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in _bolts:
		var f: float = float(b["t"]) / SHEATH_LIFE
		var c: Color = b["color"]
		_sheath_mesh.surface_set_color(Color(c.r, c.g, c.b, 0.85 * (1.0 - f * f)))
		for v in (b["sheath"] as PackedVector3Array):
			_sheath_mesh.surface_add_vertex(v)
	_sheath_mesh.surface_end()
	var any_core := false
	for b in _bolts:
		if float(b["t"]) < CORE_LIFE:
			if not any_core:
				_core_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
				any_core = true
			var g: float = float(b["t"]) / CORE_LIFE
			_core_mesh.surface_set_color(Color(1.0, 1.0, 1.0, 1.0 - g * g))
			for v in (b["core"] as PackedVector3Array):
				_core_mesh.surface_add_vertex(v)
	if any_core:
		_core_mesh.surface_end()
	_bolts_drawn = true


## A camera-facing ribbon along `pts`, `width` metres wide.
func _ribbon(pts: Array, width: float, to_cam: Vector3) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for k in range(pts.size()):
		var p: Vector3 = pts[k]
		var dir: Vector3 = (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
		var side := dir.cross(to_cam).normalized() * width * 0.5
		# thinner towards the ends
		var taper := 1.0 if (k > 0 and k < pts.size() - 1) else 0.35
		st.add_vertex(p - side * taper)
		st.add_vertex(p + side * taper)
	return st.commit()


func _process(delta: float) -> void:
	# pass 77 (lane SIMRUN): the run sim's fast mode has no effects at all (nothing here moves a number): no particle,
	# note, blood, bolt, trail or wind is made (the guards at the top of _emit, _emit_flame, _emit_dust, note, blood,
	# lightning, speed_trail and wind) and none is aged or drawn
	if Run.sim_mode:
		return
	var t0 := Time.get_ticks_usec()
	_tick_blood(delta)
	_tick_blasts()
	_draw_bolts(delta)
	var i := 0
	var ns := 0
	var nb := 0
	var nf := 0
	var nn := 0
	var nd := 0
	while i < _n:
		_age[i] += delta
		if _age[i] >= _life[i]:
			# swap-remove
			_n -= 1
			if i != _n:
				_pos[i] = _pos[_n]; _vel[i] = _vel[_n]; _age[i] = _age[_n]; _life[i] = _life[_n]
				_s0[i] = _s0[_n]; _s1[i] = _s1[_n]; _a0[i] = _a0[_n]; _a1[i] = _a1[_n]; _grav[i] = _grav[_n]
				_col[i] = _col[_n]; _shard[i] = _shard[_n]; _seed[i] = _seed[_n]; _blue[i] = _blue[_n]
			continue
		_vel[i].y -= _grav[i] * delta
		_pos[i] += _vel[i] * delta
		var f: float = _age[i] / _life[i]
		# ease-out on growth so bursts snap open, linear fade
		var e: float = 1.0 - (1.0 - f) * (1.0 - f)
		var s: float = lerpf(_s0[i], _s1[i], e)
		var c := _col[i]
		c.a = lerpf(_a0[i], _a1[i], f)
		var xf := Transform3D(Basis().scaled(Vector3(s, s, s)), _pos[i])
		if _shard[i] == 1:
			xf.basis = xf.basis.rotated(Vector3(0.3, 1, 0.2).normalized(), _age[i] * 9.0)
			_box_mm.set_instance_transform(nb, xf)
			_box_mm.set_instance_color(nb, c)
			nb += 1
		elif _shard[i] == 2:
			# a flame is taller than it is wide; the shader faces it to the camera and eats it away by its age
			_flame_mm.set_instance_transform(nf, Transform3D(Basis().scaled(Vector3(s * 0.75, s, s)), _pos[i]))
			_flame_mm.set_instance_color(nf, c)
			_flame_mm.set_instance_custom_data(nf, Color(f, _seed[i], float(_blue[i]), 0.0))
			nf += 1
		elif _shard[i] == 3:
			# a note: full size in the first third, slowing as it flies, a wobble, held bright and then faded
			_vel[i] *= maxf(1.0 - NOTE_DRAG * delta, 0.0)
			var pop: float = 1.0 - pow(1.0 - minf(f * 3.0, 1.0), 2.0)
			var ns2: float = lerpf(_s0[i], _s1[i], pop)
			c.a = _a0[i] * clampf((1.0 - f) * 2.2, 0.0, 1.0)
			var g := floorf(_seed[i])
			var tilt: float = 0.35 * sin(_age[i] * 8.0 + (_seed[i] - g) * TAU)
			_note_mm.set_instance_transform(nn, Transform3D(Basis().scaled(Vector3(ns2, ns2, ns2)), _pos[i]))
			_note_mm.set_instance_color(nn, c)
			_note_mm.set_instance_custom_data(nn, Color(g, tilt, 0.0, 0.0))
			nn += 1
		elif _shard[i] == 4:
			# a dust puff (pass 50): it slows as it drifts, swells, holds its body and then thins out, fraying (the shader)
			_vel[i] *= maxf(1.0 - DUST_DRAG * delta, 0.0)
			c.a = _a0[i] * (1.0 - f * f)
			_dust_mm.set_instance_transform(nd, xf)
			_dust_mm.set_instance_color(nd, c)
			_dust_mm.set_instance_custom_data(nd, Color(f, _seed[i], 0.0, 0.0))
			nd += 1
		else:
			_sph_mm.set_instance_transform(ns, xf)
			_sph_mm.set_instance_color(ns, c)
			ns += 1
		i += 1
	_sph_mm.visible_instance_count = ns
	_box_mm.visible_instance_count = nb
	_flame_mm.visible_instance_count = nf
	_note_mm.visible_instance_count = nn
	_dust_mm.visible_instance_count = nd
	Perf.add("fx", t0)


# ---- pass 61: projectile mutation looks (WP1): new functions below this line ----


## A tongue of flame licking out of a muzzle (pass 61, Dragon's Breath's look): flames in a row from `at` along `dir`
## over `length` metres, the first `size` metres tall and each further one smaller, thrown forward and gone in about a
## fifth of a second; `blue` (Methanol's palette) burns it blue. The first flame is never thinned by the effect budget.
func flame_tongue(at: Vector3, dir: Vector3, length: float = 1.0, size: float = 0.5, blue: bool = false) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 0.0001:
		return
	d = d.normalized()
	var n := 5
	for k in range(n):
		var f := float(k) / float(n - 1)
		var p := at + d * (length * 0.6 * f) + Vector3(0, -0.1, 0)
		var h: float = size * lerpf(1.0, 0.45, f)
		var v := d * lerpf(4.5, 8.0, f) + Vector3(randf_range(-0.3, 0.3), 0.6, randf_range(-0.3, 0.3))
		_emit_flame(p, v, lerpf(0.24, 0.15, f), h * 0.7, h, FLAME_ORANGE, k < 2, blue)


# ---- pass 61: melee, beam and sceptre looks (WP2): new functions below this line ----

## Rust's colours (pass 61, the Orbit Saws' Rust): a flake is one of these, darker and brighter oxide.
const RUST_FLAKES := [Color(0.62, 0.27, 0.09), Color(0.78, 0.38, 0.12), Color(0.45, 0.2, 0.08), Color(0.9, 0.52, 0.2)]


## One rust flake shed by a spinning saw (pass 61, Rust): a small spinning chip of oxide flung along `vel`, falling under
## gravity; `col` (alpha 0 = one of RUST_FLAKES) its colour; `dust` adds a faint puff of orange oxide where it leaves.
## Thinned by the budget like a hit's shards: it is decoration.
func rust_flake(at: Vector3, vel: Vector3, col: Color = Color(0, 0, 0, 0), size: float = 1.0, dust := false) -> void:
	var c: Color = col if col.a > 0.0 else RUST_FLAKES[randi() % RUST_FLAKES.size()]
	_emit(at, vel, randf_range(0.5, 0.8), 0.5 * size, 0.3 * size, 1.0, 1.0, Color(c.r, c.g, c.b), 9.0, true)
	if dust:
		_emit_dust(at, vel * 0.25 + Vector3(0, 0.3, 0), randf_range(0.45, 0.6), 0.15 * size, 0.55 * size, 0.45, Color(0.78, 0.42, 0.18))


## A gust of Bad Breath where its beam hits (pass 61): soft puffs of `col` thrown along `dir` (the beam's way) and up;
## `big` (the first touch, the knock) throws three wider puffs and a few streaks of wind ahead of them, else one small
## puff. The big gust is never thinned: it is the hit.
func breath_gust(at: Vector3, dir: Vector3, col: Color, big := false) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	d = d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD
	var side := Vector3(-d.z, 0.0, d.x)
	var n := 3 if big else 1
	var k_big := 1.4 if big else 1.0
	for k in range(n):
		var o := at + side * randf_range(-0.35, 0.35) + Vector3(0, randf_range(-0.1, 0.3), 0)
		var v := d * randf_range(2.0, 3.6) * k_big + side * randf_range(-0.8, 0.8) + Vector3(0, randf_range(0.3, 0.9), 0)
		_emit_dust(o, v, randf_range(0.45, 0.65), 0.3, randf_range(0.95, 1.3) * k_big, 0.8 if big else 0.65, col, big)
	if big:
		var pale := col.lerp(Color(1, 1, 1), 0.45)
		for k in range(4):
			var o2 := at + side * randf_range(-0.5, 0.5) + Vector3(0, randf_range(0.0, 0.5), 0)
			_emit(o2, d * randf_range(7.0, 10.0) + side * randf_range(-1.0, 1.0), 0.22, 0.14, 0.05, 0.9, 0.0, pale, 0.0, false, true)


## The clang of Riposte's flick (pass 61): a white pop and a brass glow at `at`, and bright sparks flung out and up, the
## way the blade snapped back (`dir`) a little; never thinned, one a stroke.
func clang_spark(at: Vector3, dir: Vector3 = Vector3.ZERO) -> void:
	_emit(at, Vector3.ZERO, 0.12, 0.2, 1.25, 1.0, 0.0, Color(1.0, 1.0, 0.94), 0.0, false, true)
	_emit(at, Vector3.ZERO, 0.24, 0.25, 0.95, 0.95, 0.0, Color(1.0, 0.8, 0.3), 0.0, false, true)
	var d := Vector3(dir.x, 0.0, dir.z)
	d = d.normalized() if d.length_squared() > 0.0001 else Vector3.ZERO
	for k in range(14):
		var a := randf() * TAU
		var v := Vector3(cos(a), 0.0, sin(a)) * randf_range(3.5, 7.5) + d * 2.5 + Vector3(0, randf_range(2.0, 5.0), 0)
		var c := Color(1.0, 1.0, 0.9) if k % 3 == 0 else Color(1.0, 0.86, 0.42)
		_emit(at, v, randf_range(0.25, 0.45), 0.55, 0.1, 1.0, 1.0, c, 14.0, true, true)


## Sparks thrown off the Sun Scepter's sun as it calls a strike (pass 61): a small white pop on the disc and `n` hot
## sparks flung out and up in its colour.
func sun_sparks(at: Vector3, tint: Color, n: int = 5) -> void:
	_emit(at, Vector3.ZERO, 0.12, 0.1, 0.6, 1.0, 0.0, Color(1.0, 0.98, 0.86), 0.0, false, true)
	var hot := tint.lerp(Color(1.0, 0.97, 0.8), 0.5)
	for k in range(n):
		var a := randf() * TAU
		var v := Vector3(cos(a), 0.0, sin(a)) * randf_range(1.5, 3.2) + Vector3(0, randf_range(1.2, 3.0), 0)
		_emit(at, v, randf_range(0.3, 0.45), 0.36, 0.06, 1.0, 0.9, hot, 7.0, true, true)


## A pillar of sunlight landing (pass 61, the Sun Scepter): a white-hot pop at its foot `r` metres across, `motes`
## pale-gold motes rising off the spot and a few sparks skittering out low; `must` keeps the pop from the budget's
## thinning (a single strike's; a Zenith sweep's forty landings may thin), `pop` scales it.
func sun_impact(at: Vector3, r: float, tint: Color, motes: int = 6, must := true, pop: float = 1.0) -> void:
	var c := at + Vector3(0, 0.25, 0)
	_emit(c, Vector3(0, 0.6, 0), 0.13, 0.3 * r * pop, 1.05 * r * pop, 1.0, 0.0, Color(1.0, 0.98, 0.88), 0.0, false, must)
	var hot := tint.lerp(Color(1.0, 0.96, 0.75), 0.55)
	for k in range(motes):
		var a := randf() * TAU
		var o := Vector3(cos(a), 0.0, sin(a)) * randf_range(0.2, 0.8) * r
		_emit(at + o + Vector3(0, 0.2, 0), Vector3(o.x * 0.6, randf_range(2.2, 4.2), o.z * 0.6), randf_range(0.55, 0.85), randf_range(0.18, 0.26), 0.05, 1.0, 0.0, hot, -1.5)
	for k in range(mini(motes, 4)):
		var a2 := randf() * TAU
		_emit(c, Vector3(cos(a2), 0.0, sin(a2)) * randf_range(3.0, 5.0) + Vector3(0, randf_range(1.5, 3.0), 0), randf_range(0.3, 0.45), 0.4, 0.08, 1.0, 0.8, Color(1.0, 0.9, 0.5), 10.0, true)


# ---- pass 62: hero mutation looks (HM): new functions below this line ----

## Heartseeker's crit thrusts and Sun Cocktail's sun puffs made (tests).
var crit_thrusts := 0
var sun_puffs := 0
## A sun puff's sunburst: SUN_PUFF_SIZE x its radius across, swelling from SUN_PUFF_FROM to full over SUN_PUFF_GROW
## seconds while its strength falls from SUN_PUFF_STRENGTH to nothing over SUN_PUFF_LIFE; SUN_PUFF_UP over the sand.
const SUN_PUFF_SIZE := 2.4
const SUN_PUFF_FROM := 0.35
const SUN_PUFF_GROW := 0.3
const SUN_PUFF_LIFE := 0.42
const SUN_PUFF_STRENGTH := 1.8
const SUN_PUFF_UP := 0.6
const SUN_PUFF_RAYS := 8
const SUN_WHITE := Color(1.0, 0.95, 0.72)
const SUN_GOLD_DEEP := Color(1.0, 0.74, 0.12)


## Heartseeker's crit thrust (pass 62) at the spear's point `at`, the thrust going `dir`: a white-hot pop inside a red
## flash thrown on a little, a fan of red-hot sparks flung on along the thrust, and red embers rising. Never thinned for
## the budget: it is the stroke that must read.
func crit_thrust(at: Vector3, dir: Vector3, col: Color = Color(1.0, 0.16, 0.08)) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	d = d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD
	_emit(at, d * 2.5, 0.22, 0.3, 1.5, 0.85, 0.0, col, 0.0, false, true)
	_emit(at, d * 1.0, 0.12, 0.15, 0.8, 1.0, 0.0, Color(1.0, 0.95, 0.85), 0.0, false, true)
	for k in range(12):
		var v := d.rotated(Vector3.UP, randf_range(-0.6, 0.6)) * randf_range(5.0, 10.0) + Vector3(0, randf_range(1.0, 3.5), 0)
		_emit(at, v, randf_range(0.25, 0.45), 0.42, 0.08, 1.0, 0.8, col.lerp(Color(1.0, 0.75, 0.4), randf() * 0.5), 10.0, true, true)
	for k in range(4):
		var o := Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
		_emit(at + o, Vector3(o.x, randf_range(1.5, 2.6), o.z), randf_range(0.4, 0.6), 0.2, 0.05, 1.0, 0.0, col, -1.0, false, true)
	crit_thrusts += 1


## Sun Cocktail's landing (pass 62, Garry: "the little sun puff should accompany the Molotov's when they 'explode'"): a
## little sun bursts where the bottle broke, `r` metres: the Sun Scepter's white pop and rising motes (sun_impact), a
## see-through gold ball with a white-hot heart and SUN_PUFF_RAYS gold rays flung out flat (added light alone read pale
## on the bright sand), and a sunburst (the chest's shine, mode 0) that blooms and is gone in SUN_PUFF_LIFE. The caller
## lays the gold ring and the hot glow on the sand (Telegraphs).
func sun_puff(at: Vector3, r: float, tint: Color = Color(1.0, 0.82, 0.3)) -> void:
	sun_impact(at, r, tint, 6, true, 1.0)
	var c := at + Vector3(0, SUN_PUFF_UP, 0)
	# the little sun itself, see-through gold (added light alone reads pale on the bright sand): a gold ball swelling
	# and gone, a white-hot heart inside it, and SUN_PUFF_RAYS short gold rays flung out flat all round
	_emit(c, Vector3(0, 0.8, 0), 0.34, 0.35 * r, 1.15 * r, 0.95, 0.0, SUN_GOLD_DEEP, 0.0, false, true)
	_emit(c, Vector3(0, 0.6, 0), 0.2, 0.2 * r, 0.6 * r, 1.0, 0.0, SUN_WHITE, 0.0, false, true)
	for k in range(SUN_PUFF_RAYS):
		var a := TAU * float(k) / float(SUN_PUFF_RAYS) + randf() * 0.2
		var d := Vector3(cos(a), 0.0, sin(a))
		_emit(c + d * 0.3 * r, d * randf_range(7.0, 9.5) * maxf(r, 0.6) * 0.6 + Vector3(0, 0.6, 0), 0.24, 0.55, 0.12, 1.0, 0.7, SUN_GOLD_DEEP.lerp(SUN_WHITE, 0.3), 0.0, true, true)
	var q := Chest.shine_quad(0, Vector2.ONE * r * SUN_PUFF_SIZE, SUN_WHITE, SUN_PUFF_STRENGTH)
	add_child(q)
	q.global_position = at + Vector3(0, SUN_PUFF_UP, 0)
	q.scale = Vector3.ONE * SUN_PUFF_FROM
	var m := q.material_override as ShaderMaterial
	var tw := q.create_tween()
	tw.set_parallel(true)
	tw.tween_property(q, "scale", Vector3.ONE, SUN_PUFF_GROW).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void: m.set_shader_parameter("strength", v), SUN_PUFF_STRENGTH, 0.0, SUN_PUFF_LIFE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(q.queue_free)
	sun_puffs += 1


# ---- pass 62: items and the spit cactus (IT): new functions below this line ----


# ---- pass 69, lane SALT: the Salt's pour ----

## Where a salt patch lands (pass 69, SaltShaker): a low puff of the salt's colour spread over the patch and a few grains
## that bounce up and fall back. `r` is the patch's radius.
func salt_land(at: Vector3, col: Color, r: float = 1.4) -> void:
	var w := clampf(r / 1.4, 0.5, 2.5)
	var c := Color(col.r, col.g, col.b)
	_emit(at + Vector3(0, 0.08, 0), Vector3(0, 0.25, 0), 0.32, 0.25 * w, 0.8 * w, 0.28, 0.0, c)
	for k in range(6):
		var a := randf() * TAU
		var v := Vector3(cos(a) * randf_range(0.6, 1.6), randf_range(1.6, 3.0), sin(a) * randf_range(0.6, 1.6)) * w
		_emit(at + Vector3(0, 0.08, 0), v, randf_range(0.3, 0.45), 0.07, 0.04, 1.0, 0.7, c, 12.0, true)


## A few grains of salt falling from the shaker's cap while it shakes (pass 69): small shards dropping under gravity.
func salt_grains(from: Vector3, col: Color) -> void:
	var c := Color(col.r, col.g, col.b)
	for k in range(2):
		var v := Vector3(randf_range(-0.35, 0.35), randf_range(-0.6, 0.1), randf_range(-0.35, 0.35))
		_emit(from + Vector3(randf_range(-0.03, 0.03), 0.0, randf_range(-0.03, 0.03)), v, randf_range(0.45, 0.65), 0.06, 0.035, 1.0, 0.85, c, 9.0, true)


# ---- pass 73, lane GROUND: the ground ----

## A creature growing out of the ground (pass 73, EnemyManager._emerge_start; Garry: "currently the enemies just kind of
## appear. Let's make it so that they grow out of the ground"): a small low puff all round its feet that spreads as the
## figure pushes up, and a few grains thrown up. `size` is the creature's size (m) times the map's dust factor. Thinned
## with the rest when the screen is busy (a crowd arrives in bursts), unless `big` (an Elite's or a boss's).
func emerge_dust(at: Vector3, size: float = 1.0, big: bool = false) -> void:
	var w := clampf(size * 0.55, 0.35, 3.5)
	var n := 4 if w < 1.0 else 7
	var phase := randf() * TAU
	for k in range(n):
		var ang := phase + TAU * float(k) / float(n)
		var out := Vector3(cos(ang), 0.0, sin(ang))
		_emit_dust(at + out * 0.25 * w + Vector3(0, 0.12, 0), out * randf_range(0.6, 1.1) * w + Vector3(0, randf_range(0.25, 0.5), 0),
			randf_range(0.5, 0.7), 0.3 * w, randf_range(0.9, 1.2) * w, 0.6, DUST_PALE if k % 2 == 0 else DUST_TAN, big)
	for k in range(3 if w < 1.0 else 6):
		var ga := randf() * TAU
		var gv := Vector3(cos(ga), 0.0, sin(ga)) * randf_range(0.6, 1.6) * w + Vector3(0, randf_range(1.6, 3.0), 0)
		_emit(at + Vector3(0, 0.08, 0), gv, randf_range(0.3, 0.45), 0.08 * maxf(w, 0.6), 0.04, 1.0, 0.6, DUST_GRAIN, 12.0, true, big)


## A creature digging itself into the sand (pass 73, the visible burrow; Garry: "It would be nice if I can actually see
## him burrowing into the ground"): a ring of dust thrown out low all round it as it starts to sink, and clods kicked up.
## Never thinned: the dig is the attack's tell.
func dig_ring(at: Vector3, size: float = 1.0) -> void:
	var w := maxf(size * 0.6, 0.6)
	var n := 10 + mini(int(size), 6)
	var phase := randf() * TAU
	for k in range(n):
		var ang := phase + TAU * float(k) / float(n)
		var out := Vector3(cos(ang), 0.0, sin(ang))
		_emit_dust(at + out * randf_range(0.35, 0.5) * w + Vector3(0, 0.15, 0), out * randf_range(1.2, 2.0) * w * 0.6 + Vector3(0, randf_range(0.2, 0.5), 0),
			randf_range(0.7, 1.0), 0.35 * w, randf_range(1.0, 1.35) * w, 0.66, DUST_PALE if k % 3 == 1 else DUST_TAN, true)
	for k in range(6):
		var ca := phase + TAU * (float(k) + 0.5) / 6.0
		var cv := Vector3(cos(ca), 0.0, sin(ca)) * randf_range(1.0, 2.0) * w * 0.5 + Vector3(0, randf_range(2.5, 4.0), 0)
		_emit(at + Vector3(cos(ca) * 0.3 * w, 0.2, sin(ca) * 0.3 * w), cv, randf_range(0.45, 0.65), 0.09 * w, 0.06 * w, 1.0, 0.9, CLOD, 12.0, true, true)


## Sand spraying off a creature as it sinks (pass 73; EnemyManager._tick_burrows, about ten a second while it goes down):
## grains flung up and out round it and a low puff drifting out; `k` (0..1) how far down it is, the spray dying away as
## the sand closes over it. Never thinned.
func dig_spray(at: Vector3, size: float = 1.0, k: float = 0.0) -> void:
	var w := maxf(size * 0.5, 0.5)
	var strength := clampf(1.0 - k * 0.6, 0.3, 1.0)
	for n in range(3):
		var ga := randf() * TAU
		var o := Vector3(cos(ga), 0.0, sin(ga))
		var gv := o * randf_range(1.0, 2.6) * w * 0.6 + Vector3(0, randf_range(2.2, 4.2) * strength, 0)
		_emit(at + o * 0.35 * w + Vector3(0, 0.12, 0), gv, randf_range(0.35, 0.55), 0.1 * maxf(w, 0.8), 0.05, 1.0, 0.6, DUST_GRAIN, 12.0, true, true)
	var pa := randf() * TAU
	var po := Vector3(cos(pa), 0.0, sin(pa))
	_emit_dust(at + po * 0.4 * w + Vector3(0, 0.12, 0), po * 0.8 * w + Vector3(0, 0.35, 0), randf_range(0.55, 0.75), 0.3 * w, 0.9 * w * strength, 0.55, DUST_TAN, true)


# ---- pass 95 (lane BREATH): the Dragon's Breath's jet of fire: new functions below this line ----

## A jet of fire breathed from `at` (the hero's face) along `dir` (pass 95, FireBreath._show, every FireBreath.FX_EVERY):
## `n` flame tongues thrown down the cone (`reach` m long, `deg` wide; `ring` = all round), each from a little in front of
## the face, fast enough to reach the end within its life, sinking from face height towards the bodies in the fire as it
## goes, `size` metres tall at its fullest (the fire shader eats it away with age); now and then an ember flung ahead
## of it. `blue` burns the blue palette (Blue Flame). The first tongue of a go is never thinned by the budget, the rest
## are, so a crowded screen keeps a breath that reads and loses only its fullness.
func breath_jet(at: Vector3, dir: Vector3, reach: float, deg: float, n: int, size: float = 0.55, blue: bool = false, ring: bool = false) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 0.0001 or n <= 0:
		return
	d = d.normalized()
	var half := deg_to_rad(clampf(deg, 1.0, 360.0)) * 0.5
	var life_mid := 0.36
	for k in range(n):
		var a: float = randf() * TAU if ring else randf_range(-half, half) * 0.88
		var dk := d.rotated(Vector3.UP, a)
		var life := randf_range(0.3, 0.42)
		# the flame covers the reach in about life_mid seconds, the odd one a little short or long
		var spd: float = reach / life_mid * randf_range(0.78, 1.04)
		var p := at + dk * randf_range(0.2, 0.55) + Vector3(randf_range(-0.08, 0.08), randf_range(-0.12, 0.08), randf_range(-0.08, 0.08))
		var v := dk * spd + Vector3(randf_range(-0.3, 0.3), randf_range(-2.4, -0.4), randf_range(-0.3, 0.3))
		var h: float = size * randf_range(0.8, 1.25)
		_emit_flame(p, v, life, h * 0.55, h * 1.15, Color(FLAME_ORANGE.r, FLAME_ORANGE.g, FLAME_ORANGE.b, 0.95), k == 0, blue)
	# an ember now and then, flung ahead and falling
	if randf() < 0.35:
		var ea: float = randf() * TAU if ring else randf_range(-half, half)
		var ed := d.rotated(Vector3.UP, ea)
		var ec := SPARK_BLUE if blue else Color(1.0, 0.82, 0.35)
		_emit(at + ed * 0.4, ed * randf_range(5.0, 9.0) + Vector3(0, randf_range(0.5, 2.0), 0), randf_range(0.35, 0.55), 0.12, 0.04, 1.0, 0.8, ec, 9.0, true)


## Pass 95 (lane BOSS): the dust a rolling tumbleweed kicks up (ProjectileManager._tumble_trail_tick, every `puffs`
## seconds): one soft tan puff at its foot drifting `back` (the way it came) and up, growing as it fades; thinned on a busy
## screen like every dust. `size` scales it.
func roll_dust(at: Vector3, back: Vector3, size: float = 1.0) -> void:
	if _busy_skip():
		return
	var w := maxf(size, 0.4)
	var o := at + Vector3(randf_range(-0.15, 0.15), 0.05, randf_range(-0.15, 0.15)) * w
	var v := back * randf_range(0.6, 1.2) * w + Vector3(randf_range(-0.2, 0.2), randf_range(0.5, 0.9), randf_range(-0.2, 0.2)) * w
	_emit_dust(o, v, randf_range(0.5, 0.75), 0.35 * w, randf_range(0.9, 1.3) * w, 0.62, DUST_TAN if randf() < 0.7 else DUST_PALE)


## Pass 111 (lane ENEMY): a puff of smoke off a fuse (the Spit Cactus's bomb in flight, ProjectileManager._bomb_trail_tick):
## a soft puff of `col` growing from `s0` to `s1` metres as it drifts along `vel` and fades over `life` seconds; thinned on a
## busy screen like every dust.
func smoke_puff(at: Vector3, vel: Vector3, life: float, s0: float, s1: float, col: Color) -> void:
	_emit_dust(at, vel, life, s0, s1, col.a, Color(col.r, col.g, col.b))


## Pass 95 (lane BOSS): the King's stomp landing (Game.stomp_wave): a ring of dust thrown out low all round the spot,
## racing out towards the stomp's `r` (the puffs cover about 0.6 r before they fade), a column up the middle, clods and
## grains flung up and out. Never thinned: the stomp is the attack's tell. `size` is the stomper's size in metres.
func stomp_dust(at: Vector3, r: float, size: float = 1.0) -> void:
	var w := clampf(size * 0.5, 0.8, 3.0)
	var n := 14 + mini(int(r), 10)
	var phase := randf() * TAU
	var reach := maxf(r, 2.0)
	for k in range(n):
		var ang := phase + TAU * float(k) / float(n)
		var out := Vector3(cos(ang), 0.0, sin(ang))
		var life := randf_range(0.6, 0.8)
		var o := at + out * randf_range(0.5, 0.9) * w + Vector3(0, 0.15, 0)
		var v := out * (reach * randf_range(0.5, 0.7) / life) + Vector3(0, randf_range(0.3, 0.7), 0)
		_emit_dust(o, v, life, 0.4 * w, randf_range(1.2, 1.6) * w, 0.72, DUST_PALE if k % 3 == 1 else DUST_TAN, true)
	for k in range(3):
		var vy := 2.4 - 0.4 * float(k)
		_emit_dust(at + Vector3(randf_range(-0.15, 0.15) * w, 0.25 + 0.35 * float(k), randf_range(-0.15, 0.15) * w), Vector3(0, vy, 0),
			randf_range(0.7, 0.9), 0.35 * w, randf_range(0.9, 1.2) * w, 0.7, DUST_TAN if k != 1 else DUST_PALE, true)
	for k in range(12):
		var ga := randf() * TAU
		var gv := Vector3(cos(ga), 0.0, sin(ga)) * randf_range(2.0, 5.0) * w * 0.5 + Vector3(0, randf_range(2.5, 5.0), 0)
		_emit(at + Vector3(0, 0.1, 0), gv, randf_range(0.35, 0.6), 0.12, 0.05, 1.0, 0.6, DUST_GRAIN, 12.0, true, true)
	for k in range(8):
		var ca := phase + TAU * (float(k) + 0.5) / 8.0
		var cv := Vector3(cos(ca), 0.0, sin(ca)) * randf_range(1.5, 3.0) * w * 0.5 + Vector3(0, randf_range(3.0, 5.0), 0)
		_emit(at + Vector3(cos(ca) * 0.3 * w, 0.25, sin(ca) * 0.3 * w), cv, randf_range(0.5, 0.75), 0.1 * w, 0.07 * w, 1.0, 0.9, CLOD, 12.0, true, true)


# ---- pass 110 (lane VFX): the hero's explosions: new functions below this line ----

## Garry: "Explosions - at some point became quite invisible. And I mean for all the explosive weapons. Can you make them
## better?" Every blast of the hero's weapons was Fx.burst: a see-through pale-orange ball that fades in a third of a
## second. Two things hid it. Pass 61 made the sand paler (its painting's mean from 203,162,102 to 215,189,146): the
## ball is drawn almost in the sand's own colour, and only the thin ring showed. And the ball came out of the shared pool
## without `must`: past a third full the budget dropped a third of them, past three quarters two thirds, and at the cap
## (a late-game crowd holds it at 394 of 400) all of them.
## Now a blast is drawn by a pool of its own (the death splash's recipe: a ring of BLAST_MAX quads animated entirely by
## core/shaders/blast_fx.gdshader from what was written once, so it costs nothing a frame and nothing can crowd it out),
## in the fire's cel look with a dark rim, so it reads on the pale sand and under the stage filters (it is see-through,
## drawn after the filter's quads, so never darkened): a white-hot flash, a lumpy fireball (a hot heart that shrinks,
## the colour cooling to embers and smoke, a dark rim, breaking up as it burns out) a little wider than the blast's
## radius, dark smoke rising out of it, sparks and clods flung out; and on the ground (weapon_blast) a shock ring racing
## out to the real radius, a scorch that lingers, and a short kick of the camera only for a big one.
## 768 pieces: a full blast writes about 35 and a cheap one 6, so the ring holds every piece of a missile swarm's second
## (BLAST_BUSY full blasts every BLAST_BUSY_SECONDS) without cutting a smoke puff short.
const BLAST_MAX := 768
## Drawn over the death splashes (BLOOD_PRIORITY 1): a blast that kills a pack stays the thing that reads.
const BLAST_PRIORITY := 2
## Styles: a weapon tagged `explosive` blasts in full; a lobbed flask or skull without the tag (the Molotov, Skull Rain)
## only splashes (a smaller flash and ball, two puffs, a few sparks; no clods, scorch or kick).
const BLAST_FULL := 0
const BLAST_SPLASH := 1
## What blast() did: nothing (the run sim), merged into a blast that had just gone off beside it, cheap, full.
const BLAST_NONE := 0
const BLAST_MERGED := 1
const BLAST_CHEAP := 2
const BLAST_DONE := 3
## Colours: the plain blast, a fire weapon's (Incendiary, Thermobaric, Napalm), poison's, blue fire's (Methanol, Blue
## Flame); a weapon names its own in `params.blast_fx.color` (the Golden Pineapple's gold).
const BLAST_ORANGE := Color(1.0, 0.5, 0.1)
const BLAST_FIRE := Color(1.0, 0.36, 0.06)
const BLAST_POISON := Color(0.42, 0.85, 0.2)
const BLAST_BLUE := Color(0.28, 0.56, 1.0)
const BLAST_GOLD := Color(1.0, 0.76, 0.12)
const BLAST_SMOKE := Color(0.4, 0.35, 0.31)
const BLAST_CLOD := Color(0.3, 0.2, 0.12)
## The fireball's width against the blast's radius (its lumpy edge sits at about 0.88 of it: the ball shows about 0.62 r
## round, growing to 0.7 r as it burns; its lumps reach about as far), its life in seconds at a 2.5 m blast, the flash's
## width (about 0.8 r round) and life. The shock ring on the sand marks the real radius.
const BLAST_BALL := 1.4
const BLAST_BALL_LIFE := 0.36
const BLAST_FLASH := 1.7
const BLAST_FLASH_LIFE := 0.09
## How far up the screen the flash's and the ball's middle stands over the blast's foot, in their own sizes (they show
## about 0.44 of their size round, so their lower edge dips a little under the foot's line, which `toward` keeps out of
## the sand).
const BLAST_LIFT := 0.3
## A blast within BLAST_MERGE_SHARE of the larger radius of one that went off less than BLAST_MERGE_SECONDS ago only
## adds a few sparks to it (a volley of rockets on one pack, bomblets landing together).
const BLAST_MERGE_SECONDS := 0.12
const BLAST_MERGE_SHARE := 0.6
## The budget: past BLAST_BUSY blasts in the last BLAST_BUSY_SECONDS the rest go off cheap (the flash, the ball and a few
## sparks: no smoke, lumps or clods).
const BLAST_BUSY := 6
const BLAST_BUSY_SECONDS := 0.3
## The camera's kick (weapon_blast): none for a blast under BLAST_KICK_FROM m, then BLAST_KICK_PER a metre more (x its
## power), BLAST_KICK_MAX at most, never two within BLAST_KICK_GAP seconds; Settings' screen shake scales it (0 = off,
## CameraRig.shake). The rockets of a pod and the bomblets never kick.
const BLAST_KICK_FROM := 2.2
const BLAST_KICK_PER := 0.3
const BLAST_KICK_MAX := 0.6
const BLAST_KICK_GAP := 0.25
## The ground (weapon_blast): the shock ring races out to the radius over BLAST_RING_SECONDS, BLAST_RING_WIDTH of it wide;
## a full blast of BLAST_SCORCH_FROM m or more leaves a scorch BLAST_SCORCH_SHARE of its radius round (held
## BLAST_SCORCH_HOLD s, then fading over BLAST_SCORCH_FADE s), none where one was laid less than BLAST_SCORCH_GAP s ago
## within half the radius (a carpet of scorches under a missile swarm).
const BLAST_RING_SECONDS := 0.3
const BLAST_RING_WIDTH := 0.22
const BLAST_SCORCH_FROM := 1.2
const BLAST_SCORCH_SHARE := 0.62
const BLAST_SCORCH_HOLD := 1.2
const BLAST_SCORCH_FADE := 2.2
const BLAST_SCORCH_GAP := 1.0
const BLAST_SCORCH_IN := Color(0.12, 0.07, 0.05, 0.62)
const BLAST_SCORCH_OUT := Color(0.22, 0.14, 0.09, 0.0)

var _blast_mm: MultiMesh
var _blast_mat: ShaderMaterial
var _blast_head := 0
var _blast_used := 0
var _blast_last := -1.0
var _blast_end := PackedFloat32Array()
var _blast_kind := PackedByteArray()
## the blasts of the last moment ({at, r, t}: merging and the budget) and the scorches of the last second ({at, r, t})
var _blast_recent: Array = []
var _scorch_recent: Array = []
var _kick_t := -10.0
## its own random sequence: the shared one is replayed by the tests, and a blast must not shift it
var _blast_rng := RandomNumberGenerator.new()
## Diagnostics and tests: blasts drawn (full or cheap), merged, cheap, scorches laid, kicks given.
var blasts := 0
var blasts_merged := 0
var blasts_cheap := 0
var blast_scorches := 0
var blast_kicks := 0
## The last blast drawn (not merged): {at, r, power, style, col, ball (the fireball's width), pieces} (tests, tools).
var last_blast: Dictionary = {}


## The blast pool (pass 110): unit quads the blast shader moves, sizes and faces to the camera. Like the blood pool its
## transforms are data, so both bounding boxes are fixed.
func _blast_pool() -> void:
	_blast_end.resize(BLAST_MAX)
	_blast_kind.resize(BLAST_MAX)
	_blast_rng.randomize()
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = BLAST_MAX
	mm.visible_instance_count = 0
	mm.custom_aabb = AABB(Vector3(-200, -80, -200), Vector3(400, 120, 400))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Blasts"
	mmi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://core/shaders/blast_fx.gdshader")
	mat.set_shader_parameter("noise_tex", load("res://art/fx/fire_noise.png"))
	mat.render_priority = BLAST_PRIORITY
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -80, -200), Vector3(400, 120, 400))
	add_child(mmi)
	_blast_mm = mm
	_blast_mat = mat
	# one piece far under the map, so the shader compiles with the start (under the spawn beam), not on the first blast
	_blast_piece(Vector3(0, -60.0, 0), Vector3.ZERO, 0.1, 0.1, 0.0, 0.5, 0.0, 0.0, Color(1, 1, 1), 1.0, 0.0, 1, 0.0, 0.0)
	_blast_commit()
	_blast_end[0] = 0.0


## One piece into the ring: it starts at `at` `delay` seconds from now and flies on `vel` (its speed dying away by
## `drag` a second) under `grav`, from `s0` to `s1` metres across over `life` seconds; `stretch` a spark's length per m/s;
## `kind` (the shader's: 0 flash, 1 fireball, 2 smoke, 3 spark, 4 clod); `toward` metres towards the camera.
func _blast_piece(at: Vector3, vel: Vector3, s0: float, s1: float, grav: float, life: float, delay: float, stretch: float, col: Color, alpha: float, seed_v: float, kind: int, toward: float, drag: float) -> void:
	var i := _blast_head
	_blast_head = (_blast_head + 1) % BLAST_MAX
	_blast_used = maxi(_blast_used, i + 1)
	var birth := _blood_clock + delay
	_blast_mm.set_instance_transform(i, Transform3D(Basis(vel, Vector3(s0, s1, grav), Vector3(birth, maxf(life, 0.01), stretch)), at))
	_blast_mm.set_instance_color(i, Color(col.r, col.g, col.b, clampf(alpha, 0.0, 1.0)))
	_blast_mm.set_instance_custom_data(i, Color(seed_v, float(kind), toward, drag))
	_blast_end[i] = birth + life
	_blast_kind[i] = kind
	_blast_last = maxf(_blast_last, birth + life)


## After a blast's pieces are written: the pool draws as far as it has been used, and the shader's clock is now.
func _blast_commit() -> void:
	_blast_mm.visible_instance_count = _blast_used
	_blast_mat.set_shader_parameter("now", _blood_clock)


## The pool's clock (Fx's, advanced by _tick_blood); it stops drawing once its last piece is gone.
func _tick_blasts() -> void:
	if _blast_mm == null or _blast_mm.visible_instance_count == 0:
		return
	if _blood_clock > _blast_last:
		_blast_mm.visible_instance_count = 0
		return
	_blast_mat.set_shader_parameter("now", _blood_clock)


## A blast on the sand at `at` (its foot on the ground), `r` metres round, in `col` (BLAST_ORANGE and the rest, or a
## weapon's own), `style` BLAST_FULL or BLAST_SPLASH, `power` its strength (1 a plain blast; the Heavy Warhead's
## blast_fx.scale more: more sparks, clods and smoke). Returns what it did (BLAST_NONE .. BLAST_DONE). Only the pieces in
## the air: weapon_blast adds the ground and the camera.
func blast(at: Vector3, r: float, col: Color = BLAST_ORANGE, style: int = BLAST_FULL, power: float = 1.0) -> int:
	if Run.sim_mode or _blast_mm == null:
		return BLAST_NONE
	r = maxf(r, 0.4)
	var pw: float = clampf(power, 0.5, 3.0)
	var now := _blood_clock
	# the last moment's blasts: one beside this that has just gone off takes it in (a few sparks more)
	var keep: Array = []
	for e: Dictionary in _blast_recent:
		if now - float(e["t"]) < BLAST_BUSY_SECONDS:
			keep.append(e)
	_blast_recent = keep
	for e: Dictionary in _blast_recent:
		var d := Vector2(at.x - (e["at"] as Vector3).x, at.z - (e["at"] as Vector3).z).length()
		if now - float(e["t"]) < BLAST_MERGE_SECONDS and d < BLAST_MERGE_SHARE * maxf(r, float(e["r"])):
			blasts_merged += 1
			_blast_sparks(at + Vector3(0, clampf(r * 0.5, 0.5, 2.0), 0), r, col, 3)
			_blast_commit()
			return BLAST_MERGED
	var cheap := _blast_recent.size() >= BLAST_BUSY
	_blast_recent.append({"at": at, "r": r, "t": now})
	blasts += 1
	if cheap:
		blasts_cheap += 1
	var splash := style == BLAST_SPLASH
	var rng := _blast_rng
	var head0 := _blast_head
	# the flash and the ball stand on the blast's foot like a painting (the shader: their quad faces the camera through
	# the foot, its middle BLAST_LIFT of its size up the screen), drawn `toward` metres towards the camera so the sand never
	# cuts their lower edge, while a hero standing a few metres in front of the foot still covers them; `c` is where the
	# sparks and the smoke come from, about the ball's middle
	var hb: float = clampf(r * 0.5, 0.5, 2.0)
	var c := at + Vector3(0, hb, 0)
	var foot := at + Vector3(0, 0.05, 0)
	var toward: float = minf(r * 0.25, 1.2)
	var size_k: float = clampf(r / 2.5, 0.75, 1.35)
	# a stronger blast (the Heavy Warhead's scale) draws a bigger ball and flash than its radius; its ring stays true
	var grow: float = 1.0 + 0.35 * (pw - 1.0)
	var ball_w: float = r * (BLAST_BALL * 0.85 if splash else BLAST_BALL) * grow
	var ball_life: float = BLAST_BALL_LIFE * clampf(sqrt(r / 2.5), 0.8, 1.25) * (0.75 if splash else (0.9 + 0.1 * pw))
	var smoke_col := BLAST_SMOKE.lerp(Color(col.r * 0.4, col.g * 0.4, col.b * 0.4), 0.2)
	var phase := rng.randf() * TAU
	# written in the order they are drawn: smoke at the bottom, then the clods, the lumps, the ball, sparks, the flash
	if not cheap:
		var ns: int = 2 if splash else 4 + int(pw)
		for j in range(ns):
			var a := phase + TAU * (float(j) + rng.randf() * 0.6) / float(ns)
			var out := Vector3(cos(a), 0.0, sin(a))
			var o := at + out * rng.randf_range(0.1, 0.3) * r + Vector3(0, hb * rng.randf_range(0.6, 1.0), 0)
			var v := out * rng.randf_range(0.4, 0.9) * r * 0.6 + Vector3(0, rng.randf_range(0.9, 1.6), 0)
			_blast_piece(o, v, 0.4 * r, rng.randf_range(0.9, 1.2) * r, -0.5, rng.randf_range(0.8, 1.1),
				ball_life * rng.randf_range(0.3, 0.55), 0.0, smoke_col, 0.4 if splash else 0.52, rng.randf(), 2, toward * 0.8, 1.4)
	if not cheap and not splash:
		var nd: int = 5 + int(2.0 * pw)
		for j in range(nd):
			var a2 := rng.randf() * TAU
			var out2 := Vector3(cos(a2), 0.0, sin(a2))
			var v2 := out2 * rng.randf_range(2.0, 4.5) * (0.6 + 0.2 * r) + Vector3(0, rng.randf_range(4.5, 7.5), 0)
			var cs := BLAST_CLOD.lerp(Color(0.16, 0.11, 0.07), rng.randf())
			_blast_piece(at + out2 * 0.25 * r + Vector3(0, 0.3, 0), v2, rng.randf_range(0.16, 0.26) * size_k, 0.0, 20.0,
				rng.randf_range(0.55, 0.85), 0.0, 0.0, cs, 1.0, rng.randf(), 4, 0.3, 0.3)
		# three lumps round the ball, pushed out a little, so its outline billows
		for j in range(3):
			var a3 := phase + TAU * (float(j) + 0.3 + rng.randf() * 0.4) / 3.0
			var out3 := Vector3(cos(a3), 0.0, sin(a3))
			var o3 := foot + out3 * 0.32 * r
			_blast_piece(o3, out3 * r * 1.2, ball_w * 0.3, ball_w * rng.randf_range(0.5, 0.58), 0.0,
				ball_life * rng.randf_range(0.8, 0.92), rng.randf_range(0.0, 0.035), BLAST_LIFT * rng.randf_range(0.6, 1.1), col, 1.0, rng.randf(), 1, toward * 0.95, 5.0)
	# the fireball
	_blast_piece(foot, Vector3.ZERO, ball_w * 0.35, ball_w, 0.0, ball_life, 0.0, BLAST_LIFT, col, 1.0, rng.randf(), 1, toward, 0.0)
	# sparks
	var nk: int = 4 if cheap else (6 if splash else 10 + int(4.0 * pw))
	_blast_sparks(c, r, col, nk)
	# the flash on top
	var fw: float = r * BLAST_FLASH * (0.7 if splash else 1.0) * grow
	_blast_piece(foot, Vector3.ZERO, fw * 0.36, fw, 0.0, BLAST_FLASH_LIFE * (0.75 if splash else 1.0), 0.0, BLAST_LIFT,
		col, 1.0, rng.randf(), 0, toward + 0.05, 0.0)
	_blast_commit()
	last_blast = {"at": at, "r": r, "power": pw, "style": style, "col": col, "ball": ball_w, "pieces": _blast_head - head0 if _blast_head >= head0 else _blast_head + BLAST_MAX - head0}
	return BLAST_CHEAP if cheap else BLAST_DONE


## `n` sparks flung out of `c` and falling, drawn long along their flight.
func _blast_sparks(c: Vector3, r: float, col: Color, n: int) -> void:
	var rng := _blast_rng
	var sk: float = clampf(r / 2.5, 0.8, 1.2)
	var reach: float = clampf(0.55 + 0.18 * r, 0.7, 1.4)
	for j in range(n):
		var a := rng.randf() * TAU
		var out := Vector3(cos(a), 0.0, sin(a))
		var v := out * rng.randf_range(6.0, 11.0) * reach + Vector3(0, rng.randf_range(2.5, 6.5), 0)
		var s0: float = rng.randf_range(0.2, 0.28) * sk
		_blast_piece(c + out * 0.2 * r, v, s0, s0 * 0.4, 16.0, rng.randf_range(0.3, 0.55), 0.0, 0.1, col, 1.0, rng.randf(), 3, 0.6, 1.2)


## The hero's weapons' blast (pass 110): blast() in the air at `at` on the ground (its height taken from the map), and
## on the sand a shock ring racing out to the radius, a scorch for a full one (one at a spot a second), and a short kick
## of the camera for a big one (BLAST_KICK_*, scaled by Settings' screen shake). `game` gives the map, the ground marks
## and the camera (Fx's parent when null); anything it lacks is left out.
func weapon_blast(at: Vector3, r: float, col: Color = BLAST_ORANGE, style: int = BLAST_FULL, power: float = 1.0, game: Node = null) -> int:
	if game == null:
		game = get_parent()
	var ground := at
	var map = game.get("map") if game else null
	if map != null and map.has_method("height_at"):
		ground.y = float(map.height_at(at.x, at.z))
	var how := blast(ground, r, col, style, power)
	if how == BLAST_NONE:
		return how
	var tg = game.get("telegraphs") if game else null
	if tg != null and how != BLAST_MERGED:
		if tg.has_method("race_ring"):
			tg.race_ring(ground, r, BLAST_RING_SECONDS, Color(col.r, col.g, col.b, 0.9), BLAST_RING_WIDTH)
		if style == BLAST_FULL and r >= BLAST_SCORCH_FROM and tg.has_method("scorch") and _scorch_free(ground, r):
			tg.scorch(ground, r * BLAST_SCORCH_SHARE, BLAST_SCORCH_IN, BLAST_SCORCH_OUT, BLAST_SCORCH_HOLD, BLAST_SCORCH_FADE)
			blast_scorches += 1
	var cam = game.get("camera") if game else null
	if cam != null and cam.has_method("shake") and style == BLAST_FULL:
		var k := blast_kick(r, power)
		if k > 0.0 and _blood_clock - _kick_t >= BLAST_KICK_GAP:
			_kick_t = _blood_clock
			blast_kicks += 1
			cam.shake(k)
	return how


## The camera's kick for a blast `r` metres round at `power` (before Settings' screen shake): 0 under BLAST_KICK_FROM.
static func blast_kick(r: float, power: float = 1.0) -> float:
	return clampf((r - BLAST_KICK_FROM) * BLAST_KICK_PER * clampf(power, 0.5, 2.0), 0.0, BLAST_KICK_MAX)


## Whether a scorch may be laid at `at` (none within half of `r` laid less than BLAST_SCORCH_GAP s ago); notes it.
func _scorch_free(at: Vector3, r: float) -> bool:
	var keep: Array = []
	for e: Dictionary in _scorch_recent:
		if _blood_clock - float(e["t"]) < BLAST_SCORCH_GAP:
			keep.append(e)
	_scorch_recent = keep
	for e: Dictionary in _scorch_recent:
		var d := Vector2(at.x - (e["at"] as Vector3).x, at.z - (e["at"] as Vector3).z).length()
		if d < 0.5 * maxf(r, float(e["r"])):
			return false
	_scorch_recent.append({"at": at, "r": r, "t": _blood_clock})
	return true


## A weapon's blast colour: its `params.blast_fx.color` when it names one (the Golden Pineapple), else by its element
## (fire, blue fire, poison), else the plain blast's orange.
static func blast_colour(w: WeaponInstance, element: String = "") -> Color:
	if w != null:
		var bfx = w.params.get("blast_fx")
		if bfx is Dictionary and (bfx as Dictionary).has("color"):
			return Color(str((bfx as Dictionary)["color"]))
	if element == "poison":
		return BLAST_POISON
	if element == "fire":
		return BLAST_BLUE if (w != null and w.blue_fire()) else BLAST_FIRE
	return BLAST_ORANGE


## A weapon's blast style: full for a weapon tagged `explosive`, else the splash.
static func blast_style(w: WeaponInstance) -> int:
	if w != null and w.def != null and w.def.tags.has("explosive"):
		return BLAST_FULL
	return BLAST_SPLASH


## How many blast pieces are showing or about to (tests).
func blast_count() -> int:
	var n := 0
	for i in range(_blast_used):
		if _blast_end[i] > _blood_clock:
			n += 1
	return n


## How many pieces of `kind` are showing or about to (tests: a full blast has its flash, ball, smoke, sparks and clods).
func blast_kind_count(kind: int) -> int:
	var n := 0
	for i in range(_blast_used):
		if _blast_end[i] > _blood_clock and _blast_kind[i] == kind:
			n += 1
	return n
