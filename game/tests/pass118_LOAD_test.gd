extends GdUnitTestSuite

## Pass 118, lane LOAD (Garry: "Let's change it. No icon, No progress bar. Title Drop sequence at the start and an
## animation of silhuettes of revolvers, stars, bombs, boots and other western(y) and not so western(y) item silhouettes
## that read well. They are meant to look like strips of saloon wallpaper and each strip moves slowly up-and a bit to the
## right, down-and a bit to the right ... This is meant to be the new progress bar replacement showing that the game is
## loading"): the boot splash is the plain paper and Android's splash shows no icon; the loading screen's first frame is
## that paper; its strips scroll up, down, up ... and drift right the whole time it loads; the title drops in, lands and
## settles before the screen dissolves; no bar, no icon, no picture of the old screen.

const BootScript := preload("res://ui/Boot.gd")
const WALLPAPER := "res://art/ui/loading/wallpaper.png"
const PLATE := "res://art/ui/loading/title_plate.png"
const SPLASH_ICON := "res://art/ui/splash_icon.png"
const STAND_IN := "user://p118_load_stand_in.tscn"
const GOOD_SCENE := "[gd_scene format=3]\n\n[node name=\"Good\" type=\"Control\"]\n"


## A loading screen whose load never finishes (it keeps loading for the length of a test).
class EndlessBoot extends "res://ui/Boot.gd":
	func _request() -> int:
		return OK

	func _status(progress: Array) -> int:
		progress.append(randf())
		return ResourceLoader.THREAD_LOAD_IN_PROGRESS


func after_test() -> void:
	if FileAccess.file_exists(STAND_IN):
		DirAccess.remove_absolute(STAND_IN)


func _same8(a: Color, b: Color) -> bool:
	return a.r8 == b.r8 and a.g8 == b.g8 and a.b8 == b.b8


func _image(path: String) -> Image:
	var img := Image.new()
	assert_int(img.load_png_from_buffer(FileAccess.get_file_as_bytes(path))).is_equal(OK)
	return img


## The loading screen's scene (its paper rect under the one draw) on a load that never finishes.
func _endless() -> Control:
	var b: Control = load("res://ui/Boot.tscn").instantiate()
	b.set_script(EndlessBoot)
	return b


func _host() -> Node:
	var host: Node = auto_free(Node.new())
	add_child(host)
	return host


# ---------------------------------------------------------------- the splash and the first frame

func test_the_splash_colour_is_the_first_frames_ground() -> void:
	# Godot's boot splash: the paper alone, no picture
	assert_bool(bool(ProjectSettings.get_setting("application/boot_splash/show_image"))).is_false()
	assert_str(str(ProjectSettings.get_setting("application/boot_splash/image", ""))).is_empty()
	var bg: Color = ProjectSettings.get_setting("application/boot_splash/bg_color")
	assert_bool(_same8(bg, W.PAPER) and is_equal_approx(bg.a, 1.0)).is_true()
	assert_int(int(ProjectSettings.get_setting("application/boot_splash/minimum_display_time"))).is_equal(0)
	# the loading screen's first frame, however long it took: the paper under, the one draw at nothing but the paper
	var boot = _endless()
	_host().add_child(boot)
	assert_bool(_same8((boot.get_node("ColorRect") as ColorRect).color, bg)).is_true()
	boot._process(3.0)
	var mat := (boot.get_node("Wallpaper") as CanvasItem).material as ShaderMaterial
	assert_float(boot.clock()).is_equal(0.0)
	assert_float(float(mat.get_shader_parameter("fade"))).is_equal(0.0)
	assert_bool(_same8(mat.get_shader_parameter("paper"), bg)).is_true()
	assert_float(float(mat.get_shader_parameter("plate_on"))).is_equal(0.0)
	# (pass 119: the slam's hit clock, not yet started; no flash, no shake)
	assert_float(float(mat.get_shader_parameter("hit_t"))).is_less(0.0)
	assert_float(float(mat.get_shader_parameter("flash"))).is_equal(0.0)
	assert_bool((mat.get_shader_parameter("shake") as Vector2).is_zero_approx()).is_true()
	# the wallpaper fades in from it over FADE_IN, then the plate is drawn (pass 119: slamming in)
	assert_float(BootScript.fade_at(0.0)).is_equal(0.0)
	assert_float(BootScript.fade_at(BootScript.FADE_IN * 0.5)).is_between(0.3, 0.7)
	assert_float(BootScript.fade_at(BootScript.FADE_IN)).is_equal_approx(1.0, 0.00001)
	assert_float(BootScript.SLAM_AT).is_greater_equal(BootScript.FADE_IN - 0.0001)
	boot.free()


## Android's own splash shows its background and an icon: the icon is clear in every pixel, so it is the paper alone.
func test_the_android_splash_has_no_icon() -> void:
	var cfg := ConfigFile.new()
	assert_int(cfg.load("res://export_presets.cfg")).is_equal(OK)
	var androids := 0
	for sec in cfg.get_sections():
		if not sec.ends_with(".options") or not cfg.has_section_key(sec, "splash_screen/icon"):
			continue
		androids += 1
		assert_bool(bool(cfg.get_value(sec, "splash_screen/disable_godot_boot_splash", false))).is_true()
		assert_bool(_same8(cfg.get_value(sec, "splash_screen/background_color", Color()), W.PAPER)).is_true()
		assert_str(str(cfg.get_value(sec, "splash_screen/icon"))).is_equal(SPLASH_ICON)
	assert_int(androids).is_greater_equal(1)
	var icon := _image(SPLASH_ICON)
	assert_bool(icon.detect_alpha() != Image.ALPHA_NONE).is_true()
	for y in range(0, icon.get_height(), 4):
		for x in range(0, icon.get_width(), 4):
			if icon.get_pixel(x, y).a8 != 0:
				assert_bool(false).override_failure_message("splash icon pixel %d,%d is not clear" % [x, y]).is_true()
				return


func test_there_is_no_bar_and_no_icon() -> void:
	var script: Script = BootScript
	var consts: Dictionary = script.get_script_constant_map()
	for gone in ["BAR", "SPLASH", "SPLASH_SIZE", "LABEL_Y", "LOAD_END", "BUILT", "CREEP_TAU"]:
		assert_bool(consts.has(gone)).override_failure_message(gone).is_false()
	var boot = auto_free(BootScript.new())
	assert_bool(boot.has_method("bar_value")).is_false()
	assert_bool(boot.has_method("splash_rect")).is_false()
	# the old splash picture (badge, title, empty bar) is gone from the game
	assert_bool(FileAccess.file_exists("res://art/ui/splash.png")).is_false()
	# the screen is the paper rect and the one draw, nothing else (no badge, no bar, no word)
	var live = _endless()
	_host().add_child(live)
	var names := []
	for c in live.get_children():
		names.append(str(c.name))
	assert_array(names).contains_exactly(["ColorRect", "Wallpaper"])
	live.free()


# ---------------------------------------------------------------- the wallpaper

func test_the_strips_move_in_alternating_directions_and_drift_right() -> void:
	for i in range(-6, 7):
		assert_float(BootScript.strip_dir(i)).is_equal(-1.0 if posmod(i, 2) == 0 else 1.0)
		var step := BootScript.strip_shift(i, 2.0) - BootScript.strip_shift(i, 1.0)
		assert_float(step).is_equal_approx(BootScript.strip_dir(i) * BootScript.SCROLL, 0.001)
	# a live screen, still loading: what the shader is handed moves that way, frame after frame
	var boot = _endless()
	boot.stall_limit = 1000.0
	_host().add_child(boot)
	var mat := (boot.get_node("Wallpaper") as CanvasItem).material as ShaderMaterial
	await await_millis(150)
	var t1: float = boot.clock()
	var first1 := int(mat.get_shader_parameter("first_strip"))
	var ys1: PackedFloat32Array = mat.get_shader_parameter("strip_y")
	var drift1 := float(mat.get_shader_parameter("drift"))
	await await_millis(400)
	var t2: float = boot.clock()
	var first2 := int(mat.get_shader_parameter("first_strip"))
	var ys2: PackedFloat32Array = mat.get_shader_parameter("strip_y")
	var drift2 := float(mat.get_shader_parameter("drift"))
	assert_float(t2 - t1).is_greater(0.1)
	assert_float(drift2 - drift1).is_equal_approx(BootScript.DRIFT * (t2 - t1), 0.01)
	assert_int(ys1.size()).is_equal(BootScript.MAX_STRIPS)
	var ups := 0
	var downs := 0
	for k in BootScript.MAX_STRIPS:
		var idx := first1 + k
		var k2 := idx - first2
		if k2 < 0 or k2 >= ys2.size():
			continue
		var moved := ys2[k2] - ys1[k]
		assert_float(moved).is_equal_approx(BootScript.strip_dir(idx) * BootScript.SCROLL * (t2 - t1), 0.05)
		if moved < 0.0:
			ups += 1
		else:
			downs += 1
	assert_int(ups).is_greater_equal(4)
	assert_int(downs).is_greater_equal(4)
	# the strips the shader is handed cover the whole screen, a strip to spare at the left
	var w := boot.get_viewport_rect().size.x
	var lo := float(first2) * BootScript.STRIP_W + drift2
	assert_float(lo).is_less_equal(-BootScript.STRIP_W * 0.999)
	assert_float(lo + BootScript.MAX_STRIPS * BootScript.STRIP_W).is_greater(w)
	boot.free()


## The atlas: VARIANTS strips side by side, each STRIP_W canvas px at the same scale, its print repeating every PERIOD
## without a seam, a pinstripe down both edges; imported lossless, no mipmaps; the plate too.
func test_the_wallpaper_atlas_tiles() -> void:
	var img := _image(WALLPAPER)
	var scale := float(img.get_width()) / (BootScript.VARIANTS * BootScript.STRIP_W)
	assert_float(scale).is_between(1.0, 2.0)
	assert_float(img.get_height() / BootScript.PERIOD).is_equal_approx(scale, 0.01)
	assert_int(FileAccess.get_file_as_bytes(WALLPAPER).size()).is_less(700 * 1024)
	var tw := int(round(BootScript.STRIP_W * scale))
	for v in BootScript.VARIANTS:
		var x0 := v * tw
		var ink := 0
		for y in range(0, img.get_height(), 7):
			# the pinstripe at both edges
			assert_float(img.get_pixel(x0, y).b).is_greater(0.5)
			assert_float(img.get_pixel(x0 + tw - 1, y).b).is_greater(0.5)
			for x in range(x0 + tw / 4, x0 + tw * 3 / 4, 5):
				if img.get_pixel(x, y).r > 0.5:
					ink += 1
		assert_int(ink).override_failure_message("strip %d has no print" % v).is_greater(200)
		# the vertical wrap: the last row runs on into the first no more sharply than rows do inside the strip (a motif
		# cut at the seam would jump along its whole width)
		var h := img.get_height()
		var seam := _row_step(img, x0, tw, h - 1, 0)
		var inside := 0.0
		for y in range(0, h - 1, 3):
			inside = maxf(inside, _row_step(img, x0, tw, y, y + 1))
		assert_float(seam).override_failure_message("strip %d seam %f, inside %f" % [v, seam, inside]).is_less_equal(inside)
	for path in [WALLPAPER, PLATE]:
		var cfg := ConfigFile.new()
		assert_int(cfg.load(path + ".import")).is_equal(OK)
		assert_int(int(cfg.get_value("params", "compress/mode", -1))).override_failure_message(path).is_equal(0)
		assert_bool(bool(cfg.get_value("params", "mipmaps/generate", true))).is_false()
	# the plate fits a 1080 px screen with room at both sides
	var plate := _image(PLATE)
	assert_float(plate.get_width() / BootScript.PLATE_SIZE.x).is_equal_approx(plate.get_height() / BootScript.PLATE_SIZE.y, 0.02)
	assert_float(BootScript.PLATE_SIZE.x).is_between(700.0, 1080.0 - 2.0 * 50.0)


## How much one row of a strip differs from another (R and G, summed over the strip's width).
func _row_step(img: Image, x0: int, w: int, ya: int, yb: int) -> float:
	var d := 0.0
	for x in range(x0, x0 + w):
		var a := img.get_pixel(x, ya)
		var b := img.get_pixel(x, yb)
		d += absf(a.r - b.r) + absf(a.g - b.g)
	return d


# ---------------------------------------------------------------- the title drop

## (Pass 119, lane LOADUI: the drop, its squash and its bounce are gone; tests/pass119_LOADUI_test.gd holds the slam.)


## The title has landed (and settled) before the dissolve, which never starts before MIN_SHOW even when the load was done
## at once; the plate is at rest when it starts, and the thud was played on the landing.
func test_the_title_lands_before_the_dissolve() -> void:
	var f := FileAccess.open(STAND_IN, FileAccess.WRITE)
	f.store_string(GOOD_SCENE)
	f.close()
	var boot: Control = load("res://ui/Boot.tscn").instantiate()
	boot.host = _host()
	boot.title_path = STAND_IN
	boot.host.add_child(boot)
	await await_signal_on(boot, "handed_over", [], 10000)
	var landed: float = boot.event_time("landed")
	var dissolve: float = boot.event_time("dissolve")
	assert_float(boot.event_time("loaded")).is_greater_equal(0.0)
	assert_float(landed).is_between(boot.impact_time(), boot.impact_time() + 0.1)
	assert_float(boot.event_time("settled")).is_less_equal(boot.event_time("built"))
	assert_float(landed).is_less(dissolve)
	assert_float(dissolve).is_greater_equal(BootScript.MIN_SHOW)
	# the stand-in loads at once, so the screen held for the drop: the dissolve came within a few frames of MIN_SHOW
	assert_float(dissolve).is_less(BootScript.MIN_SHOW + 0.5)
	assert_bool(boot.plate_pose().is_equal_approx(Vector3(0.0, 1.0, 1.0))).is_true()
	var mat := (boot.get_node("Wallpaper") as CanvasItem).material as ShaderMaterial
	assert_float(float(mat.get_shader_parameter("plate_on"))).is_equal(1.0)
	assert_bool((mat.get_shader_parameter("plate_mid") as Vector2).is_equal_approx(boot.plate_rest_mid())).is_true()
	# pass 119: the slam is over: no shake, no flash, no smear
	assert_bool((mat.get_shader_parameter("shake") as Vector2).is_zero_approx()).is_true()
	assert_float(float(mat.get_shader_parameter("flash"))).is_equal(0.0)
	assert_float(float(mat.get_shader_parameter("scale_prev"))).is_equal(1.0)
	assert_float(float(mat.get_shader_parameter("fade"))).is_equal(1.0)
	assert_bool(boot._thud_done).is_true()
	await await_millis(int(BootScript.DISSOLVE * 1000.0) + 400)
	assert_bool(is_instance_valid(boot)).is_false()


## The thud is a sound the map binds.
func test_the_thud_is_bound() -> void:
	var bound := false
	for id in BootScript.THUD:
		bound = bound or not Registry.soundmap.entry(str(id)).is_empty()
	assert_bool(bound).is_true()
