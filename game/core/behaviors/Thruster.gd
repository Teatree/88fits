## A blade that lives inside the hero and only shows itself to strike. When a creature is within `range` the blade
## thrusts out of the hero towards the nearest one (`amount` blades fan out around that line), hits everything along
## its length once, and slides back in; with nothing in range there is nothing to see. The visual scene's "Blade" node
## is the 3D blade, modelled one metre long down -Z and one unit wide, scaled to the reach and the hit width; the Halberd's `sweep_deg` swings it
## sideways while it is out. Tuning lives in `params.thrust`: out, hold and back seconds, the blade's half-width, the
## fan between blades.
## Slice mode (pass 35, the Sabre and the Zweihänder): `thrust.slice_deg` > 0 swings the blade across the target through
## that arc instead of poking it: `out` seconds to appear at one end of the arc, `slice` seconds a swing, `back` to go.
## Each of `amount` swings runs the other way (left, right, left), the edge hits what it passes once a swing, and a hit
## throws the creature away from the hero and along the swing together (`side` weighs the sideways part). A crescent
## trail follows the edge.
## Pass 48: the blade goes for WeaponBehavior.aim_index: with `"targeting": "priority"` (the Spear, the Sabre and their
## evolutions) the strong and the close before the merely close (EnemyManager.priority_index), else the nearest.
## Pass 53 (Garry's list): `thrust.amount_mode` "blades" makes `amount` blades sweep together in one stroke, fanned
## `fan_deg` apart, each creature hit once a stroke (the Spear's Wide Sweep: "this weapon should be affected by projectile
## count increasing items by adding more spears rather than more thrusts"); the Sabre keeps amount = swings. A thrust has
## bite: a wind-back (`windback` seconds, `windback_frac` of the reach), an eased out, a `hitstop` at full reach when it
## hit, the shaft flexing (`flex`), a streak behind the tip and sparks where it bit. `thrust.stun {chance, seconds}` rolls
## a stun on every hit (EnemyManager.stun, never a boss or an Elite). `thrust.alternate` (the Thunder Lance) makes every
## stroke a sweep and, straight after it, a thrust that throws `alternate_knock` times as hard, so the sweep's stuns are
## still on when the thrust lands; `params.stunned_mult` is what a stunned creature takes from this blade; `thrust.crackle`
## throws one bolt from the tip to the first creature a sweep hits. `params.crit_refund` (the Whirlwind) gives that
## share of the cooldown back on a swing that crits. `params.trail_color` colours the trail when the blade has no element.
## A stroke in progress is never cut short by the next: it finishes, and the next starts the moment it ends.
## Pass 61, the Sabre's cheap mutation looks (Garry chose them): Critical Thinking (`params.razor` {crit_streak,
## streak_length, streak_width, streak_life, color, glow}) shows the visual's hidden "LookRazor" node on the blade (a
## bright razor edge with a soft halo) and draws a white hairline streak across every creature a stroke crits
## (EnemyManager.last_crit, read right after the hit; SLASH_MAX at most, one ImmediateMesh over everything). Riposte
## (`params.riposte` {flick_deg, flick, sound, volume_db}) shows the hidden "LookGuard" (a heavy brass guard bar) and,
## at the end of every slice, flicks the blade back `flick_deg` against its last swing before it goes (inside the `back`
## time, so a stroke is no longer than it was), with a clang: Fx.clang_spark and `sound` (no clang id exists:
## w_iron_hit). Both are set on every build change (refresh_marks) and go with the mutation.
class_name Thruster
extends WeaponBehavior

var _proto: Node3D
var _blades: Array = []
var _active := 0
var _t := -1.0
var _dir := Vector3.FORWARD
var _hit_done := false
# slice mode
var _swing := -1
var _swing_hits: Dictionary = {}
var _edge_prev := 0.0
var _trail: MeshInstance3D
var _trail_mesh: ImmediateMesh
## one spoke list per blade (pass 53: Wide Sweep's blades each leave their own crescent): Vector3(edge yaw, time laid, reach)
var _trails: Array = []
var _clock := 0.0
var _trail_col := Color(0.86, 0.92, 1.0)
## the creature the last stroke went for (tests, the arena)
var target := -1
## Pass 53: whether this stroke slices (the weapon's own mode, or the sweep half of an alternate stroke), whether its
## `amount` is blades sweeping together, which half of an alternate stroke runs (0 none, 1 the sweep, 2 the thrust), a
## fire asked while a stroke ran (it starts the moment the stroke ends), the hit-stop added to the hold, and whether this
## swing's crit already refunded.
var _slicing := false
var _blades_mode := false
var _combo := 0
var _pending := false
var _hold_extra := 0.0
var _refund_done := false
var _crackled := false
## the thrust's streak: where the tip was each tick while it went out, and when
var _streak_p := PackedVector3Array()
var _streak_t := PackedFloat32Array()
## creatures this blade stunned, by index, until when on `_clock` (the fallback for stunned_mult while EnemyManager has no
## `is_stunned`)
var _stunned_until: Dictionary = {}
## Pass 61: the looks the build shows (to skip a rebuild that changes nothing), the crit streaks alive
## ({c, d, t, len, w}) and their mesh, whether this stroke's flick has clanged; streaks drawn and clangs (tests).
var _looks_key := "-"
var _slashes: Array = []
var _slash_mi: MeshInstance3D
var _slash_mesh: ImmediateMesh
var _clanged := false
var slashes := 0
var clangs := 0
## Diagnostics and tests (pass 53): strokes begun, sweeps and thrusts begun, stuns landed, cooldown refunds, crackles.
var strokes := 0
var sweeps := 0
var thrusts := 0
var stuns := 0
var refunds := 0
var crackles := 0

## Defaults of the pass 53 knobs (every one lives in `params.thrust` when a weapon says otherwise).
const WINDBACK := 0.05
const WINDBACK_FRAC := 0.2
const HITSTOP := 0.04
const FLEX := 1.06
const ALTERNATE_KNOCK := 1.5
const STREAK_LIFE := 0.14
const STREAK_HALF := 0.06
## Critical Thinking's crit streak (pass 61): it draws itself across the creature in SLASH_DRAW, is gone at its life
## (params.razor.streak_life, SLASH_LIFE without), SLASH_MAX at most at once (the oldest goes first), tilted SLASH_TILT up
## along its line so it reads as a slash across the figure, not a line on the sand.
const SLASH_LIFE := 0.26
const SLASH_DRAW := 0.05
const SLASH_MAX := 10
const SLASH_TILT := 0.45
## Riposte's flick (pass 61): it peaks FLICK_PEAK of the way through (the clang) and settles back by its end; at most
## FLICK_SHARE of the stroke's `back` time, which the retract keeps the rest of.
const FLICK_PEAK := 0.35
const FLICK_SHARE := 0.75


func _on_setup() -> void:
	_proto = visual.get_node_or_null("Blade")
	if _proto:
		_proto.visible = false


func _thrust(key: String, default: float) -> float:
	var t = inst.params.get("thrust", {})
	return float(t.get(key, default)) if t is Dictionary else default


## A sub-dictionary of params.thrust (`stun`), {} when there is none.
func _thrust_dict(key: String) -> Dictionary:
	var t = inst.params.get("thrust", {})
	if t is Dictionary:
		var d = (t as Dictionary).get(key)
		if d is Dictionary:
			return d
	return {}


func _thrust_flag(key: String) -> bool:
	var t = inst.params.get("thrust", {})
	return bool((t as Dictionary).get(key, false)) if t is Dictionary else false


## Whether the weapon's own stroke is a slice (the Sabre, the Spear with Wide Sweep, the lances).
func _slices() -> bool:
	return _thrust("slice_deg", 0.0) > 0.0


## Whether `amount` means blades sweeping together in one stroke (pass 53, `thrust.amount_mode` "blades").
func _blades_sweep() -> bool:
	var t = inst.params.get("thrust", {})
	return t is Dictionary and str((t as Dictionary).get("amount_mode", "swings")) == "blades"


func _ensure_blades(n: int) -> void:
	if _proto == null:
		return
	while _blades.size() < n:
		var b: Node3D = _proto.duplicate()
		b.visible = false
		visual.add_child(b)
		_blades.append(b)


## Whether a stroke (either half of an alternate one) is running.
func stroke_running() -> bool:
	return _t >= 0.0


func _fire() -> bool:
	if _t >= 0.0:
		# a stroke is still running (pass 53: a Whirlwind's refunds or a long Flurry can bring the cooldown round first):
		# it finishes, and the next starts the moment it ends (_end_phase)
		_pending = true
		return false
	var reach := stat("range", 2.6)
	var t := aim_index(player.global_position, reach + 0.6)
	if t < 0:
		return false
	target = t
	_aim_at(t)
	strokes += 1
	# an alternate stroke (the Thunder Lance) is a sweep, then a thrust
	_combo = 1 if _thrust_flag("alternate") else 0
	_begin_phase(_slices())
	return true


## The target line: at creature `t`, or along the hero's facing when it is gone.
func _aim_at(t: int) -> void:
	var em: EnemyManager = game.enemies
	if t < 0 or t >= EnemyManager.MAX or em.alive[t] == 0:
		return
	var d: Vector3 = em.pos[t] - player.global_position
	d.y = 0.0
	_dir = d.normalized() if d.length_squared() > 0.001 else player.forward()


## One half of a stroke begins: a slice (a sweep of one blade through its swings, or of `amount` blades together) or a
## thrust of `amount` blades fanned out.
func _begin_phase(slicing: bool) -> void:
	_slicing = slicing
	_active = maxi(stat_int("amount", 1), 1)
	_t = 0.0
	_hit_done = false
	_hold_extra = 0.0
	_swing = -1
	_edge_prev = 0.0
	_swing_hits.clear()
	_refund_done = false
	_crackled = false
	_clanged = false
	_streak_p.clear()
	_streak_t.clear()
	if slicing:
		_blades_mode = _blades_sweep()
		# one blade does every swing, one after the other; in blades mode every blade sweeps at once
		var n: int = _active if _blades_mode else 1
		_ensure_blades(n)
		for k in range(_blades.size()):
			_blades[k].visible = k < n
		sweeps += 1
	else:
		_blades_mode = false
		_ensure_blades(_active)
		for k in range(_blades.size()):
			_blades[k].visible = k < _active
		thrusts += 1
		# a slice sounds on every swing (_tick_slice)
		sfx("fire", player.aim_origin(_dir))
	# Lunge: the stroke carries the hero at the target
	var lg := _thrust("lunge", 0.0)
	if lg > 0.0 and player.has_method("apply_knockback"):
		# his own stroke, not a hostile pull: it carries him under the Invincibility bubble too (pass 60, lane WP; a fake
		# hero with the one-argument apply_knockback still takes it)
		if player.get_method_argument_count("apply_knockback") >= 2:
			player.apply_knockback(_dir * lg * 4.5, false)
		else:
			player.apply_knockback(_dir * lg * 4.5)


## A half of a stroke is over: the blades go, the thrust of an alternate stroke follows its sweep straight away (aimed
## afresh), and a fire that waited starts now.
func _end_phase() -> void:
	for b in _blades:
		b.visible = false
	_t = -1.0
	_swing = -1
	if _combo == 1:
		_combo = 2
		var em: EnemyManager = game.enemies
		var t := target
		if t < 0 or t >= EnemyManager.MAX or em.alive[t] == 0 or em.state[t] == EnemyManager.STATE_DYING:
			t = aim_index(player.global_position, stat("range", 2.6) + 0.6)
		if t >= 0:
			target = t
			_aim_at(t)
		_begin_phase(false)
		return
	_combo = 0
	if _pending:
		_pending = false
		# _process fires when the cooldown is spent; it checks right after _tick, so this stroke's heir starts this frame
		cooldown_left = minf(cooldown_left, 0.0)


func _tick(delta: float) -> void:
	_clock += delta
	if _t >= 0.0 and not _blades.is_empty():
		if _slicing:
			_tick_slice(delta)
		else:
			_tick_thrust(delta)
	# after the blade has moved, so the newest spokes draw this frame at full strength
	_tick_trail()
	_tick_slashes()


## The thrust (pass 53's bite, Garry: "the Spear thrusting should have a bit more bite to it, currently it's quite static
## looking"): the blade pulled back `windback_frac` of its reach over `windback` seconds, shot out with a fast start, held
## at full reach (longer by `hitstop` when it bit) with the shaft flexing past its length and settling, then drawn back.
func _tick_thrust(delta: float) -> void:
	var windback := maxf(_thrust("windback", WINDBACK), 0.0)
	var wb_frac := _thrust("windback_frac", WINDBACK_FRAC)
	var out := maxf(_thrust("out", 0.12), 0.01)
	var hold := _thrust("hold", 0.08) + _hold_extra
	var back := maxf(_thrust("back", 0.2), 0.01)
	var flex := _thrust("flex", FLEX)
	_t += delta
	var reach := stat("range", 2.6)
	var ext := 0.0
	var pull := 0.0
	var streak := false
	if _t < windback:
		# wound back: a short length of blade behind the hero's centre, pointing at the target
		var f := _t / windback
		ext = 0.3
		pull = wb_frac * reach * f
	elif _t < windback + out:
		var u := (_t - windback) / out
		ext = 1.0 - (1.0 - u) * (1.0 - u)
		pull = wb_frac * reach * (1.0 - minf(u * 2.0, 1.0))
		streak = true
	elif _t < windback + out + hold:
		var h: float = (_t - windback - out) / maxf(hold, 0.001)
		ext = 1.0 + (flex - 1.0) * (1.0 - h) * cos(h * TAU)
	elif _t < windback + out + hold + back:
		ext = 1.0 - (_t - windback - out - hold) / back
	else:
		_end_phase()
		return
	var width := _thrust("width", 0.7) * stat("area", 1.0)
	var fan := deg_to_rad(_thrust("fan_deg", 35.0))
	var sweep := deg_to_rad(_thrust("sweep_deg", 0.0))
	# the sweep swings the whole fan from one side to the other over the stroke
	var swing: float = (clampf((_t - windback) / (out + hold + back), 0.0, 1.0) - 0.5) * sweep
	var base := player.global_position + Vector3(0, 0.95, 0) - _dir * pull
	for k in range(_active):
		var off: float = (float(k) - float(_active - 1) * 0.5) * fan + swing
		var yaw: float = atan2(-_dir.x, -_dir.z) + off
		var b: Node3D = _blades[k]
		b.global_position = base
		b.rotation = Vector3(0, yaw, 0)
		b.scale = Vector3(width, 1.0, maxf(reach * ext, 0.05))
	if streak and _active > 0:
		_streak_p.append(_tip_of(_blades[0]))
		_streak_t.append(_clock)
	if not _hit_done and _t >= windback + out:
		_hit_done = true
		if _strike(reach, width, fan, swing):
			_hold_extra = maxf(_thrust("hitstop", HITSTOP), 0.0)


## Where blade `b`'s point is now: its origin less its scaled -Z.
func _tip_of(b: Node3D) -> Vector3:
	return b.global_position - b.global_transform.basis.z


## The edge's angle off the target line at swing progress u (0..1): swing k runs one way, k + 1 the other.
func _edge(k: int, u: float) -> float:
	var half := deg_to_rad(_thrust("slice_deg", 150.0)) * 0.5
	var s := 1.0 if k % 2 == 0 else -1.0
	var e := 0.5 - 0.5 * cos(PI * clampf(u, 0.0, 1.0))
	return s * half * (2.0 * e - 1.0)


## How many swings this slice makes: `amount` (the Sabre), or one with `amount` blades sweeping together (blades mode).
func _swings() -> int:
	return 1 if _blades_mode else _active


## The angle of blade `j` off the edge in blades mode (fanned `fan_deg` apart), 0 for the lone blade.
func _blade_off(j: int) -> float:
	if not _blades_mode:
		return 0.0
	var n := _active
	return (float(j) - float(n - 1) * 0.5) * deg_to_rad(_thrust("fan_deg", 35.0))


func _tick_slice(delta: float) -> void:
	var out := _thrust("out", 0.06)
	var sl := maxf(_thrust("slice", 0.16), 0.02)
	var back := _thrust("back", 0.12)
	# Riposte's flick (pass 61) takes the first part of the back time, the retract the rest
	var flick := flick_time(back)
	_t += delta
	var reach := stat("range", 2.6)
	var width := _thrust("width", 0.7) * stat("area", 1.0)
	var swings := _swings()
	var ext := 1.0
	var k := 0
	var u := 0.0
	var fu := -1.0
	var total := out + sl * float(swings)
	if _t < out:
		ext = _t / out
	elif _t < total:
		k = mini(int((_t - out) / sl), swings - 1)
		u = (_t - out - sl * float(k)) / sl
	elif _t < total + flick:
		k = swings - 1
		u = 1.0
		fu = (_t - total) / flick
	elif _t < total + back:
		k = swings - 1
		u = 1.0
		ext = 1.0 - (_t - total - flick) / maxf(back - flick, 0.001)
	else:
		_end_phase()
		return
	var yaw0: float = atan2(-_dir.x, -_dir.z)
	var a := _edge(k, u)
	# a little roll into the cut, so the flat of the blade shows while it swings
	var s := 1.0 if k % 2 == 0 else -1.0
	var roll := s * 0.35 * sin(PI * clampf(u, 0.0, 1.0))
	if fu >= 0.0:
		# the flick: back against the last swing and settling, the flat turned the other way as it snaps
		var f := flick_at(fu)
		a -= s * deg_to_rad(float(_riposte().get("flick_deg", 38.0))) * f
		roll = -s * 0.5 * f
	var n: int = _active if _blades_mode else 1
	for j in range(mini(n, _blades.size())):
		var b: Node3D = _blades[j]
		b.global_position = player.global_position + Vector3(0, 0.95, 0)
		b.rotation = Vector3(0, yaw0 + a + _blade_off(j), roll)
		b.scale = Vector3(width, 1.0, maxf(reach * ext, 0.05))
	if fu >= 0.0:
		_tick_flick(fu, yaw0, a, reach, s, n)
	if _t < out or _t >= total:
		_edge_prev = a
		return
	if k != _swing:
		# a new swing: a fresh hit list, and the edge starts where this swing starts
		_swing = k
		_swing_hits.clear()
		_refund_done = false
		_edge_prev = _edge(k, 0.0)
		sfx("fire", player.aim_origin(_dir))
	while _trails.size() < n:
		_trails.append([])
	for j in range(n):
		var off := _blade_off(j)
		_cut(yaw0 + off, _edge_prev, a, reach, width, s)
		# spokes no more than ~7 degrees apart, so the crescent stays round at 30 fps
		var steps := maxi(ceili(absf(a - _edge_prev) / 0.12), 1)
		for q in range(1, steps + 1):
			(_trails[j] as Array).append(Vector3(yaw0 + off + lerpf(_edge_prev, a, float(q) / float(steps)), _clock, reach))
	_edge_prev = a


## Everything between the edge's last angle and this one, within reach, takes the cut once this swing (once a stroke in
## blades mode, whichever blade reaches it first).
func _cut(yaw0: float, a0: float, a1: float, reach: float, width: float, s: float) -> void:
	var em: EnemyManager = game.enemies
	var wid := inst.def.id
	var lo := minf(a0, a1)
	var hi := maxf(a0, a1)
	var dmg := stat("damage", 16.0)
	var knock := stat("knockback", 6.0)
	var side := _thrust("side", 1.0)
	var pdmg := stat("poison_damage", 0.0)
	var fdmg := stat("fire_damage", 0.0)
	var pp := player.global_position
	var any := false
	for e in em.indices_in_radius(pp, reach + 0.8):
		if _swing_hits.has(e):
			continue
		var d: Vector3 = em.pos[e] - pp
		d.y = 0.0
		var dist := d.length()
		if dist > reach + em.radius[e]:
			continue
		var rel := 0.0
		if dist > 0.05:
			rel = wrapf(atan2(-d.x, -d.z) - yaw0, -PI, PI)
		# the creature's own width, as an angle at its distance
		var pad := atan2(em.radius[e] + width * 0.5, maxf(dist, 0.3))
		if rel < lo - pad or rel > hi + pad:
			continue
		_swing_hits[e] = true
		var radial := d / dist if dist > 0.05 else _dir
		var cy: float = yaw0 + rel
		# the way the edge travels at the creature: the tangent of the swing
		var tangent := Vector3(-cos(cy), 0.0, sin(cy)) * s
		var kdir := radial + tangent * side
		if pdmg > 0.0:
			em.poison(e, wid, pdmg, maxi(stat_int("poison_stacks", 1), 1), stat("poison_duration", 8.0))
		if fdmg > 0.0:
			em.ignite(e, wid, fdmg, stat("fire_duration", 1.8), stat("fire_spread", 0.4))
		var killed := em.damage(e, dmg * _stunned_mult(em, e), wid, kdir, knock * kdir.length())
		if killed:
			inst.kills += 1
		if _hit_was_crit(em, e):
			_crit_slash(em, e, tangent)
		_after_hit(em, e, killed)
		if not _crackled and _thrust_flag("crackle"):
			_crackle(em, e)
		game.fx_hit(em.pos[e] + Vector3(0, 0.5, 0), inst.def)
		any = true
	if any:
		sfx("hit", pp)


## What follows every hit of this blade (pass 53): the stun roll (`thrust.stun`), and the Whirlwind's refund once a swing
## when the hit was a crit (`params.crit_refund`).
func _after_hit(em: EnemyManager, i: int, killed: bool) -> void:
	if not killed:
		_stun_roll(em, i)
	var refund := float(inst.params.get("crit_refund", 0.0))
	if refund > 0.0 and not _refund_done and _hit_was_crit(em, i):
		_refund_done = true
		cooldown_left -= refund * stat("cooldown", 1.0)
		refunds += 1


## Whether the hit EnemyManager.damage just landed on `i` was a critical: damage() rolls it itself and tells nobody, so
## until it carries `last_crit` (asked of the WD lane) the squash it sets on a crit, 0.55 and nothing else, is the trace.
func _hit_was_crit(em: EnemyManager, i: int) -> bool:
	if "last_crit" in em:
		return bool(em.get("last_crit"))
	return absf(em.squash[i] - 0.55) < 0.001


## `thrust.stun {chance, seconds}` (pass 53, Garry: "a 15% chance that the enemy which is being thrust by the Spear will
## get stunned (not able to move or attack) for 1s"): EnemyManager.stun does the stunning (never a boss or an Elite).
func _stun_roll(em: EnemyManager, i: int) -> void:
	var st := _thrust_dict("stun")
	if st.is_empty():
		return
	var chance := float(st.get("chance", 0.0))
	if chance <= 0.0 or randf() >= chance:
		return
	if not em.has_method("stun"):
		return
	var seconds := float(st.get("seconds", 1.0))
	em.stun(i, seconds)
	_stunned_until[i] = _clock + seconds
	stuns += 1


## Whether creature `i` is stunned right now: EnemyManager's word when it has one, else this blade's own stuns.
func _is_stunned(em: EnemyManager, i: int) -> bool:
	if em.has_method("is_stunned"):
		return bool(em.is_stunned(i))
	if "stun_t" in em:
		return float(em.get("stun_t")[i]) > 0.0
	return float(_stunned_until.get(i, -1.0)) > _clock


## What a stunned creature takes from this blade (`params.stunned_mult`, the Thunder Lance's x1.5), 1 for the rest.
func _stunned_mult(em: EnemyManager, i: int) -> float:
	var sm := float(inst.params.get("stunned_mult", 1.0))
	if absf(sm - 1.0) < 0.0001:
		return 1.0
	return sm if _is_stunned(em, i) else 1.0


## One short bolt from the blade's tip to creature `i` (pass 53, the Thunder Lance's `crackle`): the first hit of a sweep.
func _crackle(em: EnemyManager, i: int) -> void:
	_crackled = true
	var fx = game.get("fx")
	if fx == null or not fx.has_method("lightning"):
		return
	var from: Vector3 = _tip_of(_blades[0]) if not _blades.is_empty() else player.global_position + Vector3(0, 0.95, 0)
	fx.lightning([from, em.pos[i] + Vector3(0, em.size[i] * 0.6, 0)], Color(0.6, 0.78, 1.0), 0.5)
	crackles += 1


## The crescent behind the edge: every tick of a swing leaves a spoke; spokes fade out over TRAIL_LIFE.
const TRAIL_LIFE := 0.18


## The trail's colour: the blade's element, else `params.trail_color` (pass 53, the Whirlwind's pale cyan), else steel.
func _trail_colour() -> Color:
	if stat("fire_damage", 0.0) > 0.0:
		return Color(1.0, 0.55, 0.2)
	if stat("poison_damage", 0.0) > 0.0:
		return Color(0.5, 1.0, 0.35)
	var tc = inst.params.get("trail_color")
	if tc != null and str(tc) != "":
		return Color(str(tc))
	return Color(0.86, 0.92, 1.0)


func _tick_trail() -> void:
	# drop what has faded
	var live := false
	for pts: Array in _trails:
		while not pts.is_empty() and _clock - (pts[0] as Vector3).y > TRAIL_LIFE:
			pts.pop_front()
		if pts.size() >= 2:
			live = true
	while not _streak_t.is_empty() and _clock - _streak_t[0] > STREAK_LIFE:
		_streak_t.remove_at(0)
		_streak_p.remove_at(0)
	if _streak_p.size() >= 2:
		live = true
	if not live:
		if _trail and _trail.visible:
			_trail.visible = false
		return
	if _trail == null:
		_trail_mesh = ImmediateMesh.new()
		_trail = MeshInstance3D.new()
		_trail.mesh = _trail_mesh
		_trail.top_level = true
		_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_trail.material_override = Fx.glow_ribbon_material()
		add_child(_trail)
	_trail_col = _trail_colour()
	_trail_mesh.clear_surfaces()
	_trail.visible = true
	_trail.global_position = player.global_position + Vector3(0, 0.95, 0)
	for pts: Array in _trails:
		if pts.size() >= 2:
			_draw_crescent(pts)
	if _streak_p.size() >= 2:
		_draw_streak()


## One blade's crescent: a strip between its spokes, from 45% of the reach to just past the tip, fading with age.
func _draw_crescent(pts: Array) -> void:
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(pts.size() - 1):
		var p0: Vector3 = pts[k]
		var p1: Vector3 = pts[k + 1]
		var a0 := 1.0 - (_clock - p0.y) / TRAIL_LIFE
		var a1 := 1.0 - (_clock - p1.y) / TRAIL_LIFE
		var d0 := Vector3(-sin(p0.x), 0.0, -cos(p0.x))
		var d1 := Vector3(-sin(p1.x), 0.0, -cos(p1.x))
		var in0 := d0 * p0.z * 0.45
		var out0 := d0 * p0.z * 1.02
		var in1 := d1 * p1.z * 0.45
		var out1 := d1 * p1.z * 1.02
		var c0 := Color(_trail_col.r, _trail_col.g, _trail_col.b, 0.75 * a0 * a0)
		var c1 := Color(_trail_col.r, _trail_col.g, _trail_col.b, 0.75 * a1 * a1)
		var ci0 := Color(c0.r, c0.g, c0.b, 0.0)
		var ci1 := Color(c1.r, c1.g, c1.b, 0.0)
		_trail_mesh.surface_set_color(ci0)
		_trail_mesh.surface_add_vertex(in0)
		_trail_mesh.surface_set_color(c0)
		_trail_mesh.surface_add_vertex(out0)
		_trail_mesh.surface_set_color(c1)
		_trail_mesh.surface_add_vertex(out1)
		_trail_mesh.surface_set_color(ci0)
		_trail_mesh.surface_add_vertex(in0)
		_trail_mesh.surface_set_color(c1)
		_trail_mesh.surface_add_vertex(out1)
		_trail_mesh.surface_set_color(ci1)
		_trail_mesh.surface_add_vertex(in1)
	_trail_mesh.surface_end()


## The thrust's streak (pass 53): a flat ribbon through where the tip has been, STREAK_HALF wide, fading with age; laid
## in the trail node's space (the hero's chest).
func _draw_streak() -> void:
	var origin := _trail.global_position
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(_streak_p.size() - 1):
		var p0 := _streak_p[k] - origin
		var p1 := _streak_p[k + 1] - origin
		var along := p1 - p0
		along.y = 0.0
		if along.length_squared() < 0.000001:
			continue
		var side := Vector3(-along.z, 0.0, along.x).normalized() * STREAK_HALF
		var a0 := 1.0 - (_clock - _streak_t[k]) / STREAK_LIFE
		var a1 := 1.0 - (_clock - _streak_t[k + 1]) / STREAK_LIFE
		var c0 := Color(_trail_col.r, _trail_col.g, _trail_col.b, 0.7 * a0 * a0)
		var c1 := Color(_trail_col.r, _trail_col.g, _trail_col.b, 0.7 * a1 * a1)
		_trail_mesh.surface_set_color(c0)
		_trail_mesh.surface_add_vertex(p0 - side)
		_trail_mesh.surface_set_color(c0)
		_trail_mesh.surface_add_vertex(p0 + side)
		_trail_mesh.surface_set_color(c1)
		_trail_mesh.surface_add_vertex(p1 + side)
		_trail_mesh.surface_set_color(c0)
		_trail_mesh.surface_add_vertex(p0 - side)
		_trail_mesh.surface_set_color(c1)
		_trail_mesh.surface_add_vertex(p1 + side)
		_trail_mesh.surface_set_color(c1)
		_trail_mesh.surface_add_vertex(p1 - side)
	_trail_mesh.surface_end()


## The thrust's hit: everything along any of the `_active` blades, once. Returns whether anything was struck.
func _strike(reach: float, width: float, fan: float, swing: float) -> bool:
	var em: EnemyManager = game.enemies
	var wid := inst.def.id
	var hits := em.indices_in_radius(player.global_position, reach + 0.8)
	var dmg := stat("damage", 16.0)
	var knock := stat("knockback", 6.0)
	# the thrust half of an alternate stroke throws harder (pass 53, the Thunder Lance)
	if _combo == 2:
		knock *= _thrust("alternate_knock", ALTERNATE_KNOCK)
	var pdmg := stat("poison_damage", 0.0)
	var fdmg := stat("fire_damage", 0.0)
	var any := false
	for e in hits:
		var d: Vector3 = em.pos[e] - player.global_position
		d.y = 0.0
		for k in range(_active):
			var off: float = (float(k) - float(_active - 1) * 0.5) * fan + swing
			var bdir := _dir.rotated(Vector3.UP, off)
			var along := d.dot(bdir)
			var side := (d - bdir * along).length()
			if along > 0.0 and along <= reach + em.radius[e] and side <= width * 0.5 + em.radius[e]:
				if pdmg > 0.0:
					em.poison(e, wid, pdmg, maxi(stat_int("poison_stacks", 1), 1), stat("poison_duration", 8.0))
				if fdmg > 0.0:
					em.ignite(e, wid, fdmg, stat("fire_duration", 1.8), stat("fire_spread", 0.4))
				var killed := em.damage(e, dmg * _stunned_mult(em, e), wid, bdir, knock)
				if killed:
					inst.kills += 1
				if _hit_was_crit(em, e):
					_crit_slash(em, e, Vector3(-bdir.z, 0.0, bdir.x))
				_after_hit(em, e, killed)
				game.fx_hit(em.pos[e] + Vector3(0, 0.5, 0), inst.def)
				any = true
				break
	if any:
		sfx("hit", player.global_position)
		_tip_sparks()
	return any


## A small puff and a few sparks at every blade's point when the thrust bit (pass 53), through whatever Fx the game has.
func _tip_sparks() -> void:
	var fx = game.get("fx")
	if fx == null:
		return
	var col := _trail_colour()
	for k in range(mini(_active, _blades.size())):
		var at := _tip_of(_blades[k])
		if fx.has_method("burst"):
			fx.burst(at, col, 0.45)
		if fx.has_method("mote"):
			for q in range(3):
				var a := randf() * TAU
				fx.mote(at, Vector3(cos(a) * 1.6, 1.2 + randf(), sin(a) * 1.6), 0.25, 0.09, Color(col.r, col.g, col.b, 0.9))


# ---------------------------------------------------------------- the Sabre's looks (pass 61)

func refresh_marks() -> void:
	super.refresh_marks()
	_refresh_looks()


## params.razor (Critical Thinking), {} without it.
func _razor() -> Dictionary:
	var r = inst.params.get("razor") if inst else null
	return r if r is Dictionary else {}


## params.riposte (Riposte), {} without it.
func _riposte() -> Dictionary:
	var r = inst.params.get("riposte") if inst else null
	return r if r is Dictionary else {}


## The razor edge and the guard bar on or off with their mutations, on the blade every stroke copies and on every copy.
func _refresh_looks() -> void:
	if inst == null:
		return
	var key := JSON.stringify([_razor(), _riposte()])
	if key == _looks_key:
		return
	_looks_key = key
	var razor := not _razor().is_empty()
	var guard := not _riposte().is_empty()
	var all: Array = _blades.duplicate()
	if _proto:
		all.push_front(_proto)
	for b: Node in all:
		_show(b, "LookRazor", razor)
		_show(b, "LookGuard", guard)


func _show(blade: Node, look: String, on: bool) -> void:
	var n := blade.get_node_or_null(look) as Node3D
	if n:
		n.visible = on


## Whether the blade wears `look` ("LookRazor", "LookGuard") now (tests): on the blade every stroke copies.
func shows_look(look: String) -> bool:
	if _proto == null:
		return false
	var n := _proto.get_node_or_null(look) as Node3D
	return n != null and n.visible


## How long Riposte's flick lasts in a stroke whose retract takes `back` seconds: params.riposte.flick, at most
## FLICK_SHARE of `back`; 0 without Riposte.
func flick_time(back: float) -> float:
	var rp := _riposte()
	if rp.is_empty():
		return 0.0
	return clampf(float(rp.get("flick", 0.09)), 0.0, maxf(back, 0.0) * FLICK_SHARE)


## The flick `u` of the way through (0..1): out to 1 by FLICK_PEAK with an ease-out, back to 0 by its end, eased.
static func flick_at(u: float) -> float:
	if u <= 0.0 or u >= 1.0:
		return 0.0
	if u < FLICK_PEAK:
		var q := u / FLICK_PEAK
		return 1.0 - (1.0 - q) * (1.0 - q)
	var d := (u - FLICK_PEAK) / (1.0 - FLICK_PEAK)
	return 1.0 - d * d * (3.0 - 2.0 * d)


## While the blade flicks: its crescent runs backwards behind it (spokes, no cut) and, once, at the peak, the clang: a
## spark two thirds of the way up the blade and the sound.
func _tick_flick(fu: float, yaw0: float, a: float, reach: float, s: float, n: int) -> void:
	while _trails.size() < n:
		_trails.append([])
	for j in range(n):
		var off := _blade_off(j)
		var steps := maxi(ceili(absf(a - _edge_prev) / 0.12), 1)
		for q in range(1, steps + 1):
			(_trails[j] as Array).append(Vector3(yaw0 + off + lerpf(_edge_prev, a, float(q) / float(steps)), _clock, reach))
	if _clanged or fu < FLICK_PEAK or _blades.is_empty():
		return
	_clanged = true
	clangs += 1
	var b: Node3D = _blades[0]
	var at: Vector3 = b.global_position - b.global_transform.basis.z * 0.65
	var cy := yaw0 + a
	var back_dir := Vector3(cos(cy), 0.0, -sin(cy)) * s
	var fx = game.get("fx") if game else null
	if fx and fx.has_method("clang_spark"):
		fx.clang_spark(at, back_dir)
	var rp := _riposte()
	var snd := str(rp.get("sound", "w_iron_hit"))
	if snd != "":
		Audio.play(snd, at, float(rp.get("volume_db", 0.0)))


## Critical Thinking's streak on a crit (pass 61): a white hairline across creature `i` along `along` (the way the edge
## went), tilted up along its line; the oldest goes when SLASH_MAX are up.
func _crit_slash(em: EnemyManager, i: int, along: Vector3) -> void:
	var rz := _razor()
	if rz.is_empty() or not bool(rz.get("crit_streak", true)):
		return
	var d := Vector3(along.x, 0.0, along.z)
	d = d.normalized() if d.length_squared() > 0.0001 else Vector3(-_dir.z, 0.0, _dir.x)
	if _slashes.size() >= SLASH_MAX:
		_slashes.pop_front()
	var size := maxf(em.size[i], 0.8)
	_slashes.append({"c": em.pos[i] + Vector3(0, size * 0.55, 0), "d": (d + Vector3.UP * SLASH_TILT).normalized(), "t": _clock,
		"len": float(rz.get("streak_length", 1.6)) * size, "w": float(rz.get("streak_width", 0.05))})
	slashes += 1


## How many crit streaks are showing (tests).
func slashes_live() -> int:
	return _slashes.size()


## The streak's see-through white, drawn over everything (the lightning bolts' recipe, so nothing new compiles).
static var _slash_mat: StandardMaterial3D


static func slash_material() -> StandardMaterial3D:
	if _slash_mat == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.no_depth_test = true
		m.render_priority = 2
		_slash_mat = m
	return _slash_mat


## Every crit streak a frame on: it draws itself across in SLASH_DRAW and fades by its life; a soft gold-white halo
## round a white hairline, both thin diamonds facing the camera.
func _tick_slashes() -> void:
	var life := float(_razor().get("streak_life", SLASH_LIFE)) if not _slashes.is_empty() else SLASH_LIFE
	while not _slashes.is_empty() and _clock - float((_slashes[0] as Dictionary)["t"]) > life:
		_slashes.pop_front()
	if _slashes.is_empty():
		if _slash_mi and _slash_mi.visible:
			_slash_mi.visible = false
		return
	if _slash_mi == null:
		_slash_mesh = ImmediateMesh.new()
		_slash_mi = MeshInstance3D.new()
		_slash_mi.mesh = _slash_mesh
		_slash_mi.top_level = true
		_slash_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_slash_mi.material_override = slash_material()
		_slash_mi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
		add_child(_slash_mi)
	_slash_mi.visible = true
	_slash_mi.global_transform = Transform3D.IDENTITY
	var rz := _razor()
	var col := Color(str(rz.get("color", "#FFFFFF")))
	var glow := Color(str(rz.get("glow", "#FFE7A0")))
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	_slash_mesh.clear_surfaces()
	_slash_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for sl: Dictionary in _slashes:
		var age := _clock - float(sl["t"])
		var g := clampf(age / SLASH_DRAW, 0.0, 1.0)
		var fade := 1.0 - smoothstep(SLASH_DRAW, life, age)
		var c: Vector3 = sl["c"]
		var d: Vector3 = sl["d"]
		var ln := float(sl["len"])
		var p0 := c - d * ln * 0.5
		var p1 := p0 + d * ln * g
		var to_cam: Vector3 = (cam.global_position - c).normalized() if cam else Vector3.UP
		var side := d.cross(to_cam)
		side = side.normalized() if side.length_squared() > 0.0001 else Vector3.RIGHT
		var w := float(sl["w"])
		_diamond(p0, p1, side * w * 3.2, Color(glow.r, glow.g, glow.b, 0.45 * fade))
		_diamond(p0, p1, side * w, Color(col.r, col.g, col.b, fade))
	_slash_mesh.surface_end()


## A thin diamond from `p0` to `p1`, `half` wide at its middle, in `c`.
func _diamond(p0: Vector3, p1: Vector3, half: Vector3, c: Color) -> void:
	var m := (p0 + p1) * 0.5
	var tip := Color(c.r, c.g, c.b, c.a * 0.6)
	for v in [[p0, tip], [m + half, c], [p1, tip], [p0, tip], [p1, tip], [m - half, c]]:
		_slash_mesh.surface_set_color(v[1])
		_slash_mesh.surface_add_vertex(v[0])
