// What the editor knows about the timeline schema (pass 53, pass 54): every field with a one-line help, its type and its
// default. docs/waves_schema.md is the contract; the inspector, the Settings tab and the Instructions tab all read this
// table, so a field added here shows up in the form and in the documentation at once. Types:
//   int | number | seconds (a run-clock time; "mm:ss" accepted) | text | select | bool (yes/no) | bool3 (unset/yes/no)
//   percent (shown as %, stored 0..1) | enemy | variant | enemies (one id or a list with weights) | elite | pattern
//   interval (a number or [min, max]) | overrides | alts | list (array of numbers) | points (cap curve)
//   weights (presence keyframes [[t, w], ...]) | swatch (one hex colour) | swatches (a list of hex colours)
//   curve ({mode, points, formula}: the HP x / ATK x lanes) | spawn_sides (the compass block)
//   size_range (pass 58: one size or [min, max]) | tint (pass 58: {hue: [from, to], sat, val, amount})
'use strict';

const FIELDS = (() => {
  // pass 57: Ring (Garry: "spawn in a Ring around the Player ... about 30% further" than the arena's 9 m ring) and In
  // front (Garry: "spawn above the Player, basically an override to the Spawning part in the Settings")
  const PATTERNS = [
    { v: 'pack', label: 'Pack', help: 'the whole pack at one spawn point, spread out (the default)' },
    { v: 'scatter', label: 'Scatter', help: 'each creature at its own spawn point round the hero' },
    { v: 'single', label: 'Single', help: 'one creature per draw, whatever the pack size' },
    { v: 'ring', label: 'Ring', help: 'the whole spawn evenly round the hero on a ring 11.7 m out (the arena\'s 9 m ring × 1.3): a row\'s pack, a wave\'s burst, all at once; the hint under the field says how many make a thick ring' },
    { v: 'in_front', label: 'In front', help: 'from the top of the screen, whatever Settings → Spawning says: each creature at its own point 19–24 m up, within ±45° of straight up (a loose band across the top)' },
  ];
  const SWARM_PATTERNS = [
    { v: 'ring', label: 'Ring (16 m)', help: 'a ring 16 m round the hero, as the SWARM events always came (ignores the cap); the swarm keeps its own 16 m ring, a row\'s or a wave\'s Ring is 11.7 m' },
    { v: 'pack', label: 'Pack', help: 'packs through the spawn points (ignores the cap)' },
    { v: 'scatter', label: 'Scatter', help: 'one by one through the spawn points (ignores the cap)' },
    { v: 'in_front', label: 'In front', help: 'all of them from the top of the screen, whatever Settings → Spawning says: each at its own point 19–24 m up, within ±45° of straight up (ignores the cap)' },
  ];
  const CHANNELS = [
    { v: 'regular', label: 'regular', help: 'the regular crowd: spawns into the live cap' },
    { v: 'hell', label: 'hell', help: 'the hell channel: its own cap, hell_cap of the regular one, bodies on top of the crowd' },
  ];
  // pass 54: the HP x / ATK x curves' formula kinds (m = minutes of the run clock)
  const CURVE_KINDS = [
    { v: 'linear', label: 'linear: 1 + a × minutes', help: 'grows by a every minute' },
    { v: 'power', label: 'power: (1 + a × minutes)^b', help: 'the shape hp_growth / hp_power always had' },
    { v: 'exponential', label: 'exponential: (1 + a)^minutes', help: 'compounds by a every minute' },
  ];
  const SIDE_MODES = [
    { v: 'sides', label: 'screen sides', help: 'a side of the screen by the four weights, then a point 19-24 m out within ±45° of it' },
    { v: 'facing', label: 'where the hero faces', help: 'the old rule: facing_share of the spawns ahead of the hero within ±facing_spread_deg, the rest anywhere' },
  ];

  // ------------------------------------------------------------------ roster rows
  const roster = [
    { key: 'id', label: 'Id', type: 'text', help: 'a stable label (r1, r2, ...) so a reordered row keeps its numbers on save; the game ignores it' },
    { key: 'enemy', label: 'Creature', type: 'enemy', required: true, help: 'which creature this row spawns' },
    { key: 't', label: 'From', type: 'seconds', int: true, min: 0, required: true, help: 'the run second the row starts being drawn (the clock stands still through boss fights and portals)' },
    { key: 'until', label: 'Until', type: 'seconds', int: true, min: 0, help: 'the run second the row stops; empty = to the end of the run' },
    { key: 'weights', label: 'Presence', type: 'weights', help: 'the row\'s draw weight over the run clock as [time, weight] points: linear between them, flat before the first and after the last; its share of a burst is its weight against the other open rows of its channel (10 against 4 = 71% / 29%). Drag the points on the bar; double-click the bar to add one, a point to remove it' },
    { key: 'channel', label: 'Channel', type: 'select', options: CHANNELS, def: 'regular', help: 'regular crowd, or the hell channel with its own cap' },
    { key: 'pack', label: 'Pack', type: 'int', min: 1, help: 'how many spawn together; empty = the creature\'s own pack size' },
    { key: 'pattern', label: 'Pattern', type: 'select', options: PATTERNS, def: 'pack', help: 'pack at one point, scattered, one at a time, a ring round the hero (the pack at once, 11.7 m out) or in front (from the top of the screen, whatever the spawn side in Settings says)' },
    { key: 'variant', label: 'Art variant', type: 'variant', help: 'the look to spawn with. Default = the creature\'s default look (set on the Creatures tab; the row follows it when it changes); a code picked here pins the row to that look' },
    { key: 'stats', label: 'Overrides', type: 'overrides', help: 'stat overrides for this row\'s creatures (every key optional)' },
  ];

  // ------------------------------------------------------------------ waves
  const wave = [
    { key: 'name', label: 'Name', type: 'text', help: 'a label for the editor and the hand-back notes; the game never shows it' },
    { key: 'id', label: 'Id', type: 'text', help: 'a short unique id (the editor fills one in)' },
    { key: 't', label: 'From', type: 'seconds', int: true, min: 0, required: true, help: 'the run second of the first burst' },
    { key: 'until', label: 'Until', type: 'seconds', int: true, min: 0, help: 'no burst after this run second; empty = no end (the count ends it, or nothing does)' },
    { key: 'count', label: 'Total count', type: 'int', min: 0, def: 20, help: 'how many creatures in all; 0 = no total (runs until `until`)' },
    { key: 'burst', label: 'Per burst', type: 'int', min: 1, def: 5, help: 'how many spawn together in each burst' },
    { key: 'every', label: 'Every (s)', type: 'number', min: 0, step: 0.5, def: 2, help: 'seconds between bursts' },
    { key: 'pattern', label: 'Pattern', type: 'select', options: PATTERNS, def: 'pack', help: 'packs at one point each, scattered, one at a time, a ring round the hero (the whole burst at once, 11.7 m out) or in front (from the top of the screen, whatever the spawn side in Settings says)' },
    { key: 'respect_cap', label: 'Respect the cap', type: 'bool', def: true, help: 'on: a burst spawns only into free cap room; off: on top of the cap like a SWARM (the hard cap still holds)' },
    { key: 'channel', label: 'Channel', type: 'select', options: CHANNELS, def: 'regular', help: 'which cap the burst counts against when it respects one' },
    { key: 'elite', label: 'Elite modifier', type: 'elite', def: '', help: 'every creature of the wave wears this modifier: none, random, or one by name (waits for colour_after_kills)' },
    { key: 'toast', label: 'Banner', type: 'text', help: 'a banner shown at the first burst, like "SWARM!"; empty = none' },
    { key: 'alts', label: 'Alternatives', type: 'alts', help: 'one of these is rolled once per wave per run (fresh every run) by its chance; with none, the wave carries one creature itself' },
  ];
  // the one creature a wave without `alts` carries itself (= one alternative)
  const alt = [
    { key: 'chance', label: 'Chance', type: 'percent', def: 1, help: 'its share of the roll (the chances are normalised: 50 / 50 or 1 / 1 both mean half)' },
    { key: 'enemy', label: 'Creature', type: 'enemy', required: true, help: 'the creature' },
    { key: 'variant', label: 'Art variant', type: 'variant', help: 'the look; Default = the creature\'s default look (the Creatures tab), a code pins this alternative to that look' },
    { key: 'pack', label: 'Pack', type: 'int', min: 1, help: 'how many of a burst stand together; a burst bigger than the pack is several packs; empty = the creature\'s pack size' },
    { key: 'stats', label: 'Overrides', type: 'overrides', help: 'stat overrides for this alternative\'s creatures' },
  ];

  // ------------------------------------------------------------------ events
  const EVENT_TYPES = {
    boss: { label: 'Boss', glyph: 'skull', color: '#e66767', help: 'the stage boss on the flats: the clock stops, the crowd drops to boss_cap_frac, a portal opens when it dies' },
    elite_boss: { label: 'Elite', glyph: 'crown', color: '#e6a04a', help: 'a mini-boss creature near the hero (one of the list at random), no clock stop; always drops a chest' },
    elite: { label: 'Coloured elite', glyph: 'star', color: '#c98500', help: 'one roster creature wearing an elite modifier (random creature / modifier when empty; the creature by the rows\' elite_weight); waits for colour_after_kills' },
    elite_every: { label: 'Elites every', glyph: 'repeat', color: '#9085e9', help: 'from t, a coloured elite every `interval` seconds (a fresh random interval each time when [min, max]) for the rest of the run' },
    swarm: { label: 'Swarm', glyph: 'ring', color: '#46d39a', help: '`count` creatures at once, on top of the cap (a SWARM! banner): a ring 16 m round the hero, packs or singles through the spawn points, or all from the top of the screen (Pattern). Pass 69: Special on = every one comes as its coloured special, no banner (Red Canyon\'s special Goblin at 2:00 is one, Count 1)' },
  };
  const event = [
    { key: 'type', label: 'Type', type: 'select', options: Object.keys(EVENT_TYPES).map((k) => ({ v: k, label: EVENT_TYPES[k].label, help: EVENT_TYPES[k].help })), required: true, help: 'what happens' },
    { key: 'name', label: 'Name', type: 'text', help: 'a label for the editor; the game shows the creature\'s own name' },
    { key: 't', label: 'At', type: 'seconds', int: true, min: 0, required: true, help: 'the run second it fires' },
    { key: 'enemy', label: 'Creature(s)', type: 'enemies', help: 'one creature, or a list drawn at random with optional weights; empty on a coloured elite = a random roster creature, on a swarm = the map\'s walker' },
    { key: 'mod', label: 'Modifier', type: 'elite', def: '', only: ['elite'], help: 'the elite modifier; empty = a random one' },
    { key: 'interval', label: 'Interval (s)', type: 'interval', only: ['elite_every'], def: 90, help: 'seconds between coloured elites: one number, or min and max for a fresh random interval each time' },
    { key: 'count', label: 'Count', type: 'int', min: 1, def: 40, only: ['swarm'], help: 'how many come at once' },
    { key: 'pattern', label: 'Pattern', type: 'select', options: SWARM_PATTERNS, def: 'ring', only: ['swarm'], help: 'the swarm\'s own ring 16 m round the hero, packs / singles through the spawn points, or all from the top of the screen (in front)' },
    // pass 69 (lane EN; Garry: "a moment ... where a single 'Special' regular Goblin appears at the end of the first wave")
    { key: 'special', label: 'Special', type: 'bool', def: false, only: ['swarm'], help: 'on: every creature this swarm brings comes as its coloured special for sure (its Special block on the Enemies tab: size, HP ×, ATK ×, XP ×, colour, glow), even before Colour after kills, and no SWARM! banner shows. Count 1 = one special creature at that second. A creature with no variance block has no special and comes plain' },
    { key: 'chance', label: 'Chance', type: 'percent', def: 1, help: 'the chance the event happens at all, rolled per run (100 = always)' },
    { key: 't_jitter', label: 'Jitter (± s)', type: 'number', min: 0, step: 1, def: 0, help: 'the time moves by up to this many seconds either way, rolled per run' },
    { key: 'variant', label: 'Art variant', type: 'variant', help: 'the look of what it spawns; Default = each creature\'s default look (the Creatures tab), a code pins it' },
    { key: 'stats', label: 'Overrides', type: 'overrides', help: 'stat overrides for what it spawns' },
  ];

  // ------------------------------------------------------------------ stat overrides
  // `ph` names the creature's own value for the placeholder (a function of the creature record and the timeline).
  const n = (c, k) => (c && c[k] != null ? c[k] : '');
  const sub = (c, blk, k) => (c && c[blk] && c[blk][k] != null ? c[blk][k] : '');
  const sub2 = (c, blk, blk2, k) => (c && c[blk] && c[blk][blk2] && c[blk][blk2][k] != null ? c[blk][blk2][k] : '');
  const OVERRIDES = [
    // pass 58 (R1): the grey number is the row's own HP, the creature's × the HP curve at the row's start, fixed for the
    // row's whole life; the inspector fills it in (the `ph` here is the creature's plain number, for the other uses)
    { path: 'hp', group: 'Body', label: 'HP', type: 'number', min: 0, ph: (c) => n(c, 'hp'), help: 'the row\'s health. Empty = the creature\'s own × the HP curve at the row\'s start (the grey number: it follows the bar when you move it), fixed for all the row\'s creatures; a number typed here takes no curve. The stage multiplier, creature_hp_mult and the hero level come on top in the game' },
    { path: 'hp_mult', group: 'Body', label: 'HP ×', type: 'number', min: 0, step: 0.1, ph: () => 1, help: 'multiplies the health (stacks on hp)' },
    { path: 'damage', group: 'Body', label: 'Damage', type: 'number', min: 0, ph: (c) => n(c, 'damage'), help: 'a bite\'s damage (ranged shots use their own). Empty = the creature\'s own × the damage curve at the row\'s start (the grey number), fixed for the row\'s creatures and every hit they deal; a number typed here takes no curve' },
    { path: 'damage_mult', group: 'Body', label: 'Damage ×', type: 'number', min: 0, step: 0.1, ph: () => 1, help: 'multiplies the damage' },
    { path: 'speed', group: 'Body', label: 'Speed', type: 'number', min: 0, step: 0.1, ph: (c) => n(c, 'speed'), help: 'move speed in m/s (before move_pace)' },
    { path: 'speed_mult', group: 'Body', label: 'Speed ×', type: 'number', min: 0, step: 0.1, ph: () => 1, help: 'multiplies the move speed' },
    // pass 58 (R2, Garry: "editable as a kind of a range (between 3-5 for example) and there should be the default one
    // already set for them so I have a reference"): one number, or a range each creature rolls its own size in
    { path: 'size', group: 'Body', label: 'Size (m)', type: 'size_range', min: 0.05, step: 0.05, ph: (c) => n(c, 'size'), help: 'the painting\'s height in metres: one number (the variance\'s size spread still on top, the body\'s radius unchanged), or from / to: each creature rolls its own size in the range instead of the spread, and its collision radius follows its size (radius × size / its own size) unless Radius is set; a coloured special grows by its size factor but never past the range\'s top, an elite-modified one takes its modifier\'s scale on top. A list of one size written by hand ([2]) is every creature exactly that size, no spread, its radius following (the game reads it as a range). The grey numbers are the creature\'s own size and its spread' },
    { path: 'radius', group: 'Body', label: 'Radius', type: 'number', min: 0.05, step: 0.05, ph: (c) => n(c, 'radius'), help: 'the body\'s collision radius in metres' },
    { path: 'damage_reduction', group: 'Body', label: 'Damage reduction', type: 'number', min: 0, max: 0.95, step: 0.05, ph: (c) => n(c, 'damage_reduction'), help: 'the share of every hit it shrugs off (0.25 = a quarter less)' },
    { path: 'knockback', group: 'Body', label: 'Knockback (m/s)', type: 'number', min: 0, step: 0.5, ph: (c) => (c ? App.knockbackOf(c) : ''), help: 'the shove the hero takes from a bite, in m/s; the grey number is the creature\'s own, or the game\'s default from its damage: clamp(3.4 × √(damage / 4), 2.5, 7) (a 4-damage bite shoves 3.4). A shot without its own knockback shoves 0.7 of it' },
    { path: 'knockback_mult', group: 'Body', label: 'Knockback ×', type: 'number', min: 0, step: 0.1, ph: () => 1, help: 'multiplies the bite\'s knockback and the charge, ranged, kamikaze and boss-attack knockback' },
    // pass 67 (Garry: the Hammer Giant "should take 1/3 of the knockback"): the other direction, what the creature shrugs off
    { path: 'knockback_resist', group: 'Body', label: 'Knockback resist', type: 'number', min: 0, max: 1, step: 0.05, ph: (c) => n(c, 'knockback_resist'), help: 'the share of every shove from the hero\'s side (a hit\'s knockback, a blast\'s throw, the Lasso\'s pull, Buck\'s Ram) this row\'s creatures shrug off, 0..1 (1 = never moved); the other way round from Knockback above, which is the shove they give the hero. The grey number is the creature\'s own (the Hammer Giant 0.67 = a third of the push)' },
    // pass 58 (R3, Garry: "I want a version that kind of colours all the enemies that come out of that wave. I'd like a
    // colour slider and a preview showing the actual enemy")
    { path: 'tint', group: 'Colour', label: 'Colour range', type: 'tint', help: 'every creature of this row rolls a hue in the range (from → to on the colour wheel; a range whose end is below its start runs through red) and is washed with that colour at this strength, the saturation and brightness as set. It replaces the creature\'s own random tints (Elite group). A coloured special of this row (once Colour after kills is reached) is a darker, stronger shade of the hue it rolled: saturation +0.15, brightness ×0.7, at the larger of Amount and its own tint strength, +0.15 (the last picture). An elite modifier\'s colour and burn, poison and freeze still show over it. On from the first creature (not held back by Colour after kills)' },
    { path: 'contact_cd', group: 'Attacks', label: 'Bite every (s)', type: 'number', min: 0.05, step: 0.05, ph: (c) => n(c, 'contact_cd'), help: 'seconds between bites (the creature\'s default 0.6)' },
    { path: 'attack_rate_mult', group: 'Attacks', label: 'Attack rate ×', type: 'number', min: 0.1, step: 0.1, ph: () => 1, help: '2 = attacks twice as often: divides ranged / charge cooldowns, the kamikaze wind-up, boss cooldowns and the bite time' },
    { path: 'projectile_speed_mult', group: 'Attacks', label: 'Projectile speed ×', type: 'number', min: 0.1, step: 0.1, ph: () => 1, help: 'multiplies the shots\' speed (ranged, artillery missiles, boss attacks)' },
    { path: 'ranged.cooldown', group: 'Ranged', label: 'Cooldown (s)', type: 'number', min: 0.1, step: 0.1, ph: (c) => sub(c, 'ranged', 'cooldown'), help: 'seconds between shots', needs: 'ranged' },
    { path: 'ranged.projectile_speed', group: 'Ranged', label: 'Projectile speed', type: 'number', min: 0.1, step: 0.5, ph: (c) => sub(c, 'ranged', 'projectile_speed'), help: 'the shot\'s speed in m/s', needs: 'ranged' },
    { path: 'ranged.range', group: 'Ranged', label: 'Range (m)', type: 'number', min: 0.5, step: 0.5, ph: (c) => sub(c, 'ranged', 'range'), help: 'how far it shoots from', needs: 'ranged' },
    { path: 'charge.cooldown', group: 'Charge', label: 'Cooldown (s)', type: 'number', min: 0.1, step: 0.1, ph: (c) => sub(c, 'charge', 'cooldown'), help: 'seconds between charges', needs: 'charge' },
    { path: 'charge.speed', group: 'Charge', label: 'Charge speed', type: 'number', min: 0.5, step: 0.5, ph: (c) => sub(c, 'charge', 'speed'), help: 'the charge\'s speed in m/s', needs: 'charge' },
    { path: 'pack', group: 'Spawning', label: 'Pack', type: 'int', min: 1, ph: (c) => n(c, 'pack_size'), help: 'the pack size (the row / alt field wins when both are set)' },
    { path: 'max_alive', group: 'Spawning', label: 'Max alive', type: 'int', min: 0, ph: (c) => n(c, 'max_alive'), help: 'never more than this many alive (0 = no limit); counts every type of the id' },
    { path: 'cap_share', group: 'Spawning', label: 'Cap share', type: 'number', min: 0.05, step: 0.05, ph: (c) => n(c, 'cap_share'), help: 'how much of a cap slot one takes (0.5 = two to a slot)' },
    { path: 'xp_mult', group: 'Spawning', label: 'XP ×', type: 'number', min: 0, step: 0.1, ph: (c) => n(c, 'xp_mult'), help: 'the gems it pays and how hard its kill counts for power-ups' },
    { path: 'can_be_elite', group: 'Spawning', label: 'Can be elite', type: 'bool3', ph: (c) => (c ? (c.can_be_elite ? 'yes' : 'no') : ''), help: 'whether a coloured elite modifier may land on it' },
    { path: 'drops.small', group: 'Drops', label: 'Small gem', type: 'number', min: 0, max: 1, step: 0.05, ph: (c) => sub(c, 'drops', 'small'), help: 'chance of a small gem' },
    { path: 'drops.medium', group: 'Drops', label: 'Medium gem', type: 'number', min: 0, max: 1, step: 0.05, ph: (c) => sub(c, 'drops', 'medium'), help: 'chance of a medium gem' },
    { path: 'drops.large', group: 'Drops', label: 'Large gem', type: 'number', min: 0, max: 1, step: 0.05, ph: (c) => sub(c, 'drops', 'large'), help: 'chance of a large gem' },
    { path: 'drops.gold', group: 'Drops', label: 'Coin', type: 'number', min: 0, max: 1, step: 0.01, ph: (c) => sub(c, 'drops', 'gold'), help: 'chance of a coin' },
    { path: 'drops.chest', group: 'Drops', label: 'Chest', type: 'number', min: 0, max: 1, step: 0.001, ph: (c) => sub(c, 'drops', 'chest'), help: 'chance of a chest (Elites and bosses always drop one)' },
    { path: 'drops.pickup.id', group: 'Drops', label: 'Own power-up', type: 'pickup', ph: (c) => (c && c.drops && c.drops.pickup ? c.drops.pickup.id : ''), help: 'a power-up this creature itself may drop (the hammer giant\'s Berserk)' },
    { path: 'drops.pickup.chance', group: 'Drops', label: 'Own power-up chance', type: 'number', min: 0, max: 1, step: 0.01, ph: (c) => (c && c.drops && c.drops.pickup ? c.drops.pickup.chance : ''), help: 'its chance per kill' },
    { path: 'pickup_chance_mult', group: 'Power-ups', label: 'Power-up chance ×', type: 'number', min: 0, step: 0.1, ph: () => 1, help: 'scales the timeline\'s per_kill chance for this creature\'s kills' },
    { path: 'pickup_weights', group: 'Power-ups', label: 'Power-up weights', type: 'pickup_weights', help: 'replaces the timeline\'s power-up roster for its kills: one weight per power-up, missing = never dropped' },
    // pass 54: the Elite group is the variance block (the coloured specials) plus the random-Elite draw
    { path: 'variance.size', group: 'Elite', label: 'Size spread', type: 'number', min: 0, max: 0.9, step: 0.05, ph: (c) => sub(c, 'variance', 'size'), help: 'each one comes ×(1 ± this) tall: 0.2 = from 0.8 to 1.2 of its size' },
    { path: 'variance.speed', group: 'Elite', label: 'Speed spread', type: 'number', min: 0, max: 0.9, step: 0.05, ph: (c) => sub(c, 'variance', 'speed'), help: 'each one moves ×(1 ± this): 0.15 = from 0.85 to 1.15 of its speed' },
    { path: 'variance.tints', group: 'Elite', label: 'Tints', type: 'swatches', ph: (c) => (c && c.variance && Array.isArray(c.variance.tints) ? c.variance.tints : ''), help: 'the colours an ordinary one may be washed with (one at random, after colour_after_kills); a list here replaces the creature\'s whole list' },
    { path: 'variance.tint_strength', group: 'Elite', label: 'Tint strength', type: 'number', min: 0, max: 1, step: 0.05, ph: (c) => sub(c, 'variance', 'tint_strength'), help: 'how strongly the tint shows (0 = none, 1 = the colour flat)' },
    { path: 'variance.special_chance', group: 'Elite', label: 'Special chance', type: 'number', min: 0, max: 1, step: 0.01, ph: (c) => sub(c, 'variance', 'special_chance'), help: 'the chance one comes as a coloured special (×(1 + the hero\'s difficulty) with Hot Sauce), after colour_after_kills; 0.12 = about one in eight' },
    { path: 'variance.special.size', group: 'Elite', label: 'Special size ×', type: 'number', min: 0.1, step: 0.1, ph: (c) => sub2(c, 'variance', 'special', 'size'), help: 'a special is this much taller (pass 72: the game\'s default 1.5)' },
    { path: 'variance.special.hp', group: 'Elite', label: 'Special HP ×', type: 'number', min: 0.1, step: 0.1, ph: (c) => sub2(c, 'variance', 'special', 'hp'), help: 'a special has this much more health (pass 72: default 15)' },
    { path: 'variance.special.damage', group: 'Elite', label: 'Special damage ×', type: 'number', min: 0.1, step: 0.1, ph: (c) => sub2(c, 'variance', 'special', 'damage'), help: 'a special bites this much harder (pass 69: default 2)' },
    { path: 'variance.special.xp', group: 'Elite', label: 'Special XP ×', type: 'number', min: 0.1, step: 0.1, ph: (c) => sub2(c, 'variance', 'special', 'xp'), help: 'a special pays this much more XP (default 2)' },
    { path: 'variance.special.tint', group: 'Elite', label: 'Special tint', type: 'swatch', ph: (c) => sub2(c, 'variance', 'special', 'tint'), help: 'the special\'s colour (the dark saturated wash that marks it); in a row with a Colour range the special takes a darker shade of the hue it rolled instead' },
    { path: 'variance.special.tint_strength', group: 'Elite', label: 'Special tint strength', type: 'number', min: 0, max: 1, step: 0.05, ph: (c) => sub2(c, 'variance', 'special', 'tint_strength'), help: 'how strongly the special\'s colour shows (default 0.6); in a row with a Colour range its shade shows at the larger of this and Amount, +0.15' },
    // pass 69 (lane EN): the special's emissive rim
    { path: 'variance.special.glow', group: 'Elite', label: 'Special glow', type: 'number', min: 0, max: 1, step: 0.05, ph: (c) => sub2(c, 'variance', 'special', 'glow'), help: 'the emissive rim round a special in its colour, 0 = none, 1 = widest and brightest (pass 69; empty = the creature\'s own, else the map\'s Coloured specials default, else 0.6)' },
    { path: 'variance.special.chest_chance', group: 'Elite', label: 'Special chest chance', type: 'number', min: 0, max: 1, step: 0.05, ph: (c) => sub2(c, 'variance', 'special', 'chest_chance'), help: 'the chance a special\'s death drops a chest (pass 72; empty = the creature\'s own, else the map\'s Coloured specials default, else 0.35)' },
    { path: 'elite_weight', group: 'Elite', label: 'Elite weight', type: 'number', min: 0, step: 0.5, ph: () => 1, help: 'this row\'s weight when a coloured-elite event with no creature named draws one from the open rows (0 = never, like Can be elite = no; every row 1 = an even draw)' },
    { path: 'elite_formats.single', group: 'Elite', label: 'Comes alone', type: 'number', min: 0, step: 0.5, ph: () => 1, help: 'chance a coloured elite drawn from this row arrives on its own (the three chances are normalised: 1 / 1 / 0 = half and half)' },
    { path: 'elite_formats.pack', group: 'Elite', label: 'Comes as its pack', type: 'number', min: 0, step: 0.5, ph: () => 0, help: 'chance it arrives as its whole pack, every one wearing the modifier' },
    { path: 'elite_formats.ring', group: 'Elite', label: 'Comes as a ring', type: 'number', min: 0, step: 0.5, ph: () => 0, help: 'chance it arrives as a ring of `pack` of them 12 m round the hero, every one wearing the modifier' },
    { path: 'elite.hp_mult_per_stage', group: 'Mini-boss (Elite archetype only)', label: 'Elite HP × per stage', type: 'number', min: 0, step: 0.1, ph: (c) => sub(c, 'elite', 'hp_mult_per_stage') || 1.8, help: 'an Elite-archetype creature\'s health multiplier for every stage after the first (the game\'s default 1.8); its health is hp × this^stage × the stage multiplier × creature_hp_mult, with no time or level factor', onlyIf: (c) => !c || c.archetype === 'elite', onlyNote: 'only an Elite-archetype creature (a mini-boss: the Dune Scorpion, the Sun Prophet, the Stone Golem) reads this' },
    { path: 'boss.hp_mult_per_stage', group: 'Boss', label: 'Boss HP × per stage', type: 'number', min: 0, step: 0.1, ph: (c) => sub(c, 'boss', 'hp_mult_per_stage'), help: 'a boss\'s health multiplier for every stage after the first', needs: 'boss' },
    { path: 'boss.cooldown_between', group: 'Boss', label: 'Seconds between attacks', type: 'number', min: 0.1, step: 0.1, ph: (c) => sub(c, 'boss', 'cooldown_between'), help: 'the pause between a scripted creature\'s attacks', needs: 'boss' },
    { path: 'boss.attacks', group: 'Boss', label: 'Attacks', type: 'attacks', help: 'untick an attack to take it out of the creature\'s script (true keeps it; an unknown name adds nothing)', needs: 'boss' },
  ];
  const OVERRIDE_GROUPS = ['Body', 'Colour', 'Attacks', 'Ranged', 'Charge', 'Spawning', 'Drops', 'Power-ups', 'Elite', 'Mini-boss (Elite archetype only)', 'Boss'];
  // what each override group is, for the legend and the Instructions tab (pass 54)
  const OVERRIDE_GROUP_HELP = {
    Colour: 'pass 58: wash every creature of this row in a colour from a range, each its own hue; the pictures are its standing frame as the game tints it',
    Elite: 'the variance block: the size and speed spread, the tints, the coloured specials and their numbers, merged over the creature\'s own block (a tint list replaces the whole list); plus how a random coloured elite is drawn from this row and how it arrives',
    'Mini-boss': 'Elite archetype only: the three mini-bosses\' own health rule',
  };

  // ------------------------------------------------------------------ the timeline's scalars (Settings)
  const SCALARS = [
    { key: 'stage_length', group: 'Stages', label: 'Stage length (s)', type: 'seconds', int: true, min: 10, def: 300, help: 'seconds of run clock in each stage; stage 2 starts here, stage 3 at twice it (Red Canyon 430 = 7:10)' },
    { key: 'stages', group: 'Stages', label: 'Stages', type: 'int', min: 1, max: 9, def: 3, help: 'how many stages before endless begins' },
    { key: 'stage_mults', group: 'Stages', label: 'Stage multipliers', type: 'list', def: [1.0, 1.35, 1.8], help: 'creature HP, damage and gold × per stage (first = stage 1); endless continues from the last' },
    { key: 'speed_per_stage', group: 'Stages', label: 'Speed per stage', type: 'number', min: 0, step: 0.05, def: 0, help: 'extra creature speed for every stage after the first (0.1 = +10% a stage)' },
    { key: 'cap_per_stage', group: 'Stages', label: 'Cap per stage', type: 'int', min: 0, def: 0, help: 'extra live cap for every stage after the first (stage 3 = twice this)' },
    { key: 'hell_cap', group: 'Stages', label: 'Hell cap per stage', type: 'list', def: [], help: 'the hell channel\'s cap as a share of the regular cap, per stage (0 = its rows never spawn on that stage)' },
    { key: 'cap_curve', group: 'Cap', label: 'Cap curve', type: 'points', def: [], help: 'the control points of the live cap curve (how many creatures may be alive) as [seconds, cap]: linear between them, flat before the first and after the last. They are not spawn events: the director spawns up to the cap on its own interval. Replaces the straight line below when set' },
    { key: 'cap_start', group: 'Cap', label: 'Cap start', type: 'int', min: 0, def: 100, help: 'the straight-line cap\'s start (used only while the curve is empty)' },
    { key: 'cap_per_minute', group: 'Cap', label: 'Cap per minute', type: 'number', min: 0, step: 0.5, def: 10, help: 'the straight-line cap\'s growth per minute (used only while the curve is empty)' },
    { key: 'cap_max', group: 'Cap', label: 'Cap max', type: 'int', min: 1, def: 250, help: 'the live cap never goes above this' },
    { key: 'hard_cap', group: 'Cap', label: 'Hard cap (bodies)', type: 'int', min: 1, def: 300, help: 'a count of bodies no spawn ever crosses: swarms and no-cap waves included' },
    { key: 'boss_cap_frac', group: 'Cap', label: 'Boss fight cap share', type: 'number', min: 0, max: 1, step: 0.05, def: 0.3, help: 'the crowd kept up during a boss fight, as a share of the cap' },
    { key: 'burst_min', group: 'Spawning', label: 'Burst min', type: 'int', min: 1, def: 5, help: 'a roster burst\'s least size, in cap load units (the fodder counts half)' },
    { key: 'burst_max', group: 'Spawning', label: 'Burst max', type: 'int', min: 1, def: 20, help: 'a roster burst\'s largest size, as far as the cap has room' },
    { key: 'spawn_interval', group: 'Spawning', label: 'Spawn check every (s)', type: 'number', min: 0.1, step: 0.1, def: 0.5, help: 'seconds between the director\'s spawn checks' },
    // pass 54: where the roster bursts and the waves come from
    { key: 'spawn_sides.mode', group: 'Spawning', label: 'Spawn side', type: 'select', options: SIDE_MODES, def: 'facing', block: 'spawn_sides', help: 'where roster bursts and waves come from: a screen side by the four weights, or (the old rule) mostly where the hero faces. Rings, swarms, the portal wave, bosses and Elite bosses are placed as before' },
    { key: 'spawn_sides.top', group: 'Spawning', label: 'Top (north)', type: 'int', min: 0, def: 0, block: 'spawn_sides', help: 'the weight of the top of the screen (north, away from the camera): Red Canyon 55 of 100' },
    { key: 'spawn_sides.bottom', group: 'Spawning', label: 'Bottom (south)', type: 'int', min: 0, def: 0, block: 'spawn_sides', help: 'the weight of the bottom of the screen (towards the camera): Red Canyon 15' },
    { key: 'spawn_sides.left', group: 'Spawning', label: 'Left (west)', type: 'int', min: 0, def: 0, block: 'spawn_sides', help: 'the weight of the left side: Red Canyon 15' },
    { key: 'spawn_sides.right', group: 'Spawning', label: 'Right (east)', type: 'int', min: 0, def: 0, block: 'spawn_sides', help: 'the weight of the right side: Red Canyon 15 (all four 0 = the facing rule)' },
    { key: 'spawn_sides.facing_share', group: 'Spawning', label: 'Facing share', type: 'percent', def: 0.7, block: 'spawn_sides', help: 'in the facing mode: the share of spawns that come from where the hero faces (the rest anywhere round him)' },
    { key: 'spawn_sides.facing_spread_deg', group: 'Spawning', label: 'Facing spread (°)', type: 'number', min: 1, max: 180, step: 5, def: 60, block: 'spawn_sides', help: 'in the facing mode: how far either side of the hero\'s facing those spawns may land' },
    { key: 'weight_late_t', group: 'Spawning', label: 'Weights are late at (s)', type: 'seconds', int: true, min: 0, def: 600, help: 'legacy: the run second an old-shape row (weight → weight_late) has slid by. Rows with presence keyframes carry their own times and ignore it; the editor converts old rows on load' },
    { key: 'colour_after_kills', group: 'Spawning', label: 'Colour after kills', type: 'int', min: 0, def: 0, help: 'kills before tints, variance specials and elite modifiers may appear (0 = at once)' },
    { key: 'portal_cap', group: 'Portal', label: 'Portal cap', type: 'int', min: -1, def: 10, help: 'load kept up while the portal waits: -1 = the stage-end cap, 0 = nothing; ignored when the portal wave has a count' },
    { key: 'portal_spawn_seconds', group: 'Portal', label: 'Portal spawns for (s)', type: 'number', min: -1, step: 1, def: 30, help: 'how long after the boss dies the portal cap still spawns; -1 = for as long as the portal waits' },
    { key: 'portal_wave.count', group: 'Portal', label: 'Portal wave count', type: 'int', min: 0, def: 0, help: 'one wave of this many roster creatures round the hero as the portal opens, then nothing until he steps through (0 = off)' },
    { key: 'hp_curve', group: 'Scaling', label: 'HP × over time', type: 'curve', def: {}, help: 'the multiplier on every creature\'s health over the run clock (the HP × lane): manual points, or a formula sampled onto the line. Since pass 58 each row (wave, event) reads it once, at its start, and keeps that for all its creatures (the Actual HP × lane shows what that makes). Absent = the legacy hp_growth / hp_power pair below' },
    { key: 'damage_curve', group: 'Scaling', label: 'ATK × over time', type: 'curve', def: {}, help: 'the multiplier on every creature\'s damage over the run clock (the ATK × lane), read once at each row\'s start like the HP curve (pass 58); absent = 1 all run' },
    { key: 'hp_growth', group: 'Scaling', label: 'HP growth per minute (legacy)', type: 'number', min: 0, step: 0.005, def: 0.08, help: 'legacy (used only when hp_curve is absent): creature HP × (1 + growth × minutes)^power on the run clock' },
    { key: 'hp_power', group: 'Scaling', label: 'HP growth power (legacy)', type: 'number', min: 0, step: 0.05, def: 1.2, help: 'legacy (used only when hp_curve is absent): the exponent of the HP growth' },
    { key: 'creature_hp_mult', group: 'Scaling', label: 'Creature HP ×', type: 'number', min: 0, step: 0.05, def: 1, help: 'a multiplier on every creature\'s health, never a boss (1 = as its JSON says)' },
    { key: 'creature_damage_mult', group: 'Scaling', label: 'Creature damage ×', type: 'number', min: 0, step: 0.05, def: 1, help: 'multiplies every hostile damage: bites, shots, spit, artillery missiles, kamikaze blasts, death bursts, boss and caster attacks, the Brander\'s ring (1 = as the JSON says; Red Canyon 1.25)' },
    // pass 60: the creatures' own pace knob (move_pace below is everyone's, the hero included)
    { key: 'creature_speed_mult', group: 'Scaling', label: 'Creature speed ×', type: 'number', min: 0.1, step: 0.05, def: 1, help: 'every creature, Elite and boss moves, winds up and shoots at this multiple; the hero is not affected (1 = as the JSON says; Red Canyon 0.9 = 10% slower, wind-ups 1/0.9 as long)' },
    // pass 72 (lane ITEMS): the hero's pushes on the creatures (EnemyManager.hero_knock_mult)
    { key: 'hero_knockback_mult', group: 'Scaling', label: 'Hero knockback ×', type: 'number', min: 0, step: 0.05, def: 0.5, help: 'multiplies every push the hero\'s side gives a creature: every weapon, mutation, evolution, line, passive and perk hit (the ball, the frisbee, thorns and the revive too), the Nuke\'s, Thruster Burst\'s and Grand Finale\'s throws, Buck\'s Ram, the tornado\'s toss, the Guitarra\'s bounce and Bucking Bronco\'s throw distance. Never a creature\'s push on the hero, a hostile blast throwing the crowd, the pull, a creature\'s knockback resist or a stun (1 = as each item\'s JSON says; Red Canyon 0.5 = half, so a knockback build slows the crowd but cannot hold it off; empty = the game\'s 0.5)' },
    { key: 'level_hp_per_level', group: 'Scaling', label: 'HP per hero level', type: 'number', min: 0, step: 0.01, def: 0, help: 'creatures gain this share of HP per hero level above 1' },
    { key: 'level_damage_per_level', group: 'Scaling', label: 'Damage per hero level', type: 'number', min: 0, step: 0.01, def: 0, help: 'creatures gain this share of damage per hero level above 1' },
    { key: 'contact_cap', group: 'Scaling', label: 'Contact cap', type: 'number', min: 0, max: 1, step: 0.01, def: 0, help: 'a cap on one touch\'s damage as a share of the hero\'s max HP (0 = off; never a boss)' },
    { key: 'move_pace', group: 'Scaling', label: 'Move pace', type: 'number', min: 0.1, step: 0.05, def: 1, help: 'everyone\'s speed (hero and creatures): 0.8 = 20% slower, wind-ups last 1/pace as long' },
    { key: 'xp_need_mult', group: 'Scaling', label: 'XP needed ×', type: 'number', min: 0.1, step: 0.05, def: 1, help: 'every hero level needs this many times the XP curve\'s amount' },
    { key: 'endless_wave_seconds', group: 'Endless', label: 'Endless wave (s)', type: 'number', min: 1, step: 1, def: 60, help: 'in endless, a new wave this often' },
    { key: 'endless_wave_mult', group: 'Endless', label: 'Endless wave ×', type: 'number', min: 1, step: 0.01, def: 1, help: 'every endless wave multiplies the creatures by this, compounding' },
    { key: 'weapon_cap', group: 'Items', label: 'Weapon slots per stage', type: 'list', int: true, def: [5, 5, 5], help: 'weapon slots per stage (static since pass 47: 5)' },
    { key: 'passive_cap', group: 'Items', label: 'Line slots per stage', type: 'list', int: true, def: [5, 5, 5], help: 'line slots per stage (static since pass 47: 5)' },
    { key: 'path_times', group: 'Items', label: 'Path offers per stage', type: 'path_times', def: [], help: 'seconds into each stage when a weapon\'s whole path goes on the table (one list per stage; the last holds for later stages)' },
    // pass 69 (lane EN): the map's numbers for a coloured special that the creature's own Special block leaves empty
    // (EnemyDef.special_value: the creature's own, then these, then the game's)
    { key: 'special_defaults.size', group: 'Coloured specials', label: 'Size ×', type: 'number', min: 0.1, step: 0.05, def: 1.5, help: 'a coloured special\'s size factor for every creature whose Special block leaves Size empty (empty here = the game\'s 1.5; pass 72, was 1.25)' },
    { key: 'special_defaults.hp', group: 'Coloured specials', label: 'HP ×', type: 'number', min: 0.1, step: 0.5, def: 15, help: 'its health factor where the creature leaves it empty (empty = the game\'s 15; pass 72, was 10)' },
    { key: 'special_defaults.damage', group: 'Coloured specials', label: 'ATK ×', type: 'number', min: 0.1, step: 0.1, def: 2, help: 'its damage factor where the creature leaves it empty (empty = the game\'s 2)' },
    { key: 'special_defaults.xp', group: 'Coloured specials', label: 'XP ×', type: 'number', min: 0, step: 0.5, def: 2, help: 'its XP factor where the creature leaves it empty (empty = the game\'s 2)' },
    { key: 'special_defaults.tint_strength', group: 'Coloured specials', label: 'Colour strength', type: 'number', min: 0, max: 1, step: 0.05, def: 0.6, help: 'how strongly its colour shows where the creature leaves it empty (empty = the game\'s 0.6)' },
    { key: 'special_defaults.glow', group: 'Coloured specials', label: 'Glow', type: 'number', min: 0, max: 1, step: 0.05, def: 0.6, help: 'the emissive rim round every coloured special whose creature leaves Glow empty: 0 = none, 1 = widest (empty = the game\'s 0.6). Every creature in play leaves it empty, so this is the one knob for all of them' },
    // pass 72 (lane SPEC; Garry: specials "should have way more of a chance of dropping a box ... a limit to how many of them
    // are there"): the chest a special's death drops, and how many may live at once (EnemyDef.SPECIAL_MAX_ALIVE)
    { key: 'special_defaults.chest_chance', group: 'Coloured specials', label: 'Chest chance', type: 'number', min: 0, max: 1, step: 0.05, def: 0.35, help: 'the chance a coloured special\'s death drops a chest, for every creature whose Special block leaves Chest chance empty (empty here = the game\'s 0.35, about one in three; 0 = never). On top of anything else the kill pays (Hot Sauce\'s chest rolls apart)' },
    { key: 'special_defaults.max_alive', group: 'Coloured specials', label: 'Max alive', type: 'int', min: 0, step: 1, def: 3, help: 'the most coloured specials alive at once on this map: a roll that would make one more makes a plain creature instead; a swarm event set to Special still brings its special. 0 = no limit (empty = the game\'s 3). Why a limit: x15 HP each, a crowd of 250 at 0.04 would carry ten of them late in a stage' },
    { key: 'structures.count', group: 'World', label: 'Structures', type: 'int', min: 0, def: 0, help: 'structures scattered at the run\'s start' },
    { key: 'structures.min_spacing', group: 'World', label: 'Structure spacing (m)', type: 'number', min: 0, step: 1, def: 16, help: 'the least metres between two structures' },
    // pass 72 (lane BOSS; Garry: "Boss HP should be pegged to Player DPS ... It shouldn't be 1 to 1"): the boss's HP times
    // (DPS / its reference) ^ exponent, held between min and max (WaveTimeline.boss_hp_scaling; boss_scaling.js draws the
    // references and the chart under these rows)
    { key: 'boss_hp_scaling.enabled', group: 'Boss HP', label: 'Peg boss HP to DPS', type: 'bool', def: true, help: 'on: when a boss arrives its HP is times (the hero\'s DPS ÷ the boss\'s reference DPS) ^ exponent, between the floor and the ceiling; off: every boss keeps its data HP. The debug arena never scales. Empty = the game\'s: on' },
    { key: 'boss_hp_scaling.exponent', group: 'Boss HP', label: 'Exponent', type: 'number', min: 0, max: 1, step: 0.05, def: 0.5, help: 'how much of the extra DPS the boss soaks: 0.5 = the HP grows with the square root of the DPS (twice the DPS: 1.41× the HP, the fight 29% shorter); 1 = every fight as long as at the reference (no reward for more DPS); 0 = never scaled' },
    { key: 'boss_hp_scaling.window', group: 'Boss HP', label: 'DPS window (s)', type: 'number', min: 5, max: 180, step: 5, def: 45, help: 'the seconds before the boss arrives whose damage counts: the hero\'s DPS is what his hits took off creatures over them, ÷ the window (the clock runs through boss fights too)' },
    { key: 'boss_hp_scaling.min', group: 'Boss HP', label: 'Floor ×', type: 'number', min: 0.05, max: 1, step: 0.05, def: 0.75, help: 'the least the HP is multiplied by: a weak build meets a softer boss, never a pushover (0.75 = at most a quarter off)' },
    { key: 'boss_hp_scaling.max', group: 'Boss HP', label: 'Ceiling ×', type: 'number', min: 1, step: 0.25, def: 3, help: 'the most the HP is multiplied by: a monster build never meets a sponge (3 = reached at 9× the reference DPS with the exponent 0.5)' },
    // pass 73 (lane SNIPER; Garry: "Player Attacks should prioritize Special Enemies, Elites and Bosses once Player is close
    // enough to them"): WaveTimeline.target_priority, EnemyManager.priority_target
    { key: 'target_priority.enabled', group: 'Targeting', label: 'Specials first', type: 'bool', def: true, help: 'on: every weapon that picks its target takes a special (a coloured special or a gear-badge creature: the Vulture Raider, the harpooner, the Saiga Sniper), an Elite or the boss first when one is within reach, the nearest of them; a volley spread over different creatures sends only its first shot there. Weapons that pick no target (orbits, auras, salt, mines) are not changed. Off: every weapon as before. Empty = the game\'s: on' },
    { key: 'target_priority.reach', group: 'Targeting', label: 'Reach (m)', type: 'number', min: 0, step: 0.5, def: 10, help: 'how near the hero (a turret: itself) a special, an Elite or the boss must be to be taken first; never past the weapon\'s own range (empty = the game\'s 10 m)' },
    // pass 73 (lane GROUND; Garry: "currently the enemies just kind of appear. Let's make it so that they grow out of the
    // ground"): WaveTimeline.spawn_rise, handed to EnemyManager.set_spawn_rise by the director (the arena too)
    { key: 'spawn_rise.seconds', group: 'Spawning', label: 'Rise out of the ground (s)', type: 'number', min: 0, step: 0.05, def: 0.45, help: 'every creature that spawns grows out of the sand over this many seconds (×1/pace on the map): the part still under is cut along a line of sand, a small puff of dust at its feet; it stands, bites nobody and starts no attack until it is all the way up. 0 = off (they appear at once)' },
    { key: 'spawn_rise.big_seconds', group: 'Spawning', label: 'Elite / boss rise (s)', type: 'number', min: 0, step: 0.05, def: 0.9, help: 'the same for an Elite or a boss by its kind (they throw sand off themselves all the way up)' },
    { key: 'spawn_rise.targetable', group: 'Spawning', label: 'Targetable from', type: 'number', min: 0, max: 1, step: 0.05, def: 0.7, help: 'the share of the way up from which a weapon may choose a rising creature as its target (below it no weapon picks it, nothing aims at it; area damage, blasts, patches, beams and rings still hit it); a burrower sinking out of sight is passed over below it too. It bites and attacks only once it is all the way up' },
    { key: 'spawn_rise.dust', group: 'Spawning', label: 'Rise dust ×', type: 'number', min: 0, step: 0.1, def: 1, help: 'the size of the dust puff a rising creature throws up, × its size (0 = none; only drawn on the screen)' },
  ];
  const SCALAR_GROUPS = ['Stages', 'Cap', 'Spawning', 'Portal', 'Scaling', 'Coloured specials', 'Boss HP', 'Targeting', 'Endless', 'Items', 'World'];

  // the two curves' own fields (the HP x / ATK x inspectors and the Settings block)
  const CURVE = [
    { key: 'mode', label: 'Mode', type: 'select', options: [{ v: 'points', label: 'manual points', help: 'the drawn line goes through the points; drag them on the lane' }, { v: 'formula', label: 'formula', help: 'the line is the formula below; the points are only a saved copy' }], def: 'points', help: 'manual points, or a formula sampled onto the line' },
    { key: 'formula.kind', label: 'Formula', type: 'select', options: CURVE_KINDS, def: 'power', help: 'the shape of the formula (m = minutes of the run clock)' },
    { key: 'formula.a', label: 'a', type: 'number', min: 0, step: 0.005, def: 0.0977, help: 'the growth: linear and power add a × minutes under the bracket, exponential compounds by a a minute' },
    { key: 'formula.b', label: 'b', type: 'number', min: 0, step: 0.05, def: 1.25, help: 'the exponent (power only)' },
  ];

  const SPECIALS = [
    { key: 'from', label: 'From (s)', type: 'seconds', int: true, min: 0, help: 'the run second of stage 1 the specials\' clock starts' },
    { key: 'interval', label: 'Interval (s)', type: 'interval', help: 'min and max seconds after the last special dies before the next arrives' },
    { key: 'max_alive', label: 'Max alive', type: 'int', min: 1, def: 1, help: 'how many specials may live at once' },
  ];
  const PICKUP_ROW = [
    { key: 'id', label: 'Power-up', type: 'pickup', help: 'the power-up' },
    { key: 'weight', label: 'Weight', type: 'number', min: 0, step: 0.5, def: 1, help: 'how often it drops against the others' },
    { key: 'hard_bias', label: 'Hard bias', type: 'number', min: 0, step: 0.1, def: 0, help: 'how much more the harder creatures\' kills favour it (0 = evenly)' },
  ];

  // ------------------------------------------------------------------ the lanes (the Instructions tab)
  const LANES = [
    { id: 'cap', name: 'Cap', text: 'The ceiling: how many creatures may be alive (in cap load units; the fodder counts half). The points are the control points of the live cap curve: linear between them, flat before the first and after the last. They are not spawn events: the director spawns up to the cap on its own interval (spawn_interval), in bursts of burst_min to burst_max. Drag a point; double-click the line to add one, double-click a point to remove it. The dashed line is the hard cap of bodies, the dips are the boss fights\' share.' },
    { id: 'hp_act', name: 'Actual HP ×', text: 'Pass 58: the HP multiple the creatures really come with at each second, on the HP × lane\'s scale while the rows fit under it (higher multiples give it its own, up to 1.5 times as tall, and a ▲ with the number marks anything past its top; the curve you drag keeps its scale). A row\'s numbers are fixed from its start (Garry: "a single wave of those enemies will stay consistent for the duration of their spawns"): a row without an HP override keeps the HP curve of the second it starts for its whole life, a row with one keeps its own HP (its multiple is that HP over the creature\'s). The solid line is the average over the roster rows and wave alternatives spawning round that second, each weighted by how many it spawns there (the Spawned so far estimate); the dashed line is the largest; the intended curve is dotted behind them. Hover for the rows behind the numbers. The stage multiplier, creature_hp_mult and the hero level come on top in the game.' },
    { id: 'hp', name: 'HP ×', text: 'The multiplier on every creature\'s health over the run clock (hp_curve): a line like the cap\'s, as manual points you drag, or a formula (linear, power, exponential) sampled onto it; the inspector switches. Absent, the lane shows the legacy hp_growth / hp_power formula. The stage multiplier and creature_hp_mult come on top of it (the readout shows the product). Since pass 58 a row reads it once, at its start (the Actual HP × lane shows what that makes).' },
    { id: 'dmg_act', name: 'Actual ATK ×', text: 'Pass 58: the same for damage: each row\'s ATK multiple, the damage curve at its start or its own damage over the creature\'s, averaged by the spawns round each second (solid), the largest (dashed), the intended ATK × curve dotted behind.' },
    { id: 'dmg', name: 'ATK ×', text: 'The multiplier on every creature\'s damage over the run clock (damage_curve), the same two modes. Absent = 1 all run. The stage multiplier and creature_damage_mult come on top. Since pass 58 a row reads it once, at its start, and every later bite or shot of its creatures keeps that.' },
    { id: 'roster', name: 'Roster', text: 'The stream under the ceiling: whenever there is room, a burst is drawn from the rows open at that second by their weights. A bar runs from its start to its end (or the run\'s end); the filled area inside it is the row\'s presence over time (its weight), with a point per keyframe: drag a point up or down (or along), double-click the bar to add one, a point to remove it. Red bars are the hell channel, a wrench marks stat overrides, a chip the art variant. Drag a bar to move it, its right edge to end it. The grip and the arrows at the left reorder the rows (display only: the game ignores the order).' },
    { id: 'share', name: 'Share', text: 'The draw as the director sees it: each open row\'s share of a burst over time, stacked, one colour per creature, normalised per channel (the regular crowd above, the hell channel below when the map has one). The icons are the legend. A row that is heavy on the Roster lane but drawn against many others is thin here.' },
    { id: 'waves', name: 'Waves', text: 'Scripted windows on top of the roster: from t, a burst every few seconds until the count or the end. Stripes are the alternatives (one is rolled per run); "no cap" means it spawns on top of the crowd. Drag to move, drag the right edge to end, click to edit.' },
    { id: 'events', name: 'Events', text: 'One-off moments: bosses (skull), Elites (crown), coloured elites (star), the repeating elite timer (arrows with a dotted trail), swarms (ring). Whiskers are the jitter, a faded marker a chance under 100%. Drag to move.' },
    { id: 'specials', name: 'Specials', text: 'The specials\' clock (the Vulture Raider, the harpooner): from its start, one at a time, the next a random interval after the last one dies. Edit it in Settings or by clicking the band.' },
    { id: 'paths', name: 'Paths', text: 'When each stage puts a weapon\'s whole path on the table (seconds into the stage). Edit in Settings.' },
  ];

  return { roster, wave, alt, event, EVENT_TYPES, OVERRIDES, OVERRIDE_GROUPS, OVERRIDE_GROUP_HELP, SCALARS, SCALAR_GROUPS, CURVE, CURVE_KINDS, SIDE_MODES, SPECIALS, PICKUP_ROW, PATTERNS, SWARM_PATTERNS, CHANNELS, LANES };
})();
