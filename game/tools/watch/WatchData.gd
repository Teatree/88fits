## The Watch's numbers (pass 80, lane WATCH): the run recorder's rows (RunAnalytics.samples, one a second of play)
## read as they come into flat series for the panel and its charts, the derived ones the Sim tab uses (sim_batch.py
## _derive_difficulty: real DPS over DPS_WINDOW s, Danger = HP lost a second as % of max HP over DPS_WINDOW s, Keeping
## up = the crowd's HP less the boss's over that DPS, in seconds), the bot's decisions with the real DPS change after
## each (AFTER_S s after against BEFORE_S s before; filled once the run has played that far), the items' arrivals and
## the falls from the recorder's events, and the decision log as CSV. No engine access beyond plain data: tested
## headless (tests/pass80_watch_test.gd). Tools only.
extends RefCounted

## Pass 82 (lane STATS' rule, one definition for the Sim, the dashboard and the Watch): sim_run.gd pickup_kind(e) names
## what an event picked up: "chests", "powerups", "totems" or "".
const SIM := preload("res://tools/sim_run.gd")
const PICKUP_KEYS := ["chests", "powerups", "totems"]
const DPS_WINDOW := 5
const AFTER_S := 30.0
const BEFORE_S := 30.0
const THREAT_S := 10
## the recorder's event kinds that bring an item (RunAnalytics.ITEM_KINDS)
const ITEM_KINDS := ["weapon", "passive", "mutation", "perk", "evolution", "passive_evolution"]
const CSV_COLUMNS := ["t", "clock", "level", "kind", "taken", "taken_name", "reason", "offered", "est_dps_before",
	"real_dps_before", "real_dps_after_30s", "real_change_pct"]

var t := PackedFloat32Array()
var clock := PackedFloat32Array()
var stage := PackedInt32Array()
var hp := PackedFloat32Array()
var hp_max := PackedFloat32Array()
var dps := PackedFloat32Array()
var dps5 := PackedFloat32Array()
var est := PackedFloat32Array()
## pass 83 (lane SCALE): the hero's power level each row (the row's `power`, HeroPower; 0 before pass 83)
var power := PackedFloat32Array()
var crowd := PackedFloat32Array()
var boss := PackedFloat32Array()
var danger := PackedFloat32Array()
## seconds; -1 where the DPS is under 1 (no ratio)
var keep_up := PackedFloat32Array()
var level := PackedInt32Array()
var xp_frac := PackedFloat32Array()
var kills := PackedInt32Array()
var gold := PackedInt32Array()
var near3 := PackedInt32Array()
var near6 := PackedInt32Array()
var alive := PackedInt32Array()
## each row's damage by source, HP lost by creature, hits by creature ({id: n}, only what is not zero)
var dmg_rows: Array = []
var took_rows: Array = []
var hits_rows: Array = []
## the run's damage by source so far
var dmg_total: Dictionary = {}
## the items as they came: {t, clock, kind, id, level, via}
var arrivals: Array = []
## the falls: {t, clock, killer, hit, last: [the last hits, newest first]}
var falls: Array = []
## the bot's decisions as it logged them, each with the Watch's fill: real_before, real_after (-1 = n/a), real_change
## (NAN = n/a)
var decisions: Array = []
## pass 82: the play seconds of each pickup by kind (lane STATS' rule: SIM.pickup_kind), oldest first; the specials that
## came (the recorder's "special"), fell ("special_kill") and the chests their deaths dropped
var pickups: Dictionary = {"chests": [], "powerups": [], "totems": []}
var specials_came := 0
var specials_killed := 0
var special_chests := 0

var _rows_read := 0
var _events_read := 0
var _lost5 := PackedFloat32Array()


## Reads the rows not read yet; returns how many were new.
func read_rows(rows: Array) -> int:
	var n0 := _rows_read
	while _rows_read < rows.size():
		var r = rows[_rows_read]
		_rows_read += 1
		if r is Dictionary:
			_add_row(r)
	return _rows_read - n0


func _add_row(r: Dictionary) -> void:
	t.append(float(r.get("t", 0.0)))
	clock.append(float(r.get("clock", 0.0)))
	stage.append(int(r.get("stage", 1)))
	var mx := float(r.get("hp_max", 0.0))
	hp.append(float(r.get("hp", 0.0)))
	hp_max.append(mx)
	var dm: Dictionary = r.get("dmg") if r.get("dmg") is Dictionary else {}
	var second := 0.0
	for k in dm:
		second += float(dm[k])
		dmg_total[k] = float(dmg_total.get(k, 0.0)) + float(dm[k])
	dps.append(second)
	var d5 := tail_mean(dps, DPS_WINDOW)
	dps5.append(d5)
	est.append(float(r.get("est_total", 0.0)))
	power.append(float(r.get("power", 0.0)))
	var press := float(r.get("press_hp", 0.0))
	var bh := float(r.get("boss_now", 0.0))
	crowd.append(press)
	boss.append(bh)
	var tk: Dictionary = r.get("took") if r.get("took") is Dictionary else {}
	var lost := 0.0
	for k in tk:
		lost += float(tk[k])
	_lost5.append(100.0 * lost / mx if mx > 0.0 else 0.0)
	danger.append(tail_mean(_lost5, DPS_WINDOW))
	keep_up.append(keep_up_s(press, bh, d5))
	level.append(int(r.get("level", 1)))
	var xn := float(r.get("xp_next", 0.0))
	xp_frac.append(clampf(float(r.get("xp", 0.0)) / xn, 0.0, 1.0) if xn > 0.0 else 0.0)
	kills.append(int(r.get("kills", 0)))
	gold.append(int(r.get("gold", 0)))
	near3.append(int(r.get("near3", 0)))
	near6.append(int(r.get("near6", 0)))
	alive.append(int(r.get("alive", 0)))
	dmg_rows.append(dm)
	took_rows.append(tk)
	hits_rows.append(r.get("hits_by") if r.get("hits_by") is Dictionary else {})


## Reads the recorder's events not read yet: the items' arrivals and the falls (`last_hits`: the hero's damage log as
## it stands now, newest last, for a fall read this frame). Returns how many were new.
func read_events(events: Array, last_hits: Array = []) -> int:
	var n0 := _events_read
	while _events_read < events.size():
		var e = events[_events_read]
		_events_read += 1
		if not (e is Dictionary):
			continue
		var kind := str(e.get("kind", ""))
		if kind in ITEM_KINDS:
			arrivals.append({"t": float(e.get("t", 0.0)), "clock": float(e.get("clock", 0.0)), "kind": kind,
				"id": str(e.get("id", "")), "level": int(e.get("level", 0)), "via": str(e.get("via", "")),
				"line": bool(e.get("line", false))})
		elif kind == "special":
			specials_came += 1
		elif kind == "special_kill":
			specials_killed += 1
			if bool(e.get("chest", false)):
				special_chests += 1
		elif kind == "death":
			var last: Array = []
			for i in range(last_hits.size() - 1, maxi(last_hits.size() - 6, 0) - 1, -1):
				last.append(last_hits[i])
			falls.append({"t": float(e.get("t", 0.0)), "clock": float(e.get("clock", 0.0)), "killer": str(e.get("id", "")),
				"hit": str(e.get("hit", "")), "last": last})
		# pass 82: a chest, a power-up or a totem gift (the same event may be nothing else above: chest, pickup, totem)
		var pk := str(SIM.pickup_kind(e))
		if pk != "":
			(pickups[pk] as Array).append(float(e.get("t", 0.0)))
	return _events_read - n0


## Pass 82: the run's totals so far {chests, powerups, totems}.
func pickup_totals() -> Dictionary:
	return {"chests": (pickups["chests"] as Array).size(), "powerups": (pickups["powerups"] as Array).size(),
		"totems": (pickups["totems"] as Array).size()}


## A decision entry from the bot (INTERFACES.md), kept with the Watch's fill fields (real_before / real_after: -1 until
## known or when no row fell in the window; real_change: NAN until known or when it has no meaning).
func add_decision(entry: Dictionary) -> Dictionary:
	var d := entry.duplicate(true)
	d["real_before"] = -1.0
	d["real_after"] = -1.0
	d["real_change"] = NAN
	d["filled"] = false
	decisions.append(d)
	return d


## The real DPS around each decision not filled yet (every kind but a walking goal): the mean of the rows in the AFTER_S
## s after it against the BEFORE_S s before it, once the run has played AFTER_S s past it (`now` play seconds; `final`:
## the run is over, fill what there is). Returns how many were filled.
func fill_decisions(now: float, final: bool = false) -> int:
	var n := 0
	for d in decisions:
		if bool(d.get("filled", false)):
			continue
		# a walking goal (pass 82: or a hunt's end) changes no build: no DPS change of its own
		if str(d.get("kind", "")) in ["goal", "special"]:
			d["filled"] = true
			continue
		var at := float(d.get("t", 0.0))
		if now < at + AFTER_S and not final:
			continue
		d["real_before"] = mean_between(t, dps, at - BEFORE_S, at)
		d["real_after"] = mean_between(t, dps, at, at + AFTER_S)
		d["real_change"] = change_pct(float(d["real_before"]), float(d["real_after"]))
		d["filled"] = true
		n += 1
	return n


## What hurt the hero in the last `secs` rows: [{id, lost, hits}] by HP lost, most first.
func threat(secs: int = THREAT_S) -> Array:
	var lost := {}
	var hits := {}
	for i in range(maxi(took_rows.size() - secs, 0), took_rows.size()):
		var tk: Dictionary = took_rows[i]
		for k in tk:
			lost[k] = float(lost.get(k, 0.0)) + float(tk[k])
		var hb: Dictionary = hits_rows[i]
		for k in hb:
			hits[k] = int(hits.get(k, 0)) + int(hb[k])
	var out: Array = []
	for k in lost:
		out.append({"id": str(k), "lost": float(lost[k]), "hits": int(hits.get(k, 0))})
	for k in hits:
		if not lost.has(k):
			out.append({"id": str(k), "lost": 0.0, "hits": int(hits[k])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["lost"]) > float(b["lost"]) if float(a["lost"]) != float(b["lost"]) else int(a["hits"]) > int(b["hits"]))
	return out


## Each source's share of the damage of the rows from `i0` to `i1` (inclusive), the `top` biggest by name and the rest
## as "other": [[id, share 0..1], ...] biggest first.
func shares(i0: int, i1: int, top: int = 6) -> Array:
	var sums := {}
	var total := 0.0
	for i in range(maxi(i0, 0), mini(i1 + 1, dmg_rows.size())):
		var dm: Dictionary = dmg_rows[i]
		for k in dm:
			sums[k] = float(sums.get(k, 0.0)) + float(dm[k])
			total += float(dm[k])
	return ranked_shares(sums, total, top)


static func ranked_shares(sums: Dictionary, total: float, top: int) -> Array:
	var ids := sums.keys()
	ids.sort_custom(func(a, b) -> bool: return float(sums[a]) > float(sums[b]) if float(sums[a]) != float(sums[b]) else str(a) < str(b))
	var out: Array = []
	var other := 0.0
	for i in range(ids.size()):
		var s := float(sums[ids[i]]) / total if total > 0.0 else 0.0
		# a source under half a percent is folded into "other"
		if i < top and s >= 0.005:
			out.append([str(ids[i]), s])
		else:
			other += s
	if other > 0.0:
		out.append(["other", other])
	return out


func size() -> int:
	return t.size()


# ---------------------------------------------------------------- pure arithmetic (tested)

## The mean of the newest `n` values of `a` (fewer at the start; 0 when empty).
static func tail_mean(a: PackedFloat32Array, n: int) -> float:
	var c := mini(n, a.size())
	if c <= 0:
		return 0.0
	var s := 0.0
	for i in range(a.size() - c, a.size()):
		s += a[i]
	return s / float(c)


## Keeping up (the Sim tab's): seconds of `dps` to clear the crowd's HP `crowd_hp` less the boss's `boss_hp`; -1 under
## 1 DPS.
static func keep_up_s(crowd_hp: float, boss_hp: float, dps_now: float) -> float:
	if dps_now < 1.0:
		return -1.0
	return maxf(crowd_hp - boss_hp, 0.0) / dps_now


## The mean of `vs` over the rows whose time `ts` lies in (a, b]; -1 when none does.
static func mean_between(ts: PackedFloat32Array, vs: PackedFloat32Array, a: float, b: float) -> float:
	var s := 0.0
	var n := 0
	for i in range(mini(ts.size(), vs.size())):
		var x := ts[i]
		if x > a + 0.0001 and x <= b + 0.0001:
			s += vs[i]
			n += 1
	return s / float(n) if n > 0 else -1.0


## The change from `before` to `after` in percent; NAN when either is missing (negative) or `before` is under 1 DPS
## (a percentage of nothing).
static func change_pct(before: float, after: float) -> float:
	if before < 1.0 or after < 0.0:
		return NAN
	return 100.0 * (after - before) / before


## A chart's top: the smallest of NICE x 10^k that is at least `v` (each a quarter of which reads well on the four grid
## lines: 1200 -> 300, 600, 900); 1 for nothing.
const NICE := [1.0, 1.2, 1.6, 2.0, 2.4, 3.2, 4.0, 6.0, 8.0, 10.0]


static func nice_max(v: float) -> float:
	if not (v > 0.0) or is_inf(v):
		return 1.0
	var k := floorf(log(v) / log(10.0))
	var base := pow(10.0, k)
	for m in NICE:
		if float(m) * base >= v * 0.9999:
			return float(m) * base
	return 10.0 * base


## Points (x = time, y = value) of `vs` over the times `ts` within [x0, x1], at most `max_points` of them: past that,
## each bucket of times is its mean. NAN values are left out (a gap is bridged).
static func bucket(ts: PackedFloat32Array, vs: PackedFloat32Array, x0: float, x1: float, max_points: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := mini(ts.size(), vs.size())
	if n == 0 or x1 <= x0:
		return out
	var idx0 := 0
	while idx0 < n and ts[idx0] < x0:
		idx0 += 1
	var count := n - idx0
	if count <= 0:
		return out
	if count <= max_points:
		for i in range(idx0, n):
			if not is_nan(vs[i]):
				out.append(Vector2(ts[i], vs[i]))
		return out
	var per := float(count) / float(maxi(max_points, 1))
	var b := 0
	while b < max_points:
		var i0 := idx0 + int(floor(float(b) * per))
		var i1 := mini(idx0 + int(floor(float(b + 1) * per)), n)
		var sx := 0.0
		var sy := 0.0
		var c := 0
		for i in range(i0, i1):
			if is_nan(vs[i]):
				continue
			sx += ts[i]
			sy += vs[i]
			c += 1
		if c > 0:
			out.append(Vector2(sx / float(c), sy / float(c)))
		b += 1
	return out


## "m:ss" of `s` seconds ("h:mm:ss" past an hour).
static func mmss(s: float) -> String:
	var n := int(maxf(s, 0.0))
	if n >= 3600:
		return "%d:%02d:%02d" % [n / 3600, (n / 60) % 60, n % 60]
	return "%d:%02d" % [n / 60, n % 60]


# ---------------------------------------------------------------- the decision log as CSV

## One CSV field: quoted when it holds a comma, a quote or a line break (quotes doubled).
static func csv_field(v) -> String:
	var s := str(v) if v != null else ""
	if s.contains(",") or s.contains("\"") or s.contains("\n") or s.contains("\r"):
		return "\"" + s.replace("\"", "\"\"") + "\""
	return s


static func csv_row(fields: Array) -> String:
	var parts := PackedStringArray()
	for f in fields:
		parts.append(csv_field(f))
	return ",".join(parts)


## The decision log as CSV (CSV_COLUMNS), one line a decision, `names` {id: name} for the taken one's name.
func decisions_csv(names: Dictionary = {}) -> String:
	var lines := PackedStringArray([csv_row(CSV_COLUMNS)])
	for d in decisions:
		var offered := PackedStringArray()
		for o in d.get("offered", []):
			if o is Dictionary:
				offered.append("%s=%s" % [str(o.get("id", "")), _num(o.get("score", ""))])
		var taken := str(d.get("taken", ""))
		lines.append(csv_row([_num(d.get("t", 0.0)), _num(d.get("clock", 0.0)), int(d.get("level", 0)), str(d.get("kind", "")),
			taken, str(names.get(taken, "")), str(d.get("reason", "")), " | ".join(offered), _num(d.get("dps_before", "")),
			_pos(d.get("real_before", -1.0)), _pos(d.get("real_after", -1.0)), _num(d.get("real_change", NAN))]))
	return "\n".join(lines) + "\n"


## A number as the CSV writes it: one decimal, "" for NAN; anything else as text.
static func _num(v) -> String:
	if v is float or v is int:
		var f := float(v)
		if is_nan(f) or is_inf(f):
			return ""
		return str(snappedf(f, 0.1))
	return str(v) if v != null else ""


## A DPS the CSV writes: "" when it is missing (negative).
static func _pos(v) -> String:
	if (v is float or v is int) and float(v) < 0.0:
		return ""
	return _num(v)
