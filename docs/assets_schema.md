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
| `.recipe.ctl_drivers` | entry (heroes) | folder, or `{view: folder}` | absent | **lane PUPPET, pass 71**: the views walked on a depth guide (`tools/dl/drivers/<folder>/<view>/ctl_NN.png`) by Wan 2.2 Fun Control instead of Wan Animate on `pose_drivers` (gen_art `ctl_driver_of`); its clips are cached as `<id>_<code part>_ctl_run_<view>`. A puppet look's job writes it after the guides: the depth guides (`<hero>_puppet_<clip>[_N]_depth`) for its depth views (fd, side, bd, back by default) |
| `.recipe.run_fit` | entry (heroes) | path, or `{view: ratio}` | absent | **pass 71**: each view's walk sized by its MEDIAN frame at this ratio of the standing figure (gen_art `run_fit_of`, `clip_scale`; clamped 0.6..1.4) instead of its tallest frame at the standing height; a path names a `silhouette.json` (or a guide folder holding one: the 3D puppet's own run/idle screen height per view, through the guides' 25-degree cameras). `run_scale` still multiplies on top. A puppet look's job writes its guides' silhouette here unless *run size from the puppet* is off |
| `.recipe.fringe_remap` | entry (heroes) | `true` or `{min_sat, sat}` | absent | **pass 71**: the clips' hues the view's own painting does not have (gen_art's 24 hue bins: own = 0.3 % of the figure, or a neighbour) moved to the painting's nearest own hue, saturation x `sat` (0.85), value and alpha kept, only pixels saturated past `min_sat` (0.2): the rainbow fringes Wan leaves on sleeves. Off unless named |
| `.recipe.method` `hero_puppet` | entry (heroes) | | | **pass 71**: the Puppet method (`tools/puppet.py`): the look's walks guided by the hero's own rigged 3D puppet; its recipe starts as the source look's (stills, seeds, words; never its `run_scale` or drivers), then the job writes `pose_drivers`, `ctl_drivers` and `run_fit` from the guides |
| `.recipe.puppet` | entry (heroes) | object | absent | **pass 71 follow-up**: a puppet look's settings as it ran (`jobs.PUPPET_SETTINGS`): `run_fit` (Size from the 3D model, default true), `frame` (`soles` \| `ankles`, default soles), `fringe` (Clean colour fringes, default true), `face` (`nose` \| `head`, Keep the face angle, default nose), `depth_views` (list or comma text, default fd, side, bd, back), `source`, `stills` (`reuse` \| `repaint`), `refs`, `painter`, `steps`, `turbo`, `seeds`, `words`, `screen`, `tries`, `faces`, `reuse` (`auto` \| `fresh` \| `blend` \| `fbx`), `fbx`, `clip`, `idle`. Written by the job at Queue and Edit, shown in Recipe (typed); a re-queue runs what it holds. Tool-only: the game never reads it |

**Codes.** `PREFIX-SUFFIX`. PREFIX = the most common prefix of the existing `variants` keys, else `variant_base`'s, else
the initials of the id's words (`dune_scorpion` → `DS`; a one-word id takes its first three letters, `goblin` → `GOB`).
SUFFIX = the first free of A..Z, then AA..; a suffix whose `<id>_sprite_<suffix lower>.png` or `<id>_icon_<...>.png`
exists is skipped; stub entries count as used. The server allocates them (`GET /api/content/<kind>/<id>/next_codes?n=`).
Derived names: strip `<id>_sprite_<suffix lower>.png`, clip cache key part `code.lower().replace("-", "")`, marker
`<id>_<suffix>_ai.json`.

**The Puppet method's job settings** (pass 71, not content: the `look` job's spec field `puppet`, `jobs.puppet_spec`): `source` (the look whose stills are edited; default the one he is played in), `stills` (`reuse` | `repaint`), `refs` `{front, side, back}` (`paint` | `still:<key>` | a picture's repo path | `none` for side/back), `painter` (`klein` | `dev`), `steps`, `turbo`, `seeds`, `seed`, `words` `{view: text}`, `screen`, `tries`, `faces`, `reuse` (`auto` | `fresh` | `blend` | `fbx`), `fbx`, `clip` (default `running.fbx`), `idle` (default procedural), `frame` (`soles` | `ankles`), `depth_views` (default fd, side, bd, back), `run_fit` (default true), `fringe` (default false); the card sets `picks` and the one-shot `reset_from` / `reroll`. The puppet's files live under `tools/dl/puppet/<hero>/` (`stages.json`, `apose_*.png`, `shape.glb`, `<hero>_puppet.blend` with mesh `<Name>` and armature `<Name>_Rig`, `<hero>_puppet.glb` with the clips `run` and `idle`), its guides under `tools/dl/drivers/<hero>_puppet_<clip>[_N]` (`meta.json` says `frame`, `clip`, `glb`; `silhouette.json`) and `<...>_depth`.

**Removing a look** deletes the entry; its PNGs and their `.import` files move to
`tools/level_editor/backups/deleted/<id>/<stamp>/`. Refused for the look in play and for a code a map row names.

## Heroes (`content/characters/<id>/<id>.json`)

**`appearance`** (heroes and creatures, top level, optional, pass 68): the character in words without a pose, used as the
*Character* of badge, title cut-out and icon candidates; when absent the `art_prompt` is used with its trailing pose clause
cut (`jobs.appearance_of`).

| Key | Type | Default | What it does |
|---|---|---|---|
| `hidden` | bool | `false` | out of the title and the Collection; **kept in step** with `availability` (pass 69: `hidden = availability == "hidden"`; the game reads `hidden = availability == "hidden" or (hidden and availability != "purchase")`, so a hero to buy is never hidden) |
| `availability` | `available` \| `purchase` \| `hidden` | derived from `hidden` | **pass 69, wired** (Registry.hero_state owned / buyable / locked / hidden): `available` = free, owned from the start (or, with an unlock quest, owned the moment it is done); `purchase` = on the title and in the hero drawer, locked (a black silhouette, "Unknown", the requirement over his plaque) until his unlock quest is done (none = on sale at once), then BUY for `price`; `hidden` = out of play (his perks and hero mutation too) |
| `price` | int ≥ 0 | `0` | what BUY costs (Save.buy_hero; the gold sink "hero") |
| `currency_type` | `gold` | `gold` | only gold can be spent |
| `order` | int | `0` | the title carousel's and the hero drawer's order inside each group (owned, on sale, locked) |
| `side_hint`, `pose_hint` | text | absent | *tool-only* (gen_art): the side view's words (Jeżyk's ask for level shoulders) and the standing pose words of every still |
| *unlock quest* | `content/quests/unlock_<hero>/` | none | **pass 69**: his requirement, a quest whose `unlocks` is `{"type": "character", "id": "<hero>"}` (Registry.quest_for), the shape of the items' unlock quests; the Heroes tab's **Requirement** writes, edits and removes it (`POST /api/content/hero/<id>/availability {availability, quest}`, `quest: null` removes) |

The save keeps the heroes bought in `heroes_owned` (a list of ids; a free hero is owned without being listed; a save from
before pass 69 has none). The developer menu's "Heroes · own every one" / "forget the bought ones" set it for tests.
| `title_pose`, `title_holds`, `title_camera` | text | absent | *tool-only*: the title cut-out's words (`gen_title_heroes.py` reads them before its own tables, then `portrait_prompt`) |
| `title_extra_ref` | `{file, words}` | absent | *tool-only*: a second reference for the cut-out (the held object) and what it is |
| `portrait_prompt` | text | absent | *tool-only*: the round badge's bust words |
| `badge` | `{still, head_width, top_pad}` | absent | *tool-only*: how the badge is cut from a still |
| `pose_drivers` | `{view: driver}` | `run` for every view | *tool-only*: the OpenPose driver per view (`front back side bd fd`) |
| `still_keys` | `{view: key}` | absent | *tool-only*: cached stills to reuse per view |
| `run_fps` | int | 36 | *tool-only*: the run cycle's rate written into `fps.run` |
| `momentum` | `{ramp_seconds, speed_bonus, might_bonus, evade_bonus, hit_loss}` | absent | Buck's charge (`specials: ["momentum"]`): full after `ramp_seconds` without a hit; at full, `speed_bonus` more move speed, `might_bonus` more damage and (pass 67) `evade_bonus` evade chance; a hit that reaches his health takes `hit_loss` of the charge (pass 67; 1 = all of it, the old reset) |

A hero created from a template starts `hidden: true` / `availability: "hidden"`. A hero on the title (free or to buy)
must be whole (pass66_shape_test): at least one perk and exactly one hero mutation on his favourite weapon; the Heroes
tab warns otherwise.

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

### Weapon params (pass 69: the Salt, the Frisbee, the ball, Trigger Happy)

The Items tab shows these as typed fields (`AFIELDS.PARAM_GROUPS`); an empty box shows what applies and where from. Keys
are under `params` (a mutation's merged over its weapon's, an evolution's `final` last).

| Key | Type | Default (the code's) | What it does |
|---|---|---|---|
| `salt.radius` | m | `1.4` | a patch's radius at area 1 (× area × `salt.area_mult`) |
| `salt.tick` | s | `0.5` | seconds between damage ticks; a creature in any patch takes one hit a tick |
| `salt.spacing` | m | `1.2` | metres between the patches of one pour, back along the hero's way |
| `salt.max_patches` | int | `40` | most patches at once; one more sends the oldest into its fade |
| `salt.color`, `salt.alpha`, `salt.contents` | #RRGGBB, 0..1, #RRGGBB | `#FFFFFF`, `0.5` (the Salt sets 0.6), `#F4F4F0` | the patches' colour and opacity; the salt inside the floating shaker (Sea Salt pink #F4A3C4, Hiwa Kai black) |
| `salt.duration_mult`, `salt.damage_mult`, `salt.area_mult` | number | `1` | × a patch's seconds (Sea Salt 1.75, Hiwa Kai 2), × a tick's damage (Sea Salt 0.95), × the radius (Salt Spill 1.6, Hiwa Kai 1.8) |
| `salt.luck_mult` | number | `1` | Thing About Luck: a creature killed in a patch rolls the power-up drop at this factor (3; Hiwa Kai 4) |
| `salt.momentum_on_enter` | bool | `false` | Salt Flats (Jeżyk): walking INTO a patch from outside puts his momentum at full |
| `salt.crystals` `{count, color}`, `salt.crunch.mult`, `salt.slow` | int + colour, number, 0..0.95 | none, none, `0` | Hiwa Kai: hard crystals on every patch (7), one extra hit of mult × a tick for a creature walking in (2), 30% slower inside |
| `shaker.distance`, `shaker.height`, `shaker.orbit_speed`, `shaker.bob` | m, m, rad/s, m | `1.2`, `1.25`, `0.55`, `0.08` | the floating 3D shaker round the hero |
| `bend_deg`, `bend_per_extra`, `fan_deg` | deg | `25`, `12`, `16` | the Frisbee's arc off the aim line (a random side each disc), more per extra disc, the gap between a volley's aim lines |
| `falloff.step`, `falloff.floor` | 0..1 | `0.85`, `0.25` | each creature a disc cuts after the first takes this share of the one before, never under the floor |
| `hit_radius`, `height`, `glide_seconds` | m, m, s | `0.55`, `1.0`, `0.45` | how wide it cuts, how high it flies, how long it glides down after its range |
| `disc.look` | `plain` \| `razors` \| `saucer` | `plain` | the disc drawn (built in code) |
| `disc.size`, `disc.size_mult`, `disc.albedo`, `disc.emission`, `disc.energy`, `disc.spin`, `disc.trail`, `disc.haze` | m, number, colours, number, rad/s, bool, bool | `0.36`, `1`, `#B8FF2A`, `#7CFF00`, `0.8`, `16`, `true`, `false` | its size (Carry × 1.5), colours, glow, spin, the trail, the Flying Saucer's poison haze |
| `carry.chance`, `carry.drop_hit` | 0..1, number | none, `0` | Carry: the first creature hit rides the disc to the end of its flight (never a boss or an Elite); the ride ends with a hit of drop_hit × the damage |
| `proc_mult` | number | `1` | Trick Shot: this weapon's life steal, crit, Cold Snap, Vulture and stun chances × this (1.25; the saucer 1.5) |
| `stun.chance`, `stun.seconds` | 0..1, s | none | a stun roll on every hit that does not kill |
| `loop.radius`, `loop.from`, `loop.to` | m, 0..1, 0..1 | none, `0.3`, `0.7` | the Flying Saucer: once a flight, one full circle somewhere between from and to of its range |
| `launch.chance`, `launch.height`, `launch.air_time`, `launch.fall_damage_frac`, `launch.sfx` | 0..1, m, s, number, sound id | none, `3.5`, `0.9`, `1`, `w_grav_land` | Alley-Oop: a ball hit may throw the creature straight up (no move or attack up there); it takes the hit × fall_damage_frac on landing; bosses and Elites take it at once (Slam Dunk 0.25 and 1.5) |
| `heat_look` `{color, hot, glow_min, glow_max, seam_glow_max, pulse_hz, pulse, surfaces, trail_from, trail_size, trail_life, flame_from, flame_size, halo, halo_from, halo_alpha}` | colours, numbers, `all` \| `seams` \| `body` | see keys_BB (`#FF6A1A`, `#FFC060`, 0, 0.5, 1.6, 3, 0.35, all, 0.1, 1, 0.35, 0.4, 1, 1.8, 0.9, 0.22) | the ball's Heat shown on the ball (no HUD gauge): glow, trail, flames, the beating halo at the top |
| `tint.body`, `tint.vertex_colors`, `tint.seams` `{color, emission, energy, below}` | colour, bool, object | none, the model's, `#0A0A0A` / none / `1` / `0.25` | a ball in its own colour with its seams kept (Alley-Oop dark blue, Slam Dunk black with ember seams) |
| `fire_without_target` | bool | `false` | May's Trigger Happy: the gun fires on its clock with nobody in range, along her facing |
| `stream` | bool | `false` | a burst spread evenly over the whole cooldown: the gun never pauses |

`behavior` gained `SaltShaker` (the Salt: damage a tick, cooldown between pours, amount = patches a pour, area, duration
a patch lies) and `Frisbee` (damage, cooldown, amount = discs a volley, speed, range, knockback; `pierce: 999` is only a
marker).

### Perks (pass 69: a form of their own)

`content/perks/<id>/<id>.json`, edited from the Heroes tab (His own → Edit, + New perk…): `id`, `name`, `flavour`,
`rarity`, `weight`, `hidden`, `hero` (the only hero offered it; required), `text` (the card), `effects` (player stats),
`special` and `params`. `special` names a mechanism (`vocab.PERK_SPECIALS`, checked against the code's defaults):
`decoy` and `periodic_buff` work on any perk; every other one is also checked by its perk's own id in the game
(`Run.has_perk("<id>")`), so a copy under a new id keeps its numbers but never fires.

| `special` | Params (the code's defaults) | What it does |
|---|---|---|
| `decoy` | `every` 30, `first` 6, `throw_min` 4, `throw_max` 7, `flight` 0.6, `radius` 6.5, `duration` 2 | May's Inflatable May: every `every` s she throws an inflatable double of herself; where it lands, every creature within `radius` m (Elites too, never a boss) goes for the doll for `duration` s with a pink "?" over it, then it pops |
| `periodic_buff` | `every` 30, `first` (= every), `seconds` 5, `buff` (effects) | Buzzer Beater: the buff effects for `seconds` every `every` s |
| `timeout`, `overdrive`, `ram`, `high_noon`, ... | see `vocab.PERK_SPECIALS` | each hero's own mechanism (by id) |

### Player stats (pass 69: the new passive items)

| Stat | Kind | What it does |
|---|---|---|
| `counter_damage`, `counter_haste`, `counter_speed`, `counter_seconds` | pct, pct, pct, sec | Counterpunch: after an evade the next attack × (1 + counter_damage), weapon and move speed up for counter_seconds |
| `heavyweight` | pct | attack damage per whole 10 max HP |
| `overheal` | pct | Snake Oil: heals that are not regen go past full up to this share of max HP (pink on the HP bar) |
| `heal_pulse` | num | Hot Springs: every heal hurts creatures within 3 m for this + 2 per HP healed (40 at most, one pulse per 0.5 s) |
| `last_stand` | pct | a hit leaving him under 30% HP slows time to half for 2 s and adds this attack damage (a hidden 20 s cooldown) |
| `xp_pull_radius` | m | the Magnet: every few seconds at random every EXP gem within this radius flies to him (8.5 m at most) |
| `xp_pull_rate` | **word** | the Magnet: the pulls' wait divided by 1 + this; cards say "pulls more often", never a number; left out of totals |

The `magnet` stat (pickup radius) stays for the Prospector's Eye and the hero specials; the Magnet item no longer gives it.

### Special enemies (pass 69, lane EN)

A creature's `variance.special` gained `glow` (0..1, the emissive rim in its colour; default 0.6) and every creature's
numbers moved (size 1.25, hp 10, damage 2, special_chance a third of before); the map's `timeline_data.special_defaults`
`{size, hp, damage, xp, tint_strength, glow}` fills any box a creature leaves empty (own > map > the game's), and a swarm
event's `special: true` brings every creature as its special for sure (docs/waves_schema.md). The Enemies tab's *Special*
section and Settings → *Coloured specials* edit them.

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

## Pass 70 (lane LE)

| Key / route | Meaning |
|---|---|
| `POST /api/content/<kind>/<id>/look/<base> {op: "remove", new_base}` | removes the base look (`variant_base`): `new_base` (a look with its own strip on disk) becomes the base; without it a 409 with `choices` and `suggest` (the look in play first); the base in a bulk remove is refused; the look in play still cannot be removed |
| top-level `sprite`, `icon`, `anims`, `strip_cols`, `fps`, `frame_px` (hero), `head` after a base removal | the new base's own values (`server.BASE_ART_KEYS`), no file renamed; the new base keeps its entry (`recipe`, `title`, `icon_picked`) and a landing on it is mirrored to the top level (`merge_look`, `set_look_files`' icon) |
| `variants[CODE].anims` / `fps` / `head` / `frame_px` written by a base removal | what that look inherited from the old top level ("pinned"), so it plays as before |
| `tools/level_editor/backups/deleted/<id>/<stamp>/base_<CODE>.json` | `{code, entry, top, new_base}`: what the removed base was, beside its files |
| `POST /api/jobs/<job>/install {choice, options: {variant}}` | installs a finished candidate job's pick into the look `variant` ("" = the asset's own, the base's files); the install job's `target.code` and `spec.variant` name it |
| `/api/heroes` records: `icon_play`, `title_play` | the badge and title cut-out of the look the hero is played in (`?v=<mtime>`; `title_play` null when none is on disk) |
| `recipe.stills`, a look job's `stills` | a slug `[A-Za-z0-9_]{0,40}` ("" = the asset's own paintings); anything else is refused by the form, the server, the recipe editor and gen_edit_stills |
| job spec `reroll {mode: "clip", view}` | one view's walk again (front, fd, side, bd, back): that clip moved to `<key>_old<stamp>`, anim_seed + 1 (creature_ctl: walk_seeds[view] + 1) |
| job kind `driver_tweak {src, name, op, scale, views, spread, level, tuck}` | a copy of the driver `src` as `name` with one change: op scale (pose_scale.py `scale`, `views`), spread (pose_spread.py `spread`), occlude (pose_occlude.py), shoulders (pose_shoulders.py `level`, `views`, `tuck`) |
| env `ASSET_JOB_ATTEMPT` | the job's attempt, set by tools/asset_job.py; the candidate tools without `--attempt` read it (tools/cand_seeds.job_attempt) |
| candidate seeds | `tools/cand_seeds.seeds(base, n, tag)`: base + job_salt(job id) + k × 1,000,003 (a hand run: no job move) |

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

## Pass 73: new keys

Every key the lanes added, as each lane wrote it. The map's `target_priority` and `spawn_rise` are in docs/waves_schema.md too.

### Target priority, the sniper, flee on hit, the rocket's slow

All of them are in the Level Editor already (this lane added the rows; selftest_P's block count re-pinned 10 -> 12).

#### Creature JSON (`content/enemies/<id>/<id>.json`, EnemyDef, JsonContent._enemy)

| Key | Type | Default | What it does |
|---|---|---|---|
| `brain: "sniper"` | brain | | the Saiga Sniper's brain (EnemyManager._sniper_*): placed `stand_off` away, runs inside `flee_range`, walks in past `follow`, between them freezes to aim; a new case in vocab.BRAINS / BRAIN_BLOCKS (`sniper: ["sniper"]`) |
| `sniper` | block | `{}` | the sniper brain's numbers (below); a row's `stats` may deep-merge over it (EnemyDef.with_overrides) |
| `sniper.stand_off` | m | 26 | where it is placed when it spawns (never nearer the hero), inside the wall |
| `sniper.flee_range` | m | 14 | it runs straight away from the hero while he is nearer (never while aiming) |
| `sniper.follow` | m | stand_off + 12 | it walks back in while he is farther |
| `sniper.first` | s | 2.5 | from its arrival to its first aim |
| `sniper.aim` | s | 2.0 | the lines gather and follow the hero this long (× 1/pace) |
| `sniper.lock` | s | 1.0 | the locked line holds still this long before the shot (× 1/pace) |
| `sniper.interval` | s | 9.0 | from one shot to the next, the aim and the hold included |
| `sniper.interval_jitter` | s | 1.5 | the interval varies this much either way |
| `sniper.recover` | s | 2.5 | after a spoiled aim (a hit, a stun, a freeze, a launch) the next waits at least this long |
| `sniper.cone_deg` | ° | 44 | the lines start on the two sides of a cone this wide round his aim |
| `sniper.lines` | int | 14 | how many lines gather over the aim |
| `sniper.beam` | object | | `{length 60, width 0.5, seconds 0.15, damage_from "", damage_mult 0.7, damage 15.4, knockback 5, creature_frac 0.05, creature_max 40, push 3, sparks 1.5}`: the beam's reach and width, how long it shows; the hero's damage = damage_mult × the missile damage of the creature `damage_from` names (else `damage`) × the sniper's stage, level and hostile factors; his knock (m/s); what each creature on the line takes (its max HP share, capped) and how far it is pushed off (m); how long the sparks shimmer (s) |
| `sniper.muzzle` | object | `{}` | `{up, side, forward}` in metres at the def's size: where the lines and the beam leave (the rifle's end as painted: `side` towards the barrel, screen-right in the painting); empty = 0.65 of its size straight up |
| `flee_on_hit` | block | `{}` | any creature: `{seconds 1.0, speed_mult 1.8, interrupts true}`: a hit that takes health (never a poison or fire tick) sends it straight away from the hero at speed × speed_mult for `seconds`; `interrupts` drops a wind-up, an aim or a scripted attack under way. Never a boss. vocab BLOCKS `flee_on_hit`; the editor's READ_BY `any` |
| `attack_views` | `""` \| `"front_back"` | `""` | `front_back`: the `attack` strip's first half is painted from the front, its second half from the back; the game shows the half the creature's facing shows (EnemyManager._attack_view_frame). The Saiga Sniper's aiming pose |
| `sfx.aim`, `sfx.lock`, `sfx.shot` | sound id | `""` | the sniper brain's three sounds (en_sniper_aim, en_sniper_lock, en_sniper_shot); vocab SFX_HOOKS enemy += aim, lock, shot; the form shows the rows for the sniper brain only |
| `aim_hint`, `aim_back_hint` | text | | *tool-only* (lane ART): the aiming pose's words, front and back |
| `artillery.missile.hit_slow` | object | absent | `{mult 0.5, recover 3, shake 0.35}`: every hit on the shooter drops its rockets under guidance to `mult` of their speed, back to full in a straight line over `recover` s of the shot clock; `shake` s of jitter. Absent = never slowed. The Vulture Raider names it. vocab SUBBLOCKS `artillery.missile.hit_slow` |

#### Map timeline (`content/maps/<id>/<id>.json` `timeline_data`, WaveTimeline, JsonContent.timeline_from_dict)

| Key | Type | Default | What it does |
|---|---|---|---|
| `target_priority` | block | `{}` (= the defaults) | the weapons' target priority (EnemyManager.priority_target), handed on by WaveDirector._apply_mults |
| `target_priority.enabled` | bool | true | every weapon that picks its target takes a special, an Elite or the boss within reach first (only the first shot of a volley spread over different creatures) |
| `target_priority.reach` | m | 10 | how near the hero (a turret: itself) it must be; never past the weapon's own range |
| `specials.pool[] {"enemy": "saiga_sniper"}` | row | | Red Canyon's new row, beside the Rocketeer's |

The Settings tab shows `target_priority.*` in a new **Targeting** card (fields.js SCALAR_GROUPS += 'Targeting');
the Specials card's words name the Sniper.

### Volley rain, burrow, summons, spawn rise

#### Custom boss attack (`content/boss_attacks/<id>/<id>.json`, BossAttackDef; the Boss attacks tab)

| group.key | type | default | kinds | meaning |
|---|---|---|---|---|
| landing.mode | "stagger" \| "volley" | stagger | rain | stagger: one after another from the boss's back over timing.stagger (pass 72); volley: all in one spew from its mouth, landing within timing.stagger of each other, the nearest first |
| telegraph.all_at_once | bool | false | rain | every landing circle lights together telegraph.seconds before the spikes leave (the wind-up made at least that long) and stays lit until its spike lands; off: each circle telegraph.seconds before its own landing |
| spew.crouch | s | 0.35 | rain (volley) | the boss crouches through the last this many seconds of its wind-up (× 1/pace) |
| spew.squash | 0.3..1 | 0.82 | rain (volley) | the crouch's squash (shorter, wider) |
| spew.stretch | 1..2 | 1.25 | rain (volley) | the spew's stretch (taller, narrower), easing back to 1 |
| spew.mouth | share of its height | 0.62 | rain (volley) | where the shots leave from, up its painting |
| spew.burst | s | 0.12 | rain (volley) | every shot leaves within this long of the spew |

BossAttackDef: `LANDING_MODES`, `is_volley()`, `lit_at_once()`, `windup_seconds()` (max(windup, telegraph.seconds) for a
rain lit all at once; runner_entry's windup), static `volley_times(pts, flight, stagger, burst, rng) -> [departs, lands]`.
JsonContent reads the `spew` group.

#### A creature's `burrow` attack entry (`boss.attacks[]` with `"name": "burrow"`; the Enemies tab's attack card)

| key | type | default (absent) | meaning |
|---|---|---|---|
| sink | s | 0 | sinks out of sight where it stands over this long (× 1/pace), dust ring + sand spray + a poof as it closes; 0 = gone at once (pass 60) |
| rise | s | 0.4 (RISE_TIME) | comes up out of the sand over this long at the eruption |
| predict | s | 0 | > 0: no ring and no mound before; `warn` s before the eruption the spot is fixed where the hero will be (his place + his flat velocity × this, on the walkable map) and ringed; 0: the ring at the hero (telegraph ring_at_hero) |
| warn | s | 0.4 | with predict: the warning ring's time before the eruption (× 1/pace) |
| mound | bool | true | the sand swells at the ring through the wind-up (never with predict) |
| throw_up | m | 0 | a hit that lands throws the hero this high on his airborne arc (Player.trampoline_launch) instead of the knockback shove |
| throw_out | m | 0 | how far that throw carries him, away from the middle |
| throw_air | s | empty | his time in the air; empty = sqrt(8 × throw_up / 24) |
| throw_control | 0..1 | 0.15 | the stick's share of his walk added to the arc |
| creature_up | m | 0 | every creature within the radius (not the burrower) thrown this high (launch) |
| creature_out | m | 0 | ... and this far away from the middle (× its share of a shove: 1 − knockback_resist) |
| creature_damage | share | 0 | of its max HP, taken as it lands (at once for one that cannot go up) |

vocab.py ATTACKS["burrow"]["keys"] and assets_fields.js ATTACKS.burrow.keys carry them; a burrow with predict > 0 is not
warned for lacking the ring-at-hero telegraph.

#### Map `timeline_data.spawn_rise` (WaveTimeline.spawn_rise; Settings → Spawning)

| key | type | default (absent) | meaning |
|---|---|---|---|
| seconds | s | 0.45 | every spawn rises out of the sand over this long (× 1/pace); 0 = off |
| big_seconds | s | 0.9 | the same for an Elite or a boss by its kind |
| targetable | 0..1 | 0.7 | the share of the way up from which a weapon may choose it as its target (area damage hits it all along) |
| dust | × | 1.0 | the dust puff's size × its size (0 = none; only on the screen) |

WaveTimeline: `SPAWN_RISE_DEFAULTS`, `spawn_rise_value(key)`; JsonContent reads the block as it is.

#### Game API (EnemyManager, for other lanes and tools)

`targetable(i)` (the choosers' rule), `set_spawn_rise(seconds, big_seconds, targetable, dust)`, `ground_clip(i)`,
`predict_spot(ppos, ahead)`, `custom_mouth(i, cdef)`, `rise_v[]` (signed rise rate), `force_plain`; counters `emerged`,
`digs`, `eruptions`, `erupt_thrown`, `erupt_hero_throws`, `last_erupt`. Shader: enemy_billboard.gdshader reads the cut
share from MODEL_MATRIX[2].y (the instance basis' z column's y). Fx: `emerge_dust(at, size, big)`, `dig_ring(at, size)`,
`dig_spray(at, size, k)`.

### The aiming pose in gen_art

All in `tools/gen_art.py` (creatures: enemies and bosses), read from a look's recipe or the creature JSON; every one is
off unless named, so no other creature's paintings or strip change. (Lane SNIPER owns `aim_hint`, `aim_back_hint` and
`attack_views` in the creature JSON; gen_art reads them.)

| key | type | default | meaning |
|---|---|---|---|
| `aim_hint` | text | "" | Words for a painted attack pose (the Saiga Sniper's aim). With it, the creature's `attack` frames are a painted pose instead of the two procedural leans: `<id>_<stills>_attack_front`, an edit of the front still ALONE with these words (identity and colours stay the walk's). |
| `aim_back_hint` | text | "" (falls back to aim_hint) | The same pose seen from behind: `<id>_<stills>_attack_back`, an edit of the BACK still alone, now in the pose (its poncho and stripes stay the back walk's). Painted only when the creature has `attack_views: "front_back"`. |
| `attack_views` | "front_back" or absent | absent | Lane SNIPER's key: the `attack` strip holds the pose from the front (first half) and from behind (second half). gen_art packs attack 4 = [front pose, front pose with a 1 px breath, back pose, back pose with a breath]. |
| `aim_ref` | text (a picture path) | "" | Optional: a picture of the pose as a SECOND reference of the front pose (riskier: two references with different poses painted the sniper a two-muzzled rifle once). The sniper does not use it. |
| `aim_fit` | number | 1.0 | The pose's height against the standing figure's (1 when the pose stands as tall as the standing painting, as the sniper's aim does: 937 vs 935 px). |
| `aim_match` | {lo, hi, min_s} or false | {"lo": 0, "hi": 60} | The hue band (degrees) whose colours in the pose are moved to the standing painting's mean hue and saturation (match_band). A pose painted as its own edit came out ~7 degrees yellower than the walk (the sniper's poncho: front aim 31.2 -> 23.9 degrees, back aim 27.9 -> 23.0). false = off. |
| `back_ref` | text (a picture path) | "" | A picture of the creature from behind as the back still's second reference. Tried once on the sniper: the front's pose and the drawing's back mixed into a rifle with two muzzles (the vision QA passed it). Check the back after a run with it; the sniper's back was painted as candidates instead (below). |

How a pose is placed (pose_cell): fitted by its alpha height to the standing figure's height x `aim_fit`, its lower
body (the bottom 45 % of the figure: legs, a poncho's hem) centred where the standing figure's is, its soles on the
standing figure's floor line, slid back inside the cell when what it holds out would leave it (the slide is recorded
in the look's `_ai.json` as `attack_slid_px`; 0 for the sniper). So the creature does not jump or change size when it
stops to aim.

Cache keys (tools/dl/ai_raw_anime/): `<id>_<slug>_attack_front`, `<id>_<slug>_attack_back`. The Level Editor's
re-roll list (jobs.cache_keys) does not know them: to paint one again, move its PNG and JSON aside and re-queue the
look (a later pass may add them to jobs.cache_keys / expected_stages when the creature names aim_hint).

#### Painting a still as candidates through the queue (what the sniper's back, aims and dead still were)

The look methods paint one seed per still (the QA retries up to three, and it does not see guns: two of the sniper's
in-job stills had two guns). A still can be painted as candidates with an `icon_cands` job used as a candidate painter:
target the creature's look, `ref` = the picture to start from (the front still `tools/dl/ai_raw_anime/<id>_<slug>_front.png`,
the back still, or the drawing), `subject` beginning "The reference image shows this exact creature: keep its face,
..., colors and proportions exactly, and redraw it full body <pose>", `style` = gen_art's STYLE + "Full body, ... one
single rifle, no ground, no shadow", a `key` of its own and a dummy `file` (so an Install by mistake writes nothing in
use). Pick by eye, copy the PNG and its JSON into the cache under the still's key (the old one moved aside as _old),
then re-queue the look: gen_art takes the cached still. Scripts: tools/dl/p73/art/scripts/q_back.py, q_aim.py,
q_aimback.py, q_dead.py.

#### The totem pole (a structure: the queue has no structure kind)

`icon_cands` with target `{kind: "", id: "totem_pole"}`, `ref` = the style anchor (game/art/style/style_anchor.png),
`subject` = gen_props' styled() words ("Using exactly the same art style ... draw a new subject: a desert prop for a
game: <the totem>"), `style` = the scenery view words + STYLE; the pick finished like gen_props' structures by
tools/dl/p73/art/scripts/finish_totem.py (keyed, 256 cell at 0.9 on the floor line, warm 0.007 outline, mute 0.18).

### Item looks (the fortune cards)

#### Item looks (content/passives/<id>/<id>.json; every line card has them, a passive item may)

| key | type | default | meaning |
|---|---|---|---|
| `variant_base` | string | "" | the look whose icon is the top-level `icon` (or `<id>_icon.png`); the cards: `"A"` (the icon each had before the cards) |
| `variant` | string | `variant_base` | the look the game plays: its icon is the def's own `icon` everywhere (HUD, cards, pause, Collection, chest, shop, Stranger). A code without its picture on disk falls back to the base. The cards: `"B"` |
| `variants` | object | {} | code -> look entry, below. A look whose `icon` file is not on disk is left out by the game (JsonContent._passive_variants) |
| `variants[CODE].icon` | string | (base: the top-level icon) | the look's icon file beside the JSON: `<id>_icon_<letter>.png` (B-E: `_icon_b.png` .. `_icon_e.png`) |
| `variants[CODE].note` | string | "" | words for the editor and the arena ("B · tilted card (detail: the least ...)") |
| `variants[CODE].shelved` | bool | false | kept but out of the chips and of "set every card to look X"; never worn by the phone's card look |
| `variants[CODE].icon_picked` | bool | false | the icon was picked by eye from candidates (the editor's install marks it) |
| `variants[CODE].recipe` | object | none | the words it was painted from, as the icon_cands job takes them: `subject`, `style`, `screen` (green or blue). The game skips it |
| `variants[CODE].painted` | object | none | where the pick came from: `job` (the editor's job id), `pick` (`c<k>`), `seed`, `model` (klein) |

PassiveDef (game): `variants` {code: {icon: Texture2D, icon_file, note, shelved}}, `variant`, `variant_base`, `worn`
(runtime), `variant_codes(include_shelved)`, `variant_shelved(code)`, `variant_note(code)`, `look_icon(code)`,
`look_code()`, `wear_look(code)`; static `display_name_of(id, fallback)` (a text that names a card reads its name).

#### The phone's card look (Save)

| key | type | default | meaning |
|---|---|---|---|
| `card_look` (save.json) | string | "" (absent) | every card drawn in this look on this phone (the arena's ITEMS tab, row "Card look": JSON A B C D E); "" = each card's JSON `variant`. Kept past the arena's sandbox like `hero_look`. `Save.card_look()`, `Save.set_card_look(code)`, `Registry.apply_card_looks()`, `Registry.card_look_codes()` |

#### Level Editor (server.py) routes and records

- `GET /api/items`: each passive record carries `variant`, `variant_base`, `play` (the look the game plays),
  `icon_play` (`/icon/passive/<id>/<play>`), `looks` [{code, note, icon, icon_file, exists, base, default, shelved,
  recipe, painted}] (`item_look_state`).
- `GET /api/content/passive/<id>`: `looks` as above (`item_looks`).
- `POST /api/content/passive/<id>/variant {code}`: plays that look (one line, a backup, an import; refused when its icon
  is not on disk) - `write_variant_kind` takes ITEM_LOOK_KINDS ("passive").
- `POST /api/item_looks/set_all {kind: "passive", code, ids?}`: "Set every card to look X": every line card (or the ids)
  that can play the look gets `variant` = code; the rest keep theirs and are listed (`skipped` [{id, why}]); `changed`,
  `kept`, one import. `set_item_looks_all`.
- The jobs' `set_look_files` hook takes a card look's `icon` (a candidate installed into look B..E), never a `title`.
- An `icon_cands` job on target {kind: passive, id, code: B} paints `<id>_icon_b.png` candidates (the job fields
  subject / style / screen = the look's recipe).

The page (items.js): the Items tab's filter chip and heading say Cards; above the cards a "Set every card to look"
bar (a button per painted look with how many cards have it, and what plays now); a card's editor (Art) shows its looks
at 112 px and the HUD's 48 px with PLAYS, "Play this look", Show (the icon preview and "+ Icon candidates" follow the
look shown) and "painted from" (the recipe). assets_fields.js: the passive flag `line` is labelled "Card (line item)".
A Level Editor started before this pass shows a "restart the editor" note instead (its server has no looks routes).

### The Totem Pole

Structures are not editable in the Level Editor (its kinds are enemy, boss, hero, weapon, evolution, passive, mutation,
perk; the map's World group has only `structures.count` and `structures.min_spacing`), so no editor form changed. The
Totem Pole's pool is hand-edited in its JSON; `import_json.gd -- only=structures/totem_pole` writes the .tres.

#### A structure's JSON (`content/structures/<id>/<id>.json`)
| Key | Type | Default | Meaning |
|---|---|---|---|
| `effect` | string | "heal" | new value **"totem"**: the Totem Pole's menu of gifts (Game._use_totem) |
| `params.per_map` | {min int, max int, spacing float} | none | stands min..max times a run apart from the weighted draw, `spacing` m from everything (the map's `min_spacing` when absent); without it the structure is drawn by weight as before |
| `params.per_sign` | int | -1 (no cap) | at most this many arms of one sign point at structures of this kind |
| `params.spent` | string | "" | new value **"grey"**: when used, its own painting desaturated (no `_off` painting needed); "fly_away" as before |
| `params.glow` | bool | true | false: no light on the PC |
| `params.choices` | int | 3 | gifts a totem menu offers |
| `params.boons` | array | [] | the gift pool: `{id, name, animal, stat, op ("add"/"mul"), min, max, step, weight}`; `name` the spirit's word (the menu's title), `animal` "the Wolf" ("" for none), `stat` any player stat TextGen names, `min`/`max` the roll's range (negative for cooldown), `step` the snap (0 = none), `weight` how often it is drawn |

#### Code (for other lanes and tools)
- `StructureManager`: `drawn(defs)`, `placed_apart(defs)`, `per_map_range(def) -> Vector2i` ((-1, -1) = drawn),
  `place_apart(def, placed) -> int`, `own_spacing(def)`, `off_river(p)`, `river_distance(p, pts)`,
  `nearest_distance(p, placed)`, `grey_painting(def) -> Texture2D` (cached per kind); constants `PER_MAP_CANDIDATES`,
  `PER_MAP_BAND`, `PER_MAP_TRIES`, `RIVER_CLEAR`, `SPENT_GREY_*`. A painted structure's one-frame billboard no longer
  ticks its frame (`playing = false`).
- `SignField.per_sign_cap(structure) -> int`; `SHORT["totem_pole"] = "TOTEM"`.
- `core/systems/TotemBoons.gd` (class TotemBoons): `pool_of`, `offer(def, rng, n)`, `roll`, `quality`, `effect_of`,
  `text` ("+6% move speed"), `amount_text`, `stat_text`, `title`, `source` ("Totem: Le-loo").
- `Run.totem_boons` (Array of rolled gifts, cleared by `Run.start`), `Run.take_totem_boon(boon) -> String`
  (analytics event kind "totem").
- `ui/TotemScreen.gd` (class TotemScreen, a WModal): `open(offer, def)`, signal `closed(boon)`, `planks()`, `offer()`.
- `Game.Modal.TOTEM` (priority 10, with the shop and the Stranger), `Game.totem_screen`, `Game.TOTEM_SCREEN` (the
  script by path), `visible_modals()` names it "totem".
- Tools: `touch_audit.gd -- only=totem` (the in-run menu and one under a 130 px cutout); smoke_run and
  difficulty_probe take a pole's first gift when its menu opens; hell_check lists "totem_screen";
  `game/tools/_p73_STRUCT_shots.gd -- out=<dir> [only=stranger,totem,menu,map] [tag=] [inset=]`.

## Pass 75: a companion gun's kick and trick spin

In a weapon's `params.familiar` (ProjectileEmitter's companion; the Revolver and the Golden Revolver carry both):

| key | type | default | meaning |
|---|---|---|---|
| `kick` | block | absent = the old small kick | the punch on every round, on its frame, never smoothed |
| `kick.back` | m | 0.3 | slides back along the barrel |
| `kick.climb` | rad | 0.5 | the muzzle climbs |
| `kick.twist` | rad | 0.12 | twists to a side picked at random |
| `kick.pop` | share | 0.25 | swells by this much |
| `kick.hz` | Hz | 3.2 | the spring's swing: past rest the other way at half a swing |
| `kick.decay` | 1/s | 9 | how fast it settles (at rest when 1 % is left) |
| `spin` | block | absent = never | a trick spin after the last round of a pull |
| `spin.chance` | 0..1 | 0.3 | a pull's chance |
| `spin.seconds` | s | 0.5 | the twirl's length; it only starts when it ends before the next pull |
| `spin.turns` | turns | 1 | how many |
| `spin.gap` | s | 2 | never sooner after the last |
| `spin.hop` | m | 0.15 | lifts at its middle |
| `spin.axis` | "x" / "y" | "x" | about the trigger guard, or flat |

## Pass 76: new keys

Every key the lanes added, as each lane wrote it.

### Weapon-family looks

Status (2026-10-14): built and tested (game/tests/pass76_looks_test.gd 11/11, touch_audit arena_item_looks 3/3,
tools/level_editor/selftest_LOOKS76.py 28/28). Write your entries against this page; after a JSON edit run
`import_json.gd -- only=<type>/<id>` (the game reads the .tres). Questions: a line in your status file, LOOKS reads them.

#### JSON keys

On a **weapon**, an **evolution** or a **mutation** JSON (`content/weapons|evolutions|mutations/<id>/<id>.json`):

| key | type | default | meaning |
|---|---|---|---|
| `variant_base` | string | `"A"` | the code the item's top-level fields are (its name, flavour, text, icon, visual, params, noun/nouns) |
| `variants` | object `{CODE: entry}` | `{}` | the looks; CODE matches `[A-Za-z0-9_-]+` (use `A`, `B`, `C`, `D`) |
| `variant` | string | `variant_base` | **on the weapon only**: the look the whole family plays (the weapon, its mutations incl. hero mutations, its evolutions). On an evolution or a mutation it is ignored. Save.item_looks wins over it (the arena's chips). |
| `noun`, `nouns` | string | `""` | **weapon / evolution top level**: the base look's thing words for TextGen ("" = the behaviour's own: a Lobber says "grenade"/"grenades", "bottle(s) of fire" when it burns, "poison bomb(s)") |

An **entry** (every key optional; a key it leaves out is the item's top-level value):

| key | type | meaning |
|---|---|---|
| `name` | string | the display name in this look (cards, HUD, pause, Collection, results, quest texts all read it) |
| `flavour` | string | the flavour line |
| `text` | string | a mutation's card line |
| `icon` | string | a PNG in the item's folder (`<id>_icon_<letter>.png`), or a `res://` path. **Named but not on disk (not imported) = the whole entry is dropped** (the item wears its base in that look) |
| `visual` | string | a `.tscn` in the item's folder, or `res://`. Named but missing = the entry is dropped |
| `params` | object | laid over the item's top-level `params` **one level deep**: each key replaces the item's key of that name (a nested object is replaced whole, not merged). Two extras: `final` (an evolution's block) is laid one level deeper, so `{"final": {"tint": null}}` touches only `final.tint`; and a **`null` value removes** the key (`{"size_mult": null}`). Rules stay out of looks: put only drawing keys here (`model`, `models`, `model_form`, `model_colour`, `model_scale`, `model_metallic`, `model_roughness`, `fuse_tip`, `tint`, `look`, `wick_flame`, ...) |
| `noun`, `nouns` | string | the weapon's thing words in this look ("stick" / "sticks"); TextGen uses them where it said "grenade(s)" (also "N of fire" / "poison N"). An evolution with none takes its family weapon's (worn) words |
| `note` | string | a word for Garry (arena, Level Editor) |
| `shelved` | bool | out of the arena's chips and the Level Editor's play list; a phone that kept it falls back to the weapon's `variant` |
| `fresh` | bool | a look not yet approved (the Level Editor marks it) |
| `recipe`, `painted`, `icon_picked`, `icon_history` | any | the Level Editor's; the game skips them |

An entry for the base code (`"A": {"note": "the grenade"}`) is allowed: its keys overlay the top level like any other
entry (normally it carries only `note`). A member with no entry for the code the family plays wears its base.

##### Example (the grenade family, look B)

```json
// lob_grenade.json (weapon): top level stays the grenade (A)
"variant_base": "A",
"variant": "B",
"variants": {
  "A": {"note": "the grenade"},
  "B": {"name": "Dynamite Stick", "flavour": "...", "icon": "lob_grenade_icon_b.png", "noun": "stick", "nouns": "sticks",
        "note": "classic paper stick", "fresh": true,
        "params": {"models": {"stick": {"tan": "res://art/props/dynamite_b_stick_tan.glb", "red": "...", "tip": [0, 0.1, -0.3]},
                              "bundle": {"tan": "...", "red": "...", "tip": [0, 0.1, -0.3]}},
                   "model_form": "stick", "model_colour": "tan"}}
}
// new_equipment.json (mutation): "variants": {"B": {"name": "Dynamite Bundle", "text": "...", "icon": "new_equipment_icon_b.png", "params": {"model_form": "bundle"}}}
// frag.json:            "variants": {"B": {"name": "Coffin Nails", "text": "...", "icon": "frag_icon_b.png", "params": {"model_colour": "red"}}}
// golden_pineapple.json (evolution): "variants": {"B": {"name": "Boomtown", "flavour": "...", "icon": "golden_pineapple_icon_b.png",
//                       "params": {"model": "res://art/props/dynamite_b_evo.glb", "fuse_tip": [0, 0.2, -0.4], "final": {"tint": null}}}}
```
(`final.tint` is the Golden Pineapple's gold; `null` drops it in that look so the model keeps its own colours. Leave
it out if Boomtown should stay gold-tinted.)

Write `variant_base` and `variants` as top-level keys, one per line (the Level Editor edits them line by line), and
run `import_json.gd -- only=<type>/<id>` after each JSON edit (and `--import` first for new PNG/GLB).

#### Game API (GDScript)

- **WeaponDef** (weapons and evolutions) and **MutationDef**: `variants` (code -> resolved entry: only the keys the JSON
  entry has, `icon` a Texture2D + `icon_file`, `visual` a PackedScene + `visual_file`), `variant_base`; WeaponDef also
  `variant`, `noun`, `nouns`. Methods (the same names as PassiveDef's): `variant_codes(include_shelved := false)` (base
  first, then by code; [] with one look), `variant_shelved(code)`, `variant_note(code)`, `look_icon(code)`,
  `look_name(code)`, `wear_look(code) -> String` (wears entry `code` over the top level, or the base when it has none;
  returns the code worn), `look_code()` (the code worn now), `look_worn` (the family code it was last asked to wear,
  "?" never).
- **Registry**: `item_family(W) -> Array` (the weapon def, its evolutions, every mutation whose `weapon` is W or one of
  its evolutions, hero mutations and hidden ones included), `item_family_root(id) -> String` (the weapon id of any
  member: a weapon, an evolution, a mutation; "" for none), `item_look_codes(W) -> Array` (the weapon's playable
  looks, not shelved, base first; [] with one look), `played_item_look(W) -> String` (Save.item_looks[W] when playable
  and not shelved, else the weapon's `variant`, else its base; "" for a family without looks), `apply_item_looks()`
  (every family wears its played look; called at the end of Registry.scan, by Save.load_save, Save.set_item_look and
  Save.wipe; families whose look changed during a live run rebuild: params at once, the behaviour (visual, model)
  recreated by Game._sync_weapons).
- **Save**: data key `item_looks` `{W: CODE}`; `item_looks() -> Dictionary`, `item_look(W) -> String` ("" none kept),
  `set_item_look(W, code)` ("" = the JSON's again; kept past the arena's sandbox like `card_look`, applied at once).
  Writing `Save.data["item_looks"][W]` by hand then calling `Registry.apply_item_looks()` works too (MOLO's shot tool).
- **TextGen**: `weapon_nouns(def: WeaponDef) -> Array` = `[one, many]` (`["", ""]` when neither the def nor, for an
  evolution, its family weapon has any). DYN: use it for the fuse words ("The sticks blow a second after they land";
  fall back to "grenade(s)" / "bottles"...). The Lobber sentence and `amount_noun` use it already.
- **WeaponBehavior**: `look_seen` (the def's `look_worn` at setup), `look_stale() -> bool`. Game._sync_weapons recreates a
  stale behaviour (a fresh setup: `_load_visual`, `_use_model`, every node from the visual), so a Lobber needs no
  look-specific code: DYN's `refresh_model()` is still the way for a mutation that changes `model_form`/`model_colour`.

#### Arena (ITEMS tab)
A "Look · <weapon name>" row of chips for every weapon family with two or more playable looks (row node
`ItemLooks_<W>`, chips `ItemLook_<W>_<CODE>` and `ItemLook_<W>_JSON`): a tap keeps that look on this phone
(Save.set_item_look, past the sandbox) and the family wears it at once, held weapons included.

#### Level Editor
`ITEM_LOOK_KINDS = ("passive", "weapon", "evolution", "mutation")`. A weapon look (any kind but passive) is playable when
every file its entry names (icon, visual) is on disk; an entry naming none is playable. `POST /api/content/weapon/<id>/variant
{code}` writes the weapon's `variant` (an evolution or a mutation is refused: the family plays its weapon's). The weapon
record (`/api/items`, a document) carries `family_looks`: per code {code, note, shelved, fresh, exists, default, base,
name, icon, members: [{kind, id, name, icon, own}]}; `/icon/<kind>/<id>/<code>` serves a member's look icon (its base
icon when it has no entry). The Items tab's weapon editor (Art) shows them: Play this look, Show, the note.
Every weapon / evolution / mutation record (`/api/items`) also carries `play` (the look it wears: a member follows its
weapon, its base when it lacks that look), `icon_play`, `name_play`, `looks` (per code: name, own, exists, fresh,
shelved, default...) and, on a member, `family` (its weapon's id); a member's document (`/api/content/<kind>/<id>`)
marks the look it wears as `default`. `family_looks[].members[]` = {kind, id, role (element/volume/motion/hero or
evolution), name, icon, own, hidden}. The icon guard (lane ICON) covers a weapon look's icon like a card's.

### The fuse, models by form and colour, mass mini crits

#### Content keys

On a **Lobber weapon or evolution** (`params`, top level: rules stay out of looks):

| key | type | default | meaning |
|---|---|---|---|
| `fuse` | object | none | the weapon's shots carry a fuse (lob_grenade, golden_pineapple). Without it a shot blows as it lands, as before |
| `fuse.seconds` | float s | 1.0 | a shot that lands and is not caught by Sticky lies where it landed this long, then blows |
| `fuse.out_before` | float s | 0.5 | the spark goes out this long before any blast of the shot (the ground fuse or the Sticky ride) |
| `fuse.lie` | bool | true | true: it lies on its side (a model at least 1.25x taller than wide is laid down; one long along X or Z lies as it is; a squat one sits), along its throw +-20 degrees, on the slope, still. false: it stays as it flew in, its spin stopped |
| `fuse.spark.color` | hex | "#FF9A2E" | the spark's glow and flung sparks (its core is this lightened) |
| `fuse.spark.size` | float m | 0.13 | the spark's core; its glows are 3.4x and 1.7x, its twinkle 3.8x long; a bomblet's spark 0.6x |
| `fuse.bomblet_seconds` | float s | = `seconds` | how long a bomblet (the evolution's) lies before it blows |
| `mass_mini` | object | none | the Drifter's Fire in the Hole: a blast that catches `min_hits` creatures or more mini-crits every one |
| `mass_mini.min_hits` | int | 9 | "more than 8 enemies at once" |

Drawing keys (a look's `params`, lane DYNART writes them; read by the Lobber and the spark):

| key | type | default | meaning |
|---|---|---|---|
| `models` | object `{<form>: {<colour>: "res://...glb", "tip": [x, y, z]}}` | none | the shot's model by form and colour; `tip` is the fuse tip in the model's own space (Godot, metres, before model_scale and the shot's size) |
| `model_form` | string | "stick" | which form (Dynamite Bundle's look sets "bundle") |
| `model_colour` | string | "tan" | which colour (Coffin Nails' look sets "red") |
| `model` | string | "" | the fallback model when `models[form][colour]` is missing or its file is not on disk (Boomtown's) |
| `fuse_tip` | [x, y, z] | the top of the mesh | the spark's place when the chosen model came from `model` (or a form names no tip) |

#### Game API

- `EnemyManager.damage_radius(center, r, amount, weapon_id := "", kb_force := 0.0, flags := 0)`: `flags` passed to
  damage() for every creature in the blast (HIT_MINI).
- `EnemyManager.blast_count(center, r) -> int`: the creatures a blast there would strike (alive, not dying, hidden or held).
- `ProjectileManager`: `fuse_of(w) -> Dictionary` (static), `fuse_seconds(fz, extra) -> float` (static),
  `fuse_lit(i) -> bool`, `fuse_tip(i) -> Vector3` (world), diagnostics `sparks_drawn`, `fuses_out`, `mass_minis`,
  `last_blast_caught`; per shot in `extra`: `fz` (its tip, model space; INF = mesh top), `lie_t` (seconds left lying),
  `lie_b` (the lying basis), `fz_lit`, `fz_t`.
- `Lobber`: `model_path() -> String` (the model drawn now), `refresh_model()` (re-models when the params choose another;
  refresh_marks calls it, so a mutation taken re-models), `static model_choice(params) -> {"path", "tip"}`.
- `TextGen.fuse_words(params, amount := 1) -> String`, `TextGen.mass_mini_words(params) -> String` (appended to the
  Lobber's description).

#### Level Editor
- `tools/level_editor/vocab.py` PARAMS_KEYS["Lobber"] and `assets_fields.js` PARAMS_KEYS.Lobber list `fuse`, `models`,
  `model_form`, `model_colour`, `fuse_tip`, `mass_mini` (so the Items tab knows them; selftest green).

#### Content

- `content/mutations/fire_in_the_hole/` (new): hero mutation of the Drifter on lob_grenade, rare, weight 8,
  `params.mass_mini {min_hits 9}`, text "A blast that catches nine or more creatures lands a Mini Crit on every one of
  them.", a placeholder icon (lane DYNART paints the looks' icons and its base one).
- drifter.json `favourite_weapon` "lob_grenade"; peashooter.json and fan_the_hammer.json `hidden: true`.

#### Notes for lane DYNART (from filming your B models in memory, tools/dl/p76/DYN/cap_b/)
- They fly, lie along their throw (long along Z: no lay-down; B's crate is squat and sits up), spark at your tips, go
  out 0.5 s before the blast with a wisp of smoke, and blow. A shot Sticky catches rides in the same pose.
- The tan stick reads orange in game: the Lobber's model material defaults to the gold grenade's finish
  (`model_metallic` 0.45, `model_roughness` 0.35). Paper wants `"model_metallic": 0.0, "model_roughness": 0.85` (or so)
  in the look's params.
- The evolution's bomblets are drawn with the evolution's own model at `bomblet_size` (0.5).
- Sticky's `look.blink` light sits where the spark is on a riding shot; `"look": null` in Sticky's look entry drops it.

### The wick flame and the pool flame

All are drawing keys (looks may carry them in `variants.<CODE>.params`); none changes a rule.

#### `params.wick_flame` (a lobbed weapon or evolution; read through WeaponInstance.params, so a look or a mutation may set it)
A fire bottle burns AT ITS WICK instead of dropping the old string of tongues (ProjectileManager's old branch is used
only when a shot has no wick_flame). Drawn by `core/systems/WickFlames.gd` + `core/shaders/wick_flame.gdshader` (one
MultiMesh for every flame, ember and spark in the air).

| key | type | default | meaning |
|---|---|---|---|
| `style` | string | `"torch"` | `"torch"` a steady licking flame with a soft glow and embers; `"streamer"` a continuous tapered ribbon of fire along the wick's last `tail` seconds of path (risen as it cools) under a small flame on the wick; `"cartoon"` a bold three-layer flame in a dark ink line, its tongues jumping on a stepped clock, with inked star sparks. Unknown: torch |
| `offset` | [x, y, z] | `[0, 0.25, 0]` | the wick's tip in the shot model's own space (metres, before the kind's scale; Godot axes: +Y is the bottle's neck). Turned and scaled with the shot as ProjectileManager.draw_basis draws it |
| `size` | float | `0.55` | the flame's height in metres (x the shot's size_mult); a streamer's width is half of it |
| `rate` | float | `12` | embers a second (sparks for the cartoon flame); 0 none |
| `life` | float | `0.28` | an ember's life in seconds (x 0.7..1.25) |
| `tumble` | float | `0` | turns a second end over end (about the axis across the flight); the bottle leaves the hand neck up. 0: the shot keeps the old spin about its flight line |
| `lean` | float | `0.045` | how far the flame leans back against the flight (seconds of flat speed added to the camera's up) |
| `tail` | float | `0.16` | the streamer's length in seconds of the wick's path |
| `rise` | float | `1.4` | m/s the streamer's tail rises as it ages |
| `depth` | float | torch -0.1, streamer 0, cartoon -0.12 | metres the flame is drawn towards the camera (negative: behind the wick, so the bottle stays in front of its own fire) |

Blue (WeaponInstance.blue_fire: Methanol, the Moonshine) burns each style in the blue palette.

#### `params.pool_flame` (the same weapons; read by ElementCloud for a fire pool, a Moonshine line or death pool)
The spill's flames in the look's style, stood by `WickFlames.ground_flame` in the same MultiMesh, instead of Fx's
teardrops. Without it: Fx's teardrops as before. The burning creatures (EnemyManager -> Fx.fire) are not changed.

| key | type | default | meaning |
|---|---|---|---|
| `style` | string | `"torch"` | `"torch"` (eaten away as it ages, a soft glow) or `"cartoon"` (pops up, holds, shrinks away; inked). `"streamer"` burns as torch |
| `size` | float | `1.0` | x the height the spill gives a flame (0.6 + radius x 0.45, 0.6..1.9 m, x 0.75..1.2) |
| `life` | float | `1.0` | x a flame's life (0.45..0.7 s) |

#### The Molotov family's looks (variant_base "A", `variant` "B": the family plays the torch)
| code | molotov `visual` | methanol `visual` | moonshine `visual` | wick_flame | pool_flame |
|---|---|---|---|---|---|
| A | molotov_visual.tscn (today's) | methanol_visual.tscn | moonshine_visual.tscn | none (the old string) | none (Fx) |
| B | molotov_visual_bottle.tscn | methanol_visual_bottle.tscn | moonshine_visual_jug.tscn | torch, tumble 1.0 | torch 0.78 |
| C | molotov_visual_bottle_trail.tscn | methanol_visual_bottle_trail.tscn | moonshine_visual_jug_trail.tscn | streamer (the bottle flies base first) | torch 0.78 |
| D | molotov_visual_bottle.tscn | methanol_visual_bottle.tscn | moonshine_visual_jug.tscn | cartoon, tumble 1.0 | cartoon 0.66, life 1.1 |

Models: `art/props/molotov_bottle.glb`, `molotov_bottle_blue.glb` (Methanol's), `moonshine_jug.glb`
(tools/blender_molotov.py; wick tips bottle +0.2433, jug +0.2101 on +Y; the looks stand the flame a little inside the
rag: 0.22 / 0.19, the trail visuals 0.235 / 0.2). Accelerant, Oil Slick, Sun Cocktail and Bar Fight have no entries
(they wear their base in every look; Sun Cocktail's `tint` gilds the new bottle as it did the old).

#### Code API (for tests and tools)
- `ProjectileManager.wick_flames() -> WickFlames` (made on first use), `wick_world(i) -> Vector3`,
  `warm_wick_flames(at)` (Vector3.INF stops it; builds nothing while no weapon or evolution wears wick_flame or
  pool_flame in its played look: `_wick_looks_played()`).
- `WickFlames`: `config(w)`, `style_of(cfg)`, `offset_of(cfg)`, `wick_world(pm, i, cfg)`, `tick(pm, i, w, dt)`,
  `draw(pm, dt)`, `ground_flame(at, height, life, style, blue, must=false) -> bool`, `warm(at)`; diagnostics
  `flames_drawn`, `pieces_drawn`, `wicks`, `axes`, `styles_drawn`, `ground_flames`, `ember_count()`, `ground_count()`.

### Source ids, start stats, the tracer

#### Content JSON
One new weapon param, `tracer_clear` (float metres, default 0 = beads everywhere): no tracer bead drops within that
distance of the hero on the ground plane (ProjectileManager._tracer_clear_of). The Revolver: 1.1 (its companion gun
orbits at 1.2 m and fires past the hero; the dim red beads over his coat read as blood). Mutations inherit it.

Values set on existing keys in `content/weapons/revolver/revolver.json` params:
- `tracer_color` (hex string, default none = gold): "#7A1F17". Pass 76 meaning on a WEAPON's own params: its plain
  colour, below Silver Bullet (`silver`) and an element (fire, poison); a MUTATION's `tracer_color` still comes first.
  The beads draw lighter than the hex says (a dark hex reads mid-tone on the sand).
- `tracer_alpha` (float, default 0.9): 0.85.
- `tracer_size` (float, default 0.9): 1.35.

#### Code (for the lead's notes; nothing for the Level Editor)
- `StatSheet` entries carry `"sid"` beside `"source"`: the source's stable id (`hero:<id>`, `trait:<id>`,
  `talent:<id>:<form>`, `passive:<id>`, `favourite:<id>`, `perk:<id>`, `mutation:<id>`, `buff:<id>`, `totem:<id>`,
  `stranger`, `momentum:<hero>`; running bonuses take their item's id). `add_effect(e, source, sid = "")`,
  `add_effects(list, source, sid = "")`: an empty sid is the source's words. `StatSheet.aims_at_weapons(e)`.
- `Run.start_stats` (stat -> value), `Run.start_stats_hero`, `Run.start_stat(stat, default)`.
- `TextGen.PLAYER_SHARE` (["cooldown", "duration"]), `player_kind`, `player_value`, `player_change`,
  `player_share_change`, `player_effect`.
- `core/systems/StatSources.gd` (class StatSources; preloaded by path in PauseScreen): `grid_stats`, `changed`,
  `change`, `all_multiply`, `rows` (START / RUN), `describe_source`, `at_start`, `now`.
- `QuestTracker.owned_reward(q)`.

### Icon history and the icon guard

#### Content JSON keys (tool-only: the game never reads them)
| Key | Where | Type | Default | Meaning |
|---|---|---|---|---|
| `icon_history` | a look's entry (`variants[CODE]`) | array of steps | absent | that look's icon changes, oldest first (at most 40) |
| `icon_history` | top level, next to `icon` | array of steps | absent | the BASE look's icon changes (the base's icon is the top-level `icon`); also for an item without looks |
| step `icon` | a step | string | "" | what the key said before ("" = the look had no icon of its own / the top level named none) |
| step `shown` | a step | string | | the file the look showed before |
| step `backup` | a step | string | "" | repo-relative path of the copy of that picture under tools/level_editor/backups/<id>/ |
| step `to` | a step | string | | the file it changed to |
| step `at` | a step | string | | "YYYY-MM-DD HH:MM:SS" |
| step `why` | a step | string | "" | "install c2 of #3d3c", "use backup/<file>", "use folder/<file>" |
| step `picked` | a look's step | bool | | the look's `icon_picked` before |
| step `entry_icon` | a base step | string | | the base entry's own `icon` before (a base made from a look names one) |
| `icon_picked` | a look's entry | bool | absent | (pass 68 key) now written by every install and "Use for this look"; Revert icon puts back what it was |

#### Install job spec (jobs.py, set by the server's install guard)
| Key | Type | Meaning |
|---|---|---|
| `icon_file` | string | the install's own new file (never an existing one) |
| `icon_code` | string | the look it lands in ("" = the base: the top-level `icon`) |
| `why` | string | the history step's reason ("install c2 of #a432") |

#### Tool flags
- `tools/gen_badge_cands.py --pick k ... --icon-file NAME`: the badge goes to NAME (`NAME_2.png` when another picture
  has that name); the sidecar says the file (`entry.icon` for a look, `info.icon_file` for the base) and gets no
  `<id>_icon.png` overwrite.
- `tools/gen_icon_cands.py` JOBS entry `keep_old: true` (with `file`): the same rule for an icon pick; `info.icon_file`.
- `gen_art.free_icon_name(folder, name, data=None) -> (name, path)`.

#### Routes (server.py)
- `GET /api/content/<kind>/<id>/icons` -> `{ok, kind, id, name, base, play, looks: [look_icon_info], files: [tile]}`;
  look_icon_info `{code, base, played, play, shown, own, picked, history, exists, url, what, shared_by, revertable}`;
  tile `{ref, where (folder|backup|deleted|legacy), file, mtime, when, size, digest, url, copies: [...], used_by: [codes]}`.
- `GET /iconfile/<kind>/<id>/<ref>`: one picture (refs `folder/<f>`, `backup/<f>`, `deleted/<stamp>/<f>`, `legacy/<icons dir>/<f>`).
- `POST /api/content/<kind>/<id>/icon {op: "revert" | "use", code ("" = the base), ref (use), confirm}`; the same as look
  ops `POST /api/content/<kind>/<id>/look/<code> {op: "revert_icon" | "use_icon", ref, confirm}`.
- `POST /api/jobs/<job>/install {choice, options, confirm}`: an icon install into the look in play or the base answers
  **409** `{confirm_needed: true, kind, id, name, what (badge|icon), look, base, played, play, shared_by, verb, now
  {file, url, own}, next {file, url, label, candidate}, job, choice, error}` until `confirm: true`.

#### Hooks (server.Hooks, for jobs.py)
- `set_look_files(kind, cid, code, files, meta=None)`: `{"icon": ...}` goes through `set_look_icon` (code "" or the
  base's code = the top-level icon); `meta {why}`.
- `snapshot_icons(kind, cid)`: the asset's icons into backups/<id>/ (once per picture).
- `jobs.choice_id(src, choice)`: a candidate's label -> its id.

#### Page (looks.js, `LookGrid`)
`confirmIconChange(res) -> Promise<bool>`, `installPick(jobId, choice, options)`, `iconOp(kind, id, code, op, extra)`,
`iconPanel(kind, id, code, {onChanged})`, `bustUrl(url, v)`. jobs.js `act()` and typed_forms.js `install()` ask through
`LookGrid.confirmIconChange`; assets.js shows `LookGrid.iconPanel` in an item's icon preview and takes the top-level
`icon_history` from disk in `refreshRecord`.

## Pass 77: the run sim (game/tools/sim_run.gd)

Status: PUBLISHED EARLY for lane SIMUI (2026-10-14). Field names and meanings are fixed; if anything changes it is
marked "CHANGED" here with the date.

### Command
```
<godot> --headless --fixed-fps 60 --path <project> --script res://tools/sim_run.gd -- out=<file> hero=drifter seed=1 \
    limit=1500 board=1.5 death=end [talents=grit:000,drive:1] [fast=1] [map=red_canyon] [progress=10] [wall=2700] [res=504x1122]
```
| Arg | Type | Default | Meaning |
|---|---|---|---|
| `out` | path | (required) | The player's JSON (absolute path, or res:// / user://). Written once at the end (also on a watchdog stop), to `<out>.tmp` then renamed, so a file that exists is complete. Parent folders are made. |
| `hero` | id | `drifter` | The hero (any CharacterDef id; a hidden or unbought one plays too, as in the content dock's test launch). |
| `seed` | int | `1` | The player's seed (see Seeds). Use seed + k for player k. 0 is turned into 1 (0 means "random" inside the game). |
| `limit` | play seconds | `1500` | Stop after this many seconds of unpaused play (25:00). |
| `board` | float | `0` | The Upgrade board in ranks a talent: 0 none, 1.5 a quarter, 3 half, 6 full (difficulty_probe's `mirror`, its FORMS and rank_for). |
| `death` | `end` / `ad` / `keep` | `end` | CHANGED 2026-10-14 22:30 (the lead: gold revives leave Down!): end = the first Down! is given up (the run ends). ad = Down! answered with the ad revive once while it is offered (its button there and not locked: a chance left), then the next Down! is given up. keep = the probe's way: the hero stood up at full HP the moment he falls (no Down!), every fall counted, the run plays to `limit`. `gold` is still read, as `ad`. Phoenix Feather (an item) revives on its own in every policy. |
| `map` | id | `red_canyon` | The map. |
| `progress` | play seconds | `10` | A progress line (stdout) and the progress file every this many play seconds. |
| `wall` | seconds | `2700` | Wall-clock cap for the whole process: past it the output is written with `end_reason` `stuck:wall` and the process quits. |
| `res` | `WxH` | `504x1122` | The screen the ranged weapons see (they target only what is on screen): a 9:20 phone. |
| `grit`, `spite` | int | `0`, `1` | The board's form for those two talents (as the probe). |
| `talents` | list | (none) | ADDED 2026-10-14 22:30 (lane SIMUI's format, ACCEPTED): `<id>:<picks>,...`, picks one 0/1 digit a rank (0 the first form, 1 the second; A/B letters read too): exactly Save.data.talents[id].picks, e.g. `talents=grit:000,drive:1,nerve:11`; also `<id>:<rank>:<form>` (every rank in one form); a talent left out has rank 0; `talents=none` = an empty board. Given, it replaces `board=`. Ids: choice, drive, fortune, grit, nerve, spite, stride, study; at most 6 ranks. A bad list exits 2 with the reason on stderr. |
| `fast` | `1` / `0` | `1` | ADDED 2026-10-14 22:30; default `0` from 2026-10-15 00:15 to 01:55, `1` again since: the game's run sim mode (Run.sim_mode, the launch key `sim_fast`): nothing is drawn or played (the crowd's, the shots', the pickups' and the ground marks' drawing, Fx, sounds, the HUD and damage numbers), about 30 % less wall time a player (43 % in lane SIMUI's 10-at-once batch), and a seed replays exactly in it (every row and pick equal: seed 66 to 5:00, seed 73 to 10:00). Measured against the full game: once the rules that counted real time count the run's clock in both modes (`sim_clock`), ten pairs to 10:00 end level (level +0.2 +- 1.4, kills -40 +- 390 at 10:00, full minus fast). `fast=0` plays the whole game (for a spot check; a seed does not replay there: the sounds' gaps run on real time and each sound draws its pitch from the global dice). A fast batch and a full one are still never mixed in one comparison. |
| `profile` | `1` | off | Every progress line also prints the game's frame buckets (core/systems/Perf.gd, ms a frame). |
| `trace` | frames | 0 | A debugging aid: a line of the run's state every frame for that many frames (finding what makes a seed unrepeatable). |
| `unlocks` | `all` / `save` | `all` | ADDED 2026-10-14: `all` marks every unlock quest done in the sandboxed save (the whole content as designed is in the card pool: the snapshot's fresh user folder would otherwise offer only the base items); `save` keeps whatever the user folder's save holds. |
| `lure_r`, `lure_w`, `lure_close` | float | `60`, `2.0`, `0.3` | ADDED 2026-10-14, tuning knobs of the bot's gem sweep (balancing_SIMRUN.md); `lure_r=0` = no sweep (the probe's pure kite plus the goals). Leave them at the defaults. |

Exit code 0 when the output was written (whatever the end), 2 on bad args / no autoloads (nothing written). A headless
Godot sometimes exits 0xC0000005 at teardown AFTER the output is written: judge a player by its output file
(`meta.end_reason`), not by the exit code.

### Progress file `<out>.progress` (rewritten every `progress` play seconds, and at the end)
One JSON object: `{"t": play s, "limit": s, "clock": stage clock s, "stage": n, "level": n, "deaths": n, "hp": f,
"hp_max": f, "kills": n, "wall_s": f, "state": "boot"|"running"|"done", "end_reason": "" until done, "xp_lying": f,
"xp_lying_near": f}` (the last two, ADDED 2026-10-14: XP lying uncollected on the whole field / within 10 m).
The same as a stdout line (CHANGED 2026-10-14, more fields; read it loosely by key):
`sim: t=120 clock=120.0 stage=1 level=4 hp=96/115 deaths=0 kills=163 xp=204 lying=237 near=2 | sweep 100% | wall=31.3`
(the `|...|` part: the share of frames the legs spent kiting, sweeping, walking to a chest, back to a living boss (`boss`, ADDED 2026-10-15: the boss leash), the boss chest, the portal).
stdout is lost when Godot's console is redirected on Windows: read the file, or pass `--log-file`.

### Output JSON
Every series is an array with one entry per row, aligned with `t`. A breakdown map holds one such array per id, zero
before the id first appears. A row is one second of unpaused play from the game's own run recorder
(core/systems/RunAnalytics.gd rows, kept in memory: no analytics file is written).
```
{
  "meta": {...},
  "t": [1, 2, 3, ...],
  ...series...,
  "events": [...]
}
```
#### meta
| Key | Type | Meaning |
|---|---|---|
| `schema` | int | 1 |
| `hero`, `hero_name`, `start_weapon` | str | the hero, his name, the weapon he started with |
| `seed`, `board`, `death`, `limit`, `map`, `unlocks`, `fast` | as the args | |
| `talent_forms` | {talent: "AAB"} | ADDED: each talent's ranks as letters, the form of each rank (A the first form, B the second) |
| `view` | [w, h] | the canvas the ranged weapons' screen test uses (1080 x 2404 at the default `res`) |
| `talents` | {talent: ranks} | the Upgrade board as played |
| `map_rev` | int/str | the map's Level Editor version (the recorder's header `map_rev`) |
| `version` | str | the game version (`application/config/version`) |
| `fps` | int | the fixed frame rate (`--fixed-fps`, read off the frame deltas: the engine keeps that argument to itself; 0 = real time) |
| `res` | [w, h] | the screen size the ranged weapons saw |
| `wall_s` | float | the process's wall time at the end (boot included) |
| `boot_s` | float | wall seconds until the run started |
| `end_reason` | str | `limit` (played to `limit`), `death` (given up on Down!: death=end, or death=gold with no revive left or not enough gold), `extract` (never by the bot), `stuck:<what>` (a screen unanswered more than 10 game s: `stuck:cards`, `stuck:chest`, `stuck:portal`, ...; `stuck:wall` the wall cap; `stuck:no_game` the game never came up) |
| `end_t`, `end_clock` | float | play seconds and stage clock at the end |
| `end_stage`, `end_level`, `endless_wave` | int | at the end |
| `deaths` | int | falls (every time the hero went down, Phoenix Feather's too) |
| `revives` | {ad, phoenix, keep} | how each fall was got up from (CHANGED 22:30: `gold` became `ad`) |
| `assists` | int | times the bot was put on the portal / boss chest after failing to walk there in time (see BALANCING notes) |
| `kills`, `gold_total`, `xp_total`, `dmg_total` | number | the run's totals |
| `build_text` | str | the build at the end in one line ("Revolver 5 +3 · ... \| Brawn 2 · ... \| perk") |
| `picks` | int | level-up cards the bot took (`skips` never) |
| `rows` | int | number of rows (= length of every series) |
| `started` | str | local date-time the run started |

#### Series (one entry per row)
| Key | Type | Meaning |
|---|---|---|
| `t` | int | the play second the row closes (1, 2, ...; a run that ended between two seconds closes its part-second as the next whole second, so `t` is strictly increasing) |
| `clock` | float | the stage clock (freezes in the boss fight and the portal wait; runs on in endless) |
| `stage` | int | stage number (1, 2, 3; 4+ = endless) |
| `phase` | int | 0 normal, 1 boss fight, 2 portal wait |
| `hp`, `hp_max` | float | the hero's health and max health at the row |
| `dps` | float | damage dealt in that second, every source (weapons, perks, blasts, revive blast, Powder Keg, ...) |
| `est` | float | the build's estimated DPS (the pause screen's sum of weapon estimates) |
| `alive` | int | creatures alive |
| `cap` | int | the director's live cap |
| `press_hp` | float | crowd HP alive (sum of the current HP of every creature up, every multiplier applied) |
| `press_dmg` | float | crowd attack alive (sum of every living creature's per-hit damage, every multiplier applied) |
| `boss_hp` | float | the boss's health fraction while one lives, else 0 |
| `boss_hp_abs` | float | ADDED (SIMUI #4): the boss's current HP (every multiplier), 0 without one |
| `near3`, `near6` | int | ADDED (the lead, SIMUI #3): creatures alive within 3 m / 6 m of the hero (flat) |
| `hits` | int | ADDED (SIMUI #5): hits that reached the hero that second (evaded and shielded ones included, as the recorder counts `hits`) |
| `spawned` | int | ADDED (SIMUI #8): creatures spawned that second |
| `mult_hp`, `mult_dmg` | float | ADDED (SIMUI #9): the HP and damage multiplier of a creature spawned now: stage x the HP (damage) time curve x the hero's level's (the recorder's `mults`, carried forward); the map's constant creature_hp_mult / creature_damage_mult are not in it |
| `took_by` | {creature or attack: float[]} | ADDED (SIMUI #6): cumulative HP lost to each (the recorder's `took` summed) |
| `healed_by` | {source: float[]} | ADDED (SIMUI #7): cumulative HP healed by source (the recorder's `healed_by`; regen as the source `regen`) |
| `held_by` | {weapons, evolutions, lines, passives, perks: int[]} | ADDED (SIMUI #10): the items held at the row (the recorder's build snapshots, carried forward; evolutions apart from the weapons) |
| `alive_by` | {enemy: int[]} | creatures alive by id |
| `gold_total` | int | cumulative gold gained (every source, greed included) |
| `gold` | int | the purse (gained minus spent) |
| `gold_by` | {source: int[]} | cumulative gold gained by source (RunAnalytics.GOLD_SOURCES ids) |
| `dmg_total` | float | cumulative damage dealt |
| `dmg_by` | {source: float[]} | cumulative damage dealt by source (weapon ids, evolution ids, perk/blast ids such as `revive`, `powder_keg`) |
| `kills` | int | cumulative kills |
| `kills_by` | {enemy: int[]} | cumulative kills by creature id |
| `level` | int | hero level |
| `xp_total` | float | cumulative XP gained (after Field Notes' multiplier) |
| `took` | float | damage taken that second: HP lost to every hit, before any healing (after shield and damage reduction) (the lead's "Danger" chart) |
| `healed` | float | healing that second: heals and regen |
| `deaths` | int | cumulative falls |

#### events (list, in time order)
`{"t": play s (0.1), "clock": stage clock, "kind": ..., ...}`
| kind | extra keys |
|---|---|
| `level` | `level` (the level reached) |
| `death` | `killer` (creature id of the last hit, or what hit), `hit` (melee/ranged/boss) |
| `revive` | `via`: ad / phoenix / keep (keep = the probe-style stand-up of `death=keep`; debug if keep ever meets Down!) |
| `boss_start` | `id`, `hp` (its max HP as it came), `mult` (the DPS pegging), `dps`, `ref` |
| `boss_end` | `id` |
| `stage` | `stage` (the stage that began; 1 at the start) |
| `portal` | `stage` (the stage just cleared; the bot always continues) |
| `wave` | `wave` (an endless wave began) |
| `assist` | `what`: portal / boss_chest (the bot was put there) |
| `pick` | ADDED (SIMUI #11): the bot's level-up or mutation pick: `id`, `item_kind` (weapon / evolution / line / passive / perk / mutation), `new` (bool), `level` (the level it brings), `type` (the card's type), `tier` (its card_tier; -1 a mutation offer's random pick), `others` (the other cards' ids) |
| `end` | `reason` (= meta.end_reason) |

### Game-side keys and API (for the lead: CLAUDE.md, analytics/SCHEMA.md)
| Where | Key / member | Type | Default | Meaning |
|---|---|---|---|---|
| launch (Run.launch_override or user://debug_launch.json) | `analytics_memory` | bool | false | The run recorder keeps its header, rows and events in memory and writes nothing (RunAnalytics.memory_only): no user://analytics/runs file, no analytics/runs mirror, no latest.js or index. |
| Run (autoload) | `launch_override` | Dictionary | {} | A launch set in memory: Game._read_debug_launch takes it before the file, empties it, and leaves the file alone (parallel sim players never race on the file). The file's keys. |
| Run | `rng_seed`, `seed_dice(s)` | int | 0 | The run sim's dice: `seed_dice(s)` seeds the global randf()/randi() stream, CardPool.rng (level-up offers and chest rolls) and rng_seed (read by WaveDirector.start for its own dice); `seed_dice(0)` puts them back to random. Nothing in the game calls it. |
| CardPool | `rng` (static) | RandomNumberGenerator | null | The offers' and chests' own dice while seeded; null = the global randf() as before. |
| RunAnalytics row | `xp_total` | float (0.1) | left out while 0 | Every XP point gained so far (Run.xp_gained, after Field Notes), cumulative. NEW row key: analytics/SCHEMA.md and tools/analytics_csv.py's BASE list could add it (nothing reads it there yet). |
| RunAnalytics | `memory_only`, `xp_total` | bool, float | false, 0 | The two above on the recorder node. |
| launch | `sim_fast` | bool | false | ADDED 22:30: the run sim's fast mode for this run (Game._ready sets Run.sim_mode from it, every run). |
| Run | `sim_mode` | bool | false | The fast mode: EnemyManager / ProjectileManager / PickupManager draw nothing (their `_process`), Telegraphs ages its marks but draws none, Fx makes nothing, Audio.play plays nothing, HUD and DamageNumbers skip their frames and Game skips hud.tick and hints.tick; the rules that count real time read the run's clock (as with sim_clock, below). |
| RunAnalytics row | `near3`, `near6` | int | left out while 0 | ADDED 22:30: creatures up within 3 m / 6 m of the hero (RunAnalytics.NEAR_CLOSE, NEAR_WIDE). |
| RunAnalytics row | `hp_lost`, `hp_healed` | float | left out while 0 | ADDED 22:30: the second's HP lost (`took` summed, before healing) and HP healed (`healed` + `regen`). |
| RunAnalytics row | `boss_now` | float | absent with no boss | ADDED 22:30: the boss's current HP (`boss_hp` stays its share). |
| launch | `sim_clock` | bool | false | ADDED 2026-10-15: the runner passes it in both modes (Game._ready sets Run.sim_clock from it, every run). |
| Run | `totem_rng` | RandomNumberGenerator | null | ADDED 2026-10-15: the Totem Poles' gifts' dice in a run sim (seed_dice: hash(seed, "totems")); Game._use_totem hands it to TotemBoons.offer, which rolls its own random ones when it is null (play). |
| StructureManager | `setup` seed hook | - | - | ADDED 2026-10-15: with Run.rng_seed set (a run sim) its dice are seeded (hash(seed, "structures")) after their randomize: where the structures stand, their returns, and the barrels placed clear of their rings follow the seed (two fast runs of one seed parted at 0:05 without it). |
| behaviours | companions' bob | - | - | ADDED 2026-10-15: the familiars', the stray gun's and the salt shaker's bob reads Run.rule_seconds() (ConeWave, GravityGun, LaserBeam, MissilePod, ProjectileEmitter x2, SaltShaker, WeaponBehavior): real time in play as before; in a sim the run's clock, since the Big Mouth's beam starts at its bobbing mouth (two fast runs of one seed parted at 3:14 on its damage). |
| Run | `sim_clock`, `rule_seconds()` | bool, float | false | ADDED 2026-10-15: in a run sim (sim_clock or sim_mode) the rules that counted real time count the run's own clock (buff_clock) instead: an Orbiter's repeat hit on the same creature (its `cooldown`, Orbiter._tick: Orbit Saws, Branding Iron, Rattlesnake and their evolutions) and the sheet's rebuild throttle (Desperado, Steady Hand, Hot Streak). In play nothing changes (rule_seconds is real time). Why: a headless run goes 2.5 to 4.5 times faster than real time, so every sim before this, the difficulty probe's too, had orbiters hitting a creature 2.5 to 4.5 times less often than a phone does, and the fast mode (faster still) less often than the full game. |

### Requests from lane SIMUI (2026-10-14 22:25, round 2: Garry's notes on the Sim tab, relayed by the lead)
SIMRUN: please mark each line ACCEPTED, CHANGED (your format) or NO right here. sim_batch.py passes the args; the page
draws a chart only when its data is in the runs, so a NO costs that chart only.
Answers (SIMRUN, 2026-10-14 ~23:00): all ACCEPTED as proposed, in the per-player output under the names proposed (#1
also takes `<id>:<rank>:<form>`; #4's RunAnalytics row key is `boss_now`, the output key `boss_hp_abs`). Details in the
tables above. Implemented in sim_run.gd; covered by game/tests/pass77_simrun_test.gd.

| # | What | Proposed format | For |
|---|---|---|---|
| 1 | arg `talents` | `talents=<id>:<picks>,<id>:<picks>,...`, picks = one digit a rank, the form (0 the first, 1 the second): exactly Save.data.talents[id].picks, e.g. `talents=grit:000,drive:1,nerve:11`; a talent left out has rank 0; `talents=none` = an empty board; given, it wins over `board=` | Garry: "specify the hero and what upgrades they have" (per talent rank and form; the presets none / quarter / half / full / my save are filled by the page) | **ACCEPTED (+ `<id>:<rank>:<form>`)** |
| 2 | arg `death=ad` | Down! answered with the ad revive while it is offered (a chance left), then the run ends; `death=gold` dropped from the page (Garry is removing Get up with gold). If the ad revive will not stay, say NO | the death policies: end (default), ad, keep | **ACCEPTED (once, then the next Down! is given up)** |
| 3 | row `near3` | int: creatures alive within 3 m of the hero | the Close crowd chart (the lead: "lane SIMRUN adds the field") | **ACCEPTED (+ `near6`)** |
| 4 | row `boss_hp_abs` | float: the boss's current HP (every multiplier), 0 without one (else I use boss_hp x the boss_start event's hp) | Keeping up: the boss's seconds | **ACCEPTED as `boss_hp_abs` in the output (the row key is `boss_now`)** |
| 5 | row `hits` | int: hits that reached the hero that second (RunAnalytics `hits`) | hits taken | **ACCEPTED** |
| 6 | row `took_by` | {creature id or attack name: cumulative HP lost} (RunAnalytics `took`, summed) | what hurt the hero | **ACCEPTED** |
| 7 | row `healed_by` | {source: cumulative HP healed} (RunAnalytics `healed_by`; regen as the source `regen`) | healing by source | **ACCEPTED** |
| 8 | row `spawned` | int: creatures spawned that second (RunAnalytics `spawned`, summed) | spawned against killed | **ACCEPTED** |
| 9 | rows `mult_hp`, `mult_dmg` | float: the HP and damage multiplier of a creature spawned now (RunAnalytics `mults`: stage x hp_t x lvl_hp; stage x dmg_t x lvl_dmg), carried forward | the creatures' strength | **ACCEPTED (your formula; the map's constant creature mults not in it)** |
| 10 | row `held_by` | {weapons, evolutions, lines, passives, perks: int}: the items held at the row | the build's growth | **ACCEPTED** |
| 11 | event `pick` | {t, kind: "pick", item_kind (weapon / evolution / line / passive / perk / mutation), id, level, new} | the picks' timing | **ACCEPTED (+ type, tier, others)** |
| 12 | sim mode | (the lead: the visual work skipped) say its arg if it has one; I measure 10 runs before and after | speed | **ACCEPTED: `fast=1` (the default), `fast=0` plays it all** |

SIMUI, 2026-10-14 23:40, FYI for the fast-mode proof (no request): my two 10-run sims of 25:00 (keep, seeds 1-10, 10 at once) with `fast=1` (started 22:37) and `fast=0` (22:47, the runner already with the round-2 fields) levelled differently: at 10:00 the `fast=0` run was higher in 9 of 9 untied pairs (mean level 38.5 against 31.9; kills at 25:00 18.0K against 15.7K; deaths 7.1 against 5.4). The runner changed between the two, so it proves nothing alone; the folders are tools/dl/sim/runs/p77-speed-keep-k10-fast and p77-speed-keep-k10-nofast (players/pNN.json). Wall times: 10:23 and 18:10 (the slowest runs 2.55 and 1.41 play s a wall second).

## Pass 79: new keys

### The tracer line (lane FX)

Weapon / evolution / mutation `params` (a mutation's value lays over its weapon's, an evolution's `final` block over both):

| key | type | default | meaning |
|---|---|---|---|
| `tracer` | bool | false | (unchanged) the shot draws a tracer: since pass 79 a thin line behind it, no beads |
| `tracer_width` | float, metres | 0.05 (`ProjectileManager.TRACER_WIDTH`) | NEW. The line's width as it is laid; it widens to 1.9x as it fades. Never drawn thinner than 1.5 screen pixels. |
| `tracer_life` | float, seconds | 1.4 (`TRAIL_LIFE`) | (meaning kept) how long each piece of the line lives before it has faded out like smoke |
| `tracer_color` | colour string "#RRGGBB" | the weapon's element colour, else gold | (unchanged) the line's colour; since pass 79 drawn exactly as written (sRGB) |
| `tracer_alpha` | float 0..1 | 0.9 | (unchanged) the line's opacity when fresh; it fades to 0 over `tracer_life` |
| `tracer_clear` | float, metres | 0 | (unchanged meaning) no line on the ground within this distance of the hero (the part inside is cut away) |
| `tracer_size`, `tracer_step`, `tracer_beads` | | | OLD bead keys: kept in the content, draw nothing any more (harmless). The editor may hide them or label them "unused since pass 79". |

Values set in pass 79: revolver `tracer_color` #8B0A0A, `tracer_alpha` 0.9, `tracer_width` 0.045, `tracer_life` 0.9;
silver_bullet and golden_revolver's `final`: `tracer_color` #C9DCEF, `tracer_alpha` 0.9, `tracer_width` 0.11;
drum_mag `tracer_width` 0.065; boomstick and blunderbuss `tracer_width` 0.035.

Vocab: lane FX edited `tools/level_editor/vocab.py` PARAMS_KEYS["ProjectileEmitter"] (the selftest checks every listed
key is read by the sources): `tracer_step` and `tracer_size` out, `tracer_width`, `tracer_clear`, `tracer_color`,
`tracer_alpha` in (selftest 18644 passed, 0 failed). `assets_fields.js` (~116-130) still lists `tracer_step`,
`tracer_size`, `tracer_beads` among the shot keys and has no `tracer_width`: the Level Editor's owner may swap them.

No new key for the corpses: their numbers are code constants (EnemyManager.CORPSE_*), see balancing_FX.md.

### The dynamite's lead (lane WORLD): weapon params (Lobber; vocab.py PARAMS_KEYS / assets_fields.js PARAMS_KEYS; docs/assets_schema.md)
`params.lead` (lob_grenade and golden_pineapple only): the bomb thrown where its crowd will be when it blows.
A number (the share; 0 = off), `true` (share 1), or a block:
| key | type | default | meaning |
|---|---|---|---|
| `share` | number | 1 (in a block; 0 without `lead`) | how much of the foreseen walk is led (1 = all of it, 0.5 = half) |
| `mode` | "predict" \| "chase" \| "walk" | "predict" | predict: five spots from the chosen one to the chase lead are scored by the creatures foreseen inside the blast when it goes off (EnemyManager.predicted_counts), the best wins, the one further ahead on a tie; chase: the crowd closes on where the hero will be (his position + his velocity x `hero_ahead` x the wait) at its mean walking speed for the wait, stopping `gap` m short of him; walk: its mean velocity goes on straight for the wait (drawn back to `gap` m from him where it would pass him) |
| `max` | m | 6.0 (Lobber.LEAD_MAX) | the lead is at most this |
| `gap` | m | 1.5 (LEAD_GAP) | the led spot stays this far from the hero (the crowd stops at him); a crowd nearer than this is not led |
| `radius` | m | 3.0 (LEAD_RADIUS) | the crowd sampled round the chosen spot (EnemyManager.crowd_speed / crowd_velocity) |
| `hero_ahead` | share of the wait | 0.5 (LEAD_HERO_AHEAD) | chase: how far along his run the crowd is taken to head for (0 = where he stands now) |
The wait = the lob's flight (clamp(distance / speed, 0.35, 2.5), as ProjectileManager.lob) + `fuse.seconds` (a weapon
with Sticky only the flight). A priority target (special, Elite, boss) is led by its own walk; a Sticky throw at a
priority target (the Golden Pineapple) is never led. Both weapons' JSON carry the whole block (share 1.0, predict, 6.0,
1.5, 3.0, 0.5) with mode "predict".

New code: EnemyManager `crowd_velocity(at, r) -> Vector3`, `crowd_speed(at, r) -> float`, `walk_velocity(i) -> Vector3`,
`predicted_counts(spots, r, t, goal, gap, center, reach) -> PackedInt32Array` (creatures in the grid, risen; the world's
clock: x time_scale; the push `kb` left out). Lobber `LEAD_MAX`, `LEAD_GAP`, `LEAD_RADIUS`, `LEAD_HERO_AHEAD`,
`LEAD_STEPS` (4), `lead_config(params)`, `lead_spot(...)`, `predict_pick(counts)`, `_keep_gap(...)`, `_lead_target(...)`,
counters `leads`, `last_lead`. A led shot's extra carries `lead_from` (the crowd's spot at the throw);
ProjectileManager.claimed_spots claims it beside the led `target`.

## Pass 80: new keys

### The tracer (lane TRAIL)

Every key sits in a weapon's, mutation's or evolution's `params` (a mutation's keys lay over its weapon's; an evolution's
`final` block over its own). Read by core/systems/ProjectileManager.gd (`_tracer_*`, `tracer_*_of`), drawn by
core/shaders/tracer_line.gdshader. In the Level Editor: the weapon / mutation / evolution form's typed group "Tracer (the
trail behind every round)" (assets_fields.js PARAM_GROUPS id `tracer`, shown where any of these keys is set, else under
"+ typed group"); vocab.py PARAMS_KEYS ProjectileEmitter and assets_fields.js PARAMS_SHARED know `tracer_style` and
`tracer_hot`.

| key | type | default | meaning |
|---|---|---|---|
| `tracer` | bool | false | draw a trail behind every round (unchanged) |
| `tracer_style` | string | `ProjectileManager.TRACER_STYLE` = `"wisp"` | **new.** The look: `"wisp"` (the shipped one: a red-hot tapered streak riding with the bullet over a pale smoke that lingers and fades), `"streak"` (the streak alone: a short tracer round), `"ribbon"` (a longer tapered ribbon whose hot middle dies first, widening a little like a wake), `"toon"` (hard cartoon bands: white middle, flat colour, dark outline), `"line"` (pass 79's thin line that fades like smoke). An unknown name = the default. |
| `tracer_color` | colour string | none (gold; fire orange; poison green; Silver Bullet's silver) | unchanged order (`_tracer_colour`). The Revolver's own is now `#C41E16` (was `#8B0A0A`) |
| `tracer_alpha` | float 0..1 | 0.9 | unchanged |
| `tracer_width` | float m | the style's: `TRACER_STYLE_WIDTH` 0.1 (line 0.05) | the trail's width **at the bullet, glow included**; the streak styles taper behind it (pass 79: the line's constant width). A head is never under 3 screen pixels (the line: 1.5) |
| `tracer_life` | float s | the style's: `TRACER_STYLE_LIFE` wisp 0.55, streak 0.13, ribbon 0.3, toon 0.2, line 1.4 | how long each piece lives (the trail's length = speed x life for the streak part). Leave it out to get the style's own; a weapon that sets it keeps it whatever the style |
| `tracer_hot` | float 0..1 | **new.** the style's: `TRACER_STYLE_HOT` wisp 0.3, streak 0.7, ribbon 0.4, toon 0.5 | the share of the life the white-hot middle lasts; for the wisp, the share that is streak before it turns to smoke. Clamped 0.02..1. Set on the Tommy Gun / Chicago Typewriter (0.45 of a 0.3 s life) and the Boomstick / Blunderbuss (0.5 of 0.25 s) |
| `tracer_clear` | float m | 0 | unchanged (the Revolver's 1.1) |
| `tracer_size`, `tracer_step`, `tracer_beads` | | | the old beads' keys: still draw nothing (pass 79) |

Code constants (ProjectileManager.gd, "pass 79 (lane FX): the tracers' lines" section): `TRACER_STYLE` (the default
style), `TRACER_STYLE_IDS` {line 0, streak 1, ribbon 2, wisp 3, toon 4}, `TRACER_STYLE_LIFE`, `TRACER_STYLE_WIDTH`,
`TRACER_STYLE_HOT` (per id); `tracer_style_id(w)`, `tracer_hot_of(w)`, `tracer_xform(...)` (the segment's transform);
ring arrays `tracer_kind`, `tracer_hot` beside pass 79's. `tracer_segment(a, b, col, width, life, clear, hero, t_a,
style := -1, hot := -1.0)` gained the last two (below 0: the default's).

Shader (tracer_line.gdshader): the line's uniforms are kept (now, widen, rise, fade_pow, smoke_grey, sway, min_px,
edge_soft); the new looks' numbers are `const`s at the top of the file (head_px 3, streak_taper 0.75, ribbon_taper 1,
ribbon_wake 0.7, toon_taper 0.35, toon_scale 0.6, core_size 0.2, inner_w 0.42, halo_alpha 0.42, head_glow 0.8,
core_tint 0.14, core_white, rim_pow 2.4, rim_gain 0.9, rim_from 0.45, rim_mix 0.35, rim_light 0.9, light_dark 0.3,
warm_dark 0.8, warm_tip 0.3 (a light saturated colour, gold: an amber body and a white middle only at the tip),
glow_soft 0.42, toon_outline 0.62, smoke_width 2.4, smoke_alpha 0.38, smoke_rise 0.35, smoke_colour).

#### How Garry switches the look
- One weapon: its JSON `params` `"tracer_style": "streak"` (or ribbon / toon / line / wisp), or the Level Editor's
  Tracer group, Style select; import (Save in the editor does it). The Revolver's JSON names it already
  (`"tracer_style": "wisp"`), so the Revolver is one word away.
- One path: the same key on a mutation (it lays over the weapon's) or in an evolution's params / `final`.
- Every tracer weapon at once: `const TRACER_STYLE := "wisp"` in game/core/systems/ProjectileManager.gd.
- Back to pass 79 exactly: `"tracer_style": "line"` plus the old `"tracer_life"` (Revolver 0.9) and `"tracer_width"`
  (Revolver 0.045, Silver Bullet 0.11) and colour `#8B0A0A`.

#### For docs/assets_schema.md (the lead): "Pass 80" paragraph
`params.tracer_style` (string, default "wisp": wisp | streak | ribbon | toon | line) and `params.tracer_hot` (0..1, the
style's) pick the look of a weapon's tracer; `tracer_width` is now the width at the bullet glow included (default the
style's, 0.1 m), `tracer_life` the style's when absent (wisp 0.55 s). Research and pictures: tools/dl/p80/TRAIL/.

### The bot's options: sim_run.gd, sim_batch.py, the Sim tab (lane BOT)

The bot is `game/tools/bot/Bot.gd` (with BotLegs.gd, BotCards.gd, BotGoals.gd). Its options are one dictionary; the run
sim takes the same keys as args (`key=value`), tools/sim_batch.py as `--bot "key=value,key=value"` or the settings'
`bot` dict, the Level Editor's Sim tab in its "Bot" group. A key left out takes its preset's value.

#### Options (Bot.resolve_opts)

| key | type | default (explorer) | meaning |
|---|---|---|---|
| `preset` | explorer \| sim77 \| careless \| expert | explorer | the whole set (below); `sim77` is pass 77's bot exactly |
| `seed` | int | 1 (the sim: the run's seed) | the bot's dice: card ties and skill noise (`hash([seed,"bot"])`), the legs (`hash([seed,"pilot"])`), the planner's taste/mood/jitter (`hash([seed,"goals"])`), the dodge roll (`hash([seed,"dodge"])`) |
| `skill` | 0..1 | 0.9 | decision quality: every score read with a gaussian error of (1 - skill) x 25 points; 1 always the best |
| `style` | balanced \| damage \| safety \| greedy | balanced | the scores' weights (dps / survival / plan / greed) and the goals' (STYLE_GOALS) |
| `reaction` | s, 0..3 | 0 | delay before a new warning (a telegraph younger than it is not seen) or a big one close (the danger push seen that late) is acted on |
| `dodge` | 0..1 | 1 | the share of warnings on the sand he sees at all (a fixed roll per warning) |
| `daring` | 0..1 | 0.5 | the kite's distances: keep 4.5 + (0.5 - daring) x 4 m, flee 2.6 + (0.5 - daring) x 2 m |
| `stray` | m, 0..200 | 60 | how far the sweep looks for gems (pass 77's lure_r; `lure_r=` still works) |
| `explore` | 0..1 | 0.6 | the wish to see the map (0: no explore goals) |
| `totems` | bool | on | Totem Poles are goals (seen ones) |
| `barrels` | bool | on | barrels are goals (seen ones) |
| `powerups` | bool | on | power-ups lying in sight are goals, and the sweep counts them (pass 77's sweep did; off: neither) |
| `structures` | bool | on | the other structures are goals by what they give (not totems; shop and stranger also need their own key) |
| `shop` | bool | on | walks to the Travelling Shop with gold to spend and buys a ware worth its price; off: leaves at once |
| `stranger` | bool | on | walks to the Stranger while healthy and takes his deal when it is worth the cut; off: walks away |
| `boss` | leash \| free | leash | leash: within 10 m of a living boss (pass 77's rule); free: roams |
| `cards` | score \| tier | score | score: cards, mutation offers, totem gifts by score; tier: pass 77's order, a random mutation, the most feathers |
| `death` | end \| ad \| keep | end (the sim passes its `death`) | how Down! is answered (the sim's own policy) |
| `lure_w`, `lure_close` | float | -1 (the legs' 2.0 / 0.3) | pass 77's sweep knobs |
| `t0` | float | 0 | the caller's clock when the bot starts (the run sim's, so the legs' idle wander stays pass 77's) |

#### Presets (Bot.PRESETS; plain literals, read by tools/sim_batch.py bot_presets())

| | skill | style | reaction | dodge | daring | stray | explore | totems | barrels | powerups | structures | shop | stranger | boss | cards |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| sim77 | 1 | balanced | 0 | 1 | 0.5 | 60 | 0 | off | off | on | off | off | off | leash | tier |
| explorer | 0.9 | balanced | 0 | 1 | 0.5 | 60 | 0.6 | on | on | on | on | on | on | leash | score |
| careless | 0.4 | balanced | 0.6 | 0.5 | 0.8 | 60 | 0.4 | on | on | on | on | on | on | free | score |
| expert | 1 | balanced | 0.1 | 1 | 0.45 | 60 | 0.7 | on | on | on | on | on | on | leash | score |

#### The API (INTERFACES.md)
`BOT.new(game, opts)`, `bot.tick(dt)`, `bot.intent`, `bot.goal`, `bot.decisions`, `signal decided(entry)`; also
`bot.opts` (resolved), `bot.summary()`, `bot.events` (the run sim's pick/portal/assist/revive events), `bot.revives`,
`bot.assists`, `bot.picks`, `bot.mode_frames`, `bot.metres`, `bot.planner` (BotGoals or null), `Bot.resolve_opts(raw)`,
`Bot.planner_on(opts)`, `bot.hp_frac()`, `bot.danger()`, `bot.dps_now()`.

Decision entry: `{t, clock, kind, offered: [{id, name, score, parts}], taken, reason, level, dps_before}`; kinds: card,
mutation, chest, totem, stranger, shop, structure (a structure the bot walked to was used), goal (also `what`,
`runner_up`; a goal given up is a goal entry with taken ""). Card parts: dps (% of the estimated DPS now), survival,
plan, greed; the shop's also price and gold (the price in points), the Stranger's hp_cost, a totem gift's feathers.
A goal's parts: value, dist.

#### sim_run.gd output (additive)
- `meta.bot`: `{opts, metres, goals {kind: commits}, gave_up, decisions {kind: n}, seen (share of the arena), shop_bought,
  stranger_taken, tallies {structures_by {id: n}, structures (not totems), totems, totem_t [play s], powerups (taken,
  the small ones not counted), barrels (BarrelField.broken)}}`.
- `bot_decisions`: every decision entry.
- New args: `preset= skill= style= reaction= dodge= daring= stray= explore= totems= barrels= powerups= structures= shop=
  stranger= boss= cards=` (sim_run.gd `BOT_ARGS`); a preset it does not know is an argument error.

#### tools/sim_batch.py
- settings key `bot` (sparse dict; `{}` = the runner's default preset), CLI `--bot "preset=sim77,skill=0.8"`;
  `BOT_PRESETS`, `BOT_KEYS`, `clean_bot`, `bot_arg`, `bot_presets(game_dir)`, `bot_effective`, `bot_words`;
  `runner_caps()["bot"]` (the runner has BOT_ARGS); a bot setting on an older runner is a caps problem.
- result.json `bot`: `{summary {totems, totems_20, barrels, structures, powerups, shop, stranger, metres, seen, gave_up}
  (means), players [{k, preset, ...the same, structures_by}]}` (beside aggregate()'s keys).

#### Level Editor
- `/api/sim/settings` → `bot: {default, presets [{key, label, help, values}], keys [{key, kind, lo, hi, step, choices,
  label, help}]}`; the history's `bot_words`.
- jobs.py "sim" spec field `bot` (json) → `--bot`.
- The Sim tab: a "Bot" group under the Upgrade board: the four presets, every option with the value the runs play (the
  preset's, or set here, marked, × back to the preset's); the head card's "Bot:" line with the map tallies; the runs
  table's "the map" column.

### The Watch (lane WATCH)

#### tools/watch.py (the launcher; `tools\watch.cmd` = `--hero drifter --board quarter --seed random` + whatever is passed)
| Option | Default | Meaning |
|---|---|---|
| `--hero <id>` | drifter | the hero (any, hidden ones too) |
| `--board none\|quarter\|half\|full\|save\|<ranks>` | quarter | the Upgrade board as the Sim's presets (sim_batch.board_talents); `save` = the PC save's board (read only) |
| `--talents grit:AAB,drive:A` | | the board talent by talent (A the first form, B the second); wins over `--board` |
| `--seed <n>\|random` | random | the run's dice (Run.seed_dice, the map layout, the crowd's and the pickups' dice) |
| `--map <id>` | red_canyon | |
| `--limit <s or m:ss>` | 0 | the run ends after that much play (0: until he falls / extracts) |
| `--speed 0.25..8` | 1 | the speed at the start (the nearest of 0.25, 0.5, 1, 2, 4, 8) |
| `--paused` | off | start paused |
| `--death end\|ad\|keep` | end | Down! as the bot answers it (the Sim's `death`) |
| `--unlocks all\|save` | all | every unlock quest done (the whole content in the card pool), or the Watch save's (none) |
| `--ref auto\|none\|<result.json>` | auto | the charts' grey line: the newest Sim result (tools/dl/sim/runs) of the same hero, board and map |
| `--bot key=value` (repeatable) | | a bot option (lane BOT's keys: preset, skill, style, reaction, dodge, daring, stray, explore, totems, barrels, powerups, structures, shop, stranger, boss, cards) |
| `--bot-preset <name>` | | = `--bot preset=<name>` (explorer, sim77, careless, expert) |
| `--stub` | off | the Watch's stand-in bot (game/tools/watch/BotStub.gd: pass 77's rules in small) instead of tools/bot/Bot.gd |
| `--mute` | off | start with the sound off |
| `--no-numbers` | off | no floating damage numbers (above 2x they are always off) |
| `--size WxH` | 1920x1080 | the window (fitted to the screen's usable area) |
| `--skip-draw 1\|0` | 1 | above 1x the frames that are not drawn skip the drawing work (Run.sim_mode); 0 keeps it (slower) |
| `--no-sync` | off | play the snapshot as it is |
| `--wait` / `--timeout <s>` | off / 0 | wait for the window to close (and kill it after the timeout); the exit code is Godot's |
| `--autoquit` | off | close the window when the run ends |
| `--wall <s>` | 0 | end the run after that many wall seconds |
| `--shots <dir>` / `--shots-at <play s,...>` | | window PNGs at those moments and at the end |
| `--actions <when>:<what>,...` | | checks: `p<play s>` or `w<wall s after the action before>`, then `pause`, `go`, `step`, `level`, `speed=<x>`, `shot=<name>`, `end`, `say` |
| `--log-speed <s>` / `--profile` | 30 / off | the log's speed line every that many wall seconds; with the frame costs |
| `--log <file>` | tools/dl/watch/logs/watch_<time>.log | Godot's log |

Files: snapshot `tools/dl/watch/snap/game` (user folder `%APPDATA%/Godot/app_userdata/88fits_watch`), lock
`tools/dl/locks/watch.lock` (owner.json names the Godot pid; the window lets go of it when it closes), logs
`tools/dl/watch/logs/`. The run's record: `analytics/runs/tools/<stamp>.json` (schema 2, `header.launch.watch = true`,
`header.watch = {bot, bot_opts, board, talents, ref}`), the decision log `analytics/runs/tools/<stamp>_decisions.csv`.

#### The Godot side (watch_main.gd -> Watch.gd), after `--`
`hero= seed= map= talents= board_label= limit= speed= paused= death= unlocks= repo= lock= sound= numbers= log_speed=
ref= ref_label= bot= bot.<key>= autoquit= wall= shots= shots_at= w= h= profile= actions= skip_draw=` (watch.py writes
them; started as `Godot --fixed-fps 60 --path <snapshot> --log-file <log> --script res://tools/watch/watch_main.gd -- ...`).

#### The decision log CSV
`t, clock, level, kind, taken, taken_name, reason, offered (id=score | ...), est_dps_before (the bot's dps_before),
real_dps_before (mean real DPS over the 30 s before), real_dps_after_30s (the 30 s after), real_change_pct` (empty =
not known: no row in the window, or under 1 DPS before).

#### The Level Editor
Sim tab: a **Watch** button in the "Run a sim" head row (sim.js `watchRun`): `POST /api/sim/watch {settings}` (sim_io.py
`watch`, `watch_args`): tools/watch.py started (not waited for) with the tab's hero, board (talents), seed, map, Down!
answer and bot options; 409 while a Watch is open (watch.lock's owner alive). Its own output: tools/dl/watch/logs/launch_<time>.log.

#### Keys in the window
Space pause / go on · 1..6 the speeds 0.25x, 0.5x, 1x, 2x, 4x, 8x · + / - faster / slower · . (period) step one second ·
L run to the next level-up · G the charts' last 3 minutes / whole run · M sound. (No WASD or arrows: they steer the hero.)

## Pass 81: new keys

### The bees' trail, the rocket, the sniper (lane POLISH)

#### Weapon / evolution params (MissilePod), in `params.missile`
| key | type | default | meaning |
|---|---|---|---|
| `trail_style` | string | `ProjectileManager.BEE_TRAIL_STYLE` = `"dash"` | **new.** The look of a bee's line (a seeker whose `trail` is 2; Pollen's red bees, trail 4, wear the same look in red): `"dash"` (the cartoon bee's dotted flight path, dark honey-brown dashes, 0.45 s), `"buzz"` (a thin honey squiggle weaving either side), `"bumble"` (the dashes weaving), `"zip"` (a short tapered gold streak), `"beads"` (pass 49's dark beads). Unknown name = the default. Any other trail number (1 = rocket smoke) ignores it. Set on hornet_nest, hive_queen, killer_swarm (`"dash"`). |
| `trail_color` | colour string | none (the look's own) | **new.** Recolours the bee's line (alpha stays the look's); never Pollen's red. |

Level Editor: typed group "Bee trail (the seekers' line)" (assets_fields.js PARAM_GROUPS id `bee_trail`, MissilePod, shown
where either key is set); selftest_L69's SOURCES now lists MissilePod (MissilePod.gd, ProjectileManager.gd).

Code constants (ProjectileManager.gd, "pass 81 (lane POLISH): the Killer Bees' trails"): `BEE_TRAIL_STYLE`,
`BEE_STYLE_IDS` {dash 5, buzz 6, bumble 7} (tracer_line.gdshader styles; zip draws as the guns' streak, 1), `BEE_LOOKS`
(per look: style, color, red, width, life, step), `BEE_WRAP` 6.3 m; functions `bee_trail_look(trail, style)`,
`_bee_trail_start`, `_bee_trail`; diagnostics `bee_segments`. Shader consts (tracer_line.gdshader): bee_taper 0.5,
bee_dash_period 0.42, bee_dash_len 0.24, bee_dash_edge 0.55, bee_buzz_wave 0.9, bee_buzz_amp 0.11, bee_buzz_in 0.18. For
styles 5-7 the segment's `hot` slot carries the path's length at its start.

#### Creature blocks
| key | type | default | meaning |
|---|---|---|---|
| `sniper.spoil_on_hit` | bool | true | **new.** A hit that lands (never a poison or fire tick) drops the sniper's aim or lock under way (no shot; next aim after `recover`). EnemyManager.sniper_spoil_on_hit. The Saiga sets it true. |
| `sniper.flee_range` | float m | **0** (was 14 in code) | unchanged meaning; the code's default is now 0 = never runs. The Saiga's is 0. |
| `sniper.follow` | float m | stand_off + 12 | unchanged meaning (walks towards the hero while he is farther; inside it holds and aims); the Saiga's 38 -> 16. |
| `flee_on_hit` | block | {} | unchanged primitive; removed from the Saiga: no creature has it now. |
| `artillery.missile.speed_of_hero` | float | 0 | meaning sharpened: the share of the hero's top speed the rocket covers **on the ground** (the creatures' whole pace taken out, ProjectileManager.rocket_clock_pace); the Raider's 0.9 -> 0.85. |

Level Editor: assets_fields.js sniper rows (flee_range def 0 and help, follow help, new row "Spoiled by a hit"), the
sniper brain's option text; vocab.py BLOCKS["sniper"] (flee_range 0.0, spoil_on_hit True).

#### For docs/assets_schema.md (the lead): "Pass 81" paragraph
`params.missile.trail_style` (string, default "dash": dash | buzz | bumble | zip | beads) and `params.missile.trail_color`
(colour) pick the look of a bee's line (MissilePod seekers with trail 2/4), drawn in the tracers' ring. Creature
`sniper.spoil_on_hit` (bool, default true): a hit drops the aim; `sniper.flee_range` now defaults to 0.
`artillery.missile.speed_of_hero` is the rocket's share of the hero's top speed on the ground.

### The production build (lane PROD)

#### Code (game)
| Name | Type / default | Meaning |
|---|---|---|
| custom feature `prod` | export preset feature | set by the presets "Android Prod" and "Windows Desktop Prod"; `OS.has_feature("prod")` |
| `Settings.is_prod()` | bool | the production build: the feature `prod`, or forced (`prod=1` / `--prod` after `--` on the command line, `Settings.force_prod(true)` in a test) |
| `Settings.build_flavour()` | "prod" \| "dev" | the build's flavour |
| `Settings.force_prod(on)` | method | tests and checks: on forces prod (and locks the switches); off returns to the command line's / the build's own |
| `Settings.PROD_LOCKED` | const Dictionary | the developer switches and the value prod holds them at (debug_mode, debug_panel, debug_modal_buttons, free_revive_button, hit_log, preview_locked_heroes: false; menu_style: "live"; ranged_on_screen, pierce_falloff: true) |
| analytics super property `build` | "prod" \| "dev" | on every event, beside `dev` |
| TitleScreen node `ArenaButton` | name | the debug arena's button (was unnamed), hidden in prod |

#### Export presets (game/export_presets.cfg)
| Preset | Key | Value |
|---|---|---|
| preset.0 "Android" (dev) | package/name | "88fits Dev" (was "88fits"; package unchanged) |
| preset.1 "Windows Desktop" (dev) | application/product_name, file_description | "88fits Dev" |
| preset.2 "Android Prod" | custom_features | "prod" |
| | package/unique_name | "com.eightyeightfits.game.prod" |
| | package/name | "88fits" |
| | version/name | "" (= application/config/version) |
| | version/code | 1 in the source; the staging copy writes major x 10000 + minor x 100 + patch |
| | exclude_filter | the dev one + addons/content_dock/*, *_ai.json, icon.ico |
| | export_path | export/88fits-prod.apk (ship_prod.sh exports to tools/dl/prod/out/) |
| preset.3 "Windows Desktop Prod" | custom_features | "prod" |
| | exclude_filter | the dev one + addons/content_dock/*, *_ai.json |
| | export_path | export/88fits-prod.exe |

#### The staging copy's project.godot (tools/prod_stage.py; never the source's)
| Key | Value |
|---|---|
| application/config/use_custom_user_dir | true |
| application/config/custom_user_dir_name | "88fits" (the prod exe's save: %APPDATA%/88fits) |
| application/config/custom_user_dir_name.editor | "88fits_prod_stage" (the editor binary's runs on the staging copy) |

#### Files
| Path | What |
|---|---|
| game/tools/prod_reach.gd | the reachability (static, takes the Registry) |
| game/tools/prod_plan.gd | writes the plan JSON: keep {folder: why}, drop {folder: why}, looks {folder: {kind, play, base, keep, drop, promote}}, pins, counts, registry_problems, version |
| game/tools/prod_check.gd | the staging copy's checks (`-- plan=<file>`) |
| game/tools/prod_run_check.gd | boot -> title -> settings -> developer menu -> a run with prod forced, in the staging copy |
| tools/prod_stage.py | the staging copy (tools/dl/prod/stage/game) |
| tools/prod_prune.py | the prune (`--plan`, `--report`, `--dry-run`, `--selftest`) |
| tools/prod_optimise.py | music to Ogg, the icon, lossy props (`--ogg-quality`, default 4) |
| tools/prod_probe.py | an exported exe's cold start to the title and its user folder (`--expect prod|dev`, `--repeat`) |
| tools/prod_report.py | sizes and report.md |
| tools/ship_prod.sh | the whole route (`--no-drive`, `--quick`, `--no-pc`, `--no-android`, `--out`) |
| .claude/skills/ship-prod/SKILL.md | the skill |
| Drive | `E:/My Drive/88fits builds/88fits-prod.apk`, `88fits-prod.exe` (only from ship_prod.sh without --no-drive) |

## Pass 82: new keys

### The HP bar's shake, the bodies (lane FEEL)

None. Both changes are code constants (named in balancing_FEEL.md): `HUD.HP_SHAKE_*` (ui/HUD.gd) and
`EnemyManager.CORPSE_FLOOR_* / CORPSE_HEAVY_* / CORPSE_HIT_TOSS_* / CORPSE_HEFT_* / CORPSE_CRIT_WEIGHT` (core/systems/
EnemyManager.gd). No content JSON, no map key, no new stat.

### The Spirit Pole (lane TOTEM)

#### Content (JSON)
| Key | Type | Default | Meaning |
|---|---|---|---|
| `content/structures/<id>.params.spent_motion` | `{flash: float s, fade: float s}` | absent (pass 73's instant grey) | With `params.spent "grey"`: the structure keeps its paint and ring once used, flashes its ring `flash` s when its screen opens (StructureManager.flash_ring) and drains to grey over `fade` s when the screen's gift is taken (spend_slowly). The Totem Pole: `{"flash": 0.12, "fade": 0.4}`. |
| `params.boons[].icon` (Totem Pole pool entry) | string path (`res://...` or relative to res://) | absent | The spirit's carved face. Without it the slot `res://art/ui/totem/spirit_<entry id>.png` is used (256 px square, transparent, thick dark outline); an empty slot shows the plate with the spirit's word. Today: wolf, bear, frog, serpent hold the handoff's low-res stand-ins; whale, thunderbird, seal, salmon, killer_whale, bullhead, raven are empty. |

#### Art
`game/art/ui/totem/crest.png` (the thunderbird crest, 360x108, from the handoff), `spirit_wolf.png`, `spirit_bear.png`,
`spirit_frog.png`, `spirit_serpent.png` (96x96 letterboxed stand-ins, the handoff's face-*.png). An artist fills a slot
by dropping `spirit_<id>.png` in and running --import.

#### Code (new primitives)
| Symbol | Meaning |
|---|---|
| `TotemBoons.word / animal / roll_third / range_texts / icon_path / icon_of / toast_text / pole_label / ordinal` | the screen's data from a rolled boon |
| `TotemScreen.open(offer, def, index, total)`, signal `closing(boon)` (at the pick) and `closed(boon)` (300 ms later), `planks()` / `rows()` (each `boon`, `feathers` = roll third, `plate`, `tag`, `amount`, `stat`, `spirit`, `gauge`, `nail`, `group`), `label_text()`, `_pick(row)`, `_done` | the screen (tools' API kept) |
| `WNotches` (ui/wanted) | the roll gauge: `low`, `high`, `filled`, `count`; 56x18 notches, 3 px ink, 8 apart, Bitter 600 18 ends |
| `WNail` (ui/wanted) | a 32 px brass nail head in a 4 px ink ring |
| `WToasts.push(t, c, icon)`, `WToasts.icon_spot(t)`, `HUD.toast(text, color, icon)`, `HUD.toast_icon_spot(text)` | a toast may carry a 72 px icon before its words |
| `StructureManager.flash_ring(at)`, `spend_slowly(at, seconds = -1)`, `count_of(id)` | the in-world pole's motion; the map's count of a kind |
| `sprite_billboard.gdshader` uniform `desat` (0..1), `BillboardSprite.set_desat(v)` | a painting drained of its colour |
| `Hints.totem_taken()` | the once-per-save totem hint |

### The bot and the Watch (lane WATCH)

#### The bot's option (game/tools/bot/Bot.gd PRESETS / resolve_opts; tools/sim_batch.py BOT_KEYS; sim_run.gd BOT_ARGS)
| key | type | default | meaning |
|---|---|---|---|
| `specials` | bool | on (explorer, careless, expert), off (sim77) | goes to find a glowing special that does not come: known 5 s (within 30 m) and still out of reach (past 9 m or off the screen); leans the kite in until it is within 6 m and on screen ("found"), then plays on while the weapons take it; not while a boss lives, none new under 50% health |

Taken as `specials=0|1` by the run sim (sim_run.gd arg), `--bot "specials=0"` by tools/sim_batch.py, the Level Editor's
Sim tab ("Bot" group: a new switch "Specials", from BOT_KEYS), `--bot specials=0` by tools/watch.py.

#### The bot's outputs
- New intent `special` (hunting one).
- Decision entries: the goal `{"kind": "goal", "what": "special", "reason": "a special: Red Goblin, a 35% chest (14 m)"}`;
  the end `{"kind": "special", "taken": <creature id>, "offered": [{id, name, score, parts {value, hunt_s}}], "reason":
  "found the special Red Goblin after 4 s: in reach, the weapons take it first"}` (or "... is down after 7 s of the
  hunt, a chest dropped" when it fell before he reached it); a give-up is the usual goal entry, taken "".
- `meta.bot.goals.special` (hunts started) and `meta.bot.specials` (Bot.summary, the run sim's output): `{came, killed,
  chests, life_s, hunted, found, hunted_down, gave_up}` (came / killed / chests from the recorder's `special` and
  `special_kill` events, life_s the mean play seconds a special stood; hunted = hunts started, found = brought in reach,
  hunted_down = fell before that, gave_up; the rest of the hunts were overtaken by a better goal).
- BotGoals candidates of kind `special` carry `index`, `serial`, `sid`, `name`, `fight`; `BotGoals.special_key(i, serial)`
  = "sp:<i>:<serial>", `BotGoals.special_seen` {key: play s first known}; `Bot.special_standing(em, i, serial)`,
  `Bot.special_in_reach(em, i, me)` (static).

#### The Watch (game/tools/watch/)
- The mouse on the phone view is a finger in the game (no option: always on). `Watch.finger_event(e, view_size, sub_size,
  down, last)` (static) turns a mouse event into the touch pushed into the SubViewport.
- New `--actions` words (tools/watch.py `--actions`, Watch.gd `actions=`): `click=<x>/<y>` (a click at that point of the
  game's 1080-wide canvas), `gamepause` (a click on the HUD's pause disc), `gametab=<0|1|2>` (Build, Stats, Options of the
  pause screen), `gameslider=<i>/<0..1>` (the i-th slider on the pause screen, 0 Sound, 1 Music on the Options tab,
  dragged from its thumb to that share of its track over 10 frames), `gameresume` (its RESUME), `whole` (the charts'
  whole run / last 3 minutes, as the G key). The clicks go through the window's input (Input.parse_input_event): pressed,
  let go 3 frames later.
- WatchClock `game_hold` (bool): the game's own pause screen is up; the frames come as at 1x.
- WatchData: `pickups {chests, powerups, totems: [play s]}`, `pickup_totals()`, `specials_came`, `specials_killed`,
  `special_chests`. WatchPanel: `PICKUP_MARKS`, `pickup_points(pickups)` (static). WatchChart: `points [{x, lane, shape,
  color}]`, legend items `[text, color, shape]`.
- The panel: Live tiles "Chests", "Power-ups", "Totems" and "Specials" (14 tiles, three rows of five), the Level and XP
  chart's marks and legend; the speed badge is hidden while the game's own pause screen is up (its RESUME sits there).

### The pickups series (lane STATS)

No content JSON key, param, special or stat. New keys in the analytics outputs:

| where | key | type | meaning |
|---|---|---|---|
| run sim player file (`game/tools/sim_run.gd` series(); `tools/dl/p77/keys_SIMRUN.md`) | `chests`, `powerups`, `totems` | int array, as long as `t` | picked up so far at each row (rules: balancing_STATS.md) |
| sim `result.json` (`tools/sim_batch.py` aggregate(), `sim_avg.js` aggregate()) | `series.chests|powerups|totems.mean` | number array (0..T) | the mean over the runs still playing |
| sim `result.json` | `players[].chests|powerups|totems` | int or null | each run's count at its own end (null: a runner before pass 82) |
| sim `result.json` | `summary.chests_mean|powerups_mean|totems_mean` | number or null | the mean of those over the runs |
| rows CSV (dashboard and `tools/analytics_csv.py`) | `chests`, `powerups`, `totems` | int | three columns after the row's own keys, before the maps |
| Sim chart | id `pickups`, title "Chests, power-ups, totems", section `rewards` | | after Kills |

Functions (the one rule, three languages):

| file | names |
|---|---|
| `tools/level_editor/sim_model.js` | `SimModel.PICKUP_SERIES` ({key, label, color, words}), `PICKUP_KEYS`, `isSmall(v)`, `pickupKind(e)`, `pickupTimes(events)`, `pickupCounts(events, ts)`, `pickupTotals(events)` |
| `game/tools/sim_run.gd` (static) | `PICKUP_KEYS`, `pickup_kind(e)`, `pickup_times(events)`, `pickup_totals(events)` (the Watch can call them through `preload("res://tools/sim_run.gd")`) |
| `tools/analytics_csv.py` | `PICKUP_KEYS`, `is_small(v)`, `pickup_kind(e)`, `pickup_counts(events, ts)` |

#### SCHEMA.md lines (already written into analytics/SCHEMA.md by this lane)
- a new section **Chests, power-ups and totems (pass 82)** after *Events*: the three counts, the rule, when an event
  counts, where they show (sim player files and result.json, the Sim chart, the dashboard card and Progression marks,
  the rows CSV, the Watch);
- *CSV (pass 74)*, rows: "(pass 82) then `chests`, `powerups`, `totems`, picked up so far".

## Pass 83: new keys

### The totem segments (lane TOTEM)

No new JSON key, param, special or stat. The art slots are pass 82's: `res://art/ui/totem/spirit_<boon id>.png`
(TotemBoons.ICON_SLOT; a pool entry's own `icon` path still wins) and `res://art/ui/totem/crest.png`. Since pass 83 a
spirit's picture is an OPAQUE 256 px square (a carved segment of the pole that fills its plate inside the ink border);
a new spirit added to `params.boons` without a picture still shows its word on the empty plate.

Layout constants (ui/TotemScreen.gd, code, not data): CREST_MAX_H 150, CREST_SINK 12, POST_W 200, POST_FILL #7A341F,
FACE = SEG - 2 x SEG_BORDER (288), CEDAR_PATH res://art/ui/totem/cedar.png (the post and the base), POST_SHADE 0.72.

### Heroes and quests (lane META)

No new JSON key, param, special or stat. What the Level Editor already writes covers it:

- `content/characters/<id>.json` `availability` / `price`: Ironwood `available` -> `purchase`; prices changed (see
  balancing_META.md). A hero's requirement is still the quest `unlock_<hero>`: new `content/quests/unlock_fadeaway`
  (`kills_of_enemy`, `saiga_sniper`, 3); `unlock_ironwood` retired (moved to tools/level_editor/backups/deleted/).
- `content/talents/spite` form Thorns: `effects[0].value` 5 -> 2, `text` follows.

Code constants (not data):
- `Game.THORNS_RADIUS` 2.3 m, `Game.THORNS_KNOCK` 6.0 (unchanged numbers, named), `Game.THORNS_COOLDOWN` 0.5 s (new).
- Damage id `"thorns"` in `Run.damage_by_weapon` / the run record's damage sources (the Results already named it).
- `Save.FREED_BY_QUEST` {"ironwood": "unlock_ironwood"}: a save that had done the hero's old quest owns him.
- `CollectionScreen.item_hero(def)` / `hero_item_hidden(def)` (static).

### Props: variants and shadows (lane SCENE)

#### game/art/sprites/props/props.json (per painting)
| key | type | default | meaning |
|---|---|---|---|
| `variant_of` | string (a painting id) | absent | this painting is another look of that kind: wherever the map places the kind, PropField.add draws the kind's own painting or one of its variants, chosen by a hash of the spot (PropField.pick_look), never by the map's roll, so a seed's layout, colliders and obstacle circles are unchanged; the `placed` row keeps the kind's id, `look` names the painting. A variant keeps its own `height`, `cell` and `shadow`; its `radius` is unused while the map asks for the kind (the kind's radius makes the collider). |
| `weight` | float >= 0 | 1 | the painting's share in its kind's pick (the kind's own entry counts too). 0 keeps a variant out of the scatter while it can still be placed by name (the title's vignette). |
| `shadow` | {w, d, x, z, a} | PropField.SHADOW_DEFAULT {0.5, 0.24, 0, 0, 0.35} | the painting's ground shadow, in shares of its drawn quad's height (props: `height` x the placed scale; structures: StructureDef.height x 1.15): `w` across, `d` deep (an ellipse), `x` the foot's offset right of the quad's middle (mirrors with a flipped painting), `z` the painted foot's offset (negative = back, up the screen: the foot stands a little up its leaning quad), `a` its darkness 0..1 (0 = no shadow). Measured from the painting by `python tools/prop_shadows.py` (kept unless `--force`); tune by hand. |

#### game/art/ui/title_scene.json (new file: the live title's vignette, per map id)
| key | type | meaning |
|---|---|---|
| `<map>.clear` | {x: [min, max], z: [min, max]} metres | the box round the hero's title spot (TitleStage.SPOTS) from which the map's own scatter is taken away (x right, z towards the camera) |
| `<map>.props[]` | {id, x, z, scale = 1, flip = false, sway = 0} | each painting laid by hand: the very painting named (a kind's own or a variant; never picked by the spot), x/z metres from the hero's spot, with its ground shadow |

#### Constants (code)
- PropField.SUN_SHIFT (0.08, -0.02) metres per metre of height, capped at SUN_SHIFT_MAX 0.3 m: the shadows lean right (and a touch back), away from the paintings' upper-left light.
- BarrelField.SHADOW_W/D/A/TALL 0.95 / 0.66 / 0.5 / 0.9; SignField.SHADOW_W/D/A 1.25 / 0.8 / 0.42 (shifted for the drawn post's 5.3 m); StructureManager.SHADOW_IN 6 m (a Strongbox coming down has its whole shadow under it from that height).
- core/shaders/ground_shadow.gdshader uniforms: tint (the blob colour), inner 0.45, soft 0.9 (falloff), strength (a lone mesh's).
- perf_late.gd: `shadows=0` hides the scenery shadows (the A/B).

## Pass 85: new keys

### Props, the title, teleports (lane WORLD)

#### game/art/sprites/props/props.json (per painting; a variant without its own takes its kind's)
| key | type | default | meaning |
|---|---|---|---|
| `tint` | one rule {..} or a list of up to 2 (PropField.TINT_PARTS) | absent = no tint | the painting's natural colour variation. Each rule: `hue` [lo, hi] turns (the pixels it touches; lo > hi wraps through red; absent = every hue), `sat_min` (0.1: greyer pixels, outlines and bleached bone are left alone; the darkest lines always are), `h` [min, max] (added to the hue, turns, at most +-0.08), `s` [min, max] (times the saturation, within 0.6..1.4), `v` [min, max] (times the value, within 0.75..1.2), `link` 0..1 (0.5; how much the s and v rolls follow the h roll, so a plant is drier or lusher as a whole). The second rule works on the first's result. |

Per instance: three rolls from a hash of the spot (PropField.tint_code: 12 levels each, packed in INSTANCE_CUSTOM.w as
r1 + 12 r2 + 144 r3 < 2048), so a map seed always tints the same; the painting's rules are its material's uniforms
(prop_billboard.gdshader `tint_hue_k`, `tint_hs_k`, `tint_v_k`). No new draw call.

#### game/art/ui/title_scene.json (per map)
| key | type | meaning |
|---|---|---|
| `<map>.presets[]` | {name, props: [...]} | the live title's arrangements, one drawn at random each time the title opens; `props` as before ({id, x, z, scale, flip, sway}). A bare `<map>.props` (the pass 83 file) still reads as one preset. `clear` is shared by every preset. |

#### content/structures/<id>.json `params`
| key | type | default | meaning |
|---|---|---|---|
| `per_map.max_chance` | float 0..1 | absent | with it, `max` stands that share of the runs and otherwise a count in min..max-1 (StructureManager.per_map_count); without it, min..max evenly (pass 73) |
| `per_map.kin_spacing` | metres | 0 (none) | how far apart two of this structure stand (kept in full; only in the last fifth of the tries may it close to StructureManager.KIN_RELAX 0.75 of itself) |
| `land_clear` | metres | 0 (none) | the Teleport: the hero never comes out within this of any Teleport (StructureManager.teleport_landing_ok) |
| `land_water` | metres | 0 (none) | the Teleport: nor within this of the water (on top of Game.teleport_hero's own: obstacles + 1.5 m, not in the water) |

Teleport now: radius 1.8 (was 2.2), height 2.7 (was 3.2), per_map {min 3, max 4, max_chance 0.33, kin_spacing 40},
land_clear 15, land_water 2 (out of the weighted draw: `weight` 2 is unused while per_map is set).

#### Code
- TitleStage.force_preset (static, -1 = random), TitleStage.scene_of(map), presets_of(scene), preset_index, preset_name.
- PropField.mark() / truncate(mark), tint_rules(id), tint_code(at), tint_rolls(code), TINT_MAX_H, TINT_S_RANGE, TINT_V_RANGE.
- StructureManager.per_map_count(def, a, b), kin_spacing(def), teleport_spots(), teleport_landing_ok(def, q), KIN_RELAX.
- tools: gen_prop_variants.py `--cands <dir>` and rows fan_palm_b/c, joshua_tree_d/e; menu_backdrop.gd `preset=<k>` (0 by default);
  perf_late.gd `tints=0`; captures game/tools/_p85_world_title.gd, _p85_world_tints.gd, _p85_world_teleports.gd.

### The bandit's dynamite (lane BANDIT)

#### Creature JSON (content/enemies/<id>/<id>.json)
| Key | Type | Default | Meaning |
|---|---|---|---|
| `ranged.shot` | string | "" | `"dynamite"`: the kite brain's lob is a stick of dynamite (EnemyManager._throw_dynamite) instead of the spit. |
| `ranged.release_hold` | float s | 0 | After the throw the creature stands in its release pose this long (STATE_ATTACK, the attack strip's release frames), divided by the pace knob. Kite brain only. |
| `ranged.dynamite.speed` | float m/s | ranged.projectile_speed | The stick's flight speed (the spit's arc: flat distance / speed, 0.4..2.0 s). |
| `ranged.dynamite.fuse` | float s | 1.0 | How long it lies on its spot before it blows (creatures' clock). |
| `ranged.dynamite.out_before` | float s | 0.5 | Its spark goes out this long before the blast. |
| `ranged.dynamite.lead` | float share | 0.35 | The aim: the hero's feet + lead x his flat velocity x the flight time. |
| `ranged.dynamite.lead_max` | float m | 2.5 | The most the lead may be. |
| `ranged.dynamite.model` | res path | res://art/props/dynamite_b_stick_red.glb | The stick's model (its first mesh, vertex colours). |
| `ranged.dynamite.scale` | float | 1.0 | The model's size (the kind registered at it; the cactus 0.6: the hero's 0.87 m stick dwarfed a 1.5 m bandit). |
| `ranged.dynamite.halo_r` | float m | 0.2 | The radius the pulse's halo counts from (the long stick's length made a disc of it). |
| `ranged.dynamite.tip` | [x,y,z] | the B stick's tip | The fuse spark's place in the model's own space. |
| `ranged.dynamite.hand` | {up, side, forward} m | {} (0.8 x size up) | Where the stick leaves his hand (muzzle_point's terms: up the painting, toward his right hand, toward the hero). |
| `ranged.dynamite.blast.radius` | float m | ranged.splash | The blast (and its red ring): the hero is hit within radius + 0.4. |
| `ranged.dynamite.blast.knockback` / `lift` | float | 0 / 0 | The hero thrown back (Player.blast) unless he evaded. |
| `ranged.dynamite.blast.push` / `push_radius` | float / share | 0 / 1 | The crowd within radius x push_radius thrown by `push` (EnemyManager.throw_radius: no damage). |
| `ranged.dynamite.blast.shake` / `sfx` | float / sound id | 0.5 / w_lob_boom | The camera's kick and the boom. |
| `attack_throw` (top level or a look entry) | bool | false | The attack strip is a throw: each view's half = wind-up frames (shown winding up) then release frames (shown holding the release). |
| `attack_views` (now also in a look entry) | string | the creature's | As pass 73, per look. |

#### Look recipe (gen_art.py, enemies)
| Key | Type | Default | Meaning |
|---|---|---|---|
| `windup_hint` / `windup_back_hint` | words | "" | A wind-up pose painted before the `aim_hint` pose (cache <sk>_windup_front / _back); needs `aim_hint`. |
| `windup_fit` | float | 1.0 | The wind-up pose's height against the standing figure. |
| `aim_lift` | float share of the cell | 0 | The attack pose raised off the floor line (a throw's hop). |

### The Watch and the bot (lane TOOLS)

#### tools/watch.py (new and changed options)
| Option | Default | Meaning |
|---|---|---|
| `--sound` | off | start with the sound on (pass 85: the sound is OFF by default; `--mute` is still accepted and means off) |
| `--go` | off | start the run at once (no Hero Settings pop-up; the tools' instant start). `--autoquit` implies it |
| (seed `random`) | | now also passes `seed_random=1`, so the pop-up's "Random" box starts ticked |

watch.py writes `tools/dl/watch/setup.json` before each launch (`write_setup`): `{presets: {none, quarter, half, full,
save}: {talent: letters} (save null when no PC save), labels: {name: words}, save_note, refs: [{hero, map, talents,
path, label}] (finished Sim results, newest first)}`.

#### The Godot side (Watch.gd args after `--`)
| Arg | Default | Meaning |
|---|---|---|
| `sound=` | `0` (was 1) | the sound at the start |
| `go=1` | absent | skip the pop-up, start at once (instant start unless `spawn=1`) |
| `spawn=1` | absent | with `go=1`: start down the spawn beam |
| `seed_random=1` | absent | the pop-up's Random box ticked (a new seed every Start Run) |
| `setup=<path>` | absent | the setup file above |
| `analytics=memory` | absent | tests: the record kept in memory and no decision CSV written |

#### New `--actions` words (Watch.gd `_run_actions`; these also run before a run is up)
`setup` (open the pop-up; mid-run = Restart run), `start` (press Start Run), `cancel` (press Cancel), `quit` (close the
window), `setup.hero=<id>`, `setup.look=<code>`, `setup.board=<none|quarter|half|full|save>`, `setup.seed=<n>`,
`setup.speed=<x>`, `setup.limit=<m:ss>`, `setup.bot=<preset|stub>`, `setup.sound=<0|1>`, `setup.slot=<talent>/<rank 1..6>`
(a click on that rank slot).

#### Keys in the window
`R` opens the Hero Settings pop-up (Restart run). In the pop-up: `Enter` = Start Run, `Esc` = Cancel (mid-run only).

#### The run settings (WatchSetup.gd; `Watch.run_settings`)
`{hero, look ("" = his own), map, seed, seed_random, speed, limit (play s, 0 none), death, sound, numbers, unlocks ("all" |
"save"), talents ("grit:AAB,..." | "none"), board_label, bot ("auto" | "stub"), bot_opts ({preset} + every option that
differs from the preset)}`. The record's `header.watch` gained `look` and `run` (the window's run number).

#### The bot (game/tools/bot)
- `bot.goal` gained `name` (the thing's name: a power-up's, a structure's; "" otherwise).
- BotGoals candidates of kind `powerup` and `structure` carry `name`.
- `Bot.summary().powerups` = `{lying (power-ups that lay on the map), goals (power-up goals), reached (walked to and taken)}`.
- BotGoals statics: `powerup_value(eff, c)`, `powerup_why(eff, c)`; the planner's view `c` gained `crowd` (creatures within
  `PU_CROWD_R` m).

#### The plaque (WatchPlaque.gd)
`WatchPlaque.words_of(info) -> {text, sub, tone}`; `Watch.plaque_words()` builds `info` from the screens, the bot's intent,
goal, hold and legs.

#### The Level Editor
Timeline: right-button drag inside the Spawn rows section pans (timeline.js `onPanDown`, `panTo`; `Timeline.panning`).

### Fadeaway's puppet look (lane FADE)

No new JSON key, param, special or stat. FAD-D uses the Puppet method's existing recipe keys (pass 71):
`method: hero_puppet`, `pose_drivers`, `ctl_drivers`, `run_fit`, `fringe_remap`, `puppet{...}` with
`depth_views: ["fd", "back"]` (a per-view choice the job form already offers), plus the look-entry keys `fresh`,
`icon` (FAD-C's badge), `icon_picked`, `title` (FAD-C's cut-out).

## Pass 87: new keys

### The Big Mouth (lane BIGMOUTH)

New keys in a LaserBeam weapon's `params.beam` (the Big Mouth, the Loudmouth). Every block is optional; a key left out
takes the default in `LaserBeam.WINDUP_DEFAULTS` / `PUNCH_DEFAULTS` / `THROAT_DEFAULTS`. A mutation's `params.beam`
merges over them like any other params (deep), so a mutation may carry its own.

| Key | Type | Default | Big Mouth | Loudmouth | Meaning |
|---|---|---|---|---|---|
| `beam.windup.seconds` | float s | 0.24 | 0.24 | 0.24 | the wind-up before each beam; the beam pours at its end. 0 = it pours on the pull. Taken from the cooldown (the cooldown clock starts at the pull), so the time between beams is unchanged |
| `beam.windup.rear` | float rad | 0.35 | 0.35 | 0.35 | how far the lips rear up (tip back) through the wind-up, eased in |
| `beam.windup.gape` | float deg | 36 | 36 | 36 | how far the jaw opens through the wind-up (it snaps to 80 when the beam pours) |
| `beam.windup.swell` | float | 0.1 | 0.1 | 0.1 | how much the mouth swells (an in-breath) through the wind-up, x(1 + swell) |
| `beam.windup.tremble` | float m | 0.03 | 0.03 | 0.03 | a shiver in the last half of the wind-up |
| `beam.punch.back` | float m | 0.36 | 0.36 | 0.45 | the punch back along the aim as the beam leaves |
| `beam.punch.climb` | float rad | 0.2 | 0.2 | 0.2 | the lips kick up with the punch |
| `beam.punch.pop` | float | 0.2 | 0.2 | 0.2 | the mouth swells with the punch, x(1 + pop x punch) |
| `beam.punch.hz` | float Hz | 2.8 | 2.8 | 2.8 | the punch's spring: amp x e^(-decay t) x cos(2 pi hz t); it swings past rest once |
| `beam.punch.decay` | float 1/s | 7.5 | 7.5 | 7.5 | how fast the spring dies (gone in about 0.6 s) |
| `beam.punch.pulse` | float | 0.3 | 0.3 | 0.3 | each pulse while it pours (every 0.28 s) kicks again at this share of the punch; 0 = none |
| `beam.throat.size` | float | 0.9 | 0.9 | 0.9 | the throat flare's size, in the model's own units (it scales with the model) |
| `beam.throat.gain` | float | 1.0 | 1.0 | 1.0 | the flare's brightness |
| `beam.throat.walls` | float | 0.9 | 0.9 | 0.9 | how bright the inside of the throat (its inner skin and floor) glows while it burns (emission energy) |

The glow's colour is always the beam's (`beam.color`, Bad Breath's `breath.color`, else the pink); its core runs to the
beam's core colour. No new stat, special or behaviour; no Level Editor vocabulary needed (the Items tab shows params as
JSON).

Model nodes the code reads (tools/blender_mouth.py; a model without them still works): `Familiar/Mouth` > `Jaw`
(with `Floor`, the floor's inside, lit, and `FloorBack`, its outside), `Upper`, `Cavity` (the throat's inner skin,
lit), `ThroatBack` (its outer skin in the lips' colour x0.55, never lit), `Glow` (the
core, hidden at rest), `Flare` (an empty: the flare's anchor). `Tongue` is gone.

### Facing, evade, barrels (lane FIXES)

No new JSON keys, params, specials or stats.

- `variants.<code>.back_faces` (existing key since pass 46, "right" | "left" | "straight", default the creature's own,
  else "right") now also steers the attack strip's BACK half when the look's `attack_views` is "front_back" (it read
  `front_faces` before): the back wind-up/release mirror the way the back walk does. Set on the Spit Cactus's SC-A:
  `"back_faces": "left"`. The editor's look facing control (if any) needs no change; its help text may say "the back
  set, walk and throw".
- Code constants Garry may want to see (no JSON): BarrelField.COUNT 35 / EXTRA_DARK 2 / COIN_MIN 1 / COIN_MAX 5 /
  COIN_VALUE 1; PickupManager.COIN_DEBT_SHARE 0.4; Player.EVADE_GHOST_TIME 1.0 / HOLD 0.7 / ALPHA 0.5;
  DamageNumbers.EVADE #cdb8ff.
- New gold source id `barrel` (RunAnalytics.GOLD_SOURCES; a black barrel's coins) for anything that lists gold sources
  (dashboard.html, posthog_boards.py, the Sim's gold breakdown legend); unknown ids already show as their id.

### Mummy looks, drivers, gen_art keys (lane MUMMY)

No new game key: the four mummy looks (dust_mummy DM-F..DM-I) use the recipe keys the Level Editor already knows
(creature_pose2: `stills`, `art_prompt`, `pose`, `pose_front`, `stand`, `gait`, `motion`, `anim_negative`, `back_hint`,
`dead_hint`, `death`, `death_frames`, `run_fps`, `outline_frac`, `outline_color`, `back_ref`, `anim_seed`) and the look
entry's `fresh`, plus two gen_art recipe keys (art pipeline only; the game never reads them):

| recipe key (creature look) | type | default | meaning |
|---|---|---|---|
| `remap_hues` | object `{ranges: [[h0, h1], ...], to, sat, min_sat, max_sat}` or a LIST of such objects | absent = off; in a block sat 0.55, min_sat 0.16, max_sat 1.01 | the heroes' key (pass 46) now read for a creature look too (tools/gen_art.py `process`, creature branch): every walk frame (front and back) and every frame of the death clip has the visible pixels whose hue is in `ranges` (degrees) and whose saturation is over `min_sat` and at most `max_sat` sent to hue `to` at `sat` times their saturation, value kept (artkit.remap_hues); a list applies each block in turn. All four mummies carry `[{"ranges": [[56, 75]], "to": 44, "sat": 0.9}, {"ranges": [[75, 330]], "to": 45, "sat": 0.45}]` (the yellow drift back to beige, then the teal/green feet Wan smeared in); DM-H and DM-I add `{"ranges": [[330, 360], [0, 22]], "to": 45, "sat": 0.6, "min_sat": 0.08, "max_sat": 0.55}` (their walks' pink cast back to beige, the saturated red eyes spared by max_sat) |
| `match_still` | bool | false | every walk frame's saturation and value brought to its view's painting (front frames to the front cell, back frames to the back cell; mean and spread over the figure's pixels brighter than value 0.3, hues kept, the dark lines, the outline and a saturated red (the glowing eyes) left alone: gen_art `walk_stats` / `match_walk`). For a walk that came out yellower than its painting or flickers warmer/paler frame to frame. Applied after `remap_hues` |

For the Level Editor lane: creature_pose2 in tools/level_editor/methods.json lists neither; `remap_hues` is already a
recipe row in assets_fields.js (recipeCommon, as an object: the list form is new), `match_still` would be a bool row
("Match the painting's colours"). The record's `info` (the `_ai.json`) carries `remap_hues` and `match_still: true`
when they ran.

Tool arguments (tools/pose_driver.py, additive, defaults unchanged):

| arg | type | default | meaning |
|---|---|---|---|
| `arm_wide=<deg>` | float | unset (the old fixed 0.07 / 0.09 m spread) | with `arms=zombie`: each arm spread that many degrees out from straight ahead |
| `fore_drop=<deg>` | float | unset (= `arm_drop`) | with `arms=zombie`: the forearm's own slope below the horizontal (negative raises it), so the hands rise above the elbows |

meta.json of a driver also records `arm_drop`, `arm_wide`, `fore_drop` (null when not given).

New drivers in tools/dl/drivers/ (12 frames, five views; `_f` = raised for the front view, use as `pose_front`; `_b` =
for the back view, use as `pose`): mummy_shuffle_f/_b, mummy_lurch_f/_b, mummy_bounce_f/_b, mummy_limp_f/_b, and the
body-fitted ones the goofy looks walk on (pose_driver `body=` per view: the front to the round front painting, the back
to the back painting; arms up and out as painted): mummy_bounce_fit_f/_b (DM-H), mummy_limp_fit_f/_b (DM-I). The plain
mummy_bounce/limp drivers made the round mummy slim and crossed its arms (DM-H's first run).

### Solenne's puppet (lane SOL)

No new JSON key, param, special or stat, and no code. SOL-F and SOL-G use the Puppet method's existing recipe keys
(pass 71) and the hero look keys:

- `method: "hero_puppet"`, `pose_drivers` (every view the puppet's OpenPose guide; the side on
  `solenne_puppet_catwalk_walking_farhide`), `ctl_drivers` (`{"back": "solenne_puppet_catwalk_walking_depth"}`),
  `run_fit` (`tools/dl/drivers/solenne_puppet_catwalk_walking/silhouette.json`), `fringe_remap: true`,
  `puppet{...}` with `clip: "catwalk_walking.fbx"` (the job form's Moving clip), `stills: "repaint"`,
  `source: "SOL-B"`, `depth_views: ["back"]`, `words.side` (the arms-out side's own words: her face in profile).
- The look's own paintings: `stills` (`"f"` / `"g"`) for side, fd, bd and their hurts, with `still_keys` naming her own
  `solenne_front`, `solenne_back`, `solenne_cheer`, `solenne_dead`, `solenne_hurt_front`, `solenne_hurt_back`;
  `seed_offset` (1 + crc32(code) % 9973, as the Level Editor writes it), `painter {model: klein, steps: 0}`.
- The words under test, all existing gen_art keys: `pose_hint`, `side_hint`, `back_hint`, `anim_hint`, `pose_motion`,
  `anim_negative` (SOL-G sets the empty ones to "" on purpose, so her top-level words do not apply).
- Look entry keys: `fresh: true`, `note`, `sprite`, `anims`, `strip_cols`, `fps`.

A new guide folder (git-ignored, under tools/dl/drivers): `solenne_puppet_catwalk_walking` (+ `_depth`,
`silhouette.json`) from the puppet, and `solenne_puppet_catwalk_walking_farhide` (a copy whose side view drops the far
arm in the frames where its wrist is above mid-torso; `meta.json` `far_arm_hidden` records which).

### Fadeaway's looks (lane FADE)

No new JSON key, param, special or stat. FAD-E and FAD-F use existing recipe keys:
- `method: "hero_pose5"`, `painter {model: klein, steps: 0}`, `stills` ("e" / "f"), `seed_offset` (2311 / 2377),
  `anim_seed` (FAD-F: 1);
- `art_prompt`, `pose_hint` (FAD-E), `back_hint`, `side_hint` ("" on FAD-F: the hero's own is not used), `anim_hint`,
  `anim_negative`;
- `pose_drivers` {front, fd, side, bd, back: "fadeaway_puppet_run_up"} (a new guide folder under tools/dl/drivers/, made by
  tools/dl/p87/FADE/driver_fix.py from fadeaway_puppet_run; its meta.json records `upright` {neck_up, head, twist,
  clear, report});
- `still_keys` {bd: "fadeaway_<e|f>_bd88"} and on FAD-E also {hurt_back: "fadeaway_e_hurt_back88"} (gen_art's
  hero_still_key already reads still_keys for any still name, hurt_<view> included);
- `run_fit` (the puppet's silhouette.json) and `run_scale` per view (pass 70 key) for the size;
- `fringe_remap: true`;
- look-entry keys `fresh`, `note`, `icon` + `icon_picked` + `title` (FAD-C's badge and cut-out), `sprite`, `anims`,
  `strip_cols`, `fps`.

### The stage screens (lane SUI)

The screens read lane SGAME's keys only (see keys_SGAME.md):
- `timeline_data.stage_list[k]`: `name` (the card's title over its picture, the Results' stage line), `description`
  (the card's body), `difficulty` (the card's coloured line), `length` (the card's "m:ss to the boss"), `boss` (the
  card's boss plate and name; the next stage's requirement "Beat the <boss>"), `hell` (the difficulty line in rock),
  `shot` (the card's picture path; default `res://art/ui/stages/<map>_s<k>.jpg`, k from 1, 972 x 374 box, 2.6 : 1).
- `timeline_data.endless.every` (or a stage's own `endless.every`): the stage clear's "a tougher one every N s".

Tool-only properties (not content):
- `HUD.test_stage_clock` {portal_left, endless, endless_wave, endless_seconds, stage_seconds}: a capture or test pins the
  clock plate's state (as `test_arrows` pins pointers).
- `PortalDialog.seconds_source` (Callable -> float): a capture or test pins the countdown; with it set (or without a
  game) the dialog counts by itself and closes itself at 0 (`expire()`, signal `expired`).
- `StagesScreen.hold_start` / `started`: a tap on an open card records the stage without leaving (touch_audit, tests).

## Pass 88: new keys

### The Big Mouth: one punch, one white glow, a smooth title spin (lane MOUTH)

Changes to a LaserBeam weapon's `params.beam` blocks (the Big Mouth, the Loudmouth). A mutation's `params.beam` still
merges over them deep. No new stat, special or behaviour; no Level Editor vocabulary needed (the Items tab shows params
as JSON).

| Key | Type | Default | Big Mouth | Loudmouth | Meaning |
|---|---|---|---|---|---|
| `beam.punch.pulse` | float | **0.0** (was 0.3) | 0.0 | 0.0 | each pulse while the beam pours (every 0.28 s) kicks the mouth again at this share of the punch; 0 = the punch comes once, as the beam starts (Garry's ask). The pulses still puff at the lips and ring on the sand |
| `beam.throat.rim` | float | 0.35 | 0.35 | 0.35 | NEW: how much of the beam's colour tints the white Glow's edge (0 = pure white). Replaces `throat.size` |
| `beam.throat.gain` | float | 1.0 | 1.0 | 1.0 | the Glow's brightness (white x gain; unshaded, so 1 is full white) |
| `beam.throat.walls` | float | 0.9 | 0.9 | 0.9 | how bright the floor of the mouth (on the jaw) glows while it burns (emission energy), white with a quarter of the beam's colour |
| ~~`beam.throat.size`~~ | | | | | REMOVED (the flare quad it sized is gone) |

Code constants (LaserBeam.gd), not params: `GLOW_DARK` (0.12, 0.008, 0.025: the colour the Glow fades to after the beam),
`GLOW_SHUT_OPEN` 0.12 (the Glow stays, dark, while the jaw is open more than this share of 80 degrees), `REST_PITCH_DEG`
32, `CHEW_DEG` 7, `CHEW_RATE` 2.6, `ORBIT_DEFAULTS` {radius 1.25, height 1.3, bob 0.09, speed 0.9}, `BOB_RATE` 2.4 (named
in pass 88 so the title flies the mouth on the run's numbers; the values are unchanged).

Model nodes the code reads (tools/blender_mouth.py; a model without them still works): `Familiar/Mouth` > `Jaw` (with
`Floor`, lit, and `FloorBack`, both shown only with the Glow), `Upper`, `Glow` (one closed egg filling the throat, hidden
at rest). Gone from the GLB:
`Cavity`, `ThroatBack`, the small core, `Flare`. Parts named `Cavity`, `ThroatBack` or `Tongue` found on a model are
hidden (LaserBeam.HIDDEN_PARTS).

### No knockback on the hero; DM-G and FAD-E played; two shadows (lane TWEAKS)

| Key | Where | Type | Default | Meaning |
|---|---|---|---|---|
| `hero_knockback` | Settings (save.json `settings`), Settings.PROD_LOCKED | bool | false | the hero's knockback from hits. Off: no bite, charge, shot, slam, rumble, stalactite, rocket, boulder, dynamite, tumbleweed, Elite blast, custom attack or Gila eruption moves him (Player.hit_knockback_on). On: every push as before pass 88. Switch "Hero knockback" in Settings' Debug panel (debug mode) and the developer menu; prod holds it off. Run records carry it in `settings.hero_knockback`. |
| `shadow.die_drop` | creature JSON top-level `shadow` or a look's `variants[CODE].shadow` | number, share of the cell, clamped -0.5..0.5 | 0 | how far the death strip sinks down the billboard's plane at its last frame (on top of `shadow.drop`), eased in frame by frame from 0 at the strip's first frame, so a body painted above the cell's foot line lands on its shadow (EnemyManager.die_drop_of / die_sink). For the Level Editor: a number field next to "Shadow drop" (`shadow.die_drop`, step 0.02, help "how far the dead body sinks onto its shadow, share of the cell; 0 = none"); tools/level_editor/vocab.py SHADOW_KEYS could gain `"die_drop": 0.0`. |

### The Stages menu, simpler (lane STAGEMENU)

No new JSON keys. `timeline_data.stage_list[k].difficulty` (pass 87, a free text) now reads as the difficulty WORD:
the Stages menu shows "Difficulty: <word>". Empty = by the stage's place (Easy, Medium, Hard, Extremely Hard); a
number 1..4 = that level. The Level Editor's stage card can keep its text box (help text could say "Easy, Medium,
Hard or Extremely Hard; empty = by the stage's place").

Code: `StagesScreen.difficulty_word(entry, i)`, `difficulty_text`, `level_word(k)`, `boss_met(id)`,
`Save.enemy_met(id)` (seen on the sand or killed). Tool args: `stage_shots.gd crowd=1` (the old creatures back),
`figure=0` (no hero).

### Stakes (Difficulty, Boss) for Spite; prices by power; cheapest first (lane MIRROR)

#### Player stats (StatSheet.PLAYER_DEFAULTS, all 0.0; op "add" a rank; the factor is 1 + the stat; read through
#### core/systems/MirrorDanger.gd; 1 in the arena)
| stat | TextGen name / kind | read by | meaning |
|---|---|---|---|
| `danger_hp` | "enemy HP" / pct | EnemyManager.spawn | regular creatures' HP (everything but a boss or an Elite by its kind; elite-modded and special creatures are regular) |
| `danger_attack` | "enemy attack" / pct | EnemyManager.spawn (contact) + host_of (every hit it throws) | regular creatures' attack |
| `danger_speed` | "enemy speed" / pct | EnemyManager.spawn | regular creatures' walking speed |
| `danger_bounty` | "" / **hidden** | EnemyManager.spawn (XP scale), PickupManager.drop_from (its coin), Game._kill_effects (an elite-modded creature's purse) | regular creatures' XP and coins; never written |
| `boss_danger_hp` | "boss and Elite HP" / pct | EnemyManager.spawn (a boss's HP x it AFTER the pass 83 seconds floor and the DPS scale; an Elite's after its formula) | bosses' and Elites' HP |
| `boss_danger_attack` | "boss and Elite attack" / pct | spawn + host_of | bosses' and Elites' attack |
| `boss_danger_speed` | "boss and Elite speed" / pct | spawn | their walking speed |
| `boss_danger_bounty` | "" / **hidden** | spawn (XP), drop_from (their coin), Game._kill_effects (Elite purse, boss purse, the boss's coins) | their XP and coins; never written |

#### TextGen
- New stat kind **"hidden"**: describe_effect says nothing, _sum_effects skips it, StatSources.listable false.

#### Content
- `content/talents/spite/spite.json` (id kept): name "Stakes", forms "Difficulty" (danger_*) and "Boss" (boss_danger_*),
  each with the four stats above; icons spite_0_icon.png (the skull badge) and spite_1_icon.png (the crown badge).
- Every talent's `cost` re-priced and `order` rewritten in the board's order (see balancing_MIRROR.md).

#### Code
- `TalentDef.first_price()`, `TalentDef.board_before(a, b)`: the board's order (cheaper first rank, then `order`, then id);
  `Registry.talents_list()` sorts by it.
- `MirrorDanger` (static): `is_big(def)`, `stat_for(big, what)`, `factor(big, what)`, `factor_of(def, what)`,
  `factors()`, `scaled_count(v, mult, roll)` (a whole number of coins, the fraction by chance).
- `EnemyManager.mirror_factor(big, what)` (cached with the hero's numbers, `_pstats_mirror`), `_mirror_attack_of(i)`.
- `Save._migrate_stakes()` (once-flag `stakes_v88`; `SPITE_OLD_COST` [500, 900, 1500, 2250, 3250, 4500]),
  `Save.board_note()` / `clear_board_note()` (data key `board_note` {kind "stakes_refund", gold, ranks}); buying a Stakes
  rank marks the once-flag.
- `HomesteadScreen._show_board_note()` / `note_words(n)`: two toasts over the mirror the first time the board opens
  after a refund.

#### Tools
- `tools/sim_batch.py` `PRESET_SKIP = ("spite",)`: the presets (none / quarter / half / full) never buy Stakes (a quarter
  is 11 of 48 ranks, full 42); `TALENT_FORMS["spite"]` 0.
- `game/tools/sim_run.gd`, `difficulty_probe.gd`, `_p85_bandit_probe.gd`: `spite=` default -1 = Stakes left out of a
  board= / mirror= board (0 Difficulty, 1 Boss).
- `tools/level_editor/sim_io.talents()` lists the talents in the board's order and adds `first_price`, `order`,
  `in_presets`.

## Pass 90: new keys

### The bot's ring breakout, the Survivor preset, hunting only the special types (lane BOT)

#### The bot's options (game/tools/bot/Bot.gd; sim_run.gd args, watch.py --bot, the Sim tab's Bot group, WatchSetup)
| key | type | default | meaning |
|---|---|---|---|
| `breakout` | bool | false (true in the "survivor" preset; true when `style` is given as `safety` and `breakout` is not given) | the ring breakout (game/tools/bot/BotBreakout.gd): when a ring of creatures comes up round him, or the crowd has shut him in with open ground past it, he picks the thinnest side and pushes through at full speed, taking the bites, until out by a margin (rules: tools/dl/p90/balancing_BOT.md) |

#### The new preset
| preset | label | values |
|---|---|---|
| `survivor` | Survivor | the Explorer's values with `style: "safety"` and `breakout: true` |

Every preset now names `breakout` (false in sim77, explorer, careless, expert).

#### The run sim's meta.bot (Bot.summary())
- `breakout`: {started, rings, out, timeout} (the pushes started, those a fresh ring started, ended out by the margin,
  ended by the clock); {} with the option off.
- `specials`: {came, killed, life_s, hunted, found, hunted_down, gave_up, coloured}: came / killed / life_s are now the
  special creature TYPES the bot saw (the gear badge: rocketeer = Vulture Raider, saiga_sniper, harpoon_troglodyte),
  watched every 15 frames; `coloured` {came, killed, chests, life_s} is pass 82's tally of the coloured variance
  specials from the recorder's events (no longer hunted). The old top-level `chests` moved into `coloured`.

#### Decision kinds and intents (the Watch's log and <stamp>_decisions.csv)
- kind `breakout`, two entries a push:
  - phase `start`: taken `way:<deg>` (degrees from north, clockwise), offered = the three cheapest ways
    [{id "way:<deg>", name (compass word), score (minus the cost), parts {wall (creatures in the lane), bites (their
    weighted metres), beyond, edge, rock, lean}}], extra `trigger` ("ring" | "surrounded"), `dir_deg`, `dir` (compass
    word), `thick`, `bites`, `beyond`, `n`, `gap_deg`, and `ring_r` (a ring) or `cover` (shut in). Reasons: "a ring of 30
    came up round him 18 m off: out through its thinnest side before it closes, east (1 creature in the way)" /
    "surrounded: 24 creatures round him, 100% of the ways shut, the widest gap 5°; pushes through the thinnest wall,
    north-east (2 creatures in the way)".
  - phase `end`: taken "", extra `trigger`, `why` ("out" | "timeout"), `secs`, `metres`, `hp_lost`. Reasons: "out of the
    ring after 2.1 s and 11 m, 7 HP lost" / "stopped pushing after 3.0 s (14 m), 12 HP lost".
- intent `breakout` while a push is under way (mode_frames["breakout"]).

#### Functions others call
- `Bot.on_revived()`: the Watch's revive; clears the breakout, the goal held, the hold, danger's memory, the dodge.
- `BotGoals.is_special_type(em, i)`: whether creature i is of a special creature type (its type entry's badge is "gear").

### The Watch: Damage taken, chart hover hints, revive at will (lane WATCH)

#### The Watch's command line (Watch.gd args; tools/watch.py)
| key | type | default | meaning |
|---|---|---|---|
| `death=` / `--death` | string | **ask** (was end) | ask: the run pauses at his fall, the panel's down box waits (Revive R, Revive with blast B, End run E), as often as he falls; auto: the Watch stands him up by itself 0.5 s (game time) after the fall; end / ad / keep: the bot answers Down! as before. With `autoquit` (a check that closes itself) "ask" acts as "end". The Level Editor's Sim tab still passes the Sim's own death (end/ad/keep) to its Watch button. |
| `actions=` | list | | new action words: `die` (a check's fall), `revive`, `reviveb` (with the blast), `enddown`, `hurt` / `hpchart` (the tab), `hover=<chart 0..3 \| hurt>/<x share \| t<play s> \| fall>/<y share>` (a pointer for captures) |

#### Keys in the window
| key | when | does |
|---|---|---|
| R | down | Revive (no blast, the crowd as it is). Otherwise R is still Restart run. |
| B | down | Revive with the game's own revive blast |
| E | down | End run (a death) |
| D | always | the HP block's tab: HP & Danger / Damage taken |
| Space, ., L | down | ignored (the run waits for R/B/E) |

#### The run record (RunAnalytics header and events; only from the Watch)
| key | type | meaning |
|---|---|---|
| `header.watch_revives` | int | how often the Watch stood him up (0 / absent: never) |
| `header.watch.revives` | int | the same, beside the Watch's other settings |
| `header.watch.revive_t` | [float] | the play seconds of each revive |
| event `revive`, id `watch` | event | each Watch revive: `n` (its number), `blast` (bool), `down_s` (play seconds he lay down: 0 when paused at once) |
| event `death` | event | unchanged: each fall, as before (so falls and revives pair up) |

`header.revives` (Run.revives_used, the bought ones) is not touched: a Watch revive is never "bought".
analytics/dashboard.html does not show `watch_revives` yet (lane WATCH does not own it): the lead may add
`(r.watch_revives ? ' · revived ' + r.watch_revives + '× in the Watch' : '')` beside its "revives bought" (line ~839).

#### The decision log (Watch panel and <stamp>_decisions.csv)
New kinds the Watch writes: `down` (reason "fell to <who> (<attack>) at m:ss of play; ..."), `revive` (reason
"revived by hand (#n): full health, no blast, the crowd as it is" / "with the revive blast"). Both, and lane BOT's
`breakout`, are never given a real-DPS change.

#### Code (game/tools/watch/)
- WatchData: `hurt` (one record a hit), `read_hurt(damage_log, play_t)`, `hurt_rows(since)`, `sum_hurt`, `hurt_totals`,
  `attack_of(kind, fx)`, `hit_of`, `revives`, `watch_revives()`; falls carry `revived` (the revive's id).
- WatchHurt.gd (new): the Damage taken table (`table()`, `hint_lines()`, `dot_colour()`, `click("sort:<col>" | "win:<s>")`,
  WINDOWS [10, 30, 60]).
- WatchChart: `hover`, `hover_info(p)`, `nearest_index(pts, x)`, `time_at(px)`; series/bands/marks/points take `name`;
  a mark takes `tip` (a dot colour).
- WatchPanel: `set_hurt_tab(on)`, `set_hurt_window(s)`, `check_hover(spec)`, `fall_marks(falls, w)`, the down box.
- Watch: `down_wait`, `watch_revive(blast)`, `end_down()`, `check_fell()`, `watch_handles_death()`, `down_words()`,
  `fatal_words(dlog)`, `revive_count`, `revive_times`, AUTO_REVIVE_S 0.5.

## Pass 95: new keys

### The shot from the held gun's muzzle; the Frisbee's trail per look; the Fire forward debug switch (lane ITEMS)

| Where | Key | Type | Default | Meaning |
|---|---|---|---|---|
| Settings (save `settings`) | `fire_forward` | bool | false (PROD_LOCKED false) | the "Fire forward" debug switch: the Sabre, Spear, Hammer, Frisbee, Tumbleweed and Basketball (and their evolutions) fire along the hero's facing while no creature stands within 75% of their range; Settings' Debug panel row "Fire forward" (switch node `FireForward`), the developer menu row `FireForwardRow` |
| weapon / evolution `params` | `fire_forward` | bool | false (absent) | marks a weapon the switch covers (content: sabre, pike, hammer, frisbee, tumbleweed, basketball, whirlwind, thunder_lance, earthshaker, flying_saucer, dust_devil, slam_dunk); read by core/systems/FireForward.gd; a shared params key in vocab.py / assets_fields.js |
| Frisbee `params.disc.trail` | `style` | "streak" \| "sparks" \| "glow" \| "none" | the look's own (plain streak, razors sparks, saucer glow) | the trail behind the disc (Frisbee.trail_params); `true` = the look's own block, `false` = none |
| | `length` | number (s) | the style's (0.4 / 0.32 / 0.48) | seconds the trail lingers (a point every 0.025 s) |
| | `width` | number (disc radii) | the style's (1.5 / 0.6 / 2.2) | the ribbon's full width in disc radii (so Carry's x1.5 disc trails wider); for sparks the sparks' length |
| | `alpha` | number 0..1 | the style's (0.6 / 0.9 / 0.45) | how solid the trail is at the disc, fading to nothing at the end |
| | `colour` | #RRGGBB | the disc's `emission` lerped toward white (45% / 30% / 20%) | the trail's colour |
| ProjectileManager shot `extra` | `drop_alone` | bool | absent | a ball thrown along the facing (ProjectileEmitter._throw_ball under the switch): with nobody to bounce off at the end of its flight it drops (`_drop_alone`) |
| | `drop_t` | float (s) | absent | the dropping ball's clock (`_tick_dropping`); `ProjectileManager.drops` counts them, `DROP_LIFE` 0.6 s |
| run record (`settings`) | `fire_forward` | bool | | the switch the run played with (RunAnalytics._settings) |

Level Editor: the disc group's `disc.trail` bool row became five typed rows `disc.trail.style/length/width/alpha/colour`
(assets_fields.js); `fire_forward` lives in the shared params keys (vocab.py `PARAMS_KEYS["*"]`, `_PARAMS_SHARED` +
core/systems/FireForward.gd; assets_fields.js `PARAMS_SHARED`). ProjectileEmitter gained `shot_origin(dir)`, `held_tip()`
(no keys: the muzzle is found from the held gun's meshes).

### Passive items climb the rarity ladder to Evolved; power redistributed (lane PASSIVES)

#### Content (content/passives/<id>/<id>.json, passive items only: `line` false, no `evolves_from`)

| key | type | default | meaning |
|---|---|---|---|
| `levels` | list of lists of Effect | | one list a rung: level 1 (the item's rarity), then one rung up each, the last the Evolved rung. The count is the rarity's ladder (common 6, uncommon 5, rare 4, epic 3, legendary 2). tools/passive_ladder.py wrote every rung; the Level Editor flags a longer list (error: unreachable) and a shorter one (warning: the last level repeats) |
| `max_level` | int | derived | the game derives it from the rarity (PassiveDef.apply_ladder in JsonContent.build); the JSON's value is written by the tool and shown by the editor, a different number is ignored (a warning) |
| `repeat_last_level` | bool | true | unchanged: a shorter list repeats its last level up to the top |
| `icon_evolved` | string | `<id>_icon_evolved.png` | the Evolved rung's icon (optional; tools/evolved_icons.py makes it from `<id>_icon.png`: the subject with a white outline on a transparent ground); absent = the base icon on the Evolved rung too |
| `text` / `trade` | string | | unchanged keys; the hand-written lines that named the old numbers were rewritten by the tool (TEXT / TRADE tables in tools/passive_ladder.py) |

No new key on the lines (cards) or the evolved cards.

#### Code (no JSON key)

- `PassiveDef.LADDER` = ["common", "uncommon", "rare", "epic", "legendary"], `PassiveDef.EVOLVED_RUNG` = "evolved".
- `PassiveDef.ladder_levels(rarity)` (static): the levels an item of that rarity climbs (common 6 .. legendary 2; unknown = common).
- `PassiveDef.is_item()`: on the ladder (not a line, not an evolved form); `ladder_top()`; `rung_at(level)` (the rarity at 0 and 1, a rarity up a level, "evolved" at the top and past it); `is_evolved_rung(level)`; `icon_at(level)`; `evolved_icon` (Texture2D); `apply_ladder()`.
- `W.rung_of(def, level)`, `W.is_evolved_rung(def, level)`, `W.icon_at(def, level)`; `W.plate_fill(def, level)` climbs for passive items (level 0 = the rarity's colour; the Evolved rung EVOLVED_FILL, ringed EVOLVED_RING by WPlate).
- `TextGen.rung_name(def, level)` ("Common" .. "Legendary", "Evolved"); `next_level_text` says "Next level (Rare): ..."; `passive_description` says "Level 3 (Rare): ... total." (level 1 plainly).
- `WItem.rung_word(card)` (" · RARE" after PASSIVE on an upgrade card; "" on a new card and on the Evolved rung); the tag "EVOLVED" (W.EMBER) on the Evolved rung; `options()["evolution"]` true there (the card's ember band).
- `CollectionScreen.rung_wash(def, level)`: the level cells' fill (the rung's plate colour washed to the paper; ember for Evolved).
- `Run.phoenix_spent` (int), `Run.phoenix_count()` (the `phoenix_revive` stat rounded: 1, 2 on the feather's Evolved rung); `phoenix_used` stays the "all spent" flag.

#### Level Editor

- assets_fields.js: `LADDER`, `ladderLevels(rarity)`, `rungAt(rarity, level)`, `rungName(rarity, level)`, `onLadder(doc)` (exported); RULES.passive: levels longer than the ladder = error, shorter = warning, max_level != ladder = warning.
- assets.js levelSteps: "<Rung> rung" beside each level of a passive item and a ladder line under the levels.
- vocab.py: `PASSIVE_DEFAULTS.max_level` 6 (a new item is common), `PASSIVE_LADDER` served as `passive_ladder`.

#### Analytics

Unchanged: a passive's level is still an int in every record (`passive` notes, the build snapshots); the top level is now the rarity's ladder count.

### The Cologne and Lighter (Dragon's Breath): a fire-breath weapon, its path and evolution (lane BREATH)

For the Level Editor (vocab.py / assets_fields.js already carry them) and docs/assets_schema.md.

#### Weapon behaviour `FireBreath` (core/behaviors/FireBreath.gd)

A new behaviour primitive: a cone of fire breathed from the hero's face (Player.face_origin) along where he faces, for
`duration` s every `cooldown` s; the cone follows his facing and walks with him; it never aims. Base stats it reads:
`damage` (a tick's damage to a creature standing in the fire), `cooldown`, `amount` (seconds of breath: +seconds_per_amount
per point past the first), `duration` (seconds a breath lasts at amount 1), `range` (the cone's length, m), `area` (x the
cone's width), `fire_damage` / `fire_duration` / `fire_spread` (EnemyManager.ignite on every tick, as the Molotov). A
weapon with it needs no visual scene (no 3D object). `targeting: "forward"` (the words say "where you face").

##### `params.breath` (deep-merged by mutations and an evolution's `final`, as every params key)

| Key | Type | Default | Meaning |
|---|---|---|---|
| `cone_deg` | number | 50 | the cone's width at area 1 (x the `area` stat; 15 at least; 360 = a full ring) |
| `tick` | number | 1.0 | seconds between hits on a creature standing in the fire; the first the moment it is inside |
| `seconds_per_amount` | number | 1.0 | seconds of breath added per point of `amount` past the first (Multishot, the amount buff) |
| `max_seconds` | number | 6.0 | the longest a breath lasts before Held Breath's doubling |
| `wait` | number | 2.0 | with the cooldown ready it waits this long for a creature to stand in the cone; past it, it breathes where he faces if anyone is within `range` at all (aim_index) |
| `knock` | number | 0 | Backdraft: every tick also shoves the creature straight away from the hero with this force (EnemyManager.damage's push: / its mass x knockback_resist x the map's hero_knockback_mult, a boss 0.15) |
| `look.intensity` | number | 1.0 | the flames' size (sqrt) and count (Backdraft 1.5, the Fire Eater 1.8) |
| `still` | {seconds, duration_mult, damage_mult, ring} | absent | Held Breath: present = on. A breath that starts after the hero has stood still AND unhit for `seconds` (Player.still_unhit_seconds) lasts `duration_mult` times as long, every tick deals `damage_mult` times, and `ring` makes it come from all sides (a full ring). A hit that lands breaks the stillness; a breath already burning is never cut |
| `face_up`, `face_forward` | number | 1.45, 0.3 | where the fire starts when the hero has no face_origin (a fake hero in a test); Player's own constants FACE_UP / FACE_FORWARD otherwise |

Shared keys it reads: `fire_blue` (WeaponInstance.blue_fire: the breath, its wash and the creatures it lights burn blue;
Blue Flame, the Fire Eater through its path).

##### `sfx`

| Key | Meaning |
|---|---|
| `fire` | played as a breath starts (`w_breath_start`: the lighter's flick and the whoomp) |
| `loop` | a looping sound run for the breath's length (Audio.play_loop; `w_breath_loop`, `loop: true` in the soundmap; the blue flame x1.12 pitch, an evolution x0.88) |

#### Weapon level effects aimed at the hero (WeaponDef.player_effects, Run._apply_weapon_player_effects)

A weapon's `levels[][]` effect with `"target": "player"` reaches the hero's sheet while the weapon is held, at the levels
reached, under the source `weapon:<id>` (the pause Stats tab names the weapon; StatSources kind "weapon"). As a
mutation's player effects (MutationDef.player_effects). The Fire Eater carries `thorns +8` this way (the Thorn's level
1). Run rebuilds the hero's sheet at once when a weapon with any is added, levelled or evolved.

#### Player (game/player/Player.gd)

- `face_origin(dir) -> Vector3`: FACE_UP (1.45 m) up his 1.9 m painting, FACE_FORWARD (0.3 m) out along `dir`.
- `still_unhit_seconds() -> float`: min(still_seconds(), seconds since the last hit that landed on his star, shield or
  health). `still_seconds` (Steady Hand) is untouched. take_damage's hook `_note_hit_for_still` after the evade.

#### Fx / Telegraphs

- `Fx.breath_jet(at, dir, reach, deg, n, size, blue, ring)`: `n` flame tongues down the cone, an ember now and then; the
  first never thinned by the budget.
- the wash on the sand is Telegraphs.wash (existing), the scorch at the end Telegraphs.scorch (existing).

#### Sounds (content/sounds/soundmap.json)

`w_breath_start` (weapon, -6 dB), `w_breath_loop` (weapon, -12 dB, `loop: true`), both synthesised by
tools/synth_breath_sfx.py into content/sounds/real/.

#### Content

- content/weapons/dragons_breath (Dragon's Breath; rare, weight 6; FireBreath, forward; evolves into fire_eater)
- content/mutations/blue_flame (element, fire; fire_blue), held_breath (volume; breath.still), backdraft (motion; breath.knock 5, look.intensity 1.5)
- content/evolutions/fire_eater (Fire Eater; thorns +8 on the player; final: knock 7, intensity 1.8)

#### Estimates

- `WeaponInstance.BREATH_CATCH` 3.0 (the cone's crowd), `breath_seconds()`, `breath_cone_deg()`, `breath_ticks()`,
  `breath_dps()`, `breath_rows()`; `HeroPower.element_uptime(w)`: a FireBreath weapon's burn counts for
  (breath_seconds + fire_duration) / cooldown of the time (1 for every other weapon).
- `TextGen.breath_words(sheet, params)`; `amount_noun` "seconds of breath".

### Regular creatures despawn out of view; the Magnet power-up as a timed wide pull (lane WORLD)

#### Map: `timeline_data.despawn` (WaveTimeline.despawn, JsonContent.timeline_from_dict; Level Editor Settings → Scaling)
A block; a key left out (the whole block too) plays `WaveTimeline.DESPAWN_DEFAULTS`. `WaveTimeline.despawn_value(key)` is
one number, `despawn_cfg()` the block whole with the defaults filled (what `EnemyManager.set_despawn` takes; the director
hands it over in `_apply_mults`, `{}` = off in the arena).

| key | type | default | meaning |
|---|---|---|---|
| `enabled` | bool | true | the rule runs at all; false = a crowd left behind walks after the hero forever (the game before pass 95) |
| `distance` | number (m) | 40 | how far (flat) from the hero a regular creature must be to despawn |
| `grace` | number (s) | 6 | seconds after its spawn a creature is safe, whatever its distance |
| `every` | number (s) | 0.5 | seconds between two passes over the crowd (never under 0.05) |
| `keep_share` | 0..1 | 0 | the share of the creatures that could go at a check that are spared this time (rolled again at the next check; the manager's own dice, rolled only above 0) |

For docs/waves_schema.md (the lead): "Pass 95: `despawn` {enabled, distance, grace, every, keep_share}: every `every` s a
regular creature (never the boss, an Elite by its kind or modifier, a special type (the gear badge), a coloured special, a
boss's summon while its boss lives, a training dummy, one held by the Gravity Gun, roped, in the air, still rising or
sinking, or dying) farther than `distance` m from the hero, OFF the screen (EnemyManager.refresh_onscreen: the camera's
frustum grown by 1 m; never one you can see, above him or below) and older than `grace` s vanishes with no death, blood,
XP, coins, drops, chest, kill or corpse (EnemyManager.despawn → _free: the live counts drop as for a death, so the row, the
cap and Endless spawn again near the hero)."

#### EnemyManager (new)
- `despawn_cfg: Dictionary`, `set_despawn(cfg)`, `despawn_enabled()`.
- `spawn_at: PackedFloat32Array` (each creature's birth on the despawn clock), `summoned: PackedByteArray` (1 = spawned
  while `force_plain` was up: a boss's brood or a caster's eruption), `age_of(i)`.
- `despawn_kind(i) -> bool` (the "who": alive, not dying, regular; WaveDirector._cull_behind leaves these to the rule),
- `can_despawn(i, ppos) -> bool` (the rule for one creature), `_tick_despawn(delta, ppos) -> int` (the clock, the
  check every `every` s; called at the top of `_physics_process` BEFORE `_rebuild_grid`), `despawn(i) -> bool`.
- Counters: `despawned: int`, `despawned_by: Dictionary {creature id: n}`.

#### WaveDirector
- `_cull_behind()` (the older move-up of anything 30 m behind the hero) skips `em.despawn_kind(i)` creatures while
  `em.despawn_enabled()`; otherwise as before. `_apply_mults` hands the block over: `em.set_despawn({} if Run.arena else
  timeline.despawn_cfg())`.

#### Analytics (RunAnalytics; analytics/SCHEMA.md updated)
- Hook `RunAnalytics.despawned(def)`; per-second row key `despawned` `{creature id: n}`; the header's `crowd` block gains
  `despawned` (total) and `despawned_by`.
- The run sim: `despawned_by` is a cumulative breakdown (game/tools/sim_run.gd, tools/sim_batch.py BREAKDOWNS,
  tools/level_editor/sim_avg.js BREAKDOWNS); the Sim tab draws "Despawned out of view" under Rewards when a sim carries
  it (sim_model.js). The Timeline tab's overlay tooltip was NOT extended (not cheap: sim_batch's overlay + timeline.js).

#### Pickup: `content/pickups/magnet_pulse` (effect `magnet`)
| key | type | value | meaning |
|---|---|---|---|
| `effect` | string | `"magnet"` | the pickup effect (Game.apply_pickup → `_apply_magnet_pickup`; was `vacuum`) |
| `duration` | number (s) | 10 | how long the pull runs (× the Pocket Watch's `powerup_duration`, × the hero's `buff_duration`, as every timed power-up) |
| `params.radius_mult` | number | 2.5 | the reach as a multiple of what the Magnet card gives at its level 1 (its `xp_pull_radius` add: 6 m with lane PASSIVES' ladder, 5 m before → **15 m**; the number follows the card); `PickupManager.magnet_radius(def)` |
| `name` | string | "Magnet" | (was "Magnet Pulse"); `flavour` reworded |

Other pickup effects are untouched; `vacuum` still exists as an effect kind (the Uber Magnet structure is `vacuum_all`;
the arena's button and a boss chest still call `PickupManager.vacuum_all`).

#### PickupManager (new)
- `magnet_item_reach()` (static: the card's level-1 add, 5 m fallback), `magnet_radius(def)` (static).
- `magnet_start(def, seconds) -> float` (starts, or ADDS the seconds to a running one; the entry lives in `Run.timed`
  under the pickup's id with no effects, so the HUD's plate counts it down and it wears off with the others' toast;
  returns the seconds it runs from now), `magnet_running()`, `magnet_left()`.
- `_tick_magnet(delta, hero)` (in the pickups' tick while the hero is up), `magnet_pull(c, r) -> int` (every gem and
  coin lying within r on the magnet arc, never a vacuum gem), `magnet_targets(c, r, n)` (the field lines' spots),
  `_magnet_show()`.
- State and counters: `magnet_id`, `magnet_r`, `magnet_buff: MagnetBuff`, `magnet_pulls`, `magnet_starts`.
- Constants: `MAGNET_RING_EVERY` 0.6 s, `MAGNET_COLOUR`, `MAGNET_ITEM_REACH_FALLBACK` 5, `MAGNET_SFX` "pk_vacuum",
  `MAGNET_LOOK` 1.6 (the field lines look this far past the reach for the next gems).

#### core/systems/MagnetBuff.gd (new, class_name MagnetBuff)
The 2D magnet: `setup(def)`, `follow(hero, targets, left, delta)`, `icon_at()`, `line_point(from, to, k)`; constants
`LINES` 3, `ORBIT_R` 1.3 m, `ORBIT_SPEED` 1.4 rad/s, `HEIGHT` 1.55 m, `BOB` 0.12 m, `ICON_M` 0.8 m, `LINE_COLOUR`,
`DASHES` 8, `SPARK_EVERY` 0.12 s, `BLINK_LAST` 1.5 s; counters `lines_drawn`, `sparks`; `fx` (the game's Fx for the sparks).

#### Game.gd
- `apply_pickup`'s match gains `"magnet"` → `_apply_magnet_pickup(def)` (the toast "MAGNET: gems and coins within R m
  for N s" from the data, a ring at the reach).

#### The bot (game/tools/bot)
- `BotGoals.powerup_value` / `powerup_why`: `"magnet"` priced exactly as `"vacuum"` (by the XP lying); `Bot._vacuum_lying`
  counts a magnet lying as it counted a vacuum.

#### Level Editor
- fields.js: five rows `despawn.enabled|distance|grace|every|keep_share` in the Scaling card (plain dotted keys, no
  `block:`; types bool / number / number / number / percent; grey numbers = the game's defaults).
- selftest_WORLD95.py (the checks above).

### The King's tumbleweed trail and three-stomp jump; the Scorpion Elite's tail sniper (lane BOSS)

All in a creature's `boss.attacks[]` rows (content/bosses, content/enemies), read by EnemyManager's attack runner. The
Level Editor's Enemies tab lists them (tools/level_editor/assets_fields.js ATTACKS / ATTACK_COMMON, vocab.py ATTACKS).

#### Built-in scripts (BossAttackDef.SCRIPTS, 14 -> 16)

##### `stomp` (the Tumbleweed King's; EnemyManager `_stomp_*`)
| key | type | default | meaning |
|---|---|---|---|
| `windup` | s | 1.0 (the King 1.2) | the common wind-up; its `telegraph` "ring" draws the radius round the boss (x 1/pace) |
| `stomps` | int | 3 | landings in one attack |
| `gap` | s | 0.45 | on the ground between a landing and the next hop (x 1/pace); landings come `gap + jump.up + jump.down` apart (1.0 s) |
| `jump` | {height, up, down} | {2.2, 0.35, 0.2} | the hop: how high the figure springs (m, lift_h: the shadow shrinks under it), the rise (s, ease-out) and the fall (s, ease-in) |
| `radius` | m | 6.0 | the hero within radius + 0.5 of the boss's spot is hit at every landing |
| `damage` | | 18 | a landing's damage x stage x hero level x host factors (the old slam's 30 x 0.6) |
| `knockback` | m/s | 6.0 | a landing's push on the hero: a special push (pass 89's share, 0.5 on Red Canyon) |
| `lift` | m | none | when set, the push is a throw up instead (Player.blast), the Hammer Giant's way |
A landing shows Game.stomp_wave (a band racing out over the sand to the radius, the ring's flash, a ring of dust and
clods, a camera kick 1.2) and plays `en_boulder_land`; a ring telegraph shows before every landing (the wind-up's for
the first, then one for the hop, then gap + hop long after each landing). The `slam` script is unchanged.

##### `tail_sniper` (the Dune Scorpion's; EnemyManager `_tail_*`; any creature with a script may carry it)
| key | type | default | meaning |
|---|---|---|---|
| `windup` | s | 1.0 (the Scorpion 0.5) | the stop before the first aim; `telegraph` "none" |
| `count` | int | 3 | beams in one attack, one after the other |
| `gap` | s | 0.6 | frozen between a beam and the next aim, and after the last (x 1/pace) |
| `aim` | s | 1.0 | the Saiga's red lines gather from the muzzle on the hero and follow him this long (x 1/pace) |
| `lock` | s | 0.4 | the locked line holds still before the beam (x 1/pace): the time to step off it |
| `lines` | int | 8 | lines gathering over the aim (SniperFx.line_plan) |
| `cone_deg` | deg | 40 | the cone the lines start from |
| `damage_from` | creature id | "" | a sniper creature whose beam's own base (its `damage_from` chain: the Saiga = the Vulture Raider's rocket 22 x 0.7 = 15.4) x `damage_mult` is the base |
| `damage_mult` | | 2.0 | with `damage_from` |
| `damage` | | 30.8 | the base without `damage_from`; x this creature's stage x hero level x host factors |
| `beam` | {length, width, seconds, knockback, creature_frac, creature_max, push, sparks} | the Saiga's {60, 0.5, 0.15, 5, 0.05, 40, 3, 1.5} | the beam: the hero on its line (half width + 0.4 m) takes the damage and `knockback` as a special push; every creature on it takes `creature_frac` of its max HP (at most `creature_max`) and `push` m sideways |
| `muzzle` | {up, side, forward} | {2.0, 0, -0.4} | where the lines and the beam leave, metres at the def's size (EnemyManager.muzzle_point: up the painting, screen-side, along the aim) |
| `sfx` | {aim, lock, shot} | the creature's sfx, else en_sniper_aim / en_sniper_lock / en_sniper_shot | |
Nothing but a stun, a freeze, a launch, a grab, hiding or death drops the run (`tail_cancels`); a hit does not.
The hero's hit info says `tail beam` (kind ranged, elite true, special_knock true).

#### Common attack key
| key | type | default | meaning |
|---|---|---|---|
| `chance` | 0..1 | none (always) | rolled as the attack's turn comes in the rotation; a miss skips to the next attack (as a range skip does). The Scorpion's tail: 0.7 |

#### The volley's trail (the `tumbleweed_volley` row; ProjectileManager.TUMBLE_TRAIL for any `shot: "tumbleweed"` without one)
| key | type | default | meaning |
|---|---|---|---|
| `trail.style` | "line" / "streak" / "ribbon" / "wisp" / "toon" / "none" | "line" | the tracer look the dust ribbon is laid with in the tracers' ring (tracer_line.gdshader); "none" = pass 45's bead only |
| `trail.colour` | "#RRGGBB" | "#7A5A30" | a warm dark sand (it has to read on the light sand without reading as a shadow: the darker #5C3F1E did) |
| `trail.alpha` | 0..1 | 0.58 | |
| `trail.width` | m | 0.5 | the ribbon's head width |
| `trail.life` | s | 0.75 | a segment's life |
| `trail.puffs` | s | 0.11 | a real puff of dust (Fx.roll_dust) at the ball's foot every this many seconds; 0 = none |
Game.tumbleweed_volley gained a tenth argument `trail: Dictionary = {}` (the row's), EnemyManager hands it when the game
takes it (`_tumbleweed_volley_call`).

#### Diagnostics (EnemyManager / ProjectileManager vars, for tests and tools)
`stomp_runs`, `stomp_lands`, `stomp_hero_hits`, `stomp_last`; `tail_runs`, `tail_shots`, `tail_hero_hits`,
`tail_cancels`, `tail_last`; `tumble_trails`, `tumble_puffs`. Static helpers: `EnemyManager.stomp_jump(row)`,
`stomp_hop_seconds(row)`, `stomp_period(row)`; `ProjectileManager.tumble_trail_cfg(trail)`.

### VACE frame repair in the Level Editor: the frames store, the Frames view, history, cross-look, export (lane VACE)

No new content JSON key: the frames store lives beside the content (tools/dl/frames/), the look entry keeps its keys
(sprite, anims, strip_cols, head, fps, fresh) and an export writes only those (and never `fresh`: an export is Garry's
own choice of frames, not a landing).

#### The store (tools/frames_store.py; tools/dl/frames/<kind>/<id>/<CODE>/<anim>/<view>/)

| file / key | type | meaning |
|---|---|---|
| `group.json` | object | the group: `store_version` (1), `kind, id, code, base, view, key` (the strip key, run_s), `n` (slots), `frame_px`, `fps`, `loop`, `canvas` (the clip's size, 640), `fit` {s, ox, oy, source measured|default, pairs, residual_px, worst_px, canvas}, `outline` {px, color}, `clip` {key, dir, out, full, box, seed, size, prompt, kind control|oneshot|pose|flf|free, match, wan, ctl_sig, ref_hash}, `driver` {name, view, dir, pattern, kind depth|pose, index [per slot]}, `ref_still`, `screen`, `method`, `post` {drop_islands, no_green, remap_hues}, `strip` {file, mtime, size}, `registered` |
| `slot_NN/vNNN.json` | object | a version: `id` (sha1 of the PNG, 16 hex), `label` (`<CODE>-<n>`), `slot`, `space` cell|raw, `source` installed|reroll|vace|copied|repaint, `by` pipeline|ai|human, `time`, `size`, `raw` (true when `vNNN_raw.png` is beside it), `canvas`, `cell_sha1`, `cell_fit` (the fit the cell render used), `shrunk` (the shrink guard's factor when the figure was larger than the cell; absent otherwise), `clip_key`, `clip_frame`, `driver` {name, ctl_sig} (what it was walked on), `wan` (the clip's or the repair's settings), `from` {kind, id, code, base, view, slot, version, label, removed?, resized_from_px?}, `seed`, `prompt`, `model`, `workflow`, `job`, `window` {mode, frames, taken}, `control`, `reference`, `kept`, `free_fill`, `qa` {vision {answer, model, time, note}} |
| `selected.json` | {slots: {N: {id, by, time, pinned, installed_differs?}}} | the chosen version per slot (`installed_differs` cleared when the strip shows the pinned choice again) |
| `staged.json` | {slots: {N: {id, time, why}}} | choices not yet exported; ONE writer: the page's routes and the job landing (jobs._post -> frames_io.stage_versions); vace_repair.py never writes it |
| `exports.json` | [{time, job, strip_sha1, changed, backup} or {time, job, rollback: true, strip_sha1, backup, why, staged_again}] | every export and every rollback |

Flag rules (`frames_store.FLAG_RULES`): jump 1.7, footprint (0.72, 1.35), seam 2.2, silhouette 0.5, empty 0.004;
`footprint` is also raised on a version the shrink guard shrank. Retention (`frames_store.RETENTION`): strip_backups
30 per asset, repair_days 90 (the sheets under tools/dl/frames/_repairs); a version is never deleted while anything
references it (`referenced_ids`: selections, stagings, exports, copies' `from`); raws are kept. `STORE_VERSION = 1`.

Functions added at the resume: `Look(..., override={sprite, anims, strip_cols})`, `Look.in_play`, `StoreLook` (a removed
look from its group.json), `removed_looks`, `rollback_export(kind, id, code, backup, changed, job, why)`,
`prune_strip_backups(dir, keep)`, `prune_repairs(dir, days)`, `referenced_ids(kind, id)`, `delete_version(group, slot,
id)`, `hook_after_save(folder, id, code, counts, cols, sprite, log)`; `export_look` returns `old_entry`,
`strip_sha1_before`, `in_play` (also in the sidecar's info). CLI: `stage <kind> <id> <code> <anim> <view> <slot> <id>`,
`rollback <kind> <id> <code> <backup> [changed json]`.

#### methods.json

Every method carries `repair: {vace: yes|conditional|no, fill: still|cell|none, note}` (the rule the route and the page
read: `frames_io.repair_rule(method)`, `repairable(group)`): ctl and puppet yes; pose and free conditional; proc,
pictures, front_from_picture, recolour no (fill still / cell); icons, drivers, refs no / none.

#### Routes (tools/level_editor/frames_io.py)

GET `/api/frames/<kind>/<id>/<code>` (+ `in_play`, `rule`, `strip_file`, `pinned`), `/.../<anim>/<view>` (+ `repairable` {ok, why,
rule, procedural}, `store_version`, `strip_file`, `clip_dir`, `backups_dir`), `/.../<anim>/<view>/others` (looks carry
`removed`); POST `/.../<anim>/<view>/stage` {slot, version}, `/unstage` {slot?}, `/pin` {slot, version?, pinned},
`/copy` {slot, from {code, slot?, version?}, stage?}, `/repair` {slots, prompt?, seed?, window?, size?, guide?, free_fill?}
(refused with `needs_free_fill` on a procedural animation or a method whose rule says no), `/ask` {slot, version?},
`/delete` {slot, version} (refused with `referenced` while anything refers to it); POST `/api/frames/<kind>/<id>/<code>/export`
{confirm?, force?} (the look in play answers `needs_confirm` until `confirm: true`), `/register` {force?}. Pictures:
`/dl/frames/...` (DL_ROOTS gained "frames"). `stage_versions(...)` and `rollback(...)` are the landing's and the
rollback's entry points for jobs.py.

#### Jobs (tools/level_editor/jobs.py SPECS)

- `frames_repair` (lane comfy): spec {kind, id, code, anim, view, slots [int], prompt, seed, window auto|single|double,
  guide driver|free, free_fill, size, note}; the plan writes `<job>/repair.json` and runs `python tools/vace_repair.py
  --job <it>` with the comfy lock held (env_steps: LOCK_HELD_COMFY, ASSET_JOB_SIDECAR); result.json info.outputs = the
  sheets, info.repair.versions = the versions with `stage_wanted`; the landing (`_frames_repair_post`) stages them:
  `written` {layout "staged", staged [...], skipped [{slot, id, why}]}.
- `frames_export` (lane local): spec {kind, id, code, note, in_play}; runs `python tools/frames_store.py export ...`;
  its result.json entry lands through merge_look WITHOUT `fresh`; a failed merge rolls back at once
  (`written.rollback`); the import job that follows carries `spec.after_export: [job id]` (kept through merged imports)
  and, when it fails, `_rollback_after_import` undoes the export (strip, choices staged again, the old entry merged back
  with pipeline `frames_rollback`; the export card gets `rolled_back` and "rolled back" in its error). A queued export
  waits while a `frames_repair` of the same look is queued / running / waiting (`_frames_export_waits`; the card says held).

#### server.py

`merge_look(kind, id, code, entry, info)`: no `fresh` when `info.pipeline` is `frames_export` or `frames_rollback`.

#### comfy.py

`wan_fun_vace(prompt, ref_name, ctl_names, mask_names, seed, width, height, negative, prefix, shift, steps, cfg, lora,
strength, length)`; models `WAN_VACE_HIGH` / `WAN_VACE_LOW` (wan2.2_fun_vace_{high,low}_noise_14B_fp8_scaled).

#### tools/vace_repair.py

`--kind --id --code --anim --view --slots 3-5,9 [--prompt] [--seed] [--window auto|single|double] [--size] [--steps]
[--cfg] [--shift] [--strength] [--guide driver|free] [--free-fill] [--no-stage] [--dry-run] [--out DIR]` or `--job
<repair.json>` (keys as the flags, plus `free_fill`). Never writes staged.json; refuses a procedural animation without
`--free-fill`; prunes the repair sheets older than 90 days when it runs into the default folder.

#### gen_art.py / gen_ctl.py

One line after every `strip.save`: `frames_store.hook_after_save(folder, id, code, counts, cols, sprite, log)`.

#### The page (frames.js / frames_model.js)

`FramesModel.exportConfirmText(code, total, inPlay, id)`, `whereLine(detail)`; `versionText` says the driver, the shrink
and a removed source; the repair form's "fill freely anyway" checkbox sends `free_fill`; the versions drawer's Delete;
the picker's "removed look" chip; the info block's "Where frames live" line.
