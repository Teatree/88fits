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
