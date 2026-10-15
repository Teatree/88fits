extends GdUnitTestSuite

## Pass 33.2: the crab and the jackalope out of the rotation, twice the fodder at half each, the armadillo, the rocket at
## 90% of the hero, the death log, Evade, the Energy Shield, line evolutions, the drop passives, the far-zoom marks, the
## laser that leaves the mouth.

const FAKE_GAME := """extends Node
var player: Node3D
var projectiles: ProjectileManager
var enemies = null
var map = null
var camera = null
var paused := false
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var velocity := Vector3.ZERO
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func max_speed() -> float:
	# like the real hero's, with the map's move_pace in it (pass 60: the rocket divides that knob out, so a flat 5 read
	# as 5 / 0.9 whenever an earlier suite had left Red Canyon loaded)
	return 5.0 * Run.move_pace()
func aim_origin(_d: Vector3) -> Vector3:
	return global_position + Vector3(0, 1.0, 0)
func forward() -> Vector3:
	return Vector3.FORWARD
"""

const FAKE_CAMERA := """extends Node
var z := 2.5
func zoom() -> float:
	return z
func current_yaw() -> float:
	return 0.0
"""


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _fake_game(hero_at: Vector3) -> Node:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = hero_at
	g.player = hero
	var pm := ProjectileManager.new()
	pm.game = g
	g.add_child(pm)
	g.projectiles = pm
	pm.register_kind(BoxMesh.new(), null)
	return g


func _hero() -> Player:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	add_child(p)
	p.setup(Registry.character("astro"))
	p.hp = p.max_hp
	return p


func test_the_crab_and_the_jackalope_are_out_of_the_rotation() -> void:
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	for t in [100.0, 400.0, 899.0]:
		for r in tl.roster_at(t):
			assert_bool(["sand_crab", "jackalope"].has(str(r["enemy"]))).is_false()
	for ev in tl.events:
		assert_bool(["sand_crab", "jackalope"].has(str(ev.get("enemy", "")))).is_false()
	# kept for later: the art and the logic are still there
	assert_object(Registry.enemy("sand_crab")).is_not_null()
	assert_object(Registry.enemy("jackalope")).is_not_null()
	# and the laser is not locked behind a creature that never comes
	var q: Dictionary = {}
	for qd in Registry.quests.values():
		if qd.id == "unlock_big_mouth":
			q = qd.condition
	assert_str(str(q.get("enemy", ""))).is_equal("armadillo")


func test_the_fodder_comes_twice_as_many_at_half_each() -> void:
	var g: EnemyDef = Registry.enemy("goblin")
	assert_int(g.pack_size).is_equal(6)
	assert_float(g.hp).is_equal_approx(6.0, 0.01)
	assert_float(g.cap_share).is_equal_approx(0.5, 0.001)
	# pass 53 (Garry: the ants come at 5:00 as "0.6 of a mummy"): no longer half-share fodder, a full slot each in eights
	var a: EnemyDef = Registry.enemy("fire_ant")
	assert_int(a.pack_size).is_equal(8)
	assert_float(a.hp).is_equal_approx(36.0, 0.01)
	assert_float(a.cap_share).is_equal_approx(1.0, 0.001)
	# half a slot each against the director's cap
	var em: EnemyManager = auto_free(EnemyManager.new())
	add_child(em)
	em.register_type(g)
	for k in range(4):
		em.spawn("goblin", Vector3(k, 0, 0))
	assert_float(em.cap_load()).is_equal_approx(2.0, 0.01)
	assert_int(Registry.map("red_canyon").timeline.hard_cap).is_equal(260)   # pass 43: room for the hell crowd


func test_the_armadillo_arrives_half_way_through_stage_one() -> void:
	var d: EnemyDef = Registry.enemy("armadillo")
	assert_object(d).is_not_null()
	assert_int(d.pack_size).is_greater_equal(5)
	assert_float(d.damage_reduction).is_greater_equal(0.2)
	assert_float(d.hp).is_greater(Registry.enemy("goblin").hp * 2.0)
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	var arrives := -1.0
	for r in tl.roster:
		if str(r["enemy"]) == "armadillo" and (arrives < 0.0 or float(r["t"]) < arrives):
			arrives = float(r["t"])
	# pass 62 (lane PC, re-pinned): the armadillo is stage 2's introduction now (8:56, a wall of them from the top of the
	# screen in its first rush); no row brings it before half way through stage 1
	if arrives >= 0.0:
		assert_float(arrives).is_greater_equal(200.0)
		return
	# half way through stage 1: 2:30 before pass 46 stretched the stage from 300 s to 430 s, 3:35 since; pass 54: Garry's
	# placement in the Level Editor (2026-10-06) brings it in the 12:11 swarm instead of a roster row
	var swarm := false
	for ev in tl.events:
		if str(ev.get("type", "")) == "swarm" and str(ev.get("enemy", "")) == "armadillo":
			swarm = true
	assert_bool(swarm).is_true()


func test_the_rocket_keeps_to_nine_tenths_of_the_hero() -> void:
	# pass 81 (lane POLISH, re-pinned): the share is of the hero's top speed on the ground (the whole creature pace comes
	# out, ProjectileManager.rocket_clock_pace; this fake game has no creatures, so its shot clock is 1): 0.9 x max_speed
	var g := _fake_game(Vector3(0, 0, 60.0))
	var pm: ProjectileManager = g.projectiles
	var i := pm.launch_enemy_rocket(0, 3, Vector3.ZERO, Vector3(0, 0, 1), 4.0, 1.3, 22.0, 1.6, 0.9)
	pm._physics_process(1.0 / 60.0)
	var want: float = 0.9 * float(g.player.max_speed())
	assert_float(float(pm.extra[i]["speed"])).is_equal_approx(want, 0.01)
	assert_float(pm.vel[i].length()).is_equal_approx(want, 0.05)
	assert_float(pm.rocket_ground_speed(i)).is_equal_approx(want, 0.05)


func test_the_death_log_names_the_killer() -> void:
	var p := _hero()
	p.take_damage(8.0, Vector3.ZERO, {"by": "Goblin", "kind": "melee", "fx": ["charge"]})
	p.invuln = 0.0
	p.take_damage(12.0, Vector3.ZERO, {"by": "Sun Prophet (Elite)", "kind": "ranged", "fx": ["knocked back"]})
	p.invuln = 0.0
	p.take_damage(9999.0, Vector3.ZERO, {"by": "Tumbleweed King", "kind": "boss", "fx": ["slam"]})
	var text := p.damage_log_text()
	var lines := text.split("\n")
	assert_int(lines.size()).is_equal(3)
	# newest first, in plain words since pass 46 (the Down! list draws the badges): the killing blow on top
	assert_str(lines[0]).starts_with("FATAL ")
	assert_str(lines[0]).contains("  boss  ")
	assert_str(lines[0]).contains("Tumbleweed King")
	assert_str(lines[1]).contains("  ranged  ")
	assert_str(lines[1]).contains("knocked back")
	assert_str(lines[2]).contains("  melee  ")
	assert_str(lines[2]).contains("Goblin")
	for emoji: String in [char(0x1F480), char(0x1F451), char(0x1F3F9), char(0x1F5E1)]:
		assert_str(text).not_contains(emoji)


func test_evade_takes_no_hit() -> void:
	# the chance is capped at 90%, so over twenty hits most are evaded and an evaded hit costs nothing
	var p := _hero()
	var e := Effect.make("evade", "add", 1.0)
	e.target = "player"
	Run.player_sheet.add_effects([e], "test")
	var landed := 0
	for k in range(20):
		var before := p.hp
		p.invuln = 0.0
		p.take_damage(2.0, Vector3.ZERO, {"by": "Goblin", "kind": "melee"})
		if p.hp < before:
			landed += 1
	assert_int(landed).is_less_equal(8)
	assert_str(p.damage_log_text()).contains("evaded")
	Run.player_sheet.remove_source("test")


func test_the_energy_shield_takes_whole_hits_then_breaks() -> void:
	var p := _hero()
	var e := Effect.make("shield_max", "add", 30.0)
	e.target = "player"
	Run.player_sheet.add_effects([e], "test")
	p.shield_pts = 30.0
	var before := p.hp
	p.take_damage(10.0, Vector3.ZERO, {"by": "Goblin", "kind": "melee"})
	assert_float(p.hp).is_equal(before)
	assert_float(p.shield_pts).is_less(30.0)
	# a hit bigger than what is left breaks it, and none of it reaches health
	p.invuln = 0.0
	p.take_damage(80.0, Vector3.ZERO, {"by": "Bull Beetle", "kind": "melee"})
	assert_float(p.hp).is_equal(before)
	assert_float(p.shield_pts).is_equal(0.0)
	# broken: the next hit is health's
	p.invuln = 0.0
	p.take_damage(10.0, Vector3.ZERO, {"by": "Goblin", "kind": "melee"})
	assert_float(p.hp).is_less(before)
	Run.player_sheet.remove_source("test")


func test_every_former_line_evolves() -> void:
	# the eight lines a level-up offered (pass 33.2), passives since pass 46, each with its single-level evolution; pass
	# 47: fifteen lines (the line flag on the passives), every one evolving into a line; pass 70: twenty-one (Lodestone,
	# Mule Kick, Slow Burn, Tin Star new, Prospector and Gold Tooth made lines)
	var evolving: Array = Registry.base_passives().filter(func(p: PassiveDef) -> bool: return p.evolves_into != "")
	assert_int(evolving.size()).is_equal(21)
	for p: PassiveDef in evolving:
		var evo: PassiveDef = Registry.passive(p.evolves_into)
		assert_object(evo).override_failure_message(p.id + " evolves into nothing").is_not_null()
		assert_str(evo.evolves_from).is_equal(p.id)
		assert_bool(evo.is_evolved()).is_true()
		assert_int(evo.max_level).is_equal(1)
		assert_bool(p.is_line() and evo.is_line()).override_failure_message(p.id + " is not a line pair").is_true()


func test_a_maxed_passive_is_offered_its_evolution_in_the_same_slot() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.add_or_level_passive("magnet")
	for k in range(4):
		Run.add_or_level_passive("vigour")
	Run.add_or_level_passive("haste")
	var evo_card: Dictionary = {}
	for k in range(60):
		for c in CardPool.level_up_offer(4):
			if bool(c.get("evolve", false)):
				evo_card = c
		if not evo_card.is_empty():
			break
	assert_bool(evo_card.is_empty()).override_failure_message("no evolution card in sixty offers").is_false()
	assert_str(str(evo_card["type"])).is_equal("passive")
	assert_str((evo_card["def"] as PassiveDef).id).is_equal("ironclad")
	assert_str(str(evo_card["src_id"])).is_equal("vigour")
	CardPool.apply(evo_card)
	assert_bool(Run.passives.has("vigour")).is_false()
	assert_int(Run.passive_level("ironclad")).is_equal(1)
	# the evolution stands where its source stood: the second of the three
	assert_array(Run.passives.keys()).is_equal(["magnet", "ironclad", "haste"])
	assert_float(Run.player_sheet.get_stat("damage_reduction", 0.0)).is_greater_equal(0.15)


func test_the_drop_passives_drop_small_pickups() -> void:
	# pass 46: Cheese is Cake, its bite a Cake Slice, the same numbers
	assert_float(float(Registry.passive("cake").effects_for_level(5)[0].value)).is_greater(0.0)
	var j: PickupDef = Registry.pickup("cake_slice")
	assert_str(j.effect_kind).is_equal("heal")
	assert_bool(bool(j.params.get("small", false))).is_true()
	var b: PickupDef = Registry.pickup("coin_bag")
	assert_str(b.effect_kind).is_equal("gold")
	assert_bool(bool(b.params.get("magnet", false))).is_true()
	# neither is in the random power-up table: they come only from the passives
	for r in Registry.map("red_canyon").timeline.pickups.get("roster", []):
		assert_bool(["cake_slice", "coin_bag"].has(str(r.get("id", "")))).is_false()


func test_far_zoom_marks_the_crowd() -> void:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var cam := Node.new()
	cam.set_script(_script(FAKE_CAMERA))
	g.add_child(cam)
	g.camera = cam
	var em: EnemyManager = auto_free(EnemyManager.new())
	em.game = g
	add_child(em)
	em.register_type(Registry.enemy("goblin"))
	em._update_mark()
	assert_float(float((em.types[0]["mat"] as ShaderMaterial).get_shader_parameter("mark"))).is_equal_approx(1.0, 0.01)
	cam.z = 1.5
	em._update_mark()
	assert_float(float((em.types[0]["mat"] as ShaderMaterial).get_shader_parameter("mark"))).is_equal_approx(0.0, 0.01)


func test_the_laser_leaves_the_mouth_whichever_way_it_points() -> void:
	var g := _fake_game(Vector3(20.0, 0.0, -10.0))
	var em: EnemyManager = auto_free(EnemyManager.new())
	em.game = g
	add_child(em)
	g.enemies = em
	var inst := WeaponInstance.new(Registry.weapon("big_mouth"), 2)
	inst.rebuild(Run.player_sheet, [inst])
	var b := LaserBeam.new()
	g.add_child(b)
	b.setup(inst, g)
	for yaw in [0.0, -PI * 0.5, PI * 0.5, PI]:
		b._aim_yaw = yaw
		b._beam_t = 1.0
		b._draw_beam()
		var xf: Transform3D = b._beam.global_transform
		# the ribbon's near end is the lips, and it runs along the aim, not along the world's Z
		var near_end: Vector3 = xf.origin - xf.basis.y * 0.5
		assert_float(near_end.distance_to(b.muzzle())).override_failure_message("yaw %.2f: the beam starts %.2f m off the mouth" % [yaw, near_end.distance_to(b.muzzle())]).is_less(0.05)
		var run := xf.basis.y
		run.y = 0.0
		assert_float(run.normalized().dot(b._dir())).is_greater(0.99)
