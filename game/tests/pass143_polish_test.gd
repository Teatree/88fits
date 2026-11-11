extends GdUnitTestSuite

## Pass 143 (Garry's Polish, 2026-11-11): the Skull Rain's skull half as big, whiter and remodelled; the item texts he
## asked for (the Skull Rain's damage over time, the Dynamite's damage, Cold Snap's plain chance, the Boomstick's and the
## Dragon's Breath's damage); the Big Mouth looking where the Outlaw faces and its tell half as strong; Jeżyk is the
## Horseman and Fadeaway The Robot, with no skins.

const P139 := preload("res://tests/pass139_aim_test.gd")
const DT := 1.0 / 60.0

var _aim_was := true
var _show_was := true


func before_test() -> void:
	Loc.load_table()
	Loc.clear_warnings()
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	_aim_was = Settings.aim_mode
	_show_was = Settings.show_aim
	Settings.aim_mode = true
	Settings.show_aim = true
	Aim.reset()


func after_test() -> void:
	Settings.aim_mode = _aim_was
	Settings.show_aim = _show_was
	Run.weapons = []
	Run.debug_clear_items()
	Run.end()


func _inst(id: String, level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	inst.rebuild(StatSheet.new(), [inst])
	return inst


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## pass 139's fake world (its game, hero and camera scripts), the crowd and the shots on it.
func _world() -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(P139.FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(P139.FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var cam := Node.new()
	cam.set_script(_script(P139.FAKE_CAMERA))
	g.add_child(cam)
	g.camera = cam
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	var pm := ProjectileManager.new()
	pm.game = g
	g.add_child(pm)
	g.projectiles = pm
	var fx := Fx.new()
	g.add_child(fx)
	g.fx = fx
	var tg := Telegraphs.new()
	g.add_child(tg)
	g.telegraphs = tg
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em}


static func _json(path: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


# ---------------------------------------------------------------- the skull

func test_the_skull_is_half_as_big_and_white() -> void:
	# pass 136's sizes were 1.5 (Skull Rain) and 1.6 (its evolutions); the evolutions' cream tint is white now too
	var sizes := {"res://content/weapons/skull_rain/skull_rain.json": 0.75,
		"res://content/evolutions/dia_de_muertos/dia_de_muertos.json": 0.8,
		"res://content/evolutions/grave_hail/grave_hail.json": 0.8}
	for p: String in sizes:
		var gs: Dictionary = (_json(p).get("params", {}) as Dictionary).get("ground_skull", {})
		assert_float(float(gs.get("size", 0.0))).override_failure_message(p).is_equal_approx(float(sizes[p]), 0.001)
		assert_str(str(gs.get("tint", ""))).override_failure_message(p).is_equal("#FFFFFF")
	assert_bool(ResourceLoader.exists(GroundSkulls.MODEL)).is_true()
	assert_str(GroundSkulls.SHADER_CODE).contains("uniform float lift = 0.36;")


func test_the_remodelled_skull_is_one_light_mesh_on_the_sand() -> void:
	var mesh := GroundSkulls._mesh(GroundSkulls.MODEL)
	assert_object(mesh).is_not_null()
	var aabb := mesh.get_aabb()
	# its base on the sand, about half a metre wide at scale 1, deeper (front to back) than wide like a skull
	assert_float(aabb.position.y).is_between(-0.02, 0.02)
	assert_float(aabb.size.x).is_between(0.4, 0.6)
	assert_float(aabb.size.z).is_greater(aabb.size.x * 0.95)
	var tris := 0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var idx = arr[Mesh.ARRAY_INDEX]
		tris += (idx.size() / 3) if idx is PackedInt32Array and idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		# the paint: near-white bone and dark sockets (vertex colours)
		var cols = arr[Mesh.ARRAY_COLOR]
		assert_bool(cols is PackedColorArray and (cols as PackedColorArray).size() > 0).is_true()
		var white := 0
		var dark := 0
		for c: Color in cols:
			if c.r > 0.85 and c.g > 0.85 and c.b > 0.85:
				white += 1
			elif c.v < 0.2:
				dark += 1
		assert_int(white).is_greater(dark)
		assert_int(dark).is_greater(0)
	assert_int(tris).is_less(7000)


# ---------------------------------------------------------------- the texts

func test_the_texts_garry_asked_for() -> void:
	# 1.1 the Skull Rain: the bomb's blast and every poison tick of its seconds, said as one total over the seconds
	var sr := _inst("skull_rain")
	var st := sr.sheet
	var ticks := floori(st.get_stat("poison_duration", 10.0) / TextGen.POISON_TICK + 0.001)
	var total := TextGen._dmg(st.get_stat("damage", 0.0) + st.get_stat("poison_damage", 0.0) * maxi(st.get_int("poison_stacks", 1), 1) * ticks)
	assert_str(total).is_equal("21")
	assert_str(sr.description()).is_equal("Lobs 1 poison bomb at a crowd for 21 damage over 10 s.")
	# 2. the Dynamite (look B's noun)
	assert_str(_inst("lob_grenade").description()).is_equal("Lobs 1 stick of dynamite at a crowd for 25 damage.")
	# 3. Cold Snap: the chance as it is, no "+", no "total"
	var cs: PassiveDef = Registry.passive("cold_snap")
	assert_str(TextGen.passive_description(cs, 1)).is_equal("3% chance to freeze an enemy for 1 s when hit.")
	assert_str(TextGen.passive_description(cs, 2)).is_equal("Level 2 (Uncommon): 4.5% chance to freeze an enemy for 1 s when hit.")
	assert_bool(TextGen.passive_description(cs, 6).contains("+")).is_false()
	# 4. the Boomstick, and its Birdshot lane (frac x damage x amount, as ProjectileEmitter._blast deals it)
	assert_str(_inst("boomstick").description()).is_equal("Fires 5 pellets in a 35° cone where you face for 6 damage each.")
	# 5. the Dragon's Breath
	var db := _inst("dragons_breath")
	assert_str(db.description()).is_equal("Breathes a 50° cone of fire 5 m long for 2.0 s every 10.6 s, dealing %s damage every second." % str(int(round(db.sheet.get_stat("damage", 0.0)))))
	assert_array(Loc.warnings()).is_empty()


func test_the_constants_the_words_mirror() -> void:
	assert_float(TextGen.POISON_TICK).is_equal(EnemyManager.POISON_TICK)
	assert_float(TextGen.FREEZE_SECONDS).is_equal(EnemyManager.FREEZE_SECONDS)


# ---------------------------------------------------------------- the Big Mouth

func test_the_mouth_looks_where_the_outlaw_faces_not_at_a_creature() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	# a creature straight behind him: before pass 143 the mouth at rest turned to it
	var i := em.spawn("skeleton", Vector3(0, 0, 4), null, 1.0, 50.0)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.dr[i] = 0.0
	em.rise_t[i] = 1.0
	em.pos[i] = Vector3(0, 0, 4)
	if em.onscreen.size() > i:
		em.onscreen[i] = 1
	em._rebuild_grid()
	var inst := WeaponInstance.new(Registry.weapon("big_mouth"), 1)
	inst.rebuild(Run.player_sheet, [inst])
	var lb := LaserBeam.new()
	(w["g"] as Node).add_child(lb)
	lb.setup(inst, w["g"])
	lb._yaw0 = 0.0
	lb._aim_yaw = 0.0
	lb.cooldown_left = 99.0
	for k in 90:
		lb._process(DT)
	var d := lb._dir()
	var want := atan2(-d.x, -d.z)
	assert_float(absf(wrapf(lb._face_yaw - want, -PI, PI))).is_less(0.15)
	# the creature is behind (+Z): its yaw is about PI; the mouth's is about 0 (the facing, -Z)
	assert_float(absf(wrapf(lb._face_yaw, -PI, PI))).is_less(0.5)
	# without the aim rule it turns to the creature, as before
	Settings.aim_mode = false
	for k in 90:
		lb._process(DT)
	assert_float(absf(wrapf(lb._face_yaw - PI, -PI, PI))).is_less(0.6)


func test_the_mouths_tell_is_half_as_strong() -> void:
	assert_float(AimWedge.MOUTH_GAIN).is_equal(0.5)
	var src := FileAccess.get_file_as_string("res://core/shaders/aim_wedge.gdshader")
	assert_str(src).contains("uniform float m_gain")
	assert_str(src).contains("* m_gain;")


# ---------------------------------------------------------------- the outlaws

func test_the_horseman_and_the_robot_have_no_skins() -> void:
	var h: CharacterDef = Registry.character("buck")
	var r: CharacterDef = Registry.character("fadeaway")
	assert_str(h.display_name).is_equal("Horseman")
	assert_str(r.display_name).is_equal("The Robot")
	assert_array(Registry.skins_of(h)).is_empty()
	assert_array(Registry.skins_of(r)).is_empty()
	for q in ["skin_buck_buc_g", "skin_fadeaway_fad_b", "skin_fadeaway_fad_g"]:
		assert_object(Registry.quests.get(q)).override_failure_message(q).is_null()
	# the old characters' skins are shelved looks now (their files stay)
	for pair in [[h, "BUC-G"], [r, "FAD-B"], [r, "FAD-G"]]:
		assert_bool((pair[0] as CharacterDef).variant_shelved(str(pair[1]))).override_failure_message(str(pair[1])).is_true()
