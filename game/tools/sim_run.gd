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
## The bot (the rules: tools/dl/p77/balancing_SIMRUN.md): the difficulty probe's kiting autopilot (tools/sim_pilot.gd)
## leaning towards the richest gems on the field while the way is clear and he is well (the sweep, _lure), stepping out of
## the creatures' red warning rings, keeping near a living boss (BOSS_LEASH), walking to a chest that lies within
## CHEST_RANGE, to the boss's chest and then to the portal; the level-up cards by a sensible player's priorities (card_tier), a mutation offer at random, chests taken,
## the Stranger and the shop left, a Totem Pole's gift with the most feathers, the portal always continued, Down! by
## `death`. A watchdog writes what it has with end_reason "stuck:<what>" when a screen stays up more than STUCK_S seconds
## or the wall clock passes `wall`.
## Autoloads are reached through the tree (SceneTree scripts compile before they exist); no game class is named here.
extends SceneTree

const PILOT := preload("res://tools/sim_pilot.gd")
const PROBE := preload("res://tools/difficulty_probe.gd")
const PERF := preload("res://core/systems/Perf.gd")
const SCHEMA := 1
## a screen (or a pause with none) up longer than this many seconds of the frame clock is stuck
const STUCK_S := 10.0
## the hero down this long with nothing asking (no Down!, no Phoenix) is stuck too
const DOWN_STUCK_S := 12.0
## a chest within this many metres is walked to; one not reached in CHEST_PATIENCE play seconds is left for CHEST_REST
const CHEST_RANGE := 30.0
const CHEST_PATIENCE := 20.0
const CHEST_REST := 30.0
## the boss's chest and the portal must be reached: past MUST_PATIENCE play seconds the hero is put there (an "assist")
const MUST_PATIENCE := 45.0
## after a "Not yet" he steps this far out from the portal (past its re-arm distance, Portal.REARM 2.5 m) and back in
const PORTAL_OUT := 3.2
## While a boss lives he fights it (the boss log: the sweep had led him 40 to 60 m off while the King followed at 1.3
## m/s, so a first boss fight lasted 3 s or 6 minutes by where the gems lay): he keeps within BOSS_LEASH m of it (the
## guns' reach, 9 to 10 m, and about the screen's half height), walking back to BOSS_BACK m when he is further, and the
## sweep's gems and the chests he walks to count only within BOSS_LEASH of it then.
const BOSS_LEASH := 10.0
const BOSS_BACK := 7.0
## The sweep (_lure, sim_pilot.steer_sweep): the pickups lying within LURE_R m (the whole field: what a crowd pushed him
## away from waits for him), summed by grid cell, the cell with the most worth / (distance + LURE_NEAR)^LURE_POW the
## spot; a coin COIN_WORTH a gold, a vacuum gem VACUUM_WORTH, a power-up POWERUP_WORTH (a heart only under HEART_BELOW of
## his health); the pick is made again every LURE_EVERY frames.
const LURE_R := 60.0
const LURE_NEAR := 2.0
const LURE_POW := 1.5
const COIN_WORTH := 2.0
const VACUUM_WORTH := 400.0
const POWERUP_WORTH := 40.0
const HEART_BELOW := 0.7
const LURE_EVERY := 6

var _out := ""
var _hero := "drifter"
var _seed := 1
var _limit := 1500.0
var _board := 0.0
var _death := "end"
var _map := "red_canyon"
var _progress := 10.0
var _wall := 2700.0
var _res := Vector2i(504, 1122)
var _grit := 0
var _spite := 1
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
## death=ad: the one ad revive is spent
var _ad_used := false
## trace=<frames> (a tool for finding what makes a seed unrepeatable): a state line every frame for that many frames
var _trace := 0
var _trace_n := 0
## the sweep's knobs (args lure_r, lure_w, lure_close; their defaults are the measured ones)
var _lure_r := LURE_R
var _lure_w := -1.0
var _lure_close := -1.0

var _game: Node
var _run: Node
var _reg: Node
var _pilot: PILOT
var _bot := RandomNumberGenerator.new()
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
var _chest_tapped := false
var _revives := {"ad": 0, "phoenix": 0, "keep": 0}
var _assists := 0
var _picks := 0
var _events: Array = []
var _phoenix_was := false
var _phoenix_pending := false
var _goal_key := ""
var _goal_t := 0.0
var _chest_rest: Dictionary = {}
var _seeded: Dictionary = {}
var _lure_at := Vector3.INF
var _lure_wait := 0
## walking back to a living boss (BOSS_LEASH, BOSS_BACK)
var _boss_back := false
var _first_dt := 0.0
var _fixed_dt := true
## frames the legs spent in each mode since the last progress line (kite, sweep, chest, boss, boss_chest, portal)
var _mode_frames: Dictionary = {}
## the legs' own cost since the last progress line (microseconds, frames): the progress line's bot= ms a frame
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
			"lure_r": _lure_r = maxf(float(v), 0.0)
			"lure_w": _lure_w = maxf(float(v), 0.0)
			"lure_close": _lure_close = clampf(float(v), 0.0, 1.0)
			"profile": _profile = v == "1"
			"talents": _talent_arg = v
			"fast": _fast = v != "0"
			"trace": _trace = int(v)
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
		settings.show_hints = false
		settings.damage_numbers = false
		settings.debug_mode = false
	# a phone's screen (the ranged weapons pick only what is on it): 9:20 with the canvas expanding as on Android
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.size = _res
	# the dice
	_run.seed_dice(_seed)
	_bot.seed = hash([_seed, "bot"])
	_pilot = PILOT.new(hash([_seed, "pilot"]))
	if _lure_w >= 0.0:
		_pilot.lure_w = _lure_w
	if _lure_close >= 0.0:
		_pilot.lure_close = _lure_close
	# the creatures' and the pickups' own dice, seeded right after their _ready randomizes them
	node_added.connect(_on_node_added)
	# sim_clock: the rules that count real time count the run's clock (Run.rule_seconds), as on a phone, in both modes
	_run.launch_override = {"character": _hero, "map": _map, "map_seed": _seed, "analytics_memory": true, "sim_fast": _fast,
			"sim_clock": true}
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
		_phoenix_was = bool(_run.phoenix_used)
		_say("game up: hero %s seed %d board %.1f death %s limit %.0f map %s view %s (boot %.1f s)" % [_hero, _seed, _board, _death,
			_limit, _map, str(root.get_visible_rect().size), _boot_s])
		return
	if not is_instance_valid(_game) or current_scene != _game or bool(_game.get("_ended")):
		_finish(_end_reason())
		return
	_watch(dt)
	if _done:
		return
	_screens()
	if bool(_game.get("_ended")):
		_finish(_end_reason())
		return
	_keep_up()
	if _trace > 0 and _trace_n < _trace:
		_trace_line()
	var us := Time.get_ticks_usec()
	_drive(dt)
	_bot_us += Time.get_ticks_usec() - us
	_bot_frames += 1
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


## Every screen a run raises, answered as the bot's rules say (one a frame; the game opens the next in its turn).
func _screens() -> void:
	var g := _game
	if g.revive_screen and g.revive_screen.visible:
		_down()
		return
	if g.portal_dialog and g.portal_dialog.visible:
		# walked in on the way to the boss's chest: "Not yet" (the chest first; the portal asks again once he has stepped
		# out and back in)
		if _boss_chest_lying():
			g.portal_dialog.decline()
			return
		_events.append({"t": snappedf(_play_t(), 0.1), "clock": snappedf(float(_run.elapsed), 0.1), "kind": "portal", "stage": int(_run.stage) + 1})
		g.portal_dialog.visible = false
		g.portal_dialog.decided.emit(false)
		return
	var cs = g.cards
	if cs and cs.visible and not (cs._offer as Array).is_empty() and not cs._picking:
		if cs.banish_mode():
			cs._toggle_banish()
		if cs.path_mode:
			if cs.reel_running():
				cs.skip_reel()
			var offer: Array = cs._offer
			var mut: Dictionary = offer[_bot.randi() % offer.size()]
			_note_pick(mut, cs._offer, -1)
			cs._pick(mut)
		else:
			var pick := choose_card(cs._offer, _bot)
			if not pick.is_empty():
				_picks += 1
				_note_pick(pick, cs._offer, card_tier(pick))
				cs._pick(pick)
		return
	var ch = g.chest_screen
	if ch and ch.visible:
		if ch._spinning:
			# a tap: the chest's beats skip to the reel, a second one hurries the reel (ChestScreen._input)
			if not _chest_tapped:
				if ch.intro_playing():
					ch.skip_intro()
				else:
					_chest_tapped = true
					var tw = ch.get("_tw")
					if tw is Tween and (tw as Tween).is_valid():
						var left := maxf(float(ch.get("_spin_total")) - (tw as Tween).get_total_elapsed_time(), 0.1)
						(tw as Tween).set_speed_scale(maxf(left / 0.6, 1.0))
			return
		_chest_tapped = false
		ch._finish(true)
		return
	_chest_tapped = false
	if g.resume_gate and g.resume_gate.visible:
		g.resume_gate.tap()
	if g.stranger_screen and g.stranger_screen.visible:
		g.stranger_screen._finish(false)
		return
	if g.structure_shop and g.structure_shop.visible:
		g.structure_shop._finish(false)
		return
	var ts = g.totem_screen
	if ts and ts.visible and not ts._done:
		var best: Array = []
		var most := -1
		for p in ts.planks():
			var f := int(p.feathers)
			if f > most:
				most = f
				best = [p]
			elif f == most:
				best.append(p)
		if not best.is_empty():
			ts._pick(best[_bot.randi() % best.size()])
		return


## The bot's pick as an event (the Sim tab can say what he took): its id, kind, the level it brings, its tier (-1 a
## mutation offer's random pick) and what else was on the table.
func _note_pick(card: Dictionary, offer: Array, tier: int) -> void:
	var others: Array = []
	for c in offer:
		if c is Dictionary and not is_same(c, card):
			others.append(str(c.get("id", "")))
	_events.append({"t": snappedf(_play_t(), 0.1), "clock": snappedf(float(_run.elapsed), 0.1), "kind": "pick", "id": str(card.get("id", "")),
		"type": str(card.get("type", "")), "item_kind": item_kind(card), "new": bool(card.get("is_new", false)),
		"level": int(card.get("level_to", 0)), "tier": tier, "others": others})


## What a card hands over, as lane SIMUI charts it: weapon, evolution (a maxed line's evolution card, or a weapon
## evolution), line, passive (a passive item), perk or mutation.
static func item_kind(card: Dictionary) -> String:
	var type := str(card.get("type", ""))
	var d = card.get("def")
	if bool(card.get("evolve", false)) or (type == "weapon" and d != null and bool(d.get("is_evolution"))):
		return "evolution"
	if type == "passive":
		return "line" if d != null and d.has_method("is_line") and bool(d.is_line()) else "passive"
	return type


## Down!, by `death`: ad gets up once on the ad revive while Down! offers it (its button there and not locked: a chance
## left), then gives up; end gives up at once (the run ends); keep never sees it (the hero is stood up as he falls), but
## answers "debug" if it comes.
func _down() -> void:
	var rs = _game.revive_screen
	if _death == "keep":
		_revives["keep"] = int(_revives["keep"]) + 1
		rs._decide("debug")
		return
	if _death == "ad" and not _ad_used and ad_offered(rs):
		_ad_used = true
		_revives["ad"] = int(_revives["ad"]) + 1
		rs._decide("ad")
		return
	rs._decide("give_up")


## Whether Down! offers the ad revive now: its button exists, shows and is not locked (a chance is left).
static func ad_offered(rs) -> bool:
	if rs == null:
		return false
	var b = rs.get("_ad_btn")
	if b == null or not is_instance_valid(b) or not (b is CanvasItem):
		return false
	return (b as CanvasItem).is_visible_in_tree() and not bool(b.get("locked"))


## death=keep (the probe's way): the moment he falls he is stood up at full health, the fall counted (the recorder's
## death event) and a "revive" (via keep) noted; a fall Phoenix Feather took is left to it (it stands him up itself).
func _keep_up() -> void:
	var p = _game.player
	var ph := bool(_run.phoenix_used)
	if p.dead:
		if ph and not _phoenix_was:
			_phoenix_pending = true
			_revives["phoenix"] = int(_revives["phoenix"]) + 1
		if _death == "keep" and not _phoenix_pending:
			p.revive()
			p.hp = p.max_hp
			p.invuln = 0.0
			_revives["keep"] = int(_revives["keep"]) + 1
			_events.append({"t": snappedf(_play_t(), 0.1), "clock": snappedf(float(_run.elapsed), 0.1), "kind": "revive", "via": "keep"})
			if _game.hud and _game.hud.has_method("show_player_bar"):
				_game.hud.show_player_bar()
	else:
		_phoenix_pending = false
	_phoenix_was = ph


# ---------------------------------------------------------------- the walk

## One frame of the bot's legs: a goal (the boss's chest, the portal, a chest near) walked to, else the kite.
func _drive(dt: float) -> void:
	if bool(_game.paused) or _game.player == null or _game.player.dead:
		return
	var goal := _goal()
	if goal.is_empty():
		_goal_key = ""
		_goal_t = 0.0
		_lure_wait -= 1
		if _lure_wait <= 0:
			_lure_wait = LURE_EVERY
			_lure_at = _lure()
		_pilot.steer_sweep(_game, dt, _t, _lure_at)
		_mode_frames["sweep" if _lure_at != Vector3.INF else "kite"] = int(_mode_frames.get("sweep" if _lure_at != Vector3.INF else "kite", 0)) + 1
		return
	_mode_frames[str(goal["what"])] = int(_mode_frames.get(str(goal["what"]), 0)) + 1
	var key := str(goal["key"])
	if key != _goal_key:
		_goal_key = key
		_goal_t = 0.0
	_goal_t += dt
	var at: Vector3 = goal["at"]
	_pilot.steer_to(_game, dt, at)
	if bool(goal["must"]) and _goal_t > MUST_PATIENCE:
		# he could not get there: put him on it (the run would sit in the portal wait otherwise); the portal asks at once
		_assists += 1
		_events.append({"t": snappedf(_play_t(), 0.1), "clock": snappedf(float(_run.elapsed), 0.1), "kind": "assist", "what": str(goal["what"])})
		var p: Node3D = _game.player
		if str(goal["what"]) == "portal" and _game.portal != null and is_instance_valid(_game.portal):
			at = (_game.portal as Node3D).global_position
			_game.portal.set("armed", true)
		p.global_position = Vector3(at.x, p.global_position.y, at.z)
		p.set("velocity", Vector3.ZERO)
		_goal_t = 0.0
	elif str(goal["what"]) == "chest" and _goal_t > CHEST_PATIENCE:
		_chest_rest[key] = _play_t() + CHEST_REST
		_goal_key = ""
		_goal_t = 0.0


## The goal now ({} = none): the boss's chest first, then the portal once no boss chest lies there, else the nearest
## chest within CHEST_RANGE not resting. {key, at, must, what}.
func _goal() -> Dictionary:
	var me: Vector3 = _game.player.global_position
	var pk = _game.pickups
	var near := {}
	var near_d := CHEST_RANGE
	var now := _play_t()
	var boss := _boss_at()
	if pk:
		for c in pk.chests:
			if not is_instance_valid(c) or bool(c.opened):
				continue
			var at: Vector3 = c.global_position
			var key := "chest:%d" % c.get_instance_id()
			if bool(c.boss):
				return {"key": key, "at": at, "must": true, "what": "boss_chest"}
			if float(_chest_rest.get(key, -1.0)) > now:
				continue
			if not within_leash(at, boss):
				continue
			var d := Vector2(at.x - me.x, at.z - me.z).length()
			if d < near_d:
				near_d = d
				near = {"key": key, "at": at, "must": false, "what": "chest"}
	var portal = _game.portal
	if portal != null and is_instance_valid(portal):
		var pp: Vector3 = (portal as Node3D).global_position
		if not bool(portal.get("armed")):
			# after a "Not yet" the portal asks again only once he has been out past its re-arm distance: out first
			var out := Vector3(me.x - pp.x, 0.0, me.z - pp.z)
			if out.length() < 0.1:
				out = Vector3(1.0, 0.0, 0.0)
			return {"key": "portal:%d" % portal.get_instance_id(), "at": pp + out.normalized() * PORTAL_OUT, "must": true, "what": "portal"}
		return {"key": "portal:%d" % portal.get_instance_id(), "at": pp, "must": true, "what": "portal"}
	# while a boss lives: back to it when he is too far off (BOSS_LEASH, BOSS_BACK)
	var bg := boss_goal(me, boss, _boss_back)
	_boss_back = not bg.is_empty()
	if not bg.is_empty():
		return bg
	return near


## The spot most worth walking to now (Vector3.INF for none). The gems, coins and vacuum gems lying past his magnet's
## reach within lure_r (read off PickupManager's grid of resting pickups, GRID_CELL m cells) are summed cell by cell,
## and the cell with the most worth over (distance + LURE_NEAR)^LURE_POW wins, its worth-weighted middle the spot; a
## power-up on the ground within lure_r counts as a cell of POWERUP_WORTH (a heart only while he is under HEART_BELOW of
## his health). Worth: a gem its XP, a coin COIN_WORTH a gold, a vacuum gem VACUUM_WORTH.
func _lure() -> Vector3:
	var pk = _game.pickups
	if pk == null:
		return Vector3.INF
	var me: Vector3 = _game.player.global_position
	var best := Vector3.INF
	var best_s := 0.0
	var mag: float = float(pk._magnet()) * 0.9 if pk.has_method("_magnet") else 1.35
	var head: PackedInt32Array = pk.get("_g_head")
	var nxt: PackedInt32Array = pk.get("_g_next")
	var pos: PackedVector3Array = pk.pos
	var kinds: PackedInt32Array = pk.kind
	var vals: PackedFloat32Array = pk.value
	var alive: PackedByteArray = pk.alive
	var n: int = int(pk.GRID_N)
	var cell: float = float(pk.GRID_CELL)
	var half: float = float(pk.GRID_HALF)
	var coin_kind: int = int(pk.KIND_COIN)
	var vac_kind: int = int(pk.KIND_VACUUM)
	var r := _lure_r
	var boss := _boss_at()
	if head.size() == n * n:
		var x0 := clampi(floori((me.x - r + half) / cell), 0, n - 1)
		var x1 := clampi(floori((me.x + r + half) / cell), 0, n - 1)
		var z0 := clampi(floori((me.z - r + half) / cell), 0, n - 1)
		var z1 := clampi(floori((me.z + r + half) / cell), 0, n - 1)
		for cz in range(z0, z1 + 1):
			for cx in range(x0, x1 + 1):
				var i := head[cz * n + cx]
				var guard := 0
				var sum := 0.0
				var at := Vector3.ZERO
				while i >= 0 and guard < 4096:
					guard += 1
					if i < alive.size() and alive[i] == 1:
						var dx := pos[i].x - me.x
						var dz := pos[i].z - me.z
						var d2 := dx * dx + dz * dz
						if d2 > mag * mag and d2 < r * r:
							var k := kinds[i]
							var worth := float(vals[i])
							if k == coin_kind:
								worth *= COIN_WORTH
							elif k == vac_kind:
								worth = VACUUM_WORTH
							sum += worth
							at += pos[i] * worth
					i = nxt[i] if i < nxt.size() else -1
				if sum <= 0.0:
					continue
				at /= sum
				if not within_leash(at, boss):
					continue
				var d := Vector2(at.x - me.x, at.z - me.z).length()
				var s := sum / pow(d + LURE_NEAR, LURE_POW)
				if s > best_s:
					best_s = s
					best = at
	var p = _game.player
	for sp in pk.specials:
		if not is_instance_valid(sp) or bool(sp.taken) or sp.def == null:
			continue
		if str(sp.def.effect_kind) == "heal" and float(p.hp) >= float(p.max_hp) * HEART_BELOW:
			continue
		var sat: Vector3 = (sp as Node3D).global_position
		if not within_leash(sat, boss):
			continue
		var sd := Vector2(sat.x - me.x, sat.z - me.z).length()
		if sd > r:
			continue
		var ss := POWERUP_WORTH / pow(sd + LURE_NEAR, LURE_POW)
		if ss > best_s:
			best_s = ss
			best = sat
	return best


## The boss's place while one lives (Vector3.INF for none).
func _boss_at() -> Vector3:
	var em = _game.enemies if _game else null
	if em == null:
		return Vector3.INF
	var bi: int = int(em.boss_index)
	if bi < 0 or bi >= em.alive.size() or em.alive[bi] != 1:
		return Vector3.INF
	return em.pos[bi]


## The walk back to a living boss at `boss` (Vector3.INF: none): a goal at it while the hero at `me` is further than
## BOSS_LEASH from it, or further than BOSS_BACK once he is walking back (`back`); {} otherwise.
static func boss_goal(me: Vector3, boss: Vector3, back: bool) -> Dictionary:
	if boss == Vector3.INF:
		return {}
	var d := Vector2(boss.x - me.x, boss.z - me.z).length()
	if d > BOSS_LEASH or (back and d > BOSS_BACK):
		return {"key": "boss", "at": boss, "must": false, "what": "boss"}
	return {}


## Whether a spot at `at` is one he may walk to while a boss lives at `boss`: within BOSS_LEASH of it (any spot with none).
static func within_leash(at: Vector3, boss: Vector3) -> bool:
	return boss == Vector3.INF or Vector2(at.x - boss.x, at.z - boss.z).length() <= BOSS_LEASH


## Whether the boss's chest still lies unopened (the bot opens it before it steps through the portal).
func _boss_chest_lying() -> bool:
	var pk = _game.pickups
	if pk == null:
		return false
	for c in pk.chests:
		if is_instance_valid(c) and bool(c.boss) and not bool(c.opened):
			return true
	return false


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


## A level-up card's tier for the bot (lower is taken first; ties at random), a sensible player's priorities (pass 77
## contract): 0 an evolution (a maxed line's evolution card), 1 the hero's favourite arriving (the card says FAVOURITE),
## 2 a new weapon (offered only while a weapon slot is free), 3 a level of a held weapon, 4 a hero perk (the contract
## names none: placed after the weapons), 5 a new line (only while a line slot is free), 6 a level of a held line,
## 7 a passive item (new or a level), 8 anything else.
static func card_tier(card: Dictionary) -> int:
	var type := str(card.get("type", ""))
	var d = card.get("def")
	if bool(card.get("evolve", false)) or type == "evolution":
		return 0
	if type == "weapon" and d != null and bool(d.get("is_evolution")):
		return 0
	if bool(card.get("favourite", false)):
		return 1
	var fresh := bool(card.get("is_new", false))
	match type:
		"weapon":
			return 2 if fresh else 3
		"perk":
			return 4
		"passive":
			var line: bool = d != null and d.has_method("is_line") and bool(d.is_line())
			if line:
				return 5 if fresh else 6
			return 7
	return 8


## The card the bot takes from `offer`: the best tier on the table, ties at random by `rng` ({} for an empty offer).
static func choose_card(offer: Array, rng: RandomNumberGenerator) -> Dictionary:
	var best := 1 << 30
	var tied: Array = []
	for c in offer:
		if not (c is Dictionary):
			continue
		var tier := card_tier(c)
		if tier < best:
			best = tier
			tied = [c]
		elif tier == best:
			tied.append(c)
	if tied.is_empty():
		return {}
	return tied[rng.randi() % tied.size()]


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
		"revives": _revives.duplicate(), "assists": _assists, "picks": _picks, "kills": int(_run.kills),
		"xp_total": snappedf(float(ra.get("xp_total")) if ra and ra.get("xp_total") != null else 0.0, 0.1),
		"dmg_total": snappedf(dmg, 0.1), "build_text": build, "started": str(header.get("started", ""))}


## The player's JSON from the recorder's rows and events (in memory) and the tool's own: meta, the series, the events.
func build_output(ra: Node, reason: String) -> Dictionary:
	var end_ev := {"t": snappedf(_play_t(), 0.1), "clock": snappedf(float(_run.elapsed), 0.1), "kind": "end", "reason": reason}
	# the evolutions among the weapon ids (held_by counts them apart)
	var evo_ids := {}
	for id in (_reg.get("weapons") as Dictionary).keys():
		if bool(_reg.weapons[id].is_evolution):
			evo_ids[str(id)] = true
	var out := series(ra.get("samples"), ra.get("events"), _events, end_ev, evo_ids)
	var sums: Dictionary = out["sums"]
	out.erase("sums")
	var meta := _meta(ra, reason)
	meta["rows"] = int(sums["rows"])
	meta["deaths"] = int(sums["deaths"])
	meta["gold_total"] = int(sums["gold_total"])
	out["meta"] = meta
	return out


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
	out["sums"] = {"rows": rows.size(), "deaths": fall_t.size(), "gold_total": gsum}
	out["t"] = t
	out["clock"] = clock
	out["stage"] = stage
	out["phase"] = phase
	out["hp"] = hp
	out["hp_max"] = hp_max
	out["dps"] = dps
	out["est"] = est
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
		for k in _mode_frames:
			total += int(_mode_frames[k])
		for k in _mode_frames:
			modes += " %s %d%%" % [k, roundi(100.0 * float(_mode_frames[k]) / maxf(float(total), 1.0))]
		_mode_frames.clear()
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
