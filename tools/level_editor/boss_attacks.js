'use strict';
// Pass 72 (lane BOSS): the Boss attacks tab. Garry: "add the ability to create custom attacks for bosses. Like colouring
// the projectile, deciding the ranges, etc. Like create custom ones that I can name and stuff". Every attack is a content
// folder (content/boss_attacks/<id>/<id>.json, game/core/data/BossAttackDef.gd); this page lists them, creates one from a
// template, names it, edits every number with its help (the grey number is the game's default), previews it from above
// to scale (the boss, the landing spots and their gaps, the hero; a time slider and Play), assigns it to any boss or
// scripted creature (their boss.attacks gets {"name": id}) and deletes it. The routes are boss_attacks_io.py; the maths
// boss_model.js. Ctrl+S saves the open attack, Ctrl+Z / Ctrl+Y step through its edits.
const BossAttacks = (() => {
  const { el, svg, clear, fmtN } = U;
  const M = BossModel;
  const S = {
    data: null, loading: false, failed: null,
    open: null, draft: null, base: null, mtime: null, history: [], future: [],
    seed: 1, t: null, playing: false, busy: false, creating: null, deleting: false, msg: null,
  };

  // ------------------------------------------------------------------ the field table (BossAttackDef's groups)

  const o = (v, label, help) => ({ v, label: label || v, help: help || '' });
  const LOOK_OPTS = [o('spike', 'spike: a barb, point first'), o('spit', 'spit: the Spit Cactus\'s ball'), o('pellet', 'pellet: a lead ball'), o('shard', 'shard: a golden sliver'), o('rock', 'rock: a stone'), o('fire', 'fire: a glowing ball'),
    // pass 113 (lane BOSS): the bullet-heaven looks (a pattern draws only these: paintings with a thick ink outline)
    o('burning_tumbleweed', 'burning tumbleweed (pattern)'), o('venom_blob', 'venom blob (pattern)'), o('brand_fireball', 'branded fireball (pattern)')];
  // pass 113 (lane BOSS): a pattern's emitter shapes, aims, the boss's wind-up looks and his shells
  const ESHAPE_OPTS = [o('spiral', 'spiral: arms turning as they fire'), o('ring', 'ring: all round, an opening facing its aim'), o('fan', 'fan: a spread of bullets'), o('sweep', 'sweep: a fan swinging left and right (a sprinkler)'), o('wall', 'wall: a line across, an opening in it'), o('rose', 'rose: a ring that opens into petals')];
  const EAIM_OPTS = [o('hero', 'at the hero (as the bullets begin)'), o('track', 'at the hero, every volley'), o('fixed', 'fixed (due east)'), o('random', 'a random way, every volley')];
  const TLOOK_OPTS = [o('none', 'none'), o('spin', 'spin: he spins up (the King)'), o('rear', 'rear: rears up, throat glowing (the Gila)'), o('drive', 'drive: drives his iron into the ground (the Brander)')];
  // pass 115 (lane BOSS): a pattern's barrier (BossAttackDef.BARRIER_LOOKS, BARRIER_MODES, BARRIER_HOLDS, ...)
  const BLOOK_OPTS = [o('none', 'none (no barrier, no reach rule)'), o('tumbleweed_fence', 'tumbleweed fence: staked tumbleweeds and ropes, smouldering (the King)'), o('cactus_fence', 'cactus fence: spiny organ-pipe cactus with venom blooms (the Gila)'), o('iron_fence', 'iron fence: black bars with white-hot spear heads and branding irons (the Brander)')];
  const BMODE_OPTS = [o('range', 'at the bullets\' range (less the Inset)'), o('fixed', 'at a fixed radius')];
  const BHOLD_OPTS = [o('bullets', 'until the bullets end (falls as he is dazed)'), o('spent', 'until his dazed seconds end too')];
  const BCRE_OPTS = [o('block', 'kept on their side'), o('pass', 'walk through it')];
  const BBUL_OPTS = [o('stop', 'vanish at it (a spark)'), o('pass', 'fly on through it')];
  const SHELL_OPTS = [o('none', 'none (his glowing rim only)'), o('tornado', 'tornado: a sand tornado round him'), o('scales', 'scales: a glow behind him, armour-bright'), o('pillar', 'pillar: a pillar of fire')];
  const SHAPE_OPTS = [o('rings', 'rings round the centre'), o('grid', 'a hex grid'), o('spiral', 'a sunflower spiral'), o('random', 'random, kept apart')];
  const ORDER_OPTS = [o('out', 'out: nearest first'), o('in', 'in: farthest first'), o('random', 'random'), o('sweep', 'sweep: round like a clock hand')];
  const AIM_OPTS = [o('hero', 'at the hero'), o('random', 'a random way'), o('fixed', 'fixed (due east)')];
  const CENTER_OPTS = [o('boss', 'round the boss'), o('hero', 'round the hero\'s spot')];
  const TEL_OPTS = [o('circles', 'circles on the landing spots'), o('lines', 'lines down the shots\' way'), o('ring', 'a ring round its reach'), o('none', 'no warning')];
  // pass 73 (lane GROUND): a rain's landing (BossAttackDef.LANDING_MODES)
  const MODE_OPTS = [o('stagger', 'stagger: one after another, from its back'), o('volley', 'volley: one spew from its mouth, landing together')];
  const KIND_OPTS = [
    o('rain', 'rain: shots thrown up and out, landing on a pattern', 'projectiles thrown up and out in every direction, landing on the points of a pattern round the boss, each spot warned before it lands; the hero is hit only inside a landing circle'),
    o('volley', 'volley: straight shots out from the boss', 'shots flying straight out over a fan (or all round), in waves; a shot hits the hero once and is gone'),
    o('ring', 'ring: rings racing out', 'rings racing out from the boss; each hits the hero once as it passes him'),
    o('slam', 'slam: a blast round the boss', 'a blast round the boss (or the hero\'s spot) after the wind-up'),
    o('script', 'script: a built-in with your numbers', 'one of the built-in attacks (rumble, slam, roll, ...) under its own name with its own numbers'),
    // pass 113 (lane BOSS)
    o('pattern', 'pattern: a bullet heaven (rare, long, guarded)', 'a bullet-heaven attack: never in the boss\'s cycle, it comes on its own trigger (not before 15 s of the fight, the first under 60% HP or 45 s in, then every 45 s); a big tell, then several seconds of slow bullets from its emitters while the boss is guarded; then he is spent and takes extra'),
  ];
  const PAT = ['pattern'];
  const ALL = ['rain', 'volley', 'ring', 'slam'];
  const SHOTS = ['rain', 'volley'];
  // (pass 113: the rows a pattern reads too)
  const ALLP = ALL.concat(PAT);
  const SHOTSP = SHOTS.concat(PAT);
  const SECTIONS = [
    ['projectile', 'Projectile', 'what flies: its look, colour and size, how it flies'],
    ['pattern', 'Pattern', 'where it lands or goes: the layout, the ranges, the gap rule'],
    ['landing', 'Landing', 'the circle a rain\'s shot hurts in'],
    ['telegraph', 'Telegraph', 'how the hero is warned'],
    ['_top', 'Damage and push', 'what a hit does'],
    ['timing', 'Timing', 'wind-up, stagger, rest'],
    ['spew', 'Spew', 'a volley rain: the crouch, and the shots out of the boss\'s mouth (pass 73)'],
    ['sounds', 'Sounds', 'ids from content/sounds/soundmap.json'],
    // pass 113 (lane BOSS): a bullet-heaven pattern's groups (its emitters are a list of their own above these)
    ['trigger', 'When it comes', 'a pattern is never in his cycle: these say when it comes'],
    ['tell', 'The tell (foreshadowing)', 'what warns the hero before the bullets'],
    ['hit', 'A bullet\'s hit', 'what one bullet does to the hero'],
    ['guard', 'Guard', 'how hard he is to hurt while it runs'],
    ['spent', 'Spent (the payoff)', 'after the bullets: he stands dazed and takes extra'],
    ['shell', 'His shell (the look)', 'what shows he is guarded'],
    // pass 115 (lane BOSS)
    ['barrier', 'The barrier', 'a 3D wall round him and the hero while it runs: the hero cannot run out of the bullets\' reach'],
  ];
  const FIELDS = [
    { g: 'projectile', k: 'look', label: 'Shot look', type: 'select', opts: LOOK_OPTS, kinds: SHOTSP, help: 'the shot\'s shape: spike = a barb flying point first (the centipede\'s), spit = the Spit Cactus\'s ball, pellet = a small lead ball, shard = a flat golden sliver, rock = a stone, fire = a glowing ball' },
    { g: 'projectile', k: 'tint', label: 'Colour', type: 'color', kinds: ALLP, help: 'its colour: the body a darker shade, the colour itself glowing (a ring and a slam flash in it)' },
    { g: 'projectile', k: 'size', label: 'Size ×', type: 'number', min: 0.1, step: 0.1, kinds: SHOTSP, help: 'times the look\'s size (the barb is 0.8 m long at 1)' },
    { g: 'projectile', k: 'glow', label: 'Glow', type: 'number', min: 0, max: 4, step: 0.1, kinds: SHOTSP, help: 'how bright its colour glows: 0 none, 1 like the game\'s shots, 2 hot' },
    { g: 'projectile', k: 'flight', label: 'Flight (s)', type: 'number', min: 0.1, step: 0.05, kinds: ['rain'], help: 'seconds each shot is in the air, from the boss\'s back to its spot (on the creatures\' clock: ×1/pace on the map)' },
    { g: 'projectile', k: 'arc', label: 'Arc (m)', type: 'number', min: 0, step: 0.5, kinds: ['rain'], help: 'how high its arc rises over the straight line' },
    { g: 'projectile', k: 'trail', label: 'Trail', type: 'bool', kinds: ['rain', 'pattern'], help: 'three smaller copies follow each shot' },
    { g: 'projectile', k: 'speed', label: 'Speed (m/s)', type: 'number', min: 0.5, step: 0.5, kinds: ['volley', 'ring'], help: 'volley: how fast a shot flies; ring: how fast the ring races out on average (fast at first, slowing)' },
    { g: 'projectile', k: 'range', label: 'Range (m)', type: 'number', min: 1, step: 1, kinds: ['volley', 'pattern'], help: 'how far a shot flies (the warning lines are this long)' },
    { g: 'projectile', k: 'hit_radius', label: 'Hit radius (m)', type: 'number', min: 0.05, step: 0.05, kinds: ['volley', 'pattern'], help: 'how close a shot must pass the hero\'s middle to hit him (+0.3 m for his body)' },
    { g: 'pattern', k: 'shape', label: 'Layout', type: 'select', opts: SHAPE_OPTS, kinds: ['rain'], help: 'how the landing spots are laid out: rings round the centre, a hex grid, a sunflower spiral, or random spots kept a spacing apart' },
    { g: 'pattern', k: 'center', label: 'Centre', type: 'select', opts: CENTER_OPTS, kinds: ['rain', 'slam'], help: 'round the boss, or round the spot the hero stood on when the wind-up began' },
    { g: 'pattern', k: 'radius_min', label: 'Inner radius (m)', type: 'number', min: 0, step: 0.2, kinds: ['rain'], help: 'no spot nearer the centre than this (keep it past the boss\'s body: the Gila\'s is 2.4 m)' },
    { g: 'pattern', k: 'radius_max', label: 'Outer radius (m)', type: 'number', min: 0.5, step: 0.5, kinds: ['rain', 'ring', 'slam'], help: 'rain: the outer edge of the spots; ring: how far the ring races; slam: the blast\'s radius' },
    { g: 'pattern', k: 'spacing', label: 'Spacing (m)', type: 'number', min: 0.3, step: 0.1, kinds: ['rain'], help: 'the distance between neighbouring spots\' centres (never below 2 × the landing radius + the gap: it is raised to that)' },
    { g: 'pattern', k: 'gap', label: 'Gap (m)', type: 'number', min: 0, step: 0.1, kinds: ['rain'], help: 'THE GAP RULE: the least free sand between two neighbouring circles, edge to edge. A spot that would come closer is dropped. The hero is 0.9 m wide: 1.0 leaves him room' },
    { g: 'pattern', k: 'jitter', label: 'Jitter', type: 'number', min: 0, max: 1, step: 0.05, kinds: ['rain'], help: 'how far each spot moves at random, a share of half the spacing (it never closes a gap below the rule)' },
    { g: 'pattern', k: 'count', label: 'Count', type: 'int', min: 0, step: 1, kinds: ['rain', 'volley', 'ring'], help: 'rain: at most this many spots (0 = every spot that fits); volley: shots in each wave; ring: how many rings' },
    { g: 'pattern', k: 'turn', label: 'Turn at random', type: 'bool', kinds: ['rain'], help: 'the whole layout turned at random each time, so it never falls on the same places' },
    { g: 'pattern', k: 'order', label: 'Landing order', type: 'select', opts: ORDER_OPTS, kinds: ['rain'], help: 'which spots land first: out = the nearest first (a ripple outwards), in = the farthest first, random, sweep = round like a clock hand' },
    { g: 'pattern', k: 'spread_deg', label: 'Spread (°)', type: 'number', min: 0, max: 360, step: 5, kinds: ['volley'], help: 'the fan the shots spread over; 360 = all round' },
    { g: 'pattern', k: 'aim', label: 'Aim', type: 'select', opts: AIM_OPTS, kinds: ['volley'], help: 'the middle of the fan: at the hero (where he stood as the wind-up began), a random way, or always the same way' },
    { g: 'pattern', k: 'waves', label: 'Waves', type: 'int', min: 1, step: 1, kinds: ['volley'], help: 'how many volleys' },
    { g: 'pattern', k: 'wave_gap', label: 'Between waves (s)', type: 'number', min: 0, step: 0.05, kinds: ['volley', 'ring'], help: 'seconds between two volleys, or two rings' },
    { g: 'pattern', k: 'width', label: 'Ring width (m)', type: 'number', min: 0.1, step: 0.1, kinds: ['ring'], help: 'how thick each ring is' },
    { g: 'landing', k: 'radius', label: 'Landing radius (m)', type: 'number', min: 0.1, step: 0.05, kinds: ['rain'], help: 'the circle each shot lands in: the hero is hit only inside it (his middle within the radius + 0.2 m)' },
    { g: 'landing', k: 'mode', label: 'Landing', type: 'select', opts: MODE_OPTS, kinds: ['rain'], help: 'stagger: the shots leave the boss\'s back one after another and land over the Stagger; volley (pass 73, the Gila\'s cactus rain): the boss crouches, rears up and spews them all from its mouth, each leaving within the Spew\'s Burst and landing within the Stagger of the others, the nearest first' },
    { g: 'telegraph', k: 'kind', label: 'Warning', type: 'select', opts: TEL_OPTS, kinds: ALL, help: 'rain: a red circle on each landing spot (and the edge of the area through the wind-up); volley: a line down each shot\'s way; ring and slam: a circle round its reach; none = no warning' },
    { g: 'telegraph', k: 'color', label: 'Warning colour', type: 'color', kinds: ALL, help: 'the warning\'s colour' },
    { g: 'telegraph', k: 'seconds', label: 'Circle shows (s)', type: 'number', min: 0, step: 0.05, kinds: ['rain'], help: 'how long before a shot lands its circle shows (×1/pace on the map). The hero walks about 3 m a second: 0.9 s is time to step out of a 0.9 m circle. With All circles at once: how long before the spikes leave every circle lights up (the wind-up is made at least this long)' },
    { g: 'telegraph', k: 'all_at_once', label: 'All circles at once', type: 'bool', kinds: ['rain'], help: 'pass 73: every landing circle lights up together, Circle shows seconds before the shots leave (at the wind-up\'s start when the wind-up is no longer), full size from the start, and stays lit until its own shot lands, filling in as it comes down; off: each circle shows Circle shows seconds before its own shot lands' },
    { g: '_top', k: 'damage', label: 'Damage × bite', type: 'number', min: 0, step: 0.05, kinds: ALL, help: 'a hit takes this × the boss\'s bite (its JSON damage: the Gila\'s 24), then the stage, hero-level and map factors, as every scripted attack' },
    { g: '_top', k: 'knockback', label: 'Knockback (m/s)', type: 'number', min: 0, step: 0.5, kinds: ALLP, help: 'the shove where it hits him (an evade or the Invincibility bubble ignores it)' },
    { g: '_top', k: 'lift', label: 'Lift (m/s)', type: 'number', min: 0, step: 0.5, kinds: ALL, help: 'throws him up with the shove (0 = a plain shove)' },
    { g: 'timing', k: 'windup', label: 'Wind-up (s)', type: 'number', min: 0, step: 0.05, kinds: ALL, help: 'seconds the boss winds up first, the warning showing (×1/pace on the map); a boss\'s own entry may set its own' },
    { g: 'timing', k: 'stagger', label: 'Stagger (s)', type: 'number', min: 0, step: 0.05, kinds: ['rain'], help: 'the rain arrives over this long: the first shot lands after its flight, the last this much later. A volley: every shot lands within this long of the others (the farthest a touch later)' },
    { g: 'timing', k: 'cooldown', label: 'Rest after (s)', type: 'number', min: 0, step: 0.1, kinds: ALLP, help: 'the rest after this attack before the next; 0 = the boss\'s own Between attacks' },
    { g: 'timing', k: 'hold', label: 'Stands (s)', type: 'number', min: -1, step: 0.1, kinds: ALL, help: 'seconds the boss stands still after it fires; -1 = while its shots leave (the stagger, the volleys)' },
    { g: 'sounds', k: 'windup', label: 'Wind-up sound', type: 'sound', kinds: ALLP, help: 'played as the wind-up starts (the boss\'s own attack sound plays anyway)' },
    { g: 'sounds', k: 'fire', label: 'Fire sound', type: 'sound', kinds: ALLP, help: 'played as the shots leave (a rain: every 0.35 s while they leave)' },
    { g: 'sounds', k: 'land', label: 'Land sound', type: 'sound', kinds: ['rain'], help: 'played as shots land near the hero (at most one every 0.12 s)' },
    // pass 73 (lane GROUND; Garry: "the boss does his animation of all those projectiles flying out of his mouth but they
    // all land around the same time"): a volley rain's spew (read only with Landing = volley)
    { g: 'spew', k: 'crouch', label: 'Crouch (s)', type: 'number', min: 0, step: 0.05, kinds: ['rain'], help: 'volley: the boss crouches, squashed, through the last this many seconds of its wind-up (×1/pace on the map)' },
    { g: 'spew', k: 'squash', label: 'Crouch squash', type: 'number', min: 0.3, max: 1, step: 0.02, kinds: ['rain'], help: 'volley: how low it crouches: 1 = not at all, 0.82 = 18% shorter and a little wider' },
    { g: 'spew', k: 'stretch', label: 'Spew stretch', type: 'number', min: 1, max: 2, step: 0.05, kinds: ['rain'], help: 'volley: how tall it rears up as it spews (1.25 = a quarter taller and narrower), easing back to 1 by itself' },
    { g: 'spew', k: 'mouth', label: 'Mouth height', type: 'number', min: 0, max: 1.2, step: 0.02, kinds: ['rain'], help: 'volley: where the shots leave from, this share of the boss\'s height up its painting (the Gila\'s mouth 0.62), a little in front of it' },
    { g: 'spew', k: 'burst', label: 'Burst (s)', type: 'number', min: 0, step: 0.02, kinds: ['rain'], help: 'volley: every shot leaves the mouth within this many seconds of the spew (keep it under the Stagger)' },
    // pass 113 (lane BOSS; Garry: "For each of those attacks I expect to see them in the Boss Attacks section of the
    // LevelEditor"): a bullet-heaven pattern's keys (its emitters have their own rows, EMITTER_FIELDS)
    { g: 'projectile', k: 'wobble', label: 'Wobble', type: 'number', min: 0, max: 2, step: 0.1, kinds: PAT, help: 'pattern: how much a venom blob wobbles as it flies (0 a little, 1 a lot); only the venom blob reads it' },
    { g: 'timing', k: 'duration', label: 'Bullets for (s)', type: 'number', min: 0.5, step: 0.5, kinds: PAT, help: 'pattern: seconds of bullets after the tell (Garry: "some 5+ seconds during which player is supposed to try and survive"); on the creatures\' clock (×1/pace on the map)' },
    { g: 'timing', k: 'clear', label: 'Burn out (s)', type: 'number', min: 0, step: 0.1, kinds: PAT, help: 'pattern: the bullets still flying when the bullets end shrink away over this many seconds and hurt nobody (0 = gone at once), so the payoff is a clear screen' },
    { g: 'hit', k: 'hit_frac', label: 'A bullet takes (share of max HP)', type: 'number', min: 0, max: 1, step: 0.01, kinds: PAT, help: 'pattern: each bullet that touches the hero takes this share of his max HP (0.12 = 12%: about 8 hits from full without armour), then it is gone; an evade, the Shield power-up and the blink after a hit stop it as they stop any shot. The danger is the number of bullets, never one hit' },
    // pass 114 (lane EDITOR; Garry: "make it a range between 10 and 15 for example"): Not before, At the latest and Then
    // every each take one number (fixed) or a range (min and max): the game rolls a number in the range from the fight's
    // own dice (the same in a replay)
    { g: 'trigger', k: 'first_after', label: 'Not before (s)', type: 'range', min: 0, step: 1, kinds: PAT, help: 'pattern: never in the first this many seconds of the fight (Garry: "Make it so they don\'t trigger immediately"). Fixed: one number. Range: the game picks a number between min and max once per fight (10 to 15 = somewhere from 10 s to 15 s, a new pick every fight)' },
    { g: 'trigger', k: 'first_at_hp', label: 'First at HP below', type: 'number', min: 0, max: 1, step: 0.05, kinds: PAT, help: 'pattern: the first one comes when the boss falls to this share of his max HP (0.6 = 60%)...' },
    { g: 'trigger', k: 'first_by', label: '...or at the latest (s)', type: 'range', min: 0, step: 1, kinds: PAT, help: 'pattern: ...or at the latest this many seconds into the fight, so a slow fight still sees one. Fixed: one number. Range: picked between min and max once per fight' },
    { g: 'trigger', k: 'cooldown', label: 'Then every (s)', type: 'range', min: 0, step: 1, kinds: PAT, help: 'pattern: the next one comes this many seconds after the last one is COMPLETELY over: the countdown starts only when his tell, all the bullets and his dazed (spent) seconds are done, so a 20 s attack with "every 45" means 45 s of fighting between two of them. Fixed: one number. Range: a new pick between min and max after every attack. Garry: "rare, something like once every 45s". It still waits for him to finish whatever attack he is in' },
    { g: 'tell', k: 'seconds', label: 'Tell (s)', type: 'number', min: 0, step: 0.1, kinds: PAT, help: 'pattern: how long the warning lasts before the first bullet (Garry: "Big foreshadowing"): the banner, the dark ground, the wind-up sound, the music ducking, his wind-up and his shell forming. He is guarded from its start' },
    { g: 'tell', k: 'banner', label: 'Banner words', type: 'text', kinds: PAT, placeholder: 'the attack\'s name', help: 'pattern: the words across the screen as the tell starts (empty = the attack\'s name, in capitals)' },
    { g: 'tell', k: 'banner_color', label: 'Banner colour', type: 'color', kinds: PAT, help: 'pattern: the banner\'s colour, and the ring pulsing at the edge of the dark ground' },
    { g: 'tell', k: 'ring_radius', label: 'Dark ground (m)', type: 'number', min: 0, step: 0.5, kinds: PAT, help: 'pattern: the sand darkens in a circle this wide round him through the tell and the bullets (0 = none)' },
    { g: 'tell', k: 'ring_color', label: 'Dark ground colour', type: 'color', kinds: PAT, help: 'pattern: the dark ground\'s colour' },
    { g: 'tell', k: 'ring_alpha', label: 'Dark ground strength', type: 'number', min: 0, max: 1, step: 0.05, kinds: PAT, help: 'pattern: how dark the ground gets (0 not at all, 1 fully the colour)' },
    { g: 'tell', k: 'duck_db', label: 'Music down (dB)', type: 'number', min: -40, max: 0, step: 1, kinds: PAT, help: 'pattern: the music drops this much through the tell and the bullets (-14 = to about a fifth), then comes back as he is spent; 0 = no change' },
    { g: 'tell', k: 'look', label: 'His wind-up', type: 'select', opts: TLOOK_OPTS, kinds: PAT, help: 'pattern: how the boss himself winds up: spin (the King spins faster and faster), rear (the Gila rears up, her throat swelling and glowing in the bullets\' colour), drive (the Brander raises his iron and drives it into the ground with a blast); each has its spent look too (stars, slumping, a smoking iron)' },
    { g: 'guard', k: 'share', label: 'Guard (share blocked)', type: 'number', min: 0, max: 0.95, step: 0.05, kinds: PAT, help: 'pattern: from the tell\'s start to the bullets\' end he takes this much less from every hit (0.8 = 80% less). His bar turns grey with GUARDED in it and hits on him spark and show small grey numbers' },
    { g: 'guard', k: 'color', label: 'Blocked spark colour', type: 'color', kinds: PAT, help: 'pattern: the colour of the sparks a guarded hit throws off him' },
    { g: 'spent', k: 'seconds', label: 'Spent for (s)', type: 'number', min: 0, step: 0.5, kinds: PAT, help: 'pattern: after the bullets he stands dazed this long (his bar reads DAZED): the payoff for surviving it' },
    { g: 'spent', k: 'damage_taken', label: 'Spent damage ×', type: 'number', min: 0, step: 0.05, kinds: PAT, help: 'pattern: while spent every hit on him takes this many times as much (1.5 = 50% more)' },
    { g: 'spent', k: 'still', label: 'Stands still while spent', type: 'bool', kinds: PAT, help: 'pattern: yes = he stands still while spent (no = he walks again, still taking the extra)' },
    { g: 'shell', k: 'look', label: 'Shell', type: 'select', opts: SHELL_OPTS, kinds: PAT, help: 'pattern: what shows he is guarded, besides his own glowing rim: a sand tornado round him, a glow behind him like armour, or a pillar of fire; it forms through the tell and collapses or gutters out as he is spent' },
    { g: 'shell', k: 'color', label: 'Shell colour', type: 'color', kinds: PAT, help: 'pattern: the shell\'s colour, and his rim while guarded' },
    { g: 'shell', k: 'height', label: 'Shell height (m)', type: 'number', min: 1, step: 0.5, kinds: PAT, help: 'pattern: how tall the tornado or the pillar is (the hero is about 1.9 m)' },
    { g: 'shell', k: 'radius', label: 'Shell radius (m)', type: 'number', min: 0.5, step: 0.1, kinds: PAT, help: 'pattern: how wide the tornado or the pillar is round him' },
    { g: 'shell', k: 'opacity', label: 'Shell opacity', type: 'number', min: 0.5, max: 1, step: 0.05, kinds: PAT, help: 'pattern, the tornado (pass 113): how solid its dust is, 0.5 to 1 (lower lets the boss show through it; 0.62 for the King)' },
    { g: 'shell', k: 'sigil_radius', label: 'Brand sigil (m)', type: 'number', min: 0, step: 0.5, kinds: PAT, help: 'pattern: a glowing brand sigil this wide (radius) burns into the sand under him through the tell and brightens through the bullets (0 = none; the Brander\'s is 6)' },
    { g: 'shell', k: 'sigil_color', label: 'Sigil colour', type: 'color', kinds: PAT, help: 'pattern: the sigil\'s colour (it glows, so a dark sand never swallows it)' },
    // pass 115 (lane BOSS; Garry: "add a barrier that appears around the boss and the hero. This makes it so this Boss
    // attack should only happen if Player is within the range of as far as the projectiles reach ... Avoid making it so
    // the Player gets stuck in this barrier when it goes up. Barrier falls apart and disappears when the attack is done")
    { g: 'barrier', k: 'look', label: 'Barrier', type: 'select', opts: BLOOK_OPTS, kinds: PAT, help: 'pattern: a 3D wall that comes up out of the sand round the boss and the hero as the tell begins (nearest the hero first), holds him inside while the bullets fly, then falls apart and sinks. With a barrier THE REACH RULE plays: the attack only begins with the hero within its reach of the boss (the preview\'s dashed circle); when it is due and he is further off, it waits and begins the moment he comes in (its clock is not reset). So the wall never comes up on him: he stands at least 0.5 m inside it. none = no wall and no reach rule' },
    { g: 'barrier', k: 'radius_mode', label: 'Where it stands', type: 'select', opts: BMODE_OPTS, kinds: PAT, help: 'pattern: range = the Inset inside the bullets\' Range (Projectile), so every spot inside it can be hit; fixed = at the Radius below. The phone shows about 12 m round the hero' },
    { g: 'barrier', k: 'radius', label: 'Radius (m, fixed)', type: 'number', min: 3, step: 0.5, kinds: PAT, help: 'pattern, Where it stands = fixed: the wall\'s middle this far from where the boss stands (the hero is held 0.85 m inside it at the default thickness)' },
    { g: 'barrier', k: 'inset', label: 'Inset (m, range)', type: 'number', min: 0, step: 0.5, kinds: PAT, help: 'pattern, Where it stands = range: the wall stands this far inside the bullets\' Range' },
    { g: 'barrier', k: 'height', label: 'Height (m)', type: 'number', min: 0.5, max: 4, step: 0.1, kinds: PAT, help: 'pattern: how tall the wall is (the hero is about 1.9 m); its pieces grow with it' },
    { g: 'barrier', k: 'thickness', label: 'Thickness (m)', type: 'number', min: 0.2, max: 3, step: 0.1, kinds: PAT, help: 'pattern: how thick it is: the hero stops at its inner face, the bullets vanish there, the creatures outside stop at its outer face' },
    { g: 'barrier', k: 'rise_s', label: 'Rise (s)', type: 'number', min: 0.1, step: 0.1, kinds: PAT, help: 'pattern: seconds each stretch takes to come up out of the sand (a little overshoot and a wobble)' },
    { g: 'barrier', k: 'spread_s', label: 'Spread (s)', type: 'number', min: 0, step: 0.1, kinds: PAT, help: 'pattern: the rise runs round the ring from the hero\'s side to the far side over this long (0 = all at once); the pieces also fall apart at random over this long' },
    { g: 'barrier', k: 'fall_s', label: 'Fall (s)', type: 'number', min: 0.1, step: 0.1, kinds: PAT, help: 'pattern: seconds each piece takes to topple (or roll away) and sink as the barrier falls apart' },
    { g: 'barrier', k: 'hold', label: 'Stands', type: 'select', opts: BHOLD_OPTS, kinds: PAT, help: 'pattern: bullets = it falls apart as the bullets end, as he is dazed (the hero is free to go); spent = it stands through his dazed seconds too' },
    { g: 'barrier', k: 'color', label: 'Barrier colour x', type: 'color', kinds: PAT, help: 'pattern: times the wall\'s own paint (#FFFFFF = as made; a darker colour darkens it)' },
    { g: 'barrier', k: 'glow_color', label: 'Glow colour', type: 'color', kinds: PAT, help: 'pattern: the colour of its glowing bits (the King\'s embers, the Gila\'s venom blooms, the Brander\'s white-hot iron)' },
    { g: 'barrier', k: 'hero_block', label: 'Holds the hero', type: 'bool', kinds: PAT, help: 'pattern: the hero cannot cross it while it stands (walking, shoved, thrown, leaping: he slides along it; a Teleport lands inside it)' },
    { g: 'barrier', k: 'creatures', label: 'Creatures', type: 'select', opts: BCRE_OPTS, kinds: PAT, help: 'pattern: block = every creature stays on the side it was on as it rose (the ones outside pile up against it); pass = they walk through it' },
    { g: 'barrier', k: 'bullets', label: 'Bullets at it', type: 'select', opts: BBUL_OPTS, kinds: PAT, help: 'pattern: stop = a bullet that reaches its inner face stops there and shrinks away with a spark; pass = it flies on to its Range' },
  ];

  // ------------------------------------------------------------------ data

  async function getJSON(url) { const r = await fetch(url, { cache: 'no-store' }); if (!r.ok) throw new Error(`${url}: HTTP ${r.status}`); return r.json(); }
  async function postJSON(url, body) {
    const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}) });
    let data; try { data = await r.json(); } catch (_) { data = { ok: false, error: `HTTP ${r.status}` }; }
    return { status: r.status, data };
  }
  function load(force) {
    if (S.loading || (S.data && !force)) return;
    S.loading = true;
    getJSON('/api/boss_attacks').then((d) => { S.data = d; S.failed = null; S.loading = false; redraw(); })
      .catch((e) => { S.failed = e.message; S.loading = false; redraw(); });
  }
  const attacks = () => (S.data && S.data.attacks) || [];
  const recOf = (id) => attacks().find((a) => a.id === id) || null;
  const scripted = () => (S.data && S.data.creatures) || [];
  const dirty = () => S.draft != null && JSON.stringify(S.draft) !== JSON.stringify(S.base);
  const redraw = () => { if (typeof App !== 'undefined' && App.S.tab === 'bossattacks') App.render('tab'); };

  /** The custom attacks as options for the Enemies tab's attack select (★ marks them). */
  function options() {
    if (!S.data) load();
    return attacks().map((a) => o(a.id, `★ ${a.name || a.id} (${a.kind})`, `a custom attack: ${a.doc || a.kind} (Boss attacks tab)`));
  }
  function get(id) { const a = recOf(id); return a ? { id: a.id, name: a.name, kind: a.kind } : null; }

  function openAttack(id) {
    if (dirty() && S.open !== id && !confirm(`Leave ${S.open} with unsaved changes?`)) return;
    const a = recOf(id);
    S.open = id;
    S.draft = a && a.json ? JSON.parse(JSON.stringify(a.json)) : null;
    S.base = S.draft ? JSON.parse(JSON.stringify(S.draft)) : null;
    S.mtime = a ? a.mtime : null;
    S.history = []; S.future = []; S.t = null; S.playing = false; S.deleting = false; S.msg = null;
    redraw();
  }
  /** From the Enemies tab's attack card: switch here with the attack open. */
  function open(id) {
    if (typeof App !== 'undefined') App.switchTab('bossattacks');
    if (S.data) openAttack(id); else { S.open = id; load(); }
  }

  function edit(fn) {
    if (!S.draft) return;
    S.history.push(JSON.stringify(S.draft));
    if (S.history.length > 200) S.history.shift();
    S.future = [];
    fn(S.draft);
    redraw();
  }
  function undo() { if (!S.history.length) return; S.future.push(JSON.stringify(S.draft)); S.draft = JSON.parse(S.history.pop()); redraw(); }
  function redo() { if (!S.future.length) return; S.history.push(JSON.stringify(S.draft)); S.draft = JSON.parse(S.future.pop()); redraw(); }
  function setVal(g, k, v) {
    edit((d) => {
      if (g === '_top') { if (v == null || v === '') delete d[k]; else d[k] = v; return; }
      if (d[g] == null || typeof d[g] !== 'object') d[g] = {};
      if (v == null || v === '') delete d[g][k]; else d[g][k] = v;
    });
  }

  async function save() {
    if (!S.draft || S.busy) return;
    const iss = M.issues(S.draft);
    if (iss.errors.length) { App.status(`Cannot save ${S.open}: ${iss.errors.join(' · ')}`, 'bad'); return; }
    if (!dirty()) { App.status('Nothing to save'); return; }
    S.busy = true; redraw();
    App.status(`Saving ${S.open} and importing…`, 'busy');
    const r = await postJSON(`/api/boss_attacks/${S.open}/save`, { json: S.draft, base_mtime: S.mtime });
    S.busy = false;
    if (r.status === 409) {
      App.status(`${S.open} changed on disk since it was opened: Reload to take the file, or Save again to keep yours`, 'bad');
      S.mtime = r.data.mtime;
      S.msg = { kind: 'conflict', text: 'The file changed on disk (Garry, or another editor). Save again keeps yours over it; Reload takes the file.' };
      redraw(); return;
    }
    if (!r.data.ok) { App.status(`Save failed: ${r.data.error}`, 'bad'); redraw(); return; }
    S.base = JSON.parse(JSON.stringify(S.draft));
    S.mtime = r.data.mtime;
    S.msg = null;
    // pass 114 (lane EDITOR): the import waits (queued) while Godot is busy: App.importOutcome says who holds it
    App.saveStatus(r.data, `Saved ${S.open} at ${new Date().toLocaleTimeString()}`);
    const keep = S.open;
    S.data = null; load(true);
    S.open = keep;
  }
  function revert() { if (!S.draft || !dirty()) return; S.history.push(JSON.stringify(S.draft)); S.draft = JSON.parse(JSON.stringify(S.base)); redraw(); }
  async function reload() { const keep = S.open; S.data = null; S.loading = false; await getJSON('/api/boss_attacks').then((d) => { S.data = d; }); S.open = null; S.draft = null; S.base = null; openAttack(keep); }

  async function create(id, name, from) {
    if (dirty() && !confirm(`Leave ${S.open} with unsaved changes?`)) return;
    const body = { id, name };
    if (from.startsWith('kind:')) body.kind = from.slice(5); else body.template = from;
    const r = await postJSON('/api/boss_attacks/new', body);
    if (!r.data.ok) { S.creating.error = r.data.error; redraw(); return; }
    S.creating = null;
    App.saveStatus(r.data, `Made ${id}`);
    S.data = await getJSON('/api/boss_attacks');
    S.open = null; S.draft = null; S.base = null;
    openAttack(id);
  }
  async function assign(cid, on) {
    if (dirty()) { App.status('Save the attack first: the boss plays the saved file', 'bad'); return; }
    S.busy = true; redraw();
    const r = await postJSON(`/api/boss_attacks/${S.open}/assign`, { creature: cid, on });
    S.busy = false;
    if (!r.data.ok) { App.status(`Could not ${on ? 'add it to' : 'take it out of'} ${cid}: ${r.data.error}`, 'bad'); redraw(); return; }
    App.saveStatus(r.data, `${on ? 'Added to' : 'Taken out of'} ${cid}'s script (${r.data.attacks.join(', ')})`);
    S.data = await getJSON('/api/boss_attacks');
    if (typeof App !== 'undefined' && App.refreshCreatures) App.refreshCreatures();
    redraw();
  }
  async function del(cascade) {
    const r = await postJSON(`/api/boss_attacks/${S.open}/delete`, { cascade });
    if (!r.data.ok) { App.status(`Could not delete ${S.open}: ${r.data.error}`, 'bad'); return; }
    App.status(`Deleted ${S.open} (moved to ${r.data.moved_to})${r.data.left && r.data.left.length ? ' · taken out of ' + r.data.left.join(', ') : ''}`, 'good');
    S.open = null; S.draft = null; S.base = null; S.deleting = false;
    S.data = await getJSON('/api/boss_attacks');
    if (typeof App !== 'undefined' && App.refreshCreatures) App.refreshCreatures();
    redraw();
  }

  // ------------------------------------------------------------------ the page

  function render(panel) {
    const scroll = panel.scrollTop;
    const active = panel.contains(document.activeElement) ? document.activeElement.dataset.path : null;
    clear(panel);
    load();
    const page = el('div', { class: 'batk' });
    page.appendChild(el('p', { class: 'lead', html: 'A boss\'s script is a list of attacks (Enemies tab → the boss → <i>Attack script</i>). Besides the 14 built-in ones, <b>custom attacks</b> made here need no code: a <b>rain</b> of shots landing on a pattern, a <b>volley</b>, racing <b>rings</b>, a <b>slam</b>, or a built-in under its own name with its own numbers (<b>script</b>). Make one, name it, tune it with the preview, tick the bosses that use it, Save (Ctrl+S): the file is written and imported, the next run plays it.' }));
    if (S.failed) { page.appendChild(el('p', { class: 'ferr bad', text: `Could not read /api/boss_attacks: ${S.failed} (restart the editor: the route is new in pass 72)` })); panel.appendChild(page); return; }
    if (!S.data) { page.appendChild(el('p', { class: 'muted', text: 'Loading the attacks…' })); panel.appendChild(page); return; }
    if (S.open && !S.draft && recOf(S.open)) { const id = S.open; S.open = null; openAttack(id); return; }
    const grid = el('div', { class: 'batk-grid' });
    grid.appendChild(listPane());
    grid.appendChild(S.draft ? editorPane() : el('div', { class: 'batk-empty muted' }, el('p', { text: 'Pick an attack on the left, or make a new one.' })));
    page.appendChild(grid);
    panel.appendChild(page);
    panel.scrollTop = scroll;
    if (active) { const again = panel.querySelector(`[data-path="${CSS.escape(active)}"]`); if (again) again.focus({ preventScroll: true }); }
  }

  function listPane() {
    const pane = el('aside', { class: 'batk-list' });
    pane.appendChild(el('div', { class: 'batk-list-head' }, el('h2', { text: 'Custom attacks' }), el('button', { class: 'btn small primary', type: 'button', text: '+ New attack', onclick: () => { S.creating = { id: '', name: '', from: 'kind:rain', error: '' }; redraw(); } })));
    if (S.creating) pane.appendChild(createForm());
    for (const a of attacks()) {
      const users = (a.used_by || []).map((cid) => (scripted().find((c) => c.id === cid) || { name: cid }).name);
      const row = el('button', { class: 'batk-item' + (a.id === S.open ? ' on' : ''), type: 'button', onclick: () => openAttack(a.id) },
        el('span', { class: 'batk-swatch', style: `background:${(a.json && a.json.projectile && a.json.projectile.tint) || M.DEFAULTS.projectile.tint}` }),
        el('span', { class: 'batk-item-main' },
          el('span', { class: 'batk-item-name', text: a.name || a.id }),
          el('span', { class: 'batk-item-sub', text: `${a.id} · ${a.kind}${users.length ? ' · ' + users.join(', ') : ' · in no script'}` })),
        a.id === S.open && dirty() ? el('span', { class: 'dirty-dot', text: '●', title: 'unsaved changes' }) : null);
      pane.appendChild(row);
    }
    if (!attacks().length) pane.appendChild(el('p', { class: 'muted small', text: 'None yet.' }));
    const bi = el('details', { class: 'batk-builtins' }, el('summary', { text: `The ${(S.data.builtins || []).length} built-in attacks` }));
    const AF = typeof AFIELDS !== 'undefined' ? AFIELDS : null;
    for (const n of S.data.builtins || []) bi.appendChild(el('div', { class: 'small' }, el('code', { text: n }), el('span', { class: 'muted', text: ' ' + (AF && AF.ATTACKS[n] ? AF.ATTACKS[n].help : '') })));
    bi.appendChild(el('p', { class: 'muted small', text: 'A built-in is put in a script on the Enemies tab; a "script" attack here is a built-in under its own name with its own numbers.' }));
    pane.appendChild(bi);
    return pane;
  }

  function createForm() {
    const c = S.creating;
    const box = el('div', { class: 'batk-new' });
    const idIn = el('input', { type: 'text', class: 'txt', placeholder: 'id: fire_ring', value: c.id, 'data-path': 'new.id' });
    const nameIn = el('input', { type: 'text', class: 'txt', placeholder: 'Name: Ring of Fire', value: c.name, 'data-path': 'new.name' });
    idIn.addEventListener('input', () => { c.id = idIn.value.trim().toLowerCase(); });
    nameIn.addEventListener('input', () => { c.name = nameIn.value; if (!c.idTouched) { c.id = nameIn.value.trim().toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, ''); idIn.value = c.id; } });
    idIn.addEventListener('change', () => { c.idTouched = true; });
    const opts = [{ group: 'A blank one', options: KIND_OPTS.map((k) => o('kind:' + k.v, k.label, k.help)) }];
    if (attacks().length) opts.push({ group: 'A copy of', options: attacks().map((a) => o(a.id, `${a.name} (${a.id})`)) });
    const from = Forms.select(opts, c.from, (v) => { c.from = v || 'kind:rain'; }, { path: 'new.from' });
    box.appendChild(el('div', { class: 'frow' }, el('label', { class: 'flabel', text: 'Name' }), el('div', { class: 'fctl' }, nameIn)));
    box.appendChild(el('div', { class: 'frow' }, el('label', { class: 'flabel', text: 'Id', title: 'lower-case letters, digits and _: the file\'s and the scripts\' name for it' }), el('div', { class: 'fctl' }, idIn)));
    box.appendChild(el('div', { class: 'frow' }, el('label', { class: 'flabel', text: 'Start from' }), el('div', { class: 'fctl' }, from)));
    if (c.error) box.appendChild(el('div', { class: 'ferr bad', text: c.error }));
    box.appendChild(el('div', { class: 'alt-actions' },
      el('button', { class: 'btn small primary', type: 'button', text: 'Make it', onclick: () => {
        const id = (c.id || '').trim();
        if (!/^[a-z][a-z0-9_]*$/.test(id)) { c.error = 'the id is lower-case letters, digits and _, starting with a letter'; redraw(); return; }
        if (M.SCRIPTS.includes(id)) { c.error = `"${id}" is a built-in attack's name`; redraw(); return; }
        create(id, c.name || id, c.from);
      } }),
      el('button', { class: 'btn small ghost', type: 'button', text: 'Cancel', onclick: () => { S.creating = null; redraw(); } })));
    return box;
  }

  function editorPane() {
    const d = S.draft;
    const kind = M.KINDS.includes(d.kind) ? d.kind : 'rain';
    const iss = M.issues(d);
    const pane = el('section', { class: 'batk-edit' });
    // the head: name, id, kind, the buttons
    const nameIn = Forms.textInput({ key: 'name' }, d.name, (v) => edit((x) => { x.name = v || ''; }), { path: 'name', placeholder: 'a name' });
    nameIn.classList.add('batk-name');
    pane.appendChild(el('div', { class: 'batk-head' },
      nameIn,
      el('code', { class: 'batk-id', text: S.open }),
      Forms.select(KIND_OPTS, kind, (v) => edit((x) => changeKind(x, v || 'rain')), { path: 'kind' }),
      el('span', { class: 'spacer' }),
      el('button', { class: 'btn small', type: 'button', text: 'Undo', disabled: !S.history.length, onclick: undo }),
      el('button', { class: 'btn small', type: 'button', text: 'Revert', disabled: !dirty(), onclick: revert }),
      el('button', { class: 'btn small primary' + (iss.errors.length && dirty() ? ' blocked' : ''), type: 'button', text: S.busy ? 'Saving…' : 'Save attack', disabled: !dirty() || S.busy, title: iss.errors.length ? iss.errors.join(' · ') : 'write the JSON and import it (Ctrl+S)', onclick: save }),
      // pass 114 (lane EDITOR): the whole attack as JSON, editable (every key, also ones without a box)
      el('button', { class: 'btn small', type: 'button', text: 'JSON…', title: 'show / edit the JSON: Apply takes it as typed (one undoable edit), Save attack writes it', onclick: jsonWindow }),
      el('button', { class: 'btn small danger', type: 'button', text: 'Delete…', onclick: () => { S.deleting = !S.deleting; redraw(); } })));
    if (S.msg) pane.appendChild(el('div', { class: 'ferr warn' }, el('span', { text: S.msg.text + ' ' }), el('button', { class: 'btn small', type: 'button', text: 'Reload', onclick: reload })));
    if (S.deleting) {
      const rec = recOf(S.open) || {};
      const users = rec.used_by || [];
      pane.appendChild(el('div', { class: 'batk-confirm' },
        el('span', { text: users.length ? `Delete ${S.open}? It is in the script of ${users.join(', ')}: deleting takes it out of those first. The folder goes to the editor's backups.` : `Delete ${S.open}? The folder goes to the editor's backups.` }),
        el('button', { class: 'btn small danger', type: 'button', text: 'Delete', onclick: () => del(true) }),
        el('button', { class: 'btn small ghost', type: 'button', text: 'Cancel', onclick: () => { S.deleting = false; redraw(); } })));
    }
    const doc = Forms.textareaInput({ key: 'doc' }, d.doc, (v) => edit((x) => { x.doc = v || ''; }), { path: 'doc', placeholder: 'what it is, in a line or two (the list and the Enemies tab show it)' });
    pane.appendChild(el('div', { class: 'frow' }, el('label', { class: 'flabel', text: 'What it is' }), el('div', { class: 'fctl' }, doc)));
    // issues
    if (iss.errors.length || iss.warnings.length) {
      const box = el('div', { class: 'batk-issues' });
      for (const e of iss.errors) box.appendChild(el('div', { class: 'ferr bad', text: e }));
      for (const w of iss.warnings) box.appendChild(el('div', { class: 'ferr warn', text: w }));
      pane.appendChild(box);
    }
    pane.appendChild(usedBy());
    if (kind === 'script') { pane.appendChild(scriptPane(d)); return pane; }
    // pass 113 (lane BOSS): a pattern's preview and its emitters (pass 114: the how-to above them)
    if (kind === 'pattern') { pane.appendChild(howtoBox()); pane.appendChild(patternPreview(d)); pane.appendChild(emittersPane(d)); }
    else pane.appendChild(preview(d, kind));
    for (const [g, title, sub] of SECTIONS) {
      const rows = FIELDS.filter((f) => f.g === g && f.kinds.includes(kind));
      if (!rows.length) continue;
      const det = el('details', { class: 'asection batk-sec', open: true }, el('summary', {}, el('span', { class: 'asec-title', text: title }), el('span', { class: 'muted small', text: ' ' + sub })));
      const body = el('div', { class: 'asec-body' });
      for (const f of rows) body.appendChild(fieldRow(d, f));
      det.appendChild(body);
      pane.appendChild(det);
    }
    return pane;
  }

  /** Pass 114 (lane EDITOR): the open attack's JSON in the big editable window (json_edit.js); Apply takes it as typed. */
  function jsonWindow() {
    if (!S.draft || typeof JsonEdit === 'undefined') return;
    JsonEdit.modal({
      title: `${S.open}.json as the editor holds it`,
      note: 'Edit any key (every number, the emitters, a trigger range like "first_after": [10, 15]), then Apply: the attack takes it as typed and is marked unsaved; Save attack writes it. The id stays ' + S.open + '.',
      value: S.draft,
      onApply: (v) => {
        const bad = JsonEdit.mustBeObject(v);
        if (bad) return bad;
        if (String(v.id) !== String(S.open)) return `the id must stay "${S.open}"`;
        edit((d) => { JsonEdit.replaceInto(d, v); });
        App.status(`${S.open}: the JSON as typed is in the editor (unsaved: Save attack writes it)`, 'good');
        return '';
      },
      onSave: save,
    });
  }

  /** A new kind keeps every number the two kinds share; the rows only the new kind reads take its blank's numbers (a
   *  rain's count 0 = "every spot" would be one shot a volley), and the warning becomes the new kind's usual one. */
  function changeKind(x, v) {
    const b = M.blank(v, x.id, x.name);
    const reads = (k) => new Set(FIELDS.filter((f) => f.kinds.includes(k)).map((f) => f.g + '.' + f.k));
    const had = reads(M.KINDS.includes(x.kind) ? x.kind : 'rain'), now = reads(v);
    for (const g of ['projectile', 'pattern', 'landing', 'telegraph', 'timing', 'sounds', 'spew', 'hit', 'trigger', 'guard', 'spent', 'tell', 'shell', 'barrier']) if (b[g] && (x[g] == null || typeof x[g] !== 'object')) x[g] = {};
    for (const f of FIELDS) {
      const key = f.g + '.' + f.k;
      if (!now.has(key) || f.g === '_top' || !b[f.g]) continue;
      const fresh = !had.has(key) || key === 'pattern.count' || key === 'telegraph.kind';
      if (fresh && b[f.g][f.k] !== undefined) x[f.g][f.k] = b[f.g][f.k];
    }
    if (v === 'script' && !x.script) { x.script = b.script; x.params = b.params; }
    if (v === 'rain' && !x.landing) x.landing = b.landing;
    // pass 113 (lane BOSS): a pattern gets its blank's emitters and look when it has none
    if (v === 'pattern') {
      if (!Array.isArray(x.emitters) || !x.emitters.length) x.emitters = JSON.parse(JSON.stringify(b.emitters));
      if (!Object.keys(M.BB_RADIUS).includes(String((x.projectile || {}).look))) x.projectile = Object.assign(x.projectile || {}, { look: b.projectile.look, tint: b.projectile.tint });
      if (x.sounds && !x.sounds.windup) x.sounds.windup = b.sounds.windup;
    }
    x.kind = v;
  }

  function usedBy() {
    const rec = recOf(S.open) || { used_by: [] };
    const box = el('div', { class: 'batk-used' }, el('span', { class: 'flabel', text: 'In the script of', title: 'tick a boss to add {"name": "' + S.open + '"} to its boss.attacks (the end of its cycle); untick to take it out. Written to its JSON and imported at once. The Enemies tab shows the script and orders it' }));
    const bosses = scripted().filter((c) => c.kind === 'boss');
    const others = scripted().filter((c) => c.kind !== 'boss');
    const chip = (c) => {
      const on = (rec.used_by || []).includes(c.id);
      return el('button', { class: 'batk-chip' + (on ? ' on' : ''), type: 'button', disabled: S.busy || (dirty() && !on), title: on ? `${c.name}'s script: ${c.attacks.join(' → ')} (click to take it out)` : `add it to ${c.name}'s script (${c.attacks.join(' → ') || 'empty'})`, text: `${on ? '✓ ' : '+ '}${c.name}`, onclick: () => assign(c.id, !on) });
    };
    const wrap = el('span', { class: 'batk-chips' });
    for (const c of bosses) wrap.appendChild(chip(c));
    if (others.length) {
      const more = el('details', { class: 'batk-more' }, el('summary', { text: `${others.length} more scripted creatures` }));
      for (const c of others) more.appendChild(chip(c));
      wrap.appendChild(more);
    }
    box.appendChild(wrap);
    if (dirty()) box.appendChild(el('span', { class: 'muted small', text: ' (save first: a boss plays the saved file)' }));
    return box;
  }

  function fieldRow(d, f) {
    const cur = f.g === '_top' ? d[f.k] : (d[f.g] && typeof d[f.g] === 'object' ? d[f.g][f.k] : undefined);
    const dflt = f.g === '_top' ? M.TOP_DEFAULTS[f.k] : M.DEFAULTS[f.g][f.k];
    const path = `${f.g}.${f.k}`;
    const set = (v) => setVal(f.g, f.k, v);
    let ctl;
    if (f.type === 'select') ctl = Forms.select(f.opts, cur == null ? '' : cur, set, { path, emptyLabel: `— (${dflt})` });
    else if (f.type === 'bool') ctl = Forms.bool3Input({ key: path }, cur, set, { path, placeholder: dflt ? 'yes' : 'no' });
    else if (f.type === 'color') ctl = colorInput(cur, dflt, set, path);
    // pass 113 (lane BOSS): words (the tell's banner)
    else if (f.type === 'text') ctl = Forms.textInput({ key: path }, cur == null ? '' : cur, (v) => set(v === '' ? null : v), { path, placeholder: f.placeholder || (dflt || '') });
    else if (f.type === 'sound') {
      const sounds = (S.data && S.data.sounds) || [];
      ctl = Forms.select(sounds.map((x) => o(x)), cur == null ? '' : cur, set, { path, emptyLabel: dflt ? `— (${dflt})` : '— none' });
    } else if (f.type === 'range') ctl = rangeInput(f, cur, dflt, set, path);
    else ctl = Forms.numberInput({ key: path, min: f.min, max: f.max, step: f.step, int: f.type === 'int' }, cur, set, { path, placeholder: dflt, cls: 'short' });
    return Forms.row({ key: path, label: f.label, help: f.help }, ctl, {});
  }

  /** Pass 114 (lane EDITOR): a trigger key that is one number or a range [min, max]: "fixed" shows one box (empty = the
   *  game's default, in grey), "range" two (min, max: the game rolls a number between them; BossAttackDef.roll_trigger).
   *  Switching keeps the number: fixed 15 -> range 15 to 15; range 10 to 15 -> fixed 10. A min above its max is shown at
   *  once (and blocks the save, as boss_attacks_io.py refuses it). */
  function rangeInput(f, cur, dflt, set, path) {
    const isRange = Array.isArray(cur);
    const lo = isRange ? cur[0] : cur;
    const hi = isRange ? cur[1] : null;
    const mode = Forms.select([o('fixed', 'fixed'), o('range', 'range (min to max)')], isRange ? 'range' : 'fixed', (v) => {
      const base = M.num(isRange ? cur[0] : (cur == null ? dflt : cur), dflt);
      if (v === 'range' && !isRange) set([base, base]);
      else if (v !== 'range' && isRange) set(base);
    }, { path: path + '.mode' });
    const box = (val, key, ph, onv) => Forms.numberInput({ key: path + key, min: f.min, max: f.max, step: f.step }, val, onv, { path: path + key, placeholder: ph, cls: 'short' });
    const wrap = el('span', { class: 'batk-range' }, mode);
    if (!isRange) {
      wrap.appendChild(box(cur, '', dflt, set));
    } else {
      wrap.appendChild(el('span', { class: 'muted small', text: ' min ' }));
      wrap.appendChild(box(lo, '.min', dflt, (v) => set([v == null ? M.num(dflt, 0) : v, M.num(hi, M.num(dflt, 0))])));
      wrap.appendChild(el('span', { class: 'muted small', text: ' max ' }));
      wrap.appendChild(box(hi, '.max', dflt, (v) => set([M.num(lo, M.num(dflt, 0)), v == null ? M.num(dflt, 0) : v])));
      const pr = M.triggerProblem(f.k, cur);
      wrap.appendChild(el('span', { class: pr ? 'ferr bad small' : 'muted small', text: pr ? ` ${pr}` : (Number(lo) === Number(hi) ? ' (the same: no roll)' : ` rolled ${f.k === 'cooldown' ? 'after every attack' : 'once a fight'}`) }));
    }
    return wrap;
  }

  function colorInput(cur, dflt, set, path) {
    const v = cur || dflt || '#ffffff';
    const pick = el('input', { type: 'color', value: /^#[0-9a-fA-F]{6}$/.test(v) ? v : '#ffffff', 'data-path': path + '.pick' });
    const txt = el('input', { type: 'text', class: 'txt short', value: cur || '', placeholder: dflt || '', 'data-path': path });
    pick.addEventListener('change', () => set(pick.value.toUpperCase()));
    txt.addEventListener('change', () => { const t = txt.value.trim(); set(t === '' ? null : (t.startsWith('#') ? t : '#' + t).toUpperCase()); });
    return el('span', { class: 'batk-color' }, pick, txt);
  }

  function scriptPane(d) {
    const box = el('details', { class: 'asection batk-sec', open: true }, el('summary', {}, el('span', { class: 'asec-title', text: 'The built-in it plays' })));
    const body = el('div', { class: 'asec-body' });
    const AF = typeof AFIELDS !== 'undefined' ? AFIELDS : null;
    body.appendChild(Forms.row({ key: 'script', label: 'Built-in', help: 'the built-in attack this one plays, under this attack\'s name, with the keys below' },
      Forms.select(M.SCRIPTS.map((n) => o(n, AF && AF.ATTACKS[n] ? `${n}: ${AF.ATTACKS[n].label}` : n, AF && AF.ATTACKS[n] ? AF.ATTACKS[n].help : '')), d.script || '', (v) => edit((x) => { x.script = v || 'slam'; }), { path: 'script' })));
    const ta = Forms.textareaInput({ key: 'params' }, JSON.stringify(d.params || {}, null, 1), (v) => {
      let p; try { p = JSON.parse(v || '{}'); } catch (e) { App.status(`params: not JSON (${e.message})`, 'bad'); return; }
      edit((x) => { x.params = p; });
    }, { path: 'params', rows: 6 });
    body.appendChild(Forms.row({ key: 'params', label: 'Its keys (JSON)', help: 'the built-in\'s own keys, as the Enemies tab\'s attack card lists them (windup, telegraph, damage, radius, ...)' }, ta));
    const spec = AF && AF.ATTACKS[d.script];
    if (spec) body.appendChild(el('p', { class: 'muted small', text: `${d.script} reads: windup, telegraph (usual: ${spec.telegraph}), reach, min_range, max_range, ` + spec.keys.map((k) => `${k.key} (${k.def == null ? '—' : k.def})`).join(', ') }));
    box.appendChild(body);
    return box;
  }

  // ------------------------------------------------------------------ pass 113 (lane BOSS): a bullet-heaven pattern
  // Its emitters (a list: add, remove, every key with the game's default in grey) and its preview from above (the tell,
  // the bullets as they fly at any moment, spent; Play; the numbers in plain words).

  const SH_ALL = ['spiral', 'ring', 'fan', 'sweep', 'wall', 'rose'];
  const SH_ARMS = ['spiral', 'fan', 'sweep'];
  /** BossAttackDef.EMITTER_DEFAULTS' keys: the shapes each row shows for (selftest_BOSS113.py: every key a row with help). */
  const EMITTER_FIELDS = [
    { k: 'shape', label: 'Shape', type: 'select', opts: ESHAPE_OPTS, shapes: SH_ALL, help: 'spiral: arms that turn as they fire (bullets fly straight out, so each arm curls); ring: bullets all round with an opening; fan: a spread of bullets round its aim; sweep: a fan swinging left and right like a garden sprinkler; wall: a line of bullets across its aim flying together; rose: a ring that opens into petals as it grows' },
    { k: 'count', label: 'Bullets a volley', type: 'int', min: 1, step: 1, shapes: SH_ALL, help: 'spiral, fan, sweep: bullets on each arm; ring, rose: bullets all round; wall: bullets along the line' },
    { k: 'arms', label: 'Arms', type: 'int', min: 1, step: 1, shapes: SH_ARMS, help: 'spiral, fan, sweep: that many arms evenly round (3 = three arms 120° apart)' },
    { k: 'speed', label: 'Speed (m/s)', type: 'number', min: 0.1, step: 0.1, shapes: SH_ALL, help: 'how fast each bullet flies. The hero walks about 5 m/s: 2.5-4 is slow enough to weave through' },
    { k: 'rate', label: 'Volleys a second', type: 'number', min: 0, step: 0.1, shapes: SH_ALL, help: 'how many volleys it fires a second while it is on (the first as it comes on)' },
    { k: 'spin', label: 'Spin (°/s)', type: 'number', step: 1, shapes: SH_ALL, help: 'degrees a second the whole emitter turns (minus = the other way): the spiral\'s arms, a ring\'s opening, a fan' },
    { k: 'reverse_at', label: 'Spin turns back at', type: 'number', min: -1, max: 1, step: 0.05, shapes: SH_ALL, help: 'the share of the bullets\' time at which the spin turns back the other way (0.5 = halfway: the King\'s arms reverse, so the safe lanes change); -1 = never' },
    { k: 'spread_deg', label: 'Spread (°)', type: 'number', min: 0, max: 360, step: 1, shapes: SH_ARMS, help: 'spiral, fan, sweep: how wide each arm\'s bullets spread (with more than one bullet a volley)' },
    { k: 'sweep_deg', label: 'Sweep wide (°)', type: 'number', min: 0, max: 360, step: 5, shapes: ['sweep'], help: 'sweep: how far it swings in all, from one side to the other' },
    { k: 'sweep_hz', label: 'Sweeps a second', type: 'number', min: 0, step: 0.05, shapes: ['sweep'], help: 'sweep: whole swings (there and back) a second: 0.25 = one sweep across every 2 s' },
    { k: 'gap', label: 'Opening', type: 'number', min: 0, step: 1, shapes: ['ring', 'wall'], help: 'ring: degrees left open, facing its aim; wall: metres of the line left open, at a random place each volley' },
    { k: 'petals', label: 'Petals', type: 'int', min: 1, step: 1, shapes: ['rose'], help: 'rose: how many petals round it (bullets on a petal fly fastest)' },
    { k: 'depth', label: 'Petal depth', type: 'number', min: 0, max: 1, step: 0.05, shapes: ['rose'], help: 'rose: how slow the bullets between the petals are: 0 = a plain ring, 0.75 = at a quarter of the speed, 1 = they stand still' },
    { k: 'bloom_hz', label: 'Petals breathe (/s)', type: 'number', min: 0, step: 0.05, shapes: ['rose'], help: 'rose: the petals open and close this many times a second (the depth swinging between 0 and Petal depth); 0 = held' },
    { k: 'turn_every', label: 'Turn every (s)', type: 'number', min: 0, step: 0.5, shapes: SH_ALL, help: 'a jump round every this many seconds (the Brander\'s mandala turns every 3 s); 0 = never' },
    { k: 'turn_deg', label: 'Turn by (°)', type: 'number', step: 1, shapes: SH_ALL, help: 'how far each jump turns it (a five-petal rose: 36° = half a petal, so the petals come where the gaps were)' },
    { k: 'offset_deg', label: 'Turned from its aim (°)', type: 'number', step: 1, shapes: SH_ALL, help: 'turned this far from its aim (60 with three arms puts the hero between two arms at the start)' },
    { k: 'aim', label: 'Aim', type: 'select', opts: EAIM_OPTS, shapes: SH_ALL, help: 'hero: at the hero where he stands as the bullets begin; track: at the hero at every volley; fixed: due east; random: a new random way every volley (the opening of a ring somewhere else each time)' },
    { k: 'start', label: 'From (share)', type: 'number', min: 0, max: 1, step: 0.05, shapes: SH_ALL, help: 'it is on from this share of the bullets\' time (0 = from the first moment)' },
    { k: 'stop', label: 'To (share)', type: 'number', min: 0, max: 1, step: 0.05, shapes: SH_ALL, help: '...to this share (1 = to the end)' },
    { k: 'pulse_every', label: 'On and off every (s)', type: 'number', min: 0, step: 0.5, shapes: SH_ALL, help: 'it comes on and goes off in a rhythm this long (0 = always on): the Gila\'s second fan comes on every second sweep' },
    { k: 'pulse_on', label: '...on for (s)', type: 'number', min: 0, step: 0.5, shapes: SH_ALL, help: 'how long of each rhythm it is on' },
    { k: 'pulse_at', label: '...first on at (s)', type: 'number', min: 0, step: 0.5, shapes: SH_ALL, help: 'when it first comes on (seconds into the bullets)' },
    { k: 'finale_pull', label: 'Finale pull (s)', type: 'number', min: 0, step: 0.1, shapes: SH_ALL, help: 'the last this many seconds of the bullets it fires nothing and every bullet of it still flying turns back towards the boss (the Brander\'s finale: never stand between a fireball and him); 0 = none' },
    { k: 'pull_speed', label: 'Pull speed (m/s)', type: 'number', min: 0.1, step: 0.5, shapes: SH_ALL, help: 'how fast the bullets come home in the finale' },
    { k: 'width', label: 'Wall length (m)', type: 'number', min: 0, step: 0.5, shapes: ['wall'], help: 'wall: how long the line of bullets is' },
  ];

  /** Pass 114 (lane EDITOR; Garry: "Then tell me how I can edit this myself in the future"): the plain-words how-to of a
   *  bullet heaven, the same as docs/howto/boss_bullet_heaven.md: which box changes what. [title, [steps]] */
  const HOWTO = [
    ['How long it lasts', [
      '<b>Timing → Bullets for (s)</b>: the seconds of bullets after the warning (the King\'s Royal Dust Devil: 16). The warning (<b>Tell (s)</b>, 2) comes before it and his dazed seconds (<b>Spent for (s)</b>, 2.5) after it.',
      'Each emitter\'s <b>From (share)</b> and <b>To (share)</b> are shares of that time (0.15 to 0.9 = from 15% to 90% of it), so a longer attack keeps its shape.']],
    ['How far the bullets fly', [
      '<b>Projectile → Range (m)</b>: a bullet shrinks away this far from where the boss stood (the King: 48 m; the screen shows about 12 m round the hero).',
      'Each emitter\'s <b>Speed (m/s)</b>: how fast its bullets fly (the hero walks about 5). Faster bullets reach the range sooner, so fewer are in the air.']],
    ['How far apart the bullets are (each emitter on its own)', [
      '<b>Bullets a volley</b>: fewer = more room between them (a ring of 16 instead of 20 = a quarter more room).',
      '<b>Spread (°)</b> (spiral, fan, sweep): a wider spread with the same bullets = more room between them.',
      '<b>Opening</b> (ring: degrees left open; wall: metres left open): the gap to run through.',
      '<b>Volleys a second</b>: lower = more room between one volley and the next along the same line.',
      'The preview (▶ Play) shows the bullets to scale; the line under it says how many are in the air at most (keep it under 600 for the phone).']],
    ['When it comes, and how often', [
      '<b>When it comes → Not before (s)</b>: never sooner in the fight. <b>First at HP below</b>: the first comes when he falls under this share of his HP... <b>...or at the latest (s)</b>: ...or this many seconds in.',
      '<b>Then every (s)</b>: the next one comes this many seconds after the last one is completely over (the warning, the bullets and his dazed seconds all done).',
      'Each of the three can be <b>fixed</b> (one number) or a <b>range</b> (min and max): the game picks a number between them, Not before and At the latest once per fight, Then every after each attack. 10 to 15 = somewhere from 10 s to 15 s.',
      'The line <b>In a fight</b> under the preview shows when the first three can start and end, earliest to latest.']],
    // pass 115 (lane BOSS)
    ['The barrier round him and the hero', [
      '<b>The barrier → Barrier</b>: its look (the King\'s tumbleweed fence, the Gila\'s cactus fence, the Brander\'s iron fence) or none. It comes up out of the sand as the warning begins, on the hero\'s side first, holds him inside while the bullets fly and falls apart as the bullets end (<b>Stands</b>: or when his dazed seconds end).',
      'With a barrier the attack only begins when the hero is within its reach of the boss (the white dashed circle in the preview); due while he is further off, it waits and begins the moment he comes in. So the wall never comes up on him.',
      '<b>Where it stands</b>: range = the <b>Inset</b> inside the bullets\' Range (every spot inside can be hit; off the screen until he runs out to it); fixed = at the <b>Radius</b> you type (12 to 16 m keeps it on the screen while he dodges; the bullets vanish at it).',
      '<b>Rise</b>, <b>Spread</b>, <b>Fall</b> (s): how it comes up and falls apart; <b>Creatures</b>: kept on their side or walking through; <b>Bullets at it</b>: vanish at it or fly on.']],
    ['Then', [
      '<b>Save attack</b> (Ctrl+S). The next fight plays it. If the build (or the tests) holds Godot, the file is saved at once and the import follows by itself when Godot is free; the status line says whether the build being made includes it.',
      'Ctrl+Z undoes, Revert goes back to the file as saved. <b>JSON…</b> (next to Save attack) opens the whole attack as text: change any key, even ones without a box, then Apply.']],
  ];
  function howtoBox() {
    const det = el('details', { class: 'asection batk-sec batk-howto' }, el('summary', {}, el('span', { class: 'asec-title', text: 'How do I change it?' }), el('span', { class: 'muted small', text: ' how long, how far, how far apart, when (also docs/howto/boss_bullet_heaven.md)' })));
    const body = el('div', { class: 'asec-body' });
    for (const [title, steps] of HOWTO) {
      body.appendChild(el('h4', { text: title }));
      const ul = el('ul', { class: 'small' });
      for (const st of steps) { const x = el('li'); x.innerHTML = st; ul.appendChild(x); }
      body.appendChild(ul);
    }
    det.appendChild(body);
    return det;
  }

  function setEmitter(idx, k, v) {
    edit((d) => {
      if (!Array.isArray(d.emitters)) d.emitters = [];
      const e = d.emitters[idx];
      if (!e || typeof e !== 'object') return;
      if (v == null || v === '') delete e[k]; else e[k] = v;
    });
  }

  function emittersPane(d) {
    const ems = Array.isArray(d.emitters) ? d.emitters : [];
    const det = el('details', { class: 'asection batk-sec', open: true }, el('summary', {}, el('span', { class: 'asec-title', text: `Emitters (${ems.length})` }), el('span', { class: 'muted small', text: ' what fires the bullets: each its own shape and clock, all at once' })));
    const body = el('div', { class: 'asec-body' });
    ems.forEach((e, idx) => {
      const full = M.emitterFull(e);
      const box = el('div', { class: 'batk-emitter' });
      box.appendChild(el('div', { class: 'batk-emitter-head' },
        el('b', { text: `Emitter ${idx + 1}: ${full.shape}` }),
        el('span', { class: 'spacer' }),
        el('button', { class: 'btn small', type: 'button', text: 'Copy', title: 'add a copy of this emitter', onclick: () => edit((x) => { x.emitters.splice(idx + 1, 0, JSON.parse(JSON.stringify(e))); }) }),
        el('button', { class: 'btn small danger', type: 'button', text: 'Remove', disabled: ems.length <= 1, title: ems.length <= 1 ? 'a pattern needs at least one emitter' : 'take this emitter out', onclick: () => edit((x) => { x.emitters.splice(idx, 1); }) })));
      for (const f of EMITTER_FIELDS) {
        if (!f.shapes.includes(String(full.shape))) continue;
        const cur = e[f.k];
        const dflt = M.EMITTER_DEFAULTS[f.k];
        const path = `emitters.${idx}.${f.k}`;
        const set = (v) => setEmitter(idx, f.k, v);
        let ctl;
        if (f.type === 'select') ctl = Forms.select(f.opts, cur == null ? '' : cur, set, { path, emptyLabel: `— (${dflt})` });
        else ctl = Forms.numberInput({ key: path, min: f.min, max: f.max, step: f.step, int: f.type === 'int' }, cur, set, { path, placeholder: dflt, cls: 'short' });
        box.appendChild(Forms.row({ key: path, label: f.label, help: f.help }, ctl, {}));
      }
      body.appendChild(box);
    });
    body.appendChild(el('div', { class: 'alt-actions' },
      el('button', { class: 'btn small primary', type: 'button', text: '+ Add an emitter', onclick: () => edit((x) => { if (!Array.isArray(x.emitters)) x.emitters = []; x.emitters.push({ shape: 'ring', count: 12, speed: 3.0, rate: 1.0, aim: 'hero' }); }) })));
    det.appendChild(body);
    return det;
  }

  /** The pattern from above, to scale, at S.t seconds after the tell begins: the dark ground and the shell through the tell,
   *  the bullets flying through the bullets' seconds (the hero 8 m off, standing still), spent; Play runs the clock. */
  function patternPreview(d) {
    const wrap = el('div', { class: 'batk-prev' });
    const boss = scripted().find((c) => (recOf(S.open) || { used_by: [] }).used_by.includes(c.id)) || scripted().find((c) => c.kind === 'boss') || { radius: 2.4, damage: 24, name: 'boss' };
    const bossR = M.num(boss.radius, 2.4);
    const tell = Math.max(M.num(M.val(d, 'tell', 'seconds'), 2), 0);
    const bul = M.patternDuration(d);
    const spent = Math.max(M.num(M.val(d, 'spent', 'seconds'), 2.5), 0);
    const total = tell + bul + spent;
    if (S.t == null || S.t > total) S.t = tell + bul * 0.6;
    const t = S.t;
    const rng = Math.max(M.num(M.val(d, 'projectile', 'range'), 18), 0.5);
    // (pass 115: room for a barrier standing past the range)
    const extent = Math.max(rng, 10, M.barrierOn(d) ? M.barrierRadius(d) + M.barrierHalf(d) : 0) + 2;
    const W = 460, C = W / 2, ppm = (W / 2 - 8) / extent;
    const X = (x) => C + x * ppm, Y = (z) => C + z * ppm;
    const s = svg('svg', { class: 'batk-svg', viewBox: `0 0 ${W} ${W}`, width: W, height: W, role: 'img', 'aria-label': 'the pattern from above' });
    s.appendChild(svg('rect', { x: 0, y: 0, width: W, height: W, rx: 10, class: 'bp-ground' }));
    const tint = M.val(d, 'projectile', 'tint') || '#FF8A1F';
    const heroAt = [0, -8];
    const heroAim = Math.atan2(heroAt[1], heroAt[0]);
    // the dark ground and the edge of the range
    const rr = M.num(M.val(d, 'tell', 'ring_radius'), 9);
    const dark = t < tell ? Math.min(t / Math.max(tell * 0.6, 0.01), 1) : (t < tell + bul ? 1 : Math.max(1 - (t - tell - bul) / Math.max(spent * 0.8, 0.01), 0));
    if (rr > 0) s.appendChild(svg('circle', { cx: X(0), cy: Y(0), r: rr * ppm, fill: M.val(d, 'tell', 'ring_color') || '#140A06', 'fill-opacity': 0.45 * dark, stroke: M.val(d, 'tell', 'banner_color') || '#E8502A', 'stroke-width': 2, 'stroke-opacity': t < tell + bul ? 0.8 * dark : 0 }));
    s.appendChild(svg('circle', { cx: X(0), cy: Y(0), r: rng * ppm, class: 'bp-edge' }));
    // pass 115 (lane BOSS): the barrier (its thickness to scale, coming up through the tell from the hero's side, falling
    // apart as the bullets end or as he recovers) and the reach rule's circle (dashed: the hero must be inside it for the
    // attack to begin)
    if (M.barrierOn(d)) {
      const BCOL = { tumbleweed_fence: '#7A5230', cactus_fence: '#3E8A44', iron_fence: '#2E2828' };
      const br0 = M.barrierRadius(d), bh = M.barrierHalf(d);
      const rise = Math.max(M.num(M.val(d, 'barrier', 'rise_s'), 0.8), 0.05) + Math.max(M.num(M.val(d, 'barrier', 'spread_s'), 0.6), 0);
      const fallAt = tell + bul + (String(M.val(d, 'barrier', 'hold')) === 'spent' ? spent : 0);
      const fall = Math.max(M.num(M.val(d, 'barrier', 'fall_s'), 1), 0.05) + Math.max(M.num(M.val(d, 'barrier', 'spread_s'), 0.6), 0);
      const up = t < fallAt ? Math.min(t / rise, 1) : Math.max(1 - (t - fallAt) / fall, 0);
      if (up > 0) {
        s.appendChild(svg('circle', { cx: X(0), cy: Y(0), r: br0 * ppm, fill: 'none', stroke: BCOL[String(M.val(d, 'barrier', 'look'))] || '#7A5230', 'stroke-width': Math.max(2 * bh * ppm, 3), opacity: 0.85 * up }));
        s.appendChild(svg('circle', { cx: X(0), cy: Y(0), r: br0 * ppm, fill: 'none', stroke: M.val(d, 'barrier', 'glow_color') || '#FF8A1F', 'stroke-width': 1.5, 'stroke-dasharray': '2 7', opacity: up }));
      }
      s.appendChild(svg('circle', { cx: X(0), cy: Y(0), r: Math.max(M.barrierReach(d), 0) * ppm, fill: 'none', stroke: '#ffffff', 'stroke-width': 1.2, 'stroke-dasharray': '5 5', opacity: 0.55 }));
    }
    const sig = M.num(M.val(d, 'shell', 'sigil_radius'), 0);
    if (sig > 0 && t < total) s.appendChild(svg('circle', { cx: X(0), cy: Y(0), r: sig * ppm, fill: 'none', stroke: M.val(d, 'shell', 'sigil_color') || '#FF6A1A', 'stroke-width': 3, 'stroke-dasharray': '6 4', opacity: t < tell ? Math.min(t / Math.max(tell, 0.01), 1) : (t < tell + bul ? 1 : 0.3) }));
    // the bullets
    const look = String(M.val(d, 'projectile', 'look'));
    const br = Math.max((M.BB_RADIUS[look] || 0.4) * M.num(M.val(d, 'projectile', 'size'), 1) * ppm, 2);
    const aimOf = (e, k, t) => {
      const aim = String(e.aim);
      if (aim === 'fixed') return 0;
      if (aim === 'random') return M.rng(S.seed * 31 + k * 977 + Math.round(t * 1000)).randf() * Math.PI * 2;
      return heroAim;
    };
    let sim = null;
    if (t >= tell && t < tell + bul) {
      sim = M.simulate(d, 1 / 30, t - tell, aimOf);
      for (const b of sim.at) s.appendChild(svg('circle', { cx: X(b.x), cy: Y(b.z), r: br, fill: tint, stroke: b.pull ? '#ffffff' : '#1a0d08', 'stroke-width': 1.6 }));
    }
    // the boss (his shell's colour while guarded), the hero to scale, a 5 m bar
    const guarded = t < tell + bul;
    s.appendChild(svg('circle', { cx: X(0), cy: Y(0), r: bossR * ppm, class: 'bp-boss', stroke: guarded ? (M.val(d, 'shell', 'color') || '#C9A46A') : '#e0a63a', 'stroke-width': guarded ? 5 : 3 }));
    s.appendChild(svg('text', { x: X(0), y: Y(0) + 4, class: 'bp-label mid', text: boss.name || 'boss' }));
    s.appendChild(svg('circle', { cx: X(heroAt[0]), cy: Y(heroAt[1]), r: Math.max(2.5, M.HERO_RADIUS * ppm), class: 'bp-hero' }));
    s.appendChild(svg('text', { x: X(heroAt[0]) + 8, y: Y(heroAt[1]) + 4, class: 'bp-label', text: 'hero (to scale)' }));
    s.appendChild(svg('line', { x1: 12, y1: W - 14, x2: 12 + 5 * ppm, y2: W - 14, class: 'bp-bar' }));
    s.appendChild(svg('text', { x: 12, y: W - 19, class: 'bp-label', text: '5 m' }));
    const phase = t < tell ? `the tell ${fmtN(t, 1)} / ${fmtN(tell, 1)} s: ${(M.val(d, 'tell', 'banner') || d.name || '').toUpperCase()}` : (t < tell + bul ? `bullets ${fmtN(t - tell, 1)} / ${fmtN(bul, 1)} s · ${sim ? sim.at.length : 0} in the air` : `spent ${fmtN(t - tell - bul, 1)} / ${fmtN(spent, 1)} s: DAZED`);
    s.appendChild(svg('text', { x: W - 10, y: 18, class: 'bp-label end', text: phase }));
    wrap.appendChild(s);
    const side = el('div', { class: 'batk-prev-side' });
    const slider = el('input', { type: 'range', min: 0, max: total, step: 0.01, value: t, 'data-path': 'preview.t' });
    slider.addEventListener('input', () => { S.t = Number(slider.value); S.playing = false; redraw(); });
    const play = el('button', { class: 'btn small', type: 'button', text: S.playing ? 'Pause' : '▶ Play', onclick: () => { if (S.playing) { S.playing = false; redraw(); return; } S.playing = true; if (S.t >= total - 0.02) S.t = 0; tick(total); } });
    side.appendChild(el('div', { class: 'batk-prev-ctl' }, play, slider));
    const all = M.simulate(d, 1 / 30, null, aimOf);
    const facts = el('ul', { class: 'batk-facts small' });
    const li = (h) => { const x = el('li'); x.innerHTML = h; facts.appendChild(x); };
    const tr = (k) => M.num(M.val(d, 'trigger', k), M.DEFAULTS.trigger[k]);
    // pass 114 (lane EDITOR): a range reads "10–15 s" (rolled once a fight; the cooldown after every attack), and the
    // cooldown counts from the moment the attack is completely over
    const rg = (k) => M.fmtRange(M.triggerRange(d, k));
    li(`<b>When:</b> never in the first ${rg('first_after')} of the fight; the first when the boss falls under ${fmtN(tr('first_at_hp') * 100, 0)}% HP, or ${rg('first_by')} in at the latest; then ${rg('cooldown')} after the last one is <b>completely over</b> (his tell, the bullets and his spent seconds done). A range is a new pick ${M.TRIGGER_RANGES.some((k) => M.triggerRange(d, k)[0] !== M.triggerRange(d, k)[1]) ? 'between its min and max (Not before and At the latest once a fight, Then every after each attack)' : 'when you give one'}. Never in his attack cycle, and only between his attacks`);
    // the fight's first three, earliest to latest (full HP the whole fight = the latest; under the HP share at once = the earliest)
    const sched = M.patternSchedule(d, 3);
    const span = (r) => (Math.abs(r[0] - r[1]) < 0.05 ? `${fmtN(r[0], 1)} s` : `${fmtN(r[0], 1)}–${fmtN(r[1], 1)} s`);
    li(`<b>In a fight</b> (seconds since he arrived, earliest–latest; his own attacks can only make one later, ×1/pace on the map): ${sched.map((x) => `${['1st', '2nd', '3rd'][x.k - 1]} starts ${span(x.start)}, over ${span(x.end)}`).join(' · ')}`);
    li(`<b>${fmtN(tell, 1)} s tell</b> (banner, dark ground, wind-up sound, music down ${fmtN(-M.num(M.val(d, 'tell', 'duck_db'), -14), 0)} dB, his wind-up) → <b>${fmtN(bul, 1)} s of bullets</b> → <b>${fmtN(spent, 1)} s spent</b>: about ${fmtN(total, 1)} s in all (×1/pace on the map). Meanwhile no other attack of his and no new creatures from the boss fight's rows`);
    li(`<b>${all.peak}</b> bullets in the air at most (at ${fmtN(all.peak_t, 1)} s), ${all.fired} in all over ${all.volleys} volleys (without a hero to hit)`);
    // pass 115 (lane BOSS): the barrier in words
    if (M.barrierOn(d)) {
      const lk = { tumbleweed_fence: 'a tumbleweed fence', cactus_fence: 'a cactus fence', iron_fence: 'an iron fence' }[String(M.val(d, 'barrier', 'look'))] || 'a barrier';
      li(`<b>Barrier:</b> ${lk} ${fmtN(M.barrierRadius(d), 1)} m round him (the hero held within ${fmtN(M.barrierHeroLimit(d), 1)} m of him${M.val(d, 'barrier', 'hero_block') ? '' : ': <b>off</b>, he can walk through it'}); it begins <b>only with the hero within ${fmtN(M.barrierReach(d), 1)} m</b> (the dashed circle: due while he is further off, it waits for him to come in); bullets ${M.barrierStopsBullets(d) ? `vanish at it (${fmtN(M.bulletReach(d), 1)} m)` : 'fly through it'}; creatures ${String(M.val(d, 'barrier', 'creatures')) === 'pass' ? 'walk through it' : 'stay on their side'}; it falls apart ${String(M.val(d, 'barrier', 'hold')) === 'spent' ? 'when his dazed seconds end' : 'as the bullets end'}`);
    }
    li(`a bullet takes <b>${fmtN(M.num(M.val(d, 'hit', 'hit_frac'), 0.12) * 100, 0)}%</b> of the hero's max HP and is gone; the ones left when the bullets end burn out over ${fmtN(M.num(M.val(d, 'timing', 'clear'), 0.6), 1)} s, harmless`);
    li(`guarded: he takes <b>${fmtN((1 - Math.min(Math.max(M.num(M.val(d, 'guard', 'share'), 0.8), 0), 0.95)) * 100, 0)}%</b> of every hit (grey numbers, a grey bar); spent: <b>×${fmtN(M.num(M.val(d, 'spent', 'damage_taken'), 1.5), 2)}</b>`);
    side.appendChild(facts);
    side.appendChild(el('p', { class: 'muted small', text: 'From above, to scale, the hero standing still 8 m off (track aims follow him there; random aims are one example). White-rimmed bullets are being pulled home by a finale.' }));
    wrap.appendChild(side);
    return wrap;
  }


  // ------------------------------------------------------------------ the preview

  /** The attack from above, to scale, at time S.t (seconds after the wind-up begins): the boss, the hero 8 m off, the
   *  warning, the spots and the shots as they would be then. Play runs the clock; New layout throws another random. */
  function preview(d, kind) {
    const wrap = el('div', { class: 'batk-prev' });
    const boss = scripted().find((c) => (recOf(S.open) || { used_by: [] }).used_by.includes(c.id)) || scripted().find((c) => c.kind === 'boss') || { radius: 2.4, damage: 24, name: 'boss' };
    const bossR = M.num(boss.radius, 2.4);
    // (pass 73: a rain lit all at once winds up at least as long as its circles show)
    const wind = M.windupSeconds(d);
    const lay = kind === 'rain' ? M.rainLayout(d, S.seed) : null;
    const pat = M.patternFull(d);
    const rmax = M.num(pat.radius_max, 16);
    let dur = wind + 1;
    if (kind === 'rain') dur = wind + lay.lasts + 0.6;
    if (kind === 'volley') dur = wind + Math.max(M.num(pat.waves, 1) - 1, 0) * M.num(pat.wave_gap, 0.5) + M.num(M.val(d, 'projectile', 'range'), 18) / Math.max(M.num(M.val(d, 'projectile', 'speed'), 12), 0.1) + 0.3;
    if (kind === 'ring') dur = wind + Math.max(M.num(pat.count, 1) - 1, 0) * M.num(pat.wave_gap, 0.5) + rmax / Math.max(M.num(M.val(d, 'projectile', 'speed'), 12), 0.1) + 0.3;
    if (kind === 'slam') dur = wind + 0.8;
    if (S.t == null || S.t > dur) S.t = dur * 0.62;
    const t = S.t;
    const extent = Math.max(kind === 'volley' ? M.num(M.val(d, 'projectile', 'range'), 18) : rmax, 10) + 2;
    const W = 460, C = W / 2, ppm = (W / 2 - 8) / extent;
    const X = (x) => C + x * ppm, Y = (z) => C + z * ppm;
    const s = svg('svg', { class: 'batk-svg', viewBox: `0 0 ${W} ${W}`, width: W, height: W, role: 'img', 'aria-label': 'the attack from above' });
    s.appendChild(svg('rect', { x: 0, y: 0, width: W, height: W, rx: 10, class: 'bp-ground' }));
    const tint = M.val(d, 'projectile', 'tint') || '#D0242F';
    const warn = M.val(d, 'telegraph', 'color') || '#ED4A5C';
    const telKind = M.val(d, 'telegraph', 'kind');
    const heroAt = [0, -8];
    const centerHero = pat.center === 'hero';
    const cx = centerHero ? heroAt[0] : 0, cz = centerHero ? heroAt[1] : 0;
    const fired = t >= wind;
    const tc = t - wind;   // seconds after it fires
    if (kind === 'rain') {
      s.appendChild(svg('circle', { cx: X(cx), cy: Y(cz), r: lay.rmax * ppm, class: 'bp-edge' }));
      if (lay.rmin > 0) s.appendChild(svg('circle', { cx: X(cx), cy: Y(cz), r: lay.rmin * ppm, class: 'bp-edge inner' }));
      // pass 73: a rain lit all at once shows its circles instead of the area's outline
      const allAt = M.litAtOnce(d);
      if (!fired && telKind !== 'none' && !allAt) s.appendChild(svg('circle', { cx: X(cx), cy: Y(cz), r: lay.rmax * ppm, fill: 'none', stroke: warn, 'stroke-width': 2, opacity: 0.7 }));
      const tel = M.num(M.val(d, 'telegraph', 'seconds'), 0.9);
      // the narrowest gap
      let pair = null, best = Infinity;
      lay.pts.forEach((p, a) => { for (let b = a + 1; b < lay.pts.length; b++) { const q = lay.pts[b]; const g = Math.hypot(p[0] - q[0], p[1] - q[1]); if (g < best) { best = g; pair = [p, q]; } } });
      lay.pts.forEach((p, k) => {
        const land = lay.times[k];
        const x = X(cx + p[0]), y = Y(cz + p[1]), r = lay.landR * ppm;
        // when its circle lights, in seconds after the spikes leave (pass 73: all at once, before the spew)
        const litAt = allAt ? -Math.min(tel, wind) : land - tel;
        if (telKind === 'none' || tc < litAt) { s.appendChild(svg('circle', { cx: x, cy: y, r, class: 'bp-spot' })); }
        else if (tc < land) {
          const f = Math.min(Math.max((tc - litAt) / Math.max(land - litAt, 0.01), 0), 1);
          if (allAt) s.appendChild(svg('circle', { cx: x, cy: y, r, fill: warn, 'fill-opacity': 0.2 + 0.25 * f, stroke: warn, 'stroke-width': 1.8 }));
          else s.appendChild(svg('circle', { cx: x, cy: y, r: r * (0.4 + 0.6 * f), fill: warn, 'fill-opacity': 0.18, stroke: warn, 'stroke-width': 1.6 }));
        } else {
          const age = tc - land;
          s.appendChild(svg('circle', { cx: x, cy: y, r, fill: tint, 'fill-opacity': Math.max(0.15, 0.6 - age * 0.5), stroke: tint, 'stroke-width': 1 }));
        }
        // a shot in the air (from above: on the straight line from the boss; pass 73: a volley's own flight)
        const fl = lay.flights ? lay.flights[k] : lay.flight;
        const launch = land - fl;
        if (fired && tc >= launch && tc < land) {
          const u = (tc - launch) / fl;
          s.appendChild(svg('circle', { cx: X(p[0] * u + cx * u), cy: Y(p[1] * u + cz * u), r: Math.max(2.5, 0.25 * M.num(M.val(d, 'projectile', 'size'), 1) * ppm), fill: tint, stroke: '#000', 'stroke-width': 0.6 }));
        }
      });
      if (pair) {
        const [p, q] = pair;
        const len = Math.hypot(q[0] - p[0], q[1] - p[1]) || 1;
        const ux = (q[0] - p[0]) / len, uz = (q[1] - p[1]) / len;
        s.appendChild(svg('line', { x1: X(cx + p[0] + ux * lay.landR), y1: Y(cz + p[1] + uz * lay.landR), x2: X(cx + q[0] - ux * lay.landR), y2: Y(cz + q[1] - uz * lay.landR), class: 'bp-gap' }));
      }
    } else if (kind === 'volley') {
      const aimA = pat.aim === 'fixed' ? 0 : Math.atan2(heroAt[1], heroAt[0]);
      const dirs = M.volleyDirs(d, aimA);
      const range = M.num(M.val(d, 'projectile', 'range'), 18), spd = M.num(M.val(d, 'projectile', 'speed'), 12);
      for (const a of dirs) s.appendChild(svg('line', { x1: X(0), y1: Y(0), x2: X(Math.cos(a) * range), y2: Y(Math.sin(a) * range), stroke: warn, 'stroke-width': fired ? 1 : 2.5, opacity: fired ? 0.35 : 0.85, 'stroke-linecap': 'round' }));
      if (fired) for (let w = 0; w < Math.max(Math.round(M.num(pat.waves, 1)), 1); w++) {
        const tw = tc - w * M.num(pat.wave_gap, 0.5);
        if (tw < 0 || tw * spd > range) continue;
        for (const a of dirs) s.appendChild(svg('circle', { cx: X(Math.cos(a) * tw * spd), cy: Y(Math.sin(a) * tw * spd), r: Math.max(3, 0.3 * M.num(M.val(d, 'projectile', 'size'), 1) * ppm), fill: tint }));
      }
    } else if (kind === 'ring') {
      const spd = M.num(M.val(d, 'projectile', 'speed'), 12);
      const dr = rmax / Math.max(spd, 0.1);
      const width = M.num(pat.width, 1.2);
      s.appendChild(svg('circle', { cx: X(0), cy: Y(0), r: rmax * ppm, fill: 'none', stroke: warn, 'stroke-width': fired ? 1 : 2.5, opacity: fired ? 0.3 : 0.85 }));
      if (fired) for (let w = 0; w < Math.max(Math.round(M.num(pat.count, 1)), 1); w++) {
        const f = (tc - w * M.num(pat.wave_gap, 0.5)) / dr;
        if (f < 0 || f >= 1) continue;
        const front = M.ringFront(rmax, f);
        s.appendChild(svg('circle', { cx: X(0), cy: Y(0), r: Math.max(0.5, front - front * width / rmax / 2) * ppm, fill: 'none', stroke: tint, 'stroke-width': Math.max(2, front * width / rmax * ppm), opacity: 0.85 * (1 - f * f) + 0.15 }));
      }
    } else if (kind === 'slam') {
      const r = rmax * ppm;
      if (!fired) s.appendChild(svg('circle', { cx: X(cx), cy: Y(cz), r: r * (0.4 + 0.6 * Math.min(t / Math.max(wind, 0.01), 1)), fill: warn, 'fill-opacity': 0.2, stroke: warn, 'stroke-width': 2 }));
      else if (tc < 0.6) s.appendChild(svg('circle', { cx: X(cx), cy: Y(cz), r, fill: tint, 'fill-opacity': 0.5 * (1 - tc / 0.6), stroke: tint, 'stroke-width': 2 }));
    }
    // the boss, the hero to scale, a 5 m bar
    s.appendChild(svg('circle', { cx: X(0), cy: Y(0), r: bossR * ppm, class: 'bp-boss' }));
    s.appendChild(svg('text', { x: X(0), y: Y(0) + 4, class: 'bp-label mid', text: boss.name || 'boss' }));
    s.appendChild(svg('circle', { cx: X(heroAt[0]), cy: Y(heroAt[1]), r: Math.max(2.5, M.HERO_RADIUS * ppm), class: 'bp-hero' }));
    s.appendChild(svg('text', { x: X(heroAt[0]) + 8, y: Y(heroAt[1]) + 4, class: 'bp-label', text: 'hero (to scale)' }));
    s.appendChild(svg('line', { x1: 12, y1: W - 14, x2: 12 + 5 * ppm, y2: W - 14, class: 'bp-bar' }));
    s.appendChild(svg('text', { x: 12, y: W - 19, class: 'bp-label', text: '5 m' }));
    s.appendChild(svg('text', { x: W - 10, y: 18, class: 'bp-label end', text: fired ? `${fmtN(tc, 2)} s after it fires` : `wind-up ${fmtN(t, 2)} / ${fmtN(wind, 2)} s` }));
    wrap.appendChild(s);
    // the controls and the numbers
    const side = el('div', { class: 'batk-prev-side' });
    const slider = el('input', { type: 'range', min: 0, max: dur, step: 0.01, value: t, 'data-path': 'preview.t' });
    slider.addEventListener('input', () => { S.t = Number(slider.value); S.playing = false; redraw(); });
    const play = el('button', { class: 'btn small', type: 'button', text: S.playing ? 'Pause' : '▶ Play', onclick: () => { if (S.playing) { S.playing = false; redraw(); return; } S.playing = true; if (S.t >= dur - 0.02) S.t = 0; tick(dur); } });
    side.appendChild(el('div', { class: 'batk-prev-ctl' }, play, slider, kind === 'rain' ? el('button', { class: 'btn small', type: 'button', text: 'New layout', title: 'the game turns and jitters the layout at random every time: another example', onclick: () => { S.seed = (S.seed * 7919 + 13) % 100003; redraw(); } }) : null));
    const facts = el('ul', { class: 'batk-facts small' });
    const bite = M.num(boss.damage, 24);
    const li = (h) => { const x = el('li'); x.innerHTML = h; facts.appendChild(x); };
    if (kind === 'rain') {
      li(`<b>${lay.pts.length}</b> landing spots between ${fmtN(lay.rmin, 1)} and ${fmtN(lay.rmax, 1)} m (${pat.shape}, ${pat.order === 'out' ? 'nearest first' : pat.order})`);
      li(`the narrowest gap <b>${isFinite(lay.gap) ? fmtN(lay.gap, 2) : '—'} m</b> between two circles (the rule: at least ${fmtN(M.num(pat.gap, 1), 2)} m; the hero is ${fmtN(2 * M.HERO_RADIUS, 1)} m wide) <span class="bp-gapkey">━</span>`);
      li(`the circles cover <b>${fmtN(lay.cover * 100, 0)}%</b> of the ring`);
      if (M.isVolley(d)) li(`one spew from its mouth after the ${fmtN(wind, 2)} s wind-up (it crouches the last ${fmtN(M.num(M.val(d, 'spew', 'crouch'), 0.35), 2)} s): every shot lands between ${fmtN(lay.first, 2)} s and ${fmtN(lay.lasts, 2)} s after it, <b>all within ${fmtN(lay.lasts - lay.first, 2)} s</b> (×1/pace on the map)`);
      else li(`after the ${fmtN(wind, 2)} s wind-up the shots land from ${fmtN(lay.flight, 2)} s to ${fmtN(lay.lasts, 2)} s, each circle showing ${fmtN(M.num(M.val(d, 'telegraph', 'seconds'), 0.9), 2)} s before (×1/pace on the map)`);
      if (M.litAtOnce(d)) li(`<b>every circle lights at once</b> ${fmtN(Math.min(M.num(M.val(d, 'telegraph', 'seconds'), 0.9), wind), 2)} s before the spikes leave and stays lit until its own spike lands`);
    }
    if (kind === 'volley') li(`${Math.max(Math.round(M.num(pat.count, 1)), 1)} shots a wave × ${Math.max(Math.round(M.num(pat.waves, 1)), 1)} over ${fmtN(M.num(pat.spread_deg, 360), 0)}°, ${fmtN(M.num(M.val(d, 'projectile', 'range'), 18), 0)} m at ${fmtN(M.num(M.val(d, 'projectile', 'speed'), 12), 1)} m/s`);
    if (kind === 'ring') li(`${Math.max(Math.round(M.num(pat.count, 1)), 1)} ring(s) to ${fmtN(rmax, 1)} m, ${fmtN(M.num(pat.width, 1.2), 1)} m thick`);
    if (kind === 'slam') li(`a blast of ${fmtN(rmax, 1)} m round the ${pat.center === 'hero' ? 'hero\'s spot' : 'boss'}`);
    li(`a hit: ${fmtN(M.topVal(d, 'damage'), 2)} × ${boss.name ? boss.name + '\'s' : 'the'} bite ${fmtN(bite, 0)} = <b>${fmtN(M.hitDamage(d, bite, 1), 1)}</b> before the stage, level and map factors; knockback ${fmtN(M.topVal(d, 'knockback'), 1)}${M.topVal(d, 'lift') > 0 ? ', lift ' + fmtN(M.topVal(d, 'lift'), 1) : ''}`);
    side.appendChild(facts);
    side.appendChild(el('p', { class: 'muted small', text: 'From above, to scale. The game turns and jitters a rain\'s layout at random every time it fires; this is one example with the same rules (the gap rule holds in every one).' }));
    wrap.appendChild(side);
    return wrap;
  }

  let _raf = 0;
  function tick(dur) {
    cancelAnimationFrame(_raf);
    let last = performance.now();
    const step = (now) => {
      if (!S.playing || App.S.tab !== 'bossattacks') { S.playing = false; return; }
      S.t = Math.min(dur, (S.t || 0) + (now - last) / 1000);
      last = now;
      if (S.t >= dur) S.playing = false;
      redraw();
      if (S.playing) _raf = requestAnimationFrame(step);
    };
    _raf = requestAnimationFrame(step);
  }

  // ------------------------------------------------------------------ keys (this tab's own Ctrl+S / Z / Y)

  if (typeof window !== 'undefined') {
    window.addEventListener('keydown', (e) => {
      if (typeof App === 'undefined' || App.S.tab !== 'bossattacks') return;
      if (document.querySelector('.jedit-back')) return;   // pass 114: the JSON window has the keys while it is open
      const ctrl = e.ctrlKey || e.metaKey;
      if (!ctrl) return;
      const k = e.key.toLowerCase();
      const tgt = e.target;
      const typing = tgt && (tgt.tagName === 'INPUT' || tgt.tagName === 'TEXTAREA');
      if (k === 's') { e.preventDefault(); e.stopImmediatePropagation(); if (typing && tgt.blur) tgt.blur(); setTimeout(save, 0); return; }
      if (typing) return;
      if (k === 'z' && !e.shiftKey) { e.preventDefault(); e.stopImmediatePropagation(); undo(); return; }
      if (k === 'y' || (k === 'z' && e.shiftKey)) { e.preventDefault(); e.stopImmediatePropagation(); redo(); }
    }, true);
    window.addEventListener('beforeunload', (e) => { if (dirty()) { e.preventDefault(); e.returnValue = ''; } });
  }

  // ------------------------------------------------------------------ the Instructions tab's section

  function instructions(root) {
    const p = (h) => { const x = el('p'); x.innerHTML = h; return x; };
    const li = (h) => { const x = el('li'); x.innerHTML = h; return x; };
    const ol = (...steps) => el('ol', { class: 'howto' }, steps.map((s) => li(s)));
    const how = (title, steps) => { root.appendChild(el('h3', { text: title })); root.appendChild(steps); };
    root.appendChild(el('h2', { text: 'Pass 72: boss HP pegged to DPS, custom boss attacks' }));
    root.appendChild(el('h3', { text: 'Boss HP pegged to the hero\'s DPS (Settings → Boss HP)' }));
    const ul = el('ul', {});
    for (const w of (typeof BossScaling !== 'undefined' ? BossScaling.WORDS : [])) ul.appendChild(li(w));
    root.appendChild(ul);
    how('Tune it', ol(
      'Settings → <b>Boss HP</b>: <i>Peg boss HP to DPS</i> on; the <i>Exponent</i> (0.5), the <i>DPS window</i> (45 s), the <i>Floor</i> (0.75) and the <i>Ceiling</i> (3).',
      'Each boss\'s <b>reference DPS</b>: the DPS at which it keeps its data HP. A bigger reference = an easier boss for everyone below it. Pick a boss under the chart to see its curves; move the mouse over the chart to read any DPS.',
      'Measure a reference again after a balance change: <code>bash tools/godot.sh --headless --fixed-fps 60 --path game --script res://tools/difficulty_probe.gd -- t0=785 secs=75 stage=1 level=33 build=b2 mirror=1.5 hero=calavera seed=11</code> (the window ending at the boss\'s time) and read the <code>DPS45</code> line; <code>boss=1</code> plays on through the fight and prints its length, <code>scale=0</code> plays it at data HP.',
      'Save (the map\'s Save): the next run plays it.'));
    root.appendChild(el('h3', { text: 'Custom boss attacks (the Boss attacks tab)' }));
    root.appendChild(p('A custom attack is a content folder (<code>content/boss_attacks/&lt;id&gt;/&lt;id&gt;.json</code>) a boss\'s script names like a built-in: <code>{"name": "cactus_rain"}</code>. Its kind is one the game knows how to play; everything else is numbers. The Gila Grande\'s red cactus rain is the first one (it replaced its rumble).'));
    const kinds = el('ul', {});
    for (const k of KIND_OPTS) kinds.appendChild(li(`<b>${k.v}</b>: ${k.help}`));
    root.appendChild(kinds);
    how('Make one and give it to a boss', ol(
      'Boss attacks tab → <b>+ New attack</b>: a name (the id follows it), <i>Start from</i> a blank kind or a copy of an attack → <b>Make it</b>. It is written and imported at once.',
      'Tune it with the preview: the boss, the hero to scale 8 m off, the landing spots and the narrowest gap (the yellow line), the time slider and <b>▶ Play</b> (circles show red before their shot lands, landed spots fill in its colour). <b>New layout</b> throws another random turn and jitter (the game throws one every time).',
      'Every box shows the game\'s default in grey; <b>?</b> says what it does. Save attack (Ctrl+S). Ctrl+Z / Ctrl+Y step back and forth.',
      'Tick the bosses under <i>In the script of</i>: it goes to the end of their attack cycle (Enemies tab → the boss → <i>Attack script</i> to reorder it, give it a <i>Skip inside / beyond</i> range or its own wind-up for that boss).',
      '<b>Delete…</b> takes it out of every script first and moves the folder to the editor\'s backups.'));
    // pass 113 (lane BOSS): the bullet-heaven patterns
    root.appendChild(el('h3', { text: 'Pass 113: bullet-heaven patterns (kind "pattern")' }));
    root.appendChild(p('Each boss has one: the King\'s <b>Royal Dust Devil</b>, the Gila\'s <b>Venom Monsoon</b>, the Brander\'s <b>Hellbrand Mandala</b>. A pattern is never part of the boss\'s attack cycle (its place in his script does not matter): it comes on its own <i>When it comes</i> numbers, and only between his attacks. Then a big tell (the banner, the dark ground, the wind-up sound, the music down, his own wind-up, his shell), several seconds of slow bullets from its <b>emitters</b>, and the payoff: he stands <b>spent</b>, taking extra. From the tell to the last bullet he is <b>guarded</b> (80% less damage: a grey bar, grey numbers). While it runs nothing else of his starts and the boss fight\'s rows bring nobody new.'));
    how('Tune one', ol(
      'Boss attacks tab → the attack (the ★ list) → the preview: drag the slider through the tell, the bullets and spent, or ▶ Play. The numbers under it say how many bullets are in the air at most.',
      '<b>Emitters</b>: each is a spiral, ring, fan, sweep, wall or rose with its own speed and rhythm; <i>+ Add an emitter</i>, <i>Copy</i>, <i>Remove</i>. Every box shows the game\'s default in grey.',
      '<b>When it comes</b>: not before (s), the first at HP below (share) or at the latest (s), then every (s).',
      'Save attack (Ctrl+S): the next fight plays it.'));
    // pass 114 (lane EDITOR): the how-to (the tab's "How do I change it?" fold; docs/howto/boss_bullet_heaven.md)
    root.appendChild(el('h3', { text: 'Pass 114: change a bullet heaven yourself (how long, how far, how far apart, when)' }));
    for (const [title, steps] of HOWTO) { root.appendChild(el('h4', { text: title })); const u = el('ul', {}); for (const st of steps) u.appendChild(li(st)); root.appendChild(u); }
    const ek = el('ul', {});
    for (const f of EMITTER_FIELDS) ek.appendChild(li(`<i>${f.label}</i> (<code>${f.k}</code>, ${f.shapes.join('/')}): ${f.help}`));
    root.appendChild(el('h3', { text: 'Every emitter key' }));
    root.appendChild(ek);
    const keys = el('ul', {});
    for (const [g, title] of SECTIONS) {
      const rows = FIELDS.filter((f) => f.g === g);
      keys.appendChild(li(`<b>${title}</b> (<code>${g === '_top' ? 'damage, knockback, lift' : g}</code>): ` + rows.map((f) => `<i>${f.label}</i> (<code>${f.k}</code>, ${f.kinds.join('/')}): ${f.help}`).join('; ')));
    }
    root.appendChild(el('h3', { text: 'Every key' }));
    root.appendChild(keys);
  }

  return { render, options, get, open, ids: () => attacks().map((a) => a.id), save, undo, redo, instructions, FIELDS, SECTIONS, EMITTER_FIELDS, S };
})();
if (typeof module !== 'undefined') module.exports = BossAttacks;
