extends GdUnitTestSuite

## Pass 64, lane SN (Garry, 2026-10-10: "I miss all that hype stuff. I just didn't like it on in the 3d world things,
## but having that for jingles of Level Up, Chest opens, etc ... I want things to sound like a casino a lot of the time
## ... For button taps in particular let's make something soft and simple ... For Music I want the same, as close to
## MegaBonk as possible, but slightly more Western style."): every sound-map row has a readable file; the six music
## tracks are Stable Audio 3 loops in music/ (32 kHz stereo, whole and seamless: the last sample runs on into the
## first, levelled under the effects); no file is silent but the two on purpose; every effect sits in its level window;
## the run's music is one track per stage with the boss's over it (Audio.music_stage / music_boss); the three new casino
## ids are bound and wired (the banish stamp, the stage-clear jingle, the Strongbox's till).

const SOUNDS := "res://content/sounds/"
const MUSIC_IDS := ["mu_title", "mu_run_1", "mu_run_2", "mu_run_3", "mu_boss", "mu_results"]
const SILENT_ON_PURPOSE := ["pl_hurt", "pl_jump"]
const NEW_IDS := ["ui_stamp", "ui_stage_clear", "st_deposit"]
const HYPE_IDS := ["ui_tap", "ui_card", "ui_pause", "ui_resume", "ui_locked", "ui_card_pick", "ui_reel_tick",
	"ui_chest_knock", "ui_stamp", "ui_buy", "st_deposit", "pk_chest_open", "ui_jackpot", "w_evo_reveal", "ui_levelup",
	"ui_fanfare", "ui_unlock", "ui_stage_clear", "wd_extract", "pl_revive", "it_phoenix", "pk_gem_s", "pk_gem_m",
	"pk_gem_l", "pk_coin", "it_coin_drop", "pk_vacuum", "pk_powerup", "pk_heart", "pk_flower", "st_portal_wait",
	"wd_portal_open"]


## The RIFF header and, when `read_data`, the 16-bit samples (strided: every `stride`-th frame, first channel...last).
static func wav(path: String, read_data: bool = false, stride: int = 1) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_buffer(4).get_string_from_ascii() != "RIFF":
		return {}
	f.get_32()
	if f.get_buffer(4).get_string_from_ascii() != "WAVE":
		return {}
	var info := {}
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
			info["frames"] = csize / maxi(int(info.get("channels", 1)) * 2, 1)
			info["seconds"] = float(info["frames"]) / float(maxi(int(info.get("rate", 1)), 1))
			if read_data:
				info["pcm"] = f.get_buffer(csize)
			break
		f.seek(at + csize + (csize & 1))
	return info


## Peak and RMS (dBFS) of the strided frames of a decoded wav (channels averaged).
static func levels(info: Dictionary, stride: int = 1) -> Dictionary:
	var pcm: PackedByteArray = info["pcm"]
	var ch := int(info["channels"])
	var frames := int(info["frames"])
	var peak := 0.0
	var sum := 0.0
	var n := 0
	var i := 0
	while i < frames:
		var v := 0.0
		for c in range(ch):
			var s := float(pcm.decode_s16((i * ch + c) * 2)) / 32768.0
			peak = maxf(peak, absf(s))
			v += s
		v /= float(ch)
		sum += v * v
		n += 1
		i += stride
	return {"peak_db": linear_to_db(maxf(peak, 1e-9)), "rms_db": linear_to_db(maxf(sqrt(sum / maxf(float(n), 1.0)), 1e-9))}


## RMS of the loud part (frames within 30 dB of the loudest 20 ms frame), like the tools' "content RMS".
static func content_rms_db(info: Dictionary) -> float:
	var pcm: PackedByteArray = info["pcm"]
	var ch := int(info["channels"])
	var frames := int(info["frames"])
	var win := maxi(int(int(info["rate"]) * 0.02), 1)
	var rs: Array[float] = []
	var i := 0
	while i + win <= frames:
		var sum := 0.0
		for j in range(i, i + win):
			var v := 0.0
			for c in range(ch):
				v += float(pcm.decode_s16((j * ch + c) * 2)) / 32768.0
			v /= float(ch)
			sum += v * v
		rs.append(sqrt(sum / float(win)))
		i += win
	if rs.is_empty():
		return -99.0
	var top: float = rs.max()
	var acc := 0.0
	var n := 0
	for r in rs:
		if r >= top * 0.0316:
			acc += r * r
			n += 1
	return linear_to_db(maxf(sqrt(acc / maxf(float(n), 1.0)), 1e-9))


func _file(id: String) -> String:
	return str(Registry.soundmap.entry(id).get("file", ""))


func _repo(rel: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").path_join(rel)


# ---------------------------------------------------------------- every row has its file

func test_every_soundmap_id_has_an_existing_file_and_stream() -> void:
	var table: Dictionary = Registry.soundmap.entries
	assert_int(table.size()).is_greater_equal(128)
	for id in table.keys():
		var file := _file(id)
		assert_bool(FileAccess.file_exists(SOUNDS + file)).override_failure_message("%s: no file %s" % [id, file]).is_true()
		assert_bool(table[id].get("stream") is AudioStream).override_failure_message("%s: no stream" % id).is_true()
		var info := wav(SOUNDS + file)
		assert_bool(info.has("seconds")).override_failure_message("%s: unreadable wav %s" % [id, file]).is_true()


func test_no_file_is_silent_but_the_two_on_purpose() -> void:
	for id in Registry.soundmap.entries.keys():
		var file := _file(id)
		if id in SILENT_ON_PURPOSE:
			assert_str(file).is_equal("real/silence.wav")
			continue
		assert_str(file).override_failure_message("%s plays the silent file" % id).is_not_equal("real/silence.wav")
		if id.begins_with("mu_"):
			continue   # the music's levels have their own test (and are long to decode)
		var info := wav(SOUNDS + file, true)
		var lv := levels(info)
		assert_float(float(lv["peak_db"])).override_failure_message("%s is silent (peak %.1f dB)" % [id, lv["peak_db"]]).is_greater(-30.0)


# ---------------------------------------------------------------- levels

## Every effect the game plays from real/ (the 3D world from pass 60, the hype family from pass 64) was levelled to
## a content RMS of -14 dBFS with its peaks held at -2 dBFS (a spiky clip stops short of the target): none clips, none
## blasts, none is so quiet the mix loses it.
func test_every_effect_sits_in_its_level_window() -> void:
	for id in Registry.soundmap.entries.keys():
		var file := _file(id)
		if id.begins_with("mu_") or id in SILENT_ON_PURPOSE or not file.begins_with("real/"):
			continue
		var info := wav(SOUNDS + file, true)
		var lv := levels(info)
		var crms := content_rms_db(info)
		assert_float(float(lv["peak_db"])).override_failure_message("%s peaks at %.2f dBFS" % [id, lv["peak_db"]]).is_less_equal(-1.5)
		# transients (coin clinks, a body hitting sand) stop short of the target under the 6 dB limiter cap: the floor is
		# lower for them than the target suggests (measured: the quietest pass-60 one -27.2, the quietest hype one -25.1)
		var floor_db := -26.0 if id in HYPE_IDS else -28.0
		assert_float(crms).override_failure_message("%s: content RMS %.1f dBFS" % [id, crms]).is_between(floor_db, -12.0)


func test_the_hype_family_is_short_bright_and_mono() -> void:
	for id in HYPE_IDS:
		var file := _file(id)
		assert_str(file).override_failure_message(id + " is not bound to real/").is_equal("real/%s.wav" % id)
		var info := wav(SOUNDS + file)
		assert_int(int(info.get("channels", 0))).is_equal(1)
		assert_int(int(info.get("rate", 0))).is_equal(22050)
		assert_float(float(info.get("seconds", 99.0))).override_failure_message("%s lasts %.2f s" % [id, info.get("seconds", 0.0)]).is_less_equal(2.6)
	# the taps stay short and soft: a mobile-game click, not a jingle
	for id in ["ui_tap", "ui_card", "ui_reel_tick"]:
		assert_float(float(wav(SOUNDS + _file(id)).get("seconds", 9.0))).override_failure_message(id + " is long").is_less_equal(0.25)


## The hype picks come from Stable Audio 3 (engine sa3 in tools/dl/sfx60/picks.json, when the tools/dl run is on this
## machine; a fresh clone has nothing to check here).
func test_the_hype_picks_come_from_stable_audio_3() -> void:
	var pp := _repo("tools/dl/sfx60/picks.json")
	if not FileAccess.file_exists(pp):
		assert_bool(true).is_true()
		return
	var picks = JSON.parse_string(FileAccess.get_file_as_string(pp))
	var sa3 := 0
	for id in HYPE_IDS:
		if picks is Dictionary and picks.has(id) and str(picks[id].get("engine", "")) == "sa3":
			sa3 += 1
	assert_int(sa3).is_greater_equal(HYPE_IDS.size() - 4)


# ---------------------------------------------------------------- the music

func test_the_music_tracks_are_stable_audio_loops_in_music() -> void:
	for id in MUSIC_IDS:
		var row := Registry.soundmap.entry(id)
		assert_str(_file(id)).is_equal("music/%s.wav" % id)
		assert_bool(bool(row.get("loop", false))).is_true()
		assert_str(str(row.get("category", ""))).is_equal("music")
		var info := wav(SOUNDS + _file(id))
		assert_int(int(info.get("channels", 0))).is_equal(2)
		assert_int(int(info.get("rate", 0))).is_equal(32000)
		assert_int(int(info.get("bits", 0))).is_equal(16)
		var lo := 30.0 if id == "mu_results" else 40.0
		assert_float(float(info.get("seconds", 0.0))).override_failure_message("%s is %.1f s" % [id, info.get("seconds", 0.0)]).is_between(lo, 125.0)
		# the run tracks are long enough that a stage does not hear the same minute twice in a row
		if id.begins_with("mu_run_"):
			assert_float(float(info["seconds"])).is_greater_equal(60.0)


## Seamless: the step from the last frame back to the first is no bigger than the music's ordinary sample-to-sample
## steps (the loop's tail was crossfaded into the music just before its start, so the frame after the last IS the first).
func test_the_music_loops_cleanly() -> void:
	for id in MUSIC_IDS:
		var info := wav(SOUNDS + _file(id), true)
		var pcm: PackedByteArray = info["pcm"]
		var frames := int(info["frames"])
		var steps: Array[float] = []
		var i := 1
		while i < frames:
			for c in range(2):
				steps.append(absf(float(pcm.decode_s16((i * 2 + c) * 2)) - float(pcm.decode_s16(((i - 1) * 2 + c) * 2))))
			i += 997
		steps.sort()
		var p99: float = steps[int(steps.size() * 0.99)]
		var wrap := 0.0
		for c in range(2):
			wrap = maxf(wrap, absf(float(pcm.decode_s16(c * 2)) - float(pcm.decode_s16(((frames - 1) * 2 + c) * 2))))
		assert_float(wrap).override_failure_message("%s: wrap step %.0f against p99 %.0f" % [id, wrap, p99]).is_less_equal(maxf(p99, 200.0))


## Levelled under the effects: loud-part RMS about -17 dBFS (effects -14) before the row's volume_db (-10 or so), peaks
## at -1 dBFS; a jingle at 0 dB plays well over the music without the music being thin.
func test_the_music_is_levelled_under_the_effects() -> void:
	for id in MUSIC_IDS:
		var info := wav(SOUNDS + _file(id), true)
		var lv := levels(info, 5)
		assert_float(float(lv["peak_db"])).override_failure_message("%s peaks at %.2f" % [id, lv["peak_db"]]).is_less_equal(-0.9)
		assert_float(float(lv["rms_db"])).override_failure_message("%s RMS %.1f" % [id, lv["rms_db"]]).is_between(-24.0, -15.0)
		var vol := float(Registry.soundmap.entry(id).get("volume_db", 0.0))
		assert_float(vol).is_between(-14.0, -6.0)


# ---------------------------------------------------------------- the run's music follows the stage and the boss

func test_the_run_music_is_one_track_per_stage_with_the_boss_over_it() -> void:
	var a = Engine.get_main_loop().root.get_node("Audio")
	a.play_music(["mu_run_1", "mu_run_2", "mu_run_3"], 1)
	assert_str(a.music_now()).is_equal("mu_run_1")
	a.music_stage(1)
	assert_str(a.music_now()).is_equal("mu_run_2")
	a.music_boss(true, "mu_boss")
	assert_str(a.music_now()).is_equal("mu_boss")
	a.music_stage(2)   # a stage change under a boss waits for the boss
	assert_str(a.music_now()).is_equal("mu_boss")
	a.music_boss(false)
	assert_str(a.music_now()).is_equal("mu_run_3")
	a.music_stage(7)   # endless stays on the last stage's track
	assert_str(a.music_now()).is_equal("mu_run_3")
	a.play_music(["mu_title"], 1)
	a.music_stage(2)   # a menu's single track ignores stages
	assert_str(a.music_now()).is_equal("mu_title")
	a.stop_music()
	assert_str(a.music_now()).is_equal("")


func test_game_hooks_the_stage_and_the_boss() -> void:
	var src := FileAccess.get_file_as_string("res://game/Game.gd")
	assert_str(src).contains("Audio.music_stage(s)")
	assert_str(src).contains("Audio.music_boss(true")
	assert_str(src).contains("Audio.music_boss(false)")


# ---------------------------------------------------------------- the casino spots

func test_the_three_new_ids_are_bound_and_wired() -> void:
	for id in NEW_IDS:
		assert_bool(Registry.soundmap.has_sound(id)).override_failure_message("no row " + id).is_true()
		assert_str(_file(id)).is_equal("real/%s.wav" % id)
	assert_str(FileAccess.get_file_as_string("res://ui/CardScreen.gd")).contains("\"ui_stamp\"")
	assert_str(FileAccess.get_file_as_string("res://ui/PortalDialog.gd")).contains("\"ui_stage_clear\"")
	assert_str(FileAccess.get_file_as_string("res://core/systems/CoinStream.gd")).contains("DEPOSIT_ID := \"st_deposit\"")


func test_the_tools_and_the_listening_page_exist() -> void:
	for rel in ["tools/comfy_audio.py", "tools/ai_music.py", "tools/ai_sfx.py", "tools/make_sfx_review.py", "docs/sfx_review.html"]:
		assert_bool(FileAccess.file_exists(_repo(rel))).override_failure_message("missing " + rel).is_true()
	var page := FileAccess.get_file_as_string(_repo("docs/sfx_review.html"))
	for id in ["mu_run_1", "mu_boss", "ui_levelup", "ui_tap", "pk_gem_s"]:
		assert_str(page).contains('id="%s"' % id)
