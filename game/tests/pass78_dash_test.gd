extends GdUnitTestSuite

## Pass 78, lane DASH (Garry: "save raw data in some kind of JSON or something like that and make it so that I'm able to
## download it. Then take that data and basically dress it up into one of my HTML reports"): the run's whole record goes
## to PostHog as run_record parts (core/autoload/Analytics.gd record_parts / run_record): its keys, a 25-minute run's size
## under the budget, gzip + base64 and back, parts joined in any order and refused when one is missing or wrong; sent
## only once the play-data card is answered yes, never from a tool, the test runner or with the switch off; a run the app
## was closed in after its checkpoint goes at the next launch as "killed"; a request stays under REQUEST_MAX. And the
## run sim's series mapping (game/tools/sim_run.gd series()) still gives the fixture the page's copy is checked against
## (tools/level_editor/testdata/dash78_series_*.json, selftest_DASH78). No network: every client has its own sender.

const AnalyticsScript := preload("res://core/autoload/Analytics.gd")
const SIM := preload("res://tools/sim_run.gd")
const FIXTURE := preload("res://tools/series_fixture.gd")
const DIR := "user://test_saves/pass78_dash"
const KEY := "phc_testtesttesttesttest"

var _calls: Array = []
var _save_dir := ""
var _keep: Dictionary = {}


func before() -> void:
	Save.flush()
	_save_dir = Save.dir


func after() -> void:
	Save.dir = _save_dir
	_clear()


func before_test() -> void:
	_clear()
	_calls = []
	_keep = {"consent": Save.data.get("consent", ""), "analytics": Settings.analytics}
	Save.data["consent"] = "yes"
	Settings.analytics = true
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.arena = false


func after_test() -> void:
	Save.data["consent"] = _keep["consent"]
	Settings.analytics = _keep["analytics"]
	Run.arena = false


func _clear() -> void:
	if DirAccess.dir_exists_absolute(DIR):
		for f in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(DIR.path_join(f))


func _client(gate: bool = false) -> Node:
	DirAccess.make_dir_recursive_absolute(DIR)
	var a: Node = auto_free(AnalyticsScript.new())
	a.test_mode = true
	a.test_consent_gate = gate
	a.queue_path = DIR.path_join("analytics_queue.json")
	a.pending_path = DIR.path_join("analytics_pending_run.json")
	a.set_config({"host": "https://eu.i.posthog.com", "key": KEY, "enabled": true})
	a.sender = func(url: String, body: String) -> void: _calls.append({"url": url, "body": body})
	a.new_session()
	return a


## The series fixture's record (a real tool run, tools/level_editor/testdata/dash78_series_in.json), or {} off the repo.
func _fixture_input() -> Dictionary:
	var path := FIXTURE.fixture_dir().path_join("dash78_series_in.json")
	if not FileAccess.file_exists(path):
		return {}
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK or not (j.data is Dictionary):
		return {}
	return j.data


## A 25-minute record: the fixture's real rows (a 4-minute tool run) laid end to end to 1500 seconds of play, each copy
## with its own seconds; the header and events as they were. Real rows compress as a played run does.
func _record_25min() -> Dictionary:
	var inp := _fixture_input()
	if inp.is_empty():
		return {}
	var rec: Dictionary = (inp["record"] as Dictionary).duplicate(true)
	var rows: Array = rec["samples"]
	var span := float(rows.size())
	var out: Array = []
	var k := 0
	while out.size() < 1500:
		for r in rows:
			if out.size() >= 1500:
				break
			var c: Dictionary = (r as Dictionary).duplicate(true)
			c["t"] = snappedf(float(c.get("t", 0.0)) + span * k, 0.1)
			c["clock"] = snappedf(float(c.get("clock", 0.0)) + span * k, 0.1)
			out.append(c)
		k += 1
	rec["samples"] = out
	rec["length"] = 1500.0
	return rec


# ---------------------------------------------------------------- the parts

func test_parts_keys_and_round_trip() -> void:
	var rec := _record_25min()
	if rec.is_empty():
		push_warning("pass78: the series fixture is not beside the project: skipped")
		return
	var json := JSON.stringify(rec)
	var parts: Array = AnalyticsScript.record_parts(json)
	assert_int(parts.size()).is_greater(0)
	var b64_total := 0
	for p in parts:
		var d: Dictionary = p
		for k in ["part", "parts", "data", "enc", "format", "raw_bytes", "gz_bytes", "md5"]:
			assert_bool(d.has(k)).override_failure_message("a part lacks " + k).is_true()
		assert_int(str(d["data"]).length()).is_less_equal(AnalyticsScript.RECORD_PART_MAX)
		assert_int(int(d["parts"])).is_equal(parts.size())
		assert_str(str(d["enc"])).is_equal("gzip+base64")
		b64_total += str(d["data"]).length()
	# the budget: a 25-minute run in at most 3 parts (~300 KB of base64; PostHog takes 1 MB an event, 20 MB a request)
	assert_int(parts.size()).override_failure_message("a 25-minute record took %d parts (%d chars)" % [parts.size(), b64_total]).is_less_equal(3)
	print("pass78: a 25-minute record: %d chars of JSON -> %d gzip -> %d base64 in %d parts" % [json.length(), int(parts[0]["gz_bytes"]), b64_total, parts.size()])
	# back together, in any order
	var shuffled: Array = parts.duplicate()
	shuffled.reverse()
	assert_str(AnalyticsScript.record_join(shuffled)).is_equal(json)
	assert_str(AnalyticsScript.record_join(parts)).is_equal(json)


func test_parts_small_record_and_refusals() -> void:
	var json := JSON.stringify({"schema": 2, "hero": "astro", "samples": [{"t": 1.0, "hp": 100.0}], "events": [], "note": "héros ✓"})
	var parts: Array = AnalyticsScript.record_parts(json, 40)
	assert_int(parts.size()).is_greater(1)
	assert_str(AnalyticsScript.record_join(parts)).is_equal(json)
	# a part missing, a part cut short, the md5 wrong: nothing comes back (a part changed inside is the downloader's
	# check, selftest_DASH78: zlib prints an engine error here on a broken stream)
	var missing: Array = parts.slice(1)
	assert_str(AnalyticsScript.record_join(missing)).is_equal("")
	var short: Array = parts.duplicate(true)
	short[0]["data"] = str(short[0]["data"]).substr(4)
	assert_str(AnalyticsScript.record_join(short)).is_equal("")
	var wrong: Array = parts.duplicate(true)
	for p in wrong:
		p["md5"] = "0"
	assert_str(AnalyticsScript.record_join(wrong)).is_equal("")
	assert_str(AnalyticsScript.record_join([])).is_equal("")
	# one part for a small record at the real size
	assert_int(AnalyticsScript.record_parts(json).size()).is_equal(1)
	# past the parts' cap: nothing (run_record then sends it without its rows)
	assert_array(AnalyticsScript.record_parts(json, 10, 2)).is_empty()


# ---------------------------------------------------------------- what is sent, and when

func test_run_record_goes_with_the_runs_properties() -> void:
	var a := _client()
	assert_bool(a.run_begin("rid-78")).is_true()
	var json := JSON.stringify({"schema": 2, "run_id": "rid-78", "result": "death", "samples": [{"t": 1.0}], "events": []})
	var n: int = a.run_record(json)
	assert_int(n).is_equal(1)
	var recs: Array = a.queue.filter(func(e): return str(e["event"]) == "run_record")
	assert_int(recs.size()).is_equal(1)
	var p: Dictionary = recs[0]["properties"]
	assert_str(str(p["run_id"])).is_equal("rid-78")
	assert_str(str(p["hero"])).is_equal("astro")
	assert_bool(p.has("dev")).is_true()
	assert_str(str(p["distinct_id"])).is_equal(Save.install_id())
	assert_int(int(p["part"])).is_equal(1)
	assert_int(int(p["parts"])).is_equal(1)
	assert_bool(p.has("trimmed")).is_false()
	assert_str(AnalyticsScript.record_join([p])).is_equal(json)
	# Garry's email never goes: nothing in the event looks like an address
	assert_bool(JSON.stringify(recs[0]).contains("@")).is_false()


func test_only_with_consent() -> void:
	var a := _client(true)
	Save.data["consent"] = ""
	assert_bool(a.awaiting_consent()).is_true()
	a.run_begin("rid-c")
	a.run_record(JSON.stringify({"schema": 2, "samples": [], "events": []}))
	# it waits in memory: nothing on the wire, nothing on disk
	assert_bool(a.flush()).is_false()
	assert_int(_calls.size()).is_equal(0)
	assert_bool(FileAccess.file_exists(a.queue_path)).is_false()
	# "No thanks": everything that waited is gone
	a.purge()
	assert_int(a.queue.size()).is_equal(0)
	# a yes: the record goes with the rest (pass 114: at once, as it is queued, not at the next flush)
	Save.data["consent"] = "yes"
	a.run_record(JSON.stringify({"schema": 2, "samples": [], "events": []}))
	assert_int(_calls.size()).is_equal(1)
	assert_bool(str(_calls[0]["body"]).contains("\"run_record\"")).is_true()


func test_never_from_a_tool_the_test_runner_or_switched_off() -> void:
	# the autoload in this process is the test runner's: blocked, so the recorder's calls queue nothing
	assert_str(Analytics.runtime_block()).is_not_empty()
	var queued: int = Analytics.queue.size()
	assert_int(Analytics.run_record(JSON.stringify({"schema": 2, "samples": [], "events": []}))).is_equal(0)
	assert_int(Analytics.queue.size()).is_equal(queued)
	# a client of our own that is not in test mode reads the process: the test runner, blocked
	var b: Node = auto_free(AnalyticsScript.new())
	b.queue_path = DIR.path_join("q2.json")
	b.set_config({"host": "https://eu.i.posthog.com", "key": KEY, "enabled": true})
	b.sender = func(url: String, body: String) -> void: _calls.append({"url": url, "body": body})
	assert_int(b.run_record("{\"schema\":2}")).is_equal(0)
	assert_int(b.queue.size()).is_equal(0)
	# the switch off, the arena, no key: nothing
	var a := _client()
	Settings.analytics = false
	assert_int(a.run_record("{\"schema\":2}")).is_equal(0)
	Settings.analytics = true
	Run.arena = true
	assert_int(a.run_record("{\"schema\":2}")).is_equal(0)
	Run.arena = false
	var c := _client()
	c.set_config({"host": "https://eu.i.posthog.com", "key": "", "enabled": true})
	assert_int(c.run_record("{\"schema\":2}")).is_equal(0)
	assert_int(_calls.size()).is_equal(0)


func test_killed_run_goes_at_the_next_launch() -> void:
	var a := _client()
	a.run_begin("rid-k")
	var path := DIR.path_join("2026-10-15T01-02-03.json")
	var rec := {"schema": 2, "run_id": "rid-k", "stamp": "2026-10-15T01-02-03", "result": "in_progress", "length": 61.0,
		"samples": [{"t": 1.0, "hp": 90.0}], "events": []}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(rec))
	f.close()
	a.note_checkpoint(path)
	assert_bool(FileAccess.file_exists(a.pending_path)).is_true()
	# the next launch: a new client, no run on
	var b := _client()
	var n: int = b.send_pending()
	assert_int(n).is_equal(1)
	assert_bool(FileAccess.file_exists(b.pending_path)).is_false()
	var p: Dictionary = b.queue.filter(func(e): return str(e["event"]) == "run_record")[0]["properties"]
	assert_str(str(p["run_id"])).is_equal("rid-k")
	assert_str(str(p["hero"])).is_equal("astro")
	assert_bool(bool(p["recovered"])).is_true()
	var back = JSON.parse_string(AnalyticsScript.record_join([p]))
	assert_str(str(back["result"])).is_equal("killed")
	assert_int((back["samples"] as Array).size()).is_equal(1)
	# a run that ended normally clears its note; a note whose run ended (not in_progress) sends nothing
	a.note_checkpoint(path)
	a.run_record(JSON.stringify(rec))
	assert_bool(FileAccess.file_exists(a.pending_path)).is_false()
	rec["result"] = "death"
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(rec))
	f.close()
	a.note_checkpoint(path)
	var c := _client()
	assert_int(c.send_pending()).is_equal(0)
	assert_bool(FileAccess.file_exists(c.pending_path)).is_false()


func test_request_stays_small() -> void:
	var big := "x".repeat(AnalyticsScript.RECORD_PART_MAX)
	var q: Array = []
	for i in range(5):
		q.append({"event": "run_record", "properties": {"data": big}})
	q.append({"event": "app_open", "properties": {"a": 1}})
	var n: int = AnalyticsScript.request_count(q, AnalyticsScript.BATCH_MAX, AnalyticsScript.REQUEST_MAX)
	assert_int(n).is_greater_equal(1)
	assert_int(n * (AnalyticsScript.RECORD_PART_MAX + 2048)).is_less_equal(AnalyticsScript.REQUEST_MAX)
	# small events: the batch cap as before; one event bigger than the cap still goes alone
	var small: Array = []
	for i in range(60):
		small.append({"event": "x", "properties": {"i": i}})
	assert_int(AnalyticsScript.request_count(small, 50, AnalyticsScript.REQUEST_MAX)).is_equal(50)
	assert_int(AnalyticsScript.request_count([{"event": "run_record", "properties": {"data": "y".repeat(500000)}}], 50, 1000)).is_equal(1)
	# the client's own flush keeps to it
	var a := _client()
	a.queue = q.duplicate(true)
	assert_bool(a.flush()).is_true()
	assert_int(str(_calls[0]["body"]).length()).is_less_equal(AnalyticsScript.REQUEST_MAX + 10000)


func test_recorder_sends_its_record_before_the_runs_end() -> void:
	# the wiring: finish() and a quit hand the record's text to run_record before run_finish clears the run's properties,
	# and a checkpoint leaves the note (the source, since the autoload is blocked in the test runner)
	var src := (load("res://core/systems/RunAnalytics.gd") as GDScript).source_code
	for head in ["func finish() -> void:", "func _exit_tree() -> void:"]:
		var body := _body(src, head)
		var at := body.find("Analytics.run_record(last_json)")
		assert_bool(at >= 0 and at < body.find("Analytics.run_finish(")).override_failure_message(head + " does not send the record before run_finish").is_true()
	assert_bool(_body(src, "func checkpoint() -> void:").contains("Analytics.note_checkpoint(")).is_true()
	assert_bool(_body(src, "func _write(index: bool) -> String:").contains("last_json = json")).is_true()


## A function's text: from its header to the next function.
func _body(src: String, head: String) -> String:
	var i := src.find(head)
	if i < 0:
		return ""
	var j := src.find("\nfunc ", i + head.length())
	return src.substr(i, (j if j > 0 else src.length()) - i)


# ---------------------------------------------------------------- the page's series mapping

func test_series_fixture_still_matches() -> void:
	var dir := FIXTURE.fixture_dir()
	var out_path := dir.path_join("dash78_series_out.json")
	if not FileAccess.file_exists(out_path):
		push_warning("pass78: the series fixture is not beside the project: skipped")
		return
	var res: Dictionary = FIXTURE.run_fixture(dir.path_join("dash78_series_in.json"))
	assert_str(str(res.get("ok", "?"))).is_equal("")
	var want = JSON.parse_string(FileAccess.get_file_as_string(out_path))
	var got = JSON.parse_string(JSON.stringify(res["series"], "", true, true))
	var why := _differs(want, got, "")
	assert_str(why).override_failure_message("game/tools/sim_run.gd series() no longer gives dash78_series_out.json (%s): run game/tools/series_fixture.gd, then make tools/level_editor/sim_avg.js series() match (selftest_DASH78)" % why).is_equal("")


func _differs(a, b, path: String) -> String:
	if a is Dictionary and b is Dictionary:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return path + ": keys differ"
		for k in a:
			if not (b as Dictionary).has(k):
				return path + "/" + str(k) + ": missing"
			var w := _differs(a[k], b[k], path + "/" + str(k))
			if w != "":
				return w
		return ""
	if a is Array and b is Array:
		if (a as Array).size() != (b as Array).size():
			return path + ": length"
		for i in range((a as Array).size()):
			var w := _differs(a[i], b[i], "%s[%d]" % [path, i])
			if w != "":
				return w
		return ""
	if (a is float or a is int) and (b is float or b is int):
		return "" if absf(float(a) - float(b)) <= 1e-9 * maxf(1.0, absf(float(a))) else "%s: %s vs %s" % [path, str(a), str(b)]
	return "" if str(a) == str(b) else "%s: %s vs %s" % [path, str(a), str(b)]
