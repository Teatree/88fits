## Pass 119 (lane LEGEND_B): the Undertaker's Shovel, a legendary passive item (docs/legendary_items: "One kill in 25
## leaves a grave. Two seconds later a ghost gunslinger climbs out and fights where it stands for 8 s, firing your first
## weapon's shots at 40% damage. At most 4 at once. Evolved: one kill in 15, at most 6 ghosts, 12 s each"; Garry: "This
## is cool, let's make it as you described. The tombstones should spawn and despawn with an animation, not just pop in an
## out"). Game makes this node the first time a kill is made while the hero's `grave_every` is above 0 and feeds it every
## kill (note_kill) and every frame (tick, from Game._tick_perks: the rule frames' delta, Lockstep.dt).
##
## The rules (no dice: a count, the nearest target, timers on the run's frames, so a replay digs the same graves):
## - every `grave_every`-th kill made while it is held digs a grave where the body fell; while `grave_max` graves stand
##   (rising, waiting, haunted or sinking) a grave that falls due is not dug and the count starts again; a body in the
##   water digs none.
## - the grave (its painting, params.grave.sprite, `height` m) rises out of the sand in `stone_up` s with a ring of dust;
##   `rise` s after the dig a ghost climbs out of it in `climb` s, fading in;
## - the ghost stands in front of its grave for `grave_seconds` s and shoots the nearest creature within the hero's first
##   weapon's range (between range_min and range_max m): one round every cooldown / projectiles of that weapon (between
##   fire_min and fire_max s), each for `grave_damage_pct` % of its damage (might and every bonus in it), flying at its
##   projectile speed and through as many as it pierces. A gun lends its own rounds' look (its ProjectileEmitter's kind);
##   any other weapon's ghost fires pale ghost rounds. The rounds are the item's own source (its id, `source_id`): the
##   Results screen, the run record and the damage numbers name it, and its kills count for it.
## - then the ghost fades away upward in `vanish` s and the grave sinks back into the sand in `stone_down` s with dust.
## The ghost is the hero's own look (his painting and its frames), its lightness redrawn in `ghost_tint`, see-through
## at `ghost_alpha`: cheap (one billboard each, at most six) and plainly his. Numbers: BALANCING.md 61.LEGEND_B.
class_name Graveyard
extends Node3D

const DEFAULTS := {"rise": 2.0, "stone_up": 0.45, "stone_down": 0.6, "climb": 0.7, "vanish": 0.6, "height": 1.25,
	"sprite": "undertakers_shovel_grave.png", "ghost_tint": "#7fe6ff", "ghost_alpha": 0.85, "fire_min": 0.25,
	"fire_max": 1.5, "range_min": 6.0, "range_max": 12.0, "round": "#bff6ff"}
## The id the rounds are recorded under when no held item carries params.grave (a test or a tool setting the stats).
const SOURCE_DEFAULT := "undertakers_shovel"
## How a hero's strip is laid out (as Player._setup_sprite lays it), so the ghost plays his frames.
const HERO_ORDER := ["idle", "run", "turn", "hit", "die", "cheer", "idle_f", "run_f", "idle_s", "run_s", "idle_bd", "run_bd",
	"idle_fd", "run_fd", "hit_f", "hit_s", "hit_bd", "hit_fd"]
## The ghost stands beside its grave, this far to its right and towards the camera (+X, +Z), and a ghost round leaves
## this high.
const GHOST_SIDE := 0.75
const GHOST_FRONT := 0.3
## Its colour: the painting's lightness redrawn in params.grave.ghost_tint (BillboardSprite.set_ghost), washed this far
## towards white.
const GHOST_WASH := 0.08
const HAND_Y := 1.1
const GHOST_H := 1.9
## A ghost bobs this much (m) at this pace, and a shot squashes it for a blink.
const BOB := 0.06
const BOB_HZ := 1.7
## The ghost rounds' sound: at most one every SOUND_GAP s across all the ghosts.
const SOUND_GAP := 0.25
const DUST := Color(0.62, 0.52, 0.4)

enum { STONE_UP, WAIT, CLIMB, FIGHT, VANISH, STONE_DOWN }

var game: Node = null
## Kills counted towards the next grave.
var counted := 0
## The graves standing: {"pos", "phase", "t", "age", "stone", "ghost", "fire_t", "life", "shot_t"}.
var graves: Array = []
## Tests and the capture: graves dug, ghosts raised, rounds fired, graves that fell due while the cap stood.
var dug := 0
var raised := 0
var shots := 0
var skipped := 0
var _shooter: WeaponInstance = null
var _shooter_src := ""
var _round_kind := -1
var _grave_tex: Texture2D = null
var _sound_t := 0.0
var _clock := 0.0


func setup(p_game: Node) -> void:
	game = p_game
	top_level = true


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


## The id the ghosts' rounds are recorded under: the held item's.
func source_id() -> String:
	var src: Array = Run.item_params("grave")
	return str(src[0]) if not src.is_empty() else SOURCE_DEFAULT


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
	var g := {"pos": _ground(at), "phase": STONE_UP, "t": 0.0, "age": 0.0, "stone": null, "ghost": null, "fire_t": 0.0,
		"life": maxf(_stat("grave_seconds", 8.0), 0.5), "shot_t": 0.0}
	if not Run.sim_mode:
		g["stone"] = _make_stone(g["pos"])
		_dust(g["pos"], 1.0)
	graves.append(g)
	dug += 1
	return true


## Every frame (Game._tick_perks): each grave through its phases, each ghost's shots.
func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	_clock += delta
	_sound_t = maxf(_sound_t - delta, 0.0)
	if graves.is_empty():
		return
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
				_dust(g["pos"] + Vector3(GHOST_SIDE, 0, GHOST_FRONT), 0.7)
				_place_ghost(g, 0.0, 0.0)
		CLIMB:
			var k := clampf(t / maxf(num("climb"), 0.01), 0.0, 1.0)
			_place_ghost(g, k, minf(k * 1.6, 1.0))
			if k >= 1.0:
				_next(g, FIGHT)
				g["fire_t"] = 0.1
		FIGHT:
			_place_ghost(g, 1.0, 1.0)
			_fight(g, delta)
			if t >= float(g["life"]):
				_next(g, VANISH)
		VANISH:
			var k := clampf(t / maxf(num("vanish"), 0.01), 0.0, 1.0)
			_place_ghost(g, 1.0 + k * 0.35, 1.0 - k)
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


# ---------------------------------------------------------------- the shooting

## The weapon the ghosts copy: the hero's first.
func _first_weapon() -> WeaponInstance:
	return Run.weapons[0] if not Run.weapons.is_empty() else null


## Seconds between one ghost's rounds for weapon `w`: its cooldown over its projectiles, within fire_min..fire_max.
func fire_every(w: WeaponInstance) -> float:
	if w == null:
		return num("fire_max")
	var per := maxf(w.stat("cooldown", 1.0), 0.05) / float(maxi(w.stat_int("amount", 1), 1))
	return clampf(per, num("fire_min"), num("fire_max"))


## A ghost round's damage for weapon `w`: grave_damage_pct % of its damage.
func round_damage(w: WeaponInstance) -> float:
	if w == null:
		return 0.0
	return w.stat("damage", 5.0) * maxf(_stat("grave_damage_pct", 40.0), 0.0) / 100.0


func _fight(g: Dictionary, delta: float) -> void:
	g["shot_t"] = maxf(float(g["shot_t"]) - delta, 0.0)
	g["fire_t"] = float(g["fire_t"]) - delta
	if float(g["fire_t"]) > 0.0:
		return
	var w := _first_weapon()
	var em = game.get("enemies") if game else null
	if w == null or em == null:
		g["fire_t"] = 0.3
		return
	var at: Vector3 = (g["pos"] as Vector3) + Vector3(GHOST_SIDE, 0, GHOST_FRONT)
	var rng := clampf(w.stat("range", 8.0), num("range_min"), num("range_max"))
	var target: int = em.nearest_index(at, rng, "", true)
	if target < 0:
		g["fire_t"] = 0.15
		return
	g["fire_t"] = fire_every(w)
	var from := at + Vector3(0, HAND_Y, 0)
	var aim: Vector3 = em.pos[target] + Vector3(0, 0.4 + em.lift_h[target], 0)
	var dir := aim - from
	if dir.length_squared() < 0.0001:
		return
	dir = dir.normalized()
	var b = _behavior_of(w)
	var gun: bool = b is ProjectileEmitter and int(b.get("projectile_kind")) >= 0
	var speed := clampf(w.stat("speed", 18.0), 12.0, 40.0) if gun else 18.0
	var pierce := maxi(w.stat_int("pierce", 0), 0) if gun else 0
	var kind: int = int(b.get("projectile_kind")) if gun else _ghost_round_kind()
	var pm = game.get("projectiles")
	if pm != null and kind >= 0:
		pm.fire(kind, from, dir * speed, round_damage(w), pierce, 0.2, rng / speed + 0.1, _shooter_for(), 0.0, HAND_Y)
	shots += 1
	g["shot_t"] = 0.12
	var ghost = g.get("ghost")
	if ghost is BillboardSprite:
		(ghost as BillboardSprite).set_flip(dir.x < 0.0)
	if not Run.sim_mode:
		var fx = game.get("fx")
		if fx != null:
			fx.burst(from + dir * 0.25, Color(str(params().get("round", DEFAULTS["round"]))), 0.28)
		if _sound_t <= 0.0:
			_sound_t = SOUND_GAP
			var sid := str(w.def.sfx.get("fire", ""))
			if sid != "":
				Audio.play(sid, from)


func _behavior_of(w: WeaponInstance):
	var bs = game.get("_behaviors") if game else null
	return (bs as Dictionary).get(w.def.id) if bs is Dictionary else null


## The ghosts' own WeaponInstance (a WeaponDef made here under the item's id, a pale tracer): every round is recorded as
## the item's (Run.add_damage), never as the copied weapon's.
func _shooter_for() -> WeaponInstance:
	var sid := source_id()
	if _shooter != null and _shooter_src == sid:
		return _shooter
	var d := WeaponDef.new()
	d.id = sid
	d.display_name = PassiveDef.display_name_of(sid, "Undertaker's Shovel")
	d.max_level = 1
	d.params = {"tracer": true, "tracer_color": str(params().get("round", DEFAULTS["round"])), "tracer_alpha": 0.75}
	_shooter = WeaponInstance.new(d, 1)
	_shooter_src = sid
	return _shooter


## The pale round a ghost fires for a weapon that is not a gun (registered once).
func _ghost_round_kind() -> int:
	if _round_kind >= 0:
		return _round_kind
	var pm = game.get("projectiles") if game else null
	if pm == null:
		return -1
	var m := SphereMesh.new()
	m.radius = 0.09
	m.height = 0.18
	m.radial_segments = 8
	m.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(str(params().get("round", DEFAULTS["round"])))
	_round_kind = pm.register_kind(m, mat, 1.0)
	return _round_kind


# ---------------------------------------------------------------- the look

func _grave_texture() -> Texture2D:
	if _grave_tex != null:
		return _grave_tex
	var src: Array = Run.item_params("grave")
	var folder := "res://content/passives/%s/" % (str(src[0]) if not src.is_empty() else SOURCE_DEFAULT)
	var path := folder + str(params().get("sprite", DEFAULTS["sprite"]))
	if ResourceLoader.exists(path):
		_grave_tex = load(path) as Texture2D
	if _grave_tex == null:
		# no painting yet: a plain grey slab
		var img := Image.create(16, 24, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.55, 0.55, 0.58))
		_grave_tex = ImageTexture.create_from_image(img)
	return _grave_tex


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
	var pl = game.get("player")
	var art: CharacterDef = null
	if pl != null:
		art = pl.get("look") as CharacterDef
		if art == null:
			art = pl.get("character") as CharacterDef
	var tex: Texture2D = art.sprite if art and art.sprite else (PlaceholderArt.character_strip(art) if art else null)
	if tex == null:
		return null
	var s := BillboardSprite.new()
	s.name = "Ghost"
	s.enable_over_trails()
	add_child(s)
	var anims: Dictionary = art.anims if art.sprite else {"idle": 2, "run": 4, "turn": 1, "hit": 1, "die": 1, "cheer": 1}
	s.setup(tex, anims, HERO_ORDER, GHOST_H, art.strip_cols if art.sprite else 0, art.fps if art.sprite else {})
	s.play("idle_s" if s.has_animation("idle_s") else "idle")
	var tint := Color(str(params().get("ghost_tint", DEFAULTS["ghost_tint"])))
	s.set_ghost(Color(tint.r, tint.g, tint.b, 1.0))
	s.set_flash(GHOST_WASH)
	s.set_fade(0.0)
	return s


## The ghost `up` of the way out of the grave (0 under the sand, 1 standing, past 1 drifting up and away) at `alpha` of
## its see-through.
func _place_ghost(g: Dictionary, up: float, alpha: float) -> void:
	var s = g.get("ghost")
	if not (s is BillboardSprite):
		return
	var gs := s as BillboardSprite
	var base: Vector3 = (g["pos"] as Vector3) + Vector3(GHOST_SIDE, 0, GHOST_FRONT)
	var y := -GHOST_H * (1.0 - up) if up <= 1.0 else (up - 1.0) * 1.7
	var bob := sin((_clock + float(g["age"])) * TAU * BOB_HZ) * BOB if up >= 1.0 else 0.0
	gs.global_position = base + Vector3(0, y + bob, 0)
	gs.set_fade(clampf(alpha, 0.0, 1.0) * num("ghost_alpha"))
	var kick := float(g.get("shot_t", 0.0)) / 0.12
	gs.set_squash(1.0 + 0.06 * kick, 1.0 - 0.06 * kick)


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
