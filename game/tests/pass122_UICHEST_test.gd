## Pass 122, lane UICHEST: the Royale chest screen (Garry's build brief of 2026-11-02 on Claude Design's "Royale,
## refined": a second theme behind a switch, Wanted the default and untouched; "Chest as the mock: the item framed over
## rays, a slate name card with the stat row, SKIP · BANISH · TAKE IT", "Make the Stars more visible though ... Also
## make the Header text white").
##  - the chest builds, opens and lands under both themes; under Royale the header is cream Ultra with the navy edge and
##    no gold bevel, the star line gold, the landed item a 320 px frame over the kit's rays with its level plaque and no
##    brass glow box; under Wanted the 436 px plate with its glow and the brass title with its 8 px ink shadow, as before;
##  - the three buttons' roles under Royale: SKIP slate with the count in a pill, BANISH slate (locked at none, its
##    count grey), TAKE IT gold; the label reads the same under both themes;
##  - the buttons, the name card and the landing cell sit at the same rects under both themes (a replay's taps land);
##  - the name card's layout under Royale (the kind's runs in the kit's colours, the name at 66, left-aligned, the change
##    rows across the card, the stars at today's size and pulsing) and the Wanted layout as _ready makes it;
##  - a legendary item's and an evolved item's frame flags on the landed plate, a level-5 weapon's (pass 48's rule), gold's
##    coin on a derived frame, the mutation chest's header and violet light;
##  - the mutation offer's reel builds its tiles as plates (the kit's frames under Royale) and lands on a tap; the chest's
##    paintings are there and it draws under both themes.
extends GdUnitTestSuite

const WChestScript := preload("res://ui/wanted/WChest.gd")

var _settings_before: Dictionary = {}


func before() -> void:
	_settings_before = Settings.to_dict()


func after() -> void:
	Settings.force_prod(false)
	Settings.from_dict(_settings_before)
	W.theme_changed()


func after_test() -> void:
	Run.arena = false
	Run.end()
	Settings.force_prod(false)
	Settings.ui_theme = "wanted"
	W.theme_changed()


func _royale(on: bool) -> void:
	Settings.ui_theme = "royale" if on else "wanted"
	W.theme_changed()


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


## The chest's intro skipped and its reel hurried until it lands.
func _land(cs: ChestScreen) -> void:
	cs.skip_intro()
	cs._tw.set_speed_scale(40.0)
	for k in 80:
		await get_tree().process_frame
		if not cs._spinning:
			break


## A chest screen in the tree (freed by the test itself: queue_free at its end).
func _chest() -> ChestScreen:
	var cs := ChestScreen.new()
	add_child(cs)
	await get_tree().process_frame
	return cs


## A passive item of `rarity` that is not a line and has an icon.
func _passive_of(rarity: String) -> PassiveDef:
	for p: PassiveDef in Registry.passives.values():
		if p.rarity == rarity and not p.hidden and not p.is_evolved() and not p.is_line() and p.icon != null:
			return p
	return null


func _evolution() -> WeaponDef:
	for w: WeaponDef in Registry.weapons.values():
		if w.is_evolution and w.icon != null and w.evolved_from != "":
			return w
	return null


func _up(boom: WeaponDef, from: int, to: int) -> Dictionary:
	return {"type": "weapon", "id": boom.id, "def": boom, "level_from": from, "level_to": to, "is_new": false}


func _count_node(b: WButton) -> Node:
	return b.find_child("Count", true, false)


# ---------------------------------------------------------------- the screen under both themes, its rects equal

func test_the_chest_lands_under_both_themes_and_keeps_its_rects() -> void:
	_start()
	var boom: WeaponDef = Registry.weapon("boomstick")
	Run.add_weapon(boom, 2)
	var rects: Dictionary = {}
	for royale in [false, true]:
		_royale(royale)
		Run.skips_left = 2
		Run.banishes_left = 1
		var cs: ChestScreen = await _chest()
		cs.open(_up(boom, 2, 3))
		await _land(cs)
		await _frames(2)
		assert_bool(cs._spinning).override_failure_message("royale=%s: the reel did not land" % royale).is_false()
		var side: float = ChestScreen.BIG_ROYALE if royale else ChestScreen.BIG
		assert_float(cs.landed_side()).is_equal(side)
		assert_float(cs._hero.side).is_equal(side)
		assert_bool(cs._hero.rays).is_equal(royale)
		assert_bool(cs._hero_glow.visible).is_equal(not royale)
		assert_int(cs._hero.level_plaque).is_equal(3 if royale else 0)
		# the kind's corner disc stays off the Royale frame (the plaque would clip it; the card says WEAPON); the reel's
		# passing tiles keep theirs
		assert_str(cs._hero.kind_mark).is_equal("" if royale else "weapon")
		# (the passing tiles are the reel's own random fill: each keeps the mark its item calls for, a weapon's or a Card's)
		for pe: Array in cs._plates:
			if pe[1] != null and (pe[0] as WPlate) != cs._hero:
				assert_str((pe[0] as WPlate).kind_mark).is_equal(W.kind_mark_of(pe[1] as ContentDef))
		# centred on the landing cell either way, in the reel over the shine
		assert_bool((cs._hero.position + Vector2(side, side) * 0.5).is_equal_approx(cs.landing_center())).is_true()
		assert_bool(cs._hero.get_parent() == cs._reel).is_true()
		# the header: cream Ultra with the navy edge and no bevel (Garry: white) over a gold star line; brass with the ink
		# shadow under Wanted
		if royale:
			assert_bool(cs.header.title.color.is_equal_approx(R.CREAM)).is_true()
			assert_bool(R.is_display(cs.header.title.font)).is_true()
			assert_int(cs.header.title.stroke).is_greater(0)
			assert_int(cs.header.title.shadow).is_greater(0)
			assert_bool(cs.header.title.shadow_straight).is_true()
			assert_bool(cs.header.title.shadow_color.is_equal_approx(R.NAVY)).is_true()
			assert_int(cs.header.title.bevel).is_equal(0)
			assert_bool(cs.header.star_line.color.is_equal_approx(R.GOLD_TEXT)).is_true()
			assert_bool(cs.dim_color.is_equal_approx(R.DIM)).is_true()
		else:
			assert_bool(cs.header.title.color.is_equal_approx(W.BRASS)).is_true()
			assert_int(cs.header.title.shadow).is_equal(8)
			assert_int(cs.header.title.stroke).is_equal(0)
			assert_bool(cs.header.star_line.color.is_equal_approx(W.PAPER)).is_true()
			assert_bool(cs.dim_color.is_equal_approx(W.DIM_CHEST)).is_true()
		# the buttons: SKIP and BANISH slate, TAKE IT gold (the roles mean nothing under Wanted); the label the same
		assert_str(cs._skip_btn.role).is_equal(WButton.SLATE)
		assert_str(cs._banish_btn.role).is_equal(WButton.SLATE)
		assert_str(cs._take_btn.role).is_equal(WButton.GOLD)
		assert_bool(cs._skip_btn.locked).is_false()
		assert_bool(cs._banish_btn.locked).is_true()   # the next level of a held weapon cannot be banished (pass 58)
		assert_str(cs._skip_btn.label_text()).is_equal("SKIP ×2")
		assert_str(cs._banish_btn.label_text()).is_equal("BANISH ×1")
		assert_str(cs._take_btn.label_text()).is_equal("TAKE IT")
		if royale:
			assert_object(_count_node(cs._skip_btn)).is_not_null()
			assert_object(_count_node(cs._banish_btn)).is_not_null()
		else:
			assert_object(_count_node(cs._skip_btn)).is_null()
		# the name card: the mock's left-aligned layout under Royale, the kind's word in the kit's runs; Wanted as _ready
		# made it
		assert_str(cs._word.text).is_equal("WEAPON")
		if royale:
			assert_int(cs._word.runs.size()).is_equal(1)
			assert_str(str(cs._word.runs[0][0])).is_equal("WEAPON")
			assert_bool((cs._word.runs[0][1] as Color).is_equal_approx(R.SECONDARY)).is_true()
			assert_int(cs._name.font_size).is_equal(ChestScreen.NAME_PX_ROYALE)
			assert_float(cs._name.line_height).is_equal(float(ChestScreen.NAME_PX_ROYALE))
			assert_int(cs._name.align).is_equal(HORIZONTAL_ALIGNMENT_LEFT)
			assert_bool(cs._name.color.is_equal_approx(R.CREAM)).is_true()
			assert_int(cs._name.stroke).is_greater(0)
			assert_int(cs._word_row.alignment).is_equal(BoxContainer.ALIGNMENT_BEGIN)
			assert_int(cs._marks_host.size_flags_horizontal).is_equal(Control.SIZE_SHRINK_BEGIN)
			assert_int(cs._effect.align).is_equal(HORIZONTAL_ALIGNMENT_LEFT)
			assert_float(cs._changes.custom_minimum_size.x).is_equal(cs.card_inner_width())
			assert_float(cs.card_inner_width()).is_equal(cs.get_viewport_rect().size.x - ChestScreen.PANEL_SIDE * 2.0 - ChestScreen.PANEL_PAD_X * 2.0)
		else:
			assert_int(cs._word.runs.size()).is_equal(0)
			assert_int(cs._name.font_size).is_equal(ChestScreen.NAME_PX)
			assert_float(cs._name.line_height).is_equal(float(ChestScreen.NAME_PX))
			assert_int(cs._name.align).is_equal(HORIZONTAL_ALIGNMENT_CENTER)
			assert_bool(cs._name.color.is_equal_approx(W.INK)).is_true()
			assert_int(cs._name.stroke).is_equal(0)
			assert_int(cs._word_row.alignment).is_equal(BoxContainer.ALIGNMENT_CENTER)
			assert_int(cs._marks_host.size_flags_horizontal).is_equal(Control.SIZE_FILL)
			assert_int(cs._effect.align).is_equal(HORIZONTAL_ALIGNMENT_CENTER)
			assert_float(cs._changes.custom_minimum_size.x).is_equal(ChestScreen.CHANGES_W)
		# the stars at today's size, the new one pulsing (gold in navy under Royale: WMarks)
		assert_object(cs._marks).is_not_null()
		assert_float(cs._marks.mark).is_equal(ChestScreen.STAR_PX)
		assert_bool(cs._marks.pulse).is_true()
		assert_object(cs._tag).is_not_null()
		# the light and the shine: the kit's gold under Royale, brass under Wanted
		var shine := cs.find_child("Shine", false, false) as Control
		if royale:
			assert_bool(cs.light_colour().is_equal_approx(R.role("gold")["bottom"])).is_true()
			assert_bool((shine.get("color") as Color).is_equal_approx(R.role("gold")["bottom"])).is_true()
			assert_bool((shine.get("color2") as Color).is_equal_approx(R.CREAM)).is_true()
		else:
			assert_bool(cs.light_colour().is_equal_approx(W.BRASS)).is_true()
			assert_bool((shine.get("color") as Color).is_equal_approx(W.BRASS)).is_true()
			assert_bool((shine.get("color2") as Color).is_equal_approx(W.PAPER)).is_true()
		rects[royale] = [cs._skip_btn.get_global_rect(), cs._banish_btn.get_global_rect(), cs._take_btn.get_global_rect(),
			cs._panel.get_global_rect().position, cs.landing_center(), cs.buttons.get_global_rect()]
		cs.visible = false
		cs.queue_free()
		await get_tree().process_frame
	# the touch targets and the card are where they were: a replay's or the bot's taps land under either theme
	for i in [0, 1, 2, 5]:
		assert_bool((rects[false][i] as Rect2).is_equal_approx(rects[true][i] as Rect2)).override_failure_message(
			"rect %d: wanted %s, royale %s" % [i, str(rects[false][i]), str(rects[true][i])]).is_true()
	assert_bool((rects[false][3] as Vector2).is_equal_approx(rects[true][3] as Vector2)).is_true()
	assert_bool((rects[false][4] as Vector2).is_equal_approx(rects[true][4] as Vector2)).is_true()
	assert_float((rects[true][0] as Rect2).size.x).is_greater(100.0)


# ---------------------------------------------------------------- the landed frame's flags

func test_the_landed_frame_flags_legendary_evolved_level_five_and_gold() -> void:
	_start()
	var legend := _passive_of("legendary")
	var evo := _evolution()
	var boom: WeaponDef = Registry.weapon("boomstick")
	assert_object(legend).is_not_null()
	assert_object(evo).is_not_null()
	Run.add_weapon(boom, 4)
	for royale in [false, true]:
		_royale(royale)
		Run.skips_left = 2
		Run.banishes_left = 1
		var cs: ChestScreen = await _chest()
		# a new legendary passive item: the thick gold rim (rim_mode 1), LV 1, the rarity named after the kind
		cs.open({"type": "passive", "id": legend.id, "def": legend, "level_from": 0, "level_to": 1, "is_new": true})
		await _land(cs)
		assert_bool(cs._hero.fill.is_equal_approx(W.RARITY_PLATE["legendary"])).is_true()
		assert_str(cs._hero.frame_rarity()).is_equal("legendary")
		assert_int(int(cs._hero.frame_look()["rim_mode"])).is_equal(1)
		assert_bool(cs._hero.is_evolved_frame()).is_false()
		assert_bool(cs._banish_btn.locked).is_false()
		if royale:
			assert_int(cs._hero.level_plaque).is_equal(1)
			assert_int(cs._word.runs.size()).is_equal(2)
			assert_str(str(cs._word.runs[1][0])).is_equal(" LEGENDARY")
			assert_bool((cs._word.runs[1][1] as Color).is_equal_approx(R.RARITY["legendary"]["light"])).is_true()
			var frame := cs._hero.find_child("RoyaleFrame", false, false) as Control
			assert_object(frame).is_not_null()
			assert_int(int((frame.material as ShaderMaterial).get_shader_parameter("rim_mode"))).is_equal(1)
			var rays := cs._hero.find_child("RoyaleRays", false, false) as Control
			assert_object(rays).is_not_null()
			await _frames(2)
			assert_bool(rays.visible).is_true()
			assert_float(rays.size.x).is_equal_approx(roundf(ChestScreen.BIG_ROYALE * R.RAYS_SCALE), 0.5)
		else:
			assert_int(cs._hero.level_plaque).is_equal(0)
			assert_object(cs._hero.find_child("RoyaleFrame", false, false)).is_null()
		# a weapon landing on level 5: its level's colour, legendary (pass 48's rule, no new rarity rule), the kind alone
		cs.open(_up(boom, 4, 5))
		await _land(cs)
		assert_bool(cs._hero.fill.is_equal_approx(W.RARITY_PLATE["legendary"])).is_true()
		assert_str(cs._hero.frame_rarity()).is_equal("legendary")
		if royale:
			assert_int(cs._hero.level_plaque).is_equal(5)
			assert_int(cs._word.runs.size()).is_equal(1)
		# an evolution: the black face in the rainbow rim with EVO (the Wanted brass ring), BANISH locked
		cs.open({"type": "evolution", "id": evo.id, "def": evo, "src_id": evo.evolved_from, "level_from": 0, "level_to": 1})
		await _land(cs)
		assert_bool(cs._hero.fill.is_equal_approx(W.EVOLVED_FILL)).is_true()
		assert_int(cs._hero.ring).is_greater(0)
		assert_bool(cs._hero.is_evolved_frame()).is_true()
		assert_int(int(cs._hero.frame_look()["rim_mode"])).is_equal(2)
		assert_bool(cs._banish_btn.locked).is_true()
		assert_object(cs._marks).is_null()
		assert_object(cs._tag).is_not_null()
		if royale:
			assert_int(cs._hero.level_plaque).is_equal(1)   # ignored: an evolved frame says EVO
			var emat := (cs._hero.find_child("RoyaleFrame", false, false) as Control).material as ShaderMaterial
			assert_int(int(emat.get_shader_parameter("rim_mode"))).is_equal(2)
		# gold: the coin on a frame derived from brass, SKIP and BANISH locked, GOLD in gold
		cs.open({"type": "gold", "id": "", "def": null, "gold": 50, "level_from": 0, "level_to": 0, "is_new": false})
		await _land(cs)
		assert_str(cs._hero.frame_rarity()).is_equal("custom")
		assert_int(cs._hero.level_plaque).is_equal(0)
		var coins := cs._hero.get_children().filter(func(n: Node) -> bool: return n is WCoin)
		assert_int(coins.size()).is_equal(1)
		var coin_px: float = roundf(260.0 * cs.landed_side() / ChestScreen.BIG)
		assert_float((coins[0] as WCoin).side).is_equal_approx(coin_px, 1.0)
		assert_bool(cs._skip_btn.locked).is_true()
		assert_bool(cs._banish_btn.locked).is_true()
		assert_str(cs._word.text).is_equal("GOLD")
		if royale:
			assert_int(cs._word.runs.size()).is_equal(1)
			assert_bool((cs._word.runs[0][1] as Color).is_equal_approx(R.GOLD_TEXT)).is_true()
		else:
			assert_int(cs._word.runs.size()).is_equal(0)
		# the mutation chest's header: MUTATION CHEST cream (white) with the edge under Royale, purple under Wanted; the
		# star line purple either way, the light violet either way
		cs.style_header(true)
		assert_str(cs.header.title.text).is_equal(ChestScreen.BOSS_TITLE)
		assert_bool(cs.light_colour().is_equal_approx(ChestScreen.BOSS_LIGHT)).is_true()
		if royale:
			assert_bool(cs.header.title.color.is_equal_approx(R.CREAM)).is_true()
			assert_int(cs.header.title.stroke).is_greater(0)
			assert_int(cs.header.title.bevel).is_equal(0)
			assert_bool(cs.header.star_line.color.is_equal_approx(R.MUTATION["light"])).is_true()
			assert_bool(cs.title_colour(true).is_equal_approx(R.CREAM)).is_true()
		else:
			assert_bool(cs.header.title.color.is_equal_approx(ChestScreen.BOSS_TITLE_COLOR)).is_true()
			assert_bool(cs.header.star_line.color.is_equal_approx(ChestScreen.BOSS_TITLE_COLOR)).is_true()
		cs.style_header(false)
		assert_str(cs.header.title.text).is_equal("CHEST")
		assert_bool(cs.header.star_line.color.is_equal_approx(R.GOLD_TEXT if royale else W.PAPER)).is_true()
		cs.visible = false
		cs.queue_free()
		await get_tree().process_frame


# ---------------------------------------------------------------- the banish count at none

func test_the_banish_count_reads_none_and_locks_under_royale() -> void:
	_start()
	_royale(true)
	var magnet: PassiveDef = Registry.passive("magnet")
	Run.skips_left = 1
	Run.banishes_left = 0
	var cs: ChestScreen = await _chest()
	cs.open({"type": "passive", "id": magnet.id, "def": magnet, "level_from": 0, "level_to": 1, "is_new": true})
	await _land(cs)
	assert_bool(cs._banish_btn.locked).is_true()
	assert_bool(cs._skip_btn.locked).is_false()
	assert_str(cs._banish_btn.label_text()).is_equal("BANISH ×0")
	var count := _count_node(cs._banish_btn)
	assert_object(count).is_not_null()
	var number := count.get_child(0) as WText
	assert_object(number).is_not_null()
	assert_bool(number.color.is_equal_approx(R.MUTED)).is_true()
	var skip_number := _count_node(cs._skip_btn).get_child(0) as WText
	assert_bool(skip_number.color.is_equal_approx(R.GOLD_TEXT)).is_true()
	# a tap says why and spins nothing
	cs._banish()
	assert_str(cs.header.line.text).is_equal("No banishes left this stage.")
	assert_int(cs.respins).is_equal(0)
	# the tag pill is the kit's (NEW on gold, Rubik 700), the favourite's heart never mind
	var word := cs._tag.find_child("Word", true, false) as WText
	assert_object(word).is_not_null()
	assert_str(word.text).is_equal("NEW")
	assert_bool(R.is_display(word.font)).is_false()
	# the buttons are as tall as their Wanted selves: Ultra's shorter line box is made up by the padding
	var slab := W.normal_height(W._base(W.SLAB_PATH), 34)
	var ultra := W.normal_height(W.slab_for(34), 34)
	assert_float(ultra).is_less(slab)
	assert_float(ChestScreen.button_pad_v(34, ChestScreen.BUTTON_PAD_V)).is_equal_approx(ChestScreen.BUTTON_PAD_V + (slab - ultra) * 0.5, 0.001)
	assert_float(cs._skip_btn.get_combined_minimum_size().y).is_equal_approx(slab + ChestScreen.BUTTON_PAD_V * 2.0 + 10.0, 0.6)
	cs.visible = false
	cs.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------- the reel's tiles and the chest's paintings

func test_the_reel_tiles_are_plates_and_the_chest_draws_under_both_themes() -> void:
	_start()
	var boom: WeaponDef = Registry.weapon("boomstick")
	var saws: WeaponDef = Registry.weapon("orbit_saws")
	assert_object(saws).is_not_null()
	assert_int(WChestScript.paintings(false).size()).is_equal(3)
	assert_int(WChestScript.paintings(true).size()).is_equal(3)
	for royale in [false, true]:
		_royale(royale)
		var host := Control.new()
		host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(host)
		var reel := WWeaponReel.new()
		host.add_child(reel)
		reel.play([boom, saws], saws, 0.3)
		await _frames(2)
		assert_int(reel._plates.size()).is_greater(1)
		for p in reel._plates:
			assert_bool(p is WPlate).is_true()
		var first := reel._plates[0] as WPlate
		if royale:
			assert_object(first.find_child("RoyaleFrame", false, false)).is_not_null()
		else:
			assert_object(first.find_child("RoyaleFrame", false, false)).is_null()
		assert_object(reel._window).is_not_null()
		reel.skip()
		await _frames(2)
		assert_bool(reel.is_landed()).is_true()
		assert_bool((reel._plates[reel.landing_cell()] as WPlate).tex == saws.icon).is_true()
		# the painted chest opens the same way under both themes (its light the kit's colours under Royale: a draw)
		var chest: WChestScript = WChestScript.new()
		host.add_child(chest)
		chest.setup(royale, Vector2(540, 1400), 420.0)
		assert_bool(chest.painted()).is_true()
		chest.at(WChestScript.OPEN + 0.1)
		assert_float(chest.light).is_greater(0.0)
		assert_bool(chest.visible).is_true()
		await _frames(2)
		host.queue_free()
		await get_tree().process_frame
