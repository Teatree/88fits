extends GdUnitTestSuite

## Pass 33.8: the late game on a phone, with nothing different to see. Ground marks are instances of ready-made shapes
## in shared pools (no mesh built per blast, no node per mark), the crowd checks only the obstacles near it, steers half
## at a time and keeps its grid in flat arrays, creatures, shots and gems are drawn once per shown frame, and the saws,
## the lightning, the wall's posts and weapon parts that share a material draw in far fewer calls. And the harpooner
## has the rocketeer's health.

const FAKE_GAME := """extends Node
var player: Node3D
var projectiles = null
var enemies = null
var telegraphs = null
var fx = null
var map = null
var camera = null
var paused := false
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var velocity := Vector3.ZERO
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func shove(_v: Vector3) -> bool:
	return true
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
func aim_origin(_d: Vector3) -> Vector3:
	return global_position
"""

const FAKE_CAMERA := """extends Node
func zoom() -> float:
	return 1.0
func current_yaw() -> float:
	return 0.0
"""


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _fake_game(hero_at: Vector3) -> Node:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = hero_at
	g.player = hero
	var cam := Node.new()
	cam.set_script(_script(FAKE_CAMERA))
	g.add_child(cam)
	g.camera = cam
	var tg := Telegraphs.new()
	g.add_child(tg)
	g.telegraphs = tg
	var fx := Fx.new()
	g.add_child(fx)
	g.fx = fx
	return g


func _manager(g: Node) -> EnemyManager:
	var em := EnemyManager.new()
	em.game = g
	em.player = g.player
	g.add_child(em)
	g.enemies = em
	return em


# ---------------------------------------------------------------- the harpooner

func test_the_harpooner_has_the_rocketeers_health() -> void:
	assert_float(Registry.enemy("harpoon_troglodyte").hp).is_equal_approx(Registry.enemy("rocketeer").hp, 0.001)


# ---------------------------------------------------------------- ground marks

func test_ground_marks_are_instances_not_nodes() -> void:
	var g := _fake_game(Vector3.ZERO)
	var tg: Telegraphs = g.telegraphs
	for k in range(20):
		tg.flash_ring(Vector3(k, 0, 0), 2.0, Color(1, 0.6, 0.3), 0.35)
	tg.ring(Vector3.ZERO, 3.0, 1.0, Color(1, 0, 0), true)
	tg.line(Vector3.ZERO, Vector3.FORWARD, 6.0, 1.0, Color(1, 0, 0))
	tg.sector(Vector3.ZERO, Vector3.FORWARD, 3.0, 60.0, 1.0, Color(1, 0, 0))
	tg.scorch(Vector3.ZERO, 1.5, Color(0.1, 0.06, 0.05, 0.6), Color(0.22, 0.14, 0.1, 0.0), 0.2, 0.3)
	tg._process(0.016)
	# one MultiMesh per kind of mark, however many land: twenty blast rings are twenty instances of one
	for c in tg.get_children():
		assert_bool(c is MultiMeshInstance3D).override_failure_message(str(c) + " is a node of its own").is_true()
	assert_int(tg.get_child_count()).is_less_equal(5)
	assert_int(tg.live_count()).is_equal(25)
	assert_int((tg._pools["band"]["mm"] as MultiMesh).visible_instance_count).is_equal(21)
	# the blast rings go after their 0.35 s, everything else after its own time
	tg._process(0.4)
	assert_int((tg._pools["band"]["mm"] as MultiMesh).visible_instance_count).is_equal(1)
	tg._process(0.7)
	assert_int(tg.live_count()).is_equal(0)


func test_a_blast_ring_grows_from_forty_percent_to_full() -> void:
	var g := _fake_game(Vector3.ZERO)
	var tg: Telegraphs = g.telegraphs
	tg.flash_ring(Vector3.ZERO, 5.0, Color(1, 1, 1), 1.0)
	tg._advance(0.0)
	var it: Dictionary = tg._items[0]
	assert_float((it["_k"] as Color).g).is_equal_approx(2.0, 0.001)
	tg._advance(0.5)
	assert_float((it["_k"] as Color).g).is_equal_approx(5.0 * (0.4 + 0.6 * 0.5), 0.001)
	# the band stays 12 cm wide as it grows
	assert_float((it["_k"] as Color).g - (it["_k"] as Color).r).is_equal_approx(0.12, 0.001)


func test_a_spill_and_its_billows_are_held_and_let_go() -> void:
	var g := _fake_game(Vector3(50, 0, 50))
	_manager(g)
	var tg: Telegraphs = g.telegraphs
	var c := ElementCloud.new()
	c.setup(g, null, 2.0, 1.0, 3.0, 1, 5.0, "poison")
	c.position = Vector3(3, 0, 3)
	g.add_child(c)
	# the puddle and its six billows are pool instances, not children
	assert_int(tg.live_count()).is_equal(7)
	assert_int(c.get_child_count()).is_equal(0)
	c._process(0.5)
	tg._process(0.016)
	assert_int((tg._pools["puff"]["mm"] as MultiMesh).visible_instance_count).is_equal(6)
	c.free()
	tg._process(0.016)
	assert_int(tg.live_count()).is_equal(0)
	# a fire spill: the oil alone (its flames are the Fx pool's)
	var f := ElementCloud.new()
	f.setup(g, null, 1.5, 1.0, 4.0, 1, 1.8, "fire")
	g.add_child(f)
	assert_int(tg.live_count()).is_equal(1)
	f.free()
	tg._process(0.016)
	assert_int(tg.live_count()).is_equal(0)


func test_a_zone_is_a_pooled_disc() -> void:
	var g := _fake_game(Vector3(50, 0, 50))
	_manager(g)
	var tg: Telegraphs = g.telegraphs
	var z := Zone.new()
	z.setup(g, null, 1.2, 1.0, 0.0, 0.5, 0.3, Color(0.4, 0.75, 1.0, 0.4))
	g.add_child(z)
	assert_int(tg.live_count()).is_equal(1)
	assert_int(z.get_child_count()).is_equal(0)
	z.free()
	tg._process(0.016)
	assert_int(tg.live_count()).is_equal(0)


# ---------------------------------------------------------------- the crowd

func test_the_flat_grid_finds_what_a_scan_finds_in_the_old_order() -> void:
	var g := _fake_game(Vector3.ZERO)
	var em := _manager(g)
	seed(5)
	for k in range(140):
		em.spawn("goblin", Vector3(randf_range(-58, 58), 0, randf_range(-58, 58)))
	# a few far out, past the grid's edge
	em.spawn("goblin", Vector3(95, 0, -90))
	em.spawn("goblin", Vector3(-99, 0, 97))
	em._rebuild_grid()
	for q in range(60):
		var c := Vector3(randf_range(-100, 100), 0, randf_range(-100, 100))
		var r := randf_range(0.5, 12.0)
		var got := em.indices_in_radius(c, r)
		# the old grid's order: cell by cell (x, then z), and in index order within a cell
		var want: Array = []
		for i in range(EnemyManager.MAX):
			if em.alive[i] == 1 and em.state[i] != EnemyManager.STATE_DYING and em.hidden[i] == 0:
				var d := em.pos[i] - c
				d.y = 0.0
				if d.length_squared() <= r * r:
					want.append(i)
		want.sort_custom(func(a, b):
			var ca := Vector2i(floori(em.pos[a].x / EnemyManager.CELL), floori(em.pos[a].z / EnemyManager.CELL))
			var cb := Vector2i(floori(em.pos[b].x / EnemyManager.CELL), floori(em.pos[b].z / EnemyManager.CELL))
			if ca.x != cb.x:
				return ca.x < cb.x
			if ca.y != cb.y:
				return ca.y < cb.y
			return a < b)
		assert_array(Array(got)).is_equal(want)


func test_obstacles_by_cell_push_as_hard_as_all_of_them() -> void:
	var g := _fake_game(Vector3.ZERO)
	var em := _manager(g)
	seed(9)
	var obs: Array = []
	for k in range(100):
		obs.append(Vector3(randf_range(-60, 60), randf_range(-60, 60), randf_range(0.3, 2.5)))
	em.obstacles = obs
	var small := em.spawn("goblin", Vector3.ZERO)
	# the widest creature widens every obstacle's cells
	var big := em.spawn("tumbleweed_king", Vector3(5, 0, 5))
	em._obstacle_cells()
	assert_float(em._obst_margin).is_greater_equal(em.radius[big])
	for i in [small, big]:
		for trial in range(400):
			em.pos[i] = Vector3(randf_range(-63, 63), 0, randf_range(-63, 63))
			var want := Vector3.ZERO
			for o: Vector3 in obs:
				var d := Vector3(em.pos[i].x - o.x, 0, em.pos[i].z - o.y)
				var l2 := d.length_squared()
				var min_d: float = o.z + em.radius[i]
				if l2 < min_d * min_d and l2 > 0.0001:
					var l := sqrt(l2)
					want += d / l * (min_d - l) * 3.0
			assert_float((em._obstacle_push(i) - want).length()).is_less(0.00001)
	# a new obstacle is picked up
	obs.append(Vector3(0.5, 0.0, 2.0))
	em.pos[small] = Vector3(1.0, 0, 0)
	em._obstacle_cells()
	assert_float(em._obstacle_push(small).length()).is_greater(0.5)


func test_half_the_crowd_steers_each_tick() -> void:
	var g := _fake_game(Vector3(30, 0, 30))
	var em := _manager(g)
	var ids: Array = []
	for k in range(10):
		var i := em.spawn("goblin", Vector3(k * 2.0, 0, 0))
		em.state[i] = EnemyManager.STATE_MOVE
		em.slow_t[i] = 1.0
		em.slow_f[i] = 0.1
		ids.append(i)
	var dt := 1.0 / 60.0
	em._physics_process(dt)
	var steered := 0
	for i in ids:
		if em.slow_t[i] < 1.0:
			steered += 1
	assert_int(steered).is_equal(5)
	# the next tick steers the other half: each has steered exactly once, over two ticks' time
	em._physics_process(dt)
	for i in ids:
		assert_float(em.slow_t[i]).is_equal_approx(1.0 - 2.0 * dt, 0.0001)


## The strip the old code chose by name, for the frame-table check.
func _old_strip(em: EnemyManager, i: int, def: EnemyDef) -> String:
	var anim := "run"
	var st := em.state[i]
	if st == EnemyManager.STATE_DYING:
		anim = "die"
	elif st == EnemyManager.STATE_WINDUP or st == EnemyManager.STATE_ATTACK:
		anim = "attack"
	elif st == EnemyManager.STATE_SPAWN:
		anim = "idle"
	elif em.vel[i].length_squared() < 0.04:
		anim = "idle"
	if em.flash[i] > 0.6 and def.frames_of("hit") > 0 and st != EnemyManager.STATE_DYING:
		anim = "hit"
	if def.frames_of("run_s") > 0 and def.anims.has("run_s"):
		if st == EnemyManager.STATE_CHARGE:
			anim = "run"
		elif st == EnemyManager.STATE_WINDUP and def.charge.size() > 0:
			anim = "idle"
		if anim == "run" or anim == "idle":
			var suffix: String = ["", "_b", "_s", "_bd", "_fd"][em.view[i]]
			if def.frames_of(anim + suffix) > 0 and def.anims.has(anim + suffix):
				anim += suffix
	elif em.away[i] == 1 and (anim == "run" or anim == "idle") and def.frames_of(anim + "_b") > 0:
		anim += "_b"
	return anim


func test_the_frame_table_picks_the_strip_the_names_did() -> void:
	var g := _fake_game(Vector3(80, 0, 80))
	var em := _manager(g)
	var i := em.spawn("goblin", Vector3.ZERO)
	var checked := 0
	for id in Registry.enemies.keys():
		var def: EnemyDef = Registry.enemy(id)
		var t := em.register_type(def)
		em.type_idx[i] = t
		for st in [EnemyManager.STATE_MOVE, EnemyManager.STATE_WINDUP, EnemyManager.STATE_CHARGE, EnemyManager.STATE_DYING, EnemyManager.STATE_ATTACK, EnemyManager.STATE_SPAWN]:
			for moving in [false, true]:
				for fl in [0.0, 0.9]:
					for v in range(5):
						for aw in [0, 1]:
							em.state[i] = st
							em.vel[i] = Vector3(1, 0, 0) if moving else Vector3.ZERO
							em.flash[i] = fl
							em.view[i] = v
							em.away[i] = aw
							var name := _old_strip(em, i, def)
							var strip := em._strip_of(i, t)
							assert_str(EnemyManager.ANIM_NAMES[strip]).override_failure_message("%s state %d moving %s flash %.1f view %d away %d: %s, was %s" % [id, st, moving, fl, v, aw, EnemyManager.ANIM_NAMES[strip], name]).is_equal(name)
							assert_bool(em.strip_frames(t, strip) == Vector2i(def.frame_offset(name), def.frames_of(name))).is_true()
							checked += 1
	assert_int(checked).is_greater(1000)


func test_the_crowd_is_drawn_once_per_shown_frame() -> void:
	var g := _fake_game(Vector3(30, 0, 30))
	var em := _manager(g)
	em.spawn("goblin", Vector3(2, 0, 0))
	em._physics_process(1.0 / 60.0)
	em._physics_process(1.0 / 60.0)
	# two ticks drew nothing: the draw is the frame's, once
	assert_int(em._drawn).is_equal(-1)
	em._process(1.0 / 60.0)
	assert_int(em._drawn).is_equal(em._ticks)
	assert_int((em._t_mm[0] as MultiMesh).visible_instance_count).is_equal(1)


func test_shots_are_drawn_once_per_shown_frame() -> void:
	var g := _fake_game(Vector3(30, 0, 30))
	_manager(g)
	var pm := ProjectileManager.new()
	pm.game = g
	g.add_child(pm)
	g.projectiles = pm
	var k := pm.register_kind(BoxMesh.new(), null)
	pm.hostile_shot(k, Vector3.ZERO, Vector3(0, 0, 3), 1.0, 0.0)
	pm._physics_process(1.0 / 60.0)
	assert_int(pm._drawn).is_equal(-1)
	pm._process(1.0 / 60.0)
	assert_int(pm._drawn).is_equal(pm._ticks)
	assert_int((pm.kinds[k]["mm"] as MultiMesh).visible_instance_count).is_equal(1)


# ---------------------------------------------------------------- fewer draw calls

func test_the_saws_are_one_multimesh() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var g := _fake_game(Vector3(30, 0, 30))
	_manager(g)
	var pm := ProjectileManager.new()
	pm.game = g
	g.add_child(pm)
	g.projectiles = pm
	var def: WeaponDef = Registry.weapon("saw_halo")
	var inst := WeaponInstance.new(def, def.max_level)
	var b := Orbiter.new()
	g.add_child(b)
	b.setup(inst, g)
	b._tick(1.0 / 60.0)
	var n := maxi(inst.stat_int("amount", 1), 1)
	assert_int(b.blade_count()).is_equal(n)
	var mmi: MultiMeshInstance3D = b.get_node("Blades")
	assert_int(mmi.multimesh.visible_instance_count).is_equal(n)
	for c in b.get_children():
		assert_bool(c is MeshInstance3D and (c as MeshInstance3D).mesh == mmi.multimesh.mesh).is_false()


func test_lightning_bolts_share_two_meshes() -> void:
	var fx: Fx = auto_free(Fx.new())
	add_child(fx)
	fx.lightning([Vector3.ZERO, Vector3(3, 0, 0), Vector3(6, 0, 2)])
	fx.lightning([Vector3.ZERO, Vector3(0, 0, 4)])
	var meshes := 0
	for c in fx.get_children():
		if c is MeshInstance3D:
			meshes += 1
	# the sheath and the core, whatever strikes
	assert_int(meshes).is_equal(2)
	assert_int(fx._bolts.size()).is_equal(2)
	fx._process(0.2)
	assert_int(fx._bolts.size()).is_equal(2)
	fx._process(0.2)
	assert_int(fx._bolts.size()).is_equal(0)
	assert_int(fx._live).is_equal(0)


func test_the_wall_posts_are_one_multimesh() -> void:
	var map = auto_free(load("res://world/maps/red_canyon/RedCanyon.gd").new())
	var wall: Node3D = map._boundary_wall(60.0, 90)
	var posts: MultiMeshInstance3D = wall.get_node("Posts")
	assert_int(posts.multimesh.instance_count).is_equal(36)
	for c in wall.get_children():
		assert_bool(c is MeshInstance3D and (c as MeshInstance3D).mesh is CylinderMesh).is_false()
	wall.free()


func test_parts_that_share_a_material_draw_as_one() -> void:
	var vis: Node3D = load("res://content/evolutions/missile_massacre/missile_massacre_visual.tscn").instantiate()
	var body := vis.get_node("Familiar/Body")
	var parts := body.get_child_count()
	var verts := 0
	for c in body.get_children():
		verts += (c as MeshInstance3D).mesh.get_faces().size()
	var saved := MeshMerge.merge(vis)
	# nine parts in three materials: three meshes, the same triangles
	assert_int(parts).is_equal(9)
	assert_int(saved).is_equal(6)
	assert_int(body.get_child_count()).is_equal(3)
	var after := 0
	for c in body.get_children():
		after += (c as MeshInstance3D).mesh.get_faces().size()
	assert_int(after).is_equal(verts)
	vis.free()
	# the parts the code moves by name are never merged: the Rocket Pod's cluster and its four tips
	var pod: Node3D = load("res://content/weapons/rocket_pod/rocket_pod_visual.tscn").instantiate()
	MeshMerge.merge(pod)
	assert_object(pod.get_node_or_null("Familiar/Body/Cluster")).is_not_null()
	for k in range(1, 5):
		assert_object(pod.get_node_or_null("Familiar/Body/Cluster/Tip%d" % k)).is_not_null()
	pod.free()
