## A patch of ground that works on whoever stands in it for a while: the Zap Beam's Static Field (a shocking disc
## off every hit), the Drifter's Trail Dust (a slow with no damage). A draped disc that fades in its last half second;
## damage every `tick` seconds through the weapon (so kills count for it), a slow applied every tick. The disc is an
## instance in the Telegraphs pools (pass 33.8), not a mesh of its own.
class_name Zone
extends Node3D

var game: Node
var weapon: WeaponInstance
var radius := 1.2
var life := 2.0
var dps := 0.0
var tick := 0.5
var slow := 0.0
var color := Color(0.4, 0.75, 1.0, 0.4)
## A burning patch (Brimstone Brand, pass 43): tongues of flame over it while it lasts.
var flames := false
var _t := 0.0
var _total := 2.0
var _next := 0.0
var _tg: Telegraphs
var _disc := -1


func setup(p_game: Node, w: WeaponInstance, r: float, seconds: float, p_dps: float, p_tick: float, p_slow: float, p_color: Color) -> void:
	game = p_game
	weapon = w
	radius = r
	life = seconds
	_total = seconds
	dps = p_dps
	tick = maxf(p_tick, 0.1)
	slow = p_slow
	color = p_color


func _ready() -> void:
	_tg = game.telegraphs
	_disc = _tg.hold_disc(global_position, radius, color)


func _exit_tree() -> void:
	if is_instance_valid(_tg):
		_tg.release(_disc)
	_disc = -1


func _process(delta: float) -> void:
	# pass 114 (lane REPLAY): the recorded frame's delta in a replay (Lockstep.dt)
	delta = Lockstep.dt(delta)
	if game == null or game.paused:
		return
	_t += delta
	life -= delta
	var fade: float = clampf(life / 0.5, 0.0, 1.0)
	_tg.set_alpha(_disc, color.a * fade * (0.8 + 0.2 * sin(_t * 14.0)))
	_next -= delta
	if _next <= 0.0:
		_next = tick
		var em: EnemyManager = game.enemies
		if dps > 0.0:
			var before := Run.kills
			em.damage_radius(global_position, radius, dps * tick, weapon.def.id if weapon else "", 0.0)
			if weapon:
				weapon.kills += Run.kills - before
			if flames and game.fx:
				for k in range(3):
					var a := randf() * TAU
					var rr := sqrt(randf()) * radius * 0.85
					game.fx.flame(global_position + Vector3(cos(a) * rr, 0.05, sin(a) * rr), randf_range(0.7, 1.1), 0.45, Color(1.0, 0.45, 0.12))
			elif game.has_method("fx_burst"):
				game.fx_burst(global_position + Vector3(0, 0.3, 0), Color(color.r, color.g, color.b), 0.5)
		if slow > 0.0:
			# a weapon's patch is a debuff Ducktape stretches (pass 47); a weaponless one is a hero's perk (Trail Dust)
			em.slow_radius(global_position, radius, slow, tick + 0.2, weapon != null)
	if life <= 0.0:
		queue_free()
