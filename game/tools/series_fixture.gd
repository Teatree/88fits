## Pass 78 (lane DASH): two fixtures the page and the downloader are checked against, written from the game's own code.
##  - dash78_series_out.json: game/tools/sim_run.gd series() on tools/level_editor/testdata/dash78_series_in.json (a run
##    record, the end event, the evolution ids), full precision. tools/level_editor/sim_avg.js series() must give the
##    same (selftest_DASH78); game/tests/pass78_dash_test.gd checks the GDScript still does.
##  - dash78_parts.json: the first 60 rows of that record as the game sends it to PostHog (Analytics.record_parts, small
##    parts so there are several): {"json": its text, "parts": [...]}; tools/posthog_runs.py join_parts must give the text
##    back (selftest_DASH78).
## Change sim_run.gd series() or the run_record encoding, run this again, and make the page / the downloader match.
##
##   bash tools/godot.sh --headless --path D:/_projects/88fits/game --script res://tools/series_fixture.gd
extends SceneTree

const SIM := preload("res://tools/sim_run.gd")
const PARTS_ROWS := 60
const PARTS_MAX := 3000


static func fixture_dir() -> String:
	return ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("tools/level_editor/testdata")


static func _input(input_path: String) -> Dictionary:
	if not FileAccess.file_exists(input_path):
		return {}
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(input_path)) != OK or not (j.data is Dictionary):
		return {}
	return j.data


## {"series": SIM.series(...), "ok": ""} or {"ok": why not}.
static func run_fixture(input_path: String) -> Dictionary:
	var doc := _input(input_path)
	if doc.is_empty():
		return {"ok": "no input (or it does not parse): " + input_path}
	var rec: Dictionary = doc.get("record", {})
	var rows: Array = rec.get("samples", [])
	var events: Array = rec.get("events", [])
	var out: Dictionary = SIM.series(rows, events, [], doc.get("end_ev", {}), doc.get("evo_ids", {}))
	return {"ok": "", "series": out}


## {"json": the short record's text, "parts": Analytics.record_parts(it, PARTS_MAX)}. Analytics.gd names autoloads, so
## it is loaded when they exist (a --script tool compiles before them).
static func parts_fixture(input_path: String) -> Dictionary:
	var doc := _input(input_path)
	var rec: Dictionary = (doc.get("record", {}) as Dictionary).duplicate(true)
	rec["samples"] = (rec.get("samples", []) as Array).slice(0, PARTS_ROWS)
	var json := JSON.stringify(rec)
	var analytics = load("res://core/autoload/Analytics.gd")
	return {"json": json, "parts": analytics.record_parts(json, PARTS_MAX)}


func _init() -> void:
	process_frame.connect(_go, CONNECT_ONE_SHOT)


func _go() -> void:
	var dir := fixture_dir()
	var input := dir.path_join("dash78_series_in.json")
	var res := run_fixture(input)
	if str(res.get("ok", "")) != "":
		printerr("series_fixture: " + str(res["ok"]))
		quit(2)
		return
	if not _store(dir.path_join("dash78_series_out.json"), JSON.stringify(res["series"], "", true, true)):
		quit(3)
		return
	if not _store(dir.path_join("dash78_parts.json"), JSON.stringify(parts_fixture(input))):
		quit(3)
		return
	print("series_fixture: wrote dash78_series_out.json and dash78_parts.json in " + dir)
	quit(0)


func _store(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("series_fixture: cannot write " + path)
		return false
	f.store_string(text)
	f.close()
	return true
