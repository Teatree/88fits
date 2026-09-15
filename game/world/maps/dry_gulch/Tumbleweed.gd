## Decorative tumbleweed: rolls with the wind, bounces off the arena wall, respawns upwind.
class_name Tumbleweed
extends MeshInstance3D

var wind := Vector3(1, 0, 0.3)
var arena_radius := 66.0
var map: MapBase
var _speed := 3.0
var _radius := 0.6


func setup(p_map: MapBase, p_wind: Vector3, r: float) -> void:
	map = p_map
	wind = p_wind.normalized()
	_radius = r
	arena_radius = p_map.arena_radius
	_speed = randf_range(2.0, 4.0)
	if ResourceLoader.exists("res://art/props/tumbleweed.glb"):
		var vis: Node3D = load("res://art/props/tumbleweed.glb").instantiate()
		vis.scale = Vector3.ONE * (r / 0.8)
		vis.position.y = -r
		add_child(vis)
	else:
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = 8
		m.rings = 5
		mesh = m
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.72, 0.53, 0.25)
		material_override = mat


func _physics_process(delta: float) -> void:
	var v := wind * _speed + Vector3(sin(Time.get_ticks_msec() * 0.001 + position.x), 0, 0) * 0.4
	# a short ray ahead: mesas, rocks, the wreck and the wall bounce the ball instead of swallowing it
	var space := get_world_3d().direct_space_state
	if space:
		var q := PhysicsRayQueryParameters3D.create(global_position, global_position + v.normalized() * (_radius + 0.4))
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var nrm: Vector3 = hit["normal"]
			nrm.y = 0.0
			if nrm.length_squared() > 0.01:
				wind = wind.bounce(nrm.normalized()).normalized()
				v = wind * _speed
	global_position += v * delta
	rotate(Vector3(wind.z, 0, -wind.x).normalized(), delta * _speed / max(_radius, 0.2))
	var flat := Vector2(global_position.x, global_position.z)
	if flat.length() > arena_radius - 2.0:
		flat = -flat.normalized() * (arena_radius - 4.0)
		global_position = Vector3(flat.x, 0, flat.y)
		Audio.play("wd_tumbleweed", global_position)
	if map:
		global_position.y = map.height_at(global_position.x, global_position.z) + _radius
