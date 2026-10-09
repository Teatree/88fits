extends GdUnitTestSuite

## Pass 62, lane HM (Garry: "Ironwood doesn't have a special mutation for his Spear starting weapon ... every 4th thrust
## from the Spear is a guaranteed Crit and only this hit will have a slightly higher reach ... the tip of the Spear shines
## red and there is a powerful looking red thrust effect"; "Change the Solenne favorite item to be a Molotov instead of
## Haste. Add a Special Solenne specific Molotov Mutation which add a small explosion to Molotovs ... weak knockback and
## deal extra damage on the explosion ... the Molotov projectiles as kind of imbued with sun energy, so they shine ...
## the little sun puff should accompany the Molotov's when they 'explode'"). Heartseeker counts the Spear's strokes and
## makes every 4th a forced crit that reaches 20% further, its point glowing red as it comes; Sun Cocktail gives every
## bottle a gold shine and a sunburst in flight and a small sun blast where it lands; Solenne's favourite is the Molotov.

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var fx = null
var pickups = null
var paused := false
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_at, _col, _size) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func fx_poison(_a) -> void:
	pass
func fx_fire(_a, _b = 1.0, _blue = false) -> void:
	pass
func fx_ignite(_a, _b = 1.0, _blue = false) -> void:
	pass
func fx_lightning(_points) -> void:
	pass
func hint_once(_a, _b) -> void:
	pass
func spawn_cloud(_at, _w, _r, _el = "poison", _p = {}) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
var hip: Node3D = null
var max_hp := 100.0
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func shove(_v: Vector3, _c: bool = true) -> bool:
	return true
func blast(_v: Vector3, _u: float = 0.0) -> void:
	pass
func apply_knockback(_v: Vector3) -> void:
	pass
func heal(_a: float, _s: String = "") -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
func aim_origin(d: Vector3) -> Vector3:
	return global_position + Vector3(0, 0.8, 0) + Vector3(d.x, 0, d.z).normalized() * 0.5
"""

const FAKE_CAMERA := """extends Node
var shakes := 0
func shake(_a: float) -> void:
	shakes += 1
func current_yaw() -> float:
	return 0.0
func zoom() -> float:
	return 1.0
"""

const DT := 1.0 / 60.0

## the IT lane's pierce drop-off (pass 62) changes what the second creature along a thrust takes; off here, so the
## numbers are the crit's alone
var _falloff_was = null


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("ironwood"), Registry.map("red_canyon"))
	Run.player_sheet.set_base("crit_chance", 0.0)
	if "pierce_falloff" in Settings:
		_falloff_was = Settings.get("pierce_falloff")
		Settings.set("pierce_falloff", false)


func after_test() -> void:
	if _falloff_was != null:
		Settings.set("pierce_falloff", _falloff_was)
		_falloff_was = null
	Run.debug_clear_items()
	Run.end()


func _world() -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var cam := Node.new()
	cam.set_script(_script(FAKE_CAMERA))
	g.add_child(cam)
	g.camera = cam
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	var pm := ProjectileManager.new()
	pm.game = g
	g.add_child(pm)
	g.projectiles = pm
	var fx := Fx.new()
	g.add_child(fx)
	g.fx = fx
	var tg := Telegraphs.new()
	g.add_child(tg)
	g.telegraphs = tg
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em, "pm": pm, "fx": fx, "tg": tg, "cam": cam}


func _inst(id: String, muts: Array = [], level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m: String in muts:
		var md: MutationDef = Registry.mutation(m)
		assert_object(md).override_failure_message("no mutation " + m).is_not_null()
		inst.mutations.append(md)
	inst.rebuild(Run.player_sheet, [inst])
	return inst


func _behaviour(w: Dictionary, b: WeaponBehavior, id: String, muts: Array = [], level := 1) -> WeaponBehavior:
	(w["g"] as Node).add_child(b)
	b.setup(_inst(id, muts, level), w["g"])
	return b


func _thruster(w: Dictionary, id: String, muts: Array = [], level := 1) -> Thruster:
	return _behaviour(w, Thruster.new(), id, muts, level) as Thruster


## The build change Game._sync_weapons makes: the instance folded again with these mutations, then refresh_marks.
func _rebuild_with(b: WeaponBehavior, muts: Array) -> void:
	b.inst.mutations.clear()
	for m: String in muts:
		b.inst.mutations.append(Registry.mutation(m))
	b.inst.rebuild(Run.player_sheet, [b.inst])
	b.refresh_marks()


## A tough creature standing where it was put (a skeleton).
func _creature(em: EnemyManager, at: Vector3, hp_mult := 200.0) -> int:
	var i := em.spawn("skeleton", at, null, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	em._rebuild_grid()
	em.refresh_crowd_stats()
	return i


## Ticks the blade until its stroke is over; returns the seconds it took (-1 when it never ended).
func _run_stroke(t: Thruster, max_s := 3.0) -> float:
	var s := 0.0
	while t.stroke_running() and s < max_s:
		t._tick(DT)
		s += DT
	return s if not t.stroke_running() else -1.0


## One whole stroke at the creatures standing where they were put (their knockback forgotten): what each lost.
func _stroke(t: Thruster, em: EnemyManager, who: Array, spots: Array) -> Array:
	for k in range(who.size()):
		em.pos[who[k]] = spots[k]
		em.kb[who[k]] = Vector3.ZERO
	em._rebuild_grid()
	var before: Array = []
	for i: int in who:
		before.append(em.hp[i])
	assert_bool(t._fire()).is_true()
	assert_float(_run_stroke(t)).is_greater(0.0)
	var lost: Array = []
	for k in range(who.size()):
		lost.append(float(before[k]) - em.hp[who[k]])
	return lost


func _ids(arr: Array) -> Array:
	return arr.map(func(d) -> String: return d.id)


# ---------------------------------------------------------------- Heartseeker: the content

func test_heartseeker_is_ironwoods_hero_mutation_on_the_spear() -> void:
	var m: MutationDef = Registry.mutation("heartseeker")
	assert_object(m).is_not_null()
	assert_bool(m.is_hero()).is_true()
	assert_str(m.hero).is_equal("ironwood")
	assert_str(m.weapon).is_equal("pike")
	assert_str(m.mutation_kind).is_equal("hero")
	assert_bool(m.hidden).is_false()
	assert_str(m.text).is_equal("Every 4th thrust is a guaranteed crit and reaches 20% further.")
	assert_object(m.icon).override_failure_message("Heartseeker has no icon").is_not_null()
	var cs: Dictionary = m.params["crit_stroke"]
	assert_int(int(cs["every"])).is_equal(4)
	assert_float(float(cs["reach_mult"])).is_equal_approx(1.2, 0.0001)
	assert_array(_ids(Registry.hero_mutations("ironwood"))).contains(["heartseeker"])
	assert_array(_ids(Registry.weapon_hero_mutations("pike"))).contains(["heartseeker"])
	# never part of the Spear's path (the evolution needs the three path picks alone)
	assert_array(_ids(Registry.mutations_of("pike"))).not_contains(["heartseeker"])


func test_only_ironwood_is_offered_heartseeker() -> void:
	var w := Run.add_weapon(Registry.weapon("pike"), 1)
	assert_array(_ids(Run.open_mutations(w))).contains(["heartseeker"])
	Run.end()
	for hero in ["drifter", "astro", "calavera", "solenne"]:
		Run.start(Registry.character(hero), Registry.map("red_canyon"))
		var w2 := Run.add_weapon(Registry.weapon("pike"), 1)
		assert_array(_ids(Run.open_mutations(w2))).override_failure_message(hero + " was offered Heartseeker").not_contains(["heartseeker"])
		Run.end()


# ---------------------------------------------------------------- Heartseeker: the count

func test_every_fourth_thrust_crits_everything_it_hits_and_reaches_further() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var t := _thruster(w, "pike", ["heartseeker"])
	assert_int(t.crit_every()).is_equal(4)
	assert_float(t.crit_reach_mult()).is_equal_approx(1.2, 0.0001)
	var reach := t.stat("range", 0.0)
	var near := _creature(em, Vector3(0, 0, -2.0))
	# just past the plain reach (its centre beyond reach + its radius), well inside the crit's
	var far_at := Vector3(0, 0, -(reach + em.radius[near] + 0.35))
	var far := _creature(em, far_at)
	assert_float(reach + em.radius[far] + 0.35).is_less(reach * 1.2 + em.radius[far])
	var who := [near, far]
	var spots := [em.pos[near], far_at]
	var crit_mult: float = Run.player_sheet.get_stat("crit_damage", 2.0)
	var first: Array = _stroke(t, em, who, spots)
	assert_float(float(first[0])).is_greater(0.0)
	assert_float(float(first[1])).is_equal(0.0)
	assert_int(t.crit_hits).is_equal(0)
	assert_bool(em.last_crit).is_false()
	for k in range(2):
		var lost: Array = _stroke(t, em, who, spots)
		assert_float(float(lost[0])).is_equal_approx(float(first[0]), 0.01)
		assert_float(float(lost[1])).is_equal(0.0)
	assert_int(t.crit_count).is_equal(3)
	assert_bool(t.next_is_crit()).is_true()
	# the 4th: a crit on both, the far one reached only now, the blade out 20% further
	assert_bool(t._fire()).is_true()
	assert_bool(t._phase_crit()).is_true()
	var longest := 0.0
	var s := 0.0
	while t.stroke_running() and s < 3.0:
		t._tick(DT)
		s += DT
		if not t._blades.is_empty() and (t._blades[0] as Node3D).visible:
			longest = maxf(longest, (t._blades[0] as Node3D).scale.z)
	assert_float(longest).is_greater(reach * 1.2 * 0.99)
	assert_int(t.crit_strokes).is_equal(1)
	assert_int(t.crit_hits).is_equal(2)
	assert_int(t.crit_count).is_equal(0)
	# then the count starts again: a plain stroke at the plain reach
	var after: Array = _stroke(t, em, who, spots)
	assert_float(float(after[0])).is_equal_approx(float(first[0]), 0.01)
	assert_float(float(after[1])).is_equal(0.0)
	assert_int(t.crit_hits).is_equal(2)
	assert_int(t.crit_count).is_equal(1)


func test_the_crit_stroke_does_crit_damage_at_the_heros_crit_damage() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var t := _thruster(w, "pike", ["heartseeker"])
	var i := _creature(em, Vector3(0, 0, -2.0))
	var spots := [em.pos[i]]
	var crit_mult: float = Run.player_sheet.get_stat("crit_damage", 2.0)
	var plain: float = float(_stroke(t, em, [i], spots)[0])
	_stroke(t, em, [i], spots)
	_stroke(t, em, [i], spots)
	var crit: float = float(_stroke(t, em, [i], spots)[0])
	assert_float(crit).is_equal_approx(plain * crit_mult, 0.01)
	# the forced crit is EnemyManager's: HIT_CRIT on any weapon hit, never on a tick
	var hp0: float = em.hp[i]
	em.damage(i, 10.0, "pike", Vector3.ZERO, 0.0, false, false, EnemyManager.HIT_CRIT)
	assert_bool(em.last_crit).is_true()
	assert_float(hp0 - em.hp[i]).is_equal_approx(10.0 * crit_mult * (1.0 - em.dr[i]), 0.01)
	em.damage(i, 10.0, "pike", Vector3.ZERO, 0.0, true, false, EnemyManager.HIT_CRIT)
	assert_bool(em.last_crit).is_false()


func test_a_plain_spear_counts_nothing_and_never_forces_a_crit() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var t := _thruster(w, "pike")
	assert_int(t.crit_every()).is_equal(0)
	assert_bool(t.shows_look("LookCrit")).is_false()
	var i := _creature(em, Vector3(0, 0, -2.0))
	var spots := [em.pos[i]]
	var first: float = float(_stroke(t, em, [i], spots)[0])
	for k in range(5):
		assert_float(float(_stroke(t, em, [i], spots)[0])).is_equal_approx(first, 0.01)
	assert_int(t.crit_strokes).is_equal(0)
	assert_int(t.crit_hits).is_equal(0)
	assert_int(t.lances).is_equal(0)
	assert_float(t.tip_glow()).is_equal(0.0)


# ---------------------------------------------------------------- Heartseeker: the look

func test_the_point_glows_red_as_the_fourth_thrust_comes() -> void:
	assert_float(Thruster.glow_for(0, 4)).is_equal_approx(Thruster.CRIT_HINT / 3.0, 0.0001)
	assert_float(Thruster.glow_for(1, 4)).is_equal_approx(Thruster.CRIT_HINT * 2.0 / 3.0, 0.0001)
	assert_float(Thruster.glow_for(2, 4)).is_equal_approx(Thruster.CRIT_HINT, 0.0001)
	assert_float(Thruster.glow_for(3, 4)).is_equal(1.0)
	var w := _world()
	var em: EnemyManager = w["em"]
	var t := _thruster(w, "pike", ["heartseeker"])
	assert_bool(t.shows_look("LookCrit")).is_true()
	# its materials are the blade's own, not the scene's (the Warmup's Spear keeps its own)
	var fresh: Node = (load("res://content/weapons/pike/pike_visual.tscn") as PackedScene).instantiate()
	var scene_mat: Material = (fresh.get_node("Blade/LookCrit/TipRed") as MeshInstance3D).material_override
	fresh.free()
	assert_object(t._crit_tip_mat).is_not_null()
	assert_object(t._crit_tip_mat).is_not_same(scene_mat)
	var i := _creature(em, Vector3(0, 0, -2.0))
	var spots := [em.pos[i]]
	var want := [Thruster.glow_for(0, 4), Thruster.glow_for(1, 4), Thruster.glow_for(2, 4), 1.0, Thruster.glow_for(0, 4)]
	for k in range(want.size()):
		em.pos[i] = spots[0]
		em._rebuild_grid()
		assert_bool(t._fire()).is_true()
		assert_float(t.tip_glow()).is_equal_approx(float(want[k]), 0.0001)
		t._tick(DT)
		# a copy made for the stroke wears it, in the blade's own material
		var look := (t._blades[0] as Node3D).get_node("LookCrit") as Node3D
		assert_bool(look.visible).is_true()
		assert_object((look.get_node("TipRed") as MeshInstance3D).material_override).is_same(t._crit_tip_mat)
		if float(want[k]) >= 1.0:
			assert_float(t.tip_red()).is_greater(1.0 - Thruster.CRIT_SHIMMER - 0.01)
		else:
			assert_float(t.tip_red()).is_equal_approx(float(want[k]), 0.0001)
		_run_stroke(t)
	# the look goes with the mutation, and the count with it
	_rebuild_with(t, [])
	assert_bool(t.shows_look("LookCrit")).is_false()
	assert_int(t.crit_count).is_equal(0)
	assert_float(t.tip_glow()).is_equal(0.0)


func test_the_crit_thrust_leaves_a_red_lance_a_ring_sparks_and_a_kick() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var fx: Fx = w["fx"]
	var cam: Node = w["cam"]
	var t := _thruster(w, "pike", ["heartseeker"], 5)
	assert_int(t.stat_int("amount", 1)).is_equal(2)
	var i := _creature(em, Vector3(0, 0, -2.0))
	var spots := [em.pos[i]]
	for k in range(3):
		_stroke(t, em, [i], spots)
	assert_int(t.lances).is_equal(0)
	assert_int(fx.crit_thrusts).is_equal(0)
	var shakes0: int = int(cam.get("shakes"))
	assert_bool(t._fire()).is_true()
	# the streak and the trail are red on the crit stroke
	assert_bool(t._trail_colour().is_equal_approx(t.crit_color())).is_true()
	var seen := 0
	var s := 0.0
	while t.stroke_running() and s < 3.0:
		t._tick(DT)
		s += DT
		seen = maxi(seen, t.lances_live())
	# one lance and one burst of sparks for each of the two spears, the camera kicked
	assert_int(t.lances).is_equal(2)
	assert_int(seen).is_equal(2)
	assert_int(fx.crit_thrusts).is_equal(2)
	assert_int(int(cam.get("shakes"))).is_greater(shakes0)
	# gone after their life
	for k in range(int((Thruster.LANCE_LIFE + 0.1) / DT)):
		t._tick(DT)
	assert_int(t.lances_live()).is_equal(0)
	# the next stroke is plain again: steel streak, no lance
	_stroke(t, em, [i], spots)
	assert_int(t.lances).is_equal(2)
	assert_bool(t._trail_colour().is_equal_approx(t.crit_color())).is_false()


func test_the_wide_sweep_and_the_thunder_lance_keep_it() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	# the Wide Sweep: every 4th sweep crits
	var t := _thruster(w, "pike", ["pike_sweep", "heartseeker"])
	assert_bool(t._slices()).is_true()
	var i := _creature(em, Vector3(0, 0, -2.0))
	var spots := [em.pos[i]]
	var crit_mult: float = Run.player_sheet.get_stat("crit_damage", 2.0)
	var plain: float = float(_stroke(t, em, [i], spots)[0])
	assert_float(plain).is_greater(0.0)
	_stroke(t, em, [i], spots)
	_stroke(t, em, [i], spots)
	assert_int(t.crit_hits).is_equal(0)
	assert_float(float(_stroke(t, em, [i], spots)[0])).is_equal_approx(plain * crit_mult, 0.01)
	assert_int(t.crit_hits).is_equal(1)
	assert_str(t.inst.description()).contains("Every 4th sweep is a guaranteed crit and reaches 20% further.")
	t.queue_free()
	# the Thunder Lance carries it (the evolution keeps the path and the hero's pick): its 4th stroke's sweep is plain,
	# the thrust after it the crit
	var lance := _thruster(w, "thunder_lance", ["stunning_thrust", "long_spear", "pike_sweep", "heartseeker"])
	assert_bool((lance.inst.params.get("crit_stroke", {}) as Dictionary).is_empty()).is_false()
	assert_str(lance.inst.description()).contains("Every 4th thrust is a guaranteed crit")
	for k in range(3):
		em.pos[i] = spots[0]
		em._rebuild_grid()
		assert_bool(lance._fire()).is_true()
		_run_stroke(lance)
	assert_int(lance.crit_hits).is_equal(0)
	em.pos[i] = spots[0]
	em._rebuild_grid()
	assert_bool(lance._fire()).is_true()
	var s := 0.0
	while lance._combo == 1 and s < 3.0:
		lance._tick(DT)
		s += DT
	assert_int(lance._combo).is_equal(2)
	assert_int(lance.crit_hits).is_equal(0)
	_run_stroke(lance)
	assert_int(lance.crit_hits).is_greater_equal(1)
	assert_int(lance.lances).is_greater_equal(1)


func test_the_evolution_keeps_heartseeker_through_run() -> void:
	var w := Run.add_weapon(Registry.weapon("pike"), 5)
	assert_bool(Run.add_mutation("heartseeker", true)).is_true()
	var evo := Run.evolve(w)
	assert_object(evo).is_not_null()
	assert_str(evo.def.id).is_equal("thunder_lance")
	assert_bool(evo.has_mutation("heartseeker")).is_true()
	assert_int(int((evo.params["crit_stroke"] as Dictionary)["every"])).is_equal(4)


# ---------------------------------------------------------------- Solenne's favourite

func test_solennes_favourite_is_the_molotov_at_level_two() -> void:
	var c: CharacterDef = Registry.character("solenne")
	assert_str(c.favourite_weapon).is_equal("molotov")
	assert_str(str(c.favourite_bonus.get("type", ""))).is_equal("level")
	assert_int(int(c.favourite_bonus.get("value", 0))).is_equal(2)
	assert_str(c.favourite_passive).is_equal("")
	assert_bool(c.favourite_passive_bonus.is_empty()).is_true()
	var molotov: WeaponDef = Registry.weapon("molotov")
	# the title plaque and the hero sheet show it at level 2
	assert_int(int(load("res://ui/TitleScreen.gd").start_level(c, molotov))).is_equal(2)
	Run.end()
	Run.start(c, Registry.map("red_canyon"))
	Run.player_sheet.set_base("crit_chance", 0.0)
	assert_bool(Run.is_favourite(molotov)).is_true()
	# Haste is nothing special to her any more
	assert_int(Run.first_passive_level(Registry.passive("haste"))).is_equal(1)
	assert_bool(Run.is_favourite(Registry.passive("haste"))).is_false()
	# offered from her first run, and taken it comes at level 2
	assert_bool(CardPool.offer_weapons().has(molotov)).is_true()
	seed(6202)
	var found := {}
	for k in range(400):
		for card: Dictionary in CardPool.level_up_offer(3):
			if str(card["id"]) == "molotov":
				found = card
		if not found.is_empty():
			break
	assert_bool(found.is_empty()).override_failure_message("the Molotov never came").is_false()
	assert_bool(bool(found.get("favourite", false))).is_true()
	CardPool.apply(found)
	assert_int(Run.weapon_instance("molotov").level).is_equal(2)


func test_a_heros_favourite_weapon_is_offered_whatever_its_quest() -> void:
	Run.end()
	Run.start(Registry.character("solenne"), Registry.map("red_canyon"))
	# the Spear waits behind its quest for everyone else (a new save has not done it)
	var pike: WeaponDef = Registry.weapon("pike")
	assert_bool(Registry.is_unlocked("weapon", "pike")).is_false()
	assert_bool(CardPool.offer_weapons().has(pike)).is_false()
	# a favourite behind a quest comes anyway (the rule CardPool.offer_weapons keeps for her Molotov)
	var c: CharacterDef = Run.character
	var was := c.favourite_weapon
	c.favourite_weapon = "pike"
	var has := CardPool.offer_weapons().has(pike)
	c.favourite_weapon = was
	assert_bool(has).is_true()


# ---------------------------------------------------------------- Sun Cocktail: the content

func test_sun_cocktail_is_solennes_hero_mutation_on_the_molotov() -> void:
	var m: MutationDef = Registry.mutation("sun_cocktail")
	assert_object(m).is_not_null()
	assert_bool(m.is_hero()).is_true()
	assert_str(m.hero).is_equal("solenne")
	assert_str(m.weapon).is_equal("molotov")
	assert_bool(m.hidden).is_false()
	assert_object(m.icon).override_failure_message("Sun Cocktail has no icon").is_not_null()
	assert_array(_ids(Registry.hero_mutations("solenne"))).contains(["sun_cocktail"])
	assert_array(_ids(Registry.weapon_hero_mutations("molotov"))).contains(["sun_cocktail"])
	assert_array(_ids(Registry.mutations_of("molotov"))).not_contains(["sun_cocktail"])
	Run.end()
	Run.start(Registry.character("solenne"), Registry.map("red_canyon"))
	var w := Run.add_weapon(Registry.weapon("molotov"), 1)
	assert_array(_ids(Run.open_mutations(w))).contains(["sun_cocktail"])
	Run.end()
	for hero in ["drifter", "astro", "calavera", "ironwood"]:
		Run.start(Registry.character(hero), Registry.map("red_canyon"))
		var w2 := Run.add_weapon(Registry.weapon("molotov"), 1)
		assert_array(_ids(Run.open_mutations(w2))).override_failure_message(hero + " was offered Sun Cocktail").not_contains(["sun_cocktail"])
		Run.end()
	Run.start(Registry.character("ironwood"), Registry.map("red_canyon"))


func test_the_moonshine_keeps_the_sun_cocktail() -> void:
	Run.end()
	Run.start(Registry.character("solenne"), Registry.map("red_canyon"))
	var w := Run.add_weapon(Registry.weapon("molotov"), 5)
	assert_bool(Run.add_mutation("sun_cocktail", true)).is_true()
	var evo := Run.evolve(w)
	assert_str(evo.def.id).is_equal("moonshine")
	assert_bool(evo.has_mutation("sun_cocktail")).is_true()
	for key in ["land_blast", "halo", "tint"]:
		assert_bool(evo.params.get(key) is Dictionary).override_failure_message("the Moonshine lost " + key).is_true()
	assert_str(evo.description()).contains("bursts with sunlight as it lands")


# ---------------------------------------------------------------- Sun Cocktail: the blast

func test_the_sun_blast_does_its_share_within_its_radius_and_throws_weakly() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var fx: Fx = w["fx"]
	var inst := _inst("molotov", ["sun_cocktail"])
	var area := inst.stat("area", 0.0)
	var r := area * 0.9
	var dmg := inst.stat("damage", 0.0) * 1.5
	var at := Vector3(20, 0, 20)
	var inside := _creature(em, at + Vector3(r * 0.7, 0, 0))
	var outside := _creature(em, at + Vector3(r + 0.4, 0, 0))
	var hp_in: float = em.hp[inside]
	var hp_out: float = em.hp[outside]
	var puffs0 := fx.sun_puffs
	var blasts0 := Lobber.land_blasts
	assert_int(Lobber.land_blast(g, at, inst, area, {})).is_equal(1)
	assert_float(hp_in - em.hp[inside]).is_equal_approx(dmg * (1.0 - em.dr[inside]), 0.01)
	assert_float(hp_out - em.hp[outside]).is_equal(0.0)
	# a weak shove straight out: 2.4 against a grenade's 7 (a third of a blast)
	var mass := maxf(em.size[inside], 0.8)
	assert_float(em.kb[inside].length()).is_equal_approx(2.4 / mass, 0.01)
	assert_float(em.kb[inside].x).is_greater(0.0)
	assert_float(em.kb[inside].length()).is_less(Registry.weapon("lob_grenade").base["knockback"] / mass * 0.5)
	assert_float(em.kb[outside].length()).is_equal(0.0)
	# the little sun puffs there
	assert_int(fx.sun_puffs).is_equal(puffs0 + 1)
	assert_int(Lobber.land_blasts).is_equal(blasts0 + 1)
	# a plain bottle, a bomblet and a burst make none
	var plain := _inst("molotov")
	assert_int(Lobber.land_blast(g, at, plain, area, {})).is_equal(-1)
	assert_int(Lobber.land_blast(g, at, inst, area, {"is_bomblet": true})).is_equal(-1)
	assert_int(fx.sun_puffs).is_equal(puffs0 + 1)


func test_a_thrown_sun_bottle_bursts_where_it_lands_and_a_plain_one_does_not() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var fx: Fx = w["fx"]
	var target := Vector3(6, 0, 0)
	var e := _creature(em, target)
	for muts: Array in [[], ["sun_cocktail"]]:
		var lb := Lobber.new()
		(w["g"] as Node).add_child(lb)
		lb.setup(_inst("molotov", muts), w["g"])
		em.pos[e] = target
		em.kb[e] = Vector3.ZERO
		em._rebuild_grid()
		var hp0: float = em.hp[e]
		var puffs0 := fx.sun_puffs
		var j := pm.lob(lb.shot_kind(), Vector3(0, 1.2, 0), target, 10.0, lb.stat("damage", 0.0), lb.stat("area", 2.0), lb.inst, lb.stat("knockback", 0.0), lb.inst.params.duplicate())
		var n := 0
		while pm.alive[j] == 1 and n < 300:
			pm._physics_process(DT)
			n += 1
		assert_int(pm.alive[j]).is_equal(0)
		var lost := hp0 - em.hp[e]
		var impact := lb.stat("damage", 0.0) * (1.0 - em.dr[e])
		if muts.is_empty():
			assert_float(lost).is_equal_approx(impact, 0.01)
			assert_int(fx.sun_puffs).is_equal(puffs0)
		else:
			assert_float(lost).is_equal_approx(impact * 2.5, 0.01)
			assert_int(fx.sun_puffs).is_equal(puffs0 + 1)
		lb.queue_free()


# ---------------------------------------------------------------- Sun Cocktail: the shine

func test_the_bottle_shines_gold_with_a_sunburst_only_with_the_mutation() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	_creature(em, Vector3(5, 0, 0))
	var plain := Lobber.new()
	(w["g"] as Node).add_child(plain)
	plain.setup(_inst("molotov"), w["g"])
	assert_int(plain.shot_kind()).is_equal(plain.projectile_kind)
	assert_bool(plain._fire()).is_true()
	plain._tick(DT)
	assert_int(plain.halo_shots).is_equal(0)
	assert_int(plain.halos_live()).is_equal(0)
	pm.clear_all()
	var sun := Lobber.new()
	(w["g"] as Node).add_child(sun)
	sun.setup(_inst("molotov", ["sun_cocktail"]), w["g"])
	var k := sun.shot_kind()
	assert_int(k).is_not_equal(sun.projectile_kind)
	var over: Material = (pm.kinds[k]["mmi"] as MultiMeshInstance3D).material_override
	var mat := over as StandardMaterial3D
	assert_object(mat).is_not_null()
	assert_bool(mat.emission_enabled).is_true()
	assert_float(mat.emission_energy_multiplier).is_equal_approx(2.2, 0.001)
	assert_float(mat.emission.r).is_greater(mat.emission.b)
	# thrown: a sunburst rides it while it flies, and lets go when it lands
	assert_bool(sun._fire()).is_true()
	assert_int(sun.halo_shots).is_equal(1)
	sun._tick(DT)
	assert_int(sun.halos_live()).is_equal(1)
	var j: int = int(sun._flying[0][0])
	var q: MeshInstance3D = sun._halos[0]
	assert_float(q.global_position.distance_to(pm.pos[j])).is_less(0.01)
	assert_bool(q.material_override is ShaderMaterial).is_true()
	var n := 0
	while pm.alive[j] == 1 and n < 300:
		pm._physics_process(DT)
		sun._tick(DT)
		n += 1
	sun._tick(DT)
	assert_int(sun.halos_live()).is_equal(0)
