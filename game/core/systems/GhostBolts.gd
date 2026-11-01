## Pass 120 (lane GHOST): the Undertaker's Shovel's ghost bolts (Garry: "attacks, instead of being the same as the ones the
## hero has should be kind of ghostly projectiles like ones in Warcraft 3 ziggurat attack ... The attacks carry no
## knockback to the enemies"). Graveyard's ghosts send them (Graveyard._volley); this holds every bolt in flight in packed
## arrays and draws them, their wisps and their pops in one MultiMesh (core/shaders/ghost_bolt.gdshader, one draw call).
##
## The rules (the run's frames: Graveyard.tick hands its rule delta on; no dice, so a replay flies the same bolts):
## - a bolt leaves at `speed` m/s along the way it was launched and turns towards its creature at up to `turn` rad/s,
##   turning harder the longer it flies (x (1 + TURN_GROW x its age)), so it curves in and always lands; it aims at the
##   creature's body (half its size up, its lift too);
## - it hits its creature when it is within the creature's radius + HIT_PAD on the flat: `damage` with force 0 (no
##   knockback, no HIT_BLAST) and HIT_NO_CRIT (never a crit, so never Lightning in a Bottle's arcs), recorded as
##   `source` (the item's id: the Results screen, the run record, the damage numbers); the body of a creature it kills
##   falls along the bolt's way (pass 82's corpse throw is a death's look, not a push);
## - its creature gone (dead, or its slot handed to a new spawn: EnemyManager.serial), it flies on to the spot it last
##   aimed at and pops there, landing on the first creature it touches on the way or there (GONE_REACH);
## - after `life` s it fizzles out (a pop, no damage).
## The looks (never rules): a bead shed every WISP_STEP s that drifts up, shrinks and fades over WISP_LIFE s; a pop of
## ghost-light where it hits or fizzles (POP_LIFE s) and a small one at the ghost's chest when it fires. In the run sim
## (Run.sim_mode) nothing is drawn and no node is made; the bolts still fly and hit.
class_name GhostBolts
extends RefCounted

const MAX := 48
const BEAD_MAX := 256
const POP_MAX := 64
## a bolt's touch beyond a body's radius, on the flat (m)
const HIT_PAD := 0.3
## how much harder it turns each second it flies
const TURN_GROW := 2.5
## a bolt whose creature is gone pops this close to the spot it last aimed at (m)
const GONE_REACH := 0.45
## a bolt's drawn length in head widths at full speed (its tail)
const TAIL_LEN := 2.8
const WISP_STEP := 0.035
const WISP_LIFE := 0.3
const POP_LIFE := 0.3
const MUZZLE_LIFE := 0.22

var enemies: EnemyManager = null
var source := "undertakers_shovel"
## set from params.grave by Graveyard._tune_bolts at every volley
var speed := 8.0
var turn := 5.0
var life := 2.4
var size := 0.55

var pos := PackedVector3Array()
var vel := PackedVector3Array()
var tgt := PackedInt32Array()
var tser := PackedInt32Array()
var goal := PackedVector3Array()
var dmg := PackedFloat32Array()
var age := PackedFloat32Array()
var live := PackedByteArray()
var seed_v := PackedFloat32Array()
var _wisp_t := PackedFloat32Array()
var count := 0
## Tests and the capture: bolts fired, landed on a creature, fizzled out; the damage they dealt.
var fired := 0
var hits := 0
var fizzles := 0
var dealt := 0.0

# the looks: beads and pops in rings, each {pos, age, life, size}
var _bead_pos := PackedVector3Array()
var _bead_age := PackedFloat32Array()
var _bead_next := 0
var _pop_pos := PackedVector3Array()
var _pop_age := PackedFloat32Array()
var _pop_life := PackedFloat32Array()
var _pop_size := PackedFloat32Array()
var _pop_next := 0
var _mm: MultiMesh = null
var _mmi: MultiMeshInstance3D = null
var _mat: ShaderMaterial = null


func _init() -> void:
	pos.resize(MAX)
	vel.resize(MAX)
	tgt.resize(MAX)
	tser.resize(MAX)
	goal.resize(MAX)
	dmg.resize(MAX)
	age.resize(MAX)
	live.resize(MAX)
	seed_v.resize(MAX)
	_wisp_t.resize(MAX)
	_bead_pos.resize(BEAD_MAX)
	_bead_age.resize(BEAD_MAX)
	_bead_age.fill(99.0)
	_pop_pos.resize(POP_MAX)
	_pop_age.resize(POP_MAX)
	_pop_age.fill(99.0)
	_pop_life.resize(POP_MAX)
	_pop_life.fill(POP_LIFE)
	_pop_size.resize(POP_MAX)


## The drawing (never in the run sim): one MultiMeshInstance3D under `parent`, its colours from `palette` {core, body,
## rim} (hex strings).
func attach(parent: Node3D, palette: Dictionary) -> void:
	if _mmi != null or parent == null:
		return
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	# the Compatibility renderer multiplies the shader's colour by the custom data unless colours are on (CLAUDE.md)
	_mm.use_colors = true
	_mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	_mm.mesh = q
	_mm.instance_count = MAX + BEAD_MAX + POP_MAX
	_mm.visible_instance_count = 0
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://core/shaders/ghost_bolt.gdshader")
	_mat.set_shader_parameter("core_col", Color(str(palette.get("core", "#f2fdff"))))
	_mat.set_shader_parameter("body_col", Color(str(palette.get("body", "#8fe8ff"))))
	_mat.set_shader_parameter("rim_col", Color(str(palette.get("rim", "#7a5cd6"))))
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "GhostBolts"
	_mmi.multimesh = _mm
	_mmi.material_override = _mat
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.top_level = true
	# drawn wherever its pieces are (the transforms are data, see the shader)
	_mmi.custom_aabb = AABB(Vector3(-4000, -100, -4000), Vector3(8000, 400, 8000))
	parent.add_child(_mmi)


## Warmup (under the spawn beam): the bolts' shader drawn once, a piece of each kind, so the first volley never stalls on
## a compile.
static func warm(parent: Node3D) -> void:
	var gb := GhostBolts.new()
	gb.attach(parent, {})
	gb._mmi.top_level = false
	gb._mmi.custom_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	gb._mm.visible_instance_count = 3
	for k in range(3):
		gb._mm.set_instance_transform(k, Transform3D(Basis(Vector3(0.5, 0, 0), Vector3(0, 0.5, 1), Vector3(0, 0, 1)), Vector3(float(k), 0, 0)))
		gb._mm.set_instance_color(k, Color(1, 1, 1, 1))
		gb._mm.set_instance_custom_data(k, Color(0.3, float(k), 0.0, 2.0))


func detach() -> void:
	if _mmi != null and is_instance_valid(_mmi):
		_mmi.queue_free()
	_mmi = null
	_mm = null


## A bolt from `from` along `dir` at creature `target` (its pool index) for `damage`; false when every slot flies.
func fire(from: Vector3, dir: Vector3, target: int, damage: float) -> bool:
	if count >= MAX:
		return false
	var k := -1
	for j in range(MAX):
		if live[j] == 0:
			k = j
			break
	if k < 0:
		return false
	var d := dir.normalized() if dir.length_squared() > 0.000001 else Vector3.FORWARD
	live[k] = 1
	pos[k] = from
	vel[k] = d * speed
	tgt[k] = target
	tser[k] = enemies.serial[target] if enemies != null and target >= 0 and target < enemies.serial.size() else -1
	goal[k] = _aim(target) if tser[k] >= 0 else from + d * speed * life
	dmg[k] = damage
	age[k] = 0.0
	# a look: where its tail's waver starts
	seed_v[k] = float((fired * 7919) % 1000) / 1000.0
	_wisp_t[k] = 0.0
	count += 1
	fired += 1
	return true


## A small pop of ghost-light (the ghost's fire at its chest); a look.
func muzzle(at: Vector3, s: float = 0.55) -> void:
	_pop(at, s, MUZZLE_LIFE)


## Whether creature `i` can take a bolt now: alive, not dying, not buried or held, up out of the sand.
func _valid(i: int) -> bool:
	if enemies == null or i < 0 or i >= enemies.pool_max:
		return false
	if enemies.alive[i] == 0 or enemies.state[i] == EnemyManager.STATE_DYING or enemies.hidden[i] == 1 or enemies.held[i] == 1:
		return false
	return enemies.rise_t[i] >= enemies.rise_targetable


## Every bolt's frame (`delta` the rule frame's), then the drawing when there is one.
func tick(delta: float) -> void:
	if delta > 0.0 and count > 0:
		for k in range(MAX):
			if live[k] == 1:
				_fly(k, delta)
	if _mm != null:
		_draw(delta)


## Where a bolt aims on creature `i`: its body, half its size up (0.3 to 1.2 m) and its lift.
func _aim(i: int) -> Vector3:
	return enemies.pos[i] + Vector3(0, clampf(enemies.size[i] * 0.5, 0.3, 1.2) + enemies.lift_h[i], 0)


func _fly(k: int, delta: float) -> void:
	age[k] += delta
	var t := tgt[k]
	if t >= 0 and (not _valid(t) or enemies.serial[t] != tser[k]):
		t = -1
		tgt[k] = -1
	if t >= 0:
		goal[k] = _aim(t)
	var v := vel[k]
	var dir := v.normalized() if v.length_squared() > 0.000001 else Vector3.FORWARD
	# light homing on its creature (or the spot it last aimed at), harder the longer it flies
	var want := goal[k] - pos[k]
	if want.length_squared() > 0.0001:
		want = want.normalized()
		var ang := dir.angle_to(want)
		var max_turn := turn * (1.0 + TURN_GROW * age[k]) * delta
		if ang > 0.0001:
			if ang <= max_turn or ang > 3.1:
				dir = want
			else:
				dir = dir.slerp(want, max_turn / ang).normalized()
	vel[k] = dir * speed
	pos[k] += vel[k] * delta
	# the hit
	var hit := -1
	if t >= 0:
		var dx := pos[k].x - enemies.pos[t].x
		var dz := pos[k].z - enemies.pos[t].z
		var rr := enemies.radius[t] + HIT_PAD
		if dx * dx + dz * dz <= rr * rr:
			hit = t
	elif enemies != null:
		for i in enemies.indices_touching(pos[k], 0.0, HIT_PAD):
			if _valid(i):
				hit = i
				break
		if hit < 0 and pos[k].distance_squared_to(goal[k]) <= GONE_REACH * GONE_REACH:
			fizzles += 1
			_pop(pos[k], size * 1.3, POP_LIFE * 0.8)
			_free(k)
			return
	if hit >= 0:
		var before: float = enemies.hp[hit]
		var flat := Vector3(dir.x, 0, dir.z)
		enemies.damage(hit, dmg[k], source, flat, 0.0, false, false, EnemyManager.HIT_NO_CRIT)
		dealt += maxf(before - maxf(enemies.hp[hit], 0.0), 0.0)
		hits += 1
		_pop(pos[k], size * 1.9, POP_LIFE)
		_free(k)
		return
	if age[k] >= life:
		fizzles += 1
		_pop(pos[k], size * 1.3, POP_LIFE * 0.8)
		_free(k)
		return
	# a look: the wisp it sheds
	if _mm != null:
		_wisp_t[k] -= delta
		if _wisp_t[k] <= 0.0:
			_wisp_t[k] = WISP_STEP
			_bead(pos[k] - dir * size * 0.6 + Vector3(randf_range(-0.05, 0.05), randf_range(-0.04, 0.06), randf_range(-0.05, 0.05)))


func _free(k: int) -> void:
	live[k] = 0
	tgt[k] = -1
	count -= 1


func _bead(at: Vector3) -> void:
	_bead_pos[_bead_next] = at
	_bead_age[_bead_next] = 0.0
	_bead_next = (_bead_next + 1) % BEAD_MAX


func _pop(at: Vector3, s: float, l: float) -> void:
	if _mm == null:
		return
	_pop_pos[_pop_next] = at
	_pop_age[_pop_next] = 0.0
	_pop_life[_pop_next] = l
	_pop_size[_pop_next] = s
	_pop_next = (_pop_next + 1) % POP_MAX


## Pieces drawn now (tests, the capture).
func drawn() -> int:
	return _mm.visible_instance_count if _mm != null else 0


func _draw(delta: float) -> void:
	var n := 0
	for k in range(MAX):
		if live[k] == 0:
			continue
		var sp := vel[k].length()
		var b := Basis(Vector3(size, 0, 0), vel[k], Vector3(0, 0, 1))
		_mm.set_instance_transform(n, Transform3D(b, pos[k]))
		_mm.set_instance_color(n, Color(1, 1, 1, clampf(age[k] / 0.06, 0.0, 1.0)))
		_mm.set_instance_custom_data(n, Color(0.0, 0.0, seed_v[k], 1.0 + (TAIL_LEN - 1.0) * clampf(sp / maxf(speed, 0.01), 0.0, 1.0) * clampf(age[k] / 0.12, 0.2, 1.0)))
		n += 1
	for j in range(BEAD_MAX):
		if _bead_age[j] >= WISP_LIFE:
			continue
		_bead_age[j] += delta
		var f := _bead_age[j] / WISP_LIFE
		if f >= 1.0:
			continue
		_bead_pos[j] += Vector3(0, 0.5 * delta, 0)
		var s := size * (0.8 - 0.5 * f)
		_mm.set_instance_transform(n, Transform3D(Basis(Vector3(s, 0, 0), Vector3(0, s, 0), Vector3(0, 0, 1)), _bead_pos[j]))
		_mm.set_instance_color(n, Color(1, 1, 1, 1))
		_mm.set_instance_custom_data(n, Color(f, 1.0, 0.0, 1.0))
		n += 1
	for j in range(POP_MAX):
		if _pop_age[j] >= _pop_life[j]:
			continue
		_pop_age[j] += delta
		var f := _pop_age[j] / maxf(_pop_life[j], 0.01)
		if f >= 1.0:
			continue
		var s := _pop_size[j]
		_mm.set_instance_transform(n, Transform3D(Basis(Vector3(s, 0, 0), Vector3(0, s, 0), Vector3(0, 0, 1)), _pop_pos[j]))
		_mm.set_instance_color(n, Color(1, 1, 1, 1))
		_mm.set_instance_custom_data(n, Color(f, 2.0, 0.0, 1.0))
		n += 1
	_mm.visible_instance_count = n


## Every bolt gone at once (a run's end, the arena's clear).
func clear() -> void:
	for k in range(MAX):
		live[k] = 0
	count = 0
	_bead_age.fill(99.0)
	_pop_age.fill(99.0)
	if _mm != null:
		_mm.visible_instance_count = 0
