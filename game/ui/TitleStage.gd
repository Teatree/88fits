## The live title (pass 52, Garry: "instead of this visual of the hero, we display a smaller version of the hero as they
## are in the game ... the 3d version of their main weapon flying around them as they would in the game ... the actual
## level"). Behind the title's UI, a SubViewport with its own world holds the map itself, built as a run builds it (its
## sky, sun and haze are its own; no light is added here) from one fixed layout roll (SEED), so the title always opens
## on the same spot: open sand by a saguaro stand. The hero stands there as a run draws him (Player._setup_sprite's
## BillboardSprite: his strip at 1.9 m; not the outline pass) over his blob shadow, idling and now and then looking
## round, and his start weapon's companion (the visual scene's Familiar) circles him the way its behaviour flies it in a
## run, with its own small motions (the claws breathe, the cylinder turns, the guitar strums). A weapon with no
## companion (the Spear) shows nothing. A hero still to unlock is a figure in near-black with no weapon. A camera at the
## run's angle (CameraRig's fixed pitch and field of view), only closer, frames him in the title's hero box (frame()).
## Changing heroes, the one standing runs off the way the finger went and the next runs in from the other side. Input
## never reaches it (mouse_filter IGNORE, the viewport's GUI input off), so the title's swipe and buttons work as on the
## painted title; it draws as many 3D pixels as a run does (the root's 3D scale, 80 % on a phone; _rescale), and the
## built world waits out a menu visit (keep_on_exit) instead of being built again.
class_name TitleStage
extends SubViewportContainer

## The layout roll the title opens on (RedCanyon reads Run.map_seed in its _ready; the run's own value is put back at
## once).
const SEED := 88
## The hero's sprite height and the order his strip's animations come in, as Player._setup_sprite sets them up.
const HERO_HEIGHT := 1.9
const ORDER := ["idle", "run", "turn", "hit", "die", "cheer", "idle_f", "run_f", "idle_s", "run_s", "idle_bd", "run_bd",
	"idle_fd", "run_fd", "hit_f", "hit_s", "hit_bd", "hit_fd"]
## The run's camera (CameraRig.fixed_pitch_deg and fixed_fov): the title keeps its angle and lens and comes closer.
const PITCH_DEG := 46.0
const FOV_DEG := 55.0
## The hero in the title's hero box (fractions of its height): his soles a little above where the painted cut-out's are
## (the near side of his companion's circle passes his feet, and stays clear of the plaque), and his sprite this tall, a
## smaller hero than the painting (Garry: "a smaller version of the hero as they are in the game"), so the circle stays
## between the two arrows.
const FEET_FRAC := 0.86
const QUAD_FRAC := 0.5
## The figure inside a strip's frame (the heroes' idle frames: the head's top at 20 and the soles at 244 of 256 px), as
## fractions of the frame from its top, and its width.
const FIGURE_TOP := 0.08
const FIGURE_FEET := 0.953
const FIGURE_W := 0.31
## Where he stands on each map's title roll (x, z), picked by eye: on Red Canyon's SEED, open ripple sand south of a
## saguaro stand, the big saguaro and a bush behind him and nothing between him and the camera (by the oasis the damp
## shore's patchwork and the dry river's cracks showed at this distance). A map not listed: where a run starts.
const SPOTS := {"red_canyon": Vector2(7.5, 47.4)}
## A hero still to unlock: his figure multiplied down to near-black (the painted title's silhouette brown). Pass 69
## (Garry: "they have a full black mask over them"): black.
const LOCKED_TINT := Color(0.03, 0.024, 0.02)
## Pass 69: the black mask lifting off a hero just bought (reveal), seconds.
const REVEAL_TIME := 0.6
## The swap: the next hero runs in from SWAP_IN metres to the side (just off the screen) over SWAP_TIME, and the one
## standing runs SWAP_OUT the other way on the same easing, so the two never meet; he is gone after LEAVE_TIME, once his
## companion has followed him off the screen too.
const SWAP_TIME := 0.45
const SWAP_IN := 3.2
const SWAP_OUT := 4.4
const LEAVE_TIME := 0.8
## A companion behind the hero is drawn this far past his sprite (see Actor._draw_familiar).
const BEHIND := 0.2

## The map the stage shows (TitleScreen's map line) and the roll it is laid out from; `spot` puts the hero somewhere
## else (INF: the map's own, SPOTS).
var map_id := "red_canyon"
var layout_seed := SEED
var spot := Vector2.INF
## The hero's sprite height as a share of the box (QUAD_FRAC; a capture may try another).
var quad_frac := QUAD_FRAC

var viewport: SubViewport
var world: Node3D
var map: Node3D
var camera: Camera3D
## The hero standing (or running in), and those running off.
var hero: Actor
var leaving: Array = []
## How long the map took to build, in ms (the capture reports it; 0 when the last title's world was taken back).
var build_ms := 0.0
## Whether this stage took back the world the last title kept (tests).
var reused := false
## The built world is kept between title visits: the map takes a moment to build (a quarter of a second on the PC, more
## on a phone) and the title comes back after every menu. The title sets keep_on_exit when it leaves for a menu, and on
## leaving the stage takes its heroes off and parks the viewport with the map, its sky and the camera under the root
## (PARKED: switched off, drawing nothing; there it goes with the tree if the app quits from a menu); the next stage
## takes it back when it shows the same map from the same roll. A run starting, or the painted look, lets it go
## (forget), so a run never carries a second map.
const PARKED := "TitleWorldKept"
var keep_on_exit := false
static var _kept: SubViewport = null
static var _kept_key := ""
var _box := Rect2()
var _feet := Vector3.ZERO
var _depth := 8.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	stretch = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _kept != null and is_instance_valid(_kept) and _kept_key == _key():
		# the last title's world, as it was left (parked under the root, or still waiting to be)
		viewport = _kept
		_kept = null
		_kept_key = ""
		if viewport.get_parent():
			viewport.get_parent().remove_child(viewport)
		viewport.name = "View"
		viewport.process_mode = Node.PROCESS_MODE_INHERIT
		viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		add_child(viewport)
		world = viewport.get_node("World")
		camera = world.get_node("Camera")
		map = world.get_node("Map")
		camera.make_current()
		reused = true
		_feet = _spot_on(map)
	else:
		forget()
		_build_view()
		_build_map()
	_rescale()
	resized.connect(_reframe)
	resized.connect(_rescale)
	# the window can change its pixels without the canvas changing its size
	get_tree().root.size_changed.connect(_rescale)


## The viewport (its own world, deaf to input, the root's way of scaling 3D and its anti-aliasing; the scale itself in
## _rescale) with the camera in it.
func _build_view() -> void:
	viewport = SubViewport.new()
	viewport.name = "View"
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.audio_listener_enable_3d = false
	viewport.physics_object_picking = false
	var root := get_tree().root
	viewport.scaling_3d_mode = root.scaling_3d_mode
	viewport.msaa_3d = root.msaa_3d
	viewport.screen_space_aa = root.screen_space_aa
	add_child(viewport)
	world = Node3D.new()
	world.name = "World"
	viewport.add_child(world)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = FOV_DEG
	camera.far = 260.0
	world.add_child(camera)
	camera.make_current()


## Leaving with keep_on_exit set: the heroes go, the viewport stays for the next title, switched off (nothing in it runs
## or draws) and parked under the root once the root is done changing scenes.
func _exit_tree() -> void:
	if not keep_on_exit or viewport == null or not is_instance_valid(viewport):
		return
	for a in world.get_children():
		if a is Actor:
			a.free()
	hero = null
	leaving.clear()
	forget()
	remove_child(viewport)
	viewport.name = PARKED
	viewport.process_mode = Node.PROCESS_MODE_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_kept = viewport
	_kept_key = _key()
	viewport = null
	# by the script, not this stage: the stage is freed before a deferred call on it would run
	Callable(get_script(), "_park").call_deferred(_kept, get_tree().root)


## Parks the kept world under the root, unless the next title has taken it back already or it has been let go.
static func _park(vp: Variant, root: Variant) -> void:
	if not is_instance_valid(vp) or vp != _kept or not is_instance_valid(root):
		return
	if (vp as Node).get_parent() == null:
		(root as Node).add_child(vp)


## Lets the kept world go (a run starts, the painted look is chosen).
static func forget() -> void:
	if _kept != null and is_instance_valid(_kept):
		if _kept.is_inside_tree():
			_kept.queue_free()
		else:
			_kept.free()
	_kept = null
	_kept_key = ""


## Whether a world is waiting for the next title (tests).
static func has_kept() -> bool:
	return _kept != null and is_instance_valid(_kept)


func _key() -> String:
	return "%s:%d" % [map_id, layout_seed]


## The 3D view draws as many pixels as a run's: a run draws its 3D at the window's own pixels times the root's 3D scale
## (rendering/scaling_3d/scale, 0.8 on a phone), and this viewport is as big as the title in canvas units (1080 wide),
## so its scale carries the screen's pixels per canvas unit as well (on a 720 px phone it would draw twice the run's
## pixels without it, on a 1344 px one a third fewer).
func _rescale() -> void:
	if viewport == null or not is_inside_tree():
		return
	var root := get_tree().root
	var canvas := get_viewport_rect().size
	var ratio := float(root.size.y) / canvas.y if canvas.y > 0.0 else 1.0
	viewport.scaling_3d_scale = clampf(root.scaling_3d_scale * ratio, 0.25, 2.0)


## Shows another map (the title's map line steps through them when there are several).
func set_map(id: String) -> void:
	if id == map_id and map != null:
		return
	map_id = id
	if is_inside_tree():
		_build_map()


## The map, rolled from `layout_seed` (Run.map_seed for the length of its _ready, then the run's own value again).
func _build_map() -> void:
	if map:
		# at once: two maps' skies in one world for a frame would fight over the environment
		map.free()
		map = null
	var def: MapDef = Registry.map(map_id)
	var scene: PackedScene = def.scene if def and def.scene else load("res://world/maps/red_canyon/RedCanyon.tscn")
	var t0 := Time.get_ticks_usec()
	var keep: int = Run.map_seed
	Run.map_seed = layout_seed
	map = scene.instantiate()
	map.name = "Map"
	world.add_child(map)
	Run.map_seed = keep
	_feet = _spot_on(map)
	compose()
	build_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	if hero:
		hero.place(_feet)
	_reframe()


## Where the hero stands: `spot` when one is set, else the map's (SPOTS), else where a run starts; the ground's height
## there.
func _spot_on(m: Node3D) -> Vector3:
	var s := spot
	if s == Vector2.INF:
		if SPOTS.has(map_id):
			s = SPOTS[map_id]
		elif m.has_method("player_start"):
			var p: Vector3 = m.player_start()
			s = Vector2(p.x, p.z)
		else:
			s = Vector2.ZERO
	var y: float = m.height_at(s.x, s.y) if m.has_method("height_at") else 0.0
	return Vector3(s.x, y, s.y)


## Pass 83 (lane SCENE; Garry: "Main Menu background scene, looks barren. Can you place the cactuses and other environment
## art that we have in a way that present a nicely composed scene to look at"): the title's own vignette, laid by hand
## round the hero's spot from SCENE_FILE (per map: `clear`, the box round the spot, metres across x and along z (+ towards
## the camera), from which the map's own scatter is taken away; `props`, each {id (the very painting: a kind's own or a
## variant, never picked by the spot), x, z (metres from the spot), scale, flip, sway}), every painting with its ground
## shadow. Laid once a world is built (a kept
## world keeps it). Returns how many paintings it laid.
const SCENE_FILE := "res://art/ui/title_scene.json"
var composed: Array = []


func compose() -> int:
	composed.clear()
	var props = map.get("props") if map else null
	if not props is PropField or not FileAccess.file_exists(SCENE_FILE):
		return 0
	var data = JSON.parse_string(FileAccess.get_file_as_string(SCENE_FILE))
	if not data is Dictionary or not (data as Dictionary).get(map_id) is Dictionary:
		return 0
	var sc: Dictionary = data[map_id]
	var pf := props as PropField
	var c := _feet
	var box = sc.get("clear")
	if box is Dictionary:
		var bx: Array = (box as Dictionary).get("x", [0, 0])
		var bz: Array = (box as Dictionary).get("z", [0, 0])
		pf.remove_where(func(row: Dictionary) -> bool:
			var p: Vector3 = row["pos"]
			return p.x - c.x >= float(bx[0]) and p.x - c.x <= float(bx[1]) and p.z - c.z >= float(bz[0]) and p.z - c.z <= float(bz[1]))
	for e in sc.get("props", []):
		if not e is Dictionary:
			continue
		var d: Dictionary = e
		var x := c.x + float(d.get("x", 0.0))
		var z := c.z + float(d.get("z", 0.0))
		var at := Vector3(x, map.height_at(x, z) if map.has_method("height_at") else c.y, z)
		if pf.add(str(d.get("id", "")), at, float(d.get("scale", 1.0)), bool(d.get("flip", false)), float(d.get("sway", 0.0)), true):
			composed.append(str(d.get("id", "")))
	return composed.size()


## The spot the hero stands on, in the world (tests, captures).
func feet() -> Vector3:
	return _feet


## Frames the hero in `box`, the title's hero box in this control's coordinates: his soles at FEET_FRAC of its height,
## his sprite quad_frac of it tall, the camera at the run's pitch and field of view as far off as that size asks.
func frame(box: Rect2) -> void:
	_box = box
	_reframe()


## The hero's sprite height on the screen, in canvas px.
func quad_px() -> float:
	return _box.size.y * quad_frac


## Where the sprite's foot (its quad's bottom middle, the spot on the ground) sits on the screen.
func ground_px() -> Vector2:
	var soles := _box.position.y + _box.size.y * FEET_FRAC
	return Vector2(_box.get_center().x, soles + (1.0 - FIGURE_FEET) * quad_px())


## The rect the hero's figure takes on the screen (the padlock over a locked one sits on his chest).
func figure_rect() -> Rect2:
	var g := ground_px()
	var q := quad_px()
	var top := g.y - q + FIGURE_TOP * q
	var bottom := g.y - q + FIGURE_FEET * q
	return Rect2(Vector2(g.x - FIGURE_W * q * 0.5, top), Vector2(FIGURE_W * q, bottom - top))


func _reframe() -> void:
	if camera == null or not camera.is_inside_tree() or size.y < 2.0 or _box.size.y < 2.0:
		return
	# the canvas px a metre spans at the hero's depth, so his 1.9 m fill quad_px; the depth that gives with the run's lens
	# (keep height: the field of view spans the screen's height)
	var ppm := quad_px() / HERO_HEIGHT
	_depth = size.y * 0.5 / (ppm * tan(deg_to_rad(FOV_DEG) * 0.5))
	var g := ground_px()
	var lx := (g.x - size.x * 0.5) / ppm
	var ly := (size.y * 0.5 - g.y) / ppm
	var p := deg_to_rad(PITCH_DEG)
	var fwd := Vector3(0.0, -sin(p), -cos(p))
	var up := Vector3(0.0, cos(p), -sin(p))
	camera.global_transform = Transform3D(Basis(Vector3.RIGHT, up, -fwd), _feet - fwd * _depth - Vector3.RIGHT * lx - up * ly)


## How far the camera stands from the hero's sprite, along its view.
func depth() -> float:
	return _depth


## Puts `c` on the sand: standing at once (from_side 0), or running in from that side (+1 the right) while the hero
## standing runs off the other way. `locked`: the figure in near-black, no weapon.
func show_hero(c: CharacterDef, locked: bool, from_side: int = 0) -> void:
	if hero:
		if from_side == 0:
			hero.queue_free()
		else:
			hero.run_off(_feet + Vector3.RIGHT * (-float(from_side) * SWAP_OUT), SWAP_TIME, LEAVE_TIME)
			leaving.append(hero)
		hero = null
	for a in leaving.duplicate():
		if not is_instance_valid(a):
			leaving.erase(a)
	hero = Actor.new()
	hero.name = "Hero"
	hero.stage = self
	world.add_child(hero)
	hero.setup(c, locked)
	if from_side == 0:
		hero.place(_feet)
	else:
		hero.run_in(_feet + Vector3.RIGHT * (float(from_side) * SWAP_IN), _feet, SWAP_TIME)


## The hero standing there just bought (pass 69): his black mask lifts over REVEAL_TIME and his weapon's companion comes
## out, where show_hero would put a new figure in his place.
func reveal() -> void:
	if hero and hero.locked:
		hero.reveal(REVEAL_TIME)


## The hero's sprite (tests): null before show_hero.
func hero_sprite() -> BillboardSprite:
	return hero.sprite if hero else null


## The companion circling the hero (tests): null for a weapon without one, and for a locked hero.
func familiar() -> Node3D:
	return hero.familiar if hero else null


## The terrain's height under a point (the heroes run along it).
func ground_at(x: float, z: float) -> float:
	return map.height_at(x, z) if map and map.has_method("height_at") else _feet.y


## One hero on the stage: his sprite and shadow, his weapon's companion, and the little he does (idling, looking round,
## running in or off).
class Actor extends Node3D:
	## seconds the gun companions' flourishes come apart (a drum's twirl, a kick), the gravity gun's grasp, the guitar's
	## strum; and the strum's spring (ConeWave's numbers)
	const FLOURISH := Vector2(3.5, 5.0)
	## pass 55: the sceptre's strike (its shake, its flare) comes from the behaviour's own helpers
	const SCEPTER := preload("res://core/behaviors/SunScepter.gd")
	const GRASP := Vector2(4.0, 6.0)
	const STRUM := Vector2(2.6, 3.6)
	const ROCK_K := 420.0
	const ROCK_D := 9.0
	const ROCK_KICK := 9.0
	## ConeWave's hold: tipped back to the camera, the neck to the upper left, a lean towards the aim at most
	const TILT_BACK_DEG := 24.0
	const NECK_DEG := 35.0
	const LEAN_DEG := 18.0
	## ProjectileEmitter's hip-shot twirl
	const TWIRL := 0.35
	## how much of the companion's aim follows its place front to back (the rest points it to the side it is on)
	const AIM_Z := 0.35
	## the look round: seconds between looks, a glance's length, a turntable's seconds a view
	const LOOK_EVERY := Vector2(4.5, 6.5)
	const GLANCE := 1.5
	const TURN_STEP := 0.13

	var stage: TitleStage
	var def: CharacterDef
	var locked := false
	var sprite: BillboardSprite
	var shadow: MeshInstance3D
	var weapon: WeaponDef
	var visual: Node3D
	var familiar: Node3D
	## the behaviour that flies the companion in a run: "GravityGun", "ConeWave", or a gun companion (ProjectileEmitter)
	var kind := ""
	var fam: Dictionary = {}
	var fam_pos := Vector3.ZERO
	var _base_scale := Vector3.ONE
	var _orbit := 0.0
	var _aim_yaw := 0.0
	var _recoil := 0.0
	var _twirl_t := -1.0
	var _flap := 0.0
	var _open := 0.0
	var _grasp_t := -1.0
	var _rock := 0.0
	var _rock_v := 0.0
	var _shimmer := 0.0
	var _next := 2.0
	var _drum: Node3D
	var _drum_axis := Vector3.RIGHT
	var _drum_step := 0.5
	var _wing_l: Node3D
	var _wing_r: Node3D
	var _spin: Node3D
	var _core: Node3D
	var _core_mat: StandardMaterial3D
	var _claws: Array = []
	var _strings: MeshInstance3D
	var _string_mat: StandardMaterial3D
	var _string_rest := Vector3.ONE
	var _sun_glow: ShaderMaterial
	var _sun_glow_node: MeshInstance3D
	## a strike's clock (< 0: none) and the kick up the staff it gives (pass 55)
	var _sun_t := -1.0
	var _sun_kick := Vector3.ZERO
	# running: from, to, its length, its clock (< 0: standing), whether he runs off and how long until he is gone
	var _from := Vector3.ZERO
	var _to := Vector3.ZERO
	var _run_time := 0.0
	var _run_t := -1.0
	var _leaving := false
	var _life := 0.0
	var _run_left := false
	# idling: the clock to the next look round, the look's views [[view, flip, seconds], ...] and its clock, the bob
	var _look_in := 3.0
	var _look: Array = []
	var _look_t := 0.0
	var _bob := 0.0
	var _rng := RandomNumberGenerator.new()

	func setup(c: CharacterDef, p_locked: bool) -> void:
		def = c
		locked = p_locked
		_rng.seed = hash(c.id if c else "hero")
		_look_in = _rng.randf_range(LOOK_EVERY.x * 0.6, LOOK_EVERY.y * 0.6)
		_make_sprite()
		_make_shadow()
		if not locked:
			_make_weapon()

	## Pass 69: the black mask lifting (TitleStage.reveal): the tint from LOCKED_TINT to white over `seconds`, then the
	## weapon's companion.
	func reveal(seconds: float) -> void:
		locked = false
		var tw := create_tween()
		tw.tween_method(func(k: float): sprite.set_tint(TitleStage.LOCKED_TINT.lerp(Color.WHITE, k)), 0.0, 1.0, seconds)
		tw.tween_callback(func(): sprite.set_fogless(false))
		tw.tween_callback(_make_weapon)

	## The sprite as Player._setup_sprite makes it: the strip (a drawn stand-in when there is none), its animations and
	## their speeds, 1.9 m, and the pass over his speed trails. Not the outline pass, which draws his outline wherever
	## something stands in front of him: on the title nothing does but his own companion, and close up his outline drawn
	## across the guitar or the gun passing his legs read as a glitch. Pass 55: the strip is the look kept for him
	## (Save.hero_look, else his JSON's `variant`), the one a run will draw.
	func _make_sprite() -> void:
		sprite = BillboardSprite.new()
		sprite.name = "Sprite"
		add_child(sprite)
		var art: CharacterDef = Registry.played_look(def) if def else null
		var tex: Texture2D = art.sprite if art and art.sprite else null
		var anims: Dictionary = art.anims if art else {"idle": 2, "run": 4, "turn": 1, "hit": 1, "die": 1, "cheer": 1}
		if tex == null:
			tex = PlaceholderArt.character_strip(def)
		var cols: int = art.strip_cols if art and art.sprite else 0
		var fps: Dictionary = art.fps if art and art.sprite else {}
		sprite.enable_over_trails()
		sprite.setup(tex, anims, TitleStage.ORDER, TitleStage.HERO_HEIGHT, cols, fps)
		sprite.set_tint(TitleStage.LOCKED_TINT if locked else Color.WHITE)
		# the fog would warm the black mask to brown (pass 69): a locked hero is drawn without it
		sprite.set_fogless(locked)
		sprite.play(_anim("idle", "_f"))

	## The soft dark disc under him (Player.tscn's Shadow: a 1.4 m quad lying flat, squashed as Player._animate does).
	func _make_shadow() -> void:
		shadow = MeshInstance3D.new()
		shadow.name = "Shadow"
		var q := QuadMesh.new()
		q.size = Vector2(1.4, 1.4)
		q.orientation = PlaneMesh.FACE_Y
		shadow.mesh = q
		var m := ShaderMaterial.new()
		m.shader = preload("res://core/shaders/blob_shadow.gdshader")
		shadow.material_override = m
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shadow.position = Vector3(0.0, 0.05, 0.0)
		add_child(shadow)
		_lay_shadow()

	## The shadow lies along the ground under him (Player's lies flat, on the flats where a run starts; here a dune's
	## slope cut it with a hard edge), squashed as Player._animate squashes it.
	func _lay_shadow() -> void:
		if shadow == null or stage == null:
			return
		var p := position
		var dx := stage.ground_at(p.x + 0.5, p.z) - stage.ground_at(p.x - 0.5, p.z)
		var dz := stage.ground_at(p.x, p.z + 0.5) - stage.ground_at(p.x, p.z - 0.5)
		var n := Vector3(-dx, 1.0, -dz).normalized()
		var x := Vector3.RIGHT - n * n.dot(Vector3.RIGHT)
		x = x.normalized()
		var z := x.cross(n)
		shadow.basis = Basis(x * 0.9, n, z * 0.63)

	## His start weapon's companion: the visual scene merged as a run merges it (MeshMerge), everything but the Familiar
	## hidden (a held gun, a blade, the muzzle sparks and the shot show only in a run), and the parts its behaviour moves.
	func _make_weapon() -> void:
		weapon = Registry.start_weapon_for(def)
		if weapon == null or weapon.visual == null:
			return
		var v: Node3D = weapon.visual.instantiate()
		if v.get_node_or_null("Familiar") == null:
			# the Spear: a blade that shows only when it strikes, nothing that floats
			v.free()
			return
		# pass 67: the run's grade on the companion's lit materials (WeaponBehavior.grade_materials), so the title's gun is
		# the gun a run draws
		WeaponBehavior.grade_materials(v, WeaponBehavior.grade_for(Registry.map(stage.map_id) if stage else null, weapon.params))
		MeshMerge.merge(v)
		for ch in v.get_children():
			if ch is Node3D:
				(ch as Node3D).visible = ch.name == "Familiar"
			if ch is CPUParticles3D:
				(ch as CPUParticles3D).emitting = false
		visual = v
		visual.name = "Weapon"
		# its own place in the world: the companion is set where it flies each frame, wherever the hero runs
		visual.top_level = true
		add_child(visual)
		visual.global_transform = Transform3D.IDENTITY
		familiar = visual.get_node("Familiar") as Node3D
		_base_scale = familiar.scale
		kind = weapon.behavior
		var f = weapon.params.get("familiar", {})
		fam = f if f is Dictionary else {}
		match kind:
			"GravityGun":
				_spin = familiar.find_child("Spin", true, false) as Node3D
				_core = familiar.find_child("Core", true, false) as Node3D
				for n in ["ClawA", "ClawB", "ClawC"]:
					var c := familiar.find_child(n, true, false)
					if c:
						_claws.append(c)
				if _core is MeshInstance3D:
					var m: Material = (_core as MeshInstance3D).get_active_material(0)
					if m is StandardMaterial3D:
						_core_mat = (m as StandardMaterial3D).duplicate()
						_core_mat.emission_enabled = true
						(_core as MeshInstance3D).material_override = _core_mat
				_next = _rng.randf_range(GRASP.x * 0.5, GRASP.y * 0.5)
			"ConeWave":
				_strings = familiar.find_child("Strings", true, false) as MeshInstance3D
				if _strings and _strings.mesh:
					_string_rest = _strings.scale
					var base: Material = _strings.material_override if _strings.material_override else _strings.mesh.surface_get_material(0)
					_string_mat = (base.duplicate() if base is StandardMaterial3D else StandardMaterial3D.new()) as StandardMaterial3D
					_string_mat.emission_enabled = true
					_string_mat.emission = Color(1.0, 0.92, 0.65)
					_string_mat.emission_energy_multiplier = 0.0
					_strings.material_override = _string_mat
				_next = _rng.randf_range(STRUM.x * 0.5, STRUM.y * 0.5)
			"SunScepter":
				# pass 54: the plain sceptre has no Zenith count, so its ring stays hidden (SunScepter._setup_charge), and the
				# sunburst behind the sun gets its own material to flare
				var ring := familiar.find_child("Charge", true, false) as Node3D
				if ring:
					ring.visible = false
				var glow := familiar.get_node_or_null("SunGlow") as MeshInstance3D
				if glow and glow.material_override is ShaderMaterial:
					_sun_glow = (glow.material_override as ShaderMaterial).duplicate() as ShaderMaterial
					glow.material_override = _sun_glow
					_sun_glow_node = glow
				_next = _rng.randf_range(FLOURISH.x * 0.5, FLOURISH.y * 0.5)
			_:
				_wing_l = familiar.get_node_or_null("WingL") as Node3D
				_wing_r = familiar.get_node_or_null("WingR") as Node3D
				_drum = familiar.find_child("Drum", true, false) as Node3D
				_drum_axis = Vector3.FORWARD if str(weapon.params.get("drum_axis", "")) == "forward" else Vector3.RIGHT
				_drum_step = float(weapon.params.get("drum_step", 0.5))
				_next = _rng.randf_range(FLOURISH.x * 0.5, FLOURISH.y * 0.5)
		# it starts beside his right shoulder (a little behind it), not at his feet or behind his head
		_orbit = -0.35

	func _fam(key: String, default: float) -> float:
		return float(fam.get(key, default))

	## Standing on `at` now.
	func place(at: Vector3) -> void:
		_run_t = -1.0
		position = at
		_lay_shadow()
		_settle_familiar()

	## Running from `from` to `to` over `seconds`, quick and then easing into his spot. His companion comes in behind him,
	## on his outer side (ahead of him it would pop up on the screen before he does).
	func run_in(from: Vector3, to: Vector3, seconds: float) -> void:
		_from = Vector3(from.x, stage.ground_at(from.x, from.z), from.z)
		_to = to
		_run_time = maxf(seconds, 0.01)
		_run_t = 0.0
		_leaving = false
		_run_left = to.x < from.x
		position = _from
		if familiar:
			_orbit = -0.35 if from.x > to.x else PI + 0.35
		_settle_familiar()
		sprite.play(_anim("run", "_s"))

	## Running off to `to` over `seconds` on the same easing as the one running in, and gone after `life` seconds.
	func run_off(to: Vector3, seconds: float, life: float) -> void:
		_from = position
		_to = to
		_run_time = maxf(seconds, 0.01)
		_run_t = 0.0
		_leaving = true
		_life = maxf(life, seconds)
		_run_left = to.x < position.x
		_look.clear()
		sprite.play(_anim("run", "_s"))

	## Whether he is running in or off.
	func running() -> bool:
		return _run_t >= 0.0

	## The strip may lack a view: the nearest one it has (Player._anim_for's chains).
	func _anim(base: String, view: String) -> String:
		var chain: Array = {"": [""], "_bd": ["_bd", "_s", ""], "_s": ["_s", "_bd", "_fd", ""], "_fd": ["_fd", "_s", "_f"], "_f": ["_f", "_fd", ""]}.get(view, [""])
		for suffix in chain:
			if sprite.has_animation(base + str(suffix)):
				return base + str(suffix)
		return base

	func _process(delta: float) -> void:
		if stage == null:
			return
		_move(delta)
		_animate(delta)
		if familiar:
			_fly(delta)

	func _move(delta: float) -> void:
		if _run_t < 0.0:
			return
		_run_t += delta
		var f := clampf(_run_t / _run_time, 0.0, 1.0)
		# quick, then easing off: both heroes of a swap on the one curve, a constant way apart at least
		var k := 1.0 - (1.0 - f) * (1.0 - f)
		var p := _from.lerp(_to, k)
		p.y = stage.ground_at(p.x, p.z)
		position = p
		_lay_shadow()
		if _leaving:
			if _run_t >= _life:
				queue_free()
			return
		if f >= 1.0:
			_run_t = -1.0
			sprite.play(_anim("idle", "_f"))
			sprite.set_flip(false)

	## The sprite: running, or idling and now and then looking round (a glance to one side, or once in a while a whole
	## turn through his eight views); the breathing bob Player._animate gives him.
	func _animate(delta: float) -> void:
		var moving := _run_t >= 0.0
		if moving:
			sprite.set_flip(_run_left)
		else:
			_look_round(delta)
		_bob += delta * (10.0 if moving else 3.0)
		var b := sin(_bob) * (0.03 if moving else 0.015)
		sprite.set_squash(1.0, 1.0 + b * 0.5)

	func _look_round(delta: float) -> void:
		if not _look.is_empty():
			_look_t -= delta
			if _look_t > 0.0:
				return
			_look.pop_front()
			if _look.is_empty():
				sprite.play(_anim("idle", "_f"))
				sprite.set_flip(false)
				_look_in = _rng.randf_range(LOOK_EVERY.x, LOOK_EVERY.y)
				return
			_show_view(_look[0])
			return
		_look_in -= delta
		if _look_in > 0.0:
			return
		var flip := _rng.randf() < 0.5
		if _rng.randf() < 0.3:
			# the whole turn: front, three quarters, side, back three quarters, back, and round the other side to the front
			_look = [["_fd", flip], ["_s", flip], ["_bd", flip], ["", false], ["_bd", not flip], ["_s", not flip], ["_fd", not flip]]
			for v in _look:
				v.append(TURN_STEP)
		else:
			_look = [["_fd", flip, GLANCE]]
		_show_view(_look[0])

	func _show_view(v: Array) -> void:
		var view: String = v[0]
		sprite.play(_anim("idle", view))
		sprite.set_flip(bool(v[1]) and view in ["_s", "_bd", "_fd"])
		_look_t = float(v[2])

	## The companion where it would be now, at once (a hero placed or starting to run).
	func _settle_familiar() -> void:
		if familiar == null:
			return
		var t := float(Time.get_ticks_msec()) * 0.001
		fam_pos = _want(t)
		_draw_familiar()

	## Where the companion wants to be: its circle round him at its height, bobbing (its behaviour's numbers), pushed back
	## along its barrel by a kick.
	func _want(t: float) -> Vector3:
		var r := _fam("radius", 1.3 if kind == "GravityGun" else 1.25)
		var h := _fam("height", 1.45 if kind == "GravityGun" else (1.5 if kind == "ConeWave" else 1.35))
		var bob := _fam("bob", 0.08 if kind == "GravityGun" else (0.14 if kind == "ConeWave" else 0.12))
		var rate := 2.7 if kind == "GravityGun" else 3.1
		var w := position + Vector3(cos(_orbit) * r, h + sin(t * rate) * bob, sin(_orbit) * r)
		var aim := Vector3(-sin(_aim_yaw), 0.0, -cos(_aim_yaw))
		w -= aim * (0.18 if kind == "GravityGun" else 0.1) * _recoil
		return w

	## The companion's flight, as its behaviour flies it in a run (ProjectileEmitter._place_familiar, GravityGun._place
	## and _animate, ConeWave._place and _tick): round him at its speed, eased after him, turned as it turns, with its
	## own motions; with no creature to aim at, it looks out from him over the sand.
	func _fly(delta: float) -> void:
		var t := float(Time.get_ticks_msec()) * 0.001
		var speed := _fam("speed", 1.0 if kind == "GravityGun" else (1.3 if kind == "ConeWave" else 1.4))
		if kind == "GravityGun" and _open > 0.5:
			# it hangs still while it strains to hold something
			speed *= 0.25
		_orbit += delta * speed
		# eased after him as in a run (a running hero drags it a little); one running off keeps it close, so it leaves the
		# screen with him
		fam_pos = fam_pos.lerp(_want(t), clampf(delta * (30.0 if _leaving else 9.0), 0.0, 1.0))
		# out from him over the sand, leaning to the side it is on: a gun seen side on reads, one pointed at the camera
		# (radially out, passing in front of him) is a stub
		var out := fam_pos - position
		out = Vector3(out.x, 0.0, out.z * AIM_Z)
		if out.length_squared() > 0.0001:
			_aim_yaw = lerp_angle(_aim_yaw, atan2(-out.x, -out.z), clampf(delta * 6.0, 0.0, 1.0))
		_next -= delta
		match kind:
			"GravityGun":
				_fly_gravity(delta, t)
			"ConeWave":
				_fly_guitar(delta, t)
			"SunScepter":
				_fly_sun(delta, t)
			_:
				_fly_gun(delta, t)
		_draw_familiar()

	## A gun companion: turned to its aim, rocking, a kick settling; now and then a flourish (a revolver twirls over its
	## trigger guard as its cylinder clicks round, Hip Shot's twirl; another gun kicks); wings flap.
	func _fly_gun(delta: float, t: float) -> void:
		if _next <= 0.0:
			_next = _rng.randf_range(FLOURISH.x, FLOURISH.y)
			if _drum:
				_twirl_t = 0.0
				_drum.rotate_object_local(_drum_axis, _drum_step)
			else:
				_recoil = 1.0
		var twirl := 0.0
		if _twirl_t >= 0.0:
			_twirl_t += delta
			var f: float = clampf(_twirl_t / TWIRL, 0.0, 1.0)
			twirl = TAU * (1.0 - (1.0 - f) * (1.0 - f))
			if _twirl_t >= TWIRL:
				_twirl_t = -1.0
		familiar.rotation = Vector3(-0.28 * _recoil - twirl, _aim_yaw, sin(t * 2.3) * 0.08 + _fam("roll", 0.0))
		_recoil = maxf(_recoil - delta * 9.0, 0.0)
		_flap += delta * 20.0
		var wing := 0.35 + absf(sin(_flap)) * 0.55
		if _wing_l:
			_wing_l.rotation.z = wing
		if _wing_r:
			_wing_r.rotation.z = -wing

	## The Sun Scepter (pass 54): flown as SunScepter._place flies it in a run, tipped back by its tilt so the sun's face
	## (+Z) looks up at the camera, rocking slowly, turned a little to the side it is on; never yawed out from him like a
	## gun (that turned the sun edge-on). Now and then it strikes as in a run (pass 55): the whole sceptre shakes and the
	## sunburst behind the sun flares (the plain sceptre's is hidden at rest, Zenith's shines all the time).
	func _fly_sun(delta: float, t: float) -> void:
		if _next <= 0.0:
			_next = _rng.randf_range(FLOURISH.x, FLOURISH.y)
			_sun_t = 0.0
		var sh := Vector3.ZERO
		var f := 0.0
		if _sun_t >= 0.0:
			_sun_t += delta
			sh = SCEPTER.shake_at(_sun_t)
			f = SCEPTER.flare_at(_sun_t)
			if _sun_t > 0.5:
				_sun_t = -1.0
		var lean := clampf(-sin(_aim_yaw), -1.0, 1.0) * 0.45
		familiar.rotation = Vector3(-deg_to_rad(_fam("tilt_deg", 28.0)) + sh.x, lean, sin(t * 0.7) * 0.25 + sh.y)
		_sun_kick = familiar.global_transform.basis.y.normalized() * sh.z
		if _sun_glow:
			var sp = weapon.params.get("shine", {})
			var shine: Dictionary = sp if sp is Dictionary else {}
			var st: float = SCEPTER.glow_strength(shine, f, float(shine.get("flare", SCEPTER.SHINE_FLARE)))
			_sun_glow.set_shader_parameter("strength", st)
			if _sun_glow_node:
				_sun_glow_node.visible = st > 0.004

	## The Gravity Gun: the claw ring turning, the claws breathing, the core pulsing; now and then a grasp (the claws open,
	## the ring spins up, the core swells and glows) as if it caught something.
	func _fly_gravity(delta: float, t: float) -> void:
		if _next <= 0.0:
			_next = _rng.randf_range(GRASP.x, GRASP.y)
			_grasp_t = 0.0
		var want := 0.0
		if _grasp_t >= 0.0:
			_grasp_t += delta
			want = 0.7 if _grasp_t < 0.8 else 0.0
			if _grasp_t >= 1.4:
				_grasp_t = -1.0
		_open = move_toward(_open, want, delta * (3.0 if want > _open else 1.8))
		familiar.rotation = Vector3(-0.3 * _recoil + 0.12 * _open, _aim_yaw, sin(t * 2.1) * 0.06)
		_recoil = maxf(_recoil - delta * 5.0, 0.0)
		if _spin:
			_spin.rotate_object_local(Vector3.FORWARD, delta * lerpf(1.2, 11.0, _open))
		for c: Node3D in _claws:
			c.rotation.x = lerpf(0.0, 0.8, _open) + 0.04 * sin(t * 3.0)
		if _core:
			_core.scale = Vector3.ONE * (1.0 + 0.07 * sin(t * 7.0) + 0.45 * _open)
		if _core_mat:
			_core_mat.emission_energy_multiplier = 1.2 + 3.5 * _open + 0.4 * sin(t * 9.0)

	## The Guitarra: held as a player holds a guitar (tipped back to the camera, the neck to the upper left, leaning to its
	## aim); now and then a strum rocks it on its spring and lights the strings.
	func _fly_guitar(delta: float, t: float) -> void:
		if _next <= 0.0:
			_next = _rng.randf_range(STRUM.x, STRUM.y)
			_rock_v += ROCK_KICK
			_shimmer = 1.0
		var steps: int = clampi(int(ceil(delta * 60.0)), 1, 8)
		var h: float = delta / float(steps)
		for k in range(steps):
			_rock_v += (-ROCK_K * _rock - ROCK_D * _rock_v) * h
			_rock = clampf(_rock + _rock_v * h, -1.0, 1.0)
		var aim_x := -sin(_aim_yaw)
		var lean := clampf(aim_x, -1.0, 1.0) * deg_to_rad(_fam("lean_deg", LEAN_DEG))
		var tilt := -deg_to_rad(_fam("tilt_back_deg", TILT_BACK_DEG)) - 0.15 * _rock
		var neck := deg_to_rad(_fam("neck_deg", NECK_DEG)) + 0.32 * _rock + sin(t * 2.1) * 0.04
		familiar.rotation = Vector3(tilt, lean, neck)
		if _strings:
			var j := _shimmer * _shimmer
			_strings.scale = _string_rest * Vector3(1.0 + 0.12 * j * sin(t * 97.0), 1.0, 1.0 + 0.9 * j * absf(sin(t * 131.0)))
			if _string_mat:
				_string_mat.emission_energy_multiplier = 2.6 * j
		_shimmer = maxf(_shimmer - delta * 3.0, 0.0)

	## Puts the companion where it flies. A billboard stands square to the camera through his feet, so a companion behind
	## him at chest height is nearer the camera than his sprite and would be drawn over his face (in a run too, but far
	## off and small). Behind him (north of his feet) it is drawn instead along the same line of sight just past his
	## sprite, scaled by the same factor: it looks exactly the same, and his figure hides it.
	func _draw_familiar() -> void:
		var cam: Camera3D = stage.camera
		var s := 1.0
		var at := fam_pos
		if cam and cam.is_inside_tree():
			var eye := cam.global_position
			var fwd := -cam.global_transform.basis.z
			var feet_d := (position - eye).dot(fwd)
			var d := (fam_pos - eye).dot(fwd)
			if fam_pos.z < position.z and d > 0.1 and d < feet_d + TitleStage.BEHIND:
				s = (feet_d + TitleStage.BEHIND) / d
				at = eye + (fam_pos - eye) * s
		familiar.global_position = at + _sun_kick
		familiar.scale = _base_scale * s
