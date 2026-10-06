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

  const api = {
    DEF, FORMULA_DEF, isObj, num, clamp, round, samplePoints, formulaAt, curveMode, curveMult, hasCurve, hpTimeMult, dmgTimeMult,
    stageLength, stages, runEnd, stageAt, stageMult, rowWeight, keyframesOf, convertRow, normaliseRoster, newRowId,
    defaultKnockback, baseNumbers, knockbackOf, creatureAt, otherOverrides, seedPoints, getPath,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  return api;
})();
