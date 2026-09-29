## A character line: a ranked stat track with no slot. A run opens two lines and the other four leave the pool.
## Same shape as a passive (levels of Effects, a rank cap), plus the trade it carries. Content: content/lines/<id>/.
class_name LineDef
extends PassiveDef

## The price of the line in words ("−3% move speed a rank"), empty for a pure line.
@export var trade: String = ""
## What a maxed line evolves into (pass 33.2): a level-up card offers it once the line is at its top rank.
@export var evolves_into: String = ""
## On an evolved line: the line it replaces. Evolved lines have one rank and are never offered on their own.
@export var evolves_from: String = ""
## A line's own sentence for the card (the Energy Shield's rules), shown above the generated effect text.
@export var text: String = ""


func kind() -> String:
	return "line"
