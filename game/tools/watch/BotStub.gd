## A stand-in for lane BOT's bot (pass 80, lane WATCH): the INTERFACES.md API (new(game, opts), tick(dt), intent, goal,
## decisions, signal decided) with the pass 77 run sim's behaviour in small: every screen answered as sim_run.gd
## answers it (the level cards by a sensible player's tier, a mutation offer at random, chests taken, the Stranger and
## the shop left, a Totem Pole's gift with the most feathers, the portal continued, Down! given up), the legs the
## kiting autopilot (tools/sim_pilot.gd). The Watch uses it only with bot=stub or when tools/bot/Bot.gd cannot load.
## Tools only; names no autoload (the Watch hands it the game).
extends RefCounted

signal decided(entry: Dictionary)

const PILOT_PATH := "res://tools/sim_pilot.gd"

var game: Node
var opts: Dictionary = {}
var intent := "kite"
var goal: Dictionary = {}
var decisions: Array = []

var _pilot
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _chest_tapped := false


func _init(p_game: Node, p_opts: Dictionary = {}) -> void:
	game = p_game
	opts = p_opts
	_rng.seed = hash([int(opts.get("seed", 1)), "bot"])
	var pilot_script = load(PILOT_PATH)
	if pilot_script != null:
		_pilot = pilot_script.new(hash([int(opts.get("seed", 1)), "pilot"]))


func tick(dt: float) -> void:
	_t += dt
	if game == null or not is_instance_valid(game):
		return
	if _screens():
		return
	if bool(game.get("paused")) or game.player == null or game.player.dead:
		return
	if _pilot != null:
		_pilot.steer_sweep(game, dt, _t, Vector3.INF)
		intent = "kite"


## One open screen answered (true when one was up).
func _screens() -> bool:
	var g := game
	if g.revive_screen and g.revive_screen.visible:
		intent = "down"
		g.revive_screen._decide("give_up")
		return true
	if g.portal_dialog and g.portal_dialog.visible:
		intent = "portal"
		g.portal_dialog.visible = false
		g.portal_dialog.decided.emit(false)
		return true
	var cs = g.cards
	if cs and cs.visible and not (cs._offer as Array).is_empty() and not cs._picking:
		if cs.banish_mode():
			cs._toggle_banish()
		var offer: Array = cs._offer
		var pick: Dictionary = {}
		if cs.path_mode:
			if cs.reel_running():
				cs.skip_reel()
			pick = offer[_rng.randi() % offer.size()]
			_log("mutation", offer, pick, "a mutation offer: taken at random (stand-in bot)")
		else:
			pick = _best(offer)
			_log("card", offer, pick, "the highest tier on the table (stand-in bot)")
		if not pick.is_empty():
			cs._pick(pick)
		return true
	var ch = g.chest_screen
	if ch and ch.visible:
		if ch._spinning:
			if not _chest_tapped:
				if ch.intro_playing():
					ch.skip_intro()
				else:
					_chest_tapped = true
			return true
		_chest_tapped = false
		ch._finish(true)
		return true
	_chest_tapped = false
	if g.resume_gate and g.resume_gate.visible:
		g.resume_gate.tap()
	if g.stranger_screen and g.stranger_screen.visible:
		g.stranger_screen._finish(false)
		return true
	if g.structure_shop and g.structure_shop.visible:
		g.structure_shop._finish(false)
		return true
	var ts = g.totem_screen
	if ts and ts.visible and not ts._done:
		var best = null
		for p in ts.planks():
			if best == null or int(p.feathers) > int(best.feathers):
				best = p
		if best != null:
			ts._pick(best)
		return true
	return false


func _best(offer: Array) -> Dictionary:
	var best := {}
	var bt := 99
	for c in offer:
		if c is Dictionary:
			var t := _tier(c)
			if t < bt:
				bt = t
				best = c
	return best


static func _tier(card: Dictionary) -> int:
	var type := str(card.get("type", ""))
	var d = card.get("def")
	if bool(card.get("evolve", false)) or type == "evolution" or (type == "weapon" and d != null and bool(d.get("is_evolution"))):
		return 0
	if bool(card.get("favourite", false)):
		return 1
	var fresh := bool(card.get("is_new", false))
	if type == "weapon":
		return 2 if fresh else 3
	if type == "perk":
		return 4
	if type == "passive":
		return 5 if fresh else 6
	return 8


func _log(kind: String, offer: Array, pick: Dictionary, why: String) -> void:
	var offered: Array = []
	for c in offer:
		if c is Dictionary:
			var d = c.get("def")
			offered.append({"id": str(c.get("id", "")), "name": str(d.get("display_name")) if d != null else str(c.get("id", "")),
				"score": float(9 - _tier(c)), "parts": {"tier": _tier(c)}})
	var run = game.get_node_or_null("/root/Run")
	var ra = game.get_node_or_null("RunAnalytics")
	var e := {"t": float(ra.get("play_t")) if ra else 0.0, "clock": float(run.get("elapsed")) if run else 0.0, "kind": kind,
		"offered": offered, "taken": str(pick.get("id", "")), "reason": why, "level": int(run.get("level")) if run else 0,
		"dps_before": 0.0}
	decisions.append(e)
	decided.emit(e)
