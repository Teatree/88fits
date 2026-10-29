## Pass 109: the first-run Dynamite offer (Garry: "make it so Player always gets a dynamite stick offered to him on his
## 3rd level up, and it's offered among the worst items that are available to Player at that point to increase the
## likelihood of Player choosing the dynamite ... This will only stop happening when Player actually chooses the
## dynamite"). In every run, the first ordinary card screen of the hero's level AT_LEVEL or later (the 3rd level-up; when
## that one is a mutation level-up, the next card screen) holds the Dynamite Stick (the weapon WEAPON_ID, whose played
## family look is the Dynamite Stick) as a new weapon, beside the two lowest-rarity cards the normal draw could offer
## then (worst_cards). Once the player picks a Dynamite card (note_pick), the save's once-flag ONCE_KEY ends it for good.
## The card overrides the weapon's unlock quest for that one card; picking it unlocks nothing. Not in the arena, not when
## the hero holds the weapon (or its evolution) or has no free weapon slot. A reroll or a banish's redraw draws normally.
## BALANCING.md "First-run Dynamite offer".
class_name FtueDynamite
extends RefCounted

const WEAPON_ID := "lob_grenade"
const ONCE_KEY := "ftue_dynamite_taken"
## The hero's level whose card screen holds it (his 3rd level-up).
const AT_LEVEL := 4
## Cheapest first: the order the two companion cards are taken in.
const RARITY_RANK := {"common": 0, "uncommon": 1, "rare": 2, "epic": 3, "legendary": 4}


## Whether the player has picked the Dynamite once (the offer is over for good).
static func taken() -> bool:
	return Save.once(ONCE_KEY)


## Whether the card screen opening now, for the hero's level `screen_level`, is the forced one.
static func due(screen_level: int) -> bool:
	if screen_level < AT_LEVEL or Run.ftue_dynamite_shown or Run.arena or taken():
		return false
	var def: WeaponDef = Registry.weapon(WEAPON_ID)
	if def == null or def.hidden or def.is_evolution or not Registry.hero_may_use(def):
		return false
	if Run.weapon_instance(WEAPON_ID) != null or Run.family_instance(WEAPON_ID) != null:
		return false
	return Run.weapons.size() < Run.weapon_cap()


## The forced offer: the Dynamite card (a new weapon, as a normal draw would make it: the favourite's level and heart for
## a hero whose favourite it is) and the two worst cards, the Dynamite at a random place among them. Marks the run's
## offer as shown and keeps the perk gap's count like any offer.
static func offer(count: int = 3) -> Array:
	var def: WeaponDef = Registry.weapon(WEAPON_ID)
	var out: Array = worst_cards(CardPool.candidates(), maxi(count - 1, 0))
	if def:
		var card := CardPool._favourite(CardPool._card("weapon", def, 0, CardPool.first_weapon_level(def), CardPool.weight_of(def, 0)))
		card["ftue"] = true
		out.insert(_rand_index(out.size() + 1), card)
	Run.ftue_dynamite_shown = true
	Run.note_offer(out)
	return out


## The `n` lowest-value cards of `cands`: lowest rarity first (common, uncommon, rare, epic, legendary), ties at random;
## never a new weapon (the Dynamite is the offer's one), never a perk, never the hero's favourite, never an evolution
## card or a level that maxes an item that evolves (it would complete an evolution), never the Dynamite itself. When too
## few are left, the others (but a new weapon or the Dynamite) fill in, cheapest first.
static func worst_cards(cands: Array, n: int) -> Array:
	var first: Array = []
	var rest: Array = []
	for c: Dictionary in cands:
		if str(c["id"]) == WEAPON_ID or (str(c["type"]) == "weapon" and bool(c.get("is_new", false))):
			continue
		if _is_cheap(c):
			first.append(c)
		else:
			rest.append(c)
	var out: Array = _cheapest(first, n)
	if out.size() < n:
		out.append_array(_cheapest(rest, n - out.size()))
	return out


## Whether a card may be one of the two: no perk, no favourite, no evolution, nothing that maxes an item that evolves.
static func _is_cheap(c: Dictionary) -> bool:
	var t := str(c["type"])
	if t == "perk" or t == "mutation":
		return false
	if bool(c.get("favourite", false)) or bool(c.get("evolve", false)):
		return false
	var def: ContentDef = c["def"]
	if Run.is_favourite(def):
		return false
	if def is WeaponDef:
		var wd := def as WeaponDef
		if wd.is_evolution or int(c["level_to"]) >= wd.max_level:
			return false
	elif def is PassiveDef:
		var pd := def as PassiveDef
		if pd.is_evolved() or (pd.evolves_into != "" and int(c["level_to"]) >= pd.max_level):
			return false
	return true


## The `n` cards of the lowest rarity, ties broken at random (a random fraction under one added to each card's rank).
static func _cheapest(cards: Array, n: int) -> Array:
	var keyed: Array = []
	for c: Dictionary in cards:
		var def: ContentDef = c["def"]
		keyed.append([float(RARITY_RANK.get(def.rarity if def else "", 2)) + _randf() * 0.5, c])
	keyed.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var out: Array = []
	for k in mini(n, keyed.size()):
		out.append(keyed[k][1])
	return out


## A picked level-up card: the Dynamite, by a real player (not the arena), ends the offer for good.
static func note_pick(card: Dictionary) -> void:
	if card.is_empty() or bool(card.get("skipped", false)) or Run.arena:
		return
	if str(card.get("type", "")) == "weapon" and str(card.get("id", "")) == WEAPON_ID:
		Save.mark_once(ONCE_KEY)


## Forget the pick (the developer menu): the offer comes again from the next run.
static func reset() -> void:
	(Save.data["once"] as Array).erase(ONCE_KEY)
	Save.request_save(true)


static func _randf() -> float:
	return CardPool.rng.randf() if CardPool.rng != null else Dice.r.randf()


static func _rand_index(n: int) -> int:
	return mini(int(_randf() * n), n - 1)
