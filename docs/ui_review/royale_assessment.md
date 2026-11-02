# "Royale, refined": what would change, and what to leave out (2026-11-02, after pass 121)

Source: `Design critique and verdict.zip` (design_handoff_88fits_royale: README.md, PROMPT.md, the mock
`88fits Revamp.dc.html`, round 2 turns 6-10). Not implemented; this is the lead's read for Garry. Every change is
judged on one question first: does it make the run clearer to play, or only change how the game feels to use?

## The proposal in one paragraph

A full reskin from today's "Wanted" kit (aged paper, ink, brass) to a Clash Royale-style kit: navy outlines on
everything, slate panels with a hard navy base, glossy two-tone buttons whose colour says what they do (gold = happens
now, green = buys, blue = opens something, slate = the rest, red = danger), black see-through plates for run info, rarity
frames on item icons (Evolved = black face with a rainbow rim), the Ultra (wood-type slab) and Rubik fonts, a flat
sunset-and-mesas backdrop behind the menus. Four screens change layout (Main menu, a new Heroes screen, a Hero details
pop-up, Upgrade); every other screen keeps its layout and copy and changes only its chrome.

## A. Take as it is (clear wins)

1. **HUD on black plates** (level, clock, gold, buffs, BOSS / ELITE / PORTAL pointers): white type on 56% black reads on
   bright sand, on the blue Nightfall and on the red Blood Moon alike; today's paper plates compete with the sand.
   Kill count as bare outlined type, pause the only "button". Gameplay clarity: better.
2. **Boss name and bar** (gold name with an edge, a thick red bar on a black trough): easier to read mid-fight. Better.
3. **Evolved items: black face, rainbow rim** in the HUD, the build list and the cards: an evolution is visible at a
   glance. Better.
4. **Button colours mean something** (gold now, green buys, blue opens, red danger) and one shared Confirm modal.
   UX: better; nothing in the run gets harder to read.
5. **"per Level", never "/ LV"**. Clearer, trivial.
6. **Shop**: green price button, an offer you cannot afford keeps its card and text with a grey button and "25 short"
   in red. Clearer than today's small "166 short".
7. **Stranger**: THE PRICE as a bar whose lost part is red-hatched (95 -> 81). Shows the cost instead of telling it. Better.
8. **Upgrade board fits on one screen** (2x4 tiles, no scrolling), each option's effect line on the tile, the refund
   line by TAKE IT ALL BACK. More information with fewer taps. Better (see B4 for the pips).
9. **Stages: a START button on every open card** and the locked card saying what opens it. The card being a button is
   no longer a guess. Better.
10. **Collection**: unfound items as dark silhouettes with their quest and a progress bar. Better.
11. **Level-up, chest and mutation cards** as slate cards, same layout, full text, the touched card lit with rays
    behind its icon. Neutral to slightly better (dark cards over the dimmed run have more contrast than paper over a
    paper-coloured desert). Keep today's one-tap pick: no extra confirm tap.
12. **Results, Pause, Down!, Stage clear, Totem, Settings, Consent, Survey**: chrome only, same content. Neutral.

## B. Take, but changed

1. **Rarity frames: passive items only.** Weapons and Cards have no rarity in the game; the mock gives the Golden
   Revolver a Legendary rim and Orbit Saws "Weapon Legendary". A fake rarity on a weapon teaches the player a rule
   that does not exist. Weapons and Cards: the Common frame (or a kind colour), Evolved = rainbow as above. Rarity
   colours in the HUD row are also the noisiest part of the new HUD: try it on the phone before keeping it there.
2. **Fonts**: Ultra for titles, names, big numbers and buttons; **Rubik bold for tags and small labels**, not Ultra at
   18 px with a 3 px edge (a fat slab with a thick outline fills in at that size on a phone).
3. **Main menu backdrop**: keep the painted title scene (pass 83/119, the map's own sand, props and hero) or paint a
   sunset version of it. The flat vector sunset with mesa silhouettes is generic and throws away the world the game
   already has. The new chrome (wordmark, START, tab bar) goes over it.
4. **Upgrade rank pips**: keep the chosen option's icon in each filled pip (today) instead of the option's initial
   letter on gold ("S", "P"); an initial is a code to learn.
5. **Main menu tab bar**: HEROES, BATTLE (selected), UPGRADE, COLLECTIONS, **without the locked STORE tab** (there is no
   store; a dead tab teaches players to ignore the bar). Settings behind the ≡ button as in the mock.
6. **Run history stays**: today's title line "Red Canyon · best 16:35 · Lv 32 · stage 3 · 4,864 kills" disappears in the
   mock. The handoff's own rule says nothing informational may be removed: move it to the Stages screen's header.
7. **Gold is used for too many things** (actions, coins, titles, stars, Legendary, EXP numbers): "gold = do it now"
   loses its force when every title is gold. Cream titles (as the mock's main menu already does) with gold kept for
   actions, coins and Legendary.
8. **Heroes screen and Hero details pop-up**: take them (the hero, his trait, his five items with full text, the skins
   strip and the hero grid on one screen is clearer than the drawer plus the Wanted sheet), with the real looks and
   icons from data, and the favourite kept (the README keeps it; one caption says it was dropped).

## C. Leave out (criticisms)

1. **The Boot screen's gold loading bar on a sunset.** Pass 118-120 gave the loading screen its saloon wallpaper, the
   punching OUTLAW / SURVIVORS plate and the revolver-cylinder wipe into the run, at your request, with no bar. Keep those.
2. **Empty flanks "reserved for live-ops"**: there is no live-ops; empty space on purpose is fine, but nothing should be
   built for it.
3. **"GET UP · WATCH AN AD"** stays a stand-in with no ad behind it (true today too); the reskin should not dress it up
   as finished. Rename it or leave it as is until ads exist.
4. **The mock's numbers** (Stage 3 "12:00 to the boss", upgrade effects "harder waves, more gold", prices, Option A/B
   tiles): all from data, never from the mock (the README says so; listed here because they are wrong in the pictures).
5. **Losing the western identity wholesale.** Paper, ink and brass are what make today's screens read "Wanted"; the
   Royale kit keeps the west only through the slab font and the sunset. It does fit the game's Clash-style painted
   sprites better than paper does, and the genre leaders (Survivor.io, Archero) look like this. That is a taste call
   for you, not a clarity one; my advice is to keep a few western pieces the mock does not cover rather
   than flatten everything to slate.

(The western pieces meant here are the ones in D1: the paper Bounty posters, kept as props in the world.)

## D. Not covered by the mock (needs a decision before building)

1. The in-run **Bounty posters** (paper Wanted posters: they are the game's own idea; I would keep them paper, as props
   in the world, not UI chrome).
2. The **War Drum** and **Grindstone** moments, the **boss chest's** closed/opening states, the chest reel (slot
   machine), toasts, banners, hint bubbles, TAP TO GO (the README keeps its bare text), the hero's **Wanted-poster
   sheet** (replaced by the Heroes screen?), the **Spirit Pole** frame.
3. The debug arena and developer menu stay as they are (the README agrees).

## E. How it would be built

- Today every screen is already built from one kit (ui/wanted/: W tokens, WButton, WPlate, WCard/WItem, WModal, WTabs,
  WSlider, WSwitch...), which is exactly what the handoff asks for: the tokens and components change first, most
  screens follow without being touched.
- Behind a **theme switch** (like today's menu_style painted/live) so you can compare Wanted and Royale on the phone and
  go back; Royale default only when you say so.
- Order: (1) tokens, fonts, components; (2) HUD, level-up, chest (the in-run screens, where the clarity gains are),
  captured beside the mock for you; (3) Main menu, Heroes, Hero details, Upgrade (the four new layouts); (4) the rest's
  chrome. touch_audit and the UI tests re-pinned as it goes. Roughly three to four passes.
- Godot notes: the hard navy base, two-tone fills and lips are StyleBoxFlat work; the radial rarity fills, the rainbow
  rim and the rays are a small shader each; Ultra and Rubik are free (OFL) Google fonts.
