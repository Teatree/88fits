extends GdUnitTestSuite

## Pass 87, lane FADE (Garry: "Fadeaway - Still has some problems: the size problem, they are inconsistent: run front is
## considerably larger than front stand ...; back run shoulders look slouched; back 3/4 right/left the back number 88 is
## gone. Make 2 new versions (trying a more precise and less precise prompts)"): two fresh looks, FAD-E (the precise,
## detailed prompt) and FAD-F (the loose, short one), on their own paintings, the back-diagonal painted from the front
## and the back still (the 88 stays on his back), walked on the puppet's stick figure with the neck on the shoulder line
## and the head lifted (tools/dl/drivers/fadeaway_puppet_run_up), each view's run sized to its standing still.

const DIR := "res://content/characters/fadeaway/"
const JP := DIR + "fadeaway.json"
const LOOKS := ["FAD-E", "FAD-F"]
const VIEWS := {"back": "", "front": "_f", "side": "_s", "bd": "_bd", "fd": "_fd"}
const ORDER := ["idle", "run", "turn", "hit", "die", "cheer", "idle_f", "run_f", "idle_s", "run_s", "idle_bd", "run_bd",
	"idle_fd", "run_fd", "hit_f", "hit_s", "hit_bd", "hit_fd"]
const CELL := 256


func _doc() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(JP))


func test_two_new_looks_with_their_recipes() -> void:
	var d := _doc()
	var vs: Dictionary = d["variants"]
	var arts := {}
	for code: String in LOOKS:
		assert_bool(vs.has(code)).override_failure_message(code).is_true()
		var e: Dictionary = vs[code]
		var rec: Dictionary = e["recipe"]
		# their own paintings, their own seeds
		assert_str(str(rec["stills"])).is_not_empty()
		assert_str(str(rec["stills"])).is_not_equal("c")
		assert_int(int(rec["seed_offset"])).is_not_equal(2243)
		# the back-diagonal is the painting made from the front AND the back (the 88), named per view
		assert_str(str(rec["still_keys"]["bd"])).is_equal("fadeaway_%s_bd88" % rec["stills"])
		# every view walks on the upright stick figure (the depth guide had dulled the purple)
		for v: String in VIEWS.keys():
			assert_str(str(rec["pose_drivers"][v])).is_equal("fadeaway_puppet_run_up")
		assert_bool(rec.has("ctl_drivers")).is_false()
		# each view's run sized to the standing still (run_scale per view, clamped as gen_art clamps it)
		var rs: Dictionary = rec["run_scale"]
		for v: String in VIEWS.keys():
			assert_float(float(rs.get(v, 1.0))).is_between(0.5, 1.5)
		# fresh until Garry picks (re-pinned in pass 88: he picked FAD-E, approved, so it is no longer fresh); never shelved
		assert_bool(bool(e.get("fresh", false))).is_equal(code != "FAD-E")
		assert_bool(bool(e.get("shelved", false))).is_false()
		arts[code] = str(rec["art_prompt"])
	# the precise prompt says much more than the loose one
	assert_int((arts["FAD-E"] as String).length()).is_greater(3 * (arts["FAD-F"] as String).length())
	assert_str(str(d["variant"])).starts_with("FAD-")


func test_each_new_look_has_a_whole_strip_like_his_played_one() -> void:
	var d := _doc()
	var played: Dictionary = d["variants"][str(d["variant"])]
	for code: String in LOOKS:
		var e: Dictionary = d["variants"][code]
		var letter := code.substr(4).to_lower()
		assert_str(str(e["sprite"])).is_equal("fadeaway_sprite_%s.png" % letter)
		assert_bool(ResourceLoader.exists(DIR + str(e["sprite"]))).is_true()
		assert_dict(e["anims"]).is_equal(played["anims"])
		assert_int(int(e["strip_cols"])).is_equal(int(played["strip_cols"]))
		assert_bool(ResourceLoader.exists(DIR + str(e["icon"]))).is_true()


func test_the_game_wears_each_new_look_when_named() -> void:
	var c: CharacterDef = Registry.character("fadeaway")
	assert_object(c).is_not_null()
	for code: String in LOOKS:
		assert_bool(c.variant_codes().has(code)).override_failure_message(code).is_true()
		var v: CharacterDef = c.variant_def(code)
		assert_str(v.look_code()).is_equal(code)
		assert_object(v.sprite).is_not_null()
		assert_int(int(v.anims.get("run_f", 0))).is_equal(24)


# ---------------------------------------------------------------- one size across the animations

## The frames of one animation of a strip (the PNG on disk, not the imported texture).
func _frames(img: Image, anims: Dictionary, cols: int, anim: String) -> Array[Image]:
	var out: Array[Image] = []
	var k := 0
	for a: String in ORDER:
		var n := int(anims.get(a, 0))
		if a == anim:
			for i in range(n):
				var j := k + i
				out.append(img.get_region(Rect2i((j % cols) * CELL, (j / cols) * CELL, CELL, CELL)))
			return out
		k += n
	return out


## Per frame: the figure's height (its used rect) and its head's width (the widest row in the top 23 px under the
## figure's top: the afro), the scale cue that bent knees and a foot reaching toward the camera do not change.
func _measure(f: Image) -> Vector2:
	var r := f.get_used_rect()
	if r.size.y <= 0:
		return Vector2.ZERO
	# the head band's widest row of pixels more than half opaque (the outline's soft edge left out)
	var head := 0.0
	for y in range(r.position.y, mini(CELL, r.position.y + 23)):
		var x0 := -1
		var x1 := -1
		for x in range(r.position.x, r.end.x):
			if f.get_pixel(x, y).a > 0.5:
				if x0 < 0:
					x0 = x
				x1 = x
		if x0 >= 0:
			head = maxf(head, float(x1 - x0 + 1))
	return Vector2(float(r.size.y), head)


func _median(xs: Array[float]) -> float:
	xs.sort()
	var n := xs.size()
	if n == 0:
		return 0.0
	return xs[n / 2] if n % 2 == 1 else 0.5 * (xs[n / 2 - 1] + xs[n / 2])


func _anim_size(img: Image, e: Dictionary, anim: String) -> Vector2:
	var hs: Array[float] = []
	var ws: Array[float] = []
	for f: Image in _frames(img, e["anims"], int(e["strip_cols"]), anim):
		var m := _measure(f)
		if m.x > 0:
			hs.append(m.x)
			ws.append(m.y)
	return Vector2(_median(hs), _median(ws))


func test_each_view_stands_and_runs_at_one_size() -> void:
	var d := _doc()
	for code: String in LOOKS:
		var e: Dictionary = d["variants"][code]
		var img := Image.load_from_file(ProjectSettings.globalize_path(DIR + str(e["sprite"])))
		assert_object(img).is_not_null()
		for v: String in VIEWS.keys():
			var sfx: String = VIEWS[v]
			var idle := _anim_size(img, e, "idle" + sfx)
			var run := _anim_size(img, e, "run" + sfx)
			var hit := _anim_size(img, e, "hit" + sfx)
			var what := "%s %s: idle %s run %s hit %s" % [code, v, idle, run, hit]
			# the run's body (its head) within 5 % of the standing still's: FAD-D's front run stood at 0.99 of the stand's
			# height and was 12-18 % bigger, so the height alone cannot say it
			assert_float(run.y / idle.y).override_failure_message(what).is_between(0.95, 1.05)
			# the hit stands as tall as the stand (its hand may reach the head band, so its height is the measure)
			assert_float(hit.x / idle.x).override_failure_message(what).is_between(0.95, 1.05)
			# the run's median frame never taller than the stand by more than 5 % (a run crouches, so it may stand
			# lower: E and F 0.86-0.95; a run as tall as the stand was the bug)
			assert_float(run.x / idle.x).override_failure_message(what).is_between(0.84, 1.05)
