## The Store's rules (pass 147, lane SHOP; pass 149, lane STORE). The screen (ui/StoreScreen.gd) only shows them; the
## offers are data, res://content/store/store.json (docs/store_schema.md), version 2 since pass 149 (Garry, 2026-11-14:
## "there is a problem with Coins scaling ... we create a Hard Currency ... light blue gems"; "In the Shop there will now be 2
## sections: Gems section at the top, Coins section underneath: Gems are bought with $ ... Coins are bought with Gems. As the
## Player progresses the amount of Coins they get from each offers changes ... in rounded steps"):
##     {"version": 2,
##      "gems":  {"currency": "gems", "show_bonus": true,
##                "packs": [{"id", "amount", "price_cents", "price_text", "ribbon", "picture"}, ...]},
##      "coins": {"currency": "gold", "pay": "gems", "show_bonus": true,
##                "offers": [{"id", "gems", "coins", "ribbon", "picture"}, ...],
##                "scaling": {"stage_mult": [1, 3, 7, 14], "trail_step": 10, "trail_per_step": 0.05, "round_sig": 2}},
##      "revive": {"price": 0, "currency": "gems", "per_run": 1}}
## Packs and offers in the order the screen lays them (the gem packs three a row, the coin offers in one row). BALANCING 88
## (the Store) and 92 (pass 149) have the amounts and why. A version 1 file (pass 147's coin packs for dollars) is not read:
## its sections are empty and problems() says so.
## Rules (no others):
## - **No real purchase.** buy_gems() never adds gems, never writes the save and never records anything; it answers
##   {"ok": false, "reason": "not_yet"} and the screen says so ("Coming soon"). Billing is a later pass.
## - **A coin offer is a real exchange** (buy_coins): its gems leave the wallet (Currency.spend, reason "store") and
##   coins_now() of the offer go into the purse (Currency.add, source "store"); short of gems, nothing moves.
## - **coins_now(offer)** = nice(offer.coins x stage_mult[s] x (1 + trail_per_step x floor(T / trail_step)), round_sig):
##   s the latest stage unlocked for the player (latest_stage(): the first map's highest stage Save.stage_unlocked, 0 on a
##   new save; past the end of stage_mult its last value holds), T the Trail Level (Trail.level()); nice() rounds to
##   round_sig significant figures, half away from zero (17,325 -> 17,000; 1,050 -> 1,100), 0 for nothing. The Level
##   Editor's store_model.js mirrors it; game/tests/fixtures/pass149_store_coins.json pins both.
## - **The bonus tag** "+N% BONUS": a gem pack's amount per whole dollar against the cheapest pack's (N = round(100 x
##   (amount / (dollars x base) - 1)), dollars = the price rounded up to a whole dollar); a coin offer's coins per gem
##   against the offer with the fewest gems, both at the amounts shown now (coins_now). Nothing at N < 1, nothing at all
##   when the section's "show_bonus" is false.
## - **The paid revive** (revive_for): with a price, Down! offers getting up for it once the free chances are spent and fewer
##   than per_run paid revives were used this run; price 0 (the default) = none, the game as before.
## - **Locked by default**: the STORE tab opens the screen only while is_open() (Settings.store_open, the Settings
##   screen's debug panel; held shut in the production build by Settings.PROD_LOCKED). The gem wallet shows only then too
##   (Currency.visible).
## - Coins x25 (Settings.coins_x25) never touches these amounts.
## Static, safe in tools compiled before the autoloads (Settings, Save and the Registry are looked up at run time).
class_name StorePacks
extends RefCounted

const DEFAULT := "res://content/store/store.json"
## The file's version this code reads.
const VERSION := 2
## The ribbon keys a pack or an offer may wear ("" = none); each is the string table's row RIBBON_KEY % key.
const RIBBONS := ["", "most_popular", "best_value"]
const RIBBON_KEY := "ui.store.ribbon_%s"
## The scaling when the file names none (no growth: every stage x1, no Trail steps), and the map whose stages count.
const NO_SCALING := {"stage_mult": [1.0], "trail_step": 0, "trail_per_step": 0.0, "round_sig": 2}
const FALLBACK_MAP := "red_canyon"
## The reason a coin offer's gems leave the wallet and the source its coins come from (Currency.spend / add).
const SINK := "store"
## The debug grant (the Settings screen's debug panel and the developer menu: "Add 1,000 gems"; never in prod).
const DEBUG_GRANT := 1000

static var _path := DEFAULT
static var _loaded := false
static var _data: Dictionary = {}
static var _packs: Array = []
static var _offers: Array = []
static var _scaling: Dictionary = {}


# ---------------------------------------------------------------- the file

## Reads the Store again from `path` (the game's file by default; a test may load its own).
static func load_from(path: String = DEFAULT) -> void:
	_path = path
	_loaded = false
	_ensure()


## The Store from a dictionary shaped like the file (the tests); `load_from()` goes back to the file.
static func load_data(d: Dictionary) -> void:
	_path = ""
	_build(d)


## A store file as a dictionary, or {} (with a warning) when it is missing or not a JSON object.
static func read_file(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_warning("StorePacks: %s is not a JSON object; the Store is empty" % path)
	return {}


static func _ensure() -> void:
	if _loaded:
		return
	_build(read_file(_path))


static func _section(d: Dictionary, key: String) -> Dictionary:
	var v: Variant = d.get(key, {})
	return v if v is Dictionary else {}


static func _build(d: Dictionary) -> void:
	_loaded = true
	_data = d
	_packs = []
	_offers = []
	_scaling = scaling_of(_section(_section(d, "coins"), "scaling"))
	if version() != VERSION:
		return
	var raw: Variant = _section(d, "gems").get("packs", [])
	if raw is Array:
		for p: Variant in raw:
			if not (p is Dictionary):
				continue
			var src := p as Dictionary
			_packs.append({
				"id": str(src.get("id", "")),
				"amount": maxi(int(src.get("amount", 0)), 0),
				"price_cents": maxi(int(src.get("price_cents", 0)), 0),
				"price_text": str(src.get("price_text", "")),
				"ribbon": str(src.get("ribbon", "")),
				"picture": str(src.get("picture", "")),
			})
	var base := base_rate()
	for pk: Dictionary in _packs:
		pk["bonus"] = bonus_for(int(pk["amount"]), int(pk["price_cents"]), base) if show_bonus() else 0
	raw = _section(d, "coins").get("offers", [])
	if raw is Array:
		for o: Variant in raw:
			if not (o is Dictionary):
				continue
			var src := o as Dictionary
			_offers.append({
				"id": str(src.get("id", "")),
				"gems": maxi(int(src.get("gems", 0)), 0),
				"coins": maxi(int(src.get("coins", 0)), 0),
				"ribbon": str(src.get("ribbon", "")),
				"picture": str(src.get("picture", "")),
			})


## The scaling block as the rule reads it: stage_mult a list of numbers (at least one; [1] when empty), trail_step a whole
## number of levels (0 or less = the Trail adds nothing), trail_per_step a share, round_sig the significant figures (1..6).
static func scaling_of(s: Dictionary) -> Dictionary:
	var mult: Array = []
	var raw: Variant = s.get("stage_mult", NO_SCALING["stage_mult"])
	if raw is Array:
		for m: Variant in raw:
			if m is float or m is int:
				mult.append(float(m))
	if mult.is_empty():
		mult = [1.0]
	return {"stage_mult": mult, "trail_step": int(s.get("trail_step", 0)),
		"trail_per_step": float(s.get("trail_per_step", 0.0)), "round_sig": clampi(int(s.get("round_sig", 2)), 1, 6)}


# ---------------------------------------------------------------- what the file says

## The file's version (1 when it names none).
static func version() -> int:
	_ensure()
	return int(_data.get("version", 1))


## Every gem pack in the file's order, each {id, amount, price_cents, price_text, ribbon, picture, bonus}.
static func gem_packs() -> Array:
	_ensure()
	return _packs


static func gem_pack(id: String) -> Dictionary:
	for pk: Dictionary in gem_packs():
		if str(pk["id"]) == id:
			return pk
	return {}


## The currency the gem packs give ("gems").
static func gem_currency() -> String:
	_ensure()
	return str(_section(_data, "gems").get("currency", "gems"))


## Whether the gem packs wear their bonus tags.
static func show_bonus() -> bool:
	return bool(_section(_data, "gems").get("show_bonus", true))


## Every coin offer in the file's order, each {id, gems, coins, ribbon, picture}: `coins` is the base amount (stage 1,
## Trail Level 0); coins_now() is what it gives this player.
static func offers() -> Array:
	_ensure()
	return _offers


static func offer(id: String) -> Dictionary:
	for o: Dictionary in offers():
		if str(o["id"]) == id:
			return o
	return {}


## The currency the coin offers give ("gold", the player's coins) and the one they cost ("gems").
static func coin_currency() -> String:
	_ensure()
	return str(_section(_data, "coins").get("currency", "gold"))


static func pay_currency() -> String:
	_ensure()
	return str(_section(_data, "coins").get("pay", "gems"))


## Whether the coin offers wear their bonus tags.
static func show_offer_bonus() -> bool:
	return bool(_section(_data, "coins").get("show_bonus", true))


## The coin offers' scaling as scaling_of reads it.
static func scaling() -> Dictionary:
	_ensure()
	return _scaling


# ---------------------------------------------------------------- the coin offer rule

## `v` rounded to `sig` significant figures, half away from zero, as a whole number (0 for v <= 0): 17,325 at 2 -> 17,000;
## 1,050 -> 1,100; 9,960 -> 10,000; under 10^sig it is v rounded to a whole number. The figures are counted on the
## whole part's digits (no logarithm: log(1000) / log(10) is 2.9999...).
static func nice(v: float, sig: int) -> int:
	if v <= 0.0:
		return 0
	var digits := str(int(floor(v))).length()
	var mag := pow(10.0, float(maxi(digits - maxi(sig, 1), 0)))
	return int(round(v / mag) * mag)


## The multiplier before rounding at stage index `stage_index` (0-based) and Trail Level `t_level`:
## stage_mult[s] x (1 + trail_per_step x floor(T / trail_step)).
static func mult_for(stage_index: int, t_level: int, sc: Dictionary) -> float:
	var s := scaling_of(sc)
	var mult: Array = s["stage_mult"]
	var m := float(mult[clampi(stage_index, 0, mult.size() - 1)])
	var step := int(s["trail_step"])
	var steps := floori(float(maxi(t_level, 0)) / float(step)) if step > 0 else 0
	return m * (1.0 + float(s["trail_per_step"]) * float(steps))


## The pure rule (the tests, the fixture and the Level Editor's mirror): offer `o`'s coins at stage index `stage_index`
## and Trail Level `t_level` under scaling `sc` ({} = the file's).
static func coins_for(o: Dictionary, stage_index: int, t_level: int, sc: Dictionary = {}) -> int:
	var s := scaling() if sc.is_empty() else scaling_of(sc)
	return nice(float(maxi(int(o.get("coins", 0)), 0)) * mult_for(stage_index, t_level, s), int(s["round_sig"]))


## What offer `o` gives this player now (coins_for at latest_stage() and the Trail Level).
static func coins_now(o: Dictionary) -> int:
	return coins_for(o, latest_stage(), trail_level())


## The Trail Level (Trail.level(); 0 without a save).
static func trail_level() -> int:
	return Trail.level() if _tree_node("Save") != null else 0


## The latest stage unlocked for the player: the highest index i of the first map's stage list with
## Save.stage_unlocked(map, i) (0 on a new save, without a save or without stages).
static func latest_stage() -> int:
	var sv := _tree_node("Save")
	var reg := _tree_node("Registry")
	if sv == null or reg == null:
		return 0
	var map_id := FALLBACK_MAP
	if reg.has_method("sorted_maps"):
		var maps: Array = reg.call("sorted_maps")
		if not maps.is_empty() and maps[0] != null:
			map_id = str(maps[0].get("id"))
	var m: Variant = reg.call("map", map_id) if reg.has_method("map") else null
	var n := 1
	if m != null and m.get("timeline") != null:
		n = maxi(int(m.get("timeline").call("stage_count")), 1)
	var best := 0
	for i in n:
		if bool(sv.call("stage_unlocked", map_id, i)):
			best = i
	return best


## Each offer's bonus tag N at stage `stage_index` and Trail Level `t_level` (id -> N; 0 = no tag): its coins per
## gem against the offer with the fewest gems, both at the amounts the rule gives there.
static func offer_bonuses(stage_index: int, t_level: int, sc: Dictionary = {}) -> Dictionary:
	var out := {}
	var base := 0.0
	var fewest := -1
	for o: Dictionary in offers():
		var g := int(o["gems"])
		if g > 0 and (fewest < 0 or g < fewest):
			fewest = g
			base = float(coins_for(o, stage_index, t_level, sc)) / float(g)
	for o: Dictionary in offers():
		var n := 0
		var g := int(o["gems"])
		if show_offer_bonus() and base > 0.0 and g > 0:
			n = roundi(100.0 * (float(coins_for(o, stage_index, t_level, sc)) / float(g) / base - 1.0))
		out[str(o["id"])] = n if n >= 1 else 0
	return out


## The bonus tags as shown now (offer_bonuses at the player's stage and Trail Level).
static func offer_bonuses_now() -> Dictionary:
	return offer_bonuses(latest_stage(), trail_level())


# ---------------------------------------------------------------- the gem packs' bonus tag

## A price in whole dollars, rounded up ($0.99 -> 1, $4.99 -> 5); at least 1.
static func dollars(cents: int) -> int:
	return maxi(ceili(float(cents) / 100.0), 1)


## The cheapest gem pack's amount per whole dollar (0 with no packs).
static func base_rate() -> float:
	var best := -1
	var rate := 0.0
	for pk: Dictionary in _packs:
		var c := int(pk["price_cents"])
		if c <= 0:
			continue
		if best < 0 or c < best:
			best = c
			rate = float(pk["amount"]) / float(dollars(c))
	return rate


## The bonus tag's N for a pack of `amount` at `cents` against `base` a dollar (0 = no tag).
static func bonus_for(amount: int, cents: int, base: float) -> int:
	if base <= 0.0 or cents <= 0:
		return 0
	var n := roundi(100.0 * (float(amount) / (float(dollars(cents)) * base) - 1.0))
	return n if n >= 1 else 0


# ---------------------------------------------------------------- the paid revive

## The file's paid revive: {price, currency, per_run}; price 0 = none.
static func revive_offer() -> Dictionary:
	_ensure()
	var r := _section(_data, "revive")
	return {"price": maxi(int(r.get("price", 0)), 0), "currency": str(r.get("currency", "gems")),
		"per_run": maxi(int(r.get("per_run", 1)), 0)}


## What Down! offers to pay for getting up, given the free `chances` left and the paid revives `used` this run: {} (none:
## no price, a free chance left, or per_run used) or {price, currency}.
static func revive_for(chances: int, used: int) -> Dictionary:
	var r := revive_offer()
	if int(r["price"]) <= 0 or chances > 0 or used >= int(r["per_run"]):
		return {}
	return {"price": int(r["price"]), "currency": str(r["currency"])}


# ---------------------------------------------------------------- the checks

## What is wrong with the file, a sentence each ([] = nothing): the version; a pack or an offer without an id or with a
## repeated one (ids are shared by both sections), no amount, no price; a price text that does not name the price; a
## ribbon the screen does not know; a scaling that shrinks or names no stages; a paid revive priced in nothing.
static func problems() -> Array:
	_ensure()
	var out: Array = []
	if version() != VERSION:
		out.append("version %d: the Store reads version %d (docs/store_schema.md)" % [version(), VERSION])
		return out
	var seen := {}
	for pk: Dictionary in gem_packs():
		var id := str(pk["id"])
		_id_problems(id, seen, out)
		if int(pk["amount"]) <= 0:
			out.append("%s: no amount" % id)
		if int(pk["price_cents"]) <= 0:
			out.append("%s: no price_cents" % id)
		var pt := str(pk["price_text"])
		var cents := int(pk["price_cents"])
		if pt == "":
			out.append("%s: no price_text" % id)
		elif not pt.contains("%d.%02d" % [floori(cents / 100.0), cents % 100]):
			out.append("%s: price_text %s does not name price_cents %d" % [id, pt, cents])
		if not RIBBONS.has(str(pk["ribbon"])):
			out.append("%s: unknown ribbon %s" % [id, str(pk["ribbon"])])
	for o: Dictionary in offers():
		var id := str(o["id"])
		_id_problems(id, seen, out)
		if int(o["gems"]) <= 0:
			out.append("%s: no gems" % id)
		if int(o["coins"]) <= 0:
			out.append("%s: no coins" % id)
		if not RIBBONS.has(str(o["ribbon"])):
			out.append("%s: unknown ribbon %s" % [id, str(o["ribbon"])])
	var raw_mult: Variant = _section(_section(_data, "coins"), "scaling").get("stage_mult", [])
	if not (raw_mult is Array) or (raw_mult as Array).is_empty():
		out.append("coins.scaling.stage_mult: no stages")
	var mult: Array = scaling()["stage_mult"]
	for i in range(1, mult.size()):
		if float(mult[i]) < float(mult[i - 1]):
			out.append("coins.scaling.stage_mult: stage %d gives less than stage %d" % [i + 1, i])
	if float(mult[0]) <= 0.0:
		out.append("coins.scaling.stage_mult: stage 1 gives nothing")
	if float(scaling()["trail_per_step"]) < 0.0:
		out.append("coins.scaling.trail_per_step: below 0")
	var r := revive_offer()
	if int(r["price"]) > 0 and str(r["currency"]) == "":
		out.append("revive: a price with no currency")
	return out


static func _id_problems(id: String, seen: Dictionary, out: Array) -> void:
	if id == "":
		out.append("a pack has no id")
	elif seen.has(id):
		out.append("%s: the id is used twice" % id)
	seen[id] = true


# ---------------------------------------------------------------- the lock and the purchases

static func _tree_node(n: String) -> Node:
	var ml := Engine.get_main_loop()
	return (ml as SceneTree).root.get_node_or_null(n) if ml is SceneTree else null


## Whether the STORE tab opens the Store: the Settings' store_open (the debug panel's switch; off by default, held off in
## the production build). False where there are no Settings (a tool before the autoloads).
static func is_open() -> bool:
	var s: Node = _tree_node("Settings")
	if s == null or not ("store_open" in s):
		return false
	if s.has_method("is_prod") and bool(s.call("is_prod")):
		return false
	return bool(s.get("store_open"))


## The debug grant: DEBUG_GRANT gems into the wallet (source "debug"); nothing in the production build. Returns the balance.
static func debug_grant() -> int:
	var s: Node = _tree_node("Settings")
	if s != null and s.has_method("is_prod") and bool(s.call("is_prod")):
		return Currency.balance(gem_currency())
	return Currency.add(gem_currency(), DEBUG_GRANT, "debug", {"why": "debug_grant"})


## A gem pack's price tapped (pass 147's rule): there is no billing yet, so nothing is bought, paid, saved or recorded.
static func buy_gems(id: String) -> Dictionary:
	return {"ok": false, "reason": "not_yet", "id": id}


## Pass 147's name for buy_gems (a tool or an old test).
static func buy(id: String) -> Dictionary:
	return buy_gems(id)


## A coin offer bought with gems: the offer's gems leave the wallet, coins_now() of it go into the purse. Answers
## {ok, id, gems, coins} and, when nothing moved, reason "unknown" (no such offer) or "short" (with `short`: the gems
## still needed).
static func buy_coins(id: String) -> Dictionary:
	var o := offer(id)
	if o.is_empty():
		return {"ok": false, "reason": "unknown", "id": id}
	var cost := int(o["gems"])
	var coins := coins_now(o)
	var pay := pay_currency()
	var have := Currency.balance(pay)
	var ans := {"ok": false, "id": id, "gems": cost, "coins": coins}
	if have < cost:
		ans["reason"] = "short"
		ans["short"] = cost - have
		return ans
	var extra := {"offer": id, "gems": cost, "coins": coins, "stage": latest_stage(), "trail_level": trail_level()}
	if not Currency.spend(pay, cost, SINK, extra):
		ans["reason"] = "short"
		ans["short"] = maxi(cost - Currency.balance(pay), 1)
		return ans
	Currency.add(coin_currency(), coins, SINK, extra)
	ans["ok"] = true
	return ans
