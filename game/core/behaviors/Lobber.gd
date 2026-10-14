## Lobs an arcing projectile at the densest crowd. Explodes on landing. Evolution splits into bomblets.
## Bombs spread (pass 36): each bomb of a volley, and each bomb weapon, picks a crowd no other bomb is headed for or has
## just come down on (ProjectileManager.claimed_spots); they double up only when there is no other crowd in range.
## Pass 48: a grenade whose `sticky.priority` is set (the Golden Pineapple) is thrown at the strongest creature in its
## crowd (EnemyManager.priority_index) and sticks to it; `params.model` (a GLB path) draws the shot with the model's
## first mesh in its own vertex colours (the gold sphere of the visual scene stays as the fallback when the model is
## missing); a mutation that brings its own visual (Methanol's blue bottle) swaps it in when it is taken; and
## `params.death_pool {radius, seconds, max}` (the Moonshine) splashes a small pool where a creature this weapon set
## burning dies, at most `max` of them at once.
## Pass 62, Solenne's Sun Cocktail (Garry: "add a small explosion to Molotovs. Those have a weak knockback and deal extra
## damage on the explosion ... the Molotov projectiles as kind of imbued with sun energy, so they shine ... And the little
## sun puff should accompany the Molotov's when they 'explode'"): `params.land_blast {damage_frac, radius_frac, knockback,
## look}` bursts where a shot comes down (land_blast, called by ProjectileManager._explode, bomblets and bursts never):
## damage_frac of the weapon's damage to everything within radius_frac of its area, thrown out `knockback` (weak: a
## third of a grenade's), the fire pool as before; look "sun" puffs a little sun there (Fx.sun_puff) with a gold ring
## racing out over the sand. `params.halo {size, color, strength, pulse, motes}` hangs a sunburst (the chest's shine,
## mode 0) on every shot of the weapon while it flies and drops gold motes behind it every `motes` seconds; the shot
## itself shines through `params.tint` (shot_kind: a gold emissive bottle).
## Pass 76 (lane DYN, the dynamite): `params.models {<form>: {<colour>: "res://...glb", "tip": [x, y, z]}}` with
## `params.model_form` ("stick") and `params.model_colour` ("tan") pick the model the shot is drawn with (a look's sticks
## and bundles, tan or red: Dynamite Bundle sets the form, Coffin Nails the colour), falling back to `params.model`; a
## mutation taken or a look switched re-models the weapon (refresh_model). The fuse's spark sits at the model's `tip`
## (or `params.fuse_tip`; ProjectileManager's fuse, model_choice).
class_name Lobber
extends WeaponBehavior

## The visual scene the behaviour drew last (a mutation may bring another).
var _vis_scene: PackedScene
var _deaths_hooked := false
## Diagnostics and tests: pools splashed by a death.
var death_pools := 0
## The models' meshes by path, so a second weapon (or a swap) does not load one twice.
static var _model_meshes: Dictionary = {}
## Pass 76 (lane DYN): the model drawn now ("" for the visual's own shot), the visual's own kind (back when no model is
## chosen any more), the kinds this weapon registered for its models (by path and finish, made once each), and which
## model files exist (a missing one falls back to params.model).
var _model_path := ""
var _visual_kind := -1
var _model_kinds: Dictionary = {}
static var _model_exists: Dictionary = {}
## Pass 62 (params.halo): the sunbursts riding the shots in flight (one each, made as needed, hidden when spare), the
## shots they ride ([projectile index, stamp]: a freed slot taken by another shot no longer carries the stamp), the
## stamp the next shot gets, the clock the motes keep; halos hung and land blasts made (tests).
var _halos: Array = []
var _flying: Array = []
static var _stamp := 0
var _mote_t := 0.0
var halo_shots := 0
static var land_blasts := 0
## A land blast's ring racing out over the sand (look "sun"): RING_MULT x its radius over RING_TIME.
const RING_MULT := 1.5
const RING_TIME := 0.32
const SUN_GOLD := Color(1.0, 0.82, 0.3)
## The gold motes a haloed shot drops behind it (params.halo.motes seconds apart), this big.
const MOTE_SIZE := 0.22


func _on_setup() -> void:
	_vis_scene = inst.visual_scene()
	_use_model()
	_hook_deaths()


## Game calls this on every build change (a mutation taken does not rebuild the behaviour): a new visual, a new hook.
func refresh_marks() -> void:
	super.refresh_marks()
	_check_visual()
	# pass 76: a mutation that changes the model's form or colour (Dynamite Bundle, Coffin Nails) re-models the shot
	refresh_model()
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
## Pineapple's golden_grenade.glb), at params.model_scale. Nothing changes when the model is missing. Pass 76: the model
## is model_choice's (params.models by form and colour, else params.model), each one registered once per weapon; a
## weapon whose model goes away (a look without one) is drawn with its visual's own shot again.
func _use_model() -> void:
	var path := model_path()
	# the visual's own kind, whenever the kind drawn now is none of this weapon's models
	if projectile_kind >= 0 and not _model_kinds.values().has(projectile_kind):
		_visual_kind = projectile_kind
	if path == "":
		if _model_path != "" and _visual_kind >= 0:
			projectile_kind = _visual_kind
		_model_path = ""
		return
	# a missing model is not tried again until the choice changes
	_model_path = path
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
	var metallic := float(inst.params.get("model_metallic", 0.45))
	var roughness := float(inst.params.get("model_roughness", 0.35))
	var msc := float(inst.params.get("model_scale", 1.0))
	var key := "%s|%s|%s|%s" % [path, metallic, roughness, msc]
	if _model_kinds.has(key):
		projectile_kind = int(_model_kinds[key])
		return
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.metallic = metallic
	mat.roughness = roughness
	projectile_kind = game.projectiles.register_kind(mesh, mat, msc)
	_model_kinds[key] = projectile_kind


## The model the shot is drawn with now (pass 76, model_choice): "" for the visual's own shot.
func model_path() -> String:
	if inst == null:
		return ""
	return str(model_choice(inst.params)["path"])


## Pass 76 (lane DYN): re-models the shot when its params now choose another model: a mutation taken (Dynamite Bundle's
## form, Coffin Nails' colour) or a look switched (lane LOOKS calls this). Nothing happens when the choice is the same.
func refresh_model() -> void:
	if inst == null or game == null or game.get("projectiles") == null:
		return
	if model_path() != _model_path:
		_use_model()


## The model a shot of params `p` is drawn with, and its fuse's tip (pass 76): {"path": params.models[model_form]
## [model_colour] ("stick" and "tan" when unset) when that file exists, else params.model ("" for none); "tip": that
## form's `tip`, else params.fuse_tip, as a Vector3 in the model's own space (Vector3.INF when none is given: the
## mesh's top, ProjectileManager.fuse_tip)}.
static func model_choice(p: Dictionary) -> Dictionary:
	var fallback_tip := _vec3(p.get("fuse_tip"), Vector3.INF)
	var ms = p.get("models")
	if ms is Dictionary:
		var f = (ms as Dictionary).get(str(p.get("model_form", "stick")))
		if f is Dictionary:
			var path := str((f as Dictionary).get(str(p.get("model_colour", "tan")), ""))
			if path != "" and _model_file_exists(path):
				return {"path": path, "tip": _vec3((f as Dictionary).get("tip"), fallback_tip)}
	return {"path": str(p.get("model", "")), "tip": fallback_tip}


static func _model_file_exists(path: String) -> bool:
	if not _model_exists.has(path):
		_model_exists[path] = ResourceLoader.exists(path)
	return bool(_model_exists[path])


## [x, y, z] (or a Vector3) as a Vector3, else `fallback`.
static func _vec3(v, fallback: Vector3) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return fallback


## The kind a bomb is drawn with (pass 61): the visual's (or the model's), in a mutation's `params.tint` when it brings one
## (Sticky's glossy amber resin, ProjectileManager.tinted_kind; the Golden Pineapple's own `final.tint` keeps its gold).
func shot_kind() -> int:
	var tint = inst.params.get("tint") if inst else null
	if tint is Dictionary and projectile_kind >= 0 and game.projectiles.has_method("tinted_kind"):
		return game.projectiles.tinted_kind(projectile_kind, tint)
	return projectile_kind


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
	# pass 73 (lane SNIPER): the first bomb goes for a special, an Elite or the boss within reach; the rest find crowds of
	# their own as before (its spot among the ones they keep away from)
	var pt: int = priority_pick(hero, range_m)
	if pt >= 0:
		targets.append(enemies.pos[pt])
	for k in range(amount - targets.size()):
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
	var k_draw := shot_kind()
	var haloed := not _halo().is_empty()
	for target: Vector3 in targets:
		var lp: Dictionary = inst.params.duplicate()
		lp["throw_dir"] = (target - from) * Vector3(1, 0, 1)
		# a shot that wears a halo (pass 62, Sun Cocktail) is stamped, so the halo knows it by its slot
		if haloed:
			_stamp += 1
			lp["halo_id"] = _stamp
		var j: int = game.projectiles.lob(k_draw, from, target, stat("speed", 9.0), stat("damage", 25.0), stat("area", 2.5), inst, stat("knockback", 3.0), lp)
		if haloed and j >= 0:
			_flying.append([j, _stamp])
			halo_shots += 1
	sfx("fire", from)
	return true


# ---------------------------------------------------------------- Sun Cocktail (pass 62)

## params.halo, {} without it.
func _halo() -> Dictionary:
	var h = inst.params.get("halo") if inst else null
	return h if h is Dictionary else {}


func _tick(delta: float) -> void:
	_tick_halos(delta)


## Every shot in flight that wears a halo carries a sunburst on it, pulsing, and drops gold motes behind it; a shot that
## came down (its slot freed, or taken by another shot without its stamp) lets its halo go.
func _tick_halos(delta: float) -> void:
	if _flying.is_empty():
		for q: MeshInstance3D in _halos:
			q.visible = false
		return
	var pm = game.get("projectiles") if game else null
	if pm == null:
		return
	for k in range(_flying.size() - 1, -1, -1):
		var j: int = int(_flying[k][0])
		if j < 0 or j >= pm.alive.size() or pm.alive[j] == 0:
			_flying.remove_at(k)
			continue
		var ex = pm.extra[j]
		if not ex is Dictionary or int((ex as Dictionary).get("halo_id", -1)) != int(_flying[k][1]):
			_flying.remove_at(k)
	var h := _halo()
	var col := Color(str(h.get("color", "#FFE08A")))
	var size := float(h.get("size", 1.3))
	var strength := float(h.get("strength", 1.1))
	var pulse := float(h.get("pulse", 0.25))
	while _halos.size() < _flying.size():
		var nq := Chest.shine_quad(0, Vector2(size, size), col, strength)
		nq.top_level = true
		add_child(nq)
		_halos.append(nq)
	var every := float(h.get("motes", 0.05))
	_mote_t -= delta
	var drop := every > 0.0 and _mote_t <= 0.0
	if drop:
		_mote_t = every
	var fx = game.get("fx")
	var t := float(Time.get_ticks_msec()) * 0.001
	for k in range(_halos.size()):
		var q: MeshInstance3D = _halos[k]
		if k >= _flying.size():
			q.visible = false
			continue
		var at: Vector3 = pm.pos[int(_flying[k][0])]
		q.visible = true
		q.global_position = at
		(q.material_override as ShaderMaterial).set_shader_parameter("strength", strength * (1.0 + pulse * sin(t * 18.0 + float(k) * 2.1)))
		if drop and fx and fx.has_method("mote"):
			fx.mote(at + Vector3(randf_range(-0.15, 0.15), randf_range(-0.1, 0.1), randf_range(-0.15, 0.15)), Vector3(0, randf_range(0.4, 1.0), 0), randf_range(0.3, 0.45), MOTE_SIZE, Color(col.r, col.g, col.b, 0.9))


## How many halos are riding shots now (tests).
func halos_live() -> int:
	var n := 0
	for q: MeshInstance3D in _halos:
		if q.visible:
			n += 1
	return n


## A small blast where a shot of `w` came down at `at` (its `area` the pool's radius), from params.land_blast; nothing
## for a bomblet or a burst, or without one. Returns how many it hit, -1 when there was none. ProjectileManager._explode
## calls it right after the shot's own blast.
static func land_blast(game: Node, at: Vector3, w: WeaponInstance, area: float, ex: Dictionary = {}) -> int:
	if game == null or w == null:
		return -1
	var lb = w.params.get("land_blast")
	if not lb is Dictionary or ex.has("is_bomblet") or ex.has("is_burst"):
		return -1
	var d: Dictionary = lb
	var r := maxf(area * float(d.get("radius_frac", 0.9)), 0.3)
	var dmg := w.stat("damage", 8.0) * float(d.get("damage_frac", 1.0))
	var em: EnemyManager = game.get("enemies")
	var n: int = em.damage_radius(at, r, dmg, w.def.id, float(d.get("knockback", 2.4))) if em else 0
	land_blasts += 1
	if str(d.get("look", "")) == "sun":
		var fx = game.get("fx")
		if fx and fx.has_method("sun_puff"):
			fx.sun_puff(at, r, SUN_GOLD)
		var tg = game.get("telegraphs")
		if tg and tg.has_method("race_ring"):
			tg.race_ring(at, r * RING_MULT, RING_TIME, Color(SUN_GOLD.r, SUN_GOLD.g, SUN_GOLD.b, 0.8), 0.25)
		# the sand glows hot under it a moment, as under the Sun Scepter's pillar
		if tg and tg.has_method("scorch"):
			tg.scorch(at, r * SunScepter.IMPACT_GLOW, SunScepter.IMPACT_GLOW_INNER, SunScepter.IMPACT_GLOW_OUTER, SunScepter.IMPACT_GLOW_HOLD, SunScepter.IMPACT_GLOW_FADE)
		var snd := str(d.get("sound", "w_sun_strike"))
		if snd != "":
			Audio.play(snd, at, float(d.get("volume_db", -4.0)))
	return n
