## Lane SHOTS (the one-pager, 2026-10-26): staged, marketing-grade stills of the real game ("bullshots": its own art, light,
## shadows, stage looks and effects, nothing painted over; a chosen hero, chosen creatures, a composed camera, the HUD
## hidden unless the shot keeps it). Windowed, one shot per process; the world is staged, walks a moment, every weapon
## fires once and the tree is paused, then the frozen moment is captured (with and without the damage numbers).
##   bash tools/godot.sh --audio-driver Dummy --resolution 1920x1080 --path D:/_projects/88fits/game
##        --script res://tools/marketing_shots.gd -- out=<dir> shot=<name> [hero=<id>] [rng=<n>] [...]
## (tools/dl/onepager/shots/_tools/make_all.sh runs every pick the lane kept, with the queue check RULES.md asks for.)
## A landscape window draws its whole canvas (the project keeps a 9:16 canvas on PC: content scaling is switched off).
## The shots (and the window to pass):
##   swarm      (1920x1080) the hero facing a swarm of Lesser Scorpions (LS-B, LS-D bone, LS-E gold, 0.85-1.6x, three
##              specials with their rim) and two Dune Scorpions (elites=SC-C,SC-A; SC-D sand) big at the back, side on: the
##              camera looks out at the fort wall, the hero stands at the frame's right turned `face` degrees to its left
##              (mirror=1: the other way round), the swarm comes across the frame at him in their side views
##   nightfall  (1920x1080) stage 2's blue look by the first oasis: Fire Ants ANT-E/ANT-G, bone Lesser Scorpions LS-D,
##              white and pearl Bull Beetles BB-E/BB-F (before= m from the lake, aside=, look_turn=, lake=0)
##   bloodmoon  (1920x1080) stage 3's hell: imps and hellhounds, two Hammer Giants at the back
##   boss       (1920x1080) boss=king (the stomp's ring) | king_volley | gila (the cactus rain's marks and the spew) |
##              brander (his brand burning on the sand) | brander_slam: the boss under bx=, by= of the picture, its crowd,
##              the attack forced through the attack runner (atk_i / atk_t) and frozen mid-way
##   play       (1080x1920) a scorpion fight from the real gameplay camera (CameraRig, fixed, north up) with a run's HUD (level,
##              clock, purse, weapons, Cards, XP bar, his HP, the thumb on the stick), then without the HUD, then clean
##   horde      (1080x1920) ~270 creatures of the map's roster round a late build (golden_revolver, chicago_typewriter,
##              saw_halo, loudmouth, roman_candle; build=), the gameplay camera, with the HUD and without
##   bestiary   (2400x1000) every creature of red_canyon.json's roster rows, events, specials pool and boss summons (hidden,
##              retired and dummies left out) standing to scale on the sand in their played looks, front view: everything
##              under split= m in front in size order with the hero, the big ones and the three bosses behind; an
##              orthographic camera (pitch=, depth=, wfrac=, gap=, foot=, margin=, cz=)
##   ui         (1080x1920) the in-run screens screenshot_run.gd catches mid-animation, each once it has landed: the
##              level-up cards, the mutation offer after its weapon reel, the Spirit Pole's gifts (a run some minutes in)
##   scout      (any) the hero alone at n= spots round the map, the swarm's camera: for picking a backdrop
## The framing (hero-placed, _frame_h): cam=a|w|k|b|c|d|e or yaw=, pitch=, fov=, hx=, hy= (where the hero's middle lands,
## shares of the frame), hf= (his height, a share of the frame's). The spot: angle= (degrees round the map's centre the
## camera looks out along, 45), radius= (m out), seed= (the map seed, 88). The crowd: rng= (the tool's dice), face=, x0=,
## x1=, y0= (the picture's region the crowd stands under), below= (how far in front of the hero's depth), gap=, keep_off=,
## e1x=, e1y=, e2x=, e2y= (the big ones' points), elite_scale=, props=0 (no framing props), badges=1 (crowns and skulls),
## knock=1 (knockback on: hit creatures turn), freeze= (seconds the crowd walks), flight= (seconds the volley flies before
## the freeze), fire=0 (no volley), numbers=0, clean=0 (no capture without numbers). The hero: hero=, look= (a look code),
## weapons=id:level,... (else HERO_WEAPONS). The HUD shots: level=, xp=, clock=, gold=, kills=, passives=id:level,...
## Also msaa=2|4, tag= (a file name suffix), stage= (0-based, swarm and scout).
## Bounded: a wall-clock watchdog (watchdog=, 170 s) and a frame cap (frames=, 9000) quit with code 2; the save data in
## memory goes back (tools/godot.sh puts the PC save file back) and user://debug_launch.json is never left behind.
## Autoloads and the game's classes are reached through the tree (SceneTree scripts compile before the autoloads exist).
extends SceneTree

const WATCHDOG_S := 170.0
const FRAME_CAP := 9000
const HERO_H := 1.9
## the scorpions' specials: a variance special's tint for a creature whose JSON has none (the Level Editor's row
## `stats.variance` override), a deep wine like the goblins' (its rim glows the tint's hue at full brightness)
const SPECIAL_TINT := "#8A1428"
## each hero's weapons in the staged fights (weapons= overrides): his own gun first
const HERO_WEAPONS := {
	"drifter": [["revolver", 5], ["tommy_gun", 4]],
	"solenne": [["sun_scepter", 5]],
	"calavera": [["guitarra", 5]],
	"fadeaway": [["basketball", 5]],
	"astro": [["gravity_gun", 5], ["orbit_saws", 4]],
	"ironwood": [["pike", 5], ["tommy_gun", 3]],
	"buck": [["frisbee", 5], ["revolver", 3]],
	"may": [["big_mouth", 5], ["tommy_gun", 5]],
}

var A: Dictionary = {}
var _out := ""
var _frames := 0
var _frame_cap := FRAME_CAP
var _save = null
var _keep: Dictionary = {}
var _run = null
var _reg = null
var _settings = null
var g = null
var _ended := false
var _rng := RandomNumberGenerator.new()
var _lines: PackedStringArray = PackedStringArray()
var _C: Dictionary = {}
var _shots: Array = []


# ---------------------------------------------------------------- the frame

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=", true, 1)
		A[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_out = str(A.get("out", "user://marketing_shots"))
	DirAccess.make_dir_recursive_absolute(_out)
	_frame_cap = int(A.get("frames", FRAME_CAP))
	_rng.seed = int(A.get("rng", 88))
	create_timer(float(A.get("watchdog", WATCHDOG_S)), true, false, true).timeout.connect(_bail.bind("watchdog"))
	process_frame.connect(_count)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _count() -> void:
	_frames += 1
	if _frames > _frame_cap:
		_bail("frame cap %d" % _frame_cap)


func _s(k: String, d: String) -> String:
	return str(A.get(k, d))


func _f(k: String, d: float) -> float:
	return float(A.get(k, d))


func _i(k: String, d: int) -> int:
	return int(A.get(k, d))


func _b(k: String, d: bool) -> bool:
	if not A.has(k):
		return d
	return str(A[k]) in ["1", "true", "yes", "on"]


func _log(s: String) -> void:
	print("marketing_shots: " + s)
	_lines.append(s)


func _bail(why: String) -> void:
	if _ended:
		return
	_log("stopped: " + why)
	_finish(2)


func _finish(code: int) -> void:
	if _ended:
		return
	_ended = true
	paused = false
	if _save != null and not _keep.is_empty():
		_save.data = _keep
	if FileAccess.file_exists("user://debug_launch.json"):
		DirAccess.remove_absolute("user://debug_launch.json")
	var f := FileAccess.open(_out.path_join("log_%s%s.txt" % [_s("shot", "swarm"), _tag()]), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
	quit(code)


func _tag() -> String:
	var t := _s("tag", "")
	return ("_" + t) if t != "" else ""


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _frames_wait(n: int) -> void:
	for k in range(n):
		await process_frame


func _shot(name: String) -> void:
	await _frames_wait(3)
	var img: Image = root.get_texture().get_image()
	var path := _out.path_join(name + _tag() + ".png")
	img.save_png(path)
	_shots.append(path)
	_log("saved %s (%dx%d)" % [path, img.get_width(), img.get_height()])


func _main() -> void:
	_run = root.get_node("Run")
	_reg = root.get_node("Registry")
	_save = root.get_node("Save")
	_settings = root.get_node("Settings")
	_keep = _save.data.duplicate(true)
	# no debug buttons, no hit log, no debug panel (in memory only: Settings saves through the Save, which goes back)
	for k in ["debug_modal_buttons", "free_revive_button", "hit_log", "debug_panel", "debug_mode"]:
		_settings.set(k, false)
	var ws: Vector2i = DisplayServer.window_get_size()
	if ws.x > ws.y or _b("native", false):
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	await _frames_wait(2)
	_log("window %s, viewport %s" % [str(DisplayServer.window_get_size()), str(root.get_visible_rect().size)])
	var msaa := _i("msaa", 0)
	if msaa > 0:
		root.msaa_3d = Viewport.MSAA_4X if msaa >= 4 else Viewport.MSAA_2X
	var shot := _s("shot", "swarm")
	_log("shot %s, window %s, args %s" % [shot, str(root.get_visible_rect().size), str(A)])
	match shot:
		"scout":
			await _scout()
		"swarm":
			await _swarm()
		"play":
			await _play()
		"nightfall":
			await _nightfall()
		"bloodmoon":
			await _bloodmoon()
		"boss":
			await _boss()
		"horde":
			await _horde()
		"bestiary":
			await _bestiary()
		"ui":
			await _ui()
		_:
			_log("unknown shot " + shot)
	_finish(0)


# ---------------------------------------------------------------- the run under the camera

## A tool's launch into a plain run (not the arena: no DEBUG ARENA banner, no dummies): `hero` in his played look (or
## `look=`), stage `stage` (0-based), map seed `seed`, the director held from its first tick and the field emptied, every
## spawn standing at once (no rise, no dust), no despawn, colour from the first spawn, every creature drawn.
func _launch(hero: String, stage: int, map_seed: int) -> bool:
	var d := {"character": hero, "map": "red_canyon", "map_seed": map_seed, "stage": stage + 1, "analytics": false}
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	_save.data["runs_started"] = maxi(int(_save.data.get("runs_started", 0)), 1)
	change_scene_to_file("res://game/Game.tscn")
	for k in range(900):
		await process_frame
		var cs = current_scene
		if cs != null and cs.has_method("open_pause") and cs.get("player") != null and cs.get("director") != null and cs.get("enemies") != null:
			g = cs
			break
	if g == null:
		_log("the game never came up")
		return false
	g.director.running = false
	g.no_random_chests = true
	g.player.god = true
	var em = g.enemies
	_C = em.get_script().get_script_constant_map()
	em.kill_all(false)
	await _frames_wait(2)
	g.director.running = false
	em.kill_all(false)
	em.set_spawn_rise(0.0, 0.0, 0.0, 0.0)
	em.set_despawn({})
	em.colour_after_kills = 0
	em.vis_force = 1
	# the structures stand as scenery only: a hero staged inside one's ring would charge it (its pie, a coloured wedge on
	# the sand, then its use: a heal, a drum, a gift screen); their rings and pies are the StructureManager's own children
	if g.get("structures") and g.structures:
		g.structures.process_mode = Node.PROCESS_MODE_DISABLED
		for st in g.structures.items:
			if st.get("ring") != null:
				st.ring.visible = false
			if st.get("pie") != null:
				st.pie.visible = false
	if A.has("look") and g.player.has_method("show_look"):
		g.player.show_look(_s("look", ""))
	if g.get("debug_panel") and g.debug_panel:
		g.debug_panel.visible = false
	_log("launched %s, stage %d, seed %d, hero at %s" % [hero, stage, map_seed, str(g.player.global_position)])
	return true


## The hero's build: `weapons=` (id:level,...) or his entry in HERO_WEAPONS, every one at its level.
func _arm(hero: String) -> void:
	var list: Array = []
	if A.has("weapons"):
		for part in _s("weapons", "").split(","):
			var p: PackedStringArray = part.split(":")
			if p.size() >= 1 and p[0] != "":
				list.append([p[0], int(p[1]) if p.size() > 1 else 5])
	else:
		list = HERO_WEAPONS.get(hero, [["revolver", 5]])
	_run.debug_clear_items()
	for w in list:
		# (a weapon and an evolution are one registry: Registry.weapons holds both)
		var n: int = _run.debug_set_item("weapon", str(w[0]), int(w[1]))
		_log("weapon %s -> level %d" % [str(w[0]), n])
	_run.rebuild_sheets()


## The in-run UI on or off: every child of the UI layer but the damage numbers (the HUD shows itself again on its own
## clock, so it is held as well as hidden), each put back as it was.
var _ui_was: Dictionary = {}


func _hud(on: bool) -> void:
	for c in g.ui.get_children():
		if not (c is CanvasItem) or c == g.get("damage_numbers"):
			continue
		if not on:
			if not _ui_was.has(c):
				_ui_was[c] = [(c as CanvasItem).visible, c.process_mode]
			(c as CanvasItem).visible = false
			c.process_mode = Node.PROCESS_MODE_DISABLED
		elif _ui_was.has(c):
			(c as CanvasItem).visible = bool(_ui_was[c][0])
			c.process_mode = int(_ui_was[c][1])
			_ui_was.erase(c)
	if g.get("debug_panel") and g.debug_panel:
		g.debug_panel.visible = false


func _numbers(on: bool) -> void:
	var dn = g.get("damage_numbers")
	if dn:
		dn.visible = on
		dn.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


## The crowns, skulls and gears over the Elites, the bosses and the special types (off: their type's badge emptied).
func _badges(on: bool) -> void:
	if on:
		return
	var em = g.enemies
	for t in range(em.types.size()):
		em._t_badge[t] = ""


func _ground(x: float, z: float) -> float:
	return float(g.map.height_at(x, z))


func _at(p: Vector3) -> Vector3:
	return Vector3(p.x, _ground(p.x, p.z), p.z)


static func _yaw_of(d: Vector3) -> float:
	return atan2(-d.x, -d.z)


## The hero on `at` looking along `fwd` (flat), standing (no stick), shown in the view the camera `cam_yaw` sees him in
## (Player._animate's sectors: back, back-diagonal, side, front-diagonal, front).
func _place_hero(at: Vector3, fwd: Vector3) -> void:
	var p = g.player
	p.global_position = at + Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	p.facing = _yaw_of(fwd)
	p.rotation.y = p.facing
	p.input.wants_move = false
	p.input.stick_dir = Vector2.ZERO


func _hero_view(cam_yaw: float) -> void:
	var p = g.player
	var rel := angle_difference(cam_yaw, float(p.facing))
	var a := absf(rel)
	var v := "_f"
	if a < PI * 0.125:
		v = ""
	elif a < PI * 0.375:
		v = "_bd"
	elif a < PI * 0.625:
		v = "_s"
	elif a < PI * 0.875:
		v = "_fd"
	p.set("_view", v)
	p.set("_flip", rel > 0.0)


## The game's camera rig parked by hand: its Camera3D at `eye` looking at `target` with a vertical field of view `fov`
## (the rig's own update off), its yaw told to the creatures' and the hero's views, its rest pose to the HUD's anchors.
func _cam_place(eye: Vector3, target: Vector3, fov: float) -> void:
	var rig = g.camera
	rig.set_process(false)
	var d := target - eye
	rig.global_transform = Transform3D(Basis.looking_at(d.normalized(), Vector3.UP), eye)
	rig.camera.fov = fov
	rig.yaw = _yaw_of(Vector3(d.x, 0, d.z))
	rig.set("_rest_xf", rig.global_transform)


## A framing solved from where the hero should stand in the picture: the camera looks along `look` turned `yaw` degrees
## (positive: to the left), `pitch` degrees down, a vertical field of view `fov`; the hero's middle lands at `hx`, `hy`
## (shares of the frame from its top left) and he is `hf` of the frame's height tall.
func _frame_h(hero_at: Vector3, look: Vector3, fr: Dictionary) -> void:
	var yaw := _yaw_of(look) + deg_to_rad(float(fr.get("yaw", 0.0)))
	var pitch := deg_to_rad(float(fr.get("pitch", 16.0)))
	var fov := float(fr.get("fov", 40.0))
	var vs: Vector2 = root.get_visible_rect().size
	var aspect := vs.x / maxf(vs.y, 1.0)
	var t := tan(deg_to_rad(fov) * 0.5)
	var f := Vector3(-sin(yaw), 0, -cos(yaw)) * cos(pitch) + Vector3(0, -sin(pitch), 0)
	var basis := Basis.looking_at(f, Vector3.UP)
	var z := HERO_H / (float(fr.get("hf", 0.25)) * 2.0 * t)
	var xc := (2.0 * _mx(float(fr.get("hx", 0.68))) - 1.0) * aspect * t * z
	var yc := (1.0 - 2.0 * float(fr.get("hy", 0.66))) * t * z
	var mid := hero_at + Vector3(0, HERO_H * 0.5, 0)
	var eye: Vector3 = mid - basis * Vector3(xc, yc, -z)
	var gy := _ground(eye.x, eye.z) + 0.6
	if eye.y < gy:
		eye.y = gy
	var rig = g.camera
	rig.set_process(false)
	rig.global_transform = Transform3D(basis, eye)
	rig.camera.fov = fov
	rig.yaw = yaw
	rig.set("_rest_xf", rig.global_transform)
	var cam: Camera3D = rig.camera
	var feet: Vector2 = cam.unproject_position(g.player.global_position)
	var head: Vector2 = cam.unproject_position(g.player.global_position + Vector3(0, HERO_H, 0))
	_log("frame %s: eye %s, hero feet at %.2f x %.2f, %.1f%% of the height" % [str(fr), str(eye.snapped(Vector3(0.1, 0.1, 0.1))), feet.x / vs.x, feet.y / vs.y, 100.0 * (feet.y - head.y) / vs.y])


## The ground under the screen point at `sx`, `sy` (shares of the frame), on the map's ground.
func _ground_ray(sx: float, sy: float) -> Vector3:
	var cam: Camera3D = g.camera.camera
	var vs: Vector2 = root.get_visible_rect().size
	var sp := Vector2(sx * vs.x, sy * vs.y)
	var o := cam.project_ray_origin(sp)
	var dv := cam.project_ray_normal(sp)
	var h: float = g.player.global_position.y
	var p := o
	for it in range(6):
		if absf(dv.y) < 0.001:
			break
		var tt := (h - o.y) / dv.y
		p = o + dv * tt
		h = _ground(p.x, p.z)
	return Vector3(p.x, h, p.z)


## Props off a box in front of the hero (`x0`..`x1` m across his right, `z0`..`z1` m along his look), so nothing painted
## stands between the camera and the fight; the rest of the map's scatter stays as the seed laid it.
func _clear_props(at: Vector3, fwd: Vector3, x0: float, x1: float, z0: float, z1: float) -> int:
	var props = g.map.get("props")
	if props == null:
		return 0
	var right := Vector3(-fwd.z, 0, fwd.x)
	var n: int = props.remove_where(func(row: Dictionary) -> bool:
		var p: Vector3 = row["pos"] - at
		var x := p.dot(right)
		var z := p.dot(fwd)
		return x >= x0 and x <= x1 and z >= z0 and z <= z1)
	# the barrels and the signposts standing there go too (their own nodes), and every ground shadow left in the box (the
	# barrels', the signs' and the structures' lie in the scenery's shadow field)
	for c in g.get_children():
		if c.name == "Barrels" or c.name == "Signs":
			for b in c.get_children():
				if b is Node3D and b.name != "Warm":
					var q: Vector3 = (b as Node3D).global_position - at
					if q.dot(right) >= x0 and q.dot(right) <= x1 and q.dot(fwd) >= z0 and q.dot(fwd) <= z1:
						(b as Node3D).visible = false
	var sat = props.get("_shadow_at")
	if sat is PackedVector3Array:
		for i in range(props.shadow_count()):
			var q2: Vector3 = (sat as PackedVector3Array)[i] - at
			if q2.dot(right) >= x0 and q2.dot(right) <= x1 and q2.dot(fwd) >= z0 and q2.dot(fwd) <= z1:
				props.hide_shadow(i)
	return n


## The structures (totems, shops, wells) within `r` m of `at` hidden with their ground shadows, so a painted building
## does not stand in the fight, and every structure's ring and pie on the sand hidden (a gameplay mark, not scenery).
func _hide_structures(at: Vector3, r: float) -> void:
	if g.get("structures") == null or g.structures == null:
		return
	for st in g.structures.items:
		if st.get("ring") != null:
			st.ring.visible = false
		if st.get("pie") != null:
			st.pie.visible = false
		if st is Node3D and (st as Node3D).global_position.distance_to(at) < r:
			(st as Node3D).visible = false
			if st.get("glow") != null:
				st.glow.visible = false
			g.structures.shadow_k(st, 0.0)


## One creature: `special` makes it a variance special (x1.5 with its glowing rim; a creature whose JSON has no special
## gets SPECIAL_TINT through a row's `stats.variance` override, as the Level Editor writes it), `hp` its health factor (the
## staged ones outlive the weapons), held from charging and from its scripted attacks for `hold` seconds.
func _spawn(id: String, at: Vector3, scale: float = 1.0, variant: String = "", special: bool = false, hp: float = 400.0, hold: float = 60.0) -> int:
	var em = g.enemies
	var ov := {}
	if special:
		var def = _reg.enemy(id)
		if def != null and (def.variance as Dictionary).is_empty():
			ov = {"variance": {"special": {"tint": SPECIAL_TINT, "tint_strength": 0.55}}}
		em.force_special = true
	var i: int = em.spawn(id, _at(at), null, scale, hp, variant, ov)
	em.force_special = false
	if i < 0:
		return i
	# a ranged brain's spawn walks it out to its stand-off (the rocketeer's 28 m, the sniper's 26 m): put back where staged
	em.pos[i] = _at(at)
	em.home[i] = em.pos[i]
	if hold > 0.0:
		em.cooldown[i] = hold
		em.atk_t[i] = hold
	return i


## mirror=1: the picture laid out the other way round (the hero on the left facing right, the swarm on the right): every
## share across the frame is read from the right (_mx), the hero's turn is the other way.
var _mirror := false


func _mx(x: float) -> float:
	return 1.0 - x if _mirror else x


## Whether a creature standing on `p`, `tall` m tall, is whole inside the picture (its feet above the frame's foot, its
## top below the frame's top, both clear of the sides; `_frame_box` sets the margins, shares of the frame).
var _frame_box := Rect2(0.02, 0.03, 0.96, 0.95)


func _in_frame(p: Vector3, tall: float, half_w: float = 0.8) -> bool:
	var cam: Camera3D = g.camera.camera
	var vs: Vector2 = root.get_visible_rect().size
	var q := _at(p)
	if cam.is_position_behind(q):
		return false
	var side: Vector3 = cam.global_transform.basis.x.normalized() * half_w
	for c: Vector3 in [q - side, q + side, q + Vector3(0, tall, 0) - side, q + Vector3(0, tall, 0) + side]:
		if not _frame_box.has_point(cam.unproject_position(c) / vs):
			return false
	return true


## `n` ground spots under random points of the picture's region x0..x1, y0..y1 (shares of the frame; `bias` > 1 crowds them
## towards x0), at least `gap` m apart, each one whole in the picture for a creature `tall` m tall and `half_w` m wide.
func _screen_spots(n: int, x0: float, x1: float, y0: float, y1: float, gap: float, tall: float, half_w: float, bias: float = 1.0, keep_off: float = 0.0) -> Array:
	var out: Array = []
	var tries := 0
	var hp: Vector3 = g.player.global_position
	while out.size() < n and tries < n * 300:
		tries += 1
		var u := pow(_rng.randf(), bias)
		var p := _ground_ray(lerpf(x0, x1, u), _rng.randf_range(y0, y1))
		if keep_off > 0.0 and Vector2(p.x - hp.x, p.z - hp.z).length() < keep_off:
			continue
		if not _in_frame(p, tall, half_w):
			continue
		var ok := true
		for q: Vector3 in out:
			if Vector2(p.x - q.x, p.z - q.z).length() < gap:
				ok = false
				break
		if ok:
			out.append(p)
	return out


## Painted props laid into the picture by where they should stand in it: [id, sx, sy, scale, flip] each, the spot the
## ground under that screen point (PropField.add, the painting itself; the map's own scatter stays).
func _set_props(list: Array) -> void:
	var props = g.map.get("props")
	if props == null:
		return
	for e in list:
		var at := _ground_ray(_mx(float(e[1])), float(e[2]))
		var fl: bool = bool(e[4]) if e.size() > 4 else false
		var ok: bool = props.add(str(e[0]), at, float(e[3]), fl != _mirror, 0.02, true)
		_log("prop %s at %s: %s" % [str(e[0]), str(at.snapped(Vector3(0.1, 0.1, 0.1))), str(ok)])


## The hit flashes off and the crowd drawn again as it stands (a frozen frame mid-flash is a white blob).
func _calm() -> void:
	var em = g.enemies
	for i in range(int(_C.get("MAX", 320))):
		if em.alive[i] == 1:
			em.flash[i] = 0.0
	em._render()


## Fisher-Yates on the tool's own dice (Array.shuffle uses the global ones: a rerun with the same rng= would differ).
func _shuffle(a: Array) -> void:
	for k in range(a.size() - 1, 0, -1):
		var j := _rng.randi_range(0, k)
		var t = a[k]
		a[k] = a[j]
		a[j] = t


func _freeze() -> void:
	paused = true


## Every weapon fires now (the frozen frame then holds its rounds in the air), its clock then set as a pull sets it.
func _fire_all() -> void:
	for id in g._behaviors.keys():
		var b = g._behaviors[id]
		if b != null and b.has_method("_fire"):
			b.cooldown_left = 0.0
			b._fire()
			b.cooldown_left = maxf(float(b.stat("cooldown", 1.0)), 0.05) if b.has_method("stat") else 1.0


## The weapons held from firing (false: every clock wound up) or let go (true). The weapon host keeps running, so a
## companion gun follows the hero and turns to its target while it waits; nothing fires until _fire_all.
func _weapons_free(on: bool) -> void:
	for id in g._behaviors.keys():
		var b = g._behaviors[id]
		if b != null:
			b.cooldown_left = 0.0 if on else 1.0e6


## The staged moment's last `walk` seconds, then the freeze: the crowd walks with the weapons held (no smoke, no numbers
## from shots before the one that counts), then every weapon fires at once and the world stops `flight` seconds later
## (fire=0: no shot at all), the hit flashes off.
func _volley(walk: float) -> void:
	_weapons_free(false)
	if not _b("knock", false):
		# the staged crowd takes no knockback: a hit creature would turn its back on the hero for the frame (its view
		# follows its velocity, and the shove is part of it)
		var em = g.enemies
		for t in range(em.types.size()):
			em._t_kbt[t] = 0.0
	await _wait(maxf(walk, 0.05))
	if _b("fire", true):
		if g.get("damage_numbers") and g.damage_numbers:
			g.damage_numbers.clear()
		_fire_all()
		await _wait(_f("flight", 0.16))
	_freeze()
	_calm()
	_log_marks()


## Every ground mark on the sand at the freeze (Telegraphs' children: rings, discs, lines), for the log: a staged frame
## should hold none but what the shot means to show.
func _log_marks() -> void:
	var tg = g.get("telegraphs")
	if tg == null:
		return
	for c in tg.get_children():
		if c is Node3D and (c as Node3D).is_visible_in_tree():
			_log("ground mark %s (%s) at %s" % [str(c.name), c.get_class(), str((c as Node3D).global_position.snapped(Vector3(0.1, 0.1, 0.1)))])


## The hero's spot: `angle` degrees round the map's centre (0 = north, 90 = east), `radius` m out, looking outwards at the
## wall unless `inward`.
func _spot(angle_deg: float, radius: float, inward: bool = false) -> Dictionary:
	var a := deg_to_rad(angle_deg)
	var out := Vector3(sin(a), 0, -cos(a))
	var at := _at(out * radius)
	return {"at": at, "fwd": -out if inward else out}


# ---------------------------------------------------------------- scout

func _scout() -> void:
	if not await _launch(_s("hero", "drifter"), _i("stage", 0), _i("seed", 88)):
		return
	_hud(false)
	_numbers(false)
	var n := _i("n", 8)
	var r := _f("radius", 30.0)
	var frames := _hframings()
	for k in range(n):
		var ang := _f("angle", 0.0) + 360.0 * float(k) / float(n)
		var sp := _spot(ang, r)
		_place_hero(sp["at"], sp["fwd"])
		_frame_h(sp["at"], sp["fwd"], frames[0])
		_hero_view(float(g.camera.yaw))
		await _wait(0.3)
		await _shot("scout_a%03d" % int(ang))


# ---------------------------------------------------------------- swarm (the scorpions)

## The scorpion swarm's cast: [id, count, look, scale min, scale max, specials among them].
const SWARM_CAST := [
	["lesser_scorpion", 3, "LS-B", 1.0, 1.2, 3],
	["lesser_scorpion", 26, "LS-B", 0.85, 1.6, 0],
	["lesser_scorpion", 12, "LS-D", 0.85, 1.55, 0],
	["lesser_scorpion", 11, "LS-E", 0.9, 1.6, 0],
]
## Props laid round the side-on swarm's frame (the hero on the right, the swarm from the left).
const SWARM_PROPS_SIDE := [
	["saguaro_big", 0.02, 0.74, 1.0, false],
	["boulder_b", 0.97, 0.99, 0.6, true],
	["dead_tree", 0.93, 0.42, 0.95, true],
	["skull", 0.50, 0.985, 0.8, false],
]
func _swarm() -> void:
	var hero := _s("hero", "drifter")
	if not await _launch(hero, _i("stage", 0), _i("seed", 88)):
		return
	_arm(hero)
	var sp := _spot(_f("angle", 45.0), _f("radius", 32.0))
	var bigs: Array = []
	var ep := [[0.27, 0.385], [0.49, 0.38], [0.12, 0.43]]
	var e := 0
	for code in _s("elites", "SC-C,SC-A").split(","):
		if code != "" and e < 3:
			bigs.append(["dune_scorpion", code, _f("elite_scale", 1.55), _f("e%dx" % (e + 1), float(ep[e][0])), _f("e%dy" % (e + 1), float(ep[e][1]))])
			e += 1
	await _crowd_shot("swarm", hero, sp["at"], sp["fwd"], SWARM_CAST, bigs, SWARM_PROPS_SIDE)


## A staged fight seen side on (the swarm's, Nightfall's, the Blood Moon's): the camera looks along `look` (out at the
## wall), the hero stands where the framing puts him, turned `face` degrees to the left of the look (mirror=1: to the
## right, the picture laid out the other way), the `cast` ([id, count, look, scale min, scale max, specials among them])
## dealt over ground spots under the picture's far side from him, kept whole in the frame and behind (or a little in front
## of) his depth so they walk across the frame towards him in their side views, the `bigs` ([id, look, scale, sx, sy])
## standing under chosen points of the picture at the back, `props` ([id, sx, sy, scale, flip]) laid round the frame.
## The crowd walks `freeze` seconds with the weapons held, then every weapon fires once and the moment freezes; captured
## with the damage numbers and without (clean=0: only with).
func _crowd_shot(name: String, hero: String, at: Vector3, look: Vector3, cast: Array, bigs: Array, props: Array) -> void:
	_hud(false)
	_numbers(_b("numbers", true))
	_mirror = _b("mirror", false)
	var face := _f("face", 72.0)
	var fwd: Vector3 = look.rotated(Vector3.UP, deg_to_rad(-face if _mirror else face))
	_place_hero(at, fwd)
	var frames := _hframings()
	_frame_h(at, look, frames[0])
	_hero_view(float(g.camera.yaw))
	_clear_props(at, fwd, -16.0, 16.0, -8.0, 34.0)
	_hide_structures(at + fwd * 10.0, 40.0)
	if _b("props", true):
		_set_props(props)
	await _wait(0.3)
	var total := 0
	for c in cast:
		total += int(c[1])
	# side on: under the picture's far part from him, thinning towards him, behind his depth or a little in front of it
	var cam: Camera3D = g.camera.camera
	var feet_y: float = cam.unproject_position(g.player.global_position).y / root.get_visible_rect().size.y
	_frame_box = Rect2(0.04, 0.03, 0.96 - _f("box_x", 0.075), 0.95) if _mirror else Rect2(_f("box_x", 0.075), 0.03, 0.96 - _f("box_x", 0.075), 0.95)
	var spots := _screen_spots(total, _mx(_f("x0", 0.14)), _mx(_f("x1", 0.62)), _f("y0", 0.30), _f("y1", feet_y + _f("below", 0.12)), _f("gap", 1.25), _f("tall", 2.2), _f("half_w", 1.0), _f("bias", 1.3), _f("keep_off", 3.0))
	_frame_box = Rect2(0.02, 0.03, 0.96, 0.95)
	_shuffle(spots)
	# the cast dealt out over the spots in a shuffled order, so a short list of spots still mixes every look; the specials
	# on the far half of the spots (the weapons take the nearest special first: one beside the hero drew every round and
	# its splashes into a pink pool at his feet)
	var deal: Array = []
	for c in cast:
		for j in range(int(c[1])):
			deal.append([c, j < int(c[5])])
	_shuffle(deal)
	var hp: Vector3 = g.player.global_position
	var far: Array = spots.duplicate()
	far.sort_custom(func(a: Vector3, b: Vector3) -> bool: return Vector2(a.x - hp.x, a.z - hp.z).length() > Vector2(b.x - hp.x, b.z - hp.z).length())
	far = far.slice(0, maxi(int(far.size() * 0.5), 1))
	var plain_spots: Array = spots.duplicate()
	var placed := 0
	for d in deal:
		if not bool(d[1]) or far.is_empty():
			continue
		var at_s: Vector3 = far.pop_at(_rng.randi_range(0, far.size() - 1))
		plain_spots.erase(at_s)
		var c0: Array = d[0]
		_spawn(str(c0[0]), at_s, _rng.randf_range(float(c0[3]), float(c0[4])), str(c0[2]), true)
		placed += 1
	var k := 0
	for d in deal:
		if bool(d[1]):
			continue
		if k >= plain_spots.size():
			break
		var c: Array = d[0]
		_spawn(str(c[0]), plain_spots[k], _rng.randf_range(float(c[3]), float(c[4])), str(c[2]), false)
		k += 1
		placed += 1
	_log("%s: %d placed on %d of %d spots" % [name, placed, spots.size(), total])
	for b in bigs:
		_spawn(str(b[0]), _ground_ray(_mx(float(b[3])), float(b[4])), float(b[2]), str(b[1]))
	_badges(_b("badges", false))
	g.enemies._rebuild_grid()
	await _volley(_f("freeze", 1.1))
	for f in range(frames.size()):
		_frame_h(at, look, frames[f])
		await _shot("%s_%s_%s" % [name, hero, str(frames[f].get("name", str(f)))])
	if _b("clean", true):
		_numbers(false)
		for f in range(frames.size()):
			_frame_h(at, look, frames[f])
			await _shot("%s_%s_%s_nonum" % [name, hero, str(frames[f].get("name", str(f)))])


## The hero-placed framings `cam=` names (a,w,...), or one built from yaw=, pitch=, fov=, hx=, hy=, hf= (then named "x").
## a: the key art, the hero a third of the frame's height at its right, the camera 12 degrees down, so the wall, the
##    cliffs and the crowd's far end make the backdrop; w: wider and higher, the hero a quarter of the height; k: higher
##    still (19 degrees), the ground of the fight shows (the bosses' marks, the oasis). A shot without cam= takes
##    _cam_default (the swarm's and the Blood Moon's a, the bosses' and Nightfall's k).
var _cam_default := "a"


func _hframings() -> Array:
	var presets := {
		"k": {"name": "k", "yaw": 0.0, "pitch": 19.0, "fov": 40.0, "hx": 0.72, "hy": 0.66, "hf": 0.28},
		"a": {"name": "a", "yaw": 0.0, "pitch": 12.0, "fov": 44.0, "hx": 0.74, "hy": 0.65, "hf": 0.36},
		"w": {"name": "w", "yaw": 0.0, "pitch": 16.0, "fov": 44.0, "hx": 0.76, "hy": 0.68, "hf": 0.25},
		"b": {"name": "b", "yaw": -18.0, "pitch": 17.0, "fov": 40.0, "hx": 0.72, "hy": 0.70, "hf": 0.24},
		"c": {"name": "c", "yaw": 18.0, "pitch": 20.0, "fov": 42.0, "hx": 0.30, "hy": 0.72, "hf": 0.24},
		"d": {"name": "d", "yaw": -6.0, "pitch": 9.0, "fov": 46.0, "hx": 0.64, "hy": 0.74, "hf": 0.30},
		"e": {"name": "e", "yaw": 0.0, "pitch": 26.0, "fov": 40.0, "hx": 0.66, "hy": 0.74, "hf": 0.22},
	}
	var out: Array = []
	if A.has("pitch") or A.has("hf"):
		out.append({"name": "x", "yaw": _f("yaw", 0.0), "pitch": _f("pitch", 16.0), "fov": _f("fov", 40.0), "hx": _f("hx", 0.68), "hy": _f("hy", 0.70), "hf": _f("hf", 0.25)})
	for c in _s("cam", _cam_default).split(","):
		if presets.has(c):
			out.append(presets[c])
	if out.is_empty():
		out.append(presets["a"])
	return out


# ---------------------------------------------------------------- play (the gameplay camera, portrait)

func _play() -> void:
	var hero := _s("hero", "drifter")
	if not await _launch(hero, _i("stage", 0), _i("seed", 88)):
		return
	_arm(hero)
	_hud_build()
	_numbers(true)
	_hud(true)
	var sp := _spot(_f("angle", 45.0), _f("radius", 24.0), true)
	var at: Vector3 = sp["at"]
	var fwd := Vector3(0, 0, -1)
	_place_hero(at, fwd)
	_clear_props(at, fwd, -10.0, 10.0, -14.0, 18.0)
	_hide_structures(at, 30.0)
	g.camera.snap_to(g.player)
	await _wait(0.4)
	# a crowd closing in from every side, thickest up the screen (where they come from as he walks north), scorpions of
	# every look and size, a few specials, two Dune Scorpions (crowned Elites) at the back
	var looks := ["LS-B", "LS-B", "LS-B", "LS-D", "LS-E"]
	var n := _i("count", 58)
	var placed: Array = []
	var tries := 0
	while placed.size() < n and tries < 4000:
		tries += 1
		# up the screen twice as often as down it
		var a := _rng.randf_range(-PI, PI)
		if sin(a) > 0.0 and _rng.randf() < 0.55:
			a = -a
		var r := _rng.randf_range(_f("r0", 3.6), _f("r1", 10.5))
		var p: Vector3 = at + Vector3(cos(a) * r * 0.7, 0, sin(a) * r)
		if Vector2(p.x - at.x, p.z - at.z).length() < _f("keep_off", 3.1):
			continue
		if not g.camera.on_screen(p + Vector3(0, 0.8, 0), -40.0):
			continue
		var ok := true
		for q: Vector3 in placed:
			if Vector2(p.x - q.x, p.z - q.z).length() < _f("gap", 1.05):
				ok = false
				break
		if ok:
			placed.append(p)
	for k in range(placed.size()):
		_spawn("lesser_scorpion", placed[k], _rng.randf_range(0.85, 1.4), str(looks[_rng.randi() % looks.size()]), k < 3)
	_spawn("dune_scorpion", at + Vector3(-2.6, 0, -11.5), 1.15, "SC-C")
	_spawn("dune_scorpion", at + Vector3(3.2, 0, -13.5), 1.1, "SC-A")
	_badges(true)
	g.enemies._rebuild_grid()
	_log("play: %d scorpions round the hero" % placed.size())
	# the thumb on the stick for the last moment: stepping up-left, so the ring and its knob show
	_weapons_free(false)
	var em = g.enemies
	for t in range(em.types.size()):
		em._t_kbt[t] = 0.0
	await _wait(maxf(_f("freeze", 1.3) - 0.3, 0.05))
	var inp = g.player.input
	var vs: Vector2 = root.get_visible_rect().size
	inp.origin = Vector2(vs.x * 0.5, vs.y * 0.80)
	inp.touch_pos = inp.origin + Vector2(-vs.x * 0.035, -vs.x * 0.05)
	inp.wants_move = true
	await _wait(0.14)
	if g.get("damage_numbers") and g.damage_numbers:
		g.damage_numbers.clear()
	_fire_all()
	await _wait(_f("flight", 0.16))
	_freeze()
	_calm()
	await _shot("play_%s_hud" % hero)
	_numbers(false)
	await _shot("play_%s_hud_nonum" % hero)
	_numbers(true)
	_hud(false)
	await _shot("play_%s_nohud" % hero)
	_numbers(false)
	await _shot("play_%s_clean" % hero)


## The HUD of a run some minutes in: the hero's level and his XP part way, the clock, the purse, a few Cards and passive
## items in their slots (level=, xp=, clock=, gold=; passives= id:level,...).
func _hud_build() -> void:
	var plist := _s("passives", "multishot:3,haste:2,deadeye:2,quickdraw:2,beer:1")
	for part in plist.split(","):
		var p: PackedStringArray = part.split(":")
		if p.size() >= 1 and p[0] != "":
			_run.debug_set_item("passive", p[0], int(p[1]) if p.size() > 1 else 1)
	_run.level = _i("level", 14)
	var need: float = float(_run.xp_to_next())
	_run.xp = need * _f("xp", 0.62)
	_run.run_gold = _i("gold", 312)
	_run.kills = _i("kills", 612)
	_run.rebuild_sheets()
	_run.xp_changed.emit(_run.xp, _run.xp_to_next())
	_run.gold_changed.emit(_run.run_gold)
	if g.hud.get("test_stage_clock") != null:
		g.hud.test_stage_clock = {"stage_seconds": _f("clock", 252.0)}


# ---------------------------------------------------------------- nightfall, blood moon

## Nightfall's crowd (stage 2's recolours: white and pearl Bull Beetles, gold Fire Ants, bone scorpions).
const NIGHT_CAST := [
	["fire_ant", 13, "ANT-E", 1.0, 1.45, 1],
	["fire_ant", 12, "ANT-G", 1.0, 1.45, 0],
	["lesser_scorpion", 10, "LS-D", 0.95, 1.5, 1],
	["bull_beetle", 3, "BB-E", 1.0, 1.2, 0],
	["bull_beetle", 3, "BB-F", 1.0, 1.2, 0],
]
## The Blood Moon's crowd: imps and hellhounds, the Hammer Giants big at the back.
const HELL_CAST := [
	["imp", 20, "", 0.95, 1.3, 1],
	["hellhound", 14, "", 0.95, 1.25, 1],
]
const NIGHT_PROPS := [
	["fan_palm", 0.03, 0.70, 0.95, false],
	["agave_b", 0.97, 0.985, 0.9, true],
	["desert_bush", 0.12, 0.985, 0.8, false],
]
const HELL_PROPS := [
	["dead_tree", 0.03, 0.72, 1.05, false],
	["skull", 0.95, 0.985, 0.9, true],
	["bones", 0.40, 0.985, 0.9, false],
]


func _nightfall() -> void:
	_cam_default = "k"
	var hero := _s("hero", "solenne")
	if not await _launch(hero, 1, _i("seed", 88)):
		return
	_arm(hero)
	var sp := _spot(_f("angle", 45.0), _f("radius", 30.0))
	var at: Vector3 = sp["at"]
	var look: Vector3 = sp["fwd"]
	if _b("lake", true) and g.map.has_method("lake_center"):
		# an oasis in the picture: the camera looks out over its first lake, the hero on this side of it, to its right
		var lc: Vector2 = g.map.call("lake_center")
		var lr: float = float(g.map.call("lake_radius"))
		var c := Vector3(lc.x, 0, lc.y)
		look = (c.normalized() if c.length() > 1.0 else Vector3(0, 0, -1))
		look = look.rotated(Vector3.UP, deg_to_rad(_f("look_turn", 0.0)))
		var right := Vector3(-look.z, 0, look.x)
		at = _at(c - look * (lr + _f("before", 8.0)) + right * _f("aside", 5.0) * (-1.0 if _b("mirror", false) else 1.0))
		_log("nightfall: lake at %s r %.1f, hero at %s" % [str(c), lr, str(at)])
	var bigs := [["bull_beetle", "BB-E", 1.4, _f("e1x", 0.30), _f("e1y", 0.47)], ["bull_beetle", "BB-F", 1.35, _f("e2x", 0.52), _f("e2y", 0.44)]]
	await _crowd_shot("nightfall", hero, at, look, NIGHT_CAST, bigs, NIGHT_PROPS)


func _bloodmoon() -> void:
	var hero := _s("hero", "calavera")
	if not await _launch(hero, 2, _i("seed", 88)):
		return
	_arm(hero)
	var sp := _spot(_f("angle", 45.0), _f("radius", 32.0))
	var bigs := [["hammer_giant", "", 1.05, _f("e1x", 0.26), _f("e1y", 0.38)], ["hammer_giant", "", 1.0, _f("e2x", 0.50), _f("e2y", 0.37)]]
	await _crowd_shot("bloodmoon", hero, sp["at"], sp["fwd"], HELL_CAST, bigs, HELL_PROPS)


# ---------------------------------------------------------------- the bosses

## boss=king|gila|brander: [boss id, stage (0-based), its attacks forced one after another ([name, seconds to let it run
## before the next]; the last one's seconds are the freeze), its crowd [id, count, look, scale min, scale max, specials]].
const BOSSES := {
	"king": ["tumbleweed_king", 0, [["stomp", 1.55]], [["tumbleweed_minion", 12, "", 0.95, 1.25, 0], ["lesser_scorpion", 8, "LS-B", 0.9, 1.4, 0], ["lesser_scorpion", 4, "LS-E", 0.9, 1.4, 0]]],
	"king_volley": ["tumbleweed_king", 0, [["tumbleweed_volley", 1.45]], [["tumbleweed_minion", 12, "", 0.95, 1.25, 0], ["lesser_scorpion", 8, "LS-B", 0.9, 1.4, 0]]],
	"brander_slam": ["brander", 2, [["brand", 1.7], ["slam", 0.6]], [["imp", 16, "", 0.95, 1.3, 0], ["hellhound", 10, "", 0.95, 1.2, 0]]],
	"gila": ["gila_grande", 1, [["cactus_rain", 1.95]], [["fire_ant", 12, "ANT-E", 1.0, 1.4, 0], ["fire_ant", 8, "ANT-G", 1.0, 1.4, 0], ["bull_beetle", 3, "BB-E", 1.0, 1.15, 0]]],
	"brander": ["brander", 2, [["brand", 1.7]], [["imp", 16, "", 0.95, 1.3, 0], ["hellhound", 10, "", 0.95, 1.2, 0]]],
}


func _boss() -> void:
	_cam_default = "k"
	var which := _s("boss", "king")
	var b: Array = BOSSES.get(which, BOSSES["king"])
	var hero := _s("hero", "drifter")
	if not await _launch(hero, int(b[1]), _i("seed", 88)):
		return
	_hud(false)
	_numbers(_b("numbers", true))
	_arm(hero)
	_mirror = _b("mirror", false)
	var sp := _spot(_f("angle", 45.0), _f("radius", 30.0))
	var at: Vector3 = sp["at"]
	var look: Vector3 = sp["fwd"]
	var face := _f("face", 66.0)
	var fwd: Vector3 = look.rotated(Vector3.UP, deg_to_rad(-face if _mirror else face))
	_place_hero(at, fwd)
	var frames := _hframings()
	_frame_h(at, look, frames[0])
	_hero_view(float(g.camera.yaw))
	_clear_props(at, fwd, -18.0, 18.0, -8.0, 36.0)
	_hide_structures(at + fwd * 10.0, 40.0)
	if _b("props", true):
		_set_props(HELL_PROPS if which.begins_with("brander") else (NIGHT_PROPS if which == "gila" else SWARM_PROPS_SIDE))
	await _wait(0.3)
	var em = g.enemies
	# the boss big under its point of the picture
	var bp := _ground_ray(_mx(_f("bx", 0.34)), _f("by", 0.50))
	var bi: int = em.spawn_boss(str(b[0]), bp)
	if bi < 0:
		_log("no boss came")
		return
	em.max_hp[bi] = 1.0e7
	em.hp[bi] = 1.0e7
	_badges(_b("badges", false))
	_weapons_free(false)
	await _wait(_f("walk", 0.6))
	# its attacks, now: the runner's next pick set to each in turn, its clock run out; the crowd comes in for the last
	# `crowd_walk` seconds only (a hellhound covers 10 m in the Brander's two seconds and buried the hero)
	var def = _reg.enemy(str(b[0]))
	var attacks: Array = em.custom_resolved(def, def.boss.get("attacks", []))
	var seq: Array = b[2]
	for k in range(seq.size()):
		var want := str(seq[k][0])
		var idx := 0
		for j in range(attacks.size()):
			if str((attacks[j] as Dictionary).get("name", "")) == want:
				idx = j
				break
		em.atk_i[bi] = idx
		em.atk_t[bi] = 0.0
		em.hold_t[bi] = 0.0
		em.state[bi] = int(_C.get("STATE_MOVE", 0))
		_log("boss %s attack %s (#%d of %d)" % [str(b[0]), want, idx, attacks.size()])
		var secs := float(seq[k][1])
		if k < seq.size() - 1:
			await _wait(secs)
			continue
		secs = _f("freeze", secs)
		var cw := minf(_f("crowd_walk", 0.7), secs)
		await _wait(maxf(secs - cw, 0.02))
		_boss_crowd(b[3], bp)
		await _wait(maxf(cw - _f("flight", 0.16), 0.02))
		if _b("fire", true):
			if g.get("damage_numbers") and g.damage_numbers:
				g.damage_numbers.clear()
			_fire_all()
		await _wait(_f("flight", 0.16))
	_freeze()
	_calm()
	_log_marks()
	for f in range(frames.size()):
		_frame_h(at, look, frames[f])
		await _shot("boss_%s_%s_%s" % [which, hero, str(frames[f].get("name", str(f)))])
	if _b("clean", true):
		_numbers(false)
		_frame_h(at, look, frames[0])
		await _shot("boss_%s_%s_%s_nonum" % [which, hero, str(frames[0].get("name", "0"))])


## A boss's crowd ([id, count, look, scale min, scale max, specials]) under the picture's far side from the hero, clear of
## the boss and of the hero, no knockback (a hit creature would turn).
func _boss_crowd(cast: Array, bp: Vector3) -> void:
	var em = g.enemies
	var cam: Camera3D = g.camera.camera
	var feet_y: float = cam.unproject_position(g.player.global_position).y / root.get_visible_rect().size.y
	var total := 0
	for c in cast:
		total += int(c[1])
	var spots := _screen_spots(total + 12, _mx(_f("x0", 0.10)), _mx(_f("x1", 0.64)), _f("y0", 0.32), _f("y1", feet_y + _f("below", -0.02)), _f("gap", 1.3), 2.0, 1.0, 1.0, _f("keep_off", 4.5))
	var keep: Array = []
	for p in spots:
		if Vector2((p as Vector3).x - bp.x, (p as Vector3).z - bp.z).length() > _f("boss_clear", 4.2):
			keep.append(p)
	_shuffle(keep)
	var deal: Array = []
	for c in cast:
		for j in range(int(c[1])):
			deal.append(c)
	_shuffle(deal)
	for k in range(mini(keep.size(), deal.size())):
		var c: Array = deal[k]
		_spawn(str(c[0]), keep[k], _rng.randf_range(float(c[3]), float(c[4])), str(c[2]))
	for t in range(em.types.size()):
		em._t_kbt[t] = 0.0
	_badges(_b("badges", false))
	em._rebuild_grid()
	_log("boss crowd %d at %s" % [mini(keep.size(), deal.size()), str(bp)])


# ---------------------------------------------------------------- the horde (the gameplay camera, a late build)

const HORDE_BUILD := ["golden_revolver", "chicago_typewriter", "saw_halo", "loudmouth", "roman_candle"]
const HORDE_MIX := [["skeleton", 5], ["skeleton_knight", 3], ["werewolf", 2], ["dust_mummy", 2], ["fire_ant", 4], ["lesser_scorpion", 4],
	["red_goblin", 3], ["bull_beetle", 1], ["spit_cactus", 1], ["buckshot_dwarf", 1], ["cactus_walker", 2], ["blue_slime", 1]]


func _horde() -> void:
	var hero := _s("hero", "drifter")
	if not await _launch(hero, _i("stage", 0), _i("seed", 88)):
		return
	_run.debug_clear_items()
	for id in _s("build", ",".join(HORDE_BUILD)).split(","):
		_run.debug_set_item("weapon", id, 99)
	A["passives"] = _s("passives", "multishot:4,haste:4,deadeye:3,lodestone:3,thirst:2,quickdraw:5,overkill:4,reach:3")
	A["level"] = _s("level", "38")
	A["clock"] = _s("clock", "388")
	A["gold"] = _s("gold", "2140")
	A["xp"] = _s("xp", "0.4")
	_hud_build()
	_numbers(true)
	_hud(true)
	var sp := _spot(_f("angle", 200.0), _f("radius", 14.0), true)
	var at: Vector3 = sp["at"]
	_place_hero(at, Vector3(0, 0, -1))
	_clear_props(at, Vector3(0, 0, -1), -9.0, 9.0, -14.0, 16.0)
	_hide_structures(at, 30.0)
	g.camera.snap_to(g.player)
	await _wait(0.3)
	var pool: Array = []
	for m in HORDE_MIX:
		for k in range(int(m[1])):
			pool.append(str(m[0]))
	var n := _i("count", 270)
	var made := 0
	var tries := 0
	while made < n and tries < n * 20:
		tries += 1
		# all round him, out to `r1` m up the screen (the camera sees far up it) and `r1s` m down it, a clearing of `r0` m
		# round him (his weapons keep one)
		var a := _rng.randf() * TAU
		var up := sin(a) < 0.0
		var r := _rng.randf_range(_f("r0", 4.6), _f("r1", 24.0) if up else _f("r1s", 9.0))
		if up and _rng.randf() < 0.35:
			r = _rng.randf_range(_f("r0", 4.6), 12.0)
		var p: Vector3 = at + Vector3(cos(a) * r * (0.7 if not up else 0.9), 0, sin(a) * r)
		if not g.camera.on_screen(p + Vector3(0, 0.8, 0), 40.0):
			continue
		if _spawn(str(pool[_rng.randi() % pool.size()]), p, _rng.randf_range(0.9, 1.15), "", made % 70 == 5, _f("hp", 20.0), 0.0) >= 0:
			made += 1
	_log("horde: %d creatures" % made)
	g.enemies._rebuild_grid()
	# the gems of the minutes before lying on the sand round him (the late game's ground)
	var pk = g.pickups
	var pc: Dictionary = pk.get_script().get_script_constant_map()
	for k in range(_i("gems", 70)):
		var ga := _rng.randf() * TAU
		var gr := _rng.randf_range(4.0, 13.0)
		var kind: int = int(pc.get("KIND_GEM_M", 1)) if k % 6 == 0 else int(pc.get("KIND_GEM_S", 0))
		pk.spawn(kind, _at(at + Vector3(cos(ga) * gr * 0.8, 0, sin(ga) * gr)), 1.0)
	await _wait(maxf(_f("freeze", 0.8) - 0.3, 0.05))
	# the thumb on the stick for the last moment, a nudge (he hardly moves); the numbers of that moment only (a late
	# build's whole second of numbers is a wall of digits)
	var inp = g.player.input
	var vs: Vector2 = root.get_visible_rect().size
	inp.origin = Vector2(vs.x * 0.55, vs.y * 0.80)
	inp.touch_pos = inp.origin + Vector2(vs.x * 0.03, -vs.x * 0.04)
	inp.wants_move = true
	if g.get("damage_numbers") and g.damage_numbers:
		g.damage_numbers.clear()
	await _wait(_f("last", 0.3))
	_freeze()
	_calm()
	await _shot("horde_%s_hud" % hero)
	# the same moment with the damage numbers switched off (the game's own Settings switch), then without the HUD too
	_numbers(false)
	await _shot("horde_%s_hud_nonum" % hero)
	_hud(false)
	await _shot("horde_%s_clean" % hero)


# ---------------------------------------------------------------- the bestiary

func _bestiary_ids() -> Array:
	var ids: Array = []
	var f := FileAccess.open("res://content/maps/red_canyon/red_canyon.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	var td: Dictionary = d.get("timeline_data", {})
	var want := func(x) -> void:
		if x is String and x != "" and x != "roster" and not ids.has(x):
			ids.append(x)
	for r in td.get("roster", []):
		want.call(r.get("enemy"))
		for w in r.get("enemy_weights", []):
			if w is Array and not (w as Array).is_empty():
				want.call(w[0])
			elif w is Dictionary:
				want.call((w as Dictionary).get("enemy", ""))
	for e in td.get("events", []):
		var en = e.get("enemy")
		if en is Array:
			for x in en:
				want.call(x)
		else:
			want.call(en)
	for p in td.get("specials", {}).get("pool", []):
		want.call(p.get("enemy"))
	# the bosses' summons
	for bid in ["tumbleweed_king", "gila_grande", "brander"]:
		var bd = _reg.enemy(bid)
		if bd != null:
			for atk in bd.boss.get("attacks", []):
				if str(atk.get("name", "")) == "spawn_ring":
					want.call(str(atk.get("enemy", "")))
	var out: Array = []
	for id in ids:
		var def = _reg.enemy(id)
		if def == null:
			continue
		if bool(def.get("hidden")) or bool(def.get("retired")) or str(def.brain) == "dummy":
			_log("bestiary: left out %s (hidden, retired or a dummy)" % id)
			continue
		out.append(def)
	return out


func _bestiary() -> void:
	var hero := _s("hero", "drifter")
	if not await _launch(hero, 0, _i("seed", 88)):
		return
	_hud(false)
	_numbers(false)
	_run.debug_clear_items()
	# no weapons: the companion gun would float on at the start spot (its host held, it never follows him)
	g.weapon_host.process_mode = Node.PROCESS_MODE_DISABLED
	g.weapon_host.visible = false
	# the hero's landing at the start leaves a second of dust behind him (the Drifter's Trail Dust, a pale disc): let it go
	await _wait(1.4)
	var defs := _bestiary_ids()
	# two tiers by size, each in size order (an orthographic camera draws both at one scale): in front everything up to
	# `split` m with the hero among them at his size, behind the big ones and the three bosses last
	var split := _f("split", 2.6)
	var front: Array = []
	var back: Array = []
	for d in defs:
		if str(d.archetype) == "boss" or float(d.size) >= split:
			back.append(d)
		else:
			front.append(d)
	front.append(null)
	var size_of := func(d) -> float: return HERO_H if d == null else float(d.size)
	var boss_key := func(d) -> float: return (100.0 if d != null and str(d.archetype) == "boss" else 0.0) + size_of.call(d)
	front.sort_custom(func(a, b) -> bool: return size_of.call(a) < size_of.call(b))
	back.sort_custom(func(a, b) -> bool: return boss_key.call(a) < boss_key.call(b))
	_log("bestiary: front %s" % str(front.map(func(q): return "hero" if q == null else q.id)))
	_log("bestiary: back %s" % str(back.map(func(q): return q.id)))
	var c0: Vector3 = _at(Vector3(_f("cx", 0.0), 0, _f("cz", 8.0)))
	_clear_props(c0, Vector3(0, 0, -1), -50.0, 50.0, -34.0, 80.0)
	_hide_structures(c0, 90.0)
	var gap := _f("gap", 0.22)
	var wf := _f("wfrac", 0.6)
	var tiers := [front, back]
	var xs := [[], []]
	var spans := [0.0, 0.0]
	for t in range(2):
		var run_x := 0.0
		var row: Array = tiers[t]
		for j in range(row.size()):
			var w: float = (HERO_H * 0.42) if row[j] == null else float(row[j].size) * wf
			if j > 0:
				var pw: float = (HERO_H * 0.42) if row[j - 1] == null else float(row[j - 1].size) * wf
				run_x += pw * 0.5 + w * 0.5 + gap
			(xs[t] as Array).append(run_x)
		spans[t] = run_x
	var depth := _f("depth", 9.0)
	# the camera first (the billboards' up and the hero's view read it), then everyone placed with the world frozen, so
	# no brain turns anyone towards the hero: every creature stands in its front view, idle, as it spawned
	_freeze()
	var vs: Vector2 = root.get_visible_rect().size
	var cam: Camera3D = g.camera.camera
	g.camera.set_process(false)
	var pitch := deg_to_rad(_f("pitch", 14.0))
	var dir := Vector3(0, -sin(pitch), -cos(pitch))
	var ortho_w: float = maxf(float(spans[0]), float(spans[1])) + 2.0 * _f("margin", 1.0)
	var ortho_h := ortho_w * vs.y / maxf(vs.x, 1.0)
	# the front row's feet `foot` m over the frame's foot: the frame's middle that much plus half its height up the
	# billboards' plane from them
	var up := Vector3(0, cos(pitch), -sin(pitch))
	var mid: Vector3 = c0 + up * (ortho_h * 0.5 - _f("foot", 0.8))
	g.camera.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), mid - dir * _f("back_m", 26.0))
	g.camera.yaw = 0.0
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = ortho_w
	cam.near = 0.5
	cam.far = 300.0
	var em = g.enemies
	# none of them rolls its variance special (x1.5 and a glowing rim: not its played look, not to scale) nor a palette
	# tint (colour waits for kills that never come)
	em.force_plain = true
	em.colour_after_kills = 1 << 30
	for t in range(2):
		var row: Array = tiers[t]
		for j in range(row.size()):
			var p := c0 + Vector3(float(xs[t][j]) - float(spans[t]) * 0.5, 0, -depth * float(t))
			if row[j] == null:
				_place_hero(_at(p), Vector3(0, 0, 1))
				g.player.set("_view", "_f")
				g.player.set("_flip", false)
				if g.player.sprite.has_animation("idle_f"):
					g.player.sprite.play("idle_f")
				continue
			var i: int
			if str(row[j].archetype) == "boss":
				i = em.spawn_boss(str(row[j].id), _at(p))
			else:
				i = _spawn(str(row[j].id), p, 1.0, "", false, 400.0, 999.0)
			if i >= 0:
				# its own size, no spawn jitter, standing at its full height (a spawn starts squashed and grows on its first
				# ticks, which never come here): to scale
				em.size[i] = float(row[j].size)
				em.squash[i] = 1.0
				em.speed[i] = 0.0
				em.vel[i] = Vector3.ZERO
	em.force_plain = false
	_badges(false)
	# no bounty's warm pulse on one of them (a run's marked creature; the lineup shows them as they are)
	em.bounty_i = -1
	em._render()
	if _b("probe", false):
		# what stands near the run's start (a tool's diagnosis)
		var start: Vector3 = g.map.player_start()
		for n in g.find_children("*", "GeometryInstance3D", true, false):
			var gi := n as GeometryInstance3D
			if gi.is_visible_in_tree() and Vector2(gi.global_position.x - start.x, gi.global_position.z - start.z).length() < 3.0:
				_log("near the start: %s (%s) at %s" % [str(gi.get_path()), gi.get_class(), str(gi.global_position)])
	_log("bestiary: spans %.1f / %.1f m, ortho %.1f x %.1f m" % [float(spans[0]), float(spans[1]), ortho_w, ortho_h])
	await _shot("bestiary")


# ---------------------------------------------------------------- the in-run screens, landed

## Waits (real seconds, at most `max_s`) until `cond` holds; false when it never did.
func _until(cond: Callable, max_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not bool(cond.call()):
		if float(Time.get_ticks_msec() - t0) / 1000.0 > max_s:
			return false
		await process_frame
	return true


## The screen up closed through its own path and the run handed back (the first card, the first gift).
func _close_screens() -> void:
	if g.cards and g.cards.visible and not g.cards._offer.is_empty():
		g.cards._pick(g.cards._offer[0])
	if g.get("totem_screen") and g.totem_screen and g.totem_screen.visible and not g.totem_screen.offer().is_empty():
		g.totem_screen._finish(g.totem_screen.offer()[0])
	await _wait(0.6)
	if g.resume_gate and g.resume_gate.visible:
		g.resume_gate.tap()
	g.set_paused(false)
	await _wait(0.4)


func _ui() -> void:
	var hero := _s("hero", "drifter")
	if not await _launch(hero, 0, _i("seed", 88)):
		return
	A["weapons"] = _s("weapons", "revolver:4,tommy_gun:3,lob_grenade:3")
	_arm(hero)
	_hud_build()
	_numbers(false)
	var sp := _spot(_f("angle", 45.0), _f("radius", 24.0), true)
	_place_hero(sp["at"], Vector3(0, 0, -1))
	_hide_structures(sp["at"], 30.0)
	g.camera.snap_to(g.player)
	# a few scorpions round him, under the screens' dimmed backdrop
	for k in range(14):
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(4.0, 9.0)
		_spawn("lesser_scorpion", sp["at"] + Vector3(cos(a) * r * 0.7, 0, sin(a) * r), _rng.randf_range(0.9, 1.3), "LS-B" if k % 3 else "LS-E")
	g.weapon_host.process_mode = Node.PROCESS_MODE_DISABLED
	await _wait(0.6)
	# the level-up cards, every card landed
	_run.add_xp(_run.xp_to_next() + 1.0)
	if await _until(func() -> bool: return g.cards.visible and not g.cards._offer.is_empty(), 4.0):
		await _wait(_f("settle", 2.2))
		await _shot("ui_levelup")
	await _close_screens()
	# the mutation offer: its weapon reel run out, the three paths landed
	g.present_path_offer()
	if await _until(func() -> bool: return g.cards.visible, 4.0):
		await _wait(0.3)
		if g.cards.reel_running():
			g.cards.skip_reel()
		await _wait(_f("settle", 2.2))
		await _shot("ui_mutation")
	else:
		_log("ui: no mutation offer came (no path open)")
	await _close_screens()
	# the Spirit Pole's gifts
	var tp = _reg.structure("totem_pole")
	if tp != null:
		g.use_structure(tp, g.player.global_position)
		if await _until(func() -> bool: return g.get("totem_screen") != null and g.totem_screen.visible, 4.0):
			await _wait(_f("settle", 2.2))
			await _shot("ui_totem")
		else:
			_log("ui: the totem screen never came up")
