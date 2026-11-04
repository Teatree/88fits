## Pass 122, lane UIHUD: the HUD under the Royale theme (Garry's build brief of 2026-11-02; W.royale()):
##  - Settings.hud_slot_rarity defaults off, round-trips with the other settings, is held off in prod, has its row in the
##    in-run debug panel;
##  - the HUD builds under both themes with its ten slots; under Royale every filled slot is a kit frame with a plaque
##    hanging under it, plain common unless the switch is on (then the level's colour or the rarity, pass 48's rule), an
##    evolved item black in its rainbow rim either way; under Wanted the level colours whatever the switch;
##  - the same boxes under both themes (the rail, the three top plates, the pause button, every slot);
##  - the HUD's own pieces follow the theme (the plates' boxes, the words' face and edge, the pause button, the strip
##    above the rail) and a flip in a run restyles them in place;
##  - the pieces Garry keeps exactly as they are (the kill counter's number, the boss's name and bar) wear the Wanted face
##    under both themes;
##  - the power-ups' plates (a WPlate under Wanted, the black RoyaleBuffPlate under Royale) and the pointers;
##  - the mutation mark and the clock's modes under Royale.
extends GdUnitTestSuite

var _settings_before: Dictionary = {}


func before() -> void:
	_settings_before = Settings.to_dict()


func after() -> void:
	Settings.force_prod(false)
	Settings.from_dict(_settings_before)
	W.theme_changed()


func before_test() -> void:
	Settings.force_prod(false)
	Settings.ui_theme = "wanted"
	Settings.hud_slot_rarity = false
	W.theme_changed()


func after_test() -> void:
	Settings.force_prod(false)
	Settings.ui_theme = "wanted"
	Settings.hud_slot_rarity = false
	W.theme_changed()
	Settings.top_inset = -1
	Run.arena = false
	Run.end()


func _royale(on: bool) -> void:
	Settings.ui_theme = "royale" if on else "wanted"
	W.theme_changed()


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


## Two weapons (level 2 and 5), an evolution and a line at level 2 on the strip.
func _build() -> void:
	_start()
	Run.debug_clear_items()
	Run.add_weapon(Registry.weapon("boomstick"), 2)
	Run.add_weapon(Registry.weapon("peashooter"), 5)
	Run.debug_set_item("evolution", "killer_swarm", 1)
	Run.add_or_level_passive("brawn")
	Run.add_or_level_passive("brawn")
	Run.build_changed.emit()


func _base_path(f: Font) -> String:
	var b := f
	while b is FontVariation and (b as FontVariation).base_font:
		b = (b as FontVariation).base_font
	return b.resource_path if b else ""


func _hud() -> HUD:
	var hud: HUD = auto_free(HUD.new())
	add_child(hud)
	return hud


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _rects(hud: HUD) -> Dictionary:
	var r := {"rail": hud._rail.get_rect(), "lv": hud._lv_plate.get_rect(), "timer": hud._timer_plate.get_rect(),
		"gold": hud._gold_plate.get_rect(), "pause": hud._pause_btn.get_rect(), "slots": hud._slots.get_rect()}
	var plates: Array = hud._slots.get_children().filter(func(p: Node) -> bool: return not p.is_queued_for_deletion())
	for i in plates.size():
		r["slot%d" % i] = (plates[i] as Control).get_rect()
	return r


# ---------------------------------------------------------------- the switch

func test_the_slot_rarity_switch_defaults_on_and_is_locked_in_prod() -> void:
	# pass 123 (Garry: "Weapon Rarity isn't displayed at the top left it's only the number right now"): on by default, kept
	# under a new key so a save that held the old default does not hold it off
	var script: GDScript = load("res://core/autoload/Settings.gd")
	var s: Node = auto_free(script.new())
	assert_bool(s.hud_slot_rarity).is_true()
	assert_bool(script.PROD_LOCKED.has("hud_slot_rarity")).is_true()
	assert_bool(bool(script.PROD_LOCKED["hud_slot_rarity"])).is_false()
	assert_bool(s.to_dict().has("hud_slot_rarity2")).is_true()
	assert_bool(bool(s.to_dict()["hud_slot_rarity2"])).is_true()
	s.from_dict({"hud_slot_rarity": false})
	assert_bool(s.hud_slot_rarity).override_failure_message("the old key no longer speaks").is_true()
	s.from_dict({"hud_slot_rarity2": false})
	assert_bool(s.hud_slot_rarity).is_false()
	var back: Node = auto_free(script.new())
	back.from_dict(s.to_dict())
	assert_bool(back.hud_slot_rarity).is_false()
	s.from_dict({"music_volume": 0.3})
	assert_bool(s.hud_slot_rarity).is_false()
	s.from_dict({"hud_slot_rarity2": true})
	assert_bool(s.hud_slot_rarity).is_true()
	# the live Settings: set_value flips it and tells the listeners
	var was: bool = Settings.hud_slot_rarity
	Settings.set_value("hud_slot_rarity", false)
	var heard: Array = []
	var cb := func(): heard.append(Settings.hud_slot_rarity)
	Settings.changed.connect(cb)
	Settings.set_value("hud_slot_rarity", true)
	assert_bool(Settings.hud_slot_rarity).is_true()
	assert_array(heard).is_equal([true])
	Settings.changed.disconnect(cb)
	# prod holds it off: forced on, set_value is ignored and a save with it on is locked after it loads
	Settings.force_prod(true)
	assert_bool(Settings.hud_slot_rarity).is_false()
	Settings.set_value("hud_slot_rarity", true)
	assert_bool(Settings.hud_slot_rarity).is_false()
	Settings.from_dict({"hud_slot_rarity2": true})
	assert_bool(Settings.hud_slot_rarity).is_false()
	Settings.force_prod(false)
	Settings.set_value("hud_slot_rarity", was)
	# the in-run debug panel has the row, beside the theme's
	var dp: DebugPanel = auto_free(DebugPanel.new())
	add_child(dp)
	await _frames(1)
	var words: Array = []
	for c in dp._box.get_children():
		if c is Button:
			words.append((c as Button).text)
	assert_bool(words.has("HUD slot rarity: off / on")).override_failure_message(str(words)).is_true()
	assert_bool(words.has("UI theme: wanted / royale")).is_true()
	assert_int(words.find("HUD slot rarity: off / on")).is_equal(words.find("UI theme: wanted / royale") + 1)
	# its tap flips the switch
	for c in dp._box.get_children():
		if c is Button and (c as Button).text == "HUD slot rarity: off / on":
			(c as Button).pressed.emit()
	assert_bool(Settings.hud_slot_rarity).is_true()
	Settings.set_value("hud_slot_rarity", false)


# ---------------------------------------------------------------- the HUD under both themes

func test_the_hud_builds_under_both_themes_with_its_slots_and_plaques() -> void:
	_build()
	var rects := {}
	for royale in [false, true]:
		_royale(royale)
		var hud := _hud()
		await _frames(2)
		assert_str(hud.theme_applied()).is_equal("royale" if royale else "wanted")
		var plates: Array = hud._slots.get_children()
		assert_int(plates.size()).is_equal(10)
		var filled := 0
		for p: WPlate in plates:
			assert_float(p.side).is_equal(72.0)
			assert_float(p.position.y).is_equal(0.0)
			var frame := p.find_child("RoyaleFrame", false, false)
			if royale:
				assert_object(frame).override_failure_message("a Royale frame under every slot").is_not_null()
			else:
				assert_object(frame).is_null()
			if p.empty:
				assert_str(p.frame_rarity()).is_equal("slot")
				assert_float(p.plate_alpha).is_equal(HUD.SLOT_ALPHA)
				continue
			filled += 1
			assert_float(p.plate_alpha).is_equal(1.0)
			# the level under the slot: the kit's plaque under Royale, a plain number on a 72 px frame, hanging under it
			assert_str(p.level_text).is_not_empty()
			assert_str(p.plaque_text(int(p.level_text))).is_equal(p.level_text)
			var pr := p.plaque_rect(p.level_text)
			assert_float(pr.end.y).is_greater(p.side)
			assert_float(pr.position.y).is_less(p.side)
			assert_float(pr.end.y - p.side).is_less(HUD.BUFF_GAP + 6.0)
		assert_int(filled).is_equal(4)
		var evo: WPlate = hud._slot_nodes["killer_swarm"]
		var boom: WPlate = hud._slot_nodes["boomstick"]
		var pea: WPlate = hud._slot_nodes["peashooter"]
		var brawn: WPlate = hud._slot_nodes["brawn"]
		assert_bool(evo.is_evolved_frame()).is_true()
		assert_str(evo.frame_rarity()).is_equal("evolved")
		assert_bool(boom.is_evolved_frame()).is_false()
		if royale:
			# the switch off: plain common frames (the mock's rarity colours are Garry's to compare on the phone)
			assert_bool(Settings.hud_slot_rarity).is_false()
			assert_str(boom.frame_rarity()).is_equal("common")
			assert_str(pea.frame_rarity()).is_equal("common")
			assert_str(brawn.frame_rarity()).is_equal("common")
			assert_bool(boom.fill.is_equal_approx(W.RARITY_PLATE["common"])).is_true()
			# on: pass 48's level colours (and a passive item's rarity), the rows laid out again at once
			Settings.set_value("hud_slot_rarity", true)
			await _frames(1)
			boom = hud._slot_nodes["boomstick"]
			pea = hud._slot_nodes["peashooter"]
			brawn = hud._slot_nodes["brawn"]
			evo = hud._slot_nodes["killer_swarm"]
			assert_str(boom.frame_rarity()).is_equal("uncommon")
			assert_str(pea.frame_rarity()).is_equal("legendary")
			assert_str(brawn.frame_rarity()).is_equal("uncommon")
			assert_str(evo.frame_rarity()).is_equal("evolved")
			assert_bool(boom.fill.is_equal_approx(W.level_fill(2))).is_true()
			assert_bool(pea.fill.is_equal_approx(W.level_fill(5))).is_true()
			Settings.set_value("hud_slot_rarity", false)
			await _frames(1)
			assert_str((hud._slot_nodes["peashooter"] as WPlate).frame_rarity()).is_equal("common")
			assert_str((hud._slot_nodes["killer_swarm"] as WPlate).frame_rarity()).is_equal("evolved")
		else:
			# Wanted: the level colours whatever the switch says (pass 48 pins them too)
			assert_bool(boom.fill.is_equal_approx(W.level_fill(2))).is_true()
			assert_bool(pea.fill.is_equal_approx(W.level_fill(5))).is_true()
			assert_bool(brawn.fill.is_equal_approx(W.RARITY_PLATE["uncommon"])).is_true()
			assert_bool(evo.fill.is_equal_approx(W.EVOLVED_FILL)).is_true()
			assert_int(evo.ring).is_greater(0)
			Settings.set_value("hud_slot_rarity", true)
			await _frames(1)
			assert_bool((hud._slot_nodes["boomstick"] as WPlate).fill.is_equal_approx(W.level_fill(2))).is_true()
			assert_object((hud._slot_nodes["boomstick"] as WPlate).find_child("RoyaleFrame", false, false)).is_null()
			Settings.set_value("hud_slot_rarity", false)
			await _frames(1)
		# the HUD's own pieces in the theme
		var lv_box: HardBox = hud._lv_plate.get_theme_stylebox("panel")
		assert_str(lv_box.role).is_equal("plate")
		assert_str((hud._timer_plate.get_theme_stylebox("panel") as HardBox).role).is_equal("plate")
		assert_str((hud._gold_plate.get_theme_stylebox("panel") as HardBox).role).is_equal("plate")
		assert_bool(lv_box.fill.is_equal_approx(W.PAPER)).is_true()
		assert_int(lv_box.border).is_equal(4)
		assert_int(lv_box.shadow).is_equal(5)
		var pb: HardBox = hud._pause_btn.box
		if royale:
			for t: WText in [hud._lv, hud._timer, hud._gold]:
				assert_bool(R.is_display(t.font)).is_true()
				assert_bool(t.color.is_equal_approx(R.WHITE)).is_true()
				assert_int(t.stroke).is_greater(0)
				assert_bool(t.stroke_color.is_equal_approx(R.NAVY)).is_true()
				assert_bool(t.shadow_straight).is_true()
			assert_str(pb.role).is_equal("slate")
			assert_int(pb.radius).is_equal(R.RADIUS)
			assert_int(pb.shadow).is_equal(R.BUTTON_BASE)
			assert_bool(hud._cutout.color.is_equal_approx(HUD.ROYALE_RAIL_BLACK)).is_true()
			assert_bool(((hud._pause_btn.get_node("PauseBars") as Control).get_child(0) as ColorRect).color.is_equal_approx(R.role("slate")["text"])).is_true()
			assert_bool(R.is_display(hud._mut_word.font)).is_true()
			assert_bool(hud._mut_word.color.is_equal_approx(R.WHITE)).is_true()
		else:
			for t: WText in [hud._lv, hud._timer, hud._gold]:
				assert_str(_base_path(t.font)).is_equal(W.SLAB_PATH)
				assert_bool(t.color.is_equal_approx(W.INK)).is_true()
				assert_int(t.stroke).is_equal(0)
				assert_int(t.shadow).is_equal(0)
				assert_bool(t.shadow_straight).is_false()
			assert_str(pb.role).is_equal("")
			assert_bool(pb.fill.is_equal_approx(W.BRASS)).is_true()
			assert_int(pb.radius).is_equal(int(HUD.DISC * 0.5))
			assert_int(pb.shadow).is_equal(5)
			assert_bool(hud._cutout.color.is_equal_approx(W.INK)).is_true()
			assert_bool(((hud._pause_btn.get_node("PauseBars") as Control).get_child(0) as ColorRect).color.is_equal_approx(W.INK)).is_true()
			assert_str(_base_path(hud._mut_word.font)).is_equal(W.SLAB_PATH)
			assert_bool(hud._mut_word.color.is_equal_approx(W.PAPER)).is_true()
		# the words sit in their holders: the holder's box is the Wanted face's, the words centred in it
		for pair in [[hud._lv, hud._lv_hold], [hud._timer, hud._timer_hold], [hud._gold, hud._gold_hold]]:
			var t: WText = pair[0]
			var h: Control = pair[1]
			assert_object(t.get_parent()).is_same(h)
			assert_float(h.custom_minimum_size.x).is_greater(0.0)
			assert_float(absf((t.position.x + t.size.x * 0.5) - h.size.x * 0.5)).is_less(1.0)
			if not royale:
				assert_bool(t.position.is_zero_approx()).is_true()
				assert_bool(t.size.is_equal_approx(h.size)).is_true()
		# the rects are read with "LV 14" on the plate but before flash_level: its scale tween runs on the LV plate for
		# 0.32 s and get_rect() reads the scaled rect at whatever time the next frame samples it (a flake in other lanes'
		# runs of this suite, the review of lane UIHUD)
		hud._lv.text = "LV 14"
		hud._fit_top()
		await _frames(1)
		rects[royale] = _rects(hud)
		assert_bool(hud._lv_plate.scale.is_equal_approx(Vector2.ONE)).is_true()
		hud.flash_level(14)
		hud._fit_top()
		await _frames(1)
		assert_str(hud._lv.text).is_equal("LV 14")
		hud.queue_free()
		await _frames(1)
	# the same boxes under both themes (Garry: the sizes as they are; only the style changes)
	var a: Dictionary = rects[false]
	var b: Dictionary = rects[true]
	assert_int(b.size()).is_equal(a.size())
	for k in a:
		var ra: Rect2 = a[k]
		var rb: Rect2 = b[k]
		assert_bool(ra.position.is_equal_approx(rb.position)).override_failure_message("%s: %s vs %s" % [k, ra, rb]).is_true()
		assert_bool(ra.size.is_equal_approx(rb.size)).override_failure_message("%s: %s vs %s" % [k, ra, rb]).is_true()
	assert_float((a["rail"] as Rect2).size.y).is_equal(HUD.RAIL_H)
	assert_float((a["pause"] as Rect2).size.x).is_equal(HUD.DISC)


func test_a_theme_flip_in_a_run_restyles_the_hud_in_place() -> void:
	_build()
	_royale(false)
	var hud := _hud()
	await _frames(2)
	assert_str(hud.theme_applied()).is_equal("wanted")
	var before := _rects(hud)
	# the pieces that read the theme as they draw are drawn again on the flip (the review's probe: the gold plate and its
	# coin kept the Wanted look until the purse changed its digit count or a modal hid and showed the HUD)
	var draws := {"lv": 0, "timer": 0, "gold": 0, "coin": 0}
	hud._lv_plate.draw.connect(func(): draws["lv"] += 1)
	hud._timer_plate.draw.connect(func(): draws["timer"] += 1)
	hud._gold_plate.draw.connect(func(): draws["gold"] += 1)
	hud._coin.draw.connect(func(): draws["coin"] += 1)
	# the in-run debug panel's button: Settings.set_value, which W and the HUD both hear
	Settings.set_value("ui_theme", "royale")
	await _frames(2)
	assert_bool(W.royale()).is_true()
	assert_str(hud.theme_applied()).is_equal("royale")
	for k in draws.keys():
		assert_int(int(draws[k])).override_failure_message("%s drawn again after the flip to royale: %s" % [k, draws]).is_greater_equal(1)
		draws[k] = 0
	assert_bool(R.is_display(hud._lv.font)).is_true()
	assert_bool(hud._lv.color.is_equal_approx(R.WHITE)).is_true()
	assert_str((hud._pause_btn.box as HardBox).role).is_equal("slate")
	assert_bool(hud._cutout.color.is_equal_approx(HUD.ROYALE_RAIL_BLACK)).is_true()
	for p: WPlate in hud._slots.get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion()):
		assert_object(p.find_child("RoyaleFrame", false, false)).is_not_null()
		if not p.empty and not p.is_evolved_frame():
			assert_str(p.frame_rarity()).is_equal("common")
	var mid := _rects(hud)
	for k in before:
		assert_bool((before[k] as Rect2).is_equal_approx(mid[k])).override_failure_message("%s: %s vs %s" % [k, before[k], mid[k]]).is_true()
	# and back
	Settings.set_value("ui_theme", "wanted")
	await _frames(2)
	assert_bool(W.royale()).is_false()
	assert_str(hud.theme_applied()).is_equal("wanted")
	for k in draws.keys():
		assert_int(int(draws[k])).override_failure_message("%s drawn again after the flip back: %s" % [k, draws]).is_greater_equal(1)
	assert_str(_base_path(hud._lv.font)).is_equal(W.SLAB_PATH)
	assert_bool(hud._lv.color.is_equal_approx(W.INK)).is_true()
	assert_int(hud._lv.stroke).is_equal(0)
	assert_float(hud._lv.line_height).is_equal(0.0)
	assert_str((hud._pause_btn.box as HardBox).role).is_equal("")
	assert_bool((hud._pause_btn.box as HardBox).fill.is_equal_approx(W.BRASS)).is_true()
	assert_bool(hud._cutout.color.is_equal_approx(W.INK)).is_true()
	for p: WPlate in hud._slots.get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion()):
		assert_object(p.find_child("RoyaleFrame", false, false)).is_null()
	assert_bool((hud._slot_nodes["peashooter"] as WPlate).fill.is_equal_approx(W.level_fill(5))).is_true()
	var after := _rects(hud)
	for k in before:
		assert_bool((before[k] as Rect2).is_equal_approx(after[k])).override_failure_message("%s: %s vs %s" % [k, before[k], after[k]]).is_true()
	# a settings change that is neither the theme nor the switch leaves the HUD alone (no row rebuilt)
	var plate_before: WPlate = hud._slot_nodes["boomstick"]
	Settings.set_value("sfx_volume", 0.5)
	await _frames(1)
	assert_object(hud._slot_nodes["boomstick"]).is_same(plate_before)


func test_the_wanted_face_is_kept_where_garry_keeps_it() -> void:
	_build()
	for royale in [false, true]:
		_royale(royale)
		var hud := _hud()
		await _frames(2)
		# the kill counter's number: the Wanted face, ink stroke and shadow, down-right
		var num: WText = hud._kills._num
		assert_str(_base_path(num.font)).is_equal(W.SLAB_PATH)
		assert_bool(num.stroke_color.is_equal_approx(W.INK)).is_true()
		assert_bool(num.shadow_color.is_equal_approx(W.INK)).is_true()
		assert_bool(num.shadow_straight).is_false()
		assert_int(num.stroke).is_equal(4)
		assert_int(num.shadow).is_equal(3)
		assert_int(num.bevel).is_equal(0)
		hud._kills.tick(0.0, 12)
		assert_str(hud._kills.text()).is_equal("12")
		assert_float(hud._kills.row_width()).is_greater(0.0)
		# the boss's name and bar: pass 47's piece under both themes
		assert_str(_base_path(hud._boss_name.font)).is_equal(W.SLAB_PATH)
		assert_bool(hud._boss_name.color.is_equal_approx(W.PAPER)).is_true()
		assert_int(hud._boss_name.stroke).is_equal(5)
		assert_int(hud._boss_name.shadow).is_equal(4)
		assert_bool(hud._boss_name.stroke_color.is_equal_approx(W.INK)).is_true()
		assert_bool(hud._boss_name.shadow_straight).is_false()
		assert_bool(hud._boss_bar.themed).is_false()
		assert_bool((auto_free(WBar.new()) as WBar).themed).is_true()
		assert_bool(hud._boss_bar.fill.is_equal_approx(W.ROCK)).is_true()
		hud.show_boss(Registry.enemy("tumbleweed_king"))
		hud.set_boss_hp(62, 100)
		hud.set_boss_guard(1)
		await _frames(1)
		assert_bool(hud._boss_box.visible).is_true()
		assert_str(hud._boss_bar.text).is_equal("GUARDED")
		assert_bool(hud._boss_bar.text_color.is_equal_approx(W.INK)).is_true()
		hud.set_boss_guard(0)
		hud.hide_boss()
		# the banner's words (the review of lane UIHUD; Garry: "Toasts, banners, hints and TAP TO GO stay as they are"):
		# the Wanted face with no edge, paper for news and ink for an evolution, under both themes
		var bt: WText = hud._banner._text
		assert_str(_base_path(bt.font)).is_equal(W.SLAB_PATH)
		assert_int(bt.stroke).is_equal(0)
		assert_int(bt.shadow).is_equal(0)
		assert_bool(bt.shadow_straight).is_false()
		assert_int(bt.bevel).is_equal(0)
		assert_bool(bt.stroke_color.is_equal_approx(W.INK)).is_true()
		assert_bool(bt.shadow_color.is_equal_approx(W.INK)).is_true()
		hud.banner("BOSS INCOMING")
		assert_str(hud.banner_text()).is_equal("BOSS INCOMING")
		assert_bool(bt.color.is_equal_approx(W.PAPER)).is_true()
		hud.banner("EVOLVED: KILLER SWARM")
		assert_str(hud.banner_text()).is_equal("EVOLVED · KILLER SWARM")
		assert_bool(bt.color.is_equal_approx(W.INK)).is_true()
		assert_str(_base_path(bt.font)).is_equal(W.SLAB_PATH)
		hud._banner.visible = false
		# the hero's bars and the joystick are drawn by the HUD itself with the Wanted colours (untouched code)
		hud.set_hp(70, 100)
		await _frames(1)
		hud.queue_free()
		await _frames(1)


func test_the_power_up_plates_and_the_pointers_under_both_themes() -> void:
	_start()
	Run.debug_clear_items()
	Run.add_weapon(Registry.weapon("boomstick"), 2)
	Run.build_changed.emit()
	for royale in [false, true]:
		_royale(royale)
		var hud := _hud()
		await _frames(2)
		Run.add_timed_effects("rage", "BERSERK", [], 10.0)
		hud._refresh_buffs()
		assert_int(hud._buffs.get_child_count()).is_equal(1)
		var p: Control = hud._buffs.get_child(0)
		assert_str(str(p.get_meta("buff"))).is_equal("rage")
		assert_str(str(p.get("level_text"))).is_equal("10")
		assert_bool(p.custom_minimum_size.is_equal_approx(Vector2(HUD.BUFF_PX, HUD.BUFF_PX))).is_true()
		if royale:
			assert_bool(p is HUD.RoyaleBuffPlate).is_true()
			var rp: HUD.RoyaleBuffPlate = p
			assert_object(rp.tex).is_same(Registry.pickup("rage").icon)
			assert_bool(rp.fill.is_equal_approx(W.SAGE)).is_true()
			var tr := rp.tag_rect()
			assert_float(tr.end.x).is_equal_approx(HUD.BUFF_PX + HUD.RoyaleBuffPlate.TAG_OVER, 0.01)
			assert_float(tr.end.y).is_equal_approx(HUD.BUFF_PX + HUD.RoyaleBuffPlate.TAG_OVER, 0.01)
			assert_float(tr.size.x).is_greater(HUD.RoyaleBuffPlate.TAG_PAD * 2.0)
		else:
			assert_bool(p is WPlate).is_true()
			assert_bool((p as WPlate).fill.is_equal_approx(W.SAGE)).is_true()
			assert_float((p as WPlate).icon_frac).is_equal(0.66)
		# the seconds count down on either plate, and it goes at 0
		Run.held_time += 4.0
		hud._refresh_buffs()
		assert_str(str(hud._buffs.get_child(0).get("level_text"))).is_equal("6")
		Run.held_time += 6.01
		hud._refresh_buffs()
		assert_int(hud._buffs.get_child_count()).is_equal(0)
		Run.tick_timed()
		# a structure's boost keeps its red under Wanted (pass 106) and is a black plate under Royale
		Run.add_timed_effects("structure:war_drum", "WAR DRUM", [], 15.0)
		hud._refresh_buffs()
		var drum: Control = null
		for c in hud._buffs.get_children():
			if str(c.get_meta("buff", "")) == "structure:war_drum":
				drum = c
		if drum != null:
			assert_bool((drum.get("fill") as Color).is_equal_approx(W.ROCK)).is_true()
			assert_bool((drum is HUD.RoyaleBuffPlate) == royale).is_true()
		Run.held_time += 20.0
		hud._refresh_buffs()
		Run.tick_timed()
		# a pointer pinned on the right edge: the kit's piece, placed against the edge by its own size
		hud.test_arrows = [{"pos": Vector2(1080, 548), "color": W.SAGE, "side": 1, "text": "PORTAL 80 m"}]
		hud._tick_arrow()
		assert_int(hud._pointers.size()).is_equal(1)
		var ptr: WPointer = hud._pointers[0]
		assert_bool(ptr.visible).is_true()
		assert_str(ptr.text).is_equal("PORTAL 80 m")
		assert_int(ptr.side).is_equal(1)
		var vw := hud.get_viewport().get_visible_rect().size.x
		assert_float(ptr.position.x).is_equal_approx(vw - ptr.size.x, 0.5)
		assert_float(ptr.position.y + ptr.size.y * 0.5).is_equal_approx(548.0, 0.5)
		hud.test_arrows = []
		hud._tick_arrow()
		assert_bool(ptr.visible).is_false()
		hud.queue_free()
		await _frames(1)


func test_the_mutation_mark_and_the_clock_modes_under_royale() -> void:
	_start()
	Run.debug_clear_items()
	Run.add_weapon(Registry.weapon("orbit_saws"), 2)
	Run.build_changed.emit()
	_royale(true)
	var hud := _hud()
	await _frames(2)
	# the mark: the LV plate stays black, its number in the epic light, MUTATION NEXT white at the rail's end
	Run.mutlvl_due = 1
	Run.mutation_due_changed.emit()
	assert_bool(Run.mutlvl_pending()).is_true()
	assert_bool(hud.mutation_mark_on()).is_true()
	assert_bool(hud._mut_word.visible).is_true()
	assert_bool(hud._mut_word.color.is_equal_approx(R.WHITE)).is_true()
	assert_bool(hud._lv.color.is_equal_approx(HUD.ROYALE_MUT_TEXT)).is_true()
	assert_str((hud._lv_plate.get_theme_stylebox("panel") as HardBox).role).is_equal("plate")
	Run.mutlvl_due = 0
	Run.mutation_due_changed.emit()
	assert_bool(hud.mutation_mark_on()).is_false()
	assert_bool(hud._lv.color.is_equal_approx(R.WHITE)).is_true()
	# the clock's modes: the plate stays black, the digits red while the portal counts down, white otherwise
	hud.test_stage_clock = {"portal_left": 41.3, "endless": false}
	hud.tick(0.0)
	assert_str(hud.clock_mode()).is_equal("portal")
	assert_str(hud.stage_tag_text()).is_equal("ENDLESS IN")
	assert_bool(hud._timer.color.is_equal_approx(HUD.ROYALE_WARN_TEXT)).is_true()
	assert_str((hud._timer_plate.get_theme_stylebox("panel") as HardBox).role).is_equal("plate")
	assert_str((hud._stage_tag.get_theme_stylebox("panel") as HardBox).role).is_equal("plate")
	assert_bool(hud._stage_tag_text.color.is_equal_approx(HUD.ROYALE_WARN_TEXT)).is_true()
	hud.test_stage_clock = {"endless": true, "endless_wave": 3, "endless_seconds": 31.0}
	hud.tick(0.0)
	assert_str(hud.clock_mode()).is_equal("endless")
	assert_str(hud.stage_tag_text()).is_equal("WAVE 3")
	assert_bool(hud._timer.color.is_equal_approx(R.WHITE)).is_true()
	assert_str((hud._timer_plate.get_theme_stylebox("panel") as HardBox).role).is_equal("plate")
	var tag_box: HardBox = hud._stage_tag.get_theme_stylebox("panel")
	assert_str(tag_box.role).is_equal("")
	assert_bool(tag_box.fill.is_equal_approx(R.TAG_RED)).is_true()
	assert_int(tag_box.border).is_equal(R.TAG_EDGE)
	assert_int(tag_box.radius).is_equal(R.RADIUS_TAG)
	assert_bool(hud._stage_tag_text.color.is_equal_approx(R.CREAM)).is_true()
	# the tag hangs under the clock plate, centred (pass 87's rule)
	var tag: Control = hud._stage_tag
	var plate: Control = hud._timer_plate
	assert_float(absf(tag.position.x + tag.size.x * 0.5 - (plate.position.x + plate.size.x * 0.5))).is_less(1.5)
	hud.test_stage_clock = {}
	hud.tick(0.0)
	assert_str(hud.clock_mode()).is_equal("")
	assert_bool(hud._timer.color.is_equal_approx(R.WHITE)).is_true()
	assert_bool(hud._stage_tag.visible).is_false()
	# under Wanted the same modes wear pass 87's boxes (a flip through Settings, which the HUD hears)
	Settings.set_value("ui_theme", "wanted")
	await _frames(1)
	hud.test_stage_clock = {"portal_left": 41.3, "endless": false}
	hud.tick(0.0)
	var rock: HardBox = hud._timer_plate.get_theme_stylebox("panel")
	assert_str(rock.role).is_equal("")
	assert_bool(rock.fill.is_equal_approx(W.ROCK)).is_true()
	assert_bool(hud._timer.color.is_equal_approx(W.PAPER)).is_true()
	assert_bool(hud._stage_tag_text.color.is_equal_approx(W.ROCK)).is_true()
	hud.test_stage_clock = {"endless": true, "endless_wave": 3, "endless_seconds": 31.0}
	hud.tick(0.0)
	var ink: HardBox = hud._timer_plate.get_theme_stylebox("panel")
	assert_bool(ink.fill.is_equal_approx(W.INK)).is_true()
	assert_bool((hud._stage_tag.get_theme_stylebox("panel") as HardBox).fill.is_equal_approx(W.ROCK)).is_true()
	hud.test_stage_clock = {}
	hud.tick(0.0)
	assert_bool(hud._timer.color.is_equal_approx(W.INK)).is_true()
	hud._banner.visible = false


## The kit's own Wanted pins (the review of lane UIHUD; Garry: "Toasts, banners, hints and TAP TO GO stay as they are"):
## toasts, hints, the banner's words and box, TAP TO GO with its line and the kill counter's number wear the Wanted face
## under Royale, exactly as under Wanted.
func test_the_toasts_the_banner_and_tap_to_go_keep_the_wanted_face_under_royale() -> void:
	_build()
	_royale(true)
	var hud := _hud()
	await _frames(2)
	assert_bool(W.royale()).is_true()
	# a toast and a hint: Alfa Slab in the toast's own colour, the ink stroke 2 / shadow 3 down-right, the Wanted line box
	hud._toasts.push("+22 HP", W.TOAST_GREEN)
	hud._toasts.tick(0.0)
	assert_int(hud._toasts._shown.size()).is_equal(1)
	var toast: WText = hud._toasts._shown[0][0]
	assert_str(_base_path(toast.font)).is_equal(W.SLAB_PATH)
	assert_bool(toast.color.is_equal_approx(W.TOAST_GREEN)).is_true()
	assert_int(toast.stroke).is_equal(2)
	assert_int(toast.shadow).is_equal(3)
	assert_bool(toast.stroke_color.is_equal_approx(W.INK)).is_true()
	assert_bool(toast.shadow_straight).is_false()
	assert_float(toast.size.y).is_equal(W.normal_height(W.wanted_slab(), WToasts.PX))
	hud._toasts.hint("Move with your thumb")
	assert_str(_base_path(hud._toasts._hint.font)).is_equal(W.SLAB_PATH)
	assert_bool(hud._toasts._hint.color.is_equal_approx(W.PAPER)).is_true()
	# the banner: the Wanted face, its box drawn the Wanted way (HardBox.themed false; a fresh box is themed)
	hud.banner("BOSS INCOMING")
	var bt: WText = hud._banner._text
	assert_str(_base_path(bt.font)).is_equal(W.SLAB_PATH)
	assert_bool(bt.color.is_equal_approx(W.PAPER)).is_true()
	assert_int(bt.stroke).is_equal(0)
	assert_bool((hud._banner.get_theme_stylebox("panel") as HardBox).themed).is_false()
	assert_bool((hud._banner.get_theme_stylebox("panel") as HardBox).fill.is_equal_approx(W.INK)).is_true()
	hud.endless_banner()
	assert_bool((hud._banner.get_theme_stylebox("panel") as HardBox).themed).is_false()
	assert_bool((hud._banner.get_theme_stylebox("panel") as HardBox).fill.is_equal_approx(W.ROCK)).is_true()
	assert_bool(W.box().themed).is_true()
	hud._banner.visible = false
	# TAP TO GO and its line
	var gate: ResumeGate = auto_free(ResumeGate.new())
	gate.hud = hud
	add_child(gate)
	await _frames(1)
	assert_str(_base_path(gate._go.font)).is_equal(W.SLAB_PATH)
	assert_bool(gate._go.color.is_equal_approx(W.PAPER)).is_true()
	assert_int(gate._go.stroke).is_equal(2)
	assert_int(gate._go.shadow).is_equal(5)
	assert_bool(gate._go.shadow_straight).is_false()
	assert_str(_base_path(gate._sub.font)).is_equal(W.SERIF_ITALIC_PATH)
	assert_bool(gate._sub.color.is_equal_approx(W.PAPER)).is_true()
	# the kill counter's number from the kit itself
	var kc: WKillCount = auto_free(WKillCount.new())
	assert_str(_base_path(kc._num.font)).is_equal(W.SLAB_PATH)
	assert_bool(kc._num.color.is_equal_approx(W.PAPER)).is_true()
	assert_int(kc._num.stroke).is_equal(4)
