## The Store's coin packs (pass 147, lane SHOP; Garry: "Make the Shop Screen. On this screen we will only allow selling of
## Coin Packs for now ... Don't implement actual purchasing yet, but put up prices that are common for us. Make the shop
## button unlockable via the Debug version of the Settings. By default locked."). The rules live here, the screen
## (ui/StoreScreen.gd) only shows them; the packs are data, res://content/store/store.json (docs/store_schema.md):
##     {"version": 1, "currency": "gold", "show_bonus": true,
##      "packs": [{"id", "coins", "price_cents", "price_text", "ribbon", "picture"}, ...]}
## in the order the screen lays them (two columns, left to right, top to bottom). BALANCING 88.STORE has the amounts and
## why.
## Rules (no others):
## - **No real purchase.** buy() never adds coins, never writes the save and never records anything; it answers
##   {"ok": false, "reason": "not_yet"} and the screen says so (toast.store.not_yet). Billing is a later pass.
## - **The bonus tag**: a pack shows "+N% BONUS" when its coins per whole dollar beat the cheapest pack's: N = round(100 x
##   (coins / (dollars x base) - 1)), dollars = the price rounded up to a whole dollar ($4.99 counts as $5), base = the
##   cheapest pack's coins per whole dollar; nothing at N < 1, nothing at all when "show_bonus" is false.
## - **Locked by default**: the STORE tab opens the screen only while is_open() (Settings.store_open, the Settings
##   screen's debug panel; held shut in the production build by Settings.PROD_LOCKED).
## - Coins x25 (Settings.coins_x25) never touches these amounts: the shop shows and would sell exactly the file's.
## Static, safe in tools compiled before the autoloads (Settings is looked up at run time).
class_name StorePacks
extends RefCounted

const DEFAULT := "res://content/store/store.json"
## The ribbon keys a pack may wear ("" = none); each is the string table's row RIBBON_KEY % key.
const RIBBONS := ["", "most_popular", "best_value"]
const RIBBON_KEY := "ui.store.ribbon_%s"

static var _path := DEFAULT
static var _loaded := false
static var _data: Dictionary = {}
static var _packs: Array = []


# ---------------------------------------------------------------- the file

## Reads the packs again from `path` (the game's file by default; a test may load its own).
static func load_from(path: String = DEFAULT) -> void:
	_path = path
	_loaded = false
	_ensure()


## The packs from a dictionary shaped like the file (the tests); `load_from()` goes back to the file.
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


static func _build(d: Dictionary) -> void:
	_loaded = true
	_data = d
	_packs = []
	var raw: Variant = d.get("packs", [])
	if not (raw is Array):
		return
	for p: Variant in raw:
		if not (p is Dictionary):
			continue
		var src := p as Dictionary
		_packs.append({
			"id": str(src.get("id", "")),
			"coins": maxi(int(src.get("coins", 0)), 0),
			"price_cents": maxi(int(src.get("price_cents", 0)), 0),
			"price_text": str(src.get("price_text", "")),
			"ribbon": str(src.get("ribbon", "")),
			"picture": str(src.get("picture", "")),
		})
	var base := base_rate()
	for pk: Dictionary in _packs:
		pk["bonus"] = bonus_for(int(pk["coins"]), int(pk["price_cents"]), base) if show_bonus() else 0


# ---------------------------------------------------------------- what the file says

## Every pack in the file's order, each {id, coins, price_cents, price_text, ribbon, picture, bonus}.
static func packs() -> Array:
	_ensure()
	return _packs


static func pack(id: String) -> Dictionary:
	for pk: Dictionary in packs():
		if str(pk["id"]) == id:
			return pk
	return {}


## The currency the packs give (the purse's: "gold", which the player calls coins).
static func currency() -> String:
	_ensure()
	return str(_data.get("currency", "gold"))


static func show_bonus() -> bool:
	return bool(_data.get("show_bonus", true))


## A price in whole dollars, rounded up ($0.99 -> 1, $4.99 -> 5); at least 1.
static func dollars(cents: int) -> int:
	return maxi(ceili(float(cents) / 100.0), 1)


## The cheapest pack's coins per whole dollar (0 with no packs).
static func base_rate() -> float:
	var best := -1
	var rate := 0.0
	for pk: Dictionary in _packs:
		var c := int(pk["price_cents"])
		if c <= 0:
			continue
		if best < 0 or c < best:
			best = c
			rate = float(pk["coins"]) / float(dollars(c))
	return rate


## The bonus tag's N for a pack of `coins` at `cents` against `base` coins a dollar (0 = no tag).
static func bonus_for(coins: int, cents: int, base: float) -> int:
	if base <= 0.0 or cents <= 0:
		return 0
	var n := roundi(100.0 * (float(coins) / (float(dollars(cents)) * base) - 1.0))
	return n if n >= 1 else 0


## What is wrong with the file, a sentence each ([] = nothing): a pack without an id or with a repeated one, no coins, no
## price, no price text, a price text that does not name the price, a ribbon the screen does not know.
static func problems() -> Array:
	var out: Array = []
	var seen := {}
	for pk: Dictionary in packs():
		var id := str(pk["id"])
		if id == "":
			out.append("a pack has no id")
		elif seen.has(id):
			out.append("%s: the id is used twice" % id)
		seen[id] = true
		if int(pk["coins"]) <= 0:
			out.append("%s: no coins" % id)
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
	return out


# ---------------------------------------------------------------- the lock and the purchase

## Whether the STORE tab opens the Store: the Settings' store_open (the debug panel's switch; off by default, held off in
## the production build). False where there are no Settings (a tool before the autoloads).
static func is_open() -> bool:
	var ml := Engine.get_main_loop() as SceneTree
	var s: Node = ml.root.get_node_or_null("Settings") if ml else null
	if s == null or not ("store_open" in s):
		return false
	if s.has_method("is_prod") and bool(s.call("is_prod")):
		return false
	return bool(s.get("store_open"))


## A price tapped (pass 147): there is no billing yet, so nothing is bought, paid, saved or recorded.
static func buy(id: String) -> Dictionary:
	return {"ok": false, "reason": "not_yet", "id": id}
