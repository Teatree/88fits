## Base for reusable weapon behaviour primitives. A WeaponDef names one of these and a visual scene;
## the behaviour reads its numbers from the WeaponInstance StatSheet every frame, so level-ups and
## passives apply instantly.
class_name WeaponBehavior
extends Node3D

var inst: WeaponInstance
var game: Node
var player: Node3D
var visual: Node3D
var cooldown_left := 0.0
var projectile_kind := -1


func setup(p_inst: WeaponInstance, p_game: Node) -> void:
	inst = p_inst
	game = p_game
	player = p_game.player
	_load_visual()
	_on_setup()


func _load_visual() -> void:
	if inst.def.visual:
		visual = inst.def.visual.instantiate()
	else:
		visual = Node3D.new()
	add_child(visual)
	var proj := visual.get_node_or_null("Projectile")
	if proj is MeshInstance3D and proj.mesh:
		var mat: Material = proj.material_override
		if mat == null and proj.mesh.get_surface_count() > 0:
			mat = proj.mesh.surface_get_material(0)
		projectile_kind = game.projectiles.register_kind(proj.mesh, mat, proj.scale.x)
		proj.visible = false
	if projectile_kind < 0:
		projectile_kind = game.projectiles.register_kind(_default_mesh(), _default_material(), 1.0)
	var held := visual.get_node_or_null("Held")
	if held:
		held.visible = _shows_held()


func _default_mesh() -> Mesh:
	var m := SphereMesh.new()
	m.radius = 0.15
	m.height = 0.3
	m.radial_segments = 8
	m.rings = 4
	return m


func _default_material() -> Material:
	var mat := StandardMaterial3D.new()
	var ph: Dictionary = inst.def.placeholder
	mat.albedo_color = Color(str(ph.get("color", "#FFE08A")))
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = 0.8
	return mat


func _shows_held() -> bool:
	return false


func _on_setup() -> void:
	pass


func stat(name: String, default: float = 0.0) -> float:
	return inst.stat(name, default)


func stat_int(name: String, default: int = 0) -> int:
	return inst.stat_int(name, default)


func sfx(event: String, at: Vector3 = Vector3.INF) -> void:
	var id := str(inst.def.sfx.get(event, ""))
	if id != "":
		Audio.play(id, at)


func muzzle_flash(at: Vector3 = Vector3.INF) -> void:
	var m := visual.get_node_or_null("Muzzle")
	if m is CPUParticles3D or m is GPUParticles3D:
		m.global_position = at if at != Vector3.INF else player.aim_origin(player.forward())
		m.restart()
		m.emitting = true


func _process(delta: float) -> void:
	if game == null or player == null or player.dead or game.paused:
		return
	var t0 := Time.get_ticks_usec()
	cooldown_left -= delta
	_tick(delta)
	if cooldown_left <= 0.0:
		if _fire():
			cooldown_left = max(stat("cooldown", 1.0), 0.05)
		else:
			cooldown_left = 0.15
	Perf.add("weapons", t0)


func _tick(_delta: float) -> void:
	pass


## Return true if something happened (starts the cooldown).
func _fire() -> bool:
	return false
