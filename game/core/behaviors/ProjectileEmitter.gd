## Fires projectiles. Targeting: nearest, random, or forward cone (Boomstick style). Every mode auto-aims: a forward
## weapon points its cone at the nearest enemy in range and only fires along the facing when nothing is near.
## The visual scene may carry a "Held" node (a gun at the hero's hip, forward weapons) or a "Familiar" node
## (a little companion that circles the hero and fires from where it is; child nodes "WingL"/"WingR" flap).
## Familiar tuning is data: params.familiar = {"radius": 1.25, "height": 1.35, "speed": 1.4, "bob": 0.12}.
class_name ProjectileEmitter
extends WeaponBehavior

var _held: Node3D
var _familiar: Node3D
var _wing_l: Node3D
var _wing_r: Node3D
var _aim_yaw := 0.0
var _aim_dir := Vector3.ZERO
var _orbit := 0.0
var _flap := 0.0


func _shows_held() -> bool:
	return inst.def.targeting == "forward"


func _on_setup() -> void:
	_held = visual.get_node_or_null("Held")
	_familiar = visual.get_node_or_null("Familiar")
	if _familiar:
		_wing_l = _familiar.get_node_or_null("WingL")
		_wing_r = _familiar.get_node_or_null("WingR")
		_orbit = randf() * TAU
		_place_familiar(0.0)


func _familiar_param(key: String, default: float) -> float:
	var f = inst.def.params.get("familiar", {})
	return float(f.get(key, default)) if f is Dictionary else default


func _place_familiar(delta: float) -> void:
	var r := _familiar_param("radius", 1.25)
	var h := _familiar_param("height", 1.35)
	var bob := _familiar_param("bob", 0.12)
	_orbit += delta * _familiar_param("speed", 1.4)
	var t := float(Time.get_ticks_msec()) * 0.001
	var want := player.global_position + Vector3(cos(_orbit) * r, h + sin(t * 3.1) * bob, sin(_orbit) * r)
	# eased follow, so a sprinting hero drags the companion behind him a little
	_familiar.global_position = want if delta <= 0.0 else _familiar.global_position.lerp(want, clampf(delta * 9.0, 0.0, 1.0))
	_familiar.rotation.y = _aim_yaw
	_familiar.rotation.z = sin(t * 2.3) * 0.08
	_flap += delta * 20.0
	var wing := 0.35 + absf(sin(_flap)) * 0.55
	if _wing_l:
		_wing_l.rotation.z = wing
	if _wing_r:
		_wing_r.rotation.z = -wing


func _tick(_delta: float) -> void:
	if (_held and _held.visible) or _familiar:
		# the held gun (or the companion) tracks the nearest enemy between shots, so it points where the shots go
		var enemies: EnemyManager = game.enemies
		var healthy := inst.def.targeting == "healthy"
		var t := enemies.nearest_index(player.global_position, stat("range", 9.0), healthy)
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
		_place_familiar(_delta)
		_familiar.scale = _familiar.scale.lerp(Vector3.ONE, _delta * 10.0)


func _fire() -> bool:
	var enemies: EnemyManager = game.enemies
	var amount: int = max(stat_int("amount", 1), 1)
	var speed := stat("speed", 14.0)
	var range_m := stat("range", 9.0)
	var damage := stat("damage", 5.0)
	var pierce := stat_int("pierce", 0)
	var knock := stat("knockback", 0.0)
	var prad := float(inst.def.params.get("radius", 0.25))
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
			# the nearest creature that is not poisoned yet; when everyone is, the nearest one
			var t := enemies.nearest_index(player.global_position, range_m, true)
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
		# shots leave the companion's mouth, wherever it is circling right now
		from = _familiar.global_position + dir * 0.45
		_familiar.scale = Vector3(1.18, 0.86, 1.18)
	var life := range_m / maxf(speed, 1.0)
	for k in range(amount):
		var a := 0.0
		if amount > 1:
			a = lerp(-half_spread, half_spread, float(k) / float(amount - 1))
		var d := dir.rotated(Vector3.UP, a)
		game.projectiles.fire(projectile_kind, from, d * speed, damage, pierce, prad, life, inst, knock)
	if bool(inst.def.params.get("shockwave", false)):
		enemies.damage_radius(player.global_position, 1.8, damage * 0.5, inst.def.id, knock)
		game.telegraphs.flash_ring(player.global_position, 1.8, Color(1.0, 0.7, 0.3))
	muzzle_flash(from)
	sfx("fire", from)
	return true
