## Drops stationary turrets that shoot the nearest enemy. Turret Family turrets never expire and pull gems.
class_name Spawner
extends WeaponBehavior

var _turrets: Array = []
var _turret_mesh: Mesh
var _turret_mat: Material


func _on_setup() -> void:
	var held := visual.get_node_or_null("Held")
	if held is MeshInstance3D and held.mesh:
		_turret_mesh = held.mesh
		_turret_mat = held.material_override
		held.visible = false
	else:
		var b := BoxMesh.new()
		b.size = Vector3(0.7, 0.7, 0.7)
		_turret_mesh = b
		_turret_mat = _default_material()


func _fire() -> bool:
	var amount: int = max(stat_int("amount", 1), 1)
	var max_turrets := int(inst.params.get("max_turrets", 6))
	for k in range(amount):
		var t := Turret.new()
		t.setup(self, _turret_mesh, _turret_mat)
		game.add_child(t)
		var off := Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.2, 1.2))
		var p: Vector3 = player.global_position + off
		p.y = game.map.height_at(p.x, p.z) if game.map else 0.0
		t.global_position = p
		_turrets.append(t)
	while _turrets.size() > max_turrets:
		var old: Turret = _turrets.pop_front()
		if is_instance_valid(old):
			old.expire()
	sfx("place", player.global_position)
	return true


func _tick(_delta: float) -> void:
	_turrets = _turrets.filter(func(t): return is_instance_valid(t))
