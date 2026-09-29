## A land mine on the ground: a low disc that blinks, and explodes when a creature steps on it.
class_name Mine
extends Node3D

var owner_behavior: WeaponBehavior
var damage := 25.0
var area := 2.2
var knockback := 6.0
var life := 25.0
var trigger := 0.7
var _t := 0.0
var _mi: MeshInstance3D
var _lamp: MeshInstance3D
var _lamp_mat: StandardMaterial3D
var _leaping := false


func setup(b: WeaponBehavior, mesh: Mesh, mat: Material, p_damage: float, p_area: float, p_knockback: float, p_life: float, p_trigger: float) -> void:
	owner_behavior = b
	damage = p_damage
	area = p_area
	knockback = p_knockback
	life = p_life
	trigger = p_trigger
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
	_lamp_mat.albedo_color = Color(1.0, 0.2, 0.15)
	_lamp.material_override = _lamp_mat
	_lamp.position.y = 0.2
	add_child(_lamp)
	scale = Vector3(0.3, 0.3, 0.3)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	var game: Node = owner_behavior.game if owner_behavior else null
	if game == null or game.paused:
		return
	_t += delta
	life -= delta
	_lamp_mat.albedo_color = Color(1.0, 0.2, 0.15) if int(_t * 3.0) % 2 == 0 else Color(0.5, 0.1, 0.08)
	if life <= 0.0:
		queue_free()
		return
	var em: EnemyManager = game.enemies
	if _leaping:
		return
	if em.nearest_index(global_position, trigger) >= 0:
		var leap = owner_behavior.inst.params.get("leap") if owner_behavior and owner_behavior.inst else null
		if leap is Dictionary:
			# Bouncing Betty: up first, then the blast, wider and harder
			_leaping = true
			area *= float(leap.get("radius_mult", 1.5))
			knockback *= float(leap.get("kb_mult", 2.0))
			var tw := create_tween()
			tw.tween_property(self, "position:y", position.y + float(leap.get("height", 1.2)), float(leap.get("seconds", 0.22))).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_callback(_explode)
			return
		_explode()


func _explode() -> void:
	var game: Node = owner_behavior.game
	var em: EnemyManager = game.enemies
	var w: WeaponInstance = owner_behavior.inst
	var before := Run.kills
	em.damage_radius(global_position, area, damage, w.def.id if w else "", knockback)
	if w:
		w.kills += Run.kills - before
		# Napalm Mine: the crater burns (or fumes); Blasting Cap: a mine that kills pays a nugget
		var el: String = w.element()
		if el != "":
			for e in em.indices_in_radius(global_position, area):
				if el == "fire":
					em.ignite(e, w.def.id, w.stat("fire_damage", 4.0), w.stat("fire_duration", 1.8), w.stat("fire_spread", 0.4))
				else:
					em.poison(e, w.def.id, w.stat("poison_damage", 3.0), maxi(w.stat_int("poison_stacks", 1), 1), w.stat("poison_duration", 8.0))
			game.spawn_cloud(global_position, w, area * 0.8, el)
		if Run.kills > before and int(w.params.get("gold_on_kill", 0)) > 0:
			game.pickups.spawn(PickupManager.KIND_COIN, global_position, 3.0)
	game.fx_burst(global_position + Vector3(0, 0.3, 0), Color(1.0, 0.72, 0.3), area)
	game.camera.shake(0.5)
	if owner_behavior:
		owner_behavior.sfx("hit", global_position)
	queue_free()
