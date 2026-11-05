## Pass 126 lane ITEMS: the proof that the Assayer's Scale's pay and the Canteen's heal replay (57.REPLAY): _p114_REPLAY_proof.gd
## with the items handed over at the first card screen (give=assayers_scale,canteen) and every later card screen and chest
## SKIPped by the recording's own path while skips last (the bot plays the rest): the replay must end with every checkpoint
## equal, the same number of pays and the same purse.
##   record: GODOT_TIMEOUT=400 bash tools/godot.sh --headless --path D:/_projects/88fits/game --script res://tools/_p126_ITEMS_replay.gd -- mode=record give=assayers_scale,canteen out=<f> hero=drifter stage=1 seed=7 limit=120 check=1 god=1
##   replay: GODOT_TIMEOUT=400 bash tools/godot.sh --headless --fixed-fps 64 --path D:/_projects/88fits/game --script res://tools/_p126_ITEMS_replay.gd -- mode=replay file=<f> out=<report.json>
## wade=1 (record only): the hero walks in and out of the nearest lake by the thumb while no screen is up (the bot plays only
## the screens), as BotLegs drives him, so the Canteen's stop and heal run in the replay on the same ticks; with god=1 and
## give=...,snake_oil the heal has somewhere to go (the overheal); the last line says what it healed. (Teleporting him from the
## tool parted the crowd for a tick: never a game rule.)
extends "res://tools/_p114_REPLAY_proof.gd"

var _pays := 0
var _heard := false
var _wade_on := "wade=1" in OS.get_cmdline_user_args()
var _wade_in := true
var _crossings := 0


func _hear() -> void:
	if _heard or _run == null:
		return
	_heard = true
	_run.skip_paid.connect(func(c: int, x: float) -> void:
		_pays += 1
		_say("  pay %d: +%d gold, +%.2f XP, level %d, purse %d, skips left %d" % [_pays, c, x, int(_run.level), int(_run.run_gold), int(_run.skips_left)]))


func _tick() -> void:
	_hear()
	super._tick()


func _give_once() -> void:
	super._give_once()
	if not _given or int(_run.passive_level("assayers_scale")) < 1 or int(_run.skips_left) <= 0:
		return
	var cs = _game.get("cards")
	# (the last skip is kept for a chest while the run has seen fewer than two pays' worth of time)
	if cs != null and cs.visible and not bool(cs.get("_picking")) and (int(_run.skips_left) >= 2 or float(_run.get("play_clock")) > _limit * 0.6):
		var dbg = cs.get("_debug")
		if dbg == null or not dbg.visible:
			cs._skip()
			return
	var ch = _game.get("chest_screen")
	if ch != null and ch.visible and not bool(ch.get("_spinning")) and (ch.get("buttons") as Control).visible and not ch.is_gold(ch.result()):
		ch._skip()


## The thumb, in and out of the lake (true while it steers: the bot is not ticked then; a screen up goes to the bot).
func _answer_down() -> bool:
	if super._answer_down():
		return true
	if not _wade_on or not _given or bool(_game.get("paused")) or int(_run.passive_level("canteen")) < 1:
		return false
	var pl = _game.player
	if pl.dead:
		return false
	var at := Vector2(pl.global_position.x, pl.global_position.z)
	# the nearest lake
	var c := Vector2.ZERO
	var r := 0.0
	var d := INF
	for l: Dictionary in _game.map.call("lakes"):
		var q: float = at.distance_to(l["center"]) - float(l["radius"])
		if q < d:
			d = q
			c = l["center"]
			r = l["radius"]
	d = at.distance_to(c)
	var was := _wade_in
	if d < r * 0.5:
		_wade_in = false
	elif d > r + 4.0:
		_wade_in = true
	if was != _wade_in:
		_crossings += 1
		_say("  %.1f s: turning %s, health %.1f, the Canteen's heal so far %.1f, %.1f s left of it" % [float(_run.get("play_clock")), "in" if _wade_in else "out", float(pl.hp), float(_run.healed_by_item.get("canteen", 0.0)), float(_run.canteen_left)])
	var to: Vector2 = (c - at if _wade_in else at - c).normalized()
	var inp = pl.input
	inp.wants_move = true
	inp.origin = Vector2(216, 500)
	inp.touch_pos = inp.origin + to * 120.0
	return true


func _sums() -> void:
	_say("pays %d, purse %d, level %d, canteen held %d, healed by it %.2f, kills %d" % [_pays, int(_run.run_gold), int(_run.level), int(_run.passive_level("canteen")), float(_run.healed_by_item.get("canteen", 0.0)), int(_run.kills)])


func _store_recording(rr: Node) -> void:
	_sums()
	super._store_recording(rr)


func _end_report(why: String) -> void:
	_sums()
	super._end_report(why)
