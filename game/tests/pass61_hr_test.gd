extends GdUnitTestSuite

## Pass 61, lane HR (Garry: "Heroes have 1-2 unique stats, and they scale as they level up"): every hero in play has a
## signature stat that grows with his level (CharacterDef.level_trait, JSON "trait_per_level", folded by
## Run._build_player_sheet as one effect a stat worth value x level) and nothing else for a trait; the heroes come in the
## order Garry gave (CharacterDef.order); TextGen.hero_trait words the rule everywhere; a tap on the title's plaque opens
## the hero's sheet (ui/wanted/WHeroSheet.gd, the CV), a swipe across the plaque still changes the hero.

const SHEET := preload("res://ui/wanted/WHeroSheet.gd")
const HEROES := ["drifter", "astro", "calavera", "ironwood", "solenne"]

var _keep: Dictionary = {}


func before_test() -> void:
	_keep = {"debug_mode": Settings.debug_mode, "top_inset": Settings.top_inset, "menu_style": Settings.menu_style,
		"preview": Settings.preview_locked_heroes, "last": Save.data.get("last_character", "")}
	Settings.debug_mode = false
	Settings.top_inset = -1
	Settings.preview_locked_heroes = false
	Save.data = Save._default()
	# the real crit chance (the suites leave it out, Run.base_crit): the Drifter's signature is crit
	Run.base_crit = true


func after_test() -> void:
	Run.base_crit = false
	Settings.debug_mode = bool(_keep["debug_mode"])
	Settings.top_inset = int(_keep["top_inset"])
	Settings.menu_style = str(_keep["menu_style"])
	Settings.preview_locked_heroes = bool(_keep["preview"])
	Save.data["last_character"] = _keep["last"]
	Run.arena = false
	Run.end()


func _hero(id: String) -> CharacterDef:
	var c: CharacterDef = Registry.character(id)
	assert_object(c).is_not_null()
	return c


## The run's own sheet for a hero at a level, as a run builds it.
func _run_sheet(id: String, level: int) -> StatSheet:
	Run.start(_hero(id), Registry.map("red_canyon"))
	Run.level = level
	Run.rebuild_sheets()
	return Run.player_sheet


func _player(id: String) -> Player:
	Run.start(_hero(id), Registry.map("red_canyon"))
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	add_child(p)
	p.setup(_hero(id))
	p.refresh_stats()
	p.hp = p.max_hp
	return p


func _texts(n: Node) -> String:
	var out := ""
	if n is WText:
		out += (n as WText).text + "\n"
	for c in n.get_children():
		out += _texts(c)
	return out


func _touch(at: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = at
	ev.pressed = pressed
	get_tree().root.push_input(ev, true)


func _drag(from: Vector2, to: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = 0
	ev.position = to
	ev.relative = to - from
	get_tree().root.push_input(ev, true)


func _frames(n: int) -> void:
	for k in range(n):
		await get_tree().process_frame


func _title() -> Control:
	Settings.menu_style = "painted"
	Save.data["last_character"] = "drifter"
	var t: Control = auto_free(load("res://ui/TitleScreen.tscn").instantiate())
	add_child(t)
	await _frames(3)
	return t


# ---------------------------------------------------------------- the rule on the sheet

func test_the_five_heroes_sheets_at_levels_1_10_and_40() -> void:
	# the Drifter: 1% crit chance a level on everyone's 1%
	assert_float(Run.hero_sheet(_hero("drifter"), 1).get_stat("crit_chance")).is_equal_approx(0.02, 0.00001)
	assert_float(Run.hero_sheet(_hero("drifter"), 10).get_stat("crit_chance")).is_equal_approx(0.11, 0.00001)
	assert_float(Run.hero_sheet(_hero("drifter"), 40).get_stat("crit_chance")).is_equal_approx(0.41, 0.00001)
	# Astro: 2 max HP a level on the 100
	assert_float(Run.hero_sheet(_hero("astro"), 1).get_stat("max_hp")).is_equal_approx(102.0, 0.0001)
	assert_float(Run.hero_sheet(_hero("astro"), 10).get_stat("max_hp")).is_equal_approx(120.0, 0.0001)
	assert_float(Run.hero_sheet(_hero("astro"), 40).get_stat("max_hp")).is_equal_approx(180.0, 0.0001)
	assert_float(_hero("astro").level_heal).is_equal_approx(0.08, 0.00001)
	# Calavera: 1% attack damage a level
	assert_float(Run.hero_sheet(_hero("calavera"), 1).get_stat("might")).is_equal_approx(1.01, 0.00001)
	assert_float(Run.hero_sheet(_hero("calavera"), 10).get_stat("might")).is_equal_approx(1.10, 0.00001)
	assert_float(Run.hero_sheet(_hero("calavera"), 40).get_stat("might")).is_equal_approx(1.40, 0.00001)
	# Ironwood: 0.1 regen and 0.05 s off the 3 s wait a level
	var iw1 := Run.hero_sheet(_hero("ironwood"), 1)
	var iw10 := Run.hero_sheet(_hero("ironwood"), 10)
	var iw40 := Run.hero_sheet(_hero("ironwood"), 40)
	assert_float(iw1.get_stat("regen")).is_equal_approx(0.1, 0.00001)
	assert_float(iw10.get_stat("regen")).is_equal_approx(1.0, 0.00001)
	assert_float(iw40.get_stat("regen")).is_equal_approx(4.0, 0.00001)
	assert_float(iw1.get_stat("regen_delay")).is_equal_approx(2.95, 0.00001)
	assert_float(iw10.get_stat("regen_delay")).is_equal_approx(2.5, 0.00001)
	assert_float(iw40.get_stat("regen_delay")).is_equal_approx(1.0, 0.00001)
	# Solenne: 1.5% debuff duration a level
	assert_float(Run.hero_sheet(_hero("solenne"), 1).get_stat("debuff_duration")).is_equal_approx(1.015, 0.00001)
	assert_float(Run.hero_sheet(_hero("solenne"), 10).get_stat("debuff_duration")).is_equal_approx(1.15, 0.00001)
	assert_float(Run.hero_sheet(_hero("solenne"), 40).get_stat("debuff_duration")).is_equal_approx(1.6, 0.00001)
	# the run's sheet is the same sheet
	assert_float(_run_sheet("drifter", 40).get_stat("crit_chance")).is_equal_approx(0.41, 0.00001)
	assert_float(_run_sheet("astro", 10).get_stat("max_hp")).is_equal_approx(120.0, 0.0001)
	# under the test runner (Run.base_crit off) the Drifter's crit stays out with the base 1%, so no suite meets a
	# random double
	Run.base_crit = false
	assert_float(Run.hero_sheet(_hero("drifter"), 40).get_stat("crit_chance")).is_equal(0.0)
	Run.base_crit = true


func test_nothing_else_one_effect_a_stat_and_no_compounding() -> void:
	var wanted := {"drifter": ["crit_chance"], "astro": ["max_hp"], "calavera": ["might"],
		"ironwood": ["regen", "regen_delay"], "solenne": ["debuff_duration"]}
	for id: String in HEROES:
		var c := _hero(id)
		# no flat trait left, only the signature stat
		assert_array(c.trait_effects).override_failure_message(id + " still has a flat trait").is_empty()
		var stats: Array = []
		for e: Effect in c.level_trait:
			stats.append(e.stat)
		assert_array(stats).override_failure_message(id).contains_exactly(wanted[id])
		var sheet := Run.hero_sheet(c, 30)
		# no Upgrade ranks in a fresh save: every effect on the sheet is the trait's, one a stat
		assert_int(sheet.entries.size()).override_failure_message(id).is_equal(c.level_trait.size())
		for en: Dictionary in sheet.entries:
			assert_str(str(en["source"])).is_equal("%s (Lv 30)" % c.trait_name)
	# 40 levels of +1% attack damage are +40%, not 1.01^40 (1.49)
	assert_float(Run.hero_sheet(_hero("calavera"), 40).get_stat("might")).is_equal_approx(1.4, 0.00001)
	# every other stat stays the default: no speed, no magnet, no damage reduction, no lost health
	var d := StatSheet.PLAYER_DEFAULTS
	assert_float(Run.hero_sheet(_hero("drifter"), 20).get_stat("move_speed")).is_equal_approx(float(d["move_speed"]), 0.00001)
	assert_float(Run.hero_sheet(_hero("drifter"), 20).get_stat("magnet")).is_equal_approx(float(d["magnet"]), 0.00001)
	assert_float(Run.hero_sheet(_hero("astro"), 20).get_stat("damage_reduction")).is_equal_approx(0.0, 0.00001)
	assert_float(Run.hero_sheet(_hero("calavera"), 20).get_stat("max_hp")).is_equal_approx(100.0, 0.00001)
	assert_float(Run.hero_sheet(_hero("calavera"), 20).get_stat("crit_chance")).is_equal_approx(0.01, 0.00001)


func test_solenne_gets_no_buff_duration_and_no_other_bonus() -> void:
	for lv: int in [1, 10, 40]:
		var s := Run.hero_sheet(_hero("solenne"), lv)
		assert_float(s.get_stat("buff_duration")).is_equal_approx(1.0, 0.00001)
		assert_float(s.get_stat("cooldown")).is_equal_approx(1.0, 0.00001)
		assert_float(s.get_stat("max_hp")).is_equal_approx(100.0, 0.00001)
		assert_float(s.get_stat("heal_mult")).is_equal_approx(1.0, 0.00001)


func test_the_sheet_follows_a_level_up() -> void:
	Run.start(_hero("drifter"), Registry.map("red_canyon"))
	assert_int(Run.level).is_equal(1)
	assert_float(Run.player_sheet.get_stat("crit_chance")).is_equal_approx(0.02, 0.00001)
	Run.add_xp(Run.xp_to_next())
	assert_int(Run.level).is_equal(2)
	assert_float(Run.player_sheet.get_stat("crit_chance")).is_equal_approx(0.03, 0.00001)
	# three levels at once: the sheet is the last level's
	Run.add_xp(Run.xp_to_next() + Run.xp_to_next(3) + Run.xp_to_next(4) + 0.5)
	assert_int(Run.level).is_equal(5)
	assert_float(Run.player_sheet.get_stat("crit_chance")).is_equal_approx(0.06, 0.00001)
	# the pause screen's breakdown names it with the level
	var rows := Run.player_sheet.breakdown("crit_chance")
	assert_str(str(rows[1]["source"])).is_equal("Long Road (Lv 5)")
	assert_str(str(rows[1]["text"])).is_equal("+5%")


func test_astros_health_rises_with_her_max_hp() -> void:
	var p := _player("astro")
	assert_float(p.max_hp).is_equal_approx(102.0, 0.0001)
	# wounded: a level-up adds the 2 HP to what she has, not a share of it
	p.hp = 50.0
	Run.add_xp(Run.xp_to_next())
	p.refresh_stats()
	assert_float(p.max_hp).is_equal_approx(104.0, 0.0001)
	assert_float(p.hp).is_equal_approx(52.0, 0.0001)
	# whole: she stays whole
	p.hp = p.max_hp
	Run.add_xp(Run.xp_to_next())
	p.refresh_stats()
	assert_float(p.max_hp).is_equal_approx(106.0, 0.0001)
	assert_float(p.hp).is_equal_approx(106.0, 0.0001)
	# a fall (the Stranger's cut) still keeps the share she had
	p.hp = 53.0
	Run.stranger_cost = 0.5
	Run.rebuild_sheets()
	p.refresh_stats()
	assert_float(p.max_hp).is_equal_approx(53.0, 0.0001)
	assert_float(p.hp).is_equal_approx(26.5, 0.0001)
	Run.stranger_cost = 0.0


func test_ironwoods_regen_delay_never_goes_under_half_a_second() -> void:
	var c := _hero("ironwood")
	assert_float(Run.hero_sheet(c, 50).get_stat("regen_delay")).is_equal_approx(0.5, 0.00001)
	assert_float(Run.hero_sheet(c, 60).get_stat("regen_delay")).is_equal_approx(0.5, 0.00001)
	assert_float(Run.hero_sheet(c, 99).get_stat("regen_delay")).is_equal_approx(0.5, 0.00001)
	assert_float(float(StatSheet.STAT_FLOORS["regen_delay"])).is_equal(0.5)
	# a weapon's sheet (scope "") is never floored
	var w := StatSheet.new()
	w.set_base("regen_delay", 0.1)
	assert_float(w.get_stat("regen_delay")).is_equal_approx(0.1, 0.00001)
	# the hero waits half a second after a hit at level 60, never less
	var p := _player("ironwood")
	Run.level = 60
	Run.rebuild_sheets()
	p.refresh_stats()
	p.god = false
	p.invuln = 0.0
	p.take_damage(1.0, p.global_position + Vector3(1, 0, 0), {"by": "test", "kind": "melee"})
	assert_float(p.regen_hold).is_equal_approx(0.5, 0.00001)


# ---------------------------------------------------------------- the order and the words

func test_the_heroes_come_in_garrys_order() -> void:
	var ids: Array = Registry.sorted_characters().map(func(c: CharacterDef) -> String: return c.id)
	# pass 66: the five are present with these orders, not "exactly these" (a hero made in the Level Editor may follow
	# them; pass66_shape_test holds the order rule for whoever is in play)
	assert_array(ids).contains(HEROES)
	# pass 72, lane INTEG (re-pinned): Garry re-orders the heroes in the Level Editor (2026-10-13: Drifter 1, Ironwood 2,
	# Astro 3, Calavera 4), so the rule is pinned: the five in play, the title's order the JSONs' `order`, all distinct,
	# the Drifter first
	var orders: Array = []
	for id: String in HEROES:
		assert_bool(_hero(id).hidden).override_failure_message(id).is_false()
	for i in ids.size():
		var c: CharacterDef = Registry.character(str(ids[i]))
		assert_bool(orders.has(c.order)).override_failure_message("%s shares order %d" % [c.id, c.order]).is_false()
		if i > 0:
			assert_int(c.order).override_failure_message(c.id).is_greater(int(orders[orders.size() - 1]))
		orders.append(c.order)
	assert_str(str(ids[0])).is_equal("drifter")


func test_the_trait_words() -> void:
	assert_str(TextGen.hero_trait(_hero("drifter"))).is_equal("Gain 1% crit chance per level.")
	assert_str(TextGen.hero_trait(_hero("astro"))).is_equal("Gain 2 max HP per level, and heal 8% of max HP on every level-up.")
	assert_str(TextGen.hero_trait(_hero("calavera"))).is_equal("Gain 1% attack damage per level.")
	assert_str(TextGen.hero_trait(_hero("ironwood"))).is_equal(
		"Gain 0.1 HP regen and 0.05 s less regen delay per level (regen delay never under 0.5 s).")
	assert_str(TextGen.hero_trait(_hero("solenne"))).is_equal(
		"Gain 1.5% debuff duration per level (her burns, poison, slows and pins last longer; buffs do not).")
	# the JSON's own words say the same (the bible and anything that reads trait_text)
	for id: String in HEROES:
		assert_str(_hero(id).trait_text).is_equal(TextGen.hero_trait(_hero(id)))
	# what it comes to
	assert_str(TextGen.hero_trait_now(_hero("drifter"), 12)).is_equal("+12% crit chance at level 12")
	assert_str(TextGen.hero_trait_now(_hero("astro"), 12)).is_equal("+24 max HP at level 12")
	assert_str(TextGen.hero_trait_now(_hero("solenne"), 20)).is_equal("+30% debuff duration at level 20")
	assert_str(TextGen.hero_trait_now(_hero("ironwood"), 12)).is_equal("+1.2 HP regen and 0.6 s less regen delay at level 12")
	# the delay stops at its floor: 3 s less 2.5 s at the most
	assert_str(TextGen.hero_trait_at(_hero("ironwood"), 60)).is_equal("+6 HP regen and 2.5 s less regen delay")
	# pass 67: Buck is back with a level rule (Full Tilt) and his charge (a special) says itself after it, in his own words
	var buck: CharacterDef = Registry.character("buck")
	if buck:
		assert_str(TextGen.hero_trait(buck)).is_equal("Gain 1% move speed per level. " + buck.trait_text)
		assert_str(TextGen.hero_trait_now(buck, 10)).is_equal("+10% move speed at level 10")
	# a hidden hero without a rule keeps his own words
	var dad: CharacterDef = Registry.character("dad")
	if dad:
		assert_str(TextGen.hero_trait(dad)).is_equal(dad.trait_text)
		assert_str(TextGen.hero_trait_now(dad, 10)).is_equal("")


func test_the_plaque_shows_what_a_level_gives() -> void:
	var t = load("res://ui/TitleScreen.gd").new()
	var rows: Array = t._stats_of(_hero("drifter"))
	assert_int(rows.size()).is_equal(1)
	assert_str(str(rows[0][0])).is_equal("+1%")
	assert_str(str(rows[0][1])).is_equal("CRIT / LV")
	rows = t._stats_of(_hero("astro"))
	assert_str(str(rows[0][0])).is_equal("+2")
	assert_str(str(rows[0][1])).is_equal("HP / LV")
	assert_str(str(rows[1][0])).is_equal("8%")
	assert_str(str(rows[1][1])).is_equal("HEAL / LV")
	rows = t._stats_of(_hero("ironwood"))
	assert_str(str(rows[0][0])).is_equal("+0.1/s")
	assert_str(str(rows[1][0])).is_equal("−0.05 s")
	assert_bool(bool(rows[1][2])).is_true()
	rows = t._stats_of(_hero("solenne"))
	assert_str(str(rows[0][0])).is_equal("+1.5%")
	assert_str(str(rows[0][1])).is_equal("DEBUFF DURATION / LV")
	rows = t._stats_of(_hero("calavera"))
	assert_str(str(rows[0][0])).is_equal("+1%")
	assert_str(str(rows[0][1])).is_equal("ATTACK DAMAGE / LV")
	t.free()


# ---------------------------------------------------------------- the hero's sheet (the CV)

func test_the_sheet_builds_every_block_for_every_hero() -> void:
	var host := Control.new()
	host.size = Vector2(1080, 1920)
	add_child(host)
	auto_free(host)
	for id: String in HEROES:
		var c := _hero(id)
		var s: Control = SHEET.open(host, c, false)
		await _frames(2)
		for n: String in ["Dim", "Card", "Scroll", "Body", "Close", "Portrait", "Name", "Slogan", "Signature", "Stats", "Items"]:
			assert_object(s.find_child(n, true, false)).override_failure_message("%s: no %s" % [id, n]).is_not_null()
		assert_object(s.find_child("Locked", true, false)).is_null()
		var all := _texts(s)
		assert_str(all).contains(SHEET.hero_name(c).to_upper())
		assert_str(all).contains(c.flavour)
		assert_str(all).contains(TextGen.hero_trait(c))
		# the levels table: 1, 10, 20, 40
		var levels: Node = s.find_child("Levels", true, false)
		assert_int(levels.get_child_count()).is_equal(4)
		assert_str(_texts(levels)).contains("LV 40")
		# the stats a run starts with
		var stats: Node = s.find_child("Stats", true, false)
		assert_object(stats.find_child("Stat_max_hp", true, false)).is_not_null()
		assert_object(stats.find_child("Stat_crit_chance", true, false)).is_not_null()
		# the items: the start weapon with the words a level-up card gives it, the favourite, the perks
		var start := Registry.start_weapon_for(c)
		var row: Node = s.find_child("Item_start_" + start.id, true, false)
		assert_object(row).override_failure_message(id + ": no start weapon").is_not_null()
		assert_str(_texts(row)).contains(start.display_name)
		assert_str(_texts(row)).contains(SHEET.describe(start, TitleScreenLevel.of(c, start), Run.hero_sheet(c, 1)))
		for pk: PerkDef in Registry.perks_of(c.id):
			var pr: Node = s.find_child("Item_perk_" + pk.id, true, false)
			assert_object(pr).override_failure_message(id + ": no perk " + pk.id).is_not_null()
			assert_str(_texts(pr)).contains(pk.text)
		var fav_id := c.favourite_weapon if c.favourite_weapon != "" else c.favourite_passive
		if fav_id != "" and fav_id != start.id:
			assert_object(s.find_child("Item_favourite_" + fav_id, true, false)).override_failure_message(id + ": no favourite").is_not_null()
		for m: MutationDef in Registry.hero_mutations(c.id):
			assert_object(s.find_child("Item_mutation_" + m.id, true, false)).is_not_null()
		s.close()
		await _frames(1)
		s.free()
	# a locked one says what unlocks him
	var locked: Control = SHEET.open(host, _hero("drifter"), true)
	await _frames(2)
	assert_object(locked.find_child("Locked", true, false)).is_not_null()
	locked.free()


func test_the_plaque_opens_the_sheet_and_a_swipe_still_changes_the_hero() -> void:
	var t := await _title()
	assert_bool(t.sheet_open()).is_false()
	var plaque: Control = t.find_child("Plaque", false, false)
	assert_object(plaque).is_not_null()
	var at: Vector2 = plaque.get_global_rect().get_center()
	# a swipe across the plaque: the next hero, no sheet
	var was: int = t._index
	_touch(at, true)
	_drag(at, at + Vector2(-120, 0))
	_drag(at + Vector2(-120, 0), at + Vector2(-240, 0))
	_touch(at + Vector2(-240, 0), false)
	await _frames(2)
	assert_int(t._index).is_not_equal(was)
	assert_bool(t.sheet_open()).is_false()
	# a tap on it: the sheet of the hero shown
	at = plaque.get_global_rect().get_center()
	_touch(at, true)
	_touch(at, false)
	await _frames(2)
	assert_bool(t.sheet_open()).is_true()
	var s: Control = t.find_child("HeroSheet", false, false)
	assert_object(s).is_not_null()
	assert_object(s.get("hero")).is_same(t._heroes[t._index])
	# while it is up a swipe does not change the hero under it
	var now: int = t._index
	_touch(Vector2(540, 900), true)
	_touch(Vector2(240, 900), false)
	await _frames(1)
	assert_int(t._index).is_equal(now)
	# CLOSE closes it
	var close: Control = s.find_child("Close", true, false)
	await _frames(12)
	at = close.get_global_rect().get_center()
	_touch(at, true)
	_touch(at, false)
	await _frames(1)
	assert_bool(t.sheet_open()).is_false()
	await _frames(12)
	# a tap on the dim outside the card closes it too
	t.open_sheet()
	await _frames(12)
	assert_bool(t.sheet_open()).is_true()
	_touch(Vector2(12, 900), true)
	_touch(Vector2(12, 900), false)
	await _frames(1)
	assert_bool(t.sheet_open()).is_false()
	await _frames(12)
	# and the back gesture closes it without leaving the game
	t.open_sheet()
	await _frames(2)
	assert_bool(t.sheet_open()).is_true()
	# (only with the sheet up: without it the title leaves the game, and the runner with it)
	if t.sheet_open():
		t._notification(Control.NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_bool(t.sheet_open()).is_false()
	t.visible = false


func test_the_sheet_scrolls_by_a_finger() -> void:
	var t := await _title()
	t.open_sheet()
	await _frames(12)
	var s: Control = t.find_child("HeroSheet", false, false)
	var sc: ScrollContainer = s.find_child("Scroll", true, false)
	assert_int(int(sc.get_v_scroll_bar().max_value)).is_greater(int(sc.size.y))
	var at := sc.get_global_rect().get_center()
	_touch(at, true)
	for k in range(8):
		_drag(at - Vector2(0, 40 * k), at - Vector2(0, 40 * (k + 1)))
	_touch(at - Vector2(0, 320), false)
	await _frames(2)
	assert_int(sc.scroll_vertical).is_greater(100)
	# a drag that ends on the dim does not close it
	assert_bool(t.sheet_open()).is_true()
	s.call("close")
	t.visible = false


func test_the_card_keeps_clear_of_a_camera_cutout() -> void:
	Settings.top_inset = 130
	var host := Control.new()
	host.size = Vector2(1080, 1920)
	add_child(host)
	auto_free(host)
	var s: Control = SHEET.open(host, _hero("solenne"), false)
	await _frames(2)
	var card: Control = s.find_child("Card", true, false)
	assert_float(card.offset_top).is_greater_equal(130.0 + SHEET.TOP - 0.01)
	s.free()


## The level an item is at on the plaque, read from the title's own rule.
class TitleScreenLevel:
	static func of(c: CharacterDef, def: ContentDef) -> int:
		return int(load("res://ui/TitleScreen.gd").start_level(c, def))
