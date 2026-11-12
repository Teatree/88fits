extends GdUnitTestSuite

## Pass 144 (Garry: "Megabonk ... it's kind of jerky looking, it feels like frames are missing ... let's try this out, but
## don't change how the assets are generated"): stepped poses. A looping strip shows every k-th frame and holds it,
## k = round(its rate / Settings.pose_rate); the strips are untouched; 0 = off.

var _was := 12


func before_test() -> void:
	_was = Settings.pose_rate


func after_test() -> void:
	Settings.pose_rate = _was


func test_the_stride_from_a_rate() -> void:
	assert_int(Settings.pose_stride(36.0, 12)).is_equal(3)   # an Outlaw's run: 12 poses a second
	assert_int(Settings.pose_stride(20.0, 12)).is_equal(2)
	assert_int(Settings.pose_stride(15.0, 12)).is_equal(1)   # most creatures already change pose ~15 times a second
	assert_int(Settings.pose_stride(15.0, 8)).is_equal(2)
	assert_int(Settings.pose_stride(36.0, 0)).is_equal(1)    # off
	# a new player starts at 10 (Garry's pick); 36 fps -> every 4th frame, 15 fps -> every 2nd
	var fresh: Node = load("res://core/autoload/Settings.gd").new()
	assert_int(int(fresh.get("pose_rate"))).is_equal(10)
	fresh.free()
	assert_int(Settings.pose_stride(36.0, 10)).is_equal(4)
	assert_int(Settings.pose_stride(15.0, 10)).is_equal(2)


func test_the_rates_cycle_and_save() -> void:
	assert_int(Settings.next_pose_rate(12)).is_equal(10)
	assert_int(Settings.next_pose_rate(10)).is_equal(8)
	assert_int(Settings.next_pose_rate(8)).is_equal(0)
	assert_int(Settings.next_pose_rate(0)).is_equal(12)
	assert_str(Settings.pose_rate_label(0)).is_equal("OFF")
	Settings.pose_rate = 8
	var d := Settings.to_dict()
	assert_int(int(d["pose_rate"])).is_equal(8)
	Settings.pose_rate = 12
	Settings.from_dict(d)
	assert_int(Settings.pose_rate).is_equal(8)
	Settings.from_dict({"pose_rate": 7})   # not a step: kept as it was
	assert_int(Settings.pose_rate).is_equal(8)


func test_the_outlaws_sprite_holds_every_third_frame_of_a_36_fps_run() -> void:
	var s := BillboardSprite.new()
	add_child(s)
	var img := Image.create(256 * 8, 256, false, Image.FORMAT_RGBA8)
	s.setup(ImageTexture.create_from_image(img), {"idle": 4, "run": 24}, ["idle", "run"], 1.9, 8, {"run": 36.0, "idle": 8.0})
	s.pose_rate = 12
	s.play("run")
	var shown := []
	for f in 24:
		s.frame = float(f) + 0.5
		s._apply()
		shown.append(int(s._mat.get_shader_parameter("frame")) - 4)
	assert_array(shown.slice(0, 7)).is_equal([0, 0, 0, 3, 3, 3, 6])
	# off: every frame
	s.pose_rate = 0
	s.frame = 4.5
	s._apply()
	assert_int(int(s._mat.get_shader_parameter("frame")) - 4).is_equal(4)
	s.free()


func test_a_creature_loop_holds_its_stride() -> void:
	var em := EnemyManager.new()
	em.anim_t.resize(1)
	em._t_step.append(2)
	var got := []
	for f in 6:
		em.anim_t[0] = float(f) + 0.25
		got.append(em._loop_frame(0, 0, 12))
	assert_array(got).is_equal([0, 0, 2, 2, 4, 4])
	em._t_step[0] = 1
	em.anim_t[0] = 13.0
	assert_int(em._loop_frame(0, 0, 12)).is_equal(1)
	em.free()
