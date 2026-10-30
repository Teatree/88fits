## The bullet-heaven patterns (pass 113, lane BOSS; content/boss_attacks kind "pattern", BossAttackDef; Garry: "Each of
## the Bosses needs a Bullet Heaven type of attack ... rare and powerful ... more challenging for Player to damage the boss
## until the attack is done"; "don't trigger immediately, and are rare, something like once every 45s"; "easy to detect
## as a Player. Big foreshadowing"; "incorporated in a smart way so that they make sense with other attacks").
##
## EnemyManager owns one (made on first use) and calls it from three places: _update_attacks asks step() first (true = a
## pattern owns the creature this tick: the attack cycle waits), _update_boss calls tick() once a tick (the phases, the
## bullets, the hits, the drawing), damage() reads mult (the guard and the spent multipliers). The rules (BALANCING 56.BOSS):
##   - A pattern is never in the creature's attack cycle (EnemyManager.custom_resolved leaves it out); its `trigger`
##     schedules it on the creature's fight clock (seconds of its script running: the boss's fight from his arrival).
##   - It starts only between attacks: in STATE_MOVE, up out of the sand, not standing for a rain, not hidden, on the ground,
##     no stomp, tail beam, burrow, lit rain or custom shots of his still under way (is_free()).
##   - The tell (tell.seconds on the shot clock), the bullets (timing.duration), spent (spent.seconds): through all three he
##     is held in STATE_ATTACK with the runner's timer parked (EnemyManager.SNIPER_HELD), standing still (spent.still false
##     lets him walk while spent), his contact damage as ever; nothing else of his starts (step() returns true) and the
##     boss-fight window's rows wait (EnemyManager.pattern_holds, BossFightWindow).
##   - Guarded from the tell's start to the bullets' end: every hit on him x guard_mult (grey numbers, a grey spark, a grey
##     bar with GUARDED); spent: x spent_mult (the bar reads DAZED).
##   - After the spent seconds his cycle resumes after timing.cooldown (0: his cooldown_between); the next pattern is
##     trigger.cooldown seconds after this one ended: completely over, the tell, the bullets, their burn-out (inside the
##     spent seconds) and the spent seconds themselves (last_end is set in _end, at the end of the spent stretch).
##   - Pass 114 (lane EDITOR): trigger.first_after, first_by and cooldown may each be a range [min, max]: rolled from the
##     creature's own dice (a RandomNumberGenerator seeded from the run's seed, the creature's slot and serial; never
##     the global randf, so a replay rolls the same), first_after and first_by once per fight, the cooldown afresh at
##     every end (_rolls_of, _end; BossAttackDef.roll_triggers).
##   - A bullet hits the hero once for hit.hit_frac of his max HP (Player.take_damage: an evade, the shield and the blink
##     after a hit apply as for any hostile shot) and is gone; past projectile.range m from where the pattern stood it
##     shrinks away in FADE s; the ones still flying when the bullets end burn out over timing.clear s, harmless.
##   - Pass 115 (lane BOSS): a pattern with a `barrier` (BossAttackDef.barrier_on) begins only with the hero within its
##     reach (in_reach; due while he is out, it waits), raises its wall with the tell (_wall_up: the hero held inside it
##     through Player.fence_r, the crowd kept on its side, the bullets stopped at its inner face, BossBarrier its look)
##     and lets it fall as the bullets end (or with hold "spent" at the end) or whenever the pattern ends (_wall_down).
class_name BossPatterns
extends RefCounted

const TELL := 0
const FIRE := 1
const SPENT := 2
## seconds a bullet takes to grow out of the boss, and to shrink away past its range
const POP := 0.15
const FADE := 0.3
## a bullet starts this share of the boss's radius out from his middle, and flies this high over the ground (m)
const SPAWN_AT := 0.45
const LIFT := 1.0
## seconds between two fire sounds, two grey sparks on a guarded boss, two venom puddles
const SFX_GAP := 0.35
const SPARK_GAP := 0.09
const PUDDLE_GAP := 0.05
## the grey of a blocked hit's spark (the attack's guard.color when it names one)
const SPARK := Color(0.72, 0.76, 0.82)
## A run's bullets live in one PackedFloat32Array ("b"), B floats each: x, z, vx, vz, age, fade (> 0: shrinking away,
## harmless), seed, emitter. (One array: a packed array in a Dictionary is copied on its first write, so each function
## takes it out of the run, works on it and puts it back.)
const B := 8
const BX := 0
const BZ := 1
const BVX := 2
const BVZ := 3
const BAGE := 4
const BFADE := 5
const BSEED := 6
const BEMI := 7

var em: EnemyManager
## creature -> the pattern under way (begin .. _end)
var runs: Dictionary = {}
## creature -> {serial, fight (s), runs, last_end (fight s), rolls ({attack id: {first_after, first_by, cooldown}}),
## rng (its seeded dice, pass 114)}
var sched: Dictionary = {}
## creature -> what a hit on it is multiplied by now (guard_mult while guarded, spent_mult while spent)
var mult: Dictionary = {}
## a def's instance id -> [its attacks list, [[BossAttackDef, its entry], ...]]
var _lists: Dictionary = {}
var _spark_t := 0.0
var _puddle_t := 0.0
## for the tests, the probe and the report
var started := 0
var fired := 0
var hits := 0
var peak := 0
var ended := 0
var cancelled := 0
var last: Dictionary = {}
## pass 115 (lane BOSS): ticks a due pattern waited for the hero to come in reach; walls raised; creatures and hero moves
## the walls held back; bullets that vanished at a wall
var reach_waits := 0
var walls := 0
var wall_holds := 0
var wall_stops := 0
## the last wall raised (tests, the probe): {c, r, hero_limit, up}
var last_wall: Dictionary = {}
## microseconds the last tick took (Perf "boss.pattern" too)
var last_us := 0


func _init(p_em: EnemyManager) -> void:
	em = p_em


## The pattern entries of `def`'s boss.attacks list: [[BossAttackDef, its entry], ...] (kept while the list is the same).
func list_of(def: EnemyDef) -> Array:
	if def == null:
		return []
	var attacks: Array = def.boss.get("attacks", [])
	var key: int = def.get_instance_id()
	var got = _lists.get(key)
	if got is Array and is_same((got as Array)[0], attacks):
		return (got as Array)[1]
	var out: Array = []
	for a in attacks:
		if a is Dictionary:
			var cdef := em.custom_attack_of(str((a as Dictionary).get("name", "")))
			if cdef != null and cdef.is_pattern():
				out.append([cdef, a])
	_lists[key] = [attacks, out]
	return out


func running(i: int) -> bool:
	return runs.has(i)


## Whether any pattern is under way (the boss-fight window's rows wait for it).
func holds() -> bool:
	return not runs.is_empty()


## The phase of creature `i`'s pattern (TELL, FIRE, SPENT), -1 without one.
func phase_of(i: int) -> int:
	var r = runs.get(i)
	return int((r as Dictionary)["phase"]) if r is Dictionary else -1


func _sched_of(i: int) -> Dictionary:
	var s = sched.get(i)
	if s is Dictionary and int((s as Dictionary)["serial"]) == em.serial[i]:
		return s
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_base(), "boss_pattern", i, em.serial[i]])
	var fresh := {"serial": em.serial[i], "fight": 0.0, "runs": 0, "last_end": -1.0e9, "rolls": {}, "rng": rng}
	sched[i] = fresh
	return fresh


## Pass 114 (lane EDITOR): what the fight's dice are seeded from: the run's seed (Run.run_seed when lane REPLAY's is there,
## else the run sim's rng_seed, else the run's map_seed, which every run rolls or a tool forces), 1 without a Run.
static func seed_base() -> int:
	var loop = Engine.get_main_loop()
	var run = (loop as SceneTree).root.get_node_or_null("Run") if loop is SceneTree else null
	if run == null:
		return 1
	for k: String in ["run_seed", "rng_seed", "map_seed"]:
		var v = run.get(k)
		if (v is int or v is float) and int(v) != 0:
			return int(v)
	return 1


## Pass 114 (lane EDITOR): this fight's rolls of `cdef`'s trigger (first_after and first_by once per fight, the cooldown
## again at every end), drawn the first time the attack is asked about.
func _rolls_of(s: Dictionary, cdef: BossAttackDef) -> Dictionary:
	var rolls: Dictionary = s["rolls"]
	var r = rolls.get(cdef.id)
	if r is Dictionary:
		return r
	var fresh := cdef.roll_triggers(s["rng"])
	fresh["def"] = cdef
	rolls[cdef.id] = fresh
	return fresh


## Creature `i`'s fight clock, runs and last end (tests, the probe): {} when it has none.
func schedule_of(i: int) -> Dictionary:
	var s = sched.get(i)
	return (s as Dictionary).duplicate() if s is Dictionary and int((s as Dictionary)["serial"]) == em.serial[i] else {}


## The runner's question each tick (EnemyManager._update_attacks): true while a pattern owns creature `i` (the cycle
## waits), or when one is due now and starts. Its fight clock runs here.
func step(i: int, def: EnemyDef, delta: float, ppos: Vector3) -> bool:
	var run = runs.get(i)
	if run is Dictionary and int((run as Dictionary)["serial"]) != em.serial[i]:
		_end(i, run, true)
		run = null
	var pl := list_of(def)
	if pl.is_empty() and run == null:
		return false
	var s := _sched_of(i)
	s["fight"] = float(s["fight"]) + delta
	if run is Dictionary:
		if int(run["phase"]) != SPENT or bool(run["still"]):
			em.vel[i] = Vector3.ZERO
			em.intent[i] = Vector3.ZERO
		return true
	if not is_free(i):
		return false
	var hpf: float = em.hp[i] / maxf(em.max_hp[i], 1.0)
	for e: Array in pl:
		var cdef: BossAttackDef = e[0]
		if cdef.pattern_due(float(s["fight"]), hpf, int(s["runs"]), float(s["last_end"]), _rolls_of(s, cdef)):
			# pass 115 (lane BOSS): THE REACH RULE: with a barrier it begins only with the hero within its reach; due while
			# he is out of it, it waits (its clock goes on, nothing is rolled again) and begins the tick he comes in
			if not in_reach(i, cdef, ppos):
				reach_waits += 1
				s["waiting"] = cdef.id
				continue
			s["waiting"] = ""
			begin(i, cdef, e[1], ppos)
			return true
	return false


## Pass 115: whether the hero at `ppos` is within pattern `cdef`'s reach of creature `i` (its barrier_reach(), flat; always
## true without a barrier).
func in_reach(i: int, cdef: BossAttackDef, ppos: Vector3) -> bool:
	var reach: float = cdef.barrier_reach()
	if reach == INF:
		return true
	var c: Vector3 = em.pos[i]
	var dx := ppos.x - c.x
	var dz := ppos.z - c.z
	return dx * dx + dz * dz <= reach * reach


## Whether creature `i` is between attacks: walking (STATE_MOVE), up out of the sand, not standing for a rain, not hidden
## or held, on the ground, not frozen or stunned, and nothing of its own still under way (a stomp, a tail beam, a burrow, a
## lit rain, custom shots in the air).
func is_free(i: int) -> bool:
	if em.alive[i] == 0 or em.state[i] != EnemyManager.STATE_MOVE:
		return false
	if em.rise_t[i] < 1.0 or em.hold_t[i] > 0.0 or em.hidden[i] == 1 or em.held[i] == 1 or em.lift_h[i] > 0.01:
		return false
	if em.freeze_t[i] > 0.0 or em.stun_t[i] > 0.0:
		return false
	if em._stomps.has(i) or em._tails.has(i) or em._burrows.has(i) or em._custom_lit.has(i):
		return false
	for r: Dictionary in em._custom_runs:
		if int(r.get("owner", -1)) == i:
			return false
	return true


## The pattern `cdef` starts for creature `i` (`entry` its list entry): the tell.
func begin(i: int, cdef: BossAttackDef, entry: Dictionary, ppos: Vector3) -> void:
	var look := cdef.text("projectile", "look")
	if not BossAttackFx.is_billboard(look):
		look = BossAttackFx.BILLBOARD_LOOKS[0]
	var tint := cdef.tint()
	var glow := cdef.num("projectile", "glow")
	var words: Array = [cdef.display_name.to_lower() if cdef.display_name != "" else cdef.id]
	var run := {"serial": em.serial[i], "def": cdef, "id": cdef.id, "entry": entry, "phase": TELL, "t": 0.0,
		"tell": cdef.tell_seconds(), "dur": cdef.pattern_duration(), "spent": maxf(cdef.num("spent", "seconds"), 0.0),
		"still": cdef.flag("spent", "still"), "clear": maxf(cdef.num("timing", "clear"), 0.0),
		"ems": cdef.emitters_full(), "acc": PackedFloat32Array(), "was": PackedByteArray(), "aims": PackedFloat32Array(),
		"pull_on": PackedByteArray(), "pull_v": PackedFloat32Array(), "aim": 0.0, "c0": em.pos[i],
		"look": look, "tint": tint, "glow": glow, "wobble": cdef.num("projectile", "wobble"), "trail": cdef.flag("projectile", "trail"),
		"key": BossAttackFx.pool_key(look, tint, glow) + "|pattern",
		"radius": BossAttackFx.bb_radius(look) * maxf(cdef.num("projectile", "size"), 0.05),
		"range": cdef.bullet_reach(), "hit_r": maxf(cdef.num("projectile", "hit_radius"), 0.05),
		"hit_frac": maxf(cdef.num("hit", "hit_frac"), 0.0), "info": em.hit_info(i, "ranged", words),
		"n": 0, "b": PackedFloat32Array(), "buf": PackedFloat32Array(), "volleys": 0, "fired": 0, "hits": 0, "peak": 0, "sfx_at": -10.0, "glow0": em.vglow[i],
		"fxn": null, "flip_t": 0.0}
	# (sized here and put in: a packed array taken out of a Dictionary is a copy once written)
	var ne: int = (run["ems"] as Array).size()
	for nm: String in ["acc", "aims", "pull_v"]:
		var f := PackedFloat32Array()
		f.resize(ne)
		run[nm] = f
	for nm: String in ["was", "pull_on"]:
		var by := PackedByteArray()
		by.resize(ne)
		run[nm] = by
	runs[i] = run
	em.state[i] = EnemyManager.STATE_ATTACK
	em.timer[i] = EnemyManager.SNIPER_HELD
	em.vel[i] = Vector3.ZERO
	em.intent[i] = Vector3.ZERO
	mult[i] = cdef.guard_mult()
	# pass 115 (lane BOSS): the barrier rises with the tell, round where he stands (the hero inside it: the reach rule)
	if cdef.barrier_on():
		_wall_up(i, run, cdef, ppos)
	# his shell on his own painting: a rim in the shell's colour and a touch of it over him (the guard reads on him)
	var sc := BossAttackDef.color_of(cdef.text("shell", "color"), Color(0.8, 0.6, 0.4))
	em.vglow[i] = 1.0
	em.set_status_tint(i, Color(sc.r, sc.g, sc.b, 0.22), float(run["tell"]) + float(run["dur"]) + 0.5)
	started += 1
	last = {"id": cdef.id, "creature": i, "phase": "tell", "at": em.pos[i]}
	var g = em.game
	if g != null:
		var fxn := BossPatternFx.new()
		fxn.name = "BossPattern_" + cdef.id
		em.add_child(fxn)
		fxn.setup(g, cdef, em.pos[i], em.size[i], em.radius[i])
		run["fxn"] = fxn
		var hud = g.get("hud")
		if hud != null and hud.has_method("banner"):
			var words_up := cdef.text("tell", "banner")
			if words_up == "":
				words_up = cdef.display_name if cdef.display_name != "" else cdef.id
			# with the boss's badge: the banner then wears the attack's colour (HUD.banner colours a banner with an icon)
			var bdef: EnemyDef = em.types[em.type_idx[i]]["def"]
			var badge := "res://art/ui/badges/%s.png" % bdef.badge_for()
			var icon: Texture2D = load(badge) if ResourceLoader.exists(badge) else bdef.icon
			hud.banner(words_up.to_upper(), BossAttackDef.color_of(cdef.text("tell", "banner_color"), Color(0.91, 0.31, 0.16)), icon)
		_hud_guard(i, 1)
	var ws := cdef.text("sounds", "windup")
	if ws != "":
		Audio.play(ws, em.pos[i])
	var duck := cdef.num("tell", "duck_db")
	if duck < 0.0 and Audio.has_method("duck_music"):
		Audio.duck_music(duck, minf(float(run["tell"]) * 0.5, 0.6))


## Every pattern under way, once a tick (EnemyManager._update_boss): the clock, the phase, the boss's look, the bullets.
func tick(delta: float, ppos: Vector3) -> void:
	if runs.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var dc := delta * em.pace
	_spark_t -= delta
	_puddle_t -= delta
	for key in runs.keys():
		var i := int(key)
		var run: Dictionary = runs[key]
		if em.alive[i] == 0 or em.serial[i] != int(run["serial"]) or em.state[i] == EnemyManager.STATE_DYING:
			_end(i, run, true)
			continue
		var ph := int(run["phase"])
		if em.state[i] != EnemyManager.STATE_ATTACK and not (ph == SPENT and not bool(run["still"])):
			# something took him out of it (a stun or a launch: never a boss's): the pattern is called off
			_end(i, run, true)
			continue
		run["t"] = float(run["t"]) + dc
		var t := float(run["t"])
		var fxn = run["fxn"]
		var fx_ok: bool = fxn != null and is_instance_valid(fxn)
		if fx_ok:
			fxn.follow(em.pos[i])
		match ph:
			TELL:
				var tl := maxf(float(run["tell"]), 0.001)
				_pose(i, run, TELL, clampf(t / tl, 0.0, 1.0), delta)
				if fx_ok:
					fxn.tell(clampf(t / tl, 0.0, 1.0), delta)
				if t >= float(run["tell"]):
					run["t"] = t - float(run["tell"])
					_fire_begin(i, run, ppos)
			FIRE:
				_emit(i, run, dc, ppos)
				_pose(i, run, FIRE, clampf(t / float(run["dur"]), 0.0, 1.0), delta)
				if fx_ok:
					fxn.fire(clampf(t / float(run["dur"]), 0.0, 1.0), delta)
				if t >= float(run["dur"]):
					run["t"] = t - float(run["dur"])
					_spent_begin(i, run)
			SPENT:
				var sp := maxf(float(run["spent"]), 0.001)
				_pose(i, run, SPENT, clampf(t / sp, 0.0, 1.0), delta)
				if fx_ok:
					fxn.spent(clampf(t / sp, 0.0, 1.0), delta)
				if t >= float(run["spent"]):
					_bullets(i, run, dc, ppos)
					_end(i, run, false)
					continue
		_bullets(i, run, dc, ppos)
		_draw(i, run)
		# pass 115 (lane BOSS): the crowd kept on its side of the barrier
		_wall_hold_crowd(i, run)
	last_us = Time.get_ticks_usec() - t0
	Perf.add("boss.pattern", t0)


## The bullets begin: the aims are fixed now (hero: his way from the boss this moment; track and random are taken at each
## volley).
func _fire_begin(i: int, run: Dictionary, ppos: Vector3) -> void:
	run["phase"] = FIRE
	var c: Vector3 = em.pos[i]
	# (pass 115: with a barrier the bullets' reach is measured from the wall's middle, where he stood at the tell)
	var wall = run.get("wall")
	run["c0"] = (wall as Dictionary)["c"] if wall is Dictionary else c
	var aim := atan2(ppos.z - c.z, ppos.x - c.x)
	run["aim"] = aim
	var ems: Array = run["ems"]
	var aims: PackedFloat32Array = run["aims"]
	for k in range(ems.size()):
		match str((ems[k] as Dictionary)["aim"]):
			"fixed":
				aims[k] = 0.0
			"random":
				aims[k] = Dice.r.randf() * TAU
			_:
				aims[k] = aim
	run["aims"] = aims
	last["phase"] = "fire"
	var cdef: BossAttackDef = run["def"]
	var fs := cdef.text("sounds", "fire")
	if fs != "":
		Audio.play(fs, c)
	if em.game != null and em.game.get("camera"):
		em.game.camera.shake(0.8)


## The emitters' volleys this tick (each on its own clock: the first as it comes on, then one every 1 / rate).
func _emit(i: int, run: Dictionary, dc: float, ppos: Vector3) -> void:
	var cdef: BossAttackDef = run["def"]
	var t := float(run["t"])
	var dur := float(run["dur"])
	var ems: Array = run["ems"]
	var acc: PackedFloat32Array = run["acc"]
	var was: PackedByteArray = run["was"]
	var pull_on: PackedByteArray = run["pull_on"]
	var pull_v: PackedFloat32Array = run["pull_v"]
	var any := false
	for k in range(ems.size()):
		var e: Dictionary = ems[k]
		pull_on[k] = 1 if BossAttackDef.pulling(e, t, dur) else 0
		pull_v[k] = maxf(float(e["pull_speed"]), 0.1)
		var rate := float(e["rate"])
		var on := rate > 0.0 and BossAttackDef.emitter_on(e, t, dur)
		if on:
			acc[k] = 1.0 if was[k] == 0 else acc[k] + dc * rate
			while acc[k] >= 1.0:
				acc[k] -= 1.0
				_volley(i, run, k, e, t, ppos)
				any = true
		was[k] = 1 if on else 0
	run["acc"] = acc
	run["was"] = was
	run["pull_on"] = pull_on
	run["pull_v"] = pull_v
	var fs := cdef.text("sounds", "fire")
	if any and fs != "" and t - float(run["sfx_at"]) >= SFX_GAP:
		run["sfx_at"] = t
		Audio.play(fs, em.pos[i], -6.0)


## One volley of emitter `k` (BossAttackDef.volley) from the boss's middle.
func _volley(i: int, run: Dictionary, k: int, e: Dictionary, t: float, ppos: Vector3) -> void:
	var c: Vector3 = em.pos[i]
	var aim := float((run["aims"] as PackedFloat32Array)[k])
	match str(e["aim"]):
		"track":
			aim = atan2(ppos.z - c.z, ppos.x - c.x)
		"random":
			# a way of its own every volley (a ring's opening in a new place each time)
			aim = Dice.r.randf() * TAU
	var v := BossAttackDef.volley(e, t, float(run["dur"]), aim, Dice.r.randf())
	var r0: float = em.radius[i] * SPAWN_AT
	var b: PackedFloat32Array = run["b"]
	run["b"] = PackedFloat32Array()
	var n := int(run["n"])
	var add := int(float(v.size()) / 3.0)
	if (n + add) * B > b.size():
		b.resize(maxi(64, (n + add) * 2) * B)
	for j in range(0, v.size(), 3):
		var dx := cos(v[j])
		var dz := sin(v[j])
		var spd := v[j + 1]
		var across := v[j + 2]
		var o := n * B
		b[o + BX] = c.x + dx * r0 - dz * across
		b[o + BZ] = c.z + dz * r0 + dx * across
		b[o + BVX] = dx * spd
		b[o + BVZ] = dz * spd
		b[o + BAGE] = 0.0
		b[o + BFADE] = 0.0
		b[o + BSEED] = randf() * 63.0
		b[o + BEMI] = float(k)
		n += 1
	run["b"] = b
	run["n"] = n
	run["volleys"] = int(run["volleys"]) + 1
	run["fired"] = int(run["fired"]) + add
	fired += add


## The bullets this tick: they fly (a finale pull turns its emitter's home), a hit on the hero takes him `hit_frac` of his
## max HP and the bullet goes, past the range one shrinks away, a burning-out one shrinks.
func _bullets(i: int, run: Dictionary, dc: float, ppos: Vector3) -> void:
	var n := int(run["n"])
	if n <= 0:
		return
	var b: PackedFloat32Array = run["b"]
	run["b"] = PackedFloat32Array()
	var pull_on: PackedByteArray = run["pull_on"]
	var pull_v: PackedFloat32Array = run["pull_v"]
	var firing := int(run["phase"]) == FIRE
	var c: Vector3 = em.pos[i]
	var c0: Vector3 = run["c0"]
	var rng := float(run["range"])
	var rng2 := rng * rng
	var hr := float(run["hit_r"]) + BossAttackDef.PATTERN_HERO_R
	var hr2 := hr * hr
	var home2 := pow(maxf(em.radius[i] * 0.4, 0.4), 2.0)
	var pl = em.player
	var hero_ok: bool = pl != null and not bool(pl.get("dead"))
	var hx := ppos.x
	var hz := ppos.z
	var wall = run.get("wall")
	var wall_stop: bool = wall is Dictionary and bool((wall as Dictionary)["up"]) and bool((wall as Dictionary)["stop"])
	var k := 0
	while k < n:
		var o := k * B
		b[o + BAGE] += dc
		var gone := false
		var fd := b[o + BFADE]
		if fd > 0.0:
			fd -= dc
			b[o + BFADE] = fd
			gone = fd <= 0.0
		elif firing and pull_on[int(b[o + BEMI])] == 1:
			# the finale: straight home to the boss, gone when it reaches him
			var dxp := c.x - b[o + BX]
			var dzp := c.z - b[o + BZ]
			var l2 := dxp * dxp + dzp * dzp
			if l2 <= home2:
				gone = true
			else:
				var pv := pull_v[int(b[o + BEMI])] / sqrt(l2)
				b[o + BVX] = dxp * pv
				b[o + BVZ] = dzp * pv
		if not gone:
			var x := b[o + BX] + b[o + BVX] * dc
			var z := b[o + BZ] + b[o + BVZ] * dc
			b[o + BX] = x
			b[o + BZ] = z
			if fd <= 0.0:
				var ox := x - c0.x
				var oz := z - c0.z
				if ox * ox + oz * oz > rng2:
					b[o + BFADE] = FADE
					if wall_stop:
						# pass 115: it hits the barrier: it stops there and shrinks away, with a spark
						b[o + BVX] = 0.0
						b[o + BVZ] = 0.0
						wall_stops += 1
						_wall_spark(run, x, z, hx, hz)
					_puddle(run, x, z)
				elif hero_ok:
					var hx2 := x - hx
					var hz2 := z - hz
					if hx2 * hx2 + hz2 * hz2 <= hr2:
						_hit(i, run, Vector3(x, ppos.y, z))
						gone = true
		if gone:
			n -= 1
			if k != n:
				var last_o := n * B
				for f in range(B):
					b[o + f] = b[last_o + f]
			continue
		k += 1
	run["b"] = b
	run["n"] = n
	if n > int(run["peak"]):
		run["peak"] = n
	if n > peak:
		peak = n


## A bullet hits the hero: hit_frac of his max HP, the attack's name in the hit log (the Down! list), no push unless the
## attack names a knockback; a little splash in its colour.
func _hit(_i: int, run: Dictionary, at: Vector3) -> void:
	var pl = em.player
	var cdef: BossAttackDef = run["def"]
	var mhp = pl.get("max_hp")
	var amount: float = float(run["hit_frac"]) * (float(mhp) if mhp != null else 100.0)
	var info: Dictionary = (run["info"] as Dictionary).duplicate()
	info["knock"] = cdef.knockback
	info["special_knock"] = false
	pl.take_damage(amount, at, info)
	hits += 1
	run["hits"] = int(run["hits"]) + 1
	if em.game != null and em.game.get("fx"):
		em.game.fx.burst(at + Vector3(0, LIFT, 0), run["tint"], 0.7)


## A venom blob's little puddle where it shrinks away (visual only, fading in about 2 s), at most one every PUDDLE_GAP s.
func _puddle(run: Dictionary, x: float, z: float) -> void:
	if str(run["look"]) != "venom_blob" or em.game == null or _puddle_t > 0.0:
		return
	var tg = em.game.get("telegraphs")
	if tg == null or not tg.has_method("scorch"):
		return
	_puddle_t = PUDDLE_GAP
	var tint: Color = run["tint"]
	var at := Vector3(x, em._height(x, z), z)
	tg.scorch(at, float(run["radius"]) * 1.5, Color(tint.r * 0.8, tint.g * 0.6, tint.b * 0.9, 0.7), Color(tint.r, tint.g, tint.b, 0.0), 0.4, 1.6)


## The bullets drawn: one MultiMesh for the attack (BossAttackFx.bb_draw), its buffer kept with the run (the basis's
## zeros written once, as the buffer grows; each bullet's place, flight, seed and size every tick).
func _draw(_i: int, run: Dictionary) -> void:
	if em.game == null:
		return
	var fx: BossAttackFx = em._custom_fx_node()
	if not fx.has_ground() and not bool(run.get("ground_tried", false)):
		# the map's height grid, as Telegraphs keeps it, so each bullet rides over the dunes in the shader
		run["ground_tried"] = true
		var tg = em.game.get("telegraphs")
		if tg != null and tg.get("_heights") != null:
			fx.set_ground(tg.get("_heights"), int(tg.get("_grid_n")), float(tg.get("_half")), float(tg.get("_res")))
	var n := int(run["n"])
	var buf: PackedFloat32Array = run["buf"]
	run["buf"] = PackedFloat32Array()
	var stride := BossAttackFx.BB_STRIDE
	var r := float(run["radius"])
	if buf.size() < n * stride:
		var old := int(float(buf.size()) / float(stride))
		var cap := maxi(64, n * 2)
		buf.resize(cap * stride)
		for k in range(old, cap):
			var o := k * stride
			buf[o] = r
			buf[o + 1] = 0.0
			buf[o + 2] = 0.0
			buf[o + 4] = 0.0
			buf[o + 5] = r
			buf[o + 6] = 0.0
			buf[o + 8] = 0.0
			buf[o + 9] = 0.0
			buf[o + 10] = r
	var y := LIFT
	if not fx.has_ground():
		var c0: Vector3 = run["c0"]
		y = em._height(c0.x, c0.z) + LIFT
	var b: PackedFloat32Array = run["b"]
	var clear := maxf(float(run["clear"]), 0.05)
	var burning := int(run["phase"]) == SPENT
	for k in range(n):
		var o := k * stride
		var q := k * B
		buf[o + 3] = b[q + BX]
		buf[o + 7] = y
		buf[o + 11] = b[q + BZ]
		var bvx := b[q + BVX]
		var bvz := b[q + BVZ]
		var sp := sqrt(bvx * bvx + bvz * bvz)
		if sp > 0.0001:
			buf[o + 12] = bvx / sp
			buf[o + 13] = bvz / sp
		buf[o + 14] = b[q + BSEED]
		var sc := minf(b[q + BAGE] / POP, 1.0)
		var fd := b[q + BFADE]
		if fd > 0.0:
			sc = minf(sc, fd / (clear if burning else FADE))
		buf[o + 15] = sc
	run["buf"] = buf
	fx.bb_draw(str(run["key"]), str(run["look"]), run["tint"], float(run["glow"]), float(run["wobble"]), bool(run["trail"]), buf, n)


## The bullets end: he is spent (x spent_mult, DAZED on the bar), his shell goes, the bullets still flying burn out over
## timing.clear s (harmless), the music comes back; with spent.still false he walks while spent.
func _spent_begin(i: int, run: Dictionary) -> void:
	run["phase"] = SPENT
	var cdef: BossAttackDef = run["def"]
	mult[i] = cdef.spent_mult()
	em.vglow[i] = float(run["glow0"])
	em.set_status_tint(i, Color(0, 0, 0, 0), 0.0)
	var n := int(run["n"])
	var clear := float(run["clear"])
	if clear <= 0.0:
		run["n"] = 0
	else:
		var b: PackedFloat32Array = run["b"]
		run["b"] = PackedFloat32Array()
		for k in range(n):
			var fd := b[k * B + BFADE]
			b[k * B + BFADE] = clear if fd <= 0.0 else minf(fd, clear)
		run["b"] = b
	_hud_guard(i, 2)
	# pass 115 (lane BOSS): the barrier falls apart as the bullets end (barrier.hold "bullets"; "spent" keeps it up to
	# the end of his dazed seconds)
	if not cdef.barrier_holds_spent():
		_wall_down(run)
	if Audio.has_method("duck_music"):
		Audio.duck_music(0.0, 0.8)
	if not bool(run["still"]):
		em.state[i] = EnemyManager.STATE_MOVE
	last["phase"] = "spent"


## The pattern is over (or called off: `cut`): the bullets go, the look, the guard, the bar, the music; his cycle resumes
## after timing.cooldown (0: his cooldown_between); the next pattern's cooldown runs from now.
func _end(i: int, run: Dictionary, cut: bool) -> void:
	runs.erase(i)
	mult.erase(i)
	# pass 115 (lane BOSS): whatever ended it, the barrier lets the hero go and falls apart
	_wall_down(run)
	if em.game != null:
		var fx: BossAttackFx = em._custom_fx_node()
		fx.bb_clear(str(run["key"]))
	var fxn = run["fxn"]
	if fxn != null and is_instance_valid(fxn):
		fxn.finish()
	run["fxn"] = null
	if Audio.has_method("duck_music"):
		Audio.duck_music(0.0, 0.6)
	var same: bool = i >= 0 and i < em.pool_max and em.alive[i] == 1 and em.serial[i] == int(run["serial"])
	if same:
		em.vglow[i] = float(run["glow0"])
		if int(run["phase"]) != SPENT:
			em.set_status_tint(i, Color(0, 0, 0, 0), 0.0)
		if em.state[i] == EnemyManager.STATE_ATTACK:
			em.state[i] = EnemyManager.STATE_MOVE
		var cdef: BossAttackDef = run["def"]
		var def: EnemyDef = em.types[em.type_idx[i]]["def"]
		var rest := float(def.boss.get("cooldown_between", 2.0))
		if cdef.num("timing", "cooldown") > 0.0:
			rest = cdef.num("timing", "cooldown")
		em.atk_t[i] = maxf(em.atk_t[i], rest)
		em.squash[i] = 1.0
		var s := _sched_of(i)
		s["runs"] = int(s["runs"]) + 1
		# completely over now (the tell, the bullets, their burn-out, the spent seconds): the cooldown counts from here,
		# each attack's rolled afresh (pass 114)
		s["last_end"] = float(s["fight"])
		for rk in (s["rolls"] as Dictionary).keys():
			var rr: Dictionary = s["rolls"][rk]
			rr["cooldown"] = (rr["def"] as BossAttackDef).roll_trigger("cooldown", s["rng"])
		_hud_guard(i, 0)
	elif i == em.boss_index:
		_hud_guard(i, 0)
	if cut:
		cancelled += 1
	else:
		ended += 1
	last["phase"] = "cut" if cut else "over"
	last["fired"] = int(run["fired"])
	last["hits"] = int(run["hits"])
	last["peak"] = int(run["peak"])


## Everything let go at once (the run is over: EnemyManager's clear, a test's reset).
func clear_all() -> void:
	for key in runs.keys():
		_end(int(key), runs[key], true)
	sched.clear()
	mult.clear()


## The boss's own look through the pattern by tell.look: "spin" his painting flipping faster and faster (spinning up
## in his tornado) and dizzy while spent; "rear" rearing up taller through the tell and slumping while spent; "drive" up
## with the iron, then crouched as he drives it in, slumping while spent.
func _pose(i: int, run: Dictionary, ph: int, k: float, delta: float) -> void:
	var cdef: BossAttackDef = run["def"]
	match cdef.text("tell", "look"):
		"spin":
			if ph == SPENT:
				em.squash[i] = 0.92 + 0.05 * sin(float(run["t"]) * 9.0)
				return
			var hz := lerpf(1.5, 9.0, k) if ph == TELL else 7.0
			run["flip_t"] = float(run["flip_t"]) + delta * hz
			em.flip[i] = int(floor(float(run["flip_t"]))) % 2
			em.squash[i] = 1.0 + 0.04 * sin(float(run["flip_t"]) * PI)
		"rear":
			if ph == TELL:
				em.squash[i] = lerpf(1.0, 1.24, smoothstep(0.0, 0.8, k))
			elif ph == FIRE:
				em.squash[i] = 1.16 + 0.03 * sin(float(run["t"]) * 7.0)
			else:
				em.squash[i] = 0.84 + 0.04 * sin(float(run["t"]) * 6.0)
		"drive":
			if ph == TELL:
				em.squash[i] = lerpf(1.0, 1.14, smoothstep(0.0, 0.65, k)) if k < 0.7 else 0.8
			elif ph == FIRE:
				em.squash[i] = 1.0
			else:
				em.squash[i] = 0.9
		_:
			pass


## The boss's bar shows the guard (1: grey, GUARDED), the payoff (2: DAZED) or nothing (0); only the boss's.
func _hud_guard(i: int, mode: int) -> void:
	if i != em.boss_index or em.game == null:
		return
	var hud = em.game.get("hud")
	if hud != null and hud.has_method("set_boss_guard"):
		hud.set_boss_guard(mode)


## A hit on a guarded creature (EnemyManager.damage): a small grey spark, at most one every SPARK_GAP s.
func guard_spark(i: int) -> void:
	if _spark_t > 0.0 or em.game == null or em.game.get("fx") == null:
		return
	_spark_t = SPARK_GAP
	var run = runs.get(i)
	var col := SPARK
	if run is Dictionary:
		col = BossAttackDef.color_of((run["def"] as BossAttackDef).text("guard", "color"), SPARK)
	var at: Vector3 = em.pos[i] + Vector3(randf_range(-0.6, 0.6), em.size[i] * randf_range(0.4, 0.8), randf_range(-0.3, 0.3))
	em.game.fx.hit(at, col)


## Bullets of every pattern within `r` m of `at` (x, z, vx, vz each): the bot's danger (tools/bot/BotLegs.gd).
func bullets_near(at: Vector3, r: float) -> Array:
	var out: Array = []
	var r2 := r * r
	for key in runs.keys():
		var run: Dictionary = runs[key]
		var n := int(run["n"])
		var b: PackedFloat32Array = run["b"]
		for k in range(n):
			var o := k * B
			if b[o + BFADE] > 0.0:
				continue
			var dx := b[o + BX] - at.x
			var dz := b[o + BZ] - at.z
			if dx * dx + dz * dz <= r2:
				out.append([b[o + BX], b[o + BZ], b[o + BVX], b[o + BVZ]])
	return out


## How many bullets are in the air now (all patterns).
func bullet_count() -> int:
	var n := 0
	for key in runs.keys():
		n += int((runs[key] as Dictionary)["n"])
	return n


# ---------------------------------------------------------------- pass 115 (lane BOSS): the barrier

## Seconds between two sparks of bullets hitting a barrier, and how near the hero one must be to spark (m: on his screen).
const WALL_SPARK_GAP := 0.06
const WALL_SPARK_NEAR := 20.0


## The barrier goes up round where creature `i` stands (the tell's start): its rules live here (the hero held inside it
## through Player.fence_r, the crowd on its side, the bullets stopped at it), its look is a BossBarrier (made only when
## there is a game; the rules never need it). `ppos` is the hero's place: the rise starts on his side.
func _wall_up(i: int, run: Dictionary, cdef: BossAttackDef, ppos: Vector3) -> void:
	var c: Vector3 = em.pos[i]
	var side := PackedByteArray()
	side.resize(em.pool_max)
	var ser := PackedInt32Array()
	ser.resize(em.pool_max)
	ser.fill(-1)
	# every creature's side as it rises (one that comes later takes the side it is on then: _wall_hold_crowd)
	var r0 := cdef.barrier_radius()
	for j in range(em.pool_max):
		if em.alive[j] == 1:
			var pj: Vector3 = em.pos[j]
			ser[j] = em.serial[j]
			side[j] = 1 if Vector2(pj.x - c.x, pj.z - c.z).length() < r0 else 0
	var w := {"c": c, "r": r0, "half": cdef.barrier_half(), "hero_limit": cdef.barrier_hero_limit(),
		"up": true, "crowd": cdef.barrier_blocks_creatures(), "stop": cdef.barrier_stops_bullets(), "hero": null,
		"side": side, "ser": ser, "fx": null, "spark_t": 0.0, "boss": i}
	run["wall"] = w
	walls += 1
	var pl = em.player
	if cdef.barrier_blocks_hero() and pl != null and is_instance_valid(pl) and "fence_r" in pl:
		pl.set("fence_c", c)
		pl.set("fence_r", float(w["hero_limit"]))
		w["hero"] = weakref(pl)
	last_wall = {"id": cdef.id, "c": c, "r": float(w["r"]), "hero_limit": float(w["hero_limit"]), "up": true,
		"hero_at": ppos, "reach": cdef.barrier_reach()}
	if em.game != null:
		var node := BossBarrier.new()
		node.name = "BossBarrier_" + cdef.id
		em.add_child(node)
		node.setup(em.game, cdef, c, float(w["r"]), ppos)
		w["fx"] = node


## The barrier comes down (the bullets' end, the spent seconds' end, or the pattern called off): the hero let go (only
## if the hold on him is still this wall's), its look falls apart. Once.
func _wall_down(run: Dictionary) -> void:
	var w = run.get("wall")
	if not (w is Dictionary) or not bool((w as Dictionary)["up"]):
		return
	w["up"] = false
	var hr = w["hero"]
	if hr is WeakRef:
		var pl = (hr as WeakRef).get_ref()
		if pl != null and is_instance_valid(pl) and absf(float(pl.get("fence_r")) - float(w["hero_limit"])) < 0.0001:
			pl.set("fence_r", 0.0)
	var fx = w["fx"]
	if fx != null and is_instance_valid(fx):
		fx.fall()
	w["fx"] = null
	last_wall["up"] = false


## Whether creature `i`'s pattern has its barrier standing now (tests, the probe, the bot).
func wall_up(i: int) -> bool:
	var run = runs.get(i)
	if not (run is Dictionary):
		return false
	var w = (run as Dictionary).get("wall")
	return w is Dictionary and bool((w as Dictionary)["up"])


## The barrier standing now, if any: {c, r, half, hero_limit} (the first pattern's that has one), {} without.
func standing_wall() -> Dictionary:
	for key in runs.keys():
		var w = (runs[key] as Dictionary).get("wall")
		if w is Dictionary and bool((w as Dictionary)["up"]):
			return {"c": w["c"], "r": w["r"], "half": w["half"], "hero_limit": w["hero_limit"]}
	return {}


## Every creature but the boss kept on the side of the barrier it was on as it rose (a creature that arrives later takes
## the side it is on then): inside, its body never past the inner face; outside, never past the outer face. Its place
## only (its steering and its shoves go on: one pressing on the wall stays at it). The boss stands in the middle.
func _wall_hold_crowd(bi: int, run: Dictionary) -> void:
	var w = run.get("wall")
	if not (w is Dictionary) or not bool((w as Dictionary)["up"]) or not bool((w as Dictionary)["crowd"]):
		return
	var c: Vector3 = w["c"]
	var r := float(w["r"])
	var h := float(w["half"])
	var side: PackedByteArray = w["side"]
	var ser: PackedInt32Array = w["ser"]
	w["side"] = PackedByteArray()
	w["ser"] = PackedInt32Array()
	var al: PackedByteArray = em.alive
	var sr: PackedInt32Array = em.serial
	var rad: PackedFloat32Array = em.radius
	var st: PackedInt32Array = em.state
	var ps: PackedVector3Array = em.pos
	var n := mini(em.pool_max, side.size())
	for j in range(n):
		if al[j] == 0 or j == bi or st[j] == EnemyManager.STATE_DYING:
			continue
		var p: Vector3 = ps[j]
		var dx := p.x - c.x
		var dz := p.z - c.z
		var d := sqrt(dx * dx + dz * dz)
		if ser[j] != sr[j]:
			ser[j] = sr[j]
			side[j] = 1 if d < r else 0
		if side[j] == 1:
			var lim := maxf(r - h - rad[j], 0.0)
			if d > lim:
				em.pos[j] = BossAttackDef.keep_within(p, c, lim)
				wall_holds += 1
		else:
			var lim2 := r + h + rad[j]
			if d < lim2:
				em.pos[j] = BossAttackDef.keep_beyond(p, c, lim2)
				wall_holds += 1
	w["side"] = side
	w["ser"] = ser


## A bullet hits the barrier at (x, z): a small spark in its colour where the hero can see it, at most one every
## WALL_SPARK_GAP s (a look: the run's dice are never read).
func _wall_spark(run: Dictionary, x: float, z: float, hx: float, hz: float) -> void:
	if em.game == null or em.game.get("fx") == null:
		return
	var w: Dictionary = run["wall"]
	var now := Time.get_ticks_msec() * 0.001
	if now < float(w["spark_t"]):
		return
	if (x - hx) * (x - hx) + (z - hz) * (z - hz) > WALL_SPARK_NEAR * WALL_SPARK_NEAR:
		return
	w["spark_t"] = now + WALL_SPARK_GAP
	em.game.fx.hit(Vector3(x, em._height(x, z) + LIFT, z), run["tint"])
