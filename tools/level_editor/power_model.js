'use strict';
// Pass 83 (lane SCALE): the page-free maths of the hero's power level and of the creatures' HP by power, mirrored from the
// game (game/core/systems/HeroPower.gd, game/core/data/WaveTimeline.gd power_hp_factor). The Settings tab's "Hero power"
// card (power_card.js) draws from it; selftest_SCALE83.py runs it under Node and checks it against the GDScript.
const PowerModel = (() => {
  /** HeroPower.BASE_DPS / BASE_EHP / SUSTAIN_SECONDS: a fresh level-1 Drifter with the Revolver (power 1). */
  const BASE_DPS = 20.4;
  const BASE_EHP = 100;
  const SUSTAIN_SECONDS = 30;
  /** WaveTimeline.POWER_HP_SCALING_DEFAULT / POWER_HP_MAX_DEFAULT. */
  const SCALING_DEFAULT = 1;
  const MAX_DEFAULT = 10;
  /** The power of the probe's tuned builds when each boss arrives (game/tools/_p83_SCALE_boss_probe.gd, pass 83): the
   *  chart's marks. */
  const TYPICAL = [{ at: 'level 1', power: 1 }, { at: 'King 7:10', power: 3.5 }, { at: 'Gila 14:20', power: 9 }, { at: 'Brander 21:30', power: 23 }];

  const num = (v, d) => (typeof v === 'number' && isFinite(v) ? v : (v != null && v !== '' && isFinite(Number(v)) ? Number(v) : d));
  const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

  /** HeroPower.ehp: (max HP + shield + 30 s x (regen + lifesteal a second, under its cap)) / ((1 - armour) x (1 - evade)). */
  function ehp(s, dps) {
    const st = s || {};
    const mh = num(st.max_hp, 100);
    const hp = mh + Math.max(num(st.shield_max, 0), 0);
    const regen = Math.max(num(st.regen, 0), 0);
    const ls = Math.min(Math.max(num(st.lifesteal, 0), 0) * Math.max(dps || 0, 0), mh * num(st.lifesteal_cap, 0.04));
    const dr = clamp(num(st.damage_reduction, 0), 0, 0.8);
    const ev = clamp(num(st.evade, 0), 0, 0.9);
    return (hp + SUSTAIN_SECONDS * (regen + ls)) / ((1 - dr) * (1 - ev));
  }

  /** HeroPower.power_from: sqrt((full DPS / BASE_DPS) x (effective HP / BASE_EHP)). */
  const powerFrom = (dps, eff) => Math.sqrt(Math.max(dps, 0) / BASE_DPS * Math.max(eff, 0) / BASE_EHP);

  /** WaveTimeline.power_hp_factor: power ^ (scaling - 1) held between 1 / ceiling and the ceiling; 1 at scaling 1. */
  function hpFactor(scaling, ceiling, power) {
    const s = num(scaling, SCALING_DEFAULT);
    if (Math.abs(s - 1) < 1e-6) return 1;
    const hi = Math.max(num(ceiling, MAX_DEFAULT), 1);
    return clamp(Math.pow(Math.max(num(power, 1), 0.01), s - 1), 1 / hi, hi);
  }

  /** The map's two numbers with the game's defaults. */
  function scalingOf(tl) {
    return { scaling: num(tl && tl.power_hp_scaling, SCALING_DEFAULT), max: num(tl && tl.power_hp_max, MAX_DEFAULT),
      present: !!tl && tl.power_hp_scaling != null && tl.power_hp_scaling !== '' };
  }

  /** The chart's curve: [{p, f}] on a log power axis from 1 to `hi`. */
  function series(scaling, ceiling, hi, n) {
    const N = n || 120, out = [];
    for (let k = 0; k <= N; k++) {
      const p = Math.pow(hi || 64, k / N);
      out.push({ p, f: hpFactor(scaling, ceiling, p) });
    }
    return out;
  }

  const api = { BASE_DPS, BASE_EHP, SUSTAIN_SECONDS, SCALING_DEFAULT, MAX_DEFAULT, TYPICAL, ehp, powerFrom, hpFactor, scalingOf, series, num };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  return api;
})();
