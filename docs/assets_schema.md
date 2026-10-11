# The asset schema (pass 66)

What the Level Editor's Enemies, Heroes, Items and Jobs tabs read and write, beside the wave timeline (`waves_schema.md`).
Everything is a content folder under `game/content/<type>/<id>/` with `<id>.json` as the authoring source; the game plays
the generated `<id>.tres` (`import_json.gd`). The editor writes a JSON **in place, line by line**: only the keys it comes
for change, the file's own indent and line endings stay, so a one-number change is a one-line diff in git. When a write
cannot be made that way (a hand-edited, compact file) the editor refuses rather than re-dumping; a job that could not
merge its result ends `done` with `written.layout: "unmerged"` and offers "Merge again" and "Re-dump this file (changes
its layout)" as explicit clicks. Keys the editor does not know are never removed.

Keys marked *tool-only* are read by the art tools (`gen_art.py`, `gen_ctl.py`, ...) and never by the game.

## Looks: `variants`, `variant`, `variant_base` (creatures, bosses, heroes)

A **look** is one painted strip (and, for a creature, its icon) of an asset. The JSON's top-level `sprite` / `icon` /
`anims` / `strip_cols` / `fps` / `head` describe the **base** strip; every other look is an entry of `variants`:

```json
"variant": "LS-B",
"variant_base": "LS-B",
"variants": {
  "LS-A": {"note": "Simple: flat black, two tones", "sprite": "lesser_scorpion_sprite_a.png", "icon": "lesser_scorpion_icon_a.png",
           "anims": {"idle": 4, "run": 12, "attack": 2, "hit": 1, "die": 8, "run_b": 12, "idle_b": 4, "run_s": 12, "idle_s": 4,
                     "run_bd": 12, "idle_bd": 4, "run_fd": 12, "idle_fd": 4},
           "strip_cols": 91, "fps": {"run": 20, "die": 12}, "head": 0.887,
           "front_faces": "right", "back_faces": "right",
           "shelved": true, "fresh": true,
           "recipe": {"method": "creature_pose2", "pose": "walk_zombie"}}
}
```

| Key | Where | Type | Default | What it does |
|---|---|---|---|---|
| `variant` | top | code | `variant_base` | the look the game plays for every row, wave and event that names none (the Level Editor's "Make default") |
| `variant_base` | top | code | absent | the code of the top-level strip; a creature without `variants` gets `"<PREFIX>-0"` (a hero `"<PREFIX>-A"`) and a matching entry `{"note": "the top-level strip, before the Level Editor's looks"}` when its first look is added |
| `variants[CODE].sprite` | entry | file | — | the strip beside the JSON (`<id>_sprite_<suffix>.png`; `res://` paths allowed). An entry **without** a sprite is a *stub*: a job's placeholder (queued, running, failed or cancelled); the game skips it |
| `.icon` | entry | file | the base icon | creatures: the look's icon (a crop of its front still unless icon candidates were installed). A hero's badge and title cut-out belong to the hero, never to a look |
| `.note` | entry | text | `""` | shown on the look cards and the arena chips |
| `.anims` | entry | `{name: frames}` | the base's | the frame counts in the strip's fixed order: creatures `idle run attack hit die run_b idle_b run_s idle_s run_bd idle_bd run_fd idle_fd`; heroes `idle run turn hit die cheer idle_f run_f idle_s run_s idle_bd run_bd idle_fd run_fd hit_f hit_s hit_bd hit_fd`. A strip has 8 directions when `run_s > 0`, else 2 |
| `.strip_cols` | entry | int | the base's / one row | columns of the strip grid (`min(frames, 16000 / frame_px)`); frame k sits at `((k % cols) * frame_px, floor(k / cols) * frame_px)` |
| `.fps` | entry | `{run, die, hit}` | the base's | the rates the game reads: creatures `run` (× the map's pace; 10 when 0) and `die` (6); heroes by name prefix (`run` 14, `hit`, `die`), the rest BillboardSprite's table |
| `.head` | entry | 0..1 | the base's | where the head sits in the cell from the top (the hit flash, the elite crown) |
| `.frame_px` | entry (heroes) | int | the base's | a hero look may have its own cell size; a creature look always uses the base's |
| `.front_faces`, `.back_faces` | entry or top | `right` \| `left` \| `straight` | `right` | which way the front (or back) painting turns: the game mirrors it for heading left under `right`, the other way round under `left`, never under `straight`. Side and diagonal sets always face right |
| `.shelved` | entry | bool | absent | **pass 66**: the look stays in the JSON but is hidden from the arena chips and every default list (`variant_codes()`); a map row that names the code still plays it. The look in play (`variant`) cannot be shelved |
| `.fresh` | entry | bool | absent | **pass 66**, page-only: painted by a job and not yet looked at (the NEW chip). Approve deletes the key; the game ignores it |
| `.recipe` | entry | object | absent | *tool-only*: what the art job reads for this code (`method` plus the method's recipe fields: `pose`, `motion`, `death`, `drivers`, `words`, ...; see `tools/level_editor/methods.json`) |

**Codes.** `PREFIX-SUFFIX`. PREFIX = the most common prefix of the existing `variants` keys, else `variant_base`'s, else
the initials of the id's words (`dune_scorpion` → `DS`; a one-word id takes its first three letters, `goblin` → `GOB`).
SUFFIX = the first free of A..Z, then AA..; a suffix whose `<id>_sprite_<suffix lower>.png` or `<id>_icon_<...>.png`
exists is skipped; stub entries count as used. The server allocates them (`GET /api/content/<kind>/<id>/next_codes?n=`).
Derived names: strip `<id>_sprite_<suffix lower>.png`, clip cache key part `code.lower().replace("-", "")`, marker
`<id>_<suffix>_ai.json`.

**Removing a look** deletes the entry; its PNGs and their `.import` files move to
`tools/level_editor/backups/deleted/<id>/<stamp>/`. Refused for the look in play and for a code a map row names.

## Heroes (`content/characters/<id>/<id>.json`)

| Key | Type | Default | What it does |
|---|---|---|---|
| `hidden` | bool | `false` | out of the title and the Collection; **kept in step** with `availability` (`hidden = availability != "available"`) |
| `availability` | `hidden` \| `available` \| `purchase` | derived from `hidden` | **pass 66**: shown and written, not wired: a `purchase` hero stays hidden in play until the purchase loop is built (parked) |
| `price` | int ≥ 0 | `0` | the purchase price (not wired) |
| `currency_type` | `gold` | `gold` | the currency (the list has one entry; not wired) |
| `title_pose`, `title_holds`, `title_camera` | text | absent | *tool-only*: the title cut-out's words (`gen_title_heroes.py` reads them before its own tables, then `portrait_prompt`) |
| `title_extra_ref` | `{file, words}` | absent | *tool-only*: a second reference for the cut-out (the held object) and what it is |
| `portrait_prompt` | text | absent | *tool-only*: the round badge's bust words |
| `badge` | `{still, head_width, top_pad}` | absent | *tool-only*: how the badge is cut from a still |
| `pose_drivers` | `{view: driver}` | `run` for every view | *tool-only*: the OpenPose driver per view (`front back side bd fd`) |
| `still_keys` | `{view: key}` | absent | *tool-only*: cached stills to reuse per view |
| `run_fps` | int | 36 | *tool-only*: the run cycle's rate written into `fps.run` |

A hero created from a template starts `hidden: true` / `availability: "hidden"`. The five playable heroes are pinned by
tests: the Heroes tab says so beside the availability switch.

## Items (weapons, evolutions, mutations, lines and passive items)

Availability is **derived**, never a key of its own: `hidden: true` → hidden; a quest whose `unlocks.id` is the item →
locked by that quest; else available (it enters the pool at its rarity's weight). The availability switch creates or
removes `content/quests/unlock_<id>/unlock_<id>.json` in the shape of `unlock_adrenaline.json`.

A **new weapon** is created `hidden: true` with its three template mutations `<w>_element`, `<w>_volume`, `<w>_motion`
(kinds element / volume / motion) and its template evolution `<w>_evolved`, all hidden (`NEW_WEAPON_STARTS_HIDDEN` in
`server.py`, BALANCING §13). It may turn available only when each template mutation has `text` and at least one effect
or param and the evolution has a `name`; the availability check lists what is missing. Lines and passive items are
created available. The quest-locked band test (pass 44: 0.33..0.56 of the items locked) stays; the Items tab shows the
band and warns when a change would leave it.

## A creature created from a template

Copies the template's JSON with the identity reset (`id`, `name`, `flavour`, `doc`: the create dialog asks for a one-line
`doc`), `knockback` written out as `clamp(3.4 * sqrt(damage / 4), 2.5, 7.0)` (EnemyDef.default_knockback), `blood` from
the template, no `strip_cols` / `anims` / `fps` / `head` (a placeholder strip of one row) unless `copy_art` is ticked, which
copies the template's PNGs under the new name. The created id goes into the ledger (below).

## The look record (what `/api/enemies`' `variants[]` / `looks[]` and `/api/heroes`' `looks[]` carry)

`{code, note, icon, sprite, ready, base, default, anims, fps, strip_cols, frame_px, head, front_faces, back_faces,
shelved, fresh, imported, sprite_mtime, has_recipe, recipe}`

- `ready`: the game can play it (the base strip, or an entry whose strip is on disk). `false` on a stub.
- `default`: `code == variant` (the look in play).
- `imported`: the strip PNG's `.import` exists **and** the `.tres` is at least as new as the JSON **and** as the PNG.
  Otherwise the card says "not imported": the game plays the old data until an import runs (Save, or a finished job's
  `import` step).
- `sprite_mtime`: the strip's mtime; the page appends `?v=<sprite_mtime>` to bust the strip route's 60 s cache.

## The jobs queue (`tools/dl/jobs/`, git-ignored)

`queue.json` `{rev, jobs: [record]}` (atomic, `rev` monotonic); per job `tools/dl/jobs/<id>/{job.json, result.json,
log.txt, ...}`; ids `j<YYYYMMDD>-<HHMMSS>-<4hex>`. Uploads `tools/dl/uploads/2d/<name>`, `tools/dl/uploads/3d/<slug>/`
(+ `probe.json` and the renders beside it).

Record: `id, kind, method, lane (comfy | godot | local), state, title, target {kind, id, code}, spec {method, recipe,
refs[], drivers, flags {skip_qa, dev, seed}, counts {seeds, ...}, job {...}, note}, phase, attempt, created, started,
ended, pid, cmd, equiv (the command Claude would type), progress {done, total, stage, stages[{name, state, secs}],
last_output, stalled}, eta_s ("~" always: the method's median × its stages), log_file, log_tail, outputs[{label, type
still | clip | strip | sheet | icon, url, frames, fps, cache_key, clip_kind, qa}], choices[{key, label, url, sheet,
cache_key}], cache_keys {stills, clips}, error, qa_online, written {file, keys, backup, layout block | entry |
unmerged}, lock_waits`.

States: `queued → running → done | failed`; `running → waiting` (a human pick: the side candidates of `creature_ctl`, a
picture's front candidates) `→ pick → queued` (phase + 1, the front of its lane); `cancelled`; `interrupted` = every
`running` job when the server starts (its process is gone). A job may be edited in every state but `running` (a
waiting job goes back to `queued` at phase 1); re-queued from any finished state (attempt + 1, optionally with a
re-roll: new seeds · keep the stills, redo the clips · redo one view · repaint the stills).

Kinds and lanes: `look` (methods `hero_pose5 hero_fit creature_free2 creature_pose2 creature_free8 creature_ctl
creature_proc front_from_picture recolour`), `item_icon`, `icon_cands`, `hero_badge`, `hero_title` → the **comfy**
lane (one ComfyUI job at a time); `register`, `import` (consecutive imports coalesce their targets), `launch` (Test in
game: the window holds the Godot lock while it lives) → the **godot** lane; `driver_pose`, `driver_depth`, `ref_probe`,
`ref_render` (Blender), `install` → the **local** lane. The method catalogue with every field is
`tools/level_editor/methods.json`.

`spec.refs[]` entries: `{path, role: identity | style | pose, follow: loosely | closely | copy, use: [look | icon]}`.
There is no strength number: references steer by which pictures are passed, in what order, and the words
(`methods.json` → `ref_wordings`).

## The ledger (`tools/dl/jobs/created.json`)

`{ids: {<id>: {kind, created, template}}}`: every asset the editor created. **Delete** is allowed only for ledger ids;
the ledger is local and git-ignored, so after a fresh clone Delete is refused for everything (that is intended: the
editor never deletes hand-made content).

## Locks (`tools/dl/locks/`)

`comfy.lock/` and `godot.lock/`: mkdir locks with `owner.json {pid, who, job, note, since, beat, host}`. One ComfyUI job
and one Godot process at a time across the Level Editor's jobs, Claude's scripts and the lanes (`tools/godot.sh`,
`tools/locks.py`). A lock whose owner's pid is dead is reclaimed; a lock folder without `owner.json` is never reclaimed
by code (the Jobs tab shows "held by an unknown process" and offers Force release). Children of a holder pass through
with `LOCK_HELD_COMFY=1` / `LOCK_HELD_GODOT=1`.

## Test in game (`user://debug_launch.json`)

Keys Game.gd reads: `character, map, map_seed, weapon, level, spawn, analytics` + **pass 66** `arena: bool` (decided
before `Run.arena_next`), `look: CODE` (the hero's look, the save untouched), `spawn_enemy: id`, `variant: CODE`, `count:
int` (default 3). The `launch` job writes the file right before the window opens and deletes it if the process dies with
it still there.
