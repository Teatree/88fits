'use strict';
// Pass 66 (lane P): the field tables and rules of the asset editors (enemy / elite / boss, hero, weapon, evolution,
// line / passive item, mutation), in fields.js's row vocabulary (key, label, type, help, def, min, max, step, int, options,
// required) plus `section` (the fold a row sits in), `only(doc, ctx)` (shown when true), functional `options(vocab)`,
// `ph(doc, ctx)` (a placeholder computed from the document), `group` (the sound ids' prefix), `kind` (an id_select's
// kind), `target` / `stats` (a stat_effects list's fixed target and stat set). New types: slug, readonly, textarea,
// stat_effects, level_steps, anims, fps_table, sfx, params_json, json, id_select, driver, checklist, tags,
// pickup_weights, enemy, attacks, look_grid, icon_preview, path_strip, quest_lock, band, trait_preview, shadow_scale.
// DOM-free: selftest_P.py loads it under Node (module.exports). The vocabularies carry defaults so the forms render
// without the server; `GET /api/vocab` (lane S) is merged over them. Every list is listable, not extendable: a new brain,
// attack, behaviour or stat needs code (the page says "ask Claude").
const AFIELDS = (() => {
  const M = (typeof AssetsModel !== 'undefined') ? AssetsModel : require('./assets_model.js');
  const isObj = M.isObj, num = M.num;
  const opt = (v, label, help) => ({ v, label: label == null ? v : label, help: help || '' });

  // ------------------------------------------------------------------ vocabularies (defaults; /api/vocab wins where it answers)

  const VOCAB = {
    brains: [opt('chase', 'chase', 'walks at the hero'), opt('flock', 'flock', 'walks at the hero, keeps with its pack'), opt('kite', 'kite', 'keeps its distance and shoots (the ranged block)'),
      opt('charge', 'charge', 'winds up and rushes (the charge block)'), opt('kamikaze', 'kamikaze', 'runs in and blows up (the kamikaze block)'), opt('artillery', 'artillery', 'stands off and fires rockets (the artillery block)'),
      opt('boss', 'boss', 'runs the attack script (the boss block)'), opt('dummy', 'dummy', 'the arena dummies: stands still'), opt('ambush', 'ambush', 'hides in the sand until the hero is near (the ambush block, ranged for its silk)'),
      opt('caster', 'caster', 'keeps away and casts from the attack script (caster + boss blocks)'), opt('support', 'support', 'heals and frenzies the crowd round it (the support block)'),
      // pass 73 (lane SNIPER)
      opt('sniper', 'sniper', 'walks in like the kite to its range (never runs), freezes to aim a gathering red-line laser across the map (the sniper block)')],
    archetypes: [opt('walker', 'walker', 'a label'), opt('swarmer', 'swarmer', 'a label'), opt('spitter', 'spitter', 'a label'), opt('brute', 'brute', 'a label'), opt('tank', 'tank', 'a label'), opt('runner', 'runner', 'a label'),
      opt('elite', 'elite (mini-boss)', 'its HP follows elite.hp_mult_per_stage, a crown, a chest every time, never stunned or grabbed'), opt('boss', 'boss', 'the stage boss: boss.hp_mult_per_stage, the bar, the skull, the purse')],
    telegraphs: [opt('none'), opt('line', 'line', 'a red line ahead'), opt('ring', 'ring', 'a ring round the creature'), opt('ring_at_hero', 'ring at the hero', 'a ring where the hero stands (slam_at, burrow and boulder need it)'),
      opt('sector', 'sector', 'a wedge ahead'), opt('fan', 'fan', 'several lines over a spread'), opt('spokes', 'spokes', 'lines all round')],
    shotKinds: [opt('', 'spit (the default)'), opt('pellet'), opt('spike'), opt('shard'), opt('harpoon', 'harpoon', 'set by `harpoon: true` in the game')],
    badges: [opt('', 'none (the default)'), opt('crown', 'crown', 'shown for the elite archetype only'), opt('skull'), opt('gear'), opt('none', 'none (explicit)')],
    faces: [opt('right', 'right', 'painted heading screen-right, mirrored heading left (the default)'), opt('left', 'left', 'painted heading left: the mirror is inverted'), opt('straight', 'straight', 'never mirrored')],
    pronouns: [opt('he'), opt('she'), opt('they')],
    specials: [opt('cannot_stop', 'cannot stop', 'Player.gd: he never stands still'), opt('momentum', 'momentum', 'speed and attack damage climb while he is not hit (the momentum block)'),
      opt('auto_magnet', 'auto magnet', 'gems come to him on their own'), opt('motherlode', 'motherlode', 'x1.5 gold from the Strongbox and extraction')],
    // pass 69 (lane UI wired the purchase loop): Registry.hero_state reads these; an unlock quest (Requirement below) gates either
    availability: [opt('available', 'free', 'owned from the start, nothing to pay; with a requirement: owned the moment its quest is done'),
      opt('purchase', 'to buy', 'on the title and in the hero drawer as a black silhouette: locked until his requirement is done (none = on sale at once), then BUY for the price'),
      opt('hidden', 'hidden', 'out of play: not on the title, not in the drawer; his perks and hero mutation hidden too')],
    currencies: [opt('gold', 'gold', 'coins: the only currency Save.buy_hero spends')],
    rarities: [opt('common'), opt('uncommon'), opt('rare'), opt('epic'), opt('legendary', 'legendary', 'no item uses it; the tests pin four rarities among passive items')],
    rarityPlate: { common: '#d2cfc7', uncommon: '#8cc97a', rare: '#6b9fd8', epic: '#a585c8', legendary: '#e0a060' },
    behaviors: ['Beam', 'ConeWave', 'GravityGun', 'LaserBeam', 'Lobber', 'MineLayer', 'MissilePod', 'Orbiter', 'ProjectileEmitter', 'Smasher', 'Spawner', 'SunScepter', 'Thruster'].map((b) => opt(b))
      // pass 69: the Salt's patches laid behind the hero (lane SALT) and the Frisbee's curving discs (lane FRIS)
      .concat([opt('SaltShaker', 'SaltShaker', 'pass 69, the Salt: a shaker floats round the hero and pours patches behind him that hurt what stands in them (params: salt, shaker)'),
        opt('Frisbee', 'Frisbee', 'pass 69: discs thrown at a creature on an arc bending left or right at random, cutting through everything to the end of their range (params: bend, fan, falloff, disc, carry, loop)'),
        // pass 95 (lane BREATH): the Dragon's Breath
        opt('FireBreath', 'FireBreath', 'pass 95, the Dragon\'s Breath: every cooldown the hero breathes a cone of fire from his face where he faces for `duration` s (+1 s per amount past the first); whatever stands in it takes `damage` every second and catches fire (params: breath)')]),
    targeting: [opt('nearest'), opt('priority', 'priority', 'the strongest enemy nearby'), opt('densest'), opt('densest_healthy', 'densest healthy', 'the Molotov and Skull Rain: the densest crowd of healthy enemies'), opt('orbit'), opt('random'), opt('healthy'), opt('forward'), opt('ground')],
    mutationKinds: [opt('element'), opt('volume'), opt('motion'), opt('stance', 'stance', 'no mutation uses it yet'), opt('hero', 'hero', 'one hero\'s own: needs `hero`')],
    elements: [opt('', 'none'), opt('fire'), opt('poison')],
    ops: [opt('add', 'add', 'base + value'), opt('mul', 'mul', 'x (1 + value): 0.25 is +25%'), opt('set', 'set', 'replaces the base')],
    targets: [opt('self', 'self', 'the item\'s own sheet'), opt('player', 'player', 'the hero\'s sheet'), opt('all_weapons', 'all weapons'), opt('weapon:', 'weapon:<id>', 'one weapon by id'), opt('tag:', 'tag:<tag>', 'every weapon with the tag')],
    questTypes: [opt('kills_with_weapon', 'kills with a weapon', '{weapon, count} across runs'), opt('kills_of_enemy', 'kills of a creature', '{enemy, count} across runs'), opt('open_chests', 'chests opened', '{count}'),
      opt('evolve_any', 'any evolution', '{count}'), opt('reach_level', 'reach a level', '{level} in one run'), opt('survive_minutes', 'survive minutes', '{minutes} in one run'),
      opt('survive_minutes_no_lift', 'survive minutes without a lift', '{minutes}'), opt('kills_in_run_of_enemy', 'kills of a creature in one run', '{enemy, count}'), opt('extract_after_stage', 'extract after a stage', '{map, stage}'),
      opt('kill_boss', 'kill a boss', '{map, stage}'), opt('kills_total', 'kills in all', '{count}'), opt('runs_total', 'runs in all', '{count}'), opt('pickups_total', 'power-ups in all', '{count}'), opt('gold_total', 'gold in all', '{count}'), opt('reach_stage', 'reach a stage', '{stage}')],
    screens: [opt('', 'by the placeholder colour'), opt('green'), opt('blue')],
    favouriteBonus: [opt('level', 'arrives at a level', '{value}'), opt('effects', 'arrives with effects', '{effects}')],
    passiveBonus: [opt('max', 'arrives maxed'), opt('level', 'arrives at a level', '{value}'), opt('effects', 'arrives with effects', '{effects}')],
    deaths: [opt('', 'tilt (free fall clip)'), opt('clip', 'clip', 'a painted dead still and a first-last-frame fall'), opt('squash'), opt('collapse', 'collapse', 'dead_hint must describe a heap'), opt('shatter', 'shatter', 'the painting breaks into pieces that fall into a pile (pass 91; nothing painted, dead_hint unused)'), opt('pose:death_back', 'pose: death_back'), opt('pose:death_back_goblin', 'pose: death_back_goblin')],
    walks: [opt('', 'a video clip'), opt('hop', 'hop', 'procedural: no video')],
    stands: [opt('', 'as the driver stands'), opt('still', 'still', 'the painting\'s pose differs from the driver')],
    placeholderShapes: [opt('', 'round'), opt('wide'), opt('tall'), opt('round')],
    blinkTo: [opt('', 'a step away'), opt('screen', 'screen', 'the caster\'s keep / side distance')],
    directions: [opt(2, '2 (front and back)'), opt(8, '8 (side and diagonals too)')],
    sounds: null,     // ids from /api/vocab (soundmap.json); null = unknown here
    pickups: null,
    elites: null,
    combos_seen: null,
  };

  // the player stats (StatSheet.PLAYER_DEFAULTS + the four the systems read) and the weapon stats, with TextGen's names
  const playerStats = () => Object.keys(M.PLAYER_DEFAULTS).concat(M.PLAYER_EXTRA);
  const weaponStats = () => Object.keys(M.WEAPON_DEFAULTS).concat(M.WEAPON_EXTRA);
  function statOptions(which, vocab) {
    const extra = vocab && vocab.stats ? Object.keys(vocab.stats) : [];
    const ids = which === 'weapon' ? weaponStats() : which === 'player' ? playerStats() : playerStats().concat(weaponStats());
    const all = Array.from(new Set(ids.concat(which === 'weapon' ? [] : extra)));
    // pass 69: a stat with a help line (the new passive items' stats) says what it does
    return all.map((s) => ({ v: s, label: M.statName(s, vocab), sub: `${s} · ${M.statKind(s, vocab)}`, help: `${s}: ${M.statKind(s, vocab)}${M.statHelp && M.statHelp(s, vocab) ? ' · ' + M.statHelp(s, vocab) : ''}` }));
  }
  const statKnown = (s, which, vocab) => {
    const vp = vocab && Array.isArray(vocab.player_stats) ? vocab.player_stats.map((x) => (typeof x === 'string' ? x : x.v || x.id)) : null;
    const vw = vocab && Array.isArray(vocab.weapon_stats) ? vocab.weapon_stats.map((x) => (typeof x === 'string' ? x : x.v || x.id)) : null;
    const isW = weaponStats().includes(s) || (vw && vw.includes(s));
    const isP = playerStats().includes(s) || (vp && vp.includes(s)) || (vocab && vocab.stats && !Array.isArray(vocab.stats) && !!vocab.stats[s]);
    if (which === 'weapon') return isW;
    if (which === 'player') return isP;
    return isP || isW;
  };
  /** the stat set an effect is checked against: a target that reaches weapons (all_weapons, weapon:<id>, tag:<tag>) takes
   *  the weapon stats whatever list it sits in (Kindling's fire_damage to all weapons); target player the player's */
  const statSetFor = (e, which) => {
    const t = String((e && e.target) || '');
    if (t === 'all_weapons' || t.startsWith('weapon:') || t.startsWith('tag:')) return 'weapon';
    if (t === 'player') return which === 'weapon' ? 'any' : 'player';
    return which;
  };

  // weapon defaults a base stat box shows as its placeholder (WeaponInstance.gd:106-107)
  const BASE_DEFAULTS = Object.assign({}, M.WEAPON_DEFAULTS, { fire_damage: 0, fire_duration: 0, fire_spread: 0, poison_damage: 0, poison_stacks: 0, poison_duration: 0 });
  const BASE_KEYS = ['damage', 'cooldown', 'amount', 'pierce', 'area', 'speed', 'duration', 'knockback', 'chains', 'range', 'spread_deg', 'orbit_radius', 'lifetime', 'fire_damage', 'fire_duration', 'fire_spread', 'poison_damage', 'poison_stacks', 'poison_duration'];

  // the params keys each behaviour reads (verified by grep over game/core/behaviors/*.gd and the systems: the UX draft §2.4)
  const PARAMS_KEYS = {
    Beam: ['echo_zap', 'follow', 'zone'],
    ConeWave: ['cone', 'familiar', 'tinnitus'],
    GravityGun: ['familiar', 'gravity'],
    LaserBeam: ['beam', 'familiar'],
    Lobber: ['death_of', 'death_pool', 'halo', 'land_blast', 'model', 'model_metallic', 'model_roughness', 'model_scale', 'sticky', 'tint', 'bounce', 'bomblets', 'bomblet_damage_mult', 'burst_spawn',
      // pass 76 (lane DYN): the dynamite's fuse, its models by form and colour, the Drifter's mass mini crits
      'fuse', 'models', 'model_form', 'model_colour', 'fuse_tip', 'mass_mini',
      // pass 79 (lane WORLD): the Dynamite Stick thrown ahead of its crowd
      'lead'],
    MineLayer: ['extra_supply', 'jackrabbit', 'lay_ahead', 'max_mines', 'trigger_radius', 'spring'],
    MissilePod: ['cluster_spin', 'familiar', 'hawk', 'missile', 'overpressure', 'pollen', 'pressure', 'cluster', 'blast_fx'],
    Orbiter: ['breathe', 'gyro', 'lasso', 'rust', 'rust_patina', 'side_knock', 'solid_ring', 'spin_speed', 'strike'],
    ProjectileEmitter: ['aura', 'burst', 'burst_gap', 'double_every', 'double_gap', 'double_tap', 'drum_axis', 'drum_scale', 'drum_step', 'familiar', 'fan_step_deg', 'fire_blind', 'hip_shot', 'look', 'momentum_rounds', 'no_shells', 'radius', 'radius_mult', 'shockwave', 'silver', 'speed_mult', 'sweep_deg', 'scatter_deg', 'tint', 'blast',
      'amount_mode', 'free_throw', 'tracer_color',
      // pass 69: Alley-Oop's launch and the ball's Heat look (lane BB), May's Trigger Happy (lane HERO)
      'launch', 'heat_look', 'fire_without_target', 'stream'],
    Smasher: ['giant_slayer', 'smash', 'thor'],
    Spawner: ['max_turrets', 'max_turrets_mult', 'turret', 'turret_fire_rate', 'magnet', 'tracer', 'focus'],
    SunScepter: ['familiar', 'gold_dust', 'handle_ring', 'shine', 'staff_tint', 'sun', 'zenith'],
    Thruster: ['crit_refund', 'crit_stroke', 'razor', 'riposte', 'stunned_mult', 'thrust', 'trail_color'],
    // pass 69: the Salt (lane SALT) and the Frisbee (lane FRIS)
    SaltShaker: ['salt', 'shaker'],
    Frisbee: ['bend_deg', 'bend_per_extra', 'carry', 'disc', 'falloff', 'fan_deg', 'glide_seconds', 'height', 'hit_radius', 'loop', 'proc_mult', 'stun'],
    // pass 95 (lane BREATH): the Dragon's Breath (its blue fire is the shared fire_blue)
    FireBreath: ['breath'],
  };
  // keys WeaponInstance and the systems (ProjectileManager, Game, EnergyTraces, Mine) read for any behaviour
  const PARAMS_SHARED = ['final', 'glow', 'familiar', 'look', 'ricochet_any', 'mini_crit', 'fire_blue', 'ignite_chance', 'zenith', 'sticky', 'size_mult', 'silver', 'pollen', 'plant', 'pin', 'pierce_falloff', 'out_speed_mult', 'back_speed_mult',
    'return_damage_mult', 'return', 'second_pass', 'hip_shot', 'double_every', 'cone', 'burst_spawn', 'bounce', 'bomblets', 'bomblet_damage_mult', 'aura', 'wander', 'turn', 'trail', 'tracer',
    'tracer_life', 'tracer_width', 'tracer_clear', 'tracer_alpha', 'tracer_style', 'tracer_hot', 'trace', 'tint', 'thrust', 'telegraph', 'tail_fade', 'sun', 'split_scale', 'split_count', 'spiral', 'spent', 'cloud_mult', 'cloud_seconds', 'curare', 'hit_radius',
    'roll_radius', 'no_spin', 'trail_zone', 'life', 'gold_on_kill', 'speed_mult', 'radius_mult',
    // pass 67 (the basketball): ProjectileManager turns the ball home when its hits are spent and hands the catch over
    'return_on_hit', 'return_pierce', 'catch',
    // pass 95 (lane ITEMS): a weapon the "Fire forward" debug switch covers (core/systems/FireForward.gd)
    'fire_forward'];
  function paramsKnown(key, behavior) {
    return PARAMS_SHARED.includes(key) || (PARAMS_KEYS[behavior] || []).includes(key);
  }

  // ------------------------------------------------------------------ pass 69 (lane LE): typed params
  // Garry (pass 69): "make sure to update the LevelEditor and include instructions on how I would be able to use the newly
  // created tools". The params the pass's weapons and mutations read, as typed, explained fields above the JSON box (the
  // box stays for every other key). A group is one mechanism's keys: `behaviors` = the behaviours whose weapons show it
  // (a mutation shows its weapon's, an evolution its own); `show` 'always' (every weapon of that behaviour: its own knobs)
  // or 'family' (only when the weapon family is a ball, `ball(params)`) or 'set' (only where a key of it is set on the
  // document or its weapon; else offered under "+ typed group"); `present` = the keys that count as set (default: every
  // row's). Row keys are paths under `params`; `def` = the code's own default (the placeholder when nothing sets it; null
  // = absent means off); `src` = where the game reads them.
  const P = (key, label, type, def, help, extra) => Object.assign({ key, label, type, def, help }, extra || {});
  const isBall = (params) => isObj(params) && (isObj(params.catch) || String(params.amount_mode || '') === 'bounces');
  const PARAM_GROUPS = [
    { id: 'salt', label: 'Salt patches', behaviors: ['SaltShaker'], show: 'always', src: 'core/behaviors/SaltShaker.gd, core/systems/SaltPatches.gd',
      help: 'the white patches the Salt lays behind the hero; its base stats above are a tick\'s damage, the cooldown between pours, the amount (patches a pour), the area (× the radius) and the duration (seconds a patch lies)', rows: [
        P('salt.radius', 'Patch radius (m)', 'number', 1.4, 'a patch\'s radius at area 1 (radius × area × Size ×)', { min: 0.1, step: 0.1 }),
        P('salt.tick', 'Tick (s)', 'number', 0.5, 'seconds between damage ticks: every creature standing in any patch takes one hit a tick (two patches over it still hit once)', { min: 0.05, step: 0.05 }),
        P('salt.spacing', 'Spacing (m)', 'number', 1.2, 'metres between the patches of one pour, back along his way (the first 0.4 m behind his heels); standing still they go round his feet', { min: 0, step: 0.1 }),
        P('salt.max_patches', 'Most patches', 'int', 40, 'most patches lying at once; one more sends the oldest into its fade (it hurts nothing more)', { min: 1 }),
        P('salt.color', 'Colour', 'swatch', '#FFFFFF', 'the patches\' colour (Sea Salt #F4A3C4, Hiwa Kai #161616)'),
        P('salt.alpha', 'Opacity', 'number', 0.5, 'how solid the patches are, 0..1 (the bed between the grains is 60% of it): white, half see-through; the Salt sets 0.6 (the code\'s own is 0.5)', { min: 0, max: 1, step: 0.05 }),
        P('salt.contents', 'Shaker contents', 'swatch', '#F4F4F0', 'the salt inside the floating shaker (its Contents mesh); empty = the patch colour'),
        P('salt.duration_mult', 'Lasts ×', 'number', 1, '× a patch\'s seconds (Sea Salt 1.75, Hiwa Kai 2)', { min: 0.1, step: 0.05 }),
        P('salt.damage_mult', 'Damage ×', 'number', 1, '× a tick\'s damage (Sea Salt 0.95)', { min: 0, step: 0.05 }),
        P('salt.area_mult', 'Size ×', 'number', 1, '× the patch radius (Salt Spill 1.6, Hiwa Kai 1.8)', { min: 0.1, step: 0.05 }),
        P('salt.luck_mult', 'Power-up luck ×', 'number', 1, 'Thing About Luck: a creature killed while standing in a patch rolls the power-up drop at this factor (3; Hiwa Kai 4); any weapon\'s kill counts', { min: 0, step: 0.5 }),
        P('salt.momentum_on_enter', 'Full speed on walking in', 'bool3', false, 'Salt Flats (Jeżyk\'s hero mutation): walking INTO a patch from outside it puts his speed-up (momentum) at full at once; a patch laid round his feet counts only once he has walked out and back in'),
        P('salt.crystals.count', 'Crystals a patch', 'int', null, 'Hiwa Kai: little hard crystals strewn on every patch (7); empty or 0 = none', { min: 0 }),
        P('salt.crystals.color', 'Crystal colour', 'swatch', '#0B0B0D', 'Hiwa Kai: the crystals\' colour'),
        P('salt.crunch.mult', 'Crunch ×', 'number', null, 'Hiwa Kai: a creature that walks into the salt (it was not in it at the last tick) takes one extra hit of this × a tick\'s damage (2); empty = none', { min: 0, step: 0.5 }),
        P('salt.slow', 'Slow', 'number', 0, 'Hiwa Kai: creatures standing in the salt move this much slower (0.3 = 30%), refreshed every tick, at most 0.95', { min: 0, max: 0.95, step: 0.05 }),
      ] },
    { id: 'shaker', label: 'The floating shaker', behaviors: ['SaltShaker'], show: 'always', src: 'core/behaviors/SaltShaker.gd (art/props/salt_shaker.glb)',
      help: 'the 3D salt shaker that floats round the hero and gives a little shake at each pour', rows: [
        P('shaker.distance', 'Distance (m)', 'number', 1.2, 'how far from the hero it floats', { min: 0, step: 0.1 }),
        P('shaker.height', 'Height (m)', 'number', 1.25, 'how high over his feet', { min: 0, step: 0.05 }),
        P('shaker.orbit_speed', 'Orbit speed (rad/s)', 'number', 0.55, 'how fast it circles him (6.28 = one turn a second)', { min: 0, step: 0.05 }),
        P('shaker.bob', 'Bob (m)', 'number', 0.08, 'how far it bobs up and down', { min: 0, step: 0.01 }),
      ] },
    // pass 95 (lane BREATH): the Dragon's Breath's cone
    { id: 'breath', label: 'The breath', behaviors: ['FireBreath'], show: 'always', src: 'core/behaviors/FireBreath.gd',
      help: 'the cone of fire breathed from the hero\'s face where he faces; its base stats above are a tick\'s damage, the cooldown between breaths (the slowest in the game), the amount (+seconds_per_amount s of breath per point past the first), the duration (seconds a breath lasts), the range (the cone\'s length), the area (× the cone\'s width) and the burn (fire_damage every 0.6 s for fire_duration, fire_spread)', rows: [
        P('breath.cone_deg', 'Cone (°)', 'number', 50, 'the cone\'s width at area 1 (× the area stat; 360 = a full ring)', { min: 15, max: 360, step: 1 }),
        P('breath.tick', 'Tick (s)', 'number', 1.0, 'seconds between hits on a creature standing in the fire (the first the moment it is inside)', { min: 0.1, step: 0.1 }),
        P('breath.seconds_per_amount', 'Seconds per extra amount', 'number', 1.0, 'seconds of breath added for every point of amount past the first (Multishot, the amount buff)', { min: 0, step: 0.25 }),
        P('breath.max_seconds', 'Longest breath (s)', 'number', 6, 'the breath never lasts longer than this before Held Breath\'s doubling', { min: 0.5, step: 0.5 }),
        P('breath.wait', 'Wait (s)', 'number', 2, 'with the cooldown ready it waits this long for a creature to stand in the cone; then it breathes where he faces if anyone is within reach', { min: 0, step: 0.5 }),
        P('breath.knock', 'Shove a tick', 'number', 0, 'Backdraft: every tick also shoves the creature straight away from the hero with this force (through the map\'s hero share; 5 on Backdraft)', { min: 0, step: 0.5 }),
        P('breath.look.intensity', 'Fire intensity', 'number', 1, 'the flames\' size and count (Backdraft 1.5, the Fire Eater 1.8)', { min: 0.1, step: 0.1 }),
        P('breath.still.seconds', 'Held Breath: still for (s)', 'number', null, 'Held Breath: an attack that starts after the hero has stood still and unhit this long is a held breath; empty = no Held Breath', { min: 0, step: 0.5 }),
        P('breath.still.duration_mult', 'Held Breath: lasts ×', 'number', 2, 'a held breath lasts this many times as long', { min: 1, step: 0.25 }),
        P('breath.still.damage_mult', 'Held Breath: tick ×', 'number', 1.5, 'standing in a held breath\'s fire deals this many times the tick', { min: 0, step: 0.25 }),
        P('breath.still.ring', 'Held Breath: all round', 'bool3', true, 'a held breath comes from all sides of his face (a full ring)'),
      ] },
    { id: 'frisbee_flight', label: 'Flight', behaviors: ['Frisbee'], show: 'always', src: 'core/behaviors/Frisbee.gd',
      help: 'how the discs fly: at a creature (the nearest in range, else ahead), bending left or right at random; its base stats above are damage, cooldown, amount (discs a volley), speed, range and knockback', rows: [
        P('bend_deg', 'Bend (°)', 'number', 25, 'how far off the aim line each disc leaves, to a side picked at random per disc', { min: 0, step: 1 }),
        P('bend_per_extra', 'More bend per extra disc (°)', 'number', 12, 'added to the bend for every disc past the first in a volley (3 discs = 25 + 2 × 12 = 49°)', { min: 0, step: 1 }),
        P('fan_deg', 'Fan (°)', 'number', 16, 'the gap between the aim lines of a volley\'s discs', { min: 0, step: 1 }),
        P('falloff.step', 'Drop-off a creature', 'number', 0.85, 'each creature a disc cuts after the first takes this share of the one before (steeper than the Revolver\'s: the disc never stops)', { min: 0, max: 1, step: 0.05 }),
        P('falloff.floor', 'Drop-off floor', 'number', 0.25, 'the least share any creature takes', { min: 0, max: 1, step: 0.05 }),
        P('hit_radius', 'Cut radius (m)', 'number', 0.55, 'how far from the disc\'s centre it cuts (× its size × area), plus the creature\'s own radius', { min: 0.05, step: 0.05 }),
        P('height', 'Flies at (m)', 'number', 1.0, 'how high above the sand it flies', { min: 0, step: 0.1 }),
        P('glide_seconds', 'Glide (s)', 'number', 0.45, 'after its range it slows, sinks and fades this long, hitting nothing', { min: 0, step: 0.05 }),
      ] },
    { id: 'disc', label: 'The disc (its look)', behaviors: ['Frisbee'], show: 'always', src: 'core/behaviors/Frisbee.gd (Frisbee.disc_mesh: built in code)',
      help: 'the disc drawn in flight: no held object, only the spinning disc', rows: [
        P('disc.look', 'Look', 'select', 'plain', 'plain = the neon lime plastic frisbee; razors = Poison Razors\' hot-pink disc with razor blades round the rim; saucer = the Flying Saucer\'s chrome and pink saucer', { options: [opt('plain', 'plain'), opt('razors', 'razors'), opt('saucer', 'saucer')] }),
        P('disc.size', 'Radius (m)', 'number', 0.36, 'the disc\'s radius (× Size × and the area stat)', { min: 0.05, step: 0.02 }),
        P('disc.size_mult', 'Size ×', 'number', 1, 'Carry\'s × 1.5 (it also widens the cut)', { min: 0.1, step: 0.1 }),
        P('disc.albedo', 'Colour', 'swatch', '#B8FF2A', 'the plastic (the saucer\'s chrome tint)'),
        P('disc.emission', 'Glow colour', 'swatch', '#7CFF00', 'the faint glow and the trail (the saucer\'s pink top and razors)'),
        P('disc.energy', 'Glow strength', 'number', 0.8, 'how bright the glow is', { min: 0, step: 0.1 }),
        P('disc.spin', 'Spin (rad/s)', 'number', 16, 'how fast it spins flat', { min: 0, step: 1 }),
        // pass 95 (lane ITEMS): the trail is a block, one style per look (Frisbee.trail_params); an old `trail: true` reads as
        // the look's own style and becomes a block when a row below is set
        P('disc.trail.style', 'Trail style', 'select', null, 'the trail behind the disc: streak = one faint pale ribbon with a brighter thread (the plain disc), sparks = two thin bright lines off the rim and short sparks flicking out (Poison Razors), glow = a wide soft glow with a brighter core (the Flying Saucer), none = no trail; empty = the look\'s own (plain streak, razors sparks, saucer glow)', { options: [opt('streak', 'streak'), opt('sparks', 'sparks'), opt('glow', 'glow'), opt('none', 'none')] }),
        P('disc.trail.length', 'Trail length (s)', 'number', null, 'seconds the trail lingers behind the disc (a point every 0.025 s); empty = the style\'s own (streak 0.4, sparks 0.32, glow 0.48)', { min: 0.05, step: 0.05 }),
        P('disc.trail.width', 'Trail width (× radius)', 'number', null, 'the ribbon\'s full width in disc radii, so a bigger disc (Carry) trails wider; for sparks the sparks\' length; empty = the style\'s own (streak 1.5, sparks 0.6, glow 2.2)', { min: 0, step: 0.1 }),
        P('disc.trail.alpha', 'Trail opacity', 'number', null, 'how solid the trail is at the disc, 0..1, fading to nothing at its end; empty = the style\'s own (streak 0.6, sparks 0.9, glow 0.45)', { min: 0, max: 1, step: 0.05 }),
        P('disc.trail.colour', 'Trail colour', 'swatch', null, 'the trail\'s colour; empty = the glow colour above lerped toward white (streak 45%, sparks 30%, glow 20%)'),
        P('disc.haze', 'Poison haze', 'bool3', false, 'the Flying Saucer\'s faint green poison haze under it'),
      ] },
    { id: 'carry', label: 'Carry', behaviors: ['Frisbee'], show: 'always', src: 'core/behaviors/Frisbee.gd',
      help: 'Carry (the volume mutation): the first creature a disc hits may ride it to the end of the flight and drop off there; never a boss, an Elite, an elite-modded or an ungrabbable creature; one a disc, and it still cuts the others on the way', rows: [
        P('carry.chance', 'Chance', 'number', null, 'how often the first creature hit is carried (Carry 0.1; the Flying Saucer 0.2); empty = never', { min: 0, max: 1, step: 0.05 }),
        P('carry.drop_hit', 'Drop hit ×', 'number', 0, 'the ride ends with a hit of this many times the disc\'s damage (the Flying Saucer 1)', { min: 0, step: 0.1 }),
      ] },
    { id: 'trick', label: 'Trick Shot and stun', behaviors: ['Frisbee'], show: 'always', src: 'core/behaviors/Frisbee.gd, Run.trick_proc_mult',
      help: 'Trick Shot (the motion mutation): this weapon\'s own life steal, crit chance, Cold Snap chance, Vulture chance and stun chance work this much better (only this weapon)', rows: [
        P('proc_mult', 'Procs ×', 'number', 1, 'life steal, crits, Cold Snap, Vulture and its stun × this (Trick Shot 1.25, the Flying Saucer 1.5): keep it modest', { min: 0, step: 0.05 }),
        P('stun.chance', 'Stun chance', 'number', null, 'a stun roll on every hit that does not kill; empty = none (no frisbee has one today)', { min: 0, max: 1, step: 0.05 }),
        P('stun.seconds', 'Stun (s)', 'number', null, 'how long the stun lasts', { min: 0, step: 0.1 }),
      ] },
    { id: 'loop', label: 'The loop (Flying Saucer)', behaviors: ['Frisbee'], show: 'always', src: 'core/behaviors/Frisbee.gd',
      help: 'once a flight the disc flies one full circle the way it is already turning, somewhere along its arc; absent = no loop', rows: [
        P('loop.radius', 'Loop radius (m)', 'number', null, 'the circle\'s radius (the Flying Saucer 1.3); empty = no loop', { min: 0.1, step: 0.1 }),
        P('loop.from', 'Loop from', 'number', 0.3, 'the earliest share of its range where the loop may start', { min: 0, max: 1, step: 0.05 }),
        P('loop.to', 'Loop to', 'number', 0.7, 'the latest share (it starts at random between the two)', { min: 0, max: 1, step: 0.05 }),
      ] },
    { id: 'launch', label: 'Launch (Alley-Oop)', behaviors: ['ProjectileEmitter'], show: 'family', src: 'EnemyManager.try_launch (ProjectileManager\'s hit loop)',
      help: 'a ball hit that does not kill may throw the creature straight up: it cannot move, bite or attack up there and takes the hit again when it lands (so it grows with every damage increase); bosses, Elites and elite-modded creatures take that landing damage at once, no flight', rows: [
        P('launch.chance', 'Chance', 'number', null, 'the chance per hit (Alley-Oop 0.15, Slam Dunk 0.25); empty = never', { min: 0, max: 1, step: 0.05 }),
        P('launch.height', 'Height (m)', 'number', 3.5, 'how high a plain creature flies (straight up, no drift)', { min: 0, step: 0.5 }),
        P('launch.air_time', 'Air time (s)', 'number', 0.9, 'up fast (30% of it), a hang (to 50%), then the drop', { min: 0.1, step: 0.1 }),
        P('launch.fall_damage_frac', 'Landing damage ×', 'number', 1, 'the landing\'s damage = this × the hit\'s (Slam Dunk 1.5)', { min: 0, step: 0.1 }),
        P('launch.sfx', 'Landing sound', 'sfx', 'w_grav_land', 'the thud on landing', { group: 'w_' }),
      ] },
    { id: 'heat_look', label: 'Heat on the ball', behaviors: ['ProjectileEmitter'], show: 'family', src: 'ProjectileManager.heat_glow, _heat_trail, _draw_heat_halos',
      help: 'pass 69 (Garry: no HUD gauge, only the ball itself): the ball shows its Heat (Run.heat over catch.heat_max) by glowing hotter, an orange trail, flames and at the top a beating halo; needs the catch block (the Heat)', rows: [
        P('heat_look.color', 'Glow colour', 'swatch', '#FF6A1A', 'the body warms toward it, the seams start from it, the trail and the halo wear it'),
        P('heat_look.hot', 'Hot colour', 'swatch', '#FFC060', 'what the seams and the trail turn toward near full Heat'),
        P('heat_look.glow_min', 'Glow at a little Heat', 'number', 0, 'the least emission energy once there is any Heat', { min: 0, step: 0.05 }),
        P('heat_look.glow_max', 'Body glow at full Heat', 'number', 0.5, 'the body\'s emission energy at full Heat, kept low so the ball still reads as its colour (basketball 0.45, Slam Dunk 0)', { min: 0, step: 0.05 }),
        P('heat_look.seam_glow_max', 'Seam glow at full Heat', 'number', 1.6, 'the seams\' glow at full Heat: cracks of lava (Slam Dunk 2.2)', { min: 0, step: 0.1 }),
        // pass 72 (lane ITEMS, Garry: the ball "seems to be white, should be orange")
        P('heat_look.body_green_max', 'Body stays orange (green cap)', 'number', null, 'the most green light the body\'s heat glow may add (over its own cold glow), so a body that already glows (On Fire) stays orange at full Heat instead of bleaching yellow-white; empty = no cap (basketball 0.3; the plain ball never reaches it)', { min: 0, max: 1, step: 0.05 }),
        P('heat_look.pulse_hz', 'Beat (Hz)', 'number', 3, 'the beat at full Heat', { min: 0, step: 0.5 }),
        P('heat_look.pulse', 'Beat depth', 'number', 0.35, 'how far the beat swings the glow either way (share)', { min: 0, max: 1, step: 0.05 }),
        P('heat_look.surfaces', 'What glows', 'select', 'all', 'all, the seams only (Slam Dunk: the black body stays black) or the body only', { options: [opt('all', 'all'), opt('seams', 'seams'), opt('body', 'body')] }),
        P('heat_look.trail_from', 'Trail from', 'number', 0.1, 'the share of Heat from which the orange trail shows', { min: 0, max: 1, step: 0.05 }),
        P('heat_look.trail_size', 'Trail size', 'number', 1, 'the trail bead size at full Heat', { min: 0, step: 0.1 }),
        P('heat_look.trail_life', 'Trail life (s)', 'number', 0.35, 'the trail bead life at full Heat', { min: 0, step: 0.05 }),
        P('heat_look.flame_from', 'Flames from', 'number', 0.4, 'the share of Heat from which flames lick behind it', { min: 0, max: 1, step: 0.05 }),
        P('heat_look.flame_size', 'Flame size', 'number', 1, 'the flames\' size factor', { min: 0, step: 0.1 }),
        P('heat_look.halo', 'Halo radius ×', 'number', 1.8, 'the halo radius, times the ball\'s (0 = none)', { min: 0, step: 0.1 }),
        P('heat_look.halo_from', 'Halo from', 'number', 0.9, 'the share of Heat from which the halo shows (so it marks the top)', { min: 0, max: 1, step: 0.05 }),
        P('heat_look.halo_alpha', 'Halo opacity', 'number', 0.22, 'the halo\'s opacity at full Heat (beating with the glow)', { min: 0, max: 1, step: 0.01 }),
      ] },
    { id: 'ball_tint', label: 'Ball colour (body and seams)', behaviors: ['ProjectileEmitter'], show: 'family', present: ['tint.body', 'tint.seams', 'tint.vertex_colors', 'tint.ambient'], src: 'ProjectileEmitter.tint_kind, ProjectileManager.tint_material / seam_kind',
      help: 'a mutation\'s or an evolution\'s ball in its own colour (Alley-Oop\'s dark blue, Slam Dunk\'s black with ember seams); any shot drawn from a vertex-coloured model', rows: [
        P('tint.body', 'Body colour', 'swatch', null, 'paints the model flat in this colour (its own colours off) and keeps its seams (Alley-Oop #0A4FA8, Slam Dunk #141414); empty = the ball\'s own orange'),
        P('tint.emission', 'Glow colour', 'swatch', null, 'a faint glow over the body (Alley-Oop #1A5CFF)'),
        P('tint.energy', 'Glow strength', 'number', null, 'the glow\'s energy (Alley-Oop 0.15)', { min: 0, step: 0.05 }),
        P('tint.roughness', 'Roughness', 'number', null, 'how matte the body is, 0 shiny .. 1 matte (Slam Dunk 0.45)', { min: 0, max: 1, step: 0.05 }),
        P('tint.vertex_colors', 'Keep the model\'s colours', 'bool3', null, 'no = the colour above alone paints the model (Body colour sets it)'),
        P('tint.ambient', 'Lit by the sky', 'bool3', null, 'no = the sky\'s warm ambient light is left out, so a dark ball keeps its colour on the sand (Alley-Oop and Slam Dunk: no; with it, black reads brown and navy violet)'),
        P('tint.seams.color', 'Seam colour', 'swatch', '#0A0A0A', 'the seams\' colour (the model\'s darkest lines)'),
        P('tint.seams.emission', 'Seam glow', 'swatch', null, 'the seams glow in this colour (Slam Dunk\'s embers #FF5A14)'),
        P('tint.seams.energy', 'Seam glow strength', 'number', 1, 'the seams\' glow energy (Slam Dunk 1.3)', { min: 0, step: 0.1 }),
        P('tint.seams.below', 'Seam threshold', 'number', 0.25, 'the vertex-colour brightness under which a triangle counts as seam', { min: 0, max: 1, step: 0.05 }),
      ] },
    { id: 'nonstop', label: 'Fire without a target (Trigger Happy)', behaviors: ['ProjectileEmitter'], show: 'set', src: 'core/behaviors/ProjectileEmitter.gd (stream_gap, _stream_dir)',
      help: 'May\'s Trigger Happy: the gun fires on its clock even with nobody in range, along her facing, and a burst spreads its rounds over the whole cooldown so it never pauses; pay for it with a damage cut in the effects', rows: [
        P('fire_without_target', 'Fire with no target', 'bool3', false, 'a gun with the usual targeting (nearest / priority) fires on its clock even with no creature in range, along the hero\'s facing (the Blunderbuss\'s fire_blind is the same for "forward" targeting)'),
        P('stream', 'Stream the burst', 'bool3', false, 'a burst weapon spreads its rounds evenly over the whole cooldown (gap = cooldown × 0.97 / amount) instead of 50 ms apart: the gun never pauses; each round aims at the creature it would aim at now, else along her facing'),
      ] },
    // pass 81 (lane POLISH): the Killer Bees' trail look, one key away (research and pictures in tools/dl/p81/POLISH/)
    { id: 'bee_trail', label: 'Bee trail (the seekers\' line)', behaviors: ['MissilePod'], show: 'set',
      present: ['missile.trail_style', 'missile.trail_color'],
      src: 'core/systems/ProjectileManager.gd (BEE_LOOKS, _bee_trail), core/shaders/tracer_line.gdshader',
      help: 'the line behind every bee (a seeker whose missile.trail is 2; Pollen\'s red bees keep their red); one look per weapon or evolution', rows: [
        P('missile.trail_style', 'Look', 'select', 'dash', 'dash (the game\'s own) = the cartoon bee\'s dotted flight path: dark honey-brown dashes, gone in under half a second; buzz = a thin honey-brown squiggle weaving either side of the flight; bumble = the dashes weaving like the buzz; zip = a short tapered gold streak; beads = pass 49\'s dark beads that linger 1.4 s', { options: [opt('dash', 'dash'), opt('buzz', 'buzz'), opt('bumble', 'bumble'), opt('zip', 'zip'), opt('beads', 'beads')] }),
        P('missile.trail_color', 'Colour', 'swatch', null, 'the line\'s colour; empty = the look\'s own (dash and bumble dark honey-brown, buzz honey, zip gold); never Pollen\'s red'),
      ] },
    // pass 80 (lane TRAIL): the tracer's look, one key away (research and pictures in tools/dl/p80/TRAIL/)
    { id: 'tracer', label: 'Tracer (the trail behind every round)', behaviors: ['ProjectileEmitter'], show: 'set',
      present: ['tracer', 'tracer_style', 'tracer_color', 'tracer_alpha', 'tracer_width', 'tracer_life', 'tracer_hot', 'tracer_clear'],
      src: 'core/systems/ProjectileManager.gd (_tracer_*), core/shaders/tracer_line.gdshader',
      help: 'a trail drawn behind every round so a shot reads as fired; one look per weapon, mutation or evolution (a mutation\'s keys win over its weapon\'s); empty boxes take the style\'s own numbers', rows: [
        P('tracer', 'Tracer on', 'bool3', false, 'draw a trail behind every round of this weapon'),
        P('tracer_style', 'Style', 'select', 'wisp', 'wisp (the game\'s own) = a hot streak riding with the bullet over a pale smoke that lingers and fades; streak = a short tracer round: the tapered streak alone, a hot white middle in the colour with a soft glow; ribbon = a longer ribbon whose hot middle dies first; toon = hard cartoon bands with a dark outline; line = pass 79\'s thin line that fades like smoke', { options: [opt('streak', 'streak'), opt('ribbon', 'ribbon'), opt('wisp', 'wisp'), opt('toon', 'toon'), opt('line', 'line')] }),
        P('tracer_color', 'Colour', 'swatch', null, 'the trail\'s colour (Revolver red, Silver Bullet silver-blue); empty = gold, orange for a burning weapon, green for a poison one'),
        P('tracer_alpha', 'Opacity', 'number', 0.9, 'how solid the trail is, 0..1 (with a colour of its own)', { min: 0, max: 1, step: 0.05 }),
        P('tracer_width', 'Width (m)', 'number', null, 'the trail\'s width at the bullet, glow included (it tapers behind); empty = the style\'s (0.1; the line 0.05)', { min: 0.005, step: 0.01 }),
        P('tracer_life', 'Life (s)', 'number', null, 'how long each piece of the trail lives, so its length = speed × life; empty = the style\'s (streak 0.13, ribbon 0.3, wisp 0.55, toon 0.2, line 1.4)', { min: 0.05, step: 0.01 }),
        P('tracer_hot', 'Hot part', 'number', null, 'the share of the life the white-hot middle lasts (the wisp: its streak before the smoke), 0..1; empty = the style\'s (wisp 0.3, streak 0.7, ribbon 0.4, toon 0.5)', { min: 0.02, max: 1, step: 0.05 }),
        P('tracer_clear', 'Clear of the hero (m)', 'number', 0, 'no trail within this many metres of the hero (the Revolver 1.1: its companion gun fires past him)', { min: 0, step: 0.1 }),
      ] },
  ];
  /** The typed groups a document shows: [{group, on}] where `on` = shown open (its knobs) and the rest are offered.
   *  `behavior` the behaviour that reads the document's params; `own` the document's params (the block being edited);
   *  `family` the weapon family's params (a mutation's weapon, else the document's own). */
  function paramGroupsFor(behavior, own, family, opened) {
    const has = (obj, key) => { let cur = obj; for (const p of String(key).split('.')) { if (!isObj(cur) || !(p in cur)) return false; cur = cur[p]; } return true; };
    const out = [];
    for (const g of PARAM_GROUPS) {
      if (!g.behaviors.includes(String(behavior || 'ProjectileEmitter'))) continue;
      const keys = g.present || g.rows.map((r) => r.key);
      const set = keys.some((k2) => has(own, k2) || has(family, k2));
      const on = g.show === 'always' || set || (g.show === 'family' && (isBall(own) || isBall(family))) || !!(opened && opened[g.id]);
      out.push({ group: g, on, set });
    }
    return out;
  }
  /** A typed row's value where it is not set in the box: [value, source] from the weapon family's params (a mutation's
   *  weapon; an evolution's final block reads its own params), else the code's default. */
  function paramInherited(row, inheritFrom) {
    for (const [obj, src] of inheritFrom || []) {
      let cur = obj, ok = true;
      for (const p of String(row.key).split('.')) { if (!isObj(cur) || !(p in cur)) { ok = false; break; } cur = cur[p]; }
      if (ok) return [cur, src];
    }
    return [row.def, row.def == null ? 'none: off' : 'the game\'s default'];
  }

  // ------------------------------------------------------------------ pass 69 (lane LE): perk specials (vocab.py PERK_SPECIALS)
  // A perk's `special` names the mechanism the game runs, `params` tune it (Run.perk_param). by 'special': any perk id
  // carrying it works; by 'id': the code also checks the perk's own id, so only that perk triggers it. The server's
  // /api/vocab `perk_specials` wins over this copy.
  const PS = (by, help, params) => ({ by, help, params: params || {} });
  const PERK_SPECIALS = {
    '': PS('special', 'none: the perk\'s effects only (Afterglow, Long Day)'),
    decoy: PS('special', 'Inflatable May: every `every` s (the first after `first` s) she throws an inflatable double of herself `throw_min`..`throw_max` m away in a random direction; it flies `flight` s and lands; a faint circle of `radius` m marks it and for `duration` s every creature inside (Elites too, never a boss) goes for the doll instead of her, a pink ? bobbing over it; then it pops', { every: 30, first: 6, throw_min: 4, throw_max: 7, flight: 0.6, radius: 6.5, duration: 2 }),
    periodic_buff: PS('special', 'Buzzer Beater: after `first` s (else `every`), then every `every` s, the `buff` effects (target player) for `seconds` s, a timed buff under the perk\'s name', { every: 30, first: null, seconds: 5, buff: null }),
    timeout: PS('id', 'Fadeaway\'s Timeout: drops the pickup `pickup` `side` m to his left or right, first after `first` s, then `every` s after the last one went', { every: 20, first: 10, side: 3, pickup: null }),
    trampoline: PS('special', 'Hang Time: after `first` s, then `every` s after the last one folded, a 3D trampoline drops `side` m beside the hero and stands `lifetime` s; walking onto it (within `radius` m of its middle) throws him `launch_height` m up and `launch_distance` m along the way he walked, `air_time` s in the air, the stick steering at `air_control` of his walking speed, untouchable up there; it folds after `uses` jumps', { every: 20, first: 10, side: 3.5, lifetime: 30, radius: 1.1, uses: 1, launch_height: 4, launch_distance: 8, air_time: 1.1, air_control: 0.35 }),
    overdrive: PS('id', 'Jeżyk\'s Overdrive: every `every` s at full momentum is one gear of `step` attack damage, up to `max`; a hit that lands drops every gear', { every: 5, step: 0.05, max: 0.25 }),
    ram: PS('id', 'Jeżyk\'s Ram: at a charge of `from` or more a creature that touches him is shoved `shove` and takes `flat` + `per_level` × level + `thorns_mult` × thorns instead of biting', { thorns_mult: 3, flat: 12, per_level: 0, shove: 9, from: 0.99 }),
    high_noon: PS('id', 'the Drifter\'s High Noon: every `every` s (the first after `first`) every creature moves at `slow` speed for `seconds` s', { every: 30, first: 20, seconds: 3, slow: 0.3 }),
    trail_dust: PS('id', 'the Drifter\'s Trail Dust: the dust behind him slows creatures', { every: 0.22, radius: 1.1, seconds: 1, slow: 0.25 }),
    bounty_hunter: PS('id', 'the Drifter\'s Bounty Hunter: every `every` kills a creature within `reach` m is WANTED', { every: 60, reach: 16, hp_mult: 4, gold: 40 }),
    serenade: PS('id', 'Calavera\'s Serenade: creatures near him move slower', { radius: 4, every: 0.3, slow: 0.25 }),
    crescendo: PS('id', 'Calavera\'s Crescendo: every kill adds attack damage up to `max`; a hit drops it', { per_kill: 0.01, max: 0.4 }),
    grand_finale: PS('id', 'Calavera\'s Grand Finale: a dying boss or Elite hurts and throws the crowd round it', { radius: 14, frac: 0.35, throw: 16 }),
    supply_drop: PS('id', 'Astro\'s Supply Drop: a pod crashes near her every `every` s and leaves `drops`', { every: 40, first: 15, warn: 1.5, radius: 2.6, damage: 30, damage_per_level: 4, knockback: 14, heart_below: 0.6, drops: null }),
    thruster_burst: PS('id', 'Astro\'s Thruster Burst: `crowd` creatures within `reach` m and she flies clear', { crowd: 6, reach: 2.6, every: 8, push: 28, lift: 5, throw: 18, throw_radius: 3.2, invuln: 0.6 }),
    suit_seals: PS('id', 'Astro\'s Suit Seals: the level-up patch gives `invuln` s of invulnerability', { invuln: 1.5 }),
    deep_breath: PS('id', 'Ironwood\'s Deep Breath: below `below` health his regen runs `mult` times over', { below: 0.35, mult: 4, seconds: 6, cooldown: 40 }),
    unbroken: PS('id', 'Ironwood\'s Unbroken: hits no longer pause his regen'),
    sunburn: PS('id', 'Solenne\'s Sunburn: a burning or poisoned creature takes `bonus` more from her', { bonus: 0.2 }),
    lingering_light: PS('id', 'Solenne\'s Lingering Light: her burns and poison tick harder and last longer', { harder: 0.3, longer: 0.3 }),
    tough_love: PS('id', 'Dad\'s Tough Love: a hit gives attack damage and area for a while', { might: 0.15, area: 0.15, seconds: 4 }),
  };
  // the decoy's params in words (the perk form's typed rows); the other specials show their keys with the code's defaults
  const PERK_PARAM_HELP = {
    decoy: { every: 'seconds between throws (counted from the throw)', first: 'seconds from taking the perk to the first throw', throw_min: 'the nearest the doll lands from her (m)', throw_max: 'the farthest (m); a random direction, inside the arena, off the rocks when it can',
      flight: 'the throw\'s flight time (s; an arc 2.2 m high)', radius: 'the circle (m): every creature inside is fooled (Elites too, never a boss), and one walking in while the doll stands; keep it under half a screen', duration: 'how long the doll stands (s); then it pops and they hunt her again' },
    periodic_buff: { every: 'seconds between buffs', first: 'seconds to the first (empty = every)', seconds: 'how long each buff lasts', buff: 'the effects, a list of {stat, op, value, target player}' },
    timeout: { pickup: 'the pickup id dropped beside him (content/pickups)' },
    trampoline: { every: 'seconds from the last one folding away to the next drop', first: 'seconds from taking the perk to the first drop', side: 'how far beside him it lands (m; the side with fewer creatures, off the rocks and the water)', lifetime: 'how long it stands unused (s; the last 3 s it blinks)', radius: 'how near its middle his centre must come to bounce (m; the mat is 2 m across, the pad reaches 1.28 m out)', uses: 'jumps before it folds (1)', launch_height: 'the top of the arc over the take-off (m)', launch_distance: 'how far along the way he walked he lands on level ground (m)', air_time: 'seconds in the air on level ground', air_control: 'the stick in the air, a share of his walking speed (0 = none, 1 = as on the ground)' },
    supply_drop: { drops: 'the pickup ids the pod leaves, a list' },
  };
  function perkSpecialOptions(vocab) {
    const table = vocab && isObj(vocab.perk_specials) ? vocab.perk_specials : PERK_SPECIALS;
    return Object.keys(table).map((k2) => opt(k2, k2 === '' ? 'none (effects only)' : k2, `${table[k2].by === 'id' ? 'works for that perk only (the game checks its id): ' : 'any perk can carry it: '}${String(table[k2].help || '').replace(/`/g, '')}`));
  }

  // ------------------------------------------------------------------ the brain blocks (EnemyManager.gd:2858-3365; defaults as placeholders)

  const BLOCKS = {
    ranged: { label: 'Ranged', help: 'read by kite, by ambush (its silk) and by the ranged arena dummy: keeps its distance and shoots', rows: [
      { key: 'keep_distance', label: 'Keep distance (m)', type: 'number', min: 0, def: 5, help: 'backs off when the hero is nearer than this − 0.5' },
      { key: 'range', label: 'Range (m)', type: 'number', min: 0, def: 8, help: 'shoots when the hero is within it (ambush 9, the cone sector 5)' },
      { key: 'telegraph', label: 'Wind-up (s)', type: 'number', min: 0, step: 0.05, def: 0.6, help: 'seconds the shot is announced (x 1/pace)' },
      { key: 'cooldown', label: 'Cooldown (s)', type: 'number', min: 0.1, step: 0.1, def: 2.5, help: 'seconds between shots' },
      { key: 'straight', label: 'Straight shot', type: 'bool', def: false, help: 'a straight shot instead of a lobbed spit' },
      { key: 'cone_deg', label: 'Cone (°)', type: 'number', min: 0, def: 50, help: 'with count: a pellet cone over this many degrees, a sector telegraph' },
      { key: 'count', label: 'Pellets', type: 'int', min: 1, def: 5, help: 'pellets in the cone (its presence makes the cone)' },
      { key: 'projectile_speed', label: 'Shot speed', type: 'number', min: 0, help: 'm/s: cone 16, straight 12, lob 6 when empty' },
      { key: 'splash', label: 'Splash (m)', type: 'number', min: 0, help: 'hit area: cone 0.45, straight 0.8, lob 1.2 when empty; the lob\'s landing ring is this radius' },
      { key: 'life', label: 'Shot life (s)', type: 'number', min: 0, help: 'cone 0.45, straight 1.4 when empty' },
      { key: 'shot', label: 'Shot look', type: 'select', options: (v) => v.shotKinds, def: '', help: 'pellet / spike / shard; anything else is the green spit' },
      { key: 'knockback', label: 'Shot knockback', type: 'number', min: 0, def: 0, help: '0 = 0.7 x the shooter\'s own bite knockback' },
      { key: 'pull', label: 'Pulls the hero', type: 'bool', def: false, help: 'the silk line pulls the hero toward the shooter' },
      { key: 'harpoon', label: 'Harpoon', type: 'bool', def: false, help: 'the harpoon kind: tethers the hero (the tether block)' },
      { key: 'tether', label: 'Tether', type: 'json', help: '{seconds 5, away_speed 0.7, min_length 1.8}' },
      { key: 'lead', label: 'Leads the hero', type: 'bool', def: false, help: 'aims where the hero will be' },
      { key: 'land_only', label: 'Hurts on landing only', type: 'bool', def: false, help: 'an arcing spit hurts where it lands and draws a red landing ring' },
      { key: 'trail', label: 'Trail', type: 'json', help: '{color "#62F27F", alpha, size 1.0, life 1.4, step 0.055}: read from the base creature, never from a row override' },
      { key: 'pulse', label: 'Pulse', type: 'json', help: '{hz 3, size 0.12, glow 0.3, halo 1.6, color "#9CFF6E"}' },
    ] },
    charge: { label: 'Charge', help: 'the charge brain: winds up, rushes at charge speed, bites x1.5', rows: [
      { key: 'windup', label: 'Wind-up (s)', type: 'number', min: 0, step: 0.05, def: 0.8, help: 'x 1/pace; a line telegraph of the distance + 4 m' },
      { key: 'speed', label: 'Speed (m/s)', type: 'number', min: 0, def: 9, help: 'x pace' },
      { key: 'duration', label: 'Duration (s)', type: 'number', min: 0, step: 0.05, def: 0.7 },
      { key: 'cooldown', label: 'Cooldown (s)', type: 'number', min: 0, step: 0.1, def: 4 },
      { key: 'trigger_range', label: 'Trigger range (m)', type: 'number', min: 0, def: 6, help: 'starts the wind-up when the hero is this near' },
      { key: 'knockback', label: 'Charge knockback', type: 'number', min: 0, def: 0, help: 'the shove of a connecting charge bite' },
      { key: 'shake', label: 'Shake', type: 'number', min: 0, def: 0, help: 'look: trembles while winding up' },
      { key: 'crouch', label: 'Crouch', type: 'number', min: 0, max: 0.5, step: 0.05, def: 0, help: 'look: squats this much of its height (0..0.5)' },
      { key: 'legs', label: 'Leg beats', type: 'number', min: 1, def: 1, help: 'look: how fast the legs beat in the rush' },
      { key: 'lean', label: 'Lean (°)', type: 'number', min: -30, max: 30, def: 0, help: 'look: leans into the rush' },
      { key: 'dust', label: 'Dust', type: 'number', min: 0, def: 0, help: 'look: dust behind it' },
      { key: 'shove', label: 'Shove', type: 'number', min: 0, def: 0, help: 'look: pushes the crowd aside in the rush' },
      { key: 'shove_walk', label: 'Shove walking', type: 'number', min: 0, def: 0 },
    ] },
    kamikaze: { label: 'Kamikaze', help: 'the kamikaze brain: runs in, winds up and blows up (Game.elite_explosion, the crowd takes 20%)', rows: [
      { key: 'trigger', label: 'Trigger (m)', type: 'number', min: 0, def: 1.1, help: '+ size x 0.4' },
      { key: 'windup', label: 'Wind-up (s)', type: 'number', min: 0, step: 0.05, def: 0.35 },
      { key: 'radius', label: 'Blast radius (m)', type: 'number', min: 0, def: 2.6 },
      { key: 'damage', label: 'Blast damage', type: 'number', min: 0, def: 26, help: 'x stage x level x host' },
      { key: 'knockback', label: 'Blast knockback', type: 'number', min: 0, def: 9 },
    ] },
    artillery: { label: 'Artillery', help: 'the artillery brain: placed stand_off away, one rocket at a time', rows: [
      { key: 'stand_off', label: 'Stand-off (m)', type: 'number', min: 0, def: 28, help: 'where it is placed at spawn' },
      { key: 'windup', label: 'Wind-up (s)', type: 'number', min: 0, step: 0.05, def: 1.4, help: 'a 5 m line telegraph' },
      { key: 'reload', label: 'Reload (s)', type: 'number', min: 0, step: 0.1, def: 2.5 },
      { key: 'muzzle', label: 'Muzzle', type: 'json', help: '{up, side, forward} in metres at the def\'s size' },
      { key: 'missile', label: 'Missile', type: 'json', help: '{speed 4, turn 1.3, damage 22, area 1.6, speed_of_hero 0, hit_slow {mult 0.5, recover 3, shake 0.35}}: pass 73, hit_slow = every hit on the shooter shakes its live rocket for `shake` s and drops it to `mult` of its speed, back to full in a straight line over `recover` s (a new hit starts that again, never lower); no hit_slow = never slowed' },
    ] },
    caster: { label: 'Caster', help: 'the caster brain: keeps away, sidesteps, casts its tricks from the attack script', rows: [
      { key: 'keep_distance', label: 'Keep distance (m)', type: 'number', min: 0, def: 7 },
      { key: 'side', label: 'Sidestep (m)', type: 'number', min: 0, def: 4.5 },
      { key: 'attack_range', label: 'Attack range (m)', type: 'number', min: 0, help: 'the script waits while the hero is beyond it' },
    ] },
    support: { label: 'Support', help: 'the support brain: heals and frenzies the crowd round it (x1.3 speed)', rows: [
      { key: 'keep_distance', label: 'Keep distance (m)', type: 'number', min: 0, def: 7 },
      { key: 'range', label: 'Range (m)', type: 'number', min: 0, def: 10 },
      { key: 'interval', label: 'Pulse every (s)', type: 'number', min: 0.1, def: 4 },
      { key: 'radius', label: 'Pulse radius (m)', type: 'number', min: 0, def: 5 },
      { key: 'heal', label: 'Heal (share of HP)', type: 'number', min: 0, max: 1, step: 0.05, def: 0.25 },
      { key: 'frenzy_seconds', label: 'Frenzy (s)', type: 'number', min: 0, def: 3 },
    ] },
    ambush: { label: 'Ambush', help: 'the ambush brain: spawns hidden, pops up when the hero is near, hides again', rows: [
      { key: 'trigger', label: 'Trigger (m)', type: 'number', min: 0, def: 5 },
      { key: 'rehide_distance', label: 'Re-hide beyond (m)', type: 'number', min: 0, def: 12 },
      { key: 'rehide_after', label: 'Re-hide after (s)', type: 'number', min: 0, def: 6 },
    ] },
    death_burst: { label: 'Death burst', help: 'blows up after it dies (skipped when it blew itself up)', rows: [
      { key: 'delay', label: 'Delay (s)', type: 'number', min: 0, def: 2 },
      { key: 'radius', label: 'Radius (m)', type: 'number', min: 0, def: 2.4 },
      { key: 'damage', label: 'Damage', type: 'number', min: 0, def: 12, help: 'x stage x level x host' },
      { key: 'knockback', label: 'Knockback', type: 'number', min: 0, def: 0 },
    ] },
    boss: { label: 'Attack script', help: 'the attack runner: the boss brain, casters, and any creature with attacks in here (the first attack 2 s after spawn)', rows: [
      { key: 'attacks', label: 'Attacks', type: 'attacks', help: 'in order; the runner cycles them' },
      { key: 'cooldown_between', label: 'Between attacks (s)', type: 'number', min: 0, step: 0.1, def: 2, help: 'the rest between two attacks (not scaled by pace)' },
      { key: 'hp_mult_per_stage', label: 'HP x per stage', type: 'number', min: 0, step: 0.1, def: 1.6, help: 'boss archetype: HP = hp x this^stage x max(stage_mult, 1), nothing else', only: (d) => d.archetype === 'boss' },
      { key: 'ring', label: 'Fire ring', type: 'json', help: 'the Brander\'s ring: {radius 21, min_radius 8, shrink 42, hold 8, burn 0.07, creature_burn 0.12}' },
    ] },
    elite: { label: 'Elite (mini-boss)', help: 'read for the elite archetype only', rows: [
      { key: 'hp_mult_per_stage', label: 'HP x per stage', type: 'number', min: 0, step: 0.1, def: 1.8, help: 'HP = hp x this^stage x max(stage_mult, 1) x creature_hp_mult' },
    ] },
    // pass 73 (lane SNIPER): the Saiga Sniper's brain (EnemyManager._sniper_*) and flee on hit, for any creature
    sniper: { label: 'Sniper', help: 'the sniper brain (the Saiga Sniper): placed stand-off away like the Vulture Raider; past "Walks in past" it walks towards the hero (the kite\'s way, pass 81), inside it holds where it is (it never backs off; inside "Runs inside", 0 = never, it would run from him); there it freezes in its aiming pose (the attack strip) while red lines gather on the hero and follow him for Aim s, then lock, hold for Hold s, and a laser crosses the map along the locked line. Aim and Hold × 1/pace like every wind-up', rows: [
      { key: 'stand_off', label: 'Stand-off (m)', type: 'number', min: 0, def: 26, help: 'where it is placed when it spawns (never nearer the hero), inside the wall' },
      { key: 'flee_range', label: 'Runs inside (m)', type: 'number', min: 0, def: 0, help: 'it runs straight away from the hero (along the wall when backed against it) while he is nearer than this; never while it aims. 0 = it never runs (the Saiga since pass 81; the code\'s own is 0)' },
      { key: 'follow', label: 'Walks in past (m)', type: 'number', min: 0, def: 38, help: 'it walks towards the hero while he is farther than this, then holds and aims (the Spit Cactus\'s range; the Saiga 16); empty = stand-off + 12' },
      { key: 'first', label: 'First aim after (s)', type: 'number', min: 0, step: 0.1, def: 2.5, help: 'seconds after it arrives before its first aim' },
      { key: 'aim', label: 'Aim (s)', type: 'number', min: 0.1, step: 0.1, def: 2, help: 'the lines gather on the hero and follow him this long (× 1/pace)' },
      { key: 'lock', label: 'Hold (s)', type: 'number', min: 0, step: 0.1, def: 1, help: 'the locked line holds still this long before the shot (× 1/pace): the time to step off it' },
      { key: 'interval', label: 'Shot every (s)', type: 'number', min: 1, step: 0.5, def: 9, help: 'from one shot to the next, the aim and the hold included' },
      { key: 'interval_jitter', label: 'Shot every ± (s)', type: 'number', min: 0, step: 0.1, def: 1.5, help: 'the interval varies this much either way, at random' },
      { key: 'recover', label: 'After a spoiled aim (s)', type: 'number', min: 0, step: 0.1, def: 2.5, help: 'a hit (Spoiled by a hit), a stun, a freeze or a launch drops the aim; the next one waits at least this long' },
      { key: 'spoil_on_hit', label: 'Spoiled by a hit', type: 'bool', def: true, help: 'pass 81: a hit that lands (never a poison or fire tick) drops its aim or lock under way: that shot never comes (no running; flee on hit is a separate block)' },
      { key: 'cone_deg', label: 'Line cone (°)', type: 'number', min: 1, max: 180, def: 44, help: 'the lines start on the two sides of a cone this wide round his aim and sweep in to the hero' },
      { key: 'lines', label: 'Lines', type: 'int', min: 1, def: 14, help: 'how many lines gather over the aim: closer and closer together, each sweeping in faster than the last' },
      { key: 'beam', label: 'Beam', type: 'json', help: '{length 60 (m across the map), width 0.5, seconds 0.15 (how long it shows), damage_from "rocketeer" + damage_mult 0.7 (the hero takes that share of that creature\'s rocket damage, at the sniper\'s own stage), damage 15.4 (used without damage_from), knockback 5, creature_frac 0.05 + creature_max 40 (what each creature on the line takes), push 3 (m off the line), sparks 1.5 (s they shimmer)}' },
      { key: 'muzzle', label: 'Muzzle', type: 'json', help: '{up, side, forward} in metres at the def\'s size: where the lines and the beam leave, the rifle\'s end as painted (side = towards the barrel, screen-right in the painting)' },
    ] },
    flee_on_hit: { label: 'Flee on hit', help: 'any creature: a hit that lands (never a poison or fire tick) sends it running straight away from the hero for Runs for s at its speed × Speed ×; with Spoils its attack it drops a wind-up, aim or scripted attack under way (that shot never comes). A new hit starts the run again (never faster). Never a boss', rows: [
      { key: 'seconds', label: 'Runs for (s)', type: 'number', min: 0, step: 0.1, def: 1, help: 'how long one hit sends it running (0 = off)' },
      { key: 'speed_mult', label: 'Speed ×', type: 'number', min: 0, step: 0.1, def: 1.8, help: 'its walk times this while it runs' },
      { key: 'interrupts', label: 'Spoils its attack', type: 'bool', def: true, help: 'the hit drops a wind-up, an aim or a scripted attack under way' },
    ] },
  };
  const BLOCK_ORDER = ['ranged', 'charge', 'kamikaze', 'artillery', 'sniper', 'caster', 'support', 'ambush', 'death_burst', 'flee_on_hit', 'boss', 'elite'];

  // ------------------------------------------------------------------ the attack script's names (EnemyManager.gd:3696-3882)

  const k = (key, label, type, def, help, extra) => Object.assign({ key, label, type: type || 'number', def, help: help || '', min: 0 }, extra || {});
  const ATTACK_COMMON = [
    { key: 'windup', label: 'Wind-up (s)', type: 'number', min: 0, step: 0.05, def: 1, help: 'seconds announced before it lands, x 1/pace on the map' },
    { key: 'telegraph', label: 'Telegraph', type: 'select', options: (v) => v.telegraphs, help: 'what the ground shows during the wind-up (empty = the name\'s usual)' },
    { key: 'reach', label: 'Reach (m)', type: 'number', min: 0, help: 'waits, walking on, until the hero is within reach + radius' },
    { key: 'min_range', label: 'Skip inside (m)', type: 'number', min: 0, help: 'skipped while the hero is nearer than this' },
    { key: 'max_range', label: 'Skip beyond (m)', type: 'number', min: 0, help: 'skipped while the hero is farther than this' },
    // pass 95 (lane BOSS): EnemyManager._attack_chance_misses
    { key: 'chance', label: 'Chance', type: 'number', min: 0, max: 1, step: 0.05, help: 'rolled as its turn comes (0..1): a miss skips to the next attack in the list; empty = always plays (the Scorpion\'s tail sniper 0.7)' },
  ];
  const ATTACKS = {
    roll: { label: 'Roll', telegraph: 'line', help: 'rushes along the line at `speed` for `duration` (the boss brain only runs it right)', keys: [k('speed', 'Speed (m/s)', 'number', 12), k('duration', 'Duration (s)', 'number', 1.2), k('damage', 'Damage', 'number', 25, 'x stage x host'), k('length', 'Line length (m)', 'number', null, 'the telegraph\'s line; empty = speed x duration + its radius')] },
    spawn_ring: { label: 'Spawn ring', telegraph: 'none', help: 'a ring of `count` creatures 5 m out (brood numbers)', keys: [k('enemy', 'Creature', 'enemy', '', 'the creature it brings (the game\'s default "coyote" no longer exists)'), k('count', 'Count', 'int', 10)] },
    slam_at: { label: 'Slam at the hero', telegraph: 'ring_at_hero', needsRingAtHero: true, help: 'a blast where the hero stood at the wind-up', keys: [k('radius', 'Radius (m)', 'number', 2.6), k('damage', 'Damage', 'number', 18), k('knockback', 'Knockback', 'number', 6)] },
    blink: { label: 'Blink', telegraph: 'none', help: 'teleports: `to` "screen" uses the caster\'s keep / side distance', keys: [k('to', 'To', 'select', '', '', { options: (v) => v.blinkTo, min: undefined }), k('distance', 'Distance (m)', 'number', 8)] },
    burrow: { label: 'Burrow', telegraph: 'ring_at_hero', needsRingAtHero: true, help: 'under the sand for the wind-up (a mound swells at the ring), then up at the hero; the wind-up runs from the dig to the eruption (pass 73: the sink, the wait under the sand, a predicted spot\'s warning). Pass 73: it can sink in sight, wait unseen and erupt where the hero is heading, throwing him and the crowd', keys: [k('radius', 'Radius (m)', 'number', 5), k('damage', 'Damage', 'number', 28), k('knockback', 'Knockback', 'number', 8, 'the old shove, when it throws no one (Throw hero up empty)'),
      k('sink', 'Sink (s)', 'number', 0, 'seconds it sinks out of sight where it stands, in a ring of dust and a spray of sand (0 = gone at once, as before pass 73); ×1/pace on the map'),
      k('rise', 'Rise (s)', 'number', 0.4, 'seconds it takes to come up out of the sand at the eruption (the game\'s 0.4 when empty)'),
      k('predict', 'Predict (s)', 'number', 0, 'above 0: no ring and no mound before; Warning seconds before it erupts it picks the spot where the hero will be this many seconds on (his place + his velocity × this, on the walkable map) and rings it (the Gila\'s 0.6 = about two steps ahead); 0: the ring at the hero'),
      k('warn', 'Warning (s)', 'number', 0.4, 'with Predict: the red ring on the spot this long before it erupts (×1/pace on the map)'),
      k('mound', 'Mound', 'bool', true, 'the sand swells into a mound at the ring through the wind-up (never with Predict)', { min: undefined }),
      k('throw_up', 'Throw hero up (m)', 'number', 0, 'a hit that lands throws the hero this high on a real arc (his airborne flight: nothing hits him up there) instead of the Knockback shove; 0 = the shove'),
      k('throw_out', 'Throw hero out (m)', 'number', 0, 'how far the throw carries him, away from the eruption\'s middle'),
      k('throw_air', 'Throw air time (s)', 'number', null, 'seconds he is up; empty = from the height at his own gravity (2.5 m: 0.91 s)'),
      k('throw_control', 'Air control', 'number', 0.15, 'the share of his walk the stick adds to the throw\'s arc (0..1)', { max: 1, step: 0.05 }),
      k('creature_up', 'Throw crowd up (m)', 'number', 0, 'every creature within the radius (not the burrower) is thrown this high and away; the boss, an Elite or an elite-modded one only takes the damage and a shove'),
      k('creature_out', 'Throw crowd out (m)', 'number', 0, 'how far they fly away from the middle (× their own share of a shove, knockback resist)'),
      k('creature_damage', 'Crowd damage', 'number', 0, 'the share of its max HP each creature in the radius takes as it lands (0.03 = 3%)', { max: 1, step: 0.01 })] },
    rain: { label: 'Rain', telegraph: 'none', help: '`count` strikes every `interval` within `spread` of the hero, each warned `warn` s', keys: [k('count', 'Strikes', 'int', 10), k('interval', 'Interval (s)', 'number', 0.3), k('spread', 'Spread (m)', 'number', 5), k('radius', 'Strike radius (m)', 'number', 1.6), k('damage', 'Damage', 'number', 14), k('warn', 'Warning (s)', 'number', 0.55), k('pillar', 'Pillar', 'bool', false, '', { min: undefined }), k('knockback', 'Knockback', 'number', 0)] },
    erupt: { label: 'Erupt', telegraph: 'none', help: 'the rain, and a creature rises from every strike', keys: [k('count', 'Strikes', 'int', 10), k('interval', 'Interval (s)', 'number', 0.3), k('spread', 'Spread (m)', 'number', 5), k('radius', 'Strike radius (m)', 'number', 1.6), k('damage', 'Damage', 'number', 14), k('warn', 'Warning (s)', 'number', 0.55), k('spawn', 'Rises', 'enemy', '', 'the creature each strike brings'), k('pillar', 'Pillar', 'bool', false, '', { min: undefined }), k('knockback', 'Knockback', 'number', 0)] },
    spit_volley: { label: 'Spit volley', telegraph: 'fan', help: '`count` shots over `spread_deg`; straight (x level too) or lobbed', keys: [k('count', 'Shots', 'int', 7), k('spread_deg', 'Spread (°)', 'number', 90), k('speed', 'Speed (m/s)', 'number', 14, 'straight 14, lob 7'), k('damage', 'Damage', 'number', 12), k('splash', 'Splash (m)', 'number', 0.5, 'straight 0.5, lob 1.4'), k('life', 'Life (s)', 'number', 1), k('straight', 'Straight', 'bool', false, '', { min: undefined }), k('shot', 'Shot look', 'select', '', '', { options: (v) => v.shotKinds, min: undefined }), k('knockback', 'Knockback', 'number', 0), k('length', 'Fan length (m)', 'number', 14, 'the telegraph\'s lines')] },
    slam: { label: 'Slam', telegraph: 'ring', help: 'a blast round the creature', keys: [k('radius', 'Radius (m)', 'number', 6), k('damage', 'Damage', 'number', 30), k('knockback', 'Knockback', 'number', 6), k('lift', 'Lift (m)', 'number', null, 'throws the hero up (Player.blast)')] },
    rumble: { label: 'Rumble', telegraph: 'fan', help: '`count` cracks of `length` racing out over `spread_deg`', keys: [k('count', 'Cracks', 'int', 7), k('spread_deg', 'Spread (°)', 'number', 90), k('length', 'Length (m)', 'number', 14), k('speed', 'Speed (m/s)', 'number', 13), k('width', 'Width (m)', 'number', 1.2), k('damage', 'Damage', 'number', 16), k('knockback', 'Knockback', 'number', 10), k('lift', 'Lift (m)', 'number', 3)] },
    brand: { label: 'Brand', telegraph: 'line', help: 'a line of hellfire on the ground for `life` seconds (Game.hell_line; the crowd takes half)', keys: [k('length', 'Length (m)', 'number', 16), k('life', 'Burns for (s)', 'number', 9), k('width', 'Width (m)', 'number', 1.1), k('damage', 'Damage a tick', 'number', 12), k('tick', 'Tick (s)', 'number', 0.5)] },
    tumbleweed_volley: { label: 'Tumbleweed volley', telegraph: 'spokes', help: '`count` tumbleweeds roll out all round for `life` seconds', keys: [k('count', 'Tumbleweeds', 'int', 12), k('speed', 'Speed (m/s)', 'number', 9), k('damage', 'Damage', 'number', 14), k('life', 'Life (s)', 'number', 2.6), k('knockback', 'Knockback', 'number', 14), k('lift', 'Lift (m)', 'number', 2.5), k('spoke_length', 'Spoke length (m)', 'number', null, 'the telegraph\'s lines; empty = how far a tumbleweed rolls')] },
    swoop: { label: 'Swoop', telegraph: 'sector', help: 'a sweep over a wedge ahead, then a fall', keys: [k('count', 'Count', 'int', 14), k('duration', 'Duration (s)', 'number', 0.8), k('fall', 'Fall (s)', 'number', 0.45), k('radius', 'Radius (m)', 'number', 6.5), k('deg', 'Wedge (°)', 'number', 180), k('damage', 'Damage', 'number', 24), k('knockback', 'Knockback', 'number', 14), k('lift', 'Lift (m)', 'number', 3), k('throw', 'Throw', 'number', 12), k('throw_radius', 'Throw radius (m)', 'number', 1.8)] },
    boulder: { label: 'Boulder', telegraph: 'ring_at_hero', needsRingAtHero: true, help: 'a boulder thrown at the hero\'s spot (Game.throw_boulder reads the whole block)', keys: [k('flight', 'Flight (s)', 'number', 1.6), k('radius', 'Radius (m)', 'number', 4.6), k('damage', 'Damage', 'number', 30), k('knockback', 'Knockback', 'number', 26), k('lift', 'Lift (m)', 'number', 6), k('creature_frac', 'Crowd share', 'number', 0.5), k('throw', 'Throw', 'number', 22), k('throw_radius', 'Throw radius (m)', 'number', 6.5), k('size', 'Boulder size', 'number', 1.7), k('arc', 'Arc', 'number', 9)] },
    // pass 95 (lane BOSS): the King's jump and three stomps (EnemyManager._stomp_*), the Scorpion Elite's tail beam (_tail_*)
    stomp: { label: 'Stomp', telegraph: 'ring', help: 'after the wind-up (and its ring) it springs up and lands `stomps` times, `gap` s on the ground between hops: each landing hurts the hero within `radius` + 0.5 m (`damage` x stage x level x host), pushes him `knockback` at the special share and sends a wave of light and dust over the sand; a ring warns before every landing (the King: the old slam, 60% of its damage a stomp, three of them)', keys: [k('stomps', 'Stomps', 'int', 3), k('gap', 'Gap (s)', 'number', 0.45, 'on the ground between a landing and the next hop (x 1/pace); landings come gap + up + down apart'), k('jump', 'Jump', 'json', null, '{"height": 2.2, "up": 0.35, "down": 0.2}: how high it springs (m), the rise and the fall (s); empty = those', { min: undefined }), k('radius', 'Radius (m)', 'number', 6), k('damage', 'Damage a stomp', 'number', 18), k('knockback', 'Knockback', 'number', 6), k('lift', 'Lift (m)', 'number', null, 'throws the hero up instead of the push (Player.blast)')] },
    tail_sniper: { label: 'Tail sniper', telegraph: 'none', help: 'the Saiga Sniper\'s shot from any creature: after the wind-up it freezes, red lines gather from the muzzle on the hero and follow him `aim` s, lock `lock` s, a beam crosses the map (the hero on its line takes the damage and `beam.knockback` at the special share, every creature on it a nick and a push); `count` beams one after the other, `gap` s frozen between, each aimed afresh at where he stands (a moving hero dodges the next); then the cooldown. Nothing but a stun, a freeze, a launch, a grab or hiding spoils it', keys: [k('count', 'Beams', 'int', 3), k('gap', 'Gap (s)', 'number', 0.6, 'frozen between a beam and the next aim, and after the last (x 1/pace)'), k('aim', 'Aim (s)', 'number', 1, 'the lines gather on the hero and follow him this long (x 1/pace)'), k('lock', 'Hold (s)', 'number', 0.4, 'the locked line holds still this long before the beam (x 1/pace): the time to step off it'), k('lines', 'Lines', 'int', 8), k('cone_deg', 'Line cone (°)', 'number', 40), k('damage', 'Damage', 'number', 30.8, 'used without Damage from; x stage x level x host'), k('damage_from', 'Damage from', 'enemy', '', 'a sniper creature: its beam\'s own base (the Saiga: the Vulture Raider\'s rocket x 0.7 = 15.4) x Damage x is the base instead'), k('damage_mult', 'Damage x', 'number', 2, 'with Damage from: the Scorpion\'s 2 = twice the Saiga\'s'), k('beam', 'Beam', 'json', null, '{"length": 60, "width": 0.5, "seconds": 0.15, "knockback": 5, "creature_frac": 0.05, "creature_max": 40, "push": 3, "sparks": 1.5}: the Saiga\'s look and numbers without one', { min: undefined }), k('muzzle', 'Muzzle', 'json', null, '{"up": 2, "side": 0, "forward": -0.4}: where the lines and the beam leave, in metres at the def\'s size (the Scorpion\'s tail tip: up along the painting, forward along the aim)', { min: undefined }), k('sfx', 'Sounds', 'json', null, '{"aim", "lock", "shot"}: sound ids over the creature\'s own, over the Saiga\'s (en_sniper_aim, en_sniper_lock, en_sniper_shot)', { min: undefined })] },
  };
  const ATTACK_NAMES = Object.keys(ATTACKS);
  // pass 72 (lane BOSS): the custom attacks of content/boss_attacks (the Boss attacks tab's list; none under Node)
  const customAttacks = () => (typeof BossAttacks !== 'undefined' && BossAttacks.options ? BossAttacks.options() : []);
  const isCustomAttack = (n) => customAttacks().some((o) => o.v === n);
  const attackOptions = () => ATTACK_NAMES.map((n) => opt(n, ATTACKS[n].label, ATTACKS[n].help)).concat(customAttacks());
  /** the telegraph an attack draws: its own key, else its name's usual */
  const attackTelegraph = (atk) => (isObj(atk) && atk.telegraph ? String(atk.telegraph) : (ATTACKS[String(atk && atk.name)] ? ATTACKS[String(atk.name)].telegraph : 'none'));

  // ------------------------------------------------------------------ the tables

  const T = (section, rows) => rows.map((r) => Object.assign({ section }, r));
  const isBoss = (d) => d.archetype === 'boss';
  const notEvo = (d) => !d.is_evolution;

  const enemy = [].concat(
    T('Identity', [
      { key: 'id', label: 'Id', type: 'slug', required: true, help: 'the folder\'s name: [a-z0-9_]; set when the creature is created' },
      { key: 'name', label: 'Name', type: 'text', required: true, help: 'the display name (toasts, the Collection, "killed by")' },
      { key: 'flavour', label: 'Flavour', type: 'text', help: 'one line under the name in the Collection when doc is empty' },
      { key: 'archetype', label: 'Archetype', type: 'select', options: (v) => v.archetypes, def: 'walker', help: 'only elite and boss change behaviour; the rest are labels' },
      { key: 'brain', label: 'Brain', type: 'select', options: (v) => v.brains, def: 'chase', help: 'how it moves and attacks; an unknown brain chases. A new brain needs code: ask Claude' },
      { key: 'doc', label: 'Doc', type: 'textarea', required: true, help: 'what it is and how it was made: the Collection page and the bible read it; a test wants it non-empty' },
      { key: 'note', label: 'Note', type: 'textarea', help: 'a note for the file; nothing reads it' },
      { key: 'hidden', label: 'Hidden', type: 'bool', def: false, help: 'out of the Collection; still loaded and spawnable by a wave' },
      { key: 'retired', label: 'Retired', type: 'bool', def: false, help: 'out of the game but kept: no map brings it, the Collection leaves it out' },
    ]),
    T('Body', [
      { key: 'hp', label: 'HP', type: 'number', min: 0.1, def: 10, help: 'at spawn x stage x the HP curve x the hero\'s level x creature_hp_mult' },
      { key: 'damage', label: 'Bite', type: 'number', min: 0, def: 5, help: 'contact damage (and a ranged creature\'s shot damage) x stage x level x creature_damage_mult x the damage curve' },
      { key: 'knockback', label: 'Knockback', type: 'number', min: 0.01, step: 0.1, required: true, ph: (d) => M.plain(M.defaultKnockback(num(d.damage, 5))), help: 'the bite\'s shove in m/s; every creature carries one > 0 (the game\'s own would be clamp(3.4 x sqrt(damage / 4), 2.5, 7)); x1.6 for bosses and elites' },
      { key: 'speed', label: 'Speed (m/s)', type: 'number', min: 0, def: 2.5, help: 'x stage_speed_mult x the variance jitter x pace' },
      { key: 'size', label: 'Size (m)', type: 'number', min: 0.05, step: 0.05, def: 1, help: 'the sprite\'s height in metres (one number; a range is a roster row\'s)' },
      { key: 'radius', label: 'Radius (m)', type: 'number', min: 0.05, step: 0.05, def: 0.5, help: 'contact and separation radius; the bite reaches radius + 0.45' },
      { key: 'damage_reduction', label: 'Damage reduction', type: 'number', min: 0, max: 0.9, step: 0.05, def: 0, help: 'share of every hit removed, 0..0.9' },
      { key: 'knockback_resist', label: 'Knockback resist', type: 'number', min: 0, max: 1, step: 0.05, def: 0, help: 'the OTHER direction from Knockback above: the share of every shove from the hero\'s side (a hit\'s knockback, a blast\'s throw, the Lasso\'s pull, Buck\'s Ram) it shrugs off, 0..1: 0 = thrown as its size says, 0.67 = a third of the push (the Hammer Giant), 1 = never moved. Not a damage reduction. A boss keeps 0 (its own 0.15 stays on top). Pass 67' },
      { key: 'contact_cd', label: 'Bite every (s)', type: 'number', min: 0.05, step: 0.05, def: 0.6, help: 'seconds between bites' },
      { key: 'blood', label: 'Blood', type: 'swatch', ph: '#C70D0D', help: 'the death splash\'s colour, #RRGGBB (a test wants a valid one in every file)' },
      { key: 'shadow.scale', label: 'Shadow scale', type: 'shadow_scale', help: 'one number, or [width, depth]' },
      { key: 'shadow.up', label: 'Shadow up (m)', type: 'number', step: 0.05, help: 'how high the blob sits (divided by size)' },
      { key: 'shadow.drop', label: 'Shadow drop', type: 'number', min: -0.5, max: 0.5, step: 0.02, help: '−0.5..0.5' },
      { key: 'head', label: 'Head (share of the cell)', type: 'number', min: 0, max: 1, step: 0.01, def: 0.86, help: 'where the top of the figure is: the badge sits there, the sand sink reads it; measured by the art tools' },
      { key: 'front_faces', label: 'Front faces', type: 'select', options: (v) => v.faces, def: 'right', help: 'the mirror rule of the front set' },
      { key: 'back_faces', label: 'Back faces', type: 'select', options: (v) => v.faces, def: 'right', help: 'the mirror rule of the back set' },
      // pass 73 (lane SNIPER): an attack strip painted from the front and the back (the Saiga Sniper's aim)
      { key: 'attack_views', label: 'Attack strip views', type: 'select', options: [opt('', 'front only (the default)', 'every attack frame faces the camera'), opt('front_back', 'front, then back', 'the attack strip\'s first half is painted from the front, its second half from the back; the game shows the half his facing shows')], def: '', help: 'how the attack frames are painted' },
      { key: 'badge', label: 'Badge', type: 'select', options: (v) => v.badges, def: '', help: 'the icon over its head; the crown shows only on the elite archetype' },
    ]),
    T('Spawning', [
      { key: 'pack_size', label: 'Pack', type: 'int', min: 1, def: 1, help: 'how many a burst brings (a roster row\'s pack wins)' },
      { key: 'cap_share', label: 'Cap share', type: 'number', min: 0.05, step: 0.05, def: 1, help: 'how much of the live cap one takes (0.5: two to a slot)' },
      { key: 'max_alive', label: 'Max alive', type: 'int', min: 0, def: 0, help: '0 = no limit; counted across all its looks and overrides' },
      { key: 'xp_mult', label: 'XP x', type: 'number', min: 0, step: 0.1, def: 1, help: 'gem scale' },
      { key: 'can_be_elite', label: 'Can be coloured', type: 'bool', def: true, help: 'may take an Elite modifier' },
      { key: 'can_be_grabbed', label: 'Can be grabbed', type: 'bool', def: true, help: 'the Gravity Gun may lift it' },
      { key: 'pickup_chance_mult', label: 'Power-up chance x', type: 'number', min: 0, step: 0.1, def: 1, help: 'x the timeline\'s per-kill chance' },
      { key: 'pickup_weights', label: 'Power-up weights', type: 'pickup_weights', help: 'replaces the map\'s power-up roster for this creature\'s kills' },
    ]),
    T('Drops', [
      { key: 'drops.small', label: 'Small gem', type: 'number', min: 0, max: 1, step: 0.01, help: 'chance of a 1-XP gem (the default block when drops is absent: small 1, gold 0.02)' },
      { key: 'drops.medium', label: 'Medium gem', type: 'number', min: 0, max: 1, step: 0.01, help: 'chance of a 5-XP gem (+ luck x 0.1)' },
      { key: 'drops.large', label: 'Large gem', type: 'number', min: 0, max: 1, step: 0.01, help: 'chance of a 25-XP gem' },
      { key: 'drops.gold', label: 'Coins', type: 'number', min: 0, max: 1, step: 0.005, help: 'chance of 1-3 coins, x (1 + luck)' },
      { key: 'drops.chest', label: 'Chest', type: 'number', min: 0, max: 1, step: 0.001, help: 'chance of a chest (an elite always drops one)' },
      { key: 'drops.pickup.id', label: 'Own power-up', type: 'pickup', help: 'a power-up of its own' },
      { key: 'drops.pickup.chance', label: 'Own power-up chance', type: 'number', min: 0, max: 1, step: 0.01 },
      { key: 'drops.coins', label: 'Boss coins', type: 'int', min: 0, def: 12, only: isBoss, help: 'boss only: coins worth 5 each' },
      { key: 'drops.chests', label: 'Boss chests', type: 'int', min: 0, def: 1, only: isBoss, help: 'boss only: chests − 1 extra chests on top of the boss chest' },
    ]),
    T('Variance', [
      { key: 'variance.size', label: 'Size jitter', type: 'number', min: 0, step: 0.05, def: 0, help: '± this on the size' },
      { key: 'variance.speed', label: 'Speed jitter', type: 'number', min: 0, step: 0.05, def: 0, help: '± this on the speed' },
      { key: 'variance.tints', label: 'Tints', type: 'swatches', help: 'colours rolled once Run.kills >= the map\'s colour_after_kills' },
      { key: 'variance.tint_strength', label: 'Tint strength', type: 'number', min: 0, max: 0.3, step: 0.01, def: 0.35, help: 'the shader mixes alpha x 0.65; a test wants ≤ 0.3' },
    ]),
    // pass 69 (lane EN; Garry: the specials' colouring "should be possible in the Level Editor, right now it's just a set
    // of colour choices that I can't control"): the coloured variance special on its own, with its glow; an empty box
    // takes the map's special_defaults (Settings → Coloured specials), else the game's (EnemyDef.SPECIAL_DEFAULTS); the
    // section's table says which applies
    T('Special', [
      { key: 'variance.special_chance', label: 'Chance', type: 'number', min: 0, max: 1, step: 0.005, def: 0, help: 'the chance one comes as its coloured special, × (1 + the hero\'s difficulty) with Hot Sauce, once the map\'s colour_after_kills is reached (a swarm event set to Special brings it for sure). Pass 69: a third of what it was (the goblin 0.04 = one in 25)' },
      { key: 'variance.special.size', label: 'Size ×', type: 'number', min: 0.1, step: 0.05, def: 1.5, help: 'a special is exactly this much taller than the creature\'s own size (its body too; the plain ones\' size spread does not apply to it, pass 69); in a row with a size range it grows towards the range\'s top, never past it. Pass 72: ×1.5 (was ×1.25)' },
      { key: 'variance.special.hp', label: 'HP ×', type: 'number', min: 0.1, step: 0.5, def: 15, help: 'its health × this (pass 72: ×15, was ×10)' },
      { key: 'variance.special.damage', label: 'ATK ×', type: 'number', min: 0.1, step: 0.1, def: 2, help: 'its bites and shots × this (pass 69: ×2)' },
      { key: 'variance.special.xp', label: 'XP ×', type: 'number', min: 0, step: 0.5, def: 2, help: 'its gems × this (and how hard its kill counts for power-ups)' },
      { key: 'variance.special.tint', label: 'Colour', type: 'swatch', help: 'the colour it is washed with and its glow\'s hue (the glow draws the colour at full brightness); empty = it keeps a plain one\'s tint. In a row with a colour range it takes a darker shade of the hue it rolled instead. A dark, saturated colour reads best (a light one washes it pale): a warning, not a rule' },
      { key: 'variance.special.tint_strength', label: 'Colour strength', type: 'number', min: 0, max: 1, step: 0.05, def: 0.6, help: 'how strongly the colour shows on its body (the shader mixes strength × 0.65)' },
      { key: 'variance.special.glow', label: 'Glow', type: 'number', min: 0, max: 1, step: 0.05, def: 0.6, help: 'pass 69: an emissive rim round it in its colour, so it reads at a glance in a crowd: 0 = none, 1 = the widest and brightest; it breathes slowly. Burn, poison and freeze tint the rim while they last' },
      { key: 'variance.special.chest_chance', label: 'Chest chance', type: 'number', min: 0, max: 1, step: 0.05, def: 0.35, help: 'pass 72: the chance its death drops a chest (0.35 = about one in three; 0 = never, 1 = always); empty = the map\'s Coloured specials, else the game\'s 0.35. At most the map\'s Max alive (Settings → Coloured specials, the game\'s 3) live at once: a roll past it comes plain; a Special swarm still comes' },
    ]),
    T('Sounds', [
      { key: 'sfx.hit', label: 'Hit', type: 'sfx', group: 'en_', help: 'when it is hit; empty = silent' },
      { key: 'sfx.die', label: 'Die', type: 'sfx', group: 'en_', help: 'when it dies' },
      { key: 'sfx.attack', label: 'Attack', type: 'sfx', group: 'en_', help: 'a charge, a shot, a wind-up (the script\'s default en_boss_attack)' },
      { key: 'sfx.spawn', label: 'Spawn (boss)', type: 'sfx', group: 'en_', only: isBoss, help: 'boss archetype only, default en_boss_roar (elites always play en_elite_spawn)' },
      // pass 73 (lane SNIPER): the sniper brain's three sounds
      { key: 'sfx.aim', label: 'Aim (sniper)', type: 'sfx', group: 'en_', only: (d) => d.brain === 'sniper', help: 'the sniper brain: as its aim starts and the lines gather' },
      { key: 'sfx.lock', label: 'Lock (sniper)', type: 'sfx', group: 'en_', only: (d) => d.brain === 'sniper', help: 'the sniper brain: as the line locks, before the hold' },
      { key: 'sfx.shot', label: 'Shot (sniper)', type: 'sfx', group: 'en_', only: (d) => d.brain === 'sniper', help: 'the sniper brain: the laser crossing the map' },
    ]),
    T('Looks', [
      { key: 'variant_base', label: 'Base look', type: 'readonly', help: 'the code of the top-level strip' },
      { key: 'variant', label: 'Look in play', type: 'readonly', help: 'set by "Make default" on a look' },
      { key: 'directions', label: 'Directions painted', type: 'select', options: (v) => v.directions, def: 2, help: 'art recipe: 2 (front and back) or 8' },
      { key: 'frame_px', label: 'Cell (px)', type: 'int', min: 16, def: 128, help: 'the strip\'s cell size (the placeholder\'s cell; the shader slices by count)' },
      { key: 'strip_cols', label: 'Strip columns', type: 'int', min: 0, def: 0, help: '0 = one row; a packed strip\'s column count (written by the art tools)' },
      { key: 'anims', label: 'Frames per animation', type: 'anims', help: 'in the fixed order idle, run, attack, hit, die, run_b, idle_b, run_s, idle_s, run_bd, idle_bd, run_fd, idle_fd (the art tools write them)' },
      { key: 'fps', label: 'Frame rates', type: 'fps_table', keys: ['run', 'die'], help: 'run 0 = 10 fps x pace; die 6' },
    ]),
    T('Art words', [
      { key: 'art_prompt', label: 'Subject', type: 'textarea', help: 'what the painter draws (default "a goofy <name> creature, <flavour>")' },
      { key: 'appearance', label: 'Appearance', type: 'textarea', help: 'what it looks like, without a pose: the icon candidates\' subject words (pass 68); empty = the Subject with its pose clause cut' },
      { key: 'motion', label: 'Motion', type: 'textarea', help: 'how the free walk clip moves ("walking in place with a steady stomping gait")' },
      { key: 'anim_negative', label: 'Never in a clip', type: 'textarea', help: 'what the clip must not grow (faces, extra limbs)' },
      { key: 'dead_hint', label: 'Dead still', type: 'textarea', help: 'how it lies dead' },
      { key: 'back_hint', label: 'Back view', type: 'textarea', help: 'added to the back-view turn' },
      { key: 'view_hints.side', label: 'Side view', type: 'textarea', help: '8 directions: the side turn' },
      { key: 'view_hints.bd', label: 'Back-diagonal view', type: 'textarea' },
      { key: 'view_hints.fd', label: 'Front-diagonal view', type: 'textarea' },
      { key: 'view_hints.back', label: 'Back (ctl)', type: 'textarea' },
      { key: 'death', label: 'Death', type: 'select', options: (v) => v.deaths, def: '', help: 'how the dying frames are made' },
      { key: 'death_frames', label: 'Death frames', type: 'int', min: 1, def: 8 },
      { key: 'walk', label: 'Walk', type: 'select', options: (v) => v.walks, def: '', help: '"hop": procedural, no video (blobs)' },
      { key: 'hop_height', label: 'Hop height', type: 'number', min: 0, step: 0.01, def: 0.13 },
      { key: 'pose', label: 'Pose driver (back)', type: 'driver', help: 'a Mixamo stride for the back clip (creature_pose2)' },
      { key: 'pose_front', label: 'Pose driver (front)', type: 'driver' },
      { key: 'stand', label: 'Stand', type: 'select', options: (v) => v.stands, def: '' },
      { key: 'gait', label: 'Gait', type: 'text' },
      { key: 'anim_seed', label: 'Clip seed', type: 'int', min: 0, def: 0 },
      { key: 'run_fps', label: 'Run fps (recipe)', type: 'int', min: 1, def: 15 },
      { key: 'cell_fill', label: 'Cell fill', type: 'number', min: 0.1, max: 1, step: 0.01, def: 0.86, help: 'how much of the cell the figure fills' },
      { key: 'clip_fill', label: 'Clip fill', type: 'number', min: 0.1, max: 1, step: 0.01, def: 0.72 },
      { key: 'screen', label: 'Screen', type: 'select', options: (v) => v.screens, def: '', help: 'the keying colour behind the paintings' },
      { key: 'outline_frac', label: 'Outline', type: 'number', min: 0, step: 0.001, def: 0.024 },
      { key: 'outline_color', label: 'Outline colour', type: 'swatch', ph: '#0E080C' },
      { key: 'remap_hues', label: 'Remap hues', type: 'json', help: '{ranges: [[lo, hi]...], to, sat, min_sat}' },
      { key: 'placeholder.color', label: 'Placeholder colour', type: 'swatch', help: 'the procedural stand-in art and the screen colour\'s choice' },
      { key: 'placeholder.shape', label: 'Placeholder shape', type: 'select', options: (v) => v.placeholderShapes, def: '' },
      { key: 'placeholder.eyes', label: 'Placeholder eyes', type: 'int', min: 0, max: 8 },
      { key: 'placeholder.ears', label: 'Placeholder ears', type: 'text', help: 'horn, round, ...' },
    ]),
  );

  const hero = [].concat(
    T('Identity', [
      { key: 'id', label: 'Id', type: 'slug', required: true, help: 'the folder\'s name' },
      { key: 'name', label: 'Name', type: 'text', required: true, help: '"The " is added for the drifter only' },
      { key: 'flavour', label: 'Flavour', type: 'text', help: 'the line under the name on the title' },
      { key: 'order', label: 'Order', type: 'int', min: 1, def: 100, help: 'the title carousel\'s order among playable heroes (warns on a clash)' },
      { key: 'pronoun', label: 'Pronoun', type: 'select', options: (v) => v.pronouns, def: 'they', help: 'he / she / they: hints, "his" in the trait note, the sheet' },
      { key: 'hidden', label: 'Hidden', type: 'bool', def: false, help: 'out of play; kept in step with Availability below (pass 69: ticking it sets Availability hidden, unticking a hidden hero sets it free)', after: (d, v) => { if (v) d.availability = 'hidden'; else if (d.availability == null || d.availability === 'hidden') d.availability = 'available'; } },
    ]),
    T('Trait', [
      { key: 'trait_name', label: 'Trait name', type: 'text', help: 'the plaque and sheet title ("Long Road")' },
      { key: 'trait_per_level', label: 'Per level', type: 'stat_effects', stats: 'player', target: 'player', help: 'the signature stat(s): one Effect per entry worth value x level' },
      { key: 'trait_preview', label: 'Reads as', type: 'trait_preview', help: 'TextGen.hero_trait from the rule above, and what it comes to at level 20' },
      { key: 'trait_text', label: 'Trait text', type: 'textarea', help: 'read when there is no per-level rule (the hidden heroes), and said after the rule for a hero with a special (pass 67: Buck\'s charge); a test wants it equal to the rule\'s sentence for the other played heroes' },
      { key: 'trait', label: 'Flat trait (legacy)', type: 'stat_effects', stats: 'player', target: 'player', help: 'added to the sheet once; empty on every played hero (a test wants it empty)' },
      { key: 'level_heal', label: 'Heal per level', type: 'percent', def: 0, help: 'share of max HP healed on every level-up (Astro 8%)' },
    ]),
    T('Favourites', [
      { key: 'favourite_weapon', label: 'Favourite weapon', type: 'id_select', kind: 'weapon', help: 'FAVOURITE plate; bypasses its unlock quest; his hero mutation sits on it' },
      { key: 'favourite_bonus.type', label: 'Favourite arrives', type: 'select', options: (v) => v.favouriteBonus, def: 'level', help: 'at a level, or with effects' },
      { key: 'favourite_bonus.value', label: 'At level', type: 'int', min: 1, def: 2, only: (d) => !d.favourite_bonus || (d.favourite_bonus.type || 'level') === 'level' },
      { key: 'favourite_bonus.effects', label: 'With effects', type: 'stat_effects', stats: 'weapon', target: 'self', only: (d) => d.favourite_bonus && d.favourite_bonus.type === 'effects' },
      { key: 'favourite_passive', label: 'Favourite passive', type: 'id_select', kind: 'passive', help: 'a card or a passive item (Ironwood\'s: The Sun, id brawn): bypasses the quest' },
      { key: 'favourite_passive_bonus.type', label: 'Passive arrives', type: 'select', options: (v) => v.passiveBonus, def: 'level', only: (d) => !!d.favourite_passive },
      { key: 'favourite_passive_bonus.value', label: 'At level', type: 'int', min: 1, def: 2, only: (d) => !!d.favourite_passive && (!d.favourite_passive_bonus || (d.favourite_passive_bonus.type || 'level') === 'level') },
      { key: 'favourite_passive_bonus.effects', label: 'With effects', type: 'stat_effects', stats: 'player', target: 'player', only: (d) => !!d.favourite_passive && d.favourite_passive_bonus && d.favourite_passive_bonus.type === 'effects' },
      { key: 'start_weapon', label: 'Starts with', type: 'id_select', kind: 'weapon', help: 'empty = his own weapon (WeaponDef.hero), else the favourite, else the peashooter' },
    ]),
    T('Specials', [
      { key: 'specials', label: 'Specials', type: 'checklist', options: (v) => v.specials, help: 'the mechanisms the code knows; a new one needs code: ask Claude' },
      { key: 'momentum.ramp_seconds', label: 'Momentum ramp (s)', type: 'number', min: 0, def: 12, only: (d) => Array.isArray(d.specials) && d.specials.includes('momentum') },
      { key: 'momentum.speed_bonus', label: 'Momentum speed', type: 'number', min: 0, step: 0.05, def: 0.6, only: (d) => Array.isArray(d.specials) && d.specials.includes('momentum') },
      { key: 'momentum.might_bonus', label: 'Momentum damage', type: 'number', min: 0, step: 0.05, def: 0.5, only: (d) => Array.isArray(d.specials) && d.specials.includes('momentum') },
      { key: 'momentum.evade_bonus', label: 'Momentum evade', type: 'number', min: 0, max: 0.9, step: 0.05, def: 0, help: 'evade chance added at full charge (Run._build_player_sheet; an evaded hit never touches the charge). Pass 67', only: (d) => Array.isArray(d.specials) && d.specials.includes('momentum') },
      { key: 'momentum.hit_loss', label: 'A hit knocks off (share)', type: 'number', min: 0, max: 1, step: 0.05, def: 1, help: 'the share of the charge a hit that lands takes (Player.take_damage): 0.5 = half, 1 = all of it (the old reset). Pass 67', only: (d) => Array.isArray(d.specials) && d.specials.includes('momentum') },
      { key: 'unlock_quest', label: 'Unlock quest', type: 'readonly', help: 'a dead key: never read. A hero is gated by a quest whose unlocks names him' },
    ]),
    T('Availability', [
      // pass 69 (lane UI wired it: Registry.hero_state owned | buyable | locked | hidden): changing it keeps `hidden` in step
      { key: 'availability', label: 'Availability', type: 'select', options: (v) => v.availability, def: 'available', help: 'free = owned from the start (with a Requirement: owned once its quest is done); to buy = on the title and in the hero drawer as a black silhouette, locked until the Requirement is done, then BUY for the price; hidden = out of play. A bought hero is kept in the save (heroes_owned)', after: (d, v) => { const hide = v === 'hidden'; if ('hidden' in d || hide) d.hidden = hide; } },
      { key: 'price', label: 'Price', type: 'int', min: 0, def: 0, only: (d) => d.availability === 'purchase', help: 'what BUY costs, spent from the gold he banked (Save.buy_hero; the Coins board\'s sink "hero"). 0 = free once the requirement is done' },
      { key: 'currency_type', label: 'Currency', type: 'select', options: (v) => v.currencies, def: 'gold', only: (d) => d.availability === 'purchase', help: 'only gold can be spent today' },
    ]),
    T('Art words', [
      { key: 'art_prompt', label: 'Subject', type: 'textarea', help: 'the painter\'s subject (default "a small goofy hero called <name>, <flavour>")' },
      { key: 'appearance', label: 'Appearance', type: 'textarea', help: 'who he or she is, without a pose: the Character words the badge and title cut-out candidates start from (pass 68; a look\'s recipe may carry its own); empty = the Subject with its pose clause cut ("; standing straight, both arms relaxed at her sides")' },
      { key: 'portrait_prompt', label: 'Badge portrait', type: 'textarea', help: 'the round badge\'s action: "smiling at the viewer" (the Action of the badge candidates)' },
      { key: 'motion', label: 'Free clip motion', type: 'textarea', help: '"running in place at a steady jog, arms and legs swinging naturally"' },
      { key: 'pose_motion', label: 'Pose clip motion', type: 'textarea', help: '"running in place on the spot like on a treadmill"' },
      { key: 'anim_hint', label: 'Clip subject', type: 'textarea', help: 'what the clip keeps (default: the subject\'s first clause)' },
      { key: 'anim_negative', label: 'Never in a clip', type: 'textarea' },
      { key: 'anim_seed', label: 'Clip seed', type: 'int', min: 0, def: 0 },
      { key: 'hurt_hint', label: 'Hurt', type: 'textarea', help: '"eyes squeezed shut, teeth gritted"' },
      { key: 'back_hint', label: 'Back view', type: 'textarea' },
      { key: 'pose_hint', label: 'Pose', type: 'textarea' },
      { key: 'side_hint', label: 'Side view', type: 'textarea' },
      { key: 'pose_drivers.front', label: 'Driver: front', type: 'driver', help: 'the OpenPose driver of the front clip (default run)' },
      { key: 'pose_drivers.back', label: 'Driver: back', type: 'driver' },
      { key: 'pose_drivers.side', label: 'Driver: side', type: 'driver' },
      { key: 'pose_drivers.fd', label: 'Driver: front-diagonal', type: 'driver' },
      { key: 'pose_drivers.bd', label: 'Driver: back-diagonal', type: 'driver' },
      { key: 'still_keys', label: 'Still keys', type: 'json', help: '{view: cache key} when a view\'s still was painted under another name' },
      { key: 'run_fps', label: 'Run fps (recipe)', type: 'int', min: 1, def: 36, help: '36; 14 when a clip fell back' },
      { key: 'screen', label: 'Screen', type: 'select', options: (v) => v.screens, def: '', help: 'heroes are keyed off blue unless named' },
      { key: 'key_sat', label: 'Key saturation', type: 'number', min: 0, max: 1, step: 0.05, def: 0.35 },
      { key: 'key_min_value', label: 'Key min value', type: 'number', min: 0, max: 1, step: 0.05, def: 0.2 },
      { key: 'key_cut_shadow', label: 'Key cuts shadow', type: 'bool', def: true },
      { key: 'key_clamp_screen', label: 'Key clamps screen', type: 'bool', def: false },
      { key: 'grade', label: 'Grade', type: 'json', help: '{hue, sat_mul, sat_range, hue_shift, sat_max}' },
      { key: 'remap_hues', label: 'Remap hues', type: 'json' },
      { key: 'badge.still', label: 'Badge still', type: 'text', help: 'the cached still the round badge is cut from' },
      { key: 'badge.head_width', label: 'Badge head width', type: 'number', min: 0, max: 1, step: 0.05, def: 0 },
      { key: 'badge.top_pad', label: 'Badge top pad', type: 'number', min: 0, max: 0.5, step: 0.01, def: 0.03 },
      { key: 'badge.note', label: 'Badge note', type: 'textarea' },
      { key: 'title_pose', label: 'Title pose', type: 'textarea', help: 'the title cut-out\'s pose words (gen_title_heroes; falls back to its table, then the badge portrait)' },
      { key: 'title_holds', label: 'Title holds', type: 'textarea', help: 'what he holds on the title ("the <object> is the only thing he holds")' },
      { key: 'title_camera', label: 'Title camera', type: 'textarea' },
      { key: 'title_extra_ref.file', label: 'Title object reference', type: 'text', help: 'a picture of the held object, copied exactly' },
      { key: 'title_extra_ref.words', label: 'Title object words', type: 'textarea' },
    ]),
    T('Looks & previews', [
      { key: 'variant_base', label: 'Base look', type: 'readonly' },
      { key: 'variant', label: 'Look in play', type: 'readonly', help: 'the JSON\'s look; Save.hero_look overrides it in runs' },
      { key: 'frame_px', label: 'Cell (px)', type: 'int', min: 16, def: 256 },
      { key: 'strip_cols', label: 'Strip columns', type: 'int', min: 0, def: 0 },
      { key: 'anims', label: 'Frames per animation', type: 'anims', help: 'CHAR_ORDER: idle, run, turn, hit, die, cheer, idle_f, run_f, idle_s, run_s, idle_bd, run_bd, idle_fd, run_fd, hit_f, hit_s, hit_bd, hit_fd' },
      { key: 'fps', label: 'Frame rates', type: 'fps_table', keys: ['run', 'hit', 'die', 'idle', 'cheer'], help: 'BillboardSprite: run 14, hit 6, die 5, idle 4, cheer 4 when absent (the heroes carry run 36, hit 12, die 8)' },
    ]),
  );

  const weapon = [].concat(
    T('Identity', [
      { key: 'id', label: 'Id', type: 'slug', required: true },
      { key: 'name', label: 'Name', type: 'text', required: true },
      { key: 'flavour', label: 'Flavour', type: 'text', help: 'the card\'s line' },
      { key: 'rarity', label: 'Rarity', type: 'select', options: (v) => v.rarities, def: 'common', help: 'card weight x RARITY_W (common 1, uncommon 0.75, rare 0.55, epic 0.3, legendary 0.15) and the plate\'s colour' },
      { key: 'weight', label: 'Weight', type: 'number', min: 0, def: 10, help: 'the card pool\'s weight' },
      { key: 'hero', label: 'Hero only', type: 'id_select', kind: 'hero', help: 'only this hero is offered it; empty = everyone\'s' },
      { key: 'tags', label: 'Tags', type: 'tags', help: 'gun, blade, melody, melee, homing, explosive, thrown, magic: effects with target tag:<tag> reach it' },
      { key: 'is_evolution', label: 'Evolution', type: 'readonly', only: (d) => !!d.is_evolution, help: 'an evolved form: level 1 only, delivered by a chest' },
      { key: 'evolved_from', label: 'Evolved from', type: 'readonly', only: (d) => !!d.is_evolution },
    ]),
    T('Behaviour', [
      { key: 'behavior', label: 'Behaviour', type: 'select', options: (v) => v.behaviors, def: 'ProjectileEmitter', help: 'the script that fires it (game/core/behaviors); a new one needs code: ask Claude' },
      { key: 'targeting', label: 'Targeting', type: 'select', options: (v) => v.targeting, def: 'nearest', help: 'priority / forward / random / healthy change the aim; the rest describe' },
      { key: 'visual', label: 'Visual', type: 'readonly', ph: (d, c) => `${c.id || d.id}_visual.tscn`, help: 'the 3D scene (Claude\'s): nodes Projectile, Held, Muzzle, Familiar' },
    ]),
    T('Base stats', BASE_KEYS.map((s) => ({ key: 'base.' + s, label: M.statName(s), type: 'number', min: 0, step: s === 'cooldown' ? 0.05 : 'any', int: ['amount', 'pierce', 'chains', 'poison_stacks'].includes(s), def: BASE_DEFAULTS[s], help: `${s}: the game's own is ${BASE_DEFAULTS[s]}` }))),
    T('Levels', [
      { key: 'levels', label: 'Levels', type: 'level_steps', fixed: 5, stats: 'weapon', target: 'self', help: 'levels[i] = the effects gained reaching level i + 1; level 1 is always empty (the tests pin exactly 5 lists)' },
      { key: 'max_level', label: 'Max level', type: 'int', min: 1, def: 5, help: 'base weapons 5 (a test), evolutions 1' },
    ]),
    T('Evolution & path', [
      { key: 'evolves_into', label: 'Evolves into', type: 'id_select', kind: 'evolution', only: notEvo, help: 'its evolved form (at level 5 with all three path mutations, from a chest)' },
      { key: 'evolves_with', label: 'Evolves with', type: 'id_select', kind: 'passive', only: notEvo, help: 'must stay empty: evolutions come from the path, not an item (a test)' },
      { key: 'path', label: 'Path', type: 'path_strip', only: notEvo, help: 'its three path mutations (element, volume, motion) and its hero mutations' },
    ]),
    T('Params', [
      // pass 69 (lane LE): the knobs the pass's behaviours and mechanisms read, typed (PARAM_GROUPS), above the JSON
      { key: 'params_typed', label: 'Typed params', type: 'params_fields', help: 'the params this weapon\'s behaviour reads, one field each with what it does; an empty box shows what applies without it and where that comes from. They write into the JSON below' },
      { key: 'params', label: 'Params', type: 'params_json', help: 'the behaviour\'s knobs as JSON; `final` is merged after the mutations (evolutions)' },
    ]),
    T('Sounds', [
      { key: 'sfx.fire', label: 'Fire', type: 'sfx', group: 'w_' },
      { key: 'sfx.hit', label: 'Hit', type: 'sfx', group: 'w_' },
      { key: 'sfx.place', label: 'Place', type: 'sfx', group: 'w_', help: 'mines, turrets' },
      { key: 'sfx.burst', label: 'Burst', type: 'sfx', group: 'w_' },
      { key: 'sfx.reload', label: 'Reload', type: 'sfx', group: 'w_', help: 'the Missile Pod' },
      { key: 'sfx.land', label: 'Land', type: 'sfx', group: 'w_', help: 'the Gravity Gun' },
    ]),
    T('Availability', [
      { key: 'hidden', label: 'Hidden', type: 'bool', def: false, help: 'never offered; held copies still level' },
      { key: 'quest_lock', label: 'Unlock quest', type: 'quest_lock', only: notEvo, help: 'the quest whose unlocks names this item; none = available at once' },
      { key: 'from_stage', label: 'From stage', type: 'int', min: 0, def: 0, help: 'offered from this stage on (0 = always)' },
      { key: 'band', label: 'Quest-locked band', type: 'band', only: notEvo, help: 'the share of base items behind a quest the ship test wants between 33% and 56%' },
    ]),
    T('Art', [
      { key: 'art_prompt', label: 'Icon subject', type: 'textarea', help: 'what the icon painter draws' },
      { key: 'placeholder.color', label: 'Placeholder colour', type: 'swatch' },
      { key: 'placeholder.glyph', label: 'Placeholder glyph', type: 'text', help: 'gun, star, magnet, ...' },
      { key: 'icon', label: 'Icon', type: 'icon_preview', help: 'the 256 px icon at the sheet\'s 128, the list\'s 64 and the HUD\'s 36 on its rarity plate' },
    ]),
  );
  // the evolution form is the weapon's with its own emphasis; the renderer reads `only` (is_evolution)
  const evolution = weapon;

  // pass 95 (lane PASSIVES): a passive item (not a card, not an evolved form) climbs the rarity ladder one rung an
  // upgrade (PassiveDef.ladder_levels): common 6 levels, uncommon 5, rare 4, epic 3, legendary 2; its top is Evolved.
  // The game derives max_level from the rarity; the JSON lists every rung's effects (tools/passive_ladder.py).
  const LADDER = ['common', 'uncommon', 'rare', 'epic', 'legendary'];
  const ladderIndex = (rarity) => Math.max(LADDER.indexOf(String(rarity == null || rarity === '' ? 'common' : rarity)), 0);
  const ladderLevels = (rarity) => LADDER.length - 1 - ladderIndex(rarity) + 2;
  const rungAt = (rarity, level) => (level >= ladderLevels(rarity) ? 'evolved' : LADDER[Math.min(ladderIndex(rarity) + Math.max(level, 1) - 1, LADDER.length - 1)]);
  const rungName = (rarity, level) => { const r = rungAt(rarity, level); return r === 'evolved' ? 'Evolved' : r.charAt(0).toUpperCase() + r.slice(1); };
  const onLadder = (d) => !!d && !d.line && !(d.evolves_from != null && String(d.evolves_from).trim() !== '');

  const passive = [].concat(
    T('Identity', [
      { key: 'id', label: 'Id', type: 'slug', required: true },
      { key: 'name', label: 'Name', type: 'text', required: true },
      { key: 'flavour', label: 'Flavour', type: 'text' },
      { key: 'rarity', label: 'Rarity', type: 'select', options: (v) => v.rarities, def: 'common' },
      { key: 'weight', label: 'Weight', type: 'number', min: 0, def: 10, help: 'evolved cards carry 0: they come from their base card' },
      { key: 'line', label: 'Card (line item)', type: 'bool', def: false, help: 'a fortune card (`line` in the JSON; pass 73) takes one of the 5 card slots and evolves when maxed; else a passive item (no cap)' },
    ]),
    T('Levels', [
      { key: 'levels', label: 'Levels', type: 'level_steps', stats: 'player', target: 'player', help: 'the effects per level (target player; a weapon stat with target all_weapons reaches every weapon, as Kindling does); a card lists one level and repeats it; a passive item lists every rung of its rarity ladder (pass 95: its rarity up to legendary, then Evolved)' },
      { key: 'repeat_last_level', label: 'Repeat the last level', type: 'bool', def: true, help: 'a shorter list repeats its last level up to Max level' },
      { key: 'max_level', label: 'Max level', type: 'int', min: 1, def: 8, help: 'cards 4, evolved cards 1; a passive item: derived from its rarity (pass 95: common 6, uncommon 5, rare 4, epic 3, legendary 2), the game ignores the number here' },
    ]),
    T('Links', [
      { key: 'pairs_with', label: 'Pairs with', type: 'id_select', kind: 'any_item', help: 'informational' },
      { key: 'trade', label: 'Trade', type: 'text', help: 'what it costs, in words' },
      { key: 'evolves_into', label: 'Evolves into', type: 'id_select', kind: 'passive', only: (d) => !d.evolves_from, help: 'a card\'s evolved form, its Risen card (both must agree on `line`)' },
      { key: 'evolves_from', label: 'Evolved from', type: 'id_select', kind: 'passive', only: (d) => !!d.evolves_from || !d.evolves_into, help: 'marks the evolved form: never offered alone' },
    ]),
    T('Text', [
      { key: 'text', label: 'Card text', type: 'textarea', help: 'the new card\'s line (else TextGen writes "X per level...")' },
      { key: 'element', label: 'Element', type: 'select', options: (v) => v.elements, def: '' },
    ]),
    T('Availability', [
      { key: 'hidden', label: 'Hidden', type: 'bool', def: false },
      { key: 'quest_lock', label: 'Unlock quest', type: 'quest_lock', only: (d) => !d.evolves_from },
      { key: 'from_stage', label: 'From stage', type: 'int', min: 0, def: 0 },
      { key: 'band', label: 'Quest-locked band', type: 'band', only: (d) => !d.evolves_from },
    ]),
    T('Art', [
      { key: 'art_prompt', label: 'Icon subject', type: 'textarea' },
      { key: 'placeholder.color', label: 'Placeholder colour', type: 'swatch' },
      { key: 'placeholder.glyph', label: 'Placeholder glyph', type: 'text' },
      { key: 'icon', label: 'Icon', type: 'icon_preview' },
    ]),
  );

  const mutation = [].concat(
    T('Identity', [
      { key: 'id', label: 'Id', type: 'slug', required: true },
      { key: 'name', label: 'Name', type: 'text', required: true },
      { key: 'flavour', label: 'Flavour', type: 'text' },
      { key: 'rarity', label: 'Rarity', type: 'select', options: (v) => v.rarities, def: 'rare' },
      { key: 'weight', label: 'Weight', type: 'number', min: 0, def: 8 },
      { key: 'weapon', label: 'Weapon', type: 'id_select', kind: 'weapon', required: true, help: 'the family it mutates' },
      { key: 'kind', label: 'Kind', type: 'select', options: (v) => v.mutationKinds, def: 'motion', help: 'a weapon\'s path is one of each: element, volume, motion' },
      { key: 'element', label: 'Element', type: 'select', options: (v) => v.elements, def: '' },
      { key: 'hero', label: 'Hero', type: 'id_select', kind: 'hero', only: (d) => d.kind === 'hero' || !!d.hero, help: 'the hero whose own this is (kind hero)' },
    ]),
    T('Effect', [
      { key: 'text', label: 'Card text', type: 'textarea', required: true, help: 'shown verbatim on the card' },
      { key: 'vfx', label: 'Look', type: 'text', help: 'descriptive: what it looks like' },
      { key: 'effects', label: 'Effects', type: 'stat_effects', stats: 'weapon', target: 'self', help: 'on the weapon\'s sheet (target player reaches the hero)' },
      { key: 'params_typed', label: 'Typed params', type: 'params_fields', help: 'pass 69: the params its weapon\'s behaviour reads, typed; an empty box keeps the weapon\'s value (shown with where it comes from); a value here is merged deep over the weapon\'s' },
      { key: 'params', label: 'Params', type: 'params_json', help: 'merged deep over the weapon\'s params' },
    ]),
    T('Advanced', [
      { key: 'behavior', label: 'Swaps the behaviour', type: 'select', options: (v) => [opt('', 'no swap')].concat(v.behaviors), def: '', help: 'needle_rain -> Lobber, homing_skulls -> MissilePod' },
      { key: 'visual', label: 'Swaps the visual', type: 'text', help: 'a .tscn (methanol)' },
    ]),
    T('Availability', [
      { key: 'hidden', label: 'Hidden', type: 'bool', def: false, help: 'never offered on its own; a weapon needs three non-hidden path mutations to be available' },
    ]),
    T('Art', [
      { key: 'art_prompt', label: 'Icon subject', type: 'textarea' },
      { key: 'placeholder.color', label: 'Placeholder colour', type: 'swatch' },
      { key: 'placeholder.glyph', label: 'Placeholder glyph', type: 'text' },
      { key: 'icon', label: 'Icon', type: 'icon_preview' },
    ]),
  );

  // pass 69 (lane LE): a hero's perk (PerkDef: a card only its hero is offered, taken once; effects on his sheet, a
  // special the code runs, tuned by params). Edited from the Heroes tab ("His own" → Edit, + New perk).
  const perk = [].concat(
    T('Identity', [
      { key: 'id', label: 'Id', type: 'slug', required: true, help: 'the folder\'s name' },
      { key: 'name', label: 'Name', type: 'text', required: true, help: 'the card\'s title' },
      { key: 'flavour', label: 'Flavour', type: 'text', help: 'the card\'s line' },
      { key: 'hero', label: 'Hero', type: 'id_select', kind: 'hero', required: true, help: 'the only hero offered it (pass66_shape_test: every perk names a hero who is there)' },
      { key: 'rarity', label: 'Rarity', type: 'select', options: (v) => v.rarities, def: 'rare', help: 'the plate\'s colour and the card weight factor' },
      { key: 'weight', label: 'Weight', type: 'number', min: 0, def: 6, help: 'the card pool\'s weight among his cards' },
      { key: 'hidden', label: 'Hidden', type: 'bool', def: false, help: 'never offered (a hidden hero\'s perks count as hidden anyway)' },
    ]),
    T('Card', [
      { key: 'text', label: 'Card text', type: 'textarea', required: true, help: 'shown verbatim on the card: say what it does in a sentence or two (the numbers you set below)' },
      { key: 'effects', label: 'Effects', type: 'stat_effects', stats: 'player', target: 'player', help: 'stat changes on his sheet the moment he takes it (Afterglow: healing +40%); most perks have none and a special instead' },
    ]),
    T('Special', [
      { key: 'special', label: 'Special', type: 'select', options: (v) => perkSpecialOptions(v), def: '', help: 'the mechanism the game runs for it (a new one needs code: ask Claude). "any perk can carry it": a new perk works with it at once (decoy, periodic_buff); "that perk only": the game also checks the perk\'s id, so a copy under a new id keeps the numbers but needs code to fire' },
      { key: 'params_typed', label: 'Its numbers', type: 'perk_params', help: 'the special\'s numbers, one field each; an empty box takes the game\'s default shown in grey' },
      { key: 'params', label: 'Params (JSON)', type: 'json', help: 'the same numbers as JSON, and any key the fields above do not have (a buff list, a pickup id)' },
    ]),
    T('Art', [
      { key: 'art_prompt', label: 'Icon subject', type: 'textarea', help: 'what the icon painter draws (+ Icon candidates under the icon)' },
      { key: 'placeholder.color', label: 'Placeholder colour', type: 'swatch' },
      { key: 'placeholder.glyph', label: 'Placeholder glyph', type: 'text' },
      { key: 'icon', label: 'Icon', type: 'icon_preview' },
    ]),
  );

  const QUEST_ROWS = [
    { key: 'name', label: 'Name', type: 'text', help: 'the quest\'s title' },
    { key: 'condition.type', label: 'Condition', type: 'select', options: (v) => v.questTypes, def: 'kills_total', help: 'QuestTracker._satisfied; a new type needs code: ask Claude' },
    { key: 'condition.count', label: 'Count', type: 'int', min: 1, only: (q) => ['kills_with_weapon', 'kills_of_enemy', 'open_chests', 'evolve_any', 'kills_in_run_of_enemy', 'kills_total', 'runs_total', 'pickups_total', 'gold_total'].includes((q.condition || {}).type) },
    { key: 'condition.enemy', label: 'Creature', type: 'enemy', only: (q) => ['kills_of_enemy', 'kills_in_run_of_enemy'].includes((q.condition || {}).type) },
    { key: 'condition.weapon', label: 'Weapon', type: 'id_select', kind: 'weapon', only: (q) => (q.condition || {}).type === 'kills_with_weapon' },
    { key: 'condition.map', label: 'Map', type: 'text', only: (q) => ['extract_after_stage', 'kill_boss'].includes((q.condition || {}).type), help: 'red_canyon' },
    { key: 'condition.stage', label: 'Stage', type: 'int', min: 1, only: (q) => ['extract_after_stage', 'kill_boss', 'reach_stage'].includes((q.condition || {}).type) },
    { key: 'condition.level', label: 'Level', type: 'int', min: 1, only: (q) => (q.condition || {}).type === 'reach_level' },
    { key: 'condition.minutes', label: 'Minutes', type: 'number', min: 0, only: (q) => ['survive_minutes', 'survive_minutes_no_lift'].includes((q.condition || {}).type) },
    { key: 'quest_text', label: 'Quest text', type: 'textarea', help: 'optional: TextGen writes one when empty' },
  ];

  const SECTIONS = {
    enemy: ['Identity', 'Body', 'Brain & attacks', 'Attack script', 'Spawning', 'Drops', 'Variance', 'Special', 'Sounds', 'Looks', 'Art words'],
    hero: ['Identity', 'Trait', 'Favourites', 'Specials', 'Availability', 'His own', 'Art words', 'Looks & previews'],
    weapon: ['Identity', 'Behaviour', 'Base stats', 'Levels', 'Evolution & path', 'Params', 'Sounds', 'Availability', 'Art'],
    evolution: ['Identity', 'Behaviour', 'Base stats', 'Levels', 'Evolution & path', 'Params', 'Sounds', 'Availability', 'Art'],
    passive: ['Identity', 'Levels', 'Links', 'Text', 'Availability', 'Art'],
    mutation: ['Identity', 'Effect', 'Advanced', 'Availability', 'Art'],
    perk: ['Identity', 'Card', 'Special', 'Art'],   // pass 69
  };

  // ------------------------------------------------------------------ per-look recipe rows (the fallback when methods.json is absent)

  const R = (key, label, type, help, extra) => Object.assign({ key, label, type, help: help || '' }, extra || {});
  const recipeCommon = [R('screen', 'Screen', 'select', 'the keying colour', { options: (v) => v.screens, def: '' }), R('outline_frac', 'Outline', 'number', '', { min: 0, step: 0.001 }), R('outline_color', 'Outline colour', 'swatch'),
    R('remap_hues', 'Remap hues', 'json', '{ranges, to, sat, min_sat}'), R('anim_negative', 'Never in a clip', 'textarea'), R('anim_seed', 'Clip seed', 'int', '', { min: 0 })];
  const freeCommon = [R('art_prompt', 'Subject', 'textarea', 'this look\'s own subject (else the creature\'s)'), R('stills', 'Stills slug', 'text', 'paint from `RAW/<id>_<slug>_front.png` (a picked front from a picture)'),
    R('motion', 'Motion', 'textarea'), R('back_hint', 'Back view', 'textarea'), R('dead_hint', 'Dead still', 'textarea'), R('death', 'Death', 'select', '', { options: (v) => v.deaths, def: '' }), R('death_frames', 'Death frames', 'int', '', { min: 1, def: 8 }),
    R('run_fps', 'Run fps', 'int', '', { min: 1, def: 15 }), R('cell_fill', 'Cell fill', 'number', '', { min: 0.1, max: 1, step: 0.01, def: 0.86 }), R('clip_fill', 'Clip fill', 'number', '', { min: 0.1, max: 1, step: 0.01, def: 0.72 }), R('frame_px', 'Cell (px)', 'int', '', { min: 16 })];
  const RECIPES = {
    creature_free2: freeCommon.concat(recipeCommon),
    creature_pose2: freeCommon.concat([R('pose', 'Pose driver (back)', 'driver', 'a Mixamo stride'), R('pose_front', 'Pose driver (front)', 'driver'), R('gait', 'Gait', 'text'), R('stand', 'Stand', 'select', '', { options: (v) => v.stands, def: '' })], recipeCommon),
    creature_free8: freeCommon.concat([R('directions', 'Directions', 'select', '', { options: (v) => v.directions, def: 8 }), R('view_hints.side', 'Side view', 'textarea'), R('view_hints.bd', 'Back-diagonal view', 'textarea'), R('view_hints.fd', 'Front-diagonal view', 'textarea')], recipeCommon),
    creature_proc: [R('art_prompt', 'Subject', 'textarea'), R('stills', 'Stills slug', 'text'), R('walk', 'Walk', 'select', '"hop": no video', { options: (v) => v.walks, def: 'hop' }), R('hop_height', 'Hop height', 'number', '', { min: 0, step: 0.01, def: 0.13 }), R('death', 'Death', 'select', 'squash / collapse', { options: (v) => v.deaths, def: 'squash' }), R('dead_hint', 'Dead still', 'textarea'), R('cell_fill', 'Cell fill', 'number', '', { min: 0.1, max: 1, step: 0.01, def: 0.86 })].concat(recipeCommon),
    // pass 91: Garry's own front and back pictures as the stills, then everything creature_proc does
    creature_pictures: [R('front_ref', 'Front picture', 'text', 'a path under tools/dl (the job form uploads it)'), R('back_ref', 'Back picture', 'text', 'empty: painted from the front'), R('picture_use', 'Use the pictures', 'select', 'as_is: exactly as drawn; redraw: Klein redraws them', { options: () => [opt('as_is'), opt('redraw')], def: 'as_is' }), R('art_prompt', 'Subject', 'textarea'), R('stills', 'Stills slug', 'text'), R('walk', 'Walk', 'select', '"hop": no video', { options: (v) => v.walks, def: 'hop' }), R('hop_height', 'Hop height', 'number', '', { min: 0, step: 0.01, def: 0.13 }), R('death', 'Death', 'select', 'shatter: a pile of pieces', { options: (v) => v.deaths, def: 'shatter' }), R('dead_hint', 'Dead still', 'textarea', 'squash, collapse and the tilt only'), R('cell_fill', 'Cell fill', 'number', '', { min: 0.1, max: 1, step: 0.01, def: 0.86 })].concat(recipeCommon),
    creature_ctl: [R('drivers', 'Depth drivers', 'driver', 'tools/dl/drivers/<name>/<view>/ctl_NN.png + clay.png', { driverKind: 'depth' }), R('prompt', 'Painting', 'textarea', 'how this look is painted'), R('noun', 'Noun', 'text', '"a scorpion"'), R('blockout', 'The clay', 'textarea', 'what the 3D model shows'),
      R('detail', 'Detail', 'textarea'), R('anatomy', 'Anatomy', 'textarea'), R('keep', 'Keep', 'textarea', 'what every view keeps'), R('words.front', 'Front words', 'textarea'), R('words.fd', 'Front-diagonal words', 'textarea'), R('words.bd', 'Back-diagonal words', 'textarea'), R('words.back', 'Back words', 'textarea'),
      R('look_ref', 'Look reference', 'text', 'a picture of what it looks like (identity, loosely)'), R('motion', 'Motion', 'textarea'), R('death_drivers', 'Death drivers', 'driver', '', { driverKind: 'depth' }), R('death_motion', 'Death motion', 'textarea'), R('death_keep', 'Death frames kept', 'json', '[3, 5, 6, 7, 14, 16, 19, 24]'),
      R('dead', 'Dead still', 'textarea'), R('fps', 'Run fps', 'int', '', { min: 1, def: 20 }), R('directions', 'Directions', 'select', '', { options: (v) => v.directions, def: 8 }), R('side_seeds', 'Side candidates', 'int', '', { min: 1, def: 3 }), R('walk_seeds', 'Walk seeds', 'json', '{view: n}'),
      R('model_scale', 'Model scale', 'number', '', { min: 0.1, step: 0.05 }), R('no_green', 'No green', 'json', 'true: green held to red; "rb": to red or blue (a light blue look, pass 93); false: off'), R('fit_ref', 'Fit the painting', 'json', 'pass 93: true, 0..1 or [views]: the painting fitted onto the depth figure before the walk'),
      R('paint_mode', 'Paint mode', 'select', 'pass 94: repaint = the clay repainted, as close to the model as it gets', { options: () => [opt('redraw'), opt('repaint')], def: 'redraw' }), R('anchor', 'Style anchor', 'bool', 'repaint: the style anchor last, the house style kept'), R('style', 'Style line', 'textarea', 'repaint: empty = the house style'),
      R('clay_src', 'Clay render', 'select', 'repaint: clay.png or look.png', { options: () => [opt('clay'), opt('look')], def: 'clay' }), R('clay_fill', 'Clay fill', 'number', 'repaint: crop the clay so the figure fills this share (0.8)', { min: 0, max: 1, step: 0.05 }),
      R('init', 'Start from the clay', 'json', '{denoise 0.85, tint, gain, blur}: img2img from the tinted clay'), R('refine', 'Refine rounds', 'json', '{rounds, denoise, steps}'), R('wan', 'Wan settings', 'json', '{steps 4, cfg 1, lora true}: {lora false, steps 20, cfg 3.5} = the full model'),
      R('view_words', 'Words per view', 'json', 'pass 99: {view: words} added to the painting of that one view only'), R('clay_drivers', 'Painted on driver', 'json', 'pass 99: a name or {view: name}: the clay a view was painted from (empty: the drivers)'), R('view_drivers', 'Walk driver per view', 'json', 'pass 99: {view: name}: that view walks on another driver')].concat(recipeCommon),
    hero_pose5: [R('pose_drivers.front', 'Driver: front', 'driver'), R('pose_drivers.back', 'Driver: back', 'driver'), R('pose_drivers.side', 'Driver: side', 'driver'), R('pose_drivers.fd', 'Driver: front-diagonal', 'driver'), R('pose_drivers.bd', 'Driver: back-diagonal', 'driver'),
      R('still_keys', 'Still keys', 'json', '{view: cache key}'), R('anim_hint', 'Clip subject', 'textarea'), R('pose_motion', 'Pose motion', 'textarea'), R('back_hint', 'Back view', 'textarea'), R('run_fps', 'Run fps', 'int', '', { min: 1, def: 36 })].concat(recipeCommon),
    hero_fit: [R('pose_drivers.front', 'Driver: front', 'driver'), R('pose_drivers.back', 'Driver: back', 'driver'), R('pose_drivers.side', 'Driver: side', 'driver'), R('pose_drivers.fd', 'Driver: front-diagonal', 'driver'), R('pose_drivers.bd', 'Driver: back-diagonal', 'driver'),
      R('still_keys', 'Still keys', 'json', '{view: cache key}'), R('anim_hint', 'Clip subject', 'textarea'), R('pose_motion', 'Pose motion', 'textarea'), R('anim_negative', 'Never in a clip', 'textarea'), R('anim_seed', 'Clip seed', 'int', '', { min: 0 })],
    front_from_picture: [R('stills', 'Stills slug', 'text', 'the candidates\' name'), R('ref', 'Picture', 'text', 'the uploaded picture'), R('prompt', 'Words', 'textarea'), R('keep', 'Keep', 'textarea'), R('screen', 'Screen', 'select', '', { options: (v) => v.screens, def: '' }), R('no_style_ref', 'Picture only (no style anchor)', 'bool')],
    recolour: [R('src', 'From look', 'text', 'the code copied'), R('ranges', 'Hue ranges', 'text', '"55-135"'), R('to', 'To hue', 'number', '', { min: 0, max: 360 }), R('sat', 'Saturation', 'number', '', { min: 0, max: 2, step: 0.05 })],
  };

  // the proven reference wordings (the synthesis §5.2); `methods.json.ref_wordings` replaces them when lane B's file is there
  const WORDINGS = [
    { role: 'style', level: 'fixed', text: 'Using exactly the same art style, rendering, shading, palette and outline treatment as the reference image, draw a new subject: <subject>. <view>. <STYLE>. <bg>. Do not copy any subject from the reference.', source: 'gen_art.styled() 141-145', refs: 'the anchor first' },
    { role: 'style', level: 'with other refs', text: 'The first reference image shows the art style only; do not copy its subjects.', source: 'gen_ctl.py:157, gen_edit_stills.py:77' },
    { role: 'identity', level: 'loosely', text: 'The <n>th reference image shows what this creature looks like: copy its armour, colours and markings, but not its pose or camera angle.', source: 'gen_ctl.py:155-156', refs: '[anchor, clay, look]' },
    { role: 'identity', level: 'closely', text: 'The <n>th reference image is the creature: redraw this exact creature as a finished 2D anime game creature illustration of <prompt>. Full body, front view, standing and facing the viewer, feet fully visible, the whole creature inside the picture. Keep <keep>. <STYLE>. <bg>.', source: 'gen_edit_stills.py:78-80', refs: '[anchor, picture]' },
    { role: 'identity', level: 'copy exactly', text: 'Copy this exact object from the reference image: its silhouette, proportions, parts and colours, seen from the same angle. <subject>', source: 'gen_icon_cands.COPY (36)', refs: '[ref] (icons)' },
    { role: 'identity', level: 'copy exactly (figure)', text: 'Keep the same face, outfit, colors and proportions as the reference.', source: 'gen_title_heroes.py:111' },
    { role: 'pose-and-anatomy', level: 'closely (side)', text: 'The second reference image is a smooth plain 3D model of <noun> (<blockout>): use it only for the anatomy, the pose, the camera angle and where every leg and every other part is. Redraw it as a finished, detailed anime game creature illustration of <prompt>, with <detail>, in side profile facing right, <anatomy>. It must not look like a plain 3D model.', source: 'gen_ctl.py:157-161', refs: '[anchor, clay_side, look?]' },
    { role: 'pose-and-anatomy', level: 'closely (views)', text: 'The first reference image is a finished painting of <noun> character in side view. The second reference image is a smooth plain 3D model of the same creature, <words[view]>. Redraw the 3D model as the same creature as the first image, the same colours, armour, markings and art style, in exactly the pose and camera angle of the 3D model, with <anatomy> and the same number of legs and claws as the 3D model. It keeps <keep>, seen from this angle. It must not look like a plain 3D model.', source: 'gen_ctl.py:192-196', refs: '[side_painting, clay_view]' },
    { role: 'same figure, another view', level: 'fixed', text: 'Turn this exact creature around and show a full-body back view seen directly from behind, no face visible. Keep the same colors, proportions and art style, standing. <back_hint> <bg>.', source: 'gen_art.py:747-748', refs: '[front_ref] (the painting, never the picture)' },
    { role: 'held object (title)', level: 'copy exactly', text: 'The second reference image shows the <object>: copy its shape and colours exactly: <description>. ... the <object> is the only thing he holds', source: 'gen_title_heroes.EXTRA_REFS 56-60, HOLDS' },
  ];

  // ------------------------------------------------------------------ rules (errors block Save; warnings never do)

  const E = (key, when, msg) => ({ key, level: 'error', when, msg });
  const W = (key, when, msg) => ({ key, level: 'warn', when, msg });
  const str = (v) => String(v == null ? '' : v).trim();
  const vocabOf = (ctx) => (ctx && ctx.vocab) || VOCAB;
  const vals = (list) => (list || []).map((o) => (isObj(o) ? o.v : o));
  const items = (ctx) => (ctx && ctx.lists && ctx.lists.items) || null;
  const flat = (ctx, what) => { const it = items(ctx); return it && Array.isArray(it[what]) ? it[what] : null; };
  const findIn = (list, id) => (list || []).find((x) => x && String(x.id) === String(id)) || null;
  const heroes = (ctx) => (ctx && ctx.lists && Array.isArray(ctx.lists.heroes) ? ctx.lists.heroes : null);
  const enemies = (ctx) => (ctx && ctx.lists && Array.isArray(ctx.lists.enemies) ? ctx.lists.enemies : null);
  const soundsKnown = (ctx) => { const v = vocabOf(ctx); return Array.isArray(v.sounds) ? v.sounds : null; };
  const isInt = (v) => typeof v === 'number' && isFinite(v) && Math.floor(v) === v;
  function hexToHsv(hex) {
    const m = String(hex || '').match(/^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i);
    if (!m) return null;
    const r = parseInt(m[1], 16) / 255, g = parseInt(m[2], 16) / 255, b = parseInt(m[3], 16) / 255;
    const mx = Math.max(r, g, b), mn = Math.min(r, g, b);
    return { s: mx > 0 ? (mx - mn) / mx : 0, v: mx };
  }
  const badEffects = (list, which, vocab) => {
    const out = [];
    for (const e of Array.isArray(list) ? list : []) {
      if (!isObj(e) || !e.stat) { out.push('an effect without a stat'); continue; }
      if (!statKnown(String(e.stat), statSetFor(e, which), vocab)) out.push(`unknown stat "${e.stat}"${e.target ? ` for target ${e.target}` : ''}`);
      if (e.op != null && !['add', 'mul', 'set'].includes(String(e.op))) out.push(`unknown op "${e.op}" on ${e.stat} (add / mul / set)`);
      if (e.value == null || !isFinite(Number(e.value))) out.push(`${e.stat} has no number`);
    }
    return out;
  };
  const badLevels = (levels, which, vocab) => {
    const out = [];
    (Array.isArray(levels) ? levels : []).forEach((lv, i) => {
      if (!Array.isArray(lv)) { out.push(`level ${i + 1} is not a list`); return; }
      for (const m of badEffects(lv, which, vocab)) out.push(`level ${i + 1}: ${m}`);
    });
    return out;
  };
  const unknownParams = (params, behavior) => Object.keys(isObj(params) ? params : {}).filter((k2) => !paramsKnown(k2, behavior));
  const attackList = (d) => (isObj(d.boss) && Array.isArray(d.boss.attacks) ? d.boss.attacks : []);
  const unknownSfx = (d, ctx) => { const known = soundsKnown(ctx); if (!known || !isObj(d.sfx)) return []; return Object.keys(d.sfx).filter((h) => str(d.sfx[h]) && !known.includes(str(d.sfx[h]))).map((h) => `${h}: "${d.sfx[h]}"`); };
  const bandWarn = (ctx) => {
    const ws = flat(ctx, 'weapons'), ps = flat(ctx, 'passives'), qs = flat(ctx, 'quests');
    if (!ws || !ps || !qs) return null;
    const b = M.bandOf(ws, ps, qs);
    return b.base && (b.share < b.lo || b.share > b.hi) ? b : null;
  };
  const common = (kind) => [
    E('id', (d, c) => d.id != null && (!M.slugOk(d.id) || (c && c.id && String(d.id) !== String(c.id))), (d, c) => `id "${d.id}" must be the folder's name${c && c.id ? ` (${c.id})` : ''} in [a-z0-9_]`),
    E('name', (d) => !str(d.name), 'name is empty'),
  ];
  const rarityRules = [
    E('rarity', (d, c) => d.rarity != null && !vals(vocabOf(c).rarities).includes(str(d.rarity)), (d) => `unknown rarity "${d.rarity}"`),
    E('weight', (d) => d.weight != null && !(isFinite(Number(d.weight)) && Number(d.weight) >= 0), 'weight must be a number of 0 or more'),
    W('rarity', (d) => str(d.rarity) === 'legendary', 'legendary: no item uses it; the card pool weighs it 0.15 and pass47_ui pins four rarities among passive items'),
  ];

  const RULES = {
    enemy: [].concat(common('enemy'), [
      E('doc', (d) => !str(d.doc), 'doc is empty: the Collection page would be blank (pass25_test wants it non-empty)'),
      E('blood', (d) => d.blood != null && !M.HEX_RE.test(String(d.blood)), (d) => `blood "${d.blood}" is not #RRGGBB (pass58_fx_test)`),
      E('knockback', (d, c) => !String((c && c.id) || d.id || '').startsWith('training_dummy') && !(M.isNum(d.knockback) && d.knockback > 0), (d) => `knockback must be a number above 0 (pass54_waves_test; the game's own would be ${M.plain(M.defaultKnockback(num(d.damage, 5)))})`),
      E('knockback_resist', (d) => d.knockback_resist != null && !(M.isNum(d.knockback_resist) && d.knockback_resist >= 0 && d.knockback_resist <= 1), 'knockback resist must be 0..1 (the share of the hero\'s shoves it shrugs off; 1 = never moved; the game clamps it)'),
      E('hp', (d) => d.hp != null && !(M.isNum(d.hp) && d.hp > 0), 'hp must be a number above 0'),
      E('damage', (d) => d.damage != null && !(M.isNum(d.damage) && d.damage >= 0), 'bite must be a number of 0 or more'),
      E('size', (d) => d.size != null && !(M.isNum(d.size) && d.size > 0), 'size is one number in metres above 0 (a [min, max] range belongs to a roster row: a list here fails to load)'),
      E('radius', (d) => d.radius != null && !(M.isNum(d.radius) && d.radius > 0), 'radius must be a number above 0'),
      E('speed', (d) => d.speed != null && !(M.isNum(d.speed) && d.speed >= 0), 'speed must be a number of 0 or more'),
      E('brain', (d, c) => d.brain != null && !vals(vocabOf(c).brains).includes(str(d.brain)), (d) => `unknown brain "${d.brain}": the game would chase. A new brain needs code: ask Claude`),
      E('archetype', (d, c) => d.archetype != null && !vals(vocabOf(c).archetypes).includes(str(d.archetype)), (d) => `unknown archetype "${d.archetype}"`),
      E('variance.tint_strength', (d) => isObj(d.variance) && d.variance.tint_strength != null && Number(d.variance.tint_strength) > 0.3, 'variance.tint_strength above 0.3 (pass27_test pins ≤ 0.3)'),
      // pass 69 (lane EN): any colour may be picked (Garry wants control of it); only a non-colour is an error, a light or
      // grey one a warning (pass27_test now wants a valid colour only)
      E('variance.special.tint', (d) => { const sp = isObj(d.variance) && isObj(d.variance.special) ? d.variance.special : null; if (!sp || sp.tint == null || sp.tint === '') return false; return !hexToHsv(sp.tint); }, 'the special\'s colour must be #RRGGBB'),
      W('variance.special.tint', (d) => { const sp = isObj(d.variance) && isObj(d.variance.special) ? d.variance.special : null; if (!sp || sp.tint == null || sp.tint === '') return false; const h = hexToHsv(sp.tint); return !!h && (h.v >= 0.6 || h.s <= 0.4); }, 'a light or grey colour washes the special pale: a dark, saturated one (brightness under 60 %, saturation over 40 %) reads best; the glow shows its hue either way'),
      E('variance.special.glow', (d) => { const sp = isObj(d.variance) && isObj(d.variance.special) ? d.variance.special : null; return !!sp && sp.glow != null && !(M.isNum(sp.glow) && sp.glow >= 0 && sp.glow <= 1); }, 'the glow is 0..1 (0 = none)'),
      E('variance.special.chest_chance', (d) => { const sp = isObj(d.variance) && isObj(d.variance.special) ? d.variance.special : null; return !!sp && sp.chest_chance != null && sp.chest_chance !== '' && !(M.isNum(sp.chest_chance) && sp.chest_chance >= 0 && sp.chest_chance <= 1); }, 'the chest chance is 0..1'),
      E('variance.special_chance', (d) => isObj(d.variance) && d.variance.special_chance != null && !(M.isNum(d.variance.special_chance) && d.variance.special_chance >= 0 && d.variance.special_chance <= 1), 'the special chance is 0..1'),
      E('anims', (d) => isObj(d.anims) && Object.keys(d.anims).some((a) => !isInt(d.anims[a]) || d.anims[a] < 0), 'anims counts must be whole numbers of 0 or more'),
      E('strip_cols', (d) => d.strip_cols != null && (!isInt(d.strip_cols) || d.strip_cols < 0), 'strip_cols is a whole number (0 = one row)'),
      E('badge', (d) => str(d.badge) === 'crown' && str(d.archetype) !== 'elite', 'the crown shows only on the elite archetype (pass333_test pins the crown wearers to the elites)'),
      E('badge', (d, c) => d.badge != null && !vals(vocabOf(c).badges).includes(str(d.badge)), (d) => `unknown badge "${d.badge}"`),
      E('front_faces', (d, c) => d.front_faces != null && !vals(vocabOf(c).faces).includes(str(d.front_faces)), (d) => `unknown front_faces "${d.front_faces}"`),
      E('back_faces', (d, c) => d.back_faces != null && !vals(vocabOf(c).faces).includes(str(d.back_faces)), (d) => `unknown back_faces "${d.back_faces}"`),
      E('boss.attacks', (d) => attackList(d).some((a) => !isObj(a) || !str(a.name)), 'every attack of the script is an object with a name'),
      E('boss.attacks', (d) => isObj(d.boss) && d.boss.attacks != null && !Array.isArray(d.boss.attacks), 'boss.attacks must be a list'),
      E('pack_size', (d) => d.pack_size != null && !(isInt(d.pack_size) && d.pack_size >= 1), 'pack_size is a whole number of 1 or more'),
      E('badJson', (d, c) => c && c.badJson && Object.keys(c.badJson).length > 0, (d, c) => `a JSON box does not parse: ${Object.keys(c.badJson).join(', ')}`),
      W('damage_reduction', (d) => d.damage_reduction != null && (Number(d.damage_reduction) < 0 || Number(d.damage_reduction) > 0.9), 'damage_reduction is clamped to 0..0.9 in play'),
      W('contact_cd', (d) => d.contact_cd != null && Number(d.contact_cd) < 0.05, 'contact_cd is at least 0.05 in play'),
      W('brain', (d, c) => { const seen = c && c.seenCombos; if (!seen) return false; const list = seen instanceof Set ? seen : new Set(seen); return !list.has(M.combo(d)); }, (d) => `No creature in play uses ${M.comboWords(d)}: untested in play`),
      W('sfx', (d, c) => unknownSfx(d, c).length > 0, (d, c) => `unknown sound id, silent in the game: ${unknownSfx(d, c).join(', ')}`),
      W('boss.attacks', (d) => attackList(d).some((a) => isObj(a) && str(a.name) && !ATTACKS[str(a.name)] && !isCustomAttack(str(a.name))), (d) => `unknown attack name: ${attackList(d).filter((a) => isObj(a) && str(a.name) && !ATTACKS[str(a.name)] && !isCustomAttack(str(a.name))).map((a) => `"${a.name}"`).join(', ')} (the game does nothing for it; a custom attack is made on the Boss attacks tab)`),
      // (pass 73: a burrow that predicts its spot picks it itself, with no ring at the hero)
      W('boss.attacks', (d) => attackList(d).some((a) => isObj(a) && ATTACKS[str(a.name)] && ATTACKS[str(a.name)].needsRingAtHero && attackTelegraph(a) !== 'ring_at_hero' && !(str(a.name) === 'burrow' && Number(a.predict) > 0)), (d) => `${attackList(d).filter((a) => isObj(a) && ATTACKS[str(a.name)] && ATTACKS[str(a.name)].needsRingAtHero && attackTelegraph(a) !== 'ring_at_hero' && !(str(a.name) === 'burrow' && Number(a.predict) > 0)).map((a) => a.name).join(', ')}: lands where the "ring at the hero" telegraph was set; with another telegraph it has no target (a burrow with Predict picks its own spot)`),
      W('boss.attacks', (d, c) => { const en = enemies(c); if (!en) return false; return attackList(d).some((a) => isObj(a) && ((str(a.name) === 'spawn_ring' && !findIn(en, str(a.enemy) || 'coyote')) || (str(a.name) === 'erupt' && str(a.spawn) && !findIn(en, a.spawn)))); }, 'spawn_ring / erupt names a creature that does not exist (the game\'s default "coyote" is gone): it spawns nothing'),
      W('boss.attacks', (d) => attackList(d).some((a) => isObj(a) && a.telegraph != null && !['line', 'ring', 'ring_at_hero', 'sector', 'fan', 'spokes', 'none'].includes(str(a.telegraph))), 'an attack names an unknown telegraph (line, ring, ring_at_hero, sector, fan, spokes, none)'),
      W('shadow.up', (d) => isObj(d.shadow) && M.isNum(d.shadow.up) && M.isNum(d.size) && d.shadow.up > d.size, 'shadow.up is higher than the creature (size)'),
      // pass 70 (the Bandit check): a look's Stills is a slug, never the picture (that goes in Reference)
      E('looks', (d) => M.badStills(d).length > 0, (d) => M.badStills(d).map(([w, m]) => `${w.replace(/^variants\.([^.]+)\.recipe\./, '$1 ')}: ${m}`).join(' · ')),
      W('looks', (d, c) => Array.isArray(c && c.looks) && c.looks.some((l) => l && l.fresh), (d, c) => `unreviewed look${c.looks.filter((l) => l.fresh).length > 1 ? 's' : ''}: ${c.looks.filter((l) => l.fresh).map((l) => l.code).join(', ')} (Approve in the Looks section)`),
      W('looks', (d, c) => Array.isArray(c && c.looks) && c.looks.some((l) => l && l.ready && l.imported === false), (d, c) => `not imported yet (the game plays the old .tres): ${c.looks.filter((l) => l.ready && l.imported === false).map((l) => l.code).join(', ')}`),
      W('hidden', (d) => !!d.retired && !!d.hidden, 'both retired and hidden: retired already counts as hidden'),
    ]),
    hero: [].concat(common('hero'), [
      E('pronoun', (d, c) => d.pronoun != null && !vals(vocabOf(c).pronouns).includes(str(d.pronoun)), (d) => `pronoun "${d.pronoun}" is not he / she / they`),
      E('order', (d) => d.order != null && !isInt(d.order), 'order is a whole number'),
      E('availability', (d, c) => d.availability != null && !vals(vocabOf(c).availability).includes(str(d.availability)), (d) => `unknown availability "${d.availability}" (hidden / available / purchase)`),
      E('price', (d) => d.price != null && !(isInt(d.price) && d.price >= 0), 'price is a whole number of 0 or more'),
      E('currency_type', (d, c) => d.currency_type != null && !vals(vocabOf(c).currencies).includes(str(d.currency_type)), (d) => `unknown currency "${d.currency_type}" (gold)`),
      E('trait_per_level', (d, c) => badEffects(d.trait_per_level, 'player', vocabOf(c)).length > 0, (d, c) => `trait_per_level: ${badEffects(d.trait_per_level, 'player', vocabOf(c)).join('; ')}`),
      E('trait', (d, c) => badEffects(d.trait, 'player', vocabOf(c)).length > 0, (d, c) => `trait: ${badEffects(d.trait, 'player', vocabOf(c)).join('; ')}`),
      E('favourite_bonus.effects', (d, c) => isObj(d.favourite_bonus) && badEffects(d.favourite_bonus.effects, 'any', vocabOf(c)).length > 0, (d, c) => `favourite_bonus.effects: ${badEffects(d.favourite_bonus.effects, 'any', vocabOf(c)).join('; ')}`),
      E('favourite_bonus.type', (d) => isObj(d.favourite_bonus) && d.favourite_bonus.type != null && !['level', 'effects'].includes(str(d.favourite_bonus.type)), 'favourite_bonus.type is level or effects (weapons have no "max")'),
      E('favourite_passive_bonus.type', (d) => isObj(d.favourite_passive_bonus) && d.favourite_passive_bonus.type != null && !['max', 'level', 'effects'].includes(str(d.favourite_passive_bonus.type)), 'favourite_passive_bonus.type is max, level or effects'),
      E('favourite_weapon', (d, c) => !d.hidden && str(d.favourite_weapon) && flat(c, 'weapons') && !findIn(flat(c, 'weapons'), d.favourite_weapon), (d) => `favourite_weapon "${d.favourite_weapon}" is not a weapon (Registry.problems)`),
      E('start_weapon', (d, c) => !d.hidden && str(d.start_weapon) && flat(c, 'weapons') && !findIn(flat(c, 'weapons'), d.start_weapon), (d) => `start_weapon "${d.start_weapon}" is not a weapon (Registry.problems)`),
      E('favourite_passive', (d, c) => !d.hidden && str(d.favourite_passive) && flat(c, 'passives') && !findIn(flat(c, 'passives'), d.favourite_passive), (d) => `favourite_passive "${d.favourite_passive}" is not a passive (Registry.problems)`),
      E('specials', (d, c) => Array.isArray(d.specials) && d.specials.some((s) => !vals(vocabOf(c).specials).includes(str(s))), (d, c) => `unknown special: ${d.specials.filter((s) => !vals(vocabOf(c).specials).includes(str(s))).join(', ')} (a new mechanism needs code: ask Claude)`),
      E('badJson', (d, c) => c && c.badJson && Object.keys(c.badJson).length > 0, (d, c) => `a JSON box does not parse: ${Object.keys(c.badJson).join(', ')}`),
      E('looks', (d) => M.badStills(d).length > 0, (d) => M.badStills(d).map(([w, m]) => `${w.replace(/^variants\.([^.]+)\.recipe\./, '$1 ')}: ${m}`).join(' · ')),
      W('trait_text', (d) => Array.isArray(d.trait_per_level) && d.trait_per_level.length > 0 && !M.heroOwnWords(d) && str(d.trait_text) !== M.heroTrait(d), (d) => `trait_text differs from the rule's sentence "${M.heroTrait(d)}" (pass61_hr pins them equal for played heroes: Set from the rule)`),
      W('favourite_weapon', (d, c) => !!d.hidden && str(d.favourite_weapon) && flat(c, 'weapons') && !findIn(flat(c, 'weapons'), d.favourite_weapon), (d) => `favourite_weapon "${d.favourite_weapon}" is not a weapon (fine while hidden)`),
      // pass 69 (lane UI's rule, JsonContent.build): only availability "hidden" hides; a purchase hero is on the title
      // whatever `hidden` says; an available one with hidden: true stays hidden. The page keeps them in step.
      W('hidden', (d) => d.availability != null && !!d.hidden !== (d.availability === 'hidden'), (d) => `hidden (${!!d.hidden}) and availability (${d.availability}) disagree: ${d.availability === 'purchase' ? 'a hero to buy is on the title whatever hidden says' : d.availability === 'available' ? 'the game hides an available hero whose hidden is true' : 'availability hidden hides him'}; set Availability again to put them in step`),
      // pass 69: pass66_shape_test wants every hero on the title (free or to buy) whole: a perk and exactly one hero mutation
      W('availability', (d, c) => d.availability != null && d.availability !== 'hidden' && c && c.record && Array.isArray(c.record.perks) && c.record.perks.length === 0, 'a hero on the title needs at least one perk (pass66_shape_test): add one under His own'),
      W('availability', (d, c) => d.availability != null && d.availability !== 'hidden' && liveHeroMutations(d, c) != null && liveHeroMutations(d, c).length !== 1, (d, c) => `a hero on the title needs exactly one hero mutation in play, on his favourite weapon (pass66_shape_test); he has ${liveHeroMutations(d, c).length}${liveHeroMutations(d, c).length ? ': ' + liveHeroMutations(d, c).join(', ') : ''}`),
      W('price', (d) => d.availability === 'purchase' && !(Number(d.price) > 0), 'a hero to buy at price 0 is free once his requirement is done (the BUY button still shows)'),
      W('order', (d, c) => { const hs = heroes(c); if (!hs || d.order == null) return false; return hs.some((h) => String(h.id) !== String((c && c.id) || d.id) && !h.hidden && h.order === d.order); }, (d) => `order ${d.order} is another playable hero's too`),
      W('perks', (d, c) => !!d.hidden && str(d.favourite_weapon) && c && c.record && Array.isArray(c.record.perks) && c.record.perks.length === 0, 'a hidden hero with a favourite weapon and no perk: pass26_test looped over hidden heroes too (lane G removes that loop); harmless once re-pinned'),
      W('unlock_quest', (d) => str(d.unlock_quest), 'unlock_quest is a dead key: a hero is gated by a quest whose unlocks names him'),
    ]),
    weapon: [].concat(common('weapon'), rarityRules, [
      E('behavior', (d, c) => d.behavior != null && !vals(vocabOf(c).behaviors).includes(str(d.behavior)), (d) => `unknown behaviour "${d.behavior}" (a new one needs code: ask Claude)`),
      W('targeting', (d, c) => d.targeting != null && !vals(vocabOf(c).targeting).includes(str(d.targeting)), (d) => `unknown targeting "${d.targeting}": only priority, forward, random and healthy change the aim, the rest describe (TextGen)`),
      E('levels', (d) => d.levels != null && !Array.isArray(d.levels), 'levels must be a list of lists'),
      E('levels', (d) => !d.is_evolution && Array.isArray(d.levels) && !(d.levels.length === 5 && Array.isArray(d.levels[0]) && d.levels[0].length === 0), (d) => `a base weapon has exactly 5 level lists with level 1 empty (pass48_p0_test:219); this one has ${Array.isArray(d.levels) ? d.levels.length : 0}${Array.isArray(d.levels) && d.levels[0] && d.levels[0].length ? ' and level 1 is not empty' : ''}`),
      E('levels', (d, c) => badLevels(d.levels, 'weapon', vocabOf(c)).length > 0, (d, c) => badLevels(d.levels, 'weapon', vocabOf(c)).join('; ')),
      E('max_level', (d) => !d.is_evolution && d.max_level != null && d.max_level !== 5, 'a base weapon\'s max_level is 5 (pass48_p0_test:216)'),
      E('evolves_with', (d) => str(d.evolves_with), 'evolves_with must stay empty: weapons evolve through their path (pass26_test)'),
      E('evolves_into', (d, c) => !d.is_evolution && !d.hidden && flat(c, 'evolutions') && !findIn(flat(c, 'evolutions'), d.evolves_into), (d) => str(d.evolves_into) ? `evolves_into "${d.evolves_into}" is not an evolution (Registry.problems)` : 'no evolution: Create templates in Evolution & path, or keep the weapon hidden'),
      E('path', (d, c) => { if (d.is_evolution || d.hidden) return false; const ms = flat(c, 'mutations'); if (!ms) return false; const p = M.pathOf((c && c.id) || d.id, ms); return !(p.element && p.volume && p.motion); }, (d, c) => { const p = M.pathOf((c && c.id) || d.id, flat(c, 'mutations')); const miss = ['element', 'volume', 'motion'].filter((kk) => !p[kk]); return `an available weapon needs a non-hidden path mutation of each kind (pass48_p0_test:273-278); missing: ${miss.join(', ')}${p.hidden.length ? ` (hidden: ${p.hidden.map((m) => m.id).join(', ')})` : ''}`; }),
      E('hero', (d, c) => str(d.hero) && heroes(c) && !findIn(heroes(c), d.hero), (d) => `hero "${d.hero}" is not a hero`),
      E('badJson', (d, c) => c && c.badJson && Object.keys(c.badJson).length > 0, (d, c) => `a JSON box does not parse: ${Object.keys(c.badJson).join(', ')}`),
      W('params', (d) => unknownParams(d.params, str(d.behavior) || 'ProjectileEmitter').length > 0, (d) => `params keys no behaviour script reads: ${unknownParams(d.params, str(d.behavior) || 'ProjectileEmitter').join(', ')}`),
      W('sfx', (d, c) => unknownSfx(d, c).length > 0, (d, c) => `unknown sound id, silent in the game: ${unknownSfx(d, c).join(', ')}`),
      W('evolves_into', (d, c) => !d.is_evolution && !d.hidden && flat(c, 'evolutions') && findIn(flat(c, 'evolutions'), d.evolves_into) && !!findIn(flat(c, 'evolutions'), d.evolves_into).hidden, (d) => `its evolution "${d.evolves_into}" is hidden while the weapon is available: it can never evolve`),
      W('band', (d, c) => !d.is_evolution && !!bandWarn(c), (d, c) => { const b = bandWarn(c); return `quest-locked base items ${b.locked} of ${b.base} = ${Math.round(b.share * 100)}%: the ship test wants ${Math.round(b.lo * 100)}-${Math.round(b.hi * 100)}% (pass44_test); add a quest lock or ask Claude to widen the band`; }),
      W('from_stage', (d) => d.from_stage != null && Number(d.from_stage) > 3, 'from_stage beyond stage 3: only offered in endless'),
    ]),
    evolution: [].concat(common('evolution'), rarityRules, [
      E('behavior', (d, c) => d.behavior != null && !vals(vocabOf(c).behaviors).includes(str(d.behavior)), (d) => `unknown behaviour "${d.behavior}"`),
      W('targeting', (d, c) => d.targeting != null && !vals(vocabOf(c).targeting).includes(str(d.targeting)), (d) => `unknown targeting "${d.targeting}": only priority, forward, random and healthy change the aim, the rest describe (TextGen)`),
      E('evolved_from', (d, c) => { const ws = flat(c, 'weapons'); if (!ws) return false; return !findIn(ws, d.evolved_from); }, (d) => str(d.evolved_from) ? `evolved_from "${d.evolved_from}" is not a weapon` : 'evolved_from names no weapon'),
      W('evolved_from', (d, c) => { const ws = flat(c, 'weapons'); if (!ws) return false; const w = findIn(ws, d.evolved_from); return !!w && String(w.evolves_into) !== String((c && c.id) || d.id); }, (d, c) => `${d.evolved_from} evolves into "${findIn(flat(c, 'weapons'), d.evolved_from).evolves_into}", not this: unreachable in play (an alternate kept on disk)`),
      E('levels', (d, c) => badLevels(d.levels, 'weapon', vocabOf(c)).length > 0, (d, c) => badLevels(d.levels, 'weapon', vocabOf(c)).join('; ')),
      E('badJson', (d, c) => c && c.badJson && Object.keys(c.badJson).length > 0, (d, c) => `a JSON box does not parse: ${Object.keys(c.badJson).join(', ')}`),
      W('max_level', (d) => d.max_level != null && d.max_level !== 1, 'an evolution has max_level 1: it cannot level further'),
      // pass 69 (lane LE): an evolution's one level may carry effects (WeaponDef.effects_up_to applies levels[0] at level 1:
      // Slam Dunk's burn × 1.5 for On Fire lives there); only more than one level is a mistake
      W('levels', (d) => Array.isArray(d.levels) && !(d.levels.length === 1 && Array.isArray(d.levels[0])), 'an evolution has exactly one level, levels[0] (applied at once: Slam Dunk\'s burn × 1.5 lives there); its other numbers live in base and params.final'),
      W('params', (d) => unknownParams(d.params, str(d.behavior) || 'ProjectileEmitter').length > 0, (d) => `params keys no behaviour script reads: ${unknownParams(d.params, str(d.behavior) || 'ProjectileEmitter').join(', ')}`),
      W('sfx', (d, c) => unknownSfx(d, c).length > 0, (d, c) => `unknown sound id, silent in the game: ${unknownSfx(d, c).join(', ')}`),
    ]),
    passive: [].concat(common('passive'), rarityRules, [
      E('max_level', (d) => d.max_level != null && !(isInt(d.max_level) && d.max_level >= 1), 'max_level is a whole number of 1 or more'),
      E('levels', (d) => !Array.isArray(d.levels) || d.levels.length === 0, 'levels is a non-empty list of lists'),
      E('levels', (d, c) => badLevels(d.levels, 'player', vocabOf(c)).length > 0, (d, c) => badLevels(d.levels, 'player', vocabOf(c)).join('; ')),
      E('evolves_into', (d, c) => str(d.evolves_into) && flat(c, 'passives') && !findIn(flat(c, 'passives'), d.evolves_into), (d) => `evolves_into "${d.evolves_into}" is not a passive`),
      E('evolves_into', (d, c) => { const t = str(d.evolves_into) && findIn(flat(c, 'passives'), d.evolves_into); return !!t && (String(t.evolves_from) !== String((c && c.id) || d.id) || !!t.line !== !!d.line); }, (d) => `"${d.evolves_into}" must name this as its evolves_from and agree on line (Registry.problems)`),
      E('evolves_from', (d, c) => { const t = str(d.evolves_from) && flat(c, 'passives') && findIn(flat(c, 'passives'), d.evolves_from); return str(d.evolves_from) && flat(c, 'passives') && (!t || String(t.evolves_into) !== String((c && c.id) || d.id)); }, (d) => `evolves_from "${d.evolves_from}" is not a passive whose evolves_into is this`),
      E('element', (d, c) => d.element != null && !vals(vocabOf(c).elements).includes(str(d.element)), (d) => `unknown element "${d.element}"`),
      W('weight', (d) => str(d.evolves_from) && Number(d.weight) > 0, 'an evolved card usually weighs 0: it comes from its base card, never on its own'),
      // pass 95 (lane PASSIVES): a passive item's levels are its rarity ladder (common 6 .. epic 3, the top Evolved)
      E('levels', (d) => onLadder(d) && Array.isArray(d.levels) && d.levels.length > ladderLevels(d.rarity), (d) => `a ${str(d.rarity) || 'common'} item climbs ${ladderLevels(d.rarity)} levels (its rarity up to legendary, then Evolved): level ${ladderLevels(d.rarity) + 1} and up are never reached`),
      W('levels', (d) => onLadder(d) && Array.isArray(d.levels) && d.levels.length > 0 && d.levels.length < ladderLevels(d.rarity), (d) => `a ${str(d.rarity) || 'common'} item climbs ${ladderLevels(d.rarity)} levels: the last level listed repeats for the rungs not listed (tools/passive_ladder.py writes every rung)`),
      W('max_level', (d) => onLadder(d) && d.max_level != null && Number(d.max_level) !== ladderLevels(d.rarity), (d) => `the game derives a passive item's max_level from its rarity (${ladderLevels(d.rarity)} for ${str(d.rarity) || 'common'}): this ${d.max_level} is ignored`),
      W('band', (d, c) => !d.evolves_from && !!bandWarn(c), (d, c) => { const b = bandWarn(c); return `quest-locked base items ${b.locked} of ${b.base} = ${Math.round(b.share * 100)}%: the ship test wants ${Math.round(b.lo * 100)}-${Math.round(b.hi * 100)}% (pass44_test); add a quest lock or ask Claude to widen the band`; }),
    ]),
    mutation: [].concat(common('mutation'), rarityRules, [
      E('kind', (d, c) => d.kind != null && !vals(vocabOf(c).mutationKinds).includes(str(d.kind)), (d) => `unknown kind "${d.kind}" (element / volume / motion / stance / hero)`),
      E('weapon', (d, c) => !str(d.weapon) || (flat(c, 'weapons') && !findIn(flat(c, 'weapons'), d.weapon)), (d) => str(d.weapon) ? `weapon "${d.weapon}" is not a weapon` : 'a mutation names the weapon it mutates'),
      E('hero', (d, c) => str(d.hero) && heroes(c) && !findIn(heroes(c), d.hero), (d) => `hero "${d.hero}" is not a hero`),
      E('hero', (d) => str(d.kind) === 'hero' && !str(d.hero), 'kind hero needs a hero: without one it would count as a fourth path kind'),
      E('effects', (d, c) => badEffects(d.effects, 'any', vocabOf(c)).length > 0, (d, c) => `effects: ${badEffects(d.effects, 'any', vocabOf(c)).join('; ')}`),
      E('behavior', (d, c) => str(d.behavior) && !vals(vocabOf(c).behaviors).includes(str(d.behavior)), (d) => `unknown behaviour "${d.behavior}"`),
      E('badJson', (d, c) => c && c.badJson && Object.keys(c.badJson).length > 0, (d, c) => `a JSON box does not parse: ${Object.keys(c.badJson).join(', ')}`),
      W('text', (d) => !str(d.text), 'text is empty: the card shows nothing'),
      W('params', (d, c) => { const w = flat(c, 'weapons') && findIn(flat(c, 'weapons'), d.weapon); const beh = str(d.behavior) || (w ? str(w.behavior) : '') || 'ProjectileEmitter'; return unknownParams(d.params, beh).length > 0; }, (d, c) => { const w = flat(c, 'weapons') && findIn(flat(c, 'weapons'), d.weapon); const beh = str(d.behavior) || (w ? str(w.behavior) : '') || 'ProjectileEmitter'; return `params keys ${beh} does not read: ${unknownParams(d.params, beh).join(', ')}`; }),
    ]),
    // pass 69 (lane LE): a hero's perk
    perk: [].concat(common('perk'), rarityRules, [
      E('hero', (d) => !str(d.hero), 'a perk names its hero (pass66_shape_test: every perk names a hero who is there)'),
      E('hero', (d, c) => str(d.hero) && heroes(c) && !findIn(heroes(c), d.hero), (d) => `hero "${d.hero}" is not a hero`),
      E('effects', (d, c) => badEffects(d.effects, 'player', vocabOf(c)).length > 0, (d, c) => `effects: ${badEffects(d.effects, 'player', vocabOf(c)).join('; ')}`),
      E('params', (d) => d.params != null && !isObj(d.params), 'params is an object of numbers (or {} for none)'),
      E('badJson', (d, c) => c && c.badJson && Object.keys(c.badJson).length > 0, (d, c) => `a JSON box does not parse: ${Object.keys(c.badJson).join(', ')}`),
      W('text', (d) => !str(d.text), 'text is empty: the card shows nothing'),
      W('special', (d, c) => { const t = perkSpecialTable(c); return str(d.special) !== '' && !(str(d.special) in t); }, (d) => `the game runs nothing for the special "${d.special}": only the effects count (a new mechanism needs code: ask Claude)`),
      W('special', (d, c) => { const t = perkSpecialTable(c); const s = str(d.special); return s !== '' && t[s] && t[s].by === 'id' && s !== String((c && c.id) || d.id); }, (d, c) => `"${d.special}" is checked by the perk's id in the game (Run.has_perk("${d.special}")): this perk (${(c && c.id) || d.id}) gets its numbers but the mechanism never fires; only "any perk can carry it" specials (decoy, periodic_buff) work under a new id`),
      W('special', (d, c) => !str(d.special) && !(Array.isArray(d.effects) && d.effects.length), 'no special and no effects: the perk does nothing'),
      W('params', (d, c) => { const t = perkSpecialTable(c); const sp = t[str(d.special)]; return !!sp && isObj(d.params) && Object.keys(d.params).some((k2) => !(k2 in (sp.params || {}))); }, (d, c) => { const sp = perkSpecialTable(c)[str(d.special)]; return `params ${str(d.special) || 'none'} does not read: ${Object.keys(d.params).filter((k2) => !(k2 in (sp.params || {}))).join(', ')}`; }),
    ]),
  };
  /** a hero's hero mutations in play (not hidden), by the item lists when they are there, else his record; null = unknown */
  function liveHeroMutations(d, c) {
    const id = String((c && c.id) || d.id || '');
    const ms = flat(c, 'mutations');
    if (ms) return ms.filter((m) => String(m.hero || '') === id && !m.hidden).map((m) => m.id);
    return c && c.record && Array.isArray(c.record.hero_mutations) ? c.record.hero_mutations : null;
  }
  /** the perk specials as the server tells them (vocab.perk_specials), else this file's copy */
  function perkSpecialTable(c) { const v = vocabOf(c); return v && isObj(v.perk_specials) ? v.perk_specials : PERK_SPECIALS; }
  RULES.boss = RULES.enemy;

  /** a row's options resolved against a vocabulary (array or function) */
  function options(def, vocab) {
    const o = def && def.options;
    if (typeof o === 'function') return o(vocab || VOCAB) || [];
    return Array.isArray(o) ? o : [];
  }
  /** the table of a kind (boss shares the enemy's) */
  function table(kind) { return kind === 'boss' ? enemy : (AFIELDS_TABLES[kind] || []); }
  const AFIELDS_TABLES = { enemy, hero, weapon, evolution, passive, mutation, perk };

  const api = {
    VOCAB, statOptions, statKnown, statSetFor, playerStats, weaponStats, BASE_DEFAULTS, BASE_KEYS, PARAMS_KEYS, PARAMS_SHARED, paramsKnown,
    BLOCKS, BLOCK_ORDER, ATTACK_COMMON, ATTACKS, ATTACK_NAMES, attackOptions, attackTelegraph,
    enemy, hero, weapon, evolution, passive, mutation, QUEST_ROWS, SECTIONS, RECIPES, WORDINGS, RULES, options, table, hexToHsv,
    // pass 69 (lane LE)
    perk, PARAM_GROUPS, paramGroupsFor, paramInherited, isBall, PERK_SPECIALS, PERK_PARAM_HELP, perkSpecialOptions, perkSpecialTable,
    // pass 95 (lane PASSIVES): the passive items' rarity ladder
    LADDER, ladderLevels, rungAt, rungName, onLadder,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  return api;
})();
