## Pass 140, lane HEROLIST (Garry: "When unlocking a hero that is in the middle of the list, we will make sure to rearrange
## the list such that the unlocked ones are bunched together and the locked ones are bunched together as well (so I don't
## have to scroll through many locked characters to get to the one that I have). This effect should be visible in both the
## main menu and the outlaw screen bottom ui element"):
##  - Registry.heroes_in_menu_order: the owned outlaws first, then those on sale, then the locked ones, each group in
##    today's order (`order`, Registry.sorted_characters); the hidden ones only while the developer previews them, last;
##  - a newly owned outlaw moves into the owned group the next time the list is built (the title's BUY rebuilds at once);
##  - the title's carousel and the Outlaws screen's picker list exactly that order and keep their pick by id.
## The checks do not pin which outlaws the Trail or a task gives (lanes TRAIL and QUESTS change that): an outlaw is made
## owned through whatever holds him (the save's heroes_owned, which the Trail reads as his node bought, and his quest).
extends GdUnitTestSuite

const TITLE := "res://ui/TitleScreen.tscn"
const HEROES := "res://ui/HeroesScreen.tscn"

var _keep: Dictionary = {}


func before_test() -> void:
	_keep = {"preview": Settings.preview_locked_heroes, "inset": Settings.top_inset,
		"iron": Registry.character("ironwood").availability}
	Settings.preview_locked_heroes = false
	Settings.top_inset = -1
	W.bottom_inset_override = 0.0
	Save.data = Save._default()
	Save._dirty = false
	Trail.refresh()


func after_test() -> void:
	Registry.character("ironwood").availability = str(_keep["iron"])
	Settings.preview_locked_heroes = bool(_keep["preview"])
	Settings.top_inset = int(_keep["inset"])
	W.bottom_inset_override = -1.0
	Save.data = Save._default()
	Save._dirty = false
	Trail.refresh()


# ---------------------------------------------------------------- helpers

## Makes outlaw `id` owned the way the save holds it: in heroes_owned (the Trail reads that as his node bought) and his
## unlock quest done when he has one.
func _own(id: String) -> void:
	var ho: Array = Save.data.get("heroes_owned", [])
	if not ho.has(id):
		ho.append(id)
	Save.data["heroes_owned"] = ho
	var q: QuestDef = Registry.quest_for("character", id)
	if q:
		var qd: Array = Save.data.get("quests_done", [])
		if not qd.has(q.id):
			qd.append(q.id)
		Save.data["quests_done"] = qd
	Trail.refresh()
	assert_str(Registry.hero_state(Registry.character(id))).override_failure_message("%s is not owned" % id).is_equal("owned")


func _ids(list: Array) -> Array:
	return list.map(func(c: CharacterDef) -> String: return c.id)


## Today's order of the outlaws in state group `states` (Registry.sorted_characters filtered).
func _today(states: Array) -> Array:
	return _ids(Registry.sorted_characters().filter(func(c: CharacterDef) -> bool: return states.has(Registry.hero_state(c))))


## The list is owned, then on sale, then locked, each group in today's order.
func _assert_grouped(list: Array) -> void:
	assert_array(_ids(list)).is_equal(_today(["owned"]) + _today(["buyable"]) + _today(["locked"]))


func _not_owned_late() -> CharacterDef:
	# the not-owned outlaw latest in today's order: he stands at the far end of the list until he is owned
	var cands: Array = Registry.sorted_characters().filter(func(c: CharacterDef) -> bool: return Registry.hero_state(c) != "owned")
	return cands.back() if not cands.is_empty() else null


func _title() -> Control:
	var t: Control = auto_free(load(TITLE).instantiate())
	add_child(t)
	await get_tree().create_timer(0.32).timeout
	await get_tree().process_frame
	return t


func _heroes_screen() -> Control:
	var s: Control = auto_free(load(HEROES).instantiate())
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	return s


func _grid_ids(s: Control) -> Array:
	var grid: GridContainer = s.find_child("HeroGrid", true, false)
	var out: Array = []
	for t: Node in grid.get_children():
		if t.is_queued_for_deletion():
			continue
		out.append(str(t.name).trim_prefix("Hero_"))
	return out


# ---------------------------------------------------------------- the order

func test_owned_first_then_locked_each_in_todays_order() -> void:
	var list: Array = Registry.heroes_in_menu_order()
	_assert_grouped(list)
	assert_bool(_today(["owned"]).size() >= 1).is_true()
	# the old name is the same list (tests and tools read it)
	assert_array(_ids(Registry.heroes_for_drawer())).is_equal(_ids(list))
	# no hidden outlaw (Dad, Mira) without the developer's preview
	for c: CharacterDef in list:
		assert_bool(c.hidden).override_failure_message(c.id).is_false()


func test_the_captures_save_drifter_ironwood_astro_solenne_first() -> void:
	for id in ["drifter", "ironwood", "astro", "solenne"]:
		_own(id)
	var ids := _ids(Registry.heroes_in_menu_order())
	assert_array(ids.slice(0, 4)).is_equal(["drifter", "ironwood", "astro", "solenne"])
	_assert_grouped(Registry.heroes_in_menu_order())
	for id: String in ids.slice(4):
		assert_str(Registry.hero_state(Registry.character(id))).override_failure_message(id).is_not_equal("owned")


func test_a_newly_owned_outlaw_moves_into_the_owned_group() -> void:
	var late := _not_owned_late()
	assert_object(late).is_not_null()
	var before := _ids(Registry.heroes_in_menu_order())
	var n_owned := _today(["owned"]).size()
	assert_int(before.find(late.id)).is_greater_equal(n_owned)
	_own(late.id)
	var after := _ids(Registry.heroes_in_menu_order())
	_assert_grouped(Registry.heroes_in_menu_order())
	# he is among the first n+1 now, before every outlaw still not owned
	assert_int(after.find(late.id)).is_less(n_owned + 1)
	for id: String in after.slice(n_owned + 1):
		assert_str(Registry.hero_state(Registry.character(id))).override_failure_message(id).is_not_equal("owned")
	# the owned ones keep today's order among themselves (he lands after those before him in `order`)
	assert_array(after.slice(0, n_owned + 1)).is_equal(_today(["owned"]))


func test_hidden_outlaws_only_with_the_preview_and_last() -> void:
	var plain := _ids(Registry.heroes_in_menu_order(false))
	var all_ids := _ids(Registry.heroes_in_menu_order(true))
	var hidden: Array = Registry.characters.values().filter(func(c: CharacterDef) -> bool: return c.hidden)
	assert_int(all_ids.size()).is_equal(plain.size() + hidden.size())
	assert_array(all_ids.slice(0, plain.size())).is_equal(plain)
	var tail: Array = all_ids.slice(plain.size())
	var want: Array = _ids(hidden)
	want.sort()
	assert_array(tail).is_equal(want)
	if Registry.characters.has("mira"):
		assert_str(str(all_ids.back())).is_equal("mira")


func test_hero_index_finds_by_id() -> void:
	var list: Array = Registry.heroes_in_menu_order()
	for i in list.size():
		assert_int(Registry.hero_index(list, (list[i] as CharacterDef).id)).is_equal(i)
	assert_int(Registry.hero_index(list, "nobody_p140")).is_equal(-1)
	assert_int(Registry.hero_index([], "drifter")).is_equal(-1)


# ---------------------------------------------------------------- the two menus

func test_title_lists_the_shared_order_and_keeps_its_pick_by_id() -> void:
	for id in ["drifter", "ironwood", "astro", "solenne"]:
		_own(id)
	Save.data["last_character"] = "solenne"
	var t := await _title()
	assert_array(_ids(t._heroes)).is_equal(_ids(Registry.heroes_in_menu_order()))
	assert_str((t._heroes[t._index] as CharacterDef).id).is_equal("solenne")
	var at_before: int = t._index
	# an outlaw before her in today's order is unlocked: on the next entry she moved down one and is still the pick
	var early: CharacterDef = null
	for c: CharacterDef in Registry.sorted_characters():
		if Registry.hero_state(c) != "owned" and c.order < Registry.character("solenne").order:
			early = c
			break
	if early == null:
		return
	_own(early.id)
	var t2 := await _title()
	assert_array(_ids(t2._heroes)).is_equal(_ids(Registry.heroes_in_menu_order()))
	assert_str((t2._heroes[t2._index] as CharacterDef).id).is_equal("solenne")
	assert_int(t2._index).is_equal(at_before + 1)


func test_title_buy_moves_him_into_the_owned_group_and_keeps_him_shown() -> void:
	var iron: CharacterDef = Registry.character("ironwood")
	if Trail.gated("outlaw", "ironwood"):
		return
	# Garry's case: an outlaw in the middle of the list (Ironwood, second in today's order) unlocked while the list shows
	iron.availability = "purchase"
	Save.data["gold"] = maxi(iron.price, 0) + 10
	var t := await _title()
	var ids := _ids(t._heroes)
	assert_int(ids.find("ironwood")).is_equal(_today(["owned"]).size())
	t._index = Registry.hero_index(t._heroes, "ironwood")
	t._buy_now(iron)
	assert_str(Registry.hero_state(iron)).is_equal("owned")
	assert_array(_ids(t._heroes)).is_equal(_ids(Registry.heroes_in_menu_order()))
	assert_str((t._heroes[t._index] as CharacterDef).id).is_equal("ironwood")
	_assert_grouped(t._heroes)


func test_outlaws_picker_lists_the_shared_order_and_keeps_the_shown_by_id() -> void:
	for id in ["drifter", "ironwood", "astro", "solenne"]:
		_own(id)
	Save.data["last_character"] = "solenne"
	var s := await _heroes_screen()
	assert_array(_grid_ids(s)).is_equal(_ids(Registry.heroes_in_menu_order()))
	assert_array(_ids(s.heroes)).is_equal(_ids(Registry.heroes_in_menu_order()))
	assert_str((s.shown as CharacterDef).id).is_equal("solenne")
	# a later unlock: refresh (what a purchase calls) builds the list again, he joins the owned tiles, she stays shown
	var late := _not_owned_late()
	_own(late.id)
	s.refresh()
	await get_tree().process_frame
	assert_array(_grid_ids(s)).is_equal(_ids(Registry.heroes_in_menu_order()))
	assert_int(_grid_ids(s).find(late.id)).is_less(_today(["owned"]).size())
	assert_str((s.shown as CharacterDef).id).is_equal("solenne")


func test_outlaws_picker_buy_regroups_and_shows_him() -> void:
	var iron: CharacterDef = Registry.character("ironwood")
	if Trail.gated("outlaw", "ironwood"):
		return
	iron.availability = "purchase"
	Save.data["gold"] = maxi(iron.price, 0) + 10
	var s := await _heroes_screen()
	assert_int(_grid_ids(s).find("ironwood")).is_equal(_today(["owned"]).size())
	s.show_hero(iron)
	assert_bool(s.buy_now(iron)).is_true()
	await get_tree().process_frame
	assert_array(_grid_ids(s)).is_equal(_ids(Registry.heroes_in_menu_order()))
	assert_str((s.shown as CharacterDef).id).is_equal("ironwood")
	_assert_grouped(s.heroes)
