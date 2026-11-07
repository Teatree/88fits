'use strict';
// Pass 133 (lane ONSCREEN): the page-free maths behind "Show on screen" (onscreen.js): the crowd the Timeline's On
// screen estimate expects at one second, laid out round the outlaw as a plausible still of the run. Garry (2026-11-07):
// "visualization of the OnScreen part as hero and the enemies surrounding him in the numbers that the onScreen is
// estimating ... the same visual alterations as the settings in the LevelEditor itself allow ... roughly showing the
// layout of where the enemies would be around the hero given the spawning behaviour ... a respectable distance from
// each other, just like in the game ... exactly that second of the run. The way it handles not whole numbers is just by
// random select."
//
// Nothing here is counted anew: the numbers come from one point of model.js's spawnEstimate (`aliveBy` the expected
// bodies alive per creature, `by` [spawned, coloured, elite-modified] per creature so far, `src` what each row spawned so
// far, `cap`). This module turns them into bodies:
//   counts   each creature's expected count: its whole part, and one more with the fraction as the chance (seeded);
//   rows     each body is given to one of the rows that spawn its creature, by what each row spawned in the past
//            ATTRIB_WINDOW s (the `src` tallies; the rows open now when nothing spawned; the first row of it else), so
//            it carries that row's size, look, pattern and Elite / Special settings;
//   place    its spawn point by the row's pattern (WaveDirector: 19-24 m out on a side drawn by `spawn_sides`'s weights,
//            or at the top for in_front, or on the row's ring at ring_radius / RING_RADIUS); then it has walked in for
//            its age (an exponential life with the estimate's mean) at its speed, never past the outlaw's contact ring;
//   push     a relaxation keeps every pair apart by the sum of their body radii (EnemyManager's separation), the outlaw
//            too, deterministic from the seed;
//   flags    a row set to Special makes every one of its bodies a special; an Elite modifier the same; the rest roll the
//            creature's shares so far (coloured / spawned, modified / spawned); an Elite mini-boss (archetype elite) wears
//            the crown as well. A special is x its special size (cut to a size range's top), an elite-modified x ELITE_SCALE.
// Everything is pure: selftest_P133ONSCREEN.py runs it under Node.
const OnScreenModel = (() => {
  const num = (v, d) => (typeof v === 'number' && isFinite(v) ? v : (v != null && v !== '' && isFinite(Number(v)) ? Number(v) : d));
  const isObj = (x) => x != null && typeof x === 'object' && !Array.isArray(x);
  const TAU = Math.PI * 2;

  /** WaveDirector._point_at: a regular spawn point lies this far from the outlaw. */
  const SPAWN_NEAR = 19, SPAWN_FAR = 24;
  /** WaveDirector.RING_RADIUS: a ring row without its own ring_radius. */
  const RING_RADIUS = 11.7;
  /** WaveDirector.SIDE_TURN / SIDE_HALF_ARC: screen angles of the four sides (0 = up the screen) and the arc round each. */
  const SIDE_TURN = { top: 0, bottom: Math.PI, left: Math.PI * 0.5, right: -Math.PI * 0.5 };
  const SIDE_HALF_ARC = Math.PI * 0.25;
  const SIDES = ['top', 'bottom', 'left', 'right'];
  const SIDES_DEF = { top: 30, bottom: 20, left: 20, right: 20 };
  /** Seconds of a row's spawning the attribution reads (the `src` tallies at t and t - window). */
  const ATTRIB_WINDOW = 20;
  /** A creature wearing an elite modifier is bigger by its kind, x1.4 to x1.6 in the game (docs/waves_schema.md pass 58). */
  const ELITE_SCALE = 1.4;
  /** The outlaw's body radius (Player: 0.5 m) and his painting's height (Player.gd:165: the quad is 1.9 m tall). */
  const HERO_RADIUS = 0.5, HERO_SIZE = 1.9;
  /** The estimate's default kill rate (model.js EST_DEF.turnover): a body lives 1 / turnover seconds on average. */
  const TURNOVER_DEF = 0.06;
  /** Relaxation: passes and how much of an overlap one pass takes out. */
  const RELAX_PASSES = 160, RELAX_STEP = 0.7;
  /** The crowd walks in a little slower than its speed (flocking, the push): this share of it. */
  const WALK_SHARE = 0.85;

  /** A seeded random (mulberry32; BossModel.rng's twin) with the names the layout uses. */
  function rng(seed) {
    let s = (Math.floor(num(seed, 1)) >>> 0) || 1;
    const randf = () => {
      s = (s + 0x6D2B79F5) >>> 0;
      let t = s;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
    return { randf, range: (a, b) => a + (b - a) * randf(), exp: (mean) => -Math.log(1 - randf() * 0.999999) * mean };
  }

  /** Garry's "random select": the whole part, and one more with the fraction as the chance. */
  function rollCount(expected, r) {
    const e = Math.max(num(expected, 0), 0);
    const whole = Math.floor(e);
    return whole + (r.randf() < e - whole ? 1 : 0);
  }

  /** A row's creature ids with their shares (a string, a list with enemy_weights, "roster" = none of its own). */
  function rowIds(r) {
    if (!isObj(r)) return [];
    const v = r.enemy;
    if (v == null || v === '' || v === 'roster') return [];
    if (!Array.isArray(v)) return [{ id: String(v), share: 1 }];
    const ids = v.map(String);
    if (!ids.length) return [];
    const ws = Array.isArray(r.enemy_weights) ? ids.map((_, k) => Math.max(k < r.enemy_weights.length ? num(r.enemy_weights[k], 0) : 1, 0)) : ids.map(() => 1);
    let total = 0;
    for (const w of ws) total += w;
    if (!(total > 0)) return ids.map((id) => ({ id, share: 1 / ids.length }));
    return ids.map((id, k) => ({ id, share: ws[k] / total })).filter((x) => x.share > 0);
  }

  /** The row open at second t (its window [t, until)). */
  function rowOpen(r, t) {
    const t0 = num(r && r.t, 0), t1 = r && r.until != null && r.until !== '' ? num(r.until, Infinity) : Infinity;
    return t >= t0 && t < t1;
  }

  /** How many bodies of `id` each row gets: the rows that spawn it weighed by what they spawned in the past window
   *  (`srcNow` - `srcBefore`, each row's tally x its share of the id), else by their presence now, else the first row of
   *  it; [{ri, w}] (empty: the id has no row). */
  function rowWeights(id, rows, srcNow, srcBefore, t) {
    const cands = [];
    rows.forEach((r, ri) => { for (const x of rowIds(r)) if (x.id === id) cands.push({ ri, share: x.share }); });
    if (!cands.length) return [];
    const recent = cands.map((c) => ({ ri: c.ri, w: Math.max(num(srcNow['roster:' + c.ri], 0) - num(srcBefore['roster:' + c.ri], 0), 0) * c.share }));
    if (recent.some((x) => x.w > 1e-9)) return recent.filter((x) => x.w > 1e-9);
    const open = cands.filter((c) => rowOpen(rows[c.ri], t)).map((c) => ({ ri: c.ri, w: c.share }));
    if (open.length) return open;
    return [{ ri: cands[0].ri, w: 1 }];
  }

  /** A size override: a number, or [min, max] rolled per body (docs/waves_schema.md pass 58); null = none. */
  function sizeOf(v, r) {
    if (v == null || v === '') return null;
    if (Array.isArray(v)) {
      const ns = v.map(Number).filter((x) => isFinite(x) && x > 0);
      if (!ns.length) return null;
      const lo = Math.min(...ns), hi = Math.max(...ns);
      return { size: r.range(lo, hi), top: hi, range: true };
    }
    const n = Number(v);
    return isFinite(n) && n > 0 ? { size: n, top: n, range: false } : null;
  }

  /** The special's numbers for a creature under a row: {size, tint, glow} (the creature's own variance.special, else the
   *  map's special_defaults, else the game's: EnemyDef.SPECIAL_DEFAULTS size 1.5, glow 0.6, tint #8A1428). */
  function specialOf(c, stats, defaults) {
    const st = isObj(stats) ? stats : {};
    const vr = c && isObj(c.variance) ? c.variance : {};
    const vo = isObj(st.variance) ? st.variance : {};
    const sp = Object.assign({}, isObj(vr.special) ? vr.special : {}, isObj(vo.special) ? vo.special : {});
    const d = isObj(defaults) ? defaults : {};
    const pick = (k, dflt) => (sp[k] != null && sp[k] !== '' && isFinite(Number(sp[k])) ? Number(sp[k]) : d[k] != null && d[k] !== '' && isFinite(Number(d[k])) ? Number(d[k]) : dflt);
    const hex = (v) => (typeof v === 'string' && v.trim() !== '' ? v.trim() : '');
    return { size: pick('size', 1.5), glow: pick('glow', 0.6), tint: hex(sp.tint) || hex(d.tint) || '#8A1428' };
  }

  /** A spawn point's angle (screen: 0 = up, clockwise) by the map's spawn_sides (mode sides: the four weights, 45 degrees
   *  round each side's axis; facing: 70% within 60 degrees of up, the rest anywhere; the game's _spawn_angle). */
  function spawnAngle(sides, r) {
    const ss = isObj(sides) ? sides : {};
    if (String(ss.mode == null ? 'facing' : ss.mode) === 'sides') {
      let total = 0;
      for (const s of SIDES) total += Math.max(num(ss[s], ss[s] == null && !SIDES.some((k) => ss[k] != null) ? SIDES_DEF[s] : 0), 0);
      if (total > 0) {
        let pick = r.randf() * total, side = SIDES[SIDES.length - 1];
        for (const s of SIDES) { const w = Math.max(num(ss[s], ss[s] == null && !SIDES.some((k) => ss[k] != null) ? SIDES_DEF[s] : 0), 0); if (pick < w) { side = s; break; } pick -= w; }
        return SIDE_TURN[side] + r.range(-SIDE_HALF_ARC, SIDE_HALF_ARC);
      }
    }
    if (r.randf() < num(ss.facing_share, 0.7)) return r.range(-1, 1) * (num(ss.facing_spread_deg, 60) * Math.PI / 180);
    return r.randf() * TAU;
  }

  /** The layout. `point` one of the estimate's points (aliveBy, by, src, cap, t), `before` the point ATTRIB_WINDOW s
   *  earlier (or null), `rows` the timeline's roster, `byId` the creatures' records by id (server: size, radius, speed,
   *  archetype, variance, play), `opts` {seed, turnover (the estimate's kill rate: mean life = 1 / it), sides
   *  (tl.spawn_sides), specialDefaults (tl.special_defaults), speedMult (the stage's and the map's creature speed
   *  multiple), maxBodies (default 320)}. Returns {bodies [{id, ri, x, z, size, radius, special, elite, crown, tint,
   *  glow, look, age, dist}], counts [{id, expected, n, special, elite}], total, expected, cap, seed}. x right, z down the
   *  screen (towards the camera), metres from the outlaw. */
  function layout(point, before, rows, byId, opts) {
    const o = isObj(opts) ? opts : {};
    const p = isObj(point) ? point : {};
    const seed = Math.floor(num(o.seed, 1));
    const r = rng(seed);
    const list = Array.isArray(rows) ? rows.filter(isObj) : [];
    const srcNow = isObj(p.src) ? p.src : {}, srcBefore = isObj(before && before.src) ? before.src : {};
    const t = num(p.t, 0);
    const turnover = Math.max(num(o.turnover, TURNOVER_DEF), 0.005);
    const meanLife = 1 / turnover;
    const maxBodies = Math.max(1, Math.floor(num(o.maxBodies, 320)));
    const byIdMap = isObj(byId) ? byId : {};
    const aliveBy = isObj(p.aliveBy) ? p.aliveBy : {};
    const by = isObj(p.by) ? p.by : {};
    // 1. counts, largest expected first so the roll's order is stable
    const ids = Object.keys(aliveBy).filter((id) => num(aliveBy[id], 0) > 1e-9).sort((a, b) => num(aliveBy[b], 0) - num(aliveBy[a], 0) || (a < b ? -1 : 1));
    const counts = [];
    let expected = 0;
    for (const id of ids) {
      const e = num(aliveBy[id], 0);
      expected += e;
      counts.push({ id, expected: e, n: rollCount(e, r), special: 0, elite: 0 });
    }
    // the pool's limit (EnemyManager.MAX): the biggest counts are cut last
    let total = counts.reduce((a, c) => a + c.n, 0);
    while (total > maxBodies) { const big = counts.reduce((a, c) => (c.n > a.n ? c : a), counts[0]); big.n--; total--; }
    // 2. rows and bodies
    const bodies = [];
    const rings = new Map();   // a ring row's rings: ri -> [{age, start, n, k}]
    for (const c of counts) {
      const cr = byIdMap[c.id] || null;
      const ws = rowWeights(c.id, list, srcNow, srcBefore, t);
      let W = 0;
      for (const w of ws) W += w.w;
      const tally = by[c.id];
      const spawned = Array.isArray(tally) ? num(tally[0], 0) : 0;
      const pCol = spawned > 0 && Array.isArray(tally) ? Math.min(num(tally[1], 0) / spawned, 1) : 0;
      const pMod = spawned > 0 && Array.isArray(tally) ? Math.min(num(tally[2], 0) / spawned, 1) : 0;
      for (let k = 0; k < c.n; k++) {
        // the row
        let ri = -1;
        if (W > 0) { let pick = r.randf() * W; for (const w of ws) { if (pick < w.w) { ri = w.ri; break; } pick -= w.w; } if (ri < 0) ri = ws[ws.length - 1].ri; }
        const row = ri >= 0 ? list[ri] : {};
        const st = isObj(row.stats) ? row.stats : {};
        // the flags
        const forcedSp = !!row.special;
        const forcedMod = !!(row.elite != null && row.elite !== '' && row.elite !== false);
        const special = forcedSp || (!forcedMod && r.randf() < pCol);
        const elite = forcedMod || (!special && r.randf() < pMod);
        const crown = elite || (cr && (cr.archetype === 'elite' || cr.kind === 'boss'));
        // the size: the row's (a number or a range), else the creature's; a special x its factor (cut to the range's
        // top); an elite modifier x ELITE_SCALE on top
        const baseSize = Math.max(num(cr && cr.size, 1), 0.05);
        const so = sizeOf(st.size, r);
        let size = so ? so.size : baseSize;
        const sp = specialOf(cr, st, o.specialDefaults);
        if (special) size = so && so.range ? Math.min(size * sp.size, so.top) : size * sp.size;
        if (elite) size *= ELITE_SCALE;
        const radius0 = num(st.radius, 0) > 0 ? num(st.radius, 0) : Math.max(num(cr && cr.radius, 0.5), 0.1) * (size / baseSize);
        const radius = Math.max(radius0, 0.15);
        // the spawn point and the walk in
        const pattern = String(row.pattern == null ? 'pack' : row.pattern);
        const speed = Math.max(num(cr && cr.speed, 2), 0.2) * Math.max(num(o.speedMult, 1), 0.05);
        let age, dist, ang;
        if (pattern === 'ring') {
          // one ring per `pack` bodies of the row, every body of a ring the same age, evenly round the circle
          const pack = Math.max(Math.floor(num(row.pack, num(cr && cr.pack_size, 1))), 1);
          const R = Math.max(num(row.ring_radius, RING_RADIUS), 1);
          let rs = rings.get(ri);
          if (!rs) { rs = []; rings.set(ri, rs); }
          let ring = rs[rs.length - 1];
          if (!ring || ring.k >= ring.n) { ring = { age: r.exp(meanLife), start: r.randf() * TAU, n: pack, k: 0, R }; rs.push(ring); }
          age = ring.age;
          ang = ring.start + (ring.k / ring.n) * TAU + r.range(-0.2, 0.2) * (TAU / ring.n);
          ring.k++;
          dist = ring.R + r.range(-0.6, 0.6);
        } else {
          age = r.exp(meanLife);
          dist = r.range(SPAWN_NEAR, SPAWN_FAR);
          ang = pattern === 'in_front' ? r.range(-SIDE_HALF_ARC, SIDE_HALF_ARC) : spawnAngle(o.sides, r);
        }
        const contact = HERO_RADIUS + radius + 0.1;
        dist = Math.max(dist - speed * WALK_SHARE * age, contact);
        // EnemyManager.point_inside: (-sin a, -cos a) x r (screen left is -x, up is -z)
        bodies.push({ id: c.id, ri, x: -Math.sin(ang) * dist, z: -Math.cos(ang) * dist, size, radius, special, elite, crown: !!crown,
          tint: special ? sp.tint : '', glow: special ? sp.glow : 0, look: row.variant ? String(row.variant) : (cr && (cr.play || cr.variant) ? String(cr.play || cr.variant) : ''), age, dist });
        if (special) c.special++;
        if (elite) c.elite++;
      }
    }
    relax(bodies);
    for (const b of bodies) b.dist = Math.hypot(b.x, b.z);
    return { bodies, counts, total, expected, cap: num(p.cap, 0), seed, t };
  }

  /** The push apart (EnemyManager's separation, settled): every pair closer than the sum of their radii is moved apart
   *  along their line, half each (RELAX_STEP of the overlap a pass), the outlaw at the origin pushing only. Bodies on
   *  the same spot step apart along a seeded direction so a pack never stays a point. Deterministic (index order). */
  function relax(bodies) {
    const n = bodies.length;
    if (!n) return;
    const r = rng(n * 7919 + 13);
    for (let pass = 0; pass < RELAX_PASSES; pass++) {
      let moved = 0;
      // a grid of 2.5 m cells so 300 bodies are cheap (EnemyManager's grid)
      const cell = 2.5;
      const grid = new Map();
      bodies.forEach((b, i) => { const key = Math.floor(b.x / cell) + ',' + Math.floor(b.z / cell); let l = grid.get(key); if (!l) { l = []; grid.set(key, l); } l.push(i); });
      for (let i = 0; i < n; i++) {
        const a = bodies[i];
        const cx = Math.floor(a.x / cell), cz = Math.floor(a.z / cell);
        for (let dx = -2; dx <= 2; dx++) for (let dz = -2; dz <= 2; dz++) {
          const l = grid.get((cx + dx) + ',' + (cz + dz));
          if (!l) continue;
          for (const j of l) {
            if (j <= i) continue;
            const b = bodies[j];
            const want = a.radius + b.radius;
            let ex = b.x - a.x, ez = b.z - a.z;
            let d = Math.hypot(ex, ez);
            if (d >= want) continue;
            if (d < 1e-6) { const ang = r.randf() * TAU; ex = Math.cos(ang); ez = Math.sin(ang); d = 1e-6; }
            const push = (want - d) * RELAX_STEP;
            const ux = ex / d, uz = ez / d;
            a.x -= ux * push * 0.5; a.z -= uz * push * 0.5;
            b.x += ux * push * 0.5; b.z += uz * push * 0.5;
            moved++;
          }
        }
        // the outlaw at the origin
        const want = HERO_RADIUS + a.radius;
        const d = Math.hypot(a.x, a.z);
        if (d < want) { if (d < 1e-6) { const ang = r.randf() * TAU; a.x = Math.cos(ang) * want; a.z = Math.sin(ang) * want; } else { a.x *= want / d; a.z *= want / d; } moved++; }
      }
      if (!moved) break;
    }
  }

  /** The worst overlap left among the bodies (and against the outlaw), in metres: 0 when none touch. */
  function worstOverlap(bodies) {
    let worst = 0;
    for (let i = 0; i < bodies.length; i++) {
      const a = bodies[i];
      worst = Math.max(worst, HERO_RADIUS + a.radius - Math.hypot(a.x, a.z));
      for (let j = i + 1; j < bodies.length; j++) {
        const b = bodies[j];
        worst = Math.max(worst, a.radius + b.radius - Math.hypot(a.x - b.x, a.z - b.z));
      }
    }
    return Math.max(worst, 0);
  }

  /** The facing a body walking towards the outlaw shows (the camera's view): the strip's view (front / back / side / bd
   *  / fd) and the heading (right / left) from the direction it walks (-x, -z towards the origin). `turned` flips it (the
   *  pop-up's second phase). A 2-way strip (no side views) gets front or back only. */
  function facingOf(x, z, eight, turned) {
    let dx = -x, dz = -z;
    if (turned) { dx = -dx; dz = -dz; }
    const len = Math.hypot(dx, dz) || 1;
    dx /= len; dz /= len;
    const facing = dx < 0 ? 'left' : 'right';
    // dz > 0: walking down the screen, towards the camera (its front is seen); dz < 0: away (its back)
    if (!eight) return { dir: dz >= 0 ? 'front' : 'back', facing };
    const a = Math.abs(dx);
    if (a < 0.38) return { dir: dz >= 0 ? 'front' : 'back', facing };
    if (a > 0.92) return { dir: 'side', facing };
    return { dir: dz >= 0 ? 'fd' : 'bd', facing };
  }

  /** The pop-up's phases (2 s each, one clock for all): the walk as each body faces, the walk turned round, the death. */
  const PHASES = [{ anim: 'run', turned: false, label: 'run' }, { anim: 'run', turned: true, label: 'run (turned: the back sets)' }, { anim: 'die', turned: false, label: 'die' }];
  const PHASE_SECONDS = 2;
  function phaseAt(seconds) { const k = Math.floor(Math.max(num(seconds, 0), 0) / PHASE_SECONDS) % PHASES.length; return { k, phase: PHASES[k], into: Math.max(num(seconds, 0), 0) - Math.floor(Math.max(num(seconds, 0), 0) / PHASE_SECONDS) * PHASE_SECONDS }; }

  /** The screen place of a ground spot: x across at `ppm` px/m, z down at ppm x DEPTH (the fixed camera's 46 degree pitch:
   *  a metre of ground depth spans sin(46) of a metre across); a billboard stands `size` m x ppm tall on its feet. */
  const DEPTH = 0.72;
  function project(x, z, ppm, cx, cy) { return { sx: cx + x * ppm, sy: cy + z * ppm * DEPTH }; }

  /** StageLook.filter_mults: the creatures' tint under a stage filter: white.lerp(color, strength x actors) as [r, g, b]
   *  0..1 (white = none), and the ground's at strength. */
  const ACTORS_DEFAULT = 0.35;
  function filterMults(filter) {
    const f = isObj(filter) ? filter : {};
    const hex = typeof f.color === 'string' && /^#[0-9a-fA-F]{6}$/.test(f.color) ? f.color : '#000000';
    const k = Math.min(1, Math.max(0, num(f.strength, 0)));
    const a = Math.min(1, Math.max(0, num(f.actors, ACTORS_DEFAULT)));
    const c = [parseInt(hex.slice(1, 3), 16) / 255, parseInt(hex.slice(3, 5), 16) / 255, parseInt(hex.slice(5, 7), 16) / 255];
    const lerp = (s) => c.map((v) => 1 + (v - 1) * s);
    return { world: lerp(k), actors: lerp(k * a), on: k > 0 };
  }

  const api = { SPAWN_NEAR, SPAWN_FAR, RING_RADIUS, ATTRIB_WINDOW, ELITE_SCALE, HERO_RADIUS, HERO_SIZE, TURNOVER_DEF, PHASES, PHASE_SECONDS, DEPTH, ACTORS_DEFAULT,
    rng, rollCount, rowIds, rowOpen, rowWeights, sizeOf, specialOf, spawnAngle, layout, relax, worstOverlap, facingOf, phaseAt, project, filterMults };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  return api;
})();
