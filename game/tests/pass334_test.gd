extends GdUnitTestSuite

## Pass 33.4: two skeletons (plain and in armour) that walk like zombies on a Mixamo stride, only Astro and the Drifter
## playable, no Elite cactus, the Molotov's black spill, the specials' own clock, and the debug arena's hand on the build.

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var projectiles = null
var paused := false
func toast(_t, _c = null) -> void:
	pass
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func shove(_v: Vector3) -> bool:
	return true
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
"""


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A director on the red canyon's timeline with a stand-in game, a real crowd and a plain map.
func _director() -> WaveDirector:
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
	var d: WaveDirector = auto_free(WaveDirector.new())
	d.game = g
	d.map = Registry.map("red_canyon")
	d.timeline = d.map.timeline
	return d


func _tick(d: WaveDirector, seconds: float, dt: float = 0.25) -> void:
	var t := 0.0
	while t < seconds:
		d._tick_specials(dt)
		t += dt


# ---------------------------------------------------------------- the skeletons

func test_two_skeletons_walk_like_zombies() -> void:
	var s: EnemyDef = Registry.enemy("skeleton")
	var k: EnemyDef = Registry.enemy("skeleton_knight")
	assert_object(s).is_not_null()
	assert_object(k).is_not_null()
	# the second kind wears armour, and it is tougher for it
	assert_float(k.damage_reduction).is_greater_equal(0.2)
	assert_float(k.hp).is_greater(s.hp)
	for id in ["skeleton", "skeleton_knight"]:
		var f := FileAccess.open("res://content/enemies/%s/%s.json" % [id, id], FileAccess.READ)
		var j: Dictionary = JSON.parse_string(f.get_as_text())
		# a Mixamo stride with the arms out in front (sloping down from behind, raised a little from the front), no sword
		assert_str(str(j.get("pose", ""))).is_equal("walk_zombie_low")
		assert_str(str(j.get("pose_front", ""))).is_equal("walk_zombie_high")
		assert_str(str(j.get("art_prompt", ""))).contains("no weapon")
		assert_str(str(j.get("death", ""))).is_equal("collapse")
	assert_str(str(k.flavour + " " + FileAccess.open("res://content/enemies/skeleton_knight/skeleton_knight.json", FileAccess.READ).get_as_text())).contains("breastplate")
	# kept for later (pass 33.5 brought the goblins back), and last pass's pair is gone
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	# pass 45: the skeletons took the goblins' rows (SK-A / KN-A in play) and the goblins are the ones kept for later
	# (pass 54: Garry's placement in the Level Editor opens with the red goblins; the skeletons are on the roster still)
	var on_roster: Array = tl.roster.map(func(r): return str(r.get("enemy", "")))
	assert_bool(on_roster.has("skeleton") and on_roster.has("skeleton_knight")).is_true()
	assert_bool(s.retired or k.retired).is_false()
	assert_bool(Registry.enemy("goblin").retired and Registry.enemy("goblin_runt").retired).is_true()
	assert_object(Registry.enemy("skeleton_warrior")).is_null()
	assert_object(Registry.enemy("skeleton_raider")).is_null()


# ---------------------------------------------------------------- the heroes

func test_only_astro_and_the_drifter_are_played() -> void:
	var ids: Array = Registry.sorted_characters().map(func(c): return c.id)
	# pass 43: Calavera; pass 46: Ironwood; pass 54: Solenne; re-pinned in pass 61: in Garry's order (CharacterDef.order);
	# pass 66: the five are present, not "exactly these" (a hero made in the Level Editor joins them when Garry sets him
	# available); the list is the non-hidden heroes sorted by order (pass66_shape_test holds the distinct-orders rule)
	assert_array(ids).contains(["drifter", "astro", "calavera", "ironwood", "solenne"])
	var want: Array = Registry.characters.values().filter(func(c: CharacterDef) -> bool: return not c.hidden)
	want.sort_custom(func(a: CharacterDef, b: CharacterDef) -> bool: return a.id < b.id if a.order == b.order else a.order < b.order)
	assert_array(ids).is_equal(want.map(func(c: CharacterDef) -> String: return c.id))
	# the others are kept, just hidden
	for id in ["buck", "dad", "mira"]:
		assert_object(Registry.character(id)).is_not_null()
		assert_bool(Registry.character(id).hidden).is_true()
		assert_str(Registry.playable_character(id).id).is_equal("astro")
	assert_str(Registry.playable_character("drifter").id).is_equal("drifter")
	# and the quest that unlocked a hidden hero is not shown or tracked
	assert_bool(Registry.quest_visible(Registry.quests["unlock_dad"])).is_false()
	assert_bool(Registry.quest_visible(Registry.quests["unlock_big_mouth"])).is_true()


# ---------------------------------------------------------------- no Elite cactus

func test_a_cactus_is_never_an_elite() -> void:
	for id in ["spit_cactus", "rocketeer", "harpoon_troglodyte"]:
		assert_bool(Registry.enemy(id).can_be_elite).override_failure_message(id + " may still be an Elite").is_false()
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	for t in [200.0, 500.0, 899.0]:
		var rows: Array = WaveDirector.elite_candidates(tl.roster_at(t))
		assert_bool(rows.is_empty()).is_false()
		for r in rows:
			assert_str(str(r["enemy"])).is_not_equal("spit_cactus")


# ---------------------------------------------------------------- the specials' clock

func test_the_specials_come_one_at_a_time_on_their_own_clock() -> void:
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	# off the roster, onto their own clock
	for r in tl.roster:
		assert_bool(["rocketeer", "harpoon_troglodyte"].has(str(r["enemy"]))).is_false()
	# half way through stage 1: 2:30 until pass 46 stretched the clocks by 430/300, 3:35 since
	assert_float(float(tl.specials.get("from", 0))).is_equal(215.0)
	var d := _director()
	# stage 1 before its half-way point: nothing
	Run.stage = 0
	Run.elapsed = 100.0
	_tick(d, 60.0)
	assert_int(d.specials_alive()).is_equal(0)
	# from 3:35: one comes within 64 to 86 seconds (45 to 60 before the stretch, 20 to 40 before pass 33.7), and only the
	# rocketeer (the harpooner waits for stage 2)
	Run.elapsed = 215.0
	assert_array(d.specials_pool()).contains_exactly(["rocketeer"])
	_tick(d, 63.0)
	assert_int(d.specials_alive()).is_equal(0)
	_tick(d, 24.0)
	assert_int(d.specials_alive()).is_equal(1)
	# never a second while one lives, however long
	_tick(d, 120.0)
	assert_int(d.specials_alive()).is_equal(1)
	# the clock starts when it dies: not before 64 s, by 86 s
	var em: EnemyManager = d.game.enemies
	for i in range(EnemyManager.MAX):
		if em.alive[i] == 1:
			em._die(i, "")
	assert_int(d.specials_alive()).is_equal(0)
	_tick(d, 63.0)
	assert_int(d.specials_alive()).is_equal(0)
	_tick(d, 24.0)
	assert_int(d.specials_alive()).is_equal(1)
	# stage 2 adds the harpooner to the pool
	Run.stage = 1
	assert_array(d.specials_pool()).contains_exactly(["rocketeer", "harpoon_troglodyte"])


# ---------------------------------------------------------------- the arena's hand on the build

func test_the_arena_sets_any_item_at_any_level() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.arena = true
	# past the stage's weapon cap
	for id in ["peashooter", "boomstick", "orbit_saws", "rocket_pod", "sabre"]:
		assert_int(Run.debug_set_item("weapon", id, 3)).is_equal(3)
	assert_int(Run.weapons.size()).is_equal(5)
	assert_int(Run.debug_set_item("weapon", "peashooter", 99)).is_equal(Registry.weapon("peashooter").max_level)
	assert_int(Run.debug_set_item("weapon", "sabre", 0)).is_equal(0)
	assert_bool(Run.has_weapon("sabre")).is_false()
	assert_int(Run.debug_set_item("passive", "magnet", 2)).is_equal(2)
	var shield_max_before := Run.player_sheet.get_stat("shield_max", 0.0)
	# the Energy Shield, a line until pass 46, is a passive like the rest
	assert_int(Run.debug_set_item("passive", "energy_shield", 2)).is_equal(2)
	assert_float(Run.player_sheet.get_stat("shield_max", 0.0)).is_greater(shield_max_before)
	# taking a passive away takes its effect away too
	Run.debug_set_item("passive", "energy_shield", 0)
	assert_float(Run.player_sheet.get_stat("shield_max", 0.0)).is_equal_approx(shield_max_before, 0.001)
	var mut: MutationDef = Registry.mutations_of("peashooter")[0]
	assert_int(Run.debug_set_item("mutation", mut.id, 1)).is_equal(1)
	assert_bool(Run.weapon_instance("peashooter").has_mutation(mut.id)).is_true()
	Run.debug_clear_items()
	assert_int(Run.weapons.size()).is_equal(0)
	assert_int(Run.passives.size()).is_equal(0)
	Run.arena = false


func test_the_arena_panel_lists_everything() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var p := ArenaPanel.new()
	var seen := 0
	for g in p.enemy_groups():
		seen += (g[1] as Array).size()
	# every creature in the game has a tile
	assert_int(seen).is_equal(Registry.enemies.size())
	# every weapon's mutations and evolutions are stacked under it (pass 49), so they are counted from the stacks
	var items := 0
	for s in p.item_sections():
		items += (s[2] as Array).size()
		if str(s[1]) == "weapon":
			for w in s[2]:
				items += p.weapon_stack(w).size()
	assert_int(items).is_equal(Registry.weapons.size() + Registry.passives.size() + Registry.perks.size() + Registry.mutations.size())
	p.free()
