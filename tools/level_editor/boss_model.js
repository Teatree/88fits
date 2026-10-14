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
  const KINDS = ['rain', 'volley', 'ring', 'slam', 'script'];
  const SHAPES = ['rings', 'grid', 'spiral', 'random'];
  const LOOKS = ['spike', 'spit', 'pellet', 'shard', 'rock', 'fire'];
  const ORDERS = ['out', 'in', 'random', 'sweep'];
  const AIMS = ['hero', 'random', 'fixed'];
  const CENTERS = ['boss', 'hero'];
  const TELEGRAPHS = ['circles', 'lines', 'ring', 'none'];
  // pass 73 (lane GROUND): a rain's landing, BossAttackDef.LANDING_MODES
  const LANDING_MODES = ['stagger', 'volley'];
  const SCRIPTS = ['roll', 'spawn_ring', 'slam_at', 'blink', 'burrow', 'rain', 'erupt', 'spit_volley', 'slam', 'rumble',
    'brand', 'tumbleweed_volley', 'swoop', 'boulder'];
  const DEFAULTS = {
    projectile: { look: 'spike', tint: '#D0242F', size: 1.0, glow: 1.0, flight: 1.0, arc: 6.0, speed: 12.0, range: 18.0, hit_radius: 0.5, trail: true },
    pattern: { shape: 'rings', center: 'boss', radius_min: 3.0, radius_max: 16.0, spacing: 3.2, count: 0, jitter: 0.2, gap: 1.0, turn: true, order: 'out', spread_deg: 360.0, aim: 'hero', waves: 1, wave_gap: 0.5, width: 1.2 },
    landing: { radius: 0.9, mode: 'stagger' },
    telegraph: { kind: 'circles', color: '#ED4A5C', seconds: 0.9, all_at_once: false },
    timing: { windup: 1.0, stagger: 1.5, cooldown: 0.0, hold: -1.0 },
    sounds: { windup: '', fire: 'en_boss_attack', land: '' },
    spew: { crouch: 0.35, burst: 0.12, mouth: 0.62, squash: 0.82, stretch: 1.25 },
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
    if (topVal(a, 'damage') <= 0) warnings.push('damage 0: it never hurts');
    for (const c of [val(a, 'projectile', 'tint'), val(a, 'telegraph', 'color')]) if (c && !/^#[0-9a-fA-F]{6}$/.test(String(c))) errors.push(`a colour is #rrggbb: ${c}`);
    if (ids && ids.includes(String(a.id)) === false) { /* a new one */ }
    return { errors, warnings };
  }

  /** A new attack of `kind` with the game's defaults spelt out (the Boss attacks tab's "blank" template). */
  function blank(kind, id, name) {
    const k = KINDS.includes(kind) ? kind : 'rain';
    const a = { id, name: name || id, doc: '', kind: k };
    if (k === 'script') return Object.assign(a, { script: 'slam', params: { windup: 1.0, radius: 6.0, damage: 30, knockback: 6, telegraph: 'ring' } });
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
    SCALING_DEFAULTS, REF_DEFAULTS, scalingOf, hpMult, dpsForMult, bossEvents, stageMult, bossBaseHp, chartSeries, fightRel,
    KINDS, SHAPES, LOOKS, ORDERS, AIMS, CENTERS, TELEGRAPHS, SCRIPTS, DEFAULTS, TOP_DEFAULTS, HERO_RADIUS, LANDING_MODES,
    val, patternFull, topVal, rng, points, smallestGap, landTimes, rainLayout, volleyDirs, ringFront, hitDamage, issues, blank, num,
    isVolley, litAtOnce, windupSeconds, volleyTimes,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  return api;
})();
