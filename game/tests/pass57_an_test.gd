extends GdUnitTestSuite

## Pass 57, lane AN (Garry: "apparently the analytics .json is gone, can you bring it back, or some other place where I
## would need to put it the phc... key"): the PostHog client (core/autoload/Analytics.gd). The key file parses and an
## empty key sends nothing; headless and test runs never send; the install id is made once and kept (a wipe makes a new
## one); every event carries the super properties and, in a run, the run's; the queue saves and reloads, a failed send
## keeps its batch and backs off, a success clears it, a malformed batch is dropped, the queue is capped; the run
## recorder's events reach the client renamed, with its offers, its run_end and a run_summary folded from the rows; the
## arena sends nothing and Settings off deletes the queue. No network: every test's client has its own sender.

const AnalyticsScript := preload("res://core/autoload/Analytics.gd")
const DIR := "user://test_saves/pass57_an"
const KEY := "phc_testtesttesttesttest"

const FAKE_GAME := """extends Node
var enemies = null
var director = null
var player = null
var cards = null
"""

const FAKE_CARDS := """extends Control
signal chosen(card)
var _offer: Array = []
var path_mode := false
"""

var _calls: Array = []
var _save_dir := ""


func before() -> void:
	Save.flush()
	_save_dir = Save.dir


func after() -> void:
	Save.dir = _save_dir
	_clear()


func before_test() -> void:
	_clear()
	_calls = []
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.arena = false
	Settings.analytics = true
	RunAnalytics.I = null


func after_test() -> void:
	Settings.analytics = true
	Run.arena = false
	if Save.sandboxed():
		Save.end_sandbox()


func _clear() -> void:
	if DirAccess.dir_exists_absolute(DIR):
		for f in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(DIR.path_join(f))


## A client of our own: the runtime gate open (as on a phone), a key, its queue file in the test folder, and a sender
## that only writes down what it was handed.
func _client(enabled: bool = true, key: String = KEY) -> Node:
	DirAccess.make_dir_recursive_absolute(DIR)
	var a: Node = auto_free(AnalyticsScript.new())
	a.test_mode = true
	a.queue_path = DIR.path_join("analytics_queue.json")
	a.set_config({"host": "https://eu.i.posthog.com/", "key": key, "enabled": enabled})
	a.sender = func(url: String, body: String) -> void: _calls.append({"url": url, "body": body})
	a.new_session()
	return a


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func test_the_key_file_parses_and_an_empty_key_sends_nothing() -> void:
	var a: Node = auto_free(AnalyticsScript.new())
	a.test_mode = true
	a.load_config()
	# the shipped file: the EU host, no key, not enabled
	assert_bool(a.config_found).is_true()
	assert_str(a.host).is_equal("https://eu.i.posthog.com")
	assert_str(a.key).is_equal("")
	assert_bool(a.config_enabled).is_false()
	assert_bool(a.configured()).is_false()
	assert_str(a.block_reason()).is_equal("the key is empty")
	assert_bool(a.track("app_open", {})).is_false()
	assert_int(a.queue.size()).is_equal(0)
	# its note says where the key goes
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://config/analytics.json"))
	assert_bool(raw is Dictionary).is_true()
	assert_str(str(raw["note"])).contains("phc_")
	# a key with enabled false, a personal (secret) key, a missing file: nothing either
	a.set_config({"key": KEY, "enabled": false})
	assert_str(a.block_reason()).is_equal("enabled is false in the key file")
	a.set_config({"key": "phx_personalsecretkey", "enabled": true})
	assert_bool(a.key_ok()).is_false()
	assert_str(a.block_reason()).is_equal("the key is not a phc_ project key")
	a.load_config("res://config/no_such_file.json")
	assert_bool(a.config_found).is_false()
	assert_bool(a.active()).is_false()
	# a good one: the trailing slash goes, the batch endpoint follows
	var b := _client()
	assert_str(b.host).is_equal("https://eu.i.posthog.com")
	assert_str(b.endpoint()).is_equal("https://eu.i.posthog.com/batch/")
	assert_str(b.block_reason()).is_equal("")


func test_headless_and_test_runs_never_send() -> void:
	# the autoload in this run: the gate is shut whatever the key file says
	assert_str(Analytics.runtime_block()).is_not_equal("")
	assert_bool(Analytics.active()).is_false()
	assert_bool(Analytics.is_processing()).is_false()
	assert_int(Analytics.queue.size()).is_equal(0)
	# a client that is not a test's own, with a good key: still nothing
	var a: Node = auto_free(AnalyticsScript.new())
	a.set_config({"key": KEY, "enabled": true})
	a.sender = func(_u: String, _b: String) -> void: _calls.append(1)
	var why: String = a.runtime_block()
	assert_bool(why == "headless run" or why == "test runner" or why == "tool script").is_true()
	assert_bool(a.track("app_open", {"cold": true})).is_false()
	assert_bool(a.flush()).is_false()
	assert_int(_calls.size()).is_equal(0)
	# nor does it write a queue file (on the PC a tool must never touch the player's)
	DirAccess.make_dir_recursive_absolute(DIR)
	a.queue_path = DIR.path_join("blocked_queue.json")
	a.queue = [{"event": "x"}]
	a.save_queue()
	assert_bool(FileAccess.file_exists(a.queue_path)).is_false()


func test_the_install_id_is_made_once_and_kept() -> void:
	Save.dir = DIR
	Save.data = Save._default()
	assert_bool(Save.has_install_id()).is_false()
	var id := Save.install_id()
	# a UUID v4: 8-4-4-4-12 hex, version 4, variant 8..b
	var re := RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
	assert_object(re.search(id)).is_not_null()
	assert_str(Save.install_id()).is_equal(id)
	assert_bool(Save.save_now()).is_true()
	Save.load_save()
	assert_str(Save.install_id()).is_equal(id)
	# the arena's sandbox keeps it too (made inside it, it goes into the copy end_sandbox puts back)
	Save.data["install_id"] = ""
	Save.save_now()
	Save.begin_sandbox()
	var in_arena := Save.install_id()
	Save.end_sandbox()
	assert_str(Save.install_id()).is_equal(in_arena)
	# a wipe makes a new anonymous player
	Save.wipe()
	assert_bool(Save.has_install_id()).is_false()
	assert_str(Save.install_id()).is_not_equal(in_arena)
	Save.dir = _save_dir
	Save.load_save()


func test_events_carry_the_super_properties_and_the_run_ids() -> void:
	var a := _client()
	assert_bool(a.track("app_open", {"cold": true, "first_launch": false})).is_true()
	var e: Dictionary = a.queue[0]
	var p: Dictionary = e["properties"]
	for k in ["schema", "app_version", "os", "os_version", "device", "screen", "top_inset", "lang", "dev", "session_id",
			"$session_id", "distinct_id", "$lib", "$process_person_profile", "$geoip_disable"]:
		assert_bool(p.has(k)).override_failure_message("missing " + k).is_true()
	assert_int(int(p["schema"])).is_equal(1)
	assert_str(str(p["app_version"])).is_equal(str(ProjectSettings.get_setting("application/config/version")))
	assert_bool(bool(p["dev"])).is_true()   # the editor binary runs the tests
	assert_bool(bool(p["$process_person_profile"])).is_false()
	assert_str(str(p["distinct_id"])).is_equal(Save.install_id())
	assert_str(str(e["distinct_id"])).is_equal(Save.install_id())
	assert_str(str(p["session_id"])).is_equal(a.session_id)
	assert_bool(p.has("run_id")).is_false()
	assert_str(str(e["timestamp"])).ends_with("Z")
	# event ids and session ids are UUID v7 (time first)
	var re7 := RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
	assert_object(re7.search(str(e["uuid"]))).is_not_null()
	assert_object(re7.search(a.session_id)).is_not_null()
	# a run: run_start, then the run's events carry its id, hero, look, map and the map's Level Editor version
	var rid: String = AnalyticsScript.uuid7()
	assert_bool(a.run_begin(rid)).is_true()
	a.run_event({"t": 12.0, "clock": 12.0, "kind": "boss_start", "id": "tumbleweed_king"})
	var start: Dictionary = a.queue[1]
	assert_str(str(start["event"])).is_equal("run_start")
	assert_str(str(start["properties"]["start_weapon"])).is_equal(Registry.start_weapon_for(Run.character).id)
	assert_bool(start["properties"].has("talents")).is_true()
	var boss: Dictionary = a.queue[2]
	assert_str(str(boss["event"])).is_equal("boss_started")
	var bp: Dictionary = boss["properties"]
	assert_str(str(bp["run_id"])).is_equal(rid)
	assert_str(str(bp["hero"])).is_equal("astro")
	assert_str(str(bp["map"])).is_equal("red_canyon")
	assert_str(str(bp["boss"])).is_equal("tumbleweed_king")
	assert_int(int(bp["stage"])).is_equal(1)
	assert_float(float(bp["t"])).is_equal(12.0)
	assert_str(str(bp["hero_look"])).is_equal(Run.character.variant_def(Save.hero_look("astro")).look_code())
	var rev := str(bp["map_rev"])
	assert_int(rev.length()).is_equal(8)
	assert_str(a.map_rev(Run.map)).is_equal(rev)
	# the run over: the run's properties leave the next event
	a.run_finish({"result": "death"}, {"minutes": 0})
	a.track("app_background", {"session_s": 1, "in_run": false})
	assert_bool((a.queue.back() as Dictionary)["properties"].has("run_id")).is_false()


func test_the_queue_saves_and_reloads() -> void:
	var a := _client()
	for k in range(4):
		a.track("e%d" % k, {"k": k})
	assert_bool(FileAccess.file_exists(a.queue_path)).is_false()
	a.track("e4", {"k": 4})
	# the fifth event writes the file
	assert_bool(FileAccess.file_exists(a.queue_path)).is_true()
	a.track("e5", {"k": 5})
	a.save_queue()
	var b := _client()
	b.load_queue()
	assert_int(b.queue.size()).is_equal(6)
	assert_str(str(b.queue[5]["event"])).is_equal("e5")
	assert_int(int(b.queue[3]["properties"]["k"])).is_equal(3)
	# a file that does not read is dropped, not kept forever
	var f := FileAccess.open(a.queue_path, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	b.load_queue()
	assert_int(b.queue.size()).is_equal(0)
	assert_bool(FileAccess.file_exists(a.queue_path)).is_false()


func test_a_failed_send_keeps_the_batch_and_backs_off() -> void:
	var a := _client()
	for k in range(3):
		a.track("e%d" % k)
	assert_bool(a.flush()).is_true()
	assert_int(_calls.size()).is_equal(1)
	assert_str(str(_calls[0]["url"])).is_equal("https://eu.i.posthog.com/batch/")
	var body = JSON.parse_string(str(_calls[0]["body"]))
	assert_str(str(body["api_key"])).is_equal(KEY)
	assert_int((body["batch"] as Array).size()).is_equal(3)
	assert_bool(body.has("sent_at")).is_true()
	# one request at a time
	assert_int(a.in_flight()).is_equal(3)
	assert_bool(a.flush()).is_false()
	a.send_done(false, "network: cant_connect")
	assert_int(a.queue.size()).is_equal(3)
	assert_int(a.in_flight()).is_equal(0)
	assert_float(a.backoff()).is_equal(30.0)
	assert_float(a.retry_in()).is_greater(25.0)
	assert_bool(a.flush()).is_false()
	# each failure doubles the wait, to five minutes at most
	var waits: Array = []
	for k in range(5):
		a._retry_at_ms = 0
		assert_bool(a.flush()).is_true()
		a.send_done(false, "HTTP 503", 503)
		waits.append(a.backoff())
	assert_array(waits).is_equal([60.0, 120.0, 240.0, 300.0, 300.0])
	assert_int(a.queue.size()).is_equal(3)
	assert_bool(FileAccess.file_exists(a.queue_path)).is_true()


func test_a_success_clears_the_batch() -> void:
	var a := _client()
	for k in range(3):
		a.track("e%d" % k)
	a.flush()
	a.send_done(false, "network: timeout")
	a._retry_at_ms = 0
	a.flush()
	a.send_done(true, "HTTP 200", 200)
	assert_int(a.queue.size()).is_equal(0)
	assert_int(a.sent_session).is_equal(3)
	assert_float(a.backoff()).is_equal(0.0)
	assert_float(a.retry_in()).is_equal(0.0)
	assert_bool(FileAccess.file_exists(a.queue_path)).is_false()
	assert_str(a.last_status).is_equal("HTTP 200")
	# a long queue goes BATCH_MAX at a time; what came in while one was on the wire stays for the next
	var b := _client()
	b.queue = []
	for k in range(60):
		b.queue.append({"event": "x%d" % k, "properties": {}})
	assert_bool(b.flush()).is_true()
	var sent_batch: Array = JSON.parse_string(str(_calls.back()["body"]))["batch"]
	assert_int(sent_batch.size()).is_equal(AnalyticsScript.BATCH_MAX)
	b.track("late")
	b.send_done(true, "HTTP 200", 200)
	assert_int(b.queue.size()).is_equal(11)
	assert_str(str(b.queue[0]["event"])).is_equal("x50")
	assert_str(str(b.queue.back()["event"])).is_equal("late")


func test_a_malformed_batch_is_dropped_and_the_queue_is_capped() -> void:
	var a := _client()
	for k in range(4):
		a.track("e%d" % k)
	a.flush()
	a.send_done(false, "HTTP 400", 400)
	assert_int(a.queue.size()).is_equal(0)
	assert_int(a.dropped).is_equal(4)
	assert_float(a.backoff()).is_equal(0.0)
	# past QUEUE_CAP the oldest go
	a.queue = []
	for k in range(AnalyticsScript.QUEUE_CAP + 5):
		a.queue.append({"event": "x%d" % k})
	a._trim()
	assert_int(a.queue.size()).is_equal(AnalyticsScript.QUEUE_CAP)
	assert_str(str(a.queue[0]["event"])).is_equal("x5")
	assert_int(a.dropped).is_equal(9)


func test_the_run_recorders_events_are_renamed() -> void:
	var a := _client()
	a.run_begin("")
	var m: Array = a.map_event({"t": 3.0, "clock": 3.0, "kind": "offer", "id": "", "level": 4, "route": "path",
		"cards": ["a", "b"], "skipped": true, "left": 1, "decision_ms": 900, "weapon": "boomstick"})
	assert_str(str(m[0])).is_equal("path_offer")
	assert_str(str(m[1]["picked"])).is_equal("")
	assert_int(int(m[1]["skips_left"])).is_equal(1)
	assert_bool(m[1].has("route")).is_false()
	m = a.map_event({"kind": "offer", "id": "peashooter", "route": "level_up", "cards": ["peashooter"]})
	assert_str(str(m[0])).is_equal("level_up")
	assert_str(str(m[1]["picked"])).is_equal("peashooter")
	m = a.map_event({"kind": "mutation", "id": "fan_the_hammer", "level": 1, "weapon": "revolver", "hero": true, "via": "path"})
	assert_str(str(m[0])).is_equal("item_picked")
	assert_str(str(m[1]["item_kind"])).is_equal("mutation")
	assert_bool(bool(m[1]["hero_mutation"])).is_true()
	assert_bool(m[1].has("hero")).is_false()
	m = a.map_event({"kind": "chest", "id": "mend", "level": 2, "roll": "passive", "take": false, "skip": true, "left": 0, "boss": false})
	assert_str(str(m[0])).is_equal("chest_opened")
	assert_bool(bool(m[1]["taken"])).is_false()
	assert_bool(bool(m[1]["skipped"])).is_true()
	m = a.map_event({"kind": "death", "id": "goblin", "hit": "melee"})
	assert_str(str(m[0])).is_equal("player_died")
	assert_str(str(m[1]["killer"])).is_equal("goblin")
	assert_str(str(m[1]["killer_kind"])).is_equal("melee")
	assert_bool(m[1].has("weapons")).is_true()
	m = a.map_event({"kind": "portal", "level": 3, "extract": false})
	assert_str(str(m[1]["choice"])).is_equal("stay")
	m = a.map_event({"kind": "portal", "level": 1, "extract": false})
	assert_str(str(m[1]["choice"])).is_equal("continue")
	m = a.map_event({"kind": "portal", "level": 2, "extract": true})
	assert_str(str(m[1]["choice"])).is_equal("extract")
	# not sent on their own: the level reached, skips and rerolls (the offer carries them), small pickups (counted)
	for k in ["level", "skip", "reroll"]:
		assert_array(a.map_event({"kind": k})).is_empty()
	assert_array(a.map_event({"kind": "pickup", "id": "coin_bag", "small": true})).is_empty()
	assert_array(a.map_event({"kind": "pickup", "id": "coin_bag", "small": true})).is_empty()
	assert_int(int(a._run_small["coin_bag"])).is_equal(2)
	assert_str(str(a.map_event({"kind": "pickup", "id": "nuke", "small": false})[0])).is_equal("pickup_taken")


func test_run_summary_comes_out_of_the_rows() -> void:
	var rows: Array = []
	for t in range(1, 151):
		var r := {"t": float(t), "clock": float(t), "stage": 1 if t <= 120 else 2, "level": 1 + int(t / 30.0),
			"alive": 10 if t <= 60 else (20 if t <= 120 else 30), "cap": 25, "press": 100.0, "est_total": 12.5,
			"hp": 80.0, "hp_max": 100.0, "gold": t, "spawned": {"goblin": 1}, "dmg": {"peashooter": 10.0},
			"est": {"peashooter": 12.5}}
		if t % 2 == 0:
			r["killed"] = {"goblin": 1}
		if t == 30 or t == 90:
			r["took"] = {"goblin": 2.0}
			r["hits"] = 1
		if t == 100:
			r["hp"] = 20.0
		rows.append(r)
	var s := RunAnalytics.summary(rows)
	assert_int(int(s["minutes"])).is_equal(3)
	assert_int(int(s["bucket_s"])).is_equal(60)
	assert_array(s["m_secs"]).is_equal([60, 60, 30])
	assert_array(s["m_alive"]).is_equal([10, 20, 30])
	assert_array(s["m_cap"]).is_equal([25, 25, 25])
	assert_array(s["m_spawned"]).is_equal([60, 60, 30])
	assert_array(s["m_killed"]).is_equal([30, 30, 15])
	assert_array(s["m_dmg"]).is_equal([600, 600, 300])
	assert_array(s["m_est"]).is_equal([12.5, 12.5, 12.5])
	assert_array(s["m_press"]).is_equal([100, 100, 100])
	assert_array(s["m_took"]).is_equal([2.0, 2.0, 0.0])
	assert_array(s["m_hits"]).is_equal([1, 1, 0])
	assert_array(s["m_hp"]).is_equal([0.8, 0.2, 0.8])
	assert_array(s["m_low_s"]).is_equal([0, 1, 0])
	assert_array(s["m_level"]).is_equal([3, 5, 6])
	assert_array(s["m_stage"]).is_equal([1, 1, 2])
	assert_array(s["m_gold"]).is_equal([60, 120, 150])
	assert_int(int(s["dmg_by_weapon"]["peashooter"])).is_equal(1500)
	assert_int(int(s["est_by_weapon"]["peashooter"])).is_equal(1875)
	assert_int(int(s["spawned_by_creature"]["goblin"])).is_equal(150)
	assert_int(int(s["killed_by_creature"]["goblin"])).is_equal(75)
	assert_float(float(s["took_by_creature"]["goblin"])).is_equal(4.0)
	# every array as long as the run's minutes
	for k in s.keys():
		if str(k).begins_with("m_"):
			assert_int((s[k] as Array).size()).override_failure_message(str(k)).is_equal(3)
	# too big for an event: folded into two-minute buckets, then four, until it fits or is one bucket
	var small := RunAnalytics.fit_summary(rows, 300)
	assert_int(int(small["bucket_s"])).is_equal(240)
	assert_int(int(small["minutes"])).is_equal(1)
	assert_array(small["m_spawned"]).is_equal([150])
	assert_int(int(RunAnalytics.fit_summary(rows)["bucket_s"])).is_equal(60)
	# the top ten only
	var many := {}
	for k in range(14):
		many["w%d" % k] = float(k)
	assert_int(RunAnalytics._top(many, 10, 1.0).size()).is_equal(10)
	assert_bool(RunAnalytics._top(many, 10, 1.0).has("w0")).is_false()
	assert_dict(RunAnalytics.summary([])).contains_keys(["minutes", "m_alive"])


func test_the_recorder_hands_the_run_to_the_client() -> void:
	# the autoload, opened for this test like a phone's (its own sender, its queue in the test folder), shut after
	var keep_q: String = Analytics.queue_path
	var keep_sender: Callable = Analytics.sender
	Analytics.test_mode = true
	Analytics.queue_path = DIR.path_join("autoload_queue.json")
	Analytics.set_config({"key": KEY, "enabled": true})
	Analytics.sender = func(_u: String, _b: String) -> void: pass
	Analytics.queue = []
	Analytics.new_session()
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var cards := Control.new()
	cards.set_script(_script(FAKE_CARDS))
	cards.visible = false
	g.add_child(cards)
	g.cards = cards
	var ra := RunAnalytics.new()
	ra.mirror = false
	g.add_child(ra)
	ra.begin(g)
	ra._join_cards()
	var names := func() -> Array:
		var out: Array = []
		for e in Analytics.queue:
			out.append(str(e["event"]))
		return out
	assert_array(names.call()).contains(["run_start"])
	var rid := str(ra.header["run_id"])
	assert_int(rid.length()).is_equal(36)
	assert_int(str(ra.header["map_rev"]).length()).is_equal(8)
	# an offer: shown, a reroll and a banish on the way, a pick
	cards._offer = [{"id": "peashooter", "type": "weapon", "level_to": 2}, {"id": "mend", "type": "passive", "level_to": 1}]
	cards.visible = true
	ra.event("reroll")
	ra.event("banish", "magnet")
	cards.visible = false
	cards.chosen.emit({"id": "mend", "type": "passive", "level_to": 1})
	var offer: Dictionary = ra.events.back()
	assert_str(str(offer["kind"])).is_equal("offer")
	assert_str(str(offer["route"])).is_equal("level_up")
	assert_array(offer["cards"]).is_equal(["peashooter", "mend"])
	assert_int(int(offer["rerolls"])).is_equal(1)
	assert_array(offer["banished"]).is_equal(["magnet"])
	var lu: Dictionary = Analytics.queue.back()
	assert_str(str(lu["event"])).is_equal("level_up")
	assert_str(str(lu["properties"]["picked"])).is_equal("mend")
	assert_str(str(lu["properties"]["run_id"])).is_equal(rid)
	# an item waits for its est_after, then goes
	ra.via = "card"
	Run.add_or_level_passive("mend")
	var item: Dictionary = Analytics.queue.back()
	assert_str(str(item["event"])).is_equal("item_picked")
	assert_str(str(item["properties"]["id"])).is_equal("mend")
	assert_str(str(item["properties"]["via"])).is_equal("card")
	assert_bool(item["properties"].has("est_after")).is_true()
	# the death keeps its kind (pass 57: the hit kind had overwritten it)
	ra.took({"by": "Goblin", "id": "goblin", "kind": "melee"}, 10.0, 8.0, 0.0, "")
	ra.death()
	assert_str(str(ra.events.back()["kind"])).is_equal("death")
	assert_str(str(ra.events.back()["hit"])).is_equal("melee")
	assert_str(str(Analytics.queue.back()["properties"]["killer"])).is_equal("goblin")
	# the debug hand's item kind no longer replaces the event's
	ra.event("debug_item", "magnet", 2, {"kind": "passive"})
	assert_str(str(ra.events.back()["kind"])).is_equal("debug_item")
	assert_str(str(ra.events.back()["item_kind"])).is_equal("passive")
	# two seconds of rows, then the end: run_end and a run_summary
	ra.tick(1.0)
	ra.tick(1.0)
	ra.header["stamp"] = "test-p57-%d" % Time.get_ticks_usec()
	Run.died = true
	ra.finish()
	DirAccess.remove_absolute("user://analytics/runs/%s.json" % ra.header["stamp"])
	var tail: Array = names.call()
	assert_array(tail).contains(["run_end", "run_summary"])
	var end_e: Dictionary = Analytics.queue[tail.find("run_end")]
	assert_str(str(end_e["properties"]["result"])).is_equal("death")
	var sum_e: Dictionary = Analytics.queue[tail.find("run_summary")]
	assert_int(int(sum_e["properties"]["minutes"])).is_equal(1)
	assert_array(sum_e["properties"]["m_secs"]).is_equal([2])
	assert_bool(Analytics.in_run()).is_false()
	# every event under the size cap
	for e in Analytics.queue:
		assert_int(JSON.stringify(e).length()).is_less(AnalyticsScript.EVENT_MAX)
	g.remove_child(ra)
	ra.free()
	# shut again
	Analytics.queue = []
	Analytics.run_props = {}
	Analytics._in_flight = 0
	Analytics._since_save = 0
	Analytics._retry_at_ms = 0
	Analytics._backoff = 0.0
	Analytics.test_mode = false
	Analytics.queue_path = keep_q
	Analytics.sender = keep_sender
	Analytics.load_config()
	assert_bool(Analytics.active()).is_false()


func test_the_arena_sends_nothing() -> void:
	var a := _client()
	Run.arena = true
	assert_str(a.block_reason()).is_equal("the arena")
	assert_bool(a.track("app_open")).is_false()
	assert_bool(a.run_begin("")).is_false()
	Run.arena = false
	a.track("app_open")
	assert_int(a.queue.size()).is_equal(1)
	Save.begin_sandbox()
	assert_bool(a.flush()).is_false()
	assert_bool(a.track("app_background")).is_false()
	Save.end_sandbox()
	assert_int(_calls.size()).is_equal(0)
	assert_bool(a.flush()).is_true()
	# and a real arena game makes no recorder at all (Game: "if not arena ... RunAnalytics.create")
	assert_object(RunAnalytics.I).is_null()


func test_settings_off_deletes_the_queue() -> void:
	var a := _client()
	for k in range(6):
		a.track("e%d" % k)
	a.save_queue()
	assert_bool(FileAccess.file_exists(a.queue_path)).is_true()
	Settings.changed.connect(a._on_settings_changed)
	Settings.set_value("analytics", false)
	assert_int(a.queue.size()).is_equal(0)
	assert_bool(FileAccess.file_exists(a.queue_path)).is_false()
	assert_str(a.block_reason()).is_equal("switched off in Settings")
	assert_bool(a.track("e6")).is_false()
	assert_bool(a.send_now()).is_false()
	assert_str(a.last_status).contains("switched off")
	Settings.set_value("analytics", true)
	Settings.changed.disconnect(a._on_settings_changed)
	assert_bool(a.track("e7")).is_true()
	# the switch is kept in the save
	assert_bool(Settings.to_dict().has("analytics")).is_true()
	Settings.from_dict({"analytics": false})
	assert_bool(Settings.analytics).is_false()
	Settings.from_dict({"analytics": true})


func test_send_now_and_the_readout() -> void:
	var a := _client()
	assert_bool(a.send_now()).is_true()
	assert_int(a.manual_sends).is_equal(1)
	var body = JSON.parse_string(str(_calls.back()["body"]))
	assert_str(str(body["batch"][0]["event"])).is_equal("dev_ping")
	a.send_done(true, "HTTP 200", 200)
	var lines: PackedStringArray = a.status_lines()
	var text := "\n".join(lines)
	assert_str(text).contains("key: set")
	assert_str(text).contains("sending: yes")
	assert_str(text).contains("sent this session: 1")
	assert_str(text).contains("last send: HTTP 200")
	# never the key itself
	assert_str(text).not_contains(KEY)
	# the line under the Settings switch says what goes, or that the key file is empty
	assert_str(a.settings_line()).contains("no name")
	var empty := _client(true, "")
	assert_str(empty.settings_line()).contains("key file is empty")
	assert_str("\n".join(empty.status_lines())).contains("key: empty")


func test_fps_from_the_frame_clock() -> void:
	var ra: RunAnalytics = auto_free(RunAnalytics.new())
	assert_dict(ra.fps_stats()).is_empty()
	var h := PackedInt32Array()
	h.resize(RunAnalytics.FRAME_BINS)
	h[16] = 99
	h[40] = 1
	ra._frame_hist = h
	ra._frame_n = 100
	ra._frame_ms = 99 * 16.5 + 40.5
	var f := ra.fps_stats()
	assert_float(float(f["fps_avg"])).is_equal_approx(1000.0 * 100.0 / (99 * 16.5 + 40.5), 0.1)
	# the 1 % low is the slowest frame's bin
	assert_float(float(f["fps_low"])).is_equal_approx(1000.0 / 40.5, 0.1)
