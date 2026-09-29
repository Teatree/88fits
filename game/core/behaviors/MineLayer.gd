## Drops a mine where the hero walks. A mine waits on the ground until a creature steps on it, then explodes with the
## weapon's damage and area; old mines beyond params.max_mines are removed, and every mine expires after `lifetime`.
class_name MineLayer
extends WeaponBehavior

var _mines: Array = []
var _mine_mesh: Mesh
var _mine_mat: Material


func _on_setup() -> void:
	var held := visual.get_node_or_null("Held")
	if held is MeshInstance3D and held.mesh:
		_mine_mesh = held.mesh
		_mine_mat = held.material_override
		held.visible = false
	else:
		var c := CylinderMesh.new()
		c.top_radius = 0.28
		c.bottom_radius = 0.34
		c.height = 0.16
		c.radial_segments = 10
		_mine_mesh = c
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.36, 0.42, 0.28)
		_mine_mat = m


func _fire() -> bool:
	var amount: int = max(stat_int("amount", 1), 1)
	var max_mines := int(inst.params.get("max_mines", 8))
	for k in range(amount):
		var mine := Mine.new()
		mine.setup(self, _mine_mesh, _mine_mat, stat("damage", 25.0), stat("area", 2.2), stat("knockback", 6.0), stat("lifetime", 25.0), float(inst.params.get("trigger_radius", 0.7)))
		game.add_child(mine)
		var off := Vector3.ZERO
		if k > 0:
			off = Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
		var p: Vector3 = player.global_position + off
		p.y = game.map.height_at(p.x, p.z) if game.map else 0.0
		mine.global_position = p
		_mines.append(mine)
	while _mines.size() > max_mines:
		var old: Mine = _mines.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	sfx("place", player.global_position)
	return true


func _tick(_delta: float) -> void:
	_mines = _mines.filter(func(m): return is_instance_valid(m))
