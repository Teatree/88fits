extends GdUnitTestSuite

## Pass 46, phase 0: the schema the lanes code against. The timeline's new numbers (colour_after_kills, creature_hp_mult,
## contact_cap, passive_cap and passive_cap_at), a hero's favourite passive, the line fields on every passive, a talent's
## per-rank effects and its rank and price limits, a variant's own facing, the new player stats and their names, the
## stubs' signatures, and EnemyManager.bounce(): straight up and down on the spot, no harm, no spin, never a boss or an
## Elite, while the tornado's toss stays what it was.

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var fx = null
var paused := false
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var hits := 0
var last_outcome := "hit"
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	hits += 1
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

const FAKE_FX := """extends Node
var sands := 0
func sand(_at: Vector3, _size: float = 1.0) -> void:
	sands += 1
func burst(_a, _b, _c = 1.0) -> void:
	pass
"""

const DT := 1.0 / 60.0


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game with a fake hero at the origin and a real EnemyManager wired to both.
func _world() -> Dictionary:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var em: EnemyManager = auto_free(EnemyManager.new())
	em.game = g
	em.player = hero
	add_child(em)
	g.enemies = em
	return {"g": g, "hero": hero, "em": em}


## A creature on its feet (past the spawn pop), standing where it was put.
func _creature(em: EnemyManager, at: Vector3) -> int:
	var i := em.spawn("skeleton", at)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	return i


# ---------------------------------------------------------------- the timeline

func test_the_timeline_reads_the_new_numbers() -> void:
	var tl := JsonContent.timeline_from_dict({"colour_after_kills": 150, "creature_hp_mult": 1.25, "contact_cap": 0.08,
		"passive_cap": [3, 4]})
	assert_int(tl.colour_after_kills).is_equal(150)
	assert_float(tl.creature_hp_mult).is_equal_approx(1.25, 0.0001)
	assert_float(tl.contact_cap).is_equal_approx(0.08, 0.0001)
	assert_int(tl.passive_cap_at(0)).is_equal(3)
	assert_int(tl.passive_cap_at(1)).is_equal(4)
	# the last entry holds for later stages and endless, and a stage below zero reads the first
	assert_int(tl.passive_cap_at(7)).is_equal(4)
	assert_int(tl.passive_cap_at(-1)).is_equal(3)
	# each is off at its default
	var d := JsonContent.timeline_from_dict({})
	assert_int(d.colour_after_kills).is_equal(0)
	assert_float(d.creature_hp_mult).is_equal(1.0)
	assert_float(d.contact_cap).is_equal(0.0)
	# pass 47: six all run (the lines' cap, static) when a map names none
	assert_int(d.passive_cap_at(0)).is_equal(5)
	assert_int(d.passive_cap_at(1)).is_equal(5)
	assert_int(d.passive_cap_at(2)).is_equal(5)
	assert_int(d.passive_cap_at(9)).is_equal(5)
	assert_int(d.weapon_cap_at(0)).is_equal(5)
	assert_int(WaveTimeline.new().passive_cap_at(0)).is_equal(5)
	assert_int(WaveTimeline.new().weapon_cap_at(0)).is_equal(5)
	var empty := WaveTimeline.new()
	empty.passive_cap = []
	assert_int(empty.passive_cap_at(0)).is_equal(5)
	# a .tres round trip keeps them (the maps carry their timeline as a sub-resource)
	var path := "user://pass46_timeline.tres"
	assert_int(ResourceSaver.save(tl, path)).is_equal(OK)
	var back: WaveTimeline = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_int(back.colour_after_kills).is_equal(150)
	assert_float(back.creature_hp_mult).is_equal_approx(1.25, 0.0001)
	assert_float(back.contact_cap).is_equal_approx(0.08, 0.0001)
	assert_int(back.passive_cap_at(5)).is_equal(4)


# ---------------------------------------------------------------- the heroes

func test_a_hero_may_favour_a_passive() -> void:
	var dir := "res://content/characters/astro/"
	var c: CharacterDef = JsonContent.build("characters", {"id": "t46_hero", "favourite_passive": "cake",
		"favourite_passive_bonus": {"type": "max"}}, dir)
	assert_str(c.favourite_passive).is_equal("cake")
	assert_str(str(c.favourite_passive_bonus.get("type", ""))).is_equal("max")
	# an effects bonus becomes Effects aimed at the hero
	var c2: CharacterDef = JsonContent.build("characters", {"id": "t46_hero2", "favourite_passive_bonus": {"type": "effects",
		"effects": [{"stat": "max_hp", "op": "mul", "value": 0.1}]}}, dir)
	var eff: Array = c2.favourite_passive_bonus["effects"]
	assert_int(eff.size()).is_equal(1)
	assert_str((eff[0] as Effect).stat).is_equal("max_hp")
	assert_str((eff[0] as Effect).target).is_equal("player")
	# none by default
	var c3: CharacterDef = JsonContent.build("characters", {"id": "t46_hero3"}, dir)
	assert_str(c3.favourite_passive).is_empty()
	assert_bool(c3.favourite_passive_bonus.is_empty()).is_true()
	# Ironwood's data reads through (his .tres is generated): Brawn at level 2 since pass 47
	var iw: CharacterDef = Registry.character("ironwood")
	assert_object(iw).is_not_null()
	assert_str(iw.favourite_passive).is_equal("brawn")
	assert_str(str(iw.favourite_passive_bonus.get("type", ""))).is_equal("level")
	assert_int(int(iw.favourite_passive_bonus.get("value", 0))).is_equal(2)


func test_a_hidden_hero_may_name_what_is_not_made_yet() -> void:
	var before: Array = Registry.problems.duplicate()
	var c := CharacterDef.new()
	c.id = "t46_hero"
	c.start_weapon = "t46_no_such_weapon"
	c.favourite_weapon = "t46_no_such_weapon"
	c.favourite_passive = "t46_no_such_passive"
	c.hidden = true
	Registry.characters[c.id] = c
	Registry.problems.clear()
	Registry._validate()
	var while_hidden: Array = Registry.problems.duplicate()
	c.hidden = false
	Registry.problems.clear()
	Registry._validate()
	var once_played: Array = Registry.problems.duplicate()
	Registry.characters.erase(c.id)
	Registry.problems = before
	assert_array(while_hidden).is_empty()
	assert_int(once_played.size()).is_equal(3)
	# and the content as it is has no problem
	assert_array(Registry.problems).is_empty()


# ---------------------------------------------------------------- the passives

func test_every_passive_carries_the_line_fields() -> void:
	var dir := "res://content/passives/haste/"
	var p: PassiveDef = JsonContent.build("passives", {"id": "t46_p", "trade": "-3% move speed a level", "evolves_into": "t46_p2",
		"text": "Its own words.", "line": true, "levels": [[{"stat": "regen", "op": "add", "value": 0.5}]]}, dir)
	assert_str(p.kind()).is_equal("passive")
	# pass 47: a line says so
	assert_bool(p.is_line()).is_true()
	assert_str(p.trade).is_equal("-3% move speed a level")
	assert_str(p.evolves_into).is_equal("t46_p2")
	assert_str(p.evolves_from).is_empty()
	assert_str(p.text).is_equal("Its own words.")
	assert_bool(p.is_evolved()).is_false()
	assert_int(p.max_level).is_equal(8)
	assert_str((p.effects_at_level(1)[0] as Effect).target).is_equal("player")
	var evo: PassiveDef = JsonContent.build("passives", {"id": "t46_p2", "evolves_from": "t46_p"}, dir)
	assert_bool(evo.is_evolved()).is_true()
	var plain: PassiveDef = JsonContent.build("passives", {"id": "t46_p3"}, dir)
	assert_bool(plain.is_line()).is_false()
	assert_str(plain.trade).is_empty()
	assert_str(plain.text).is_empty()
	assert_bool(plain.is_evolved()).is_false()
	# the former lines (pass 46) are passives now, their fields read off their own JSON
	var traded := 0
	for pd: PassiveDef in Registry.passives.values():
		var d := JsonContent.load_json(pd.source_dir + pd.id + ".json")
		assert_str(pd.trade).override_failure_message(pd.id + " trade").is_equal(str(d.get("trade", "")))
		assert_str(pd.evolves_into).override_failure_message(pd.id + " evolves_into").is_equal(str(d.get("evolves_into", "")))
		assert_str(pd.evolves_from).override_failure_message(pd.id + " evolves_from").is_equal(str(d.get("evolves_from", "")))
		assert_bool(pd.is_evolved()).is_equal(pd.evolves_from != "")
		assert_bool(pd.is_line()).override_failure_message(pd.id + " line").is_equal(bool(d.get("line", false)))
		if pd.trade != "":
			traded += 1
	assert_int(traded).is_greater(0)


# ---------------------------------------------------------------- the talents

func _talent_json() -> Dictionary:
	return {"id": "t46_talent", "ranks": 3, "cost": [100, 200, 300], "forms": [
		{"name": "Steps", "text": "Bigger steps.", "rank_effects": [
			[{"stat": "max_hp", "op": "mul", "value": 0.05}],
			[{"stat": "max_hp", "op": "mul", "value": 0.10}],
			[{"stat": "max_hp", "op": "mul", "value": 0.15}, {"stat": "regen", "op": "add", "value": 0.5}]]},
		{"name": "Flat", "text": "The same step.", "effects": [{"stat": "might", "op": "mul", "value": 0.06}]}]}


func test_a_talent_may_give_each_rank_its_own_effects() -> void:
	var t: TalentDef = JsonContent.build("talents", _talent_json(), "res://content/talents/drive/")
	assert_int(t.max_rank()).is_equal(3)
	# rank 2 is the first two lists
	var r2 := t.effects_for(0, 2)
	assert_int(r2.size()).is_equal(2)
	assert_float((r2[0] as Effect).value).is_equal_approx(0.05, 0.0001)
	assert_float((r2[1] as Effect).value).is_equal_approx(0.10, 0.0001)
	assert_str((r2[0] as Effect).target).is_equal("player")
	assert_int(t.effects_for(0, 3).size()).is_equal(4)
	# past the lists it stops at the last
	assert_int(t.effects_for(0, 9).size()).is_equal(4)
	# summed for reading: one per stat, the ranks added up
	var s3 := t.summed_effects(0, 3)
	assert_int(s3.size()).is_equal(2)
	assert_str((s3[0] as Effect).stat).is_equal("max_hp")
	assert_float((s3[0] as Effect).value).is_equal_approx(0.30, 0.0001)
	assert_str((s3[1] as Effect).stat).is_equal("regen")
	assert_float((s3[1] as Effect).value).is_equal_approx(0.5, 0.0001)
	# the sum never touches the form's own Effects
	assert_float((t.effects_for(0, 1)[0] as Effect).value).is_equal_approx(0.05, 0.0001)
	assert_float((t.summed_effects(0, 1)[0] as Effect).value).is_equal_approx(0.05, 0.0001)
	# without rank lists the form's effect repeats a rank
	assert_int(t.effects_for(1, 3).size()).is_equal(3)
	assert_float((t.summed_effects(1, 3)[0] as Effect).value).is_equal_approx(0.18, 0.0001)
	# nothing at rank 0 or for a form that is not there
	assert_array(t.effects_for(0, 0)).is_empty()
	assert_array(t.effects_for(5, 1)).is_empty()
	assert_array(t.summed_effects(-1, 2)).is_empty()
	# a .tres round trip keeps the lists
	var path := "user://pass46_talent.tres"
	assert_int(ResourceSaver.save(t, path)).is_equal(OK)
	var back: TalentDef = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_int(back.effects_for(0, 3).size()).is_equal(4)
	assert_float((back.summed_effects(0, 3)[0] as Effect).value).is_equal_approx(0.30, 0.0001)
	assert_float((back.summed_effects(1, 2)[0] as Effect).value).is_equal_approx(0.12, 0.0001)


func test_a_rank_has_a_price_only_inside_both_the_ranks_and_the_price_list() -> void:
	var t := TalentDef.new()
	t.ranks = 3
	t.cost = [100, 200, 300]
	assert_int(t.cost_of_rank(0)).is_equal(100)
	assert_int(t.cost_of_rank(2)).is_equal(300)
	assert_int(t.cost_of_rank(3)).is_equal(-1)
	assert_int(t.cost_of_rank(-1)).is_equal(-1)
	# more prices than ranks: full at the ranks
	t.cost = [100, 200, 300, 400]
	assert_int(t.cost_of_rank(3)).is_equal(-1)
	# more ranks than prices: full at the prices
	t.ranks = 5
	assert_int(t.cost_of_rank(3)).is_equal(400)
	assert_int(t.cost_of_rank(4)).is_equal(-1)
	# every talent on the board agrees with itself
	for td: TalentDef in Registry.talents_list():
		assert_int(td.cost.size()).override_failure_message(td.id + " prices").is_equal(td.ranks)
		assert_int(td.cost_of_rank(td.max_rank())).is_equal(-1)
		assert_int(td.cost_of_rank(td.max_rank() - 1)).is_greater(0)
	# buying stops at the shorter of the two
	Save.data = Save._default()
	Save.add_gold(1000)
	var short := TalentDef.new()
	short.id = "t46_short"
	short.ranks = 2
	short.cost = [10, 20, 30]
	assert_bool(Save.buy_talent(short)).is_true()
	assert_bool(Save.buy_talent(short)).is_true()
	assert_bool(Save.buy_talent(short)).is_false()
	assert_int(Save.talent_rank("t46_short")).is_equal(2)
	assert_int(Save.gold()).is_equal(970)
	short.id = "t46_cheap"
	short.ranks = 3
	short.cost = [10]
	assert_bool(Save.buy_talent(short)).is_true()
	assert_bool(Save.buy_talent(short)).is_false()
	assert_int(Save.talent_rank("t46_cheap")).is_equal(1)
	Save.data = Save._default()


# ---------------------------------------------------------------- a variant's facing

func test_a_variant_may_turn_its_own_way() -> void:
	var dir := "res://content/enemies/blue_slime/"
	var d := JsonContent.load_json(dir + "blue_slime.json")
	var codes: Array = []
	for code in (d.get("variants", {}) as Dictionary).keys():
		if (d["variants"][code] as Dictionary).has("sprite"):
			codes.append(str(code))
	codes.sort()
	assert_int(codes.size()).is_greater_equal(3)
	# the test sets the faces itself (the real SL-C turns left since pass 46)
	for code in codes:
		(d["variants"][code] as Dictionary).erase("front_faces")
		(d["variants"][code] as Dictionary).erase("back_faces")
	d["front_faces"] = "right"
	d["back_faces"] = "right"
	d.erase("variant_base")
	d["variant"] = codes[0]
	(d["variants"][codes[1]] as Dictionary)["front_faces"] = "left"
	(d["variants"][codes[1]] as Dictionary)["back_faces"] = "straight"
	var e: EnemyDef = JsonContent.build("enemies", d, dir)
	assert_str(e.variant).is_equal(codes[0])
	assert_str(e.front_faces).is_equal("right")
	var turned := e.variant_def(codes[1])
	assert_str(turned.front_faces).is_equal("left")
	assert_str(turned.back_faces).is_equal("straight")
	# one that says nothing faces like the top-level strip
	assert_str(e.variant_def(codes[2]).front_faces).is_equal("right")
	# the game playing the turned one: the def turns, and another variant does not inherit it
	d["variant"] = codes[1]
	var e2: EnemyDef = JsonContent.build("enemies", d, dir)
	assert_str(e2.front_faces).is_equal("left")
	assert_str(e2.back_faces).is_equal("straight")
	assert_str(e2.variant_def(codes[2]).front_faces).is_equal("right")
	assert_str(e2.variant_def(codes[2]).back_faces).is_equal("right")
	# apply_art takes the facing only from an entry that has it
	var bare: EnemyDef = EnemyDef.new()
	bare.front_faces = "left"
	bare.apply_art({"head": 0.8})
	assert_str(bare.front_faces).is_equal("left")
	bare.apply_art({"front_faces": "straight"})
	assert_str(bare.front_faces).is_equal("straight")
	assert_str(bare.back_faces).is_equal("right")
	# a base strip's own entry may state its facing (variant_base, like the goblin's)
	var gdir := "res://content/enemies/goblin/"
	var gd := JsonContent.load_json(gdir + "goblin.json")
	var base := str(gd.get("variant_base", ""))
	if base != "" and (gd.get("variants", {}) as Dictionary).has(base):
		gd["variant"] = base
		gd.erase("front_faces")
		(gd["variants"][base] as Dictionary)["front_faces"] = "left"
		var ge: EnemyDef = JsonContent.build("enemies", gd, gdir)
		assert_str(ge.variant).is_equal(base)
		assert_str(ge.front_faces).is_equal("left")


# ---------------------------------------------------------------- the stats, their names and the stubs

func test_the_new_player_stats_have_defaults_and_names() -> void:
	assert_float(float(StatSheet.PLAYER_DEFAULTS["hit_invuln"])).is_equal_approx(0.25, 0.0001)  # pass 83: halved
	assert_float(float(StatSheet.PLAYER_DEFAULTS["revive_hp"])).is_equal_approx(0.5, 0.0001)
	assert_float(float(StatSheet.PLAYER_DEFAULTS["desperado"])).is_equal(0.0)
	var sheet := StatSheet.new()
	sheet.set_bases(StatSheet.PLAYER_DEFAULTS)
	assert_float(sheet.get_stat("hit_invuln")).is_equal_approx(0.25, 0.0001)
	assert_str(TextGen.describe_effect(Effect.make("desperado", "add", 0.3, "player"))).is_equal("up to +30% attack damage as health falls")
	assert_str(TextGen.describe_effect(Effect.make("revive_hp", "add", 0.25, "player"))).is_equal("+25% health on revive")
	assert_str(TextGen.describe_effect(Effect.make("hit_invuln", "add", 0.2, "player"))).is_equal("+0.2 s invulnerability after a hit")
	assert_str(TextGen.stat_name("heal_drop")).is_equal("cake drop chance")
	assert_str(TextGen.format_value("revive_hp", 0.5)).is_equal("50%")
	# the prefix is Desperado's alone
	assert_str(TextGen.describe_effect(Effect.make("might", "mul", 0.1, "player"))).is_equal("+10% attack damage")


func test_the_stubs_are_there_to_code_against() -> void:
	assert_object(DamageNumbers.I).is_null()
	var dn: DamageNumbers = auto_free(DamageNumbers.new())
	assert_bool(dn is Control).is_true()
	dn.add(0, Vector3.ZERO, 12.0, true, false, false)
	var cw: ConeWave = auto_free(ConeWave.new())
	assert_bool(cw is WeaponBehavior).is_true()
	assert_bool(cw.has_method("_fire")).is_true()
	assert_bool(Run.has_method("note_hp")).is_true()
	Run.note_hp(40.0, 100.0)


# ---------------------------------------------------------------- the bounce

func test_a_bounce_goes_straight_up_and_lands_on_the_spot_unhurt() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var i := _creature(em, Vector3(2.0, 0, 3.0))
	var start: Vector3 = em.pos[i]
	var hp0: float = em.hp[i]
	var flip0: int = em.flip[i]
	var a0: float = em.lift_a[i]
	assert_bool(em.bounce(i, 1.5, 0.6)).is_true()
	assert_int(em.lift_mode[i]).is_equal(1)
	assert_float(em.lift_t[i]).is_equal_approx(0.6, 0.0001)
	# one at a time: no second bounce while it is up
	assert_bool(em.bounce(i, 1.5, 0.6)).is_false()
	var top := 0.0
	var t := 0.0
	var moved := 0.0
	while em.lift_t[i] > 0.0 and t < 2.0:
		em._physics_process(DT)
		t += DT
		top = maxf(top, em.lift_h[i])
		moved = maxf(moved, Vector2(em.pos[i].x - start.x, em.pos[i].z - start.z).length())
		assert_int(em.flip[i]).is_equal(flip0)
		assert_float(em.lift_a[i]).is_equal(a0)
	# up to its height and down again in its time, never off its spot, never turned
	assert_float(t).is_between(0.55, 0.65)
	assert_float(top).is_between(1.4, 1.5001)
	assert_float(moved).is_less(0.0001)
	assert_float(em.lift_h[i]).is_equal(0.0)
	assert_int(em.lift_mode[i]).is_equal(0)
	# the landing: squashed, a short grace, no shove asked for so none given, and no harm
	assert_float(em.squash[i]).is_equal_approx(0.7, 0.001)
	assert_float(em.lift_cd[i]).is_equal_approx(0.3, 0.001)
	assert_float(em.kb[i].length()).is_equal(0.0)
	assert_float(em.hp[i]).is_equal(hp0)
	assert_int(hero.hits).is_equal(0)


func test_a_bounce_lands_with_its_shove_and_a_puff_of_sand() -> void:
	var w := _world()
	var g: Node = w["g"]
	var em: EnemyManager = w["em"]
	var fx: Node = Node.new()
	fx.set_script(_script(FAKE_FX))
	g.add_child(fx)
	g.fx = fx
	var i := _creature(em, Vector3(4.0, 0, 0))
	var hp0: float = em.hp[i]
	# the shove stays on the ground
	assert_bool(em.bounce(i, 1.0, 0.4, Vector3(3.0, 5.0, 0.0))).is_true()
	var t := 0.0
	while em.lift_t[i] > 0.0 and t < 2.0:
		em._physics_process(DT)
		t += DT
	assert_float(em.kb[i].x).is_equal_approx(3.0, 0.0001)
	assert_float(em.kb[i].y).is_equal(0.0)
	assert_float(em.kb[i].z).is_equal(0.0)
	assert_int(fx.sands).is_equal(1)
	assert_float(em.hp[i]).is_equal(hp0)
	# and it walks off with the shove after
	em._physics_process(DT)
	assert_float(em.pos[i].x).is_greater(4.0)


func test_a_bounce_never_lifts_a_boss_an_elite_or_one_that_cannot_go() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var boss := em.spawn("tumbleweed_king", Vector3(12, 0, 12))
	assert_int(em.boss_index).is_equal(boss)
	assert_bool(em.bounce(boss, 1.0, 0.5)).is_false()
	var elite := em.spawn("dune_scorpion", Vector3(-12, 0, 12))
	assert_int(elite).is_greater_equal(0)
	assert_bool(em.bounce(elite, 1.0, 0.5)).is_false()
	# an ordinary creature wearing an elite modifier is an Elite too
	var mods: Array = Registry.elites_list()
	assert_bool(mods.is_empty()).is_false()
	var modded := em.spawn("skeleton", Vector3(-12, 0, -12), mods[0])
	assert_int(em.elite_idx[modded]).is_greater_equal(0)
	assert_bool(em.bounce(modded, 1.0, 0.5)).is_false()
	# held, buried, dying, no time, no creature
	var a := _creature(em, Vector3(6, 0, -6))
	em.grab(a)
	assert_bool(em.bounce(a, 1.0, 0.5)).is_false()
	em.release(a)
	em.hidden[a] = 1
	assert_bool(em.bounce(a, 1.0, 0.5)).is_false()
	em.hidden[a] = 0
	assert_bool(em.bounce(a, 1.0, 0.0)).is_false()
	em.state[a] = EnemyManager.STATE_DYING
	assert_bool(em.bounce(a, 1.0, 0.5)).is_false()
	em.state[a] = EnemyManager.STATE_MOVE
	assert_bool(em.bounce(-1, 1.0, 0.5)).is_false()
	assert_bool(em.bounce(EnemyManager.MAX, 1.0, 0.5)).is_false()
	for k: int in [boss, elite, modded, a]:
		assert_float(em.lift_t[k]).is_equal(0.0)
		assert_int(em.lift_mode[k]).is_equal(0)
	# a creature in a tornado's toss cannot bounce, and a bounced one is left out of the tornado's swirl
	var b := _creature(em, Vector3(0, 0, -8))
	em._rebuild_grid()
	assert_int(em.lift_radius(em.pos[b], 0.5, 1.0)).is_equal(1)
	assert_int(em.lift_mode[b]).is_equal(0)
	assert_bool(em.bounce(b, 1.0, 0.5)).is_false()
	var c := _creature(em, Vector3(1.0, 0, -8))
	assert_bool(em.bounce(c, 1.0, 0.5)).is_true()
	var at: Vector3 = em.pos[c]
	em.swirl(em.pos[b], 2.0, 0.1)
	assert_float(em.pos[c].distance_to(at)).is_equal(0.0)


func test_the_tornado_toss_is_what_it_was() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _creature(em, Vector3(3.0, 0, 3.0))
	var hp0: float = em.hp[i]
	em._rebuild_grid()
	assert_int(em.lift_radius(em.pos[i], 0.5, 1.0)).is_equal(1)
	var top := 0.0
	var t := 0.0
	while em.lift_t[i] > 0.0 and t < 3.0:
		em._physics_process(DT)
		t += DT
		top = maxf(top, em.lift_h[i])
	# 3.2 m times its size up, flung out at 12, 8% of its health off, four seconds before the next grab
	assert_float(top).is_greater(3.2 * maxf(em.size[i], 0.6) * 0.95)
	assert_float(em.kb[i].length()).is_equal_approx(12.0 * em.hero_knock_mult(), 0.001)  # pass 72: the map's share of the hero's pushes (hero_knockback_mult)
	assert_float(em.lift_cd[i]).is_equal_approx(4.0, 0.001)
	assert_float(em.hp[i]).is_equal_approx(hp0 - em.max_hp[i] * 0.08 * (1.0 - em.dr[i]), 0.001)
