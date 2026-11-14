## Pass 150, lane ENDLESS: what a stage's Endless window brings, played. The Endless kite (tools/_p106_ENDLESS_kite.gd: the
## difficulty probe's builds, Trail argument and kiting autopilot, the outlaw never dies) from Endless's first second
## for `secs` seconds; every 10 s the crowd (alive, Max count, the cycle, elite-modded, specials, crowned Elites on the
## sand) and at the end what each window row brought (EndlessWindow.came_by) and each creature (the "spawn84 endless"
## lines the director prints headless).
##   bash tools/godot.sh --headless --fixed-fps 60 --path D:/_projects/88fits/game --log-file <f> \
##       --script res://tools/_p150_ENDLESS_probe.gd -- stage=0 t0=420 secs=250 level=30 build=b2 hero=drifter seed=11
## `old=1` plays the old Endless (the window switched off) for comparison.
extends "res://tools/_p106_ENDLESS_kite.gd"

var _old := false
var _win_samples: Array = []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2 and kv[0] == "old":
			_old = kv[1] == "1"
	super._init()
	_wave = 1


func _go_endless() -> void:
	if _old:
		var e = _game.director.timeline._stage_raw(_stage).get("endless_window")
		if e is Dictionary:
			e["enabled"] = false
	super._go_endless()
	var w = _game.director.endless_window
	print("endless: window %s, stage %d, cycle %.0f s, max %d (+%.1f a cycle), %d rows" % ["ON" if w.active else "off",
		_stage + 1, w.length, w.base_max, w.growth, w.rows.size()])


func _sample(ran: float) -> void:
	super._sample(ran)
	var em = _game.enemies
	var w = _game.director.endless_window
	var alive := 0
	var modded := 0
	var special := 0
	var crowned := 0
	for i in range(em.MAX):
		if not em.is_alive(i):
			continue
		alive += 1
		if em.elite_idx[i] >= 0:
			modded += 1
		if em.vspecial[i] == 1:
			special += 1
		var def = em.types[em.type_idx[i]]["def"]
		if def.archetype == "elite":
			crowned += 1
	print("endless:   t+%3d wave %2d cycle %d | alive %3d / max %3d | elite-modded %2d specials %d crowned %d | came %d" % [
		int(ran), _run.endless_wave(), w.cycle + 1, alive, w.cap_value() if w.active else _game.director.current_cap(), modded,
		special, crowned, w.came_total])
	if int(ran) % 60 == 0 and int(ran) > 0:
		_rows_line(w)


func _rows_line(w) -> void:
	var keys: Array = w.came_by.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append("%s=%d" % [str(k).get_slice(":", 1), int(w.came_by[k])])
	print("endless:   rows " + " ".join(parts))


func _speed_report() -> void:
	super._speed_report()
	for s: String in _win_samples:
		print(s)
	var w = _game.director.endless_window
	var keys: Array = w.came_by.keys()
	keys.sort()
	for k in keys:
		print("endless:   row %s brought %d" % [k, int(w.came_by[k])])
	print("endless: %d cycles begun, %d creatures from the window, %d chests opened by the pilot" % [w.cycles, w.came_total, _chests])
