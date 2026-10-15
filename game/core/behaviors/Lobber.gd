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
## Pass 79 (lane WORLD): `params.lead` throws ahead of the crowd, where it will be when the bomb blows (lead_spot).
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
	# (pass 79: such a throw is never led, `unled`)
	var unled: Array = []
	unled.resize(targets.size())
	unled.fill(false)
	var stp = inst.params.get("sticky")
	if stp is Dictionary and bool((stp as Dictionary).get("priority", false)):
		var reach: float = float((stp as Dictionary).get("reach", 1.4)) + 1.0
		for k in range(targets.size()):
			# a pick next to a crowd already chosen on the screen (pass 54: any of them)
			var s := enemies.priority_index(targets[k], reach, "", true)
			if s >= 0:
				targets[k] = enemies.pos[s]
				unled[k] = true
	# from the companion when it has one (Needle Rain throws from the dart), else from the hero's hand
	var from: Vector3 = _stray.global_position if _stray else hero + Vector3(0, 1.2, 0)
	var k_draw := shot_kind()
	var haloed := not _halo().is_empty()
	for k in range(targets.size()):
		var target: Vector3 = _lead_target(targets[k], from, hero, range_m, pt if k == 0 else -1, bool(unled[k]))
		var lp: Dictionary = inst.params.duplicate()
		lp["throw_dir"] = (target - from) * Vector3(1, 0, 1)
		# pass 79: a led throw keeps the crowd's spot at the throw too, a spot the other bombs keep away from as well
		if not target.is_equal_approx(targets[k]):
			lp["lead_from"] = targets[k]
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


# ---------------------------------------------------------------- the lead (pass 79, lane WORLD)

## Pass 79 (lane WORLD; Garry: "Throw the dynamite in front of the enemies"): `params.lead` throws a bomb where its crowd
## will be when it blows, not where it stood when it was chosen (the Dynamite Stick lies FUSE seconds on the sand first,
## and the crowd walking at the hero had passed the spot by then). The wait is the lob's flight as ProjectileManager.lob
## times it plus the fuse's seconds (a Sticky bomb only the flight: it rides whatever it catches). Three ways to foresee
## the crowd (`mode`):
##   "chase": the crowd walks at the hero. It closes on where he will be partway through the wait (his position plus his
##     velocity times `hero_ahead` x the wait) at its mean walking speed (EnemyManager.crowd_speed within `radius` m of
##     the spot; a priority target's own), for the wait, times `share`, and stops `gap` m short of him.
##   "walk": the crowd goes on as it walks now: its mean velocity (EnemyManager.crowd_velocity; a priority target's own,
##     walk_velocity) times the wait times `share`, drawn back to `gap` m from the hero where it would pass him.
##   "predict" (the default): the chase lead is the far end of a short line from the spot chosen; LEAD_STEPS + 1 spots
##     along it are scored by how many creatures will stand inside the blast there when it goes off (EnemyManager.
##     predicted_counts: each creature near closes on where the hero will be at its own pace, stopping `gap` short of
##     him) and the bomb goes to the best; on a tie, the one further ahead.
## The lead is at most `max` m; the spot stays within the weapon's range of the hero and inside the arena; no lead when
## the crowd is within `gap` of him already. A Sticky throw at a priority target (the Golden Pineapple's) is never led.
## `lead`: a number (the share, 1 = all of it, 0 = off), true, or {share, mode, max, gap, radius, hero_ahead}. Weapons
## without it throw where they did. Why predict: scored on the same blasts in the game (tools/_p79_WORLD_lead_probe.gd,
## the paired count), a plain lead caught about as many as none (the crowd near the hero is a stream, the blast wider
## than the lead), the best-scored spot clearly more.
const LEAD_MAX := 6.0
const LEAD_GAP := 1.5
const LEAD_RADIUS := 3.0
const LEAD_HERO_AHEAD := 0.5
## "predict": the spots scored between the spot chosen and the full chase lead are LEAD_STEPS + 1 (0, 1/4, ... all of it).
const LEAD_STEPS := 4
## Diagnostics and tests: throws led, and the last lead in metres (on the ground).
var leads := 0
var last_lead := 0.0


## params.lead as {share, mode ("predict" | "chase" | "walk"), max, gap, radius, hero_ahead} (share 0 = off).
static func lead_config(p: Dictionary) -> Dictionary:
	var out := {"share": 0.0, "mode": "predict", "max": LEAD_MAX, "gap": LEAD_GAP, "radius": LEAD_RADIUS, "hero_ahead": LEAD_HERO_AHEAD}
	var l = p.get("lead")
	if l is bool:
		out["share"] = 1.0 if l else 0.0
	elif l is float or l is int:
		out["share"] = float(l)
	elif l is Dictionary:
		out["share"] = 1.0
		for k: String in ["share", "max", "gap", "radius", "hero_ahead"]:
			var v = (l as Dictionary).get(k)
			if v is float or v is int:
				out[k] = float(v)
		var md := str((l as Dictionary).get("mode", "predict"))
		if md == "walk" or md == "chase":
			out["mode"] = md
	out["share"] = maxf(float(out["share"]), 0.0)
	return out


## Where a bomb meant for `target` lands with the lead: `v` the crowd's mean ground velocity (m/s), `pace` its mean walking
## speed (m/s; -1 = v's length), `speed` the lob's, `fuse` the seconds it lies before it blows (0 for a Sticky bomb), `cfg`
## lead_config's, `hero` and `hero_v` where the hero is and how he moves, `range_m` the weapon's reach, `arena_r` the
## arena's radius (0 = none). `target` itself when the share is 0 or the crowd stands still.
static func lead_spot(target: Vector3, from: Vector3, v: Vector3, speed: float, fuse: float, cfg: Dictionary, hero: Vector3, range_m: float, arena_r: float, hero_v := Vector3.ZERO, pace := -1.0) -> Vector3:
	var share := float(cfg.get("share", 0.0))
	v.y = 0.0
	# "predict" takes the chase's spot as the far end of its line (_lead_target scores the way there)
	var chase := str(cfg.get("mode", "predict")) != "walk"
	var walk := pace if pace >= 0.0 else v.length()
	if share <= 0.0 or (chase and walk < 0.01) or (not chase and v.length_squared() < 0.0001):
		return target
	var mx := float(cfg.get("max", LEAD_MAX))
	var gap := float(cfg.get("gap", LEAD_GAP))
	if Vector2(target.x - hero.x, target.z - hero.z).length() <= gap:
		return target
	var aim := target
	# the flight depends on the distance and the distance on the lead: twice round is near enough
	for _k in range(2):
		var dist := maxf(Vector2(aim.x - from.x, aim.z - from.z).length(), 0.5)
		var t := clampf(dist / maxf(speed, 1.0), 0.35, 2.5) + maxf(fuse, 0.0)
		var off := v * (t * share)
		if chase:
			var goal := hero + hero_v * (t * float(cfg.get("hero_ahead", LEAD_HERO_AHEAD)))
			var to := Vector2(goal.x - target.x, goal.z - target.z)
			var step := minf(walk * t * share, maxf(to.length() - gap, 0.0))
			off = Vector3(to.x, 0.0, to.y).normalized() * step if to.length() > 0.001 else Vector3.ZERO
		if off.length() > mx:
			off = off.normalized() * mx
		aim = target + off
	if not chase:
		aim = _keep_gap(target, aim, hero, gap)
	var fl := Vector2(aim.x - hero.x, aim.z - hero.z)
	if range_m > 0.0 and fl.length() > range_m:
		fl = fl.normalized() * range_m
		aim = Vector3(hero.x + fl.x, aim.y, hero.z + fl.y)
	var ar := Vector2(aim.x, aim.z)
	if arena_r > 0.0 and ar.length() > arena_r:
		ar = ar.normalized() * arena_r
		aim = Vector3(ar.x, aim.y, ar.y)
	return aim


## Mode "predict": the index of the best of `counts` (the creatures foreseen inside the blast at each spot), the later
## (further ahead) on a tie.
static func predict_pick(counts: PackedInt32Array) -> int:
	var best := 0
	for k in range(counts.size()):
		if counts[k] >= counts[best]:
			best = k
	return best


## The led spot drawn back along the lead to the first point `gap` m from the hero (the crowd stops at him); `target` when
## the crowd is that near already, `aim` when the lead never comes that near.
static func _keep_gap(target: Vector3, aim: Vector3, hero: Vector3, gap: float) -> Vector3:
	if gap <= 0.0:
		return aim
	var d := Vector2(target.x - hero.x, target.z - hero.z)
	if d.length() <= gap:
		return target
	var l := Vector2(aim.x - target.x, aim.z - target.z)
	var a := l.dot(l)
	if a < 0.000001:
		return aim
	var b := 2.0 * d.dot(l)
	var c := d.dot(d) - gap * gap
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return aim
	var s := (-b - sqrt(disc)) / (2.0 * a)
	if s < 0.0 or s > 1.0:
		return aim
	return target + Vector3(l.x, 0.0, l.y) * s


## A throw's target with this weapon's lead (params.lead): `pt` the priority creature it was chosen for (-1 for a crowd),
## `unled` for a Sticky throw at a priority target. On the ground at the led spot.
func _lead_target(target: Vector3, from: Vector3, hero: Vector3, range_m: float, pt: int, unled: bool) -> Vector3:
	var lc := lead_config(inst.params)
	if unled or float(lc["share"]) <= 0.0:
		return target
	var enemies: EnemyManager = game.enemies
	var v: Vector3 = enemies.walk_velocity(pt) if pt >= 0 else enemies.crowd_velocity(target, float(lc["radius"]))
	var pace: float = v.length() if pt >= 0 else enemies.crowd_speed(target, float(lc["radius"]))
	var hv := Vector3.ZERO
	if player and player.get("velocity") is Vector3:
		hv = player.get("velocity")
	hv.y = 0.0
	var fz := ProjectileManager.fuse_of(inst)
	var fuse := 0.0
	if not fz.is_empty() and not inst.params.get("sticky") is Dictionary:
		fuse = ProjectileManager.fuse_seconds(fz, {})
	var map = game.get("map")
	var arena_r: float = float(map.get("arena_radius")) - 1.5 if map and map.get("arena_radius") != null else 0.0
	var aim := lead_spot(target, from, v, stat("speed", 9.0), fuse, lc, hero, range_m, arena_r, hv, pace)
	if aim.is_equal_approx(target):
		return target
	if str(lc["mode"]) == "predict":
		# the spots from the one chosen to the chase's, scored by the creatures foreseen inside the blast as it goes off
		var area := stat("area", 2.5)
		var wait := clampf(maxf(Vector2(target.x - from.x, target.z - from.z).length(), 0.5) / maxf(stat("speed", 9.0), 1.0), 0.35, 2.5) + fuse
		var goal := hero + hv * (wait * float(lc["hero_ahead"]))
		var spots: Array = []
		for k in range(LEAD_STEPS + 1):
			spots.append(target.lerp(aim, float(k) / float(LEAD_STEPS)))
		var counts := enemies.predicted_counts(spots, area, wait, goal, float(lc["gap"]), target, area + target.distance_to(aim) + 6.0)
		aim = spots[predict_pick(counts)]
		if aim.is_equal_approx(target):
			return target
	if map and map.has_method("height_at"):
		aim.y = map.height_at(aim.x, aim.z)
	leads += 1
	last_lead = Vector2(aim.x - target.x, aim.z - target.z).length()
	return aim


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
