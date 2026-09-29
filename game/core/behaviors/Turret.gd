## A stationary turret dropped by Spawner. Shoots the nearest enemy; expires after `lifetime`.
class_name Turret
extends Node3D

var owner_behavior: WeaponBehavior
var life := 12.0
var fire_rate := 0.35
var _fire_t := 0.0
var _head: MeshInstance3D
var _magnet := false
var _expiring := false
# the stance (pass 29): "tower" stands on a tall tripod, "bunker" digs in behind sandbags with twin barrels and a
# slow traverse; params.turret {style, barrels, turn}
var _style := ""
var _barrels := 1
var _turn := 0.0
var _head_h := 0.85


func setup(b: WeaponBehavior, mesh: Mesh, mat: Material) -> void:
	owner_behavior = b
	life = b.stat("lifetime", 12.0)
	fire_rate = float(b.inst.params.get("turret_fire_rate", 0.35))
	_magnet = bool(b.inst.params.get("magnet", false))
	var tp = b.inst.params.get("turret", {})
	if tp is Dictionary:
		_style = str(tp.get("style", ""))
		_barrels = int(tp.get("barrels", 1))
		_turn = float(tp.get("turn", 0.0))
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.25, 0.25, 0.3)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.5, 0.34, 0.18)
	wood.roughness = 1.0
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color(0.72, 0.6, 0.4)
	sand.roughness = 1.0
	match _style:
		"tower":
			# three legs to a platform, the gun on top: higher, further
			_head_h = 1.95
			for k in range(3):
				var a := TAU * float(k) / 3.0
				var leg := MeshInstance3D.new()
				var lm := CylinderMesh.new()
				lm.top_radius = 0.05
				lm.bottom_radius = 0.07
				lm.height = 1.9
				lm.radial_segments = 6
				leg.mesh = lm
				leg.material_override = wood
				leg.position = Vector3(cos(a) * 0.22, 0.9, sin(a) * 0.22)
				leg.rotation = Vector3(-sin(a) * 0.22, 0, cos(a) * 0.22)
				add_child(leg)
			var plat := MeshInstance3D.new()
			var pm := CylinderMesh.new()
			pm.top_radius = 0.42
			pm.bottom_radius = 0.42
			pm.height = 0.08
			pm.radial_segments = 8
			plat.mesh = pm
			plat.material_override = wood
			plat.position.y = 1.75
			add_child(plat)
			var box := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.36, 0.3, 0.36)
			box.mesh = bm
			box.material_override = mat if mat else hmat
			box.position.y = 1.94
			add_child(box)
			_head_h = 2.05
		"bunker":
			# a ring of sandbags, the body low inside, twin barrels
			_head_h = 0.55
			var bags := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.42
			tm.outer_radius = 0.78
			tm.rings = 16
			tm.ring_segments = 6
			bags.mesh = tm
			bags.material_override = sand
			bags.position.y = 0.16
			bags.scale = Vector3(1, 0.55, 1)
			add_child(bags)
			var body := MeshInstance3D.new()
			var bm2 := BoxMesh.new()
			bm2.size = Vector3(0.5, 0.36, 0.5)
			body.mesh = bm2
			body.material_override = mat if mat else hmat
			body.position.y = 0.2
			add_child(body)
		_:
			var base := MeshInstance3D.new()
			base.mesh = mesh
			if mat:
				base.material_override = mat
			base.position.y = 0.35
			add_child(base)
	_head = MeshInstance3D.new()
	var head_root := _head
	if _barrels >= 2:
		# two barrels side by side on one mount
		var mount := BoxMesh.new()
		mount.size = Vector3(0.42, 0.2, 0.3)
		_head.mesh = mount
		for side in [-1.0, 1.0]:
			var bar := MeshInstance3D.new()
			var bmm := BoxMesh.new()
			bmm.size = Vector3(0.12, 0.12, 0.8)
			bar.mesh = bmm
			bar.material_override = hmat
			bar.position = Vector3(side * 0.13, 0.0, -0.25)
			_head.add_child(bar)
	else:
		var hm := BoxMesh.new()
		hm.size = Vector3(0.25, 0.25, 0.7)
		_head.mesh = hm
	_head.material_override = hmat
	_head.position.y = _head_h
	add_child(head_root)
	scale = Vector3(0.1, 0.1, 0.1)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func expire() -> void:
	if _expiring:
		return
	_expiring = true
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(0.05, 0.05, 0.05), 0.3)
	tw.tween_callback(queue_free)


func _process(delta: float) -> void:
	if owner_behavior == null or owner_behavior.game == null or owner_behavior.game.paused:
		return
	if _expiring:
		return
	life -= delta
	if life <= 0.0:
		expire()
		return
	var game = owner_behavior.game
	if _magnet:
		game.pickups.add_attractor(global_position, 4.0)
	_fire_t -= delta
	if _fire_t > 0.0:
		return
	var enemies: EnemyManager = game.enemies
	var rng := owner_behavior.stat("range", 8.0)
	var t := enemies.nearest_index(global_position, rng)
	if t < 0:
		_fire_t = 0.1
		return
	# Berserk: a turret's own clock runs with the hero's weapon speed
	_fire_t = fire_rate / maxf(Run.haste, 1.0)
	var from := global_position + Vector3(0, _head_h, 0)
	var dir := enemies.pos[t] + Vector3(0, 0.4, 0) - from
	dir = dir.normalized()
	if _turn > 0.0:
		# a slow traverse: the head swings towards the target at `turn` rad/s and fires when it is close enough
		var want_yaw := atan2(-dir.x, -dir.z)
		var cur := _head.rotation.y
		var step: float = _turn * maxf(fire_rate, 0.05)
		_head.rotation.y = cur + clampf(angle_difference(cur, want_yaw), -step, step)
		if absf(angle_difference(_head.rotation.y, want_yaw)) > 0.25:
			_fire_t = 0.05
			return
		dir = Vector3(-sin(_head.rotation.y), dir.y, -cos(_head.rotation.y)).normalized()
	else:
		_head.look_at(from + dir, Vector3.UP)
	var speed := owner_behavior.stat("speed", 16.0)
	var pierce := owner_behavior.stat_int("pierce", 0)
	var kb := owner_behavior.stat("knockback", 0.3)
	var side := Vector3(-dir.z, 0, dir.x).normalized()
	for b in range(maxi(_barrels, 1)):
		var off: Vector3 = side * ((float(b) - float(_barrels - 1) * 0.5) * 0.26) if _barrels > 1 else Vector3.ZERO
		game.projectiles.fire(owner_behavior.projectile_kind, from + off, dir * speed, owner_behavior.stat("damage", 4.0), pierce, 0.2, rng / speed, owner_behavior.inst, kb)
	owner_behavior.sfx("fire", from)
