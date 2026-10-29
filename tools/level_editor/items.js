'use strict';
// Pass 66 (lane P): the Items tab: weapons with their evolution and path mutations (and the hero mutations) under one
// card, lines with their evolved form, passive items; a filter (weapons · lines · passive items · mutations · evolutions),
// a status filter and a search; the status chips available / hidden / locked by quest / hero-only / stage N+; the
// quest-locked band gauge (pass44_test wants 33-56% of base items behind a quest). The editor pane (assets.js) has the
// weapon / evolution form (behaviour, targeting, base stats with the game's defaults as placeholders, the five level
// steps, the evolution and the path strip with Create templates -> make_path, params as guided JSON with the behaviour's
// key chips, sounds, availability with the quest drawer and the band, art), the line / passive form and the mutation form.
const Items = (() => {
  const { el, clear, fmtN } = U;
  const M = AssetsModel, F = AFIELDS;
  let listEl = null, createHost = null, creating = false, createKind = 'weapon';
  // pass 73 (lane CARDS): the line items are fortune cards to the player ('lines' stays the filter's key)
  const KINDS = [['all', 'all'], ['weapons', 'weapons'], ['lines', 'cards'], ['passives', 'passive items'], ['mutations', 'mutations'], ['evolutions', 'evolutions']];
  const filt = () => Assets.S.filters.items;

  function render(panel) {
    Forms.closePop();
    clear(panel);
    Assets.ensureItems(); Assets.ensureHeroes(); Assets.ensureVocab(); Assets.ensureMethods();
    const doc = Assets.active('items');
    const wrap = el('div', { class: 'apanes' + (doc ? ' with-editor' : '') });
    const list = el('div', { class: 'alist' });
    const bar = el('div', { class: 'ibar' });
    const chips = el('div', { class: 'kchips' });
    for (const [v, label] of KINDS) chips.appendChild(el('button', { class: 'kchip' + (filt().kind === v ? ' on' : ''), type: 'button', text: label, onclick: () => { filt().kind = v; App.render('tab'); } }));
    bar.appendChild(chips);
    const box = el('input', { type: 'search', class: 'txt', placeholder: 'filter by name or id…', value: filt().q });
    box.addEventListener('input', () => { filt().q = box.value.trim().toLowerCase(); draw(); });
    bar.appendChild(box);
    bar.appendChild(Forms.select([{ v: 'all', label: 'any status' }, { v: 'available', label: 'available' }, { v: 'hidden', label: 'hidden' }, { v: 'locked', label: 'locked by quest' }, { v: 'hero', label: 'hero-only' }, { v: 'stage', label: 'from a stage' }], filt().status, (v) => { filt().status = v || 'all'; draw(); }, { path: 'items.status' }));
    bar.appendChild(el('button', { class: 'btn small' + (creating ? ' toggle on' : ''), type: 'button', text: '+ New from template ▾', onclick: () => { creating = !creating; drawCreate(); } }));
    list.appendChild(bar);
    list.appendChild(bandGauge(null));
    createHost = el('div', { class: 'acreate-host' });
    list.appendChild(createHost);
    drawCreate();
    listEl = el('div', { class: 'ilist' });
    list.appendChild(listEl);
    wrap.appendChild(list);
    if (doc) wrap.appendChild(Assets.buildPane(doc, (pane) => editor(pane, doc)));
    panel.appendChild(wrap);
    draw();
  }

  const icon = (kind, id) => `/icon/${kind}/${encodeURIComponent(id)}`;
  const plate = (rarity) => (Assets.vocab().rarityPlate || F.VOCAB.rarityPlate)[String(rarity || 'common')] || '#d2cfc7';

  function drawCreate() {
    if (!createHost) return;
    clear(createHost);
    if (!creating) return;
    const fl = Assets.flatItems();
    if (!fl) { createHost.appendChild(el('p', { class: 'muted small', text: 'the item lists have not loaded' })); return; }
    const kindSel = Forms.select([{ v: 'weapon', label: 'a weapon (with three template mutations and an evolution, all hidden)' }, { v: 'passive', label: 'a card (line item) or passive item (available at once)' }, { v: 'mutation', label: 'a mutation of a weapon' }], createKind, (v) => { createKind = v || 'weapon'; drawCreate(); }, { path: 'items.createKind' });
    const mk = (list, k) => list.map((x) => ({ v: x.id, label: x.name || x.id, icon: icon(k, x.id), sub: `${x.id} · ${x.rarity || ''}${x.hidden ? ' · hidden' : ''}`, dim: !!x.hidden }));
    const templates = createKind === 'weapon' ? mk(fl.weapons, 'weapon') : createKind === 'passive' ? [{ group: 'Cards (line items)', options: mk(fl.passives.filter((p) => p.line && !p.evolves_from), 'passive') }, { group: 'Passive items', options: mk(fl.passives.filter((p) => !p.line), 'passive') }] : mk(fl.mutations, 'mutation');
    const taken = new Set([].concat(fl.weapons, fl.evolutions, fl.mutations, fl.passives, fl.quests).map((x) => x.id).concat((App.S.enemies || []).map((c) => c.id), (Assets.S.lists.heroes || []).map((h) => h.id)));
    const notes = {
      weapon: 'INTERFACES §0.1: a new weapon is created hidden with <id>_element, <id>_volume, <id>_motion (kinds element / volume / motion) and <id>_evolved, all five hidden; it may turn available once each template mutation has text and an effect or param and the evolution a name. Its path and evolution land as a register job.',
      passive: 'Garry\'s answer 13: a new card (line item) or passive item is available at once, at its template\'s weight (its rarity\'s usual). The band below moves: the ship test wants 28-56% of base items behind a quest (pass 69).',
      mutation: 'A mutation of a weapon: its kind, weapon and text come from the template; the weapon\'s path wants one of each kind (element, volume, motion) among its non-hidden mutations.',
    };
    const dlg = Assets.createDialog(createKind, templates, taken, {
      label: createKind, docRequired: false, copyArt: false, note: notes[createKind],
      onCreate: async (body) => { const d = await Assets.create(createKind, body); if (d) creating = false; },
      onCancel: () => { creating = false; drawCreate(); },
    });
    dlg.insertBefore(Forms.row({ key: 'items.createKind', label: 'Kind' }, kindSel, {}), dlg.children[1]);
    createHost.appendChild(dlg);
  }

  // ------------------------------------------------------------------ the list

  function availabilityOf(x, kind) {
    if (!x) return 'available';
    if (x.availability) return x.availability;
    const fl = Assets.flatItems();
    return M.availabilityOf(x, fl ? fl.quests : [], kind);
  }
  function statusChips(x, kind) {
    const out = [Assets.statusChip(availabilityOf(x, kind))];
    if (x.hero) out.push(el('span', { class: 'achip hero', text: `${x.hero} only` }));
    if (Number(x.from_stage) > 0) out.push(el('span', { class: 'achip stage', text: `stage ${x.from_stage}+` }));
    if (x.is_evolution) out.push(el('span', { class: 'achip', text: 'evolution' }));
    return out;
  }
  function matches(x, kind) {
    const f = filt();
    if (f.q && ![x.id, x.name, x.flavour].some((s) => String(s || '').toLowerCase().includes(f.q))) return false;
    if (f.status === 'all') return true;
    if (f.status === 'hero') return !!x.hero;
    if (f.status === 'stage') return Number(x.from_stage) > 0;
    return availabilityOf(x, kind) === f.status;
  }

  function draw() {
    if (!listEl) return;
    clear(listEl);
    const it = Assets.S.lists.items, fl = Assets.flatItems();
    if (!it || !fl) { listEl.appendChild(el('p', { class: 'muted', text: Assets.S.failed.items ? `No item list: ${Assets.S.failed.items} (lane S's /api/items)` : 'Reading the items…' })); return; }
    const kind = filt().kind;
    let n = 0;
    const add = (node) => { listEl.appendChild(node); n++; };
    if (kind === 'all' || kind === 'weapons') {
      const ws = fl.weapons.filter((w) => matches(w, 'weapon')).sort((a, b) => (!!a.hidden - !!b.hidden) || String(a.name || a.id).localeCompare(String(b.name || b.id)));
      if (ws.length) listEl.appendChild(el('h3', { class: 'ihead', text: `Weapons · ${ws.length}` }));
      for (const w of ws) add(weaponCard(w, fl));
    }
    if (kind === 'all' || kind === 'lines') {
      const ls = fl.passives.filter((p) => p.line && !p.evolves_from && matches(p, 'passive')).sort((a, b) => String(a.name || a.id).localeCompare(String(b.name || b.id)));
      if (ls.length) listEl.appendChild(el('h3', { class: 'ihead', text: `Cards · ${ls.length}` }));
      if (ls.length) { const bar = cardLooksBar(fl); if (bar) listEl.appendChild(bar); }
      for (const l of ls) add(lineCard(l, fl));
    }
    if (kind === 'all' || kind === 'passives') {
      const ps = fl.passives.filter((p) => !p.line && matches(p, 'passive')).sort((a, b) => String(a.name || a.id).localeCompare(String(b.name || b.id)));
      if (ps.length) listEl.appendChild(el('h3', { class: 'ihead', text: `Passive items · ${ps.length}` }));
      for (const p of ps) add(passiveCard(p));
    }
    if (kind === 'mutations') {
      const ms = fl.mutations.filter((m) => matches(m, 'mutation')).sort((a, b) => String(a.weapon).localeCompare(String(b.weapon)) || String(a.kind).localeCompare(String(b.kind)));
      listEl.appendChild(el('h3', { class: 'ihead', text: `Mutations · ${ms.length}` }));
      for (const m of ms) add(mutationCard(m, fl));
    }
    if (kind === 'evolutions') {
      const es = fl.evolutions.filter((e) => matches(e, 'evolution')).sort((a, b) => (!!a.hidden - !!b.hidden) || String(a.name || a.id).localeCompare(String(b.name || b.id)));
      listEl.appendChild(el('h3', { class: 'ihead', text: `Evolutions · ${es.length}` }));
      for (const e of es) add(evolutionCard(e, fl));
    }
    if (!n) listEl.appendChild(el('p', { class: 'muted', text: 'nothing matches' }));
  }

  function cardShell(kind, x, extraTop) {
    const doc = Assets.S.docs[`${kind}:${x.id}`] || null;
    const editing = !!doc && Assets.S.open.items === doc.key;
    const art = el('article', { class: 'icard' + (x.hidden ? ' dim' : '') + (editing ? ' editing' : ''), 'data-id': x.id, 'data-kind': kind });
    art.appendChild(el('div', { class: 'icard-top' },
      el('div', { class: 'icard-icon' + (kind === 'hero' ? ' round' : ''), style: `background:${plate(x.rarity)}` }, el('img', { src: x.icon_play || icon(kind, x.id), alt: '', onerror: (e) => { e.target.style.visibility = 'hidden'; } })),
      el('div', { class: 'icard-id' },
        el('h3', {}, el('span', { text: x.name_play || x.name || x.id, title: x.name_play && x.name_play !== x.name ? `${x.name} in its look ${x.play}` : '' }), doc && Assets.docDirty(doc) ? el('span', { class: 'ccard-dirty', text: ' ●', title: 'unsaved changes' }) : null),
        el('div', { class: 'muted small', text: `${x.id} · ${x.rarity || 'common'}${x.weight != null ? ' · weight ' + x.weight : ''}${extraTop ? ' · ' + extraTop : ''}` }),
        el('div', { class: 'tags' }, statusChips(x, kind))),
      el('button', { class: 'btn small' + (editing ? ' primary' : ''), type: 'button', text: editing ? 'Editing' : 'Edit', onclick: () => Assets.open(kind, x.id) })));
    return art;
  }
  const sub = (kind, x, label, note) => el('div', { class: 'isub' }, el('img', { src: x.icon_play || icon(kind, x.id), alt: '', onerror: (e) => { e.target.style.visibility = 'hidden'; } }), el('span', { class: 'achip ' + (label.includes('hero') ? 'hero' : ''), text: label }), el('b', { text: x.name_play || x.name || x.id }), x.hidden ? el('span', { class: 'achip hidden', text: 'hidden' }) : null, note ? el('span', { class: 'muted small', text: note }) : null, el('button', { class: 'btn small ghost', type: 'button', text: 'Edit', onclick: () => Assets.open(kind, x.id) }));

  function weaponCard(w, fl) {
    const base = M.isObj(w.base) ? w.base : {};
    // pass 76 (lane LOOKS): a family with looks says the one it plays
    const looked = Array.isArray(w.family_looks) && w.family_looks.length > 1 ? ` · look ${w.play} of ${w.family_looks.length}` : '';
    const art = cardShell('weapon', w, `${w.behavior || 'ProjectileEmitter'} · ${w.targeting || 'nearest'} · dmg ${fmtN(M.num(base.damage, 5))} · cd ${fmtN(M.num(base.cooldown, 1))} s · ×${fmtN(M.num(base.amount, 1))}${looked}`);
    const subs = el('div', { class: 'icard-sub' });
    const evo = fl.evolutions.find((e) => e.id === w.evolves_into) || null;
    if (evo) subs.appendChild(sub('evolution', evo, 'evolution', evo.evolved_from && evo.evolved_from !== w.id ? `evolved_from ${evo.evolved_from}` : ''));
    else subs.appendChild(el('div', { class: 'isub muted small' }, el('span', { class: 'achip bad', text: 'no evolution' }), el('span', { text: w.evolves_into ? `evolves_into "${w.evolves_into}" does not exist` : 'evolves_into is empty: Create templates in the editor' })));
    const path = M.pathOf(w.id, fl.mutations);
    for (const k of ['element', 'volume', 'motion']) {
      if (path[k]) subs.appendChild(sub('mutation', path[k], k, path[k].text ? '' : 'no text'));
      else subs.appendChild(el('div', { class: 'isub muted small' }, el('span', { class: 'achip ' + (w.hidden ? 'hidden' : 'bad'), text: k }), el('span', { text: `no ${k} mutation${path.hidden.some((m) => m.kind === k) ? ` (hidden: ${path.hidden.filter((m) => m.kind === k).map((m) => m.id).join(', ')})` : ''}` })));
    }
    for (const m of path.hero) subs.appendChild(sub('mutation', m, `hero mutation · ${m.hero}`));
    for (const m of path.stance) subs.appendChild(sub('mutation', m, 'stance'));
    for (const m of path.extra || []) subs.appendChild(sub('mutation', m, `extra ${m.kind}`, 'a fourth path kind: the game picks the first of each'));
    art.appendChild(subs);
    return art;
  }
  function lineCard(l, fl) {
    const art = cardShell('passive', l, `card · ${l.max_level || 4} levels${l.play ? ' · look ' + l.play : ''}`);
    const evo = l.evolves_into ? fl.passives.find((p) => p.id === l.evolves_into) : null;
    const subs = el('div', { class: 'icard-sub' });
    if (evo) subs.appendChild(sub('passive', evo, 'evolved form', evo.evolves_from !== l.id ? `evolves_from ${evo.evolves_from}` : ''));
    else subs.appendChild(el('div', { class: 'isub muted small' }, el('span', { class: 'achip bad', text: 'no evolved form' }), el('span', { text: 'a card evolves when maxed: evolves_into names its evolved form' })));
    art.appendChild(subs);
    return art;
  }
  function passiveCard(p) { return cardShell('passive', p, `${p.max_level || 8} level${(p.max_level || 8) === 1 ? '' : 's'}${p.pairs_with ? ' · pairs with ' + p.pairs_with : ''}`); }
  function mutationCard(m, fl) {
    const w = fl.weapons.find((x) => x.id === m.weapon);
    const art = cardShell('mutation', m, `${m.kind || 'motion'} of ${w ? w.name : m.weapon}${m.hero ? ' · ' + m.hero : ''}`);
    if (m.text) art.appendChild(el('p', { class: 'doc', text: m.text }));
    return art;
  }
  function evolutionCard(e, fl) {
    const w = fl.weapons.find((x) => x.id === e.evolved_from);
    const current = w && w.evolves_into === e.id;
    const art = cardShell('evolution', e, `from ${w ? w.name : e.evolved_from}${w && !current ? ` (it evolves into ${w.evolves_into}: an alternate)` : ''}`);
    return art;
  }

  function redraw(doc, what) {
    if (what === 'all') { App.render('tab'); return; }
    if (!Assets.swapPane(doc, (pane) => editor(pane, doc))) App.render('tab');
    else if (listEl) for (const c of listEl.querySelectorAll('.icard')) { const d = Assets.S.docs[`${c.dataset.kind}:${c.dataset.id}`]; c.classList.toggle('editing', !!d && Assets.S.open.items === d.key); const dot = c.querySelector('.ccard-dirty'); if (dot) dot.hidden = !(d && Assets.docDirty(d)); }
  }

  // ------------------------------------------------------------------ the editors

  function editor(pane, doc) {
    const iss = Assets.issuesOf(doc);
    const kind = doc.kind;
    const defs = F.table(kind);
    pane.appendChild(Assets.header(doc, iss));
    const names = F.SECTIONS[kind] || [];
    const fl = Assets.flatItems();
    const behavior = kind === 'mutation' && fl ? ((fl.weapons.find((w) => w.id === doc.data.weapon) || {}).behavior || '') : '';
    for (const name of names) {
      let nodes = Assets.rows(doc, defs, name, iss, { behavior });
      const extra = [];
      if (kind === 'weapon' || kind === 'evolution') {
        if (name === 'Evolution & path' && !doc.data.is_evolution) extra.push(pathStrip(doc, iss));
        if (name === 'Availability' && !doc.data.is_evolution) { extra.push(questLock(doc, iss)); extra.push(bandGauge(doc)); }
        if (name === 'Params' && doc.data.is_evolution) extra.unshift(el('p', { class: 'muted small', text: 'params.final is merged after the mutations and dropped: the evolution\'s own extras live there.' }));
        if (name === 'Levels' && doc.data.is_evolution) extra.unshift(el('p', { class: 'muted small', text: 'An evolution has one level, applied at once: usually [[]], its numbers being its base and params.final; an effect there amplifies a mutation\'s stat (Slam Dunk: On Fire\'s burn × 1.5).' }));
        if (name === 'Base stats') nodes = [el('div', { class: 'basegrid' }, nodes)];
      }
      if (kind === 'passive' && name === 'Availability' && !doc.data.evolves_from) { extra.push(questLock(doc, iss)); extra.push(bandGauge(doc)); }
      if (kind === 'mutation' && name === 'Effect') extra.unshift(el('p', { class: 'muted small', text: `Params merge deep over ${doc.data.weapon || 'the weapon'}'s; the chips are ${behavior || 'the behaviour'}'s keys.` }));
      // pass 69 (lane LE): the item's finished icon candidate jobs, each picture installable (Rebound's three designs)
      if (name === 'Art' && typeof TypedForms !== 'undefined') { const ic = TypedForms.iconCandidates(doc); if (ic) extra.push(ic); }
      // pass 73 (lane CARDS): the card's looks (A the old icon, B-E the four framings), the one the game plays, its words
      if (name === 'Art' && kind === 'passive') { const lk = itemLooks(doc); if (lk) extra.unshift(lk); }
      // pass 76 (lane LOOKS): a weapon family's looks (the weapon plays one for all; a member says which it wears)
      if (name === 'Art' && (kind === 'weapon' || kind === 'evolution' || kind === 'mutation')) { const fk = familyLooks(doc); if (fk) extra.unshift(fk); }
      const all = nodes.concat(extra);
      if (!all.length) continue;
      const keys = Assets.sectionKeys(defs, name).concat(name === 'Evolution & path' ? ['path'] : name === 'Availability' ? ['band', 'quest_lock'] : []);
      pane.appendChild(Assets.section(doc, name, all, { open: ['Identity', 'Behaviour', 'Base stats', 'Levels', 'Evolution & path', 'Effect', 'Links', 'Text'].includes(name), marks: Assets.sectionMarks(iss, keys), foot: name === 'Behaviour' ? 'The behaviours are game/core/behaviors/*.gd: a new one needs code, ask Claude. The 3D visual (<id>_visual.tscn) is Claude\'s too.' : name === 'Levels' && kind !== 'passive' ? 'levels[i] = the effects gained reaching level i + 1 (target self: the weapon\'s own sheet); the card reads TextGen.describe_effect, mirrored in grey under each effect.' : null }));
    }
  }

  /** The weapon's path: one slot per kind with its mutation, the hero mutations, Create templates when a slot or the evolution is missing. */
  function pathStrip(doc, iss) {
    const fl = Assets.flatItems();
    const wrap = el('div', { class: 'pathwrap', 'data-key': 'path' });
    if (!fl) { wrap.appendChild(el('p', { class: 'muted small', text: 'the mutation list has not loaded' })); return wrap; }
    const path = M.pathOf(doc.id, fl.mutations);
    const strip = el('div', { class: 'pathstrip' });
    for (const k of ['element', 'volume', 'motion']) {
      const m = path[k];
      const slot = el('div', { class: 'pslot' + (m ? '' : ' empty') });
      slot.appendChild(el('div', { class: 'muted small', text: k }));
      if (m) {
        slot.appendChild(el('div', { class: 'isub' }, el('img', { src: icon('mutation', m.id), alt: '', onerror: (e) => { e.target.style.visibility = 'hidden'; } }), el('b', { text: m.name || m.id })));
        slot.appendChild(el('div', { class: 'small', text: m.text || '(no card text yet)' }));
        slot.appendChild(el('div', { class: 'alt-actions' }, el('button', { class: 'btn small', type: 'button', text: 'Edit', onclick: () => Assets.open('mutation', m.id) })));
      } else {
        const hid = path.hidden.filter((x) => x.kind === k);
        slot.appendChild(el('div', { class: 'small muted', text: hid.length ? `hidden: ${hid.map((x) => x.id).join(', ')} (fill it and unhide)` : 'none' }));
        for (const x of hid) slot.appendChild(el('div', { class: 'alt-actions' }, el('button', { class: 'btn small', type: 'button', text: `Edit ${x.id}`, onclick: () => Assets.open('mutation', x.id) })));
      }
      strip.appendChild(slot);
    }
    wrap.appendChild(strip);
    if (path.hero.length) wrap.appendChild(el('div', { class: 'hisown' }, path.hero.map((m) => el('div', { class: 'isub' }, el('img', { src: icon('mutation', m.id), alt: '' }), el('span', { class: 'achip hero', text: `hero mutation · ${m.hero}` }), el('b', { text: m.name || m.id }), el('span', { class: 'muted small', text: m.text || '' }), el('button', { class: 'btn small ghost', type: 'button', text: 'Edit', onclick: () => Assets.open('mutation', m.id) })))));
    const missing = ['element', 'volume', 'motion'].filter((k) => !path[k] && !path.hidden.some((x) => x.kind === k));
    const noEvo = !doc.data.evolves_into || !fl.evolutions.some((e) => e.id === doc.data.evolves_into);
    if (missing.length || noEvo) wrap.appendChild(el('div', { class: 'alt-actions' }, el('button', { class: 'btn small primary', type: 'button', text: 'Create templates', title: 'POST make_path: <id>_element, <id>_volume, <id>_motion and <id>_evolved, all hidden, placeholder icons', onclick: () => Assets.makePath(doc) }), el('span', { class: 'muted small', text: `${missing.length ? `missing ${missing.join(', ')}` : ''}${missing.length && noEvo ? ' and ' : ''}${noEvo ? 'no evolution' : ''}: the templates are created hidden for you to fill` })));
    Assets.markRow(wrap, iss, 'path');
    return wrap;
  }

  /** The quest whose unlocks names this item: its condition in words, Edit / Remove, or Add quest lock (through the availability op). */
  function questLock(doc, iss) {
    const fl = Assets.flatItems();
    const kind = doc.kind === 'passive' ? 'passive' : 'weapon';
    const wrap = el('div', { class: 'frow wide-ctl', 'data-key': 'quest_lock' });
    wrap.appendChild(el('label', { class: 'flabel', text: 'Unlock quest', title: 'a quest whose unlocks is {type: ' + kind + ', id: ' + doc.id + '}; the item is locked until it is done' }));
    const ctl = el('div', { class: 'fctl' });
    const q = fl ? M.questFor(doc.id, fl.quests, kind) : null;
    const draft = doc.ui.questDraft;
    const words = (qq) => { const c = M.isObj(qq.condition) ? qq.condition : {}; const t = F.VOCAB.questTypes.find((o) => o.v === c.type); const bits = ['count', 'enemy', 'weapon', 'map', 'stage', 'level', 'minutes', 'hero', 'kind', 'id', 'rung', 'item', 'source_kind', 'element', 'in_one_run'].filter((k) => c[k] != null && c[k] !== '' && c[k] !== false).map((k) => `${k} ${c[k]}`); return `${t ? t.label : c.type || '?'}${bits.length ? ' · ' + bits.join(', ') : ''}`; };
    if (q && !draft) {
      ctl.appendChild(el('div', { class: 'small' }, el('b', { text: q.name || q.id }), el('span', { text: ` · ${words(q)}` }), el('span', { class: 'muted small', text: ` (${q.id}${q.quest_text ? ': "' + q.quest_text + '"' : ''})` })));
      ctl.appendChild(el('div', { class: 'alt-actions' },
        el('button', { class: 'btn small', type: 'button', text: 'Edit quest', onclick: () => { doc.ui.questDraft = JSON.parse(JSON.stringify(q)); Assets.redraw(doc, 'editor'); } }),
        el('button', { class: 'btn small danger', type: 'button', text: 'Remove the lock', title: 'deletes the quest file: the item is available at once (the band moves)', onclick: () => { if (confirm(`Remove ${q.id}? ${doc.id} becomes available at once.`)) Assets.availabilityOp(doc, { availability: 'available' }); } })));
    } else if (!draft) {
      ctl.appendChild(el('div', { class: 'small muted', text: doc.data.hidden ? 'hidden: no quest needed' : 'none: available at once' }));
      ctl.appendChild(el('div', { class: 'alt-actions' }, el('button', { class: 'btn small', type: 'button', text: 'Add quest lock', onclick: () => { doc.ui.questDraft = { id: `unlock_${doc.id}`, name: String(doc.data.name || doc.id), condition: { type: 'kills_total', count: 400 }, unlocks: { type: kind, id: doc.id } }; Assets.redraw(doc, 'editor'); } })));
    }
    if (draft) {
      const box = el('div', { class: 'qdrawer' });
      box.appendChild(el('div', { class: 'small' }, el('b', { text: draft.id || `unlock_${doc.id}` }), el('span', { class: 'muted small', text: ` · content/quests/${draft.id || 'unlock_' + doc.id}/ (shape of unlock_adrenaline.json; written by the availability op)` })));
      const localApply = (fn) => { fn(); Assets.redraw(doc, 'editor'); };
      for (const def of F.QUEST_ROWS) {
        if (typeof def.only === 'function' && !def.only(draft)) continue;
        const def2 = Object.assign({}, def, { key: def.key });
        if (typeof def.options === 'function') def2.options = F.options(def, Assets.vocab());
        let rowEl;
        if (def.type === 'enemy') rowEl = Forms.row(def2, Forms.enemyPick(U.getPath(draft, def.key) || '', (v) => localApply(() => U.setPath(draft, def.key, v)), { path: 'quest.' + def.key, summary: false, emptyLabel: '—' }), {});
        else if (def.type === 'id_select') rowEl = Forms.row(def2, Forms.iconSelect(((def.kind === 'hero' ? Assets.ensureHeroes() : null), Assets.idOptions(def.kind || 'weapon')) || [], U.getPath(draft, def.key) || '', (v) => localApply(() => U.setPath(draft, def.key, v)), { emptyLabel: '—', path: 'quest.' + def.key }), {});
        else rowEl = Forms.fieldRow(def2, draft, { apply: (fn) => localApply(fn), pathPrefix: 'quest' });
        box.appendChild(rowEl);
      }
      // pass 113 (lane TASKS): the picture the game draws for the goal (tasks.js)
      if (typeof TaskPics !== 'undefined') box.appendChild(TaskPics.row(draft));
      box.appendChild(el('div', { class: 'alt-actions' },
        el('button', { class: 'btn small primary', type: 'button', text: q ? 'Save quest' : 'Create quest and lock', onclick: async () => { const ok = await Assets.availabilityOp(doc, { availability: 'locked', quest: draft }); if (ok) { doc.ui.questDraft = null; } } }),
        el('button', { class: 'btn small ghost', type: 'button', text: 'Cancel', onclick: () => { doc.ui.questDraft = null; Assets.redraw(doc, 'editor'); } })));
      ctl.appendChild(box);
    }
    wrap.appendChild(ctl);
    Assets.markRow(wrap, iss, 'quest_lock');
    return wrap;
  }

  /** The quest-locked share of base items as the lists stand (this document's unsaved hidden flag counted). */
  function bandGauge(doc) {
    const fl = Assets.flatItems();
    const wrap = el('div', { class: 'band', 'data-key': 'band' });
    if (!fl) return wrap;
    const ws = fl.weapons.map((w) => (doc && doc.kind === 'weapon' && w.id === doc.id ? Object.assign({}, w, { hidden: !!doc.data.hidden }) : w)).concat(doc && doc.kind === 'weapon' && !fl.weapons.some((w) => w.id === doc.id) ? [{ id: doc.id, hidden: !!doc.data.hidden }] : []);
    const ps = fl.passives.map((p) => (doc && doc.kind === 'passive' && p.id === doc.id ? Object.assign({}, p, { hidden: !!doc.data.hidden, evolves_from: doc.data.evolves_from }) : p)).concat(doc && doc.kind === 'passive' && !fl.passives.some((p) => p.id === doc.id) ? [{ id: doc.id, hidden: !!doc.data.hidden, evolves_from: doc.data.evolves_from }] : []);
    const b = M.bandOf(ws, ps, fl.quests);
    const srv = Assets.S.lists.items && Assets.S.lists.items.band;
    const pct = Math.round(b.share * 100);
    const inside = b.share >= b.lo && b.share <= b.hi;
    const bar = el('div', { class: 'band-bar' }, el('div', { class: 'band-ok', style: `left:${b.lo * 100}%;width:${(b.hi - b.lo) * 100}%` }), el('div', { class: 'band-mark' + (inside ? '' : ' bad'), style: `left:calc(${pct}% - 1px)`, title: `${pct}%` }));
    wrap.appendChild(bar);
    wrap.appendChild(el('div', { class: 'small ' + (inside ? 'muted' : ''), style: inside ? '' : 'color: var(--warn)', text: `Quest-locked base items ${b.locked} of ${b.base} = ${pct}% (the ship test pass44_test wants ${Math.round(b.lo * 100)}-${Math.round(b.hi * 100)}%${srv && srv.share != null && Math.round(srv.share * 100) !== pct ? `; the server counts ${Math.round(srv.share * 100)}%` : ''}).${inside ? '' : ' Outside the band the ship test fails: add a quest lock, or ask Claude to widen the band.'}` }));
    return wrap;
  }

  // ------------------------------------------------------------------ pass 73 (lane CARDS): the cards' looks

  /** "Set every card to look X" (Garry): a button per look any card has painted, with how many cards have it; a card
   *  without that look keeps its own (the server says which). One import for all. Says so when the server is older than
   *  the item looks (the records carry no `looks`): a restart of the editor loads them. */
  function cardLooksBar(fl) {
    const cards = fl.passives.filter((p) => p.line);
    const wrap = el('div', { class: 'cardlooks' });
    if (!cards.some((p) => Array.isArray(p.looks))) {
      wrap.appendChild(el('p', { class: 'muted small', text: 'The cards have looks (A the icons before the cards, B-E the four card framings): this Level Editor was started before they existed, so close it and open it again to pick them here.' }));
      return wrap;
    }
    const have = {}, plays = {};
    for (const p of cards) {
      for (const l of p.looks || []) if (l.exists && !l.shelved) have[l.code] = (have[l.code] || 0) + 1;
      if (p.play) plays[p.play] = (plays[p.play] || 0) + 1;
    }
    const codes = Object.keys(have).sort();
    if (codes.length < 2) return null;
    wrap.appendChild(el('span', { class: 'muted small', text: 'Set every card to look' }));
    for (const c of codes) wrap.appendChild(el('button', { class: 'btn small', type: 'button', text: `${c} · ${have[c]}/${cards.length}`, title: `every card with look ${c} painted plays it (its JSON's variant), the rest keep theirs; one import`, onclick: () => setAllCards(c, cards.length) }));
    wrap.appendChild(el('span', { class: 'muted small', text: 'playing now: ' + Object.keys(plays).sort().map((c) => `${c} ×${plays[c]}`).join(' · ') }));
    return wrap;
  }
  async function setAllCards(code, total) {
    if (!confirm(`Every card that has look ${code} plays it from now on (its JSON's variant, then one import). Go on?`)) return;
    App.status(`Setting every card to look ${code}…`, 'busy');
    const { status, data } = await Assets.postJSON('/api/item_looks/set_all', { kind: 'passive', code });
    if (status === 404) { App.status('This Level Editor was started before the cards had looks: close it and open it again', 'bad'); return; }
    if (!data.ok) { App.status(`Could not set the cards to ${code}: ${data.error || status}`, 'bad'); return; }
    const skipped = data.skipped || [];
    App.toast(`${(data.changed || []).length} of ${total} cards now play ${code}${(data.kept || []).length ? `, ${data.kept.length} already did` : ''}${skipped.length ? `; kept their own: ${skipped.map((x) => `${x.id} (${x.why})`).join(', ')}` : ''}${data.import_ok === false ? ' · the import did not run: ' + (data.output || '') : ''}`);
    for (const d of Object.values(Assets.S.docs)) if (d.kind === 'passive') await Assets.refreshRecord('passive', d.id);
    await Assets.refreshList('items');
    App.render('tab');
  }

  /** A card's looks in its editor (Art): each look's icon on the card's plate at 112 px and at the HUD's 48, its code and
   *  note, PLAYS on the one the game plays, "Play this look" (its JSON's variant, then an import), Show (the icon preview
   *  and "+ Icon candidates" follow the look shown: a repaint lands in that look) and the words it was painted from. */
  function itemLooks(doc) {
    const looks = Array.isArray(doc.looks) ? doc.looks : [];
    const vs = doc.data && doc.data.variants;
    if (!looks.length) {
      if (M.isObj(vs) && Object.keys(vs).length) return el('p', { class: 'muted small', 'data-key': 'variants', text: 'This card has looks in its JSON, but this Level Editor was started before items had looks: close it and open it again to see and pick them.' });
      return null;
    }
    const playing = (looks.find((l) => l.default) || {}).code || '';
    const wrap = el('div', { class: 'ilooks', 'data-key': 'variants' });
    wrap.appendChild(el('div', { class: 'muted small', text: `Looks: the game plays ${playing || 'its own icon'} (the JSON's variant). On the phone the arena's ITEMS tab shows every card in any look (Card look).` }));
    const grid = el('div', { class: 'ilooks-grid' });
    const hide = (e) => { e.target.style.visibility = 'hidden'; };
    for (const l of looks) {
      const shown = doc.ui.look === l.code;
      const url = `${l.icon}?v=${doc.baseMtime || 0}`;
      const tile = el('figure', { class: 'ilook' + (l.default ? ' plays' : '') + (shown ? ' shown' : '') + (l.exists ? '' : ' missing') });
      tile.appendChild(el('div', { class: 'ilook-plates' },
        el('div', { class: 'iconplate', style: `width:112px;height:112px;background:${plate(doc.data.rarity)}` }, el('img', { src: url, alt: '', width: 112, height: 112, onerror: hide })),
        el('div', { class: 'iconplate', style: `width:48px;height:48px;background:${plate(doc.data.rarity)}` }, el('img', { src: url, alt: '', width: 48, height: 48, onerror: hide }))));
      tile.appendChild(el('figcaption', {}, el('b', { text: l.code }), l.default ? el('span', { class: 'achip good', text: 'plays' }) : null,
        l.shelved ? el('span', { class: 'achip hidden', text: 'shelved' }) : null, !l.exists ? el('span', { class: 'achip bad', text: 'not painted' }) : null,
        el('div', { class: 'muted small', text: l.note || (l.base ? 'the icon before the cards' : '') })));
      const acts = el('div', { class: 'alt-actions' });
      if (!l.default) acts.appendChild(el('button', { class: 'btn small primary', type: 'button', text: 'Play this look', disabled: !l.exists, title: l.exists ? 'writes this card\'s variant and imports it' : 'its icon is not painted yet', onclick: () => playLook(doc, l.code) }));
      acts.appendChild(el('button', { class: 'btn small ghost', type: 'button', text: shown ? 'Shown above' : 'Show', title: 'the icon preview and "+ Icon candidates" follow the look shown', onclick: () => { doc.ui.look = shown ? null : l.code; Assets.redraw(doc, 'editor'); } }));
      tile.appendChild(acts);
      const r = M.isObj(l.recipe) ? l.recipe : null;
      if (r) tile.appendChild(el('details', { class: 'small' }, el('summary', { text: 'painted from' }), el('pre', { class: 'recipe-words', text: [r.subject ? 'subject: ' + r.subject : '', r.style ? 'style: ' + r.style : '', r.screen ? 'screen: ' + r.screen : '', l.painted ? 'pick: ' + JSON.stringify(l.painted) : ''].filter(Boolean).join('\n\n') })));
      grid.appendChild(tile);
    }
    wrap.appendChild(grid);
    return wrap;
  }
  async function playLook(doc, code) {
    if (Assets.docDirty(doc) && !confirm(`${doc.id} has unsaved changes. Playing look ${code} writes only its variant line; your other edits stay unsaved. Go on?`)) return;
    App.status(`${doc.id} plays ${code}…`, 'busy');
    const { status, data } = await Assets.postJSON(`/api/content/passive/${encodeURIComponent(doc.id)}/variant`, { code });
    if (!data.ok) { App.status(`${doc.id}: ${data.error || status}`, 'bad'); return; }
    App.toast(`${doc.id} plays ${code}${data.import_ok === false ? ' · the import did not run: ' + (data.output || '') : ''}`);
    await Assets.refreshRecord('passive', doc.id);
    await Assets.refreshList('items');
    App.render('tab');
  }

  // ------------------------------------------------------------------ pass 76 (lane LOOKS): a weapon family's looks

  /** A weapon family's looks (Garry: the Grenade as a Dynamite Stick "as a Look (with several candidates), so I can switch
   *  back to the grenade"). In the weapon's editor: per look of the weapon its icon on the plate (112 and 48), its code and
   *  name, PLAYS on the one the family plays (the weapon's `variant`), its members in that look (their icons; faint where a
   *  member has no entry for it and wears its base), the note, Play this look (the weapon's variant, then an import) and
   *  Show (the icon preview and "+ Icon candidates" follow the look shown). In an evolution's or a mutation's editor: the
   *  look its family plays, the one it wears, its own looks with Show, and a way to its weapon. */
  function familyLooks(doc) {
    const rec = Assets.listRecord(doc) || {};
    const hide = (e) => { e.target.style.visibility = 'hidden'; };
    const v = `?v=${doc.baseMtime || 0}`;
    const pl = (px, url) => el('div', { class: 'iconplate', style: `width:${px}px;height:${px}px;background:${plate(doc.data.rarity)}` }, el('img', { src: url, alt: '', width: px, height: px, onerror: hide }));
    const looks = Array.isArray(doc.looks) ? doc.looks : [];
    if (M.isObj(doc.data.variants) && Object.keys(doc.data.variants).length && !looks.length) {
      return el('p', { class: 'muted small', 'data-key': 'variants', text: 'This item has looks in its JSON, but this Level Editor was started before weapons had looks: close it and open it again to see and pick them.' });
    }
    if (doc.kind === 'weapon') {
      const fls = Array.isArray(rec.family_looks) ? rec.family_looks : [];
      if (fls.length < 2) return null;
      const playing = (fls.find((l) => l.default) || {}).code || '';
      const wrap = el('div', { class: 'ilooks', 'data-key': 'variants' });
      wrap.appendChild(el('div', { class: 'muted small', text: `Looks of the whole family: the game plays ${playing} (this weapon's variant), its mutations and its evolution with it. On the phone the arena's ITEMS tab switches the family's look (Weapon looks). A look changes names, words, icons and drawing params, never the rules.` }));
      const grid = el('div', { class: 'ilooks-grid' });
      for (const l of fls) {
        const shown = doc.ui.look === l.code;
        const tile = el('figure', { class: 'ilook' + (l.default ? ' plays' : '') + (shown ? ' shown' : '') + (l.exists ? '' : ' missing'), 'data-look': l.code });
        tile.appendChild(el('div', { class: 'ilook-plates' }, pl(112, l.icon + v), pl(48, l.icon + v)));
        tile.appendChild(el('figcaption', {}, el('b', { text: `${l.code} · ${l.name}` }), l.default ? el('span', { class: 'achip good', text: 'plays' }) : null,
          l.shelved ? el('span', { class: 'achip hidden', text: 'shelved' }) : null, l.fresh ? el('span', { class: 'achip', text: 'unreviewed' }) : null,
          !l.exists ? el('span', { class: 'achip bad', text: 'files missing' }) : null,
          el('div', { class: 'muted small', text: l.note || (l.base ? 'the top level' : '') })));
        const mem = el('div', { class: 'flook-members', style: 'display:flex;flex-wrap:wrap;gap:4px;margin:6px 0' });
        for (const m of l.members || []) {
          mem.appendChild(el('img', { src: m.icon + v, alt: '', width: 40, height: 40, onerror: hide,
            style: `width:40px;height:40px;border-radius:6px;background:${plate(doc.data.rarity)};${m.own || l.base ? '' : 'opacity:0.45;'}${m.hidden ? 'filter:grayscale(1);' : ''}`,
            title: `${m.role} · ${m.name}${m.own || l.base ? '' : ` (no ${l.code} of its own: its base)`}${m.hidden ? ' · hidden' : ''}` }));
        }
        tile.appendChild(mem);
        const acts = el('div', { class: 'alt-actions' });
        if (!l.default) acts.appendChild(el('button', { class: 'btn small primary', type: 'button', text: 'Play this look', disabled: !l.exists, title: l.exists ? 'writes this weapon\'s variant (its whole family plays it) and imports it' : 'a file its entry names is not on disk yet', onclick: () => playFamilyLook(doc, l.code) }));
        acts.appendChild(el('button', { class: 'btn small ghost', type: 'button', text: shown ? 'Shown above' : 'Show', title: 'the icon preview and "+ Icon candidates" follow the look shown', onclick: () => { doc.ui.look = shown ? null : l.code; Assets.redraw(doc, 'editor'); } }));
        tile.appendChild(acts);
        grid.appendChild(tile);
      }
      wrap.appendChild(grid);
      return wrap;
    }
    // an evolution or a mutation: it wears its weapon's look (its base when it has none of that code)
    const fam = rec.family || '';
    const fl = Assets.flatItems();
    const wrec = fam && fl ? fl.weapons.find((w) => w.id === fam) : null;
    const famLooks = wrec && Array.isArray(wrec.family_looks) ? wrec.family_looks : [];
    if (!looks.length && famLooks.length < 2) return null;
    const wears = (looks.find((l) => l.default) || {}).code || '';
    const wrap = el('div', { class: 'ilooks', 'data-key': 'variants' });
    const famText = wrec ? `${wrec.name_play || wrec.name} (${fam}) plays ${wrec.play || 'its top level'}` : 'its weapon plays one look for the family';
    const mine = looks.length ? `wears ${wears}${wrec && wrec.play && wrec.play !== wears ? ` (it has no ${wrec.play} of its own: its base)` : ''}` : 'has no looks of its own and wears its top level in every look';
    wrap.appendChild(el('div', { class: 'muted small', text: `Its weapon family's look: ${famText}; this ${doc.kind} ${mine}. The look is played on the weapon.` }));
    if (fam) wrap.appendChild(el('div', { class: 'alt-actions' }, el('button', { class: 'btn small', type: 'button', text: `Open ${fam}`, onclick: () => Assets.open('weapon', fam) })));
    if (!looks.length) return wrap;
    const grid = el('div', { class: 'ilooks-grid' });
    for (const l of looks) {
      const shown = doc.ui.look === l.code;
      const tile = el('figure', { class: 'ilook' + (l.default ? ' plays' : '') + (shown ? ' shown' : '') + (l.exists ? '' : ' missing'), 'data-look': l.code });
      tile.appendChild(el('div', { class: 'ilook-plates' }, pl(112, l.icon + v), pl(48, l.icon + v)));
      tile.appendChild(el('figcaption', {}, el('b', { text: `${l.code} · ${l.name || doc.data.name || doc.id}` }), l.default ? el('span', { class: 'achip good', text: 'wears' }) : null,
        l.shelved ? el('span', { class: 'achip hidden', text: 'shelved' }) : null, l.fresh ? el('span', { class: 'achip', text: 'unreviewed' }) : null,
        !l.exists ? el('span', { class: 'achip bad', text: 'files missing' }) : null, el('div', { class: 'muted small', text: l.note || (l.base ? 'the top level' : '') })));
      tile.appendChild(el('div', { class: 'alt-actions' }, el('button', { class: 'btn small ghost', type: 'button', text: shown ? 'Shown above' : 'Show', title: 'the icon preview and "+ Icon candidates" follow the look shown', onclick: () => { doc.ui.look = shown ? null : l.code; Assets.redraw(doc, 'editor'); } })));
      grid.appendChild(tile);
    }
    wrap.appendChild(grid);
    return wrap;
  }
  async function playFamilyLook(doc, code) {
    if (Assets.docDirty(doc) && !confirm(`${doc.id} has unsaved changes. Playing look ${code} writes only its variant line; your other edits stay unsaved. Go on?`)) return;
    App.status(`${doc.id}'s family plays ${code}…`, 'busy');
    const { status, data } = await Assets.postJSON(`/api/content/weapon/${encodeURIComponent(doc.id)}/variant`, { code });
    if (!data.ok) { App.status(`${doc.id}: ${data.error || status}`, 'bad'); return; }
    App.toast(`${doc.id} and its family play ${code}${data.import_ok === false ? ' · the import did not run: ' + (data.output || '') : ''}`);
    await Assets.refreshRecord('weapon', doc.id);
    await Assets.refreshList('items');
    App.render('tab');
  }

  return { render, redraw, weaponCard, pathStrip, questLock, bandGauge, cardLooksBar, itemLooks, setAllCards, playLook, familyLooks, playFamilyLook };
})();
