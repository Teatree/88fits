## Pass 129 (lane TRAIL-SETUP): the Drifter's power (core/systems/HeroPower.gd) under a list of permanent set-ups: a
## fresh save, the Upgrade board at given ranks and forms, the Trail with given nodes bought. Each set-up is measured
## twice: at level 1 with the Revolver, and at level 30 with a plain build (PLAIN, no mutations).
## Run: bash tools/godot.sh --headless --fixed-fps 60 --path <project> --script res://tools/_p129_SETUP_power.gd
##        --log-file <f> -- plan=<abs path> out=<abs path>
## The plan (written by tools/trail_setup.py --probe-plan): {"trail": "<abs path of a Trail file, or empty for the
## game's own>", "configs": [{"name": "...", "talents": {"drive": [1,1,...]}, "bought": ["n001", ...]}]}.
## The save is sandboxed (Save.begin_sandbox): nothing is written. Bounded by a frame cap.
extends SceneTree

const PLAIN_WEAPONS := [["revolver", 5], ["molotov", 4], ["orbit_saws", 4], ["boomstick", 3], ["tommy_gun", 3]]
const PLAIN_PASSIVES := [["brawn", 3], ["vigour", 3], ["mend", 2], ["reach", 2], ["quickdraw", 2]]
const STATS := ["might", "cooldown", "max_hp", "damage_reduction", "regen", "evade", "shield_max", "crit_chance", "crit_damage",
	"area", "amount", "move_speed", "xp_gain", "greed", "luck", "revives", "revive_hp"]

var _plan := ""
var _out := ""
var _run: Node
var _game: Node
var _t := 0.0
var _frames := 0
var _done := false


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"plan": _plan = kv[1]
			"out": _out = kv[1]
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var save := root.get_node_or_null("Save")
	save.begin_sandbox()
	save.data["runs_started"] = 1
	save.data["talents"] = {}
	save.data["trail"] = {"bought": [], "spent": 0, "had": []}
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 11, "analytics": false, "sim_clock": true}))
	f.close()
	_run = root.get_node("Run")
	change_scene_to_file("res://game/Game.tscn")
	process_frame.connect(_tick)


func _tick() -> void:
	if _done:
		return
	_frames += 1
	_t += root.get_process_delta_time()
	if _frames > 3000 or _t > 240.0:
		print("p129power: TIMEOUT")
		_done = true
		quit(1)
		return
	if _game == null:
		var g = current_scene
		if g == null or not g.has_method("open_pause") or g.player == null:
			return
		_game = g
		_game.player.god = true
	if _t > 0.6 and not _run.weapons.is_empty():
		_done = true
		_measure_all()


func _measure_all() -> void:
	var save := root.get_node("Save")
	var trail = load("res://core/systems/Trail.gd")
	var hp = load("res://core/systems/HeroPower.gd")
	var plan: Variant = JSON.parse_string(FileAccess.get_file_as_string(_plan))
	if not (plan is Dictionary):
		print("p129power: no plan at %s" % _plan)
		quit(1)
		return
	var tpath := str((plan as Dictionary).get("trail", ""))
	if tpath != "":
		trail.load_data(trail.read_file(tpath))
	_game.director.stop()
	_game.enemies.kill_all(false)
	var rows: Array = []
	for c: Variant in (plan as Dictionary).get("configs", []):
		var cfg: Dictionary = c
		var talents := {}
		var tl: Variant = cfg.get("talents", {})
		if tl is Dictionary:
			for id: Variant in (tl as Dictionary).keys():
				var picks: Array = []
				for p: Variant in ((tl as Dictionary)[id] as Array):
					picks.append(int(p))
				if not picks.is_empty():
					talents[str(id)] = {"picks": picks, "rank": picks.size(), "form": int(picks[picks.size() - 1])}
		save.data["talents"] = talents
		var bought: Array = []
		for b: Variant in cfg.get("bought", []):
			bought.append(str(b))
		save.data["trail"] = {"bought": bought, "spent": 0, "had": []}
		trail.refresh()
		var row := {"name": str(cfg.get("name", "")), "trail_level": int(trail.level())}
		for which: String in ["l1", "l30"]:
			_run.debug_clear_items()
			if which == "l1":
				_run.debug_set_item("weapon", "revolver", 1)
				_run.level = 1
			else:
				for w: Array in PLAIN_WEAPONS:
					_run.debug_set_item("weapon", str(w[0]), int(w[1]))
				for p: Array in PLAIN_PASSIVES:
					_run.debug_set_item("passive", str(p[0]), int(p[1]))
				_run.level = 30
			_run.rebuild_sheets()
			hp.forget()
			var m: Dictionary = hp.measure(_run.weapons, _run.player_sheet)
			var st := {}
			for s: String in STATS:
				st[s] = snappedf(float(_run.player_sheet.get_stat(s, 0.0)), 0.0001)
			row[which] = {"dps": snappedf(float(m["dps"]), 0.01), "ehp": snappedf(float(m["ehp"]), 0.01), "power": snappedf(float(m["power"]), 0.0001), "stats": st}
		rows.append(row)
		print("p129power: %s | trail level %d | L1 dps %.1f ehp %.1f power %.3f | L30 dps %.1f ehp %.1f power %.3f" % [row["name"], int(row["trail_level"]),
			float(row["l1"]["dps"]), float(row["l1"]["ehp"]), float(row["l1"]["power"]), float(row["l30"]["dps"]), float(row["l30"]["ehp"]), float(row["l30"]["power"])])
	save.data["talents"] = {}
	save.data["trail"] = {"bought": [], "spent": 0, "had": []}
	trail.load_from()
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"rows": rows}, "  "))
			f.close()
	print("p129power: DONE %d set-ups" % rows.size())
	quit(0)
