## The bot (pass 80, lane BOT): one reusable player for the run sim (tools/sim_run.gd) and the Watch (lane WATCH). It
## answers every screen a run raises (cards, the mutation offer, chests, the Totem Pole, the Stranger, the shop, the
## portal, Down!) and drives the hero's legs (tools/bot/BotLegs.gd, pass 77's kiting autopilot) towards one goal at a
## time; every choice it makes is a decision entry with the options, their scores and a reason in a player's words.
##   const BOT := preload("res://tools/bot/Bot.gd")
##   var bot = BOT.new(game, {"seed": 7, "preset": "explorer", "skill": 0.8})
##   bot.tick(dt)            # every frame, after the game's own
##   bot.intent / bot.goal / bot.decisions / bot.decided (signal)
## The options (keys in tools/dl/p80/keys_BOT.md, numbers in BALANCING.md): `preset` names a whole set ("sim77" = pass
## 77's bot exactly, "explorer" the default, "careless", "expert"); any key given wins over the preset's.
## Reached only from tools and tests: nothing here names an autoload or a game class (tools compile before autoloads).
extends RefCounted

signal decided(entry: Dictionary)

const LEGS := preload("res://tools/bot/BotLegs.gd")
const CARDS := preload("res://tools/bot/BotCards.gd")
const GOALS := preload("res://tools/bot/BotGoals.gd")
const TOTEM_BOONS_PATH := "res://core/systems/TotemBoons.gd"

## a chest within this many metres is walked to; one not reached in CHEST_PATIENCE play seconds is left for CHEST_REST
const CHEST_RANGE := 30.0
const CHEST_PATIENCE := 20.0
const CHEST_REST := 30.0
## the boss's chest and the portal must be reached: past MUST_PATIENCE play seconds the hero is put there (an "assist")
const MUST_PATIENCE := 45.0
## after a "Not yet" he steps this far out from the portal (past its re-arm distance, Portal.REARM 2.5 m) and back in
const PORTAL_OUT := 3.2
## While a boss lives he fights it (pass 77's boss log): he keeps within BOSS_LEASH m of it, walking back to BOSS_BACK m
## when he is further, and the sweep's gems and the chests he walks to count only within BOSS_LEASH of it then
## (boss "leash"; "free" lets him roam).
const BOSS_LEASH := 10.0
const BOSS_BACK := 7.0
## The sweep (_lure, BotLegs.steer_sweep): the pickups lying within `stray` m summed by grid cell, the cell with the most
## worth / (distance + LURE_NEAR)^LURE_POW the spot; a coin COIN_WORTH a gold, a vacuum gem VACUUM_WORTH, a power-up
## POWERUP_WORTH (a heart only under HEART_BELOW of his health); the pick is made again every LURE_EVERY frames.
const LURE_R := 60.0
const LURE_NEAR := 2.0
const LURE_POW := 1.5
const COIN_WORTH := 2.0
const VACUUM_WORTH := 400.0
const POWERUP_WORTH := 40.0
const HEART_BELOW := 0.7
const LURE_EVERY := 6

## The presets: every option's value (the defaults of the keys a caller leaves out; plain literals: tools/sim_batch.py
## reads this block for the Level Editor's Sim tab). "sim77" is pass 77's bot exactly
## (tiers for cards, a random mutation, the gift with the most feathers, the shop and the Stranger left, no goals but
## chests, the boss and the portal).
const PRESETS := {
	"sim77": {"skill": 1.0, "style": "balanced", "reaction": 0.0, "dodge": 1.0, "daring": 0.5, "stray": 60.0, "explore": 0.0,
		"totems": false, "barrels": false, "powerups": true, "structures": false, "shop": false, "stranger": false, "boss": "leash",
		"cards": "tier", "specials": false, "portal": "endless"},
	"explorer": {"skill": 0.9, "style": "balanced", "reaction": 0.0, "dodge": 1.0, "daring": 0.5, "stray": 60.0, "explore": 0.6,
		"totems": true, "barrels": true, "powerups": true, "structures": true, "shop": true, "stranger": true, "boss": "leash",
		"cards": "score", "specials": true, "portal": "endless"},
	"careless": {"skill": 0.4, "style": "balanced", "reaction": 0.6, "dodge": 0.5, "daring": 0.8, "stray": 60.0, "explore": 0.4,
		"totems": true, "barrels": true, "powerups": true, "structures": true, "shop": true, "stranger": true, "boss": "free",
		"cards": "score", "specials": true, "portal": "endless"},
	"expert": {"skill": 1.0, "style": "balanced", "reaction": 0.1, "dodge": 1.0, "daring": 0.45, "stray": 60.0, "explore": 0.7,
		"totems": true, "barrels": true, "powerups": true, "structures": true, "shop": true, "stranger": true, "boss": "leash",
		"cards": "score", "specials": true, "portal": "endless"},
}
const DEFAULT_PRESET := "explorer"
## Pass 87 (lane STOOLS; a stage run ends at its boss, then the portal counts down to Endless): what the bot does after
## the stage's boss: "endless" (the default) never walks to the portal and answers it "not yet" if he steps in, so the
## run goes on into Endless until the stop or his death; "extract" walks to the portal (after the boss's chest) and
## extracts (the run ends there, the stage beaten).
const PORTAL_CHOICES := ["endless", "extract"]
## The planner (BotGoals; on whenever explore > 0 or totems, barrels or structures are on): a new plan every PLAN_EVERY
## play seconds; a goal held is kept unless one SWITCH_K times better turns up; none under U_MIN is taken; a goal not
## reached in PATIENCE_BASE + PATIENCE_PER_M s a metre (+ its use time) is given up and rests REST_S seconds.
const PLAN_EVERY := 0.5
const SWITCH_K := 1.4
const U_MIN := 4.0
const PATIENCE_BASE := 8.0
const PATIENCE_PER_M := 0.55
const REST_S := 40.0
## The kite wins (the goal is held, he kites) when the crowd closes: HOLD_CROWD or more stand within HOLD_NEAR m, a big
## one or a rocket pushes (BotLegs.danger_push) more than HOLD_DANGER, or, under HOLD_HURT of his health, a creature is
## nearer than his flee distance (on the way the walk itself sidesteps a single one, BotLegs.steer_to); he goes back to
## the goal once fewer than HOLD_CROWD_OUT stand that close, the push is under HOLD_DANGER_OUT and (hurt) none is nearer
## than his flee distance, after HOLD_MIN s at least. Within HOLD_GRAB m of the goal he grabs it whatever comes; a
## structure's use he has HOLD_KEEP_USE done of goes on unless he is under HOLD_KEEP_HP of his health. While held the
## goal's patience runs at HOLD_PATIENCE of the clock.
const HOLD_CROWD := 5
const HOLD_NEAR := 3.0
const HOLD_DANGER := 0.4
const HOLD_CROWD_OUT := 3
const HOLD_DANGER_OUT := 0.2
const HOLD_MIN := 0.4
const HOLD_HURT := 0.5
const HOLD_GRAB := 2.5
const HOLD_KEEP_USE := 0.6
const HOLD_KEEP_HP := 0.4
const HOLD_PATIENCE := 0.5
## Danger (the scores' and the planner's): the damage taken, fading over HURT_FADE s, over max HP (0..1).
const HURT_FADE := 30.0
## The Stranger: his ware is taken while the hero holds STRANGER_HP of his health and its score beats the HP it costs
## (the cut in % of max HP x STRANGER_HP_PTS x survival's weight) by STRANGER_MIN.
const STRANGER_HP := 0.6
const STRANGER_HP_PTS := 0.8
const STRANGER_MIN := 5.0
## The shop: the ware with the best score less its price (x GOLD_PTS a gold x greed's weight) is bought when that is
## SHOP_MIN or more and he can pay.
const GOLD_PTS := 0.03
const SHOP_MIN := 6.0
## The hunt (pass 82, lane WATCH: a special goal, BotGoals.special_candidates): the kite leans towards the special
## (BotLegs.steer_sweep with it as the lure: the sweep's lean, whole while the way is clear, a little while a creature
## stands in it, none with a big one close, less the more he is hurt) until it is within HUNT_NEAR m and on the screen
## (EnemyManager.onscreen: the weapons take it first there, within their range and the map's target_priority reach of
## 10 m); that ends the hunt ("found") and he plays on as he would. The hold (the crowd on him, a big one's push, hurt)
## still wins, and a hunt is no commitment (anything better takes over at once). Patience as every goal's (plus
## BotGoals.SPECIAL_FIGHT_S of slack: the lean is slower than a walk); a hunt ends after SPECIAL_MAX_S play seconds
## whatever (the special rests REST_S then). What the sims showed on the way: walking straight at every special, or
## keeping the hunt as the goal while the weapons fought it, killed no larger share and cost levels and falls.
const HUNT_NEAR := 6.0
## (a special in reach by the planner's word, BotGoals.IN_REACH: no hunt starts for one within it and on the screen)
const HUNT_FAR := GOALS.IN_REACH
const SPECIAL_MAX_S := 60.0
const STYLES := ["balanced", "damage", "safety", "greedy"]
const BOOL_KEYS := ["totems", "barrels", "powerups", "structures", "shop", "stranger", "specials"]

var game: Node
## the options as resolved (resolve_opts): every key has its value
var opts: Dictionary = {}
## what the legs do now: kite | sweep | explore | totem | barrel | powerup | structure:<id> | chest | boss | boss_chest |
## portal | dodge | down | special (pass 82: hunting one)
var intent := "kite"
## {} or {what, key, at: Vector3, why: String}
var goal: Dictionary = {}
## every decision so far, newest last ({t, clock, kind, offered, taken, reason, level, dps_before})
var decisions: Array = []
## the run sim's own events (pick, portal, assist, revive), as tools/sim_run.gd's output writes them
var events: Array = []
var revives := {"ad": 0, "phoenix": 0, "keep": 0}
var assists := 0
var picks := 0
## frames the legs spent in each mode since the caller last cleared it (the run sim's progress line)
var mode_frames: Dictionary = {}
var legs: LEGS
## the bot's own dice (card ties, a random mutation, a tie among gifts): pass 77's `_bot` stream
var rng := RandomNumberGenerator.new()

var _run: Node
var _reg: Node
var _t := 0.0
var _death := "end"
var _ad_used := false
var _phoenix_was := false
var _phoenix_pending := false
var _chest_tapped := false
var _goal_key := ""
var _goal_t := 0.0
var _chest_rest: Dictionary = {}
var _lure_at := Vector3.INF
var _lure_wait := 0
var _boss_back := false
var _lure_r := LURE_R
## the planner (BotGoals) and its state: the goal held ({} none; "gems" the sweep), the next plan, the hold
var planner = null
var _cur: Dictionary = {}
var _plan_at := 0.0
var _hold := false
var _hold_t := 0.0
var _nearest := INF
var _near_n := 0
var _dpush := 0.0
var _scan_k := 0
var _lure_s := 0.0
## danger's memory: damage taken, fading (HURT_FADE), and the health last frame
var _hurt := 0.0
var _hp_last := -1.0
## tallies (the run sim's meta): metres walked, goals chosen by kind, goals given up
var metres := 0.0
var goals_by: Dictionary = {}
var gave_up := 0
var _last_pos := Vector3.INF
## the kind of the goal just reached (one explore cell after another is one decision)
var _last_kind := ""
## pass 82: the hunts of the specials (summary's `specials`): those that brought it in reach, those that ended with it down
## before that, those given up
var specials_found := 0
var specials_down := 0
var specials_gave_up := 0
## pass 85 (lane TOOLS): the creatures within BotGoals.PU_CROWD_R m (the power-ups' worth while he fights); the power-ups
## that lay on the map (instance id -> true, seen anywhere) and those he walked to and took (summary's `powerups`)
var _crowd_near := 0
var pu_lying: Dictionary = {}
var pu_reached := 0


func _init(p_game: Node, p_opts: Dictionary = {}) -> void:
	game = p_game
	opts = resolve_opts(p_opts)
	var tree := game.get_tree() if game != null and game.is_inside_tree() else null
	if tree:
		_run = tree.root.get_node_or_null("Run")
		_reg = tree.root.get_node_or_null("Registry")
	var sd := int(opts["seed"])
	rng.seed = hash([sd, "bot"])
	legs = LEGS.new(hash([sd, "pilot"]))
	legs.keep_d = daring_keep(float(opts["daring"]))
	legs.flee_d = daring_flee(float(opts["daring"]))
	legs.reaction = float(opts["reaction"])
	legs.dodge = float(opts["dodge"])
	legs.dodge_seed = hash([sd, "dodge"])
	if float(opts.get("lure_w", -1.0)) >= 0.0:
		legs.lure_w = float(opts["lure_w"])
	if float(opts.get("lure_close", -1.0)) >= 0.0:
		legs.lure_close = float(opts["lure_close"])
	_lure_r = float(opts["stray"])
	_death = str(opts["death"])
	_t = float(opts.get("t0", 0.0))
	if _run:
		_phoenix_was = bool(_run.phoenix_used)
	if planner_on(opts):
		planner = GOALS.new(hash([sd, "goals"]))
		if game != null and game.get("map") != null:
			planner.setup_map(game.map)


## Whether the planner runs: the map's things are wanted (explore, totems, barrels or structures; pass 82: or the specials).
static func planner_on(o: Dictionary) -> bool:
	return float(o.get("explore", 0.0)) > 0.0 or bool(o.get("totems", false)) or bool(o.get("barrels", false)) or bool(o.get("structures", false)) \
		or bool(o.get("specials", false))


## The options in full: the preset's values (opts.preset, else DEFAULT_PRESET), every known key given over them, coerced
## and kept in range; plus seed (1), death ("end": Down! gives up; "ad": the ad revive once while offered; "keep": stood
## up at once), lure_w / lure_close (-1: the legs' own) and t0 (the caller's clock at the start). Unknown keys are dropped.
static func resolve_opts(raw: Dictionary) -> Dictionary:
	var pre := str(raw.get("preset", DEFAULT_PRESET))
	if not PRESETS.has(pre):
		pre = DEFAULT_PRESET
	var o: Dictionary = (PRESETS[pre] as Dictionary).duplicate()
	o["preset"] = pre
	o["seed"] = 1
	o["death"] = "end"
	o["lure_w"] = -1.0
	o["lure_close"] = -1.0
	o["t0"] = 0.0
	for k in raw:
		var key := str(k)
		var v = raw[k]
		match key:
			"seed":
				o["seed"] = int(v) if int(v) != 0 else 1
			"skill", "dodge", "daring", "explore":
				o[key] = clampf(float(v), 0.0, 1.0)
			"reaction":
				o[key] = clampf(float(v), 0.0, 3.0)
			"stray":
				o[key] = clampf(float(v), 0.0, 200.0)
			"style":
				o[key] = str(v) if STYLES.has(str(v)) else str(o[key])
			"boss":
				o[key] = str(v) if str(v) in ["leash", "free"] else str(o[key])
			"cards":
				o[key] = str(v) if str(v) in ["tier", "score"] else str(o[key])
			"portal":
				o[key] = str(v) if PORTAL_CHOICES.has(str(v)) else str(o.get(key, "endless"))
			"death":
				o[key] = str(v) if str(v) in ["end", "ad", "keep"] else "end"
			"lure_w", "lure_close", "t0":
				o[key] = float(v)
			_:
				if BOOL_KEYS.has(key):
					o[key] = truthy(v)
	return o


## A bool option from a word or a number: 1, true, yes, on.
static func truthy(v) -> bool:
	if v is bool:
		return v
	return str(v).strip_edges().to_lower() in ["1", "true", "yes", "on"]


## `daring` as the kite's distances: KEEP / FLEE at 0.5 (pass 77's 4.5 m and 2.6 m), 6.5 / 3.6 m at 0, 2.5 / 1.6 m at 1.
static func daring_keep(d: float) -> float:
	return LEGS.KEEP + (0.5 - d) * 4.0


static func daring_flee(d: float) -> float:
	return LEGS.FLEE + (0.5 - d) * 2.0


# ---------------------------------------------------------------- the frame

## One frame: the open screen answered (one a frame; the game opens the next in its turn), death=keep's stand-up, then
## the legs.
func tick(dt: float) -> void:
	_t += dt
	if game == null or not is_instance_valid(game) or bool(game.get("_ended")):
		return
	_screens()
	if bool(game.get("_ended")):
		return
	_keep_up()
	_drive(dt)


func play_t() -> float:
	var ra := game.get_node_or_null("RunAnalytics") if game != null and is_instance_valid(game) else null
	return float(ra.get("play_t")) if ra else 0.0


func _clock() -> float:
	return float(_run.elapsed) if _run else 0.0


## A decision entry appended and announced: kind, the options [{id, name, score, parts}], the one taken ("" none) and
## the reason in a player's words; the time, the run's clock, the level and the estimated DPS are added here.
func _decide(kind: String, offered: Array, taken: String, reason: String, extra: Dictionary = {}) -> Dictionary:
	var e := {"t": snappedf(play_t(), 0.1), "clock": snappedf(_clock(), 0.1), "kind": kind, "offered": offered, "taken": taken,
		"reason": reason, "level": int(_run.level) if _run else 0, "dps_before": snappedf(dps_now(), 0.1)}
	for k in extra:
		e[k] = extra[k]
	decisions.append(e)
	decided.emit(e)
	return e


## The weapons' estimated DPS now (what the pause screen prints: WeaponInstance.dps_estimate summed).
func dps_now() -> float:
	if _run == null:
		return 0.0
	var s := 0.0
	for w in _run.weapons:
		s += float(w.dps_estimate())
	return s


# ---------------------------------------------------------------- the screens

## Every screen a run raises, answered as the options say (one a frame).
func _screens() -> void:
	var g := game
	if g.revive_screen and g.revive_screen.visible:
		_down()
		return
	if g.portal_dialog and g.portal_dialog.visible:
		# walked in on the way to the boss's chest: "Not yet" (the chest first; the portal asks again once he has stepped
		# out and back in)
		if _boss_chest_lying():
			g.portal_dialog.decline()
			return
		# pass 87 (lane STOOLS): EXTRACT with portal=extract, else "not yet" (the countdown runs on into Endless)
		var out := str(opts.get("portal", "endless")) == "extract"
		events.append({"t": snappedf(play_t(), 0.1), "clock": snappedf(_clock(), 0.1), "kind": "portal", "stage": int(_run.stage) + 1, "extract": out})
		g.portal_dialog.visible = false
		g.portal_dialog.decided.emit(out)
		return
	var cs = g.cards
	if cs and cs.visible and not (cs._offer as Array).is_empty() and not cs._picking:
		if cs.banish_mode():
			cs._toggle_banish()
		if cs.path_mode:
			if cs.reel_running():
				cs.skip_reel()
			var offer: Array = cs._offer
			var mut := _choose_mutation(offer)
			_note_pick(mut, offer, -1)
			cs._pick(mut)
		else:
			var pick := _choose_card(cs._offer)
			if not pick.is_empty():
				picks += 1
				_note_pick(pick, cs._offer, CARDS.card_tier(pick))
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
		_note_chest(ch)
		ch._finish(true)
		return
	_chest_tapped = false
	if g.resume_gate and g.resume_gate.visible:
		g.resume_gate.tap()
	if g.stranger_screen and g.stranger_screen.visible:
		_stranger(g.stranger_screen)
		return
	if g.structure_shop and g.structure_shop.visible:
		# a purchase closes the stall a beat later (StructureShop._buy): nothing to answer meanwhile
		if not bool(g.structure_shop.get("_done")):
			_shop(g.structure_shop)
		return
	var ts = g.totem_screen
	if ts and ts.visible and not ts._done:
		_totem(ts)
		return


## A level-up's card: pass 77's tiers (opts.cards "tier"), else the scores; a decision entry either way.
func _choose_card(offer: Array) -> Dictionary:
	if str(opts["cards"]) == "score":
		return _choose_scored("card", offer)
	var pick := CARDS.choose_card(offer, rng)
	if pick.is_empty():
		return pick
	var rows: Array = []
	for c in offer:
		if c is Dictionary:
			var tier := CARDS.card_tier(c)
			rows.append({"id": str(c.get("id", "")), "name": CARDS.card_name(c), "score": float(8 - tier), "parts": {"tier": tier}})
	var tier_p := CARDS.card_tier(pick)
	_decide("card", rows, str(pick.get("id", "")), "%s: %s" % [CARDS.card_name(pick), CARDS.TIER_WORDS[clampi(tier_p, 0, 8)]])
	return pick


## A mutation offer's pick: pass 77's at random (opts.cards "tier"), else by the scores.
func _choose_mutation(offer: Array) -> Dictionary:
	if str(opts["cards"]) == "score":
		return _choose_scored("mutation", offer)
	var mut: Dictionary = offer[rng.randi() % offer.size()]
	var rows: Array = []
	for c in offer:
		if c is Dictionary:
			rows.append({"id": str(c.get("id", "")), "name": CARDS.card_name(c), "score": 0.0, "parts": {}})
	_decide("mutation", rows, str(mut.get("id", "")), "%s: at random" % CARDS.card_name(mut))
	return mut


## The health now as a share of max HP (1 with no hero).
func hp_frac() -> float:
	var p = game.player if game != null else null
	if p == null or float(p.max_hp) <= 0.0:
		return 1.0
	return clampf(float(p.hp) / float(p.max_hp), 0.0, 1.0)


## Danger (0..1): the damage of the last half minute or so over max HP.
func danger() -> float:
	var p = game.player if game != null else null
	if p == null or float(p.max_hp) <= 0.0:
		return 0.0
	return clampf(_hurt / float(p.max_hp), 0.0, 1.0)


## The scores' view of the run now.
func _ctx() -> Dictionary:
	return CARDS.context(_run, hp_frac(), danger(), str(opts["style"]))


## The rows a decision lists: [{id, name, score, parts}] for scored cards (`scored` from CARDS.score_card).
static func _rows(cards: Array, scored: Array) -> Array:
	var rows: Array = []
	for i in range(cards.size()):
		var c: Dictionary = cards[i]
		var sc: Dictionary = scored[i]
		rows.append({"id": str(c.get("id", "")), "name": CARDS.card_name(c), "score": float(sc["score"]), "parts": sc["parts"]})
	return rows


## A scored choice from `offer` (cards or a mutation offer): every card scored, the pick by skill (CARDS.pick_scored), a
## decision entry with the reason (and, when skill took a weaker one, the best's name).
func _choose_scored(kind: String, offer: Array) -> Dictionary:
	var cards: Array = []
	for c in offer:
		if c is Dictionary:
			cards.append(c)
	if cards.is_empty():
		return {}
	var ctx := _ctx()
	var scored: Array = []
	for c in cards:
		scored.append(CARDS.score_card(c, ctx))
	var rows := _rows(cards, scored)
	var i := CARDS.pick_scored(rows, float(opts["skill"]), rng)
	_decide(kind, rows, str(cards[i].get("id", "")), str(scored[i]["words"]) + slip_note(rows, i))
	return cards[i]


## When the skill dial took a weaker one than the best scored: " (a weaker pick: <best> scored N against M)"; else "".
static func slip_note(rows: Array, i: int) -> String:
	var best := 0
	for k in range(rows.size()):
		if float(rows[k]["score"]) > float(rows[best]["score"]):
			best = k
	if i == best or float(rows[best]["score"]) == float(rows[i]["score"]):
		return ""
	return " (a weaker pick: %s scored %d against %d)" % [str(rows[best]["name"]), roundi(float(rows[best]["score"])), roundi(float(rows[i]["score"]))]


## A chest's gift (always taken): a decision entry naming it.
func _note_chest(ch) -> void:
	var r = ch.get("_result")
	var d = r.get("def") if r is Dictionary else null
	var nm := str(d.get("display_name")) if d != null and d.get("display_name") != null else "the chest"
	var id := str(d.get("id")) if d != null and d.get("id") != null else ""
	_decide("chest", [{"id": id, "name": nm, "score": 1.0, "parts": {}}], id, "%s: a chest is always opened" % nm)


## The Stranger: pass 77 walks away (and so does a bot told stranger=0); else his ware is taken while the hero is healthy
## and it is worth the cut (STRANGER_HP, STRANGER_HP_PTS, STRANGER_MIN).
func _stranger(ss) -> void:
	var offer = ss.result() if ss.has_method("result") else {}
	var nm := CARDS.card_name(offer) if offer is Dictionary and not (offer as Dictionary).is_empty() else "nothing"
	if bool(opts["stranger"]) and str(opts["cards"]) == "score" and offer is Dictionary and not (offer as Dictionary).is_empty():
		var ctx := _ctx()
		var sc := CARDS.score_card(offer, ctx)
		var cut := float((offer as Dictionary).get("hp_cost", 0.15))
		var cost := cut * 100.0 * STRANGER_HP_PTS * float((ctx["w"] as Dictionary)["survival"]) * CARDS.danger_weight(ctx)
		var net := float(sc["score"]) - cost
		var row := {"id": str(offer.get("id", "")), "name": nm, "score": snappedf(net, 0.1), "parts": (sc["parts"] as Dictionary).merged({"hp_cost": snappedf(-cost, 0.1)})}
		var hf := hp_frac()
		if hf >= STRANGER_HP and net >= STRANGER_MIN:
			_decide("stranger", [row], row["id"], "took the deal, %d%% of max HP for %s" % [roundi(cut * 100.0), str(sc["words"])])
			ss._finish(true)
			return
		var no := "too hurt for the deal (%d%% HP)" % roundi(hf * 100.0) if hf < STRANGER_HP else "not worth %d%% of max HP: %s" % [roundi(cut * 100.0), str(sc["words"])]
		_decide("stranger", [row], "", "walked away: " + no)
		ss._finish(false)
		return
	_decide("stranger", [{"id": str((offer as Dictionary).get("id", "")) if offer is Dictionary else "", "name": nm, "score": 0.0, "parts": {}}], "",
		"walked away from %s: the Stranger is left alone" % nm)
	ss._finish(false)


## The shop: pass 77 leaves (and so does a bot told shop=0); else the ware with the best score less its price is bought
## when it is worth SHOP_MIN and he can pay (GOLD_PTS).
func _shop(sh) -> void:
	var rows: Array = []
	var cards: Array = []
	for c in sh._offer:
		if c is Dictionary:
			cards.append(c)
	if not bool(opts["shop"]) or str(opts["cards"]) != "score":
		for c in cards:
			rows.append({"id": str(c.get("id", "")), "name": CARDS.card_name(c), "score": 0.0, "parts": {"price": int(sh.price_of(c))}})
		_decide("shop", rows, "", "left the shop: the shop is left alone")
		sh._finish(false)
		return
	var ctx := _ctx()
	var gw := float((ctx["w"] as Dictionary)["greed"])
	var gold := int(_run.run_gold)
	var best := -1
	var best_net := -INF
	var scored: Array = []
	for i in range(cards.size()):
		var c: Dictionary = cards[i]
		var sc := CARDS.score_card(c, ctx)
		scored.append(sc)
		var price := int(sh.price_of(c))
		var net := float(sc["score"]) - float(price) * GOLD_PTS * gw
		rows.append({"id": str(c.get("id", "")), "name": CARDS.card_name(c), "score": snappedf(net, 0.1),
			"parts": (sc["parts"] as Dictionary).merged({"price": price, "gold": snappedf(-float(price) * GOLD_PTS * gw, 0.1)})})
		if price <= gold and net > best_net:
			best_net = net
			best = i
	if best >= 0 and best_net >= SHOP_MIN and best < (sh._cards as Array).size():
		var c: Dictionary = cards[best]
		var price := int(sh.price_of(c))
		_decide("shop", rows, str(c.get("id", "")), "bought for %d gold: %s" % [price, str(scored[best]["words"])])
		sh._buy(c, price, sh._cards[best])
		return
	var why := "nothing affordable (%d gold)" % gold if best < 0 else "nothing worth its price"
	_decide("shop", rows, "", "left the shop: " + why)
	sh._finish(false)


## A Totem Pole's gift: pass 77's, the one with the most feathers (ties at random) with opts.cards "tier"; else by the
## scores (each gift as the effect it puts on the hero).
func _totem(ts) -> void:
	if str(opts["cards"]) == "score":
		_totem_scored(ts)
		return
	var best: Array = []
	var most := -1
	var rows: Array = []
	for p in ts.planks():
		var f := int(p.feathers)
		var b: Dictionary = p.boon
		rows.append({"id": str(b.get("id", "")), "name": str(b.get("name", b.get("id", ""))), "score": float(f), "parts": {"feathers": f}})
		if f > most:
			most = f
			best = [p]
		elif f == most:
			best.append(p)
	if best.is_empty():
		return
	var pick = best[rng.randi() % best.size()]
	_decide("totem", rows, str(pick.boon.get("id", "")), "%s: the most feathers (%d)" % [str(pick.boon.get("name", "")), most])
	ts._pick(pick)


## A Totem Pole's gift by the scores: each gift as the effect it puts on the hero (TotemBoons.effect_of), the pick by skill.
func _totem_scored(ts) -> void:
	var boons_script = load(TOTEM_BOONS_PATH)
	var planks: Array = ts.planks()
	var cards: Array = []
	for p in planks:
		var b: Dictionary = p.boon
		cards.append({"type": "boon", "id": str(b.get("id", "")), "name": str(boons_script.title(b)), "effects": [boons_script.effect_of(b)]})
	if cards.is_empty():
		return
	var ctx := _ctx()
	var scored: Array = []
	for c in cards:
		scored.append(CARDS.score_card(c, ctx))
	var rows := _rows(cards, scored)
	for k in range(rows.size()):
		(rows[k]["parts"] as Dictionary)["feathers"] = int(planks[k].feathers)
	var i := CARDS.pick_scored(rows, float(opts["skill"]), rng)
	_decide("totem", rows, str(cards[i]["id"]), str(scored[i]["words"]) + slip_note(rows, i))
	ts._pick(planks[i])


## The bot's pick as an event (the Sim tab can say what he took): its id, kind, the level it brings, its tier (-1 a
## mutation offer's pick) and what else was on the table.
func _note_pick(card: Dictionary, offer: Array, tier: int) -> void:
	var others: Array = []
	for c in offer:
		if c is Dictionary and not is_same(c, card):
			others.append(str(c.get("id", "")))
	events.append({"t": snappedf(play_t(), 0.1), "clock": snappedf(_clock(), 0.1), "kind": "pick", "id": str(card.get("id", "")),
		"type": str(card.get("type", "")), "item_kind": CARDS.item_kind(card), "new": bool(card.get("is_new", false)),
		"level": int(card.get("level_to", 0)), "tier": tier, "others": others})


## Down!, by `death`: ad gets up once on the ad revive while Down! offers it, then gives up; end gives up at once (the run
## ends); keep never sees it (the hero is stood up as he falls), but answers "debug" if it comes.
func _down() -> void:
	var rs = game.revive_screen
	if _death == "keep":
		revives["keep"] = int(revives["keep"]) + 1
		rs._decide("debug")
		return
	if _death == "ad" and not _ad_used and ad_offered(rs):
		_ad_used = true
		revives["ad"] = int(revives["ad"]) + 1
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
	var p = game.player
	var ph := bool(_run.phoenix_used)
	if p.dead:
		if ph and not _phoenix_was:
			_phoenix_pending = true
			revives["phoenix"] = int(revives["phoenix"]) + 1
		if _death == "keep" and not _phoenix_pending:
			p.revive()
			p.hp = p.max_hp
			p.invuln = 0.0
			revives["keep"] = int(revives["keep"]) + 1
			events.append({"t": snappedf(play_t(), 0.1), "clock": snappedf(_clock(), 0.1), "kind": "revive", "via": "keep"})
			if game.hud and game.hud.has_method("show_player_bar"):
				game.hud.show_player_bar()
	else:
		_phoenix_pending = false
	_phoenix_was = ph


# ---------------------------------------------------------------- the walk

## One frame of the legs: pass 77's (a goal: the boss's chest, the portal, a chest near, else the kite and the sweep), or
## the planner's when it runs.
func _drive(dt: float) -> void:
	if bool(game.paused) or game.player == null or game.player.dead:
		if game.player != null and game.player.dead:
			intent = "down"
		return
	var me: Vector3 = game.player.global_position
	if _last_pos != Vector3.INF:
		metres += Vector2(me.x - _last_pos.x, me.z - _last_pos.z).length()
	_last_pos = me
	if planner != null:
		_drive_planned(dt)
		return
	var g := _goal()
	if g.is_empty():
		_set_goal({})
		_goal_key = ""
		_goal_t = 0.0
		_lure_wait -= 1
		if _lure_wait <= 0:
			_lure_wait = LURE_EVERY
			_lure_at = _lure()
		legs.steer_sweep(game, dt, _t, _lure_at)
		var mode := "sweep" if _lure_at != Vector3.INF else "kite"
		mode_frames[mode] = int(mode_frames.get(mode, 0)) + 1
		intent = "dodge" if legs.seen_ring != Vector3.ZERO or legs.seen_danger > 0.4 else mode
		return
	_walk_goal(g, dt)


## A goal of pass 77's (a chest, the boss's chest, the portal, back to the boss) walked to this frame, with its patience
## and the assist.
func _walk_goal(g: Dictionary, dt: float) -> void:
	var what := str(g["what"])
	mode_frames[what] = int(mode_frames.get(what, 0)) + 1
	var key := str(g["key"])
	if key != _goal_key:
		_goal_key = key
		_goal_t = 0.0
		_set_goal(g)
	_goal_t += dt
	var at: Vector3 = g["at"]
	legs.steer_to(game, dt, at)
	intent = what
	if bool(g["must"]) and _goal_t > MUST_PATIENCE:
		# he could not get there: put him on it (the run would sit in the portal wait otherwise); the portal asks at once
		assists += 1
		events.append({"t": snappedf(play_t(), 0.1), "clock": snappedf(_clock(), 0.1), "kind": "assist", "what": what})
		var p: Node3D = game.player
		if what == "portal" and game.portal != null and is_instance_valid(game.portal):
			at = (game.portal as Node3D).global_position
			game.portal.set("armed", true)
		p.global_position = Vector3(at.x, p.global_position.y, at.z)
		p.set("velocity", Vector3.ZERO)
		_goal_t = 0.0
	elif what == "chest" and _goal_t > CHEST_PATIENCE:
		_chest_rest[key] = play_t() + CHEST_REST
		_goal_key = ""
		_goal_t = 0.0


# ---------------------------------------------------------------- the planner (pass 80)

## One frame under the planner: a must (the boss's chest, the portal, back to the boss) first, as pass 77's; else the goal
## held (BotGoals' best by utility), walked to unless the kite wins (_update_hold), stood still at inside a structure's
## ring; else the sweep.
func _drive_planned(dt: float) -> void:
	_observe(dt)
	var must := _must_goal()
	if not must.is_empty():
		if not _cur.is_empty():
			_cur = {}
		_walk_goal(must, dt)
		return
	# no must now: the next one starts its own patience
	_goal_key = ""
	_goal_t = 0.0
	_lure_wait -= 1
	if _lure_wait <= 0:
		_lure_wait = LURE_EVERY
		_lure_at = _lure()
	var now := play_t()
	if not _cur.is_empty() and str(_cur["kind"]) != "gems" and _goal_done(_cur):
		_goal_finished(_cur)
		_last_kind = str(_cur["kind"])
		_cur = {}
		_plan_at = 0.0
	if now >= _plan_at:
		_plan_at = now + PLAN_EVERY
		_replan(now)
	if _cur.is_empty() or str(_cur["kind"]) == "gems":
		legs.steer_sweep(game, dt, _t, _lure_at)
		var mode := "sweep" if _lure_at != Vector3.INF else "kite"
		mode_frames[mode] = int(mode_frames.get(mode, 0)) + 1
		intent = "dodge" if legs.seen_ring != Vector3.ZERO or legs.seen_danger > 0.4 else mode
		goal = {} if _cur.is_empty() else goal
		return
	# pass 82: a special is followed where it is now, frame by frame (the plan's place is half a second old)
	var hunting := str(_cur["kind"]) == "special"
	if hunting:
		_cur["at"] = _special_at(_cur)
	var at: Vector3 = _cur["at"]
	var me: Vector3 = game.player.global_position
	var d := Vector2(at.x - me.x, at.z - me.z).length()
	_update_hold(dt, d)
	if hunting:
		_cur["hunt_t"] = float(_cur.get("hunt_t", 0.0)) + dt
		if float(_cur["hunt_t"]) > SPECIAL_MAX_S:
			_cur["t"] = float(_cur["patience"]) + 1.0
	if _hold:
		legs.steer_sweep(game, dt, _t, Vector3.INF)
		intent = "dodge" if legs.seen_ring != Vector3.ZERO or legs.seen_danger > 0.4 else "kite"
		mode_frames["hold"] = int(mode_frames.get("hold", 0)) + 1
		_cur["t"] = float(_cur["t"]) + dt * HOLD_PATIENCE
	elif hunting:
		_hunt_step(dt, d)
	else:
		var stand := float(_cur.get("stand", 0.0))
		if stand > 0.0 and d < stand:
			_stand()
		else:
			legs.steer_to(game, dt, at)
		intent = str(_cur["what"])
		mode_frames[intent] = int(mode_frames.get(intent, 0)) + 1
		_cur["t"] = float(_cur["t"]) + dt
	if float(_cur["t"]) > float(_cur["patience"]):
		planner.resting[str(_cur["key"])] = now + REST_S
		gave_up += 1
		if hunting:
			specials_gave_up += 1
		_decide("goal", [{"id": str(_cur["key"]), "name": str(_cur["what"]), "score": snappedf(float(_cur["u"]), 0.1), "parts": {"dist": snappedf(d, 0.1)}}], "",
			"gave up on %s after %d s" % [str(_cur["why"]), roundi(float(_cur.get("hunt_t", _cur["t"])))], {"what": str(_cur["what"]), "runner_up": ""})
		_cur = {}
		goal = {}
		_plan_at = 0.0


## The thumb off the stick: he stands where he is (a structure's ring).
func _stand() -> void:
	var inp = game.player.input
	if inp != null:
		inp.wants_move = false


## What he watches every frame under the planner: the damage he takes (danger), the crowd round him (every 2nd frame: the
## nearest, how many within HOLD_NEAR), the big ones' and rockets' push (every 3rd frame), and what he sees (BotGoals).
func _observe(dt: float) -> void:
	var p = game.player
	var hp := float(p.hp)
	_hurt *= exp(-dt / HURT_FADE)
	if _hp_last >= 0.0 and hp < _hp_last:
		_hurt += _hp_last - hp
	_hp_last = hp
	_scan_k += 1
	var me: Vector3 = p.global_position
	if _scan_k % 2 == 0:
		var em = game.enemies
		var nearest := INF
		var nn := 0
		var nc := 0
		var cr2 := GOALS.PU_CROWD_R * GOALS.PU_CROWD_R
		for i in range(em.MAX):
			if em.alive[i] != 1:
				continue
			var dx: float = em.pos[i].x - me.x
			var dz: float = em.pos[i].z - me.z
			var l2 := dx * dx + dz * dz
			nearest = minf(nearest, l2)
			if l2 < HOLD_NEAR * HOLD_NEAR:
				nn += 1
			if l2 < cr2:
				nc += 1
		_nearest = sqrt(nearest) if nearest < INF else INF
		_near_n = nn
		_crowd_near = nc
	if _scan_k % 3 == 0:
		_dpush = legs.danger_push(game, me).length()
	if _scan_k % 15 == 0:
		planner.observe(game, me)
		# pass 85: every power-up that lay on the map (the share he took: summary's powerups)
		var pk = game.pickups
		if pk != null:
			for sp in pk.specials:
				if is_instance_valid(sp):
					pu_lying[sp.get_instance_id()] = true


## The kite wins while the crowd is on him (HOLD_*); the hold lifts once it has thinned.
func _update_hold(dt: float, d: float) -> void:
	var using := false
	var s = instance_from_id(int(_cur.get("ref", 0))) if _cur.has("ref") else null
	if s != null and is_instance_valid(s) and s.get("progress") != null and float(_cur.get("stand", 0.0)) > 0.0:
		using = d < float(s.def.radius) and float(s.progress) >= HOLD_KEEP_USE and hp_frac() >= HOLD_KEEP_HP
	# (pass 82: a special is never grabbed: he keeps it in range, the kite keeps him off it; pass 85: a power-up is grabbed
	# from BotGoals.PU_GRAB m)
	var grab := GOALS.PU_GRAB if str(_cur.get("kind", "")) == "powerup" else HOLD_GRAB
	if (d < grab and float(_cur.get("stand", 0.0)) <= 0.0 and str(_cur.get("kind", "")) != "special") or using:
		_hold = false
		return
	var hurt := hp_frac() < HOLD_HURT
	if not _hold:
		if _near_n >= HOLD_CROWD or _dpush > HOLD_DANGER or (hurt and _nearest < legs.flee_d):
			_hold = true
			_hold_t = 0.0
		return
	_hold_t += dt
	if _hold_t >= HOLD_MIN and _near_n < HOLD_CROWD_OUT and _dpush < HOLD_DANGER_OUT and not (hurt and _nearest < legs.flee_d):
		_hold = false


## The musts of pass 77 (they win over every goal): the boss's chest, then the portal, then back to a living boss.
func _must_goal() -> Dictionary:
	var me: Vector3 = game.player.global_position
	var pk = game.pickups
	if pk:
		for c in pk.chests:
			if is_instance_valid(c) and bool(c.boss) and not bool(c.opened):
				return {"key": "chest:%d" % c.get_instance_id(), "at": c.global_position, "must": true, "what": "boss_chest"}
	var portal = game.portal
	# pass 87: only a bot told to extract walks to the portal
	if portal != null and is_instance_valid(portal) and str(opts.get("portal", "endless")) == "extract":
		var pp: Vector3 = (portal as Node3D).global_position
		if not bool(portal.get("armed")):
			var out := Vector3(me.x - pp.x, 0.0, me.z - pp.z)
			if out.length() < 0.1:
				out = Vector3(1.0, 0.0, 0.0)
			return {"key": "portal:%d" % portal.get_instance_id(), "at": pp + out.normalized() * PORTAL_OUT, "must": true, "what": "portal"}
		return {"key": "portal:%d" % portal.get_instance_id(), "at": pp, "must": true, "what": "portal"}
	var boss := _boss_at()
	var bg := boss_goal(me, boss if str(opts["boss"]) == "leash" else Vector3.INF, _boss_back)
	_boss_back = not bg.is_empty()
	return bg


## A new plan: BotGoals' candidates; the goal held stays unless the best beats it SWITCH_K times (or it is no candidate
## any more: out of reach now); nothing under U_MIN; a new goal is a decision entry with the runner-up.
func _replan(now: float) -> void:
	var me: Vector3 = game.player.global_position
	var pk = game.pickups
	var lying := Vector2.ZERO
	var c := {"me": me, "t": now, "hp_frac": hp_frac(), "danger": danger(), "style": str(opts["style"]), "opts": opts,
		"boss": _boss_at(), "leash": str(opts["boss"]) == "leash", "lure_s": _lure_s, "lure_at": _lure_at,
		"xp_need": float(_run.xp_to_next()) if _run else 1.0, "held_key": str(_cur.get("key", "")), "crowd": _crowd_near}
	# (pass 85: the XP lying also prices a vacuum power-up in sight)
	if pk != null and (_uber_standing() or _vacuum_lying(pk, me)):
		lying = xp_lying(game)
	c["xp_lying"] = lying.x
	var cands: Array = planner.candidates(game, _run, c)
	if cands.is_empty():
		if not _cur.is_empty():
			_cur = {}
			goal = {}
		return
	var best: Dictionary = cands[0]
	if not _cur.is_empty():
		var held := {}
		for cd in cands:
			if str(cd["key"]) == str(_cur["key"]):
				held = cd
				break
		if not held.is_empty():
			_cur["u"] = float(held["u"])
			_cur["at"] = held["at"]
			# a goal held is kept unless one SWITCH_K times better turns up; the sweep is no commitment
			# (pass 82: nor is a special's hunt: a heal or a chest that beats it takes over at once)
			var k := 1.0 if str(_cur["kind"]) in ["gems", "special"] else SWITCH_K
			if str(best["key"]) == str(_cur["key"]) or float(best["u"]) <= float(held["u"]) * k:
				return
	if float(best["u"]) < U_MIN:
		if not _cur.is_empty():
			_cur = {}
			goal = {}
		return
	_commit(best, cands[1] if cands.size() > 1 else {})


## Pass 85: whether a vacuum power-up lies within BotGoals.PU_SEE m of `me` (the XP lying is counted for it then).
static func _vacuum_lying(pk, me: Vector3) -> bool:
	for sp in pk.specials:
		if not is_instance_valid(sp) or bool(sp.taken) or sp.def == null or str(sp.def.effect_kind) != "vacuum":
			continue
		var at: Vector3 = (sp as Node3D).global_position
		if Vector2(at.x - me.x, at.z - me.z).length() <= GOALS.PU_SEE:
			return true
	return false


## Whether an Uber Magnet stands unused where he has seen it (only then is the XP lying counted for it).
func _uber_standing() -> bool:
	var sm = game.get("structures")
	if sm == null:
		return false
	for s in sm.items:
		if is_instance_valid(s) and not bool(s.used) and s.def != null and str(s.def.effect_kind) == "vacuum_all" and planner.seen_struct.has(s.get_instance_id()):
			return true
	return false


## The goal taken: held with its patience; bot.goal shows it; a decision entry (what, why, the runner-up).
func _commit(best: Dictionary, runner: Dictionary) -> void:
	var was_kind := str(_cur.get("kind", _last_kind))
	_last_kind = ""
	_cur = best.duplicate()
	_cur["t"] = 0.0
	_cur["patience"] = PATIENCE_BASE + float(best["d"]) * PATIENCE_PER_M + float(best.get("interact", 0.0)) + float(best.get("fight", 0.0))
	_hold = false
	if str(best["kind"]) == "special":
		_cur["hunt_t"] = 0.0
		var em = game.get("enemies") if game != null else null
		_cur["chests0"] = int(em.get("special_chests")) if em != null and em.get("special_chests") != null else 0
	var kind := str(best["kind"])
	goals_by[kind] = int(goals_by.get(kind, 0)) + 1
	goal = {"what": str(best["what"]), "key": str(best["key"]), "at": best["at"], "why": str(best["why"]), "name": str(best.get("name", ""))}
	# the sweep after nothing, and one cell after another while exploring, are no new decision
	if (kind == "gems" and (was_kind == "" or was_kind == "gems")) or (kind == "explore" and was_kind == "explore"):
		return
	var ru := ""
	if not runner.is_empty():
		ru = "%s (%s, %d)" % [str(runner["what"]), str(runner["why"]), roundi(float(runner["u"]))]
	_decide("goal", [{"id": str(best["key"]), "name": str(best["what"]), "score": snappedf(float(best["u"]), 0.1),
		"parts": {"value": snappedf(float(best["value"]), 0.1), "dist": snappedf(float(best["d"]), 0.1)}}], str(best["key"]),
		"%s (%d m)" % [str(best["why"]), roundi(float(best["d"]))], {"what": str(best["what"]), "runner_up": ru})


## Whether the goal held is done: its structure used, its barrel broken, its power-up taken, its chest opened, its cell
## seen (or the thing gone).
func _goal_done(g: Dictionary) -> bool:
	match str(g["kind"]):
		"totem", "structure", "chest", "powerup":
			var o = instance_from_id(int(g.get("ref", 0)))
			if o == null or not is_instance_valid(o):
				return true
			if o.get("used") != null:
				return bool(o.used)
			if o.get("opened") != null:
				return bool(o.opened)
			if o.get("taken") != null:
				return bool(o.taken)
			return false
		"barrel":
			var bf = game.get("barrels")
			var i := int(g.get("index", -1))
			return bf == null or i < 0 or i >= bf.alive.size() or bf.alive[i] == 0
		"explore":
			var ci := int(g.get("cell", -1))
			return ci < 0 or ci >= planner.visited.size() or planner.visited[ci] == 1
		"special":
			var em = game.get("enemies")
			if not special_standing(em, int(g.get("index", -1)), int(g.get("serial", -1))):
				return true
			return special_in_reach(em, int(g["index"]), game.player.global_position)
	return false


## A goal reached: a structure used is a "structure" decision entry (what it gave is the next screen's, or its effect).
func _goal_finished(g: Dictionary) -> void:
	if str(g["kind"]) == "special":
		_special_found(g)
		return
	if str(g["kind"]) == "powerup":
		var pu = instance_from_id(int(g.get("ref", 0)))
		if pu != null and is_instance_valid(pu) and bool(pu.get("taken")):
			pu_reached += 1
		return
	if str(g["kind"]) in ["structure", "totem"]:
		var o = instance_from_id(int(g.get("ref", 0)))
		if o != null and is_instance_valid(o) and bool(o.get("used")):
			var nm := str(o.def.display_name) if o.def != null else str(g.get("sid", ""))
			_decide("structure", [{"id": str(g.get("sid", "")), "name": nm, "score": snappedf(float(g["u"]), 0.1), "parts": {"value": snappedf(float(g["value"]), 0.1)}}],
				str(g.get("sid", "")), "used the %s: %s" % [nm, str(g["why"])])


## The XP lying on the sand (gems at rest or bobbing, not on their way): x the whole map, y within 10 m of the hero.
static func xp_lying(g: Node) -> Vector2:
	if g == null or not is_instance_valid(g) or g.pickups == null or g.player == null:
		return Vector2.ZERO
	var pk = g.pickups
	var me: Vector3 = g.player.global_position
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


## The bot's tallies for the run sim's meta: the options, metres walked, goals chosen by kind, goals given up, decisions
## by kind, the share of the arena seen.
func summary() -> Dictionary:
	var by := {}
	var bought := 0
	var dealt := 0
	for e in decisions:
		var k := str(e.get("kind", ""))
		by[k] = int(by.get(k, 0)) + 1
		if k == "shop" and str(e.get("taken", "")) != "":
			bought += 1
		elif k == "stranger" and str(e.get("taken", "")) != "":
			dealt += 1
	var o := opts.duplicate()
	o.erase("t0")
	return {"opts": o, "metres": roundi(metres), "goals": goals_by.duplicate(), "gave_up": gave_up, "decisions": by,
		"seen": snappedf(planner.seen_share(), 0.01) if planner != null else 0.0, "shop_bought": bought, "stranger_taken": dealt,
		"specials": special_tallies(),
		# pass 85: the power-ups that lay on the map, the goals made of them, those walked to and taken
		"powerups": {"lying": pu_lying.size(), "goals": int(goals_by.get("powerup", 0)), "reached": pu_reached}}


## The goal shown (bot.goal) and, when it is a new one, a "goal" decision entry with why.
func _set_goal(g: Dictionary) -> void:
	if g.is_empty():
		goal = {}
		return
	var me: Vector3 = game.player.global_position
	var at: Vector3 = g["at"]
	var d := Vector2(at.x - me.x, at.z - me.z).length()
	var why := str(g.get("why", ""))
	if why == "":
		match str(g["what"]):
			"chest": why = "a chest %d m off" % roundi(d)
			"boss_chest": why = "the boss's chest"
			"portal": why = "the portal, the boss is down"
			"boss": why = "back to the boss (%d m off)" % roundi(d)
			_: why = str(g["what"])
	goal = {"what": str(g["what"]), "key": str(g["key"]), "at": at, "why": why}
	_decide("goal", [{"id": str(g["key"]), "name": str(g["what"]), "score": 1.0, "parts": {"dist": snappedf(d, 0.1)}}], str(g["key"]), why,
		{"what": str(g["what"]), "runner_up": str(g.get("runner_up", ""))})


## The goal now ({} = none): the boss's chest first, then the portal once no boss chest lies there, else the nearest
## chest within CHEST_RANGE not resting. {key, at, must, what}.
func _goal() -> Dictionary:
	var me: Vector3 = game.player.global_position
	var pk = game.pickups
	var near := {}
	var near_d := CHEST_RANGE
	var now := play_t()
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
			if not _within_leash(at, boss):
				continue
			var d := Vector2(at.x - me.x, at.z - me.z).length()
			if d < near_d:
				near_d = d
				near = {"key": key, "at": at, "must": false, "what": "chest"}
	var portal = game.portal
	# pass 87: only a bot told to extract walks to the portal
	if portal != null and is_instance_valid(portal) and str(opts.get("portal", "endless")) == "extract":
		var pp: Vector3 = (portal as Node3D).global_position
		if not bool(portal.get("armed")):
			# after a "Not yet" the portal asks again only once he has been out past its re-arm distance: out first
			var out := Vector3(me.x - pp.x, 0.0, me.z - pp.z)
			if out.length() < 0.1:
				out = Vector3(1.0, 0.0, 0.0)
			return {"key": "portal:%d" % portal.get_instance_id(), "at": pp + out.normalized() * PORTAL_OUT, "must": true, "what": "portal"}
		return {"key": "portal:%d" % portal.get_instance_id(), "at": pp, "must": true, "what": "portal"}
	# while a boss lives: back to it when he is too far off (BOSS_LEASH, BOSS_BACK)
	var bg := boss_goal(me, boss if str(opts["boss"]) == "leash" else Vector3.INF, _boss_back)
	_boss_back = not bg.is_empty()
	if not bg.is_empty():
		return bg
	return near


## The spot most worth walking to now (Vector3.INF for none). The gems, coins and vacuum gems lying past his magnet's
## reach within `stray` m (read off PickupManager's grid of resting pickups, GRID_CELL m cells) are summed cell by cell,
## and the cell with the most worth over (distance + LURE_NEAR)^LURE_POW wins, its worth-weighted middle the spot; a
## power-up on the ground within reach counts as a cell of POWERUP_WORTH (a heart only while he is under HEART_BELOW of
## his health; none with `powerups` off). Worth: a gem its XP, a coin COIN_WORTH a gold, a vacuum gem VACUUM_WORTH.
func _lure() -> Vector3:
	var pk = game.pickups
	if pk == null:
		return Vector3.INF
	var me: Vector3 = game.player.global_position
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
				if not _within_leash(at, boss):
					continue
				var d := Vector2(at.x - me.x, at.z - me.z).length()
				var s := sum / pow(d + LURE_NEAR, LURE_POW)
				if s > best_s:
					best_s = s
					best = at
	_lure_s = best_s
	if not bool(opts["powerups"]):
		return best
	_lure_s = best_s
	var p = game.player
	for sp in pk.specials:
		if not is_instance_valid(sp) or bool(sp.taken) or sp.def == null:
			continue
		if str(sp.def.effect_kind) == "heal" and float(p.hp) >= float(p.max_hp) * HEART_BELOW:
			continue
		var sat: Vector3 = (sp as Node3D).global_position
		if not _within_leash(sat, boss):
			continue
		var sd := Vector2(sat.x - me.x, sat.z - me.z).length()
		if sd > r:
			continue
		var ss := POWERUP_WORTH / pow(sd + LURE_NEAR, LURE_POW)
		if ss > best_s:
			best_s = ss
			best = sat
	_lure_s = best_s
	return best


## The boss's place while one lives (Vector3.INF for none).
func _boss_at() -> Vector3:
	var em = game.enemies if game else null
	if em == null:
		return Vector3.INF
	var bi: int = int(em.boss_index)
	if bi < 0 or bi >= em.alive.size() or em.alive[bi] != 1:
		return Vector3.INF
	return em.pos[bi]


## within_leash under the `boss` option: anywhere when it is "free".
func _within_leash(at: Vector3, boss: Vector3) -> bool:
	return str(opts["boss"]) != "leash" or within_leash(at, boss)


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
	var pk = game.pickups
	if pk == null:
		return false
	for c in pk.chests:
		if is_instance_valid(c) and bool(c.boss) and not bool(c.opened):
			return true
	return false


# ---------------------------------------------------------------- the specials (pass 82, lane WATCH)

## Whether the special in slot `i` with `serial` still stands (alive, the same creature, not dying) in the crowd `em`.
static func special_standing(em, i: int, serial: int) -> bool:
	if em == null or i < 0 or i >= int(em.MAX):
		return false
	return em.alive[i] == 1 and int(em.serial[i]) == serial and int(em.state[i]) != int(em.STATE_DYING)


## The hunted special's place now (its last known one once it is gone).
func _special_at(g: Dictionary) -> Vector3:
	var em = game.get("enemies")
	var i := int(g.get("index", -1))
	if special_standing(em, i, int(g.get("serial", -1))):
		return em.pos[i]
	return g["at"]


## Whether the special in slot `i` is in reach of the hero at `me`: within HUNT_NEAR m and on the screen (a crowd without
## an onscreen list counts it on the screen).
static func special_in_reach(em, i: int, me: Vector3) -> bool:
	var at: Vector3 = em.pos[i]
	if Vector2(at.x - me.x, at.z - me.z).length() > HUNT_NEAR:
		return false
	var os = em.get("onscreen")
	return not (os is PackedByteArray) or i >= (os as PackedByteArray).size() or (os as PackedByteArray)[i] == 1


## One frame of a hunt: the kite leans towards the special (never straight into it); the hunt's patience runs.
func _hunt_step(dt: float, _d: float) -> void:
	legs.steer_sweep(game, dt, _t, _cur["at"])
	_cur["t"] = float(_cur["t"]) + dt
	intent = "special"
	mode_frames[intent] = int(mode_frames.get(intent, 0)) + 1


## A hunt has ended: the special in reach ("found": a "special" decision entry, the weapons take it first now; its clock
## of being out of reach starts again), or down before that (with whether its death dropped a chest).
func _special_found(g: Dictionary) -> void:
	var em = game.get("enemies")
	var nm := str(g.get("name", "the special"))
	var sid := str(g.get("sid", ""))
	var hunt_s := float(g.get("hunt_t", 0.0))
	var row := [{"id": sid, "name": nm, "score": snappedf(float(g["u"]), 0.1), "parts": {"value": snappedf(float(g["value"]), 0.1),
		"hunt_s": snappedf(hunt_s, 0.1)}}]
	if special_standing(em, int(g.get("index", -1)), int(g.get("serial", -1))):
		specials_found += 1
		# the weapons have it: it is hunted again only once it has kept out of reach SPECIAL_WAIT s more (no find, lose,
		# find again every half second when it hovers at the screen's edge)
		if planner != null:
			planner.special_seen[str(g.get("key", ""))] = play_t()
		_decide("special", row, sid, "found the special %s after %d s: in reach, the weapons take it first" % [nm, roundi(hunt_s)])
		return
	specials_down += 1
	var dropped: bool = em != null and em.get("special_chests") != null and int(em.special_chests) > int(g.get("chests0", 0))
	_decide("special", row, sid, "the special %s is down after %d s of the hunt%s" % [nm, roundi(hunt_s), ", a chest dropped" if dropped else ""])


## The specials of the run (the run sim's meta.bot.specials): from the recorder's events the specials that came, those
## killed and the chests their deaths dropped, and `life_s`, the mean play seconds a special stood (the sum of the kills'
## times less the sum of the comings', a special still standing counted to now: no pairing needed, a special leaves the
## field only by dying); from the bot, the hunts (goals of kind special), those that brought it in reach (found), those
## that ended with it down before that, and those given up.
func special_tallies() -> Dictionary:
	var came := 0
	var killed := 0
	var chests := 0
	var t_in := 0.0
	var t_out := 0.0
	var ra := game.get_node_or_null("RunAnalytics") if game != null and is_instance_valid(game) else null
	var evs = ra.get("events") if ra != null else null
	if evs is Array:
		for e in evs:
			if not (e is Dictionary):
				continue
			var k := str(e.get("kind", ""))
			if k == "special":
				came += 1
				t_in += float(e.get("t", 0.0))
			elif k == "special_kill":
				killed += 1
				t_out += float(e.get("t", 0.0))
				if bool(e.get("chest", false)):
					chests += 1
	var life := (t_out + float(maxi(came - killed, 0)) * play_t() - t_in) / float(came) if came > 0 else 0.0
	return {"came": came, "killed": killed, "chests": chests, "life_s": snappedf(maxf(life, 0.0), 0.1), "hunted": int(goals_by.get("special", 0)),
		"found": specials_found, "hunted_down": specials_down, "gave_up": specials_gave_up}
