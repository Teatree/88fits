## The Dragon's Breath's fire (pass 109, lane VFX; Garry: "Fire Breath - Doesn't look like anything at the moment, any way
## we could make this to be looking more like fire and more like breath? Maybe a simple cheap 3d particle thing?").
## Two CPUParticles3D (CPU particles: the same on the phone's Compatibility renderer and in a headless run) that FireBreath
## points from the hero's face along his facing every frame of a breath:
##  - the FLAMES: soft puffs (core/shaders/breath_flame.gdshader) thrown fast out of the mouth, slowing (damping) as they
##    spread down the cone, growing, rising a little and burning white-hot -> orange -> red -> dark smoke; their speed
##    is fitted so they reach the end of the cone (`reach`) as they die, their spread is the cone's half width, flattened
##    so the fire is a fan like the cone the damage takes; a full ring (Held Breath) throws them all round, flat;
##  - the CORE: a short bright jet at the mouth, white and yellow, so the breath reads as coming out of his face.
## The puffs live in the world (local_coords off): a breath swept round leaves its fire where it went, as a hose does.
## stop() lets the puffs in the air burn out (no fire cut off mid-flight); free with the behaviour. Blue Flame and the
## Fire Eater burn the blue ramps. At most FLAME_MAX + CORE_AMOUNT puffs alive.
class_name BreathFlames
extends Node3D

const SHADER := preload("res://core/shaders/breath_flame.gdshader")
## Puffs alive at intensity 1 (the Backdraft's 1.5 and a ring's x1.6 add to it, FLAME_MAX at most), their life, their size
## at full grown (metres; x sqrt(intensity)).
const FLAME_AMOUNT := 64
const FLAME_MAX := 130
const FLAME_LIFE := 0.5
const FLAME_SIZE := 1.15
## The share of a flame's first speed left when it dies (the damping), and how far down the cone it gets.
const END_SPEED := 0.2
const REACH_SHARE := 0.95
## How much the cone's height is flattened (0 round, 1 a flat fan).
const FLATNESS := 0.65
const CORE_AMOUNT := 18
const CORE_LIFE := 0.18
const CORE_SIZE := 0.5

const ORANGE_RAMP := [
	[0.0, Color(1.0, 0.97, 0.78, 0.95)],
	[0.14, Color(1.0, 0.78, 0.25, 0.95)],
	[0.36, Color(1.0, 0.42, 0.06, 0.9)],
	[0.6, Color(0.78, 0.13, 0.03, 0.75)],
	[0.82, Color(0.2, 0.12, 0.1, 0.45)],
	[1.0, Color(0.12, 0.1, 0.09, 0.0)]]
const BLUE_RAMP := [
	[0.0, Color(0.92, 0.97, 1.0, 0.95)],
	[0.14, Color(0.55, 0.82, 1.0, 0.95)],
	[0.36, Color(0.22, 0.48, 1.0, 0.9)],
	[0.6, Color(0.3, 0.16, 0.85, 0.72)],
	[0.82, Color(0.14, 0.12, 0.2, 0.42)],
	[1.0, Color(0.1, 0.1, 0.14, 0.0)]]
const CORE_RAMP := [
	[0.0, Color(1.0, 1.0, 0.92, 1.0)],
	[0.5, Color(1.0, 0.9, 0.45, 0.9)],
	[1.0, Color(1.0, 0.6, 0.15, 0.0)]]
const CORE_BLUE_RAMP := [
	[0.0, Color(0.95, 1.0, 1.0, 1.0)],
	[0.5, Color(0.6, 0.88, 1.0, 0.9)],
	[1.0, Color(0.3, 0.55, 1.0, 0.0)]]

var flames: CPUParticles3D
var core: CPUParticles3D
var _ring := false
var _blue := false
## Breaths started (tests).
var starts := 0
## Pass 110 (lane VFX; Garry: "when Player hero is facing up, or up-left or up-right the Fire Breath visual renders behind
## the hero 2.5d art asset"): the hero's face is 1.45 m up and his painting leans back with the camera, so the fire
## leaving his face is in front of the painting's plane and drew over him whichever way he faced. While the camera sees
## his back (his back and back-diagonal views, FireBreath: Player.faces_away) the puffs draw at BEHIND_PRIORITY in the
## see-through queue, before his second pass (BillboardSprite.OVER_PRIORITY), so his painting covers them wherever they
## cross it, as it covers his speed trails; in his other views at 0, over him as before. The whole fire (the puffs share
## one material) switches at the view change.
const BEHIND_PRIORITY := -2
var behind := false


## A BreathFlames under `parent` (the game: the puffs live in the world, not on the weapon).
static func make(parent: Node) -> BreathFlames:
	var bf := BreathFlames.new()
	bf.name = "BreathFlames"
	parent.add_child(bf)
	return bf


func _init() -> void:
	flames = _emitter(FLAME_AMOUNT, FLAME_LIFE, 0.6)
	flames.name = "Flames"
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.28))
	sc.add_point(Vector2(0.18, 0.62))
	sc.add_point(Vector2(0.55, 1.0))
	sc.add_point(Vector2(1.0, 1.3))
	flames.scale_amount_curve = sc
	flames.angular_velocity_min = -90.0
	flames.angular_velocity_max = 90.0
	flames.gravity = Vector3(0, 2.2, 0)
	add_child(flames)
	core = _emitter(CORE_AMOUNT, CORE_LIFE, 0.3)
	core.name = "Core"
	var cc := Curve.new()
	cc.add_point(Vector2(0.0, 0.7))
	cc.add_point(Vector2(1.0, 0.3))
	core.scale_amount_curve = cc
	core.gravity = Vector3.ZERO
	add_child(core)
	_paint(false)


func _emitter(amount: int, life: float, edge_noise: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.lifetime_randomness = 0.25
	p.local_coords = false
	p.direction = Vector3(0, 0, -1)
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.anim_offset_min = 0.0
	p.anim_offset_max = 1.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.06
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("edge_noise", edge_noise)
	q.material = m
	p.mesh = q
	return p


static func _gradient(stops: Array) -> Gradient:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s: Array in stops:
		offs.append(float(s[0]))
		cols.append(s[1])
	g.offsets = offs
	g.colors = cols
	return g


func _paint(blue: bool) -> void:
	_blue = blue
	flames.color_ramp = _gradient(BLUE_RAMP if blue else ORANGE_RAMP)
	core.color_ramp = _gradient(CORE_BLUE_RAMP if blue else CORE_RAMP)


## A breath starts: `reach` m long, `deg` wide (a ring past FireBreath.RING_DEG or with `ring`), blue or orange, its
## `intensity` (the look's: Backdraft, the Fire Eater) growing the puffs and their count.
func start(reach: float, deg: float, ring: bool, blue: bool, intensity: float = 1.0) -> void:
	starts += 1
	_ring = ring or deg >= 359.0
	if blue != _blue:
		_paint(blue)
	var k := maxf(intensity, 0.1)
	var want: int = mini(int(round(float(FLAME_AMOUNT) * k * (1.6 if _ring else 1.0))), FLAME_MAX)
	if flames.amount != want:
		flames.amount = want
	var size: float = FLAME_SIZE * sqrt(k)
	flames.scale_amount_min = size * 0.8
	flames.scale_amount_max = size * 1.1
	core.scale_amount_min = CORE_SIZE * sqrt(k) * 0.8
	core.scale_amount_max = CORE_SIZE * sqrt(k)
	# the first speed that carries a flame REACH_SHARE of the reach in its life, slowing to END_SPEED of it: distance =
	# v0 L (1 + END_SPEED) / 2 with a steady damping of v0 (1 - END_SPEED) / L
	var r: float = maxf(reach, 0.5) * REACH_SHARE
	var v0: float = 2.0 * r / (FLAME_LIFE * (1.0 + END_SPEED))
	flames.initial_velocity_min = v0 * 0.88
	flames.initial_velocity_max = v0 * 1.05
	flames.damping_min = v0 * (1.0 - END_SPEED) / FLAME_LIFE * 0.9
	flames.damping_max = v0 * (1.0 - END_SPEED) / FLAME_LIFE
	var cv: float = minf(r * 0.3, 1.6) / CORE_LIFE
	core.initial_velocity_min = cv * 0.8
	core.initial_velocity_max = cv
	var half: float = 180.0 if _ring else clampf(deg, 1.0, 359.0) * 0.5
	flames.spread = half * 0.92
	core.spread = minf(half * 0.45, 30.0) if not _ring else 180.0
	flames.flatness = 1.0 if _ring else FLATNESS
	core.flatness = 1.0 if _ring else FLATNESS
	flames.emitting = true
	core.emitting = true


## The fire's mouth this frame: at `at` (the hero's face), along `dir` (flat). A ring keeps its flat turn (its fan is
## the ground's plane).
func follow(at: Vector3, dir: Vector3) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 0.0001:
		d = Vector3.FORWARD
	d = d.normalized()
	var b := Basis() if _ring else Basis.looking_at(d, Vector3.UP)
	global_transform = Transform3D(b, at)


## Pass 110: the fire behind the hero (`on`: his back views) or over him.
func set_behind(on: bool) -> void:
	if on == behind:
		return
	behind = on
	for p: CPUParticles3D in [flames, core]:
		var m := (p.mesh as QuadMesh).material as ShaderMaterial if p.mesh is QuadMesh else null
		if m:
			m.render_priority = BEHIND_PRIORITY if on else 0


## The see-through queue's place the puffs draw at now (tests).
func draw_priority() -> int:
	var m = (flames.mesh as QuadMesh).material if flames.mesh is QuadMesh else null
	return (m as ShaderMaterial).render_priority if m is ShaderMaterial else 0


## The breath ends: no new puffs, the ones in the air burn out.
func stop() -> void:
	flames.emitting = false
	core.emitting = false


func is_emitting() -> bool:
	return flames.emitting
