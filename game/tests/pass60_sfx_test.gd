extends GdUnitTestSuite

## Pass 60, lane SFX (Garry, 2026-10-08: "I don't quite like how high pitched everything is ... regenerate them ...
## Remove all the voice effects, including hit sounds, all that voice stuff"; later: "I switched from using AudioCraft
## to now using Stable Audio 3"): every sound-map row has its file and a stream; no row points into voice/ and the
## folder is gone; the six music rows and files are untouched (44.1 kHz, the same bytes); pl_hurt and pl_jump are the
## 50 ms silence; every real/*.wav is mono 22050 Hz 16-bit and no longer than 4.5 s (loops) / 2.5 s (the rest); the 118
## non-music ids of this pass (+ pk_nuke, the Nuke's own blast) all play from real/; the listening page and
## tools/ai_sfx.py exist; the picks come from
## Stable Audio first and the picked set reads lower than the placeholders did (tools/dl/sfx60/picks.json +
## <engine>/scores.json, when the tools/dl run is on this machine).

const SOUNDS := "res://content/sounds/"
const MUSIC := {"mu_title": 2016044, "mu_run_1": 1282952, "mu_run_2": 1282952, "mu_run_3": 1282952, "mu_boss": 1085582,
	"mu_results": 1814444}
const SILENCED := ["pl_hurt", "pl_jump"]
const REPLACED := ["ui_levelup", "ui_unlock", "wd_extract", "en_elite_spawn", "en_boss_roar", "en_boss_die", "pl_revive",
	"pl_death"]
const LOOPS := ["w_saw_loop", "w_snake_rattle", "wd_ambient", "wd_portal_open", "wd_dust_devil"]
const SFX_IDS := ["ui_tap", "ui_card_pick", "ui_levelup", "ui_pause", "ui_resume", "ui_buy", "ui_locked", "ui_unlock",
	"pl_step_sand", "pl_jump", "pl_land", "pl_spawn_beam", "pl_spawn_land", "pl_hurt", "pl_death", "pl_revive",
	"w_pea_fire", "w_pea_hit", "w_boom_fire", "w_boom_hit", "w_saw_loop", "w_saw_hit", "w_lob_throw", "w_lob_boom",
	"w_zap_fire", "w_zap_hit", "w_turret_place", "w_turret_fire", "w_evo_reveal", "pk_gem_s", "pk_gem_m", "pk_gem_l",
	"pk_coin", "pk_chest_open", "pk_vacuum", "en_goblin_hit", "en_goblin_die", "en_ant_hit", "en_ant_die",
	"en_cactus_spit", "en_cactus_die", "en_beetle_charge", "en_beetle_die", "en_lizard_die", "en_mummy_die",
	"en_scorpion_die", "en_elite_spawn", "en_boss_roar", "en_boss_attack", "en_boss_die", "en_king_volley",
	"wd_ambient", "wd_portal_open", "wd_extract", "wd_dust_devil", "wd_tumbleweed", "w_tumble_roll", "w_tumble_hit",
	"w_snake_rattle", "w_snake_bite", "w_skull_throw", "w_skull_boom", "w_flare_fire", "w_flare_hit", "w_molotov_throw",
	"w_molotov_boom", "w_iron_hit", "w_ignite", "w_tommy_fire", "w_mine_arm", "pk_powerup", "pk_heart", "en_bone_hit",
	"en_bone_die", "en_rocket_boom", "en_rocket_loose", "en_rocket_wild", "en_rocket_dive", "w_hammer_swing",
	"w_hammer_hit", "w_revolver_fire", "w_grav_grab", "w_grav_throw", "w_grav_land", "w_blackhole", "st_teleport",
	"w_guitarra_strum", "w_sun_warn", "w_sun_strike", "w_sun_zenith", "w_spear_throw", "w_spear_hit", "en_slime_hit",
	"en_slime_die", "en_golem_attack", "en_golem_throw", "en_golem_hit", "en_golem_die", "en_boulder_land",
	"en_stalactite_hit", "st_barrel_break", "ui_fanfare", "ui_jackpot", "wd_gust", "ui_chest_knock", "w_thor_zap",
	"w_tinnitus_ring", "w_hawk_sting", "w_hip_spin", "w_silver_fire", "w_mine_spring", "it_keg_boom", "it_phoenix",
	"it_coin_drop", "pk_flower", "st_portal_wait", "ui_reel_tick", "ui_card", "pk_nuke"]


## The RIFF header of a wav: format, channels, rate, bits, data bytes and seconds. Read from the source file, not the
## imported stream, because the import compresses (compress/mode 2) and would hide the bit depth.
static func wav_info(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	if f.get_buffer(4).get_string_from_ascii() != "RIFF":
		return {}
	f.get_32()
	if f.get_buffer(4).get_string_from_ascii() != "WAVE":
		return {}
	var info := {"bytes": f.get_length()}
	while f.get_position() + 8 <= f.get_length():
		var cid := f.get_buffer(4).get_string_from_ascii()
		var csize := f.get_32()
		var at := f.get_position()
		if cid == "fmt ":
			info["format"] = f.get_16()
			info["channels"] = f.get_16()
			info["rate"] = f.get_32()
			f.get_32()
			f.get_16()
			info["bits"] = f.get_16()
		elif cid == "data":
			info["data"] = csize
			break
		f.seek(at + csize + (csize & 1))
	if info.has("data") and info.has("rate") and int(info["rate"]) > 0:
		var frame := int(info["channels"]) * int(info["bits"]) / 8
		info["seconds"] = float(info["data"]) / float(int(info["rate"]) * maxi(frame, 1))
	return info


func _repo(rel: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").path_join(rel)


func _file_of(id: String) -> String:
	var row := Registry.soundmap.entry(id)
	return str(row.get("file", ""))


# ---------------------------------------------------------------- every row plays

func test_every_row_has_its_file_and_stream() -> void:
	var table: Dictionary = Registry.soundmap.entries
	assert_int(table.size()).is_greater_equal(124)
	for id in table.keys():
		var row: Dictionary = table[id]
		var file := str(row.get("file", ""))
		assert_bool(FileAccess.file_exists(SOUNDS + file)).override_failure_message("%s: no file %s" % [id, file]).is_true()
		assert_bool(row.get("stream") is AudioStream).override_failure_message("%s: no stream for %s" % [id, file]).is_true()


func test_the_rows_the_older_tests_need_are_still_there() -> void:
	for id in ["en_slime_hit", "en_slime_die", "st_barrel_break", "ui_fanfare", "ui_jackpot", "wd_gust", "en_king_volley",
			"w_tumble_hit", "en_golem_attack", "en_golem_throw", "en_golem_hit", "en_golem_die", "en_boulder_land",
			"en_stalactite_hit", "pl_spawn_beam", "pl_spawn_land", "en_rocket_loose", "en_rocket_wild", "en_rocket_dive",
			"w_sun_warn", "w_sun_strike", "w_sun_zenith"]:
		assert_bool(Registry.soundmap.has_sound(id)).override_failure_message("missing row " + id).is_true()


# ---------------------------------------------------------------- the voices are gone

func test_no_row_points_into_voice_and_the_folder_is_gone() -> void:
	for id in Registry.soundmap.entries.keys():
		assert_str(_file_of(id)).override_failure_message("%s still plays a voice file" % id).not_contains("voice/")
	assert_bool(DirAccess.dir_exists_absolute(SOUNDS + "voice")).is_false()
	assert_bool(FileAccess.file_exists(_repo("tools/gen_voice.py"))).is_false()


func test_the_silenced_ids_play_the_silent_file() -> void:
	for id in SILENCED:
		assert_str(_file_of(id)).is_equal("real/silence.wav")
	var info := wav_info(SOUNDS + "real/silence.wav")
	assert_bool(info.has("seconds")).is_true()
	assert_float(float(info["seconds"])).is_less(0.1)
	assert_int(int(info["channels"])).is_equal(1)
	assert_int(int(info["rate"])).is_equal(22050)


func test_the_replaced_voice_ids_have_their_own_sounds() -> void:
	for id in REPLACED:
		assert_str(_file_of(id)).is_equal("real/%s.wav" % id)
		var info := wav_info(SOUNDS + "real/%s.wav" % id)
		assert_float(float(info.get("seconds", 0.0))).override_failure_message("%s is too short to be a sound" % id).is_greater(0.3)


# ---------------------------------------------------------------- the music is untouched

## Re-pinned in pass 64: the music rows now play the Stable Audio 3 loops in music/ (pass64_sn_test checks them); the
## procedural placeholders stay on disk, untouched, as the fallback files.
func test_the_six_music_rows_and_files_are_untouched() -> void:
	for id in MUSIC.keys():
		assert_str(_file_of(id)).is_equal("music/%s.wav" % id)
		var info := wav_info(SOUNDS + "placeholder/%s.wav" % id)
		assert_int(int(info.get("rate", 0))).is_equal(44100)
		assert_int(int(info.get("bytes", 0))).override_failure_message("%s changed size" % id).is_equal(int(MUSIC[id]))
		var row := Registry.soundmap.entry(id)
		assert_bool(bool(row.get("loop", false))).is_true()
		assert_str(str(row.get("category", ""))).is_equal("music")


# ---------------------------------------------------------------- the real set

func test_every_real_wav_is_mono_22050_16bit_and_short() -> void:
	var files := DirAccess.get_files_at(SOUNDS + "real")
	var wavs := 0
	for fn in files:
		if not fn.ends_with(".wav"):
			continue
		wavs += 1
		var info := wav_info(SOUNDS + "real/" + fn)
		assert_int(int(info.get("format", 0))).override_failure_message(fn + " is not PCM").is_equal(1)
		assert_int(int(info.get("channels", 0))).override_failure_message(fn + " is not mono").is_equal(1)
		assert_int(int(info.get("rate", 0))).override_failure_message(fn + " is not 22050 Hz").is_equal(22050)
		assert_int(int(info.get("bits", 0))).override_failure_message(fn + " is not 16-bit").is_equal(16)
		var id := fn.get_basename()
		var cap := 4.5 if id in LOOPS else 2.5
		assert_float(float(info.get("seconds", 99.0))).override_failure_message("%s is longer than %.1f s" % [fn, cap]).is_less_equal(cap)
	# 117 generated sounds (116 of the pass + pk_nuke) + silence.wav
	assert_int(wavs).is_greater_equal(118)


func test_the_loops_are_textures_not_blips() -> void:
	for id in LOOPS:
		var info := wav_info(SOUNDS + "real/%s.wav" % id)
		assert_float(float(info.get("seconds", 0.0))).override_failure_message("%s is too short for a loop" % id).is_greater_equal(1.9)


func test_every_sfx_id_of_this_pass_plays_from_real() -> void:
	# the 118 ids of the sound map at the start of the pass + pk_nuke, the Nuke's own blast (Game.nuke_blast had played
	# en_boss_die, the Tumbleweed King's old "My crown!" bark)
	assert_int(SFX_IDS.size()).is_equal(119)
	for id in SFX_IDS:
		var file := _file_of(id)
		assert_bool(file.begins_with("real/")).override_failure_message("%s still plays %s" % [id, file]).is_true()
		var info := wav_info(SOUNDS + file)
		assert_bool(info.has("seconds")).override_failure_message("%s: unreadable wav %s" % [id, file]).is_true()


# ---------------------------------------------------------------- the review page and the register

func test_the_listening_page_and_the_tool_exist() -> void:
	assert_bool(FileAccess.file_exists(_repo("docs/sfx_review.html"))).is_true()
	assert_bool(FileAccess.file_exists(_repo("tools/ai_sfx.py"))).is_true()
	assert_bool(FileAccess.file_exists(_repo("tools/audiocraft_sfx.py"))).is_false()
	assert_bool(FileAccess.file_exists(_repo("tools/make_sfx_review.py"))).is_true()
	var page := FileAccess.get_file_as_string(_repo("docs/sfx_review.html"))
	for id in ["pk_gem_s", "en_boss_roar", "wd_ambient", "ui_tap"]:
		assert_str(page).contains('id="%s"' % id)


## The pick is the candidate with the lowest centroid that passed its kind's ceiling (and is not mostly sub-bass);
## across the set the new sounds should read lower than the synthetic placeholders, and they come from Stable Audio
## (the AudioGen alternate only where every Stable candidate failed). picks.json and <engine>/scores.json live in the
## git-ignored tools/dl: without them (a fresh clone) there is nothing to check here.
func test_the_picked_set_reads_lower_than_the_placeholders_and_comes_from_stable() -> void:
	var pp := _repo("tools/dl/sfx60/picks.json")
	if not FileAccess.file_exists(pp):
		assert_bool(true).is_true()
		return
	var picks = JSON.parse_string(FileAccess.get_file_as_string(pp))
	assert_bool(picks is Dictionary).is_true()
	var scores := {}
	for engine in ["stable", "audiogen"]:
		var sp := _repo("tools/dl/sfx60/%s/scores.json" % engine)
		if FileAccess.file_exists(sp):
			scores[engine] = JSON.parse_string(FileAccess.get_file_as_string(sp))
	var n := 0
	var lower := 0
	var stable := 0
	for id in picks.keys():
		var engine := str(picks[id].get("engine", "audiogen"))
		# pass 64: the UI, reward and pickup ids moved to Stable Audio 3 (engine sa3) in a brighter register on purpose
		if engine == "stable" or engine == "sa3":
			stable += 1
		var s = scores.get(engine, {}).get(id)
		if not (s is Dictionary) or not (s.get("old") is Dictionary):
			continue
		var k := int(picks[id].get("k", -1))
		for c in s.get("cands", []):
			if int(c.get("k", -2)) == k:
				n += 1
				if float(c.get("centroid", 0.0)) < float(s["old"].get("centroid", 0.0)):
					lower += 1
	assert_int(n).is_greater_equal(80)   # pass 64: 119 less the 32 hype ids now on sa3
	assert_float(float(lower) / float(maxi(n, 1))).is_greater(0.5)
	assert_float(float(stable) / float(maxi(picks.size(), 1))).is_greater(0.8)
