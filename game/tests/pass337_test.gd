extends GdUnitTestSuite

## Pass 33.7: 30% less camera zoom, the specials 45 to 60 seconds apart, two more weapon slots in stage 2, the harpooner
## at half its HP.


func test_the_camera_pulls_out_a_third_less() -> void:
	var rig: CameraRig = auto_free(CameraRig.new())
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	rig.add_child(cam)
	add_child(rig)
	var hero: CharacterBody3D = auto_free(CharacterBody3D.new())
	add_child(hero)
	rig.snap_to(hero)
	assert_float(rig.zoom_amount).is_equal_approx(0.7, 0.001)
	# flat out at any speed, the widest the camera goes is 1 + 1.6 x 0.7
	hero.velocity = Vector3(200.0, 0, 0)
	rig._update(1.0)
	assert_float(rig.zoom()).is_equal_approx(1.0 + (rig.zoom_max - 1.0) * 0.7, 0.01)
	assert_float(rig.zoom()).is_less(2.2)


func test_specials_slots_and_the_harpooner() -> void:
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	var iv: Array = tl.specials.get("interval", [])
	assert_float(float(iv[0])).is_equal(45.0)
	assert_float(float(iv[iv.size() - 1])).is_equal(60.0)
	# stage 1 four weapons, stage 2 six (two more instead of one), stage 3 six
	assert_int(tl.weapon_cap_at(0)).is_equal(4)
	assert_int(tl.weapon_cap_at(1)).is_equal(6)
	assert_int(tl.weapon_cap_at(2)).is_equal(6)
	# 70 in pass 33.7; since pass 33.8 the rocketeer's (pass338_test)
	assert_float(Registry.enemy("harpoon_troglodyte").hp).is_equal_approx(Registry.enemy("rocketeer").hp, 0.01)
