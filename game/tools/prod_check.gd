## Pass 81 (lane PROD): the production build's checks, run in the STAGING copy after the prune and the import
## (tools/ship_prod.sh; the editor binary, headless):
##   godot --headless --path tools/dl/prod/stage/game --script res://tools/prod_check.gd [-- plan=<the plan the prune used>]
## Fails (exit 1, "prod_check: FAIL ...") when: the Registry has a problem; a hero in play, a creature or boss the map
## brings (with every look a row names), a weapon, card, passive, mutation, perk, pickup or structure in play has no art
## (sprite / icon) or does not load; a sound of the sound map has no stream (music must be Ogg); planning again would drop
## anything more (the prune must leave nothing unreachable behind, and nothing reachable must be gone); a played look
## differs from the plan's; the production switch (forced here) leaves any developer surface on. Prints "prod_check: OK".
extends SceneTree

var _fails: Array = []


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _fail(s: String) -> void:
	_fails.append(s)
	print("prod_check: FAIL " + s)


func _run() -> void:
	var reg: Node = root.get_node("Registry")
	var settings: Node = root.get_node("Settings")
	var reach = load("res://tools/prod_reach.gd")
	var old_plan := {}
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("plan="):
			var v = JSON.parse_string(FileAccess.get_file_as_string(a.trim_prefix("plan=")))
			old_plan = v if v is Dictionary else {}
	for p in reg.problems:
		_fail("Registry: %s" % p)
	# planning again finds nothing more to drop, and every look left is one that is kept
	var plan: Dictionary = reach.plan(reg)
	for k: String in plan["drop"]:
		var kept_by_ref := false
		if old_plan.has("drop") and (old_plan["drop"] as Dictionary).has(k):
			kept_by_ref = true   # the prune kept it because a file that stays names it (prod_prune.py says which)
		if not kept_by_ref:
			_fail("planned again, %s would be dropped (%s): the prune left it" % [k, plan["drop"][k]])
	for k: String in plan["looks"]:
		var lk: Dictionary = plan["looks"][k]
		if not (lk["drop"] as Array).is_empty():
			_fail("planned again, %s still has looks to drop: %s" % [k, lk["drop"]])
		if old_plan.has("looks") and (old_plan["looks"] as Dictionary).has(k):
			var was: Dictionary = old_plan["looks"][k]
			if str(was["play"]) != str(lk["play"]):
				_fail("%s plays %s, the plan said %s" % [k, lk["play"], was["play"]])
	if old_plan.has("keep"):
		for k: String in old_plan["keep"]:
			if not (plan["keep"] as Dictionary).has(k):
				_fail("%s was to be kept (%s) and is gone" % [k, old_plan["keep"][k]])
	# the art of everything in play
	var n := 0
	for c in reg.sorted_characters():
		n += 1
		var look = reg.played_look(c)
		if look.sprite == null:
			_fail("hero %s (%s) has no strip" % [c.id, look.look_code()])
		if c.icon == null:
			_fail("hero %s has no badge" % c.id)
		if not ResourceLoader.exists(look.title_path()):
			_fail("hero %s has no title cut-out (%s)" % [c.id, look.title_path()])
	for key: String in plan["keep"]:
		var type := key.get_slice("/", 0)
		var id := key.get_slice("/", 1)
		var d = null
		match type:
			"weapons", "evolutions":
				d = reg.weapon(id)
			"passives":
				d = reg.passive(id)
			"mutations":
				d = reg.mutation(id)
			"perks":
				d = reg.perk(id)
			"pickups":
				d = reg.pickup(id)
			"structures":
				d = reg.structure(id)
			"enemies", "bosses":
				d = reg.enemy(id)
				if d != null and d.sprite == null:
					_fail("creature %s has no strip" % id)
			_:
				continue
		n += 1
		if d == null:
			_fail("%s does not load" % key)
		elif d.icon == null and not ["structures", "pickups"].has(type):
			_fail("%s has no icon" % key)
	# every look a map row or event names
	for key: String in plan["looks"]:
		var lk: Dictionary = plan["looks"][key]
		if str(lk["kind"]) != "creature":
			continue
		for code in lk["keep"]:
			var e = reg.enemy_with(key.get_slice("/", 1), str(code))
			n += 1
			if e == null or e.sprite == null:
				_fail("creature %s in look %s has no strip" % [key, code])
	# the sounds
	for sid in reg.soundmap.entries.keys():
		var row: Dictionary = reg.soundmap.entries[sid]
		n += 1
		if row.get("stream") == null:
			_fail("sound %s (%s) has no stream" % [sid, row.get("file", "")])
		elif str(row.get("category", "")) == "music" and not (row["stream"] is AudioStreamOggVorbis):
			_fail("music %s is not Ogg Vorbis" % sid)
	# the production switch, forced: every developer surface off and staying off
	settings.call("from_dict", {"debug_mode": true, "debug_panel": true, "debug_modal_buttons": true, "free_revive_button": true,
		"hit_log": true, "preview_locked_heroes": true, "menu_style": "painted"})
	settings.call("force_prod", true)
	settings.call("from_dict", {"debug_mode": true, "debug_panel": true, "debug_modal_buttons": true, "free_revive_button": true,
		"hit_log": true, "preview_locked_heroes": true, "menu_style": "painted"})
	settings.call("set_value", "debug_mode", true)
	for k: String in settings.get("PROD_LOCKED"):
		if settings.get(k) != settings.get("PROD_LOCKED")[k]:
			_fail("prod: Settings.%s is %s" % [k, str(settings.get(k))])
	if str(settings.call("build_flavour")) != "prod":
		_fail("prod: the build flavour reads %s" % settings.call("build_flavour"))
	settings.call("force_prod", false)
	if _fails.is_empty():
		print("prod_check: OK %d items, %d sounds, version %s" % [n, reg.soundmap.entries.size(),
			str(ProjectSettings.get_setting("application/config/version", ""))])
		quit(0)
	else:
		print("prod_check: FAIL %d problems" % _fails.size())
		quit(1)
