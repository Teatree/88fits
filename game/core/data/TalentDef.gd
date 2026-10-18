## One talent on the Mirror (content/talents/<id>): two mutually exclusive forms, six ranks (three until pass 46), a gold cost a rank.
## The hero picks a form and buys ranks of it; switching form is free, and taking it all back returns half the gold
## (Save.REFUND_FRAC, Save.talent_refund_all).
class_name TalentDef
extends ContentDef

## where it sits on the board
@export var order: int = 0
## how many ranks a form may take
@export var ranks: int = 3
## gold for each rank, one entry a rank (as many as `ranks`)
@export var cost: Array = []
## two entries: {"name", "text", "effects": [Effect]}, and optionally "rank_effects": [[Effect], ...] (pass 46): one list
## a rank, for a form whose ranks are not all the same step (rank 2 is lists 0 and 1); without it every rank is `effects`;
## "icon" (Texture2D) and "icon_file" (pass 61, form_icon)
@export var forms: Array = []


func form_name(form: int) -> String:
	if form < 0 or form >= forms.size():
		return ""
	return str((forms[form] as Dictionary).get("name", ""))


func form_text(form: int) -> String:
	if form < 0 or form >= forms.size():
		return ""
	return str((forms[form] as Dictionary).get("text", ""))


## The form's icon (pass 61, Garry: "The choices in the Mirror should be shown as little icons"): the picture a bought
## rank shows in the Upgrade board's rank bar, the summary's chip and the sheet's choice, from the form's `icon` in the
## JSON or content/talents/<id>/<id>_<form>_icon.png; null when neither exists (the board draws the name's initial).
func form_icon(form: int) -> Texture2D:
	if form < 0 or form >= forms.size():
		return null
	var t = (forms[form] as Dictionary).get("icon")
	return t if t is Texture2D else null


## How many ranks a form may take.
func max_rank() -> int:
	return ranks


## The form's per-rank lists (pass 46), empty when every rank is the same step.
func _rank_lists(form: int) -> Array:
	var rl = (forms[form] as Dictionary).get("rank_effects", [])
	return rl if rl is Array else []


## The effects of `form` at `rank` ranks: its rank lists 0..rank-1 together when it has them, else the form's own effects
## repeated, so rank 3 is three times rank 1.
func effects_for(form: int, rank: int) -> Array:
	var out: Array = []
	if form < 0 or form >= forms.size() or rank <= 0:
		return out
	var rl := _rank_lists(form)
	if not rl.is_empty():
		for k in range(mini(rank, rl.size())):
			if rl[k] is Array:
				out.append_array(rl[k])
		return out
	var base: Array = (forms[form] as Dictionary).get("effects", [])
	for k in range(rank):
		out.append_array(base)
	return out


## The ranks summed for reading (pass 45): one Effect per stat at the ranks' total ("+30% max HP" at rank 3). Text
## only; the sheet still folds effects_for.
func summed_effects(form: int, rank: int) -> Array:
	var out: Array = []
	if form < 0 or form >= forms.size() or rank <= 0:
		return out
	if _rank_lists(form).is_empty():
		for e in (forms[form] as Dictionary).get("effects", []):
			if e is Effect:
				out.append(Effect.make(e.stat, e.op, e.value * rank, e.target))
		return out
	# rank lists: one Effect per stat, op and target, in the order they first appear; a "set" keeps the last value
	var at: Dictionary = {}
	for e in effects_for(form, rank):
		if not (e is Effect):
			continue
		var key := "%s|%s|%s" % [e.stat, e.op, e.target]
		if at.has(key):
			var acc: Effect = out[int(at[key])]
			acc.value = e.value if e.op == "set" else acc.value + e.value
		else:
			at[key] = out.size()
			out.append(Effect.make(e.stat, e.op, e.value, e.target))
	return out


## The first rank's price (pass 88: what the board sorts by), 0 without a price list.
func first_price() -> int:
	return int(cost[0]) if not cost.is_empty() else 0


## The board's order (pass 88, Registry.talents_list): the cheaper first rank first, then `order`, then the id.
static func board_before(a: TalentDef, b: TalentDef) -> bool:
	if a.first_price() != b.first_price():
		return a.first_price() < b.first_price()
	if a.order != b.order:
		return a.order < b.order
	return a.id < b.id


## The price of the next rank when `rank` are already owned, or -1 when the form is full: past `ranks` or past the
## price list, whichever ends first (pass 46: the two can never disagree silently; tools/import_json.gd warns when they
## differ in length).
func cost_of_rank(rank: int) -> int:
	if rank < 0 or rank >= ranks or rank >= cost.size():
		return -1
	return int(cost[rank])
