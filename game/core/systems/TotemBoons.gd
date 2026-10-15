## The Totem Pole's gifts (pass 73, Garry: "When activated a menu pops up offering Players a choice between 3 small stats
## improvements for that run. Each upgrade is titled somethings like one of those native American words for animals ...
## the size of the stat increase ranges quite a bit, with more common stats being more common than the others ... The
## stat increases shouldn't be big, but not nothing").
## The pool is data: content/structures/totem_pole's `params.boons`, one entry per carved spirit {id, name (its word,
## "Le-loo"), animal ("the Wolf"), stat, op (add | mul), min, max, step, weight}. An offer draws `params.choices` entries
## by weight without putting one back and never two of one stat, and rolls each one's amount evenly between its min and
## max, snapped to its step. A boon taken stays on the hero for the whole run (Run.totem_boons, a source of its own on
## the sheet: "Totem: Le-loo").
class_name TotemBoons
extends RefCounted

## The choices an offer holds when the structure does not say (`params.choices`).
const CHOICES := 3
## The sheet's source of a taken boon: "Totem: <its word>".
const SOURCE := "Totem: %s"


## The well-formed entries of a structure's pool (a stat, a positive weight, numbers for min and max), in its order.
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
		if not (d.has("min") and d.has("max")):
			continue
		out.append(d)
	return out


## An offer of `n` boons from the structure's pool (its `params.choices` when `n` is 0 or less): drawn by weight, one
## entry at most once, one stat at most once, each rolled (roll). Fewer when the pool runs out.
static func offer(def: StructureDef, rng: RandomNumberGenerator = null, n: int = 0) -> Array:
	var r := rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.randomize()
	var want: int = n
	if want <= 0:
		want = int(def.params.get("choices", CHOICES)) if def != null else CHOICES
	var left: Array = pool_of(def)
	var out: Array = []
	while out.size() < want and not left.is_empty():
		var pick := _weighted(left, r)
		var stat := str(pick.get("stat", ""))
		left = left.filter(func(e: Dictionary) -> bool: return e != pick and str(e.get("stat", "")) != stat)
		out.append(roll(pick, r))
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


## One boon rolled from a pool entry: the entry's words and stat with `value` drawn evenly between min and max and
## snapped to `step` (never outside the range), and `quality` 1..3: which third of the range the amount's size landed
## in (the menu hangs that many feathers on its plank).
static func roll(e: Dictionary, r: RandomNumberGenerator) -> Dictionary:
	var lo := float(e.get("min", 0.0))
	var hi := float(e.get("max", lo))
	var v := lerpf(lo, hi, r.randf())
	var step := float(e.get("step", 0.0))
	if step > 0.0:
		v = snappedf(v, step)
	v = clampf(v, minf(lo, hi), maxf(lo, hi))
	var out := {"id": str(e.get("id", e.get("stat", ""))), "name": str(e.get("name", "")), "animal": str(e.get("animal", "")),
		"stat": str(e.get("stat", "")), "op": str(e.get("op", "add")), "value": v, "min": lo, "max": hi,
		"quality": quality(v, lo, hi)}
	# pass 82 (lane TOTEM): a pool entry's own icon path rides along (icon_of); without one the spirit's slot is used
	if str(e.get("icon", "")) != "":
		out["icon"] = str(e["icon"])
	return out


## How big an amount is within its range, in thirds of its size: 1 (the smallest third) .. 3 (the biggest). A range
## that is one number is 3.
static func quality(v: float, lo: float, hi: float) -> int:
	var a := minf(absf(lo), absf(hi))
	var b := maxf(absf(lo), absf(hi))
	if b - a < 0.000001:
		return 3
	var t := clampf((absf(v) - a) / (b - a), 0.0, 1.0)
	return clampi(int(floor(t * 3.0)) + 1, 1, 3)


## The boon as an Effect on the hero.
static func effect_of(boon: Dictionary) -> Effect:
	return Effect.make(str(boon.get("stat", "")), str(boon.get("op", "add")), float(boon.get("value", 0.0)), "player")


## The boon's stat as a plain number with its name ("+6% move speed", "+10 max HP", "−3% cooldown"), from TextGen.
static func text(boon: Dictionary) -> String:
	return TextGen.describe_effect(effect_of(boon))


## The amount alone ("+6%", "+10", "+0.3") and the stat's name alone ("move speed"), for the menu's big number.
static func amount_text(boon: Dictionary) -> String:
	return TextGen.describe_effect(effect_of(boon), false)


static func stat_text(boon: Dictionary) -> String:
	return TextGen.stat_name(str(boon.get("stat", "")))


## The boon's title: its word and its animal ("Le-loo, the Wolf"; the Raven and the Frog have no word of their own).
static func title(boon: Dictionary) -> String:
	var n := str(boon.get("name", ""))
	var a := str(boon.get("animal", ""))
	return n if a == "" else "%s, %s" % [n, a]


## The sheet's source name of a taken boon.
static func source(boon: Dictionary) -> String:
	return SOURCE % str(boon.get("name", boon.get("id", "?")))


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


## Which third of its own range the roll landed in, 1..3 (the gauge's filled notches; `quality` as rolled, worked out
## again from value, min and max when a boon comes without it).
static func roll_third(boon: Dictionary) -> int:
	if boon.has("quality"):
		return clampi(int(boon["quality"]), 1, 3)
	var lo := float(boon.get("min", boon.get("value", 0.0)))
	var hi := float(boon.get("max", lo))
	return quality(float(boon.get("value", 0.0)), lo, hi)


## The range's two ends written like the amount ("+1%", "+3%"; "+2", "+6"; "+0.1", "+0.3"), the smaller size first, so
## the gauge fills from the left as a gift grows whatever its sign (the Thunderbird's cooldown: "−2%" ... "−4%").
static func range_texts(boon: Dictionary) -> Array:
	var lo := float(boon.get("min", boon.get("value", 0.0)))
	var hi := float(boon.get("max", lo))
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
		return "%s TOTEM" % ordinal(n)
	return "TOTEM %d OF %d" % [n, maxi(total, n)]


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
