## Pass 137 (lane BARRELS): what the Outlaw's rounds hitting barrels costs ProjectileManager's tick. A fake game (no map,
## no creatures) with the real ProjectileManager and BarrelField: `n` rounds kept flying at 20 m/s over a field of 35
## barrels 60 m across (the map's spacing), every tick timed with the switch on and off in turn (blocks of `block`
## ticks), the barrels made unbreakable (a `shots` of 100000) so the field stays whole. `near=1` sends every round from 2 m
## beside a barrel through it (the worst case: every round asks its barrel each tick). Headless:
##   bash tools/godot.sh --headless --path D:/_projects/88fits/game --log-file <abs> --script res://tools/_p137_BARRELS_bench.gd -- n=400 ticks=1200 [near=1]
## Autoloads are reached through the tree (a SceneTree script compiles before they exist).
extends SceneTree

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var pickups = null
var fx = null
var hud = null
var director = null
var barrels = null
var paused := false
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
"""
const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func max_speed() -> float:
	return 5.0
"""
const FAKE_DIRECTOR := """extends Node
var running := false
var phase := 0
var timeline = null
"""

var _n := 400
var _ticks := 1200
var _block := 60
var _near := false
const WATCHDOG := 120.0
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("n="):
			_n = int(a.substr(2))
		elif a.begins_with("ticks="):
			_ticks = int(a.substr(6))
		elif a.begins_with("near="):
			_near = a.substr(5) != "0"
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_watch)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


## A script error inside _main leaves nothing to quit: give up after WATCHDOG seconds.
func _watch() -> void:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG * 1000.0):
		print("p137_bench: watchdog, quitting")
		quit(3)


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _main() -> void:
	var settings = root.get_node("Settings")
	var was: bool = bool(settings.shoot_barrels)
	root.get_node("Run").start(root.get_node("Registry").character("drifter"), root.get_node("Registry").map("red_canyon"))
	var g := Node.new()
	g.set_script(_script(FAKE_GAME))
	root.add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	hero.global_position = Vector3(0, 0, 500)
	var em = load("res://core/systems/EnemyManager.gd").new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	var pm = load("res://core/systems/ProjectileManager.gd").new()
	pm.game = g
	g.add_child(pm)
	g.projectiles = pm
	var tl = load("res://core/data/WaveTimeline.gd").new()
	tl.barrels = {"exp": {"shots": 100000}, "coins": {"shots": 100000}, "powerup": {"shots": 100000}}
	var d := Node.new()
	d.set_script(_script(FAKE_DIRECTOR))
	g.add_child(d)
	d.timeline = tl
	g.director = d
	var bf = load("res://core/systems/BarrelField.gd").new()
	bf.game = g
	g.add_child(bf)
	g.barrels = bf
	var rng := RandomNumberGenerator.new()
	rng.seed = 137
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = 64
	mm.visible_instance_count = 35
	bf.set("_body_dark", mm)
	for k in range(35):
		var p := Vector3(rng.randf_range(-30, 30), 0, rng.randf_range(-30, 30))
		bf.pos.append(p)
		bf.light.append(0)
		bf.alive.append(1)
		bf.coins.append(0)
		bf._index_in.append(k)
		bf.shadows.append(-1)
	em._rebuild_grid()
	var kind: int = pm.register_kind(SphereMesh.new(), null, 1.0)
	var inst = load("res://core/systems/WeaponInstance.gd").new(root.get_node("Registry").weapon("revolver"), 1)
	var dt := 1.0 / 60.0
	var on_us := 0
	var off_us := 0
	var on_ticks := 0
	var off_ticks := 0
	for t in range(_ticks):
		var on := (t / _block) % 2 == 1
		settings.shoot_barrels = on
		# keep n rounds in the air
		while pm.count < _n:
			var a := rng.randf() * TAU
			var dir := Vector3(cos(a), 0, sin(a))
			var from: Vector3
			if _near:
				var b: Vector3 = bf.pos[rng.randi_range(0, 34)]
				from = b - dir * 2.0 + Vector3(0, 0.8, 0)
			else:
				from = Vector3(rng.randf_range(-35, 35), 0.8, rng.randf_range(-35, 35))
			if pm.fire(kind, from, dir * 20.0, 1.0, 0, 0.3, 0.25 if _near else 1.5, inst, 0.0) < 0:
				break
		var t0 := Time.get_ticks_usec()
		pm._physics_process(dt)
		var us := Time.get_ticks_usec() - t0
		if t < _block * 2:
			continue
		if on:
			on_us += us
			on_ticks += 1
		else:
			off_us += us
			off_ticks += 1
	settings.shoot_barrels = was
	var on_ms := float(on_us) / maxf(float(on_ticks), 1.0) / 1000.0
	var off_ms := float(off_us) / maxf(float(off_ticks), 1.0) / 1000.0
	print("p137_bench: rounds %d near %s ticks on %d off %d | projectiles ms/tick on %.4f off %.4f extra %.4f | knocks %d, breaks %d" % [
		_n, str(_near), on_ticks, off_ticks, on_ms, off_ms, on_ms - off_ms, bf.shot_knocks, bf.shot_breaks])
	quit(0)
