'use strict';
// Pass 66 (lane P): page-free maths for the asset editors. No DOM here: selftest_P.py runs this file under Node like
// model.js. What lives here: the strip grid (frame offsets, cells, which key a view plays, mirroring, preview rates),
// the variant codes (INTERFACES.md §3's rule), the words (TextGen.describe_effect and TextGen.hero_trait ported from
// game/core/systems/TextGen.gd:106-139 and 958-1006), the enemy numbers the compare panel and the attack script show
// (EnemyManager.gd:3633-3676's telegraph rules, the wind-up pacing), the items' derived availability and the
// quest-locked band, and `issues(kind, doc, ctx)`, which runs AFIELDS.RULES so the same rules check a document in the
// page and in the self-test.
const AssetsModel = (() => {
  // the fixed pack order of an enemy strip (EnemyDef.gd:521-527) and of a hero strip (Player.gd:165, artkit.CHAR_ORDER)
  const ENEMY_ORDER = ['idle', 'run', 'attack', 'hit', 'die', 'run_b', 'idle_b', 'run_s', 'idle_s', 'run_bd', 'idle_bd', 'run_fd', 'idle_fd'];
  const CHAR_ORDER = ['idle', 'run', 'turn', 'hit', 'die', 'cheer', 'idle_f', 'run_f', 'idle_s', 'run_s', 'idle_bd', 'run_bd', 'idle_fd', 'run_fd', 'hit_f', 'hit_s', 'hit_bd', 'hit_fd'];
  const ENEMY_SUFFIX = { front: '', back: '_b', side: '_s', bd: '_bd', fd: '_fd' };
  const HERO_SUFFIX = { back: '', front: '_f', side: '_s', bd: '_bd', fd: '_fd' };
  // Player.gd:965: when a view's key is missing the hero walks this chain
  const HERO_FALLBACK = { '': [''], '_bd': ['_bd', '_s', ''], '_s': ['_s', '_bd', '_fd', ''], '_fd': ['_fd', '_s', '_f'], '_f': ['_f', '_fd', ''] };
  const ID_RE = /^[a-z0-9_]+$/;
  const HEX_RE = /^#[0-9A-Fa-f]{6}$/;

  // ------------------------------------------------------------------ the game's stat tables (StatSheet.gd:8-54, TextGen.gd:9-51)

  const PLAYER_DEFAULTS = {
    max_hp: 100, damage_reduction: 0, regen: 0, move_speed: 3.6, might: 1, cooldown: 1, area: 1, projectile_speed: 1, duration: 1, amount: 0, magnet: 1.5, luck: 0,
    freeze_chance: 0, crit_heal_chance: 0, gold_on_hit: 0, greed: 1, lifesteal: 0, revives: 0, turn_rate: 180, rerolls: 1, skips: 2, banishes: 1,
    crit_chance: 0.01, crit_damage: 2, execute_frac: 0, thorns: 0, adrenaline_speed: 0, adrenaline_might: 0, overkill: 0, cooldown_on_kill: 0, xp_gain: 1, ricochet: 0, homing_turn: 1, haste: 1,
    evade: 0, evade_invuln: 0, shield_max: 0, shield_delay: 3, shield_rate: 0.5, regen_delay: 3, lifesteal_cap: 0.04, heal_drop: 0, coin_drop: 0,
    hit_invuln: 0.25, revive_hp: 0.5, desperado: 0, debuff_duration: 1, difficulty: 0, still_regen: 0, still_might: 0, barrel_speed: 0, barrel_seconds: 0, xp_drop_chance: 0, elite_damage: 0,
    phoenix_revive: 0, hurt_speed: 0, hurt_speed_seconds: 0, powder_keg_chance: 0, coin_on_hit: 0, gas_mask_cap: 0, kill_might: 0, buff_duration: 1, heal_mult: 1, powerup_duration: 1, powerup_chance: 1,
    // pass 69 (lane PAS): Counterpunch, Heavyweight, Snake Oil, Hot Springs, Last Stand, the Magnet's EXP pulls
    counter_damage: 0, counter_haste: 0, counter_speed: 0, counter_seconds: 0, heavyweight: 0, overheal: 0, heal_pulse: 0, last_stand: 0, xp_pull_radius: 0, xp_pull_rate: 0,
    // pass 70 (lane LINES): the evolved lines' twists
    bronco_chance: 0, debuff_jump: 0, star_block_every: 0, gem_sweep_every: 0, vein_chance: 0, gold_might: 0,
    // pass 88 (lane MIRROR): the Upgrade board's Stakes
    danger_hp: 0, danger_attack: 0, danger_speed: 0, danger_bounty: 0, boss_danger_hp: 0, boss_danger_attack: 0, boss_danger_speed: 0, boss_danger_bounty: 0,
  };
  // player stats the systems read that are not in PLAYER_DEFAULTS (default 0): Game.gd brand_chance, EnemyManager fire_vuln / poison_slow / poison_pass
  const PLAYER_EXTRA = ['brand_chance', 'fire_vuln', 'poison_slow', 'poison_pass'];
  const STAT_FLOORS = { regen_delay: 0.5 };
  // stat -> [shown name, kind]; kind: num | pct | sec | m | deg | count (TextGen.STATS, the one place a stat's name lives)
  const STATS = {
    damage: ['damage', 'num'], cooldown: ['cooldown', 'sec'], amount: ['projectiles', 'count'], pierce: ['pierce', 'count'], area: ['area of effect', 'pct'],
    speed: ['projectile speed', 'num'], duration: ['duration', 'sec'], knockback: ['knockback', 'num'], chains: ['chain jumps', 'count'], range: ['range', 'm'],
    spread_deg: ['spread', 'deg'], orbit_radius: ['orbit radius', 'm'], max_hp: ['max HP', 'num'], damage_reduction: ['damage reduction', 'pct'],
    regen: ['regen per second', 'num'], move_speed: ['move speed', 'num'], might: ['attack damage', 'pct'], projectile_speed: ['projectile speed', 'pct'],
    magnet: ['pickup radius', 'm'], luck: ['luck', 'pct'], greed: ['coin gain', 'pct'], revives: ['revives', 'count'], rerolls: ['rerolls', 'count'], skips: ['skips', 'count'],
    banishes: ['banishes', 'count'], hp: ['HP', 'num'], size: ['size', 'pct'], turn_rate: ['turn rate', 'num'], lifetime: ['turret lifetime', 'sec'],
    poison_damage: ['poison per tick', 'num'], poison_stacks: ['poison stacks', 'count'], poison_duration: ['poison lasts', 'sec'], lifesteal: ['life steal', 'pct'],
    fire_damage: ['burn per tick', 'num'], fire_duration: ['burns for', 'sec'], fire_spread: ['spread chance', 'pct'], crit_chance: ['crit chance', 'pct'],
    crit_damage: ['crit damage', 'pct'], execute_frac: ['execute threshold', 'pct'], thorns: ['thorns damage', 'num'], adrenaline_speed: ['speed per kill stack', 'pct'],
    adrenaline_might: ['attack damage per kill stack', 'pct'], overkill: ['overkill splash', 'pct'], cooldown_on_kill: ['cooldown cut per kill', 'sec'], xp_gain: ['XP gain', 'pct'],
    ricochet: ['ricochet chance', 'pct'], homing_turn: ['homing agility', 'pct'], haste: ['weapon speed', 'pct'], evade: ['evade chance', 'pct'],
    evade_invuln: ['untouchable after an evade', 'sec'], shield_max: ['shield', 'num'], shield_delay: ['shield recharge wait', 'sec'], shield_rate: ['shield recharge a second', 'pct'],
    regen_delay: ['regen wait after a hit', 'sec'], lifesteal_cap: ['life steal cap a second', 'pct'], heal_drop: ['cake drop chance', 'pct'], coin_drop: ['coin bag drop chance', 'pct'],
    brand_chance: ['chance a kill burns the ground', 'pct'], desperado: ['attack damage as health falls', 'pct'], revive_hp: ['health on revive', 'pct'],
    hit_invuln: ['invulnerability after a hit', 'sec'], cone_deg: ['cone width', 'deg'], lift: ['lift', 'm'], pin: ['pins for', 'sec'], plant: ['stands in the sand for', 'sec'],
    freeze_chance: ['chance a hit freezes for 1 s', 'pct'], crit_heal_chance: ['chance a crit heals 2% max HP', 'pct'], gold_on_hit: ['gold when hit', 'num'],
    debuff_duration: ['debuff duration', 'pct'], difficulty: ['difficulty', 'pct'], still_regen: ['regen per second standing still', 'num'],
    still_might: ['attack damage per second standing still', 'pct'], barrel_speed: ['move speed after a barrel', 'pct'], barrel_seconds: ['barrel boost', 'sec'],
    xp_drop_chance: ['extra XP gem chance', 'pct'], elite_damage: ['damage to Elites and bosses', 'pct'], phoenix_revive: ['free revive', 'count'],
    hurt_speed: ['move speed after a hit', 'pct'], hurt_speed_seconds: ['boost after a hit', 'sec'], powder_keg_chance: ['chance a kill blows up', 'pct'],
    coin_on_hit: ['chance a hit knocks a coin out', 'pct'], gas_mask_cap: ['damage reduction from poisoned enemies', 'pct'], kill_might: ['attack damage per 1,000 kills', 'pct'],
    buff_duration: ['buff duration', 'pct'], heal_mult: ['healing', 'pct'], radius: ['pillar radius', 'm'], powerup_duration: ['power-up duration', 'pct'], powerup_chance: ['power-up drop chance', 'pct'],
    // pass 69: the new passive items' stats; kind "word" = said in words, never with a number (the Magnet's "pulls more often")
    counter_damage: ['damage of the next attack after an evade', 'pct'], counter_haste: ['attack speed after an evade', 'pct'], counter_speed: ['move speed after an evade', 'pct'],
    counter_seconds: ['boost after an evade', 'sec'], heavyweight: ['attack damage per 10 max HP', 'pct'], overheal: ['overheal past full health', 'pct'],
    heal_pulse: ['damage a heal sends out', 'num'], last_stand: ['attack damage in Last Stand', 'pct'], xp_pull_radius: ['EXP pull radius', 'm'], xp_pull_rate: ['pulls more often', 'word'],
    // pass 70 (lane LINES); kind "rule" = said in TextGen.RULE_TEXT's words with the number inside
    bronco_chance: ['chance a knocked-back enemy is launched', 'pct'], debuff_jump: ['debuff jumps', 'rule'], star_block_every: ['seconds between star blocks', 'rule'],
    gem_sweep_every: ['seconds between gem sweeps', 'rule'], vein_chance: ['chance a kill bursts into 5 XP gems', 'pct'], gold_might: ['attack damage per 100 gold gained', 'pct'],
    // pass 88 (lane MIRROR): the Upgrade board's Stakes; kind "hidden" = never written anywhere (their bounty)
    danger_hp: ['enemy HP', 'pct'], danger_attack: ['enemy attack', 'pct'], danger_speed: ['enemy speed', 'pct'], danger_bounty: ['', 'hidden'],
    boss_danger_hp: ['boss and Elite HP', 'pct'], boss_danger_attack: ['boss and Elite attack', 'pct'], boss_danger_speed: ['boss and Elite speed', 'pct'],
    boss_danger_bounty: ['', 'hidden'],
  };
  // pass 69: what a new stat does, in a line (the effect picker's hover and the line under an effect); vocab.py STAT_HELP
  const STAT_HELP = {
    counter_damage: 'Counterpunch: after an evade the next weapon to fire hits for 1 + this (1.0 = double) with every hit, until it fires again or 1 s passes',
    counter_haste: 'Counterpunch: weapon speed (haste) during the boost after an evade',
    counter_speed: 'Counterpunch: move speed during the boost after an evade',
    counter_seconds: 'Counterpunch: how long the boost after an evade lasts (Buff duration stretches it); 0 = no boost',
    heavyweight: 'Heavyweight: attack damage grows with max HP: this much per whole 10 max HP (its own source on the pause screen)',
    overheal: 'Snake Oil: heals that are not regen can go past full health up to this share of max HP; hits take it first, it never fades, pink on the HP bar',
    heal_pulse: 'Hot Springs: every heal (regen too, one pulse per 0.5 s at most) hurts creatures within 3 m for this + 2 per HP healed, 40 at most',
    last_stand: 'Last Stand: a hit that leaves him under 30% health slows time to half for 2 s and adds this much attack damage; a hidden 20 s cooldown',
    xp_pull_radius: 'Magnet: every few seconds at random every EXP gem within this many metres flies to the hero (never chests, gold or power-ups); 8.5 m at most',
    xp_pull_rate: 'Magnet: the pulls\' random 3-8 s wait is divided by 1 + this (1.0 = 1.5-4 s); the cards say "pulls more often", never a number',
    // pass 70 (lane LINES)
    bronco_chance: 'Bucking Bronco: the chance a hero\'s hit that knocks a plain creature back throws it up and away instead (2.8 m up, 2.5-6 m away, 0.8 s, no fall damage); bosses and Elites only take the knock',
    debuff_jump: 'Prairie Fire: how many times a burn or poison that runs out, or whose creature dies, jumps to the nearest creature within 4 m that lacks it, at its full seconds (a fire never onto the boss)',
    star_block_every: 'Marshal\'s Star: a gold star over the hero blocks one whole hit, then comes back after this many seconds; 0 = none',
    gem_sweep_every: 'Mother Lode: every this many seconds every XP gem on the screen flies to the hero (the first 1 s after it is taken); 0 = none',
    vein_chance: 'Eureka: the chance a kill bursts into 5 more XP gems of its size (rolled with Prospector\'s extra gem, so it needs xp_drop_chance above 0)',
    gold_might: 'Gold Rush: attack damage for every 100 gold gained while held (after coin gain), up to +50% in all; spending takes nothing back',
  };
  /** A stat's help line: the server's (vocab.stat_help) else this file's, else '' */
  function statHelp(stat, vocab) {
    const t = vocab && vocab.stat_help && vocab.stat_help[stat];
    return t ? String(t) : (STAT_HELP[stat] || '');
  }
  // weapon stats the behaviours read (WeaponInstance.gd:106-107 defaults + the systems' extras)
  const WEAPON_DEFAULTS = { damage: 5, cooldown: 1, amount: 1, pierce: 0, area: 1, speed: 10, duration: 2, knockback: 0, chains: 0, range: 8, spread_deg: 30, orbit_radius: 2, lifetime: 12 };
  const WEAPON_EXTRA = ['fire_damage', 'fire_duration', 'fire_spread', 'poison_damage', 'poison_stacks', 'poison_duration', 'ricochet', 'ricochet_damage', 'mark', 'spin', 'pull', 'cone_deg', 'lift', 'pin', 'plant', 'radius'];
  const PREFIX = { desperado: 'up to ', gas_mask_cap: 'up to ' };
  const HERO_WORDS = { regen: 'HP regen', regen_delay: 'regen delay', max_hp: 'max HP' };
  const HERO_NOTES = { debuff_duration: '{his} burns, poison, slows and pins last longer; buffs do not' };
  const HERO_LOWER = ['cooldown', 'regen_delay', 'shield_delay'];

  const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x);
  const num = (v, d) => { const n = Number(v); return v == null || v === '' || !isFinite(n) ? d : n; };
  const isNum = (v) => typeof v === 'number' && isFinite(v);

  // ------------------------------------------------------------------ strips

  function order(kind) { return kind === 'hero' ? CHAR_ORDER : ENEMY_ORDER; }

  /** frame index of animation `anim`'s first frame in a strip packed in `order` with these `anims` counts (-1: not in the order) */
  function frameOffset(anims, anim, ord) {
    let off = 0;
    for (const a of ord || ENEMY_ORDER) { if (a === anim) return off; off += (anims && isNum(Number(anims[a])) && anims[a] > 0) ? Math.floor(anims[a]) : 0; }
    return -1;
  }

  /** every animation's first frame, in pack order (a key the strip lacks sits at -1) */
  function offsets(anims, kind) {
    const out = {};
    for (const a of order(kind)) out[a] = frameOffset(anims, a, order(kind));
    return out;
  }

  /** the sum of every count (EnemyDef.total_frames: unknown keys count too, the shader slices by count) */
  function totalFrames(anims) { let n = 0; for (const k in (anims || {})) { const v = Number(anims[k]); if (isFinite(v) && v > 0) n += Math.floor(v); } return n; }

  /** the cell (x, y) in pixels of frame k in a strip of `cols` columns (0 = one row) */
  function cell(k, cols, framePx) { const c = cols > 0 ? cols : Math.max(1, k + 1); return [(k % c) * framePx, Math.floor(k / c) * framePx]; }

  /** rows a strip of `total` frames takes at `cols` columns (EnemyManager.gd:799-801) */
  function rows(total, cols) { return cols > 0 ? Math.max(1, Math.ceil(total / cols)) : 1; }

  /** 8 when the strip has a side set (EnemyManager.gd:814 `frames_of("run_s") > 0`), else 2 */
  function directions(anims) { return anims && Number(anims.run_s) > 0 ? 8 : 2; }

  /** The key a view plays and whether the game fell back to another set. Enemy: attack / hit / die exist once (the front
   *  set) and play in any view; idle / run take the view's suffix; a missing back / side set shows the front one. Hero:
   *  "" is the back (walking away), _f the front; die / cheer / turn exist once; hit has a key per view; a missing key
   *  walks Player.gd:965's chain. */
  function animKey(kind, anim, dir, anims) {
    const has = (k) => anims && Number(anims[k]) > 0;
    if (kind === 'hero') {
      if (anim === 'die' || anim === 'cheer' || anim === 'turn') return { key: anim, fell: false, chain: [anim] };
      const want = HERO_SUFFIX[dir] == null ? '' : HERO_SUFFIX[dir];
      const chain = HERO_FALLBACK[want] || [''];
      for (const s of chain) if (has(anim + s)) return { key: anim + s, fell: s !== want, chain: chain.map((x) => anim + x) };
      return { key: anim + want, fell: false, missing: true, chain: chain.map((x) => anim + x) };
    }
    if (anim === 'attack' || anim === 'hit' || anim === 'die') return { key: anim, fell: false, chain: [anim] };
    const s = ENEMY_SUFFIX[dir] == null ? '' : ENEMY_SUFFIX[dir];
    if (has(anim + s)) return { key: anim + s, fell: false, chain: [anim + s, anim] };
    return { key: anim, fell: s !== '', missing: !has(anim), chain: [anim + s, anim] };
  }

  /** Whether the drawn frame is mirrored: side / diagonal sets face screen-right as painted and mirror heading left
   *  (EnemyManager.gd:2695-2701, Player.gd:459); an enemy's front and back sets mirror too, inverted by front_faces /
   *  back_faces "left", never for "straight" (EnemyDef.gd:77-80); a hero's back and front sets never mirror. */
  function mirror(kind, dir, facing, frontFaces, backFaces) {
    const left = facing === 'left';
    if (dir === 'side' || dir === 'bd' || dir === 'fd') return left;
    if (kind === 'hero') return false;
    const faces = dir === 'back' ? (backFaces || 'right') : (frontFaces || 'right');
    if (faces === 'straight') return false;
    return faces === 'left' ? !left : left;
  }

  /** The rate a preview plays an animation at (approximate: the game runs an enemy's `run` by its speed when fps.run is
   *  0, EnemyManager.gd:2727; die 6 and the hero's SPEEDS table, BillboardSprite.gd:9). */
  function previewFps(kind, anim, fps) {
    const f = isObj(fps) ? fps : {};
    const base = anim.replace(/_(b|s|bd|fd|f)$/, '');
    if (kind === 'hero') {
      if (base === 'run') return num(f.run, 14) || 14;
      if (base === 'hit') return num(f.hit, 12) || 12;
      if (base === 'die') return num(f.die, 8) || 8;
      if (base === 'turn') return 8;
      return 6;
    }
    if (base === 'run') return num(f.run, 10) || 10;
    if (base === 'die') return num(f.die, 6) || 6;
    if (base === 'attack' || base === 'hit') return 8;
    return 6;
  }

  // ------------------------------------------------------------------ variant codes (INTERFACES.md §3)

  /** The prefix new codes take: the most common prefix among the existing `variants` keys, else `variant_base`'s part
   *  before its dash, else the initials of the id's words (dune_scorpion -> DS; a one-word id its first three letters,
   *  goblin -> GOB). */
  function prefixOf(doc, id) {
    const d = doc || {};
    const counts = {};
    let best = '', bestN = 0;
    for (const code of Object.keys(isObj(d.variants) ? d.variants : {})) {
      const i = String(code).lastIndexOf('-');
      if (i <= 0) continue;
      const p = String(code).slice(0, i);
      counts[p] = (counts[p] || 0) + 1;
      if (counts[p] > bestN) { best = p; bestN = counts[p]; }
    }
    if (best) return best;
    const vb = String(d.variant_base || '');
    if (vb.lastIndexOf('-') > 0) return vb.slice(0, vb.lastIndexOf('-'));
    const words = String(id || d.id || '').split('_').filter(Boolean);
    if (words.length > 1) return words.map((w) => w[0]).join('').toUpperCase();
    return String(words[0] || 'X').slice(0, 3).toUpperCase();
  }

  /** A, B, .., Z, AA, AB, .., AZ, BA, .. */
  function suffixAt(n) {
    if (n < 26) return String.fromCharCode(65 + n);
    const m = n - 26;
    return String.fromCharCode(65 + Math.floor(m / 26)) + String.fromCharCode(65 + (m % 26));
  }

  /** The suffixes already taken: every variants key's part after its dash (a stub entry without a sprite counts), and
   *  every `<id>_sprite_<s>.png` / `<id>_icon_<s>.png` on disk (`files`: the folder's file names). */
  function usedSuffixes(doc, id, files) {
    const used = new Set();
    const d = doc || {};
    for (const code of Object.keys(isObj(d.variants) ? d.variants : {})) {
      const s = String(code);
      used.add((s.lastIndexOf('-') >= 0 ? s.slice(s.lastIndexOf('-') + 1) : s).toUpperCase());
    }
    const re = new RegExp('^' + String(id || d.id || '').replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '_(?:sprite|icon)_([a-z0-9]+)\\.png$', 'i');
    for (const f of files || []) { const m = String(f).match(re); if (m) used.add(m[1].toUpperCase()); }
    return used;
  }

  /** The next `n` free codes (`PREFIX-A`, ...) for a creature or hero document. */
  function nextCodes(doc, id, files, n) {
    const prefix = prefixOf(doc, id);
    const used = usedSuffixes(doc, id, files);
    const out = [];
    for (let k = 0; out.length < (n || 1) && k < 26 * 27; k++) {
      const s = suffixAt(k);
      if (!used.has(s)) out.push(prefix + '-' + s);
    }
    return out;
  }

  /** The strip, icon and marker files a look's code names (gen_art: `<id>_sprite_<letter>.png`, lower-case suffix). */
  function codeFiles(id, code) {
    const s = String(code).split('-').pop().toLowerCase();
    return { sprite: `${id}_sprite_${s}.png`, icon: `${id}_icon_${s}.png`, marker: `${id}_${s}_ai.json`, clipKey: String(code).toLowerCase().replace(/-/g, '') };
  }

  const slugOk = (s) => ID_RE.test(String(s || ''));
  const slugify = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');

  // ------------------------------------------------------------------ words (TextGen.gd)

  /** TextGen._plain: as few decimals as it needs, two at most. */
  function plain(a) {
    const x = Math.abs(a);
    if (Math.abs(x - Math.round(x)) < 0.001) return String(Math.round(x));
    if (Math.abs(x * 10 - Math.round(x * 10)) < 0.001) return x.toFixed(1);
    return x.toFixed(2);
  }
  const signed = (v, suffix) => (v >= 0 ? '+' : '−') + plain(Math.abs(v)) + (suffix || '');
  function statName(stat, vocab) {
    const t = vocab && vocab.stats && vocab.stats[stat];
    if (t && t.name) return t.name;
    return STATS[stat] ? STATS[stat][0] : String(stat).replace(/_/g, ' ');
  }
  function statKind(stat, vocab) {
    const t = vocab && vocab.stats && vocab.stats[stat];
    if (t && t.kind) return t.kind;
    return STATS[stat] ? STATS[stat][1] : 'num';
  }
  function formatValue(stat, v, vocab) {
    switch (statKind(stat, vocab)) {
      case 'pct': return `${Math.round(v * 100)}%`;
      case 'sec': return `${Number(v).toFixed(2)} s`;
      case 'm': return `${Number(v).toFixed(1)} m`;
      case 'deg': return `${Math.round(v)}°`;
      case 'count': return String(Math.round(v));
      case 'word': return Number(v) > 0 ? statName(stat, vocab) : '—';   // pass 69: never a number on a card
      case 'hidden': return '—';   // pass 88: never written
      default: return Math.abs(v - Math.round(v)) < 0.001 ? String(Math.round(v)) : Number(v).toFixed(1);
    }
  }
  const singular = (name) => (name.endsWith('s') ? name.slice(0, -1) : name);

  /** TextGen.describe_effect: "+25% damage", "+1 pierce", "+2 projectiles", "−0.1 s cooldown", "range = 14.0 m". `opts.weaponName(id)`
   *  names a weapon:<id> target; `opts.withName` false drops the stat's name. */
  function describeEffect(e, opts) {
    const o = opts || {};
    const withName = o.withName !== false;
    if (!isObj(e) || !e.stat) return '';
    const stat = String(e.stat), op = String(e.op || 'add'), value = num(e.value, 0);
    const name = statName(stat, o.vocab), kind = statKind(stat, o.vocab);
    // pass 69 (TextGen.describe_effect): a stat said in words ("word": the Magnet's "pulls more often") is its name when
    // it grows, nothing else, never a number
    if (kind === 'word') return value > 0 && withName ? name : '';
    // pass 88 (TextGen.describe_effect): a hidden stat says nothing
    if (kind === 'hidden') return '';
    let out = '';
    if (op === 'mul') {
      const pct = Math.round(value * 100);
      out = (pct >= 0 ? '+' : '−') + Math.abs(pct) + '%' + (withName ? ' ' + name : '');
    } else if (op === 'add') {
      if (kind === 'count') { const n = Math.round(value); out = signed(n) + (withName ? ' ' + (n !== 1 && n !== -1 ? name : singular(name)) : ''); }
      else if (kind === 'sec') out = signed(value, ' s') + (withName ? ' ' + name : '');
      else if (kind === 'm') out = signed(value, ' m') + (withName ? ' ' + name : '');
      else if (kind === 'pct') out = signed(value * 100, '%') + (withName ? ' ' + name : '');
      else out = signed(value) + (withName ? ' ' + name : '');
    } else if (op === 'set') {
      out = (withName ? name + ' = ' : '= ') + formatValue(stat, value, o.vocab);
    } else return `(unknown op "${op}")`;
    if (op !== 'set' && PREFIX[stat]) out = PREFIX[stat] + out;
    const target = String(e.target || '');
    if (target === 'all_weapons') out += ', all weapons';
    else if (target.startsWith('weapon:')) out += ', ' + (o.weaponName ? o.weaponName(target.slice(7)) : target.slice(7));
    else if (target.startsWith('tag:')) out += ', ' + target.slice(4) + ' weapons';
    return out;
  }
  const describeEffects = (list, opts) => (Array.isArray(list) ? list.map((e) => describeEffect(e, opts)).filter(Boolean).join(', ') : '');

  const heroWord = (stat) => HERO_WORDS[stat] || statName(stat);
  function possessive(doc) { const p = doc && doc.pronoun; return p === 'he' ? 'his' : p === 'she' ? 'her' : 'their'; }
  /** TextGen.hero_amount: unsigned, "1%", "2", "0.1", "0.05 s" */
  function heroAmount(stat, op, value) {
    const a = Math.abs(value);
    if (op === 'mul' || statKind(stat) === 'pct') return plain(a * 100) + '%';
    if (statKind(stat) === 'sec') return plain(a) + ' s';
    return plain(a);
  }
  /** TextGen.hero_capped: a step down stops at the stat's floor, measured from its default */
  function heroCapped(e) {
    let v = num(e.value, 0);
    if (STAT_FLOORS[e.stat] != null && (e.op || 'add') === 'add' && v < 0) {
      const room = num(PLAYER_DEFAULTS[e.stat], 0) - STAT_FLOORS[e.stat];
      v = -Math.min(-v, Math.max(room, 0));
    }
    return v;
  }
  /** TextGen.hero_step: "+1%", "−0.05 s" */
  function heroStep(e) { const v = heroCapped(e); return (v < 0 ? '−' : '+') + heroAmount(e.stat, e.op || 'add', v); }

  /** TextGen.hero_trait (TextGen.gd:958-983): the rule in words from `trait_per_level`; a hero without one reads his
   *  own `trait_text`, else his flat `trait` described. */
  function heroTrait(doc) {
    const d = doc || {};
    const lt = Array.isArray(d.trait_per_level) ? d.trait_per_level.filter((e) => isObj(e) && e.stat) : [];
    if (!lt.length) return d.trait_text ? String(d.trait_text) : describeEffects(d.trait);
    const parts = [], notes = [];
    for (const e of lt) {
      const stat = String(e.stat), op = String(e.op || 'add'), value = num(e.value, 0);
      const word = heroWord(stat);
      if (value < 0 && HERO_LOWER.includes(stat)) parts.push(`${heroAmount(stat, op, value)} less ${word}`);
      else parts.push(`${heroAmount(stat, op, value)} ${word}`);
      if (STAT_FLOORS[stat] != null) notes.push(`${word} never under ${heroAmount(stat, 'add', STAT_FLOORS[stat])}`);
      if (HERO_NOTES[stat]) notes.push(HERO_NOTES[stat].replace('{his}', possessive(d)));
    }
    let s = 'Gain ' + parts.join(' and ') + ' per level';
    if (num(d.level_heal, 0) > 0) s += `, and heal ${plain(num(d.level_heal, 0) * 100)}% of max HP on every level-up`;
    if (notes.length) s += ' (' + notes.join('; ') + ')';
    s += '.';
    // pass 67 (TextGen.hero_trait): a hero with a special of his own (Buck's charge) says it after the rule, in his trait_text
    if (heroOwnWords(d)) s += ' ' + String(d.trait_text);
    return s;
  }

  /** Whether the hero's trait_text is his own words, said after the rule (pass 67): he has a special and the words; the
   *  "Set from the rule" button and the trait_text warning leave him alone. */
  function heroOwnWords(doc) {
    const d = doc || {};
    return !!d.trait_text && Array.isArray(d.specials) && d.specials.length > 0;
  }

  /** TextGen.hero_trait_at: what the stat comes to at `level`, signed ("+12% crit chance", "+1.2 HP regen and 0.6 s less regen delay"). */
  function heroTraitAt(doc, level) {
    const d = doc || {};
    const lt = Array.isArray(d.trait_per_level) ? d.trait_per_level.filter((e) => isObj(e) && e.stat) : [];
    if (!lt.length) return '';
    const parts = [];
    for (const e of lt) {
      const op = String(e.op || 'add');
      const v = heroCapped({ stat: e.stat, op, value: num(e.value, 0) * Math.max(1, num(level, 1)) });
      const word = heroWord(String(e.stat));
      if (v < 0 && HERO_LOWER.includes(String(e.stat))) parts.push(`${heroAmount(e.stat, op, v)} less ${word}`);
      else parts.push(`${v < 0 ? '−' : '+'}${heroAmount(e.stat, op, v)} ${word}`);
    }
    return parts.join(' and ');
  }
  function heroTraitNow(doc, level) { const at = heroTraitAt(doc, level); return at ? `${at} at level ${level}` : ''; }

  // ------------------------------------------------------------------ enemies

  /** EnemyDef.default_knockback: clamp(3.4 * sqrt(damage / 4), 2.5, 7.0) */
  function defaultKnockback(damage) { return Math.min(7, Math.max(2.5, 3.4 * Math.sqrt(Math.max(0, num(damage, 0)) / 4))); }

  const BLOCK_NAMES = ['ranged', 'charge', 'kamikaze', 'artillery', 'caster', 'support', 'ambush', 'death_burst', 'boss', 'elite', 'sniper', 'flee_on_hit'];
  // the blocks each brain reads (EnemyManager.gd:2858-3061); chase / flock / dummy read none
  const NATURAL = { kite: ['ranged'], charge: ['charge'], kamikaze: ['kamikaze'], artillery: ['artillery'], caster: ['caster', 'boss'], support: ['support'], ambush: ['ambush', 'ranged'], boss: ['boss'], sniper: ['sniper'] };
  function naturalBlocks(brain, archetype) {
    const out = (NATURAL[brain] || []).slice();
    if (archetype === 'elite' && !out.includes('elite')) out.push('elite');
    if (archetype === 'boss' && !out.includes('boss')) out.push('boss');
    return out;
  }
  /** the blocks a document carries (an object under the key) */
  function blocksOf(doc) { return BLOCK_NAMES.filter((b) => isObj((doc || {})[b])); }
  /** "brain|sorted block names": the key the untested-combination check compares with the server's `combos_seen` */
  function combo(doc) { return `${(doc || {}).brain || 'chase'}|${blocksOf(doc).sort().join('+')}`; }
  function comboWords(doc) {
    const b = blocksOf(doc).sort();
    return `${(doc || {}).brain || 'chase'}${b.length ? ' with ' + b.join(' + ') : ' with no block'}`;
  }

  /** The record shape server.creature_record gives the page, built from a document, so Model.creatureAt / knockbackOf
   *  accept an unsaved enemy. */
  function enemyRecord(doc, kind, id) {
    const d = doc || {};
    const boss = isObj(d.boss) ? d.boss : null;
    const bossOut = boss ? { attacks: (Array.isArray(boss.attacks) ? boss.attacks : []).map((a) => (isObj(a) ? String(a.name || '') : String(a))).filter(Boolean) } : null;
    if (bossOut) for (const k of ['cooldown_between', 'hp_mult_per_stage']) if (boss[k] != null) bossOut[k] = boss[k];
    const kb = d.knockback;
    return {
      id: id || d.id || '', name: String(d.name || id || ''), kind: kind || (d.archetype === 'boss' ? 'boss' : 'enemy'),
      archetype: String(d.archetype || 'walker'), brain: String(d.brain || 'chase'),
      hp: num(d.hp, 10), damage: num(d.damage, 5), speed: num(d.speed, 2.5), size: isNum(d.size) ? d.size : 1, radius: num(d.radius, 0.5),
      pack_size: num(d.pack_size, 1), cap_share: num(d.cap_share, 1), max_alive: num(d.max_alive, 0), xp_mult: num(d.xp_mult, 1),
      damage_reduction: num(d.damage_reduction, 0), knockback_resist: num(d.knockback_resist, 0), contact_cd: num(d.contact_cd, 0.6), drops: isObj(d.drops) ? d.drops : {},
      ranged: isObj(d.ranged) ? d.ranged : null, charge: isObj(d.charge) ? d.charge : null, kamikaze: isObj(d.kamikaze) ? d.kamikaze : null,
      artillery: isObj(d.artillery) ? d.artillery : null, boss: bossOut, elite: isObj(d.elite) ? d.elite : null, variance: isObj(d.variance) ? d.variance : {},
      knockback: isNum(kb) ? kb : null, can_be_elite: d.can_be_elite == null ? true : !!d.can_be_elite, hidden: !!d.hidden, retired: !!d.retired,
      doc: String(d.doc || ''), flavour: String(d.flavour || ''),
    };
  }

  // ---- the attack script (EnemyManager.gd:3633-3676 and 3883-3895)
  const VOLLEY_START = 1.2, VOLLEY_HIT = 0.6;
  /** How far a tumbleweed of the King's volley rolls: VOLLEY_START + speed x life + VOLLEY_HIT */
  function volleyReach(atk) { return VOLLEY_START + num(atk.speed, 9) * num(atk.life, 2.6) + VOLLEY_HIT; }

  /** What the telegraph draws for one attack, in metres: `tel` is the resolved telegraph kind (the attack's own, else
   *  the name's default). line: `length`, else a roll's speed x duration + the body's radius, else 22; ring: `radius`
   *  (6) round the creature; ring_at_hero: `radius` (5) round the hero; sector: `radius` (6.5) and `deg` (180); fan:
   *  `count` (7) lines over `spread_deg` (90) of `length` (14); spokes: `count` (12) lines of `spoke_length`, else how far
   *  a tumbleweed rolls (approximate). */
  function telegraphGeometry(atk, tel, radius) {
    const a = isObj(atk) ? atk : {};
    const r = num(radius, 0.5);
    switch (String(tel || 'none')) {
      case 'line': {
        let L = num(a.length, 0);
        let approx = false;
        if (L <= 0) { if (String(a.name || '') === 'roll') L = num(a.speed, 12) * num(a.duration, 1.2) + r; else L = 22; approx = false; }
        return { kind: 'line', length: L, approx, words: `a line ${plain(L)} m ahead` };
      }
      case 'ring': { const R = num(a.radius, 6); return { kind: 'ring', radius: R, atHero: false, words: `a ring of ${plain(R)} m round it` }; }
      case 'ring_at_hero': { const R = num(a.radius, 5); return { kind: 'ring', radius: R, atHero: true, words: `a ring of ${plain(R)} m on the hero` }; }
      case 'sector': { const R = num(a.radius, 6.5), deg = num(a.deg, 180); return { kind: 'sector', radius: R, deg, words: `a ${plain(deg)}° wedge ${plain(R)} m deep ahead` }; }
      case 'fan': { const n = Math.max(1, Math.round(num(a.count, 7))), spread = num(a.spread_deg, 90), L = num(a.length, 14); return { kind: 'fan', count: n, spread, length: L, words: `${n} lines of ${plain(L)} m over ${plain(spread)}° ahead` }; }
      case 'spokes': {
        const n = Math.max(1, Math.round(num(a.count, 12)));
        let L = num(a.spoke_length, 0), approx = false;
        if (L <= 0) { L = volleyReach(a); approx = true; }
        return { kind: 'spokes', count: n, length: L, approx, words: `${n} lines of ${approx ? '≈ ' : ''}${plain(L)} m all round` };
      }
      default: return { kind: 'none', words: 'no telegraph' };
    }
  }

  /** How long the attack itself lasts after its wind-up (the sequence line's hatched block). */
  function attackActive(atk) {
    const a = isObj(atk) ? atk : {};
    switch (String(a.name || '')) {
      case 'roll': return num(a.duration, 1.2);
      case 'rain': case 'erupt': return Math.max(1, Math.round(num(a.count, 10))) * num(a.interval, 0.3) + num(a.warn, 0.55);
      case 'swoop': return num(a.duration, 0.8) + num(a.fall, 0.45);
      case 'boulder': return num(a.flight, 1.6);
      default: return 0.3;
    }
  }

  /** 1 / (move_pace x creature_speed_mult): how many times longer every wind-up and telegraph lasts on this map
   *  (EnemyManager.gd:3633 `timer = windup / pace`, pace = Run.move_pace() x creature_speed_mult; Red Canyon 0.9 x 0.9 ->
   *  x1.23). */
  function paceOf(tl) {
    const t = isObj(tl) ? tl : {};
    const pace = num(t.move_pace, 1) * num(t.creature_speed_mult, 1);
    return pace > 0 ? 1 / pace : 1;
  }

  /** The script's cycle: per attack its wind-up (x the pace factor), its active time, then cooldown_between. */
  function attackSequence(boss, paceFactor) {
    const b = isObj(boss) ? boss : {};
    const gap = num(b.cooldown_between, 2);
    const pf = num(paceFactor, 1);
    const out = [];
    let t = 0;
    for (const atk of (Array.isArray(b.attacks) ? b.attacks : [])) {
      const a = isObj(atk) ? atk : { name: String(atk) };
      const windup = num(a.windup, 1) * pf, active = attackActive(a);
      out.push({ name: String(a.name || '?'), start: t, windup, active, gap });
      t += windup + active + gap;
    }
    return { steps: out, total: t, gap, paceFactor: pf };
  }

  /** Shots and seconds a level-1 Revolver needs (base damage 20, cooldown 1.0, amount 1: the first shot at once; pierce,
   *  might and crit ignored). */
  function revolverTTK(hp, base) {
    const b = isObj(base) ? base : {};
    const dmg = num(b.damage, 20) * Math.max(1, num(b.amount, 1));
    const shots = dmg > 0 && hp > 0 ? Math.ceil(hp / dmg) : 0;
    return { shots, seconds: Math.max(0, shots - 1) * num(b.cooldown, 1) };
  }
  /** bites to bring the hero (max HP 100) down */
  function hitsToKill(atk, maxHp) { const a = num(atk, 0); return a > 0 ? Math.ceil(num(maxHp, 100) / a) : Infinity; }

  // ------------------------------------------------------------------ items

  /** An item's state in play: hidden -> "hidden"; a quest whose unlocks names it -> "locked"; else "available". */
  function availabilityOf(item, quests, kind) {
    if (!item) return 'available';
    if (item.hidden) return 'hidden';
    const q = questFor(item.id, quests, kind);
    return q ? 'locked' : 'available';
  }
  function questFor(id, quests, kind) {
    for (const q of quests || []) {
      const u = q && isObj(q.unlocks) ? q.unlocks : null;
      if (!u || String(u.id) !== String(id)) continue;
      if (kind && u.type && String(u.type) !== kind) continue;
      return q;
    }
    return null;
  }
  /** The quest-locked share of the base items pass44_test.gd:48-79 pins (pass 69: 0.28-0.56, re-pinned when the Salt, the
   *  Frisbee and five passive items came unlocked): non-hidden base weapons and base passives (no `evolves_from`) over
   *  those with an unlock quest. */
  const BAND = { lo: 0.28, hi: 0.56 };
  function bandOf(weapons, passives, quests) {
    const base = [];
    for (const w of weapons || []) if (!w.hidden && !w.is_evolution) base.push({ id: w.id, kind: 'weapon' });
    for (const p of passives || []) if (!p.hidden && !p.evolves_from) base.push({ id: p.id, kind: 'passive' });
    const locked = base.filter((b) => !!questFor(b.id, quests, b.kind)).length;
    return { locked, base: base.length, share: base.length ? locked / base.length : 0, lo: BAND.lo, hi: BAND.hi };
  }
  /** TextGen.quest_text (pass 69: a hero's requirement reads like the game's words). `names` {weapon(id), enemy(id),
   *  map(id)} name things when the lists are there. */
  function questText(q, names) {
    if (!isObj(q)) return '';
    if (q.quest_text) return String(q.quest_text);
    const c = isObj(q.condition) ? q.condition : {};
    const nm = names || {};
    const n = (k, d) => Math.trunc(num(c[k], d));
    const grouped = (v) => String(Math.abs(v)).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    const map = (id) => (nm.map ? nm.map(id) : String(id || '').replace(/_/g, ' ').replace(/\b\w/g, (x) => x.toUpperCase()));
    const creature = (id, k) => { const name = nm.enemy ? nm.enemy(id) : String(id || '').replace(/_/g, ' ').replace(/\b\w/g, (x) => x.toUpperCase()); return k <= 1 ? 'the ' + name : `${k} ${name}${/[sx]$/.test(name) ? 'es' : 's'}`; };
    switch (String(c.type || '')) {
      case 'kills_with_weapon': return `Kill ${n('count', 0)} creatures with the ${nm.weapon ? nm.weapon(c.weapon) : String(c.weapon || '')}.`;
      case 'kills_of_enemy': return `Kill ${creature(c.enemy, n('count', 0))}.`;
      case 'reach_level': return `Reach level ${n('level', 0)} in one run.`;
      case 'survive_minutes': return `Survive ${n('minutes', 0)} minutes in one run.`;
      case 'survive_minutes_no_lift': return `Survive ${n('minutes', 0)} minutes without lifting your thumb.`;
      case 'open_chests': return `Open ${n('count', 0)} chests.`;
      case 'evolve_any': return `Evolve any weapon${n('count', 1) <= 1 ? '' : ` ${n('count', 1)} times`}.`;
      case 'extract_after_stage': return `Extract after stage ${n('stage', 1)} on ${map(c.map)}.`;
      case 'kill_boss': return `Kill the stage ${n('stage', 1)} boss on ${map(c.map)}.`;
      case 'kills_in_run_of_enemy': return `Kill ${creature(c.enemy, n('count', 0))} in one run.`;
      case 'kills_total': return `Kill ${grouped(n('count', 0))} creatures, all time.`;
      case 'runs_total': return `Play ${n('count', 0)} runs.`;
      case 'pickups_total': return `Pick up ${n('count', 0)} power-ups.`;
      case 'gold_total': return `Earn ${n('count', 0)} gold, all time.`;
      case 'reach_stage': return `Reach stage ${n('stage', 1)}.`;
      // pass 100 (lane QUESTS): TextGen.quest_build_text
      case 'hero_level': case 'item_level': case 'evolve_item': case 'weapon_paths': case 'items_maxed': return questBuildText(c, nm);
      default: return 'Complete a challenge.';
    }
  }
  /** Pass 100 (lane QUESTS): TextGen.quest_build_text, the words of the build quests. `nm.hero(id)` names a hero,
   *  `nm.items` {weapons (with the evolutions), passives, mutations} names the items; without them ids read capitalised. */
  function questBuildText(c, nm) {
    const n = (k, d) => Math.trunc(num(c[k], d));
    const cap = (id) => String(id || '').replace(/_/g, ' ').replace(/\b\w/g, (x) => x.toUpperCase());
    const it = nm.items || {};
    const weapon = (id) => (it.weapons || []).find((w) => w.id === id) || null;
    const passive = (id) => (it.passives || []).find((p) => p.id === id) || null;
    const pname = (id) => { const p = passive(id); return p ? String(p.name || id) : cap(id); };
    const itemName = (id) => { const w = weapon(id); return w ? 'the ' + String(w.name || id) : pname(id); };
    const kindWords = (k, article) => { const noun = { weapon: 'weapon', card: 'card', passive: 'passive item' }[k] || 'item'; return article ? (noun === 'item' ? 'an ' : 'a ') + noun : noun; };
    const id = String(c.id || '');
    const kind = String(c.kind || 'any');
    switch (String(c.type || '')) {
      case 'hero_level': return `Reach level ${n('level', 0)} with ${(nm.hero && nm.hero(c.hero)) || cap(c.hero)}.`;
      case 'item_level': {
        const rung = String(c.rung || '');
        const to = rung ? cap(rung) : `level ${n('level', 0)}`;
        return `Get ${id ? itemName(id) : kindWords(rung ? 'passive' : kind, true)} to ${to} in one run.`;
      }
      case 'evolve_item': {
        if (!id) return `Evolve any ${kindWords(kind, false)}.`;
        const w = weapon(id);
        if (w && w.is_evolution) return `Evolve the ${w.name || id}.`;
        if (w) { const into = weapon(w.evolves_into); return into ? `Evolve the ${w.name || id} into the ${into.name || into.id}.` : `Evolve the ${w.name || id}.`; }
        const p = passive(id);
        if (p && p.evolves_into) return `Evolve ${p.name || id} into ${pname(p.evolves_into)}.`;
        if (p && !p.line && !p.evolves_from) return `Get ${p.name || id} to Evolved in one run.`;
        return `Evolve ${itemName(id)}.`;
      }
      case 'weapon_paths': {
        const wid = String(c.weapon || '');
        if (!wid) return 'Take all of one weapon\'s mutations in one run.';
        const k = it.mutations ? it.mutations.filter((m) => String(m.weapon) === wid && !m.hidden && !m.hero && m.kind !== 'hero').length : 3;
        return `Take all ${k} mutations of ${itemName(wid)} in one run.`;
      }
      case 'items_maxed': { const k = n('count', 1); return `Hold ${k} ${kindWords(kind, false)}${k === 1 ? '' : 's'} at max level at once.`; }
      default: return 'Complete a challenge.';
    }
  }
  /** A weapon's path: its non-hero, non-hidden mutation of each kind, the hero ones, the hidden ones. */
  function pathOf(weaponId, mutations) {
    const out = { element: null, volume: null, motion: null, stance: [], hero: [], hidden: [] };
    for (const m of mutations || []) {
      if (String(m.weapon) !== String(weaponId)) continue;
      if (m.hidden) { out.hidden.push(m); continue; }
      const k = String(m.kind || 'motion');
      if (k === 'hero' || m.hero) out.hero.push(m);
      else if (k === 'stance') out.stance.push(m);
      else if (k in out && out[k] === null) out[k] = m;
      else if (k in out) (out.extra = out.extra || []).push(m);
    }
    return out;
  }
  /** What a weapon's levels come to at the top: per stat the sum of adds and the product of (1 + mul) over levels[1..]. */
  function levelsSummary(base, levels) {
    const b = isObj(base) ? base : {};
    const acc = {};
    const touch = (s) => acc[s] || (acc[s] = { add: 0, mul: 1, set: null });
    (Array.isArray(levels) ? levels : []).forEach((lv) => {
      for (const e of Array.isArray(lv) ? lv : []) {
        if (!isObj(e) || !e.stat) continue;
        // pass 69 (TextGen._sum_effects): a stat said in words has no total
        if (statKind(String(e.stat)) === 'word' || statKind(String(e.stat)) === 'hidden') continue;
        const a = touch(String(e.stat)), v = num(e.value, 0);
        if (e.op === 'mul') a.mul *= 1 + v; else if (e.op === 'set') a.set = v; else a.add += v;
      }
    });
    const rows = [];
    for (const stat of Object.keys(acc)) {
      const start = num(b[stat], num(WEAPON_DEFAULTS[stat], 0));
      const a = acc[stat];
      const end = a.set != null ? a.set : (start + a.add) * a.mul;
      rows.push({ stat, start, end, add: a.add, mul: a.mul });
    }
    return rows;
  }

  // ------------------------------------------------------------------ rules

  /** Run AFIELDS.RULES[kind] (or ctx.rules[kind]) on a document: {errors: [{key, msg}], warnings, marks: {key: {level, msgs}}}. */
  function issues(kind, doc, ctx) {
    const c = ctx || {};
    const table = c.rules || (typeof AFIELDS !== 'undefined' ? AFIELDS.RULES : null) || {};
    const errors = [], warnings = [], marks = {};
    const mark = (key, level, msg) => {
      (level === 'error' ? errors : warnings).push({ key, msg });
      const m = marks[key] || (marks[key] = { level: 'warn', msgs: [] });
      if (level === 'error') m.level = 'error';
      m.msgs.push(msg);
    };
    for (const rule of table[kind] || []) {
      let hit = false;
      try { hit = !!rule.when(doc || {}, c); } catch (e) { mark(rule.key || '?', 'warn', `rule "${rule.key}" failed: ${e.message}`); continue; }
      if (!hit) continue;
      let msg = '';
      try { msg = typeof rule.msg === 'function' ? rule.msg(doc || {}, c) : String(rule.msg || rule.key); } catch (e) { msg = String(rule.key); }
      mark(rule.key, rule.level === 'error' ? 'error' : 'warn', msg);
    }
    return { errors, warnings, marks };
  }

  // ------------------------------------------------------------------ pass 70 (lane LE): the Bandit check

  /** A look's `stills` is the short name its paintings are cached under (<id>_<slug>_<view>), never a picture's path
   *  (vocab.py STILLS_RE / STILLS_HELP / stills_problem, gen_edit_stills.SLUG_RE: the same rule). '' is allowed. */
  const STILLS_RE = /^[A-Za-z0-9_]{0,40}$/;
  const STILLS_HELP = "Stills is a short name for this look's paintings, like bdb; the picture goes in Reference";
  /** '' when `v` is a slug or empty (or absent), else the plain message to show. */
  function stillsProblem(v) {
    if (v == null) return '';
    if (typeof v !== 'string' || !STILLS_RE.test(v)) return `${STILLS_HELP} (letters, digits and _ only; got ${JSON.stringify(v)})`;
    return '';
  }
  /** [[where, message]] for every `stills` of a creature or hero document that is not a slug (vocab.bad_stills). */
  function badStills(d) {
    const out = [];
    if (!isObj(d)) return out;
    const p = stillsProblem(d.stills);
    if (p) out.push(['stills', p]);
    const vs = isObj(d.variants) ? d.variants : {};
    for (const code of Object.keys(vs)) {
      const r = isObj(vs[code]) && isObj(vs[code].recipe) ? vs[code].recipe : {};
      const q = stillsProblem(r.stills);
      if (q) out.push([`variants.${code}.recipe.stills`, q]);
    }
    return out;
  }

  const api = {
    STILLS_RE, STILLS_HELP, stillsProblem, badStills,   // pass 70
    ENEMY_ORDER, CHAR_ORDER, ENEMY_SUFFIX, HERO_SUFFIX, HERO_FALLBACK, ID_RE, HEX_RE,
    PLAYER_DEFAULTS, PLAYER_EXTRA, STAT_FLOORS, STATS, WEAPON_DEFAULTS, WEAPON_EXTRA, PREFIX, HERO_WORDS, HERO_NOTES, HERO_LOWER,
    isObj, num, isNum, order, frameOffset, offsets, totalFrames, cell, rows, directions, animKey, mirror, previewFps,
    prefixOf, suffixAt, usedSuffixes, nextCodes, codeFiles, slugOk, slugify,
    STAT_HELP, statHelp,
    plain, signed, statName, statKind, formatValue, describeEffect, describeEffects, heroWord, possessive, heroAmount, heroCapped, heroStep, heroTrait, heroOwnWords, heroTraitAt, heroTraitNow,
    defaultKnockback, BLOCK_NAMES, NATURAL, naturalBlocks, blocksOf, combo, comboWords, enemyRecord, VOLLEY_START, VOLLEY_HIT, volleyReach, telegraphGeometry, attackActive, paceOf, attackSequence, revolverTTK, hitsToKill,
    availabilityOf, questFor, bandOf, pathOf, levelsSummary, issues,
    BAND, questText,   // pass 69
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  return api;
})();
