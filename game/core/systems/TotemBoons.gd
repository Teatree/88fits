## The Totem Pole's gifts (pass 73, Garry: "When activated a menu pops up offering Players a choice between 3 small stats
## improvements for that run. Each upgrade is titled somethings like one of those native American words for animals ...
## the size of the stat increase ranges quite a bit, with more common stats being more common than the others ... The
## stat increases shouldn't be big, but not nothing").
## The pool is data: content/structures/totem_pole's `params.boons`, one entry per carved spirit {id, name (its word,
## "Le-loo"), animal ("the Wolf"), stat, op (add | mul), tiers (pass 138: its five amounts, Common .. Legendary), weight}.
## An offer draws `params.choices` entries by weight without putting one back and never two of one stat, and rolls each
## one's rarity tier (pass 138, `params.rarity`: see TIERS). A boon taken stays on the hero for the whole run (Run.totem_boons, a source of its own on
## the sheet: "Totem: Le-loo").
class_name TotemBoons
extends RefCounted

## The choices an offer holds when the structure does not say (`params.choices`).
const CHOICES := 3
## The row of the sheet's source of a taken boon: "Totem: <its word>" (pass 137: content/strings/en.json).
const SOURCE_KEY := "gen.structure.totem.source"

## Pass 138 (lane TOTEM; Garry: "Let's make it so there are 5 rarities now (Common, Uncommon, Rare, Epic, Legendary) ...
## Legendary is a bit stronger than the strongest right now, Common is a bit weaker than the weakest right now. The rarity
## of the different rarities is as you'd expect: Legendary the rarest, Common most common. But a couple of rules: offered
## stat increases are the same [rarity] more rarely (but it still happens sometimes); the more totems Player claims the
## better the rarity chances"). A gift's rarity is its tier, 1 (Common) .. 5 (Legendary), and the tier IS its amount:
## every pool entry names its five amounts (`tiers` {common, uncommon, rare, epic, legendary}, or a list of five); an
## older entry with only `min` and `max` reads as TIER_FROM_RANGE of them. Each gift of an offer rolls its tier from the
## pole's `params.rarity.weights` row for the totems taken before this one (the last row for any later one), a tier
## already in the offer weighing `same_tier` (0.3) as much again for each copy; the stat rule (never two of one stat)
## stays. The rolled boon carries `tier` and `quality` (both 1..5), `rarity` (its id), and `min` / `max` (the Common
## and Legendary amounts: the ladder's ends).
const TIERS := ["common", "uncommon", "rare", "epic", "legendary"]
## An entry without `tiers`: its five amounts from its old range (Common 0.75 x min, Uncommon min, Rare the middle, Epic
## max, Legendary 1.3 x max), each snapped to `step` when that keeps it strictly between its neighbours.
const TIER_FROM_RANGE := [0.75, 1.0, 0.5, 1.0, 1.3]
## The rarity odds when a pole names none (`params.rarity`): content/structures/totem_pole's own table.
const DEFAULT_WEIGHTS := [[42, 32, 18, 8, 0], [38, 32, 20, 10, 0], [34, 32, 22, 11, 1], [31, 31, 23, 13, 2],
	[28, 30, 24, 15, 3], [25, 29, 25, 17, 4], [22, 28, 26, 19, 5], [19, 27, 27, 21, 6], [16, 26, 28, 23, 7],
	[14, 25, 28, 25, 8], [12, 24, 28, 27, 9], [11, 23, 28, 28, 10]]
const DEFAULT_SAME_TIER := 0.3


## The well-formed entries of a structure's pool (a stat, a positive weight, five tier amounts or numbers for min and
## max), in its order.
static func pool_of(def: StructureDef) -> Array:
	var out: Array = []
	if def == null:
		return out
	var raw = def.params.get("boons", [])
	if not raw is Array:
		return out
	for e in raw:
		if not e is Dictionary:
			continue
		var d := e as Dictionary
		if str(d.get("stat", "")) == "" or float(d.get("weight", 1.0)) <= 0.0:
			continue
		if not (d.has("tiers") or (d.has("min") and d.has("max"))):
			continue
		out.append(d)
	return out


## A pool entry's five amounts, Common .. Legendary: its `tiers` (by name, or a list of five), else from its old range
## (TIER_FROM_RANGE).
static func tier_amounts(e: Dictionary) -> Array:
	var t = e.get("tiers", null)
	if t is Dictionary:
		var out: Array = []
		var last := 0.0
		for k in range(TIERS.size()):
			last = float((t as Dictionary).get(TIERS[k], last))
			out.append(last)
		return out
	if t is Array and (t as Array).size() >= TIERS.size():
		var out2: Array = []
		for k in range(TIERS.size()):
			out2.append(float((t as Array)[k]))
		return out2
	var lo := float(e.get("min", 0.0))
	var hi := float(e.get("max", lo))
	var step := float(e.get("step", 0.0))
	var raw: Array = [lo * TIER_FROM_RANGE[0], lo * TIER_FROM_RANGE[1], lerpf(lo, hi, TIER_FROM_RANGE[2]),
		hi * TIER_FROM_RANGE[3], hi * TIER_FROM_RANGE[4]]
	var out3: Array = []
	for k in range(raw.size()):
		var v := float(raw[k])
		if step > 0.0:
			var s := snappedf(v, step)
			# a snap that would meet the tier below or the one above keeps the exact amount
			var above_ok := out3.is_empty() or absf(s) > absf(float(out3[out3.size() - 1])) + 0.000001
			var below_ok := k == raw.size() - 1 or absf(s) < absf(float(raw[k + 1])) - 0.000001
			if above_ok and below_ok:
				v = s
		out3.append(v)
	return out3


## The rarity odds of a pole (`params.rarity.weights`: one row a claim count, five weights a row) and its same-tier
## factor.
static func rarity_weights(def: StructureDef) -> Array:
	var r = def.params.get("rarity", {}) if def != null else {}
	var w = (r as Dictionary).get("weights", []) if r is Dictionary else []
	return w if w is Array and not (w as Array).is_empty() else DEFAULT_WEIGHTS


static func same_tier_of(def: StructureDef) -> float:
	var r = def.params.get("rarity", {}) if def != null else {}
	return float((r as Dictionary).get("same_tier", DEFAULT_SAME_TIER)) if r is Dictionary else DEFAULT_SAME_TIER


## The five weights for a gift when `claimed` totems were taken before this one (the table's last row past its end).
static func weights_for(table: Array, claimed: int) -> Array:
	var t := table if not table.is_empty() else DEFAULT_WEIGHTS
	var row = t[clampi(claimed, 0, t.size() - 1)]
	var out: Array = []
	for k in range(TIERS.size()):
		out.append(maxf(float(row[k]) if row is Array and k < (row as Array).size() else 0.0, 0.0))
	return out


## One gift's tier, 0 (Common) .. 4 (Legendary): drawn from `weights`, a tier already in `have` (this offer's tiers so
## far, 0-based) weighing `same` as much again for every copy of it. Common when every weight is 0. One draw from `r`.
static func roll_tier(weights: Array, have: Array, same: float, r: RandomNumberGenerator) -> int:
	var w: Array = []
	var total := 0.0
	for k in range(TIERS.size()):
		var v := float(weights[k]) if k < weights.size() else 0.0
		v *= pow(maxf(same, 0.0), have.count(k))
		w.append(v)
		total += v
	var x := r.randf() * total
	if total <= 0.0:
		return 0
	for k in range(w.size()):
		x -= float(w[k])
		if x <= 0.0 and float(w[k]) > 0.0:
			return k
	for k in range(w.size() - 1, -1, -1):
		if float(w[k]) > 0.0:
			return k
	return 0


## An offer of `n` boons from the structure's pool (its `params.choices` when `n` is 0 or less): drawn by weight, one
## entry at most once, one stat at most once, each rolled (roll) at a tier drawn from the pole's rarity odds for
## `claimed` totems taken before this one. Fewer when the pool runs out. Two draws a gift from `rng`: the entry, the tier.
static func offer(def: StructureDef, rng: RandomNumberGenerator = null, n: int = 0, claimed: int = 0) -> Array:
	var r := rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.randomize()
	var want: int = n
	if want <= 0:
		want = int(def.params.get("choices", CHOICES)) if def != null else CHOICES
	var left: Array = pool_of(def)
	var weights := weights_for(rarity_weights(def), claimed)
	var same := same_tier_of(def)
	var have: Array = []
	var out: Array = []
	while out.size() < want and not left.is_empty():
		var pick := _weighted(left, r)
		var stat := str(pick.get("stat", ""))
		left = left.filter(func(e: Dictionary) -> bool: return e != pick and str(e.get("stat", "")) != stat)
		var tier := roll_tier(weights, have, same, r)
		have.append(tier)
		out.append(roll(pick, r, tier + 1))
	return out


static func _weighted(entries: Array, r: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	for e: Dictionary in entries:
		total += maxf(float(e.get("weight", 1.0)), 0.0)
	var x := r.randf() * total
	for e: Dictionary in entries:
		x -= maxf(float(e.get("weight", 1.0)), 0.0)
		if x <= 0.0:
			return e
	return entries[entries.size() - 1]


## One boon from a pool entry at `tier` (1 Common .. 5 Legendary): the entry's words and stat with `value` its amount
## at that tier, `tier` and `quality` the tier, `rarity` its id, `min` / `max` the Common and Legendary amounts. A tier
## of 0 or less is drawn from DEFAULT_WEIGHTS' first row with `r` (one draw); a given tier draws nothing.
static func roll(e: Dictionary, r: RandomNumberGenerator, tier: int = 0) -> Dictionary:
	var t := tier
	if t <= 0:
		t = roll_tier(weights_for(DEFAULT_WEIGHTS, 0), [], 1.0, r) + 1
	t = clampi(t, 1, TIERS.size())
	var amounts := tier_amounts(e)
	var v := float(amounts[t - 1])
	var out := {"id": str(e.get("id", e.get("stat", ""))), "name": str(e.get("name", "")), "animal": str(e.get("animal", "")),
		"stat": str(e.get("stat", "")), "op": str(e.get("op", "add")), "value": v,
		"min": float(amounts[0]), "max": float(amounts[TIERS.size() - 1]),
		"tier": t, "quality": t, "rarity": str(TIERS[t - 1])}
	# pass 82 (lane TOTEM): a pool entry's own icon path rides along (icon_of); without one the spirit's slot is used
	if str(e.get("icon", "")) != "":
		out["icon"] = str(e["icon"])
	return out


## Pass 73: how big an amount is within a range, in thirds of its size: 1 (the smallest third) .. 3 (the biggest). A
## range that is one number is 3. (Pass 138: a gift's rarity is its `tier`; this stays for the older tools.)
static func quality(v: float, lo: float, hi: float) -> int:
	var a := minf(absf(lo), absf(hi))
	var b := maxf(absf(lo), absf(hi))
	if b - a < 0.000001:
		return 3
	var t := clampf((absf(v) - a) / (b - a), 0.0, 1.0)
	return clampi(int(floor(t * 3.0)) + 1, 1, 3)


## A rolled gift's tier, 1 (Common) .. 5 (Legendary): its `tier`, else its `quality`, else where its value sits on its
## ladder (`min` Common .. `max` Legendary, the nearest of five evenly spaced steps).
static func tier_of(boon: Dictionary) -> int:
	if boon.has("tier"):
		return clampi(int(boon["tier"]), 1, TIERS.size())
	if boon.has("quality"):
		return clampi(int(boon["quality"]), 1, TIERS.size())
	var lo := float(boon.get("min", boon.get("value", 0.0)))
	var hi := float(boon.get("max", lo))
	var a := minf(absf(lo), absf(hi))
	var b := maxf(absf(lo), absf(hi))
	if b - a < 0.000001:
		return TIERS.size()
	var x := clampf((absf(float(boon.get("value", 0.0))) - a) / (b - a), 0.0, 1.0)
	return clampi(int(roundf(x * (TIERS.size() - 1))) + 1, 1, TIERS.size())


## A tier's id ("common" .. "legendary") and its name as the player reads it ("Common" .. "Legendary": gen.rarity.*).
static func rarity_id(tier: int) -> String:
	return str(TIERS[clampi(tier, 1, TIERS.size()) - 1])


static func rarity_name(tier: int) -> String:
	return TextGen.rarity_name(rarity_id(tier))


## Pass 129 (lane TRAILCORE; the Trail's Spirit Guide, the hero's `totem_boost`): an offer with every gift's amount
## x (1 + boost), its range's ends with it (so the gauge's thirds and its end marks stay true). The same list for a
## boost of 0.
static func boosted(offer_list: Array, boost: float) -> Array:
	if absf(boost) < 0.000001:
		return offer_list
	var f := maxf(1.0 + boost, 0.0)
	var out: Array = []
	for b: Dictionary in offer_list:
		var c := b.duplicate()
		for k: String in ["value", "min", "max"]:
			if c.has(k):
				c[k] = float(c[k]) * f
		out.append(c)
	return out


## The boon as an Effect on the hero.
static func effect_of(boon: Dictionary) -> Effect:
	return Effect.make(str(boon.get("stat", "")), str(boon.get("op", "add")), float(boon.get("value", 0.0)), "player")


## The boon's stat as a plain number with its name ("+6% move speed", "+10 max HP", "−3% cooldown"), from TextGen.
## Pass 138: a percentage that is not a whole one keeps its half ("+0.5% move speed", "+1.5% attack damage": the Common
## gifts), where the sheet's words round it ("+1%"); every other amount reads as TextGen says it.
static func text(boon: Dictionary) -> String:
	var own := _half_pct(boon)
	return TextGen.describe_effect(effect_of(boon)) if own == "" else own + " " + stat_text(boon)


## The amount alone ("+6%", "+10", "+0.3") and the stat's name alone ("move speed"), for the menu's big number.
static func amount_text(boon: Dictionary) -> String:
	var own := _half_pct(boon)
	return TextGen.describe_effect(effect_of(boon), false) if own == "" else own


## A multiplied amount that is not a whole percentage, with one decimal ("+0.5%", "−1.5%"); "" for any other amount.
static func _half_pct(boon: Dictionary) -> String:
	if str(boon.get("op", "add")) != "mul":
		return ""
	var stat := str(boon.get("stat", ""))
	if TextGen.stat_kind(stat) in ["word", "hidden", "rule"] or TextGen.PREFIX.has(stat):
		return ""
	var pct := float(boon.get("value", 0.0)) * 100.0
	if absf(pct - roundf(pct)) < 0.001:
		return ""
	return ("+" if pct >= 0.0 else "−") + "%.1f%%" % absf(pct)


static func stat_text(boon: Dictionary) -> String:
	return TextGen.stat_name(str(boon.get("stat", "")))


## The boon's title: its word and its animal ("Le-loo, the Wolf"; the Raven and the Frog have no word of their own).
static func title(boon: Dictionary) -> String:
	var n := str(boon.get("name", ""))
	var a := str(boon.get("animal", ""))
	return n if a == "" else "%s, %s" % [n, a]


## The sheet's source name of a taken boon.
static func source(boon: Dictionary) -> String:
	return Loc.t(SOURCE_KEY, {"name": str(boon.get("name", boon.get("id", "?")))})


# ---------------------------------------------------------------- the Spirit Pole screen's data (pass 82, lane TOTEM)
## Pass 82 (lane TOTEM, design_handoff_88fits_totem, direction 1b "The Spirit Pole"): what each element of the gift
## screen reads, from the rolled boon and its pool entry. Nothing here changes a roll: the weights, ranges and steps are
## the pole's JSON as before.

## The texture slot every spirit has (256 px square, carved face, thick dark outline, in the pole's paint style): an
## artist fills one by dropping art/ui/totem/spirit_<boon id>.png in; a pool entry's own `icon` path wins over it. Until
## one is there the screen shows the empty plate with the spirit's word.
const ICON_SLOT := "res://art/ui/totem/spirit_%s.png"
static var _icons: Dictionary = {}


## The spirit's word ("Le-loo", "Frog").
static func word(boon: Dictionary) -> String:
	return str(boon.get("name", boon.get("id", "")))


## The spirit's animal ("the Wolf"), "" when the spirit has none (the Frog, the Raven, the Thunderbird).
static func animal(boon: Dictionary) -> String:
	return str(boon.get("animal", ""))


## The gift's rarity tier, 1..5 (pass 138: tier_of; before it, which third of its range the roll landed in, 1..3; the
## bot's "feathers").
static func roll_third(boon: Dictionary) -> int:
	return tier_of(boon)


## The range's two ends written like the amount ("+1%", "+3%"; "+2", "+6"; "+0.1", "+0.3"), the smaller size first, so
## the gauge fills from the left as a gift grows whatever its sign (the Thunderbird's cooldown: "−2%" ... "−4%").
## (Pass 138: a pool entry with `tiers` reads its Common and Legendary amounts.)
static func range_texts(boon: Dictionary) -> Array:
	var lo := float(boon.get("min", boon.get("value", 0.0)))
	var hi := float(boon.get("max", lo))
	if boon.has("tiers") and not boon.has("min"):
		var ends := tier_amounts(boon)
		lo = float(ends[0])
		hi = float(ends[TIERS.size() - 1])
	if absf(lo) > absf(hi):
		var t := lo
		lo = hi
		hi = t
	var a := boon.duplicate()
	a["value"] = lo
	var b := boon.duplicate()
	b["value"] = hi
	return [amount_text(a), amount_text(b)]


## The path of the spirit's icon: the pool entry's `icon` when it names one, else its slot (ICON_SLOT by the boon's id).
static func icon_path(boon: Dictionary) -> String:
	var own := str(boon.get("icon", ""))
	if own != "":
		return own if own.begins_with("res://") else "res://" + own
	return ICON_SLOT % str(boon.get("id", ""))


## The spirit's carved face, null when its slot is still empty (the screen then shows the plate with the word).
static func icon_of(boon: Dictionary) -> Texture2D:
	var p := icon_path(boon)
	if not _icons.has(p):
		_icons[p] = load(p) as Texture2D if ResourceLoader.exists(p) else null
	return _icons[p]


## The toast once a gift is taken: "Le-loo · +2% move speed".
static func toast_text(boon: Dictionary) -> String:
	return "%s · %s" % [word(boon), text(boon)]


## The screen's label: "★ TOTEM 4 OF 11 ★" read as "TOTEM 4 OF 11" (the stars are drawn), or "4TH TOTEM" when the map's
## count of poles is unknown (`total` 0 or less). A count past the total (a pole the arena stood) raises the total.
static func pole_label(index: int, total: int) -> String:
	var n := maxi(index, 1)
	if total <= 0:
		return Loc.t("gen.structure.totem.nth", {"nth": ordinal(n)})
	return Loc.t("gen.structure.totem.of", {"n": str(n), "total": str(maxi(total, n))})


## 1ST, 2ND, 3RD, 4TH ... 11TH, 12TH, 13TH ... 21ST.
static func ordinal(n: int) -> String:
	var suf := "TH"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1:
				suf = "ST"
			2:
				suf = "ND"
			3:
				suf = "RD"
	return "%d%s" % [n, suf]
