# -*- coding: utf-8 -*-
"""The ideas document's words and its concept art's prompts (pass 124). Read by tools/gen_ideas_art.py (the art, Flux.2 Klein
on the AI server) and tools/make_ideas_doc.py (the page). Every number is a starting point for the Level Editor, not a tuned
value. `art` = the prompt's subject; `kind` = scene | creature | icon | card | portrait; `ref` = a game picture to repaint."""

S1 = "game/art/ui/stages/red_canyon_s1.jpg"

# ------------------------------------------------------------------ the last ideas Garry asked for (pass 122's 5 + 5)
PAST_FEATURES = [
    dict(id="spreads", name="Spreads", tag="Named two-Card combos",
         what="Pairs of Cards form a named Spread with a bonus: The Sun + The Eye gives extra crit damage, The Tower + The Guardian a shield pulse. The Card screen marks a card that would complete one.",
         adds="The fourth Card slot becomes a plan, not just the best stat on offer. Gives a reason to remember Cards between runs.",
         kind="scene", art="two glowing ornate tarot cards laid side by side on a dark green saloon card table, a golden arc of light joining them, a sun on one card and an eye on the other, poker chips around"),
    dict(id="got_you", name="The One That Got You", tag="A grudge from your last run",
         what="Whatever killed you comes back early in your next run as a glowing special with a sure chest, and a small poster pays extra for the revenge.",
         adds="A personal story from run to run, and a known threat in the quiet opening minutes.",
         kind="scene", art="a torn western wanted poster nailed to a post showing a snarling red scorpion marked REVENGE, bullet holes in the paper, a glowing red aura round the poster, desert dusk"),
    dict(id="daily_canyon", name="The Daily Canyon", tag="One seed for everyone, every day",
         what="One stage, one hero, one poster a day, the same seed for all players, one attempt that counts. A short board shows friends' results.",
         adds="A reason to open the app every day and something to compare. It uses the deterministic replays already in the game.",
         kind="scene", art="a daily calendar page nailed to a saloon wall showing a desert canyon sketch, a sheriff star pinned on it, a small wooden scoreboard beside it with chalk tallies"),
    dict(id="cover", name="Cover", tag="Rocks stop bullets",
         what="Enemy straight shots stop at rocks and tall cacti; lobbed ones fly over. A small puff shows the hit.",
         adds="Steering matters against ranged enemies, and map generation starts to matter for fights.",
         kind="scene", art="a cowboy gunslinger crouching behind a big red desert boulder while a bright enemy bullet shatters against the rock in a puff of dust, top three quarter view of desert sand"),
    dict(id="staked", name="Staked Posters", tag="Bet your gold on a bounty",
         what="Put up half a hard poster's reward from your own gold before a run: double it if you finish, lose it if you don't.",
         adds="A risk choice for experts and a gold sink for the greedy.",
         kind="scene", art="a pile of gold coins and a wanted poster on a rough wooden table, a hand pushing the stack of coins forward, a revolver lying beside it, warm saloon light"),
]
PAST_CONTENT = [
    dict(id="pack_rat", name="The Pack Rat", tag="A loot runner",
         what="A fast creature carrying a huge sack. It never attacks and flees; catch it within 30 s for a sure chest and coins.",
         adds="A sudden change of plan in the middle of a fight: chase it or stay safe?",
         kind="creature", art="a fat desert pack rat running on its hind legs carrying a huge overstuffed burlap sack spilling gold coins on its back, panicked greedy face"),
    dict(id="elite_mods", name="Four more Elite modifiers", tag="Brute, Colossus, Twin, Blasting Cap",
         what="Brute hits twice as hard, Colossus is huge with triple HP, Twin splits in two on death, Blasting Cap explodes after a warning.",
         adds="Elites stop repeating by run three.",
         kind="creature", art="a huge crowned skeleton elite warrior with a glowing golden crown floating above its head, cracked armour, sticks of dynamite strapped to its chest with burning fuses, menacing pose"),
    dict(id="skin_wave", name="A wave of skins", tag="Eight hero skins",
         what="Eight hero skins, such as the Drifter's Black Hat, each earned by a quest and bought with gold.",
         adds="A long goal on every hero sheet, using the skin system that already exists.",
         kind="creature", art="a gunslinger cowboy in a long black duster coat, black wide brim hat and a silver skull belt buckle, red bandana, cool standing pose, full body"),
    dict(id="bullwhip", name="The Bullwhip", tag="The western's missing weapon",
         what="A long thin crack that throws what it hits, with fire, triple-crack and lasso-pull mutations.",
         adds="A reach weapon with a shape no other weapon has: a long curved line.",
         kind="icon", art="a long thin brown braided leather bullwhip coiled in loops, a short leather grip at one end and the thin tip curling away with a small white crack spark; only the whip, no gun, no rifle"),
    dict(id="dealer", name="The Dealer", tag="A hero built around luck",
         what="A riverboat gambler who levels luck, the stat that improves card offers, and throws curving playing cards.",
         adds="The first hero built around what you are offered rather than raw damage.",
         kind="creature", art="an elegant riverboat gambler woman in a burgundy waistcoat and a small black top hat, fanning a hand of glowing playing cards, sly smile, full body"),
]

# ------------------------------------------------------------------ map variations
VARIATIONS = [
    dict(id="var_saltflat", name="Salt Flat Noon", tag="White, hot and blinding",
         look="Sand becomes a cracked white salt crust in big hexagon plates. Hard, short blue-violet shadows. Bleached bones, rusted cars and salt pillars replace palms. Heat shimmer at the screen's top edge.",
         apart="The brightest stage in the game; every creature reads as a dark silhouette, the exact opposite of Nightfall.",
         play="The oases are brine pools. Salt crust crunches: a faint trail shows where you have walked.",
         cost="Cheap: a new ground texture, a filter and 4 to 6 painted props.",
         ref=S1, art="the same desert scene repainted as a blinding white salt flat: cracked hexagonal white salt crust ground, a turquoise brine pool in the middle, bleached bones and white salt pillars instead of palms, pale sky, short blue-violet shadows"),
    dict(id="var_duststorm", name="The Dust Bowl", tag="A storm you can't see through",
         look="Amber haze rolling across the map, soft-edged props fading into brown, a low orange sun as a disc through the dust.",
         apart="Depth comes from fog bands, not colour. The world feels closed in.",
         play="Gusts every 40 to 60 s push everything one way for a few seconds, and creatures arrive out of the haze.",
         cost="Cheap to medium: scrolling fog layers on top of the ground. They must stay light on the phone's GPU.",
         ref=S1, art="the same desert scene repainted inside a huge brown dust storm: thick amber haze bands rolling across, props half hidden as silhouettes, a dim orange sun disc, wind streaks of sand, an abandoned wagon"),
    dict(id="var_superbloom", name="Superbloom", tag="The desert after the rain",
         look="Sand under a carpet of purple, yellow and orange wildflowers, green-tinted saguaros, shallow streams everywhere, big white clouds.",
         apart="The only colourful, happy stage. Violence on it reads as funny, and it sells screenshots.",
         play="Flowers are flattened where you walk. Streams slow you as water does now, so routes change.",
         cost="Medium: a bloom ground texture, flower-patch props, and the river rule run several times.",
         ref=S1, art="the same desert scene repainted as a desert superbloom after rain: carpets of purple lupine yellow poppies and orange wildflowers over the sand, bright green saguaros, sparkling shallow streams, big white clouds, cheerful daylight"),
    dict(id="var_burn", name="After the Fire", tag="Charcoal and embers",
         look="Black and grey ash ground with glowing orange cracks, charred cactus skeletons, drifting embers, a smoke-brown sky.",
         apart="Hell's opposite: Blood Moon is red on red; this is orange lights on black, so creatures pop strongly.",
         play="Burnt patches flare up now and then (a short fire zone). Fire weapons leave longer flames here.",
         cost="Cheap: a recolour of the ground, charred versions of props by the existing paint pipeline, and the embers Fx.",
         ref=S1, art="the same desert scene repainted after a wildfire: black charcoal ash ground with glowing orange ember cracks, charred blackened cactus skeletons, drifting orange sparks, a brown smoky sky, a ruined burnt wagon"),
    dict(id="var_sunset", name="Painted Desert", tag="Candy-striped strata",
         look="The ground in bands of pink, cream and rust like the real Painted Desert; banded hoodoos and mesas; soft lilac shadows at golden hour.",
         apart="Keeps the desert fantasy but makes it look like a postcard. The bands give the ground direction and shape.",
         play="Pure look; the bands can follow the map's noise so every run's stripes differ.",
         cost="Cheap: one ground shader using the height noise for stripes, plus hoodoo props.",
         ref=S1, art="the same desert scene repainted as the Painted Desert of Arizona: ground in soft horizontal bands of pink cream and rust, striped hoodoo rock towers, a pale teal oasis, lilac shadows, golden hour light"),
    dict(id="var_roswell", name="WILD: Roswell", tag="Something crashed last night",
         look="Night desert under a huge teal aurora, a crashed silver saucer at the map's centre with glowing green goo, crop-circle patterns burnt into the sand, tin-foil scarecrows.",
         apart="Sci-fi invading the western: instantly a different game on the store page.",
         play="Creatures take a green rim and float a little. Goo pools hurt them and heal you. Alien tech chests hold a weapon look you can only earn here. Astro feels at home.",
         cost="Medium: a set piece, a filter, goo pools (the Molotov's pool with other params), a few new props.",
         ref=S1, art="the same desert scene repainted as a night in Roswell: dark blue sand under a teal green aurora sky, a crashed silver flying saucer half buried at the centre glowing green, crop circle patterns burnt into the sand, pools of glowing green goo"),
    dict(id="var_seabed", name="WILD: The Dry Sea", tag="An ocean that left",
         look="Sand turns teal and pale, with rippled seabed patterns. Whale skeletons, galleon wrecks on dunes, giant coral fossils, anchors and rusted chains. Faint light caustics drift over the ground as if the water never quite left.",
         apart="A desert that is still a desert, but with a story nobody expects: the caustics alone make it read as somewhere else.",
         play="Every couple of minutes a ghost tide rolls across: for 10 s everything moves as if under water, shots slow, and ghost fish swim past. A galleon wreck holds the stage's chest.",
         cost="Medium: caustics in the ground shader (cheap), about 8 new props, the tide as a timed slow on the existing systems.",
         ref=S1, art="the same desert scene repainted as a dried up ancient seabed: pale teal rippled sand, a huge whale skeleton, a wrecked wooden galleon lying on a dune, giant fossil coral, rusty anchor and chains, soft water caustic light patterns drifting over the sand"),
]

# ------------------------------------------------------------------ map generation
GENERATION = [
    dict(id="gen_landmarks", name="One big landmark a map", tag="The thing you remember",
         what="Roll one large set piece per run from a list: a ghost town street, a wrecked train on a trestle, a mine head, a mission ruin, a giant dinosaur skeleton, a meteor crater. It sits somewhere off centre and holds the map's best chest.",
         why="People describe a run by its landmark: \"the one with the train\". Today's scatter of props never gives you that.",
         cost="Medium: each is a cluster of painted billboards and obstacle circles, content rather than code once the first exists.",
         kind="scene", art="top three quarter view of a small abandoned western ghost town street in the desert: a crooked saloon, a sheriff's office, a water tower, wooden boardwalks and tumbleweeds, seen from above like a game map"),
    dict(id="gen_biomes", name="Districts instead of one scatter", tag="Three neighbourhoods a map",
         what="Split the map into 3 to 5 soft regions with their own prop mix and ground tint: a palm oasis belt, a dead cactus forest, a rocky badland, a dune sea, a salt pan. Which ones you get, and where, comes from the seed.",
         why="This is the biggest single change for \"this map feels different\". Walking somewhere new would look new.",
         cost="Low: PropField already picks by a hash of the spot. It gains a low-frequency noise that chooses the mix.",
         kind="diagram", art=""),
    dict(id="gen_hard", name="Real walls: canyons and mesas", tag="Terrain that changes your route",
         what="Roll one big hard shape per run: a winding dry canyon, two mesas with a gap between them, a ring of rock with two exits, or a long fence line. Creatures path round them and hard walls stop ranged shots (see Cover).",
         why="Today's obstacles are small circles, so you can run in any line on any map. A wall forces a route, which is what makes two runs play differently.",
         cost="Medium to high: creature steering has to handle long walls. It needs a cheap flow field, which could also speed up the crowd.",
         kind="diagram", art=""),
    dict(id="gen_traits", name="Named map traits", tag="\"Rattler's Gulch: Dry Year, Many Barrels\"",
         what="Each seed rolls 1 or 2 traits shown on the loading screen and the map's name: Dry Year (no water), Wet Year (four oases), Barrel Country (double barrels), Totem Grove (totems cluster), Boneyard (bones everywhere, more Skeletons), Windy (constant dust devils).",
         why="Players notice a difference they can read. A name and a sentence make a seed feel chosen rather than random.",
         cost="Low: the numbers already live in `timeline_data`. A trait is a small overlay on them.",
         kind="scene", art="a weathered wooden trail signpost in the desert with several painted arrows and carved place names, a rattlesnake coiled at its foot, sunset"),
    dict(id="gen_roads", name="Roads, rails and old tracks", tag="Lines that connect things",
         what="Generate a dirt road or rail line that links the landmark to the fort gate and past the oases, with fence posts, telegraph poles and signs along it. Walking on the road gives a small speed boost.",
         why="Lines across the map give the eye structure and turn a blank field into a place. A small boost makes them a choice.",
         cost="Low to medium: the river's code already draws a curve onto the ground texture.",
         kind="scene", art="a dusty dirt road winding across desert sand with old wooden telegraph poles and a broken fence along it, seen from high above at an angle, a lone wagon wheel by the road"),
    dict(id="gen_pockets", name="Treasure pockets", tag="Small rewards to go and find",
         what="Hide 3 to 6 small authored scenes per map: a camp with a chest, a cactus ring round a totem, a wrecked wagon with barrels, a skeleton holding a map. Each has a small visible clue from far away.",
         why="Survivors are best when walking somewhere has a purpose. The rule of thumb: one thing worth finding within about 20 seconds of walking in any direction.",
         cost="Low: scenes are short lists of existing props with a reward.",
         kind="scene", art="a small abandoned desert camp seen from above: a tattered canvas tent, a dead campfire, a treasure chest half buried in sand, a ring of cactus around it"),
    dict(id="gen_weather", name="Weather and hour rolled per run", tag="The same place, another day",
         what="Roll the sky per run: clear noon, overcast, long golden hour, dusk haze. Shadows, tint and ambient sound follow. It stays within a stage's own colour rules.",
         why="Two runs on the same stage stop looking identical. It costs almost nothing, because the stage filter already exists.",
         cost="Very low: a few filter presets, and the shadows' direction as a shader value.",
         kind="scene", art="split view of the same small desert hill with a saguaro cactus under four different skies: noon, overcast, golden hour and dusk, four vertical panels"),
]

# ------------------------------------------------------------------ the snow map
SNOW_SCENES = [
    dict(id="snow_overview", caption="The whole map's feel: an alpine valley seen from the game's camera", ref=S1,
         art="the same game camera view repainted as a snowy Colorado alpine valley: white snow ground with blue shadows and exposed dark rock patches, a frozen blue lake in the middle, dark green snow-covered spruce trees in clusters, a small log cabin, wind drift patterns, crisp clear daylight"),
    dict(id="snow_dusk", caption="The same valley at last light: this could be its Nightfall", ref=S1,
         art="the same game camera view repainted as a snowy mountain valley at dusk: blue and violet snow, a frozen lake reflecting a pink sky, warm orange lights in a log cabin window, dark spruce trees, long soft shadows"),
    dict(id="snow_props", caption="Prop sheet: what replaces cactus and palm", kind="scene",
         art="a game prop sheet on plain pale blue background of snowy Colorado objects arranged in a neat grid: snow covered spruce tree, bare aspen tree, snow capped boulder, half buried wooden fence, a mine cart full of ore, a log cabin, a ski lift pylon, a frozen wagon, a wooden trail marker, a snow drift, a small ice crystal cluster, a steaming hot spring"),
    dict(id="snow_lake", caption="The frozen lake, the map's big hard element", kind="scene",
         art="a large frozen mountain lake seen from above at an angle: smooth pale blue ice with long white cracks, a small ice fishing shack and a hole in the ice, snow banks and dark spruce trees around the shore"),
]
SNOW_ENV = [
    ("Trees", "Spruce in dense dark clusters (the map's main shapes), pale bare aspen groves as a lighter accent, fallen logs, stumps with snow caps."),
    ("Rock", "Grey granite outcrops with snow on top, scree slopes, cliff faces along the map's north edge with the Rockies painted behind them, as the fort wall and red cliffs are today."),
    ("Human traces", "Log cabins with lit windows, an old mine head with rails and ore carts, a ski lift whose pylons cross the map in a line, a half-buried wagon, split rail fences, trail markers, a lookout tower, a frozen water tower."),
    ("Small life on the ground", "Dry yellow grass poking through snow, animal tracks painted on the ground, snow drifts, icicles on eaves, frost on rocks."),
    ("What sells it most", "Footprints. Hero and creatures leave a trail in the snow that fades slowly. It is the single strongest cue that this is snow, and a cheap ring buffer of ground decals can do it. Add light falling snow and breath puffs on the hero."),
]
SNOW_LAND = [
    "Flat, as you say, but not featureless: the top-down camera reads height through shadow, so wind-carved ridges and soft drifts in the ground texture do the work that dunes do in the desert. Blue shadows on white, warm rock accents, and pure white kept for highlights only, so that sprites stay readable.",
    "White ground is the risk. A white snow field fights our white damage numbers and pale creatures and it blooms on the screen. I would keep the snow at a mid light blue-grey (around 75% brightness), with brighter wind streaks. The Nightfall filter and creature outlines can stay as they are.",
    "A strong north: mountains painted behind a treeline at the map's top edge, the way the fort wall and cliffs close the desert. Colorado reads through the skyline more than through anything on the ground.",
    "Stage arc: bright morning for Stage 1, a blue blizzard dusk for Stage 2, and for Stage 3 either an aurora night or a thawing mine fire. The stage filters already exist.",
]
SNOW_HARD = [
    ("Frozen lake", "Big, near the centre. Ice is slippery: you keep your momentum for a moment when turning. Creatures slide too, and heavy ones can crack the ice and fall through. It is the map's memorable place, and it replaces the oasis."),
    ("Deep snow", "Soft areas that slow everyone by 15 to 20% (as water does in the desert), with packed trails through them that are faster. It makes the hero's line matter."),
    ("Ridgelines and rock walls", "Long hard shapes that block movement and straight shots, forming two or three natural pockets. This needs the wall steering from the generation ideas above. It is what makes this more than a reskin."),
    ("Spruce belts", "Dense tree clusters you can't walk through but shots can pass, so they break up the crowd's line without blocking your guns."),
    ("The ski lift", "A line of pylons across the map, with chairs moving above. Standing under it does nothing, but a rideable chair could be a moving safe spot for 6 s every so often: the map's signature risk-free moment."),
    ("Hot springs", "Replace oases as the heal spot: stand in the steam and regain HP, but the crowd comes through it too. Heat melts deep snow around it, so it's also a fast zone."),
    ("Avalanche chutes", "Marked slopes at the map's edge. Now and then one releases a moving wall of snow across part of the map (see Avalanche Caller below). It buries creatures too, so you can lure them in."),
]

# ------------------------------------------------------------------ snow enemies
FODDER = [
    dict(id="sn_miner", name="Frostbitten Miner", role="The basic walker (like the Skeleton)", text="A frozen dead miner with a dim headlamp, slow and steady, comes in large numbers. Its lamp makes a crowd of them read at night.", art="a frozen undead skeleton miner covered in frost with a dented helmet and a dim yellow headlamp, tattered coat, icicles, carrying a broken pickaxe, shuffling forward"),
    dict(id="sn_marmot", name="Yellow-Belly Marmot", role="Tiny swarmer", text="Very small and low HP, comes in tight packs of 15 to 20. They die in one hit and feel great to mow down.", art="a chubby angry yellow-bellied marmot running on all fours with bared buck teeth and a snow-dusted back"),
    dict(id="sn_hare", name="Snowshoe Hare", role="Fast hopper", text="White and quick, hopping in bursts with pauses between them. Only its dark eye and ear tips keep it readable on snow.", art="a fierce white snowshoe hare with black ear tips and huge furry feet, mid hop, mean red eyes"),
    dict(id="sn_wolf", name="Frost Wolf", role="Pack runner", text="Comes in loose packs from one side and runs at about your speed, so they catch you if you stop. A mid-tier body.", art="a lean grey and white frost wolf with ice crystals on its back and glowing pale blue eyes, snarling, running"),
    dict(id="sn_snowman", name="Snow Deputy", role="Comedy tank", text="A walking snowman with a tin star and a carrot nose. It loses its head when badly hurt and keeps walking. A kind of joke the game can carry.", art="a menacing three-ball walking snowman wearing a battered cowboy hat and a tin sheriff star, carrot nose, coal eyes, twig arms, scowling"),
    dict(id="sn_yeti_cub", name="Yeti Cub", role="Chunky bruiser", text="Round and slow with high HP, wandering in small groups. Rewards area weapons.", art="a round fluffy white baby yeti with small blue horns and a toothy grumpy grin, waddling with big feet"),
    dict(id="sn_skier", name="Lost Skier", role="Straight-line runner", text="A zombie skier who speeds up in a straight line and turns badly, so it's easy to sidestep but hits hard if you don't.", art="a zombie skier in a torn retro 1970s orange ski jacket with goggles and ski poles, skis on its feet, leaning forward at speed, undead grey skin"),
    dict(id="sn_crawler", name="Rime Crawler", role="Ground-hugging swarm", text="A pale ice beetle low to the ground. Low HP and many of them; the Lesser Scorpion of this map.", art="a pale blue ice beetle crawler with a crystalline shell, six spiky legs and small glowing eyes, low to the ground"),
    dict(id="sn_grizzly", name="Grizzly", role="Heavy walker", text="A big body with a wide hit area. It doesn't charge, it just keeps coming and knocks you back when it bites.", art="a huge angry brown grizzly bear with snow on its shoulders walking on all fours, open roaring mouth, big claws"),
    dict(id="sn_goat", name="Mountain Goat", role="Steady pusher", text="White with a dark face and horns. It shoves other creatures aside, so it reaches you ahead of the pack.", art="a stocky white mountain goat with short black horns and a shaggy beard, lowered head, stubborn angry expression, walking forward"),
]
SPECIALS = [
    dict(id="sn_thrower", name="Snowball Yeti", role="Lobber", uses="The Spit Cactus's lob, the Bombmaker's throw", text="Throws big snowballs at where you are going. They leave slush patches that slow you for a few seconds, so standing near them is bad.", art="a big white yeti with blue skin on its face hefting a huge snowball above its head with both arms, about to throw"),
    dict(id="sn_ram", name="Bighorn Ram", role="Charger", uses="The Bull Beetle's charge", text="Paws the ground, then charges in a line, knocking creatures aside and stopping only at something hard. Lure it into a rock and it's dazed.", art="a massive bighorn ram with huge curled horns and snow on its back, lowered head, pawing the ground, steam from its nostrils"),
    dict(id="sn_shaman", name="Frost Priestess", role="Healer", uses="The Dust Shaman's pulse (green numbers included)", text="Heals what's around her and wraps them in a brief ice armour that takes one hit. Kill her first.", art="a hooded frost priestess in pale blue robes holding a staff topped with a glowing ice crystal, long white hair, floating snowflakes, calm cold expression"),
    dict(id="sn_nitro", name="Nitro Miner", role="Exploder", uses="The Mine Crab's walk, the Horned Toad's death burst", text="A miner hugging a crate of nitro who runs at you and blows up. The blast also freezes the ground for a moment. Kill him at range or use him on his friends.", art="a panicked undead miner running while hugging a wooden crate marked with a skull full of nitroglycerin bottles, lit fuse sparking, frost on his beard"),
    dict(id="sn_sniper", name="Ski Patrol Marksman", role="Sniper", uses="The Saiga Sniper's line and lock", text="Stands far off on a ridge with a rifle. A thin red line gathers and locks; hit him to spoil his aim.", art="a ski patrol marksman in a red parka with a white cross armband and goggles, kneeling on skis and aiming a long old hunting rifle"),
    dict(id="sn_choir", name="Frost Choir", role="Bullet heaven", uses="The Monk's squad brain and energy orbs", text="A squad of ten hooded singers who stop as one and release a slow ring of ice shards, so you weave through the gaps. Aurora light rises while they sing.", art="a hooded choir monk in deep blue robes with a pale glowing face and an open singing mouth, holding a floating ring of sharp ice shards around him"),
    dict(id="sn_lurker", name="Drift Lurker", role="Burrower", uses="The Gila's and Scorpion Elite's burrowing", text="A long pale worm. A ridge in the snow moves toward you, then it erupts under your feet and throws everything near. Its ridge is the warning.", art="a giant pale snow worm erupting from the ground, ring-shaped toothy mouth wide open, chunks of snow flying, small black eyes"),
]
UNIQUE = [
    dict(id="sn_avalanche", name="Avalanche Caller", role="NEW: a moving wall and terrain that changes",
         how="A giant on the map's edge stamps its foot. A wide wall of snow then sweeps slowly across a band of the map. It pushes and buries everything it touches, creatures included, and leaves a line of snow banks behind it that you can't walk through for 20 s, cutting the map in two.",
         counter="The band is marked well ahead, and you can run across it or shelter behind a rock. The fun is luring the crowd into it. The giant can be killed to stop it.",
         build="New: a moving hazard (a wide capsule with a push, close to the boss slam's code) and temporary obstacle circles, which also need the wall steering.",
         art="a colossal stone and ice giant with a mountain peak on its back stamping one huge foot, a wall of avalanche snow bursting up behind it, roaring"),
    dict(id="sn_wendigo", name="Whiteout Wendigo", role="NEW: it takes away what you can see",
         how="A tall thin figure wrapped in its own blizzard. Inside a wide circle around it the screen goes white at the edges, and creatures beyond a few metres become faint shapes. Only their shadows show. The damage it does is modest; the fear is the point.",
         counter="Kill it and the fog lifts at once. Its position shows as a dark centre in the storm, and an arrow at the screen's edge points at it.",
         build="New: a screen-space fog around the hero that creatures fade into. It needs a light shader, and it must stay cheap on the phone (one quad, no extra pass).",
         art="a tall gaunt wendigo with a deer skull head and long antlers, skeletal arms and pale ragged fur, swirling blizzard wrapped around its body, glowing white eye sockets"),
    dict(id="sn_hag", name="Rime Hag", role="NEW: she freezes one of your weapons",
         how="Every few seconds she points at you and picks your strongest weapon. Its HUD icon ices over, a crack runs across it and the weapon stops firing for 4 s. Two at once can silence half a build. The first creature in the game that attacks your build rather than your health.",
         counter="A hit from any other weapon breaks her focus, so a build with one big gun suffers and a varied one shrugs it off. The icon's ice cracks as the time runs down, so you can plan around it.",
         build="New: a small per-weapon `jammed` timer read by every behaviour, plus the HUD's ice overlay. Low cost, high impact on build choices.",
         art="an old ice witch with frostbitten blue skin, a long crooked nose and wild white hair, wearing a cloak of frozen rags, one bony finger pointing forward with cold mist curling from it"),
]

# ------------------------------------------------------------------ items: the ones not taken
OLD_ITEMS = [
    dict(id="old_deadmans", name="Dead Man's Hand", slot="Legendary", from_="Pass 118", text="Every 8th hit of each weapon deals x5 and can still crit. A black card with aces and eights flicks over the target. Evolved: every 6th.", choice="Pulls you toward weapons that hit often over slow heavy ones. You feel the rhythm of the big numbers coming.", art="a fanned poker hand of black aces and eights held in a skeletal hand, tiny red glow"),
    dict(id="old_bell", name="High Noon Bell", slot="Legendary", from_="Pass 118", text="Every 60 s the bell tolls and time stops for 3 s: creatures, their shots and the spawns freeze while you walk, pick up and fire. Evolved: every 45 s for 4 s, and kills in the stop drop double XP. (It would need a new name: the Drifter's perk is called High Noon.)", choice="Each toll is a window to spend: break out of a ring, sweep the gems, or empty every gun into a boss.", art="a big old brass mission bell with a crack in it, ringing, golden sound waves around it"),
    dict(id="old_coin", name="Two-Headed Coin", slot="Legendary", from_="Pass 118", text="Every chest's reel lands twice and you take both. Evolved: purple chests and bosses' chests also pay 50% more gold.", choice="Chests become worth crossing the map for. Pairs with the Jade and Ruby Keys.", art="a gold coin with a laughing skull head on it spinning, a second identical face visible, sparkle"),
    dict(id="old_bounty", name="Bounty on Your Head", slot="Legendary", from_="Pass 118", text="Creatures arrive 35% faster, up to the map's cap, and hit 10% harder. Every kill pays x1.6 XP and coins. Evolved: 50% faster, x2.", choice="A pure risk dial: greedy players grab it early and race the curve. (Careful with your phone: the cap stays full more often.)", art="a torn wanted poster with a big red circle and skull target printed on it, pierced by a knife, gold coins falling"),
    dict(id="old_jar", name="Dust Devil in a Jar", slot="Legendary", from_="Pass 118", text="While you run, a whirlwind grows behind you to full size in 3 s, pulls gems and coins from 6 m and tosses the creatures it touches. Standing still it shrinks. Evolved: 2 s, wider, and it hurts what it tosses.", choice="Forks the build between running and standing: Siesta and Steady Hand reward standing still, this rewards never stopping.", art="a corked glass mason jar with a tiny angry tornado swirling inside, sand grains, a small crack in the glass"),
    dict(id="old_shadow", name="Gunslinger's Shadow", slot="Legendary", from_="Pass 118", text="Your shadow peels off and moves as your mirror image across the spot where it rose, firing your first weapon at 50% damage. It can't be hurt. Evolved: your first two weapons, and it picks up gems.", choice="Two bodies to steer with one thumb: walk so that the crowd ends up between you and the twin.", art="a black silhouette cowboy shadow peeling off the ground with a revolver raised, glowing white eyes, wisps of darkness"),
    dict(id="old_map", name="Treasure Map", slot="Legendary", from_="Pass 118", text="An X appears 40 to 60 m away with a pointer at the screen's edge. Stand on it for 3 s to dig up a purple chest and 200 gold. A new X 90 s after one is dug. Evolved: 1.5 s, and it also holds a power-up.", choice="Pulls you out of your safe loop and makes you stand still under pressure.", art="a rolled out old parchment treasure map with a dotted trail and a big red X, a small shovel lying across it"),
    dict(id="old_loader", name="Speed Loader", slot="Passive", from_="Pass 116", text="Every kill takes 0.4% off the time to every weapon's next shot, up to 4% a second; +0.2% a level. Evolved Gatling Chamber: cap 6%.", choice="Great with Tommy Gun, Orbit Saws and Salt; poor with Sun Scepter, Big Mouth and in boss fights.", art="a brass revolver speed loader with six bullets held in a round clip, gleaming, motion lines"),
    dict(id="old_key", name="Skeleton Key", slot="Passive", from_="Pass 116", text="A chest offers one more choice to pick from; level 2: 5% of black barrels hold a small chest; level 3: +10%. Different from the Jade and Ruby Keys, which bank a stat per chest.", choice="A level-up spent on no power now for better chests later.", art="an ornate old iron skeleton key with a little skull as its handle, hanging from a loop of red string"),
    dict(id="old_pup", name="Coyote Pup", slot="Passive", from_="Pass 116", text="A coyote runs at your side and bites the nearest creature for 8 damage every 0.8 s; +25% a level; a second pup at level 4. Evolved Pack Leader: three pups, and bites howl a short slow.", choice="Costs no weapon slot but is weak: safe damage or a stat that scales everything?", art="a cute scrappy coyote puppy with big ears wearing a small red bandana, mid-bark, tail up"),
    dict(id="old_silver", name="Silver Bullets", slot="Passive", from_="Pass 116", text="Shots turn toward their target (40 degrees a second, +20 a level) and do +10% to specials and Elites. Evolved Pinkerton's Mark: crits on specials always.", choice="Loved by Revolver, Boomstick, Tommy Gun and Spear; useless to Hammer, Guitarra, Salt and Orbit Saws. On a phone you aim with your feet, so it's a real comfort.", art="three shining silver bullets standing upright with a moon glint on them, a faint blue glow"),
    dict(id="old_saddle", name="Saddlebags", slot="Passive", from_="Pass 116", text="Level-ups show 4 cards instead of 3, but each level needs 8% more XP.", choice="Fewer, better level-ups: bad when you need raw levels fast, good when steering toward an evolution.", art="a pair of worn brown leather saddlebags with brass buckles, overflowing with playing cards"),
    dict(id="old_smudge", name="Smudge Pot", slot="Weapon", from_="Pass 116", text="A ring of sage smoke round you, 2.2 m, 6 damage every 0.5 s, slowing what's in it by 15%. Paths: Thick Smoke, Burning Sage, Sweet Grass (heals). Evolution: Sweat Lodge, a larger ring that pulses a knockback.", choice="The one weapon type we still lack: an aura. Safe and steady, never kills bosses.", art="a small round iron smudge pot on three legs burning bundled sage, thick curling greenish smoke rising"),
    dict(id="old_lasso", name="Lasso", slot="Weapon", from_="Pass 116", text="Every 4 s throws a loop at the densest group within 9 m, pulls everything inside 3 m to its centre and holds them 0.8 s. Paths: Long Rope, Hogtie, Dally. Evolution: Stampede Round-up.", choice="Almost no damage itself: only worth a slot with area weapons. Gathering is today only Astro's.", art="a coiled cowboy lasso rope spinning in a big loop with motion lines, a brass honda ring"),
    dict(id="old_hermit", name="The Hermit", slot="Card", from_="Pass 116", text="+10% duration a level: Molotov pools, Salt patches, mines, beams, breath, fire and freeze. Risen: when a field ends, it gives one last pulse at full damage.", choice="Shines for field weapons, nearly nothing for guns: \"longer field\" against the Ember's \"longer poison\".", kind="card", art="a tarot card showing an old hooded hermit holding up a lantern with a star inside, on a snowy mountain top"),
    dict(id="old_wheel", name="Wheel of Fortune", slot="Card", from_="Pass 116", text="+1 reroll a level; levels 2 and 4 also +1 skip. Risen: once a stage a banish refunds itself.", choice="A Card slot of no power for a better build later: strongest early, worthless once your build is set.", kind="card", art="a tarot card showing a great golden wooden wheel of fortune with strange symbols, stars around it"),
]

# ------------------------------------------------------------------ items: 15 new ones
NEW_PASSIVES = [
    dict(id="new_rod", name="Dowsing Rod", gap="Map knowledge (Megabonk's shrine and chest hunting; we have no way to find things)", text="An arrow points to the nearest unused chest, barrel, totem or structure. Level 2 and up: everything in reach gives +10% from it. Evolved: chests within 30 m show on the edge of the screen.", choice="A pick with no combat power that makes the map itself your build. Worthless on a boss rush, wonderful in a long Sundown.", art="a simple Y-shaped forked hazel twig, like a slingshot without a band, the single tip glowing blue with water drops around it; only a bare wooden twig, no gun"),
    dict(id="new_spurs", name="Spurs", gap="Skill reward for risk (Hades-style near misses; nothing rewards close play)", text="Passing within 1 m of a creature without being hit gives a stack: +1% speed and attack speed for 5 s, up to 15 stacks. Getting hit loses them all.", choice="Hug the crowd for power, or stay safe and waste it. It rewards the one thumb more than any other item and fights Heavyweight's standing style.", art="a pair of silver cowboy boot spurs with spinning star rowels, sparks flying from the rowel"),
    dict(id="new_warrant", name="Deputy's Warrant", gap="Target focus (VS has no marking, Survivor.io's bosses are hit evenly)", text="Every 10 s the toughest creature on screen is marked Wanted: it takes +50% damage from you and pays x3 XP and coins. Evolved: two at a time, and a kill resets the timer.", choice="Pulls your walking route toward the mark, away from safety. Slow-firing heavy weapons love it.", art="a folded legal warrant paper with a wax seal and a sheriff star pinned through it, a red target stamp"),
    dict(id="new_rattle", name="Rattler's Tail", gap="Panic button (Survivor.io's shockwaves; a ring today is only broken by damage)", text="When you are hit at low HP, or surrounded by eight or more, the tail rattles and creatures within 5 m flee for 1.5 s; every 12 s. Levels shorten the wait. Evolved: they also take +25% damage while fleeing.", choice="A safety item you only notice when it saves you. It uses `flee_on_hit`, so it's small to build.", art="a rattlesnake's rattle tail curled up and shaking with sound lines, sandy brown and cream bands"),
    dict(id="new_moonshine", name="Moonshine", gap="A heal-to-power conversion (Crimson Shroud-like trades; heals past full are wasted today)", text="Natural regen stops. Every heal past full HP turns into attack speed for 8 s, up to +40%. Levels raise the cap.", choice="A real trade: you give up regen, so it asks for a Cake or Hot Springs build. Terrible as a first pick, thrilling at level 25.", art="a brown clay moonshine jug marked XXX with a cork, purple-green bubbles and a little lightning crackle"),
    dict(id="new_scale", name="Assayer's Scale", gap="Skip economy (VS pays XP for skipping; a Skip is just lost here)", text="Skipping a card or chest pays 25 coins and 5% of the next level's XP, and levels raise both. Evolved: a banish pays too.", choice="Makes a lean, focused build possible. The player who wants only three items finally has a reason to refuse the rest.", art="a small brass balance scale with gold nuggets on one pan and a playing card on the other"),
    dict(id="new_canteen", name="Canteen", gap="Map synergy (water only slows you today)", text="Water no longer slows you, and leaving it gives +3 HP a second for 15 s. Evolved: enemies in water take +25% damage from you. On the Snow Map it would fill at hot springs.", choice="Turns the oases into your home base, which pairs well with the map generation ideas. Useless on a Dry Year map.", art="an old round felt-covered metal water canteen with a leather strap and a cork, droplets of water"),
    dict(id="new_camp", name="Campfire Kit", gap="A place you make (Megabonk's zone tomes; every field today is a weapon)", text="Stand still for 2 s and a campfire lights at your feet. It heals you 2% a second while you're inside and burns what walks in; it lasts 8 s after you leave. Only one at a time.", choice="Different from Siesta: you choose where the fight will be, and the crowd comes through it. Weak for runners.", art="a small crackling campfire of crossed logs with a tin coffee pot hanging over it, warm orange flames and sparks"),
]
NEW_CARDS = [
    dict(id="new_moon", name="The Moon", gap="Reach reward (nothing rewards killing from far away)", text="+6% damage a level to anything more than 6 m away. Risen: shots that have flown past 6 m also turn toward a target.", choice="The opposite of Heavyweight and Counterpunch: a build that kites and never lets anything near. Weak with Hammer, Sabre and Orbit Saws.", art="a tarot card showing a large pale crescent moon with a sleepy face above two howling coyotes and a winding path"),
    dict(id="new_hanged", name="The Hanged Man", gap="Curse with a payoff (VS's Curse, Skull O'Maniac; we have Hot Sauce only for items)", text="-6% max HP a level, +12% XP a level. Risen: when you level up you heal 10%.", choice="An early pick that speeds up the whole run but makes you fragile for all of it. Experts will fight over it, new players will regret it, and the text is plain about the price.", art="a tarot card showing a cowboy hanging upside down by one boot from a dead desert tree, calm face, golden halo round his head"),
]
NEW_WEAPONS = [
    dict(id="new_cart", name="Mine Cart", gap="A shot that follows your own trail: nothing uses the path you walked", text="A cart rolls along the path you walked in the last 6 s, hitting everything on it, then vanishes. Every 5 s. Paths: Twin Carts, Dynamite Load (it blows at the end), Long Rails. Evolution: Runaway Train, longer and throws what it hits.", choice="Your route is your aim: walk a loop round the crowd and let it close the circle. Poor if you stand still, which is exactly the point.", art="a rusty iron mine cart full of glowing gold ore on two short pieces of rail, rolling with sparks at the wheels"),
    dict(id="new_snakes", name="Basket of Rattlers", gap="Summons on the ground (Survivor.io's drones and pets; we have bees in the air only)", text="Every 3 s two snakes slither to the nearest creatures and bite, leaving poison. They last 6 s. Paths: Bigger Nest, King Cobra (a large slow one that spits), Shed Skin (a dead snake leaves a poison patch). Evolution: Snake Pit.", choice="Low up-front damage but huge in crowds; pairs with Venom and the Ember. Bad against a lone boss early on.", art="a woven straw snake charmer's basket with its lid tilted, three cartoon rattlesnakes rising from inside, fangs out"),
    dict(id="new_harpoon", name="Whaler's Harpoon", gap="Drag and pile-up (only Astro's pull exists, and it's a circle)", text="A slow heavy shot that pierces everything in a line and drags them along with it to where it stops, stacking them up. Paths: Barbed (they bleed), Reel In (it drags back toward you), Twin Barbs. Evolution: Moby's Wrath.", choice="Sets up the crowd for Dynamite and Molotov, but pulling toward you is dangerous if you take Reel In. Inspired by the Harpoon Troglodyte: you get to do it back.", art="a long straight wooden spear shaft with a big barbed iron whaling harpoon head at the end and a coil of thick rope tied to it, diagonal; a hand thrown harpoon, no gun, no rifle, no trigger"),
    dict(id="new_pick", name="Prospector's Pick", gap="A high arc thrower (VS's Axe, the most copied weapon in the genre; we have no arc weapon)", text="Throws a pick high up and it falls back down, hitting on the way up and the way down. One in ten hits knocks out a gold nugget. Paths: Twin Picks, Heavy Head (bigger and it stuns), Rich Vein (nuggets are worth more). Evolution: Mother Lode.", choice="Pays for itself in coins, so the Shop is more interesting, but it does poor damage compared with a gun. Fool's Gold loves it.", art="a miner's steel pickaxe with a wooden handle spinning in the air, a gold nugget breaking off the tip with sparkles"),
    dict(id="new_globe", name="Snow Globe", gap="Crowd stop as a weapon (VS's Clock Lancet; Cold Snap is only a passive)", text="Lobs a globe that shatters into a 4 m circle of still air: what's inside slows to a crawl for 3 s and takes +20% damage. Almost no damage of its own. Paths: Big Globe, Blizzard (hurts over time), Shatter (frozen creatures burst when killed). Evolution: Ice Age.", choice="A support weapon, a slot with no kills. Great with Dynamite and Big Mouth; the first weapon you'd take for your other weapons. Also the Snow Map's signature find.", art="a glass snow globe on a wooden base with a tiny desert cactus inside and swirling snow, an icy blue glow"),
]

# ------------------------------------------------------------------ time-limited events
TLE_INTRO = [
    "Today's meta is sparse on purpose: gold, the Upgrade board, hero purchases, looks, posters and the Collection. That shapes what an event can sell. There is no gear grid or gacha to feed, and I wouldn't add one: so an event can't lean on \"more power through dupes\". Its value has to come from three things that this game does have.",
    "**Looks and heroes people can see.** Heroes are the game's most visible, most personal purchase, and looks already have a whole system. **Runs with a twist.** Our runs are short and our content is data, so a mutator is cheap to make and feels new. **Replays.** Every run can already be replayed exactly from a seed, which means scores can be verified and old runs can stand in for rivals. That last one is rare in this genre and is your best answer to a small population.",
    "What's missing is a paying currency. The game has one currency (gold) and a currency layer ready for more. Every suggestion below assumes one small premium currency and a single-purchase pass. Survivor.io and Archero both earn on the pairing of pass and marquee event; GameRefinery reports that themed time-limited skins, characters and currencies are among the most profitable event revenue sources.",
]
TLE_PVE = [
    dict(id="tle_rush", name="Gold Rush", length="Weekend, 3 days, monthly", what="Nuggets (an event currency) lie on the map and fall from creatures, with an event map trait (Barrel Country, a goldier ground). Nuggets buy from an event shop: a limited hero look, permanent gold, one chest token a day.",
         why="Uses what we have and asks for no new code beyond a currency. It works because the Upgrade board's price curve (k squared) means gold is always wanted: late players have a genuine reason to care.",
         money=["Nugget doubler for the weekend (a one-off, the classic driver)", "Direct bundle of nuggets that finishes the shop", "Rewarded ads for double nuggets at a run's end"],
         art="an old prospector kneeling at a desert stream at sunset panning for gold, a pan full of shining gold nuggets, a mule and a pickaxe behind him, a small mining tent, warm evening light, a full scene with a painted background"),
    dict(id="tle_season", name="Bounty Season", length="4 weeks, repeating", what="A pass built on the Wanted posters: each poster done gives season stars. Free track: gold, nuggets, a skin at the end. Paid track: a hero look each week, a unique weapon look, an extra poster slot, and the last reward, a season title and poster frame.",
         why="Posters already exist, already float in over the run and already pay, so a pass adds a long goal without any new gameplay. Commitment grows every week as stars pile up. The risk is that it's content-hungry, but looks are the cheapest thing your pipeline makes.",
         money=["The paid track itself (the main earner of the whole plan)", "Star skips near the end, when commitment is highest", "Time-limited looks people can see in the title's hero spot"],
         art="a wooden saloon wall covered in many wanted posters at night lit by a lantern, a big gold sheriff badge hanging in the middle on a red ribbon with five stars along it, a full scene with a painted background"),
    dict(id="tle_debut", name="Hero Debut Trial", length="10 days, each new hero", what="A new hero (say The Dealer) can be played free for the event, on a special stage with a goal track. Finish the track and the hero is yours for less gold; or buy early. After the event the hero joins the normal roster at full price and a quest.",
         why="Heroes are the main long-term goal of the meta. Letting people play one before buying is the best sales pitch there is, and it can't annoy anyone because the hero stays in the game afterwards: no permanent FOMO on power.",
         money=["Launch bundle: the hero, a look and gold, once only, for the event's length", "Debut-only look that never returns at this price", "Replay with a shorter track for players who missed it"],
         art="a riverboat gambler hero stepping onto a stage through theatre curtains with a spotlight and gold letters banner NEW HERO, playing cards flying"),
    dict(id="tle_weird", name="Weird West Week", length="A week, every six weeks", what="One map variation from this document (Roswell, The Dry Sea) opens for a week with its own rules and a unique legendary item to earn: once you've won it, it stays in your pool for good. Next time the event returns, it offers another.",
         why="This is where unique power fits: rare, optional, earned, and the map variation work pays twice. Legendaries are already rare and loud, so owning one more is exciting without breaking anything: it's only one more item in a big pool.",
         money=["Revive tokens in the hard event (its difficulty is the sell)", "A pre-run boost: start with one extra card choice for currency or an ad", "Event look bundle in the variation's own theme"],
         art="a crashed silver flying saucer in a western desert at night with a green glow, a cowboy with a revolver standing in front looking up in shock, aurora sky"),
    dict(id="tle_drive", name="The Long Drive", length="2 weeks, all players together", what="A community goal: everyone's kills of one creature add up on a shared bar (Red Goblins, say, a billion of them). Tiers unlock rewards for everyone, even someone who played once. Your own share is shown beside the bar.",
         why="It works better with a small population than a ranked event, because a target can be set to your real numbers and adjusted. A shared bar is the friendliest thing on the list, and it makes every run count for something.",
         money=["Rewarded ads add to the bar and your own share", "A cosmetic trophy for the top contributors", "Low direct revenue on purpose: it's a retention event that makes the paying ones work better"],
         art="a long cattle drive across a western plain at sunset, dozens of longhorn cattle in a line with cowboys riding beside them, a big progress banner in the sky"),
]
TLE_PVP = [
    dict(id="tle_daily_board", name="The Daily Canyon Board", length="Every day, 1 scored attempt", what="One seed for everyone. Score from a simple formula: kills, level and time. Your board is 30 players: real ones first, then past players' real runs of earlier days as named ghosts (from the replay records), at scores just around yours. Top ten by the day's end get a small reward.",
         small="This is the main trick. A board of 30 with 40 real players a day still feels full, because the fill is made of real recordings, not bots with random numbers. Tapping any name plays their run. And because a run replays exactly, a faked score can be caught by re-simulating it.",
         money=["Extra attempts by ad or token (only the best counts)", "A premium board frame and a title for top placings", "A \"scout\" button: watch the current leader's replay"],
         art="a chalkboard outside a saloon listing outlaw names and scores with a sheriff star on the top line, a dusty cowboy looking up at it, sunset"),
    dict(id="tle_duel", name="Sheriff's Duel", length="Always on, 3 tickets a day", what="An asynchronous one-on-one: you're paired with another player's recorded run on the same seed. Beat their score. Winning takes a share of their stake of gold (paid by the system when they're offline) and moves your rating. You can watch the run that beat you.",
         small="It needs nothing live: any recorded run can be an opponent for weeks. Ratings match people who are close; when nobody is close, an older run of yours or of someone similar serves. It's an honest way to fill a small pool, and the game can say that it's a past run.",
         money=["Ticket refills (the classic async PvP driver)", "Rematch tokens: most people pay after a close loss", "Stake sizes as a gold sink, which helps the economy too"],
         art="two cowboys in a dusty western street facing each other for a duel at high noon, seen from the side, long shadows, tumbleweed between them"),
    dict(id="tle_league", name="Outlaw Leagues", length="Weekly seasons", what="Five leagues of 20: Tin, Copper, Silver, Gold, Legend. Weekly total score over any stages you play. Top five go up, bottom five go down. Each league's end reward grows, and a league badge sits beside your name.",
         small="The same 20-person trick that language apps use: a player never sees the world rank, only their small group. Real players are grouped by activity, and filled up with recorded runs where needed. Empty top leagues just show fewer people until they fill.",
         money=["Season pass stars for league placing (ties it to the main earner)", "A one-shot \"demotion shield\"", "League-only looks earned at Gold and up: seen by everyone, sold to nobody"],
         art="five ornate five-pointed western sheriff star badges in a row on a dark wooden shelf, left to right: dull tin, copper, silver, gold, and a last one glowing with rainbow light, like trophies in a saloon; only star badges"),
]

# ------------------------------------------------------------------ pass 126: what Garry chose from this book, shown as a tag on its card
BUILDING_NOW = {
    "skin_wave": "Twelve skins: two each for the Drifter, Astro, Calavera and Ironwood, one each for the other four.",
    "var_duststorm": "The third stage, after Nightfall, with its own boss and three creatures. No gusts or other new rules.",
    "new_scale": "A rare passive item. Skips pay; banishes don't.",
    "new_canteen": "An uncommon passive item.",
    "gen_roads": "Only its telephone poles, as the one broken line across the map (see below).",
}
BUILDING_GEN = [
    ("The telephone line", "One line across the whole desert, usually bending a little, often broken, often without its wire. The wire moves with the wind, more in the Dust Bowl."),
    ("The toppled cart", "On 75% of maps: a 2.5D cart on flat ground, with one or two 3D wheels lying near it at their own distances, half stuck in the sand, no collision on the wheels."),
    ("Grave crosses", "2 to 6 a map, mostly alone, sometimes three together. 3D, no collision, tilted, each one different; one in twenty is only a stick."),
]

# ------------------------------------------------------------------ pass 126: two more map ideas under Garry's rule
NEW_MAP_RULE = "I would like to avoid any kinds of generation elements that create big obstacles for players to have trouble traversing. Our enemies don't think so I don't want them to be dealing with A* pathfinding or anything like that. I don't want them to get stuck."
NEW_MAP_IDEAS = [
    dict(id="gen_fields", name="The Old Forty", tag="Dead fields ploughed into the ground",
         look="One to three huge tilted rectangles of old ploughed ground, 30 to 50 m a side, each turned its own way. Long straight furrows in darker soil, with pale blown sand eating the edges. Dead corn stubble, ankle high, stands along some rows with long gaps. (A \"forty\" is forty acres, the unit a homesteader farmed.)",
         why="The sand has no straight lines today, so the ground gives you no sense of direction, and you only feel your speed when a prop goes by. Furrows give you both: they stream past when you run along them and flicker when you cross them. From the high camera a field reads at once, even at phone size, and every seed turns them differently, so it becomes \"the run with the diagonal fields\". It's also the true story of the Dust Bowl: this ploughing is what caused the storm.",
         rule="It's paint. The furrows have no height and the stubble has no collider, so the hero and the crowd run straight across, and no steering code ever reads it. It doesn't slow anyone either, since you asked for no extra mechanics there.",
         cost="Low. One new primitive: flat ground paint, a mesh draped over the map's height the way the ground shadows already are, with a furrow texture that fades at its edges. Every field on the map merges into one mesh, so one draw call. Stubble is one MultiMesh of at most about 400 short stalks, one more. Art: one tiling furrow picture from the `gen_sand.py` recipe. Keys in `timeline_data.dressing.fields`: count, size, stubble share. Seeded from the map seed, so replays hold.",
         art="seen from a high camera looking down at about 45 degrees, flat desert sand with a huge tilted rectangle of abandoned ploughed farmland painted on the ground, dozens of long thin perfectly straight parallel furrow stripes of dark brown soil and pale crests, completely flat like a pattern on the ground with no raised beds and no banks, running diagonally across the whole picture and past the edges of the picture, the field's edges soft and half buried by pale blown sand, sparse dead dry corn stubble, tiny short stalks only ankle high with long gaps between them, one tiny cowboy gunslinger seen from above near the centre, very small for scale, a few small dry shrubs and one small barrel on the sand beyond the field, warm late afternoon light, no buildings, no fences, no walls, no trees, no sky"),
    dict(id="gen_footings", name="Where the House Was", tag="The floor plan of a farm that gave up",
         look="Two to four a map, each 8 to 14 m across. The outline of a house that's gone: ankle-high stone footings in the shape of two or three rooms, a flat hearth slab, two steps going nowhere, and one or two things left behind, such as an iron bed frame or a claw-foot tub half full of sand. Turned a different way each time.",
         why="A floor plan is one of the few things that looks better from a high camera than from the ground. You read it at a glance on a phone, and it tells a small sad story: somebody lived here. It breaks up empty sand at a size nothing else on the map has, bigger than a prop and smaller than a landmark. It fits the Dust Bowl's abandoned farms and still works as a ghost ranch in the plain desert.",
         rule="The footings and the hearth are flat paint, and the belongings come no higher than the knee with no collider. Nothing stands up, so there's nothing to walk round and nothing for a creature to get stuck on. The crowd's steering never hears about it.",
         cost="Low, and cheap once The Old Forty exists, because it's the same flat ground paint with one more picture sheet. Art: four or five floor plans painted from above by Klein and three small props through `gen_prop_variants.py`. Placement can share the cart's flat-ground check. One draw call for the plans, one MultiMesh for the belongings, no new rule.",
         art="seen from a high camera looking down at about 45 degrees, the ruined footprint of a lost farmhouse lying flat on desert sand, a single line of flat grey fieldstones half sunk into the sand tracing three rooms of a floor plan like a drawing on the ground, barely rising above the sand, with gaps in the line, a flat square stone hearth slab, two low stone doorsteps, a small rusty iron bed frame and a small white claw foot bathtub half full of sand inside the rooms, one cowboy gunslinger standing inside one room, each room many times wider than he is, the bathtub about as long as he is tall, open sand all around with a few small dry shrubs, warm late afternoon light, no standing walls, no chimney, no roof, no sky"),
]

# ------------------------------------------------------------------ pass 126: the lots of Proposal C's Main Street (only the mock uses these)
STREET_ART = [
    dict(id="st_sheriff", art="a sheriff's office: a small square timber jailhouse with a barred window, a porch with one post leaning, a big tin star fixed above the door"),
    dict(id="st_chapel", art="a tiny white wooden frontier chapel with a small steeple, peeling paint, two crooked steps up to its door"),
    dict(id="st_fortune", art="a fortune teller's painted wagon: a wooden wagon with a rounded roof in purple and gold, a glowing crystal ball on a small table under a striped awning"),
    dict(id="st_saloon", art="a big two storey saloon with a tall wooden false front, swinging doors, a balcony with a railing, warm lit windows"),
    dict(id="st_doc", art="a doctor's large canvas tent on a plank floor, bottles and a stone mortar and pestle on a crate by the door flap, a small wooden sign shaped like a mortar"),
    dict(id="st_livery", art="a timber livery stable: a barn with a big dark open doorway, horseshoes nailed along the beam, hay bales, a water trough"),
    dict(id="st_outfitter", art="a small plank outfitter's shop with a canvas awning, a quilted leather coat and a steel breastplate on stands out front"),
    dict(id="st_gun1", art="a gunsmith's camp: a patched canvas tent, a small anvil on a tree stump, a wooden rack with two rifles"),
    dict(id="st_gun2", art="a small plank gunsmith's shack with a tin roof and a stovepipe, a wooden sign shaped like a revolver, an anvil by the door"),
    dict(id="st_gun3", art="a handsome one storey gunsmith's shop with a wooden false front, a large window with guns on display, a brick chimney with a little smoke, a big wooden revolver sign"),
    dict(id="st_gun4", art="a grand two storey brick gunsmith's works, a tall smoking chimney, a huge golden revolver mounted over the double doors, iron balconies"),
    dict(id="pouch_silver", kind="charm", art="one small rounded leather belt pouch with silver studs and a silver buckle, seen from the front, only the pouch"),
]

# ------------------------------------------------------------------ pass 126: restructuring the Upgrade board
# The game's real forms: talent, form index, name, one rank's step in short, three of them together. Numbers from content/talents/*.
FORMS = {
    "muscle": dict(icon="drive_0", name="Muscle", talent="Drive", step="+8% attack", three="+26% attack damage"),
    "tempo": dict(icon="drive_1", name="Tempo", talent="Drive", step="-6% cooldown", three="-17% cooldown"),
    "padding": dict(icon="grit_0", name="Padding", talent="Grit", step="+10% max HP", three="+33% max HP"),
    "plate": dict(icon="grit_1", name="Plate", talent="Grit", step="+6% reduction", three="+18% damage reduction"),
    "boots": dict(icon="stride_0", name="Boots", talent="Stride", step="+5% speed", three="+16% move speed"),
    "lodestone": dict(icon="stride_1", name="Lodestone", talent="Stride", step="+18% pickup", three="+64% pickup radius"),
    "notes": dict(icon="study_0", name="Field Notes", talent="Study", step="+10% XP", three="+33% XP"),
    "poultice": dict(icon="study_1", name="Poultice", talent="Study", step="+0.3 regen", three="+0.9 regen a second"),
    "omen": dict(icon="fortune_0", name="Omen", talent="Fortune", step="+0.12 luck", three="+0.36 luck: rarer items more often"),
    "greed": dict(icon="fortune_1", name="Greed", talent="Fortune", step="+12% gold", three="+40% gold"),
    "reroll": dict(icon="choice_0", name="Reroll", talent="Choice", step="+1 reroll", three="+3 rerolls a run"),
    "banish": dict(icon="choice_1", name="Banish", talent="Choice", step="+1 banish", three="+3 banishes a stage"),
    "skip": dict(icon="nerve_0", name="Skip", talent="Nerve", step="+1 skip", three="+3 skips a stage"),
    "wind": dict(icon="nerve_1", name="Second Wind", talent="Nerve", step="+10% revive", three="+30% health on revive"),
}
FLAVOUR = {"Drive": "Hit harder, or hit sooner.", "Grit": "Thicker skin, or harder bones.", "Stride": "Cover the ground, or pull it to you.",
           "Study": "Learn faster, or mend slower.", "Fortune": "Better cards, or fatter purses.", "Choice": "See another, or throw one away.",
           "Nerve": "Pass on one more, or get back up."}
HEROES = {
    "ironwood": dict(name="Ironwood", price=1000, weapon="the Spear", icon="ironwood_icon", place=2),
    "astro": dict(name="Astro", price=1500, weapon="the Gravity Gun", icon="astro_icon", place=3),
    "calavera": dict(name="Calavera", price=2000, weapon="the Guitarra", icon="calavera_icon", place=4),
    "solenne": dict(name="Solenne", price=2500, weapon="the Sun Scepter", icon="solenne_icon", place=5),
    "fadeaway": dict(name="Fadeaway", price=3000, weapon="the Basketball", icon="fadeaway_icon_c", place=6),
    "buck": dict(name="Jeżyk", price=3500, weapon="the Frisbee", icon="buck_icon_f", place=7),
    "may": dict(name="May", price=4000, weapon="the Big Mouth", icon="may_icon_p", place=8),
}
# The whole tree, bottom to top: ("plain", name, form icon, effect), ("fork", form, form), ("hero", id), ("mile", name, icon, effect).
TREE_SECTIONS = [
    dict(id="sundown", name="Sundown", ready="Gets you ready for Nightfall", rows=[
        ("plain", "Long Stride", "boots", "+2.5% speed, +9% pickup"),
        ("plain", "Trail Journal", "notes", "+5% XP, +0.15 regen"),
        ("fork", "muscle", "tempo"),
        ("hero", "ironwood"),
        ("fork", "padding", "plate"),
        ("plain", "Lucky Deck", "reroll", "+1 reroll"),
        ("hero", "astro"),
        ("fork", "boots", "lodestone"),
        ("mile", "Dead Eye", "m_deadeye", "+6% crit chance"),
    ]),
    dict(id="nightfall", name="Nightfall", ready="Gets you ready for The Dust Bowl", rows=[
        ("hero", "calavera"),
        ("fork", "notes", "poultice"),
        ("plain", "Bull Hide", "padding", "+5% max HP, +3% reduction"),
        ("hero", "solenne"),
        ("fork", "omen", "greed"),
        ("mile", "High Stakes", "m_stakes", "Opens the Stakes dial on the Stages screen"),
    ]),
    dict(id="dust", name="The Dust Bowl", ready="Gets you ready for Blood Moon", rows=[
        ("hero", "fadeaway"),
        ("fork", "skip", "wind"),
        ("plain", "Hair Trigger", "muscle", "+4% attack, -3% cooldown"),
        ("hero", "buck"),
        ("fork", "reroll", "banish"),
        ("mile", "Wide Load", "m_area", "+15% area of effect on every weapon"),
    ]),
    dict(id="blood", name="Blood Moon", ready="The long top: add rows here for ever", rows=[
        ("hero", "may"),
        ("fork", "muscle", "tempo"),
        ("plain", "Lucky Penny", "omen", "+0.06 luck, +6% gold"),
        ("fork", "padding", "plate"),
        ("mile", "Card Sharp", "m_cards", "+2 rerolls, +1 banish, +1 skip"),
        ("fork", "boots", "lodestone"),
        ("plain", "Tough Luck", "skip", "+1 skip"),
        ("fork", "notes", "poultice"),
        ("mile", "Big Iron", "m_iron", "+25% crit damage"),
        ("fork", "omen", "greed"),
        ("mile", "Boot Hill Pass", "m_revive", "One free revive a run"),
        ("fork", "skip", "wind"),
        ("mile", "Extra Barrel", "m_amount", "+1 projectile on every gun"),
        ("fork", "reroll", "banish"),
        ("mile", "Living Legend", "m_legend", "+10% attack, +10% max HP, +5% speed"),
    ]),
]
# Where the printed tree breaks into strips (row numbers, inclusive): Blood Moon's long top in three.
TREE_STRIPS = [(1, 15), (16, 25), (26, 35), (36, 44), (45, 56), (57, 64)]

UP_A_QUOTE = "Talent Tree with mutually exclusive paths. Simply put instead of letting Players choose what to upgrade they have to dump their coins directly into a single path with occasional choices for which path to take. It will be less choice, but allows me to add special milestone nodes in the path that cost more but give more as well. Better for balancing too since I don't have to guess. The tree only goes up and I can extend it as much as I like. Some nodes might actually just be Hero unlocks or something."
UP_QUOTE = "It currently doesn't look very presentable. I like the choices that players have to make, but I don't like that it looks like that."
UP_TODAY_FACTS = [
    "**The rules today.** Eight talents, two forms each, seven ranks. Rank k of a talent costs k x k x its rank 1 (100 for Stakes, up to 450 for Grit). Every rank is bought in one form and keeps it. Reset Upgrades gives half back.",
    "**The numbers today.** The whole board is **353,500 gold**. A very good run banks about 1,140 (your Drifter, Stage 1, level 30, 13:06 in, banked 1,138), so that's about **310 very good runs**. Later stages pay more: the best recent Stage 2 runs in the remote records banked 3,700 to 4,400. Stage 2 was tuned for a quarter of the ranks (about 7,600 gold) and the last stage for half (about 35,350).",
]
UP_TODAY_WHY = [
    ("It's a form, not a place.", "Eight identical tiles with the same five layers. Nothing is bigger than anything else, so the eye has nowhere to land."),
    ("There's too much to read at once.", "16 icons, 16 names, 16 effect lines, 56 rank pips and 8 buttons on one screen, before you've bought a thing."),
    ("A purchase barely shows.", "One dark pip gets a small icon. A rank 7 tile looks like a rank 1 tile with more pips, so spending 22,050 gold feels like filling in a box."),
    ("A short purse turns it into a wall.", "The second picture: a column of grey buttons with red numbers, 900 next to 20,825, and no hint which one matters."),
    ("There's no destination.", "Nothing says what you're working towards, and the top rank is only half a step bigger."),
]
UP_TODAY_KEEP = "The kit isn't the problem: the frames, buttons and fonts are fine. The structure gives them nothing to show off. And one thing is right and stays in all three proposals: **the pairs**. Muscle or Tempo and Padding or Plate are real questions."

# Proposal words. Numbers in {braces} are filled in by tools/ideas_mocks.py from the tree above, so they can't drift.
UP_A = dict(
    how="You don't pick what to upgrade. One path goes up the screen and there's one BUY button: the next node. Every so often the path splits in two for three nodes. You pick a side, the other side closes, and the two sides join again above. That's where your pairs live. You make **14 real choices** on the way up instead of 56 small ones, and each one lasts three purchases.",
    kinds=[
        ("Plain node", "Half a step of both sides of a pair (\"+5% max HP, +3% damage reduction\"). Rerolls and skips can't be halved, so those give +1. Cheap, and it asks no question. 7 of them."),
        ("Fork", "Three nodes of one form, each worth exactly one of today's ranks. Each pair comes up twice, so you can go all Muscle or take both. 14 forks, 42 rows."),
        ("Milestone", "Twice the price of the nodes around it and worth far more, in something no rank gives today: crit, area, a projectile, a free revive. 8 of them, about one every eight rows, and each one is drawn big."),
        ("Hero", "Just a hero, at today's price. All seven come in the first 36 rows, so nobody waits for the endgame to get May."),
    ],
    stakes="**One thing can't go on a single path: Stakes.** A forced node that makes creatures harder would punish everyone who climbs. So Stakes leaves the tree and becomes a free dial on the Stages screen (either form, rank 0 to 7, set per run, today's numbers), opened by the milestone High Stakes. That's a rule you didn't ask for, so it's yours to veto.",
    scroll="**How it scrolls.** The screen opens with the next node in its lower third. Below it is what you've bought, above it what's coming, with locked nodes in grey so you can see the next milestone from far off. Drag to look around. The dock at the foot always shows the next purchase with its button in the same spot, so buying is one thumb. The sky behind the tree changes by section, from Sundown to Nightfall to The Dust Bowl to Blood Moon, so you feel the climb.",
    economy="**Gold.** Today's income, nothing new. A node in row n costs **100 + 3 x n x n**. A milestone costs twice that. A hero costs what he costs today. The whole tree costs about what the whole board costs today, but the shape is different: early ranks come faster, so a new player feels them in his first few runs, and the two meet at the top (the table below).",
    balance="**Why you stop guessing.** Anyone who has spent a given amount of gold is on one known row. All that differs between two players on that row is which side of each fork they took. So you can tune a stage to a row (\"Nightfall expects row 15\"), and `difficulty_probe.gd` can test the all-left and all-right builds at that row, which is the whole range. Today's board has 36 ways to hold one talent, so 36^8, about 2.8 trillion boards. The tree has at most 2^14 = 16,384, and each fork's two sides cost the same, so you only ever balance one pair at a time.",
    extend="**Extending it.** Add rows at the top. Nothing below moves. Milestones can be anything the game can do, heroes included, and a new hero is one row.",
    json_="""// content/upgrade_tree/main.json: every row is data, edited in the Level Editor's Tree tab
{ "price": {"type": "quadratic", "base": 100, "k": 3},
  "rows": [
    {"kind": "plain", "name": "Long Stride", "icon": "drive_0",
     "effects": [{"stat": "move_speed", "op": "mul", "value": 0.025, "target": "player"},
                 {"stat": "magnet", "op": "mul", "value": 0.09, "target": "player"}]},
    {"kind": "fork", "talent": "drive", "nodes": 3},        // both forms, steps and icons come from the talent
    {"kind": "hero", "character": "ironwood"},              // his price comes from his JSON
    {"kind": "milestone", "name": "Dead Eye", "icon": "deadeye", "price_mult": 2,
     "effects": [{"stat": "crit_chance", "op": "add", "value": 0.06, "target": "player"}]}
  ] }""",
    content="**As content.** One JSON file, using the same `Effect` as everything else, so a row needs no code unless it does something new. The Level Editor's Mirror tab becomes a Tree tab: rows in order, add a fork or a milestone, and each row shows its price, the gold so far and how many very good runs that is.",
    migrate="**Old saves.** The first time the screen opens, the game takes what you actually spent (`Save.talent_spent`) and walks up the tree with it. Each fork goes to the side you held more ranks in. Hero nodes on the way are free, whether you owned him or not, and the tree is cheaper per rank, so nobody ends up with fewer ranks. Someone who piled everything into one talent gets them spread along the path instead, which he may not like, so the first Reset after this is free. What doesn't buy a whole node goes back in the purse. Stakes ranks come back as gold and set the dial to the same rank. Toasts say so once, as the Stakes refund did in pass 88.",
    cost="**Cost: medium code, small art.** A tree data class and loader, Save and its migration, the screen drawn in one pass like today's rank pips, the Tree tab, the Stakes dial on the Stages screen, tests. Art: 8 milestone icons at most (the mock uses icons the game already has). One pass with two lanes.",
    decide=[
        "Stakes as a free dial, as above, or keep it some other way?",
        "Changing a fork: today's Reset Upgrades takes everything back at half, which on one path is a heavy hammer. I'd add a cheap swap: pay 25% of what that side cost and its three nodes move to the other side. Yes or no?",
        "Hero nodes need gold only, which retires today's hero unlock quests (Calavera's boss kill, Fadeaway's three Snipers). Retire them, or leave them as a free shortcut past the node's price?",
        "Early ranks cost less than today (the table above), so a new player reaches Stage 2 sooner. Keep that shape, or raise the early rows?",
    ],
)
UP_B = dict(
    how="You own charms and level them with gold. Every form on today's board is one charm: Muscle, Tempo, Padding, Plate and so on, sixteen in all. But a hero only carries what fits in his belt: at most six pouches, **two Iron** (fighting), **two Leather** (the trail) and **two Silver** (luck). Swap them for free between runs, and each hero keeps his own belt.",
    why="**Why it's different.** Power stops being a line or a pile and becomes a budget. Muscle or Tempo is still the question, but now you answer it per hero, and you can change your mind tomorrow. New builds appear too: Muscle plus Tempo with no defence at all is now a choice. Difficulty and Boss become Silver charms, so Stakes' extra XP and coins finally cost you something real: a pouch.",
    look="**How it looks.** The hero stands large on the real menu backdrop with his pouches round him, the way gear screens work in Archero and Survivor.io. A charm's frame climbs the game's rarity colours with its level, grey at LV 1 up to gold at LV 5, so the belt visibly gets richer. It's the one screen where your hero art does the selling.",
    economy="**Gold.** Today's income and today's price ladder: level k of a charm costs k x k x its talent's rank 1. Levels stop at 5 for now. You start with one pouch of each kind; the next three cost 600, 1,500 and 4,000. Six charms at level 3 cost {b_half} with the pouches, about today's half board ({today_half}). Six at level 5 cost {b_full}, so you reach full power in about {b_full_runs} very good runs, not 310. After that gold buys options, not power: all sixteen at level 5 costs {b_all}.",
    balance="**Balancing.** The ceiling is known: pouches x top level. A new charm can never raise it, only widen the choice, so you can add forever without power creep. The belts that change a fight are Iron pair x Leather pair, 6 x 6 = 36; with Silver's 28 pairs it's 1,008 in all, against 2.8 trillion today. The catch: the very top is weaker than today's full board, because you can't hold everything, so Endless and anything tuned for the full board needs one pass with the run sim. The quarter and half targets stay about where they are.",
    json_="""// content/talents/drive/drive.json: forms stay as they are, each gains its pouch kind
{ "forms": [ {"name": "Muscle", "pouch": "iron", "text": "...", "effects": [ ... ]},
             {"name": "Tempo",  "pouch": "iron", "text": "...", "effects": [ ... ]} ] }

// content/upgrade_belt.json: the pouches in the order they open
{ "max_level": 5,
  "pouches": [ {"kind": "iron", "price": 0}, {"kind": "leather", "price": 0}, {"kind": "silver", "price": 0},
               {"kind": "iron", "price": 600}, {"kind": "leather", "price": 1500}, {"kind": "silver", "price": 4000} ] }""",
    content="**As content.** Charms are today's talent folders, so a new charm is one form in a JSON file, and a new pouch is one row. The Level Editor's Mirror tab gains the pouch table and the kind per form.",
    migrate="**Old saves.** Each form's ranks become that charm's level, and any rank above level 5 is refunded. Charms have their own ladders, so most players get gold back: Drive with 2 Muscle and 2 Tempo paid 30 x 375 = 11,250, while Muscle LV 2 and Tempo LV 2 now cost 10 x 375 = 3,750, so 7,500 comes back. Stakes ranks become the Difficulty and Boss charms. Pouches come free up to what the old board was worth, and the belt fills from the highest levels.",
    cost="**Cost: medium code, almost no art.** The belt screen and pop-up from the kit, `Run` folding only what's in the belt, Save and migration, the Level Editor. The 16 icons already exist. One pass, plus one balance pass with the sim, because the ceiling moves.",
    risk="**The risk.** It adds a chore before a run, and some players will never open it. Silver may also read as a tax, because Reroll and Skip don't feel like power.",
)
UP_C = dict(
    how="Your upgrades are a town. Each talent is a building on one street going up the screen: **Gunsmith** is Drive, **Outfitter** Grit, **Livery** Stride, **Doc's** Study, **Fortune Teller** Fortune, **Saloon** Choice, **Chapel** Nerve, **Sheriff's Office** Stakes. Tap one and you get today's choice for its next rank: the same two options at the same price. The building grows as ranks go in, from a tent to a shack to a storefront to a landmark. Heroes you own stand in the street.",
    rule="**One new rule keeps it honest:** no building can be more than two ranks ahead of your smallest one (the Sheriff's Office doesn't count), so you get \"Build up the Doc first\". It's a rule you didn't ask for, and it's what makes this easier to balance than today.",
    why="**Why it's different.** It's the only one of the three where buying something changes a picture. You open the screen and see everything you've ever earned, all at once. It's also the code's old name for this screen, the Homestead, finally made true.",
    economy="**Gold.** Exactly today's: 353,500 for the whole town, 310 very good runs, and no stage needs tuning again. If that's too long, it's the same edit as today (the price lists in the talents' JSON).",
    balance="**Balancing.** The weakest of the three, and honest about it: it's today's board with a fence. With the rule, a player with 21 ranks has about 3 in every building, give or take one, so `difficulty_probe.gd` has a small band to test. Forms stay free per rank, so the choice count is the same as today. Milestones can only come as small bonuses on a building's new look.",
    json_="""// content/talents/drive/drive.json: today's file, plus where it stands and how it looks
{ "id": "drive", "name": "Drive", "cost": [375, 1500, 3375, 6000, 9375, 13500, 18375],
  "forms": [ ... ],
  "building": { "name": "Gunsmith",
    "looks": [ {"from_rank": 1, "art": "gunsmith_tent.png"},  {"from_rank": 3, "art": "gunsmith_shack.png"},
               {"from_rank": 4, "art": "gunsmith_store.png"}, {"from_rank": 7, "art": "gunsmith_works.png"} ] } }""",
    content="**As content.** A new building is one new talent folder with four paintings; the street scrolls, so there's always a lot for it. Each new building raises the ceiling, as a new talent would today. The Level Editor's Mirror tab gains the name and the looks.",
    migrate="**Old saves.** Nothing to migrate: it reads `Save.talent_picks` as it is. A save already past the two-rank rule keeps what it has and simply can't widen the gap.",
    cost="**Cost: small code, big art.** The street is two columns and a pop-up the kit nearly has. The art is the job: 8 buildings x 4 looks is 32 paintings, at four seeds each that's about 130 renders picked by eye, and Flux bends signs and porches.",
    risk="**The risk.** Eight paintings on one phone screen have to read at about a third of its width each, in every stage of growth. If they don't, it's a pretty picture you have to squint at.",
)
UP_ALSO = "**Why these two alternatives.** Your tree makes power a line you climb. I looked for the two other shapes it can take: a budget you spend again before every run (B), and a place you build and can look at (C). Looked at and dropped: a trail map with stops is your tree drawn differently, so if you like that look the tree can wear it. A wanted board of posters is today's tiles on paper. A deck of permanent cards plays like the Gunbelt, but would be confused with the Cards you pick in a run."
UP_COMPARE = [
    ("", "A. The Tree", "B. The Gunbelt", "C. Main Street"),
    ("In a word", "Climb", "Equip", "Build"),
    ("Your pairs", "14 forks, 3 nodes each; closed once picked", "Every run, per hero, free to change", "Every rank, as today"),
    ("First look on a phone", "A clear path and one button; only as good as its milestones", "The hero large, frames that climb the rarity colours", "The prettiest by far, if the paintings read"),
    ("What a purchase shows", "The line moves up; milestones get a big moment", "A frame changes colour", "A building grows"),
    ("Balancing", "Best: one known row, 16,384 builds at most", "Good: a known ceiling, 36 fight belts", "Weakest: today's board with a fence"),
    ("Extending", "Add rows at the top, for ever", "Add charms with no power creep; a pouch is a deliberate step", "Add a lot; raises the ceiling"),
    ("Hero unlocks", "Nodes on the path, as you wanted", "Stay on the Heroes tab", "Stay on the Heroes tab; owned ones stand in the street"),
    ("Gold to fill it", "{a_total} (about {a_runs} very good runs)", "{b_full} for one full belt, {b_all} for everything", "353,500 (310), as today"),
    ("Old saves", "A walk up the tree, never fewer ranks", "Levels carry over, most get gold back", "Nothing to do"),
    ("Build cost", "Medium code, small art", "Medium code, no art, one balance pass", "Small code, big art"),
    ("Main risk", "Long stretches of small nodes; regret over a fork", "A chore before each run", "Paintings too small to read"),
]
UP_REC = [
    "**Build A, the Tree.** It's the only one that answers both of your complaints: it gives the screen one clear thing to look at, and it stops you guessing at balance. It's also the only one with a natural home for hero unlocks, and buying is one button in one spot, which suits this game's one thumb.",
    "**The honest catch** is that a tree of small nodes can be dull, and it takes choice away. That's why the version above has forks that last three nodes, a milestone about every eight rows, and a sky that changes as you climb. If I had to cut anything to save time I'd keep the milestones and cut the sky.",
    "**Why not B:** it's my favourite as a game, because it's the only one that asks a new question every run. But it moves the ceiling, so it needs real balance work, and it doesn't solve your guessing as cleanly as a single line. It could arrive later as a milestone at the top of the tree. **Why not C:** it would look the best and cost the least code, but it's today's system underneath, so you'd still be guessing, and 32 paintings is a lot to spend on a menu.",
    "If you pick A, the four questions under it are all I need before starting.",
]
UP_NOTE = "Every number in these proposals is a starting point, worked out against today's gold, not a tuned value. The mocks are drawn from the game's real colours, fonts, icons and names."
