# Pass 138: every text I changed, and how

Written for Garry. Lane TEXTS, 2026-11-10. Tables made by `tools/dl/p138/TEXTS/make_md.py` from the diffs, so no change is missed.

## 1. The approach (your rules, as I read them from commit c1d5f178)

- One sentence, two at most, about the main effect. Secondary clauses go ("a hit breaks the stillness", "at full damage and faster", "It can't attack up there...").
- Plain verbs and words: "Shoots a 13 m long beam", "close by" for "within 7 m", "flies back" for "flies back to his hand".
- No "his" or "her", no "where you face".
- A chance reads "has a 60% chance of ...".
- A mutation says what changes in a few words ("Breath is wider and knocks enemies harder.").
- The main effect's key numbers stay as variables; the rest go.
- Quips and scene-setting go from the item's own text ("The Star smiles on you:", "The Devil deals you in:").

## 2. Nothing glued on: the card says the item's own text

Before, the game added sentences after every weapon's row. It no longer does. A weapon's description is now its row and nothing else (an evolution's is its row plus the mutations note, section 3). Everywhere: level-up cards, the chest, the pause screen, the Collection, the Outlaw sheet.

What is no longer added, with the rows that held it (the rows stay in the table, unused on cards):

| What | Rows |
|---|---|
| The Dynamite's fuse ("It lies where it lands and blows a second later.") | `gen.weapon.fuse.it / .each / .sticky / .when / .when_second` |
| "Knocks enemies back." | `gen.weapon.knocks_back` |
| The pierce count and the pierce drop-off ("Pierces 2: the first enemy takes 15% more...") | `gen.weapon.pierces, gen.weapon.pierce.*` |
| Burn and poison ("Sets on fire: 4 damage every 0.6 s...", "Poisons: ...") | `gen.weapon.burns, .burns_some, .poisons, .poisons_stacks` |
| "<Outlaw>'s own." | `gen.weapon.outlaws_own` |
| "Evolved: cannot level further." | `gen.weapon.evolved` |
| Held mutations' own sentences (Hip Shot, Both Barrels, ricochets, mini crits, Fire in the Hole, Sun Cocktail's burst) | `gen.weapon.hip_shot, .double_every, .ricochet, .mini_crit, .mass_mini, .land_blast.*` |
| Melee extras (stun, the Thunder Lance's thrust, the Whirlwind's refund, Heartseeker) | `gen.weapon.stun_always, .stun_chance, .thrust.alternate, .thrust.crit_refund, .thrust.stunned_mult, .crit_stroke.*` |
| Spear extras (Pinning Throw, the War Lance's dust) | `gen.weapon.spear.pin, .spear.dust` |
| Hammer extras (the Earthshaker's cracks, Giant Slayer) | `gen.weapon.smash.quake*, .smash.giant_slayer` |
| Rocket extras (Cluster Munitions, Pressure Cooker, double volley) | `gen.weapon.pod.cluster*, .pod.pressure, .pod.overpressure, .pod.vent_*` |
| Guitar extras (Music Slap's slap, the echoes) | `gen.weapon.cone.slap, .cone.echoes` |
| Sun Scepter extras (pillars a strike, Zenith, Gold Dust) | `gen.weapon.sun.pillars, .sun.zenith, .sun.gold_dust` |
| Frisbee extras (Carry, Trick Shot, stun, the Saucer's loop) | `gen.weapon.frisbee.carry*, .frisbee.procs, .frisbee.loop` |
| Salt extras (Hiwa Kai's crystals, slow, Thing About Luck, Salt Flats) | `gen.weapon.salt.crunch*, .salt.slow, .salt.luck, .salt.momentum` |
| Basketball extras (Heat, Slam Dunk's dunk, Alley-Oop's launch) | `gen.weapon.ball.heat*, .ball.slam, .ball.at_*, gen.weapon.launch (yours, kept as you wrote it)` |
| Dragon's Breath extras (extra seconds, Backdraft's shove, Held Breath) | `gen.weapon.breath.extra, .breath.shove_*, .breath.still (yours, kept), .breath.still_ring` |

Where the player still sees it: each mutation's own card says what it adds; the pause screen's Build row lists the held mutations by name and its stat rows show pierce, knockback, burn, poison, hip shot and the rest. The code that compared English ("Knocks enemies back", "Evolved:") on the pause screen is gone; it now takes the first sentence of the row's line.

One before/after per kind (level 1 unless it says `mut ALL`, every path mutation held). 504 weapon description states changed in all.

| Card | Before | After |
|---|---|---|
| `lob_grenade L1 desc` | Lobs 1 stick at the densest crowd. Explodes in a 2.8 m radius. It lies where it lands and blows a second later. Knocks enemies back. | Lobs 1 stick at the densest crowd. Explodes in a 2.8 m radius. |
| `lob_grenade mut ALL desc` | Lobs 2 sticks at the densest crowd. Explodes in a 4.6 m radius. One that sticks to nothing lies where it lands and blows a second later. Knocks enemies back. | Lobs 2 sticks at the densest crowd. Explodes in a 4.6 m radius. |
| `revolver mut ALL desc` | Fires 3 shots within 14 m and aims at the strongest enemy nearby. Every 5th pull fires 3 volleys in a row. Pierces 4: the first enemy takes 15% more, each one after it 20% less than the one before. Knocks enemies back. Drifter's own. | Fires 3 shots at the strongest enemy nearby within 14 m. |
| `golden_revolver L1 desc` | Fires 2 shots within 15 m and aims at the strongest enemy nearby. Every 3rd pull fires 3 volleys in a row. Every round ricochets 2 times at 80%. Pierces 3: the first enemy takes 15% more, each one after it 20% less than the one before. Knocks enemies back. Drifter's own. Evolved: cannot level further. | Fires 2 silver bullets at the strongest enemy nearby that ricochet 2 times. Every 3rd pull is a hip shot. / All your mutations still apply and get stronger. |
| `basketball L1 desc` | Throws a ball at the strongest enemy within 9 m, it bounces to 1 more enemy close by, then flies back. Every caught ball that scored adds Heat: +5% damage, up to +50%. A hit on him cools it. Knocks enemies back. Fadeaway's own. | Throws a ball at the strongest enemy within 9 m, it bounces to 1 more enemy close by, then flies back. |
| `dragons_breath mut ALL desc` | Breathes a 60° cone of fire 8 m long for 3.0 s every 7.0 s Every extra projectile adds 1 s of breath. Every second in it shoves them away from you. Stand still 2 s before a breath: it lasts ×2, hits ×1.5 and comes from all sides; a hit breaks the stillness. Sets on fire: 9 damage every 0.6 s for 4.4 s. Spreads to touching enemies (30%). | Breathes a 60° cone of fire 8 m long for 3.0 s every 7.0 s |
| `tommy_gun L1 desc` | Fires 6 shots within 12 m and aims at the strongest enemy nearby. Pierces 2: the first enemy takes 15% more, each one after it 20% less than the one before. Knocks enemies back. | Fires a burst of 6 rounds at the strongest enemy nearby within 12 m. |
| `pike L1 desc` | Thrusts 1 blade at the strongest enemy nearby within 4.6 m. The first enemy along the thrust takes 15% more, each one behind it 20% less than the one before. Knocks enemies back. | Thrusts a spear at the strongest enemy nearby within 4.6 m. |
| `hellfire_battery L1 desc` | Launches 8 homing rockets at enemies within 13 m: a 2.0 m blast each. Every blast scatters 6 bomblets that pop under a creature's feet for 25% of the damage, setting off their neighbours. Standing still builds pressure: up to 200% faster after 15 s; moving lets it out, a hit vents half. At full pressure every 4th volley fires twice. Knocks enemies back. Evolved: cannot level further. | Launches 8 homing rockets. Every blast scatters bomblets that set each other off. / All your mutations still apply and get stronger. |
| `salt L1 desc` | Pours a 1.4 m patch of salt in your wake every 1.9 s. It lasts 4 s; enemies in it take 6 damage every 0.5 s. | Pours a patch of salt (1.4 m) behind you every 1.9 s. Enemies in the salt take 6 damage every 0.5 s. |
| `sun_scepter mut ALL desc` | Calls a pillar of sunlight down on a random enemy you can see every 0.7 s (the closer, the likelier): 16 damage in 1.8 m. 3 pillars a strike. Its kills drop a coin 30% of the time. Sets 35% of the enemies it hits on fire: 4 damage every 0.6 s for 3.6 s. Spreads to touching enemies (50%). Knocks enemies back. Solenne's own. | Calls 3 pillars of sunlight down on random enemies every 0.7 s, 16 damage in a 1.8 m radius. |
| `orbit_saws L1 desc` | 2 blades circle you at 2.0 m, hitting anything they touch. Knocks enemies back. | 2 saw blades circle you and cut every enemy in the way. |

## 3. Evolutions: one short line, then the note

Every evolution's text is now one short row of its own (what it does that the weapon did not), then on its own line at the bottom:

- `gen.evolution.mutations_note` = "All your mutations still apply."
- Evolutions whose own numbers raise a path mutation's (read from each evolution's `final` block against its family's mutations) say instead "All your mutations still apply and get stronger." (`evolution.<id>.note`, one row each, so you can change one alone): Blunderbuss, Dust Devil, Fire Eater, Flying Saucer, Golden Pineapple, Golden Revolver, Grave Hail, Hellfire Battery, Hive Queen, Hiwa Kai, Iron Bastion, Moonshine, Pea Cannon, Slam Dunk, Storm Cloud, Thunder Lance.
- The note goes on your four families' evolutions too (Slam Dunk, Loudmouth, Fire Eater, Blunderbuss, Doomstick). It is a new line under your text, not a change to it.

An evolution always carries its three path mutations, so its own row is used whatever they did to its shape (the Halberd with Pike Sweep). Your Doomstick row needs `{cone}`; under Birdshot Lane there is no cone, so it falls back to the lane row as before.

## 4. Every row and text that changed

`key | before | after`. Rows of `game/content/strings/en.json`; content texts name their file.

### Basketball family

| Key | Before | After |
|---|---|---|
| `evolution.slam_dunk.note` | *(new)* | All your mutations still apply and get stronger. |

### Boomstick family

| Key | Before | After |
|---|---|---|
| `evolution.blunderbuss.note` | *(new)* | All your mutations still apply and get stronger. |

### Branding Iron family

| Key | Before | After |
|---|---|---|
| `evolution.ring_of_fire.desc` | {amount} {amount?blade:blades} circle you at {radius} m, hitting anything they touch. | {amount} branding irons circle you in a ring of fire, burning every enemy they touch. |
| `weapon.branding_iron.desc` | {amount} {amount?blade:blades} circle you at {radius} m, hitting anything they touch. | {amount?A hot branding iron circles:{amount} hot branding irons circle} you and set{amount?s:} enemies on fire. |
| mutation `cauterize` (`mutations/cauterize/cauterize.json`) | A branded creature takes +40% from everything for 3 s. | Branded enemies take 40% more damage for 3 s. |
| mutation `lasso` (`mutations/lasso/lasso.json`) | Every 2 s the iron swings out to 5 m and drags what it hits back to you. | Every 2 s the iron swings out and drags enemies back to you. |

### Dragon's Breath family

| Key | Before | After |
|---|---|---|
| `evolution.fire_eater.note` | *(new)* | All your mutations still apply and get stronger. |

### Flare Gun family

| Key | Before | After |
|---|---|---|
| `evolution.roman_candle.desc` | Fires {amount} {amount?flare:flares} at the nearest enemy within {range} m that is not burning yet. | Fires a volley of {amount} flares that set enemies on fire. |
| `weapon.flare_gun.desc` | Fires {amount} {amount?flare:flares} at the nearest enemy within {range} m that is not burning yet. | Fires {amount} {amount?flare that sets:flares that set} enemies on fire. |
| mutation `sky_flare` (`mutations/sky_flare/sky_flare.json`) | The flare bursts into five embers that fall in a ring around whatever it hits. | Flares burst into embers that rain down around what they hit. |
| mutation `white_phosphorus` (`mutations/white_phosphorus/white_phosphorus.json`) | Burning creatures take +50% fire damage and spread the fire when they die. | Burning enemies take 50% more fire damage and spread the fire when they die. |

### Frisbee family

| Key | Before | After |
|---|---|---|
| `evolution.flying_saucer.desc` | {amount?Throws a frisbee:Throws {amount} frisbees, fanned out,} at the nearest enemy within {range} m, curving left or right: {amount?it cuts:they cut} through everything in a {range} m flight, each enemy after the first taking {less}% less (never under {floor}%). | Throws {amount?a glowing saucer that loops:{amount} glowing saucers that loop} once and {amount?cuts:cut} through every enemy in the way. |
| `evolution.flying_saucer.note` | *(new)* | All your mutations still apply and get stronger. |
| `weapon.frisbee.desc` | {amount?Throws a frisbee:Throws {amount} frisbees, fanned out,} at the nearest enemy within {range} m, curving left or right: {amount?it cuts:they cut} through everything in a {range} m flight, each enemy after the first taking {less}% less (never under {floor}%). | Throws {amount?a frisbee that curves:{amount} frisbees that curve} through every enemy in the way. |
| mutation `carry` (`mutations/carry/carry.json`) | It has a 10% chance to carry the enemy away. | The frisbee has a 10% chance of carrying an enemy away. |
| mutation `poison_razors` (`mutations/poison_razors/poison_razors.json`) | Razor blades round the rim: everything it cuts is poisoned. | The frisbee poisons every enemy it cuts. |

### Gravity Gun family

| Key | Before | After |
|---|---|---|
| `evolution.singularity.desc` | Lobs {amount} {amount?black hole:black holes} at the thickest crowd: {amount?it drags everything in and eats it, then pops:they drag everything in and eat it, then pop}. | Lobs {amount?a black hole that drags enemies in, eats them, then pops:{amount} black holes that drag enemies in, eat them, then pop}. |
| `weapon.gravity_gun.desc` | Picks up {amount} {amount?enemy:enemies} within {range} m and throws {amount?it:them} into the thickest crowd: a {blast} m blast. What it throws takes a hit when it lands. | Picks up {amount} {amount?enemy:enemies} and throws {amount?it:them} into the thickest crowd for a {blast} m blast. |
| mutation `repulsor` (`mutations/repulsor/repulsor.json`) | Landings throw 2.5 times as hard over a 40% wider blast, +15% damage. | Landings throw enemies harder in a 40% wider blast. |
| mutation `slingshot` (`mutations/slingshot/slingshot.json`) | The thrown enemy skips on to the next crowd for a second blast at 60%. | The thrown enemy skips on to the next crowd for a second blast. |

### Guitarra family

| Key | Before | After |
|---|---|---|
| `evolution.requiem.desc` | Strums a ring of melody {range} m all round: whatever stands in it is lifted {lift} m and dropped where it stood. | Strums a full ring of melody that lifts every enemy around you into the air. |
| `weapon.guitarra.desc` | Strums a {deg}° cone of melody {range} m at the nearest enemy: whatever stands in it is lifted {lift} m and dropped where it stood. | Strums a {deg}° cone of melody that lifts enemies into the air{amount?:, {amount} times in a row}. |
| mutation `far_reach` (`mutations/far_reach/far_reach.json`) | Half a circle of sound, half again as far, half the damage. | The melody covers half a circle and reaches 50% further, for half the damage. |
| mutation `music_slap` (`mutations/music_slap/music_slap.json`) | Every chord slaps them sideways: +60% damage, 40% slower. | Chords slap enemies aside for 60% more damage, but strum 40% slower. |
| mutation `tinnitus` (`mutations/tinnitus/tinnitus.json`) | Every third hit on the same creature deals double damage and 50% more knockback. | Every third hit on the same enemy deals double damage. |

### Hammer family

| Key | Before | After |
|---|---|---|
| `evolution.earthshaker.desc` | Brings {amount} {amount?hammer:hammers} down on the thickest crowd within {range} m: a {blast} m blast that throws them outwards. | Slams {amount} hammers down on the thickest crowd, splitting the ground in lightning cracks. |
| `evolution.earthshaker_v47.desc` | Brings {amount} {amount?hammer:hammers} down on the thickest crowd within {range} m: a {blast} m blast that throws them outwards. | Slams {amount} hammers down on the thickest crowd, splitting the ground in cracks. |
| `weapon.hammer.desc` | Brings {amount} {amount?hammer:hammers} down on the thickest crowd within {range} m: a {blast} m blast that throws them outwards. | Slams {amount?a hammer:{amount} hammers} down on the thickest crowd, throwing enemies out of a {blast} m blast. |
| mutation `aftershock` (`mutations/aftershock/aftershock.json`) | A beat after every impact a shockwave rolls out to twice the blast, for 40% damage. | Every impact sends out a second shockwave twice as wide. |
| mutation `giant_slayer` (`mutations/giant_slayer/giant_slayer.json`) | Half of all impacts deal 2.5 times the damage to a boss, an Elite or an elite creature in the blast. | Impacts have a 50% chance of dealing 2.5 times the damage to bosses and Elites. |
| mutation `thors_wrath` (`mutations/thors_wrath/thors_wrath.json`) | Half of all impacts throw lightning at the three nearest creatures outside the blast within 7 m, 35% of the hit each. | Impacts have a 50% chance of throwing lightning at 3 enemies close by. |

### Killer Bees family

| Key | Before | After |
|---|---|---|
| `evolution.hive_queen.desc` | Sends {amount} killer {amount?bee:bees} after {prey} within {range} m. | Sends {amount} killer bees and a Tarantula Hawk with every burst. |
| `evolution.hive_queen.note` | *(new)* | All your mutations still apply and get stronger. |
| `evolution.killer_swarm.desc` | Sends {amount} killer {amount?bee:bees} after {prey} within {range} m. | Sends a swarm of {amount} killer bees after {prey}. |
| mutation `pollen` (`mutations/pollen/pollen.json`) | While held, a flower grows from the sand every 8-12 s, 10-18 m away (3 at most, 15 s each); walk into one for 4 times the bees at 1.5 times the speed for 5 s. | Flowers grow from the sand; walk into one for 4 times the bees for 5 s. |
| mutation `second_sting` (`mutations/second_sting/second_sting.json`) | A bee that kills turns and dives at the next creature, once. | A bee that kills dives at the next enemy. |
| mutation `tarantula_hawk` (`mutations/tarantula_hawk/tarantula_hawk.json`) | Every fourth burst (every burst while a flower's buff lasts) sends a big purple bee at the strongest enemy near: it buzzes round it and darts in to sting five times over 4 s, each a bee's damage, slowing its moves and attacks 10%. | Every fourth burst also sends a Tarantula Hawk that stings the strongest enemy five times. |

### Land Mine family

| Key | Before | After |
|---|---|---|
| `evolution.jackrabbit_mines.desc` | Drops {amount?a mine:{amount} mines} at your feet every {cooldown} s: each springs at a creature within {sense} m and bursts at chest height, then its casing hops on to another, a {area} m blast. | Drops {amount?a mine:{amount} mines} every {cooldown} s that {amount?jumps:jump} at enemies within {sense} m, then {amount?hops:hop} on to another. |
| `evolution.minefield.desc` | Drops {amount?a mine:{amount} mines} at your feet every {cooldown} s: a creature that steps on it sets it off, a {area} m blast. | Drops {amount?a mine:{amount} mines} every {cooldown} s, covering the ground in mines. |
| `weapon.land_mine.desc` | Drops {amount?a mine:{amount} mines} at your feet every {cooldown} s: a creature that steps on it sets it off, a {area} m blast. | Drops {amount?a mine:{amount} mines} every {cooldown} s that {amount?blows:blow} up in a {area} m blast when an enemy steps on {amount?it:them}. |
| mutation `blasting_cap` (`mutations/blasting_cap/blasting_cap.json`) | A mine that kills drops a gold nugget; +25% radius. | Mines that kill drop a gold nugget and blow 25% wider. |
| mutation `bouncing_betty` (`mutations/bouncing_betty/bouncing_betty.json`) | The mine leaps and bursts at chest height: ×1.5 radius, ×2 knockback. | Mines leap and burst at chest height in a bigger blast. |
| mutation `wide_reach` (`mutations/wide_reach/wide_reach.json`) | A creature within 2.8 m makes the mine crouch and spring at it, blowing where it lands. | Mines jump at enemies close by and blow where they land. |

### Lob Grenade family

| Key | Before | After |
|---|---|---|
| `evolution.cluster_bomb.desc` | Lobs {amount} {thing} at the densest crowd. Explodes in a {area} m radius. | Lobs {amount} {thing} at the densest crowd that burst into small bombs. |
| `evolution.golden_pineapple.desc` | Lobs {amount} {thing} at the densest crowd. Explodes in a {area} m radius. | Lobs {amount} golden {thing} that stick to the strongest enemy, then explode in a {area} m radius. |
| `evolution.golden_pineapple.note` | *(new)* | All your mutations still apply and get stronger. |
| mutation `fire_in_the_hole` (`mutations/fire_in_the_hole/fire_in_the_hole.json`) | A blast that catches nine or more creatures lands a Mini Crit on every one of them. | A blast that hits 9 or more enemies lands a Mini Crit on each of them. |
| mutation `new_equipment` (`mutations/new_equipment/new_equipment.json`) | +30% knockback, +20% area, +20% damage, and a grenade 35% bigger. | A bigger grenade: +20% damage, +20% area and +30% knockback. |
| mutation `new_equipment` (`mutations/new_equipment/new_equipment.json`) | +30% knockback, +20% area, +20% damage, and a bundle of sticks 35% bigger. | A bigger bundle of sticks: +20% damage, +20% area and +30% knockback. |
| mutation `sticky` (`mutations/sticky/sticky.json`) | Sticks to the first creature it lands by and rides it into its pack before it blows. | Sticks to the first enemy it lands near and rides it into the crowd before it blows. |

### Molotov family

| Key | Before | After |
|---|---|---|
| `evolution.firestorm.desc` | Lobs {amount} {thing} of fire at the thickest crowd that is not burning yet. Leaves a {area} m pool of flames. | Lobs {amount} {thing} of fire that leave big pools of flames. |
| `evolution.moonshine.desc` | Lobs {amount} {thing} of fire at the thickest crowd that is not burning yet. Leaves a {area} m pool of flames. | Lobs {amount} {thing} of blue fire that leave a burning trail and long-lasting pools. |
| `evolution.moonshine.note` | *(new)* | All your mutations still apply and get stronger. |
| `weapon.molotov.desc` | Lobs {amount} {thing} of fire at the thickest crowd that is not burning yet. Leaves a {area} m pool of flames. | Lobs {amount} {thing} of fire at the thickest crowd. Leaves a {area} m pool of flames. |
| mutation `accelerant` (`mutations/accelerant/accelerant.json`) | Clouds last twice as long and burning creatures spread the fire when they die. | Flames last twice as long, and burning enemies spread the fire when they die. |
| mutation `methanol` (`mutations/methanol/methanol.json`) | The fire burns blue: pools 50% bigger, burns last 75% longer, −20% burn damage. | The fire burns blue: 50% bigger pools and longer burns, for 20% less burn damage. |
| mutation `oil_slick` (`mutations/oil_slick/oil_slick.json`) | The bottle leaks as it flies: a trail of small burning spills drips along the throw, and they slow. | The bottle leaves a trail of burning oil that slows enemies. |
| mutation `sun_cocktail` (`mutations/sun_cocktail/sun_cocktail.json`) | Bottles shine with sunlight and burst where they land: a small blast for 150% of their damage that pushes a little. | Bottles burst with sunlight where they land, a small blast for 150% damage. |

### Orbit Saws family

| Key | Before | After |
|---|---|---|
| `evolution.saw_halo.desc` | {amount} {amount?blade:blades} circle you at {radius} m, hitting anything they touch. | {amount} saw blades spin round you in a solid ring that cuts everything it touches. |
| `weapon.orbit_saws.desc` | {amount} {amount?blade:blades} circle you at {radius} m, hitting anything they touch. | {amount?A saw blade circles you and cuts:{amount} saw blades circle you and cut} every enemy in the way. |
| mutation `gyro_saws` (`mutations/gyro_saws/gyro_saws.json`) | The ring widens 30% while she moves and tightens when she stops. | The ring widens 30% while moving and tightens when standing still. |
| mutation `wide_orbit` (`mutations/wide_orbit/wide_orbit.json`) | The ring breathes from ×0.9 to ×1.6 its radius. A saw hit shoves the creature sideways along the spin, once a second. | The ring grows and shrinks, reaching up to 60% wider. |

### Peashooter family

| Key | Before | After |
|---|---|---|
| `evolution.bullet_hose.desc` | Fires {amount} {amount?shot:shots} within {range} m and aims at {who}. | Sprays a nonstop stream of peas at {who} within {range} m. |
| `evolution.pea_cannon.desc` | Fires {amount} {amount?shot:shots} within {range} m and aims at {who}. | Fires {amount} giant toxic {amount?pea:peas} at {who} that bounce on to {bounces} more enemies. |
| `evolution.pea_cannon.note` | *(new)* | All your mutations still apply and get stronger. |
| `weapon.peashooter.desc` | Fires {amount} {amount?shot:shots} within {range} m and aims at {who}. | Fires {amount} {amount?pea:peas} at {who} within {range} m. |
| mutation `big_peas` (`mutations/big_peas/big_peas.json`) | Peas half again as big: +35% damage and twice the knockback. | Bigger peas: +35% damage and twice the knockback. |
| mutation `bouncing_peas` (`mutations/bouncing_peas/bouncing_peas.json`) | Every pea bounces to a second creature at full damage. | Every pea bounces on to a second enemy. |

### Poison Dart family

| Key | Before | After |
|---|---|---|
| `evolution.plague_volley.desc` | Fires {amount} {amount?dart:darts} at the nearest enemy within {range} m that is not poisoned yet. | Fires a volley of {amount} poison darts at enemies that are not poisoned yet. |
| `weapon.poison_dart.desc` | Fires {amount} {amount?dart:darts} at the nearest enemy within {range} m that is not poisoned yet. | Fires {amount} poison {amount?dart:darts} at an enemy that is not poisoned yet. |
| mutation `blight` (`mutations/blight/blight.json`) | +2 poison stacks, and a creature that dies poisoned passes it to the nearest one. | +2 poison stacks, and poisoned enemies pass the poison on when they die. |
| mutation `needle_rain` (`mutations/needle_rain/needle_rain.json`) | The darts arc over everything and fall from above, leaving a poison cloud where they land. | Darts fall from above and leave a poison cloud where they land. |

### Rattlesnake family

| Key | Before | After |
|---|---|---|
| `evolution.snake_pit.desc` | {amount} {amount?blade:blades} circle you at {radius} m, hitting anything they touch. | {amount} rattlesnakes circle you fast, poisoning every enemy they bite. |
| `weapon.rattlesnake.desc` | {amount} {amount?blade:blades} circle you at {radius} m, hitting anything they touch. | {amount?A rattlesnake circles you and bites:{amount} rattlesnakes circle you and bite} enemies, poisoning them. |
| mutation `rattle` (`mutations/rattle/rattle.json`) | Poisoned creatures move 30% slower. | Poisoned enemies move 30% slower. |
| mutation `strike` (`mutations/strike/strike.json`) | Every 2 s the snake lunges at the nearest creature outside the orbit for double damage. | Every 2 s a snake lunges at an enemy outside the ring for double damage. |

### Revolver family

| Key | Before | After |
|---|---|---|
| `evolution.golden_revolver.desc` | Fires {amount} {amount?shot:shots} within {range} m and aims at {who}. | Fires {amount} silver {amount?bullet:bullets} at {who} that ricochet {bounces} {bounces?time:times}. Every {hip_nth} pull is a hip shot. |
| `evolution.golden_revolver.note` | *(new)* | All your mutations still apply and get stronger. |
| `evolution.golden_revolver_v47.desc` | Fires {amount} {amount?shot:shots} within {range} m and aims at {who}. | Fires {amount} golden {amount?bullet:bullets} at {who} within {range} m. |
| `weapon.revolver.desc` | Fires {amount} {amount?shot:shots} within {range} m and aims at {who}. | Fires {amount} {amount?shot:shots} at {who} within {range} m. |
| mutation `hip_shot` (`mutations/hip_shot/hip_shot.json`) | Every fifth pull fires three volleys 0.12 s apart, each the full round count, then the revolver spins. | Every fifth pull fires three volleys in a row. |
| mutation `silver_bullet` (`mutations/silver_bullet/silver_bullet.json`) | +50% damage and +1 pierce, in rounds half again as big that hit wider. | Bigger silver bullets: +50% damage and +1 pierce. |
| mutation `trick_shot` (`mutations/trick_shot/trick_shot.json`) | A round that kills bounces on to the next enemy at 80%, every time. | A bullet that kills bounces on to the next enemy. |

### Rocket Pod family

| Key | Before | After |
|---|---|---|
| `evolution.hellfire_battery.desc` | Launches {amount} homing {amount?rocket:rockets} at {prey} within {range} m: a {blast} m blast each. | Launches {amount} homing rockets. Every blast scatters bomblets that set each other off. |
| `evolution.hellfire_battery.note` | *(new)* | All your mutations still apply and get stronger. |
| `evolution.missile_massacre.desc` | Launches {amount} homing {amount?rocket:rockets} at {prey} within {range} m: a {blast} m blast each. | Launches {amount} homing rockets that fill the sky. |
| `weapon.rocket_pod.desc` | Launches {amount} homing {amount?rocket:rockets} at {prey} within {range} m: a {blast} m blast each. | Launches {amount} homing {amount?rocket:rockets} at {prey}. {amount?It explodes:Each explodes} in a {blast} m radius. |
| mutation `cluster_munitions` (`mutations/cluster_munitions/cluster_munitions.json`) | 30% of blasts scatter five bomblets: step on one and it pops for a quarter of the rocket's damage. | Blasts have a 30% chance of scattering bomblets that pop when stepped on. |
| mutation `heavy_warhead` (`mutations/heavy_warhead/heavy_warhead.json`) | +40% damage, ×2 knockback, +15% area of effect: bigger rockets, a stronger blast. | Bigger rockets: +40% damage, double knockback and a 15% bigger blast. |
| mutation `pressure_cooker` (`mutations/pressure_cooker/pressure_cooker.json`) | Standing still builds pressure: the pod fires faster every second, up to +200% after 15 s. Moving lets it out; a hit vents half. | Standing still makes the pod fire faster, up to +200% after 15 s. Moving lets the pressure out. |

### Sabre family

| Key | Before | After |
|---|---|---|
| `evolution.whirlwind.desc` | Slices a {deg}° arc across {who} within {range} m{amount?:, {amount} swings a stroke}, throwing what it cuts out and aside. | Spins a full circle {amount?once:{amount} times} a swing. Crits give back part of the cooldown. |
| `evolution.zweihander.desc` | Slices a {deg}° arc across {who} within {range} m{amount?:, {amount} swings a stroke}, throwing what it cuts out and aside. | Swings a huge {deg}° slash {amount?once:{amount} times} a swing. |
| `weapon.sabre.desc` | Slices a {deg}° arc across {who} within {range} m{amount?:, {amount} swings a stroke}, throwing what it cuts out and aside. | Slashes a {deg}° arc at {who}{amount?:, {amount} times a swing}. |
| mutation `flurry` (`mutations/flurry/flurry.json`) | Twice the slices a stroke. | Twice as many slashes a swing. |
| mutation `riposte` (`mutations/riposte/riposte.json`) | Strokes come 25% faster and throw what they hit twice as far. | Swings come 25% faster and knock enemies twice as far. |

### Salt family

| Key | Before | After |
|---|---|---|
| `evolution.hiwa_kai.desc` | {amount?Pours a {radius} m patch of salt in your wake every {cooldown} s. It lasts {lasts} s; enemies in it:Pours {amount} patches of salt ({radius} m) in your wake every {cooldown} s. They last {lasts} s; enemies in them} take {damage} damage every {tick} s. | Pours black lava salt behind you that slows enemies and bites hard when they step in. |
| `evolution.hiwa_kai.note` | *(new)* | All your mutations still apply and get stronger. |
| `weapon.salt.desc` | {amount?Pours a {radius} m patch of salt in your wake every {cooldown} s. It lasts {lasts} s; enemies in it:Pours {amount} patches of salt ({radius} m) in your wake every {cooldown} s. They last {lasts} s; enemies in them} take {damage} damage every {tick} s. | Pours {amount?a patch:{amount} patches} of salt ({radius} m) behind you every {cooldown} s. Enemies in the salt take {damage} damage every {tick} s. |
| mutation `salt_flats` (`mutations/salt_flats/salt_flats.json`) | Walking into a salt patch puts his speed-up at full at once. | Walking into salt fills the speed-up at once. |

### Skull Rain family

| Key | Before | After |
|---|---|---|
| `evolution.dia_de_muertos.desc` | Lobs {amount} poison {thing} at the thickest crowd of healthy enemies. Leaves a {area} m cloud of green smoke. | Lobs {amount} poison {thing} that leave long-lasting clouds of poison. |
| `evolution.grave_hail.desc` | Lobs {amount} poison {thing} at the thickest crowd of healthy enemies. Leaves a {area} m cloud of green smoke. | Lobs {amount} poison {thing} that bounce on, leaving a poison cloud at every landing. |
| `evolution.grave_hail.note` | *(new)* | All your mutations still apply and get stronger. |
| `weapon.skull_rain.desc` | Lobs {amount} poison {thing} at the thickest crowd of healthy enemies. Leaves a {area} m cloud of green smoke. | Lobs {amount} poison {thing} at the thickest crowd. Leaves a {area} m cloud of poison. |
| mutation `bouncing_skull` (`mutations/bouncing_skull/bouncing_skull.json`) | After its blast the skull bounces on twice, turning up to 30° toward the nearest enemy ahead: the first bounce lands 1.6x the blast's radius + 1.5 m on with a 70% blast and cloud, the second 1.2x + 1 m on at 50%. | Skulls bounce on twice after the blast, leaving a smaller blast and cloud each time. |
| mutation `curare` (`mutations/curare/curare.json`) | Poisoning a creature may slow its moves and attacks by 50% for 3 s: a 20% chance that grows 20% with every re-poisoning, then 10 s before it can again. | Poison has a 20% chance of slowing an enemy by 50% for 3 s. |

### Spear family

| Key | Before | After |
|---|---|---|
| `evolution.halberd.desc` | Thrusts {amount} {amount?blade:blades} at {who} within {range} m. | Swings {amount} halberd blades in a wide fan at {who}. |
| `evolution.thunder_lance.desc` | Slices a {deg}° arc across {who} within {range} m{amount?:, {amount} blades sweeping together}, throwing what it cuts out and aside. | Sweeps {amount} lances in a {deg}° arc, then thrusts. Every hit stuns. |
| `evolution.thunder_lance.note` | *(new)* | All your mutations still apply and get stronger. |
| `weapon.pike.desc` | Thrusts {amount} {amount?blade:blades} at {who} within {range} m. | Thrusts {amount?a spear:{amount} spears} at {who} within {range} m. |
| mutation `pike_sweep` (`mutations/pike_sweep/pike_sweep.json`) | A 120° sweep like a sabre's, with less knockback. | The spear sweeps a 120° arc instead of thrusting. |
| mutation `stunning_thrust` (`mutations/stunning_thrust/stunning_thrust.json`) | Every hit has a 15% chance to stun for a second. | Each hit has a 15% chance of stunning the enemy for 1 s. |

### Sun Scepter family

| Key | Before | After |
|---|---|---|
| `evolution.zenith.desc` | Calls a pillar of sunlight down on a random enemy you can see every {cooldown} s (the closer, the likelier): {damage} damage in {radius} m. | Calls {amount} pillars of sunlight down every {cooldown} s. Every {nth} strike hits every enemy on screen. |
| `weapon.sun_scepter.desc` | Calls a pillar of sunlight down on a random enemy you can see every {cooldown} s (the closer, the likelier): {damage} damage in {radius} m. | Calls {amount?a pillar:{amount} pillars} of sunlight down on random enemies every {cooldown} s, {damage} damage in a {radius} m radius. |
| mutation `flicker` (`mutations/flicker/flicker.json`) | Strikes 30% sooner for 25% less damage. The pillars burn thinner and yellower. | Strikes 30% sooner for 25% less damage. |
| mutation `gold_dust` (`mutations/gold_dust/gold_dust.json`) | An enemy it kills drops a coin 30% of the time. | Kills have a 30% chance of dropping a coin. |
| mutation `heat_stroke` (`mutations/heat_stroke/heat_stroke.json`) | 35% of the enemies its pillars hit catch fire: 4 damage every 0.6 s for 3.6 s. | Pillars have a 35% chance of setting enemies on fire. |

### Throwing Spear family

| Key | Before | After |
|---|---|---|
| `evolution.war_lance.desc` | Throws {amount?a spear:{amount} spears} at {who}: through everything in the way, out to {range} m, where {amount?it sticks:they stick} in the sand. | Throws {amount?a spear:{amount} spears} through every enemy in the way, leaving a trail of slowing dust. |
| `weapon.spear.desc` | Throws {amount?a spear:{amount} spears} at {who}: through everything in the way, out to {range} m, where {amount?it sticks:they stick} in the sand. | Throws {amount?a spear:{amount} spears} {range} m through every enemy in the way. |
| mutation `fire_hardened` (`mutations/fire_hardened/fire_hardened.json`) | The spear sets alight everything it passes through. | Spears set every enemy they pass through on fire. |
| mutation `pinning_throw` (`mutations/pinning_throw/pinning_throw.json`) | The first enemy each spear strikes is pinned in place for 1.2 s. | Spears pin the first enemy they hit for 1.2 s. |
| mutation `spear_volley` (`mutations/spear_volley/spear_volley.json`) | Three spears for every one, fanned out, −40% damage each. | Throws three spears for every one, −40% damage each. |

### Tommy Gun family

| Key | Before | After |
|---|---|---|
| `evolution.chicago_typewriter.desc` | Fires {amount} {amount?shot:shots} within {range} m and aims at {who}. | Fires a long burst of {amount} rounds at {who} within {range} m. |
| `weapon.tommy_gun.desc` | Fires {amount} {amount?shot:shots} within {range} m and aims at {who}. | Fires a burst of {amount} {amount?round:rounds} at {who} within {range} m. |
| mutation `mini_crits` (`mutations/mini_crits/mini_crits.json`) | A quarter of the rounds are mini crits: half a crit's extra damage, carried through every pierce. | A quarter of the rounds are mini crits. |
| mutation `trigger_happy` (`mutations/trigger_happy/trigger_happy.json`) | The Tommy Gun never stops firing: a steady stream of two thirds more rounds, each 35% weaker, swaying 12° to either side on its own so it sprays the whole front. | The Tommy Gun never stops firing, spraying a steady stream of weaker rounds. |

### Tumbleweed family

| Key | Before | After |
|---|---|---|
| `evolution.dust_devil.desc` | Fires {amount} {amount?shot:shots} within {range} m and aims at {who}. | Rolls {amount} thorny tumbleweeds out and back twice, hitting harder on the way back. |
| `evolution.dust_devil.note` | *(new)* | All your mutations still apply and get stronger. |
| `evolution.stampede.desc` | Fires {amount} {amount?shot:shots} within {range} m and aims at {who}. | Rolls {amount} tumbleweeds out in a wide fan through every enemy in the way. |
| `weapon.tumbleweed.desc` | Fires {amount} {amount?shot:shots} within {range} m and aims at {who}. | Rolls {amount?a tumbleweed:{amount} tumbleweeds} {range} m out through every enemy in the way. |
| mutation `dust_wake` (`mutations/dust_wake/dust_wake.json`) | A faint dust wake: enemies within 1.6 m are slowed a little. | Leaves a dust wake that slows enemies a little. |
| mutation `thorns` (`mutations/thorns/thorns.json`) | Heavier and thornier: +35% damage. It rolls out slower and comes back faster. | Heavier and thornier: +35% damage. |

### Turret Buddy family

| Key | Before | After |
|---|---|---|
| `evolution.iron_bastion.desc` | {amount?Drops a turret every {cooldown} s. It {stays}.:Drops {amount} turrets every {cooldown} s, up to {cap} standing. Each {stays}.} | Drops {amount?an armoured bunker:{amount} armoured bunkers} every {cooldown} s that explode when they go. |
| `evolution.iron_bastion.note` | *(new)* | All your mutations still apply and get stronger. |
| `evolution.turret_family.desc` | {amount?Drops a turret every {cooldown} s. It {stays}.:Drops {amount} turrets every {cooldown} s, up to {cap} standing. Each {stays}.} | Drops {amount} turrets every {cooldown} s that never leave and pull gems to you. |
| `weapon.turret_buddy.desc` | {amount?Drops a turret every {cooldown} s. It {stays}.:Drops {amount} turrets every {cooldown} s, up to {cap} standing. Each {stays}.} | Drops {amount?a turret:{amount} turrets} every {cooldown} s. {amount?It shoots:They shoot} {who} for {seconds} s. |
| mutation `bunker` (`mutations/bunker/bunker.json`) | The buddy digs in behind sandbags: twin barrels, +40% damage, shots knock back, it turns slowly. | The turret digs in behind sandbags: twin barrels and +40% damage. |
| mutation `last_stand` (`mutations/last_stand/last_stand.json`) | A turret that despawns explodes: a 3 m blast for 4× its shot's damage, throwing them back. | A turret explodes when it goes, a 3 m blast. |

### Zap Beam family

| Key | Before | After |
|---|---|---|
| `evolution.storm_cloud.desc` | Zaps a random enemy within {range} m and chains to {chains} more. | A storm cloud follows you, zapping enemies within {range} m and chaining to {chains} more. |
| `evolution.storm_cloud.note` | *(new)* | All your mutations still apply and get stronger. |
| mutation `echo_zap` (`mutations/echo_zap/echo_zap.json`) | 20% of hits zap the same enemy 3 more times for 40% damage each. | Hits have a 20% chance of zapping the same enemy 3 more times. |

### New rows: the evolution note

| Key | Before | After |
|---|---|---|
| `gen.evolution.mutations_note` | *(new)* | All your mutations still apply. |
| `gen.evolution.mutations_note_stronger` | *(new)* | All your mutations still apply and get stronger. |

### Shared shape rows (a weapon whose mutation changes its shape, or a new weapon folder)

| Key | Before | After |
|---|---|---|
| `gen.weapon.cone.cone` | Strums a {deg}° cone of melody {range} m at the nearest enemy: whatever stands in it is lifted {lift} m and dropped where it stood. | Strums a {deg}° cone of melody that lifts enemies into the air{amount?:, {amount} times in a row}. |
| `gen.weapon.cone.ring` | Strums a ring of melody {range} m all round: whatever stands in it is lifted {lift} m and dropped where it stood. | Strums a ring of melody that lifts every enemy around you into the air. |
| `gen.weapon.frisbee` | {amount?Throws a frisbee:Throws {amount} frisbees, fanned out,} at the nearest enemy within {range} m, curving left or right: {amount?it cuts:they cut} through everything in a {range} m flight, each enemy after the first taking {less}% less (never under {floor}%). | Throws {amount?a frisbee that curves:{amount} frisbees that curve} through every enemy in the way. |
| `gen.weapon.gravity.hole` | Lobs {amount} {amount?black hole:black holes} at the thickest crowd: {amount?it drags everything in and eats it, then pops:they drag everything in and eat it, then pop}. | Lobs {amount?a black hole that drags enemies in, eats them, then pops:{amount} black holes that drag enemies in, eat them, then pop}. |
| `gen.weapon.gravity.throw` | Picks up {amount} {amount?enemy:enemies} within {range} m and throws {amount?it:them} into the thickest crowd: a {blast} m blast. What it throws takes a hit when it lands. | Picks up {amount} {amount?enemy:enemies} and throws {amount?it:them} into the thickest crowd for a {blast} m blast. |
| `gen.weapon.lob.fire` | Lobs {amount} {thing} of fire at the thickest crowd that is not burning yet. Leaves a {area} m pool of flames. | Lobs {amount} {thing} of fire at the thickest crowd. Leaves a {area} m pool of flames. |
| `gen.weapon.lob.poison` | Lobs {amount} poison {thing} at the thickest crowd of healthy enemies. Leaves a {area} m cloud of green smoke. | Lobs {amount} poison {thing} at the thickest crowd. Leaves a {area} m cloud of poison. |
| `gen.weapon.mine.jackrabbit` | Drops {amount?a mine:{amount} mines} at your feet every {cooldown} s: each springs at a creature within {sense} m and bursts at chest height, then its casing hops on to another, a {area} m blast. | Drops {amount?a mine:{amount} mines} every {cooldown} s that {amount?jumps:jump} at enemies within {sense} m, then {amount?hops:hop} on to another. |
| `gen.weapon.mine.spring` | Drops {amount?a mine:{amount} mines} at your feet every {cooldown} s: each springs at a creature within {sense} m and blows where it lands, a {area} m blast. | Drops {amount?a mine:{amount} mines} every {cooldown} s that {amount?jumps:jump} at enemies within {sense} m and {amount?blows:blow} up in a {area} m blast. |
| `gen.weapon.mine.step` | Drops {amount?a mine:{amount} mines} at your feet every {cooldown} s: a creature that steps on it sets it off, a {area} m blast. | Drops {amount?a mine:{amount} mines} every {cooldown} s that {amount?blows:blow} up in a {area} m blast when an enemy steps on {amount?it:them}. |
| `gen.weapon.orbit` | {amount} {amount?blade:blades} circle you at {radius} m, hitting anything they touch. | {amount?A blade circles you and hits:{amount} blades circle you and hit} every enemy in the way. |
| `gen.weapon.pod.rockets` | Launches {amount} homing {amount?rocket:rockets} at {prey} within {range} m: a {blast} m blast each. | Launches {amount} homing {amount?rocket:rockets} at {prey}. {amount?It explodes:Each explodes} in a {blast} m radius. |
| `gen.weapon.salt` | {amount?Pours a {radius} m patch of salt in your wake every {cooldown} s. It lasts {lasts} s; enemies in it:Pours {amount} patches of salt ({radius} m) in your wake every {cooldown} s. They last {lasts} s; enemies in them} take {damage} damage every {tick} s. | Pours {amount?a patch:{amount} patches} of salt ({radius} m) behind you every {cooldown} s. Enemies in the salt take {damage} damage every {tick} s. |
| `gen.weapon.shot.dart` | Fires {amount} {amount?dart:darts} at the nearest enemy within {range} m that is not poisoned yet. | Fires {amount} poison {amount?dart:darts} at an enemy that is not poisoned yet. |
| `gen.weapon.shot.flare` | Fires {amount} {amount?flare:flares} at the nearest enemy within {range} m that is not burning yet. | Fires {amount} {amount?flare that sets:flares that set} enemies on fire. |
| `gen.weapon.shot.priority` | Fires {amount} {amount?shot:shots} within {range} m and aims at {who}. | Fires {amount} {amount?shot:shots} at {who} within {range} m. |
| `gen.weapon.smash` | Brings {amount} {amount?hammer:hammers} down on the thickest crowd within {range} m: a {blast} m blast that throws them outwards. | Slams {amount?a hammer:{amount} hammers} down on the thickest crowd, throwing enemies out of a {blast} m blast. |
| `gen.weapon.spawn` | {amount?Drops a turret every {cooldown} s. It {stays}.:Drops {amount} turrets every {cooldown} s, up to {cap} standing. Each {stays}.} | Drops {amount?a turret:{amount} turrets} every {cooldown} s. {amount?It:Each} {stays}. |
| `gen.weapon.spear` | Throws {amount?a spear:{amount} spears} at {who}: through everything in the way, out to {range} m, where {amount?it sticks:they stick} in the sand. | Throws {amount?a spear:{amount} spears} {range} m through every enemy in the way. |
| `gen.weapon.sun` | Calls a pillar of sunlight down on a random enemy you can see every {cooldown} s (the closer, the likelier): {damage} damage in {radius} m. | Calls {amount?a pillar:{amount} pillars} of sunlight down on random enemies every {cooldown} s, {damage} damage in a {radius} m radius. |
| `gen.weapon.thrust.slice` | Slices a {deg}° arc across {who} within {range} m{amount?:, {amount} swings a stroke}, throwing what it cuts out and aside. | Slashes a {deg}° arc at {who}{amount?:, {amount} times a swing}. |
| `gen.weapon.thrust.sweep` | Slices a {deg}° arc across {who} within {range} m{amount?:, {amount} blades sweeping together}, throwing what it cuts out and aside. | Sweeps {amount?a blade:{amount} blades} in a {deg}° arc at {who}. |

### Passive items and cards

| Key | Before | After |
|---|---|---|
| `gen.passive.rule.arc` | Every critical hit throws an arc to up to {arcs} more enemies within {radius} m for {pct}% of the hit. Arcs never chain. | Critical hits arc to {arcs} more enemies close by for {pct}% of the hit. |
| `gen.passive.rule.bible_block` | No single hit takes more than {cap}% of your max HP. Once every {every} s a hit is stopped outright, never a boss's. | No single hit takes more than {cap}% of your max HP, and every {every} s one hit is blocked. |
| `gen.passive.rule.bible_boss_block` | No single hit takes more than {cap}% of your max HP ({boss}% from a boss). Once every {every} s a hit is stopped outright, never a boss's. | No single hit takes more than {cap}% of your max HP ({boss}% from a boss), and every {every} s one hit is blocked. |
| `gen.passive.rule.chest` | Every chest you open banks {effects} for the rest of the run; a later level raises only the chests after it. | Every chest you open gives {effects} for the rest of the run. |
| `gen.passive.rule.grave` | One kill in {every} leaves a grave; {rise} s later a ghost rises and circles it for {seconds} s, firing ghost bolts at the nearest enemies. The stronger you are, the more bolts (up to {bolts}) and the harder they hit; no knockback. At most {max} at once. | One kill in {every} leaves a grave, and a ghost rises from it to shoot enemies close by for {seconds} s. |
| `gen.passive.rule.grind` | Every level you take raises your weakest weapon a level (lowest level first, then least damage dealt). Once all are maxed, it evolves one that is ready. | Every level you take levels up your weakest weapon, or evolves one that is ready. |
| `gen.passive.rule.grind_once` | Once: your weakest weapon goes up a level (lowest level first, then least damage dealt); with every weapon maxed, one that is ready evolves. One per run; it never levels up. | Levels up your weakest weapon once, or evolves one that is ready. |
| `gen.passive.rule.purse` | +1% attack damage for every {per} gold in this run's purse. Spending lowers it. | +1% attack damage for every {per} gold you carry. |
| `gen.passive.rule.purse_cap` | +1% attack damage for every {per} gold in this run's purse, up to +{cap}%. Spending lowers it. | +1% attack damage for every {per} gold you carry, up to +{cap}%. |
| `gen.passive.rule.purse_cap_hp` | +1% attack damage for every {per} gold in this run's purse, up to +{cap}%; +1% max HP for every {hp} gold. Spending lowers it. | +1% attack damage for every {per} gold you carry, up to +{cap}%, and +1% max HP for every {hp} gold. |
| `gen.passive.rule.purse_hp` | +1% attack damage for every {per} gold in this run's purse; +1% max HP for every {hp} gold. Spending lowers it. | +1% attack damage for every {per} gold you carry, and +1% max HP for every {hp} gold. |
| `gen.passive.rule.storm` | Every {every} s storm clouds gather over you and for {seconds} s lightning strikes about {rate} times a second, mostly where enemies crowd: {damage} damage and a hard shove ({big} to Elites and bosses). | Every {every} s a storm gathers over you for {seconds} s, striking crowds with lightning for {damage} damage. |
| `gen.passive.rule.train` | Every {every} s a whistle blows and a ghost train charges down a track through you, the way you face. Everything on the rails takes {share}% of its max HP (Elites and bosses {big}%) + {damage} damage and is thrown aside. | Every {every} s a ghost train charges through, hitting every enemy on the rails for {share}% of its max HP + {damage} damage. |
| `passive.fools_gold.desc` | +1% attack damage for every {per} gold in this run's purse, up to +{cap}%. Spending lowers it. | +1% attack damage for every {per} gold you carry, up to +{cap}%. |
| `passive.grindstone.desc` | Once: your weakest weapon goes up a level (lowest level first, then least damage dealt); with every weapon maxed, one that is ready evolves. One per run; it never levels up. | Levels up your weakest weapon once, or evolves one that is ready. |
| `passive.iron_horse.desc` | Every {every} s a whistle blows and a ghost train charges down a track through you, the way you face. Everything on the rails takes {share}% of its max HP (Elites and bosses {big}%) + {damage} damage and is thrown aside. | Every {every} s a ghost train charges through, hitting every enemy on the rails for {share}% of its max HP + {damage} damage. |
| `passive.jade_key.desc` | Every chest you open banks {effects} for the rest of the run; a later level raises only the chests after it. | Every chest you open gives {effects} for the rest of the run. |
| `passive.lightning_in_a_bottle.desc` | Every critical hit throws an arc to up to {arcs} more enemies within {radius} m for {pct}% of the hit. Arcs never chain. | Critical hits arc to {arcs} more enemies close by for {pct}% of the hit. |
| `passive.personal_storm.desc` | Every {every} s storm clouds gather over you and for {seconds} s lightning strikes about {rate} times a second, mostly where enemies crowd: {damage} damage and a hard shove ({big} to Elites and bosses). | Every {every} s a storm gathers over you for {seconds} s, striking crowds with lightning for {damage} damage. |
| `passive.pocket_bible.desc` | No single hit takes more than {cap}% of your max HP. Once every {every} s a hit is stopped outright, never a boss's. | No single hit takes more than {cap}% of your max HP, and every {every} s one hit is blocked. |
| `passive.ruby_key.desc` | Every chest you open banks {effects} for the rest of the run; a later level raises only the chests after it. | Every chest you open gives {effects} for the rest of the run. |
| `passive.undertakers_shovel.desc` | One kill in {every} leaves a grave; {rise} s later a ghost rises and circles it for {seconds} s, firing ghost bolts at the nearest enemies. The stronger you are, the more bolts (up to {bolts}) and the harder they hit; no knockback. At most {max} at once. | One kill in {every} leaves a grave, and a ghost rises from it to shoot enemies close by for {seconds} s. |
| passive `assayers_scale` (`passives/assayers_scale/assayers_scale.json`) | Skipping a card or chest pays 25 coins and 5% of the next level's XP; levels raise both. Evolved: the pay doubles. | Skipping a card or chest pays 25 coins and 5% of a level's XP. |
| passive `barrel_rush` (`passives/barrel_rush/barrel_rush.json`) | Smash a barrel to run 30% faster for 4 s. Each rung after: +8% and +0.6 s more; Evolved +12% and +0.9 s. | Smash a barrel to run 30% faster for 4 s. |
| passive `canteen` (`passives/canteen/canteen.json`) | Water no longer slows you, and leaving it gives +3 HP a second for 15 s. Evolved: enemies in water take +25% damage from you. | Water no longer slows you, and leaving it heals 3 HP a second for 15 s. |
| passive `clover` (`passives/clover/clover.json`) | The Star smiles on you: +10% luck a level, so rarer items turn up more often in level-ups and chests. | +10% luck a level, so rarer items turn up more often. |
| passive `cold_snap` (`passives/cold_snap/cold_snap.json`) | A hit may freeze a creature for 1 second: blue, still and harmless. 3% at level 1, 11% once Evolved. Bosses shrug it off. | Hits have a 3% chance of freezing an enemy for 1 s. |
| passive `counterpunch` (`passives/counterpunch/counterpunch.json`) | After an evade, your next attack deals double damage, and for 2.5 s you attack 25% faster and move 20% faster. Evolved: 2.5 times. | After an evade, your next attack deals double damage and you attack and move faster for 2.5 s. |
| passive `desperado` (`passives/desperado/desperado.json`) | The more you are hurt, the harder you hit: +1.6% attack damage for every 10% of health you are missing at level 1 (+16% near death), up to +51% once Evolved. | The more you are hurt, the harder you hit: up to +16% attack damage near death. |
| passive `ducktape` (`passives/ducktape/ducktape.json`) | The sand runs slow for them: your burns, poison, slows, marks and pins last 15% longer a level. | Your burns, poison, slows, marks and pins last 15% longer a level. |
| passive `energy_shield` (`passives/energy_shield/energy_shield.json`) | The Guardian's blue bar over your health: while it holds, a hit takes shield and no HP; it recharges once you go 3 s untouched. | A blue shield over your health takes hits for you and recharges after 3 s untouched. |
| passive `evade` (`passives/evade/evade.json`) | The Ghost takes a hit for you now and then: a chance to take no hit at all, 3% at level 1, 20% at level 4. | Each hit has a 3% chance of missing you. |
| passive `gas_mask` (`passives/gas_mask/gas_mask.json`) | 1% damage reduction for every poisoned enemy, up to 12% (20% at level 2, 30% once Evolved). | 1% damage reduction for every poisoned enemy, up to 12%. |
| passive `guillotine` (`passives/guillotine/guillotine.json`) | Finishes the job: a creature left under the threshold by any of your hits dies on the spot. 9% of its health at level 1, 23% once Evolved. Bosses are spared. | Your hits finish off any enemy left under 9% health, except bosses. |
| passive `heavyweight` (`passives/heavyweight/heavyweight.json`) | +1.2% attack damage for every 10 max HP you have (+0.15% a rung, Evolved +0.25%). | +1.2% attack damage for every 10 max HP you have. |
| passive `hot_sauce` (`passives/hot_sauce/hot_sauce.json`) | The Devil deals you in: +25% difficulty a level. Dark variants and elite-marked creatures come more often: tougher, but each pays more XP and may drop a chest. | +25% difficulty a level: tougher enemies that pay more XP and may drop a chest. |
| passive `hot_springs` (`passives/hot_springs/hot_springs.json`) | +26 max HP and +0.65 HP regen a second. Every heal sends out a pulse that hurts enemies within 3 m: 5 damage, +2 for each HP healed, up to 40. | +26 max HP and +0.65 HP regen a second. Every heal hurts enemies close by. |
| passive `hot_streak` (`passives/hot_streak/hot_streak.json`) | Kills make you stronger for the rest of the run: +7% attack damage per 1,000 kills (more each rung), up to +100%. | +7% attack damage for every 1,000 kills this run, up to +100%. |
| passive `last_stand` (`passives/last_stand/last_stand.json`) | When a hit leaves you under 30% health, time slows for 2 s and you deal 2.3 times the damage (more each rung). | When a hit leaves you under 30% health, time slows and you deal 2.3 times the damage for 2 s. |
| passive `loose_change` (`passives/loose_change/loose_change.json`) | A hit has a 32% chance to knock a coin worth 10 gold out of you (+8% a rung, Evolved +12%). It lands a few steps away: go and get it. | Getting hit has a 32% chance of dropping a 10 gold coin close by. |
| passive `magnet` (`passives/magnet/magnet.json`) | Every few seconds, at random, pulls every EXP gem within 6 m to you. Rungs reach farther and pull more often. | Every few seconds pulls every EXP gem within 6 m to you. |
| passive `phoenix_feather` (`passives/phoenix_feather/phoenix_feather.json`) | Two seconds after you fall, you get back up at half health (more with Second Wind) with the revive's blast. Once a run; it never levels up. | When you fall, you get back up at half health. Once a run. |
| passive `pocket_watch` (`passives/pocket_watch/pocket_watch.json`) | Power-ups you pick up last 20% longer, more each rung (+76% once Evolved); at levels 1, 3 and Evolved they also drop more often (+14% in all). | Power-ups you pick up last 20% longer. |
| passive `powder_keg` (`passives/powder_keg/powder_keg.json`) | A kill has a 6.5% chance to blow up (+2% a rung, Evolved +3%): a twelfth of its max health to everything within 2.4 m, and a shove. Kills from the blast never blow. | Kills have a 6.5% chance of exploding, hurting everything close by. |
| passive `prospector` (`passives/prospector/prospector.json`) | The Miner digs for you: a kill may drop an extra XP gem, 6% a level. | Kills have a 6% chance a level of dropping an extra XP gem. |
| passive `siesta` (`passives/siesta/siesta.json`) | Standing still heals you: +1.4 health a second, more each rung. | Standing still heals you 1.4 health a second. |
| passive `skedaddle` (`passives/skedaddle/skedaddle.json`) | After a hit, run 25% faster for 2 s (+3% and +0.3 s a rung, Evolved +5% and +0.5 s). | After a hit, run 25% faster for 2 s. |
| passive `slow_burn` (`passives/slow_burn/slow_burn.json`) | The Ember keeps them burning: your burns, poison, slows, freezes and stuns last 20% longer a level. | Your burns, poison, slows, freezes and stuns last 20% longer a level. |
| passive `snake_oil` (`passives/snake_oil/snake_oil.json`) | Heals can fill your health past full, up to 25% of max HP more, shown pink on your health bar. Regen stops at full. | Heals can fill your health past full, up to 25% more. |
| passive `steady_hand` (`passives/steady_hand/steady_hand.json`) | The longer you stand still, the harder you hit: +13% attack damage a second (faster each rung), up to +100%. Moving drops it. | +13% attack damage for every second you stand still, up to +100%. Moving drops it. |
| passive `vulture` (`passives/vulture/vulture.json`) | A critical hit may heal you for 2% of your max health. 6% of crits at level 1, 20% once Evolved. | Critical hits have a 6% chance of healing you for 2% of your max health. |

215 rows and texts in all (124 en.json rows, 91 content texts).

## 5. Left exactly as you wrote them

Your four families, every text: the Basketball, Big Mouth, Dragon's Breath and Boomstick rows (`weapon.basketball.desc`, `weapon.big_mouth.desc`, `weapon.dragons_breath.desc`, `weapon.boomstick.desc`), their evolutions (`evolution.slam_dunk.desc`, `evolution.loudmouth.desc`, `evolution.fire_eater.desc`, `evolution.blunderbuss.desc`, `evolution.doomstick.desc`), every mutation of theirs (Alley-Oop, Free Throw, Full Court Press, On Fire, Rebound, Mouth Arch, Mouth Burn, Mouth Knock, Birdshot, Birdshot Lane, Both Barrels, Dragon's Breath, Slug, Backdraft, Blue Flame, Held Breath), your edited shared rows (`gen.weapon.ball.bounces`, `gen.weapon.breath.still`, `gen.weapon.laser`, `gen.weapon.launch`) and the shape rows only your families use (`gen.weapon.blast.lane`, `gen.weapon.blast.cone`, `gen.weapon.shot.forward`, `gen.weapon.ball.back`, `gen.weapon.breath.cone`, `gen.weapon.breath.ring`). A test (`pass138_texts_test.gd`) pins them byte for byte.

Also untouched: hidden mutations (not offered), the Outlaws' perks and traits, the generated stat lines ("+50% XP gain.").

## 6. Your typos, as suggestions only (not changed)

- `weapon.dragons_breath.desc`, `evolution.fire_eater.desc`: no full stop at the end.
- `gen.weapon.breath.still`, Both Barrels: no full stop at the end.
- Birdshot Lane: "curent" for "current"; "a quarter longer than the curent range takes" reads garbled; "Deals 40% less damage than a full point-blank volley" says 60% where the rule is 40% of a volley (`params.blast.frac` 0.4).
- Free Throw: "Every hit evade throw a ball." might read "Every evaded hit throws a ball.".
- Mouth Burn: "Beams lights enemies on fire" might read "The beam lights enemies on fire for 3 s.".
- Alley-Oop: says "creature" where the other texts say "enemy".

## 7. Doubts

- Your Basketball's Heat and Slam Dunk's dunk are no longer on its card (they were glued on, not your row). The ball shows its Heat; add a clause to your row if you want it on the card.
- Your Slam Dunk, Fire Eater and Loudmouth evolutions read exactly like their weapons now (your rows). Their own short lines would say what they add; I did not write over your rows.
- The pierce drop-off is explained nowhere now (the pause screen shows the pierce number only).
- Iron Bastion's note says "get stronger": Last Stand's blast grows, but Buddy Squad's doubled cap is set back to the Bastion's own six standing.
- Weapons aim where the Outlaw faces since pass 136; rows still say "at the strongest enemy nearby" (`gen.weapon.who.priority`), as before.
