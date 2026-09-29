## Fires projectiles. Targeting: nearest, random, or forward cone (Boomstick style). Every mode auto-aims: a forward
## weapon points its cone at the nearest enemy in range and only fires along the facing when nothing is near.
## The visual scene may carry a "Held" node (a gun at the hero's hip, forward weapons) or a "Familiar" node
## (a little companion that circles the hero and fires from where it is; child nodes "WingL"/"WingR" flap).
## Familiar tuning is data: params.familiar = {"radius": 1.25, "height": 1.35, "speed": 1.4, "bob": 0.12}.
## A burst (params.burst) leaves a round every `burst_gap` seconds (0.05), each scattered up to `scatter_deg` (else the
## volley's spread, at least 5 degrees); the companion's "Drum" turns `drum_step` radians a round about its sideways
## axis, or about the barrel with `drum_axis` "forward" (the Revolver's cylinder, pass 35); `no_shells` keeps the casings
## in (a revolver).
class_name ProjectileEmitter
extends WeaponBehavior

var _held: Node3D
var _familiar: Node3D
var _wing_l: Node3D
var _wing_r: Node3D
var _drum: Node3D          # a drum magazine on the companion gun turns a notch per round
var _recoil := 0.0
var _aim_yaw := 0.0
var _aim_dir := Vector3.ZERO
var _orbit := 0.0
var _flap := 0.0
# params.burst: the shots of one trigger pull leave one after another (a submachine gun) instead of all at once
var _burst: Array = []   # pending shots: {from, dir, speed, damage, pierce, prad, life, knock, spread}
var _burst_t := 0.0
var _shots := 0          # trigger pulls, for Both Barrels (every Nth fires twice)
var _taps := 0           # Fan the Hammer: extra volleys still to fire after this one
var _tap_t := 0.0
var _tap_mult := 1.0


func _shows_held() -> bool:
	return inst.def.targeting == "forward"


func _on_setup() -> void:
	_held = visual.get_node_or_null("Held")
	_familiar = visual.get_node_or_null("Familiar")
	if _familiar:
		_wing_l = _familiar.get_node_or_null("WingL")
		_wing_r = _familiar.get_node_or_null("WingR")
		_drum = _familiar.find_child("Drum", true, false)
		_orbit = randf() * TAU
		_place_familiar(0.0)


func _familiar_param(key: String, default: float) -> float:
	var f = inst.params.get("familiar", {})
	return float(f.get(key, default)) if f is Dictionary else default


func _place_familiar(delta: float) -> void:
	var r := _familiar_param("radius", 1.25)
	var h := _familiar_param("height", 1.35)
	var bob := _familiar_param("bob", 0.12)
	_orbit += delta * _familiar_param("speed", 1.4)
	var t := float(Time.get_ticks_msec()) * 0.001
	var want := player.global_position + Vector3(cos(_orbit) * r, h + sin(t * 3.1) * bob, sin(_orbit) * r)
	# recoil: the gun jumps back along its own barrel and the muzzle climbs, then settles
	var aim := Vector3(-sin(_aim_yaw), 0, -cos(_aim_yaw))
	want -= aim * 0.1 * _recoil
	# eased follow, so a sprinting hero drags the companion behind him a little
	_familiar.global_position = want if delta <= 0.0 else _familiar.global_position.lerp(want, clampf(delta * 9.0, 0.0, 1.0))
	_familiar.rotation.y = _aim_yaw
	_familiar.rotation.x = -0.28 * _recoil
	# params.familiar.roll lays a flat gun on its side, so the camera overhead sees its profile (the Revolver)
	_familiar.rotation.z = sin(t * 2.3) * 0.08 + _familiar_param("roll", 0.0)
	_flap += delta * 20.0
	var wing := 0.35 + absf(sin(_flap)) * 0.55
	if _wing_l:
		_wing_l.rotation.z = wing
	if _wing_r:
		_wing_r.rotation.z = -wing


func _fire_burst_shot() -> void:
	if _burst.is_empty():
		return
	var b: Dictionary = _burst.pop_front()
	var dir: Vector3 = _aim_dir if _aim_dir.length_squared() > 0.0001 else player.forward()
	if _familiar:
		# every round aims from where the companion is now (pass 35: it circles a metre off the hero, and the hero's line
		# to the target sent a tight round, the Revolver's, a metre wide of it)
		dir = _from_familiar(dir)
	# Sweep Fire: the rounds walk across a fan instead of scattering
	var d: Vector3 = dir.rotated(Vector3.UP, float(b["angle"])) if b.has("angle") else dir.rotated(Vector3.UP, randf_range(-float(b["spread"]), float(b["spread"])))
	var from: Vector3 = (_familiar.global_position + dir * 0.45) if _familiar else player.aim_origin(dir)
	game.projectiles.fire(projectile_kind, from, d * float(b["speed"]), float(b["damage"]), int(b["pierce"]), float(b["prad"]), float(b["life"]), inst, float(b["knock"]))
	if _familiar:
		# every round: a kick, the drum turns a notch, a casing flies out to the right
		_recoil = 1.0
		if _drum:
			# a drum magazine turns about the axis running sideways through the gun; a revolver's cylinder about the barrel
			var axis := Vector3.FORWARD if str(inst.params.get("drum_axis", "")) == "forward" else Vector3.RIGHT
			_drum.rotate_object_local(axis, float(inst.params.get("drum_step", 0.5)))
		if not bool(inst.params.get("no_shells", false)):
			game.fx.shell(_familiar.global_position + Vector3(0, 0.05, 0), dir.rotated(Vector3.UP, -PI * 0.5))
	muzzle_flash(from)


func _tick(_delta: float) -> void:
	if not _burst.is_empty():
		_burst_t -= _delta
		if _burst_t <= 0.0:
			_burst_t = float(inst.params.get("burst_gap", 0.05))
			_fire_burst_shot()
	if _taps > 0:
		_tap_t -= _delta
		if _tap_t <= 0.0:
			_taps -= 1
			_tap_t = 0.09
			_volley(_tap_mult)
	if (_held and _held.visible) or _familiar:
		# the held gun (or the companion) tracks the nearest enemy between shots, so it points where the shots go
		var enemies: EnemyManager = game.enemies
		var healthy := inst.def.targeting == "healthy"
		var t := enemies.nearest_index(player.global_position, stat("range", 9.0), inst.element() if healthy else "")
		if t < 0 and healthy:
			t = enemies.nearest_index(player.global_position, stat("range", 9.0))
		var want: Vector3 = (enemies.pos[t] - player.global_position) if t >= 0 else player.forward()
		want.y = 0.0
		if want.length_squared() > 0.0001:
			_aim_yaw = lerp_angle(_aim_yaw, atan2(-want.x, -want.z), clampf(_delta * 12.0, 0.0, 1.0))
	if _held and _held.visible:
		_held.global_position = player.hip.global_position
		_held.rotation.y = _aim_yaw
		# small recoil settle
		_held.scale = _held.scale.lerp(Vector3.ONE, _delta * 10.0)
	if _familiar:
		_recoil = maxf(_recoil - _delta * 9.0, 0.0)
		_place_familiar(_delta)
		_familiar.scale = _familiar.scale.lerp(Vector3.ONE, _delta * 10.0)


## The way from the companion to the nearest creature in range (the gun's own line of fire), else `fallback`.
func _from_familiar(fallback: Vector3) -> Vector3:
	var em: EnemyManager = game.enemies
	var t := em.nearest_index(player.global_position, stat("range", 9.0))
	if t < 0:
		return fallback
	var to: Vector3 = em.pos[t] - _familiar.global_position
	to.y = 0.0
	return to.normalized() if to.length_squared() > 0.01 else fallback


## One fan of `amount` shots along `dir` from `from`.
func _volley_at(dir: Vector3, from: Vector3, amount: int, damage: float, speed: float, pierce: int, prad: float, life: float, knock: float, half_spread: float) -> void:
	for k in range(amount):
		var a := 0.0
		if amount > 1:
			a = lerp(-half_spread, half_spread, float(k) / float(amount - 1))
		var d := dir.rotated(Vector3.UP, a)
		game.projectiles.fire(projectile_kind, from, d * speed, damage, pierce, prad, life, inst, knock)


## A repeat of the last volley at the current aim (Fan the Hammer), scaled.
func _volley(mult: float) -> void:
	var dir: Vector3 = _aim_dir if _aim_dir.length_squared() > 0.0001 else player.forward()
	var from: Vector3 = (_familiar.global_position + dir * 0.45) if _familiar else player.aim_origin(dir)
	var amount: int = max(stat_int("amount", 1), 1)
	var speed := stat("speed", 14.0)
	var half_spread := deg_to_rad(4.0) * (amount - 1)
	if inst.def.targeting == "forward":
		half_spread = deg_to_rad(stat("spread_deg", 30.0)) * 0.5
	_volley_at(dir, from, amount, stat("damage", 5.0) * mult, speed, stat_int("pierce", 0), float(inst.params.get("radius", 0.25)), stat("range", 9.0) / maxf(speed, 1.0), stat("knockback", 0.0), half_spread)
	muzzle_flash(from)
	sfx("fire", from)


func _fire() -> bool:
	var enemies: EnemyManager = game.enemies
	var amount: int = max(stat_int("amount", 1), 1)
	var speed := stat("speed", 14.0)
	var range_m := stat("range", 9.0)
	var damage := stat("damage", 5.0)
	var pierce := stat_int("pierce", 0)
	var knock := stat("knockback", 0.0)
	var prad := float(inst.params.get("radius", 0.25))
	var dir := Vector3.ZERO
	var half_spread := 0.0
	match inst.def.targeting:
		"forward":
			var t := enemies.nearest_index(player.global_position, range_m)
			dir = (enemies.pos[t] - player.global_position) if t >= 0 else player.forward()
			half_spread = deg_to_rad(stat("spread_deg", 30.0)) * 0.5
			if _held:
				_held.scale = Vector3(1.0, 1.0, 0.7)
		"random":
			var t := enemies.random_in_range(player.global_position, range_m)
			if t < 0:
				return false
			dir = (enemies.pos[t] - player.global_position)
			half_spread = deg_to_rad(4.0) * (amount - 1)
		"healthy":
			# the nearest creature not carrying this weapon's element yet; when everyone does, the nearest one
			var t := enemies.nearest_index(player.global_position, range_m, inst.element())
			if t < 0:
				t = enemies.nearest_index(player.global_position, range_m)
			if t < 0:
				return false
			dir = (enemies.pos[t] - player.global_position)
			half_spread = deg_to_rad(4.0) * (amount - 1)
		_:
			var t := enemies.nearest_index(player.global_position, range_m)
			if t < 0:
				return false
			dir = (enemies.pos[t] - player.global_position)
			half_spread = deg_to_rad(4.0) * (amount - 1)
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = player.forward()
	dir = dir.normalized()
	_aim_dir = dir
	_aim_yaw = atan2(-dir.x, -dir.z)
	var from: Vector3 = player.aim_origin(dir)
	if _familiar:
		# shots leave the companion's mouth, wherever it is circling right now, aimed from there
		if inst.def.targeting != "random":
			dir = _from_familiar(dir)
			_aim_dir = dir
		from = _familiar.global_position + dir * 0.45
		_familiar.scale = Vector3(1.18, 0.86, 1.18)
	var life := range_m / maxf(speed, 1.0)
	_shots += 1
	# Drum Roll: the burst grows with Buck's momentum
	var mr := int(inst.params.get("momentum_rounds", 0))
	if mr > 0:
		amount += int(floor(Run.momentum * float(mr) + 0.0001))
	if bool(inst.params.get("burst", false)):
		# a burst: one shot now, the rest every 50 ms from wherever the gun is by then, each with its own scatter
		_burst.clear()
		var sweep := deg_to_rad(float(inst.params.get("sweep_deg", 0.0)))
		var scatter: float = deg_to_rad(float(inst.params["scatter_deg"])) if inst.params.has("scatter_deg") else maxf(half_spread, deg_to_rad(5.0))
		for k in range(amount):
			var shot := {"speed": speed, "damage": damage, "pierce": pierce, "prad": prad, "life": life, "knock": knock, "spread": scatter}
			if sweep > 0.0 and amount > 1:
				shot["angle"] = lerpf(-sweep * 0.5, sweep * 0.5, float(k) / float(amount - 1))
			_burst.append(shot)
		_burst_t = 0.0
		_fire_burst_shot()
	else:
		_volley_at(dir, from, amount, damage, speed, pierce, prad, life, knock, half_spread)
		# Both Barrels: every Nth pull fires the volley twice; Fan the Hammer: extra volleys a beat apart, a little weaker
		var de := int(inst.params.get("double_every", 0))
		if de > 0 and _shots % de == 0:
			_volley_at(dir, from, amount, damage, speed, pierce, prad, life, knock, half_spread)
			muzzle_flash(from)
		var dt = inst.params.get("double_tap")
		if dt is Dictionary:
			_taps = maxi(int(dt.get("count", 2)) - 1, 0)
			_tap_t = 0.09
			_tap_mult = float(dt.get("damage_mult", 0.75))
	if bool(inst.params.get("shockwave", false)):
		enemies.damage_radius(player.global_position, 1.8, damage * 0.5, inst.def.id, knock)
		game.telegraphs.flash_ring(player.global_position, 1.8, Color(1.0, 0.7, 0.3))
	muzzle_flash(from)
	sfx("fire", from)
	return true
