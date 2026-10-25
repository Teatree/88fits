## Pass 106, lane ENDLESS (scratch): the difficulty probe (tools/difficulty_probe.gd, its builds, Mirror and kiting
## autopilot) dropped into Endless at wave `wave` after stage `stage`'s window: Endless starts, its first wave is cleared,
## the clock set just before wave `wave`, then `secs` seconds of Endless are played and reported as the probe does, plus
## how fast the crowd walks against the hero (the share of the live crowd faster than him, its median and top speed).
##   bash tools/godot.sh --headless --fixed-fps 60 --path game --script res://tools/_p106_ENDLESS_kite.gd -- wave=20 secs=60 \
##       stage=0 t0=400 level=22 build=b1 mirror=1.5 hero=drifter seed=11 [sg=0.015 smax=1.6]
## sg / smax play other speed_growth / speed_max (the pass 103 numbers: sg=0.015 smax=1.6). Bounded like the probe
## (its own frame clock) plus a 240 s watchdog.
extends "res://tools/difficulty_probe.gd"

var _wave := 20
var _sg := -1.0
var _smax := -1.0
var _e0 := 0.0
var _went := false
var _spd_samples: Array = []


func _init() -> void:
	super._init()
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"wave": _wave = int(kv[1])
			"sg": _sg = float(kv[1])
			"smax": _smax = float(kv[1])
	create_timer(240.0, true, false, true).timeout.connect(func(): print("kite: watchdog"); quit(3))


func _go_endless() -> void:
	var d = _game.director
	var tl = d.timeline
	if _sg >= 0.0:
		tl.endless["speed_growth"] = _sg
	if _smax >= 0.0:
		tl.endless["speed_max"] = _smax
	_run.elapsed = tl.stage_end(_stage)
	d.phase = d.Phase.PORTAL
	d.start_endless()
	_game.enemies.kill_all(false)
	var every: float = tl.endless_value("every", _stage)
	_run.endless_time = float(_wave - 1) * every - 0.02
	_e0 = _run.endless_time
	_went = true
	print("kite: endless after stage %d from wave %d, speed x%.3f at wave %d (growth %.3f, max %.2f)" % [_stage + 1, _wave,
		float(tl.endless_mults(_wave, _stage)["speed"]), _wave, tl.endless_value("speed_growth", _stage), tl.endless_value("speed_max", _stage)])


func _tick() -> void:
	var dt: float = root.get_process_delta_time()
	_t += dt
	if _game == null:
		var g = current_scene
		if g == null or not g.has_method("open_pause") or g.player == null:
			return
		_game = g
		_game.player.god = true
		if _game.get("damage_numbers") != null and _game.damage_numbers:
			_game.damage_numbers.suppressed = true
	_screens()
	if not _set and _t > 0.6 and not _run.weapons.is_empty():
		_setup()
	if not _set:
		return
	if not _went:
		_go_endless()
		_kills0 = int(_run.kills)
		_dmg0 = _total_dmg()
	_steer(dt)
	_track()
	var ran: float = _run.endless_time - _e0
	if ran >= _next_sample:
		_next_sample += 10.0
		_sample(ran)
		_speeds()
	if ran >= _secs or _t - _set_t > _secs * 3.0 + 60.0:
		_report(ran)
		_speed_report()
		quit(0)


## The live crowd's walk speeds against the hero's top speed now.
func _speeds() -> void:
	var em = _game.enemies
	var hero: float = _game.player.max_speed() if _game.player.has_method("max_speed") else 3.6
	var v: Array = []
	for i in range(em.MAX):
		if em.is_alive(i) and em.elite_idx[i] < 0 and i != em.boss_index:
			v.append(float(em.speed[i]))
	v.sort()
	if v.is_empty():
		return
	var faster := 0
	for s: float in v:
		if s > hero:
			faster += 1
	_spd_samples.append({"t": _run.endless_time - _e0, "wave": _run.endless_wave(), "hero": hero, "n": v.size(),
		"median": v[v.size() / 2], "top": v[v.size() - 1], "faster": float(faster) / float(v.size()), "live": em.endless_speed_live})


func _speed_report() -> void:
	for s: Dictionary in _spd_samples:
		print("kite:   t+%3d wave %d live x%.3f | hero %.2f m/s | crowd %d median %.2f top %.2f faster %.0f%%" % [int(s["t"]), int(s["wave"]),
			float(s["live"]), float(s["hero"]), int(s["n"]), float(s["median"]), float(s["top"]), 100.0 * float(s["faster"])])
