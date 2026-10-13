'use strict';
// Pass 66 (lane P): the enemy / elite / boss editor pane shown under the Enemies tab beside the palette (creatures.js).
// One form for all three, archetype-driven: a sticky header (assets.js), the compare-with-template panel (HP, bite,
// speed, XP, knockback, size, radius, pack; HP at 0:00 / 5:00 / 12:00 on a map of its own choosing through
// Model.creatureAt; seconds to kill with a level-1 Revolver; bites to kill the hero; the ring hint), then the sections of
// AFIELDS.enemy: Identity, Body, Brain & attacks (the brain's natural blocks, the ones the file carries, "+ Add block",
// the untested-combination note), the Attack script (attack cards with the keys their name reads, up / down, a telegraph
// picture drawn to scale with EnemyManager.gd:3638-3676's rules, the sequence line with the map's pacing), Spawning,
// Drops, Variance (with the tinted standing frame), Sounds, Looks (lane V's LookGrid, the jobs' buttons, the look's
// recipe), Art words.
const Enemies = (() => {
  const { el, clear, fmtN, fmtT } = U;
  const M = AssetsModel, F = AFIELDS;
  const RED = 'rgba(237, 74, 92, 0.9)';
  // which brains read a block (EnemyManager.gd:2858-3365); "any" = every creature
  const READ_BY = { ranged: ['kite', 'ambush', 'dummy'], charge: ['charge'], kamikaze: ['kamikaze'], artillery: ['artillery'], caster: ['caster'], support: ['support'], ambush: ['ambush'], death_burst: ['any'], boss: ['any'], elite: ['elite archetype'] };

  function render(pane, doc) {
    const iss = Assets.issuesOf(doc);
    const defs = F.table(doc.kind);
    pane.appendChild(Assets.header(doc, iss));
    pane.appendChild(comparePanel(doc));
    const sec = (name, nodes, opts) => Assets.section(doc, name, nodes, Object.assign({ marks: Assets.sectionMarks(iss, (opts && opts.keys) || Assets.sectionKeys(defs, name)) }, opts || {}));
    pane.appendChild(sec('Identity', Assets.rows(doc, defs, 'Identity', iss), { open: true }));
    pane.appendChild(sec('Body', Assets.rows(doc, defs, 'Body', iss), { open: true }));
    pane.appendChild(sec('Brain & attacks', brainBlocks(doc, iss), { open: true, keys: ['brain'].concat(M.BLOCK_NAMES), foot: 'Every wind-up and telegraph lasts its seconds x 1/pace (the map\'s move_pace x creature_speed_mult). The blocks and attack names are the game\'s: a new one needs code, ask Claude.' }));
    pane.appendChild(sec('Attack script', attackScript(doc, iss), { open: hasScript(doc.data), keys: ['boss.attacks', 'boss.cooldown_between'], chips: [el('span', { class: 'achip', text: `${attacksOf(doc.data).length} attack${attacksOf(doc.data).length === 1 ? '' : 's'}` })] }));
    pane.appendChild(sec('Spawning', Assets.rows(doc, defs, 'Spawning', iss)));
    pane.appendChild(sec('Drops', Assets.rows(doc, defs, 'Drops', iss), { foot: 'When the whole drops block is absent the game plays {small 1, gold 0.02}; an Elite or coloured creature always drops a chest; a dummy drops nothing.' }));
    pane.appendChild(sec('Variance', Assets.rows(doc, defs, 'Variance', iss).concat([tintPreview(doc)])));
    // pass 69 (lane EN): the coloured special on its own: its numbers, what applies and from where, and how it looks
    pane.appendChild(sec('Special', Assets.rows(doc, defs, 'Special', iss).concat([specialPreview(doc)]), { foot: 'A special rolls once the map\'s Colour after kills is reached (× (1 + difficulty) with Hot Sauce); a swarm event set to Special (the Timeline\'s events) brings one for sure. An empty box takes the map\'s Settings → Coloured specials, else the game\'s default.' }));
    pane.appendChild(sec('Sounds', Assets.rows(doc, defs, 'Sounds', iss), { foot: 'Ids from content/sounds/soundmap.json; an unknown id is silent. A new sound: add a row to the sound map (gen_sfx.py / ai_sfx.py), then it is listable here.' }));
    const lookChips = [el('span', { class: 'achip', text: `${doc.looks.length} look${doc.looks.length === 1 ? '' : 's'}` })];
    if (doc.looks.some((l) => l.fresh)) lookChips.push(el('span', { class: 'achip warn', text: `${doc.looks.filter((l) => l.fresh).length} new` }));
    if (doc.looks.some((l) => l.shelved)) lookChips.push(el('span', { class: 'achip hidden', text: `${doc.looks.filter((l) => l.shelved).length} shelved` }));
    pane.appendChild(sec('Looks', [Assets.looksSection(doc, iss)].concat(Assets.rows(doc, defs, 'Looks', iss)), { open: true, chips: lookChips, keys: ['looks', 'variant', 'variant_base', 'anims', 'strip_cols', 'frame_px', 'fps', 'directions'] }));
    pane.appendChild(sec('Art words', Assets.rows(doc, defs, 'Art words', iss), { foot: 'The words gen_art.py and gen_ctl.py send to the painter for the base look; each look\'s own recipe (in Looks) overrides them.' }));
  }

  const attacksOf = (d) => (M.isObj(d.boss) && Array.isArray(d.boss.attacks) ? d.boss.attacks : []);
  const hasScript = (d) => d.archetype === 'boss' || d.archetype === 'elite' || d.brain === 'boss' || d.brain === 'caster' || M.isObj(d.boss);

  // ------------------------------------------------------------------ compare with the template

  function comparePanel(doc) {
    const d = doc.data;
    const ui = doc.ui;
    const others = App.S.enemies.filter((c) => c.id !== doc.id);
    if (!ui.compareWith) ui.compareWith = doc.templateId || (others.find((c) => c.id === 'skeleton') || others[0] || {}).id || null;
    const tmpl = ui.compareWith ? App.creature(ui.compareWith) : null;
    const mine = M.enemyRecord(d, doc.kind, doc.id);
    const card = el('details', { class: 'asection compare' });
    card.open = ui.compareOpen == null ? true : !!ui.compareOpen;
    card.addEventListener('toggle', () => { ui.compareOpen = card.open; });
    const sum = el('summary', {}, el('span', { class: 'asec-title', text: 'Compare with' }));
    card.appendChild(sum);
    const body = el('div', { class: 'asec-body' });
    const pick = Forms.enemyPick(ui.compareWith || '', (v) => { ui.compareWith = v; Assets.redraw(doc, 'editor'); }, { path: 'compare.with', summary: false, emptyLabel: 'a creature…' });
    const maps = (App.S.maps || []).map((m) => ({ v: m.id, label: m.name || m.id }));
    if (!maps.some((m) => m.v === 'red_canyon')) maps.unshift({ v: 'red_canyon', label: 'Red Canyon' });
    const mapSel = Forms.select(maps, ui.map || 'red_canyon', (v) => { ui.map = v || 'red_canyon'; Assets.redraw(doc, 'editor'); }, { path: 'compare.map' });
    body.appendChild(el('div', { class: 'compare-bar' }, el('span', { class: 'muted small', text: 'template' }), pick, el('span', { class: 'muted small', text: 'on' }), mapSel, el('span', { class: 'muted small', text: `hero level ${App.S.level} (the top bar)` })));
    const tl = Assets.mapTl(ui.map || 'red_canyon');
    const tbl = el('table', { class: 'kv ctable' });
    tbl.appendChild(el('tr', {}, el('th'), el('th', { text: tmpl ? tmpl.name : 'template' }), el('th', { text: d.name || doc.id }), el('th', { text: 'Δ' })));
    const row = (label, a, b, fmt, title) => {
      const f = fmt || ((x) => fmtN(x, 2));
      let delta = '';
      if (a != null && b != null && isFinite(a) && isFinite(b)) delta = a === 0 ? (b === 0 ? '0 %' : '—') : `${b >= a ? '+' : '−'}${Math.round(Math.abs(b - a) / Math.abs(a) * 100)} %`;
      tbl.appendChild(el('tr', { title: title || '' }, el('td', { text: label }), el('td', { text: a == null ? '—' : f(a) }), el('td', { class: 'mine', text: b == null ? '—' : f(b) }), el('td', { class: 'delta ' + (b > a ? 'up' : b < a ? 'down' : ''), text: delta })));
    };
    const t = tmpl || {};
    row('HP', t.hp, mine.hp);
    row('bite', t.damage, mine.damage);
    row('speed m/s', t.speed, mine.speed);
    row('XP ×', t.xp_mult, mine.xp_mult);
    row('knockback', tmpl ? Model.knockbackOf(t, null).value : null, Model.knockbackOf(mine, null).value, (x) => fmtN(x, 2), 'the bite\'s shove (the game\'s default when the file has none)');
    row('KB resist', t.knockback_resist, mine.knockback_resist, (x) => `${Math.round(x * 100)} %`, 'the share of every shove from the hero\'s side it shrugs off (pass 67; the other way round from knockback)');
    row('size m', t.size, mine.size);
    row('radius m', t.radius, mine.radius);
    row('pack', t.pack_size, mine.pack_size, (x) => String(x));
    if (tl) {
      const times = [0, 300, 720];
      const at = (c, s) => (c ? Model.creatureAt(tl, c, null, s, App.S.level) : null);
      for (const s of times) {
        const a = at(tmpl, s), b = at(mine, s);
        row(`HP at ${fmtT(s)}`, a ? a.hp : null, b ? b.hp : null, (x) => fmtN(x, 1), `stage × ${b ? fmtN(b.stageMult, 2) : ''} · HP curve × ${b && b.hpParts ? fmtN(b.hpParts[1][1], 2) : ''} · creature_hp_mult × ${b ? fmtN(b.chm, 2) : ''} · level × ${b ? fmtN(b.lvHp, 2) : ''}${mine.archetype !== 'walker' && (mine.archetype === 'boss' || mine.archetype === 'elite') ? ' · the ' + mine.archetype + ' rule: hp × hp_mult_per_stage^stage × max(stage mult, 1)' : ''}`);
      }
      const rev = (Assets.flatItems() && Assets.flatItems().weapons.find((w) => w.id === 'revolver')) || null;
      const base = rev && rev.base ? rev.base : { damage: 20, cooldown: 1.0, amount: 1 };
      for (const s of times) {
        const a = at(tmpl, s), b = at(mine, s);
        const ta = a ? M.revolverTTK(a.hp, base) : null, tb = b ? M.revolverTTK(b.hp, base) : null;
        row(`Revolver L1 at ${fmtT(s)}`, ta ? ta.seconds : null, tb ? tb.seconds : null, (x) => `${fmtN(x, 1)} s`, `shots = ceil(HP / ${base.damage} × ${base.amount}), seconds = (shots − 1) × ${base.cooldown}; the first shot at once; pierce, attack damage and crits ignored${tb ? ` (${tb.shots} shot${tb.shots === 1 ? '' : 's'})` : ''}`);
      }
      for (const s of times) {
        const a = at(tmpl, s), b = at(mine, s);
        row(`bites to kill the hero at ${fmtT(s)}`, a ? M.hitsToKill(a.atk) : null, b ? M.hitsToKill(b.atk) : null, (x) => (isFinite(x) ? String(x) : '∞'), 'ceil(100 max HP / the bite at that second: bite × stage × damage curve × creature_damage_mult × level)');
      }
    } else body.appendChild(el('p', { class: 'muted small', text: 'reading the map for the HP curve…' }));
    body.appendChild(tbl);
    const ring = U.ringCount(mine.radius);
    body.appendChild(el('p', { class: 'muted small', text: `A ring of these: about ${ring.row} shoulder to shoulder round the hero (${fmtN(U.RING_RADIUS, 1)} m), ${ring.thick} as a thick ring. Wind-ups on ${(ui.map || 'red_canyon')}: ×${tl ? fmtN(M.paceOf(tl), 2) : '…'} (1 / (move_pace × creature_speed_mult)).` }));
    card.appendChild(body);
    return card;
  }

  // ------------------------------------------------------------------ brain and blocks

  function brainBlocks(doc, iss) {
    const d = doc.data;
    const defs = F.table(doc.kind);
    const out = [];
    const brainDef = defs.find((x) => x.key === 'brain');
    const archDef = defs.find((x) => x.key === 'archetype');
    out.push(Assets.fieldRow(doc, archDef, iss));
    out.push(Assets.fieldRow(doc, brainDef, iss));
    const seen = Assets.seenCombos(doc);
    const combo = M.combo(d);
    const users = App.S.enemies.filter((c) => c.id !== doc.id && `${c.brain || 'chase'}|${['ranged', 'charge', 'kamikaze', 'artillery', 'boss', 'elite'].filter((b) => c[b]).sort().join('+')}` === combo);
    if (seen.size && !seen.has(combo)) out.push(el('div', { class: 'anote warn', 'data-key': 'brain' }, el('b', { text: 'Untested combination: ' }), el('span', { text: `no creature in play uses ${M.comboWords(d)}. Any brain and block mix is allowed; this one has never been watched in a run.` })));
    else if (users.length) out.push(el('div', { class: 'anote', 'data-key': 'brain' }, el('span', { class: 'muted small', text: `${M.comboWords(d)}: as ${users.slice(0, 4).map((c) => c.name).join(', ')}${users.length > 4 ? ` and ${users.length - 4} more` : ''}` })));
    const natural = M.naturalBlocks(d.brain || 'chase', d.archetype || 'walker');
    const present = M.blocksOf(d);
    const shown = F.BLOCK_ORDER.filter((b) => natural.includes(b) || present.includes(b));
    const blocks = el('div', { class: 'blocks' });
    for (const b of shown) {
      const spec = F.BLOCKS[b];
      const isNat = natural.includes(b), isPresent = present.includes(b);
      const readers = READ_BY[b] || [];
      const readNote = readers[0] === 'any' ? 'read by every creature' : readers[0] === 'elite archetype' ? 'read for the elite archetype' : `read by the ${readers.join(' / ')} brain${readers.length > 1 ? 's' : ''}`;
      const card = el('div', { class: 'block-card' + (isNat ? ' natural' : ' extra') + (isPresent ? '' : ' empty'), 'data-key': b });
      const head = el('div', { class: 'block-head' }, el('b', { text: spec.label }), el('span', { class: 'achip ' + (isNat ? 'available' : 'warn'), text: isNat ? readNote : `${readNote}: the ${d.brain || 'chase'} brain does not` }),
        isPresent ? el('button', { class: 'btn small ghost', type: 'button', text: '× remove block', title: `delete the ${b} block from the file`, onclick: () => Assets.apply(doc, (dd) => { delete dd[b]; }, 'editor') }) : el('span', { class: 'muted small', text: 'not in the file: the game\'s defaults (grey); a value typed adds the block' }));
      card.appendChild(head);
      card.appendChild(el('p', { class: 'muted small', text: spec.help }));
      if (b === 'boss') card.appendChild(el('p', { class: 'muted small', text: 'The attacks themselves are edited in the Attack script section below.' }));
      for (const r of spec.rows) {
        if (r.type === 'attacks') continue;
        if (typeof r.only === 'function' && !r.only(d)) continue;
        const def2 = Object.assign({}, r, { key: `${b}.${r.key}` });
        const rowEl = Assets.fieldRow(doc, def2, iss);
        if (rowEl) card.appendChild(rowEl);
      }
      blocks.appendChild(card);
    }
    out.push(blocks);
    const addable = F.BLOCK_ORDER.filter((b) => !shown.includes(b));
    if (addable.length) {
      const sel = Forms.select(addable.map((b) => ({ v: b, label: F.BLOCKS[b].label, help: F.BLOCKS[b].help })), '', (v) => { if (v) Assets.apply(doc, (dd) => { dd[v] = {}; }, 'editor'); }, { emptyLabel: '+ Add block ▾', path: 'blocks.add' });
      out.push(el('div', { class: 'alt-actions' }, sel, el('span', { class: 'muted small', text: 'a block the brain does not read is kept in the file and does nothing in play' })));
    }
    return out;
  }

  // ------------------------------------------------------------------ the attack script

  function attackScript(doc, iss) {
    const d = doc.data;
    const out = [];
    const attacks = attacksOf(d);
    if (!hasScript(d) && !attacks.length) {
      out.push(el('p', { class: 'muted small', text: 'No script: the attack runner serves the boss and caster brains and any creature with attacks in a boss block. Add a boss block (Brain & attacks) or an attack here to start one.' }));
    }
    const tl = Assets.mapTl(doc.ui.map || 'red_canyon');
    const pf = tl ? M.paceOf(tl) : 1;
    const radius = M.num(d.radius, 0.5);
    const write = (fn) => Assets.apply(doc, (dd) => { if (!M.isObj(dd.boss)) dd.boss = {}; if (!Array.isArray(dd.boss.attacks)) dd.boss.attacks = []; fn(dd.boss.attacks, dd); }, 'editor');
    const list = el('div', { class: 'attacks' });
    attacks.forEach((atk0, i) => {
      const atk = M.isObj(atk0) ? atk0 : { name: String(atk0) };
      const name = String(atk.name || '');
      const spec = F.ATTACKS[name] || null;
      // pass 72 (lane BOSS): a custom attack of content/boss_attacks (made on the Boss attacks tab)
      const custom = !spec && typeof BossAttacks !== 'undefined' && BossAttacks.get ? BossAttacks.get(name) : null;
      const tel = F.attackTelegraph(atk);
      const card = el('div', { class: 'atk-card' + (spec || custom ? '' : ' unknown'), 'data-key': `boss.attacks.${i}` });
      const setKey = (k, v) => write((arr) => { const a = M.isObj(arr[i]) ? arr[i] : { name: String(arr[i]) }; if (v == null || v === '') delete a[k]; else a[k] = v; arr[i] = a; });
      const nameSel = Forms.select(F.attackOptions(), name, (v) => setKey('name', v), { path: `boss.attacks.${i}.name`, emptyLabel: 'name…' });
      const head = el('div', { class: 'atk-head' },
        el('span', { class: 'atk-n', text: `#${i + 1}` }), nameSel,
        el('span', { class: 'muted small', text: spec ? spec.help : custom ? `custom attack "${custom.name || name}" (${custom.kind}): its own numbers are on the Boss attacks tab; the keys below override them for this boss` : (name ? 'an unknown name: the game does nothing for it' : '') }),
        custom ? el('button', { class: 'btn small', type: 'button', text: 'Open in Boss attacks', onclick: () => BossAttacks.open(name) }) : null,
        el('span', { class: 'atk-ops' },
          el('button', { class: 'btn small ghost', type: 'button', text: '▲', title: 'earlier', disabled: i === 0, onclick: () => write((arr) => { const [x] = arr.splice(i, 1); arr.splice(i - 1, 0, x); }) }),
          el('button', { class: 'btn small ghost', type: 'button', text: '▼', title: 'later', disabled: i === attacks.length - 1, onclick: () => write((arr) => { const [x] = arr.splice(i, 1); arr.splice(i + 1, 0, x); }) }),
          el('button', { class: 'btn small ghost', type: 'button', text: '⧉', title: 'duplicate', onclick: () => write((arr) => { arr.splice(i + 1, 0, JSON.parse(JSON.stringify(arr[i]))); }) }),
          el('button', { class: 'x', type: 'button', text: '×', title: 'remove this attack', onclick: () => write((arr) => { arr.splice(i, 1); }) })));
      card.appendChild(head);
      const body = el('div', { class: 'atk-body' });
      const keys = el('div', { class: 'atk-keys' });
      const common = F.ATTACK_COMMON.map((r) => (r.key === 'telegraph' ? Object.assign({}, r, { def: spec ? spec.telegraph : 'none' }) : r));
      const rowsDefs = common.concat(spec ? spec.keys : Object.keys(atk).filter((k) => !['name', 'windup', 'telegraph', 'reach', 'min_range', 'max_range'].includes(k)).map((k) => ({ key: k, label: k, type: typeof atk[k] === 'boolean' ? 'bool' : typeof atk[k] === 'number' ? 'number' : 'text' })));
      for (const r of rowsDefs) keys.appendChild(attackField(doc, i, r, atk, setKey));
      // keys the file has that the name does not read
      if (spec) {
        const known = new Set(['name'].concat(common.map((r) => r.key), spec.keys.map((r) => r.key)));
        const extra = Object.keys(atk).filter((k) => !known.has(k));
        if (extra.length) keys.appendChild(el('div', { class: 'muted small punknown' }, el('span', { class: 'ydot' }), el('span', { text: ` keys ${name} does not read: ${extra.join(', ')}` })));
      }
      body.appendChild(keys);
      body.appendChild(telegraphPicture(atk, tel, radius, pf));
      card.appendChild(body);
      const m = iss.marks[`boss.attacks.${i}`];
      if (m) card.appendChild(el('div', { class: 'ferr ' + m.level, text: m.msgs.join(' · ') }));
      list.appendChild(card);
    });
    out.push(list);
    const addSel = Forms.select(F.attackOptions(), '', (v) => { if (v) write((arr) => { arr.push({ name: v }); }); }, { emptyLabel: '+ attack ▾', path: 'boss.attacks.add' });
    out.push(el('div', { class: 'alt-actions' }, addSel, el('span', { class: 'muted small', text: 'the 14 names EnemyManager knows, then the custom attacks (★, pass 72: made on the Boss attacks tab without code: a rain, a volley, a ring, a slam or a built-in with your numbers)' })));
    const m = iss.marks['boss.attacks'];
    if (m) out.push(el('div', { class: 'ferr ' + m.level, 'data-key': 'boss.attacks', text: m.msgs.join(' · ') }));
    if (attacks.length) out.push(sequenceLine(d, pf, doc.ui.map || 'red_canyon', tl));
    const bossDefs = F.BLOCKS.boss.rows.filter((r) => r.type !== 'attacks' && (typeof r.only !== 'function' || r.only(d)));
    for (const r of bossDefs) { const rowEl = Assets.fieldRow(doc, Object.assign({}, r, { key: 'boss.' + r.key }), iss); if (rowEl) out.push(rowEl); }
    return out;
  }

  function attackField(doc, i, r, atk, setKey) {
    const val = atk[r.key];
    const path = `boss.attacks.${i}.${r.key}`;
    let ctl;
    const ph = r.def == null ? '' : String(r.def);
    if (r.type === 'select') {
      const opts = typeof r.options === 'function' ? r.options(Assets.vocab()) : (r.options || []);
      ctl = Forms.select(opts, val == null ? '' : val, (v) => setKey(r.key, v), { path, emptyLabel: r.key === 'telegraph' ? `usual (${r.def || 'none'})` : (r.key === 'to' ? 'a step away' : '—') });
    } else if (r.type === 'bool') ctl = Forms.bool3Input({ key: path }, val, (v) => setKey(r.key, v), { path, placeholder: ph || 'no' });
    else if (r.type === 'enemy') ctl = Forms.enemyPick(val || '', (v) => setKey(r.key, v), { path, summary: false, emptyLabel: r.key === 'enemy' ? '— (the game\'s default "coyote" no longer exists)' : '—' });
    else if (r.type === 'text') ctl = Forms.textInput({ key: path }, val, (v) => setKey(r.key, v), { path, placeholder: ph });
    else ctl = Forms.numberInput({ key: path, min: r.min, step: r.type === 'int' ? 1 : (r.step || 'any'), int: r.type === 'int' }, val, (v) => setKey(r.key, v), { path, placeholder: ph, cls: 'short' });
    return Forms.row({ key: path, label: r.label, help: r.help || '' }, ctl, {});
  }

  /** The telegraph as the ground shows it, to scale: the creature a circle of its radius at the bottom, the hero a dot
   *  8 m ahead; red what the wind-up draws (EnemyManager.gd:3638-3676 through AssetsModel.telegraphGeometry). */
  function telegraphPicture(atk, tel, radius, pf) {
    const g = M.telegraphGeometry(atk, tel, radius);
    const W = 240, H = 240;
    const cx = 120, cy = 176;
    const heroDist = 8;
    let extent = heroDist + 2;
    if (g.kind === 'line') extent = Math.max(extent, g.length);
    if (g.kind === 'ring') extent = Math.max(extent, g.atHero ? heroDist + g.radius : g.radius);
    if (g.kind === 'sector') extent = Math.max(extent, g.radius);
    if (g.kind === 'fan' || g.kind === 'spokes') extent = Math.max(extent, g.length);
    const ppm = Math.min(6, 150 / Math.max(extent, 1));
    const svg = U.svg('svg', { class: 'atk-pic', viewBox: `0 0 ${W} ${H}`, width: W, height: H });
    svg.appendChild(U.svg('rect', { x: 0, y: 0, width: W, height: H, rx: 8, class: 'tp-ground' }));
    const up = (m) => cy - m * ppm;
    const red = (node) => { node.setAttribute('fill', 'rgba(237,74,92,0.28)'); node.setAttribute('stroke', RED); node.setAttribute('stroke-width', '2'); return node; };
    if (g.kind === 'line') svg.appendChild(red(U.svg('rect', { x: cx - 5, y: up(g.length), width: 10, height: g.length * ppm, rx: 3 })));
    else if (g.kind === 'ring') { const y = g.atHero ? up(heroDist) : cy; svg.appendChild(red(U.svg('circle', { cx, cy: y, r: g.radius * ppm }))); }
    else if (g.kind === 'sector') {
      const r = g.radius * ppm, a = g.deg * Math.PI / 180;
      const x1 = cx + r * Math.sin(-a / 2), y1 = cy - r * Math.cos(-a / 2), x2 = cx + r * Math.sin(a / 2), y2 = cy - r * Math.cos(a / 2);
      const large = g.deg > 180 ? 1 : 0;
      svg.appendChild(red(U.svg('path', { d: g.deg >= 360 ? `M ${cx - r} ${cy} A ${r} ${r} 0 1 0 ${cx + r} ${cy} A ${r} ${r} 0 1 0 ${cx - r} ${cy}` : `M ${cx} ${cy} L ${x1} ${y1} A ${r} ${r} 0 ${large} 1 ${x2} ${y2} Z` })));
    } else if (g.kind === 'fan') {
      const spread = g.spread * Math.PI / 180;
      for (let k = 0; k < g.count; k++) {
        const ang = -spread / 2 + spread * k / Math.max(g.count - 1, 1);
        svg.appendChild(U.svg('line', { x1: cx, y1: cy, x2: cx + g.length * ppm * Math.sin(ang), y2: cy - g.length * ppm * Math.cos(ang), stroke: RED, 'stroke-width': 3, 'stroke-linecap': 'round' }));
      }
    } else if (g.kind === 'spokes') {
      for (let k = 0; k < g.count; k++) {
        const ang = 2 * Math.PI * k / g.count;
        svg.appendChild(U.svg('line', { x1: cx, y1: cy, x2: cx + g.length * ppm * Math.sin(ang), y2: cy - g.length * ppm * Math.cos(ang), stroke: RED, 'stroke-width': 2.5, 'stroke-linecap': 'round', 'stroke-dasharray': g.approx ? '6 4' : '' }));
      }
    }
    // the creature, the hero, a 5 m bar
    svg.appendChild(U.svg('circle', { cx, cy, r: Math.max(3, radius * ppm), class: 'tp-creature' }));
    svg.appendChild(U.svg('circle', { cx, cy: up(heroDist), r: 4.5, class: 'tp-hero' }));
    svg.appendChild(U.svg('text', { x: cx + 8, y: up(heroDist) + 4, class: 'tp-label', text: 'hero 8 m' }));
    svg.appendChild(U.svg('line', { x1: 10, y1: H - 10, x2: 10 + 5 * ppm, y2: H - 10, class: 'tp-bar' }));
    svg.appendChild(U.svg('text', { x: 10, y: H - 14, class: 'tp-label', text: '5 m' }));
    const wind = M.num(atk.windup, 1);
    svg.appendChild(U.svg('text', { x: W - 8, y: 16, class: 'tp-label right', text: g.words }));
    svg.appendChild(U.svg('text', { x: W - 8, y: 30, class: 'tp-label right', text: `wind-up ${fmtN(wind, 2)} s${pf !== 1 ? ` (${fmtN(wind * pf, 2)} s on the map)` : ''}` }));
    return svg;
  }

  /** The cycle as a line: per attack a red block (the wind-up x the pace), a hatched block (its active time), a grey gap
   *  (cooldown_between), the total labelled. */
  function sequenceLine(d, pf, mapId, tl) {
    const seq = M.attackSequence(d.boss, pf);
    const W = 640, H = 64, left = 8, top = 10, barH = 22;
    const scale = (W - 16) / Math.max(seq.total, 0.001);
    const svg = U.svg('svg', { class: 'seq', viewBox: `0 0 ${W} ${H}`, width: '100%', height: H, preserveAspectRatio: 'none' });
    const defs = U.svg('defs');
    const pat = U.svg('pattern', { id: 'seq-hatch', width: 6, height: 6, patternUnits: 'userSpaceOnUse', patternTransform: 'rotate(45)' });
    pat.appendChild(U.svg('rect', { width: 6, height: 6, fill: 'rgba(237,74,92,0.18)' }));
    pat.appendChild(U.svg('line', { x1: 0, y1: 0, x2: 0, y2: 6, stroke: RED, 'stroke-width': 2 }));
    defs.appendChild(pat);
    svg.appendChild(defs);
    for (const s of seq.steps) {
      const x0 = left + s.start * scale;
      svg.appendChild(U.svg('rect', { x: x0, y: top, width: Math.max(1, s.windup * scale), height: barH, fill: RED }));
      svg.appendChild(U.svg('rect', { x: x0 + s.windup * scale, y: top, width: Math.max(1, s.active * scale), height: barH, fill: 'url(#seq-hatch)', stroke: RED, 'stroke-width': 1 }));
      svg.appendChild(U.svg('rect', { x: x0 + (s.windup + s.active) * scale, y: top + 6, width: Math.max(1, s.gap * scale), height: barH - 12, fill: 'rgba(255,255,255,0.12)' }));
      svg.appendChild(U.svg('text', { x: x0 + 2, y: top + barH + 14, class: 'tp-label', text: `${s.name} ${fmtN(s.windup, 1)}+${fmtN(s.active, 1)} s` }));
    }
    svg.appendChild(U.svg('text', { x: W - 8, y: top + barH + 26, class: 'tp-label right', text: `cycle ${fmtN(seq.total, 1)} s · rest ${fmtN(seq.gap, 1)} s between attacks` }));
    const wrap = el('div', { class: 'seqwrap' }, el('div', { class: 'muted small', text: 'The sequence: red = the wind-up (the telegraph shows), hatched = the attack, grey = cooldown_between. The first attack comes 2 s after spawn; the runner skips one out of its range.' }), svg);
    const pace = tl ? `${fmtN(M.num(tl.move_pace, 1), 2)} × ${fmtN(M.num(tl.creature_speed_mult, 1), 2)}` : '…';
    wrap.appendChild(el('div', { class: 'muted small', text: `Wind-ups last 1/pace: ×${fmtN(pf, 2)} on ${mapId} (move_pace × creature_speed_mult = ${pace}), so the slower hero still gets clear; the rest between attacks is not scaled.` }));
    return wrap;
  }

  // ------------------------------------------------------------------ the variance tints on the standing frame

  const frames = new Map();   // url|cell -> {canvas, lin} of frame 0 (the inspector's standingFrame, copied: its functions are closures)
  function standingFrame(url, cell, done) {
    const key = `${url}|${cell}`;
    if (frames.has(key)) { done(frames.get(key)); return; }
    const img = new Image();
    img.onload = () => {
      const size = Math.max(1, Math.min(cell || 128, img.naturalWidth, img.naturalHeight));
      const S2 = 96;
      const c = document.createElement('canvas'); c.width = S2; c.height = S2;
      const ctx = c.getContext('2d');
      ctx.imageSmoothingEnabled = true;
      ctx.drawImage(img, 0, 0, size, size, 0, 0, S2, S2);
      const data = ctx.getImageData(0, 0, S2, S2);
      const entry = { data, size: S2 };
      frames.set(key, entry);
      done(entry);
    };
    img.onerror = () => done(null);
    img.src = url;
  }
  function paintTint(canvas, frame, hex, amount) {
    const ctx = canvas.getContext('2d');
    const out = ctx.createImageData(frame.size, frame.size);
    const src = frame.data.data, dst = out.data;
    const m = String(hex || '').match(/^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i);
    const tint = m ? [Model.toLinear(parseInt(m[1], 16) / 255), Model.toLinear(parseInt(m[2], 16) / 255), Model.toLinear(parseInt(m[3], 16) / 255)] : null;
    for (let i = 0; i < src.length; i += 4) {
      if (tint && src[i + 3] > 0) {
        const rgb = Model.tintPixel([src[i] / 255, src[i + 1] / 255, src[i + 2] / 255], tint, amount);
        dst[i] = Math.round(rgb[0] * 255); dst[i + 1] = Math.round(rgb[1] * 255); dst[i + 2] = Math.round(rgb[2] * 255);
      } else { dst[i] = src[i]; dst[i + 1] = src[i + 1]; dst[i + 2] = src[i + 2]; }
      dst[i + 3] = src[i + 3];
    }
    ctx.putImageData(out, 0, 0);
  }
  function tintPreview(doc) {
    const d = doc.data;
    const vr = M.isObj(d.variance) ? d.variance : {};
    const tints = Array.isArray(vr.tints) ? vr.tints : [];
    const sp = M.isObj(vr.special) ? vr.special : {};
    const rec = App.creature(doc.id);
    const wrap = el('div', { class: 'tintprev-wrap', 'data-key': 'variance.tints' });
    if (!rec) return wrap;
    const look = doc.looks.find((l) => l.code === (doc.ui.look || rec.play)) || null;
    const url = (look && look.sprite) || rec.sprite_play;
    const cell = (look && look.frame_px) || rec.frame_px || 128;
    const strength = M.num(vr.tint_strength, 0.35);
    const items = [{ hex: null, cap: 'as painted' }].concat(tints.map((h) => ({ hex: h, cap: `${h} · ${fmtN(strength, 2)}` })));
    // (pass 69: the special's picture, with its glow, is in the Special section)
    void sp;
    const grid = el('div', { class: 'tint-preview tintprev' });
    const canvases = [];
    for (const it of items) {
      const c = el('canvas', { class: 'tint-pic', width: 96, height: 96, title: it.cap });
      canvases.push([c, it]);
      grid.appendChild(el('figure', { class: 'tint-fig' + (it.special ? ' special' : '') + (it.hex ? '' : ' orig') }, c, el('figcaption', { class: 'tint-cap', text: it.cap })));
    }
    standingFrame(url, cell, (frame) => { if (!frame) return; for (const [c, it] of canvases) paintTint(c, frame, it.hex, it.amount == null ? strength : it.amount); });
    wrap.appendChild(el('div', { class: 'muted small', text: `The standing frame of ${look ? look.code : rec.play || 'the strip'} under each tint (the shader mixes alpha × 0.65 in linear light; a tint rolls once the run passed the map's colour_after_kills).` }));
    wrap.appendChild(grid);
    return wrap;
  }

  // ------------------------------------------------------------------ pass 69 (lane EN): the coloured special

  const SP_ROWS = [['size', 'Size ×'], ['hp', 'HP ×'], ['damage', 'ATK ×'], ['xp', 'XP ×'], ['tint_strength', 'Colour strength'], ['glow', 'Glow'], ['chest_chance', 'Chest chance']];
  /** "#8A1428" -> [r, g, b] 0..1, or null. */
  function hexRgb(hex) {
    const m = String(hex || '').match(/^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i);
    return m ? [parseInt(m[1], 16) / 255, parseInt(m[2], 16) / 255, parseInt(m[3], 16) / 255] : null;
  }
  /** The glow's colour as enemy_billboard.gdshader draws it: the colour's hue at full brightness (its largest channel 1). */
  function rimRgb(rgb) {
    const mx = Math.max(rgb[0], rgb[1], rgb[2], 0.001);
    return rgb.map((c) => c / mx);
  }
  /** The standing frame on `canvas`: tinted by `hex` at `amount`, ringed by the glow (`glow` 0..1: a rim 1 + 4.2 × glow
   *  pixels wide in the rim's colour with a lighter core 0.6 + glow pixels wide, the painted outline lit by 0.85 × glow,
   *  as the shader does), drawn `scale` of the canvas tall, feet on its bottom edge. */
  function paintSpecial(canvas, frame, hex, amount, glow, scale) {
    const S = frame.size;
    const src = frame.data.data;
    const work = new Uint8ClampedArray(src.length);
    const rgb = hexRgb(hex);
    const tint = rgb ? rgb.map(Model.toLinear) : null;
    const rim = rgb ? rimRgb(rgb) : [1, 1, 1];
    const g = Math.max(0, Math.min(1, Number(glow) || 0));
    const r = g > 0.01 ? Math.max(1, Math.round(1.0 + 4.2 * g)) : 0;
    const ri = g > 0.01 ? Math.max(1, Math.round(0.6 + 1.0 * g)) : 0;
    const core = rim.map((c) => Model.toSrgb(Model.toLinear(c) * 0.55 + 0.45));
    const A = (x, y) => (x < 0 || y < 0 || x >= S || y >= S ? 0 : src[(y * S + x) * 4 + 3]);
    for (let y = 0; y < S; y++) {
      for (let x = 0; x < S; x++) {
        const i = (y * S + x) * 4;
        if (src[i + 3] >= 128) {
          let px = [src[i] / 255, src[i + 1] / 255, src[i + 2] / 255];
          if (tint) px = Model.tintPixel(px, tint, amount);
          // the painted outline lit up: a dark pixel by the figure's edge
          if (r > 0 && (px[0] * 0.3 + px[1] * 0.59 + px[2] * 0.11) < 0.3 && (A(x + 2, y) < 128 || A(x - 2, y) < 128 || A(x, y + 2) < 128 || A(x, y - 2) < 128)) {
            px = px.map((c, j) => c + (rim[j] - c) * 0.85 * g);
          }
          work[i] = Math.round(px[0] * 255); work[i + 1] = Math.round(px[1] * 255); work[i + 2] = Math.round(px[2] * 255); work[i + 3] = 255;
        } else if (r > 0) {
          // the nearest opaque pixel within r: within ri it is the lighter core, beyond it the colour
          let best = Infinity;
          for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) { const d2 = dx * dx + dy * dy; if (d2 < best && d2 <= r * r + 0.5 && A(x + dx, y + dy) >= 128) best = d2; }
          if (best < Infinity) {
            const cc = best <= ri * ri + 0.5 ? core : rim;
            work[i] = Math.round(cc[0] * 255); work[i + 1] = Math.round(cc[1] * 255); work[i + 2] = Math.round(cc[2] * 255); work[i + 3] = 255;
          }
        }
      }
    }
    const off = document.createElement('canvas'); off.width = S; off.height = S;
    off.getContext('2d').putImageData(new ImageData(work, S, S), 0, 0);
    const ctx = canvas.getContext('2d');
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    const h = canvas.height * scale;
    ctx.imageSmoothingEnabled = true;
    ctx.drawImage(off, (canvas.width - h) / 2, canvas.height - h, h, h);
  }
  /** The Special section's foot: what applies to each number and where it comes from (the creature, the map's
   *  special_defaults, the game), the chance in words, and the plain one beside its special as the game draws them. */
  function specialPreview(doc) {
    const d = doc.data;
    const vr = M.isObj(d.variance) ? d.variance : {};
    const sp = M.isObj(vr.special) ? vr.special : {};
    const mapId = doc.ui.map || 'red_canyon';
    const tl = Assets.mapTl(mapId);
    const defaults = tl && M.isObj(tl.special_defaults) ? tl.special_defaults : {};
    const wrap = el('div', { class: 'tintprev-wrap', 'data-key': 'variance.special' });
    const chance = M.num(vr.special_chance, 0);
    if (!Object.keys(vr).length) wrap.appendChild(el('p', { class: 'muted small', text: 'No variance block: this creature never comes as a coloured special (a special swarm brings it plain).' }));
    else wrap.appendChild(el('p', { class: 'muted small', text: chance > 0 ? `Chance ${fmtN(chance * 100, 2)} % = about one in ${Math.round(1 / chance)} once ${mapId}'s Colour after kills (${tl ? M.num(tl.colour_after_kills, 0) : '…'}) is reached.` : 'Chance 0: it never rolls its special on its own; a swarm event set to Special still brings one.' }));
    const tbl = el('table', { class: 'kv ctable' });
    tbl.appendChild(el('tr', {}, el('th'), el('th', { text: 'in play' }), el('th', { text: 'from' })));
    const where = { own: 'this creature', map: `${mapId}'s Coloured specials (Settings)`, game: 'the game\'s default' };
    for (const [k, label] of SP_ROWS) {
      tbl.appendChild(el('tr', {}, el('td', { text: label }), el('td', { class: 'mine', text: fmtN(Model.specialValue(sp, defaults, k), 2) }), el('td', { class: 'muted small', text: where[Model.specialSource(sp, defaults, k)] })));
    }
    // pass 72 (lane SPEC): the map's cap on how many live at once (Settings → Coloured specials; the game's 3)
    const capN = Model.specialMaxAlive(defaults);
    tbl.appendChild(el('tr', {}, el('td', { text: 'Max alive (map)' }), el('td', { class: 'mine', text: isFinite(capN) ? String(capN) : 'no limit' }), el('td', { class: 'muted small', text: (M.isObj(defaults) && defaults.max_alive != null && defaults.max_alive !== '' ? `${mapId}'s Coloured specials (Settings)` : 'the game\'s default') + ': past it a roll comes plain; a Special swarm still comes' })));
    tbl.appendChild(el('tr', {}, el('td', { text: 'Colour' }), el('td', { class: 'mine' }, sp.tint ? el('span', { class: 'sw-chip', style: `background:${sp.tint}`, title: sp.tint }) : '—'), el('td', { class: 'muted small', text: sp.tint ? 'this creature' : 'none: it keeps a plain one\'s tint (a row\'s colour range gives it a darker shade)' })));
    wrap.appendChild(tbl);
    const rec = App.creature(doc.id);
    if (!rec) return wrap;
    const look = doc.looks.find((l) => l.code === (doc.ui.look || rec.play)) || null;
    const url = (look && look.sprite) || rec.sprite_play;
    const cell = (look && look.frame_px) || rec.frame_px || 128;
    const size = Model.specialValue(sp, defaults, 'size');
    const strength = Model.specialValue(sp, defaults, 'tint_strength');
    const glow = Model.specialValue(sp, defaults, 'glow');
    const grid = el('div', { class: 'tint-preview tintprev' });
    const cPlain = el('canvas', { class: 'tint-pic', width: 120, height: 120, title: 'a plain one' });
    const cSp = el('canvas', { class: 'tint-pic', width: 120, height: 120, title: 'its special' });
    grid.appendChild(el('figure', { class: 'tint-fig orig' }, cPlain, el('figcaption', { class: 'tint-cap', text: 'plain' })));
    grid.appendChild(el('figure', { class: 'tint-fig special' }, cSp, el('figcaption', { class: 'tint-cap', text: `special ×${fmtN(size, 2)} · glow ${fmtN(glow, 2)}` })));
    const big = Math.max(size, 1);
    standingFrame(url, cell, (frame) => {
      if (!frame) return;
      paintSpecial(cPlain, frame, null, 0, 0, 0.8 / big);
      paintSpecial(cSp, frame, sp.tint || null, strength, glow, 0.8 * size / big);
    });
    wrap.appendChild(el('div', { class: 'muted small', text: `The standing frame of ${look ? look.code : rec.play || 'the strip'}: a plain one beside its special at its size, washed in its colour at its strength (× 0.65 in linear light) and ringed by its glow (a rim of the colour at full brightness; in the game it breathes slowly).` }));
    wrap.appendChild(grid);
    return wrap;
  }

  return { render, comparePanel, telegraphPicture, sequenceLine, paintSpecial, rimRgb };
})();
