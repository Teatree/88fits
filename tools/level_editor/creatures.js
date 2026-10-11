// The Enemies tab (pass 53, pass 54, pass 58; "Creatures" until pass 66): the palette. A card per creature with its numbers,
// its looks, its badges and its doc line, a filter box, and buttons that start a wave or a roster row with it. The creature
// data lives in the creature's own JSON; two things are set from here, each through the server after a backup and
// followed by that creature's import: its default look (the JSON's top-level `variant`) and, since pass 58, its blood
// (`blood`, the colour of its death splash).
//
// Pass 58: the default look is an always-visible strip of pictures on every card (Garry: "I asked for this to be a
// functionality in the Level Editor, the idea being is that I should be able to set the default Art Variant for those
// enemies from the Creatures tab"). Pass 54's "Set as default look" button showed only while a figure was hovered or
// clicked (and on the first figure it was cut off by the card's edge), so the tab looked as if it could not do it.
//
// Pass 66 (lane P): every card has an Edit button that opens the creature's document in an editor pane beside the
// palette (enemies.js; the palette narrows to one column of cards while a document is open), and the bar has
// "+ New from template", which creates a creature's folder from another's JSON. The tab keeps its id `creatures`.
'use strict';

const Creatures = (() => {
  const { el, clear, fmtN } = U;
  let filter = '';
  let showRetired = true;
  let confirming = null;      // {id, code} while the inline "make it the default?" shows
  let busy = null;            // the creature id a request is running for
  let creating = false;       // pass 66: the "New from template" form is open
  const pendingBlood = {};    // creature id -> the colour picked but not saved yet
  /** What a creature with no `blood` bleeds in the game (EnemyDef.blood's default, Color(0.78, 0.05, 0.05)). */
  const BLOOD_DEFAULT = '#c70d0d';
  let gridEl = null, countEl = null, createHost = null;

  function render(container) {
    Forms.closePop();
    clear(container);
    const doc = typeof Assets !== 'undefined' ? Assets.active('creatures') : null;
    const wrap = el('div', { class: 'apanes' + (doc ? ' with-editor' : '') });
    const list = el('div', { class: 'alist' });
    const bar = el('div', { class: 'palette-bar' });
    const box = el('input', { type: 'search', class: 'txt wide', placeholder: 'filter by name, id, archetype or brain…', value: filter });
    box.addEventListener('input', () => { filter = box.value.trim().toLowerCase(); draw(); });
    const cb = el('input', { type: 'checkbox' }); cb.checked = showRetired;
    cb.addEventListener('change', () => { showRetired = cb.checked; draw(); });
    bar.appendChild(box);
    bar.appendChild(el('label', { class: 'cb' }, cb, el('span', { text: 'show retired and hidden' })));
    countEl = el('span', { class: 'muted' });
    bar.appendChild(countEl);
    bar.appendChild(el('button', { class: 'btn small' + (creating ? ' toggle on' : ''), type: 'button', text: '+ New from template ▾', title: 'a new creature folder from another creature\'s JSON (its numbers and art words; placeholder art unless the art is copied)', onclick: () => { creating = !creating; drawCreate(); } }));
    if (!doc) bar.appendChild(el('span', { class: 'muted small', text: 'Default look: click a picture on a card to make it the look every row that names none plays. Blood: the colour of its death splash. Edit opens the creature\'s form.' }));
    list.appendChild(bar);
    createHost = el('div', { class: 'acreate-host' });
    list.appendChild(createHost);
    drawCreate();
    gridEl = el('div', { class: 'palette' });
    list.appendChild(gridEl);
    wrap.appendChild(list);
    if (doc) wrap.appendChild(Assets.buildPane(doc, (pane) => Enemies.render(pane, doc)));
    container.appendChild(wrap);
    draw();
  }

  function draw() {
    const grid = gridEl;
    if (!grid) return;
    clear(grid);
    const rosterIds = new Set((App.tl().roster || []).map((r) => r.enemy));
    const list = App.S.enemies.filter((c) => {
      if (!showRetired && (c.retired || c.hidden)) return false;
      if (!filter) return true;
      return [c.name, c.id, c.archetype, c.brain, c.kind].some((s) => String(s).toLowerCase().includes(filter));
    });
    const order = { enemy: 0, boss: 2 };
    list.sort((a, b) => (a.archetype === 'elite') - (b.archetype === 'elite') || order[a.kind] - order[b.kind] || (a.retired || a.hidden) - (b.retired || b.hidden) || a.name.localeCompare(b.name));
    countEl.textContent = `${list.length} of ${App.S.enemies.length}`;
    for (const c of list) grid.appendChild(card(c, rosterIds.has(c.id), () => draw()));
  }

  /** pass 66: the "New from template" form above the grid */
  function drawCreate() {
    if (!createHost) return;
    clear(createHost);
    if (!creating || typeof Assets === 'undefined') return;
    const taken = new Set(App.S.enemies.map((c) => c.id));
    const dlg = Assets.createDialog('enemy', Forms.creatureGroups('creature'), taken, {
      label: 'creature', docRequired: true,
      note: 'The folder lands under content/enemies (bosses for a boss template) with the template\'s numbers and art words, its id, name, flavour and doc reset, a placeholder strip and icon (one row, strip_cols 0), knockback written out, blood kept; a register job makes the placeholders and imports it.',
      onCreate: async (body) => {
        const t = App.creature(body.template);
        const kind = t && t.kind === 'boss' ? 'boss' : 'enemy';
        const doc = await Assets.create(kind, body);
        if (doc) { creating = false; }
      },
      onCancel: () => { creating = false; drawCreate(); const b = createHost.parentNode && createHost.parentNode.querySelector('.palette-bar .btn.toggle'); if (b) b.classList.remove('on'); },
    });
    createHost.appendChild(dlg);
  }

  /** pass 66: the editor pane again after a change (the palette keeps its scroll); 'all' = the whole tab. */
  function redraw(doc, what) {
    if (what === 'all') { App.render('tab'); return; }
    if (!Assets.swapPane(doc, (pane) => Enemies.render(pane, doc))) App.render('tab');
    else updateCards();
  }
  /** the open / unsaved marks on the cards without rebuilding them */
  function updateCards() {
    if (!gridEl) return;
    for (const c of gridEl.querySelectorAll('.ccard')) {
      const doc = Assets.S.docs[`enemy:${c.dataset.id}`] || Assets.S.docs[`boss:${c.dataset.id}`];
      c.classList.toggle('editing', !!doc && Assets.S.open.creatures === doc.key);
      const dot = c.querySelector('.ccard-dirty');
      if (dot) dot.hidden = !(doc && Assets.docDirty(doc));
    }
  }

  function card(c, onRoster, redrawFn) {
    const tags = [];
    if (c.kind === 'boss') tags.push('boss');
    if (c.archetype === 'elite') tags.push('elite');
    if (c.max_alive === 1 && c.kind === 'enemy' && c.archetype !== 'elite') tags.push('special');
    if (c.retired) tags.push('retired');
    if (c.hidden) tags.push('hidden');
    if (!c.can_be_elite) tags.push('never coloured');
    if (onRoster) tags.push('on the roster');
    const drops = [];
    const d = c.drops || {};
    for (const k of ['small', 'medium', 'large']) if (d[k]) drops.push(`${k[0]} ${fmtN(d[k])}`);
    if (d.gold) drops.push(`coin ${pct(d.gold)}`);
    if (d.chest) drops.push(`chest ${pct(d.chest)}`);
    if (d.chests) drops.push(`${d.chests} chests`);
    if (d.coins) drops.push(`${d.coins} coins`);
    if (d.pickup && d.pickup.id) drops.push(`${App.pickup(d.pickup.id) ? App.pickup(d.pickup.id).name : d.pickup.id} ${pct(d.pickup.chance)}`);
    const doc = typeof Assets !== 'undefined' ? (Assets.S.docs[`${c.kind}:${c.id}`] || null) : null;
    const editing = !!doc && Assets.S.open.creatures === doc.key;
    const el2 = el('article', { class: 'ccard' + (c.retired || c.hidden ? ' dim' : '') + (editing ? ' editing' : ''), 'data-id': c.id });
    el2.appendChild(el('div', { class: 'ccard-top' },
      el('img', { class: 'ccard-icon', src: c.icon_play || c.icon, alt: '', width: 72, height: 72, title: c.play ? `the default look: ${c.play}` : '' }),
      el('div', { class: 'ccard-id' },
        el('h3', {}, el('span', { text: c.name }), el('span', { class: 'ccard-dirty', text: ' ●', title: 'unsaved changes in the editor', hidden: !(doc && Assets.docDirty(doc)) })),
        el('div', { class: 'muted small', text: `${c.id} · ${c.archetype} / ${c.brain}${c.play ? ' · default look ' + c.play : ''}` }),
        el('div', { class: 'tags' }, tags.map((t) => el('span', { class: 'tag ' + t.replace(/ /g, '-'), text: t }))))));
    const stats = el('dl', { class: 'cstats' });
    const stat = (k, v, title) => { stats.appendChild(el('dt', { text: k, title: title || '' })); stats.appendChild(el('dd', { text: v, title: title || '' })); };
    stat('HP', fmtN(c.hp)); stat('bite', fmtN(c.damage)); stat('speed', `${fmtN(c.speed)} m/s`); stat('size', `${fmtN(c.size)} m`);
    stat('pack', String(c.pack_size)); stat('cap', `${fmtN(c.cap_share)} slot`); stat('XP ×', fmtN(c.xp_mult));
    const kb = Model.knockbackOf(c, null);
    stat('knock', `${fmtN(kb.value, 2)} m/s${kb.from === 'default' ? ' (default)' : ''}`, kb.from === 'default' ? 'no knockback in its JSON: the game\'s default from its damage, clamp(3.4 × √(damage / 4), 2.5, 7)' : 'the bite\'s shove on the hero (its JSON\'s knockback)');
    if (c.damage_reduction) stat('DR', `${Math.round(c.damage_reduction * 100)}%`);
    if (c.knockback_resist) stat('KB resist', `${Math.round(c.knockback_resist * 100)}%`, 'the share of every shove from the hero\'s side (hits, blasts, the pull, the Ram) it shrugs off (pass 67): the other way round from knock, which is its bite\'s shove on the hero');
    if (c.max_alive) stat('max alive', String(c.max_alive));
    if (c.ranged) stat('ranged', `every ${fmtN(c.ranged.cooldown)} s, ${fmtN(c.ranged.range)} m`);
    if (c.charge) stat('charge', `${fmtN(c.charge.speed)} m/s every ${fmtN(c.charge.cooldown)} s`);
    if (c.boss) stat('attacks', [...new Set(c.boss.attacks)].join(', '));
    stat('drops', drops.join(' · ') || '—');
    el2.appendChild(stats);
    const vr = c.variance || {};
    if ((Array.isArray(vr.tints) && vr.tints.length) || vr.special_chance) {
      const sp = vr.special || {};
      el2.appendChild(el('div', { class: 'cvariance' },
        el('span', { class: 'muted small', text: 'tints' }),
        (vr.tints || []).map((h) => el('span', { class: 'sw-chip', style: `background:${h}`, title: `${h} at ${fmtN(vr.tint_strength == null ? 0 : vr.tint_strength, 2)}` })),
        vr.special_chance ? el('span', { class: 'muted small', text: ` · special ${Math.round(Number(vr.special_chance) * 100)}%` }) : null,
        sp.tint ? el('span', { class: 'sw-chip big', style: `background:${sp.tint}`, title: `the special's colour ${sp.tint}: HP ×${sp.hp || 1.6}, damage ×${sp.damage || 1.2}, size ×${sp.size || 1.3}, XP ×${sp.xp || 2}` }) : null));
    }
    el2.appendChild(bloodRow(c, redrawFn));
    el2.appendChild(lookStrip(c, redrawFn));
    if (c.doc) el2.appendChild(el('p', { class: 'doc', text: c.doc }));
    el2.appendChild(el('div', { class: 'ccard-actions' },
      el('button', { class: 'btn small' + (editing ? ' primary' : ''), type: 'button', text: editing ? 'Editing' : 'Edit', title: 'open this creature\'s form beside the palette (every stat, its brain, attacks, drops, sounds, looks and art words)', onclick: () => { if (typeof Assets !== 'undefined') Assets.open(c.kind, c.id); } }),
      el('button', { class: 'btn small', type: 'button', text: '+ wave', title: 'a new wave of this creature at the view\'s centre (it plays the default look)', onclick: () => { App.switchTab('timeline'); App.newWave(c.id, null); App.select(App.S.sel, { scroll: true }); } }),
      el('button', { class: 'btn small', type: 'button', text: '+ roster row', title: 'a new roster row of this creature at the view\'s centre (it plays the default look)', onclick: () => { App.switchTab('timeline'); App.newRow(c.id, null); App.select(App.S.sel, { scroll: true }); } })));
    return el2;
  }

  // ------------------------------------------------------------------ the default look (pass 54, pass 58)

  /** The creature's looks as pictures, always on show: the default ringed and tagged "default", every other painted look
   *  tagged "make default" (a click asks first, inline: it writes the creature's JSON), an unpainted one faded. A
   *  creature with one painting says so. Pass 66: a shelved look is faded and says so. */
  function lookStrip(c, redrawFn) {
    const wrap = el('div', { class: 'look-wrap' });
    if (!c.variants.length) {
      wrap.appendChild(el('div', { class: 'look-head' }, el('b', { text: 'Default look' }), el('span', { class: 'muted small', text: ' · its one painting' })));
      return wrap;
    }
    const others = c.variants.filter((v) => v.code !== c.play && v.ready).length;
    wrap.appendChild(el('div', { class: 'look-head' }, el('b', { text: 'Default look' }),
      el('span', { class: 'muted small', text: others ? ` ${c.play || ''} · click another picture to make it the default` : ` ${c.play || ''} · no other painted look` })));
    const vs = el('div', { class: 'looks' });
    for (const v of c.variants) {
      const isDef = v.code === c.play;
      const asking = confirming && confirming.id === c.id && confirming.code === v.code;
      const fig = el('button', {
        type: 'button', class: 'look' + (isDef ? ' default' : '') + (asking ? ' asking' : '') + (v.ready ? '' : ' not-ready') + (v.shelved ? ' shelved' : ''),
        disabled: !v.ready || (busy === c.id && !isDef), 'data-code': v.code,
        title: `${v.code}${v.note ? ': ' + v.note : ''}${isDef ? ' (the default look)' : v.ready ? ' (click to make it the default)' : ' (not painted yet: the game would play the base strip)'}${v.shelved ? ' · shelved: out of the arena and the default lists' : ''}${v.fresh ? ' · unreviewed' : ''}`,
      },
      el('img', { src: v.icon, alt: '', width: 48, height: 48, onerror: (e) => { e.target.src = c.icon; } }),
      el('span', { class: 'look-code', text: v.code }),
      el('span', { class: 'look-tag' + (isDef ? ' on' : v.ready ? '' : ' na'), text: isDef ? 'default' : v.shelved ? 'shelved' : v.fresh ? 'new' : v.ready ? 'make default' : 'not painted' }));
      if (!isDef && v.ready) fig.addEventListener('click', () => { confirming = asking ? null : { id: c.id, code: v.code }; redrawFn(); });
      vs.appendChild(fig);
    }
    wrap.appendChild(vs);
    if (confirming && confirming.id === c.id) {
      const code = confirming.code;
      wrap.appendChild(el('div', { class: 'confirm' },
        el('span', { text: `Make ${code} the default look of ${U.theName(c.name)}? Every row, wave and event that names no look plays it from the next launch (this writes "variant" in ${c.id}.json after a backup, then imports it).` }),
        el('button', { class: 'btn small primary', type: 'button', text: busy === c.id ? 'Setting…' : `Yes, make ${code} the default`, disabled: busy === c.id, onclick: () => setDefault(c, code, redrawFn) }),
        el('button', { class: 'btn small ghost', type: 'button', text: 'Cancel', disabled: busy === c.id, onclick: () => { confirming = null; redrawFn(); } })));
    }
    return wrap;
  }

  async function setDefault(c, code, redrawFn) {
    busy = c.id;
    redrawFn();
    App.status(`Setting ${c.id}'s default look to ${code} and importing…`, 'busy');
    try {
      const r = await fetch(`/api/enemy/${encodeURIComponent(c.id)}/variant`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ code }) });
      const res = await r.json();
      if (!res.ok) throw new Error(res.error || `HTTP ${r.status}`);
      confirming = null;
      busy = null;
      if (typeof Assets !== 'undefined') await Assets.refreshRecord(c.kind, c.id);
      await App.refreshCreatures();
      if (res.import_ok) App.status(`${c.name} now plays ${code} (was ${res.was || 'its base'}) · ${res.wrote} · import OK · backup ${String(res.backup).split('/').pop()}`, 'good', res.output);
      else App.status(`${c.name} now plays ${code} in its JSON · IMPORT FAILED (the game still plays the old .tres)`, 'bad', res.output);
      App.toast(`${c.name}: ${code} is the default look`);
      return;   // refreshCreatures drew the tab again with the new look ringed
    } catch (e) {
      busy = null;
      App.status(`Could not set ${c.id}'s look: ${e.message}`, 'bad');
    }
    if (App.S.tab === 'creatures') redrawFn();
  }

  // ------------------------------------------------------------------ the blood colour (pass 58, R4)

  /** A small splash in the colour (the swatch beside the picker). */
  function splash(color) {
    const s = U.svg('svg', { class: 'splash', viewBox: '0 0 34 26', width: 34, height: 26, 'aria-hidden': 'true' });
    s.appendChild(U.svg('path', { d: 'M17 3.2c2.4 0 3.2 3.1 5.3 3.5 2.6.5 5.1-1.5 6.3.6 1.2 2.1-1.8 3.7-1.3 5.7.5 2.3 3.6 3.2 2.6 5.3-1 2.2-4.1.8-6 2-2.1 1.3-2.4 4.4-4.9 4.4s-3-3-5.2-4.1c-2.1-1.1-5.3.4-6.3-1.8-1-2.2 2.1-3.1 2.3-5.4.3-2.1-2.9-3.5-1.8-5.6 1.2-2.2 3.8-.4 6.3-.9 2.1-.5 2.4-3.7 4.7-3.7z', fill: color, stroke: 'rgba(0,0,0,0.55)', 'stroke-width': 0.8 }));
    for (const [cx, cy, r] of [[4.2, 6, 1.7], [30.5, 21.5, 1.4], [29, 4, 1.1], [6, 22, 1.2]]) s.appendChild(U.svg('circle', { cx, cy, r, fill: color, stroke: 'rgba(0,0,0,0.5)', 'stroke-width': 0.5 }));
    s.appendChild(U.svg('ellipse', { cx: 14.2, cy: 9.6, rx: 2.4, ry: 1.3, fill: 'rgba(255,255,255,0.5)' }));
    return s;
  }

  /** The creature's blood: the splash, a colour picker, its hex; a colour changed here waits for Save (it writes the
   *  creature's JSON and imports it) or ↺. With no `blood` in the JSON the game's default red shows, marked so. */
  function bloodRow(c, redrawFn) {
    const saved = c.blood ? c.blood.toLowerCase() : null;
    const want = pendingBlood[c.id] || null;
    const shown = want || saved || BLOOD_DEFAULT;
    const changed = !!want && want !== saved;
    const row = el('div', { class: 'blood-row' + (changed ? ' changed' : ''), 'data-blood': c.id });
    const color = el('input', { type: 'color', class: 'sw-color blood-color', value: shown, title: 'pick the colour of its death splash', 'data-path': `blood.${c.id}` });
    const hex = el('input', { type: 'text', class: 'txt hex', value: shown, maxlength: 7, spellcheck: false, title: '#rrggbb' });
    const pick = (v) => {
      const h = Forms.normHex(v);
      if (!h) { hex.value = shown; App.toast(`"${v}" is not a colour: #rrggbb`); return; }
      pendingBlood[c.id] = h.toLowerCase() === saved ? undefined : h.toLowerCase();
      if (!pendingBlood[c.id]) delete pendingBlood[c.id];
      redrawFn();
    };
    color.addEventListener('input', () => { hex.value = color.value; const sw = row.querySelector('.splash'); if (sw) sw.replaceWith(splash(color.value)); });
    color.addEventListener('change', () => pick(color.value));
    hex.addEventListener('change', () => pick(hex.value));
    hex.addEventListener('keydown', (e) => { if (e.key === 'Enter') hex.blur(); });
    row.appendChild(el('span', { class: 'blood-lab', text: 'blood' }));
    row.appendChild(splash(shown));
    row.appendChild(color);
    row.appendChild(hex);
    if (changed) {
      row.appendChild(el('button', { class: 'btn small primary', type: 'button', text: busy === c.id ? 'Saving…' : 'Save', disabled: busy === c.id, title: `write "blood": "${want}" in ${c.id}.json (after a backup) and import it`, onclick: () => setBlood(c, want, redrawFn) }));
      row.appendChild(el('button', { class: 'btn small ghost', type: 'button', text: '↺', title: `back to ${saved || 'the default red'}`, disabled: busy === c.id, onclick: () => { delete pendingBlood[c.id]; redrawFn(); } }));
    } else if (!saved) row.appendChild(el('span', { class: 'muted small', text: 'none set: the game\'s default red' }));
    return row;
  }

  async function setBlood(c, color, redrawFn) {
    busy = c.id;
    redrawFn();
    App.status(`Setting ${c.id}'s blood to ${color} and importing…`, 'busy');
    try {
      const r = await fetch(`/api/enemy/${encodeURIComponent(c.id)}/blood`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ color }) });
      const res = await r.json();
      if (!res.ok) throw new Error(res.error || `HTTP ${r.status}`);
      delete pendingBlood[c.id];
      busy = null;
      if (typeof Assets !== 'undefined') await Assets.refreshRecord(c.kind, c.id);
      await App.refreshCreatures();
      if (res.unchanged) App.status(`${c.name} already bleeds ${res.blood}: nothing written`, 'good');
      else if (res.import_ok) App.status(`${c.name} bleeds ${res.blood} (was ${res.was || 'the default red'}) · ${res.wrote} · import OK · backup ${String(res.backup).split('/').pop()}`, 'good', res.output);
      else App.status(`${c.name} bleeds ${res.blood} in its JSON · IMPORT FAILED (the game still plays the old .tres)`, 'bad', res.output);
      App.toast(`${c.name}: blood ${res.blood}`);
      return;
    } catch (e) {
      busy = null;
      App.status(`Could not set ${c.id}'s blood: ${e.message}`, 'bad');
    }
    if (App.S.tab === 'creatures') redrawFn();
  }

  function pct(v) { const p = Number(v) * 100; return (p >= 10 ? Math.round(p) : p >= 1 ? p.toFixed(1) : p.toFixed(2)) + '%'; }

  return { render, redraw, card, lookStrip, bloodRow, splash, BLOOD_DEFAULT };
})();
