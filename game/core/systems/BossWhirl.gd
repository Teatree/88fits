## Pass 126 (lane BOSS; Garry: "A new Boss is needed of course. Try looking at our other Bosses critically and coming up with
## something that is very similar, but has a unique twist to it"): the built-in attack `whirl`, Black Sunday's signature
## and any scripted creature's. Every other boss's signature is something you only run from and that only helps the boss;
## this one hurts his own crowd, and he pays for it afterwards (BALANCING 68.BOSS).
##
## A row of `boss.attacks`: {"name": "whirl", "windup": 1.4, "telegraph": "ring", "radius": 5, ...}; DEFAULTS fill what it
## leaves out (tools/level_editor/vocab.py ATTACKS mirrors the table, selftest_BOSS126.py checks they agree):
##   radius        metres round him that a creature is taken; the hero is thrown within radius + DustDevils.HERO_REACH.
##   seconds       how long he is the storm, real seconds (never stretched by the pace knob: Garry reads what the row says).
##   speed         metres a second he hunts at, before the pace knob, as a roll's `speed` (3.2 x 0.81 = 2.6 m/s, 72% of a
##                 fresh hero's 3.6), turning towards the hero at most `turn` degrees a second.
##   damage        the hit on each toss (x stage x level x host, as every boss attack); `toss` {up, out, cooldown}: the
##                 throw (Player.launch, as a dust devil's; the Dust Bowl's tornado's 13.4 up and 7.2 out: 1.07 m across
##                 against a plain one's 0.53) and the least seconds between two tosses. An
##                 evade, the Invincibility bubble or May's box leaves him standing. No bite while he spins: the toss is
##                 the only harm his body does then.
##   lift, lift_height  the seconds a creature rides and how high (EnemyManager.lift_radius), `fling` how far it is
##                 flung (EnemyManager.swirl: 1 = a plain dust devil's, it comes down 1.1 radii past the grab, 2 twice
##                 that), `landing_damage` the share of its max HP the fall takes (`landing_damage_big` for an Elite, a
##                 coloured special or anything big). Nothing here is credited to a weapon, so nothing feeds lifesteal; a
##                 creature that dies drops what it drops.
##   dazed         {seconds, damage_taken}: he stumbles out and stands, hits on him x damage_taken (BossPatterns.mult, the
##                 bar says DAZED, stars, a warm tint); his bite as ever.
##   look          the funnel and the ground under it, drawn by BossPatternFx from a def made here (look_def); `rim` and
##                 `rim_color` a glowing line round his painting while he spins (the special's rim): black on brown dust
##                 is what he is, and through the funnel he needs it to stay seen.
##   sound         the loop while he spins; end_sound as he stumbles out.
## Wind-up: the runner's as any attack's (his painting flips faster and faster, the shell rising). While he spins his body
## stays a target and takes normal hits: he is never hidden and never lifted. He runs in the script (bosses are never handed
## to the compiled crowd). No dice: every rule follows the physics tick, so a replay plays the same; the look may roll its
## own (BossPatternFx's camera shakes roll Dice.r, as a pattern's).
class_name BossWhirl
extends RefCounted

const TELL := 0
const SPIN := 1
const DAZED := 2
const DEFAULTS := {
	"radius": 5.0, "seconds": 6.0, "speed": 3.2, "turn": 150.0, "damage": 26.0,
	"toss": {"up": 13.4, "out": 7.2, "cooldown": 1.6},
	"lift": 1.7, "lift_height": 4.5, "fling": 2.0, "landing_damage": 0.75, "landing_damage_big": 0.12,
	"dazed": {"seconds": 2.5, "damage_taken": 1.5},
	"look": {"color": "#8A6C4A", "height": 9.0, "funnel": 2.6, "opacity": 0.5, "skirt_opacity": 0.6, "flip_hz": 7.0, "hover": 0.35,
		"rim": 1.0, "rim_color": "#F2C468", "ring_color": "#17100A", "ring_alpha": 0.42, "edge_color": "#E0A63A", "dazed_tint": "#E0A63A", "shake": 0.8},
	"sound": "wd_dust_devil", "end_sound": "en_boulder_land",
}
## Keys of the row that are groups (config_of merges them key by key).
const GROUPS := ["toss", "dazed", "look"]

## The storm's loop while the game is paused or the scene goes (the Audio autoload plays through a pause): off, and on again
## as the pause ends.
class SoundGuard extends Node:
	var id := ""

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PAUSED:
			Audio.stop_loop(id)
		elif what == NOTIFICATION_UNPAUSED:
			Audio.play_loop(id)

	func _exit_tree() -> void:
		Audio.stop_loop(id)


var em: EnemyManager
## creature -> the whirl under way {serial, cfg, phase, t, heading, cd, flip_t, windup, fxn, ride}
var runs: Dictionary = {}
## for the tests, the probe and the report: whirls begun, tosses (hits that threw him), creatures taken, tosses a dodge or
## a bubble stopped, whirls that ended whole, whirls cut, seconds dazed so far
var started := 0
var tosses := 0
var lifted := 0
var saved := 0
var ended := 0
var cut := 0
var last: Dictionary = {}


func _init(p_em: EnemyManager) -> void:
	em = p_em


## A row with every default filled in (DEFAULTS; the groups key by key).
static func config_of(atk: Dictionary) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	for k in atk.keys():
		if k in GROUPS and atk[k] is Dictionary:
			for gk in (atk[k] as Dictionary).keys():
				out[k][gk] = (atk[k] as Dictionary)[gk]
		elif out.has(k):
			out[k] = atk[k]
	return out


## Metres from his middle the hero is thrown within (the ring on the ground).
static func reach_of(cfg: Dictionary) -> float:
	return float(cfg["radius"]) + DustDevils.HERO_REACH


## How he looks through it, as a pattern's look (BossPatternFx: the dark ground, the ring, the funnel, the stars).
static func look_def(cfg: Dictionary) -> BossAttackDef:
	var lk: Dictionary = cfg["look"]
	var d := BossAttackDef.new()
	d.id = "whirl"
	d.attack_kind = "pattern"
	d.tell = {"look": "spin", "ring_radius": reach_of(cfg), "ring_color": lk["ring_color"], "ring_alpha": lk["ring_alpha"],
		"banner_color": lk["edge_color"]}
	d.shell = {"look": "tornado", "color": lk["color"], "height": lk["height"], "radius": lk["funnel"], "opacity": lk["opacity"]}
	return d


func running(i: int) -> bool:
	return runs.has(i)


## The phase of creature `i`'s whirl (TELL, SPIN, DAZED), -1 without one.
func phase_of(i: int) -> int:
	var r = runs.get(i)
	return int((r as Dictionary)["phase"]) if r is Dictionary else -1


## The wind-up starts (the runner has set its timer and drawn its ring): the shell begins to rise round him.
func wind_up(i: int, atk: Dictionary, _ppos: Vector3) -> void:
	var cfg := config_of(atk)
	var run := {"serial": em.serial[i], "cfg": cfg, "phase": TELL, "t": 0.0, "heading": em.charge_dir[i], "cd": 0.0, "flip_t": 0.0,
		"windup": maxf(em.timer[i], 0.05), "fxn": null, "ride": {"land": float(cfg["landing_damage"]), "land_big": float(cfg["landing_damage_big"])},
		"glow0": em.vglow[i]}
	if runs.has(i):
		_end(i, runs[i], true)
	runs[i] = run
	if em.game != null:
		var fxn := BossPatternFx.new()
		fxn.name = "BossWhirl"
		em.add_child(fxn)
		fxn.setup(em.game, look_def(cfg), em.pos[i], em.size[i], em.radius[i])
		var tornado = fxn.get_node_or_null("Tornado")
		if tornado != null:
			# the dust round his foot reaches nearly to his grab, as a dust devil's: the cloud is what grabs
			tornado.set("skirt_radius", float(cfg["radius"]) * 0.92)
			tornado.set("skirt_opacity", float((cfg["look"] as Dictionary)["skirt_opacity"]))
		run["fxn"] = fxn


## The wind-up is over (the runner's fire step): he is the storm now.
func begin(i: int, atk: Dictionary, _ppos: Vector3) -> void:
	var run = runs.get(i)
	if not (run is Dictionary):
		wind_up(i, atk, _ppos)
		run = runs[i]
	run["phase"] = SPIN
	run["t"] = 0.0
	em.state[i] = EnemyManager.STATE_ATTACK
	em.timer[i] = EnemyManager.SNIPER_HELD
	em.vel[i] = Vector3.ZERO
	em.intent[i] = Vector3.ZERO
	# no bite from the first tick on (_spin holds it)
	em.contact_cd[i] = maxf(em.contact_cd[i], 0.1)
	var h: Vector3 = em.charge_dir[i]
	run["heading"] = h if h.length_squared() > 0.01 else Vector3(1, 0, 0)
	started += 1
	last = {"phase": "spin", "at": em.pos[i], "creature": i}
	var cfg: Dictionary = run["cfg"]
	var lk: Dictionary = cfg["look"]
	# seen inside the funnel: the special's rim on his painting, in the tint's colour (status_tint; its alpha a touch over him)
	if float(lk["rim"]) > 0.0:
		var rc: Color = BossAttackDef.color_of(str(lk["rim_color"]), Color(0.95, 0.77, 0.41))
		em.vglow[i] = clampf(float(lk["rim"]), 0.0, 1.0)
		em.set_status_tint(i, Color(rc.r, rc.g, rc.b, 0.12), float(cfg["seconds"]) + 0.5)
	_loop(str(cfg["sound"]), true)
	_guard_sound(run, str(cfg["sound"]))
	if em.game != null and em.game.get("camera"):
		em.game.camera.shake(float((cfg["look"] as Dictionary)["shake"]))


## Every whirl under way, once a tick (EnemyManager._update_boss).
func tick(delta: float, ppos: Vector3) -> void:
	if runs.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	for key in runs.keys():
		var i := int(key)
		var run: Dictionary = runs[key]
		if em.alive[i] == 0 or em.serial[i] != int(run["serial"]) or em.state[i] != EnemyManager.STATE_ATTACK:
			# dead, gone, or something took him out of it
			_end(i, run, true)
			continue
		run["t"] = float(run["t"]) + delta
		var t := float(run["t"])
		var cfg: Dictionary = run["cfg"]
		var fxn = run["fxn"]
		var fx_ok: bool = fxn != null and is_instance_valid(fxn)
		match int(run["phase"]):
			TELL:
				var k := clampf(t / float(run["windup"]), 0.0, 1.0)
				_flip(i, run, delta, lerpf(1.5, float((cfg["look"] as Dictionary)["flip_hz"]), k))
				if fx_ok:
					fxn.follow(em.pos[i])
					fxn.tell(k, delta)
			SPIN:
				_spin(i, run, cfg, delta, ppos)
				_sound_level(str(cfg["sound"]), i, ppos)
				if fx_ok:
					fxn.follow(em.pos[i])
					fxn.fire(clampf(t / maxf(float(cfg["seconds"]), 0.05), 0.0, 1.0), delta)
				if t >= float(cfg["seconds"]):
					_dazed_begin(i, run, cfg)
			DAZED:
				var secs := maxf(float((cfg["dazed"] as Dictionary)["seconds"]), 0.0)
				em.squash[i] = 0.92 + 0.05 * sin(t * 9.0)
				# the ones still up keep turning round where he came out
				if t < float(cfg["lift"]):
					em.swirl(em.pos[i], float(cfg["radius"]), delta, float(cfg["fling"]))
				if fx_ok:
					fxn.follow(em.pos[i])
					fxn.spent(clampf(t / maxf(secs, 0.001), 0.0, 1.0), delta)
				if t >= secs:
					_end(i, run, false)
	Perf.add("boss.whirl", t0)


## One tick of the storm: he hunts, his painting flips, what is in reach rides, the hero is thrown.
func _spin(i: int, run: Dictionary, cfg: Dictionary, delta: float, ppos: Vector3) -> void:
	var c: Vector3 = em.pos[i]
	var h: Vector3 = run["heading"]
	var want := Vector3(ppos.x - c.x, 0.0, ppos.z - c.z)
	if want.length_squared() > 0.01:
		var turn := deg_to_rad(float(cfg["turn"])) * delta
		var diff := angle_difference(atan2(h.z, h.x), atan2(want.z, want.x))
		var a := atan2(h.z, h.x) + clampf(diff, -turn, turn)
		h = Vector3(cos(a), 0.0, sin(a))
		run["heading"] = h
	var np := em._clamp_arena(c + h * float(cfg["speed"]) * em.pace * delta)
	np.y = em._height(np.x, np.z)
	em.pos[i] = np
	# (the walk's own wind-up pose: no walking frames, no bite; a body the crowd pushes as ever)
	em.contact_cd[i] = maxf(em.contact_cd[i], 0.1)
	var lk: Dictionary = cfg["look"]
	_flip(i, run, delta, float(lk["flip_hz"]))
	em.lift_h[i] = float(lk["hover"]) * (0.8 + 0.2 * sin(float(run["t"]) * 5.0))
	# a whirler that is no boss never takes itself (lift_radius only leaves the boss out by name)
	em.lift_cd[i] = 1.0
	var secs := float(cfg["lift"])
	if secs > 0.0:
		lifted += em.lift_radius(np, float(cfg["radius"]), secs, float(cfg["lift_height"]), run["ride"])
	em.swirl(np, float(cfg["radius"]), delta, float(cfg["fling"]))
	_toss_hero(i, run, cfg, delta, np, ppos)


## The hero within reach is thrown up and out and hit, at most once per toss cooldown (a dodge or a bubble stops the throw and
## the hit, and the cooldown still runs: he is not thrown a tick later).
func _toss_hero(i: int, run: Dictionary, cfg: Dictionary, delta: float, c: Vector3, ppos: Vector3) -> void:
	run["cd"] = maxf(float(run["cd"]) - delta, 0.0)
	var pl = em.player
	if pl == null or not is_instance_valid(pl) or bool(pl.get("dead")) or float(run["cd"]) > 0.0:
		return
	var d := Vector3(ppos.x - c.x, 0.0, ppos.z - c.z)
	var reach := reach_of(cfg)
	if d.length_squared() >= reach * reach:
		return
	var toss: Dictionary = cfg["toss"]
	run["cd"] = float(toss["cooldown"])
	var n: Vector3 = d.normalized() if d.length_squared() > 0.01 else run["heading"]
	var dmg_now := float(cfg["damage"]) * em.stage_of(i) * em.lvd_of(i) * em.host_of(i)
	var info := em.hit_info(i, "melee", ["whirl", "thrown"])
	# the toss is the push: no shove of its own on top
	info["knock"] = 0.0
	info["special_knock"] = false
	pl.take_damage(dmg_now, c, info)
	var out_come = pl.get("last_outcome")
	if str(out_come) == "evaded" or (pl.has_method("knock_immune") and bool(pl.call("knock_immune"))):
		saved += 1
		return
	if pl.has_method("launch"):
		pl.launch(Vector3(n.x * float(toss["out"]), float(toss["up"]), n.z * float(toss["out"])))
	tosses += 1
	last = {"phase": "toss", "at": c, "creature": i, "damage": dmg_now}


func _flip(i: int, run: Dictionary, delta: float, hz: float) -> void:
	run["flip_t"] = float(run["flip_t"]) + delta * hz
	em.flip[i] = int(floor(float(run["flip_t"]))) % 2
	em.squash[i] = 1.0 + 0.04 * sin(float(run["flip_t"]) * PI)


## He stumbles out: the funnel bursts, the hits on him x damage_taken, the bar says DAZED.
func _dazed_begin(i: int, run: Dictionary, cfg: Dictionary) -> void:
	run["phase"] = DAZED
	run["t"] = 0.0
	em.lift_h[i] = 0.0
	em.lift_cd[i] = 0.0
	em.vglow[i] = float(run["glow0"])
	_mult(i, float((cfg["dazed"] as Dictionary)["damage_taken"]))
	var tint: Color = BossAttackDef.color_of(str((cfg["look"] as Dictionary)["dazed_tint"]), Color(0.88, 0.65, 0.23))
	em.set_status_tint(i, Color(tint.r, tint.g, tint.b, 0.3), float((cfg["dazed"] as Dictionary)["seconds"]))
	_hud(i, 2)
	_loop(str(cfg["sound"]), false)
	_guard_sound(run, "")
	var es := str(cfg["end_sound"])
	if es != "":
		Audio.play(es, em.pos[i])
	last = {"phase": "dazed", "at": em.pos[i], "creature": i}


## What a hit on him is multiplied by while dazed: BossPatterns' guard table, the one EnemyManager.damage reads.
func _mult(i: int, m: float) -> void:
	if em.patterns == null:
		em.patterns = BossPatterns.new(em)
	em.patterns.mult[i] = m


## It is over (or cut short: `was_cut`): the look goes, the bar and the tint clear, his cycle resumes after cooldown_between.
func _end(i: int, run: Dictionary, was_cut: bool) -> void:
	runs.erase(i)
	var cfg: Dictionary = run["cfg"]
	_loop(str(cfg["sound"]), false)
	var fxn = run["fxn"]
	if fxn != null and is_instance_valid(fxn):
		fxn.finish()
	run["fxn"] = null
	if em.patterns != null:
		em.patterns.mult.erase(i)
	var same: bool = i >= 0 and i < em.pool_max and em.alive[i] == 1 and em.serial[i] == int(run["serial"])
	if same:
		em.lift_h[i] = 0.0
		em.lift_cd[i] = 0.0
		em.squash[i] = 1.0
		em.vglow[i] = float(run["glow0"])
		em.set_status_tint(i, Color(0, 0, 0, 0), 0.0)
		if em.state[i] == EnemyManager.STATE_ATTACK:
			em.state[i] = EnemyManager.STATE_MOVE
		var def: EnemyDef = em.types[em.type_idx[i]]["def"]
		em.atk_t[i] = maxf(em.atk_t[i], float(def.boss.get("cooldown_between", 2.0)))
	_hud(i, 0)
	if was_cut:
		cut += 1
	else:
		ended += 1
	last = {"phase": "cut" if was_cut else "over", "creature": i}


## The boss's bar: DAZED (2) or as it was (0); only the boss's.
func _hud(i: int, mode: int) -> void:
	if i != em.boss_index or em.game == null:
		return
	var hud = em.game.get("hud")
	if hud != null and hud.has_method("set_boss_guard"):
		hud.set_boss_guard(mode)


## The storm's loop on and off (a look; silent in the sim's fast mode and without a game).
func _loop(id: String, on: bool) -> void:
	if id == "" or em.game == null or Run.sim_mode:
		return
	if on:
		Audio.play_loop(id)
	else:
		Audio.stop_loop(id)


## The guard that keeps the loop quiet through a pause rides on the look, gone with it; "" takes it off.
func _guard_sound(run: Dictionary, id: String) -> void:
	var fxn = run["fxn"]
	if fxn == null or not is_instance_valid(fxn):
		return
	var old = fxn.get_node_or_null("SoundGuard")
	if old != null:
		fxn.remove_child(old)
		old.free()
	if id != "" and not Run.sim_mode:
		var g := SoundGuard.new()
		g.name = "SoundGuard"
		g.id = id
		fxn.add_child(g)


## The loop louder the nearer the hero is, as a dust devil's (DustDevils.SOUND_NEAR, SOUND_FALLOFF).
func _sound_level(id: String, i: int, ppos: Vector3) -> void:
	if id == "" or em.game == null or Run.sim_mode:
		return
	var p = Audio.play_loop(id)
	if p == null:
		return
	var row: Dictionary = Registry.soundmap.entry(id) if Registry.soundmap != null else {}
	var d: float = em.pos[i].distance_to(ppos)
	(p as AudioStreamPlayer).volume_db = float(row.get("volume_db", -14.0)) - clampf((d - DustDevils.SOUND_NEAR) * DustDevils.SOUND_FALLOFF, 0.0, 40.0)


## Everything let go at once (a test's reset, the run over).
func clear_all() -> void:
	for key in runs.keys():
		_end(int(key), runs[key], true)
