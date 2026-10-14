extends GdUnitTestSuite

## Pass 62, lane UX (Garry, 2026-10-09): "I'd like an option to reset the Survey. Basically some way to test it for sure.
## Like in the developer options that Player can access", "I'd like to have control over the count of runs at which the
## first Survey appears. And on top of that I'd like a new survey that appears only on the 5th run", and "When Player
## encounters their 'favorite' item during Gameplay it should be marked somehow in a subtle way. And have more obvious
## markings, like in the case of The Drifter seeing Peashooter for the first time it should display at already the higher
## level with description as before but the description includes the correct stats for that level".
## A survey's name in PostHog carries its runs ("[after 3]", "[run 5]"); the game counts runs of a minute or more for
## life; the developer menu resets, fetches, shows, arms and counts. The favourite's cards wear a brass heart and
## FAVOURITE, and a new favourite shows the level it lands on, that level's numbers and its own effects.

const AnalyticsScript := preload("res://core/autoload/Analytics.gd")
const DIR := "user://test_saves/pass62_ux"
const KEY := "phc_testtesttesttesttest"

var _keep: Dictionary = {}


func before_test() -> void:
	_keep = {"consent": Save.data.get("consent", ""), "survey": (Save.data.get("survey", {}) as Dictionary).duplicate(true),
		"analytics": Settings.analytics, "surveys": Settings.surveys, "runs": Save.total("runs")}
	Save.data["survey"] = {}
	Settings.analytics = true
	Settings.surveys = true
	Run.arena = false


func after_test() -> void:
	Save.data["consent"] = _keep["consent"]
	Save.data["survey"] = _keep["survey"]
	Save.data["totals"]["runs"] = _keep["runs"]
	Settings.analytics = _keep["analytics"]
	Settings.surveys = _keep["surveys"]
	Run.arena = false
	Run.end()


## A client of its own (pass 59's): no network, the gate open.
func _client() -> Node:
	DirAccess.make_dir_recursive_absolute(DIR)
	var a: Node = auto_free(AnalyticsScript.new())
	a.test_mode = true
	a.queue_path = DIR.path_join("analytics_queue.json")
	a.survey_cache_path = DIR.path_join("surveys_cache.json")
	a.set_config({"host": "https://eu.i.posthog.com", "key": KEY, "enabled": true})
	a.sender = func(_url: String, _body: String) -> void: pass
	a.new_session()
	return a


## A running survey as PostHog lists it, with one rating question.
func _sv(id: String, sv_name: String) -> Dictionary:
	return {"id": id, "name": sv_name, "type": "api", "start_date": "2026-10-09T10:00:00Z", "end_date": null,
		"questions": [{"id": "q1", "type": "rating", "question": "Fun?", "scale": 5}]}


func _client_with(list: Array) -> Node:
	var a := _client()
	a.set_surveys_from({"surveys": list})
	return a


## One counted run in a new session (each call a fresh process, as a player opens the app once a run).
func _run_in_new_session(list: Array, seconds: float = 90.0) -> Dictionary:
	var a := _client_with(list)
	return a.survey_after_run(seconds)


func _counted() -> int:
	return int(Save.survey_state().get("counted", 0))


# ---------------------------------------------------------------- the tag in the name

func test_the_run_tag_is_read_from_the_name() -> void:
	assert_dict(AnalyticsScript.survey_rule("Net promoter score [after 3]")).is_equal({"kind": "after", "n": 3})
	assert_dict(AnalyticsScript.survey_rule("Fifth run check-in [run 5]")).is_equal({"kind": "run", "n": 5})
	assert_dict(AnalyticsScript.survey_rule("[RUN 5] loud")).is_equal({"kind": "run", "n": 5})
	assert_dict(AnalyticsScript.survey_rule("x [ after 12 ] y")).is_equal({"kind": "after", "n": 12})
	# no tag, and junk that is not a tag
	assert_dict(AnalyticsScript.survey_rule("Net promoter score (NPS) (2026-10-07 23:26)")).is_equal({"kind": "none", "n": 0})
	assert_dict(AnalyticsScript.survey_rule("Check [after three]")).is_equal({"kind": "none", "n": 0})
	assert_dict(AnalyticsScript.survey_rule("Check [after 0]")).is_equal({"kind": "none", "n": 0})
	assert_dict(AnalyticsScript.survey_rule("Check [runs 5]")).is_equal({"kind": "none", "n": 0})
	assert_dict(AnalyticsScript.survey_rule("Check (run 5)")).is_equal({"kind": "none", "n": 0})
	# the first tag wins
	assert_dict(AnalyticsScript.survey_rule("[run 5] [after 2]")).is_equal({"kind": "run", "n": 5})
	# the name a player could see never carries it; PostHog's own name stays on the survey for its events
	assert_str(AnalyticsScript.survey_title("Net promoter score [after 3]")).is_equal("Net promoter score")
	assert_str(AnalyticsScript.survey_title("Fifth run [run 5] check-in")).is_equal("Fifth run check-in")
	assert_str(AnalyticsScript.survey_title("Plain")).is_equal("Plain")
	var n := AnalyticsScript.normalise_survey(_sv("s5", "Fifth run check-in [run 5]"))
	assert_str(str(n["name"])).is_equal("Fifth run check-in [run 5]")
	assert_str(str(n["title"])).is_equal("Fifth run check-in")
	assert_dict(n["rule"]).is_equal({"kind": "run", "n": 5})
	# a cache from before pass 62 (no rule) reads it off the name
	assert_dict(AnalyticsScript.rule_of({"id": "x", "name": "Old [after 4]"})).is_equal({"kind": "after", "n": 4})


# ---------------------------------------------------------------- the rules over counted runs

func test_short_runs_are_not_counted() -> void:
	var list := [_sv("a3", "NPS [after 3]")]
	assert_dict(_run_in_new_session(list, 30.0)).is_empty()
	assert_dict(_run_in_new_session(list, 59.0)).is_empty()
	assert_int(_counted()).is_equal(0)
	# never in the arena either
	Run.arena = true
	assert_dict(_run_in_new_session(list, 300.0)).is_empty()
	Run.arena = false
	assert_int(_counted()).is_equal(0)
	# a long run counts even with questions off (the count is the player's, the question is not)
	Settings.surveys = false
	assert_dict(_run_in_new_session(list)).is_empty()
	assert_int(_counted()).is_equal(1)


func test_after_n_comes_first_at_n_then_every_three_until_answered() -> void:
	var list := [_sv("a3", "NPS [after 3]")]
	assert_dict(_run_in_new_session(list)).is_empty()
	assert_dict(_run_in_new_session(list)).is_empty()
	assert_str(str(_run_in_new_session(list).get("id", ""))).is_equal("a3")
	assert_int(_counted()).is_equal(3)
	# not answered: again three counted runs later
	assert_dict(_run_in_new_session(list)).is_empty()
	assert_dict(_run_in_new_session(list)).is_empty()
	var a := _client_with(list)
	var sv: Dictionary = a.survey_after_run(90.0)
	assert_str(str(sv.get("id", ""))).is_equal("a3")
	assert_int(int((Save.survey_state()["shown"] as Dictionary)["a3"])).is_equal(6)
	# answered: never again
	a.survey_sent(sv, {"q1": 5})
	for k in 7:
		assert_dict(_run_in_new_session(list)).is_empty()


func test_run_n_comes_only_at_its_run() -> void:
	var list := [_sv("r5", "Fifth run check-in [run 5]")]
	for k in 4:
		assert_dict(_run_in_new_session(list)).is_empty()
	assert_str(str(_run_in_new_session(list).get("id", ""))).is_equal("r5")
	# not answered, and still never again
	for k in 8:
		assert_dict(_run_in_new_session(list)).is_empty()
	assert_int(_counted()).is_equal(13)


func test_both_due_the_run_n_one_goes_first_and_only_one_card() -> void:
	var list := [_sv("a5", "NPS [after 5]"), _sv("r5", "Fifth run [run 5]")]
	for k in 4:
		assert_dict(_run_in_new_session(list)).is_empty()
	var a := _client_with(list)
	assert_str(str(a.survey_after_run(90.0).get("id", ""))).is_equal("r5")
	# the same session: nothing more (the other waits)
	assert_dict(a.survey_after_run(90.0)).is_empty()
	# the next session: the [after 5] one, never shown yet
	assert_str(str(_run_in_new_session(list).get("id", ""))).is_equal("a5")


func test_a_run_n_survey_is_not_held_back_by_the_session() -> void:
	var list := [_sv("a1", "Every run [after 1]"), _sv("r3", "Third [run 3]")]
	var a := _client_with(list)
	assert_str(str(a.survey_after_run(90.0).get("id", ""))).is_equal("a1")
	assert_dict(a.survey_after_run(90.0)).is_empty()
	assert_str(str(a.survey_after_run(90.0).get("id", ""))).is_equal("r3")


func test_an_untagged_survey_keeps_the_pass_59_rule() -> void:
	var list := [_sv("u", "Net promoter score (NPS) (2026-10-07 23:26)")]
	# the first counted run of a new install brings it, then every three counted runs
	assert_str(str(_run_in_new_session(list).get("id", ""))).is_equal("u")
	assert_dict(_run_in_new_session(list)).is_empty()
	assert_dict(_run_in_new_session(list)).is_empty()
	assert_str(str(_run_in_new_session(list).get("id", ""))).is_equal("u")


func test_the_next_counted_run_says_when_each_comes() -> void:
	var a := _client_with([_sv("a3", "NPS [after 3]"), _sv("r5", "Fifth [run 5]"), _sv("u", "Plain")])
	var st := Save.survey_state()
	st["counted"] = 1
	assert_int(a.survey_next_run(a.surveys[0], st)).is_equal(3)
	assert_int(a.survey_next_run(a.surveys[1], st)).is_equal(5)
	assert_int(a.survey_next_run(a.surveys[2], st)).is_equal(2)
	st["counted"] = 6
	assert_int(a.survey_next_run(a.surveys[1], st)).is_equal(-1)
	assert_int(a.survey_next_run(a.surveys[0], st)).is_equal(7)
	var lines := "\n".join(a.survey_lines())
	assert_str(lines).contains("NPS [after 3]")
	assert_str(lines).contains("[run 5]: after counted run 5 only")
	assert_str(lines).contains("counted runs: 6")


# ---------------------------------------------------------------- the developer menu's tools

func test_reset_clears_the_survey_record_and_leaves_the_switches() -> void:
	var a := _client_with([_sv("a3", "NPS [after 3]")])
	Save.data["consent"] = "yes"
	var st := Save.survey_state()
	st["counted"] = 9
	st["runs_since"] = 1
	st["answered"] = ["a3"]
	st["dismissed"] = ["a3"]
	st["shown"] = {"a3": 6}
	st["armed"] = true
	a.survey_after_run(90.0)
	a.set("_survey_this_session", true)
	a.reset_surveys()
	st = Save.survey_state()
	assert_int(int(st["counted"])).is_equal(0)
	assert_array(st["answered"]).is_empty()
	assert_array(st["dismissed"]).is_empty()
	assert_dict(st["shown"]).is_empty()
	assert_bool(st.has("runs_since")).is_false()
	assert_bool(st.has("armed")).is_false()
	assert_bool(bool(a.get("_survey_this_session"))).is_false()
	assert_str(Save.consent()).is_equal("yes")
	assert_bool(Settings.surveys).is_true()
	# as on a new install: the [after 3] survey at the third counted run again
	assert_dict(a.survey_after_run(90.0)).is_empty()
	assert_dict(a.survey_after_run(90.0)).is_empty()
	assert_str(str(a.survey_after_run(90.0).get("id", ""))).is_equal("a3")


func test_next_run_asks_arms_one_survey_whatever_the_rules() -> void:
	var a := _client_with([_sv("a10", "Later [after 10]")])
	# not due: nothing
	assert_dict(a.survey_after_run(90.0)).is_empty()
	a.arm_next_run(true)
	assert_bool(a.next_run_armed()).is_true()
	# a short run does not use it
	assert_dict(a.survey_after_run(20.0)).is_empty()
	assert_bool(a.next_run_armed()).is_true()
	assert_str(str(a.survey_after_run(90.0).get("id", ""))).is_equal("a10")
	assert_bool(a.next_run_armed()).is_false()
	# armed again in the same session: the session rule gives way too
	a.arm_next_run(true)
	assert_str(str(a.survey_after_run(90.0).get("id", ""))).is_equal("a10")
	a.arm_next_run(false)
	assert_bool(a.next_run_armed()).is_false()


func test_counted_runs_step_and_show_now_takes_turns() -> void:
	var a := _client_with([_sv("x", "One"), _sv("y", "Two [run 5]")])
	a.add_counted(4)
	assert_int(_counted()).is_equal(4)
	# the next counted run is the fifth: the [run 5] one
	assert_str(str(a.survey_after_run(90.0).get("id", ""))).is_equal("y")
	assert_str(str(a.survey_for_test().get("id", ""))).is_equal("x")
	assert_str(str(a.survey_for_test().get("id", ""))).is_equal("y")
	a.survey_sent(a.surveys[0], {"q1": 3})
	assert_str(str(a.survey_for_test().get("id", ""))).is_equal("y")
	a.survey_sent(a.surveys[1], {"q1": 3})
	assert_dict(a.survey_for_test()).is_empty()
	assert_str(a.no_test_survey_reason()).contains("Reset surveys")
	# a dismissal is kept for the readout and changes nothing else
	a.survey_dismissed(a.surveys[0])
	assert_array(Save.survey_state()["dismissed"]).contains(["x"])


func test_an_old_save_counts_from_its_finished_runs() -> void:
	Save.data["survey"] = {"answered": [], "runs_since": 1}
	Save.data["totals"]["runs"] = 7
	Save._survey_counted_from_runs()
	assert_int(_counted()).is_equal(7)
	# once there, it is the save's own
	Save.data["totals"]["runs"] = 12
	Save._survey_counted_from_runs()
	assert_int(_counted()).is_equal(7)
	# a wipe keeps it
	assert_array(Save.KEEP_ON_WIPE).contains(["survey"])


func test_the_developer_menu_has_the_surveys_block() -> void:
	Analytics.surveys = []
	var menu: Control = auto_free(load("res://ui/DevMenu.tscn").instantiate())
	add_child(menu)
	await get_tree().process_frame
	for n in ["Surveys", "SurveyReset", "SurveyFetch", "SurveyShow", "SurveyArm", "SurveyCounted"]:
		assert_object(menu.find_child(n, true, false)).override_failure_message(n).is_not_null()
	# nothing fetched: Show says so instead of opening a card
	assert_object(menu.call("show_survey_now")).is_null()
	await get_tree().process_frame
	await get_tree().process_frame
	var note: WText = menu.find_child("SurveyNote", true, false)
	assert_object(note).is_not_null()
	assert_str(note.text).contains("Fetch surveys now")
	# a survey there: the card opens over the menu
	Analytics.surveys = [AnalyticsScript.normalise_survey(_sv("t", "Test [run 5]"))]
	var card: Control = menu.call("show_survey_now")
	assert_object(card).is_not_null()
	assert_object(menu.get_node_or_null("Survey")).is_not_null()
	card.call("dismiss")
	# Reset asks first
	menu.call("_ask_reset_surveys")
	assert_bool(WConfirm.is_open(menu)).is_true()
	WConfirm.dismiss(menu)
	Analytics.surveys = []
	menu.visible = false
	# the rows the menu rebuilt and the closed cards are freed at a frame's end
	for k in 30:
		await get_tree().process_frame


func test_no_row_of_the_developer_menu_is_wider_than_the_screen() -> void:
	Settings.top_inset = 130
	var menu: Control = auto_free(load("res://ui/DevMenu.tscn").instantiate())
	add_child(menu)
	for k in 4:
		await get_tree().process_frame
	var list: VBoxContainer = menu.get("_list")
	var vw: float = menu.get_viewport_rect().size.x
	assert_float(list.size.x).is_less_equal(vw - 96.0 + 0.5)
	for row in list.get_children():
		var r := (row as Control).get_global_rect()
		assert_float(r.end.x).override_failure_message(str(row.name)).is_less_equal(vw + 0.5)
		var val: Control = (row as Node).find_child("Value", true, false)
		if val:
			assert_float(val.get_global_rect().end.x).override_failure_message(str(row.name)).is_less_equal(r.end.x + 0.5)
	Settings.top_inset = -1
	menu.visible = false


# ---------------------------------------------------------------- the favourite on the cards

func _offer_card_of(id: String, tries: int = 400) -> Dictionary:
	for k in tries:
		for c: Dictionary in CardPool.level_up_offer(3):
			if str(c["id"]) == id:
				return c
	return {}


## Pass 76 (lane DYN): the Drifter's favourite is the dynamite (the Lob Grenade) now, the Peashooter is hidden.
func test_the_drifters_first_favourite_shows_level_two_and_its_numbers() -> void:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	var pea: WeaponDef = Registry.weapon("lob_grenade")
	assert_int(CardPool.first_weapon_level(pea)).is_equal(2)
	assert_int(CardPool.first_weapon_level(Registry.weapon("boomstick"))).is_equal(1)
	seed(6201)
	var card := _offer_card_of("lob_grenade")
	assert_bool(card.is_empty()).override_failure_message("no Lob Grenade card").is_false()
	assert_int(int(card["level_to"])).is_equal(2)
	assert_bool(WItem.favourite(card)).is_true()
	# the level-2 stars and the level-2 words: a wider blast, as he will get it
	assert_array(WItem.stars(card)).is_equal([pea.max_level, 2, -1])
	var two := CardPool.preview_weapon(pea, 2).description()
	var one := CardPool.preview_weapon(pea, 1).description()
	assert_str(two).is_not_equal(one)
	assert_str(WItem.effect(card)).starts_with(two)
	assert_str(WItem.effect(card)).ends_with(" His favourite: found at level 2.")
	# the card wears the heart and the word; its plate is in the level-2 colour
	var o := WItem.options(card)
	assert_bool(bool(o["favourite"])).is_true()
	assert_int(int(o["level"])).is_equal(2)
	var wc: WCard = auto_free(WCard.make(pea, o))
	assert_object(wc.fav_heart).is_not_null()
	assert_object(wc.fav_word).is_not_null()
	assert_str(wc.fav_word.text).is_equal("FAVOURITE")
	assert_object(wc.plate.get_node_or_null("FavouriteHeart")).is_not_null()
	assert_str(str(o["tag"])).is_equal("NEW")
	# taken, it is what the card said
	CardPool.apply(card)
	var inst := Run.weapon_instance("lob_grenade")
	assert_int(inst.level).is_equal(2)
	assert_str(inst.description()).is_equal(two)
	# its upgrades keep the quiet mark, without the bonus words
	var up := {"type": "weapon", "id": pea.id, "def": pea, "level_from": 2, "level_to": 3, "is_new": false}
	assert_bool(WItem.favourite(up)).is_true()
	assert_str(WItem.favourite_line(up)).is_equal("")


func test_an_ordinary_card_is_unchanged() -> void:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	var boom: WeaponDef = Registry.weapon("boomstick")
	var card := {"type": "weapon", "id": boom.id, "def": boom, "level_from": 0, "level_to": 1, "is_new": true}
	assert_bool(WItem.favourite(card)).is_false()
	var tmp := WeaponInstance.new(boom, 1)
	tmp.rebuild(Run.player_sheet, Run.weapons)
	assert_str(WItem.effect(card)).is_equal(tmp.description())
	var o := WItem.options(card)
	assert_bool(bool(o["favourite"])).is_false()
	var wc: WCard = auto_free(WCard.make(boom, o))
	assert_object(wc.fav_heart).is_null()
	assert_object(wc.fav_word).is_null()
	assert_object(wc.find_child("Favourite", true, false)).is_null()
	assert_array(WItem.stars(card)).is_equal([boom.max_level, 1, -1])
	# evolutions, mutations and perks are never the favourite
	var pc: WeaponDef = Registry.weapon("pea_cannon")
	if pc:
		assert_bool(WItem.favourite({"type": "evolution", "id": pc.id, "def": pc, "level_from": 0, "level_to": 1})).is_false()


func test_astros_orbit_saws_card_names_her_bonus() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var saws: WeaponDef = Registry.weapon("orbit_saws")
	var card := {"type": "weapon", "id": saws.id, "def": saws, "level_from": 0, "level_to": CardPool.first_weapon_level(saws), "is_new": true}
	assert_int(int(card["level_to"])).is_equal(1)
	assert_bool(WItem.favourite(card)).is_true()
	var e := WItem.effect(card)
	assert_str(e).contains("Her favourite: +20% area of effect.")
	# folded into the numbers she gets: the preview carries the bonus, as the copy she will hold does
	var pv := CardPool.preview_weapon(saws, 1)
	assert_float(pv.stat("area")).is_equal_approx(1.2, 0.001)
	CardPool.apply(card)
	assert_float(Run.weapon_instance("orbit_saws").stat("area")).is_equal_approx(1.2, 0.001)


func test_the_stranger_hands_the_favourite_over_with_its_bonus() -> void:
	# a hero of the test's own (the Stranger sells rare and up: the Molotov), its favourite found at level 3
	var c: CharacterDef = Registry.character("drifter").duplicate()
	c.favourite_weapon = "molotov"
	c.favourite_bonus = {"type": "level", "value": 3}
	Run.start(c, Registry.map("red_canyon"))
	var mol: WeaponDef = Registry.weapon("molotov")
	assert_int(CardPool.first_weapon_level(mol)).is_equal(3)
	seed(6203)
	var offer := {}
	for k in 600:
		var o: Dictionary = Run.stranger_offer()
		if str(o.get("id", "")) == "molotov":
			offer = o
			break
	assert_bool(offer.is_empty()).override_failure_message("the Stranger never offered the Molotov").is_false()
	assert_int(int(offer["level_to"])).is_equal(3)
	assert_bool(WItem.favourite(offer)).is_true()
	Run.stranger_take(offer, 0.1)
	assert_int(Run.weapon_instance("molotov").level).is_equal(3)
	# an effects bonus comes along too (it never did from him before pass 62)
	Run.end()
	var c2: CharacterDef = Registry.character("drifter").duplicate()
	c2.favourite_weapon = "molotov"
	var area := Effect.make("area", "mul", 0.2)
	c2.favourite_bonus = {"type": "effects", "effects": [area]}
	Run.start(c2, Registry.map("red_canyon"))
	Run.stranger_take({"type": "weapon", "id": "molotov", "def": mol, "level_from": 0, "level_to": 2, "is_new": true}, 0.1)
	var inst := Run.weapon_instance("molotov")
	assert_int(inst.level).is_equal(2)
	assert_int(inst.bonus_effects.size()).is_equal(1)


func test_the_chest_landing_on_the_favourite_wears_the_heart() -> void:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	# pass 76 (lane DYN): his favourite is the dynamite (the Lob Grenade) now
	var pea: WeaponDef = Registry.weapon("lob_grenade")
	Run.add_weapon(pea, 2)
	var cs: ChestScreen = auto_free(ChestScreen.new())
	add_child(cs)
	await get_tree().process_frame
	cs.open({"type": "weapon", "id": pea.id, "def": pea, "level_from": 2, "level_to": 3, "is_new": false})
	cs.skip_intro()
	cs._tw.set_speed_scale(40.0)
	for k in 60:
		await get_tree().process_frame
		if not cs._spinning:
			break
	assert_object(cs._fav_word).is_not_null()
	assert_str(cs._fav_word.text).is_equal("FAVOURITE")
	assert_object(cs._hero.get_node_or_null("FavouriteHeart")).is_not_null()
	# a gold roll after it: the word goes
	cs.open({"type": "gold", "id": "", "def": null, "gold": 50, "level_from": 0, "level_to": 0, "is_new": false})
	cs.skip_intro()
	cs._tw.set_speed_scale(40.0)
	for k in 60:
		await get_tree().process_frame
		if not cs._spinning:
			break
	assert_object(cs._fav_word).is_null()
	cs.visible = false


func test_a_favourite_passive_card_says_its_level() -> void:
	Run.start(Registry.character("ironwood"), Registry.map("red_canyon"))
	var brawn: PassiveDef = Registry.passive("brawn")
	var card := {"type": "passive", "id": brawn.id, "def": brawn, "level_from": 0, "level_to": Run.first_passive_level(brawn), "is_new": true}
	assert_int(int(card["level_to"])).is_equal(2)
	assert_bool(WItem.favourite(card)).is_true()
	assert_str(WItem.effect(card)).ends_with(" His favourite: found at level 2.")
	# the shop's starless card says where it lands
	var o := WItem.options(card, {"stars": []})
	assert_str(str(o["word"])).ends_with("· LV 2")
