## Pass 119 (lane LEGEND_A): Personal Storm, a legendary passive item (content/passives/personal_storm; Garry: "darkens
## the area with 'clouds moving in' and for a period of time lighting strikes randomly at various spots causing damage
## and significant knockback to enemies (it strikes not just enemies but all around the ground, with a preference for
## enemy groups). Strikes leave a mark on the ground that fades away after some time"). Every `storm_every` s (the
## item's stat: 30 at Legendary, 24 Evolved) one storm:
##   1. the clouds gather (params.storm.gather s): cloud shadows roll in over a circle of `radius` m round the hero and
##      drift with the wind (core/shaders/storm_shadow.gdshader, laid on the sand), the screen dims under an overcast
##      that creeps in from its edges (storm_dim.gdshader on a canvas layer under the HUD), thunder rolls;
##   2. for `storm_seconds` s (8 Legendary, 10 Evolved) lightning strikes about `rate` times a second at spots in the
##      circle (it follows the hero at `follow` a second): `crowd_share` of them seek a crowd (of `samples` creatures
##      drawn in the circle, the one with the most others within `strike_r` m), the rest any spot on the ground, never
##      within `hero_clear` m of the hero nor within `apart` m of the last few. Each spot glows for `tell` s, then the bolt:
##      every creature within `strike_r` m takes `damage` x attack damage (x the stage multiplier when `stage_scaled`;
##      x `big_mult` for an Elite or a boss), never a crit, and is thrown outwards (`knock`, x `big_knock` for an Elite or
##      a boss; an explosive push, HIT_BLAST), and the sand keeps a scorch mark that holds `mark_hold` s and fades over
##      `mark_fade` s (Telegraphs.scorch, pooled). The hero is never hit;
##   3. the clouds clear (`clear` s), the way they came.
## Rules on the run's delta (Game._process, Lockstep.dt) and its own dice (Dice.rng_for("personal_storm")); every look on
## the looks' stream. Game._tick_legends makes this node the first time the item is held.
class_name PersonalStorm
extends Node3D

const ID := "personal_storm"
const SOURCE := "personal_storm"
const SHADOW_SHADER := preload("res://core/shaders/storm_shadow.gdshader")
const DIM_SHADER := preload("res://core/shaders/storm_dim.gdshader")
const BOLT := Color(0.55, 0.78, 1.0)
const TELL := Color(0.62, 0.84, 1.0)
const SCORCH_IN := Color(0.07, 0.07, 0.11, 0.85)
const SCORCH_OUT := Color(0.22, 0.18, 0.2, 0.0)
## Every rule number's default (the item's params.storm names each; BALANCING 61.LEGEND_A).
const DEFAULTS := {
	"every": 30.0, "seconds": 8.0, "first": 4.0, "gather": 1.6, "clear": 1.6, "radius": 9.0, "follow": 1.2,
	"rate": 2.0, "crowd_share": 0.75, "samples": 6.0, "strike_r": 2.0, "tell": 0.3, "damage": 40.0,
	"stage_scaled": 1.0, "big_mult": 0.5, "knock": 34.0, "big_knock": 0.4, "hero_clear": 1.6, "apart": 2.0,
	"mark_hold": 2.0, "mark_fade": 4.0, "dim": 0.3, "darkness": 0.4, "shadow_scale": 1.6,
}
## How many past strikes a new one keeps `apart` from.
const RECENT := 3

enum { IDLE, GATHER, STRIKE, CLEAR }

var game: Node = null
var phase := IDLE
## seconds until the next storm (-1: not started: `first` once the item is held)
var clock := -1.0
## seconds into the phase
var t := 0.0
## where the storm stands (it follows the hero)
var center := Vector3.ZERO
## how far the clouds are in, 0..1
var cover := 0.0
var _next := 0.0
## the strikes waiting out their tell: [{at: Vector3, t: seconds left}]
var pending: Array = []
var _recent: Array = []
var _rng: RandomNumberGenerator = Dice.rng_for("personal_storm")
var _looks := true
var _shadow: MeshInstance3D = null
var _shadow_mat: ShaderMaterial = null
var _dim_layer: CanvasLayer = null
var _dim_mat: ShaderMaterial = null
var _flash := 0.0
## the looks' fronts: the clouds' leading edge sweeping in (0..1) and their trailing edge sweeping after it (0..1)
var _in := 0.0
var _out := 0.0
## the wind the clouds ride (on the ground; the overcast reads it in screen axes, x right and y down = +z)
const WIND := Vector2(1.0, 0.4)
# for the tests, the captures and the analytics
var storms := 0
var strikes := 0
var crowd_strikes := 0
var hits := 0
## every strike this storm: [{at, crowd, hit}]
var strike_log: Array = []


## The item's params.storm number `key` (DEFAULTS when it names none).
static func param(key: String, fallback: float = INF) -> float:
	var d: PassiveDef = Registry.passive(ID)
	var p = d.params.get("storm", {}) if d else {}
	var def_v: float = float(DEFAULTS.get(key, 0.0)) if fallback == INF else fallback
	return float((p as Dictionary).get(key, def_v)) if p is Dictionary else def_v


## Whether the hero holds Personal Storm.
static func active() -> bool:
	return Run.passives.has(ID)


## Seconds between two storms now (the item's storm_every: 30 Legendary, 24 Evolved).
static func every() -> float:
	return maxf(Run.player_sheet.get_stat("storm_every", param("every")), 1.0)


## Seconds a storm strikes for (storm_seconds: 8 Legendary, 10 Evolved).
static func seconds() -> float:
	return maxf(Run.player_sheet.get_stat("storm_seconds", param("seconds")), 0.5)


## What a creature within a strike takes: `damage` x attack damage (x the stage multiplier when `stage_scaled`), x
## `big_mult` for an Elite or a boss.
static func strike_amount(big: bool) -> float:
	var d := param("damage") * Run.player_sheet.get_stat("might", 1.0)
	if param("stage_scaled") > 0.5:
		d *= Run.stage_mult()
	return d * (param("big_mult") if big else 1.0)


## Pass 119: the cloud shadows' material on a small disc under `parent` (Warmup's pit) and the overcast's canvas material on
## a small rect in `ui` (Warmup's near-invisible labels), so the first storm never stalls on a compile.
static func warm(parent: Node3D, ui: Control) -> void:
	var d := MeshInstance3D.new()
	d.mesh = _disc_mesh(2, 8)
	var sm := ShaderMaterial.new()
	sm.shader = SHADOW_SHADER
	d.material_override = sm
	d.custom_aabb = AABB(Vector3(-1000, -100, -1000), Vector3(2000, 200, 2000))
	parent.add_child(d)
	if ui:
		var rect := ColorRect.new()
		rect.size = Vector2(4, 4)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dm := ShaderMaterial.new()
		dm.shader = DIM_SHADER
		rect.material = dm
		ui.add_child(rect)


func setup(p_game: Node) -> void:
	game = p_game
	Dice.seed_rng(_rng, "personal_storm")
	_looks = not Run.sim_mode


## Starts a storm at once (the captures; the tests).
func trigger() -> void:
	if phase == IDLE:
		_start()


func tick(delta: float) -> void:
	if active():
		if clock < 0.0 and phase == IDLE:
			clock = param("first")
	else:
		clock = -1.0
		if phase == GATHER or phase == STRIKE:
			phase = CLEAR
			t = 0.0
	var hero = game.player if game else null
	var up: bool = hero != null and not bool(hero.get("dead"))
	# the next storm's clock runs from this one's start (a storm every `every` s), held while the hero is down
	if active() and up and clock > 0.0:
		clock -= delta
	match phase:
		IDLE:
			if active() and up and clock <= 0.0:
				_start()
		GATHER:
			t += delta
			cover = smoothstep(0.0, 1.0, t / maxf(param("gather"), 0.05))
			if t >= param("gather"):
				phase = STRIKE
				t = 0.0
				_next = 0.1
		STRIKE:
			t += delta
			cover = 1.0
			_next -= delta
			while _next <= 0.0 and t < seconds():
				_schedule()
				_next += _gap()
			if t >= seconds():
				phase = CLEAR
				t = 0.0
		CLEAR:
			t += delta
			cover = 1.0 - smoothstep(0.0, 1.0, t / maxf(param("clear"), 0.05))
			if t >= param("clear") and pending.is_empty():
				phase = IDLE
				cover = 0.0
	if phase != IDLE:
		_follow(delta)
	_tick_pending(delta)
	if _looks:
		_tick_looks(delta)


## Whether a storm is up (its clouds or a strike still to land).
func busy() -> bool:
	return phase != IDLE or not pending.is_empty()


func _start() -> void:
	phase = GATHER
	t = 0.0
	cover = 0.0
	clock = every()
	storms += 1
	strike_log.clear()
	_recent.clear()
	center = _hero_pos()
	Audio.play("it_storm_gather", center)


## The seconds to the next strike: 1 / rate, give or take 30%.
func _gap() -> float:
	return (1.0 / maxf(param("rate"), 0.1)) * _rng.randf_range(0.7, 1.3)


func _follow(delta: float) -> void:
	var h := _hero_pos()
	center = center.lerp(Vector3(h.x, center.y, h.z), clampf(param("follow") * delta, 0.0, 1.0))


# ---------------------------------------------------------------- the strikes

## One strike: its spot picked now, its tell shown, the bolt after `tell` s.
func _schedule() -> void:
	var pick := pick_spot()
	var at: Vector3 = pick["at"]
	at.y = _h(at.x, at.z)
	pending.append({"at": at, "t": param("tell"), "crowd": bool(pick["crowd"])})
	_recent.push_front(at)
	if _recent.size() > RECENT:
		_recent.resize(RECENT)
	if _looks:
		var tg = game.telegraphs if game else null
		if tg and tg.has_method("ring"):
			tg.ring(at, param("strike_r") * 0.8, param("tell") + 0.05, TELL, true)


## Where the next bolt lands: {at, crowd}. With `crowd_share` the spot of the creature in the circle with the most others
## round it (of `samples` drawn), else any spot on the ground in the circle; kept `hero_clear` m off the hero and `apart`
## m off the last strikes (a few tries, then as it is).
func pick_spot() -> Dictionary:
	var r := param("radius")
	var ens = game.enemies if game else null
	var hero := _hero_pos()
	if ens != null and _rng.randf() < param("crowd_share"):
		var cands: PackedInt32Array = ens.indices_in_radius(center, r)
		if not cands.is_empty():
			var best := -1
			var best_n := -1
			var draws := mini(int(param("samples")), cands.size())
			for k in range(draws):
				var i: int = cands[_rng.randi() % cands.size()]
				if not ens.is_alive(i):
					continue
				var p: Vector3 = ens.position_of(i)
				if _near_recent(p) or _flat_dist(p, hero) < param("hero_clear"):
					continue
				var n: int = (ens.indices_in_radius(p, param("strike_r")) as PackedInt32Array).size()
				if n > best_n:
					best_n = n
					best = i
			if best >= 0:
				var bp: Vector3 = ens.position_of(best)
				crowd_strikes += 1
				return {"at": _clear_of_hero(bp + Vector3(_rng.randf_range(-0.4, 0.4), 0.0, _rng.randf_range(-0.4, 0.4)), hero), "crowd": true}
	var spot := center
	for tries in range(4):
		var a := _rng.randf() * TAU
		var d := sqrt(_rng.randf()) * r
		spot = center + Vector3(cos(a), 0.0, sin(a)) * d
		if not _near_recent(spot) and _flat_dist(spot, hero) >= param("hero_clear"):
			break
	return {"at": _clear_of_hero(spot, hero), "crowd": false}


func _near_recent(p: Vector3) -> bool:
	var ap := param("apart")
	for q: Vector3 in _recent:
		if _flat_dist(p, q) < ap:
			return true
	return false


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## `p` pushed out to `hero_clear` m from the hero when it is nearer (never a bolt on his head).
func _clear_of_hero(p: Vector3, hero: Vector3) -> Vector3:
	var c := param("hero_clear")
	var d := Vector3(p.x - hero.x, 0.0, p.z - hero.z)
	if d.length() >= c:
		return p
	if d.length_squared() < 0.0001:
		d = Vector3(1.0, 0.0, 0.0)
	var q := hero + d.normalized() * c
	return Vector3(q.x, p.y, q.z)


func _tick_pending(delta: float) -> void:
	if pending.is_empty():
		return
	var keep: Array = []
	var due: Array = []
	for s: Dictionary in pending:
		s["t"] = float(s["t"]) - delta
		if float(s["t"]) <= 0.0:
			due.append(s)
		else:
			keep.append(s)
	pending = keep
	for s: Dictionary in due:
		land(s["at"], bool(s.get("crowd", false)))


## The bolt at `at`: every creature within strike_r takes strike_amount and is thrown outwards; the looks.
func land(at: Vector3, crowd: bool = false) -> int:
	strikes += 1
	var n := 0
	var ens = game.enemies if game else null
	if ens != null:
		var sr := param("strike_r")
		for i: int in ens.indices_touching(at, sr, 0.3):
			if not ens.is_alive(i):
				continue
			var big: bool = ens.is_big_game(i)
			var p: Vector3 = ens.position_of(i)
			var d := Vector3(p.x - at.x, 0.0, p.z - at.z)
			if d.length_squared() < 0.0001:
				d = Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0))
			var force := param("knock") * (param("big_knock") if big else 1.0)
			ens.damage(i, strike_amount(big), SOURCE, d.normalized(), force, false, false, EnemyManager.HIT_BLAST | EnemyManager.HIT_NO_CRIT)
			n += 1
	hits += n
	strike_log.append({"at": at, "crowd": crowd, "hit": n})
	if _looks:
		_bolt(at)
	return n


# ---------------------------------------------------------------- the looks

func _bolt(at: Vector3) -> void:
	var top := at + Vector3(randf_range(-2.5, 2.5), 18.0, randf_range(-2.5, 2.5))
	var m1 := at.lerp(top, 0.62) + Vector3(randf_range(-1.2, 1.2), 0.0, randf_range(-1.2, 1.2))
	var m2 := at.lerp(top, 0.28) + Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
	_fx("lightning", [[top, m1, m2, at + Vector3(0, 0.1, 0)], BOLT, 1.25])
	if randf() < 0.5:
		var fork := m1 + Vector3(randf_range(-2.5, 2.5), randf_range(-4.0, -2.0), randf_range(-2.5, 2.5))
		_fx("lightning", [[m1, fork], BOLT, 0.6])
	_fx("burst", [at + Vector3(0, 0.4, 0), Color(0.85, 0.93, 1.0), 1.8, 1.0, true])
	_fx("sand", [at, 0.9])
	var tg = game.telegraphs if game else null
	if tg:
		if tg.has_method("scorch"):
			tg.scorch(at, 1.15, SCORCH_IN, SCORCH_OUT, param("mark_hold"), param("mark_fade"))
		if tg.has_method("flash_ring"):
			tg.flash_ring(at, param("strike_r"), BOLT, 0.35)
	_shake(0.35)
	_flash = 1.0
	Audio.play("it_storm_strike", at)


func _tick_looks(delta: float) -> void:
	_flash = maxf(_flash - delta * 6.0, 0.0)
	var show := cover > 0.001
	if show and _shadow == null:
		_build_looks()
	match phase:
		GATHER:
			_in = cover
			_out = 0.0
		STRIKE:
			_in = 1.0
			_out = 0.0
		CLEAR:
			_in = 1.0
			_out = 1.0 - cover
		_:
			_in = 0.0
			_out = 0.0
	if _shadow:
		_shadow.visible = show
		_shadow_mat.set_shader_parameter("center", Vector2(center.x, center.z))
		_shadow_mat.set_shader_parameter("cover_in", _in)
		_shadow_mat.set_shader_parameter("cover_out", _out)
		_shadow_mat.set_shader_parameter("radius", param("radius") * param("shadow_scale"))
	if _dim_layer:
		_dim_layer.visible = show
		_dim_mat.set_shader_parameter("cover_in", _in)
		_dim_mat.set_shader_parameter("cover_out", _out)
		_dim_mat.set_shader_parameter("flash", _flash)


func _build_looks() -> void:
	_shadow = MeshInstance3D.new()
	_shadow.name = "CloudShadows"
	_shadow.mesh = _disc_mesh(14, 48)
	_shadow_mat = ShaderMaterial.new()
	_shadow_mat.shader = SHADOW_SHADER
	_shadow_mat.set_shader_parameter("darkness", param("darkness"))
	_shadow_mat.set_shader_parameter("wind", WIND)
	var m = game.map if game else null
	if m and int(m.get("grid_n")) >= 2:
		var gn := int(m.grid_n)
		var img := Image.create_from_data(gn, gn, false, Image.FORMAT_RF, (m.heights as PackedFloat32Array).to_byte_array())
		_shadow_mat.set_shader_parameter("heights", ImageTexture.create_from_image(img))
		_shadow_mat.set_shader_parameter("grid_n", gn)
		_shadow_mat.set_shader_parameter("half_size", float(m.size_m) * 0.5)
		_shadow_mat.set_shader_parameter("resolution", float(m.resolution))
	_shadow.material_override = _shadow_mat
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# its vertices are placed by the shader round `center`: never culled
	_shadow.custom_aabb = AABB(Vector3(-1000, -100, -1000), Vector3(2000, 200, 2000))
	add_child(_shadow)
	_dim_layer = CanvasLayer.new()
	_dim_layer.name = "Overcast"
	_dim_layer.layer = 0
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim_mat = ShaderMaterial.new()
	_dim_mat.shader = DIM_SHADER
	_dim_mat.set_shader_parameter("dim", param("dim"))
	_dim_mat.set_shader_parameter("wind", WIND)
	rect.material = _dim_mat
	_dim_layer.add_child(rect)
	add_child(_dim_layer)


## A flat disc of unit radius in rings x segments (UV.x 0 at the middle .. 1 at the rim); the shader lays it on the sand.
static func _disc_mesh(rings: int, segs: int) -> ArrayMesh:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	v.append(Vector3.ZERO)
	uv.append(Vector2.ZERO)
	for k in range(1, rings + 1):
		var rr := float(k) / float(rings)
		for s in range(segs):
			var a := TAU * float(s) / float(segs)
			v.append(Vector3(cos(a) * rr, 0.0, sin(a) * rr))
			uv.append(Vector2(rr, float(s) / float(segs)))
	for s in range(segs):
		idx.append_array([0, 1 + s, 1 + (s + 1) % segs])
	for k in range(1, rings):
		var a0 := 1 + (k - 1) * segs
		var a1 := 1 + k * segs
		for s in range(segs):
			var s1 := (s + 1) % segs
			idx.append_array([a0 + s, a1 + s, a1 + s1, a0 + s, a1 + s1, a0 + s1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


# ---------------------------------------------------------------- the world it reads

func _hero_pos() -> Vector3:
	var hero = game.player if game else null
	return (hero as Node3D).global_position if hero is Node3D else Vector3.ZERO


func _h(x: float, z: float) -> float:
	var m = game.map if game else null
	return float(m.height_at(x, z)) if m and m.has_method("height_at") else 0.0


func _shake(k: float) -> void:
	var cam = game.camera if game else null
	if cam and cam.has_method("shake"):
		cam.call("shake", k)


func _fx(fn: String, args: Array) -> void:
	var fx = game.fx if game else null
	if fx and fx.has_method(fn):
		fx.callv(fn, args)
