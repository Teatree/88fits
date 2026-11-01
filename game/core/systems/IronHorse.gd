## Pass 119 (lane LEGEND_A): the Iron Horse, a legendary passive item (content/passives/iron_horse; Garry: "our most
## powerful one yet ... There should be some visual foreshadowing that the Train is about to come, not just the whistle
## ... Each part of this sequence should be accompanied by animation. Start to Finish ... There should be knockback from
## the Train running over enemies"). Every `train_every` s (the item's stat: 20 at Legendary, 15 Evolved) one cycle:
##   1. the rumble (params.train.rumble s): a low rumble grows, the camera starts to shake, dust hops on the sand round
##      the hero and a ghost headlight glimmers at the screen's edge behind him (where the train will come from);
##   2. the whistle: the line locks through the hero along the way he faces (`train_cross` 1: a second line across it,
##      its train `cross_delay` s behind). Ghost rails and sleepers rise out of the sand from the back end to the front
##      in `assemble` s, a crest of light riding the wave, dust lifting along them, a glow strip under them
##      (Telegraphs.line); the headlight at the edge grows and throws its beam down the rails;
##   3. `warn` s after the whistle the engine's nose reaches the hero's spot: the ghost train (art/props/iron_horse.glb:
##      the Railway Kit's locomotive, a tender and a coach; core/shaders/ghost_train.gdshader turns its wheels and works
##      its rods) charges down the rails at `speed` m/s, ghost smoke streaming from its stack, sparks at its wheels, sand
##      thrown up behind it. Everything it runs over (within `width` m of the line) takes `share` of its max HP
##      (`big_share` for an Elite or a boss) + `damage` x attack damage (x the stage multiplier when `stage_scaled`),
##      never a crit (EnemyManager.HIT_NO_CRIT), and is thrown aside off the rails and a little forward (`knock`, x
##      `big_knock` for an Elite or a boss; an explosive push Endless never resists, HIT_BLAST); each creature once a
##      train. The hero is never hit;
##   4. the wake: the rails behind the tail sink and fade in ghost wisps, the smoke drifts and thins, the train fades out
##      past the far end.
## Rules on the run's delta (Game._process, Lockstep.dt) and on its own dice (Dice.rng_for("iron_horse")); every look on
## the looks' stream. Game._tick_legends makes this node the first time the item is held; it idles while it is not.
class_name IronHorse
extends Node3D

const ID := "iron_horse"
const SOURCE := "iron_horse"
const TRAIN_SCENE := "res://art/props/iron_horse.glb"
const GHOST_SHADER := preload("res://core/shaders/ghost_train.gdshader")
const RAIL_SHADER := preload("res://core/shaders/ghost_rails.gdshader")
const GLOW_SHADER := preload("res://core/shaders/ghost_glow.gdshader")
const BEAM_SHADER := preload("res://core/shaders/ghost_beam.gdshader")
const CARS := ["Engine", "Tender", "Coach"]
const GHOST := Color(0.45, 0.95, 0.82)
const GHOST_PALE := Color(0.82, 1.0, 0.96)
const STRIP := Color(0.35, 1.0, 0.85)
const SMOKE := Color(0.8, 0.98, 0.93, 0.5)
## Every rule number's default (the item's params.train names each; BALANCING 61.LEGEND_A).
const DEFAULTS := {
	"every": 20.0, "first": 4.0, "rumble": 1.2, "warn": 1.0, "assemble": 0.55, "speed": 30.0, "half_length": 24.0,
	"width": 1.8, "share": 0.25, "big_share": 0.05, "damage": 35.0, "stage_scaled": 1.0, "knock": 30.0,
	"big_knock": 0.35, "forward": 0.35, "cross_delay": 0.35, "scale": 0.9, "car_gap": 0.5,
}

enum { IDLE, RUMBLE }

## One line's train: its whistle's moment, its line, the creatures it has struck, and its looks.
class TrainRun:
	extends RefCounted
	var origin := Vector3.ZERO
	var dir := Vector3.FORWARD
	var side := Vector3.RIGHT
	## seconds since its whistle (negative while a crossing train waits its turn)
	var u := 0.0
	var half := 24.0
	var hit: Dictionary = {}
	var started := false
	var entered := false
	var passed := false
	var done := false
	var root: Node3D = null
	var rails_mat: ShaderMaterial = null
	var train: Node3D = null
	var cars: Array = []          # [{node: MeshInstance3D, mat: ShaderMaterial, len: float, back: float}]
	var length := 0.0             # the whole train, nose to tail, in metres
	var chimney: Node3D = null
	var lamp: MeshInstance3D = null
	var beam: MeshInstance3D = null
	var edge: MeshInstance3D = null
	var edge_s := -9.0
	var smoke_t := 0.0
	var spark_t := 0.0
	var dust_t := 0.0
	var wisp_t := 0.0
	var seed_v := 0.0

var game: Node = null
var phase := IDLE
## seconds until the next rumble (-1: not started: `first` once the item is held)
var clock := -1.0
## seconds into the rumble
var t := 0.0
var runs: Array = []
var _rng: RandomNumberGenerator = Dice.rng_for("iron_horse")
var _looks := true
var _scene: PackedScene = null
var _edge_glow: MeshInstance3D = null
## the rumble's far headlight beam, shining up the line towards the hero as he turns
var _edge_beam: MeshInstance3D = null
var _pop_t := 0.0
# for the tests, the captures and the analytics
var rumbles := 0
var whistles := 0
var trains := 0
var hits := 0
## the last train's strikes: [{i, amount, big, dir, force}]
var hit_log: Array = []


## The item's params.train number `key` (DEFAULTS when it names none).
static func param(key: String, fallback: float = INF) -> float:
	var d: PassiveDef = Registry.passive(ID)
	var p = d.params.get("train", {}) if d else {}
	var def_v: float = float(DEFAULTS.get(key, 0.0)) if fallback == INF else fallback
	return float((p as Dictionary).get(key, def_v)) if p is Dictionary else def_v


## Whether the hero holds the Iron Horse.
static func active() -> bool:
	return Run.passives.has(ID)


## Seconds between two trains now: the item's train_every stat (20 Legendary, 15 Evolved).
static func every() -> float:
	return maxf(Run.player_sheet.get_stat("train_every", param("every")), 1.0)


## Whether a second train crosses the first (Evolved: train_cross).
static func crossing() -> bool:
	return Run.player_sheet.get_stat("train_cross", 0.0) >= 0.5


## What a creature the train runs over takes: `share` of its max HP (`big_share` for an Elite or a boss) + the flat part.
static func hit_amount(max_hp: float, big: bool) -> float:
	return max_hp * (param("big_share") if big else param("share")) + flat_damage()


## The might-scaled part of a hit: `damage` x attack damage (x the stage multiplier when `stage_scaled`).
static func flat_damage() -> float:
	var d := param("damage") * Run.player_sheet.get_stat("might", 1.0)
	if param("stage_scaled") > 0.5:
		d *= Run.stage_mult()
	return d


## Whether the point `p` lies on the rails of the line through `origin` along `dir` between `s0` and `s1` metres, within
## `width` m of it (`pad` more for a body's radius).
static func on_rails(p: Vector3, origin: Vector3, dir: Vector3, s0: float, s1: float, width: float, pad: float = 0.0) -> bool:
	var rel := Vector3(p.x - origin.x, 0.0, p.z - origin.z)
	var along := rel.dot(dir)
	if along < s0 or along > s1:
		return false
	var side := Vector3(-dir.z, 0.0, dir.x)
	return absf(rel.dot(side)) <= width + pad


## Pass 119: the train (the model's first load and its three ghost materials), a stretch of rails and both lights drawn
## once under `parent` (Warmup's pit under the spawn beam), so the first whistle never stalls on a load or a compile.
static func warm(parent: Node3D) -> void:
	var b := IronHorse.new()   # a builder only, never in the tree
	if ResourceLoader.exists(TRAIN_SCENE):
		var tr := (load(TRAIN_SCENE) as PackedScene).instantiate() as Node3D
		for nm: String in CARS:
			var mi := tr.get_node_or_null(nm) as MeshInstance3D
			if mi:
				var mat := ShaderMaterial.new()
				mat.shader = GHOST_SHADER
				mat.render_priority = 1
				mi.material_override = mat
		parent.add_child(tr)
	var r := TrainRun.new()
	r.half = 2.0
	var rails := MeshInstance3D.new()
	rails.mesh = b._rails_mesh(r)
	var rm := ShaderMaterial.new()
	rm.shader = RAIL_SHADER
	rm.set_shader_parameter("build_s", 100.0)
	rails.material_override = rm
	parent.add_child(rails)
	parent.add_child(b._glow_quad(1.0))
	parent.add_child(b._beam_node(GHOST))
	b.free()


func setup(p_game: Node) -> void:
	game = p_game
	Dice.seed_rng(_rng, "iron_horse")
	_looks = not Run.sim_mode
	if _looks and ResourceLoader.exists(TRAIN_SCENE):
		_scene = load(TRAIN_SCENE)


## Starts a cycle at once (the captures, game/tools/_p119_LEGEND_A_shots.gd; the tests).
func trigger() -> void:
	if phase == IDLE:
		_start_rumble()


func tick(delta: float) -> void:
	if active():
		if clock < 0.0 and phase == IDLE:
			clock = param("first")
		var hero = game.player if game else null
		var up: bool = hero != null and not bool(hero.get("dead"))
		if phase == IDLE:
			if up:
				clock -= delta
				if clock <= 0.0:
					_start_rumble()
		elif phase == RUMBLE:
			# the next cycle's clock runs from this one's start: a whistle every `every` s
			clock -= delta
			t += delta
			_tick_rumble(delta)
			if t >= param("rumble"):
				_whistle()
	else:
		clock = -1.0
		if phase == RUMBLE:
			_end_rumble()
	if runs.is_empty():
		return
	for r: TrainRun in runs:
		_tick_run(r, delta)
	var left: Array = []
	for r: TrainRun in runs:
		if r.done:
			_free_run(r)
		else:
			left.append(r)
	runs = left


## Whether a cycle is playing (the rumble or a train on its rails).
func busy() -> bool:
	return phase != IDLE or not runs.is_empty()


# ---------------------------------------------------------------- 1. the rumble

func _start_rumble() -> void:
	phase = RUMBLE
	t = 0.0
	clock = every()
	rumbles += 1
	_pop_t = 0.0
	Audio.play("it_train_rumble", _hero_pos())
	if _looks:
		_edge_glow = _glow_quad(2.2)
		add_child(_edge_glow)
		_glow_strength(_edge_glow, 0.0)
		_edge_beam = _beam_node(GHOST)
		add_child(_edge_beam)
		_glow_strength(_edge_beam, 0.0)


func _tick_rumble(delta: float) -> void:
	var k := clampf(t / maxf(param("rumble"), 0.01), 0.0, 1.0)
	_shake(lerpf(0.06, 0.4, k))
	if not _looks:
		return
	var here := _hero_pos()
	var fwd := _hero_forward()
	# the sand trembles: small dust hops round the hero, more of them as it grows
	_pop_t -= delta
	if _pop_t <= 0.0:
		_pop_t = lerpf(0.1, 0.03, k)
		var a := randf() * TAU
		var at := here + Vector3(cos(a), 0.0, sin(a)) * randf_range(1.2, 7.5)
		at.y = _h(at.x, at.z) + 0.05
		_fx("sand", [at, randf_range(0.45, 0.75) * (0.6 + k)])
		# and the sand shivers: a faint ripple where it hops
		var tg = game.telegraphs if game else null
		if tg and tg.has_method("flash_ring") and randf() < 0.5:
			tg.flash_ring(at, randf_range(0.5, 0.9), Color(0.45, 0.33, 0.2), 0.35)
	# the headlight far down the line behind him, at the screen's edge, as he turns
	if _edge_glow:
		var s := _edge_s(here, fwd)
		var p := here + fwd * s
		p.y = _h(p.x, p.z) + 1.6 * param("scale")
		_edge_glow.global_position = p
		_glow_strength(_edge_glow, k * k * 1.2 * (0.85 + 0.15 * sin(t * 30.0)))
		# its beam up the line to his feet: where the rails will lie if he keeps facing this way
		if _edge_beam:
			var foot := Vector3(p.x, _h(p.x, p.z) + 0.25, p.z)
			var to := Vector3(here.x, _h(here.x, here.z) + 0.25, here.z)
			var d := to - foot
			var side := Vector3(-fwd.z, 0.0, fwd.x)
			_edge_beam.global_transform = Transform3D(Basis(side * 3.2, Vector3.UP, d * 1.6), foot)
			_glow_strength(_edge_beam, k * 2.4)


func _end_rumble() -> void:
	phase = IDLE
	if _edge_glow:
		_edge_glow.queue_free()
		_edge_glow = null
	if _edge_beam:
		_edge_beam.queue_free()
		_edge_beam = null


# ---------------------------------------------------------------- 2. the whistle: the line locks and the rails rise

func _whistle() -> void:
	phase = IDLE
	whistles += 1
	hit_log.clear()
	var here := _hero_pos()
	var fwd := _hero_forward()
	var first := _new_run(here, fwd, 0.0)
	runs.append(first)
	if crossing():
		runs.append(_new_run(here, Vector3(-fwd.z, 0.0, fwd.x), -param("cross_delay")))
	# the rumble's glimmer becomes the first train's own
	if _edge_glow:
		first.edge = _edge_glow
		_edge_glow = null
	if _edge_beam:
		_edge_beam.queue_free()
		_edge_beam = null
	Audio.play("it_train_whistle", here)


func _new_run(at: Vector3, dir: Vector3, u0: float) -> TrainRun:
	var r := TrainRun.new()
	r.origin = Vector3(at.x, _h(at.x, at.z), at.z)
	r.dir = Vector3(dir.x, 0.0, dir.z).normalized()
	r.side = Vector3(-r.dir.z, 0.0, r.dir.x)
	r.u = u0
	r.half = param("half_length") * _zoom()
	r.seed_v = randf() * 10.0
	r.length = _train_length()
	return r


## The whole train's length (the cars' lengths and their gaps, x scale): the model's (tools/blender_iron_horse.py prints
## them), fixed here so the rules never wait on the model.
const CAR_LENGTHS := [9.74, 5.6, 9.0]


func _train_length() -> float:
	var sc := param("scale")
	var lens := CAR_LENGTHS
	return (float(lens[0]) + float(lens[1]) + float(lens[2])) * sc + param("car_gap") * 2.0


func _start_run(r: TrainRun) -> void:
	r.started = true
	trains += 1
	if not _looks:
		return
	r.root = Node3D.new()
	r.root.name = "TrainRun%d" % trains
	add_child(r.root)
	r.root.global_position = r.origin
	# the rails, laid along the line
	var rails := MeshInstance3D.new()
	rails.name = "Rails"
	rails.mesh = _rails_mesh(r)
	rails.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.rails_mat = ShaderMaterial.new()
	r.rails_mat.shader = RAIL_SHADER
	r.rails_mat.set_shader_parameter("build_s", 0.0)
	r.rails_mat.set_shader_parameter("gone_s", -1000.0)
	rails.material_override = r.rails_mat
	rails.custom_aabb = AABB(Vector3(-r.half - 4.0, -6.0, -r.half - 4.0), Vector3(r.half * 2.0 + 8.0, 12.0, r.half * 2.0 + 8.0))
	r.root.add_child(rails)
	# the strip of light under them
	var tg = game.telegraphs if game else null
	if tg and tg.has_method("line"):
		tg.line(r.origin - r.dir * r.half, r.dir, r.half * 2.0, param("warn") + 0.3, STRIP, 0.4)
	# its own glimmer at the edge (the crossing train's; the first took the rumble's)
	if r.edge == null:
		r.edge = _glow_quad(2.2)
		add_child(r.edge)
	r.edge_s = _edge_s(r.origin, r.dir)
	var ep := r.origin + r.dir * r.edge_s
	ep.y = _h(ep.x, ep.z) + 1.6 * param("scale")
	r.edge.global_position = ep
	# the train, waiting out of sight
	if _scene:
		r.train = _scene.instantiate() as Node3D
		r.train.name = "Train"
		add_child(r.train)
		r.train.visible = false
		var sc := param("scale")
		var back := 0.0
		for nm: String in CARS:
			var mi := r.train.get_node_or_null(nm) as MeshInstance3D
			if mi == null:
				continue
			var mat := ShaderMaterial.new()
			mat.shader = GHOST_SHADER
			mat.set_shader_parameter("seed", r.seed_v + float(r.cars.size()))
			# after the rails, whatever their distance
			mat.render_priority = 1
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var ab: AABB = mi.mesh.get_aabb() if mi.mesh else AABB(Vector3(-1, 0, -4), Vector3(2, 3, 8))
			var ln := ab.size.z * sc
			# each car a little fainter than the one ahead: the train trails off into the past
			r.cars.append({"node": mi, "mat": mat, "len": ln, "back": back + ln * 0.5, "mid": (ab.position.z + ab.size.z * 0.5) * sc,
				"ghost": 1.0 - 0.12 * float(r.cars.size())})
			back += ln + param("car_gap")
			if nm == "Engine":
				r.chimney = mi.get_node_or_null("Chimney") as Node3D
				var lamp_at := mi.get_node_or_null("Lamp") as Node3D
				r.lamp = _glow_quad(1.6 / sc)
				(lamp_at if lamp_at else mi).add_child(r.lamp)
				r.beam = _beam_quad(sc)
				(lamp_at if lamp_at else mi).add_child(r.beam)
		# (the rules keep _train_length's number, the same with or without the model: a replay or the run sim agrees)


# ---------------------------------------------------------------- 3. the charge, 4. the wake

func _tick_run(r: TrainRun, delta: float) -> void:
	r.u += delta
	if r.u < 0.0:
		return
	if not r.started:
		_start_run(r)
	var warn := param("warn")
	var speed := maxf(param("speed"), 1.0)
	var s_nose := (r.u - warn) * speed
	var s_tail := s_nose - r.length
	# the creatures it runs over, from the moment its nose is on the rails to the moment its tail leaves them
	if s_nose > -r.half and s_tail < r.half:
		_strike_along(r, maxf(s_tail, -r.half), minf(s_nose, r.half))
	if not r.entered and s_nose > -r.half:
		r.entered = true
		Audio.play("it_train_pass", r.origin)
	if not r.passed and s_nose >= 0.0:
		r.passed = true
		_shake(0.9)
	# its looks
	if _looks:
		_tick_run_looks(r, delta, s_nose, s_tail, speed)
	# done once the tail is past the far end and the rails behind it have gone
	if s_tail > r.half + 3.0 + param("speed") * 0.5:
		r.done = true


func _strike_along(r: TrainRun, s0: float, s1: float) -> void:
	var ens = game.enemies if game else null
	if ens == null:
		return
	var w := param("width")
	var step := maxf(w, 1.0)
	var s := s0
	while true:
		var c := r.origin + r.dir * s
		for i: int in ens.indices_touching(c, w, 0.35):
			if r.hit.has(i) or not ens.is_alive(i):
				continue
			var p: Vector3 = ens.position_of(i)
			if not on_rails(p, r.origin, r.dir, s0 - 0.6, s1 + 0.6, w, float(ens.radius[i]) * 0.5):
				continue
			r.hit[i] = true
			_strike(ens, i, r, (p - r.origin).dot(r.side))
		if s >= s1:
			break
		s = minf(s + step, s1)


func _strike(ens, i: int, r: TrainRun, across: float) -> void:
	var big: bool = ens.is_big_game(i)
	var amt := hit_amount(float(ens.max_hp[i]), big)
	var side_sign := signf(across) if absf(across) > 0.05 else (1.0 if _rng.randf() < 0.5 else -1.0)
	var kdir := (r.side * side_sign + r.dir * param("forward")).normalized()
	var force := param("knock") * (param("big_knock") if big else 1.0)
	var at: Vector3 = ens.position_of(i)
	ens.damage(i, amt, SOURCE, kdir, force, false, false, EnemyManager.HIT_BLAST | EnemyManager.HIT_NO_CRIT)
	hits += 1
	hit_log.append({"i": i, "amount": amt, "big": big, "dir": kdir, "force": force})
	if _looks:
		_fx("hit", [at + Vector3(0, 0.7, 0), GHOST_PALE])


func _tick_run_looks(r: TrainRun, delta: float, s_nose: float, s_tail: float, speed: float) -> void:
	var assemble := maxf(param("assemble"), 0.05)
	var warn := param("warn")
	var full := r.half * 2.0
	# the rails: laid from the back end to the front in `assemble` s, glowing as the train comes, gone behind its tail
	if r.rails_mat:
		var built := clampf(r.u / assemble, 0.0, 1.0)
		r.rails_mat.set_shader_parameter("build_s", built * (full + 6.0))
		r.rails_mat.set_shader_parameter("glow", clampf(r.u / maxf(warn, 0.05), 0.0, 1.0))
		r.rails_mat.set_shader_parameter("gone_s", s_tail + r.half - 2.0 if s_tail > -r.half else -1000.0)
		# dust lifting where the wave lays them
		if built < 1.0:
			r.dust_t -= delta
			if r.dust_t <= 0.0:
				r.dust_t = 0.03
				var sb := -r.half + built * full
				var p := r.origin + r.dir * sb + r.side * randf_range(-1.2, 1.2)
				p.y = _h(p.x, p.z) + 0.1
				_fx("smoke_puff", [p, Vector3(0, randf_range(0.6, 1.2), 0) + r.side * randf_range(-0.5, 0.5), randf_range(0.5, 0.8), 0.4, 1.3, Color(0.86, 0.74, 0.55, 0.45)])
	# the glimmer at the edge: it grows until the train comes into sight, then the lamp has the light
	if r.edge:
		var into := s_nose - r.edge_s
		var k := clampf(r.u / maxf(warn - 0.15, 0.1), 0.0, 1.0)
		_glow_strength(r.edge, (1.2 + 1.3 * k) * clampf(1.0 - into / 3.0, 0.0, 1.0))
		if into > 3.0:
			r.edge.queue_free()
			r.edge = null
	if r.train == null:
		return
	var on := s_nose > -r.half - 2.0 and s_tail < r.half + 6.0
	r.train.visible = on
	if not on:
		return
	var sc := param("scale")
	var travel := (s_nose + r.half) / maxf(sc, 0.01)
	for c: Dictionary in r.cars:
		var sc_mid := s_nose - float(c["back"])
		var ln := float(c["len"])
		var mi: MeshInstance3D = c["node"]
		mi.global_transform = _car_xform(r, sc_mid, ln, sc, float(c["mid"]))
		var mat: ShaderMaterial = c["mat"]
		mat.set_shader_parameter("travel", travel)
		# it rises out of nothing past the back end and fades away past the front
		var fin := clampf((sc_mid + r.half + ln * 0.5) / 4.0, 0.0, 1.0)
		var fout := clampf((r.half + 2.0 - sc_mid) / 5.0, 0.0, 1.0)
		mat.set_shader_parameter("fade", minf(fin, fout) * float(c["ghost"]))
	if r.lamp:
		_glow_strength(r.lamp, 1.6 * clampf((r.half + 2.0 - s_nose) / 5.0, 0.0, 1.0))
	if r.beam:
		var bm: ShaderMaterial = r.beam.material_override
		bm.set_shader_parameter("strength", 1.0 * clampf((r.half - s_nose) / 5.0, 0.0, 1.0))
	# the wake: ghost smoke from the stack, sparks at the wheels, sand thrown up behind, wisps where the rails go
	if s_nose > -r.half and s_nose < r.half + 3.0 and r.chimney:
		r.smoke_t -= delta
		while r.smoke_t <= 0.0:
			r.smoke_t += 0.03
			var cp := r.chimney.global_position + Vector3(randf_range(-0.2, 0.2), 0.2, randf_range(-0.2, 0.2))
			_fx("smoke_puff", [cp, -r.dir * speed * randf_range(0.1, 0.25) + Vector3(0, randf_range(2.0, 3.5), 0) + r.side * randf_range(-0.6, 0.6),
				randf_range(1.0, 1.5), 0.6 * sc, randf_range(2.0, 3.0) * sc, SMOKE])
	if s_nose > -r.half and s_tail < r.half:
		r.spark_t -= delta
		if r.spark_t <= 0.0:
			r.spark_t = 0.07
			var wp := r.origin + r.dir * (s_nose - randf_range(1.0, r.length * 0.4)) + r.side * (0.75 * sc * (1.0 if randf() < 0.5 else -1.0))
			wp.y = _h(wp.x, wp.z) + 0.15
			_fx("hit", [wp, Color(0.7, 1.0, 0.92)])
		r.dust_t -= delta
		if r.dust_t <= 0.0:
			r.dust_t = 0.045
			var tp := r.origin + r.dir * maxf(s_tail, -r.half)
			tp.y = _h(tp.x, tp.z)
			_fx("charge_dust", [tp, -r.dir, 2.6 * sc, 0.9])
	if s_tail > -r.half and s_tail < r.half + 2.0:
		r.wisp_t -= delta
		if r.wisp_t <= 0.0:
			r.wisp_t = 0.06
			var gp := r.origin + r.dir * (s_tail - 2.0) + r.side * randf_range(-0.9, 0.9) * sc
			gp.y = _h(gp.x, gp.z) + 0.2
			_fx("smoke_puff", [gp, Vector3(0, randf_range(0.8, 1.5), 0), randf_range(0.6, 0.9), 0.35, 1.0, Color(0.7, 1.0, 0.9, 0.35)])


## A car's place: its middle `s_mid` m along the line, riding the sand under its two ends (its pitch), facing along.
func _car_xform(r: TrainRun, s_mid: float, ln: float, sc: float, mid_z: float) -> Transform3D:
	var c := r.origin + r.dir * s_mid
	var f := c + r.dir * ln * 0.5
	var b := c - r.dir * ln * 0.5
	var hf := _h(f.x, f.z)
	var hb := _h(b.x, b.z)
	var fwd := (r.dir * ln + Vector3(0.0, hf - hb, 0.0)).normalized()
	var x := Vector3.UP.cross(fwd).normalized()
	var y := fwd.cross(x).normalized()
	var basis := Basis(x * sc, y * sc, fwd * sc)
	var at := Vector3(c.x, (hf + hb) * 0.5 + 0.02, c.z) - fwd * mid_z
	return Transform3D(basis, at)


func _free_run(r: TrainRun) -> void:
	if r.edge and is_instance_valid(r.edge):
		r.edge.queue_free()
	if r.train and is_instance_valid(r.train):
		r.train.queue_free()
	if r.root and is_instance_valid(r.root):
		r.root.queue_free()


# ---------------------------------------------------------------- the rails' mesh

## Sleepers and two rails along the line from its back end (-half) to its front (+half), each point on the sand under
## it, in the run's own space (its root stands at the origin). UV.x: metres from the back end; UV.y: 0 sleeper, 1 rail.
func _rails_mesh(r: TrainRun) -> ArrayMesh:
	var sc := param("scale")
	var gauge := 0.75 * sc
	var rail_w := 0.1 * sc
	var rail_h := 0.14 * sc
	var sl_half := 1.25 * sc
	var sl_d := 0.13 * sc
	var sl_h := 0.08 * sc
	var gap := 0.78 * sc
	var step := 0.6
	var full := r.half * 2.0
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var y0 := r.origin.y
	# the sleepers
	var n_sl := int(full / gap)
	for k in range(n_sl + 1):
		var s := -r.half + k * gap
		var c := r.origin + r.dir * s
		var hl := _h(c.x - r.side.x * sl_half, c.z - r.side.z * sl_half) - y0
		var hr := _h(c.x + r.side.x * sl_half, c.z + r.side.z * sl_half) - y0
		var top := sl_h + 0.02
		var u := s + r.half
		var a0 := r.dir * (s - sl_d) - r.side * sl_half
		var a1 := r.dir * (s + sl_d) - r.side * sl_half
		var b0 := r.dir * (s - sl_d) + r.side * sl_half
		var b1 := r.dir * (s + sl_d) + r.side * sl_half
		_quad(v, uv, idx, a0 + Vector3(0, hl + top, 0), a1 + Vector3(0, hl + top, 0), b1 + Vector3(0, hr + top, 0), b0 + Vector3(0, hr + top, 0), u, 0.0)
		_quad(v, uv, idx, a0 + Vector3(0, hl, 0), b0 + Vector3(0, hr, 0), b0 + Vector3(0, hr + top, 0), a0 + Vector3(0, hl + top, 0), u, 0.0)
		_quad(v, uv, idx, a1 + Vector3(0, hl, 0), b1 + Vector3(0, hr, 0), b1 + Vector3(0, hr + top, 0), a1 + Vector3(0, hl + top, 0), u, 0.0)
	# the rails: a top and two sides a segment
	var n_seg := int(ceil(full / step))
	for sgn in [-1.0, 1.0]:
		var off := r.side * gauge * float(sgn)
		var prev_h := 0.0
		for k in range(n_seg + 1):
			var s := -r.half + minf(k * step, full)
			var c := r.origin + r.dir * s + off
			var h := _h(c.x, c.z) - y0 + sl_h + 0.02
			if k > 0:
				var s0 := s - step
				var p0 := r.dir * s0 + off
				var p1 := r.dir * s + off
				var w := r.side * rail_w * 0.5
				var u0 := s0 + r.half
				var u1 := s + r.half
				_quad2(v, uv, idx, p0 - w + Vector3(0, prev_h + rail_h, 0), p1 - w + Vector3(0, h + rail_h, 0), p1 + w + Vector3(0, h + rail_h, 0), p0 + w + Vector3(0, prev_h + rail_h, 0), u0, u1)
				_quad2(v, uv, idx, p0 - w + Vector3(0, prev_h, 0), p1 - w + Vector3(0, h, 0), p1 - w + Vector3(0, h + rail_h, 0), p0 - w + Vector3(0, prev_h + rail_h, 0), u0, u1)
				_quad2(v, uv, idx, p0 + w + Vector3(0, prev_h, 0), p1 + w + Vector3(0, h, 0), p1 + w + Vector3(0, h + rail_h, 0), p0 + w + Vector3(0, prev_h + rail_h, 0), u0, u1)
			prev_h = h
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## A quad of one part (a sleeper: its metres along `u`, UV.y 0); both windings are drawn (the material culls nothing).
func _quad(v: PackedVector3Array, uv: PackedVector2Array, idx: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, u: float, part: float) -> void:
	var o := v.size()
	v.append_array([a, b, c, d])
	uv.append_array([Vector2(u, part), Vector2(u, part), Vector2(u, part), Vector2(u, part)])
	idx.append_array([o, o + 1, o + 2, o, o + 2, o + 3])


## A rail's quad from `u0` to `u1` metres (UV.y 1).
func _quad2(v: PackedVector3Array, uv: PackedVector2Array, idx: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, u0: float, u1: float) -> void:
	var o := v.size()
	v.append_array([a, b, c, d])
	uv.append_array([Vector2(u0, 1.0), Vector2(u1, 1.0), Vector2(u1, 1.0), Vector2(u0, 1.0)])
	idx.append_array([o, o + 1, o + 2, o, o + 2, o + 3])


# ---------------------------------------------------------------- the lights

## A round additive glow turned to the camera, `size` m across.
func _glow_quad(size: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = GLOW_SHADER
	m.set_shader_parameter("color", GHOST_PALE)
	m.set_shader_parameter("beam", 0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = size * 2.0
	return mi


## The headlight's beam on the sand: a quad laid ahead of the lamp along the rails (in the car's space: +Z ahead).
func _beam_quad(sc: float) -> MeshInstance3D:
	var mi := _beam_node(GHOST)
	# in the lamp's space (the engine's, scaled by sc): from just ahead of the lamp's foot, 3 m wide and 12 m long on the
	# ground (the lamp stands 2.35 m up the engine)
	mi.transform = Transform3D(Basis(Vector3(3.0 / sc, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 12.0 / sc)), Vector3(0.0, -2.25, 0.2))
	return mi


## A beam of light on the ground: the unit strip (0..1 along its +Z, -0.5..0.5 across its X, flat) in the glow shader's
## beam mode, brightest at its start; its node's basis gives it its width, its length and its way.
func _beam_node(col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var v := PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 0, 1), Vector3(-0.5, 0, 1)])
	var uv := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mi.mesh = m
	var mat := ShaderMaterial.new()
	mat.shader = BEAM_SHADER
	mat.set_shader_parameter("color", col)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 20.0
	return mi


func _glow_strength(mi: MeshInstance3D, k: float) -> void:
	if mi == null:
		return
	var m := mi.material_override as ShaderMaterial
	if m:
		m.set_shader_parameter("strength", maxf(k, 0.0))
	mi.visible = k > 0.01


# ---------------------------------------------------------------- the world it reads

func _hero_pos() -> Vector3:
	var hero = game.player if game else null
	return (hero as Node3D).global_position if hero is Node3D else Vector3.ZERO


func _hero_forward() -> Vector3:
	var hero = game.player if game else null
	var f: Vector3 = hero.call("forward") if hero and hero.has_method("forward") else Vector3.FORWARD
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD


func _h(x: float, z: float) -> float:
	var m = game.map if game else null
	return float(m.height_at(x, z)) if m and m.has_method("height_at") else 0.0


func _zoom() -> float:
	var cam = game.camera if game else null
	return clampf(float(cam.call("zoom")), 1.0, 2.2) if cam and cam.has_method("zoom") else 1.0


## How far behind `at` along -`fwd` the screen's edge lies (negative metres): the farthest point still on the screen,
## pulled a metre in; -9 m without a camera.
func _edge_s(at: Vector3, fwd: Vector3) -> float:
	var cam = game.camera if game else null
	if cam == null or not cam.has_method("on_screen"):
		return -9.0
	var s := -1.0
	while s > -60.0:
		var p := at - fwd * (absf(s) + 1.0)
		p.y = _h(p.x, p.z) + 1.0
		if not bool(cam.call("on_screen", p, -24.0)):
			break
		s -= 1.0
	return s


func _shake(k: float) -> void:
	var cam = game.camera if game else null
	if cam and cam.has_method("shake"):
		cam.call("shake", k)


## An Fx call by name, when the game has its Fx (tools and tests may not).
func _fx(fn: String, args: Array) -> void:
	var fx = game.fx if game else null
	if fx and fx.has_method(fn):
		fx.callv(fn, args)
