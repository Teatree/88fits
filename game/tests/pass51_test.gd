extends GdUnitTestSuite

## Pass 51 (Garry's list): the arena's ITEMS tab opens what a player reads about each item (INFO, the very calls the cards,
## the Build tab and the chest make, read from the run as it stands) and a weapon's EVO counts only the three path
## mutations its evolution needs (a hero's own one is optional, a hidden hero's hidden); Calavera's crit is +5%; Wide
## Reach springs from 2.8 m; the Jackrabbit Mines are flicked ahead of the walking hero; Both Barrels fires its second
## shot a beat after the first; Dragon's Breath sets 60% of the creatures a shot hits alight (one roll a creature a shot),
## the Blunderbuss every one.

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
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))


func after_test() -> void:
	Run.debug_clear_items()
	Run.end()


## A fake game round a fake hero at the origin, with the real crowd, shots, effects and ground marks.
func _world() -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	var hip := Node3D.new()
	hero.add_child(hip)
	hero.set("hip", hip)
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
	return {"g": g, "hero": hero, "em": em, "pm": pm, "fx": fx}


func _inst(id: String, muts: Array = [], level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m: String in muts:
		inst.mutations.append(Registry.mutation(m))
	inst.rebuild(Run.player_sheet, [inst])
	return inst


func _creature(em: EnemyManager, at: Vector3, id := "skeleton") -> int:
	var i := em.spawn(id, at, null, 1.0, 50.0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	return i


# ---------------------------------------------------------------- INFO: the player's words

func test_info_shows_the_words_a_player_reads_for_every_kind() -> void:
	var pea: WeaponDef = Registry.weapon("peashooter")
	# a weapon not held: the card that offers it
	var t := ArenaPanel.item_texts("weapon", pea)
	assert_str(str(t[0][1])).is_equal(WItem.effect({"def": pea, "level_from": 0, "level_to": 1}))
	assert_str(str(t[0][1])).is_equal(UiKit.card_description({"def": pea, "level_from": 0, "level_to": 1}))
	# held at 3: its description as it fires now, the Build tab's rows, the evolve note, the next level's card
	Run.debug_set_item("weapon", "peashooter", 3)
	var inst := Run.weapon_instance("peashooter")
	t = ArenaPanel.item_texts("weapon", pea)
	assert_str(str(t[0][0])).starts_with("Lv 3 of %d" % pea.max_level)
	assert_str(str(t[0][1])).is_equal(inst.description())
	var by := {}
	for pair in t:
		by[str(pair[0])] = str(pair[1])
	assert_str(str(by.get("Evolution", ""))).is_equal(PauseScreen.evolve_note(inst))
	assert_str(str(by.get("Next level · the level-up card", ""))).is_equal(WItem.card_text({"def": pea, "level_from": 3, "level_to": 4}))
	assert_str(str(by.get("The Build tab", ""))).contains(str(inst.stat_rows()[0]["value"]))
	# at the top there is no next level
	Run.debug_set_item("weapon", "peashooter", pea.max_level)
	for pair in ArenaPanel.item_texts("weapon", pea):
		assert_str(str(pair[0])).not_contains("Next level")
	# a line held: the Build tab's words at its level, then the next level's card
	Run.debug_set_item("passive", "deadeye", 2)
	var dd: PassiveDef = Registry.passive("deadeye")
	t = ArenaPanel.item_texts("passive", dd)
	assert_str(str(t[0][1])).is_equal(PauseScreen.passive_now(dd, 2))
	assert_str(str(t[1][1])).is_equal(WItem.card_text({"def": dd, "level_from": 2, "level_to": 3}))
	# maxed, its evolution's card
	Run.debug_set_item("passive", "deadeye", dd.max_level)
	t = ArenaPanel.item_texts("passive", dd)
	assert_str(str(t.back()[0])).contains("Evolves into")
	# a mutation and a perk: their cards
	var wr: MutationDef = Registry.mutation("wide_reach")
	assert_str(str(ArenaPanel.item_texts("mutation", wr)[0][1])).is_equal(wr.text)
	var perk: PerkDef = Registry.perks.values()[0]
	assert_str(str(ArenaPanel.item_texts("perk", perk)[0][1])).is_equal(perk.text)


func test_info_follows_the_run_as_it_stands() -> void:
	var pea: WeaponDef = Registry.weapon("peashooter")
	Run.debug_set_item("weapon", "peashooter", 2)
	var build := func() -> String:
		for pair in ArenaPanel.item_texts("weapon", pea):
			if str(pair[0]) == "The Build tab":
				return str(pair[1])
		return ""
	var before: String = build.call()
	# more attack damage reaches the weapon's numbers, and INFO's Build tab line says so
	Run.debug_set_item("passive", "brawn", 4)
	var after: String = build.call()
	assert_str(after).is_not_equal(before)
	assert_str(after).contains(str(Run.weapon_instance("peashooter").stat_rows()[0]["value"]))
	# a level more: the description it fires with now, read again
	Run.debug_set_item("weapon", "peashooter", 5)
	assert_str(str(ArenaPanel.item_texts("weapon", pea)[0][1])).is_equal(Run.weapon_instance("peashooter").description())


func test_the_items_tab_opens_info_under_a_row_and_fills_it_again_when_a_level_is_set() -> void:
	var panel: ArenaPanel = auto_free(ArenaPanel.new())
	add_child(panel)
	panel._tab = "items"
	panel._open["info:weapon:peashooter"] = true
	panel._refresh()
	var row: Node = panel._content.find_child("Item_weapon_peashooter", true, false)
	assert_object(row).is_not_null()
	assert_object(row.find_child("Info", true, false)).is_not_null()
	assert_object(row.find_child("Stack", true, false)).is_not_null()
	var box: Node = panel._content.find_child("Info_weapon_peashooter", true, false)
	assert_object(box).is_not_null()
	var shown: Label = box.find_child("InfoText0", true, false)
	assert_str(shown.text).is_equal(str(ArenaPanel.item_texts("weapon", Registry.weapon("peashooter"))[0][1]))
	# the row's + gives it a level, and the open words become the held weapon's
	var plus: Button = null
	for b in row.find_children("*", "Button", true, false):
		if (b as Button).text == "+":
			plus = b
	plus.pressed.emit()
	assert_int(Run.weapon_instance("peashooter").level).is_equal(1)
	shown = box.find_child("InfoText0", true, false)
	assert_str(shown.text).is_equal(Run.weapon_instance("peashooter").description())
	# a passive row has INFO and no EVO
	panel._open["Lines"] = true
	panel._refresh()
	var prow: Node = panel._content.find_child("Item_passive_deadeye", true, false)
	assert_object(prow.find_child("Info", true, false)).is_not_null()
	assert_object(prow.find_child("Stack", true, false)).is_null()
	# the rows taken down on each refresh go at the end of the frame
	await get_tree().process_frame


# ---------------------------------------------------------------- EVO: three mutations, the hero's own optional

func test_evo_counts_the_three_path_mutations_and_a_heros_own_is_optional() -> void:
	var ap: ArenaPanel = auto_free(ArenaPanel.new())
	for id in ["land_mine", "skull_rain", "tommy_gun", "peashooter", "orbit_saws"]:
		var w: WeaponDef = Registry.weapon(id)
		var stack := ap.weapon_stack(w)
		assert_str(ArenaPanel.stack_summary(stack)).override_failure_message(id).is_equal("3 + EVO")
		assert_int(Registry.mutations_of(id).size()).is_equal(3)
	var tags := {}
	for entry in ap.weapon_stack(Registry.weapon("skull_rain")):
		tags[(entry[1] as ContentDef).id] = str(entry[2])
	assert_str(str(tags["danza_macabra"])).is_equal("Calavera · optional")
	tags.clear()
	for entry in ap.weapon_stack(Registry.weapon("land_mine")):
		tags[(entry[1] as ContentDef).id] = str(entry[2])
	# Mira is out of play, and so is her Blasting Cap
	assert_str(str(tags["blasting_cap"])).is_equal("hidden · Mira")
	# and the evolution asks for the three: Skull Rain at the top with its path, no Danza Macabra, is ready
	Run.start(Registry.character("calavera"), Registry.map("red_canyon"))
	Run.debug_set_item("weapon", "skull_rain", Registry.weapon("skull_rain").max_level)
	for m: MutationDef in Registry.mutations_of("skull_rain"):
		Run.debug_set_item("mutation", m.id, 1)
	assert_bool(Run.mutations_held("skull_rain").has("danza_macabra")).is_false()
	assert_bool(Run.evolution_ready(Run.weapon_instance("skull_rain"))).is_true()


# ---------------------------------------------------------------- Calavera, Wide Reach

## Re-pinned in pass 61: Calavera's trait is 1% attack damage a level and no crit chance at all (the crit is the
## Drifter's signature now, pass61_hr_test; the suites leave every crit out, Run.base_crit).
func test_calaveras_crit_is_five_percent() -> void:
	var c: CharacterDef = Registry.character("calavera")
	assert_str(c.trait_text).contains("attack damage")
	assert_str(c.trait_text).not_contains("crit")
	Run.start(c, Registry.map("red_canyon"))
	assert_float(Run.player_sheet.get_stat("crit_chance", 0.0)).is_equal(0.0)
	assert_float(Run.player_sheet.get_stat("might", 1.0)).is_equal_approx(1.01, 0.0001)
	# nobody starts with any under the runner
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	assert_float(Run.player_sheet.get_stat("crit_chance", 0.0)).is_equal(0.0)


func test_wide_reach_springs_from_two_point_eight_metres() -> void:
	var wr: MutationDef = Registry.mutation("wide_reach")
	assert_float(float((wr.params["spring"] as Dictionary)["sense"])).is_equal_approx(2.8, 0.001)
	assert_str(wr.text).contains("2.8 m")
	# the Jackrabbit's own spring is as it was
	assert_float(float((Registry.weapon("jackrabbit_mines").params["jackrabbit"] as Dictionary)["sense"])).is_equal(6.0)


# ---------------------------------------------------------------- the Jackrabbit lays ahead

func test_the_jackrabbit_flicks_its_mines_ahead_of_the_walking_hero() -> void:
	var w := _world()
	var hero: Node3D = w["hero"]
	var ml := MineLayer.new()
	(w["g"] as Node).add_child(ml)
	ml.setup(_inst("jackrabbit_mines"), w["g"])
	# walking east: two metres ahead of him
	hero.set("velocity", Vector3(5, 0, 0))
	var at := ml.lay_point()
	assert_float(at.x).is_equal_approx(2.0, 0.001)
	assert_float(at.z).is_equal_approx(0.0, 0.001)
	seed(5151)
	ml._fire()
	var mines := ml.mines()
	# its two, doubled
	assert_int(mines.size()).is_equal(2 * ml.stat_int("amount"))
	for m: Mine in mines:
		# flicked from his feet, not armed in the air
		assert_int(m.state).is_equal(Mine.ST_TOSS)
	for k in range(int(Mine.TOSS_TIME / DT) + 3):
		for m: Mine in mines:
			m.step(DT)
	# the first lands on the spot ahead, armed and full size; the rest round it
	var first: Mine = mines[0]
	assert_int(first.state).is_equal(Mine.ST_ARMED)
	assert_float(Vector2(first.global_position.x - 2.0, first.global_position.z).length()).is_less(0.05)
	assert_bool(first.scale.is_equal_approx(Vector3.ONE)).is_true()
	for m: Mine in mines:
		assert_int(m.state).is_equal(Mine.ST_ARMED)
		assert_float(Vector2(m.global_position.x - 2.0, m.global_position.z).length()).is_less(2.2)
	# standing, at his feet as ever
	hero.set("velocity", Vector3.ZERO)
	assert_bool(ml.lay_point().is_equal_approx(hero.global_position)).is_true()
	# the plain Land Mine keeps them at his heels even walking
	hero.set("velocity", Vector3(5, 0, 0))
	var plain := MineLayer.new()
	(w["g"] as Node).add_child(plain)
	plain.setup(_inst("land_mine"), w["g"])
	assert_bool(plain.lay_point().is_equal_approx(hero.global_position)).is_true()


# ---------------------------------------------------------------- Both Barrels: two shots

func test_both_barrels_fires_its_second_shot_a_beat_after_the_first() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	_creature(em, Vector3(3, 0, 0))
	em._rebuild_grid()
	var inst := _inst("boomstick", ["both_barrels"], 5)
	var pe := ProjectileEmitter.new()
	(w["g"] as Node).add_child(pe)
	pe.setup(inst, w["g"])
	var per_volley: int = inst.stat_int("amount")
	var live := func() -> int:
		var n := 0
		for j in range(ProjectileManager.MAX):
			if pm.alive[j] == 1 and pm.weapon[j] == inst:
				n += 1
		return n
	pe._fire()
	pe._fire()
	assert_int(live.call()).is_equal(per_volley * 2)
	# the third pull: one volley now, none of the second yet
	pe._fire()
	assert_int(live.call()).is_equal(per_volley * 3)
	assert_int(pe.second_barrels).is_equal(0)
	pe._tick(ProjectileEmitter.DOUBLE_GAP * 0.5)
	assert_int(pe.second_barrels).is_equal(0)
	# a beat later the second barrel goes: another whole volley
	pe._tick(ProjectileEmitter.DOUBLE_GAP * 0.5 + 0.02)
	assert_int(pe.second_barrels).is_equal(1)
	assert_int(live.call()).is_equal(per_volley * 4)
	assert_float(float(inst.params.get("double_gap", 0.0))).is_equal_approx(ProjectileEmitter.DOUBLE_GAP, 0.001)
	assert_str(inst.description()).contains("fires twice in quick succession")


# ---------------------------------------------------------------- Dragon's Breath: 60% of them

func test_dragons_breath_lights_sixty_percent_and_the_blunderbuss_all() -> void:
	var db := _inst("boomstick", ["dragons_breath"], 5)
	assert_float(db.ignite_chance()).is_equal_approx(0.6, 0.001)
	assert_str(db.description()).contains("Sets 60% of the enemies it hits on fire")
	var rows := {}
	for r: Dictionary in db.stat_rows():
		rows[str(r["stat"])] = str(r["value"])
	assert_str(str(rows.get("ignite_chance", ""))).is_equal("60%")
	# the evolution keeps its fire sure, over the Dragon's Breath it carries
	var bb := _inst("blunderbuss", ["dragons_breath", "birdshot_lane", "both_barrels"])
	assert_float(bb.ignite_chance()).is_equal(1.0)
	assert_str(bb.description()).contains("Sets on fire")
	# everything else sets on fire as ever
	assert_float(_inst("molotov").ignite_chance()).is_equal(1.0)


func test_a_shot_rolls_once_a_creature_and_sixty_percent_catch() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	Run.debug_set_item("weapon", "boomstick", 3)
	Run.debug_set_item("mutation", "dragons_breath", 1)
	assert_float(Run.weapon_instance("boomstick").ignite_chance()).is_equal_approx(0.6, 0.001)
	em._rng.seed = 51
	var lit := 0
	var n := 0
	for k in range(5):
		var ids: Array = []
		for c in range(40):
			ids.append(_creature(em, Vector3(float(c % 8) * 1.5 - 6.0, 0, float(c / 8) * 1.5 + float(k) * 9.0 - 20.0)))
		for i: int in ids:
			# several pellets of one shot on the same creature: one roll, one answer
			em.ignite(i, "boomstick", 4.0, 1.8, 0.0)
			var first := em.is_burning(i)
			em.ignite(i, "boomstick", 4.0, 1.8, 0.0)
			em.ignite(i, "boomstick", 4.0, 1.8, 0.0)
			assert_bool(em.is_burning(i)).is_equal(first)
			lit += 1 if first else 0
			n += 1
		for i: int in ids:
			em._free(i)
	var share := float(lit) / float(n)
	assert_float(share).override_failure_message("%d of %d caught" % [lit, n]).is_between(0.5, 0.7)
	# the next shot rolls again once the hold is over
	var j := _creature(em, Vector3(0, 0, 30))
	em.ign_t[j] = 0.0
	var answers := {}
	for k in range(40):
		em.ign_t[j] = 0.0
		answers[em.ignite_roll(j, "boomstick", 0.6)] = true
	assert_int(answers.size()).is_equal(2)
	# a fire that jumps from a burning creature never rolls
	var a := _creature(em, Vector3(10, 0, 30))
	var b := _creature(em, Vector3(10.5, 0, 30))
	em.ign_t[b] = EnemyManager.IGNITE_ROLL_HOLD
	em.ign_w[b] = "boomstick"
	em.ign_ok[b] = 0
	em.ignite(b, "boomstick", 4.0, 1.8, 0.0, a)
	assert_bool(em.is_burning(b)).is_true()
