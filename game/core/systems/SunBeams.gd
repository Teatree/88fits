## Pillars of sunlight (pass 54, the Sun Scepter and Zenith): up to MAX tall soft beams standing on the sand, every one an
## instance of a single MultiMesh drawn by core/shaders/sun_beam.gdshader, so Zenith's forty cost one draw call as one
## pillar does. A pillar brightens from WARN_FLOOR to `flash` over its warning (an ease-in), flashes LAND_POP brighter as its
## warning ends (the strike lands) and is gone FADE seconds later; its slot goes back to the pool. begin() lights one and
## returns its id; the owner calls tick() on every frame it is not paused, so a pause holds the light where it is.
## Pass 61 (Garry: "Make the attack of the scepter visuals a bit stronger. For both the 'projectile' and the scepter
## itself"): the landing hits harder and lingers: LAND_POP 0.6 -> 0.85, FADE 0.2 -> 0.34, and an impact channel
## (impact_at, the instance's custom z) that widens the quad by LAND_WIDEN and fattens and whitens the white thread in
## the shader for that instant, falling away over the fade.
class_name SunBeams
extends Node3D

const MAX := 48
## How tall a pillar stands (it fades out towards its top) and how long the flash takes to die after it lands.
const HEIGHT := 16.0
const FADE := 0.34
## The landing flash: this much over the warning's end for an instant, falling back over FADE.
const LAND_POP := 0.85
## The landing's width (pass 61): the quad this much wider at the instant it lands, back to its own width over FADE.
const LAND_WIDEN := 0.25
## A pillar's strength the moment it appears, a share of `flash` (pass 54, the lead: rising from nothing, an additive pale
## beam on bright sand was invisible for most of its 0.45 s warning; the gold ring alone showed)
const WARN_FLOOR := 0.3
## A beam's quad is this many times the strike's diameter: its soft core shows over a little more than half of it.
const WIDTH_PER_DIAMETER := 1.4
const SHADER := preload("res://core/shaders/sun_beam.gdshader")

var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _beams: Array = []   # {id, at, w, t, warn, flash, tint, alpha, phase}
var _next_id := 1


func _init() -> void:
	# its own place in the world: the instances are written in world space
	top_level = true
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	q.center_offset = Vector3(0.0, 0.5, 0.0)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	# the flags go before the count, or the buffer is built without room for them
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = q
	_mm.instance_count = MAX
	_mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	_mmi.material_override = mat
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(_mmi)


## A pillar standing on `at` (its foot on the sand) for a strike `r` metres round, brightening over `warn` seconds in
## `tint` at `alpha`, `flash` at its brightest; `thin` narrows it (Flicker); `land` scales its landing's pop and impact
## (pass 61: a Zenith sweep's forty land at half, or together they white the screen out). Returns its id, -1 when all MAX
## are lit.
func begin(at: Vector3, r: float, warn: float, tint: Color, alpha: float, flash: float = 1.0, thin: float = 1.0, land: float = 1.0) -> int:
	if _beams.size() >= MAX:
		return -1
	var id := _next_id
	_next_id += 1
	_beams.append({"id": id, "at": at, "w": maxf(2.0 * r * WIDTH_PER_DIAMETER * thin, 0.2), "t": 0.0,
		"warn": maxf(warn, 0.01), "flash": flash, "tint": tint, "alpha": alpha, "phase": randf() * 10.0, "land": land})
	_draw()
	return id


## Every pillar a frame on; the ones whose flash has died go back to the pool.
func tick(delta: float) -> void:
	if _beams.is_empty():
		return
	var keep: Array = []
	for b: Dictionary in _beams:
		b["t"] = float(b["t"]) + delta
		if float(b["t"]) < float(b["warn"]) + FADE:
			keep.append(b)
	_beams = keep
	_draw()


## A pillar's strength at `t` seconds old: an ease-in to `flash` over the warning, LAND_POP over it as it lands, then
## falling to nothing over FADE.
static func strength_at(t: float, warn: float, flash: float, land: float = 1.0) -> float:
	if t < warn:
		var u := t / maxf(warn, 0.01)
		return flash * (WARN_FLOOR + (1.0 - WARN_FLOOR) * u * u)
	var v := clampf((t - warn) / FADE, 0.0, 1.0)
	return flash * (1.0 + LAND_POP * land * (1.0 - v)) * (1.0 - v)


## The landing's impact at `t` seconds old (pass 61): 0 through the warning, 1 the instant it lands, falling away over
## FADE on an ease-out (the shader's fat white core and lit foot, the quad's extra width).
static func impact_at(t: float, warn: float) -> float:
	if t < warn:
		return 0.0
	var v := clampf((t - warn) / FADE, 0.0, 1.0)
	return (1.0 - v) * (1.0 - v)


## A pillar's drawn width at `t` seconds old, its own width `w`: LAND_WIDEN wider the instant it lands, back over FADE.
static func width_at(w: float, t: float, warn: float, land: float = 1.0) -> float:
	return w * (1.0 + LAND_WIDEN * land * impact_at(t, warn))


## How many pillars are lit now (tests, the perf report).
func live() -> int:
	return _beams.size()


## The strength pillar `id` shows now (tests), -1 when it is gone.
func strength_of(id: int) -> float:
	for b: Dictionary in _beams:
		if int(b["id"]) == id:
			return strength_at(float(b["t"]), float(b["warn"]), float(b["flash"]), float(b.get("land", 1.0)))
	return -1.0


func clear() -> void:
	_beams.clear()
	_draw()


## The shader's warm-up (Warmup): one faint pillar at `at` for a moment.
func warm(at: Vector3) -> void:
	begin(at, 0.5, 0.25, Color(1.0, 0.85, 0.4), 0.02)


func _draw() -> void:
	var n := 0
	for b: Dictionary in _beams:
		var at: Vector3 = b["at"]
		var land := float(b.get("land", 1.0))
		var imp := impact_at(float(b["t"]), float(b["warn"])) * land
		_mm.set_instance_transform(n, Transform3D(Basis.from_scale(Vector3(width_at(float(b["w"]), float(b["t"]), float(b["warn"]), land), HEIGHT, 1.0)), at))
		var c: Color = b["tint"]
		_mm.set_instance_color(n, Color(c.r, c.g, c.b, float(b["alpha"])))
		_mm.set_instance_custom_data(n, Color(strength_at(float(b["t"]), float(b["warn"]), float(b["flash"]), land), float(b["phase"]), imp, 0.0))
		n += 1
	_mm.visible_instance_count = n
