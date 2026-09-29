## A launcher that floats beside the hero and fires homing missiles. Every volley queues `amount` missiles that leave
## one after another in a fan; each corkscrews for a moment before it locks on and dives (ProjectileManager.launch_missile,
## tuned by `params.missile`). The "Familiar" node of the visual scene is the pod: it tracks the nearest creature between
## volleys and kicks back per launch. The same behaviour runs the Hornet Nest with faster, smaller, non-exploding seekers.
class_name MissilePod
extends WeaponBehavior

const LAUNCH_GAP := 0.09

var _familiar: Node3D
var _orbit := 0.0
var _aim_yaw := 0.0
var _recoil := 0.0
var _queue: Array = []
var _queue_t := 0.0
# the pod's own animation (pass 28): the tube cluster revolves a quarter turn per launch, the fired tube shows empty, and
# the rocket tips pop back one at a time while the pod reloads
var _cluster: Node3D
var _tips: Array = []
var _spin_target := 0.0
var _next_tube := 0
var _empty: Array = []
var _reload_t := 0.0
var _kick := 0.0


func _on_setup() -> void:
	_familiar = visual.get_node_or_null("Familiar")
	_orbit = randf() * TAU
	_cluster = visual.get_node_or_null("Familiar/Body/Cluster")
	_tips.clear()
	for k in range(1, 5):
		var tip := visual.get_node_or_null("Familiar/Body/Cluster/Tip%d" % k)
		if tip:
			_tips.append(tip)
	_place(0.0)


## The reload: while nothing is queued, every empty tube gets its tip back in turn, spread over most of the cooldown,
## each with a pop; the cluster eases to its next quarter turn and the launch kick settles.
func _tick_pod(delta: float) -> void:
	if _cluster == null:
		return
	_cluster.rotation.z = lerp_angle(_cluster.rotation.z, _spin_target, clampf(delta * 12.0, 0.0, 1.0))
	_kick = maxf(_kick - delta * 6.0, 0.0)
	_cluster.scale = Vector3(1.0 + 0.12 * _kick, 1.0 + 0.12 * _kick, 1.0 - 0.1 * _kick)
	if _queue.is_empty() and not _empty.is_empty():
		_reload_t -= delta
		if _reload_t <= 0.0:
			var gap: float = maxf(stat("cooldown", 1.0) * 0.7 / float(maxi(_tips.size(), 1)), 0.12)
			_reload_t = gap
			var tip: Node3D = _empty.pop_front()
			if is_instance_valid(tip):
				tip.visible = true
				tip.scale = Vector3(0.2, 0.2, 0.2)
				var tw := create_tween()
				tw.tween_property(tip, "scale", Vector3(1.15, 1.15, 1.15), 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tw.tween_property(tip, "scale", Vector3.ONE, 0.07)
				_kick = maxf(_kick, 0.35)
				sfx("reload", _familiar.global_position if _familiar else Vector3.INF)


func _missile_param(key: String, default: float) -> float:
	var m = inst.params.get("missile", {})
	return float(m.get(key, default)) if m is Dictionary else default


func _familiar_param(key: String, default: float) -> float:
	var f = inst.params.get("familiar", {})
	return float(f.get(key, default)) if f is Dictionary else default


func _place(delta: float) -> void:
	if _familiar == null:
		return
	var r := _familiar_param("radius", 1.2)
	var h := _familiar_param("height", 1.6)
	var bob := _familiar_param("bob", 0.1)
	_orbit += delta * _familiar_param("speed", 0.9)
	var t := float(Time.get_ticks_msec()) * 0.001
	var want := player.global_position + Vector3(cos(_orbit) * r, h + sin(t * 2.7) * bob, sin(_orbit) * r)
	var aim := Vector3(-sin(_aim_yaw), 0, -cos(_aim_yaw))
	want -= aim * 0.12 * _recoil
	_familiar.global_position = want if delta <= 0.0 else _familiar.global_position.lerp(want, clampf(delta * 8.0, 0.0, 1.0))
	_familiar.rotation.y = _aim_yaw
	_familiar.rotation.x = -0.3 * _recoil
	_familiar.rotation.z = sin(t * 1.9) * 0.06


func _tick(delta: float) -> void:
	if not _queue.is_empty():
		_queue_t -= delta
		if _queue_t <= 0.0:
			_queue_t = LAUNCH_GAP
			_launch_one()
	var enemies: EnemyManager = game.enemies
	var t := enemies.nearest_index(player.global_position, stat("range", 12.0))
	var want: Vector3 = (enemies.pos[t] - player.global_position) if t >= 0 else player.forward()
	want.y = 0.0
	if want.length_squared() > 0.0001:
		_aim_yaw = lerp_angle(_aim_yaw, atan2(-want.x, -want.z), clampf(delta * 8.0, 0.0, 1.0))
	_recoil = maxf(_recoil - delta * 8.0, 0.0)
	_tick_pod(delta)
	_place(delta)


func _fire() -> bool:
	var enemies: EnemyManager = game.enemies
	if enemies.nearest_index(player.global_position, stat("range", 12.0)) < 0:
		return false
	var n: int = maxi(stat_int("amount", 1), 1)
	for k in range(n):
		_queue.append(k)
	_queue_t = 0.0
	return true


func _launch_one() -> void:
	var k: int = _queue.pop_front()
	var from: Vector3 = (_familiar.global_position if _familiar else player.aim_origin(player.forward())) + Vector3(0, 0.2, 0)
	var aim := Vector3(-sin(_aim_yaw), 0, -cos(_aim_yaw))
	# a fan: alternate sides of the aim, wider for the later ones, all tilted up; the corkscrew does the rest
	var side: float = (1.0 if k % 2 == 0 else -1.0) * (0.3 + 0.22 * float(k / 2))
	var dir: Vector3 = (aim + aim.rotated(Vector3.UP, PI * 0.5) * side + Vector3(0, 0.9, 0)).normalized()
	var params := {
		"wander": _missile_param("wander", 0.5),
		"turn": _missile_param("turn", 6.0) * Run.player_sheet.get_stat("homing_turn", 1.0),
		"spiral": _missile_param("spiral", 7.0),
		"life": _missile_param("life", 4.5),
		"trail": int(_missile_param("trail", 1.0)),
	}
	game.projectiles.launch_missile(projectile_kind, from, dir, stat("speed", 13.0), stat("damage", 12.0), stat("area", 1.5), stat("range", 12.0), inst, params, stat("knockback", 3.0))
	_recoil = 1.0
	# the tube that fired shows empty and the cluster turns the next one up
	if not _tips.is_empty():
		var tip: Node3D = _tips[_next_tube % _tips.size()]
		_next_tube += 1
		if tip.visible:
			tip.visible = false
			_empty.append(tip)
		_spin_target += PI * 0.5
		_kick = 1.0
		_reload_t = 0.35
	muzzle_flash(from)
	sfx("fire", from)
