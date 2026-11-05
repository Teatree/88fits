## Pass 127 (Garry: "Remove Black Sunday's charge attack. Sunday won't be charging, he will instead be pulling Players in. So
## replace it with a new attack 'Come Here'. The Pull Area of this Attack will be marked by a wider rectangle, but have the same
## reach as the charge attack. This attack is rather quick and it results in a whole bunch of dust to spring up in that area and
## pulls everyone in it towards the Boss. It pulls harder the further away the perp is, but never quite enough to reach the boss
## himself. The pull should be visualized as a jump kind of thing."): the built-in attack `come_here` (BALANCING 69.BOSS).
##
## A row of `boss.attacks`: {"name": "come_here", "windup": 0.5, "telegraph": "rect", "length": 17, "width": 6, ...}; DEFAULTS fill
## what it leaves out (tools/level_editor/vocab.py ATTACKS mirrors the table):
##   length, width  the rectangle from his middle along his aim, metres; the mark drawn is this one (telegraph "rect").
##   pull_near, pull_far  the share of the way to him a body is pulled at his feet and at the far end of the rectangle
##                  (between them in a straight line by its distance), so the further away the harder.
##   keep           metres past his body a pull always stops short of (with his radius: BossComeHere.stop_of). A body already
##                  inside that does not move.
##   hop_time, hop_time_per, hop_height, hop_height_per  the leap: seconds and metres for a pull of nothing, and per metre pulled.
##   sound          the gust as it fires.
## It does no damage: a pull only brings the hero into what comes next. The hero leaps along a straight line he does not steer
## (Player.pull_leap: an evade does not apply, it is no hit; the Invincibility bubble and May's box hold him); a creature that can
## be thrown leaps too (EnemyManager.launch with a drift, no landing damage); a big one (an Elite, a special) only slides, as big
## ones take any throw. A leap lands on a spot worked out as it leaves, so nothing here rolls a die.
class_name BossComeHere
extends RefCounted

const DEFAULTS := {
	"length": 17.0, "width": 6.0, "pull_near": 0.2, "pull_far": 0.7, "keep": 2.0,
	"hop_time": 0.42, "hop_time_per": 0.03, "hop_height": 1.1, "hop_height_per": 0.16, "sound": "wd_gust",
}
## A big creature's slide: EnemyManager's kb fades at 6 a second, so a push of v m/s carries it about v / 6 metres.
const SLIDE_K := 6.0
## How many clouds a metre of the rectangle's length and how many across it (about 25 over his 17 x 6 m).
const CLOUD_EVERY := 2.0
const CLOUD_ROWS := 3


## A row with every default filled in.
static func config_of(atk: Dictionary) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	for k in atk.keys():
		if out.has(k):
			out[k] = atk[k]
	return out


## Whether `at` is inside the rectangle from `from` along `axis` (flat, unit length).
static func inside(at: Vector3, from: Vector3, axis: Vector3, cfg: Dictionary) -> bool:
	var d := Vector3(at.x - from.x, 0.0, at.z - from.z)
	var along := d.dot(axis)
	if along < 0.0 or along > float(cfg["length"]):
		return false
	return absf(d.dot(Vector3(-axis.z, 0.0, axis.x))) <= float(cfg["width"]) * 0.5


## Metres from his middle a pull stops: his body and `keep`.
static func stop_of(boss_radius: float, cfg: Dictionary) -> float:
	return boss_radius + float(cfg["keep"])


## How far a body `dist` metres from his middle is pulled: the share grows with its distance, and it never comes nearer than `stop`.
static func pull_of(dist: float, stop: float, cfg: Dictionary) -> float:
	if dist <= stop:
		return 0.0
	var f := clampf(dist / maxf(float(cfg["length"]), 0.01), 0.0, 1.0)
	return minf(dist * lerpf(float(cfg["pull_near"]), float(cfg["pull_far"]), f), dist - stop)


## The attack fires (EnemyManager's fire step): the dust stands up over the whole rectangle, everyone in it leaps. Returns how many
## creatures came (the hero not counted).
static func fire(em: EnemyManager, i: int, atk: Dictionary, ppos: Vector3) -> int:
	var cfg := config_of(atk)
	var from: Vector3 = em.pos[i]
	var axis := Vector3(em.charge_dir[i].x, 0.0, em.charge_dir[i].z)
	axis = axis.normalized() if axis.length_squared() > 0.0001 else Vector3(1, 0, 0)
	var stop := stop_of(em.radius[i], cfg)
	_dust(em, from, axis, cfg)
	var came := 0
	var reach := Vector2(float(cfg["length"]), float(cfg["width"]) * 0.5).length()
	for j in em.indices_in_radius(from, reach):
		if j == i or not inside(em.pos[j], from, axis, cfg):
			continue
		if _pull_creature(em, j, from, stop, cfg):
			came += 1
	var pl = em.player
	if pl != null and is_instance_valid(pl) and inside(ppos, from, axis, cfg) and pl.has_method("pull_leap"):
		var to := Vector3(from.x - ppos.x, 0.0, from.z - ppos.z)
		var dist := to.length()
		var pull := pull_of(dist, stop, cfg)
		if pull > 0.0:
			pl.pull_leap(to / dist, pull, float(cfg["hop_height"]) + float(cfg["hop_height_per"]) * pull,
				float(cfg["hop_time"]) + float(cfg["hop_time_per"]) * pull)
	var sound := str(cfg["sound"])
	if sound != "":
		Audio.play(sound, from)
	if em.game != null and em.game.get("camera"):
		em.game.camera.shake(0.5)
	return came


## One creature's leap (or a big one's slide): false when it did not move.
static func _pull_creature(em: EnemyManager, j: int, from: Vector3, stop: float, cfg: Dictionary) -> bool:
	if em.alive[j] == 0 or em.state[j] == EnemyManager.STATE_DYING or em.hidden[j] == 1 or em.held[j] == 1:
		return false
	var to := Vector3(from.x - em.pos[j].x, 0.0, from.z - em.pos[j].z)
	var dist := to.length()
	var pull := pull_of(dist, stop, cfg)
	if pull <= 0.0:
		return false
	var n := to / dist
	if not em.can_launch(j):
		if em.is_big_game(j) and em.lift_t[j] <= 0.0:
			em.kb[j] = n * pull * SLIDE_K
			return true
		return false
	var secs := float(cfg["hop_time"]) + float(cfg["hop_time_per"]) * pull
	if not em.launch(j, float(cfg["hop_height"]) + float(cfg["hop_height_per"]) * pull, secs, 0.0, "", ""):
		return false
	(em._launched[j] as Dictionary)["drift"] = n * (pull / secs)
	return true


## The dust: clouds all over the rectangle at once, each leaning towards him (a look: the global dice).
static func _dust(em: EnemyManager, from: Vector3, axis: Vector3, cfg: Dictionary) -> void:
	var fx = em.game.get("fx") if em.game != null else null
	if fx == null or not fx.has_method("pull_dust"):
		return
	var side := Vector3(-axis.z, 0.0, axis.x)
	var length := float(cfg["length"])
	var width := float(cfg["width"])
	var rows := maxi(int(length / CLOUD_EVERY), 1)
	for r in rows:
		for c in CLOUD_ROWS:
			var along := (float(r) + 0.5 + randf_range(-0.35, 0.35)) * length / float(rows)
			var across := (float(c) - float(CLOUD_ROWS - 1) * 0.5) * width / float(CLOUD_ROWS) + randf_range(-0.5, 0.5)
			var at: Vector3 = from + axis * along + side * across
			at.y = em._height(at.x, at.z)
			fx.pull_dust(at, -axis, 1.0 + along / length)
