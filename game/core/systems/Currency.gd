## The meta game's money (pass 111, lane SKINS; Garry: "get everything ready for the currency selection functionality
## in every place where it matters. We aren't adding new currency yet, but we might eventually"). Every price that is
## shown and paid outside a run goes through here: a hero on sale (CharacterDef.currency_type), an Upgrade board rank
## (TalentDef.currency_type), a look sold as a skin (`skin.currency_type`); anything that pays out (a run's purse, a
## refund, a contract's reward) can call add(). The currencies are content (content/currencies/<id>, CurrencyDef,
## Registry.currencies); only "gold" exists. Gold is the save's old "gold" key (Save.gold / add_gold / spend_gold, so
## every gold_moved event and the analytics stay as they were); any other currency lives in the save's "wallets".
##
##   Currency.balance("gold")                      -> int
##   Currency.add("gold", 250, "contract", {...})  -> the balance after
##   Currency.spend("gold", 900, "skin", {...})    -> true when paid (false: short, nothing spent)
##   Currency.can_afford("gold", 900)              -> bool
##   Currency.of(id)                               -> the id as the game reads it: a known currency, else "gold"
##   Currency.icon(id) / name_of(id) / word_of(id) / colour(id) / price_words(id, n)
##
## An id the content does not have reads as gold (of()): a hero or a skin priced in a currency not made yet is sold for
## gold rather than never (BALANCING §54.SKINS). Static, no class it names refers to an autoload at compile time: the
## Save and the Registry are fetched from the tree (tools compile before the autoloads exist).
class_name Currency
extends RefCounted

## The currency every price falls back to, and the one the save's old "gold" key holds.
const DEFAULT := "gold"
## The coin the gold icon was before the registry (art/ui/wanted/coin.png), for a build without the gold folder.
const GOLD_ART := "res://art/ui/wanted/coin.png"


static func _tree_node(n: String) -> Node:
	var ml := Engine.get_main_loop()
	return (ml as SceneTree).root.get_node_or_null(n) if ml is SceneTree else null


static func _reg() -> Node:
	return _tree_node("Registry")


static func _save() -> Node:
	return _tree_node("Save")


## Every currency the content has, by `order` then id (gold first); ["gold"] when the folder is missing.
static func ids() -> Array:
	var reg := _reg()
	var all: Dictionary = reg.get("currencies") if reg and reg.get("currencies") is Dictionary else {}
	if all.is_empty():
		return [DEFAULT]
	var defs: Array = all.values()
	defs.sort_custom(func(a, b) -> bool: return a.id < b.id if int(a.order) == int(b.order) else int(a.order) < int(b.order))
	return defs.map(func(d) -> String: return str(d.id))


## The currency def (null for an id the content does not have).
static func def(id: String) -> CurrencyDef:
	var reg := _reg()
	if reg == null or not (reg.get("currencies") is Dictionary):
		return null
	return (reg.get("currencies") as Dictionary).get(id)


## Whether the content has currency `id`.
static func known(id: String) -> bool:
	return def(id) != null or id == DEFAULT


## The id as the game reads it: `id` when the content has it, else gold ("" and unknown ids alike).
static func of(id: String) -> String:
	return id if id != "" and known(id) else DEFAULT


## Its name ("Gold").
static func name_of(id: String) -> String:
	var d := def(of(id))
	return d.display_name if d else "Gold"


## The word a sentence uses ("gold": "250 gold from your purse").
static func word_of(id: String) -> String:
	var d := def(of(id))
	return d.word_of() if d else "gold"


## Its colour.
static func colour(id: String) -> Color:
	var d := def(of(id))
	return d.colour if d else Color("c9932f")


## Its icon (the coin for gold), null when the content names none.
static func icon(id: String) -> Texture2D:
	var d := def(of(id))
	if d and d.icon:
		return d.icon
	if of(id) == DEFAULT and ResourceLoader.exists(GOLD_ART):
		return load(GOLD_ART) as Texture2D
	return null


## "2,000 gold".
static func price_words(id: String, n: int) -> String:
	return "%s %s" % [_grouped(n), word_of(id)]


static func _grouped(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## The balance of `id` in the save (0 without a save).
static func balance(id: String) -> int:
	var sv := _save()
	return int(sv.call("currency_balance", of(id))) if sv else 0


## Whether the save holds `n` of `id`.
static func can_afford(id: String, n: int) -> bool:
	return balance(id) >= maxi(n, 0)


## `n` of `id` into the save; `source` says from where (run_bank, contract, refund, ...), `extra` rides along on the
## event. Returns the balance after.
static func add(id: String, n: int, source: String = "other", extra: Dictionary = {}) -> int:
	var sv := _save()
	if sv == null:
		return 0
	sv.call("add_currency", of(id), n, source, extra)
	return balance(id)


## `n` of `id` out of the save for `reason` (hero, talent, skin, ...): true when paid, false (nothing spent) when short.
static func spend(id: String, n: int, reason: String = "other", extra: Dictionary = {}) -> bool:
	var sv := _save()
	if sv == null:
		return false
	return bool(sv.call("spend_currency", of(id), maxi(n, 0), reason, extra))
