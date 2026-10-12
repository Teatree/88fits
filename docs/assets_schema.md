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
| `.icon` | entry | file | the base icon | the look's icon: a creature's is a crop of its front still unless an icon candidate was picked; **pass 68**: a hero look's own round badge when a badge candidate was picked for it (`<id>_icon_<letter>.png`); the game draws the badge of the look a hero is played in |
| `.icon_picked` | entry | bool | absent | **pass 68**: the icon was picked from candidates; gen_art, gen_ctl and a recolour leave it in place on the look's later runs |
| `.title` | entry (heroes) | file | absent | **pass 68**: the look's own title cut-out, a file name under `res://art/ui/wanted/` (`hero_<id>_<letter>.png`, written by a cut-out pick for the look); the Painted title shows the played look's, else `hero_<id>.png`; the Live title (the default) has no cut-out |
| `.note` | entry | text | `""` | shown on the look cards and the arena chips |
| `.anims` | entry | `{name: frames}` | the base's | the frame counts in the strip's fixed order: creatures `idle run attack hit die run_b idle_b run_s idle_s run_bd idle_bd run_fd idle_fd`; heroes `idle run turn hit die cheer idle_f run_f idle_s run_s idle_bd run_bd idle_fd run_fd hit_f hit_s hit_bd hit_fd`. A strip has 8 directions when `run_s > 0`, else 2 |
| `.strip_cols` | entry | int | the base's / one row | columns of the strip grid (`min(frames, 16000 / frame_px)`); frame k sits at `((k % cols) * frame_px, floor(k / cols) * frame_px)` |
| `.fps` | entry | `{run, die, hit}` | the base's | the rates the game reads: creatures `run` (× the map's pace; 10 when 0) and `die` (6); heroes by name prefix (`run` 14, `hit`, `die`), the rest BillboardSprite's table |
| `.head` | entry | 0..1 | the base's | where the head sits in the cell from the top (the hit flash, the elite crown) |
| `.frame_px` | entry (heroes) | int | the base's | a hero look may have its own cell size; a creature look always uses the base's |
| `.front_faces`, `.back_faces` | entry or top | `right` \| `left` \| `straight` | `right` | which way the front (or back) painting turns: the game mirrors it for heading left under `right`, the other way round under `left`, never under `straight`. Side and diagonal sets always face right |
| `.shelved` | entry | bool | absent | **pass 66**: the look stays in the JSON but is hidden from the arena chips and every default list (`variant_codes()`); a map row that names the code still plays it. The look in play (`variant`) cannot be shelved |
| `.fresh` | entry | bool | absent | **pass 66**, page-only: painted by a job and not yet looked at (the NEW chip). Approve deletes the key; the game ignores it |
| `.recipe` | entry | object | absent | *tool-only*: what the art job reads for this code (`method` plus the method's recipe fields: `pose`, `motion`, `death`, `drivers`, `words`, ...; see `tools/level_editor/methods.json`). It keeps only what differs from the creature's own art words: gen_art does `d.update(recipe)`, so an absent word inherits the top-level one (the editor shows the value that applies with its source: own, inherited, default) |
| `.recipe.painter` | entry | `{model, steps, guidance?, turbo?}` | absent | **pass 66 follow-up**: the painter the look's job ran with (Flux.2 `klein` or `dev`; the passes, 0 = that model's own default; for dev the guidance and whether Turbo was on), written by `jobs.py` from the form's Model settings. Shown on the card, the stage facts and the recipe editor; Re-roll… and Duplicate… start from it; `gen_art.py` reads it on a hand run that names no painter (`ART_*` env and `--model/--steps` flags win). Absent on looks painted before it was kept |
| `.recipe.stills` | entry | slug | see the rule | the key a look's stills are cached under (`<id>_<slug>_<view>`; **pass 68**: heroes too, `hero_pose5` looks): a NEW look's job writes its letter when the key is absent (its own paintings), an EXISTING look's (it has a strip, or it is the base) writes `""` (the paintings it was made from); an explicit `""` = the creature's or hero's own paintings, another look's slug = that look's. `hero_fit` never takes one |
| `.recipe.seed_offset` | entry | int | absent (0) | **pass 68**: a NEW look's own seeds (`1 + crc32(code) % 9973`; every seed moves by 104729 a step), so two new looks with the same words differ; looks painted before pass 68 have none and keep their seeds. A re-roll of the stills moves it by one |
| `.recipe.method` | entry | method id | absent | the method that ran (written by the job; pass 68 records it on every look job) |
| `.recipe.from` | entry | code | absent | **pass 68**: a draft made by Duplicate… names its source (the Generate form offers "reuse <from>'s paintings"); bookkeeping, no tool reads it |
| `.recipe.painter.stills`, `.recipe.painter.reused` | entry | text, [keys] | absent | **pass 68**: when the look's job reused cached stills: `"reused"` (all) or `"N of M painted"`, and the reused keys; the card says the painter changed nothing |

**Codes.** `PREFIX-SUFFIX`. PREFIX = the most common prefix of the existing `variants` keys, else `variant_base`'s, else
the initials of the id's words (`dune_scorpion` → `DS`; a one-word id takes its first three letters, `goblin` → `GOB`).
SUFFIX = the first free of A..Z, then AA..; a suffix whose `<id>_sprite_<suffix lower>.png` or `<id>_icon_<...>.png`
exists is skipped; stub entries count as used. The server allocates them (`GET /api/content/<kind>/<id>/next_codes?n=`).
Derived names: strip `<id>_sprite_<suffix lower>.png`, clip cache key part `code.lower().replace("-", "")`, marker
`<id>_<suffix>_ai.json`.

**Removing a look** deletes the entry; its PNGs and their `.import` files move to
`tools/level_editor/backups/deleted/<id>/<stamp>/`. Refused for the look in play and for a code a map row names.

## Heroes (`content/characters/<id>/<id>.json`)

**`appearance`** (heroes and creatures, top level, optional, pass 68): the character in words without a pose, used as the
*Character* of badge, title cut-out and icon candidates; when absent the `art_prompt` is used with its trailing pose clause
cut (`jobs.appearance_of`).

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
| `momentum` | `{ramp_seconds, speed_bonus, might_bonus, evade_bonus, hit_loss}` | absent | Buck's charge (`specials: ["momentum"]`): full after `ramp_seconds` without a hit; at full, `speed_bonus` more move speed, `might_bonus` more damage and (pass 67) `evade_bonus` evade chance; a hit that reaches his health takes `hit_loss` of the charge (pass 67; 1 = all of it, the old reset) |

A hero created from a template starts `hidden: true` / `availability: "hidden"`. The playable heroes are pinned by
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

### Weapon params (pass 67: the basketball)

A weapon's `params` are free keys its behaviour reads, deep-merged under its mutations' `params` and the evolution's
`final` block (WeaponInstance.fold_params). Pass 67 adds, for a `ProjectileEmitter`:

| Key | Type | Default | What it does |
|---|---|---|---|
| `amount_mode` | `"bounces"` | absent | one ball a throw; every point of `amount` past 1 (levels, Multishot, a timed buff) is one more hop of `ricochet_any` |
| `return` | bool | `false` | the shot flies out and comes home (the boomerang: it turns at the end of its range) |
| `return_on_hit` | bool | `false` | it also turns home when its pierce and hops are spent, or nobody is within reach: every throw comes back |
| `return_pierce` | int | `80` | how many creatures the way home may hit (80 = all of them, the Tumbleweed's Boomerang; the basketball's 2) |
| `return_damage_mult`, `back_speed_mult` | number | `1` | the way home's damage and speed, times the throw's |
| `ricochet_any` | `{count, frac, reach}` | absent | the shot hops to the nearest creature it has not struck: `count` hops at `frac` of its first damage, looking `reach` m (pass 67; default 7) |
| `catch` | `{refund, heat_per, heat_max, heat_keep, slam}` | absent | the ball is caught in his hand: `refund` of the cooldown back; a trip that hit a creature adds one Heat, each `heat_per` more damage up to `heat_max` stacks, all of it lost on a hit that reaches his health unless `heat_keep`; `slam {at_heat, radius, damage_frac, knockback}`: at that Heat every catch hits everything within `radius` m for `damage_frac` of the damage |
| `free_throw` | `{every, damage_mult}` | absent | (Free Throw, a hero mutation) every evaded hit throws a free ball at once, at most one every `every` s |

The sound ids under `sfx` gain `catch` (played on the catch) beside `fire` and `hit`.

### Perk specials and pickup effects (pass 67)

A perk's `special` names the mechanism the game runs and its `params` tune it (Run.perk_param). Free strings, no
vocabulary:

| `special` | Params | What it does |
|---|---|---|
| `timeout` | `every`, `first`, `side`, `pickup` | Fadeaway's Timeout: drops the pickup `pickup` `side` m to his left or right (the side with fewer creatures), first after `first` s, then `every` s after the last one was taken or faded; one lies at a time |
| `periodic_buff` | `every`, `first`, `seconds`, `buff` (effects) | after `first` s, then every `every` s: the `buff` effects (target `player`) for `seconds`, a timed buff under the perk's name (Fadeaway's Buzzer Beater) |
| `overdrive` | `every`, `step`, `max` | Buck's Overdrive: every `every` s spent at full momentum is one more gear of `step` attack damage, up to `max`; a hit that lands drops every gear |
| `ram` | `thorns_mult`, `flat`, `per_level`, `shove`, `from` | Buck's Ram: at a charge of `from` (0.99) or more, a creature that touches him is shoved by `shove` (times its knockback share) and takes `flat` + `per_level` x his level + `thorns_mult` x his thorns instead of biting him; never a boss or a charging creature (pass 67 added `per_level` and `from`; absent: 0 and 0.99) |

A pickup's `effect` is a free string too, matched by Game.apply_pickup: `heal`, `gold`, `buff`, `shield`, `vacuum`, `nuke`,
`pollen` and (pass 67) `leap`: he leaps clear towards the emptiest of `directions` ways (`push` m/s along the sand,
`lift` m/s up), untouchable for `invuln` s, and the creatures within `slow_radius` m of where he stood move `slow` slower
for `slow_seconds` s. `quiet` keeps a pickup's fanfare down (a heal: no "+N HP" toast; the Timeout: dropped without the
chest's sound). A pickup drops from kills only when the map's `pickups.roster` names it; the Timeout is in no roster
(its `weight: 0` is the cake slice's and the coin bag's convention), so only the perk or the arena's DROPS tab puts one
down.

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

## Candidate jobs (pass 68)

`hero_badge` {character, prompt (the action), ref, variant, seeds, first_seed, head_width, top_pad}, `hero_title`
{character, pose, holds, camera, ref, extra_ref, extra_words, variant, seeds, first_seed} and `icon_cands` {subject, ref,
screen, file, style} take the Model settings too. Every empty field is filled at Queue from the target
(`jobs.candidate_defaults`, shown before Queue by `GET /api/jobs/defaults?kind=<job kind>&target=<kind>/<id>[/<code>]` ->
{fields, sources, ref_url, ref_exists}; `spec.defaults_from` says where each came from). `ref` is the identity picture (the
look's own front still by default; any picture path); `variant` names the look the pick lands in ("" = the hero's or
creature's own, the base code too). icon_cands is refused for a hero (its icon is the round badge). A candidate job waits
in the queue while a look job of the same target is still painting its reference (`held` in the job record).

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
