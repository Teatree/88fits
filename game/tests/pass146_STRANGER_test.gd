extends GdUnitTestSuite

## Pass 146 (Garry: "The Stranger ... looks too static ... a bit of an idle animation ... he actually dies when Player agrees /
## doesn't. Just collapses into that thing that stays." and "The Outlaw Screen still uses the old animation style without the
## stutter thing ... do this anywhere else we show enemy or outlaw animations"): the Stranger's painted strip (idle loop,
## then the collapse into his spent painting) and pass 144's held poses on the menus' figures.

const TS := preload("res://ui/TitleScreen.gd")
const ID := "hooded_figure"

var _was := 10


func before_test() -> void:
	_was = Settings.pose_rate


func after_test() -> void:
	Settings.pose_rate = _was


func test_the_menu_figure_holds_its_poses() -> void:
	var f = TS.HeroFigure.new()
	f.count = 24
	f.fps = 36.0
	f.anim_rate = 1.0
	Settings.pose_rate = 10
	var seen := {}
	for k in 60:
		f._process(1.0 / 60.0)
		seen[f.frame] = true
	for fr in seen.keys():
		assert_int(int(fr) % 4).is_equal(0)
	assert_int(seen.size()).is_greater(1)
	# off: every frame
	Settings.pose_rate = 0
	var odd := false
	for k in 60:
		f._process(1.0 / 60.0)
		if f.frame % 4 != 0:
			odd = true
	assert_bool(odd).is_true()
	f.free()


func test_the_stranger_has_his_strip() -> void:
	var d: StructureDef = Registry.structure(ID)
	var an := StructureManager.anim_of(d)
	assert_bool(an.is_empty()).is_false()
	var tex: Texture2D = load(str(an["strip"]))
	var cols := int(an["cols"])
	var n := int(an["idle"]) + int(an["die"])
	assert_int(tex.get_width()).is_equal(cols * 256)
	assert_int(tex.get_height()).is_equal(int(ceil(float(n) / float(cols))) * 256)
	assert_int(int(an["idle"])).is_greater(8)
	assert_int(int(an["die"])).is_greater(4)


func test_he_stands_idle_and_falls_when_his_screen_closes() -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 9, "analytics": false}))
	f.close()
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	await get_tree().create_timer(0.4).timeout
	g.player.god = true
	var sm: StructureManager = g.structures
	var at: Vector3 = g.player.global_position + Vector3(4, 0, 0)
	at.y = g.map.height_at(at.x, at.z)
	var s: StructureManager.Structure = sm._spawn(Registry.structure(ID), at)
	var bs := s.visual as BillboardSprite
	assert_str(bs.animation).is_equal("idle")
	assert_bool(bs.playing).is_true()
	assert_int(bs.pose_rate).is_equal(Settings.pose_rate)
	sm._use(s)
	for k in 20:
		if g.stranger_screen.visible or bs.animation == "die":
			break
		await get_tree().create_timer(0.05).timeout
	# his screen is up (or he had nothing to offer and fell at once): he stands until it closes
	if g.stranger_screen.visible:
		assert_str(bs.animation).is_equal("idle")
		g.stranger_screen._finish(false)
		await get_tree().process_frame
	assert_str(bs.animation).is_equal("die")
	var done: bool = false
	for k in 80:
		await get_tree().create_timer(0.05).timeout
		if not bs.playing:
			done = true
			break
	assert_bool(done).is_true()
	var an := StructureManager.anim_of(Registry.structure(ID))
	assert_int(int(bs.frame)).is_equal(int(an["die"]) - 1)
