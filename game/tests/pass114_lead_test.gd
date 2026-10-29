extends GdUnitTestSuite

## Pass 114 (the lead): a run's replay and record parts leave the phone at once. Garry's first phone replay (2026-10-29,
## a 10:50 Drifter run on 0.97) never reached PostHog: the run_record went with the run's end, the run_replay parts were
## queued about a second later and waited for the 30 s beat, and the phone was put away first. Now queuing either sends
## at once when nothing is on the wire, else 1 s after the request on it ends, until the queue is empty. No network: the
## client's sender only writes down what it was handed.

const AnalyticsScript := preload("res://core/autoload/Analytics.gd")
const DIR := "user://test_saves/pass114_lead"
const KEY := "phc_testtesttesttesttest"

var _calls: Array = []


func before_test() -> void:
	_calls = []
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Run.arena = false
	Settings.analytics = true


func after_test() -> void:
	Run.end()
	if DirAccess.dir_exists_absolute(DIR):
		for f in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(DIR.path_join(f))


func _client() -> Node:
	DirAccess.make_dir_recursive_absolute(DIR)
	var a: Node = auto_free(AnalyticsScript.new())
	a.test_mode = true
	a.queue_path = DIR.path_join("analytics_queue.json")
	a.set_config({"host": "https://eu.i.posthog.com/", "key": KEY, "enabled": true})
	a.sender = func(url: String, body: String) -> void: _calls.append({"url": url, "body": body})
	a.new_session()
	return a


## A recording about the size of a phone's 10-minute one: incompressible noise, so it needs several parts.
func _big_json() -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 114
	var raw := PackedByteArray()
	raw.resize(260000)
	for i in range(raw.size()):
		raw[i] = rng.randi() & 255
	return JSON.stringify({"stamp": "2026-10-29T19-52-05", "frames": Marshalls.raw_to_base64(raw), "build": {"id": "0.97-x"}})


func test_a_replay_goes_at_once_and_every_part_follows() -> void:
	var a := _client()
	var n: int = a.run_replay(_big_json(), {"build_id": "0.97-x"})
	assert_int(n).is_greater(1)
	# sent now, not at the 30 s beat
	assert_int(_calls.size()).is_equal(1)
	# each answered request sends the next batch a second later until the queue is empty
	var guard := 0
	while not a.queue.is_empty() and guard < 20:
		guard += 1
		a.send_done(true, "HTTP 200", 200)
		if not a.queue.is_empty():
			assert_int(a._next_flush_ms - Time.get_ticks_msec()).is_less_equal(1000)
		a._next_flush_ms = 0
		a.flush()
	assert_bool(a.queue.is_empty()).is_true()
	var parts := 0
	for c: Dictionary in _calls:
		var body = JSON.parse_string(str(c["body"]))
		for e: Dictionary in body["batch"]:
			if str(e["event"]) == "run_replay":
				parts += 1
	assert_int(parts).is_equal(n)
	assert_bool(a._hurry).is_false()


func test_a_replay_queued_while_the_record_is_on_the_wire_goes_a_second_after_it() -> void:
	var a := _client()
	a.run_record(JSON.stringify({"stamp": "r", "samples": []}))
	assert_int(_calls.size()).is_equal(1)
	# the record's request has not come back yet: the replay waits for it, then goes a second later (not 30 s)
	a.run_replay(_big_json())
	assert_int(_calls.size()).is_equal(1)
	a.send_done(true, "HTTP 200", 200)
	assert_int(a._next_flush_ms - Time.get_ticks_msec()).is_less_equal(1000)
	assert_bool(a.queue.is_empty()).is_false()
