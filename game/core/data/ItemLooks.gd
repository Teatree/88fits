## Pass 76 (lane LOOKS; Garry: make the Grenade a Dynamite Stick "as a Look (with several candidates), so I can switch back
## to the grenade if I ever change my mind", and the Molotov "in several different versions"): a weapon family's looks,
## how the family looks and is called, never its rules.
##
## A weapon, an evolution or a mutation JSON may carry `variants {CODE: entry}` and `variant_base` (the code its top-level
## fields are, "A" by default); the WEAPON's `variant`, or a phone's Save.item_looks, names the code its whole family plays
## (the weapon, its evolutions, every mutation of it, hero mutations too: Registry.item_family / apply_item_looks). An
## entry may carry name, flavour, text (a mutation's), icon, visual, params, noun / nouns (the weapon's thing words,
## TextGen.weapon_nouns), note, shelved and fresh; every key it leaves out is the item's top-level value, and a member
## without an entry for the code wears its top level. An entry whose icon or visual file is not on disk is left out (the
## cards' rule, JsonContent._passive_variants).
##
## A look is worn in place on the def, as PassiveDef.wear_look puts a card's icon on: display_name, flavour, text, icon,
## visual, params, noun and nouns become the look's, so every screen, the cards, TextGen and WeaponInstance.fold_params
## read it without a line of their own. The top level is kept aside in `look_top` the first time a look is worn
## (JsonContent never wears a weapon, so its .tres holds the top level).
## Preloaded where it is used (const ItemLooks := preload(...)): no class_name, so a run before the next --import never
## meets an unknown class; it names no def class either (kind() tells a weapon from a mutation).
extends RefCounted

## `look_worn` before the first wear (no look code is spelt so: codes are [A-Za-z0-9_-]).
const NEVER := "?"
## The words an entry may carry, read as text.
const TEXT_KEYS := ["name", "flavour", "text", "noun", "nouns", "note"]


## `d`'s looks onto `def` (a WeaponDef or a MutationDef): `variants` (each entry resolved by resolve_entry; one naming a
## file that is not on disk is left out), `variant_base` ("A" when the JSON names none) and, on a weapon, `variant` (the
## code its family plays: the JSON's, else the base). Nothing when the JSON has no looks.
static func read(def, d: Dictionary, dir: String) -> void:
	var vs = d.get("variants", {})
	if not (vs is Dictionary) or (vs as Dictionary).is_empty():
		return
	var base := str(d.get("variant_base", "A"))
	if base == "":
		base = "A"
	var all: Dictionary = {}
	for code in (vs as Dictionary).keys():
		var e = resolve_entry((vs as Dictionary)[code], dir)
		if e is Dictionary:
			all[str(code)] = e
	def.variants = all
	def.variant_base = base
	if def.kind() == "weapon":
		var use := str(d.get("variant", base))
		def.variant = use if (use == base or all.has(use)) else base


## One JSON entry as the game wears it: its words, its flags, its `icon` loaded (a Texture2D; `icon_file` the name) and
## its `visual` (a PackedScene; `visual_file`), a copy of its `params`; only the keys the entry has. Null when it is not
## an object or names a file that is not on disk (not imported yet).
static func resolve_entry(v, dir: String):
	if not (v is Dictionary):
		return null
	var src: Dictionary = v
	var e: Dictionary = {}
	for k: String in TEXT_KEYS:
		if src.has(k):
			e[k] = str(src[k])
	for k: String in ["shelved", "fresh"]:
		if src.has(k):
			e[k] = bool(src[k])
	if src.has("icon"):
		var f := str(src["icon"])
		var t = _load(dir, f)
		if not (t is Texture2D):
			return null
		e["icon"] = t
		e["icon_file"] = f
	if src.has("visual"):
		var vf := str(src["visual"])
		var s = _load(dir, vf)
		if not (s is PackedScene):
			return null
		e["visual"] = s
		e["visual_file"] = vf
	if src.get("params") is Dictionary:
		e["params"] = (src["params"] as Dictionary).duplicate(true)
	return e


## A file beside the JSON (or a res:// path) loaded, null when it is not there (JsonContent.resolve_texture's rule).
static func _load(dir: String, file: String) -> Resource:
	if file == "":
		return null
	var path := file if file.begins_with("res://") else dir + file
	if not ResourceLoader.exists(path):
		return null
	return load(path)


## `def`'s top level (its name, flavour, icon, visual, params, a mutation's text, a weapon's nouns), kept aside the first
## time it is asked for: a def fresh from its .tres or its JSON wears its top level.
static func top_of(def) -> Dictionary:
	var t: Dictionary = def.look_top
	if not t.is_empty():
		return t
	t = {"name": def.display_name, "flavour": def.flavour, "icon": def.icon, "icon_file": def.icon_file,
		"visual": def.visual, "visual_file": def.visual_file, "params": def.params}
	if def.kind() == "mutation":
		t["text"] = def.text
	if def.kind() == "weapon":
		t["noun"] = def.noun
		t["nouns"] = def.nouns
	def.look_top = t
	return t


## `def` worn in look `code`: its entry for `code` over its top level (a key the entry lacks is the top level's), or its
## top level alone when it has no entry for `code` ("" included). The params are the top level's with the entry's laid
## over them (overlay). `look_worn` remembers `code` (Registry.apply_item_looks skips a member already in it, and a weapon
## behaviour set up in another look is made again: WeaponBehavior.look_stale). Returns the code of the look worn: `code`
## when it has an entry, else the base.
static func wear(def, code: String) -> String:
	var top := top_of(def)
	var vs: Dictionary = def.variants
	var e: Dictionary = vs[code] if (code != "" and vs.get(code) is Dictionary) else {}
	def.display_name = str(e.get("name", top["name"]))
	def.flavour = str(e.get("flavour", top["flavour"]))
	def.icon = e["icon"] if e.has("icon") else top["icon"]
	def.icon_file = str(e.get("icon_file", top["icon_file"]))
	def.visual = e["visual"] if e.has("visual") else top["visual"]
	def.visual_file = str(e.get("visual_file", top["visual_file"]))
	def.params = overlay(top["params"], e["params"]) if e.get("params") is Dictionary else top["params"]
	if def.kind() == "mutation":
		def.text = str(e.get("text", top.get("text", "")))
	if def.kind() == "weapon":
		def.noun = str(e.get("noun", top.get("noun", "")))
		def.nouns = str(e.get("nouns", top.get("nouns", "")))
	def.look_worn = code
	return code if vs.has(code) else str(def.variant_base)


## A look's params over the top level's, one level deep (keys.md: every key of `over` replaces the key of that name; a
## nested object is replaced whole). Two extras: `final` (an evolution's own block, WeaponInstance.fold_params) is laid
## one level deeper, so a look may change one of its keys and keep the rest; and a null removes the key (`{"final":
## {"tint": null}}` keeps the Golden Pineapple's rules and drops its gold tint). `base` is never written.
static func overlay(base: Dictionary, over: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	for k in over.keys():
		var v = over[k]
		if typeof(v) == TYPE_NIL:
			out.erase(k)
		elif str(k) == "final" and v is Dictionary and out.get("final") is Dictionary:
			var fin: Dictionary = out["final"]
			for fk in (v as Dictionary).keys():
				var fv = (v as Dictionary)[fk]
				if typeof(fv) == TYPE_NIL:
					fin.erase(fk)
				else:
					fin[fk] = _copy(fv)
		else:
			out[k] = _copy(v)
	return out


static func _copy(v):
	return v.duplicate(true) if (v is Dictionary or v is Array) else v


## Every look `def` can play: its base first (its top level, with or without an entry), then its other entries by code;
## a shelved one only when `include_shelved`. Empty when it has no looks.
static func codes(def, include_shelved := false) -> Array:
	var vs: Dictionary = def.variants
	if vs.is_empty():
		return []
	var base := str(def.variant_base)
	var others: Array = []
	for c in vs.keys():
		if str(c) != base:
			others.append(str(c))
	others.sort()
	var out: Array = []
	for c in [base] + others:
		if include_shelved or not shelved(def, str(c)):
			out.append(str(c))
	return out


## Whether look `code` is shelved (out of the arena's chips and the Level Editor's play list); false for a code it lacks.
static func shelved(def, code: String) -> bool:
	var e = (def.variants as Dictionary).get(code)
	return e is Dictionary and bool((e as Dictionary).get("shelved", false))


## A look's note ("" when it has none).
static func note(def, code: String) -> String:
	var e = (def.variants as Dictionary).get(code)
	return str((e as Dictionary).get("note", "")) if e is Dictionary else ""


## The icon `def` shows in look `code`: its entry's own, else its top level's.
static func look_icon(def, code: String) -> Texture2D:
	var e = (def.variants as Dictionary).get(code)
	if e is Dictionary and (e as Dictionary).get("icon") is Texture2D:
		return (e as Dictionary)["icon"]
	return top_of(def)["icon"]


## The name `def` goes by in look `code`: its entry's own, else its top level's.
static func look_name(def, code: String) -> String:
	var e = (def.variants as Dictionary).get(code)
	if e is Dictionary and (e as Dictionary).has("name"):
		return str((e as Dictionary)["name"])
	return str(top_of(def)["name"])


## The code of the look `def` wears now: the one it was last asked to wear when it has an entry for it, else its base; a
## weapon never worn yet reads its JSON's `variant`. "" for an item without looks.
static func code_worn(def) -> String:
	var vs: Dictionary = def.variants
	if vs.is_empty():
		return ""
	var w := str(def.look_worn)
	if w == NEVER:
		w = str(def.variant) if def.kind() == "weapon" else ""
	return w if vs.has(w) else str(def.variant_base)
