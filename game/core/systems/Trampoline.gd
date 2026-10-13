## Pass 70 (lane TRAMP): Hang Time's trampoline, the perk whose `special` is "trampoline" (content/perks/hang_time,
## Fadeaway's; it replaces pass 67's Timeout). A reusable primitive: any perk carrying the special gets one, tuned by its
## params (Run.perk_param("trampoline", key, default)). After `first` s, then `every` s after the last one folded away, a
## 3D trampoline (art/props/trampoline.glb: Mat, Rim, Legs) drops out of the sky `side` m to his left or right (the side
## with fewer creatures, off the rocks and the water) and stands `lifetime` s, one at a time. Walking onto it from
## outside (his centre crossing `radius` m of its middle; standing there when it landed does not count, nor does being
## in the air) throws him: Player.trampoline_launch, up `launch_height` m and `launch_distance` m along the way he was
## walking (where he faces when he stood still), `air_time` s in the air, the stick steering at `air_control` of his
## walking speed, untouchable up there. The mat dips and wobbles; after `uses` jumps (one) it folds away. His landing
## is a thud, a dust ring and a shake. Game._tick_trampoline makes this node the first time a trampoline perk is held.
class_name Trampoline
extends Node3D

const MODEL_PATH := "res://art/props/trampoline.glb"
const TOP := 0.55            # the mat's height in the model
const DROP_H := 7.0          # it falls from this high
const DROP_TIME := 0.45
const FOLD_TIME := 0.55
const FOLD_AFTER := 0.45     # seconds after the last jump before it folds (the mat still wobbling)
const BLINK := 3.0           # the last seconds of its lifetime it blinks
const SPRING_K := 260.0      # the mat's spring (stiffness, damping): a dip that rebounds past flat and settles
const SPRING_DAMP := 6.5
const BUMP_K := 380.0        # the whole frame's bounce as it lands
const BUMP_DAMP := 11.0
const SHADOW_R := 1.6
const BLUE := Color(0.24, 0.5, 1.0)
const CREATURE_CLEAR := 2.5  # a side is crowded by the creatures within this of its spot

enum { IDLE, DROPPING, STANDING, FOLDING }

var game: Node = null
var phase := IDLE
var clock := -1.0            # seconds until the next drop (-1: not started yet)
var t := 0.0                 # seconds into the drop or the fold
var age := 0.0               # seconds it has stood
var at := Vector3.ZERO       # where it stands, on the ground
var model: Node3D = null
var uses_left := 0
var dip := 0.0               # the mat's bow now (1 = the model's full "Dip"; below 0 it bulges up)
var _dip_v := 0.0
var _bump := 0.0             # the frame's squash as it lands
var _bump_v := 0.0
var _since_jump := -1.0
var _was_inside := true
var _flying := false         # a flight it launched has not landed yet
var _mat: MeshInstance3D = null
var _rim: Node3D = null
var _mat_y := 0.0           # the parts' rest heights in the model (0 in the GLB; the stand-in's mat sits at TOP)
var _rim_y := 0.0
var _legs: Node3D = null
var _dip_idx := -1
var _shadow: MeshInstance3D = null
# for the tests and the captures
var drops := 0
var launches := 0
var folds := 0
var landings := 0


## Whether the hero holds a perk whose special is "trampoline".
static func active() -> bool:
	for pk in Run.perks:
		var def: PerkDef = Registry.perk(str(pk))
		if def and def.special == "trampoline":
			return true
	return false


# the perk's numbers (Run.perk_param by the mechanism; the Level Editor's vocab reads these defaults)
static func every() -> float:
	return Run.perk_param("trampoline", "every", 20.0)


static func first() -> float:
	return Run.perk_param("trampoline", "first", 10.0)


static func side() -> float:
	return Run.perk_param("trampoline", "side", 3.5)


static func lifetime() -> float:
	return Run.perk_param("trampoline", "lifetime", 30.0)


static func radius() -> float:
	return Run.perk_param("trampoline", "radius", 1.1)


static func uses() -> int:
	return maxi(int(Run.perk_param("trampoline", "uses", 1.0)), 1)


static func launch_height() -> float:
	return Run.perk_param("trampoline", "launch_height", 4.0)


static func launch_distance() -> float:
	return Run.perk_param("trampoline", "launch_distance", 8.0)


static func air_time() -> float:
	return Run.perk_param("trampoline", "air_time", 1.1)


static func air_control() -> float:
	return Run.perk_param("trampoline", "air_control", 0.35)


func setup(p_game: Node) -> void:
	game = p_game
	var pl = _player()
	if pl and pl.has_signal("air_landed"):
		pl.connect("air_landed", _on_landed)


func _player() -> Node3D:
	return game.get("player") as Node3D if game else null


func _ground(p: Vector3) -> Vector3:
	var m = game.get("map") if game else null
	if m:
		return Vector3(p.x, m.height_at(p.x, p.z), p.z)
	return p


func tick(delta: float) -> void:
	match phase:
		IDLE:
			if not active():
				clock = -1.0
				return
			if clock < 0.0:
				clock = first()
			clock -= delta
			if clock <= 0.0:
				drop_now()
		DROPPING:
			_tick_drop(delta)
		STANDING:
			_tick_standing(delta)
		FOLDING:
			_tick_fold(delta)
	_tick_springs(delta)


## Where it lands (pass 70): `side` m to his left or right, square to the way he faces (ahead he would run onto it by
## accident, behind lies the crowd), on the side with fewer creatures within CREATURE_CLEAR of the spot, never on a rock
## or in the water when the other side is clear (a toss when even), inside the arena, on the ground.
func pick_spot(here: Vector3, facing_dir: Vector3, dist: float) -> Vector3:
	var f := Vector3(facing_dir.x, 0.0, facing_dir.z)
	if f.length_squared() < 0.0001:
		f = Vector3.FORWARD
	var s := Vector3(-f.z, 0.0, f.x).normalized() * dist
	var m = game.get("map") if game else null
	var em = game.get("enemies") if game else null
	var best := here + s
	var best_score := INF
	var first_side := randf() < 0.5
	for k in range(2):
		var p: Vector3 = here + (s if (k == 0) == first_side else -s)
		if m and m.has_method("clamp_to_arena"):
			p = m.clamp_to_arena(p)
		var score := 0.0
		if em:
			score += float((em as EnemyManager).indices_in_radius(p, CREATURE_CLEAR).size())
			if Decoy._on_rock((em as EnemyManager).obstacles, p):
				score += 100.0
		if m and m.has_method("in_water") and bool(m.call("in_water", p)):
			score += 50.0
		if score < best_score:
			best_score = score
			best = p
	return _ground(best)


## Drops one now (the clock's moment; the arena and the tests call it directly). Nothing while one stands.
func drop_now() -> void:
	var pl := _player()
	if pl == null or bool(pl.get("dead")):
		clock = 1.0
		return
	if phase == DROPPING or phase == STANDING:
		return
	at = pick_spot(pl.global_position, pl.call("forward"), side())
	t = 0.0
	age = 0.0
	phase = DROPPING
	drops += 1
	clock = every()
	uses_left = uses()
	_since_jump = -1.0
	_was_inside = true
	_show_model()
	_place(at + Vector3(0.0, DROP_H, 0.0))
	var tg = game.get("telegraphs") if game else null
	if tg:
		# where it will come down: a blue ring on the sand for the length of the fall
		tg.ring(at, 1.3, DROP_TIME, BLUE)


func _tick_drop(delta: float) -> void:
	t += delta
	var k := clampf(t / DROP_TIME, 0.0, 1.0)
	# falling: slow at the top, fast at the bottom
	_place(at + Vector3(0.0, DROP_H * (1.0 - k * k), 0.0))
	if model:
		model.rotation.y = (1.0 - k) * 0.9
	if k >= 1.0:
		_arrive()


func _arrive() -> void:
	phase = STANDING
	age = 0.0
	_place(at)
	if model:
		model.rotation.y = 0.0
	_bump_v = -6.0
	dip = 0.35
	_dip_v = 0.0
	# standing where it landed is not walking onto it: he has to step off and come back
	_was_inside = _inside()
	var fx = game.get("fx") if game else null
	if fx:
		# sand kicked up round its feet (the middle is under the mat)
		for k in range(4):
			var a := TAU * (float(k) + 0.5) / 4.0
			fx.sand(at + Vector3(cos(a), 0.0, sin(a)) * 1.3, 0.7)
	var tg = game.get("telegraphs") if game else null
	if tg:
		tg.flash_ring(at, 1.8, BLUE, 0.4)
	var cam = game.get("camera") if game else null
	if cam and cam.has_method("shake"):
		cam.shake(0.25)
	Audio.play("pk_trampoline_drop", at)


## Whether the hero stands on it: on the ground (in the air does not count), alive, his centre within `radius`.
func _inside() -> bool:
	var pl := _player()
	if pl == null or bool(pl.get("dead")) or bool(pl.get("airborne")) or bool(pl.get("cinematic")):
		return false
	return Vector2(pl.global_position.x - at.x, pl.global_position.z - at.z).length() < radius()


func _tick_standing(delta: float) -> void:
	age += delta
	if not active():
		# the perk went (the arena's swap): it goes too
		fold()
		return
	var inside := _inside()
	if inside and not _was_inside and uses_left > 0:
		_launch()
	_was_inside = inside
	if _since_jump >= 0.0:
		_since_jump += delta
		if uses_left <= 0 and _since_jump >= FOLD_AFTER:
			fold()
			return
	var life := lifetime()
	if age >= life:
		fold()
		return
	if model:
		# the last seconds it blinks, faster as it goes
		var left := life - age
		model.visible = left > BLINK or int(left * (6.0 if left > 1.0 else 12.0)) % 2 == 0


func _launch() -> void:
	var pl := _player()
	if pl == null or not pl.has_method("trampoline_launch"):
		return
	# the way he was walking; standing still (pushed in, say), the way he faces
	var v: Vector3 = pl.get("velocity")
	var dir := Vector3(v.x, 0.0, v.z)
	if dir.length_squared() < 0.25:
		dir = pl.call("forward")
	if not bool(pl.call("trampoline_launch", dir, launch_height(), launch_distance(), air_time(), air_control())):
		return
	uses_left -= 1
	launches += 1
	_since_jump = 0.0
	_flying = true
	# the mat takes his weight and throws it back: a full dip, rebounding past flat, wobbling out
	dip = 1.0
	_dip_v = 0.0
	_bump_v = -3.0
	var tg = game.get("telegraphs") if game else null
	if tg:
		tg.flash_ring(at, 1.5, BLUE, 0.3)
	var cam = game.get("camera") if game else null
	if cam and cam.has_method("shake"):
		cam.shake(0.3)
	Audio.play("pk_trampoline_boing", at)


## His landing from a flight this trampoline gave him: the dust ring, a ring on the sand, a shake.
func _on_landed(where: Vector3) -> void:
	if not _flying:
		return
	_flying = false
	landings += 1
	var fx = game.get("fx") if game else null
	if fx:
		fx.pop_dust(where, 1.3)
	var tg = game.get("telegraphs") if game else null
	if tg:
		tg.flash_ring(where, 2.2, Color(0.95, 0.85, 0.65), 0.4)
	var cam = game.get("camera") if game else null
	if cam and cam.has_method("shake"):
		cam.shake(0.45)


## Folds it away now (its lifetime ran out, it was used, the perk went): the legs fold, the frame sinks, it shrinks
## into a puff; the clock to the next one starts.
func fold() -> void:
	if phase != STANDING and phase != DROPPING:
		return
	phase = FOLDING
	t = 0.0
	clock = every()
	if model:
		model.visible = true


func _tick_fold(delta: float) -> void:
	t += delta
	var k := clampf(t / FOLD_TIME, 0.0, 1.0)
	var legs_k := clampf(k / 0.6, 0.0, 1.0)
	if _legs:
		_legs.scale = Vector3(1.0, maxf(1.0 - legs_k, 0.02), 1.0)
	var sink := -TOP * 0.85 * legs_k
	if _mat:
		_mat.position.y = _mat_y + sink
	if _rim:
		_rim.position.y = _rim_y + sink
	if model:
		var shrink := 1.0 - smoothstep(0.55, 1.0, k)
		model.scale = Vector3(shrink, maxf(shrink, 0.01), shrink)
		model.rotation.y = k * 1.4
	if k >= 1.0:
		_hide_model()
		var fx = game.get("fx") if game else null
		if fx:
			fx.pop_dust(at, 0.8)
		folds += 1
		phase = IDLE


func standing() -> bool:
	return phase == STANDING


# ---------------------------------------------------------------- the model

func _show_model() -> void:
	if model == null:
		model = _build_model()
		add_child(model)
	model.visible = true
	model.scale = Vector3.ONE
	model.rotation = Vector3.ZERO
	if _legs:
		_legs.scale = Vector3.ONE
	if _mat:
		_mat.position.y = _mat_y
	if _rim:
		_rim.position.y = _rim_y
	dip = 0.0
	_dip_v = 0.0
	_bump = 0.0
	_bump_v = 0.0
	_apply_dip()
	if _shadow:
		_shadow.visible = true


func _hide_model() -> void:
	if model:
		model.visible = false
	if _shadow:
		_shadow.visible = false


func _place(p: Vector3) -> void:
	if model:
		model.global_position = p
	if _shadow:
		# the blob stays on the sand under it, darker as it comes down
		_shadow.global_position = at + Vector3(0.0, 0.03, 0.0)
		var mat := _shadow.material_override as ShaderMaterial
		if mat:
			var h := clampf((p.y - at.y) / DROP_H, 0.0, 1.0)
			mat.set_shader_parameter("strength", 0.42 * (1.0 - 0.7 * h))


## The GLB's three parts (Mat with its "Dip" blend shape, Rim, Legs), graded like the 3D weapons under the map's light
## (WeaponBehavior.grade_materials: the sand pulls every lit mesh towards its own tone); a primitive stand-in when the
## model is missing. A blob shadow under it, its own node.
func _build_model() -> Node3D:
	var root := model_instance()
	_mat = root.find_child("Mat", true, false) as MeshInstance3D
	_rim = root.find_child("Rim", true, false) as Node3D
	_legs = root.find_child("Legs", true, false) as Node3D
	_dip_idx = _mat.find_blend_shape_by_name("Dip") if _mat and _mat.mesh else -1
	_mat_y = _mat.position.y if _mat else 0.0
	_rim_y = _rim.position.y if _rim else 0.0
	_shadow = MeshInstance3D.new()
	_shadow.name = "TrampolineShadow"
	var quad := QuadMesh.new()
	quad.size = Vector2(SHADOW_R * 2.0, SHADOW_R * 2.0)
	quad.orientation = PlaneMesh.FACE_Y
	_shadow.mesh = quad
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://core/shaders/blob_shadow.gdshader")
	sm.render_priority = EnemyManager.SHADOW_PRIORITY
	sm.set_shader_parameter("strength", 0.42)
	_shadow.material_override = sm
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)
	return root


## Under Red Canyon's warm haze the black mat came out brown and the blue pad lavender (pass 70 capture; the fog is what
## tinted the title's black-masked hero brown in pass 69, BillboardSprite.set_fogless): the mat and the pad are drawn
## without the fog and without shine, the pad glowing a little of its own blue (RIM_GLOW), so both keep the colours the
## request names. Copies, the GLB never written.
const RIM_GLOW := Color(0.08, 0.32, 1.0)
const RIM_GLOW_ENERGY := 0.45


static func _tune_materials(root: Node) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not (mi.name == "Mat" or mi.name == "Rim"):
			continue
		for s in range(mi.mesh.get_surface_count()):
			var src := mi.get_active_material(s) as StandardMaterial3D
			if src == null:
				continue
			var m := src.duplicate() as StandardMaterial3D
			m.metallic = 0.0
			# the mat only a faint sheen: more of it mirrored the sandy sky and browned it from some angles
			m.metallic_specular = 0.12 if mi.name == "Mat" else 0.15
			m.roughness = 0.8 if mi.name == "Mat" else 0.9
			m.set("disable_fog", true)
			if mi.name == "Mat":
				m.albedo_color = Color(0.03, 0.03, 0.035)
			else:
				m.emission_enabled = true
				m.emission = RIM_GLOW
				m.emission_energy_multiplier = RIM_GLOW_ENERGY
			mi.set_surface_override_material(s, m)


## The model as a run draws it (the GLB or the stand-in, graded, its materials tuned, no shadows): the trampoline's own
## and Warmup's (pass 70: drawn once under the spawn beam when the hero can be offered a trampoline perk, so its
## materials and the mat's blend shape compile there, not at the first drop).
static func model_instance() -> Node3D:
	var root: Node3D = null
	if ResourceLoader.exists(MODEL_PATH):
		var ps := load(MODEL_PATH) as PackedScene
		if ps:
			root = ps.instantiate() as Node3D
	if root == null:
		root = _primitive_model()
	root.name = "TrampolineModel"
	WeaponBehavior.grade_materials(root, WeaponBehavior.grade_for(Run.map, {}))
	_tune_materials(root)
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


## Whether the hero being played can be offered a trampoline perk (his perks by Registry.perks_of, hidden ones left out).
static func can_offer() -> bool:
	if Run.character == null:
		return false
	for pk: PerkDef in Registry.perks_of(Run.character.id):
		if pk.special == "trampoline":
			return true
	return false


## A stand-in when art/props/trampoline.glb is missing: a black disc, a blue ring, four grey legs (the dip lowers the
## mat instead of bowing it).
static func _primitive_model() -> Node3D:
	var root := Node3D.new()
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.07, 0.07, 0.09)
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color(0.1, 0.38, 0.92)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.6, 0.62, 0.66)
	var m := MeshInstance3D.new()
	m.name = "Mat"
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.04
	m.mesh = disc
	m.material_override = black
	root.add_child(m)
	m.position.y = TOP
	var r := MeshInstance3D.new()
	r.name = "Rim"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.95
	torus.outer_radius = 1.28
	r.mesh = torus
	r.material_override = blue
	r.position.y = TOP + 0.05
	r.scale = Vector3(1.0, 0.35, 1.0)
	root.add_child(r)
	var legs := Node3D.new()
	legs.name = "Legs"
	root.add_child(legs)
	for k in range(4):
		var a := TAU * (float(k) + 0.5) / 4.0
		var leg := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.035
		cyl.bottom_radius = 0.035
		cyl.height = TOP
		leg.mesh = cyl
		leg.material_override = steel
		leg.position = Vector3(cos(a) * 1.2, TOP * 0.5, sin(a) * 1.2)
		legs.add_child(leg)
	return root


## The mat's spring and the frame's bounce, every frame it shows.
func _tick_springs(delta: float) -> void:
	if model == null or not model.visible:
		return
	var dt := minf(delta, 0.05)
	_dip_v += (-SPRING_K * dip - SPRING_DAMP * _dip_v) * dt
	dip += _dip_v * dt
	if absf(dip) < 0.002 and absf(_dip_v) < 0.02:
		dip = 0.0
		_dip_v = 0.0
	_bump_v += (-BUMP_K * _bump - BUMP_DAMP * _bump_v) * dt
	_bump += _bump_v * dt
	_apply_dip()
	if phase == STANDING or phase == DROPPING:
		var sq := clampf(_bump, -0.25, 0.25)
		model.scale = Vector3(1.0 - sq * 0.5, 1.0 + sq, 1.0 - sq * 0.5)


func _apply_dip() -> void:
	if _mat == null:
		return
	var d := clampf(dip, -0.4, 1.0)
	if _dip_idx >= 0:
		_mat.set_blend_shape_value(_dip_idx, d)
	elif phase != FOLDING:
		_mat.position.y = _mat_y - 0.2 * d
