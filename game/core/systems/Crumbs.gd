## The red crumb trails (pass 123; Garry: "There should be red crumb trail to that button element when the Look is unlocked.
## Make the existing crumb trail that we have to the Upgrade red as well, and make it disappear once Player had tapped it.
## So if there is enough coins for a new kind of Upgrade where previously there wasn't, the crumb trail will show up. Once
## Player had tapped it at least once it disappears."). What the player has already been shown lives in the save
## (`crumbs`: "upgrade": the Trail nodes seen affordable, by node id; "looks": the looks seen unlocked, "<hero>:<code>"),
## so a mark means something NEW. Read by the tab bar (the Royale theme's) and the Heroes screen.
class_name Crumbs
extends RefCounted


## What has been shown so far. Only reads: a save that has never marked anything stays as it was.
static func _seen(kind: String) -> Array:
	var c = Save.data.get("crumbs")
	if c is Dictionary and (c as Dictionary).get(kind) is Array:
		return (c as Dictionary)[kind]
	return []


## The list to add to, made in the save when it is first needed.
static func _seen_to_write(kind: String) -> Array:
	if not (Save.data.get("crumbs") is Dictionary):
		Save.data["crumbs"] = {}
	var c: Dictionary = Save.data["crumbs"]
	if not (c.get(kind) is Array):
		c[kind] = []
	return c[kind]


## The Trail nodes the purse can buy now, by id (Trail.can_buy). Pass 129: the fourth tab (its id is still "upgrade")
## is the Trail, and pass 123's crumb keeps its rule on the Trail's nodes; the save's list is the same one (a save from
## the Upgrade board's days holds "<talent>:<rank>" keys there too: they match no node and do nothing).
static func upgrade_keys() -> Array:
	var out: Array = []
	for n: Dictionary in Trail.nodes():
		if Trail.can_buy(str(n["id"])):
			out.append(str(n["id"]))
	return out


## The crumb to the Trail's tab: a node the purse can buy that the player has not been shown yet.
static func upgrade_due() -> bool:
	var seen := _seen("upgrade")
	for k: String in upgrade_keys():
		if not seen.has(k):
			return true
	return false


## The Trail was opened (or a node bought on it): everything affordable now has been seen.
static func upgrade_mark_seen() -> void:
	var seen := _seen("upgrade")
	var changed := false
	for k: String in upgrade_keys():
		if not seen.has(k):
			_seen_to_write("upgrade").append(k)
			changed = true
	if changed:
		Save.request_save()


## The looks of hero `c` the player can wear or buy that are not his starting one.
static func unlocked_looks(c: CharacterDef) -> Array:
	var out: Array = []
	if c == null or Registry.hero_state(c) != "owned":
		return out
	for code: String in Registry.skins_of(c):
		if code == c.home_look():
			continue
		var st := str(Registry.skin_state(c, code))
		if st == "owned" or st == "buyable":
			out.append(code)
	return out


## The crumb to hero `c`'s LOOKS button: a look unlocked since his looks were last opened.
static func look_due(c: CharacterDef) -> bool:
	var seen := _seen("looks")
	for code: String in unlocked_looks(c):
		if not seen.has("%s:%s" % [c.id, code]):
			return true
	return false


## The crumb to the Heroes tab: any hero's look_due.
static func any_look_due() -> bool:
	for c: CharacterDef in Registry.characters.values():
		if not c.hidden and look_due(c):
			return true
	return false


## Hero `c`'s LOOKS were opened: his unlocked looks have been seen.
static func looks_mark_seen(c: CharacterDef) -> void:
	var seen := _seen("looks")
	var changed := false
	for code: String in unlocked_looks(c):
		var k := "%s:%s" % [c.id, code]
		if not seen.has(k):
			_seen_to_write("looks").append(k)
			changed = true
	if changed:
		Save.request_save()
