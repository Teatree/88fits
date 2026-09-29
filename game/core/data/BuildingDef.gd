## A homestead building (content/buildings): its levels cost gold and the materials the deep runs drop, and every level
## unlocks one more tier of each permanent upgrade in `unlocks`.
class_name BuildingDef
extends ContentDef

## order on the yard
@export var order: int = 0
## shop upgrade ids this building keeps: level N of the building lets tier N of each be bought
@export var unlocks: Array = []
## per level: {gold, bones, relics}
@export var levels: Array = []
## what the building looks like, for the record
@export var look: String = ""
## the farm (pass 27): the resource this building makes and how many a run at each level; the market sells the stock
## for silver at `rates` (silver a unit) times `rate_mult` for its level
@export var produces: String = ""
@export var yields: Array = []
@export var is_market: bool = false
@export var rates: Dictionary = {}
@export var rate_mult: Array = [1.0]


## Units of its resource a run at `level` (0 = not built: nothing).
func yield_at(level: int) -> int:
	if produces == "" or level <= 0 or yields.is_empty():
		return 0
	return int(yields[mini(level, yields.size()) - 1])


## Silver a unit of `res` fetches at a market of `level` (level 0: the base rate, so a stock is never worthless).
func rate_of(res: String, level: int) -> float:
	var base := float(rates.get(res, 0.0))
	if rate_mult.is_empty():
		return base
	return base * float(rate_mult[clampi(level - 1, 0, rate_mult.size() - 1)])


func max_level() -> int:
	return levels.size()


func cost_of(level: int) -> Dictionary:
	if level < 0 or level >= levels.size():
		return {}
	var c = levels[level]
	return c if c is Dictionary else {}
