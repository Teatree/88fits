# The Store's file (pass 147)

`game/content/store/store.json` holds the coin packs the Store screen sells (`game/ui/StoreScreen.gd`; the rules in
`game/core/systems/StorePacks.gd`; the numbers and why in BALANCING.md section 88). Edit it by hand; the game reads it
each time the Store opens. Nothing is bought for real yet: a price tap only says "Coming soon".

```json
{
  "version": 1,
  "currency": "gold",
  "show_bonus": true,
  "packs": [
    {"id": "pack_handful", "coins": 1000, "price_cents": 99, "price_text": "$0.99", "ribbon": "", "picture": "res://art/ui/store/pack_handful.png"}
  ]
}
```

| key | what it is |
|---|---|
| `currency` | the purse the packs fill: `gold` (the player's "coins"). |
| `show_bonus` | `true`: a pack that gives more coins a dollar than the cheapest one wears "+N% BONUS"; `false`: no tags. |
| `packs` | the packs in screen order: two columns, left to right, top to bottom (six fill the screen). |
| `id` | a short unique name; the card is `Pack_<id>` for the tools. |
| `coins` | the coins the pack would give (Coins x25 never multiplies it). |
| `price_cents` | the real-money price in cents (`99` = $0.99); the bonus tag is counted from it. |
| `price_text` | what the green button says (`"$0.99"`); it must name the same price as `price_cents`. |
| `ribbon` | `""` (none), `"most_popular"` or `"best_value"`: the ribbon over the card's top (words in en.json `ui.store.ribbon_*`). |
| `picture` | the pack's picture (`res://art/ui/store/<id>.png`, 384 px, painted by `tools/dl/p147/SHOP/gen_store_packs.py`); a missing one shows the coin. |

The bonus tag's N: round(100 x (coins / (dollars x base) - 1)), where dollars is the price rounded up to a whole dollar
($4.99 counts as $5) and base is the cheapest pack's coins per whole dollar. `StorePacks.problems()` lists what is wrong
with the file (the test `game/tests/pass147_store_test.gd` keeps it empty).

The STORE tab opens the screen only while the Settings' `store_open` is on (the Settings screen's debug panel row
"Store", in the player's debug mode; off by default; always off in the production build).
