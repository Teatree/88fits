extends GdUnitTestSuite

## Pass 95, lane BREATH: the Dragon's Breath (FireBreath): a cone of fire from the hero's face where he faces, every
## creature whose body stands in it hit every second (the first the moment it is inside) and set burning, the breath
## lengthened a second per point of amount (capped), the wait rule (a creature in the cone, or anyone within reach after
## the wait); Backdraft's shove every tick; Blue Flame's blue fire on the breath and the burning creatures; Held Breath's
## still rule (twice as long, x1.5, a ring; a hit breaks the stillness, never a breath already burning); the Fire Eater's
## thorns on the hero while held (a weapon level effect aimed at "player"); the words, the rows, the estimate; the shape
## rule for its path; the sounds; the jet's budget.

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
var hits := 0
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	hits += 1
func fx_sand(_a, _b = 1.0) -> void:
	pass
func fx_ignite(_a, _b = 1.0, _c = false) -> void:
	pass
func fx_fire(_a, _b = 1.0, _c = false) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var still_unhit := 0.0
func forward() -> Vector3:
	return Vector3(-sin(facing), 0, -cos(facing))
func aim_origin(d: Vector3) -> Vector3:
	return global_position + Vector3(0, 0.8, 0)
func face_origin(d: Vector3) -> Vector3:
	return global_position + Vector3(0, 1.45, 0) + d.normalized() * 0.3
func still_unhit_seconds() -> float:
	return still_unhit
"""

const DT := 1.0 / 60.0
const WID := "dragons_breath"
const PATH := ["blue_flame", "held_breath", "backdraft"]


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero at the origin facing -Z with the real crowd, effects and ground marks; no crits to roll;
## every creature a ranged pick (no screen filter).
func _world() -> Dictionary:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.player_sheet.set_base("crit_chance", 0.0)
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
	em.screen_filter_on = false
	var fx := Fx.new()
	g.add_child(fx)
	g.fx = fx
	var tg := Telegraphs.new()
	g.add_child(tg)
	g.telegraphs = tg
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em, "fx": fx}


func _inst(id: String, muts: Array = [], level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m: String in muts:
		var md: MutationDef = Registry.mutation(m)
		assert_object(md).override_failure_message("no mutation " + m).is_not_null()
		inst.mutations.append(md)
	inst.rebuild(Run.player_sheet, [inst])
	return inst


func _breath(w: Dictionary, id := WID, muts: Array = [], level := 1) -> FireBreath:
	var b := FireBreath.new()
	(w["g"] as Node).add_child(b)
	b.setup(_inst(id, muts, level), w["g"])
	return b


## A tough creature standing where it was put, up out of the sand, a ranged pick.
func _creature(em: EnemyManager, at: Vector3, hp_mult := 50.0, id := "skeleton") -> int:
	var i := em.spawn(id, at, null, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	if em.rise_t.size() > i:
		em.rise_t[i] = 1.0
	em._rebuild_grid()
	return i


func _tick(b: FireBreath, seconds: float) -> void:
	var n := int(round(seconds / DT))
	for k in range(n):
		b._tick(DT)


# ---------------------------------------------------------------- content and shape

func test_the_weapon_is_whole_and_in_the_card_pool() -> void:
	var w: WeaponDef = Registry.weapon(WID)
	assert_object(w).is_not_null()
	assert_str(w.behavior).is_equal("FireBreath")
	assert_str(w.targeting).is_equal("forward")
	assert_str(w.rarity).is_equal("rare")
	assert_bool(w.hidden).is_false()
	assert_str(w.hero).is_equal("")
	assert_int(w.max_level).is_equal(5)
	assert_int(w.levels.size()).is_equal(5)
	assert_array(w.levels[0]).is_empty()
	# the slowest weapon in the game, at level 1 and at level 5 (the Turret Buddy's 6 s is next)
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var mine5 := _inst(WID, [], 5).stat("cooldown")
	for o: WeaponDef in Registry.base_weapons():
		if o.id != WID and not o.hidden:
			assert_float(float(w.base.get("cooldown", 0.0))).override_failure_message(o.id + " is slower").is_greater(float(o.base.get("cooldown", 1.0)))
			assert_float(mine5).override_failure_message(o.id + " is slower at 5").is_greater(_inst(o.id, [], 5).stat("cooldown"))
	assert_bool(Registry.unlocked_weapons().has(w)).is_true()
	assert_bool(CardPool.offer_weapons().has(w)).is_true()
	# the path: one of each kind, in element / volume / motion order (pass66_shape_test's rule)
	var path: Array = Registry.mutations_of(WID)
	assert_array(path.map(func(m: MutationDef) -> String: return m.id)).is_equal(["blue_flame", "held_breath", "backdraft"])
	assert_array(path.map(func(m: MutationDef) -> String: return m.mutation_kind)).is_equal(["element", "volume", "motion"])
	for m: MutationDef in path:
		assert_str(m.weapon).is_equal(WID)
		assert_str(m.text).is_not_empty()
	assert_str(Registry.mutation("blue_flame").element).is_equal("fire")
	assert_bool(bool(Registry.mutation("blue_flame").params.get("fire_blue", false))).is_true()
	# the evolution
	assert_str(w.evolves_into).is_equal("fire_eater")
	var ev: WeaponDef = Registry.weapon("fire_eater")
	assert_object(ev).is_not_null()
	assert_bool(ev.is_evolution).is_true()
	assert_str(ev.evolved_from).is_equal(WID)
	assert_str(ev.behavior).is_equal("FireBreath")
	assert_bool(Registry.is_hidden(ev)).is_false()
	assert_int(ev.player_effects(1).size()).is_equal(1)
	assert_str((ev.player_effects(1)[0] as Effect).stat).is_equal("thorns")
	assert_float((ev.player_effects(1)[0] as Effect).value).is_equal_approx(8.0, 0.001)
	assert_int(w.player_effects(5).size()).is_equal(0)
	# the sounds
	assert_bool(Registry.soundmap.entries.has("w_breath_start")).is_true()
	assert_bool(Registry.soundmap.entries.has("w_breath_loop")).is_true()
	assert_bool(bool(Registry.soundmap.entries["w_breath_loop"].get("loop", false))).is_true()
	assert_object(Registry.soundmap.entries["w_breath_loop"].get("stream")).is_not_null()
	assert_object(Registry.soundmap.entries["w_breath_start"].get("stream")).is_not_null()
	# icons on disk
	assert_object(w.icon).is_not_null()
	assert_object(ev.icon).is_not_null()
	for m: MutationDef in path:
		assert_object(m.icon).override_failure_message(m.id + " has no icon").is_not_null()


func test_the_words_the_rows_and_the_estimate() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var inst := _inst(WID)
	var words := inst.description()
	assert_str(words).contains("Breathes")
	assert_str(words).contains("cone of fire")
	assert_str(words).contains("where you face")
	assert_str(words).contains("every second")
	assert_str(words).contains("Sets on fire")
	var rows: Array = inst.stat_rows()
	var stats: Array = rows.map(func(r: Dictionary) -> String: return str(r["stat"]))
	assert_array(stats).contains(["damage", "cooldown", "duration", "range", "cone_deg", "fire_damage", "dps"])
	assert_float(inst.breath_seconds()).is_equal_approx(2.0, 0.001)
	assert_int(inst.breath_ticks()).is_equal(2)
	assert_float(inst.breath_cone_deg()).is_equal_approx(50.0, 0.001)
	# the estimate: two ticks of the damage on three creatures over the cooldown
	var dmg := inst.stat("damage")
	var cd := inst.stat("cooldown")
	assert_float(inst.dps_estimate()).is_equal_approx(dmg * 2.0 * WeaponInstance.BREATH_CATCH / cd, 0.01)
	# HeroPower: one target, the burn for the share of the time it is lit ((2 + fire_duration) / cooldown)
	assert_float(HeroPower.crowd_of(inst)).is_equal_approx(WeaponInstance.BREATH_CATCH, 0.001)
	var up := (2.0 + inst.stat("fire_duration")) / cd
	assert_float(HeroPower.element_uptime(inst)).is_equal_approx(up, 0.001)
	assert_float(HeroPower.weapon_dps(inst)).is_equal_approx(dmg * 2.0 / cd + inst.stat("fire_damage") / 0.6 * up, 0.01)
	assert_float(HeroPower.element_uptime(_inst("molotov"))).is_equal_approx(1.0, 0.001)
	assert_str(TextGen.amount_noun(inst.def, inst.sheet, inst.params)).is_equal("seconds of breath")
	# the path's words
	var full := _inst(WID, PATH, 5)
	var fw := full.description()
	assert_str(fw).contains("shoves them away")
	assert_str(fw).contains("Stand still 2 s")
	assert_str(fw).contains("from all sides")
	var frows: Array = full.stat_rows()
	assert_array(frows.map(func(r: Dictionary) -> String: return str(r["stat"]))).contains(["knockback", "still"])


# ---------------------------------------------------------------- the cone

func test_the_cone_hits_the_bodies_inside_and_nothing_outside() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var b := _breath(w)
	var a := _creature(em, Vector3(0, 0, -3))          # dead ahead
	var behind := _creature(em, Vector3(0, 0, 3))      # behind him
	var side := _creature(em, Vector3(3, 0, -1))       # 72 degrees off: outside a 50 degree cone
	var edge := _creature(em, Vector3(1.2, 0, -3))     # 22 degrees off: inside
	var far := _creature(em, Vector3(0, 0, -7))        # past the 5 m reach
	var hp0: float = em.hp[a]
	assert_bool(b._fire()).is_true()
	assert_int(b.breaths).is_equal(1)
	assert_bool(b.burning()).is_true()
	var hits := Array(b.last_hits)
	hits.sort()
	var want := [a, edge]
	want.sort()
	assert_array(hits).is_equal(want)
	# a tick of 12 the moment they stand in it, and the burn
	var tick: float = b.stat("damage")
	assert_float(em.hp[a]).is_equal_approx(hp0 - tick, 0.01)
	assert_float(em.hp[edge]).is_equal_approx(hp0 - tick, 0.01)
	assert_float(em.hp[behind]).is_equal_approx(hp0, 0.01)
	assert_float(em.hp[side]).is_equal_approx(hp0, 0.01)
	assert_float(em.hp[far]).is_equal_approx(hp0, 0.01)
	assert_bool(em.is_burning(a)).is_true()
	assert_bool(em.is_burning(edge)).is_true()
	assert_bool(em.is_burning(behind)).is_false()
	assert_int(b.ticks).is_equal(2)


func test_a_creature_in_the_fire_takes_a_tick_every_second_and_the_breath_ends_on_time() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var b := _breath(w)
	var a := _creature(em, Vector3(0, 0, -3))
	var hp0: float = em.hp[a]
	assert_bool(b._fire()).is_true()
	assert_float(b.last_len).is_equal_approx(2.0, 0.001)
	_tick(b, 0.5)
	assert_int(b.ticks).is_equal(1)
	_tick(b, 0.6)
	# the second tick at 1.0 s
	assert_int(b.ticks).is_equal(2)
	assert_float(em.hp[a]).is_equal_approx(hp0 - 2.0 * b.stat("damage"), 0.5)
	_tick(b, 1.0)
	assert_bool(b.burning()).is_false()
	# two ticks in a 2 s breath (0 and 1 s), none at the end
	assert_int(b.ticks).is_equal(2)
	# a creature that walks in late takes its first tick at once
	assert_bool(b._fire()).is_true()
	_tick(b, 0.5)
	var late := _creature(em, Vector3(0.5, 0, -2))
	var hl: float = em.hp[late]
	_tick(b, DT)
	assert_float(em.hp[late]).is_equal_approx(hl - b.stat("damage"), 0.01)


func test_the_cone_follows_his_facing_while_it_burns() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var b := _breath(w)
	var ahead := _creature(em, Vector3(0, 0, -3))
	var right := _creature(em, Vector3(3, 0, 0))
	assert_bool(b._fire()).is_true()
	assert_bool(Array(b.last_hits).has(ahead)).is_true()
	assert_bool(Array(b.last_hits).has(right)).is_false()
	# he turns to his right (+X) while it burns: the fire turns with him
	hero.facing = -PI * 0.5
	_tick(b, 0.1)
	assert_bool(Array(b.last_hits).has(right)).is_true()
	assert_bool(Array(b.last_hits).has(ahead)).is_false()


func test_it_waits_for_a_creature_in_the_cone_then_breathes_anyway_at_anyone_in_reach() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var b := _breath(w)
	# nobody at all: nothing
	assert_bool(b._fire()).is_false()
	var side := _creature(em, Vector3(4, 0, 0))   # within 5 m, outside the cone
	assert_bool(b._fire()).is_false()
	assert_int(b.breaths).is_equal(0)
	# the cooldown ready for longer than the wait: it breathes where he faces, hitting nobody
	b.cooldown_left = 0.0
	_tick(b, 2.1)
	assert_float(b._ready_for).is_greater_equal(2.0)
	assert_bool(b._fire()).is_true()
	assert_int(b.breaths).is_equal(1)
	assert_array(Array(b.last_hits)).is_empty()
	assert_float(em.hp[side]).is_equal_approx(em.max_hp[side], 0.01)


func test_amount_lengthens_the_breath_up_to_the_cap() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.player_sheet.set_base("amount", 2.0)
	var three := _inst(WID)
	assert_int(three.stat_int("amount", 1)).is_equal(3)
	assert_float(three.breath_seconds()).is_equal_approx(4.0, 0.001)
	assert_int(three.breath_ticks()).is_equal(4)
	Run.player_sheet.set_base("amount", 9.0)
	var ten := _inst(WID)
	assert_float(ten.breath_seconds()).is_equal_approx(6.0, 0.001)
	Run.player_sheet.set_base("amount", 0.0)
	# level 5: duration 3, two cooldown cuts, two range steps
	var five := _inst(WID, [], 5)
	assert_float(five.breath_seconds()).is_equal_approx(3.0, 0.001)
	assert_int(five.breath_ticks()).is_equal(3)
	assert_float(five.stat("cooldown")).is_equal_approx(9.0 * 0.88 * 0.88, 0.001)
	assert_float(five.stat("range")).is_equal_approx(6.0, 0.001)
	assert_float(five.breath_cone_deg()).is_equal_approx(60.0, 0.001)
	# in the world: a 4 s breath with amount 3
	var w := _world()
	Run.player_sheet.set_base("amount", 2.0)
	var b := _breath(w)
	_creature(w["em"], Vector3(0, 0, -3))
	assert_bool(b._fire()).is_true()
	assert_float(b.last_len).is_equal_approx(4.0, 0.001)
	_tick(b, 3.5)
	assert_bool(b.burning()).is_true()
	assert_int(b.ticks).is_equal(4)
	_tick(b, 0.6)
	assert_bool(b.burning()).is_false()
	Run.player_sheet.set_base("amount", 0.0)


# ---------------------------------------------------------------- the path

func test_backdraft_shoves_what_stands_in_the_fire_every_tick() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.hero_knockback_override = 1.0
	var plain := _breath(w)
	var a := _creature(em, Vector3(0, 0, -3))
	assert_bool(plain._fire()).is_true()
	assert_int(plain.knocks).is_equal(0)
	assert_float(em.kb[a].length()).is_equal_approx(0.0, 0.001)
	plain.queue_free()
	var b := _breath(w, WID, ["backdraft"])
	# pass 103 (lane PLAY): Backdraft's knock a third lower, 5.0 -> 3.3 (the JSON's number)
	assert_float(b.bval("knock")).is_equal_approx(float(((Registry.mutation("backdraft").params as Dictionary)["breath"] as Dictionary)["knock"]), 0.001)
	assert_float(b.intensity()).is_equal_approx(1.5, 0.001)
	assert_bool(b._fire()).is_true()
	assert_int(b.knocks).is_equal(1)
	# straight away from the hero: further down -Z
	assert_float(em.kb[a].z).is_less(-0.01)
	assert_float(absf(em.kb[a].x)).is_less(0.01)
	var k1: float = em.kb[a].z
	em.kb[a] = Vector3.ZERO
	_tick(b, 1.05)
	assert_int(b.knocks).is_equal(2)
	assert_float(em.kb[a].z).is_equal_approx(k1, 0.05)


func test_blue_flame_burns_the_breath_and_the_creatures_blue_further_and_longer() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var plain := _inst(WID)
	var blue := _inst(WID, ["blue_flame"])
	assert_bool(blue.blue_fire()).is_true()
	assert_bool(plain.blue_fire()).is_false()
	assert_float(blue.stat("range")).is_equal_approx(plain.stat("range") * 1.25, 0.001)
	assert_float(blue.stat("damage")).is_equal_approx(plain.stat("damage") * 0.8, 0.001)
	assert_float(blue.stat("fire_duration")).is_equal_approx(plain.stat("fire_duration") * 1.75, 0.001)
	assert_str(blue.element()).is_equal("fire")
	# in the world, held by the run so the crowd's fire finds the weapon's blue
	var b := FireBreath.new()
	(w["g"] as Node).add_child(b)
	Run.weapons.append(blue)
	b.setup(blue, w["g"])
	assert_bool(b.blue()).is_true()
	var a := _creature(em, Vector3(0, 0, -3))
	assert_bool(b._fire()).is_true()
	assert_bool(em.is_burning(a)).is_true()
	assert_int(em.fire_blue[a]).is_equal(1)
	Run.weapons.erase(blue)


func test_held_breath_doubles_a_still_attack_hits_harder_and_rings_all_round() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var b := _breath(w, WID, ["held_breath"])
	var ahead := _creature(em, Vector3(0, 0, -3))
	var behind := _creature(em, Vector3(0, 0, 3))
	var hp0: float = em.hp[ahead]
	# moving (or hit lately): a plain breath, the creature behind untouched
	hero.still_unhit = 1.0
	assert_bool(b._fire()).is_true()
	assert_int(b.still_breaths).is_equal(0)
	assert_bool(b.is_ring()).is_false()
	assert_float(b.last_len).is_equal_approx(2.0, 0.001)
	var tick: float = b.stat("damage")
	assert_float(em.hp[ahead]).is_equal_approx(hp0 - tick, 0.01)
	assert_float(em.hp[behind]).is_equal_approx(hp0, 0.01)
	_tick(b, 2.1)
	assert_bool(b.burning()).is_false()
	# still and unhit for 2 s: twice as long, x1.5, from all sides
	var hp1: float = em.hp[ahead]
	var hb1: float = em.hp[behind]
	hero.still_unhit = 2.0
	assert_bool(b._fire()).is_true()
	assert_int(b.still_breaths).is_equal(1)
	assert_bool(b.is_ring()).is_true()
	assert_float(b.last_len).is_equal_approx(4.0, 0.001)
	assert_float(em.hp[ahead]).is_equal_approx(hp1 - 1.5 * tick, 0.01)
	assert_float(em.hp[behind]).is_equal_approx(hb1 - 1.5 * tick, 0.01)
	# a hit while it burns breaks the stillness but never the breath (3.05 s in: the ticks at 0, 1, 2 and 3 s landed)
	hero.still_unhit = 0.0
	_tick(b, 3.05)
	assert_bool(b.burning()).is_true()
	assert_bool(b.is_ring()).is_true()
	assert_float(em.hp[behind]).is_equal_approx(hb1 - 1.5 * tick * 4.0, 0.5)
	_tick(b, 1.05)
	assert_bool(b.burning()).is_false()
	# the next one, right after the hit, is a plain breath again
	assert_bool(b._fire()).is_true()
	assert_bool(b.is_ring()).is_false()
	assert_int(b.still_breaths).is_equal(1)


func test_the_heros_stillness_counts_only_unhit_seconds_and_steady_hands_still_is_untouched() -> void:
	var p = preload("res://player/Player.gd").new()
	p._still_raw = 3.0
	assert_float(p.still_seconds()).is_equal_approx(2.5, 0.001)
	p._tick_hit_ago(5.0)
	assert_float(p.still_unhit_seconds()).is_equal_approx(2.5, 0.001)
	p._note_hit_for_still()
	assert_float(p.still_unhit_seconds()).is_equal_approx(0.0, 0.001)
	# Steady Hand's seconds go on
	assert_float(p.still_seconds()).is_equal_approx(2.5, 0.001)
	p._tick_hit_ago(1.0)
	assert_float(p.still_unhit_seconds()).is_equal_approx(1.0, 0.001)
	p._tick_hit_ago(5.0)
	assert_float(p.still_unhit_seconds()).is_equal_approx(2.5, 0.001)
	# his face, up his painting and a little forward
	p.facing = 0.0
	var f: Vector3 = p.face_origin(Vector3.FORWARD)
	assert_float(f.y).is_equal_approx(1.45, 0.001)
	assert_float(f.z).is_equal_approx(-0.3, 0.001)
	p.free()


# ---------------------------------------------------------------- the evolution

func test_the_fire_eater_puts_thorns_on_the_hero_while_held_and_amplifies_the_breath() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.debug_clear_items()
	assert_float(Run.player_sheet.get_stat("thorns", 0.0)).is_equal_approx(0.0, 0.001)
	var w := Run.add_weapon(Registry.weapon(WID), 5)
	assert_object(w).is_not_null()
	for m: String in PATH:
		Run.debug_set_item("mutation", m, 1)
	assert_float(Run.player_sheet.get_stat("thorns", 0.0)).is_equal_approx(0.0, 0.001)
	var base_dps := w.dps_estimate()
	var ev := Run.evolve(w)
	assert_object(ev).is_not_null()
	assert_str(ev.def.id).is_equal("fire_eater")
	assert_int(ev.mutations.size()).is_equal(3)
	# the thorns land the moment it evolves, named by the weapon
	assert_float(Run.player_sheet.get_stat("thorns", 0.0)).is_equal_approx(8.0, 0.001)
	var sids: Array = Run.player_sheet.entries.filter(func(en: Dictionary) -> bool: return (en["effect"] as Effect).stat == "thorns").map(func(en: Dictionary) -> String: return str(en["source"]))
	assert_array(sids).contains(["weapon:fire_eater"])
	assert_str(str(StatSources.describe_source("weapon:fire_eater")["name"])).is_equal("Fire Eater")
	# amplified: the path stays on (blue, Backdraft's shove stronger, Held Breath), more a second than the base at 5
	assert_bool(ev.blue_fire()).is_true()
	# pass 103 (lane PLAY): a third lower, 7.0 -> 4.7
	assert_float(float((ev.params["breath"] as Dictionary).get("knock", 0.0))).is_equal_approx(4.7, 0.001)
	assert_bool((ev.params["breath"] as Dictionary).has("still")).is_true()
	assert_float(float(((ev.params["breath"] as Dictionary)["look"] as Dictionary).get("intensity", 1.0))).is_equal_approx(1.8, 0.001)
	assert_float(ev.dps_estimate()).is_greater(base_dps)
	assert_float(ev.breath_seconds()).is_equal_approx(3.5, 0.001)
	# the weapon gone, the thorns gone
	Run.debug_clear_items()
	assert_float(Run.player_sheet.get_stat("thorns", 0.0)).is_equal_approx(0.0, 0.001)
	# a weapon added at once at its evolved form carries them too
	Run.add_weapon(Registry.weapon("fire_eater"))
	assert_float(Run.player_sheet.get_stat("thorns", 0.0)).is_equal_approx(8.0, 0.001)
	Run.debug_clear_items()


# ---------------------------------------------------------------- the look

func test_the_jet_stays_within_its_budget_and_is_nothing_in_the_sim() -> void:
	var w := _world()
	var fx: Fx = w["fx"]
	var n0: int = fx._n
	fx.breath_jet(Vector3(0, 1.45, 0), Vector3.FORWARD, 5.0, 50.0, 3, 0.55, false, false)
	assert_int(fx._n - n0).is_between(3, 4)
	fx.breath_jet(Vector3(0, 1.45, 0), Vector3.FORWARD, 5.0, 360.0, 2, 0.55, true, true)
	assert_int(fx._n - n0).is_between(5, 7)
	fx.breath_jet(Vector3(0, 1.45, 0), Vector3.ZERO, 5.0, 50.0, 3)
	assert_int(fx._n - n0).is_between(5, 7)
	Run.sim_mode = true
	fx.breath_jet(Vector3(0, 1.45, 0), Vector3.FORWARD, 5.0, 50.0, 3)
	Run.sim_mode = false
	assert_int(fx._n - n0).is_between(5, 7)
	# the breath itself in the world: it burns, flames come, the sound loop runs, and the end stops it
	var b := _breath(w)
	_creature(w["em"], Vector3(0, 0, -3))
	var before: int = fx._n
	assert_bool(b._fire()).is_true()
	_tick(b, 0.5)
	assert_int(fx._n).is_greater(before)
	_tick(b, 1.6)
	assert_bool(b.burning()).is_false()
	assert_bool(b._loop_on).is_false()
