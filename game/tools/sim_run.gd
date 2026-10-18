## The run sim's player (pass 77, lane SIMRUN; Garry: "simulate like 10 players ... charts per second"): one simulated
## player's whole run of the real game, headless, driven by a bot, written as one JSON of per-second series for the
## Level Editor's Sim tab (tools/sim_batch.py runs several side by side on a snapshot of game/ and averages them). Every
## multiplier, the cap, the timeline, specials, Elites, bosses and their HP pegging count because it is the game itself.
##   "$GODOT" --headless --fixed-fps 60 --path game --script res://tools/sim_run.gd -- out=<file> hero=drifter seed=1 \
##       limit=1500 board=1.5 death=end [talents=grit:000,drive:1,...] [fast=1] [map=red_canyon] [progress=10] [wall=2700]
##       [res=504x1122] [unlocks=all]
## Args, the output and the progress file: tools/dl/p77/keys_SIMRUN.md. Safe to run side by side: the launch is set in
## memory (Run.launch_override, never user://debug_launch.json), the Save is sandboxed before anything changes (nothing
## reaches the disk), and the run recorder keeps its rows in memory (RunAnalytics.memory_only: no analytics file).
## The dice are seeded (Run.seed_dice: the global stream, the card offers and chests, the director; the creatures' and
## the pickups' own dice here; the map layout from the seed); the structures' placement and the Totem Poles' gifts stay
## random (their own dice, randomized where this tool cannot reach).
## The bot (pass 80, lane BOT): tools/bot/Bot.gd, shared with the Watch; its options come in as args (preset=, skill=,
## style=, reaction=, dodge=, daring=, stray=, explore=, totems=, barrels=, powerups=, structures=, shop=, stranger=, boss=,
## cards=; tools/dl/p80/keys_BOT.md) and preset=sim77 is pass 77's bot exactly (its rules: tools/dl/p77/
## balancing_SIMRUN.md). The portal is always continued, Down! answered by `death`. A watchdog writes what it has with
## end_reason "stuck:<what>" when a screen stays up more than STUCK_S seconds or the wall clock passes `wall`.
## Autoloads are reached through the tree (SceneTree scripts compile before they exist); no game class is named here.
## Pass 84 (lane SIMVIEW): a sampler of its own adds the Timeline overlay's series (the `_sv_*` functions at the end).
extends SceneTree

const BOT := preload("res://tools/bot/Bot.gd")
const CARDS := preload("res://tools/bot/BotCards.gd")
const PROBE := preload("res://tools/difficulty_probe.gd")
const PERF := preload("res://core/systems/Perf.gd")
const SCHEMA := 1
## a screen (or a pause with none) up longer than this many seconds of the frame clock is stuck
const STUCK_S := 10.0
## the hero down this long with nothing asking (no Down!, no Phoenix) is stuck too
const DOWN_STUCK_S := 12.0
## the bot's numbers live in tools/bot/Bot.gd since pass 80 (forwards for the older tests and tools)
const CHEST_RANGE := BOT.CHEST_RANGE
const MUST_PATIENCE := BOT.MUST_PATIENCE
const BOSS_LEASH := BOT.BOSS_LEASH
const BOSS_BACK := BOT.BOSS_BACK
const LURE_R := BOT.LURE_R

var _out := ""
var _hero := "drifter"
var _seed := 1
var _limit := 1500.0
var _board := 0.0
var _death := "end"
var _map := "red_canyon"
## pass 87 (lane SGAME): the stage the run plays, 1-based (stage=k; the launch's `stage`, Game._start_chosen_stage)
var _stage := 1
var _progress := 10.0
var _wall := 2700.0
var _res := Vector2i(504, 1122)
var _grit := 0
## pass 88 (lane MIRROR): -1 (the default) leaves Spite (now Stakes: Difficulty 0 / Boss 1) out of a board= board
var _spite := -1
var _unlocks := "all"
var _arg_error := ""
## talents=<id>:<rank>:<form>,... (or <id>:<picks>): the Upgrade board talent by talent, {id: [form a rank]}; empty =
## the board= ranks
var _talent_arg := ""
## fast=1 (the default): the game's run sim mode (Run.sim_mode: nothing is drawn or played, about 30 % less wall time,
## and a seed replays exactly); fast=0 plays it all (a seed does not replay there: the sounds' gaps run on real time and
## each sound draws its pitch from the global dice). Measured against each other in pass 77 (tools/dl/p77/
## history_SIMRUN.md): no difference beyond the noise once the rules that counted real time count the run's clock.
var _fast := true
## trace=<frames> (a tool for finding what makes a seed unrepeatable): a state line every frame for that many frames
var _trace := 0
var _trace_n := 0
## the bot's options as given (args; Bot.resolve_opts fills in the rest from the preset); lure_r is stray's old name
var _bot_raw: Dictionary = {}
const BOT_ARGS := ["preset", "skill", "style", "reaction", "dodge", "daring", "stray", "explore", "totems", "barrels", "powerups",
	"structures", "shop", "stranger", "boss", "cards", "lure_w", "lure_close", "breakout", "specials", "portal"]

var _game: Node
var _run: Node
var _reg: Node
## the bot (tools/bot/Bot.gd), made when the game is up
var _bot = null
var _t := 0.0
var _boot_s := 0.0
var _done := false
var _next_progress := 0.0
var _talents: Dictionary = {}
var _talent_forms: Dictionary = {}
var _start_weapon := ""
var _screen := ""
var _screen_t := 0.0
var _down_t := 0.0
var _seeded: Dictionary = {}
var _first_dt := 0.0
var _fixed_dt := true
## the bot's own cost since the last progress line (microseconds, frames): the progress line's bot= ms a frame
var _bot_us := 0
var _bot_frames := 0
## profile=1: every progress line also prints the game's own frame buckets (core/systems/Perf.gd), ms a frame
var _profile := false
var _prof_wall_ms := 0
var _prof_frames := 0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var i := a.find("=")
		if i <= 0:
			continue
		var k := a.substr(0, i)
		var v := a.substr(i + 1)
		match k:
			"out": _out = v
			"hero": _hero = v
			"seed": _seed = int(v)
			"limit": _limit = float(v)
			"board": _board = float(v)
			"death": _death = v
			"map": _map = v
			"stage": _stage = maxi(int(v), 1)
			"progress": _progress = maxf(float(v), 1.0)
			"wall": _wall = float(v)
			"res":
				var wh := v.split("x")
				if wh.size() == 2 and int(wh[0]) > 0 and int(wh[1]) > 0:
					_res = Vector2i(int(wh[0]), int(wh[1]))
				else:
					_arg_error = "res must be WxH"
			"grit": _grit = int(v)
			"spite": _spite = int(v)
			"unlocks": _unlocks = v
			"lure_r": _bot_raw["stray"] = maxf(float(v), 0.0)
			"lure_w": _bot_raw["lure_w"] = maxf(float(v), 0.0)
			"lure_close": _bot_raw["lure_close"] = clampf(float(v), 0.0, 1.0)
			"profile": _profile = v == "1"
			"talents": _talent_arg = v
			"fast": _fast = v != "0"
			"trace": _trace = int(v)
			_:
				if BOT_ARGS.has(k):
					_bot_raw[k] = v
	if _seed == 0:
		_seed = 1
	# pass 77 (the lead): gold revives are leaving Down!; `gold` is read as `ad`
	if _death == "gold":
		_death = "ad"
	if not _death in ["ad", "end", "keep"]:
		_arg_error = "death must be ad, end or keep"
	if not _unlocks in ["all", "save"]:
		_arg_error = "unlocks must be all or save"
	if _out == "":
		_arg_error = "out=<file> is required"
	if _bot_raw.has("preset") and not BOT.PRESETS.has(str(_bot_raw["preset"])):
		_arg_error = "preset must be one of %s" % ", ".join(PackedStringArray(BOT.PRESETS.keys()))
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _say(s: String) -> void:
	print("sim: ", s)


func _start() -> void:
	if _arg_error != "":
		printerr("sim: " + _arg_error)
		quit(2)
		return
	var save := root.get_node_or_null("Save")
	_run = root.get_node_or_null("Run")
	_reg = root.get_node_or_null("Registry")
	var settings := root.get_node_or_null("Settings")
	if save == null or _run == null or _reg == null:
		printerr("sim: the autoloads did not load (a script error elsewhere); nothing run")
		quit(2)
		return
	if _reg.character(_hero) == null:
		printerr("sim: no hero '%s'" % _hero)
		quit(2)
		return
	if _reg.map(_map) == null:
		printerr("sim: no map '%s'" % _map)
		quit(2)
		return
	# nothing reaches the disk: not even a write the boot left pending (begin_sandbox flushes it first; side-by-side
	# players in one user folder would all write save.json at once), and from here on the sandbox (never ended: its flush
	# on quit writes nothing)
	save.set("_dirty", false)
	save.begin_sandbox()
	save.data["runs_started"] = 1
	# the Upgrade board as the difficulty probe writes it (its FORMS, a fraction by turns)
	var talents := {}
	if _board > 0.0:
		var k := 0
		for id: String in PROBE.FORMS.keys():
			var form: int = PROBE.FORMS[id]
			if id == "grit":
				form = _grit
			elif id == "spite":
				form = _spite
				if form < 0:
					k += 1
					continue
			var rank: int = PROBE.rank_for(_board, k)
			k += 1
			if rank <= 0:
				continue
			var picks: Array = []
			for _r in range(rank):
				picks.append(form)
			talents[id] = {"picks": picks, "rank": rank, "form": form}
			_talents[id] = rank
			_talent_forms[id] = ("B" if form == 1 else "A").repeat(rank)
	# talents= (the lead, Garry: "we should be able to specify ... what upgrades they have"): the board talent by talent,
	# every rank in the form given, as Save.talent_picks reads it (it replaces board=)
	if _talent_arg != "":
		var parsed := parse_talents(_talent_arg, (_reg.get("talents") as Dictionary).keys())
		if parsed.has("error"):
			printerr("sim: " + str(parsed["error"]))
			quit(2)
			return
		talents = {}
		_talents = {}
		for id in parsed:
			var picks: Array = parsed[id]
			if picks.is_empty():
				continue
			talents[id] = {"picks": picks, "rank": picks.size(), "form": int(picks[picks.size() - 1])}
			_talents[id] = picks.size()
			_talent_forms[id] = "".join(PackedStringArray(picks.map(func(f): return "B" if int(f) == 1 else "A")))
	save.data["talents"] = talents
	# every unlock quest done (unlocks=all): the whole content as designed is in the card pool
	if _unlocks == "all":
		var done: Array = []
		for qid in (_reg.get("quests") as Dictionary).keys():
			done.append(str(qid))
		save.data["quests_done"] = done
	# a player's settings, whatever the save held: the fixed camera (the autopilot steers north-up), ranged weapons on
	# what is on the screen, pierce drop-off; no hints, no floating numbers (nobody reads them)
	if settings:
		settings.camera_mode = 0
		settings.ranged_on_screen = true
		settings.pierce_falloff = true
		settings.hero_knockback = false
		settings.show_hints = false
		settings.damage_numbers = false
		settings.debug_mode = false
	# a phone's screen (the ranged weapons pick only what is on it): 9:20 with the canvas expanding as on Android
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.size = _res
	# the dice
	_run.seed_dice(_seed)
	# the creatures' and the pickups' own dice, seeded right after their _ready randomizes them
	node_added.connect(_on_node_added)
	# sim_clock: the rules that count real time count the run's clock (Run.rule_seconds), as on a phone, in both modes
	_run.launch_override = {"character": _hero, "map": _map, "map_seed": _seed, "analytics_memory": true, "sim_fast": _fast,
			"sim_clock": true, "stage": _stage}
	change_scene_to_file("res://game/Game.tscn")
	process_frame.connect(_tick)
	_write_progress("boot", "")


func _on_node_added(node: Node) -> void:
	var nm := str(node.name)
	if not (nm == "EnemyManager" or nm == "PickupManager") or _seeded.has(nm):
		return
	if not (node.get("_rng") is RandomNumberGenerator):
		return
	_seeded[nm] = true
	node.ready.connect(func() -> void:
		var r: RandomNumberGenerator = node.get("_rng")
		r.seed = hash([_seed, nm])
		_say("seeded %s's dice" % nm), CONNECT_ONE_SHOT)
	if _seeded.size() >= 2 and node_added.is_connected(_on_node_added):
		node_added.disconnect(_on_node_added)


func _ra() -> Node:
	return _game.get_node_or_null("RunAnalytics") if _game != null and is_instance_valid(_game) else null


func _play_t() -> float:
	var ra := _ra()
	return float(ra.get("play_t")) if ra else 0.0


func _tick() -> void:
	if _done:
		return
	if _trace > 0 and _trace_n < _trace:
		_say("frames process %d physics %d game %s" % [Engine.get_process_frames(), Engine.get_physics_frames(), "up" if _game != null else "no"])
	var dt: float = root.get_process_delta_time()
	_t += dt
	if _game == null and dt > 0.0:
		if _first_dt <= 0.0:
			_first_dt = dt
		elif absf(dt - _first_dt) > 1e-7:
			_fixed_dt = false
	if float(Time.get_ticks_msec()) / 1000.0 > _wall:
		_finish("stuck:wall")
		return
	if _game == null:
		var g = current_scene
		if g == null or not g.has_method("open_pause") or g.get("player") == null:
			if _t > 120.0:
				_finish("stuck:no_game")
			return
		_game = g
		_boot_s = float(Time.get_ticks_msec()) / 1000.0
		if _game.get("damage_numbers") != null and _game.damage_numbers:
			_game.damage_numbers.suppressed = true
		if not _run.weapons.is_empty():
			_start_weapon = str(_run.weapons[0].def.id)
		var o := _bot_raw.duplicate()
		o["seed"] = _seed
		o["death"] = _death
		o["t0"] = _t
		_bot = BOT.new(_game, o)
		_say("game up: hero %s seed %d board %.1f death %s limit %.0f map %s view %s (boot %.1f s) | bot %s" % [_hero, _seed, _board, _death,
			_limit, _map, str(root.get_visible_rect().size), _boot_s, str(_bot.opts["preset"])])
		# pass 84 (lane SIMVIEW): the Timeline overlay's own sampler
		_sv_start()
		return
	if not is_instance_valid(_game) or current_scene != _game or bool(_game.get("_ended")):
		_finish(_end_reason())
		return
	_watch(dt)
	if _done:
		return
	if _trace > 0 and _trace_n < _trace:
		_trace_line()
	var us := Time.get_ticks_usec()
	_bot.tick(dt)
	_bot_us += Time.get_ticks_usec() - us
	_bot_frames += 1
	_sv_frame()
	if bool(_game.get("_ended")):
		_finish(_end_reason())
		return
	var pt := _play_t()
	if pt >= _next_progress:
		_next_progress += _progress
		_write_progress("running", "")
	if pt >= _limit:
		var ra := _ra()
		var rows: Array = ra.get("samples") if ra else []
		if not rows.is_empty() and float((rows[rows.size() - 1] as Dictionary).get("t", 0.0)) >= _limit - 0.05:
			_finish("limit")


## trace=: one line of the run's state this frame (the hero, the crowd's and the pickups' sums, the tallies).
func _trace_line() -> void:
	_trace_n += 1
	var em = _game.enemies
	var sum := Vector3.ZERO
	var n := 0
	for i in range(em.MAX):
		if em.alive[i] == 1:
			sum += em.pos[i]
			n += 1
	var pk = _game.pickups
	var psum := Vector3.ZERO
	var pn := 0
	var pal: PackedByteArray = pk.alive
	var ppos: PackedVector3Array = pk.pos
	for i in range(pal.size()):
		if pal[i] == 1:
			psum += ppos[i]
			pn += 1
	var p: Vector3 = _game.player.global_position
	_say("trace %d pt %.4f hero %.4f,%.4f n %d sum %.3f,%.3f pk %d %.3f,%.3f kills %d xp %.2f hp %.2f proj %d" % [_trace_n, _play_t(), p.x, p.z, n, sum.x, sum.z,
		pn, psum.x, psum.z, int(_run.kills), float(_run.xp), float(_game.player.hp), int(_game.projectiles.get("count") if _game.projectiles.get("count") != null else -1)])


## Pass 87 (lane STOOLS): how the stage run ended, in Run.outcome()'s words when it ended by itself (a death, an
## extraction); a run the sim stopped (the limit, the wall, a stuck screen) says where it stood: "stopped" (before the
## boss), "stopped_after_boss" (the boss down, before Endless), "stopped_endless" (in Endless).
func _stage_outcome(reason: String) -> String:
	if (reason == "death" or reason == "extract") and _run.has_method("outcome"):
		return str(_run.call("outcome"))
	if bool(_run.get("endless")):
		return "stopped_endless"
	if bool(_run.get("stage_beaten")):
		return "stopped_after_boss"
	return "stopped"


## How the run ended on its own: extracted, given up on Down! (a death), or something else ended it.
func _end_reason() -> String:
	if bool(_run.extracted):
		return "extract"
	if bool(_run.died):
		return "death"
	return "end"


# ---------------------------------------------------------------- the screens

## The watchdog: a screen (or a pause with none up) that stays STUCK_S seconds of the frame clock, or the hero down
## DOWN_STUCK_S with nothing asking, ends the player as "stuck:<what>".
func _watch(dt: float) -> void:
	var vis: Array = _game.visible_modals()
	if _game.resume_gate and _game.resume_gate.visible:
		vis.append("gate")
	var key := ",".join(PackedStringArray(vis))
	if key == "" and bool(_game.paused):
		key = "paused"
	if key == "":
		_screen = ""
		_screen_t = 0.0
	elif key != _screen:
		_screen = key
		_screen_t = 0.0
	else:
		_screen_t += dt
		if _screen_t > STUCK_S:
			_finish("stuck:" + key)
			return
	if _game.player and _game.player.dead and key == "":
		_down_t += dt
		if _down_t > DOWN_STUCK_S:
			_finish("stuck:down")
	else:
		_down_t = 0.0


## What a card hands over (tools/bot/BotCards.gd since pass 80).
static func item_kind(card: Dictionary) -> String:
	return CARDS.item_kind(card)


## Whether Down! offers the ad revive now (tools/bot/Bot.gd since pass 80).
static func ad_offered(rs) -> bool:
	return BOT.ad_offered(rs)


# ---------------------------------------------------------------- the walk (tools/bot/Bot.gd since pass 80)

## The walk back to a living boss (Bot.boss_goal).
static func boss_goal(me: Vector3, boss: Vector3, back: bool) -> Dictionary:
	return BOT.boss_goal(me, boss, back)


## Whether a spot is within the boss's leash (Bot.within_leash).
static func within_leash(at: Vector3, boss: Vector3) -> bool:
	return BOT.within_leash(at, boss)


# ---------------------------------------------------------------- the cards

## talents=<list> (lane SIMUI's format): comma-separated `<id>:<picks>`, one form a rank (0 or A the first form, 1 or B
## the second: exactly Save.data.talents[id].picks, e.g. grit:000,drive:1,nerve:11), or `<id>:<rank>:<form>` (every rank
## in that form); a talent left out has no rank; `none` is an empty board. At most 6 ranks; `known` are the talent ids.
## Returns {id: [form a rank]} or {"error": text}.
static func parse_talents(arg: String, known: Array) -> Dictionary:
	var out := {}
	if arg.strip_edges() == "none":
		return out
	for part in arg.split(",", false):
		var bits := part.strip_edges().split(":")
		var id := bits[0].strip_edges()
		if not known.has(id):
			return {"error": "talents: no talent '%s' (%s)" % [id, ", ".join(PackedStringArray(known))]}
		var picks: Array = []
		if bits.size() == 2:
			for ch in bits[1].strip_edges().to_upper():
				if ch == "0" or ch == "A":
					picks.append(0)
				elif ch == "1" or ch == "B":
					picks.append(1)
				else:
					return {"error": "talents: '%s' picks are 0/1 (or A/B), one a rank" % part}
		elif bits.size() == 3:
			if not bits[1].strip_edges().is_valid_int():
				return {"error": "talents: '%s' rank must be a number" % part}
			var rank := clampi(int(bits[1]), 0, 6)
			var f := bits[2].strip_edges().to_upper()
			if not f in ["0", "1", "A", "B"]:
				return {"error": "talents: '%s' form must be 0, 1, A or B" % part}
			for _r in range(rank):
				picks.append(1 if f == "1" or f == "B" else 0)
		else:
			return {"error": "talents: '%s' is not <id>:<picks> or <id>:<rank>:<form>" % part}
		if picks.size() > 6:
			return {"error": "talents: '%s' has more than 6 ranks" % part}
		out[id] = picks
	return out


## A level-up card's tier for the bot (tools/bot/BotCards.gd since pass 80: pass 77's tiers).
static func card_tier(card: Dictionary) -> int:
	return CARDS.card_tier(card)


## The card pass 77's bot takes from `offer` (BotCards.choose_card).
static func choose_card(offer: Array, rng: RandomNumberGenerator) -> Dictionary:
	return CARDS.choose_card(offer, rng)


# ---------------------------------------------------------------- the end

func _finish(reason: String) -> void:
	if _done:
		return
	_done = true
	var doc := {}
	if _game != null and is_instance_valid(_game) and _ra() != null:
		doc = build_output(_ra(), reason)
	else:
		doc = {"meta": _meta(null, reason), "t": [], "events": [{"t": 0.0, "clock": 0.0, "kind": "end", "reason": reason}]}
	var ok := _store(_out, JSON.stringify(doc))
	_write_progress("done", reason)
	var m: Dictionary = doc.get("meta", {})
	_say("END %s | t %.1f clock %.1f stage %d level %d | deaths %d kills %d gold %d xp %.0f dmg %.0f | rows %d | wall %.1f s | %s%s" % [
		reason, float(m.get("end_t", 0.0)), float(m.get("end_clock", 0.0)), int(m.get("end_stage", 0)), int(m.get("end_level", 0)),
		int(m.get("deaths", 0)), int(m.get("kills", 0)), int(m.get("gold_total", 0)), float(m.get("xp_total", 0.0)), float(m.get("dmg_total", 0.0)),
		int(m.get("rows", 0)), float(m.get("wall_s", 0.0)), _out, "" if ok else " (NOT WRITTEN)"])
	quit(0 if ok else 3)


func _meta(ra: Node, reason: String) -> Dictionary:
	var header: Dictionary = ra.get("header") if ra else {}
	# --fixed-fps is the engine's own argument (not in get_cmdline_args): a fixed rate shows as every boot frame's delta
	# exactly the same; 0 = real time
	var fps := roundi(1.0 / _first_dt) if _fixed_dt and _first_dt > 0.0 else 0
	var dmg := 0.0
	for k in (_run.damage_by_weapon as Dictionary).keys():
		dmg += float(_run.damage_by_weapon[k])
	var build := ""
	if ra and ra.has_method("build_text") and ra.has_method("_build"):
		build = str(ra.build_text(ra._build()))
	return {"schema": SCHEMA, "hero": _hero, "hero_name": str(header.get("hero_name", "")), "start_weapon": _start_weapon,
		"seed": _seed, "board": _board, "talents": _talents.duplicate(), "talent_forms": _talent_forms.duplicate(),
		"fast": _fast, "death": _death, "limit": _limit, "map": _map,
		"unlocks": _unlocks, "map_rev": header.get("map_rev", ""), "version": str(ProjectSettings.get_setting("application/config/version", "")),
		"fps": fps, "res": [_res.x, _res.y], "view": [int(root.get_visible_rect().size.x), int(root.get_visible_rect().size.y)],
		"wall_s": snappedf(float(Time.get_ticks_msec()) / 1000.0, 0.1), "boot_s": snappedf(_boot_s, 0.1),
		"end_reason": reason, "end_t": snappedf(float(ra.get("play_t")) if ra else 0.0, 0.1), "end_clock": snappedf(float(_run.elapsed), 0.1),
		"end_stage": int(_run.stage) + 1, "end_level": int(_run.level), "endless_wave": int(_run.endless_wave()),
		"revives": _bot.revives.duplicate() if _bot else {"ad": 0, "phoenix": 0, "keep": 0}, "assists": int(_bot.assists) if _bot else 0,
		"picks": int(_bot.picks) if _bot else 0, "kills": int(_run.kills),
		"xp_total": snappedf(float(ra.get("xp_total")) if ra and ra.get("xp_total") != null else 0.0, 0.1),
		"dmg_total": snappedf(dmg, 0.1), "build_text": build, "started": str(header.get("started", "")),
		# pass 87 (lane STOOLS): the stage run: the stage played (1-based), how it ended, its boss, its Endless
		"stage": _stage, "outcome": _stage_outcome(reason),
		"boss_killed": bool(_run.get("stage_beaten")) if _run.get("stage_beaten") != null else false,
		"endless_s": snappedf(float(_run.get("endless_time")) if _run.get("endless_time") != null and bool(_run.get("endless")) else 0.0, 0.1),
		"stage_clock": snappedf(float(_run.call("stage_clock")) if _run.has_method("stage_clock") else float(_run.elapsed), 0.1)}


## The player's JSON from the recorder's rows and events (in memory) and the tool's own: meta, the series, the events.
func build_output(ra: Node, reason: String) -> Dictionary:
	var end_ev := {"t": snappedf(_play_t(), 0.1), "clock": snappedf(float(_run.elapsed), 0.1), "kind": "end", "reason": reason}
	# the evolutions among the weapon ids (held_by counts them apart)
	var evo_ids := {}
	for id in (_reg.get("weapons") as Dictionary).keys():
		if bool(_reg.weapons[id].is_evolution):
			evo_ids[str(id)] = true
	var out := series(ra.get("samples"), ra.get("events"), _bot.events if _bot else [], end_ev, evo_ids)
	var sums: Dictionary = out["sums"]
	out.erase("sums")
	var meta := _meta(ra, reason)
	meta["rows"] = int(sums["rows"])
	meta["deaths"] = int(sums["deaths"])
	meta["gold_total"] = int(sums["gold_total"])
	# pass 80 (lane BOT): the bot's options and tallies (meta.bot) and its decisions (bot_decisions)
	if _bot:
		var b: Dictionary = _bot.summary()
		b["tallies"] = bot_tallies(ra.get("events"), _game.get("barrels"))
		meta["bot"] = b
		out["bot_decisions"] = _bot.decisions
	# pass 84 (lane SIMVIEW): the overlay's series, life_by and the roster as played
	_sv_output(out, meta, (ra.get("samples") as Array).size())
	out["meta"] = meta
	return out


## What the hero did with the map (pass 80): structures used by id (the recorder's "structure" events; totem_pole the Totem
## Poles) with the play seconds of each Totem Pole's use, power-ups taken (its "pickup" events, the small ones underfoot
## not counted), barrels broken (BarrelField.broken).
static func bot_tallies(rec: Array, barrels) -> Dictionary:
	var used := {}
	var totem_t: Array = []
	var powerups := 0
	for e in rec:
		if not (e is Dictionary):
			continue
		var kind := str(e.get("kind", ""))
		if kind == "structure":
			var id := str(e.get("id", ""))
			used[id] = int(used.get(id, 0)) + 1
			if id == "totem_pole":
				totem_t.append(float(e.get("t", 0.0)))
		elif kind == "pickup" and not bool(e.get("small", false)):
			powerups += 1
	var totems := int(used.get("totem_pole", 0))
	var structures := 0
	for id in used:
		if str(id) != "totem_pole":
			structures += int(used[id])
	return {"structures_by": used, "structures": structures, "totems": totems, "totem_t": totem_t, "powerups": powerups,
		"barrels": int(barrels.broken) if barrels != null else 0}


## Pass 82 (lane STATS): chests, power-ups and totems picked up, the Sim's chart and the Watch's totals and marks. The
## same rule, line for line, as tools/level_editor/sim_model.js pickupKind() (the Sim tab, the dashboard) and
## tools/analytics_csv.py pickup_kind() (the rows CSV): "chests" for a `chest` event (one per chest opened, taken or
## skipped, a boss chest too), "powerups" for a `pickup` whose `small` is not set (the game's own count of power-ups:
## Game.apply_pickup), "totems" for a `totem` event (a Totem Pole's gift taken); "" for anything else.
const PICKUP_KEYS := ["chests", "powerups", "totems"]


static func pickup_kind(e) -> String:
	if not (e is Dictionary):
		return ""
	var kind := str(e.get("kind", ""))
	if kind == "chest":
		return "chests"
	if kind == "pickup":
		var s = e.get("small", false)
		var small: bool = (s is bool and s) or ((s is int or s is float) and float(s) != 0.0)
		return "" if small else "powerups"
	if kind == "totem":
		return "totems"
	return ""


## {chests, powerups, totems}: each kind's event times (play seconds), in order.
static func pickup_times(rec: Array) -> Dictionary:
	var out := {"chests": [], "powerups": [], "totems": []}
	for e in rec:
		var k := pickup_kind(e)
		if k != "":
			var tv = e.get("t", 0.0)
			(out[k] as Array).append(float(tv) if (tv is int or tv is float) else 0.0)
	for k in PICKUP_KEYS:
		(out[k] as Array).sort()
	return out


## {chests, powerups, totems}: the run's totals so far (every event given).
static func pickup_totals(rec: Array) -> Dictionary:
	var times := pickup_times(rec)
	return {"chests": (times["chests"] as Array).size(), "powerups": (times["powerups"] as Array).size(),
		"totems": (times["totems"] as Array).size()}


## The series of keys_SIMRUN.md from the recorder's `rows` (RunAnalytics samples) and events `rec`, with the tool's own
## events and the end's: every series one entry a row, aligned with `t`; the breakdowns one such array per id, zero
## before it first appears; "events" in time order; "sums" {rows, deaths, gold_total} for the meta.
static func series(rows: Array, rec: Array, tool_events: Array, end_ev: Dictionary, evo_ids: Dictionary = {}) -> Dictionary:
	var out := {}
	var t: Array = []
	var clock: Array = []
	var stage: Array = []
	var phase: Array = []
	var hp: Array = []
	var hp_max: Array = []
	var dps: Array = []
	var est: Array = []
	# pass 83 (lane SCALE): the hero's power level (the row's `power`, HeroPower; 0 in a record before pass 83)
	var power: Array = []
	var alive: Array = []
	var cap: Array = []
	var press_hp: Array = []
	var press_dmg: Array = []
	var boss_hp: Array = []
	var boss_hp_abs: Array = []
	var near3: Array = []
	var near6: Array = []
	var hits: Array = []
	var spawned: Array = []
	var mult_hp: Array = []
	var mult_dmg: Array = []
	var took_by := {}
	var healed_by := {}
	var took_acc := {}
	var healed_acc := {}
	var held_by := {"weapons": [], "evolutions": [], "lines": [], "passives": [], "perks": []}
	var held := {"weapons": 0, "evolutions": 0, "lines": 0, "passives": 0, "perks": 0}
	var m_hp := 1.0
	var m_dmg := 1.0
	var gold_total: Array = []
	var gold: Array = []
	var dmg_total: Array = []
	var kills: Array = []
	var level: Array = []
	var xp_total: Array = []
	var took: Array = []
	var healed: Array = []
	var deaths: Array = []
	var alive_by := {}
	var gold_by := {}
	var dmg_by := {}
	var kills_by := {}
	var gold_acc := {}
	var dmg_acc := {}
	var kills_acc := {}
	# the falls, in time order (the recorder's death events)
	var fall_t: Array = []
	for e in rec:
		if e is Dictionary and str(e.get("kind", "")) == "death":
			fall_t.append(float(e.get("t", 0.0)))
	var fi := 0
	# pass 82 (lane STATS): chests, power-ups and totems picked up so far (pickup_kind), counted like the falls
	var pk_times := pickup_times(rec)
	var pk_i := {"chests": 0, "powerups": 0, "totems": 0}
	var pk_out := {"chests": [], "powerups": [], "totems": []}
	var gsum := 0
	var dsum := 0.0
	var last_t := 0
	for i in range(rows.size()):
		var r: Dictionary = rows[i]
		var rt := float(r.get("t", 0.0))
		var ti := maxi(int(ceil(rt - 0.05)), last_t + 1)
		last_t = ti
		t.append(ti)
		clock.append(snappedf(float(r.get("clock", 0.0)), 0.1))
		stage.append(int(r.get("stage", 1)))
		phase.append(int(r.get("phase", 0)))
		hp.append(snappedf(float(r.get("hp", 0.0)), 0.1))
		hp_max.append(snappedf(float(r.get("hp_max", 0.0)), 0.1))
		var second := 0.0
		var dm = r.get("dmg", {})
		if dm is Dictionary:
			for k in dm:
				second += float(dm[k])
		dsum += second
		dps.append(snappedf(second, 0.1))
		dmg_total.append(snappedf(dsum, 0.1))
		_step(dmg_by, dmg_acc, dm if dm is Dictionary else {}, i, true, true)
		est.append(snappedf(float(r.get("est_total", 0.0)), 0.1))
		power.append(snappedf(float(r.get("power", 0.0)), 0.01))
		alive.append(int(r.get("alive", 0)))
		cap.append(int(r.get("cap", 0)))
		press_hp.append(snappedf(float(r.get("press_hp", 0.0)), 0.1))
		press_dmg.append(snappedf(float(r.get("press_dmg", 0.0)), 0.1))
		# the boss's share of its health (the row's boss_hp) and the health itself (boss_now); 0 with no boss up
		boss_hp.append(float(r.get("boss_hp", 0.0)))
		boss_hp_abs.append(float(r.get("boss_now", 0.0)))
		near3.append(int(r.get("near3", 0)))
		near6.append(int(r.get("near6", 0)))
		hits.append(int(r.get("hits", 0)))
		var sp = r.get("spawned", {})
		var sp_n := 0
		if sp is Dictionary:
			for k in sp:
				sp_n += int(sp[k])
		spawned.append(sp_n)
		# a creature spawned now: stage x the HP (damage) curve x the level's (the row's mults, carried until they change)
		var mu = r.get("mults")
		if mu is Dictionary:
			m_hp = float(mu.get("stage", 1.0)) * float(mu.get("hp_t", 1.0)) * float(mu.get("lvl_hp", 1.0))
			m_dmg = float(mu.get("stage", 1.0)) * float(mu.get("dmg_t", 1.0)) * float(mu.get("lvl_dmg", 1.0))
		mult_hp.append(snappedf(m_hp, 0.001))
		mult_dmg.append(snappedf(m_dmg, 0.001))
		var tk_map = r.get("took", {})
		_step(took_by, took_acc, tk_map if tk_map is Dictionary else {}, i, true, true)
		var hb: Dictionary = (r.get("healed_by", {}) as Dictionary).duplicate() if r.get("healed_by", {}) is Dictionary else {}
		if float(r.get("regen", 0.0)) != 0.0:
			hb["regen"] = float(hb.get("regen", 0.0)) + float(r.get("regen", 0.0))
		_step(healed_by, healed_acc, hb, i, true, true)
		# the build held (the row's snapshots, carried until the next one)
		if r.get("weapons") is Array:
			var nw := 0
			var ne := 0
			for w in r["weapons"]:
				if w is Dictionary and evo_ids.has(str(w.get("id", ""))):
					ne += 1
				else:
					nw += 1
			held["weapons"] = nw
			held["evolutions"] = ne
		if r.get("lines") is Dictionary:
			held["lines"] = (r["lines"] as Dictionary).size()
		if r.get("passives") is Dictionary:
			held["passives"] = (r["passives"] as Dictionary).size()
		if r.get("perks") is Array:
			held["perks"] = (r["perks"] as Array).size()
		for k in held:
			(held_by[k] as Array).append(int(held[k]))
		var ab = r.get("alive_by", {})
		_step(alive_by, {}, ab if ab is Dictionary else {}, i, false, false)
		var gi = r.get("gold_in", {})
		if gi is Dictionary:
			for k in gi:
				gsum += int(gi[k])
		gold_total.append(gsum)
		_step(gold_by, gold_acc, gi if gi is Dictionary else {}, i, true, false)
		gold.append(int(r.get("gold", 0)))
		kills.append(int(r.get("kills", 0)))
		var kd = r.get("killed", {})
		_step(kills_by, kills_acc, kd if kd is Dictionary else {}, i, true, false)
		level.append(int(r.get("level", 1)))
		xp_total.append(snappedf(float(r.get("xp_total", 0.0)), 0.1))
		var lost := 0.0
		var tk = r.get("took", {})
		if tk is Dictionary:
			for k in tk:
				lost += float(tk[k])
		took.append(snappedf(lost, 0.1))
		healed.append(snappedf(float(r.get("healed", 0.0)) + float(r.get("regen", 0.0)), 0.1))
		while fi < fall_t.size() and float(fall_t[fi]) <= rt + 0.001:
			fi += 1
		deaths.append(fi)
		for k in PICKUP_KEYS:
			var pk_tk: Array = pk_times[k]
			var j: int = pk_i[k]
			while j < pk_tk.size() and float(pk_tk[j]) <= rt + 0.001:
				j += 1
			pk_i[k] = j
			(pk_out[k] as Array).append(j)
	out["sums"] = {"rows": rows.size(), "deaths": fall_t.size(), "gold_total": gsum}
	out["t"] = t
	out["clock"] = clock
	out["stage"] = stage
	out["phase"] = phase
	out["hp"] = hp
	out["hp_max"] = hp_max
	out["dps"] = dps
	out["est"] = est
	out["power"] = power
	out["alive"] = alive
	out["cap"] = cap
	out["press_hp"] = press_hp
	out["press_dmg"] = press_dmg
	out["boss_hp"] = boss_hp
	out["boss_hp_abs"] = boss_hp_abs
	out["near3"] = near3
	out["near6"] = near6
	out["hits"] = hits
	out["spawned"] = spawned
	out["mult_hp"] = mult_hp
	out["mult_dmg"] = mult_dmg
	out["took_by"] = took_by
	out["healed_by"] = healed_by
	out["held_by"] = held_by
	out["alive_by"] = alive_by
	out["gold_total"] = gold_total
	out["gold"] = gold
	out["gold_by"] = gold_by
	out["dmg_total"] = dmg_total
	out["dmg_by"] = dmg_by
	out["kills"] = kills
	out["kills_by"] = kills_by
	out["level"] = level
	out["xp_total"] = xp_total
	out["took"] = took
	out["healed"] = healed
	out["deaths"] = deaths
	for k in PICKUP_KEYS:
		out[k] = pk_out[k]
	out["events"] = events_out(rec, tool_events, end_ev)
	return out


## One row of a breakdown: every id seen so far gets this row's value (`cum`: the running sum), a new id an array of
## zeros for the rows before it. `snap` keeps floats to 0.1.
static func _step(by_id: Dictionary, acc: Dictionary, vals: Dictionary, i: int, cum: bool, snap: bool) -> void:
	for k in vals:
		var id := str(k)
		if not by_id.has(id):
			var a: Array = []
			a.resize(i)
			a.fill(0)
			by_id[id] = a
	for id in by_id:
		var v = vals.get(id, 0)
		var a: Array = by_id[id]
		if not cum:
			a.append(int(v))
		elif snap:
			var f := float(acc.get(id, 0.0)) + float(v)
			acc[id] = f
			a.append(snappedf(f, 0.1))
		else:
			var n := int(acc.get(id, 0)) + int(v)
			acc[id] = n
			a.append(n)


## The events the charts mark (the recorder's, renamed to say what their number is, the tool's own and the end), in
## time order (at one moment the recorder's first).
static func events_out(rec: Array, tool_events: Array, end_ev: Dictionary) -> Array:
	var out: Array = []
	for e in rec:
		if not (e is Dictionary):
			continue
		var kind := str(e.get("kind", ""))
		var base := {"t": float(e.get("t", 0.0)), "clock": float(e.get("clock", 0.0)), "kind": kind}
		match kind:
			"level":
				base["level"] = int(e.get("level", 0))
			"death":
				base["killer"] = str(e.get("id", ""))
				base["hit"] = str(e.get("hit", ""))
			"revive":
				base["via"] = str(e.get("id", ""))
			"boss_start":
				base["id"] = str(e.get("id", ""))
				for k in ["hp", "mult", "dps", "ref"]:
					if e.has(k):
						base[k] = e[k]
			"boss_end":
				base["id"] = str(e.get("id", ""))
			"stage":
				base["stage"] = int(e.get("level", 0))
			"wave":
				base["wave"] = int(e.get("level", 0))
			_:
				continue
		out.append(base)
	for e in tool_events:
		out.append(e)
	if not end_ev.is_empty():
		out.append(end_ev)
	# stable by time: the recorder's first, then the tool's, at one moment
	var idx := range(out.size())
	idx.sort_custom(func(a: int, b: int) -> bool:
		var ta := float(out[a]["t"])
		var tb := float(out[b]["t"])
		return ta < tb if ta != tb else a < b)
	var sorted: Array = []
	for k in idx:
		sorted.append(out[k])
	return sorted


func _write_progress(state: String, reason: String) -> void:
	var p = _game.player if _game != null and is_instance_valid(_game) else null
	var d := {"t": snappedf(_play_t(), 0.1), "limit": _limit, "clock": snappedf(float(_run.elapsed), 0.1) if _run else 0.0,
		"stage": int(_run.stage) + 1 if _run else 1, "level": int(_run.level) if _run else 1, "deaths": _fall_count(),
		"hp": snappedf(float(p.hp), 0.1) if p else 0.0, "hp_max": snappedf(float(p.max_hp), 0.1) if p else 0.0,
		"kills": int(_run.kills) if _run else 0, "wall_s": snappedf(float(Time.get_ticks_msec()) / 1000.0, 0.1),
		"state": state, "end_reason": reason}
	var lying := _xp_lying()
	d["xp_lying"] = snappedf(lying.x, 0.1)
	d["xp_lying_near"] = snappedf(lying.y, 0.1)
	_store(_out + ".progress", JSON.stringify(d))
	if state == "running":
		var ra := _ra()
		var modes := ""
		var total := 0
		var mf: Dictionary = _bot.mode_frames if _bot else {}
		for k in mf:
			total += int(mf[k])
		for k in mf:
			modes += " %s %d%%" % [k, roundi(100.0 * float(mf[k]) / maxf(float(total), 1.0))]
		mf.clear()
		var bot_ms := float(_bot_us) / 1000.0 / maxf(float(_bot_frames), 1.0)
		_bot_us = 0
		_bot_frames = 0
		_say("t=%d clock=%.1f stage=%d level=%d hp=%d/%d deaths=%d kills=%d xp=%.0f lying=%.0f near=%.0f |%s | bot=%.2fms wall=%.1f" % [int(d["t"]),
			float(d["clock"]), int(d["stage"]), int(d["level"]), int(d["hp"]), int(d["hp_max"]), int(d["deaths"]), int(d["kills"]),
			float(ra.get("xp_total")) if ra else 0.0, lying.x, lying.y, modes, bot_ms, float(d["wall_s"])])
		if _profile:
			_say_profile()


## profile=1: the game's own buckets since the last line (Perf.report: ms a frame) beside the whole frame's wall ms.
func _say_profile() -> void:
	var rep: Dictionary = PERF.report()
	var now := Time.get_ticks_msec()
	var fr := Engine.get_process_frames()
	var frame_ms := float(now - _prof_wall_ms) / maxf(float(fr - _prof_frames), 1.0) if _prof_wall_ms > 0 else 0.0
	_prof_wall_ms = now
	_prof_frames = fr
	var parts: Array = []
	var sum := 0.0
	for k in rep.keys():
		if rep[k] is float and not str(k) in ["worst_ms"]:
			parts.append([str(k), float(rep[k])])
			sum += float(rep[k])
	parts.sort_custom(func(a, b) -> bool: return float(a[1]) > float(b[1]))
	var txt := ""
	for pp in parts:
		txt += " %s %.2f" % [pp[0], pp[1]]
	_say("profile: frame %.2f ms (buckets %.2f):%s" % [frame_ms, sum, txt])


## The XP lying on the sand (gems at rest or bobbing, not on their way): x the whole map, y within 10 m of the hero
## (the progress line's diagnostic: how much the sweep leaves behind).
func _xp_lying() -> Vector2:
	if _game == null or not is_instance_valid(_game) or _game.pickups == null or _game.player == null:
		return Vector2.ZERO
	var pk = _game.pickups
	var me: Vector3 = _game.player.global_position
	var alive: PackedByteArray = pk.alive
	var flying: PackedByteArray = pk.flying
	var kinds: PackedInt32Array = pk.kind
	var vals: PackedFloat32Array = pk.value
	var pos: PackedVector3Array = pk.pos
	var coin_kind: int = int(pk.KIND_COIN)
	var vac_kind: int = int(pk.KIND_VACUUM)
	var all := 0.0
	var near := 0.0
	for i in range(mini(alive.size(), mini(flying.size(), kinds.size()))):
		if alive[i] != 1 or flying[i] != 0 or kinds[i] == coin_kind or kinds[i] == vac_kind:
			continue
		all += vals[i]
		if Vector2(pos[i].x - me.x, pos[i].z - me.z).length() < 10.0:
			near += vals[i]
	return Vector2(all, near)


func _fall_count() -> int:
	var ra := _ra()
	if ra == null:
		return 0
	var n := 0
	for e in ra.get("events"):
		if e is Dictionary and str(e.get("kind", "")) == "death":
			n += 1
	return n


## Written whole: to `<path>.tmp`, then renamed over `path` (a file that exists is complete). False when it failed.
func _store(path: String, text: String) -> bool:
	if path == "":
		return false
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		printerr("sim: cannot write %s" % tmp)
		return false
	f.store_string(text)
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path) == OK


# ---------------------------------------------------------------- pass 84 (lane SIMVIEW): the Timeline overlay's data

## Garry's Timeline (pass 84) overlays the Sim on the map's clock: how many creatures were alive on each channel, how
## full the cap was, which roster rows wanted to spawn and could not, the crowd's threat against the hero's power, and
## how long each creature lives. This sampler reads the game (never changes it) and adds, one entry per recorder row
## (aligned with `t`): alive_hell, load, load_hell, cap_hell, hard_cap, cap_full, threat, hero_dps, hero_ehp, challenge;
## the breakdowns alive_hell_by and starving_by; the top-level life_by; meta.rows and meta.simview_ms. Definitions:
## tools/dl/p84/balancing_SIMVIEW.md (and status_SIMVIEW.md "OVERLAY READY").
## Seconds of play between two cap checks (cap_full and starving are shares of a second's checks).
const SV_CHECK_S := 0.2
## life_by's stage slots: stage 1, 2, 3 and everything after (endless)
const SV_STAGES := 4

var _sv_on := false
var _sv_rows := 0
var _sv: Dictionary = {}
var _sv_hell_by: Dictionary = {}
var _sv_starve_by: Dictionary = {}
var _sv_checks := 0
var _sv_full := 0
var _sv_starve_n: Dictionary = {}
var _sv_check_t := 0.0
var _sv_serial := -1
var _sv_born_serial := PackedInt32Array()
var _sv_born_t := PackedFloat32Array()
var _sv_open := PackedByteArray()
var _sv_born_id: Array = []
var _sv_life: Dictionary = {}
var _sv_us := 0
var _sv_rows_meta: Array = []
const SV_KEYS := ["alive_hell", "load", "load_hell", "cap_hell", "hard_cap", "cap_full", "threat", "hero_dps", "hero_ehp", "challenge"]


## The sampler's start, when the game is up: the deaths heard, the slots' births tracked, the roster as played noted.
func _sv_start() -> void:
	var em = _game.get("enemies")
	var dir = _game.get("director")
	if em == null or dir == null or dir.get("timeline") == null:
		_say("simview: no enemies or director: the overlay's series are left out")
		return
	_sv_on = true
	for k in SV_KEYS:
		_sv[k] = []
	var n: int = int(em.MAX)
	_sv_born_serial.resize(n)
	_sv_born_serial.fill(0)
	_sv_born_t.resize(n)
	_sv_open.resize(n)
	_sv_open.fill(0)
	_sv_born_id.resize(n)
	_sv_born_id.fill("")
	if em.has_signal("creature_dying"):
		em.creature_dying.connect(_sv_on_dying)
	_sv_rows_meta = roster_rows(dir.timeline.roster, dir)
	_sv_check_t = _play_t()


## The roster as the run plays it: [{key, k, id, enemy, t, until, channel, pace}] (key: the director's row key).
static func roster_rows(roster: Array, dir = null) -> Array:
	var out: Array = []
	for k in range(roster.size()):
		var r = roster[k]
		if not (r is Dictionary):
			continue
		var en = r.get("enemy", "")
		out.append({"key": row_key(r, k, dir), "k": k, "id": str(r.get("id", "")), "enemy": en if (en is String or en is Array) else str(en),
			"t": float(r.get("t", 0.0)), "until": float(r["until"]) if r.get("until") != null else null,
			"channel": str(r.get("channel", "")), "pace": str(r.get("pace", "continuous"))})
	return out


## A roster row's key as the director keys its state (WaveDirector._row_key_at: "row:<id>#<index>", else "row#<index>").
static func row_key(r: Dictionary, k: int, dir = null) -> String:
	if dir != null and dir.has_method("_row_key_at"):
		return str(dir._row_key_at(r, k))
	var id := str(r.get("id", ""))
	return ("row:%s#%d" % [id, k]) if id != "" else "row#%d" % k


## Every frame: births (a slot's spawn number moved), the cap checks every SV_CHECK_S of play, and one sample a recorder
## row.
func _sv_frame() -> void:
	if not _sv_on:
		return
	var us := Time.get_ticks_usec()
	var em = _game.enemies
	var ser := int(em.get("_serial"))
	if ser != _sv_serial:
		_sv_serial = ser
		_sv_births(em)
	var pt := _play_t()
	if pt >= _sv_check_t:
		_sv_check(em, _game.director)
		_sv_check_t = maxf(_sv_check_t + SV_CHECK_S, pt)
	var ra := _ra()
	if ra != null:
		var rows: Array = ra.get("samples")
		while _sv_rows < rows.size():
			_sv_sample(em, _game.director, rows[_sv_rows] if rows[_sv_rows] is Dictionary else {})
			_sv_rows += 1
	_sv_us += Time.get_ticks_usec() - us


## The slots whose creature is new since the last look: its spawn noted (a creature still open there left without dying:
## `gone`).
func _sv_births(em) -> void:
	var alive: PackedByteArray = em.alive
	var serial: PackedInt32Array = em.serial
	var tidx: PackedInt32Array = em.type_idx
	var types: Array = em.types
	var now := _play_t()
	for i in range(mini(alive.size(), _sv_born_serial.size())):
		if alive[i] == 0 or serial[i] == _sv_born_serial[i]:
			continue
		if _sv_open[i] == 1:
			life_gone(_sv_life, str(_sv_born_id[i]))
		_sv_born_serial[i] = serial[i]
		_sv_born_t[i] = now
		_sv_open[i] = 1
		var ti := tidx[i]
		_sv_born_id[i] = str((types[ti]["def"] as Resource).get("id")) if ti >= 0 and ti < types.size() else ""


## A creature falls (EnemyManager.creature_dying): its life from its spawn to now, counted in its stage's slot.
func _sv_on_dying(i: int, _weapon_id: String) -> void:
	var em = _game.enemies if _game != null and is_instance_valid(_game) else null
	if em == null or i < 0 or i >= _sv_born_serial.size():
		return
	var now := _play_t()
	var s: int = int(em.serial[i])
	if _sv_born_serial[i] != s:
		# born and fallen between two looks (one frame): a life of 0
		if _sv_open[i] == 1:
			life_gone(_sv_life, str(_sv_born_id[i]))
		_sv_born_serial[i] = s
		_sv_born_t[i] = now
		var ti: int = int(em.type_idx[i])
		_sv_born_id[i] = str((em.types[ti]["def"] as Resource).get("id")) if ti >= 0 and ti < em.types.size() else ""
		_sv_open[i] = 1
	if _sv_open[i] == 0:
		return
	_sv_open[i] = 0
	life_add(_sv_life, str(_sv_born_id[i]), int(_run.stage), now - _sv_born_t[i])


## life_by's bookkeeping: {id: {n: [a stage], s: [seconds a stage], gone, open}}.
static func life_entry(life: Dictionary, id: String) -> Dictionary:
	if not life.has(id):
		var n: Array = []
		var s: Array = []
		for _k in range(SV_STAGES):
			n.append(0)
			s.append(0.0)
		life[id] = {"n": n, "s": s, "gone": 0, "open": 0}
	return life[id]


static func life_add(life: Dictionary, id: String, stage: int, secs: float) -> void:
	if id == "":
		return
	var e := life_entry(life, id)
	var k := clampi(stage, 0, SV_STAGES - 1)
	(e["n"] as Array)[k] = int(e["n"][k]) + 1
	(e["s"] as Array)[k] = float(e["s"][k]) + maxf(secs, 0.0)


static func life_gone(life: Dictionary, id: String) -> void:
	if id == "":
		return
	var e := life_entry(life, id)
	e["gone"] = int(e["gone"]) + 1


## The creature ids the hell channel brings now, as the director reckons its hell load (its hell rows and hell waves).
static func hell_ids(dir) -> Dictionary:
	var out := {}
	if dir == null:
		return out
	var rows: Array = dir.hell_rows() if dir.has_method("hell_rows") else []
	for r in rows:
		if r is Dictionary:
			out[str(r.get("enemy", ""))] = true
	if dir.has_method("_hell_wave_ids"):
		for id in dir._hell_wave_ids():
			out[str(id)] = true
	return out


## The crowd now, in one pass over the slots: {alive, alive_hell, load, load_hell, threat, hell_by}. Dying creatures are
## not counted; the boss is counted in alive but left out of threat.
static func crowd_now(em, hell: Dictionary) -> Dictionary:
	var alive: PackedByteArray = em.alive
	var state: PackedInt32Array = em.state
	var tidx: PackedInt32Array = em.type_idx
	var mx: PackedFloat32Array = em.max_hp
	var dmg: PackedFloat32Array = em.dmg
	var ccd: PackedFloat32Array = em.get("_t_ccd") if em.get("_t_ccd") is PackedFloat32Array else PackedFloat32Array()
	var types: Array = em.types
	var dying: int = int(em.STATE_DYING)
	var boss: int = int(em.boss_index)
	var n := 0
	var nh := 0
	var load := 0.0
	var load_h := 0.0
	var threat := 0.0
	var by := {}
	for i in range(alive.size()):
		if alive[i] == 0 or state[i] == dying:
			continue
		var ti := tidx[i]
		if ti < 0 or ti >= types.size():
			continue
		var t: Dictionary = types[ti]
		var id := str((t["def"] as Resource).get("id"))
		var share := float(t.get("share", 1.0))
		n += 1
		if hell.has(id):
			nh += 1
			load_h += share
			by[id] = int(by.get(id, 0)) + 1
		else:
			load += share
		if i != boss:
			var cd: float = ccd[ti] if ti < ccd.size() else 0.6
			threat += threat_of(mx[i], dmg[i], cd)
	return {"alive": n, "alive_hell": nh, "load": load, "load_hell": load_h, "threat": threat, "hell_by": by}


## One creature's threat: its max HP x its bite's damage a second (the bite / its cadence, at least 0.05 s).
static func threat_of(max_hp: float, bite: float, cadence: float) -> float:
	return maxf(max_hp, 0.0) * maxf(bite, 0.0) / maxf(cadence, 0.05)


## The crowd's threat against the hero's full DPS x effective HP (0 when he has none).
static func challenge_of(threat: float, hero_dps: float, hero_ehp: float) -> float:
	var p := hero_dps * hero_ehp
	return threat / p if p > 0.0 else 0.0


## One cap check: whether the regular channel had room, and which rows wanted to spawn and could not (`starving`, the
## rule in balancing_SIMVIEW.md).
func _sv_check(em, dir) -> void:
	var tl = dir.timeline
	if tl == null:
		return
	_sv_checks += 1
	var cap: int = int(dir.current_cap())
	var hell := hell_ids(dir)
	var c := crowd_now(em, hell)
	var bodies_full: bool = int(em.alive_count()) >= int(tl.hard_cap)
	var reg_full: bool = cap > 0 and (float(c["load"]) >= float(cap) or bodies_full)
	var hell_full: bool = cap > 0 and (float(c["load_hell"]) >= float(tl.hell_cap_at(int(_run.stage))) * float(cap) or bodies_full)
	if reg_full:
		_sv_full += 1
	var normal: bool = int(dir.phase) == 0
	var t: float = float(_run.elapsed) if normal else float(_run.elapsed) - 1.0
	var row_waves = dir.get("_row_waves")
	for k in range(tl.roster.size()):
		var r = tl.roster[k]
		if not (r is Dictionary):
			continue
		if starving(r, k, t, reg_full, hell_full, dir, em, row_waves):
			var key := row_key(r, k, dir)
			_sv_starve_n[key] = int(_sv_starve_n.get(key, 0)) + 1


## Whether roster row `r` (index k) starves now: (a) in the continuous draw, open at `t`, weighing above 0, its creature
## under its max_alive, and its channel full; or (b) paced (waves / once) with its last wave still owing creatures.
static func starving(r: Dictionary, k: int, t: float, reg_full: bool, hell_full: bool, dir, em, row_waves) -> bool:
	var paced: bool = str(r.get("pace", "continuous")) != "continuous"
	var drawn: bool = not paced or bool(r.get("trickle", false))
	if dir != null and dir.get("timeline") != null and dir.timeline.has_method("row_drawn"):
		drawn = bool(dir.timeline.row_drawn(r))
	if paced and row_waves is Dictionary:
		var st = (row_waves as Dictionary).get(row_key(r, k, dir))
		if st is Dictionary and int((st as Dictionary).get("owed", 0)) > 0:
			return true
	if not drawn:
		return false
	var full: bool = hell_full if str(r.get("channel", "")) == "hell" else reg_full
	if not full:
		return false
	if t < float(r.get("t", 0.0)) or (r.get("until") != null and t >= float(r["until"])):
		return false
	var w := float(r.get("weight", 1.0))
	if dir != null and dir.has_method("_roster_weight"):
		w = float(dir._roster_weight(r, t))
	if w <= 0.0:
		return false
	if dir != null and em != null and dir.has_method("_row_def") and r.get("enemy") is String:
		var def = dir._row_def(r)
		if def != null and int(def.max_alive) > 0 and int(em.alive_of(str(def.id))) >= int(def.max_alive):
			return false
	return true


## One recorder row's entry of every overlay series (the shares over the checks since the last row).
func _sv_sample(em, dir, row: Dictionary) -> void:
	var i: int = (_sv["load"] as Array).size()
	var tl = dir.timeline
	var c := crowd_now(em, hell_ids(dir))
	var cap: int = int(dir.current_cap())
	var dps := float(row.get("full_dps", 0.0))
	var ehp := float(row.get("ehp", 0.0))
	_sv["alive_hell"].append(int(c["alive_hell"]))
	_sv["load"].append(snappedf(float(c["load"]), 0.1))
	_sv["load_hell"].append(snappedf(float(c["load_hell"]), 0.1))
	_sv["cap_hell"].append(snappedf(float(tl.hell_cap_at(int(_run.stage))) * float(cap), 0.1))
	_sv["hard_cap"].append(int(tl.hard_cap))
	_sv["cap_full"].append(snappedf(float(_sv_full) / float(_sv_checks), 0.01) if _sv_checks > 0 else 0.0)
	_sv["threat"].append(snappedf(float(c["threat"]), 1.0))
	_sv["hero_dps"].append(snappedf(dps, 0.1))
	_sv["hero_ehp"].append(snappedf(ehp, 0.1))
	_sv["challenge"].append(snappedf(challenge_of(float(c["threat"]), dps, ehp), 0.001))
	put_by(_sv_hell_by, c["hell_by"], i, 1.0)
	var shares := {}
	for key in _sv_starve_n:
		shares[key] = float(_sv_starve_n[key]) / float(maxi(_sv_checks, 1))
	put_by(_sv_starve_by, shares, i, 0.01)
	_sv_checks = 0
	_sv_full = 0
	_sv_starve_n.clear()


## One row of a level breakdown: every id seen so far gets this row's value (0 when absent now), a new id zeros for the
## rows before it; values snapped to `step` (1.0: whole numbers).
static func put_by(by_id: Dictionary, vals: Dictionary, i: int, step: float) -> void:
	for k in vals:
		var id := str(k)
		if not by_id.has(id):
			var a: Array = []
			a.resize(i)
			a.fill(0)
			by_id[id] = a
	for id in by_id:
		var v := float(vals.get(id, 0))
		(by_id[id] as Array).append(int(v) if step >= 1.0 else snappedf(v, step))


## The overlay's output: every series cut or padded to the recorder's `n` rows (a row the sampler never saw repeats the
## last), the breakdowns, life_by (the creatures still up at the end counted as open), meta.rows, meta.simview_ms.
func _sv_output(out: Dictionary, meta: Dictionary, n: int) -> void:
	if not _sv_on:
		return
	# the rows the recorder wrote since the last frame
	if _game != null and is_instance_valid(_game):
		var ra := _ra()
		var rows: Array = ra.get("samples") if ra else []
		while _sv_rows < rows.size():
			_sv_sample(_game.enemies, _game.director, rows[_sv_rows] if rows[_sv_rows] is Dictionary else {})
			_sv_rows += 1
	for k in SV_KEYS:
		out[k] = fit_len(_sv[k], n)
	var hb := {}
	for id in _sv_hell_by:
		hb[id] = fit_len(_sv_hell_by[id], n)
	out["alive_hell_by"] = hb
	var sb := {}
	for id in _sv_starve_by:
		sb[id] = fit_len(_sv_starve_by[id], n)
	out["starving_by"] = sb
	for i in range(_sv_open.size()):
		if _sv_open[i] == 1:
			var e := life_entry(_sv_life, str(_sv_born_id[i]))
			e["open"] = int(e["open"]) + 1
	_sv_life.erase("")
	for id in _sv_life:
		var e: Dictionary = _sv_life[id]
		var s: Array = e["s"]
		for k in range(s.size()):
			s[k] = snappedf(float(s[k]), 0.1)
	out["life_by"] = _sv_life
	meta["rows_played"] = _sv_rows_meta
	var pt := maxf(_play_t(), 1.0)
	meta["simview_ms"] = snappedf(float(_sv_us) / 1000.0 / pt, 0.01)


## `a` cut to `n` entries, or padded with its last entry (0 when empty).
static func fit_len(a: Array, n: int) -> Array:
	var out: Array = a.slice(0, n)
	var last = out[out.size() - 1] if not out.is_empty() else 0
	while out.size() < n:
		out.append(last)
	return out
