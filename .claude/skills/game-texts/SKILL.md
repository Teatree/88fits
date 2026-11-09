---
name: game-texts
description: Add or change any text a player reads in 88fits / Outlaw Survivors (a screen's words, a button, a toast, a hint, a card sentence, a stat name) through the string table (game/core/systems/Loc.gd, game/content/strings/en.json), keep the Level Editor's Texts tab and its icons working, and prove no existing text changed (the census and loc_verify). Use whenever code would put player-facing words on screen, when converting old literals, or when Garry edits texts.
---

# Texts a player reads (pass 137)

Garry edits every player-facing text in the Level Editor's **Texts** tab (or as CSV in Excel). That only works if no
player text is a literal in code. His guide: `docs/howto/texts_and_localization.html` (the tab's Guide button).

## Where a text lives (one source of truth each)

- A content item's own words stay in its JSON (`name`, `flavour`, a mutation's / passive's / perk's `text`, an Outlaw's
  `trait_name` / `trait_text`, a skin's `variants[CODE].skin.name`, trail.json's section / upgrade words, wanted.json's
  task words). The tab reads and writes them there. Key: `<word>.<id>.<field>` (`weapon.revolver.name`); the words are in
  `tools/level_editor/strings_io.py` `CONTENT`.
- Everything the code says goes in `game/content/strings/en.json`: flat `{key: text}`, keys sorted, two-space indent,
  LF, UTF-8 without BOM. Keep it sorted when you add rows (`json.dumps(dict(sorted(d.items())), ensure_ascii=False,
  indent=2) + "\n"`).

## Adding a text

1. Pick a key: dotted lower snake. `ui.<screen>.<what>` (screens, buttons), `toast.<what>`, `hint.<what>`,
   `banner.<what>`, `gen.<family>.<what>` (a sentence built for many items: TextGen), `stat.<id>.name`,
   `weapon.<id>.desc` (one item's own description row), `quest.<type>.text`. Look at neighbours in en.json first.
2. Write the row in en.json, then in code: `Loc.t("ui.portal.extract")`, or with values
   `Loc.t("ui.portal.line", {"time": W.mmss(t), "kills": W.num(k), "level": W.lv(lv)})`.
   - Variables are short and named for what they are in that row: `{amount}`, `{range}`, `{who}`, `{seconds}`.
   - **Numbers are formatted by the code** and handed in as strings (`"%.0f" % range_m`, `str(n)`): the text never decides
     how a number looks.
   - Plurals / either-or: `{amount?shot:shots}` (first part when the value is exactly 1). A part may hold variables:
     `{amount?a spear:{amount} spears}`. A literal brace is `{{` / `}}`.
   - One template for a whole sentence; never glue pieces with `+` or `%` (a translator must be able to reorder them).
   - A text the code upper-cases (`.to_upper()`) keeps today's case in en.json and keeps the call.
3. An item's own variant of a generic sentence: `Loc.t_first(["weapon.%s.desc" % id, "gen.weapon.shot.nearest"], vars)`:
   the item's row when it exists, else the template (a new content folder still gets words, no row needed). A
   pre-filled item row starts as exactly the template's text.
4. `Loc` is static (`class_name Loc`), safe in tools compiled before the autoloads. A missing key shows the key and warns
   once; a missing variable leaves `{name}` and warns once; `Loc.warnings()` lists them (tests assert it is empty).
5. Not player text, stays in code: developer surfaces (DevMenu, ArenaPanel, ArenaShots, DebugPanel, DebugHand, UiKit,
   the Watch, the replay viewer, the Level Editor), logs and `print`, analytics event names, ids, node names, sound ids,
   `WPlaceholder` art notes, and strings with no letters ("%s → %s", "×%d").

## Proving nothing changed

- `bash tools/godot.sh --headless --path D:/_projects/88fits/game --log-file <abs log> --script res://tools/text_census.gd -- out=<abs json> [parts=a,b] [only=<touch_audit screens>] [samples=1]`
  before and after your change (back to back: other lanes change the tree too), then
  `python tools/text_census_diff.py before.json after.json` (exit 1 on any difference). Part a (the generated words) is
  exact; part b (screens) writes numbers as `#`. A full run takes ~6 minutes under the Godot lock; `parts=a` is 15 s.
- `python tools/loc_verify.py [--files game/ui/X.gd ...]`: every literal your diff removed must equal (printf holes and
  {variables} as wildcards, selectors both ways) the en.json text of a key your diff added in that file; every key named
  must exist. Exit 1 otherwise.
- `samples=1` writes `tools/dl/loc/samples.json`: the values the tab shows beside each variable. Run it after adding
  variables so Garry sees real numbers.
- Tests: `game/tests/pass137_loc_test.gd` (every `Loc.t("...")` literal key in game code must exist; the shared render
  cases in `tools/level_editor/fixtures/loc_cases.json`, also run by strings_io.py and strings_model.js).

## The Texts tab (tools/level_editor)

`strings_io.py` (rows, save, CSV, `/api/strings...`), `strings_model.js` (renderer + checks, Loc.gd's twin),
`strings.js` / `strings.css` (the page), `selftest_LOC137.py`. Sub-tabs come from `GROUPS` (key prefix -> group): a new
key family gets a prefix there if none fits. **Icons**: `ICON_FOLDERS` maps a key's first word to a content folder and
`icon_path` finds `<folder>/<id>/<id>_icon.png` (a skin row: `<id>_icon_<letter>.png`). A new content type: add its
folder to `CONTENT` (its text fields) in strings_io.py; it gets icons, rows and the CSV with no other change. If the
three renderers ever change, change Loc.gd, strings_io.py and strings_model.js together and add a fixture case.

Since pass 137 every player-facing file is converted. The detailed conversion rules (concatenations, `%` formats,
selectors, consts as `*_KEY`, texts drawn with draw_string, what is excluded) are in `docs/howto/loc_convert_rules.md`
(pass 137's wave-2 brief, kept). Code that still compares English words (HUD.banner's
"EVOLVED"/"UNLOCKED", PauseScreen's "Knocks enemies back" / "Evolved:", StagesScreen's "Reach Trail Level", WHeroSheet's
" per level") must move to ids or keys before a second language.
