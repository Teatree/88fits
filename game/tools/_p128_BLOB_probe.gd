## Pass 128, lane BLOB: does the crowd still trail a running outlaw as one blob? The difficulty probe's run (its
## sandboxed Save, its screens taken for him, the live director) with the outlaw standing `warm` seconds at the arena's
## west side while the stage's crowd gathers, then running in a straight line for `secs` seconds (east; at the far wall
## he turns round and runs straight back: the arena is about 39 s of the Drifter's run across, so the second leg starts
## then and is reported as leg 2). He is never hurt (god) and keeps his level-1 start weapon. Every 10 s of the run:
## the creatures within 30 m of him, the share of them in the rear 120 degrees (within 60 degrees of straight behind
## his heading; an even ring is 33%), in the front 120 degrees, beyond 16 m, their mean distance, how evenly they fill
## twelve sectors round him (the fullest sector's share; an even ring is 8%), and the relocations, the queue and the
## despawns so far. Run it once with relocate=0 and once with relocate=1 and compare the RESULT lines.
##   bash tools/godot.sh --headless --fixed-fps 60 --path game --script res://tools/_p128_BLOB_probe.gd --log-file <f> -- \
##       relocate=1 secs=60 warm=20 t0=200 stage=0 hero=drifter seed=11 [every=0.1] [far=2]
## Bounded: the probe's own frame clock, a 300 s watchdog (and GODOT_TIMEOUT on tools/godot.sh). Nothing reaches the disk
## (Save.begin_sandbox in the probe's _start).
extends "res://tools/difficulty_probe.gd"

const REACH := 30.0
const FAR := 16.0
const EDGE := 56.0

var _relocate := true
var _warm := 20.0
var _run_secs := 60.0
var _dir := Vector3(1, 0, 0)
var _leg := 1
var _rows: Array = []
## relocate keys played in place of the map's (every=, far=: the block's `seconds`), to read what a number changes
var _over: Dictionary = {}


func _init() -> void:
	_hero = "drifter"
	_t0 = 200.0
	super._init()
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"relocate": _relocate = kv[1] != "0"
			"warm": _warm = float(kv[1])
			"secs": _run_secs = float(kv[1])
			"every": _over["every"] = float(kv[1])
			"far": _over["seconds"] = float(kv[1])
	_secs = _warm + _run_secs
	create_timer(300.0, true, false, true).timeout.connect(func(): print("blob: watchdog"); quit(3))


## The run's dice from `seed` (Run.forced_run_seed: the same crowd, the same cards and the same kills in a relocate=0 and
## a relocate=1 run until the first relocation).
func _start() -> void:
	var run := root.get_node_or_null("Run")
	if run != null:
		run.forced_run_seed = _seed
	super._start()


## No build: the outlaw as a run starts him, at the stage clock `t0`, at the west side, unhurt; the map's relocation
## switched off for the run with relocate=0.
func _setup() -> void:
	_set = true
	_set_t = _t
	_run.stage = _stage
	_run.elapsed = _t0
	_run.kills = 1000
	var d = _game.director
	d.skip_events_before(_t0)
	var blk: Dictionary = d.timeline.relocate.duplicate()
	if not _relocate:
		blk["enabled"] = false
	blk.merge(_over, true)
	d.timeline.relocate = blk
	d.forget_sources()
	d._apply_mults()
	_game.enemies.kill_all(false)
	var p = _game.player
	var at := Vector3(-EDGE, 0, 0)
	if _game.map and _game.map.has_method("height_at"):
		at.y = _game.map.height_at(at.x, at.z)
	p.global_position = at
	p.god = true
	_last_hp = p.hp
	_kills0 = int(_run.kills)
	_dmg0 = _total_dmg()
	var c: Dictionary = d.timeline.relocate_cfg()
	var fs: Dictionary = d.timeline.far_speed_cfg()
	print("blob: hero %s stage %d t0 %.0f seed %d warm %.0f s run %.0f s | relocate %s %s | far_speed x%.1f cap %.1f m/s | his run %.2f m/s" % [
		_hero, _stage, _t0, _seed, _warm, _run_secs, "ON" if _relocate else "OFF", str(c), float(fs["max_mult"]), float(fs["max_speed"]),
		_run.player_sheet.get_stat("move_speed", 5.0) * _run.move_pace()])


## He stands through the warm-up, then runs straight: east, and back at the wall.
func _steer(_dt: float) -> void:
	var p: Node3D = _game.player
	var inp = p.input
	if inp == null or _game.paused:
		return
	if _run.elapsed - _t0 < _warm:
		inp.wants_move = false
		return
	if p.global_position.x > EDGE and _dir.x > 0.0:
		_dir = Vector3(-1, 0, 0)
		_leg += 1
	elif p.global_position.x < -EDGE and _dir.x < 0.0:
		_dir = Vector3(1, 0, 0)
		_leg += 1
	PILOT.push(inp, _dir)


func _sample(ran: float) -> void:
	var em = _game.enemies
	var me: Vector3 = _game.player.global_position
	var n := 0
	var rear := 0
	var front := 0
	var far := 0
	var sum_d := 0.0
	var sect := PackedInt32Array()
	sect.resize(12)
	for i in range(em.pool_max):
		if em.alive[i] == 0 or em.state[i] == em.STATE_DYING or em.hidden[i] == 1:
			continue
		var d: Vector3 = em.pos[i] - me
		d.y = 0.0
		var dist := d.length()
		if dist > REACH or dist < 0.01:
			continue
		n += 1
		sum_d += dist
		if dist > FAR:
			far += 1
		var c := d.dot(_dir) / dist
		if c <= -0.5:
			rear += 1
		elif c >= 0.5:
			front += 1
		sect[clampi(int(fposmod(atan2(d.z, d.x), TAU) / (TAU / 12.0)), 0, 11)] += 1
	var top := 0
	for s in sect:
		top = maxi(top, s)
	var rl = em.get("relocate")
	var row := {"t": ran - _warm, "leg": _leg if ran >= _warm else 0, "alive": int(em.count_alive), "n": n,
		"rear": float(rear) / maxf(n, 1), "front": float(front) / maxf(n, 1), "far": float(far) / maxf(n, 1),
		"mean_d": sum_d / maxf(n, 1), "top": float(top) / maxf(n, 1), "relocated": int(rl.relocated) if rl != null else 0,
		"queue": int(rl.queue.size()) if rl != null else 0, "despawned": int(em.despawned), "x": me.x}
	_rows.append(row)
	print("blob: t=%3.0f leg %d x %6.1f | alive %3d within 30 m %3d | rear120 %5.1f%% front120 %5.1f%% | beyond 16 m %5.1f%% mean %4.1f m | fullest sector %5.1f%% | relocated %3d queue %2d despawned %3d" % [
		row["t"], row["leg"], row["x"], row["alive"], row["n"], row["rear"] * 100.0, row["front"] * 100.0, row["far"] * 100.0, row["mean_d"], row["top"] * 100.0,
		row["relocated"], row["queue"], row["despawned"]])


func _report(ran: float) -> void:
	var em = _game.enemies
	var rl = em.get("relocate")
	var all_rear := 0.0
	var all_n := 0
	var leg1_rear := 0.0
	var leg1_n := 0
	var top := 0.0
	var alive := 0.0
	for r: Dictionary in _rows:
		# the samples while he runs (the one at the run's first second is still the warm-up's ring)
		if float(r["t"]) < 9.0:
			continue
		all_rear += float(r["rear"])
		top += float(r["top"])
		alive += float(r["n"])
		all_n += 1
		if int(r["leg"]) == 1:
			leg1_rear += float(r["rear"])
			leg1_n += 1
	print("blob: RESULT relocate=%s secs=%.0f seed=%d | rear120 mean %.1f%% over %d samples (leg 1: %.1f%% over %d) | fullest sector mean %.1f%% | within 30 m mean %.0f | relocated %d (queued %d, dropped %d) | despawned %d | kills %d" % [
		"on" if _relocate else "off", ran - _warm, _seed, all_rear / maxf(all_n, 1) * 100.0, all_n, leg1_rear / maxf(leg1_n, 1) * 100.0, leg1_n,
		top / maxf(all_n, 1) * 100.0, alive / maxf(all_n, 1), int(rl.relocated) if rl != null else 0, int(rl.queued_total) if rl != null else 0,
		int(rl.dropped) if rl != null else 0, int(em.despawned), int(_run.kills) - _kills0])
	if rl != null:
		print("blob: relocated by creature %s" % str(rl.relocated_by))
