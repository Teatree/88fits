## The Royale theme's menu backdrop (pass 123, lane BACKDROP; Garry: "Paint a sunset version of today's title scene (same
## desert, props and hero) and use it behind the menus" ... "The BG should also be a bit animated, maybe a tumbleweed
## passes every minute or so, maybe a wind moves some cactuses gently, maybe the sun shine. The BG should feel alive,
## picturesque."). No class_name: load it by path and call make():
##     var bd: Control = load("res://ui/wanted/RoyaleBackdrop.gd").make("menu")   # or "title"
## A full-rect Control that never takes a touch, built from layers (art/ui/royale/backdrop.json, made by
## tools/gen_royale_backdrop.py):
##   - the plate: the live title's own desert (Red Canyon's sand, its fort wall and red-rock cliffs, its far scatter)
##     seen from lower down and painted at sunset by Flux.2 Klein over a capture of it, 1080 x 2400 (a 20:9 phone shows
##     it whole, a 16:9 one its middle; wider screens cover; the hero's spot is kept where the menu stands him);
##   - the sun's shine (ui_backdrop_sun.gdshader): a slow breathing glow round the painted sun, faint rays turning in
##     the sky behind it, a warm haze along the horizon;
##   - a few of the title preset's paintings (art/ui/title_scene.json's "Saguaro stand"; pass 123, Garry: "Make the
##     environment art a bit Sparser"), the game's own prop pictures where the capture projected them, graded for the
##     evening (backlit, a warm rim towards the sun), the greenery swaying from its base as the title's own wind sways it
##     (ui_backdrop_prop.gdshader);
##   - every object's shadow one way (pass 123, Garry: "fix the drop shadows from objects and hero they are all
##     mismatched"): one soft ellipse from its foot straight away from the sun, its length by the object's height, the
##     hero's too (set_caster), the tumbleweed's too;
##   - a tumbleweed rolling across behind the hero's spot every TUMBLE_MIN..TUMBLE_MAX seconds (the first sooner), hopping
##     and spinning over its shadow;
##   - dust motes drifting in the light (ui_backdrop_motes.gdshader);
##   - kind "title" only: a faint warm pool of light where the hero stands (ui_backdrop_disc.gdshader; set_disc moves it);
##   - a dark overlay over everything (set_dim) for screens full of panels.
## The animation (the tumbleweed's clock) runs only while the backdrop shows in a window: hidden, out of the tree or
## headless it does nothing (the shaders' own motion costs nothing while nothing is drawn). Without the manifest or the
## plate (a fresh checkout before the import) it draws a plain sunset gradient behind the same API.
extends Control

const SELF_PATH := "res://ui/wanted/RoyaleBackdrop.gd"
const MANIFEST := "res://art/ui/royale/backdrop.json"
const PROP_SHADER := "res://core/shaders/ui_backdrop_prop.gdshader"
const SUN_SHADER := "res://core/shaders/ui_backdrop_sun.gdshader"
const DISC_SHADER := "res://core/shaders/ui_backdrop_disc.gdshader"
const MOTES_SHADER := "res://core/shaders/ui_backdrop_motes.gdshader"

## the canvas the menus are laid out on, and the plate's (a taller phone shows more of it)
const CANVAS := Vector2(1080, 1920)
const PLATE := Vector2(1080, 2400)
## the default hero spot on the 1080 x 1920 canvas (the mock 5_Main_menu: the disc's centre at y ~1160, the feet just
## above it); on a taller screen it sits half the extra height lower (the plate follows it)
const DISC_CENTER := Vector2(540, 1160)
const DISC_RADIUS := 270.0
## how flat the disc's ellipse is (its height over its width)
const DISC_FLAT := 0.21
## a tumbleweed rolls across every TUMBLE_MIN..TUMBLE_MAX seconds (a fresh random wait each time); the first one comes
## TUMBLE_FIRST_MIN..TUMBLE_FIRST_MAX seconds after the backdrop first shows, so a short visit sees one too
const TUMBLE_MIN := 45.0
const TUMBLE_MAX := 90.0
const TUMBLE_FIRST_MIN := 6.0
const TUMBLE_FIRST_MAX := 16.0
## the tumbleweed: metres across, metres a second over the sand, and a share of the passes going right to left
const TUMBLE_SIZE_M := 0.95
const TUMBLE_SPEED := Vector2(1.8, 2.8)
const TUMBLE_LEFTWARD := 0.3

## the README's sunset sky (the fallback drawing), top to the sun's glow, and the ground under it
const SKY := [Color("120c3a"), Color("2d1a5a"), Color("7a2a5a"), Color("d8513f"), Color("f7a33a"), Color("ffd27a")]
const GROUND_TOP := Color("2a1430")
const GROUND_BOTTOM := Color("0c0918")
## the near sand falls into the evening's shade towards the screen's foot (the mock's ground darkens the same way, and
## the menu's name, START and tab bar sit there): from FOOT_FROM px under the disc's centre to the bottom, FOOT_COLOR
## rising to its alpha
const FOOT_FROM := 57.0
const FOOT_COLOR := Color(0.09, 0.045, 0.15, 0.62)

## tools and tests: animate even headless (a capture in a window animates anyway)
static var force_live := false

var kind := "menu"
## the plate's canvas (PLATE px), scaled and moved to cover this control with the hero's spot kept
var stage: Control
var plate: TextureRect
var sun: ColorRect
var disc: ColorRect
var motes: ColorRect
var foot: TextureRect
var tumble: Node2D
var props: Array[Sprite2D] = []
var shadows: Array[Sprite2D] = []

var _m: Dictionary = {}
var _dim := 0.0
var _dim_rect: ColorRect
var _scale := 1.0
var _disc_center := DISC_CENTER
var _disc_radius := DISC_RADIUS
var _disc_set := false
var _prop_mats: Array[ShaderMaterial] = []
var _shadow_tex: GradientTexture2D
var _shadow_root: Node2D
var _caster: Sprite2D
var _rng := RandomNumberGenerator.new()
# the tumbleweed's pass: rolling, or waiting for the session's next pass (_next_pass_ms: one clock for every backdrop, so
# a new screen's backdrop waits out the rest of the wait instead of sending its own: Garry's "every minute or so")
var _rolling := false
var _wait := 0.0
static var _next_pass_ms := -1
var _passes := 0
var _weed: Sprite2D
var _weed_shadow: Sprite2D
var _t := 0.0
var _x := 0.0
var _dir := 1.0
var _speed := 0.0
var _ground := 0.0
var _size := 0.0
var _hop_t := 0.6
var _hop_h := 0.0
var _spin := 0.0


## A backdrop of the given kind ("menu" or "title"), full rect, mouse_filter IGNORE.
static func make(kind_: String = "menu") -> Control:
	var s: GDScript = load(SELF_PATH)
	var b: Control = s.new()
	b.set("kind", "title" if kind_ == "title" else "menu")
	return b


func _init() -> void:
	name = "RoyaleBackdrop"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rng.randomize()
	if _next_pass_ms < 0:
		_next_pass_ms = Time.get_ticks_msec() + int(_rng.randf_range(TUMBLE_FIRST_MIN, TUMBLE_FIRST_MAX) * 1000.0)
	_wait = maxf(float(_next_pass_ms - Time.get_ticks_msec()) / 1000.0, 0.0)
	_dim_rect = ColorRect.new()
	_dim_rect.name = "Dim"
	_dim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim_rect.color = Color(0, 0, 0, 0)
	_dim_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim_rect)


func _ready() -> void:
	_build()
	_layout()
	_update_live()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			_layout()
		NOTIFICATION_VISIBILITY_CHANGED, NOTIFICATION_ENTER_TREE:
			_update_live()
		NOTIFICATION_EXIT_TREE:
			# still inside the tree while it is told it leaves
			set_process(false)


# --- the API ---------------------------------------------------------------------------------------------------------

## Where the main menu's hero stands (this control's px): the centre of the sand disc.
func disc_center() -> Vector2:
	if _disc_set:
		return _disc_center
	var s := _view()
	return Vector2(s.x * 0.5, DISC_CENTER.y + (s.y - CANVAS.y) * 0.5)


## The disc's half width (its height is DISC_FLAT of it).
func disc_radius() -> float:
	return _disc_radius


## Move the hero's sand disc and its light pool (the title lays the hero out and tells the backdrop where he stands);
## the painted plate follows, as far as it still covers the screen, so his spot stays the painting's.
func set_disc(center: Vector2, radius: float) -> void:
	_disc_center = center
	_disc_radius = maxf(radius, 1.0)
	_disc_set = true
	_layout()


## A dark overlay over the whole scene (0 none .. 1 black), for screens full of panels.
func set_dim(a: float) -> void:
	_dim = clampf(a, 0.0, 1.0)
	_dim_rect.color = Color(0, 0, 0, _dim)


func get_dim() -> float:
	return _dim


## Whether the living layers run now (false while hidden, out of the tree, or headless without force_live).
func is_animating() -> bool:
	return is_processing()


## Send a tumbleweed across now (tools and captures).
func force_tumbleweed() -> void:
	if tumble != null:
		_start_roll()


## Seconds until the next tumbleweed (0 while one rolls), and whether one rolls now.
func tumble_wait() -> float:
	return 0.0 if _rolling else _wait


func tumble_rolling() -> bool:
	return _rolling


## How much the plate is scaled to cover this control (1 on a 9:16 or 20:9 phone; more on a wider screen): a hero
## stood on the disc may be scaled by it to keep his size against the scene.
func plate_scale() -> float:
	return _scale


## Whether the painted plate is showing (false: the fallback gradient).
func has_plate() -> bool:
	return plate != null


# --- building --------------------------------------------------------------------------------------------------------

func _view() -> Vector2:
	return size if size.x > 1.0 and size.y > 1.0 else CANVAS


func _build() -> void:
	if stage != null:
		return
	if FileAccess.file_exists(MANIFEST):
		var data = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if data is Dictionary:
			_m = data
	var plate_path := str(_m.get("plate", ""))
	if plate_path == "" or not ResourceLoader.exists(plate_path):
		return
	stage = Control.new()
	stage.name = "Stage"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.size = PLATE
	# pass 123 (Garry: "a bit brighter than I expected. I'd want it to be a bit darker"): the whole scene through one tint
	var tint = _m.get("scene_tint")
	if tint is Array and (tint as Array).size() >= 3:
		stage.modulate = Color(float(tint[0]), float(tint[1]), float(tint[2]))
	add_child(stage)
	move_child(stage, 0)
	plate = TextureRect.new()
	plate.name = "Plate"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.texture = load(plate_path)
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode = TextureRect.STRETCH_SCALE
	plate.size = PLATE
	stage.add_child(plate)
	_build_sun()
	_build_props()
	_build_motes()
	_build_foot()
	queue_redraw()


func _vec(key: String, dflt: Vector2) -> Vector2:
	var a = _m.get(key)
	if a is Array and (a as Array).size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return dflt


func _build_sun() -> void:
	var sd: Dictionary = _m.get("sun", {})
	var c := _vec("sun_center", Vector2(430, 770))
	var h := float(_m.get("horizon_y", 1040.0))
	sun = ColorRect.new()
	sun.name = "Sun"
	sun.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sun.color = Color.WHITE
	var rh := h + 220.0
	sun.position = Vector2.ZERO
	sun.size = Vector2(PLATE.x, rh)
	var mat := ShaderMaterial.new()
	mat.shader = load(SUN_SHADER)
	mat.set_shader_parameter("rect_size", sun.size)
	mat.set_shader_parameter("sun_center", c)
	mat.set_shader_parameter("sun_radius", float(_m.get("sun_radius", 118.0)))
	mat.set_shader_parameter("horizon_y", h)
	var mask_path := str(_m.get("sky_mask", ""))
	if mask_path != "" and ResourceLoader.exists(mask_path):
		mat.set_shader_parameter("sky_mask", load(mask_path))
	for k in sd.keys():
		mat.set_shader_parameter(str(k), sd[k])
	sun.material = mat
	stage.add_child(sun)


## The preset's paintings, far first, each over its long shadow; the disc (title) under them and the tumbleweed among
## them at its lane's depth.
func _build_props() -> void:
	var list: Array = (_m.get("props", []) as Array).duplicate()
	list.sort_custom(func(a, b) -> bool: return float(a.get("base", [0, 0])[1]) < float(b.get("base", [0, 0])[1]))
	var grade: Dictionary = _m.get("grade", {})
	var by_sway := {}
	if kind == "title":
		disc = ColorRect.new()
		disc.name = "Disc"
		disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		disc.color = Color.WHITE
		var dm := ShaderMaterial.new()
		dm.shader = load(DISC_SHADER)
		disc.material = dm
		stage.add_child(disc)
	_shadow_root = Node2D.new()
	_shadow_root.name = "Shadows"
	stage.add_child(_shadow_root)
	var lane := _vec("tumble_lane", Vector2(1290, 1335))
	var lane_mid := (lane.x + lane.y) * 0.5
	var placed_weed := false
	for e in list:
		if not e is Dictionary:
			continue
		var d: Dictionary = e
		var tex_path := str(d.get("texture", ""))
		if tex_path == "" or not ResourceLoader.exists(tex_path):
			continue
		var base := Vector2(float(d["base"][0]), float(d["base"][1]))
		if not placed_weed and base.y > lane_mid:
			_build_tumble()
			placed_weed = true
		var tex: Texture2D = load(tex_path)
		var th := float(tex.get_height())
		var sc := float(d.get("height_px", th)) / maxf(th, 1.0)
		var sway := snappedf(float(d.get("sway", 0.0)), 0.005)
		if not by_sway.has(sway):
			var pm := ShaderMaterial.new()
			pm.shader = load(PROP_SHADER)
			pm.set_shader_parameter("sway", sway)
			for k in grade.keys():
				pm.set_shader_parameter(str(k), grade[k])
			by_sway[sway] = pm
			_prop_mats.append(pm)
		# its shadow, the one way every shadow here falls (_cast)
		if float(d.get("shadow_a", 0.5)) > 0.0:
			var sh_s := _cast(base, float(d.get("height_px", th)))
			sh_s.name = "Shadow_" + str(d.get("look", ""))
			shadows.append(sh_s)
		var p := _sprite(tex, base, sc, bool(d.get("flip", false)))
		p.name = "Prop_" + str(d.get("look", ""))
		p.material = by_sway[sway]
		stage.add_child(p)
		props.append(p)
	if not placed_weed:
		_build_tumble()


## One object's shadow on the sand: a soft ellipse from its foot `base` (plate px) straight away from the sun, as long as
## `h` x the manifest's shadow.length, as wide as `h` x shadow.width (a painting's square holds air, so a share of it),
## flattened by shadow.flat as the ground is. Every object's, the hero's and the tumbleweed's are this one.
func _cast(base: Vector2, h: float) -> Sprite2D:
	var sh: Dictionary = _m.get("shadow", {})
	if _shadow_tex == null:
		var g := Gradient.new()
		var col := Color(str(sh.get("color", "#1a0c24")))
		g.set_color(0, Color(col, 1.0))
		g.set_color(1, Color(col, 0.0))
		g.add_point(0.55, Color(col, 0.62))
		_shadow_tex = GradientTexture2D.new()
		_shadow_tex.gradient = g
		_shadow_tex.fill = GradientTexture2D.FILL_RADIAL
		_shadow_tex.fill_from = Vector2(0.5, 0.5)
		_shadow_tex.fill_to = Vector2(1.0, 0.5)
		_shadow_tex.width = 96
		_shadow_tex.height = 96
	var s := Sprite2D.new()
	s.texture = _shadow_tex
	s.modulate = Color(1, 1, 1, float(sh.get("alpha", 0.5)))
	_shadow_root.add_child(s)
	_lay_cast(s, base, h)
	return s


## Lays shadow `s` for an object at `base` of height `h`: the direction from under the sun out through the foot.
func _lay_cast(s: Sprite2D, base: Vector2, h: float) -> void:
	var sh: Dictionary = _m.get("shadow", {})
	var d := shadow_dir(base)
	var l := h * float(sh.get("length", 0.62))
	var w := h * float(sh.get("width", 0.34))
	var flat := float(sh.get("flat", 0.42))
	# the near end at the foot; the ground's foreshortening squeezes it towards the horizontal
	var dir := Vector2(d.x, d.y * flat).normalized()
	s.position = base + dir * l * 0.22
	s.rotation = dir.angle()
	s.scale = Vector2(l, w * lerpf(flat, 1.0, absf(dir.y))) / 96.0


## Where a shadow on the sand falls from a foot at `base` (plate px): straight away from the point of the horizon under
## the sun, never back towards it.
func shadow_dir(base: Vector2) -> Vector2:
	var sun := _vec("sun_center", Vector2(430, 770))
	var h := float(_m.get("horizon_y", 1040.0))
	var d := base - Vector2(sun.x, h - 40.0)
	d.y = maxf(d.y, 60.0)
	return d.normalized()


## The figure standing on the scene (the main menu's hero): his foot in this control's px and his height; his shadow falls
## the way every other falls. The title calls it when it lays him out.
func set_caster(foot: Vector2, h: float) -> void:
	if stage == null or _shadow_root == null:
		return
	if _caster == null:
		_caster = _cast(Vector2.ZERO, h)
		_caster.name = "Shadow_hero"
	_lay_cast(_caster, (foot - stage.position) / _scale, h / _scale)


func _sprite(tex: Texture2D, base: Vector2, sc: float, flip: bool) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.offset = Vector2(-tex.get_width() * 0.5, -tex.get_height())
	s.position = base
	s.scale = Vector2(sc, sc)
	s.flip_h = flip
	return s


func _build_tumble() -> void:
	var path := str(_m.get("tumbleweed", ""))
	if path == "" or not ResourceLoader.exists(path):
		return
	tumble = Node2D.new()
	tumble.name = "Tumbleweed"
	tumble.visible = false
	stage.add_child(tumble)
	_weed_shadow = _cast(Vector2.ZERO, 100.0)
	_weed_shadow.name = "Shadow"
	_weed_shadow.get_parent().remove_child(_weed_shadow)
	tumble.add_child(_weed_shadow)
	_weed = Sprite2D.new()
	_weed.name = "Weed"
	_weed.texture = load(path)
	var gm := ShaderMaterial.new()
	gm.shader = load(PROP_SHADER)
	for k in (_m.get("grade", {}) as Dictionary).keys():
		gm.set_shader_parameter(str(k), _m["grade"][k])
	gm.set_shader_parameter("rim_width", 0.03)
	_weed.material = gm
	_prop_mats.append(gm)
	tumble.add_child(_weed)


func _build_motes() -> void:
	var r := _m.get("motes", {}) as Dictionary
	if r.is_empty():
		return
	motes = ColorRect.new()
	motes.name = "Motes"
	motes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	motes.color = Color.WHITE
	var rect: Array = r.get("rect", [0, 700, 1080, 900])
	motes.position = Vector2(float(rect[0]), float(rect[1]))
	motes.size = Vector2(float(rect[2]), float(rect[3]))
	var mat := ShaderMaterial.new()
	mat.shader = load(MOTES_SHADER)
	mat.set_shader_parameter("rect_size", motes.size)
	var sc := _vec("sun_center", Vector2(430, 770))
	mat.set_shader_parameter("light_center", sc - motes.position)
	for k in r.keys():
		if str(k) != "rect":
			mat.set_shader_parameter(str(k), r[k])
	motes.material = mat
	stage.add_child(motes)


## The foot's shade: a vertical gradient over the scene (under the dim), laid out in this control's px.
func _build_foot() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(FOOT_COLOR.r, FOOT_COLOR.g, FOOT_COLOR.b, 0.0))
	g.set_color(1, FOOT_COLOR)
	g.add_point(0.45, Color(FOOT_COLOR.r, FOOT_COLOR.g, FOOT_COLOR.b, FOOT_COLOR.a * 0.55))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	gt.width = 4
	gt.height = 128
	foot = TextureRect.new()
	foot.name = "Foot"
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.texture = gt
	foot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	foot.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(foot)
	move_child(foot, stage.get_index() + 1)


# --- layout ----------------------------------------------------------------------------------------------------------

## Cover: the plate scaled to fill this control at least (never below 1:1), moved so its own hero spot lands on
## disc_center() as far as it still covers; the disc drawn exactly there.
func _layout() -> void:
	if stage == null:
		queue_redraw()
		return
	var v := _view()
	_scale = maxf(1.0, maxf(v.x / PLATE.x, v.y / PLATE.y))
	var spot := _vec("disc_center", Vector2(540, 1400))
	var want := disc_center()
	var ox := clampf(want.x - spot.x * _scale, v.x - PLATE.x * _scale, 0.0)
	var oy := clampf(want.y - spot.y * _scale, v.y - PLATE.y * _scale, 0.0)
	stage.position = Vector2(ox, oy)
	stage.scale = Vector2(_scale, _scale)
	if foot != null:
		var top := clampf(want.y + FOOT_FROM, 0.0, v.y - 1.0)
		foot.position = Vector2(0.0, top)
		foot.size = Vector2(v.x, v.y - top)
	if disc != null:
		var c := (want - stage.position) / _scale
		var r := _disc_radius / _scale
		var half := Vector2(r * 1.8, r * DISC_FLAT * 2.6)
		disc.position = c - half
		disc.size = half * 2.0
		var dm := disc.material as ShaderMaterial
		dm.set_shader_parameter("rect_size", disc.size)
		dm.set_shader_parameter("disc", Vector2(r, r * DISC_FLAT))
	# the rim light faces the sun and the haze reads the horizon: the props' shader works in the canvas's px
	var xf := get_global_transform()
	var sun_canvas := xf * (stage.position + _vec("sun_center", Vector2(430, 770)) * _scale)
	var near := xf * (stage.position + Vector2(0.0, float(_m.get("feet_y", 1370.0))) * _scale)
	var far := xf * (stage.position + Vector2(0.0, float(_m.get("horizon_y", 1040.0))) * _scale)
	for m in _prop_mats:
		m.set_shader_parameter("sun_pos", sun_canvas)
		m.set_shader_parameter("haze_near_y", near.y)
		m.set_shader_parameter("haze_far_y", far.y)


# --- the tumbleweed --------------------------------------------------------------------------------------------------

func _update_live() -> void:
	var live := is_inside_tree() and is_visible_in_tree() and tumble != null \
		and (force_live or DisplayServer.get_name() != "headless")
	set_process(live)


## px a metre at a ground y of the plate (the capture's lens: the hero's 1.9 m at his feet's y, 0 at the horizon)
func _ppm(y: float) -> float:
	var h := float(_m.get("horizon_y", 1040.0))
	var fy := float(_m.get("feet_y", 1370.0))
	var hp := float(_m.get("hero_px", 300.0))
	return hp / 1.9 * maxf(y - h, 1.0) / maxf(fy - h, 1.0)


func _start_roll() -> void:
	var lane := _vec("tumble_lane", Vector2(1290, 1335))
	_ground = _rng.randf_range(lane.x, lane.y)
	var ppm := _ppm(_ground)
	_size = TUMBLE_SIZE_M * ppm * _rng.randf_range(0.85, 1.15)
	_speed = _rng.randf_range(TUMBLE_SPEED.x, TUMBLE_SPEED.y) * ppm
	_dir = -1.0 if _rng.randf() < TUMBLE_LEFTWARD else 1.0
	# from just off the shown part of the plate to just past the other side
	var left := -stage.position.x / _scale - _size
	var right := (_view().x - stage.position.x) / _scale + _size
	_x = left if _dir > 0.0 else right
	_hop_t = _rng.randf_range(0.5, 0.75)
	_hop_h = _size * _rng.randf_range(0.35, 0.6)
	_t = 0.0
	_spin = _rng.randf() * TAU
	var tex_w := float(_weed.texture.get_width()) if _weed.texture else 256.0
	_weed.scale = Vector2.ONE * (_size / maxf(tex_w * 0.92, 1.0))
	# its shadow falls the way every other falls (at the lane's middle: the roll's own x would swing it past the sun)
	_lay_cast(_weed_shadow, Vector2(540.0, _ground), _size)
	_weed_shadow.position -= Vector2(540.0, _ground)
	_rolling = true
	_passes += 1
	tumble.visible = true
	_step_roll(0.0)


func _process(delta: float) -> void:
	if tumble == null:
		return
	if not _rolling:
		_wait -= delta
		if _wait <= 0.0:
			_start_roll()
		return
	_step_roll(delta)


func _step_roll(delta: float) -> void:
	_t += delta
	_x += _dir * _speed * delta
	# hops: each a little different in height, a squash as it lands
	var k := _t / _hop_t
	var n := floorf(k)
	var f := k - n
	var amp := _hop_h * (0.55 + 0.45 * absf(sin(n * 2.399 + 0.7)))
	var lift := amp * 4.0 * f * (1.0 - f)
	_spin += _dir * _speed * delta / maxf(_size * 0.5, 1.0)
	tumble.position = Vector2(_x, _ground)
	_weed.position = Vector2(0.0, -_size * 0.46 - lift)
	_weed.rotation = _spin
	var squash := 1.0 - 0.08 * maxf(0.0, 1.0 - f * 8.0)
	_weed.scale.y = absf(_weed.scale.x) * squash
	# the shadow pales as it hops
	var near := 1.0 - clampf(lift / maxf(_size, 1.0), 0.0, 1.0) * 0.5
	_weed_shadow.modulate.a = near * float((_m.get("shadow", {}) as Dictionary).get("alpha", 0.5))
	var left := -stage.position.x / _scale - _size * 1.5
	var right := (_view().x - stage.position.x) / _scale + _size * 1.5
	if (_dir > 0.0 and _x > right) or (_dir < 0.0 and _x < left):
		_rolling = false
		tumble.visible = false
		_wait = _rng.randf_range(TUMBLE_MIN, TUMBLE_MAX)
		_next_pass_ms = Time.get_ticks_msec() + int(_wait * 1000.0)


# --- the fallback ----------------------------------------------------------------------------------------------------

func _draw() -> void:
	if stage != null:
		return
	var r := Rect2(Vector2.ZERO, size)
	var horizon := size.y * 0.62
	var n := SKY.size()
	for i in n - 1:
		var y0 := horizon * float(i) / float(n - 1)
		var y1 := horizon * float(i + 1) / float(n - 1)
		var c0: Color = SKY[i]
		var c1: Color = SKY[i + 1]
		draw_polygon(PackedVector2Array([Vector2(0, y0), Vector2(r.size.x, y0), Vector2(r.size.x, y1), Vector2(0, y1)]),
			PackedColorArray([c0, c0, c1, c1]))
	draw_circle(Vector2(size.x * 0.4, horizon - 60.0), 150.0, Color(1.0, 0.85, 0.55, 0.95))
	draw_polygon(PackedVector2Array([Vector2(0, horizon), Vector2(r.size.x, horizon), Vector2(r.size.x, r.size.y),
		Vector2(0, r.size.y)]), PackedColorArray([GROUND_TOP, GROUND_TOP, GROUND_BOTTOM, GROUND_BOTTOM]))
	if kind == "title":
		var c := disc_center()
		var pts := PackedVector2Array()
		for k in 48:
			var a := TAU * float(k) / 48.0
			pts.append(c + Vector2(cos(a) * _disc_radius, sin(a) * _disc_radius * DISC_FLAT))
		draw_colored_polygon(pts, Color(0.86, 0.62, 0.38, 0.55))
