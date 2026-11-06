# The Trail: data, rules and names

The Trail is the game's permanent progression (pass 129; it replaces the Upgrade board, "the Mirror" in code). One
long track of nodes bought with gold, read from one JSON file and edited in the Level Editor's Trail tab. Garry's brief
and his answers (2026-11-06) are the source of every rule here; a rule he did not ask for is marked *(lead)*.

- Data: `game/content/trail/trail.json` (plain JSON read at run time, like `content/wanted/wanted.json`; no `.tres`).
- Icons: `game/art/ui/trail/<icon>.png`, 256 px, transparent.
- Runtime: `game/core/systems/Trail.gd` (static; the one place the rules live). Screen: `game/ui/TrailScreen.gd`.
- Save: `Save.data.trail = {"bought": [<node id>, ...], "spent": <gold>}`.

## The file

```json
{
  "version": 1,
  "currency": "gold",
  "price": {"base": 40, "k": 1.5, "power": 2.0, "round": 10},
  "sections": [{"from": 1, "name": "Sundown", "top": "f7b24a", "bottom": "ef7d22", "motif": "cactus"}],
  "upgrades": {
    "might": {"name": "Might", "icon": "might", "kind": "percent", "text": "Attack damage",
              "effects": [{"stat": "might", "op": "mul", "per": 1.0}]}
  },
  "nodes": [
    {"id": "n001", "level": 1, "kind": "node", "gives": {"type": "upgrade", "upgrade": "might", "value": 0.03}}
  ],
  "end": {"text": "To be continued"}
}
```

### `price`

A node without its own `price` costs `round_to(base + k * level ^ power, round) * price_mult` (the node's
`price_mult`, default 1). Prices grow as a polynomial of the level (Garry). `currency` names a `content/currencies` id.

### `sections`

The backdrop changes every 15 to 20 levels: each section starts at level `from` and gives two colours (`top`,
`bottom`, hex without #) and a `motif` (a faint tiled sign: `cactus`, `star`, `skull`, `horseshoe`, `moon`, `flame`,
`dust`, `none`); the screen blends from one section's colours into the next over the three levels before `from`.
`name` shows as a small plate where the section begins.

### `upgrades` (the upgrade types)

One entry per type of permanent upgrade. A node names the type and its own `value`: the amount is free per node
(Garry: "I can select might and any percentage I like").

| key | meaning |
|---|---|
| `name` | what the player reads ("Might") |
| `icon` | file name in `art/ui/trail/` without `.png`; every type has its own |
| `kind` | how the value is written: `percent` (0.03 -> "+3%"), `flat` (+2), `count` (+1), `seconds`, `word` |
| `text` | the line after the amount ("Attack damage") |
| `effects` | one or more `{stat, op, per}`: the stat gets `value * per` with `op` (`add` or `mul`), an `Effect` like any other |
| `warn` | optional line the buy card shows in red before buying (Stakes: "Creatures get tougher for good.") |

All bought nodes of one type add up into one effect per stat (source id `trail:<type>`, shown on the pause screen as
"The Trail: <name>"); against other sources it multiplies or adds as the stat sheet always does.

### `nodes`

| key | meaning |
|---|---|
| `id` | unique, never reused (saves hold ids) |
| `level` | 1 at the bottom, counting up; several nodes may share a level |
| `kind` | `node` (plain), `choice` (one of a group), `optional` (may be skipped) |
| `group` | `choice` only: siblings on the same level share it (2 to 4) |
| `from` | ids of the nodes it connects from. Absent on a plain or choice node = every required node of the nearest lower level (a group counts as the one chosen). An optional node may name a node of its own level (it hangs beside it) |
| `need` | `all` (default) or `any` of `from` |
| `gives` | what buying it gives, below |
| `price`, `price_mult` | an own price, or a multiplier on the curve |
| `x` | optional place across the screen, 0 to 1; absent = spread by the rule below |
| `name`, `note` | optional words (a milestone's own name; a designer's note the game never shows) |

`gives`:

| `type` | fields | effect |
|---|---|---|
| `upgrade` | `upgrade`, `value` | the type's effects at this value |
| `outlaw` | `id` | the outlaw is owned |
| `skin` | `id` ("<outlaw>:<CODE>") | the skin is owned |
| `weapon`, `passive` | `id` | the item joins the pool (cards, lines and passive items are `passive`) |
| `stage` | `map`, `stage` (the stage's id) | the stage may be played (its other rule, the boss before it beaten, stays) *(lead)* |
| `map` | `id` | the map may be played |
| `structure` | `id` | the structure may stand on maps |
| `powerup` | `id` | the power-up may drop |
| `feature` | `id` (`wanted` only, for now) | the feature opens |

A thing named by some node's `gives` is **locked until that node is bought**; a thing no node names keeps today's
rule (its quest, its price, or free). A node whose gift the save already has (an outlaw already owned, an item whose
old quest was done, a stage already open when the Trail arrived) counts as bought at no cost.

## The rules

1. A node is **closed** when a sibling of its choice group was bought, or when its `from` can no longer be met (a
   needed node is closed; with `any`, all of them are). Closed is for good: choices are permanent, there is no reset
   and no swap (Garry). The developer menu has a reset for testing only.
2. A level is **done** when every node on it that is neither optional nor closed is bought; a choice group is
   satisfied by one member.
3. **Trail Level** = the highest level L with every level 1..L done (0 on a new save).
4. A node is **open** (can be bought) when it is not bought, not closed, on a level no higher than Trail Level + 1,
   and its `from` is met. Otherwise it is **locked**. Optional nodes on done levels stay open.
5. Buying pays the price in the Trail's currency, records the node, and gives its gift at once.
6. The line between the lit and the dark part sits just above level Trail Level + 1.
7. A locked thing reads **"Reach Trail Level N"** where N is its node's level; a tap on that line opens the Trail on
   that node, and Back returns to where the player was.
8. Stakes (creatures tougher for more XP and coins) are optional nodes; once bought they are on for good (Garry).
9. An unlock (`outlaw`, `skin`, `weapon`, `passive`, `stage`, `map`, `structure`, `powerup`, `feature`) should never
   sit in a choice group (it could be lost for good): the editor warns, the game allows it.

## Layout (shared by the game and the editor's preview)

Design width 1080. The right quarter (x > 0.75) is kept free. Levels are rows 236 px apart, level 1 at the bottom.

- Node tile 148 px (132 px on a level with four). Auto places across the width by count:
  1 -> 0.50; 2 -> 0.33, 0.60; 3 -> 0.20, 0.42, 0.64; 4 -> 0.12, 0.30, 0.48, 0.66. Required nodes take the places
  from the centre outward in file order, optional nodes the outer ones.
- The level's number in a diamond at x 0.06, on every level.
- Links: a 22 px rail from each `from` node; bought rails are lit, others dark. A choice group's members are joined
  by a bar with a lock mark (one may be taken).
- Screen opens centred on the node bought last (a new save: level 1); from a requirement tap, on that node, ringed.
- Above the last level: the `end.text` plate.

## `Trail.gd` (names the other code relies on)

```
Trail.reload(path := DEFAULT)           # tests load a fixture
Trail.nodes() -> Array[Dictionary]      # file order; Trail.node(id); Trail.levels() -> int
Trail.state(id) -> "bought" | "open" | "locked" | "closed"
Trail.level() -> int                    # Trail Level
Trail.level_done(l) -> bool
Trail.price(id) -> int
Trail.can_buy(id) -> bool               # open and affordable
Trail.buy(id) -> bool
Trail.any_affordable() -> bool          # the tab's red crumb
Trail.gate(type, id) -> Dictionary      # the node that gives it, {} if none
Trail.has(type, id) -> bool             # no gate, or its node is bought
Trail.level_for(type, id) -> int        # N of "Reach Trail Level N", 0 if no gate
Trail.effects() -> Array                # [{effects: Array[Effect], name, source}] for Run.hero_sheet
Trail.give_text(node) -> String         # "Attack damage +3%", "Outlaw: Astro"
Trail.sections(), Trail.upgrade(type)   # for the screen
Trail.check(data) -> Array[String]      # the same warnings the editor shows
```
