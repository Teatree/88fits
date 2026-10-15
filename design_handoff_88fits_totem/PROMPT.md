# Prompt for Claude Code

Copy `design_handoff_88fits_totem/` into the repo root first, then paste this.

---

Replace the Totem Pole gift screen in 88fits with the "Spirit Pole" design in `design_handoff_88fits_totem/`.

Read, in this order:
1. `design_handoff_88fits_totem/README.md` — the spec: layout in px, tokens, the roll gauge, states, motion with timings, the data each element reads.
2. `design_handoff_88fits_totem/screens/01-totem-offer.png`, `02-totem-offer-pressed.png`, `03-gift-three-rolls.png` — the visual targets at 1080×1920. Look at all three before writing code.
3. `design_handoff_88fits_totem/design/88fits Totem.dc.html` — the design file. Direction **1b** is the chosen one; ignore 1a and 1c. Grep it for any value the README or PNGs leave ambiguous; every style is inline on the element. Do not port the HTML.
4. `design_handoff_88fits_totem/reference/` — today's screen and the pole in the world, for context only.

Then find in our codebase: the scene/script that opens today's totem gift screen, the data it receives (the three gifts, their ranges and rolls), the toast system, the in-world pole node (ring, pie, grey-out), and the Wanted UI kit components already built from the earlier handoff (slab button, paper panel nine-slice, item plate, modal dim). Write a short plan mapping the README's elements to the nodes you will build or reuse, and show it to me before changing anything.

Rules:
- Match the PNGs pixel-close at 1080×1920: positions, sizes, hex colours, fonts (Alfa Slab One, Bitter), 5/6 px ink borders, 8 px hard shadows, no blur, no gradients.
- Reuse the kit: the tag is the kit's paper panel; the segment plate is the kit's item plate in rock `#B4472B` at 300 px with the carved inset shadow; the dim is the kit's modal dim. Build the notch gauge and the nail once as components.
- Each gift row is one tap target spanning both the segment and its tag. No buttons, no skip, no reroll, no close; taps outside the rows do nothing.
- The roll gauge shows thirds of the gift's own range with both ends written, exactly as the README's table; the number turns `#A8792A` only on a top-third roll. Never show rarity colours, stars or seals on this screen.
- Spirit icons: use the four placeholder faces in `design/totem/` for Le-loo, Chet-woot, Frog and Se-sook; for the other seven, render the empty-plate fallback from the README and wire every spirit's icon to a texture slot our artists can fill (256 px square).
- Copy exactly: label "★ TOTEM {n} OF {total} ★" (or "★ {n}TH TOTEM ★" when the total is unknown), the spirit line as "Word, the Animal" (word only when there is no animal), amounts formatted with sign and unit.
- Motion and timings as the README's Open / Press / Close sections, using tweens; the face flies to the existing toast slot and the toast reads "{Word} · {amount} {stat}".
- Keep gameplay untouched: gift weights, ranges, the 3-second charge, the 1-second safety after the pick, the pole greying out, analytics events.
- Top 130 px stay empty on this screen; the layout is top-anchored so taller phones add space below the base.

When done, run the game to a pole, capture the screen at 1080×1920 in idle and pressed states, and compare against the PNGs side by side. List every difference and why it remains.
