'use strict';
// Pass 72 (lane BOSS): the page-free maths of the boss HP scaling and the custom boss attacks, mirrored from the game
// (game/core/data/WaveTimeline.gd boss_hp_mult, game/core/data/BossAttackDef.gd DEFAULTS / points / land_times,
// game/core/systems/WaveDirector.gd boss_dps_scale). The Settings card (boss_scaling.js) and the Boss attacks tab
// (boss_attacks.js) draw from it; selftest_BOSS.py runs it under Node and checks it against the GDScript tables.
const BossModel = (() => {
  const TAU = Math.PI * 2;

  // ------------------------------------------------------------------ boss HP pegged to the hero's DPS

  /** WaveTimeline.BOSS_HP_SCALING_DEFAULTS: what a key the block leaves out plays (pass 72, lane INTEG: on, so a map
   *  saved without the block still pegs its bosses). */
  const SCALING_DEFAULTS = { enabled: true, exponent: 0.5, window: 45, min: 0.75, max: 3.0 };
  /** WaveTimeline.BOSS_REF_DPS_DEFAULTS: a boss's reference DPS when ref_dps leaves it out (lane BOSS's measurements). */
  const REF_DEFAULTS = { tumbleweed_king: 600, gila_grande: 4500, brander: 20000 };

  const num = (v, d) => (typeof v === 'number' && isFinite(v) ? v : (v != null && v !== '' && isFinite(Number(v)) ? Number(v) : d));
  const isObj = (x) => x != null && typeof x === 'object' && !Array.isArray(x);
  const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

  /** The block with every default filled in. */
  function scalingOf(tl) {
    const b = isObj(tl && tl.boss_hp_scaling) ? tl.boss_hp_scaling : {};
    return {
      present: isObj(tl && tl.boss_hp_scaling) && Object.keys(tl.boss_hp_scaling).length > 0,
      enabled: b.enabled != null ? !!b.enabled : SCALING_DEFAULTS.enabled,
      exponent: num(b.exponent, SCALING_DEFAULTS.exponent),
      window: num(b.window, SCALING_DEFAULTS.window),
      min: num(b.min, SCALING_DEFAULTS.min),
      max: Math.max(num(b.max, SCALING_DEFAULTS.max), num(b.min, SCALING_DEFAULTS.min)),
      // a boss the block names takes its number (0 = never scaled), any other its measured default (WaveTimeline.boss_ref_dps)
      ref: Object.assign({}, REF_DEFAULTS, isObj(b.ref_dps) ? b.ref_dps : {}),
    };
  }

  /** WaveTimeline.boss_hp_mult: (dps / ref) ^ exponent held between min and max; 1 when off or without a reference. */
  function hpMult(cfg, dps, ref) {
    if (!cfg || !cfg.enabled || !(ref > 0)) return 1;
    const lo = cfg.min, hi = Math.max(cfg.max, lo);
    return clamp(Math.pow(Math.max(dps, 0) / ref, cfg.exponent), lo, hi);
  }

  // pass 83 (lane SCALE; Garry: "at least 25 seconds of Player's FULL DPS on Tumbleweed king ... 40s for the next and a
  // full minute to the last one"): WaveTimeline.BOSS_HP_MODE_DEFAULT, BOSS_SECONDS_DEFAULTS, boss_seconds_hp
  const MODE_DEFAULT = 'seconds';
  const SECONDS_DEFAULTS = { tumbleweed_king: 25, gila_grande: 40, brander: 60 };
  /** The full DPS on a boss of the probe's tuned builds when it arrives (game/tools/_p83_SCALE_boss_probe.gd, pass 83:
   *  Calavera and the Drifter on difficulty_probe's b1 / b2 / b3): the "a typical build" mark on the seconds chart. */
  const TYPICAL_FULL_DPS = { tumbleweed_king: 170, gila_grande: 500, brander: 2000 };

  /** The mode the block plays: 'seconds' or 'dps' (WaveTimeline.boss_hp_mode). */
  function modeOf(tl) {
    const b = isObj(tl && tl.boss_hp_scaling) ? tl.boss_hp_scaling : {};
    return b.mode === 'seconds' || b.mode === 'dps' ? b.mode : MODE_DEFAULT;
  }

  /** Every boss's seconds (the map's, else SECONDS_DEFAULTS'; WaveTimeline.boss_seconds). */
  function secondsOf(tl) {
    const b = isObj(tl && tl.boss_hp_scaling) ? tl.boss_hp_scaling : {};
    return Object.assign({}, SECONDS_DEFAULTS, isObj(b.seconds) ? b.seconds : {});
  }

  /** WaveTimeline.boss_seconds_hp: max(the data HP, full DPS x seconds x (1 - damage reduction)); the data HP when the
   *  seconds or the DPS is 0. */
  function secondsHp(base, fullDps, seconds, dr) {
    if (!(seconds > 0) || !(fullDps > 0)) return base;
    return Math.max(base, fullDps * (1 - clamp(dr || 0, 0, 0.95)) * seconds);
  }

  /** The DPS at which full DPS x seconds passes the data HP (below it the boss keeps its data HP). */
  const secondsCross = (base, seconds) => (seconds > 0 ? base / seconds : Infinity);

  /** The DPS at which the multiplier reaches `m` (the clamp's corners on the chart). */
  function dpsForMult(cfg, ref, m) {
    if (!(cfg.exponent > 0)) return ref;
    return ref * Math.pow(m, 1 / cfg.exponent);
  }

  /** The boss events of a timeline in time order: [{id, t, stage}] (the stage the event closes, 0-based). */
  function bossEvents(tl) {
    const L = Math.max(num(tl && tl.stage_length, 300), 1);
    const out = [];
    for (const ev of (tl && Array.isArray(tl.events) ? tl.events : [])) {
      if (!isObj(ev) || ev.type !== 'boss') continue;
      const ids = Array.isArray(ev.enemy) ? ev.enemy : [ev.enemy];
      for (const id of ids) if (id && !out.some((o) => o.id === id)) out.push({ id: String(id), t: num(ev.t, 0), stage: Math.max(Math.ceil(num(ev.t, 0) / L) - 1, 0) });
    }
    return out.sort((a, b) => a.t - b.t);
  }

  /** The timeline's stage multiplier for stage index `s` (the last for later ones). */
  function stageMult(tl, s) {
    const sm = Array.isArray(tl && tl.stage_mults) && tl.stage_mults.length ? tl.stage_mults : [1];
    return num(sm[Math.min(Math.max(s, 0), sm.length - 1)], 1);
  }

  /** A boss's HP before the scaling, as EnemyManager.spawn gives it: hp x hp_mult_per_stage^stage x max(stage mult, 1). */
  function bossBaseHp(boss, tl, stage) {
    if (!boss) return 0;
    const hpm = num(isObj(boss.boss) ? boss.boss.hp_mult_per_stage : null, 1.6);
    return num(boss.hp, 0) * Math.pow(hpm, stage) * Math.max(stageMult(tl, stage), 1);
  }

  /** The chart's curves for one boss, on a log DPS axis from ref / 2^lo to ref x 2^hi: the multiplier, and the fight's
   *  length against the fight at the reference (1 = as long as there, 0.71 = 29% shorter) with the scaling and without
   *  (only the boss's share of the DPS is unknown here, so the length is relative: the same share at every DPS). */
  function chartSeries(cfg, ref, lo, hi, n) {
    const N = n || 160;
    const pts = [];
    for (let k = 0; k <= N; k++) {
      const e = -lo + (lo + hi) * k / N;
      const dps = ref * Math.pow(2, e);
      const m = hpMult(cfg, dps, ref);
      pts.push({ e, dps, mult: m, fight: m * ref / dps, fightPlain: ref / dps });
    }
    return pts;
  }

  /** The fight's length at `dps` against the fight at the reference (the boss's HP x its multiplier over the DPS). */
  const fightRel = (cfg, dps, ref) => (dps > 0 && ref > 0 ? hpMult(cfg, dps, ref) * ref / dps : Infinity);

  // ------------------------------------------------------------------ custom boss attacks

  // BossAttackDef's tables (selftest_BOSS.py reads them out of the GDScript and checks they agree)
  const KINDS = ['rain', 'volley', 'ring', 'slam', 'script', 'pattern'];
  const SHAPES = ['rings', 'grid', 'spiral', 'random'];
  const LOOKS = ['spike', 'spit', 'pellet', 'shard', 'rock', 'fire', 'burning_tumbleweed', 'venom_blob', 'brand_fireball'];
  // pass 113 (lane BOSS): a bullet-heaven pattern's emitter shapes and aims, the boss's wind-up looks, his shells
  // (BossAttackDef.EMITTER_SHAPES, EMITTER_AIMS, TELL_LOOKS, SHELLS; selftest_BOSS113.py checks them)
  const EMITTER_SHAPES = ['spiral', 'ring', 'fan', 'sweep', 'wall', 'rose'];
  const EMITTER_AIMS = ['hero', 'track', 'fixed', 'random'];
  const TELL_LOOKS = ['none', 'spin', 'rear', 'drive'];
  const SHELLS = ['none', 'tornado', 'scales', 'pillar'];
  // pass 115 (lane BOSS): a pattern's barrier (BossAttackDef.BARRIER_LOOKS, BARRIER_MODES, BARRIER_HOLDS,
  // BARRIER_CREATURES, BARRIER_BULLETS; the hero's body and the reach rule's room BARRIER_HERO_R, BARRIER_KEEP, the
  // smallest wall BARRIER_MIN_R; selftest_BOSS115.py checks them)
  const BARRIER_LOOKS = ['none', 'tumbleweed_fence', 'cactus_fence', 'iron_fence'];
  const BARRIER_MODES = ['range', 'fixed'];
  const BARRIER_HOLDS = ['bullets', 'spent'];
  const BARRIER_CREATURES = ['block', 'pass'];
  const BARRIER_BULLETS = ['stop', 'pass'];
  const BARRIER_HERO_R = 0.45;
  const BARRIER_KEEP = 0.5;
  const BARRIER_MIN_R = 3.0;
  /** BossAttackFx.BB_RADIUS: a bullet-heaven look's body radius (m) at size 1. */
  const BB_RADIUS = { burning_tumbleweed: 0.34, venom_blob: 0.5, brand_fireball: 0.4 };
  const ORDERS = ['out', 'in', 'random', 'sweep'];
  const AIMS = ['hero', 'random', 'fixed'];
  const CENTERS = ['boss', 'hero'];
  const TELEGRAPHS = ['circles', 'lines', 'ring', 'none'];
  // pass 73 (lane GROUND): a rain's landing, BossAttackDef.LANDING_MODES
  const LANDING_MODES = ['stagger', 'volley'];
  const SCRIPTS = ['roll', 'spawn_ring', 'slam_at', 'blink', 'burrow', 'rain', 'erupt', 'spit_volley', 'slam', 'rumble',
    'brand', 'tumbleweed_volley', 'swoop', 'boulder', 'stomp', 'tail_sniper'];
  const DEFAULTS = {
    projectile: { look: 'spike', tint: '#D0242F', size: 1.0, glow: 1.0, flight: 1.0, arc: 6.0, speed: 12.0, range: 18.0, hit_radius: 0.5, trail: true, wobble: 0.0 },
    pattern: { shape: 'rings', center: 'boss', radius_min: 3.0, radius_max: 16.0, spacing: 3.2, count: 0, jitter: 0.2, gap: 1.0, turn: true, order: 'out', spread_deg: 360.0, aim: 'hero', waves: 1, wave_gap: 0.5, width: 1.2 },
    landing: { radius: 0.9, mode: 'stagger' },
    telegraph: { kind: 'circles', color: '#ED4A5C', seconds: 0.9, all_at_once: false },
    timing: { windup: 1.0, stagger: 1.5, cooldown: 0.0, hold: -1.0, duration: 8.0, clear: 0.6 },
    sounds: { windup: '', fire: 'en_boss_attack', land: '' },
    spew: { crouch: 0.35, burst: 0.12, mouth: 0.62, squash: 0.82, stretch: 1.25 },
    // pass 113 (lane BOSS): a bullet-heaven pattern's groups
    hit: { hit_frac: 0.12 },
    trigger: { first_after: 15.0, first_at_hp: 0.6, first_by: 45.0, cooldown: 45.0 },
    guard: { share: 0.8, color: '#B9C3CE' },
    spent: { seconds: 2.5, damage_taken: 1.5, still: true },
    tell: { seconds: 2.0, banner: '', banner_color: '#E8502A', ring_radius: 9.0, ring_color: '#140A06', ring_alpha: 0.5, duck_db: -14.0, look: 'none' },
    shell: { look: 'none', color: '#C9A46A', height: 7.0, radius: 3.0, opacity: 0.94, sigil_radius: 0.0, sigil_color: '#FF6A1A' },
    // pass 115 (lane BOSS): a pattern's barrier (BossAttackDef.DEFAULTS.barrier; selftest_BOSS115.py checks it)
    barrier: { look: 'none', radius_mode: 'range', radius: 16.0, inset: 1.0, height: 1.8, thickness: 0.8, rise_s: 0.8, spread_s: 0.6, fall_s: 1.0, hold: 'bullets', color: '#FFFFFF', glow_color: '#FF8A1F', hero_block: true, creatures: 'block', bullets: 'stop' },
  };
  /** BossAttackDef.EMITTER_DEFAULTS: one emitter of a pattern, every key it leaves out. */
  const EMITTER_DEFAULTS = {
    shape: 'spiral', count: 1, arms: 1, speed: 3.0, rate: 4.0, spin: 0.0, reverse_at: -1.0, spread_deg: 60.0, sweep_deg: 0.0, sweep_hz: 0.0,
    gap: 0.0, petals: 5, depth: 0.7, bloom_hz: 0.0, turn_every: 0.0, turn_deg: 0.0, offset_deg: 0.0, aim: 'hero', start: 0.0, stop: 1.0,
    pulse_every: 0.0, pulse_on: 0.0, pulse_at: 0.0, finale_pull: 0.0, pull_speed: 7.0, width: 12.0,
  };
  const TOP_DEFAULTS = { damage: 0.75, knockback: 4.0, lift: 0.0 };
  /** The Player's body radius (Player.RADIUS), for the preview's hero. */
  const HERO_RADIUS = 0.45;

  /** A key of a group with the game's default. */
  function val(a, group, key) {
    const g = a && isObj(a[group]) ? a[group] : {};
    return key in g ? g[key] : DEFAULTS[group][key];
  }
  function patternFull(a) { return Object.assign({}, DEFAULTS.pattern, isObj(a && a.pattern) ? a.pattern : {}); }
  function topVal(a, key) { return a && a[key] != null && a[key] !== '' ? num(a[key], TOP_DEFAULTS[key]) : TOP_DEFAULTS[key]; }

  /** A seeded random (mulberry32) with Godot's randf / randf_range names. */
  function rng(seed) {
    let s = (seed >>> 0) || 1;
    const randf = () => {
      s = (s + 0x6D2B79F5) >>> 0;
      let t = s;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
    return { randf, randfRange: (a, b) => a + (b - a) * randf() };
  }

  /** BossAttackDef.points: a rain's landing points (offsets [x, z] round its centre) by its shape, the jitter that never
   *  closes two layout neighbours past the rule, a random turn, the landing order, then THE GAP RULE (a point closer than
   *  2 x landR + gap to one kept is dropped) and the count. Same rules as the game; the random numbers are the page's own,
   *  so a layout is an example of the game's, never the same one. */
  function points(pat0, landR, R) {
    const pat = Object.assign({}, DEFAULTS.pattern, pat0 || {});
    let spacing = Math.max(num(pat.spacing, 3.2), 0.3);
    const gap = Math.max(num(pat.gap, 1), 0);
    const dmin = 2 * Math.max(landR, 0) + gap;
    spacing = Math.max(spacing, dmin);
    const rmin = Math.max(num(pat.radius_min, 3), 0);
    const rmax = Math.max(num(pat.radius_max, 16), rmin);
    const jit = Math.min(clamp(num(pat.jitter, 0.2), 0, 1) * spacing * 0.5, Math.max(spacing - dmin, 0) * 0.5);
    const turn = pat.turn !== false ? R.randf() * TAU : 0;
    const rot = (x, y, a) => [x * Math.cos(a) - y * Math.sin(a), x * Math.sin(a) + y * Math.cos(a)];
    const len = (p) => Math.hypot(p[0], p[1]);
    let raw = [];
    const shape = String(pat.shape || 'rings');
    if (shape === 'grid') {
      const dy = spacing * 0.8660254;
      const rows = Math.ceil(rmax / dy) + 1;
      for (let ry = -rows; ry <= rows; ry++) {
        const y = ry * dy;
        const off = Math.abs(ry) % 2 === 1 ? spacing * 0.5 : 0;
        const cols = Math.ceil(rmax / spacing) + 1;
        for (let cx = -cols; cx <= cols; cx++) {
          const p = [cx * spacing + off, y];
          const l = len(p);
          if (l >= rmin - 0.001 && l <= rmax + 0.001) raw.push(rot(p[0], p[1], turn));
        }
      }
    } else if (shape === 'spiral') {
      const c = spacing * Math.sqrt(0.8660254 / Math.PI);
      let n = Math.floor(Math.pow(rmin / c, 2));
      const golden = Math.PI * (3 - Math.sqrt(5));
      for (let guard = 0; guard < 4000; guard++) {
        const r = c * Math.sqrt(n + 0.5);
        if (r > rmax) break;
        if (r >= rmin) raw.push([Math.cos(n * golden + turn) * r, Math.sin(n * golden + turn) * r]);
        n++;
      }
    } else if (shape === 'random') {
      const want = Math.floor((Math.PI * (rmax * rmax - rmin * rmin)) / (0.8660254 * spacing * spacing)) + 1;
      let tries = want * 30;
      const keepD = Math.max(spacing * 0.9, dmin);
      while (tries > 0 && raw.length < want) {
        tries--;
        const a = R.randf() * TAU;
        const r = Math.sqrt(R.randfRange(rmin * rmin, rmax * rmax));
        const p = [Math.cos(a) * r, Math.sin(a) * r];
        if (raw.every((q) => Math.hypot(p[0] - q[0], p[1] - q[1]) >= keepD)) raw.push(p);
      }
    } else {
      const step = Math.max(spacing * 0.87, dmin + 2 * jit);
      let r = rmin;
      let k = 0;
      if (r < 0.001) { raw.push([0, 0]); r = step; k = 1; }
      while (r <= rmax + 0.001) {
        const n = Math.max(Math.floor(TAU * r / spacing), 1);
        const off = k % 2 === 1 ? 0.5 * TAU / n : 0;
        for (let j = 0; j < n; j++) { const a = off + TAU * j / n + turn; raw.push([Math.cos(a) * r, Math.sin(a) * r]); }
        r += step;
        k++;
      }
    }
    if (jit > 0) raw = raw.map((p) => { const a = R.randf() * TAU; const d = R.randf() * jit; return [p[0] + Math.cos(a) * d, p[1] + Math.sin(a) * d]; });
    const order = String(pat.order || 'out');
    const keyed = raw.map((p) => {
      let key;
      if (order === 'in') key = -len(p);
      else if (order === 'random') key = R.randf();
      else if (order === 'sweep') key = ((Math.atan2(p[1], p[0]) - turn) % TAU + TAU) % TAU;
      else key = len(p);
      return [key, p];
    });
    keyed.sort((a, b) => a[0] - b[0]);
    const out = [];
    const cap = Math.round(num(pat.count, 0));
    for (const [, p] of keyed) {
      if (out.some((q) => Math.hypot(p[0] - q[0], p[1] - q[1]) < dmin - 0.0001)) continue;
      out.push(p);
      if (cap > 0 && out.length >= cap) break;
    }
    return out;
  }

  function smallestGap(pts, landR) {
    let best = Infinity;
    for (let a = 0; a < pts.length; a++) for (let b = a + 1; b < pts.length; b++) best = Math.min(best, Math.hypot(pts[a][0] - pts[b][0], pts[a][1] - pts[b][1]) - 2 * landR);
    return best;
  }

  /** BossAttackDef.land_times: the k-th spot lands after its flight plus its share of the stagger. */
  function landTimes(n, stagger, flight) {
    const out = [];
    for (let k = 0; k < n; k++) out.push(Math.max(flight, 0.05) + (n > 1 ? Math.max(stagger, 0) * k / Math.max(n - 1, 1) : 0));
    return out;
  }

  /** Pass 73 (lane GROUND): a rain that throws every shot in one spew from the boss's mouth (landing.mode "volley"). */
  const isVolley = (a) => String((a && a.kind) || 'rain') === 'rain' && String(val(a, 'landing', 'mode')) === 'volley';
  /** ... that lights every landing circle at once before the spew (telegraph.all_at_once). */
  const litAtOnce = (a) => String((a && a.kind) || 'rain') === 'rain' && val(a, 'telegraph', 'all_at_once') === true && val(a, 'telegraph', 'kind') !== 'none';
  /** BossAttackDef.windup_seconds: timing.windup, or for a rain lit all at once at least telegraph.seconds. */
  function windupSeconds(a) {
    let w = Math.max(num(val(a, 'timing', 'windup'), 1), 0);
    if (String((a && a.kind) || 'rain') === 'rain' && val(a, 'telegraph', 'all_at_once') === true) w = Math.max(w, Math.max(num(val(a, 'telegraph', 'seconds'), 0.9), 0));
    return w;
  }

  /** BossAttackDef.volley_times: every shot leaves within `burst` of the spew and flies `flight` to the nearest spot, up
   *  to `stagger - burst` longer to the farthest, so all land within `stagger` of each other. {dep, land} per point. */
  function volleyTimes(pts, flight, stagger, burst, R) {
    const fl = Math.max(flight, 0.05), st = Math.max(stagger, 0), b = clamp(burst, 0, st);
    const ds = pts.map((p) => Math.hypot(p[0], p[1]));
    const lo = ds.length ? Math.min(...ds) : 0, hi = ds.length ? Math.max(...ds) : 0;
    const dep = [], land = [];
    for (let k = 0; k < pts.length; k++) {
      const dn = hi - lo > 0.001 ? (ds[k] - lo) / (hi - lo) : 0;
      dep.push(b * R.randf());
      land.push(dep[k] + fl + (st - b) * dn);
    }
    return { dep, land };
  }

  /** A rain's example layout and its numbers: spots, landing times and each shot's flight, smallest gap, the share of
   *  the area its circles cover, how long the rain lasts after it fires (pass 73: a volley's times by volleyTimes). */
  function rainLayout(a, seed) {
    const lr = Math.max(num(val(a, 'landing', 'radius'), 0.9), 0);
    const R = rng(seed == null ? 1 : seed);
    const pts = points(patternFull(a), lr, R);
    const flight = Math.max(num(val(a, 'projectile', 'flight'), 1), 0.1);
    const stagger = num(val(a, 'timing', 'stagger'), 1.5);
    let times, flights;
    if (isVolley(a)) {
      const vt = volleyTimes(pts, flight, stagger, num(val(a, 'spew', 'burst'), 0.12), R);
      times = vt.land;
      flights = vt.land.map((l, k) => l - vt.dep[k]);
    } else {
      times = landTimes(pts.length, stagger, flight);
      flights = times.map(() => flight);
    }
    const pat = patternFull(a);
    const rmin = Math.max(num(pat.radius_min, 3), 0), rmax = Math.max(num(pat.radius_max, 16), rmin);
    const area = Math.PI * (rmax * rmax - rmin * rmin);
    return {
      pts, times, flights, landR: lr, flight, stagger, rmin, rmax,
      gap: smallestGap(pts, lr),
      cover: area > 0 ? pts.length * Math.PI * lr * lr / area : 0,
      lasts: times.length ? Math.max(...times) : flight,
      first: times.length ? Math.min(...times) : flight,
    };
  }

  /** The directions of a volley (radians) round `aim`: `count` over `spread_deg` (all round at 360). */
  function volleyDirs(a, aim) {
    const pat = patternFull(a);
    const n = Math.max(Math.round(num(pat.count, 1)), 1);
    const spread = clamp(num(pat.spread_deg, 360), 0, 360) * Math.PI / 180;
    const out = [];
    for (let k = 0; k < n; k++) out.push(spread >= TAU - 0.001 ? aim + TAU * k / n : aim - spread / 2 + spread * k / Math.max(n - 1, 1));
    return out;
  }

  /** EnemyManager.custom_ring_front: a ring's radius at `f` (0..1) of its race. */
  const ringFront = (rmax, f) => rmax * (1 - Math.pow(1 - clamp(f, 0, 1), 3));

  /** What one hit takes, from the boss's bite (its JSON damage) and the factors given (stage x level x hostile). */
  const hitDamage = (a, bite, factors) => topVal(a, 'damage') * num(bite, 0) * (factors == null ? 1 : factors);

  // ------------------------------------------------------------------ pass 113 (lane BOSS): the bullet-heaven pattern
  // BossAttackDef's emitter maths, line for line (the gdUnit test pass113_BOSS_test and selftest_BOSS113.py pin the same
  // fixed emitters' numbers in both).

  const fposmod = (a, b) => ((a % b) + b) % b;
  const deg2rad = (d) => d * Math.PI / 180;
  /** BossAttackDef.emitter_full. */
  const emitterFull = (e) => Object.assign({}, EMITTER_DEFAULTS, isObj(e) ? e : {});
  /** The pattern's emitters, each full (entries that are not objects left out). */
  const emittersFull = (a) => (a && Array.isArray(a.emitters) ? a.emitters : []).filter(isObj).map(emitterFull);
  const patternDuration = (a) => Math.max(num(val(a, 'timing', 'duration'), 8), 0.5);
  /** BossAttackDef.pulling: the last finale_pull seconds of dur. */
  function pulling(e, t, dur) {
    const fp = num(e.finale_pull, 0);
    return fp > 0 && t >= dur - fp && t < dur;
  }
  /** BossAttackDef.emitter_on. */
  function emitterOn(e, t, dur) {
    if (t < num(e.start, 0) * dur || t >= num(e.stop, 1) * dur) return false;
    if (pulling(e, t, dur)) return false;
    const every = num(e.pulse_every, 0);
    if (every > 0) {
      const at = num(e.pulse_at, 0);
      if (t < at || fposmod(t - at, every) >= num(e.pulse_on, 0)) return false;
    }
    return true;
  }
  /** BossAttackDef.emitter_turned (degrees). */
  function emitterTurned(e, t, dur) {
    const spin = num(e.spin, 0);
    let deg = spin * t;
    const ra = num(e.reverse_at, -1);
    if (ra >= 0 && t > ra * dur) { const tr = ra * dur; deg = spin * tr - spin * (t - tr); }
    const te = num(e.turn_every, 0);
    if (te > 0) deg += Math.floor(t / te) * num(e.turn_deg, 0);
    return deg;
  }
  /** BossAttackDef.emitter_angle (radians). */
  function emitterAngle(e, t, dur, aim) {
    let deg = num(e.offset_deg, 0) + emitterTurned(e, t, dur);
    if (String(e.shape) === 'sweep') deg += num(e.sweep_deg, 0) * 0.5 * Math.sin(TAU * num(e.sweep_hz, 0) * t);
    return aim + deg2rad(deg);
  }
  /** BossAttackDef.rose_depth. */
  function roseDepth(e, t) {
    let depth = clamp(num(e.depth, 0.7), 0, 1);
    const bh = num(e.bloom_hz, 0);
    if (bh > 0) depth *= 0.5 + 0.5 * Math.cos(TAU * bh * t);
    return depth;
  }
  /** BossAttackDef.volley: [[angle, speed, across], ...]. */
  function volley(e, t, dur, aim, hole) {
    const out = [];
    const a = emitterAngle(e, t, dur, aim);
    const n = Math.max(Math.trunc(num(e.count, 1)), 1);
    const spd = Math.max(num(e.speed, 3), 0.1);
    const shape = String(e.shape);
    if (shape === 'ring') {
      const gap = deg2rad(clamp(num(e.gap, 0), 0, 359));
      for (let k = 0; k < n; k++) out.push([gap > 0 ? a + gap * 0.5 + (TAU - gap) * (k + 0.5) / n : a + TAU * k / n, spd, 0]);
    } else if (shape === 'rose') {
      const petals = Math.max(num(e.petals, 5), 1);
      const depth = roseDepth(e, t);
      for (let k = 0; k < n; k++) { const phi = TAU * k / n; const petal = 0.5 + 0.5 * Math.cos(petals * phi); out.push([a + phi, spd * (1 - depth + depth * petal), 0]); }
    } else if (shape === 'wall') {
      const w = Math.max(num(e.width, 12), 0);
      const opening = Math.max(num(e.gap, 0), 0);
      const at = (clamp(hole == null ? 0.5 : hole, 0, 1) - 0.5) * Math.max(w - opening, 0);
      for (let k = 0; k < n; k++) {
        const across = n > 1 ? -w * 0.5 + w * k / (n - 1) : 0;
        if (opening > 0 && Math.abs(across - at) < opening * 0.5) continue;
        out.push([a, spd, across]);
      }
    } else {
      const arms = Math.max(Math.trunc(num(e.arms, 1)), 1);
      const spread = deg2rad(clamp(num(e.spread_deg, 60), 0, 360));
      for (let arm = 0; arm < arms; arm++) {
        const ac = a + TAU * arm / arms;
        for (let k = 0; k < n; k++) {
          let ak = ac;
          if (n > 1) ak = spread >= TAU - 0.001 ? ac + TAU * k / n : ac - spread * 0.5 + spread * k / (n - 1);
          out.push([ak, spd, 0]);
        }
      }
    }
    return out;
  }
  /** BossAttackDef.emitter_volley_times: when the emitter fires over dur, stepped at dt (the game's runner's way). */
  function emitterVolleyTimes(e, dur, dt) {
    const out = [];
    const rate = Math.max(num(e.rate, 4), 0);
    const step = Math.max(dt || 1 / 60, 0.001);
    let acc = 0, was = false;
    for (let i = 0; i * step < dur; i++) {
      const t = i * step;
      const on = rate > 0 && emitterOn(e, t, dur);
      if (on) { acc = was ? acc + step * rate : 1; while (acc >= 1) { acc -= 1; out.push(t); } }
      was = on;
    }
    return out;
  }
  /** BossAttackDef.simulate: the pattern played out without a hero: {peak, peak_t, fired, volleys}; with `at` (seconds after
   *  the bullets begin) also the bullets in the air then, [{x, z, k (its emitter), pull}], for the preview; `aimOf(e, k, t)`
   *  gives an emitter's aim (radians; 0 = +x, the game's 'fixed'). */
  // pass 115 (lane BOSS): the barrier (BossAttackDef.barrier_on, barrier_radius, barrier_half, barrier_hero_limit,
  // barrier_reach, barrier_stops_bullets, bullet_reach; selftest_BOSS115.py checks them against the game)
  function barrierOn(a) {
    if (!a || a.kind !== 'pattern') return false;
    const lk = String(val(a, 'barrier', 'look'));
    return lk !== 'none' && BARRIER_LOOKS.includes(lk);
  }
  const barrierHalf = (a) => Math.max(num(val(a, 'barrier', 'thickness'), 0.8), 0.2) * 0.5;
  function barrierRadius(a) {
    const r = String(val(a, 'barrier', 'radius_mode')) === 'fixed'
      ? num(val(a, 'barrier', 'radius'), 16)
      : Math.max(num(val(a, 'projectile', 'range'), 18), 0.5) - Math.max(num(val(a, 'barrier', 'inset'), 1), 0);
    return Math.max(r, BARRIER_MIN_R + barrierHalf(a));
  }
  const barrierHeroLimit = (a) => barrierRadius(a) - barrierHalf(a) - BARRIER_HERO_R;
  /** THE REACH RULE: how near the boss the hero must be for the pattern to begin (Infinity without a barrier). */
  function barrierReach(a) {
    if (!barrierOn(a)) return Infinity;
    return Math.min(Math.max(num(val(a, 'projectile', 'range'), 18), 0.5), barrierHeroLimit(a) - BARRIER_KEEP);
  }
  const barrierStopsBullets = (a) => barrierOn(a) && String(val(a, 'barrier', 'bullets')) !== 'pass';
  /** How far a bullet flies before it is gone: the range, or the wall's inner face when nearer and it stops bullets. */
  function bulletReach(a) {
    let r = Math.max(num(val(a, 'projectile', 'range'), 18), 0.5);
    if (barrierStopsBullets(a)) r = Math.min(r, barrierRadius(a) - barrierHalf(a));
    return r;
  }

  function simulate(a, dt, at, aimOf) {
    const step = dt || 1 / 30;
    const dur = patternDuration(a);
    // (pass 115: a barrier that stops the bullets ends their flight at its inner face: bulletReach)
    const rng = bulletReach(a);
    const ems = emittersFull(a);
    const accs = ems.map(() => 0), was = ems.map(() => false);
    let live = [];
    let peak = 0, peakT = 0, fired = 0, volleys = 0;
    let shot = null;
    for (let i = 0; i * step < dur; i++) {
      const t = i * step;
      ems.forEach((e, k) => {
        const on = num(e.rate, 4) > 0 && emitterOn(e, t, dur);
        if (on) {
          accs[k] = was[k] ? accs[k] + step * num(e.rate, 4) : 1;
          while (accs[k] >= 1) {
            accs[k] -= 1;
            const aim = aimOf ? aimOf(e, k, t) : 0;
            const v = volley(e, t, dur, aim, 0.5);
            volleys++;
            for (const [ang, spd, across] of v) {
              const dx = Math.cos(ang), dz = Math.sin(ang);
              live.push([-dz * across, dx * across, dx * spd, dz * spd, k]);
              fired++;
            }
          }
        }
        was[k] = on;
      });
      const keep = [];
      for (const b of live) {
        const e = ems[b[4]];
        if (pulling(e, t, dur)) {
          const l = Math.hypot(b[0], b[1]);
          const s = Math.max(num(e.pull_speed, 7), 0.1) * step;
          if (l <= s + 0.5) continue;
          b[0] *= 1 - s / l; b[1] *= 1 - s / l;
        } else { b[0] += b[2] * step; b[1] += b[3] * step; }
        if (Math.hypot(b[0], b[1]) > rng) continue;
        keep.push(b);
      }
      live = keep;
      if (live.length > peak) { peak = live.length; peakT = t; }
      if (at != null && shot == null && t + step > at) shot = live.map((b) => ({ x: b[0], z: b[1], k: b[4], pull: pulling(ems[b[4]], t, dur) }));
    }
    return { peak, peak_t: peakT, fired, volleys, at: shot || [] };
  }
  /** BossAttackDef.pattern_due (pass 114: `rolled` = this fight's rolls; a key it lacks plays its range's low end). */
  function patternDue(a, fightT, hpFrac, runs, lastEnd, rolled) {
    const v = (k) => (rolled && rolled[k] != null ? Number(rolled[k]) : triggerRange(a, k)[0]);
    if (fightT < v('first_after')) return false;
    if (runs <= 0) return hpFrac <= num(val(a, 'trigger', 'first_at_hp'), 0.6) || fightT >= v('first_by');
    return fightT - lastEnd >= v('cooldown');
  }

  // pass 114 (lane EDITOR; Garry: "make it a range between 10 and 15 for example ... the cooldown only starts after
  // those 10 seconds are done"): BossAttackDef.TRIGGER_RANGES, range_of, trigger_range
  const TRIGGER_RANGES = ['first_after', 'first_by', 'cooldown'];
  const isNum = (x) => typeof x === 'number' && isFinite(x);
  /** BossAttackDef.range_of: [low, high] of a number (v, v) or a [min, max] list (sorted, never below 0); a one-number
   *  list is that number; anything else is the default. */
  function rangeOf(v, fallback) {
    if (isNum(v)) { const f = Math.max(v, 0); return [f, f]; }
    if (Array.isArray(v)) {
      if (v.length === 1 && isNum(v[0])) { const g = Math.max(v[0], 0); return [g, g]; }
      if (v.length === 2 && isNum(v[0]) && isNum(v[1])) { const lo = Math.max(v[0], 0), hi = Math.max(v[1], 0); return [Math.min(lo, hi), Math.max(lo, hi)]; }
    }
    const d = Math.max(num(fallback, 0), 0);
    return [d, d];
  }
  function triggerRange(a, key) { return rangeOf(val(a, 'trigger', key), DEFAULTS.trigger[key]); }
  /** What is wrong with a trigger key's value as the file holds it ('' when nothing): boss_attacks_io.py refuses the same. */
  function triggerProblem(key, v) {
    if (v == null) return '';
    if (isNum(v)) return v < 0 ? `${key} is below 0` : '';
    if (Array.isArray(v)) {
      if (v.length !== 2 || !isNum(v[0]) || !isNum(v[1])) return `${key}: a range is two numbers, [min, max]`;
      if (v[0] < 0 || v[1] < 0) return `${key}: the range is below 0`;
      if (v[0] > v[1]) return `${key}: the range's min (${v[0]}) is above its max (${v[1]})`;
      return '';
    }
    return `${key} is a number or a range [min, max]`;
  }
  /** A number to one decimal ("12.5", "48"). */
  const fmt1 = (x) => (Math.round(x * 10) / 10).toString();
  /** "15 s" or "10–15 s". */
  function fmtRange(r) {
    const f = (x) => (Math.round(x * 10) / 10).toString();
    return r[0] === r[1] ? `${f(r[0])} s` : `${f(r[0])}–${f(r[1])} s`;
  }
  /** Pass 114: when the fight's first `n` patterns can start and end, in fight seconds, each [earliest, latest]: the first
   *  at the earliest when he falls under first_at_hp at once (the low end of Not before), at the latest at full HP (the
   *  high end of Not before or of At the latest, whichever is later); each next one the cooldown after the one before
   *  was completely over (its tell, its bullets and his spent seconds). His own attacks can only push one later (it
   *  waits for him to finish one); ×1/pace on the map. [{k, start: [a, b], end: [a, b]}] */
  function patternSchedule(a, n) {
    const fa = triggerRange(a, 'first_after'), fb = triggerRange(a, 'first_by'), cd = triggerRange(a, 'cooldown');
    const lasts = Math.max(num(val(a, 'tell', 'seconds'), 2), 0) + patternDuration(a) + Math.max(num(val(a, 'spent', 'seconds'), 2.5), 0);
    const out = [];
    let s = [fa[0], Math.max(fa[1], fb[1])];
    for (let k = 1; k <= Math.max(1, n || 3); k++) {
      const e = [s[0] + lasts, s[1] + lasts];
      out.push({ k, start: s, end: e });
      s = [e[0] + cd[0], e[1] + cd[1]];
    }
    return out;
  }

  /** The problems of an attack document (errors block a save, warnings do not). */
  function issues(a, ids) {
    const errors = [], warnings = [];
    if (!isObj(a)) return { errors: ['not an object'], warnings };
    if (!/^[a-z][a-z0-9_]*$/.test(String(a.id || ''))) errors.push('the id is lower-case letters, digits and _');
    if (SCRIPTS.includes(String(a.id))) errors.push(`"${a.id}" is a built-in attack's name: pick another id`);
    if (!String(a.name || '').trim()) warnings.push('no name: the list and the hit log show the id');
    const kind = String(a.kind || 'rain');
    if (!KINDS.includes(kind)) errors.push(`unknown kind "${kind}" (${KINDS.join(', ')})`);
    if (kind === 'script') {
      if (!SCRIPTS.includes(String(a.script || ''))) errors.push('a script attack names one of the built-in attacks');
      return { errors, warnings };
    }
    const pat = patternFull(a);
    if (kind === 'rain') {
      if (num(pat.radius_max, 16) <= num(pat.radius_min, 3)) errors.push('the outer radius must be bigger than the inner one');
      const lay = rainLayout(a, 1);
      if (!lay.pts.length) errors.push('no landing spot fits between the radii');
      if (!LANDING_MODES.includes(String(val(a, 'landing', 'mode')))) errors.push(`unknown landing "${val(a, 'landing', 'mode')}" (${LANDING_MODES.join(', ')})`);
      if (!litAtOnce(a) && num(val(a, 'telegraph', 'seconds'), 0.9) > num(val(a, 'projectile', 'flight'), 1) + num(val(a, 'timing', 'stagger'), 1.5)) warnings.push('the circles show before the first spike is even thrown');
      if (isVolley(a) && num(val(a, 'spew', 'burst'), 0.12) > num(val(a, 'timing', 'stagger'), 1.5)) warnings.push('the burst is longer than the stagger: the spikes cannot all land within the stagger');
      if (num(val(a, 'telegraph', 'seconds'), 0.9) < 0.4 && val(a, 'telegraph', 'kind') !== 'none') warnings.push('under 0.4 s of warning: hard to step out of a circle (the hero walks about 3 m a second)');
      if (num(pat.gap, 1) < 2 * HERO_RADIUS) warnings.push(`a gap under ${2 * HERO_RADIUS} m is narrower than the hero`);
      if (lay.pts.length > 200) warnings.push(`${lay.pts.length} spots: heavy on a phone (keep it under 200)`);
    }
    if (kind === 'volley' && num(pat.count, 1) * num(pat.waves, 1) > 120) warnings.push('more than 120 shots');
    if (kind !== 'pattern' && topVal(a, 'damage') <= 0) warnings.push('damage 0: it never hurts');
    for (const c of [val(a, 'projectile', 'tint'), val(a, 'telegraph', 'color')]) if (c && !/^#[0-9a-fA-F]{6}$/.test(String(c))) errors.push(`a colour is #rrggbb: ${c}`);
    // pass 113 (lane BOSS): a bullet-heaven pattern
    if (kind === 'pattern') {
      const ems = emittersFull(a);
      if (!ems.length) errors.push('a pattern needs at least one emitter');
      for (const e of ems) {
        if (!EMITTER_SHAPES.includes(String(e.shape))) errors.push(`unknown emitter shape "${e.shape}" (${EMITTER_SHAPES.join(', ')})`);
        if (!EMITTER_AIMS.includes(String(e.aim))) errors.push(`unknown emitter aim "${e.aim}" (${EMITTER_AIMS.join(', ')})`);
        if (num(e.rate, 4) <= 0) warnings.push(`an emitter (${e.shape}) with rate 0 never fires`);
        if (num(e.speed, 3) > 6) warnings.push(`an emitter flies at ${num(e.speed, 3)} m/s: faster than the hero (about 5 m/s) is hard to weave`);
      }
      if (!Object.keys(BB_RADIUS).includes(String(val(a, 'projectile', 'look')))) warnings.push('a pattern draws one of the bullet looks (burning_tumbleweed, venom_blob, brand_fireball); any other plays the first');
      if (patternDuration(a) < 5) warnings.push('under 5 s of bullets (Garry: "some 5+ seconds during which player is supposed to try and survive")');
      if (num(val(a, 'tell', 'seconds'), 2) < 1.2) warnings.push('a tell under 1.2 s (Garry: "Big foreshadowing")');
      if (num(val(a, 'hit', 'hit_frac'), 0.12) >= 0.34) warnings.push('a bullet takes a third of his HP or more: danger should come from the density, never one-shots');
      // pass 114: each of the three a number or a range [min, max]; the warnings read its low end
      for (const k of TRIGGER_RANGES) { const pr = triggerProblem(k, isObj(a.trigger) ? a.trigger[k] : undefined); if (pr) errors.push(pr); }
      if (triggerRange(a, 'cooldown')[0] < 20) warnings.push('a cooldown under 20 s (Garry: "rare, something like once every 45s")');
      if (triggerRange(a, 'first_after')[0] < 5) warnings.push('first after under 5 s (Garry: "Make it so they don\'t trigger immediately")');
      if (triggerRange(a, 'first_by')[1] < triggerRange(a, 'first_after')[0]) warnings.push('"At the latest" is before "Not before": Not before decides when the first comes');
      if (num(val(a, 'timing', 'clear'), 0.6) > Math.max(num(val(a, 'spent', 'seconds'), 2.5), 0)) warnings.push('the burn-out is longer than the spent seconds: the last bullets vanish at once when he recovers');
      if (!TELL_LOOKS.includes(String(val(a, 'tell', 'look')))) errors.push(`unknown wind-up look "${val(a, 'tell', 'look')}" (${TELL_LOOKS.join(', ')})`);
      if (!SHELLS.includes(String(val(a, 'shell', 'look')))) errors.push(`unknown shell "${val(a, 'shell', 'look')}" (${SHELLS.join(', ')})`);
      for (const c of [val(a, 'guard', 'color'), val(a, 'tell', 'banner_color'), val(a, 'tell', 'ring_color'), val(a, 'shell', 'color'), val(a, 'shell', 'sigil_color')]) if (c && !/^#[0-9a-fA-F]{6}$/.test(String(c))) errors.push(`a colour is #rrggbb: ${c}`);
      // pass 115 (lane BOSS): the barrier
      if (!BARRIER_LOOKS.includes(String(val(a, 'barrier', 'look')))) errors.push(`unknown barrier look "${val(a, 'barrier', 'look')}" (${BARRIER_LOOKS.join(', ')})`);
      if (!BARRIER_MODES.includes(String(val(a, 'barrier', 'radius_mode')))) errors.push(`unknown barrier radius mode "${val(a, 'barrier', 'radius_mode')}" (${BARRIER_MODES.join(', ')})`);
      if (!BARRIER_HOLDS.includes(String(val(a, 'barrier', 'hold')))) errors.push(`unknown barrier hold "${val(a, 'barrier', 'hold')}" (${BARRIER_HOLDS.join(', ')})`);
      if (!BARRIER_CREATURES.includes(String(val(a, 'barrier', 'creatures')))) errors.push(`unknown barrier creatures "${val(a, 'barrier', 'creatures')}" (${BARRIER_CREATURES.join(', ')})`);
      if (!BARRIER_BULLETS.includes(String(val(a, 'barrier', 'bullets')))) errors.push(`unknown barrier bullets "${val(a, 'barrier', 'bullets')}" (${BARRIER_BULLETS.join(', ')})`);
      for (const c of [val(a, 'barrier', 'color'), val(a, 'barrier', 'glow_color')]) if (c && !/^#[0-9a-fA-F]{6}$/.test(String(c))) errors.push(`a colour is #rrggbb: ${c}`);
      if (barrierOn(a)) {
        const rngM = Math.max(num(val(a, 'projectile', 'range'), 18), 0.5);
        if (barrierRadius(a) - barrierHalf(a) > rngM + 0.01) warnings.push(`the barrier stands at ${fmt1(barrierRadius(a))} m, past the bullets' range (${fmt1(rngM)} m): a hero between them is out of reach`);
        if (barrierReach(a) < 6) warnings.push(`the hero must stand within ${fmt1(barrierReach(a))} m of the boss for it to begin: very little room inside the barrier`);
        if (Math.max(num(val(a, 'barrier', 'rise_s'), 0.8), 0) + Math.max(num(val(a, 'barrier', 'spread_s'), 0.6), 0) > Math.max(num(val(a, 'tell', 'seconds'), 2), 0)) warnings.push('the barrier is still rising when the bullets begin (Rise + Spread is longer than the tell)');
        if (!val(a, 'barrier', 'hero_block')) warnings.push("the barrier does not hold the hero: he can walk out of the bullets' reach");
      }
      const sim = simulate(a, 1 / 20);
      // pass 114: 600 (twice as long and twice as far: the King's Royal Dust Devil peaks at about 450; the pattern's tick
      // measured at about 0.3 ms on the PC with 450 in the air, tools/dl/p114/EDITOR)
      if (sim.peak > 600) warnings.push(`${sim.peak} bullets in the air at once: heavy on a phone (keep it under 600)`);
    }
    if (ids && ids.includes(String(a.id)) === false) { /* a new one */ }
    return { errors, warnings };
  }

  /** A new attack of `kind` with the game's defaults spelt out (the Boss attacks tab's "blank" template). */
  function blank(kind, id, name) {
    const k = KINDS.includes(kind) ? kind : 'rain';
    const a = { id, name: name || id, doc: '', kind: k };
    if (k === 'script') return Object.assign(a, { script: 'slam', params: { windup: 1.0, radius: 6.0, damage: 30, knockback: 6, telegraph: 'ring' } });
    // pass 113 (lane BOSS): a bullet-heaven pattern (boss_attacks_io.py blank() makes the same)
    if (k === 'pattern') {
      return Object.assign(a, {
        projectile: { look: 'burning_tumbleweed', tint: '#FF8A1F', size: 1.0, glow: 1.2, range: 16.0, hit_radius: 0.35, trail: true, wobble: 0.0 },
        emitters: [{ shape: 'spiral', arms: 3, count: 1, speed: 3.0, rate: 4.0, spin: 30.0, reverse_at: 0.5, aim: 'hero' }],
        hit: Object.assign({}, DEFAULTS.hit), damage: 0.0, knockback: 0.0, lift: 0.0,
        timing: { duration: 8.0, clear: 0.6, cooldown: 0.0 },
        trigger: Object.assign({}, DEFAULTS.trigger), guard: Object.assign({}, DEFAULTS.guard), spent: Object.assign({}, DEFAULTS.spent),
        tell: Object.assign({}, DEFAULTS.tell), shell: Object.assign({}, DEFAULTS.shell),
        barrier: Object.assign({}, DEFAULTS.barrier),
        sounds: { windup: 'en_boss_pattern_warn', fire: 'en_boss_attack', land: '' },
      });
    }
    a.projectile = Object.assign({}, DEFAULTS.projectile);
    a.pattern = Object.assign({}, DEFAULTS.pattern);
    if (k === 'rain') a.landing = Object.assign({}, DEFAULTS.landing);
    if (k === 'rain') a.spew = Object.assign({}, DEFAULTS.spew);
    a.telegraph = Object.assign({}, DEFAULTS.telegraph, { kind: k === 'rain' ? 'circles' : k === 'volley' ? 'lines' : 'ring' });
    a.damage = TOP_DEFAULTS.damage; a.knockback = TOP_DEFAULTS.knockback; a.lift = TOP_DEFAULTS.lift;
    a.timing = Object.assign({}, DEFAULTS.timing);
    a.sounds = Object.assign({}, DEFAULTS.sounds);
    if (k === 'volley') Object.assign(a.pattern, { count: 12, spread_deg: 360, waves: 2, wave_gap: 0.5 });
    if (k === 'ring') Object.assign(a.pattern, { radius_max: 14, width: 1.2, count: 2, wave_gap: 0.8 });
    if (k === 'slam') Object.assign(a.pattern, { radius_max: 6 });
    return a;
  }

  const api = {
    SCALING_DEFAULTS, REF_DEFAULTS, MODE_DEFAULT, SECONDS_DEFAULTS, TYPICAL_FULL_DPS, modeOf, secondsOf, secondsHp, secondsCross, scalingOf, hpMult, dpsForMult, bossEvents, stageMult, bossBaseHp, chartSeries, fightRel,
    KINDS, SHAPES, LOOKS, ORDERS, AIMS, CENTERS, TELEGRAPHS, SCRIPTS, DEFAULTS, TOP_DEFAULTS, HERO_RADIUS, LANDING_MODES,
    val, patternFull, topVal, rng, points, smallestGap, landTimes, rainLayout, volleyDirs, ringFront, hitDamage, issues, blank, num,
    isVolley, litAtOnce, windupSeconds, volleyTimes,
    EMITTER_SHAPES, EMITTER_AIMS, TELL_LOOKS, SHELLS, EMITTER_DEFAULTS, BB_RADIUS, emitterFull, emittersFull, patternDuration, pulling,
    emitterOn, emitterTurned, emitterAngle, roseDepth, volley, emitterVolleyTimes, simulate, patternDue,
    TRIGGER_RANGES, rangeOf, triggerRange, triggerProblem, fmtRange, patternSchedule,   // pass 114 (lane EDITOR)
    BARRIER_LOOKS, BARRIER_MODES, BARRIER_HOLDS, BARRIER_CREATURES, BARRIER_BULLETS, BARRIER_HERO_R, BARRIER_KEEP, BARRIER_MIN_R,   // pass 115 (lane BOSS)
    barrierOn, barrierRadius, barrierHalf, barrierHeroLimit, barrierReach, barrierStopsBullets, bulletReach,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  return api;
})();
