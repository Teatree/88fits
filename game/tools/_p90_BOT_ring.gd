## Pass 90 lane BOT scratch probe: the run sim's player (tools/sim_run.gd, every arg of its) with rings of creatures put
## round the hero at set play seconds, and what each ring cost him: HP lost and falls in the RING_WINDOW s after it came,
## the creatures of it still standing then, and the bot's breakouts. Extra args: ring_id= (lesser_scorpion), ring_n= (24),
## ring_r= (14), ring_from= (30), ring_every= (20), ring_count= (5), ring_size= (1.5), ring_window= (12).
## Writes <out>.ring.json beside the sim's own output. Played on the sim's snapshot (tools/dl/p90/BOT/ring_probe.py).
extends "res://tools/sim_run.gd"

var _ring_id := "lesser_scorpion"
var _ring_n := 24
var _ring_r := 14.0
var _ring_from := 30.0
var _ring_every := 20.0
var _ring_count := 5
var _ring_size := 1.5
var _ring_window := 12.0
var _ring_hp := 1.0
var _ring_dmg := 1.0
var _rings: Array = []
var _hp_last := -1.0
var _was_dead := false


func _init() -> void:
	super._init()
	for a in OS.get_cmdline_user_args():
		var i := a.find("=")
		if i <= 0:
			continue
		var k := a.substr(0, i)
		var v := a.substr(i + 1)
		match k:
			"ring_id": _ring_id = v
			"ring_n": _ring_n = int(v)
			"ring_r": _ring_r = float(v)
			"ring_from": _ring_from = float(v)
			"ring_every": _ring_every = float(v)
			"ring_count": _ring_count = int(v)
			"ring_size": _ring_size = float(v)
			"ring_window": _ring_window = float(v)
			"ring_hp": _ring_hp = float(v)
			"ring_dmg": _ring_dmg = float(v)


func _tick() -> void:
	super._tick()
	if _done or _game == null or not is_instance_valid(_game) or _game.player == null:
		return
	var pt := _play_t()
	var p = _game.player
	var hp := float(p.hp)
	var lost := 0.0
	if _hp_last >= 0.0 and hp < _hp_last:
		lost = _hp_last - hp
	_hp_last = hp
	var fell := bool(p.dead) and not _was_dead
	_was_dead = bool(p.dead)
	for r: Dictionary in _rings:
		if pt <= float(r["t"]) + _ring_window:
			r["lost"] = float(r["lost"]) + lost
			if fell:
				r["falls"] = int(r["falls"]) + 1
	# the next ring
	if _rings.size() < _ring_count and pt >= _ring_from + _ring_every * float(_rings.size()) and not bool(_game.paused) and not bool(p.dead):
		var em = _game.enemies
		var before := {}
		for i in range(int(em.MAX)):
			if em.alive[i] == 1:
				before[i] = int(em.serial[i])
		var came: int = em.spawn_ring(_ring_id, _ring_n, p.global_position, _ring_r, "", {"size": _ring_size, "hp_mult": _ring_hp, "damage_mult": _ring_dmg})
		var mine: Array = []
		for i in range(int(em.MAX)):
			if em.alive[i] == 1 and (not before.has(i) or int(before[i]) != int(em.serial[i])):
				mine.append([i, int(em.serial[i])])
		_rings.append({"t": pt, "came": came, "lost": 0.0, "falls": 0, "mine": mine, "left": -1, "hp0": hp, "level": int(_run.level),
			"bo0": int((_bot.breakout.tallies() as Dictionary)["started"]) if _bot != null and _bot.breakout != null else 0})
	for r: Dictionary in _rings:
		if not r.has("fr") and pt >= float(r["t"]) + 0.08 and _bot != null and _bot.breakout != null:
			var fr: Dictionary = _bot.breakout.fresh_ring(_bot._bo_bodies, _bot._bo_keys, p.global_position, float(_game.map.arena_radius))
			r["fr"] = {"n": int(fr["n"]), "gap": roundi(float(fr["gap_deg"])), "r": snappedf(float(fr["r"]), 0.1), "ring": bool(fr["ring"]),
				"active": bool(_bot.breakout.active), "cd": snappedf(float(_bot.breakout.cooldown), 0.1), "kind": str(_bot.breakout.kind)}
	for r: Dictionary in _rings:
		if int(r["left"]) < 0 and pt > float(r["t"]) + _ring_window:
			var em2 = _game.enemies
			var left := 0
			for m in r["mine"]:
				if em2.alive[int(m[0])] == 1 and int(em2.serial[int(m[0])]) == int(m[1]):
					left += 1
			r["left"] = left
			r["bo"] = (int((_bot.breakout.tallies() as Dictionary)["started"]) if _bot != null and _bot.breakout != null else 0) - int(r["bo0"])


func _finish(reason: String) -> void:
	var out: Array = []
	for r: Dictionary in _rings:
		out.append({"t": snappedf(float(r["t"]), 0.1), "came": int(r["came"]), "lost": roundi(float(r["lost"])), "falls": int(r["falls"]),
			"left": int(r["left"]), "hp0": roundi(float(r["hp0"])), "level": int(r["level"]), "bo": int(r.get("bo", -1)), "fr": r.get("fr", {})})
	var f := FileAccess.open(_out + ".ring.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"rings": out, "bot": _bot.summary() if _bot != null else {}}))
		f.close()
	super._finish(reason)
