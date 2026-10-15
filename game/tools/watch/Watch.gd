## The Watch (pass 80, lane WATCH; Garry approved the design in pass 79 and said "proceed" in pass 80): a PC window with
## the real game on the left, at a phone's proportions (9:20) scaled to the window's height, played by the bot
## (tools/bot/Bot.gd, lane BOT; BotStub.gd with bot=stub), and on the right a panel of numbers, charts and the bot's
## decisions (WatchPanel.gd), with a speed control (WatchClock.gd). Started by tools/watch.py on its own snapshot of
## game/ (tools/dl/watch/snap, user folder 88fits_watch) through watch_main.gd:
##   Godot --fixed-fps 60 --path <snapshot> --script res://tools/watch/watch_main.gd -- hero=drifter talents=... seed=7
##       [map=red_canyon] [limit=0] [speed=1] [paused=0] [death=end] [unlocks=all] [ref=<sim result.json>] [repo=<repo>]
##       [lock=<lock dir>] [bot=auto|stub] [bot.<key>=<value> ...] [board_label=...] [ref_label=...] [sound=1]
##       [numbers=1] [autoquit=0] [wall=0] [shots=<dir> shots_at=30,120] [log_speed=30] [w=1920 h=1080]
## (tools/dl/p80/keys_WATCH.md lists them). How it lives with the game:
## - The Game scene sits in a SubViewport (own World3D, size_2d_override = the phone's canvas, 1080 wide), drawn through
##   a TextureRect: no window input reaches it but the mouse on the phone view, turned into a finger (pass 82: the
##   game's own Pause button, its pause screen and its options work as on the phone; _on_view_input). The bot writes
##   the hero's PlayerInput as sim_pilot does; the hero's input is switched off for touches and keys (PlayerInput.enabled),
##   so neither a click nor WASD ever steers him. Nothing in the game changes: every system reads get_viewport().
## - The tree's current scene stays empty (watch_main.gd is a SceneTree script): the run's end is caught the frame
##   Game._ended turns true, the record already written (RunAnalytics.finish in end_run), and the Game is freed before
##   its 1.2 s wait ends (the pending await goes with it: no Results scene, no scene change); a Results scene or the
##   scene fade that reaches the root anyway is freed.
## - The run is a tool run: the save sandboxed (nothing reaches the disk), every unlock quest done (unlocks=all), the
##   run sim's settings (the north-up camera the bot steers by, no hints), the dice seeded as sim_run.gd seeds them,
##   the launch in memory with sim_clock (Run.rule_seconds on the run's own clock at any speed). The record goes to the
##   repo's analytics/runs/tools/ (RunAnalytics.mirror_root) with <stamp>_decisions.csv beside it.
## Tools only (tools/* is never exported).
extends Control

const CLOCK := preload("res://tools/watch/WatchClock.gd")
const DATA := preload("res://tools/watch/WatchData.gd")
const PANEL := preload("res://tools/watch/WatchPanel.gd")
const RING := preload("res://tools/watch/WatchRing.gd")
const STUB := preload("res://tools/watch/BotStub.gd")
const BOT_PATH := "res://tools/bot/Bot.gd"
const GAME_SCENE := "res://game/Game.tscn"
const RESULTS_SCENE := "res://ui/ResultsScreen.tscn"
## the phone's canvas width in design pixels (project.godot viewport_width) and its shape
const CANVAS_W := 1080
const ASPECT := Vector2(9.0, 20.0)
## a screen (cards, a chest, the Stranger...) stays up this many wall seconds at 1x (less above: HOLD_S / speed) before
## the bot answers it, so it can be seen
const HOLD_S := 0.8
## a screen the bot has left up this many wall seconds of running is reported (and Down! is answered by `death`)
const STUCK_S := 15.0
## the panel's numbers are refreshed this often (wall seconds); the charts at most CHART_EVERY
const REFRESH_S := 1.0
const CHART_EVERY := 0.5
## the speed print in the log (log_speed=, wall seconds)
const LOG_SPEED_S := 30.0

var args: Dictionary = {}
var hero := "drifter"
var run_seed := 1
var map_id := "red_canyon"
var limit := 0.0
var death := "end"
var bot_opts: Dictionary = {}
var repo := ""
var sound_on := true
var numbers_on := true
var autoquit := false
## skip_draw=0 keeps the drawing work on the frames that are not drawn (above 1x); 1 (the default) skips it there
var skip_draw_work := true

var sub: SubViewport
var view: TextureRect
var view_bg: ColorRect
var badge: Label
var panel
var game: Node
var ra: Node
var bot
var bot_kind := ""
var clock := CLOCK.new()
var data := DATA.new()
var ref: Dictionary = {}
var ref_label := ""
var names: Dictionary = {}
var ended := false
var end_info: Dictionary = {}
var problems: Array = []

var _attached := false
var _seeded: Dictionary = {}
var _last_play := 0.0
var _last_us := 0
var _screen_key := ""
var _screen_held := 0.0
var _screen_up := 0.0
var _forced_pause := false
var _refresh_left := 0.0
var _chart_left := 0.0
var _charts_dirty := true
## the Watch's own cost, ms a frame over the last COST_S wall seconds: the panel (reading the rows, refreshing the
## numbers and the charts, drawing them) apart from the bot's tick
var panel_ms := 0.0
var bot_ms := 0.0
var _acc_frames := 0
var _acc_panel_us := 0
var _acc_bot_us := 0
var _acc_left := 2.0
## profile=1: the log's speed line also says what a frame costs, drawn and not (its work from the end of the Watch's wait
## to the next frame: the game's frame, the bot, the panel, the drawing), the waits, and the game's own buckets (Perf)
var _profile := false
var _prof_us0 := 0
var _prof_drawn := true
var _prof_draw_us := 0
var _prof_draw_n := 0
var _prof_sim_us := 0
var _prof_sim_n := 0
var _prof_wait_us := 0
var _log_left := LOG_SPEED_S
var _log_every := LOG_SPEED_S
var _wall_cap := 0.0
var _shots_dir := ""
var _shots: Array = []
var _shot_frames := 0
var _shot_name := ""
var _end_shot := false
var _shot_wanted := ""
var _actions: Array = []
var _attach_wall := 0.0
var _fixed_checked := 0
var _limit_called := false
var _was_paused := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_read_args()
	_setup_window()
	_setup_save()
	_build()
	_load_ref()
	_start_game()
	var tree := get_tree()
	tree.process_frame.connect(_on_frame)
	tree.physics_frame.connect(_on_physics)
	tree.node_added.connect(_on_node_added)
	get_viewport().size_changed.connect(_fit)
	_fit()
	_last_us = Time.get_ticks_usec()
	print("watch: %s seed %d map %s board %s limit %s speed %s bot %s ref %s" % [hero, run_seed, map_id, str(args.get("board_label", "")),
		DATA.mmss(limit) if limit > 0.0 else "none", CLOCK.label(clock.speed), str(args.get("bot", "auto")), ref_label if ref_label != "" else "none"])


# ---------------------------------------------------------------- the start

func _read_args() -> void:
	hero = str(args.get("hero", "drifter"))
	run_seed = int(args.get("seed", "1"))
	if run_seed == 0:
		run_seed = 1
	map_id = str(args.get("map", "red_canyon"))
	limit = maxf(float(args.get("limit", "0")), 0.0)
	death = str(args.get("death", "end"))
	repo = str(args.get("repo", ""))
	sound_on = str(args.get("sound", "1")) != "0"
	numbers_on = str(args.get("numbers", "1")) != "0"
	autoquit = str(args.get("autoquit", "0")) == "1"
	skip_draw_work = str(args.get("skip_draw", "1")) != "0"
	_wall_cap = maxf(float(args.get("wall", "0")), 0.0)
	_log_every = maxf(float(args.get("log_speed", str(LOG_SPEED_S))), 1.0)
	_profile = str(args.get("profile", "0")) == "1"
	_log_left = _log_every
	clock.set_speed(float(args.get("speed", "1")))
	clock.paused = str(args.get("paused", "0")) == "1"
	for k in args:
		var key := str(k)
		if key.begins_with("bot."):
			bot_opts[key.substr(4)] = typed_value(str(args[k]))
	_shots_dir = str(args.get("shots", ""))
	for part in str(args.get("shots_at", "")).split(",", false):
		if part.strip_edges().is_valid_float():
			_shots.append(float(part))
	_shots.sort()
	_read_actions()


## A command line's value typed: true/false/on/off a bool, a number a float (an int when whole), else the text.
static func typed_value(v: String) -> Variant:
	var s := v.strip_edges()
	match s.to_lower():
		"true", "on", "yes":
			return true
		"false", "off", "no":
			return false
	if s.is_valid_int():
		return int(s)
	if s.is_valid_float():
		return float(s)
	return s


## talents=grit:AAB,drive:A (one letter a rank bought, A the first form, B the second; "none" = an empty board) as
## Save.data.talents writes it ({id: {picks, rank, form}}), only the talents in `known`. {"error": text} when it cannot.
static func talents_from(arg: String, known: Array) -> Dictionary:
	var out := {}
	var txt := arg.strip_edges()
	if txt == "" or txt.to_lower() == "none":
		return out
	for part in txt.split(",", false):
		var bits := part.strip_edges().split(":")
		if bits.size() != 2:
			return {"error": "talents: '%s' is not <id>:<letters>" % part}
		var id := bits[0].strip_edges()
		if not known.has(id):
			return {"error": "talents: no talent '%s'" % id}
		var picks: Array = []
		for ch in bits[1].strip_edges().to_upper():
			if ch == "A" or ch == "0":
				picks.append(0)
			elif ch == "B" or ch == "1":
				picks.append(1)
			else:
				return {"error": "talents: '%s' picks are A or B, one a rank" % part}
		if picks.size() > 6:
			return {"error": "talents: '%s' has more than 6 ranks" % part}
		if not picks.is_empty():
			out[id] = {"picks": picks, "rank": picks.size(), "form": int(picks[picks.size() - 1])}
	return out


func _setup_window() -> void:
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	if DisplayServer.get_name() == "headless":
		return
	var want := Vector2i(int(args.get("w", "1920")), int(args.get("h", "1080")))
	var scr := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	if scr.size.x > 0 and scr.size.y > 0:
		want = Vector2i(mini(want.x, scr.size.x), mini(want.y, scr.size.y - 32))
	win.min_size = Vector2i(1100, 620)
	DisplayServer.window_set_size(want)
	if scr.size.x > 0:
		DisplayServer.window_set_position(scr.position + (scr.size - want) / 2)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_title("88fits Watch: %s, seed %d" % [hero, run_seed])


func _setup_save() -> void:
	var save := get_node("/root/Save")
	var reg := get_node("/root/Registry")
	var settings := get_node_or_null("/root/Settings")
	# nothing reaches the disk (the Watch's own user folder anyway): the boot's pending write dropped, then the sandbox
	save.set("_dirty", false)
	save.begin_sandbox()
	save.data["runs_started"] = 1
	var tal := talents_from(str(args.get("talents", "none")), (reg.get("talents") as Dictionary).keys())
	if tal.has("error"):
		problems.append(str(tal["error"]) + ": the board is empty")
		tal = {}
	save.data["talents"] = tal
	if str(args.get("unlocks", "all")) == "all":
		var done: Array = []
		for qid in (reg.get("quests") as Dictionary).keys():
			done.append(str(qid))
		save.data["quests_done"] = done
	if settings:
		settings.camera_mode = 0
		settings.ranged_on_screen = true
		settings.pierce_falloff = true
		settings.show_hints = false
		settings.damage_numbers = numbers_on
		settings.debug_mode = false
	if reg.character(hero) == null:
		problems.append("no hero '%s': the save's hero plays" % hero)
	if reg.map(map_id) == null:
		problems.append("no map '%s'" % map_id)


func _build() -> void:
	view_bg = ColorRect.new()
	view_bg.color = Color(0.03, 0.03, 0.04)
	view_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view_bg)
	sub = SubViewport.new()
	sub.name = "Phone"
	# the game pauses as it does under the window's root (pausable; its UI layer is ALWAYS itself): the Watch around it
	# processes always, and would otherwise lend it that mode (the crowd moving behind the level-up cards)
	sub.process_mode = Node.PROCESS_MODE_PAUSABLE
	sub.own_world_3d = true
	sub.size_2d_override_stretch = true
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.audio_listener_enable_3d = true
	sub.handle_input_locally = false
	add_child(sub)
	view = TextureRect.new()
	view.name = "PhoneView"
	view.texture = sub.get_texture()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	# pass 82: the mouse on the phone view is a finger on the game's screen (_on_view_input)
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	view.gui_input.connect(_on_view_input)
	add_child(view)
	# the speed over the phone's view: PAUSED, a step, the run to a level-up, or the speed when it is not 1x
	badge = Label.new()
	badge.name = "SpeedBadge"
	badge.add_theme_font_size_override("font_size", 18)
	badge.add_theme_color_override("font_color", Color(1, 1, 1))
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.05, 0.05, 0.07, 0.72)
	bs.set_corner_radius_all(5)
	bs.content_margin_left = 10
	bs.content_margin_right = 10
	bs.content_margin_top = 3
	bs.content_margin_bottom = 3
	badge.add_theme_stylebox_override("normal", bs)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.visible = false
	add_child(badge)
	panel = PANEL.new()
	panel.name = "Panel"
	add_child(panel)
	panel.build(self)


## The phone on the left at 9:20, as tall as the window (at most half its width), the panel on the right.
func _fit() -> void:
	var win := get_viewport_rect().size
	var h := win.y
	var w := roundf(h * ASPECT.x / ASPECT.y)
	if w > win.x * 0.5:
		w = roundf(win.x * 0.5)
		h = roundf(w * ASPECT.y / ASPECT.x)
	var y := roundf((win.y - h) * 0.5)
	view_bg.position = Vector2.ZERO
	view_bg.size = Vector2(w, win.y)
	view.position = Vector2(0, y)
	view.size = Vector2(w, h)
	panel.position = Vector2(w, 0)
	panel.size = Vector2(win.x - w, win.y)
	_place_badge()
	if sub:
		sub.size = Vector2i(maxi(int(w), 64), maxi(int(h), 128))
		sub.size_2d_override = Vector2i(CANVAS_W, int(roundf(float(CANVAS_W) * h / maxf(w, 1.0))))


## The badge's words now ("" hides it) and its place: the phone view's bottom middle.
func badge_words() -> String:
	if ended:
		return "RUN OVER"
	if clock.paused:
		return "PAUSED"
	# (pass 82: the game's own pause screen says PAUSED and its RESUME sits where the badge would; the header says
	# "paused (in game)")
	if clock.game_hold:
		return ""
	if clock.mode == "step":
		return "STEP 1 s"
	if clock.mode == "level":
		return "TO THE NEXT LEVEL-UP  8x"
	if absf(clock.speed - 1.0) > 0.001:
		var txt := CLOCK.label(clock.speed)
		if clock.short():
			txt += "  (%.1fx)" % clock.reached
		return txt
	return ""


func _place_badge() -> void:
	if badge == null or view == null:
		return
	var txt := badge_words()
	badge.visible = txt != ""
	if txt != badge.text:
		badge.text = txt
		badge.reset_size()
	var sz := badge.get_combined_minimum_size()
	badge.position = Vector2(view.position.x + (view.size.x - sz.x) * 0.5, view.position.y + view.size.y - sz.y - 18.0)


func _load_ref() -> void:
	var p := str(args.get("ref", ""))
	ref_label = str(args.get("ref_label", ""))
	if p == "" or p == "none":
		return
	if not FileAccess.file_exists(p):
		problems.append("no Sim result at %s" % p)
		return
	var doc = JSON.parse_string(FileAccess.get_file_as_string(p))
	var r := ref_from(doc)
	if r.is_empty():
		problems.append("the Sim result %s has no series" % p.get_file())
		return
	ref = r
	if ref_label == "":
		ref_label = p.get_base_dir().get_file()


## The Sim's average (a result.json, tools/sim_batch.py aggregate) as the charts read it: {t, dps, hp, level, crowd,
## danger} one value a second of play (NAN where no run played), plus its players; {} when it has no series.
static func ref_from(doc) -> Dictionary:
	if not (doc is Dictionary) or not (doc.get("series") is Dictionary) or not (doc.get("t") is Array):
		return {}
	var ts := PackedFloat32Array()
	for x in doc["t"]:
		ts.append(float(x))
	var out := {"t": ts}
	var series: Dictionary = doc["series"]
	for pair in [["dps", "dps"], ["hp", "hp"], ["level", "level"], ["crowd", "press_hp"], ["danger", "danger"]]:
		var s = series.get(pair[1])
		if not (s is Dictionary) or not (s.get("mean") is Array):
			continue
		var vs := PackedFloat32Array()
		for v in s["mean"]:
			vs.append(float(v) if (v is float or v is int) else NAN)
		vs.resize(ts.size())
		out[pair[0]] = vs
	var summ = doc.get("summary")
	out["players"] = int(summ.get("ok", 0)) if summ is Dictionary else 0
	return out if out.size() > 2 else {}


func _start_game() -> void:
	var run := run_node()
	run.seed_dice(run_seed)
	# the creatures' and the pickups' own dice, seeded right after their _ready randomizes them (sim_run.gd's way)
	run.launch_override = {"character": hero, "map": map_id, "map_seed": run_seed, "sim_clock": true, "sim_fast": false, "watch": true}
	var scene = load(GAME_SCENE)
	if scene == null:
		problems.append("the Game scene did not load")
		return
	game = scene.instantiate()
	sub.add_child(game)


func _on_node_added(node: Node) -> void:
	var nm := str(node.name)
	if (nm == "EnemyManager" or nm == "PickupManager") and not _seeded.has(nm) and node.get("_rng") is RandomNumberGenerator:
		_seeded[nm] = true
		node.ready.connect(func() -> void:
			var r: RandomNumberGenerator = node.get("_rng")
			r.seed = hash([run_seed, nm]), CONNECT_ONE_SHOT)
		return
	# what the run's end sends to the window's root (UiFx.go's fade, the Results scene): not in the Watch
	var root := get_tree().root
	if node.get_parent() == root and node != self:
		if (node is CanvasLayer and (node as CanvasLayer).layer == 100) or str(node.scene_file_path) == RESULTS_SCENE:
			node.queue_free.call_deferred()


# ---------------------------------------------------------------- every frame

func run_node() -> Node:
	return get_node_or_null("/root/Run")


func play_t() -> float:
	if ra != null and is_instance_valid(ra):
		return float(ra.get("play_t"))
	return _last_play


func _game_ok() -> bool:
	return game != null and is_instance_valid(game)


## The tree held paused while the Watch is paused: a timer of the game's own (the beat between two screens) may unpause
## it between frames, so every physics step looks again.
func _on_physics() -> void:
	if clock.paused and _game_ok() and not ended:
		get_tree().paused = true


func _on_frame() -> void:
	# the frame's share of wall time first (WatchClock.pace: --fixed-fps leaves the frame rate to the Watch)
	var enter := Time.get_ticks_usec()
	if _profile and _prof_us0 > 0:
		var work := enter - _prof_us0
		if _prof_drawn:
			_prof_draw_us += work
			_prof_draw_n += 1
		else:
			_prof_sim_us += work
			_prof_sim_n += 1
	# pass 82: the game's own pause screen up: the frames come as at 1x for it (WatchClock.game_hold)
	clock.game_hold = _attached and not ended and game_pause_up()
	var wait := clock.pace(enter, ended or not _attached)
	if wait > 0:
		OS.delay_usec(wait)
		_prof_wait_us += wait
	var us0 := Time.get_ticks_usec()
	_prof_us0 = us0
	var wall_dt := float(us0 - _last_us) / 1000000.0
	_last_us = us0
	if _wall_cap > 0.0 and float(Time.get_ticks_msec()) / 1000.0 > _wall_cap and not ended:
		print("watch: the wall limit (%d s) came: the run ends here" % int(_wall_cap))
		autoquit = true
		end_now()
	_take_shot_if_due()
	_run_actions()
	_drive_clicks()
	if ended or not _game_ok():
		_tick_panel(wall_dt)
		return
	if not _attached:
		_attach()
		if not _attached:
			return
	if bool(game.get("_ended")):
		_finish_run()
		return
	var pt := play_t()
	var dplay := pt - _last_play
	_last_play = pt
	clock.measure(wall_dt, dplay)
	_check_fixed_fps()
	# a step or a run to the next level-up that has come to its end pauses before the bot answers the cards
	if clock.reached_end(pt, level_cards_up()):
		_charts_dirty = true
		_refresh_left = 0.0
	# the Watch's pause holds the tree; going on hands it back to the game's own state
	var tree := get_tree()
	if clock.paused:
		tree.paused = true
		_forced_pause = true
	elif _forced_pause:
		tree.paused = bool(game.get("paused"))
		_forced_pause = false
	if clock.paused != _was_paused:
		_was_paused = clock.paused
		clock.reset_measure()
	_apply_engine(us0)
	if not clock.paused:
		var b0 := Time.get_ticks_usec()
		_tick_bot(wall_dt)
		_acc_bot_us += Time.get_ticks_usec() - b0
		if limit > 0.0 and pt >= limit and not _limit_called:
			_limit_called = true
			print("watch: the limit (%s of play) came: the run ends" % DATA.mmss(limit))
			game.end_run()
	var p0 := Time.get_ticks_usec()
	_read_data()
	_tick_panel(wall_dt)
	_acc_panel_us += Time.get_ticks_usec() - p0
	_count_cost(wall_dt)


## The panel's and the bot's cost, ms a frame, every 2 wall seconds (the chart and strip drawing counted in).
func _count_cost(wall_dt: float) -> void:
	_acc_frames += 1
	_acc_left -= wall_dt
	if _acc_left > 0.0:
		return
	_acc_left = 2.0
	_acc_panel_us += panel.take_draw_us()
	panel_ms = float(_acc_panel_us) / 1000.0 / float(maxi(_acc_frames, 1))
	bot_ms = float(_acc_bot_us) / 1000.0 / float(maxi(_acc_frames, 1))
	_acc_frames = 0
	_acc_panel_us = 0
	_acc_bot_us = 0


func _attach() -> void:
	if game.get("player") == null or game.get_node_or_null("RunAnalytics") == null:
		return
	ra = game.get_node_or_null("RunAnalytics")
	_attached = true
	_attach_wall = float(Time.get_ticks_msec()) / 1000.0
	if repo != "":
		ra.set("mirror_root", repo.path_join("analytics"))
	var hdr = ra.get("header")
	if hdr is Dictionary:
		hdr["watch"] = {"bot": "", "board": str(args.get("board_label", "")), "talents": str(args.get("talents", "none")),
			"ref": ref_label}
	if game.get("damage_numbers") != null and game.damage_numbers and not numbers_on:
		game.damage_numbers.suppressed = true
	_make_bot()
	# pass 82: a click in the phone view never steers the hero, nor do the keys (the bot's writes still drive him)
	_mute_hero_input()
	if hdr is Dictionary:
		hdr["watch"]["bot"] = bot_kind
		var o := {}
		for k in bot_opts:
			o[str(k)] = bot_opts[k]
		hdr["watch"]["bot_opts"] = o
	_refresh_left = 0.0


func _make_bot() -> void:
	var opts := bot_opts.duplicate()
	opts["seed"] = run_seed
	if not opts.has("death"):
		opts["death"] = death
	if str(args.get("bot", "auto")) != "stub" and ResourceLoader.exists(BOT_PATH):
		var s = load(BOT_PATH)
		if s is GDScript and (s as GDScript).can_instantiate():
			bot = s.new(game, opts)
			bot_kind = "bot"
		else:
			problems.append("tools/bot/Bot.gd did not load: the stand-in bot plays")
	if bot == null:
		bot = STUB.new(game, opts)
		bot_kind = "stub"
	if bot.has_signal("decided"):
		bot.decided.connect(_on_decided)


func _on_decided(entry: Dictionary) -> void:
	data.add_decision(entry)
	_refresh_left = minf(_refresh_left, 0.25)


func _check_fixed_fps() -> void:
	if _fixed_checked >= 30:
		return
	_fixed_checked += 1
	if absf(Engine.time_scale - 1.0) > 0.001:
		return
	var dt := get_process_delta_time()
	if _fixed_checked == 30 and absf(dt - 1.0 / CLOCK.STEP_HZ) > 0.0005:
		problems.append("Godot was started without --fixed-fps 60: above 1x only the drawing speeds up")


## The engine's clock for this frame: the time scale (the Watch's slow speeds composed with the game's own), whether
## the frame is drawn, the sound.
func _apply_engine(now_us: int) -> void:
	Engine.time_scale = clock.compose(Engine.time_scale)
	var sp := clock.running_speed()
	var draw := clock.draw_due(now_us) or _shot_frames > 0
	RenderingServer.render_loop_enabled = draw
	_prof_drawn = draw
	# a frame that is not drawn skips the work that only draws (the run sim's fast mode, Run.sim_mode: the crowd's, the
	# shots' and the pickups' drawing, effects, the HUD's frame, sounds); nothing that moves a number changes
	var run := run_node()
	if run != null:
		run.sim_mode = skip_draw_work and not draw
	AudioServer.set_bus_mute(0, not sound_on or sp > 1.0)
	if game.get("damage_numbers") != null and game.damage_numbers:
		game.damage_numbers.suppressed = not numbers_on or sp > 2.0


## The bot's frame. A screen that just came up stays HOLD_S wall seconds (less above 1x) before the bot answers it, so
## a watcher sees the cards; one left up STUCK_S is reported, and Down! is answered by `death` then.
func _tick_bot(wall_dt: float) -> void:
	if bot == null:
		return
	# pass 82: the game paused by its own screen (the player's): the bot neither answers it nor plays; no stuck count
	if game_pause_up():
		_screen_key = ""
		_screen_up = 0.0
		return
	var key := screen_key()
	if key != "":
		if key != _screen_key:
			_screen_key = key
			_screen_held = 0.0
			_screen_up = 0.0
		_screen_held += wall_dt
		_screen_up += wall_dt
		if _screen_up > STUCK_S:
			_screen_up = 0.0
			_unstick(key)
		if _screen_held < HOLD_S / maxf(clock.running_speed(), 1.0):
			return
	else:
		_screen_key = ""
		_screen_up = 0.0
	bot.tick(get_process_delta_time())


## The screens up now ("cards,gate", "" for none): Game.visible_modals and the TAP TO GO gate.
func screen_key() -> String:
	if not _game_ok():
		return ""
	var vis: Array = game.visible_modals()
	if game.resume_gate and game.resume_gate.visible:
		vis.append("gate")
	return ",".join(PackedStringArray(vis))


## Whether a level-up's cards are on screen waiting for a pick (not a mutation offer).
func level_cards_up() -> bool:
	if not _game_ok():
		return false
	var cs = game.get("cards")
	return cs != null and cs.visible and not (cs._offer as Array).is_empty() and not cs._picking and not cs.path_mode


func _unstick(key: String) -> void:
	var msg := "the bot left the %s screen up for %d s" % [key, int(STUCK_S)]
	print("watch: " + msg)
	if not problems.has(msg):
		problems.append(msg)
	if key.contains("revive") and game.revive_screen and game.revive_screen.visible:
		game.revive_screen._decide("give_up")


func _read_data() -> void:
	if ra == null or not is_instance_valid(ra):
		return
	var n: int = data.read_rows(ra.get("samples"))
	var p = game.get("player")
	data.read_events(ra.get("events"), p.damage_log if p != null else [])
	if n > 0:
		_charts_dirty = true
		data.fill_decisions(play_t())


func _tick_panel(wall_dt: float) -> void:
	_refresh_left -= wall_dt
	_chart_left -= wall_dt
	_log_left -= wall_dt
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH_S
		panel.refresh()
		_place_badge()
	if _charts_dirty and _chart_left <= 0.0:
		_chart_left = CHART_EVERY
		_charts_dirty = false
		panel.update_charts()
	if _log_left <= 0.0:
		_log_left = _log_every
		if not ended and _attached:
			print("watch: t %s clock %s level %d alive %d | speed asked %s reached %.2fx | panel %.2f ms, bot %.2f ms a frame | %s" % [
				DATA.mmss(play_t()), DATA.mmss(float(run_node().elapsed)), int(run_node().level), int(run_node().alive),
				CLOCK.label(clock.running_speed()), clock.reached, panel_ms, bot_ms, "paused" if clock.paused else "running"])
			if _profile:
				_say_profile()


## profile=1: frames drawn and not, their mean work (ms), the waits, and the game's Perf buckets since the last line.
func _say_profile() -> void:
	var rep: Dictionary = Perf.report()
	var parts: Array = []
	for k in rep.keys():
		if rep[k] is float and not str(k) in ["worst_ms"]:
			parts.append([str(k), float(rep[k])])
	parts.sort_custom(func(a, b) -> bool: return float(a[1]) > float(b[1]))
	var txt := ""
	for pp in parts.slice(0, 10):
		txt += " %s %.2f" % [pp[0], pp[1]]
	print("watch: profile: drawn %d frames %.2f ms each, not drawn %d frames %.2f ms each, waited %.0f ms | process %.2f ms physics %.2f ms (last frame) | objects %d nodes %d | game buckets:%s" % [
		_prof_draw_n, float(_prof_draw_us) / 1000.0 / maxf(float(_prof_draw_n), 1.0), _prof_sim_n,
		float(_prof_sim_us) / 1000.0 / maxf(float(_prof_sim_n), 1.0), float(_prof_wait_us) / 1000.0,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.OBJECT_COUNT)), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), txt])
	_prof_draw_us = 0
	_prof_draw_n = 0
	_prof_sim_us = 0
	_prof_sim_n = 0
	_prof_wait_us = 0


# ---------------------------------------------------------------- the controls (the panel's buttons, the keys)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := (event as InputEventKey).keycode
	var handled := true
	match k:
		KEY_SPACE:
			toggle_pause()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			set_speed(float(CLOCK.SPEEDS[int(k - KEY_1)]))
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			set_speed(CLOCK.faster(clock.speed))
		KEY_MINUS, KEY_KP_SUBTRACT:
			set_speed(CLOCK.slower(clock.speed))
		KEY_PERIOD, KEY_KP_PERIOD:
			step_second()
		KEY_L:
			run_to_level()
		KEY_G:
			toggle_window()
		KEY_M:
			toggle_sound()
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()


func toggle_pause() -> void:
	clock.toggle_pause()
	_refresh_left = 0.0


func set_speed(s: float) -> void:
	clock.set_speed(s)
	clock.reset_measure()
	_refresh_left = 0.0


func step_second() -> void:
	clock.step(play_t())
	clock.reset_measure()
	_refresh_left = 0.0


func run_to_level() -> void:
	clock.to_level(int(run_node().level))
	clock.reset_measure()
	_refresh_left = 0.0


func toggle_window() -> void:
	panel.whole_run = not panel.whole_run
	_charts_dirty = true
	_chart_left = 0.0
	_refresh_left = 0.0


func toggle_sound() -> void:
	sound_on = not sound_on
	_refresh_left = 0.0


## Ends the run now (the End run button, the limit, the wall cap): the record and the decision log are saved.
func end_now() -> void:
	if ended or not _game_ok():
		if autoquit:
			_quit_soon()
		return
	clock.paused = false
	clock.mode = ""
	if _forced_pause:
		get_tree().paused = bool(game.get("paused"))
		_forced_pause = false
	game.end_run()


func open_meta(meta: String) -> void:
	if meta == "dashboard" and repo != "":
		OS.shell_open(repo.path_join("analytics/dashboard.html"))
	elif meta != "":
		OS.shell_open(meta)


# ---------------------------------------------------------------- the end

func _finish_run() -> void:
	ended = true
	_read_data()
	data.fill_decisions(play_t(), true)
	var run := run_node()
	var hdr: Dictionary = ra.get("header") if ra != null and is_instance_valid(ra) else {}
	var stamp := str(hdr.get("stamp", "run"))
	end_info = {"result": str(hdr.get("result", "end")), "t": play_t(), "clock": float(run.elapsed), "level": int(run.level),
		"kills": int(run.kills), "stamp": stamp}
	# the record: where RunAnalytics mirrored it (the repo's analytics/runs/tools/), else the user folder's copy
	var dir := repo.path_join("analytics/runs/tools") if repo != "" else ""
	var rec := dir.path_join(stamp + ".json") if dir != "" else ""
	if rec == "" or not FileAccess.file_exists(rec):
		dir = ProjectSettings.globalize_path("user://analytics/runs")
		rec = dir.path_join(stamp + ".json")
	end_info["record"] = rec
	var csv := dir.path_join(stamp + "_decisions.csv")
	var f := FileAccess.open(csv, FileAccess.WRITE)
	if f:
		f.store_string(data.decisions_csv(_names_for_csv()))
		f.close()
		end_info["csv"] = csv
	else:
		problems.append("could not write %s" % csv)
	# the last frame stays on the left; the game goes before its wait for the Results screen ends
	var img: Image = sub.get_texture().get_image() if sub else null
	if img != null and not img.is_empty():
		view.texture = ImageTexture.create_from_image(img)
		view.modulate = Color(0.55, 0.55, 0.6)
	game.queue_free()
	game = null
	ra = null
	# the bot stays for the panel's words (its intent, its options); it is never ticked again
	get_tree().paused = false
	_forced_pause = false
	run.sim_mode = false
	Engine.time_scale = 1.0
	RenderingServer.render_loop_enabled = true
	AudioServer.set_bus_mute(0, false)
	_charts_dirty = true
	_chart_left = 0.0
	_refresh_left = 0.0
	print("watch: END %s at %s of play (clock %s) level %d kills %d | record %s | decisions %s (%d) | panel %.2f ms a frame" % [
		end_info["result"], DATA.mmss(float(end_info["t"])), DATA.mmss(float(end_info["clock"])), int(end_info["level"]),
		int(end_info["kills"]), rec, str(end_info.get("csv", "not written")), data.decisions.size(), panel_ms])
	if autoquit:
		_quit_soon()


func _quit_soon() -> void:
	get_tree().create_timer(0.6, true, false, true).timeout.connect(func() -> void:
		_release_lock()
		get_tree().quit(0))


func _names_for_csv() -> Dictionary:
	var out := {}
	for d in data.decisions:
		var id := str(d.get("taken", ""))
		if id != "":
			out[id] = name_of(id)
	return out


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not ended and ra != null and is_instance_valid(ra):
		# the window closed mid-run: the recorder writes its record as "quit" when the game leaves the tree; the decision
		# log goes beside it now
		_read_data()
		data.fill_decisions(play_t(), true)
		var hdr: Dictionary = ra.get("header")
		var dir := repo.path_join("analytics/runs/tools") if repo != "" else ProjectSettings.globalize_path("user://analytics/runs")
		DirAccess.make_dir_recursive_absolute(dir)
		var csv := dir.path_join(str(hdr.get("stamp", "run")) + "_decisions.csv")
		var f := FileAccess.open(csv, FileAccess.WRITE)
		if f:
			f.store_string(data.decisions_csv(_names_for_csv()))
			f.close()
			print("watch: closed mid-run at %s of play: decisions %s" % [DATA.mmss(play_t()), csv])
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_release_lock()


## The Watch's lock (watch.py takes it with this process's pid): let go when the window closes.
func _release_lock() -> void:
	var lk := str(args.get("lock", ""))
	if lk == "" or not DirAccess.dir_exists_absolute(lk):
		return
	var owner := lk.path_join("owner.json")
	if FileAccess.file_exists(owner):
		var o = JSON.parse_string(FileAccess.get_file_as_string(owner))
		if o is Dictionary and int(o.get("pid", 0)) != OS.get_process_id():
			return
		DirAccess.remove_absolute(owner)
	DirAccess.remove_absolute(lk)


# ---------------------------------------------------------------- captures and scripted checks

## shots=<dir> shots_at=<play seconds>: the whole window as PNGs at those moments and at the end (three frames after
## the panel's refresh, the frames drawn whatever the speed). actions=<when>:<what>,... (checks): <when> is p<play s>
## or w<wall s after the action before it (the first: after the run came up)>; <what> is pause, go, step, level, speed=<x>, shot=<name>, end or say; each done
## once, in order, with a line in the log saying the run's state then. Pass 82: also `click=<x>/<y>` (a click at that
## point of the game's 1080-wide canvas), `gamepause` (a click on the HUD's pause disc), `gametab=<0|1|2>` (a click on
## the pause screen's tab), `gameslider=<i>/<0..1>` (the pause screen's i-th slider dragged from its thumb to that share
## of its track), `gameresume` (a click on its RESUME) and `whole` (the charts' whole run / last 3 minutes): the clicks
## and drags go through the window's own input (Input.parse_input_event), the whole way the mouse goes.
func _take_shot_if_due() -> void:
	if _shots_dir == "":
		return
	if _shot_frames > 0:
		_shot_frames -= 1
		if _shot_frames == 0:
			var img := get_viewport().get_texture().get_image()
			if img != null and not img.is_empty():
				DirAccess.make_dir_recursive_absolute(_shots_dir)
				var p := _shots_dir.path_join(_shot_name + ".png")
				img.save_png(p)
				print("watch: shot %s" % p)
		return
	if _shot_wanted != "":
		_start_shot(_shot_wanted)
		_shot_wanted = ""
		return
	var due := ""
	if ended and not _end_shot:
		_end_shot = true
		_shots.clear()
		due = "end"
	elif not ended and not _shots.is_empty() and play_t() >= float(_shots[0]):
		due = "t%04d" % int(_shots.pop_front())
	if due != "":
		_start_shot(due)


func _start_shot(nm: String) -> void:
	_shot_name = nm
	_shot_frames = 3
	_charts_dirty = true
	_chart_left = 0.0
	_refresh_left = 0.0
	panel.refresh()
	panel.update_charts()


func _read_actions() -> void:
	for part in str(args.get("actions", "")).split(",", false):
		var i := part.find(":")
		if i <= 1:
			continue
		var when := part.substr(0, i).strip_edges()
		var kind := when.substr(0, 1)
		if not (kind in ["p", "w"]) or not when.substr(1).is_valid_float():
			continue
		_actions.append({"wall": kind == "w", "at": float(when.substr(1)), "what": part.substr(i + 1).strip_edges()})


func _run_actions() -> void:
	if _actions.is_empty() or not _attached:
		return
	var a: Dictionary = _actions[0]
	var now := (float(Time.get_ticks_msec()) / 1000.0 - _attach_wall) if bool(a["wall"]) else play_t()
	if now < float(a["at"]):
		return
	_actions.pop_front()
	# a wall time counts from the action before it (the first from the run coming up)
	_attach_wall = float(Time.get_ticks_msec()) / 1000.0
	var what := str(a["what"])
	match what:
		"pause":
			if not clock.paused:
				toggle_pause()
		"go":
			if clock.paused:
				toggle_pause()
		"step":
			step_second()
		"level":
			run_to_level()
		"end":
			end_now()
		"say":
			pass
		_:
			if what.begins_with("speed="):
				set_speed(float(what.substr(6)))
			elif what.begins_with("shot="):
				_shot_wanted = what.substr(5)
			else:
				_game_action(what)
	print("watch: action %s at %s %.1f: play %.2f, level %d, %s, mode '%s', speed %s, cards up %s, screens '%s', reached %.2fx" % [what,
		"wall" if bool(a["wall"]) else "play", float(a["at"]), play_t(), int(run_node().level), "paused" if clock.paused else "running",
		clock.mode, CLOCK.label(clock.speed), str(level_cards_up()), screen_key(), clock.reached])


# ---------------------------------------------------------------- words for the panel

## The damage sources that are no content item (RunAnalytics.SOURCE_NAMES, the Sim tab's SOURCE_WORDS).
const SOURCE_WORDS := {"blast": "Blast", "revive": "Revive blast", "grand_finale": "Grand Finale", "powder_keg": "Powder Keg",
	"loose_rocket": "Loose rocket", "thorns": "Thorns", "other": "Other", "something": "Something"}


func name_of(id: String) -> String:
	if names.has(id):
		return str(names[id])
	if SOURCE_WORDS.has(id):
		names[id] = SOURCE_WORDS[id]
		return str(SOURCE_WORDS[id])
	var reg := get_node_or_null("/root/Registry")
	var nm := id
	if reg != null:
		var d = reg.weapon(id)
		if d == null:
			d = reg.passive(id)
		if d == null:
			d = reg.perk(id)
		if d == null:
			d = reg.mutation(id)
		if d == null:
			d = reg.enemy(id)
		if d == null:
			d = reg.pickup(id)
		if d == null:
			d = reg.structure(id)
		if d == null:
			d = reg.character(id)
		if d != null and str(d.get("display_name")) != "":
			nm = str(d.get("display_name"))
	names[id] = nm
	return nm


func passive_def(id: String) -> Resource:
	var reg := get_node_or_null("/root/Registry")
	return reg.passive(id) if reg != null else null


func hero_name() -> String:
	return name_of(hero)


func header_words() -> String:
	var parts := PackedStringArray()
	var board := str(args.get("board_label", ""))
	parts.append("board %s" % (board if board != "" else str(args.get("talents", "none"))))
	parts.append("seed %d" % run_seed)
	parts.append("map %s" % map_id.replace("_", " "))
	parts.append("bot: " + bot_words())
	if limit > 0.0:
		parts.append("ends at %s" % DATA.mmss(limit))
	if not ref.is_empty():
		parts.append("grey: the Sim's average, %s (%d runs)" % [ref_label, int(ref.get("players", 0))])
	return "  ·  ".join(parts)


## The bot in a few words: its preset, skill and style as it resolved them, and the options given ("the stand-in").
func bot_words() -> String:
	if bot_kind == "stub":
		return "the stand-in (bot=stub)"
	if bot == null:
		return "starting"
	var o = bot.get("opts")
	var bits := PackedStringArray()
	if o is Dictionary:
		bits.append(str(o.get("preset", "?")))
		bits.append("skill %s" % str(o.get("skill", "?")))
		bits.append(str(o.get("style", "")))
	for k in bot_opts:
		if not str(k) in ["preset", "skill", "style"]:
			bits.append("%s %s" % [str(k), str(bot_opts[k])])
	return ", ".join(bits)


func status_words() -> String:
	var parts := PackedStringArray()
	if ended:
		parts.append("run over")
	elif clock.paused:
		parts.append("paused" + (" (and in game)" if clock.game_hold else ""))
	elif clock.game_hold:
		parts.append("paused (in game): Resume there goes on at " + CLOCK.label(clock.speed))
	elif clock.mode == "step":
		parts.append("stepping 1 s")
	elif clock.mode == "level":
		parts.append("to the next level-up")
	else:
		parts.append("running " + CLOCK.label(clock.speed))
	if not ended and not clock.paused and not clock.game_hold and clock.reached > 0.0:
		parts.append("reached %.1fx%s" % [clock.reached, " (short)" if clock.short() else ""])
	parts.append("panel %.2f ms, bot %.2f ms a frame" % [panel_ms, bot_ms])
	for p in problems:
		parts.append(str(p))
	return "  ·  ".join(parts)


func end_words() -> String:
	var res := str(end_info.get("result", "end"))
	var what: String = {"death": "He fell", "extract": "He got out", "abandon": "Given up", "end": "Ended", "quit": "Stopped"}.get(res, res)
	var t := "[b]Run over[/b]: %s at %s of play (clock %s), level %d, %d kills.  " % [what, DATA.mmss(float(end_info.get("t", 0.0))),
		DATA.mmss(float(end_info.get("clock", 0.0))), int(end_info.get("level", 0)), int(end_info.get("kills", 0))]
	var rec := str(end_info.get("record", ""))
	t += "Record: [url=%s]%s[/url]" % [rec, _short(rec)]
	if end_info.has("csv"):
		t += "  ·  decisions: [url=%s]%s[/url]" % [str(end_info["csv"]), str(end_info["csv"]).get_file()]
	if repo != "":
		t += "  ·  [url=dashboard]open the dashboard[/url] (it lists the run under the tool runs)"
	return t


func _short(p: String) -> String:
	if repo != "" and p.begins_with(repo):
		return p.substr(repo.length() + 1)
	return p


# ---------------------------------------------------------------- the game's own screens under the mouse (pass 82)

## A check's click: pressed now, let go this many frames later.
const CLICK_FRAMES := 3

## the finger the mouse makes on the phone view: down, and where (the SubViewport's pixels)
var _finger_down := false
var _finger_at := Vector2.ZERO
## the checks' clicks waiting for their release: [{at: window position, frames}]
var _clicks: Array = []


## Whether the game's own pause screen is up (the player paused from the HUD's disc in the phone view).
func game_pause_up() -> bool:
	if not _game_ok():
		return false
	var ps = game.get("pause_screen")
	return ps != null and is_instance_valid(ps) and (ps as CanvasItem).visible


## The hero's input deaf to touches and keys (PlayerInput.enabled off: no stick from a click in the thumb zone, no WASD);
## the bot's writes (wants_move, origin, touch_pos) still drive him.
func _mute_hero_input() -> void:
	var p = game.get("player") if _game_ok() else null
	var inp = p.get("input") if p != null else null
	if inp != null and inp.get("enabled") != null:
		inp.set("enabled", false)


## The mouse on the phone view (its gui_input): a left press, the drag while it is held and the release become the touch
## the phone sends (finger_event), pushed into the game's SubViewport, whose stretch puts it on the game's canvas. The
## window's own touches (emulated from the mouse) and every other button are swallowed: one finger, no doubles.
func _on_view_input(e: InputEvent) -> void:
	view.accept_event()
	if not _game_ok() or ended or sub == null:
		return
	var f := finger_event(e, view.size, Vector2(sub.size), _finger_down, _finger_at)
	if f.is_empty():
		return
	_finger_down = bool(f["down"])
	_finger_at = f["at"]
	sub.push_input(f["event"])


## The touch a mouse event on the phone view makes (pure; tests/pass82_watch_test.gd): {event: an InputEventScreenTouch
## (a left press or release) or InputEventScreenDrag (the mouse moving while held), finger 0, at the view's local position
## x sub_size / view_size (the SubViewport's pixels); down: the finger after it; at: that position}. {} for anything else
## (another button, a move with nothing held, a release with nothing held, the window's emulated touches).
static func finger_event(e: InputEvent, view_size: Vector2, sub_size: Vector2, down: bool, last: Vector2) -> Dictionary:
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		return {}
	var k := sub_size / view_size
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT or mb.pressed == down:
			return {}
		var at := mb.position * k
		var t := InputEventScreenTouch.new()
		t.index = 0
		t.position = at
		t.pressed = mb.pressed
		t.double_tap = mb.pressed and mb.double_click
		return {"event": t, "down": mb.pressed, "at": at}
	if e is InputEventMouseMotion and down:
		var mm := e as InputEventMouseMotion
		var at2 := mm.position * k
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = at2
		d.relative = at2 - last
		d.screen_relative = d.relative
		d.velocity = mm.velocity * k
		d.screen_velocity = d.velocity
		return {"event": d, "down": true, "at": at2}
	return {}


## The window position of a point `p` of the game's canvas (1080 wide; Control.get_global_transform_with_canvas's
## space), through the phone view's place and size.
func canvas_to_window(p: Vector2) -> Vector2:
	var cs := Vector2(sub.size_2d_override) if sub != null and sub.size_2d_override.x > 0 else Vector2(CANVAS_W, CANVAS_W * ASPECT.y / ASPECT.x)
	return view.global_position + p * view.size / cs


## The middle of a game control in its canvas's space (its CanvasLayer's transform included).
static func canvas_middle(c: Control) -> Vector2:
	return c.get_global_transform_with_canvas() * (c.size * 0.5)


## A check's click at `p` on the game's canvas: the mouse pressed there now and let go CLICK_FRAMES frames later, both
## through the window's own input (the whole way a click goes: the view, finger_event, the SubViewport).
func click_canvas(p: Vector2) -> void:
	var w := canvas_to_window(p)
	_send_mouse(w, true)
	_clicks.append({"at": w, "frames": CLICK_FRAMES})


## A check's drag on the game's canvas from `a` to `b`: pressed at `a`, moved there over `frames` frames, let go at `b`.
func drag_canvas(a: Vector2, b: Vector2, frames: int = 10) -> void:
	var wa := canvas_to_window(a)
	_send_mouse(wa, true)
	_clicks.append({"at": canvas_to_window(b), "from": wa, "last": wa, "frames": frames, "n": frames})


func _drive_clicks() -> void:
	if _clicks.is_empty():
		return
	var left: Array = []
	for c in _clicks:
		c["frames"] = int(c["frames"]) - 1
		if c.has("from"):
			# a drag: the mouse moves on with the button held, the last step on the end itself
			var f := 1.0 - float(maxi(int(c["frames"]), 0)) / float(maxi(int(c["n"]), 1))
			var w: Vector2 = (c["from"] as Vector2).lerp(c["at"], f)
			_send_motion(w, w - (c["last"] as Vector2))
			c["last"] = w
		if int(c["frames"]) <= 0:
			_send_mouse(c["at"], false)
		else:
			left.append(c)
	_clicks = left


func _send_motion(w: Vector2, rel: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = w
	mm.global_position = w
	mm.relative = rel
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(mm)


func _send_mouse(w: Vector2, pressed: bool) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.position = w
	mb.global_position = w
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(mb)


## The checks' game actions (actions=): click=<x>/<y>, gamepause, gametab=<i>, gameresume, gameslider=<i>/<0..1>,
## whole.
func _game_action(what: String) -> void:
	if what == "whole":
		toggle_window()
		return
	if not _game_ok():
		return
	if what.begins_with("click="):
		var xy := what.substr(6).split("/")
		if xy.size() == 2:
			click_canvas(Vector2(float(xy[0]), float(xy[1])))
		return
	var ps = game.get("pause_screen")
	if what == "gamepause":
		var hud = game.get("hud")
		var b = hud.get("_pause_btn") if hud != null else null
		if b is Control:
			click_canvas(canvas_middle(b))
	elif what.begins_with("gametab=") and ps != null:
		var tabs = ps.get("_tabs")
		var list = tabs.get("_tabs") if tabs != null else null
		var i := int(what.substr(8))
		if list is Array and i >= 0 and i < (list as Array).size():
			click_canvas(canvas_middle(list[i]))
	elif what.begins_with("gameslider=") and ps != null:
		# the i-th slider on the pause screen (the Options tab: Sound, Music) dragged from its thumb to that share of it
		var bits := what.substr(11).split("/")
		var sliders: Array = []
		_collect_sliders(ps, sliders)
		var i := int(bits[0])
		if bits.size() == 2 and i >= 0 and i < sliders.size():
			var sl: Range = sliders[i]
			var xf: Transform2D = (sl as Control).get_global_transform_with_canvas()
			var w := (sl as Control).size.x
			var span := maxf(sl.max_value - sl.min_value, 0.0001)
			var y := (sl as Control).size.y * 0.5
			var a := xf * Vector2(w * clampf((sl.value - sl.min_value) / span, 0.0, 1.0), y)
			var b := xf * Vector2(w * clampf(float(bits[1]), 0.0, 1.0), y)
			drag_canvas(a, b)
	elif what == "gameresume" and ps != null:
		# RESUME: the lowest button on the pause screen
		var best: Control = null
		for c in (ps as Node).get_children():
			if c is Control and (c as Control).visible and c.has_signal("pressed"):
				if best == null or canvas_middle(c).y > canvas_middle(best).y:
					best = c
		if best != null:
			click_canvas(canvas_middle(best))


## The game's sliders (TouchSlider: the kit's WSlider) under `n`, in tree order.
static func _collect_sliders(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is TouchSlider and (c as Control).is_visible_in_tree():
			out.append(c)
		_collect_sliders(c, out)
