extends GdUnitTestSuite

## Pass 123, lane RUN_C: the mutation offer, the War Drum and Grindstone moments, and the play-data and survey cards under
## the Royale theme (Garry's build brief: "Mutation offer as the mock: the weapon framed over rays, the count plates, three
## slate cards with purple-rimmed frames and full text", "The Header texts should all be white and make the amount of
## Skips display better than what's on the mock"; "War Drum moment: keep the drum art; set its title in the new kit's
## type"; "Grindstone moment: keep the wheel and sparks; the weapon in the new item frame, its title and LEVEL / EVOLVED
## stamp in the new kit's type"; "Consent and survey pop-ups in the shared pop-up shell, as the mock", "White header").
## Shapes and rules only: Wanted stays today's (the plate, the list's width, the skip's size, no count plates, no skips
## pill), Royale is the mock's structure (the frame's size and rays, the black count plates, the cards' epic frames and
## purple kind word, the 990 px list, the 590 x 106 SKIP with its skips left in words, the shell's pieces on both cards).

const CONSENT := preload("res://ui/wanted/WConsent.gd")
const SURVEY := preload("res://ui/wanted/WSurvey.gd")
const GRIND := preload("res://ui/GrindMoment.gd")
const SV := {"id": "p123", "name": "P123", "questions": [
	{"id": "q1", "type": "rating", "question": "How much fun was that run?", "description": "", "optional": false, "choices": [], "scale": 5, "lower": "Not fun", "upper": "Loved it"},
	{"id": "q2", "type": "open", "question": "Anything you would change?", "description": "", "optional": true, "choices": [], "scale": 5, "lower": "", "upper": ""}]}

var _settings_before: Dictionary = {}


func before() -> void:
	_settings_before = Settings.to_dict()


func after() -> void:
	Settings.force_prod(false)
	Settings.from_dict(_settings_before)


func before_test() -> void:
	Save.begin_sandbox()


func after_test() -> void:
	get_tree().paused = false
	Run.end()
	if Save.sandboxed():
		Save.end_sandbox()


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


func _start() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.add_weapon(Registry.weapon("boomstick"), 3)
	Run.rerolls_left = 1
	Run.skips_left = 2
	Run.banishes_left = 0


## A mutation offer for the Boomstick, its reel skipped and its cards landed.
func _path_offer(cs: CardScreen) -> void:
	cs.show_offer(CardPool.path_offer(Run.weapon_instance("boomstick")), "MUTATION", false, true)
	cs.skip_reel()
	var n := 0
	while (cs.reel_running() or cs._cards.is_empty()) and n < 120:
		await get_tree().process_frame
		n += 1
	await await_millis(450)


func _host() -> Control:
	var h: Control = auto_free(Control.new())
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(h)
	return h


## The words of every WText under `n` (runs read in order).
func _words(n: Node) -> String:
	var out := ""
	if n is WText:
		var t := n as WText
		if t.runs.is_empty():
			out += t.text
		else:
			for r in t.runs:
				out += str(r[0])
	for c in n.get_children():
		out += _words(c)
	return out


# ---------------------------------------------------------------- 1. the Royale mutation offer is the mock's

func test_the_royale_mutation_offer_is_the_mocks_structure() -> void:
	_start()
	var cs: CardScreen = auto_free(CardScreen.new())
	add_child(cs)
	await _path_offer(cs)
	assert_bool(cs.path_mode).is_true()
	# the head: the star line and the weapon's name cream (Garry: "The Header texts should all be white"), the 280 px
	# frame over the kit's rays
	var star: WStarLine = cs._path_head.get_child(0)
	assert_bool(star.color.is_equal_approx(R.CREAM)).is_true()
	assert_float(cs._path_plate.side).is_equal(CardScreen.ROYALE_PATH_PLATE_PX)
	assert_bool(cs._path_plate.rays).is_true()
	var nm: WText = cs._path_name
	assert_str(nm.text).is_equal("BOOMSTICK")
	assert_bool(nm.color.is_equal_approx(R.CREAM)).is_true()
	assert_bool(R.is_display(nm.font)).is_true()
	assert_int(nm.font_size).is_between(CardScreen.ROYALE_PATH_NAME_MIN, CardScreen.ROYALE_PATH_NAME_PX)
	# the count plates: "Mutation" with a rivet per mutation of the path, and what the others do, each a black pill
	assert_str(str(cs._path_row.name)).is_equal("CountPlates")
	var p1: Control = cs._path_row.find_child("MutationPill", true, false)
	assert_object(p1).is_not_null()
	var riv: WMarks = p1.find_child("Rivets", true, false)
	assert_object(riv).is_not_null()
	assert_int(riv.total).is_equal(maxi(Registry.mutations_of("boomstick").size(), 1))
	assert_int(riv.held).is_equal(Run.path_progress(Run.weapon_instance("boomstick")).x)
	assert_str(_words(p1)).is_equal("Mutation")
	var p2: Control = cs._path_row.find_child("LeavePill", true, false)
	assert_object(p2).is_not_null()
	assert_str(_words(p2)).is_equal(CardScreen.leave_line(cs._cards.size()).trim_prefix("· "))
	assert_str((p1.get_theme_stylebox("panel") as HardBox).royale_kind()).is_equal("plate")
	# the cards: 990 wide, epic frames of 160 px, the kind word purple, the full text at the mock's size, equal heights up
	# to 290, clear of the skips pill
	assert_float(cs._list.get_global_rect().position.x).is_equal_approx(CardScreen.ROYALE_PATH_INSET, 0.5)
	assert_float(cs._list.size.x).is_equal_approx(1080.0 - 2.0 * CardScreen.ROYALE_PATH_INSET, 0.5)
	assert_int(cs._cards.size()).is_greater_equal(2)
	var h0 := (cs._cards[0] as Control).size.y
	for c in cs._cards:
		var card := c as WCard
		assert_float(card.plate.side).is_equal(CardScreen.ROYALE_PATH_FRAME_PX)
		# pass 123 (Garry: "Mutation Icons looks too much like Epic Rarity Items"): their own colour
		assert_str(card.plate.frame_rarity()).is_equal("mutation")
		var wl := card.find_child("WordLine", true, false)
		var wt := wl.get_child(0) as WText
		assert_bool((wt.runs[0][1] as Color).is_equal_approx(R.MUTATION["word"])).is_true()
		assert_int(card.effect_text.font_size).is_equal(CardScreen.ROYALE_PATH_TEXT_PX)
		assert_float(card.size.y).is_equal_approx(h0, 1.0)
		assert_float(card.size.y).is_less_equal(CardScreen.ROYALE_PATH_CARD_H + 0.5)
	var last: Control = cs._cards.back()
	assert_float(last.get_global_rect().end.y).is_less_equal(cs._skips_box.get_global_rect().position.y - CardScreen.ROYALE_CARDS_CLEAR + 1.0)
	assert_float((cs._cards[0] as Control).get_global_rect().position.y).is_greater(cs._path_row.get_global_rect().end.y)
	# the SKIP: the mock's 590 x 106 slate with its count pill, and the skips left in words over it
	var sk := cs._path_skip.get_global_rect()
	assert_float(sk.size.x).is_equal_approx(CardScreen.ROYALE_SKIP_W, 0.5)
	assert_float(sk.size.y).is_greater_equal(CardScreen.ROYALE_SKIP_H - 0.5)
	assert_float(sk.end.y).is_equal_approx(1920.0 - CardScreen.SKIP_FOOT, 1.0)
	assert_str(cs._path_skip.label_text()).is_equal("SKIP×2")
	assert_str(cs._path_skip.role).is_equal(WButton.SLATE)
	assert_int(cs._path_skip.font_size).is_equal(CardScreen.ROYALE_SKIP_PX)
	assert_bool(cs._skips_box.visible).is_true()
	assert_str(cs.skips_pill_text()).is_equal("2 skips left this stage")
	assert_float(cs._skips_box.get_global_rect().end.y).is_less_equal(sk.position.y)
	assert_array(CardScreen.skips_parts(1)).is_equal([["1", R.GOLD_TEXT, "bold"], " skip left this stage"])
	# none left: the words say so, the button locks, a tap is refused and the screen stays (the note stays hidden: the
	# pill says it)
	Run.skips_left = 0
	cs._refresh_buttons()
	await _frames(1)
	assert_str(cs.skips_pill_text()).is_equal("No skips left this stage")
	assert_bool(cs._path_skip.locked).is_true()
	cs._skip()
	assert_bool(cs.visible).is_true()
	assert_bool(cs._path_note.visible).is_false()
	assert_str(cs._path_note.text).is_equal("No skips left this stage.")
	cs.visible = false
	await _frames(1)


# ---------------------------------------------------------------- 2. Wanted keeps today's



# ---------------------------------------------------------------- 3. a theme flip rebuilds the skip in its place



# ---------------------------------------------------------------- 4. the play-data card in the shell

func test_the_play_data_card_is_the_shell_under_royale() -> void:
	Save.data["consent"] = ""
	var host := _host()
	var card: Control = CONSENT.open(host)
	await _frames(3)
	await await_millis(350)
	var panel: PanelContainer = card.get("card")
	assert_float(panel.size.x).is_equal_approx(float(R.MODAL_W), 0.5)
	assert_float(panel.size.y).is_greater_equal(CONSENT.CONSENT_MIN_H - 0.5)
	assert_str((panel.get_theme_stylebox("panel") as HardBox).royale_kind()).is_equal("panel")
	# the card's top R.MODAL_TOP_AT of the room, as the shell's
	var vh := card.get_viewport_rect().size.y
	assert_float(panel.offset_top).is_equal_approx(CONSENT.rest_top(panel.size.y, vh), 1.0)
	assert_float(panel.offset_top).is_equal_approx((vh - panel.size.y) * R.MODAL_TOP_AT, 1.0)
	var dim: ColorRect = card.get("dim")
	assert_bool(dim.color.is_equal_approx(W.dim_color("ask"))).is_true()
	var stars: Array = []
	var titles: Array = []
	for n in panel.find_children("*", "", true, false):
		if n is WStarLine:
			stars.append(n)
		elif n is WText and (n as WText).text == "PLAY DATA":
			titles.append(n)
	assert_int(stars.size()).is_equal(1)
	assert_bool((stars[0] as WStarLine).color.is_equal_approx(R.GOLD_TEXT)).is_true()
	assert_int(titles.size()).is_equal(1)
	var t := titles[0] as WText
	assert_bool(t.color.is_equal_approx(R.CREAM)).is_true()
	assert_bool(R.is_display(t.font)).is_true()
	assert_int(t.font_size).is_equal(R.MODAL_TITLE_PX)
	var b: WText = card.find_child("Body", true, false)
	assert_str(b.text).is_equal(CONSENT.body_text(Save.player_name()))
	assert_bool(b.color.is_equal_approx(R.WHITE)).is_true()
	assert_bool(R.is_display(b.font)).is_false()
	assert_int(b.font_size).is_equal(R.MODAL_BODY_PX)
	var no: WButton = card.find_child("Decline", true, false)
	var ok: WButton = card.find_child("Accept", true, false)
	assert_str(no.role).is_equal(WButton.SLATE)
	assert_str(ok.role).is_equal(WButton.GOLD)
	assert_str(no.label_text()).is_equal("NO THANKS")
	assert_str(ok.label_text()).is_equal("OK")
	assert_float(ok.size.y).is_greater_equal(float(R.MODAL_BUTTON_H) - 0.5)
	# the buttons on the card's foot, side by side
	assert_float(no.get_global_rect().position.y).is_equal_approx(ok.get_global_rect().position.y, 0.5)
	assert_float(ok.get_global_rect().end.y).is_greater(b.get_global_rect().end.y)
	assert_bool(bool(card.call("is_done"))).is_false()




# ---------------------------------------------------------------- 5. the survey card in the shell

func test_the_survey_is_the_shell_under_royale() -> void:
	var host := _host()
	var card: Control = SURVEY.open(host, SV.duplicate(true))
	await _frames(3)
	await await_millis(350)
	var panel: PanelContainer = card.get("card")
	assert_float(panel.size.x).is_equal_approx(float(R.MODAL_W), 0.5)
	assert_float(panel.size.y).is_greater_equal(SURVEY.SURVEY_MIN_H - 0.5)
	assert_float(float(card.get("_base_top"))).is_greater_equal(SURVEY.CARD_TOP + W.safe_top() - 0.5)
	var prog: WText = card.find_child("Progress", true, false)
	assert_str(prog.text).is_equal("1 / 2")
	assert_int(prog.align).is_equal(HORIZONTAL_ALIGNMENT_RIGHT)
	var head: Control = card.find_child("Head", true, false)
	assert_bool((head.get_child(0) as WStarLine).color.is_equal_approx(R.GOLD_TEXT)).is_true()
	var q: VBoxContainer = card.find_child("Question", true, false)
	var title := q.get_child(0) as WText
	assert_str(title.text).is_equal("How much fun was that run?")
	assert_bool(title.color.is_equal_approx(R.CREAM)).is_true()
	assert_bool(R.is_display(title.font)).is_true()
	assert_int(title.font_size).is_equal(SURVEY.QUESTION_PX)
	assert_int(title.align).is_equal(HORIZONTAL_ALIGNMENT_LEFT)
	var nxt: WButton = card.find_child("Next", true, false)
	var nn: WButton = card.find_child("NotNow", true, false)
	assert_str(nxt.role).is_equal(WButton.BLUE)
	assert_str(nn.role).is_equal(WButton.SLATE)
	assert_float(nxt.size.y).is_greater_equal(SURVEY.BUTTON_H - 0.5)
	assert_bool(nxt.locked).is_true()
	for k in range(1, 6):
		var r: WButton = card.find_child("Rate%d" % k, true, false)
		assert_str(r.role).is_equal(WButton.SLATE)
		assert_float(r.size.y).is_greater_equal(SURVEY.CELL_H - 0.5)
	# the pick gold, the rest slate; NEXT opens
	var r4: WButton = card.find_child("Rate4", true, false)
	r4.pressed.emit()
	await _frames(1)
	for k in range(1, 6):
		var r: WButton = card.find_child("Rate%d" % k, true, false)
		assert_str(r.role).is_equal(WButton.GOLD if k == 4 else WButton.SLATE)
		assert_bool(bool(card.call("is_marked", r))).is_equal(k == 4)
	assert_bool(nxt.locked).is_false()
	# the link under the card: underlined, the secondary blue
	var never: Control = card.find_child("NeverAsk", true, false)
	var lt := never.get_child(0) as WText
	assert_bool(lt.underline).is_true()
	assert_bool(lt.color.is_equal_approx(R.SECONDARY)).is_true()
	assert_float(never.get_global_rect().position.y).is_greater_equal(panel.get_global_rect().end.y - 1.0)
	# the text page: a solid navy cell, its edge gold while focused, cream words
	card.call("next")
	await _frames(2)
	var ans: TextEdit = card.find_child("Answer", true, false)
	assert_object(ans).is_not_null()
	var nb := ans.get_theme_stylebox("normal") as HardBox
	var fb := ans.get_theme_stylebox("focus") as HardBox
	assert_bool(nb.fill.is_equal_approx(R.CELL)).is_true()
	assert_bool(fb.border_color.is_equal_approx(R.GOLD_TEXT)).is_true()
	assert_bool(ans.get_theme_color("font_color").is_equal_approx(R.CREAM)).is_true()
	assert_str(prog.text).is_equal("2 / 2")
	assert_str(nxt.label_text()).is_equal("SEND")




# ---------------------------------------------------------------- 6. the War Drum's moment

func test_the_drum_moment_plays_its_beats_under_both_themes() -> void:
	var d: StructureDef = Registry.structure("war_drum")
	assert_object(d).is_not_null()
	var hits: int = (d.params["moment"]["hits"] as Array).size()
	for royale in [true]:
		var dm: DrumMoment = auto_free(DrumMoment.new())
		add_child(dm)
		dm.open(d, "x2 damage · 15 seconds")
		assert_bool(dm.playing).is_true()
		assert_str(dm.title).is_equal(d.display_name.to_upper())
		dm.set_process(false)
		var n := 0
		while dm.playing and dm.t < 1.7 and n < 400:
			dm._process(1.0 / 60.0)
			n += 1
		# drawn in the theme on (the kit's lines under Royale): a frame of it
		dm.queue_redraw()
		await _frames(1)
		assert_int(dm.hits_played).is_equal(hits)
		var done: Array = []
		dm.finished.connect(func(): done.append(true))
		dm.skip()
		assert_bool(dm.playing).is_false()
		assert_int(done.size()).is_equal(1)


# ---------------------------------------------------------------- 7. the Grindstone's show

func test_the_grind_moment_wears_the_kits_frame_under_royale() -> void:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	for royale in [true]:
		# a level: the Boomstick 2 -> 3, stamped
		var gm: Control = auto_free(GRIND.new())
		add_child(gm)
		gm.open({"id": "boomstick", "from": "boomstick", "level_from": 2, "level_to": 3, "evolved": false})
		gm.set_process(false)
		gm.seek(2.3)
		assert_bool(bool(gm.get("stamped"))).is_true()
		var plate: WPlate = gm.get("_plate")
		assert_bool(plate.visible).is_true()
		if royale:
			assert_bool(R.RARITY.has(plate.frame_rarity())).is_true()
			assert_bool(plate.is_evolved_frame()).is_false()
		await _frames(1)
		gm.call("skip")
		# an evolution: the Revolver into the Golden Revolver, burst
		var ge: Control = auto_free(GRIND.new())
		add_child(ge)
		ge.open({"id": "golden_revolver", "from": "revolver", "level_from": 5, "level_to": 5, "evolved": true})
		ge.set_process(false)
		ge.seek(2.75)
		assert_bool(bool(ge.get("stamped"))).is_true()
		var ep: WPlate = ge.get("_plate")
		if royale:
			assert_bool(ep.is_evolved_frame()).is_true()
		await _frames(1)
		ge.call("skip")
		assert_bool(bool(ge.get("playing"))).is_false()
