## Converts content JSON (the authoring format) into typed Resources.
## Used by tools/import_json.gd to write .tres files, and by Registry as a runtime fallback
## when a folder has JSON but no .tres yet.
class_name JsonContent
extends RefCounted

const TYPES := ["weapons", "evolutions", "passives", "mutations", "perks", "enemies", "bosses", "elites", "characters", "talents", "quests", "maps", "pickups", "structures", "boss_attacks"]
## Pass 76 (lane LOOKS): the weapon families' looks, preloaded (it has no class_name: see its header).
const ItemLooks := preload("res://core/data/ItemLooks.gd")


static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if parsed is Dictionary:
		return parsed
	push_error("JsonContent: %s is not a JSON object" % path)
	return {}


static func build(type: String, d: Dictionary, dir: String) -> ContentDef:
	var res: ContentDef = null
	match type:
		"weapons", "evolutions":
			res = _weapon(d, dir, type == "evolutions")
		"passives":
			res = _passive(d, dir)
		"mutations":
			res = _mutation(d, dir)
		"perks":
			res = _perk(d, dir)
		"enemies", "bosses":
			res = _enemy(d, dir)
		"elites":
			res = _elite(d, dir)
		"characters":
			res = _character(d, dir)
		"talents":
			res = _talent(d, dir)
		"quests":
			res = _quest(d, dir)
		"maps":
			res = _map(d, dir)
		"pickups":
			res = _pickup(d, dir)
		"structures":
			res = _structure(d, dir)
		"buildings":
			res = _building(d, dir)
		"boss_attacks":
			# pass 72 (lane BOSS): a custom boss attack
			res = _boss_attack(d)
		_:
			push_error("JsonContent: unknown type %s" % type)
			return null
	_common(res, d, dir)
	# a creature playing another art variant than its top-level one shows that variant's icon too
	if res is EnemyDef:
		var ed := res as EnemyDef
		if ed.variant != "" and ed.variants.has(ed.variant) and ed.variants[ed.variant].get("icon") != null:
			ed.icon = ed.variants[ed.variant]["icon"]
	# and a hero playing a look with its own badge shows that one (pass 55, the same rule)
	if res is CharacterDef:
		var cd := res as CharacterDef
		if cd.variant != "" and cd.variants.has(cd.variant) and cd.variants[cd.variant].get("icon") != null:
			cd.icon = cd.variants[cd.variant]["icon"]
		# pass 66: an availability other than "available" ("hidden", "purchase") keeps him hidden, whatever `hidden` says.
		# Pass 69 (the purchase loop is wired): "hidden" hides him; "purchase" shows him on the title, locked or on sale
		# (Registry.hero_state), whatever `hidden` says; "available" with `hidden: true` stays hidden (hidden wins there)
		cd.hidden = cd.availability == "hidden" or (cd.hidden and cd.availability != "purchase")
	# pass 73 (lane CARDS): an item playing a look (a card's B-E) shows that look's icon (PassiveDef.wear_look)
	if res is PassiveDef:
		(res as PassiveDef).wear_look("")
	# pass 76 (lane LOOKS): a weapon family's looks (ItemLooks), read but not worn: the def keeps its top level (the .tres
	# too), Registry.apply_item_looks puts the family's look on
	if res is WeaponDef or res is MutationDef:
		ItemLooks.read(res, d, dir)
	return res


static func _common(res: ContentDef, d: Dictionary, dir: String) -> void:
	res.id = str(d.get("id", ""))
	res.display_name = str(d.get("name", res.id.capitalize()))
	res.flavour = str(d.get("flavour", ""))
	res.rarity = str(d.get("rarity", "common"))
	res.element = str(d.get("element", ""))
	res.weight = float(d.get("weight", 10.0))
	res.hidden = bool(d.get("hidden", false))
	res.from_stage = int(d.get("from_stage", 0))
	res.icon_file = str(d.get("icon", res.id + "_icon.png"))
	res.icon = resolve_texture(dir, res.icon_file)
	var ph = d.get("placeholder", {})
	res.placeholder = ph if ph is Dictionary else {}
	res.source_dir = dir


static func effects_list(arr, default_target: String = "self") -> Array:
	var out: Array = []
	if arr is Array:
		for e in arr:
			if e is Dictionary:
				out.append(Effect.from_dict(e, default_target))
	return out


static func levels_list(arr, default_target: String = "self") -> Array:
	var out: Array = []
	if arr is Array:
		for lv in arr:
			out.append(effects_list(lv, default_target))
	return out


static func resolve_texture(dir: String, file: String) -> Texture2D:
	if file == "":
		return null
	var path := file if file.begins_with("res://") else dir + file
	if ResourceLoader.exists(path):
		var t = load(path)
		if t is Texture2D:
			return t
	return null


static func resolve_scene(dir: String, file: String) -> PackedScene:
	if file == "":
		return null
	var path := file if file.begins_with("res://") else dir + file
	if ResourceLoader.exists(path):
		var s = load(path)
		if s is PackedScene:
			return s
	return null


static func _weapon(d: Dictionary, dir: String, is_evo: bool) -> WeaponDef:
	var w := WeaponDef.new()
	w.behavior = str(d.get("behavior", "ProjectileEmitter"))
	w.targeting = str(d.get("targeting", "nearest"))
	var b = d.get("base", {})
	w.base = b if b is Dictionary else {}
	w.levels = levels_list(d.get("levels", []), "self")
	w.max_level = int(d.get("max_level", 8))
	var tg = d.get("tags", [])
	w.tags = tg if tg is Array else []
	w.evolves_with = str(d.get("evolves_with", ""))
	w.evolves_into = str(d.get("evolves_into", ""))
	w.is_evolution = bool(d.get("is_evolution", is_evo))
	w.evolved_from = str(d.get("evolved_from", ""))
	var s = d.get("sfx", {})
	w.sfx = s if s is Dictionary else {}
	var p = d.get("params", {})
	w.params = p if p is Dictionary else {}
	w.visual_file = str(d.get("visual", str(d.get("id", "")) + "_visual.tscn"))
	w.visual = resolve_scene(dir, w.visual_file)
	w.hero = str(d.get("hero", ""))
	# pass 76 (lane LOOKS): the base look's thing words for TextGen ("" = the behaviour's own)
	w.noun = str(d.get("noun", ""))
	w.nouns = str(d.get("nouns", ""))
	return w


## A passive (pass 46: the lines folded in, so a passive may carry a trade, an evolution pair and its own card text).
static func _passive(d: Dictionary, dir: String) -> PassiveDef:
	var p := PassiveDef.new()
	p.levels = levels_list(d.get("levels", []), "player")
	p.repeat_last_level = bool(d.get("repeat_last_level", true))
	p.max_level = int(d.get("max_level", 8))
	p.pairs_with = str(d.get("pairs_with", ""))
	p.trade = str(d.get("trade", ""))
	p.evolves_into = str(d.get("evolves_into", ""))
	p.evolves_from = str(d.get("evolves_from", ""))
	p.text = str(d.get("text", ""))
	# pass 47: a line item (four levels, an evolution, one of six slots) or a passive item (no cap, off the HUD)
	p.line = bool(d.get("line", false))
	# pass 73 (lane CARDS): its looks (the cards' A-E)
	_passive_variants(p, d, dir)
	return p


## An item's looks (pass 73, lane CARDS; the heroes' scheme of pass 55 for icons alone): `variant_base` names the look
## whose icon is the top-level `icon` (or <id>_icon.png), every other entry names its own `icon` file; an entry whose file
## is not on disk yet is left out. `variant` is the look the game plays (build() puts its icon on; a phone's kept card look,
## Registry.apply_card_looks, wins over it). An entry may carry a `recipe` (the words it was painted from): the game skips it.
static func _passive_variants(p: PassiveDef, d: Dictionary, dir: String) -> void:
	var vs = d.get("variants", {})
	if not (vs is Dictionary) or (vs as Dictionary).is_empty():
		return
	var base_code := str(d.get("variant_base", ""))
	var base_file := str(d.get("icon", str(d.get("id", "")) + "_icon.png"))
	var base_icon: Texture2D = resolve_texture(dir, base_file)
	var all: Dictionary = {}
	for code in (vs as Dictionary).keys():
		var v = vs[code]
		if not (v is Dictionary):
			continue
		var e: Dictionary = v
		var file := str(e.get("icon", ""))
		var tex: Texture2D = resolve_texture(dir, file) if file != "" else null
		if str(code) == base_code and tex == null:
			file = base_file
			tex = base_icon
		if tex == null:
			continue
		all[str(code)] = {"icon": tex, "icon_file": file, "note": str(e.get("note", "")), "shelved": bool(e.get("shelved", false))}
	if base_code != "" and not all.has(base_code) and base_icon != null:
		all[base_code] = {"icon": base_icon, "icon_file": base_file, "note": "", "shelved": false}
	if all.is_empty():
		return
	p.variants = all
	p.variant_base = base_code
	var use := str(d.get("variant", base_code))
	p.variant = use if all.has(use) else (base_code if all.has(base_code) else "")


static func _mutation(d: Dictionary, dir: String) -> MutationDef:
	var m := MutationDef.new()
	m.weapon = str(d.get("weapon", ""))
	m.mutation_kind = str(d.get("kind", "motion"))
	m.hero = str(d.get("hero", ""))
	m.text = str(d.get("text", ""))
	m.vfx = str(d.get("vfx", ""))
	m.effects = effects_list(d.get("effects", []), "self")
	var pr = d.get("params", {})
	m.params = pr if pr is Dictionary else {}
	m.behavior = str(d.get("behavior", ""))
	m.visual_file = str(d.get("visual", ""))
	if m.visual_file != "":
		m.visual = resolve_scene(dir, m.visual_file)
	return m



static func _perk(d: Dictionary, dir: String) -> PerkDef:
	var p := PerkDef.new()
	p.hero = str(d.get("hero", ""))
	p.text = str(d.get("text", ""))
	p.effects = effects_list(d.get("effects", []), "player")
	p.special = str(d.get("special", ""))
	var pr = d.get("params", {})
	p.params = pr if pr is Dictionary else {}
	return p


static func _enemy(d: Dictionary, dir: String) -> EnemyDef:
	var e := EnemyDef.new()
	e.archetype = str(d.get("archetype", "walker"))
	e.doc = str(d.get("doc", ""))
	e.brain = str(d.get("brain", "chase"))
	e.hp = float(d.get("hp", 10.0))
	e.speed = float(d.get("speed", 2.5))
	e.damage = float(d.get("damage", 5.0))
	e.radius = float(d.get("radius", 0.5))
	e.size = float(d.get("size", 1.0))
	e.pack_size = int(d.get("pack_size", 1))
	var dr = d.get("drops", {"small": 1.0, "gold": 0.02})
	e.drops = dr if dr is Dictionary else {}
	var an = d.get("anims", {"idle": 2, "run": 2, "attack": 2, "hit": 1, "die": 1})
	e.anims = an if an is Dictionary else {}
	e.frame_px = int(d.get("frame_px", 128))
	e.strip_cols = int(d.get("strip_cols", 0))
	var fp = d.get("fps", {})
	e.fps = fp if fp is Dictionary else {}
	e.sprite_file = str(d.get("sprite", str(d.get("id", "")) + "_sprite.png"))
	e.sprite = resolve_texture(dir, e.sprite_file)
	var r = d.get("ranged", {})
	e.ranged = r if r is Dictionary else {}
	var c = d.get("charge", {})
	e.charge = c if c is Dictionary else {}
	e.damage_reduction = clampf(float(d.get("damage_reduction", 0.0)), 0.0, 0.9)
	# pass 54: the shove the hero takes from its bite, m/s (0 = EnemyDef.default_knockback from its damage)
	e.knockback = maxf(float(d.get("knockback", 0.0)), 0.0)
	# pass 67: the share of the hero's knockback it shrugs off, 0..1 (the Hammer Giant 0.67); the other way round from the
	# bite's shove above
	e.knockback_resist = clampf(float(d.get("knockback_resist", 0.0)), 0.0, 1.0)
	e.max_alive = int(d.get("max_alive", 0))
	e.cap_share = float(d.get("cap_share", 1.0))
	# pass 53 (the wave schema): the bite's cadence and the creature's own power-up roll
	e.contact_cd = maxf(float(d.get("contact_cd", 0.6)), 0.05)
	e.pickup_chance_mult = maxf(float(d.get("pickup_chance_mult", 1.0)), 0.0)
	var pw = d.get("pickup_weights", {})
	e.pickup_weights = pw if pw is Dictionary else {}
	e.badge = str(d.get("badge", ""))
	e.head = float(d.get("head", 0.86))
	e.front_faces = str(d.get("front_faces", "right"))
	e.back_faces = str(d.get("back_faces", "right"))
	e.retired = bool(d.get("retired", false))
	# the blob shadow's tuning (pass 47: the Dune Scorpion floated over its shadow); a variant entry may carry its own
	var sh = d.get("shadow", {})
	e.shadow = sh if sh is Dictionary else {}
	# the death splash's colour (pass 58): "#rrggbb", red when missing or unreadable
	var bl := str(d.get("blood", ""))
	if bl != "" and Color.html_is_valid(bl):
		e.blood = Color.html(bl)
	# art variants (pass 34): the top-level strip is `variant_base`'s; each other entry names its own strip (and icon). The
	# code in `variant` is the art the game plays, so switching variants is one word in the JSON. (_common loads the icon
	# after this, so the base icon is resolved here, and build() puts the chosen variant's back.)
	var vs = d.get("variants", {})
	if vs is Dictionary and not vs.is_empty():
		var base_code := str(d.get("variant_base", ""))
		var base_icon: Texture2D = resolve_texture(dir, str(d.get("icon", str(d.get("id", "")) + "_icon.png")))
		var all: Dictionary = {}
		if base_code != "":
			var bnote = vs.get(base_code, {})
			var bn: Dictionary = bnote if bnote is Dictionary else {}
			all[base_code] = {"sprite": e.sprite, "sprite_file": e.sprite_file, "anims": e.anims, "fps": e.fps, "strip_cols": e.strip_cols,
				"head": e.head, "icon": base_icon, "note": str(bn.get("note", "")),
				"front_faces": str(bn.get("front_faces", e.front_faces)), "back_faces": str(bn.get("back_faces", e.back_faces)),
				"shadow": bn["shadow"] if bn.get("shadow") is Dictionary else e.shadow, "shelved": bool(bn.get("shelved", false))}
		for code in vs.keys():
			var v = vs[code]
			if code == base_code or not v is Dictionary or not v.has("sprite"):
				continue
			var tex := resolve_texture(dir, str(v["sprite"]))
			if tex == null:
				continue
			var van = v.get("anims", e.anims)
			var vfp = v.get("fps", e.fps)
			# a variant's own icon (its own painting), else the creature's
			var vicon: Texture2D = resolve_texture(dir, str(v["icon"])) if v.has("icon") else null
			# its facing (pass 46): a painting that turns the other way says so in its own entry (`front_faces` /
			# `back_faces`, EnemyDef), else it faces like the top-level strip. `shelved` (pass 66, the Level Editor's
			# looks): out of variant_codes() and so of the arena chips and the default lists; variant_def still wears it.
			all[str(code)] = {"sprite": tex, "sprite_file": str(v["sprite"]), "anims": van if van is Dictionary else e.anims,
				"fps": vfp if vfp is Dictionary else e.fps, "strip_cols": int(v.get("strip_cols", 0)), "head": float(v.get("head", e.head)),
				"icon": vicon if vicon else base_icon, "note": str(v.get("note", "")),
				"front_faces": str(v.get("front_faces", e.front_faces)), "back_faces": str(v.get("back_faces", e.back_faces)),
				"shadow": v["shadow"] if v.get("shadow") is Dictionary else e.shadow, "shelved": bool(v.get("shelved", false))}
		e.variants = all
		var use := str(d.get("variant", base_code))
		e.variant = use if all.has(use) else base_code
		if e.variant != base_code and all.has(e.variant):
			e.apply_art(all[e.variant])
		elif all.has(e.variant):
			# the base strip's own entry may state its facing too
			e.front_faces = str(all[e.variant].get("front_faces", e.front_faces))
			e.back_faces = str(all[e.variant].get("back_faces", e.back_faces))
	e.can_be_elite = bool(d.get("can_be_elite", true))
	e.can_be_grabbed = bool(d.get("can_be_grabbed", true))
	var km = d.get("kamikaze", {})
	e.kamikaze = km if km is Dictionary else {}
	var art = d.get("artillery", {})
	e.artillery = art if art is Dictionary else {}
	# pass 73 (lane SNIPER): the sniper brain's block, any creature's flee on hit, the attack strip's two views
	var snp = d.get("sniper", {})
	e.sniper = snp if snp is Dictionary else {}
	var foh = d.get("flee_on_hit", {})
	e.flee_on_hit = foh if foh is Dictionary else {}
	e.attack_views = str(d.get("attack_views", ""))
	var am = d.get("ambush", {})
	e.ambush = am if am is Dictionary else {}
	var su = d.get("support", {})
	e.support = su if su is Dictionary else {}
	var dbst = d.get("death_burst", {})
	e.death_burst = dbst if dbst is Dictionary else {}
	var ca = d.get("caster", {})
	e.caster = ca if ca is Dictionary else {}
	var b = d.get("boss", {})
	e.boss = b if b is Dictionary else {}
	var el = d.get("elite", {})
	e.elite = el if el is Dictionary else {}
	var s = d.get("sfx", {})
	e.sfx = s if s is Dictionary else {}
	e.xp_mult = float(d.get("xp_mult", 1.0))
	var vr = d.get("variance", {})
	e.variance = vr if vr is Dictionary else {}
	return e


static func _elite(d: Dictionary, dir: String) -> EliteModDef:
	var m := EliteModDef.new()
	m.effects = effects_list(d.get("effects", []), "self")
	m.outline = Color(str(d.get("outline", "#FFFFFF")))
	m.scale_mult = float(d.get("scale_mult", 1.5))
	m.on_death = str(d.get("on_death", "none"))
	var p = d.get("params", {})
	m.params = p if p is Dictionary else {}
	return m


static func _character(d: Dictionary, dir: String) -> CharacterDef:
	var c := CharacterDef.new()
	c.trait_effects = effects_list(d.get("trait", []), "player")
	# the signature stat a level (pass 61): what one level gives, folded as value x level by Run._build_player_sheet
	c.level_trait = effects_list(d.get("trait_per_level", []), "player")
	c.order = int(d.get("order", 100))
	c.trait_name = str(d.get("trait_name", ""))
	c.trait_text = str(d.get("trait_text", ""))
	c.pronoun = str(d.get("pronoun", "they"))
	c.level_heal = float(d.get("level_heal", 0.0))
	c.favourite_weapon = str(d.get("favourite_weapon", ""))
	c.start_weapon = str(d.get("start_weapon", ""))
	var fb = d.get("favourite_bonus", {})
	c.favourite_bonus = fb.duplicate() if fb is Dictionary else {}
	if c.favourite_bonus.has("effects"):
		c.favourite_bonus["effects"] = effects_list(c.favourite_bonus["effects"], "self")
	# a favourite passive (pass 46: Ironwood's Cake) and what finding it gives, the same shape as favourite_bonus
	c.favourite_passive = str(d.get("favourite_passive", ""))
	var fpb = d.get("favourite_passive_bonus", {})
	c.favourite_passive_bonus = fpb.duplicate() if fpb is Dictionary else {}
	if c.favourite_passive_bonus.has("effects"):
		c.favourite_passive_bonus["effects"] = effects_list(c.favourite_passive_bonus["effects"], "player")
	var sp = d.get("specials", [])
	c.specials = sp if sp is Array else []
	var mo = d.get("momentum", {})
	c.momentum = mo if mo is Dictionary else {}
	c.unlock_quest = str(d.get("unlock_quest", ""))
	# pass 66 (the Level Editor's Heroes tab): `availability` "hidden" | "available" | "purchase", derived from `hidden`
	# when absent; anything but "available" keeps him out of play (a "purchase" hero stays hidden until the loop is
	# wired, BALANCING §13): build() folds it into `hidden` after _common has read the flag. `price` in `currency_type`
	# is written and shown nowhere yet.
	var avail := str(d.get("availability", ""))
	if avail == "":
		avail = "hidden" if bool(d.get("hidden", false)) else "available"
	c.availability = avail
	c.price = maxi(int(d.get("price", 0)), 0)
	c.currency_type = str(d.get("currency_type", "gold"))
	c.frame_px = int(d.get("frame_px", 256))
	c.strip_cols = int(d.get("strip_cols", 0))
	var fp = d.get("fps", {})
	c.fps = fp if fp is Dictionary else {}
	var an = d.get("anims", {"idle": 2, "run": 4, "turn": 1, "hit": 1, "die": 1, "cheer": 1})
	c.anims = an if an is Dictionary else {}
	c.sprite_file = str(d.get("sprite", str(d.get("id", "")) + "_sprite.png"))
	c.sprite = resolve_texture(dir, c.sprite_file)
	_character_variants(c, d, dir)
	return c


## A hero's art variants (pass 55, the creatures' scheme of pass 34 in _enemy): `variant_base` names the top-level strip,
## unless its entry names a strip of its own; every other entry names its strip, and one whose strip is not there yet is
## left out. `variant` is the look the game plays (the player's kept look, Save.hero_look, wins over it), so switching
## is one word in the JSON. The base entry carries the hero's own icon, the others their own or his (_common loads the
## icon after this, so it is resolved here, and build() puts the playing look's back). Every entry carries its `title`
## (pass 68: the look's own title cut-out, a file name under res://art/ui/wanted/; "" = the hero's hero_<id>.png), which
## CharacterDef.title_path reads for the look worn.
static func _character_variants(c: CharacterDef, d: Dictionary, dir: String) -> void:
	var vs = d.get("variants", {})
	if not (vs is Dictionary) or (vs as Dictionary).is_empty():
		return
	var base_code := str(d.get("variant_base", ""))
	var base_icon: Texture2D = resolve_texture(dir, str(d.get("icon", str(d.get("id", "")) + "_icon.png")))
	var top := {"sprite": c.sprite, "sprite_file": c.sprite_file, "anims": c.anims, "fps": c.fps, "strip_cols": c.strip_cols,
		"frame_px": c.frame_px, "icon": base_icon, "title": "", "note": "", "shelved": false}
	var all: Dictionary = {}
	for code in vs.keys():
		var v = vs[code]
		if not (v is Dictionary):
			continue
		var e: Dictionary = v
		var tex: Texture2D = resolve_texture(dir, str(e["sprite"])) if e.has("sprite") else null
		if tex == null:
			# no strip of its own (or not painted yet): the base look is the top-level strip, any other is left out
			if str(code) == base_code:
				var b := top.duplicate()
				b["note"] = str(e.get("note", ""))
				b["shelved"] = bool(e.get("shelved", false))
				b["title"] = str(e.get("title", ""))
				all[str(code)] = b
			continue
		var van = e.get("anims", c.anims)
		var vfp = e.get("fps", c.fps)
		var vicon: Texture2D = resolve_texture(dir, str(e["icon"])) if e.has("icon") else null
		# `shelved` (pass 66, the Level Editor's looks): out of variant_codes() and the arena chips, worn when named
		all[str(code)] = {"sprite": tex, "sprite_file": str(e["sprite"]), "anims": van if van is Dictionary else c.anims,
			"fps": vfp if vfp is Dictionary else c.fps, "strip_cols": int(e.get("strip_cols", 0)),
			"frame_px": int(e.get("frame_px", c.frame_px)), "icon": vicon if vicon else base_icon,
			"title": str(e.get("title", "")), "note": str(e.get("note", "")), "shelved": bool(e.get("shelved", false))}
	if base_code != "" and not all.has(base_code):
		all[base_code] = top
	if all.is_empty():
		return
	c.variants = all
	var use := str(d.get("variant", base_code))
	c.variant = use if all.has(use) else (base_code if all.has(base_code) else "")
	if c.variant != "":
		c.apply_art(all[c.variant])


static func _shop(d: Dictionary, dir: String) -> ShopUpgradeDef:
	var s := ShopUpgradeDef.new()
	var e = d.get("effect", {})
	if e is Dictionary and not e.is_empty():
		s.effect_per_tier = Effect.from_dict(e, "player")
	var costs = d.get("costs", [])
	s.costs = costs if costs is Array else []
	s.order = int(d.get("order", 0))
	s.effect_text = str(d.get("effect_text", ""))
	return s


static func _quest(d: Dictionary, dir: String) -> QuestDef:
	var q := QuestDef.new()
	var c = d.get("condition", {})
	q.condition = c if c is Dictionary else {}
	var u = d.get("unlocks", {})
	q.unlocks = u if u is Dictionary else {}
	q.quest_text = str(d.get("quest_text", ""))
	return q


static func _map(d: Dictionary, dir: String) -> MapDef:
	var m := MapDef.new()
	m.scene_file = str(d.get("scene", ""))
	m.scene = resolve_scene(dir, m.scene_file)
	m.timeline_file = str(d.get("timeline", ""))
	var tl = d.get("timeline_data", {})
	if tl is Dictionary and not tl.is_empty():
		m.timeline = timeline_from_dict(tl)
	var sk = d.get("skins", {})
	m.skins = sk if sk is Dictionary else {}
	# pass 67: the grade the weapon models get under this map's light (WeaponBehavior.grade_materials)
	var wg = d.get("weapon_grade", {})
	m.weapon_grade = wg if wg is Dictionary else {}
	m.boss = str(d.get("boss", ""))
	m.unlock_quest = str(d.get("unlock_quest", ""))
	var mu = d.get("music", {})
	if mu is Dictionary and not mu.is_empty():
		m.music = mu
	return m


static func _talent(d: Dictionary, dir: String) -> TalentDef:
	var t := TalentDef.new()
	t.order = int(d.get("order", 0))
	t.ranks = int(d.get("ranks", 3))
	var c = d.get("cost", [])
	t.cost = c if c is Array else []
	var forms: Array = []
	var tid := str(d.get("id", ""))
	for f in (d.get("forms", []) as Array):
		if not (f is Dictionary):
			continue
		var form := {"name": str(f.get("name", "")), "text": str(f.get("text", "")),
			"effects": effects_list(f.get("effects", []), "player")}
		# the form's own icon (pass 61, the Upgrade board's rank bars): `icon` in the form, else <id>_<form>_icon.png in the
		# talent's folder; absent, the board draws the form's initial
		var ifile := str(f.get("icon", "%s_%d_icon.png" % [tid, forms.size()]))
		form["icon_file"] = ifile
		var itex := resolve_texture(dir, ifile)
		if itex:
			form["icon"] = itex
		# one effect list a rank (pass 46), when the ranks are not all the same step
		var re = f.get("rank_effects", [])
		if re is Array and not (re as Array).is_empty():
			form["rank_effects"] = levels_list(re, "player")
		forms.append(form)
	t.forms = forms
	return t


static func _pickup(d: Dictionary, dir: String) -> PickupDef:
	var p := PickupDef.new()
	p.effect_kind = str(d.get("effect", "heal"))
	p.value = float(d.get("value", 0.3))
	p.duration = float(d.get("duration", 0.0))
	p.effects = effects_list(d.get("effects", []), "player")
	p.lifetime = float(d.get("lifetime", 20.0))
	p.color = Color(str(d.get("color", "#FFFFFF")))
	var pp = d.get("params", {})   # pickup params
	p.params = pp if pp is Dictionary else {}
	return p


static func _structure(d: Dictionary, dir: String) -> StructureDef:
	var st := StructureDef.new()
	st.effect_kind = str(d.get("effect", "heal"))
	var pr = d.get("params", {})
	st.params = pr if pr is Dictionary else {}
	st.effects = effects_list(st.params.get("effects", []), "player")
	st.radius = float(d.get("radius", 2.2))
	st.interact_time = float(d.get("interact_time", 3.0))
	st.color = Color(str(d.get("color", "#FFFFFF")))
	st.prop = str(d.get("prop", ""))
	st.height = float(d.get("height", 2.0))
	return st


static func _building_farm(b: BuildingDef, d: Dictionary) -> void:
	b.produces = str(d.get("produces", ""))
	var ys = d.get("yield", [])
	b.yields = ys if ys is Array else []
	b.is_market = bool(d.get("market", false))
	var rt = d.get("rates", {})
	b.rates = rt if rt is Dictionary else {}
	var rm = d.get("rate_mult", [1.0])
	b.rate_mult = rm if rm is Array else [1.0]


static func _building(d: Dictionary, _dir: String) -> BuildingDef:
	var b := BuildingDef.new()
	b.order = int(d.get("order", 0))
	var un = d.get("unlocks", [])
	b.unlocks = un if un is Array else []
	var lv = d.get("levels", [])
	b.levels = lv if lv is Array else []
	b.look = str(d.get("look", ""))
	_building_farm(b, d)
	return b


## Pass 72 (lane BOSS): a custom boss attack (content/boss_attacks/<id>/<id>.json, BossAttackDef). Each group is read
## as the file has it (a key it leaves out plays BossAttackDef.DEFAULTS); a group that is not an object reads as empty.
static func _boss_attack(d: Dictionary) -> BossAttackDef:
	var a := BossAttackDef.new()
	a.attack_kind = str(d.get("kind", "rain"))
	a.doc = str(d.get("doc", ""))
	for g: String in ["projectile", "pattern", "landing", "telegraph", "timing", "sounds", "params", "spew"]:
		var v = d.get(g, {})
		a.set(g, (v as Dictionary).duplicate(true) if v is Dictionary else {})
	a.damage = float(d.get("damage", 0.75))
	a.knockback = float(d.get("knockback", 4.0))
	a.lift = float(d.get("lift", 0.0))
	a.script_name = str(d.get("script", ""))
	return a


static func timeline_from_dict(t: Dictionary) -> WaveTimeline:
	var w := WaveTimeline.new()
	w.stage_length = float(t.get("stage_length", 300.0))
	w.stages = int(t.get("stages", 3))
	var sm = t.get("stage_mults", [1.0, 1.35, 1.8])
	w.stage_mults = sm if sm is Array else [1.0]
	w.endless_mult_per_minute = float(t.get("endless_mult_per_minute", 0.0))
	w.endless_wave_seconds = float(t.get("endless_wave_seconds", 60.0))
	w.endless_wave_mult = float(t.get("endless_wave_mult", 1.0))
	var hc = t.get("hell_cap", [])
	w.hell_cap = hc if hc is Array else []
	w.cap_per_stage = int(t.get("cap_per_stage", 0))
	w.speed_per_stage = float(t.get("speed_per_stage", 0.0))
	w.cap_start = int(t.get("cap_start", 100))
	w.cap_per_minute = float(t.get("cap_per_minute", 10.0))
	w.cap_max = int(t.get("cap_max", 250))
	w.hard_cap = int(t.get("hard_cap", 300))
	var cc = t.get("cap_curve", [])
	w.cap_curve = cc if cc is Array else []
	w.boss_cap_frac = float(t.get("boss_cap_frac", 0.3))
	w.portal_cap = int(t.get("portal_cap", 10))
	w.portal_spawn_seconds = float(t.get("portal_spawn_seconds", 30.0))
	var spc = t.get("specials", {})
	w.specials = spc if spc is Dictionary else {}
	w.hp_growth = float(t.get("hp_growth", 0.08))
	w.hp_power = float(t.get("hp_power", 1.2))
	w.burst_min = int(t.get("burst_min", 5))
	w.burst_max = int(t.get("burst_max", 20))
	w.spawn_interval = float(t.get("spawn_interval", 0.5))
	w.level_hp_per_level = float(t.get("level_hp_per_level", 0.0))
	w.level_damage_per_level = float(t.get("level_damage_per_level", 0.0))
	var ro = t.get("roster", [])
	w.weight_late_t = float(t.get("weight_late_t", 600.0))
	w.roster = ro if ro is Array else []
	var ev = t.get("events", [])
	w.events = ev if ev is Array else []
	# pass 53: explicit wave windows on top of the roster (docs/waves_schema.md), read by WaveDirector as plain dictionaries
	var wv = t.get("waves", [])
	w.waves = wv if wv is Array else []
	var pk = t.get("pickups", {})
	w.pickups = pk if pk is Dictionary else {}
	var stc = t.get("structures", {})
	w.structures = stc if stc is Dictionary else {}
	# pass 47: six weapon slots and six line slots all run (Garry: "keep that static"); the run no longer reads these,
	# the HUD still lays its padlocks from them, so a map that names none has six of each from the start
	var wc = t.get("weapon_cap", [5, 5, 5])
	w.weapon_cap = wc if wc is Array else [5, 5, 5]
	var pc = t.get("passive_cap", [5, 5, 5])
	w.passive_cap = pc if pc is Array else [5, 5, 5]
	w.colour_after_kills = int(t.get("colour_after_kills", 0))
	w.creature_hp_mult = float(t.get("creature_hp_mult", 1.0))
	# pass 54: every hostile damage times this, the spawn sides, and the HP and damage curves (blocks read as they are)
	w.creature_damage_mult = float(t.get("creature_damage_mult", 1.0))
	# pass 60: every creature's, Elite's, boss's and hostile shot's pace times this (never the hero's)
	w.creature_speed_mult = float(t.get("creature_speed_mult", 1.0))
	# pass 72 (lane ITEMS): every push the hero's side gives a creature times this (EnemyManager.hero_knock_mult)
	# (lane INTEG: a map that names none halves, WaveTimeline.HERO_KNOCKBACK_DEFAULT)
	w.hero_knockback_mult = float(t.get("hero_knockback_mult", WaveTimeline.HERO_KNOCKBACK_DEFAULT))
	# pass 69 (lane EN): the map's fallbacks for a variance special's numbers (read as they are)
	var spd = t.get("special_defaults", {})
	w.special_defaults = spd if spd is Dictionary else {}
	var ss = t.get("spawn_sides", {})
	w.spawn_sides = ss if ss is Dictionary else {}
	var hcv = t.get("hp_curve", {})
	w.hp_curve = hcv if hcv is Dictionary else {}
	var dcv = t.get("damage_curve", {})
	w.damage_curve = dcv if dcv is Dictionary else {}
	w.contact_cap = float(t.get("contact_cap", 0.0))
	w.xp_need_mult = float(t.get("xp_need_mult", 1.0))
	# pass 82 (lane XP): the XP growth type (read as it is; XpCurve's defaults fill gaps, {} = today's curve)
	var xpc = t.get("xp_curve", {})
	w.xp_curve = xpc if xpc is Dictionary else {}
	# pass 79 (lane MUT): whether mutation level-ups count for the level scaling (Run.card_level)
	w.mutation_levels_scale = bool(t.get("mutation_levels_scale", false))
	# pass 48: the pace knob and the portal wait's wave (WaveTimeline)
	w.move_pace = float(t.get("move_pace", 1.0))
	var pw = t.get("portal_wave", {})
	w.portal_wave = pw if pw is Dictionary else {}
	# pass 72 (lane BOSS): boss HP pegged to the hero's DPS (read as it is; WaveTimeline.boss_hp_mult)
	var bhs = t.get("boss_hp_scaling", {})
	w.boss_hp_scaling = bhs if bhs is Dictionary else {}
	# pass 83 (lane SCALE): enemy HP by the hero's power (WaveTimeline.power_hp_factor; 1 = none)
	w.power_hp_scaling = float(t.get("power_hp_scaling", WaveTimeline.POWER_HP_SCALING_DEFAULT))
	w.power_hp_max = float(t.get("power_hp_max", WaveTimeline.POWER_HP_MAX_DEFAULT))
	# pass 73 (lane SNIPER): the weapons' target priority (read as it is; WaveTimeline.TARGET_PRIORITY_DEFAULTS fill gaps)
	var tpr = t.get("target_priority", {})
	w.target_priority = tpr if tpr is Dictionary else {}
	# pass 73 (lane GROUND): growing out of the ground (read as it is; WaveTimeline.SPAWN_RISE_DEFAULTS fill gaps)
	var srs = t.get("spawn_rise", {})
	w.spawn_rise = srs if srs is Dictionary else {}
	# pass 79 (lane WORLD): the rim's rock colour and the walls' colours (read as they are; RedCanyon's defaults fill gaps)
	w.rock_color = str(t.get("rock_color", ""))
	var wcs = t.get("wall_colors", {})
	w.wall_colors = wcs if wcs is Dictionary else {}
	# pass 82 (lane SAND): which sand the ground is painted with (an id of RedCanyon.SANDS; "" = the default)
	w.sand = str(t.get("sand", ""))
	# pass 80 (lane OASIS): the water's slow and the oases' count (WaveTimeline's defaults fill gaps)
	w.water_slow = float(t.get("water_slow", WaveTimeline.WATER_SLOW_DEFAULT))
	var oas = t.get("oases", {})
	w.oases = oas if oas is Dictionary else {}
	var pt = t.get("path_times", [[55, 115, 175, 230, 270], [35, 90, 145, 200, 245, 280]])
	w.path_times = pt if pt is Array else []
	return w


static func soundmap_from_dict(d: Dictionary, dir: String) -> SoundMap:
	var sm := SoundMap.new()
	var entries = d.get("sounds", {})
	if entries is Dictionary:
		for id in entries.keys():
			var e = entries[id]
			if not (e is Dictionary):
				continue
			var row := {
				"file": str(e.get("file", "placeholder/%s.wav" % id)),
				"category": str(e.get("category", "sfx")),
				"voices": int(e.get("voices", 4)),
				"pitch_spread": float(e.get("pitch_spread", 0.05)),
				"volume_db": float(e.get("volume_db", 0.0)),
				"loop": bool(e.get("loop", false)),
				"stream": null,
			}
			# pass 65: a rising pitch over quick repeats (the gems' dings) and a least gap between plays (the hero's hurt);
			# pass 67: the least ms a step of the ladder lasts
			for k in ["chain_step", "chain_window", "chain_max", "min_gap", "chain_min_ms"]:
				if e.has(k):
					row[k] = float(e[k])
			# pass 67, the gem tune (Audio.chain_pitch): the ladder of semitone offsets, the counter a family shares, the
			# top's rule (hold | wrap)
			if e.get("ladder") is Array:
				var ladder: Array = []
				for v in e["ladder"]:
					ladder.append(float(v))
				row["ladder"] = ladder
			for k in ["chain_group", "chain_end"]:
				if e.has(k):
					row[k] = str(e[k])
			var path: String = row["file"] if row["file"].begins_with("res://") else dir + row["file"]
			if ResourceLoader.exists(path):
				var s = load(path)
				if s is AudioStream:
					row["stream"] = s
			sm.entries[str(id)] = row
	return sm
