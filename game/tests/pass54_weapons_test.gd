extends GdUnitTestSuite

## Pass 54, lane W: Solenne's Sun Scepter (pillars of sunlight on what she can see, the close likelier; it holds with
## nothing on the screen), its path (Heat Stroke, Flicker, Gold Dust) and Zenith (every 10th strike hits everything on the
## screen at 80%), the hero Solenne (Magic Hour, Haste at level 2 from her first level-up, her perks), the new player
## stats (buff_duration stretches every timed buff, heal_mult), the mutation offer's weapon drawn at random, and the
## Tumbleweed's darker colours (Thorny Weed's own tint through ProjectileEmitter.tint_kind, the Dust Devil's rim).
## SunScepter and SunBeams are reached by path: a class added since the editor last scanned has no global name in a
## headless run.

const SCEPTER := preload("res://core/behaviors/SunScepter.gd")
const BEAMS := preload("res://core/systems/SunBeams.gd")

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
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func fx_ignite(_a, _b = 1.0, _c = false) -> void:
	pass
func fx_lightning(_points) -> void:
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
func shove(_v: Vector3) -> bool:
	return true
func blast(_v: Vector3, _u: float = 0.0) -> void:
	pass
func apply_knockback(_v: Vector3) -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
func aim_origin(d: Vector3) -> Vector3:
	return global_position + Vector3(0, 0.8, 0) + Vector3(d.x, 0, d.z).normalized() * 0.5
"""

const FAKE_CAMERA := """extends Node
func shake(_a: float) -> void:
	pass
"""

const DT := 1.0 / 60.0


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("solenne"), Registry.map("red_canyon"))


func after_test() -> void:
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
	var cam := Node.new()
	cam.set_script(_script(FAKE_CAMERA))
	g.add_child(cam)
	g.camera = cam
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em, "pm": pm, "fx": fx, "tg": tg}


func _inst(id: String, muts: Array = [], level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m: String in muts:
		var md: MutationDef = Registry.mutation(m)
		assert_object(md).override_failure_message("no mutation " + m).is_not_null()
		inst.mutations.append(md)
	inst.rebuild(Run.player_sheet, [inst])
	return inst


func _scepter(w: Dictionary, id := "sun_scepter", muts: Array = [], level := 1):
	var b = SCEPTER.new()
	(w["g"] as Node).add_child(b)
	b.setup(_inst(id, muts, level), w["g"])
	return b


## A tough creature standing where it was put (a skeleton: never a boss or an Elite).
func _creature(em: EnemyManager, at: Vector3, hp_mult := 50.0, id := "skeleton") -> int:
	var i := em.spawn(id, at, null, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	em._rebuild_grid()
	em.refresh_crowd_stats()
	return i


func _taken(em: EnemyManager, i: int, amount: float) -> float:
	return amount * (1.0 - em.dr[i])


func _near(a: Color, b: Color, eps := 0.003) -> bool:
	return absf(a.r - b.r) < eps and absf(a.g - b.g) < eps and absf(a.b - b.b) < eps


## Runs the behaviour's frame clock past every pending pillar.
func _settle(b) -> void:
	for k in range(40):
		b._tick(DT)


# ---------------------------------------------------------------- content

func test_the_sun_scepter_is_solennes_weapon_with_a_whole_path() -> void:
	var w: WeaponDef = Registry.weapon("sun_scepter")
	assert_object(w).is_not_null()
	assert_str(w.behavior).is_equal("SunScepter")
	assert_str(w.hero).is_equal("solenne")
	assert_int(w.max_level).is_equal(5)
	assert_int(w.levels.size()).is_equal(5)
	assert_int((w.levels[0] as Array).size()).is_equal(0)
	assert_str(w.evolves_into).is_equal("zenith")
	var kinds: Array = []
	for m: MutationDef in Registry.mutations_of("sun_scepter"):
		kinds.append(m.mutation_kind)
	assert_array(kinds).is_equal(["element", "volume", "motion"])
	var z: WeaponDef = Registry.weapon("zenith")
	assert_bool(z.is_evolution).is_true()
	assert_str(z.evolved_from).is_equal("sun_scepter")
	assert_str(z.hero).is_equal("solenne")
	# level 5 strikes three pillars
	var top := _inst("sun_scepter", [], 5)
	assert_int(top.stat_int("amount", 0)).is_equal(3)
	assert_float(top.stat("damage", 0.0)).is_equal_approx(14.0 * 1.25 * 1.25, 0.001)
	# Zenith's sweep rides in its `final` block, over whatever the path brought
	var zi := _inst("zenith", ["heat_stroke", "flicker", "gold_dust"])
	var zp: Dictionary = zi.params["zenith"]
	assert_int(int(zp["every"])).is_equal(10)
	assert_float(float(zp["frac"])).is_equal_approx(0.8, 0.0001)
	assert_str(str((zi.params["sun"] as Dictionary)["tint"])).is_equal("#FFD24F")
	# the sounds are bound
	for sid in ["w_sun_warn", "w_sun_strike", "w_sun_zenith"]:
		assert_bool(Registry.soundmap.has_sound(sid)).override_failure_message("no sound " + sid).is_true()


# ---------------------------------------------------------------- picking

func test_the_picker_holds_with_nothing_on_the_screen() -> void:
	var w := _world()
	var b = _scepter(w)
	# nobody at all: no strike and no cooldown, it asks again in a moment
	assert_bool(b._fire()).is_false()
	assert_int(b.strikes).is_equal(0)
	# a creature off the screen does not count either
	var em: EnemyManager = w["em"]
	var i := _creature(em, Vector3(5, 0, 0))
	em.onscreen[i] = 0
	assert_bool(b._fire()).is_false()
	assert_int(b.strikes).is_equal(0)
	em.onscreen[i] = 1
	assert_bool(b._fire()).is_true()
	assert_int(b.strikes).is_equal(1)


func test_the_close_are_likelier_and_never_twice_a_strike() -> void:
	assert_float(SCEPTER.weight_at(0.5, 2.0)).is_equal_approx(SCEPTER.weight_at(1.5, 2.0), 0.0001)
	assert_float(SCEPTER.weight_at(3.0, 2.0)).is_equal_approx(1.0 / 9.0, 0.0001)
	var w := _world()
	var em: EnemyManager = w["em"]
	var near := _creature(em, Vector3(2, 0, 0))
	var far := _creature(em, Vector3(0, 0, 6))
	var b = _scepter(w)
	seed(5401)
	var near_n := 0
	for k in range(400):
		var p: Array = b.pick_targets(1)
		assert_int(p.size()).is_equal(1)
		if int(p[0]) == near:
			near_n += 1
	# 1/4 against 1/36: nine in ten go to the near one
	assert_int(near_n).is_between(330, 390)
	# a strike of three on two creatures: each once, no third
	var two: Array = b.pick_targets(3)
	assert_int(two.size()).is_equal(2)
	assert_bool(two.has(near) and two.has(far)).is_true()


# ---------------------------------------------------------------- striking

func test_a_pillar_warns_then_hits_everything_in_its_circle() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var tg: Telegraphs = w["tg"]
	var a := _creature(em, Vector3(4, 0, 0))
	var c := _creature(em, Vector3(4.6, 0, 0.2))
	var b = _scepter(w)
	var hp_a := em.hp[a]
	var hp_c := em.hp[c]
	var marks := tg.live_count()
	seed(5402)
	assert_bool(b._fire()).is_true()
	# the warning: a ring held on the sand, a pillar brightening, nobody hurt yet
	assert_int(tg.live_count()).is_greater(marks)
	assert_int(b._beams.live()).is_equal(1)
	for k in range(20):
		b._tick(DT)
	assert_float(em.hp[a]).is_equal(hp_a)
	assert_float(em.hp[c]).is_equal(hp_c)
	# past the warning (0.45 s): both stand within 1.3 m of the struck one, both are hit, once
	_settle(b)
	assert_float(em.hp[a]).is_equal_approx(hp_a - _taken(em, a, 14.0), 0.01)
	assert_float(em.hp[c]).is_equal_approx(hp_c - _taken(em, c, 14.0), 0.01)
	assert_int(b.hits).is_equal(2)
	# its light is gone a moment after
	assert_int(b._beams.live()).is_equal(0)


func test_a_pillar_leads_a_walking_creature() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var a := _creature(em, Vector3(5, 0, 0))
	em.vel[a] = Vector3(2, 0, 0)
	var b = _scepter(w)
	assert_bool(b._fire()).is_true()
	var at: Vector3 = b._strikes[0]["at"]
	# 0.45 s ahead at 2 m/s
	assert_float(at.x).is_equal_approx(5.0 + 0.9, 0.01)


func test_heat_stroke_sets_its_share_alight_and_flicker_strikes_sooner_and_thinner() -> void:
	var hs := _inst("sun_scepter", ["heat_stroke"])
	assert_float(hs.ignite_chance()).is_equal_approx(0.35, 0.0001)
	assert_float(hs.stat("fire_damage", 0.0)).is_greater(0.0)
	assert_str(hs.element()).is_equal("fire")
	var w := _world()
	var em: EnemyManager = w["em"]
	var a := _creature(em, Vector3(3, 0, 0))
	var b = _scepter(w, "sun_scepter", ["heat_stroke"])
	# every one this time (the share is the WeaponInstance's word, EnemyManager.ignite rolls it)
	b.inst.params["ignite_chance"] = 1.0
	assert_bool(b._fire()).is_true()
	_settle(b)
	assert_bool(em.is_burning(a)).is_true()
	# Flicker: 30% sooner, 25% less, the pillars thinner and yellower (re-pinned in pass 61: her Magic Hour no longer
	# touches the cooldown)
	var fl := _inst("sun_scepter", ["flicker"])
	# (pass 109: the base cooldown is the attack-speed ramp's level 1, read from the JSON)
	assert_float(fl.stat("cooldown", 0.0)).is_equal_approx(float(Registry.weapon("sun_scepter").base["cooldown"]) * 0.7, 0.0001)
	assert_float(fl.stat("damage", 0.0)).is_equal_approx(14.0 * 0.75, 0.0001)
	var sun: Dictionary = fl.params["sun"]
	assert_float(float(sun["thin"])).is_equal_approx(0.7, 0.0001)
	assert_str(str(sun["tint"])).is_equal("#FFE86A")
	# fainter than the sceptre's own beam (pass 54, the lead raised both so a beam reads on the sand)
	assert_float(float(sun["beam_alpha"])).is_less(float((Registry.weapon("sun_scepter").params["sun"] as Dictionary)["beam_alpha"]))


func test_zeniths_tenth_strike_hits_every_creature_on_the_screen() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var ids: Array = []
	for k in range(6):
		ids.append(_creature(em, Vector3(-9.0 + 3.6 * k, 0, -4.0 + float(k % 2) * 7.0), 400.0))
	var hidden_one := _creature(em, Vector3(8, 0, 8), 400.0)
	em.onscreen[hidden_one] = 0
	var b = _scepter(w, "zenith")
	seed(5403)
	for k in range(9):
		assert_bool(b._fire()).is_true()
		_settle(b)
	assert_int(b.count).is_equal(9)
	assert_int(b.sweeps).is_equal(0)
	var before := {}
	for i: int in ids + [hidden_one]:
		before[i] = em.hp[i]
	# the tenth: one pillar on each creature on the screen, each hit once at 80%, the count starting over (pass 61: the
	# landing fades over 0.34 s, so the ninth strike's pillars may still be lit after _settle; count the new ones)
	var lit0: int = b._beams.live()
	assert_bool(b._fire()).is_true()
	assert_int(b._beams.live() - lit0).is_equal(ids.size())
	_settle(b)
	assert_int(b.sweeps).is_equal(1)
	assert_int(b.count).is_equal(0)
	var dmg: float = b.inst.stat("damage", 0.0) * 0.8
	for i: int in ids:
		assert_float(em.hp[i]).is_equal_approx(float(before[i]) - _taken(em, i, dmg), 0.01)
	assert_float(em.hp[hidden_one]).is_equal(float(before[hidden_one]))
	# the sun head's ring is lit only on Zenith
	assert_bool(b._charge != null and b._charge.visible).is_true()
	var plain = _scepter(w)
	assert_bool(plain._charge == null or not plain._charge.visible).is_true()


func test_gold_dust_pays_a_coin_on_its_share_of_kills() -> void:
	var gd := _inst("sun_scepter", ["gold_dust"])
	var p: Dictionary = gd.params["gold_dust"]
	assert_float(float(p["chance"])).is_equal_approx(0.3, 0.0001)
	assert_int(SCEPTER.gold_dust_coins(_inst("sun_scepter"))).is_equal(0)
	assert_int(SCEPTER.gold_dust_coins(null)).is_equal(0)
	seed(5404)
	var drops := 0
	for k in range(1000):
		drops += SCEPTER.gold_dust_coins(gd)
	assert_int(drops).is_between(250, 350)
	gd.params["gold_dust"] = {"chance": 1.0, "coins": 2}
	assert_int(SCEPTER.gold_dust_coins(gd)).is_equal(2)


func test_the_pillars_light_rises_lands_and_fades() -> void:
	# visible from the moment it appears (WARN_FLOOR), brightening over the warning
	assert_float(BEAMS.strength_at(0.0, 0.45, 1.0)).is_equal_approx(BEAMS.WARN_FLOOR, 0.0001)
	assert_float(BEAMS.strength_at(0.3, 0.45, 1.0)).is_between(0.5, 0.75)
	assert_float(BEAMS.strength_at(0.45, 0.45, 1.0)).is_equal_approx(1.0 + BEAMS.LAND_POP, 0.0001)
	assert_float(BEAMS.strength_at(0.45 + BEAMS.FADE, 0.45, 1.0)).is_equal_approx(0.0, 0.0001)
	var sb = auto_free(BEAMS.new())
	add_child(sb)
	var id: int = sb.begin(Vector3.ZERO, 1.3, 0.45, Color(1, 0.8, 0.3), 0.35)
	assert_int(id).is_greater(0)
	for k in range(BEAMS.MAX + 4):
		sb.begin(Vector3(k, 0, 0), 1.0, 0.45, Color(1, 0.8, 0.3), 0.35)
	assert_int(sb.live()).is_equal(BEAMS.MAX)
	sb.tick(0.45 + BEAMS.FADE + 0.01)
	assert_int(sb.live()).is_equal(0)


# ---------------------------------------------------------------- words

func test_the_cards_say_what_the_sceptre_does() -> void:
	var base := _inst("sun_scepter")
	var t := base.description()
	assert_str(t).contains("pillar of sunlight")
	assert_str(t).contains("you can see")
	assert_str(t).contains("14 damage in 1.3 m")
	assert_str(t).contains("Solenne only.")
	assert_str(_inst("sun_scepter", [], 3).description()).contains("2 pillars a strike.")
	var z := _inst("zenith", ["heat_stroke", "flicker", "gold_dust"]).description()
	assert_str(z).contains("Every 10th strike hits every enemy on the screen at 80%.")
	assert_str(z).contains("Its kills drop a coin 30% of the time.")
	assert_str(z).contains("Sets 35% of the enemies it hits on fire")
	var rows: Array = base.stat_rows()
	var names: Array = []
	for r: Dictionary in rows:
		names.append(str(r["stat"]))
	for k in ["damage", "cooldown", "amount", "radius", "dps"]:
		assert_bool(names.has(k)).override_failure_message("no row " + k).is_true()
	# a pillar counts for 1.6 creatures (re-pinned in pass 61: her Magic Hour no longer runs the cooldown at 0.87)
	# (pass 109: over level 1's cooldown, 1.1 / 0.85, the attack-speed ramp, BALANCING.md 52.ATKSPD)
	assert_float(base.dps_estimate()).is_equal_approx(14.0 * 1.6 / float(Registry.weapon("sun_scepter").base["cooldown"]), 0.01)
	assert_str(TextGen.stat_name("buff_duration")).is_equal("buff duration")
	assert_str(TextGen.stat_name("heal_mult")).is_equal("healing")
	assert_str(Registry.mutation("heat_stroke").text).contains("35%")


# ---------------------------------------------------------------- the hero

func test_solenne_lands_with_her_trait_and_her_sceptre() -> void:
	var c: CharacterDef = Registry.character("solenne")
	assert_object(c).is_not_null()
	assert_bool(c.hidden).is_false()
	assert_str(c.pronoun).is_equal("she")
	assert_str(c.trait_name).is_equal("Magic Hour")
	assert_str(Registry.start_weapon_for(c).id).is_equal("sun_scepter")
	# re-pinned in pass 61 (Garry: "it's a debuff duration not a buff duration ... Remove the rest of the stat stuff"):
	# 1.5% debuff duration a level and nothing else, so at level 1 her health, cooldowns and buffs are everyone's
	var s := Run.player_sheet
	assert_float(s.get_stat("max_hp", 0.0)).is_equal_approx(100.0, 0.001)
	assert_float(s.get_stat("cooldown", 0.0)).is_equal_approx(1.0, 0.0001)
	assert_float(s.get_stat("buff_duration", 0.0)).is_equal_approx(1.0, 0.0001)
	assert_float(s.get_stat("debuff_duration", 0.0)).is_equal_approx(1.015, 0.0001)
	var sc := Run.add_weapon(Registry.weapon("sun_scepter"), 1)
	# (pass 109: the sceptre's own level-1 cooldown, 1.1 / 0.85, the attack-speed ramp; her trait leaves it alone)
	assert_float(sc.stat("cooldown", 0.0)).is_equal_approx(float(Registry.weapon("sun_scepter").base["cooldown"]), 0.0001)
	# re-pinned in pass 62 (Garry: "Change the Solenne favorite item to be a Molotov instead of Haste"): Haste is
	# nothing special to her now (level 1, behind its quest like everyone's), and her favourite is the Molotov
	var haste: PassiveDef = Registry.passive("haste")
	assert_int(Run.first_passive_level(haste)).is_equal(1)
	assert_bool(Save.quest_done("unlock_haste")).is_false()
	assert_bool(CardPool.offer_passives().has(haste)).is_false()
	assert_str(c.favourite_weapon).is_equal("molotov")
	assert_bool(CardPool.offer_weapons().has(Registry.weapon("molotov"))).is_true()


## re-pinned in pass 62: her favourite is the Molotov (it was Haste), found at level 2
func test_the_molotov_comes_to_her_as_her_favourite_at_level_two() -> void:
	seed(5405)
	var found := {}
	for k in range(300):
		for card: Dictionary in CardPool.level_up_offer(3):
			if str(card["id"]) == "molotov":
				found = card
		if not found.is_empty():
			break
	assert_bool(found.is_empty()).override_failure_message("the Molotov never came").is_false()
	assert_bool(bool(found.get("favourite", false))).is_true()
	CardPool.apply(found)
	assert_int(Run.weapon_instance("molotov").level).is_equal(2)


func test_her_perks_two_on_offer_two_kept_back() -> void:
	var ids: Array = []
	for p: PerkDef in Registry.perks_of("solenne"):
		ids.append(p.id)
	assert_array(ids).is_equal(["afterglow", "sunburn"])
	assert_bool(Registry.perk("lingering_light").hidden).is_true()
	assert_bool(Registry.perk("long_day").hidden).is_true()
	assert_str(Registry.perk("sunburn").special).is_equal("sunburn")
	assert_float(Run.perk_param("sunburn", "bonus", 0.0)).is_equal(0.0)
	# Afterglow: every heal 40% bigger (the stat Player.heal reads)
	assert_float(Run.player_sheet.get_stat("heal_mult", 0.0)).is_equal_approx(1.0, 0.0001)
	assert_bool(Run.add_perk("afterglow")).is_true()
	assert_float(Run.player_sheet.get_stat("heal_mult", 0.0)).is_equal_approx(1.4, 0.0001)
	assert_bool(Run.add_perk("sunburn")).is_true()
	assert_float(Run.perk_param("sunburn", "bonus", 0.0)).is_equal_approx(0.2, 0.0001)


# ---------------------------------------------------------------- the new stats

func test_buff_duration_stretches_every_timed_buff() -> void:
	assert_float(float(StatSheet.PLAYER_DEFAULTS["buff_duration"])).is_equal(1.0)
	assert_float(float(StatSheet.PLAYER_DEFAULTS["heal_mult"])).is_equal(1.0)
	# re-pinned in pass 61: Solenne's Magic Hour no longer stretches her buffs (only her debuffs), so they last as long
	# as they say
	assert_float(Run.buff_seconds(10.0)).is_equal_approx(10.0, 0.0001)
	var e := Effect.make("might", "mul", 0.5, "player")
	Run.add_timed_effects("test_buff", "Test", [e], 10.0)
	assert_float(Run.boost_left("test_buff")).is_equal_approx(10.0, 0.001)
	# Long Day (hidden) doubles them
	assert_bool(Run.add_perk("long_day")).is_true()
	assert_float(Run.buff_seconds(10.0)).is_equal_approx(20.0, 0.0001)
	# Barrel Rush runs through the same door
	Run.player_sheet.add_effect(Effect.make("barrel_speed", "add", 0.3, "player"), "test")
	Run.player_sheet.add_effect(Effect.make("barrel_seconds", "add", 2.0, "player"), "test")
	assert_bool(Run.barrel_rush()).is_true()
	assert_float(Run.boost_left(Run.BARREL_RUSH)).is_equal_approx(4.0, 0.001)
	# anyone else: as long as it says
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.add_timed_effects("test_buff", "Test", [e], 10.0)
	assert_float(Run.boost_left("test_buff")).is_equal_approx(10.0, 0.001)


# ---------------------------------------------------------------- the mutation offer's weapon

func test_the_path_weapon_is_drawn_at_random_among_the_open() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.add_weapon(Registry.weapon("hornet_nest"), 1)
	Run.add_weapon(Registry.weapon("orbit_saws"), 4)
	var open: Array = Run.path_offer_weapons()
	assert_int(open.size()).is_equal(2)
	assert_bool(open.has(Registry.weapon("hornet_nest")) and open.has(Registry.weapon("orbit_saws"))).is_true()
	seed(5406)
	var n := {"hornet_nest": 0, "orbit_saws": 0}
	for k in range(200):
		var w := Run.next_path_weapon()
		n[w.def.id] += 1
	assert_int(int(n["hornet_nest"])).is_between(70, 130)
	assert_int(int(n["orbit_saws"])).is_between(70, 130)
	# a weapon whose pick is spent for the stage leaves the draw
	CardPool.apply(CardPool.path_offer(Run.weapon_instance("orbit_saws"))[1])
	assert_array(Run.path_offer_weapons()).is_equal([Registry.weapon("hornet_nest")])
	for k in range(20):
		assert_str(Run.next_path_weapon().def.id).is_equal("hornet_nest")
	CardPool.apply(CardPool.path_offer(Run.weapon_instance("hornet_nest"))[1])
	assert_object(Run.next_path_weapon()).is_null()
	assert_array(Run.path_offer_weapons()).is_empty()


# ---------------------------------------------------------------- the tumbleweed's colours

## A property a packed scene sets on the node at `path` (read off the scene's own state, so it holds whether or not the
## model the node instances is imported yet).
func _scene_prop(ps: PackedScene, path: String, prop: String) -> Variant:
	var st := ps.get_state()
	for i in range(st.get_node_count()):
		if str(st.get_node_path(i)) != path:
			continue
		for j in range(st.get_node_property_count(i)):
			if str(st.get_node_property_name(i, j)) == prop:
				return st.get_node_property_value(i, j)
	return null


## The first mesh in a GLB read straight from the file (GLTFDocument: no import needed).
func _glb_mesh(path: String) -> MeshInstance3D:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	assert_int(doc.append_from_file(path, st)).is_equal(OK)
	var root: Node = auto_free(doc.generate_scene(st))
	var found: Array = root.find_children("*", "MeshInstance3D", true, false)
	return found[0] if not found.is_empty() else null


func test_the_weed_is_dark_brown_and_thorny_weed_darker_with_warm_tips() -> void:
	# the Tumbleweed's shot is art/props/tumbleweed_dark.glb (tools/blender_props.py only=tumbleweed_dark): the same
	# tangle in dark brown with thicker wires and a faint glow; the King's weeds and the world's keep tumbleweed.glb
	var path := "res://content/weapons/tumbleweed/tumbleweed_visual.tscn"
	var deps := ResourceLoader.get_dependencies(path)
	assert_bool(str(deps).contains("tumbleweed_dark.glb")).override_failure_message(str(deps)).is_true()
	var dark := _glb_mesh("res://art/props/tumbleweed_dark.glb")
	assert_object(dark).is_not_null()
	assert_str(dark.name).is_equal("tumbleweed")
	# as wide as the tan one, so the drawn radius (pass 53: 0.55-0.7 m) holds
	assert_float(dark.mesh.get_aabb().size.x * 0.5).is_between(0.75, 0.95)
	var gm := dark.mesh.surface_get_material(0) as StandardMaterial3D
	assert_bool(_near(gm.albedo_color, Color8(74, 46, 24))).is_true()
	assert_bool(gm.emission_enabled).is_true()
	var pale := _glb_mesh("res://art/props/tumbleweed.glb")
	assert_float((pale.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color.r).is_greater(0.8)
	# the visual pins the colour and the glow on that mesh by its name
	var m := _scene_prop(Registry.weapon("tumbleweed").visual, "./Projectile/tumbleweed", "material_override") as StandardMaterial3D
	assert_object(m).is_not_null()
	assert_bool(_near(m.albedo_color, Color8(74, 46, 24))).is_true()
	assert_bool(m.emission_enabled).is_true()
	assert_float(m.emission_energy_multiplier).is_equal_approx(0.15, 0.0001)
	# Thorny Weed: its own kind in its own colours, made once
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	_creature(em, Vector3(5, 0, 0))
	var b := ProjectileEmitter.new()
	(w["g"] as Node).add_child(b)
	b.setup(_inst("tumbleweed", ["thorns"]), w["g"])
	# pass 61 (re-pinned): the shot is drawn bristling with thorns (ProjectileManager.spiked_kind) over this tinted kind;
	# the tint itself is still made once, in these colours
	var k := b.tint_kind(b.inst.params["tint"])
	assert_int(k).is_not_equal(b.projectile_kind)
	assert_int(b.tint_kind(b.inst.params["tint"])).is_equal(k)
	assert_int(b._kind()).is_not_equal(k)
	assert_int(b._kind()).is_equal(b._kind())
	var tm := (pm.kinds[k]["mmi"] as MultiMeshInstance3D).material_override as StandardMaterial3D
	assert_bool(_near(tm.albedo_color, Color("#3A2412"))).is_true()
	assert_bool(_near(tm.emission, Color("#8A5A2A"))).is_true()
	assert_float(tm.emission_energy_multiplier).is_equal_approx(0.35, 0.0001)
	assert_float(float(pm.kinds[k]["scale"])).is_equal_approx(float(pm.kinds[b.projectile_kind]["scale"]), 0.0001)
	# a plain weed keeps the visual's kind
	var plain := ProjectileEmitter.new()
	(w["g"] as Node).add_child(plain)
	plain.setup(_inst("tumbleweed"), w["g"])
	assert_int(plain._kind()).is_equal(plain.projectile_kind)
	# the Dust Devil: still jet black, with a faint warm glow and a rim that catches the light
	var dvis: Node = auto_free(Registry.weapon("dust_devil").visual.instantiate())
	var dm := WeaponBehavior.projectile_source(dvis).material_override as StandardMaterial3D
	assert_bool(_near(dm.albedo_color, Color(0.035, 0.03, 0.03))).is_true()
	assert_bool(dm.emission_enabled).is_true()
	assert_bool(dm.rim_enabled).is_true()


# ---------------------------------------------------------------- a real run

func test_a_real_run_with_solenne_flies_the_sceptre_and_pays_gold_dust() -> void:
	Run.end()
	Save.data = Save._default()
	Save.data["last_character"] = "solenne"
	var g: Node = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	# the warm-up under the spawn beam finishes on a timer: let it, so nothing of it outlives the game
	await get_tree().create_timer(0.5).timeout
	assert_str(Run.character.id).is_equal("solenne")
	assert_bool(Run.has_weapon("sun_scepter")).is_true()
	var b = g._behaviors.get("sun_scepter")
	assert_object(b).is_not_null()
	assert_object(b.get_script()).is_same(SCEPTER)
	# the companion is there (the GLB's or the stand-in), its sun facing up at the camera
	assert_object(b._familiar).is_not_null()
	assert_object(b._model).is_not_null()
	# Gold Dust through the kill's payout: a sure coin for the test
	var inst := Run.weapon_instance("sun_scepter")
	inst.params["gold_dust"] = {"chance": 1.0, "coins": 1}
	var coins_before := 0
	for i in range(g.pickups.alive.size()):
		if g.pickups.alive[i] == 1 and g.pickups.kind[i] == PickupManager.KIND_COIN:
			coins_before += 1
	g._kill_effects(Registry.enemy("skeleton"), g.player.global_position + Vector3(3, 0, 0), null, "sun_scepter")
	var coins_after := 0
	for i in range(g.pickups.alive.size()):
		if g.pickups.alive[i] == 1 and g.pickups.kind[i] == PickupManager.KIND_COIN:
			coins_after += 1
	assert_int(coins_after).is_equal(coins_before + 1)
	g.set_paused(false)
	Run.end()
