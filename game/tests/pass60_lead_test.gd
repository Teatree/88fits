## Pass 60, the lead's pieces: run_summary carries the rest of the local dashboard's curves (Garry: "Run Curves doesn't
## seem to contain all of the dashboard.html stuff") and a readable line of the final build.
class_name Pass60LeadTest
extends GdUnitTestSuite


func _row(t: float, extra: Dictionary) -> Dictionary:
	var r := {"t": t, "stage": 1, "level": 3, "alive": 10, "cap": 20, "hp": 50.0, "hp_max": 100.0, "xp": 30.0, "xp_next": 60.0,
		"gold": 40, "banked": 10, "kills": 7, "phase": 0, "load": 8.5, "hard_cap": 240, "est_total": 12.0}
	r.merge(extra, true)
	return r


func test_summary_carries_the_new_curves() -> void:
	var rows: Array = []
	for s in range(1, 61):
		rows.append(_row(float(s), {"shield": 4.0 if s <= 30 else 0.0, "invuln": 1 if s <= 6 else 0, "took_raw": 2.0,
			"evaded": 1 if s % 10 == 0 else 0, "shielded": 0.5, "healed": 0.25, "dmg": {"peashooter": 3.0, "sabre": 1.0},
			"took_kind": {"melee": 1.0, "ranged": 0.5}}))
	for s in range(61, 91):
		rows.append(_row(float(s), {"shield": 0.0, "took_raw": 1.0, "dmg": {"sabre": 5.0}, "kills": 20, "banked": 50, "phase": 1,
			"xp": 15.0, "xp_next": 60.0}))
	var s := RunAnalytics.summary(rows)
	assert_array(s["m_secs"]).is_equal([60, 30])
	assert_array(s["m_hp_max"]).is_equal([100, 100])
	assert_that(float(s["m_shield"][0])).is_equal_approx(2.0, 0.051)
	assert_that(float(s["m_shield"][1])).is_equal_approx(0.0, 0.001)
	assert_array(s["m_shield_s"]).is_equal([30, 0])
	assert_array(s["m_invuln_s"]).is_equal([6, 0])
	assert_that(float(s["m_took_raw"][0])).is_equal_approx(120.0, 0.11)
	assert_that(float(s["m_took_raw"][1])).is_equal_approx(30.0, 0.11)
	assert_array(s["m_evaded"]).is_equal([6, 0])
	assert_that(float(s["m_shielded"][0])).is_equal_approx(30.0, 0.11)
	assert_that(float(s["m_healed"][0])).is_equal_approx(15.0, 0.11)
	assert_that(float(s["m_load"][0])).is_equal_approx(8.5, 0.051)
	assert_array(s["m_hard_cap"]).is_equal([240, 240])
	assert_that(float(s["m_xp"][0])).is_equal_approx(0.5, 0.011)
	assert_that(float(s["m_xp"][1])).is_equal_approx(0.25, 0.011)
	assert_array(s["m_banked"]).is_equal([10, 50])
	assert_array(s["m_kills"]).is_equal([7, 20])
	assert_array(s["m_phase"]).is_equal([0, 1])
	# each weapon's damage minute by minute
	var by: Dictionary = s["dmg_by_minute"]
	assert_array(by["peashooter"]).is_equal([180, 0])
	assert_array(by["sabre"]).is_equal([60, 150])
	assert_dict(s["took_kind"]).is_equal({"melee": 60.0, "ranged": 30.0})
	# the old keys are still there
	assert_dict(s).contains_keys(["m_alive", "m_cap", "m_press", "m_est", "m_dmg", "m_hp", "m_took", "m_gold", "dmg_by_weapon"])


func test_dmg_by_minute_keeps_the_top_eight_weapons() -> void:
	var rows: Array = []
	var dmg := {}
	for k in range(12):
		dmg["w%d" % k] = float(k + 1)
	rows.append(_row(1.0, {"dmg": dmg}))
	var s := RunAnalytics.summary(rows)
	var by: Dictionary = s["dmg_by_minute"]
	assert_int(by.size()).is_equal(8)
	assert_bool(by.has("w11")).is_true()
	assert_bool(by.has("w0")).is_false()


func test_empty_summary_has_the_new_keys() -> void:
	var s := RunAnalytics.summary([])
	assert_dict(s).contains_keys(["m_shield", "m_took_raw", "m_load", "m_xp", "m_kills", "dmg_by_minute", "took_kind"])
	assert_int(int(s["minutes"])).is_equal(0)


func test_build_text_reads_as_one_line() -> void:
	var ra := RunAnalytics.new()
	var text := ra.build_text({"weapons": [{"id": "peashooter", "level": 3, "mutations": ["toxic_peas"]}, {"id": "sabre", "level": 1, "mutations": []}],
		"passives": {"clover": 2}, "perks": []})
	ra.free()
	assert_str(text).contains("Peashooter 3 +1")
	assert_str(text).contains("Sabre 1")
	# pass 73 (lane CARDS): Clover is the card The Star (the line reads display names; the ids go out as ids)
	assert_str(text).contains(Registry.passive("clover").display_name + " 2")
	assert_str(text).contains(" | ")
	assert_str(text).not_contains("+0")


func test_fit_summary_stays_in_minute_buckets_for_a_long_run() -> void:
	# a 25-minute run with the new arrays still fits SUMMARY_MAX in minute buckets
	var rows: Array = []
	for s in range(1, 1501):
		rows.append(_row(float(s), {"shield": 1.0, "took_raw": 1.0, "evaded": 0, "shielded": 0.1, "healed": 0.1,
			"dmg": {"peashooter": 3.0, "sabre": 1.0, "rocket_pod": 2.0, "tommy_gun": 4.0, "orbit_saws": 1.0},
			"took": {"skeleton": 1.0, "goblin": 0.5}, "spawned": {"skeleton": 2}, "killed": {"skeleton": 1},
			"took_kind": {"melee": 1.0}, "est": {"peashooter": 3.0, "sabre": 1.0}}))
	var s := RunAnalytics.fit_summary(rows)
	assert_int(int(s["bucket_s"])).is_equal(60)
	assert_int(int(s["minutes"])).is_equal(25)
	assert_int(JSON.stringify(s).length()).is_less(RunAnalytics.SUMMARY_MAX)
