## One talent on the Mirror (content/talents/<id>): two mutually exclusive forms, three ranks, a gold cost a rank.
## The hero picks a form and buys ranks of it; switching form or refunding costs nothing (Save.talent_refund_all).
class_name TalentDef
extends ContentDef

## where it sits on the board
@export var order: int = 0
## how many ranks a form may take
@export var ranks: int = 3
## gold for rank 1, 2, 3
@export var cost: Array = []
## two entries: {"name", "text", "effects": [Effect]}
@export var forms: Array = []


func form_name(form: int) -> String:
	if form < 0 or form >= forms.size():
		return ""
	return str((forms[form] as Dictionary).get("name", ""))


func form_text(form: int) -> String:
	if form < 0 or form >= forms.size():
		return ""
	return str((forms[form] as Dictionary).get("text", ""))


## The effects of `form` at `rank` ranks: the form's own effects repeated, so rank 3 is three times rank 1.
func effects_for(form: int, rank: int) -> Array:
	var out: Array = []
	if form < 0 or form >= forms.size() or rank <= 0:
		return out
	var base: Array = (forms[form] as Dictionary).get("effects", [])
	for k in range(rank):
		out.append_array(base)
	return out


## The price of the next rank when `rank` are already owned, or -1 when the form is full.
func cost_of_rank(rank: int) -> int:
	if rank < 0 or rank >= cost.size():
		return -1
	return int(cost[rank])
