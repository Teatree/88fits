# The Store's file (pass 147; version 2 since pass 149)

`game/content/store/store.json` holds what the Store screen sells (`game/ui/StoreScreen.gd`; the rules in
`game/core/systems/StorePacks.gd`; the numbers and why in BALANCING.md sections 88 and 92). Edit it by hand or in the
Level Editor's Store tab; the game reads it each time the Store opens. The Store has two sections: **GEMS** on top (gem
packs for real money; nothing is bought for real yet: a price tap only says "Coming soon") and **COINS** underneath (coin
offers bought with gems: a real exchange, whose coins grow as the player unlocks stages and climbs the Trail). The file
also sets the paid revive on Down!.

```json
{
  "version": 2,
  "gems": {
    "currency": "gems",
    "show_bonus": true,
    "packs": [
      {"id": "gems_handful", "amount": 80, "price_cents": 99, "price_text": "$0.99", "ribbon": "", "picture": "res://art/ui/store/gems_handful.png"}
    ]
  },
  "coins": {
    "currency": "gold",
    "pay": "gems",
    "show_bonus": true,
    "offers": [
      {"id": "coins_small", "gems": 100, "coins": 1000, "ribbon": "", "picture": "res://art/ui/store/pack_handful.png"}
    ],
    "scaling": {"stage_mult": [1.0, 3.0, 7.0, 14.0], "trail_step": 10, "trail_per_step": 0.05, "round_sig": 2}
  },
  "revive": {"price": 0, "currency": "gems", "per_run": 1}
}
```

## Keys

| key | what it is |
|---|---|
| `version` | `2`. A file without it or with `1` (pass 147's coin packs for dollars) is not read: both sections are empty and `StorePacks.problems()` says so. |
| **`gems`** | the GEMS section. |
| `gems.currency` | the currency the packs give: `gems` (content/currencies/gems). |
| `gems.show_bonus` | `true`: a pack that gives more gems a dollar than the cheapest one wears "+N% BONUS"; `false`: no tags. |
| `gems.packs` | the packs in screen order: three a row, left to right, top to bottom (six fill two rows). |
| `id` | a short unique name (unique across both sections); the card is `Pack_<id>` (a coin offer's `Offer_<id>`) for the tools. |
| `amount` | the gems the pack would give. |
| `price_cents` | the real-money price in cents (`99` = $0.99); the bonus tag is counted from it. |
| `price_text` | what the green button says (`"$0.99"`); it must name the same price as `price_cents`. |
| `ribbon` | `""` (none), `"most_popular"` or `"best_value"`: the ribbon over the card's top (words in en.json `ui.store.ribbon_*`). Coin offers too. |
| `picture` | the card's picture (`res://art/ui/store/<id>.png`, 384 px); a missing one shows the currency's icon (the gem, the coin). Coin offers too. |
| **`coins`** | the COINS section. |
| `coins.currency` | the currency the offers give: `gold` (the player's "coins"). |
| `coins.pay` | the currency they cost: `gems`. |
| `coins.show_bonus` | `true`: an offer that gives more coins a gem than the offer with the fewest gems wears "+N% BONUS". |
| `coins.offers` | the offers in screen order, in one row (three fill it). |
| `gems` (an offer's) | its price in gems (the green button: the gem and the number). |
| `coins` (an offer's) | its coins at the start (stage 1, Trail Level 0); what it gives a player is the rule below. |
| `coins.scaling.stage_mult` | the multiplier a stage, by the latest stage the player has unlocked (the first value for Sundown, the second for Nightfall, ...); past its end the last value holds. Never smaller than the one before it. |
| `coins.scaling.trail_step` | every this many Trail Levels the offers step up (`0` = the Trail adds nothing). |
| `coins.scaling.trail_per_step` | how much a Trail step adds (`0.05` = +5% of the stage's amount a step). |
| `coins.scaling.round_sig` | the significant figures the amounts are rounded to (`2`: 17,325 -> 17,000). |
| **`revive`** | the paid revive on Down!. |
| `revive.price` | its price (`0` = no paid revive: Down! exactly as before pass 149). |
| `revive.currency` | what it is paid in (`gems`; any currency the content has). |
| `revive.per_run` | how many paid revives a run may take. |

## The coin offer rule

```
coins_now(offer) = nice(offer.coins x stage_mult[s] x (1 + trail_per_step x floor(T / trail_step)), round_sig)
```

- `s` = the latest stage unlocked for the player: the highest index of the first map's stages that `Save.stage_unlocked`
  says may be played (0 on a new save: Sundown; 1 once Sundown is beaten; the Dust Bowl and the Blood Moon also need
  their Trail nodes).
- `T` = the Trail Level (`Trail.level()`).
- `nice(v, sig)` = `v` rounded to `sig` significant figures, half away from zero, as a whole number; 0 for nothing. The
  figures are counted on the whole part's digits (`1,050` at 2 -> `1,100`; `17,325` -> `17,000`; `9,960` -> `10,000`).
- Coins x25 never multiplies a Store amount.

So the amounts move in steps: a new stage is a big step (x1, x3, x7, x14), every ten Trail Levels a small one (+5% of the
stage's amount, before the rounding). With the file above, coins at Trail Level 0:

| offer | gems | Sundown | Nightfall | Dust Bowl | Blood Moon |
|---|---|---|---|---|---|
| coins_small | 100 | 1,000 | 3,000 | 7,000 | 14,000 |
| coins_medium | 500 | 5,500 | 17,000 | 39,000 | 77,000 |
| coins_large | 1,200 | 14,000 | 42,000 | 98,000 | 200,000 |

The fixture `game/tests/fixtures/pass149_store_coins.json` (made by `tools/dl/p149/STORE/make_fixture.py`) holds these and
more (Trail Levels 0, 9, 10, 35, 83, the bonus tags, rounding cases, an edge scaling); `game/tests/pass149_store_test.gd`
checks StorePacks against it and the Level Editor's `store_model.js` is checked against the same file.

## The bonus tags

- A gem pack: N = round(100 x (amount / (dollars x base) - 1)), dollars = the price rounded up to a whole dollar ($4.99
  counts as $5), base = the cheapest pack's gems a whole dollar.
- A coin offer: N = round(100 x (coins a gem / base - 1)), base = the coins a gem of the offer with the fewest gems, both at
  the amounts the player is shown now (so the rounding can move a tag a point or two as the amounts grow).
- No tag under 1%; none at all with the section's `show_bonus` false.

`StorePacks.problems()` lists what is wrong with the file (`game/tests/pass149_store_test.gd` keeps it empty): the
version, an id missing or used twice, no amount, gems, coins or price, a price text that does not name the price, an
unknown ribbon, no stages or a stage that gives less than the one before, a negative Trail step, a revive price with no
currency.

## Where it shows

The STORE tab opens the screen only while the Settings' `store_open` is on (the Settings screen's debug panel row "Store",
in the player's debug mode; off by default; always off in the production build). The gem wallet (the gem and the
balance) shows beside the coin purse on the main menu, the Outlaws, Trail and Store screens and on Down! only while the
Store is open; with the Store shut nothing about gems shows (a price set in gems elsewhere still shows its price with the
gem and charges gems). The debug panel's "Add 1,000 gems" and the developer menu's "Gems · add 1,000" put gems in the
wallet for tests (never in the production build).
