extends GdUnitTestSuite

## Pass 119, lane LEGEND_B (Garry picked four legendary passive items off docs/legendary_items/index.html, reworked the
## Grindstone and replaced the Dragon's Breath's ready sign):
## - Lightning in a Bottle: a crit arcs to the 3 nearest creatures within 5 m for 25% of the hit (Garry: "reduce the % of
##   damage a bit"; 35% and 5 Evolved, with a 0.3 s stun); arcs never chain or crit, at most 12 in 0.1 s, recorded as
##   the item's own source (EnemyManager.crit_arc);
## - the Undertaker's Shovel: one kill in 25 digs a grave (a count, no dice), at most 4 stand, the grave rises, a ghost
##   climbs out 2 s after the dig, fights 8 s with the first weapon's damage share, fades, the grave sinks
##   (core/systems/Graveyard.gd);
## - Fool's Gold: 1% attack damage per 50 gold in the run's purse, up to 60%, spending lowers it; Evolved per 40 and max
##   HP per 100 (Run._apply_purse);
## - the Pocket Bible: no hit past 12% of max HP (a boss's 35%), a block every 20 s that never takes a boss's hit
##   (Player.take_damage, Run.bible_try_block);
## - the Grindstone: no more random bonuses; a level raises the weakest weapon or evolves a ready one (Run._grindstone),
##   rare (four levels), offered only while it can work;
## - the Dragon's Breath: no ready ring; a splash of liquid at his face before it breathes (FireBreath._mouthful).

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
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
func heal(_a: float, _s: String = "", _c: String = "") -> void:
	pass
"""

const FAKE_PICKUPS := """extends Node
func spawn(_kind: int, _at: Vector3, _v: float) -> int:
	return 0
func spawn_chest(_at: Vector3, _boss: bool = false) -> void:
	pass
func add_attractor(_p: Vector3, _r: float) -> void:
	pass
func mark_coin(_i: int, _s: String) -> void:
	pass
"""

const LEGENDS := ["lightning_in_a_bottle", "undertakers_shovel", "fools_gold", "pocket_bible"]


func before_test() -> void:
	Save.data = Save._default()
	Run.arena = false
	CardPool.rng = null


func after_test() -> void:
	CardPool.rng = null
	Run.arena = false
	Run.end()


func _start(hero: String = "drifter") -> void:
	var c: CharacterDef = Registry.character(hero)
	Run.start(c, Registry.map("red_canyon"))
	Run.add_weapon(Registry.start_weapon_for(c), 1)


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _world() -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = Vector3(60, 0, 60)
	g.player = hero
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	var pk := Node.new()
	pk.set_script(_script(FAKE_PICKUPS))
	g.add_child(pk)
	g.pickups = pk
	var fx := Fx.new()
	g.add_child(fx)
	g.fx = fx
	em._rebuild_grid()
	return {"g": g, "em": em}


## Skeletons standing at `spots` (tough: they never die of a test's hits), the grid rebuilt; their indices.
func _stand(em: EnemyManager, spots: Array) -> Array:
	var out: Array = []
	for at: Vector3 in spots:
		var i := em.spawn("skeleton", at, null, 1.0, 500.0)
		assert_int(i).is_greater_equal(0)
		em.state[i] = EnemyManager.STATE_MOVE
		em.rise_t[i] = 1.0
		out.append(i)
	em._rebuild_grid()
	return out


func _evolve(id: String) -> void:
	while Run.passive_level(id) < Registry.passive(id).max_level:
		assert_bool(Run.add_or_level_passive(id)).is_true()


# ---------------------------------------------------------------- the items

func test_the_four_legendaries_are_there_on_the_ladder_with_their_icons() -> void:
	for id: String in LEGENDS:
		var p: PassiveDef = Registry.passive(id)
		assert_object(p).override_failure_message(id).is_not_null()
		assert_bool(p.is_item()).is_true()
		assert_bool(p.hidden).is_false()
		assert_str(p.rarity).is_equal("legendary")
		assert_int(p.max_level).override_failure_message(id).is_equal(2)
		assert_float(float(p.weight)).is_equal(5.0)
		assert_bool(Registry.is_unlocked("passive", id)).override_failure_message(id + " is locked").is_true()
		assert_str(p.flavour).is_not_empty()
		assert_object(p.icon).override_failure_message(id + " has no icon").is_not_null()
		assert_object(p.evolved_icon).override_failure_message(id + " has no Evolved icon").is_not_null()
		# its own sentence on the card, its levels in words on the pause screen and the Evolved card
		assert_str(TextGen.passive_text(p)).override_failure_message(id).is_not_empty()
		assert_bool(TextGen.passive_description(p, 2).contains("_")).override_failure_message(id).is_false()
		assert_bool(TextGen.next_level_text(p, 1).contains("nothing new")).override_failure_message(id).is_false()


func test_the_cards_say_the_numbers_of_their_json() -> void:
	var t := TextGen.passive_text(Registry.passive("lightning_in_a_bottle"))
	assert_str(t).contains("up to 3 more enemies within 5 m for 25% of the hit")
	assert_str(t).contains("never chain")
	assert_str(TextGen.next_level_text(Registry.passive("lightning_in_a_bottle"), 1)).contains("5 more enemies")
	assert_str(TextGen.next_level_text(Registry.passive("lightning_in_a_bottle"), 1)).contains("35%")
	var g := TextGen.passive_text(Registry.passive("undertakers_shovel"))
	assert_str(g).contains("One kill in 25 leaves a grave")
	assert_str(g).contains("2 s later")
	assert_str(g).contains("8 s")
	assert_str(g).contains("40% damage")
	assert_str(g).contains("At most 4")
	var f := TextGen.passive_text(Registry.passive("fools_gold"))
	assert_str(f).contains("every 50 gold")
	assert_str(f).contains("up to +60%")
	assert_str(f).contains("Spending lowers it")
	var b := TextGen.passive_text(Registry.passive("pocket_bible"))
	assert_str(b).contains("12% of your max HP")
	assert_str(b).contains("35% from a boss")
	assert_str(b).contains("every 20 s")
	assert_str(b).contains("never a boss's")


# ---------------------------------------------------------------- Lightning in a Bottle

func test_a_crit_arcs_to_the_three_nearest_within_5_m_for_a_quarter_and_never_chains() -> void:
	_start()
	Run.add_or_level_passive("lightning_in_a_bottle")
	# every weapon hit a crit: an arc that could crit or arc again would show it
	Run.player_sheet.add_effects([Effect.make("crit_chance", "add", 1.0, "player")], "test crits")
	var w := _world()
	var em: EnemyManager = w["em"]
	em.refresh_player_stats()
	var c := Vector3(60, 0, 50)
	var all := _stand(em, [c, c + Vector3(1, 0, 0), c + Vector3(0, 0, 2), c + Vector3(-3, 0, 0), c + Vector3(0, 0, -4),
		c + Vector3(6, 0, 0)])
	var hp0: Array = []
	for i: int in all:
		hp0.append(em.hp[i])
	em.damage(all[0], 20.0, "revolver")
	assert_bool(em.last_crit).is_true()
	var dealt: float = float(hp0[0]) - em.hp[all[0]]
	assert_float(dealt).is_greater(20.0)
	# the three nearest each take a quarter of the crit as dealt (no crit of their own), the fourth and the one 6 m out none
	for k in [1, 2, 3]:
		var lost: float = float(hp0[k]) - em.hp[all[k]]
		assert_float(lost).override_failure_message("arc %d" % k).is_equal_approx(dealt * 0.25 * (1.0 - em.dr[all[k]]), 0.01)
	assert_float(em.hp[all[4]]).is_equal_approx(float(hp0[4]), 0.0001)
	assert_float(em.hp[all[5]]).is_equal_approx(float(hp0[5]), 0.0001)
	assert_int(em.arcs_thrown).is_equal(3)
	assert_int(em.arc_crits).is_equal(1)
	# recorded as the item's own source
	assert_float(float(Run.damage_by_weapon.get("lightning_in_a_bottle", 0.0))).is_greater(0.0)
	# the last hit's crit flag is the crit's, not its arcs'
	assert_bool(em.last_crit).is_true()


func test_no_crit_no_arc_and_without_the_item_none() -> void:
	_start()
	var w := _world()
	var em: EnemyManager = w["em"]
	var c := Vector3(60, 0, 50)
	var all := _stand(em, [c, c + Vector3(1, 0, 0)])
	em.damage(all[0], 20.0, "revolver", Vector3.ZERO, 0.0, false, false, EnemyManager.HIT_CRIT)
	assert_int(em.arcs_thrown).is_equal(0)
	Run.add_or_level_passive("lightning_in_a_bottle")
	em.refresh_player_stats()
	# a plain hit (crit chance 0 under the test runner): no arc
	Run.player_sheet.add_effects([Effect.make("crit_chance", "set", 0.0, "player")], "no crits")
	em.refresh_player_stats()
	em.damage(all[0], 20.0, "revolver")
	assert_int(em.arcs_thrown).is_equal(0)
	# a burn's tick never crits, so never arcs
	em.damage(all[0], 20.0, "revolver", Vector3.ZERO, 0.0, false, true, EnemyManager.HIT_CRIT)
	assert_int(em.arcs_thrown).is_equal(0)
	em.damage(all[0], 20.0, "revolver", Vector3.ZERO, 0.0, false, false, EnemyManager.HIT_CRIT)
	assert_int(em.arcs_thrown).is_equal(1)


func test_evolved_arcs_reach_five_for_35_percent_and_stun() -> void:
	_start()
	_evolve("lightning_in_a_bottle")
	var w := _world()
	var em: EnemyManager = w["em"]
	em.refresh_player_stats()
	var c := Vector3(60, 0, 50)
	var spots: Array = [c]
	for k in range(6):
		spots.append(c + Vector3(cos(float(k)), 0, sin(float(k))) * (1.0 + 0.5 * float(k)))
	var all := _stand(em, spots)
	var hp1: float = em.hp[all[1]]
	var hp0: float = em.hp[all[0]]
	em.damage(all[0], 20.0, "revolver", Vector3.ZERO, 0.0, false, false, EnemyManager.HIT_CRIT)
	var dealt: float = hp0 - em.hp[all[0]]
	assert_int(em.arcs_thrown).is_equal(5)
	assert_float(hp1 - em.hp[all[1]]).is_equal_approx(dealt * 0.35 * (1.0 - em.dr[all[1]]), 0.01)
	for k in range(1, 6):
		assert_float(em.stun_t[all[k]]).override_failure_message("arc %d stun" % k).is_greater(0.0)
	# the sixth (the farthest) is neither hit nor stunned
	assert_float(em.stun_t[all[6]]).is_equal(0.0)


func test_arcs_are_capped_at_12_in_a_tenth_of_a_second() -> void:
	_start()
	Run.add_or_level_passive("lightning_in_a_bottle")
	var w := _world()
	var em: EnemyManager = w["em"]
	em.refresh_player_stats()
	var c := Vector3(60, 0, 50)
	var all := _stand(em, [c, c + Vector3(1, 0, 0), c + Vector3(0, 0, 1), c + Vector3(-1, 0, 0)])
	for _k in range(10):
		em.damage(all[0], 5.0, "revolver", Vector3.ZERO, 0.0, false, false, EnemyManager.HIT_CRIT)
	assert_int(em.arcs_thrown).is_equal(12)
	# the next tenth of a second on the buffs' clock lets more go
	Run.elapsed += 0.11
	em.damage(all[0], 5.0, "revolver", Vector3.ZERO, 0.0, false, false, EnemyManager.HIT_CRIT)
	assert_int(em.arcs_thrown).is_equal(15)


# ---------------------------------------------------------------- the Undertaker's Shovel

func test_one_kill_in_25_digs_a_grave_and_at_most_4_stand() -> void:
	_start()
	Run.add_or_level_passive("undertakers_shovel")
	assert_bool(Graveyard.active()).is_true()
	var gy: Graveyard = auto_free(Graveyard.new())
	add_child(gy)
	gy.setup(null)
	for _k in range(24):
		gy.note_kill(Vector3.ZERO)
	assert_int(gy.dug).is_equal(0)
	gy.note_kill(Vector3(3, 0, 4))
	assert_int(gy.dug).is_equal(1)
	assert_vector((gy.graves[0] as Dictionary)["pos"]).is_equal(Vector3(3, 0, 4))
	for _k in range(25 * 5):
		gy.note_kill(Vector3.ZERO)
	# four stand; the two due past the cap were not dug
	assert_int(gy.graves.size()).is_equal(4)
	assert_int(gy.dug).is_equal(4)
	assert_int(gy.skipped).is_equal(2)
	# Evolved: one in 15, six at once
	_evolve("undertakers_shovel")
	assert_int(gy.cap()).is_equal(6)
	gy.counted = 0
	for _k in range(15 * 2):
		gy.note_kill(Vector3.ZERO)
	assert_int(gy.graves.size()).is_equal(6)


func test_a_grave_rises_a_ghost_climbs_out_fights_then_both_go() -> void:
	_start()
	Run.add_or_level_passive("undertakers_shovel")
	var gy: Graveyard = auto_free(Graveyard.new())
	add_child(gy)
	gy.setup(null)
	assert_bool(gy.dig(Vector3(1, 0, 1))).is_true()
	var g: Dictionary = gy.graves[0]
	assert_int(int(g["phase"])).is_equal(Graveyard.STONE_UP)
	var t := 0.0
	var dt := 1.0 / 60.0
	var seen := {}
	while t < 20.0 and not gy.graves.is_empty():
		gy.tick(dt)
		t += dt
		if not gy.graves.is_empty():
			var ph := int((gy.graves[0] as Dictionary)["phase"])
			if not seen.has(ph):
				seen[ph] = t
	assert_bool(gy.graves.is_empty()).is_true()
	# every phase played, in order: the ghost out 2 s after the dig, fighting 8 s
	for ph in [Graveyard.WAIT, Graveyard.CLIMB, Graveyard.FIGHT, Graveyard.VANISH, Graveyard.STONE_DOWN]:
		assert_bool(seen.has(ph)).override_failure_message("phase %d" % ph).is_true()
	assert_float(float(seen[Graveyard.CLIMB])).is_equal_approx(2.0, 0.05)
	assert_float(float(seen[Graveyard.VANISH]) - float(seen[Graveyard.FIGHT])).is_equal_approx(8.0, 0.05)
	assert_int(gy.raised).is_equal(1)


func test_the_ghost_copies_the_first_weapons_damage_share_and_pace() -> void:
	_start()
	Run.add_or_level_passive("undertakers_shovel")
	var gy: Graveyard = auto_free(Graveyard.new())
	add_child(gy)
	gy.setup(null)
	var w := Run.weapons[0] as WeaponInstance
	assert_float(gy.round_damage(w)).is_equal_approx(w.stat("damage") * 0.4, 0.0001)
	var per := maxf(w.stat("cooldown"), 0.05) / float(maxi(w.stat_int("amount"), 1))
	assert_float(gy.fire_every(w)).is_equal_approx(clampf(per, 0.25, 1.5), 0.0001)
	# the rounds are the item's own source, never the copied weapon's
	assert_str(gy._shooter_for().def.id).is_equal("undertakers_shovel")
	assert_str(gy.source_id()).is_equal("undertakers_shovel")


# ---------------------------------------------------------------- Fool's Gold

func _might() -> float:
	return Run.player_sheet.get_stat("might", 1.0)


func _purse(n: int) -> void:
	Run.run_gold = n
	Run.gold_changed.emit(n)


func test_the_purse_is_attack_damage_capped_and_spending_lowers_it() -> void:
	_start()
	var m0 := _might()
	_purse(500)
	assert_float(_might()).is_equal_approx(m0, 0.0001)
	Run.add_or_level_passive("fools_gold")
	# 500 gold: +10%
	assert_float(_might()).is_equal_approx(m0 * 1.10, 0.0001)
	var w := Run.weapons[0] as WeaponInstance
	var d1 := w.stat("damage")
	_purse(649)
	assert_float(_might()).is_equal_approx(m0 * 1.12, 0.0001)
	assert_float(w.stat("damage")).is_greater(d1)
	# spending lowers it
	assert_bool(Run.spend_gold(400, "shop")).is_true()
	assert_float(_might()).is_equal_approx(m0 * 1.04, 0.0001)
	# capped at +60%
	_purse(100000)
	assert_float(_might()).is_equal_approx(m0 * 1.60, 0.0001)
	# its own source on the pause Stats tab, by the item
	var rows: Array = StatSources.rows(Run.player_sheet, "might")[StatSources.RUN]
	var mine := rows.filter(func(r: Dictionary) -> bool: return str(r["sid"]) == "passive:fools_gold" and str(r["name"]).contains("Fool"))
	assert_int(mine.size()).is_greater_equal(1)
	# a rebuild keeps it (the purse is the run's)
	Run.rebuild_sheets()
	assert_float(_might()).is_equal_approx(m0 * 1.60, 0.0001)


func test_evolved_fools_gold_also_gives_max_hp() -> void:
	_start()
	var hp0 := Run.player_sheet.get_stat("max_hp", 100.0)
	var m0 := _might()
	_evolve("fools_gold")
	_purse(1000)
	# per 40 gold: +25%; per 100 gold: +10% max HP
	assert_float(_might()).is_equal_approx(m0 * 1.25, 0.0001)
	assert_float(Run.player_sheet.get_stat("max_hp", 100.0)).is_equal_approx(hp0 * 1.10, 0.01)
	_purse(10000)
	assert_float(Run.player_sheet.get_stat("max_hp", 100.0)).is_equal_approx(hp0 * 1.30, 0.01)
	assert_int(Run.purse_percent(1000, 40.0, 60.0)).is_equal(25)
	assert_int(Run.purse_percent(39, 40.0, 60.0)).is_equal(0)


# ---------------------------------------------------------------- the Pocket Bible

func _hero() -> Player:
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	add_child(p)
	p.setup(Run.character)
	p.refresh_stats()
	p.hp = p.max_hp
	return p


func _hit(p: Player, amount: float, boss: bool = false) -> void:
	p.invuln = 0.0
	var info := {"by": "test", "kind": "boss" if boss else "melee", "role": "boss" if boss else ""}
	p.take_damage(amount, p.global_position + Vector3(1, 0, 0), info)


func test_the_bible_caps_a_hit_blocks_one_every_20_s_and_never_a_bosss() -> void:
	_start("astro")
	Run.add_or_level_passive("pocket_bible")
	var p := _hero()
	# ready from the start: the first hit is stopped outright
	assert_float(Run.bible_left()).is_equal(0.0)
	_hit(p, 500.0)
	assert_float(p.hp).is_equal_approx(p.max_hp, 0.001)
	assert_int(Run.bible_blocks).is_equal(1)
	assert_str(p.last_outcome).is_equal("shield")
	assert_bool(p.damage_log_text().contains("Pocket Bible")).is_true()
	assert_float(Run.bible_left()).is_equal_approx(20.0, 0.01)
	# spent: a huge hit takes 12% of max HP, no more
	_hit(p, 500.0)
	assert_float(p.max_hp - p.hp).is_equal_approx(p.max_hp * 0.12, 0.01)
	# a small one is untouched
	p.hp = p.max_hp
	_hit(p, 3.0)
	assert_float(p.max_hp - p.hp).is_equal_approx(3.0, 0.01)
	# ready again after 20 s of the buffs' clock: a boss's hit passes it by, capped at 35%, and the block waits
	Run.elapsed += 20.01
	p.hp = p.max_hp
	_hit(p, 500.0, true)
	assert_float(p.max_hp - p.hp).is_equal_approx(p.max_hp * 0.35, 0.01)
	assert_int(Run.bible_blocks).is_equal(1)
	assert_float(Run.bible_left()).is_equal(0.0)
	p.hp = p.max_hp
	_hit(p, 500.0)
	assert_float(p.hp).is_equal_approx(p.max_hp, 0.001)
	assert_int(Run.bible_blocks).is_equal(2)


func test_the_evolved_bible_caps_at_9_and_30_and_blocks_every_15_s() -> void:
	_start("astro")
	_evolve("pocket_bible")
	assert_float(Run.hit_cap_share(false)).is_equal_approx(0.09, 0.0001)
	assert_float(Run.hit_cap_share(true)).is_equal_approx(0.30, 0.0001)
	assert_float(Run.bible_every()).is_equal_approx(15.0, 0.0001)
	# without the item: no cap, no block, no plate
	_start("astro")
	assert_float(Run.hit_cap_share(false)).is_equal(0.0)
	assert_float(Run.bible_left()).is_equal(-1.0)
	assert_bool(Run.bible_try_block(false)).is_false()
	assert_str(HUD.bible_plate_key()).is_equal("")
	Run.add_or_level_passive("pocket_bible")
	assert_str(HUD.bible_plate_key()).is_equal("passive:pocket_bible")
	assert_object(HUD.plate_def(HUD.bible_plate_key())).is_same(Registry.passive("pocket_bible"))


# ---------------------------------------------------------------- the Grindstone

func test_the_grindstone_is_rare_with_four_levels_and_no_bonus_table() -> void:
	var g: PassiveDef = Registry.passive("grindstone")
	assert_str(g.rarity).is_equal("rare")
	assert_int(g.max_level).is_equal(4)
	assert_bool(g.params.get("grind") is Dictionary).is_true()
	var t := TextGen.passive_text(g)
	assert_str(t).contains("weakest weapon")
	assert_str(t).contains("evolves")
	assert_int(t.length()).is_less_equal(190)
	assert_str(WItem.effect({"def": g, "level_from": 1, "level_to": 2})).contains("+1 level for your weakest weapon")
	assert_bool(TextGen.passive_description(g, 3).contains("+3 levels for your weakest weapons")).is_true()


func test_a_grindstone_level_raises_the_lowest_weapon_ties_to_the_least_damage() -> void:
	_start()
	var rev := Run.weapon_instance("revolver")
	Run.level_weapon("revolver")
	Run.level_weapon("revolver")
	var saws := Run.add_weapon(Registry.weapon("orbit_saws"), 1)
	var boom := Run.add_weapon(Registry.weapon("boomstick"), 1)
	Run.damage_by_weapon["orbit_saws"] = 500.0
	Run.damage_by_weapon["boomstick"] = 100.0
	var told: Array = []
	var cb := func(id: String, words: String) -> void: told.append([id, words])
	Run.grindstone_worked.connect(cb)
	# the boomstick: level 1 like the saws, less damage dealt
	Run.add_or_level_passive("grindstone")
	assert_int(boom.level).is_equal(2)
	assert_int(saws.level).is_equal(1)
	assert_int(rev.level).is_equal(3)
	assert_array(told[0]).is_equal(["boomstick", "level 2"])
	# then the saws (the only level 1)
	Run.add_or_level_passive("grindstone")
	assert_int(saws.level).is_equal(2)
	Run.grindstone_worked.disconnect(cb)
	# no random bonus anywhere on the sheets
	for w: WeaponInstance in Run.weapons:
		for en in w.sheet.entries:
			assert_bool(str(en["source"]).begins_with("grind:")).is_false()


func test_with_every_weapon_maxed_it_evolves_a_ready_one_else_it_is_not_offered() -> void:
	_start()
	var rev := Run.weapon_instance("revolver")
	while rev.level < rev.def.max_level:
		Run.level_weapon("revolver")
	# nothing to raise, nothing ready: it does nothing and no offer holds it
	assert_bool(Run.grind_can_work()).is_false()
	assert_bool(Run.grind_idle(Registry.passive("grindstone"))).is_true()
	assert_bool(CardPool.offer_passives().has(Registry.passive("grindstone"))).is_false()
	assert_bool(Run.chest_candidates().any(func(c: Dictionary) -> bool: return str(c["id"]) == "grindstone")).is_false()
	# the whole path on it: ready to evolve, so the Grindstone evolves it (no chest needed)
	for m: MutationDef in Registry.mutations_of("revolver"):
		Run.add_mutation(m.id, true)
	assert_bool(Run.evolution_ready(rev)).is_true()
	assert_bool(Run.grind_can_work()).is_true()
	assert_bool(CardPool.offer_passives().has(Registry.passive("grindstone"))).is_true()
	var into := rev.def.evolves_into
	Run.add_or_level_passive("grindstone")
	assert_str((Run.weapons[0] as WeaponInstance).def.id).is_equal(into)


func test_the_arena_plus_works_the_grindstone_too() -> void:
	_start()
	var rev := Run.weapon_instance("revolver")
	Run.debug_set_item("passive", "grindstone", 2)
	assert_int(rev.level).is_equal(3)


# ---------------------------------------------------------------- the Dragon's Breath

func test_the_ready_ring_is_gone_and_a_mouthful_splash_plays_once_a_cooldown() -> void:
	assert_bool(ResourceLoader.exists("res://core/systems/BreathReady.gd")).is_false()
	assert_bool(ResourceLoader.exists("res://core/shaders/breath_ready.gdshader")).is_false()
	var fx: Fx = auto_free(Fx.new())
	add_child(fx)
	var n0 := fx.blood_count()
	fx.water_splash(Vector3(0, 1.5, 0))
	# a splat and its drops into the blood pool, in the liquid's colour, gone within a second
	assert_int(fx.blood_count() - n0).is_equal(Fx.SPLASH_DROPS + 1)
	assert_bool(fx.blood_colors().has(Color(Fx.SPLASH_WATER.r, Fx.SPLASH_WATER.g, Fx.SPLASH_WATER.b, 1.0))).is_true()
	assert_float(FireBreath.MOUTHFUL_LEAD).is_greater(0.0)
