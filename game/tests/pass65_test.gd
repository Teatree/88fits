## Pass 65: the blob shadows lie on the slope (EnemyManager.drape), the gem dings by size (rising on quick repeats), the
## hero's chiptune hurt (rate-limited) and the slot machine's sequence round the reels (WSlotSound).
extends GdUnitTestSuite

const SlotScript := preload("res://ui/wanted/WSlotSound.gd")
const ReelScript := preload("res://ui/wanted/WWeaponReel.gd")
const Pass64 := preload("res://tests/pass64_sn_test.gd")
const SOUNDS := "res://content/sounds/"


func _row(id: String) -> Dictionary:
	return Registry.soundmap.entry(id)


func _seconds(id: String) -> float:
	return float(Pass64.wav(SOUNDS + str(_row(id).get("file", ""))).get("seconds", 0.0))


func _check_drape(h: Callable, at: Vector3, sx: float, sz: float, yaw: float) -> void:
	var flat := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(sx, 1.0, sz))
	var xf := EnemyManager.drape(Transform3D(flat, at), h)
	# the quad's up follows the ground's normal there
	var e := 0.05
	var n := Vector3(-(float(h.call(at.x + e, at.z)) - float(h.call(at.x - e, at.z))) / (2 * e), 1.0,
		-(float(h.call(at.x, at.z + e)) - float(h.call(at.x, at.z - e))) / (2 * e)).normalized()
	assert_float(xf.basis.y.normalized().dot(n)).is_greater(0.98)
	# no corner, edge or the middle under the sand
	for u in [-0.5, 0.0, 0.5]:
		for v in [-0.5, 0.0, 0.5]:
			var p: Vector3 = xf.origin + xf.basis.x * u + xf.basis.z * v
			assert_float(p.y).override_failure_message("point %s,%s at %s under the ground %s" % [u, v, p, h.call(p.x, p.z)]).is_greater_equal(float(h.call(p.x, p.z)) + 0.005)
	# and it is not floating either
	assert_float(xf.origin.y - float(h.call(at.x, at.z))).is_less(0.4)


func test_shadows_lie_on_slopes() -> void:
	var slope := func(x: float, z: float) -> float: return 0.45 * x - 0.3 * z + 1.0
	var dish := func(x: float, z: float) -> float: return 0.08 * (x * x + z * z)
	var dune := func(x: float, z: float) -> float: return 1.2 * sin(x * 0.6) + 0.5 * cos(z * 0.8)
	for h: Callable in [slope, dish, dune]:
		for at: Vector3 in [Vector3(0, 0, 0), Vector3(2.5, 0, -1.0), Vector3(-3.0, 0, 4.0)]:
			_check_drape(h, at, 0.9, 0.6, 0.7)
			_check_drape(h, at, 2.0, 1.3, -1.9)
	# flat ground: the old flat quad, a hair up
	var flat := func(_x: float, _z: float) -> float: return 2.0
	var xf := EnemyManager.drape(Transform3D(Basis.from_scale(Vector3(1, 1, 0.6)), Vector3(1, 0, 1)), flat)
	assert_float(xf.origin.y).is_equal_approx(2.0 + EnemyManager.SHADOW_LIFT, 0.001)
	assert_float(xf.basis.y.normalized().y).is_equal_approx(1.0, 0.0001)


func test_the_creatures_and_hero_use_the_drape() -> void:
	var em := FileAccess.get_file_as_string("res://core/systems/EnemyManager.gd")
	assert_str(em).contains("return drape(Transform3D(Basis(scr")
	var game := FileAccess.get_file_as_string("res://game/Game.gd")
	assert_str(game).contains("_drape_hero_shadow()")
	assert_str(game).contains("EnemyManager.drape(")


func test_each_gem_size_dings_its_own_id_and_bigger_is_stronger() -> void:
	var pm := FileAccess.get_file_as_string("res://core/systems/PickupManager.gd")
	for id in ["pk_gem_s", "pk_gem_m", "pk_gem_l"]:
		assert_str(pm).contains("Audio.play(\"%s\")" % id)
		assert_str(str(_row(id).get("file", ""))).is_equal("real/%s.wav" % id)
		assert_bool(_row(id).get("stream") is AudioStream).is_true()
		assert_float(float(_row(id).get("chain_step", 0.0))).is_greater(0.0)
	assert_float(float(_row("pk_gem_l")["volume_db"])).is_greater(float(_row("pk_gem_m")["volume_db"]))
	assert_float(float(_row("pk_gem_m")["volume_db"])).is_greater(float(_row("pk_gem_s")["volume_db"]))
	assert_float(_seconds("pk_gem_l")).is_greater(_seconds("pk_gem_m"))
	assert_float(_seconds("pk_gem_m")).is_greater(_seconds("pk_gem_s"))


func test_quick_gems_climb_in_pitch_then_start_again() -> void:
	var row := {"chain_step": 1.0, "chain_window": 0.3, "chain_max": 3.0}
	var a: Node = Audio
	a._chain.erase("t65")
	assert_float(a.chain_pitch("t65", row, 1000)).is_equal_approx(1.0, 0.0001)
	assert_float(a.chain_pitch("t65", row, 1100)).is_equal_approx(pow(2.0, 1.0 / 12.0), 0.0001)
	a.chain_pitch("t65", row, 1200)
	a.chain_pitch("t65", row, 1300)
	assert_float(a.chain_pitch("t65", row, 1400)).is_equal_approx(pow(2.0, 3.0 / 12.0), 0.0001)
	assert_float(a.chain_pitch("t65", row, 3000)).is_equal_approx(1.0, 0.0001)
	assert_float(a.chain_pitch("t65", {}, 3100)).is_equal(1.0)


func test_the_hero_hurt_has_a_sound_and_is_rate_limited() -> void:
	var row := _row("pl_hurt")
	assert_str(str(row["file"])).is_equal("real/pl_hurt.wav")
	assert_bool(row.get("stream") is AudioStream).is_true()
	assert_float(_seconds("pl_hurt")).is_between(0.08, 0.4)
	assert_float(float(row.get("min_gap", 0.0))).is_greater_equal(0.15)
	assert_str(FileAccess.get_file_as_string("res://player/Player.gd")).contains("Audio.play(\"pl_hurt\", global_position)")
	var a: Node = Audio
	a._last_any.erase("pl_hurt")
	a._last_played.erase("pl_hurt")
	a.play("pl_hurt")
	var first: int = int(a._last_any["pl_hurt"])
	a.play("pl_hurt")
	assert_int(int(a._last_any["pl_hurt"])).is_equal(first)
	assert_int((a._last_played["pl_hurt"] as Array).size()).is_equal(1)


func test_the_slot_sequence_runs_in_order_and_the_loop_stops() -> void:
	var s = SlotScript.new()
	s.begin()
	assert_bool(Audio.loop_playing("ui_slot_spin")).is_true()
	s.feed(100.0)
	s.land()
	assert_bool(Audio.loop_playing("ui_slot_spin")).is_false()
	assert_array(s.events).is_equal(["ui_slot_start", "ui_slot_spin", "ui_slot_stop"])
	var c = SlotScript.new()
	c.begin()
	c.cancel()
	assert_bool(Audio.loop_playing("ui_slot_spin")).is_false()
	assert_array(c.events).is_equal(["ui_slot_start", "ui_slot_spin", "cancel"])


func _weapons(n: int) -> Array:
	var out: Array = []
	for w in Registry.weapons.values():
		out.append(w)
		if out.size() >= n:
			break
	return out


func test_the_weapon_reel_plays_start_spin_stop_then_jackpot() -> void:
	var defs := _weapons(3)
	var reel = auto_free(ReelScript.new())
	add_child(reel)
	reel.play(defs, defs[1], 1.5)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	assert_bool(Audio.loop_playing("ui_slot_spin")).is_true()
	reel.skip()
	assert_array(reel.slot.events).is_equal(["ui_slot_start", "ui_slot_spin", "ui_slot_stop"])
	assert_bool(Audio.loop_playing("ui_slot_spin")).is_false()


func test_closing_the_weapon_reel_mid_spin_stops_the_loop() -> void:
	var defs := _weapons(3)
	var reel = ReelScript.new()
	add_child(reel)
	reel.play(defs, defs[0], 1.5)
	await get_tree().create_timer(0.2).timeout
	assert_bool(Audio.loop_playing("ui_slot_spin")).is_true()
	reel.visible = false
	assert_bool(Audio.loop_playing("ui_slot_spin")).is_false()
	reel.queue_free()


func test_the_chest_screen_wires_the_sequence() -> void:
	var src := FileAccess.get_file_as_string("res://ui/ChestScreen.gd")
	assert_str(src).contains("slot.begin()")
	var land_at := src.find("slot.land()")
	assert_int(land_at).is_greater(0)
	assert_int(src.find("\"ui_jackpot\")", land_at)).is_greater(land_at)
	assert_str(src).contains("slot.cancel()")
	assert_str(src).contains("NOTIFICATION_VISIBILITY_CHANGED")


func test_every_soundmap_id_has_a_file() -> void:
	for id in Registry.soundmap.entries.keys():
		var file := str(_row(id).get("file", ""))
		var path := file if file.begins_with("res://") else SOUNDS + file
		assert_bool(FileAccess.file_exists(path)).override_failure_message("%s: no file %s" % [id, file]).is_true()
	for id in ["ui_slot_start", "ui_slot_spin", "ui_slot_stop"]:
		assert_bool(_row(id).get("stream") is AudioStream).override_failure_message(id).is_true()
	assert_bool(bool(_row("ui_slot_spin").get("loop", false))).is_true()
