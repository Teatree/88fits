## Lobs an arcing projectile at the densest crowd. Explodes on landing. Evolution splits into bomblets.
## Bombs spread (pass 36): each bomb of a volley, and each bomb weapon, picks a crowd no other bomb is headed for or has
## just come down on (ProjectileManager.claimed_spots); they double up only when there is no other crowd in range.
## Pass 48: a grenade whose `sticky.priority` is set (the Golden Pineapple) is thrown at the strongest creature in its
## crowd (EnemyManager.priority_index) and sticks to it; `params.model` (a GLB path) draws the shot with the model's
## first mesh in its own vertex colours (the gold sphere of the visual scene stays as the fallback when the model is
## missing); a mutation that brings its own visual (Methanol's blue bottle) swaps it in when it is taken; and
## `params.death_pool {radius, seconds, max}` (the Moonshine) splashes a small pool where a creature this weapon set
## burning dies, at most `max` of them at once.
class_name Lobber
extends WeaponBehavior

## The visual scene the behaviour drew last (a mutation may bring another).
var _vis_scene: PackedScene
var _deaths_hooked := false
## Diagnostics and tests: pools splashed by a death.
var death_pools := 0
## The models' meshes by path, so a second weapon (or a swap) does not load one twice.
static var _model_meshes: Dictionary = {}


func _on_setup() -> void:
	_vis_scene = inst.visual_scene()
	_use_model()
	_hook_deaths()


## Game calls this on every build change (a mutation taken does not rebuild the behaviour): a new visual, a new hook.
func refresh_marks() -> void:
	super.refresh_marks()
	_check_visual()
	_hook_deaths()


func _exit_tree() -> void:
	var em = game.get("enemies") if is_instance_valid(game) else null
	if _deaths_hooked and is_instance_valid(em) and (em as EnemyManager).creature_dying.is_connected(_on_creature_dying):
		(em as EnemyManager).creature_dying.disconnect(_on_creature_dying)
	_deaths_hooked = false


## A mutation's visual scene (Methanol's pale blue bottle) replaces the one on the weapon when it is taken.
func _check_visual() -> void:
	if inst == null or visual == null:
		return
	var want := inst.visual_scene()
	if want == _vis_scene:
		return
	_vis_scene = want
	var old := visual
	remove_child(old)
	old.free()
	projectile_kind = -1
	_load_visual()
	_stray = visual.get_node_or_null("Familiar") as Node3D
	_use_model()


## params.model: the shot drawn with that model's first mesh, its own vertex colours lit as metal (pass 48: the Golden
## Pineapple's golden_grenade.glb), at params.model_scale. Nothing changes when the model is missing.
func _use_model() -> void:
	var path := str(inst.params.get("model", ""))
	if path == "":
		return
	var mesh: Mesh = _model_meshes.get(path)
	if mesh == null:
		if not ResourceLoader.exists(path):
			return
		var scn = load(path)
		if not scn is PackedScene:
			return
		var root: Node = (scn as PackedScene).instantiate()
		for c in root.find_children("*", "MeshInstance3D", true, false):
			if (c as MeshInstance3D).mesh:
				mesh = (c as MeshInstance3D).mesh
				break
		root.free()
		if mesh == null:
			return
		_model_meshes[path] = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.metallic = float(inst.params.get("model_metallic", 0.45))
	mat.roughness = float(inst.params.get("model_roughness", 0.35))
	projectile_kind = game.projectiles.register_kind(mesh, mat, float(inst.params.get("model_scale", 1.0)))


## The Moonshine listens for its burning creatures' deaths (EnemyManager.creature_dying).
func _hook_deaths() -> void:
	if _deaths_hooked or inst == null or game == null or game.enemies == null:
		return
	if not inst.params.get("death_pool") is Dictionary:
		return
	game.enemies.creature_dying.connect(_on_creature_dying)
	_deaths_hooked = true


## A creature this weapon set burning dies (its fire is still on it as the signal comes): a small pool of the weapon's
## fire splashes where it fell, unless `max` of them are burning already.
func _on_creature_dying(i: int, _weapon_id: String) -> void:
	if inst == null or game == null:
		return
	var dp = inst.params.get("death_pool")
	if not dp is Dictionary:
		return
	var em: EnemyManager = game.enemies
	if not (em.fire_src[i] as Dictionary).has(inst.def.id):
		return
	if death_pool_count() >= int((dp as Dictionary).get("max", 6)):
		return
	death_pools += 1
	game.spawn_cloud(em.pos[i], inst, float((dp as Dictionary).get("radius", 1.0)), "fire",
		{"pool_seconds": float((dp as Dictionary).get("seconds", 3.0)), "death_of": inst.def.id})


## How many of this weapon's death pools are burning now.
func death_pool_count() -> int:
	if not is_inside_tree():
		return 0
	var n := 0
	for c in get_tree().get_nodes_in_group(ElementCloud.DEATH_GROUP):
		if c is ElementCloud and not (c as Node).is_queued_for_deletion() and str((c as ElementCloud).params.get("death_of", "")) == inst.def.id:
			n += 1
	return n


func _fire() -> bool:
	var enemies: EnemyManager = game.enemies
	var range_m := stat("range", 10.0)
	# a poison or fire bomb looks for the thickest crowd of creatures not carrying its element; plain bombs take any crowd
	var healthy := inst.def.targeting == "densest_healthy" or inst.def.targeting == "healthy"
	var el := inst.element() if healthy else ""
	var amount: int = max(stat_int("amount", 1), 1)
	var hero := player.global_position
	var keep_r := maxf(stat("area", 2.5), 1.5)
	var taken: Array = game.projectiles.claimed_spots()
	var targets: Array = []
	for k in range(amount):
		var avoid: Array = taken + targets
		var t := enemies.densest_point(hero, range_m, el, avoid, keep_r)
		if t == Vector3.INF and el != "":
			t = enemies.densest_point(hero, range_m, "", avoid, keep_r)
		if t == Vector3.INF:
			break
		targets.append(t)
	if targets.is_empty():
		# every crowd in range is already someone's target (or there is only the one): the thickest again
		var t0 := enemies.densest_point(hero, range_m, el)
		if t0 == Vector3.INF and el != "":
			t0 = enemies.densest_point(hero, range_m, "")
		if t0 == Vector3.INF:
			var n := enemies.nearest_index(hero, range_m * 1.5)
			if n < 0:
				return false
			t0 = enemies.pos[n]
		targets.append(t0)
	# bombs left over land round the crowds found, not on the same spot
	var found := targets.size()
	while targets.size() < amount:
		var b: Vector3 = targets[targets.size() % found]
		targets.append(b + Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0)))
	# the Golden Pineapple (pass 48): at the strongest creature in each crowd, the one it will stick to
	var stp = inst.params.get("sticky")
	if stp is Dictionary and bool((stp as Dictionary).get("priority", false)):
		var reach: float = float((stp as Dictionary).get("reach", 1.4)) + 1.0
		for k in range(targets.size()):
			# a pick next to a crowd already chosen on the screen (pass 54: any of them)
			var s := enemies.priority_index(targets[k], reach, "", true)
			if s >= 0:
				targets[k] = enemies.pos[s]
	# from the companion when it has one (Needle Rain throws from the dart), else from the hero's hand
	var from: Vector3 = _stray.global_position if _stray else hero + Vector3(0, 1.2, 0)
	for target: Vector3 in targets:
		var lp: Dictionary = inst.params.duplicate()
		lp["throw_dir"] = (target - from) * Vector3(1, 0, 1)
		game.projectiles.lob(projectile_kind, from, target, stat("speed", 9.0), stat("damage", 25.0), stat("area", 2.5), inst, stat("knockback", 3.0), lp)
	sfx("fire", from)
	return true
