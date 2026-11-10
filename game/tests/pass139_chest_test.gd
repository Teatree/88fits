## Pass 139, lane CHEST (Garry: "Mutation chest should show which weapon a mutation is for, because no one remembers them
## like that. I think maybe the weapon icon at it's direct rarity it's mutation count appearing under the selected
## mutation and it's text could be good."):
##  - a landed mutation's card carries the weapon badge (WWeaponBadge): the right weapon, its level and frame as the HUD's
##    slot shows it, the path's mutations held and its total, the one this chest gives lit and pulsing, the count "n/3";
##  - a hero's own mutation (outside the path) lights no rivet; an evolved family shows its evolution;
##  - no badge for a weapon upgrade, a new item, gold or an evolution;
##  - the buttons' rects are the same as for any other landing (a replay's taps land where they were) and the card with the
##    longest mutation text still ends above them.
extends GdUnitTestSuite

const WeaponBadgeScript := preload("res://ui/wanted/WWeaponBadge.gd")


func after_test() -> void:
	Run.arena = false
	Run.end()


func _start() -> void:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Run.debug_clear_items()


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


func _chest() -> ChestScreen:
	var cs := ChestScreen.new()
	add_child(cs)
	await get_tree().process_frame
	return cs


## The chest opened on `roll`, its intro skipped and its reel hurried until it lands.
func _land(cs: ChestScreen, roll: Dictionary) -> void:
	Run.skips_left = 2
	Run.banishes_left = 1
	cs.open(roll)
	cs.skip_intro()
	cs._tw.set_speed_scale(40.0)
	for k in 120:
		await get_tree().process_frame
		if not cs._spinning:
			break
	await _frames(3)


## `n` of `weapon`'s path held (never `skip_id`); returns the first path mutation not held.
func _hold(weapon: String, n: int, skip_id: String = "") -> MutationDef:
	var held := 0
	for m: MutationDef in Registry.mutations_of(weapon):
		if held >= n:
			break
		if m.id == skip_id:
			continue
		Run.debug_set_item("mutation", m.id, 1)
		held += 1
	for m: MutationDef in Registry.mutations_of(weapon):
		if not Run.mutations_held(weapon).has(m.id) and m.id != skip_id:
			return m
	return null


func _mut_roll(md: MutationDef) -> Dictionary:
	return {"type": "mutation", "id": md.id, "def": md, "level_from": 0, "level_to": 1, "is_new": true, "boss": true}


func test_a_mutation_chest_shows_the_weapon_it_is_for() -> void:
	_start()
	Run.debug_set_item("weapon", "revolver", 4)
	Run.debug_set_item("weapon", "boomstick", 2)
	var md := _hold("revolver", 1)
	assert_object(md).is_not_null()
	var total := Registry.mutations_of("revolver").size()
	var cs := await _chest()
	await _land(cs, _mut_roll(md))
	var b = cs.weapon_badge()
	assert_object(b).override_failure_message("no weapon badge on a landed mutation").is_not_null()
	assert_str(b.weapon_id).is_equal("revolver")
	assert_int(b.level).is_equal(4)
	assert_int(b.held).is_equal(1)
	assert_int(b.total).is_equal(total)
	assert_bool(b.gives).is_true()
	assert_int(b.count_shown()).is_equal(2)
	assert_str(b.count_text.text).is_equal("2/%d" % total)
	# the rivets: one held, the one this chest gives lit and pulsing
	assert_int(b.rivets.held).is_equal(1)
	assert_int(b.rivets.upto).is_equal(2)
	assert_int(b.rivets.total).is_equal(total)
	assert_bool(b.rivets.pulse).is_true()
	# the plate as the HUD's slot draws it: the revolver's icon at level 4 in that level's frame, its plain level number
	var hud := WPlate.new().for_def(Registry.weapon("revolver"), 72.0, false, 4)
	if not Settings.hud_slot_rarity:
		hud.fill = W.RARITY_PLATE["common"]
	assert_str(b.plate.frame_rarity()).is_equal(hud.frame_rarity())
	assert_object(b.plate.tex).is_equal(W.icon_at(Registry.weapon("revolver"), 4))
	assert_str(b.plate.level_text).is_equal("4")
	hud.free()
	# its words: FOR over the weapon's name, through the string table
	assert_str((b.find_child("For", true, false) as WText).text).is_equal(Loc.t(WeaponBadgeScript.FOR_KEY).to_upper())
	assert_str(b.name_text.text).is_equal(Registry.weapon("revolver").display_name)
	# under the mutation's name and text, inside the card
	assert_bool(cs._badge_host.visible).is_true()
	var col := cs._badge_host.get_parent()
	assert_int(cs._badge_host.get_index()).is_greater(cs._effect.get_index())
	assert_bool(col == cs._effect.get_parent()).is_true()
	# nothing in it takes a finger (the taps on the screen land as before)
	for n: Node in [cs._badge_host, b] + b.find_children("*", "Control", true, false):
		assert_int((n as Control).mouse_filter).override_failure_message("%s takes taps" % n.name).is_equal(Control.MOUSE_FILTER_IGNORE)
	cs.queue_free()


func test_the_count_at_none_and_at_two_held() -> void:
	_start()
	Run.debug_set_item("weapon", "revolver", 3)
	var md0 := _hold("revolver", 0)
	var f0: Dictionary = WeaponBadgeScript.facts(md0)
	assert_int(int(f0["held"])).is_equal(0)
	assert_bool(bool(f0["gives"])).is_true()
	assert_object(f0["weapon"]).is_equal(Registry.weapon("revolver"))
	assert_int(int(f0["level"])).is_equal(3)
	var md2 := _hold("revolver", 2)
	var f2: Dictionary = WeaponBadgeScript.facts(md2)
	assert_int(int(f2["held"])).is_equal(2)
	assert_bool(bool(f2["gives"])).is_true()
	var b = WeaponBadgeScript.for_mutation(md2)
	assert_int(b.count_shown()).is_equal(mini(3, int(f2["total"])))
	b.free()


func test_a_heros_own_mutation_lights_no_rivet() -> void:
	_start()
	Run.debug_set_item("weapon", "lob_grenade", 3)
	var hm: MutationDef = Registry.mutation("fire_in_the_hole")
	assert_object(hm).is_not_null()
	assert_bool(hm.is_hero()).is_true()
	_hold("lob_grenade", 1)
	var cs := await _chest()
	await _land(cs, _mut_roll(hm))
	var b = cs.weapon_badge()
	assert_object(b).is_not_null()
	assert_str(b.weapon_id).is_equal("lob_grenade")
	assert_bool(b.gives).is_false()
	assert_int(b.held).is_equal(1)
	assert_int(b.count_shown()).is_equal(1)
	assert_int(b.rivets.upto).is_equal(-1)
	assert_bool(b.rivets.pulse).is_false()
	cs.queue_free()


func test_an_evolved_family_shows_its_evolution() -> void:
	_start()
	var evo: WeaponDef = Registry.weapon(Registry.weapon("revolver").evolves_into)
	assert_object(evo).is_not_null()
	Run.debug_set_item("weapon", evo.id, 1)
	var md := MutationDef.new()
	md.id = "test_mut"
	md.weapon = "revolver"
	var f: Dictionary = WeaponBadgeScript.facts(md)
	assert_object(f["weapon"]).is_equal(evo)
	# a mutation that is not on the path gives no rivet
	assert_bool(bool(f["gives"])).is_false()
	var none := MutationDef.new()
	assert_bool(WeaponBadgeScript.facts(none).is_empty()).is_true()
	assert_object(WeaponBadgeScript.for_mutation(none)).is_null()


func test_no_badge_for_an_upgrade_an_item_gold_or_an_evolution() -> void:
	_start()
	Run.debug_set_item("weapon", "boomstick", 2)
	var boom: WeaponDef = Registry.weapon("boomstick")
	var pd: PassiveDef = null
	for p: PassiveDef in Registry.passives.values():
		if not p.hidden and not p.is_evolved() and not p.is_line() and p.icon != null:
			pd = p
			break
	var evo: WeaponDef = Registry.weapon(boom.evolves_into)
	var rolls: Array = [
		{"type": "weapon", "id": boom.id, "def": boom, "level_from": 2, "level_to": 3, "is_new": false},
		{"type": "passive", "id": pd.id, "def": pd, "level_from": 0, "level_to": 1, "is_new": true},
		{"type": "gold", "id": "", "def": null, "gold": 50, "level_from": 0, "level_to": 0, "is_new": false},
		{"type": "evolution", "id": evo.id, "def": evo, "src_id": boom.id, "level_from": 0, "level_to": 1, "is_new": true}]
	var cs := await _chest()
	# a mutation first, so each roll after it must take the badge away
	await _land(cs, _mut_roll(_hold("boomstick", 0)))
	assert_object(cs.weapon_badge()).is_not_null()
	for r: Dictionary in rolls:
		await _land(cs, r)
		assert_bool(cs._spinning).is_false()
		assert_object(cs.weapon_badge()).override_failure_message("a %s roll showed a weapon badge" % str(r["type"])).is_null()
		assert_bool(cs._badge_host.visible).is_false()
		assert_int(cs._badge_host.get_child_count()).is_equal(0)
	cs.queue_free()


func test_the_buttons_stay_put_and_the_longest_text_fits_above_them() -> void:
	_start()
	Run.debug_set_item("weapon", "boomstick", 4)
	Run.debug_set_item("weapon", "revolver", 2)
	var boom: WeaponDef = Registry.weapon("boomstick")
	var cs := await _chest()
	await _land(cs, {"type": "weapon", "id": boom.id, "def": boom, "level_from": 4, "level_to": 5, "is_new": false})
	var was := [cs._skip_btn.get_global_rect(), cs._banish_btn.get_global_rect(), cs._take_btn.get_global_rect(),
		cs.buttons.get_global_rect(), cs._panel.get_global_rect().position, cs.landing_center()]
	# the longest mutation text of any weapon in play, on its own weapon
	var longest: MutationDef = null
	for w: WeaponDef in Registry.weapons.values():
		if w.is_evolution or w.hidden:
			continue
		for m: MutationDef in Registry.mutations_of(w.id):
			if longest == null or m.text.length() > longest.text.length():
				longest = m
	assert_object(longest).is_not_null()
	Run.debug_set_item("weapon", longest.weapon, 3)
	await _land(cs, _mut_roll(longest))
	assert_object(cs.weapon_badge()).is_not_null()
	var now := [cs._skip_btn.get_global_rect(), cs._banish_btn.get_global_rect(), cs._take_btn.get_global_rect(),
		cs.buttons.get_global_rect(), cs._panel.get_global_rect().position, cs.landing_center()]
	for i in was.size():
		assert_bool(now[i] == was[i]).override_failure_message("part %d moved: %s -> %s" % [i, str(was[i]), str(now[i])]).is_true()
	# the card ends above the buttons, with the badge inside it
	var card := cs._panel.get_global_rect()
	assert_float(card.end.y).is_less(cs.buttons.get_global_rect().position.y)
	var br: Rect2 = cs.weapon_badge().get_global_rect()
	assert_bool(card.encloses(br)).override_failure_message("badge %s outside the card %s" % [str(br), str(card)]).is_true()
	# on a 1080 x 1920 screen the buttons are where they were before pass 139
	var vp := cs.get_viewport_rect().size
	if vp.is_equal_approx(Vector2(1080, 1920)):
		assert_bool((now[0] as Rect2).position.is_equal_approx(Vector2(48, 1716))).is_true()
		assert_bool((now[2] as Rect2).position.is_equal_approx(Vector2(672, 1716))).is_true()
	assert_bool(Loc.has(WeaponBadgeScript.FOR_KEY)).is_true()
	cs.queue_free()
