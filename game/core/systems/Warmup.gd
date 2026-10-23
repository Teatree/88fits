## Shader and font warm-up. The Compatibility renderer compiles a shader the first time something is drawn with it,
## which on a phone is a visible hitch the first time a creature type, a weapon, a burst or a big label appears.
## So, under the spawn beam (Game._spawn_begin; the arena and a tool's instant start call it too), everything the run
## can show is drawn once in a pit eight metres under the
## hero for a few frames: every creature type and projectile kind (through their MultiMeshes, so the instanced
## variants compile), every weapon visual, the effect pools, the ground-mark and cloud materials, chests, mines,
## turrets, power-ups, the portal, and the fonts at every size the overlays use.
class_name Warmup
extends Node3D

const PIT := Vector3(0, -8.0, 0)
## pass 70: by path, so Warmup never waits on the class cache
const TRAMPOLINE := preload("res://core/systems/Trampoline.gd")
const FRAMES_S := 0.3

var _labels: Control


static func run(game: Node) -> void:
	var w := Warmup.new()
	w.name = "Warmup"
	game.add_child(w)
	w.position = game.player.global_position + PIT
	w._build(game)
	# the timer runs paused or not, then everything goes
	var t := game.get_tree().create_timer(FRAMES_S, true, false, true)
	t.timeout.connect(func(): w._finish(game))


func _build(game: Node) -> void:
	var em: EnemyManager = game.enemies
	var pm: ProjectileManager = game.projectiles
	# every creature type the map can show, drawn once through its MultiMesh. Pass 101 (lane LOOKS): only the creatures
	# this run's stage can bring (RunLooks: their strips, in every look the stage brings them in, and the hero's, are
	# loaded and pinned here, under the beam); every other creature's strip loads when something first asks for it
	var li = game.get("launch_info")   # pass 101 review: a tool's launch creature and look are pinned too
	for def: EnemyDef in RunLooks.prepare(game, li if li is Dictionary else {}):
		em.register_type(def)
	em.warm_draw(global_position)
	# every weapon's visual (held guns, familiars, projectile meshes) and its projectile kind
	for wdef in Registry.weapons.values():
		if wdef.visual:
			var vis: Node3D = wdef.visual.instantiate()
			# pass 67: the run's grade on the model's lit materials, as WeaponBehavior._load_visual applies it, so the
			# kinds registered here wear what a run draws (the title does the same for its companion)
			WeaponBehavior.grade_materials(vis, WeaponBehavior.grade_for(Run.map, wdef.params))
			add_child(vis)
			# pass 61 (lane WP2): the looks a mutation switches on (the Sabre's razor edge and guard bar) are hidden in the
			# scene; shown here so their materials compile with the rest
			for look in vis.find_children("Look*", "Node3D", true, false):
				(look as Node3D).visible = true
			# the shot's mesh as WeaponBehavior._load_visual registers it: the Projectile node, or (pass 46, the Spear) the first
			# mesh of the model under it, each part keeping its own material
			var proj := vis.get_node_or_null("Projectile")
			var src := WeaponBehavior.projectile_source(vis)
			if src:
				var mat: Material = src.material_override
				var sc: float = src.scale.x
				var mesh: Mesh = src.mesh
				if src == proj:
					if mat == null and src.mesh.get_surface_count() > 0:
						mat = src.get_active_material(0)
				else:
					if mat == null and src.mesh.get_surface_count() == 1:
						mat = src.get_active_material(0)
					elif mat == null:
						# pass 67: the model's surfaces in their graded copies (WeaponBehavior.kind_mesh)
						mesh = WeaponBehavior.kind_mesh(src)
					sc *= (proj as Node3D).scale.x
				_shot_kinds[wdef.id] = pm.register_kind(mesh, mat, sc)
		# pass 48: a shot drawn from a model in the weapon's params (the Golden Pineapple's grenade), with the material
		# Lobber._use_model gives it
		var mp := str(wdef.params.get("model", ""))
		if mp != "" and ResourceLoader.exists(mp):
			var scn = load(mp)
			if scn is PackedScene:
				var root: Node = (scn as PackedScene).instantiate()
				for c in root.find_children("*", "MeshInstance3D", true, false):
					if (c as MeshInstance3D).mesh:
						var gm := StandardMaterial3D.new()
						gm.vertex_color_use_as_albedo = true
						gm.metallic = float(wdef.params.get("model_metallic", 0.45))
						gm.roughness = float(wdef.params.get("model_roughness", 0.35))
						_shot_kinds[wdef.id] = pm.register_kind((c as MeshInstance3D).mesh, gm, float(wdef.params.get("model_scale", 1.0)))
						break
				root.free()
	_warm_mutation_shots(pm)
	pm.warm_draw(global_position)
	# pass 76 (lane MOLO): the flames on the bottles' wicks, every style (core/shaders/wick_flame.gdshader) once
	if pm.has_method("warm_wick_flames"):
		pm.warm_wick_flames(global_position)
	# pass 54: the gems and coins draw see-through and read the stencil now: one of each under the beam, so their
	# materials compile here rather than at the first kill (PickupManager.warm_draw). Pass 60: that one gem of each kind
	# is drawn charged, so core/shaders/gem.gdshader compiles here on the gem MultiMeshes themselves (a quad would compile
	# the un-instanced variant, not theirs) and the first magnet pull never stalls.
	if game.get("pickups") and game.pickups.has_method("warm_draw"):
		game.pickups.warm_draw(global_position)
	# pass 48: the Tarantula Hawk is built from its own meshes when it launches; one sits here (no game, so it never moves)
	add_child(TarantulaHawk.new())
	# pass 54: the Sun Scepter's pillars of sunlight, one MultiMesh on their own shader: one faint pillar here
	var sb: Node3D = preload("res://core/systems/SunBeams.gd").new()
	add_child(sb)
	sb.warm(global_position)
	# pass 61 (lane WP2): Rust's blades on a MultiMesh as the saws draw them (the instanced variant), and the Sabre's
	# crit streak
	var rmm := MultiMesh.new()
	rmm.transform_format = MultiMesh.TRANSFORM_3D
	rmm.mesh = CylinderMesh.new()
	rmm.instance_count = 1
	rmm.set_instance_transform(0, Transform3D.IDENTITY)
	var rmi := MultiMeshInstance3D.new()
	rmi.multimesh = rmm
	rmi.material_override = Orbiter.rust_material(null, {})
	add_child(rmi)
	_quad(Thruster.slash_material())
	# the Saw Halo's solid ring wears the rust as a plain mesh, the other variant of the shader (the review)
	_quad(Orbiter.rust_material(null, {}))
	# the effect pools: one of each particle kind
	game.fx.burst(global_position, Color(1, 1, 1), 0.5)
	game.fx.hit(global_position, Color(1, 1, 1))
	game.fx.fire(global_position, 0.5)
	# the ground marks' pools (rings, discs, lines, spills, the poison billows) and the lightning bolts' two ribbons
	game.telegraphs.warm_draw(global_position)
	# material recipes the run uses on meshes that are built on the fly (marks, clouds, chests, bars)
	_quad(_flat(Color(1, 0.3, 0.3, 0.5), true, true))
	_quad(_flat(Color(0.3, 1, 0.3, 0.5), true, false))
	_quad(_flat(Color(1, 1, 1, 1), false, false))
	var lit := StandardMaterial3D.new()
	lit.albedo_color = Color(0.5, 0.4, 0.3)
	_quad(lit)
	var lit_alpha := StandardMaterial3D.new()
	lit_alpha.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lit_alpha.albedo_color = Color(0.8, 0.5, 0.2, 0.8)
	_quad(lit_alpha)
	var glow := StandardMaterial3D.new()
	glow.emission_enabled = true
	glow.emission = Color(1, 0.5, 0.2)
	_quad(glow)
	# vertex-coloured see-through meshes: the oil spill under a fire pool, the rocket's line home (pass 33)
	var vc := StandardMaterial3D.new()
	vc.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vc.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vc.vertex_color_use_as_albedo = true
	vc.cull_mode = BaseMaterial3D.CULL_DISABLED
	_quad(vc)
	# pass 35: the swept trails' additive ribbon, the black hole's rim and the swirl (the Singularity, the Teleport)
	_quad(Fx.glow_ribbon_material())
	# the hero's speed trails, drawn under him (pass 49)
	_quad(Fx.speed_ribbon_material())
	_quad(Fx.tint_ribbon_material())
	# the coin (pass 52: its own unshaded look)
	_quad(PickupManager.coin_material())
	for sh: Shader in [preload("res://core/shaders/black_hole.gdshader"), preload("res://core/shaders/swirl.gdshader")]:
		var sm := ShaderMaterial.new()
		sm.shader = sh
		_quad(sm)
	# the nodes that appear mid-run
	var chest := Chest.new()
	add_child(chest)
	var portal := Portal.new()
	add_child(portal)
	# pass 70 (lane TRAMP): Hang Time's trampoline (its graded, fog-free materials, the mat's blend shape) when this hero
	# can be offered a trampoline perk
	if TRAMPOLINE.can_offer():
		add_child(TRAMPOLINE.model_instance())
	for pdef in Registry.pickups.values():
		var pu := Powerup.new()
		pu.setup(pdef)
		add_child(pu)
	# the fonts: every size the overlays draw, once, almost invisible under the beam
	_labels = Control.new()
	_labels.modulate.a = 0.02
	_labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.ui.add_child(_labels)
	# the level-up's and the chest's turning shine (pass 58): its shader compiles here, under the spawn beam
	preload("res://ui/wanted/WShine.gd").warm(_labels)
	var y := 0.0
	for size in [22, 24, 26, 28, 30, 32, 34, 36, 40, 44, 46, 56, 64, 84, 96]:
		var l := UiKit.outline(UiKit.label("ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789 +%→·!?", size, UiKit.INK), 6)
		l.position = Vector2(0, y)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		_labels.add_child(l)
		y += size * 1.3
	Perf.context = "warmup"


## Pass 61 (lane WP1): the shot kinds a mutation's look makes mid-run (ProjectileManager.tinted_kind / spiked_kind:
## Sticky's resin on the Golden Pineapple's model, Thorny Weed's thorns, Dragon's Breath's pellets), made here for every
## weapon as if its whole path were held, so a material that switches a shader feature on (a glow on a vertex-coloured
## model) compiles under the beam.
var _shot_kinds := {}


func _warm_mutation_shots(pm: ProjectileManager) -> void:
	if not pm.has_method("tinted_kind"):
		return
	for wid: String in _shot_kinds.keys():
		var wd: WeaponDef = Registry.weapon(wid)
		if wd == null:
			continue
		var wi := WeaponInstance.new(wd)
		wi.mutations = Registry.mutations_of(wd.evolved_from if wd.is_evolution and wd.evolved_from != "" else wd.id)
		var fp := wi.fold_params()
		var k: int = int(_shot_kinds[wid])
		if fp.get("tint") is Dictionary:
			k = pm.tinted_kind(k, fp["tint"])
		var lk = fp.get("look")
		if lk is Dictionary and (lk as Dictionary).get("spikes") is Dictionary:
			pm.spiked_kind(k, lk["spikes"])
		# pass 62: a hero's own mutation may tint the shot too (Solenne's Sun Cocktail: a gold bottle), on its own
		for hm: MutationDef in Registry.weapon_hero_mutations(wd.evolved_from if wd.is_evolution and wd.evolved_from != "" else wd.id):
			if hm.params.get("tint") is Dictionary:
				pm.tinted_kind(int(_shot_kinds[wid]), hm.params["tint"])


func _flat(c: Color, alpha: bool, cull_off: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if cull_off:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	return m


func _quad(mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _finish(game: Node) -> void:
	if is_instance_valid(_labels):
		_labels.queue_free()
	if is_instance_valid(game) and game.enemies:
		game.enemies.warm_draw(Vector3.INF)
	if is_instance_valid(game) and game.projectiles:
		game.projectiles.warm_draw(Vector3.INF)
		if game.projectiles.has_method("warm_wick_flames"):
			game.projectiles.warm_wick_flames(Vector3.INF)
	if is_instance_valid(game) and game.get("pickups") and game.pickups.has_method("warm_draw"):
		game.pickups.warm_draw(Vector3.INF)
	queue_free()
