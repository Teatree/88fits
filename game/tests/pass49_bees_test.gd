extends GdUnitTestSuite

## Pass 49, lane B (Garry's seventh list): the Hornet Nest is the Killer Bees (every name and line the player reads,
## the id kept) with a honey-gold beehive for its companion; the Tarantula Hawk is one glowing purple ball, two and a half
## bees across, that buzzes round its prey at the bees' speed on a tilted, bobbing circle, turns back now and then and
## darts in for each of its five stings (still slowing and tinting its prey, still dropping when its prey dies); Pollen's
## flowers have no pointers on the HUD, and its buff is a timed power-up plate with its seconds, one for every weapon
## that carries it, gone at 0.

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var director = null
var telegraphs = null
var projectiles = null
var fx = null
var pickups = null
var paused := false
var clouds: Array = []
var toasts: Array = []
func toast(t, _c = null) -> void:
	toasts.append(str(t))
func fx_burst(_a, _b, _c) -> void:
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
func hint_once(_a, _b) -> void:
	pass
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
func telegraph_sector(_a, _b, _c, _d, _e, _f) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func shove(_v: Vector3) -> bool:
	return true
func apply_knockback(_v: Vector3) -> void:
	pass
func blast(_v: Vector3, _up: float = 0.0) -> void:
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

## The camera rig as the HUD reads it: the camera and its yaw.
const FAKE_RIG := """extends Node
var camera: Camera3D
func current_yaw() -> float:
	return 0.0
"""

## The director as the HUD's pointers read it: where the Elite is.
const FAKE_DIRECTOR := """extends Node
var elite_at := Vector3.INF
func elite_position() -> Vector3:
	return elite_at
"""

const DT := 1.0 / 60.0
## The Killer Bees' family: the weapon, its evolution, the old hidden one; and every mutation of its path.
const FAMILY := ["hornet_nest", "hive_queen", "killer_swarm"]
const FAMILY_MUTATIONS := ["pollen", "tarantula_hawk", "second_sting", "ember_hornets", "swarm"]


func before_test() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))


func after_test() -> void:
	Run.held_time = 0.0
	Run.timed.clear()
	Run.end()


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero at the origin, with the real crowd and effects.
func _world() -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
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
	return {"g": g, "hero": hero, "em": em, "pm": pm, "fx": fx}


## A tough creature on its feet where it was put, taking every hit whole.
func _creature(em: EnemyManager, at: Vector3, hp_mult := 50.0, id := "skeleton") -> int:
	var i := em.spawn(id, at, null, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.dr[i] = 0.0
	return i


func _inst(id: String, muts: Array = [], level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m: String in muts:
		inst.mutations.append(Registry.mutation(m))
	inst.rebuild(Run.player_sheet, [inst])
	return inst


func _no_hornet(s: String, what: String) -> void:
	assert_bool(s.to_lower().contains("hornet")).override_failure_message("%s says hornet: %s" % [what, s]).is_false()


# ---------------------------------------------------------------- the Tarantula Hawk

func test_the_hawk_is_one_glowing_purple_ball_two_and_a_half_bees_across() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var inst := _inst("hornet_nest", ["tarantula_hawk"], 3)
	var c := _creature(em, Vector3(4, 0, 0))
	em._rebuild_grid()
	var h := TarantulaHawk.launch(w["g"], inst, Vector3(0, 1.6, 0), c, inst.params["hawk"])
	var meshes := h.find_children("*", "MeshInstance3D", true, false)
	assert_int(meshes.size()).is_equal(1)
	var ball: MeshInstance3D = meshes[0]
	assert_bool(ball.mesh is SphereMesh).is_true()
	# a bee is 0.07 m; the ball two and a half of that, both drawn a third bigger (ProjectileManager.CHUNK)
	assert_float((ball.mesh as SphereMesh).radius).is_equal_approx(0.07 * 2.5 * ProjectileManager.CHUNK, 0.01)
	assert_bool(h.find_children("*Wing*", "", true, false).is_empty()).is_true()
	# glowing, and purple
	var mat := ball.material_override as StandardMaterial3D
	assert_bool(mat.emission_enabled).is_true()
	assert_float(mat.albedo_color.b).is_greater(mat.albedo_color.g + 0.5)
	assert_float(mat.albedo_color.r).is_greater(mat.albedo_color.g)


func test_the_hawk_buzzes_round_its_prey_at_the_bees_speed_and_darts_in_for_each_sting() -> void:
	seed(49)
	var w := _world()
	var em: EnemyManager = w["em"]
	var inst := _inst("hornet_nest", ["tarantula_hawk"], 5)
	var cfg: Dictionary = inst.params["hawk"]
	var big := _creature(em, Vector3(4, 0, 0), 60.0)
	em._rebuild_grid()
	em.refresh_crowd_stats()
	var h := TarantulaHawk.launch(w["g"], inst, Vector3(0, 1.6, 0), big, cfg)
	# the bees' speed: 15 m/s for the Killer Bees
	assert_float(h.speed).is_equal_approx(inst.stat("speed"), 0.001)
	assert_float(h.speed).is_between(12.0, 18.0)
	var r := h.orbit_radius()
	assert_float(r).is_between(0.55, 2.0)
	var hp0: float = em.hp[big]
	var t := 0.0
	var speeds: Array = []
	var off_ring := 0.0          # how far its distance from the middle strayed from the radius between darts
	var turned := 0.0            # radians it went round its prey
	var turns_back := 0          # times it turned back the other way
	var last_sign := 0
	var dart_min := INF
	var dart_mins: Array = []
	var was_darting := false
	var prev_rel := Vector3.INF
	var prev_ang := INF
	var held_seen := false
	while t < 7.0 and not h.is_queued_for_deletion():
		h.tick(DT)
		t += DT
		if h.state != TarantulaHawk.HOLD:
			prev_rel = Vector3.INF
			continue
		var rel: Vector3 = h.global_position - h.centre()
		var ang := atan2(rel.z, rel.x)
		if h.darting:
			dart_min = minf(dart_min, rel.length())
		elif was_darting:
			dart_mins.append(dart_min)
			dart_min = INF
		if not h.darting and not was_darting:
			off_ring = maxf(off_ring, absf(rel.length() - r))
			if prev_rel != Vector3.INF and absf(h._spin) >= 0.999:
				speeds.append((rel - prev_rel).length() / DT)
		if prev_ang != INF:
			var da := angle_difference(prev_ang, ang)
			turned += absf(da)
			if absf(da) > 0.02:
				var sg := 1 if da > 0.0 else -1
				if last_sign != 0 and sg != last_sign:
					turns_back += 1
				last_sign = sg
		was_darting = h.darting
		prev_rel = rel
		prev_ang = ang
		if h.stings_done >= 2:
			held_seen = true
			# its prey is held slowed and purple
			assert_float(em.attack_clock(big)).is_equal_approx(0.9, 0.001)
			assert_bool(em.status_tint[big].is_equal_approx(TarantulaHawk.TINT)).is_true()
	assert_bool(held_seen).is_true()
	# five stings over four seconds, each a bee's damage, then it leaves
	assert_int(h.stings_done).is_equal(5)
	assert_float(hp0 - em.hp[big]).is_equal_approx(5.0 * inst.stat("damage"), 0.01)
	assert_float(t).is_between(4.0, 6.0)
	assert_bool(h.is_queued_for_deletion()).is_true()
	# one dart in to the body and back out for every sting
	assert_int(h.darts).is_equal(5)
	assert_int(dart_mins.size()).is_equal(5)
	for m: float in dart_mins:
		assert_float(m).override_failure_message("a dart reached only %.2f m of its prey's middle (r %.2f)" % [m, r]).is_less(r * 0.4)
	# between darts it stays on its circle (a bob of 0.12 m either way)...
	assert_float(off_ring).is_less(0.2)
	# ...going round at the bees' speed
	speeds.sort()
	assert_int(speeds.size()).is_greater(60)
	var median: float = speeds[speeds.size() >> 1]
	assert_float(median).is_between(h.speed * 0.85, h.speed * 1.15)
	# round and round (over four seconds about seven turns at 15 m/s), turning back now and then
	assert_float(turned).is_greater(TAU * 4.0)
	assert_int(turns_back).is_greater_equal(1)


func test_the_hawk_flies_after_a_prey_that_blinks_away_instead_of_snapping_to_it() -> void:
	seed(7)
	var w := _world()
	var em: EnemyManager = w["em"]
	var inst := _inst("hornet_nest", ["tarantula_hawk"], 3)
	var c := _creature(em, Vector3(3, 0, 0), 60.0)
	em._rebuild_grid()
	var h := TarantulaHawk.launch(w["g"], inst, Vector3(0, 1.6, 0), c, inst.params["hawk"])
	var guard := 0
	while h.state != TarantulaHawk.HOLD and guard < 300:
		h.tick(DT)
		guard += 1
	assert_int(h.state).is_equal(TarantulaHawk.HOLD)
	for n in range(12):
		h.tick(DT)
	# its prey blinks eight metres off: the hawk flies after it at CATCH_UP times its speed, never a jump
	em.pos[c] += Vector3(8, 0, 0)
	var was := h.global_position
	h.tick(DT)
	assert_float(h.global_position.distance_to(was)).is_less_equal(h.speed * TarantulaHawk.CATCH_UP * DT + 0.001)
	assert_float(h.global_position.distance_to(h.centre())).is_greater(h.orbit_radius() + 3.0)
	var back := false
	for n in range(40):
		h.tick(DT)
		if not h.darting and absf(h.global_position.distance_to(h.centre()) - h.orbit_radius()) < 0.2:
			back = true
			break
	assert_bool(back).is_true()
	# and every sting still lands
	var t := 0.0
	while t < 8.0 and not h.is_queued_for_deletion():
		h.tick(DT)
		t += DT
	assert_int(h.stings_done).is_equal(5)


func test_the_hawk_drops_when_its_prey_dies_and_never_takes_another() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var inst := _inst("hornet_nest", ["tarantula_hawk"], 3)
	var a := _creature(em, Vector3(-3, 0, 0), 20.0)
	var b := _creature(em, Vector3(3, 0, 2), 20.0)
	em._rebuild_grid()
	var h := TarantulaHawk.launch(w["g"], inst, Vector3(0, 1.6, 0), a, inst.params["hawk"])
	for n in range(40):
		h.tick(DT)
	assert_int(h.state).is_equal(TarantulaHawk.HOLD)
	# one hawk a creature: the other one is the next pick
	assert_int(TarantulaHawk.pick(em, Vector3.ZERO, 12.0, TarantulaHawk.held_serials(w["g"]))).is_equal(b)
	em.damage(a, 99999.0, "x")
	var s := h.stings_done
	for n in range(60):
		h.tick(DT)
	assert_int(h.state).is_equal(TarantulaHawk.FALLING)
	assert_bool(h.is_queued_for_deletion()).is_true()
	assert_int(h.stings_done).is_equal(s)
	assert_int(h.prey).is_equal(a)


# ---------------------------------------------------------------- Pollen on the HUD

func test_pollen_is_one_timed_plate_with_its_seconds_gone_at_zero() -> void:
	var hud: HUD = auto_free(HUD.new())
	add_child(hud)
	# a picked flower: every held weapon carrying Pollen gets its buff for params.pollen.seconds (5)
	Run.add_weapon(Registry.weapon("hornet_nest"), 1)
	assert_bool(Run.add_mutation("pollen", true)).is_true()
	FlowerField.give_buff(null)
	assert_float(Run.boost_left(FlowerField.buff_id("hornet_nest"))).is_equal_approx(5.0, 0.001)
	hud._refresh_buffs()
	assert_int(hud._buffs.get_child_count()).is_equal(1)
	var p: WPlate = hud._buffs.get_child(0)
	assert_str(str(p.get_meta("buff"))).is_equal(FlowerField.MUTATION)
	assert_str(p.level_text).is_equal("5")
	assert_object(p.tex).is_same(Registry.mutation("pollen").icon)
	assert_bool(p.fill.is_equal_approx(W.SAGE)).is_true()
	# a second weapon carrying it (the arena's hand can give both): still one plate, showing the longer of the two
	Run.add_timed_effects(FlowerField.buff_id("hive_queen"), "Pollen", [], 3.0, true)
	hud._refresh_buffs()
	assert_int(hud._buffs.get_child_count()).is_equal(1)
	assert_str((hud._buffs.get_child(0) as WPlate).level_text).is_equal("5")
	# beside a power-up's plate
	Run.add_timed_effects("rage", "BERSERK", [], 10.0)
	hud._refresh_buffs()
	assert_int(hud._buffs.get_child_count()).is_equal(2)
	# it counts down on the buffs' clock...
	Run.held_time += 2.0
	hud._refresh_buffs()
	var pollen: Array = hud._buffs.get_children().filter(func(c: Node) -> bool: return str(c.get_meta("buff")) == FlowerField.MUTATION)
	assert_int(pollen.size()).is_equal(1)
	assert_str((pollen[0] as WPlate).level_text).is_equal("3")
	# ...and goes at 0, before Run.tick_timed has taken the buff off
	Run.held_time += 3.01
	hud._refresh_buffs()
	assert_int(hud._buffs.get_child_count()).is_equal(1)
	assert_str(str(hud._buffs.get_child(0).get_meta("buff"))).is_equal("rage")
	Run.tick_timed()
	assert_float(Run.boost_left(FlowerField.buff_id("hornet_nest"))).is_equal(0.0)
	hud._refresh_buffs()
	assert_int(hud._buffs.get_child_count()).is_equal(1)
	# only a Pollen buff or a pickup's has a plate
	assert_str(HUD.plate_key(FlowerField.buff_id("hornet_nest"))).is_equal(FlowerField.MUTATION)
	assert_str(HUD.plate_key("rage")).is_equal("rage")
	assert_str(HUD.plate_key("skedaddle")).is_equal("")


func test_no_pointer_shows_where_the_flowers_are() -> void:
	var w := _world()
	var g: Node = w["g"]
	var rig := Node.new()
	rig.set_script(_script(FAKE_RIG))
	g.add_child(rig)
	var cam := Camera3D.new()
	rig.add_child(cam)
	cam.fov = 55.0
	cam.global_position = Vector3(0, 22.5 * sin(deg_to_rad(46.0)), 22.5 * cos(deg_to_rad(46.0)))
	cam.look_at(Vector3.ZERO)
	cam.current = true
	rig.set("camera", cam)
	g.camera = rig
	var d := Node.new()
	d.set_script(_script(FAKE_DIRECTOR))
	g.add_child(d)
	g.director = d
	var hud: HUD = auto_free(HUD.new())
	add_child(hud)
	hud.game = g
	# three flowers far off the screen
	var f := FlowerField.ensure(g)
	for at: Vector3 in [Vector3(40, 0, 0), Vector3(-40, 0, 8), Vector3(0, 0, -60)]:
		f.grow_at(at, false)
	assert_int(f.positions().size()).is_equal(3)
	hud._tick_arrow()
	assert_int(hud._arrows.size()).is_equal(0)
	# the pointers still work: an Elite off the screen has its tag, and it is the only one
	d.set("elite_at", Vector3(70, 0, 0))
	hud._tick_arrow()
	assert_int(hud._arrows.size()).is_equal(1)
	assert_str(str(hud._arrows[0]["text"])).starts_with("ELITE")


# ---------------------------------------------------------------- the Killer Bees

func test_the_hornet_nest_is_called_killer_bees_everywhere() -> void:
	assert_str(Registry.weapon("hornet_nest").display_name).is_equal("Killer Bees")
	assert_str(Registry.mutation("ember_hornets").display_name).is_equal("Ember Bees")
	for id: String in FAMILY:
		var d: WeaponDef = Registry.weapon(id)
		assert_object(d).override_failure_message(id).is_not_null()
		_no_hornet(d.display_name + " " + d.flavour, id)
		var inst := _inst(id)
		var desc := TextGen.weapon_description(d, inst.sheet, inst.params)
		_no_hornet(desc, id + "'s description")
		assert_str(desc).contains("killer bee")
	for id: String in FAMILY_MUTATIONS:
		var m: MutationDef = Registry.mutation(id)
		assert_object(m).override_failure_message(id).is_not_null()
		_no_hornet(m.display_name + " " + m.flavour + " " + m.text, id)
	assert_str(Registry.mutation("second_sting").text).contains("bee")
	assert_str(Registry.mutation("tarantula_hawk").text).contains("4 s")
	var q: QuestDef = Registry.quests.get("unlock_hornet_nest")
	assert_object(q).is_not_null()
	assert_str(q.display_name).is_equal("Killer Bees")
	_no_hornet(q.display_name + " " + TextGen.quest_text(q), "the unlock quest")
	for id: String in FlowerField.KINDS:
		var pk: PickupDef = Registry.pickup(id)
		_no_hornet(pk.display_name + " " + pk.flavour, id)
	# Pollen's buff is aimed at the weapon by its id; the words name it
	var e := Effect.make("amount", "mul", 3.0, "weapon:hornet_nest")
	assert_str(TextGen.describe_effect(e)).contains("Killer Bees")
	_no_hornet(TextGen.describe_effect(e), "Pollen's effect")
	assert_str(TextGen.weapon_name("no_such_gun")).is_equal("No Such Gun")


func test_the_nest_is_a_honey_gold_beehive_and_the_bees_stay_small_yellow() -> void:
	for id: String in FAMILY:
		var vis: Node3D = auto_free((Registry.weapon(id).visual as PackedScene).instantiate())
		var body := vis.get_node_or_null("Familiar/Body")
		assert_object(body).override_failure_message(id).is_not_null()
		# the grey paper nest and its hole are gone: stacked honey-gold rings and a dark door
		assert_object(body.get_node_or_null("Nest")).is_null()
		var rings := body.get_children().filter(func(n: Node) -> bool: return n is MeshInstance3D and (n as MeshInstance3D).mesh is TorusMesh and str(n.name).begins_with("Ring"))
		assert_int(rings.size()).override_failure_message(id).is_greater_equal(6)
		var straw := (rings[0] as MeshInstance3D).material_override as StandardMaterial3D
		assert_float(straw.albedo_color.r).is_greater(0.8)
		assert_float(straw.albedo_color.g).is_greater(straw.albedo_color.b + 0.3)
		assert_object(body.get_node_or_null("Door")).is_not_null()
		# the bee: the same small yellow capsule
		var proj := vis.get_node("Projectile") as MeshInstance3D
		assert_bool(proj.mesh is CapsuleMesh).is_true()
		assert_float((proj.mesh as CapsuleMesh).radius).is_equal_approx(0.07, 0.001)
		assert_bool((proj.material_override as StandardMaterial3D).albedo_color.is_equal_approx(Color(1, 0.8, 0.2))).is_true()
	# the Hive Queen wears a crown
	var hq: Node3D = auto_free((Registry.weapon("hive_queen").visual as PackedScene).instantiate())
	assert_object(hq.get_node_or_null("Familiar/Body/Crown")).is_not_null()
	# the pod still finds its companion and draws its bees, and they come out of the hive's door
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	_creature(em, Vector3(5, 0, 0))
	em._rebuild_grid()
	var inst := _inst("hornet_nest")
	var mp: MissilePod = auto_free(MissilePod.new())
	(w["g"] as Node).add_child(mp)
	mp.setup(inst, w["g"])
	assert_object(mp._familiar).is_not_null()
	assert_object(mp._entrance).is_not_null()
	assert_int(mp.projectile_kind).is_greater_equal(0)
	var door := mp._entrance.global_position
	assert_bool(mp._fire()).is_true()
	mp._tick(0.01)
	var out: Array = []
	for j in range(ProjectileManager.MAX):
		if pm.alive[j] == 1 and pm.weapon[j] == inst:
			out.append(j)
	assert_int(out.size()).is_equal(1)
	assert_float(pm.pos[out[0]].distance_to(door)).is_less(0.05)
