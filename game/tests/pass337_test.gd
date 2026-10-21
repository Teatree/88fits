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
	assert_float(float(iv[0])).is_equal(64.0)  # pass 46: 45-60 s stretched by 430/300
	assert_float(float(iv[iv.size() - 1])).is_equal(86.0)
	# pass 47: six weapon slots on every stage (Garry: the caps never change); were four, six, six
	assert_int(tl.weapon_cap_at(0)).is_equal(5)
	assert_int(tl.weapon_cap_at(1)).is_equal(5)
	assert_int(tl.weapon_cap_at(2)).is_equal(5)
	# 70 in pass 33.7; the rocketeer's from pass 33.8 (both 50 since pass 45); pass 48 took the rocketeer (the Vulture
	# Raider) down to 35 and left the harpooner at 50 (pass338_test)
	assert_float(Registry.enemy("harpoon_troglodyte").hp).is_equal_approx(float(JSON.parse_string(FileAccess.get_file_as_string("res://content/enemies/harpoon_troglodyte/harpoon_troglodyte.json"))["hp"]), 0.01)  # pass 95 (lead): Garry hand-tunes these (150 / 100 today): the pins read his file
