## Pass 136 (lane HOMING; Garry: "Zap Beam and Sun Scepter: Should leave a mark on the floor whenever they attack"): the
## burns an aimed Zap Beam / Storm Cloud bolt and an aimed Sun Scepter / Zenith pillar leave on the sand, and the R7 marks
## of the Rocket Pod (where each rocket of a volley is going). All of them are held marks in the Telegraphs pools (draped
## on the terrain by ground_mark.gdshader, one draw call a pool, nothing of their own), timed and faded here.
##   zap: a dark burnt star (a lobed scorch blob) under a faint blue glow that cools in ZAP_GLOW s; it lies ZAP_HOLD s and
##        fades over ZAP_FADE.
##   sun: a gold-white ring burnt into the sand that cools to a dark ring in SUN_GLOW s; it lies SUN_HOLD s and fades over
##        SUN_FADE.
## At most CAP of each kind lie at once (the oldest goes first). Looks only: no rule reads them, no dice.
class_name StrikeMarks
extends Node

const GROUP := "strike_marks"
const CAP := 24
const ZAP_R := 0.75
const ZAP_GLOW := 0.9
const ZAP_HOLD := 1.6
const ZAP_FADE := 2.2
const ZAP_BURN_IN := Color(0.05, 0.05, 0.07, 0.82)
const ZAP_BURN_OUT := Color(0.1, 0.1, 0.14, 0.0)
const ZAP_GLOW_COL := Color(0.45, 0.78, 1.0, 0.5)
const SUN_GLOW := 1.3
const SUN_HOLD := 1.8
const SUN_FADE := 2.4
const SUN_HOT := Color(1.0, 0.9, 0.58, 0.85)
const SUN_DARK := Color(0.17, 0.09, 0.04, 0.6)
## a rocket's mark (R7): an outer ring and a small filled dot, the pod's colour (params.aim.mark_color)
const ROCKET_R := 0.7
const ROCKET_DOT := 0.2
const ROCKET_ALPHA := 0.55
const ROCKET_COL := Color(1.0, 0.55, 0.18)

var game: Node
## {kind, t, burn (id), glow (id), glow_t, hold, fade, a_burn, a_glow}
var _marks: Array = []
## marks laid in all (tests)
var laid := 0


static func ensure(p_game: Node) -> StrikeMarks:
	var f := of(p_game)
	if f == null and p_game != null:
		f = StrikeMarks.new()
		f.game = p_game
		f.name = "StrikeMarks"
		f.add_to_group(GROUP)
		p_game.add_child(f)
	return f


static func of(p_game: Node) -> StrikeMarks:
	if p_game == null or not p_game.is_inside_tree():
		return null
	for n in p_game.get_tree().get_nodes_in_group(GROUP):
		if n is StrikeMarks and not (n as Node).is_queued_for_deletion() and (n as StrikeMarks).game == p_game:
			return n
	return null


## The zap's burn at `at` (on the sand).
static func zap(p_game: Node, at: Vector3) -> void:
	var f := ensure(p_game)
	if f:
		f._add("zap", at, ZAP_R)


## The sun's burnt ring of radius `r` at `at`.
static func sun(p_game: Node, at: Vector3, r: float) -> void:
	var f := ensure(p_game)
	if f:
		f._add("sun", at, r)


## The aim wedge's pulse (lane GUNS' AimWedge.pulse(), when that class is there; a no-op without it).
static func wedge_pulse() -> void:
	const P := "res://core/systems/AimWedge.gd"
	if not ResourceLoader.exists(P):
		return
	var s = load(P)
	if s != null and s.has_method("pulse"):
		s.pulse()


## How many marks of `kind` lie now ("" = all; tests).
func count(kind: String = "") -> int:
	var n := 0
	for m: Dictionary in _marks:
		if kind == "" or str(m["kind"]) == kind:
			n += 1
	return n


func _tg() -> Telegraphs:
	var t = game.get("telegraphs") if game else null
	return t as Telegraphs if t is Telegraphs else null


func _ground(p: Vector3) -> Vector3:
	var map = game.get("map") if game else null
	if map != null and map.has_method("height_at"):
		return Vector3(p.x, map.height_at(p.x, p.z), p.z)
	return p


func _add(kind: String, at: Vector3, r: float) -> void:
	var tg := _tg()
	if tg == null:
		return
	# the cap: the oldest of the kind goes
	var same: Array = []
	for m: Dictionary in _marks:
		if str(m["kind"]) == kind:
			same.append(m)
	while same.size() >= CAP:
		var old: Dictionary = same.pop_front()
		_drop(old)
		_marks.erase(old)
	var g := _ground(at)
	var m := {"kind": kind, "t": 0.0}
	if kind == "zap":
		# the burn first (under), then the glow over it; a lobed blob reads as a burnt star
		m["burn"] = tg.hold_blob(g, r, randf(), ZAP_BURN_IN, ZAP_BURN_OUT, Telegraphs.PRIO_SCORCH)
		m["glow"] = tg.hold_disc(g, r * 0.7, ZAP_GLOW_COL)
		m["glow_t"] = ZAP_GLOW
		m["hold"] = ZAP_HOLD
		m["fade"] = ZAP_FADE
		m["a_burn"] = 1.0
		m["a_glow"] = ZAP_GLOW_COL.a
	else:
		var rr := maxf(r, 0.5)
		m["burn"] = tg.hold_ring(g, rr, SUN_DARK)
		m["glow"] = tg.hold_ring(g, rr, SUN_HOT)
		m["glow_t"] = SUN_GLOW
		m["hold"] = SUN_HOLD
		m["fade"] = SUN_FADE
		m["a_burn"] = SUN_DARK.a
		m["a_glow"] = SUN_HOT.a
		# the dark ring comes in as the hot one cools
		tg.set_alpha(int(m["burn"]), 0.0)
	_marks.append(m)
	laid += 1


func _drop(m: Dictionary) -> void:
	var tg := _tg()
	if tg == null:
		return
	for k: String in ["burn", "glow"]:
		if int(m.get(k, -1)) >= 0:
			tg.release(int(m[k]))
			m[k] = -1


func _process(delta: float) -> void:
	delta = Lockstep.dt(delta)
	if _marks.is_empty():
		return
	var tg := _tg()
	if tg == null:
		_marks.clear()
		return
	var keep: Array = []
	for m: Dictionary in _marks:
		var t: float = float(m["t"]) + delta
		m["t"] = t
		var hold: float = m["hold"]
		var fade: float = m["fade"]
		if t >= hold + fade:
			_drop(m)
			continue
		var gt: float = m["glow_t"]
		var cool: float = clampf(t / maxf(gt, 0.01), 0.0, 1.0)
		if int(m["glow"]) >= 0:
			if cool >= 1.0:
				tg.release(int(m["glow"]))
				m["glow"] = -1
			else:
				tg.set_alpha(int(m["glow"]), float(m["a_glow"]) * (1.0 - cool) * (1.0 - cool))
		var out: float = 1.0 - clampf((t - hold) / maxf(fade, 0.01), 0.0, 1.0)
		var a_in: float = cool if str(m["kind"]) == "sun" else 1.0
		tg.set_alpha(int(m["burn"]), float(m["a_burn"]) * a_in * out)
		keep.append(m)
	_marks = keep


func _exit_tree() -> void:
	for m: Dictionary in _marks:
		_drop(m)
	_marks.clear()
