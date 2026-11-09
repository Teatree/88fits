# Pass 137 wave 2: moving every player text into the string table (rules from lane LOCKIT)

Read first: `.claude/skills/game-texts/SKILL.md` (the system, the key families, the proofs). The runtime is
`game/core/systems/Loc.gd`; the table `game/content/strings/en.json`; the pilot that shows every rule below on real code:
`game/ui/PortalDialog.gd`, `game/ui/StrangerScreen.gd` and TextGen's ProjectileEmitter branch (`git diff` them).

**The one promise: no text changes.** Garry: "double check that the texts haven't changed after your changes". Every
row you add holds exactly the words the literal had (case, punctuation, curly quotes, spaces, `·`, `×`, `→`). Wording
fixes are Garry's, later, in the Texts tab. If a literal reads wrong, note it in your status.md; do not fix it.

## Per file

1. **Key names.** `ui.<screen>.<what>` with `<screen>` the file's screen in lower snake (`ui.results.play_again`,
   `ui.pause.resume`, `ui.collection.locked`), `<what>` what the text IS, not where it sits (`title`, `deal`, `foot`,
   `kills`). Messages: `toast.<what>`, `hint.<step>`, `banner.<what>`. TextGen and other generated sentences:
   `gen.<family>.<shape>` (`gen.weapon.shot.priority`, `gen.passive.rule.thorns`, `gen.quest.kill_enemy`), shared words
   `gen.word.<what>` (`gen.word.nth.2` = "second"). Stats: `stat.<id>.name`, `stat.<id>.rule`. One item's own row:
   `weapon.<id>.desc`, `evolution.<id>.desc`, `passive.<id>.desc` (pre-filled with exactly the template's text, used
   through `Loc.t_first([own, generic])` only when the item's sentence is the shape it comes with; see `_pe_shape` /
   `_home_params` in TextGen for the pattern). Reuse an existing key only when it is the same text in the same role.
2. **Concatenations become one template.** `"%s · %s kills · %s. Bank it..." % [a, b, c]` ->
   `"{time} · {kills} kills · {level}. Bank it..."` with `{"time": a, "kills": b, "level": c}`. `text += " Every %s pull"
   ...` -> `text += " " + Loc.t("gen.weapon.hip_shot", {...})`: the joining space stays in code, the row starts with
   the word. A sentence assembled from optional pieces (TextGen's extras) stays assembled in code, one row a piece.
3. **`%` formats**: the number is formatted in code exactly as before (`"%.0f" % range_m`, `"%.1f" % s`, `str(n)`,
   `W.num(n)`) and handed in as a string; `%%` in the old literal is a plain `%` in the row.
4. **Plurals and either-or**: `"shot%s" % ("" if n == 1 else "s")` -> `{amount?shot:shots}`; `"a spear" if n == 1 else
   "%d spears" % n` -> `{amount?a spear:{amount} spears}`. The selector's "1" is the value handed in: hand in the same
   number the old test used (`amount`, not a different count). Where the old code did NOT pluralise ("%d volleys"),
   keep it unpluralised: the text must not change.
5. **Word tables** (`{2: "second", 3: "third"}`, `RARITY_NAMES`, `STATS` names, `RULE_TEXT`, `HERO_WORDS`): one row a
   word under a pattern key (`gen.word.nth.%d`), looked up with `Loc.has(...)` and a generic fallback row
   (`gen.word.nth.n` = "{n}th"). Keep the const's shape when tests or other files read it (grep first); a table whose
   values are only read through one function may become keys only. `RULE_TEXT`'s own `{n}` placeholders map straight to
   Loc variables.
6. **Consts holding text** cannot call Loc (parse time): `const FOOT := "Not ready..."` -> `const FOOT_KEY :=
   "ui.portal.foot"` and `Loc.t(FOOT_KEY)` where it is used (loc_verify reads a `*_KEY` const as an added key).
7. **Texts built in loops** (rows, lists): the loop stays; the row's template is one key with the loop's values as
   variables. A list joined with ", " stays joined in code.
8. **Texts drawn with `draw_string`** (WSeal, WPlate, HUD numbers, ResultsScreen counters): convert the string the
   function draws (it is usually a property or a const above it); the census reaches only what a node holds in `text` /
   `runs`, so these rely on loc_verify and a capture look.
9. **Upper-casing in code** (`.to_upper()`, `W.caps(...)`): the row keeps today's literal case and the call stays.
   Never upper-case a row by hand to drop a `.to_upper()`.
10. **Not converted** (not player text, or not yet): developer surfaces (`ui/DevMenu.gd`, `ui/ArenaPanel.gd`,
    `ui/ArenaShots.gd`, `ui/DebugPanel.gd`, `ui/DebugHand.gd`, `ui/UiKit.gd`'s debug parts, `replay/`, `game/tools/`,
    the Watch), `print` / `push_warning` / logs, analytics and replay event names, ids, node names (`x.name = "Extract"`),
    theme keys, sound ids, file paths, `WPlaceholder` art notes, number-only formats (`"%s → %s"`, `"×%d"`, `"%d s"` unit
    helpers: leave `_secs`, `W.mmss`, `W.num`, `W.lv` as they are this pass and say so in status.md), content JSON
    fields (already in the tab). Strings in tests stay.
11. **Content words read through code** (`def.display_name`) are not converted: they already live in their JSON rows.

## Proving it, per lane

Before your first edit and after your last, back to back on the same tree (other lanes keep editing):

```
L=D:/_projects/88fits/tools/dl/p137/<LANE>
bash tools/godot.sh --headless --path D:/_projects/88fits/game --log-file $L/census_before.log --script res://tools/text_census.gd -- out=$L/census_before.json
... your conversion ...
bash tools/godot.sh --headless --path D:/_projects/88fits/game --log-file $L/census_after.log --script res://tools/text_census.gd -- out=$L/census_after.json samples=1
python tools/text_census_diff.py $L/census_before.json $L/census_after.json          # must say "no difference"
python tools/loc_verify.py --files game/ui/X.gd game/ui/Y.gd                          # must say "every removed text is accounted for"
bash tools/godot.sh --headless --path D:/_projects/88fits/game --log-file <abs> -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/pass137_loc_test.gd
```

- A full census (`parts=a,b`) takes about 6 minutes under the Godot lock; `parts=a` (TextGen and its kin, exact) takes
  15 s; `only=portal,stranger` limits part b to touch_audit's screens of those names (the lane's own screens).
- The diff's `SCREEN ... reached in one run only` lines are touch_audit not reaching a screen (another lane's half-done
  edit, a crash): not a text change, but your screen must be reached in both runs to count as proved.
- Part c (toasts seen while the screens play) is timing-dependent; check its differences by eye.
- `test_every_key_in_code_exists` fails on any `Loc.t("key")` without its row; keys built with `%` are checked by
  loc_verify only.
- Old tests that compare a screen's text to a literal keep passing (the text did not change); a test that reads a
  const you turned into a key needs that const kept or the test pointed at `Loc.t(...)`.

## Proposed split into three lanes

Counts are literals that read as player text (`yes`) in today's tree (`tools/dl/p137/LOCKIT/literal_counts.txt`, made
by loc_verify's own classifier; it over-counts files full of ids and logs: Analytics, RunReplay, Save, MeshMerge,
EnemyManager, SignField, TornadoFx have few or none that a player reads). Files the wave-1 lanes edited (ResultsScreen,
TrailScreen, PauseScreen, ReviveScreen, SettingsScreen, WTabBar, Game.gd) are converted after the lead's merge, against
the merged tree.

| Lane | Files (player-text literals) | About |
|---|---|---|
| **W2-TEXTGEN**: TextGen and core words | core/systems/TextGen.gd (345, the rest of `weapon_description` after the pilot's branch, passives, quests, heroes, stats, changes), core/systems/Trail.gd (68: give_text, requirement_text, bundle_text, note_text; keep trail_bundle.js / trail_bundle.py in step: they mirror bundle_text and a fixture pins the three), core/systems/WeaponInstance.gd (25, stat row names), ui/wanted/WItem.gd (39, card words), core/autoload/Run.gd (32), core/autoload/Registry.gd (16, requirement texts), core/systems/WantedRun.gd (8), core/systems/TotemBoons.gd (7), core/systems/StatSources.gd (6), core/systems/HeroPower.gd (6), core/systems/DrumBoost.gd (5), CardPool, Currency, BossChest, CharacterDef, WantedBoard (2-3 each) | ~570 |
| **W2-HUB**: hub screens and the kit | ui/CollectionScreen.gd (78), ui/wanted/WHeroSheet.gd (63), core/autoload/Save.gd (65: the toasts and notes it hands the screens only), ui/SettingsScreen.gd (48), ui/TitleScreen.gd (33), ui/HeroesScreen.gd (31), ui/TrailScreen.gd (29), ui/StagesScreen.gd (24), ui/wanted/W.gd (13), ui/wanted/WTabBar.gd (12), ui/wanted/WSurvey.gd (8), ui/wanted/WConsent.gd (7), ui/Boot.gd (6), ui/wanted/WPlate.gd (5), ui/TitleStage.gd, WCard, WPoster, WConfirm, WChest, WModal, WPointer, WSeal (1-2 each), core/autoload/Settings.gd (5), core/systems/StageLook.gd (2) | ~440 |
| **W2-RUN**: in-run screens and Game's toasts | game/Game.gd (87: toasts, banners), ui/PauseScreen.gd (44), ui/ResultsScreen.gd (44), ui/CardScreen.gd (39), ui/ReviveScreen.gd (31), ui/HUD.gd (28), ui/ChestScreen.gd (25), ui/BossChestScreen.gd (19), player/Player.gd (10), ui/Hints.gd (8), ui/GrindMoment.gd (7), ui/StructureShop.gd (5), ui/BountyPosters.gd (4), ui/TotemScreen.gd (4), world/maps/red_canyon/RedCanyon.gd, core/behaviors/*, EnemyManager, IronHorse, BarrelField, DamageNumbers, DrumMoment, RunCurtain, ResumeGate (check each: most are ids) | ~430 |

Done in the pilot (wave 1): ui/PortalDialog.gd, ui/StrangerScreen.gd (their `WPlaceholder` note and number formats
stay), TextGen's ProjectileEmitter sentences (`gen.weapon.shot.*`, `gen.weapon.blast.*`, the four fragments,
`gen.weapon.who.*`, `gen.word.nth.*`, 18 `weapon.<id>.desc` / `evolution.<id>.desc` rows).

Each lane appends its rows to en.json with small edits (keep the keys sorted; two lanes adding rows at once: re-read the
file right before writing, add yours, write it back sorted), runs `python tools/level_editor/strings_io.py --export
<scratch>.csv` once at the end (the tab still reads every row), and runs the census with `samples=1` last so the tab
shows real values.
