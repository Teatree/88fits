## A currency the meta game prices things in (pass 111, lane SKINS; Garry: "get everything ready for the currency
## selection functionality in every place where it matters. We aren't adding new currency yet, but we might
## eventually"): content/currencies/<id>/<id>.json. Only "gold" exists. Its balance lives in the save: gold under the
## save's old "gold" key, any other currency under "wallets"[id] (Save.currency_balance). Every price on the title, the
## hero sheet, the drawer and the Upgrade board is shown with the currency's own icon (WCoin.currency) and paid through
## core/systems/Currency.gd. Adding a currency is one folder (docs/assets_schema.md "Pass 111").
class_name CurrencyDef
extends ContentDef

## where it sits in a list of currencies (the Level Editor's select, a future purse row)
@export var order: int = 0
## its colour (a price tag's ink, a chart line)
@export var colour: Color = Color("c9932f")
## the word a sentence uses ("gold": "250 gold from your purse")
@export var word: String = ""


func kind() -> String:
	return "currency"


## The word a sentence uses for it: `word`, else its name in lower case.
func word_of() -> String:
	return word if word != "" else display_name.to_lower()
