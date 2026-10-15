## Pass 80 (lane OASIS) micro-benchmark: what the water's slow costs the crowd's tick. An EnemyManager with Red Canyon's
## lakes for a seed (three for seed 7), `n` creatures spread over the arena (a share of them in the water), and the time
## of `_wade_tick` (marking who wades) and of reading `_wade_k` for every creature, as many rounds as asked, against the same loop without it.
##   bash tools/godot.sh --headless --path game --script res://tools/_p80_OASIS_bench.gd -- n=250 rounds=2000 seed=7
extends SceneTree

var _n := 250
var _rounds := 2000
var _seed := 7


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("n="):
			_n = int(a.substr(2))
		elif a.begins_with("rounds="):
			_rounds = int(a.substr(7))
		elif a.begins_with("seed="):
			_seed = int(a.substr(5))
	process_frame.connect(_go, CONNECT_ONE_SHOT)


func _go() -> void:
	var run = root.get_node("Run")
	var reg = root.get_node("Registry")
	run.forced_map_seed = _seed
	run.end()
	run.start(reg.character("drifter"), reg.map("red_canyon"))
	var map: Node3D = (reg.map("red_canyon").scene as PackedScene).instantiate()
	root.add_child(map)
	# (loaded, not named: a --script tool compiles before the autoloads exist)
	var EM: GDScript = load("res://core/systems/EnemyManager.gd")
	var em = EM.new()
	var hero := Node3D.new()
	root.add_child(hero)
	var gs := GDScript.new()
	gs.source_code = "extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var pickups = null
var fx = null
var paused := false
func fx_burst(_a, _b, _c) -> void:
	pass
"
	gs.reload()
	var g := Node.new()
	g.set_script(gs)
	root.add_child(g)
	g.set("player", hero)
	g.set("map", map)
	em.game = g
	em.player = hero
	root.add_child(em)
	g.set("enemies", em)
	var lakes: Array = map.call("lakes")
	var first: Dictionary = lakes[0]
	em.set_lake(first["center"], float(first["radius"]))
	for k in range(1, lakes.size()):
		var l: Dictionary = lakes[k]
		em.add_lake(l["center"], float(l["radius"]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var wet := 0
	for k in range(_n):
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 60.0
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		# a tenth of them wading, as a crowd chasing a hero by the water would
		if k % 10 == 0:
			var l: Dictionary = lakes[k % lakes.size()]
			var c: Vector2 = l["center"]
			p = Vector3(c.x + rng.randf_range(-3, 3), 0, c.y + rng.randf_range(-3, 3))
		var i: int = em.spawn("skeleton", p, null, 1.0, 50.0)
		if i >= 0:
			em.rise_t[i] = 1.0
			em.state[i] = EM.STATE_MOVE
	em._rebuild_grid()
	em._wade_tick()
	var idx: Array = []
	for i in int(EM.MAX):
		if em.alive[i] == 1:
			idx.append(i)
			if em._wade_k[i] < 1.0:
				wet += 1
	# the loop alone
	var t0 := Time.get_ticks_usec()
	var s0 := 0.0
	for r in range(_rounds):
		for i: int in idx:
			s0 += em.vel[i].x
	var base := Time.get_ticks_usec() - t0
	# the loop with the wade factor
	var t1 := Time.get_ticks_usec()
	var s1 := 0.0
	for r in range(_rounds):
		em._wade_tick()
		for i: int in idx:
			s1 += em.vel[i].x * em._wade_k[i]
	var with := Time.get_ticks_usec() - t1
	var per := float(with - base) / float(_rounds)
	print("oasis_bench: %d creatures (%d wading), %d lakes: %.1f us a tick for the wade factor (%.3f us a creature); loop alone %.1f us, with %.1f us (%s %s)" % [idx.size(), wet, lakes.size(), per, per / float(maxi(idx.size(), 1)), float(base) / _rounds, float(with) / _rounds, str(s0), str(s1)])
	run.forced_map_seed = 0
	run.end()
	quit(0)
