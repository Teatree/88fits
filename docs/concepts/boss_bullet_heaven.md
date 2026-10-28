# Boss "bullet heaven" attacks: proposals (pass 111, 2026-10-28)

Garry: "Each of the Bosses needs a Bullet Heaven type of attack. Those attacks are supposed to be rare and powerful. And while
the boss is doing them it should be more challenging for Player to damage the boss until the attack is done. This is supposed
to be accompanied by impressive visuals."

Proposals only; nothing is built yet. Each boss gets two options to choose from.

## Rules all of them share
- **Rare.** Once per fight on the first try: the first time the boss drops below 60% HP. Then at most once every 45 s.
  - It never comes in the first 15 s of the fight.
  - Content keys: `phase_at` 0.6, `cooldown` 45.
- **Hard to hurt while it lasts.** The boss takes 80% less damage (`guard` 0.8) for the attack's 6–9 s.
  - A visible shell shows it (a glowing aura, a shield of tumbleweeds or scales, a fire pillar).
  - Hits on it spark and show small grey numbers, so the player can tell their damage is being blocked.
- **A payoff.** When the attack ends the boss is "spent" for 2.5 s: it takes +50% damage and stands still. The player learns
  to survive the pattern and then punish.
- **A clear tell (1.2–1.5 s).**
  - A banner word across the screen (like the EVADE word).
  - The music ducks.
  - The ground darkens in a ring round the boss, and a loud wind-up sound plays.
  - The creature crowd is held back: the boss-fight window's rows pause for the attack, so the screen is the pattern and the
    player.
- **Projectiles built for weaving.**
  - Slow: 2.5–4 m/s, against the hero's ~5.
  - Big and bright, with a thick ink outline.
  - Drawn in the never-tinted class, so they read under Nightfall and Blood Moon.
  - One MultiMesh per attack, so a few hundred bullets stay cheap on a phone.
  - Each bullet deals one small fixed hit (about 12% of the hero's max HP), so danger comes from density, never from one-shots.
- **Code needed.** One reusable primitive: a boss attack kind `"pattern"` in content/boss_attacks/<id>.
  - Emitters: `spiral`, `ring`, `fan`, `sweep`, `wall`, each with count, speed, rate, spin, gap and duration.
  - The attack's `guard` and `spent`.
  - After that, every pattern below is content, tuned in the Level Editor's Boss attacks tab.

## The Tumbleweed King (Sundown)
**A. Royal Dust Devil** (recommended)
- **Wind-up:** the King spins up on the spot into a sand tornado as tall as three heroes. His crown shines through the dust.
- **Pattern:** for 8 s, three spiral arms of small burning tumbleweeds turn slowly outwards. The arms reverse direction halfway
  through, so the safe lanes change.
- **Guard:** the tornado is the shield; shots hitting it throw sand sparks.
- **End:** the tornado collapses and the King lies dizzy for 2.5 s, with stars circling over the crown.
- **Visuals:** a swirling sand cylinder (a scrolling noise shader on a cone), dust carried across the screen, the tumbleweeds
  trailing ember sparks.

**B. Royal Decree**
- **Wind-up:** the King slams down and unrolls a giant scroll (a 2.5D painting).
- **Pattern:** four rings of thorny burrs roll outwards, each with a gap in a different place. The player has to read each ring
  and step through its gap.
- **Guard:** a golden glow round the King while he reads the decree.

## Gila Grande (Nightfall)
**A. Venom Monsoon** (recommended)
- **Wind-up:** she rears up and her throat sac swells and glows purple.
- **Pattern:** for 7 s she sprays big, slow, wobbling venom blobs in a fan that sweeps left and right like a garden sprinkler.
  Every second sweep adds a second, offset fan.
- **Guard:** her scales glow like armour.
- **Optional twist:** the throat sac is a weak spot that takes full damage. Popping it ends the attack early.
- **End:** she collapses for 2.5 s, panting.
- **Visuals:** purple blobs leave little poison puddles that fade in 2 s. The night filter makes the purple glow pop.

**B. Needle Storm**
- **Pattern:** she burrows. The ground cracks in a cross, and lines of cactus needles rise from the cracks and slide slowly
  across the arena like moving walls, each with a gap.
- **Guard:** she is underground and can't be hit at all. The attack is 6 s, the shortest of the set, to make up for it.
- **End:** she erupts where the walls met and stays spent for 2.5 s.

## The Brander (Blood Moon)
**A. Hellbrand Mandala** (recommended)
- **Wind-up:** he drives his branding iron into the ground. A glowing brand sigil a dozen metres across burns into the red
  sand.
- **Pattern:** for 9 s, slow branded fireballs spin out in a rose-curve pattern (petals that open and close). Every 3 s the
  mandala turns a fifth of a turn.
- **Guard:** he stands inside a pillar of fire.
- **Finale:** the last second pulls every fireball still flying back in towards the centre, so the player must not stand
  between a fireball and him.
- **End:** the pillar gutters out and the iron cools and smokes. He is spent for 2.5 s.
- **Visuals:** the sigil is an additive decal that brightens as it fills. Fireballs leave short smoke trails. The red filter
  turns the sand darker and the bullets brighter.

**B. Forge Rain**
- **Wind-up:** he raises the iron to the blood moon.
- **Pattern:** molten drops fall in an advancing grid across the arena, with a warning circle 0.8 s before each drop lands.
  Under the grid, rows of slow sparks sweep sideways.
- **Guard:** a shower of embers round him.

## Next steps if one is picked
1. Build the `"pattern"` boss attack primitive (the emitters, guard, spent, tell; a Level Editor form).
2. Make the King's Dust Devil as content to prove it.
3. Tune: probe a fight with tools/_p110_BOSS_fight_probe.gd.
4. Add the visuals: tornado, sigil, sac glow.
