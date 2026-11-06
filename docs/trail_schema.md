# The Trail: data, rules and names

The Trail is the game's permanent progression (pass 129; it replaces the Upgrade board, "the Mirror" in code). One
long track of nodes bought with gold, read from one JSON file and edited in the Level Editor's Trail tab. Garry's brief
and his answers (2026-11-06) are the source of every rule here; a rule he did not ask for is marked *(lead)*.

- Data: `game/content/trail/trail.json` (plain JSON read at run time, like `content/wanted/wanted.json`; no `.tres`).
- Icons: `game/art/ui/trail/<icon>.png`, 256 px, transparent.
- Runtime: `game/core/systems/Trail.gd` (static; the one place the rules live). Screen: `game/ui/TrailScreen.gd`.
- Save: `Save.data.trail = {"bought": [<node id>, ...], "spent": <gold>, "had": ["<type>:<id>", ...]}` (`had`: the
  gifts the save had before the Trail, written once by the migration; see "The save and the migration").

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

- Node tile 148 px (132 px on a level with four). The level's **required** nodes (plain and choice) are placed
  among themselves by their count, **left to right in file order**: 1 -> 0.50; 2 -> 0.33, 0.60; 3 -> 0.20, 0.42,
  0.64; 4 -> 0.12, 0.30, 0.48, 0.66. So the track's spine stays where it is whether or not a level has optional
  nodes.
- **Optional** nodes (tile 116 px) hang beside them: the first 0.20 to the right of the rightmost required node
  when that is no further right than 0.68, else 0.20 to the left of the leftmost; a second one takes the other
  side; any more keep stepping outward on the left. A level with only optional nodes places them by the count
  table. An `x` on a node always wins.
- The level's number in a diamond at x 0.06, on every level.
- Links: a 22 px rail from each `from` node; bought rails are lit, others dark. A choice group's members are joined
  by a bar with a lock mark (one may be taken).
- Screen opens centred on the node bought last (a new save: level 1); from a requirement tap, on that node, ringed.
- Above the last level: the `end.text` plate.

## `Trail.gd` (names the other code relies on)

As built in pass 129 by lane TRAILCORE (`game/core/systems/Trail.gd`, every function static; tests
`game/tests/pass129_trail_test.gd` on `game/tests/fixtures/trail_*.json`). **One name differs from the first draft of
this page: `Trail.load_from(path)`, not `Trail.reload(path)`.** `Trail` is a script, and `Trail.reload(...)` reaches the
engine's own `Script.reload(keep_state)` instead of ours; no other name collides.

```
# the file
Trail.load_from(path := Trail.DEFAULT)  # reads the Trail again; tests load a fixture, load_from() goes back to the game's file
Trail.load_data(d: Dictionary)          # the Trail from a dictionary shaped like the file (a preview, a test)
Trail.read_file(path) -> Dictionary     # the file as a dictionary ({} when missing or not an object); what check() takes
Trail.has_nodes() -> bool               # false: nothing is gated, nothing can be bought (the game's file today)
Trail.nodes() -> Array[Dictionary]      # file order, normalised (below); Trail.node(id) -> Dictionary ({} unknown)
Trail.levels() -> int                   # the highest level a node stands on
Trail.nodes_on(l) -> Array[Dictionary]  # the nodes of one level, file order
Trail.group(id) -> Array                # a choice's group, itself among them ([] for a node that is no choice)
Trail.from_of(id) -> Array              # the node ids a rail is drawn from: its `from`, else the required, not closed
                                        # nodes of the nearest lower level (a group as the one chosen, all while none is)
Trail.currency() -> String              # "gold" (an id the content lacks reads as gold)
Trail.sections() -> Array               # [{from, name, top, bottom, motif}] by `from`; Trail.section_at(l) -> Dictionary
Trail.upgrade(type) -> Dictionary       # {name, icon, kind, text, effects, warn}; Trail.upgrade_types() -> Array (file order)
Trail.icon_path(type) -> String         # res://art/ui/trail/<icon>.png; Trail.icon(type) -> Texture2D (null: not painted yet)
Trail.end_text() -> String

# the rules
Trail.state(id) -> "bought" | "open" | "locked" | "closed"   # an unknown id is "locked"
Trail.level() -> int                    # Trail Level
Trail.level_done(l) -> bool
Trail.price(id) -> int                  # Trail.price_at(price_cfg, level, mult := 1.0) -> int is the bare curve
Trail.can_buy(id) -> bool               # open and affordable
Trail.buy(id) -> bool                   # pays (Currency, reason "trail"), Save.trail_buy, event `trail_buy`
Trail.any_affordable() -> bool          # the tab's red crumb
Trail.refresh()                         # forget the cached states (only needed after editing a save list in place)

# the gates (type: outlaw, skin, weapon, passive, stage, map, structure, powerup, feature)
Trail.gated(type, id) -> bool           # some node gives it
Trail.gate(type, id) -> Dictionary      # the node that gives it (the lowest when several do), {} if none
Trail.has(type, id) -> bool             # no gate, or a node that gives it is bought
Trail.level_for(type, id) -> int        # N of "Reach Trail Level N", 0 if no gate
Trail.requirement_text(type, id) -> String   # "Reach Trail Level N", "" if no gate
Trail.gift_key(gives) -> String         # "<type>:<id>", "" for an upgrade
Trail.stage_key(map_id, i) -> String    # "<map>:<stage id>" of stage index i; Trail.stage_index(map_id, stage_id) -> int
Trail.stage_open(map_id, i) -> bool     # what Save.stage_unlocked asks beside its own rule
Trail.rows_open(type, rows) -> Array    # a weighted roster [{id, ...}] without the locked ones (the same list with no gate)

# the stats and the words
Trail.effects() -> Array                # [{effects: Array[Effect], name, source, type, value}] for Run.hero_sheet
Trail.total(type) -> float              # the summed value of one upgrade type over the bought nodes
Trail.give_text(node) -> String         # "Attack damage +3%", "Outlaw: Astro", "Skin: The Drifter, Black Hat", "Weapon: ...",
                                        # "Card: ...", "Item: ...", "Stage: Nightfall", "Map: ...", "Structure: ...",
                                        # "Power-up: ...", "The Bounty Board"
Trail.amount_text(kind, value) -> String     # "+3%", "+2.5%", "+2", "+1", "+2 s", "" for a word
Trail.note_text(Save.board_note()) -> String # the migration's toast, "" for any other note
Trail.record() -> Dictionary            # the run record's block {level, bought: [ids], paid, spent, upgrades: {type: sum}}

# the editor's warnings, the migration
Trail.check(data) -> Array[String]      # "<where>: <what>" lines, [] for a sound file (list below)
Trail.had_before() -> Array             # the gifts the save has by the rules as they were (Save._migrate_trail)
```

A normalised node (`Trail.nodes()`, `Trail.node(id)`): `{id, level (>= 1), kind (an unknown one reads as "node"),
group ("" unless a choice), from ([] = the default; ids the file does not have, and its own, are left out), need
("all" | "any"), gives ({} when the file has none), gift ("<type>:<id>" as gated, "" for an upgrade), price_mult,
name, note, index (its place in the file)}`, plus `price` and `x` only when the file gives them. A node without an id,
and the second node of an id used twice, are left out.

### How the rules were read where this page left room

- A `from` left out is never what locks or closes a node: rule 4's level gate already asks for every required node
  below it. `Trail.from_of(id)` gives the default links for drawing.
- A node is closed by its `from` only when it names one (`all`: any of them closed; `any`: every one closed). A ring of
  `from`s counts as closed.
- A bought node is never closed: when a save holds two siblings of a group (both gifts already had), both are bought.
- Several nodes may give the same thing (the editor warns): it is the player's once any of them is bought.
- A level with no node, or whose every required node is closed, is done (the Trail Level passes it).
- A choice with no `group` forms a group with the other group-less choices of its level.
- Buying an unlock records only the node: the gift is the player's because `Trail.has` says so (nothing is written to
  `heroes_owned` or `skins_owned`). An outlaw or a skin the save owns there counts its node as bought.

### What asks the Trail (pass 129's hooks)

Each asks the Trail first and keeps its old rule for a thing no node names. Outlaws: `Registry.hero_state` (locked,
then owned: never "buyable"), `hero_requirement_text`. Skins: `Registry.skin_state`, `skin_requirement_text`. Weapons,
cards, items, maps: `Registry.is_unlocked`. Stages: `Save.stage_unlocked` (its own rule **and** the Trail), the line in
`StagesScreen.requirement`. Structures: `StructureManager.in_play`. Power-ups: the kill drops and a timed roster
(`WaveDirector.drop_pickup_from`, `_spawn_pickup`), the barrels' throws (`BarrelField._throw_powerup`), a creature's
own drop, the Cake and Pickpocket drops, the Supply Drop perk (`Game.gd`). The Bounty Board: `WantedBoard.unlocked`.
And `Registry.quest_visible` is false for a quest whose thing a node gives (not shown, not tracked). **Screens that
read a quest directly for a locked outlaw's line** (`HeroesScreen` ~458/474, `TitleScreen` ~452, `WHeroSheet` ~562,
`CollectionScreen`) still do: lane TRAILUI switches them to `Registry.hero_requirement_text` /
`Trail.requirement_text` and makes the line a tap (rule 7).

### The save and the migration

`Save.trail_bought() -> Array` (ids paid for, in buying order), `Save.trail_spent() -> int`, `Save.trail_had() ->
Array`, `Save.trail_buy(id, cost)` (records only; `Trail.buy` pays), `Save.trail_reset(forget_had := false) -> int`
(the developer menu's two rows: every bought node forgotten and its coins back; with `forget_had` the save meets every
gate like a new one).

`Save._migrate_trail()` runs once per save (once-flag `trail_v129`) and only once the Trail has nodes. It pays every
coin the Upgrade board cost back in full, clears its ranks, leaves `Save.board_note() = {kind: "trail_refund", gold,
ranks}` (the Trail screen shows `Trail.note_text(note)` and calls `Save.clear_board_note()`; the old board's screen
leaves this kind alone), and writes into `trail.had` every gift the save has by the rules as they were: outlaws and
skins owned, weapons / cards / items / maps not locked, stages open, structures and power-ups in play, the Bounty
Board when it had opened. **A save that has never started a run is a new save *(lane TRAILCORE; the lead confirms)*: it keeps nothing.** `had` holds
every such thing, not only the ones a node names today, so a node added later still counts as bought for that save.

`game/content/trail/quests_before.json` lists the unlock quests as they stood when the Trail arrived
(`"<quest type>:<id>": quest id`). A quest may be deleted once a node gives its thing: the migration then counts the
thing as had only when that quest's id is in the save's done list. Do not edit the file; a quest added after pass 129
does not belong in it.

### `Trail.check(data)`: the warnings

`price`: missing, a key that is not a number, a negative one. `currency`: not one the content has. `sections`: none,
the first not at level 1, one not after the one before, a colour that is not six hex digits, an unknown motif.
`upgrade '<type>'`: no name, unknown kind, no icon, its icon file missing, no effects, a stat the outlaw's sheet does
not have, an op other than add / mul, `per` 0. `node <id>`: no id, an id used twice, level under 1, unknown kind, a
choice without a group, a group on a node that is no choice, `need` other than all / any, `from` naming itself, no
node, a node above it, or a node of its own level (only an optional node may), `from` not a list, a price under 0, a
`price_mult` of 0 or less, `x` outside 0..1 or in the right quarter (over 0.75), gives nothing, an unknown gift type,
an unknown upgrade type, an upgrade without a value, an unlock that names nothing, a thing another node gives too, an
unlock in a choice group (rule 9), a thing the content lacks or that is hidden, a look the outlaw lacks or the one every
player owns, a stage the map lacks, the map's first stage, an unknown feature. `choice group`: fewer than 2 or more
than 4 members. `level N`: more than 4 nodes; no nodes at all below the top.

From a shell, the game's own reading of a file (its counts, what every node costs together, each warning; exit 1 with
any): `bash tools/godot.sh --headless --path D:/_projects/88fits/game --script res://tools/trail_check.gd --log-file
<f> [-- file=<res:// or absolute path>]`.
