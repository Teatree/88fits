## Pass 139 (lane CHEST; Garry: "Mutation chest should show which weapon a mutation is for, because no one remembers them
## like that. I think maybe the weapon icon at it's direct rarity it's mutation count appearing under the selected
## mutation and it's text could be good."): the weapon a mutation is for, as one compact row under the mutation's name and
## text: the weapon's plate as the HUD's slot draws it (the same frame in its level's rarity, Settings.hud_slot_rarity's
## rule; its level as the HUD's plain plaque number; an evolved one black with EVO), and beside it "FOR" over the weapon's
## name and its path's rivets (held gold, the one this mutation gives cream and pulsing, the rest slate, WMarks' Royale
## rivets as the mutation offer's count pill shows them) with the count after them ("2/3": the path once this one is
## taken). The plate carries no mutation dots of its own: the rivets beside it are the count, at a size that reads on a
## phone, and two counts side by side read as two different things. A hero's own mutation sits outside the path: its
## rivets show the path as it is, none lit.
## The kit's one drawing of "the weapon this is for": the chest's result card uses it (ui/ChestScreen.gd); the mutation
## offer (CardScreen) already puts its weapon's plate, name and rivets over its cards and keeps them.
class_name WWeaponBadge
extends HBoxContainer

## The weapon's plate, the room its hanging level plaque and navy foot take under it, the gap to the words.
const PLATE_PX := 124.0
const PLAQUE_ROOM := 22.0
const GAP := 26
## "FOR", the weapon's name, the rivets and the count after them.
const LABEL_PX := 22
const NAME_PX := 40
const RIVET_PX := 32.0
const COUNT_PX := 32
const ROW_GAP := 14
const FOR_KEY := "ui.chest.mutation_for"

## What the badge shows (facts()): the weapon's def and level, the path's mutations held and its total, and whether this
## mutation fills the next rivet.
var weapon_id := ""
var level := 0
var held := 0
var total := 0
var gives := false
var plate: WPlate
var name_text: WText
var rivets: WMarks
var count_text: WText


## What the badge says for mutation `md` in this run: {weapon (WeaponDef), level, held, total, gives}. The weapon is the
## run's copy of the mutation's family (its evolution once it has evolved: Run.family_instance), at the level it is held
## at; held and total are its path's (Run.path_progress: never a hero's own); `gives` is true for a path mutation not held
## yet. A weapon the run does not hold (a tool's roll) is its family's base at level 0 with none held. {} for no weapon.
static func facts(md: MutationDef) -> Dictionary:
	if md == null or md.weapon == "":
		return {}
	var run := W.node("Run")
	var reg := W.node("Registry")
	var inst = run.call("family_instance", md.weapon) if run and run.has_method("family_instance") else null
	var wd: WeaponDef = null
	var lv := 0
	var pp := Vector2i.ZERO
	if inst != null:
		wd = (inst as WeaponInstance).def
		lv = (inst as WeaponInstance).level
		pp = run.call("path_progress", inst)
	elif reg and reg.has_method("weapon"):
		wd = reg.call("weapon", md.weapon) as WeaponDef
		if reg.has_method("mutations_of"):
			pp = Vector2i(0, (reg.call("mutations_of", md.weapon) as Array).size())
	if wd == null:
		return {}
	var in_path := false
	if reg and reg.has_method("mutations_of"):
		for m in (reg.call("mutations_of", md.weapon) as Array):
			if (m as MutationDef).id == md.id:
				in_path = true
				break
	var has := inst != null and (inst as WeaponInstance).has_mutation(md.id)
	return {"weapon": wd, "level": lv, "held": pp.x, "total": pp.y, "gives": in_path and not has and pp.x < pp.y}


## The badge for mutation `md` in this run, or null when it names no weapon.
static func for_mutation(md: MutationDef) -> WWeaponBadge:
	var f := facts(md)
	if f.is_empty():
		return null
	var b := WWeaponBadge.new()
	b.setup(f["weapon"] as WeaponDef, int(f["level"]), int(f["held"]), int(f["total"]), bool(f["gives"]))
	return b


## The count the words say: the path's mutations once this one is taken (held + 1 when it gives one), of its total.
func count_shown() -> int:
	return mini(held + (1 if gives else 0), total)


func setup(wd: WeaponDef, p_level: int, p_held: int, p_total: int, p_gives: bool) -> WWeaponBadge:
	name = "WeaponBadge"
	weapon_id = wd.id
	level = p_level
	held = clampi(p_held, 0, maxi(p_total, 0))
	total = maxi(p_total, 0)
	gives = p_gives and held < total
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", GAP)
	# the plate as the HUD's slot draws it (HUD._refresh_rows): its level's frame, the common one when the switch puts
	# none on the slots, the level as the plaque's plain number; in a plain holder (a Container would size the plate to
	# the row and the plaque hangs under its foot)
	var holder := Control.new()
	holder.name = "PlateHolder"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.custom_minimum_size = Vector2(PLATE_PX, PLATE_PX + PLAQUE_ROOM)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(holder)
	plate = WPlate.new().for_def(wd, PLATE_PX, false, maxi(level, 1))
	plate.name = "WeaponPlate"
	plate.border = 4
	plate.radius = 10
	var settings := W.node("Settings")
	if settings and not bool(settings.get("hud_slot_rarity")):
		plate.fill = W.RARITY_PLATE["common"]
	if level > 0:
		plate.level_text = str(level)
	holder.add_child(plate)
	var col := VBoxContainer.new()
	col.name = "Words"
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 4)
	add_child(col)
	var lbl := R.label(Loc.t(FOR_KEY), LABEL_PX, R.SECONDARY)
	lbl.name = "For"
	col.add_child(lbl)
	name_text = W.text(wd.display_name, R.body(R.LABEL_WEIGHT), NAME_PX, R.CREAM, HORIZONTAL_ALIGNMENT_LEFT,
		roundf(NAME_PX * 1.15), true)
	name_text.name = "WeaponName"
	col.add_child(name_text)
	if total > 0:
		var row := HBoxContainer.new()
		row.name = "Count"
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", ROW_GAP)
		col.add_child(row)
		rivets = WMarks.new().setup("rivets", total, held, held + 1 if gives else -1, RIVET_PX)
		rivets.name = "Rivets"
		rivets.gap = 8.0
		rivets.rivet_border = 3.0
		rivets.pulse = gives
		rivets.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(rivets)
		# a count has no letters: it stays in code ("2/3")
		count_text = W.text("%d/%d" % [count_shown(), total], R.body(R.LABEL_WEIGHT), COUNT_PX, R.GOLD_TEXT if gives else R.SECONDARY)
		count_text.name = "CountText"
		count_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(count_text)
	return self
