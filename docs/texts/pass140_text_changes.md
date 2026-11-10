# Pass 140: every text I changed, and how

Written for Garry. Lane TEXTS, 2026-11-10. Tables made by `tools/dl/p140/TEXTS/make_changes.py` from the diffs, so no change is missed. The rules I wrote from your notes are in [`text_rules.md`](text_rules.md).

## 1. Your seven examples

| You wrote | The game now says (level 1) | Notes |
|---|---|---|
| Gravity Gun: "Picks up 1 enemy and throws them into a crowd for a 2m blast" | Picks up 1 enemy and throws them into a crowd for a 2 m blast that deals 18 damage. | Your words, then the damage (your note 6: every weapon says its damage). Its blast is **2.0 in the JSON** (was 1.9), the Singularity's too. With Repulsor the blast reads "3 m" (2.8). |
| Juggler: "Pick up 2 more, but deal -30% damage" | Pick up 2 more, but deal −30% damage. | The numbers are its effects (+2 amount, −30% damage). |
| Repulsor: "Thrown enemies deal a 40% wider blast and knock back enemies harder" | Thrown enemies deal a 40% wider blast and knock back enemies harder. | As written. |
| Singularity: "Creates a Black Hole that drags enemies in and deals N damage" | Creates a Black Hole that drags enemies in and deals 22 damage a second. | N is what the hole deals each second (its damage × `dps_frac`); "a second" added because it ticks for 3 s and pops at the end. |
| "All your mutations still apply" in a different cursive, less visible font | The note is now Rubik Italic at 78% of the description's size in a faded blue, under the evolution's line. | Every screen that draws a description (the chest, the cards, the Collection, the Outlaw sheet, the pause screen) gets it from the kit (`W.desc_text`); no screen draws its own. |
| Revolver: "Fires 1 shot at an enemy withing 14m for N damage" | Fires 1 shot at an enemy within 14 m for 20 damage. | "within" for "withing"; N is its damage with your bonuses in it. |
| Hip Shot: "Every 5th pull fires 3 shots in a row" | Every 5th pull fires 3 shots in a row. | As written. |

One thing I did not copy letter for letter: you typed "2m" and "14m"; every other text in the game, your own rows too ("Shoots a 13 m long beam", "for 3 s"), writes a space before the unit, so these two do as well. If you prefer "2m" everywhere, it is one sweep over the rows and the change rows: say so.

## 2. What changed everywhere

- **Every weapon says the damage it deals**, as a variable (`{damage}`, the weapon's damage with your bonuses), at the end of its row: "for 20 damage", "for 3 damage each" (a burst), "for 5 damage a sting" (the bees), "4 damage a shot" (turrets), "damage a second" (the black hole). Evolutions say it too where it fits. Your four families do not yet (section 5: suggestions).
- **Lengths in whole metres** in an item's own description ("2 m", never "1.9 m"); upgrade rows keep their decimals. Where a blast or patch size was secondary and would round far (the Hammer's 1.6, the rockets' 1.5, the Sun Scepter's 1.3, the Salt's 1.4), I left it out of the row rather than show a wrong whole number; the upgrade rows still show it exactly.
- **Times** without a trailing ".0" ("every 6 s", "every 2.2 s").
- **A number keeps its unit on its line**: the description face no longer wraps "14" and "m" onto two lines (the pause screen's Revolver did).
- **Counts as digits**: "Fires 1 shot", "Drops 1 mine", "Lob 2 more", "×2", "Every 4th burst" (never "a", "two", "twice", "double", "fourth").
- **"an enemy"**: weapons aim where you face since pass 136, so rows no longer promise "the strongest enemy nearby" or "the nearest enemy".
- **The game's words for actions**: "deal damage", "knock back", "explode" (not "blow"), "crit chance", "range", "cooldown"; "enemies" (never "creatures"); "you" (never "his").
- **Mutations in your Juggler pattern**: the gain, then the price after "but" ("Fire 2 more darts, but deal −30% damage.").

## 3. Every row and text that changed

`key | before | after`. Rows of `game/content/strings/en.json`; content texts name their file.


### Branding Iron family

| Row or text | Before | After |
|---|---|---|
| `weapon.branding_iron.desc` | {amount?A hot branding iron circles:{amount} hot branding irons circle} you and set{amount?s:} enemies on fire. | {amount} hot branding {amount?iron circles:irons circle} you, dealing {damage} damage and setting enemies on fire. |
| `evolution.ring_of_fire.desc` | {amount} branding irons circle you in a ring of fire, burning every enemy they touch. | {amount} branding irons circle you in a ring of fire, dealing {damage} damage and burning every enemy they touch. |
| mutation `twin_irons` (Twin Irons) | +2 irons, −30% damage. | 2 more irons, but deal −30% damage. |

### Flare Gun family

| Row or text | Before | After |
|---|---|---|
| `weapon.flare_gun.desc` | Fires {amount} {amount?flare that sets:flares that set} enemies on fire. | Fires {amount} {amount?flare:flares} for {damage} damage that {amount?sets:set} enemies on fire. |
| `evolution.roman_candle.desc` | Fires a volley of {amount} flares that set enemies on fire. | Fires a volley of {amount} flares for {damage} damage that set enemies on fire. |
| mutation `flare_volley` (Flare Volley) | Three flares a shot, −35% damage. | Fire 2 more flares, but deal −35% damage. |
| mutation `sky_flare` (Sky Flare) | Flares burst into embers that rain down around what they hit. | Flares burst into 5 embers that rain down around what they hit. |

### Frisbee family

| Row or text | Before | After |
|---|---|---|
| `weapon.frisbee.desc` | Throws {amount?a frisbee that curves:{amount} frisbees that curve} through every enemy in the way. | Throws {amount} {amount?frisbee that curves:frisbees that curve} through every enemy in the way for {damage} damage. |
| `evolution.flying_saucer.desc` | Throws {amount?a glowing saucer that loops:{amount} glowing saucers that loop} once and {amount?cuts:cut} through every enemy in the way. | Throws {amount} glowing {amount?saucer that loops:saucers that loop} once and {amount?cuts:cut} through every enemy in the way for {damage} damage. |

### Gravity Gun family

| Row or text | Before | After |
|---|---|---|
| `weapon.gravity_gun.desc` | Picks up {amount} {amount?enemy:enemies} and throws {amount?it:them} into the thickest crowd for a {blast} m blast. | Picks up {amount} {amount?enemy:enemies} and throws them into a crowd for a {blast} m blast that deals {damage} damage. |
| `evolution.singularity.desc` | Lobs {amount?a black hole that drags enemies in, eats them, then pops:{amount} black holes that drag enemies in, eat them, then pop}. | Creates {amount?a Black Hole that drags:{amount} Black Holes that drag} enemies in and {amount?deals:deal} {damage} damage a second. |
| mutation `juggler` (Juggler) | Picks up two more at once, −30% damage. | Pick up 2 more, but deal −30% damage. |
| mutation `repulsor` (Repulsor) | Landings throw enemies harder in a 40% wider blast. | Thrown enemies deal a 40% wider blast and knock back enemies harder. |
| mutation `slingshot` (Slingshot) | The thrown enemy skips on to the next crowd for a second blast. | Thrown enemies bounce on to the next crowd for another blast at 60% damage. |

### Guitarra family

| Row or text | Before | After |
|---|---|---|
| `weapon.guitarra.desc` | Strums a {deg}° cone of melody that lifts enemies into the air{amount?:, {amount} times in a row}. | Strums a {deg}° cone of melody that deals {damage} damage and lifts enemies into the air{amount?:, {amount} times in a row}. |
| `evolution.requiem.desc` | Strums a full ring of melody that lifts every enemy around you into the air. | Strums a full ring of melody that deals {damage} damage and lifts every enemy around you into the air. |
| mutation `ember_chord` (Ember Chord, hidden) | Every chord sets what it lifts alight. | Chords set enemies on fire. |
| mutation `far_reach` (Far Reach) | The melody covers half a circle and reaches 50% further, for half the damage. | Strum a 180° arc with +50% range, but deal −50% damage. |
| mutation `music_slap` (Music Slap) | Chords slap enemies aside for 60% more damage, but strum 40% slower. | Chords knock back enemies and deal +60% damage, but strum 40% slower. |
| mutation `tinnitus` (Tinnitus) | Every third hit on the same enemy deals double damage. | Every 3rd hit on the same enemy deals ×2 damage. |

### Hammer family

| Row or text | Before | After |
|---|---|---|
| `weapon.hammer.desc` | Slams {amount?a hammer:{amount} hammers} down on the thickest crowd, throwing enemies out of a {blast} m blast. | Slams {amount} {amount?hammer:hammers} down on the densest crowd for {damage} damage. |
| `evolution.earthshaker.desc` | Slams {amount} hammers down on the thickest crowd, splitting the ground in lightning cracks. | Slams {amount} {amount?hammer:hammers} down on the densest crowd for {damage} damage, splitting the ground in lightning cracks. |
| `evolution.earthshaker_v47.desc` | Slams {amount} hammers down on the thickest crowd, splitting the ground in cracks. | Slams {amount} {amount?hammer:hammers} down on the densest crowd for {damage} damage, splitting the ground in cracks. |
| mutation `aftershock` (Aftershock) | Every impact sends out a second shockwave twice as wide. | Every impact sends out another shockwave ×2 as wide that deals 40% of the damage. |
| mutation `giant_slayer` (Giant Slayer) | Impacts have a 50% chance of dealing 2.5 times the damage to bosses and Elites. | Impacts have a 50% chance of dealing ×2.5 damage to bosses and Elites. |
| mutation `hammer_rain` (Hammer Rain, hidden) | Two more hammers a stroke, −35% damage. | Slam 2 more hammers, but deal −35% damage. |

### Killer Bees family

| Row or text | Before | After |
|---|---|---|
| `weapon.hornet_nest.desc` | Sends {amount} killer {amount?bee:bees} after {prey} within {range} m. | Sends {amount} killer {amount?bee:bees} after enemies within {range} m for {damage} damage a sting. |
| `evolution.hive_queen.desc` | Sends {amount} killer bees and a Tarantula Hawk with every burst. | Sends {amount} killer bees and a Tarantula Hawk with every burst, {damage} damage a sting. |
| `evolution.killer_swarm.desc` | Sends a swarm of {amount} killer bees after {prey}. | Sends a swarm of {amount} killer bees after enemies for {damage} damage a sting. |
| mutation `ember_hornets` (Ember Bees, hidden) | Stings burn. | Stings set enemies on fire. |
| mutation `pollen` (Pollen) | Flowers grow from the sand; walk into one for 4 times the bees for 5 s. | Flowers grow from the sand: walk into one for ×4 bees for 5 s. |
| mutation `swarm` (Swarm, hidden) | +6 bees, −60% damage each, cooldown −30%. | Send 6 more bees with −30% cooldown, but deal −60% damage. |
| mutation `tarantula_hawk` (Tarantula Hawk) | Every fourth burst also sends a Tarantula Hawk that stings the strongest enemy five times. | Every 4th burst also sends a Tarantula Hawk that stings the strongest enemy 5 times. |

### Land Mine family

| Row or text | Before | After |
|---|---|---|
| `weapon.land_mine.desc` | Drops {amount?a mine:{amount} mines} every {cooldown} s that {amount?blows:blow} up in a {area} m blast when an enemy steps on {amount?it:them}. | Drops {amount} {amount?mine:mines} every {cooldown} s that {amount?explodes:explode} for {damage} damage when an enemy steps on {amount?it:them}. |
| `evolution.jackrabbit_mines.desc` | Drops {amount?a mine:{amount} mines} every {cooldown} s that {amount?jumps:jump} at enemies within {sense} m, then {amount?hops:hop} on to another. | Drops {amount} {amount?mine:mines} every {cooldown} s that {amount?jumps:jump} at enemies within {sense} m for {damage} damage, then {amount?hops:hop} on to another. |
| `evolution.minefield.desc` | Drops {amount?a mine:{amount} mines} every {cooldown} s, covering the ground in mines. | Drops {amount} {amount?mine:mines} every {cooldown} s, covering the ground in mines that deal {damage} damage. |
| mutation `blasting_cap` (Blasting Cap) | Mines that kill drop a gold nugget and blow 25% wider. | Mines that kill drop a gold nugget and explode 25% wider. |
| mutation `bouncing_betty` (Bouncing Betty) | Mines leap and burst at chest height in a bigger blast. | Mines leap up and explode in a 50% wider blast. |
| mutation `cluster_mines` (Cluster Mines, hidden) | Two mines a drop, twice as many on the ground, −40% damage. | Drop 1 more mine and keep ×2 on the ground, but deal −40% damage. |
| mutation `extra_supply` (Extra Supply) | One drop in four lays twice as many mines. | 1 drop in 4 lays ×2 mines. |
| mutation `wide_reach` (Wide Reach) | Mines jump at enemies close by and blow where they land. | Mines jump at enemies close by and explode where they land. |

### Lob Grenade family

| Row or text | Before | After |
|---|---|---|
| `weapon.lob_grenade.desc` | Lobs {amount} {thing} at the densest crowd. Explodes in a {area} m radius. | Lobs {amount} {thing} at the densest crowd. Explodes in a {area} m radius for {damage} damage. |
| `evolution.cluster_bomb.desc` | Lobs {amount} {thing} at the densest crowd that burst into small bombs. | Lobs {amount} {thing} at the densest crowd for {damage} damage that burst into small bombs. |
| `evolution.golden_pineapple.desc` | Lobs {amount} golden {thing} that stick to the strongest enemy, then explode in a {area} m radius. | Lobs {amount} golden {thing} that stick to the strongest enemy, then explode in a {area} m radius for {damage} damage. |
| mutation `frag` (Frag) | The burst throws six steel spikes out past the blast. | Explosions throw 6 steel spikes out past the blast. |
| mutation `new_equipment` (New Equipment) | A bigger grenade: +20% damage, +20% area and +30% knockback. | Deal +20% damage in a 20% wider blast and knock back enemies harder. |
| mutation `sticky` (Sticky) | Sticks to the first enemy it lands near and rides it into the crowd before it blows. | Sticks to the first enemy it lands near and rides it into the crowd before it explodes. |
| mutation `frag` look B (Frag) | The burst throws six wire barbs out past the blast. | Explosions throw 6 wire barbs out past the blast. |
| mutation `frag` look C (Frag) | The burst throws six coffin nails out past the blast. | Explosions throw 6 coffin nails out past the blast. |
| mutation `frag` look D (Frag) | The burst throws six coffin nails out past the blast. | Explosions throw 6 coffin nails out past the blast. |
| mutation `new_equipment` look B (New Equipment) | A bigger bundle of sticks: +20% damage, +20% area and +30% knockback. | A bigger bundle of sticks deals +20% damage in a 20% wider blast and knocks back enemies harder. |
| mutation `new_equipment` look C (New Equipment) | A bigger bundle of sticks: +20% damage, +20% area and +30% knockback. | A bigger bundle of sticks deals +20% damage in a 20% wider blast and knocks back enemies harder. |
| mutation `new_equipment` look D (New Equipment) | A bigger bundle of sticks: +20% damage, +20% area and +30% knockback. | A bigger bundle of sticks deals +20% damage in a 20% wider blast and knocks back enemies harder. |

### Molotov family

| Row or text | Before | After |
|---|---|---|
| `weapon.molotov.desc` | Lobs {amount} {thing} of fire at the thickest crowd. Leaves a {area} m pool of flames. | Lobs {amount} {thing} of fire at the densest crowd for {damage} damage. Leaves a {area} m pool of flames. |
| `evolution.firestorm.desc` | Lobs {amount} {thing} of fire that leave big pools of flames. | Lobs {amount} {thing} of fire for {damage} damage, leaving big pools of flames. |
| `evolution.moonshine.desc` | Lobs {amount} {thing} of blue fire that leave a burning trail and long-lasting pools. | Lobs {amount} {thing} of blue fire for {damage} damage, leaving a burning trail and long-lasting pools. |
| mutation `accelerant` (Accelerant) | Flames last twice as long, and burning enemies spread the fire when they die. | Pools of flames last ×2 as long, and burning enemies spread the fire when they die. |
| mutation `bar_fight` (Bar Fight, hidden) | Three bottles, smaller clouds, −30% damage. | Lob 2 more bottles, but deal −30% damage in smaller pools. |
| mutation `methanol` (Methanol) | The fire burns blue: 50% bigger pools and longer burns, for 20% less burn damage. | The fire burns blue: 50% bigger pools and 75% longer burns, but −20% burn damage. |
| mutation `oil_slick` (Oil Slick) | The bottle leaves a trail of burning oil that slows enemies. | The bottle leaves a trail of burning oil that slows enemies by 35%. |

### Orbit Saws family

| Row or text | Before | After |
|---|---|---|
| `weapon.orbit_saws.desc` | {amount?A saw blade circles you and cuts:{amount} saw blades circle you and cut} every enemy in the way. | {amount} saw {amount?blade circles:blades circle} you and {amount?cuts:cut} every enemy in the way for {damage} damage. |
| `evolution.saw_halo.desc` | {amount} saw blades spin round you in a solid ring that cuts everything it touches. | {amount} saw blades spin round you in a solid ring that deals {damage} damage to everything it touches. |
| mutation `rust` (Rust) | Cuts poison. | Saws poison every enemy they cut. |
| mutation `saw_swarm` (Saw Swarm) | +3 saws, −35% damage, ×1.5 spin. | 3 more saws that spin ×1.5 as fast, but deal −35% damage. |

### Peashooter family

| Row or text | Before | After |
|---|---|---|
| `weapon.peashooter.desc` | Fires {amount} {amount?pea:peas} at {who} within {range} m. | Fires {amount} {amount?pea:peas} at an enemy within {range} m for {damage} damage. |
| `evolution.bullet_hose.desc` | Sprays a nonstop stream of peas at {who} within {range} m. | Sprays a nonstop stream of peas at an enemy within {range} m for {damage} damage each. |
| `evolution.pea_cannon.desc` | Fires {amount} giant toxic {amount?pea:peas} at {who} that bounce on to {bounces} more enemies. | Fires {amount} giant toxic {amount?pea:peas} for {damage} damage that bounce on to {bounces} more enemies. |
| mutation `big_peas` (Big Peas) | Bigger peas: +35% damage and twice the knockback. | Bigger peas deal +35% damage and knock back enemies ×2 as hard. |
| mutation `bouncing_peas` (Bouncing Peas) | Every pea bounces on to a second enemy. | Every pea bounces on to 1 more enemy. |
| mutation `fan_the_hammer` (Fan the Hammer, hidden) | Two shots a cooldown at −25% damage. | Fire 2 shots a cooldown, but deal −25% damage. |
| mutation `pea_hose` (Pea Hose, hidden) | +3 peas a shot, −40% damage, cooldown −20%. | Fire 3 more peas with −20% cooldown, but deal −40% damage. |

### Poison Dart family

| Row or text | Before | After |
|---|---|---|
| `weapon.poison_dart.desc` | Fires {amount} poison {amount?dart:darts} at an enemy that is not poisoned yet. | Fires {amount} poison {amount?dart:darts} for {damage} damage at enemies not yet poisoned. |
| `evolution.plague_volley.desc` | Fires a volley of {amount} poison darts at enemies that are not poisoned yet. | Fires a volley of {amount} poison darts for {damage} damage at enemies not yet poisoned. |
| mutation `blowgun_burst` (Blowgun Burst) | Three darts a shot, −30% damage. | Fire 2 more darts, but deal −30% damage. |

### Rattlesnake family

| Row or text | Before | After |
|---|---|---|
| `weapon.rattlesnake.desc` | {amount?A rattlesnake circles you and bites:{amount} rattlesnakes circle you and bite} enemies, poisoning them. | {amount} {amount?rattlesnake circles:rattlesnakes circle} you and {amount?bites:bite} enemies for {damage} damage, poisoning them. |
| `evolution.snake_pit.desc` | {amount} rattlesnakes circle you fast, poisoning every enemy they bite. | {amount} rattlesnakes circle you fast, biting enemies for {damage} damage and poisoning them. |
| mutation `nest` (Nest) | +2 snakes, −25% damage. | 2 more snakes, but deal −25% damage. |
| mutation `strike` (Strike) | Every 2 s a snake lunges at an enemy outside the ring for double damage. | Every 2 s a snake lunges at an enemy outside the ring for ×2 damage. |

### Revolver family

| Row or text | Before | After |
|---|---|---|
| `weapon.revolver.desc` | Fires {amount} {amount?shot:shots} at {who} within {range} m. | Fires {amount} {amount?shot:shots} at an enemy within {range} m for {damage} damage. |
| `evolution.golden_revolver.desc` | Fires {amount} silver {amount?bullet:bullets} at {who} that ricochet {bounces} {bounces?time:times}. Every {hip_nth} pull is a hip shot. | Fires {amount} silver {amount?bullet:bullets} for {damage} damage that ricochet {bounces} {bounces?time:times}. Every {hip_nth} pull is a hip shot. |
| `evolution.golden_revolver_v47.desc` | Fires {amount} golden {amount?bullet:bullets} at {who} within {range} m. | Fires {amount} golden {amount?bullet:bullets} at an enemy within {range} m for {damage} damage. |
| mutation `hip_shot` (Hip Shot) | Every fifth pull fires three volleys in a row. | Every 5th pull fires 3 shots in a row. |
| mutation `silver_bullet` (Silver Bullet) | Bigger silver bullets: +50% damage and +1 pierce. | Bigger silver bullets deal +50% damage and pierce 1 more enemy. |
| mutation `six_shooter` (Six-Shooter, hidden) | Three more rounds a pull, fired in a quick string, −40% damage. | Fire 3 more rounds a pull, but deal −40% damage. |

### Rocket Pod family

| Row or text | Before | After |
|---|---|---|
| `weapon.rocket_pod.desc` | Launches {amount} homing {amount?rocket:rockets} at {prey}. {amount?It explodes:Each explodes} in a {blast} m radius. | Launches {amount} homing {amount?rocket:rockets} that {amount?explodes:explode} for {damage} damage. |
| `evolution.hellfire_battery.desc` | Launches {amount} homing rockets. Every blast scatters bomblets that set each other off. | Launches {amount} homing rockets for {damage} damage. Every blast scatters bomblets that set each other off. |
| `evolution.missile_massacre.desc` | Launches {amount} homing rockets that fill the sky. | Launches {amount} homing rockets that fill the sky, {damage} damage each. |
| mutation `bunker_buster` (Bunker Buster, hidden) | One rocket: ×3 damage, ×1.8 area of effect, ×2 knockback. | Fire 1 rocket that deals ×3 damage in a ×1.8 blast and knocks back enemies ×2 as hard. |
| mutation `cluster_munitions` (Cluster Munitions) | Blasts have a 30% chance of scattering bomblets that pop when stepped on. | Blasts have a 30% chance of scattering 5 bomblets that explode when stepped on. |
| mutation `heavy_warhead` (Heavy Warhead) | Bigger rockets: +40% damage, double knockback and a 15% bigger blast. | Bigger rockets deal +40% damage in a 15% wider blast and knock back enemies harder. |
| mutation `salvo` (Salvo, hidden) | +3 rockets a volley, −35% damage. | Launch 3 more rockets, but deal −35% damage. |
| mutation `thermobaric` (Thermobaric, hidden) | The blast ignites. | Blasts set enemies on fire. |

### Sabre family

| Row or text | Before | After |
|---|---|---|
| `weapon.sabre.desc` | Slashes a {deg}° arc at {who}{amount?:, {amount} times a swing}. | Slashes a {deg}° arc for {damage} damage{amount?:, {amount} times a swing}. |
| `evolution.whirlwind.desc` | Spins a full circle {amount?once:{amount} times} a swing. Crits give back part of the cooldown. | Spins a full circle for {damage} damage{amount?:, {amount} times a swing}. Crits give back part of the cooldown. |
| `evolution.zweihander.desc` | Swings a huge {deg}° slash {amount?once:{amount} times} a swing. | Swings a huge {deg}° slash for {damage} damage{amount?:, {amount} times a swing}. |
| mutation `critical_thinking` (Critical Thinking) | +10% critical hit chance for every weapon. | +10% crit chance for every weapon. |
| mutation `flame_blade` (Flame Blade, hidden) | Cuts burn. | Slashes set enemies on fire. |
| mutation `flurry` (Flurry) | Twice as many slashes a swing. | ×2 slashes a swing. |
| mutation `riposte` (Riposte) | Swings come 25% faster and knock enemies twice as far. | Swing 25% faster and knock back enemies ×2 as far. |

### Salt family

| Row or text | Before | After |
|---|---|---|
| `weapon.salt.desc` | Pours {amount?a patch:{amount} patches} of salt ({radius} m) behind you every {cooldown} s. Enemies in the salt take {damage} damage every {tick} s. | Pours {amount} {amount?patch:patches} of salt behind you every {cooldown} s. Enemies in the salt take {damage} damage every {tick} s. |
| `evolution.hiwa_kai.desc` | Pours black lava salt behind you that slows enemies and bites hard when they step in. | Pours black lava salt behind you that slows enemies and bites hard when they step in. Enemies in it take {damage} damage every {tick} s. |
| mutation `sea_salt` (Sea Salt) | The salt turns pink and lasts 75% longer, for 5% less damage. | The salt turns pink and lasts 75% longer, but deals −5% damage. |
| mutation `thing_about_luck` (Thing About Luck) | An enemy killed in the salt is 3 times as likely to drop a power-up. | Enemies killed in the salt are ×3 as likely to drop a power-up. |

### Skull Rain family

| Row or text | Before | After |
|---|---|---|
| `weapon.skull_rain.desc` | Lobs {amount} poison {thing} at the thickest crowd. Leaves a {area} m cloud of poison. | Lobs {amount} poison {thing} at the densest crowd for {damage} damage. Leaves a {area} m cloud of poison. |
| `evolution.dia_de_muertos.desc` | Lobs {amount} poison {thing} that leave long-lasting clouds of poison. | Lobs {amount} poison {thing} for {damage} damage, leaving long-lasting clouds of poison. |
| `evolution.grave_hail.desc` | Lobs {amount} poison {thing} that bounce on, leaving a poison cloud at every landing. | Lobs {amount} poison {thing} for {damage} damage that bounce on, leaving a poison cloud at every landing. |
| mutation `bone_storm` (Bone Storm, hidden) | +3 skulls, −30% damage. | Lob 3 more skulls, but deal −30% damage. |
| mutation `bouncing_skull` (Bouncing Skull) | Skulls bounce on twice after the blast, leaving a smaller blast and cloud each time. | Skulls bounce on 2 more times, leaving a smaller blast and cloud each time. |
| mutation `homing_skulls` (Homing Skulls, hidden) | The skulls seek. | Skulls home in on enemies. |
| mutation `plague` (Plague) | Every skull leaves poison smoke that stacks. | +1 poison stack, and poison clouds last longer. |

### Spear family

| Row or text | Before | After |
|---|---|---|
| `weapon.pike.desc` | Thrusts {amount?a spear:{amount} spears} at {who} within {range} m. | Thrusts {amount} {amount?spear:spears} at an enemy within {range} m for {damage} damage. |
| `evolution.halberd.desc` | Swings {amount} halberd blades in a wide fan at {who}. | Swings {amount} halberd blades in a wide fan for {damage} damage. |
| `evolution.thunder_lance.desc` | Sweeps {amount} lances in a {deg}° arc, then thrusts. Every hit stuns. | Sweeps {amount} lances in a {deg}° arc for {damage} damage, then thrusts. Every hit stuns. |
| mutation `long_spear` (Long Spear) | +40% reach, strokes 15% slower. | +40% range, but thrusts 15% slower. |
| mutation `phalanx` (Phalanx, hidden) | Three spears fanned, −35% damage. | Thrust 2 more spears in a fan, but deal −35% damage. |
| mutation `venom_tip` (Venom Tip, hidden) | Poison. | Thrusts poison enemies. |

### Sun Scepter family

| Row or text | Before | After |
|---|---|---|
| `weapon.sun_scepter.desc` | Calls {amount?a pillar:{amount} pillars} of sunlight down on random enemies every {cooldown} s, {damage} damage in a {radius} m radius. | Calls {amount} {amount?pillar:pillars} of sunlight down on random enemies every {cooldown} s for {damage} damage. |
| `evolution.zenith.desc` | Calls {amount} pillars of sunlight down every {cooldown} s. Every {nth} strike hits every enemy on screen. | Calls {amount} pillars of sunlight down every {cooldown} s for {damage} damage. Every {nth} strike hits every enemy on screen. |
| mutation `flicker` (Flicker) | Strikes 30% sooner for 25% less damage. | −30% cooldown, but deal −25% damage. |

### Throwing Spear family

| Row or text | Before | After |
|---|---|---|
| `weapon.spear.desc` | Throws {amount?a spear:{amount} spears} {range} m through every enemy in the way. | Throws {amount} {amount?spear:spears} {range} m through every enemy in the way for {damage} damage. |
| `evolution.war_lance.desc` | Throws {amount?a spear:{amount} spears} through every enemy in the way, leaving a trail of slowing dust. | Throws {amount} {amount?spear:spears} through every enemy in the way for {damage} damage, leaving a trail of slowing dust. |
| mutation `spear_volley` (Spear Volley) | Throws three spears for every one, −40% damage each. | Throw ×3 spears, but deal −40% damage. |

### Tommy Gun family

| Row or text | Before | After |
|---|---|---|
| `weapon.tommy_gun.desc` | Fires a burst of {amount} {amount?round:rounds} at {who} within {range} m. | Fires a burst of {amount} {amount?round:rounds} at an enemy within {range} m for {damage} damage each. |
| `evolution.chicago_typewriter.desc` | Fires a long burst of {amount} rounds at {who} within {range} m. | Fires a long burst of {amount} rounds at an enemy within {range} m for {damage} damage each. |
| mutation `drum_mag` (Drum Mag) | Twice the burst, −35% a round. | Fire 6 more rounds a burst, but deal −35% damage. |
| mutation `mini_crits` (Mini Crits) | A quarter of the rounds are mini crits. | 25% of rounds are mini crits. |
| mutation `tracer_rounds` (Tracer Rounds, hidden) | The rounds ignite. | Rounds set enemies on fire. |
| mutation `trigger_happy` (Trigger Happy) | The Tommy Gun never stops firing, spraying a steady stream of weaker rounds. | The Tommy Gun never stops firing: a steady stream of rounds that deal −35% damage. |
| mutation `drum_roll` (Drum Roll, hidden) | +1 round in the burst for every notch of his charge (+4 at full). | +1 round a burst for every notch of charge, +4 at full. |

### Tumbleweed family

| Row or text | Before | After |
|---|---|---|
| `weapon.tumbleweed.desc` | Rolls {amount?a tumbleweed:{amount} tumbleweeds} {range} m out through every enemy in the way. | Rolls {amount} {amount?tumbleweed:tumbleweeds} {range} m out through every enemy in the way for {damage} damage. |
| `evolution.dust_devil.desc` | Rolls {amount} thorny tumbleweeds out and back twice, hitting harder on the way back. | Rolls {amount} thorny tumbleweeds out and back 2 times for {damage} damage, hitting harder on the way back. |
| `evolution.stampede.desc` | Rolls {amount} tumbleweeds out in a wide fan through every enemy in the way. | Rolls {amount} tumbleweeds out in a wide fan through every enemy in the way for {damage} damage. |
| mutation `boomerang` (Boomerang) | Rolls out and comes back through the crowd. | The tumbleweed comes back through the crowd. |
| mutation `dust_wake` (Dust Wake) | Leaves a dust wake that slows enemies a little. | Leaves a dust wake that slows enemies by 20%. |
| mutation `thorns` (Thorny Weed) | Heavier and thornier: +35% damage. | Heavier, thornier tumbleweeds deal +35% damage. |
| mutation `weed_storm` (Weed Storm, hidden) | Three smaller weeds, −30% damage. | Roll 2 more smaller tumbleweeds, but deal −30% damage. |

### Turret Buddy family

| Row or text | Before | After |
|---|---|---|
| `weapon.turret_buddy.desc` | Drops {amount?a turret:{amount} turrets} every {cooldown} s. {amount?It shoots:They shoot} {who} for {seconds} s. | Drops {amount} {amount?turret:turrets} every {cooldown} s. {amount?It shoots:They shoot} enemies for {seconds} s, {damage} damage a shot. |
| `evolution.iron_bastion.desc` | Drops {amount?an armoured bunker:{amount} armoured bunkers} every {cooldown} s that explode when they go. | Drops {amount} armoured {amount?bunker:bunkers} every {cooldown} s that {amount?shoots:shoot} for {damage} damage and {amount?explodes:explode} when {amount?it goes:they go}. |
| `evolution.turret_family.desc` | Drops {amount} turrets every {cooldown} s that never leave and pull gems to you. | Drops {amount} turrets every {cooldown} s that never leave, shoot for {damage} damage and pull gems to you. |
| mutation `buddy_squad` (Buddy Squad) | Twice the turrets a drop and twice as many standing, −40% damage each. | Drop ×2 turrets and keep ×2 standing, but deal −40% damage. |
| mutation `bunker` (Bunker) | The turret digs in behind sandbags: twin barrels and +40% damage. | Turrets dig in behind sandbags with 2 barrels, deal +40% damage and knock back enemies harder. |
| mutation `dart_buddy` (Dart Buddy, hidden) | It spits poison. | Turrets spit poison. |
| mutation `last_stand` (Last Stand) | A turret explodes when it goes, a 3 m blast. | Turrets explode in a 3 m blast when they go, dealing ×4 damage. |

### Zap Beam family

| Row or text | Before | After |
|---|---|---|
| `weapon.zap_beam.desc` | Zaps a random enemy within {range} m and chains to {chains} more. | Zaps a random enemy within {range} m for {damage} damage and chains to {chains} more. |
| `evolution.storm_cloud.desc` | A storm cloud follows you, zapping enemies within {range} m and chaining to {chains} more. | A storm cloud follows you, zapping enemies within {range} m for {damage} damage and chaining to {chains} more. |
| mutation `fork` (Fork) | +2 chains, −25% damage. | Chain to 2 more, but deal −25% damage. |

### Passive items

| Row or text | Before | After |
|---|---|---|
| passive `counterpunch` (Counterpunch) | After an evade, your next attack deals double damage and you attack and move faster for 2.5 s. | After an evade, your next attack deals ×2 damage and you attack and move faster for 2.5 s. |
| passive `hot_springs` (Hot Springs) | +26 max HP and +0.65 HP regen a second. Every heal hurts enemies close by. | +26 max HP and +0.65 HP regen a second. Every heal deals 5 damage to enemies close by. |
| passive `last_stand` (Last Stand) | When a hit leaves you under 30% health, time slows and you deal 2.3 times the damage for 2 s. | When a hit leaves you under 30% health, time slows and you deal ×2.3 damage for 2 s. |
| passive `powder_keg` (Powder Keg) | Kills have a 6.5% chance of exploding, hurting everything close by. | Kills have a 6.5% chance of exploding, dealing damage to everything close by. |
| passive `siesta` (Siesta) | Standing still heals you 1.4 health a second. | Standing still heals you 1.4 HP a second. |
| passive `vulture` (Vulture) | Critical hits have a 6% chance of healing you for 2% of your max health. | Critical hits have a 6% chance of healing you for 2% of your max HP. |

### Shared rows (a shape's own words, used when a mutation changes it)

| Row or text | Before | After |
|---|---|---|
| `gen.weapon.gravity.throw` | Picks up {amount} {amount?enemy:enemies} and throws {amount?it:them} into the thickest crowd for a {blast} m blast. | Picks up {amount} {amount?enemy:enemies} and throws them into a crowd for a {blast} m blast that deals {damage} damage. |
| `gen.weapon.gravity.hole` | Lobs {amount?a black hole that drags enemies in, eats them, then pops:{amount} black holes that drag enemies in, eat them, then pop}. | Creates {amount?a Black Hole that drags:{amount} Black Holes that drag} enemies in and {amount?deals:deal} {damage} damage a second. |
| `gen.weapon.cone.cone` | Strums a {deg}° cone of melody that lifts enemies into the air{amount?:, {amount} times in a row}. | Strums a {deg}° cone of melody that deals {damage} damage and lifts enemies into the air{amount?:, {amount} times in a row}. |
| `gen.weapon.cone.ring` | Strums a ring of melody that lifts every enemy around you into the air. | Strums a ring of melody that deals {damage} damage and lifts every enemy around you into the air. |
| `gen.weapon.frisbee` | Throws {amount?a frisbee that curves:{amount} frisbees that curve} through every enemy in the way. | Throws {amount} {amount?frisbee that curves:frisbees that curve} through every enemy in the way for {damage} damage. |
| `gen.weapon.lob.blast` | Lobs {amount} {thing} at the densest crowd. Explodes in a {area} m radius. | Lobs {amount} {thing} at the densest crowd. Explodes in a {area} m radius for {damage} damage. |
| `gen.weapon.lob.fire` | Lobs {amount} {thing} of fire at the thickest crowd. Leaves a {area} m pool of flames. | Lobs {amount} {thing} of fire at the densest crowd for {damage} damage. Leaves a {area} m pool of flames. |
| `gen.weapon.lob.poison` | Lobs {amount} poison {thing} at the thickest crowd. Leaves a {area} m cloud of poison. | Lobs {amount} poison {thing} at the densest crowd for {damage} damage. Leaves a {area} m cloud of poison. |
| `gen.weapon.mine.jackrabbit` | Drops {amount?a mine:{amount} mines} every {cooldown} s that {amount?jumps:jump} at enemies within {sense} m, then {amount?hops:hop} on to another. | Drops {amount} {amount?mine:mines} every {cooldown} s that {amount?jumps:jump} at enemies within {sense} m for {damage} damage, then {amount?hops:hop} on to another. |
| `gen.weapon.mine.spring` | Drops {amount?a mine:{amount} mines} every {cooldown} s that {amount?jumps:jump} at enemies within {sense} m and {amount?blows:blow} up in a {area} m blast. | Drops {amount} {amount?mine:mines} every {cooldown} s that {amount?jumps:jump} at enemies within {sense} m and {amount?explodes:explode} for {damage} damage. |
| `gen.weapon.mine.step` | Drops {amount?a mine:{amount} mines} every {cooldown} s that {amount?blows:blow} up in a {area} m blast when an enemy steps on {amount?it:them}. | Drops {amount} {amount?mine:mines} every {cooldown} s that {amount?explodes:explode} for {damage} damage when an enemy steps on {amount?it:them}. |
| `gen.weapon.orbit` | {amount?A blade circles you and hits:{amount} blades circle you and hit} every enemy in the way. | {amount} {amount?blade circles:blades circle} you and {amount?hits:hit} every enemy in the way for {damage} damage. |
| `gen.weapon.pod.bees` | Sends {amount} killer {amount?bee:bees} after {prey} within {range} m. | Sends {amount} killer {amount?bee:bees} after enemies within {range} m for {damage} damage a sting. |
| `gen.weapon.pod.rockets` | Launches {amount} homing {amount?rocket:rockets} at {prey}. {amount?It explodes:Each explodes} in a {blast} m radius. | Launches {amount} homing {amount?rocket:rockets} that {amount?explodes:explode} for {damage} damage. |
| `gen.weapon.salt` | Pours {amount?a patch:{amount} patches} of salt ({radius} m) behind you every {cooldown} s. Enemies in the salt take {damage} damage every {tick} s. | Pours {amount} {amount?patch:patches} of salt behind you every {cooldown} s. Enemies in the salt take {damage} damage every {tick} s. |
| `gen.weapon.shot.dart` | Fires {amount} poison {amount?dart:darts} at an enemy that is not poisoned yet. | Fires {amount} poison {amount?dart:darts} for {damage} damage at enemies not yet poisoned. |
| `gen.weapon.shot.flare` | Fires {amount} {amount?flare that sets:flares that set} enemies on fire. | Fires {amount} {amount?flare:flares} for {damage} damage that {amount?sets:set} enemies on fire. |
| `gen.weapon.shot.nearest` | Fires {amount} {amount?shot:shots} at the nearest enemy within {range} m. | Fires {amount} {amount?shot:shots} at an enemy within {range} m for {damage} damage. |
| `gen.weapon.shot.priority` | Fires {amount} {amount?shot:shots} at {who} within {range} m. | Fires {amount} {amount?shot:shots} at an enemy within {range} m for {damage} damage. |
| `gen.weapon.shot.random` | Fires {amount} {amount?shot:shots} at random enemies within {range} m. | Fires {amount} {amount?shot:shots} at random enemies within {range} m for {damage} damage. |
| `gen.weapon.smash` | Slams {amount?a hammer:{amount} hammers} down on the thickest crowd, throwing enemies out of a {blast} m blast. | Slams {amount} {amount?hammer:hammers} down on the densest crowd for {damage} damage. |
| `gen.weapon.spawn` | Drops {amount?a turret:{amount} turrets} every {cooldown} s. {amount?It:Each} {stays}. | Drops {amount} {amount?turret:turrets} every {cooldown} s. {amount?It:Each} {stays}, {damage} damage a shot. |
| `gen.weapon.spawn.shoots_for` | shoots {who} for {seconds} s | shoots enemies for {seconds} s |
| `gen.weapon.spawn.stays` | stays and shoots {who} | stays and shoots enemies |
| `gen.weapon.spear` | Throws {amount?a spear:{amount} spears} {range} m through every enemy in the way. | Throws {amount} {amount?spear:spears} {range} m through every enemy in the way for {damage} damage. |
| `gen.weapon.sun` | Calls {amount?a pillar:{amount} pillars} of sunlight down on random enemies every {cooldown} s, {damage} damage in a {radius} m radius. | Calls {amount} {amount?pillar:pillars} of sunlight down on random enemies every {cooldown} s for {damage} damage. |
| `gen.weapon.thrust.slice` | Slashes a {deg}° arc at {who}{amount?:, {amount} times a swing}. | Slashes a {deg}° arc for {damage} damage{amount?:, {amount} times a swing}. |
| `gen.weapon.thrust.sweep` | Sweeps {amount?a blade:{amount} blades} in a {deg}° arc at {who}. | Sweeps {amount} {amount?blade:blades} in a {deg}° arc for {damage} damage. |
| `gen.weapon.thrust.thrust` | Thrusts {amount} {amount?blade:blades} at {who} within {range} m. | Thrusts {amount} {amount?blade:blades} at an enemy within {range} m for {damage} damage. |
| `gen.weapon.zap` | Zaps a random enemy within {range} m and chains to {chains} more. | Zaps a random enemy within {range} m for {damage} damage and chains to {chains} more. |

182 rows and texts in all (95 en.json rows, 87 content texts).

## 4. Every weapon card at level 1, before and after

From the text census (`game/tools/text_census.gd parts=a`, before and after this lane's change, no bonuses):


| Weapon | Before | After |
|---|---|---|
| Branding Iron | A hot branding iron circles you and sets enemies on fire. | 1 hot branding iron circles you, dealing 6 damage and setting enemies on fire. |
| Bullet Hose | Sprays a nonstop stream of peas at the strongest enemy nearby within 10 m. / All your mutations still apply. | Sprays a nonstop stream of peas at an enemy within 10 m for 12 damage each. / All your mutations still apply. |
| Chicago Typewriter | Fires a long burst of 14 rounds at the strongest enemy nearby within 13 m. / All your mutations still apply. | Fires a long burst of 14 rounds at an enemy within 13 m for 6 damage each. / All your mutations still apply. |
| Cluster Bomb | Lobs 2 sticks at the densest crowd that burst into small bombs. / All your mutations still apply. | Lobs 2 sticks at the densest crowd for 22 damage that burst into small bombs. / All your mutations still apply. |
| Dia de Muertos | Lobs 3 poison bombs that leave long-lasting clouds of poison. / All your mutations still apply. | Lobs 3 poison bombs for 8 damage, leaving long-lasting clouds of poison. / All your mutations still apply. |
| Dust Devil | Rolls 3 thorny tumbleweeds out and back twice, hitting harder on the way back. / All your mutations still apply and get stronger. | Rolls 3 thorny tumbleweeds out and back 2 times for 30 damage, hitting harder on the way back. / All your mutations still apply and get stronger. |
| Earthshaker | Slams 2 hammers down on the thickest crowd, splitting the ground in cracks. / All your mutations still apply. | Slams 2 hammers down on the densest crowd for 42 damage, splitting the ground in cracks. / All your mutations still apply. |
| Earthshaker | Slams 3 hammers down on the thickest crowd, splitting the ground in lightning cracks. / All your mutations still apply. | Slams 3 hammers down on the densest crowd for 40 damage, splitting the ground in lightning cracks. / All your mutations still apply. |
| Firestorm | Lobs 2 bottles of fire that leave big pools of flames. / All your mutations still apply. | Lobs 2 bottles of fire for 10 damage, leaving big pools of flames. / All your mutations still apply. |
| Flare Gun | Fires 1 flare that sets enemies on fire. | Fires 1 flare for 3 damage that sets enemies on fire. |
| Flying Saucer | Throws 3 glowing saucers that loop once and cut through every enemy in the way. / All your mutations still apply and get stronger. | Throws 3 glowing saucers that loop once and cut through every enemy in the way for 30 damage. / All your mutations still apply and get stronger. |
| Frisbee | Throws a frisbee that curves through every enemy in the way. | Throws 1 frisbee that curves through every enemy in the way for 14 damage. |
| Golden Pineapple | Lobs 2 golden crates that stick to the strongest enemy, then explode in a 3.0 m radius. / All your mutations still apply and get stronger. | Lobs 2 golden crates that stick to the strongest enemy, then explode in a 3 m radius for 45 damage. / All your mutations still apply and get stronger. |
| Golden Revolver | Fires 2 golden bullets at the strongest enemy nearby within 15 m. / All your mutations still apply. | Fires 2 golden bullets at an enemy within 15 m for 40 damage. / All your mutations still apply. |
| Golden Revolver | Fires 2 silver bullets at the strongest enemy nearby that ricochet 2 times. Every 3rd pull is a hip shot. / All your mutations still apply and get stronger. | Fires 2 silver bullets for 40 damage that ricochet 2 times. Every 3rd pull is a hip shot. / All your mutations still apply and get stronger. |
| Grave Hail | Lobs 3 poison bombs that bounce on, leaving a poison cloud at every landing. / All your mutations still apply and get stronger. | Lobs 3 poison bombs for 8 damage that bounce on, leaving a poison cloud at every landing. / All your mutations still apply and get stronger. |
| Gravity Gun | Picks up 1 enemy and throws it into the thickest crowd for a 1.9 m blast. | Picks up 1 enemy and throws them into a crowd for a 2 m blast that deals 18 damage. |
| Guitarra | Strums a 70° cone of melody that lifts enemies into the air. | Strums a 70° cone of melody that deals 14 damage and lifts enemies into the air. |
| Halberd | Swings 2 halberd blades in a wide fan at the strongest enemy nearby. / All your mutations still apply. | Swings 2 halberd blades in a wide fan for 48 damage. / All your mutations still apply. |
| Hammer | Slams a hammer down on the thickest crowd, throwing enemies out of a 1.6 m blast. | Slams 1 hammer down on the densest crowd for 20 damage. |
| Hellfire Battery | Launches 8 homing rockets. Every blast scatters bomblets that set each other off. / All your mutations still apply and get stronger. | Launches 8 homing rockets for 24 damage. Every blast scatters bomblets that set each other off. / All your mutations still apply and get stronger. |
| Hive Queen | Sends 5 killer bees and a Tarantula Hawk with every burst. / All your mutations still apply and get stronger. | Sends 5 killer bees and a Tarantula Hawk with every burst, 7 damage a sting. / All your mutations still apply and get stronger. |
| Hiwa Kai | Pours black lava salt behind you that slows enemies and bites hard when they step in. / All your mutations still apply and get stronger. | Pours black lava salt behind you that slows enemies and bites hard when they step in. Enemies in it take 13 damage every 0.5 s. / All your mutations still apply and get stronger. |
| Killer Bees | Sends 2 killer bees after the strongest enemy nearby within 11 m. | Sends 2 killer bees after enemies within 11 m for 5 damage a sting. |
| Iron Bastion | Drops 2 armoured bunkers every 5.0 s that explode when they go. / All your mutations still apply and get stronger. | Drops 2 armoured bunkers every 5 s that shoot for 8 damage and explode when they go. / All your mutations still apply and get stronger. |
| Jackrabbit Mines | Drops 2 mines every 1.4 s that jump at enemies within 6 m, then hop on to another. / All your mutations still apply. | Drops 2 mines every 1.4 s that jump at enemies within 6 m for 62 damage, then hop on to another. / All your mutations still apply. |
| Killer Swarm | Sends a swarm of 5 killer bees after the strongest enemy nearby. / All your mutations still apply. | Sends a swarm of 5 killer bees after enemies for 7 damage a sting. / All your mutations still apply. |
| Land Mine | Drops a mine every 3.1 s that blows up in a 2.4 m blast when an enemy steps on it. | Drops 1 mine every 3.1 s that explodes for 28 damage when an enemy steps on it. |
| Lob Grenade | Lobs 1 stick at the densest crowd. Explodes in a 2.8 m radius. | Lobs 1 stick at the densest crowd. Explodes in a 3 m radius for 25 damage. |
| Minefield | Drops 2 mines every 1.4 s, covering the ground in mines. / All your mutations still apply. | Drops 2 mines every 1.4 s, covering the ground in mines that deal 40 damage. / All your mutations still apply. |
| Missile Massacre | Launches 8 homing rockets that fill the sky. / All your mutations still apply. | Launches 8 homing rockets that fill the sky, 18 damage each. / All your mutations still apply. |
| Molotov | Lobs 1 bottle of fire at the thickest crowd. Leaves a 2.0 m pool of flames. | Lobs 1 bottle of fire at the densest crowd for 8 damage. Leaves a 2 m pool of flames. |
| Moonshine | Lobs 2 bottles of blue fire that leave a burning trail and long-lasting pools. / All your mutations still apply and get stronger. | Lobs 2 bottles of blue fire for 10 damage, leaving a burning trail and long-lasting pools. / All your mutations still apply and get stronger. |
| Orbit Saws | 2 saw blades circle you and cut every enemy in the way. | 2 saw blades circle you and cut every enemy in the way for 8 damage. |
| Pea Cannon | Fires 3 giant toxic peas at the strongest enemy nearby that bounce on to 3 more enemies. / All your mutations still apply and get stronger. | Fires 3 giant toxic peas for 15 damage that bounce on to 3 more enemies. / All your mutations still apply and get stronger. |
| Peashooter | Fires 1 pea at the strongest enemy nearby within 9 m. | Fires 1 pea at an enemy within 9 m for 8 damage. |
| Spear | Thrusts a spear at the strongest enemy nearby within 4.6 m. | Thrusts 1 spear at an enemy within 5 m for 30 damage. |
| Plague Volley | Fires a volley of 3 poison darts at enemies that are not poisoned yet. / All your mutations still apply. | Fires a volley of 3 poison darts for 3 damage at enemies not yet poisoned. / All your mutations still apply. |
| Poison Dart | Fires 1 poison dart at an enemy that is not poisoned yet. | Fires 1 poison dart for 2 damage at enemies not yet poisoned. |
| Rattlesnake | A rattlesnake circles you and bites enemies, poisoning them. | 1 rattlesnake circles you and bites enemies for 5 damage, poisoning them. |
| Requiem | Strums a full ring of melody that lifts every enemy around you into the air. / All your mutations still apply. | Strums a full ring of melody that deals 30 damage and lifts every enemy around you into the air. / All your mutations still apply. |
| Revolver | Fires 1 shot at the strongest enemy nearby within 14 m. | Fires 1 shot at an enemy within 14 m for 20 damage. |
| Ring of Fire | 3 branding irons circle you in a ring of fire, burning every enemy they touch. / All your mutations still apply. | 3 branding irons circle you in a ring of fire, dealing 9 damage and burning every enemy they touch. / All your mutations still apply. |
| Rocket Pod | Launches 3 homing rockets at enemies. Each explodes in a 1.5 m radius. | Launches 3 homing rockets that explode for 14 damage. |
| Roman Candle | Fires a volley of 3 flares that set enemies on fire. / All your mutations still apply. | Fires a volley of 3 flares for 4 damage that set enemies on fire. / All your mutations still apply. |
| Sabre | Slashes a 150° arc at the strongest enemy nearby. | Slashes a 150° arc for 16 damage. |
| Salt | Pours a patch of salt (1.4 m) behind you every 1.9 s. Enemies in the salt take 6 damage every 0.5 s. | Pours 1 patch of salt behind you every 1.9 s. Enemies in the salt take 6 damage every 0.5 s. |
| Saw Halo | 8 saw blades spin round you in a solid ring that cuts everything it touches. / All your mutations still apply. | 8 saw blades spin round you in a solid ring that deals 12 damage to everything it touches. / All your mutations still apply. |
| Singularity | Lobs a black hole that drags enemies in, eats them, then pops. / All your mutations still apply. | Creates a Black Hole that drags enemies in and deals 22 damage a second. / All your mutations still apply. |
| Skull Rain | Lobs 1 poison bomb at the thickest crowd. Leaves a 2.2 m cloud of poison. | Lobs 1 poison bomb at the densest crowd for 6 damage. Leaves a 2 m cloud of poison. |
| Snake Pit | 4 rattlesnakes circle you fast, poisoning every enemy they bite. / All your mutations still apply. | 4 rattlesnakes circle you fast, biting enemies for 8 damage and poisoning them. / All your mutations still apply. |
| Throwing Spear | Throws a spear 11 m through every enemy in the way. | Throws 1 spear 11 m through every enemy in the way for 22 damage. |
| Stampede | Rolls 4 tumbleweeds out in a wide fan through every enemy in the way. / All your mutations still apply. | Rolls 4 tumbleweeds out in a wide fan through every enemy in the way for 22 damage. / All your mutations still apply. |
| Storm Cloud | A storm cloud follows you, zapping enemies within 7 m and chaining to 3 more. / All your mutations still apply and get stronger. | A storm cloud follows you, zapping enemies within 7 m for 10 damage and chaining to 3 more. / All your mutations still apply and get stronger. |
| Sun Scepter | Calls a pillar of sunlight down on random enemies every 1.3 s, 14 damage in a 1.3 m radius. | Calls 1 pillar of sunlight down on random enemies every 1.3 s for 14 damage. |
| Thunder Lance | Sweeps 2 lances in a 140° arc, then thrusts. Every hit stuns. / All your mutations still apply and get stronger. | Sweeps 2 lances in a 140° arc for 58 damage, then thrusts. Every hit stuns. / All your mutations still apply and get stronger. |
| Tommy Gun | Fires a burst of 6 rounds at the strongest enemy nearby within 12 m. | Fires a burst of 6 rounds at an enemy within 12 m for 3 damage each. |
| Tumbleweed | Rolls a tumbleweed 16 m out through every enemy in the way. | Rolls 1 tumbleweed 16 m out through every enemy in the way for 16 damage. |
| Turret Buddy | Drops a turret every 7.1 s. It shoots the strongest enemy nearby for 12 s. | Drops 1 turret every 7.1 s. It shoots enemies for 12 s, 4 damage a shot. |
| Turret Family | Drops 2 turrets every 5.0 s that never leave and pull gems to you. / All your mutations still apply. | Drops 2 turrets every 5 s that never leave, shoot for 6 damage and pull gems to you. / All your mutations still apply. |
| War Lance | Throws 2 spears through every enemy in the way, leaving a trail of slowing dust. / All your mutations still apply. | Throws 2 spears through every enemy in the way for 44 damage, leaving a trail of slowing dust. / All your mutations still apply. |
| Whirlwind | Spins a full circle 4 times a swing. Crits give back part of the cooldown. / All your mutations still apply. | Spins a full circle for 30 damage, 4 times a swing. Crits give back part of the cooldown. / All your mutations still apply. |
| Zap Beam | Zaps a random enemy within 9 m and chains to 2 more. | Zaps a random enemy within 9 m for 12 damage and chains to 2 more. |
| Zenith | Calls 3 pillars of sunlight down every 1.0 s. Every 10th strike hits every enemy on screen. / All your mutations still apply. | Calls 3 pillars of sunlight down every 1 s for 24 damage. Every 10th strike hits every enemy on screen. / All your mutations still apply. |
| Zweihänder | Swings a huge 210° slash 3 times a swing. / All your mutations still apply. | Swings a huge 210° slash for 34 damage, 3 times a swing. / All your mutations still apply. |

## 5. Left exactly as you wrote them, and suggestions for you

Your four families are untouched, every row and text (the Basketball, Big Mouth, Boomstick and Dragon's Breath, their evolutions and mutations, and the shape rows only they use); `pass138_texts_test.gd` still pins them byte for byte. Your rules would change them like this, if you want it (not done):

| Row | Today | Suggestion |
|---|---|---|
| `weapon.basketball.desc` | Throws a ball at {who} within {range} m, it bounces to {hops} more {hops?enemy:enemies} close by, then flies back. | Throws a ball at an enemy within {range} m for {damage} damage. It bounces to {hops} more {hops?enemy:enemies} close by, then flies back. |
| `weapon.big_mouth.desc` | Shoots a {range} m long beam at the crowd for {seconds} s. | Shoots a {range} m long beam at the crowd for {seconds} s, {damage} damage a second. |
| `weapon.boomstick.desc` | Fires {amount} {amount?pellet:pellets} in a {cone}° cone where you face. | Fires {amount} {amount?pellet:pellets} in a {cone}° cone where you face for {damage} damage each. |
| `weapon.dragons_breath.desc` | Breathes a {deg}° cone of fire {range} m long for {seconds} s every {cooldown} s | Breathes a {deg}° cone of fire {range} m long for {seconds} s every {cooldown} s, {damage} damage a second. (also the missing full stop) |
| Fire Eater, Loudmouth, Slam Dunk, Doomstick, Blunderbuss | your weapon rows | the same damage clause |
| the breath's and beam's numbers | "for 3.0 s every 7.0 s" | "for 3 s every 7 s" (the code formats them; I left your families' numbers as they were) |

Your typos from pass 138, still open: Birdshot Lane's "curent" (and its 40% / "40% less" mismatch), Free Throw's "Every hit evade throw a ball.", Mouth Burn's "Beams lights", Alley-Oop's and Mouth Knock's "creature" (the rules say "enemy"), Both Barrels' "third" (the rules say "3rd") and its missing full stop.

**Balance numbers behind a rounded text** (the text now shows the whole metre; I changed only the Gravity Gun's and the Singularity's 1.9, the one you named; say which of these to round in the JSON):

| Item | The number | The text shows | Rounding it would be |
|---|---|---|---|
| Dynamite (`lob_grenade` area) | 2.8 m | 3 m | +7% radius |
| Skull Rain (`skull_rain` area) | 2.2 m | 2 m | −9% radius |
| Spear thrust (`pike` range) | 4.6 m | 5 m | +9% reach |
| Wide Reach (Land Mine, `spring.sense`) | 2.8 m | 3 m | +7% |

The Hammer's 1.6 m blast, the rockets' 1.5 m, the Sun Scepter's 1.3 m pillar and the Salt's 1.4 m patch are no longer in their rows (secondary to the weapon, and a whole metre would be far off); the upgrade rows show them exactly.

## 6. Doubts

- The Gravity Gun's text is yours plus "that deals 18 damage": your note 6 ("All weapon descriptions should do that I think") came after your example, so I applied it to the Gravity Gun too.
- The Singularity says "a second": "deals 22 damage" alone would undersell it (it ticks for 3 s, then pops for 1.5 times the damage).
- "an enemy" replaces "the strongest enemy nearby" on every weapon: true with aim on (the default since pass 136) and with it off.
- The damage shown is per hit with your bonuses in; a weapon with many hits (the Tommy Gun's burst, the bees) says "each" or "a sting" so 3 damage does not read as weak against a single 20-damage shot. Damage a second (the estimate on the pause screen) would compare them better but changes as you level; say if you want that instead.
- Hidden items (not offered) were brought to the rules too, so they read right if you turn them on.
