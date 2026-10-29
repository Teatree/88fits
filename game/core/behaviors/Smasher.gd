## The Hammer (pass 35): a hammer appears over the hero's head, rears back and comes down in an overhead swoop on the
## thickest crowd within `range`. Where it lands is a small explosion: `damage` to everything inside the blast
## (params.smash.radius times `area`), thrown outwards from the impact. `amount` hammers come down a beat apart, each
## on a crowd of its own while there are crowds enough (WeaponBehavior.crowd_spots).
## The visual scene's "Hammer" node is the model: its grip at the origin, a "Handle" running one metre down -Z (stretched
## to the reach while it swings) and a "Head" at the far end (moved with the handle and sized with the blast).
## Pass 46, a swing in six beats so it reads: it appears overhead (`rise`), winds up (`windup`: rears back past upright
## with an ease-out and a slight twist about the handle, holding `windup_hold` of it at the top), swoops (`swing`: an
## ease-in cubic, with the smear), hits (the head squashes for SQUASH_TIME and the camera kicks), bounces off the ground
## (`bounce`) and lifts away fading (`fade`). Where it lands is settled as the wind-up ends: on the creature it was aimed
## at, where that one will be (the crowd walks on through the wind-up). The whole hammer is `size` times the model, the
## head's reach to the ground with it (the handle still stretches to the strike), its grip `grip_up` over the hero.
## params.smash: radius, rise, windup, windup_hold, swing, bounce, fade, stagger, shake, size, grip_up; `aftershock`
## {frac, scale, delay}: a second, wider ring a beat after the impact; `quake` {lines, length, width, frac}: fissures split
## the ground from every impact.
## Pass 48, the paths. Thor's Wrath (params.thor {chance, zaps, reach, frac}): `chance` per impact that `zaps` bolts jump
## off the blast's rim to the nearest creatures standing outside the blast within `reach` (none when nobody stands out
## there), `frac` of the hammer's damage each. Giant Slayer (params.giant_slayer {chance, mult, always}): `chance` per
## impact (every impact with `always`: the Earthshaker) that a boss, an Elite or an elite-modded creature in the blast
## takes `mult` times the damage, with a gold flash ring and a kick of the camera. The Earthshaker's quake carries `zap`
## {reach, frac}: lightning runs down every crack and jumps to whatever stands within `reach` of one, `frac` of the hit
## each, once a blow; and `roll` {delay, frac, steps, step}: `delay` after the impact a second wave rolls out along every
## crack from the impact to its end in `steps` beats `step` apart, `frac` of the hit to whatever stands on the crack.
## The handle stretches along its own long axis and the head keeps the model's proportions (the rebuilt Earthshaker's
## head is a scaled cube; the stretch had widened the old handle instead of lengthening it).
class_name Smasher
extends WeaponBehavior

const GRIP_UP := 1.75      # the grip hangs this far over the hero's feet (params.smash.grip_up)
const HEAD_HALF := 0.32    # half the head's height at scale 1: the head's face meets the ground, not its middle
const REST_LEN := 1.1      # the handle's length while the hammer is raised (the model's own)
const SMEAR_LIFE := 0.14
## the swing's poses: overhead and a little forward as it appears, rearing back past upright at the top of the wind-up
## (radians of pitch: a quarter turn is straight up), and the twist about the handle at the top
const PITCH_APPEAR := 1.25
const PITCH_BACK := 2.3
const TWIST := 0.22
## the head squashed flat on the ground for this long when it hits (about three frames), to SQUASH x 1/SQUASH
const SQUASH_TIME := 0.05
const SQUASH := 0.8
## Thor's Wrath's zaps and the Earthshaker's crack lightning: blue bolts, thinner than the Static Field's when Fx takes a
## width (ZAP_WIDTH, its third argument), a small spark where each lands; the Giant Slayer's crush in gold
const ZAP_BLUE := Color(0.45, 0.7, 1.0)
const SPARK_BLUE := Color(0.62, 0.82, 1.0)
const ZAP_WIDTH := 0.5
const CRUSH_GOLD := Color(1.0, 0.8, 0.25)
## jumps drawn a blow off the cracks (every creature by a crack is hit; only this many get a bolt of their own)
const MAX_JUMPS := 5

var _proto: Node3D
var _pool: Array = []      # hammer nodes, reused
var _swings: Array = []    # {node, handle, head, at, yaw, t, hit, len1, pitch1, smear: []}
var _later: Array = []     # {t, fn}: aftershocks waiting their beat
var _smear: MeshInstance3D
var _smear_mesh: ImmediateMesh
var _clock := 0.0
## what the paths did so far (tests, the arena): Thor's zaps, Giant Slayer crushes, creatures zapped off a crack, and
## creatures caught by a crack's rolling wave
var zaps := 0
var crushes := 0
var crack_zaps := 0
var rolls := 0


func _on_setup() -> void:
	_proto = visual.get_node_or_null("Hammer")
	if _proto:
		_proto.visible = false


func _smash(key: String, default: float) -> float:
	var s = inst.params.get("smash", {})
	return float(s.get(key, default)) if s is Dictionary else default


func _smash_dict(key: String) -> Dictionary:
	var s = inst.params.get("smash", {})
	if s is Dictionary and s.get(key) is Dictionary:
		return s[key]
	return {}


func _blast_r() -> float:
	return _smash("radius", 1.6) * stat("area", 1.0)


func _take_node() -> Dictionary:
	for it: Dictionary in _pool:
		if not it["busy"]:
			it["busy"] = true
			return it
	if _proto == null:
		return {}
	var n: Node3D = _proto.duplicate()
	n.top_level = true
	visual.add_child(n)
	var handle := n.find_child("Handle", true, false) as Node3D
	var head := n.find_child("Head", true, false) as Node3D
	var it := {"node": n, "handle": handle, "head": head, "busy": true,
			"handle_rest": handle.scale if handle else Vector3.ONE, "axis": long_axis(handle),
			"head_rest": head.scale if head else Vector3.ONE, "half": head_half(head)}
	_pool.append(it)
	return it


## The axis the handle's mesh runs along (0 x, 1 y, 2 z): the stretch lengthens that one. The Blender handles are turned
## a quarter about x on import and run down their own y; a plain one runs down z.
static func long_axis(handle: Node3D) -> int:
	if handle is MeshInstance3D and (handle as MeshInstance3D).mesh:
		var size: Vector3 = (handle as MeshInstance3D).get_aabb().size
		var axis := 0
		for k in [1, 2]:
			if size[k] > size[axis]:
				axis = k
		return axis
	return 2


## Half the head's height at scale 1, its own scale in it (HEAD_HALF without a mesh): the face that meets the ground.
static func head_half(head: Node3D) -> float:
	if head is MeshInstance3D and (head as MeshInstance3D).mesh:
		return (head as MeshInstance3D).get_aabb().size.y * 0.5 * absf(head.scale.y)
	return HEAD_HALF


func _fire() -> bool:
	var reach := stat("range", 4.6)
	var r := _blast_r()
	var n: int = maxi(stat_int("amount", 1), 1)
	# pass 95 (lane ITEMS): "Fire forward" (FireForward.dir, Settings.fire_forward): the blow lands 75% of the reach ahead
	# along his facing (FireForward.NEAR_FRAC: the smash's radius covers the range's end) while no creature stands within
	# 75% of the range; else on the thickest crowd as before
	var fwd: Vector3 = FireForward.dir(inst, player, game.enemies, 4.6)
	var spots: Array = [player.global_position + fwd * reach * FireForward.NEAR_FRAC] if fwd != Vector3.ZERO else crowd_spots(n, reach, r)
	if spots.is_empty():
		return false
	var stagger := _smash("stagger", 0.12)
	for k in range(n):
		var at: Vector3 = spots[k % spots.size()]
		if k >= spots.size():
			# more hammers than crowds: the extra ones land round the thickest, not on the same spot
			at += Vector3(Dice.r.randf_range(-1.0, 1.0), 0.0, Dice.r.randf_range(-1.0, 1.0)) * r * 0.6
		at.y = game.map.height_at(at.x, at.z) if game.map else at.y
		var it := _take_node()
		if it.is_empty():
			break
		var d: Vector3 = at - player.global_position
		d.y = 0.0
		if d.length_squared() < 0.01:
			d = player.forward()
		# the creature it is aimed at: the strike follows it through the wind-up
		var anchor: int = game.enemies.nearest_index(at, r, "", true)
		var sw := {"it": it, "at": at, "yaw": atan2(-d.x, -d.z), "anchor": anchor, "aimed": false,
				"t": -stagger * float(k), "hit": false, "smear": []}
		_swings.append(sw)
	return true


## Where the grip is: over the hero's head, a little towards the strike.
func _grip(sw: Dictionary) -> Vector3:
	var yaw: float = sw["yaw"]
	return player.global_position + Vector3(0, _smash("grip_up", GRIP_UP), 0) + Vector3(-sin(yaw), 0.0, -cos(yaw)) * 0.25


## The beats of a swing, in seconds from its start: [appeared, wound up, landed, bounced, gone].
func phase_times() -> Array:
	var rise := maxf(_smash("rise", 0.12), 0.02)
	var windup := maxf(_smash("windup", 0.34), 0.05)
	var swing := maxf(_smash("swing", 0.18), 0.04)
	var bounce := maxf(_smash("bounce", _smash("hold", 0.18)), 0.04)
	var fade := maxf(_smash("fade", 0.22), 0.05)
	return [rise, rise + windup, rise + windup + swing, rise + windup + swing + bounce, rise + windup + swing + bounce + fade]


## As the wind-up ends the strike settles on the creature it was aimed at, where it will be when the head comes down
## (its walk carried on for the swing); a strike whose creature is gone, or has walked out of reach, stays where it was.
func _settle(sw: Dictionary, swing: float) -> void:
	sw["aimed"] = true
	var em: EnemyManager = game.enemies
	var a: int = int(sw.get("anchor", -1))
	if em == null or a < 0 or not em.is_alive(a):
		return
	var at: Vector3 = em.pos[a] + em.vel[a] * swing
	var d: Vector3 = at - player.global_position
	d.y = 0.0
	if d.length() > stat("range", 4.6) + 1.0 or d.length_squared() < 0.01:
		return
	at.y = game.map.height_at(at.x, at.z) if game.map else at.y
	sw["at"] = at
	sw["yaw"] = atan2(-d.x, -d.z)


func _tick(delta: float) -> void:
	_clock += delta
	var beats := phase_times()
	var t0: float = beats[0]
	var t1: float = beats[1]
	var t2: float = beats[2]
	var t3: float = beats[3]
	var t4: float = beats[4]
	var hold_top := clampf(_smash("windup_hold", 0.08), 0.0, (t1 - t0) - 0.02)
	var size := maxf(_smash("size", 1.0), 0.2)
	var r := _blast_r()
	var head_s := clampf(r / 1.6, 0.75, 1.9)
	for k in range(_swings.size() - 1, -1, -1):
		var sw: Dictionary = _swings[k]
		var it: Dictionary = sw["it"]
		var n: Node3D = it["node"]
		sw["t"] = float(sw["t"]) + delta
		var t: float = sw["t"]
		if t < 0.0:
			n.visible = false
			continue
		if not n.visible:
			sfx("fire", player.global_position)
		n.visible = true
		if t >= t1 and not sw["aimed"]:
			_settle(sw, t2 - t1)
		var grip := _grip(sw)
		var at: Vector3 = sw["at"]
		# the pitch that puts the head's face on the target: the handle points down at the ground past the crowd's centre
		# (lengths in the model's units: the node is `size` times the model)
		var flat := Vector2(at.x - grip.x, at.z - grip.z).length()
		var drop: float = grip.y - (at.y + float(it.get("half", HEAD_HALF)) * head_s * size)
		var len1 := sqrt(flat * flat + drop * drop) / size
		var pitch1 := -atan2(drop, maxf(flat, 0.05))
		var pitch := PITCH_APPEAR
		var roll := 0.0
		var length := REST_LEN
		var s := 1.0
		var squash := Vector3.ONE
		if t < t0:
			# it appears overhead with a pop
			s = _back_out(t / t0)
		elif t < t1:
			# the wind-up: rears back past upright, fast then slow, turning a little about the handle, and holds at the top
			var u := clampf((t - t0) / maxf(t1 - t0 - hold_top, 0.01), 0.0, 1.0)
			var e := 1.0 - pow(1.0 - u, 3.0)
			pitch = lerpf(PITCH_APPEAR, PITCH_BACK, e)
			roll = TWIST * e
			if u >= 1.0:
				pitch += 0.025 * sin(t * 90.0)
		elif t < t2:
			# the swoop: faster and faster, the handle reaching out to the crowd on the way down
			var u2 := (t - t1) / (t2 - t1)
			var e2 := u2 * u2 * u2
			pitch = lerpf(PITCH_BACK, pitch1, e2)
			length = lerpf(REST_LEN, len1, e2)
			roll = TWIST * (1.0 - e2)
			_add_smear(sw, grip, pitch, length * size, sw["yaw"])
		elif t < t3:
			if not sw["hit"]:
				sw["hit"] = true
				_impact(at, r)
			# planted: squashed flat for a moment, then a bounce off the ground
			var u3 := (t - t2) / (t3 - t2)
			pitch = pitch1 + 0.16 * sin(PI * u3)
			length = len1
			if t - t2 < SQUASH_TIME:
				squash = Vector3(1.0 / SQUASH, SQUASH, 1.0 / SQUASH)
		elif t < t4:
			# it lifts away and fades
			var u4 := (t - t3) / (t4 - t3)
			pitch = pitch1 + 0.5 * u4
			length = len1
			s = 1.0 - u4 * u4
		else:
			n.visible = false
			it["busy"] = false
			_swings.remove_at(k)
			continue
		n.global_position = grip
		n.rotation = Vector3(pitch, sw["yaw"], roll)
		n.scale = Vector3.ONE * maxf(s, 0.01) * size
		var handle: Node3D = it["handle"]
		var head: Node3D = it["head"]
		if handle:
			# longer along its own length only, as thick as the model made it
			var hs: Vector3 = it["handle_rest"]
			var ax: int = it["axis"]
			hs[ax] *= length / REST_LEN
			handle.scale = hs
		if head:
			head.position = Vector3(0.0, 0.0, -length)
			head.scale = (it["head_rest"] as Vector3) * squash * head_s
	_tick_later(delta)
	_draw_smear()


## An elastic pop-in: overshoots a touch and settles.
func _back_out(u: float) -> float:
	var c := 1.9
	var x := u - 1.0
	return 1.0 + (c + 1.0) * x * x * x + c * x * x


func _impact(at: Vector3, r: float) -> void:
	var em: EnemyManager = game.enemies
	var wid := inst.def.id
	var dmg := stat("damage", 20.0)
	var knock := stat("knockback", 10.0)
	var pdmg := stat("poison_damage", 0.0)
	var fdmg := stat("fire_damage", 0.0)
	# Giant Slayer: this blow crushes the big one in its blast (the roll is the blow's, not each creature's)
	var slay := slayer_rolls()
	var slay_mult := float(_slayer().get("mult", 2.5))
	var crushed: Array = []
	for e in em.indices_in_radius(at, r):
		var away: Vector3 = em.pos[e] - at
		away.y = 0.0
		if pdmg > 0.0:
			em.poison(e, wid, pdmg, maxi(stat_int("poison_stacks", 1), 1), stat("poison_duration", 8.0))
		if fdmg > 0.0:
			em.ignite(e, wid, fdmg, stat("fire_duration", 1.8), stat("fire_spread", 0.4))
		# the closer to the head, the harder it flies
		var f: float = knock * (1.0 - 0.45 * clampf(away.length() / maxf(r, 0.1), 0.0, 1.0))
		var d := dmg
		if slay and em.is_big_game(e):
			d *= slay_mult
			crushed.append(em.pos[e] + Vector3(0, em.size[e] * 0.5, 0))
			crushes += 1
		if em.damage(e, d, wid, away, f):
			inst.kills += 1
	var hot := fdmg > 0.0
	game.fx.sand(at, 0.9 + 0.3 * r)
	game.fx.burst(at + Vector3(0, 0.35, 0), Color(1.0, 0.55, 0.2) if hot else Color(0.95, 0.85, 0.65), r * 0.75)
	game.telegraphs.flash_ring(at, r, Color(1.0, 0.6, 0.25) if hot else Color(1.0, 0.9, 0.6), 0.32)
	game.telegraphs.scorch(at, r * 0.6, Color(0.12, 0.08, 0.06, 0.55), Color(0.25, 0.16, 0.1, 0.0), 0.8, 1.6)
	game.camera.shake(_smash("shake", 0.35))
	sfx("hit", at)
	for p: Vector3 in crushed:
		_crush_fx(p)
	_thor(at, r, dmg)
	var af := _smash_dict("aftershock")
	if not af.is_empty():
		_later.append({"t": float(af.get("delay", 0.18)), "at": at, "r": r * float(af.get("scale", 2.0)), "frac": float(af.get("frac", 0.4)), "kind": "aftershock"})
	var qk := _smash_dict("quake")
	if not qk.is_empty():
		_quake(at, qk, dmg)


# ---------------------------------------------------------------- Giant Slayer

func _slayer() -> Dictionary:
	var gs = inst.params.get("giant_slayer")
	return gs if gs is Dictionary else {}


## Whether this blow crushes: always with `giant_slayer.always` (the Earthshaker), else `chance` of the time; never
## without the path.
func slayer_rolls() -> bool:
	var gs := _slayer()
	if gs.is_empty():
		return false
	if bool(gs.get("always", false)):
		return true
	return Dice.r.randf() < float(gs.get("chance", 0.35))


## The crush on a big one: a gold flash ring round it, a gold burst on it, and a short kick of the camera.
func _crush_fx(p: Vector3) -> void:
	var ground := Vector3(p.x, _ground_y(p), p.z)
	game.telegraphs.flash_ring(ground, 1.5, CRUSH_GOLD, 0.4)
	game.fx.burst(p + Vector3(0, 0.4, 0), CRUSH_GOLD, 0.9)
	game.camera.shake(0.25)


# ---------------------------------------------------------------- Thor's Wrath

## Thor's Wrath's targets for a blow at `at` with a blast of `r`: the `n` nearest creatures standing outside the blast
## and within `reach` of the impact, nearest first. None when nobody stands out there.
func zap_targets(at: Vector3, r: float, reach: float, n: int) -> Array:
	var em: EnemyManager = game.enemies
	var near: Array = []
	for e in em.indices_in_radius(at, reach):
		if em.alive[e] == 0 or em.state[e] == EnemyManager.STATE_DYING:
			continue
		var d := Vector2(em.pos[e].x - at.x, em.pos[e].z - at.z).length()
		if d <= r:
			continue
		near.append([d, e])
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var out: Array = []
	for k in range(mini(n, near.size())):
		out.append(int(near[k][1]))
	return out


## `chance` of a blow: bolts off the blast's rim to the nearest creatures outside it, `frac` of the hammer's damage each.
func _thor(at: Vector3, r: float, dmg: float) -> void:
	var th = inst.params.get("thor")
	if not (th is Dictionary) or Dice.r.randf() >= float(th.get("chance", 0.3)):
		return
	var targets := zap_targets(at, r, float(th.get("reach", 7.0)), int(th.get("zaps", 3)))
	if targets.is_empty():
		return
	var em: EnemyManager = game.enemies
	var hit := dmg * float(th.get("frac", 0.35))
	for e: int in targets:
		var to: Vector3 = em.pos[e]
		var dir := Vector3(to.x - at.x, 0.0, to.z - at.z).normalized()
		var from := at + dir * r * 0.85
		from.y = _ground_y(from) + 0.35
		var chest := to + Vector3(0, em.size[e] * 0.55 + em.lift_h[e], 0)
		_bolt([from, chest])
		_spark(chest)
		zaps += 1
		if em.damage(e, hit, inst.def.id, dir, 3.0):
			inst.kills += 1
	Audio.play("w_thor_zap", at)


## A bolt through `pts`: Fx.lightning, made thin (ZAP_WIDTH) when Fx takes a width as its third argument.
func _bolt(pts: Array, col: Color = ZAP_BLUE) -> void:
	var fx = game.get("fx")
	if fx == null or not fx.has_method("lightning"):
		return
	if fx.get_method_argument_count("lightning") >= 3:
		fx.lightning(pts, col, ZAP_WIDTH)
	else:
		fx.lightning(pts, col)


## The small blue spark where a zap lands.
func _spark(at: Vector3) -> void:
	game.fx.burst(at, SPARK_BLUE, 0.3)


func _ground_y(p: Vector3) -> float:
	return game.map.height_at(p.x, p.z) if game.map else p.y


# ---------------------------------------------------------------- the Earthshaker

## The Earthshaker's fissures: `lines` cracks run out from the impact, and whatever stands on one takes `frac` of the hit.
## With `zap` the lightning runs down every crack and jumps to whatever stands near one; with `roll` a second wave rolls
## along each crack a beat later.
func _quake(at: Vector3, qk: Dictionary, dmg: float) -> void:
	var em: EnemyManager = game.enemies
	var wid := inst.def.id
	var n := int(qk.get("lines", 4))
	var length := float(qk.get("length", 4.5)) * stat("area", 1.0)
	var width := float(qk.get("width", 0.9))
	var frac := float(qk.get("frac", 0.6))
	var zap: Dictionary = qk["zap"] if qk.get("zap") is Dictionary else {}
	var roll: Dictionary = qk["roll"] if qk.get("roll") is Dictionary else {}
	var a0 := Dice.r.randf() * TAU
	var col := Color(1.0, 0.5, 0.15)
	var cracks: Array = []
	for k in range(n):
		var a := a0 + TAU * float(k) / float(n) + Dice.r.randf_range(-0.2, 0.2)
		var dir := Vector3(cos(a), 0.0, sin(a))
		cracks.append(dir)
		game.telegraphs.line(at, dir, length, 0.9, col, width)
		for j in range(3):
			var p := at + dir * length * (0.3 + 0.3 * float(j))
			p.y = game.map.height_at(p.x, p.z) if game.map else at.y
			game.fx.sand(p, 0.7)
			game.fx.flame(p, 0.8, 0.5)
		for e: int in on_crack(at, dir, length, width * 0.5):
			var d: Vector3 = em.pos[e] - at
			d.y = 0.0
			var side := d - dir * d.dot(dir)
			# thrown off the crack, to whichever side it stood
			if em.damage(e, dmg * frac, wid, side if side.length_squared() > 0.01 else dir, 6.0):
				inst.kills += 1
		if not roll.is_empty():
			_roll_crack(at, dir, length, width, roll)
	if not zap.is_empty():
		_crack_lightning(at, cracks, length, zap, dmg)


## The creatures standing on the crack from `at` along `dir` (`half_w` either side of it, their own width added), between
## `f0` and `f1` of its `length` from the impact.
func on_crack(at: Vector3, dir: Vector3, length: float, half_w: float, f0: float = 0.0, f1: float = 1.0) -> Array:
	var em: EnemyManager = game.enemies
	var out: Array = []
	var a := length * f0
	var b := length * f1
	var mid := at + dir * (a + b) * 0.5
	for e in em.indices_in_radius(mid, (b - a) * 0.5 + half_w + 1.0):
		if em.state[e] == EnemyManager.STATE_DYING:
			continue
		var d: Vector3 = em.pos[e] - at
		d.y = 0.0
		var along := d.dot(dir)
		if along < a or along > b:
			continue
		if (d - dir * along).length() > half_w + em.radius[e]:
			continue
		out.append(e)
	return out


## The lightning down the cracks: a bolt along each, then a jump to everything standing within `zap.reach` of a crack,
## `zap.frac` of the hit, once a blow however many cracks it stands by.
func _crack_lightning(at: Vector3, cracks: Array, length: float, zap: Dictionary, dmg: float) -> void:
	var em: EnemyManager = game.enemies
	var reach := float(zap.get("reach", 1.5))
	var hit := dmg * float(zap.get("frac", 0.5))
	for dir: Vector3 in cracks:
		var pts: Array = []
		for j in range(4):
			var p: Vector3 = at + dir * length * float(j) / 3.0
			p.y = _ground_y(p) + 0.15
			pts.append(p)
		_bolt(pts)
	var jumps := 0
	var any := false
	for e in em.indices_in_radius(at, length + reach):
		if em.state[e] == EnemyManager.STATE_DYING:
			continue
		var d: Vector3 = em.pos[e] - at
		d.y = 0.0
		var best := INF
		var foot := at
		for dir: Vector3 in cracks:
			var along := clampf(d.dot(dir), 0.0, length)
			var gap := (d - dir * along).length()
			if gap < best:
				best = gap
				foot = at + dir * along
		if best > reach:
			continue
		any = true
		crack_zaps += 1
		var chest: Vector3 = em.pos[e] + Vector3(0, em.size[e] * 0.55 + em.lift_h[e], 0)
		if jumps < MAX_JUMPS:
			jumps += 1
			_bolt([Vector3(foot.x, _ground_y(foot) + 0.15, foot.z), chest])
			_spark(chest)
		var off: Vector3 = em.pos[e] - foot
		off.y = 0.0
		if em.damage(e, hit, inst.def.id, off, 3.0):
			inst.kills += 1
	if any:
		Audio.play("w_thor_zap", at)


## The roll along one crack: `roll.steps` beats, each hitting the next stretch of the crack outwards from the impact;
## a creature is caught once a roll.
func _roll_crack(at: Vector3, dir: Vector3, length: float, width: float, roll: Dictionary) -> void:
	var steps: int = maxi(int(roll.get("steps", 4)), 1)
	var step_t := float(roll.get("step", 0.07))
	var delay := float(roll.get("delay", 0.3))
	var caught := {}
	for s in range(steps):
		_later.append({"t": delay + step_t * float(s), "kind": "roll", "at": at, "dir": dir, "length": length,
				"width": width, "f0": float(s) / float(steps), "f1": float(s + 1) / float(steps),
				"frac": float(roll.get("frac", 0.4)), "caught": caught})


func _tick_later(delta: float) -> void:
	var em: EnemyManager = game.enemies
	for k in range(_later.size() - 1, -1, -1):
		var job: Dictionary = _later[k]
		job["t"] = float(job["t"]) - delta
		if float(job["t"]) > 0.0:
			continue
		_later.remove_at(k)
		if str(job.get("kind", "")) == "roll":
			_roll_step(job)
			continue
		var at: Vector3 = job["at"]
		var r: float = job["r"]
		var before := Run.kills
		for e in em.indices_in_radius(at, r):
			var away: Vector3 = em.pos[e] - at
			away.y = 0.0
			em.damage(e, stat("damage", 20.0) * float(job["frac"]), inst.def.id, away, stat("knockback", 10.0) * 0.6)
		inst.kills += Run.kills - before
		game.telegraphs.flash_ring(at, r, Color(1.0, 0.85, 0.55), 0.4)
		for j in range(6):
			var a := TAU * float(j) / 6.0
			var p := at + Vector3(cos(a), 0.0, sin(a)) * r * 0.85
			p.y = game.map.height_at(p.x, p.z) if game.map else at.y
			game.fx.sand(p, 0.6)
		game.camera.shake(0.2)


## One beat of a crack's roll: the stretch from `f0` to `f1` of the crack heaves, and what stands on it takes `frac` of
## the hit, thrown off the crack.
func _roll_step(job: Dictionary) -> void:
	var em: EnemyManager = game.enemies
	var at: Vector3 = job["at"]
	var dir: Vector3 = job["dir"]
	var length: float = job["length"]
	var width: float = job["width"]
	var f0: float = job["f0"]
	var f1: float = job["f1"]
	var caught: Dictionary = job["caught"]
	var hit := stat("damage", 20.0) * float(job["frac"])
	for e: int in on_crack(at, dir, length, width * 0.5, f0, f1):
		if caught.has(em.serial[e]):
			continue
		caught[em.serial[e]] = true
		rolls += 1
		var d: Vector3 = em.pos[e] - at
		d.y = 0.0
		var side := d - dir * d.dot(dir)
		if em.damage(e, hit, inst.def.id, side if side.length_squared() > 0.01 else dir, 4.0):
			inst.kills += 1
	var p: Vector3 = at + dir * length * (f0 + f1) * 0.5
	p.y = _ground_y(p)
	game.fx.sand(p, 0.8)
	game.telegraphs.line(at + dir * length * f0, dir, length * (f1 - f0), 0.3, Color(1.0, 0.7, 0.3), width * 1.2)
	if f0 <= 0.0:
		game.camera.shake(0.12)


## The swoop's smear: a fan of the handle's outer half behind the head, fading in SMEAR_LIFE.
func _add_smear(sw: Dictionary, grip: Vector3, pitch: float, length: float, yaw: float) -> void:
	var b := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var axis := b * Vector3(0, 0, -1)
	(sw["smear"] as Array).append({"a": grip + axis * length * 0.55, "b": grip + axis * (length + 0.35), "born": _clock})


func _draw_smear() -> void:
	var any := false
	for sw: Dictionary in _swings:
		var pts: Array = sw["smear"]
		while not pts.is_empty() and _clock - float(pts[0]["born"]) > SMEAR_LIFE:
			pts.pop_front()
		if pts.size() >= 2:
			any = true
	if not any:
		if _smear:
			_smear.visible = false
		return
	if _smear == null:
		_smear_mesh = ImmediateMesh.new()
		_smear = MeshInstance3D.new()
		_smear.mesh = _smear_mesh
		_smear.top_level = true
		_smear.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_smear.material_override = Fx.glow_ribbon_material()
		add_child(_smear)
		_smear.global_transform = Transform3D.IDENTITY
	_smear.visible = true
	_smear_mesh.clear_surfaces()
	_smear_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var hot := stat("fire_damage", 0.0) > 0.0
	var col := Color(1.0, 0.6, 0.25) if hot else Color(1.0, 0.95, 0.8)
	for sw: Dictionary in _swings:
		var pts: Array = sw["smear"]
		for k in range(pts.size() - 1):
			var p0: Dictionary = pts[k]
			var p1: Dictionary = pts[k + 1]
			var a0 := 1.0 - (_clock - float(p0["born"])) / SMEAR_LIFE
			var a1 := 1.0 - (_clock - float(p1["born"])) / SMEAR_LIFE
			var c0 := Color(col.r, col.g, col.b, 0.55 * a0)
			var c1 := Color(col.r, col.g, col.b, 0.55 * a1)
			var i0 := Color(col.r, col.g, col.b, 0.0)
			_smear_mesh.surface_set_color(i0)
			_smear_mesh.surface_add_vertex(p0["a"])
			_smear_mesh.surface_set_color(c0)
			_smear_mesh.surface_add_vertex(p0["b"])
			_smear_mesh.surface_set_color(c1)
			_smear_mesh.surface_add_vertex(p1["b"])
			_smear_mesh.surface_set_color(i0)
			_smear_mesh.surface_add_vertex(p0["a"])
			_smear_mesh.surface_set_color(c1)
			_smear_mesh.surface_add_vertex(p1["b"])
			_smear_mesh.surface_set_color(i0)
			_smear_mesh.surface_add_vertex(p1["a"])
	_smear_mesh.surface_end()
