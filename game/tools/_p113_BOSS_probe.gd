## Pass 113 (lane BOSS): how survivable a boss's bullet-heaven pattern is. Headless, in the debug arena: the boss comes
## `up` metres north of the hero, his own cycle held back, his pattern started once he is free, and the hero is driven
## for the whole pattern by one of three pilots; every bullet that touches him is counted (his health is put back each
## frame, so the blink after a hit and an evade work as in play) and the run is repeated `runs` times with fresh dice.
##   dodge  a careful player: every frame he looks 0.4 s ahead along 16 ways and standing still, and takes the way whose
##          predicted spot is furthest from every bullet's predicted spot (a soft sum), kept 7-12 m from the boss
##   kite   the run sim's bot (tools/bot/BotLegs.gd: kiting the crowd, its danger now including the bullets)
##   still  he stands where he is (the worst case)
##   bash tools/godot.sh --headless --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/_p113_BOSS_probe.gd
##        -- boss=tumbleweed_king pilot=dodge runs=3 [up=9] [stage=1] [watchdog=400]
## Prints a line a run and a summary: "p113probe: <boss> <pilot>: hits a run ... = N% of max HP, peak bullets ...".
## The save in memory goes back as it was; tools/godot.sh puts the PC save file back too.
extends SceneTree

const LEGS := preload("res://tools/bot/BotLegs.gd")
const WATCHDOG_S := 400.0
const AHEAD := 0.4
const WAYS := 16

var A: Dictionary = {}
var g = null
var _ended := false
var _save = null
var _keep: Dictionary = {}
var _legs = null


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=", true, 1)
		A[kv[0]] = kv[1] if kv.size() > 1 else "1"
	create_timer(float(A.get("watchdog", WATCHDOG_S)), true, false, true).timeout.connect(_bail.bind("watchdog"))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _log(s: String) -> void:
	print("p113probe: " + s)


func _bail(why: String) -> void:
	if _ended:
		return
	_log("stopped: " + why)
	_finish(2)


func _finish(code: int) -> void:
	if _ended:
		return
	_ended = true
	if _save != null and not _keep.is_empty():
		_save.data = _keep
	quit(code)


func _main() -> void:
	var run = root.get_node("Run")
	var reg = root.get_node("Registry")
	_save = root.get_node("Save")
	_keep = _save.data.duplicate(true)
	var boss_id := str(A.get("boss", "tumbleweed_king"))
	var bdef = reg.enemy(boss_id)
	var cdef = null
	for e in bdef.boss.get("attacks", []):
		var c = reg.boss_attack(str((e as Dictionary).get("name", ""))) if e is Dictionary else null
		if c != null and c.attack_kind == "pattern":
			cdef = c
	if cdef == null:
		_log("no pattern for " + boss_id)
		_finish(1)
		return
	run.launch_override = {"arena": true, "analytics": false}
	change_scene_to_file("res://game/Game.tscn")
	for k in range(1200):
		await process_frame
		var cs = current_scene
		if cs != null and cs.get("arena_panel") != null and cs.get("player") != null and cs.get("enemies") != null:
			g = cs
			break
	if g == null:
		_log("the arena never came up")
		_finish(1)
		return
	await process_frame
	var panel = g.arena_panel
	var em = g.enemies
	g.no_random_chests = true
	var stage := int(A.get("stage", 1)) - 1
	var tl = run.map.timeline if run.map else null
	if stage >= 0 and tl != null:
		panel.call("set_clock", float(tl.stage_start(stage)) / 60.0 + 0.05)
	_legs = LEGS.new(int(A.get("seed", 7)))
	var pilot := str(A.get("pilot", "dodge"))
	var runs := int(A.get("runs", 3))
	var pscript = load("res://core/systems/BossPatterns.gd")
	var all_hits: Array = []
	var peak := 0
	for r in range(runs):
		panel.call("_clear_field")
		await process_frame
		var hero = g.player
		hero.god = false
		hero.global_position = Vector3(0, g.map.height_at(0, 0) + 0.5, 0)
		panel.set("_count", 1)
		panel.call("spawn_enemy", bdef)
		var bi := int(em.boss_index)
		if bi < 0:
			_log("no boss")
			_finish(1)
			return
		var bz := -float(A.get("up", 9.0))
		em.pos[bi] = Vector3(0, g.map.height_at(0, bz), bz)
		for k in range(600):
			em.atk_t[bi] = 50.0
			await process_frame
			if em.patterns == null:
				em.patterns = pscript.new(em)
			if em.patterns.is_free(bi):
				break
		var p = em.patterns
		var h0: int = p.hits
		p.begin(bi, cdef, {"name": cdef.id}, hero.global_position)
		var guard := 0
		while p.running(bi) and guard < 3000:
			guard += 1
			em.atk_t[bi] = 50.0
			hero.hp = hero.max_hp
			if hero.get("dead") == true:
				break
			_drive(pilot, hero, em, bi)
			await process_frame
			peak = maxi(peak, p.bullet_count())
		var got: int = p.hits - h0
		all_hits.append(got)
		_log("%s %s run %d: %d hits (%.0f%% of max HP), peak %d bullets" % [boss_id, pilot, r + 1, got, 100.0 * got * cdef.num("hit", "hit_frac"), p.peak])
		# the boss goes for the next run's fresh one
		em.hp[bi] = 0.0
		em.damage(bi, 1.0, "")
		for k in range(30):
			await process_frame
	var sum := 0
	for h in all_hits:
		sum += int(h)
	var mean := float(sum) / maxf(float(all_hits.size()), 1.0)
	_log("%s %s: hits a run %s, mean %.1f = %.0f%% of max HP (a bullet %.0f%%); peak %d bullets" % [boss_id, pilot, str(all_hits), mean,
		100.0 * mean * cdef.num("hit", "hit_frac"), 100.0 * cdef.num("hit", "hit_frac"), peak])
	_finish(0)


## One frame of the pilot.
func _drive(pilot: String, hero, em, bi: int) -> void:
	var inp = hero.input
	if inp == null:
		return
	match pilot:
		"still":
			inp.wants_move = false
		"kite":
			_legs.steer(g, 1.0 / 60.0, 0.0)
		_:
			LEGS.push(inp, _dodge_dir(hero, em, bi))


## The careful player's way: of 16 ways and standing still, the one whose spot AHEAD s on is furthest from every bullet's
## spot then (a soft sum of exp(-d / 0.8)), with a pull to 7-12 m from the boss and away from his body.
func _dodge_dir(hero, em, bi: int) -> Vector3:
	var me: Vector3 = hero.global_position
	var spd: float = float(hero.call("max_speed")) if hero.has_method("max_speed") else 5.0
	var bs: Array = em.patterns.bullets_near(me, 9.0)
	var c: Vector3 = em.pos[bi]
	var best := Vector3.ZERO
	var best_cost := INF
	for w in range(WAYS + 1):
		var d := Vector3.ZERO
		if w < WAYS:
			var a := TAU * float(w) / float(WAYS)
			d = Vector3(cos(a), 0, sin(a))
		var cost := 0.0
		for step in [0.15, AHEAD]:
			var at: Vector3 = me + d * spd * float(step)
			for b: Array in bs:
				var bx := float(b[0]) + float(b[2]) * float(step)
				var bz := float(b[1]) + float(b[3]) * float(step)
				var dd := Vector2(at.x - bx, at.z - bz).length()
				cost += exp(-dd / 0.8) * (2.0 if float(step) < 0.2 else 1.0)
		var at2: Vector3 = me + d * spd * AHEAD
		var r := Vector2(at2.x - c.x, at2.z - c.z).length()
		if r < 7.0:
			cost += (7.0 - r) * 0.5
		elif r > 12.0:
			cost += (r - 12.0) * 0.3
		if cost < best_cost:
			best_cost = cost
			best = d
	return best
