// The inspector (pass 53, pass 54): the form for whatever is selected on the timeline. Every field of the schema for that
// item, typed, with the creature's own numbers as placeholders under the overrides so Garry sees what he is overriding;
// with nothing selected it lists the validation issues (each a button that selects the item). Pass 54: a roster row's
// presence points and order buttons, the Elite overrides as the variance block with colour swatches, the HP x / ATK x
// curves with their mode switch, and the Share band's table. Pass 57: a note under a row's, a wave's or a swarm's Pattern
// field: for Ring how many of the creature make a thick ring and how many really come at once, for In front where from.
// Pass 58: HP and Damage default to the row's own numbers at its start (R1), and a green line under From / Until (a
// wave's and an event's under the creature) says them, kept up to date while the bar is dragged (live()); the size as a
// range; the Colour group (a hue range, the sliders and the creature tinted as the game tints it, its coloured special
// too); the curves' inspector compares the intended curve with what the rows really carry. A box being typed in commits
// before the form is drawn again, and an Overrides block opened by hand stays open.
'use strict';

const Inspector = (() => {
  const { el, fmtT, fmtN, clear } = U;
  // pass 58: what follows the dragged bar without a new form: the From box, the title, the row's fixed HP and ATK
  let liveFns = [];

  /** Bring the live parts of the form up to date (the timeline calls it on every move of a drag): cheap, in place. */
  function live() {
    for (const f of liveFns) {
      try { f(); } catch (_) { /* a part whose item is gone: the next render drops it */ }
    }
  }

  function render(container) {
    Forms.closePop();
    const focused = container.contains(document.activeElement) ? document.activeElement : null;
    const active = focused ? focused.dataset.path : null;
    const scroll = container.scrollTop;
    const sameItem = container.dataset.sel === App.selKey();
    // the review of pass 58: a box still being typed in commits before the form goes. Its blur fires 'change', whose apply
    // draws this inspector itself; left to the clear below, that commit and its draw ran from inside the clear, which
    // then threw NotFoundError half way. Committed here, the draw it makes is whole, and the one below draws it again.
    if (focused && typeof focused.blur === 'function') focused.blur();
    liveFns = [];
    clear(container);
    container.dataset.sel = App.selKey();
    const sel = App.S.sel;
    const item = App.selected();
    if (!sel || !item) issues(container);
    else if (sel.kind === 'roster') rosterForm(container, item, sel.i);
    else if (sel.kind === 'wave') waveForm(container, item, sel.i);
    else if (sel.kind === 'event') eventForm(container, item, sel.i);
    else if (sel.kind === 'cap') capForm(container);
    else if (sel.kind === 'hp') curveForm(container, 'hp_curve');
    else if (sel.kind === 'dmg') curveForm(container, 'damage_curve');
    // pass 84 (lane TIMELINE): the floor curve and the portal after a boss
    else if (sel.kind === 'floor') floorForm(container);
    else if (sel.kind === 'portal') portalForm(container);
    else if (sel.kind === 'specials') blockForm(container, 'Specials', 'the specials\' clock: one at a time, a random interval after the last one dies', Forms.specialsBlock(App.tl()), 'specials');
    else if (sel.kind === 'paths') blockForm(container, 'Mutation offers', 'when each stage\'s mutation offers fall due: each comes at the hero\'s next level-up, in place of the three cards', Forms.pathTimesBlock(App.tl()), 'paths');
    else if (sel.kind === 'pickups') blockForm(container, 'Power-up drops', 'what kills drop and how often', Forms.pickupsBlock(App.tl()), 'pickups');
    // the same item drawn again (an edit in its form) keeps its place in a long form
    if (sameItem) container.scrollTop = scroll;
    if (active) { const again = container.querySelector(`[data-path="${CSS.escape(active)}"]`); if (again) again.focus({ preventScroll: true }); }
  }

  // ------------------------------------------------------------------ pieces

  /** The form's head; returns the title element (a drag keeps it up to date, pass 58). */
  function header(container, kind, title, key, actions, sub) {
    const titleEl = el('div', { class: 'insp-title', text: title });
    const h = el('div', { class: 'insp-head' }, el('div', { class: 'insp-kind', text: kind }), titleEl);
    const acts = el('div', { class: 'insp-actions' });
    for (const a of actions || []) acts.appendChild(el('button', { class: 'btn small' + (a.danger ? ' danger' : '') + (a.cls ? ' ' + a.cls : ''), type: 'button', text: a.text, title: a.title || '', disabled: !!a.disabled, onclick: a.onclick }));
    acts.appendChild(el('button', { class: 'btn small ghost', type: 'button', text: '✕', title: 'close (Esc)', onclick: () => App.select(null) }));
    h.appendChild(acts);
    if (sub) h.appendChild(el('div', { class: 'insp-sub', text: sub }));
    container.appendChild(h);
    const m = App.issuesFor(key);
    if (m) container.appendChild(el('div', { class: 'insp-issues ' + m.level }, m.msgs.map((x) => el('div', { text: x }))));
    return titleEl;
  }

  /** Keep a run-clock field (From, Until, At) and the title in step with a drag (pass 58). */
  function liveTimes(container, titleEl, titleFn, obj, keys) {
    liveFns.push(() => {
      titleEl.textContent = titleFn();
      for (const k of keys) {
        const inp = container.querySelector(`.form [data-path="${k}"]`);
        if (!inp || document.activeElement === inp) continue;
        const v = obj[k];
        inp.value = v == null ? '' : v;
        const hint = inp.parentElement && inp.parentElement.querySelector('.hint');
        if (hint) hint.textContent = v == null || v === '' ? '' : fmtT(v);
      }
    });
  }

  function jsonPeek(container, obj) {
    container.appendChild(el('details', { class: 'json-peek' }, el('summary', { text: 'JSON as it will be written' }), el('pre', { text: JSON.stringify(obj, null, 2) })));
  }

  function listActions() {
    return [
      { text: 'Duplicate', title: 'Ctrl+D', onclick: () => App.duplicateSelected() },
      { text: 'Delete', title: 'Delete key', danger: true, onclick: () => App.deleteSelected() },
    ];
  }

  function section(title, help) {
    return el('div', { class: 'fsection' }, el('h3', { text: title, title: help || '' }));
  }

  /** The row for one field of FIELDS.<kind>, by type; `ctx` carries the creature for variant / overrides. */
  function fieldFor(def, obj, ctx) {
    switch (def.type) {
      case 'enemy':
        return Forms.row(def, Forms.enemyPick(obj[def.key], (v) => App.apply(() => {
          U.setKey(obj, def.key, v);
          // a creature change drops a variant code the new creature does not have
          if (obj.variant && !App.variantOk(v, obj.variant)) delete obj.variant;
        }), { prefer: ctx && ctx.prefer, emptyLabel: ctx && ctx.allowEmpty ? '(none)' : undefined, path: (ctx && ctx.pathPrefix ? ctx.pathPrefix + '.' : '') + def.key }));
      case 'variant':
        return Forms.row(def, Forms.variantSelect(ctx.enemyId, obj.variant, (v) => App.apply(() => U.setKey(obj, 'variant', v)), { path: (ctx && ctx.pathPrefix ? ctx.pathPrefix + '.' : '') + 'variant' }));
      case 'overrides':
        return overridesBlock(obj, def.key, ctx.enemyId, (ctx && ctx.pathPrefix ? ctx.pathPrefix + '.' : '') + def.key, ctx);
      default:
        return Forms.fieldRow(def, obj, { pathPrefix: ctx && ctx.pathPrefix, placeholder: ctx && ctx.placeholders ? ctx.placeholders[def.key] : undefined, allowRandom: def.type === 'elite', note: ctx && ctx.note });
    }
  }

  // ------------------------------------------------------------------ the Pattern field's notes (pass 57)

  const b = (text) => el('b', { text: String(text) });
  /** "a Skeleton", "an Imp", "The Brander". */
  const aName = (name) => (/^the\s/i.test(String(name)) ? String(name) : (/^[aeiou]/i.test(String(name)) ? 'an ' : 'a ') + name);

  /** What a row, a wave (its alternatives, else its own creature) or an event spawns: [{c, stats}] for the known
   *  creatures, distinct by creature and body radius, in order. An event with no creature named spawns the map's walker
   *  (WaveDirector's swarm). */
  function spawnedBy(kind, obj) {
    const out = [];
    const add = (id, stats) => {
      const c = App.creature(id);
      if (!c) return;
      const st = U.isObj(stats) ? stats : {};
      // pass 58 (R2): a size range moves the body's radius with the rolled size (radius × size / its own size): count
      // with the middle of the range; one plain size leaves the radius as it was
      const sr = Model.sizeRange(st.size);
      const follow = sr && sr.range && Number(c.size) > 0 ? ((sr.min + sr.max) / 2) / Number(c.size) : 1;
      const radius = st.radius != null ? Number(st.radius) : Number(c.radius) * follow;
      if (!out.find((x) => x.c.id === c.id && x.radius === radius)) out.push({ c, stats: st, radius });
    };
    if (kind === 'wave') {
      const alts = Array.isArray(obj.alts) && obj.alts.length ? obj.alts : [obj];
      for (const a of alts) add(a.enemy, a.stats);
    } else if (kind === 'event') {
      let ids = U.idList(obj.enemy);
      const skins = App.S.map && U.isObj(App.S.map.skins) ? Object.values(App.S.map.skins) : [];
      if (!ids.length && skins.length) ids = [String(skins[0])];
      for (const id of ids) add(id, obj.stats);
    } else add(obj.enemy, obj.stats);
    return out;
  }

  /** "about 105 Skeletons (70 close one row)" for each creature, joined by "or" (three at most). */
  function ringCounts(list, radius) {
    const parts = [];
    list.slice(0, 3).forEach((x, k) => {
      const rc = U.ringCount(x.radius, radius);
      if (k > 0) parts.push(' or ');
      parts.push('about ', b(rc.thick), ` ${U.plural(x.c.name)} (${rc.row} close one row)`);
    });
    if (list.length > 3) parts.push(' …');
    return parts;
  }

  /** The note under the Pattern field (pass 57): for Ring, how many make "a thick ring with few gaps" (Garry) for the
   *  creature(s), from the body radius (U.ringCount), and how many this row, wave or swarm really sends at once; for In
   *  front, where they come from. Null for the other patterns. */
  /** Pass 69 (lane EN): a swarm set to Special, in words: what each creature it brings comes as (its Special block's
   *  numbers, the map's defaults where it leaves one empty), or why one comes plain. */
  function specialNote(ev) {
    if (!ev.special) return null;
    const tl = App.tl();
    const defaults = U.isObj(tl.special_defaults) ? tl.special_defaults : {};
    const out = [b('Special: ')];
    const shares = App.eventShares(ev);
    if (!shares.length) return [b('Special: '), 'pick a creature: each one this swarm brings comes as its coloured special.'];
    shares.slice(0, 3).forEach((s, k) => {
      const c = App.creature(s.id);
      if (!c) return;
      if (k) out.push(' · ');
      const vs = Model.varianceSpecial(c, ev.stats, defaults);
      const hasVar = U.isObj(c.variance) && Object.keys(c.variance).length > 0;
      if (!hasVar) { out.push(`${U.theName(c.name)} has no variance block: it comes plain`); return; }
      const v = (key) => U.fmtN(Model.specialValue(vs.sp, defaults, key), 2);
      out.push(`${U.theName(c.name)} comes with HP ×${v('hp')}, ATK ×${v('damage')}, size ×${v('size')}, XP ×${v('xp')}, glow ${v('glow')}${vs.sp.tint ? ` in ${vs.sp.tint}` : ''}`);
    });
    out.push(`; for sure, even before Colour after kills, and no SWARM! banner. Its numbers are its Special block on the Enemies tab.`);
    return out;
  }

  function patternNote(kind, obj) {
    const tl = App.tl();
    const pattern = obj.pattern == null || obj.pattern === '' ? (kind === 'event' ? 'ring' : 'pack') : String(obj.pattern);
    const hard = Number(tl.hard_cap) || 300;
    const list = spawnedBy(kind, obj);
    if (pattern === 'in_front') {
      const what = kind === 'roster' ? 'this row\'s pack comes' : kind === 'wave' ? 'every burst comes' : `all ${Number(obj.count) || 40} come`;
      return [b('In front: '), `${what} from the top of the screen, each at its own point 19–24 m up within ±45° of straight up, whatever Settings → Spawning → Spawn side says.`];
    }
    if (pattern !== 'ring') return null;
    if (kind === 'event') {
      if (obj.type !== 'swarm') return null;
      if (!list.length) return [b('Ring (16 m, the swarm\'s own): '), 'pick a creature to see how many make a thick ring.'];
      return [b('Ring (16 m, the swarm\'s own): '), ...ringCounts(list, U.SWARM_RING_RADIUS), ' make a thick ring with few gaps 16 m round the hero; this swarm sends ', b(Number(obj.count) || 40), ' (Count), on top of the cap.'];
    }
    if (!list.length) return [b('Ring: '), 'pick a creature to see how many make a thick ring with few gaps, 11.7 m round the hero.'];
    const head = [b('Ring: '), ...ringCounts(list, U.RING_RADIUS), ' make a thick ring with few gaps, 11.7 m round the hero (the arena\'s ring × 1.3).'];
    const thick = U.ringCount(list[0].radius).thick;
    if (kind === 'roster') {
      const x = list[0];
      const pack = Math.max(1, Math.round(Number(obj.pack != null ? obj.pack : (x.stats.pack != null ? x.stats.pack : x.c.pack_size)) || 1));
      const rawShare = x.stats.cap_share != null ? x.stats.cap_share : x.c.cap_share;
      const share = Math.max(rawShare == null || isNaN(Number(rawShare)) ? 1 : Number(rawShare), 0.05);
      const burstMax = Number(tl.burst_max != null ? tl.burst_max : 20);
      // the most one burst holds of this creature (WaveDirector._burst_from cuts a row's spawn to the burst's load)
      const burstCap = U.ringAtOnce(1e9, share, burstMax);
      const why = `Burst max ${burstMax} load units, ${aName(x.c.name)} takes ${fmtN(share)}`;
      const useWave = `for a thick ring use a wave with Per burst about ${thick} and Respect the cap off`;
      // a creature with a live limit: the row is not drawn while that many live (WaveDirector._roster_open)
      const maxAlive = Math.round(Number(x.stats.max_alive != null ? x.stats.max_alive : x.c.max_alive) || 0);
      const limit = maxAlive > 0 ? ` The row is never drawn while ${maxAlive} ${maxAlive === 1 ? 'is' : 'are'} alive (Max alive).` : '';
      if (pack > burstCap) return [...head, ` This row spawns its pack (${pack}) at once, but never more than one burst holds: at most `, b(burstCap), ` here (${why}). So ${useWave}.${limit}`];
      const lead = [...head, ' This row spawns its pack (', b(pack), ') at once, as far as the cap has room'];
      if (pack >= thick) return [...lead, `.${limit}`];
      if (burstCap >= thick) return [...lead, `: set Pack to about ${thick} for a thick ring.${limit}`];
      return [...lead, `; one burst holds at most ${burstCap} here (${why}), so ${useWave}.${limit}`];
    }
    // a wave: its burst is one ring, cut by the count, the hard cap and, when it respects one, the cap's free room
    const burst = Math.max(1, Math.round(Number(obj.burst == null ? 5 : obj.burst) || 1));
    const count = Number(obj.count == null ? 20 : obj.count) || 0;
    const forWhom = list.length > 1 ? ` for the ${U.plural(list[0].c.name)}` : '';
    const parts = burst >= thick ? [...head, ' Per burst (', b(burst), `) makes one${forWhom}.`] : [...head, ` Set Per burst to about ${thick}${forWhom} (now `, b(burst), ').'];
    if (count > 0 && count < burst) parts.push(` Total count (${count}) cuts the burst to ${count}.`);
    parts.push(obj.respect_cap === false
      ? ` Respect the cap is off: the whole burst comes at once (the hard cap of ${hard} bodies still holds).`
      : ' With Respect the cap on, a burst is cut to the free room under the cap; turn it off for the whole ring at once (the hard cap still holds).');
    return parts;
  }

  // ------------------------------------------------------------------ overrides

  function countLeaves(o) {
    if (!U.isObj(o)) return o === undefined ? 0 : 1;
    let n = 0;
    for (const v of Object.values(o)) n += countLeaves(v);
    return n;
  }

  /** How a coloured elite drawn from this row arrives, as the game rolls it (WaveDirector._elite_format): the three
   *  chances normalised, a missing one 0 once any is set, all missing = alone. */
  function formatShares(stats) {
    const ef = U.getPath(stats, 'elite_formats');
    const ks = ['single', 'pack', 'ring'];
    if (!U.isObj(ef)) return { single: 1, pack: 0, ring: 0 };
    const w = {};
    let total = 0;
    for (const k of ks) { w[k] = Math.max(0, Number(ef[k]) || 0); total += w[k]; }
    if (total <= 0) return { single: 1, pack: 0, ring: 0 };
    for (const k of ks) w[k] /= total;
    return w;
  }

  /** The grey HP and Damage of a row (pass 58, R1): the creature's own × the curves at the row's start (no curve for an
   *  Elite or a boss); what the row's creatures have when the box is left empty. */
  function rowDefaults(c, t0) {
    const rn = App.rowNumbers(c, {}, t0);
    return { hp: rn.hp, atk: rn.atk, arch: rn.arch };
  }

  /** A row's own HP and ATK (pass 58, R1, Garry: "as I move the enemy bar left and right the actual HP value in the stats
   *  changes to reflect the multiple being applied to it at the point of the start of the enemy wave"): the two numbers
   *  fixed from its start, where each comes from (the creature's own × the curve there, or a number typed in Overrides),
   *  and what a creature of it has in play at that start (× the stage, creature_hp_mult / creature_damage_mult and the
   *  hero level). `from`: 'row' | 'wave' | 'event'. */
  function rowNote(c, stats, t0, from, end) {
    const st = U.isObj(stats) ? stats : {};
    const rn = App.rowNumbers(c, st, t0);
    if (rn.arch !== 'regular') {
      return [el('span', { class: 'rn-main' }, b(`${U.theName(c.name)} is ${rn.arch === 'boss' ? 'a boss' : 'an Elite-archetype mini-boss'}: `), 'its own rules, no time curve (its HP × per stage under ', rn.arch === 'boss' ? 'Boss' : 'Mini-boss', '); the stage multiplier on top.')];
    }
    const at = App.creatureAt(c, st, t0, t0);
    const mult = (k) => (st[k] != null && st[k] !== '' && isFinite(Number(st[k])) && Number(st[k]) !== 1 ? ` × ${fmtN(Number(st[k]), 2)} (${k === 'hp_mult' ? 'HP ×' : 'Damage ×'})` : '');
    const hpSrc = rn.hpOver ? `its own ${fmtN(Number(st.hp), 2)}, typed in Overrides (no curve)` : `${U.theName(c.name)}'s ${fmtN(rn.jsonHp, 2)} × the HP curve ×${fmtN(rn.hpTime, 2)} at ${fmtT(t0)}`;
    const atkSrc = rn.dmgOver ? `its own ${fmtN(Number(st.damage), 2)}, typed in Overrides (no curve)` : `its ${fmtN(rn.jsonDmg, 2)} × the damage curve ×${fmtN(rn.dmgTime, 2)}`;
    return [
      el('span', { class: 'rn-main' }, 'Row HP ', b(fmtN(rn.hp, 2)), ' · ATK ', b(fmtN(rn.atk, 2)), ', fixed from ', b(fmtT(t0)), `, the ${from || 'row'}'s start`),
      el('span', { class: 'rn-sub' }, `HP: ${hpSrc}${mult('hp_mult')}. ATK: ${atkSrc}${mult('damage_mult')}.`),
      el('span', { class: 'rn-play' }, 'In play at its start: HP ', b(fmtN(at.hp, 1)), ' · ATK ', b(fmtN(at.atk, 1)),
        ` (${App.stageName(at.stage)} ×${fmtN(at.stageMult, 2)}, creature ×${fmtN(at.chm, 2)} / ×${fmtN(at.cdm, 2)}, hero level ${App.S.level} ×${fmtN(at.lvHp, 2)} / ×${fmtN(at.lvDmg, 2)}); one it sends in a later stage takes that stage's multiplier instead.`),
      ...longBarNote(rn, t0, end),
    ];
  }

  /** For a row or a wave (`end` given; Infinity = no end) the review's two notes on a long bar (lane WV's fix round): on
   *  a bar longer than three minutes the HP curve has climbed more than 15% by its last second while its creatures keep
   *  the start's numbers (a split bar steps up), and a bar running into endless is fixed afresh at each endless wave. */
  function longBarNote(rn, t0, end) {
    if (end === undefined || rn.arch !== 'regular') return [];
    const tl = App.tl();
    const runEnd = App.runEnd();
    const last = Math.min(Number(end), runEnd);
    const out = [];
    if (!rn.hpOver && last > t0 + LONG_BAR) {
      const later = App.hpTimeMult(last);
      if (later > rn.hpTime * 1.15) out.push(`By ${fmtT(last)} the HP curve says ×${fmtN(later, 2)} while its creatures keep ×${fmtN(rn.hpTime, 2)} all the way: split the bar for a step up.`);
    }
    if (!(Number(end) <= runEnd)) out.push(`In endless it is fixed afresh at each wave (every ${fmtN(Math.max(Number(tl.endless_wave_seconds) || 60, 1), 0)} s), from the wave's start.`);
    return out.length ? [el('span', { class: 'rn-hint' }, out.join(' '))] : [];
  }

  const LONG_BAR = 180;

  /** What an event's creatures carry (lane WV's fix round, WaveDirector.event_numbers): the curves at the second it fires,
   *  or, while a roster row or a wave brings the same creature in the same look, that row's numbers for each half (HP,
   *  ATK) the event's own overrides leave alone; the line names the row. */
  function eventNote(c, stats, t, variant) {
    const st = U.isObj(stats) ? stats : {};
    const en = App.eventNumbers(c.id, variant, st, t);
    if (!en.joined || en.arch !== 'regular') return rowNote(c, st, t, 'event');
    const who = App.sourceName(en.joined);
    const halves = en.hpJoined && en.dmgJoined ? 'its HP and ATK' : en.hpJoined ? 'its HP (the Damage typed here is the event\'s own, at this second)' : 'its ATK (the HP typed here is the event\'s own, at this second)';
    const at = App.creatureAt(c, st, t, t, en);
    return [
      el('span', { class: 'rn-main' }, 'HP ', b(fmtN(en.hp, 2)), ' · ATK ', b(fmtN(en.atk, 2)), ', joining ', b(who), ` (${U.theName(c.name)} from ${fmtT(en.joined.t0)})`),
      el('span', { class: 'rn-sub' }, `At ${fmtT(t)} ${who} brings ${U.theName(c.name)} in the same look, so the creatures this event sends play ${halves}, fixed from ${fmtT(en.hpJoined ? en.hpFrom : en.dmgFrom)}: the same creature with the same numbers as the ones already there. An HP or a Damage typed in Overrides is the event's own instead.`),
      el('span', { class: 'rn-play' }, 'In play: HP ', b(fmtN(at.hp, 1)), ' · ATK ', b(fmtN(at.atk, 1)),
        ` (${App.stageName(at.stage)} ×${fmtN(at.stageMult, 2)}, creature ×${fmtN(at.chm, 2)} / ×${fmtN(at.cdm, 2)}, hero level ${App.S.level} ×${fmtN(at.lvHp, 2)} / ×${fmtN(at.lvDmg, 2)}).`),
    ];
  }

  /** An "Elites every" event's numbers (the review of pass 58): every firing takes the curves at its own second
   *  (WaveDirector._spawn_elite), or the numbers of a row bringing the same creature then (lane WV's fix round), so the
   *  first few firings and their HP and ATK. */
  function firingsNote(c, stats, ev) {
    const st = U.isObj(stats) ? stats : {};
    const times = Model.eliteEveryTimes(ev, 4, App.runEnd());
    const rn0 = App.rowNumbers(c, st, times[0]);
    if (rn0.arch !== 'regular') return rowNote(c, st, times[0], 'event');
    const main = el('span', { class: 'rn-main' }, 'Each firing takes the curves at its own second, or the numbers of a row bringing the same creature then: ');
    let joins = 0;
    times.forEach((t, k) => {
      const en = App.eventNumbers(c.id, ev.variant, st, t);
      if (k) main.appendChild(document.createTextNode(' · '));
      main.append(b(fmtT(t)), ` HP ${fmtN(en.hp, 2)} · ATK ${fmtN(en.atk, 2)}`);
      if (en.joined) { joins++; main.append(el('small', { text: ` (${App.sourceName(en.joined)})` })); }
    });
    const iv = ev.interval;
    const every = Array.isArray(iv) && iv.length ? `${fmtN(Number(iv[0]), 1)}–${fmtN(Number(iv[iv.length - 1]), 1)} s (about the middle here)` : `${fmtN(iv == null ? 90 : Number(iv), 1)} s`;
    return [main, el('span', { class: 'rn-sub' }, `Every ${every}${rn0.hpOver ? '; the HP typed in Overrides takes no curve' : ''}.${joins ? ' A firing in brackets joins that row: the same creature in the same look as the ones it brings, with their numbers.' : ''} Hot Sauce brings them sooner and one held back for colour comes later, with the numbers of that second. In play × the stage then × creature × the hero level then.`)];
  }

  /** The row's numbers where they are always in sight (the review of pass 58: under HP / Damage they sat inside the
   *  Overrides block, which is closed on a row with no overrides): under From / Until on a roster row, under the creature
   *  of a wave (each alternative) and of an event. Redrawn while the bar is dragged. `statsOf` reads the item's stats
   *  afresh (an edit replaces the block). */
  function numbersLine(c, statsOf, t0, from, ev, label, endOf) {
    const box = el('div', { class: 'fhelp fnote rn-note rn-line', 'data-note': 'row-numbers' });
    const fill = () => {
      clear(box);
      const t = Math.max(Number(t0()) || 0, 0);
      const parts = ev && ev.type === 'elite_every' ? firingsNote(c, statsOf(), Object.assign({}, ev, { t }))
        : ev ? eventNote(c, statsOf(), t, ev.variant) : rowNote(c, statsOf(), t, from, endOf ? endOf() : undefined);
      if (label) box.appendChild(el('span', { class: 'rn-who', text: label }));
      for (const x of parts) box.appendChild(typeof x === 'string' ? document.createTextNode(x) : x);
    };
    fill();
    liveFns.push(fill);
    return box;
  }

  /** The `stats` block of `holder[key]` for `creatureId`: every override key, the creature's own value as the placeholder.
   *  `ctx` (pass 58): t0 (a function: the row's start, for the HP / Damage defaults and the note), from ('row' | 'wave' |
   *  'event'), look (a function: the art variant the row plays, for the colour preview). */
  // the review of pass 58: an Overrides block opened (or closed) by hand stays so when the form is drawn again (a drop, an
  // edit); it used to fall back to "open when something is set" every time. Keyed by the item and the block's path.
  const overridesOpen = new Map();

  function overridesBlock(holder, key, creatureId, pathPrefix, ctx) {
    const o = ctx || {};
    const c = App.creature(creatureId);
    const stats = U.isObj(holder[key]) ? holder[key] : {};
    const n = countLeaves(stats);
    const openKey = `${App.selKey()}|${pathPrefix}`;
    const det = el('details', { class: 'overrides', open: overridesOpen.has(openKey) ? overridesOpen.get(openKey) : n > 0 });
    det.addEventListener('toggle', () => overridesOpen.set(openKey, det.open));
    const whose = o.each ? "the first firing's" : o.event ? "what the event's creatures carry" : `the ${o.from || 'row'}'s at its start`;
    det.appendChild(el('summary', {}, el('b', { text: `Overrides · ${n} set` }), el('span', { class: 'muted', text: c ? ` · grey = ${U.theName(c.name)}'s own numbers${o.t0 ? `, HP and Damage ${whose} (the green line above)` : ''}` : '' })));
    const write = (path, v) => App.apply(() => {
      if (!U.isObj(holder[key])) holder[key] = {};
      U.setPath(holder[key], path, v);
      if (!Object.keys(holder[key]).length) delete holder[key];
    });
    const t0 = () => (o.t0 ? Math.max(Number(o.t0()) || 0, 0) : null);
    // the grey HP and Damage: what the box means left empty. A row's: the creature's own × the curves at its start. An
    // event's (lane WV's fix round): the numbers of a row bringing the same creature then, when the event's other
    // override of that half leaves it free to join, else its own at its second.
    const greyOf = (which) => {
      const own = rowDefaults(c, t0())[which];
      if (!o.event) return own;
      const st2 = Object.assign({}, U.isObj(holder[key]) ? holder[key] : {});
      delete st2[which === 'hp' ? 'hp' : 'damage'];
      const en = App.eventNumbers(c.id, o.event.variant, st2, t0());
      return which === 'hp' ? (en.hpJoined ? en.hp : own) : (en.dmgJoined ? en.atk : own);
    };
    for (const group of FIELDS.OVERRIDE_GROUPS) {
      const defs = FIELDS.OVERRIDES.filter((d) => d.group === group);
      if (!defs.length) continue;
      const fs = el('fieldset', { class: 'ogroup' }, el('legend', { text: group }));
      const gh = FIELDS.OVERRIDE_GROUP_HELP[group];
      if (gh) fs.appendChild(el('div', { class: 'muted small ghelp', text: gh }));
      const needs = defs[0].needs;
      if (needs && c && !c[needs]) fs.appendChild(el('div', { class: 'muted small', text: `${U.theName(c.name)} has no ${needs} block: these change nothing for it` }));
      const only = defs.find((d) => d.onlyIf);
      if (only && c && !only.onlyIf(c)) { fs.classList.add('dim'); fs.appendChild(el('div', { class: 'note small', text: `${only.onlyNote}: ${U.theName(c.name)} is not one, so these change nothing for it` })); }
      for (const def of defs) {
        const value = U.getPath(stats, def.path);
        let ph = def.ph ? def.ph(c, App.tl()) : '';
        const path = `${pathPrefix}.${def.path}`;
        // pass 58 (R1): a row's HP and Damage default to the creature's own × the curves at the row's start
        const r1 = c && t0() != null && (def.path === 'hp' || def.path === 'damage');
        if (r1) ph = Model.round(greyOf(def.path === 'hp' ? 'hp' : 'atk'), 2);
        let ctl;
        if (def.type === 'number' || def.type === 'int') ctl = Forms.numberInput(def, value, (v) => write(def.path, v), { placeholder: ph === '' ? '—' : (typeof ph === 'number' ? fmtN(ph, 3) : ph), path });
        else if (def.type === 'bool3') ctl = Forms.bool3Input(def, value, (v) => write(def.path, v), { placeholder: ph, path });
        else if (def.type === 'pickup') ctl = Forms.pickupSelect(value, (v) => write(def.path, v), { path, emptyLabel: ph ? `— (${App.pickup(ph) ? App.pickup(ph).name : ph})` : '—', emptyIcon: ph && App.pickup(ph) ? App.pickup(ph).icon : '' });
        else if (def.type === 'attacks') ctl = attacksControl(stats, c, write, path);
        else if (def.type === 'pickup_weights') ctl = pickupWeightsControl(stats, write, path);
        else if (def.type === 'swatch') ctl = Forms.swatchInput(value, (v) => write(def.path, v), { placeholder: ph, path });
        else if (def.type === 'swatches') ctl = Forms.swatchesInput(value, (v) => write(def.path, v), { placeholder: ph, path });
        else if (def.type === 'size_range') ctl = sizeRangeControl(stats, c, write, path);
        else if (def.type === 'tint') ctl = tintControl(stats, c, write, path, o);
        else ctl = el('span', { class: 'muted', text: def.type });
        if (r1) {
          // the grey number follows the bar while it is dragged
          const inp = ctl;
          const which = def.path === 'hp' ? 'hp' : 'atk';
          liveFns.push(() => { inp.placeholder = fmtN(Model.round(greyOf(which), 2), 3); });
        }
        fs.appendChild(Forms.row(def, ctl, { cls: (value !== undefined ? 'is-set' : '') + (def.type === 'tint' ? ' wide-ctl' : '') }));
      }
      if (group === 'Elite') {
        const fsh = formatShares(stats);
        fs.appendChild(el('p', { class: 'muted small', text: `A coloured elite from this row comes alone ${Math.round(fsh.single * 100)}% · as its pack ${Math.round(fsh.pack * 100)}% · as a ring ${Math.round(fsh.ring * 100)}% (once one chance is set, an empty one counts 0).` }));
      }
      det.appendChild(fs);
    }
    return det;
  }

  // ------------------------------------------------------------------ the size range (pass 58, R2)

  /** Size as one number or a range (Garry: "editable as a kind of a range (between 3-5 for example) and there should be
   *  the default one already set for them so I have a reference"): from / to boxes, the creature's own size and its
   *  variance spread as the grey reference under them. Equal boxes or one box write one number. */
  function sizeRangeControl(stats, c, write, path) {
    const v = U.getPath(stats, 'size');
    const isList = Array.isArray(v);
    const lo = isList ? v[0] : v, hi = isList ? v[v.length - 1] : null;
    const own = c && c.size != null ? Number(c.size) : null;
    const spread = c && U.isObj(c.variance) ? Number(c.variance.size) || 0 : 0;
    const bad = Model.sizeIssues(v).length > 0;
    const a = el('input', { type: 'number', class: 'num short' + (bad ? ' bad' : ''), min: 0.05, step: 0.05, value: lo == null ? '' : lo, placeholder: own == null ? 'from' : fmtN(own, 3), 'data-path': `${path}.0`, title: 'one size, or the smallest of the range' });
    const bx = el('input', { type: 'number', class: 'num short' + (bad ? ' bad' : ''), min: 0.05, step: 0.05, value: hi == null ? '' : hi, placeholder: 'to', 'data-path': `${path}.1`, title: 'the largest of the range (empty: one size)' });
    const fire = () => {
      const x = U.parseNum(a.value), y = U.parseNum(bx.value);
      if (x == null && y == null) return write('size', null);
      if (x == null || y == null) return write('size', x == null ? y : x);
      if (x === y) return write('size', x);
      write('size', [x, y]);
    };
    for (const inp of [a, bx]) {
      inp.addEventListener('change', fire);
      inp.addEventListener('keydown', (e) => { if (e.key === 'Enter') inp.blur(); });
    }
    const sr = Model.sizeRange(v);
    let ref;
    if (!own) ref = 'pick a creature for its own size';
    else if (sr && sr.range && sr.min === sr.max) ref = `a list of one size: every creature exactly ${fmtN(sr.min, 2)} m (no spread), its radius following, as the game reads it; its own: ${fmtN(own, 2)} m${spread ? `, spread ±${Math.round(spread * 100)}%` : ''}`;
    else if (sr && sr.range) {
      // lane WV's fix round: a coloured special is cut at the range's top; an elite modifier's scale still goes on top
      const vs = Model.varianceSpecial(c, stats, App.tl().special_defaults);
      const sp = vs.chance > 0 ? `; a coloured special ×${fmtN(vs.size, 2)} but never past ${fmtN(sr.max, 2)} m` : '';
      ref = `each creature its own size from ${fmtN(sr.min, 2)} to ${fmtN(sr.max, 2)} m (no spread), its radius following${sp}; an elite-modified one × its modifier's scale on top; its own: ${fmtN(own, 2)} m${spread ? `, spread ±${Math.round(spread * 100)}%` : ''}`;
    }
    else ref = `its own: ${fmtN(own, 2)} m${spread ? `, spread ±${Math.round(spread * 100)}% = ${fmtN(own * (1 - spread), 2)}–${fmtN(own * (1 + spread), 2)} m` : ''}${sr ? `; set to ${fmtN(sr.min, 2)} m (the spread still on top)` : ''}`;
    return el('div', { class: 'size-range' },
      el('span', { class: 'interval' }, a, el('span', { class: 'hint', text: 'to' }), bx, el('span', { class: 'hint', text: 'm' })),
      el('div', { class: 'size-ref' + (bad ? ' bad' : ''), text: bad ? Model.sizeIssues(v).join('; ') : ref }));
  }

  // ------------------------------------------------------------------ the colour range (pass 58, R3)

  /** The standing frame of a look (frame 0 of its strip, `cell` px square), scaled to S x S, with each pixel in linear
   *  light: {S, alpha, lin}. One fetch and decode per strip, kept for the page's life. Painted at 192 px: the pictures
   *  show at about 90 px in a row of four and at 240 px when clicked (the review of pass 58: at 58 px a tint was hard to
   *  judge). */
  const PREVIEW_S = 192;
  const frameCache = new Map();
  function standingFrame(url, cell) {
    const key = `${url}|${cell}`;
    if (frameCache.has(key)) return frameCache.get(key);
    const p = new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => {
        try {
          const size = Math.max(1, Math.min(Number(cell) || 128, img.naturalWidth, img.naturalHeight));
          const cv = document.createElement('canvas');
          cv.width = PREVIEW_S; cv.height = PREVIEW_S;
          const ctx = cv.getContext('2d', { willReadFrequently: true });
          ctx.imageSmoothingQuality = 'high';
          ctx.drawImage(img, 0, 0, size, size, 0, 0, PREVIEW_S, PREVIEW_S);
          const d = ctx.getImageData(0, 0, PREVIEW_S, PREVIEW_S).data;
          const n = PREVIEW_S * PREVIEW_S;
          const lin = new Float32Array(n * 3), alpha = new Uint8ClampedArray(n);
          for (let i = 0; i < n; i++) {
            alpha[i] = d[i * 4 + 3];
            for (let j = 0; j < 3; j++) lin[i * 3 + j] = LIN8[d[i * 4 + j]];
          }
          resolve({ S: PREVIEW_S, alpha, lin });
        } catch (e) { reject(e); }
      };
      img.onerror = () => reject(new Error('no strip at ' + url));
      img.src = url;
    });
    frameCache.set(key, p);
    return p;
  }
  // sRGB 0..255 -> linear, and linear 0..1 (4096 steps) -> sRGB 0..255
  const LIN8 = new Float32Array(256).map((_, i) => Model.toLinear(i / 255));
  const SRGB12 = new Uint8ClampedArray(4096).map((_, i) => Math.round(Model.toSrgb(i / 4095) * 255));

  /** Paint `frame` into `canvas` washed with `tint` ([r, g, b] 0..1, as the game feeds it) at `amount` (R3: mix(rgb,
   *  tint, amount × 0.65), in linear light like the billboard shader; Model.tintPixel is the same per pixel). Without a
   *  tint the painting as it is. */
  function paintFrame(canvas, frame, tint, amount) {
    const S = frame.S;
    canvas.width = S; canvas.height = S;
    const ctx = canvas.getContext('2d');
    const out = ctx.createImageData(S, S);
    const k = tint ? Math.min(Math.max(Number(amount) || 0, 0), 1) * 0.65 : 0;
    const t = tint || [0, 0, 0];
    for (let i = 0, n = S * S; i < n; i++) {
      const a = frame.alpha[i];
      if (!a) continue;
      for (let j = 0; j < 3; j++) {
        const v = frame.lin[i * 3 + j] * (1 - k) + t[j] * k;
        out.data[i * 4 + j] = SRGB12[Math.round(Math.min(Math.max(v, 0), 1) * 4095)];
      }
      out.data[i * 4 + 3] = a;
    }
    ctx.putImageData(out, 0, 0);
  }

  /** The strip of the look a row plays: its own art variant, else the creature's default; and its cell. */
  function lookStrip(c, code) {
    const v = code ? (c.variants || []).find((x) => x.code === code && x.ready) : null;
    return { url: v && v.sprite ? v.sprite : c.sprite_play, cell: c.frame_px || 128, code: v ? v.code : (c.play || '') };
  }

  /** Garry: "Add option to change enemy colour (should be a kind of a range) ... I want a version that kind of colours all
   *  the enemies that come out of that wave. I'd like a colour slider and a preview showing the actual enemy." The hue
   *  range on a colour-wheel track with two handles (an end below the start runs through red; ⇄ takes the other side of
   *  the wheel), saturation, brightness and amount sliders, Clear, and the creature's standing frame as the game tints it
   *  at five hues across the range, then the row's coloured special in its darker shade (a click on a picture shows it
   *  larger). A handle or a slider redraws the track at once and the pictures once a frame; the file is written when it
   *  is let go (one undo step). */
  function tintControl(stats, c, write, path, ctx) {
    const cur = Model.tintRange(U.getPath(stats, 'tint'));
    const wrap = el('div', { class: 'tint-ctl' + (cur ? '' : ' unset') });
    const look = c ? lookStrip(c, ctx && ctx.look ? ctx.look() : '') : null;
    const preview = el('div', { class: 'tint-preview' });
    const pics = [];
    const addPic = (label, cls, title) => {
      const cv = el('canvas', { class: 'tint-pic', width: PREVIEW_S, height: PREVIEW_S });
      const cap = el('div', { class: 'tint-cap', text: label });
      // a click shows the picture larger (a click again, smaller)
      const fig = el('figure', { class: 'tint-fig' + (cls ? ' ' + cls : ''), title: (title ? title + '. ' : '') + 'Click to see it larger' }, cv, cap);
      fig.addEventListener('click', () => fig.classList.toggle('big'));
      preview.appendChild(fig);
      pics.push({ cv, cap, fig });
    };
    let frame = null;
    if (!cur) {
      addPic('as painted', 'orig');
      wrap.appendChild(el('div', { class: 'hue-track off', style: `background:${U.hueGradient(0, 360, 0.85, 1, 13)}` }));
      wrap.appendChild(el('div', { class: 'muted small', text: c ? `No colour range: ${U.theName(c.name)} keeps its own random tints (the Elite group).` : 'pick a creature first' }));
      wrap.appendChild(el('div', { class: 'alt-actions' }, el('button', { class: 'btn small', type: 'button', text: 'Add a colour range', 'data-path': path, disabled: !c, onclick: () => write('tint', { hue: [200, 260], sat: Model.TINT_DEF.sat, val: Model.TINT_DEF.val, amount: Model.TINT_DEF.amount }) })));
      if (look) {
        wrap.appendChild(preview);
        standingFrame(look.url, look.cell).then((f) => paintFrame(pics[0].cv, f, null, 0)).catch(() => { pics[0].cap.textContent = 'no picture'; });
      }
      return wrap;
    }
    const st = { h0: cur.h0, h1: cur.h1, sat: cur.sat, val: cur.val, amount: cur.amount };
    const commit = () => write('tint', { hue: [Math.round(st.h0), Math.round(st.h1)], sat: Model.round(st.sat, 2), val: Model.round(st.val, 2), amount: Model.round(st.amount, 2) });
    // the track: the wheel left to right (0° to 360°), the parts outside the range dimmed, a handle at each end
    const track = el('div', { class: 'hue-track', title: 'drag a handle, or press the track to move the nearer one' });
    const dimA = el('div', { class: 'hue-dim' }), dimB = el('div', { class: 'hue-dim' });
    const hA = el('div', { class: 'hue-handle from', title: 'from' }), hB = el('div', { class: 'hue-handle to', title: 'to' });
    track.append(dimA, dimB, hA, hB);
    const n0 = el('input', { type: 'number', class: 'num tiny', min: 0, max: 360, step: 1, 'data-path': `${path}.hue.0`, title: 'from (degrees)' });
    const n1 = el('input', { type: 'number', class: 'num tiny', min: 0, max: 360, step: 1, 'data-path': `${path}.hue.1`, title: 'to (degrees)' });
    const spanTxt = el('span', { class: 'hint' });
    const flip = el('button', { class: 'btn small ghost', type: 'button', text: '⇄', title: 'the other side of the wheel: swap from and to (a range through red becomes the hues between, and back)', onclick: () => { const t = st.h0; st.h0 = st.h1; st.h1 = t; commit(); } });
    const sliders = {};
    const slider = (k, label, help) => {
      const r = el('input', { type: 'range', class: 'tint-slider', min: 0, max: 1, step: 0.01, value: st[k], 'data-path': `${path}.${k}`, title: help });
      const out = el('span', { class: 'tint-val', text: fmtN(st[k], 2) });
      r.addEventListener('input', () => { st[k] = Number(r.value); redraw(); });
      r.addEventListener('change', () => { st[k] = Number(r.value); commit(); });
      sliders[k] = { r, out };
      return el('label', { class: 'tint-row', title: help }, el('span', { class: 'tint-lab', text: label }), r, out);
    };
    const redraw = () => {
      const p0 = st.h0 / 360 * 100, p1 = st.h1 / 360 * 100;
      track.style.background = U.hueGradient(0, 360, st.sat, st.val, 13);
      if (st.h1 >= st.h0) {
        Object.assign(dimA.style, { left: '0%', width: `${p0}%` });
        Object.assign(dimB.style, { left: `${p1}%`, width: `${100 - p1}%` });
      } else {
        // through red: the hues between "to" and "from" are out
        Object.assign(dimA.style, { left: `${p1}%`, width: `${p0 - p1}%` });
        Object.assign(dimB.style, { left: '0%', width: '0%' });
      }
      hA.style.left = `${p0}%`; hB.style.left = `${p1}%`;
      hA.style.background = U.hsvHex(st.h0, st.sat, st.val); hB.style.background = U.hsvHex(st.h1, st.sat, st.val);
      if (document.activeElement !== n0) n0.value = Math.round(st.h0);
      if (document.activeElement !== n1) n1.value = Math.round(st.h1);
      const span = Model.hueSpan(st.h0, st.h1);
      spanTxt.textContent = `${Math.round(span)}° wide${st.h1 < st.h0 ? ', through red' : ''}`;
      for (const [k, s] of Object.entries(sliders)) s.out.textContent = fmtN(st[k], 2);
      schedulePaint();
    };
    // the pictures: as painted, then five hues across the range (one when the range is a single hue), then the row's
    // coloured special at the middle hue when the creature has specials (WV's follow-up: a darker, stronger shade of the
    // hue it rolled, Model.tintSpecial; the review of pass 58: the help had promised the special's own colour)
    const fracs = () => (Model.hueSpan(st.h0, st.h1) < 1e-9 ? [0] : [0, 0.25, 0.5, 0.75, 1]);
    // an elite-modified creature (a coloured-elite event, a wave wearing a modifier) never rolls the special
    const vs = c && !(ctx && ctx.modded) ? Model.varianceSpecial(c, stats, App.tl().special_defaults) : { chance: 0 };
    addPic('as painted', 'orig');
    for (let i = 0; i < 5; i++) addPic('');
    const spPic = vs.chance > 0 ? (addPic('special', 'special', `A coloured special of this row (${Math.round(vs.chance * 100)}% of them once Colour after kills is reached): the hue it rolled in a darker, stronger shade (saturation +0.15, brightness ×0.7, amount +0.15 over the larger of Amount and its own tint strength ${fmtN(vs.strength, 2)}), ×${fmtN(vs.size, 2)} the size`), pics[pics.length - 1]) : null;
    const paintAll = () => {
      paintFrame(pics[0].cv, frame, null, 0);
      const fs = fracs();
      for (let i = 1; i <= 5; i++) {
        const f = fs[i - 1];
        const fig = pics[i].fig;
        if (f == null) { fig.hidden = true; continue; }
        fig.hidden = false;
        const h = Model.hueAt(st.h0, st.h1, f);
        paintFrame(pics[i].cv, frame, Model.hsvToRgb(h, st.sat, st.val), st.amount);
        pics[i].cap.textContent = `${Math.round(h)}°`;
      }
      if (spPic) {
        const sp = Model.tintSpecial(st, vs.strength, fs.length > 1 ? 0.5 : 0);
        paintFrame(spPic.cv, frame, sp.rgb, sp.amount);
        spPic.cap.textContent = `special ${Math.round(sp.h)}°`;
      }
    };
    // a slider or a handle repaints once a frame at most (seven 192 px pictures each time)
    let paintRaf = 0;
    const schedulePaint = () => {
      if (!frame || paintRaf) return;
      paintRaf = requestAnimationFrame(() => { paintRaf = 0; if (frame) paintAll(); });
    };
    // dragging a handle (or the track: the nearer handle jumps there)
    const hueAtX = (clientX) => { const r = track.getBoundingClientRect(); return Math.min(Math.max((clientX - r.left) / Math.max(r.width, 1), 0), 1) * 360; };
    const startDrag = (e, which) => {
      if (e.button !== 0) return;
      e.preventDefault(); e.stopPropagation();
      const move = (ev) => { st[which] = hueAtX(ev.clientX); redraw(); };
      const up = () => { window.removeEventListener('pointermove', move); window.removeEventListener('pointerup', up); commit(); };
      move(e);
      window.addEventListener('pointermove', move);
      window.addEventListener('pointerup', up);
    };
    hA.addEventListener('pointerdown', (e) => startDrag(e, 'h0'));
    hB.addEventListener('pointerdown', (e) => startDrag(e, 'h1'));
    track.addEventListener('pointerdown', (e) => {
      if (e.target === hA || e.target === hB) return;
      const h = hueAtX(e.clientX);
      const near = (a2, b2) => Math.min(Math.abs(a2 - b2), 360 - Math.abs(a2 - b2));
      startDrag(e, near(h, st.h0) <= near(h, st.h1) ? 'h0' : 'h1');
    });
    for (const [inp, k] of [[n0, 'h0'], [n1, 'h1']]) {
      inp.addEventListener('change', () => { const v = U.parseNum(inp.value); if (v == null) return; st[k] = Math.min(Math.max(v, 0), 360); commit(); });
      inp.addEventListener('keydown', (e) => { if (e.key === 'Enter') inp.blur(); });
    }
    wrap.appendChild(track);
    wrap.appendChild(el('div', { class: 'tint-hues' }, el('span', { class: 'hint', text: 'from' }), n0, el('span', { class: 'hint', text: '° to' }), n1, el('span', { class: 'hint', text: '°' }), flip, spanTxt));
    wrap.appendChild(slider('sat', 'Saturation', 'how strong the colour is (0 = grey; the game\'s default 0.85)'));
    wrap.appendChild(slider('val', 'Brightness', 'how light the colour is (0 = black; default 1)'));
    wrap.appendChild(slider('amount', 'Amount', 'how much of the colour washes over the painting (0 = none, 1 = the most the game draws: 65% of the colour; default 0.5)'));
    wrap.appendChild(preview);
    wrap.appendChild(el('div', { class: 'tint-foot' },
      el('span', { class: 'muted small', text: look ? `${U.theName(c.name)}${look.code ? ` (${look.code})` : ''} on the sand as the game washes it (each creature rolls its own hue in the range)` : '' }),
      el('button', { class: 'btn small danger', type: 'button', text: 'Clear', title: 'no colour range: the creature\'s own tints again', onclick: () => write('tint', null) })));
    redraw();
    if (look) {
      standingFrame(look.url, look.cell).then((f) => { frame = f; paintAll(); }).catch(() => { pics[0].cap.textContent = 'no picture'; });
    }
    return wrap;
  }

  function attacksControl(stats, c, write, path) {
    const wrap = el('div', { class: 'attacks' });
    const names = c && c.boss ? [...new Set(c.boss.attacks)] : [];
    const map = U.getPath(stats, 'boss.attacks') || {};
    if (!names.length) wrap.appendChild(el('span', { class: 'muted small', text: c ? `${U.theName(c.name)} has no attack script` : 'pick a creature first' }));
    for (const name of names) {
      const cb = el('input', { type: 'checkbox', 'data-path': `${path}.${name}` });
      cb.checked = map[name] !== false;
      cb.addEventListener('change', () => {
        if (cb.checked) write(`boss.attacks.${name}`, map[name] === true ? true : null);
        else write(`boss.attacks.${name}`, false);
      });
      wrap.appendChild(el('label', { class: 'cb' }, cb, el('span', { text: name })));
    }
    for (const name of Object.keys(map)) {
      if (names.includes(name)) continue;
      wrap.appendChild(el('label', { class: 'cb unknown', title: 'not one of this creature\'s attacks (adds nothing)' }, el('span', { text: `${name}: ${map[name]}` }),
        el('button', { class: 'x', type: 'button', text: '×', onclick: () => write(`boss.attacks.${name}`, null) })));
    }
    return wrap;
  }

  function pickupWeightsControl(stats, write, path) {
    const wrap = el('div', { class: 'pweights' });
    const tl = App.tl();
    const roster = (tl.pickups && tl.pickups.roster) || [];
    const own = U.getPath(stats, 'pickup_weights') || {};
    const ids = [...new Set(roster.map((r) => r.id).concat(Object.keys(own)))];
    if (!ids.length) wrap.appendChild(el('span', { class: 'muted small', text: 'the map drops no power-ups' }));
    for (const id of ids) {
      const inTl = roster.find((r) => r.id === id);
      const p = App.pickup(id);
      const inp = el('input', { type: 'number', class: 'num short', min: 0, step: 'any', value: own[id] == null ? '' : own[id], placeholder: inTl ? String(inTl.weight) : '—', 'data-path': `${path}.${id}`, title: inTl ? `the map's weight is ${inTl.weight}` : 'not in the map\'s roster' });
      inp.addEventListener('change', () => write(`pickup_weights.${id}`, U.parseNum(inp.value)));
      inp.addEventListener('keydown', (e) => { if (e.key === 'Enter') inp.blur(); });
      wrap.appendChild(el('label', { class: 'pw' }, p ? el('img', { src: p.icon, width: 18, height: 18 }) : null, el('span', { text: p ? p.name : id }), inp));
    }
    wrap.appendChild(el('div', { class: 'muted small', text: 'any number here replaces the whole roster for this creature\'s kills: a power-up left empty is then never dropped by it' }));
    return wrap;
  }

  // ------------------------------------------------------------------ roster

  // pass 84 (lane TIMELINE; Garry: "spawning options are important to me ... better add too many controls than too few";
  // "I really like the ability to modify the enemy by the stats that they have, the colouring, the behaviour, the
  // everything in the timeline itself"): a spawn row's form in groups that fold (each remembered), every field with its
  // help: Schedule, Creature, Where and how, Presence, In the estimate (its numbers and a mini-chart), Overrides.
  const ROW_GROUPS = [
    { id: 'schedule', name: 'Schedule', kind: 'edit', keys: ['t', 'until', 'pace', 'every', 'count', 'offset', 'respect_cap', 'trickle', 'interval', 'chance', 't_jitter'], help: 'when its creatures come: continuous (drawn into the cap), waves every N s, or once' },
    { id: 'creature', name: 'Creature', kind: 'edit', keys: ['name', 'enemy', 'variant', 'role', 'elite', 'special'], help: 'who comes: one creature, a list, or the roster draw; its look, its role, an elite modifier, special' },
    { id: 'where', name: 'Where and how', kind: 'edit', keys: ['pattern', 'ring_radius', 'channel', 'pack', 'banner'], help: 'where they spawn round the hero, which cap they count against, the banner' },
    { id: 'presence', name: 'Presence', kind: 'edit', keys: ['weights'], help: 'its weight over the run clock (the filled area on its bar)' },
    { id: 'estimate', name: 'In the estimate', kind: 'view', keys: [], help: 'its numbers at its start and what the estimate says it brings' },
  ];
  const IGROUP_KEY = '88fits-editor-igroups';
  let igroupState = {};
  try { const v = JSON.parse(localStorage.getItem(IGROUP_KEY) || 'null'); if (v && typeof v === 'object') igroupState = v; } catch (_) { /* all open */ }

  /** A foldable group of the row form: its mark (eye: shows; pencil: edits), its name, a line of what it holds. */
  function igroup(g, sub) {
    const det = el('details', { class: `igroup kind-${g.kind}`, 'data-igroup': g.id });
    det.open = igroupState[g.id] !== false;
    det.addEventListener('toggle', () => { igroupState[g.id] = det.open; try { localStorage.setItem(IGROUP_KEY, JSON.stringify(igroupState)); } catch (_) { /* fine */ } });
    det.appendChild(el('summary', { title: g.help }, el('span', { class: `kmark kmark-${g.kind} small`, title: g.kind === 'view' ? 'view only: worked out from the map and the estimate' : 'editing' }, U.glyph(g.kind === 'view' ? 'eye' : 'pencil')), g.name, el('span', { class: 'igroup-sub', text: sub || g.help })));
    const body = el('div', { class: 'igroup-body' });
    det.appendChild(body);
    return { det, body };
  }

  function rosterForm(container, r, i) {
    const key = `roster:${i}`;
    const rows = App.tl().roster || [];
    const pace = TimelineModel.paceOf(r);
    const title = () => `${r.name ? r.name + ': ' : ''}${Timeline.enemyWords(r)} · ${fmtT(r.t)} → ${r.until == null ? 'end' : fmtT(r.until)}`;
    const cutT = Timeline.cursorT;
    const tEnd = r.until == null || r.until === '' ? App.viewEnd() : Number(r.until);
    const canSplit = cutT != null && cutT > (Number(r.t) || 0) && cutT < tEnd;
    const titleEl = header(container, 'Spawn row', title(), key, [
      { text: '▲', title: 'move the row up (Alt+↑): the order is for this page only, the game draws by weight', disabled: i === 0, cls: 'order', onclick: () => App.moveRow(i, -1) },
      { text: '▼', title: 'move the row down (Alt+↓)', disabled: i >= rows.length - 1, cls: 'order', onclick: () => App.moveRow(i, 1) },
      ...listActions(),
      { text: canSplit ? `Split at ${fmtT(cutT)}` : 'Split at cursor', title: canSplit ? `two rows: this one until ${fmtT(cutT)}, a copy from ${fmtT(cutT)} (its numbers fixed afresh there: the HP curve steps up)` : 'hover the timeline over this row\'s span first: the second under the pointer is where it splits', disabled: !canSplit, onclick: () => App.splitRow(i, cutT) },
      pace !== 'once' ? { text: '→ once', title: 'pace it as one wave at its start (+ Offset): Per wave creatures, then nothing', onclick: () => App.convertRow(i, 'once') } : null,
      pace !== 'waves' ? { text: '→ waves', title: 'pace it as waves every 30 s (Every)', onclick: () => App.convertRow(i, 'waves') } : null,
      pace !== 'continuous' ? { text: '→ continuous', title: 'draw it into the cap by its weight at every spawn check (the waves keys go)', onclick: () => App.convertRow(i, 'continuous') } : null,
    ].filter(Boolean), `${r.id ? `id ${r.id} · ` : ''}row ${i + 1} of ${rows.length} · ${TimelineModel.quantityText(r, Model.rowWaveCount(r, App.creature(Timeline.firstEnemy(r))), null)}${TimelineModel.roleOf(r) ? ` · ${TimelineModel.roleOf(r)}` : ''}`);
    const c = App.creature(Timeline.firstEnemy(r));
    const form = el('div', { class: 'form' });
    // pass 58: the row's numbers are fixed from its start; its look (its own variant, else the default) for the colours
    const octx = { t0: () => r.t, from: 'row', look: () => r.variant, modded: !!r.elite };
    const groups = {};
    for (const g of ROW_GROUPS) { groups[g.id] = igroup(g); form.appendChild(groups[g.id].det); }
    const groupOfKey = (k) => (ROW_GROUPS.find((g) => g.keys.includes(k)) || ROW_GROUPS[1]).id;
    for (const def of FIELDS.roster) {
      if (def.key === 'id') continue;
      // pass 84: a field for some pacings only (paceIn); pass 81 (lane PACE): the waves-only fields while it says Waves
      if (def.paceIn) { if (!def.paceIn.includes(TimelineModel.paceOf(r))) continue; }
      else if (def.paced && !Model.rowPaced(r)) continue;
      // pass 83 (lane TIMELINE): a row's own draw interval, while it is in the continuous draw
      if (def.drawn && !Model.rowDrawn(r)) continue;
      if (def.ring && r.pattern !== 'ring') continue;
      const host = groups[groupOfKey(def.key)].body;
      if (def.key === 'pace') { host.appendChild(paceRow(def, r, c)); continue; }
      if (def.key === 'enemy') { host.appendChild(Forms.row(def, rowEnemyControl(r), { cls: 'wide-ctl' })); continue; }
      if (def.key === 'variant' && r.enemy === 'roster') continue;
      if (def.type === 'weights') {
        // the Presence boxes follow a dragged bar or point (the review of pass 58: the time stayed put until the drop)
        const pres = Forms.weightsBlock(r);
        if (pres.refresh) liveFns.push(pres.refresh);
        host.appendChild(Forms.row(def, pres, { cls: 'wide-ctl' }));
        continue;
      }
      if (def.type === 'overrides') continue;
      host.appendChild(fieldFor(def, r, Object.assign({ enemyId: Timeline.firstEnemy(r), placeholders: { pack: c ? c.pack_size : '', count: Model.rowWaveCount({ pack: r.pack, stats: r.stats }, c), interval: spawnCheck() }, note: def.key === 'pattern' ? patternNote('roster', r) : def.key === 'interval' ? intervalNote(r) : def.key === 'special' ? rowSpecialNote(r, c) : null }, octx)));
    }
    // the row's HP and ATK (pass 58 review: in sight with Overrides closed, following a dragged bar) and its mini-chart
    const est = groups.estimate.body;
    if (c) est.appendChild(numbersLine(c, () => (U.isObj(r.stats) ? r.stats : {}), () => r.t, 'row', null, '', () => (r.until == null || r.until === '' ? Infinity : Number(r.until))));
    est.appendChild(miniChart(i, r));
    const facts = el('div', { class: 'row-facts' });
    const fill = () => {
      clear(facts);
      const t0 = Math.max(Number(r.t) || 0, 0);
      const open = App.rosterAt(t0).find((o) => o.i === i);
      const lines = [];
      // pass 81 (lane PACE): a waves row is not in the draw (unless it trickles): its weight only gates its waves
      if (open && !open.drawn) lines.push(`At ${fmtT(t0)} this row weighs ${fmtN(open.w, 2)}: it comes as ${TimelineModel.paceOf(r) === 'once' ? 'one wave' : 'waves'}, not in the draw (a weight of 0 holds its waves).`);
      else if (open) lines.push(`At ${fmtT(t0)} this row weighs ${fmtN(open.w, 2)}: ${Math.round(open.norm * 100)}% of its channel's draw.`);
      lines.push('The order of the rows is for this page only: the game draws a burst by the weights, whatever the order.');
      for (const l of lines) facts.appendChild(el('p', { class: 'muted small', text: l }));
    };
    fill();
    est.appendChild(facts);
    // every override group (Body, Colour, Attacks, Ranged, Charge, Kamikaze, Artillery, Sniper, Flee on hit, Spawning,
    // Drops, Power-ups, Elite, Mini-boss, Boss), each with its help
    const ovDef = FIELDS.roster.find((d) => d.key === 'stats');
    form.appendChild(fieldFor(ovDef, r, Object.assign({ enemyId: Timeline.firstEnemy(r) }, octx)));
    container.appendChild(form);
    liveTimes(container, titleEl, title, r, ['t', 'until']);
    liveFns.push(fill);
    jsonPeek(container, r);
  }

  /** Who a row brings (pass 84; INTERFACES.md / keys_SPAWN.md): one creature, a list drawn at random by `enemy_weights`,
   *  or "roster" (the coloured-elite draw by the open rows' Elite weight). The switch keeps the first creature. */
  function rowEnemyControl(r) {
    const mode = r.enemy === 'roster' ? 'roster' : Array.isArray(r.enemy) ? 'list' : 'one';
    const wrap = el('div', { class: 'enemy-mode' });
    const first = Timeline.firstEnemy(r) || firstCreature();
    wrap.appendChild(Forms.select(FIELDS.ENEMY_MODES, mode, (v) => App.apply(() => {
      if (v === 'roster') { r.enemy = 'roster'; delete r.enemy_weights; delete r.variant; }
      else if (v === 'list') { r.enemy = [first]; delete r.enemy_weights; }
      else { r.enemy = first; delete r.enemy_weights; }
    }), { path: 'enemy.mode' }));
    if (mode === 'one') {
      wrap.appendChild(Forms.enemyPick(r.enemy, (v) => App.apply(() => {
        U.setKey(r, 'enemy', v);
        if (r.variant && !App.variantOk(v, r.variant)) delete r.variant;
      }), { path: 'enemy' }));
    } else if (mode === 'list') {
      const ids = r.enemy.slice();
      const ws = Array.isArray(r.enemy_weights) ? r.enemy_weights.map(Number) : null;
      const total = ids.reduce((a, _, k) => a + (ws && ws[k] != null ? ws[k] : 1), 0) || 1;
      const write = (ids2, ws2) => App.apply(() => {
        if (!ids2.length) { r.enemy = first; delete r.enemy_weights; return; }
        r.enemy = ids2;
        if (ws2 && ws2.some((x) => x != null && x !== 1)) r.enemy_weights = ws2.map((x) => (x == null ? 1 : x)); else delete r.enemy_weights;
        if (r.variant && !ids2.every((id) => App.variantOk(id, r.variant))) delete r.variant;
      });
      ids.forEach((id, k) => {
        const sel = Forms.iconSelect(Forms.creatureGroups('creature'), id, (v) => { const n = ids.slice(); n[k] = v || ''; write(n.filter(Boolean), ws); }, { path: `enemy.${k}`, popWidth: 330, cls: 'grow' });
        const w = el('input', { type: 'number', class: 'num short', min: 0, step: 'any', value: ws && ws[k] != null ? ws[k] : '', placeholder: '1', title: 'its pick weight (enemy_weights; equal when empty; 0 never comes)', 'data-path': `enemy_weights.${k}` });
        w.addEventListener('change', () => { const n = (ws || ids.map(() => 1)).slice(); n[k] = U.parseNum(w.value) == null ? 1 : U.parseNum(w.value); write(ids, n); });
        const share = ((ws && ws[k] != null ? ws[k] : 1) / total) * 100;
        wrap.appendChild(el('div', { class: 'enemy-row' }, sel, el('span', { class: 'with-hint' }, w, el('span', { class: 'hint', text: `${Math.round(share)}%` })),
          el('button', { class: 'x', type: 'button', text: '×', title: 'remove', onclick: () => { const n = ids.slice(); n.splice(k, 1); const nw = ws ? ws.slice() : null; if (nw) nw.splice(k, 1); write(n, nw); } })));
      });
      wrap.appendChild(el('button', { class: 'btn small', type: 'button', text: '+ another', onclick: () => {
        const groups = Forms.creatureGroups('creature');
        const nx = groups.length && groups[0].options.length ? (groups[0].options.find((o) => !ids.includes(o.v)) || groups[0].options[0]).v : first;
        write(ids.concat([nx]), ws ? ws.concat([1]) : null);
      } }));
    } else {
      wrap.appendChild(el('div', { class: 'muted small', text: 'each creature drawn from the rows open at that second by their Elite weight (each row\'s Overrides -> Elite -> Elite weight), with that row\'s look and HP and ATK: the coloured-elite draw. Set an Elite modifier below for coloured elites.' }));
    }
    return wrap;
  }

  /** The first creature of the roster (a new list's first entry). */
  function firstCreature() {
    const rows = App.tl().roster || [];
    for (const r of rows) { const id = Timeline.firstEnemy(r); if (App.creature(id)) return id; }
    const c = App.S.enemies.find((x) => x.kind === 'enemy' && !x.hidden);
    return c ? c.id : '';
  }

  /** A row set to Special, in words (pass 84; the swarm event's note, pass 69). */
  function rowSpecialNote(r, c) {
    if (!r.special) return null;
    if (!c) return [b('Special: '), 'each creature of the list or the draw comes as its own coloured special.'];
    return specialNote({ special: true, enemy: c.id, stats: r.stats });
  }

  /** The row's own mini-chart (pass 84): what the estimate says it spawns each second over its life (yellow bars) and
   *  a creature's HP in play each second (the line: fixed from its start, stepping with the stage and the hero level). */
  function miniChart(i, r) {
    const d = Timeline.rowSpawnsPerSecond(i);
    const W = 380, H = 110, L = 34, R = 40, T = 10, B = 18;
    const box = el('div', { class: 'mini-wrap' });
    if (!d || !d.ts.length) { box.appendChild(el('div', { class: 'mc-note', text: 'the estimate is not drawn yet' })); return box; }
    const s = U.svg('svg', { class: 'mini-chart', viewBox: `0 0 ${W} ${H}`, preserveAspectRatio: 'none' });
    const t0 = d.ts[0], t1 = d.ts[d.ts.length - 1] || t0 + 1;
    const xx = (t) => L + ((t - t0) / Math.max(t1 - t0, 1)) * (W - L - R);
    const nMax = Math.max(1, ...d.n);
    const hps = d.hp.filter((v) => v != null);
    const hMax = hps.length ? Math.max(...hps) * 1.1 : 1;
    const yn = (v) => H - B - (v / nMax) * (H - T - B);
    const yh = (v) => H - B - (v / hMax) * (H - T - B);
    s.appendChild(U.svg('line', { x1: L, x2: W - R, y1: H - B, y2: H - B, class: 'mc-grid' }));
    const bw = Math.max(1, (W - L - R) / Math.max(d.ts.length, 1) - 0.3);
    let total = 0;
    d.ts.forEach((t, k) => { total += d.n[k]; if (d.n[k] > 0.01) s.appendChild(U.svg('rect', { x: xx(t), y: yn(d.n[k]), width: bw, height: Math.max(0.5, H - B - yn(d.n[k])), class: 'mc-bar' })); });
    if (hps.length) s.appendChild(U.svg('polyline', { points: d.ts.map((t, k) => (d.hp[k] == null ? '' : `${xx(t)},${yh(d.hp[k])}`)).filter(Boolean).join(' '), class: 'mc-hp' }));
    s.appendChild(U.svg('text', { x: 2, y: T + 8, class: 'mc-axis', text: `${fmtN(nMax, 1)}/s` }));
    s.appendChild(U.svg('text', { x: 2, y: H - B, class: 'mc-axis', text: '0' }));
    if (hps.length) s.appendChild(U.svg('text', { x: W - R + 3, y: T + 8, class: 'mc-axis', text: `HP ${fmtN(hMax / 1.1, 0)}` }));
    s.appendChild(U.svg('text', { x: L, y: H - 4, class: 'mc-axis', text: fmtT(t0) }));
    s.appendChild(U.svg('text', { x: W - R - 26, y: H - 4, class: 'mc-axis', text: fmtT(t1) }));
    box.appendChild(s);
    box.appendChild(el('div', { class: 'mc-note', text: `Yellow bars: what it spawns each second in the estimate (≈${Math.round(total)} over ${fmtT(t1 - t0)}${Number(r.until) > App.viewEnd() || r.until == null ? ', to the view\'s end' : ''}). Line: a creature's HP in play each second (fixed from its start; the stage multiplier steps it up, the hero level box ${App.S.level}).` }));
    return box;
  }

  /** A roster row's Pacing select (pass 81, lane PACE; Garry: "the frequency at which enemy waves come"): Continuous drops
   *  the waves-only keys (the game ignores them on a continuous row); Waves sets Every to 30 when the row has none, so its
   *  ticks show at once; Once (pass 84) drops Every. The note under it says when the row's creatures come, kept up to date
   *  while the bar is dragged. */
  function paceRow(def, r, c) {
    const value = r.pace == null || r.pace === '' ? 'continuous' : String(r.pace);
    const ctl = Forms.select(def.options, value, (v) => App.apply(() => {
      if (v === 'waves') {
        r.pace = 'waves';
        if (r.every == null) r.every = Model.ROW_WAVE_EVERY_DEF;
      } else if (v === 'once') {
        r.pace = 'once';
        delete r.every;
      } else {
        delete r.pace;
        for (const k of Model.ROW_WAVE_KEYS) delete r[k];
      }
    }), { path: 'pace' });
    const note = el('span', { class: 'pace-note' });
    const fill = () => { clear(note); for (const part of paceNote(r, c)) note.appendChild(typeof part === 'string' ? document.createTextNode(part) : part); };
    fill();
    liveFns.push(fill);
    return Forms.row(def, ctl, { note });
  }

  /** The words under Pacing (pass 81): a continuous row's draw (the map's spawn check and bursts), or a waves row's waves:
   *  how many, every how often, from when to when, the first few seconds, the ones its presence holds back, the cap. */
  function paceNote(r, c) {
    const tl = App.tl();
    if (!Model.rowPaced(r)) {
      const si = tl.spawn_interval == null ? 0.5 : Number(tl.spawn_interval);
      const lo = tl.burst_min == null ? 5 : Number(tl.burst_min), hi = tl.burst_max == null ? 20 : Number(tl.burst_max);
      // pass 83 (lane TIMELINE): its draws are notches now, at the spawn check or on its own clock (Draw every)
      if (Model.rowHasInterval(r)) return [b('Continuous: '), `drawn by its weight on its own clock, every ${fmtN(Model.rowDrawInterval(r, si), 2)} s (Draw every below), a burst of ${lo}–${hi} load units cut to its share, while the cap has room. A yellow tick along its bar at each draw.`];
      return [b('Continuous: '), `drawn by its weight at every spawn check (every ${fmtN(si, 2)} s, a burst of ${lo}–${hi} load units shared by the open rows, Settings → Spawning) while the cap has room. A yellow tick along its bar at each check (dotted where they are under 3 px apart; Draw every below gives it its own clock).`];
    }
    const name = c ? U.plural(c.name) : 'creatures';
    const n = Model.rowWaveCount(r, c);
    // pass 84: a once row: its one wave
    if (TimelineModel.paceOf(r) === 'once') {
      const at = Model.rowWaveStart(r);
      const held = !(App.rowWeight(r, at) > 0);
      return [b('Once: '), `${n} ${name} at ${fmtT(at)}${held ? ' (its presence is 0 then: it does not come)' : ''}. `,
        r.respect_cap === false ? 'On top of the cap, all at once (the hard cap still holds).' : 'Into the free room under the cap; the rest as room frees, until its Until (or the end).',
        r.trickle ? ' Also drawn continuously while it is open.' : ''];
    }
    const every = Model.rowWaveEvery(r);
    const end = r.until == null || r.until === '' ? App.viewEnd() : Number(r.until);
    const all = Model.rowWaveTimes(r, end);
    const come = Model.rowEtchTimes(r, end, tl.weight_late_t);
    const held = all.length - come.length;
    const first = come.slice(0, 4).map((t) => fmtT(t)).join(', ') + (come.length > 4 ? ', …' : '');
    const out = [b('Waves: '), `${n} ${name} `, every > 0 ? `every ${fmtN(every, 2)} s` : 'once', ` from ${fmtT(Model.rowWaveStart(r))}`];
    if (r.until != null && r.until !== '') out.push(` to ${fmtT(r.until)}`);
    out.push(come.length ? `: ${come.length}${r.until == null || r.until === '' ? ' in view' : ''} wave${come.length === 1 ? '' : 's'} (${first})` : ': no wave comes');
    if (held > 0) out.push(`, ${held} held back where its presence is 0`);
    out.push('. ');
    out.push(r.respect_cap === false ? 'On top of the cap, all at once (the hard cap still holds).' : 'Into the free room under the cap; the rest comes first as room frees, until its next wave.');
    out.push(r.trickle ? ' Also drawn continuously between its waves.' : ' Not in the continuous draw between its waves.');
    return out;
  }

  /** The map's spawn check (seconds): Settings → Spawning → Spawn check every (pass 83: a row's Draw every placeholder). */
  function spawnCheck() {
    const si = App.tl().spawn_interval;
    return si == null || si === '' ? 0.5 : Number(si);
  }

  /** The words under a row's Draw every (pass 83, lane TIMELINE; Garry: "for Continuous spawning, I would still like to
   *  control the interval of continuous spawning, the 0.7s can be a default"): at the spawn check with the other rows,
   *  or on its own clock, with what a draw holds at the row's start and how that compares with the spawn check. */
  function intervalNote(r) {
    const tl = App.tl();
    const si = spawnCheck();
    const lo = tl.burst_min == null ? 5 : Number(tl.burst_min), hi = tl.burst_max == null ? 20 : Number(tl.burst_max);
    const t0 = Math.max(Number(r.t) || 0, 0);
    const i = (tl.roster || []).indexOf(r);
    const open = App.rosterAt(t0).find((o) => o.i === i);
    const sh = open ? open.norm : 0;
    const per = ((lo + hi) / 2) * sh;
    const shTxt = `${Math.round(sh * 100)}% of the open rows' weight at ${fmtT(t0)}`;
    if (!Model.rowHasInterval(r)) return [b('At the spawn check: '), `drawn every ${fmtN(si, 2)} s together with the other rows (Settings → Spawning), ${shTxt}: about ${fmtN(per, 1)} load units a draw while the cap has room. Type a number to give it its own clock.`];
    const iv = Model.rowDrawInterval(r, si);
    const out = [b('Own clock: '), `a draw every ${fmtN(iv, 2)} s from ${fmtT(t0)}${Number(r.interval) < Model.ROW_INTERVAL_MIN ? ` (${r.interval} counts as ${Model.ROW_INTERVAL_MIN})` : ''}, each about ${fmtN(per, 1)} load units (a burst of ${lo}–${hi} × ${shTxt}), `];
    out.push(Math.abs(iv - si) < 1e-9 ? 'as often as the spawn check: the same amount, on its own beat.' : `${fmtN(si / iv, 2)}× as often as at the spawn check (every ${fmtN(si, 2)} s), so about ${fmtN(si / iv, 2)}× the creatures while the cap has room.`);
    out.push(' Clear the box to draw it at the spawn check again.');
    return out;
  }

  // ------------------------------------------------------------------ waves

  function waveForm(container, w, i) {
    const key = `wave:${i}`;
    const title = () => { const e = App.waveEnd(w); return `${w.name || w.id || 'wave'} · ${fmtT(w.t)} → ${e === Infinity ? 'no end' : fmtT(e)}`; };
    const titleEl = header(container, 'Wave', title(), key, listActions());
    liveTimes(container, titleEl, title, w, ['t', 'until']);
    const form = el('div', { class: 'form' });
    for (const def of FIELDS.wave) {
      if (def.type === 'alts') continue;
      form.appendChild(fieldFor(def, w, { note: def.key === 'pattern' ? patternNote('wave', w) : null }));
    }
    const cnt = Number(w.count) || 0, burst = Number(w.burst == null ? 5 : w.burst), every = Number(w.every == null ? 2 : w.every);
    const bursts = cnt > 0 ? Math.ceil(cnt / burst) : null;
    form.appendChild(el('p', { class: 'muted small', text: bursts ? `${bursts} burst${bursts > 1 ? 's' : ''} of ${burst}: the last at ${fmtT((Number(w.t) || 0) + every * (bursts - 1))}${w.until != null ? `, or until ${fmtT(w.until)}, whichever comes first` : ''}.` : (w.until != null ? `bursts of ${burst} every ${fmtN(every)} s until ${fmtT(w.until)}: about ${Math.max(0, Math.floor((Number(w.until) - (Number(w.t) || 0)) / Math.max(every, 0.01)) + 1) * burst} creatures.` : 'no count and no until: the wave never stops.') }));
    container.appendChild(form);
    container.appendChild(altsBlock(w));
    jsonPeek(container, w);
  }

  function altsBlock(w) {
    const wrap = el('div', { class: 'alts' });
    const defAlts = FIELDS.wave.find((d) => d.type === 'alts');
    const alts = Array.isArray(w.alts) ? w.alts : null;
    if (!alts || !alts.length) {
      wrap.appendChild(section('Creature', 'the one creature the wave spawns (an alternative of its own)'));
      const c = App.creature(w.enemy);
      for (const def of FIELDS.alt) {
        if (def.key === 'chance') continue;
        wrap.appendChild(fieldFor(def, w, { enemyId: w.enemy, placeholders: { pack: c ? c.pack_size : '' }, t0: () => w.t, from: 'wave', modded: !!w.elite, look: () => w.variant }));
        if (def.key === 'enemy' && c) wrap.appendChild(numbersLine(c, () => (U.isObj(w.stats) ? w.stats : {}), () => w.t, 'wave', null, '', () => App.waveEnd(w)));
      }
      wrap.appendChild(el('div', { class: 'alt-actions' }, el('button', { class: 'btn small', type: 'button', text: 'Split into alternatives', title: defAlts.help, onclick: () => App.apply(() => {
        const first = { chance: 1 };
        for (const k of ['enemy', 'variant', 'pack', 'stats']) if (w[k] !== undefined) first[k] = w[k];
        w.alts = [first, { chance: 1, enemy: w.enemy }];
        for (const k of ['enemy', 'variant', 'pack', 'stats']) delete w[k];
      }) })));
      return wrap;
    }
    wrap.appendChild(section(`Alternatives · one of ${alts.length} is rolled per run`, defAlts.help));
    const shares = App.waveAlts(w);
    alts.forEach((a, k) => {
      const c = App.creature(a.enemy);
      const card = el('div', { class: 'alt-card', style: `border-left-color:${Timeline.ALT_COLORS[k % Timeline.ALT_COLORS.length]}` });
      card.appendChild(el('div', { class: 'alt-head' }, el('b', { text: `Alternative ${k + 1}` }), el('span', { class: 'muted', text: ` · ${Math.round(shares[k].share * 100)}% of the roll` }),
        el('span', { class: 'spacer' }),
        el('button', { class: 'btn small', type: 'button', text: 'Copy', onclick: () => App.apply(() => { w.alts.splice(k + 1, 0, U.clone(a)); }) }),
        el('button', { class: 'btn small danger', type: 'button', text: '×', title: 'remove this alternative', disabled: alts.length <= 1, onclick: () => App.apply(() => { w.alts.splice(k, 1); }) })));
      for (const def of FIELDS.alt) {
        card.appendChild(fieldFor(def, a, { enemyId: a.enemy, pathPrefix: `alts.${k}`, placeholders: { pack: c ? c.pack_size : '' }, t0: () => w.t, from: 'wave', modded: !!w.elite, look: () => a.variant }));
        if (def.key === 'enemy' && c) card.appendChild(numbersLine(c, () => (U.isObj(a.stats) ? a.stats : {}), () => w.t, 'wave', null, '', () => App.waveEnd(w)));
      }
      wrap.appendChild(card);
    });
    wrap.appendChild(el('div', { class: 'alt-actions' },
      el('button', { class: 'btn small', type: 'button', text: '+ alternative', onclick: () => App.apply(() => { const last = alts[alts.length - 1]; w.alts.push({ chance: last.chance == null ? 1 : last.chance, enemy: last.enemy }); }) }),
      alts.length === 1 ? el('button', { class: 'btn small ghost', type: 'button', text: 'Fold into the wave', title: 'one alternative is the wave\'s own creature: write it on the wave itself', onclick: () => App.apply(() => {
        const a = w.alts[0];
        for (const k of ['enemy', 'variant', 'pack', 'stats']) if (a[k] !== undefined) w[k] = a[k];
        delete w.alts;
      }) }) : null));
    return wrap;
  }

  // ------------------------------------------------------------------ events

  function eventForm(container, ev, i) {
    const key = `event:${i}`;
    const info = FIELDS.EVENT_TYPES[ev.type];
    const title = () => `${App.eventLabel(ev)} · ${fmtT(ev.t)}`;
    const titleEl = header(container, 'Event', title(), key, listActions());
    liveTimes(container, titleEl, title, ev, ['t']);
    if (info) container.appendChild(el('p', { class: 'insp-help' }, U.glyph(info.glyph), ' ', info.help));
    const form = el('div', { class: 'form' });
    const ids = U.idList(ev.enemy);
    for (const def of FIELDS.event) {
      if (def.only && !def.only.includes(ev.type)) continue;
      if (def.key === 'type') {
        form.appendChild(Forms.row(def, Forms.select(def.options, ev.type, (v) => App.apply(() => {
          ev.type = v;
          // the keys of the old type that mean nothing to the new one go
          for (const d of FIELDS.event) if (d.only && !d.only.includes(v)) delete ev[d.key];
          if (v === 'swarm' && ev.count == null) ev.count = 30;
          if (v === 'elite_every' && ev.interval == null) ev.interval = 120;
        }), { path: 'type' })));
      } else if (def.type === 'enemies') {
        form.appendChild(Forms.row(def, enemiesControl(ev), {}));
        // pass 58 review: what it spawns has these numbers (each creature of a list its own line, three at most)
        const named = ids.map((id) => App.creature(id)).filter(Boolean);
        const regular = named.filter((c) => Model.archOf(c) === 'regular');
        regular.slice(0, 3).forEach((c) => form.appendChild(numbersLine(c, () => (U.isObj(ev.stats) ? ev.stats : {}), () => ev.t, 'event', ev, regular.length > 1 ? c.name : '')));
        // Elites and bosses by their kind: one line for the lot (their own rules)
        if (named.length && !regular.length) {
          const bosses = named.every((c) => Model.archOf(c) === 'boss');
          form.appendChild(el('div', { class: 'fhelp fnote rn-note rn-line', 'data-note': 'row-numbers' }, el('span', { class: 'rn-main' },
            b(named.length > 1 ? `${named.map((c) => c.name).join(', ')}: ` : `${U.theName(named[0].name)}: `),
            bosses ? 'a boss keeps its own rules: no time curve (its HP × per stage under Boss); the stage multiplier on top.'
              : `${named.length > 1 ? 'Elite-archetype mini-bosses keep their' : 'an Elite-archetype mini-boss keeps its'} own rules: no time curve (HP × per stage under Mini-boss); the stage multiplier on top.`)));
        }
      } else if (def.type === 'variant') {
        form.appendChild(Forms.row(def, Forms.variantSelect(ids[0] || '', ev.variant, (v) => App.apply(() => U.setKey(ev, 'variant', v)), { path: 'variant' })));
      } else if (def.type === 'overrides') {
        // pass 58: an event's creatures take their numbers from the second it fires (each firing of an "Elites every")
        form.appendChild(overridesBlock(ev, 'stats', ids[0] || '', 'stats', { t0: () => ev.t, from: 'event', event: ev, each: ev.type === 'elite_every', modded: ev.type === 'elite' || ev.type === 'elite_every', look: () => ev.variant }));
      } else {
        form.appendChild(Forms.fieldRow(def, ev, { allowRandom: false, emptyLabel: def.key === 'mod' ? 'random modifier' : undefined, note: def.key === 'pattern' ? patternNote('event', ev) : def.key === 'special' ? specialNote(ev) : null }));
      }
    }
    if (ev.type === 'elite_every') {
      const iv = ev.interval;
      const lo = Array.isArray(iv) ? Number(iv[0]) : Number(iv == null ? 90 : iv);
      const hi = Array.isArray(iv) ? Number(iv[iv.length - 1]) : lo;
      const left = App.runEnd() - (Number(ev.t) || 0);
      if (lo > 0) form.appendChild(el('p', { class: 'muted small', text: `About ${Math.floor(left / ((lo + hi) / 2))} coloured elites before the last boss (Hot Sauce makes them come sooner). With no creature named, each is drawn from the open roster rows by their Elite weight (Overrides → Elite) and comes with that row's HP and ATK, fixed from the row's start.` }));
    }
    container.appendChild(form);
    jsonPeek(container, ev);
  }

  /** `enemy` as one id or a list with optional weights. */
  function enemiesControl(ev) {
    const ids = U.idList(ev.enemy);
    const hadList = Array.isArray(ev.enemy);
    const ws = Array.isArray(ev.weights) ? ev.weights.map(Number) : null;
    const prefer = ev.type === 'boss' ? 'boss' : ev.type === 'elite_boss' ? 'elite' : 'creature';
    const wrap = el('div', { class: 'enemies' });
    const write = (ids2, ws2) => App.apply(() => {
      if (!ids2.length) { delete ev.enemy; delete ev.weights; return; }
      if (ids2.length === 1 && !hadList) { ev.enemy = ids2[0]; delete ev.weights; return; }
      ev.enemy = ids2;
      const any = ws2 && ws2.some((x) => x != null && x !== 1);
      if (ws2 && (any || 'weights' in ev)) ev.weights = ws2.map((x) => (x == null ? 1 : x));
      else delete ev.weights;
    });
    const shares = App.eventShares(ev);
    ids.forEach((id, k) => {
      const sel = Forms.iconSelect(Forms.creatureGroups(prefer), id, (v) => { const n = ids.slice(); n[k] = v || ''; write(n.filter(Boolean), ws); }, { path: `enemy.${k}`, popWidth: 330, cls: 'grow' });
      const row = el('div', { class: 'enemy-row' }, sel);
      if (ids.length > 1 || ws) {
        const w = el('input', { type: 'number', class: 'num short', min: 0, step: 'any', value: ws && ws[k] != null ? ws[k] : '', placeholder: '1', title: 'weight (equal when empty)', 'data-path': `weights.${k}` });
        w.addEventListener('change', () => { const n = (ws || ids.map(() => 1)).slice(); n[k] = U.parseNum(w.value) == null ? 1 : U.parseNum(w.value); write(ids, n); });
        row.appendChild(el('span', { class: 'with-hint' }, w, el('span', { class: 'hint', text: `${Math.round(shares[k].share * 100)}%` })));
      }
      row.appendChild(el('button', { class: 'x', type: 'button', text: '×', title: 'remove', onclick: () => { const n = ids.slice(); n.splice(k, 1); const nw = ws ? ws.slice() : null; if (nw) nw.splice(k, 1); write(n, nw); } }));
      wrap.appendChild(row);
    });
    if (!ids.length) wrap.appendChild(el('div', { class: 'muted small', text: ev.type === 'elite' ? 'empty: a random roster creature that may be an elite (by the rows\' Elite weight)' : ev.type === 'swarm' ? 'empty: the map\'s walker' : ev.type === 'boss' ? 'empty: the map\'s own boss' : 'add a creature' }));
    wrap.appendChild(el('button', { class: 'btn small', type: 'button', text: ids.length ? '+ another (random pick)' : '+ creature', onclick: () => {
      const groups = Forms.creatureGroups(prefer);
      const first = groups.length && groups[0].options.length ? groups[0].options.find((o) => !ids.includes(o.v)) || groups[0].options[0] : null;
      if (!first) return;
      App.apply(() => {
        const n = ids.concat([first.v]);
        ev.enemy = n.length === 1 && !hadList ? n[0] : n;
        if (ws) ev.weights = ws.concat([1]);
      });
    } }));
    return wrap;
  }

  // ------------------------------------------------------------------ cap, curves, share, blocks, issues

  function capForm(container) {
    const tl = App.tl();
    header(container, 'Cap', 'the live cap over the run', 'cap', []);
    container.appendChild(el('p', { class: 'insp-help', text: 'The points are the control points of the live cap curve (how many creatures may be alive): linear between them, flat before the first and after the last. They are not spawn events: the director spawns up to the cap on its own interval (every spawn_interval seconds, a burst of burst_min to burst_max load units while there is room).' }));
    container.appendChild(el('p', { class: 'insp-help', text: 'Drag a point on the lane, double-click the line to add one, double-click a point to remove it. Load units: a creature counts its cap_share (the skeleton 0.5).' }));
    const form = el('div', { class: 'form' });
    form.appendChild(section('Curve points'));
    form.appendChild(Forms.pointsBlock(tl));
    form.appendChild(section('Limits'));
    for (const k of ['hard_cap', 'cap_max', 'boss_cap_frac', 'cap_per_stage', 'hell_cap', 'cap_start', 'cap_per_minute']) {
      const def = FIELDS.SCALARS.find((d) => d.key === k);
      if (def) form.appendChild(Forms.fieldRow(def, tl, { labels: def.type === 'list' ? (i) => `stage ${i + 1}` : undefined }));
    }
    const SL = App.stageLength();
    const samples = [0, SL / 2, SL, SL * 1.5, SL * 2, SL * 2.5, App.runEnd()].map((t) => `${fmtT(t)} → ${App.capAt(t)}`);
    form.appendChild(el('p', { class: 'muted small', text: 'Cap by time: ' + samples.join(' · ') }));
    container.appendChild(form);
  }

  /** The HP x or ATK x lane's curve: the mode switch, the formula, the points, and what it makes with the stage
   *  multiplier, creature_hp_mult / creature_damage_mult and the assumed hero level at the stage marks. */
  function curveForm(container, key) {
    const isHp = key === 'hp_curve';
    const lane = FIELDS.LANES.find((l) => l.id === (isHp ? 'hp' : 'dmg'));
    header(container, isHp ? 'HP ×' : 'ATK ×', isHp ? 'creature health over the run clock' : 'creature damage over the run clock', isHp ? 'hp' : 'dmg', []);
    container.appendChild(el('p', { class: 'insp-help', text: lane ? lane.text : '' }));
    container.appendChild(Forms.curveBlock(App.tl(), key));
    container.appendChild(section('What it makes', 'the curve with the stage multiplier, the creature multiplier and the assumed hero level'));
    const SL = App.stageLength();
    const times = [];
    for (let k = 0; k < App.stages(); k++) { times.push(k * SL); times.push(k * SL + SL / 2); }
    times.push(App.runEnd() - 1);
    const t = el('table', { class: 'kv wide' });
    t.appendChild(el('tr', {}, el('td', { text: 'time' }), el('td', { text: 'curve' }), el('td', { text: '× stage' }), el('td', { text: '× level' }), el('td', { text: isHp ? '× creature_hp_mult' : '× creature_damage_mult' }), el('td', { text: '= total' })));
    for (const tt of times) {
      const m = isHp ? App.hpMultAt(tt) : App.dmgMultAt(tt);
      t.appendChild(el('tr', {}, el('td', { text: fmtT(tt) }), el('td', { text: `×${fmtN(m.time, 2)}` }), el('td', { text: `×${fmtN(m.stage, 2)}` }), el('td', { text: `×${fmtN(m.level, 2)}` }), el('td', { text: `×${fmtN(m.creature, 2)}` }), el('td', { text: `×${fmtN(m.total, 2)}` })));
    }
    container.appendChild(t);
    container.appendChild(el('p', { class: 'muted small', text: isHp
      ? `For an ordinary creature of a row starting at that second (hero level ${App.S.level}, the box in the top bar). An Elite-archetype mini-boss ignores the curve and the level (elite.hp_mult_per_stage^stage × stage × creature_hp_mult); a boss ignores creature_hp_mult too.`
      : `Every hostile damage of a row starting at that second (hero level ${App.S.level}): bites, shots, spit, artillery, blasts, boss attacks. creature_damage_mult is in Settings → Scaling.` }));
    // pass 58: the intended curve against what the rows really carry (the Actual lane above it)
    container.appendChild(section(`Intended and actual`, 'each row keeps the curve of its own start (or its override): the Actual lane averages what spawns round each second'));
    const act = App.actual();
    const ser = act.series;
    const ta = el('table', { class: 'kv wide' });
    ta.appendChild(el('tr', {}, el('td', { text: 'time' }), el('td', { text: 'intended' }), el('td', { text: 'actual average' }), el('td', { text: 'actual largest' })));
    for (const tt of times) {
      const k = Math.max(0, Math.min(ser.ts.length - 1, Math.round(tt)));
      const pick = isHp ? ser.hp : ser.atk;
      const fx = (v) => (v == null ? '–' : `×${fmtN(v, 2)}`);
      ta.appendChild(el('tr', {}, el('td', { text: fmtT(tt) }), el('td', { text: fx(isHp ? App.hpTimeMult(tt) : App.dmgTimeMult(tt)) }), el('td', { text: fx(pick.avg[k]) }), el('td', { text: fx(pick.max[k]) })));
    }
    container.appendChild(ta);
    container.appendChild(el('p', { class: 'muted small', text: `A row keeps the ${isHp ? 'HP' : 'damage'} curve of its own start for its whole life (Garry: "a single wave of those enemies will stay consistent for the duration of their spawns"), so a long row lags the curve and a row with its own ${isHp ? 'HP' : 'damage'} sits wherever that puts it. "–": nothing of the roster or the waves spawns round that second (swarms, coloured elites and the specials are not counted: each takes the curves at the second it comes, or the numbers of a row or wave bringing the same creature then). The average weighs each row by what it spawns (the Spawned so far estimate). The Actual lane shares this curve's scale while the rows fit under it; higher multiples give it its own, up to ${fmtN(Model.ACTUAL_CLAMP, 1)} times as tall, and a ▲ marks anything past its top.` }));
  }

  /** The floor curve (pass 84): its points, what it does, how it compares with the cap. */
  function floorForm(container) {
    const tl = App.tl();
    header(container, 'Floor', 'the least creatures alive', 'floor', Array.isArray(tl.floor_curve) && tl.floor_curve.length ? [{ text: 'Remove the floor', danger: true, title: 'no floor: the game as before pass 84', onclick: () => App.apply((d) => { delete d.floor_curve; }) }] : []);
    const def = FIELDS.SCALARS.find((d) => d.key === 'floor_curve');
    container.appendChild(el('p', { class: 'insp-help', text: def ? def.help : '' }));
    container.appendChild(el('p', { class: 'insp-help', text: 'Drag a point on the Floor lane (Curves), double-click the line to add one, a point to remove it. The On screen lane draws it dotted green against the creatures alive and the cap in bodies; the Warnings say when it sits above the cap.' }));
    const form = el('div', { class: 'form' });
    form.appendChild(Forms.floorBlock(tl));
    const fc = Array.isArray(tl.floor_curve) ? tl.floor_curve.filter((p) => Array.isArray(p)).slice().sort((a, b2) => a[0] - b2[0]) : [];
    if (fc.length) {
      const SL = App.stageLength();
      const samples = [0, SL / 2, SL, SL * 1.5, SL * 2, SL * 2.5, App.runEnd() - 1].map((t) => `${fmtT(t)} → ${Math.round(Model.samplePoints(fc, t))}`);
      form.appendChild(el('p', { class: 'muted small', text: 'Floor by time: ' + samples.join(' · ') }));
    }
    container.appendChild(form);
  }

  /** The portal after a boss (pass 84: its mark on the Events lane): the portal wave, or the portal cap for a while. */
  function portalForm(container) {
    const tl = App.tl();
    header(container, 'Portal', 'what the portal after a boss brings', 'portal', []);
    container.appendChild(el('p', { class: 'insp-help', text: 'When a boss dies its portal opens; until the hero steps through, either one wave of Portal wave count creatures of the rows open as the stage ended comes round him (then nothing), or the crowd is kept up to Portal cap load units for Portal spawns for seconds. No specials come while it waits.' }));
    const form = el('div', { class: 'form' });
    for (const k of ['portal_wave.count', 'portal_cap', 'portal_spawn_seconds']) {
      const def = FIELDS.SCALARS.find((d) => d.key === k);
      if (def) form.appendChild(Forms.fieldRow(def, tl, {}));
    }
    container.appendChild(form);
  }

  function blockForm(container, title, help, block, key) {
    header(container, 'Settings', title, key, []);
    container.appendChild(el('p', { class: 'insp-help', text: help }));
    container.appendChild(block);
  }

  function issues(container) {
    const { errors, warnings } = App.S.issues;
    container.appendChild(el('div', { class: 'insp-head' }, el('div', { class: 'insp-kind', text: 'Nothing selected' }), el('div', { class: 'insp-title', text: errors.length || warnings.length ? 'Checks' : 'All checks pass' })));
    container.appendChild(el('p', { class: 'insp-help', text: 'Click a bar, block or marker to edit it. Drag to move; drag a right edge to set its end. Hover anything for its card (HP and ATK at that second). Delete removes, Ctrl+Z undoes, arrows nudge by a second (Shift: ten), Alt+↑/↓ moves a roster row, Ctrl+S saves.' }));
    const list = el('div', { class: 'issue-list' });
    const toSel = (key) => {
      const [kind, i] = key.split(':');
      if (kind === 'settings') return App.switchTab('settings');
      App.select(i == null ? { kind } : { kind, i: Number(i) }, { scroll: true });
    };
    for (const e of errors) list.appendChild(el('button', { class: 'issue-row error', type: 'button', onclick: () => toSel(e.key) }, el('b', { text: 'error' }), el('span', { text: `${issueName(e.key)}: ${e.msg}` })));
    for (const w of warnings) list.appendChild(el('button', { class: 'issue-row warn', type: 'button', onclick: () => toSel(w.key) }, el('b', { text: 'warning' }), el('span', { text: `${issueName(w.key)}: ${w.msg}` })));
    if (!errors.length && !warnings.length) list.appendChild(el('div', { class: 'muted', text: 'Errors block Save; warnings never do.' }));
    container.appendChild(list);
    const tl = App.tl();
    const facts = el('div', { class: 'facts' });
    facts.appendChild(el('div', { text: `${(tl.roster || []).length} roster rows · ${(tl.waves || []).length} waves · ${(tl.events || []).length} events` }));
    facts.appendChild(el('div', { text: `${App.stages()} stages of ${fmtT(App.stageLength())} · cap ${App.capAt(0)} → ${App.capAt(App.runEnd())} · hard cap ${tl.hard_cap}` }));
    container.appendChild(facts);
  }

  function issueName(key) {
    const [kind, i] = key.split(':');
    const tl = App.tl();
    if (kind === 'roster' && tl.roster && tl.roster[i]) return `row ${App.creatureName(tl.roster[i].enemy)} @ ${fmtT(tl.roster[i].t)}`;
    if (kind === 'wave' && tl.waves && tl.waves[i]) return `wave ${tl.waves[i].name || tl.waves[i].id || i}`;
    if (kind === 'event' && tl.events && tl.events[i]) return `event ${App.eventLabel(tl.events[i])} @ ${fmtT(tl.events[i].t)}`;
    if (kind === 'hp') return 'HP curve';
    if (kind === 'dmg') return 'damage curve';
    return kind;
  }

  return { render, live, overridesBlock, formatShares, patternNote };
})();
