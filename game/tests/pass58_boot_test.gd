extends GdUnitTestSuite

## Pass 58, lane BOOT (Garry, 2026-10-07: "for like a second or 2 right before the Main Menu loads I see a kind of a
## broken version of our Loading screen - with brown lines at the top and bottom visible ... My phone is a Pixel 8 pro,
## might be resolution thing. Also, while you are at it, maybe add a loading progress bar to the Loading Screen."): the
## boot splash picture is paper to every edge (its ink bands floated inside a 20:9 screen, where stretch mode Keep fits
## the picture to the width and the bg_color runs on above and below it), exactly the boot splash's bg_color; Keep keeps
## its middle whole and centred on 9:16, 20:9, 19.5:9 and a 3:4 tablet; the texture Boot draws is the picture to the
## pixel (a lossless import); the picture is the loading screen at 0 % (the bar's empty look and its word under the last
## line) and Boot draws it where the engine drew it (splash_rect, Godot 4.7.2's own rule) as one draw over the whole
## screen, the bar's fill painted in by its shader, so its dissolve into the title is even (the review's two lines across
## a 20:9 screen); it loads the title on a thread, builds it under itself and hands over, the bar only growing and ending
## full; a failed load is fetched and read again from its file, a load that never moves is given up on, a title that
## cannot load is said on the screen; a long frame neither throws the bar nor eats the dissolve; the camera cutout's band
## waits while it shows and comes back.

const BootScript := preload("res://ui/Boot.gd")
const Stage := preload("res://ui/TitleStage.gd")
const SPLASH := "res://art/ui/splash.png"
const TITLE := "res://ui/TitleScreen.tscn"
## Screens the picture's middle must stay whole and centred on: the design's 9:16, Garry's Pixel 8 Pro (20:9), 19.5:9
## and a 3:4 tablet.
const SCREENS := [Vector2(1080, 1920), Vector2(1344, 2992), Vector2(1170, 2532), Vector2(1536, 2048)]
## Stand-in titles for the load's failures (written to user:// by the tests, removed after).
const STAND_IN := "user://p58_boot_stand_in.tscn"
const BROKEN_SCENE := "[gd_scene format=3]\n\n[node name=\"Broken\" type=\"Node\"\nthis is not a scene\n"
const GOOD_SCENE := "[gd_scene format=3]\n\n[node name=\"Good\" type=\"Control\"]\n"


## A loading screen whose threaded load never moves (its status stays in progress at a quarter).
class StuckBoot extends "res://ui/Boot.gd":
	func _request() -> int:
		return OK

	func _status(progress: Array) -> int:
		progress.append(0.25)
		return ResourceLoader.THREAD_LOAD_IN_PROGRESS


var _keep_style := ""


func before_test() -> void:
	_keep_style = Settings.menu_style


func after_test() -> void:
	Settings.menu_style = _keep_style
	Stage.forget()
	if FileAccess.file_exists(STAND_IN):
		DirAccess.remove_absolute(STAND_IN)


func _splash() -> Image:
	var img := Image.new()
	assert_int(img.load_png_from_buffer(FileAccess.get_file_as_bytes(SPLASH))).is_equal(OK)
	return img


func _is(c: Color, want: Color) -> bool:
	return c.r8 == want.r8 and c.g8 == want.g8 and c.b8 == want.b8


func _paper(c: Color) -> bool:
	return _is(c, W.PAPER)


## Whether every pixel of `r` (stepping `step` px) is `want` (the paper by default).
func _all(img: Image, r: Rect2i, want: Color = W.PAPER, step: int = 1) -> bool:
	for y in range(r.position.y, r.end.y, step):
		for x in range(r.position.x, r.end.x, step):
			if not _is(img.get_pixel(x, y), want):
				return false
	return true


## The box round everything that is not paper (the disc, its shadow, the title, the line, the bar, its word), stepping
## 2 px.
func _ink_box(img: Image) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	var lo := Vector2i(w, h)
	var hi := Vector2i(-1, -1)
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			if not _paper(img.get_pixel(x, y)):
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	return Rect2i(lo, hi - lo + Vector2i(2, 2))


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


# ---------------------------------------------------------------- the picture

func test_the_splash_is_paper_to_every_edge_with_no_bands() -> void:
	var bytes := FileAccess.get_file_as_bytes(SPLASH)
	assert_int(bytes.size()).is_between(1000, 600 * 1024)
	var img := _splash()
	assert_int(img.get_width()).is_equal(1080)
	assert_int(img.get_height()).is_equal(1920)
	# every pixel on the four edges is the paper (the boot splash's bg_color continues it without a seam)
	assert_bool(_all(img, Rect2i(0, 0, 1080, 1))).is_true()
	assert_bool(_all(img, Rect2i(0, 1919, 1080, 1))).is_true()
	assert_bool(_all(img, Rect2i(0, 0, 1, 1920))).is_true()
	assert_bool(_all(img, Rect2i(1079, 0, 1, 1920))).is_true()
	# no dark rows at the top or the foot: the old ink bands filled rows 0-103 and 1816-1919; 300 rows of paper each way
	assert_bool(_all(img, Rect2i(0, 0, 1080, 300), W.PAPER, 3)).is_true()
	assert_bool(_all(img, Rect2i(0, 1620, 1080, 300), W.PAPER, 3)).is_true()
	# the project's boot splash: this picture on the same paper, kept whole, nothing held on screen on purpose
	assert_str(str(ProjectSettings.get_setting("application/boot_splash/image"))).is_equal(SPLASH)
	var bg: Color = ProjectSettings.get_setting("application/boot_splash/bg_color")
	assert_bool(_paper(bg) and is_equal_approx(bg.a, 1.0)).is_true()
	assert_bool(_paper(img.get_pixel(0, 0))).is_true()
	assert_bool(bool(ProjectSettings.get_setting("application/boot_splash/show_image"))).is_true()
	assert_int(int(ProjectSettings.get_setting("application/boot_splash/minimum_display_time"))).is_equal(0)


## Keep fits a portrait screen's width and centres the picture up and down: the paper runs on above and below it on a
## tall phone, and it runs off the top and the foot on a tablet; either way the middle (the disc, the title, the line,
## the bar and its word) stays whole and centred.
func test_keep_keeps_the_middle_whole_and_centred_on_every_screen() -> void:
	assert_int(int(ProjectSettings.get_setting("application/boot_splash/stretch_mode"))).is_equal(1)   # Keep
	var img := _splash()
	var middle := Rect2(_ink_box(img))
	# the bar and its word are part of it
	assert_bool(middle.encloses(BootScript.BAR.grow_individual(0, 0, BootScript.BAR_SHADOW, BootScript.BAR_SHADOW))).is_true()
	assert_float(middle.end.y).is_greater_equal(BootScript.LABEL_Y + BootScript.LABEL_PX * 0.6)
	# the middle is centred in the picture itself, give or take the disc's hard shadow
	assert_float(absf(middle.get_center().x - 540.0)).is_less_equal(8.0)
	assert_float(absf(middle.get_center().y - 960.0)).is_less_equal(8.0)
	for s: Vector2 in SCREENS:
		var r: Rect2 = BootScript.splash_rect(BootScript.SPLASH_SIZE, s, 1)
		var k := r.size / BootScript.SPLASH_SIZE
		var on_screen := Rect2(r.position + middle.position * k, middle.size * k)
		assert_bool(Rect2(Vector2.ZERO, s).encloses(on_screen)).override_failure_message("%s: %s" % [str(s), str(on_screen)]).is_true()
		assert_float(absf(r.get_center().x - s.x * 0.5)).is_less(0.01)
		assert_float(absf(r.get_center().y - s.y * 0.5)).is_less(0.01)


## splash_rect is Godot 4.7.2's RenderingServerTypes::get_splash_stretched_screen_rect, mode by mode.
func test_splash_rect_is_the_engines_rule() -> void:
	var img := Vector2(1080, 1920)
	var cases := [
		# Keep: portrait fits the width, landscape the height
		[1, Vector2(1080, 1920), Rect2(0, 0, 1080, 1920)],
		[1, Vector2(1344, 2992), Rect2(0, 301.333, 1344, 2389.333)],
		[1, Vector2(1536, 2048), Rect2(0, -341.333, 1536, 2730.667)],
		[1, Vector2(1920, 1080), Rect2(656.25, 0, 607.5, 1080)],
		# Disabled: its own size in the middle, floored
		[0, Vector2(1344, 2992), Rect2(132, 536, 1080, 1920)],
		# Keep Width, Keep Height
		[2, Vector2(1920, 1080), Rect2(0, -1166.667, 1920, 3413.333)],
		[3, Vector2(1536, 2048), Rect2(192, 0, 1152, 2048)],
		# Cover: a 20:9 phone fills the height and loses the sides, a 3:4 tablet fills the width
		[4, Vector2(1344, 2992), Rect2(-169.5, 0, 1683, 2992)],
		[4, Vector2(1536, 2048), Rect2(0, -341.333, 1536, 2730.667)],
		# Ignore: the whole window
		[5, Vector2(1344, 2992), Rect2(0, 0, 1344, 2992)],
	]
	for c: Array in cases:
		var got: Rect2 = BootScript.splash_rect(img, c[1], c[0])
		var want: Rect2 = c[2]
		var near := got.position.distance_to(want.position) < 0.01 and got.size.distance_to(want.size) < 0.01
		assert_bool(near).override_failure_message("mode %d on %s: %s, want %s" % [c[0], str(c[1]), str(got), str(want)]).is_true()


## The picture is the loading screen at 0 %: under the last line the bar as the kit's WBar draws it empty (a hard ink
## shadow down and right, an ink box, the aged track inside its border) and its word, on paper, in the middle
## (make_splash.py lays it out and writes the bar's place into Boot.gd, whose shader fills that track).
func test_the_empty_bar_and_its_word_are_in_the_picture_under_the_last_line() -> void:
	var img := _splash()
	var bar: Rect2i = Rect2i(BootScript.BAR)
	var b: int = BootScript.BAR_BORDER
	var s: int = BootScript.BAR_SHADOW
	assert_float(Rect2(bar).get_center().x).is_equal_approx(540.0, 0.5)
	# the aged track, every pixel of it
	var track := bar.grow(-b)
	assert_bool(_all(img, track, W.AGED)).is_true()
	# the ink border on all four sides
	assert_bool(_all(img, Rect2i(bar.position, Vector2i(bar.size.x, b)), W.INK)).is_true()
	assert_bool(_all(img, Rect2i(bar.position.x, bar.end.y - b, bar.size.x, b), W.INK)).is_true()
	assert_bool(_all(img, Rect2i(bar.position, Vector2i(b, bar.size.y)), W.INK)).is_true()
	assert_bool(_all(img, Rect2i(bar.end.x - b, bar.position.y, b, bar.size.y), W.INK)).is_true()
	# the hard shadow, right and under, and the paper in the two corners it leaves
	assert_bool(_all(img, Rect2i(bar.end.x, bar.position.y + s, s, bar.size.y), W.INK)).is_true()
	assert_bool(_all(img, Rect2i(bar.position.x + s, bar.end.y, bar.size.x, s), W.INK)).is_true()
	assert_bool(_all(img, Rect2i(bar.end.x, bar.position.y, s, s))).is_true()
	assert_bool(_all(img, Rect2i(bar.position.x, bar.end.y, s, s))).is_true()
	# paper round it
	var ring := Rect2i(bar.position - Vector2i(16, 16), bar.size + Vector2i(32 + s, 16 + s))
	assert_bool(_all(img, Rect2i(ring.position, Vector2i(ring.size.x, 16)))).is_true()
	assert_bool(_all(img, Rect2i(ring.position.x, bar.position.y, 16, bar.size.y + s))).is_true()
	assert_bool(_all(img, Rect2i(bar.end.x + s, bar.position.y, 16, bar.size.y + s))).is_true()
	# its word under it, in the soft ink, centred, with paper at both sides of the bar's width
	var word := Rect2i(bar.position.x, int(BootScript.LABEL_Y), bar.size.x, int(BootScript.LABEL_PX * 1.2))
	assert_bool(_all(img, word)).is_false()
	var lo := word.end.x
	var hi := word.position.x
	var soft := false
	for y in range(word.position.y, word.end.y):
		for x in range(word.position.x, word.end.x):
			var c := img.get_pixel(x, y)
			if not _paper(c):
				lo = mini(lo, x)
				hi = maxi(hi, x)
			soft = soft or _is(c, W.INK_SOFT)
	assert_bool(soft).is_true()
	assert_float(absf((lo + hi) * 0.5 - 540.0)).is_less_equal(3.0)
	assert_int(hi - lo).is_between(140, 260)
	assert_bool(_all(img, Rect2i(0, word.position.y, 380, word.size.y))).is_true()
	assert_bool(_all(img, Rect2i(700, word.position.y, 380, word.size.y))).is_true()
	# the line ("A survivor shooter") ends close above the bar
	var above := Rect2i(bar.position.x, bar.position.y - 120, bar.size.x, 100)
	assert_bool(_all(img, above)).is_false()


## The texture Boot draws is the picture to the pixel: a lossless import with no mipmaps (lossy_imports.py leaves
## art/ui/splash.png alone), so the switch from the engine's boot splash to Boot cannot be seen.
func test_the_splash_import_is_lossless() -> void:
	var cfg := ConfigFile.new()
	assert_int(cfg.load(SPLASH + ".import")).is_equal(OK)
	assert_int(int(cfg.get_value("params", "compress/mode", -1))).is_equal(0)
	assert_bool(bool(cfg.get_value("params", "mipmaps/generate", true))).is_false()


# ---------------------------------------------------------------- the loading screen

func test_boot_starts_on_the_paper_with_the_picture_and_an_empty_bar() -> void:
	var boot: Control = auto_free(load("res://ui/Boot.tscn").instantiate())
	# the first scene after the boot splash is paper too, so nothing flashes dark between them (pass 54)
	assert_bool((boot.get_node("ColorRect") as ColorRect).color.is_equal_approx(W.PAPER)).is_true()
	assert_object(boot.get_node_or_null("Art")).is_null()   # built in _ready


## The first frame carries the engine's start (Godot's frame clock starts before the autoloads load and caps the step at
## 8 physics ticks, about 0.13 s), which had thrown the bar a fifth of the way in the very first frame: a long frame
## moves it no further than MAX_STEP does, so it starts all but empty, and the creep still runs on towards its cap
## (never past it) frame by frame.
func test_a_long_first_frame_leaves_the_bar_all_but_empty() -> void:
	var boot = auto_free(BootScript.new())
	var cap: float = BootScript.LOAD_END * BootScript.CREEP_STOP
	boot._cap = cap
	boot._show(0.0)
	boot._advance(5.0)
	var first: float = boot.history[boot.history.size() - 1]
	assert_float(first).is_greater(0.0)
	assert_float(first).is_less(0.05)
	for i in 120:
		boot._advance(1.0 / 60.0)
	var h: PackedFloat32Array = boot.history
	assert_float(h[h.size() - 1]).is_greater(0.45)
	assert_float(h[h.size() - 1]).is_less_equal(cap + 0.0001)
	for i in range(1, h.size()):
		assert_bool(h[i] >= h[i - 1]).is_true()


## The review's timing run: the frame before the dissolve carries the title's first full draw (74 ms on the PC, longer
## on a phone), and the tween had spent it on the dissolve's first step (already 20 % gone in its first frame, a cut at
## 250 ms). A step counts at most MAX_STEP, so the dissolve always takes its frames, the cover only falls (sine in and
## out) and ends at nothing.
func test_a_long_frame_does_not_eat_the_dissolve() -> void:
	var boot = auto_free(BootScript.new())
	boot._dissolve_t = 0.0
	assert_bool(boot._step_dissolve(0.5)).is_false()
	var k0 := 0.5 - 0.5 * cos(PI * BootScript.MAX_STEP / BootScript.DISSOLVE)
	assert_float(boot.modulate.a).is_equal_approx(1.0 - k0, 0.0001)
	assert_float(boot.modulate.a).is_greater(0.95)
	var frames := 1
	var prev: float = boot.modulate.a
	while not boot._step_dissolve(0.5):
		frames += 1
		assert_bool(boot.modulate.a <= prev).is_true()
		prev = boot.modulate.a
		assert_int(frames).is_less(100)
	frames += 1
	assert_int(frames).is_greater_equal(ceili(BootScript.DISSOLVE / BootScript.MAX_STEP))
	assert_float(boot.modulate.a).is_equal_approx(0.0, 0.0001)


func test_boot_hands_over_to_the_title_and_the_bar_only_grows_and_ends_full() -> void:
	Settings.menu_style = "live"
	var host: Node = auto_free(Node.new())
	add_child(host)
	var boot: Control = load("res://ui/Boot.tscn").instantiate()
	boot.host = host
	host.add_child(boot)
	# the picture where the engine drew it (headless: the canvas is the screen), drawn by one shader over everything
	var canvas := boot.get_viewport_rect().size
	var r: Rect2 = BootScript.splash_rect(BootScript.SPLASH_SIZE, canvas, 1)
	var art := boot.get_node("Art") as Node2D
	assert_object(art).is_not_null()
	assert_bool(art.position.is_equal_approx(r.position)).is_true()
	assert_bool(art.scale.is_equal_approx(r.size / BootScript.SPLASH_SIZE)).is_true()
	assert_int(art.get_child_count()).is_equal(1)
	var splash := boot.get_node("Art/Splash") as Node2D
	assert_object(splash).is_not_null()
	var mat := splash.material as ShaderMaterial
	assert_object(mat).is_not_null()
	assert_bool(boot.has_picture()).is_true()
	var inner: Rect2 = BootScript.BAR.grow(-BootScript.BAR_BORDER)
	assert_bool(mat.get_shader_parameter("track") == Vector4(inner.position.x, inner.position.y, inner.size.x, inner.size.y)).is_true()
	assert_bool(_is(mat.get_shader_parameter("track_color"), W.AGED)).is_true()
	assert_bool(_is(mat.get_shader_parameter("fill_color"), W.BRASS)).is_true()
	# the one draw reaches past every edge of the canvas
	var cover: Rect2 = boot._cover
	var on_canvas := Rect2(art.position + cover.position * art.scale, cover.size * art.scale)
	assert_bool(on_canvas.encloses(Rect2(Vector2.ZERO, canvas))).is_true()
	assert_float(float(boot.bar_value())).is_less(0.5)
	assert_float(float(mat.get_shader_parameter("fill"))).is_equal_approx(boot.bar_value(), 0.0001)
	# the camera cutout's band waits while the loading screen shows
	var band := get_tree().root.get_node_or_null("CutoutBand") as CanvasLayer
	if band:
		assert_bool(band.visible).is_false()
	var title: Node = await await_signal_on(boot, "handed_over", [], 30000)
	assert_object(title).is_not_null()
	assert_str(title.scene_file_path).is_equal(TITLE)
	assert_object(title.get_parent()).is_same(host)
	# the title is not left half faded: the loading screen dissolves into it
	assert_float((title as CanvasItem).modulate.a).is_equal(1.0)
	# from the dissolve on, the one draw is the whole screen: the paper rect under it is gone
	assert_bool((boot.get_node("ColorRect") as CanvasItem).visible).is_false()
	# the bar only grew, and it ended full
	var h: PackedFloat32Array = boot.history
	assert_int(h.size()).is_greater_equal(4)
	for i in range(1, h.size()):
		assert_bool(h[i] >= h[i - 1]).override_failure_message("the bar went back at %d: %f -> %f" % [i, h[i - 1], h[i]]).is_true()
	assert_float(h[h.size() - 1]).is_equal(1.0)
	assert_float(float(mat.get_shader_parameter("fill"))).is_equal(1.0)
	for key in ["engine", "load", "build", "first_frame"]:
		assert_bool(boot.timings.has(key)).override_failure_message(key).is_true()
	# it dissolves and goes, and the band comes back
	await await_millis(int(BootScript.DISSOLVE * 1000.0) + 400)
	assert_bool(is_instance_valid(boot)).is_false()
	if band:
		assert_bool(band.visible).is_true()
		for c in band.get_children():
			if c is CanvasItem:
				assert_float((c as CanvasItem).modulate.a).is_equal(1.0)


## The review's case: after a threaded load FAILS, Godot 4.7.2 keeps the failed task under its path until it is fetched,
## and a plain load() or change_scene_to_file() of the path gives nothing, so the old fallback could never bring the
## title up. Boot fetches the failed task and reads the file again past the cache: a title that failed once (broken on
## disk for the threaded load, mended before the second) still comes up.
func test_a_failed_threaded_load_still_brings_the_title_up() -> void:
	_write(STAND_IN, BROKEN_SCENE)
	var host: Node = auto_free(Node.new())
	add_child(host)
	var boot: Control = load("res://ui/Boot.tscn").instantiate()
	boot.host = host
	boot.title_path = STAND_IN
	var why := []
	boot.load_failed.connect(func(w: String) -> void:
		why.append(w)
		_write(STAND_IN, GOOD_SCENE))
	host.add_child(boot)
	var title: Node = await await_signal_on(boot, "handed_over", [], 10000)
	assert_object(title).is_not_null()
	assert_str(title.name).is_equal("Good")
	assert_str(title.scene_file_path).is_equal(STAND_IN)
	assert_object(title.get_parent()).is_same(host)
	assert_int(why.size()).is_equal(1)
	assert_str(str(why[0])).contains("failed")
	assert_bool(boot.failed).is_false()
	var h: PackedFloat32Array = boot.history
	for i in range(1, h.size()):
		assert_bool(h[i] >= h[i - 1]).is_true()
	await await_millis(int(BootScript.DISSOLVE * 1000.0) + 400)
	assert_bool(is_instance_valid(boot)).is_false()


## A title that cannot be read at all: the loading screen stays and says so under its word (it used to sit there with
## its bar stopped and no word of why), and its bar never goes back.
func test_a_title_that_cannot_load_is_said_on_the_screen() -> void:
	_write(STAND_IN, BROKEN_SCENE)
	var host: Node = auto_free(Node.new())
	add_child(host)
	var boot: Control = load("res://ui/Boot.tscn").instantiate()
	boot.host = host
	boot.title_path = STAND_IN
	host.add_child(boot)
	var waited := 0
	while not boot.failed and waited < 5000:
		await await_millis(50)
		waited += 50
	assert_bool(boot.failed).is_true()
	assert_object(boot.title).is_null()
	assert_object(boot.get_node_or_null("Art/Error")).is_not_null()
	await await_millis(200)
	assert_bool(is_instance_valid(boot)).is_true()
	assert_float(boot.modulate.a).is_equal(1.0)
	var h: PackedFloat32Array = boot.history
	for i in range(1, h.size()):
		assert_bool(h[i] >= h[i - 1]).is_true()
	boot.free()


## A threaded load whose progress never moves (its status in progress for good) used to leave the bar creeping to 55 %
## for ever: once it has sat still for stall_limit, Boot loads the title at once, past the stuck task, and hands over.
func test_a_load_that_never_moves_is_given_up_on() -> void:
	_write(STAND_IN, GOOD_SCENE)
	var host: Node = auto_free(Node.new())
	add_child(host)
	var boot: Control = StuckBoot.new()
	boot.host = host
	boot.title_path = STAND_IN
	boot.stall_limit = 0.3
	var why := []
	boot.load_failed.connect(func(w: String) -> void: why.append(w))
	host.add_child(boot)
	var title: Node = await await_signal_on(boot, "handed_over", [], 10000)
	assert_object(title).is_not_null()
	assert_str(title.name).is_equal("Good")
	assert_int(why.size()).is_equal(1)
	assert_str(str(why[0])).contains("25%")
	assert_bool(boot.timings.has("load")).is_true()
	# the stall clock runs on frame deltas, the timing on the wall clock: a frame of slack (it read 298.8 once)
	assert_float(float(boot.timings["load"])).is_greater_equal(270.0)
	var h: PackedFloat32Array = boot.history
	assert_float(h[h.size() - 1]).is_equal(1.0)
	for i in range(1, h.size()):
		assert_bool(h[i] >= h[i - 1]).is_true()
	await await_millis(int(BootScript.DISSOLVE * 1000.0) + 400)
	assert_bool(is_instance_valid(boot)).is_false()
