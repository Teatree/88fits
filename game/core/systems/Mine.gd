## A land mine on the ground: a low disc that blinks, and explodes when a creature steps on it.
## Bouncing Betty (params.leap {height, seconds, radius_mult, kb_mult}): it pops up to chest height first and bursts there,
## wider and harder.
## Pass 48, Wide Reach (params.spring {sense, windup, flight, apex}): a creature within `sense` of the mine makes it crouch
## (squashed down, its lamp blinking fast) for `windup` seconds, then spring at that creature on an arc `apex` metres high
## that comes down `flight` seconds later where the creature will be by then (led by its walk), and blow where it lands;
## with Bouncing Betty it pops at the landing. A creature on the mine itself still sets it off where it lies. Mines share
## out the creatures in reach (MineLayer.spring_target): two mines do not leap at one goblin while another walks by.
## Jackrabbit Mines (params.jackrabbit {sense, windup, flight, apex, double, hop}): the evolution's own block, over the
## spring a carried Wide Reach brings; after its burst the casing hops on (`hop` {reach, frac, flight, apex}) to the
## nearest other creature within `reach` on a small arc, and blows again there at `frac` of the damage.
## Every clock runs in _process (no tweens), so the mine pauses with the game and tests can step it.
class_name Mine
extends Node3D

const ST_ARMED := 0
const ST_CROUCH := 1
const ST_SPRING := 2
const ST_POP := 3
const ST_HOP := 4
const ST_GONE := 5
## Pass 51: flicked ahead of the walking hero (MineLayer's lay_ahead, toss_to) on a short hop, TOSS_TIME seconds and
## TOSS_APEX metres high, growing to full size on the way; it lands armed
const ST_TOSS := 6
const TOSS_TIME := 0.24
const TOSS_APEX := 0.7
## the crouch: squashed to this height, this much wider; the lamp blinks this fast (Hz) while it is about to go
const CROUCH_Y := 0.55
const CROUCH_XZ := 1.3
const BLINK_FAST := 12.0
const BLINK_SLOW := 3.0
const POP_IN := 0.2
## a spring never leaps further than its sense ring and this much
const LEAP_SLACK := 2.0
## an armed mine with a spring looks round its ring this often (stepping on it is checked every frame)
const LOOK_EVERY := 0.1
const LAMP_ON := Color(1.0, 0.2, 0.15)
const LAMP_OFF := Color(0.5, 0.1, 0.08)
const LAMP_DEAD := Color(0.18, 0.12, 0.1)

var owner_behavior: WeaponBehavior
var damage := 25.0
var area := 2.2
var knockback := 6.0
var life := 25.0
var trigger := 0.7
var state := ST_ARMED
## the creature it is after (its slot, and the serial that tells it from the next one in that slot); -1 for none
var target := -1
var target_serial := -1
## blasts so far (tests: the Jackrabbit's casing blows twice)
var blasts := 0
var _t := 0.0
var _st_t := 0.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _dur := 0.0
var _apex := 0.0
var _hopped := false
var _base_area := 2.2
var _base_knock := 6.0
var _pop_t := 0.0
var _look_t := 0.0
var _mi: MeshInstance3D
var _lamp: MeshInstance3D
var _lamp_mat: StandardMaterial3D


func setup(b: WeaponBehavior, mesh: Mesh, mat: Material, p_damage: float, p_area: float, p_knockback: float, p_life: float, p_trigger: float) -> void:
	owner_behavior = b
	damage = p_damage
	area = p_area
	knockback = p_knockback
	life = p_life
	trigger = p_trigger
	_base_area = area
	_base_knock = knockback
	_mi = MeshInstance3D.new()
	_mi.mesh = mesh
	_mi.material_override = mat
	_mi.position.y = 0.09
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)
	# the red button on top blinks so the mine is read on the sand
	_lamp = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.09
	s.height = 0.18
	s.radial_segments = 6
	s.rings = 3
	_lamp.mesh = s
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lamp_mat.albedo_color = LAMP_ON
	_lamp.material_override = _lamp_mat
	_lamp.position.y = 0.2
	add_child(_lamp)
	# it pops out of the drop (its own clock, POP_IN, so a crouch can take the scale over at once)
	scale = Vector3(0.3, 0.3, 0.3)
	_pop_t = POP_IN
	# the first look comes at once; the next ones LOOK_EVERY apart
	_look_t = 0.0


func _params() -> Dictionary:
	if is_instance_valid(owner_behavior) and owner_behavior.inst:
		return owner_behavior.inst.params
	return {}


func _dict(key: String) -> Dictionary:
	var v = _params().get(key)
	return v if v is Dictionary else {}


## The spring this mine has (Wide Reach's block with the Jackrabbit's own over it), or {} for none.
func spring() -> Dictionary:
	var sp: Dictionary = _dict("spring").duplicate()
	var jb := _dict("jackrabbit")
	for k in ["sense", "windup", "flight", "apex"]:
		if jb.has(k):
			sp[k] = jb[k]
	return sp


func is_armed() -> bool:
	return state == ST_ARMED


## Flicked from where it lies to `to` (pass 51, the Jackrabbit's lay_ahead): a short hop, not armed until it lands.
func toss_to(to: Vector3) -> void:
	_from = global_position
	_to = to
	_dur = TOSS_TIME
	_apex = TOSS_APEX
	_enter(ST_TOSS)


func _process(delta: float) -> void:
	if not is_instance_valid(owner_behavior):
		# the weapon is gone (swapped or evolved): its mines go with it
		queue_free()
		return
	var game: Node = owner_behavior.game
	if game == null or game.paused:
		return
	step(delta)


## One frame of the mine (tests call it directly).
func step(delta: float) -> void:
	var game: Node = owner_behavior.game
	_t += delta
	_st_t += delta
	var fast := state != ST_ARMED and state != ST_TOSS
	if state == ST_HOP:
		_lamp_mat.albedo_color = LAMP_DEAD
	else:
		_lamp_mat.albedo_color = LAMP_ON if int(_t * (BLINK_FAST if fast else BLINK_SLOW)) % 2 == 0 else LAMP_OFF
	if _pop_t > 0.0:
		_pop_t = maxf(_pop_t - delta, 0.0)
		if state == ST_ARMED:
			scale = Vector3.ONE * lerpf(0.3, 1.0, _back_out(1.0 - _pop_t / POP_IN))
	var em: EnemyManager = game.enemies
	match state:
		ST_ARMED:
			life -= delta
			if life <= 0.0:
				_finish()
				return
			# a trigger, not an aim: it goes off under whatever steps on it, on the screen or off it (pass 54)
			var on := em.nearest_index(global_position, trigger, "", true)
			if on >= 0:
				_set_target(em, on)
				_go_off()
				return
			_look_t -= delta
			if _look_t > 0.0:
				return
			_look_t = LOOK_EVERY
			var sp := spring()
			if not sp.is_empty():
				var t := _pick_spring_target(float(sp.get("sense", 3.5)))
				if t >= 0:
					_set_target(em, t)
					_enter(ST_CROUCH)
					_pop_t = 0.0
		ST_CROUCH:
			var windup := maxf(float(spring().get("windup", 0.25)), 0.01)
			var u := clampf(_st_t / windup, 0.0, 1.0)
			var e := u * u * (3.0 - 2.0 * u)
			scale = Vector3(lerpf(1.0, CROUCH_XZ, e), lerpf(1.0, CROUCH_Y, e), lerpf(1.0, CROUCH_XZ, e))
			if u >= 1.0:
				_launch(em)
		ST_SPRING:
			var u2 := clampf(_st_t / maxf(_dur, 0.01), 0.0, 1.0)
			global_position = _arc(u2)
			# stretched as it leaves, round again by the top, spinning on the way
			var s := lerpf(1.25, 1.0, clampf(u2 * 3.0, 0.0, 1.0))
			scale = Vector3(1.0 / sqrt(s), s, 1.0 / sqrt(s))
			rotation.y += delta * 14.0
			if u2 >= 1.0:
				scale = Vector3.ONE
				rotation = Vector3.ZERO
				_go_off()
		ST_POP:
			var leap := _dict("leap")
			var secs := maxf(float(leap.get("seconds", 0.22)), 0.01)
			var u3 := clampf(_st_t / secs, 0.0, 1.0)
			var y0 := _from.y
			global_position = Vector3(_from.x, y0 + float(leap.get("height", 1.2)) * (1.0 - (1.0 - u3) * (1.0 - u3)), _from.z)
			if u3 >= 1.0:
				_explode()
		ST_TOSS:
			var u5 := clampf(_st_t / maxf(_dur, 0.01), 0.0, 1.0)
			global_position = _arc(u5)
			scale = Vector3.ONE * lerpf(0.3, 1.0, u5)
			rotation.y += delta * 10.0
			if u5 >= 1.0:
				scale = Vector3.ONE
				rotation = Vector3.ZERO
				_pop_t = 0.0
				_look_t = 0.0
				_enter(ST_ARMED)
		ST_HOP:
			var u4 := clampf(_st_t / maxf(_dur, 0.01), 0.0, 1.0)
			global_position = _arc(u4)
			rotation.x += delta * 9.0
			if u4 >= 1.0:
				_hop_blast()


func _enter(st: int) -> void:
	state = st
	_st_t = 0.0


func _set_target(em: EnemyManager, i: int) -> void:
	target = i
	target_serial = em.serial[i] if i >= 0 else -1


## The creature the spring goes for: shared out by the layer (each mine its own), the nearest within `sense` without one.
func _pick_spring_target(sense: float) -> int:
	if owner_behavior.has_method("spring_target"):
		return owner_behavior.spring_target(global_position, sense, self)
	return owner_behavior.game.enemies.nearest_index(global_position, sense, "", true)


## Whether the creature it is after is still there to leap at: the same one (its serial), alive, not falling, not
## buried and not in the Gravity Gun's grip.
func _target_alive(em: EnemyManager) -> bool:
	return target >= 0 and em.alive[target] == 1 and em.serial[target] == target_serial and em.state[target] != EnemyManager.STATE_DYING \
			and em.hidden[target] == 0 and em.held[target] == 0


## The crouch is over: up and at the creature, to where it will be when the mine comes down. Its creature gone, it takes
## the next in reach; nobody left, it settles back down armed.
func _launch(em: EnemyManager) -> void:
	var sp := spring()
	if not _target_alive(em):
		_release()
		var t := _pick_spring_target(float(sp.get("sense", 3.5)))
		if t < 0:
			_enter(ST_ARMED)
			scale = Vector3.ONE
			return
		_set_target(em, t)
	_dur = maxf(float(sp.get("flight", 0.4)), 0.05)
	_apex = float(sp.get("apex", 1.4))
	_from = global_position
	var to: Vector3 = em.pos[target] + Vector3(em.vel[target].x, 0.0, em.vel[target].z) * _dur
	var flat := Vector3(to.x - _from.x, 0.0, to.z - _from.z)
	var most := float(sp.get("sense", 3.5)) + LEAP_SLACK
	if flat.length() > most:
		to = _from + flat.normalized() * most
	to.y = _ground(to)
	_to = to
	_enter(ST_SPRING)
	Audio.play("w_mine_spring", _from)


## Where an arc from _from to _to is at `u` (0..1): a straight line with a parabola of _apex on top.
func _arc(u: float) -> Vector3:
	return _from.lerp(_to, u) + Vector3(0.0, _apex * 4.0 * u * (1.0 - u), 0.0)


func _ground(p: Vector3) -> float:
	var game: Node = owner_behavior.game
	return game.map.height_at(p.x, p.z) if game.map else p.y


## Set off where it is: Bouncing Betty pops up first, else it blows now.
func _go_off() -> void:
	var leap := _dict("leap")
	if leap.is_empty():
		_explode()
		return
	# Bouncing Betty: up first, then the blast, wider and harder
	area = _base_area * float(leap.get("radius_mult", 1.5))
	knockback = _base_knock * float(leap.get("kb_mult", 2.0))
	_from = global_position
	_enter(ST_POP)


func _explode() -> void:
	_blast(area, damage, knockback)
	var hop: Dictionary = _dict("jackrabbit").get("hop", {}) if _dict("jackrabbit").get("hop") is Dictionary else {}
	if not hop.is_empty() and not _hopped and _start_hop(hop):
		return
	_finish()


## The blast where the mine is: `r` metres, `dmg`, thrown with `kb`; a crater that burns or fumes for a mine of an
## element, a nugget for a kill with Blasting Cap.
func _blast(r: float, dmg: float, kb: float) -> void:
	var game: Node = owner_behavior.game
	var em: EnemyManager = game.enemies
	var w: WeaponInstance = owner_behavior.inst
	var before := Run.kills
	em.damage_radius(global_position, r, dmg, w.def.id if w else "", kb)
	if w:
		w.kills += Run.kills - before
		# Napalm Mine: the crater burns (or fumes); Blasting Cap: a mine that kills pays a nugget
		var el: String = w.element()
		if el != "":
			for e in em.indices_in_radius(global_position, r):
				if el == "fire":
					em.ignite(e, w.def.id, w.stat("fire_damage", 4.0), w.stat("fire_duration", 1.8), w.stat("fire_spread", 0.4))
				else:
					em.poison(e, w.def.id, w.stat("poison_damage", 3.0), maxi(w.stat_int("poison_stacks", 1), 1), w.stat("poison_duration", 8.0))
			game.spawn_cloud(global_position, w, r * 0.8, el)
		if Run.kills > before and int(w.params.get("gold_on_kill", 0)) > 0:
			game.pickups.mark_coin(game.pickups.spawn(PickupManager.KIND_COIN, global_position, 3.0), "blasting_cap")
	game.fx_burst(global_position + Vector3(0, 0.3, 0), Color(1.0, 0.72, 0.3), r)
	game.camera.shake(0.5)
	owner_behavior.sfx("hit", global_position)
	blasts += 1


## Jackrabbit: after the burst the casing hops on to the nearest other creature within `hop.reach` (not the one it went
## off on, nor one the burst just killed). False when there is nobody to hop to.
func _start_hop(hop: Dictionary) -> bool:
	var em: EnemyManager = owner_behavior.game.enemies
	var reach := float(hop.get("reach", 5.0))
	var best := -1
	var best_d := reach * reach
	for i in em.indices_in_radius(global_position, reach):
		if em.alive[i] == 0 or em.state[i] == EnemyManager.STATE_DYING:
			continue
		if i == target and em.serial[i] == target_serial:
			continue
		var d := Vector2(em.pos[i].x - global_position.x, em.pos[i].z - global_position.z).length_squared()
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		return false
	_hopped = true
	_release()
	_set_target(em, best)
	_dur = maxf(float(hop.get("flight", 0.32)), 0.05)
	_apex = float(hop.get("apex", 0.9))
	_from = global_position
	var to: Vector3 = em.pos[best] + Vector3(em.vel[best].x, 0.0, em.vel[best].z) * _dur
	to.y = _ground(to)
	_to = to
	rotation = Vector3.ZERO
	_enter(ST_HOP)
	return true


## The casing comes down on its second creature: a blast of the mine's own size (not the Betty's) at `hop.frac`.
func _hop_blast() -> void:
	var hop: Dictionary = _dict("jackrabbit").get("hop", {}) if _dict("jackrabbit").get("hop") is Dictionary else {}
	_blast(_base_area, damage * float(hop.get("frac", 0.6)), _base_knock)
	_finish()


func _release() -> void:
	if is_instance_valid(owner_behavior) and owner_behavior.has_method("release_claim"):
		owner_behavior.release_claim(self)


func _finish() -> void:
	state = ST_GONE
	_release()
	queue_free()


## An elastic pop-in: overshoots a touch and settles.
static func _back_out(u: float) -> float:
	var c := 1.70158
	var x := u - 1.0
	return 1.0 + (c + 1.0) * x * x * x + c * x * x
