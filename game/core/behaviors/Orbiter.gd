## Blades orbiting the player on a tilted ring. Hits anything they touch, with a per-enemy hit cooldown.
class_name Orbiter
extends WeaponBehavior

var _blades: Array = []
var _angle := 0.0
var _hit_times: Dictionary = {}
var _ring: MeshInstance3D
var _blade_mesh: Mesh
var _blade_mat: Material


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
	if bool(inst.def.params.get("solid_ring", false)):
		_ring = MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.3
		t.outer_radius = 0.5
		_ring.mesh = t
		_ring.material_override = _blade_mat
		add_child(_ring)


func _sync_blades() -> void:
	var n: int = max(stat_int("amount", 1), 1)
	while _blades.size() < n:
		var b := MeshInstance3D.new()
		b.mesh = _blade_mesh
		if _blade_mat:
			b.material_override = _blade_mat
		add_child(b)
		_blades.append(b)
	while _blades.size() > n:
		var b: MeshInstance3D = _blades.pop_back()
		b.queue_free()


func _tick(delta: float) -> void:
	_sync_blades()
	var r := stat("orbit_radius", 2.0)
	var spin := float(inst.def.params.get("spin_speed", 2.6))
	_angle += delta * spin
	var enemies: EnemyManager = game.enemies
	var damage := stat("damage", 8.0)
	var knock := stat("knockback", 1.0)
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
	var n := _blades.size()
	for k in range(n):
		var a := _angle + TAU * float(k) / float(n)
		var p := center + Vector3(cos(a) * r, sin(a * 2.0) * 0.12, sin(a) * r)
		var b: MeshInstance3D = _blades[k]
		b.global_position = p
		b.rotation = Vector3(0.35, a * 6.0, 0)
		b.scale = Vector3.ONE * stat("area", 1.0)
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
			if enemies.damage(e, damage, inst.def.id, away, knock):
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


func _fire() -> bool:
	return false
