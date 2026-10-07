// The inspector (pass 53, pass 54): the form for whatever is selected on the timeline. Every field of the schema for that
// item, typed, with the creature's own numbers as placeholders under the overrides so Garry sees what he is overriding;
// with nothing selected it lists the validation issues (each a button that selects the item). Pass 54: a roster row's
// presence points and order buttons, the Elite overrides as the variance block with colour swatches, the HP x / ATK x
// curves with their mode switch, and the Share band's table. Pass 57: a note under a row's, a wave's or a swarm's Pattern
// field: for Ring how many of the creature make a thick ring and how many really come at once, for In front where from.
'use strict';

const Inspector = (() => {
  const { el, fmtT, fmtN, clear } = U;

  function render(container) {
    Forms.closePop();
    const active = container.contains(document.activeElement) ? document.activeElement.dataset.path : null;
    const scroll = container.scrollTop;
    const sameItem = container.dataset.sel === App.selKey();
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
    else if (sel.kind === 'share') shareForm(container);
    else if (sel.kind === 'specials') blockForm(container, 'Specials', 'the specials\' clock: one at a time, a random interval after the last one dies', Forms.specialsBlock(App.tl()), 'specials');
    else if (sel.kind === 'paths') blockForm(container, 'Path offers', 'when each stage puts a weapon\'s whole path on the table', Forms.pathTimesBlock(App.tl()), 'paths');
    else if (sel.kind === 'pickups') blockForm(container, 'Power-up drops', 'what kills drop and how often', Forms.pickupsBlock(App.tl()), 'pickups');
    // the same item drawn again (an edit in its form) keeps its place in a long form
    if (sameItem) container.scrollTop = scroll;
    if (active) { const again = container.querySelector(`[data-path="${CSS.escape(active)}"]`); if (again) again.focus({ preventScroll: true }); }
  }

  // ------------------------------------------------------------------ pieces

  function header(container, kind, title, key, actions, sub) {
    const h = el('div', { class: 'insp-head' }, el('div', { class: 'insp-kind', text: kind }), el('div', { class: 'insp-title', text: title }));
    const acts = el('div', { class: 'insp-actions' });
    for (const a of actions || []) acts.appendChild(el('button', { class: 'btn small' + (a.danger ? ' danger' : '') + (a.cls ? ' ' + a.cls : ''), type: 'button', text: a.text, title: a.title || '', disabled: !!a.disabled, onclick: a.onclick }));
    acts.appendChild(el('button', { class: 'btn small ghost', type: 'button', text: '✕', title: 'close (Esc)', onclick: () => App.select(null) }));
    h.appendChild(acts);
    if (sub) h.appendChild(el('div', { class: 'insp-sub', text: sub }));
    container.appendChild(h);
    const m = App.issuesFor(key);
    if (m) container.appendChild(el('div', { class: 'insp-issues ' + m.level }, m.msgs.map((x) => el('div', { text: x }))));
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
        return overridesBlock(obj, def.key, ctx.enemyId, (ctx && ctx.pathPrefix ? ctx.pathPrefix + '.' : '') + def.key);
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
      const radius = st.radius != null ? Number(st.radius) : Number(c.radius);
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

  /** The `stats` block of `holder[key]` for `creatureId`: every override key, the creature's own value as the placeholder. */
  function overridesBlock(holder, key, creatureId, pathPrefix) {
    const c = App.creature(creatureId);
    const stats = U.isObj(holder[key]) ? holder[key] : {};
    const n = countLeaves(stats);
    const det = el('details', { class: 'overrides', open: n > 0 });
    det.appendChild(el('summary', {}, el('b', { text: `Overrides · ${n} set` }), el('span', { class: 'muted', text: c ? ` · grey = ${U.theName(c.name)}'s own numbers` : '' })));
    const write = (path, v) => App.apply(() => {
      if (!U.isObj(holder[key])) holder[key] = {};
      U.setPath(holder[key], path, v);
      if (!Object.keys(holder[key]).length) delete holder[key];
    });
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
        const ph = def.ph ? def.ph(c, App.tl()) : '';
        const path = `${pathPrefix}.${def.path}`;
        let ctl;
        if (def.type === 'number' || def.type === 'int') ctl = Forms.numberInput(def, value, (v) => write(def.path, v), { placeholder: ph === '' ? '—' : (typeof ph === 'number' ? fmtN(ph, 3) : ph), path });
        else if (def.type === 'bool3') ctl = Forms.bool3Input(def, value, (v) => write(def.path, v), { placeholder: ph, path });
        else if (def.type === 'pickup') ctl = Forms.pickupSelect(value, (v) => write(def.path, v), { path, emptyLabel: ph ? `— (${App.pickup(ph) ? App.pickup(ph).name : ph})` : '—', emptyIcon: ph && App.pickup(ph) ? App.pickup(ph).icon : '' });
        else if (def.type === 'attacks') ctl = attacksControl(stats, c, write, path);
        else if (def.type === 'pickup_weights') ctl = pickupWeightsControl(stats, write, path);
        else if (def.type === 'swatch') ctl = Forms.swatchInput(value, (v) => write(def.path, v), { placeholder: ph, path });
        else if (def.type === 'swatches') ctl = Forms.swatchesInput(value, (v) => write(def.path, v), { placeholder: ph, path });
        else ctl = el('span', { class: 'muted', text: def.type });
        fs.appendChild(Forms.row(def, ctl, { cls: value !== undefined ? 'is-set' : '' }));
      }
      if (group === 'Elite') {
        const fsh = formatShares(stats);
        fs.appendChild(el('p', { class: 'muted small', text: `A coloured elite from this row comes alone ${Math.round(fsh.single * 100)}% · as its pack ${Math.round(fsh.pack * 100)}% · as a ring ${Math.round(fsh.ring * 100)}% (once one chance is set, an empty one counts 0).` }));
      }
      det.appendChild(fs);
    }
    return det;
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

  function rosterForm(container, r, i) {
    const key = `roster:${i}`;
    const rows = App.tl().roster || [];
    header(container, 'Roster row', `${App.creatureName(r.enemy)} · ${fmtT(r.t)} → ${r.until == null ? 'end' : fmtT(r.until)}`, key, [
      { text: '▲', title: 'move the row up (Alt+↑): the order is for this page only, the game draws by weight', disabled: i === 0, cls: 'order', onclick: () => App.moveRow(i, -1) },
      { text: '▼', title: 'move the row down (Alt+↓)', disabled: i >= rows.length - 1, cls: 'order', onclick: () => App.moveRow(i, 1) },
      ...listActions(),
    ], `${r.id ? `id ${r.id} · ` : ''}row ${i + 1} of ${rows.length}`);
    const c = App.creature(r.enemy);
    const form = el('div', { class: 'form' });
    for (const def of FIELDS.roster) {
      if (def.key === 'id') continue;
      if (def.type === 'weights') { form.appendChild(Forms.row(def, Forms.weightsBlock(r), { cls: 'wide-ctl' })); continue; }
      form.appendChild(fieldFor(def, r, { enemyId: r.enemy, placeholders: { pack: c ? c.pack_size : '' }, note: def.key === 'pattern' ? patternNote('roster', r) : null }));
    }
    const t0 = Math.max(Number(r.t) || 0, 0);
    const open = App.rosterAt(t0).find((o) => o.i === i);
    const lines = [];
    if (open) lines.push(`At ${fmtT(t0)} this row weighs ${fmtN(open.w, 2)}: ${Math.round(open.norm * 100)}% of its channel's draw.`);
    if (c) {
      const at = App.creatureAt(c, r.stats, t0);
      lines.push(`One spawned at ${fmtT(t0)}: HP ${fmtN(at.hp, 1)} · ATK ${fmtN(at.atk, 1)} (hero level ${App.S.level}; hover the bar for any other time).`);
    }
    lines.push('The order of the rows is for this page only: the game draws a burst by the weights, whatever the order.');
    for (const l of lines) form.appendChild(el('p', { class: 'muted small', text: l }));
    container.appendChild(form);
    jsonPeek(container, r);
  }

  // ------------------------------------------------------------------ waves

  function waveForm(container, w, i) {
    const key = `wave:${i}`;
    const end = App.waveEnd(w);
    header(container, 'Wave', `${w.name || w.id || 'wave'} · ${fmtT(w.t)} → ${end === Infinity ? 'no end' : fmtT(end)}`, key, listActions());
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
        wrap.appendChild(fieldFor(def, w, { enemyId: w.enemy, placeholders: { pack: c ? c.pack_size : '' } }));
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
      for (const def of FIELDS.alt) card.appendChild(fieldFor(def, a, { enemyId: a.enemy, pathPrefix: `alts.${k}`, placeholders: { pack: c ? c.pack_size : '' } }));
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
    header(container, 'Event', `${App.eventLabel(ev)} · ${fmtT(ev.t)}`, key, listActions());
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
      } else if (def.type === 'variant') {
        form.appendChild(Forms.row(def, Forms.variantSelect(ids[0] || '', ev.variant, (v) => App.apply(() => U.setKey(ev, 'variant', v)), { path: 'variant' })));
      } else if (def.type === 'overrides') {
        form.appendChild(overridesBlock(ev, 'stats', ids[0] || '', 'stats'));
      } else {
        form.appendChild(Forms.fieldRow(def, ev, { allowRandom: false, emptyLabel: def.key === 'mod' ? 'random modifier' : undefined, note: def.key === 'pattern' ? patternNote('event', ev) : null }));
      }
    }
    if (ev.type === 'elite_every') {
      const iv = ev.interval;
      const lo = Array.isArray(iv) ? Number(iv[0]) : Number(iv == null ? 90 : iv);
      const hi = Array.isArray(iv) ? Number(iv[iv.length - 1]) : lo;
      const left = App.runEnd() - (Number(ev.t) || 0);
      if (lo > 0) form.appendChild(el('p', { class: 'muted small', text: `About ${Math.floor(left / ((lo + hi) / 2))} coloured elites before the last boss (Hot Sauce makes them come sooner). With no creature named, each is drawn from the open roster rows by their Elite weight (Overrides → Elite).` }));
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
      ? `For an ordinary creature (hero level ${App.S.level}, the box in the top bar). An Elite-archetype mini-boss ignores the curve and the level (elite.hp_mult_per_stage^stage × stage × creature_hp_mult); a boss ignores creature_hp_mult too.`
      : `Every hostile damage (hero level ${App.S.level}): bites, shots, spit, artillery, blasts, boss attacks. creature_damage_mult is in Settings → Scaling.` }));
  }

  /** The Share band's table: each creature's share of its channel's draw at the stage marks and halfway through. */
  function shareForm(container) {
    const lane = FIELDS.LANES.find((l) => l.id === 'share');
    header(container, 'Share', 'each creature\'s share of the draw', 'share', []);
    container.appendChild(el('p', { class: 'insp-help', text: lane ? lane.text : '' }));
    const SL = App.stageLength();
    const times = [];
    for (let k = 0; k < App.stages(); k++) { times.push(k * SL + 1); times.push(k * SL + SL / 2); }
    const rows = App.tl().roster || [];
    const seen = [];
    for (const r of rows.slice().sort((a, b) => (Number(a.t) || 0) - (Number(b.t) || 0))) {
      const k = `${r.channel === 'hell' ? 'hell' : 'reg'}:${r.enemy}`;
      if (!seen.find((s) => s.k === k)) seen.push({ k, id: r.enemy, hell: r.channel === 'hell' });
    }
    const shareAt = (t) => {
      const out = {};
      for (const o of App.rosterAt(t)) { const k = `${o.hell ? 'hell' : 'reg'}:${o.row.enemy}`; out[k] = (out[k] || 0) + o.norm; }
      return out;
    };
    const cols = times.map(shareAt);
    const tbl = el('table', { class: 'share-table' });
    tbl.appendChild(el('tr', {}, el('th', { text: 'creature' }), times.map((t) => el('th', { text: fmtT(t) }))));
    for (const s of seen) {
      const c = App.creature(s.id);
      tbl.appendChild(el('tr', { class: s.hell ? 'hell' : '' },
        el('td', { class: 'sh-name' }, el('span', { class: 'sh-sw', style: `background:${App.creatureColor(s.id)}` }), c ? el('img', { src: App.iconFor(s.id), width: 18, height: 18 }) : null, el('span', { text: App.creatureName(s.id) + (s.hell ? ' (hell)' : '') })),
        cols.map((col) => el('td', { class: 'sh-pct', text: col[s.k] ? `${Math.round(col[s.k] * 100)}%` : '' }))));
    }
    container.appendChild(tbl);
    container.appendChild(el('p', { class: 'muted small', text: 'Each column sums to 100% per channel (the regular crowd, the hell channel). Hover the band for any other second.' }));
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

  return { render, overridesBlock, formatShares, patternNote };
})();
