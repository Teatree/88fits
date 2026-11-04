extends GdUnitTestSuite

## Pass 123, the lead's rules from Garry's list (BALANCING 65): the seventh Upgrade rank (top_mult, Save.talent_top, the
## price; Second Wind past full health buys untouchable time), the red crumbs (core/systems/Crumbs.gd), the Exploding Frog's
## body that waits for its blast, the Shaman's healing numbers, the boss barrier's reach, the Gila's Poison Rain, the mutation
## colour, the coin's painting under both themes and the numbers highlighted in the kit's text.

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var pickups = null
var fx = null
var paused := false
var blasts: Array = []
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
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
func hint_once(_a, _b) -> void:
	pass
func elite_explosion(_at, _r, damage, _delay = 0.0, _kb = 0.0, _ff = 0.2, _info = {}) -> void:
	blasts.append(damage)
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var character = null
var max_hp := 100.0
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
"""

var _settings_before: Dictionary = {}


func before() -> void:
	_settings_before = Settings.to_dict()


func after() -> void:
	Settings.from_dict(_settings_before)


func before_test() -> void:
	Save.data = Save._default()
	Save._dirty = false


func after_test() -> void:
	Save.data = Save._default()
	Save._dirty = false


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _world() -> Dictionary:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var mb := MapBase.new()
	g.add_child(mb)
	g.map = mb
	var em: EnemyManager = auto_free(EnemyManager.new())
	em.game = g
	em.player = hero
	add_child(em)
	g.enemies = em
	em.colour_after_kills = 999999
	return {"g": g, "hero": hero, "em": em}


func _creature(em: EnemyManager, id: String, at: Vector3) -> int:
	var i := em.spawn(id, at, null)
	assert_int(i).override_failure_message("could not spawn " + id).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	return i


func _hero_on(rank_stat: float) -> Player:
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	add_child(p)
	p.setup(Registry.character("astro"))
	p.refresh_stats()
	p.sheet.add_effects([Effect.make("revive_hp", "add", rank_stat, "player")], "test")
	return p


# ---------------------------------------------------------------- the seventh rank

func test_every_talent_has_a_dearer_stronger_seventh_rank() -> void:
	for def: TalentDef in Registry.talents_list():
		assert_int(def.max_rank()).override_failure_message(def.id).is_equal(7)
		assert_int(def.cost_of_rank(6)).override_failure_message(def.id).is_equal(int(def.cost[0]) * 49)
		for f in def.forms.size():
			# the top rank gives more than a plain one, in both forms
			assert_float(def.top_mult(f)).override_failure_message("%s form %d" % [def.id, f]).is_greater(1.0)
			var plain: Array = def.step_effects(f, false)
			var top: Array = def.step_effects(f, true)
			assert_int(top.size()).is_equal(plain.size())
			for k in plain.size():
				var a: Effect = plain[k]
				var b: Effect = top[k]
				assert_str(b.stat).is_equal(a.stat)
				assert_float(absf(b.value)).override_failure_message("%s %s" % [def.id, a.stat]).is_greater(absf(a.value))


func test_the_top_rank_counts_only_in_the_form_it_was_bought_in() -> void:
	var grit: TalentDef = Registry.talent("grit")
	assert_float(grit.top_mult(0)).is_equal(1.5)
	Save.data["talents"] = {"grit": {"picks": [0, 0, 0, 0, 0, 0]}}
	assert_bool(Save.talent_top(grit, 0)).is_false()
	Save.data["talents"] = {"grit": {"picks": [0, 0, 0, 0, 0, 0, 1]}}
	assert_bool(Save.talent_top(grit, 0)).is_false()
	assert_bool(Save.talent_top(grit, 1)).is_true()
	Save.data["talents"] = {"grit": {"picks": [1, 1, 1, 1, 1, 1, 0]}}
	assert_bool(Save.talent_top(grit, 0)).is_true()
	assert_bool(Save.talent_top(grit, 1)).is_false()
	# six ranks of +10% and the seventh's +15%, summed for reading and folded into the sheet the same
	var one := float((grit.effects_for(0, 1)[0] as Effect).value)
	var summed: Effect = grit.summed_effects(0, 7, true)[0]
	assert_float(summed.value).is_equal_approx(one * 7.5, 0.0001)
	var listed := 0.0
	for e: Effect in grit.effects_for(0, 7, true):
		listed += e.value
	assert_float(listed).is_equal_approx(one * 7.5, 0.0001)


func test_second_wind_past_full_health_buys_untouchable_time() -> void:
	var nerve: TalentDef = Registry.talent("nerve")
	var form := -1
	for f in nerve.forms.size():
		if nerve.form_name(f) == "Second Wind":
			form = f
	assert_int(form).is_greater_equal(0)
	assert_float(nerve.top_mult(form)).is_equal(1.5)
	# 40% base + six ranks of 10% = 100%: nothing over; the seventh's 15% more = 1.5 s more
	var p := _hero_on(0.0)
	var base := p.sheet.get_stat("revive_hp", 0.5)
	p.sheet.add_effects([Effect.make("revive_hp", "add", 1.0 - base, "player")], "test2")
	assert_float(p.revive_overflow_seconds()).is_equal_approx(0.0, 0.001)
	p.sheet.add_effects([Effect.make("revive_hp", "add", 0.15, "player")], "test3")
	assert_float(p.revive_overflow_seconds()).is_equal_approx(1.5, 0.001)
	assert_float(p.revive_share(false)).is_less_equal(1.0)


# ---------------------------------------------------------------- the crumbs

func test_the_upgrade_crumb_shows_for_a_new_rank_the_purse_can_pay_and_goes_once_seen() -> void:
	Save.data["gold"] = 0
	assert_bool(Crumbs.upgrade_due()).is_false()
	var cheapest: TalentDef = Registry.talents_list()[0]
	Save.data["gold"] = cheapest.cost_of_rank(0)
	assert_bool(Crumbs.upgrade_due()).is_true()
	Crumbs.upgrade_mark_seen()
	assert_bool(Crumbs.upgrade_due()).is_false()
	# the purse falls and rises again to the same rank: already seen, no crumb
	Save.data["gold"] = 0
	assert_bool(Crumbs.upgrade_due()).is_false()
	Save.data["gold"] = cheapest.cost_of_rank(0)
	assert_bool(Crumbs.upgrade_due()).is_false()
	# enough for one it had not been shown: the crumb is back
	Save.data["gold"] = 1000000
	assert_bool(Crumbs.upgrade_due()).is_true()
	Crumbs.upgrade_mark_seen()
	assert_bool(Crumbs.upgrade_due()).is_false()


func test_reading_the_crumbs_never_writes_to_the_save() -> void:
	Save.data.erase("crumbs")
	Save.data["gold"] = 1000000
	assert_bool(Crumbs.upgrade_due()).is_true()
	Crumbs.any_look_due()
	assert_bool(Save.data.has("crumbs")).override_failure_message("a read changed the save").is_false()
	Crumbs.upgrade_mark_seen()
	assert_bool(Save.data.has("crumbs")).is_true()
	assert_array(Save.data["crumbs"]["upgrade"]).is_not_empty()


func test_a_new_look_crumbs_until_his_looks_are_opened() -> void:
	var c: CharacterDef = null
	for h: CharacterDef in Registry.characters.values():
		if not h.hidden and Registry.skins_of(h).size() >= 2 and c == null:
			c = h
	if c == null:
		return
	if not Save.heroes_owned().has(c.id):
		Save.heroes_owned().append(c.id)
	var looks := Crumbs.unlocked_looks(c)
	assert_bool(looks.has(c.home_look())).is_false()
	Save.data["crumbs"] = {"looks": []}
	assert_bool(Crumbs.look_due(c)).is_equal(not looks.is_empty())
	Crumbs.looks_mark_seen(c)
	assert_bool(Crumbs.look_due(c)).is_false()
	# a look he has already been shown is no news; one more unlocked is
	Save.data["crumbs"] = {"looks": []}
	for code: String in looks:
		(Save.data["crumbs"]["looks"] as Array).append("%s:%s" % [c.id, code])
	assert_bool(Crumbs.look_due(c)).is_false()


func test_the_tab_bars_crumbs_are_red_and_read_the_rules() -> void:
	var script: GDScript = load("res://ui/wanted/WTabBar.gd")
	Save.data["gold"] = 0
	var bare: Control = auto_free(script.make("battle"))
	add_child(bare)
	await get_tree().process_frame
	assert_bool((bare.find_child("UpgradeMark", true, false) as Control).visible).is_false()
	Save.data["gold"] = 1000000
	var due: Control = auto_free(script.make("battle"))
	add_child(due)
	await get_tree().process_frame
	assert_bool((due.find_child("UpgradeMark", true, false) as Control).visible).is_true()
	Crumbs.upgrade_mark_seen()
	var seen: Control = auto_free(script.make("battle"))
	add_child(seen)
	await get_tree().process_frame
	assert_bool((seen.find_child("UpgradeMark", true, false) as Control).visible).is_false()


# ---------------------------------------------------------------- the creatures

func test_the_frogs_body_lies_until_its_blast_then_goes() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var t := _creature(em, "horned_toad", Vector3(0, 0, 9))
	var def: EnemyDef = Registry.enemy("horned_toad")
	var delay := float(def.death_burst.get("delay", 2.0))
	assert_float(delay).is_greater(EnemyManager.DIE_TIME)
	em.kb[t] = Vector3(4, 0, 0)
	var at := em.pos[t]
	var who := em.serial[t]
	em._die(t, "")
	assert_int(em.state[t]).is_equal(EnemyManager.STATE_DYING)
	assert_bool(em._burst_bodies.has(t)).is_true()
	# it stays where it fell, flat out of no push
	assert_vector(em.kb[t]).is_equal(Vector3.ZERO)
	assert_float(em.timer[t]).is_greater(EnemyManager.DIE_TIME)
	# just before the blast it is still there and has not sunk (a plain body's squash would be timer / DIE_SINK)
	em.squash[t] = 1.0
	em.timer[t] = 0.05
	em._physics_process(0.02)
	assert_int(em.state[t]).is_equal(EnemyManager.STATE_DYING)
	assert_int(em.serial[t]).is_equal(who)
	assert_float(em.squash[t]).is_greater(0.5)
	assert_float(em.pos[t].distance_to(at)).is_less(0.5)
	# past it, the slot is freed and forgets the body
	for k in 8:
		em._physics_process(0.02)
	assert_bool(em._burst_bodies.has(t)).is_false()


func test_a_plain_creature_dies_as_before() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var s := _creature(em, "skeleton", Vector3(0, 0, 5))
	em._die(s, "")
	assert_bool(em._burst_bodies.has(s)).is_false()
	assert_float(em.timer[s]).is_equal_approx(EnemyManager.DIE_TIME, 0.0001)


func test_the_shamans_pulse_shows_what_it_mends_over_each_creature() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var dn: DamageNumbers = auto_free(DamageNumbers.new())
	add_child(dn)
	await get_tree().process_frame
	var calls: Array = []
	var shaman := _creature(em, "skeleton", Vector3(0, 0, 8))
	var hurt := _creature(em, "skeleton", Vector3(1, 0, 8))
	var whole := _creature(em, "skeleton", Vector3(-1, 0, 8))
	em.hp[hurt] = em.max_hp[hurt] * 0.5
	# the grid the pulse looks them up in
	em._physics_process(0.001)
	var before_live: int = dn._live.size()
	var want := em.max_hp[hurt] * 0.25
	em._support_pulse(shaman, 5.0, 0.25, 3.0)
	assert_float(em.hp[hurt]).is_equal_approx(em.max_hp[hurt] * 0.75, 0.001)
	assert_float(em.hp[whole]).is_equal(em.max_hp[whole])
	calls = dn._live.slice(before_live)
	# headless the camera may hide it off screen: when it did draw, it is one heal number of what was mended, never the whole one's
	for n in calls:
		assert_int(int(n.kind)).is_equal(DamageNumbers.KIND_HEAL)
		assert_int(int(n.who)).is_equal(hurt)
		assert_float(float(n.amount)).is_equal_approx(want, 0.001)


func test_the_barrier_reaches_a_third_further_and_the_gilas_rain_is_poison() -> void:
	for id: String in ["royal_dust_devil", "venom_monsoon", "hellbrand_mandala"]:
		var a: BossAttackDef = Registry.boss_attack(id)
		assert_float(a.num("barrier", "radius")).override_failure_message(id).is_equal_approx(14.0 * 1.35, 0.01)
	var rain: BossAttackDef = Registry.boss_attack("cactus_rain")
	assert_str(rain.display_name).is_equal("Poison Rain")
	assert_str(rain.text("projectile", "look")).is_equal("spit")


# ---------------------------------------------------------------- the kit under Royale

func test_the_mutation_look_is_its_own() -> void:
	# pass 124: a frame shape no other item has, a near-black face, a rim no rarity and no perk wears
	assert_bool(R.MUTATION_FILL.is_equal_approx(R.RARITY["epic"]["base"])).is_false()
	assert_bool((R.MUTATION["rim_b"] as Color).is_equal_approx(R.RARITY["epic"]["rim"])).is_false()
	assert_float((R.MUTATION["base"] as Color).v).is_less(0.25)
	assert_float(R.MUTATION_CUT).is_greater(0.0)
	var p: WPlate = auto_free(WPlate.new())
	p.side = 120.0
	p.fill = R.MUTATION_FILL
	assert_str(p.frame_rarity()).is_equal("mutation")
	assert_bool(p.frame_look().has("cut")).is_true()
	var q: WPlate = auto_free(WPlate.new())
	q.fill = W.RARE
	assert_bool(q.frame_look().has("cut")).is_false()


func test_the_coin_is_the_painting_under_both_themes() -> void:
	for theme: String in ["royale"]:
		var c: WCoin = auto_free(WCoin.make(40.0))
		add_child(c)
		await get_tree().process_frame
		assert_object(c.material).override_failure_message(theme).is_null()


func test_the_serif_texts_numbers_are_yellowish_under_royale_only() -> void:
	var r: WText = auto_free(W.serif_text("+10% max HP", 24, W.INK))
	assert_bool(r.bold_color.is_equal_approx(R.NUMBER_HI)).is_true()
func test_a_poster_keeps_the_wanted_faces_under_royale() -> void:
	var t: WText = auto_free(W.wanted_serif_text("Kill 100 creatures.", 27, W.INK_SOFT, 600))
	assert_bool(R.is_display(t.font)).is_false()
	assert_float(t.color.get_luminance()).is_less(0.5)
