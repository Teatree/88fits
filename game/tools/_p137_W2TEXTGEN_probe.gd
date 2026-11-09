## Pass 137, lane W2-TEXTGEN: the words the census's part a does not reach, written as one sorted JSON so a conversion
## into the string table can be proved to change none of them (compare two runs with tools/text_census_diff.py), and
## the own-row shapes (mode=shapes: every weapon's and evolution's home sentence key, every rule item's).
##   bash tools/godot.sh --headless --path D:/_projects/88fits/game --log-file <abs> --script res://tools/_p137_W2TEXTGEN_probe.gd -- out=<abs json> [mode=words|shapes]
## Never touches user://save.json (Save.begin_sandbox when the Save has it; nothing here writes).
extends SceneTree

var _args: Dictionary = {}
var _out: Dictionary = {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := str(a).split("=", true, 1)
		if kv.size() == 2:
			_args[kv[0]] = kv[1]
	process_frame.connect(_go, CONNECT_ONE_SHOT)


func _put(k: String, v) -> void:
	_out[k] = str(v)


func _go() -> void:
	await process_frame
	await process_frame
	var sv = root.get_node_or_null("Save")
	if sv and sv.has_method("begin_sandbox"):
		sv.call("begin_sandbox")
	if str(_args.get("mode", "words")) == "shapes":
		_shapes()
	else:
		_words()
	var keys := _out.keys()
	keys.sort()
	var sorted := {}
	for k in keys:
		sorted[k] = _out[k]
	var f := FileAccess.open(str(_args.get("out", "user://w2textgen_probe.json")), FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "parts": ["a"], "a": sorted}, "  ", false) + "\n")
	f.close()
	print("w2textgen probe: %d texts" % _out.size())
	quit(0)


## Every weapon's and evolution's opening sentence key at level 1 with its own params (the own row it would read), and
## every rule passive's and the box perk's.
func _shapes() -> void:
	var reg = root.get_node("Registry")
	var tg: GDScript = load("res://core/systems/TextGen.gd")
	var wi: GDScript = load("res://core/systems/WeaponInstance.gd")
	var ss: GDScript = load("res://core/systems/StatSheet.gd")
	var player = ss.new()
	for id in reg.weapons.keys():
		var def = reg.weapons[id]
		var inst = wi.new(def, 1)
		inst.rebuild(player, [inst])
		var pr: Dictionary = tg.call("_home_params", def)
		var sheet = inst.sheet
		var shape := ""
		var b: String = def.behavior
		if b == "ProjectileEmitter" and pr.has("plant"):
			b = "Spear"
		match b:
			"Spear":
				shape = "spear"
			"ProjectileEmitter":
				shape = tg.call("_ball_shape", sheet, pr) if bool(pr.get("return_on_hit", false)) else tg.call("_pe_shape", def, sheet, pr)
			"Orbiter":
				shape = "orbit"
			"Lobber":
				shape = tg.call("_lob_shape", sheet)
			"Beam":
				shape = "zap"
			"Thruster":
				shape = tg.call("_thrust_shape", pr)
			"Smasher":
				shape = "smash"
			"MineLayer":
				shape = tg.call("_mine_shape", pr)
			"GravityGun":
				var gv = pr.get("gravity", {})
				shape = "gravity.hole" if gv is Dictionary and (gv as Dictionary).get("black_hole") is Dictionary else "gravity.throw"
			"Spawner":
				shape = "spawn"
			"MissilePod":
				shape = "pod.rockets" if float(def.base.get("area", 0.0)) > 0.3 else "pod.bees"
			"LaserBeam":
				shape = "laser"
			"ConeWave":
				shape = "cone.ring" if float(tg.call("cone_width", pr, sheet.get_stat("area", 1.0))) >= 359.0 else "cone.cone"
			"SunScepter":
				shape = "sun"
			"Frisbee":
				shape = "frisbee"
			"SaltShaker":
				shape = "salt"
			"FireBreath":
				shape = tg.call("_breath_shape", sheet, pr)
		if shape != "":
			_put(("evolution.%s.desc" if def.is_evolution else "weapon.%s.desc") % id, "gen.weapon." + shape)
	for id in reg.passives.keys():
		var p = reg.passives[id]
		if p.text != "":
			continue
		var rule := ""
		var prm: Dictionary = p.params
		if prm.get("grind") is Dictionary:
			rule = "grind_once" if p.single else ""
		elif prm.get("arc") is Dictionary:
			rule = "arc"
		elif prm.get("grave") is Dictionary:
			rule = "grave"
		elif prm.get("purse") is Dictionary:
			var cap: float = tg.call("first_level_value", p, "purse_might_cap", 0.0)
			var hp: float = tg.call("first_level_value", p, "purse_hp_per", 0.0)
			rule = "purse" + ("_cap" if cap > 0.0 else "") + ("_hp" if hp > 0.0 else "")
		elif prm.get("bible") is Dictionary:
			var c: float = tg.call("first_level_value", p, "hit_cap_pct", 12.0)
			var bo: float = tg.call("first_level_value", p, "boss_hit_cap_pct", 0.0)
			var ev: float = tg.call("first_level_value", p, "hit_block_every", 0.0)
			rule = "bible" + ("_boss" if bo > 0.0 and not is_equal_approx(bo, c) else "") + ("_block" if ev > 0.0 else "")
		elif prm.get("train") is Dictionary:
			rule = "train"
		elif prm.get("storm") is Dictionary:
			rule = "storm"
		elif str(tg.call("chest_text", p)) != "":
			rule = "chest"
		if rule != "":
			_put("passive.%s.desc" % id, "gen.passive.rule." + rule)
	for id in reg.perks.keys():
		if str(reg.perks[id].special) == "box":
			_put("perk.%s.desc" % id, "gen.perk.box")


## The words outside the census's part a: the Trail's requirement and note, the Totem's labels, the drum's summary, the
## currency's words, the skins' names, the cards' words (WItem), the weapon rows' names.
func _words() -> void:
	var reg = root.get_node("Registry")
	var trail: GDScript = load("res://core/systems/Trail.gd")
	if bool(trail.call("has_nodes")):
		for n in trail.call("nodes"):
			var g: Dictionary = (n as Dictionary).get("gives", {}) if (n as Dictionary).get("gives") is Dictionary else {}
			var type := str(g.get("type", ""))
			var gid := str(g.get("id", ""))
			if type != "" and type != "upgrade":
				_put("trail|req|%s|%s" % [type, gid], trail.call("requirement_text", type, gid))
	for gold in [0, 1, 2400, 1234567]:
		_put("trail|note|%d" % gold, trail.call("note_text", {"kind": "trail_refund", "gold": gold}))
	_put("trail|note|other", trail.call("note_text", {"kind": "other"}))
	var tb: GDScript = load("res://core/systems/TotemBoons.gd")
	for n in range(1, 25):
		_put("totem|ordinal|%d" % n, tb.call("ordinal", n))
		_put("totem|label|%d|11" % n, tb.call("pole_label", n, 11))
		_put("totem|label|%d|0" % n, tb.call("pole_label", n, 0))
	for sid in reg.structures.keys():
		var sd = reg.structures[sid]
		for b in tb.call("pool_of", sd):
			var boon: Dictionary = (b as Dictionary).duplicate()
			if not boon.has("value"):
				boon["value"] = 0.05
			var bid := str(boon.get("id", boon.get("stat", "?")))
			_put("totem|%s|%s|title" % [sid, bid], tb.call("title", boon))
			_put("totem|%s|%s|source" % [sid, bid], tb.call("source", boon))
			_put("totem|%s|%s|toast" % [sid, bid], tb.call("toast_text", boon))
	var db: GDScript = load("res://core/systems/DrumBoost.gd")
	var ef: GDScript = load("res://core/data/Effect.gd")
	var sets := [[["might", 1.0], ["haste", 1.0], ["move_speed", 0.15], ["knockback", 1.0]], [["might", 0.5]], [["move_speed", 0.15], ["knockback", 1.0]]]
	for k in range(sets.size()):
		var list: Array = []
		for pair in sets[k]:
			list.append(ef.call("make", pair[0], "mul", pair[1]))
		_put("drum|summary|%d" % k, db.call("summary", list, 15.0))
	var cu: GDScript = load("res://core/systems/Currency.gd")
	for id in ["gold", "", "nope"]:
		_put("currency|%s|name" % id, cu.call("name_of", id))
		_put("currency|%s|word" % id, cu.call("word_of", id))
		_put("currency|%s|price" % id, cu.call("price_words", id, 2400))
	for cid in reg.characters.keys():
		var c = reg.characters[cid]
		_put("skin|%s|" % cid, c.skin_name(""))
		for code in c.variants.keys():
			_put("skin|%s|%s" % [cid, code], c.skin_name(str(code)))
		_put("skin|%s|ZZ-Q" % cid, c.skin_name("ZZ-Q"))
	# Run's words a tool can reach: the trait's source name, every weapon's evolution line (pass 137, the later files)
	var run = root.get_node("Run")
	for cid in reg.characters.keys():
		_put("run|trait_source|%s" % cid, run.call("trait_source", reg.characters[cid], 7))
	var wi2: GDScript = load("res://core/systems/WeaponInstance.gd")
	for id in reg.weapons.keys():
		var wdef = reg.weapons[id]
		for lv in [1, wdef.max_level]:
			var inst = wi2.new(wdef, lv)
			_put("run|evo|%s|%d" % [id, lv], run.call("evolution_status", inst))
	for ut in trail.call("upgrade_types"):
		var uname := str((trail.call("upgrade", str(ut)) as Dictionary).get("name", ut))
		var old_fmt := str(trail.get_script_constant_map().get("SOURCE", ""))
		_put("trail|source|%s" % str(ut), trail.call("source_name", uname) if old_fmt == "" else old_fmt % uname)
	var wit: GDScript = load("res://ui/wanted/WItem.gd")
	var cards: Array = []
	for id in reg.weapons.keys():
		var w = reg.weapons[id]
		cards.append({"def": w, "level_from": 0, "level_to": 1})
		if not w.is_evolution:
			cards.append({"def": w, "level_from": 0, "level_to": 2})
			cards.append({"def": w, "level_from": 1, "level_to": 2})
	for id in reg.passives.keys():
		var p = reg.passives[id]
		cards.append({"def": p, "level_from": 0, "level_to": 1})
		if p.max_level > 1:
			cards.append({"def": p, "level_from": 1, "level_to": 2})
			cards.append({"def": p, "level_from": p.max_level - 1, "level_to": p.max_level})
		if p.evolves_from != "":
			cards.append({"def": p, "level_from": 0, "level_to": 1, "evolve": true})
	for id in reg.perks.keys():
		cards.append({"def": reg.perks[id], "level_from": 0, "level_to": 1})
	for id in reg.mutations.keys():
		cards.append({"def": reg.mutations[id], "level_from": 0, "level_to": 1})
	for card in cards:
		var d = card["def"]
		var tag := "%s|%s|%d|%d|%s" % [str(wit.call("kind", d)), d.id, int(card["level_from"]), int(card["level_to"]), str(card.get("evolve", false))]
		_put("card|%s|word" % tag, wit.call("word", card))
		_put("card|%s|tag" % tag, wit.call("tag", card))
		_put("card|%s|rung" % tag, wit.call("rung_word", card))
		_put("card|%s|effect" % tag, wit.call("effect", card))
		_put("card|%s|text" % tag, wit.call("card_text", card))
		var o: Dictionary = wit.call("options", card, {"stars": []})
		_put("card|%s|opt_word" % tag, o.get("word", ""))
