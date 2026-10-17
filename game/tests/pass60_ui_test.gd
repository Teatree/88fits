extends GdUnitTestSuite

## Pass 60, lane UI (Garry's list): the travelling shop's prices (half a stage's gold, by kind, rarity and the levels
## held: StructureShop.price_of) and its YOU HOLD tray (a flow of plates that wraps under the header, the cards under
## its real height, at any camera-cutout inset); the play-data words without their maker (WConsent.body_text,
## Analytics.settings_line); the survey's answer box taking focus from a finger (the phone's keyboard follows focus) and
## the card lifting so its foot clears the keyboard (WSurvey.lift_for); the signposts drawn at their foot's depth
## (core/shaders/sign_depth.gdshader on every post and arm, one material set per sign), so the hero sorts with a sign
## like with any painting; and Game's one-screen rule (_request_modal / _modal_done: one screen at a time, death wins,
## level-ups banked while he is down and offered after the revive, pause-respecting blasts).

const SIGNS := preload("res://core/systems/SignField.gd")
const SURVEY := preload("res://ui/wanted/WSurvey.gd")
const CONSENT := preload("res://ui/wanted/WConsent.gd")
const ANALYTICS := preload("res://core/autoload/Analytics.gd")
const KEY := "phc_testtesttesttesttest"
const DIR := "user://test_saves/p60_ui"
const IDS := ["teleport", "uber_magnet", "gold_bank", "hooded_figure", "healing_well", "loot_cache", "shop", "war_drum", "beacon"]
const FLAT_MAP := """extends MapBase
var flats_radius := 16.0
"""
const FAKE_GAME := """extends Node
var structures = null
var player = null
var paused := false
"""
const FAKE_SM := """extends Node3D
var items: Array = []
"""
const SURVEY_OPEN := {"id": "p60", "name": "P60", "questions": [
	{"id": "q1", "type": "open", "question": "Anything you would change?", "description": "", "optional": true, "choices": [], "scale": 5, "lower": "", "upper": ""}]}

var _keep: Dictionary = {}


func before_test() -> void:
	_keep = {"debug_mode": Settings.debug_mode, "top_inset": Settings.top_inset}
	Settings.debug_mode = false
	Settings.top_inset = -1
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Run.arena = false


func after_test() -> void:
	get_tree().paused = false
	Settings.debug_mode = bool(_keep["debug_mode"])
	Settings.top_inset = int(_keep["top_inset"])
	Run.forced_map_seed = 0
	Run.arena = false
	Run.end()


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _frames(n: int) -> void:
	for k in range(n):
		await get_tree().process_frame


## A phone's canvas to lay a screen out on: a 1080 x 1920 viewport of its own (so the kit's measures and the screen's
## own `get_viewport_rect` read the phone's size, whatever window the runner has) with a full-size Control in it.
func _host() -> Control:
	var sub := SubViewport.new()
	sub.size = Vector2i(1080, 1920)
	sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(sub)
	auto_free(sub)
	var h := Control.new()
	h.size = Vector2(1080, 1920)
	sub.add_child(h)
	return h


## A finger laid down or lifted at `at` in `host`'s viewport, as the phone sends it (no mouse emulation in this game).
func _touch(host: Control, at: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = at
	ev.pressed = pressed
	host.get_viewport().push_input(ev, true)


func _card(type: String, def: ContentDef, from: int = 0, to: int = 1) -> Dictionary:
	return {"type": type, "id": def.id, "def": def, "level_from": from, "level_to": to, "is_new": from == 0, "weight": 1.0}


func _weapon_def(rarity: String, evolution: bool = false) -> WeaponDef:
	var d := WeaponDef.new()
	d.id = "p60_" + rarity
	d.rarity = rarity
	d.is_evolution = evolution
	return d


func _passive_def(rarity: String, line: bool) -> PassiveDef:
	var d := PassiveDef.new()
	d.id = "p60_p_" + rarity
	d.rarity = rarity
	d.line = line
	return d


# ---------------------------------------------------------------- 1. the shop's prices

func test_a_common_weapon_costs_half_a_stages_gold_by_stage() -> void:
	var c := _card("weapon", _weapon_def("common"))
	assert_array(StructureShop.PRICE_BASE_BY_STAGE).is_equal([300, 500, 700])
	# 300 / 500 / 700 x 1.0 (a weapon) x 0.8 (common)
	assert_int(StructureShop.price_of(c, 1)).is_equal(240)
	assert_int(StructureShop.price_of(c, 2)).is_equal(400)
	assert_int(StructureShop.price_of(c, 3)).is_equal(560)
	# the run's own stage (Run.stage counts from 0); endless and anything past the third stay on the third
	Run.stage = 0
	assert_int(StructureShop.price_of(c)).is_equal(240)
	Run.stage = 2
	assert_int(StructureShop.price_of(c)).is_equal(560)
	assert_int(StructureShop.price_stage(1)).is_equal(1)
	assert_int(StructureShop.price_stage(9)).is_equal(3)


func test_a_rare_line_and_an_epic_passive_item_by_kind_and_rarity() -> void:
	var line := _card("passive", _passive_def("rare", true))
	var item := _card("passive", _passive_def("epic", false))
	# a line is 0.85 of the base, rare x 1.0
	assert_int(StructureShop.price_of(line, 1)).is_equal(255)
	assert_int(StructureShop.price_of(line, 2)).is_equal(425)
	assert_int(StructureShop.price_of(line, 3)).is_equal(595)
	# a passive item 0.7, epic x 1.2, rounded to 5 (252 -> 250, 588 -> 590)
	assert_int(StructureShop.price_of(item, 1)).is_equal(250)
	assert_int(StructureShop.price_of(item, 2)).is_equal(420)
	assert_int(StructureShop.price_of(item, 3)).is_equal(590)


func test_levels_held_raise_the_price_by_twelve_percent_each() -> void:
	var w := _weapon_def("common")
	assert_float(StructureShop.LEVEL_STEP).is_equal_approx(0.12, 0.0001)
	assert_int(StructureShop.price_of(_card("weapon", w, 0, 1), 1)).is_equal(240)
	assert_int(StructureShop.price_of(_card("weapon", w, 1, 2), 1)).is_equal(270)   # 268.8
	assert_int(StructureShop.price_of(_card("weapon", w, 2, 3), 1)).is_equal(300)   # 297.6
	assert_int(StructureShop.price_of(_card("passive", _passive_def("rare", true), 2, 3), 2)).is_equal(525)    # 425 x 1.24 = 527
	assert_int(StructureShop.price_of(_card("passive", _passive_def("epic", false), 2, 3), 3)).is_equal(730)   # 588 x 1.24 = 729.1


func test_every_rarity_is_priced_and_climbs() -> void:
	var prices: Array = []
	for r in ContentDef.RARITIES:
		prices.append(StructureShop.price_of(_card("weapon", _weapon_def(r)), 1))
	assert_array(prices).is_equal([240, 270, 300, 360, 420])
	assert_int(StructureShop.RARITY_MULT.size()).is_equal(ContentDef.RARITIES.size())
	# an unknown rarity reads as common
	assert_int(StructureShop.price_of(_card("weapon", _weapon_def("mythic")), 1)).is_equal(240)
	# a perk is priced as a passive item
	assert_float(StructureShop.KIND_MULT["perk"]).is_equal_approx(StructureShop.KIND_MULT["passive"], 0.0001)


func test_an_evolution_costs_more_and_the_table_stays_over_the_floor() -> void:
	assert_int(StructureShop.price_of(_card("evolution", _weapon_def("common", true)), 1)).is_equal(335)   # 240 x 1.4 = 336
	assert_int(StructureShop.price_of({"def": _weapon_def("common"), "type": "evolution", "level_from": 0}, 1)).is_equal(335)
	assert_int(StructureShop.PRICE_MIN).is_equal(40)
	assert_int(StructureShop.PRICE_ROUND).is_equal(5)
	# the cheapest thing in the table, a common passive item on stage 1 (300 x 0.7 x 0.8 = 168 -> 170), is over the floor
	assert_int(StructureShop.price_of(_card("passive", _passive_def("common", false)), 1)).is_equal(170)
	assert_int(StructureShop.price_of(_card("passive", _passive_def("common", false)), 1)).is_greater(StructureShop.PRICE_MIN)


# ---------------------------------------------------------------- 2. the YOU HOLD tray

## A late build: five weapons, five lines and twelve passive items (22), through Run.debug_set_item.
func _long_build() -> int:
	Run.debug_clear_items()
	for w in ["hornet_nest", "turret_buddy", "big_mouth", "molotov", "boomstick"]:
		Run.debug_set_item("weapon", w, 3)
	var n := 0
	for p: PassiveDef in Registry.sorted_lines():
		if n >= 5:
			break
		if Run.debug_set_item("passive", p.id, 2) > 0:
			n += 1
	n = 0
	for p: PassiveDef in Registry.sorted_passives_only():
		if n >= 12:
			break
		if Run.debug_set_item("passive", p.id, 1) > 0:
			n += 1
	return StructureShop.held_items().size()


## The shop opened on a phone's canvas with the cutout inset `inset` (-1 = none), three wares on the table, laid out and
## settled (the header drops in over 0.25 s; the fit reads the laid-out heights a frame after the open).
func _shop(inset: int) -> StructureShop:
	Settings.top_inset = inset
	var host := _host()
	var shop := StructureShop.new()
	host.add_child(shop)
	var offer := [_card("weapon", Registry.weapon("hornet_nest"), 3, 4), _card("passive", Registry.passive("clover"), 0, 1),
		_card("passive", Registry.passive("desperado"), 0, 1)]
	shop.open(offer)
	await get_tree().create_timer(0.35).timeout
	await _frames(1)
	return shop


## The foot the cards may reach: CARDS_GAP over the LEAVE button (90 px up, 108 tall) at 1080 x 1920.
func _cards_floor() -> float:
	return 1920.0 - 90.0 - 108.0 - StructureShop.CARDS_GAP


func test_the_tray_wraps_a_long_build_above_the_cards() -> void:
	assert_int(_long_build()).is_equal(22)
	var shop := await _shop(-1)
	# 22 plates at 60 px in a 984 px flow: two rows (14 and 8), nothing past the screen's edge, the cards under the tray
	# and over LEAVE as they are (no step down, no shrink)
	assert_float(StructureShop.tray_px(22)).is_equal(StructureShop.TRAY_PX_SMALL)
	assert_int(StructureShop.tray_rows_for(22, 60.0, 984.0)).is_equal(2)
	assert_int(StructureShop.tray_rows_for(22, 76.0, 984.0)).is_equal(2)
	assert_int(StructureShop.tray_rows_for(22, 48.0, 984.0)).is_equal(2)
	assert_int(StructureShop.tray_rows_for(0, 60.0, 984.0)).is_equal(0)
	assert_float(shop.plate_px()).is_equal(StructureShop.TRAY_PX_SMALL)
	assert_float(shop.cards_scale()).is_equal_approx(1.0, 0.001)
	assert_int(shop.tray_rows()).is_equal(2)
	assert_float(shop.tray_right()).is_less_equal(1080.0)
	assert_float(shop.cards_top()).is_greater_equal(shop.tray_bottom())
	assert_float(shop.cards_bottom()).is_less_equal(_cards_floor() + 0.5)
	# the YOU HOLD line on a row of its own, over the plates, which are all there
	var label: Control = shop.find_child("HoldLabel", true, false)
	var flow: Control = shop.find_child("HoldFlow", true, false)
	assert_object(label).is_not_null()
	assert_bool(label.visible).is_true()
	assert_float(label.global_position.y + label.size.y).is_less_equal(flow.global_position.y + 0.5)
	assert_int(flow.get_child_count()).is_equal(22)
	# the tray starts under the header's foot
	var tray: Control = shop.find_child("Tray", true, false)
	var header_foot: float = shop.header.offset_top + shop.header.get_combined_minimum_size().y
	assert_float(tray.global_position.y).is_greater_equal(header_foot - 0.5)


func test_the_tray_at_a_cutout_inset_of_130_still_fits_above_the_cards() -> void:
	assert_int(_long_build()).is_equal(22)
	var shop := await _shop(130)
	assert_int(shop.tray_rows()).is_equal(2)
	assert_float(shop.tray_right()).is_less_equal(1080.0)
	assert_float(shop.cards_top()).is_greater_equal(shop.tray_bottom())
	# the header moved down with the inset and everything followed it
	assert_float(shop.header.offset_top).is_equal_approx(110.0 + 130.0, 0.5)
	var tray: Control = shop.find_child("Tray", true, false)
	var header_foot: float = shop.header.offset_top + shop.header.get_combined_minimum_size().y
	assert_float(tray.global_position.y).is_greater_equal(header_foot - 0.5)
	assert_float(tray.global_position.y).is_less_equal(header_foot + StructureShop.BODY_GAP + 0.5)
	# the stack would have passed LEAVE (three cards of about 300 px and the cutout): the cards' gap squeezed, the
	# plates stepped down to 48 px, and the list shrank a little; the cards still end over the LEAVE button
	var cards: Control = shop.find_child("Cards", true, false)
	assert_int(cards.get_child_count()).is_equal(3)
	assert_float(shop.plate_px()).is_equal(StructureShop.TRAY_PX_MIN)
	assert_int(cards.get_theme_constant("separation")).is_equal(int(StructureShop.CARD_GAP_MIN))
	assert_float(shop.cards_scale()).is_between(0.9, 1.0)
	assert_float(shop.cards_bottom()).is_less_equal(_cards_floor() + 0.5)
	assert_float(shop.cards_bottom()).is_less_equal(1920.0 - 90.0 - 108.0)


func test_a_short_build_sits_in_one_row_of_the_handoffs_76_px() -> void:
	Run.debug_clear_items()
	for w in ["hornet_nest", "turret_buddy", "big_mouth"]:
		Run.debug_set_item("weapon", w, 3)
	Run.debug_set_item("passive", "magnet", 2)
	Run.debug_set_item("passive", "clover", 2)
	assert_int(StructureShop.held_items().size()).is_equal(5)
	assert_float(StructureShop.tray_px(5)).is_equal(StructureShop.TRAY_PX)
	assert_float(StructureShop.tray_px(StructureShop.TRAY_SMALL_FROM - 1)).is_equal(StructureShop.TRAY_PX)
	assert_float(StructureShop.tray_px(StructureShop.TRAY_SMALL_FROM)).is_equal(StructureShop.TRAY_PX_SMALL)
	var shop := await _shop(-1)
	assert_int(shop.tray_rows()).is_equal(1)
	assert_float(shop.plate_px()).is_equal(StructureShop.TRAY_PX)
	assert_float(shop.cards_scale()).is_equal_approx(1.0, 0.001)
	assert_float(shop.cards_top()).is_greater_equal(shop.tray_bottom())
	assert_float(shop.cards_bottom()).is_less_equal(_cards_floor() + 0.5)
	# nothing held: no tray, the cards from the body's top
	Run.debug_clear_items()
	var bare := await _shop(-1)
	var tray: Control = bare.find_child("Tray", true, false)
	assert_bool(tray.visible).is_false()
	assert_float(bare.cards_top()).is_equal_approx(bare.tray_bottom(), 0.5)


# ---------------------------------------------------------------- 3. the play-data words

func test_the_play_data_card_names_no_maker_and_keeps_the_players_name() -> void:
	var body := CONSENT.body_text("Dusty Coyote 41")
	assert_str(body).contains("\"Dusty Coyote 41\"")
	assert_str(body.to_lower()).not_contains("maker")
	assert_str(body.to_lower()).not_contains("garry")
	assert_str(body).contains("Settings")
	# the card lays the words out whole at the phone's width
	Save.data["consent"] = ""
	var host := _host()
	var card: Control = CONSENT.open(host)
	await _frames(3)
	var b: Control = card.find_child("Body", true, false)
	assert_object(b).is_not_null()
	assert_str(str(b.get("text"))).is_equal(CONSENT.body_text(Save.player_name()))
	var panel: Control = card.get("card")
	assert_float(panel.size.x).is_equal_approx(1080.0 - 2.0 * 60.0, 0.5)
	assert_float(panel.size.y).is_less(1920.0 * 0.6)
	assert_object(card.find_child("Accept", true, false)).is_not_null()
	assert_object(card.find_child("Decline", true, false)).is_not_null()


func test_the_settings_line_names_no_maker_and_keeps_the_player_name() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var a: Node = auto_free(ANALYTICS.new())
	a.test_mode = true
	a.queue_path = DIR.path_join("analytics_queue.json")
	a.set_config({"host": "https://eu.i.posthog.com/", "key": KEY, "enabled": true})
	var line: String = a.settings_line()
	assert_str(line).contains("player name")
	assert_str(line).contains("No account, no location")
	assert_str(line.to_lower()).not_contains("maker")
	var off: Node = auto_free(ANALYTICS.new())
	off.test_mode = true
	off.queue_path = DIR.path_join("analytics_queue_off.json")
	off.set_config({"host": "https://eu.i.posthog.com/", "key": KEY, "enabled": false})
	assert_str(off.settings_line()).contains("Nothing is sent")


# ---------------------------------------------------------------- 4. the survey's text box

func _survey() -> Dictionary:
	var host := _host()
	var card: Control = SURVEY.open(host, SURVEY_OPEN.duplicate(true))
	await _frames(3)
	var answer: TextEdit = card.find_child("Answer", true, false)
	return {"host": host, "card": card, "answer": answer}


func test_a_finger_on_the_answer_box_focuses_it_and_one_outside_lets_go() -> void:
	var s := await _survey()
	var host: Control = s["host"]
	var card: Control = s["card"]
	var answer: TextEdit = s["answer"]
	assert_object(answer).is_not_null()
	assert_bool(answer.has_focus()).is_false()
	var at := answer.get_global_rect().get_center()
	_touch(host, at, true)
	await _frames(1)
	_touch(host, at, false)
	await _frames(1)
	assert_bool(answer.has_focus()).is_true()
	assert_bool(bool(card.call("answer_focused"))).is_true()
	# the focused box wears the brass ring
	var focus := answer.get_theme_stylebox("focus") as HardBox
	assert_object(focus).is_not_null()
	assert_bool(focus.border_color.is_equal_approx(W.BRASS)).is_true()
	# a finger on the dim outside the box lets the focus go (the phone's keyboard with it)
	var outside := Vector2(540.0, 40.0)
	assert_bool(answer.get_global_rect().has_point(outside)).is_false()
	_touch(host, outside, true)
	await _frames(1)
	_touch(host, outside, false)
	await _frames(1)
	assert_bool(answer.has_focus()).is_false()


func test_the_card_lifts_so_its_foot_clears_a_phones_keyboard() -> void:
	var s := await _survey()
	var card: Control = s["card"]
	var panel: Control = card.get("card")
	var vh: float = card.get_viewport_rect().size.y
	assert_float(vh).is_equal_approx(1920.0, 0.5)
	var base: float = card.get("_base_top")
	assert_float(base).is_equal_approx(SURVEY.CARD_TOP + W.safe_top(), 0.5)
	var h := maxf(panel.size.y, panel.get_combined_minimum_size().y)
	var foot := base + h + SURVEY.KEYBOARD_GAP
	assert_float(foot).is_less(vh)
	# no keyboard: no lift
	assert_float(card.call("lift_for", 0.0)).is_equal(0.0)
	# a keyboard whose top is 100 px over the card's foot: the card rises those 100 px, its foot KEYBOARD_GAP clear
	var kb := vh - foot + 100.0
	var lift: float = card.call("lift_for", kb)
	assert_float(lift).is_equal_approx(100.0, 0.5)
	assert_float(base - lift + h + SURVEY.KEYBOARD_GAP).is_equal_approx(vh - kb, 0.5)
	# never past the cutout: a keyboard as tall as the screen lifts it to LIFT_TOP_MIN under the cutout, no further
	var cap: float = card.call("lift_for", vh)
	assert_float(cap).is_equal_approx(base - (W.safe_top() + SURVEY.LIFT_TOP_MIN), 0.5)
	# on the PC (and headless) there is no keyboard to measure
	assert_float(card.call("keyboard_canvas_height")).is_equal(0.0)
	assert_float(card.call("keyboard_lift")).is_equal(0.0)
	# a lift applied moves the card's top up by it, and back (the poll held, so it does not take it back at once)
	card.set_process(false)
	card.call("_set_lift", 80.0)
	await get_tree().create_timer(SURVEY.LIFT_SECONDS + 0.15).timeout
	assert_float(panel.offset_top).is_equal_approx(base - 80.0, 0.5)
	card.call("_set_lift", 0.0)
	await get_tree().create_timer(SURVEY.LIFT_SECONDS + 0.15).timeout
	assert_float(panel.offset_top).is_equal_approx(base, 0.5)


# ---------------------------------------------------------------- 5. the signposts' depth

## A flat map and a game holding the nine structures on a ring (pass54_world_test's world), signs by `ms`.
func _world(ms: int = 54) -> Dictionary:
	Run.map_seed = ms
	var map: Node3D = auto_free(Node3D.new())
	map.set_script(_script(FLAT_MAP))
	add_child(map)
	var game: Node = auto_free(Node.new())
	game.set_script(_script(FAKE_GAME))
	add_child(game)
	var sm: Node3D = Node3D.new()
	sm.set_script(_script(FAKE_SM))
	game.add_child(sm)
	game.structures = sm
	for k in IDS.size():
		var s := StructureManager.Structure.new()
		s.def = Registry.structure(IDS[k])
		sm.add_child(s)
		var a := TAU * float(k) / float(IDS.size()) + 0.3
		var r := 30.0 + 8.0 * float(k % 3)
		s.position = Vector3(cos(a) * r, 0.0, sin(a) * r)
		sm.items.append(s)
	return {"map": map, "game": game, "sm": sm}


func _signs(w: Dictionary) -> Node3D:
	var f: Node3D = auto_free(SIGNS.new())
	add_child(f)
	f.setup(w["game"], w["map"])
	return f


func test_every_post_and_arm_wears_the_depth_material_at_its_own_foot_and_casts_no_shadow() -> void:
	var w := _world()
	var f := _signs(w)
	var spots: PackedVector3Array = f.get("spots")
	assert_int(spots.size()).is_greater(0)
	for k in spots.size():
		var stand: Node3D = f.get_node("Sign%d" % k)
		var n := 0
		for mi in stand.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			assert_int(int(m.cast_shadow)).is_equal(int(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF))
			for i in m.mesh.get_surface_count():
				var mat := m.get_surface_override_material(i)
				assert_bool(SIGNS.depth_material(mat)).override_failure_message("Sign%d %s surface %d" % [k, m.name, i]).is_true()
				var foot: Vector3 = (mat as ShaderMaterial).get_shader_parameter("foot")
				assert_bool(foot.is_equal_approx(spots[k])).override_failure_message("Sign%d foot %s != %s" % [k, str(foot), str(spots[k])]).is_true()
				n += 1
		# a post and at least one arm
		assert_int(n).is_greater_equal(2)


func test_each_sign_has_its_own_materials_and_the_shader_moves_the_depth_not_the_picture() -> void:
	var w := _world()
	var f := _signs(w)
	var spots: PackedVector3Array = f.get("spots")
	assert_int(spots.size()).is_greater_equal(2)
	var a: MeshInstance3D = f.get_node("Sign0").find_children("*", "MeshInstance3D", true, false)[0]
	var b: MeshInstance3D = f.get_node("Sign1").find_children("*", "MeshInstance3D", true, false)[0]
	var ma := a.get_surface_override_material(0) as ShaderMaterial
	var mb := b.get_surface_override_material(0) as ShaderMaterial
	assert_object(ma).is_not_same(mb)
	assert_bool((ma.get_shader_parameter("foot") as Vector3).is_equal_approx(mb.get_shader_parameter("foot") as Vector3)).is_false()
	# within one sign the arms share one wood material (the template copied once per sign and surface)
	var arms: Array = f.get("arms")
	var mine: Array = arms.filter(func(r: Dictionary) -> bool: return int(r["sign"]) == 0)
	if mine.size() >= 2:
		var w0 := _wood(mine[0]["node"])
		var w1 := _wood(mine[1]["node"])
		assert_object(w0).is_same(w1)
	# the colours are the templates': a spent arm pales
	var tpl: Dictionary = f.get("_mats")
	var wood: Color = (tpl["wood"] as ShaderMaterial).get_shader_parameter("albedo")
	var spent: Color = (tpl["wood_spent"] as ShaderMaterial).get_shader_parameter("albedo")
	assert_bool(spent.is_equal_approx(SIGNS.WOOD_SPENT)).is_true()
	assert_bool(wood.is_equal_approx(spent)).is_false()
	# the shader: the engine's transform skipped, the depth taken from the sign's foot, no shadows looked up
	var src := FileAccess.get_file_as_string(SIGNS.DEPTH_SHADER)
	assert_str(src).contains("skip_vertex_transform")
	assert_str(src).contains("shadows_disabled")
	assert_str(src).contains("uniform vec3 foot")
	assert_str(src).contains("VIEW_MATRIX * vec4(foot, 1.0)")
	assert_str(src).contains("view.xy * (z1 / z0)")


func _wood(node: MeshInstance3D) -> Material:
	for i in node.mesh.get_surface_count():
		if SIGNS.surface_key(node.mesh, i) == "wood":
			return node.get_surface_override_material(i)
	return null


# ---------------------------------------------------------------- 6. one screen at a time

## A real Game (the scene) on a tool's launch file: the Drifter with a Boomstick, the instant start, no recorder.
func _game() -> Game:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "boomstick", "level": 2, "character": "drifter", "map": "red_canyon", "map_seed": 5, "analytics": false}))
	f.close()
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	await get_tree().create_timer(0.5).timeout
	g.player.god = false
	return g


func test_death_wins_a_level_up_that_comes_while_he_is_down_is_banked_and_comes_after_the_revive() -> void:
	var g := await _game()
	g.player._die()
	assert_bool(g.player.dead).is_true()
	# a gem lands on the corpse: the level-up is banked, nothing opens, the run goes on for the fall
	Run.add_xp(Run.xp_to_next())
	await _frames(1)
	assert_bool(g.cards.visible).is_false()
	assert_int(g._pending_levels).is_equal(1)
	assert_array(g.modal_queue_kinds()).is_equal([Game.Modal.CARDS])
	assert_array(g.visible_modals()).is_empty()
	assert_bool(g.paused).is_false()
	# Down! after the fall, alone
	await get_tree().create_timer(1.4).timeout
	assert_array(g.visible_modals()).is_equal(["revive"])
	assert_int(g.current_modal()).is_equal(Game.Modal.REVIVE)
	assert_bool(g.paused).is_true()
	assert_bool(g.cards.visible).is_false()
	# up again: the banked level comes once his blast has read
	g.revive_screen._decide("debug")
	await _frames(1)
	assert_bool(g.player.dead).is_false()
	assert_bool(g.cards.visible).is_false()
	assert_bool(g.paused).is_false()
	await get_tree().create_timer(g.REVIVE_BEAT + 0.3).timeout
	assert_array(g.visible_modals()).is_equal(["cards"])
	assert_int(g._pending_levels).is_equal(0)
	assert_bool(g.paused).is_true()
	g.cards.visible = false
	g.modal_reset()
	g.set_paused(false)


func test_a_blast_scheduled_before_the_cards_waits_until_they_close() -> void:
	var g := await _game()
	g._pending_levels += 1
	assert_bool(g._show_next_level_cards()).is_true()
	assert_array(g.visible_modals()).is_equal(["cards"])
	assert_bool(g.paused).is_true()
	var hp0: float = g.player.hp
	g.player.invuln = 0.0
	g.elite_explosion(g.player.global_position, 3.0, 20.0, 0.3)
	await get_tree().create_timer(0.7).timeout
	# behind the cards the clock stood still: not a scratch
	assert_float(g.player.hp).is_equal(hp0)
	assert_bool(g.cards.visible).is_true()
	# the pick closes the cards and the run goes on through the gate; the blast lands once the clock runs again
	g.cards.visible = false
	g._on_card_chosen({"skipped": true})
	assert_bool(g.resume_gate.visible).is_true()
	g.resume_gate.tap()
	assert_bool(g.paused).is_false()
	g.player.invuln = 0.0
	await get_tree().create_timer(0.6).timeout
	assert_float(g.player.hp).is_less(hp0)


func test_a_level_up_behind_the_down_screen_waits_for_the_decision() -> void:
	var g := await _game()
	g.player._die()
	await get_tree().create_timer(1.4).timeout
	assert_array(g.visible_modals()).is_equal(["revive"])
	Run.add_xp(Run.xp_to_next())
	await _frames(1)
	assert_bool(g.cards.visible).is_false()
	assert_array(g.modal_queue_kinds()).is_equal([Game.Modal.CARDS])
	assert_array(g.visible_modals()).is_equal(["revive"])
	g.revive_screen._decide("ad")
	await _frames(1)
	assert_bool(g.player.dead).is_false()
	await get_tree().create_timer(g.REVIVE_BEAT + 0.3).timeout
	assert_array(g.visible_modals()).is_equal(["cards"])
	assert_array(g.modal_queue_kinds()).is_empty()
	g.cards.visible = false
	g.modal_reset()
	g.set_paused(false)


func test_the_portal_and_a_chest_open_one_at_a_time() -> void:
	var g := await _game()
	# pass 87 (lane SGAME, re-pinned): the portal asks only while it is open (the director's portal phase, after the boss)
	g.director.phase = WaveDirector.Phase.PORTAL
	g._on_portal_entered()
	g.open_chest(g.player.global_position + Vector3(1, 0, 0))
	await _frames(1)
	assert_array(g.visible_modals()).is_equal(["portal"])
	assert_array(g.modal_queue_kinds()).is_equal([Game.Modal.CHEST])
	assert_bool(g.chest_screen.visible).is_false()
	# NOT YET: the dialog goes, the chest comes after a beat, the run still paused in between
	g._on_portal_declined()
	assert_bool(g.portal_dialog.visible).is_false()
	assert_bool(g.paused).is_true()
	await get_tree().create_timer(g.MODAL_BEAT + 0.3).timeout
	assert_array(g.visible_modals()).is_equal(["chest"])
	assert_array(g.modal_queue_kinds()).is_empty()
	g.chest_screen.visible = false
	g.modal_reset()
	g.set_paused(false)


func test_a_boss_chest_goes_before_an_ordinary_one_that_fell_beside_it() -> void:
	var g := await _game()
	var at := g.player.global_position
	g.open_chest(at, false)
	assert_array(g.visible_modals()).is_equal(["chest"])
	g.open_chest(at + Vector3(1, 0, 0), false)
	g.open_chest(at + Vector3(2, 0, 0), true)
	assert_array(g.modal_queue_kinds()).is_equal([Game.Modal.CHEST, Game.Modal.CHEST])
	assert_int(int(g._modal_queue[0]["priority"])).is_equal(int(Game.MODAL_PRIORITY[Game.Modal.CHEST]) + Game.BOSS_CHEST_BUMP)
	assert_int(int(g._modal_queue[1]["priority"])).is_equal(int(Game.MODAL_PRIORITY[Game.Modal.CHEST]))
	# the reel up closes: the next follows after a beat, the plain one still waiting behind it
	g.chest_screen.visible = false
	g._on_chest_closed(true)
	await get_tree().create_timer(g.MODAL_BEAT + 0.3).timeout
	assert_array(g.visible_modals()).is_equal(["chest"])
	assert_array(g.modal_queue_kinds()).is_equal([Game.Modal.CHEST])
	g.chest_screen.visible = false
	g.modal_reset()
	g.set_paused(false)


func test_the_shop_takes_its_turn_and_a_level_up_behind_it_waits() -> void:
	var g := await _game()
	var def: StructureDef = Registry.structure("shop")
	assert_object(def).is_not_null()
	g.use_structure(def, g.player.global_position)
	await _frames(1)
	assert_array(g.visible_modals()).is_equal(["shop"])
	assert_int(g.current_modal()).is_equal(Game.Modal.SHOP)
	assert_bool(g.paused).is_true()
	Run.add_xp(Run.xp_to_next())
	assert_bool(g.cards.visible).is_false()
	assert_array(g.modal_queue_kinds()).is_equal([Game.Modal.CARDS])
	# LEAVE: the shop hands the turn on, the cards come after a beat
	g.structure_shop._finish(false)
	assert_int(g.current_modal()).is_equal(Game.Modal.NONE)
	await get_tree().create_timer(g.MODAL_BEAT + 0.3).timeout
	assert_array(g.visible_modals()).is_equal(["cards"])
	g.cards.visible = false
	g.modal_reset()
	g.set_paused(false)


func test_the_watch_names_the_screens_up_and_the_rule_is_written_down() -> void:
	var g := await _game()
	assert_array(g.visible_modals()).is_empty()
	g.cards.visible = true
	g.chest_screen.visible = true
	assert_array(g.visible_modals()).is_equal(["cards", "chest"])
	g.cards.visible = false
	g.chest_screen.visible = false
	# a tool's hand-close forgets the turn and the queue
	g._pending_levels += 1
	assert_bool(g._show_next_level_cards()).is_true()
	assert_int(g.current_modal()).is_equal(Game.Modal.CARDS)
	g.cards.visible = false
	g.modal_reset()
	assert_int(g.current_modal()).is_equal(Game.Modal.NONE)
	assert_array(g.modal_queue_kinds()).is_empty()
	g.set_paused(false)
	# the rule stands at the arbiter for the next pass, and every timer that can land a hit waits with the pause
	var src := FileAccess.get_file_as_string("res://game/Game.gd")
	assert_str(src).contains("THE RULE (pass 60")
	assert_str(src).contains("one screen at a time, and death wins")
	assert_str(src).contains("create_timer(delay, false)")
	assert_str(src).contains("create_timer(1.2, false)")
	assert_str(src).not_contains("_chest_queue")
	assert_str(src).not_contains("_path_pending")


## A request whose opener has nothing to show (a path slot due with no pick open: 7-8 a stage) leaves the run
## untouched: not paused for a call, no gate, no blink (pass 60, the review: the pre-pause had dropped the thumb).
func test_an_opener_with_nothing_to_show_never_pauses_the_running_game() -> void:
	var g := await _game()
	assert_bool(g.paused).is_false()
	var asked: Array = []
	g._request_modal(Game.Modal.PATH, func() -> bool:
		asked.append("path")
		return false)
	assert_array(asked).is_equal(["path"])
	assert_bool(g.paused).is_false()
	assert_int(g.current_modal()).is_equal(Game.Modal.NONE)
	assert_array(g.modal_queue_kinds()).is_empty()
	assert_bool(g.resume_gate.visible).is_false()
	assert_float(g.player.invuln).is_less_equal(0.0001)


## A newcomer never jumps a waiting queue: with the cards waiting (a revive beat), a path slot due takes its place in
## line and the cards open first (pass 60, the review).
func test_a_newcomer_takes_its_place_behind_a_waiting_queue() -> void:
	var g := await _game()
	var opened: Array = []
	g._modal_queue.append({"kind": Game.Modal.CARDS, "priority": int(Game.MODAL_PRIORITY[Game.Modal.CARDS]), "seq": 1, "opener": func() -> bool:
		opened.append("cards")
		g.set_paused(true)
		return true})
	g._request_modal(Game.Modal.PATH, func() -> bool:
		opened.append("path")
		g.set_paused(true)
		return true)
	assert_array(opened).is_equal(["cards"])
	assert_int(g.current_modal()).is_equal(Game.Modal.CARDS)
	assert_array(g.modal_queue_kinds()).is_equal([Game.Modal.PATH])
	assert_bool(g.paused).is_true()
	g.modal_reset()
	g.set_paused(false)


## A power-up is not spent on the corpse (pass 60, the review): it waits where it lies until he is up.
func test_a_power_up_waits_while_he_is_down() -> void:
	var g := await _game()
	var pdef: PickupDef = Registry.pickup("shield")
	g.player._die()
	g.pickups.spawn_special(pdef, g.player.global_position + Vector3(0.3, 0, 0))
	await _frames(3)
	assert_int(g.pickups.specials.size()).is_equal(1)
	assert_float(g.player.shield_t).is_less_equal(0.0001)
	# Down! after the fall, then up again: the power-up is taken
	await get_tree().create_timer(1.4).timeout
	assert_array(g.visible_modals()).is_equal(["revive"])
	g.revive_screen._decide("debug")
	await _frames(6)
	assert_bool(g.player.dead).is_false()
	assert_int(g.pickups.specials.size()).is_equal(0)
	g.modal_reset()
	g.set_paused(false)
