// The Level Editor's maths with no page attached (pass 54): what the game does with the timeline's numbers, so the lanes,
// the readout and the hover cards show what a run will do. The same rules as game/core/data/WaveTimeline.gd
// (sample_points, curve_mult, hp_mult_at, damage_mult_at), WaveDirector._roster_weight and EnemyManager.spawn's health
// and damage. tools/level_editor/selftest.py loads this file under node and checks it against a Python copy of the game's
// formulas, so keep it free of the DOM.
'use strict';

const Model = (() => {
  const isObj = (x) => x != null && typeof x === 'object' && !Array.isArray(x);
  const num = (v, d) => { const n = Number(v); return v == null || v === '' || !isFinite(n) ? d : n; };
  const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
  const round = (n, d) => { const p = Math.pow(10, d == null ? 2 : d); return Math.round(n * p) / p; };

  // the game's own defaults where a key is missing (JsonContent.timeline_from_dict, WaveTimeline)
  const DEF = { hp_growth: 0.08, hp_power: 1.2, weight_late_t: 600, stage_length: 300, stages: 3 };
  const FORMULA_DEF = { kind: 'power', a: 0.0977, b: 1.25 };

  // ------------------------------------------------------------------ curves

  /** A point list at t: [[t, v], ...] in array order, linear between two points, flat before the first and after the
   *  last, 0 for an empty list; a malformed entry is skipped (WaveTimeline.sample_points). */
  function samplePoints(points, t) {
    let prevT = 0, prevV = 0, seen = false;
    for (const p of Array.isArray(points) ? points : []) {
      if (!Array.isArray(p) || p.length < 2) continue;
      const pt = num(p[0], 0), pv = num(p[1], 0);
      if (!seen) {
        if (t <= pt) return pv;
        seen = true;
      } else if (t <= pt) {
        return prevV + (pv - prevV) * ((t - prevT) / Math.max(pt - prevT, 0.001));
      }
      prevT = pt; prevV = pv;
    }
    return prevV;
  }

  /** A curve's formula at t, m = minutes: linear 1 + a*m, power (1 + a*m)^b, exponential (1 + a)^m; an unknown kind is 1. */
  function formulaAt(f, t) {
    const ff = isObj(f) ? f : {};
    const a = num(ff.a, FORMULA_DEF.a), b = num(ff.b, FORMULA_DEF.b), m = t / 60;
    switch (ff.kind == null ? FORMULA_DEF.kind : String(ff.kind)) {
      case 'linear': return 1 + a * m;
      case 'power': return Math.pow(Math.max(1 + a * m, 0), b);
      case 'exponential': return Math.pow(Math.max(1 + a, 0), m);
      default: return 1;
    }
  }

  /** "points" or "formula": the curve's `mode`, else points when it has any, else the formula (WaveTimeline.curve_mult). */
  function curveMode(c) {
    if (!isObj(c)) return 'formula';
    const pts = Array.isArray(c.points) ? c.points : [];
    return c.mode != null ? String(c.mode) : (pts.length ? 'points' : 'formula');
  }

  /** An hp_curve / damage_curve block's multiplier at t; 1 when the block is empty or says nothing usable. */
  function curveMult(c, t) {
    if (!isObj(c) || !Object.keys(c).length) return 1;
    const pts = Array.isArray(c.points) ? c.points : [];
    const mode = curveMode(c);
    if (mode === 'points') return pts.length ? samplePoints(pts, t) : 1;
    if (mode !== 'formula') return 1;
    return formulaAt(isObj(c.formula) ? c.formula : {}, t);
  }

  const hasCurve = (c) => isObj(c) && Object.keys(c).length > 0;

  /** Creature HP over the run clock: the hp_curve when the map has one, else (1 + hp_growth × minutes)^hp_power. */
  function hpTimeMult(tl, t) {
    if (hasCurve(tl.hp_curve)) return curveMult(tl.hp_curve, t);
    return Math.pow(1 + num(tl.hp_growth, DEF.hp_growth) * (t / 60), num(tl.hp_power, DEF.hp_power));
  }

  /** Creature damage over the run clock: the damage_curve, 1 without one. */
  function dmgTimeMult(tl, t) {
    return hasCurve(tl.damage_curve) ? curveMult(tl.damage_curve, t) : 1;
  }

  // ------------------------------------------------------------------ stages

  const stageLength = (tl) => num(tl.stage_length, DEF.stage_length) || DEF.stage_length;
  const stages = (tl) => Math.max(1, num(tl.stages, DEF.stages));
  const runEnd = (tl) => stages(tl) * stageLength(tl);
  /** 0-based stage index at run second t (stages() and above = endless, as Run.stage counts on through endless). */
  const stageAt = (tl, t) => Math.max(0, Math.floor(t / stageLength(tl)));

  /** The stage multiplier (WaveTimeline.stage_mult): the stage's entry, endless from the last one by its waves. */
  function stageMult(tl, s, t) {
    const sm = Array.isArray(tl.stage_mults) ? tl.stage_mults : [];
    if (!sm.length) return 1;
    if (s < sm.length) return num(sm[s], 1);
    const last = num(sm[sm.length - 1], 1);
    const into = Math.max(0, (t == null ? s * stageLength(tl) : t) - runEnd(tl));
    const wm = num(tl.endless_wave_mult, 1);
    if (wm > 1) return last * Math.pow(wm, Math.floor(into / Math.max(num(tl.endless_wave_seconds, 60), 1)));
    return last * (1 + num(tl.endless_mult_per_minute, 0) * into / 60);
  }

  // ------------------------------------------------------------------ roster rows

  /** A row's draw weight at t: its `weights` keyframes, else the old slide from `weight` to `weight_late` by
   *  weight_late_t (WaveDirector._roster_weight). */
  function rowWeight(r, t, lateT) {
    const ws = r && r.weights;
    if (Array.isArray(ws) && ws.length) return Math.max(samplePoints(ws, t), 0);
    const w = num(r && r.weight, 1);
    if (!r || r.weight_late == null) return w;
    const start = num(r.t, 0), late = num(lateT, DEF.weight_late_t);
    const f = clamp((t - start) / Math.max(late - start, 1), 0, 1);
    return w + (num(r.weight_late, w) - w) * f;
  }

  /** The keyframes an old-shape row stands for: [[t, weight]] plus [weight_late_t, weight_late] when it slides; the
   *  second point is never before t + 1 (the old slide reached weight_late a second after a row that starts at or after
   *  weight_late_t, and the order cannot flip). Lane WD converted Red Canyon by the same rule. */
  function keyframesOf(r, lateT) {
    const t = num(r.t, 0);
    const pts = [[t, num(r.weight, 1)]];
    if (r.weight_late != null) pts.push([Math.max(num(lateT, DEF.weight_late_t), t + 1), num(r.weight_late, 0)]);
    return pts;
  }

  /** The row in the pass-54 shape: `weights` where `weight` stood, `weight_late` gone; null when it already is. */
  function convertRow(r, lateT) {
    if (!isObj(r)) return null;
    const hasNew = Array.isArray(r.weights) && r.weights.length > 0;
    if (hasNew && !('weight' in r) && !('weight_late' in r)) return null;
    const pts = hasNew ? r.weights : keyframesOf(r, lateT);
    const out = {};
    let placed = false;
    for (const k of Object.keys(r)) {
      if (k === 'weight' || k === 'weight_late' || k === 'weights') {
        if (!placed) { out.weights = pts; placed = true; }
      } else out[k] = r[k];
    }
    if (!placed) out.weights = pts;
    return out;
  }

  /** Every roster row in the new shape with a unique `id` (r1, r2, ... in the file's order for the rows that have none; a
   *  duplicate gets a fresh one). Changes `tl.roster` in place; returns how many rows were converted and given ids. */
  function normaliseRoster(tl, lateT) {
    const rows = Array.isArray(tl.roster) ? tl.roster : [];
    let converted = 0, ided = 0;
    const late = lateT != null ? lateT : num(tl.weight_late_t, DEF.weight_late_t);
    for (let i = 0; i < rows.length; i++) {
      const c = convertRow(rows[i], late);
      if (c) { rows[i] = c; converted++; }
    }
    const used = new Set();
    const need = [];
    rows.forEach((r, i) => {
      if (!isObj(r)) return;
      if (typeof r.id === 'string' && r.id !== '' && !used.has(r.id)) used.add(r.id);
      else need.push(i);
    });
    let n = 1;
    for (const i of need) {
      while (used.has('r' + n)) n++;
      const r = rows[i];
      const out = { id: 'r' + n };
      for (const k of Object.keys(r)) if (k !== 'id') out[k] = r[k];
      rows[i] = out;
      used.add('r' + n);
      ided++;
    }
    return { converted, ided };
  }

  /** A fresh row id not used in the roster. */
  function newRowId(tl) {
    const used = new Set((Array.isArray(tl.roster) ? tl.roster : []).map((r) => r && r.id));
    let n = 1;
    while (used.has('r' + n)) n++;
    return 'r' + n;
  }

  // ------------------------------------------------------------------ one creature's numbers at a time

  const getPath = (o, path) => {
    let cur = o;
    for (const p of path.split('.')) { if (!isObj(cur) || !(p in cur)) return undefined; cur = cur[p]; }
    return cur;
  };

  /** A bite's shove on the hero when the creature's JSON has no `knockback` (EnemyDef.default_knockback). */
  const defaultKnockback = (damage) => clamp(3.4 * Math.sqrt(Math.max(num(damage, 0), 0) / 4), 2.5, 7.0);

  /** The creature's base HP and damage after a row's overrides (EnemyDef.with_overrides: `hp` / `damage` replace, then
   *  the `*_mult` keys multiply). */
  function baseNumbers(c, stats) {
    const st = isObj(stats) ? stats : {};
    const cc = c || {};
    const hp = num(st.hp, num(cc.hp, 0)) * num(st.hp_mult, 1);
    const dmg = num(st.damage, num(cc.damage, 0)) * num(st.damage_mult, 1);
    return { hp, dmg };
  }

  /** The knockback (m/s) a bite of this creature gives with the row's overrides: stats.knockback, else the JSON's own,
   *  else the default from its (overridden) damage; × knockback_mult. `from` says where the number came from. */
  function knockbackOf(c, stats) {
    const st = isObj(stats) ? stats : {};
    const mult = num(st.knockback_mult, 1);
    if (st.knockback != null && st.knockback !== '') return { value: num(st.knockback, 0) * mult, from: 'row' };
    const k = c ? num(c.knockback, 0) : 0;
    if (k > 0) return { value: k * mult, from: 'creature' };
    return { value: defaultKnockback(baseNumbers(c, st).dmg) * mult, from: 'default' };
  }

  /** HP and ATK of one creature spawned at run second t (EnemyManager.spawn): a boss scales by its own
   *  boss.hp_mult_per_stage^stage × the stage multiplier; an Elite-archetype mini-boss by elite.hp_mult_per_stage^stage ×
   *  the stage multiplier × creature_hp_mult (no time, no level); everyone else by the stage, the HP curve, the hero's
   *  level and creature_hp_mult. Damage is the stage, the hero's level, the damage curve and creature_damage_mult for
   *  all. `parts` lists the factors for the cards; `level` is the hero level the page assumes. */
  function creatureAt(tl, c, stats, t, level) {
    const st = isObj(stats) ? stats : {};
    const s = stageAt(tl, t);
    const sm = stageMult(tl, s, t);
    const lv = Math.max(1, num(level, 1));
    const lvHp = 1 + num(tl.level_hp_per_level, 0) * Math.max(lv - 1, 0);
    const lvDmg = 1 + num(tl.level_damage_per_level, 0) * Math.max(lv - 1, 0);
    const chm = num(tl.creature_hp_mult, 1), cdm = num(tl.creature_damage_mult, 1);
    const hpT = hpTimeMult(tl, t), dmgT = dmgTimeMult(tl, t);
    const base = baseNumbers(c, st);
    const arch = c.archetype === 'boss' || c.kind === 'boss' ? 'boss' : c.archetype === 'elite' ? 'elite' : 'regular';
    let hp, hpParts;
    if (arch === 'boss') {
      const per = num(getPath(st, 'boss.hp_mult_per_stage'), num(c.boss && c.boss.hp_mult_per_stage, 1.6));
      hp = base.hp * Math.pow(per, s) * Math.max(sm, 1);
      hpParts = [['base', base.hp], [`boss ${round(per, 2)}^${s}`, Math.pow(per, s)], ['stage', Math.max(sm, 1)]];
    } else if (arch === 'elite') {
      const per = num(getPath(st, 'elite.hp_mult_per_stage'), num(c.elite && c.elite.hp_mult_per_stage, 1.8));
      hp = base.hp * Math.pow(per, s) * Math.max(sm, 1) * chm;
      hpParts = [['base', base.hp], [`elite ${round(per, 2)}^${s}`, Math.pow(per, s)], ['stage', Math.max(sm, 1)], ['creature', chm]];
    } else {
      hp = base.hp * sm * hpT * lvHp * chm;
      hpParts = [['base', base.hp], ['stage', sm], ['time', hpT], ['level', lvHp], ['creature', chm]];
    }
    const atk = base.dmg * sm * lvDmg * cdm * dmgT;
    const atkParts = [['base', base.dmg], ['stage', sm], ['time', dmgT], ['level', lvDmg], ['creature', cdm]];
    // the coloured variance special (EnemyManager: × special.hp / special.damage, defaults 1.6 / 1.2)
    const vr = isObj(c.variance) ? c.variance : {};
    const vo = isObj(st.variance) ? st.variance : {};
    const sp = Object.assign({}, isObj(vr.special) ? vr.special : {}, isObj(vo.special) ? vo.special : {});
    const spChance = num(vo.special_chance, num(vr.special_chance, 0));
    const special = arch === 'regular' && spChance > 0 ? { chance: spChance, hp: hp * num(sp.hp, 1.6), atk: atk * num(sp.damage, 1.2) } : null;
    return { arch, stage: s, stageMult: sm, hp, atk, hpParts, atkParts, special, base };
  }

  /** The override keys of a stats block other than the ones the HP / ATK numbers already show, as short words. */
  function otherOverrides(stats) {
    const out = [];
    const walk = (o, prefix) => {
      for (const [k, v] of Object.entries(o)) {
        const key = prefix ? `${prefix}.${k}` : k;
        if (!prefix && (k === 'hp' || k === 'hp_mult' || k === 'damage' || k === 'damage_mult')) continue;
        if (isObj(v)) walk(v, key);
        else if (Array.isArray(v)) out.push(`${key} [${v.length}]`);
        else out.push(`${key} ${typeof v === 'number' ? round(v, 3) : v}`);
      }
    };
    if (isObj(stats)) walk(stats, '');
    return out;
  }

  /** A curve's formula sampled at the stage marks (0, stage_length, ... the run's end): the points a switch from formula
   *  to manual starts from. Four decimals, like the map's own curves. */
  function seedPoints(tl, formula) {
    const SL = stageLength(tl), n = stages(tl);
    const out = [];
    for (let k = 0; k <= n; k++) out.push([k * SL, round(formulaAt(formula, k * SL), 4)]);
    return out;
  }

  // ------------------------------------------------------------------ spawned so far (pass 57)
  //
  // Garry (2026-10-07): "a row ... which shows the cumulative amount of enemies of all types that had spawned thus far up
  // to that point. This option should account for spawning patterns and caps ... including Elites, Specials and Bosses,
  // and for regular enemies there should be an average estimate of how many of them were made 'coloured' or 'elite'".
  //
  // A run only spawns what the hero kills: the director tops the crowd up to its cap, so the count depends on how fast
  // the hero clears it. The estimate plays WaveDirector with expected values instead of dice, 20 steps a second: every
  // creature alive dies at `turnover` a second (6 % = an average creature lives about 17 s; the server fits it from
  // Garry's own run records), and the director refills at its own cadence under its own rules: the live cap (the curve,
  // cap_per_stage, cap_max), load units by cap_share, the roster rows inside their windows by their presence weights,
  // a draw bringing the row's pack (a "single" row one creature; "ring" and "in_front" spawn the pack as "pack" does),
  // max_alive, the hard cap, the hell channel against its own share of the cap, the waves (count, burst, every,
  // respect_cap, the alternatives as expected values), swarms on top of the cap, Elites, the elite modifiers (elite and
  // elite_every with the rows' formats, held until colour comes), the specials' clock (each special lives 1 / turnover
  // seconds), each boss fight (`bossSeconds` of play at boss_cap_frac, with what the boss's own script brings: its
  // spawn_ring minions) and its portal wait (the portal wave, or portal_cap for portal_spawn_seconds), then endless. Events are taken at their own `t` (t_jitter averages out) and an
  // event's `chance` scales what it brings (a boss comes when its chance is 0.5 or more). The run clock stands still
  // through a boss fight, so on the clock axis a fight is a step at its second. tools/level_editor/selftest.py runs a
  // Python copy of this function on the same timelines and checks that the two agree.

  /** The game's body limit (EnemyManager.MAX): nothing spawns past it, a swarm included. */
  const MAX_BODIES = 320;
  /** Steps a second: the estimate's tick is 0.05 s, so a spawn_interval of 0.25, 0.5 or 0.7 s lands on whole steps. */
  const EST_HZ = 20;
  /** The assumptions when there is nothing better (no run records): 6 % of the crowd killed a second, a 60 s boss fight,
   *  a 30 s portal wait. */
  const EST_DEF = { turnover: 0.06, bossSeconds: 60, portalSeconds: 30 };
  /** WaveTimeline's own defaults for the keys the estimate reads (JsonContent.timeline_from_dict). */
  const TL_SPAWN_DEF = {
    cap_start: 100, cap_per_minute: 10, cap_max: 250, hard_cap: 300, cap_per_stage: 0, boss_cap_frac: 0.3, portal_cap: 10,
    portal_spawn_seconds: 30, burst_min: 5, burst_max: 20, spawn_interval: 0.5, colour_after_kills: 0,
  };

  /** How far past its second the frozen clock reads (see `now` in spawnEstimate). */
  const HAIR = 1e-4;
  /** GDScript's int(): toward zero. */
  const trunc = (v) => (v < 0 ? Math.ceil(v) : Math.floor(v));

  /** An event's creature list as [{id, share}] (WaveDirector._pick_id: by `weights` when given, an entry past their end
   *  weighing 1 and a weight at or below 0 never drawn; else evenly). */
  function pickShares(v, weights) {
    const ids = v == null || v === '' ? [] : Array.isArray(v) ? v.map(String) : [String(v)];
    if (!ids.length) return [];
    if (Array.isArray(v) && Array.isArray(weights) && weights.length) {
      const ws = ids.map((_, k) => Math.max(k < weights.length ? num(weights[k], 0) : 1, 0));
      let total = 0;
      for (const w of ws) total += w;
      if (total > 0) return ids.map((id, k) => ({ id, share: ws[k] / total })).filter((x) => x.share > 0);
    }
    return ids.map((id) => ({ id, share: 1 / ids.length }));
  }

  /** How many an elite-modified arrival brings on average (WaveDirector._elite_format): alone, its whole pack, or a ring
   *  of its pack, by the row's elite_formats chances (all 0, or none = alone). */
  function eliteCount(formats, pack) {
    const f = isObj(formats) ? formats : {};
    const s = Math.max(num(f.single, 0), 0), p = Math.max(num(f.pack, 0), 0), r = Math.max(num(f.ring, 0), 0);
    const total = s + p + r;
    if (!(total > 0)) return 1;
    return (s + (p + r) * pack) / total;
  }

  /** The expected bodies one burst of `start` load units brings from each of `rows` ([{w, s (load per body, at least
   *  0.05), pack, single, room (what max_alive still allows, Infinity without one)}]), WaveDirector._burst_from: each draw
   *  picks a row by weight and brings its pack (a single row one creature), the last draw only what the burst still
   *  holds. One moment is kept: the draws that end the burst stop their share of the mass, the rest go on with the mean
   *  of what they left. */
  function burstOnce(rows, start) {
    const out = rows.map(() => 0);
    let W = 0;
    for (const x of rows) if (x.w > 0) W += x.w;
    if (!(W > 0) || !(start > 0)) return out;
    let mass = 1, rem = start;
    for (let step = 0; step < 64 && mass > 1e-9 && rem > 1e-9; step++) {
      let cm = 0, cr = 0;
      for (let k = 0; k < rows.length; k++) {
        const x = rows[k];
        if (!(x.w > 0)) continue;
        const p = x.w / W;
        let n = x.single ? 1 : x.pack;
        const fit = rem / x.s;
        if (fit < n) n = fit;
        if (x.room < n) n = x.room;
        out[k] += mass * p * n;
        const left = rem - n * x.s;
        if (left > 1e-9 && n > 1e-9) { cm += p; cr += p * left; }
      }
      if (!(cm > 0)) break;
      rem = cr / cm;
      mass *= cm;
    }
    return out;
  }

  /** One burst averaged over its size: randi_range(burst_min, burst_max), each cut to the room. */
  function burstAvg(rows, room, lo, hi) {
    const acc = rows.map(() => 0);
    let nb = 0, lastStart = null, last = null;
    for (let b = lo; b <= hi; b++) {
      const start = Math.min(b, room);
      if (start !== lastStart) { last = burstOnce(rows, start); lastStart = start; }
      for (let k = 0; k < rows.length; k++) acc[k] += last[k];
      nb++;
    }
    if (nb > 0) for (let k = 0; k < rows.length; k++) acc[k] /= nb;
    return acc;
  }

  /** When a boss's own script brings creatures in a fight of `seconds` (EnemyManager._update_attacks): its attacks in
   *  order from 2 s in, each its wind-up (/ move_pace), a roll its charge too, a rain or an eruption its strikes, then the
   *  cooldown; a spawn_ring brings its `count` of `enemy` as its wind-up ends, an eruption with a `spawn` one a strike.
   *  [{t, id, n}] in the fight's own seconds. */
  function bossBrood(script, cooldown, seconds, pace) {
    const out = [];
    if (!Array.isArray(script) || !script.length) return out;
    const pc = pace > 0 ? pace : 1;
    let t = 2;
    for (let k = 0; k < 1000 && t < seconds; k++) {
      const a = isObj(script[k % script.length]) ? script[k % script.length] : {};
      const name = String(a.name == null ? '' : a.name);
      const wind = num(a.windup, 1) / pc;
      const at = t + wind;
      let busy = wind;
      if (name === 'roll') busy += num(a.duration, 1.2) / pc;
      if (name === 'rain' || name === 'erupt') busy += num(a.count, 10) * num(a.interval, 0.3) + num(a.warn, 0.55) / pc + 0.3;
      if (at <= seconds) {
        if (name === 'spawn_ring') out.push({ t: at, id: String(a.enemy == null ? 'coyote' : a.enemy), n: Math.max(trunc(num(a.count, 10)), 0) });
        else if (name === 'erupt' && a.spawn) out.push({ t: at, id: String(a.spawn), n: Math.max(trunc(num(a.count, 10)), 0) });
      }
      t += busy + cooldown;
    }
    return out;
  }

  /** The estimate (the block comment above). `creatures`: the server's records (a list or an id map). `opts`: {turnover
   *  (a share of the crowd a second, or a list per stage, the last for later stages and endless), bossSeconds,
   *  portalSeconds, end (the run clock to stop at; default the editor's view end), skin (the map's first skin, for a swarm
   *  that names no creature), boss (the map's boss, for a boss event that names none and for endless)}. Returns
   *  {points: one per run second (and one after each boss fight, at the fight's second), each {t, after, all, reg, col,
   *  mod, elite, special, boss, kills, alive, by: {id: [spawned, coloured, elite-modified]}}, ids (largest first), marks
   *  [{t, kind elite|mod|special|boss|swarm, id, n}], fights [{t, boss, seconds, portal, spawned}], colourAt, assume}. */
  function spawnEstimate(tl, creatures, opts) {
    const o = isObj(opts) ? opts : {};
    const byId = {};
    if (Array.isArray(creatures)) { for (const c of creatures) if (c && c.id) byId[c.id] = c; } else if (isObj(creatures)) Object.assign(byId, creatures);
    const g = (key) => num(tl[key], TL_SPAWN_DEF[key]);
    const SL = stageLength(tl), NST = stages(tl);
    const end = o.end != null ? num(o.end, 0) : runEnd(tl) + Math.max(120, Math.round(SL * 0.35));
    // the kill rate: a number, a list per stage (the last for later stages and endless), or [[t, rate], ...] over the run
    // clock (the server's minute-by-minute fit: a young build kills slowly), linear between the points, flat outside
    const tin = o.turnover;
    const tvCurve = Array.isArray(tin) && tin.length && Array.isArray(tin[0])
      ? tin.filter((q) => Array.isArray(q) && q.length >= 2).map((q) => [num(q[0], 0), Math.max(num(q[1], 0), 0)]) : null;
    const tvStages = !tvCurve && Array.isArray(tin) && tin.length ? tin.map((v) => Math.max(num(v, EST_DEF.turnover), 0)) : null;
    const tvFlat = Math.max(num(Array.isArray(tin) ? null : tin, EST_DEF.turnover), 0);
    // a fight or a wait is kept under half an hour, so a typo cannot hang the page
    const bossSteps = Math.max(1, Math.round(clamp(num(o.bossSeconds, EST_DEF.bossSeconds), 0, 1800) * EST_HZ));
    const portalSteps = Math.max(1, Math.round(clamp(num(o.portalSeconds, EST_DEF.portalSeconds), 0, 1800) * EST_HZ));
    const burstEvery = Math.max(1, Math.round(g('spawn_interval') * EST_HZ));
    const bLo = trunc(g('burst_min')), bHi = Math.max(trunc(g('burst_max')), bLo);
    const hard = trunc(g('hard_cap')), capMax = trunc(g('cap_max')), capPerStage = trunc(g('cap_per_stage'));
    const colourAfter = trunc(g('colour_after_kills'));
    const bossFrac = g('boss_cap_frac');
    const portalCap = trunc(g('portal_cap')), portalSpawn = g('portal_spawn_seconds');
    const pwBlock = isObj(tl.portal_wave) ? tl.portal_wave : {};
    const portalWaveCount = trunc(num(pwBlock.count, 0));
    const hellCap = Array.isArray(tl.hell_cap) ? tl.hell_cap : [];
    const curve = Array.isArray(tl.cap_curve) ? tl.cap_curve : [];
    const lateT = num(tl.weight_late_t, DEF.weight_late_t);
    const pace = num(tl.move_pace, 1) > 0 ? num(tl.move_pace, 1) : 1;
    const evList = Array.isArray(tl.events) ? tl.events : [];

    // ---- a creature as overrides make it (EnemyDef.with_overrides: the fields the spawn rules read)
    const defCache = new Map();
    function defOf(id, stats) {
      const st = isObj(stats) ? stats : {};
      const key = id + '|' + JSON.stringify(st);
      if (defCache.has(key)) return defCache.get(key);
      const c = byId[id];
      let d = null;
      if (c) {
        const vr = isObj(c.variance) ? c.variance : {};
        const vo = isObj(st.variance) ? st.variance : {};
        const hasVar = Object.keys(vr).length > 0 || Object.keys(vo).length > 0;
        d = {
          id,
          arch: c.archetype === 'boss' || c.kind === 'boss' ? 'boss' : c.archetype === 'elite' ? 'elite' : 'regular',
          share: num(st.cap_share, num(c.cap_share, 1)),
          pack: Math.max(trunc(num(st.pack, num(c.pack_size, 1))), 1),
          maxAlive: trunc(num(st.max_alive, num(c.max_alive, 0))),
          canBeElite: st.can_be_elite != null ? !!st.can_be_elite : c.can_be_elite !== false,
          eliteWeight: Math.max(num(st.elite_weight, 1), 0),
          formats: isObj(st.elite_formats) ? st.elite_formats : {},
          chance: hasVar ? Math.max(num(vo.special_chance, num(vr.special_chance, 0)), 0) : 0,
        };
        // a boss's script as the overrides leave it (EnemyDef.with_overrides: boss.attacks on / off by name or a list,
        // boss.cooldown_between, attack_rate_mult)
        const cb = isObj(c.boss) ? c.boss : {};
        const sb = isObj(st.boss) ? st.boss : {};
        let script = Array.isArray(cb.script) ? cb.script.filter(isObj) : [];
        if (isObj(sb.attacks)) script = script.filter((a) => sb.attacks[a.name] === undefined || !!sb.attacks[a.name]);
        else if (Array.isArray(sb.attacks)) script = sb.attacks.filter(isObj);
        let cooldown = num(sb.cooldown_between, num(cb.cooldown_between, 2));
        const rate = num(st.attack_rate_mult, 1);
        if (rate > 0 && rate !== 1) cooldown /= rate;
        d.script = script;
        d.cooldown = cooldown;
      }
      defCache.set(key, d);
      return d;
    }
    // every roster row with its creature, in the timeline's order (the game reads them in that order)
    const roster = [];
    for (const r of Array.isArray(tl.roster) ? tl.roster : []) {
      if (!isObj(r)) continue;
      const d = defOf(String(r.enemy == null ? '' : r.enemy), r.stats);
      if (d) roster.push({ r, d, t: num(r.t, 0), until: r.until == null || r.until === '' ? 1e9 : num(r.until, 1e9), hell: r.channel === 'hell', pack: Math.max(trunc(num(r.pack, d.pack)), 1), single: r.pattern === 'single' });
    }

    // ---- the crowd: expected bodies per type (an id and its load per body)
    const alive = new Map();           // id|share -> {id, share, n}
    const spLive = [];                 // the specials alive: [{share, die (play step)}]
    let bossAlive = null;              // {share} while a boss fight runs
    const cum = {}, col = {}, mod = {};
    const cat = { reg: 0, col: 0, mod: 0, elite: 0, special: 0, boss: 0, minion: 0 };
    let kills = 0, colourAt = null;
    const marks = [], fights = [];
    const aliveOf = (id) => { let n = 0; for (const a of alive.values()) if (a.id === id) n += a.n; return n; };
    const bodies = () => { let n = 0; for (const a of alive.values()) n += a.n; return n + spLive.length + (bossAlive ? 1 : 0); };
    const loadOf = (ids) => { let l = 0; for (const a of alive.values()) if (ids.has(a.id)) l += a.n * a.share; return l; };
    const loadAll = () => {
      let l = 0;
      for (const a of alive.values()) l += a.n * a.share;
      for (const s of spLive) l += s.share;
      return l + (bossAlive ? bossAlive.share : 0);
    };
    const total = () => cat.reg + cat.elite + cat.special + cat.boss;
    const colourOpen = () => kills >= colourAfter;
    const bump = (m, id, n) => { m[id] = (m[id] || 0) + n; };

    /** `n` (expected) bodies of `d` join the crowd as `kind`: 'reg' (a roster, wave, swarm or portal creature, coloured by
     *  its variance special's chance once colour is open), 'mod' (wearing an elite modifier: never coloured) or 'elite'
     *  (an Elite mini-boss). */
    function add(d, n, kind) {
      if (!(n > 0) || !d) return;
      const key = d.id + '|' + d.share;
      const a = alive.get(key);
      if (a) a.n += n; else alive.set(key, { id: d.id, share: d.share, n });
      bump(cum, d.id, n);
      if (kind === 'elite') { cat.elite += n; return; }
      cat.reg += n;
      if (kind === 'mod') { cat.mod += n; bump(mod, d.id, n); return; }
      if (d.arch === 'regular' && d.chance > 0 && colourOpen()) { const c = n * d.chance; cat.col += c; bump(col, d.id, c); }
    }

    // ---- the clocks: the run clock is k / EST_HZ and stands still through a boss fight and its portal wait
    let k = 0, play = 0, stage = 0, phase = 0, phaseLeft = 0, portalT = 0, spawnStep = 0;
    let fight = null;
    let endless = false, enNextBoss = 0, enNextElite = 0, enNextEliteBoss = 0, enBossI = 0;
    const clock = () => k / EST_HZ;
    // what the director reads as Run.elapsed: the clock, but a hair past it while the clock stands still (the frame that
    // fired an event is past its second, so a boss fight dated on a step of the cap curve plays the step's far side:
    // Red Canyon's first fight keeps 0.6 of 54, not of 100)
    const now = () => (phase === 0 ? k / EST_HZ : k / EST_HZ + HAIR);
    // never more than the whole crowd a second
    const turnoverNow = () => Math.min(tvCurve ? (tvCurve.length ? samplePoints(tvCurve, clock()) : 0)
      : tvStages ? tvStages[Math.min(Math.max(stage, 0), tvStages.length - 1)] : tvFlat, 1);

    /** WaveDirector.current_cap: the curve (or the old line), cap_per_stage, cap_max; boss_cap_frac of it in a boss fight;
     *  in the portal wait 0 after a portal wave, else portal_cap (-1 = the stage-end cap) for portal_spawn_seconds. */
    function capNow() {
      const t = now();
      const base = curve.length ? samplePoints(curve, t) : trunc(g('cap_start')) + g('cap_per_minute') * (t / 60);
      const cap = Math.min(trunc(base + capPerStage * stage), capMax);
      if (phase === 1) return trunc(cap * bossFrac);
      if (phase === 2) {
        if (portalWaveCount > 0) return 0;
        if (portalSpawn >= 0 && portalT >= portalSpawn) return 0;
        return portalCap < 0 ? cap : portalCap;
      }
      return cap;
    }
    const hellFrac = () => (hellCap.length ? num(hellCap[Math.min(Math.max(stage, 0), hellCap.length - 1)], 0) : 0);

    /** The roster rows open at `tr` (WaveTimeline.roster_at): the hell channel's (`hell` true), the rest (false) or all. */
    function rowsAt(tr, hell) {
      const out = [];
      for (const x of roster) {
        if (!(tr >= x.t && tr < x.until)) continue;
        if (hell != null && x.hell !== hell) continue;
        out.push(x);
      }
      return out;
    }
    /** The rows whose creature is under its max_alive (WaveDirector._roster_open), with the room it leaves. */
    function openRows(rows) {
      const out = [];
      for (const x of rows) {
        let room = Infinity;
        if (x.d.maxAlive > 0) { room = x.d.maxAlive - aliveOf(x.d.id); if (!(room > 1e-9)) continue; }
        out.push({ x, room });
      }
      return out;
    }

    // ---- the waves: one branch per alternative, weighted by its chance (the game rolls one of them per run)
    const waves = [];
    for (const w of Array.isArray(tl.waves) ? tl.waves : []) {
      if (!isObj(w)) continue;
      const alts = (Array.isArray(w.alts) ? w.alts : []).filter(isObj);
      const list = alts.length ? alts : [{ chance: 1, enemy: w.enemy, pack: w.pack, stats: w.stats }];
      let sum = 0;
      for (const a of list) sum += Math.max(num(a.chance, 1), 0);
      const branches = [];
      for (const a of list) {
        const p = alts.length ? (sum > 0 ? Math.max(num(a.chance, 1), 0) / sum : 0) : 1;
        const d = defOf(String(a.enemy == null ? '' : a.enemy), a.stats);
        if (p > 0) branches.push({ p, d, spawned: 0, next: num(w.t, 0), done: !d });
      }
      waves.push({
        t: num(w.t, 0), until: w.until == null || w.until === '' ? null : num(w.until, 0), count: trunc(num(w.count, 0)),
        burst: Math.max(trunc(num(w.burst, 5)), 1), every: num(w.every, 0), respect: w.respect_cap !== false,
        hell: w.channel === 'hell', elite: w.elite ? String(w.elite) : '', branches,
      });
    }
    function hellIds(rows) {
      const s = new Set();
      for (const x of rows) s.add(x.d.id);
      const t = clock();
      for (const w of waves) {
        if (!w.hell || t < w.t || (w.until != null && t >= w.until)) continue;
        for (const b of w.branches) if (!b.done && b.d) s.add(b.d.id);
      }
      return s;
    }
    /** WaveDirector._channel_room: the regular cap less everything that is not hell, or the hell share less the hell load. */
    function channelRoom(hell) {
      const cap = capNow();
      const hl = loadOf(hellIds(rowsAt(clock(), true)));
      return hell ? hellFrac() * cap - hl : cap - (loadAll() - hl);
    }
    /** WaveDirector._tick_waves / _wave_burst, per branch: a burst each time the clock passes its next time, cut to what
     *  count still owes, the hard cap and (respect_cap) the channel's room, at least one while there is any room. */
    function tickWaves() {
      const t = clock();
      for (const w of waves) {
        if (t < w.t) continue;
        let room = null;
        for (const b of w.branches) {
          if (b.done) continue;
          if (w.until != null && t >= w.until) { b.done = true; continue; }
          if (w.count > 0 && b.spawned >= w.count) { b.done = true; continue; }
          let fired = 0;
          while (t >= b.next && fired < 8) {
            fired++;
            let n = w.burst;
            if (w.count > 0) n = Math.min(n, w.count - b.spawned);
            n = Math.min(n, Math.floor(hard - bodies()));
            if (w.respect) {
              if (room === null) room = channelRoom(w.hell);
              n = room > 0 ? Math.min(n, Math.max(Math.ceil(room / Math.max(b.d.share, 0.05)), 1)) : 0;
            }
            const came = n > 0 ? n : 0;
            if (came > 0) { add(b.d, b.p * came, w.elite && colourOpen() ? 'mod' : 'reg'); b.spawned += came; }
            if (w.every <= 0) { if (came > 0) b.done = true; else b.next = t + burstEvery / EST_HZ; break; }
            b.next += w.every;
            if (w.count > 0 && b.spawned >= w.count) { b.done = true; break; }
          }
          if (!b.done && fired >= 8 && t >= b.next) b.next = t;
        }
      }
    }

    // ---- the elite modifiers, the Elites, the swarms, the bosses
    const held = [];                   // elite spawns asked for before colour came: {enemy, weights, stats, p}
    let heldRetry = 0;
    const timers = [];                 // elite_every: {next, mean, enemy, weights, stats, p}
    /** WaveDirector._spawn_elite: the named creature, or a roster row's by its elite_weight, wearing a modifier, arriving
     *  as the formats say; held until colour comes. */
    function spawnElite(enemy, weights, stats, p) {
      if (!colourOpen()) { held.push({ enemy, weights, stats, p }); return; }
      const st = isObj(stats) ? stats : {};
      let n = 0, id = '';
      const picks = pickShares(enemy, weights);
      if (!picks.length) {
        const cands = openRows(rowsAt(clock(), null)).filter((c) => c.x.d.canBeElite && c.x.d.eliteWeight > 0);
        let sum = 0;
        for (const c of cands) sum += c.x.d.eliteWeight;
        for (const c of cands) {
          const d = Object.keys(st).length ? defOf(c.x.d.id, st) : c.x.d;
          if (!d) continue;
          const pack = Math.max(trunc(num(c.x.r.pack, d.pack)), 1);
          const m = p * (c.x.d.eliteWeight / sum) * eliteCount(d.formats, pack);
          add(d, m, 'mod'); n += m; if (!id) id = d.id;
        }
      } else {
        for (const pk of picks) {
          const d = defOf(pk.id, st);
          if (!d) continue;
          const m = p * pk.share * eliteCount(d.formats, d.pack);
          add(d, m, 'mod'); n += m; if (!id) id = d.id;
        }
      }
      if (n > 0) marks.push({ t: clock(), kind: 'mod', id, n });
    }
    function spawnEliteBoss(enemy, weights, stats, p) {
      let n = 0, id = '';
      for (const pk of pickShares(enemy, weights)) {
        const d = defOf(pk.id, stats);
        if (!d) continue;
        add(d, p * pk.share, 'elite'); n += p * pk.share; if (!id) id = d.id;
      }
      if (n > 0) marks.push({ t: clock(), kind: 'elite', id, n });
    }
    function startBoss(enemy, weights, stats) {
      const picks = pickShares(enemy, weights).filter((pk) => defOf(pk.id, stats));
      if (!picks.length) return;
      let share = 0;
      for (const pk of picks) {
        const d = defOf(pk.id, stats);
        bump(cum, d.id, pk.share);
        share += pk.share * d.share;
      }
      cat.boss += 1;
      bossAlive = { share };
      phase = 1; phaseLeft = bossSteps;
      fight = { t: clock(), boss: picks[0].id, seconds: bossSteps / EST_HZ, portal: portalSteps / EST_HZ, before: total() - 1, spawned: 0, minions: 0, brood: [] };
      // what the boss's own script brings in the fight (its spawn_ring), by the boss's share when the event names several
      for (const pk of picks) {
        const d = defOf(pk.id, stats);
        for (const b of bossBrood(d.script, d.cooldown, bossSteps / EST_HZ, pace)) fight.brood.push({ step: play + Math.max(1, Math.round(b.t * EST_HZ)), id: b.id, n: b.n * pk.share });
      }
      fight.brood.sort((a, b) => a.step - b.step);
      marks.push({ t: clock(), kind: 'boss', id: picks[0].id, n: 1 });
    }
    function runEvent(ev, p) {
      const stats = isObj(ev.stats) ? ev.stats : {};
      switch (String(ev.type == null ? '' : ev.type)) {
        case 'elite': spawnElite(ev.enemy, ev.weights, stats, p); break;
        case 'elite_every': {
          const iv = ev.interval;
          const lo = Array.isArray(iv) && iv.length ? num(iv[0], 90) : num(iv, 90);
          const hi = Array.isArray(iv) && iv.length ? num(iv[iv.length - 1], 90) : lo;
          timers.push({ next: clock(), mean: (lo + hi) / 2, enemy: ev.enemy, weights: ev.weights, stats, p });
          break;
        }
        case 'swarm': {
          let picks = pickShares(ev.enemy, ev.weights);
          if (!picks.length && o.skin) picks = [{ id: String(o.skin), share: 1 }];
          const n = Math.min(p * Math.max(trunc(num(ev.count, 40)), 0), Math.max(MAX_BODIES - bodies(), 0));
          let id = '';
          for (const pk of picks) { const d = defOf(pk.id, stats); if (d) { add(d, n * pk.share, 'reg'); if (!id) id = d.id; } }
          if (n > 0 && id) marks.push({ t: clock(), kind: 'swarm', id, n });
          break;
        }
        case 'boss':
          if (p >= 0.5) startBoss('enemy' in ev ? ev.enemy : o.boss, ev.weights, stats);
          break;
        case 'elite_boss': spawnEliteBoss(ev.enemy, ev.weights, stats, p); break;
        default: break;
      }
    }
    const events = evList.map((ev, i) => ({ ev, i, t: isObj(ev) ? Math.max(num(ev.t, 0), 0) : 0 }))
      .filter((e) => isObj(e.ev) && num(e.ev.chance, 1) > 0)
      .sort((a, b) => a.t - b.t || a.i - b.i);
    let evI = 0;
    const bossIds = evList.filter((ev) => isObj(ev) && ev.type === 'boss' && typeof ev.enemy === 'string' && byId[ev.enemy]).map((ev) => ev.enemy);
    let lastEliteBoss = null;
    for (const ev of evList) if (isObj(ev) && ev.type === 'elite_boss') lastEliteBoss = ev;
    /** WaveDirector._process_events: the events due, the elite_every timers, one held elite a second, endless's clocks. */
    function processEvents() {
      const t = clock();
      while (evI < events.length) {
        const e = events[evI];
        if (e.t > t) break;
        evI++;
        runEvent(e.ev, Math.min(Math.max(num(e.ev.chance, 1), 0), 1));
        if (phase !== 0) return;
      }
      for (const tm of timers) {
        if (t >= tm.next) {
          if (!colourOpen()) { tm.next = t + 1; continue; }
          tm.next = t + tm.mean;
          spawnElite(tm.enemy, tm.weights, tm.stats, tm.p);
        }
      }
      if (held.length && t >= heldRetry) {
        heldRetry = t + 1;
        if (colourOpen()) { const h = held.shift(); spawnElite(h.enemy, h.weights, h.stats, h.p); }
      }
      if (endless) {
        if (t >= enNextElite) {
          if (colourOpen()) { enNextElite = t + SL * 0.15; spawnElite('', null, {}, 1); } else enNextElite = t + 1;
        }
        if (t >= enNextBoss && o.boss) {
          enNextBoss = t + SL; enNextEliteBoss = t + SL * 0.5;
          const id = bossIds.length ? bossIds[enBossI % bossIds.length] : String(o.boss);
          enBossI++;
          runEvent({ type: 'boss', enemy: id }, 1);
        }
        if (enNextEliteBoss > 0 && t >= enNextEliteBoss && lastEliteBoss && pickShares(lastEliteBoss.enemy).length) {
          enNextEliteBoss = 0;
          runEvent({ type: 'elite_boss', enemy: lastEliteBoss.enemy }, 1);
        }
      }
    }

    // ---- the specials' clock (WaveDirector._tick_specials: one countdown, started once the last one is dead)
    const spBlock = isObj(tl.specials) ? tl.specials : {};
    const spOn = Object.keys(spBlock).length > 0;
    const spFrom = num(spBlock.from, SL * 0.5);
    const spIv = Array.isArray(spBlock.interval) && spBlock.interval.length ? spBlock.interval : [20, 40];
    const spSteps = Math.max(1, Math.round(((num(spIv[0], 20) + num(spIv[spIv.length - 1], 40)) / 2) * EST_HZ));
    const spMax = trunc(num(spBlock.max_alive, 1));
    let spLeft = -1;
    function tickSpecials() {
      if (!spOn) return;
      if (stage === 0 && clock() < spFrom) return;
      const pool = [];
      for (const row of Array.isArray(spBlock.pool) ? spBlock.pool : []) {
        const id = isObj(row) ? String(row.enemy == null ? '' : row.enemy) : String(row);
        const st = isObj(row) ? trunc(num(row.stage, 1)) : 1;
        if (byId[id] && stage + 1 >= st) pool.push(id);
      }
      if (!pool.length) return;
      if (spLive.length >= spMax) { spLeft = -1; return; }
      if (spLeft < 0) spLeft = spSteps;
      spLeft--;
      if (spLeft > 0) return;
      spLeft = -1;
      const tv = turnoverNow();
      const life = tv > 0 ? Math.max(1, Math.round(EST_HZ / tv)) : Infinity;
      let share = 0;
      for (const id of pool) { bump(cum, id, 1 / pool.length); share += defOf(id, null).share / pool.length; }
      cat.special += 1;
      spLive.push({ share, die: play + life });
      marks.push({ t: clock(), kind: 'special', id: pool.join('/'), n: 1 });
    }

    // ---- the roster's burst (WaveDirector._spawn_burst / _burst_from) and the portal's one wave
    function burstRows(list, room, left) {
      const t = now();
      const rows = list.map((c) => ({ w: rowWeight(c.x.r, t, lateT), s: Math.max(c.x.d.share, 0.05), pack: c.x.pack, single: c.x.single, room: c.room }));
      const got = burstAvg(rows, room, bLo, bHi);
      let sum = 0;
      for (const n of got) sum += n;
      const scale = sum > left ? left / sum : 1;
      let used = 0;
      for (let i = 0; i < list.length; i++) { const n = got[i] * scale; add(list[i].x.d, n, 'reg'); used += n; }
      return left - used;
    }
    function spawnBurst() {
      const cap = capNow();
      if (cap <= 0) return;
      const tr = phase === 0 ? now() : now() - 1;
      const hellRows = rowsAt(tr, true);
      const hl = loadOf(hellIds(hellRows));
      const room = cap - (loadAll() - hl);
      let left = hard - bodies();
      if (left <= 0) return;
      const regular = openRows(rowsAt(tr, false));
      if (room > 0 && regular.length) left = burstRows(regular, room, left);
      const hellRoom = hellFrac() * cap - hl;
      if (hellRoom > 0 && left > 0 && hellRows.length) {
        const ho = openRows(hellRows);
        if (ho.length) burstRows(ho, hellRoom, left);
      }
    }
    /** WaveDirector.spawn_portal_wave: `count` bodies of the regular rows as the stage ended, by weight, a pack a draw. */
    function portalWave() {
      if (portalWaveCount <= 0) return;
      const list = openRows(rowsAt(now() - 1, false));
      if (!list.length) return;
      const left = Math.min(portalWaveCount, Math.floor(hard - bodies()));
      if (left <= 0) return;
      const t = now();
      const rows = list.map((c) => ({ w: rowWeight(c.x.r, t, lateT), s: 1, pack: c.x.pack, single: c.x.single, room: Infinity }));
      const got = burstOnce(rows, left);
      for (let i = 0; i < list.length; i++) add(list[i].x.d, got[i], 'reg');
    }

    // ---- the points: one a run second, and one after each boss fight
    const points = [];
    function record(after) {
      const by = {};
      for (const id of Object.keys(cum)) by[id] = [cum[id], col[id] || 0, mod[id] || 0];
      points.push({ t: clock(), after, all: total(), reg: cat.reg, col: cat.col, mod: cat.mod, elite: cat.elite, special: cat.special, boss: cat.boss, minion: cat.minion, kills, alive: bodies(), by });
    }
    record(false);

    const endK = Math.round(end * EST_HZ);
    let guard = 0;
    while ((k < endK || phase !== 0) && guard < 4000000) {
      guard++;
      play++;
      // the hero kills `turnover` of the crowd a second; a special goes at the end of its expected life
      const kd = turnoverNow() / EST_HZ;
      if (kd > 0) for (const a of alive.values()) { const dn = a.n * kd; a.n -= dn; kills += dn; }
      for (let i = spLive.length - 1; i >= 0; i--) if (spLive[i].die <= play) { spLive.splice(i, 1); kills += 1; }
      if (colourAt == null && colourOpen()) colourAt = clock();
      if (phase === 0) {
        k++;
        processEvents();
        if (phase === 0) tickWaves();
      } else if (phase === 1) {
        phaseLeft--;
        while (fight && fight.brood.length && fight.brood[0].step <= play) {
          const b = fight.brood.shift();
          const d = defOf(b.id, null);
          const n = Math.min(b.n, Math.max(MAX_BODIES - bodies(), 0));
          if (d && n > 0) { add(d, n, 'reg'); cat.minion += n; fight.minions += n; }
        }
        if (phaseLeft <= 0) {
          // the boss falls: the portal opens with its wave (WaveDirector._on_boss_died)
          bossAlive = null; kills += 1;
          phase = 2; phaseLeft = portalSteps; portalT = 0;
          portalWave();
        }
      } else {
        phaseLeft--;
        portalT += 1 / EST_HZ;
      }
      if (phase !== 2) tickSpecials();
      spawnStep--;
      if (spawnStep <= 0) { spawnStep = burstEvery; spawnBurst(); }
      if (phase === 2 && phaseLeft <= 0) {
        // the hero walks through: the next stage (or endless, its clocks set again at every portal) at the same second
        stage++;
        if (stage >= NST) {
          endless = true; enBossI = 0;
          enNextBoss = clock() + SL; enNextElite = clock() + SL * 0.15; enNextEliteBoss = clock() + SL * 0.5;
        }
        phase = 0;
        fight.spawned = total() - fight.before - 1;
        delete fight.brood;
        fights.push(fight);
        fight = null;
        record(true);
        continue;
      }
      if (k % EST_HZ === 0 && (phase === 0 || points[points.length - 1].t !== clock())) record(false);
    }

    const last = points[points.length - 1].by;
    const ids = Object.keys(last).sort((a, b) => last[b][0] - last[a][0] || (a < b ? -1 : a > b ? 1 : 0));
    return { points, ids, marks, fights, colourAt, assume: { turnover: tvCurve || tvStages || tvFlat, bossSeconds: bossSteps / EST_HZ, portalSeconds: portalSteps / EST_HZ, end } };
  }

  /** The estimate's point at run second t: the last one at or before it (at a boss fight's own second the point after
   *  the fight, or with `beforeFight` the one before it; past that second, the point after). */
  function estimateAt(est, t, beforeFight) {
    const pts = est && est.points ? est.points : [];
    if (!pts.length) return null;
    if (t < pts[0].t) return pts[0];
    let lo = 0, hi = pts.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (pts[mid].t <= t) lo = mid; else hi = mid - 1;
    }
    let i = lo;
    if (beforeFight && pts[i].t === t) while (i > 0 && pts[i - 1].t === pts[i].t) i--;
    return pts[i];
  }

  const api = {
    DEF, FORMULA_DEF, isObj, num, clamp, round, samplePoints, formulaAt, curveMode, curveMult, hasCurve, hpTimeMult, dmgTimeMult,
    stageLength, stages, runEnd, stageAt, stageMult, rowWeight, keyframesOf, convertRow, normaliseRoster, newRowId,
    defaultKnockback, baseNumbers, knockbackOf, creatureAt, otherOverrides, seedPoints, getPath,
    MAX_BODIES, EST_HZ, EST_DEF, pickShares, eliteCount, burstOnce, burstAvg, bossBrood, spawnEstimate, estimateAt,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  return api;
})();
