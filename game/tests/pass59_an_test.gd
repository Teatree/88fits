extends GdUnitTestSuite

## Pass 59 (Garry: "I want to be able to Identify the Player ... check the PostHog on my phone ... some type of a Survey
## system within the game"): every install is a person with a readable name kept through a wipe; nothing leaves before
## the play-data card is answered; end-of-run surveys come from PostHog Surveys (API mode) with PostHog's own events,
## paced, and with an opt-out PostHog can see. No network: every client here has its own sender.

const AnalyticsScript := preload("res://core/autoload/Analytics.gd")
const WSurveyScript := preload("res://ui/wanted/WSurvey.gd")
const WConsentScript := preload("res://ui/wanted/WConsent.gd")
const DIR := "user://test_saves/pass59_an"
const KEY := "phc_testtesttesttesttest"

var _calls: Array = []
var _save_dir := ""
var _keep: Dictionary = {}


func before() -> void:
	Save.flush()
	_save_dir = Save.dir


func after() -> void:
	Save.dir = _save_dir


func before_test() -> void:
	_calls = []
	_keep = {"consent": Save.data.get("consent", ""), "survey": (Save.data.get("survey", {}) as Dictionary).duplicate(true),
		"analytics": Settings.analytics, "surveys": Settings.surveys}
	Save.data["survey"] = {}
	Settings.analytics = true
	Settings.surveys = true
	Run.arena = false


func after_test() -> void:
	Save.data["consent"] = _keep["consent"]
	Save.data["survey"] = _keep["survey"]
	Settings.analytics = _keep["analytics"]
	Settings.surveys = _keep["surveys"]


func _client(gate: bool = false) -> Node:
	DirAccess.make_dir_recursive_absolute(DIR)
	var a: Node = auto_free(AnalyticsScript.new())
	a.test_mode = true
	a.test_consent_gate = gate
	a.queue_path = DIR.path_join("analytics_queue.json")
	a.survey_cache_path = DIR.path_join("surveys_cache.json")
	a.set_config({"host": "https://eu.i.posthog.com", "key": KEY, "enabled": true})
	a.sender = func(url: String, body: String) -> void: _calls.append({"url": url, "body": body})
	a.new_session()
	return a


## PostHog's /api/surveys answer, as the endpoint gives it: one running survey with five questions (a link the game
## cannot draw), one not launched, one ended, one archived.
func _posthog_surveys() -> Dictionary:
	return {"surveys": [
		{"id": "s-run", "name": "After a run", "type": "api", "start_date": "2026-10-07T10:00:00Z", "end_date": null,
			"questions": [
				{"id": "q1", "type": "rating", "question": "How much fun was that run?", "scale": 5, "display": "number",
					"lowerBoundLabel": "Not fun", "upperBoundLabel": "Loved it", "optional": false},
				{"id": "q2", "type": "single_choice", "question": "What would make the next run better?",
					"choices": ["More weapons", "More creatures", "Harder", "Easier"]},
				{"id": "q3", "type": "link", "question": "Join the Discord", "link": "https://example.org"},
				{"id": "q4", "type": "multiple_choice", "question": "What did you use?", "choices": ["Chests", "Strongbox"]},
				{"id": "q5", "type": "open", "question": "Anything else?", "optional": true}]},
		{"id": "s-draft", "name": "Draft", "type": "api", "start_date": null, "questions": [{"id": "x", "type": "open", "question": "?"}]},
		{"id": "s-ended", "name": "Old", "type": "api", "start_date": "2026-09-01T00:00:00Z", "end_date": "2026-09-30T00:00:00Z",
			"questions": [{"id": "y", "type": "open", "question": "?"}]},
		{"id": "s-archived", "name": "Gone", "type": "api", "start_date": "2026-09-01T00:00:00Z", "archived": true,
			"questions": [{"id": "z", "type": "open", "question": "?"}]},
	]}


# ---------------------------------------------------------------- the player

func test_a_player_name_reads_well_and_follows_the_id() -> void:
	var n: String = Save.name_for("0f1c8e2a-6d3b-4a7f-9b1e-2c5d8a9e4f10")
	assert_str(n).is_equal(Save.name_for("0f1c8e2a-6d3b-4a7f-9b1e-2c5d8a9e4f10"))
	var re := RegEx.create_from_string("^[A-Z][a-z]+ [A-Z][a-z]+ [1-9][0-9]$")
	assert_object(re.search(n)).is_not_null()
	assert_str(Save.name_for("another-id")).is_not_equal(n)
	assert_str(Save.player_name()).is_equal(Save.name_for(Save.install_id()))


func test_a_wipe_keeps_the_player_and_takes_the_progress() -> void:
	Save.dir = DIR
	Save.data = Save._default()
	var id: String = Save.install_id()
	var name: String = Save.player_name()
	Save.set_consent("yes")
	Save.survey_state()["answered"] = ["s-run"]
	Save.data["gold"] = 500
	Save.wipe()
	assert_str(Save.install_id()).is_equal(id)
	assert_str(Save.player_name()).is_equal(name)
	assert_str(Save.consent()).is_equal("yes")
	assert_array(Save.survey_state().get("answered", [])).contains(["s-run"])
	assert_int(Save.gold()).is_equal(0)
	Save.dir = _save_dir
	Save.load_save()


func test_events_make_a_person_with_the_player_name() -> void:
	var a := _client()
	var props: Dictionary = a.person_properties()
	assert_str(str(props["player_name"])).is_equal(Save.player_name())
	assert_bool(props.has("label")).override_failure_message("the game must never write Garry's label").is_false()
	assert_bool(a.track("app_open", {"$set": props})).is_true()
	var p: Dictionary = a.queue[0]["properties"]
	assert_bool(p.has("$process_person_profile")).is_false()
	assert_str(str(p["$set"]["player_name"])).is_equal(Save.player_name())


func test_settings_shows_the_name_by_the_version() -> void:
	var line: String = preload("res://ui/SettingsScreen.gd").version_line()
	assert_str(line).contains(Save.player_name())
	assert_str(line).contains(str(ProjectSettings.get_setting("application/config/version")))


# ---------------------------------------------------------------- the play-data card

func test_nothing_leaves_before_the_card_is_answered_and_yes_sends_it() -> void:
	Save.data["consent"] = ""
	var a := _client(true)
	assert_bool(a.awaiting_consent()).is_true()
	assert_bool(a.track("app_open", {})).is_true()
	assert_bool(a.flush()).is_false()
	assert_int(_calls.size()).is_equal(0)
	a.answer_consent(true)
	assert_str(Save.consent()).is_equal("yes")
	assert_bool(Settings.analytics).is_true()
	assert_int(_calls.size()).is_equal(1)
	var batch: Array = JSON.parse_string(str(_calls[0]["body"]))["batch"]
	var names := batch.map(func(e): return str(e["event"]))
	assert_array(names).contains(["app_open", "consent"])
	var consent: Dictionary = batch[names.find("consent")]["properties"]
	assert_bool(bool(consent["accepted"])).is_true()
	assert_str(str(consent["$set"]["player_name"])).is_equal(Save.player_name())


func test_no_thanks_deletes_what_waited_and_turns_the_switch_off() -> void:
	Save.data["consent"] = ""
	var a := _client(true)
	a.track("app_open", {})
	a.answer_consent(false)
	assert_str(Save.consent()).is_equal("no")
	assert_bool(Settings.analytics).is_false()
	assert_int(a.queue.size()).is_equal(0)
	assert_int(_calls.size()).is_equal(0)


func test_the_card_never_comes_in_a_tool_or_the_test_runner() -> void:
	Save.data["consent"] = ""
	assert_bool(Analytics.consent_needed()).is_false()


func test_the_card_says_what_goes_and_ok_answers_it() -> void:
	Save.data["consent"] = ""
	var host: Control = auto_free(Control.new())
	add_child(host)
	var card: Control = WConsentScript.open(host)
	assert_str(WConsentScript.body_text(Save.player_name())).contains(Save.player_name())
	var accept: WButton = card.find_child("Accept", true, false)
	var decline: WButton = card.find_child("Decline", true, false)
	assert_object(accept).is_not_null()
	assert_object(decline).is_not_null()
	accept.pressed.emit()
	assert_bool(card.call("is_done")).is_true()
	assert_str(Save.consent()).is_equal("yes")


# ---------------------------------------------------------------- surveys

func test_only_running_surveys_and_drawable_questions_are_kept() -> void:
	var a := _client()
	assert_int(a.set_surveys_from(_posthog_surveys())).is_equal(1)
	var sv: Dictionary = a.surveys[0]
	assert_str(str(sv["id"])).is_equal("s-run")
	var types: Array = (sv["questions"] as Array).map(func(q): return str(q["type"]))
	assert_array(types).is_equal(["rating", "single_choice", "multiple_choice", "open"])
	assert_str(str(sv["questions"][0]["lower"])).is_equal("Not fun")
	assert_int(int(sv["questions"][0]["scale"])).is_equal(5)
	# junk is no survey
	assert_int(a.set_surveys_from("nonsense")).is_equal(0)
	assert_int(a.set_surveys_from({"surveys": [{"id": "q", "start_date": "2026-01-01", "questions": [{"type": "link"}]}]})).is_equal(0)
	# the cache keeps them for a run with no network
	a.set_surveys_from(_posthog_surveys())
	a.save_survey_cache()
	var b := _client()
	b.load_survey_cache()
	assert_int(b.surveys.size()).is_equal(1)


func test_the_url_asks_posthog_with_the_project_key() -> void:
	var a := _client()
	assert_str(a.surveys_url()).is_equal("https://eu.i.posthog.com/api/surveys/?token=" + KEY)


func test_a_survey_comes_every_few_runs_once_a_session_until_answered() -> void:
	var a := _client()
	a.set_surveys_from(_posthog_surveys())
	# a run under a minute does not count
	assert_dict(a.survey_after_run(30.0)).is_empty()
	# the first counted run of an install brings it
	assert_str(str(a.survey_after_run(90.0).get("id", ""))).is_equal("s-run")
	# never twice in a session
	assert_dict(a.survey_after_run(90.0)).is_empty()
	# a later session: again every SURVEY_EVERY counted runs
	var b := _client()
	b.surveys = a.surveys
	for k in AnalyticsScript.SURVEY_EVERY - 2:
		assert_dict(b.survey_after_run(90.0)).is_empty()
	var sv: Dictionary = b.survey_after_run(90.0)
	assert_str(str(sv.get("id", ""))).is_equal("s-run")
	# answered, it never comes again
	b.survey_sent(sv, {"q1": 4})
	var c := _client()
	c.surveys = a.surveys
	for k in AnalyticsScript.SURVEY_EVERY + 1:
		assert_dict(c.survey_after_run(90.0)).is_empty()


func test_survey_sent_speaks_posthogs_language() -> void:
	var a := _client()
	a.set_surveys_from(_posthog_surveys())
	var sv: Dictionary = a.surveys[0]
	var p: Dictionary = a.survey_sent(sv, {"q1": 4, "q2": "Harder", "q4": ["Chests"], "q5": "More hats"})
	assert_str(str(p["$survey_id"])).is_equal("s-run")
	assert_int(int(p["$survey_response_q1"])).is_equal(4)
	assert_str(str(p["$survey_response_q2"])).is_equal("Harder")
	assert_array(p["$survey_response_q4"]).is_equal(["Chests"])
	assert_bool(bool(p["$survey_completed"])).is_true()
	assert_bool(bool(p["$set"]["$survey_responded/s-run"])).is_true()
	assert_int((p["$survey_questions"] as Array).size()).is_equal(4)
	assert_str(str(a.queue.back()["event"])).is_equal("survey sent")
	a.survey_shown(sv)
	assert_str(str(a.queue.back()["event"])).is_equal("survey shown")
	a.survey_dismissed(sv)
	assert_str(str(a.queue.back()["event"])).is_equal("survey dismissed")
	assert_bool(bool(a.queue.back()["properties"]["$set"]["$survey_dismissed/s-run"])).is_true()


func test_dont_ask_me_again_is_seen_in_posthog_and_stops_them() -> void:
	var a := _client()
	a.set_surveys_from(_posthog_surveys())
	a.set_surveys(false, "card")
	assert_bool(Settings.surveys).is_false()
	var e: Dictionary = a.queue.back()
	assert_str(str(e["event"])).is_equal("survey_opt_out")
	assert_str(str(e["properties"]["where"])).is_equal("card")
	assert_bool(bool(e["properties"]["$set"]["surveys_opt_out"])).is_true()
	assert_dict(a.survey_after_run(90.0)).is_empty()
	a.set_surveys(true, "settings")
	assert_str(str(a.queue.back()["event"])).is_equal("survey_opt_in")


func test_the_card_asks_one_question_a_page_and_sends_the_answers() -> void:
	var a := _client()
	a.set_surveys_from(_posthog_surveys())
	var host: Control = auto_free(Control.new())
	add_child(host)
	var card: Control = WSurveyScript.open(host, a.surveys[0])
	var how := [""]
	card.connect("finished", func(h: String): how[0] = h)
	var next_btn: WButton = card.find_child("Next", true, false)
	assert_object(card.find_child("NotNow", true, false)).is_not_null()
	assert_object(card.find_child("NeverAsk", true, false)).is_not_null()
	# a rating: nothing picked, no way on
	assert_bool(card.call("can_go_on")).is_false()
	(card.find_child("Rate4", true, false) as WButton).pressed.emit()
	assert_bool(card.call("can_go_on")).is_true()
	card.call("next")
	assert_int(int(card.get("page"))).is_equal(1)
	# a single choice
	(card.find_child("Choice2", true, false) as WButton).pressed.emit()
	assert_bool(card.call("is_marked", card.find_child("Choice2", true, false))).is_true()
	card.call("next")
	# a multiple choice: two picked, one taken back
	(card.find_child("Choice0", true, false) as WButton).pressed.emit()
	(card.find_child("Choice1", true, false) as WButton).pressed.emit()
	(card.find_child("Choice1", true, false) as WButton).pressed.emit()
	card.call("next")
	# an optional text can be left empty; the last page sends
	assert_bool(card.call("can_go_on")).is_true()
	assert_object(card.find_child("Answer", true, false)).is_not_null()
	card.call("next")
	assert_str(how[0]).is_equal("sent")
	assert_dict(card.get("answers")).is_equal({"q1": 4, "q2": "Harder", "q4": ["Chests"]})
	assert_bool(next_btn.visible).is_false()
	# answered: the save remembers it
	assert_array(Save.survey_state().get("answered", [])).contains(["s-run"])


func test_not_now_dismisses_without_sending() -> void:
	var a := _client()
	a.set_surveys_from(_posthog_surveys())
	var host: Control = auto_free(Control.new())
	add_child(host)
	var card: Control = WSurveyScript.open(host, a.surveys[0])
	var how := [""]
	card.connect("finished", func(h: String): how[0] = h)
	(card.find_child("NotNow", true, false) as WButton).pressed.emit()
	assert_str(how[0]).is_equal("dismissed")
	assert_array(Save.survey_state().get("answered", [])).not_contains(["s-run"])
