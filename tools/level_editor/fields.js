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
  // pass 81 (lane PACE; Garry: "Add the ability to control the pacing of the waves ... If it's continuous (choose an
  // option) it's shown as a continuous yellow line"): a roster row's `pace` (WaveTimeline.ROW_PACES)
  const PACES = [
    { v: 'continuous', label: 'Continuous', help: 'drawn into the cap by its weight at every spawn check, as every row always was (a yellow line on its bar)' },
    { v: 'waves', label: 'Waves every N s', help: 'a wave of Per wave creatures every Every seconds from From (+ Offset) while the row is open (a yellow tick on its bar at each wave)' },
    // pass 84 (lane TIMELINE; INTERFACES.md): one wave at From + Offset, what the SWARM and coloured-elite events were
    { v: 'once', label: 'Once', help: 'one wave of Per wave creatures at From + Offset, then nothing (a SWARM event was one of these: on top of the cap, a ring 16 m out, a banner); a yellow tick on its bar where it comes' },
  ];
  // pass 84 (lane TIMELINE): who a row brings (the inspector's "Who" switch over the `enemy` key)
  const ENEMY_MODES = [
    { v: 'one', label: 'One creature', help: 'every creature of the row is this one' },
    { v: 'list', label: 'A list, one drawn at random', help: 'each creature (each pack) is drawn from the list by its weight (equal when the weights are empty), as the swarm and Elite events drew theirs' },
    { v: 'roster', label: 'From the roster (the coloured-elite draw)', help: 'each creature is drawn from the roster rows open at that second by their Elite weight (Overrides -> Elite), with that row\'s HP and ATK: what the coloured-elite and Elites-every events did' },
  ];
  // pass 82 (lane XP; Garry: "types of EXP growth displayed in a dropdown, each one with it's own 2 charts for cumulative
  // and per level EXP requirements"): the growth types of `xp_curve` and their numbers (game/core/data/XpCurve.gd TYPES /
  // DEFAULTS; xp_model.js has the maths, xp_card.js draws the Settings card; selftest_XP82.py keeps the three equal).
  // L = the hero's level: level 1 needs the curve at L = 1 to reach level 2. Every type is times XP needed ×.
  const XP_TYPES = [
    { v: 'quadratic', label: 'Today\'s: quadratic', formula: 'base + linear × L + quad × L²', help: 'the curve every run has played so far (15 + 6L + L²/2): the L² part makes each level need a little more than the step before, so late levels climb steadily. Level 10 needs 125, level 30 645, level 60 2,175 (before XP needed ×)', params: [
      { key: 'base', label: 'Base', type: 'number', min: 0, step: 1, def: 15, help: 'the XP every level needs at the least (the constant part)' },
      { key: 'linear', label: 'Per level', type: 'number', min: 0, step: 0.5, def: 6, help: 'the XP added for every level (× L)' },
      { key: 'quad', label: 'Per level²', type: 'number', min: 0, step: 0.05, def: 0.5, help: 'the L² part: what makes late levels climb (0 = a straight line)' },
    ] },
    { v: 'linear', label: 'Linear', formula: 'base + step × (L − 1)', help: 'every level needs the same amount more than the one before: the gaps never widen. With the defaults the first levels are dearer than today\'s and the late ones cheaper (the same total by level 30)', params: [
      { key: 'base', label: 'Level 1 needs', type: 'number', min: 0, step: 1, def: 21.5, help: 'the XP level 1 needs to reach level 2' },
      { key: 'step', label: 'Step', type: 'number', min: 0, step: 0.5, def: 16.5, help: 'the XP each level needs more than the one before' },
    ] },
    { v: 'exponential', label: 'Exponential', formula: 'base × growth^(L − 1), at most cap', help: 'every level needs Growth times the one before (1.11 = 11% more each level): gentle early, a wall late. With the defaults level 60 needs 18,900 (today\'s 2,175, before XP needed ×): a cap flattens the climb', params: [
      { key: 'base', label: 'Level 1 needs', type: 'number', min: 0, step: 1, def: 40, help: 'the XP level 1 needs to reach level 2' },
      { key: 'growth', label: 'Growth', type: 'number', min: 1, step: 0.01, def: 1.11, help: 'each level needs this many times the one before: 1.11 = 11% more a level, 1 = every level the same' },
      { key: 'cap', label: 'Cap', type: 'number', min: 0, step: 50, def: 0, help: 'the most XP any one level needs (before XP needed ×); past it every level needs the cap. 0 = no cap' },
    ] },
    { v: 'power', label: 'Power', formula: 'base × L^power', help: 'the XP grows as a power of the level: 1 = a straight line, 2 = a parabola like today\'s L² part, in between the climb eases off as the levels rise', params: [
      { key: 'base', label: 'Level 1 needs', type: 'number', min: 0, step: 0.5, def: 6.5, help: 'the XP level 1 needs to reach level 2' },
      { key: 'power', label: 'Power', type: 'number', min: 0, step: 0.01, def: 1.33, help: 'how steeply the need climbs with the level: 1 = straight, 2 = a parabola' },
    ] },
    { v: 'table', label: 'Table (your levels)', formula: 'your [level, XP] points, straight between them', help: 'you set the XP for the levels you list; the levels between are filled in on a straight line, the levels before the first need the first\'s XP, and past the last listed level each level needs the last amount grown by After the table', params: [
      { key: 'points', label: 'Levels', type: 'xp_points', def: [[1, 21.5], [5, 57.5], [10, 125], [20, 335], [30, 645], [40, 1055], [50, 1565], [60, 2175]], help: 'a list of [level, XP the level needs]: straight between two listed levels; empty = this default (today\'s curve at those levels)' },
      { key: 'after_growth', label: 'After the table', type: 'percent', min: 0, def: 0.025, help: 'past the last listed level, each level needs this much more than the one before (2.5% = 1.025 times; 0 = the last amount repeats)' },
    ] },
  ];

  // ------------------------------------------------------------------ roster rows
  const roster = [
    { key: 'id', label: 'Id', type: 'text', help: 'a stable label (r1, r2, ...) so a reordered row keeps its numbers on save; the game ignores it' },
    // pass 84 (lane TIMELINE; INTERFACES.md): a label (as the events had), the editor's role, and who the row brings
    { key: 'name', label: 'Name', type: 'text', group: 'Creature', help: 'a label for the editor and the hand-back notes ("Ant swarm"); the game never shows it (Banner is what the player reads)' },
    { key: 'enemy', label: 'Creature', type: 'enemy', required: true, group: 'Creature', help: 'which creature this row spawns: one creature, a list with weights (each creature drawn at random by its weight), or "roster" (each drawn from the rows open at that second by their Elite weight, with that row\'s HP and ATK: the coloured-elite draw)' },
    { key: 'role', label: 'Role', type: 'select', group: 'Creature', options: [{ v: '', label: '(untagged)', help: 'no role: drawn neutral grey' }, { v: 'fodder', label: 'fodder', help: 'the plain crowd' }, { v: 'swarm', label: 'swarm', help: 'a burst of many at once' }, { v: 'tank', label: 'tank', help: 'slow and tough' }, { v: 'ranged', label: 'ranged', help: 'shoots from a distance' }, { v: 'elite', label: 'elite', help: 'wears an elite modifier' }, { v: 'special', label: 'special', help: 'comes as its coloured special' }], def: '', help: 'what this row is for, in your words: it colours and groups the bar on the Timeline (Spawn rows: colour by role, group by role). The game ignores it' },
    { key: 'elite', label: 'Elite modifier', type: 'elite', def: '', group: 'Creature', help: 'every creature of the row wears this elite modifier: none, random (a fresh one each creature), or one by name; they wait for Colour after kills (Settings -> Spawning) like the coloured-elite events did, and never roll the coloured special' },
    { key: 'special', label: 'Special', type: 'bool', def: false, group: 'Creature', help: 'on: every creature of the row comes as its coloured special for sure (its Special block on the Enemies tab: size, HP x, ATK x, XP x, colour, glow), even before Colour after kills: the special Goblin at 2:00 is a once row of 1 with this on. A creature with no variance block comes plain' },
    { key: 't', label: 'From', type: 'seconds', int: true, min: 0, required: true, help: 'the run second the row starts being drawn (the clock stands still through boss fights and portals)' },
    { key: 'until', label: 'Until', type: 'seconds', int: true, min: 0, help: 'the run second the row stops; empty = to the end of the run' },
    { key: 'weights', label: 'Presence', type: 'weights', help: 'the row\'s draw weight over the run clock as [time, weight] points: linear between them, flat before the first and after the last; its share of a burst is its weight against the other open rows of its channel (10 against 4 = 71% / 29%). Drag the points on the bar; double-click the bar to add one, a point to remove it. A row paced as Waves (Pacing) is not in that draw: its presence only switches its waves on and off (a wave due while the weight is 0 does not come; the weight\'s size does not change the wave, Per wave does), unless it is Also continuous' },
    { key: 'channel', label: 'Channel', type: 'select', options: CHANNELS, def: 'regular', help: 'regular crowd, or the hell channel with its own cap' },
    { key: 'pack', label: 'Pack', type: 'int', min: 1, help: 'how many spawn together; empty = the creature\'s own pack size' },
    { key: 'pattern', label: 'Pattern', type: 'select', options: PATTERNS, def: 'pack', group: 'Where', help: 'pack at one point, scattered, one at a time, a ring round the hero (the pack at once, 11.7 m out) or in front (from the top of the screen, whatever the spawn side in Settings says)' },
    // pass 84 (lane TIMELINE; INTERFACES.md): a ring's own radius (a swarm's was 16 m)
    { key: 'ring_radius', label: 'Ring radius (m)', type: 'number', min: 2, step: 0.5, def: 11.7, group: 'Where', ring: true, help: 'how far out the ring is, in metres, while Pattern is Ring: empty = 11.7 m (the arena\'s 9 m ring x 1.3); the SWARM events came on a ring of 16 m' },
    // pass 81 (lane PACE): the row's own pacing; the `paced` fields show only while Pacing is Waves (WaveDirector._tick_row_waves)
    { key: 'pace', label: 'Pacing', type: 'select', options: PACES, def: 'continuous', help: 'how this row\'s creatures come. Continuous (the default, as every row always came): drawn into the cap by its weight at every spawn check (Settings → Spawning: Spawn check every, Burst min / max) or on its own clock (Draw every), a yellow tick along its bar at each draw (a dotted yellow line where they are under 3 px apart). Waves every N s: a wave of Per wave creatures every Every seconds from From (+ Offset) while the row is open, a yellow tick on its bar at each wave; between its waves it is not drawn (unless Also continuous). Once (pass 84): one wave at From + Offset, then nothing: a swarm, a coloured elite, the special Goblin' },
    { key: 'every', label: 'Every (s)', type: 'interval', min: 0, step: 1, def: 30, paced: true, paceIn: ['waves'], help: 'seconds between this row\'s waves, the first at From + Offset; 0 = one wave only. Two numbers (min and max, pass 84) = a fresh random gap between them before each wave, as the Elites-every events had. Empty = 30' },
    { key: 'count', label: 'Per wave', type: 'int', min: 1, paced: true, paceIn: ['waves', 'once'], help: 'how many creatures each wave brings, in the row\'s Pattern (packs of Pack); empty = the row\'s Pack, else the creature\'s pack size' },
    { key: 'offset', label: 'Offset (s)', type: 'number', min: 0, step: 1, def: 0, paced: true, paceIn: ['waves', 'once'], help: 'the first wave comes this many seconds after From, then one every Every seconds; 0 = at From' },
    { key: 'respect_cap', label: 'Respect the cap', type: 'bool', def: true, paced: true, paceIn: ['waves', 'once'], help: 'on: a wave spawns into the free room under its channel\'s cap (at least one while there is any); what does not fit comes first as room frees, ahead of the continuous rows, until this row\'s next wave (which drops the rest) or its Until. Off: the whole wave at once on top of the cap, like a SWARM (the hard cap and Max alive still hold)' },
    { key: 'trickle', label: 'Also continuous', type: 'bool', def: false, paced: true, paceIn: ['waves', 'once'], help: 'on: between its waves the row is also drawn into the cap by its weight, like a continuous row (a yellow line under its ticks); off (the default): its creatures come only in its waves' },
    // pass 83 (lane TIMELINE): a row in the continuous draw may keep its own clock (WaveDirector._tick_row_intervals); the
    // `drawn` field shows while the row is drawn (Continuous, or Waves with Also continuous)
    { key: 'interval', label: 'Draw every (s)', type: 'number', min: 0.1, step: 0.1, drawn: true, help: 'how often the director draws this continuous row, in seconds. Empty (the grey number) = at its spawn check, with every other row (Settings → Spawning: Spawn check every; Red Canyon 0.7 s). A number gives the row its own clock: a draw every N seconds from From, each a burst (Burst min to Burst max load units) cut to this row\'s share of the open rows\' weight, so 0.35 brings it about twice as often as 0.7 and 1.4 about half as often, a little at a time; the cap and Max alive still hold. A yellow tick on its bar at each draw (dotted where they are under 3 px apart). Least 0.1' },
    // pass 84 (lane SPAWN's keys): a once or waves row's roll per run and its jitter, as the events had
    { key: 'chance', label: 'Chance', type: 'percent', def: 1, paceIn: ['waves', 'once'], help: 'the chance this row comes at all, rolled per run (100 = always), as an event\'s chance; a waves row rolls once for the run' },
    { key: 't_jitter', label: 'Jitter (± s)', type: 'number', min: 0, step: 1, def: 0, paceIn: ['waves', 'once'], help: 'its time moves by up to this many seconds either way, rolled per run (never before 0:00), as an event\'s jitter' },
    // pass 84 (lane TIMELINE; INTERFACES.md): the banner a wave shows when it fires (the swarms' "SWARM!")
    { key: 'banner', label: 'Banner', type: 'text', group: 'Where', paceIn: ['waves', 'once'], help: 'a banner the player reads when a wave of this row fires, like "SWARM!"; empty = none. Only a row paced as Waves or Once shows one' },
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
    // pass 84 (lane TIMELINE; Garry: "better add too many controls than too few"): the two *_mult keys the game already
    // reads (EnemyDef.OVERRIDE_MULTS) with no box until now
    { path: 'size_mult', group: 'Body', label: 'Size ×', type: 'number', min: 0.05, step: 0.05, ph: () => 1, help: 'multiplies the painting\'s height (both ends of a size range): 1.3 = 30% taller. The collision radius stays unless Radius × or Radius is set' },
    { path: 'radius_mult', group: 'Body', label: 'Radius ×', type: 'number', min: 0.05, step: 0.05, ph: () => 1, help: 'multiplies the body\'s collision radius (how much room it takes in the crowd and how close it bites)' },
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
    // pass 84 (lane TIMELINE): the rest of the ranged block (deep-merged over the creature's own, EnemyDef.with_overrides)
    { path: 'ranged.keep_distance', group: 'Ranged', label: 'Keeps away (m)', type: 'number', min: 0, step: 0.5, ph: (c) => sub(c, 'ranged', 'keep_distance'), help: 'the distance it tries to keep from the hero while it shoots', needs: 'ranged' },
    { path: 'ranged.telegraph', group: 'Ranged', label: 'Telegraph (s)', type: 'number', min: 0, step: 0.05, ph: (c) => sub(c, 'ranged', 'telegraph'), help: 'the warning before a shot leaves (the aim line or the glow)', needs: 'ranged' },
    { path: 'ranged.damage', group: 'Ranged', label: 'Shot damage', type: 'number', min: 0, step: 1, ph: (c) => sub(c, 'ranged', 'damage'), help: 'a shot\'s own damage (empty: the creature\'s bite damage)', needs: 'ranged' },
    { path: 'ranged.splash', group: 'Ranged', label: 'Splash (m)', type: 'number', min: 0, step: 0.1, ph: (c) => sub(c, 'ranged', 'splash'), help: 'the radius a shot hurts where it lands (0 = only a direct hit)', needs: 'ranged' },
    { path: 'ranged.count', group: 'Ranged', label: 'Shots a volley', type: 'int', min: 1, ph: (c) => sub(c, 'ranged', 'count'), help: 'how many shots each volley holds', needs: 'ranged' },
    { path: 'ranged.cone_deg', group: 'Ranged', label: 'Volley cone (°)', type: 'number', min: 0, max: 360, step: 5, ph: (c) => sub(c, 'ranged', 'cone_deg'), help: 'the spread of a volley\'s shots', needs: 'ranged' },
    { path: 'ranged.knockback', group: 'Ranged', label: 'Shot knockback', type: 'number', min: 0, step: 0.5, ph: (c) => sub(c, 'ranged', 'knockback'), help: 'the shove a shot gives the hero, m/s', needs: 'ranged' },
    { path: 'charge.cooldown', group: 'Charge', label: 'Cooldown (s)', type: 'number', min: 0.1, step: 0.1, ph: (c) => sub(c, 'charge', 'cooldown'), help: 'seconds between charges', needs: 'charge' },
    { path: 'charge.speed', group: 'Charge', label: 'Charge speed', type: 'number', min: 0.5, step: 0.5, ph: (c) => sub(c, 'charge', 'speed'), help: 'the charge\'s speed in m/s', needs: 'charge' },
    { path: 'charge.windup', group: 'Charge', label: 'Wind-up (s)', type: 'number', min: 0, step: 0.05, ph: (c) => sub(c, 'charge', 'windup'), help: 'the crouch before it runs (the hero\'s warning)', needs: 'charge' },
    { path: 'charge.duration', group: 'Charge', label: 'Charge length (s)', type: 'number', min: 0.1, step: 0.1, ph: (c) => sub(c, 'charge', 'duration'), help: 'how long a charge runs', needs: 'charge' },
    { path: 'charge.trigger_range', group: 'Charge', label: 'Charges from (m)', type: 'number', min: 0, step: 0.5, ph: (c) => sub(c, 'charge', 'trigger_range'), help: 'how near the hero must be before it charges', needs: 'charge' },
    { path: 'charge.knockback', group: 'Charge', label: 'Charge knockback', type: 'number', min: 0, step: 0.5, ph: (c) => sub(c, 'charge', 'knockback'), help: 'the shove a charge gives the hero, m/s', needs: 'charge' },
    // pass 84 (lane TIMELINE): the kamikaze, artillery, sniper and flee-on-hit blocks (deep-merged like Ranged; the
    // brain, the death burst and a caster's spells are not overridable per row: the game reads them from the creature only)
    { path: 'kamikaze.trigger', group: 'Kamikaze', label: 'Triggers at (m)', type: 'number', min: 0, step: 0.1, ph: (c) => sub(c, 'kamikaze', 'trigger'), help: 'how near the hero it starts its blast', needs: 'kamikaze' },
    { path: 'kamikaze.windup', group: 'Kamikaze', label: 'Wind-up (s)', type: 'number', min: 0, step: 0.05, ph: (c) => sub(c, 'kamikaze', 'windup'), help: 'the flash before it blows', needs: 'kamikaze' },
    { path: 'kamikaze.radius', group: 'Kamikaze', label: 'Blast radius (m)', type: 'number', min: 0, step: 0.1, ph: (c) => sub(c, 'kamikaze', 'radius'), help: 'how far the blast reaches', needs: 'kamikaze' },
    { path: 'kamikaze.damage', group: 'Kamikaze', label: 'Blast damage', type: 'number', min: 0, step: 1, ph: (c) => sub(c, 'kamikaze', 'damage'), help: 'the blast\'s damage (× the stage, the level and the creature damage ×)', needs: 'kamikaze' },
    { path: 'kamikaze.knockback', group: 'Kamikaze', label: 'Blast knockback', type: 'number', min: 0, step: 0.5, ph: (c) => sub(c, 'kamikaze', 'knockback'), help: 'the shove the blast gives, m/s', needs: 'kamikaze' },
    { path: 'artillery.stand_off', group: 'Artillery', label: 'Stands off (m)', type: 'number', min: 0, step: 1, ph: (c) => sub(c, 'artillery', 'stand_off'), help: 'the distance it keeps to fire its rockets', needs: 'artillery' },
    { path: 'artillery.windup', group: 'Artillery', label: 'Wind-up (s)', type: 'number', min: 0, step: 0.05, ph: (c) => sub(c, 'artillery', 'windup'), help: 'the aim before a rocket leaves', needs: 'artillery' },
    { path: 'artillery.reload', group: 'Artillery', label: 'Reload (s)', type: 'number', min: 0.1, step: 0.1, ph: (c) => sub(c, 'artillery', 'reload'), help: 'seconds between rockets', needs: 'artillery' },
    { path: 'artillery.missile.speed', group: 'Artillery', label: 'Rocket speed', type: 'number', min: 0.1, step: 0.1, ph: (c) => sub2(c, 'artillery', 'missile', 'speed'), help: 'the rocket\'s speed, m/s', needs: 'artillery' },
    { path: 'artillery.missile.turn', group: 'Artillery', label: 'Rocket turn', type: 'number', min: 0, step: 0.1, ph: (c) => sub2(c, 'artillery', 'missile', 'turn'), help: 'how hard the rocket homes (radians a second)', needs: 'artillery' },
    { path: 'artillery.missile.damage', group: 'Artillery', label: 'Rocket damage', type: 'number', min: 0, step: 1, ph: (c) => sub2(c, 'artillery', 'missile', 'damage'), help: 'the rocket\'s damage (× the stage, the level and the creature damage ×)', needs: 'artillery' },
    { path: 'artillery.missile.area', group: 'Artillery', label: 'Rocket blast (m)', type: 'number', min: 0, step: 0.1, ph: (c) => sub2(c, 'artillery', 'missile', 'area'), help: 'the rocket\'s blast radius', needs: 'artillery' },
    { path: 'sniper.stand_off', group: 'Sniper', label: 'Holds at (m)', type: 'number', min: 0, step: 1, ph: (c) => sub(c, 'sniper', 'stand_off'), help: 'the distance it walks in to and holds', needs: 'sniper' },
    { path: 'sniper.first', group: 'Sniper', label: 'First shot after (s)', type: 'number', min: 0, step: 0.5, ph: (c) => sub(c, 'sniper', 'first'), help: 'seconds from its arrival to its first aim', needs: 'sniper' },
    { path: 'sniper.aim', group: 'Sniper', label: 'Aim (s)', type: 'number', min: 0, step: 0.1, ph: (c) => sub(c, 'sniper', 'aim'), help: 'the gathering red line before the lock', needs: 'sniper' },
    { path: 'sniper.lock', group: 'Sniper', label: 'Lock (s)', type: 'number', min: 0, step: 0.05, ph: (c) => sub(c, 'sniper', 'lock'), help: 'the locked line before the beam fires (the hero\'s last chance to step aside)', needs: 'sniper' },
    { path: 'sniper.interval', group: 'Sniper', label: 'Between shots (s)', type: 'number', min: 0.1, step: 0.5, ph: (c) => sub(c, 'sniper', 'interval'), help: 'seconds between shots', needs: 'sniper' },
    { path: 'sniper.spoil_on_hit', group: 'Sniper', label: 'A hit spoils its aim', type: 'bool3', ph: (c) => (c && c.sniper ? (c.sniper.spoil_on_hit ? 'yes' : 'no') : ''), help: 'whether a hit on it while it aims drops the shot', needs: 'sniper' },
    { path: 'flee_on_hit.seconds', group: 'Flee on hit', label: 'Flees for (s)', type: 'number', min: 0, step: 0.1, ph: (c) => sub(c, 'flee_on_hit', 'seconds'), help: 'after a hit it runs straight away from the hero for this long (0 = never); a creature without the block gains it here (the game\'s 1 s)' },
    { path: 'flee_on_hit.speed_mult', group: 'Flee on hit', label: 'Flee speed ×', type: 'number', min: 0, step: 0.1, ph: (c) => sub(c, 'flee_on_hit', 'speed_mult'), help: 'its speed while it flees, × its own (the game\'s 1.8)' },
    { path: 'flee_on_hit.interrupts', group: 'Flee on hit', label: 'A hit interrupts', type: 'bool3', ph: (c) => (c && c.flee_on_hit && c.flee_on_hit.interrupts != null ? (c.flee_on_hit.interrupts ? 'yes' : 'no') : ''), help: 'whether a hit drops a wind-up or an aim under way (the shot never comes); the game\'s yes' },
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
  const OVERRIDE_GROUPS = ['Body', 'Colour', 'Attacks', 'Ranged', 'Charge', 'Kamikaze', 'Artillery', 'Sniper', 'Flee on hit', 'Spawning', 'Drops', 'Power-ups', 'Elite', 'Mini-boss (Elite archetype only)', 'Boss'];
  // what each override group is, for the legend and the Instructions tab (pass 54)
  const OVERRIDE_GROUP_HELP = {
    Colour: 'pass 58: wash every creature of this row in a colour from a range, each its own hue; the pictures are its standing frame as the game tints it',
    Elite: 'the variance block: the size and speed spread, the tints, the coloured specials and their numbers, merged over the creature\'s own block (a tint list replaces the whole list); plus how a random coloured elite is drawn from this row and how it arrives',
    'Mini-boss': 'Elite archetype only: the three mini-bosses\' own health rule',
    'Flee on hit': 'pass 84: any creature may run from a hit (the Saiga Sniper\'s block): typed here, the row\'s creatures gain it',
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
    // pass 84 (lane TIMELINE; INTERFACES.md, lane SPAWN plays it): the density floor beside the cap
    { key: 'floor_curve', group: 'Cap', label: 'Floor curve', type: 'floor_points', def: [], help: 'the least creatures alive on the regular channel as [seconds, creatures] control points, linear between them, flat outside: while fewer are alive the director draws the continuous rows at once (not waiting for the spawn check) until the floor is met, within the cap and the hard cap. Empty = no floor (the game as before pass 84). Drag its points on the Floor lane (Curves)' },
    { key: 'boss_cap_frac', group: 'Cap', label: 'Boss fight cap share', type: 'number', min: 0, max: 1, step: 0.05, def: 0.3, help: 'the crowd kept up during a boss fight, as a share of the cap' },
    // pass 81 (lane PACE): the continuous rows' pacing, said as such (a row's own Pacing is in the row form)
    { key: 'burst_min', group: 'Spawning', label: 'Burst min', type: 'int', min: 1, def: 5, help: 'the continuous rows\' pacing: at every spawn check the director draws a burst of Burst min to Burst max cap load units (the fodder counts half) from the open continuous rows by their weights, as far as the cap has room. This is the least' },
    { key: 'burst_max', group: 'Spawning', label: 'Burst max', type: 'int', min: 1, def: 20, help: 'the largest burst a spawn check draws (as far as the cap has room): small bursts often refill the crowd as a steady trickle, big bursts seldom bring it in clumps. A row\'s Pack still comes together, cut to what the burst holds' },
    { key: 'spawn_interval', group: 'Spawning', label: 'Spawn check every (s)', type: 'number', min: 0.1, step: 0.1, def: 0.5, help: 'seconds between the director\'s spawn checks: how often the continuous rows refill the crowd while the cap has room (Red Canyon 0.7). A row paced as Waves (the row form\'s Pacing) keeps its own clock; what a capped wave still owes comes in at these checks, first. Pass 83: a continuous row with its own Draw every (the row form) is drawn on its own clock instead, a burst cut to its share; this is every other row\'s interval and that box\'s grey default' },
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
    // pass 82 (lane XP): the XP card (xp_card.js draws these rows, the charts and the pace with them)
    { key: 'xp_curve.type', group: 'XP per level', label: 'Growth', type: 'select', options: XP_TYPES.map((t) => ({ v: t.v, label: t.label, help: t.help })), def: 'quadratic', block: 'xp_curve', help: 'how the XP a level needs grows with the level: today\'s quadratic (the default: absent = exactly the curve every run has played), linear, exponential, power, or a table of your own. Each type keeps its own numbers in the file (switching back keeps them); only the chosen one is played. Every type is times XP needed ×' },
    // (the table's default list is named in its help rather than the Instructions tab's Default column, which it would swamp)
    ...XP_TYPES.flatMap((t) => t.params.map((p) => Object.assign({}, p, { key: `xp_curve.${t.v}.${p.key}`, group: 'XP per level', label: `${t.label}: ${p.label}`, block: 'xp_curve', help: `${p.help} (${t.formula})` }, p.type === 'xp_points' ? { def: undefined, help: `${p.help}: ${JSON.stringify(p.def)}` } : {}))),
    { key: 'xp_need_mult', group: 'XP per level', label: 'XP needed ×', type: 'number', min: 0.1, step: 0.05, def: 1, block: 'xp_curve', help: 'every hero level needs this many times the growth curve\'s amount, whatever its type (today\'s: 15 + 6L + L²/2 XP for level L). Pass 79: mutation offers come as level-ups, so levels come faster to keep the same three-card picks by any minute plus the mutation level-ups on top: Red Canyon 1.65 (it was 3.1 with mutations on the clock)' },
    // pass 79 (lane MUT): whether mutation level-ups count for what grows with the hero's level (Run.card_level)
    { key: 'mutation_levels_scale', group: 'Scaling', label: 'Mutation levels scale', type: 'bool', def: false, help: 'off: what grows with the hero\'s level (the HP and damage per hero level above, his trait, Barrel Rush\'s gems, Ram, Supply Drop) counts only his card levels, his level less the level-ups that were mutation offers, so a minute brings the same scaling as before mutations came as level-ups; on: every level-up counts. Empty = the game\'s: off' },
    { key: 'endless_wave_seconds', group: 'Endless', label: 'Endless wave (s)', type: 'number', min: 1, step: 1, def: 60, help: 'in endless, a new wave this often' },
    { key: 'endless_wave_mult', group: 'Endless', label: 'Endless wave ×', type: 'number', min: 1, step: 0.01, def: 1, help: 'every endless wave multiplies the creatures by this, compounding' },
    { key: 'weapon_cap', group: 'Items', label: 'Weapon slots per stage', type: 'list', int: true, def: [5, 5, 5], help: 'weapon slots per stage (static since pass 47: 5)' },
    { key: 'passive_cap', group: 'Items', label: 'Line slots per stage', type: 'list', int: true, def: [5, 5, 5], help: 'line slots per stage (static since pass 47: 5)' },
    { key: 'path_times', group: 'Items', label: 'Mutation offers per stage', type: 'path_times', def: [], help: 'seconds into each stage when a mutation offer falls due: it comes at the hero\'s next level-up, in place of the three cards (a weapon drawn among those with the stage\'s pick open, its whole path on the table; the HUD marks the LV plate while one waits). Offers queue, one a level-up; one that falls due while no weapon has a pick open is spent with nothing. One list per stage; the last holds for later stages (pass 79: they no longer pop up on the clock)' },
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
    // pass 80 (lane OASIS; Garry: "make the water slow everyone down when they walk though it, not by a lot, just 10%. And
    // make it so there are 2 oasis at least per level generation in the red canyon, sometimes 3"): WaveTimeline.water_slow
    // and oases (WATER_SLOW_DEFAULT, OASES_DEFAULTS are the game's defaults, the def here; RedCanyon._roll_oases)
    { key: 'water_slow', group: 'World', label: 'Water slow', type: 'number', min: 0, max: 0.95, step: 0.05, def: 0.1, help: 'how much slower anyone walks in an oasis\'s water: 0.1 = 10% slower (the hero, every creature, Elites and bosses). Only walking: a push, a knockback or a pull is never slowed, nor anyone in the air (a trampoline flight, a creature thrown or launched) or under the sand. 0 = off (empty = the game\'s 0.1)' },
    { key: 'oases.min', group: 'World', label: 'Oases (at least)', type: 'int', min: 1, max: 6, def: 2, help: 'how many oases every run rolls at least, each a wadeable lake with its palms and green (empty = the game\'s 2)' },
    { key: 'oases.max', group: 'World', label: 'Oases (at most)', type: 'int', min: 1, max: 6, def: 3, help: 'the most oases a run rolls; past the least, each one more comes with the chance below (empty = the game\'s 3)' },
    { key: 'oases.extra_chance', group: 'World', label: 'Chance of one more oasis', type: 'number', min: 0, max: 1, step: 0.05, def: 0.35, help: 'the chance of each oasis past the least, up to the most: with 2 to 3, 0.35 = a third oasis in about a third of the runs (empty = the game\'s 0.35)' },
    { key: 'oases.gap', group: 'World', label: 'Oasis spacing (m)', type: 'number', min: 0, step: 1, def: 10, help: 'the least open ground between two oases\' dips (each dip reaches 1.6 times its lake\'s radius). Every oasis also keeps 8 m past its lake off the flats and 5 m off the dry river. A larger spacing can leave a run an oasis short where the map has no room (empty = the game\'s 10 m)' },
    // pass 82 (lane SAND; Garry: "Add the previous sand texture as the 5th variant as well. I want to be able to switch
    // between them easily. Maybe in the LevelEditor"): WaveTimeline.sand, an id of RedCanyon.SANDS (SAND_DEFAULT = 'pass81')
    { key: 'sand', group: 'World', label: 'Sand', type: 'select', def: 'pass81', options: [
      { v: 'pass81', label: 'Pass 81 sand (today\'s)', help: 'the sand played since pass 81: calm, soft blotches, a few small pebbles and dark grains' },
      { v: 'dunes', label: 'Soft dunes', help: 'broad soft wavy dune shading over a fine grain, no stones' },
      { v: 'dunes_pebbles', label: 'Soft dunes + pebbles', help: 'the soft dune shading with small grey pebbles scattered far apart' },
      { v: 'ripples', label: 'Wind ripples', help: 'smaller, more irregular wind ripples over a fine grain, no stones: livelier' },
      { v: 'ripples_pebbles', label: 'Wind ripples + pebbles', help: 'the wind ripples with small grey pebbles scattered far apart' },
    ], help: 'the painting the open ground is drawn with (the river bed, the oases\' wet ground, the rock outside the wall and every colour stay as they are: all five sands share one mean colour). The four new ones (pass 82) follow Garry\'s reference: soft wavy dune shading and a fine grain; two keep little rocks. Pick one, Save, play: the next run is drawn with it. The arena\'s WORLD tab switches them on the spot to compare. The default stays the pass 81 sand until you pick' },
    // pass 79 (lane WORLD; Garry: "Map the sides are too orange"): the colours of the map's sides (WaveTimeline.rock_color,
    // wall_colors; RedCanyon.ROCK_COLOR / WALL_COLORS are the game's defaults, the def here)
    { key: 'rock_color', group: 'World', label: 'Rock colour', type: 'swatch', def: '#785C5E', help: 'the red-rock rim the ground rises into towards the wall (the painting is recoloured to it, its bands and cracks kept as light and dark). The sun and the sky light are warm and push every colour towards orange on the screen, so pick a touch rosier than you want to see. Empty = the game\'s #785C5E (pass 79; it was the orange #9E573D)' },
    { key: 'wall_colors.near', group: 'World', label: 'Cliffs (near)', type: 'swatch', def: '#856B6E', help: 'the ring of cliffs right behind the boundary wall (a grey sandstone painting tinted to this). Empty = the game\'s #856B6E' },
    { key: 'wall_colors.far', group: 'World', label: 'Cliffs (far)', type: 'swatch', def: '#705963', help: 'the second ring of cliffs, farther out and a shade darker. Empty = the game\'s #705963' },
    { key: 'wall_colors.farther', group: 'World', label: 'Cliffs (farthest)', type: 'swatch', def: '#594A57', help: 'the outermost ring of cliffs on the horizon, darkest. Empty = the game\'s #594A57' },
    // pass 80 (lane WALLS): the boundary is a western sandstone fort wall, drawn unshaded in these colours times its block painting
    { key: 'wall_colors.stone', group: 'World', label: 'Wall stone', type: 'swatch', def: '#C59E7B', help: 'the fort wall\'s sandstone blocks: its faces, the parapet, the merlons and the towers (the foot a third darker, the outer face a quarter darker). Drawn as it is, times the block painting. Empty = the game\'s #C59E7B (pass 79\'s stacked stone was #7A6363)' },
    { key: 'wall_colors.light', group: 'World', label: 'Wall trim', type: 'swatch', def: '#DEC09F', help: 'the fort wall\'s dressed trim: the cap course under the walk, the merlons\' rounded tops, the parapet\'s top. Empty = the game\'s #DEC09F' },
    { key: 'wall_colors.cap', group: 'World', label: 'Wall walk', type: 'swatch', def: '#A58266', help: 'the fort wall\'s walk along the top and the towers\' roofs. Empty = the game\'s #A58266' },
    { key: 'wall_colors.riser', group: 'World', label: 'Wall shade', type: 'swatch', def: '#7A604E', help: 'the fort wall\'s shaded sides: the steps where the walk climbs, the merlons\' sides, the cap course\'s underside. Empty = the game\'s #7A604E' },
    { key: 'wall_colors.beams', group: 'World', label: 'Wall beams', type: 'swatch', def: '#4F3626', help: 'the vigas: the round wooden beam ends along the fort wall under its walk and on the towers. Empty = the game\'s #4F3626 (pass 80; replaces the boulders)' },
    // pass 72 (lane BOSS; Garry: "Boss HP should be pegged to Player DPS ... It shouldn't be 1 to 1"): the boss's HP times
    // (DPS / its reference) ^ exponent, held between min and max (WaveTimeline.boss_hp_scaling; boss_scaling.js draws the
    // references and the chart under these rows)
    // pass 83 (lane SCALE; Garry: "at least 25 seconds of Player's FULL DPS on Tumbleweed king ... 40s for the next and a
    // full minute to the last one"): the mode on top; the pass 72 numbers below only show (and only count) in the "dps" mode
    { key: 'boss_hp_scaling.mode', group: 'Boss HP', label: 'Boss HP is set by', type: 'select', def: 'seconds', options: [
      { v: 'seconds', label: 'seconds of full DPS', help: 'when a boss arrives its HP becomes the hero\'s FULL DPS right then × the boss\'s seconds below (never less than its data HP): Garry\'s 25 / 40 / 60 s' },
      { v: 'dps', label: 'pegged to recent DPS (pass 72)', help: 'the old way: (the hero\'s real damage a second over the last window ÷ the boss\'s reference DPS) ^ exponent × its data HP, between the floor and the ceiling' },
    ], help: 'how a boss\'s HP is worked out when it arrives. "Seconds of full DPS" (the game\'s default since pass 83): the boss takes at least that many seconds to kill if every shot of every weapon lands on it; a real fight is longer (misses, dodging, its minions, burrows). "Pegged to recent DPS" is pass 72\'s rule (its five numbers show below when you pick it). Empty = the game\'s: seconds' },
    { key: 'boss_hp_scaling.enabled', group: 'Boss HP', label: 'Scale boss HP', type: 'bool', def: true, help: 'on: the bosses\' HP follows the rule picked above; off: every boss keeps the HP its own JSON gives it (hp × hp_mult_per_stage per stage × the stage multiplier), whatever the hero deals. The debug arena never scales. Empty = the game\'s: on' },
    { key: 'boss_hp_scaling.exponent', group: 'Boss HP', label: 'Exponent', type: 'number', min: 0, max: 1, step: 0.05, def: 0.5, showIf: (tl) => BossModel.modeOf(tl) === 'dps', help: '(pegged mode only) how much of the extra DPS the boss soaks: 0.5 = its HP grows with the square root of the hero\'s DPS (twice the reference DPS: 1.41× the HP, the fight 29% shorter); 1 = every fight lasts as long as at the reference; 0 = never scaled' },
    { key: 'boss_hp_scaling.window', group: 'Boss HP', label: 'DPS window (s)', type: 'number', min: 5, max: 180, step: 5, def: 45, showIf: (tl) => BossModel.modeOf(tl) === 'dps', help: '(pegged mode only) how far back the game looks for the hero\'s DPS when the boss arrives: the damage his hits really took off creatures over these seconds ÷ the seconds (a hit on a nearly dead goblin counts only what it had left)' },
    { key: 'boss_hp_scaling.min', group: 'Boss HP', label: 'Floor ×', type: 'number', min: 0.05, max: 1, step: 0.05, def: 0.75, showIf: (tl) => BossModel.modeOf(tl) === 'dps', help: '(pegged mode only) the least the data HP is multiplied by, however weak the hero: 0.75 = at most a quarter off. A hero far below a boss\'s reference DPS always gets the floor' },
    { key: 'boss_hp_scaling.max', group: 'Boss HP', label: 'Ceiling ×', type: 'number', min: 1, step: 0.25, def: 3, showIf: (tl) => BossModel.modeOf(tl) === 'dps', help: '(pegged mode only) the most the data HP is multiplied by, however strong the hero: 3 = reached at 9× the reference DPS with the exponent 0.5' },
    // pass 83 (lane SCALE; Garry: "add a modifier for the enemy HP scaling with the power level of the Player ... Default
    // scaling is 1, meaning no scaling at all"): WaveTimeline.power_hp_scaling / power_hp_max (power_card.js draws the
    // formula box and the chart under them)
    { key: 'power_hp_scaling', group: 'Hero power', label: 'Enemy HP by power', type: 'number', min: 0, max: 3, step: 0.05, def: 1, help: 'every ordinary creature\'s HP × (the hero\'s power) ^ (this − 1): 1 = no scaling at all (the default); 2 = the HP grows in step with his power (power 4: ×4 HP); 1.5 = with its square root (power 4: ×2); below 1 the creatures get softer as he grows. Never the bosses (they have the Boss HP card) nor the Elites by their kind. Read when a roster row or a wave first spawns, like the HP curve and the hero level, and kept for that row. Power 1 = a fresh level-1 Drifter: see "How power is calculated" below' },
    { key: 'power_hp_max', group: 'Hero power', label: 'Most HP × by power', type: 'number', min: 1, step: 0.5, def: 10, help: 'the cap on that multiplier (and 1 ÷ it the least, below 1): 10 = never more than ten times the HP, however strong the hero. Empty = the game\'s 10' },
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
  const SCALAR_GROUPS = ['Stages', 'Cap', 'Spawning', 'Portal', 'Scaling', 'XP per level', 'Coloured specials', 'Boss HP', 'Hero power', 'Targeting', 'Endless', 'Items', 'World'];

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
    // pass 84 (lane TIMELINE): the view lanes (kind 'view': computed, nothing to drag) and the floor
    { id: 'alive', kind: 'view', name: 'On screen', text: 'Pass 84: creatures alive at each second (a count of bodies): the estimate\'s crowd as a filled area (the hell channel\'s on top in red), the Sim\'s real count dashed when the map has a Sim, the cap turned into bodies (the cap counts load units: cap ÷ the average load per body alive) and the floor curve dotted. Red behind the lane where the regular channel\'s load is at the cap: rows that wanted to spawn starve there (hover it for which). The section\'s "How it is worked out" box has the recipe.' },
    { id: 'challenge', kind: 'view', name: 'Challenge', text: 'Pass 84: seconds of the hero\'s own damage it takes to kill everything on the screen = the crowd\'s HP on screen ÷ the hero\'s damage a second. The crowd\'s HP: every living creature (the estimate) × its HP in play (its row\'s HP fixed from the row\'s start × the stage multiplier × creature_hp_mult × the hero level box; a coloured special its special HP; bosses left out). The hero\'s damage: the Sim\'s DPS when there is a Sim, else 20.4 × a typical power curve. Dashed: the Sim\'s own seconds to clear (keep_up). Green / amber / red: under the easy limit, up to the hard limit, past it (the boxes in the section\'s header). Red dots: the Sim\'s deaths.' },
    { id: 'composition', kind: 'view', name: 'Composition', text: 'Pass 84: who the crowd is made of: each creature\'s share of the creatures alive (or, switched in the section\'s header, of what spawned in the past N seconds), stacked to 100%. Estimate or Sim. Hover for every creature\'s count and share.' },
    { id: 'floor', kind: 'edit', name: 'Floor', text: 'Pass 84: the floor curve (floor_curve): the least creatures alive on the regular channel; while fewer are alive the director draws the continuous rows at once until it is met, within the cap. Drag a point, double-click the line to add one, a point to remove it; "+ Floor" starts one. Empty = no floor.' },
    { id: 'cap', name: 'Cap', text: 'The ceiling: how many creatures may be alive (in cap load units; the fodder counts half). The points are the control points of the live cap curve: linear between them, flat before the first and after the last. They are not spawn events: the director spawns up to the cap on its own interval (spawn_interval), in bursts of burst_min to burst_max. Drag a point; double-click the line to add one, double-click a point to remove it. The dashed line is the hard cap of bodies, the dips are the boss fights\' share.' },
    { id: 'hp_act', name: 'Actual HP ×', text: 'Pass 58: the HP multiple the creatures really come with at each second, on the HP × lane\'s scale while the rows fit under it (higher multiples give it its own, up to 1.5 times as tall, and a ▲ with the number marks anything past its top; the curve you drag keeps its scale). A row\'s numbers are fixed from its start (Garry: "a single wave of those enemies will stay consistent for the duration of their spawns"): a row without an HP override keeps the HP curve of the second it starts for its whole life, a row with one keeps its own HP (its multiple is that HP over the creature\'s). The solid line is the average over the roster rows and wave alternatives spawning round that second, each weighted by how many it spawns there (the Spawned so far estimate); the dashed line is the largest; the intended curve is dotted behind them. Hover for the rows behind the numbers. The stage multiplier, creature_hp_mult and the hero level come on top in the game.' },
    { id: 'hp', name: 'HP ×', text: 'The multiplier on every creature\'s health over the run clock (hp_curve): a line like the cap\'s, as manual points you drag, or a formula (linear, power, exponential) sampled onto it; the inspector switches. Absent, the lane shows the legacy hp_growth / hp_power formula. The stage multiplier and creature_hp_mult come on top of it (the readout shows the product). Since pass 58 a row reads it once, at its start (the Actual HP × lane shows what that makes).' },
    { id: 'dmg_act', name: 'Actual ATK ×', text: 'Pass 58: the same for damage: each row\'s ATK multiple, the damage curve at its start or its own damage over the creature\'s, averaged by the spawns round each second (solid), the largest (dashed), the intended ATK × curve dotted behind.' },
    { id: 'dmg', name: 'ATK ×', text: 'The multiplier on every creature\'s damage over the run clock (damage_curve), the same two modes. Absent = 1 all run. The stage multiplier and creature_damage_mult come on top. Since pass 58 a row reads it once, at its start, and every later bite or shot of its creatures keeps that.' },
    { id: 'roster', name: 'Roster', text: 'The stream under the ceiling: whenever there is room, a burst is drawn from the rows open at that second by their weights. A bar runs from its start to its end (or the run\'s end); the filled area inside it is the row\'s presence over time (its weight), with a point per keyframe: drag a point up or down (or along), double-click the bar to add one, a point to remove it. Red bars are the hell channel, a wrench marks stat overrides, a chip the art variant. Drag a bar to move it, its right edge to end it. The grip and the arrows at the left reorder the rows (display only: the game ignores the order). Pass 81, the yellow etches along the foot of each bar show when its creatures come: a tall tick at each wave of a row paced as Waves (the row form\'s Pacing; the chip says every how many seconds and how many); pass 83, a short tick at each draw of a continuous row (the spawn check, every 0.7 s on Red Canyon, or the row\'s own Draw every), where its weight is above 0, drawn as a dotted line where they are closer than 3 px at this zoom; both on an Also continuous one. Wave ticks closer than 3 px are thinned (every second, third ... one shown, never merged into a line): zoom in to see each. Hover a bar for the share of everything spawned in the past N seconds this row made (N is the box next to Snap on), hover a tick for that wave or that draw. Pass 84: the lane is Spawn rows: one kind of row for every way to spawn (continuous, waves every N s, once; swarms, coloured elites and Elites every are rows), grouped by stage or role (each group folds), each bar coloured by its role, saying how many and how often, its HP and ATK at its start and its badges (elite, special, banner, pattern, hell).' },
    { id: 'waves', name: 'Waves (old)', text: 'Pass 84: the old waves[] list (a row paced as Waves does the same; an old map\'s blocks are read as rows on load). Scripted windows on top of the roster: from t, a burst every few seconds until the count or the end. Stripes are the alternatives (one is rolled per run); "no cap" means it spawns on top of the crowd. Drag to move, drag the right edge to end, click to edit. Pass 81: a yellow tick along the foot of a block at each burst (thinned under 3 px apart, like the roster\'s).' },
    { id: 'events', name: 'Events', text: 'Pass 84: the bosses (skull) and the Elite mini-bosses (crown); the portal after each boss is marked under it (click it for its settings); an old map\'s swarm and coloured-elite events are read as spawn rows. Before pass 84, one-off moments: bosses (skull), Elites (crown), coloured elites (star), the repeating elite timer (arrows with a dotted trail), swarms (ring). Whiskers are the jitter, a faded marker a chance under 100%. Drag to move.' },
    { id: 'specials', name: 'Specials', text: 'The specials\' clock (the Vulture Raider, the harpooner): from its start, one at a time, the next a random interval after the last one dies. Edit it in Settings or by clicking the band.' },
    { id: 'paths', name: 'Mutations', text: 'When each stage\'s mutation offers fall due (seconds into the stage): each comes at the hero\'s next level-up, in place of the three cards (pass 79). Edit in Settings.' },
  ];

  // pass 84 (lane TIMELINE; Garry: "allow for the option to collapse some sections ... Mark somehow (in a subtle way)
  // which sections are view only, and which are tools for editing things"): the Timeline's sections, top to bottom.
  // kind 'view' = drawn from the map, the estimate and the Sim, nothing to drag (an eye, a recessed background); 'edit'
  // = tools that change the map (a pencil, the normal surface). The Instructions tab lists them from here.
  const SECTIONS = [
    { id: 'controls', kind: 'edit', name: 'Ruler and controls', what: 'the run clock and its stages (the ruler stays when this is collapsed); the page settings every chart reads: the estimate\'s kill rate, boss fight and portal wait, the Sim to show, how the spawn rows are grouped and coloured', lanes: [] },
    { id: 'onscreen', kind: 'view', name: 'On screen', what: 'how many creatures are alive each second, against the cap and the floor; red where the cap is full', lanes: ['alive'] },
    { id: 'challenge', kind: 'view', name: 'Challenge', what: 'seconds of the hero\'s damage it takes to clear the screen (the crowd\'s HP ÷ his damage a second)', lanes: ['challenge'] },
    { id: 'composition', kind: 'view', name: 'Composition', what: 'who the crowd is made of, as % of it', lanes: ['composition'] },
    { id: 'spawned', kind: 'view', name: 'Spawned so far', what: 'every creature a run has spawned by each second (a running total, the estimate)', lanes: ['spawned'] },
    { id: 'rows', kind: 'edit', name: 'Spawn rows', what: 'every creature group with its schedule (continuous, waves, once): drag a bar, click it to edit everything about it', lanes: ['roster', 'waves'] },
    { id: 'events', kind: 'edit', name: 'Events', what: 'bosses, Elite mini-bosses, the specials\' clock, the portal waves and the mutation offers', lanes: ['events', 'specials', 'paths'] },
    { id: 'curves', kind: 'edit', name: 'Curves', what: 'the cap, the floor, the HP × and ATK × curves (drag their points; the Actual lanes show what the rows really carry)', lanes: ['cap', 'floor', 'hp_act', 'hp', 'dmg_act', 'dmg'] },
    { id: 'warnings', kind: 'view', name: 'Warnings', what: 'what the estimate and the checks found, each with a link to the second and the row', lanes: [] },
  ];
  // the lanes that only show (an eye on their label, a recessed background)
  const VIEW_LANES = ['alive', 'challenge', 'composition', 'spawned', 'hp_act', 'dmg_act'];

  return { SECTIONS, VIEW_LANES, ENEMY_MODES, XP_TYPES, roster, wave, alt, event, EVENT_TYPES, OVERRIDES, OVERRIDE_GROUPS, OVERRIDE_GROUP_HELP, SCALARS, SCALAR_GROUPS, CURVE, CURVE_KINDS, SIDE_MODES, SPECIALS, PICKUP_ROW, PATTERNS, SWARM_PATTERNS, CHANNELS, LANES, PACES };
})();
