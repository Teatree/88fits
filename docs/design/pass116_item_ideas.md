# Pass 116: new items, weapons and cards (ideas for Garry)

Design only. Nothing here is in the game yet. Numbers are starting points for the Level Editor and BALANCING.md.

## What we have today (short)

- **Weapons in play (22):** Revolver, Boomstick, Tommy Gun, Basketball, Frisbee, Gravity Gun, Guitarra, Hammer,
  Sabre, Spear (`pike`), Sun Scepter, Big Mouth, Zap Beam, Dragon's Breath, Killer Bees, Rocket Pod, Land Mine,
  Lob Grenade (Dynamite), Molotov, Orbit Saws, Salt, Skull Rain, Tumbleweed, Turret Buddy. Hidden: Branding Iron,
  Flare Gun, Peashooter, Poison Dart, Rattlesnake, Throwing Spear.
- **Cards (21 lines, 4 levels, "Risen" when maxed):** the Sun (might), Giant (HP, armour), Tower (attack speed),
  Hydra (amount), Eye (crit), Star (luck), Chariot (move speed), Ghost (evade), Guardian (shield), Temperance (regen),
  Death (lifesteal), Thorn (thorns), Devil (difficulty for reward), Sage (XP), Miner (XP drops), Magnet (pickup reach),
  King (greed), Emperor (armour), Hourglass and Ember (debuff duration), Storm (knockback).
- **Passive items (~45):** Adrenaline, Barrel Rush, Beer, Big Game Hunter, Brimstone Brand, Cake, Cold Snap (freeze),
  Counterpunch, Desperado, Gas Mask, Guillotine (execute), Heavyweight, Hot Springs, Hot Streak, Hush Money, Kindling,
  Last Stand, Loose Change, Magnet, Overkill, Phoenix Feather (revive, one-shot), Pickpocket, Pocket Watch (power-ups),
  Powder Keg, Quickdraw (projectile speed), Reach (area), Ricochet, Siesta, Sinner's Greed, Skedaddle, Snake Oil,
  Steady Hand, Venom, Vulture.

We are already wide. The holes are narrow but real: stats the code has with **no item** that moves them
(`duration`, `rerolls`/`skips`/`banishes`, `cooldown_on_kill`, `homing_turn`), and whole roles the genre treats as
staples (a damage aura, crowd gathering, a pet, chest/weapon-upgrade items).

## Gap table

| Role | Megabonk | Vampire Survivors | Survivor.io / Lonely Survivor | Ours |
|---|---|---|---|---|
| Effect duration | Duration Tome | Spellbinder | Exo-Bracer | stat `duration` exists, **no item** |
| Reroll / skip / banish | (shrines, Chaos Tome) | Skip/Reroll/Banish shop + Tirajisú-style unlocks | ad rerolls | only the Mirror; **no in-run item** |
| Chests / weapon upgrade | Key, Anvil, Credit Card | Treasure chest evolutions | Supply boxes | chests only from Elites/bosses; **nothing to improve them** |
| On-kill cooldown | Battery-style procs | (Candelabrador-like none) | — | stat `cooldown_on_kill`, **no item** |
| Homing / accuracy | Precision Tome | — | Hi-power bullets | stat `homing_turn`, **no item** |
| Damage aura | Aura weapon | Garlic | Force Field | **nothing** (Salt, Breath are not an aura) |
| Gather the crowd | Black hole items | Laurel/Clock Lancet, Pentagram style control | Durian / vacuum | Gravity Gun (Astro's only) |
| Pet / summon | Ghost, minions | Peachone/Ebony Wings | Drones A/B | Turret Buddy, Killer Bees (weapons) |
| Growth / XP | XP Tome | Crown | — | the Sage, Miner (fine) |
| Curse for reward | Cursed Tome | Skull O'Maniac | — | the Devil, Sinner's Greed (fine) |
| Revival | — | Tirajisú | revive ad | Phoenix Feather, Temperance Risen (fine) |
| Luck, crit, armour, regen, move, magnet, gold | many | many | many | covered |

## Passive items (6)

### 1. Speed Loader (on-kill cooldown)
- **Does:** every kill takes 0.4% off the time to every weapon's next shot, up to 4% per second; +0.2% a level, 5 levels.
- **Hole:** `cooldown_on_kill` is in the code with no item. Rewards fighting in the crowd, the genre's core loop.
- **Choice:** great with Tommy Gun, Orbit Saws, Salt (many small kills); poor with Sun Scepter, Big Mouth, Rocket Pod
  (few big shots) and in boss fights (no kills: the boss fight windows thin the crowd). Do not take it for a boss build.
- **Interacts:** Hot Streak (kill might) and Overkill make a "chain kill" build; May's attack speed trait stacks.
- **Ladder:** common to rare; Evolved "Gatling Chamber": the cap rises to 6%.
- **Degenerate risk:** endless crowds in Endless feed it forever. Guard: the per-second cap, and cooldown floors already in WeaponInstance.
- **Build:** content only (stat exists); check TextGen words it.

### 2. Skeleton Key (chests)
- **Does:** a chest offers one more choice to pick from (level 1); level 2: 5% of black barrels hold a small chest; level 3: +10%.
- **Hole:** Megabonk's Key / VS treasure luck: nothing improves chests today, though chests carry evolutions.
- **Choice:** a level-up spent on no power now for better chests later; strong for evolution hunting, weak in a short Sundown run.
- **Interacts:** Barrel Rush, BarrelSpawns (pass 112), specials' sure chests, the Star (luck).
- **Ladder:** 3 levels, single rarity rare; no evolution.
- **Degenerate risk:** barrel chests as an evolution farm. Guard: barrel chests never hold an evolution, a cap of 2 per stage.
- **Build:** small primitive: a `chest_choices` and `barrel_chest_chance` stat read by Chest.gd and BarrelSpawns.gd.

### 3. Blacksmith's Anvil (one-shot weapon upgrade)
- **Does:** `single` like the Phoenix Feather: when picked, your lowest-level weapon gains one level at once. Then gone.
- **Hole:** Megabonk's Anvil. Gives a way out of a weak card screen and helps a late weapon catch up.
- **Choice:** taken now it is +1 level; compare it to a fresh item that keeps growing. Worthless if all weapons are 5.
- **Interacts:** path mutations stay at their slots (it never grants a mutation); helps reach the level 5 + three
  paths needed for an evolution; FtueDynamite's weak card table could show it.
- **Ladder:** off the ladder (`single`).
- **Degenerate risk:** none past one level. Guard: never offered when no weapon is below 5.
- **Build:** small primitive: a pickup-effect hook in Run (one `on_take` action "level_weapon_lowest").

### 4. Coyote Pup (a pet)
- **Does:** a coyote runs at your side and bites the nearest creature for 8 damage every 0.8 s; each level +25% bite, level 4 a second pup.
- **Hole:** Survivor.io drones, VS wings, Megabonk ghost: a companion that is not a weapon slot.
- **Choice:** costs no weapon slot but is weak; a passive slot for safe damage vs a stat that scales everything.
- **Interacts:** takes the hero's might and crit (Sun, Eye); Inflatable May decoy gives it a place to fight;
  Mule Kick's knockback on its bite.
- **Ladder:** common to legendary; Evolved "Pack Leader": three pups, bites howl a short slow.
- **Degenerate risk:** small. Guard: does not count for weapon damage quests, damage from its own stat sheet.
- **Build:** new primitive, reusing Spawner/Turret targeting and the familiar code of the Revolver (`params.familiar`).

### 5. Silver Bullets (homing)
- **Does:** shots turn toward their target (homing 40 degrees a second, +20 a level) and +10% damage to specials and Elites.
- **Hole:** `homing_turn` has no item; on a phone you aim with your feet, so missed shots at a running Saiga Sniper feel bad.
- **Choice:** loved by Revolver, Boomstick, Tommy Gun, Spear; useless to Hammer, Guitarra, Salt, Orbit Saws.
- **Interacts:** Ricochet (bounces find a new target), Quickdraw, Big Game Hunter (stacks vs Elites; cap the sum).
- **Ladder:** 5 levels; Evolved "Pinkerton's Mark": crits on specials always.
- **Degenerate risk:** homing + Ricochet + pierce clearing screens. Guard: homing only on the first flight, not after a bounce.
- **Build:** content only if ProjectileEmitter reads `homing_turn` (it is in PLAYER_DEFAULTS); the special bonus reuses `elite_damage`.

### 6. Saddlebags (a fourth card, with a price)
- **Does:** level-ups show 4 cards instead of 3; but each level needs 8% more XP.
- **Hole:** the choice-quality role (VS's luck-for-more-choices, Megabonk shrines). Earlier a hidden 4th card from luck read
  as a bug (memory "no surprise mechanics"); here it is the item's whole, written rule.
- **Choice:** fewer, better level-ups. Bad when you need raw levels fast (Blood Moon); good to steer towards an evolution.
- **Interacts:** xp_curve, the Sage (offsets the cost), mutation level-ups stay three tables (unchanged).
- **Ladder:** one level, rare.
- **Degenerate risk:** none big; Guard: does not stack with any future card-count source.
- **Build:** small primitive: a `card_choices` stat read by Run.refill_choices / CardPool.

## Weapons (2)

### 1. Smudge Pot (a damage aura)
- **Does:** a ring of sage smoke round the hero, 2.2 m, 6 damage every 0.5 s, slows creatures in it by 15%. Levels: +area, +damage, faster ticks.
- **Hole:** VS Garlic, Survivor.io Force Field, Megabonk Aura: the one weapon type we lack. On a phone it rewards the
  one-thumb skill we have: walking close past the crowd.
- **Choice:** safe and steady, never kills bosses; you trade a slot of reach for a defensive weapon.
- **Paths (3):** Thick Smoke (bigger, stronger slow), Burning Sage (ignite: Kindling, the Ember), Sweet Grass (heals 1 HP per 10 creatures touched, capped).
- **Interacts:** Reach (area), Cold Snap, Counterpunch, Heavyweight; Ironwood / tanky heroes.
- **Evolution:** "Sweat Lodge": a larger ring that pulses a knockback every 3 s.
- **Degenerate risk:** an aura + thorns + regen standing build. Guard: the heal cap; slow does not stack with Shackles past 40%.
- **Build:** new behaviour `Aura` (a cheap one: reuse Zone.gd for the area, ElementCloud.gd for the smoke look).

### 2. Lasso (gather the crowd)
- **Does:** every 4 s throws a loop to the densest group within 9 m, pulls everything inside (3 m) to its centre and holds them 0.8 s, 10 damage.
- **Hole:** gathering is Astro's alone (Gravity Gun); every other hero has no way to bunch creatures for Dynamite, Molotov, Skull Rain.
- **Choice:** almost no damage itself; worth a slot only with area weapons. A poor first weapon.
- **Paths:** Long Rope (range and radius), Hogtie (hold 1.6 s, Elites too), Dally (the pulled crowd takes +20% damage while held).
- **Interacts:** Lob Grenade / Golden Pineapple (lead targeting already predicts crowds: `EnemyManager.predicted_counts`),
  Molotov's pool, Salt patches, Cold Snap.
- **Evolution:** "Stampede Round-up" (the hidden Stampede id could be reused or renamed).
- **Degenerate risk:** holding bosses. Guard: bosses never held, only nudged; specials held half as long.
- **Build:** reuse Vortex.gd / GravityGun pull and Lobber's crowd choice: likely `GravityGun` with new params, else a small `Lasso` behaviour.

## Cards (2)

### 1. The Hermit (duration)
- **Does:** +10% to how long effects last a level (Molotov pools, Salt patches, mines' life, beams, breath, fire, freeze, power-ups' own weapon effects); 4 levels.
- **Hole:** the `duration` stat; Spellbinder / Duration Tome / Exo-Bracer are in every game of the four.
- **Choice:** shines for Molotov, Salt, Land Mine, Zap Beam, Dragon's Breath; near nothing for guns. Overlaps the Hourglass and the Ember
  (debuffs), so you choose "longer field" or "longer poison".
- **Risen ("The Hermit Risen"):** when a field ends it gives one last pulse at full damage.
- **Degenerate risk:** permanent overlapping pools. Guard: every lasting effect keeps its own cap of copies on the ground.
- **Build:** content, but check which behaviours read `duration` (not all may yet); wiring the rest is small code.

### 2. Wheel of Fortune (rerolls and skips)
- **Does:** +1 reroll a level; level 2 and 4 also +1 skip; Risen: once a stage, a banish refunds itself.
- **Hole:** in-run control of the card offer; today only the Upgrade board adds rerolls.
- **Choice:** a card slot of no power for a better build later; strongest early, worthless once your build is set.
  Competes with the Star (luck) for the "better offers" role.
- **Interacts:** the banish rules of pass 58 stay; FtueDynamite's redraw draws normally.
- **Degenerate risk:** rerolling until an evolution. Guard: rerolls do not work on boss chests.
- **Build:** content only (stats `rerolls`, `skips`, `banishes` exist); Risen needs a small hook.

## Recommended build order

1. **The Hermit** and **Speed Loader**: both are content on stats the code already has; cheap and they fill the most
   common genre staples. (Verify which behaviours read `duration` first.)
2. **Smudge Pot**: the biggest missing role (a damage aura), suits the one-thumb walking play, and one new small behaviour
   on Zone.gd unlocks a family of ground weapons.

Then Silver Bullets, Wheel of Fortune, Lasso, then the small-primitive passives (Skeleton Key, Anvil, Saddlebags) and the
Coyote Pup last (most new art and code).

Sources for the other games' rosters: dexerto.com/wikis/megabonk (tomes, items), primagames.com Vampire Survivors
passive item guide, pocketgamer.com/survivor-io/best-gear; Lonely Survivor has no public wiki, its roster follows Survivor.io's.
