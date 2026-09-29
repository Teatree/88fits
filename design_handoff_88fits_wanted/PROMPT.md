# Prompt for Claude Code

Copy the `design_handoff_88fits_wanted/` folder into the repo root first, then paste this.

---

Replace the whole in-game UI of 88fits with the "Wanted" design in `design_handoff_88fits_wanted/`.

Read, in this order:
1. `design_handoff_88fits_wanted/README.md` — tokens, components, every screen, interactions, state, layout rules. Treat it as the spec.
2. `design_handoff_88fits_wanted/screens/*.png` — the visual target for each screen, 1080×1920. Look at every one before writing code.
3. `design_handoff_88fits_wanted/design/88fits Wanted.dc.html` — the source of every exact value (colour, size, spacing, copy). Grep it when the README or a PNG leaves a value ambiguous; every style is inline on the element. Do not port this HTML; it is a reference.

Then read our codebase and find: the UI framework/scene system, where each of the 17 current screens lives, the font pipeline, the sprite/nine-slice pipeline, and the game state each screen reads. Write a short plan mapping each screen in the README to the file(s) you will change or create, and list the components you will build once and reuse (the README's "build once" list). Show me the plan before you change anything.

Rules for the implementation:
- Match the PNGs pixel-close at 1080×1920: colours by hex, fonts and sizes as listed, borders and hard shadows as listed, no corner radius on panels, no blur anywhere, no gradients except the two dims and the title wash.
- Build the components first (icon plate, wax seal, item card, slab button, tab strip, slider, switch, two-way choice, list row, toast, banner, edge pointer, bar, menu header, modal header), then compose the screens from them. No screen may draw its own version of a component.
- Kind is shown by plate colour and one word; rarity only by the wax seal; level only by stars (weapons /8, passives /5) or notches (ranks /3) or rivets (paths /3). No kind tags, level chips or flavour lines on in-run cards.
- Merge and remove exactly what the README's flow says: Play setup into the Title; "tap to continue" into the gate animation; Pause · Options down to sound, music, shake, abandon; every debug element (title arena entry, version label, debug buttons on modals, dbg revive, hit log, copy log, pause log, hidden collection, save path) into one developer menu opened by holding the Settings version label for 2 s. The arena itself stays as it is.
- HUD: XP rail, LV, timer, gold, pause, held-item slots (no empty or locked slots), toast queue, banner, boss name+bar only while a boss is alive, edge pointers, hero bars, joystick. Remove stage name and kill/alive counters.
- Numbers: thousands separators everywhere, "Lv 14" not "L14", mm:ss timers.
- Keep the placeholders as placeholders: where the PNG shows a striped dashed box (hero cut-outs, the Stranger, strongbox, portal, chest art) use a same-size stand-in sprite with the label from the mock, wired to an asset slot our artists can fill.
- Use the fonts Alfa Slab One and Bitter (Google Fonts, OFL); add them to the font pipeline.
- Keep all existing gameplay logic, save format and analytics events. This is a UI replacement only.

Work screen by screen in the README's order (components → 06 HUD → 07 Level-up → 09 gate → 08, 10, 11, 12 → 13 → 14, 15, 16 → 01/02 → 03 → 04 → 05 → 17). After each screen, render it at 1080×1920 and compare against its PNG side by side; fix differences before moving on. At the end, produce a checklist of every screen with what still differs from the PNG and why.
