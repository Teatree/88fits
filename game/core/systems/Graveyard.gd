## Pass 119 (lane LEGEND_B): the Undertaker's Shovel, a legendary passive item (docs/legendary_items: "One kill in 25
## leaves a grave. Two seconds later a ghost gunslinger climbs out ..."; Garry: "This is cool, let's make it as you
## described. The tombstones should spawn and despawn with an animation, not just pop in an out"). Reworked in pass 120
## (lane GHOST; Garry: "Currently the ghost rises and stands there looking rather weird. Let's make him run in a circle
## around the grave ... instead of the ghost being Player's hero let's make it an actual floating ghost. It still 'runs'
## around instead of standing still, but it's the same visual for every hero. It's a 2 sided sprite and it's mostly staying
## still ... attacks ... should be kind of ghostly projectiles like ones in Warcraft 3 ziggurat attack ... The count of
## those projectiles as well as the damage scale with hero power ... Cap is 6 projectiles at the same time ... The attacks
## carry no knockback to the enemies"). Game makes this node the first time a kill is made while the hero's `grave_every`
## is above 0 and feeds it every kill (note_kill) and every frame (tick, from Game._tick_perks: the rule frames' delta,
## Lockstep.dt).
##
## The rules (no dice: a count, the nearest targets, timers on the run's frames, so a replay digs the same graves and flies
## the same bolts):
## - every `grave_every`-th kill made while it is held digs a grave where the body fell; while `grave_max` graves stand
##   (rising, waiting, haunted or sinking) a grave that falls due is not dug and the count starts again; a body in the
##   water digs none.
## - the grave (its painting, params.grave.sprite, `height` m) rises out of the sand in `stone_up` s with a ring of dust;
##   `rise` s after the dig a ghost climbs out of it in `climb` s, fading in, in front of the grave (towards the camera);
## - the ghost then circles its grave for `grave_seconds` s: `circle_radius` m round it (reached over its first `spiral`
##   s), one lap every `lap_seconds` s, `hover` m over the sand, the way round alternating grave by grave (the first
##   anticlockwise seen from above); while it circles it fires a VOLLEY every `volley_every` s (the first `first_volley`
##   s after it is out): bolt_count(power) ghost bolts (GhostBolts) at the bolt_count nearest distinct creatures within
##   `range` m of it, each for bolt_damage(power); with fewer creatures than bolts, the rest go round the same creatures
##   again, launched fanned out (`fan` degrees more each round) so they still leave in different directions and curve in;
##   none near: it waits RETRY s and looks again.
##     bolt_count(p) = clamp(round(bolts_mult x p ^ bolts_exp), 1, bolts_max)      (1 below power 2, 6 from 17.2)
##     bolt_damage(p) = damage x p ^ damage_exp x max(1, bolts_mult x p ^ bolts_exp / bolts_max)
##   p is the hero's power (HeroPower.measure of his weapons and sheet now: 1.0 = a fresh level-1 Drifter); past the cap
##   the bolts it holds back are paid as damage on the six. No stage multiplier (the power is the hero's own measure).
##   Every bolt: no knockback, never a crit, the item's own source (`source_id`): the Results screen, the run record and
##   the damage numbers name it, and its kills count for it.
## - then the ghost drifts up as it keeps circling and fades away in `vanish` s and the grave sinks back into the sand in
##   `stone_down` s with dust.
## The look: one painted floating ghost for every hero (params.grave `ghost_front` / `ghost_back`, `ghost_height` m),
## tinted towards `ghost_tint` by `ghost_mix`, see-through at `ghost_alpha`. It shows its front while it moves across or
## towards the camera and its back while it moves away (a paper turn between them: it narrows to an edge and opens on
## the other side in TURN s, the switch held off by FACE_HYST so it never flickers), bobs and sways, leans into its motion
## (LEAN rad at full sideways speed), and squashes and glows for a blink when it fires. Numbers: BALANCING.md 62.GHOST.
class_name Graveyard
extends Node3D

const DEFAULTS := {"rise": 2.0, "stone_up": 0.45, "stone_down": 0.6, "climb": 0.7, "vanish": 0.6, "height": 1.25,
	"sprite": "undertakers_shovel_grave.png", "ghost_front": "undertakers_shovel_ghost_front.png",
	"ghost_back": "undertakers_shovel_ghost_back.png", "ghost_height": 1.55, "ghost_tint": "#7fe6ff", "ghost_mix": 0.45,
	"ghost_alpha": 0.85, "hover": 0.35, "circle_radius": 1.5, "lap_seconds": 4.0, "spiral": 0.8, "volley_every": 1.0,
	"first_volley": 0.35, "range": 9.0, "bolts_mult": 1.0, "bolts_exp": 0.6, "bolts_max": 6.0, "damage": 3.2,
	"damage_exp": 0.9, "bolt_speed": 8.0, "bolt_turn": 5.0, "bolt_life": 2.4, "bolt_size": 0.55, "curve": 14.0,
	"fan": 32.0, "lift": 0.35, "bolt_core": "#f2fdff", "bolt_color": "#7fe0ff", "bolt_rim": "#6a4ccc",
	"sound": "it_ghost_volley"}
## The id the bolts are recorded under when no held item carries params.grave (a test or a tool setting the stats).
const SOURCE_DEFAULT := "undertakers_shovel"
## The ghost climbs out this far from its grave's middle (m), towards the camera (+Z), and widens to its circle from there.
const CLIMB_R := 0.35
## Seconds before a ghost with no creature in range looks again.
const RETRY := 0.15
## A bolt leaves the ghost this high over its own foot, in ghost heights (its chest).
const CHEST := 0.55
## Its colour: the painting's lightness redrawn towards params.grave.ghost_tint (BillboardSprite.set_ghost), washed this
## far towards white.
const GHOST_WASH := 0.06
## A ghost bobs this much (m) at this pace, sways (rad) at that pace, and leans this far into its motion.
const BOB := 0.08
const BOB_HZ := 0.9
const SWAY := 0.05
const SWAY_HZ := 0.55
const LEAN := 0.16
## The paper turn between its front and its back (s), and how far past moving sideways it must be heading (the dot of
## its way with the camera's back, -1..1) before it turns, so a ghost moving across never flickers between the two.
const TURN := 0.26
const FACE_HYST := 0.22
## A volley's squash and glow (s).
const FIRE_KICK := 0.16
## The bolts' sound: at most one every SOUND_GAP s across all the ghosts.
const SOUND_GAP := 0.3

enum { STONE_UP, WAIT, CLIMB, FIGHT, VANISH, STONE_DOWN }

var game: Node = null
## Kills counted towards the next grave.
var counted := 0
## The graves standing: {"pos", "phase", "t", "age", "stone", "ghost", "fire_t", "life", "kick", "theta", "rad", "spin",
## "face", "turn", "turn_to"}.
var graves: Array = []
## Tests and the capture: graves dug, ghosts raised, volleys and bolts sent, graves that fell due while the cap stood.
var dug := 0
var raised := 0
var volleys := 0
var shots := 0
var skipped := 0
## The bolts in flight (GhostBolts), made with the node.
var bolts: GhostBolts = GhostBolts.new()
## Tests and the capture: a power to fire with instead of the hero's (below 0: his).
var power_override := -1.0
var _grave_tex: Texture2D = null
var _ghost_tex: Array = [null, null]
var _sound_t := 0.0
var _clock := 0.0


func setup(p_game: Node) -> void:
	game = p_game
	top_level = true
	bolts.source = source_id()
	var em = game.get("enemies") if game else null
	bolts.enemies = em as EnemyManager


## Whether the hero holds a grave-digging item now.
static func active() -> bool:
	return Run.player_sheet != null and Run.player_sheet.get_stat("grave_every", 0.0) > 0.0


func _stat(stat: String, fallback: float) -> float:
	return Run.player_sheet.get_stat(stat, fallback) if Run.player_sheet else fallback


## The most graves standing at once.
func cap() -> int:
	return maxi(int(round(_stat("grave_max", 4.0))), 1)


## The held item's params.grave ({} without one) and a number of it, else DEFAULTS'. A frame's tick reads them once
## (_frame_params) rather than at every number.
var _frame_params = null


func params() -> Dictionary:
	if _frame_params is Dictionary:
		return _frame_params
	var src: Array = Run.item_params("grave")
	return src[1] if not src.is_empty() else {}


func num(key: String) -> float:
	return float(params().get(key, DEFAULTS[key]))


func _str(key: String) -> String:
	return str(params().get(key, DEFAULTS[key]))


## The id the bolts are recorded under: the held item's.
func source_id() -> String:
	var src: Array = Run.item_params("grave")
	return str(src[0]) if not src.is_empty() else SOURCE_DEFAULT


# ---------------------------------------------------------------- the power

## The hero's power now (HeroPower.measure of the run's weapons and sheet, worked out here rather than read from its
## per-frame cache, so two rule frames in one drawn frame read the build each has), or power_override.
func power() -> float:
	if power_override >= 0.0:
		return power_override
	if Run.player_sheet == null:
		return 1.0
	return float(HeroPower.measure(Run.weapons, Run.player_sheet)["power"])


## The bolts a volley sends at power `p`, before the cap.
func bolts_raw(p: float) -> float:
	return maxf(num("bolts_mult"), 0.0) * pow(maxf(p, 0.0), num("bolts_exp"))


## The bolts a volley sends at power `p`: clamp(round(bolts_mult x p ^ bolts_exp), 1, bolts_max).
func bolt_count(p: float) -> int:
	return clampi(int(round(bolts_raw(p))), 1, maxi(int(round(num("bolts_max"))), 1))


## One bolt's damage at power `p`: damage x p ^ damage_exp, x the share of bolts the cap holds back past it.
func bolt_damage(p: float) -> float:
	var capn := maxf(round(num("bolts_max")), 1.0)
	return maxf(num("damage"), 0.0) * pow(maxf(p, 0.0), num("damage_exp")) * maxf(1.0, bolts_raw(p) / capn)


# ---------------------------------------------------------------- the graves

## A kill (Game._kill_effects): the count, and a grave where the body fell when it falls due.
func note_kill(at: Vector3) -> void:
	var every := int(round(_stat("grave_every", 0.0)))
	if every <= 0:
		return
	counted += 1
	if counted < every:
		return
	counted = 0
	if graves.size() >= cap():
		skipped += 1
		return
	dig(at)


func _ground(p: Vector3) -> Vector3:
	var m = game.get("map") if game else null
	if m != null and m.has_method("height_at"):
		return Vector3(p.x, m.height_at(p.x, p.z), p.z)
	return p


## A grave at `at` now (note_kill's, the arena's and the tests'): false in the water or past the cap.
func dig(at: Vector3) -> bool:
	if graves.size() >= cap():
		return false
	var m = game.get("map") if game else null
	if m != null and m.has_method("in_water") and m.in_water(at):
		skipped += 1
		return false
	# the way round alternates grave by grave (the first anticlockwise seen from above: +X towards -Z)
	var g := {"pos": _ground(at), "phase": STONE_UP, "t": 0.0, "age": 0.0, "stone": null, "ghost": null, "fire_t": 0.0,
		"life": maxf(_stat("grave_seconds", 8.0), 0.5), "kick": 0.0, "theta": PI * 0.5, "rad": CLIMB_R,
		"spin": -1.0 if dug % 2 == 0 else 1.0, "face": 1, "turn": -1.0, "turn_to": 1}
	if not Run.sim_mode:
		g["stone"] = _make_stone(g["pos"])
		_dust(g["pos"], 1.0)
	graves.append(g)
	dug += 1
	return true


## Every frame (Game._tick_perks): each grave through its phases, each ghost's volleys, the bolts in flight.
func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	_clock += delta
	_sound_t = maxf(_sound_t - delta, 0.0)
	if not graves.is_empty():
		_frame_params = null
		_frame_params = params()
		var keep: Array = []
		for g: Dictionary in graves:
			if _tick_grave(g, delta):
				keep.append(g)
			else:
				_free_grave(g)
		graves = keep
		_frame_params = null
	if bolts.count > 0 or bolts.drawn() > 0:
		bolts.tick(delta)


## One grave's frame; false once it has sunk away.
func _tick_grave(g: Dictionary, delta: float) -> bool:
	g["t"] = float(g["t"]) + delta
	g["age"] = float(g["age"]) + delta
	var t: float = g["t"]
	match int(g["phase"]):
		STONE_UP:
			var k := clampf(t / maxf(num("stone_up"), 0.01), 0.0, 1.0)
			_place_stone(g, _ease_back(k))
			if k >= 1.0:
				_next(g, WAIT)
		WAIT:
			if float(g["age"]) >= num("rise"):
				_next(g, CLIMB)
				g["ghost"] = _make_ghost()
				raised += 1
				_dust(ghost_spot(g), 0.7)
				_place_ghost(g, 0.0, 0.0, delta)
		CLIMB:
			var k := clampf(t / maxf(num("climb"), 0.01), 0.0, 1.0)
			_place_ghost(g, k, minf(k * 1.6, 1.0), delta)
			if k >= 1.0:
				_next(g, FIGHT)
				g["fire_t"] = num("first_volley")
		FIGHT:
			_circle(g, delta, t)
			_place_ghost(g, 1.0, 1.0, delta)
			_fight(g, delta)
			if t >= float(g["life"]):
				_next(g, VANISH)
		VANISH:
			_circle(g, delta, -1.0)
			var k := clampf(t / maxf(num("vanish"), 0.01), 0.0, 1.0)
			_place_ghost(g, 1.0 + k * 0.35, 1.0 - k, delta)
			if k >= 1.0:
				_free_ghost(g)
				_next(g, STONE_DOWN)
				_dust(g["pos"], 0.8)
		STONE_DOWN:
			var k := clampf(t / maxf(num("stone_down"), 0.01), 0.0, 1.0)
			_place_stone(g, 1.0 - k * k)
			if k >= 1.0:
				return false
	return true


func _next(g: Dictionary, phase: int) -> void:
	g["phase"] = phase
	g["t"] = 0.0


# ---------------------------------------------------------------- the circling

## The way round its grave a frame: the angle on at one lap every `lap_seconds`, the circle widening from CLIMB_R to
## `circle_radius` over the fight's first `spiral` s (`t` the fight's seconds; below 0 it keeps its radius).
func _circle(g: Dictionary, delta: float, t: float) -> void:
	var omega := TAU / maxf(num("lap_seconds"), 0.5)
	g["theta"] = fmod(float(g["theta"]) + float(g["spin"]) * omega * delta, TAU)
	if t >= 0.0:
		var k := clampf(t / maxf(num("spiral"), 0.01), 0.0, 1.0)
		g["rad"] = lerpf(CLIMB_R, num("circle_radius"), k * k * (3.0 - 2.0 * k))


## Where the ghost is over the sand now (its foot, without its hover or bob): on its circle round the grave.
func ghost_spot(g: Dictionary) -> Vector3:
	var th: float = g["theta"]
	var r: float = g["rad"]
	return _ground((g["pos"] as Vector3) + Vector3(cos(th), 0.0, sin(th)) * r)


## Its way along the circle (flat, unit length).
static func circle_way(g: Dictionary) -> Vector3:
	var th: float = g["theta"]
	return Vector3(-sin(th), 0.0, cos(th)) * float(g["spin"])


# ---------------------------------------------------------------- the volleys

func _fight(g: Dictionary, delta: float) -> void:
	g["kick"] = maxf(float(g["kick"]) - delta, 0.0)
	g["fire_t"] = float(g["fire_t"]) - delta
	if float(g["fire_t"]) > 0.0:
		return
	var em: EnemyManager = bolts.enemies
	if em == null:
		g["fire_t"] = 0.3
		return
	var spot := ghost_spot(g)
	var p := power()
	var n := bolt_count(p)
	var targets := nearest_targets(spot, num("range"), n)
	if targets.is_empty():
		g["fire_t"] = RETRY
		return
	g["fire_t"] = maxf(num("volley_every"), 0.1)
	_volley(g, spot, targets, n, bolt_damage(p))


## The `n` nearest distinct creatures within `reach` m of `at` on the flat that a bolt may take (alive, up out of the
## sand, not buried or held), nearest first (ties to the lower slot).
func nearest_targets(at: Vector3, reach: float, n: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var em: EnemyManager = bolts.enemies
	if em == null or n <= 0:
		return out
	var ds := PackedFloat32Array()
	var r2 := reach * reach
	for i in em.indices_in_radius(at, reach):
		if not bolts._valid(i):
			continue
		var dx := em.pos[i].x - at.x
		var dz := em.pos[i].z - at.z
		var d := dx * dx + dz * dz
		if d > r2:
			continue
		# insert in order, keeping the n nearest
		var k := ds.size()
		while k > 0 and (ds[k - 1] > d or (ds[k - 1] == d and out[k - 1] > i)):
			k -= 1
		if k >= n:
			continue
		ds.insert(k, d)
		out.insert(k, i)
		if ds.size() > n:
			ds.resize(n)
			out.resize(n)
	return out


## One volley: `n` bolts from the ghost's chest at `targets` (the k-th at targets[k mod their count]), each launched
## along the flat way to its creature turned by its own angle (bolt_angle) and lifted `lift`, for `dmg`.
func _volley(g: Dictionary, spot: Vector3, targets: PackedInt32Array, n: int, dmg: float) -> void:
	var em: EnemyManager = bolts.enemies
	var from := spot + Vector3(0, num("hover") + num("ghost_height") * CHEST, 0)
	_tune_bolts()
	var nt := targets.size()
	for k in range(n):
		var t := targets[k % nt]
		var flat := em.pos[t] - from
		flat.y = 0.0
		if flat.length_squared() < 0.0001:
			flat = circle_way(g)
		var dir := flat.normalized().rotated(Vector3.UP, deg_to_rad(bolt_angle(k, nt)))
		dir.y = num("lift")
		bolts.fire(from, dir.normalized(), t, dmg)
		shots += 1
	volleys += 1
	g["kick"] = FIRE_KICK
	if Run.sim_mode:
		return
	bolts.muzzle(from, num("bolt_size") * 1.6)
	if _sound_t <= 0.0:
		_sound_t = SOUND_GAP
		var sid := _str("sound")
		if sid != "":
			Audio.play(sid, from)


## The turn (degrees, about the vertical) the k-th bolt of a volley at `nt` distinct creatures leaves with: the first
## round curves a little out to alternate sides (`curve`), each round after it fans `fan` degrees wider.
func bolt_angle(k: int, nt: int) -> float:
	var side := 1.0 if k % 2 == 0 else -1.0
	var round_k := k / maxi(nt, 1)
	return side * (num("curve") + num("fan") * float(round_k))


func _tune_bolts() -> void:
	bolts.source = source_id()
	bolts.speed = num("bolt_speed")
	bolts.turn = num("bolt_turn")
	bolts.life = num("bolt_life")
	bolts.size = num("bolt_size")
	if bolts.enemies == null:
		var em = game.get("enemies") if game else null
		bolts.enemies = em as EnemyManager


# ---------------------------------------------------------------- the look

func _grave_texture() -> Texture2D:
	if _grave_tex != null:
		return _grave_tex
	var path := _folder() + _str("sprite")
	if ResourceLoader.exists(path):
		_grave_tex = load(path) as Texture2D
	if _grave_tex == null:
		# no painting yet: a plain grey slab
		var img := Image.create(16, 24, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.55, 0.55, 0.58))
		_grave_tex = ImageTexture.create_from_image(img)
	return _grave_tex


func _folder() -> String:
	var src: Array = Run.item_params("grave")
	return "res://content/passives/%s/" % (str(src[0]) if not src.is_empty() else SOURCE_DEFAULT)


## The ghost's painting: 0 its front, 1 its back (the front when there is no back; a pale blob when there is neither).
func ghost_texture(side: int) -> Texture2D:
	if _ghost_tex[side] != null:
		return _ghost_tex[side]
	var path := _folder() + _str("ghost_front" if side == 0 else "ghost_back")
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null and side == 1:
		tex = ghost_texture(0)
	if tex == null:
		var img := Image.create(16, 24, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.9, 0.97, 1.0))
		tex = ImageTexture.create_from_image(img)
	_ghost_tex[side] = tex
	return tex


func _make_stone(at: Vector3) -> BillboardSprite:
	var s := BillboardSprite.new()
	s.name = "Grave"
	add_child(s)
	s.setup(_grave_texture(), {"idle": 1}, ["idle"], num("height"))
	s.global_position = at - Vector3(0, num("height"), 0)
	return s


## The grave `k` of the way up (0 under the sand, 1 standing; past 1 a little overshoot): it pushes up out of the sand,
## the ground hiding what is still under it, a touch squashed while it is low.
func _place_stone(g: Dictionary, k: float) -> void:
	var s = g.get("stone")
	if not (s is BillboardSprite):
		return
	var h := num("height")
	(s as BillboardSprite).global_position = (g["pos"] as Vector3) - Vector3(0, h * (1.0 - k), 0)
	(s as BillboardSprite).set_squash(1.0 + 0.08 * (1.0 - clampf(k, 0.0, 1.0)), clampf(0.55 + 0.45 * k, 0.3, 1.1))


func _make_ghost() -> BillboardSprite:
	if Run.sim_mode or game == null:
		return null
	bolts.attach(self, {"core": _str("bolt_core"), "body": _str("bolt_color"), "rim": _str("bolt_rim")})
	var s := BillboardSprite.new()
	s.name = "Ghost"
	s.enable_over_trails()
	add_child(s)
	s.setup(ghost_texture(0), {"idle": 1}, ["idle"], num("ghost_height"))
	var tint := Color(_str("ghost_tint"))
	s.set_ghost(Color(tint.r, tint.g, tint.b, clampf(num("ghost_mix"), 0.0, 1.0)))
	s.set_flash(GHOST_WASH)
	s.set_fade(0.0)
	return s


## The side a ghost wants to show now: 1 its front, -1 its back. `toward` is the dot of its way with the camera's back
## (1 straight at the camera); it keeps the side it shows until its way is FACE_HYST past sideways.
static func want_face(face: int, toward: float) -> int:
	if face >= 0 and toward < -FACE_HYST:
		return -1
	if face < 0 and toward > FACE_HYST:
		return 1
	return 1 if face >= 0 else -1


## The camera's back and right on the flat (+Z and +X without a camera: the game's).
func _cam_flat() -> Array:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() and get_viewport() else null
	if cam == null:
		return [Vector3(0, 0, 1), Vector3(1, 0, 0)]
	var b := cam.global_transform.basis
	var back := Vector3(b.z.x, 0, b.z.z)
	var right := Vector3(b.x.x, 0, b.x.z)
	return [back.normalized() if back.length_squared() > 0.0001 else Vector3(0, 0, 1),
		right.normalized() if right.length_squared() > 0.0001 else Vector3(1, 0, 0)]


## The ghost `up` of the way out of the grave (0 under the sand, 1 floating, past 1 drifting up and away) at `alpha` of
## its see-through; its side, its paper turn, its lean, bob and sway, its kick when it fires. A look only.
func _place_ghost(g: Dictionary, up: float, alpha: float, delta: float) -> void:
	var s = g.get("ghost")
	if not (s is BillboardSprite):
		return
	var gs := s as BillboardSprite
	var hover := num("hover")
	var gh := num("ghost_height")
	var y := -gh + (gh + hover) * up if up <= 1.0 else hover + (up - 1.0) * 1.7
	var bob := sin((_clock + float(g["age"])) * TAU * BOB_HZ) * BOB if up >= 1.0 else 0.0
	gs.global_position = ghost_spot(g) + Vector3(0, y + bob, 0)
	gs.set_fade(clampf(alpha, 0.0, 1.0) * num("ghost_alpha"))
	# its side: the way it goes against the camera, once it circles
	var cf := _cam_flat()
	var way := circle_way(g) if int(g["phase"]) >= FIGHT else Vector3.ZERO
	var toward: float = way.dot(cf[0])
	var sideways: float = way.dot(cf[1])
	var face: int = int(g["face"])
	var turn: float = g["turn"]
	if turn < 0.0:
		var want := want_face(face, toward)
		if want != face:
			g["turn"] = 0.0
			g["turn_to"] = want
			turn = 0.0
	var sx := 1.0
	if turn >= 0.0:
		turn += delta / TURN
		if turn >= 0.5 and face != int(g["turn_to"]):
			face = int(g["turn_to"])
			g["face"] = face
			gs.set_texture(ghost_texture(0 if face > 0 else 1))
		if turn >= 1.0:
			turn = -1.0
		else:
			sx = maxf(absf(cos(PI * turn)), 0.06)
		g["turn"] = turn
	var kick := clampf(float(g.get("kick", 0.0)) / FIRE_KICK, 0.0, 1.0)
	gs.set_squash(sx * (1.0 + 0.12 * kick), 1.0 - 0.09 * kick)
	gs.set_flash(GHOST_WASH + 0.4 * kick)
	var sway := sin((_clock + float(g["age"]) * 0.37) * TAU * SWAY_HZ) * SWAY
	gs.set_roll(-sideways * LEAN + sway)


## Sand thrown as a grave comes up or goes down, or a ghost climbs out.
func _dust(at: Vector3, size: float) -> void:
	if Run.sim_mode or game == null:
		return
	var fx = game.get("fx")
	if fx == null:
		return
	if fx.has_method("dig_ring"):
		fx.dig_ring(at, size)
	elif fx.has_method("emerge_dust"):
		fx.emerge_dust(at, size, true)


func _free_ghost(g: Dictionary) -> void:
	var s = g.get("ghost")
	if s is Node and is_instance_valid(s):
		(s as Node).queue_free()
	g["ghost"] = null


func _free_grave(g: Dictionary) -> void:
	_free_ghost(g)
	var s = g.get("stone")
	if s is Node and is_instance_valid(s):
		(s as Node).queue_free()
	g["stone"] = null


## Ghosts out and fighting now (tests, the capture).
func ghosts_fighting() -> int:
	var n := 0
	for g: Dictionary in graves:
		if int(g["phase"]) == FIGHT:
			n += 1
	return n


static func _ease_back(k: float) -> float:
	# out of the sand with a small overshoot, then settles
	var c := 1.6
	var q := k - 1.0
	return 1.0 + (c + 1.0) * q * q * q + c * q * q
