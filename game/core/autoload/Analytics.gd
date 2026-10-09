## The PostHog client (pass 57, Garry: "apparently the analytics .json is gone, can you bring it back, or some other
## place where I would need to put it the phc... key"). One autoload: it reads the key file game/config/analytics.json
## (res://config/analytics.json, outside content/ so the Registry never scans it; the export ships every *.json),
## stamps every event with the super properties, keeps a queue in memory and in user://analytics_queue.json, and sends
## it to PostHog's batch endpoint (POST {host}/batch/ with {"api_key", "batch"}) every 30 s, at 20 events waiting, at
## a run's end and when the app leaves the screen: one request at a time, backing off 30 s, 60 s, ... 5 min after a
## failure, the oldest dropped past 2000 waiting.
## A run's story comes from the run recorder (core/systems/RunAnalytics.gd, pass 45): its events, renamed for PostHog
## here (KIND_EVENTS, map_event), run_start, run_end and one run_summary with the per-minute series Garry's local
## dashboard charts. The app itself sends app_open and app_background.
## It never sends from a headless run, a tool's script (smoke runs, captures, touch_audit), the gdUnit runner, the debug
## arena, or with Settings.analytics off; a missing key file, an empty key, a key that is not a phc_ project key or
## "enabled": false means nothing is sent and nothing is queued. Runs from the editor binary, debug builds and runs with
## the player's debug mode on do send, tagged dev: true (Garry is the only player now; the dashboards filter dev = false
## once there are others).
## Pass 59 (Garry: "I want to be able to Identify the Player who is playing and view only their behaviour"): person
## profiles are on, so every install is a Person in PostHog under its install id, named by `Save.player_name()` ("Dusty
## Coyote 41", sent as the person property player_name, shown in Settings by the version); Garry labels a person in
## PostHog with his own `label` property, which the game never writes. Nothing leaves before the play-data card
## (ui/wanted/WConsent.gd, on the title the first time a build with a key starts) is answered: events wait in memory,
## "No thanks" deletes them and turns the switch off. End-of-run surveys come from PostHog Surveys in API mode
## (`fetch_surveys`: GET {host}/api/surveys/?token=<key>, cached in user://surveys_cache.json): the Results screen asks
## `survey_after_run` and draws the questions itself (ui/wanted/WSurvey.gd), sending PostHog's own "survey shown",
## "survey sent" and "survey dismissed"; "Don't ask me again" and Settings' switch send survey_opt_out / survey_opt_in
## and set the person property surveys_opt_out. No account, no advertising id, and PostHog's IP location is switched
## off on every event ($geoip_disable).
extends Node

## A send finished (the developer menu refreshes its readout).
signal sent(ok: bool)

const SCHEMA := 1
const LIB := "88fits-godot"
const CONFIG_PATH := "res://config/analytics.json"
const DEFAULT_HOST := "https://eu.i.posthog.com"
const QUEUE_PATH := "user://analytics_queue.json"
const FLUSH_EVERY_MS := 30000
const FLUSH_AT := 20
const SAVE_EVERY := 5
## Events in one request (a run's events are a few hundred bytes each, its summary a few KB).
const BATCH_MAX := 50
const QUEUE_CAP := 2000
const BACKOFF_FIRST := 30.0
const BACKOFF_MAX := 300.0
## Five minutes in the background and the next open is a new session.
const SESSION_GAP := 300.0
## Every event stays under ~32 KB (the biggest is the run summary, a few KB for a twenty-minute run).
const EVENT_MAX := 32000
## The first send after launch waits this long, so last time's queue and this app_open go together.
const LAUNCH_SEND_MS := 3000
const HTTP_TIMEOUT := 20.0
## The active surveys as last fetched (pass 59), so a survey can come with no network at the run's end.
const SURVEYS_PATH := "user://surveys_cache.json"
## A survey comes at most once every SURVEY_EVERY runs of at least SURVEY_MIN_RUN seconds, never twice in one session,
## and each survey only until the player answers it (the first qualifying run of an install can bring one).
const SURVEY_EVERY := 3
const SURVEY_MIN_RUN := 60.0
## The question types the game can draw; a survey with none of them is skipped, a question of another type (a link) is
## left out.
const SURVEY_TYPES := ["rating", "single_choice", "multiple_choice", "open"]

## The run recorder's event kinds and the PostHog events they become. A kind not here stays in the local record only:
## "level" (each level reached: the settled offer carries it), "skip" and "reroll" (folded into the offer they belong
## to). "offer" is level_up, or path_offer when the offer was a weapon's mutations; a small pickup (a cake slice, a coin
## bag) is counted into the run summary instead of sent on its own.
const KIND_EVENTS := {
	"weapon": "item_picked", "passive": "item_picked", "mutation": "item_picked", "perk": "item_picked",
	"evolution": "item_picked", "passive_evolution": "item_picked",
	"offer": "level_up", "banish": "card_banished", "chest": "chest_opened", "structure": "structure_used",
	"pickup": "pickup_taken", "boss_start": "boss_started", "boss_end": "boss_killed", "elite": "elite_spawned",
	"stage": "stage_started", "wave": "endless_wave", "portal_wait": "portal_reached", "portal": "stage_cleared",
	"death": "player_died", "revive": "revive_chosen", "unlock": "quest_completed", "debug_item": "debug_item",
}

# ---------------------------------------------------------------- the key file
var host := DEFAULT_HOST
var key := ""
var config_found := false
var config_enabled := false

# ---------------------------------------------------------------- the queue and the wire
var queue: Array = []
var queue_path := QUEUE_PATH
## Events PostHog took this session, events dropped (the cap, or a batch it refused as malformed), Send now taps.
var sent_session := 0
var dropped := 0
var manual_sends := 0
## The last send: its status ("HTTP 200", "network: cant_connect", ...) and when (unix seconds, 0 = never this session).
var last_status := ""
var last_send_unix := 0
## A test's own instance: the runtime gate is open (the arena and the switch still count) and the sender is its own.
var test_mode := false
## A test that checks the play-data card's gate turns it on (other tests' instances skip it).
var test_consent_gate := false
## The surveys PostHog says are running (pass 59): [{id, name, questions: [{id, type, question, description, optional,
## choices, scale, display, lower, upper}]}], from the cache at launch and from fetch_surveys after.
var surveys: Array = []
## The last survey fetch's answer ("HTTP 200 · 1 active", "network: ...", "" = none yet) for the developer menu.
var survey_status := ""
var survey_cache_path := SURVEYS_PATH
var _survey_http: HTTPRequest
var _survey_fetching := false
var _survey_this_session := false
## The one place a batch leaves the game: (url: String, body: String) -> void, answered by send_done(). A test puts its
## own Callable here (no network in tests).
var sender: Callable

# ---------------------------------------------------------------- who and when
var session_id := ""
## The run's super properties while one is on (run_id, hero, hero_look, map, map_rev); {} between runs.
var run_props: Dictionary = {}

var _http: HTTPRequest
var _in_flight := 0
## A request is on the wire (pass 58 review): kept apart from _in_flight, which counts the queued events that request
## carries; purge() and the queue cap can take those away while it is out, and a new request must still wait for it.
var _requesting := false
var _since_save := 0
var _next_flush_ms := 0
var _retry_at_ms := 0
var _backoff := 0.0
var _session_start := 0.0
var _bg_at := 0.0
var _map_revs: Dictionary = {}
## the properties that never change while the app runs (the app, the phone, the screen, the language), read once
var _fixed: Dictionary = {}
## runtime_block()'s answer, read once ("?" = not yet)
var _runtime := "?"
static var _crypto: Crypto
## small pickups of the run on (id -> count), handed to the run summary
var _run_small: Dictionary = {}


func _init() -> void:
	sender = _http_send


func _ready() -> void:
	# behind the pause menu, the cards and the reel the tree is paused; the clock and the wire keep going
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_config()
	# the saved gold's every move (pass 61): joined before the gate, so a test that opens this autoload hears it too;
	# track() still refuses a tool, the test runner and the arena's sandbox
	if not Save.gold_moved.is_connected(meta_gold):
		Save.gold_moved.connect(meta_gold)
	if runtime_block() != "":
		# a tool, a headless run or the test runner: nothing is sent, and the player's queue file is not touched
		set_process(false)
		return
	_http = HTTPRequest.new()
	_http.name = "Http"
	_http.timeout = HTTP_TIMEOUT
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	_survey_http = HTTPRequest.new()
	_survey_http.name = "SurveyHttp"
	_survey_http.timeout = HTTP_TIMEOUT
	add_child(_survey_http)
	_survey_http.request_completed.connect(_on_surveys_done)
	Settings.changed.connect(_on_settings_changed)
	load_queue()
	load_survey_cache()
	var first := not Save.has_install_id()
	new_session()
	track("app_open", {"cold": true, "first_launch": first, "runs": Save.total("runs"), "gold": Save.gold(),
		"$set": person_properties(), "$set_once": {"first_app_version": str(ProjectSettings.get_setting("application/config/version", ""))}})
	_next_flush_ms = Time.get_ticks_msec() + LAUNCH_SEND_MS
	if Save.consent() == "yes":
		fetch_surveys.call_deferred()


# ---------------------------------------------------------------- the key file and the gate

## Reads game/config/analytics.json: {"host", "key", "enabled", "note"}.
func load_config(path: String = CONFIG_PATH) -> void:
	host = DEFAULT_HOST
	key = ""
	config_enabled = false
	config_found = FileAccess.file_exists(path)
	if not config_found:
		return
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK or not (j.data is Dictionary):
		push_warning("Analytics: %s is not a JSON object" % path)
		return
	set_config(j.data)


## The key file's contents (a test hands its own): the host (no trailing slash), the key, whether it is enabled.
func set_config(d: Dictionary) -> void:
	var h := str(d.get("host", DEFAULT_HOST)).strip_edges().trim_suffix("/")
	host = h if h != "" else DEFAULT_HOST
	key = str(d.get("key", "")).strip_edges()
	config_enabled = bool(d.get("enabled", false))
	config_found = true


## A PostHog project API key: write-only, safe to ship. A personal API key (phx_...) is a secret and is refused.
func key_ok() -> bool:
	return key.begins_with("phc_") and key.length() > 8


## The key file says send.
func configured() -> bool:
	return config_found and config_enabled and key_ok()


func endpoint() -> String:
	return host + "/batch/"


## Why nothing can be sent from this process at all ("" = it can): a headless run, a tool's script (any --script or -s
## run: the smoke runs, the captures, touch_audit) or the gdUnit runner. A test's own instance skips it.
func runtime_block() -> String:
	if test_mode:
		return ""
	if _runtime == "?":
		_runtime = _read_runtime()
	return _runtime


## The process as it started (read once: it cannot change while it runs).
func _read_runtime() -> String:
	if DisplayServer.get_name() == "headless":
		return "headless run"
	for a in OS.get_cmdline_args():
		var s := str(a)
		if s.ends_with("GdUnitCmdTool.gd") or s.contains("gdUnit4"):
			return "test runner"
		if s == "-s" or s == "--script":
			return "tool script"
	var ml := Engine.get_main_loop()
	if ml != null and ml.get_script() != null:
		return "tool script"
	return ""


## The debug arena (Run.arena, and the save's sandbox it plays in) sends nothing and holds nothing back.
func in_arena() -> bool:
	return Run.arena or Save.sandboxed()


## Why nothing is sent right now ("" = events are queued and sent), in the order the developer menu says it.
func block_reason() -> String:
	if not config_found:
		return "no key file (%s)" % CONFIG_PATH
	if key == "":
		return "the key is empty"
	if not key_ok():
		return "the key is not a phc_ project key"
	if not config_enabled:
		return "enabled is false in the key file"
	if not Settings.analytics:
		return "switched off in Settings"
	var rb := runtime_block()
	if rb != "":
		return rb
	if in_arena():
		return "the arena"
	return ""


func active() -> bool:
	return block_reason() == ""


## Garry's own runs: the editor binary, a debug build, or the player's debug mode on.
func is_dev() -> bool:
	return OS.has_feature("editor") or OS.is_debug_build() or bool(Settings.debug_mode)


func in_run() -> bool:
	return not run_props.is_empty()


# ---------------------------------------------------------------- events

## Every event's super properties: the app, the phone, the session and, during a run, the run.
func super_properties() -> Dictionary:
	if _fixed.is_empty():
		var scr := DisplayServer.screen_get_size()
		_fixed = {"schema": SCHEMA, "app_version": str(ProjectSettings.get_setting("application/config/version", "")),
			"os": OS.get_name(), "os_version": OS.get_version(), "device": OS.get_model_name(),
			"screen": "%dx%d" % [scr.x, scr.y], "lang": OS.get_locale_language(),
			"$lib": LIB, "$lib_version": str(SCHEMA), "$geoip_disable": true}
	var did := Save.install_id()
	var p := _fixed.duplicate()
	p["top_inset"] = int(round(W.safe_top()))
	p["dev"] = is_dev()
	p["session_id"] = session_id
	p["$session_id"] = session_id
	p["distinct_id"] = did
	if not run_props.is_empty():
		p.merge(run_props, true)
		p["stage"] = Run.stage + 1
	return p


## Queues one event (nothing when block_reason() says why not). Returns whether it was queued.
func track(event: String, props: Dictionary = {}) -> bool:
	if not active():
		return false
	var p := super_properties()
	p.merge(props, true)
	var e := {"event": event, "distinct_id": str(p["distinct_id"]), "uuid": uuid7(), "timestamp": iso_now(), "properties": p}
	if JSON.stringify(e).length() > EVENT_MAX:
		_shrink(e)
	queue.append(e)
	_trim()
	_since_save += 1
	# to disk every SAVE_EVERY events while the queue is short; a long one (no network for a while) every 5 % of it, so a
	# big queue is not rewritten every few seconds (the background, a quit and a run's end always write it)
	if _since_save >= maxi(SAVE_EVERY, int(queue.size() / 20.0)):
		save_queue()
	if queue.size() - _in_flight >= FLUSH_AT:
		flush()
	return true


## An event past EVENT_MAX loses its biggest list or table properties, largest first, until it fits; "trimmed" names
## them.
func _shrink(e: Dictionary) -> void:
	var p: Dictionary = e["properties"]
	var cut: Array = []
	while JSON.stringify(e).length() > EVENT_MAX:
		var worst := ""
		var worst_n := 0
		for k in p.keys():
			if p[k] is Array or p[k] is Dictionary:
				var n := JSON.stringify(p[k]).length()
				if n > worst_n:
					worst = str(k)
					worst_n = n
		if worst == "":
			break
		p.erase(worst)
		cut.append(worst)
	p["trimmed"] = cut


func _trim() -> void:
	var over := queue.size() - QUEUE_CAP
	if over > 0:
		queue = queue.slice(over)
		_in_flight = maxi(_in_flight - over, 0)
		dropped += over


## A random UUID v7 (RFC 9562: the first 48 bits are the unix time in ms, so ids sort by time): sessions, runs, events.
static func uuid7() -> String:
	var ms := int(Time.get_unix_time_from_system() * 1000.0)
	if _crypto == null:
		_crypto = Crypto.new()
	var b := _crypto.generate_random_bytes(16)
	for i in range(6):
		b[i] = (ms >> (8 * (5 - i))) & 0xff
	b[6] = (b[6] & 0x0f) | 0x70
	b[8] = (b[8] & 0x3f) | 0x80
	var h := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]


## Now in UTC as PostHog reads it: 2026-10-07T18:42:07.125Z.
static func iso_now() -> String:
	var t := Time.get_unix_time_from_system()
	var s := int(floor(t))
	return Time.get_datetime_string_from_unix_time(s) + ".%03dZ" % clampi(int((t - float(s)) * 1000.0), 0, 999)


# ---------------------------------------------------------------- the session

func new_session() -> void:
	session_id = uuid7()
	_session_start = Time.get_unix_time_from_system()


func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_PAUSED and what != NOTIFICATION_APPLICATION_RESUMED and what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	if runtime_block() != "":
		return
	if what == NOTIFICATION_APPLICATION_PAUSED:
		went_background(false)
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		came_back()
	else:
		went_background(true)


## The phone took the app off the screen (or the window is closing): app_background, the queue to disk, a send tried.
func went_background(quit: bool) -> void:
	if _bg_at > 0.0 and not quit:
		return
	var p := {"session_s": int(Time.get_unix_time_from_system() - _session_start), "in_run": in_run()}
	if quit:
		p["quit"] = true
	track("app_background", p)
	_bg_at = Time.get_unix_time_from_system()
	save_queue()
	flush()


## Back on the screen: after SESSION_GAP away a new session and a warm app_open; either way a send is tried.
func came_back() -> void:
	if _bg_at <= 0.0:
		return
	var away := Time.get_unix_time_from_system() - _bg_at
	_bg_at = 0.0
	if away >= SESSION_GAP:
		new_session()
		track("app_open", {"cold": false, "first_launch": false, "away_s": int(away), "runs": Save.total("runs"), "gold": Save.gold()})
	flush()


# ---------------------------------------------------------------- the run (RunAnalytics hands these over)

## A run began (RunAnalytics.begin, with the id its local record keeps): the run's super properties and run_start.
## Returns whether it went out (nothing does from a tool, the test runner, the arena or with no key).
func run_begin(rid: String = "") -> bool:
	run_props = {}
	_run_small = {}
	if not active():
		return false
	var hero: CharacterDef = Run.character
	var mapdef: MapDef = Run.map
	if rid == "":
		rid = uuid7()
	run_props = {"run_id": rid, "hero": hero.id if hero else "", "hero_look": hero_look_of(hero),
		"map": mapdef.id if mapdef else "", "map_rev": map_rev(mapdef)}
	var talents := {}
	var forms := {}
	var all = Save.data.get("talents", {})
	if all is Dictionary:
		for id in (all as Dictionary).keys():
			var t = all[id]
			if t is Dictionary and int(t.get("rank", 0)) > 0:
				talents[str(id)] = int(t.get("rank", 0))
				forms[str(id)] = int(t.get("form", 0))
	var sw: WeaponDef = Registry.start_weapon_for(hero) if hero else null
	track("run_start", {"start_weapon": sw.id if sw else "", "talents": talents, "talent_forms": forms,
		"gold_before": Save.gold(), "runs_before": maxi(int(Save.data.get("runs_started", 1)) - 1, 0), "seed": Run.map_seed})
	return true


## One of the run recorder's events, renamed and sent (see KIND_EVENTS).
func run_event(e: Dictionary) -> void:
	if run_props.is_empty() or not active():
		return
	var m := map_event(e)
	if m.is_empty():
		return
	track(str(m[0]), m[1])


## [PostHog event, properties] for a run recorder event, or [] for one that is not sent on its own. The local record's
## keys mostly keep their names; `id` and `level` become what they mean where a bare id would mislead (the boss, the
## killer, the stage, the wave), and a mutation's `hero` flag is `hero_mutation` (`hero` is the hero's id on every event).
func map_event(e: Dictionary) -> Array:
	var kind := str(e.get("kind", ""))
	var ev_name := str(KIND_EVENTS.get(kind, ""))
	if ev_name == "":
		return []
	var p := {}
	for k in e.keys():
		if str(k) != "kind":
			p[str(k)] = e[k]
	match kind:
		"weapon", "passive", "mutation", "perk", "evolution", "passive_evolution":
			p["item_kind"] = kind
			if p.has("hero"):
				p["hero_mutation"] = p["hero"]
				p.erase("hero")
		"offer":
			if str(p.get("route", "")) == "path":
				ev_name = "path_offer"
			p.erase("route")
			p["picked"] = str(p.get("id", ""))
			p.erase("id")
			_rename(p, "left", "skips_left")
		"banish":
			if not p.has("where"):
				p["where"] = "cards"
		"chest":
			p["taken"] = bool(p.get("take", false))
			p.erase("take")
			_rename(p, "skip", "skipped")
			_rename(p, "left", "skips_left")
		"pickup":
			if bool(p.get("small", false)):
				var pid := str(p.get("id", ""))
				_run_small[pid] = int(_run_small.get(pid, 0)) + 1
				return []
			p.erase("small")
		"boss_start", "boss_end":
			_rename(p, "id", "boss")
		"stage", "portal_wait":
			p["stage"] = int(p.get("level", Run.stage + 1))
			p.erase("level")
		"wave":
			_rename(p, "level", "wave")
		"portal":
			var st := int(p.get("level", Run.stage + 1))
			p["stage"] = st
			p.erase("level")
			var stages := 3
			if Run.map and Run.map.timeline:
				stages = int(Run.map.timeline.stages)
			p["choice"] = "extract" if bool(p.get("extract", false)) else ("stay" if st >= stages else "continue")
			p.erase("extract")
		"death":
			_rename(p, "id", "killer")
			_rename(p, "hit", "killer_kind")
			p["level"] = Run.level
			p["kills"] = Run.kills
			p["gold"] = Run.run_gold
			p["wave"] = Run.endless_wave()
			var ws: Array = []
			for w in Run.weapons:
				ws.append({"id": w.def.id, "level": w.level})
			p["weapons"] = ws
		"revive":
			_rename(p, "id", "choice")
		"unlock":
			_rename(p, "id", "quest")
	return [ev_name, p]


func _rename(p: Dictionary, from: String, to: String) -> void:
	if p.has(from):
		p[to] = p[from]
		p.erase(from)


## The run ended (RunAnalytics.finish, or its exit without one): run_end, run_summary (with the small pickups counted
## on the way), the queue to disk and a send at once.
func run_finish(end: Dictionary, summary: Dictionary) -> void:
	if not run_props.is_empty() and active():
		track("run_end", end)
		var s := summary.duplicate(true)
		if not _run_small.is_empty():
			s["small_pickups"] = _run_small.duplicate()
		track("run_summary", s)
		save_queue()
		flush()
	run_props = {}
	_run_small = {}


## One move of the saved gold (pass 61, Garry: "Coin Gains / Spend (During gameplay and not, have all the sources)";
## Save.gold_moved): gold_meta {delta (signed), reason (run_bank, strongbox, talent, talent_refund, wipe, ...),
## balance_after, in_run} plus what it was for (a talent's `talent`, `rank`, `form`; a refund's `ranks`, `spent`). In a
## run (the Strongbox, the banking at the end) it carries the run's ids like every event. Nothing from the arena's
## sandbox, a tool or the test runner (track refuses). Returns whether it was queued.
func meta_gold(delta: int, reason: String, balance: int, extra: Dictionary = {}) -> bool:
	if delta == 0:
		return false
	var p := {"delta": delta, "reason": reason, "balance_after": balance, "in_run": in_run()}
	for k in extra.keys():
		if not p.has(k):
			p[str(k)] = extra[k]
	return track("gold_meta", p)


## The look the hero is played with: the one the player kept (Save.hero_look), else his JSON's `variant`.
func hero_look_of(hero: CharacterDef) -> String:
	if hero == null:
		return ""
	return hero.variant_def(Save.hero_look(hero.id)).look_code()


## A short stable hash of the map's timeline as loaded (its JSON's timeline_data, keys sorted, md5, 8 hex), so the
## dashboards can split results by Garry's Level Editor versions. Read once a session per map: the Registry loaded the
## map at boot, so a later edit is the next session's rev.
func map_rev(m: MapDef) -> String:
	if m == null:
		return ""
	if _map_revs.has(m.id):
		return str(_map_revs[m.id])
	var rev := ""
	var path := m.source_dir.path_join(m.id + ".json") if m.source_dir != "" else ""
	if path == "" or not FileAccess.file_exists(path):
		path = "res://content/maps/%s/%s.json" % [m.id, m.id]
	if FileAccess.file_exists(path):
		var j := JSON.new()
		if j.parse(FileAccess.get_file_as_string(path)) == OK and j.data is Dictionary:
			var tl = (j.data as Dictionary).get("timeline_data", {})
			rev = JSON.stringify(tl, "", true).md5_text().left(8)
	_map_revs[m.id] = rev
	return rev


# ---------------------------------------------------------------- the queue on disk

## The queue to user://analytics_queue.json (through a .tmp, so a kill mid-write keeps the last whole file); an empty
## queue removes the file. A tool or the test runner never touches the player's file.
func save_queue() -> void:
	_since_save = 0
	if runtime_block() != "" or awaiting_consent():
		return
	if queue.is_empty():
		_remove(queue_path)
		return
	var tmp := queue_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Analytics: could not write " + tmp)
		return
	f.store_string(JSON.stringify(queue))
	f.close()
	if DirAccess.rename_absolute(tmp, queue_path) != OK:
		push_warning("Analytics: could not move the queue into " + queue_path)


## Last time's queue (sent first: the launch send goes LAUNCH_SEND_MS after boot).
func load_queue() -> void:
	queue = []
	if not FileAccess.file_exists(queue_path):
		return
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(queue_path)) != OK or not (j.data is Array):
		push_warning("Analytics: %s did not read; dropped" % queue_path)
		_remove(queue_path)
		return
	for e in (j.data as Array):
		if e is Dictionary and (e as Dictionary).has("event"):
			queue.append(e)
	_trim()


## Off in Settings: the queue goes, on disk too.
func purge() -> void:
	queue.clear()
	# a batch on the wire no longer stands for anything queued: its answer must not take new events off the front
	_in_flight = 0
	_since_save = 0
	_remove(queue_path)
	_remove(queue_path + ".tmp")


func _remove(p: String) -> void:
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)


func _on_settings_changed() -> void:
	if not Settings.analytics and runtime_block() == "" and (not queue.is_empty() or FileAccess.file_exists(queue_path)):
		purge()
	if _answering or runtime_block() != "" or Save.consent() == "":
		return
	# the switch is the answer from then on (pass 59): on after a "no" records a yes (and says so), off records a no
	if Settings.analytics and Save.consent() == "no":
		Save.set_consent("yes")
		track("consent", {"accepted": true, "where": "settings", "$set": person_properties()})
		fetch_surveys()
	elif not Settings.analytics and Save.consent() == "yes":
		Save.set_consent("no")


# ---------------------------------------------------------------- the wire

## Sends the oldest BATCH_MAX events when nothing is on the wire and no backoff is running. Returns whether it sent.
func flush() -> bool:
	if queue.is_empty() or _in_flight > 0 or _requesting or not active() or awaiting_consent():
		return false
	if Time.get_ticks_msec() < _retry_at_ms:
		return false
	var n := mini(queue.size(), BATCH_MAX)
	var body := JSON.stringify({"api_key": key, "batch": queue.slice(0, n), "sent_at": iso_now()})
	_in_flight = n
	_requesting = true
	_next_flush_ms = Time.get_ticks_msec() + FLUSH_EVERY_MS
	sender.call(endpoint(), body)
	return true


## The developer menu's Send now: a dev_ping goes into the queue (so PostHog's live view shows something even when
## nothing waits), the backoff is forgotten, and the queue goes.
func send_now() -> bool:
	manual_sends += 1
	var why := block_reason()
	if why != "":
		last_status = "not sent: " + why
		sent.emit(false)
		return false
	track("dev_ping", {"waiting": queue.size()})
	_retry_at_ms = 0
	return flush()


func _http_send(url: String, body: String) -> void:
	if _http == null:
		call_deferred("send_done", false, "no request node")
		return
	var err := _http.request(url, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, body)
	if err != OK:
		call_deferred("send_done", false, "request: " + error_string(err))


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		send_done(false, "network: %s" % _result_name(result))
	elif code >= 200 and code < 300:
		send_done(true, "HTTP %d" % code, code)
	else:
		send_done(false, "HTTP %d" % code, code)


## How the request on the wire went. Taken: those events leave the queue. Refused as malformed or too big (400, 413):
## dropped, so one bad batch can never block the queue. Anything else (no network, 5xx, a wrong key's 401): kept, and
## the next try waits 30 s, then 60, 120, 240 and 300 s at most.
func send_done(ok: bool, status: String, code: int = 0) -> void:
	var n := mini(_in_flight, queue.size())
	_in_flight = 0
	_requesting = false
	last_status = status
	last_send_unix = int(Time.get_unix_time_from_system())
	if ok or code == 400 or code == 413:
		queue = queue.slice(n)
		if ok:
			sent_session += n
		else:
			dropped += n
		_backoff = 0.0
		_retry_at_ms = 0
		if queue.size() >= FLUSH_AT:
			_next_flush_ms = Time.get_ticks_msec() + 1000
	else:
		_backoff = BACKOFF_FIRST if _backoff <= 0.0 else minf(_backoff * 2.0, BACKOFF_MAX)
		_retry_at_ms = Time.get_ticks_msec() + int(_backoff * 1000.0)
	save_queue()
	if is_dev() and not test_mode:
		print("analytics: %s, %d events (%d waiting)" % [status, n, queue.size()])
	sent.emit(ok)


## Seconds until the next try after a failure (0 = none waiting).
func retry_in() -> float:
	if _retry_at_ms <= 0:
		return 0.0
	return maxf(float(_retry_at_ms - Time.get_ticks_msec()) / 1000.0, 0.0)


## The backoff the last failure set, in seconds (0 after a success).
func backoff() -> float:
	return _backoff


## Events on the wire right now (0 = none).
func in_flight() -> int:
	return _in_flight


func _result_name(r: int) -> String:
	if r == HTTPRequest.RESULT_CANT_CONNECT:
		return "cant_connect"
	if r == HTTPRequest.RESULT_CANT_RESOLVE:
		return "cant_resolve"
	if r == HTTPRequest.RESULT_CONNECTION_ERROR:
		return "connection_error"
	if r == HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
		return "tls_handshake"
	if r == HTTPRequest.RESULT_NO_RESPONSE:
		return "no_response"
	if r == HTTPRequest.RESULT_TIMEOUT:
		return "timeout"
	return "result %d" % r


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _retry_at_ms > 0 and now >= _retry_at_ms and _in_flight == 0 and not _requesting:
		_retry_at_ms = 0
		flush()
	elif _next_flush_ms > 0 and now >= _next_flush_ms:
		_next_flush_ms = now + FLUSH_EVERY_MS
		flush()


# ---------------------------------------------------------------- the developer menu and Settings

## The readout (never the key itself): the file, why nothing goes if nothing does, the queue, the last send.
func status_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("key file: %s" % ("found" if config_found else "missing (%s)" % CONFIG_PATH))
	out.append("key: %s" % ("set" if key_ok() else ("empty" if key == "" else "not a phc_ project key")))
	out.append("enabled in the file: %s" % ("yes" if config_enabled else "no"))
	var why := block_reason()
	out.append("sending: %s" % ("yes" if why == "" else "no · " + why))
	out.append("tagged dev: %s" % ("yes" if is_dev() else "no"))
	out.append("host: " + host)
	out.append("install id: " + (str(Save.data.get("install_id", "")) if Save.has_install_id() else "none yet"))
	out.append("player: %s · play-data card: %s" % [Save.player_name(), {"": "not answered", "yes": "yes", "no": "no"}.get(Save.consent(), "?")])
	out.append("surveys: %d running · %s · questions after a run %s" % [surveys.size(), survey_status if survey_status != "" else "not fetched", "on" if Settings.surveys else "off"])
	if session_id != "":
		out.append("session: %s · %d min" % [session_id.left(8), int((Time.get_unix_time_from_system() - _session_start) / 60.0)])
	out.append("queue: %d waiting%s" % [queue.size(), (" · %d on the wire" % _in_flight) if _in_flight > 0 else ""])
	out.append("sent this session: %d%s" % [sent_session, (" · dropped %d" % dropped) if dropped > 0 else ""])
	if last_send_unix > 0:
		var ago := int(Time.get_unix_time_from_system()) - last_send_unix
		out.append("last send: %s · %s" % [last_status, ("%d s ago" % ago) if ago < 120 else ("%d min ago" % int(ago / 60.0))])
	else:
		out.append("last send: %s" % (last_status if last_status != "" else "none yet"))
	var wait := retry_in()
	if wait > 0.0:
		out.append("next try in %d s" % int(ceil(wait)))
	return out


## Settings' one line under the switch: what goes, or why nothing does (pass 58 review: a key pasted with "enabled"
## still false had said the key file was empty). Pass 60 (Garry: simpler, no mention of him): no "maker".
func settings_line() -> String:
	if configured():
		return "Your runs (picks, falls, frame rate) are sent under your player name, shown at the foot of this screen. No account, no location. Off deletes what waits."
	return "Nothing is sent: %s." % block_reason()

# ---------------------------------------------------------------- the player (pass 59)

## The person properties every app_open and consent sets: the game's name for the install, the build, the survey switch.
## Garry's own `label` is never among them, so PostHog keeps it.
func person_properties() -> Dictionary:
	return {"player_name": Save.player_name(), "app_version": str(ProjectSettings.get_setting("application/config/version", "")),
		"surveys_opt_out": not Settings.surveys, "analytics_consent": Save.consent() == "yes"}


## The play-data card has not been answered: events wait in memory, nothing goes out or to disk.
func awaiting_consent() -> bool:
	if test_mode and not test_consent_gate:
		return false
	return Save.consent() == ""


## Whether the title shows the play-data card: a build that could send (a key, enabled, a real run of the app, not
## the arena) whose player has not answered it.
func consent_needed() -> bool:
	return Save.consent() == "" and configured() and runtime_block() == "" and not in_arena()


var _answering := false


## The card's answer. Yes: the switch on, a "consent" event with the person's properties, what waited goes, the
## surveys are fetched. No: the switch off and everything that waited is deleted; nothing is sent.
func answer_consent(yes: bool) -> void:
	_answering = true
	Save.set_consent("yes" if yes else "no")
	Settings.set_value("analytics", yes)
	_answering = false
	if yes:
		track("consent", {"accepted": true, "where": "card", "$set": person_properties()})
		save_queue()
		flush()
		fetch_surveys()
	else:
		purge()


# ---------------------------------------------------------------- surveys (pass 59)

## PostHog's public survey list for this project (the project key is enough to read it).
func surveys_url() -> String:
	return host + "/api/surveys/?token=" + key.uri_encode()


## Asks PostHog for the running surveys (once at launch after consent, and after a yes on the card).
func fetch_surveys() -> void:
	if _survey_http == null or _survey_fetching or not active() or awaiting_consent():
		return
	_survey_fetching = true
	var err := _survey_http.request(surveys_url())
	if err != OK:
		_survey_fetching = false
		survey_status = "request: " + error_string(err)


func _on_surveys_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_survey_fetching = false
	if result != HTTPRequest.RESULT_SUCCESS:
		survey_status = "network: %s" % _result_name(result)
		return
	if code != 200:
		survey_status = "HTTP %d" % code
		return
	var n := set_surveys_from(JSON.parse_string(body.get_string_from_utf8()))
	survey_status = "HTTP 200 · %d running" % n
	save_survey_cache()


## PostHog's answer ({"surveys": [...]}) made into the surveys the game can ask: launched (a start date), not ended,
## not archived, with at least one question it can draw. Returns how many.
func set_surveys_from(j) -> int:
	surveys = []
	if not (j is Dictionary):
		return 0
	var list = (j as Dictionary).get("surveys", [])
	if not (list is Array):
		return 0
	for sv in list:
		var n := normalise_survey(sv)
		if not n.is_empty():
			surveys.append(n)
	return surveys.size()


## One survey as the card needs it, or {} when the game cannot or should not ask it.
static func normalise_survey(sv) -> Dictionary:
	if not (sv is Dictionary):
		return {}
	var d: Dictionary = sv
	var id := str(d.get("id", ""))
	if id == "" or str(d.get("type", "")) == "external_survey" or bool(d.get("archived", false)):
		return {}
	if d.get("start_date") == null or str(d.get("start_date", "")) == "":
		return {}
	if d.get("end_date") != null and str(d.get("end_date", "")) != "":
		return {}
	var qs: Array = []
	var raw = d.get("questions", [])
	for q in (raw if raw is Array else []):
		if not (q is Dictionary) or not SURVEY_TYPES.has(str(q.get("type", ""))):
			continue
		var choices: Array = []
		for c in (q.get("choices", []) if q.get("choices") is Array else []):
			choices.append(str(c))
		if str(q.get("type")) in ["single_choice", "multiple_choice"] and choices.is_empty():
			continue
		qs.append({"id": str(q.get("id", "")), "type": str(q.get("type")), "question": str(q.get("question", "")),
			"description": str(q.get("description", "")) if q.get("description") != null else "",
			"optional": bool(q.get("optional", false)), "choices": choices,
			"scale": clampi(int(q.get("scale", 5)) if q.get("scale") != null else 5, 2, 10),
			"lower": str(q.get("lowerBoundLabel", "")) if q.get("lowerBoundLabel") != null else "",
			"upper": str(q.get("upperBoundLabel", "")) if q.get("upperBoundLabel") != null else ""})
	if qs.is_empty():
		return {}
	return {"id": id, "name": str(d.get("name", "")), "questions": qs}


func save_survey_cache() -> void:
	if runtime_block() != "":
		return
	var f := FileAccess.open(survey_cache_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"surveys": surveys}))
		f.close()


func load_survey_cache() -> void:
	surveys = []
	if not FileAccess.file_exists(survey_cache_path):
		return
	var j = JSON.parse_string(FileAccess.get_file_as_string(survey_cache_path))
	if j is Dictionary and j.get("surveys") is Array:
		for sv in j["surveys"]:
			if sv is Dictionary and str(sv.get("id", "")) != "" and sv.get("questions") is Array and not (sv["questions"] as Array).is_empty():
				surveys.append(sv)


## The Results screen's question (Garry: "ask people a couple of questions at the end of the run ... Only the Result
## Screens"): counts this run when it lasted SURVEY_MIN_RUN seconds and returns the survey to ask now, or {}. At most
## one every SURVEY_EVERY counted runs, never twice in a session, each survey until it is answered, none when the
## player said "Don't ask me again" or play data is off.
func survey_after_run(run_seconds: float) -> Dictionary:
	if not Settings.surveys or not active() or awaiting_consent() or run_seconds < SURVEY_MIN_RUN:
		return {}
	var st := Save.survey_state()
	var since := int(st.get("runs_since", SURVEY_EVERY - 1)) + 1
	st["runs_since"] = since
	Save.request_save()
	if since < SURVEY_EVERY or _survey_this_session:
		return {}
	var answered: Array = st.get("answered", []) if st.get("answered") is Array else []
	for sv in surveys:
		if not answered.has(str(sv.get("id", ""))):
			st["runs_since"] = 0
			_survey_this_session = true
			return sv
	return {}


func survey_shown(sv: Dictionary) -> void:
	track("survey shown", {"$survey_id": str(sv.get("id", "")), "$survey_name": str(sv.get("name", ""))})


## Closed without answering ("Not now"): PostHog marks it dismissed for this person; it may come again in a later run.
func survey_dismissed(sv: Dictionary) -> void:
	var id := str(sv.get("id", ""))
	track("survey dismissed", {"$survey_id": id, "$survey_name": str(sv.get("name", "")), "$set": {"$survey_dismissed/" + id: true}})


## The answers ({question id: value}: a rating an int, a choice a String, several choices an Array, a text a String) in
## PostHog's own shape: one $survey_response_<question id> each and the $survey_questions list. The survey is not
## asked again.
func survey_sent(sv: Dictionary, answers: Dictionary) -> Dictionary:
	var id := str(sv.get("id", ""))
	var listed: Array = []
	var p := {"$survey_id": id, "$survey_name": str(sv.get("name", "")), "$survey_completed": true,
		"$survey_submission_id": uuid7(), "$set": {"$survey_responded/" + id: true}}
	for q in sv.get("questions", []):
		var qid := str(q.get("id", ""))
		var has := answers.has(qid)
		listed.append({"id": qid, "question": str(q.get("question", "")), "response": answers[qid] if has else null})
		if has:
			p["$survey_response_" + qid] = answers[qid]
	p["$survey_questions"] = listed
	track("survey sent", p)
	var st := Save.survey_state()
	var answered: Array = st.get("answered", []) if st.get("answered") is Array else []
	if not answered.has(id):
		answered.append(id)
	st["answered"] = answered
	Save.request_save()
	return p


## The survey switch (Settings' "Questions after a run", or "Don't ask me again" on the card): opting out is told to
## PostHog (survey_opt_out, surveys_opt_out on the person) so Garry sees who did; opting back in likewise.
func set_surveys(on: bool, where: String) -> void:
	if Settings.surveys == on:
		return
	Settings.set_value("surveys", on)
	track("survey_opt_in" if on else "survey_opt_out", {"where": where, "$set": {"surveys_opt_out": not on}})
