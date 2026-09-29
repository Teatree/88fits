## Blades orbiting the player on a tilted ring. Hits anything they touch, with a per-enemy hit cooldown. The blades
## are one MultiMesh (pass 33.8: a node and a draw call each, twenty of them for an evolved Saw Halo).
class_name Orbiter
extends WeaponBehavior

var _blade_n := 0
var _blade_mm: MultiMesh
var _angle := 0.0
var _hit_times: Dictionary = {}
var _ring: MeshInstance3D
var _blade_mesh: Mesh
var _blade_mat: Material
var _lasso_t := 0.0
var _strike_t := 1.0
var _strike_at := Vector3.INF
var _strike_anim := 0.0
var _gyro := 1.0
var _breathe_t := 0.0
var _side_times: Dictionary = {}   # creature -> when Wide Orbit last batted it aside


func _on_setup() -> void:
	var proj := visual.get_node_or_null("Projectile")
	if proj is MeshInstance3D and proj.mesh:
		_blade_mesh = proj.mesh
		_blade_mat = proj.material_override if proj.material_override else (proj.mesh.surface_get_material(0) if proj.mesh.get_surface_count() > 0 else null)
	else:
		var c := CylinderMesh.new()
		c.top_radius = 0.35
		c.bottom_radius = 0.35
		c.height = 0.06
		c.radial_segments = 10
		_blade_mesh = c
		_blade_mat = _default_material()
	if bool(inst.params.get("solid_ring", false)):
		_ring = MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.3
		t.outer_radius = 0.5
		_ring.mesh = t
		_ring.material_override = _blade_mat
		add_child(_ring)


func _sync_blades() -> void:
	var n: int = max(stat_int("amount", 1), 1)
	if _blade_mm == null:
		_blade_mm = MultiMesh.new()
		_blade_mm.transform_format = MultiMesh.TRANSFORM_3D
		_blade_mm.mesh = _blade_mesh
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Blades"
		mmi.multimesh = _blade_mm
		if _blade_mat:
			mmi.material_override = _blade_mat
		# the blades are placed in world space, like the nodes they replace
		mmi.top_level = true
		mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
		add_child(mmi)
	if n > _blade_mm.instance_count:
		_blade_mm.instance_count = maxi(n, 8)
	_blade_n = n
	_blade_mm.visible_instance_count = n


## How many blades are out (tests).
func blade_count() -> int:
	return _blade_n


func _tick(delta: float) -> void:
	_sync_blades()
	var r := stat("orbit_radius", 2.0)
	# Gyro Saws: the ring widens while the hero moves; Lasso: every period it swings out to its reach and back
	var gyro = inst.params.get("gyro")
	if gyro is Dictionary:
		var want: float = float(gyro.get("moving_mult", 1.3)) if player.velocity.length() > 0.8 else 1.0
		_gyro = lerpf(_gyro, want, clampf(delta * 5.0, 0.0, 1.0))
		r *= _gyro
	var lasso = inst.params.get("lasso")
	if lasso is Dictionary:
		_lasso_t += delta
		var period := float(lasso.get("period", 2.0))
		var out_t := float(lasso.get("out", 0.4))
		var phase := fmod(_lasso_t, period)
		if phase < out_t:
			r = lerpf(r, float(lasso.get("reach", 5.0)), sin(phase / out_t * PI))
	# Wide Orbit (pass 34): the ring breathes, drawing out to its widest and back in to a little inside its own radius
	var breathe = inst.params.get("breathe")
	if breathe is Dictionary:
		_breathe_t += delta
		var per := maxf(float(breathe.get("period", 2.8)), 0.2)
		r *= lerpf(float(breathe.get("min", 0.9)), float(breathe.get("max", 1.6)), 0.5 - 0.5 * cos(TAU * _breathe_t / per))
	var spin := float(inst.params.get("spin_speed", 2.6))
	# Berserk spins the blades faster too (their hits are paced by the halved cooldown)
	_angle += delta * spin * Run.haste
	var enemies: EnemyManager = game.enemies
	var damage := stat("damage", 8.0)
	var knock := stat("knockback", 1.0)
	# Wide Orbit's hits neither push away nor pull in: at most once a `every` a saw bats a creature aside along its spin
	var side = inst.params.get("side_knock")
	var side_on: bool = side is Dictionary
	var blade_r := 0.45 * stat("area", 1.0)
	var hit_cd: float = max(stat("cooldown", 0.25), 0.05)
	var pdmg := stat("poison_damage", 0.0)
	var pstacks: int = maxi(stat_int("poison_stacks", 1), 1)
	var pdur := stat("poison_duration", 10.0)
	var fdmg := stat("fire_damage", 0.0)
	var fdur := stat("fire_duration", 1.8)
	var fspread := stat("fire_spread", 0.5)
	var now := Time.get_ticks_msec() * 0.001
	var center: Vector3 = player.global_position + Vector3(0, 0.6, 0)
	var n := _blade_n
	var area := stat("area", 1.0)
	# Strike: every period the first blade lunges at the nearest creature outside the ring, hits it for more, snaps back
	var strike = inst.params.get("strike")
	if strike is Dictionary:
		_strike_t -= delta
		_strike_anim = maxf(_strike_anim - delta, 0.0)
		if _strike_t <= 0.0:
			_strike_t = float(strike.get("period", 2.0))
			var best := -1
			var best_d := float(strike.get("reach", 6.0))
			for e in enemies.indices_in_radius(center, float(strike.get("reach", 6.0))):
				var dd := (enemies.pos[e] - center).length()
				if dd > r + 0.4 and dd < best_d:
					best_d = dd
					best = e
			if best >= 0:
				_strike_at = enemies.pos[best] + Vector3(0, 0.6, 0)
				_strike_anim = 0.3
				if pdmg > 0.0:
					enemies.poison(best, inst.def.id, pdmg, pstacks, pdur)
				if enemies.damage(best, damage * float(strike.get("damage_mult", 2.0)), inst.def.id, enemies.pos[best] - center, knock):
					inst.kills += 1
				game.fx_hit(_strike_at, inst.def)
				sfx("hit", _strike_at)
	for k in range(n):
		var a := _angle + TAU * float(k) / float(n)
		var p := center + Vector3(cos(a) * r, sin(a * 2.0) * 0.12, sin(a) * r)
		if k == 0 and _strike_anim > 0.0 and _strike_at != Vector3.INF:
			p = p.lerp(_strike_at, sin(_strike_anim / 0.3 * PI))
		_blade_mm.set_instance_transform(k, Transform3D(Basis.from_euler(Vector3(0.35, a * 6.0, 0)).scaled(Vector3(area, area, area)), p))
		for e in enemies.indices_in_radius(p, blade_r + 0.35):
			var last: float = _hit_times.get(e, -100.0)
			if now - last < hit_cd:
				continue
			_hit_times[e] = now
			var away := enemies.pos[e] - center
			if pdmg > 0.0:
				enemies.poison(e, inst.def.id, pdmg, pstacks, pdur)
			if fdmg > 0.0:
				enemies.ignite(e, inst.def.id, fdmg, fdur, fspread)
			var kdir := away
			var kforce := knock
			if side_on:
				kdir = Vector3.ZERO
				kforce = 0.0
				if now - float(_side_times.get(e, -100.0)) >= float(side.get("every", 1.0)):
					_side_times[e] = now
					# the way the blade is travelling: the ring's tangent at the blade, turned with the spin
					kdir = Vector3(-sin(a), 0.0, cos(a)) * signf(spin)
					kforce = float(side.get("force", 7.0))
			if enemies.damage(e, damage, inst.def.id, kdir, kforce):
				inst.kills += 1
				_hit_times.erase(e)
			game.fx_hit(p, inst.def)
			sfx("hit", p)
	if _ring:
		_ring.global_position = center - Vector3(0, 0.3, 0)
		_ring.rotation.y = _angle
		var t := _ring.mesh as TorusMesh
		t.inner_radius = max(r - 0.25, 0.2)
		t.outer_radius = r + 0.05
		for e in enemies.indices_in_radius(center, r + 0.5):
			var d := enemies.pos[e] - center
			d.y = 0.0
			if abs(d.length() - r) < 0.6:
				var last: float = _hit_times.get(e, -100.0)
				if now - last >= hit_cd:
					_hit_times[e] = now
					if enemies.damage(e, damage * 0.6, inst.def.id, d, knock):
						inst.kills += 1
	if _hit_times.size() > 400:
		_hit_times.clear()
	if _side_times.size() > 400:
		_side_times.clear()


func _fire() -> bool:
	return false
