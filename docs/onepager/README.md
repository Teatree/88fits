# The 88fits kick-off one pager

A pitch deck in the spirit of `_REFERENCES/BB-KrazyRobots_KickOff_v002.pdf`: a cover and 22 slides, built for 88fits on
26 October 2026 (build 0.91).

| File | What it is |
|---|---|
| `88fits_OnePager.html` | The deck: one self-contained page (pictures inside), 16:9 slides that reflow into one column on a phone. Left and right arrow keys step through the slides; `#s05` in the address jumps to a slide by its id. |
| `88fits_OnePager.pdf` | The same deck printed, one 1600x900 page a slide. |
| `reference_review.md` | What is good, weak and unnecessary in the Krazy Robots deck, and how this deck maps onto it. |
| `benchmark_sources.md` | Every number about other games on the positioning, references and benchmark slides, with its source and date, and how the market scan was done. |
| `src/onepager.html` | The template: the slides, their styles and their words. Edit this, not the output. |
| `src/content.json` | Captions, alt texts and the data behind the generated parts (the action loop, the Venn, the benchmark table, the HUD call-outs). |
| `src/pictures.json` | Which picture fills which slot: source file, crop and size. |
| `img/` | The pictures as the deck uses them (JPEG, or WebP where they keep transparency). |
| `data/` | The frozen data behind the two charts: a recorded phone run (`run.json`) and the pass dates (`velocity.json`). |

## The slides

| No. | Slide | Pictures |
|---|---|---|
| Cover | 88fits, the tagline, the pitch | concept art: the posse against the scorpion swarm |
| 01 | Positioning: pitch, specs, phone, the market Venn, three genre numbers | in-engine horde (portrait, HUD) |
| 02 | In the engine | staged in-engine stills: Sundown swarm, Nightfall, Blood Moon |
| 03 | Pillars (six promises) | in-engine crops, the level-up cards, the Level Editor |
| 04 | References: how it plays (Megabonk, Vampire Survivors, Brotato, Archero, Survivor.io) | the games' store pictures |
| 05 | Visual style: four layers, each beside its reference | our cut-outs, 3D world, icons, Wanted UI; Megabonk, Shop Titans, a wanted poster |
| 06 | Key art: the store page and ads | concept art: the lone Drifter, two wanted posters |
| 07 | Benchmark against Megabonk, Vampire Survivors, Survivor.io, Archero | a strip of each game |
| 08 | The action loop | the cards, a mutation, a chest |
| 09 | A real run: 17 minutes on a Pixel 8 Pro, second by second | chart from the run record |
| 10 | The posse: eight heroes | concept art from the title cut-outs |
| 11 | Stages and bosses | concept art per stage, each boss in the engine |
| 12 | The bestiary | every creature to scale, in the engine |
| 13 | Builds | the icon grid |
| 14 | Controls and HUD, with numbered call-outs | in-engine portrait with the HUD |
| 15 | Game flow and meta loop | eight screens of the current build |
| 16 | Production: velocity, counts, how a pass runs | chart from the pass dates |
| 17 | Art workflow: a 3D model becomes a creature (the Bull Beetle) | the pipeline's own steps |
| 18 | Art workflow: the Puppet (May) | the pipeline's own steps |
| 19 | Art workflow: icons from our own 3D, one creature many looks | the Tommy Gun, the Dune Scorpion, the Bull Beetle |
| 20 | Tools: the Level Editor | its Timeline, a look playing, an art request |
| 21 | Tools: the Watch, the run sim, telemetry, ship.sh | their screens |
| 22 | Summary and proposed next steps | the cover's painting |

## Rebuild

```
python tools/make_onepager.py          # pictures (only the changed ones) + the HTML
python tools/make_onepager.py --pdf    # the same, then the PDF through headless Edge
python tools/make_onepager.py --force  # every picture made again from its source
```

The sources of the pictures are the game's own art, the design bible's captures (`docs/design/img/`), the art and tool
explainers (`docs/puppet/`, `docs/spider/`) and the one pager's own work in `tools/dl/onepager/` (git-ignored): the
in-engine stills from `game/tools/marketing_shots.gd` (`shots/`), the concept art painted with Flux.2 Klein from the
heroes' title cut-outs (`concept/`, prompts and seeds in its `manifest.json`), the reference games' store pictures and
the market facts (`refs/`), and the tooling screenshots (`tools/`). The finished pictures are kept in `img/`, so the deck
rebuilds without `tools/dl`.

The in-engine stills are staged: the crowd, the camera and the moment are set up and frozen, every weapon fires once,
and the scorpion swarm's glowing specials use a roster-row override (the Lesser Scorpion has no special in today's map).
Nothing is painted over. Pictures of other games come from their store pages and wikis and are there only to name what
88fits borrows from each; they stay labelled as theirs, which suits an internal kick-off but not public marketing.
