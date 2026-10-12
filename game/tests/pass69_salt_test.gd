extends GdUnitTestSuite

## Pass 69, lane SALT: the Salt (SaltShaker, SaltPatches). A pour lays `amount` patches back along the hero's way (the
## first a little behind his heels, the next salt.spacing further), round his feet when he stands; a tick hits every
## creature standing in the salt once (two patches over one creature still hit it once) and nothing outside; at most 40
## patches lie (the oldest fades); Sea Salt's longer and pink patches, Salt Spill's wider ones, Thing About Luck's x3
## power-up roll only for a creature killed in the salt, Salt Flats only when the hero walks INTO a patch, Hiwa Kai's
## amplified path, its crunch on the way in and its slow; the words and rows; the shape rule for the Salt's path.

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
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var maxed := 0
var can_max := true
func max_momentum() -> bool:
	if not can_max:
		return false
	maxed += 1
	return true
func forward() -> Vector3:
	return Vector3.FORWARD
func aim_origin(d: Vector3) -> Vector3:
	return global_position + Vector3(0, 0.8, 0)
"""

const DT := 1.0 / 60.0


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero at the origin with the real crowd, effects and ground marks; no crits to roll.
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
	var fx := Fx.new()
	g.add_child(fx)
	g.fx = fx
	var tg := Telegraphs.new()
	g.add_child(tg)
	g.telegraphs = tg
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em}


func _inst(id: String, muts: Array = [], level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m: String in muts:
		var md: MutationDef = Registry.mutation(m)
		assert_object(md).override_failure_message("no mutation " + m).is_not_null()
		inst.mutations.append(md)
	inst.rebuild(Run.player_sheet, [inst])
	return inst


func _salt(w: Dictionary, id := "salt", muts: Array = [], level := 1) -> SaltShaker:
	var b := SaltShaker.new()
	(w["g"] as Node).add_child(b)
	b.setup(_inst(id, muts, level), w["g"])
	return b


## A tough creature standing where it was put.
func _creature(em: EnemyManager, at: Vector3, hp_mult := 50.0, id := "skeleton") -> int:
	var i := em.spawn(id, at, null, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	return i


## The hero walked from `from` to `to` in steps, the shaker noting his way each frame (no pour, no bite).
func _walk(b: SaltShaker, hero: Node3D, from: Vector3, to: Vector3, steps := 40) -> void:
	for k in range(steps + 1):
		hero.global_position = from.lerp(to, float(k) / float(steps))
		b._note_path()


# ---------------------------------------------------------------- content and shape

func test_the_salt_is_a_whole_weapon_in_play_with_its_path_and_evolution() -> void:
	var w: WeaponDef = Registry.weapon("salt")
	assert_object(w).is_not_null()
	assert_str(w.behavior).is_equal("SaltShaker")
	assert_str(w.rarity).is_equal("uncommon")
	assert_bool(w.hidden).is_false()
	assert_str(w.hero).is_equal("")
	assert_bool(w.tags.has("salt") and w.tags.has("ground")).is_true()
	assert_int(w.max_level).is_equal(5)
	var kinds: Array = Registry.mutations_of("salt").map(func(m: MutationDef) -> String: return m.id + ":" + m.mutation_kind)
	assert_array(kinds).is_equal(["sea_salt:element", "salt_spill:volume", "thing_about_luck:motion"])
	var flats: MutationDef = Registry.mutation("salt_flats")
	assert_str(flats.mutation_kind).is_equal("hero")
	assert_str(flats.hero).is_equal("buck")
	assert_str(flats.weapon).is_equal("salt")
	var ev: WeaponDef = Registry.weapon("hiwa_kai")
	assert_bool(ev.is_evolution).is_true()
	assert_str(ev.evolved_from).is_equal("salt")
	assert_str(w.evolves_into).is_equal("hiwa_kai")
	assert_str(ev.behavior).is_equal("SaltShaker")
	# the shaker is the visual's, for both
	assert_object(w.visual).is_not_null()
	assert_object(ev.visual).is_not_null()
	var v: Node = w.visual.instantiate()
	assert_object(v.get_node_or_null("Shaker")).is_not_null()
	assert_int(v.find_children("Contents", "", true, false).size()).is_equal(1)
	v.free()


func test_the_game_makes_a_salt_shaker_for_the_salt() -> void:
	var gs: Script = load("res://game/Game.gd")
	assert_object(gs).is_not_null()
	var g: Node = gs.new()
	var made = g._make_behavior("SaltShaker")
	assert_bool(made is SaltShaker).is_true()
	made.free()
	g.free()


# ---------------------------------------------------------------- the pour

func test_a_pour_lays_amount_patches_back_along_the_way_he_came() -> void:
	var w := _world()
	var hero: Node3D = w["hero"]
	var b := _salt(w, "salt", [], 5)
	assert_int(b.stat_int("amount")).is_equal(3)
	_walk(b, hero, Vector3(-8, 0, 0), Vector3(0, 0, 0))
	assert_bool(b._fire()).is_true()
	assert_int(b.patches.live_count()).is_equal(3)
	assert_int(b.laid).is_equal(3)
	var xs: Array = b.patches.patches.map(func(q: Dictionary) -> float: return (q["at"] as Vector3).x)
	# behind him on his way (he came from -x): 0.4 m back, then 1.2 m apart
	assert_float(float(xs[0])).is_equal_approx(-0.4, 0.05)
	assert_float(float(xs[1])).is_equal_approx(-1.6, 0.05)
	assert_float(float(xs[2])).is_equal_approx(-2.8, 0.05)
	for q: Dictionary in b.patches.patches:
		assert_float(absf((q["at"] as Vector3).z)).is_less(0.01)
		assert_float(float(q["r"])).is_equal_approx(b.patch_radius(), 0.001)


func test_standing_still_the_patches_go_round_his_feet() -> void:
	var w := _world()
	var b := _salt(w, "salt", [], 5)
	(w["hero"] as Node3D).global_position = Vector3(2, 0, 3)
	b._note_path()
	var spots := b.pour_spots(3)
	assert_int(spots.size()).is_equal(3)
	assert_float((spots[0] as Vector3).distance_to(Vector3(2, 0, 3))).is_less(0.01)
	for k in range(1, 3):
		var d: float = (spots[k] as Vector3).distance_to(Vector3(2, 0, 3))
		assert_float(d).is_greater(0.5)
		assert_float(d).is_less(1.2 * 0.8 * sqrt(float(k)) + 0.01)


func test_a_short_walk_lays_what_fits_on_the_way_and_the_rest_round_his_feet() -> void:
	var w := _world()
	var hero: Node3D = w["hero"]
	var b := _salt(w, "salt", [], 5)
	_walk(b, hero, Vector3(-1.0, 0, 0), Vector3(0, 0, 0), 10)
	var spots := b.pour_spots(3)
	assert_int(spots.size()).is_equal(3)
	assert_float((spots[0] as Vector3).x).is_equal_approx(-0.4, 0.05)


# ---------------------------------------------------------------- the bite

func test_a_tick_hits_what_stands_in_the_salt_once_and_nothing_outside() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var b := _salt(w)
	var hero_at := Vector3(0, 0, 0)
	b.patches.add(Vector3(5, 0, 0), 1.4, 4.0, hero_at)
	# a second patch over the first: a creature in both is still hit once a tick
	b.patches.add(Vector3(5.5, 0, 0), 1.4, 4.0, hero_at)
	var inside := _creature(em, Vector3(5.2, 0, 0.3))
	var outside := _creature(em, Vector3(9, 0, 0))
	em._rebuild_grid()
	var h_in: float = em.hp[inside]
	var h_out: float = em.hp[outside]
	b._bite()
	var tick := b.tick_damage() * (1.0 - em.dr[inside])
	assert_float(h_in - em.hp[inside]).is_equal_approx(tick, 0.01)
	assert_float(em.hp[outside]).is_equal(h_out)
	assert_int(b.ticks_dealt).is_equal(1)
	# walking or standing: a creature that walks into it is hit at the next tick
	em.pos[outside] = Vector3(4.6, 0, 0)
	em._rebuild_grid()
	b._bite()
	assert_float(em.hp[outside]).is_less(h_out)
	# a patch fading out for the cap hurts nothing
	b.patches.patches[0]["dying"] = true
	b.patches.patches[1]["dying"] = true
	var h2: float = em.hp[inside]
	b._bite()
	assert_float(em.hp[inside]).is_equal(h2)


func test_the_ticks_follow_the_clock_and_patches_go_when_their_time_is_up() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var b := _salt(w)
	b.patches.add(Vector3(5, 0, 0), 1.4, b.patch_seconds(), Vector3.ZERO)
	var i := _creature(em, Vector3(5, 0, 0))
	em._rebuild_grid()
	b._tick_t = 0.0
	for k in range(int(2.0 / DT)):
		b._tick(DT)
	# 2 s at a tick every 0.5 s: four or five
	assert_int(b.ticks_dealt).is_between(4, 5)
	for k in range(int(2.5 / DT)):
		b._tick(DT)
	assert_int(b.patches.patches.size()).is_equal(0)
	assert_int(i).is_greater_equal(0)


func test_at_most_forty_patches_lie_the_oldest_fading_first() -> void:
	var w := _world()
	var b := _salt(w)
	assert_int(b.patches.cap).is_equal(40)
	for k in range(45):
		b.patches.add(Vector3(float(k) * 0.5, 0, 0), 1.4, 30.0, Vector3(-50, 0, 0))
	assert_int(b.patches.live_count()).is_equal(40)
	for k in range(5):
		assert_bool(b.patches.patches[k]["dying"]).is_true()
		assert_float(float(b.patches.patches[k]["life"])).is_less_equal(SaltPatches.FADE_OUT)
	assert_bool(b.patches.patches[5]["dying"]).is_false()
	b.patches.advance(SaltPatches.FADE_OUT + 0.01)
	assert_int(b.patches.patches.size()).is_equal(40)
	b.patches.draw()


# ---------------------------------------------------------------- the path

func test_sea_salt_lasts_longer_pink_and_a_little_weaker_and_salt_spill_is_wider() -> void:
	var w := _world()
	var plain := _salt(w)
	assert_float(plain.patch_radius()).is_equal_approx(1.4, 0.001)
	assert_float(plain.patch_seconds()).is_equal_approx(4.0, 0.001)
	assert_float(plain.tick_damage()).is_equal_approx(6.0, 0.001)
	var sea := _salt(w, "salt", ["sea_salt"])
	assert_float(sea.patch_seconds()).is_equal_approx(7.0, 0.001)
	assert_float(sea.tick_damage()).is_equal_approx(5.7, 0.001)
	assert_float(sea.patch_radius()).is_equal_approx(1.4, 0.001)
	assert_str(sea.patches.color.to_html(false)).is_equal(Color("#F4A3C4").to_html(false))
	assert_str((sea._contents.material_override as StandardMaterial3D).albedo_color.to_html(false)).is_equal(Color("#F4A3C4").to_html(false))
	var spill := _salt(w, "salt", ["salt_spill"])
	assert_float(spill.patch_radius()).is_equal_approx(1.4 * 1.6, 0.001)
	assert_float(spill.patch_seconds()).is_equal_approx(4.0, 0.001)


func test_thing_about_luck_triples_the_power_up_roll_only_in_the_salt() -> void:
	var w := _world()
	var luck := _salt(w, "salt", ["thing_about_luck"])
	luck.patches.add(Vector3(5, 0, 0), 1.4, 4.0, Vector3.ZERO)
	assert_float(luck.powerup_luck_at(Vector3(5.5, 0, 0))).is_equal(3.0)
	assert_float(luck.powerup_luck_at(Vector3(9, 0, 0))).is_equal(1.0)
	# without the mutation the salt changes no odds
	var plain := _salt(w)
	plain.patches.add(Vector3(5, 0, 0), 1.4, 4.0, Vector3.ZERO)
	assert_float(plain.powerup_luck_at(Vector3(5.5, 0, 0))).is_equal(1.0)
	# the kill path hands the factor on: WaveDirector.drop_pickup_from takes it as its fourth argument
	var wd := WaveDirector.new()
	assert_int(wd.get_method_argument_count("drop_pickup_from")).is_equal(4)
	wd.free()


func test_salt_flats_charges_him_only_when_he_walks_into_a_patch() -> void:
	var w := _world()
	var hero: Node3D = w["hero"]
	var b := _salt(w, "salt", ["salt_flats"])
	assert_bool(bool(b._salt().get("momentum_on_enter", false))).is_true()
	hero.global_position = Vector3.ZERO
	b._salt_flats()
	# a patch laid round his feet: nothing while he stays in it
	b.patches.add(Vector3.ZERO, 1.4, 30.0, hero.global_position)
	for k in range(10):
		hero.global_position = Vector3(float(k) * 0.05, 0, 0)
		b._salt_flats()
	assert_int(hero.maxed).is_equal(0)
	# out, then back in: once
	hero.global_position = Vector3(3, 0, 0)
	b._salt_flats()
	assert_int(hero.maxed).is_equal(0)
	hero.global_position = Vector3(1.2, 0, 0)
	b._salt_flats()
	assert_int(hero.maxed).is_equal(1)
	assert_int(b.flats).is_equal(1)
	# staying in it charges nothing more
	hero.global_position = Vector3(1.0, 0, 0)
	b._salt_flats()
	assert_int(hero.maxed).is_equal(1)
	# a patch laid ahead of him that he walks into counts
	b.patches.add(Vector3(10, 0, 0), 1.4, 30.0, hero.global_position)
	hero.global_position = Vector3(7, 0, 0)
	b._salt_flats()
	hero.global_position = Vector3(8.8, 0, 0)
	b._salt_flats()
	assert_int(hero.maxed).is_equal(2)
	# a hero without a charge (max_momentum says no) is not counted
	hero.can_max = false
	hero.global_position = Vector3(20, 0, 0)
	b._salt_flats()
	hero.global_position = Vector3(10, 0, 0)
	b._salt_flats()
	assert_int(b.flats).is_equal(2)


func test_without_salt_flats_the_salt_charges_nobody() -> void:
	var w := _world()
	var hero: Node3D = w["hero"]
	var b := _salt(w)
	b.patches.add(Vector3(10, 0, 0), 1.4, 30.0, hero.global_position)
	for k in range(60):
		hero.global_position = Vector3(float(k) * 0.2, 0, 0)
		b._tick(DT)
	assert_int(hero.maxed).is_equal(0)


func test_hiwa_kai_amplifies_the_path_and_its_crystals_bite_on_the_way_in_and_slow() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var hk := _salt(w, "hiwa_kai", ["sea_salt", "salt_spill", "thing_about_luck"])
	var s := hk._salt()
	# the path amplified: lasts x2 (Sea Salt's 1.75), x1.8 wider (Salt Spill's 1.6), the luck x4 (Thing About Luck's 3)
	assert_float(float(s["duration_mult"])).is_equal(2.0)
	assert_float(float(s["area_mult"])).is_equal(1.8)
	assert_float(float(s["luck_mult"])).is_equal(4.0)
	assert_float(hk.patch_seconds()).is_equal_approx(hk.stat("duration") * 2.0, 0.001)
	assert_float(hk.patch_radius()).is_equal_approx(1.4 * hk.stat("area") * 1.8, 0.001)
	# black salt, black crystals on each patch it lays
	assert_float(hk.patches.color.v).is_less(0.15)
	hk._fire()
	for q: Dictionary in hk.patches.patches:
		assert_int((q["crystals"] as Array).size()).is_equal(7)
	hk.patches.patches.clear()
	hk.patches.add(Vector3(5, 0, 0), 2.0, 30.0, Vector3.ZERO)
	var i := _creature(em, Vector3(9, 0, 0))
	em._rebuild_grid()
	hk._bite()
	assert_int(hk.crunches).is_equal(0)
	# it walks in: a crunch (x2 a tick) and the tick at the first bite, the slow on
	em.pos[i] = Vector3(5.5, 0, 0)
	em._rebuild_grid()
	var h0: float = em.hp[i]
	hk._bite()
	var tick := hk.tick_damage() * (1.0 - em.dr[i])
	assert_int(hk.crunches).is_equal(1)
	assert_float(h0 - em.hp[i]).is_equal_approx(tick * 3.0, 0.01)
	assert_float(em.slow_f[i]).is_greater_equal(0.3)
	assert_float(em.slow_t[i]).is_greater(0.0)
	# standing in it: only the tick
	var h1: float = em.hp[i]
	hk._bite()
	assert_int(hk.crunches).is_equal(1)
	assert_float(h1 - em.hp[i]).is_equal_approx(tick, 0.01)
	# out and back in: a crunch again
	em.pos[i] = Vector3(12, 0, 0)
	em._rebuild_grid()
	hk._bite()
	em.pos[i] = Vector3(5, 0, 0)
	em._rebuild_grid()
	hk._bite()
	assert_int(hk.crunches).is_equal(2)
	# the plain salt has neither
	var plain := _salt(w)
	plain.patches.add(Vector3(5, 0, 0), 2.0, 30.0, Vector3.ZERO)
	var h2: float = em.hp[i]
	plain._bite()
	assert_int(plain.crunches).is_equal(0)
	assert_float(h2 - em.hp[i]).is_equal_approx(plain.tick_damage() * (1.0 - em.dr[i]), 0.01)


# ---------------------------------------------------------------- words and rows

func test_the_words_say_what_the_salt_does() -> void:
	var w := _world()
	var b := _salt(w)
	var text := b.inst.description()
	assert_str(text).is_equal("Pours a 1.4 m patch of salt in your wake every 1.6 s. It lasts 4 s; enemies in it take 6 damage every 0.5 s.")
	var lvl5 := _inst("salt", [], 5)
	assert_str(lvl5.description()).contains("Pours 3 patches of salt (1.8 m)")
	assert_str(TextGen.amount_noun(Registry.weapon("salt"))).is_equal("patches")
	var hk := _inst("hiwa_kai", ["sea_salt", "salt_spill", "thing_about_luck"])
	var ht := hk.description()
	assert_str(ht).contains("crystals")
	assert_str(ht).contains("30% slower")
	assert_str(ht).contains("power-ups ×4")
	assert_str(_inst("salt", ["salt_flats"]).description()).contains("speed-up at full")
	for id: String in ["sea_salt", "salt_spill", "thing_about_luck", "salt_flats"]:
		var m: MutationDef = Registry.mutation(id)
		assert_str(m.text).is_not_empty()
		assert_int(m.text.length()).is_less(90)
	var rows: Array = b.inst.stat_rows()
	var names: Array = rows.map(func(r: Dictionary) -> String: return str(r["name"]))
	assert_bool(names.has("patches")).is_true()
	assert_bool(names.has("patch radius")).is_true()
	assert_bool(names.has("lasts")).is_true()
	assert_float(b.inst.dps_estimate()).is_greater(0.0)
	# a level's step reads in the Salt's own words
	var ch := TextGen.weapon_changes(Registry.weapon("salt"), 2, 3)
	var cn: Array = ch.map(func(r: Dictionary) -> String: return str(r["name"]))
	assert_bool(cn.has("Patches")).override_failure_message(str(cn)).is_true()
