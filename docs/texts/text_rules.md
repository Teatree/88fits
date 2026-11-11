# How item texts are written

Garry's rules (pass 138 and his notes of 2026-11-10), for whoever writes a weapon, mutation, evolution, item or Card
text next. Where a text lives and how to add one: the skill `game-texts` (`.claude/skills/game-texts/SKILL.md`).

## The words

1. **One sentence, two at most**, about the main effect. Secondary clauses go. A full stop at the end.
2. **Numbers as digits**, never words: "Pick up 2 more", "Every 5th pull fires 3 shots in a row", "×2 damage",
   never "two", "fifth", "twice", "double". An item's own count is a digit even at 1 ("Fires 1 shot").
3. **The game's own words for what happens**, the same words the Outlaw's stats use on the pause screen
   (`stat.<id>.name`): **deal** damage ("for 20 damage", "deals 18 damage", "deal −30% damage"), **knock back**
   ("knock back enemies harder", never "throw enemies harder" or "shove"), **crit chance**, **range**, **cooldown**,
   **area of effect**, **pierce**, **move speed**, **max HP**. Enemies are **enemies**, never creatures. The player is
   **you**, never his or her.
4. **Every weapon's description says the damage it deals** (`{damage}`, a variable, never a number in the row): a hit,
   "a sting", "a shot", "each" (a burst), or "a second" for what ticks (a black hole). An evolution says it where it
   fits. Choosing between weapons on one screen needs it.
5. **A mutation says what changes, in few words**, without repeating what the weapon does: the gain first, the price
   after "but" ("Pick up 2 more, but deal −30% damage.", "Thrown enemies deal a 40% wider blast and knock back
   enemies harder.").
6. **A chance** reads "has a 15% chance of ..." ("Hits have a 3% chance of freezing an enemy for 1 s.").
7. **Who a weapon hits**: "an enemy" (weapons aim where you face since pass 136); never promise "the strongest" or
   "the nearest" unless the rule really picks it.
8. Plain verbs: "Creates a Black Hole", not "Lobs a black hole"; "explodes", not "blows".

## The numbers

9. **Units**: a number and its unit with one space: `2 m`, `14 m`, `3 s`; `30%`, `60°`, `×2` glued. (Garry typed "2m"
   and "14m" in his notes; the game writes "2 m" everywhere, his own rows too, so both his texts carry the space.) The
   kit never breaks a line between a number and its unit (WText keeps "14 m" together).
10. **An item's own description shows lengths in whole metres**: ranges, radii, blasts, areas ("2 m", never "1.9 m";
    TextGen._m). A balance number a tenth off a whole is rounded in the JSON too (the Gravity Gun's blast 1.9 -> 2.0);
    a length that is secondary to the weapon is left out rather than rounded far (the Hammer's, the rockets', the
    Sun Scepter's and the Salt's blast or patch size).
11. **Times keep one decimal only when they have one**: "every 6 s", "every 2.2 s" (TextGen._sec).
12. **Damage is a whole number** (TextGen._dmg).
13. **Upgrade rows keep their decimals** (a level-up's "Blast radius 2.4 m → 2.9 m", "Cooldown 1.10 s → 0.95 s"): there
    the change is the point.

## The look

14. An evolution's own line comes first; under it, on its own line, the mutations note ("All your mutations still
    apply." / "... and get stronger.") in the **note face**: Rubik Italic, smaller, faded blue (`R.NOTE_*`; `W.desc_text`
    sets it apart by itself, `W.note_text` for a note on its own).
15. Numbers are set bold in the description face by the kit (WText.bold_numbers): write them as plain digits.

## Never

- Change a text Garry wrote (the Basketball, Big Mouth, Boomstick and Dragon's Breath families, commit c1d5f178, and
  any row `git log -p` shows him editing): list a suggestion instead. (Pass 143: he asked the Boomstick and Dragon's
  Breath families to say their damage, and gave the Skull Rain's, the Dynamite's and Cold Snap's sentences; those rows
  are his new texts. The Big Mouth's row still says no damage: a suggestion for him.)
- Put a number in a row the code can hand in as a variable, or glue sentences after an item's own row.
